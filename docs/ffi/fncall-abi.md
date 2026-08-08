# `fncallN` — calling convention reference

Cyrius exposes `fncall0` through `fncall8` in `lib/fnptr.cyr` for
calling function pointers. This doc is the canonical reference for
when you can call a function directly via `fncallN` and when you
must route through a C shim.

**Landed:** v5.4.13 (ceiling lifted from 6 to 8; see
`../development/roadmap.md §v5.4.13`).

---

## Calling convention

Cyrius uses a per-target calling convention (see the `lib/fnptr.cyr`
header for the authoritative breakdown):

| Target                  | Args                                  | Args overflow         | Return | Indirect-call reg |
|-------------------------|---------------------------------------|-----------------------|--------|-------------------|
| x86_64 SysV (Linux/macOS) | 1–6 in `rdi, rsi, rdx, rcx, r8, r9` | `[rsp+0], [rsp+8], …` | `rax`  | `rax`             |
| x86_64 MS-x64 (Windows PE / UEFI) | 1–4 in `rcx, rdx, r8, r9`, +32 B shadow space | `[rsp+0x20+(N-5)*8]` | `rax`  | `rax`             |
| aarch64 (cyrius subset of AAPCS64) | 1–6 in `x0, x1, x2, x3, x4, x5`   | `[sp+0], [sp+16], …` | `x0`   | `x9`              |

On aarch64 cyrius uses only **6** argument registers (not AAPCS64's
8) to stay symmetric with x86_64 SysV. Stack args on aarch64 occupy
**16 bytes each** (8 data + 8 padding) to preserve the 16-byte SP
alignment AAPCS64 and AArch64 SPAlignmentCheck require.

Cyrius pads the local frame to a 16-byte boundary
(`src/frontend/parse.cyr`: `fsz = (flc*8 + 15) & ~15`), so RSP / SP
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
`cyrc → cybs` / `cc5 → cycc` rename era) and not a v5.4.x patch.

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

## Extern-C prerequisite: a glibc-compatible `%fs` (v6.3.26)

**There is no `fncall6` calling-convention bug.** The v6.3.26 slot was
scheduled as one ("Class B FFI / `fncall6` ABI fix"); investigation proved
the arg-passing (`rdi,rsi,rdx,rcx,r8,r9`) and 16-byte stack alignment are
correct — a real gcc-compiled, stack-protected C function taking 4/5/6/7
integer args returns the right result when called via `fncallN`.

The folklore that **"`fncall6` into extern-C (wgpu) is unreliable"** — carried
in mabda's `wgpu_ffi.cyr` / `compute.cyr` / `texture.cyr` comments, which
work around it by packing args into a struct and calling `fncall2` instead —
was a **misdiagnosis of a TLS/`%fs` init problem**:

- Any glibc-compiled C function with an array/buffer local carries
  `-fstack-protector` and begins with `mov %fs:0x28, %rax` (the stack-canary
  read). If `%fs` is not a glibc-compatible thread block, that prologue
  faults — **regardless of arg count** (`fncall1` through `fncall8` all hit
  it; it merely correlated with the 6-arg wgpu entry points, which have local
  buffers). The struct-packing "workaround" only sidestepped it by chance
  when the packed callee happened not to be stack-protected.
- The failure the C-launcher model was invented to avoid (ADR-004: *"calling
  libc's dlopen from a non-libc process crashes — TLS not initialized"*) is
  the same root cause.

### Satisfying it

1. **C launcher (preferred)** — mabda's `deps/wgpu_main.c`: C `main` gets
   full libc init (`%fs`, pthreads, dynamic linker), pre-inits the GPU, builds
   the fn-pointer table, then calls into cyrius. `%fs` is already glibc's, so
   every `fncallN` into wgpu works. This is the shipping model through the
   NVIDIA wgpu route's life (mabda v5.0, per ADR-006).
2. **Pure-cyrius dlopen** — call `dynlib_bootstrap_cpu_features()` +
   `dynlib_bootstrap_tls()` (+ `dynlib_bootstrap_stack_end(0)`) before the
   first extern-C `fncallN`. See `tests/tcyr/dynlib_init.tcyr`.

### Coexisting cyrius thread-locals in a foreign host

If cyrius code in a glibc-hosted process **also** uses its own thread-locals
(sigil crypto banking on slot 8, patra on slots 0-4), `thread_local_init`
would `arch_prctl(ARCH_SET_FS)` a fresh cyrius block over glibc's `%fs` —
wiping the TCB self-pointer at offset 0 and the **stack canary at 0x28**, and
`thread_local_set(5, …)` (offset `0x28`) would overwrite the canary directly.
Either breaks every stack-protected C callee.

The host declares itself once at startup with
**`thread_local_use_foreign_tls()`** (`lib/thread_local.cyr`). cyrius then
leaves `%fs` untouched and keeps its slots in a process-global fallback array
(identical to the macOS/agnos path). It is **explicit, not auto-detected**: a
native `CLONE_SETTLS` worker also has a non-zero `%fs`, so a `fs != 0 =>
foreign` heuristic would misclassify native workers and collapse their
per-thread crypto lanes (the v6.3.25 collision class). Foreign mode is
process-global, so it assumes cyrius thread-local code runs on a single thread
inside the host (the C launcher runs mabda on `main`); a foreign multi-thread
consumer would need a pthread-key backing (tracked follow-up).

Regression gate: `tests/gates/platform/ffi_stack_protected_extern_c.sh` (check.sh) — a
stack-protected extern-C `.so` via `fncall4/5/6/7` **and** the foreign-`%fs`
no-clobber / canary-intact proof.

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
