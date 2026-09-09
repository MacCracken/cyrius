# `#derive(accessors)` getter as an `f64v_*` argument leaves the intrinsic's DESTINATION slot unwritten — wrong code

**Status:** ✅ **FIXED in v6.6.2** — see CHANGELOG [6.6.2].

> ⛔ **THE FILING WAS RIGHT ABOUT THE SYMPTOM AND WRONG ABOUT THE SCOPE, IN THREE WAYS.**
> Recorded here rather than silently corrected, because each error would have shaped a narrower fix:
>
> 1. **Not derive-specific.** All **21** `f64v_*`/`f32v_*`/`f32v8_*`/`f64v256_*`/`iv_*` handlers in
>    `parse_expr.cyr` share the defect: `var vbase = GFLC(S);` with no `GFLC` bump until every
>    argument is parsed, so ANY argument that allocates a frame local binds it to the intrinsic's
>    own destination slot. `#derive` is one admission route; `#inline` (6.5.63) and `callptr`
>    (6.0.70) are others. The fix is one `_SIMD_RESERVE` helper shared by all 21.
> 2. **Not a 6.5.71 regression.** The filing's own speculation was correct and understated:
>    6.5.71 only stopped *hiding* it. Before that the getter was a real CALL, and the call
>    incidentally forced the spill the expansion had been depending on. Reachable since **6.0.70**.
> 3. **The SIGSEGV is the lucky half.** Under `CYRIUS_REGALLOC_PICKER_CAP=0` the same program
>    exits **0** and writes the result into the *argument object* — silent wrong code. The filing
>    reported only the crash. Both are now pinned.
>
> ⭐ **AND A SEPARATE DEFECT WAS FOUND WHILE WRITING THE TEST:** a SIMD intrinsic in **top-level**
> position compiled clean and SIGSEGV'd on every release checked, for *any* argument shape —
> these stash operands in FRAME slots and top-level code has no frame. `bitset`/`bitclr` already
> refuse this way; the SIMD band never got the guard. Now a named error.
>
> Pinned by `tests/gates/codegen/simd_intrinsic_operand_slots.sh` (5 axes; **axis 1 counts STORES**,
> because a value assertion cannot see a spill that was skipped) and
> `tests/tcyr/crossos/simd_intrinsic_inline_arg.tcyr` (so it executes on ecb/ach/cass/pi).
> Mutation-proven: against unfixed 6.6.1 the gate reports **0 stores**.
> ⚠ The fixpoint and seed-derive are blind — cycc has zero call sites of these intrinsics.
>
> **Downstream:** hisab's load-bearing hoist in `src/mat4.cyr` can be removed once 6.6.2 is
> vendored, and the 13 repos carrying `lib/hisab.cyr:975` re-vendor. Do NOT file 13 downstream
> issues — the compiler was the defect.

**Placement:** unpinned — 6.6.x line. Wrong-code, so it wants a point release rather than a backlog slot.
**Discovered:** 2026-09-09 during hisab's 6.5.33 → 6.6.1 toolchain bump (hisab v2.11.3).
**Severity:** **Critical** — silent wrong code. A 128-bit packed store is issued through an uninitialised stack slot.
**Affects:** cycc **6.5.71 → 6.6.1** (bisected). **6.5.70 and earlier are clean.**
**Filed by:** hisab (higher-mathematics library), which uses the packed intrinsics on every vec/quat/mat type.

## Summary

When a `#derive(accessors)` getter is passed **directly as an argument** to one of the global
`f64v_*` packed-double intrinsics, the intrinsic's inline expansion reads its **destination
pointer** from a frame slot that **no instruction in the function ever writes**. The `src` and
`scalar` operands are spilled correctly; only the destination is missed. The loop then issues
`movupd %xmm0,(%rdx,%rsi,8)` through whatever garbage that slot held.

It usually SIGSEGVs, which is the lucky case. Where the stale slot happens to hold a mapped
address it is a **silent out-of-bounds write** instead.

hisab's `m4_mul_vec4` died on every call; three of its five test suites terminated with rc=139
before reaching a verdict. The bump was blocked outright until it was worked around.

## Reproduction

`docs/development/issues/repros/2026-09-09-derive-accessor-simd-dst-slot.cyr` — self-validating,
four variants of one shape in a single file so context and register pressure are controlled:

```
stdlib = ["syscalls", "alloc", "io", "fmt", "string", "str", "ganita", "math"]
cyrius build repros/2026-09-09-derive-accessor-simd-dst-slot.cyr /tmp/r && /tmp/r
```

| variant | scalar argument | 6.5.70 | 6.6.1 |
|---|---|---|---|
| W1 | plain `fn` accessor (a real `call`) | ok | ok |
| W2 | raw `load64(v + 0)` | ok | ok |
| W4 | derived getter **hoisted into a local** | ok | ok |
| W3 | **derived getter passed directly** | ok | **SIGSEGV** |

Measured: exit **0** on 6.5.70, exit **139** on 6.6.1, same file.

⚠ **W2 is the important control.** A raw `load64` is inlined too and compiles correctly, so this is
**not** "inlining in general" — it is specific to the derive inline-replay path.

## Root cause (speculation — flagged as such; the frontend is yours)

Disassembly of hisab's `m4_mul_vec4`, cycc 6.6.1, `CYRIUS_DCE=1`:

```
405373:  mov  %rax,%rbx             ; rbx = r  (dst, from alloc)
405382:  mov  %rax,%r12             ; r12 = tmp
405388:  mov  %rax,%r13             ; r13 = r  -- dst kept in a REGISTER, never spilled
405399:  mov  %rax,-0x58(%rbp)      ; src    spilled   OK
4053b9:  mov  %rax,-0x60(%rbp)      ; scalar spilled   OK
         ; loop:
4053e4:  mov  -0x58(%rbp),%rdx      ; src    read back OK
4053eb:  movupd (%rdx,%rsi,8),%xmm0
4053f0:  mulpd  %xmm2,%xmm0
4053f4:  mov  -0x50(%rbp),%rdx      ; dst    <-- SLOT NEVER WRITTEN
4053fb:  movupd %xmm0,(%rdx,%rsi,8) ; faults, %rdx = 1
```

`-0x50(%rbp)` is **read exactly once and written zero times** in the entire function. The garbage
varies with build settings — `%rdx = 12` plain, `%rdx = 1` under `CYRIUS_DCE=1`.

**Why 6.5.71.** That release's headline is *"`#derive(accessors)` getters/setters now reach the
inline-replay path"*, measured there as `callq` **7 → 3**. Before it, the getter was a real call,
and the call incidentally forced the surrounding live values — including the intrinsic's
destination — to be spilled. Removing the call removed the spill that the `f64v_*` expansion had
been silently depending on.

**So the intrinsic-expansion bug is almost certainly older than 6.5.71; that release only stopped
hiding it.** The suspect is the argument-lowering in the `f64v_*` expansion assuming its operand
slots are always materialised, rather than anything wrong in the derive work itself.

## Proposed fix

Make the `f64v_*` expansion materialise **all** its pointer operands into their frame slots
unconditionally, or teach it to read the destination from the register the allocator actually
chose. The asymmetry — `src` and `scalar` spilled, `dst` not — is the whole bug.

⭐ Worth a gate that **counts the stores** into an intrinsic's operand slots rather than asserting
the computed values, for the same reason 6.5.71's own `derive_accessors_inlined.sh` counts `callq`:
a result assertion cannot see a spill that was skipped, only one that produced a wrong number, and
here the wrong number is usually a segfault instead.

## Consumer-side workaround

Hoist the getter into a local before the call — variant W4 above:

```cyrius
var vx = V4_x(v);
f64v_scale(r, m + 0, vx, 4);   # instead of f64v_scale(r, m + 0, V4_x(v), 4);
```

Shipped in hisab v2.11.3 (`src/mat4.cyr`, `m4_mul_vec4`), with a comment marking the hoist
load-bearing so it is not tidied away. Mutation-proven: reverting the hoist returns three suites to
rc=139; restoring it returns 3532/3532 assertions green.

**Recommended minimum for the fix to deploy:** whatever 6.6.x point release carries it — consumers
on 6.5.71–6.6.1 have no safe version in that range other than the source-level hoist.
