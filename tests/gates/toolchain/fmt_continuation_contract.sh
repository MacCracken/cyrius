#!/bin/sh
# v6.5.28 — the cyrfmt continuation-indent contract, and the fmt CLI modes.
#
# THE DEFECT. cyrfmt indented every line at `brace_depth * 4` and never tracked PARENS, so a
# continuation line inside an unclosed `(` came out at the enclosing statement's indent. Then
# `--check` compared byte-for-byte and exited 1 in SILENCE — no diff, no message, no line — so
# a consumer's CI failed with nothing to act on and `cyrius fmt` (stdout-only) offered no
# in-place way to fix it. Filed from rupa 0.1.3, worked around by un-wrapping every call.
#
# ⚠ BOTH the filing's headline AND its first refutation were half wrong. Wrapped calls are not
# rejected — the line break survives. But fmt's own output still failed fmt's own --check, so
# the unfixable-in-place state the consumer reported was real.
#
# ⚖️ MAINTAINER CONTRACT (2026-08-18): canonical continuation indent is 2 spaces per open
# paren level; 4 is ACCEPTED; deeper is REJECTED — "else it wouldn't be a format check".
# A tolerance exactly two shapes wide keeps already-formatted trees from churning without
# turning the check into a no-op.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
command -v cyrius >/dev/null 2>&1 || { echo "SKIP: cyrius CLI not on PATH"; exit 0; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0

mk() { sp=$(printf "%${2}s" ""); printf 'fn main(): i64 {\n    var x = some_call(1,\n%s2);\n    return x;\n}\n' "$sp" > "$1"; }

# --- axis 1: the acceptance boundary. 6 = 4 brace + 2 paren (canonical), 8 = +4 (accepted),
# 12 = +8 (rejected). All three matter: without the 12 case the check accepts anything.
for n in 6 8; do
    mk "$W/a$n.cyr" "$n"
    if cyrius fmt "$W/a$n.cyr" --check >/dev/null 2>&1; then
        echo "  ok axis 1: ${n}-space continuation accepted"
    else
        echo "  FAIL axis 1: ${n}-space continuation REJECTED (canonical is 6, accepted is 8)"; fail=1
    fi
done
mk "$W/a12.cyr" 12
if cyrius fmt "$W/a12.cyr" --check >/dev/null 2>&1; then
    echo "  FAIL axis 1 (anti-vacuous): 12-space continuation ACCEPTED — the tolerance is unbounded, so this is not a check"
    fail=1
else
    echo "  ok axis 1: 12-space continuation rejected (tolerance is bounded)"
fi

# --- axis 2: --check must SAY WHAT DIFFERS. The silence was the uncontested half of the filing.
mk "$W/b.cyr" 12
out=$(cyrius fmt "$W/b.cyr" --check 2>&1 || true)
if [ -z "$out" ]; then
    echo "  FAIL axis 2: --check produced ZERO bytes — a silent CI failure again"; fail=1
elif printf '%s' "$out" | grep -q ":3:"; then
    echo "  ok axis 2: --check names the file and the first differing line"
else
    echo "  FAIL axis 2: --check said something but did not name the differing line: $out"; fail=1
fi

# --- axis 3: fmt REWRITES IN PLACE by default (the breaking change), --dry does NOT.
mk "$W/c.cyr" 12
cyrius fmt "$W/c.cyr" >/dev/null 2>&1 || true
if cyrius fmt "$W/c.cyr" --check >/dev/null 2>&1; then
    echo "  ok axis 3: default fmt rewrote the file in place"
else
    echo "  FAIL axis 3: default fmt did not fix the file — the unfixable-in-place state is back"; fail=1
fi
mk "$W/d.cyr" 12
before=$(cksum < "$W/d.cyr")
cyrius fmt "$W/d.cyr" --dry >/dev/null 2>&1 || true
after=$(cksum < "$W/d.cyr")
if [ "$before" = "$after" ]; then
    echo "  ok axis 3: --dry left the file untouched"
else
    echo "  FAIL axis 3: --dry MODIFIED the file — that is the one thing it must not do"; fail=1
fi

# --- axis 4: cyrfmt actually tracks parens (the mechanism, not just the outcome).
if grep -q "pdepth" programs/cyrfmt.cyr; then
    echo "  ok axis 4: cyrfmt tracks paren depth"
else
    echo "  FAIL axis 4: no paren-depth tracking — continuations would flatten to brace depth again"; fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: fmt-continuation-contract"; exit 1; }
echo "PASS: fmt-continuation-contract — 2 canonical / 4 accepted / deeper rejected, --check speaks, fmt writes in place, --dry does not"
