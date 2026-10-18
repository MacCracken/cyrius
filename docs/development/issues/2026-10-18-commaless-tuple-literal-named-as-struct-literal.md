# A commaless tuple literal is reported as "expected ',' between struct literal elements" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend at 6593fbf1d, x86_64; the
frontend, every target). Introduced by the lane's e5a003c6f (D1 (a), the struct literal's required comma); the
slot-open compiler (b2e1f4c48) refused the same sources with "expected ')', got number 3".
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 frontend review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — refused before and after (rc 1, one error at the same token); only the wording changed, and it now
names the wrong construct for a tuple.
**Kind:** bug (diagnostic wording).
**Discovered:** by the frontend lane's review (2026-10-18), checking issues/2026-10-16-struct-literal-elements-need-no-comma.md.

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
