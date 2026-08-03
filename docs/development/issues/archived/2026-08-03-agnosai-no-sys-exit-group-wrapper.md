# `lib/` has no `sys_exit_group` wrapper, so every threaded program's exit path is a hand-rolled `syscall()`

> ✅ **RESOLVED in cyrius 6.5.6 (2026-08-03)** — same day as filing, in the W1 reactive
> window. `sys_exit_group` now exists on **all three** syscall peer families, not just
> `syscalls_linux_common.cyr`: Windows and agnos are standalone and would otherwise have
> lacked the name (Windows routes to `SYS_EXIT` because `ExitProcess` already ends every
> thread and 231 has no PE reroute; agnos routes to `SYS_EXIT` because it defines no
> `exit_group`). Both adjacent changes the filing raised were taken: **all seven**
> templates carrying the epilogue were switched — not the two named, the other five were
> found by the new gate's structural axis — and `proj-tcyr` now clamps, closing the
> 256/512/768-failures-score-PASS truncation. `sys_exit`'s doc comment now states it is
> per-thread. Gated by `tests/exit_group_wrapper.sh` (6 axes, mutation-proven; axis 2
> asserts the OLD epilogue still hangs, so the gate cannot silently become a placebo).
>
> ⭐ **The filing understated its own reach.** macOS-x86 resolved `SYS_EXIT_GROUP` to 231
> and `EMACHO_SYSXLAT` had **no 231 entry**, so the constant the filing correctly
> identified as "already present on every Linux target" was a **silent SIGSYS** there —
> silent because the unrouted-syscall warning is arm64-only. Fixed in the same patch
> (`231 → 0x2000001`), which is why this release also touched compiler source and needed
> a fresh seed-derive.

**Status:** ✅ **RESOLVED** — filed 2026-08-03, fixed in 6.5.6 the same day.
**Placement:** shipped in v6.5.6 (W1 reactive window).
**Discovered:** 2026-08-03 while porting agnosai's `main.rs` (the bind bite) to Cyrius.
**Severity:** Medium — hard failure (a hung process) with a known workaround.
**Affects:** cycc 6.5.5 and every earlier 6.x with `lib/syscalls_linux_common.cyr`.

## Summary

`lib/syscalls_linux_common.cyr` wraps `sys_exit` (`exit(2)`) but **not**
`exit_group(2)`, even though the syscall number is defined on every Linux target
Cyrius emits for. `exit(2)` terminates **only the calling thread**. Any program
that has spawned a thread — which on this toolchain means anything using
`thread_create`, `sandhi_server_run_pooled`, or a worker pool — and then exits
through the idiomatic `syscall(SYS_EXIT, code)` epilogue does **not** terminate:
the main thread dies, the remaining threads keep running, and the process hangs
with no diagnostic.

**`cyrius init`'s own templates ship the per-thread call**, so it is the default
a consumer copies and then stops looking at:

- `programs/cyrius-init-templates/main-cyr-bin:11` — `syscall(SYS_EXIT, r);`
- `programs/cyrius-init-templates/proj-tcyr:13` — `syscall(60, exit_code);`
  (the raw number rather than the constant, but the same per-thread `exit(2)`)

The symptom is the worst shape available: it looks like a clean exit right up
until the process does not go away, and it only manifests once a program grows
its first thread — long after the epilogue was written and stopped being looked
at.

## Reproduction

```cyrius
# exit-group-repro.cyr
fn _spin(arg) {
    while (1 == 1) { sleep_ms(1000); }
    return 0;
}

fn main(): i64 {
    alloc_init();
    thread_create(&_spin, 0);
    sleep_ms(100);          # let the worker get going
    println("main returning");
    return 0;
}

var r = main();
syscall(SYS_EXIT, r);       # the idiomatic epilogue
```

Saved as
[`repros/2026-08-03-agnosai-exit-group.cyr`](./repros/2026-08-03-agnosai-exit-group.cyr).
**Build it from inside a project root** — a bare `.cyr` gets no stdlib
auto-prepend, so building it standalone fails on `undefined variable 'SYS_EXIT'`
rather than showing the bug. Any project whose `[deps].stdlib` carries
`syscalls`, `alloc`, `thread`, `io`, `chrono` will do:

```sh
cd <any-project-root>
cyrius build /path/to/2026-08-03-agnosai-exit-group.cyr build/repro
timeout 5 ./build/repro; echo "exit=$?"
```

**Expected:** prints `main returning`, exits 0.
**Actual:** prints `main returning`, then **hangs**; `timeout` reports
`exit=124`.

Verified on cycc 6.5.5, x86-64 Linux, 2026-08-03:

| epilogue | output | exit |
|---|---|---|
| `syscall(SYS_EXIT, r)` | `main returning` | **124 (hung)** |
| `syscall(SYS_EXIT_GROUP, r)` | `main returning` | **0** |

Same binary otherwise — one token changed.

## Root cause

`lib/syscalls_linux_common.cyr` defines `sys_exit` and no `exit_group`
counterpart. The constant is already present on every Linux target:

- `lib/syscalls_x86_64_linux.cyr:83` — `SYS_EXIT_GROUP = 231;`
- `lib/syscalls_aarch64_linux.cyr:101` — `SYS_EXIT_GROUP = 94;`

So this is a missing four-line wrapper, not a missing capability. Note the
constant is deliberately **absent** on agnos
(`lib/syscalls_x86_64_agnos.cyr:23` defines `SYS_EXIT` alone), which is why the
wrapper needs the same `#ifdef` shape the existing per-target helpers use rather
than being unconditional.

## Proposed fix

Add next to `sys_exit` in `lib/syscalls_linux_common.cyr`:

```cyrius
# Terminate every thread in the process, not just the caller.
#
# `sys_exit` is exit(2) and ends ONE thread; a program that has spawned any
# worker and exits through it leaves the process alive with no main thread.
# Prefer this in any program epilogue.
fn sys_exit_group(code): i64 {
    return syscall(SYS_EXIT_GROUP, code);
}
```

Two adjacent changes worth considering in the same pass, both larger calls than
this issue wants to make on its own:

1. **Switch the two `cyrius init` templates** (`main-cyr-bin:11`,
   `proj-tcyr:13`) to `sys_exit_group`. Leaving them means every new project
   starts with the latent bug. Worth noting `proj-tcyr` is a *test* epilogue, so
   it is the less urgent of the two — a suite that spawns no thread is
   unaffected — but it also spells the syscall as a bare `60`, which is its own
   small readability cost.

   While that template is open, it has a **separate** defect worth fixing in the
   same pass: `syscall(60, exit_code)` passes the raw failure count, and the
   kernel truncates a wait status to 8 bits, so exactly 256 / 512 / 768 failing
   assertions exit **0** and score PASS. Consumers already work around it by
   clamping (`if (f > 0) { f = 1; }`); the template should clamp itself.
2. A **doc note on `sys_exit`** stating it is per-thread would have prevented
   this independently of the wrapper.

## Consumer-side workaround

agnosai ships this in `src/main.cyr` (v2.0.0 line, bite 16):

```cyrius
fn _agnosai_exit_process(code): i64 {
    #ifdef CYRIUS_TARGET_LINUX
    syscall(SYS_EXIT_GROUP, code);
    #endif
    syscall(SYS_EXIT, code);
    return 0;
}
```

The guard is load-bearing rather than defensive: `SYS_EXIT_GROUP` is undefined
on agnos, so an unconditional reference fails to build there. On Linux
`exit_group` does not return, making the trailing `sys_exit` dead; off Linux it
is the real path.

Found because `sandhi_server_run_pooled` returns 1 from three sites
(`lib/sandhi.cyr:14192`, `:14203`, `:14213`) and the last two return into a
process with up to 100 live worker threads. Verified: with the plain `SYS_EXIT`
epilogue a bind failure left the process hung; with `exit_group` it exits 1.
