# A struct-typed field, a struct call result or a struct dereference passed to a word-pointer parameter (`ri(w.s)`, `ri(mk())`, `ri(*pp)` with `p: *i64`) pushes its first word as the address — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-8, `9498bfb3f`: every struct VALUE passed to a pointer of another kind is refused by name, once: "cannot pass 's' to a parameter that is not a pointer to its struct type in a call to 'ri' - a struct value is no address". No new decision: 6.7.13's D5 (a), "a struct value", with its vector twin, 6.7.13's D31, "at every source". The values are a struct-typed field, a by-value call, a method or operator result, and a `*S` / `**S` dereference, wrapped or not, in a fn, a closure or at top level. The filed f1 / f2 / f3 (139 / 139 / cx 253 / PE 5) are each refused at compile time, one error each, on the x86_64, aarch64, cx and PE compilers. An address, a `*T` field, a `: *T` call or method, `*ppi` of a `**i64` and a `Str` field pass as before (42 on every leg). Rows: `struct_arg_type_refused.sh` V1 (the filed repro verbatim) - V17, VK1 - VK3; mutations RED 17 / 1 / 4. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 structs lane (unit S3) while landing D5 (a)
(issues/archived/2026-10-15-struct-local-into-word-pointer-parameter-pushes-first-word.md: a struct NAME — an inline local, a
by-value parameter, a value global, a capture — into a `*T` whose T is no struct is refused by name). Measured on the
lane tree after that bite, x86_64 / aarch64 (qemu) / cx (cxvm) / PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean and faults (or reads through whatever the first field holds), no diagnostic.
**Kind:** language — D5 (a)'s rule ("a struct value into a pointer of another kind is refused by name") stated for
the name shapes the filing listed; whether it reaches the other struct VALUE shapes (a field, a call, a method /
operator result, a dereference) is the same question at the remaining sources. (D27 left the vector twin's call
and dereference sources to archived/2026-10-15-vector-value-into-other-pointer-or-byvalue-struct-and-unreceived-call-sources.md.)

## Repro

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct W { s: Pt; }
fn ri(p: *i64): i64 { return load64(p); }
fn mk(): Pt { var r: Pt; r.x = 42; r.y = 7; return r; }
fn f1(): i64 { var w: W; w.s.x = 42; return ri(w.s); }
fn f2(): i64 { return ri(mk()); }
fn f3(): i64 { var s: Pt; s.x = 42; var pp: *Pt = &s; return ri(*pp); }
syscall(60, f1());     # f2() / f3() alike
```

```
f1 (ri(w.s)):  x86_64 139, aarch64 139, cx 253, PE 5     (no diagnostic)
f2 (ri(mk())): x86_64 139, aarch64 139, cx 253, PE 5
f3 (ri(*pp)):  x86_64 139, aarch64 139, cx 253, PE 5
```

`ri(s)` with `s` a local of Pt is refused since the D5 bite: "cannot pass 's' to a parameter that is not a pointer
to its struct type in a call to 'ri' - pass &s for its address".

## Root cause

A `*i64` parameter has no address-passed bit, so `_try_push_struct_addr_arg` hands the argument to
`_sarg_byval_small` (src/frontend/parse_fn.cyr), whose struct-kind check (`_sarg_struct_other`) reads only a whole
NAME (`_sarg_wname` + `_hl_amp_sid`); any other struct value is parsed and pushed by the value push, which is its
first word (a field's 8-byte load, a call's rax, a dereference's first word).

## Fix direction

The same refusal for the other whole struct-value arguments (`_expr_struct_sid` / `_ess_deref` already type them in
`_sarg_byval_small` for a by-value parameter's check) when the parameter is a pointer of another kind — or the
user's word that only names are refused.
