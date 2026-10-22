# The developer and release helpers moved into `scripts/` (Python and shell) are converted to cyrius — sovereignty, long term — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-19 with the move of the agent's helper scripts out of its private cache
(`~/.cache/c6`, `~/.cache/cyrius-tools`) into `scripts/`. The user, 2026-10-19: "scripts worth keeping should live in our
scripts folder" / "scripts worth keeping will need to be converted at some point... to not go against the rule long
term" (CLAUDE.md § *Ecosystem & stdlib*: "Sovereignty: no Python / bash / C as a shipped deliverable").
**Placement:** 6.7.17 — the cleanup of the remaining issues (tool lane, wave 1, unit TO1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D38 — Keep them in scripts/release/.
**Severity:** Low — none of them ships (the tarball scripts copy named files from `scripts/`, never the folder); the
rule's long-term reading is that the toolchain's own tooling is cyrius.
**Kind:** tooling (scripts/dev, scripts/release, scripts/folds → programs/ or `cyrius` verbs).

## What is converted (as moved 2026-10-19)

| Helper | Language | What it does |
|---|---|---|
| `scripts/dev/regen-issue-index.py` | Python | regenerates `docs/development/issues/README.md` § *Open queue* from each file's `**Placement:**` |
| `scripts/dev/ab.py` | Python | A/B self-compile timing of two refs on the same input (the CHANGELOG's bench delta) |
| `scripts/dev/keepboth.py` | Python | resolves lane-merge conflicts by keeping both hunks |
| `scripts/dev/probe-split.py`, `scripts/dev/probe.sh` | Python, sh | split a file of `== name` blocks into probes; compile and run each (optionally against an older compiler) |
| `scripts/dev/xb.sh` | sh | build and run one program on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine) |
| `scripts/dev/envprobe.sh` | sh | a dev machine's inventory (what a new box lacks) |
| `scripts/build-cycc-verify.sh --fixpoint` / `--install` | sh | the guarded three-stage fixpoint and the atomic install of `build/cycc` (folded in from the agent's `fixpoint.sh`; the script itself predates this move) |
| `scripts/folds/sibci.sh`, `run-ci.py`, `cymlcheck.py` | sh, Python | a fold's CI run isolated (clean `git archive`, throwaway `HOME` / `CYRIUS_HOME`); `.cyml` check |
| `scripts/release/{place,briefs,archive,assemble,release_common}.py`, `roadmap-state.py` | Python | the release's mechanical document steps (placements, lane briefs, issue archiving, CHANGELOG assembly, roadmap / state counts) |

The rest of `scripts/` (release-gate.sh, check.sh's shell, the install and tarball scripts) is outside this issue.

**Not convertible:** `scripts/release/{lanes,triage,docs}.js` are input to Claude Code's Workflow tool (agent
orchestration, run by the harness), not programs — no cyrius form exists. The choice for them is the user's: keep them in
`scripts/release/`, or move them into the cyrius-plugins language-development skill (planned 2026-10-19).

## Acceptance

Each converted helper is a cyrius program (programs/ or a `cyrius` verb) that produces the same output as the script it
replaces on the same input (a row per helper in tests/gates), and the script is removed; `scripts/` holds no Python.
