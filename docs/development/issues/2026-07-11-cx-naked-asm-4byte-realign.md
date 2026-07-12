# cx: naked-asm functions can misalign the 4-byte code stream (same class as the v6.4.54 DCE-stub bug)

**Filed:** 2026-07-11 (during v6.4.54; identified while root-causing the DCE-stub misalignment).
**Severity:** P3 (latent — no consumer currently reaches a naked-asm fn on cx).
**Backend:** cx (cyrius-x bytecode) only.

## Root invariant

cx bytecode is **strictly 4-byte fixed instructions**, and cxvm computes every call/jump target
as `off*4` (`backend/cx/emit.cyr:366` `ECALLTO off=(target-cp)/4`). Any raw byte emit (`EB`) that
inserts a non-multiple-of-4 number of bytes shifts every following function off 4-byte alignment,
so a later call `(target-cp)/4` truncates and lands mid-instruction (v6.4.54 fixed one instance:
the 3-byte `xor eax,eax; ret` DCE stub in `main_cx.cyr`).

## The remaining violation

`lib/fdlopen.cyr:218/270` — the `#naked` fns `dl_setjmp` / `dl_longjmp` emit a raw 3-byte
`asm{0x31; 0xC0; 0xC3;}` block. `parse.cyr:1034` gates the asm-block 4-byte re-alignment padding
to **`_AARCH64_BACKEND==1` only**, so on cx the 3 bytes are emitted un-padded → same misalignment
class as the DCE stub.

**Not currently reachable:** in normal programs those naked fns are themselves DCE-dead, so they
route through the (now-fixed) `main_cx.cyr` DCE-stub path and emit no raw bytes (post-v6.4.54
repros have 0 `31 c0 c3` sequences). A cx program that actually *reaches* a naked-asm fn (e.g. a
cx `dlopen` consumer) would misalign.

## Fix options

- Extend the `parse.cyr:1034` re-align-padding guard to `|| _TARGET_CX==1` (pad naked-asm blocks
  to a 4-byte boundary on cx), **and/or**
- Add a general assertion in the cx `EB` path that the code offset stays a multiple of 4 (fail
  loud on any future non-4-aligned raw emit — a structural guard for the whole invariant).

## Acceptance

- A cx program that reaches a naked-asm fn keeps the code stream 4-aligned (or fails loud).
- cx self-host byte-identical; x86/aarch64 unaffected.
