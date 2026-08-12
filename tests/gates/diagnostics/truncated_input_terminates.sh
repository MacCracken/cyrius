#!/bin/sh
# tests/gates/diagnostics/truncated_input_terminates.sh — v6.5.19 (CVE-39)
#
# cycc reads UNTRUSTED source from stdin (`cat foo.cyr | cycc`). On ANY input — a
# clipped file, an unclosed construct, a hostile 4 bytes — it must terminate with a
# diagnostic. It must never die by SIGNAL and never hang.
#
# WHY THIS EXISTS ALONGSIDE cycc_parser_fuzz.sh. That gate mutates bytes at random
# and, from v6.3.22 to v6.5.18, could not report a crash AT ALL: it tested
# `r.returncode >= 128` on a Python `subprocess.run` result, but Python reports a
# signal death as NEGATIVE (-11), so the signal branch was dead code and only the
# timeout branch ever ran. It sat GREEN for three minors over 40 crashing constructs.
# Fixing that predicate makes it RED at its own default ITERS=15 — but it finds those
# crashes BY CHANCE, from a fixed LCG seed. This gate names the shapes DETERMINISTICALLY
# so a regression cannot slip through on a seed that happens not to hit it. It is also
# pure `sh`: the fuzz gate SKIPs when python3 is unavailable, and a gate that can skip
# itself is a gate that will.
#
# ⭐ WHAT ACTUALLY BROKE (all measured at 6.5.18, all fixed in v6.5.19):
#   * `enum` — FOUR BYTES — SIGSEGV. The member loop's only exit was `}`; at EOF it
#     re-registered the same member forever and walked a 1024-entry table off its
#     region at ~1027 iterations. 1,027 lines of `duplicate symbol` spew, then death.
#   * `fn`, `var x`, `async` — SIGSEGV with **ZERO bytes of stderr**. No diagnostic at
#     all. These die BEFORE any error is emitted, which is the crux (see below).
#   * `fn f<`, `struct S<`, `enum E<` — HANG. SKIP_GENERICS loops to `>` with no EOF
#     exit and emits no diagnostic, so `_had_error` stayed 0 and the v6.4.62 watchdog
#     — which is gated on `_had_error` — never ticked once.
#   * 40 of 103 truncated top-level constructs crashed or hung in total.
#
# ⭐ THE ROOT CAUSE, AND WHY THE PREVIOUS FIX MISSED IT. v6.4.78 added the past-EOF
# clamp to PEEKT but placed it INSIDE the `_had_error == 1` guard, reasoning that "a
# WELL-FORMED parse never advances past [EOF] — the runaway is exclusively a post-error
# recovery phenomenon". That premise is false: the silent skippers walk off the end
# before any error exists. v6.5.19 makes the clamp unconditional and adds
# `_wd_eof_tick`, a backstop that is NOT gated on `_had_error`.
#
# ANTI-VACUOUS — the axes that stop this gate being satisfiable by breaking cycc:
#   * axis 2 requires valid programs to still COMPILE AND RUN to the right exit code
#     (a cycc that rejected everything would pass axes 1 and 3 alone);
#   * axis 4 requires a 256-arm match and a 256-case switch — right at the cap — to
#     still compile and produce the right answer, so the new `_ends_guard` cannot be
#     "fixed" by clamping the limit down to something safe and useless;
#   * axis 5 requires the diagnostic to stay SHORT, so "terminates" cannot be bought
#     by spewing a hundred thousand lines first (the 6.4.78 failure mode).
#
# MUTATION PROOF (all run at v6.5.19, RED then GREEN):
#   * revert PEEKT's clamp to the v6.4.78 `_had_error`-gated form -> 21 RED across
#     axes 1 and 3 (`fn`, `var x`, `async`, all six generics shapes); axes 2/4/5 green.
#   * delete the `elif (PEEKT(S) == 12)` EOF guard from PARSE_ENUM_DEF's member loop
#     -> axis 1 `enum` RED (SIGSEGV) and axis 5 RED (1027 lines); everything else green.
#   * delete `_ends_guard(S, ec);` from the four call sites in parse.cyr -> axis 3
#     bigmatch/bigswitch RED (SIGSEGV); axis 4 stays green, which is the point — the
#     cap-boundary cases are unaffected, so only the overflow assertion moves.
#   * lower `_ends_guard`'s limit from 256 to 200 -> axis 4 RED (both boundary cases
#     stop compiling), axis 3 green. This is the mutation that proves axis 4 is load-
#     bearing rather than decorative.
#   * raise `_wd_eof_tick`'s bound from 20000 to 100000000 -> axis 1 generics shapes
#     RED (they hang again) ONLY IF the SKIP_GENERICS guard is also removed; with the
#     guard in place this mutation is green, correctly showing the backstop is defence
#     in depth and not the primary fix.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
fails=0

if [ ! -x "$CC" ]; then
    echo "FAIL: truncated-input-terminates — build/cycc not built"
    exit 1
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# run_src <label> <file> -> echoes the exit status; 124 = timed out (hang).
run_src() {
    timeout 20 "$CC" < "$2" > "$T/out" 2> "$T/err"
    echo $?
}

# A crash is exit >= 128 (the SHELL convention — correct here, unlike the Python
# `>= 128` that made the sibling fuzz gate vacuous). 124 is timeout(1)'s own code.
assert_no_crash() {
    label=$1; rc=$2
    if [ "$rc" -ge 128 ]; then
        echo "  FAIL: $label — died by SIGNAL (exit $rc)"; fails=$((fails + 1)); return
    fi
    if [ "$rc" -eq 124 ]; then
        echo "  FAIL: $label — HUNG (20s timeout)"; fails=$((fails + 1)); return
    fi
    if [ "$rc" -eq 0 ]; then
        echo "  FAIL: $label — accepted a truncated file (exit 0)"; fails=$((fails + 1)); return
    fi
    echo "  ok: $label (graceful exit $rc)"
}

# ── AXIS 1 — every construct, truncated at each token boundary.
echo "axis 1 — truncated constructs terminate gracefully (no signal, no hang):"
i=0
while IFS= read -r frag; do
    [ -n "$frag" ] || continue
    i=$((i + 1))
    printf '%s' "$frag" > "$T/t$i.cyr"
    rc=$(run_src "t$i" "$T/t$i.cyr")
    assert_no_crash "[$frag]" "$rc"
done <<'FRAGS'
enum
enum E
enum E {
enum E { A
enum E { A(
enum E { A = 1
struct
struct S
struct S {
struct S { a
struct S { a: i64
union
union U
union U {
union U { a
fn
fn f
fn f(
fn f()
fn f() {
fn f() { var
fn f() { var x =
fn f() { if (
fn f() { while (
fn f() { for
fn f() { match
fn f() { match (
fn f() { switch (x) {
fn f() { return
var
var x
var x =
var x[
var x: i64[
async
async fn
fn f<
fn f<T
struct S<
struct S<T
enum E<
enum E<T
FRAGS

# ── AXIS 2 — ⭐ ANTI-VACUOUS. Valid programs must still compile AND RUN correctly.
# Without this, every assertion above is satisfiable by a cycc that refuses everything.
echo "axis 2 — ANTI-VACUOUS: valid programs still compile and run:"
printf 'fn add(a, b) { return a + b; }\nfn main() { return add(17, 25); }\nvar r = main();\n' > "$T/ok.cyr"
if "$CC" < "$T/ok.cyr" > "$T/ok.bin" 2> "$T/ok.err"; then
    chmod +x "$T/ok.bin"
    "$T/ok.bin"; got=$?
    if [ "$got" = "42" ]; then echo "  ok: valid program compiles and returns 42"
    else echo "  FAIL: valid program returned $got, expected 42"; fails=$((fails + 1)); fi
else
    echo "  FAIL: valid program did not compile"; fails=$((fails + 1))
fi
printf 'enum Color { RED = 1; GREEN = 2; }\nstruct P { x; y; }\nunion U { a; b; }\nfn pick(c) { match (c) { RED => { return 10; } _ => { return 20; } } }\nfn main() { return pick(RED); }\nvar r = main();\n' > "$T/ok2.cyr"
if "$CC" < "$T/ok2.cyr" > "$T/ok2.bin" 2> "$T/ok2.err"; then
    chmod +x "$T/ok2.bin"
    "$T/ok2.bin"; got2=$?
    if [ "$got2" = "10" ]; then echo "  ok: enum/struct/union/match all still parse and run"
    else echo "  FAIL: enum/match program returned $got2, expected 10"; fails=$((fails + 1)); fi
else
    echo "  FAIL: enum/struct/union/match program did not compile"; fails=$((fails + 1))
fi

# ── AXIS 3 — ⭐ NO HOSTILE INPUT NEEDED. A >256-arm match / >256-case switch is
# ORDINARY VALID CYRIUS (opcode dispatch) and wrote off the end of a 256-slot LOCAL
# array. v6.2.1 resized these arrays 32 -> 256 and guarded the array NEXT TO them but
# never bounded `ec`, so the cliff moved instead of being fenced.
echo "axis 3 — over-cap match/switch is refused, not a stack smash:"
{
    echo 'fn pick(x) {'
    echo '    var r = 0;'
    echo '    match (x) {'
    j=0; while [ "$j" -lt 400 ]; do echo "        $j => { r = $j; }"; j=$((j + 1)); done
    echo '        _ => { r = 999; }'
    echo '    }'
    echo '    return r;'
    echo '}'
    echo 'fn main() { return pick(3); }'
    echo 'var r = main();'
} > "$T/bigmatch.cyr"
rc=$(run_src bigmatch "$T/bigmatch.cyr")
assert_no_crash "400-arm match" "$rc"
if grep -q "too many case/arm bodies" "$T/err"; then echo "  ok: names the cap"
else echo "  FAIL: 400-arm match did not name the cap"; fails=$((fails + 1)); fi

{
    echo 'fn pick(x) {'
    echo '    var r = 0;'
    echo '    switch (x) {'
    j=0; while [ "$j" -lt 400 ]; do echo "        case $j: { return $j; }"; j=$((j + 1)); done
    echo '        default: { return 999; }'
    echo '    }'
    echo '    return r;'
    echo '}'
    echo 'fn main() { return pick(3); }'
    echo 'var r = main();'
} > "$T/bigswitch.cyr"
rc=$(run_src bigswitch "$T/bigswitch.cyr")
assert_no_crash "400-case switch" "$rc"
if grep -q "too many case/arm bodies" "$T/err"; then echo "  ok: names the cap"
else echo "  FAIL: 400-case switch did not name the cap"; fails=$((fails + 1)); fi

# ── AXIS 4 — ⭐ ANTI-VACUOUS for axis 3. The cap must be a real boundary, not a
# convenient low number: a match/switch AT the cap must still compile and be correct.
# This is what stops `_ends_guard` being "fixed" by clamping the limit to 8.
echo "axis 4 — ANTI-VACUOUS: a construct AT the 256 cap still compiles and is correct:"
{
    echo 'fn pick(x) {'
    echo '    var r = 0;'
    echo '    match (x) {'
    j=0; while [ "$j" -lt 255 ]; do echo "        $j => { r = $j; }"; j=$((j + 1)); done
    echo '        _ => { r = 7; }'
    echo '    }'
    echo '    return r;'
    echo '}'
    echo 'fn main() { return pick(200); }'
    echo 'var r = main();'
} > "$T/capmatch.cyr"
if "$CC" < "$T/capmatch.cyr" > "$T/cap.bin" 2> "$T/cap.err"; then
    chmod +x "$T/cap.bin"; "$T/cap.bin"; g=$?
    if [ "$g" = "200" ]; then echo "  ok: 256-body match compiles and returns 200"
    else echo "  FAIL: 256-body match returned $g, expected 200"; fails=$((fails + 1)); fi
else
    echo "  FAIL: a match AT the cap was rejected — the cap is too tight"; fails=$((fails + 1))
fi
{
    echo 'fn pick(x) {'
    echo '    var r = 0;'
    echo '    switch (x) {'
    # NB: `case N: { return N; }` — RETURN, deliberately, and do not "simplify" these
    # bodies to assign-and-fall-out. Two pre-existing switch defects (both reproduced
    # against the HEAD compiler, both filed in
    # docs/development/issues/2026-08-11-switch-case-body-only-exits-safely-via-return.md)
    # make any other exit from a case body unsafe:
    #   * `break` inside switch/match emits an UNPATCHED jump — PARSE_SWITCH and
    #     PARSE_MATCH never touch the 0x18F840 break chain that PARSE_WHILE/PARSE_FOR
    #     maintain — and the binary SIGSEGVs;
    #   * falling out of a TABLE-regime case (>= 4 cases) is miscompiled: with a
    #     `default:` present it SIGSEGVs, without one it silently yields the wrong
    #     answer (case 2 of 4 returned 0 instead of 2).
    # Those are out of this gate's scope; it exists to prove truncated input
    # terminates. Using `return` keeps this axis measuring the cap, not that.
    j=0; while [ "$j" -lt 255 ]; do echo "        case $j: { return $j; }"; j=$((j + 1)); done
    echo '        default: { return 7; }'
    echo '    }'
    echo '    return r;'
    echo '}'
    echo 'fn main() { return pick(200); }'
    echo 'var r = main();'
} > "$T/capswitch.cyr"
if "$CC" < "$T/capswitch.cyr" > "$T/caps.bin" 2> "$T/caps.err"; then
    chmod +x "$T/caps.bin"; "$T/caps.bin"; g=$?
    if [ "$g" = "200" ]; then echo "  ok: 256-body switch compiles and returns 200"
    else echo "  FAIL: 256-body switch returned $g, expected 200"; fails=$((fails + 1)); fi
else
    echo "  FAIL: a switch AT the cap was rejected — the cap is too tight"; fails=$((fails + 1))
fi

# ── AXIS 5 — the diagnostic stays SHORT. "Terminates" is not enough on its own: the
# v6.4.78 issue was 166,670 stderr lines burying the real error, and at 6.5.18 a bare
# `enum` still emitted 1,027 lines of `duplicate symbol` before dying.
echo "axis 5 — truncated input yields a SHORT diagnostic, not a spew:"
for frag in 'enum' 'struct S {' 'fn f() { match' 'fn f<T'; do
    printf '%s' "$frag" > "$T/q.cyr"
    timeout 20 "$CC" < "$T/q.cyr" > /dev/null 2> "$T/qerr"
    n=$(wc -l < "$T/qerr" | tr -d ' ')
    if [ "$n" -le 40 ]; then echo "  ok: [$frag] -> $n stderr lines"
    else echo "  FAIL: [$frag] -> $n stderr lines (spew; expected <= 40)"; fails=$((fails + 1)); fi
done

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: truncated-input-terminates — no signal, no hang, bounded output, caps honoured"
    exit 0
fi
echo "FAIL: truncated-input-terminates — $fails assertion(s) failed"
exit 1
