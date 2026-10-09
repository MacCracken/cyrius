# yantra: nine test files include `src/web.cyr` / `src/mobile.cyr` without `src/security.cyr` (undefined-function warnings) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b and yantra 1.0.9 (`f12b9eb`, the folded
tag): each of the nine files below, compiled from a scratch `git archive` copy with cyrius's `lib/` and
`lib/assert.cyr` prepended (as the manifest does), builds rc 0 with `warning: undefined function
'yantra_tls_pin_verify_ed25519'` and `… 'yantra_tls_pin_verify_hybrid'`. The roadmap named only the Android / iOS
e2e files; the set is wider.
**Placement:** yantra's next patch release, then re-vendored (`cyrius distlib` at the tag — yantra's `dist/` is
untracked) — never 7.x.
**Discovered:** the 6.7.6 fold wave (W2, yantra 1.0.9 — the Android / iOS E2E runs, "results unaffected, 4/4
each"); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a warning in test builds; the pin-verify fns are unreachable from the tests, so results are
unaffected — but a standing warning of the same shape as a real one trains readers to skip it.
**Affects:** yantra ≤ 1.0.9 test sources (`tests/`); `lib/yantra.cyr` itself is unaffected — `[lib] modules` lists
`src/security.cyr` before `src/web.cyr` / `src/mobile.cyr`.

## Summary

`src/web.cyr:52, 59` and `src/mobile.cyr:38, 45` call `yantra_tls_pin_verify_ed25519` / `_hybrid`, defined in
`src/security.cyr:28, 39`. Tests that include the source modules one by one include `web.cyr` and `mobile.cyr` but not
`security.cyr`: `tests/e2e/{android-appium,ios-appium,chromium,firefox,webdriver,webkit}-smoke.tcyr`, `tests/m5.tcyr`,
`tests/cdp_close_once.tcyr`, `tests/open_retry_backoff.tcyr`. `tests/m8.tcyr` and `tests/cdp_http_short_send.tcyr`
include it and are clean.

## Reproduction

```sh
T=$(mktemp -d); cd ~/Repos/yantra && git archive 1.0.9 | tar -x -C "$T" && cp -r /home/macro/Repos/cyrius/lib "$T/lib"
cd "$T"; for t in tests/e2e/android-appium-smoke.tcyr tests/m5.tcyr tests/m8.tcyr; do
  { echo 'include "lib/assert.cyr"'; cat "$t"; } | CYRIUS_NO_WARN_PIN_DRIFT=1 /home/macro/Repos/cyrius/build/cycc > /dev/null 2> err
  echo "$t rc=$? $(grep -c "undefined function 'yantra_tls_pin" err)"; done
# tests/e2e/android-appium-smoke.tcyr rc=0 2
# tests/m5.tcyr rc=0 2
# tests/m8.tcyr rc=0 0
```

Expected: no undefined-function warning. Actual: two per affected file.

## Root cause

The test files' hand-written include lists predate (or missed) the `security.cyr` module that `web.cyr` /
`mobile.cyr` came to depend on.

## Proposed fix

In yantra's source repo: add `include "src/security.cyr"` after `src/runtime.cyr` (the `[lib] modules` order) in the
nine files; release a yantra patch; re-vendor `lib/yantra.cyr` with `cyrius distlib` at the tag (byte-compare the
fold) and update the `docs/ecosystem.md` row. Optionally a yantra CI check that a test build carries no
`undefined function` warning.
