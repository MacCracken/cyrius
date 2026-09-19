# `var p: S = f(..., v, ...)` pushes a value-form vector argument as an INT — wrong values on SysV/aarch64, a page fault on Win64, at any arity — ✅ FIXED in 6.6.6 (bite 14)

**Status:** ✅ **FIXED in 6.6.6 (bite 14)** — both struct-valued receive loops now marshal every
argument through `_call_arg_one` / `_owncall_args` (`src/frontend/parse_fn.cyr`), the same
per-argument gates the method-call loop runs (which now calls the same helper). Found during 6.6.6
bite 1's review; re-measured on HEAD `bbc880a9` before the fix: `149` / `53`, exactly as filed.
**Placement:** the next 6.6.x repair release. Not parked to 7.x (nothing codegen is).
**Discovered:** 2026-09-19.
**Severity:** High — silent wrong values on x86_64 and aarch64 (exit 0, no diagnostic), a crash on
Win64. Ordinary source: a struct-returning fn with a SIMD parameter, bound with `var p: S = ...`.
**Affects:** cycc 6.6.5 and 6.6.6-in-flight. Measured: x86_64 Linux (native), aarch64 (qemu-user,
NOT hardware), Win64 (wine, NOT hardware). cx unmeasured (it refuses the pair-return ABI).

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/simd.cyr"
struct P2 { x; y; }
struct P3 { x; y; z; }
fn mkv(a, v: f64v2, b): P3 { var p: P3; p.x = a; p.y = load64(&v + 8); p.z = b; return p; }
fn pr2(a, v: f64v2): P2 { var p: P2; p.x = a; p.y = load64(&v); return p; }
fn main(): i64 {
    alloc_init();
    var v = f64v2_make(9, 8);
    var w = f64v2_make(3, 4);
    var q: P3 = mkv(1, v, 2);
    print_num(q.x); print_num(q.y); print_num(q.z); println("");
    var p: P2 = pr2(5, v);
    print_num(p.x); print_num(p.y); println("");
    return 0;
}
var ec = main();
syscall(60, ec);
```

`cat r.cyr | ./build/cycc > r && ./r` — want `182` / `59`:

| target | `mkv(1, v, 2)` (>16 B, `asv`) | `pr2(5, v)` (9-16 B, `asv_pair`) |
|---|---|---|
| x86_64 Linux | `149` — `v` read from a stale XMM0 (`w`), `b` reads the vector's value 9 | `53` — `v` read from a stale XMM0 (`w`'s 3) |
| aarch64 (qemu) | `149` | `53` |
| Win64 (wine) | page fault `read access to 0x9` at `movupd (%rax), %xmm5` (`rax = 9`) — the vector's first word is dereferenced as the by-pointer vector argument | — (not reached) |

⚠ **Without the `var w = f64v2_make(3, 4);` line, `pr2` prints the right answer** — XMM0 still holds
`v` by accident. That is how a hand-written arity-2 check passes over this; a gate must clobber the
vector registers first. The plain call, method call and `return`-position paths route a vector
correctly — 6.6.6 bite 1's `tests/tcyr/crossos/simd_param_int_stack_args.tcyr` covers them; only
the `var p: S = f(...)` binding is wrong.

## Root cause

`src/frontend/parse_decl.cyr`, `PARSE_VAR`'s two struct-valued-assign call loops: the `asv` loop
(`asv_argc`, ~2848-2873: retptr, then every argument `PCMPE` + `EPUSHR`, `ECALLPOPS(S, asv_argc)`)
and the `asv_pair` loop (`asp_argc`, ~2941-2958, the same with no retptr). Neither consults the
callee's SIMD parameter mask, so a value-form vector is evaluated as an int expression and pushed as
an int argument: SysV/aarch64 get one extra int arg (shifting every later int) and nothing in XMM/V;
Win64 gets the vector's first word where it expects a pointer to it. The plain call path
(`_fc_int_argc` / `_fc_simd_count`) and the method path (6.6.5 bite 3, `m_int_argc`) already do this
routing — these two loops are the call syntaxes that were never given it (vidya
`one_call_syntax_is_not_one_call_path_enumerate_the_masks`).

## Proposed fix

Give both loops the plain call path's SIMD routing — ideally by sharing its marshalling helper
rather than a third copy, since the method path was fixed the same way one release ago and the
two copies are how this one was missed. The retptr must stay int arg 0 on x86 (and X8 on aarch64)
while vectors go to XMM/V (SysV/aarch64) or by pointer in their int slot (Win64).

## Acceptance criteria

1. The repro prints `182` / `59` on x86_64, aarch64 and Win64.
2. A `tests/tcyr/crossos/` test with literal expectations, vector registers clobbered before each
   call: `asv` and `asv_pair` callees with f64v2 / f32v4 / f64v4 params, vector first / middle /
   last, 2 and 7+ int params (x86's retptr is int arg 0, so 6+ user ints reach the stack) — green
   on real ecb / ach / cass / pi.
3. A gate that reddens if either loop stops routing vectors (mutation-proven), x86 + aarch64 (qemu)
   + Win64 (wine).
4. `build/cycc` fixpoint + seed-derive GREEN; the `.tcyr` corpus byte-difference count reported.

## Corrections to this filing

- **It was not only the SIMD mask.** "Neither consults the callee's SIMD parameter mask" undercounts:
  both loops were a bare `PCMPE + EPUSHR` and consulted NONE of PARSE_FNCALL's callee gates.
  Measured on the pre-fix compiler through the same `var p: S = f(...)` receive: a string literal
  into a `: Str` param was never wrapped (`var a: P3 = fs("abcde", 2)` read `str_len` of a raw
  cstr — garbage), a struct local into a by-value struct param was pushed BY VALUE (SIGSEGV), an
  integer literal into a `: cstring` param was not refused, and a wrong argument count compiled
  clean (`var q: P3 = f3(1)` for a 2-param `f3`). The Win64 page fault in the table is the
  struct-address gate's absence, not the SIMD mask's (PE vectors travel by pointer, and PE's
  simd mask is 0). All five come from one root — the loop never asked the callee — and are fixed
  by the one shared helper.
- **Placement of the fix.** The filing proposed sharing "the plain call path's" marshalling; the
  helper shared is the method-call loop's (6.6.5 bite 3), because PARSE_FNCALL's loop carries
  extra warning-only checks between the gates. The method loop now calls the same helper.
- **"One copy between them" was not true when first committed** (bite 14's review). Four more
  own-call loops — the Win64-only vector-retptr calls: `var v: f64v2 = f(..)`, `v = f(..)`,
  `var w: f64v4 = f(..)` and `return f(..)` in a vector fn — kept a private loop with the gates but
  NO arity check, so a wrong argument count built clean on PE alone (x86 and aarch64 refused the
  same source). They now call `_owncall_args` too; PE output is byte-identical across the corpus,
  and `stack_param_homing_matrix.sh`'s refusal section pins it on every compiler.

