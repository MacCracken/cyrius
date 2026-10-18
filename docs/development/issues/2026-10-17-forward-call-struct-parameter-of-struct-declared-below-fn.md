# A call ABOVE a fn whose by-value / `*S` parameter names a struct declared BELOW that fn takes the pass-1 signature with no struct: the 16 / 24 B argument is pushed as its first word (SIGSEGV), a `*S` one is refused — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S2), probing the user-struct `Result`
item (issues/archived/2026-10-15-user-struct-named-result-option-tagged-is-a-handle-by-name.md) with the struct declared after
its use. Not that item's: any struct name does it. Pre-existing — identical on f133fb2f's build/cycc (the 6.7.14
wave-2 base) and on the lane tree after S2 (9498bfb3).
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — compiles clean and faults on every target measured (x86_64, aarch64 qemu, cx); the `*S` shape
is a false refusal of a valid program.
**Kind:** bug — CO-01 (6.3.5) made a forward call read the callee's pass-1 signature; 6.6.20's address-pass for
`p: *S` and the by-value address-pass over 8 B are decided there by `FINDSTRUCT`, which pass 1 answers 0 for a struct
it has not reached yet.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn main() { var t: R2 = R2 { 5, 7 }; return g(t); }
fn g(x: R2): i64 { return x.b; }
struct R2 { a; b; }
var r = main();
syscall(SYS_EXIT, r);
```

```
x86_64 139, aarch64 (qemu) 139, cx 1 (a guest fault)        want 7
```

The same with `struct R2 { a; b; c; }` (24 B; `R2 { 5, 7, 9 }`): x86_64 139. With a `*S` parameter:

```cyrius
include "lib/syscalls.cyr"
fn main() { var t: R2 = R2 { 5, 7 }; return g(&t) * 10 + h(t); }
fn g(x: *R2): i64 { return x.b; }
fn h(x: *R2): i64 { return x.b; }
struct R2 { a; b; }
var r = main();
syscall(SYS_EXIT, r);
```

```
error:<source>:2:60: cannot pass 't' to a parameter that is not a pointer to its struct type in a call to 'h' - pass &t for its address
```

(want 77: `h(t)` into `x: *R2` passes `&t`, 6.6.20). Controls, each 7: the struct declared ABOVE the fn (between
`main` and `g`, or first); `g` defined above `main` with the struct still last (pass 2 re-reads the definition before
the call).

## Root cause

`_prescan_fn_sig` (src/frontend/parse_fn.cyr, the pass-1 scan `_tl_scan1`) records each parameter's masks as it meets
the fn: `_param_wants_struct_ptr` / GFPSID ask `FINDSTRUCT`, and a struct declared below the fn is not registered yet,
so the parameter is a plain word (no struct-mask bit, no GFPSID). A call parsed in pass 2 before the fn's own pass-2
definition uses those masks: it pushes the struct's first word (the callee, defined with the struct known, reads
through it) or, for `x: *R2`, `_sarg_struct_other` sees a pointer recording no struct and refuses the struct name.

## Fix direction

Register every struct (name and size) before the pass-1 signature prescan reads a parameter type — a struct pre-pass,
or a second signature pass once pass 1 has seen every struct — so the prescan and the definition agree whatever the
order, as CO-01 intended. Rows: both repros; 8 / 16 / 24 B by value, `*S`, a method's parameter, a generic instance
`Box<R2>` declared below; the struct declared above (unchanged).
