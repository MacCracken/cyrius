# A refusal latched in an `if` / `while` header swallows the second statement of its block, and that statement's error — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-6, `14ba05693` (with FF-7 `9f94ba317` and FF-10 `453c5393b`) — no decision needed (diagnostics). `_blk_open` (src/frontend/parse_ctrl.cyr) clears a header's latch at the block's `{` when the latch was clear as the head began and the `{` is the header's end, in if / elif / while / for / for-in / switch / match. The filed program reports all three errors, 5:11, "7:16: undefined variable 'zz8'" (it was swallowed) and 8:16; the `while (qq[0] == 1)` and syntax-error-header shapes report the block's error; a header left mid-way keeps its latch. FF-7 (met as the H9 control): a header left mid-way and a body written without braces are one error each, the enclosing body's `}` kept (no invented "expected '}', got end of file"). Rows: in_sync_refusal_next_statement.sh H1 (the filed program verbatim) – H16 and R1 – R15 on five legs; mutants RED 70 / 15 / 55; FF-10 gives the gate its corpus floor (395, 445 after FF-44). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F1) beside
issues/archived/2026-10-18-in-sync-refusal-in-assignment-swallows-next-statement.md, whose fix (`_refuse_in_sync`) covers a
statement that refuses and then ends at its own `;`. Measured on the slot-open compiler (480de63eb's build/cycc) and
on the lane head 814a8fb36 (x86_64; the frontend, every target): identical.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF2) — never 7.x.
**Severity:** Low — diagnostics: an error in the block is not reported (the build is refused, rc 1, and the first
error is right; one fix-and-rebuild round more).
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
fn main(): i64 {
    var a: u128 = 0;
    var pa: *u128 = &a;
    var y = 0;
    if (pa[0] == 1) {
        y = 1;
        y = zz8;
        y = zz7;
    }
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < hdr5.cyr > /dev/null
error:<source>:5:11: cannot subscript 'pa': a u128 element does not fit one register - use load64/store64 on its two halves
error:<source>:8:16: undefined variable 'zz7' (missing include or enum?)
```

Line 7's "undefined variable 'zz8'" is never reported. The same with `while (qq[0] == 1) { y = 1; y = zz8; }` (an
undefined subscript base: only `qq` is reported) and with a plain syntax error in the header, `if (y == 0 +) { y = 1;
y = zz8; }` (only "unexpected ')'"). A refusal whose statement ends at its `;` no longer does this since the 6.7.16
fix above (`y = pa[0]; y = zz9;` reports both).

## Root cause

The header's refusal latches `_panic`, and PARSE_IF / the while parser go on to parse the block's statements with the
latch still set. The block's FIRST statement (`y = 1;`) ends with `_panic == 1`, so its PARSE_STMT calls
`_stmt_resync(S, before)` with `before` = that inner statement's first token. The in-sync mark, when there is one,
sits in the header — below `before` — so `_sync_skip` runs from after `y = 1;` and consumes the SECOND statement to its
`;` (unless it begins with a statement keyword, `_sync_kw`), clearing the latch there; the third statement on is
parsed. The latch belongs to the header, not to the block's first statement.

## Direction (not decided here)

The header's own end — the `)` before the block — is where its refusal is in sync; clearing the latch there (as
`_stmt_resync` clears an in-sync statement's at its `;`) would let the block parse unlatched. Rows: the repro gives
three errors (5, 7, 8); the `while` and syntax-error shapes report the block's error; a refusal that leaves the header
mid-way still recovers with no cascade.
