# A struct literal naming an undeclared struct (`var x = Q { 1 };`) is two errors — "undefined variable 'Q'" then "expected ';', got '{'" (in a fn, three more) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-26, `3e39def4b` (with SS-27 `f59666b5a`, a positional literal short of a field, met) — no decision needed. `_slit_undecl` keeps the one "undefined variable 'Q' (missing include or enum?)" at the name, steps the `{ .. }` and marks a declared variable; the zone sweep marks such a global (`_gu_slit0`). The top-level repro prints 2:11 and 3:11 (it printed four errors); the fn repro prints 3:15 and its line 4's own "4:19: missing struct field in initializer" (it printed five) — line 4, `var y = P { 2 };` with two fields, is a second, genuine mistake (SS-27 gives it its words); an assignment, a `return` and an argument the same; `--syntax-only` with a sibling file's struct prints nothing. On x86_64, aarch64, cx and PE. Rows: `dx_multi_error.sh` L1 (the top-level repro), L2 (the fn repro), L3 – L13; `struct_literal_type_refused.sh` SH1 – SH9. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at 2bf80a6d3, unit Z3, x86_64; the shared
front end); the pair pre-exists (7965f3685's compiler prints it for line 2, and the fn form identically). Met while checking that the zone replay's per-entry latch release
(issues/archived/2026-10-18-zone-replay-reports-only-first-latched-error.md) adds no cascade of its own: it does not — it
reports this pre-existing pair once per declaration, as a fn does.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ1) — never 7.x.
**Severity:** Low — refused (rc 1); an invented second error (more in a fn).
**Kind:** bug (diagnostics: a refusal cascade).

## Reproduction

```cyrius
struct P { a; }
var x = Q { 1 };
var y = R { 2 };
syscall(60, 0);
```

```
error:<source>:2:11: undefined variable 'Q' (missing include or enum?)
error:<source>:2:11: expected ';', got '{'
error:<source>:3:11: undefined variable 'R' (missing include or enum?)
error:<source>:3:11: expected ';', got '{'
```

(Before 6.7.16's latch release the zone printed the first pair and line 3's "undefined variable 'R'" — an undefined
name latches nothing — with line 3's "expected ';'" swallowed.) In a fn the same mistake cascades further:

```cyrius
struct P { a; b; }
fn f(): i64 {
    var x = Q { 1 };
    var y = P { 2 };
    return 0;
}
syscall(60, f());
```

```
error:<source>:3:15: undefined variable 'Q' (missing include or enum?)
error:<source>:3:15: expected ';', got '{'
error:<source>:3:20: unexpected ';'
error:<source>:4:19: unexpected '}'
error:<source>:5:5: return outside a fn body
```

## Root cause (not traced to the line)

`Q {` with Q no struct is not taken as a literal head (`_lit_head_tok` / `_lit_head_w` want a declared struct), so `Q`
parses as a name (undefined) and the declaration's `;` check meets the `{`; in a fn the resync then stops inside the
literal's braces and the block loop misreads the rest. A `NAME {` initialiser whose NAME is no variable could be
refused once as an unknown struct ("unknown struct 'Q' in a struct literal") with the literal skipped whole.
