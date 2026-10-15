# The CLI's kill handler has a fork-to-track window: a signal between `fork` and `_cbt_child_track` lets one child recreate `<out>.tmp.<pid>` — OPEN

**Status:** 🟡 **OPEN** — a residual the 6.7.12 tools lane stated and did not file (its handoff: "residual, stated, not
done"), recorded 2026-10-15 by the release-docs pass. TL's kill handler (`cbt/sigclean.cyr`) removes a compile's scratch
and kills its tracked compiler child on SIGTERM / SIGINT; a signal that lands after `fork` and before the child is
tracked leaves that child running, and it can recreate `<out>.tmp.<pid>` after the cleanup.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; filed from the 6.7.12 release-docs pass, 2026-10-15) — never 7.x.
**Severity:** Low — a narrow race; the reaper's dead-pid rule covers the dir, not the running child.

## Fix

Block the handled signals across `fork` + `_cbt_child_track` (and unblock in the child before `exec`), or track the pid
before the parent can take the signal; a row that delivers the signal inside the window.
