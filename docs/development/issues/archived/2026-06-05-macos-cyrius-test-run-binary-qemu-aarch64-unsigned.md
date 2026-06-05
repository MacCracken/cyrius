# `cyrius test`/`run` exit 127 on native Apple Silicon — `run_binary` routes through `qemu-aarch64`, and the tmp binary is never codesigned

> **Status**: ✅ RESOLVED in v6.0.66 (cbt wrapper-only; cycc unchanged). Both stacked bugs fixed in
> `cbt/build.cyr`: **Bug 1 (the 127)** — gated `run_binary`'s qemu-aarch64 branch `#ifndef
> CYRIUS_TARGET_MACOS` so a native Mach-O host execs directly (no missing-qemu execve-fail). **Bug 2 (the
> 137)** — hoisted the v6.0.38 ad-hoc codesign into a shared `_macho_codesign()` called inside
> `run_binary`, so test/run/bench/fuzz/doctest all sign (cmd_build DRY'd to it). Proof: `cyrius test
> smoke.tcyr` on ecb → `1 passed`. See CHANGELOG [6.0.66].

- **Filed**: 2026-06-05
- **Reporter**: yantra (downstream consumer; GitHub Actions `macos-latest` / Apple-Silicon runner, iOS/XCUITest e2e job)
- **Affects**: 6.0.65 (and earlier — the `run_binary` qemu branch predates it). **Linux is unaffected.**
- **Platform**: native macOS arm64 (hosted GitHub runner). **Does not repro on `ecb`** — see "Why ecb is green" below.

## Symptom

`cyrius test <file>.tcyr` on a native arm64-macOS runner fails with **exit code
127** and produces **no test output at all** (no `=== name ===`, no pass/fail
counts). The compile clearly succeeds — the last line before the failure is the
normal `note: NNNN unreachable fns (… bytes …)` — and then the step dies:

```
note: 1094 unreachable fns (398072 bytes — set CYRIUS_DCE=1 to eliminate …)
Error: Process completed with exit code 127.
```

The large flood of `warning: syscall not routed by the Mach-O ARM translation
(ESYSXLAT/__got); will fault on macOS` lines above it is the known
uncalled-stdlib-helper noise (`parse_expr.cyr` demoted it to a warning for
exactly that reason) and is **not** the cause here.

## Root cause — two stacked bugs in `cbt`

### Bug 1 (produces the literal 127): `run_binary` runs aarch64 output under `/usr/bin/qemu-aarch64` even on a native arm64 host

`cbt/build.cyr:236` `run_binary(path)`:

```
if (_arch == ARCH_AARCH64) {
    store64(&argv, "/usr/bin/qemu-aarch64");
    store64(&argv + 8, path);
    store64(&argv + 16, 0);
    sys_execve("/usr/bin/qemu-aarch64", &argv, _envp);
    sys_exit(127);            // <-- execve failed → child exits 127
}
```

The qemu branch is a **cross-run** convenience: run aarch64 output on an **x86**
host via the QEMU linux-user emulator. But on a **native** Apple-Silicon host
there is no `/usr/bin/qemu-aarch64`, so `sys_execve` returns `ENOENT` and the
child falls through to the literal `sys_exit(127)`. The parent
(`WIFEXITED → WEXITSTATUS`) returns **127**.

It takes this branch unconditionally because `_arch` is forced to `AARCH64` on
arm64-macOS at `cbt/core.cyr:232` (`find_tools()`):

```
#ifdef CYRIUS_TARGET_MACOS
#ifdef CYRIUS_ARCH_AARCH64
    _arch = ARCH_AARCH64;
#endif
#endif
```

So `_arch == ARCH_AARCH64` is conflating *target arch* with *needs-emulation*.
On a native arm64 host (host == target) the binary should be exec'd **directly**;
qemu is only correct when host ≠ target (x86 host, aarch64 target).

This matches every symptom exactly: the exit code is **precisely 127** (the
`sys_exit(127)` literal, not `128+9=137` from a signal), there is **zero test
output** (the test binary never executes), and it is **only** on the macOS
runner (the Linux jobs run an x86 cycc, `_arch != AARCH64`, so they exec
directly and never touch qemu).

### Bug 2 (the next domino): `cmd_test`/`cmd_run`/`cmd_bench`/`cmd_fuzz` never ad-hoc codesign the tmp binary

`cmd_build` already self-signs its output (`cbt/commands.cyr:48-57`, added in
6.0.38):

```
#ifdef CYRIUS_TARGET_MACOS
// Apple Silicon AMFI-SIGKILLs an unsigned arm64 binary … Sign it now …
var _cs = str_builder_new();
str_builder_add_cstr(_cs, "codesign -s - -f ");
str_builder_add_cstr(_cs, output);
str_builder_add_cstr(_cs, " 2>/dev/null");
sys_system(str_data(str_builder_build(_cs)));
#endif
```

But `cmd_run` (`commands.cyr:66`), `cmd_test` (`:85`), `cmd_bench`
(`_bench_run_one`), and `cmd_fuzz` all compile to a `/tmp/cyrius_*` path and call
`run_binary(tmpbin)` with **no** codesign step. So even after Bug 1 is fixed to
exec natively, the unsigned `/tmp/cyrius_test_bin` would be **AMFI-SIGKILL'd**
(→ `run_binary` returns `128+9 = 137`). Both bugs must be fixed for `cyrius test`
to actually pass on Apple Silicon.

## Repro

On a native arm64-macOS host with the arm64-macos toolchain installed:

```sh
printf 'fn main(): i64 { syscall(60, 0); return 0; }\n' > /tmp/t.tcyr   # any trivial test
cyrius test /tmp/t.tcyr        # -> exit 127, no test output
# Direct evidence of Bug 1:
ls /usr/bin/qemu-aarch64       # -> No such file or directory  (on a native host)
```

`cyrius build /tmp/t.tcyr /tmp/t && /tmp/t; echo $?` works (build self-signs,
and `cyrius build` doesn't go through `run_binary`), which isolates the failure
to the test/run path.

## Why `ecb` is green but the hosted runner 127s

Either `ecb` has a `/usr/bin/qemu-aarch64` present (qemu-user happily runs a
native-arch binary too, so the qemu detour is invisible there), or the last
green iOS e2e on `ecb` predates this qemu branch (≤ 6.0.59). The hosted runner
has neither qemu nor a relaxed AMFI, so both bugs surface. This is the recurring
"works on ecb, fails on the hosted runner — the runner is the real test" pattern.

## Suggested fix (both in `cbt`)

1. **`run_binary` (`cbt/build.cyr:236`)** — only use `qemu-aarch64` when the host
   can't natively exec the target. On macOS the host arch always matches the
   target (there is no aarch64-on-x86 macOS cross-*run* path), so exec directly:

   ```
   #ifdef CYRIUS_TARGET_MACOS
       store64(&argv, path); store64(&argv + 8, 0);
       sys_execve(path, &argv, _envp);
       sys_exit(127);
   #else
       // Linux: qemu only when host x86 + target aarch64 (true cross-run)
       if (_arch == ARCH_AARCH64) { …qemu… }
       …direct…
   #endif
   ```
   (Or gate the qemu branch on an explicit host≠target check rather than on
   target arch alone.)

2. **`cmd_run`/`cmd_test`/`cmd_bench`/`cmd_fuzz`** — ad-hoc codesign the tmp
   binary on macOS before `run_binary`, identical to `cmd_build`. Cleanest: hoist
   cmd_build's codesign block into a shared helper (e.g. `macho_adhoc_sign(path)`)
   and call it from all five compile→run sites.

## Note for the self-host / funcgate gate

The self-host gate never hits this because it doesn't `run_binary` arm64 output
on a native arm64 host. A functional gate that does `cyrius test` of a trivial
`.tcyr` on the arm64-macos build would have caught both bugs (127 on Bug 1; 137
once Bug 1 is fixed but Bug 2 isn't).

## Downstream status (yantra)

yantra's iOS e2e (`cyrius test tests/e2e/ios-appium-smoke.tcyr` on `macos-latest`)
is blocked on this. Separately, yantra fixed a real correctness bug surfaced
while chasing this — `_yantra_sleep_ms` was calling raw `syscall(35)`, which on
aarch64-macho is `unlinkat` (routed), not nanosleep, so its auto-wait never
actually slept on macOS; it now uses `poll` (`syscall(7)`, routed `7→230`). That
is independent of this issue and does **not** unblock the iOS e2e — this `cbt`
fix does. Do not archive until yantra confirms the iOS job green on a toolchain
carrying the `run_binary` + codesign fixes.
