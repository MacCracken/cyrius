# `crossos/regression_terminate_children.tcyr` asserts wall-clock bounds and failed once on ach — OPEN

**Status:** 🟡 **OPEN** — not re-verified on hardware (needs ach). Verified 2026-10-08 against 6.7.6 @ 2fb6ad8b that the
test still asserts the three wall-clock bounds below (read), and that it passes 3 of 3 on this Linux box (compiled with
the tree's `build/cycc`, 14 passed). The 6.7.6 record (CHANGELOG [6.7.6] gate line; `state.md` Gates row): the first
release-gate run (21:43) was RED on ach alone with this test, then 11 of 11 passes on ach (eight exactly as the runner
runs it) and a GREEN re-run. Which assertion failed was not recorded.
**Placement:** 6.7.7 (being fixed in this release) — never 7.x.
**Discovered:** 2026-10-08, the 6.7.6 release gate's cross-OS leg on ach (Intel Mac); filed 2026-10-08 from roadmap.md
(the CHANGELOG's "Filed:" meant that backlog line; no issue file existed, open or archived).
**Severity:** Low — an intermittent RED on one release-gate host; no product defect is indicated.
**Affects:** the test as of 6.6.11 (the deadline group) through 6.7.6.

## Summary

The test pins `lib/regression.cyr`'s `regression_terminate_children` / `regression_reap_orphans` /
`regression_run_with_timeout` contracts with real processes and the wall clock. Three rows depend on scheduling
latency on a loaded host:

1. `tests/tcyr/crossos/regression_terminate_children.tcyr:69` — `regression_terminate_children(3000)` must return in
   `< 1000` ms (off Linux: at once; the child it must NOT wait for sleeps 1,500 ms, `:57-59`).
2. `:104` — `regression_reap_orphans()` must return in `< 1000` ms while a second child sleeps 1,500 ms (`:99`).
3. `:129-142` — `regression_run_with_timeout(scr, 600, …)` must hit its 600 ms deadline (`-2`) AFTER the `/bin/sh`
   script has started `/bin/sleep 30 &` and written its pid (`:132`, "premise: the script recorded its background
   child"), then the background child must be gone within 150 × 20 ms polls. On a busy Intel Mac a cold `sh` + `sleep`
   fork + `echo $! >` inside 600 ms is the tightest of the three (speculation — the failing row is unknown).

## Reproduction

Hardware-only: run the cross-OS leg on ach under load (the release gate runs the four legs beside check.sh). Locally:

```sh
cat tests/tcyr/crossos/regression_terminate_children.tcyr | build/cycc > /tmp/rtc && chmod +x /tmp/rtc && /tmp/rtc
# Linux: 14 passed, 0 failed (3 of 3)
```

## Root cause

Absolute wall-clock thresholds close to the work's real latency on a slow host: 1,000 ms against a 1,500 ms
discriminating sleep (only 500 ms of headroom on the "it waited" side, and none of the run's own fork / scheduling
noise accounted for), and a 600 ms deadline that also has to cover the script's start-up.

## Proposed fix

Keep each row's discrimination, widen its margin: make the "must not wait for it" children sleep much longer (e.g.
10 s, killed at the end) so the "returned at once" threshold can sit at several seconds; give the deadline group a
deadline long enough for the script to record its pid (or have the script signal readiness — e.g. poll for the pid
file — before the deadline is armed), while still requiring `-2`. Print which row failed and its measured elapsed
time, so the next flake names itself.

## Note from the 6.7.7 fix

The first run of a freshly written executable on ach costs ~370 ms (macOS checks a new executable), and concurrent
first runs queue (4 at once: up to ~1.7 s). Other `crossos/` tests that write and run a new script or binary under a
tight deadline can flake on ach the same way; none was surveyed.
