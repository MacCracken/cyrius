# yukti udev.cyr `src_len[1]` undersized array-local (4-byte socklen in a 1-slot local)

> **RESOLVED v6.4.27** (2026-07-08, folded-stdlib repair). `~/Repos/yukti/src/udev.cyr:685`
> `var src_len[1]` → `var src_len[4]` (benign — `[1]` rounds to 8B so the 4-byte write already fit —
> but it removes the under-declared-slot idiom). Released as **yukti 2.2.9** + re-vendored into
> `lib/yukti.cyr`.

**Filed:** 2026-07-07 (CHANGELOG-prose deferral sweep — "cosmetic backlog item for yukti's
own timeline" that never got a real issue).
**Severity:** P3 — benign today; the under-declared-slot idiom the v6.3.18 sweep eliminated
repo-wide otherwise.
**Component:** upstream **yukti** (`yukti/src/udev.cyr:685`), vendored into `lib/yukti.cyr:3290`.

## Problem

`var src_len[1]` is used as a 4-byte `socklen_t` out-param. `var x[N]` reserves N **bytes**
(rounded to 8), so `src_len[1]` = 8 bytes and the 4-byte write fits — benign today. But it
is exactly the under-declared-slot idiom the v6.3.18 sweep removed everywhere else; the one
vendored site was reverted to byte-identity with the yukti 2.2.7 dist (per the fix-the-
source-not-the-fold rule) rather than diverging the fold, and filed only in CHANGELOG prose.

## Fix (upstream-first)

Fix in the **yukti source** (`yukti/src/udev.cyr:685`: `var src_len[1]` → `var src_len[4]`),
bump the yukti dist, regen, and re-vendor into `lib/yukti.cyr` — do NOT patch the vendored
fold directly (it evaporates at the next re-vendor). Confirmed still `var src_len[1]` at
`lib/yukti.cyr:3290`, byte-identical to the 2.2.7/2.2.8 dist.

## Acceptance

yukti source uses `src_len[4]`; a new yukti dist is vendored; `lib/yukti.cyr:3290` matches
the corrected dist byte-for-byte. Gated on yukti's release timeline (no cyrius-side blocker).
