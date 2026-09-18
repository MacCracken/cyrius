# A fn-local struct literal (and an oversized / opted-out array local) is a GLOBAL slot that shadows other files' globals — FIXED

**Status:** ✅ **FIXED in 6.6.5 (bite 4)** — both halves, plus a widened surface the filing
did not reach. See the CHANGELOG entry for 6.6.5 and the "Corrections to this filing" section
at the bottom of this file.
**Discovered:** 2026-09-13, by the adversarial reviewer of the marker-scoping repair, probing
whether the new `PARSE_STRUCT_INIT` stamp could fire inside a fn.
**Severity as filed:** Medium. **Actual:** Critical — see the corrections.
**Affects:** every cycc release up to and including 6.6.4.
**Gates:** `tests/gates/codegen/fn_local_storage_class.sh` (**25 rows over 11 axes, nine
mutants** — re-derived from the gate's own output, `PASS … 25 of 25 rows`, and from its
`MUTATION LEDGER`; this line said 17/8/seven, which was stale by review round 1's four rows and
round 2's four more), `tests/gates/codegen/hidden_temp_census.sh` (5 axes),
`tests/tcyr/crossos/aggregate_storage_class.tcyr`,
`tests/tcyr/crossos/hidden_temp_reentrancy.tcyr`,
`tests/tcyr/concurrency/struct_literal_threads.tcyr`, and the new aggregate-capture group in
`tests/tcyr/lang/closures_capture.tcyr`.

## Summary

```cyrius
# lib/a.cyr (private)                      # main.cyr
private                                    struct P { x; y; }
fn f() { var cfg = P { 1, 2 }; return cfg.x; }
public fn api() { return f(); }            include "lib/a.cyr"
                                           var cfg = 5;
                                           fn main() { return api() + cfg; }   # want 6
```

- **6.6.3 / bite-2 compiler:** builds, runs, returns **2** — `cfg` in `main.cyr` resolves (FINDVAR
  is last-match) to `a.cyr`'s fn-local `cfg` slot, which is a global in the flat namespace.
- **6.6.4:** refused with `'cfg' is private to its file` — pointing at the consumer's OWN `var
  cfg = 5`, because the private file's slot now carries `a.cyr`'s stamp and the lookup lands on
  it. Strictly better than a silent wrong value; still the wrong story.

The same shape for arrays: an in-fn `var big[200000]` (past the per-fn stack budget, so it
falls back to the shared global region) or any array local under `CYRIUS_STACK_ARRAYS=0`.
Default-on stack arrays (v6.3.15) are true locals and are NOT affected.

## Root cause

`src/frontend/parse_decl.cyr`: `PARSE_VAR` dispatches `var x = T { … }` to
`PARSE_STRUCT_INIT`, which always registers at `GVCNT` — a global slot — even with
`GINFN(S) == 1`; `PARSE_ARRAY`'s global-fallback path likewise. `FINDVAR` (parse_types.cyr) is a
single flat last-match table, so a later file's same-named global is shadowed by an earlier
file's fn-local slot. The `_GVAR_VIS` stamp added in v6.6.4 keys on the declaring file and
therefore correctly marks the slot private to `a.cyr`; the misattribution is that FINDVAR
returns that slot for `main.cyr`'s reference instead of `main.cyr`'s own global declared later.

## Why it was not packed into 6.6.4

Making struct-literal locals real locals means routing them through the per-thread stack-slot
mechanism `var arr[N]` locals got at v6.3.13/15 (frame slots + `EFLADDR` addressing +
initialiser stores into the frame), with the `_resolve_field_base_addr` inline rule already
in place for the read side. That is a codegen/storage change across every backend with its own
gate cycle, and a same-arity behaviour change for code that (accidentally) relied on the slot
persisting across calls. The alternative — gating the v6.6.4 stamp on `GINFN != 1` — would
restore the silent miscompile, which is worse. Reason named per the "cannot pack" rule.

## Proposed fix

1. `PARSE_STRUCT_INIT` inside a fn: allocate `ceil(STRUCTSZ/8)` frame slots (the v6.3.15 array
   mechanism, `-1` predecessor markers so `_resolve_field_base_addr` treats it as inline), emit
   the field initialisers as frame stores, register the NAME as a local. Same for the array
   fallback paths where the budget allows.
2. Until then, at minimum: `FINDVAR` should prefer a same-file / same-fn match over a
   last-match from another file's fn-local slot — or the diagnostic should say "shadowed by a
   fn-local slot in `lib/a.cyr:2`" rather than "'cfg' is private to its file".

Gate: the two-file shape above must return 6; the array-fallback shape (`var big[200000]` in a
private fn + `var big = 3` in the consumer) must return 3; a same-file struct-literal local
must keep working (in-tree: `tests/tcyr/lang/advanced.tcyr` and every `T { … }` local).

## Consumer-side workaround

Do not reuse a global's name for a struct-literal local in another file, or declare the
global BEFORE the include (last-match then finds the global — but note it is the *local* slot
that then loses, silently, inside the private file). Prefer heap structs (`var p: T =
alloc(N)`) for locals until this lands.

## Corrections to this filing

Written after the fix, because four of this file's own claims steered the work wrong and the
next reader should not re-derive them.

1. **"Not Critical: the collision needs the same identifier in two files."** REFUTED. One file
   is enough — a global, a fn with a struct literal of the same name and a later reader in ONE
   file returns 2 where 6 is right, on x86, aarch64, cx and PE. And *no collision at all is
   needed*: the literal is shared across RECURSION (`rec(3)` returns 0 for 9) and across
   THREADS (8 threads: 175,793 mismatches, 3 of 3 runs). Passing one to a by-value struct
   parameter SIGSEGVs. The severity is Critical.

2. **"v6.6.4 turned the silent miscompile into a diagnostic."** Only for a `private` declaring
   file. The same program without `private` compiles clean on 6.6.4 and still returns 2. The
   diagnostic's position is also the consumer's REFERENCE, not its declaration.

3. **"Proposed fix (1): reuse the `-1` predecessor marker so `_resolve_field_base_addr` treats
   the literal as inline."** REFUTED, and this is the important one — **the marker is not a
   sound discriminator and following this advice would have entrenched a second, larger bug**.
   `SCOPE_POP` writes -1 over every local of a closed block, and the callptr, bitset,
   SIMD-reserve and closure-env temporaries are registered -1 by construction. The guess had
   already been wrong since **5.8.17** for every pointer-mode struct local declared after such
   a slot: `var p: P = mk()` after an `if { var t; }` returns 6 for 22, `str_from(..).len`
   returns 6 for 7, `var p: P = callptr(..)` returns 181, copy-init reads a neighbour (99 for
   22), and `x = y` between two pointer-mode locals sets an unreached `defer` flag. The layout
   is now RECORDED at registration (`SLAGG`/`GLSPAN`, `src/common/util.cyr`), never inferred.

4. **"Not packable: a storage-class change across every backend with its own gate cycle."**
   No new backend emitter was needed. `EFLADDR_X1`, `EADDIMM_X1`, `ESTORE8/16/32` and `ESTOC`
   already existed on x86, aarch64 and cx, and PE plus both Mach-O targets reuse them; the one
   backend edit is coroutine address recovery in x86 `EFLADDR`/`EFLADDR_X1`. No heap or brk
   layout change: the span lives in the high half of the existing per-slot depth word.

5. **"In-tree coverage: `tests/tcyr/lang/advanced.tcyr` and every `T { … }` local."** The
   literal in `advanced.tcyr` is at TOP LEVEL, so it does not exercise this path at all.

### What the filing did not reach

The same audit found the hidden temporaries of `switch` / `match` / both `?` lowerings /
`for ... in` in global slots under NAME OFFSET 0 (the program's first lexed word), the
collection `for`-in index registered under the user-visible name `_i`, a `secret var` over the
frame budget that was refused and, when it did compile, never zeroised, closures unable to
capture an enclosing stack array or struct local, operator overloading that silently did an
integer add for a struct LOCAL while dispatching for a global, x86 `EFLADDR` addressing a dead
stack frame inside a coroutine, and cx's width-aware loads being 64-bit stubs. All are in the
6.6.5 entry.

Two more were reached only by the review round after the first cut of the fix, and both are the
same shape as claim 3 above — a check that shares a defect with the thing it checks:

* **`B = A` between two inline struct GLOBALS copied eight bytes**, along with `var b: P = A`
  (SIGSEGV), `B = p` and `q = A`. The copy resolver was local-only, so tightening the LOCAL side
  onto the recorded layout made the SAME assignment answer differently for globals and locals.
  It is one resolver now, and the global arm is addressed and byte-exact (a global slot index is
  not a word index, and globals are packed by exact byte size).
* **`ELOAD_LOCAL_ADDR`'s v6.5.70 coroutine recovery had never once fired**, because it was
  guarded on `_cur_fn_regalloc == 0` and an `async fn` body reserves the five callee-saved slots
  like any other fn. Harmless while `&name` and field access both addressed the stack; a silent
  0-for-11 the moment `EFLADDR`/`EFLADDR_X1` learned the heap frame in this release.

A SECOND review round found two more, both introduced by the repair itself and both of the
shape "the fix moved a variable to a new rung and the new rung did less than the old one":

* **A struct LITERAL in a suspending `async fn` disagreed with itself about where its own
  block was.** `_STRUCT_LIT_LOCAL` recorded the span (`SLAGG`) only after emitting the
  zero-fill and every initialiser store, so the stores based at the named slot and every later
  read based at `named - nslots + 1` — and the stores ran up to `nslots-1` slots past the block.
  `var p = P2{5,6}` across a suspend read **5** where 6.6.4 read 56. The TYPED form (`var p: P2;`)
  was correct throughout, which is why the first cut's axis 9 — typed rows only — passed.
  The span is now set before any byte is emitted.
* **A closure-captured struct stopped dispatching its operator overload.** Moving
  `var a = Num{1}` onto the frame moved it from the global rung (which sets the expression's
  struct type) to the capture rung (which did not): `|x| a + x` answered **2** for 102, and with
  `Num_add` deleted it COMPILED where 6.6.4 refused the program.

### Downstream

`stiva/src/fleet.cyr:257-275` carries a raw-offset workaround whose comment misattributes this
defect to the retired "struct-id 20/21" miscompile, and its memory-constraint check is
silently wrong on every cyrius up to 6.6.4 (a 512 MB node passes a 1024 MB constraint). Notify
stiva after the release; it needs no change to move its pin, only to drop the workaround.
