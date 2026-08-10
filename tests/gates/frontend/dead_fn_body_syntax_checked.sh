#!/bin/sh
# tests/gates/frontend/dead_fn_body_syntax_checked.sh — v6.5.17
#
# EVERY fn body is parsed, whether or not anything calls it.
#
# THE FILED DEFECT (hisab, 2026-08-09). A function that nothing called, AND whose
# name contained no underscore, had its body SKIPPED: pass 2 emitted a 3-byte
# `xor eax,eax; ret` stub and brace-skipped the tokens, so arbitrary garbage inside
# it compiled green and `build` / `lint` / `vet` / `check` all agreed. Both
# conditions were required, and the second is the one that makes this a bug rather
# than a policy: whether your function was syntax-checked depended on a CHARACTER IN
# ITS IDENTIFIER. (The underscore guard was there because `mod_fn` name mangling
# makes the offset-keyed reference bitmap unreliable — a real problem, guarded by a
# proxy that happens to cover snake_case and expose camelCase.)
#
# It was also FORK-DIVERGENT: the skip lived in main.cyr / main_win.cyr /
# main_x86_macho.cyr / main_cx.cyr and never in the three aarch64 drivers, so the
# same source was accepted on x86/PE/Mach-O and REJECTED on aarch64.
#
# WHAT THIS GATE ASSERTS — on the COMPILER'S EXIT CODE, not on stdout text:
#   1. a syntax error in an uncalled underscore-free fn FAILS the build,
#   2. across a spread of name shapes, because the old behaviour was keyed on the
#      name (one name proves nothing — `n` and `len` were already checked by
#      accident, since some stdlib file uses them as locals),
#   3. the underscore and called variants still fail (no regression),
#   4. a CLEAN file with an uncalled underscore-free fn still compiles, so the gate
#      cannot pass by rejecting everything,
#   5. the diagnostic names a line — a bare non-zero exit is not a diagnostic.
#
# MUTATION PROOF: restore the `dce_has_us == 0` + bitmap skip in src/main.cyr and
# case 1 goes RED for gg / victim / abcdefghij / a while the underscore case stays
# green — which is exactly the filed truth table.

set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: dead-fn-body-syntax-checked — %s not built\n" "$CC"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0

# The body is the filing's verbatim garbage. `$1` is the fn name, `$2` is either
# "call" (main calls it) or "dead" (nothing does).
emit_broken() {
    if [ "$2" = "call" ]; then
        printf 'fn %s() { var x = ; this is not cyrius at all ]] ((\n    return 0; }\nfn main() { return %s(); }\nvar r = main();\n' "$1" "$1" > "$T/p.cyr"
    else
        printf 'fn %s() { var x = ; this is not cyrius at all ]] ((\n    return 0; }\nfn main() { return 0; }\nvar r = main();\n' "$1" > "$T/p.cyr"
    fi
}

compile() {
    # Never merge stderr into the output stream — that produces a "binary" that
    # looks runnable. Separate files, and the exit code is what we judge.
    "$CC" < "$T/p.cyr" > "$T/out.bin" 2> "$T/err.txt" && echo 0 || echo 1
}

echo "axis 1 — a syntax error in an UNCALLED fn fails the build, whatever the name:"
for n in gg victim abcdefghij a broken_fn victim_x; do
    emit_broken "$n" dead
    rc=$(compile)
    if [ "$rc" = 1 ]; then
        echo "  ok: uncalled '$n' rejected (1)"
    else
        echo "  FAIL: uncalled '$n' COMPILED — a body with a syntax error was never parsed"
        fail=$((fail + 1))
    fi
done

echo "axis 2 — the same fn, called, still fails (no regression on the path that always worked):"
for n in gg broken_fn; do
    emit_broken "$n" call
    rc=$(compile)
    if [ "$rc" = 1 ]; then
        echo "  ok: called '$n' rejected (1)"
    else
        echo "  FAIL: called '$n' compiled"
        fail=$((fail + 1))
    fi
done

echo "axis 3 — the diagnostic NAMES the offending line (a bare exit 1 is not a diagnostic):"
emit_broken gg dead
compile > /dev/null
if grep -q "unexpected ';'" "$T/err.txt" 2>/dev/null; then
    echo "  ok: error text present (1)"
else
    echo "  FAIL: no 'unexpected' diagnostic for the uncalled fn"
    head -3 "$T/err.txt" 2>/dev/null || true
    fail=$((fail + 1))
fi
if grep -qE '<source>:[0-9]+:[0-9]+' "$T/err.txt" 2>/dev/null; then
    echo "  ok: line:column cited (1)"
else
    echo "  FAIL: diagnostic carries no line:column"
    head -3 "$T/err.txt" 2>/dev/null || true
    fail=$((fail + 1))
fi

echo "axis 4 — ⭐ ANTI-VACUOUS: a CLEAN file with an uncalled underscore-free fn still builds:"
printf 'fn gg() { var x = 1;\n    return x; }\nfn main() { return 0; }\nvar r = main();\n' > "$T/p.cyr"
rc=$(compile)
if [ "$rc" = 0 ]; then
    echo "  ok: clean dead fn compiles (0)"
else
    echo "  FAIL: a CLEAN uncalled fn was rejected — this gate would pass by rejecting everything"
    head -3 "$T/err.txt" 2>/dev/null || true
    fail=$((fail + 1))
fi

if [ "$fail" != 0 ]; then
    echo "FAIL: dead-fn-body-syntax-checked — $fail assertion(s) failed"
    exit 1
fi
echo "PASS: dead-fn-body-syntax-checked — every fn body is parsed, name-independent"
exit 0
