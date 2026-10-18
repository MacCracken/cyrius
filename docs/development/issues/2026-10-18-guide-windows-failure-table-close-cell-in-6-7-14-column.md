# The guide's Windows failure table puts the 6.7.15 close answer in its `Windows 6.7.14` column — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 in the 6.7.15 platform lane's review (branch l6715-platform).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 platform review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — documentation: a reader on 6.7.14 is told `sys_close(-999)` answers -9 there, which it does not
(6.7.14 still answered CloseHandle's BOOL).
**Found:** the review of the lane's 53ab05eef (a PE close answers 0 or a negative errno,
issues/2026-10-16-pe-close-returns-closehandle-bool.md), which added the 6.7.15 answer to an existing per-version
table.

## Reproduction

```sh
grep -n -e 'Call that fails' -e 'sys_close(-999)' docs/guides/cyrius-guide.md
```

```text
7861:| Call that fails | Linux | Windows before 6.7.14 | Windows 6.7.14 |
7867:| `sys_close(-999)` | -9 | 0 (a good close: 1) | -9 since 6.7.15 (a good close: 0) |
```

## Root cause

The table's last column is headed `Windows 6.7.14`; the close row's cell there gives the 6.7.15 answer with a
"since 6.7.15" note. In 6.7.14 the close still answered the BOOL (0 failed, 1 closed), so the cell is wrong for the
version its column names.

## Fix direction

Either head the last column `Windows 6.7.14+` with the close row reading `0 (a good close: 1); -9 since 6.7.15 (a
good close: 0)`, or move the close out of the table into its own sentence below it ("since 6.7.15 a PE close
answers 0 or a negative errno: `sys_close(-999)` -9"). Row: the table's cells each read true for the version their
column names.
