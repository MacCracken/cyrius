# A bounded-forward judgement deeper than 64 generics silently answers "not bad": a valid 65+-deep forwarding chain is refused at a definition — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 generics lane's review fix step on the lane tree (after
95b7f735, issues/2026-10-14-generic-forwarding-to-bounded-generic-refused-at-f64.md), x86_64.
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-17, the 6.7.14 generics lane review. 95b7f735 makes a generic that forwards its `T` to a bounded
generic whose i64 base is refused have no i64 instance, judged by `_bbs_fwd_bad` (src/frontend/parse_fn.cyr). The
judgement recurses through the forwards with a depth cap, `if (_bbf_dep > 64) { return 0; }`, which answers "not bad"
past it: the deep end of a long chain keeps its i64 base, that base calls the next forwarder at i64, and the call is
refused. The lane states the reach ("up to 64 forwards", guide § Trait bounds; gate row trait_bounds_checked.sh F12, a
64-forward chain, exits 5) instead of the "any number of forwards" it first wrote.
**Severity:** Low — a valid program is refused at compile time (no miscompile); a real chain of 65+ forwarders is rare,
and the existing instance-nesting refusal ("nesting too deep (over 256 levels)") bounds real chains at about 120.

## Reproduction

A chain `o69 -> o68 -> .. -> o0 -> gb<T: Show>`, only `impl Show for f64`, called at f64 (generated; lines 5-74 are
`fn oK<T>(x: T): i64 { return oK-1(x); }`):

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn o0<T>(x: T): i64 { return gb(x); }
fn o1<T>(x: T): i64 { return o0(x); }
# .. o2 .. o68, each forwarding to the one below ..
fn o69<T>(x: T): i64 { return o68(x); }
fn main(): i64 { var h: f64 = 1.5; return o69(h); }
syscall(60, main());
```

```
error:<source>:70:35: generic 'o64' has no i64 instance: it forwards its type parameter to 'o63'
    fn o65<T>(x: T): i64 { return o64(x); }
                                      ^
  note: the bound on type parameter 'T' of 'gb' needs `impl Show for i64`, and there is none
```

Right: exit 5 (`o69(h)` calls `o69$f64` down the chain to `gb$f64`). The same chain 60 deep (o0..o59) exits 5; the
boundary is exact: 65 forwarders (o0..o64) compile, 66 are refused at o65's definition. (The slot-open compiler refused
every depth: "generic 'o69' ... uses its type parameter as a struct", the defect 95b7f735 fixed.)

## Root cause

`_bbs_fwd_bad` (src/frontend/parse_fn.cyr) scans fi, then judges each generic it forwards to with `_bnd_base_bad`,
recursively; `_bbf_vis` (a visited list per judgement) already ends cycles, and the depth cap is a second guard. Past
64 levels the answer is 0 ("not bad"), so the generic at that depth keeps an i64 base, which the chain above it then
calls at i64. Removing the cap alone (measured by the review on a scratch tree, fixpoint OK) makes the 70-deep chain
exit 5, but the uncached judgement is then quadratic: a 3000-deep chain took 39.8 s (2.5 s with the cap) before the
existing "nesting too deep (over 256 levels)" refusal.

**Fix direction:** memoise `_bnd_base_bad` per generic in pass 2 (every impl is known after pass 1, so a generic's
verdict does not change), then drop the depth cap; trait_bounds_checked.sh F12 grows a 70- (and a 120-) deep row, and
the guide's "up to 64 forwards" goes.
