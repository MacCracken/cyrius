# cyrius-x bytecode correctness — direct-emit inventory (v5.7.12)

> **ARCHIVED — RESOLVED.** All 10 direct-x86-emit sites were guarded with
> `_TARGET_CX` checks and a CYX round-trip gate was added to check.sh
> (CHANGELOG [5.7.12]). Archived 2026-06-09 (v6.1.18 doc sweep).

Date: 2026-04-27
Cyrius version at audit: 5.7.11 (in-flight v5.7.12 work)
Source of truth: `src/frontend/parse_*.cyr` after the v5.7.11
cx-drift fix landed.

## Why this audit

v5.7.11 fixed `main_cx.cyr`'s parse-time / build-time / startup
breakage. Bytecode SEMANTIC correctness was explicitly cascaded
to v5.7.12: cc5_cx today produces a `CYX\0` magic header + valid
CYX opcodes interleaved with raw x86 instruction bytes. The x86
noise comes from `parse_*.cyr` calling `EB(S, 0xNN)` /
`E2(S, 0xNNNN)` / `E3(S, 0xNNNNNN)` directly with x86 hex
literals in unconditional shared codepaths — bypassing each
backend's named-op abstraction layer.

This doc inventories every direct-emit site, classifies it, and
proposes the v5.7.12 fix shape.

## Method

```sh
grep -nE "EB\(S, 0x[0-9A-Fa-f]+\)" src/frontend/parse_*.cyr | wc -l
grep -nE "E[2348W]\(S, 0x[0-9A-Fa-f]+\)" src/frontend/parse_*.cyr | wc -l
```

Each hit walked + classified by enclosing context.

## Raw counts (v5.7.11)

| Primitive | parse_ctrl | parse_decl | parse_types | parse_fn | parse_expr | total |
|-----------|-----------:|-----------:|------------:|---------:|-----------:|------:|
| `EB(S, 0x..)`  | 0 | 9  | 0 | 16 | 16  | 41 |
| `E2(S, 0x..)`  | 0 | 0  | 0 | 0  | 2   | 2  |
| `E3(S, 0x..)`  | 0 | 0  | 0 | 10 | 1   | 11 |
| `EW(S, 0x..)`  | 0 | 0  | 0 | 0  | 13  | 13 |
| `E8(S, 0x..)`  | 0 | 0  | 0 | 0  | 0   | 0  |
| **TOTAL hits** | **0** | **9** | **0** | **26** | **32** | **67** |

67 raw sites. After deduplication into logical-emit blocks (a
`# mov [rbp-8], rbx` is one logical mov even when split across
`E3(...) EB(...)`): **~10 distinct sites** across the codebase.

## Classification

### A. Already arch-conditional (no fix needed — leave alone)

Sites inside `if (_AARCH64_BACKEND == 1)` or analogous that
only emit on aarch64 builds. cx has `_AARCH64_BACKEND = 0`
(set in v5.7.11), so these branches don't execute on cx.

| Site | Lines | Op | Enclosing condition | cx exec? |
|------|------:|----|---------------------|---------:|
| `parse_expr.cyr` aarch64 PIC fn-addr | 309-311 | `EW × 3` | `if (_AARCH64_BACKEND == 1)` | ❌ skip ✓ |
| `parse_expr.cyr` aarch64 `&local`    | 339-355 | `EW × 1-3` (depending on disp) | `if (_AARCH64_BACKEND == 1)` | ❌ skip ✓ |
| `parse_expr.cyr` aarch64 PIC gvar    | 788-790 | `EW × 3` | `if (_AARCH64_BACKEND == 1)` | ❌ skip ✓ |
| `parse_expr.cyr` aarch64 f64 cmp     | 835-841 | `EW × 5-6` | `if (_AARCH64_BACKEND == 1)` | ❌ skip ✓ |

### B. x86-conditional via `_AARCH64_BACKEND == 0` and `_IS_OBJ`-shaped — but cx falls through to the x86 arm

Sites where the parser picks `aarch64 / x86 / object-mode` —
the aarch64 arm uses arch-conditional, but the x86 arm
unconditionally executes for "anything not aarch64", which
includes cx. cx ends up emitting x86 bytes into bytecode.

This is the **primary problem class**. Fix shape: add a `cx`
arm or `_TARGET_CX == 0` guard around the x86-emit arm.

| Site | Lines | Op | What it emits | cx behavior today |
|------|------:|----|---------------|-------------------|
| `parse_expr.cyr` PIC fn-addr (`_IS_OBJ` arm) | 313-316 | `EB × 3` + `EDISP32` | `lea rax, [rip+rel32]` | _IS_OBJ→0 on cx, **falls to else** |
| `parse_expr.cyr` PIC fn-addr (else / direct exec) | 318-321 | `E2(0xB848)` + `E8(0)` | `mov rax, imm64` (x86 movabs) | **emits x86 movabs into bytecode** |
| `parse_expr.cyr` `&local` x86 arm | 354-358 | `E3(0x858D48)` | `lea rax, [rbp+disp32]` | **emits x86 LEA into bytecode** |
| `parse_expr.cyr` PIC gvar (`_IS_OBJ`) | 793-796 | `EB × 3` + `EDISP32` | same shape as fn-addr | **falls to else (movabs)** |
| `parse_expr.cyr` PIC gvar (else) | 798-800 | `E2(0xB848)` + `E8(0)` | `mov rax, imm64` | **emits x86 movabs** |
| `parse_expr.cyr` f64 cmp x86 SETcc chain | 845-854 | `EB × 13-14` | `mov rcx, rax; mov rax, 0; setXX al; movzx rax, al` | **emits x86 chain** |

### C. x86-only operations that error on aarch64 — cx falls through unguarded

Sites that explicitly error on aarch64 (`ERR_MSG`) and then
emit x86 bytes. cx hits the same fall-through but no error
fires (cx is not aarch64).

| Site | Lines | Op | Today's aarch64 guard | cx behavior |
|------|------:|----|----------------------|-------------|
| `parse_fn.cyr` struct-return `rep movsb` | 280-321 | `EB × 16` | `if (_AARCH64_BACKEND == 1) { ERR_MSG }` | falls through, **emits x86 rep movsb** |
| `parse_expr.cyr` f64_atan (x87) | 950 | `EB × 4` | `ERR_MSG` for aarch64 | falls through, **emits x87 fpatan** |
| `parse_expr.cyr` f64 unary (x87/SSE) | 1094, 1106-1116 | `EB × 6-22` per ptyp | not arch-guarded — uses cx-stub `EX87PUSH/POP` etc. | **emits x87/SSE bytes** |

### D. Unconditional x86 emits in shared code (no arch guard at all)

Worst class — runs on every backend. cx today emits these x86
bytes into bytecode.

| Site | Lines | Op | What it emits | Impact |
|------|------:|----|---------------|--------|
| `parse_expr.cyr` arg cleanup | 495-496 | `EB(0x48); EB(0x83); EB(0xC4); EB(0x08);` | `add rsp, 8` (x86) | every fn call returning struct-by-value |
| `parse_decl.cyr` struct field load | 176-178 | `EB × 3-4` per `fld_sz` | `movzx rax, byte/word/dword [rcx]` | every struct field read of size <8 |
| `parse_fn.cyr` regalloc save | 787-791 | `E3 + EB × 5` | `mov [rbp-N], rbx/r12-r15` | every fn with `_cur_fn_regalloc > 0` |
| `parse_fn.cyr` regalloc restore | 977-981 | `E3 + EB × 5` | `mov rbx/r12-r15, [rbp-N]` | every fn with `_cur_fn_regalloc > 0` |

The regalloc save/restore is the highest-volume offender —
v5.6.24 made regalloc default-on for x86, and on cc5_cx every
generated fn fires these emits. That's why the cc5_cx output
earlier showed `4889 5df8 4c89 65f0 ...` (callee-save chains)
inside the bytecode stream.

## Proposed fix (path B — `_TARGET_CX == 0` guards)

Path A (replace direct emits with abstract named ops in each
backend) was considered. Rejected for v5.7.12 because:
- 10 logical sites × 3 backends × design-each-op = real
  multi-week refactor.
- Changes the x86 emit interface (every direct emit becomes a
  named call) — must be accompanied by exhaustive byte-identity
  testing on every emit site to prove no regression.
- Path A is the right LONG-TERM architecture; v5.7.12 fixes the
  bytecode noise without committing to that scope.

Path B per-site guard pattern:

```cyr
if (_TARGET_CX == 0) {
    EB(S, 0x48); EB(S, 0x8D); EB(S, 0x05);  // x86 LEA
    ...
}
```

For sites in class D (unconditional x86), add `_TARGET_CX`
to the guard. For sites in class C (already error on
aarch64), broaden the error to also cover cx OR add a no-op
fallthrough for cx that emits a CYX-equivalent op (e.g., a
no-op halt for unsupported f64 ops).

For sites in class B (x86 vs aarch64 split), add a third
arm:

```cyr
if (_AARCH64_BACKEND == 1) {
    EW(...);
} else {
    if (_TARGET_CX == 1) {
        // CYX bytecode emit (or no-op for unsupported)
    } else {
        EB(S, 0x48); ...  // x86 emit
    }
}
```

Class A sites need no change.

## Per-site fix matrix

| # | File | Line | Class | Action |
|---|------|-----:|-------|--------|
| 1 | parse_decl.cyr | 176-178 | D | `if (_TARGET_CX == 0) { ... }` wrapper around 3 fld_sz arms |
| 2 | parse_expr.cyr | 313-321 | B | Add `_TARGET_CX == 1` arm: emit CYX `LOAD_FN_ADDR` opcode + fixup; else x86 |
| 3 | parse_expr.cyr | 354-358 | B | Add `_TARGET_CX == 1` arm: CYX `LOAD_LOCAL_ADDR` |
| 4 | parse_expr.cyr | 495-496 | D | `if (_TARGET_CX == 0)` wrapper (cx has no rsp, no-op) |
| 5 | parse_expr.cyr | 793-800 | B | Same as #2 — gvar PIC variant |
| 6 | parse_expr.cyr | 845-854 | B | Add `_TARGET_CX == 1` arm: CYX f64 cmp (or no-op fallback) |
| 7 | parse_expr.cyr | 950, 1094-1116 | C | Broaden aarch64 error to also reject cx, OR cx no-op fallthrough |
| 8 | parse_fn.cyr | 280-321 | C | Broaden struct-return error to reject cx |
| 9 | parse_fn.cyr | 787-791 | D | `if (_TARGET_CX == 0)` wrapper around 5 save lines |
| 10 | parse_fn.cyr | 977-981 | D | `if (_TARGET_CX == 0)` wrapper around 5 restore lines |

10 logical fix sites. Each is a 3-5 line diff. Total v5.7.12
patch surface: ~50 LOC added (mostly guard lines), ~0 LOC
deleted.

## What v5.7.12 is NOT

- **Not** path A. Named-op refactor stays a long-term
  consideration; pin if a 4th backend (RISC-V) makes the
  guard pattern unwieldy.
- **Not** semantic-complete CYX op coverage. f64 ops, struct
  return-by-value, regalloc — all "unsupported on cx today,
  emit nothing or fail" for v5.7.12. Bytecode-grade f64 is its
  own slot (cxvm needs the ops added too).

## What v5.7.12 IS (acceptance gates)

1. cc5_cx output is **valid CYX bytecode end-to-end** —
   no x86 instruction bytes in the stream.
2. `tests/regression-cx-roundtrip.sh`:
   - `echo 'syscall(60, 42);' | cc5_cx | cxvm` → exit 42.
   - `echo 'fn add(a, b) { return a + b; } syscall(60, add(13, 29));' | cc5_cx | cxvm` → exit 42.
   - Conditional, while loop, string write — exits 0.
3. `tests/regression-cx-build.sh` (v5.7.11 gate) still passes.
4. x86 fixpoint clean (path B doesn't change emitted x86
   bytes).
5. `scripts/check.sh` — gate count adds 4v (cx roundtrip).

## Drift-prevention follow-up (for v5.7.13 or later)

Per the v5.7.11 lesson: drift accumulated because no gate
built cx. Even with v5.7.11's build gate + v5.7.12's roundtrip
gate, future direct-x86 additions in `parse_*.cyr` could still
slip in unguarded.

Pin a static-analysis gate: scan `parse_*.cyr` for
`E[B238W]\(S, 0x[0-9A-Fa-f]+\)` and warn unless inside a
recognized arch-conditional or `_TARGET_CX == 0` guard.
Heuristic-based but cheap to run; surfaces new direct emits
at PR review.

## Conclusion

v5.7.12 is **path B (≈10 sites × 3-5 LOC each = ~50 LOC)** plus
the cxvm regression test + the check.sh gate. Real engineering,
NOT a wedge — but bounded enough to land in one slot if the
shape holds. Worst-case escalation: cx CYX opcodes for sites #2,
#3, #5, #6 require coordination with cxvm's interpreter side,
which adds scope.

Decision point: when starting v5.7.12, confirm path B and
pick which sites get a "cx no-op" vs "cx CYX op emit". The
no-op approach lets cc5_cx → cxvm work for the simple programs
in the acceptance gate; full CYX op coverage (f64, struct
return) is bonus.
