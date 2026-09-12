# `continue` at two nesting levels binds to the wrong loop

**Status:** ✅ **FIXED in v6.6.3** — the continue-patch array is indexed absolutely
instead of per-loop, and `PARSE_WHILE` now declares while-mode. Gated by
`tests/tcyr/lang/nested_continue_binds.tcyr` (8 assertions; the pre-fix compiler fails 6).
(only 6.6.0–6.6.2 installed, see below).
**Placement:** unpinned — hisab pins 6.6.2 and ships an `if`-guard workaround.
**Discovered:** 2026-09-11, building a 32×32 product table in hisab (`geo_advanced.cyr`).
**Severity:** High — **silent wrong code, not a crash.** No diagnostic, no failure: the
loop simply produces the wrong answer, in a construct that reads as obviously correct,
and the workaround is invisible to a reviewer.

⚠ **This filing was corrected on 2026-09-11, before it was acted on.** Its first
version was titled *"a firing inner `continue` exits the OUTER loop"* and said the
inner `continue` "behaves like a break to the outermost level". **Instrumenting the
loop refuted that**: the outer loop is *not* terminated and runs its full trip count.
The first version also asserted the defect fires whenever a `continue` at either level
executes, which over-claims in one direction and under-claims in another — the real
trigger is **lexical placement**, and the outer `continue` is broken too, silently and
in the opposite direction. The counts below are measured, not inferred.

## Symptom

When a loop contains a `continue` **and** encloses a nested loop that also contains a
`continue`, **and the outer `continue` appears lexically before the nested loop**, both
bind one level too far out:

- the **inner** `continue` jumps to the **outer** loop's latch — it abandons the rest of
  the inner loop *and* the rest of the outer loop body;
- the **outer** `continue` becomes a **no-op** — it skips nothing at all.

```cyrius
var o = 0;
for (var c = 0; c < 3; c = c + 1) {
    if (c == 99) { continue; }        # NEVER TAKEN
    for (var d = 0; d < 3; d = d + 1) {
        if (d == 0) { continue; }     # fires
        o = o + 1;
    }
}
# o == 6 is correct.  6.6.2 gives o == 0.
```

⚠ **The decisive part is that the outer `continue` never executes.** `c == 99` is
impossible for `c` in 0..2. Its mere *presence* changes the code generated for the
inner one. That rules out a misreading of `continue`'s semantics.

### Which loop is actually affected

Counters placed in the nest above, on 6.6.2:

| counter | measured | correct |
|---|---|---|
| outer body entered | **3** | 3 |
| inner body entered | **3** | 9 |
| outer body *after* the inner loop | **0** | 3 |

The outer loop is **not** terminated — it runs its full trip count. The inner loop stops
at its first firing `continue`, and the remainder of the outer body is skipped: exactly
the behaviour of `continue` applied to the **outer** loop.

## What is and is not affected

Every row measured by `repros/2026-09-11-nested-continue-binds-to-wrong-loop.cyr`.

| # | shape | result |
|---|---|---|
| A | `continue` in the INNER loop only | correct |
| B | `continue` in the OUTER loop only | correct |
| C | present at both levels, **neither** fires | correct |
| D | both present, only the **OUTER** fires | **WRONG** — the outer `continue` is a no-op (9 iterations run, 6 correct) |
| E | both present, only the **INNER** fires | **WRONG** — 0, correct is 6 |
| F | both present, **both** fire | **WRONG** — 0, correct is 4 |
| G | both present, outer `continue` placed **after** the inner loop | correct |
| H | two `continue`s in the **same** loop body | correct |
| I | two **sequential** (non-nested) loops, each with a firing `continue` | correct |
| J | E's control flow written with `if`-guards | correct |

Rows G and J are the load-bearing controls. **G isolates the trigger to lexical order**:
move the outer `continue` below the nested loop and the same program is correct. **J is
the workaround**: the same control flow expressed as `if (cond) { ... }` instead of
`if (!cond) { continue; }` is correct on the same compiler, which is what makes this
codegen rather than a language question.

⚠ Row D matters as much as E even though it looks milder. A `continue` that silently
does nothing produces *more* work, not less, so it cannot announce itself by hanging or
crashing — it just quietly widens whatever the loop was filtering.

**Mechanism not determined here.** The shape is consistent with a continue-fixup list
that is function-scoped rather than per-loop, so the nested loop's latch claims the
enclosing loop's pending fixups — but that is a guess, and only the observable behaviour
above was measured.

## Repro

`repros/2026-09-11-nested-continue-binds-to-wrong-loop.cyr` — **proves itself**: exit 0
if the compiler is correct, exit 1 if the bug is present. It runs all ten shapes plus the
three instrumentation counters, so a failing run also demonstrates which of them are
correct on the same build.

```
cyrius build repros/2026-09-11-nested-continue-binds-to-wrong-loop.cyr /tmp/repro && /tmp/repro
```

On 6.6.2:
```
  A inner only, fires             : 6  want 6   ok
  B outer only, fires             : 6  want 6   ok
  C both, neither fires           : 9  want 9   ok
  D both, only OUTER fires        : 9  want 6   WRONG
  E both, only INNER fires        : 0  want 6   WRONG
  F both, both fire               : 0  want 4   WRONG
  G outer cont AFTER inner loop   : 6  want 6   ok
  H two conts, one loop           : 1  want 1   ok
  I sequential loops              : 4  want 4   ok
  J control, if-guards            : 6  want 6   ok
  E' outer body entered           : 3  want 3   ok
  E' inner body entered           : 3  want 9   WRONG
  E' outer body after inner loop  : 0  want 3   WRONG
  BUG PRESENT
```

## How it was found

hisab builds a 32×32 geometric-product table and skipped empty rows the obvious way —
`if (cp == 0) { continue; }` in the outer loop and the same test in the inner one. That
is row D and row E at once: the outer skip did nothing, and the inner skip abandoned the
outer body before any entry was stored. The result was an **all-zero 1024-entry table
while every helper tested correct in isolation and the build reported success**. Nothing
failed; the values were simply absent.

## Not bisected

Only 6.6.0–6.6.2 are installed and hisab pins 6.6.2, so establishing a first-bad-version
would mean repinning. Stated rather than guessed. ⚠ And this project's own history
records a first-bad-version as evidence about **visibility**, not **origin** — see the
6.5.71 GFLC filing, which was wrong on exactly that point.

## Consumer workaround

hisab's table builder is written with `if`-guards and carries a comment saying **not to
tidy them back into `continue`** until this issue closes.

---

## Root cause (v6.6.3) — one flat array, two halves

`0x18F8A0` is **one flat 8-entry patch array** holding the forward jumps a C-style `for`'s
`continue`s need; `0x18F898` is the next-free index into it — 1-based, with **0 doubling
as a mode flag** meaning "while-mode: jump straight to loop top".

**Half 1 — array aliasing.** All three `for` parse sites reset the index to `1` on entry.
A nested loop therefore began writing at index 0 again and **overwrote the enclosing
loop's recorded jump**. At patch time the outer loop then re-patched that same slot, which
by then held the INNER jump — sending the inner `continue` to the outer latch — while its
own jump had been lost and was never patched, making the outer `continue` a no-op. That is
exactly the reported pair of symptoms, and it explains the lexical trigger: the outer
`continue` must appear BEFORE the nested loop to claim index 0 first and have it stolen.

Fixed by starting each loop at the enclosing loop's next-free index
(`var cfwb = scfw; if (cfwb < 1) { cfwb = 1; }`) and patching only `[its base, its count)`.
The ranges are then disjoint and no save/restore of the array contents is needed.

**Half 2 — mode inheritance, NOT in the original filing.** `PARSE_WHILE` never wrote
`0x18F898`. A `while` nested inside a `for` therefore saw the for's non-zero count, took
the forward-patch branch, and sent its `continue` to the **for's step**. Measured on
6.6.2: `while` inside `for` with a first-iteration `continue` produced **0** where 6 was
right — the same silent-wrong-answer shape, found while fixing half 1.

Fixed by saving `0x18F898`, setting it to 0 for the body, and restoring it — matching what
`PARSE_WHILE` already did for the loop-top and break slots.

### Verification

- Filed reproducer: **0 → 6**.
- `while`-in-`for`: **0 → 6**.
- New test, 8 assertions covering both nesting directions, three-level nesting, an outer
  `continue` that actually fires, and `break` (a separate chain that must not regress):
  **8 passed, 0 failed**. The pre-fix compiler fails **6 of 8**.
- Self-host fixpoint byte-identical; seed-derive OK from the 29,024-byte seed.

⚠ **The `max 8` limit is now total across a nest**, not per loop, because the indices no
longer restart. Eight is unchanged as the array bound and still hard-errors rather than
corrupting — which is what it did before.

### hisab

`geo_advanced.cyr` ships an `if`-guard workaround for this. It can be removed once hisab
moves to 6.6.3, but it is harmless to leave.
