# `duplicate fn` warnings report a file:line that cannot be in that file

**Status:** ✅ **RESOLVED — v6.5.19.** Expected outcomes 1 AND 2 both shipped.

⚠ **The filed mechanism was not the real one, and it matters.** The FILE was correct in all 35
cases; only the LINE was wrong (35 of 35). A fix built on "the filename is whichever file the
mapping last resolved to" would have fixed the wrong thing. `FM_LOOKUP` reconstructs a source
line by linear arithmetic over a `#@file` span (`expanded − start + base`), which holds only
while the preprocessor copies a file 1:1 — and two transforms broke that INSIDE a span with no
re-anchor: the `#ifdef` family consumed directive lines and dropped skipped bodies (line too
SMALL; kavach's 30 warnings were uniformly `true − 55`) and `#derive` replaced 2–3 source lines
with N generated ones (too LARGE; +476 by line 11112, which is how `:11588` landed 267 past
EOF). Fixed in `src/frontend/lex_pp.cyr`: the `#ifdef` family now PADS one newline per consumed
or skipped source line, and `#derive` — which adds lines and cannot be padded — RE-ANCHORS with
a `#@file` marker. A marker per `#ifdef` block would have needed ~1139 entries against a 1024
cap, and overflow makes `FM_FILEID` return `-1`, which `private` visibility is load-bearing on.

Expected outcome 2 also shipped: the message is now
`duplicate fn 'X' (last definition wins; first defined in <file>)`, and the caret moved off the
`(` onto the `fn` keyword (`_err_head_at(S, _defstart_ti)`).

**§6 of this filing is answered: `last definition wins` is honest.** On the exact `_sub_new`
shape the warning names `lib/libro.cyr:6` (`grep -n` agrees), names majra as the first
definition, and a runtime probe returns libro's value. Whatever the original probe showed, it
is not explained by this defect.

⚠ **One measured residual, filed:** a fn the derive SYNTHESIZES (`SpawnedProcess_pid` /
`_set_pid` — 2 of the 35) has no source `fn` line at all, so no marker can make it exact. It
now lands in the generated block a few lines past its struct instead of drifting across the
file. Two candidate repairs were implemented, measured WORSE, and reverted (both shift the
struct's own lines, moving a diagnostic inside the struct from +1 to +2). Closing it is a
design decision about generated-code layout with 34 derive tests downstream:
`docs/development/issues/2026-08-11-derive-generated-code-inflates-line-numbering.md`.

**NOT done, deliberately — the "adjacent" suggestion.** Promoting an arity-differing duplicate
from warning to error is a behaviour change that can break existing builds; it is the
maintainer's call, not a bug fix, and is left unpinned.

Gate: `tests/gates/frontend/duplicate_fn_attribution.sh` (both halves mutation-proven
independently). See CHANGELOG [Unreleased].

**Status (as filed):** 🔴 OPEN — filed from a consumer (agnosai).
**Discovered:** 2026-08-10, v6.5.18, auditing 35 duplicate-fn warnings across seven bundles.
**Severity:** Medium. It is a diagnostic, but it is the diagnostic a consumer uses to decide
whether a collision matters, and it led directly to two wrong conclusions that had to be
retracted.

## The defect

```
warning:lib/kavach.cyr:11512:26: duplicate fn 'SpawnedProcess_set_pid' (last definition wins)
warning:lib/kavach.cyr:11588:26: duplicate fn 'attestation_result_new' (last definition wins)
```

`lib/kavach.cyr` is **11,321 lines long**. Lines 11,512 and 11,588 do not exist in it. The
offsets are evidently into the preprocessed stream and the filename is whichever file the
mapping last resolved to, so both the line and the file are wrong for these entries.

`grep -n 'fn attestation_result_new' lib/kavach.cyr` finds it at **11112**.

## Why it matters beyond tidiness

A consumer linking several bundles gets a list of collisions and has to decide, per symbol,
which copy wins — because for anything with differing bodies, that decision is the
behaviour. The natural reading of `warning:<file>:<line>: duplicate fn 'x'` is "this is the
duplicate, i.e. the later definition, so this one wins". With the attribution wrong, that
reading produces a confident and incorrect answer.

Concretely: `_sub_new` is defined by both majra and libro with different arity, size and
field layout. The warning points at `lib/libro.cyr`, which reads as "libro's wins". It does
not — a runtime probe shows **majra's** body runs. Two upstream issues were filed on the
wrong reading and had to be corrected.

## Expected

Either:

1. **Report the true source location of the later definition** — file and line as they
   appear in the file a user can open, which is what every other cyrius diagnostic does.
2. If the mapping is genuinely unavailable at that point, **report both definitions**
   (`first defined at A, redefined at B; B wins`) so the answer does not have to be inferred
   from a single position at all. This is strictly more useful even when the attribution is
   correct.

Option 2 would have made all 35 of these self-explanatory.

## Adjacent, and arguably the more valuable fix

A duplicate whose **arity differs** is never intentional — `_sub_new(chan, filter_fn)`
against `_sub_new(pattern)` cannot be a deliberate override. Promoting that specific case
from warning to error would have caught this class at the point of linking rather than
leaving it to a consumer's audit. The same is true of a duplicate between two *declared*
dependencies, as opposed to a consumer deliberately overriding a stdlib symbol.

## Repro

Any build linking two bundles that define the same symbol; agnosai's is
`cyrius build src/main.cyr build/agnosai 2>&1 | grep duplicate`, which emits 35. Compare any
reported line number against `wc -l` of the named file.
