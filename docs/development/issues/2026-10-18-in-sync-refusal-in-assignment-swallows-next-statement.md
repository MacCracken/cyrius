# A refusal latched inside an expression statement that parsed to its own `;` swallows the NEXT statement and its first error — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 structs lane (beside D20, 62fbdf162), re-measured
by its fix step on the lane head 342244fa8 and the lane base 8b4d44602 (x86_64). Pre-existing: the base does the same
with a `pa[0]` subscript.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs review, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — diagnostics: a later error is not reported (the build is still refused, rc 1, and the first error
is right; one fix-and-rebuild round more).
**Kind:** bug (diagnostics). Related to, not the same as, issues/2026-10-18-zone-replay-reports-only-first-latched-error.md
(the declaration zone's replay) and issues/2026-10-18-double-pointer-generic-parameter-refusal-swallows-the-next.md (a
signature); this one is a statement in a fn body.

## Reproduction

```cyrius
fn main(): i64 {
    var a: u128 = 0;
    var pa: *u128 = &a;
    var y = 0;
    y = pa[0];
    y = zz9;
    pa[0] = 1;
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < latch4.cyr > /dev/null; echo $?
error:<source>:5:11: cannot subscript 'pa': a u128 element does not fit one register - use load64/store64 on its two halves
        y = pa[0];
              ^
error:<source>:7:7: cannot subscript 'pa': a u128 element does not fit one register - use load64/store64 on its two halves
        pa[0] = 1;
          ^
1
```

Line 6's "undefined variable 'zz9'" is never reported. With 6.7.15's D20 `*pa` refusal on the lane:

```cyrius
fn main(): i64 {
    var a: u128 = 0;
    var pa: *u128 = &a;
    var y = 0;
    y = *pa;
    *pa = 1;
    y = *pa;
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < latch5.cyr > /dev/null
error:<source>:5:9: cannot dereference 'pa': a u128 element does not fit one register - use load64/store64 on its two halves
error:<source>:7:9: cannot dereference 'pa': a u128 element does not fit one register - use load64/store64 on its two halves
```

Line 6's store is not reported (it is refused when it stands alone). Control — the next statement is a `var`: line 6's
`var z = zz9;` IS reported (three errors, lines 5, 6 and 7), on the lane and the base alike.

## Root cause

The refusal (`ERR_MSG` / `ERR_IDENT`, which set `_panic`) is made while the statement still parses on to its own `;`
— in sync. PARSE_STMT (src/frontend/parse.cyr) then sees `_panic == 1` and calls `_stmt_resync`, which clears only an
in-sync PAIR refusal (`_pair_sync_ti`, 6.7.11) and otherwise calls `_sync_skip` (src/common/util.cyr): the cursor is
already past the `;`, so `_sync_skip` consumes the NEXT statement up to and including its `;` — unless that statement
starts with a statement keyword (`_sync_kw`: `var`, `if`, `return`, ...), where it stops. So a following assignment or
call statement is skipped unparsed, its errors lost.

## Fix direction

Generalise 6.7.11's in-sync mark: a refusal made in sync records where (as `_pair_refuse_in_sync` does with
`_pair_sync_ti`), and `_stmt_resync` clears only the latch when the statement ended at its own `;` / `}` past that
point. Rows: latch4 gives three errors (lines 5, 6, 7); latch5 three (5, 6, 7); a refusal that leaves the statement
mid-way still resyncs to its `;` with no cascade.
