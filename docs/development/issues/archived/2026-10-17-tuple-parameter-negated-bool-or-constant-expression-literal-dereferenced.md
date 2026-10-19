# Into a tuple parameter, a negated literal, a bool literal or a constant expression still compiles and is dereferenced as the tuple's address — `take(-5)`, `take((-5))`, `take(true)`, `take(5 + 0)` — where `take(5)` is refused (D44) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (RC-3, `140fd4c3e` — the user's decision D36 (a), 2026-10-18: refused by name. `_tup_arg_lit` (src/frontend/parse_fn.cyr) tests the tuple parameter first and scans the whole argument (`_tal_scan`): literals, `true` / `false`, unary `-` / `~` / `!`, the binary operators and parentheses; a name (a const too), a call, `&t`, a string or a float exempts it. Each filed argument — `-5`, `(-5)`, `true`, `5 + 0` — compiled and exited 139 / 139 / 1 / 5 (x86_64 / aarch64 / cx / PE) and is now refused once on all four and from the Mach-O compilers: "cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple" (`take(true)` / `take(false)`: "cannot pass a bool …"); `~0`, `(1 << 3)`, `(1) + 2`, a second argument, a method's `!true` and a top-level `'a' - 1` too. `take(&t)`, `take(u)`, `take(mk())` and a const `take(C)` still pass the address (34), as decided; a generic's tuple parameter keeps R4 alone. Rows: `frontend/tuple_checked.sh` R17w1 – R17w13 on x86_64, aarch64, cx and PE; mutations RED. Not closed here (filed, 6.7.16; outside D36's two texts): a float literal, `take(1.5)`, still compiles and faults (`2026-10-18-tuple-parameter-float-literal-dereferenced.md`); `take(1 == 1)` / `take(!0)` are refused in the integer words (`2026-10-18-tuple-parameter-comparison-argument-called-an-integer.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives, after D44's 5c4f1472 and
the review-fix step) with `build/cycc`, `cycc_aarch64`, `cycc_cx` and `cycc_win_cross` built from that tree.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D36 — (a) refused by name.
**Severity:** Low — compiles clean and crashes at run time (x86_64 / aarch64 SIGSEGV 139, cx guest error 1, PE
access violation 5); none of these values can be an address, and the spellings are unusual.
**Discovered:** 2026-10-17, the 6.7.14 receives lane's review of D44 (issues/2026-10-15-non-tuple-word-into-tuple-
parameter-dereferenced.md, probe rev/p/tl.cyr). The filed surface was `take(5)`; these shapes lie beyond it.

## Reproduction

Each program alone (`<ARG>` replaced by the argument in the table):

```cyrius
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return take(<ARG>); }
syscall(60, f());
```

| argument | compile | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (wine) |
|---|---|---|---|---|---|
| `-5` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `(-5)` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `true` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `5 + 0` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `5` (control) | refused | — | — | — | — |
| `'a'` (control) | refused | — | — | — | — |

The two controls (D44):

```
error:<source>:2:27: cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple
```

## Root cause

D44's check, `_tup_arg_lit` (src/frontend/parse_fn.cyr), is reached from `_try_push_struct_addr_arg` only when the
argument's first token is an integer literal (`PEEKT(S) == 1`) and only when the token after it is `,` or `)` — the
literal is the whole argument (`_sarg_paren` peels enclosing parentheses first, so `take((5))` is refused). A
leading unary minus (`-5` is `-` then `5`), a `true` / `false` keyword token and a literal followed by an operator
(`5 + 0`) never reach it, so they fall to the value push and the callee reads through the integer as the tuple's
address. The fix is the same refusal for every argument whose value is a compile-time integer or bool constant (a
negated literal, `true` / `false`, a constant expression) — none of which can be a tuple's address — while a name,
`&t` and a one-value call keep D44's decided "still the address".
