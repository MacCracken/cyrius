# On a macOS host, `cyrius build --win` writes a Mach-O named `.exe` at rc 0 — neither Mach-O compiler reads CYRIUS_TARGET_WIN — RESOLVED

> ✅ **RESOLVED in v6.7.14** (TL-1, `c7ebef693`: the macOS CLIs refuse `--win` by name. No new decision: the user's 2026-10-13 rule (6.7.11's D30: a target the host's compiler cannot emit is refused by name), as 6.7.13 applied it to the aarch64 Linux CLI. `_cli_host_refuses_win` gains a `CYRIUS_TARGET_MACOS` arm with `_cli_host_emits_only()`'s text, and `_cli_foreign_target` asks it before anything resolves or compiles. The filed `../cyrius build --win hello.cyr w.exe` now gives, on ecb and on ach, `error: --win is not available from the macOS CLI: cycc emits Mach-O only (build PE images on x86_64 Linux or Windows)`, rc 1, and no w.exe (an existing one is left as it was); `run --win` is refused the same way. It gave `[aarch64] OK (66480 bytes)` / `[x86_64] OK (8192 bytes)` at rc 0, a Mach-O (`cf fa ed fe`) named `.exe`. A plain build is unchanged. The filing's alternative, a PE-emitting compiler shipped for macOS hosts, was not taken. Rows: `win_cli_refuses_foreign_targets.sh` S6 / S6m (mutation M16 RED), `cross-os-selfhost.sh`'s ecb and ach WIN rows (RED on the pre-fix CLI on ach), `crossos/cli_host_win_refusal.tcyr` (macOS now expects 1). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on ecb (macOS arm64) and ach (Intel macOS) by the 6.7.13 tools lane
(unit T1), with the macOS CLIs and native Mach-O compilers cross-built from the lane's tree (l6713-tools @ a1e0c0fb)
and from its base (945e70c7, 6.7.12's behaviour): identical on both. Named "met in passing, not measured" by the
6.7.13 triage of issues/archived/2026-10-15-aarch64-linux-cli-win-writes-aarch64-elf-and-aarch64-selectors-need-cross-compiler.md
(its Risk line); that issue refuses `--win` on the aarch64 Linux CLI only, so the macOS CLIs are outside its surface.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane, wave 1, unit T1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** High — a dropped target selector that changes the artifact (the 6.6.5 one-argument rule's defect, the
class 6.7.11 / D6 / 6.7.13 refused by name on the other hosts): the requested PE is not written, a Mach-O named
`w.exe` is, and the CLI says OK at rc 0.
**Affects:** the macOS CLIs (`CYRIUS_MACHO=1 cycc < cbt/cyrius.cyr`, `CYRIUS_MACHO_ARM=1 cycc_aarch64 < cbt/cyrius.cyr`)
since `--win` reached the compiler as CYRIUS_TARGET_WIN=1.

## Reproduction

```sh
# on x86_64 Linux, from the tree:
cat src/main_aarch64.cyr | ./build/cycc > cc_x && chmod +x cc_x
CYRIUS_MACHO_ARM=1 ./cc_x < src/main_aarch64_macho.cyr > ecb/cycc; cp ecb/cycc ecb/cycc_aarch64
CYRIUS_MACHO_ARM=1 ./cc_x < cbt/cyrius.cyr > ecb/cyrius
CYRIUS_MACHO=1 ./build/cycc < src/main_x86_macho.cyr > ach/cycc
CYRIUS_MACHO=1 ./build/cycc < cbt/cyrius.cyr > ach/cyrius
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > hello.cyr
# on the host, in a scratch dir holding its CLI + compiler (ecb: codesign -s - -f each), HOME / CYRIUS_HOME throwaway:
../cyrius build --win hello.cyr w.exe; echo "rc=$?"; od -An -tx1 -N4 w.exe; ./w.exe; echo "exit=$?"
```

```
ecb:  compile hello.cyr -> w.exe [aarch64] OK (66480 bytes)
      rc=0
      cf fa ed fe          <- an arm64 Mach-O (flags 0x00200084), not a PE
      exit=7
ach:  compile hello.cyr -> w.exe [x86_64] OK (8192 bytes)
      rc=0
      cf fa ed fe          <- an x86_64 Mach-O, not a PE
      exit=7
expected: refused by name, rc 1, nothing written (the user's 2026-10-13 rule: a target the host's compiler cannot emit
          is refused by name), as the aarch64 Linux CLI refuses `--win` since 6.7.13 — or, a decision, a PE-emitting
          compiler shipped for macOS hosts (distribution work).
```

## Root cause

compile() injects CYRIUS_TARGET_WIN=1 for the host compiler (cbt/build.cyr); src/main_x86_macho.cyr and
src/main_aarch64_macho.cyr read no CYRIUS_TARGET_WIN (`grep -c CYRIUS_TARGET_WIN` → 0 in both), so each writes its own
format. `_cli_foreign_target` (cbt/cli_args.cyr) refuses `--win` only through `_cli_host_refuses_win`, which answers on
the aarch64 Linux CLI alone; `_cli_host_emits_only()` already names the macOS CLI ("the macOS CLI: cycc emits Mach-O
only").

## Proposed fix

`_cli_host_refuses_win` gains a CYRIUS_TARGET_MACOS arm (both Macs) using `_cli_host_emits_only()`'s text:
`error: --win is not available from the macOS CLI: cycc emits Mach-O only (build PE images on x86_64 Linux or Windows)`.
Rows: tests/gates/toolchain/win_cli_refuses_foreign_targets.sh S6 (the Mach-O CLIs then carry the `--win` refusal) and
the probe above on ecb and ach (rc 1, no w.exe).
