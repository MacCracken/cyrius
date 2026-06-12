# CVE-24 re-scoped — the per-fn local tables are slot-indexed and overflow on large stack frames

**Filed:** 2026-06-12 (split out of the F3 pack at the v6.1.38 cut)
**Severity:** P2 (latent OOB write; benign in practice today)
**Supersedes:** the CVE-24 entry in `2026-06-10-memory-safety-parity-gaps.md`,
whose premise was wrong.

## What the audit got wrong

CVE-24 was filed as "locals registration has no cap → add a count guard in
`SFLC` (mirror `SVCNT`)." The naive fix (`if (v >= 256) error`) was implemented
in v6.1.38 and **reverted before the cut** because it breaks legitimate code.

`SFLC` / `local_cnt` (`S + 0x18DA10`) is **not a variable count** — it is the
**stack-frame size in 8-byte slots**. A `stack var buf[N]` registers `N/8`
per-slot entries: the loop in `parse_decl.cyr` (~1162) writes `nslots - 1`
anonymous filler slots (`fn_local_names[li] = -1`) plus one named slot, bumping
`local_cnt` by `N/8`. So:

- `stack var buf[16000]` → `local_cnt += 2000`.
- `tests/tcyr/stack_var.tcyr::big_frame` (a **committed** 16 KB `__chkstk` test)
  drives `local_cnt` to ~2000 and compiles + runs correctly today.

## The actual bug

The local tables are all indexed by `local_cnt` (the slot index), but are sized
far smaller than large frames need:

| table | accessor | base | capacity |
|---|---|---|---|
| `fn_local_names` | `0x191000 + li*8` | `0x191000` | ~256 slots (ends `0x191800`) |
| `local_depths` | `SLDEP`/`GLDEP` | `0x191800` | ~256 slots (ends `0x192000`) |
| `local_types` | `SLTYPE`/`GLTYPE` | `0x192200` | 576 slots (ends `0x193400`) |
| `local_slice_widths` | `SSLICE_W`/`GSLICE_W` | `0x193400` | 576 slots (ends `0x194600`) |

Any function whose frame exceeds the smallest table (256 slots = 2 KB) writes
these per-slot tables **past their region into the neighbouring heap** (and a
`local_types`/`slice` index past 576 does likewise). `big_frame` (2000 slots)
overruns all four. It has been **silently benign** — the corrupted high-index
entries are not read back in a way that breaks codegen for the simple functions
that hit it — which is exactly why it never surfaced. It is a real OOB write and
could miscompile a more complex large-frame function.

## Why a count cap is the wrong fix

A cap at the table size (256) rejects sanctioned large frames (`big_frame`, any
`>2 KB` `stack var`). Capping higher still rejects frames larger than the cap, and
frames are effectively unbounded (`stack var buf[1_000_000]`).

## Real fix options (pick at scoping)

1. **Grow + cap.** Relocate/grow the four slot-indexed tables to a generous size
   (e.g. 8192 slots = 64 KB frames) and cap `local_cnt` at the new capacity with a
   loud error. Heap-map change → mandatory cross-OS re-verify. Rejects only
   pathological multi-64 KB stack frames (arguably correct — those are stack-blow
   risks anyway).
2. **Stop polluting the slot-indexed tables.** Register a `stack var buf[N]` as a
   single named entry with a size/width attribute and reserve the frame space in
   the offset allocator separately, instead of `N/8` filler slots. Removes the
   coupling between frame size and table size entirely. Larger refactor (the
   fillers currently drive the slot-by-slot offset allocator).

## Status

OPEN. CVE-25/26/27/28 + AR-03 shipped in v6.1.38; CVE-24 deferred here. Needs a
scoping decision (option 1 vs 2) before implementation.
