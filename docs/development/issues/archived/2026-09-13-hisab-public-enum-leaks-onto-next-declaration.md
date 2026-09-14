# `public enum` leaks its `public` onto the next top-level declaration in a `private` file — FIXED v6.6.4

**Status:** ✅ **FIXED in v6.6.4** — `_TL_VIS` armed the marker unconditionally and only a fn /
global-var definition consumed it; a struct / union / enum / impl / `use` never did, so the
marker outlived them. `public` now arms only for a token that can carry visibility (a positive
list) and is consumed un-armed otherwise; pass 2's impl / relaxed-ordering paths clear a stale
marker on entry (`public var` before an impl re-exposed its FIRST method). Also closed with it:
`public var a, b = f()` exposed `a` only; derived codecs did not inherit `public`; the shared enum
helper was private to the first deriving file; PARSE_PROG-path globals were never stamped. The
repro is refused; gated by `tests/gates/frontend/public_marker_scoped_to_its_item.sh` (56 rows;
6.6.3 reds 30). ⚠ `public impl` now marks NO method — per-method `public fn` is the form.
**Placement:** unpinned — reproduced identically on **6.6.2 and 6.6.3**, so it predates the 6.6.3
`public struct`/derive work and is not a regression of it.
**Discovered:** 2026-09-13. A generated consumer calling every one of hisab's 457 non-public
top-level items against a fully-`private` bundle was refused on **456** — the one accepted was
`_ad_pow`, the declaration immediately after `public enum AdPowLimit { … }` in `autodiff.cyr`.
**Severity:** High — silent. A file-private fn or var becomes reachable (and callable — the repro
runs it) from any file, with no diagnostic, purely because of what precedes it in the source.

## Summary

```cyrius
private

public enum PubOne { PO_A = 1 }
fn _after_pub_enum() { return 3; }   # reachable from another file — WRONG
fn _second_after() { return 4; }     # refused, as declared
```

Measured matrix on 6.6.3 (each row: a `private` file, one `public` item, then a `_`-named fn, called
from a second file through `cyrius check --with-deps`):

| preceding item | next declaration |
|---|---|
| `public enum` (one-line) | **ACCEPTED (leak)** |
| `public enum` (multi-line body) | **ACCEPTED (leak)** |
| `public enum` (multi-line), next item a `var` | **ACCEPTED (leak)** |
| non-public `enum` (either shape) | refused |
| `public var` | refused |
| `public fn` | refused |
| `#derive(accessors) public struct` | refused |

Only the FIRST declaration after the enum is affected; the one after that is private again. The
6.6.2 column is identical for the bare `public enum` case (a file that also derives a `public
struct` cannot be expressed on 6.6.2, which is the 6.6.3 fix, so the full matrix runs there only).

## Likely cause

Whatever records "the next declaration is public" is armed by the `public` keyword and consumed by
the fn / var / struct paths, but **not by the enum path** — so after an enum it is still armed when
the next declaration is registered. The 6.6.3 `_pp_decl_public` work (the `public ` prefix probe in
`PP_PARSE_STRUCT_DEF`) is in the neighbourhood; the pre-6.6.3 reproduction says the enum path has
been skipping the reset for longer than that.

## Proposed fix

Consume / clear the pending `public` marker on the enum path exactly as on the struct path. Gate: the
repro (must be refused) plus its control (`_second_after` must stay refused) plus a positive control
(`api()` and `PO_A` must stay reachable). Mutation: dropping the clear reddens the first; clearing
before the enum's own visibility is recorded reddens the third.

## Consumer stopgap (what hisab does)

hisab's `scripts/check-public-surface.sh` carries `_ad_pow` as a **known leak** keyed to this
filing: the exactness claim passes at `probes − 1`, and if `_ad_pow` ever comes back refused the
gate FAILS with "upstream fixed it — remove the allowlist entry", so the pinned defect inverts into a
tripwire for its own repair rather than silently going stale.
