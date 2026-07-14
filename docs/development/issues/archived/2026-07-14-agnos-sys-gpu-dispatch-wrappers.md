# 2026-07-14 — agnos GPU-compute syscalls: `SYS_GPU_DISPATCH` (82) / `SYS_GPU_DISPATCH_F64` (83) wrappers

**Status:** ✅ **RESOLVED v6.4.63** (2026-07-14) — `SYS_GPU_DISPATCH`/`SYS_GPU_DISPATCH_F64` + both
wrappers shipped in `lib/syscalls_x86_64_agnos.cyr`; permanent gate `agnos-crossbuild-gate.sh` §1i.
**Note on the safety ask:** the requested in-function `#ifdef` was NOT added, because the premise was
wrong — `sys_readdir` has no such guard either. The whole peer is included behind `#ifdef
CYRIUS_TARGET_AGNOS` in `lib/syscalls.cyr`, which is STRONGER than the ask: off-agnos the fns do not
exist, so a Linux build fails at COMPILE time (`refusing to emit binary with 2 reachable undefined
function(s)`, no binary) rather than returning a runtime error — it can never emit rename/mkdir.
Guarding 2 of ~80 wrappers would be false comfort anyway (the peer is wrong in its entirety off-agnos:
`SYS_OPEN=7` is Linux `lseek`). Gate leg 2 pins the absence. **Remaining: gpumm 0.2.0 migrates off the
raw numbers and re-pins** (downstream).

**Original filing:** 🟡 OPEN — cyrius ask. **Requested by:** agnos (kernel leg done + iron-proven: `#82` cut
1.54.30, hardened 1.54.33; `#83` cut 1.54.33). **Consumer waiting:** `gpumm` 0.2.0 (currently on raw
`syscall(82/83, …)`).

Mirror: `agnos/docs/development/issues/2026-07-14-gpu-dispatch-syscall-cyrius-wrappers.md` (full kernel-side
detail lives there).

## The ask

Add two rows to the agnos syscall band in `lib/syscalls_x86_64_agnos.cyr`, mirroring the existing
`SYS_SND_*` / `SYS_BLK_*` / `SYS_READDIR` shape:

```cyrius
SYS_GPU_DISPATCH     = 82;   # gpu_dispatch(a,b,c) -> 0 / <0; 64xi32 A,B (row-major 8x8) -> C = A*B,
                             # computed on the AMD GPU shader cores. Iron-only (-1 where there's no AMD GPU).
SYS_GPU_DISPATCH_F64 = 83;   # gpu_dispatch_f64(a,b,c) -> 0 / <0; 64xf64 A,B -> C = A*B, rosnet-bit-correct.
```

```cyrius
fn sys_gpu_dispatch(a, b, c): i64     { return syscall(SYS_GPU_DISPATCH, a, b, c); }
fn sys_gpu_dispatch_f64(a, b, c): i64 { return syscall(SYS_GPU_DISPATCH_F64, a, b, c); }
```

## ⚠ The gate is a SAFETY requirement here, not just portability

On **Linux x86_64**: **82 = `rename(oldpath, newpath)`**, **83 = `mkdir(path, mode)`**.

An ungated wrapper would pass the caller's **matmul buffer pointers as filesystem paths** and attempt to
**rename a file** or **create a directory**. That is materially worse than the `SYS_READDIR`/81 precedent
(81 = `fchdir` on Linux — harmless by comparison).

**Both wrappers must be `#ifdef CYRIUS_TARGET_AGNOS`-gated and must NOT emit the syscall instruction on
non-agnos targets** (return an error instead), exactly as `sys_readdir` does.

## What these are

The agnos 1.54.x GPU arc drives the AMD Cezanne iGPU (gfx90c) **directly from the kernel — no amdgpu, no
ROCm**: PSP firmware load → CP/MEC engines → GPUVM → PM4 → hand-assembled gfx90c shaders → an 8×8 matmul on
the shader cores, verified bit-for-bit against a CPU reference on real hardware. `#82`/`#83` are the **ring-3
seam** onto that — the path **mabda / tentib / attn11** consume to run ML inference on the GPU *on agnos*
(mabda's GPU surface is Linux-only today; this is its agnos backend).

`#83` is deliberately **not** fused-FMA: the shader accumulates with separate `v_mul_f64` + `v_add_f64`
(two roundings, k-ascending) to match **rosnet**'s semantics (`f64v_fmadd` lowers to `mulpd+addpd`; the
scalar path is `f64_add(y, f64_mul(x, W))`). Iron-proven on rounding data where fused-vs-unfused diverge on
29/64 outputs — i.e. the GPU result is **bit-identical to rosnet's CPU arithmetic**.

## Semantics for the wrapper comments

- `a`, `b`, `c`: ring-3 pointers to 64-element row-major 8×8 arrays — **i32** for `#82` (256 B each),
  **f64** for `#83` (512 B each). `c` receives `C = A · B`.
- Return: `0` OK · `-1` GPU not ready · `-2` dispatch didn't complete · `-3` VM fault · `-4` pointer outside
  user range · `-5` user page not mapped.
- **`-1` is the normal answer where there is no AMD GPU (e.g. QEMU)** — consumers should treat it as "no GPU
  here", not a failure. Verified: the ELF loads, runs in ring 3, calls the syscall, takes `-1`, exits clean.
- **Blocking**: the kernel busy-waits on a bounded watchdog (~100 ms cap) for the dispatch fence.
- Kernel-side hardened (agnos 1.54.33): `is_user_range` on all three pointers + `proc_copy_from_user` for the
  A/B reads + a present/user page-walk verify before the C write-back.
- Fixed 8×8 today; a generalized (M,N,K) form would be new numbers, not a change to these.

## Done when

`SYS_GPU_DISPATCH` / `SYS_GPU_DISPATCH_F64` + the two agnos-gated wrappers ship in the next cyrius release;
`gpumm` migrates off the raw numbers and re-pins.
