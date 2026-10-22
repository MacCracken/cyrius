# Top-level directive lines read less than their line: `#assert`'s and `include`'s tails are skipped unread (silently dropping code), `use` takes no module path, and a `private` line after the first statement swallows the next error — OPEN

**Status:** 🟡 **OPEN** — each fix newly refuses source that compiles today, or changes what it computes, beyond the
decided answers; the 6.7.16 lanes stopped on each (the user, 2026-10-21: no new decision round).
**Placement:** 6.7.17 — the cleanup of the remaining issues (fea lane, wave 1, unit FA1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D28 — Refuse it by name.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D29 — Refuse it by name.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D30 — Refuse it by name.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D31 — Accept it.
**Discovered:** the f16 lane — unit FF2 (`#assert`'s tail, met while fixing
issues/archived/2026-10-19-refused-assert-after-first-statement-swallows-next-statement.md; the f16 review's file_as_issue,
staged as 2026-10-21-assert-tail-after-message-skipped-drops-impl-methods-and-program.md), unit FF3 (`use`), unit FF5
(`private`); the pw review (`include`'s tail, met while writing its one-line repros; left unfiled in the lane's handoff,
flagged by the release-docs pass).
**Severity:** High — rows 1 and 3 compile with rc 0 and no diagnostic, and statements the source writes never run.
**Kind:** decision (what each line means; every option stops some compiling source, or changes what it computes).

## Summary

Four file-level lines are read by their own short scanners, not by the statement parser, and each stops short of its
line. `#assert C, "msg"` skips everything after its message up to the next `;` or line end, unread — in an impl body that
eats the next method, and pass 2 then ends the impl early and drops the rest of the program. An `include "f"` line is
replaced whole, so statements after it on the same line vanish. `use` accepts no module path at all. A file-level
`private` line after the first top-level statement is "unexpected private", and the refusal's latch swallows the next
statement's own error.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B, the
l6716-integ fixpoint at `53826418f`), x86_64, and where shown with the aarch64 (qemu-aarch64), cx (cxvm) and PE
(wine 11.20) compilers built from that tree. Each program is compiled from the repo root so `include` resolves.

**1. `#assert` in an impl body — the method and the rest of the program are dropped:**

```cyrius
struct S { a; }
impl S { #assert 1 == 1, "m" fn m(self): i64 { return 5; } }
syscall(60, 9);
```

rc 0, no diagnostic; the binary exits **0**, not 9, on x86_64, aarch64, cx and PE. The tail eats
`fn m(self): i64 { return 5; }` up to its `;`; pass 2 ends the impl at the method's `}`, and the module's PARSE_PROG stops
at the impl's own `}`, so `syscall(60, 9);` is never compiled. Pass 1 skipped the impl by brace balance, so the
stray-`}` check (`_tl_stray_brace`) never fires.

**2. `#assert`'s tail at module scope and in a fn:**

```cyrius
#assert 1 == 1, "m" junk
syscall(60, 9);
```

```cyrius
fn main(): i64 { #assert 1 == 1, "m" junk
return 9; }
syscall(60, main());
```

Each rc 0, no diagnostic, exit 9: `junk` is never read.

**3. `include` with source after it on the same line:**

```cyrius
include "lib/syscalls.cyr"; var x = 42; syscall(60, x);
```

rc 0, no diagnostic, exit **0** on x86_64 and PE: `var x = 42; syscall(60, x);` is gone. The same two statements on the
next line exit 42 on both. (The guide: "file contents replace the include line".)

**4. `use` with no module path:**

```cyrius
use 5;
syscall(60, 3);
```

rc 0, exit 3 on all four targets; `use m.;` the same.

**5. `private` after the first top-level statement:**

```cyrius
var a = 1;
a = 2;
private
syscall(60, a + zz);
```

```
error:<source>:3:1: unexpected private
    private
    ^
```

rc 1, and that is the only line: the undefined `zz` on line 4 is never reported. The guide says the file-level marker
applies "wherever in it the marker sits" and does not list `private` among the declaration-section kinds;
private_per_item_rejected.sh's row PC3 pins today's line as a control.

## The decision

- **Rows 1 – 3, a directive's tail** — (a) the directive ends where its grammar ends and the rest of the line is parsed
  as source: row 1 exits 9, row 3 exits 42, and row 2's `junk` is its own error; or (b) a token after the message / the
  path other than `;` or the end of the line is refused by name ("expected the end of the line after #assert's message",
  "... after an include's path"). Either stops `#assert 1 == 1, "m" junk` compiling; (a) also changes what rows 1 and 3
  compute (the code the source writes runs), (b) refuses them.
- **Row 4, `use` with no path** — refuse it by name ("expected a module path after `use`"): `use 5;` and `use m.;`
  stop compiling. Or keep.
- **Row 5, a late `private`** — (a) accept the file-level marker there (it compiles; the next statement keeps its own
  error); or (b) refuse it by name ("a `private` line must come before the first top-level statement") and release the
  latch so line 4's error is reported too.

## Acceptance

The five repros give the decided result on x86_64, aarch64, cx and PE; an `#assert` with no message, one ending in `;`,
an `include` alone on its line and a `use` with a path are unchanged.

## Root cause (as the lanes measured it)

- `#assert`: the directive's message scan skips to the `;` / line end without checking what it skips; in an impl body
  the skip crosses a method's braces, and pass 1's brace-balanced skip of the impl hides the stray `}` (the f16 lane,
  FF2; the review re-measured it on the lane head a31410709 and on base 450ecf2c9: identical).
- `include`: the preprocessor replaces the whole include line with the file's text, so the rest of the line never
  reaches the parser (inferred from the guide's wording and the measured exit; not traced to a line).
- `use`: a `use` with no module path is accepted (the f16 lane, FF3); the reader was not traced (speculation: it steps
  to the `;` without requiring a name).
- `private`: after the first statement the line reaches the statement parser, which has no `private` arm ("unexpected
  private"); the refusal sets the panic latch and the next statement's error is swallowed by it (the f16 lane, FF5).
