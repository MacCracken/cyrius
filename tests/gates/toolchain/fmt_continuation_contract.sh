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
command -v cyrius >/dev/null 2>&1 || { echo "SKIP: cyrius CLI not on PATH"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: fmt_continuation_contract: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$W"' EXIT
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

# --- axis 5 (6.7.12, D26): `cyrius audit` gives --check's verdict. Its fmt stage byte-compared
# cyrfmt's CANONICAL output with the file, so it flagged the accepted 4-step file --check passes
# (cyim 1.11.0, the filed repro below). The contract stays; audit now asks `cyrfmt --check`.
# Mutation: lib/audit_walk.cyr back on the byte compare -> axis 5 rows x and a8 RED.
audit_fmt() {   # $1 project dir -> the audit's fmt section on stdout
    ( cd "$1" && cyrius audit 2>&1 ) | awk '/── fmt ──/ { on = 1; next } /── lint ──/ { on = 0 } on'
}
mkp() {   # $1 dir, $2 the src/main.cyr content source
    mkdir -p "$1/src"
    printf '[package]\nname = "p"\nversion = "0.1.0"\n' > "$1/cyrius.cyml"
    cp "$2" "$1/src/main.cyr"
}
# The filed repro (issues/2026-10-12-cyrfmt-check-passes-a-file-cyrfmt-would-reformat.md), verbatim.
printf 'fn f(a, b) {\n    return a + b;\n}\nfn main() {\n    f(1,\n        2);\n    return 0;\n}\n' > "$W/x.cyr"
for shape in x a8 a6 a12; do
    [ -f "$W/$shape.cyr" ] || mk "$W/$shape.cyr" "${shape#a}"
    mkp "$W/p_$shape" "$W/$shape.cyr"
    chk=fail; cyrius fmt "$W/p_$shape/src/main.cyr" --check >/dev/null 2>&1 && chk=pass
    sec=$(audit_fmt "$W/p_$shape")
    aud=other
    printf '%s\n' "$sec" | grep -qF 'ok: format clean' && aud=pass
    printf '%s\n' "$sec" | grep -qF 'files need reformatting' && aud=fail
    want=pass; [ "$shape" = a12 ] && want=fail
    if [ "$chk" = "$want" ] && [ "$aud" = "$want" ]; then
        echo "  ok axis 5: $shape — cyrfmt --check and cyrius audit both say $want"
    else
        echo "  FAIL axis 5: $shape — --check says $chk, cyrius audit says $aud (want $want for both): $sec"; fail=1
    fi
done
# 5b: the rewrite stays canonical — fmt normalises the accepted 4 to 2 (the guide's sentence).
cyrius fmt "$W/p_x/src/main.cyr" >/dev/null 2>&1 || true
if grep -qx '      2);' "$W/p_x/src/main.cyr"; then
    echo "  ok axis 5b: cyrius fmt rewrote the accepted 4-step continuation as the canonical 2"
else
    echo "  FAIL axis 5b: cyrius fmt did not normalise the filed repro to the 2-step form"; fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: fmt-continuation-contract"; exit 1; }
echo "PASS: fmt-continuation-contract — 2 canonical / 4 accepted / deeper rejected, --check speaks, fmt writes in place, --dry does not, cyrius audit agrees with --check"
