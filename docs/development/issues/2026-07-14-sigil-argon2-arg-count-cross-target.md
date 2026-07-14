# sigil 3.12.0 argon2/blake2b: 9–17 args per fn, unverified on aarch64 / PE / Mach-O

**Status:** 🟡 **OPEN** — cross-repo (sigil is the owner; cyrius is the vendor).
**Filed:** 2026-07-14 at the v6.4.63 fold-in. **Severity:** Medium (latent — no caller today).
**Not a v6.4.63 blocker:** the code is inert in cyrius (zero callers), so the release does not
depend on it. This is filed so the gap is not mistaken for "verified".

## The gap

sigil 3.12.0 adds BLAKE2b + Argon2id. Its new fns exceed the register-ABI arg budget:

| fn | args | surface |
|---|---|---|
| `argon2_hash_into` | **17** | public |
| `_argon2_h0` | **14** | internal |
| `argon2id_into` | **10** | public (api-surface) |
| `argon2d` / `argon2i` / `argon2id` | **9** | public (api-surface) |
| `_argon2_fill_segment` | 11 | internal |
| `_blake2b_g`, `_argon2_index_alpha` | 7 | internal |

CLAUDE.md's standing rule: *"**fns take ≤6 args cleanly** (register ABI); args 7+ go on the
stack and **have shown corruption** — restructure instead."* Eight new fns are over that line,
and they are all NEW in 3.12.0 (the vendored 3.11.1 had no argon2/blake2b at all).

## Why it is unverified

- sigil validates argon2 against the **three official RFC 9106 §5 vectors** — real validation,
  but on **x86_64 Linux only** (its `tests/tcyr/argon2.tcyr` + `blake2b.tcyr` run in sigil's own
  suite).
- **cyrius's release gate cannot cover it.** The gate's cross-OS step (ecb/ach/cass/pi) exercises
  cycc's self-host + the VR-01 tcyr corpus. sigil is **outside cycc's transitive closure**, so
  none of that touches argon2. cyrius's only sigil consumers — `cyrsign`, `cyrsign-efi` — use
  authenticode/RSA and never call argon2.
- Net: **argon2 on aarch64 / Win64-PE / Mach-O has never been executed anywhere.** The Win64 ABI
  is the sharpest risk (4 register args then stack + shadow space, vs SysV's 6), and the v6.4.44
  "retptr deep-stack-param homing" bug is precedent for exactly this class.

## Why it matters despite "no caller"

The moment a consumer calls `argon2id` on Windows or ARM — password hashing is the obvious use —
a stack-arg marshaling bug would corrupt a **KDF**, which fails silently-wrong (a wrong hash is
still a hash). This is the same shape as the sigil `_SIGIL_CBANK_SLOT` bug that motivated
`yeo-cy-test-shadow-lib-silent-version-skew`: crypto that is wrong but not loud.

## Done when

Either (preferred, sigil-side):
1. sigil restructures the >6-arg fns to a params-struct/pointer form (the CLAUDE.md remedy), OR
2. sigil's argon2/blake2b tcyr run on **real ecb + cass + pi** and pass the RFC vectors there,
   with the result recorded in sigil's CHANGELOG.

And cyrius-side: once either lands, re-vendor and note the verification status in the fold entry.

## Notes for whoever picks this up

- Do **not** patch `lib/sigil.cyr` — fix at the source repo, version-bump, regen dist (all 14
  profiles), re-vendor. A fold edit evaporates at the next re-vendor.
- `argon2id_into` is the allocator-free arena variant and is the one a concurrent consumer will
  reach for; prioritize it.
- Sizing helpers `argon2_mem_bytes/2` / `argon2_mem_blocks/2` are ≤6 args and not at risk.
