# sandhi `_SANDHI_RPC_POLICY_SLOT = 16` is out-of-bounds on macOS/agnos thread-local

**Filed:** 2026-07-01 (surfaced while mapping the thread-local slot namespace)
**Severity:** Medium — latent OOB write on macOS/agnos; benign on Linux.
**Component:** vendored sandhi (`lib/sandhi.cyr:_SANDHI_RPC_POLICY_SLOT`).
**Status:** OPEN — **un-archived 2026-07-07**: it was archived while the OOB is still
live (macOS/agnos `TLOCAL_MAX_SLOTS = 16` → slot 16 is still one past the end; no fix
shipped). Lands as ONE coordinated cross-repo bite with
[`2026-07-01-thread-local-slot-namespace-no-allocator.md`](2026-07-01-thread-local-slot-namespace-no-allocator.md)
— the `thread_local_alloc()` allocator that hands out slots is the real fix, and the
`TLOCAL_MAX_SLOTS` bump on the macOS/agnos 16-slot arrays is exactly the raise this OOB needs.

## Problem

`lib/sandhi.cyr` uses `var _SANDHI_RPC_POLICY_SLOT = 16` as a `thread_local_set`/`get`
slot. But `TLOCAL_MAX_SLOTS = 16` → valid slots are **0..15**. Slot 16 is one past the
end.

- **Linux**: the per-thread TLS block is `TLOCAL_BLOCK_SIZE = 4096` B (512 slots), so
  `fs:[16*8]` lands inside the block — benign today.
- **macOS / agnos**: the block is `_tlocal_macos[128]` / `_tlocal_agnos[128]` = exactly
  16 slots × 8 B. `thread_local_set(16, ...)` writes at `+128` — **past the array**,
  corrupting whatever `.bss` global follows. A silent OOB write per RPC-policy set on a
  sandhi thread.

## Fix

In sandhi source, move `_SANDHI_RPC_POLICY_SLOT` into the valid range (a FREE slot per the
`lib/thread_local.cyr` registry — 5-7 or 9-14 as of v6.3.25), version-bump sandhi, regen
dist, re-vendor. (Or fold into the `thread_local_alloc()` migration once that lands — see
the sibling `thread-local-slot-namespace-no-allocator` issue.) Cross-repo (vendored
sandhi).
