# `*(&p)` of a struct over 8 B — as an argument for a by-value struct parameter or a declaration's initialiser — reads its first word as the struct's address: SIGSEGV — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 callargs lane (after its review fixes) and the slot-open
compiler (`0f733aea`), alike. Since 6.7.10 (decision 6) a dereference `*p` is a struct VALUE at every size, and `take(*pp)`
with `pp: *P3` passes the struct (9 below). The same dereference spelled through an address-of, `*(&p)`, is not typed as
one: `take(*(&p))` into `fn take(p: P3)` exits 139 on x86_64 and aarch64 (1 on cx), and `var q: P3 = *(&p);` exits 139 on
x86_64 / aarch64 (252 on cx) — the struct's first field (1) is used as the struct's address. At 8 B or less the word IS
the struct, so `take(*(&s))` with `s: S1` gives 9 everywhere.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 callargs lane's review fix (probing `gsz(*(&bi))` for the generic carrier's
dereference arm, which binds nothing for it: the fault is the same through the base).
**Severity:** Medium — a SIGSEGV on valid code; the plain spellings (`take(p)`, `take(*pp)`, `var q: P3 = p;`) work.
**Affects:** 6.7.10 onward at least (the slot-open compiler; older releases not measured); x86_64, aarch64, cx (PE not
measured).

## Reproduction

```cyrius
struct P3 { a; b; c; }
fn take(p: P3): i64 { return p.c; }
fn go(): i64 {
    var p: P3; p.a = 1; p.b = 2; p.c = 9;
    var pp: *P3 = &p;
    return take(*pp) * 10 + take(*(&p));
}
syscall(60, go());
```

```
$ build/cycc < da.cyr > da && ./da; echo $?       # the lane compiler and the slot-open one alike
139                                               # aarch64 (qemu) 139, cx (cxvm) 1; 99 is right
```

```cyrius
struct P3 { a; b; c; }
fn go(): i64 {
    var p: P3; p.a = 1; p.b = 2; p.c = 9;
    var q: P3 = *(&p);
    return q.c;
}
syscall(60, go());
```

```
$ build/cycc < db.cyr > db && ./db; echo $?
139                                               # aarch64 139, cx 252; 9 is right
```

## Root cause

Not traced. The dereference readers that make `*p` a struct value type the operand from its tokens — `_hl_psid`
(parse_decl.cyr), used by the declaration's `_hl_dstar`, the argument's `_dro_check` / `_ess_deref` — and `_hl_psid`
answers 0 for `&x` ("an untyped value, a `*i64`, a struct value, `&x`, .."), so `*(&p)` is an untyped word load whose
value (p's first field) is then passed / copied from as the struct's address.

## Proposed fix

Type `&x` of a struct local / parameter / global as a `*S` in `_hl_psid` (its struct, `_hl_cp` 1) so `*(&p)` is the
struct value `p` is — or refuse `*(&p)` by name if that is the user's call. Rows beside the 6.7.10 decision-6 rows
(struct_arg_type_refused.sh D-rows, the declaration's `*p` rows), on x86 / aarch64 / cx / PE.
