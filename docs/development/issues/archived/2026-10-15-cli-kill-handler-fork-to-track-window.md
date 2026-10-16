# The CLI's kill handler has a fork-to-track window: a signal between `fork` and `_cbt_child_track` lets one child recreate `<out>.tmp.<pid>` — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-8: every tracked fork now goes through `_cbt_fork_tracked`: compile(), capacity, the distlib per-target spawn and `_dep_wt_run`. It blocks HUP / INT / TERM from before the fork until the child is tracked. The child restores its mask first, so an exec'd tool never starts with those signals blocked; on macOS this goes through 6.7.12's per-thread `__pthread_sigmask` shim. A signal that lands in the window is therefore handled after the track, and stops the child. No decision needed. Rows: `crossos/cli_kill_handler.tcyr` scenario E, where a test-only hook raises SIGTERM inside the window: the child is stopped and reaped, and its late file is never written. Without the block 2 rows go RED, with the child keeping the mask 2 RED, and with the parent keeping it 8 RED. E0 checks both masks are restored. Both run on x86_64, qemu-aarch64, pi, ecb and ach; `_cbt_fork_tracked(0) == -1` on cass and wine. The three fork-site detector gates read the helper as a fork. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — a residual the 6.7.12 tools lane stated and did not file (its handoff: "residual, stated, not
done"), recorded 2026-10-15 by the release-docs pass. TL's kill handler (`cbt/sigclean.cyr`) removes a compile's scratch
and kills its tracked compiler child on SIGTERM / SIGINT; a signal that lands after `fork` and before the child is
tracked leaves that child running, and it can recreate `<out>.tmp.<pid>` after the cleanup.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Low — a narrow race; the reaper's dead-pid rule covers the dir, not the running child.

## Fix

Block the handled signals across `fork` + `_cbt_child_track` (and unblock in the child before `exec`), or track the pid
before the parent can take the signal; a row that delivers the signal inside the window.
