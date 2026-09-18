# A value-form SIMD argument alongside six or more int-class arguments silently miscompiles — on every call path

**Status:** 🟡 **OPEN** — pre-existing, not a 6.6.5 regression; found while verifying 6.6.5 bite 3's method-arg SIMD gate.
**Placement:** unpinned — 6.x line. Not parked to 7.x (nothing codegen is).
**Discovered:** 2026-09-17, review round 3 of 6.6.5 bite 3, x86_64 Linux.
**Severity:** High — a silent wrong value with no diagnostic, on ordinary source, on the documented
value-form SIMD parameter ABI. No crash, so it reads as a logic bug in the consumer.
**Affects:** cycc 6.6.4 (`git show 6.6.4:build/cycc`) and 6.6.5 identically. A free-fn-only
compiland is BYTE-IDENTICAL between the two, so 6.6.5 did not introduce it and did not move it.

## Summary

A callee that mixes a value-form SIMD parameter with int-class parameters is correct while the
int-class count is ≤ 5 and wrong from **6** onward. The SIMD argument itself survives; the INT
arguments after the register ceiling bind to the wrong slots.

On SysV the two classes have independent counters — `_fc_int_argc` (pushed, popped into
RDI/RSI/RDX/RCX/R8/R9 by `ECALLPOPS`) and `_fc_simd_count` (recorded, loaded into XMM by the
second pass). The callee side counts int-class params with `int_pc` and homes only
`int_pc + _pp_shift < 6` (`src/frontend/parse_fn.cyr`, PARSE_FN_DEF's parameter loop), while the
SIMD branch allocates `nslots` FRAME slots for the vector. The two sides disagree once the int
args reach the ceiling; which side is wrong has not been isolated.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/simd.cyr"

fn n5(v: f64v2, a, b, c, d, e): i64 { return a*10000 + b*1000 + c*100 + d*10 + e; }
fn n6(v: f64v2, a, b, c, d, e, f): i64 { return a*100000 + b*10000 + c*1000 + d*100 + e*10 + f; }
fn n7(v: f64v2, a, b, c, d, e, f, g): i64 { return a*1000000 + b*100000 + c*10000 + d*1000 + e*100 + f*10 + g; }

fn main(): i64 {
    alloc_init();
    var v = f64v2_make(9, 0);
    print_num(n5(v, 1,2,3,4,5));   print_num(0-1);
    print_num(n6(v, 1,2,3,4,5,6)); print_num(0-1);
    print_num(n7(v, 1,2,3,4,5,6,7));
    return 0;
}
var e = main();
syscall(60, e);
```

Measured, `cat repro.cyr | ./build/cycc`, identical on 6.6.4 and 6.6.5:

| call | want | got |
|---|---|---|
| `n5` (5 int args) | `12345` | `12345` ✅ |
| `n6` (6 int args) | `123456` | `123406` — param `e` read **0** |
| `n7` (7 int args) | `1234567` | `1234171` — `e`, `f`, `g` all wrong |

The SIMD-arg-last shape fails the same way: `fn f7(s, a, b, v: f64v2, c, d, e, f)` called as
`f7(0,1,2,v,3,4,5,6)` returns `3688501086957876468` for `9123456`.

## Both call paths inherit it

6.6.5 gave the method-call path the SIMD record + second pass it was missing, which means it now
inherits this defect too: `w.many(1,2,v,3,4,5,6)` is garbage on 6.6.4 (wrong for a different
reason — the vector went in as an int arg) and garbage on 6.6.5 (wrong for THIS reason). The
method path is not a separate bug; fixing this fixes both, and
`tests/gates/frontend/method_call_runs_every_callee_gate.sh` compares the two arms, so it will
keep agreeing while both are wrong. **That gate cannot catch this** — it is a differential, and
this defect is on the shared half. A row here needs an absolute expectation.

## Why this was not packed into 6.6.5 bite 3

Not "a different subsystem" and not "P2" — neither is a reason. The reason is that the fix is a
change to the **value-form SIMD calling convention past the integer register ceiling**, which is
a different convention on each of the four targets the release gate runs (SysV XMM + stack,
Win64 by-pointer-in-an-int-reg, aarch64 V-regs + x0..x7, cx), and the failure mode of getting it
wrong is another silent wrong value. It needs its own bisect (caller vs callee), its own
absolute-expectation gate per target, and a real-hardware run on ecb/ach/cass/pi — a full gate
cycle, in a review round of a repair release whose compiler changes are otherwise proven
output-neutral across 317 `.tcyr` and 117 program binaries. Packing it here would have put an
unverified ABI change inside a release that is currently byte-clean.

## Acceptance criteria

1. The repro above prints `12345`, `123456`, `1234567`.
2. The SIMD-arg-last shape `f7(0,1,2,v,3,4,5,6)` returns `9123456`.
3. Both hold for `f32v4`, `f64v4` (2 XMM slots) and a 128-bit integer vector, and for 2 SIMD
   args plus 6+ int args.
4. A new `tests/tcyr/crossos/` test — crossos because the convention differs per target — with
   **absolute** expectations computed from the literals, not a method-vs-free-fn differential
   (see above). Green on real ecb / ach / cass / pi.
5. A mutation-proven shell gate that reddens if the caller's int-arg counter and the callee's
   homing condition drift apart again.
6. `build/cycc` self-host fixpoint + seed-derive GREEN; the 317-file `.tcyr` corpus reported
   with its byte-difference count (this one WILL move bytes — say how many and why).

## Related

* `feedback_dont_encode_codegen_bugs_as_language_rules` — the arity note in `CLAUDE.md` used to
  tell users to restructure their code around a codegen bug. This is the same family: if a
  consumer files "my SIMD helper reads 0 for its 6th argument", it is the compiler.
* v6.4.64 (`project_v6464_win64_stack_args_p0`) — the Win64 half of exactly this shape:
  `ECALLPOPS`' PE branch had no path past `nextra == 5` and corrupted argument 1 at 10+ args.
  The SysV side was assumed fine then; it is not, once a SIMD param is in the mix.
* `vidya` `one_call_syntax_is_not_one_call_path_enumerate_the_masks` (6.6.5).
