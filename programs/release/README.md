# programs/release — the release steps

The steps of a cyrius release run as lanes that edit the checkout: `place` and `briefs` at the slot
open, `assemble`, `archive` and `roadmap_state` at the close. They are cyrius programs (6.7.17: they
replaced `scripts/release`'s Python, each with the same output on the same input —
[`tests/gates/toolchain/dev_helpers_match_golden.sh`](../../tests/gates/toolchain/dev_helpers_match_golden.sh)),
run from the checkout's root with `cyrius run programs/release/<step>.cyr` (their includes resolve from
there). Development tools: nothing ships them. `--repo` defaults to `$CYRIUS_REPO`, else the cyrius
checkout the current directory is in (the Python steps used the checkout they lived in).

The flow, every step's options, inputs and outputs, and the input files' schemas are in
[`scripts/release/README.md`](../../scripts/release/README.md), beside the Workflow scripts
(`triage.js`, `lanes.js`, `docs.js`) that run the lanes around them.

| File | What it is |
|---|---|
| `place.cyr`, `briefs.cyr`, `assemble.cyr`, `archive.cyr`, `roadmap_state.cyr` | the steps |
| `common.cyr` | the options and helpers the steps share (was `release_common.py`) |
| `pyre.cyr` | Python's `re`: roadmap_state's `sub` patterns and templates are Python regexes |
| `pyfmt.cyr` | Python's `string.Formatter`: every template `to` is a Python format string |
| `pydiff.cyr` | `difflib.unified_diff`: roadmap_state `--dry` prints the hunks Python printed |
