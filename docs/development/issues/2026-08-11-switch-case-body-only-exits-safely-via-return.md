# `switch`: a case body can only be left safely by `return`

> ### ✅ RESOLVED — v6.5.20, bite 1. Fixed, gated, measured.
>
> **⛔ THE ROOT CAUSE IS NOT THE ONE THIS FILE GUESSES.** Both suspects named under
> *Root cause — fall-through in the table regime* below are **fine**, and the analysis
> is kept only as a record of what a plausible-but-wrong diagnosis looked like:
>
> * *"the gap-fill sentinel `load32(te) == 0` conflates a real entry with an empty
>   one"* — it cannot. An entry holds `body_cp - table_cp`, and
>   `ESWITCH_DISPATCH_TABLE` emits the whole `(range+1) × 4` byte table **before** any
>   case body is parsed, so every `body_cp` is at least `table_cp + (range+1)*4`.
>   A real entry is therefore always strictly positive; 0 is unambiguously "unfilled".
>   (The file's supporting hunch — "suspicious that case 0 is the one case that works"
>   — confuses the case *value* with the table *index*: `case 0` works because it is at
>   table index `val - case_min == 0`, where the number of NOPs harvested before it is
>   zero. That is the real defect's signature, not the sentinel's.)
> * *"`S64` writes EIGHT bytes into a table of FOUR-byte entries"* — deliberate and
>   correct. The read-modify-write keeps the high 32 bits (`L64(ta) >> 32 << 32`), which
>   on little-endian **is** the neighbouring entry, and the table path is x86-family
>   only (`parse.cyr:453-454` forces the chain path on aarch64/cx), so there is no
>   big-endian arm to get wrong. At the last index the `L64` reads 4 bytes past the
>   table into the first case body and writes those same bytes back unchanged.
>
> **The actual cause is the v5.6.27 regalloc NOP-harvest compactor**
> (`src/frontend/parse_fn.cyr`, "Stage 4: compact bytes"), and it is a *codegen*
> defect, not a *switch* one. That pass deletes the 4-byte NOPs the register-allocation
> picker leaves behind and repairs jump `disp32`s, fixup CPs and jump-target CPs — but
> it never knew the switch jump table existed. Every NOP harvested between the table and
> a case body left that body's entry **4 bytes too far, cumulatively**: index 0 (zero
> deletions before it) stayed correct while every later case landed mid-instruction.
> With a `default:` that is a SIGSEGV; without one the strayed target fell past the end
> of the switch and the program returned the wrong answer silently. **Only bodies that
> assign a register-allocated local produce NOPs at all** — which is exactly why a
> corpus of `case N: { return N; }` bodies never saw it, and why the blind spot named in
> criterion 4 is causally connected to the bug rather than a coincidence.
>
> **Shipped fix.** New `_sw_tbl_repair()` runs as compaction **stage 3b**, before the
> byte copy, recomputing each entry from scratch (both ends move independently) off a
> per-fn table registry `_sw_tbl_reg()` populates in `parse.cyr` (heap `0x1AC800`
> count + `0x1AC808` records; reset per fn). `match` shared the defect and is fixed with
> it. `break` now leaves the switch/match with C semantics via `_brk_chain_end()` —
> `continue` still belongs to the enclosing loop.
>
> **Measured, one binary per argument, 6.5.19 → 6.5.20:**
>
> | repro | arg | 6.5.19 | 6.5.20 |
> |---|---|---|---|
> | 1 — table, fall out, `default:` | `p(0)` | 0 ✓ | 0 ✓ |
> | | `p(1)` | **139** SIGSEGV | **1** ✓ |
> | | `p(2)` | **0** silently WRONG | **2** ✓ |
> | | `p(3)` | **139** SIGSEGV | **3** ✓ |
> | | `p(99)` | 7 ✓ | 7 ✓ |
> | 2 — table, fall out, no `default:` | `p(2)` | **0** silently WRONG | **2** ✓ |
> | 3 — `break`, CHAIN regime | `p(2)` | **139** SIGSEGV | **22** ✓ |
>
> **Acceptance criteria:**
> 1. ✅ Table-regime fall-out is correct with and without `default:` — repros 1 and 2
>    above, plus `dense4_fallout` / `dense4_nodefault` in the corpus.
> 2. ✅ `break` breaks the switch (implemented, not rejected — C semantics). No
>    unpatched jump survives. **This changed the language surface**, so
>    `docs/guides/cyrius-guide.md` and vidya `language/core.cyml` were updated to
>    describe it; the file's note that the choice "is a language call for the
>    maintainer" stands — what is documented now is what *ships*, and reverting to a
>    hard error remains open to the maintainer.
> 3. ✅ `tests/tcyr/crossos/switch_case_exit_routes.tcyr` — 75 assertions over all four
>    exit routes × both regimes, plus nesting, `continue`, `match` and empty bodies. In
>    `crossos/`, so the release gate runs it on real ecb / ach / cass / pi.
> 4. ✅ `tests/tcyr/codegen/switch_dispatch.tcyr` extended (this criterion was **UNMET**
>    at first cut — the fix shipped with a brand-new fixture and this file untouched,
>    82 `return`s and 0 `break`s). One non-`return` mirror per dispatch regime: chain
>    fall-out + `break`, dense-4 fall-out with and without `default:` + `break`,
>    non-zero `case_min`, sparse, 8-case, and 40-case. **Mutation-proven end to end:**
>    the pre-extension file on the 6.5.19 compiler is `47 passed, 0 failed, exit 0` —
>    the blind spot, exactly as filed; the extended file on that same compiler prints
>    the first new group header and then **SIGSEGVs, exit 139**; on 6.5.20 it is
>    **102 passed, 0 failed, exit 0**.
> 5. ⏳ Cross-OS (ecb / ach / cass / pi) — run as part of the release gate at slot
>    close. The table path is x86-family only, but the `break`/`match` half is shared,
>    and cx showed a *third* failure mode (hang, exit 124) that only real hardware and
>    the cx runner can confirm.
>
> **Follow-on found while fixing this** (`parse_fn.cyr`, same pass): `_ra_frame_trim`'s
> NOP-run recorder is an *unaligned byte-pattern scan* over the whole fn range, and that
> range now contains jump-table DATA. Its safety comment reasoned only about emitted
> instructions, so it no longer covered the range it scans. The scan now refuses any
> window overlapping a table (`_sw_tbl_hits`). Measured as hardening, not a fix: with
> the guard removed, 352 corpus files compile to **0 differing binaries**.
>
> *Archive this file at slot close.*

**Filed** 2026-08-11 (during v6.5.19, CVE-39 truncated-input work)
**Severity** P1 — silent miscompile. One shape gives the WRONG ANSWER with no
diagnostic; two shapes SIGSEGV the produced binary at runtime.
**Status:** ✅ RESOLVED in v6.5.20 (bite 1). Was: 🔴 OPEN — pinned, first bite of the
release.
**Placement:** **v6.5.20, bite 1** — ahead of everything else in the minor. It is a SILENT
miscompile of ordinary valid cyrius, which this project treats as a P0 smell, and the
2026-08-11 re-triage measured the fix as far more local than this file originally claimed
(see *Locality correction* below).
**Affects** `PARSE_SWITCH` (`src/frontend/parse.cyr`), table + chain regimes

> ### ⛔ Locality correction (re-triage 2026-08-11, verified against live code at 6.5.19)
>
> This file's stated reason for filing-rather-than-fixing — "the fix is in the switch
> jump-table emitter and the break-chain protocol, both of which are **per-backend** (x86 /
> aarch64 / macho / PE / cx)" — **is wrong against live code.**
>
> `src/frontend/parse.cyr:453-454` forces `use_table = 0` for `_AARCH64_BACKEND` and
> `_TARGET_CX`, so the jump-table path is **x86-family only** (ELF x86-64 + PE + x86 Mach-O,
> which share x86's emitters — three instruction backends, not five). **Both** defective
> halves live in the shared frontend: the table patch + gap-fill arithmetic is in `parse.cyr`
> (the backend emitter only lays out a reserved zero table), and the break chain is
> `parse.cyr` + `parse_ctrl.cyr` — `grep -rn 0x18F840 src/frontend/` returns `parse_ctrl.cyr`
> (16 sites, while/for) and `parse.cyr:1095`/`:1100` (the break emitter), and **zero** in
> `PARSE_SWITCH`/`PARSE_MATCH`, which is the bug.
>
> **This is a one-file frontend fix, not a five-backend arc.** The four-host gate cycle is
> real and remains the honest cost — but it is now the *only* surviving reason this was not
> packed into .19, and it makes this the cheapest P1 in the queue.
>
> ### ⛔ The bug is WIDER than the table in this file shows
>
> Re-run on HEAD `build/cycc` (6.5.19), one binary per argument:
> `p(0)`→0 ✓ · `p(1)`→**139** · `p(2)`→**0, silently WRONG (expected 2)** · `p(3)`→**139** ·
> `p(99)`→7 ✓. The silent-wrong-answer row is therefore **not** confined to the no-`default:`
> shape as the table below states — it occurs **with `default:` present**. Control (3-case
> chain, no table) returns 2 correctly, confirming the regime boundary.
> On **cx**, `break` inside a case **HANGS** (timeout, exit 124) rather than SIGSEGVing — a
> third failure mode this file does not record.
>
> Corpus blind spot confirmed: `tests/tcyr/codegen/switch_dispatch.tcyr` has 77 `case` lines
> and **zero** non-`return` case bodies, which is why 269 .tcyr and four hosts are all green.

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
