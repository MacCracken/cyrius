# An enum variant constructor with 7+ fields reads its stack-passed fields from the wrong place — wrong value on x86 SysV, SIGILL on aarch64 — ✅ FIXED in 6.6.6 (bite 14)

**Status:** ✅ **FIXED in 6.6.6 (bite 14)** — the constructor prologue now passes `ctor_arity` as the
caller's int-class total (`src/frontend/parse_types.cyr`). Found during 6.6.6 bite 1's review;
re-measured on HEAD `bbc880a9` before the fix: `1234565` / `12345656` on x86_64, exactly as filed.
**Placement:** the next 6.6.x repair release. Not parked to 7.x (nothing codegen is).
**Discovered:** 2026-09-19.
**Severity:** High — silent on x86 (exit 0, no diagnostic, a field holds another field's value);
a crash on aarch64. Ordinary source: any `enum` variant with seven or more fields.
**Affects:** cycc 6.6.5 and 6.6.6-in-flight. Measured: x86_64 Linux (native) wrong; aarch64
(qemu-user, NOT hardware) SIGILL; Win64 (wine, NOT hardware) correct. cx and Mach-O unmeasured.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
enum E7 { V7(a, b, c, d, e, f, g); }
enum E8 { V8(a, b, c, d, e, f, g, h); }
fn main(): i64 {
    alloc_init();
    var e7 = V7(1, 2, 3, 4, 5, 6, 7);
    var i = 0;
    while (i < 7) { print_num(load64(e7 + 8 + i*8)); i = i + 1; }
    println("");
    var e8 = V8(1, 2, 3, 4, 5, 6, 7, 8);
    i = 0;
    while (i < 8) { print_num(load64(e8 + 8 + i*8)); i = i + 1; }
    println("");
    return 0;
}
var ec = main();
syscall(60, ec);
```

`cat r.cyr | ./build/cycc > r && ./r`:

| target | want | got |
|---|---|---|
| x86_64 Linux | `1234567` / `12345678` | `1234565` / `12345656` — `g` reads `e`, `h` reads `f` |
| aarch64 (qemu-user) | same | `uncaught target signal 4 (Illegal instruction)` |
| Win64 (wine) | same | `1234567` / `12345678` ✅ |

Six or fewer fields are correct everywhere (all in registers).

## Root cause

`src/frontend/parse_types.cyr:465`, the constructor prologue:

```cyr
ESTOREPARM(S, ctor_pi, ctor_pi, 0);
```

The last argument is the caller's int-class TOTAL, which SysV and aarch64 `ESTORESTACKPARM`
count stack slots DOWN from (`si = (pc - 6) - 1 - (pidx - 6)`). With 0, `si` goes negative: on
x86 `sdisp = 16 + si*8` becomes `[rbp-40]`, `[rbp-48]` — the constructor's OWN frame slots 4 and 5,
i.e. fields `e` and `f`, exactly the measured values. On aarch64 the negative offset is OR-ed into
an `ldr x9, [x29, #imm12]` encoding and corrupts the opcode — SIGILL. Win64's formula
(`16 + 32 + (pidx - 4) * 8`) does not use the total, which is why it is correct.

It is the same class as 6.6.6 bite 1 (a stack-param homing site handed a wrong total) and the v6.5.46
closure fix, whose comment already calls `pc = 0` here "garbage" — but a different site and a
different wrong value, so bite 1 did not touch it.

## Proposed fix

Constructor params are all int-class, one slot each, with no retptr (a heap variant returns a
pointer in `rax`, a stack variant `rax:rdx`), so the total is `ctor_arity`: `ESTOREPARM(S, ctor_pi, ctor_pi, ctor_arity)`. Then grep
every other `ESTOREPARM` caller for a total that is not the caller's int-class count (the async
constructor at `parse_fn.cyr` `ESTOREPARM(S, i, i, pc)` is the other `pc`-shaped one — correct only
while every param is int-class; see
`2026-09-19-async-fn-simd-param-not-captured.md`).

## Acceptance criteria

1. The repro prints `1234567` / `12345678` on x86_64, aarch64 and Win64.
2. A `tests/tcyr/crossos/` test with literal expectations: variants of 6, 7, 8 and 10 fields,
   every field read back — green on real ecb / ach / cass / pi.
3. A gate that reddens on the pre-fix `0` (mutation-proven), x86 + aarch64 (qemu) + Win64 (wine).
4. `build/cycc` fixpoint + seed-derive GREEN; the `.tcyr` corpus byte-difference count reported.

## Corrections to this filing

None to the diagnosis — the root cause, the measured values and the one-word fix were all right.
The follow-up grep it asked for, done: every other `ESTOREPARM` caller passes a correct total.
The closure prologue's in-loop `ESTOREPARM(S, clpc, cpli, 0)` is register-only (`clpc < 6`; on
Win64 its `pidx` 4-5 go through the total-free shadow formula) and its deferred pass uses `clpc`
(closure params are untyped int-class, one slot each, no retptr); the env param passes
`clpc + 1`. The async constructor's `ESTOREPARM(S, i, i, pc)` is right only while every async
parameter is int-class — bite 14d makes that an enforced invariant (a value-form vector
parameter on an `async fn` is refused).

