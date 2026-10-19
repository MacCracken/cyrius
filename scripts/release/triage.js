export const meta = {
  name: 'triage',
  description: 'Premise-check every issue placed in a cyrius release against the slot-open compiler, extract the user decisions, draft fix plans per lane (read-only)',
  phases: [{ title: 'Triage', detail: 'one read-only agent per lane group' }],
}
// scripts/release/triage.js — the slot-open triage of a cyrius release, for Claude Code's Workflow
// tool: one read-only agent per lane group premise-checks each of its issues against the slot-open
// compiler (the filed repro run verbatim), says whether the fix needs the user's decision (and
// drafts the question), and drafts the fix plan. Its result, saved as <c6>/<tag>_triage.json, is
// what the decisions are asked from and what scripts/release/briefs.py reads.
// (meta stays the first statement: the Workflow tool requires it there, as a pure literal.)
//
// usage:   the Workflow tool, with this file as scriptPath and the args below.
// args:    {
//   c6:   '<abs dir>',           the release scratch dir; agent scratch under <c6>/t<tag>/<lane>/
//   repo: '<abs dir>',           the main checkout at the slot open (read-only here)
//   ver:  'X.Y.Z',
//   prev: 'X.Y.W',               the release that just shipped
//   rel:  '<one line>'?,         optional: what the release is ("Break N, repair M — what X.Y.W filed")
//   slot_open_sha: '<sha>',      the commit the triage reads
//   cycc_size: '<bytes, as printed with thousands commas>',   build/cycc at that commit
//   prev_decisions: { count: N, file: '<abs path>' },   the previous release's decisions
//   lanes: [{ name, desc: '<one line>', items: ['<issue file name without .md>', ...],
//             extra: '<lane notes>'? }]
// }
// inputs:  the issue files in repo; the previous release's handoffs <c6>/<prevtag>_handoff_*.md.
// outputs: the return value [{ lane, items: [{issue, title, status, evidence, severity, kind,
//          decision_needed, decisions, fix_plan, touches, rows, targets, hosts, size,
//          heap_layout_change, risk}], order, groups, cross_lane, ordering_constraints }]
//          (save it as <c6>/<tag>_triage.json). Writes no file outside its scratch.
//
// converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
// (a Workflow script has no cyrius form; that issue records the choice for it.)
const need = (v, what) => { if (v === undefined || v === null || v === '') throw new Error(`triage.js: args.${what} is required`); return v }
const C6 = need(args.c6, 'c6')
const REPO = need(args.repo, 'repo')
const VER = need(args.ver, 'ver')
const PREV = need(args.prev, 'prev')
const SHA = need(args.slot_open_sha, 'slot_open_sha')
const SIZE = need(args.cycc_size, 'cycc_size')
const PD = need(args.prev_decisions, 'prev_decisions')
need(args.lanes, 'lanes')
const TAG = VER.replace(/\./g, '')
const PREVTAG = PREV.replace(/\./g, '')
const REPOS = REPO.replace(/\/+$/, '').replace(/\/[^/]*$/, '')
const ITEM = {
  type: 'object',
  properties: {
    issue: { type: 'string' },
    title: { type: 'string' },
    status: { type: 'string', enum: ['OPEN', 'FIXED_ALREADY', 'PARTIAL', 'CANNOT_REPRODUCE'] },
    evidence: { type: 'string' },
    severity: { type: 'string' },
    kind: { type: 'string', enum: ['platform', 'language', 'tooling', 'stdlib', 'infra', 'docs', 'decision-only'] },
    decision_needed: { type: 'boolean' },
    decisions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'object', properties: { label: { type: 'string' }, effect: { type: 'string' } }, required: ['label', 'effect'] } },
          recommended: { type: 'string' },
          why: { type: 'string' },
        },
        required: ['question', 'options', 'recommended', 'why'],
      },
    },
    fix_plan: { type: 'string' },
    touches: { type: 'array', items: { type: 'string' } },
    rows: { type: 'array', items: { type: 'string' } },
    targets: { type: 'array', items: { type: 'string' } },
    hosts: { type: 'array', items: { type: 'string' } },
    size: { type: 'string', enum: ['S', 'M', 'L'] },
    heap_layout_change: { type: 'boolean' },
    risk: { type: 'string' },
  },
  required: ['issue', 'title', 'status', 'evidence', 'severity', 'kind', 'decision_needed', 'fix_plan', 'touches', 'rows', 'targets', 'hosts', 'size', 'heap_layout_change'],
}
const LANE = {
  type: 'object',
  properties: {
    lane: { type: 'string' },
    items: { type: 'array', items: ITEM },
    order: { type: 'array', items: { type: 'string' } },
    groups: { type: 'string' },
    cross_lane: { type: 'string' },
    ordering_constraints: { type: 'string' },
  },
  required: ['lane', 'items', 'order', 'groups', 'cross_lane', 'ordering_constraints'],
}
const COMMON = (lane) => `You are triaging cyrius ${VER}${args.rel ? ` (${args.rel})` : ''} — READ-ONLY. Repo: ${REPO} (main, at the ${VER} slot open ${SHA} = ${PREV}'s code, cycc ${SIZE} B). Issue files: docs/development/issues/<name>.md.

HARD RULES (the user's standing instructions):
- Do NOT edit, create, move or delete ANY file in ${REPO} or any other repo. Never edit any CLAUDE.md or rules file (in any repo); report a stale rule line instead. No git command that writes (commit, stash, worktree add, checkout, branch, tag). Never write into ~/.cyrius. Never run install.sh, version-bump.sh, cyrius pulsar, or a bare \`cyrius build\` in the repo.
- Probes and scratch ONLY under SCR=${C6}/t${TAG}/${lane}/ (mkdir -p it). export TMPDIR=$SCR/tmp (mkdir it) — /tmp has a shared per-user quota. Never write under /tmp directly. Run every command non-interactively; use rm -f / rm -rf only inside $SCR.
- Do not open, grep or survey consumer repos (CLAUDE.md's top rule) — the issue text is the spec. Fold SOURCE repos (${REPOS}/<fold>, for each fold docs/ecosystem.md lists) may be read when an item is a fold item.
- Do not hunt for other bugs. Report on the listed issues only; a severe find met in passing gets one line in risk.
- The real hosts (ssh ecb / ach / cass / pi) MAY be used read-only for a platform premise-check when the issue cannot be checked locally (copy a probe to a scratch dir there, run, delete it; each host's traps — cass's Defender-excluded directory and its exit codes — are in CLAUDE.md § Verification habits). Prefer local emulation first: aarch64 = cross compiler from src/main_aarch64.cyr + qemu-aarch64; PE = CYRIUS_TARGET_WIN=1 ./build/cycc + wine with a PRIVATE WINEPREFIX under $SCR (kill its wineserver when done); cx = src/main_cx.cyr + programs/cxvm.cyr built into $SCR. Build cross binaries into $SCR from the tree (cat src/main_<x>.cyr | ./build/cycc > $SCR/x).
- Compile probes from the repo root so 'include "lib/x.cyr"' resolves: cat $SCR/p.cyr | ./build/cycc > $SCR/p 2>$SCR/p.err; echo rc=$?; then run it. ALWAYS check the compile rc and stderr before reading a probe's exit code: an empty output file runs as an empty shell script and exits 0.

CONTEXT: ${PREV} just shipped (CHANGELOG.md [${PREV}]; its ${PD.count} decisions in ${PD.file}; the ${PREV} lane handoffs in ${C6}/${PREVTAG}_handoff_*.md). Nearly every issue was filed BY those lanes, their reviews or the release-docs pass; some may already be fixed by a later bite or another lane — premise-check every one against the LIVE build/cycc. Decision ids from earlier releases must be named with their release ("${PREV}'s D8"). Decisions you draft get new ids at the open.

FOR EACH ISSUE in your list:
1. Read the issue file fully. Premise-check its CLAIM against the live compiler: run the filed repro VERBATIM (the repro is the spec; never edit it to fit). status OPEN / FIXED_ALREADY / PARTIAL / CANNOT_REPRODUCE, with the command and the actual output (short) in evidence. severity: the file's, or yours if it has none (High = a crash or a silent wrong value on valid code; Medium; Low).
2. kind: platform, language, tooling, stdlib, infra, docs, decision-only.
3. Decide whether the fix needs the USER's decision: it does when the fix changes what compiles (a newly refused or newly accepted shape), changes a value existing valid code computes, removes a public symbol, or picks between two plausible meanings of valid source; *-decision.md files always carry one. It does NOT when the program crashes or computes what its source plainly does not say (a codegen bug — just fix). Each decision is ONE question (never two forks bundled), phrased by what concretely changes for a user ("this line stops compiling", "this prints 7 instead of 3"), with 2-4 options and their observable effect, the recommended option, and WHY grounded in cyrius's own guide (docs/guides/cyrius-guide.md), ADRs, vidya, or earlier user decisions — never 'other languages do X'. Prefer the option that extends an existing user decision to the shape. No internal function names in the question or option labels.
4. Draft the fix plan: the functions and CURRENT line numbers, the approach, the regression rows (gate under tests/gates/<bucket>/ and/or .tcyr; crossos/ when it must run on ecb/ach/cass/pi), the targets, the hosts it needs (qemu, wine, cxvm, ecb, ach, cass, pi), size S (< ~1h) / M (a few hours) / L (a day+), heap_layout_change (a heap / brk region moved or resized = the two-step bootstrap), and risk (seed/cybs exposure if it touches anything cybs compiles — all of src/; ABI change; a fold release needed first).
Also: groups (which items share a fix or must land together), the files your lane touches that another lane plausibly touches (cross_lane — name the functions), the suggested bite order, and ordering constraints (a fold the user must tag first, a decision before a bite, the IR arena's two-step first).

Be concise and concrete. Clean your scratch binaries and any remote probe dirs when done. Your final output is the structured object only.`
const results = await parallel(args.lanes.map(l => () => agent(
  COMMON(l.name) + `\n\nYOUR LANE: ${l.name} — ${l.desc}\nISSUES:\n` + l.items.map(i => '- ' + i + '.md').join('\n') + (l.extra ? '\n\nLANE NOTES:\n' + l.extra : ''),
  { label: 'triage:' + l.name, phase: 'Triage', schema: LANE }
)))
return results.filter(Boolean)
