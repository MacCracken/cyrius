# `var s: *u8 = "abc" + 1;` and `= ("abc");` still warn "assigning non-pointer to typed pointer" — 6.7.14 exempts a string literal into a byte pointer only when it stands alone before the `;` — RESOLVED

> ✅ **RESOLVED in v6.7.15** (RC-7, `cbf7e15d0` — no decision needed for the shape: `_tp_str_exempt` (src/frontend/parse_decl.cyr) exempts a string literal plus or minus one integer operand (a literal or a single name), under parentheses that wrap it whole; the issue's other option (a byte pointer's scale on a string literal) is not taken. The destination is D59's (the user, 2026-10-18; RC-6, `7b2eafece`): no string literal warns into any `*T`, so the row this issue asked for, a string into `*i64` warning, is quiet by decision. The filed repro (`"abc" + 1`, `("xyz")` into `*u8`) warned twice (3:27, 4:25) and now builds with no warning, exit 218, on x86_64, aarch64, cx and PE and from the Mach-O compilers; binaries byte-identical. `"abc" + x * 2` and `'a' + 0` still warn. Rows: `diagnostics/typed_pointer_warn_sign.sh` axis 15, SL0 (the repro verbatim) – SL5 quiet, SLK1 / SLK2 warn; mutation RED 6. Not closed here (filed, 6.7.16; the literal 0, outside this filing): `var p: *i64 = (0);` still warns (`2026-10-18-parenthesised-null-literal-into-typed-pointer-warns.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives at 63aa1cb8, unit R4, after the
string-literal bite), x86_64; the warning is the shared frontend's, every target the same.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a false warning on valid code that runs right; nothing miscompiles.
**Discovered:** 2026-10-17, the receives lane (unit R4), repairing
`issues/archived/2026-10-16-typed-pointer-warning-string-literal-and-address-of-subscript.md`, whose filed fix is "a string
literal (token type of a string constant, alone up to the terminator)" — `_tp_exempt` (src/frontend/parse_decl.cyr).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 {
    var s: *u8 = "abc" + 1;
    var t: *u8 = ("xyz");
    return load8(s) + load8(t);
}
syscall(60, main());
```

```
warning:<source>:3:27: assigning non-pointer to typed pointer
warning:<source>:4:25: assigning non-pointer to typed pointer
```

rc 0; exits 218 ('b' + 'x'). `var s: *u8 = "abc";` beside them is quiet.

## Root cause

A string literal's value is its address but sets no pointer scale (GPSC 0), so every site's warning test (`aps == 0`,
`expr_ps == 0`) sees a non-pointer; `_tp_exempt` recognises only the literal alone before the `;`. `"abc" + 1` is byte
arithmetic on that address (its result also has scale 0), and the wrap is the same value.

## The question / proposed fix

Give a string literal a byte pointer's scale (step 1, element u8) where it is a factor — which also makes `"abc" + n`
pointer arithmetic by one byte (it already is: the step is 1) and a string into a `*i64` would then warn as a `*u8`
value does — or widen `_tp_exempt` to a wrapped literal and `literal + / - integer`. The first changes what other
sites see of a string (overload routing, a compare-mix warning), so it is a question; rows: wrapped, `+ n`, `- n`, a
string into `*i64` (warns), in a fn, the zone and an assignment.
