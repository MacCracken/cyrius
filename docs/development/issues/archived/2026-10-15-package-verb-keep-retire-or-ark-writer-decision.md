# `cyrius package`: keep it, retire it, or give it an `.ark` writer? — RESOLVED

> ✅ **DECIDED at the 6.7.13 open — no change** (the user, 2026-10-15: "ark is a REAL REPO PACKAGE MANAGER… PACKAGE IS FOR IT… LEAVE IT ALONE FOR NOW"). `cyrius package` stays as it is; its shape comes with ark's work. Nothing to implement.

**Status:** ✅ **DECIDED — no change** (see the banner). Was: 🟡 **OPEN** — a decision for the user, carried from `archived/2026-10-12-package-missing-entry-reports-ready.md`,
whose one-line question (keep / retire / give `package` an `.ark` writer) was not asked at the 6.7.12 open; its defect
(a missing entry reported "ready") shipped fixed in 6.7.12 and the fix holds under any answer.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D44 — leave it alone for now — `cyrius package` is reserved for ark, the repo package manager (no change).
**Severity:** Low — what the verb is for.

## Options

1. Keep `package` as it is (compile the `[build]` entry to `build/<output>`).
2. Retire it (`cyrius build` does the same), with a removal window as `cyrius tests` had.
3. Give it an `.ark` writer (the package format the verb's name promises).
