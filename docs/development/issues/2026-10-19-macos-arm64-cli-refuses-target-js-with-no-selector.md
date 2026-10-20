# On arm64 macOS `cyrius build --target=js x.ts out.js` (no target selector) is refused: "runs this host's cycc, not the compiler another target selector chose" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 libfix lane (unit L3) while running the closed-std-fd
rows on ecb; measured with the INSTALLED 6.7.15 CLI on ecb (`~/.cyrius/bin/cyrius`, read only) and with a CLI
cross-built from the lane tree (l6716-libfix, after c86336672). Not touched by the lane's redirect fix: the
refusal happens before any fork.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 libfix lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; t16 lane, wave 3, unit TT3) — never 7.x.
**Severity:** Medium — a documented verb does not work at all on one host family (Apple Silicon); exit 1 with a
message that blames a target selector the user did not pass. No boundary is crossed.

## Reproduction

On ecb (macOS arm64), in any scratch directory:

```sh
printf 'const x: number = 1;\nconsole.log(x);\n' > x.ts
~/.cyrius/bin/cyrius build --target=js x.ts out.js; echo "rc=$?"
~/.cyrius/bin/cycc_aarch64 --emit-js x.ts; echo "rc=$?"     # the compiler itself can do it
```

```text
error: build --target=js runs this host's cycc, not the compiler another target selector chose
rc=1
const x = 1;
console.log(x);
rc=0
```

The same with a CLI cross-built from the tree (`CYRIUS_MACHO_ARM=1 build/cycc_aarch64 < cbt/cyrius.cyr`) and
`cycc` / `cycc_aarch64` beside it: rc 1, the same line. x86_64 Linux, aarch64 Linux (pi) and x86_64 macOS (ach)
emit the 29-byte out.js with rc 0.

## Root cause

cbt/build.cyr `_js_cc_is_host()` (6.7.12, D20's "one emit target per run") is `current_cc() == _cc`. On arm64
macOS `find_tools()` (cbt/core.cyr) sets `_arch = ARCH_AARCH64` by default — the native Mach-O compiler there is
named `cycc_aarch64` — so `current_cc()` answers `_cc_arm`, while `_cc` is the `cycc` beside the CLI (the install
ships both, byte-identical, at different paths). The js arm therefore reads the HOST's own default as "another
target selector chose a different compiler" and refuses. `tests/gates/toolchain/target_selectors_exclusive.sh`
and `emit_js_per_host_fork.sh` run on Linux only (the latter evaluates `_target_cc_has_js()` under the macOS
macro sets, never `_js_cc_is_host()` with the arm64-macOS `_arch` default), so nothing pinned it.

## Fix direction

The js arm needs "did the USER pick a target" (an explicit `--aarch64` / `--win` / `--agnos` / `--target=` on this
run, which `_cli_apply_target` knows), not "is current_cc() the x86 slot". A row on ecb: the verbatim repro above
→ rc 0 and a 29-byte out.js; `--aarch64 --target=js` still refused by name (D20). What the arm should do with an
explicit `--aarch64` on an arm64 Mac (where it selects the host's own compiler) is the user's call if it is not
already settled by 6.7.12's D20.
