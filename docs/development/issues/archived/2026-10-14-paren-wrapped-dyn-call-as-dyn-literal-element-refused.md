# A parenthesised dyn-returning call as a struct literal's `dyn` element is refused with two reports, where the unwrapped call and every other dyn destination take it — RESOLVED

> ✅ **RESOLVED in v6.7.13** (RC-10, `98801809`: the user's decision D17 (a), 2026-10-15 — the wrap is transparent for a dyn element too (`_spi_call` no longer declines a wrapped dyn result). The filed repro `H { 7, (pass(o)), 8 }` exits 169 on x86_64, IR=3, aarch64, cx and PE (it was refused with the two reports filed); double parentheses and a wrapped dyn method `(q.mk(o))` give 169; at top level the element is refused once, by name (no frame), wrapped or not. The untyped `var x = (pass(o));` stays refused (6.7.8 V4d). Rows: `dyn_checked.sh` PW1 (the repro verbatim) – PW5; `crossos/dyn_objects.tcyr` §literal; mutants M-PW1, M-PW2 RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 struct lane (`l6711-struct`, unit S7) on x86_64,
aarch64 (qemu), cx (cxvm) and PE (wine): `H { 7, (pass(o)), 8 }` with `fn pass(o: dyn Show): dyn Show` is refused with
two errors; `H { 7, pass(o), 8 }` builds and gives 169 (7849 & 255) on all four. The lane base compiler does the same.
**Placement:** 6.7.13 — repair 3: struct values (receives lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D17 — (a).
compiling — the user's call; or the user keeps the refusal and it is named once.)
**Discovered:** 2026-10-14, the 6.7.11 struct lane (S7), fixing issues/2026-10-10-paren-wrapped-struct-call-as-nested-
literal-element-refused.md (a parenthesised FREE struct call as a nested literal element, the user's decision (a),
2026-10-13). That issue notes the 6.7.8 dyn lane's bite D4 "refuses that form for a dyn with its own two reports";
the S7 fix keeps a dyn result on its 6.7.8 path (`_spi_call` returns 0 for a wrapped dyn), so this shape is unchanged
and is filed here for the user's decision rather than changed with the struct one.
**Severity:** Low — valid-looking source refused loudly, with a working spelling (drop the parentheses).
**Affects:** every target (shared frontend); 6.7.8 – 6.7.11.

## Reproduction

```cyrius
include "lib/alloc.cyr"
trait Show { fn show(self): i64; }
struct W { o: dyn Show; }
struct H { a; o: dyn Show; b; }
fn mkw(d, v): i64 { var m = alloc(16); store64(m, d); store64(m + 8, v); return m; }
fn get(w: *W): dyn Show { var o: dyn Show = w.o; return o; }
fn pass(o: dyn Show): dyn Show { return o; }
fn dw(o: dyn Show): i64 { var w: W = W { o }; return load64(&w) * 10 + load64(&w + 8); }
fn main(): i64 {
    alloc_init();
    var o: dyn Show = get(mkw(4, 9));
    var h: H = H { 7, (pass(o)), 8 };      # refused (2 errors); without the parentheses: 169
    return dw(h.o) + h.a * 1000 + h.b * 100;
}
syscall(60, main() & 255);
```

```
error:<source>:13:24: a dyn Show result used as a value - call one of its methods, or copy it whole into a dyn
error:<source>:13:23: a struct literal does not form a dyn - form it first (`var d: dyn Show = ..;`) and write `d` here
```

Every other dyn destination takes the same wrapped call (tests/gates/frontend/dyn_checked.sh's PL rows):
`var y2: dyn Show = (pass(o));`, `z = (pass(o));`, `h.o = (pass(o));`, `take(3, (pass(o)), 5)`. Only an UNTYPED
`var x = (pass(o));` is refused by design (6.7.8 V4d).

## Root cause

`_spi_src` (`src/frontend/parse_decl.cyr`) takes an unwrapped `pass(o)` through `_spi_call` (a struct-sized result
into a temp, copied whole into the dyn field). Wrapped, `_spi_pcall` (6.7.11) steps in but `_spi_call` declines a dyn
result (`if (pk > 0) { if (_dyn_is(S, rs) == 1) { return 0; } }`), so `_spi_expr` parses `(pass(o))` as a value — the
"dyn result used as a value" refusal — and `_spi_nested`'s dyn arm (`_dyn_lit_form`) adds the second report.

## Proposed fix

The user's call: (a) the wrap is transparent for a dyn too — drop the dyn exclusion in `_spi_call` (the element is
then the unwrapped call's: 169); or (b) keep it refused, as one report naming the wrap. Rows: the repro, double
parentheses, a dyn method result `(q.mk(o))`, at top level.
