#!/bin/sh
# v6.5.28 — `_distlib_named_deps` must recognise a `[deps.X]` SECTION HEADER only, never the
# same text appearing in comment prose.
#
# THE BUG. The exclude-set scan matched the literal `[deps.` ANYWHERE in the manifest buffer
# with no line anchoring (`cbt/commands.cyr`), so a comment explaining the layout registered
# its example dep as a real one. Because that set means "this is a fold, not a stdlib leaf",
# the named leaf was then EXCLUDED from the generated `.deps` sidecar. Filed from patra
# (11 leaves emitted against 12 declared, `sakshi` missing) and confirmed in libro.
# Silent packaging corruption: the BUNDLE stays correct, so nothing fails — only a clean-room
# consumer resolving from the sidecar comes up short, which is what the sidecar is FOR.
#
# ⚠ THE UPSTREAM SYMPTOM NO LONGER REPRODUCES. At patra 1.13.8 the manifest contains no
# `[deps.` text at all (the triggering comment was removed upstream), so the end-to-end
# repro in the filing is gone. This gate therefore tests the PARSER RULE directly rather than
# re-staging a consumer tree — a defect whose only witness has been edited away still needs a
# regression test, and one that depends on a third-party file staying wrong is not a test.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
F=cbt/commands.cyr
fail=0

# axis 1 — the scan must be anchored to a line start.
if grep -q 'bol == 1 && ndi + 6 <= mlen && memeq(mbuf + ndi, "\[deps\.", 6) == 1' "$F"; then
    echo "  ok axis 1: the [deps. match is anchored to a line start (bol)"
else
    echo "  FAIL axis 1: the [deps. match is no longer line-anchored — comment prose can register a dep again"
    fail=1
fi

# axis 2 — comment lines must be skipped outright.
if grep -q 'in_cmt = 1' "$F" && grep -q 'ndc == 35' "$F"; then
    echo "  ok axis 2: '#' opens a comment and the rest of the line is skipped"
else
    echo "  FAIL axis 2: no comment suppression — a comment BEGINNING with [deps.x] still matches"
    fail=1
fi

# axis 3 (ANTI-VACUOUS) — the function must still FIND real headers.
# Axes 1-2 only assert the guards exist; deleting the whole scan would satisfy them.
if grep -q 'vec_push(named_deps, nd)' "$F"; then
    echo "  ok axis 3: real [deps.X] headers are still collected"
else
    echo "  FAIL axis 3 (anti-vacuous): the collector is gone — the exclude set would be empty"
    fail=1
fi

# axis 4 (BEHAVIOURAL) — a real consumer's sidecar must still be complete.
# patra declares its stdlib leaves and is the tree the defect was filed from.
P="$HOME/Repos/patra"
if [ -f "$P/dist/patra.deps" ]; then
    n=$(grep -cv '^#' "$P/dist/patra.deps" || true)
    if [ "$n" -ge 12 ]; then
        echo "  ok axis 4: patra's sidecar carries $n leaves (>= 12)"
    else
        echo "  FAIL axis 4: patra's sidecar carries only $n leaves — a leaf is being excluded again"
        fail=1
    fi
else
    echo "  note axis 4: ~/Repos/patra/dist/patra.deps absent — skipped"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: distlib-named-deps-anchored"; exit 1; }
echo "PASS: distlib-named-deps-anchored — only real [deps.X] section headers register, comment prose does not"
