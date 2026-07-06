# DECODE_LEN mis-lengths no-ModRM two-byte (0F) opcodes (syscall / cpuid / rdtsc / ud2 …)

- **Filed**: 2026-07-05 (during SIMD Phase 4 R1; surfaced when adding VEX length-decode)
- **Severity**: P3 (conservative DCE miss; no miscompile, no crash, fail-safe today)
- **File**: `src/backend/x86/decode.cyr` — `DECODE_LEN`, the `if (op == 0x0F)` block

## Symptom

`DECODE_LEN` assumes **every** non-Jcc two-byte (`0F xx`) opcode carries a ModR/M byte
(`decode.cyr:92-95`: it reads the byte after `0F xx` as ModR/M and adds `_MODRM_FOLLOW`).
That is wrong for the `0F` opcodes that have **no ModR/M and no operands**, notably:

- `0F 05` **SYSCALL** (Cyrius emits this constantly — every `syscall(...)`)
- `0F A2` **CPUID** (emitted by `lib/sigil.cyr` AES-NI / SHA-NI probes)
- `0F 31` RDTSC, `0F 0B` UD2, `0F 34/35` SYSENTER/EXIT, `0F 77` EMMS, `0F 09` WBINVD, etc.

For `0F 05`, `DECODE_LEN` reads the *following* instruction's first byte as a ModR/M and
returns a length of ~4 instead of 2, so the byte-walk **mis-aligns** and lands mid-way
into the next instruction.

## Why it's been invisible (fail-safe by accident)

`DECODE_LEN` is used in exactly one place — the DCE dead-function validator
(`src/backend/x86/fixup.cyr:585`), which walks an already-unreachable fn's body and only
NOPs it if every byte decodes AND the walk lands exactly at `fn_end`. When the walk
mis-aligns off a SYSCALL, it usually lands on a byte the decoder can't handle (returns 0)
→ `valid = 0` → **DCE refuses to NOP** the fn. So the bug degrades to "some dead
syscall-containing fns are conservatively kept" — a missed optimization, never a
miscompile. (`CYRIUS_DCE` is opt-in; default is count-only.)

## How it surfaced

SIMD Phase 4 R1 briefly added VEX (`0xC5`) length-decoding to `DECODE_LEN`. Under
`CYRIUS_DCE=1` (the differential "torture" mode), 25 crypto/TLS programs then diverged:
a dead sigil fn contains `... 0F 05 (syscall) ; 49 89 C5 (mov r13,rax) ...`. The
mis-lengthed SYSCALL walk landed on the `0xC5` **ModR/M byte** of `mov r13,rax`; OLD
returned 0 there (→ refuse, accidentally safe), while the VEX decode let the garbage walk
complete and NOP the fn. The `0xC5` was never a VEX instruction — it was a coincidence of
the SYSCALL mis-decode. The VEX-decode change was reverted (it isn't needed: an
undecodable VEX byte already makes DCE refuse, which is the correct fail-safe for a dead
f32v8 wrapper).

## Root cause

The `0F` handler has no table of no-ModR/M `0F` opcodes; it treats everything except
`0F 38/3A` and `0F 8x` (Jcc) as ModR/M-bearing.

## Fix sketch

Add the no-ModR/M `0F` opcodes as fixed-length (2 bytes) cases before the ModR/M
fallthrough: `0F 05, 07, 08, 09, 0B, 30, 31, 32, 33, 34, 35, 77, A2, AA` → `return p - off`.

## Why deferred (not fixed in Phase 4 R1)

- It is **orthogonal** to f32v8 (surfaced by it, not caused by it).
- **Any** change to `DECODE_LEN`'s walk alters which dead fns DCE NOPs → **breaks
  DCE-mode byte-identity** for existing crypto/TLS programs (the same 25 that diverged).
  Fixing SYSCALL is a *correct* change but still non-byte-identical, so it needs its own
  slot with a deliberate re-baseline of the DCE-torture differential, not a silent bundle
  into a SIMD release.
- Impact is a conservative DCE miss, not a correctness bug — no urgency.

Tracked for a dedicated decoder-correctness slot.
