# `#derive(Serialize)`'s generated `<Name>_from_json_str` dereferences a null `json`, and returns a zero-filled struct as success on any malformed input

**Status:** ✅ **RESOLVED — shipped v6.5.37.** Both halves: the emitted body returns 0 for a null `json` (was exit 139 SIGSEGV) and returns 0 when no `{` is found (was a non-null zeroed struct). Gate: `tests/tcyr/derive/derive_from_json_str_guards.tcyr`. ⚠ This filing's OTHER claim — that `cyrius test` scores such a crash as `1 passed, 0 failed` — is FALSE at 6.5.36: measured, a segfaulting .tcyr gives exit 139 and the suite exit 1. Reading `$?` through a pipe is the likeliest source. The real defect there was SILENCE (a crashed test counted but never NAMED), fixed separately at v6.5.37.
**Placement:** `src/frontend/lex_pp.cyr` — the `Name_from_json_str` emitter (`:1719`).
One added guard closes the crash; the zero-struct half needs a decision.
**Discovered:** 2026-08-31, during prani's roadmap 2.0.5 input-range survey.
**Severity:** **High** for the null deref — SIGSEGV on a code path every deserializer
consumer has, reachable from any caller that passes an unvalidated pointer.
**Medium** for the zero-struct-as-success half — silent wrong data, not memory unsafety.
**Affects:** cycc **6.5.36** and every release since the derive gained `from_json_str`.

## Summary — two defects, one emitter

The generated body opens like this (`src/frontend/lex_pp.cyr:1719-1729`):

```
fn Name_from_json_str(json) {
    var ptr = alloc(N);
    memset(ptr, 0, N);
    var _p = 0; ...
    while (load8(json + _p) != 0) { if (load8(json + _p) == 123) { _p = _p + 1; break; } _p = _p + 1; }
    ...
    return ptr;
}
```

**1. Null deref.** `json == 0` makes the first statement `load8(0)`. There is no guard.

**2. Malformed input is indistinguishable from success.** `memset(ptr, 0, N)` runs first, the
scan then matches nothing, and the zeroed struct is returned as a valid pointer. A caller
cannot tell `"{garbage"` from a real document.

## Reproducer

Verified on cycc 6.5.36, x86_64 Linux, against prani's `PrRng` (`#derive(Serialize)` over
two i64 fields). Built and run as a binary — **`cyrius test` masks this**, because the
runner reports a pass when the child dies of SIGSEGV:

```
include "src/error.cyr"
include "src/rng.cyr"
fn main() {
    alloc_init();
    var r = PrRng_from_json_str(0);
    if (prani_is_err(r) == 1) { return 2; }
    return 3;
}
```

```
$ ./nullprobe
$ echo $?
139          # SIGSEGV. Expected 2 (error) or a checkable 0.
```

The second defect, same type: `PrRng_from_json_str("not json at all")` returns a **non-null**
pointer with `state == 0` and `inc == 0`, and `prani_is_err` is 0.

## Why a consumer cannot work around it

The body is emitted, not written, so there is nothing to edit. A project can only:

- hand-write every codec and drop the derive — which is what prani did for its four
  hand-written deserializers, and precisely the duplication the derive exists to remove; or
- wrap each generated function — which does not remove the unguarded original from the
  distlib bundle, where it stays part of the public surface.

prani hit this with **five** generated codecs at once (`PrEmotion`, `PrEmotionOut`,
`FatigueState`, `PrRng`, `CallBout`). Its four *hand-written* deserializers all carry
`if (json == 0) { return PRANI_ERR_*; }` — added deliberately in its
[ADR-0002](https://github.com/MacCracken/prani/blob/main/docs/adr/0002-deserializers-report-parse-failure.md),
which repaired exactly this defect class after a malformed document was found producing a
fully-formed struct with every field zero. The generated codecs were never covered by that
ADR **because they are generated**, so the same repair could not reach them.

## Proposed fix

**The null guard is unambiguous.** Emit, before the `alloc`:

```
if (json == 0) { return 0; }
```

0 is already the convention for a failed `alloc`, so callers that check the return at all
are unaffected, and no currently-working call changes behaviour — the only inputs that
reach it today crash.

**The zero-struct half needs a decision**, because it changes a return value consumers may
depend on. Options, in the order I'd rank them:

1. **Return 0 when no `{` is found.** Cheap — the skip-to-`{` loop already knows it ran to
   the terminator. Catches `"garbage"`, `""` and truncation. Does not catch a well-formed
   document with the wrong keys, which is fine: that is a schema question, not a parse one.
2. **Return 0 only when zero fields matched.** Stricter, but wrong for a legitimately
   all-default document, and it would break round-tripping a zeroed struct.
3. **Leave it and document it.** Every consumer then repeats prani's ADR-0002 by hand.

Option 1 restores the same contract prani's hand-written codecs already have, and makes
`#derive(Serialize)` safe to use on untrusted input — which is the only reason to have a
`from_json_str` rather than a `from_json` that takes an already-parsed node.

## Note on test visibility

`cyrius test` reported **`1 passed, 0 failed`** for a `.tcyr` whose process died of SIGSEGV
mid-run. That is arguably a separate issue and a serious one — a crashing test is currently
indistinguishable from a passing one — but it is why this defect survived prani's 2.0.3
P(-1) sweep and its 2.0.4 parity audit, both of which exercised these codecs.
