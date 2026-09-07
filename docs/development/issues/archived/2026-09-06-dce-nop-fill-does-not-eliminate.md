> ### ✅ RESOLVED at v6.5.72 — `CYRIUS_DCE=1` now ELIMINATES. Four attempts, six causes.
>
> **36,864 bytes removed from a cycc self-compile** (1,235,272 → 1,198,408), the eliminated cycc
> compiles and **reproduces the normal build byte-identically**, and the whole corpus agrees:
> **0 divergences of 301**, elimination firing on 297.
>
> The six causes, in the order they were found — recorded because each one produced a
> confidently-wrong diagnosis first:
> 1. **`_wp_inside` (a BINARY SEARCH) called before the run table was sorted** — it searched
>    unsorted data and voided the wrong fixups. (v6.5.71)
> 2. **`dbase` recomputed after compaction.** Data does NOT follow code — `.rodata`/`.bss` land
>    at identical vaddrs with and without elimination — so recomputing relocated every absolute
>    data reference by the bytes reclaimed. (v6.5.71)
> 3. **Extracting the fixup patch loop breaks the SEED CHAIN** — cybs cannot compile it and
>    `seed-derive` goes red while `build/cycc` is fine. So the fixup sites are repaired
>    ARITHMETICALLY instead of by re-running the loop. (v6.5.70)
> 4. **The position registries were gated on `IR_ENABLED`** — correct when written at v6.5.68,
>    and silently EMPTY for this new consumer, so the repair stage fixed no jump at all. A gate
>    written against one caller disables the machinery for the next one. (v6.5.71)
> 5. **The fixup repair ran AFTER the CP shift**, so it wrote at post-compaction coordinates into
>    a buffer that had not moved yet — 3 corrupted live bodies in a five-line program, 147 in
>    cycc. It must run beside stage 1, on pre-compaction coordinates. (v6.5.72)
> 6. **ftype-3 fixups were never repaired** — absolute function ADDRESSES, behind every indirect
>    call. This is the one no body-level audit can catch, because every body still decodes
>    perfectly; it surfaced as SIGILL on `callq *-0x48(%rbp)` landing mid-instruction. (v6.5.72)
>
> Two more things had to change that were not defects in the pass itself:
> * **The undefined-call verdict now runs BEFORE elimination.** "Is this undefined call
>   reachable?" is a property of the program the user WROTE. Computed after elimination, a
>   shifted call site slid into a neighbouring live function and 186 of 301 corpus programs
>   stopped compiling.
> * **`DECODE_LEN` could not walk `0F 38` / `0F 3A`** — it bailed with "Cyrius doesn't emit these
>   in normal codegen", and it does: `roundsd` in the float-formatting path. The v6.5.68 audit
>   only ever saw cycc's own `.text`, which contains none. **A coverage claim is only as wide as
>   the corpus it was measured on.**
>
> The pass now AUDITS ITSELF: after compaction it walks every surviving live body with the length
> decoder and refuses to emit if one stopped decoding — **baseline-relative**, because the first
> cut asserted absolutely and blocked 240 programs for a decoder gap rather than for corruption.
>
> Gate: `tests/gates/codegen/dce_eliminates.sh`, 4 axes.

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

## ⟳ v6.5.71 — FOURTH cause found, and SMALL PROGRAMS NOW WORK END TO END.

Closest yet. Two design changes and one more root cause:

4. ⛔ **THE REGISTRY WAS EMPTY ON A DCE BUILD — and it was my own optimisation that emptied it.**
   v6.5.68 gated `_wpjs_add` / `_wpsw_add` on `IR_ENABLED` because `wp_compact` only ran under
   `CYRIUS_IR` and recording cost 3.8 % of self_compile on every other build. That was correct
   when written. Adding a SECOND consumer (`CYRIUS_DCE=1`) made it wrong: on a DCE build with no
   IR the registry holds nothing, so stage 1 repairs **no jump at all** and the eliminated binary
   faults on the first call it should have fixed. **A gate written against one caller silently
   disables the machinery for the next one.** The fix is a lazy `_wp_recording(S)` that ORs in a
   `CYRIUS_DCE` env read (FIXUP reads that flag far too late for the emit path).

5. **Do NOT re-run the fixup patch loop; repair its sites arithmetically.** Cause 3 above says
   extracting that loop breaks cybs. It is not needed: after compaction, walk the fixup table and
   adjust each ftype-2 `rel32` by the shifts at both ends — the same formula stage 1 uses for
   recorded jumps, and disjoint from them (WPJS holds EJCC/EJMP/EJMP0/ECALLTO; the fixup table
   holds ECALLFIX). ftype-3 holds an ABSOLUTE fn VA and must be rewritten from the shifted
   `_fnt_offsets`; every other ftype is an absolute DATA address and must be left alone, because
   data does not move.

**STATE: small programs are CORRECT.** A 5-line fixture with two dead functions eliminates
32,686 bytes and exits 42 — the right answer, from a compacted binary. That is the first time any
attempt has produced a working eliminated program.

**cycc itself still fails**, and the symptom is now precise and different: a call whose target is
**2 bytes off**, landing mid-instruction inside a live function's prologue (`callq 0x4001fc`
where 0x4001fc is inside `movq %r13, -0x18(%rbp)`), not the 32 KB error of earlier attempts.
Disabling the arithmetic repair changes the failure to SIGILL, so that stage is necessary but not
yet sufficient. A 2-byte discrepancy points at a run boundary rather than a whole-table mistake —
the next thing to check is whether a dead body's `[dfoff, dfend)` can overlap a live neighbour's
first instructions, or whether some site is being repaired twice.

⚠ Reproduce with the SMALL fixture first — it is now the control that passes, so any change can
be checked against a known-good case before running cycc.
