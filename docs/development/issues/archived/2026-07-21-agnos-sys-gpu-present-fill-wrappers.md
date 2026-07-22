# 2026-07-21 — agnos ask: `sys_gpu_present` (#84) / `sys_gpu_fill` (#85) wrappers

**Status:** ✅ **FIXED (cyrius 6.4.70, 2026-07-21).** `SYS_GPU_PRESENT = 84` / `SYS_GPU_FILL = 85` +
`sys_gpu_present()` (nullary) / `sys_gpu_fill(color)` landed in `lib/syscalls_x86_64_agnos.cyr`, with the
iron-only return semantics documented (`0`/`-1` under QEMU = "no GPU here", not a failure). Safety is the
**file-level** `#ifdef CYRIUS_TARGET_AGNOS` on the whole peer (`lib/syscalls.cyr`) — stronger than an
in-function guard: off-agnos the fns do not exist, so a Linux build referencing them fails at COMPILE time
with no binary emitted (the v6.4.63 `#82`/`#83` precedent; guarding 2 of ~80 rows would be false comfort
when `SYS_OPEN=7` is Linux `lseek`). `agnos-crossbuild-gate.sh` extended to all four band members, both
legs (correct numbers on agnos + ABSENT on Linux).
**⚠ While gating this I found the existing check was a PLACEBO:** `grep 'mov eax,0x54'` matches ASCII
`'T'` — 0x52-0x55 are `'R','S','T','U'`, so string-literal byte stores satisfied it and a mutated number
still reported PASS (verified: `#84 -> 99` passed the old check). Replaced with a precise extraction of the
`mov eax,0xNN` immediately preceding each `syscall`; mutation-proven (mutated → FAIL, restored → PASS).
That also repairs the latent hole in the v6.4.63 `#82`/`#83` checks.

**Original ask below.** Prior status: **agnos kernel:** done + **iron-proven** on archaemenid — `#84` cut with the P7
blit/present split (**1.55.x**), `#85` cut **1.55.30** (CP-DMA fill). **cyrius:** `SYS_GPU_PRESENT = 84` /
`SYS_GPU_FILL = 85` + agnos-gated wrappers — **this ask**. **Consumer:** `/bin/gpufill` (agnos `gpu-test/`)
currently calls the raw `syscall(84)` / `syscall(85, color)`.

Mirror: `agnos/docs/development/issues/2026-07-21-gpu-present-fill-syscall-cyrius-wrappers.md`.

Continues the band already landed in `lib/syscalls_x86_64_agnos.cyr`: `SYS_READDIR = 81`,
`SYS_GPU_DISPATCH = 82`, `SYS_GPU_DISPATCH_F64 = 83`. **The enum currently stops at 83** — #84/#85 are the gap.

## ⚠⚠ Safety — the sharpest Linux collision in this band so far

On **Linux x86_64**: syscall **84 = `rmdir(pathname)`** and **85 = `creat(pathname, mode)`**.

- **`sys_gpu_present()` is NULLARY.** Ungated on Linux it emits **`rmdir()` with whatever stale value is in
  `rdi`**, interpreted as a path pointer — a **destructive** call that can *delete a directory*. The existing
  rows in this band are non-destructive by comparison (`fchdir`#81 harmless; `rename`#82 / `mkdir`#83 damaging
  but not deleting). **This one removes data.**
- **`sys_gpu_fill(color)`** ungated becomes **`creat(color, mode)`** — a 32-bit pixel colour reinterpreted as a
  path pointer, creating/truncating a file at whatever that address decodes to.

The nullary shape compounds a known issue — see `2026-07-19-sys-reboot-nullary-vs-agnos-4arg-abi.md`: a
nullary wrapper must not leak a caller-visible register into `a1`.

**Both wrappers MUST be `#ifdef CYRIUS_TARGET_AGNOS`-gated, and on non-agnos targets must return an error
WITHOUT emitting the syscall instruction.**

## What the agnos kernel provides

### `#84 present() -> 1 / 0`
No arguments. Flips the accumulated blit back buffer to the scanout, **tear-free and vsync-paced**. The
explicit half of the blit/present split: a compositor blits windows with `blit`#39's `DEFER_PRESENT` bit (no
flip), then calls this **once** per frame. `1` = presented; `0` = nothing to present (double-buffer not armed /
direct-FB path).

### `#85 gpu_fill(color) -> 0 / -1`
`color` = 32-bit **xRGB8888**. GPU-clears the current blit back buffer to that colour via **CP-DMA** — a PM4
`DMA_DATA` constant-fill (`SRC_SEL=2 DATA`, value in dw2) on the MEC compute ring, replacing a full-screen CPU
store-loop. Arms the double-buffer lazily; pair with `present`#84 to show it. Ring-3 passes **only the colour**
— no GPU MC address crosses the boundary (`fb_phys` stays unexposed, same discipline as `blit`#39).
`0` = filled; `-1` = no usable display (no GPU/pipe — e.g. **QEMU**) or the fill failed.

### Behaviour notes for the wrapper docs
- **Iron-only.** Under QEMU `#85` returns `-1` and `#84` returns `0` **cleanly** (no fault) — treat as "no GPU
  here", not an error, exactly like the `#82`/`#83` precedent.
- **Both block.** `#84` blocks until the pipe takes the surface at the next vblank (≤ one frame) — it *is* the
  vsync pacer. `#85` busy-waits on a bounded CP-DMA completion fence (~100 ms cap).
- `#85`'s fill needs **no cache flush** to be scanout-visible (CP-DMA writes MC-direct, bypassing GL2).
- **Iron proof:** `gpu: CP-DMA hardware fill verified (4KB, all=pattern)` (agnos 1.55.30).

## The ask

```cyrius
SYS_GPU_PRESENT = 84;    # present() → 1/0; flip the blit back buffer to the scanout (RMDIR on Linux — DESTRUCTIVE)
SYS_GPU_FILL    = 85;    # gpu_fill(color) → 0/-1; GPU-clear the back buffer via CP-DMA (CREAT on Linux)
```

```cyrius
fn sys_gpu_present(): i64   { return syscall(SYS_GPU_PRESENT); }
fn sys_gpu_fill(color): i64 { return syscall(SYS_GPU_FILL, color); }
```

**Requirements**
1. **`#ifdef CYRIUS_TARGET_AGNOS`-gated** — `84 = rmdir` on Linux **deletes**; this is a safety gate, not a
   portability nicety. On non-agnos targets: return an error, do **not** emit the syscall.
2. **`sys_gpu_present()` is nullary** — no stale/caller register may leak into `a1`.
3. Document the iron-only returns so `-1` / `0` read as "no GPU here" rather than a failure.
4. Land for the next release; `gpufill` migrates off the raw numbers and re-pins.

## Consumers

- **`/bin/gpufill`** (agnos `gpu-test/`, 0.1.0) — reference ring-3 consumer: fills red/green/blue via `#85`,
  flips each in via `#84`, exits `95` iff all succeeded.
- **aethersafha** — the real target: compositor back-buffer clears + frame present.
