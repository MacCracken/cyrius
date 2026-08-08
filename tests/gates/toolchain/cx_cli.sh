#!/bin/sh
# cx arc A: the `cyrius build --target=cx` + `cyrius run *.cyx` CLI path, end-to-end.
# The 5 internal cx gates prove src/main_cx.cyr self-hosts, NOT that the installed
# CLI reaches the same emit — so without this gate --target=cx can rot behind a
# green check (the macOS-CI-rot pattern). Builds the cyrius CLI, then:
#   (1) build --target=cx an integer program -> a valid CYX (format version byte
#       = 1) that `cyrius run` executes with the correct exit code;
#   (2) a float program hard-errors (the A5 EMIT_FLOAT_LIT footgun guard).
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f src/main_cx.cyr ] || { echo "SKIP: src/main_cx.cyr missing"; exit 0; }

CYR=$(mktemp)
cat cbt/cyrius.cyr | "$CC" > "$CYR" 2>/dev/null || { echo "FAIL: cyrius CLI build"; rm -f "$CYR"; exit 1; }
chmod +x "$CYR"
T=$(mktemp -d)
trap 'rm -f "$CYR"; rm -rf "$T"' EXIT

# (1) integer build --target=cx -> versioned .cyx -> run
printf 'fn f(): i64 { return 33; }\nsyscall(60, f());\n' > "$T/i.cyr"
"$CYR" build --target=cx "$T/i.cyr" "$T/i.cyx" >/dev/null 2>&1 || { echo "FAIL: cyrius build --target=cx"; exit 1; }
[ -f "$T/i.cyx" ] || { echo "FAIL: no .cyx produced"; exit 1; }
v=$(od -An -j3 -N1 -tu1 "$T/i.cyx" | tr -d ' ')
[ "$v" = "1" ] || { echo "FAIL: .cyx format version byte = $v (want 1)"; exit 1; }
# NB: `cyrius run` exits with the guest's code (33), which is nonzero — capture it
# via `|| rc=$?` so `set -e` doesn't abort before the assertion (the CI-loop trap).
rc=0
"$CYR" run "$T/i.cyx" >/dev/null 2>&1 || rc=$?
[ "$rc" = "33" ] || { echo "FAIL: cyrius run *.cyx exited $rc (want 33)"; exit 1; }

# (2) cx arc B: f64 ARITHMETIC works. 60.0 / 4.0 - 13.0 = 2.0 -> exit 2.
printf 'fn main(): i64 { var a = 60.0; var b = 4.0; var q = f64_div(a, b); var r = f64_sub(q, 13.0); return f64_to(r); }\nvar e = main();\nsyscall(60, e);\n' > "$T/fa.cyr"
"$CYR" build --target=cx "$T/fa.cyr" "$T/fa.cyx" >/dev/null 2>&1 || { echo "FAIL: f64 arithmetic build --target=cx"; exit 1; }
rc=0; "$CYR" run "$T/fa.cyx" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || { echo "FAIL: cx f64 arithmetic exit $rc (want 2)"; exit 1; }

# (3) global-var-collision fix (RECFIX/fixup-table): 3 globals must be distinct.
printf 'var a = 100;\nvar b = 7;\nvar c = a - b;\nsyscall(60, c);\n' > "$T/g.cyr"
"$CYR" build --target=cx "$T/g.cyr" "$T/g.cyx" >/dev/null 2>&1 || { echo "FAIL: global-var build"; exit 1; }
rc=0; "$CYR" run "$T/g.cyx" >/dev/null 2>&1 || rc=$?
[ "$rc" = "93" ] || { echo "FAIL: cx global vars collide (exit $rc, want 93)"; exit 1; }

# (4) cx arc B follow-up: f64 COMPARES now WORK in conditionals (the flag-less-EJCC
# truthiness fix). gt(10,4) true -> +1; lt(10,4) false -> +0; gt(10,4)==1 true -> +2 = 3.
printf 'fn main(): i64 { var a = 10.0; var b = 4.0; var r = 0; if (f64_gt(a, b)) { r = r + 1; } if (f64_lt(a, b)) { r = r + 100; } if (f64_gt(a, b) == 1) { r = r + 2; } return r; }\nvar e = main();\nsyscall(60, e);\n' > "$T/fc.cyr"
"$CYR" build --target=cx "$T/fc.cyr" "$T/fc.cyx" >/dev/null 2>&1 || { echo "FAIL: f64 compare build --target=cx"; exit 1; }
rc=0; "$CYR" run "$T/fc.cyx" >/dev/null 2>&1 || rc=$?
[ "$rc" = "3" ] || { echo "FAIL: cx f64 compare in conditionals exit $rc (want 3)"; exit 1; }

# (5) transcendentals still fail loud (f64_sin — no libm opcodes yet).
printf 'fn main(): i64 { var x = 1.0; var y = f64_sin(x); return 0; }\nvar e = main();\nsyscall(60, e);\n' > "$T/ts.cyr"
if "$CYR" build --target=cx "$T/ts.cyr" "$T/ts.cyx" >/dev/null 2>"$T/ts.err"; then
    echo "FAIL: f64_sin compiled on cx — transcendentals must fail loud"; exit 1
fi
grep -q "not yet supported on the cx bytecode target" "$T/ts.err" || { echo "FAIL: wrong transcendental error:"; cat "$T/ts.err"; exit 1; }

# (6) cx arc C: the guest syscall path (0x70) does real I/O — a .cyx that WRITES
# to stdout, and exits with the guest write()'s byte count. Proves the pointer-arg
# fixup + arity-correct dispatch route the guest write to the host (not just a
# halt). Cross-OS hosts run the same class of fixture via cross-os-selfhost.sh.
printf 'fn main(): i64 { var w = syscall(1, 1, "cx-io-ok\\n", 9); return w; }\nvar e = main();\nsyscall(60, e);\n' > "$T/io.cyr"
"$CYR" build --target=cx "$T/io.cyr" "$T/io.cyx" >/dev/null 2>&1 || { echo "FAIL: cx I/O build --target=cx"; exit 1; }
# `cyrius run` exits with the guest's code (9) — capture stdout AND rc in one
# ||-guarded assignment so `set -e` doesn't abort on the nonzero exit (the
# CI-loop trap). Command substitution captures stdout regardless of exit code.
io_rc=0; io_out=$("$CYR" run "$T/io.cyx" 2>/dev/null) || io_rc=$?
[ "$io_out" = "cx-io-ok" ] || { echo "FAIL: cx I/O stdout=[$io_out] (want cx-io-ok)"; exit 1; }
[ "$io_rc" = "9" ] || { echo "FAIL: cx I/O guest write returned $io_rc (want 9 bytes)"; exit 1; }

echo "PASS: cx --target=cx build/run + versioned .cyx; f64 arithmetic + comparisons work; globals distinct; transcendentals fail loud; guest I/O writes to stdout (cx arc A/B/C)"
