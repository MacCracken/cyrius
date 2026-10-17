# A `var` with `:` and no type (`var b: = 0;`, `var G: ;`) is reported as "expected '=', got number 0" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F4, f793b013) and on
the lane's base compiler (c0d6d1ba), x86_64 (the frontend: every target alike).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F4, beside
issues/2026-10-14-var-annotation-non-type-token-compiles.md (D15 (a): a token that is no type is refused by name; a
`=` / `;` right after the `:` is no annotation at all and was left to the error below, so the shape is not reported
twice).
**Severity:** Low — the declaration is refused (rc 1, one error), but the message names the wrong problem and the
wrong token.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
fn f(): i64 {
    var b: = 0;
    return b;
}
var G: = 4;
syscall(60, f() + G);
```

```
error:<source>:2:14: expected '=', got number 0
error:<source>:5:10: expected '=', got number 4
```

`var G: ;` in the declaration zone: `expected '=', got syscall` at the next line's first token. A parameter's missing
type (`fn f(a: )`) is "expected a type for parameter 'a', got ')'" (6.7.11).

Expected: one error each, at the token after the `:` — "expected a type for variable 'b', got '='" — and the
declaration read on from that `=` (so `= 0` is its initializer and nothing more is reported).

## Root cause

The annotation ladders (PARSE_VAR's else arm; PARSE_GVAR_REG after `_gvar_ann_head`) step one token after the `:`
whatever it is, so the `=` is consumed as the type and the initializer's `0` is read where `=` is expected. The
declaration-zone replay's `_gvi_ann` (src/frontend/parse_decl.cyr) steps the same token, so a fix that keeps the `=`
in pass 1 must keep it there too; `var G: ;` then reaches the bare-declaration refusal ("uninitialized variable not
allowed"), which should stand down after the annotation's report.

## Proposed fix

In `_tn_head_var` (src/frontend/parse_types.cyr), report a `=` / `;` too, and leave the cursor ON it (the ladders
step one token: put the cursor back one first); `_gvi_ann` steps no token at a `=` / `;`; the bare-declaration
refusal is skipped for a declaration whose annotation was refused. Rows beside type_name_refused.sh va_missing (which
pins today's single "expected '='"): local, both global zones x `=` / `;`, one error each, at the token after the `:`.
