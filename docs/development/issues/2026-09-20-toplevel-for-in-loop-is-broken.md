# A top-level `for x in a..b` cannot use its own loop variable, and nesting two SIGSEGVs — OPEN

**Status:** 🟡 open — found during 6.6.6 (bite 19's review, probing top-level block scoping);
reproduces identically on 6.6.5 and on the 6.6.6 tree.
**Placement:** unpinned — 6.x line, the next repair batch.
**Discovered:** 2026-09-20

## Repro A — the loop variable is not visible in its own body

```cyrius
var s = 0;
s = 0;
for i in 0..4 { s = s + i; }
syscall(60, s);
```

`error:<source>:3:26: undefined variable 'i'`, rc 1. The same loop **inside a fn** exits 6.

## Repro B — nesting two of them compiles and crashes

```cyrius
var s = 0;
s = 0;
for i in 0..3 { for j in 0..2 { s = s + 1; } }
syscall(60, s);
```

Exits **139** (SIGSEGV). Expected 6. No diagnostic at compile time.

## Why it is filed rather than fixed

6.6.6's bite 19a gave top-level blocks a scope mechanism (the global var table had none), which
is the neighbouring machinery — but the loop variable is a different binding: `for-in` at top
level never registers `i` anywhere the body can see, and the nested form corrupts something
further down. Both predate 6.6.6 and neither is a regression from it. The release's queue was
closed by then (the user's boundary), so this is the first item of the next batch.

## Acceptance criteria

- Repro A exits 6; repro B exits 6.
- A `tests/tcyr/crossos/` companion, since a top-level for-in is emitted by every backend.
- A gate row that goes RED on the pre-fix compiler for BOTH shapes — the nested one exits 139
  today, so an exit-code assertion alone is enough to prove the row is live.
