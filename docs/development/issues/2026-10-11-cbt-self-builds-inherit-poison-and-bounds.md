# `cyrius pulsar` and the CLI's on-demand cx builds hand an inherited `CYRIUS_POISON` / `CYRIUS_BOUNDS` to the compiler they build — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-11 from the 6.7.9 quick lane (bite 10). That bite added the scrub to every
self-build SCRIPT. The same leak in the CLI (cbt/) did not fit in it: a cyrius-side environment filter on two POSIX
exec sites, the Windows spawn arm, and a behavioural gate with a stub compiler on Linux and under wine.
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *The releases after 6.7.8*; `cbt/pulsar.cyr` / `cbt/build.cyr`, the Windows arm under wine, then cass) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's self-build scrub
([the scripts issue](2026-10-10-self-build-scripts-inherit-poison-and-bounds.md)), by looking for every OTHER place
that builds a `src/main*.cyr` fork. Verified with the repro below on the quick lane's tip.
**Severity:** High. This is the scripts issue's class: a wrong artifact with no diagnostic. `CYRIUS_POISON=1 cyrius
pulsar` rebuilds the TRACKED `build/cycc` as a poison-mode compiler. Its stage 1 and stage 2 agree, so the self-host
check passes. `scripts/install.sh --refresh-only` then copies that `build/cycc` into the store as it is: cycc is never
rebuilt there. The 6.7.9 install.sh scrub cannot help, because the compiler was built before install.sh ran. This is
a bug, not a ledger id: the variable is the developer's own shell.
**Affects:** `CYRIUS_POISON` since 6.5.29 and `CYRIUS_BOUNDS` since 6.7.8, through the 6.7.9 quick lane's tip.

## Summary

The CLI passes its own environment (`_envp`) to every child, and two of its children are compilers built from the
checkout:

| Site | Builds | Where it goes |
|---|---|---|
| `cbt/pulsar.cyr` `_pulsar_raw_compile` (`sys_execve(cc, &argv, _envp)`, :61) | `src/main.cyr` twice (or three times), then `src/main_aarch64.cyr` and `src/main_aarch64_native.cyr` | over the tracked `build/cycc` and `build/cycc-native-aarch64`, then into the store through `install.sh --refresh-only` |
| `cbt/pulsar.cyr` step 3, `compile()` | `programs/{cyrfmt,cyrlint,cyrdoc,ark}.cyr` and `cbt/cyrius.cyr` | `build/`, then the store (a fresh `build/<tool>` is installed as it is) |
| `cbt/build.cyr` `_cx_jit_build` (`sys_execve(cc, &argv, _envp)`, :189), called by `_ensure_cc_cx` and `_ensure_cxvm` | `src/main_cx.cyr` → `./build/cycc_cx` and `programs/cxvm.cyr` → the cx VM, on first cx use in the checkout | `build/`, kept and reused; `install.sh --refresh-only` installs a fresh `build/cycc_cx` as it is |

A user's program is a different case. When `cyrius build` / `test` / `fuzz` compiles the user's program, the
variables reaching cycc is the intended behaviour (`--poison` / `--bounds` inject them on purpose). Only these
compiler and tool self-builds must not see them.

## Reproduction

`docs/development/issues/repros/2026-10-11-cbt-self-builds-inherit-poison-and-bounds.sh`. Run it from the repo root
with `sh <repro>`. It builds the CLI from `cbt/cyrius.cyr` into a mktemp directory. It runs `cyrius pulsar` and
`cyrius build --target=cx` in scratch repos whose `build/cycc` is a stub. The stub logs the two variables and emits
itself. HOME and CYRIUS_HOME are throwaways, and pulsar stops at its install step, so no store is touched:

```
what each compiler child saw (CYRIUS_POISON=1 CYRIUS_BOUNDS=1 inherited):
  pulsar self-build: POISON=1 BOUNDS=1
  pulsar self-build: POISON=1 BOUNDS=1
  cx compiler build, then x.cyr: POISON=1 BOUNDS=1
  cx compiler build, then x.cyr: POISON=1 BOUNDS=1
pulsar installed its self-build over the scratch build/cycc
```

The cx run's first line is the `cycc_cx` build, a self-build that must read `unset`. Its second line is `x.cyr`, the
user's program, which keeps the variables.

## Root cause

Both exec sites pass `_envp` unchanged. `_envp` is the CLI's environment, read from `/proc/self/environ`, or the
kernel's entry envp on macOS. Found by reading, not run: the Windows arm of `_cx_jit_build` (`_win_compile_spawn`,
build.cyr:172) spawns through cmd.exe with the CLI's own process environment. An inherited pair reaches it the same
way. compile()'s Windows arm also WRITES `CYRIUS_BOUNDS` / `CYRIUS_POISON` onto that environment
(`_cc_win_env_apply`, build.cyr:1640) for `--bounds` / `--poison`, so a later cx self-build in the same process would
inherit them too. `cyrius pulsar` itself refuses off an x86-64 Linux host (`_pulsar_host_is_x86_linux`), so pulsar has
only the POSIX arm.

## Proposed fix

1. A `cbt/core.cyr` helper that returns `_envp` without its `CYRIUS_POISON=` / `CYRIUS_BOUNDS=` entries. `cmd_pulsar`
   uses it for the whole verb (the raw compiles, compile()'s tool builds, the install step), and `_cx_jit_build`'s
   POSIX child uses it.
2. The Windows arm of `_cx_jit_build`: save the two variables, clear them on the process around `_win_compile_spawn`
   (`SetEnvironmentVariableA(name, NULL)`), then restore them.
3. A toolchain gate built from this repro: on Linux, the stub's log shows `unset` for every self-build line and the
   pair for the user's `x.cyr`. Under wine, the same check for the cx build with a PE stub. A mutation of each site
   must turn the gate RED.

## Consumer-side workaround

Run `cyrius pulsar` and the first cx use in a checkout with neither variable set:
`env -u CYRIUS_POISON -u CYRIUS_BOUNDS cyrius pulsar`.
