# `CYRIUS_DCE=1` NOP-fills dead code and reclaims zero bytes — the flag says "eliminate"

**Status:** 🟠 **OPEN.** Attempted at v6.5.68, implemented, **reverted** — the naive route
produces a compiler that SIGSEGVs. The measurements and the failed approach are below so the
next attempt does not re-derive them.
**Filed:** 2026-09-06 (during v6.5.68 — whole-program NOP compaction)
**Severity:** P2 — a documented user-facing flag does not do what it says; no miscompile.
**Component:** `src/backend/x86/fixup.cyr` (the DCE pass + the fixup patch loop).

## The defect

`CYRIUS_DCE=1` finds unreachable functions and overwrites their bodies with `0x90`. It does not
remove them. The binary is byte-for-byte the same size with the flag on and off:

| cycc self-compile @ 6.5.68 | file | `.text` | NOP bytes |
|---|---|---|---|
| default | 1,218,104 | 1,068,408 | 1,852 |
| `CYRIUS_DCE=1` | 1,218,104 | 1,068,408 | **36,699** |

`note: 76 unreachable fns (34847 bytes NOPed)` — recognised, padded, shipped. Meanwhile the
default-path message at `fixup.cyr:641` reads *"set `CYRIUS_DCE=1` to **eliminate**"*.

**34,847 bytes is 3.3 % of `.text`**, twice the whole-program IR harvest v6.5.68 shipped.

## The stated reason is no longer true

The pass documents the choice:

> NOP-fill (not code shifting) is the intentional tradeoff:
>   - O(n) one pass, no fixup rework, deterministic (self-host stable)
>   - Binary size unchanged (compresses vastly better though)
>   - **Code shifting would break cycc==cycc byte-identity; deferred.**

v6.5.68 disproves the last line: whole-program compaction is deterministic, the compacted
compiler reaches the same fixpoint, and it reproduces the uncompacted compiler byte-identically.
⚠ This is the shape the repo keeps finding — a limitation written down as a design decision,
which is then never revisited. Treat the comment as the bug report.

## Why it did not pack into v6.5.68 — measured, not asserted

The ordering is **forced**, and that is the whole difficulty:

1. **DCE seeds liveness by SCANNING EMITTED `rel32` control transfers** (`fixup.cyr`, seed
   pass: *"scan rel32 control transfers, classify by host fn"*). It therefore cannot run before
   the fixup patch loop — with placeholders in place every target reads as garbage.
2. Compaction cannot run before DCE, or there is no dead-function fill to collect.
3. So the only consistent sequence is **patch → DCE → compact → re-patch**.

The re-patch is sound in principle: the patch loop is a pure function of (fixup table, fn
offsets, entry, dbase), recomputing every site rather than accumulating.

## What was built and what happened

All of this was implemented and is preserved at
`scratchpad/p68/fixup_bite3.cyr` (see the release session):

- `_fixup_patch_loop(S, entry, dbase, pfx, kmode, vcnt, fcnt, totvar)` — the patch loop
  extracted so it can run twice. ✅ **Verified behaviour-preserving**: 22/22 corpus inputs
  compile byte-identically before and after the extraction.
- The dead-function fill registered into the whole-program run table.
- Fixups whose CP lands **inside a deleted body** voided to `-1` (they have no image in the new
  layout, and "shifting" one yields a plausible address inside LIVE code that the re-patch would
  then overwrite — a miscompile manufactured by the repair itself). 96 such fixups in cycc.
- A second `wp_compact` call plus a re-patch against a recomputed `dbase`.

Result: `note: 34847 bytes of dead code ELIMINATED (96 fixups voided)`, binary 1,185,384 B —
and the resulting compiler **SIGSEGVs (rc 139)** and fails **300 of 301** corpus compiles.

So something beyond the fixup-mediated sites is position-dependent after the patch loop. The
prime suspects, in order, none yet confirmed:

1. **`dbase` moves when the code shrinks.** Every absolute data fixup was patched against the
   old `entry + acp`; the re-patch uses the new one, but `EMITELF` derives its own data base
   (`_wx_data_vaddr` / the W^X 2 MB pad) and the two must agree exactly.
2. **`acp` alignment**: the original computes `cp = GCP(S)` then aligns; compaction changes the
   alignment residue.
3. **Sites written at emit time that no table records** — the whole-program disp32 registry
   covers `EJCC`/`EJMP`/`EJMP0`/`ECALLTO` and the entry trampoline, but a site resolved during
   the *first* patch loop and not re-derivable from a fixup entry would be orphaned.

## Acceptance

- `CYRIUS_DCE=1` on a cycc self-compile removes ~34.8 KB of `.text` rather than padding it.
- The DCE-built cycc compiles `src/main.cyr` to bytes identical to the non-DCE build's output.
- Whole corpus: default vs `CYRIUS_DCE=1` — zero divergences in compile status and exit code.
- The `differential.sh` DCE axis is deliberately **re-baselined** in the same change (v6.5.68
  already moved recognised dead code 16,404 → 34,847 bytes by widening decoder coverage).
- Gate: dead-function identity across the five shapes, mutation-proven by voiding the
  fixup-voiding step — which must produce the SIGSEGV above, not a quiet pass.

## ⟳ v6.5.70 — ATTEMPTED AGAIN. Three more causes found; still not landed.

Re-attempted rather than left sitting. Three concrete defects in the v6.5.69 approach, each
measured, so the next attempt does not re-derive them:

1. ⛔ **The dead-body fixup voiding called `_wp_inside` — a BINARY SEARCH — before
   `wp_compact` had sorted the run table.** It searched unsorted data and voided the wrong
   entries. This was the single biggest cause of the SIGSEGV and it is now structurally
   impossible: the voiding lives inside the pass as "stage 0", after `_wp_sort_prefix`.
2. ⛔ **`dbase` must NOT be recomputed after compaction.** v6.5.69 derived a new one from the
   shrunken code size, on the reasonable theory that data follows code. It does not — measured,
   `.rodata` and `.bss` land at IDENTICAL vaddrs with and without elimination (0x600750 /
   0x600000), because the data segment gets its own 2 MB-aligned page. Recomputing relocated
   every absolute data reference by the bytes reclaimed.
3. ⛔ **Extracting the fixup patch loop into its own function BREAKS THE SEED CHAIN.** `cybs`
   — the hand-assembly bootstrap compiler — cannot compile the extracted 8-parameter function
   and fails with a bare `syntax error`; `scripts/seed-derive-cycc.sh` step 3 goes red while
   `build/cycc` compiles it fine. This is exactly the cybs-ceiling class CLAUDE.md warns about,
   and it constrains the design: **the re-patch cannot be a new function of that size.** Either
   inline the second pass, or split the loop small enough for cybs.
   ⚠ Do NOT bisect this with `build/cycc`'s neighbour `build/cybs` — that binary is stale and
   fails on a CLEAN HEAD tree too, which invalidated a whole bisect. Assemble the real one:
   `cat bootstrap/cybs.cyr | bootstrap/asm > cybs`.

**Where it stands with 1 and 2 fixed:** `CYRIUS_DCE=1` reports `34847 bytes of dead code
eliminated`, the binary shrinks 1,231,040 → 1,198,272 B, and the resulting compiler still
SIGSEGVs. The fault is a control transfer to an address ~32 KB BELOW `.text` — the amount
reclaimed — from a call whose `rel32` was never re-patched, with an unpatched `jmp rel32=0`
beside it. So a live region is still being spliced: either a run covers live code, or a fixup
that should have been re-patched was skipped. That is the next thing to chase, on the small
reproducer (a 5-line program with two dead fns) rather than on cycc itself.
