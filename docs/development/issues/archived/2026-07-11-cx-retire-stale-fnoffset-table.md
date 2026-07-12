# cx: retire the stale 0xE92000 fn-offset table (ftype==3 fn-pointer + undefined-warning + DCE-stub write still use it)

**Filed:** 2026-07-11 (during v6.4.54; the forward-call `ftype==2` reader was migrated, these remain).
**Severity:** P3 (cleanup + latent correctness; the reachable path — `ftype==2` forward calls — is fixed).
**Backend:** cx (cyrius-x bytecode) only. `src/main_cx.cyr`.

## Background

The canonical fn-offset table is `_fnt_offsets` (cx: `S + 0x9CA000`), written by the SHARED
`PARSE_FN_DEF` (`parse_fn.cyr:2435/3021`) and read by the backward-call path
(`parse_fn.cyr:1526` → `ECALLTO`). A **second, stale** fixed-address table at `S + 0xE92000`
predates the relocatable `_fnt_offsets` and is only used by cx-fork code. v6.4.54 migrated the
forward-call resolver (`ftype==2`) off 0xE92000 onto `_fnt_offsets` — the reachable bug. Three
0xE92000 users remain, all latent/cosmetic:

## Remaining 0xE92000 references (`src/main_cx.cyr`)

1. **DCE-stub write** (~`:337`): `S64(S + 0xE92000 + stub_fi * 8, GCP(S))` records a DCE-dead
   fn's stub offset in 0xE92000, not `_fnt_offsets`. Harmless today (dead fns are unreferenced →
   never called), but inconsistent. Should also (or instead) write `_fnt_offsets[stub_fi]` so a
   `CYRIUS_DCE=1` build resolving a forward call to an eliminated fn lands on its stub rather than
   reading `_fnt_offsets = -1`.
2. **Undefined-fn warning** (~`:386`): `if (L64(S + 0xE92000 + wfi*8) < 0)` — 0xE92000 is all-zero
   in a normal build (only DCE stubs write positive offsets), so this check NEVER fires on cx
   (the warning is effectively dead). Reading `_fnt_offsets` (which is `-1` for
   registered-but-undefined fns) would make it work — and corroborates `_fnt_offsets` is the live
   table.
3. **`ftype==3` fn-pointer fixup** (~`:432`): `var foff = L64(S + 0xE92000 + idx*8)` has the same
   stale-table read as the (now-fixed) `ftype==2`. cx has no indirect-call op (`ECALLIND` fails
   loud), so a fn-pointer *value* can only be stored/compared, never called — but it would store a
   garbage (0) offset. Migrate to `_fnt_offsets` for consistency.

## Fix

Migrate all three to `_fnt_offsets` and delete the 0xE92000 region from the cx heap map (retire
it). Verify the undefined-fn warning fires correctly, `CYRIUS_DCE=1` cx builds resolve forward
calls to eliminated-fn stubs, and cx self-host stays byte-identical.

## Acceptance

- No cx code reads/writes 0xE92000; all fn-offset lookups go through `_fnt_offsets`.
- Undefined-fn warning fires on cx for a registered-but-undefined fn.
- cx self-host byte-identical; x86 unaffected.

---

**RESOLVED — v6.4.58** (2026-07-12). See CHANGELOG [6.4.58]. Verified: x86 self-host byte-identical + seed-derive, cross-OS self-host on ecb/cass/pi, and (for the cx items) the `_cx_v6458_modulo_immediate_gate` cxvm exit-code gate; (for the Windows items) `vr01_atomic_write.tcyr` 23/23 on real cass.
