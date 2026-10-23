export const meta = {
  name: 'release-docs',
  description: 'cyrius release docs: per lane, draft the CHANGELOG sections, migration notes, behaviour-change bullets, issue archive banners and vidya notes from the handoffs and the merged commits (scratch only, no repo edits)',
  phases: [{ title: 'Draft' }],
}
// scripts/release/docs.js — the release-docs pass of a cyrius release, for Claude Code's Workflow
// tool: after the lanes are merged, one agent per lane drafts that lane's part of the release docs
// into the docs dir (never into a repo); programs/release/assemble.cyr and archive.cyr consume them
// at the close. (meta stays the first statement: the Workflow tool requires it there, as a pure literal.)
//
// usage:   the Workflow tool, with this file as scriptPath and the args below; one run per release
//          (or per batch of lanes).
// args:    {
//   c6:   '<abs dir>',          the release scratch dir; the drafts go to <c6>/<tag>_docs/
//   repo: '<abs dir>',          the main checkout, the lanes merged into it (read-only here)
//   ver:  'X.Y.Z',
//   prev: 'X.Y.W',              the previous release: its CHANGELOG entry and migration section are
//                               the model, its banners the model banner
//   rel_blurb: '<one line>',    what the release is ("Break N, repair M — what X.Y.W filed, in seven
//                               lanes over four waves")
//   decisions: { range: 'D1-D<n>', date: 'YYYY-MM-DD' },   the user's answers (<c6>/<tag>_decisions.md)
//   no_edit_repos: ['<path of a fold checkout>', ...],   also named in the "edit no file" rule (the
//                               checkout and the vidya checkout are always named)
//   vidya: '<abs dir>'?,        optional; default: the sibling checkout <dirname(repo)>/vidya
//   lanes: [{ name, heading: '<### heading text>', prefix: '<bite id prefix, e.g. GN>',
//             range: '<base>..<lane branch>', issues: ['<issue>.md', ...], extra: '<lane note>'? }]
// }
// inputs:  <c6>/<tag>_handoff_<lane>.md, <c6>/<tag>_briefs/<lane>*_*.md, <c6>/<tag>_decisions.md,
//          the lane commits and the open issue files in repo. <tag> = ver without dots.
// outputs: per lane, in <c6>/<tag>_docs/: changelog_<lane>.md, migration_<lane>.md,
//          behaviour_<lane>.md, banners_<lane>.json, vidya_<lane>.md (+ a probe_<lane>/ scratch dir);
//          the return value [{ lane, files_written, bites, banners, behaviour_changes,
//          discrepancies, notes }].
//
// converted to cyrius later: docs/development/issues/archived/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
// (a Workflow script has no cyrius form; that issue records the choice for it.)
const need = (v, what) => { if (v === undefined || v === null || v === '') throw new Error(`docs.js: args.${what} is required`); return v }
const C6 = need(args.c6, 'c6')
const REPO = need(args.repo, 'repo')
const VER = need(args.ver, 'ver')
const PREV = need(args.prev, 'prev')
const BLURB = need(args.rel_blurb, 'rel_blurb')
const DEC = need(args.decisions, 'decisions')
const NO_EDIT = args.no_edit_repos || []
const VIDYA = args.vidya || REPO.replace(/\/+$/, '').replace(/\/[^/]*$/, '') + '/vidya'
const lanes = need(args.lanes, 'lanes')
const TAG = VER.replace(/\./g, '')
const OUT = `${C6}/${TAG}_docs`
const RES = {
  type: 'object',
  properties: {
    files_written: { type: 'array', items: { type: 'string' } },
    bites: { type: 'integer' },
    banners: { type: 'integer' },
    behaviour_changes: { type: 'integer' },
    discrepancies: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['files_written', 'bites', 'banners', 'behaviour_changes', 'discrepancies', 'notes'],
}
const noEdit = [...new Set([REPO, VIDYA, ...NO_EDIT])].map(r => `not ${r}`).join(', ')   // the vidya checkout is always named
const P = (l) => `You draft the release documentation for ONE lane of cyrius ${VER} (${BLURB}): the "${l.name}" lane. Everything you write goes under ${OUT}/ — you edit NO file in any repository (${noEdit}, not a worktree). Never edit any CLAUDE.md or rules file (in any repo); report a stale rule line instead. Read-only git commands only. Any probe compiles in a scratch dir under ${OUT}/probe_${l.name}/ with ${REPO}/build/cycc (export TMPDIR=${OUT}/probe_${l.name}/tmp, mkdir -p it); check a probe's compile rc before reading its exit code (an empty output file runs as an empty script and exits 0). Use only non-interactive commands; never rm outside ${OUT}/probe_${l.name}/; do NOT delete your probe dir at the end (the caller cleans it).

SOURCES (read them all):
- The lane's handoff: ${C6}/${TAG}_handoff_${l.name}.md — per issue: the commit sha, what changed, rows, measured before/after, the decision, a CHANGELOG bullet, migration and vidya notes; then "## Review fixes and lane gate". Where a bullet is marked corrected by the review fixes, or the review-fix section corrects an earlier bullet, the CORRECTED text wins; never carry a claim the review withdrew.
- The lane's commits, merged into main with their shas intact: cd ${REPO} && git log --format='%h %s' ${l.range} (and git show <sha> to check a claim). The commit message is the most exact statement of each bite.
- The issues it resolved (docs/development/issues/<file>, still OPEN on disk): ${l.issues.join(', ')}.
- The user's decisions: ${C6}/${TAG}_decisions.md (${DEC.range}, answered ${DEC.date}) and the briefs ${C6}/${TAG}_briefs/${l.name}*_*.md; each issue file's **Decision (user, ${DEC.date}, …)** line(s). Decision ids are ${VER}'s; an earlier release's are named with it ("${PREV}'s D30").
- THE MODEL for format and voice: CHANGELOG.md's [${PREV}] entry (the entry after the empty [${VER}] header) — its lane sections ("### …" then "#### <PREFIX>-N — …"). And docs/development/ecosystem-migration.md § "### ${PREV}" for migration notes.

WRITE (Markdown, matching the model's voice: plain, exact, the shape → old behaviour → new behaviour, per target where measured, the decision with its date, the rows and mutations; no marketing):
1. ${OUT}/changelog_${l.name}.md — the lane's part of CHANGELOG [${VER}]: one "### ${l.heading}" heading, then one "#### ${l.prefix}-N — <title> (lane ${l.name}, commit <sha>)" per bite in commit order (a review fix is its own "#### ${l.prefix}-Nr — … (lane ${l.name}, review fix, commit <sha>)"), each closing with a link to its issue as docs/development/issues/archived/<file> (the archive path it will have). End with "#### ${l.name} lane — the lane gate" (seed-derive, the check.sh summary, the per-file loop, hardware legs if run) taken from the handoff.
2. ${OUT}/migration_${l.name}.md — for ecosystem-migration § ${VER}: one "**${l.prefix}-N — <title>**" block per bite that changes what an existing program does or makes it stop compiling (newly refused shapes, changed results, renamed / removed things), each with how to migrate. Bites that only fix a crash into the right answer, or only add diagnostics on code that never compiled, get no block. If none, write "(none)". Start the file with "#### <the lane's heading>".
3. ${OUT}/behaviour_${l.name}.md — one bullet per behaviour change for the release head's "⚠ Behaviour changes" list: the shape in one line, then its decision id and date (e.g. "(D27, user ${DEC.date})"); a change no decision covers says why it needed none, and a change that goes BEYOND its decision's text is marked "⚠ beyond D#'s text".
4. ${OUT}/banners_${l.name}.json — a JSON array, one object per resolved issue file: {"file": "<basename>.md", "banner": "> ✅ **RESOLVED in v${VER}** (<one paragraph: what now happens to the filed repro, the decision applied, the rows that pin it>. CHANGELOG [${VER}])"}. The model banner: any file in docs/development/issues/archived/ resolved in v${PREV} (grep -l 'RESOLVED in v${PREV}' docs/development/issues/archived/ | head -3), line 3. One object per FILE (an issue several bites closed gets one banner naming all of them). If an issue's filed surface was only partly closed, say so in its banner and in discrepancies.
5. ${OUT}/vidya_${l.name}.md — notes for ${VIDYA}/content/cyrius/: (a) language entries to change (which entry, what the new rule is: newly refused shapes, changed behaviour), (b) field_notes/compiler — one entry per compiler surprise or gotcha the lane met (the mechanism, the trap, the fix), (c) field_notes/language — user-facing gotchas. Use the handoff's vidya notes as the base; say "(none)" for an empty part.

Lane extra: ${l.extra || '(none)'}

Report: the files written, the bite count, the banner count, the behaviour-change count, and every DISCREPANCY you found between the handoff, the commits and the issue files (a claim the commit does not support, an issue's filed shape the lane did not close, a bullet the review corrected that still reads wrong, a change beyond its decision's text).`
const results = await parallel(lanes.map(l => () => agent(P(l), { label: `docs:${l.name}`, phase: 'Draft', schema: RES }).then(r => ({ lane: l.name, ...(r || { files_written: [], notes: 'agent returned nothing' }) }))))
return results
