# Stale comments, gate text and doc lines the 6.7.11 lanes left behind (comment / doc only) — RESOLVED

> ✅ **RESOLVED in v6.7.12** (TL-1: items 1–7 corrected in place — lex_pp.cyr's `LEXATTRWORD` home, quality.cyr's bare-`Vec` field rule, the win_cli gate's driver text (only the x86_64 Linux CLI keeps the selectors; TL-30 then rewrote it to the post-fix truth), small_struct_handle_line.sh's floor 266, platform-status.md's Linux x86_64 row (2,223,320 B at 6.7.11, one compaction sentence), the security audit's agnos #109 sentence (time's up is never passed as 0; a 0 still goes over while no clock can time the deadline), and dce_data_vaddr_frozen.sh's mutation ledger re-measured with every RED row per mutant. Item 8 needs no action (commit messages cannot be edited; CHANGELOG [6.7.11] carries the corrected text). Comment / doc only: cycc and the CLI byte-identical, seed-derive OK. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — collected 2026-10-14 by the 6.7.11 release-docs pass, each checked on main 0601aff4. The user,
2026-10-14: "file and fix them in 6.7.12". Every item is comment-, message- or doc-only: cycc stays byte-identical.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Severity:** Low — text that misdescribes the code.

## Items

1. `src/frontend/lex_pp.cyr` lines ~201–202 say `LEXATTRWORD` is "the lexer's own (src/frontend/lex.cyr)"; since
   TL-1 (7c978df8) it lives in `src/frontend/lex_attr.cyr`.
2. `cbt/quality.cyr` ~line 1421 says "(a `Str` / `Vec` FIELD is its 8-byte handle)"; since the tools review fix
   3624e00f a bare `Vec` field is the file's own `struct Vec` when one is declared above it (the guide was updated).
3. `programs/checks/main.cyr`'s registration text for `win_cli_refuses_foreign_targets.sh` says "the Linux CLI keeps all
   three selectors"; the review fix a3d9837d established that only the x86_64 Linux CLI does (the aarch64 Linux CLI
   drops them: `2026-10-14-aarch64-linux-cli-drops-target-selectors.md`). The gate header was corrected, the driver text
   not.
4. `tests/gates/codegen/small_struct_handle_line.sh`'s R2 header comment says "(floor 267)"; since 09875a47 `GFLOOR`
   is 266.
5. `docs/platform-status.md` row 19 says twice that a `kernel;` image / `CYRIUS_WX=0` executable compact since 6.7.11
   (the review fix 71811882's clause and the older trailing sentence), and still cites cycc 2,057,736 B at 6.7.9.
6. `docs/audit/2026-09-03-security-audit.md`'s "Update (6.7.11)" (20c0e160) says the agnos send deadline is "never
   passing 0"; the exact form (the stdlib review) is "time's up is never passed as 0" — 0, meaning no ceiling, still
   goes over in tier 3 or before the RTC arms. Read alone the line claims more than the code does.
7. `dce_data_vaddr_frozen.sh`'s in-file mutation ledger records fewer red rows than the infra handoff measured (the
   handoff ran the gate through a copy whose fail does not exit); the ledger understates, it does not contradict.
8. Commit messages that over-claim cannot be edited; the CHANGELOG carries the corrected text (6538d390's "no two type
   arguments share an instance", 92b690cb's unqualified scalar-annotation sentence, 6cc59858's derive guard,
   42a0b63a's "a `*S` GLOBAL destination is unchanged", 783d795c's "+11").
