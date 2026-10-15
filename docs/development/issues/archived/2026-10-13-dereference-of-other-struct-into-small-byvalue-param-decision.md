# `take8(*pu)` with `pu: *U8` (a pointer to ANOTHER struct) into a by-value `S8` parameter compiles and passes U8's bytes; `take8(u)` with `u: U8` and the 16 B `take(*pu)` are refused by name — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ARG-6, with the review fix ARG-5r, per the user's decision of 2026-10-13 (D36, '(a) Refuse by name'; `take8(pu)` keeps the 2026-10-08 pointer rule): a whole dereference of another struct's pointer into a by-value struct parameter of 8 B or less is refused by name, so the rule is size-independent. The filed repro `take8(*pu)` is refused 'cannot pass 'pu' to a parameter of a different struct type in a call to 'take8'' on x86_64, aarch64, cx and PE, and so are the filing's `(*pu)`, `*gp()`, `*w.pu`, plus `*(pu + n)`, a tail call, `*self` in another struct's impl and a `Str` parameter (`sl(*pu)` SIGSEGV'd). `take8(pu)` still converts, a dereference of the same struct is accepted, and a generic carrier of the same instance through a dereference (`gw(*wp)`) binds T and calls `gw$i32` (ARG-5r). Rows: `struct_arg_type_refused.sh` D1–D12 (D9 an acceptance) and G2 / G4. A dereference as a tuple literal element (`(*ps, *pw)`) is outside the argument check — filed separately for 6.7.12. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN — a decision for the user** (is a dereference of another struct's pointer a struct of the wrong
type at 8 B or less too?). Verified 2026-10-13 against `build/cycc` 2,114,376 B (6.7.10, x86_64): `take8(*pu)` exits 7
(U8's `u`) with no diagnostic. Refused by name: `take8(u)` ("cannot pass 'u' to a parameter of a different struct
type"), the 16 B `take(*pu)` (the same message, naming `pu`), and `var l: S8 = *pu;` ("cannot copy 'pu' into a variable
of a different struct/vector type"). The plain pointer `take8(pu)` exits 7 too, and the 16 B `take(pu)` 7 — a typed
pointer of another struct "converts freely" into a struct parameter (the user's decision of 2026-10-08), and since
6.7.10's decision 7 the struct it points at is passed.
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** Low — no corruption: the callee reads a struct of the same size; a missed type check on one size class.
**Affects:** the 6.7.10 tree (measured there only, x86_64); the check is frontend-only, so every target.

## Summary

6.7.10 made a dereference `*p` a struct VALUE at every size (B7-1d, decision 6), and checks its struct where it is
copied: the declaration and the address-passed argument (ops-5's `_dro_check`) refuse a `*U` of another struct by
name. The by-value argument of 8 B or less does not ask the dereference's struct, so it passes. Two readings of the
2026-10-08 rule meet here: "a typed POINTER of another struct converts freely" (`pu`) versus "a struct VALUE of another
type is refused" (`u`, and `*pu` everywhere else).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/dv.cyr <<'EOF'
struct S8 { v; }
struct U8 { u; }
fn take8(s: S8): i64 { return s.v; }
fn main(): i64 { var u: U8; u.u = 7; var pu: *U8 = &u; return take8(*pu); }
syscall(60, main());
EOF
build/cycc < /tmp/dv.cyr > /tmp/dv && chmod +x /tmp/dv && /tmp/dv; echo $?           # 7, no diagnostic
sed 's/take8(\*pu)/take8(u)/' /tmp/dv.cyr | build/cycc > /tmp/dv2; echo $?             # 1: cannot pass 'u' to a parameter of a different struct type
cat > /tmp/dv16.cyr <<'EOF'
struct S { v; w; }
struct U { u; x; }
fn take(s: S): i64 { return s.v; }
fn main(): i64 { var u: U; u.u = 7; u.x = 1; var pu: *U = &u; return take(*pu); }
syscall(60, main());
EOF
build/cycc < /tmp/dv16.cyr > /tmp/dv16; echo $?                                          # 1: cannot pass 'pu' to a parameter of a different struct type
```

## Root cause

`_sarg_byval_small` (`src/frontend/parse_fn.cyr:1828`) checks a by-value argument of 8 B or less with
`_expr_struct_sid` (`:1844`), which reads a bare name, a whole call, a method / operator result and a whole
struct-typed field — not a dereference, so `*pu` is 0 (untyped) and `_sarg_type_err` (`:1498`) passes it. Over 8 B a
whole dereference is parked and checked by `_dro_check` (`:1679`) with the struct `_hl_dstar` typed.

## Proposed fix

The user's call, one of:

- **(a) Refuse `take8(*pu)` by name**, as `take8(u)`, the 16 B `take(*pu)` and `var l: S8 = *pu;` are: a dereference is
  a struct value, checked by its struct at every size (`_expr_struct_sid` gains the dereference arm, typed by
  `_hl_dstar` / `_hl_psid`). Stops code compiling. `take8(pu)` keeps the 2026-10-08 pointer rule.
- **(b) Accept it** as the pointer form is accepted (and then decide whether the 16 B `take(*pu)` and the declaration
  should accept it too, for one rule).
- **(c) Leave it**, documented.

Rows either way: `*pu`, `(*pu)`, `*gp()`, `*w.pu` into an 8 B parameter, in `struct_arg_type_refused.sh` or a `.tcyr`.

## Consumer-side workaround

Pass a value of the parameter's own struct: `var s: S8; s.v = pu.u; take8(s);`.
