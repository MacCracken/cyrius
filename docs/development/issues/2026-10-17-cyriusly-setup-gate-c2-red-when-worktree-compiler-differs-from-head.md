# cyriusly_setup_bootstrap_and_env.sh C2 is red whenever the working tree's build/cycc differs from the committed one — its reference cyrfmt is built by `$CC`, the installed one by the `git archive HEAD` copy's compiler — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b; the lane gate's
`sh scripts/check.sh`, CYRIUS_CHECK_JOBS=4). Red in every lane check run since the lane's first codegen change
(735fb3c7, F3), green before it; the lane rule is that build/ is never committed (integration rebuilds build/cycc once),
so the gate is red in any lane whose compiler emits different code. Met by the 6.7.14 frontend lane gate.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a gate defect only: at a release (build/cycc committed, == the tree's fixpoint) the two compilers
are the same and the row is right. In a lane, or for anyone testing a rebuilt but uncommitted compiler, the row is a
false red that has to be explained away each time.

## Reproduction

```sh
cd <a tree whose build/cycc is the fixpoint of src/ but not committed, e.g. the frontend lane>
sh tests/gates/toolchain/cyriusly_setup_bootstrap_and_env.sh | grep -E 'C2|^(PASS|FAIL)'
#   FAIL: C2 the installed bin/cyrfmt is the default build, byte for byte — expected [identical], got [differs]
# FAIL: cyriusly_setup_bootstrap_and_env — 1 of 10 checks failed
git show HEAD:build/cycc > /tmp/head_cycc && chmod +x /tmp/head_cycc
CYCC=/tmp/head_cycc sh tests/gates/toolchain/cyriusly_setup_bootstrap_and_env.sh | grep -E 'C2|^(PASS|FAIL)'
#   ok: C2 the installed bin/cyrfmt is the default build, byte for byte (identical)
# PASS: cyriusly_setup_bootstrap_and_env — 10 checks
```

## Root cause

Section C builds the reference `"$T/cyrfmt.plain"` with `"$CC"` (the working tree's build/cycc, or `CYCC`), but
`cyriusly setup` runs in `co "$T/c"` — a `git archive HEAD` copy, whose build/cycc is the COMMITTED compiler — and
builds the installed bin/cyrfmt with that. The row means "CYRIUS_BOUNDS=1 did not leak into the tool build"; it also
silently asserts "the working tree's build/cycc is the committed one".

## Proposed fix

Build C0's two references with the compiler setup will use: `"$T/c/build/cycc"` (after `co "$T/c"`), so C2 compares
like with like whatever the working tree holds. The mutation row MC (the `unset` dropped: C2 RED) still applies.
Rows: the gate green with an uncommitted rebuilt build/cycc (the repro's first command), and with the committed one.
