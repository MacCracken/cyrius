# The value-form vector local refusal prints its fn-pointer hint for every source, and now reports an undefined function as a refused source — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 callargs lane (after its review fixes, x86_64). Since
6.7.11 (`2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md`, the user's decision: refuse by name) a value-form
vector local is initialised / assigned only from a local of its type or a call declared to return it. Two diagnostic
defects in that refusal: (1) its text always ends "; through a fn pointer held in a variable, give the target an
out-pointer", which is beside the point for a word source (`= 5`, `= load64(&w)`, `= &w`); (2) a call to a fn that does
not exist — `var v: f64v2 = f64v2_splat(1.0);` without `include "lib/simd.cyr"` — is now reported as a refused source
("got `f64v2_splat`") ahead of the undefined-function warnings, where the slot-open compiler's error was "refusing to emit
binary with 1 reachable undefined function(s)" after "undefined function 'f64v2_splat'". Diagnostic quality only: every
shape is still refused, and no binary is written.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the review of the 6.7.11 callargs lane (probes review/rev/vr/c8-c10, d7).
**Severity:** Low — message text; the refusal and its line are right.
**Affects:** 6.7.11 (the refusal is new); every target (frontend).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2 = 5; return lanes(v); }
syscall(60, run());
```

```
$ build/cycc < c8.cyr > c8                        # the 6.7.11 lane compiler
error:<source>:3:32: a value-form vector local is initialised only from a local of its type or a call declared to return it (by name, or fncallN / callptr with the callee written `&f`) - got `5`; through a fn pointer held in a variable, give the target an out-pointer
# (slot-open: compiled, exit 50.) The same hint for `= load64(&w)` (got `load64`) and `= &w` (got `&w`).
```

```cyrius
fn run(): i64 { var v: f64v2 = f64v2_splat(1.0); return 1; }
syscall(60, run());
```

```
$ build/cycc < d7.cyr > d7                        # the 6.7.11 lane compiler
error:<source>:1:32: a value-form vector local is initialised only from a local of its type or a call declared to return it (by name, or fncallN / callptr with the callee written `&f`) - got `f64v2_splat`; through a fn pointer held in a variable, give the target an out-pointer
warning: undefined function 'f64v2_splat'
warning: undefined function 'f64v2_splat' (reachable call site)
# slot-open: the two warnings, then "error: refusing to emit binary with 1 reachable undefined function(s)"
```

## Root cause

`_vrcv_err` (parse_decl.cyr) appends the fn-pointer hint unconditionally, and `_vrcv_decl_err` / `_vrcv_asg` refuse any
source that is not a known vector call before the call's name is resolved — an `IDENT (` that names no fn is not
distinguished from one that names a fn returning something else.

## Proposed fix

Print the hint only when the source is a call through `fncallN` / `callptr` whose callee is not written `&f`; leave an
`IDENT (` naming no fn (`FINDFN < 0`) to the undefined-function path (no refusal from the receive). Rows in
simd_return_shapes.sh (the message text) beside the existing refusal rows.
