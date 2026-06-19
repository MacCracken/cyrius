# Ecosystem-stdlib daimon-class fixes — patched in source, held for release + re-fold

> **✅ RESOLVED — ready to archive (`git mv` → `issues/archived/`).** The
> maintainable-lib half is done (sigil 3.9.0 `i64[4]` cert slots + sakshi 2.4.0
> `var ts[16]`, both absorbed @ .24); the agnosys part is moot (frozen 1.4.3,
> upstream repo decomposed → agnodrm, being retired). Nothing left to track.

> **MOSTLY RESOLVED (verified at v6.2.24) — sigil + sakshi absorbed; agnosys
> frozen.** The held source patches landed via the v6.2.23/.24 fold refreshes:
> **sigil 3.9.0** has the `i64[4]` cert-pointer slots in `sgx_quote_verify_full_into`/
> `snp_report_verify_full_into`/`tdx_quote_verify_full_into` (old byte-array form
> gone); **sakshi 2.4.0** uses `var ts[16]` (16-byte two-i64 form, the OOB `ts[2]`
> gone). **agnosys** stays at the frozen 1.4.3 fold (upstream repo decomposed →
> agnodrm; can't be re-folded) — its part is moot as agnosys is being retired.
> Kept OPEN only to track the agnosys retirement; the maintainable-lib half is done.

**Filed:** 2026-06-12 · **Parent:** v6.2.1 element-typed-array / addr-taken-local
slot-idiom fix ([`2026-06-11-addr-taken-local-array-static-underreserve.md`](2026-06-11-addr-taken-local-array-static-underreserve.md))
**Status:** HELD FOR RELEASE — source patches applied in each lib's repo; awaiting
each lib's release, then re-fold into cyrius `lib/`.

## What this is

The v6.2.1 daimon-class audit found address-taken local slot-arrays written past
their byte capacity in three **ecosystem stdlibs** (sigil / sakshi / agnosys).
These are the language's own stdlibs vendored into cyrius `lib/<name>.cyr` via the
fold/regen flow (`# Do not edit` headers). Per discipline the fix goes in the lib's
**source repo**, not the vendored copy. The source patches are applied; they are
**held for release** (the user drives the lib releases), then re-folded into cyrius.

## Source patches applied (this session)

| Lib · repo | File · fn | Was | Now |
|---|---|---|---|
| sigil 3.7.12 | `src/sgx.cyr` `sgx_quote_verify_full_into` | `parsed[4]`, `inters[4]` | `i64[4]` |
| sigil | `src/sev_snp.cyr` `snp_report_verify_full_into` | `parsed[4]`, `inters[4]` | `i64[4]` |
| sigil | `src/tdx.cyr` `tdx_quote_verify_full_into` | `parsed[4]`, `inters[4]` | `i64[4]` |
| sakshi 2.2.10 | `src/clock.cyr` `_sk_clock_now_ns_raw` | `ts[2]` | `i64[2]` |
| agnosys 1.4.1 | `src/update.cyr` `update_save_state` | `bc_buf[8]` | `bc_buf[24]` |

Each is a 4-cert-pointer / 2-i64-timespec slot array (`store64(&x + i*8)`, the
sigil ones also `memset(&x, 0, 32)` — already a 24-byte OOB into the 8-byte
buffer) or, for agnosys, an i64-decimal ASCII scratch (`fmt_int_buf`, up to 20
digits). All "work by luck" today (latent until layout shift) — same class as the
daimon route-404.

Note: the cyrius-side audit (run on the **vendored fold**) flagged only 5 sigil
sites; checking the **source** caught snp's `parsed[4]` too. Always audit the
source repo, not the fold.

## Release + re-fold checklist (per lib)

1. `sigil` / `sakshi` now use `i64[N]` → bump each `cyrius.cyml` pin to **≥ 6.2.1**
   (the spelling needs the v6.2.1 cycc). agnosys `bc_buf[24]` is a plain byte-bump —
   no pin change required.
2. Run each lib's `regen-dist` + test suite + bench; bump the lib version; release.
3. Re-fold the released dist into cyrius `lib/<name>.cyr` (a follow-on cyrius patch,
   e.g. v6.2.2). Until then cyrius ships the prior (latent-buggy) folds — no
   regression vs 6.2.0, but the fix isn't in the vendored copy yet.

## Why held, not folded into 6.2.1

v6.2.1 introduces the `i64[N]` spelling the sigil/sakshi fixes depend on, so those
libs can't compile their fix until 6.2.1 exists. Patch source now, release the libs
against 6.2.1, re-fold after. (agnosys could fold sooner — byte-bump only.)
