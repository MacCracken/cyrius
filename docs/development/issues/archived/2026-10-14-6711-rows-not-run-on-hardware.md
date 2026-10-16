# 6.7.11 rows the issues asked to run on hardware that only run under emulation (or not at all) — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-10, `db5774f2`: item 1 — NEW `tests/tcyr/crossos/toplevel_return_controls.tcyr` carries `toplevel_return_checked.sh`'s C1–C5 controls (7 rows); item 2 — the agnos-only wrappers (`sys_console_mode`, `sys_fd_kind`, `sys_sock_send_dl`) are a recorded exception in the guide's § The portable `x*` wrapper set, their companion `agnos_peer_fake_kernel.sh` axes 10–12 and #109's real-kernel leg named "cannot run: no agnos host" (D14, the user 2026-10-15); item 3 — nothing to fix (aarch64 and cx refuse a mid-body `await` by name); item 4 — the struct lane's accepted shapes as NEW `crossos/struct_return_shape_controls.tcyr` (12), `struct_operator_controls.tcyr` (7) and `struct_copy_source_controls.tcyr` (12), and `derive_nested_scanner.tcyr` moved into `crossos/`. ecb, ach, cass and pi each SELFHOST_OK and 298 passed, 0 failed on the crossos leg. The refusal rows and the int + f64 single-warning row stay in their shell gates (host-independent); the sweep covers the slot-open shapes. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — collected 2026-10-14 by the 6.7.11 release-docs pass. The release gate's hardware leg runs
`tests/tcyr/crossos/` only (ecb · ach · cass · pi, all `SELFHOST_OK` + `LIBTEST_OK` at 6.7.11), so a row that lives in
a shell gate runs under qemu / wine / cxvm only. The user, 2026-10-14: "file and fix them in 6.7.12".
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D14 — a recorded exception for the agnos-only wrappers.
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
