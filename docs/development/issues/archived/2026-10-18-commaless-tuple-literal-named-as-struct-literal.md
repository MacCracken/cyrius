# A commaless tuple literal is reported as "expected ',' between struct literal elements" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-15, `7315613d4` — no decision needed (a refusal's wording; refused before and after). `_slit_sep` (src/frontend/parse_decl.cyr) says "expected ',' between tuple literal elements" while `_tup_elems` stores a tuple element (`_slit_tup`, saved and restored), at every `_tup_elems` caller. The two filed repros now say "1:29 expected ',' between tuple literal elements" / "1:15 ..." (was "... struct literal elements"), at the same tokens, rc 1, on x86_64, aarch64, cx, PE and Mach-O; after a statement, an argument, an assignment and `--syntax-only` the same. A struct literal keeps its wording. The filing's proposed row `(P { 1 2 }, 3)` cannot name the inner element: the struct literal there is refused first by 6.7.14's D12 (a) ("a struct literal is an initializer: ..."), its one error, pinned as a control. Rows: `tests/gates/frontend/struct_literal_type_refused.sh` TU1 / TU2 (the repros verbatim), TU3 – TU5, TU8, controls TU6 / TU7; mutation (the tree without `_slit_tup`) RED TU1 – TU5, TU8. Filed beside it (placed IN 6.7.16): `(1 2)` leaving the name untyped, and `W { (1, 2), 3 }` cascading "unexpected '}'". CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend at 6593fbf1d, x86_64; the
frontend, every target). Introduced by the lane's e5a003c6f (D1 (a), the struct literal's required comma); the
slot-open compiler (b2e1f4c48) refused the same sources with "expected ')', got number 3".
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — refused before and after (rc 1, one error at the same token); only the wording changed, and it now
names the wrong construct for a tuple.
**Kind:** bug (diagnostic wording).
**Discovered:** by the frontend lane's review (2026-10-18), checking issues/archived/2026-10-16-struct-literal-elements-need-no-comma.md.

## Reproduction

```sh
cd <the tree>
printf 'fn f(): i64 { var t = (1, 2 3); return t.1; }\n' | build/cycc > /tmp/t1; echo "rc=$?"
# error:<source>:1:29: expected ',' between struct literal elements
# rc=1
printf 'var t = (1, 2 3);\n' | build/cycc > /tmp/t2; echo "rc=$?"
# error:<source>:1:15: expected ',' between struct literal elements
# rc=1
```

The slot-open compiler (b2e1f4c48's build/cycc) on the same two sources:

```
error:<source>:1:29: expected ')', got number 3
error:<source>:1:15: expected ')', got number 3
```

A two-element `(1 2)` is unchanged (`1:26: expected ')', got number 2`): the tuple shape check refuses it before the
element walk runs.

## Root cause

`_slit_sep` (src/frontend/parse_decl.cyr, 6.7.15 D1 (a)) is called at the end of EMIT_STRUCT_FIELD_W, the element store
that struct literals and tuple literals share: `_tup_elems` (same file) stores each tuple element through
EMIT_STRUCT_FIELD_W, so a missing `,` between tuple elements meets the struct literal's message.

## Proposed fix

`_tup_elems` sets a flag around its element walk (saved and restored, as `_sl_base_li` is) so `_slit_sep` says
"expected ',' between tuple literal elements" for a tuple. Rows: the two repros above give the tuple wording at the same
positions (1:29, 1:15); `P { 1 2 }` keeps the struct wording; a tuple of struct literals `(P { 1 2 }, 3)` names the
struct literal at the inner element (in struct_literal_type_refused.sh beside the D1 rows).
