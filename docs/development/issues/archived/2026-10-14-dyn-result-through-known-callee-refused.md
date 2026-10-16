# A `dyn Tr` result through a known callee (`var a: dyn Shape = fncall1(&mkd, &q);`) is refused, where `mkd(&q)` forms the dyn — RESOLVED

> ✅ **RESOLVED in v6.7.13** (RC-8, `1330b9ed`: the user's decision D15 (a), 2026-10-15 — a known `&f` callee declared `: dyn Tr` is a dyn source, as the direct call is (`_dyn_icall` reads the call as `mkd(&q)`). The filed repro exits 18 on x86_64, aarch64, cx and PE (it was refused "cannot form dyn Shape from this expression"); `callptr(&mkd, &q)`, `fncall1((&mkd), &q)`, `(fncall1(&mkd, &q))`, a `*Sq`-returning callee, and an assignment / argument / field store / `return` give 18 / 42. A callee held in a variable stays refused (FP6, 6.7.11's D31); at top level the one no-frame refusal, as `mkd(&Q0)`. Rows: `dyn_checked.sh` KC1 (the repro verbatim) – KC7; `crossos/dyn_objects.tcyr` §known (x86_64 IR=1 / IR=3 / DCE=1, aarch64, cx, PE); mutants M-KC1, M-KC2 RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 callargs lane (after its review fixes, x86_64) and the
slot-open compiler (`0f733aea`): the same rc 1 and message on both. With `fn mkd(p: *Sq): dyn Shape`, `var b: dyn Shape =
mkd(&q);` compiles and runs, but `var a: dyn Shape = fncall1(&mkd, &q);` is refused "cannot form dyn Shape from this
expression". 6.7.11 gave a KNOWN callee (`&f`) the struct-result conventions (`_icall_sret` / `_icall_result`'s
`_sc_post`), but the dyn-forming receive does not recognise that call as returning a `dyn`.
**Placement:** 6.7.13 — repair 3: struct values (receives lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D15 — (a).
**Discovered:** 2026-10-14, the review of the 6.7.11 callargs lane (probe review/rev/sr/dy2.cyr).
**Severity:** Low — a refusal by name with a working spelling (call `mkd(&q)` directly, or bind the result first).
**Affects:** every release with `dyn` (the indirect call never carried it); every target (frontend).

## Reproduction

```cyrius
include "lib/fnptr.cyr"
trait Shape { fn area(self): i64; }
struct Sq { s; }
impl Shape for Sq { fn area(self): i64 { return self.s * self.s; } }
fn mkd(p: *Sq): dyn Shape { var o: dyn Shape = p; return o; }
fn run(): i64 { var q = Sq { 3 }; var a: dyn Shape = fncall1(&mkd, &q); var b: dyn Shape = mkd(&q); return a.area() + b.area(); }
syscall(60, run());
```

```
$ build/cycc < dy2.cyr > dy2                      # the 6.7.11 lane compiler and the slot-open one alike
error:<source>:6:54: cannot form dyn Shape from this expression - a dyn is formed from a `*T` the compiler knows (`&p`, a `*T` name, a pointer-mode handle, a `*T` field or call), a declared scalar or a literal: bind it to a declared variable first
# without the `a` declaration (b alone): exit 9
```

## Root cause

The dyn-forming receive (parse_decl.cyr, the `dyn` declaration path) accepts a by-name call declared `: dyn Tr` (and the
`*T` sources its message lists); a `fncallN(&f, ..)` / `callptr(&f, ..)` with a known `f` is not among them — the
6.7.11 known-callee route (`_icall_callee` / `_icall_rs_at`) is consulted by the struct and vector receives only.

## Proposed fix

Treat a known-callee indirect call whose callee is declared `: dyn Tr` as that call (its two-word result as the direct
call's), via `_icall_rs_at`; rows in tests/gates/frontend/dyn_checked.sh beside the by-name receive, on x86 / aarch64 /
cx / PE. A callee in a variable stays refused (its return is unknown), as for a struct (the user's decision, 2026-10-13: FP6).
