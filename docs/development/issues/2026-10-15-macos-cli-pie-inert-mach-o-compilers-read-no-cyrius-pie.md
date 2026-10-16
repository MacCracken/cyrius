# `cyrius build --pie` on a macOS host writes the same Mach-O as a plain build at rc 0 — neither Mach-O compiler reads CYRIUS_PIE — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on ecb (macOS arm64) and ach (Intel macOS) with the native Mach-O compilers
cross-built from the 6.7.12 tools lane (l6712-tools, the strict-pin fix applied: `CYRIUS_MACHO_ARM=1 cycc_aarch64 <
src/main_aarch64_macho.cyr`, ad-hoc signed on ecb; `CYRIUS_MACHO=1 build/cycc < src/main_x86_macho.cyr`), and with the
same compilers built from the lane's base (6.7.11's behaviour). Met while fixing
issues/archived/2026-10-10-strict-pin-and-pie-inert-off-linux.md, whose triage noted it "seen in passing, not part of this
filing"; that issue's decision (D5) refuses `--pie` by name on the Windows CLI only.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D43 — (b) Accept on arm64 (already MH_PIE), refuse on x86_64.
**Severity:** Medium — a dropped flag that changes the artifact (the 6.6.5 one-argument rule): `cyrius build --pie` from
the macOS CLI says OK at rc 0 and writes the image a plain build writes, the defect D5 refused on Windows. What `--pie`
should MEAN there differs by arch, measured from the headers cycc writes: the arm64 Mach-O already sets MH_PIE (mach_header
flags 0x00200084), the x86_64 one does not (flags 0x00000001, MH_NOUNDEFS only) — so on Intel the flag drops a real
request, on Apple Silicon it is already met.
**Affects:** the macOS CLIs' `cyrius build --pie` / `CYRIUS_PIE=1` since `--pie` reached the compiler (v6.6.5): the CLI
hands cycc `CYRIUS_PIE=1` (cbt/build.cyr, `_pie_target`), and src/main_x86_macho.cyr / src/main_aarch64_macho.cyr read no
`CYRIUS_PIE` (`grep -c CYRIUS_PIE src/main_x86_macho.cyr src/main_aarch64_macho.cyr` → 0 and 0; src/main.cyr and the
aarch64 Linux forks read it).

## Reproduction

```sh
# on ecb / ach, in a scratch dir, with the native Mach-O cycc as ./cc (codesign -s - -f ./cc on arm64)
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > hello.cyr
./cc < hello.cyr > p0; CYRIUS_PIE=1 ./cc < hello.cyr > p1; echo "rc=$?"; cmp p0 p1 && echo identical
```

```
ecb (Darwin arm64):  rc=0 identical (66044 B)      — base and lane compilers alike
ach (Darwin x86_64): rc=0 identical (8192 B)       — base and lane compilers alike
```

The CLI (`_cli_foreign_target`, cbt/cli_args.cyr) refuses `--pie` only under `#ifdef CYRIUS_TARGET_WIN`
(`_cli_host_refuses_pie`, 6.7.12), so `cyrius build --pie` from either macOS CLI reaches this compiler and reports OK.

## Root cause

The Mach-O compiler forks never grew the `--pie` / `CYRIUS_PIE` read that src/main.cyr (v6.1.6) and the aarch64 Linux
forks (v6.1.8) carry; the macOS CLI passes the variable regardless.

## Proposed fix

The user's call, one of: (a) refuse `--pie` by name on the macOS CLI too (extend `_cli_host_refuses_pie` with a
`CYRIUS_TARGET_MACOS` arm — the D5 shape; tests/gates/toolchain/win_cli_refuses_foreign_targets.sh S4 then expects the
Mach-O CLIs to carry the text); (b) on arm64 accept it by name as already met (MH_PIE) and refuse it on x86_64; or
(c) give the x86_64 Mach-O compiler an MH_PIE mode (a feature). Rows: the probe above on ecb and ach; S4's Mach-O
expectation.
