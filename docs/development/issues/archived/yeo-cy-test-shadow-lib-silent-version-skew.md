# Shadow-`lib/` note doesn't report version skew — silently hid a crypto fix for 3 minor versions

**Status:** ✅ **RESOLVED v6.4.63** (2026-07-14). All three ranked fixes shipped, in `cbt/` (the CLI
wrapper), not cycc — see below for why, and for two corrections to this filing.

- **Fix #1 (name the drift): DONE.** `cyrius build` now prints `warning: ./lib/ shadows
  version-pinned <snap> — N bundled lib(s) differ:` followed by `sigil 3.9.8 (pinned: 3.11.1), …`
  and `run \`cyrius lib sync --full\` to re-sync`.
- **Fix #2 (escalate severity): DONE.** It is a `warning:`, not a `note:`.
- **Fix #3 (fail the build / CI flag): DONE.** New `cyrius build --check-lib-sync` → `error:` + exit 1.

**Correction 1 — the mechanism guess was wrong, and the filing was right about severity.** The check
does NOT compare paths. `_check_shadow_lib` (src/frontend/lex.cyr:361-441) byte-SIZE-compares ONE
hardcoded sentinel, `lib/alloc.cyr`, against the snapshot's. So the note fired for you only because
your 3-minor-stale `alloc.cyr` ALSO differed. Your ranked order was correct for the bug you filed.

**Correction 2 — a SECOND, worse defect existed, which you did not hit.** If `alloc.cyr` had matched
byte-for-byte while sigil was stale, the sentinel would have returned silently and you would have
gotten **no note at all** — total silence with the slot-0 crypto config in place. Reproduced by
forging exactly that state. The new check ignores the sentinel entirely, so both defects are closed
on the `cyrius build` path.

**Why `cbt/` and not cycc.** The wrapper already has cross-platform `dir_list` + `file_read_all`
(per-OS `#ifdef`s inside the lib files), so the check costs no new syscall surface AND works on
macOS/Windows — where cycc's note **does not exist at all** (its `#ifdef CYRIUS_TARGET_LINUX` keys on
the compiler's HOST os, not the emit target). Verified on real Linux + macOS-arm64 + Intel-Mac +
Windows. Note there is no runtime name→version map to reuse: sigil et al. are FOLDED (vendored into
`lib/` and removed from `[deps]`), so the `# Version:` header is the only source of truth — and
sakshi uses a different one (`# Bundled distribution of sakshi v2.4.6`), which is handled.

Gate: `tests/lib_freshness.sh` (check.sh 147). Follow-up filed to converge/retire cycc's now-redundant
sentinel note: `2026-07-14-converge-cycc-shadow-lib-sentinel.md`.

**Original filing follows.**

---

**Discovered:** 2026-07-14 while porting SecureYeoman's `auth` module in `yeo-cy-test`
**Severity:** Medium (diagnostics/DX gap; the *consequence* here was a latent crypto-scratch race)
**Affects:** cycc 6.4.62 (and every version emitting the shadow-lib note)

## Summary

A stale project-local `lib/` silently shadows the version-pinned snapshot. Cyrius *does*
notice and emits:

```
note: cwd ./lib/ shadows version-pinned /home/macro/.cyrius/versions/6.4.62/lib/ —
delete ./lib/ to use the version-matched snapshot, or set CYRIUS_NO_WARN_SHADOW_LIB=1
```

but the note (a) is severity *note*, and (b) **says nothing about what actually differs**.
So a consumer cannot tell whether `./lib/` is identical to the snapshot or three minor
versions behind it. In `yeo-cy-test` it was the latter, and the skew was in *crypto*:

- `lib/sigil.cyr` in the project: **sigil 3.9.8**
- what the pinned cyrius 6.4.62 folds: **sigil 3.11.1**

sigil 3.9.8 predates sigil **3.9.9**'s `_SIGIL_CBANK_SLOT` 0→8 fix. That fix exists
*because of this same consumer*: sigil's own crypto_scratch.cyr comment names
"SecureYeoman's yeo-cy-test" as the reporting project. With the stale lib, sigil's
crypto-bank thread-local slot sat at **0** while the project's `lib/patra.cyr` declares
`enum SqlTls { TLS_TOKS = 0; TLS_PR = 1; TLS_NTOKS = 2; }` — **both on slot 0**, which is
exactly the documented corruption condition (a patra query clobbers sigil's pinned bank →
a later `cbank()` reads patra's scratch pointer as the lane index → indexes the wrong lane
of the process-global banked crypto buffers → corrupts an in-flight TLS handshake's key
schedule → `RECORD_LAYER_FAILURE`).

**This was latent, not observed** — the project's full suite (8 unit + 46 backend + 13 UI,
including 60 concurrent HTTPS POSTs) passed throughout, and sigil reports the failure as
layout-dependent ("every 4th handshake fails under a specific worker layout"). So the
report here is: *the toolchain let a consumer ship a known-bad crypto configuration with
no actionable signal*, not "cyrius corrupted my handshakes".

The consumer had even written the discrepancy down — a prior finding recorded "the bundled
sigil is 3.9.8, not 3.9.9" — and mis-filed it as a stale documentation label rather than a
stale `lib/`. A note that named the skew would have made that impossible to misread.

## Reproduction

In any project whose `cyrius.cyml` pins a cyrius version, with a `lib/` resolved by an
older toolchain still present:

```sh
# what the project compiles against
grep -m1 '^# Version:' lib/sigil.cyr
# -> # Version: 3.9.8
grep -m1 '^var _SIGIL_CBANK_SLOT' lib/sigil.cyr
# -> var _SIGIL_CBANK_SLOT = 0;

# what the pinned toolchain actually folds
grep -m1 '^# Version:' ~/.cyrius/versions/6.4.62/lib/sigil.cyr
# -> # Version: 3.11.1
grep -m1 '^var _SIGIL_CBANK_SLOT' ~/.cyrius/versions/6.4.62/lib/sigil.cyr
# -> var _SIGIL_CBANK_SLOT = 8;

cyrius build src/main.cyr build/app
# -> note: cwd ./lib/ shadows version-pinned .../6.4.62/lib/ — delete ./lib/ ...
#    (no indication that the shadowed sigil is 3 minor versions behind)
```

Expected: the note tells me *what* is skewed and by how much.
Actual: the note tells me a shadow exists, which is true of every project using `lib/`,
so it reads as routine noise.

Fix on the consumer side: `cyrius lib sync --full` → sigil 3.11.1, slot 8, clear of
patra's 0-4. Suite re-verified green.

## Root cause (speculation — flag for verification)

The shadow check appears to compare *paths* (does `./lib/` exist and take precedence?) and
not *contents/versions*. Nothing reads the bundle version headers to compare them, so the
note is emitted identically whether `./lib/` is byte-identical to the snapshot or years
stale. I have not read the cycc source for this — treat the mechanism as speculation; the
observable behaviour above is verified.

## Proposed fix

Ranked, smallest first:

1. **Make the note report the skew.** When `./lib/` shadows the pinned snapshot, diff the
   bundle version headers and name the drift:
   ```
   note: ./lib/ shadows version-pinned .../6.4.62/lib/ — 3 file(s) differ:
         sigil 3.9.8 (pinned: 3.11.1), patra 1.12.4 (pinned: 1.12.10)
         run `cyrius lib sync --full` to re-sync
   ```
   This alone would have prevented this issue entirely, and it costs one header read per
   shadowed file.
2. **Escalate severity when the skew is non-trivial.** A byte-identical `./lib/` is
   genuinely a note. A `./lib/` carrying an older *version* of a bundled lib is a
   **warning** — the consumer is not building what their pin says they are.
3. **Consider `cyrius deps` / `cyrius build` verifying freshness** (or offering
   `--check-lib-sync` for CI), so a stale `lib/` fails the build rather than whispering.

## Why this matters beyond DX

`lib/` is gitignored and regenerated, so it is invisible to code review and to the lockfile
— the pin in `cyrius.cyml` is the *only* thing a reader sees, and it was wrong here. When
the shadowed bundle is the crypto library, a silent multi-version skew can withhold a
security fix (as it did) with no signal a consumer would act on. The sovereign-stack
promise ("your pin is what you get") depends on this being loud.

## Consumer

`yeo-cy-test` (SecureYeoman → Cyrius port probe). Working around it today by running
`cyrius lib sync --full` and now asserting the resolved sigil version in the project's
state docs.
