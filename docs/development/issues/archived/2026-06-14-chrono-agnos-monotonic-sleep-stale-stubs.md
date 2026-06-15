# 2026-06-14 — chrono's agnos monotonic-clock + sleep are stale stubs (don't use uptime_ms#40 / sleep_ms#41)

> **Class:** vendored-stdlib (chrono) gap surfaced by the v6.2.5 AGNOS net-tool
> ports (`dig` 0.3.1, `yo` 0.5.3 now build + RUN on the agnos kernel — `dig`
> resolves a real domain over the #51-54 UDP syscalls, verified by
> `agnos/scripts/net-tool-smoke.sh` 2/2). **Not a v6.2.x blocker** — both tools
> ship working agnos backends; this is a quality/portability gap that makes every
> agnos timing+sleep consumer re-roll the same workaround.
> **Status:** RESOLVED (cyrius-side) v6.2.6. `lib/chrono.cyr`'s AGNOS monotonic
> + sleep branches now bind the real `uptime_ms`#40 / `sleep_ms`#41 syscalls via
> new `sys_uptime_ms`/`sys_sleep_ms` wrappers in `lib/syscalls_x86_64_agnos.cyr`
> (`SysNrAgnosTimer` enum). `agnos-crossbuild-gate.sh` gained a chrono monotonic/
> sleep probe (anti-re-stub guard); emit inspected (`mov eax,40/41; syscall`);
> cross-OS self-host byte-identical ecb/pi/cass; check.sh 89/89. The `dig`/`yo`
> backend migration off their direct-`syscall(40)/(41)` workaround onto the
> portable chrono / `sys_*` API remains the consumer-repo (AGNOS-side) agent's
> follow-up — tracked there, not blocking. See CHANGELOG [6.2.6].

## What

`lib/chrono.cyr`'s AGNOS branches for **monotonic time** and **sleep** are
fixed-zero / no-op stubs, predicated on an obsolete "agnos has no monotonic /
sleep syscall in the frozen 0-33 surface" assumption:

- **`clock_now_ns()`** (~line 13) → `#ifdef CYRIUS_TARGET_AGNOS return 0;` — and
  `clock_now_ms()` (~25) derives from it, so **monotonic time is always 0 on agnos.**
- **`sleep_ms()`** (~97) → falls through to the trailing `# agnos ... no-op` `return 0;`
  — so **`sleep_ms` does not sleep on agnos** (a poll loop that calls it busy-spins).

But AGNOS has had both since kernel **1.43.x**:
- **`uptime_ms` — syscall #40** → monotonic milliseconds since boot (the cyrius-doom
  frame clock `DG_GetTicksMs` already drives it).
- **`sleep_ms` — syscall #41** → blocks ~ms (the cyrius-doom pacing primitive `DG_SleepMs`).

(The *wall-clock* side is already correct — v6.2.3 bound `clock_epoch_secs`/`_ns`
to `sys_time_unix`#46, which is what `tls_native`'s cert-validity check uses. This
issue is **monotonic + sleep only.**)

## Where it bites

The v6.2.5 net-tool agnos backends had to bypass chrono and call the kernel
syscalls **directly** to get correct timing + real sleeps:
- `dig/src/platform_agnos.cyr` — `platform_now_us` = `syscall(40) * 1000`;
  `platform_sleep_ms` = `syscall(41, ms)`; the non-blocking UDP-recv poll loop
  uses `syscall(40)` for the deadline.
- `yo/src/platform_agnos.cyr` — same.

Every future agnos consumer that needs monotonic elapsed-time or a real sleep
(`whirl`, the Docker service-sweep harness's drivers, any retry/backoff/timeout
loop) will re-roll this workaround until chrono's agnos branch binds the syscalls.

## Fix

In `lib/chrono.cyr`, point the agnos branches at the real syscalls:
- `clock_now_ns()` agnos branch → `return syscall(40) * 1000000;` (ms → ns; the low
  6 digits are zero at 10 ms tick resolution, the same shape as the agnos
  `clock_epoch_ns` v6.2.3 sub-second-zero note). `clock_now_ms()` then works for free.
- `sleep_ms()` agnos branch → `syscall(41, ms); return 0;` (replace the no-op
  fall-through with a real sleep; guard `ms <= 0`).

Recommended companion (cleaner than raw `syscall(40)/(41)` at call sites): add
`sys_uptime_ms()` (#40) + `sys_sleep_ms(ms)` (#41) wrappers to
`lib/syscalls_x86_64_agnos.cyr` (the `SysNrAgnos*` enum carries #45-#57 from the
v6.2.3 net peer; #40/#41 are older kernel syscalls not yet wrapped there), and
have chrono call those. Then the net-tool backends can drop their direct-syscall
workaround and use the portable chrono API.

## Verify

After the fix, the agnos net-tool backends should build + run identically with
their `syscall(40)/(41)` lines replaced by `chrono.clock_now_*` / `chrono.sleep_ms`
(or the new `sys_uptime_ms`/`sys_sleep_ms`). The end-to-end check is
`agnos/scripts/net-tool-smoke.sh` (still 2/2 — dig resolves `example.com`). The
agnos cross-build gate (`scripts/agnos-crossbuild-gate.sh`) should stay green.

## Related

- `2026-06-14-sandhi-nonblocking-connect-not-agnos-ported.md` (sibling agnos-peer gap)
- The v6.2.3 AGNOS net/entropy/clock peer (CHANGELOG) — bound #45-#55 + `time_unix`#46
  for wall-clock; this is the **monotonic/sleep** counterpart it didn't cover.
- AGNOS-side proposal: `agnos`/`cyrius/docs/development/proposals/2026-06-14-agnos-net-entropy-clock-syscalls.md`.
