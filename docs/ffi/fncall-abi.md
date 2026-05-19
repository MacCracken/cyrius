# `fncallN` — calling convention reference

Cyrius exposes `fncall0` through `fncall8` in `lib/fnptr.cyr` for
calling function pointers. This doc is the canonical reference for
when you can call a function directly via `fncallN` and when you
must route through a C shim.

**Landed:** v5.4.13 (ceiling lifted from 6 to 8; see
`../development/roadmap.md §v5.4.13`).

---

## Calling convention

Cyrius uses a single calling convention across both arches:

| Arch    | Args 1–6                    | Args 7+              | Return | Indirect-call reg |
|---------|-----------------------------|----------------------|--------|-------------------|
| x86_64  | `rdi, rsi, rdx, rcx, r8, r9`| `[rsp+0], [rsp+8], …` | `rax`  | `rax`             |
| aarch64 | `x0, x1, x2, x3, x4, x5`    | `[sp+0], [sp+16], …` | `x0`   | `x9`              |

On aarch64 cyrius uses only **6** argument registers (not AAPCS64's
8) to stay symmetric with x86_64 SysV. Stack args on aarch64 occupy
**16 bytes each** (8 data + 8 padding) to preserve the 16-byte SP
alignment AAPCS64 and AArch64 SPAlignmentCheck require.

Cyrius pads the local frame to a 16-byte boundary
(`src/cc/parse.cyr:1505`: `fsz = (flc*8 + 15) & ~15`), so RSP / SP
is 16-byte aligned in every function body. `fncall7` / `fncall8`'s
x86 variants reserve 16 bytes via `sub rsp, 16` to hold the stack
arg(s) plus padding; aarch64 pushes each stack arg with
`str xN, [sp, #-16]!`.

---

## When direct `fncallN` is safe

All of:

1. **N ≤ 8** (0 → 8 supported as of v5.4.13).
2. **Every argument is a scalar** — integer, pointer, or enum widened
   to `i64`. No struct-by-value parameters.
3. **No `float` / `double` arguments.** SysV passes floats in
   `xmm0..xmm7`; AAPCS64 uses `v0..v7`. `fncallN` touches only
   integer registers.
4. **Not a variadic function.** SysV variadic requires `AL = # of
   SSE regs used`; AAPCS64 variadic uses `x8` as the indirect
   result register. `fncallN` sets neither.
5. **On aarch64: ≤ 6 args when calling C functions.** Args 7–8 go
   to stack under cyrius's convention but into `x6..x7` under
   AAPCS64 — the ABI diverges past arg 6. `fncall7` / `fncall8` are
   **cyrius-to-cyrius safe** but **not AAPCS64-compatible** for the
   last two args. C functions with 7+ args on aarch64 must route
   through a C shim regardless.

If all five hold, direct call is correct:

```cyrius
fn add3(a, b, c) { return a + b + c; }
var r = fncall3(&add3, 1, 2, 3);           // cyrius → cyrius, all scalars
```

```cyrius
// C declared: int64_t some_c_api(int64_t, int64_t);
var r = fncall2(_c_fp, 42, 99);            // cyrius → C, ≤ 6 scalar args on x86 or aarch64
```

---

## When a C shim is required

Any one of:

| Trigger                                        | Why                                                   |
|------------------------------------------------|-------------------------------------------------------|
| Struct-by-value parameter                      | SysV §3.2.3 / AAPCS64 §B.4 aggregate rules split into register pairs or stack-home; `fncallN` loads integer regs only |
| `float` / `double` parameter or return         | Float passing uses xmm / v registers cyrius doesn't touch |
| Variadic callee (e.g. `printf`, `wgpuLog*`)    | SysV needs `AL` set; AAPCS64 needs `x8` set           |
| >6 args calling a C function on aarch64        | Cyrius 6-reg convention ≠ AAPCS64 8-reg convention    |
| Nested pointer chains passed individually      | Tolerable but struct-pack is cleaner + fewer FFI slots |

The canonical shim pattern: accept a packed-args struct by pointer,
unpack in C, call the real function with ABI-correct layout. See
`struct-packing.md` for worked examples.

---

## How to tell in practice

Look at the C signature. If you see:

- `const XXXDescriptor*` or `const XXXInfo*` (pointer to a struct) —
  safe for `fncallN` (the pointer goes in a register).
- `XXXDescriptor` or `XXXInfo` **without `*`** (by-value) — shim required.
- `float`, `double`, `WGPUColor` (which holds doubles) — shim required.
- `...` at the end of the parameter list — variadic, shim required.

wgpu-native is heavy on by-value descriptors, so most wgpu FFI
slots go through shims. Pure-integer APIs like `sigil`'s hash
primitives, `sakshi`'s allocators, and `yukti`'s permission checks
can use `fncallN` directly.

---

## Background — why cyrius diverges from AAPCS64

The six-register limit predates the aarch64 port. When the aarch64
backend landed (v5.3.15), it mirrored the x86_64 code shape rather
than rewriting for AAPCS64's wider register set. The divergence is
intentional: it keeps the caller / callee codegen uniform across
arches (`src/backend/aarch64/emit.cyr:ECALLPOPS`) and means any
`fncallN` consumer writing cyrius-to-cyrius code has identical
behaviour on both arches. The cost is that aarch64 direct C calls
with 7–8 args must shim — a small cost given wgpu-scale APIs shim
anyway for struct-by-value reasons.

If a future release widens cyrius's convention to AAPCS64-proper on
aarch64, that would be a v6.0.0-class ABI break (symmetric to the
`cycc → cyc` rename era) and not a v5.4.x patch.

---

## SysV 16-byte stack alignment for odd-stack-arg callers (v5.6.41)

A separate calling-convention nuance, not specific to `fncallN`
but relevant to anyone reading this file: SysV requires
`%rsp + 8` to be 16-aligned at function entry. For cyrius
functions whose own param list takes more than 6 args, the 7th+
arg goes on the stack — and for **odd** stack-arg counts (7, 9,
11 params), the caller-side push sequence leaves rsp 8-aligned
at the CALL site, which violates the ABI.

Pre-v5.6.41, `ECALLPOPS`'s SysV path emitted `add rsp, 48` to
drop the 6 reg-arg slots regardless of N's parity. For odd
nextra (N - 6), this left rsp at `R - nextra*8` = 8-aligned
(mod 16), and the violation propagated through every CALL
inside the body until something downstream used SSE on a
stack-saved value (most libssl / libc prologs) and SIGSEGV'd
at its first instruction.

**Fix shipped v5.6.41**: for odd nextra, ECALLPOPS shifts the
step-2 writes from `[rsp + (6+i)*8]` to `[rsp + (5+i)*8]` and
uses `add rsp, 40` instead of `add rsp, 48`. This drops one
fewer reg-arg slot, leaves the stack args at the same
`[rbp+16]`-relative offsets in the callee, and lands rsp
16-aligned at the CALL site. `ECALLCLEAN` releases the
corresponding 8 bytes of alignment padding.

Acceptance: `tests/tcyr/sysv_odd_stack_args.tcyr` (5
assertions covering callers with 7/8/9/10/11 params hitting an
SSE-using leaf) was added as the regression gate.
Sandhi-filed: `sandhi/docs/issues/2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md`.

The Win64 path was already correct — it had the symmetric
alignment branch via `if ((framesize & 15) != 0) framesize+=8`
in `ECALLPOPS`.

---

## See also

- `struct-packing.md` — canonical C-shim pattern with worked examples.
- `lib/fnptr.cyr` — header comment summarises this table.
- `tests/tcyr/fncall_ceiling.tcyr` — correctness regression for
  all `fncall0..fncall8` on both arches.
- `tests/tcyr/sysv_odd_stack_args.tcyr` — v5.6.41 SysV
  alignment regression gate.
- mabda's `docs/issues/2026-04-19-fncall6-wgpu-crash-resolution.md`
  — concrete case study of the struct-by-value failure mode.
