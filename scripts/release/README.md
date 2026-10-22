# scripts/release/

The release machinery of a cyrius `X.Y.Z` release run as lanes: the slot-open triage, the
placements and lane briefs, the lanes of each wave, the release-docs pass, and the close's
CHANGELOG assembly, issue archiving and roadmap / state refresh. These are development tools.
Nothing ships them: no tarball or installer copies this folder (the tarballs copy only the files
named in `cyrius.cyml`'s `[release] scripts`).

- The `.js` files are scripts for Claude Code's **Workflow tool**. Each one starts with a pure-literal
  `export const meta` and takes its inputs as the global `args`. They have no filesystem or
  environment access, so every path and release fact is an `args` field.
- The steps that edit the checkout are cyrius programs in [`programs/release/`](../../programs/release/)
  (6.7.17: they replaced this folder's Python, each with the same output on the same input —
  [`tests/gates/toolchain/dev_helpers_match_golden.sh`](../../tests/gates/toolchain/dev_helpers_match_golden.sh)).
  Run each from the checkout with `cyrius run programs/release/<step>.cyr`. `common.cyr` holds the
  options they share; `pyre.cyr` (Python's `re`), `pyfmt.cyr` (Python's `str.format`) and
  `pydiff.cyr` (`difflib`'s unified diff) are what roadmap_state's template reads and prints with.
  None of them is a program of its own.
- The Workflow scripts have no cyrius form; they stay here, beside the steps' docs (the user,
  2026-10-22, 6.7.17's D38).

## Conventions

| Name | Meaning |
|---|---|
| `<c6>` | the release scratch directory. The steps take it as `--c6`, default `$CYRIUS_SCRATCH`, else `${XDG_CACHE_HOME:-$HOME/.cache}/c6`. The Workflow scripts take it as `args.c6`. |
| `<tag>` | the version without dots (`X.Y.Z` → `XYZ`). Every per-release file is `<c6>/<tag>_<name>`. |
| `--repo` | the checkout a step reads and edits. Default `$CYRIUS_REPO`, else the checkout the current directory is in. |
| `--ver` | the release, `X.Y.Z`. Required by every step. |
| `--date` | `YYYY-MM-DD` for the step's dated lines. Required where the step writes dated text. |
| `--dry` | report what would change and write nothing. Offered by every step that writes. |

The steps never write into `<c6>` inputs they did not produce. The per-release literal content
(unit notes, special re-placements, prose) lives in input files that the release itself writes
(schemas below), not in the code.

## The flow, in order

### 1. Slot open — triage (`triage.js`, Workflow)

One read-only agent per lane group. Each agent premise-checks its issues on the slot-open compiler,
drafts the decision questions, and drafts the fix plans.

`args`:

```js
{
  c6: '<abs dir>', repo: '<abs checkout>', ver: 'X.Y.Z', prev: 'X.Y.W',
  rel: '<one line>',                 // optional: what the release is
  slot_open_sha: '<sha>', cycc_size: '<bytes as printed with thousands commas>',
  prev_decisions: { count: N, file: '<abs path of the previous release decisions .md>' },
  lanes: [{ name, desc: '<one line>', items: ['<issue file name, no .md>', ...], extra: '<notes>'? }]
}
```

- **Reads:** the issue files, and the previous release's handoffs `<c6>/<prevtag>_handoff_*.md`.
- **Writes:** nothing outside its scratch `<c6>/t<tag>/<lane>/`.
- **Output:** the triage, returned. Save it as `<c6>/<tag>_triage.json`.

The session then asks the user the decisions, once, and plans the waves and units. No script does
either step. Two files come out of it:

- `<c6>/<tag>_decisions.json`: `[{"id": N, "issue": "<file>.md", "lane", "question", "options": [{"label", "effect"}], "rec", "rec_label", "why"}]`. `rec_label` is the label of the chosen option. A human-readable `<c6>/<tag>_decisions.md` goes beside it.
- `<c6>/<tag>_units.json`: `{"W<n>": {"<lane>": {"<unit>": ["<issue>.md", ...]}}}`. Wave 0 (lane `main`) is the work done on main before the lanes fork.

### 2. Slot open — placements (`place`) and briefs (`briefs`)

```sh
cyrius run programs/release/place.cyr  --ver X.Y.Z --date YYYY-MM-DD [--dry] [--units F] [--decisions F] [--plan F]
cyrius run programs/release/briefs.cyr --ver X.Y.Z --date YYYY-MM-DD [--dry] [--units F] [--triage F] [--decisions F] [--notes F] [--out DIR]
```

- **place** rewrites each planned issue's `**Placement:** X.Y.Z — <label> (…) — never 7.x.` line.
  The new line names the issue's wave and unit, keeps `<label>`, and is dated `--date`. Under it,
  place adds one `**Decision (user, <date>, at the X.Y.Z open):** D<n> — <answer>.` line per
  decision on that issue. Then it applies the plan's special items.
  - **The line's shape:** `<label>` sits on the `**Placement:**` line itself. The parenthetical may
    wrap onto continuation lines (never across a blank line or a `**Field:**` line), and it becomes
    one line. Text after `— never 7.x.` is kept, and the Decision lines go after the wrapped
    sentence's last line.
  - **Reads:** `units.json`, `decisions.json`, and the optional `<c6>/<tag>_place.json`.
  - **Writes:** the issue files.
  - **Fails:** exits 1, writing nothing, when an issue has no Placement line for `X.Y.Z`.
- **briefs** writes `<c6>/<tag>_briefs/<lane>_<unit>.md` for every unit of waves 1 and up. Each
  brief holds the unit's issues with their triage, the user's decisions with the chosen answer, and
  the lane's triage notes.
  - **Reads:** `units.json`, `triage.json`, `decisions.json`, and the optional `<c6>/<tag>_brief_notes.json`.

Briefs for lanes added later (for example a lib-fix lane opened at an integration) are written by
hand in the same format.

**`<c6>/<tag>_place.json`** (optional; every key is optional):

```json
{
  "decision_ids": "1-<n>",
  "special": [
    {
      "file": "<issue>.md",
      "placement": "**Placement:** <the whole new line>",
      "decisions": ["**Decision (user, …):** <a whole line>", "..."],
      "decisions_after": "**Decision (user, <date>, at the X.Y.W open):**",
      "decision_count": 3
    }
  ]
}
```

- `decision_ids` limits which decisions get a line of their own. The default is every decision whose
  issue a unit places.
- Each `special` item replaces the issue's `X.Y.Z` Placement line with `placement`. That line may name
  another release, which moves the issue. In the line, `{label}` stands for the old line's label.
- Each special item's `decisions` lines go after the line that starts with `decisions_after`. The
  default position is after the Placement line.
- `decision_count` only feeds the printed count.

**`<c6>/<tag>_brief_notes.json`** (optional; every key is optional):

```json
{
  "preamble": "<markdown put under every brief's title; end it with \n>",
  "unit_notes": {"<lane>/<unit>": "<the unit note>"},
  "extra_decisions": {"<lane>/<unit>": [12, 14]},
  "cross_lane": {"<lane>": [{"from": "<other lane>", "label": "<bold label>"}]}
}
```

- `extra_decisions` lists decisions on another issue that this unit carries. Each one becomes a
  `## <issue> — D<n>` section with its question, answer and why.
- Each `cross_lane` entry appends the other triage lane's `cross_lane` text under the given label.

### 3. Each wave — the lanes (`lanes.js`, Workflow)

The script runs once per wave. For each lane, in parallel:

1. One agent per unit, in order, implements that unit in the lane's worktree.
2. One read-only review round checks the lane's bites.
3. One fix step applies the review's fixes and runs the lane gate.

`args`:

```js
{
  c6: '<abs dir>', repo: '<abs checkout>', ver: 'X.Y.Z', rel: '<one line>',
  decisions: { count: N, date: 'YYYY-MM-DD', file: '<abs path of <tag>_decisions.md>' },
  known_skips: ['<gate>', ...],          // the check.sh SKIPs this release expects; [] when none
  coauthor: 'Co-Authored-By: <name> <email>',
  hosts: ['ecb macOS arm64', 'ach Intel macOS', 'cass Windows', 'pi aarch64 Linux'],   // ~/.ssh/config aliases
  lanes: [{ name, wt: '<abs worktree>', base: '<sha the lane was cut from>', units: ['G1', ...], heap: true?,
            notes: { '<unit>': '<text>' }? }]   // a resumed run: what each listed unit already did
}
```

A run stopped part-way (an account limit, a killed session) is resumed by running the script again with
`units` cut to the units not yet finished. Give a unit that was mid-way a `notes` entry naming what it already
committed and what it left uncommitted in the worktree; its agent verifies that and continues from it.
`base` stays the lane's cut point, so the review still covers every bite of the lane.

- **Reads:** the briefs.
- **Writes:**
  - commits on the branch `l<tag>-<lane>`
  - `<c6>/<tag>_handoff_<lane>.md` (appended)
  - `<c6>/<tag>_staging/<lane>/*.md` (the issues the lane files, for the integration to place)
- **Returns:** per lane, the units' commits, anything blocked, the review, and the gate result.

The integration between waves is the session's job: merge the lanes, run `cyrius pulsar`, place the
staged issues, run the gate.

### 4. After the last wave — the release docs (`docs.js`, Workflow)

One agent per lane drafts that lane's part of the docs into `<c6>/<tag>_docs/`. The agents edit no
repository.

`args`:

```js
{
  c6: '<abs dir>', repo: '<abs checkout>', ver: 'X.Y.Z', prev: 'X.Y.W',
  rel_blurb: '<one line>', decisions: { range: 'D1-D<n>', date: 'YYYY-MM-DD' },
  no_edit_repos: ['<a fold checkout the release touched>', ...],   // repo and vidya are always named
  vidya: '<abs dir>'?,                   // default: <dirname(repo)>/vidya
  lanes: [{ name, heading: '<### heading>', prefix: '<bite id prefix>', range: '<base>..<lane branch>',
            issues: ['<issue>.md', ...], extra: '<lane note>'? }]
}
```

Per lane it writes, in `<c6>/<tag>_docs/`:

- `changelog_<lane>.md`
- `migration_<lane>.md`
- `behaviour_<lane>.md`
- `banners_<lane>.json`
- `vidya_<lane>.md`

The session writes the rest of the docs dir by hand:

- `changelog_head.md`: the entry's head. It may carry `@GATEHEAD@`, `@DRIVER@`, `@SHELL@` and `@BENCH@`, which assemble fills.
- `changelog_integration.md`
- `changelog_filed.md`
- any extra part, for example a fold's `changelog_fold_<name>.md`
- `migration_intro.md`: the `### X.Y.Z` heading and the paragraph under it

### 5. Close — after the release gate is GREEN and the bench has run, in this order

```sh
cyrius run programs/release/assemble.cyr --ver X.Y.Z --prev X.Y.W --date YYYY-MM-DD \
    --lanes <lane>,<lane>,... [--extra integration,filed] [--mig-extra <part>,...] \
    --gatehead <sha> --driver '<n / n>' --shell '<n / n>' --bench '<ms>' [--dry]
cyrius run programs/release/archive.cyr --ver X.Y.Z [--dry]
cyrius run programs/release/roadmap_state.cyr --ver X.Y.Z --set gatehead=<sha> --set archived=<N> ... [--dry]
```

**assemble** writes the CHANGELOG entry and the migration section.

- **CHANGELOG entry:** it replaces the release's placeholder header `## [X.Y.Z] — <date>` (written by
  `version-bump.sh`; it must appear exactly once) with `## [X.Y.Z] — <--date>`, followed by these
  parts in order:
  1. the head, with its placeholders filled
  2. `changelog_<lane>.md` for each lane in `--lanes`
  3. `changelog_<part>.md` for each part in `--extra` (default `integration,filed`)
- **Migration section:** it inserts the intro, then `migration_<lane>.md` for each lane, then each
  `--mig-extra` part, above `### <prev>` in `docs/development/ecosystem-migration.md`.
- A lane's follow-on wave can be its own lane name (for example `libfix,libfix4`). Its parts are
  then joined with one blank line, as every part is.
- **Runs once.** The placeholder must still be empty: the header, a blank line, then the previous
  release's `## [`. A header that already carries an entry, or a migration doc that already has
  `### X.Y.Z`, stops the step before anything is written, so a second run refuses.

**archive** archives the resolved issues.

- For each issue named in `<c6>/<tag>_docs/banners_*.json`, it marks the title `— RESOLVED` (or
  `— CLOSED (not a cyrius bug)`), puts the banner under the title, rewrites the `**Status:**` line,
  and `git mv`s the file into `docs/development/issues/archived/`.
- It then repoints every link to those files in every tracked text file.
- Run it after assemble, so the new CHANGELOG entry's links are repointed too.
- `--dry` neither moves nor rewrites anything. In a dry run the moved files' own links are
  therefore counted at their old paths, so the repointed count is higher than a real run's.

**roadmap_state** has two modes.

- **`--derive`** prints the tree's figures and writes nothing. It works on any checkout, at any time.
  The figures are:
  - `.tcyr` and `crossos/` counts
  - `lib/*.cyr`
  - shell gates
  - api-surface
  - open issues and proposals
  - cycc and `cycc-native-aarch64` sizes, and `.text` (needs `readelf`)
  - issues placed per release, from each file's first `**Placement:**` line
- **Without `--derive`** it applies `<c6>/<tag>_roadmap_state.json` to `roadmap.md`, `state.md` and
  `completed-phases.md`. It refuses while any issue is still placed in `X.Y.Z`.

**`<c6>/<tag>_roadmap_state.json`** holds the release's prose, as edit operations applied in order
per file:

```json
{"files": {
  "docs/development/roadmap.md": [
    {"sub": "<regex>", "to": "<text>", "count": 1, "flags": "S"},
    {"replace": "<literal>", "to": "<text>", "must": true},
    {"cut": ["<start literal>", "<end literal>"]}
  ],
  "docs/development/state.md": [
    {"row": "<row name>", "to": "<cell text>"},
    {"row": "<row name>", "keep_from": "<marker>", "to": "<new text before the marker>"}
  ],
  "docs/development/completed-phases.md": [
    {"insert_after_row": "<row name>", "to": "<the new table line>"}
  ]
}}
```

- Every `to` is a Python `str.format` template (read as Python reads it, by `pyfmt.cyr`), so literal
  braces are written `{{ }}`.
- The placeholders the template can use:
  - the derived figures: `{n_tcyr}` `{n_cross}` `{n_lib}` `{n_gates}` `{n_api}` `{n_open}` `{n_prop}` `{cyc}` `{arm}` `{text}`
  - the count of issues placed in a release: `{placed[X.Y.Z]}`
  - `{ver}`, and `{date}` when `--date` is given
  - every `--set key=value`: the gate head, the driver and shell counts, the bench, the A/B figures, the archived count, and anything the tree cannot give, such as the number of issues filed
- The `sub` patterns and every literal are written as-is (no placeholders). A `sub` pattern is a
  Python regex and its replacement a Python `re.sub` template (read as Python reads them, by
  `pyre.cyr`), so it may use `\g<1>`.
- A row is a `docs/development/state.md`-style line `| **<name>** | … |`.
- An operation that matches nothing is reported in the output. A missing row or marker stops the
  step before anything is written.

After the close steps, the session regenerates the issue index (`docs/development/issues/README.md`,
`cyrius run programs/dev/regen_issue_index.cyr`),
reads the diffs, and hand-edits what the templates did not foresee before committing.
