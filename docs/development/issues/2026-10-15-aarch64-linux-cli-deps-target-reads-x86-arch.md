# The aarch64 Linux CLI resolves `[deps.X] target = "x86_64"` and skips `target = "aarch64"` on a plain build — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 tools lane (unit T1) while fixing
issues/archived/2026-10-15-aarch64-linux-cli-win-writes-aarch64-elf-and-aarch64-selectors-need-cross-compiler.md; measured
under qemu-aarch64 with the aarch64 Linux CLI cross-built from the lane's tree (l6713-tools @ e892f018) and from its
base (b13d3598): the same result on both.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane; filed from the 6.7.13 tools lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — the arch axis of a dep's `target` key answers for the WRONG arch on an aarch64 Linux host: a
dependency declared for aarch64 is silently not vendored (its symbols then undefined at the build), and one declared
for x86_64 is vendored and prepended into an aarch64 build. No error, rc 0.
**Affects:** the aarch64 Linux CLI (`cat cbt/cyrius.cyr | cycc_aarch64`), every verb that resolves deps without
`--aarch64`, since `target` was read (v6.3.1 lever 2). The arm64 macOS CLI is unaffected (find_tools / cyrius.cyr set
`_arch = ARCH_AARCH64` there); x86_64 hosts are right.

## Reproduction

```sh
mkdir -p tgt/da/dist tgt/dx/dist tgt/proj tgt/home
printf 'fn da_f(): i64 { return 1; }\n' > tgt/da/dist/da.cyr
printf 'fn dx_f(): i64 { return 2; }\n' > tgt/dx/dist/dx.cyr
cat > tgt/proj/cyrius.cyml <<'EOF'
[package]
name = "tg"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.13"

[deps.da]
path = "../da"
target = "aarch64"
modules = ["dist/da.cyr"]

[deps.dx]
path = "../dx"
target = "x86_64"
modules = ["dist/dx.cyr"]
EOF
cd tgt/proj
# the aarch64 Linux CLI (qemu-aarch64 here; the same code runs on pi)
HOME=$PWD/../home CYRIUS_HOME=$PWD/../home/.cyrius CYRIUS_RESOLVED=1 qemu-aarch64 ./cyrius-aarch64 deps; ls lib
rm -rf lib cyrius.lock
HOME=$PWD/../home CYRIUS_HOME=$PWD/../home/.cyrius CYRIUS_RESOLVED=1 qemu-aarch64 ./cyrius-aarch64 deps --aarch64; ls lib
```

```
actual:   1 deps resolved          (plain: the x86_64 dep)
          dx.cyr
          1 deps resolved          (--aarch64: the aarch64 dep)
          da.cyr
expected: a plain run on an aarch64 host resolves the aarch64 dep (da.cyr) and skips the x86_64 one, as the arm64
          macOS CLI does; --aarch64 the same.
```

## Root cause

`_dep_target_matches` (cbt/deps.cyr) reads the arch axis from `_arch` (0 = x86_64, 1 = aarch64). On the aarch64 Linux
CLI `_arch` stays ARCH_X86 by default: cbt/cyrius.cyr's `set_arch(ARCH_X86)` is overridden only on the arm64 Mach-O CLI,
and 6.7.12's `arch_name` comment records why (ARCH_AARCH64 made `current_cc()` pick cycc_aarch64, an x86_64 binary no
aarch64 host has). 6.7.13 (the issue above) set `_cc_arm = _cc` on that host and guarded the run path's qemu exec off
there, so that obstacle is gone; the arch the deps resolver reads was never part of that issue.

## Proposed fix

Either read the host arch in `_dep_target_matches` (the aarch64 Linux CLI answers aarch64 when `_arch` is the default),
or set `_arch = ARCH_AARCH64` by default on the aarch64 Linux CLI (mirroring the arm64 macOS CLI) now that
`current_cc()` and the run path are host-correct there — then `arch_name`'s aarch64 Linux arm becomes redundant. Row:
the repro above in tests/gates/toolchain/win_cli_refuses_foreign_targets.sh's A axis (qemu), plus pi.
