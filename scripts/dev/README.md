# scripts/dev — developer helpers

Helpers for working on cyrius itself, kept in the repo so every dev machine has them. None ships (the tarball
builders copy named files from `scripts/`, never this folder). Each takes the repo root from its own location
(`CYRIUS_REPO` overrides it) and keeps its scratch under `CYRIUS_SCRATCH` (default
`${XDG_CACHE_HOME:-$HOME/.cache}/c6`); each file's header says what it reads and writes. They are to be converted
to cyrius: [`docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md`](../../docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md).

| Helper | Usage |
|---|---|
| `regen-issue-index.py` | `python3 scripts/dev/regen-issue-index.py` — rewrite `docs/development/issues/README.md` § *Open queue* from each issue's `**Placement:**` |
| `xb.sh` | `sh scripts/dev/xb.sh <file.cyr\|file.tcyr>` — build and run one program on x86_64, aarch64 (qemu-aarch64), cx (cxvm) and PE (wine); prints the four exit codes |
| `probe-split.py` | `python3 scripts/dev/probe-split.py <dir> <file>` — split a file of `== name` blocks into `<dir>/<name>.cyr` probes |
| `probe.sh` | `[OLD_CC=<compiler>] sh scripts/dev/probe.sh <dir>` — compile and run every `<dir>/*.cyr`; with `OLD_CC`, before / after side by side |
| `ab.py` | `python3 scripts/dev/ab.py <old_ref> <new_ref> [--runs N]` — A/B self-compile timing of two refs' committed compilers (own sources and same input) |
| `envprobe.sh` | `sh scripts/dev/envprobe.sh` — a dev machine's inventory (sysctls, ulimits, locale, binfmt, network); diff two boxes' outputs |
| `keepboth.py` | `python3 scripts/dev/keepboth.py [--sep] <file>` — resolve every conflict block by keeping both sides; exits 1 when there was none |

Rebuilding `build/cycc` from the source at a fixpoint is `sh scripts/build-cycc-verify.sh --install <scratch-dir>`
(c1 = build/cycc(src), c2 = c1(src), c3 = c2(src); c2 == c3 required; build/cycc replaced by an atomic rename);
`--fixpoint <scratch-dir>` runs the same stages and check and installs nothing.
