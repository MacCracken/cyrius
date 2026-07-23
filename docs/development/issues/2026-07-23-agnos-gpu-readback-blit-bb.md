# 2026-07-23 — agnos ask: #90 `gpu_readback_shm` + #91 `gpu_blit_bb` wrappers (Tier 2 now SHIPPED in agnos)

**Status:** 🟡 **OPEN.** Promotes the two **Tier 2** rows of
[`2026-07-22-agnos-gpu-display-syscall-band.md`](2026-07-22-agnos-gpu-display-syscall-band.md) — which held
`#90`/`#91` as *reserved, not requested* ("wrap each as agnos ships it"). **agnos has now shipped both**, so
the trigger has fired. This closes the numbering hole: the kernel dispatch was contiguous through `#89`, then
jumped to `#92`; `#90`/`#91` were live-but-unimplemented. Wrapping them lets the ring-3 band be contiguous
`84…92` with no gap.

**Discovered:** 2026-07-23 while landing the two kernel handlers in agnos.
**Severity:** Medium — the peer-add itself is ergonomic (Low), but both numbers collide with **destructive**
Linux syscalls and `#91` would plausibly **succeed** off-agnos, so the file-level gate is load-bearing.
**Affects:** cycc 6.4.71 (`lib/syscalls_x86_64_agnos.cyr` stops at `#89`); wrappers would land 6.4.72+.

Mirror: `agnos/docs/development/issues/2026-07-23-gpu-readback-blit-bb-wrappers.md`.

## Summary

Two new agnos GPU syscalls need `sys_*` wrappers. Both are CP-DMA jobs built on the iron-proven
`gpu_cp_dma_blit` primitive that `#87 gpu_blit_shm` already uses — no new engine mechanism.

- **`#90 gpu_readback_shm(id, wh, srcxy) -> 0 / -1`** — the **inverse of #87**: GPU-copy a `w×h` rect **out of**
  the blit back buffer at `(sx,sy)` **into** the client's carveout shm slot `id`. The screen-capture /
  read-pixels primitive; without it a compositor reading its own shm sees **stale** content (the composited
  frame lives in the kernel back buffer, never the client page). Pack: `wh = (h<<16)|w`, `srcxy = (sy<<16)|sx`.
  Rejects (does not clip): off-screen, a slot too small for `w*h*4`, a PMM-backed slot (GPU can't write it),
  no display.
- **`#91 gpu_blit_bb(srcxy, wh, dstxy) -> 0 / -1`** — GPU rect **copy within** the blit back buffer (move a
  window / scroll a region). Pack: `srcxy = (sy<<16)|sx`, `wh = (h<<16)|w`, `dstxy = (dy<<16)|dx`. Rejects
  either rect off-screen. **Overlap is handled kernel-side** (a downward move copies rows bottom-up, memmove
  semantics) — the wrapper needs no reverse-order logic. Residual: intra-row horizontal overlap on the SAME
  source row is undefined; a caller must not self-overlap a single row.

Kernel half is landed and green on the agnos side: `scripts/build.sh` OK, `scripts/check.sh` 14/0 (incl. the
call-arity gate). Not iron-proven — QEMU has no AMD GPU — but that is the agnos side's burn to run, not a
cyrius concern.

## Reproduction

Not a bug — a peer-add. The "repro" is the gap: `lib/syscalls_x86_64_agnos.cyr` defines wrappers through
`#89 sys_gpu_caps` and then `#92 sys_gpu_shader_op`, with nothing at `90`/`91`, so a ring-3 program cannot
call either kernel handler through the portable surface.

## Root cause

n/a (surface gap, not a compiler defect).

## Proposed fix

Add to `lib/syscalls_x86_64_agnos.cyr`, inside the existing **file-level** `#ifdef CYRIUS_TARGET_AGNOS` GPU
band (so off-agnos the functions do not exist and a referencing build fails at compile time):

```cyrius
SYS_GPU_READBACK_SHM = 90;   # gpu_readback_shm(id,wh,srcxy) → 0/-1; capture bb→shm.
                             # CHMOD on Linux — a metadata WRITE that can set setuid. Gate is load-bearing.
SYS_GPU_BLIT_BB      = 91;   # gpu_blit_bb(srcxy,wh,dstxy) → 0/-1; bb→bb move/scroll (overlap-safe kernel-side).
                             # FCHMOD on Linux — (0,0) packs to fd 0 = stdin, would PLAUSIBLY SUCCEED. Gate load-bearing.
```
```cyrius
fn sys_gpu_readback_shm(id, wh, srcxy): i64 { return syscall(SYS_GPU_READBACK_SHM, id, wh, srcxy); }
fn sys_gpu_blit_bb(srcxy, wh, dstxy): i64   { return syscall(SYS_GPU_BLIT_BB, srcxy, wh, dstxy); }
```

Docstrings should carry (as 6.4.70/6.4.71 did for `#84`–`#89`): the packing, the reject-don't-clip contract,
the **Linux collision + destructive flag**, and the **iron-only** returns (`0`/`-1` under QEMU means "no GPU
here", not a failure). Extend `scripts/agnos-crossbuild-gate.sh` to assert `#90`/`#91` and cover the
Linux-absence leg (mutation-prove one row like the `#87 → 79` FAIL/restore check).

### Safety — both land on destructive Linux numbers

| # | agnos | Linux x86_64 | Destructive? | Notes |
|---|---|---|---|---|
| 90 | `gpu_readback_shm` | **`chmod(path,mode)`** | **YES** | A packed geometry word as a mode can set **setuid**. Mitigating: arg1 is a 1..N id ⇒ near-null path ⇒ EFAULT overwhelmingly likely. |
| 91 | `gpu_blit_bb` | **`fchmod(fd,mode)`** | **YES** | arg1 is a packed `srcxy`; **`(0,0)` packs to fd 0 = stdin**, so small coordinates are valid fd numbers and the Linux call would **plausibly SUCCEED**. |

The file-level `#ifdef CYRIUS_TARGET_AGNOS` gate on the whole peer is the only barrier — same posture the band
has used since `#84`/`#85` in 6.4.70.

## Consumer-side workaround (if any)

None shipped and none needed yet — neither syscall has a shipping ring-3 caller (the consumers are
`aethersafha` screen-capture for `#90` and `win_move`/damage-scroll for `#91`, both future). If a consumer
needs one before the wrapper lands, the established stopgap is a local `#ifdef CYRIUS_TARGET_AGNOS` raw
`syscall(90, …)` / `syscall(91, …)` (as hapi did for `readlink`#70), removed when the peer ships. Nothing is
blocked.
