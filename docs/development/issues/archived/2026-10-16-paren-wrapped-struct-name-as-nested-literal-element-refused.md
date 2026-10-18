# `HE { 7, (q0), 8 }` — a struct LOCAL in parentheses as a nested-struct literal element is "unexpected '}'" — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-7, `11677414` — no decision needed: guide § Parentheses names "a name" among the transparent sources (6.7.11's D44): a struct name in parentheses as a nested-struct literal element — `HE { 7, (q0), 8 }`, `((q0))`, a global `(G)`, a by-value or `*QE` parameter, a capture, in a fn or at top level — is the element the unwrapped name is (`_spi_pname` steps into the whole-element wrap, `_spi_name` takes the name, `_pw_close` closes it). The filed repro exits 64 (it was "unexpected '}'") on x86_64, aarch64, cx and PE; another struct's name is refused once by name, as unwrapped; 13 shapes written `x`, `(x)`, `((x))` compile byte-identical. Rows: `crossos/struct_value_codegen.tcyr` Q49 – Q52 (also on pi and cass); `codegen/struct_value_codegen.sh` PN1 (the repro verbatim, `docs/development/issues/repros/2026-10-16-paren-wrapped-struct-name-as-nested-literal-element-refused.cyr`) – PN7; mutations M-PN1 / M-PN2 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane (unit R1, after its wrapped
method / operator element commit) and with the lane base (`f59668ad`): x86_64, aarch64 (qemu), cx (cxvm), PE (wine)
refuse it alike (frontend).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — valid source refused loudly (the reason is wrong: an "unexpected '}'"); no wrong value. Workaround:
drop the parentheses.
**Discovered:** 2026-10-16, the receives lane, repairing
`issues/archived/2026-10-14-paren-wrapped-pair-method-or-operator-as-nested-literal-element-refused.md` (whose filed surface is
a wrapped method / operator result; its fix also made a wrapped struct-typed FIELD `(h.q)` an element). Guide
§ Parentheses: a wrap around a whole struct source is transparent "for every source shape — a name, a field, a call,
a method or an operator result — into every struct destination", the nested literal element included.

## Reproduction

```cyrius
struct QE { a; b; }
struct HE { x; q: QE; z; }
fn main(): i64 {
    var q0 = QE { 4, 9 };
    var h = HE { 7, (q0), 8 };
    return h.x + h.q.a * 10 + h.q.b + h.z;
}
syscall(60, main());
```

```
$ build/cycc < r.cyr > r
error:<source>:5:29: unexpected '}'
```

Unwrapped (`HE { 7, q0, 8 }`) the program exits 64. `((q0))` is refused the same way.

## Root cause

`_spi_src` (`src/frontend/parse_decl.cyr`) takes a named struct element only as `IDENT ,` / `IDENT }` (`_spi_name`).
A `(` goes to `_spi_pcall` (a wrapped CALL only) and then `_spi_expr`, which parses `q0` as an expression: a name
records no struct-call temp and no field hit, so it is a scalar for the nested struct's first leaf, the next element
fills its second leaf and the literal runs one element short.

## Proposed fix

In `_spi_src`, peel a whole-element wrap (`_spi_epk`, 6.7.13) before the `IDENT ,` / `IDENT }` test — the name then
followed by the wrap's `)` — take it as `_spi_name` does, and close the wrap (`_pw_close`). Rows beside
tests/tcyr/crossos/struct_value_codegen.tcyr Q42-Q48: `(q0)`, `((q0))`, a struct of another type refused by name as
the unwrapped name is, a global name at top level.
