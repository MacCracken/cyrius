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
(`src/frontend/parse_fn.cyr`: `fsz = (flc*8 + 15) & ~15`), so RSP / SP
is 16-byte aligned in a function body **between statements**.
`fncall7` / `fncall8`'s x86 variants reserve 16 bytes via
`sub rsp, 16` to hold the stack arg(s) plus padding; aarch64 pushes
each stack arg with `str xN, [sp, #-16]!`.

> ⛔ **"Between statements" is load-bearing, and until 6.6.5 this file
> said "in every function body" without it.** x86 evaluates expressions
> on the machine stack — one `push rax` per pending value — so inside an
> expression RSP is 16-aligned only when an EVEN number of values is
> pending. `f(0, c())` called `c` with RSP 8 bytes off; `var t = c();
> f(0, t);` did not. Since 6.6.5 the call emitters track that depth and
> pad, so the invariant genuinely holds at every call site; before it,
> any nested call into C whose callee spilled SSE with `movaps`/`movdqa`
> — what gcc emits for ordinary code — took a #GP. The shift is also
> inherited: a cyrius fn entered misaligned runs its whole body
> misaligned. See CHANGELOG [6.6.5] and
> `docs/development/issues/archived/2026-09-16-mabda-cycc-nested-call-stack-misalignment.md`.
>
> ⛔ **And the frame rounding only makes the body aligned if the ENTRY
> was.** `fsz = (flc*8 + 15) & ~15` preserves a parity; it does not
> create one. Three targets were found inheriting the entry parity
> instead of establishing it in 6.6.5 — PE, UEFI and x86_64 Mach-O, the
> last of which has no fixed parity at all (it varies with the argv/env
> byte count; see item 4 under *SysV 16-byte stack alignment* below).
> Every landing that needs one now emits it.

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

Acceptance: `tests/tcyr/codegen/sysv_odd_stack_args.tcyr` (5
assertions covering callers with 7/8/9/10/11 params hitting an
SSE-using leaf) was added as the regression gate.
Sandhi-filed: `sandhi/docs/issues/2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md`.

**6.6.5 generalises this, and corrects two claims in the paragraph above.**

1. The v5.6.41 rule padded on `nextra & 1` alone, which assumes the call
   is emitted with NOTHING else pending — true at statement level, false
   inside an expression. The parity is `(nextra + depth) & 1`, where
   `depth` is the number of values the enclosing expressions have pushed;
   at depth 0 it reduces to exactly the old test, which is why 7-arg
   calls at statement level are byte-identical across the change.
2. **"The Win64 path was already correct" was wrong twice.** Its
   `framesize & 15` branch only rounds the frame; the parity pad it also
   applied (`n & 1`) had the same depth-blind assumption. And underneath
   both, the PE *base* was inverted: Windows enters an image with the
   return address pushed (RSP ≡ 8) and cyrius never re-aligned, so on
   Windows it was the STATEMENT-level calls that were misaligned. 6.6.5
   adds the landing seed and retunes the seven fixed-frame kernel32
   reroutes that had been hand-tuned to the inverted base.
3. **UEFI shares that entry convention and adds one requirement of its
   own.** A UEFI Application's entry point IS an MS-x64 function and
   firmware reads its `rax` as the `EFI_STATUS`, so the image exits with a
   `ret` — and `ret` pops `[rsp]` itself, so it is correct only where rsp
   is EXACTLY the rsp firmware entered with. It never is: the landing seed
   moved it by 8, and a `syscall(60, x)` inside a fn body is a whole frame
   plus its locals below that (`lib/alloc.cyr` and `lib/bounds.cyr` abort
   exactly that way, so a UEFI image takes the route on OOM or a bounds
   trip with no explicit exit in user code). 6.6.5 therefore PARKS the
   entry rsp at the landing — `lea r13, [rsp]`, before the seed — and
   emits `mov rsp, r13; ret` at every exit, which is depth-independent.
   r13 is reserved from the register allocator on that target
   (`_ra_cap = 2` in `src/frontend/parse_fn.cyr`); a parked register the
   allocator may assign to a hot local is not parked. Hand-written asm in
   a UEFI image that returns through its own `ret` must carry the same
   correction itself — see `programs/efi_probe.cyr`'s deliberately
   asymmetric `sub rsp,0x20` / `add rsp,0x28`.
4. **x86_64 Mach-O has NO fixed entry parity, and that is a per-KERNEL
   fact rather than an ABI one.** Items 2 and 3 are both "this platform
   enters at RSP ≡ 8, so seed the landing". Darwin is not that: MEASURED
   ON REAL HARDWARE (ach, Darwin 22.6.0, x86_64), XNU does not 16-align
   the initial rsp of a static Mach-O executable — it falls where the
   argv/env string area leaves it, so the parity varies with the
   process's own name and environment. One binary, renamed: `./_l` and
   `./_lt` misaligned, `./_ltxx` and `/tmp/csa2` aligned; `PADVAR=x`
   misaligned, `PADVAR=xxxxxxx` aligned. A 20-argv0-length × 16-env-pad
   sweep splits 160/160 and tracks the parked entry rsp (`r15 & 15`) row
   for row. 6.6.5 therefore emits `and rsp, -16` (`EALIGN_RSP_16`) at the
   Mach-O landing, AFTER the `mov r15, rsp` park, in BOTH `src/main.cyr`
   and `src/main_x86_macho.cyr`. It rounds DOWN, so it is correct for
   either parity.

   **The rule the three share: a landing must ESTABLISH the alignment
   invariant, never inherit it.** Every alignment statement in this
   document is relative to the landing, so the landing itself has to be
   an absolute. Linux ELF is the one target that may inherit — SysV amd64
   §3.4.1 makes `rsp ≡ 0` at `_start` a guarantee, measured 320/320 over
   the same sweep. aarch64 is safe architecturally (measured 320/320 on
   ecb, its anti-vacuous control 320/320 at 8) and agnos builds rsp from
   two 16-aligned terms in its own loader.

   ⚠ **On Darwin, re-running a test under one name is not a
   verification.** The cross-OS lib-test runner names every binary
   `./_lt`, i.e. it samples exactly one parity; use the argv0/env sweep
   in `tests/gates/codegen/call_site_stack_alignment.sh`'s header.

Also note `tests/tcyr/codegen/sysv_odd_stack_args.tcyr`'s leaf uses
`movdqu`, which does NOT fault on a misaligned address — it pins the
argument VALUES, not the alignment. The alignment gates are
`tests/gates/codegen/call_site_stack_alignment.sh` (a gcc leaf that
measures `(rsp+8) & 15` with the CPU, plus a `movaps` leaf that faults)
and `tests/tcyr/crossos/call_site_stack_alignment.tcyr` (the same rows on
real ecb / ach / cass / pi).

---

## Extern-C prerequisite: a glibc-compatible `%fs` (v6.3.26)

**There is no `fncall6` calling-convention bug.** The v6.3.26 slot was
scheduled as one ("Class B FFI / `fncall6` ABI fix"); investigation proved
the arg-passing (`rdi,rsi,rdx,rcx,r8,r9`) and 16-byte stack alignment are
correct — a real gcc-compiled, stack-protected C function taking 4/5/6/7
integer args returns the right result when called via `fncallN`.

> ⚠ 6.6.5: that conclusion holds for the position v6.3.26 tested — a
> `fncallN` at TOP LEVEL, in left-operand position, where nothing is
> pending on the expression stack. It was read for years as "16-byte
> alignment into extern C is correct" full stop, and the same callees
> called from a NESTED position (`f(0, fncallN(...))`, `store64(&s,
> fncallN(...))`) were entered 8 bytes off and SIGSEGV'd on their
> `movdqa` spills. The gate now covers both positions; a gate proves only
> the position it tests.

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
- `tests/tcyr/stdlib/fncall_ceiling.tcyr` — correctness regression for
  all `fncall0..fncall8` on both arches.
- `tests/tcyr/codegen/sysv_odd_stack_args.tcyr` — v5.6.41 SysV
  argument-passing regression gate (its leaf uses `movdqu`, so it does
  NOT catch misalignment).
- `tests/gates/codegen/call_site_stack_alignment.sh` +
  `tests/tcyr/crossos/call_site_stack_alignment.tcyr` — 6.6.5: rsp is
  16-aligned at every call, in every expression position, on every host.
- mabda's `docs/issues/2026-04-19-fncall6-wgpu-crash-resolution.md`
  — concrete case study of the struct-by-value failure mode.
