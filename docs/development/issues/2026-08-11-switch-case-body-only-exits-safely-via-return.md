# `switch`: a case body can only be left safely by `return`

**Filed** 2026-08-11 (during v6.5.19, CVE-39 truncated-input work)
**Severity** P1 — silent miscompile. One shape gives the WRONG ANSWER with no
diagnostic; two shapes SIGSEGV the produced binary at runtime.
**Status** open
**Affects** `PARSE_SWITCH` (`src/frontend/parse.cyr`), table + chain regimes

> **Why this is filed rather than fixed in v6.5.19.** Per CLAUDE.md an audit's output
> is fixes, not a backlog, and "different subsystem" is explicitly not a reason to
> file. The reason here is the one the rule does name: **it cannot pack into the patch
> it was found in.** The fix is in the switch jump-table emitter and the break-chain
> protocol, both of which are per-backend (x86 / aarch64 / macho / PE / cx), and a
> codegen change to switch dispatch needs its own full release gate — self-host
> fixpoint, seed-derive, and cross-OS self-host on ecb/ach/cass/pi — plus a new
> codegen gate. v6.5.19 is a parser-termination and tooling release; landing an
> unverified switch-dispatch change inside it would put the seed chain at risk for a
> bug that has been latent for multiple minors.
>
> **It is NOT a v6.5.19 regression.** Every result below was reproduced against the
> HEAD-committed `build/cycc` (sha256 `636702b2add2f117…`) as well as the v6.5.19
> compiler. Behaviour is identical before and after.

## Summary

Exiting a `switch` case body by any route other than `return` is broken:

| exit route | regime | result |
|---|---|---|
| `return` inside the case | chain and table | **correct** |
| fall out of the body | chain (< 4 cases) | correct |
| fall out of the body | **table (>= 4 cases), `default:` present** | **SIGSEGV at runtime** |
| fall out of the body | **table (>= 4 cases), no `default:`** | **silently WRONG ANSWER** |
| `break;` inside the case | chain and table | **SIGSEGV at runtime** |

Only the `return` row is exercised by the existing corpus, which is why this has
survived: `tests/tcyr/codegen/switch_dispatch.tcyr` writes every case body as
`case N: { return NNN; }`, in both the chain and the table regime.

## Repro 1 — table regime, falls out, `default:` present → SIGSEGV

```
fn p(x) {
    var r = 0;
    switch (x) {
        case 0: { r = 0; }
        case 1: { r = 1; }
        case 2: { r = 2; }
        case 3: { r = 3; }
        default: { r = 7; }
    }
    return r;
}
fn main() { return p(3); }
var r = main();
```

Measured, one binary per argument:

```
p(0)  -> exit 0    correct
p(1)  -> exit 139  SIGSEGV
p(3)  -> exit 139  SIGSEGV
p(99) -> exit 7    correct (default)
```

Case 0 and the default are dispatched correctly; every other case jumps somewhere
fatal. Four cases is the minimum to enter the table regime — the same source with
three cases is correct, which is the cleanest confirmation that the chain path is
fine and the table path is not.

## Repro 2 — table regime, falls out, no `default:` → silent wrong answer

Same as above with the `default:` arm deleted and `p(2)`:

```
expected 2, got 0, exit 0, no diagnostic
```

This is the worst of the three: no crash, no message, just the wrong number. `r`
keeps its initial value, i.e. control reached the end of the switch without running
the selected body.

## Repro 3 — `break` inside a case → SIGSEGV

```
fn p(x) {
    var r = 0;
    switch (x) {
        case 1: { r = 11; break; }
        case 2: { r = 22; break; }
        default: { r = 7; break; }
    }
    return r;
}
fn main() { return p(2); }
var r = main();
```

`compile ok, run exit=139`. Note this one fails even in the CHAIN regime (3 cases),
so it is a second, independent defect rather than another face of repros 1-2.

## Root cause — `break`

`break` is token 51 and is emitted in `PARSE_STMT` (`src/frontend/parse.cyr:1086`) as
a forward jump threaded onto a linked list whose head lives at heap slot
`S + 0x18F840`. The enclosing construct is responsible for saving that slot, zeroing
it, parsing the body, then walking the chain and patching every jump to its own end.

`PARSE_WHILE` and `PARSE_FOR` do exactly that (`src/frontend/parse_ctrl.cyr:203`,
`:207`, `:231`, `:239`, and the `for` variants at `:324`/`:329`/`:383`/`:386`,
`:409`/`:414`/`:449`/`:452`, `:464`/`:469`/`:547`/`:551`).

**`PARSE_SWITCH` and `PARSE_MATCH` never touch `0x18F840` at all.** Grep it:

```
$ grep -rn "0x18F840" src/frontend/
src/frontend/parse_ctrl.cyr:  (16 hits — while / for)
src/frontend/parse.cyr:1090   (the break emitter itself)
src/frontend/parse.cyr:1095   (the break emitter itself)
```

So a `break` inside a switch either links onto an enclosing loop's chain (breaking the
LOOP, not the switch — a semantic divergence from C worth deciding on) or, with no
enclosing loop, is never patched at all and retains its placeholder displacement. That
is the SIGSEGV.

Note `docs/guides/cyrius-guide.md:132` says "Break / Continue (in while and for)", so
`break` in a switch may well be intended as unsupported. **If so it must be REJECTED,
not silently miscompiled** — the established precedent in this tree is `CHK_ENUM_SHADOW`
(`src/frontend/parse_types.cyr`), which hard-errors on a shape that "is almost always a
bug and SILENTLY miscompiles". Whether to implement it or reject it is a language call
for the maintainer; either is better than the current wild jump.

## Root cause — fall-through in the table regime

Less certain, and the reason this needs a proper investigation rather than a quick
patch. In the table path (`src/frontend/parse.cyr`, from `ESWITCH_DISPATCH_TABLE`):

```
var body_cp = GCP(S);
var toff = (val - case_min) * 4 + table_cp;
var ta = _codebuf_base + toff;
var trel = body_cp - table_cp;
S64(ta, (L64(ta) >> 32 << 32) | (trel & 0xFFFFFFFF));
```

and later, the gap fill:

```
var end_cp = GCP(S);
var gap_rel = end_cp - table_cp;
if (default_cp >= 0) { gap_rel = default_cp - table_cp; }
ti = 0;
while (ti <= range) {
    var te = _codebuf_base + table_cp + ti * 4;
    if (load32(te) == 0) { S64(te, (L64(te) >> 32 << 32) | (gap_rel & 0xFFFFFFFF)); }
    ti = ti + 1;
}
```

Two things to check, in this order:

1. **The gap-fill sentinel is `load32(te) == 0`, i.e. "relative offset 0 means
   unfilled".** That conflates a real entry with an empty one. It is suspicious that
   case 0 is the one case that works and every later case fails.
2. **`S64` writes EIGHT bytes into a table of FOUR-byte entries.** The read-modify-write
   is intended to preserve the neighbouring entry, but it is worth confirming the
   preserved half is the right half on both endiannesses and that the final entry does
   not run off the end of the table region.

The observed symptom — the selected body is skipped and control lands at the end of the
switch (no default) or somewhere fatal (default present) — is consistent with the table
entries for cases 1..N being overwritten by `gap_rel`.

## Acceptance criteria

1. A table-regime switch (>= 4 cases) whose bodies fall out produces the right answer,
   with and without a `default:`.
2. `break` inside a switch/match either breaks the switch (if implemented) or is a
   compile ERROR naming the construct — never an unpatched jump.
3. A new codegen gate covers all four exit routes (`return`, fall-out, `break`,
   fall-out-with-no-default) across BOTH regimes (3 cases and >= 4 cases), and is
   mutation-proven.
4. Extend `tests/tcyr/codegen/switch_dispatch.tcyr`: every one of its case bodies
   currently ends in `return`, which is precisely the blind spot.
5. Cross-OS: verify on ecb / ach / cass / pi — the table dispatch is per-backend.

## Related

- Found while building `tests/gates/diagnostics/truncated_input_terminates.sh` (v6.5.19,
  CVE-39). That gate's axis 4 deliberately uses `{ return N; }` bodies and carries a
  comment pointing here, so nobody "simplifies" it into the broken shape.
- The `ends` array in both `PARSE_SWITCH` and `PARSE_MATCH` gained a bound
  (`_ends_guard`) in v6.5.19 — that fixed an unbounded 256-slot stack write, a
  different bug in the same function. It does not touch the dispatch defect here.
