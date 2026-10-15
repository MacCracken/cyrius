# A parenthesised 9-16 B method or operator result as a nested-struct literal element is refused ("unexpected '}'") — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 struct lane (`l6711-struct`, unit S7, after the
parenthesised FREE call element was fixed — issues/2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-
refused.md) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): `H { 7, (q0.dupe()), 8 }` and `H { 7, (q0 + q1), 8 }`
with a 16-byte result are refused "unexpected '}'"; unwrapped both give 64. The same with the lane base compiler.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 struct lane) — never 7.x. (Refused source starts compiling:
the user's call at that release's open, as the free-call element's was.)
**Discovered:** 2026-10-14, the 6.7.11 struct lane (S7), writing the free-call element's "a wrapped method element is
unchanged" row: the filed issue says a wrapped method / operator element "has been taken since 6.7.6 (`_sc_pwrap`)" —
true at 24 B and at 8 B, not at 9-16 B.
**Severity:** Low — valid source refused loudly (the reason is wrong: an "unexpected '}'"); no wrong value.
**Affects:** every target (the literal is parsed in the shared frontend); at least 6.7.6 – 6.7.11.

## Reproduction

```cyrius
struct QE { a; b; }
struct HE { x; q: QE; z; }
impl QE { fn dupe(self): QE { var q = QE { self.a, self.b }; return q; } }
fn QE_add(a: QE, b: QE): QE { var q = QE { a.a + b.a, a.b + b.b }; return q; }
fn main(): i64 {
    var q0 = QE { 4, 9 };
    var q1 = QE { 0, 0 };
    var m = HE { 7, (q0.dupe()), 8 };      # refused: unexpected '}'  (unwrapped: 64)
    var n = HE { 7, (q0 + q1), 8 };        # refused: unexpected '}'  (unwrapped: 64)
    return m.x + m.q.a * 10 + m.q.b + m.z;
}
syscall(60, main());
```

Measured with the l6711-struct compilers (x86_64 / aarch64 qemu / cx cxvm / PE wine), one shape per file:

| element | wrapped | unwrapped |
|---|---|---|
| `(q0.dupe())`, a 16 B method | refused `unexpected '}'` on all four | 64 on all four |
| `(q0 + q1)`, a 16 B operator | refused `unexpected '}'` on all four | 64 on all four |
| `(q3.dupe3())`, a 24 B method | 164 on all four (right) | 164 |
| `(q8.dupe())`, an 8 B two-u32 method | 64 on all four (right) | 64 |

The same 16 B method in parentheses is taken at every other destination: `h.q = (q0.dupe());` and
`take((q0.dupe()))` give the right words; at top level the element is refused by name ("'QE_dupe' returns a struct by
value, and a struct result needs storage in a fn's frame").

## Root cause

`_spi_expr` (`src/frontend/parse_decl.cyr`, the struct literal's nested-element arm) arms the struct-call
destination at the element's FIRST token (`_sc_arm` sets `_sc_want` to the `(`). A 9-16 B (rax:rdx) method or
operator result gets its frame temp only when `_sc_want` is the call's own start (`_sc_pre` / `_sc_pre_m`), so inside
the wrap no temp is made, `_sc_whole` finds no record spanning the element, and the element is kind 2 — a scalar for
the nested struct's first leaf; the second leaf then consumes the next element (`8`) and the literal runs out one
element early. A 24 B result always has its retptr temp, and an 8 B one comes back in rax (`_sc_whole` -3), so both
are right. Every other destination steps its whole wrap BEFORE it arms (`_scv_peel`, `_rcv_peel`, `_ret_peel`, 6.7.6 /
6.7.11); the literal element does not.

## Proposed fix

In `_spi_expr`, step inside parentheses that wrap the whole element (`_pwrap_name`-style, the token after the
outermost `)` a `,` or `}`; a tuple literal is no wrap) before `_sc_arm`, and close them (`_pw_close`) after the
parse, as `_scv_peel` / `_scv_disarm` do for a declaration. Rows: the two shapes above (64), the 24 B and 8 B twins
unchanged, double parentheses, at top level the by-name refusal once, a wrapped method of ANOTHER struct refused by
name.
