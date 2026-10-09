# A trait's required signature is never parsed, and an overridden default method's is not either — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 with the tree's `build/cycc`: junk in a
trait's required signature (`fn sh(self, n + foo bar): i64;`) and in a default method that every impl overrides
(`fn tw(self, k 1 2): i64 { … }`) compiles clean and runs (rc 0, exit 7).
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 2026-10-09 during the 6.7.7 B6 (default and named arguments) planning (repro `tsig.cyr`).
**Severity:** Low — invalid source accepted. Nothing that is valid miscompiles, because the unparsed tokens never
reach codegen.
**Affects:** cycc 6.7.0 – 6.7.6 (checked traits, A1 / A2). Measured on 6.7.0, 6.7.3 and 6.7.6.

## Summary

The trait pre-scan reads only two things from a member's signature: the name, and the parameter count (it counts the
commas). Nothing else in a **required** signature (`fn sh(self, n): i64;`) is ever parsed: not the parameters, not
their types, and nothing between the `)` and the `;`. A **default** method's signature and body are parsed only when
an impl inherits the body. If every impl overrides it, or no impl exists, its tokens are skipped too.

So `n + foo bar`, `k 1 2`, an unknown type name or a stray token compiles silently, and the error appears only if a
later impl inherits that default.

The 6.7.7 B6 decision covers one shape of this gap. A parameter default (`= …`) in a required signature becomes an
error ("a trait's methods take no parameter defaults"; fork F1, user 2026-10-09). This issue is everything else.

## Reproduction

`docs/development/issues/repros/2026-10-09-trait-signature-parameter-list-unparsed.cyr`:

```cyrius
trait Sh {
    fn sh(self, n + foo bar): i64;
    fn tw(self, k 1 2): i64 { return 1; }
}
struct P { v; }
impl Sh for P {
    fn sh(self, n): i64 { return self.v + n; }
    fn tw(self, k): i64 { return k; }
}
fn main(): i64 { var p = P { 5 }; return p.sh(2); }
var rc = main();
syscall(60, rc);
```

```sh
cat docs/development/issues/repros/2026-10-09-trait-signature-parameter-list-unparsed.cyr | build/cycc > /tmp/t && chmod +x /tmp/t && /tmp/t; echo $?
# actual:   rc 0, exit 7
# expected: a parse error at `+` (line 9) and at `1` (line 10)
```

If `P`'s own `tw` is deleted, the impl inherits the default body and the compiler reports
`expected ')', got number 1` at line 10. That is the parse every default method should get.

## Root cause

- `src/frontend/parse_fn.cyr:4749` `_tr_scan_tm` (pass 1, from `_tr_prepass` :4700): `_tr_paren` finds the `(`,
  `_tr_arity` (:4642) counts the depth-0 commas, and the loop skips to the `;` or `{` without looking at the tokens in
  between.
- `src/frontend/parse_fn.cyr:5125` `_tl_trait2` (pass 2) checks only that the trait body is a sequence of `fn`
  members, then skips it.
- `src/frontend/parse_fn.cyr:5059` `_tr_defaults` parses a default method (`_prescan_fn_sig`, then `PARSE_FN_DEF`)
  only for an impl that does not define that method.

## Proposed fix

In pass 2, parse each member's signature once, at the trait itself, without emitting anything. Use the same
parameter-list walk a fn definition uses (name, optional `: type`, `,` / `)`), then the return annotation, then `;`.
For a default method, parse its signature the same way even when no impl inherits it.

The body of a default method that no impl inherits can stay unparsed: that is the generic-template rule, where a body
nothing instantiates is not emitted. Its signature should still be checked.

Add gate rows for the two repro lines, one row for the inherited control, and the 6.7.0 trait gates unchanged.

## Consumer-side workaround

None needed. Valid traits are unaffected; only invalid ones are accepted.
