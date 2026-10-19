# A `var` with `:` and no type (`var b: = 0;`, `var G: ;`) is reported as "expected '=', got number 0" — RESOLVED

> ✅ **RESOLVED in v6.7.15** (FE-6, `5b8126fe1` — 6.7.14's D15 (a) (a non-type annotation refused by name) applied to a `=` / `;` right after the `:`; no 6.7.15 decision asked. `_tn_head_var` (src/frontend/parse_types.cyr) reports the `=` / `;` and leaves the cursor on it, the zone replay's `_gvi_ann` steps no token there, and the bare-declaration refusal (`_decl_eq_err`) stands down for a `;` the annotation reported. The filed repro is `5:8 expected a type for variable 'G', got '='` + `2:12 ... 'b', got '='`, each declaration reading `= 0` / `= 4` as its initializer (was "expected '=', got number 0" / "number 4"); a zone `var G: ;` is `1:8 ... got ';'` alone; the zone `var c: ; var d = 2;`, which compiled with c = 2, is refused. Rows: `type_name_refused.sh` va_missing (moved to the new message), va_miss_lsemi / _dzeq / _dzcall / _dzsemi / _ppeq / _ppsemi / _next / _gen / _for, va_miss_repro (the filed repro verbatim), `--syntax-only`; mutations RED on their rows. Partly beyond its reach, filed (6.7.16): in a fn or after the first statement, `var c: ;` followed by a declaring statement still loses that statement ("undefined variable 'd'" follows) — the pre-existing bare-declaration class, `2026-10-18-bare-declaration-refusal-reads-next-statement-as-initializer.md`. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F4, f793b013) and on
the lane's base compiler (c0d6d1ba), x86_64 (the frontend: every target alike).
**Placement:** 6.7.15 — repair 5 (frontend lane, wave 1, unit F2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F4, beside
issues/archived/2026-10-14-var-annotation-non-type-token-compiles.md (D15 (a): a token that is no type is refused by name; a
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
