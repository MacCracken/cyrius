#!/bin/sh
# Gate: no .tcyr may END in a shape that exits 0 after an assertion failed (6.6.11 B01).
#
# THE DEFECT. Two epilogue shapes in the corpus made a test exit 0 with `1 failed` printed:
#
#   (1) MAIN-TWICE. When a source DEFINES `fn main`, the executable epilogue (src/main.cyr,
#       the `_find_fn_by_name(S, "main", 4)` block) auto-calls it after the top level. A file
#       that ALSO calls `main();` / `var x = main();` at top level and then does NOT exit runs
#       the body twice and exits with the SECOND run's return value, so a trailing
#       `var r = assert_summary();` is dead for the exit code. Measured at 6.6.11 with one
#       assert mutated: crossos/derive_accessor_widths.tcyr printed `23 passed, 1 failed` and
#       exited 0 on x86_64, qemu-aarch64 and wine PE; derive/derive_body_shapes.tcyr the same.
#   (2) EXIT-0-AFTER-SUMMARY. platform/pwd_grp.tcyr and platform/shadow_pam.tcyr ended in
#       `var r = assert_summary();` followed by a literal `syscall(60, 0);`.
#
# THE RULES ENFORCED over every tests/tcyr/**/*.tcyr (recursive, with the corpus floor):
#   A  a file that defines `fn main(` and calls `main(` in a TOP-LEVEL statement
#      (column 0: `main(...)` or `var NAME = main(...)`) must have a top-level exit —
#      `syscall(60|SYS_EXIT, ...)` or `sys_exit(...)` — on that line or a later one.
#      (`syscall(60, main());` is itself the exit, and has no bare top-level call.)
#   B  no TOP-LEVEL `syscall(60|SYS_EXIT, 0)` / `sys_exit(0)` after a line calling
#      `assert_summary(`. Top level only: an indented `sys_exit(0)` in a forked child's
#      block (crypto/tls_native_freestanding.tcyr) is the child's own exit, not the test's.
# The auto-call of main is NOT changed (it is a documented contract for programs); the lint
# covers tests/ only.
#
# AXES
#   1  the live corpus: zero violations, and at least CORPUS_FLOOR files walked.
#   2  staged fixtures: each bad shape is REFUSED by name, each good shape is accepted.
#   3  the live compiler still makes the bad shapes dangerous: a staged main-twice file and a
#      staged exit-0 file each print `1 failed` and exit 0 — the reason rule A/B exist. If the
#      compiler ever stops auto-calling main, axis 3 goes red so this gate is revisited rather
#      than left guarding a shape that no longer bites.
#
# MUTATION LEDGER (6.6.11), run on every invocation as axis 2's M rows: a copy of the lint
# with rule A's exit requirement deleted accepts the main-twice fixture; a copy with rule B
# deleted accepts the exit-0 fixture. Both mutants must ACCEPT — otherwise the rows are not
# proving anything.
#
# Exit 77 when it could not run (no compiler to drive axis 3). CHANGELOG [6.6.11]
set -eu

NAME=tcyr_epilogue_shape
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC (axis 3 cannot run)"; exit 77; }
[ -d "$ROOT/tests/tcyr" ] || { echo "FAIL: $NAME — no tests/tcyr"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $NAME — mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
_fail() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# The rules, as ONE awk program so the mutants below are textual deletions of it.
# Prints one "FILE:LINE: rule X — why" line per violation.
LINT_AWK='
FNR == 1 { if (NR > 1) flush(); f = FILENAME; hasmain = 0; call = 0; callln = 0; exited = 0; summ = 0 }
/^fn main\(/ { hasmain = 1 }
/^(var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*)?main\(/ { if (!call) { call = 1; callln = FNR } }
call && /(^|;[ \t]*)(syscall\((60|SYS_EXIT),|sys_exit\()/ { exited = 1 } # RULE-A-EXIT
/assert_summary\(/ { summ = 1 }
summ && /^(syscall\((60|SYS_EXIT),[ \t]*0[ \t]*\)|sys_exit\([ \t]*0[ \t]*\))/ { print f ":" FNR ": rule B — exits a literal 0 after assert_summary(); exit with the summary instead" } # RULE-B
function flush() {
    if (hasmain && call && !exited) print f ":" callln ": rule A — calls main() at top level with no exit after it; the epilogue auto-calls a defined main AGAIN and exits with its value"
}
END { if (NR > 0) flush() }
'
lint() { awk "$LINT_AWK" "$@"; }

echo "axis 1: the live corpus"
find "$ROOT/tests/tcyr" -name '*.tcyr' | sort > "$D/files"
NF=$(grep -c . "$D/files" || true)
FL=$(sed -n 1p "$ROOT/tests/tcyr/CORPUS_FLOOR" 2>/dev/null || true)
case "$FL" in
    ''|*[!0-9]*) _fail "axis 1: tests/tcyr/CORPUS_FLOOR line 1 is '$FL', not a number" ;;
    *) [ "$NF" -ge "$FL" ] || _fail "axis 1: walked $NF .tcyr, the corpus floor is $FL — the walk went blind" ;;
esac
# xargs would split the batch and rerun FNR==1 per file anyway; one awk per chunk is fine.
tr '\n' '\0' < "$D/files" | xargs -0 awk "$LINT_AWK" > "$D/live" || _fail "axis 1: the lint itself failed to run"
if [ -s "$D/live" ]; then
    _fail "axis 1: $(grep -c . "$D/live") violation(s) in tests/tcyr:"
    sed "s|^$ROOT/|      |" "$D/live"
fi

echo "axis 2: staged fixtures"
mkdir -p "$D/fx"
# Bad shapes.
printf 'include "lib/assert.cyr"\nfn main() {\n    assert(1, "x");\n    return 0;\n}\n\nmain();\nvar r = assert_summary();\n' > "$D/fx/bad_twice.tcyr"
printf 'include "lib/assert.cyr"\nfn main() {\n    assert(1, "x");\n    return assert_summary();\n}\nvar ec = main();\n' > "$D/fx/bad_twice_var.tcyr"
printf 'include "lib/assert.cyr"\nassert(1, "x");\nvar r = assert_summary();\nsyscall(60, 0);\n' > "$D/fx/bad_exit0.tcyr"
printf 'include "lib/assert.cyr"\nassert(1, "x");\nvar r = assert_summary();\nsys_exit(0);\n' > "$D/fx/bad_sysexit0.tcyr"
# Good shapes (every one of these spellings is in the corpus).
printf 'include "lib/assert.cyr"\nfn main() {\n    assert(1, "x");\n    return assert_summary();\n}\nsyscall(60, main());\n' > "$D/fx/good_exit_main.tcyr"
printf 'include "lib/assert.cyr"\nfn main() {\n    assert(1, "x");\n    return assert_summary();\n}\nvar ec = main();\nsyscall(SYS_EXIT, ec);\n' > "$D/fx/good_var_exit.tcyr"
printf 'include "lib/assert.cyr"\nfn main() {\n    return assert_summary();\n}\nvar rc = main(); syscall(SYS_EXIT, rc);\n' > "$D/fx/good_same_line.tcyr"
printf 'include "lib/assert.cyr"\nfn main() {\n    return assert_summary();\n}\nvar exit_code = main();\nsys_exit(exit_code);\n' > "$D/fx/good_sys_exit.tcyr"
printf 'include "lib/assert.cyr"\nfn main() {\n    assert(1, "x");\n    return assert_summary();\n}\n' > "$D/fx/good_auto_main.tcyr"
printf 'include "lib/assert.cyr"\nassert(1, "x");\nif (0) {\n    sys_exit(0);\n}\nvar r = assert_summary();\nif (1) {\n    sys_exit(0);\n}\nsyscall(60, r);\n' > "$D/fx/good_child_exit.tcyr"
lint "$D"/fx/*.tcyr > "$D/fx.out" || _fail "axis 2: the lint failed to run on the fixtures"
_want() { grep -q "/$1.tcyr:[0-9]*: rule $2 " "$D/fx.out" || _fail "axis 2: $1.tcyr was not refused by rule $2"; }
_want bad_twice A
_want bad_twice_var A
_want bad_exit0 B
_want bad_sysexit0 B
if grep '/good_' "$D/fx.out" > "$D/fx.good"; then
    _fail "axis 2: a correct epilogue was refused:"; sed 's/^/      /' "$D/fx.good"
fi
# Mutants: delete a rule, and the fixture it exists for must then be ACCEPTED.
LINT_A=$(printf '%s\n' "$LINT_AWK" | grep -v 'RULE-A-EXIT')
LINT_B=$(printf '%s\n' "$LINT_AWK" | grep -v 'RULE-B')
# With the exit test gone, EVERY main-caller reads unexited — so the proof is that the good
# `var ec = main(); syscall(...)` fixture now reads as a violation too, i.e. the deleted line
# was the only thing telling them apart.
awk "$LINT_A" "$D/fx/good_var_exit.tcyr" > "$D/mA2.out"
[ -s "$D/mA2.out" ] || _fail "axis 2 (mutant A): deleting rule A's exit test changed nothing — the row is vacuous"
awk "$LINT_B" "$D/fx/bad_exit0.tcyr" > "$D/mB.out"
[ ! -s "$D/mB.out" ] || _fail "axis 2 (mutant B): deleting rule B still refused bad_exit0 — the row is vacuous"

echo "axis 3: the live compiler still makes these shapes exit 0 on failure"
mkdir -p "$D/live3/lib"
cp "$ROOT"/lib/*.cyr "$D/live3/lib/"
printf 'include "lib/assert.cyr"\nfn main() {\n    assert_eq(1, 1, "right");\n    assert_eq(1, 2, "deliberately wrong");\n    return 0;\n}\n\nmain();\nvar r = assert_summary();\n' > "$D/live3/twice.cyr"
printf 'include "lib/assert.cyr"\nassert_eq(1, 1, "right");\nassert_eq(1, 2, "deliberately wrong");\nvar r = assert_summary();\nsyscall(60, 0);\n' > "$D/live3/exit0.cyr"
for s in twice exit0; do
    ( cd "$D/live3" && "$CC" < "$s.cyr" > "$s.bin" 2>"$s.err" ) || { _fail "axis 3: $s.cyr does not compile"; continue; }
    chmod +x "$D/live3/$s.bin"
    rc=0; ( cd "$D/live3" && "./$s.bin" > "$s.out" 2>&1 ) || rc=$?
    last=$(grep -E '^[0-9]+ passed, [0-9]+ failed' "$D/live3/$s.out" | tail -1)
    case "$last" in
        *" 1 failed"*|*" 2 failed"*) ;;
        *) _fail "axis 3: $s printed '$last', expected a failing summary" ;;
    esac
    [ "$rc" = 0 ] || _fail "axis 3: $s exited $rc — the shape no longer exits 0 on failure; revisit rule $( [ $s = twice ] && echo A || echo B )"
done

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: $NAME: $NFAIL problem(s)"
    exit 1
fi
echo "PASS: $NAME ($NF .tcyr, floor $FL; 4 bad shapes refused, 6 good accepted, 2 mutants proven, 2 live shapes confirmed dangerous)"
exit 0
