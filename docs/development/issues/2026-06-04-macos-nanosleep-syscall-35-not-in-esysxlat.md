# arm64 macOS: nanosleep (syscall 35) not in ESYSXLAT → consumer runtime fault

- **Filed**: 2026-06-04
- **Reporter**: yantra (downstream consumer; GitHub Actions `macos-15-arm64` runner)
- **Affects**: aarch64-macOS, ≥6.0.63 (surfaced once 6.0.63's dir-walk fix let
  `cyrius lib sync` succeed and the e2e finally reached runtime). **Linux unaffected.**
- **Class**: same as the socket-surface gap (`2026-06-04-macos-net-socket-syscalls-unported.md`)
  and the getdents gap (`2026-06-04-macos-install-lib-snapshot-missing-breaks-lib-sync.md`)
  — an x86/Linux syscall number used by a consumer that the aarch64 macho
  `ESYSXLAT` chain doesn't translate to a Darwin BSD number.

## Symptom

yantra's iOS e2e (`cyrius test` of a `.tcyr` that drives Appium over localhost
HTTP) now **compiles and runs** on the macОС runner (6.0.63 fixed `lib sync`),
but the run dies with **exit code 127** preceded by a flood of:

```
warning: syscall not on Mach-O BSD whitelist (0,1,2,3,9,10,11,60,228); runtime call will fault unless a reroute is added.
```

## Root cause

`ESYSXLAT` (`src/backend/aarch64/emit.cyr`) translates the BSD whitelist + the
v6.0.34/.59/.60/.63 additions (stat, getpid, fcntl, rename, symlink, the socket
surface 41/42/43/48/49/50/54/55, poll 7, getdents 217 & 61, …). It does **not**
translate **`35` (nanosleep)**.

yantra calls it directly in its auto-wait / retry-backoff path
(`src/runtime.cyr`):

```cyrius
fn _yantra_sleep_ms(ms): i64 {
    var ts = alloc(16);
    store64(ts, ms / 1000);
    store64(ts + 8, (ms % 1000) * 1000000);
    syscall(35, ts, 0);   # nanosleep(timespec, NULL)
    return 0;
}
```

The auto-wait poller (`yantra_click`/`yantra_tap` actionability wait) and the
open-retry backoff both reach this, so the e2e hits it early. On aarch64 macОС
the untranslated `35` is emitted as `svc` with a stale `x16` → wrong/garbage BSD
call (the same failure shape that broke sockets pre-6.0.59 and `lib sync`
pre-6.0.63).

## Caveat for the fix — Darwin has no plain `nanosleep` BSD syscall

Unlike the socket surface (clean number renumbers), XNU does **not** expose a
direct `nanosleep` BSD syscall the way Linux does — libsystem implements
`nanosleep` over `__semwait_signal` / `clock_nanosleep`-style primitives. So a
one-line `cmp x8,#35; movz x16,#<n>` renumber may not have a target. Options for
the maintainer:

1. Reroute to a Darwin primitive that *does* exist as a syscall (e.g.
   `__semwait_signal`), with the arg-shuffle that implies — heavier, like the
   `openat→open` / `getcwd→open+fcntl` reroutes already in ESYSXLAT.
2. Provide a libSystem `__got` reroute for `nanosleep` (mirror of the
   `clock_gettime_nsec_np` slot) so consumers' sleeps bind the libc entry.
3. Expose a portable `sleep_ms` in the stdlib (`lib/time.cyr` / `process.cyr`)
   that does the right thing per-OS, and have consumers call that instead of
   raw `syscall(35)`. (yantra would happily switch to a stdlib sleep — that's
   arguably the cleaner long-term contract than every consumer hardcoding 35.)

## Secondary finding — the compile-time warning whitelist is stale

The warning in `src/frontend/parse_expr.cyr` (~line 419) checks a hardcoded set
`{0,1,2,3,9,10,11,60,228}` that no longer reflects what `ESYSXLAT` actually
translates (sockets, poll, getdents, fcntl, rename, …). So it fires for dozens
of syscalls that are in fact rerouted — drowning the log and hiding the *one*
that genuinely isn't (35). Worth syncing that whitelist to the ESYSXLAT-covered
set so the warning means something again. (A real consumer-flow funcgate that
exercises sleep would also have caught this, à la the 6.0.63 dir-walk gate.)

## Repro

- `macos-15-arm64`, cyrius 6.0.63, any `.tcyr` that calls a yantra auto-waiting
  verb (or any program that calls `syscall(35, ts, 0)`): compiles, then faults
  at runtime (exit 127) with the whitelist warning.
- Same source on Linux: runs fine (nanosleep 35 is native).

## Downstream status

yantra's iOS CI job is blocked on this. yantra can switch `_yantra_sleep_ms` to
a stdlib sleep helper the moment one exists that's macOS-correct; until then the
iOS e2e can't run to green on arm64 macOS.
