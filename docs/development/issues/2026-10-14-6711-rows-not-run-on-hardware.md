# 6.7.11 rows the issues asked to run on hardware that only run under emulation (or not at all) — OPEN

**Status:** 🟡 **OPEN** — collected 2026-10-14 by the 6.7.11 release-docs pass. The release gate's hardware leg runs
`tests/tcyr/crossos/` only (ecb · ach · cass · pi, all `SELFHOST_OK` + `LIBTEST_OK` at 6.7.11), so a row that lives in
a shell gate runs under qemu / wine / cxvm only. The user, 2026-10-14: "file and fix them in 6.7.12".
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 integration; the platform release runs the hosts at slot one) —
never 7.x.
**Severity:** Low — coverage, not a known defect.

## Items

1. **The top-level `return` refusal** (GF-9, `issues/archived/2026-10-12-top-level-return-decision.md`): the issue asked
   for rows on "aarch64 (qemu, then pi)" and "PE (wine, then cass)". `toplevel_return_checked.sh` runs qemu and wine
   only; a refusal is host-independent, but the accepted controls (a fn's `return` beside it) never ran on pi / cass.
   Fix: a `tests/tcyr/crossos/` control row.
2. **The three new agnos wrappers** (`sys_console_mode`, `sys_fd_kind`, `sys_sock_send_dl`; LIB-4..6) have no
   `tests/tcyr/crossos/` companion (CLAUDE.md: every new syscall wrapper gets one). No cross-OS host runs agnos; their
   rows are `agnos_peer_fake_kernel.sh` axes 10–12 against a fake kernel, and #109's real-kernel leg (the issue's
   compatibility section) never ran. Decide: a crossos file that compiles them for agnos and skips by name off agnos,
   or record the exception in the guide's crossos rule.
3. **The coroutine rows of the await and closure-field issues** (GF-16, GF-15) are x86_64-only: aarch64 and cx refuse a
   mid-body `await` / `suspend` by name, so the issues' qemu-aarch64 / cxvm coroutine rows cannot exist. Recorded in
   the banners; nothing to fix unless those targets gain mid-body await.
4. **The struct lane's operator, return-shape and derive bites** (the 14 commits after 2f5387e5) ran on ecb / ach / cass
   / pi only through the release gate's crossos leg, not per bite; their shell-gate rows (`small_struct_handle_line.sh`
   legs, `struct_copy_source_type_refused.sh`) run on emulators. A crossos sweep of those rows at the platform release.
