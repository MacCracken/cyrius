# A typed-array global leaves every later global misaligned — atomics on them SIGBUS on aarch64 — 🔴 OPEN

**Status:** 🔴 **OPEN** — found by agnostic 0.1.7 on real hardware; not repaired. No consumer-side
work-around is sane (see the end).
**Placement:** **6.6.13**, bite I9 (2026-10-01, with the other open issues) — see `roadmap.md` § 6.6.13. A
global-layout fix: it rides in the `src` lane with M1–M3.
**Discovered:** 2026-10-01, agnostic 0.1.7 — its aarch64 release binary dies with SIGBUS at startup on
a Raspberry Pi 4, and 12 of its 27 suites die the same way. agnostic 0.1.6 (cyrius 6.6.11) is
identical, so this predates 6.6.12; agnostic recorded it as "SIGBUS under qemu, needs real hardware"
from 0.1.3 on.
**Severity:** High on aarch64 — every program whose compile unit holds a typed-array global of a size
not divisible by 8 has misaligned 64-bit globals after it, and the first atomic on one of them kills
the process. sigil's crypto init flags are among them, so anything that hashes is affected. Silent on
x86_64, which tolerates a misaligned `lock cmpxchg` (but a split lock can still be fatal under
`split_lock_detect=fatal`).
**Affects:** cyrius 6.6.12 global data layout (both backends lay globals out the same way; only
aarch64 faults). Folded modules that trip it today: `lib/sankoch.cyr` (`_brd_tr: u8[363]`,
`_brd_affix: u8[217]`, `_brd_affix_hex: u8[50]` — 630 bytes, ≡ 6 mod 8).
**Repro:** [`repros/typed-array-global-misaligns-next.cyr`](repros/typed-array-global-misaligns-next.cyr).

## Summary

`var a: u8[N]` reserves exactly `N` bytes, as the guide documents. The global declared after it is
placed at `&a + N` with no padding, so for `N % 8 != 0` it is not 8-aligned — nor is any 64-bit global
after it until some other odd-sized object happens to shift the offset back. On aarch64 an `atomic_cas`
(`ldaxr`/`stlxr`) or `atomic_load` / `atomic_store` (`ldar`/`stlr`) on such a global raises an
alignment fault; the Pi 4's Cortex-A72 (ARMv8.0, no LSE2) does not relax that.

## Measured

The repro (cyrius 6.6.12; `fmt_int` of `&_tr - &_head`, `&_lock - &_tr`, `&_lock % 8`, then the CAS):

| target | `var _tr: u8[363]` | output | exit |
|---|---|---|---|
| x86_64 | typed | `8 363 3 1` | 0 — misaligned, CAS succeeds |
| aarch64 (Pi 4, native) | typed | `8 363 3 ` | **135 — SIGBUS in `ldaxr`** |
| aarch64 (Pi 4, native) | bare `var _tr[363]` (363 slots) | `8 2904 0 1` | 0 |

In agnostic's real binary (every scalar global's address printed by a generated probe, run on the Pi):
**1,101 of 1,962 globals are misaligned**, starting right after sankoch's three `u8` arrays. Twelve of
them are used with atomics: sigil's `_crypto_tls_inited`, `_crypto_next_bank`, `_sigil_slot_gate`,
`_sha_ni_probe_lock`, `_aes_inited`, `_aes_ni_probe_lock`, `_sha512_inited`, `_blake2b_inited`,
`_ed_p_inited`, `_ed25519_inited`, `_mldsa_ntt_inited`, and majra's `_mq_next_job_id`. The first fault
in agnostic's crypto suite (gdb on the Pi): `ldaxr x4, [x0]` with `x0 = 0xa200f6`, in `atomic_cas`
called from `sha_ni_available` — `&_sha_ni_probe_lock`.

## Suggested fix (for the maintainer to choose)

1. **Align every global to 8** (or to its natural alignment, at least 8 for word-sized data) — pad after
   an odd-sized typed array, exactly as the bare `var a[N]` form never needed to. A `u8[N]` keeps its
   `N` usable bytes; only the gap after it changes.
2. A gate that would have caught it: a crossos row asserting `&g % 8 == 0` for a 64-bit global declared
   after `u8[3]`, `u8[363]`, `i16[3]` and `i32[3]` globals, plus an `atomic_cas` on it, run natively on
   aarch64 (the Pi and the other cross-OS hosts).

Until then, a library can avoid the trap by sizing byte arrays to a multiple of 8 (sankoch:
`u8[368]`, `u8[224]`, `u8[56]`), but that is a convention nothing enforces.

## Why no consumer work-around

The offset comes from a folded module the consumer does not even include itself (agnostic gets sankoch
through agnosai's sidecar), and the victims are a dozen private flags inside another folded module.
Pre-setting them from consumer code would be fragile and would not cover the next one.
