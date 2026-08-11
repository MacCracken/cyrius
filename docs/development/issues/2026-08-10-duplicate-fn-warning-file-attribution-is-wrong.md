# `duplicate fn` warnings report a file:line that cannot be in that file

**Status:** 🔴 OPEN — filed from a consumer (agnosai).
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
