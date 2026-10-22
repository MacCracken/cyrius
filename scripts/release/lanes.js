export const meta = {
  name: 'lanes',
  description: 'cyrius release lanes (one wave per run): per lane, implement its units in order in its worktree, one review round, one fix step + the lane gate',
  phases: [{ title: 'Implement' }, { title: 'Review' }, { title: 'Fix + gate' }],
}
// scripts/release/lanes.js — the lanes of one wave of a cyrius release, for Claude Code's Workflow
// tool. Per lane, in parallel: one agent per unit implements its brief in the lane's worktree
// (commits, handoff, staged issue files), then ONE read-only review round over the lane's bites,
// then ONE fix step that applies the review's must-fix items, stages the rest as issue files and
// runs the lane gate (fixpoint, seed-derive, check.sh, the per-file loop).
// (meta stays the first statement: the Workflow tool requires it there, as a pure literal.)
//
// usage:   the Workflow tool, with this file as scriptPath and the args below; one run per wave.
// args:    {
//   c6:   '<abs dir>',            the release scratch dir: <tag>_briefs/, <tag>_handoff_<lane>.md,
//                                 <tag>_staging/<lane>/, s<tag>/<lane>/<unit>/ (agent scratch)
//   repo: '<abs dir>',            the main checkout (the lanes never touch it)
//   ver:  'X.Y.Z',
//   rel:  '<one line>',           what the release is ("Break N, repair M — what X.Y.W filed")
//   decisions: { count: N, date: 'YYYY-MM-DD', file: '<abs path>' },   the user's answers
//   known_skips: ['<gate>', ...], the SKIPs this release expects in check.sh ([] when none)
//   coauthor: 'Co-Authored-By: <name> <email>',   the commit trailer line
//   hosts: ['ecb macOS arm64', ...],   the verification hosts, by ~/.ssh/config alias + what each is
//   lanes: [{ name, wt: '<abs worktree>', base: '<sha or branch the lane was cut from>',
//             units: ['G1', ...], heap: true? (the lane carries a heap-layout bite),
//             notes: { '<unit>': '<text>' }? (a resumed run: what that unit already committed or left
//                                             uncommitted in the worktree, put in its agent's prompt) }]
// }
// inputs:  <c6>/<tag>_briefs/<lane>_<unit>.md (programs/release/briefs.cyr), decisions.file, the
//          issue files in each worktree. <tag> = ver without dots.
// outputs: commits on each lane branch l<tag>-<lane>; <c6>/<tag>_handoff_<lane>.md (appended);
//          <c6>/<tag>_staging/<lane>/*.md (issue files for integration to place); the return value
//          [{ lane, units: [{unit, commits, blocked, staged, notes}], review, fix }].
//
// converted to cyrius later: docs/development/issues/archived/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
// (a Workflow script has no cyrius form; that issue records the choice for it.)
const need = (v, what) => { if (v === undefined || v === null || v === '') throw new Error(`lanes.js: args.${what} is required`); return v }
const C6 = need(args.c6, 'c6')
const REPO = need(args.repo, 'repo')
const VER = need(args.ver, 'ver')
const REL = need(args.rel, 'rel')
const DEC = need(args.decisions, 'decisions')
const COAUTHOR = need(args.coauthor, 'coauthor')
const HOSTS = need(args.hosts, 'hosts')
const SKIPS = args.known_skips || []
need(args.lanes, 'lanes')
const TAG = VER.replace(/\./g, '')
const SKIPS_TXT = SKIPS.length ? SKIPS.join(', ') : 'none'
const NO_RULES = 'Never edit any CLAUDE.md or rules file (in any repo); report a stale rule line instead.'
const COMMIT = { type: 'object', properties: { sha: { type: 'string' }, issue: { type: 'string' }, summary: { type: 'string' } }, required: ['sha', 'issue', 'summary'] }
const BLOCKED = { type: 'object', properties: { issue: { type: 'string' }, why: { type: 'string' } }, required: ['issue', 'why'] }
const UNIT_RES = {
  type: 'object',
  properties: {
    commits: { type: 'array', items: COMMIT },
    blocked: { type: 'array', items: BLOCKED },
    staged: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['commits', 'blocked', 'staged', 'notes'],
}
const REVIEW_RES = {
  type: 'object',
  properties: {
    verdicts: { type: 'array', items: { type: 'object', properties: { issue: { type: 'string' }, ok: { type: 'boolean' }, note: { type: 'string' } }, required: ['issue', 'ok', 'note'] } },
    must_fix: { type: 'array', items: { type: 'object', properties: { issue: { type: 'string' }, defect: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' } }, required: ['issue', 'defect', 'evidence', 'fix'] } },
    file_as_issue: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, evidence: { type: 'string' }, severity: { type: 'string' } }, required: ['title', 'evidence', 'severity'] } },
  },
  required: ['verdicts', 'must_fix', 'file_as_issue'],
}
const FIX_RES = {
  type: 'object',
  properties: {
    fixed: { type: 'array', items: { type: 'string' } },
    not_fixed: { type: 'array', items: { type: 'string' } },
    staged: { type: 'array', items: { type: 'string' } },
    seed_derive: { type: 'string' },
    check_summary: { type: 'string' },
    lane_status: { type: 'string', enum: ['GREEN', 'RED'] },
    head: { type: 'string' },
    notes: { type: 'string' },
  },
  required: ['fixed', 'not_fixed', 'staged', 'seed_derive', 'check_summary', 'lane_status', 'head', 'notes'],
}

function rules(l, scr) {
  return `THE USER'S STANDING RULES (hard — violating any is a failure of the task):
- ${NO_RULES} Never push or tag. Never run install.sh, version-bump.sh, \`cyrius pulsar\`, or anything that writes ~/.cyrius. No \`git stash\`. Never \`git add -A\` / \`git add .\`: stage named paths only.
- Work ONLY inside your worktree ${l.wt} (branch l${TAG}-${l.name}, cut from ${l.base}); cd there for every command. Never touch the main tree ${REPO} or another lane's worktree.
- Fix each issue COMPLETELY, with the user's decided answer (in the brief — final, never re-ask, never re-decide). A filed repro is the spec: the reporter's verbatim case must give the decided result; never edit it to fit. COMPLETE means the whole defect class: every other shape with the same root cause that your fix's functions handle (another spelling, position, target or type of the same thing) is fixed in the same bite, with its rows — never stage a sibling shape for later. Do not go looking for other bugs (fixing is not hunting) — but ANY defect you MEET while working, High or Low (a crash, a wrong value, a message's wording, an error cascade, accepted bad syntax, a gate's hygiene), you FIX, in its own commit with its row: fixing it costs less than filing it (CLAUDE.md: a find repairable faster than its issue could be written IS repaired when found; the user, 2026-10-20: "IF YOU FIX A HIGH AND A LOW APPEARS FUCKING FIX THE LOW TOO"). Two exceptions, each one line under blocked with its repro, never an issue file: a fix that would change what compiles or what a valid program computes beyond the user's decided answers (the user decides; the session asks), and a repair that is genuinely a day or more of work (the session folds it into this release). Never write issue files, never stage anything, never defer. Never ask the user anything.
- Do not open, grep or survey consumer repos (the one exception a brief names explicitly: a consumer-FILED issue's own repro). Do not edit a vendored fold (lib/<fold>.cyr for the folds in docs/ecosystem.md) in place — a fold defect is filed.
- export TMPDIR=${scr}/tmp (mkdir -p it first): /tmp's per-user quota is shared with other sessions. Scratch and probes under ${scr}.
- Stop a process you started by its PID only — never pkill / killall / pgrep -f a name or pattern (it hits other sessions' processes).
- The real hosts are available over ssh by their ~/.ssh/config aliases (${HOSTS.join(', ')}); each host's traps (cass: the Defender-excluded directory, reading exit codes) are in CLAUDE.md § Verification habits. Copy probes to a scratch dir you create there and remove it when done. Never write into a host's ~/.cyrius. The ARM native compiler for pi comes from your tree (cat src/main_aarch64_native.cyr | ./build/cycc_aarch64 > scratch, after building build/cycc_aarch64 from your tree) — never cyrius pulsar (integration runs it).

HOW TO BUILD AND TEST HERE (this repo's traps):
- Build test compilers from your tree, fixpoint-checked: cat src/main.cyr | ./build/cycc > ${scr}/c1 && chmod +x ${scr}/c1 && cat src/main.cyr | ${scr}/c1 > ${scr}/c2 && chmod +x ${scr}/c2 && cat src/main.cyr | ${scr}/c2 > ${scr}/c3 && cmp ${scr}/c2 ${scr}/c3. Install it into the worktree (gates and seed-derive read build/cycc): cp ${scr}/c2 build/cycc.new && mv -f build/cycc.new build/cycc. NEVER commit anything under build/ (integration rebuilds build/cycc and the ARM binary once)${l.heap ? ' — EXCEPT this lane\'s heap-layout bite, which the brief says how to land (the two-step bootstrap)' : ''}.
- Cross compilers from your tree when a target matters (temp file + mv -f, never cp over a busy binary): src/main_aarch64.cyr -> build/cycc_aarch64 (run outputs with qemu-aarch64); src/main_cx.cyr -> build/cycc_cx and programs/cxvm.cyr -> build/cxvm; src/main_win.cyr -> build/cycc_win_cross (emits PE from Linux; run with wine in a PRIVATE WINEPREFIX under your scratch, its wineserver stopped when done). Each is \`cat <src> | ./build/cycc > tmp && mv -f tmp <out>\`.
- Probes: from ${l.wt}, cat ${scr}/p.cyr | ./build/cycc > ${scr}/p 2> ${scr}/p.err (so include "lib/x.cyr" resolves). ALWAYS check the compile rc and stderr before reading a probe's exit code: an empty output file runs as an empty shell script and exits 0. Never a bare \`cyrius build\` in the repo (its manifest output can overwrite build/cycc). The CLI is ./build/cyrius (rebuild it from cbt/ if you change cbt/ or a lib/ file it includes: see how scripts/check.sh or the gates build it).
- ANY change under src/ or bootstrap/: \`sh scripts/seed-derive-cycc.sh\` must pass, run after build/cycc is the fixpoint of your src. cybs compiles src/: keep new code to constructs cybs has (no const, loop, do/while, if-expression, unary minus, >>>, >>=), and add small helper fns rather than growing a fn near cybs's per-fn reference ceiling.
- Run the gates you touch and those the brief names (sh tests/gates/<bucket>/<gate>.sh), the affected .tcyr, on every target the brief names (qemu-aarch64, cxvm, wine). Behaviour a user sees on hardware gets a tests/tcyr/crossos/ row. A frame-layout or codegen row needs a TIGHT caller (a caller with locals of its own pads the frame and hides it). A new gate under tests/gates/<bucket>/ is wired the way its neighbours are (read scripts/check.sh and programs/checks/main.cyr: \`_chk_gate "$ROOT/tests/gates/..."\` lines) and carries a mutation: show it goes RED with the fix reverted. A .tcyr ends with \`var r = assert_summary();\` and never defines \`fn main\` (a source defining main exits with main's result; tcyr_epilogue_shape.sh refuses it).
- A changed or newly refused behaviour updates the guide (docs/guides/cyrius-guide.md) where it documents the shape. Source comments keep the WHY plus a one-line \`CHANGELOG [${VER}]\` pointer, not history. Decision ids from an earlier release are named with it ("X.Y.Z's D19").
- Adding a public lib/ fn trips lint, \`cyrius_api_surface --update\` (docs/api-surface.snapshot) and doc --check (a doc comment on EACH fn).`
}

const IMPL = (l, u) => {
  const scr = `${C6}/s${TAG}/${l.name}/${u}`
  return `You implement ONE unit of cyrius ${VER} (${REL}): lane ${l.name}, unit ${u}.
Your brief: ${C6}/${TAG}_briefs/${l.name}_${u}.md — read it first: the issues, the triage evidence, the USER DECISIONS (final; all ${DEC.count} with their questions and answers are in ${DEC.file}) and a fix plan whose line numbers you must re-verify against the current code (earlier units of this lane may have moved them; read \`git log --oneline ${l.base}..HEAD\` and ${C6}/${TAG}_handoff_${l.name}.md for what this lane already did).
Read each issue file in docs/development/issues/ fully before coding.
${l.notes && l.notes[u] ? `
THIS UNIT WAS STARTED BY AN EARLIER RUN THAT STOPPED PART-WAY (verify each claim against git log, git status and git diff in the worktree before building on it): ${l.notes[u]}
` : ''}
${rules(l, scr)}

COMMITS: one commit per issue (or per decision item when one issue carries several), each with its regression rows; message "${VER} ${l.name}: <what changed> (issues/<file>.md)", then a blank line and "${COAUTHOR}". Do not move or edit the issue files themselves (integration archives them).

HANDOFF: APPEND (never overwrite) a "## Unit ${u}" section to ${C6}/${TAG}_handoff_${l.name}.md: per issue — the commit sha; what changed; the rows; the measured before/after on each target; the decision applied; a CHANGELOG bullet (the shape, the old and the new behaviour, the user's decision (D#, ${VER}'s) with its date ${DEC.date} where one applied); an ecosystem-migration note when code that compiled now behaves differently or stops compiling; a vidya note when the issue is a gotcha worth recording; the staged issue files.

If an issue cannot be done as decided (a genuine impossibility, not difficulty), stop that issue, leave the tree clean and committed, and report it under blocked with the evidence — never improvise new semantics.`
}

const REVIEW = (l) => {
  const scr = `${C6}/s${TAG}/${l.name}/review`
  return `You review lane ${l.name} of cyrius ${VER} — ONE review round. Read-only: you may build probes and run tests, but you edit no file in the worktree and commit nothing.
Worktree ${l.wt} (branch l${TAG}-${l.name}). THE BITES UNDER REVIEW: git log --oneline ${l.base}..HEAD; git diff ${l.base}..HEAD. Briefs: ${C6}/${TAG}_briefs/${l.name}_*.md (the issues, the user's final decisions, the plans). Handoff: ${C6}/${TAG}_handoff_${l.name}.md.
export TMPDIR=${scr}/tmp (mkdir -p). Probes under ${scr}/rev. ${NO_RULES} Stop processes by PID only. Check a probe's compile rc before reading its exit code.
Review THE BITES, not the codebase:
1. Per issue: run its filed repro VERBATIM (docs/development/issues/<file>) with the lane's compiler (./build/cycc, plus the cross compilers the issue's targets need, rebuilt from the lane tree) → the decided result? Does the fix cover the issue's FILED surface (every shape the issue file lists) and the decision as worded — no more, no less?
2. Regressions the bites could cause: run the gates and .tcyr the lane touched or that cover the changed functions (grep tests/ for the fn names), and seed-derive (sh scripts/seed-derive-cycc.sh) when src/ or bootstrap/ changed (first check build/cycc is the fixpoint: cat src/main.cyr | ./build/cycc | cmp - build/cycc). Do NOT run the full check.sh (the fix step does).
3. The diff: wrong-target code (x86 encodings on aarch64 / cx / PE paths, SysV on Win64), a missed PE / cx / aarch64 / Mach-O arm, off-by-ones, silently ignored errors, a transient frame slot not recorded in the frame high-water, a gate that cannot fail (try its mutation), a new gate not wired into check.sh / the driver, a .tcyr defining fn main, a comment without the WHY, guide text that disagrees with the new behaviour, a CHANGELOG bullet in the handoff that misstates what changed.
must_fix = defects IN the bites: a filed repro not giving the decided result, a regression the lane caused, a broken or unwired gate, a row the issue's acceptance names but the lane lacks, a wrong-target emission, AND a sibling shape of the same root cause in the functions the bite changed that is left unfixed (the class is fixed whole). Give evidence and the exact fix. file_as_issue = ONLY a defect the bites neither caused nor touch AND that the fix step cannot repair in under an hour, or one whose fix changes what compiles / computes beyond the decided answers (one entry each, with its repro) — everything else you find (wording, cascades, sibling shapes, a missing row, a stale comment) goes in must_fix, to be FIXED by the fix step (the user, 2026-10-20: fix the Low too). Never ask the user anything.`
}

const FIX = (l, rv) => {
  const scr = `${C6}/s${TAG}/${l.name}/fix`
  return `You are the ONE fix step for lane ${l.name} of cyrius ${VER}, then you run the lane gate.
Review result: (JSON) ${JSON.stringify(rv)}

${rules(l, scr)}

1. Apply every must_fix item: each its own commit with its row ("${VER} ${l.name}: review fix — <what>" + the "${COAUTHOR}" line). Read the sibling paths first so the fix is right the first time — there is no second review.
2. Then write each file_as_issue item (only the day-plus repairs and the changes needing the user's decision — nothing that a commit here could fix) as an issue file into ${C6}/${TAG}_staging/${l.name}/ (the issues/ format; **Placement:** ${VER} — found by the ${VER} ${l.name} review; every find stays in this release, integration assigns its unit — never 7.x.; include the evidence as a repro — only a crash, miscompile or silent wrong value is ever written here). First \`ls ${C6}/${TAG}_staging/${l.name}/\`: an item already staged there is not staged twice.
3. The lane gate, in order: build/cycc = the fixpoint of the lane's src (cmp); if src/ or bootstrap/ changed: sh scripts/seed-derive-cycc.sh; then EVERY gate the lane's bites touch or that covers a changed function (each tests/gates/<bucket>/<gate>.sh the lane edited or added, and the gates \`grep -rl\` finds naming each fn the lane changed) — run each alone, under sh AND bash -eo pipefail. Do NOT run the full scripts/check.sh: the lanes of a wave run in parallel and N full suites on one box thrash it (6.7.17 wave 1: eight at once, load 76 on 16 cores, each 60-95 min where one alone takes ~12); the integration runs the ONE full check.sh on the merged tree. A TIMING gate red under load: rerun it alone — green alone = environmental (say so in notes). Anything else red is real. Then a per-file exit-code loop over every .tcyr the lane added or changed, on every target the lane touched (check.sh's summary can mask a .tcyr exit failure).
   A failure the lane caused: fix it (its own commit) and rerun the failing gates, then the suite once more. A failure that is pre-existing or environmental: PROVE it (run the same gate in a scratch copy of the lane base: git -C ${l.wt} archive ${l.base} | tar -x -C ${scr}/base, with the base's build/ tools copied in) and stage an issue; say so in notes.
4. Append a "## Review fixes and lane gate" section to ${C6}/${TAG}_handoff_${l.name}.md (the fixes with shas and CHANGELOG bullets, the staged issues, the check.sh summary line, seed-derive).
Report lane_status GREEN only when every gate you ran is green and seed-derive passes where required; head = the lane branch's final sha.`
}

const runLane = async (l) => {
  const units = []
  for (const u of l.units) {
    const r = await agent(IMPL(l, u), { label: `impl:${l.name}:${u}`, phase: 'Implement', schema: UNIT_RES })
    units.push({ unit: u, ...(r || { commits: [], blocked: [{ issue: u, why: 'agent returned nothing' }], staged: [], notes: '' }) })
  }
  const review = await agent(REVIEW(l), { label: `review:${l.name}`, phase: 'Review', schema: REVIEW_RES })
  const fix = await agent(FIX(l, review || { verdicts: [], must_fix: [], file_as_issue: [] }), { label: `fix:${l.name}`, phase: 'Fix + gate', schema: FIX_RES })
  return { lane: l.name, units, review, fix }
}
const results = await parallel(args.lanes.map(l => () => runLane(l)))
return results
