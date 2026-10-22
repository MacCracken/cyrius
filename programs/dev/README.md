# programs/dev — developer helpers

Helpers for working on cyrius itself, kept in the repo so every dev machine has them. They are cyrius
programs (6.7.17: they replaced the Python and shell helpers of `scripts/dev`, each with the same
output on the same input — [`tests/gates/toolchain/dev_helpers_match_golden.sh`](../../tests/gates/toolchain/dev_helpers_match_golden.sh)).
None ships (the tarball builders copy named files, never this folder). Run them from the checkout root
with `cyrius run programs/dev/<name>.cyr` (their includes resolve from there); in this checkout `cyrius run`
builds each with `./build/cycc` (cbt/core.cyr's in-repo rule). They share
[`helper_common.cyr`](helper_common.cyr), which is no program of its own. Each takes the checkout
from `CYRIUS_REPO`, else the cyrius checkout the current directory is in (the nearest directory up
holding `src/main.cyr` whose `cyrius.cyml` has `[package] name = "cyrius"`, as `cyrius` itself decides;
the scripts used the checkout they lived in), and keeps its scratch under
`CYRIUS_SCRATCH` (default `${XDG_CACHE_HOME:-$HOME/.cache}/c6`); each file's header says what it
reads and writes.

| Helper | Usage |
|---|---|
| `regen_issue_index.cyr` | `cyrius run programs/dev/regen_issue_index.cyr` — rewrite `docs/development/issues/README.md` § *Open queue* from each issue's `**Placement:**` |
| `xb.cyr` | `cyrius run programs/dev/xb.cyr <file.cyr\|file.tcyr>` — build and run one program on x86_64, aarch64 (qemu-aarch64), cx (cxvm) and PE (wine); prints the four exit codes |
| `probe.cyr` | `cyrius run programs/dev/probe.cyr split <dir> <file>` — split a file of `== name` blocks into `<dir>/<name>.cyr` probes |
| `probe.cyr` | `[OLD_CC=<compiler>] cyrius run programs/dev/probe.cyr run <dir>` — compile and run every `<dir>/*.cyr`; with `OLD_CC`, before / after side by side |
| `ab.cyr` | `cyrius run programs/dev/ab.cyr <old_ref> <new_ref> [--runs N]` — A/B self-compile timing of two refs' committed compilers (own sources and same input) |
| `envprobe.cyr` | `cyrius run programs/dev/envprobe.cyr` — a dev machine's inventory (sysctls, limits, locale, binfmt, network); diff two boxes' outputs |
| `keepboth.cyr` | `cyrius run programs/dev/keepboth.cyr [--sep] <file>` — resolve every conflict block by keeping both sides; exits 1 when there was none |
| `fixpoint.cyr` | `cyrius run programs/dev/fixpoint.cyr --install <scratch-dir>` — rebuild `build/cycc` from the source at a fixpoint (c1 = build/cycc(src), c2 = c1(src), c3 = c2(src); c2 == c3 required; build/cycc replaced by an atomic rename); `--fixpoint <scratch-dir>` runs the same stages and check and installs nothing |

`fixpoint.cyr` was `scripts/build-cycc-verify.sh`'s `--install` / `--fixpoint` (the script keeps its verify
mode, CI's trust-root job). It is compiled by a cyrius compiler and checks one: `cyrius run` builds it with
`./build/cycc`, the compiler its c1 stage runs and `--install` replaces. So its verdicts are not its own bytes:
every comparison is an exec of `cmp -s` and every digest of `sha256sum`. To build it independently of
`build/cycc`, from the checkout root:

```sh
~/.cyrius/bin/cycc < programs/dev/fixpoint.cyr > <scratch>/fixpoint && chmod +x <scratch>/fixpoint
<scratch>/fixpoint --install <scratch-dir>
```
