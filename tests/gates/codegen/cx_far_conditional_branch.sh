#!/bin/sh
# cx_far_conditional_branch.sh — a conditional branch over more than 128 KiB of cx bytecode lands
# where the source says.
#
# 6.7.14. cx's jz / jnz carry a signed 16-bit offset (+-32768 instructions = +-128 KiB). EJCC
# (src/backend/cx/emit.cyr) emitted every condition's false-jump as a jz / jnz and EPATCH wrote
# `(cp - off) / 4` into its two offset bytes with no range check, so an `if` body of 1500
# statements (~150 KB) wrapped: cycc_cx exited 0 and cxvm jumped to a negative pc
# (`cxvm: jump to a negative code offset: -112020`) — and a wrap that lands inside the code runs
# the wrong instructions with no diagnostic. EJCC now lowers every patchable conditional to the
# inverted short branch over a 24-bit jmp (`jnz r0,+2; jmp L`), which EPATCH's 24-bit arm patches;
# no .cyx format or cxvm change. EPATCH's jz / jnz arm (left only for the fixed-size vector loops,
# bodies under 100 B — no source reaches it with a far span) refuses past 16 bits by name.
# issues/2026-10-15-cx-conditional-jump-past-128k-wraps-silently.md, CHANGELOG [6.7.14]
#
# Every far case is checked against TWO expectations: the literal exit code written next to it
# and the same source through the x86 backend. Each far fixture's .cyx is checked to be past
# 128 KiB, so a body that shrinks cannot turn the case into a near one and pass vacuously.
#
# Shell gate, not a .tcyr, for the cx_multi_return.sh reason: a .tcyr pulls in assert / fmt,
# which the cx backend cannot compile.
#
# Mutation ledger (6.7.14, each in a tree copy — the gate builds cycc_cx from the TREE's
# src/backend/cx/emit.cyr, so swapping build/cycc mutates nothing):
#   real tree                                      -> GREEN
#   EJCC reverted (a bare jz / jnz), EPATCH kept   -> RED, 8 of 9: every far case refused at compile
#                                                     ("a conditional branch spans more than 128 KiB
#                                                     of cx bytecode in fn 'f'")
#   EJCC and EPATCH both reverted (6.7.13)         -> RED, 7 of 9: every jump over a far body traps
#                                                     (`cxvm: jump to a negative code offset`); the
#                                                     filed repro's want is 1, cxvm's fault exit, so
#                                                     its row reads cxvm's stderr as well. Row 2 (the
#                                                     fall-through) stays green: it never jumps.
#   the near control stays GREEN under both mutants.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cx_far_conditional_branch: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: cx_far_conditional_branch: $CC missing"; exit 1; }

cat src/main_cx.cyr | "$CC" > "$D/cc" 2>/dev/null || true
[ -s "$D/cc" ] || { echo "FAIL: cx_far_conditional_branch: the cx compiler build produced nothing"; exit 1; }
chmod +x "$D/cc"
cat programs/cxvm.cyr | "$CC" > "$D/vm" 2>/dev/null || true
[ -s "$D/vm" ] || { echo "FAIL: cx_far_conditional_branch: the cxvm build produced nothing"; exit 1; }
chmod +x "$D/vm"

pass=0; fail=0
# $1 label  $2 source file  $3 expected exit code  $4 minimum .cyx bytes (0 = a near case)
run_case() {
    NAT=0
    cat "$2" | "$CC" > "$D/c.bin" 2>/dev/null || NAT=$?
    if [ "$NAT" != 0 ] || [ ! -s "$D/c.bin" ]; then
        printf '  FAIL: %-46s native compile rc=%s\n' "$1" "$NAT"; fail=$((fail+1)); return
    fi
    chmod +x "$D/c.bin"
    ( ulimit -c 0; "$D/c.bin" ) >/dev/null 2>&1 || NAT=$?
    CRC=0
    cat "$2" | "$D/cc" > "$D/c.cyx" 2> "$D/c.err" || CRC=$?
    if [ "$CRC" != 0 ] || [ ! -s "$D/c.cyx" ]; then
        printf '  FAIL: %-46s cx compile rc=%s: %s\n' "$1" "$CRC" "$(grep -v '^note' "$D/c.err" | head -1)"
        fail=$((fail+1)); return
    fi
    nb=$(wc -c < "$D/c.cyx" | tr -d ' ')
    if [ "$nb" -lt "$4" ]; then
        printf '  FAIL: %-46s the .cyx is %s B (want >= %s): no longer a far branch\n' "$1" "$nb" "$4"
        fail=$((fail+1)); return
    fi
    CX=0
    ( ulimit -c 0; timeout 60 "$D/vm" < "$D/c.cyx" ) > /dev/null 2> "$D/c.vm" || CX=$?
    if [ "$NAT" != "$3" ]; then
        printf '  FAIL: %-46s native=%s (want %s) — the expectation itself is wrong\n' "$1" "$NAT" "$3"
        fail=$((fail+1)); return
    fi
    # cxvm exits 1 on a guest fault — the filed repro's own value — so a fault line fails the row
    if [ -s "$D/c.vm" ]; then
        printf '  FAIL: %-46s cx=%s, cxvm faulted: %s\n' "$1" "$CX" "$(head -1 "$D/c.vm")"
        fail=$((fail+1)); return
    fi
    if [ "$CX" = "$3" ]; then
        printf '  ok: %-48s cx=%s native=%s (.cyx %s B)\n' "$1" "$CX" "$NAT" "$nb"; pass=$((pass+1))
    else
        printf '  FAIL: %-46s cx=%s (want %s, native=%s) %s\n' "$1" "$CX" "$3" "$NAT" "$(head -1 "$D/c.vm")"
        fail=$((fail+1))
    fi
}

# 1500 statements of ~100 B of cx bytecode each: one body is ~150 KB, past the 128 KiB a jz / jnz
# offset reaches. `k` / `d` vary the statement per arm so each arm adds its own amount to x.
body() { awk -v n=1500 -v k="$1" -v d="$2" -v ind="$3" 'BEGIN { for (i = 0; i < n; i++) printf "%sx = x + g * %d - %d;\n", ind, k, d }'; }
FAR=135168   # 132 KiB: one body past 128 KiB plus the fn around it

echo "row 1 — the filed repro, verbatim (an if-body of 1500 statements; the condition false):"
awk 'BEGIN { print "var g = 1;"; print "fn f(a): i64 {\n    var x = a;\n    if (a == 5) {";
  for (i = 0; i < 1500; i++) print "        x = x + g * 3 - 1;";
  print "    }\n    return x;\n}"; print "syscall(60, f(1) % 251);" }' > "$D/r1.cyr"
run_case "filed repro: f(1), the jump over the body" "$D/r1.cyr" 1 "$FAR"

echo "row 2 — the same fn, the condition true (the body runs: 5 + 1500 * 2 = 3005):"
sed 's/f(1) % 251/f(5) % 251/' "$D/r1.cyr" > "$D/r2.cyr"
run_case "filed shape: f(5), the fall-through" "$D/r2.cyr" 244 "$FAR"

echo "row 3 — a while loop whose body is past 128 KiB (the exit jump; f(3) = 9000):"
{
    printf 'var g = 1;\nfn f(n): i64 {\n    var x = 0;\n    var i = 0;\n    while (i < n) {\n'
    body 3 1 '        '
    printf '        i = i + 1;\n    }\n    return x;\n}\nsyscall(60, f(3) %% 251);\n'
} > "$D/r3.cyr"
run_case "while body past 128 KiB" "$D/r3.cyr" 215 "$FAR"

echo "row 4 — a C-style for and a for-in range, each body past 128 KiB (f(2) = 6000, h(4) = 12000):"
{
    printf 'var g = 1;\nfn f(n): i64 {\n    var x = 0;\n    for (var i = 0; i < n; i = i + 1) {\n'
    body 3 1 '        '
    printf '    }\n    return x;\n}\nsyscall(60, f(2) %% 251);\n'
} > "$D/r4a.cyr"
run_case "for body past 128 KiB" "$D/r4a.cyr" 227 "$FAR"
{
    printf 'var g = 1;\nfn h(n): i64 {\n    var x = 0;\n    for i in 0..n {\n'
    body 3 1 '        '
    printf '    }\n    return x;\n}\nsyscall(60, h(4) %% 251);\n'
} > "$D/r4b.cyr"
run_case "for-in body past 128 KiB" "$D/r4b.cyr" 203 "$FAR"

echo "row 5 — an if / elif / else chain, each arm past 128 KiB, conditions with && and ||:"
# f(1) takes the if (+3000), f(3) the elif (+4500), f(7) the else (+6000): 3001 + 4503 + 6007 = 13511
{
    printf 'var g = 1;\nfn f(a): i64 {\n    var x = a;\n    if (a == 1 && g == 1) {\n'
    body 3 1 '        '
    printf '    } elif (a == 2 || a == 3) {\n'
    body 5 2 '        '
    printf '    } else {\n'
    body 7 3 '        '
    printf '    }\n    return x;\n}\nsyscall(60, (f(1) + f(3) + f(7)) %% 251);\n'
} > "$D/r5.cyr"
run_case "if/elif/else, each arm past 128 KiB" "$D/r5.cyr" 208 $((FAR * 3))

echo "row 6 — a switch case and a match arm past 128 KiB (the jump to the next case / arm):"
# s(1) runs case 1 (+3000), s(2) case 2 (+4500), s(9) the default (+0): 3001 + 4502 + 9 = 7512
{
    printf 'var g = 1;\nfn s(a): i64 {\n    var x = a;\n    switch (a) {\n        case 1: {\n'
    body 3 1 '            '
    printf '        }\n        case 2: {\n'
    body 5 2 '            '
    printf '        }\n        default: { x = x + 0; }\n    }\n    return x;\n}\n'
    printf 'syscall(60, (s(1) + s(2) + s(9)) %% 251);\n'
} > "$D/r6a.cyr"
run_case "switch cases past 128 KiB" "$D/r6a.cyr" 233 $((FAR * 2))
# m(1) runs the first arm (+3000), m(4) the wildcard (+4500): 3001 + 4504 = 7505
{
    printf 'var g = 1;\nfn m(a): i64 {\n    var x = a;\n    match a {\n        1 => {\n'
    body 3 1 '            '
    printf '        }\n        _ => {\n'
    body 5 2 '            '
    printf '        }\n    }\n    return x;\n}\nsyscall(60, (m(1) + m(4)) %% 251);\n'
} > "$D/r6b.cyr"
run_case "match arm past 128 KiB" "$D/r6b.cyr" 226 $((FAR * 2))

echo "row 7 — control: near branches (if / elif / else, while, && / ||) unchanged:"
cat > "$D/r7.cyr" <<'EOF'
var g = 1;
fn f(a): i64 {
    var x = 0;
    if (a == 1 && g == 1) { x = 10; } elif (a == 2 || a == 3) { x = 20; } else { x = 30; }
    var i = 0;
    while (i < a) { x = x + 1; i = i + 1; }
    if (a > 5) { x = x + 100; }
    if (a <= 2) { x = x + 200; }
    return x;
}
syscall(60, (f(1) + f(3) + f(7)) % 251);
EOF
# f(1) = 10 + 1 + 200 = 211, f(3) = 20 + 3 = 23, f(7) = 30 + 7 + 100 = 137: 371 % 251 = 120
run_case "near branches" "$D/r7.cyr" 120 0

WANT=9
echo "cx_far_conditional_branch: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then echo "FAIL: cx_far_conditional_branch — $fail row(s) red"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: cx_far_conditional_branch — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: cx_far_conditional_branch — $pass/$WANT: a jump over an if body, a loop body, an elif / else arm, a switch case or a match arm past 128 KiB of cx bytecode lands where the source says, on cxvm as natively"
exit 0
