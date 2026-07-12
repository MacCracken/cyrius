# cx: value-form SIMD params & returns (the Phase-4 tail of the cx-SIMD arc)

**Status (2026-07-11): RESOLVED in cyrius 6.4.54.** Implemented the four marshaling emitters
(`ESTOREPARM_F64V2/F64V4`, `ELOAD_F64V2/F64V4_TO_XMM`, `backend/cx/emit.cyr`) via a **GP
register-pair transport** (cxvm has no vector regs): SIMD ordinal k → r(16+2k)=lo / r(16+2k+1)=hi;
a 32B f64v4 spans r(16+2k)..+3 — clear of int-args/returns/scratch/ENOTR. Predefined
`CYRIUS_HAS_VAL_SIMD_PARAMS` on cx so `lib/simd.cyr`'s value-form wrappers compile. The
**"f32v4 value-form struct-return SIGSEGV"** was NOT a return-path defect — it was the cx
**forward-call resolver** (`main_cx.cyr` ftype==2) reading a stale table (0xE92000 not
`_fnt_offsets`), using byte units not 4-byte units, and clobbering the call opcode; fixed to mirror
`ECALLTO`. That resolver fix roughly **doubled** cx corpus correctness (49→99/221). Verified
framework-free (exit-code): f32v4/i32v4 16B + f64v4 32B value param+return all match x86; x86
self-host byte-identical; cx-bytecode regression gate added (`programs/checks/cx.cyr`). NOTE the
acceptance's "assert-framework tcyr green on cx" is gated by pre-existing cx `fmt_int`/large-immediate
gaps (filed separately, [`2026-07-11-cx-fmt-int-and-large-immediate-gaps`](2026-07-11-cx-fmt-int-and-large-immediate-gaps.md));
control-flow/exit-codes are correct.

**Filed:** v6.4.32 (cx-SIMD arc — flat-array shipped in .32; this is the deferred tail)
**Pinned to:** a follow-on release after v6.4.32 (user-directed: "flat-array first, then
break value-form into a followup release").
**Severity:** P2 (feature completeness; cx value-form is currently gated OFF so nothing
regresses by leaving it — no correctness hole in shipped code).

## Scope

v6.4.32 ships the **flat-array** cx SIMD surface (the 13 `EMIT_F*V_*` / `EMIT_IVEC_*`
emitters as scalar per-lane bytecode loops, bit-exact vs x86/aarch64). This issue tracks
the **value-form** tail:

- `ESTOREPARM_F64V2` / `ESTOREPARM_F64V4` (cx/emit.cyr:577-578) — currently `return 0` stubs.
  Should store the incoming pair/quad (r0..r1 / r0..r3) into the named param's downward frame
  slots, mirroring the working `EFLSTORE_F64V2_PAIR`/`_F64V4_PAIR` (cx/emit.cyr:523/583).
- `ELOAD_F64V2_TO_XMM` / `ELOAD_F64V4_TO_XMM` (cx/emit.cyr:580-581) — currently `return 0`.
  Should load a source local's 2/4 slots into r0..r1 / r0..r3 before a call (the "TO_XMM" name
  is an x86 inheritance — cx has no vector regs; the target is the GP pair/quad ABI).
- Root-cause the **f32v4 value-form struct-return SIGSEGV on cx** — `f32v4_lane0_ptr(&a)` after
  a `f32v4_make(...)` faults on cx independent of any arithmetic (sid −2121 value-return does not
  line up with the stubbed marshaling). This is why value-form is high-risk + separable.
- Then define `CYRIUS_HAS_VAL_SIMD_PARAMS` for the cx target (`main_cx.cyr`) so `lib/simd.cyr`'s
  value-form wrappers compile, and flip the value-form asserts on for cx.

## Why deferred (not a silent subset)

cx currently does NOT define `CYRIUS_HAS_VAL_SIMD_PARAMS`, so `lib/simd.cyr`'s value-form
wrappers are `#ifdef`-excluded on cx and every value-form assert is already skipped there.
Shipping flat-array-only in .32 therefore regresses nothing and hides nothing — the value-form
path was never enabled on cx. This is a genuine planned split at arc-open, user-signed-off.

## Acceptance

- `simd_f32v4.tcyr` + `simd_ints.tcyr` **value-form** asserts pass in cxvm (compile+run via
  `cycc_cx` → `.cyx` → `cyrius run`), matching x86/aarch64 results.
- cx self-host fixpoint + seed-derive stay byte-identical; cross-OS cx round-trip on cass/ecb/pi.
- Possibly a two-step-bootstrap layout change if the value-param frame layout shifts (watch for it).
