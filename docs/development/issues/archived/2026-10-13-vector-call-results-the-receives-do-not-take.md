# A call DECLARED to return a vector that the vector receive / return still do not take: a method call, an untyped `var v = callptr(&f, ..)`, `return callptr(&f, ..)` — RESOLVED

> ✅ **RESOLVED in v6.7.13** (VC-4, `2d020a72`: the user's decision D29, 2026-10-15 (A — taken as the vector). The three filed repros exit 161 on x86_64, IR=3, aarch64, cx and PE and on ecb, ach, pi and cass: `var v: f64v2 = s.mv();` — a method declared `: f64v2` initialises or is assigned to the vector local (on Windows the local's address is the method's hidden result pointer, before `self`); an unannotated `var v = callptr(&mkv, 41, 7);` declares an `f64v2` local (it was one word, and `lanes(v)` faulted on Windows); `return callptr(&mkv, a, b);` from a `: f64v2` fn is accepted (on Windows through a temporary copied into the result pointer). A method declared to return another vector is refused as a by-name call is; a callee held in a variable stays a word. Rows: `simd_return_shapes.sh` C1-C5 (the repros verbatim, five legs) and Q1-Q4 (refused once), `simd_indirect_receive.tcyr` groups M, U and R (30 → 49 rows); mutations MC1-MC5 RED. Filed beside it: the method destinations the filing did not name — an unannotated `var v = s.mv();` still binds one word (wrong lanes, silently), `var x: i64 = s.mv()` compiles, `return s.mv();` is refused. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-13 on the 6.7.11 callargs lane tree (unit A1) and the slot-open compiler
(`0f733aea`). The 6.7.11 decision on `2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md` (the user's, 2026-10-13:
"(a) refuse both by name") accepts into a value-form vector local exactly a local of the type, a by-name call declared
to return it (also parenthesised) and `fncallN(&f, ..)` / `callptr(&f, ..)` with a known `f`; every other source is
refused by name. Three sources that ARE calls declared to return the vector are left outside that list:
(1) `var v: f64v2 = s.mv();` with `impl S { fn mv(self): f64v2 }` — read wrong lanes before (x86_64 1, aarch64 1, cx 155,
PE 41 where 161 is right, `lanes(v)` below) and is refused by name since A1; (2) an untyped `var v = callptr(&mkv, 41, 7);`
binds an untyped word — `lanes(v)` is refused "value-form SIMD arg must be a 16-byte vector" on x86_64 / aarch64 / cx
and page-faults on PE (exit 5), where `var v = mkv(41, 7);` infers the vector; (3) `return callptr(&mkv, a, b);` from
a fn declared `: f64v2` is refused by the 6.6.6 return rule ("got `this expression`"), as through a variable.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D29 — A.
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A1).
**Severity:** Medium. (1) and (3) are refused loudly (no wrong value); (2) is refused on three targets and crashes
on PE (`2026-10-13-pe-discarded-vector-call-result-no-hidden-pointer.md` is that crash's class).
**Affects:** every value-form vector type; all four targets.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 {
    var s: S = S { 1 };
    var v: f64v2 = s.mv();
    return lanes(v);
}
syscall(60, run() % 256);
```
A1 tree: `error:<source>:8:20: a value-form vector local is initialised only from a local of its type or a call
declared to return it (by name, or fncallN / callptr with the callee written `&f`) - got `s`; ...` on all four targets.
Slot-open compiler: x86_64 1, aarch64 1, cx 155, PE 41 (161 is right).

```cyrius
include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    var v = callptr(&mkv, 41, 7);
    return lanes(v);
}
syscall(60, run() % 256);
```
Both compilers: `error:<source>:6:19: value-form SIMD arg must be a 16-byte vector` on x86_64 / aarch64 / cx; PE
compiles and exits 5 (a page fault).

```cyrius
include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn fwd(a, b): f64v2 { return callptr(&mkv, a, b); }
fn run(): i64 { var v: f64v2 = fwd(41, 7); return lanes(v); }
syscall(60, run() % 256);
```
Both compilers: `error:<source>:4:30: a vector-returning fn carries its result in a fixed register pair, so `return`
takes a local of that vector type or a call to a fn declared to return the same one — got `this expression``.

## Root cause

The receive (`_vrcv_src`, parse_decl.cyr) recognises a by-name call and a known indirect callee from the tokens; the
method arm (`_field_load_on`) emits its own call with no vector destination, and `_sc_pre` / `_sc_post` serve structs
only. The untyped declaration infers a vector only from `IDENT (` (the `_vin_*` block in PARSE_VAR). The vector return
rule (`_simd_ret_call_ok`) accepts only `IDENT (` by name.

## Proposed fix

A question for the user first (what compiles changes): should a method call declared `: <vector>`, an untyped
declaration from `fncallN(&f, ..)` / `callptr(&f, ..)` with `f` declared `: <vector>`, and `return` of that indirect call
be taken as the vector they are declared to be (the by-name call's receive and PE hidden pointer), or stay refused?
If taken: the method arm takes the receive's destination (PE: its address as the hidden pointer after `self`'s slot),
the untyped declaration infers the descriptor from `_icall_rs_at`, and `_simd_ret_call_ok` accepts a known `&f` callee
of the same declared type. Rows on all four targets, the three repros above.
