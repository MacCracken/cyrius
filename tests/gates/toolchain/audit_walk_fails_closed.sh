#!/bin/sh
# tests/gates/toolchain/audit_walk_fails_closed.sh — 6.6.7 (bite 9)
#
# The lint and doc walkers — and every checker built on them — FAIL CLOSED when the tool
# they run does not finish.
#
# THE DEFECT. lib/audit_walk.cyr ran cyrlint / `cyrdoc --check` through `exec_capture`,
# which throws the exit status away, and took the tool's summary trailer ("<n> warnings",
# "X documented, Y undocumented (Z total)") as its ONLY signal — and a MISSING trailer
# parsed as ZERO. So a linter that crashed, hung past the deadline, refused the file or did
# not exist at all scored "0 warnings", in three independent checkers at once:
#   * `cyrius audit` printed "ok: lint clean". LIVE in rekha: fonts/face_data.cyr is 1.65 MB,
#     cyrlint refuses it (`file too large to lint (>1028KB)`, rc 1, no trailer), and its
#     header says GENERATED but not AUTO-GE, so the walker neither skipped nor linted it.
#   * the check driver's `lint (stdlib)` row, and
#   * the driver's two cyrlint fixture gates, which assert a warning marker is ABSENT over a
#     capture that also discarded the status — a crashing or refusing cyrlint prints no
#     markers, so they PASSED.
# (CI's lint step had the same shape in shell, `… | tail -1 | grep -oP '^\d+' || echo 0`;
# it now runs the driver's lint suite, i.e. the code this gate pins.)
#
# THE FIX. lib/process.cyr gains `exec_capture_status` (exit code, signal, deadline), and a
# file counts as checked only when the run exited on its own with the status its trailer
# implies AND printed that trailer. Anything else is an ERROR naming the file and why.
#
# AXES
#   A  walker × fake cyrlint: control (5 warnings) · crash after the trailer · hang past the
#      deadline · refusal (rc 1, no trailer) · missing tool · rc≠0 with a trailer · rc 0 with
#      no trailer. Every failure: ERRORS=1, TOTAL=0, the note names the file.
#   B  walker × fake cyrdoc: control (exit = the undocumented count) · crash · hang · refusal
#      · missing tool · an exit status that disagrees with the trailer.
#   C  walker × THIS tree's real cyrlint/cyrdoc: a >1028 KB non-bundle file and an EMPTY .cyr
#      are both ERRORS (cyrlint's own rc-1 refusals); a trailing-whitespace file still counts
#      1 warning and a clean one 0 (over-correction guard); cyrdoc counts an undocumented fn.
#   D  the check DRIVER's `lint` suite in a scratch root whose build/cyrlint is a fake: every
#      one of its three rows goes RED, for a killed-after-"0 warnings" fake and a refusing
#      fake; the init-order row goes RED for a fake that answers only its positive fixture
#      and dies on the three negative ones; the same root with the real cyrlint is GREEN.
#   E  `cyrius audit` over the rekha shape: rc≠0, the file named, no "ok: lint clean"; a
#      clean project still reads "ok: lint clean" / "ok: docs complete" with rc 0.
#   F  CI's lint step runs that suite (`cyrius_check lint`) and parses no trailer itself.
#
# MUTATIONS (each RED; run by hand when this gate was written)
#   m1 the lint walker back on exec_capture + the old parser (missing trailer = 0)  A,C,E
#   m2 the doc walker's verdict dropped (parse only)                                 B
#   m3 _cyrlint_count_marker back on the status-discarding capture          D1/D2 row 3, D3
#   m4 _lint_gate ignores AW_LINT_ERRORS                                    D1/D2 row 1
#   m5 `cyrius audit` ignores AW_LINT_ERRORS                                         E1
#   m6 exec_capture_status stores "exited 0" whatever happened                       A,B
#   m7 ci.yml's lint step restored to its inline `tail -1 … || echo 0` loop             F
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=audit_walk_fails_closed
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
[ -x "$ROOT/build/cycc" ] || { echo "FAIL: $NAME — build/cycc not built"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $NAME — needs timeout(1)"; exit 1; }
ulimit -c 0 2>/dev/null || :   # the crash fakes must not leave core files behind

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# A compile that fails or yields a tiny file stops the gate: cycc on empty stdin exits 0 and
# emits a runnable binary, so an unbuilt tool would otherwise score a fake PASS.
build_one() {   # $1 source, $2 dest
    if ! "$ROOT/build/cycc" < "$1" > "$2" 2> "$T/build.err"; then
        echo "FAIL: $NAME — could not build $1"; sed -n '1,5p' "$T/build.err"; exit 1
    fi
    if [ ! -s "$2" ] || [ "$(wc -c < "$2")" -lt 20000 ]; then
        echo "FAIL: $NAME — $1 produced a $(wc -c < "$2")-byte binary"; exit 1
    fi
    chmod +x "$2"
}

# ── the harness: runs one walker over one dir with one tool and a deadline ──────────────
cat > "$T/harness.cyr" <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/args.cyr"
include "lib/syscalls.cyr"
include "lib/tagged.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "lib/audit_walk.cyr"
fn main(): i64 {
    alloc_init();
    args_init();
    var dirs = vec_new();
    vec_push(dirs, str_from(argv(3)));
    proc_set_timeout_ms(atoi(argv(4)));
    var tot = 0;
    var errs = 0;
    var notes = 0;
    if (streq(argv(1), "lint") == 1) {
        audit_lint_walk(argv(2), dirs);
        tot = AW_LINT_TOTAL; errs = AW_LINT_ERRORS; notes = AW_LINT_ERROR_FILES;
    } else {
        audit_doc_walk(argv(2), dirs);
        tot = AW_DOC_TOTAL; errs = AW_DOC_ERRORS; notes = AW_DOC_ERROR_FILES;
    }
    print("TOTAL=", 6); print_num(tot); print(" ERRORS=", 8); print_num(errs); println("");
    audit_print_errors(notes);
    return 0;
}
var r = main();
syscall(60, r);
EOF
build_one "$T/harness.cyr" "$T/h"
H="$T/h"
walk() {   # $1 lint|doc  $2 tool  $3 dir  $4 deadline-ms  → $T/w.out
    timeout 20 "$H" "$1" "$2" "$3" "$4" > "$T/w.out" 2>&1 || echo "HARNESS rc=$?" >> "$T/w.out"
}
counts() { head -n 1 "$T/w.out"; }
named() {  # does the error note name file $1 with reason keyword $2?
    if grep -F -- "$1: " "$T/w.out" | grep -qF -- "$2"; then echo yes; else echo no; fi
}

# One linted file per fixture dir, so ERRORS/TOTAL are exact.
D="$T/one"; mkdir -p "$D"; printf 'fn f(): i64 { return 0; }\n' > "$D/x.cyr"
fake() {   # $1 name, $2 body → an executable fake tool
    printf '#!/bin/sh\n%s\n' "$2" > "$T/$1"; chmod +x "$T/$1"
}

# ── A — lint walker × fake cyrlint ────────────────────────────────────────────────────
fake l_ok      'echo "=== cyrlint: $1 ==="; echo "5 warnings"'
fake l_segv    'echo "0 warnings"; kill -SEGV $$'
fake l_hang    'echo "0 warnings"; exec sleep 30'
fake l_refuse  'echo "cyrlint: file too large to lint (>1028KB)"; exit 1'
fake l_rc3     'echo "0 warnings"; exit 3'
fake l_notrail 'echo "=== cyrlint: $1 ==="; echo "all good"'
walk lint "$T/l_ok" "$D" 0
check "A0 control: a finished run's trailer is summed" "TOTAL=5 ERRORS=0" "$(counts)"
walk lint "$T/l_segv" "$D" 0
check "A1 a cyrlint that CRASHES after printing '0 warnings' is an error" "TOTAL=0 ERRORS=1" "$(counts)"
check "   …named, as a crash" yes "$(named "$D/x.cyr" "crashed, signal 11")"
walk lint "$T/l_hang" "$D" 500
check "A2 a cyrlint killed at the deadline is an error" "TOTAL=0 ERRORS=1" "$(counts)"
check "   …named, as a timeout" yes "$(named "$D/x.cyr" "timed out")"
walk lint "$T/l_refuse" "$D" 0
check "A3 a cyrlint that REFUSES the file (rc 1, no trailer) is an error" "TOTAL=0 ERRORS=1" "$(counts)"
check "   …named, with its exit" yes "$(named "$D/x.cyr" "no summary line), exit 1")"
walk lint "$T/does_not_exist" "$D" 0
check "A4 a MISSING cyrlint is an error, not a clean tree" "TOTAL=0 ERRORS=1" "$(counts)"
walk lint "$T/l_rc3" "$D" 0
check "A5 a trailer with a non-zero exit is an error" "TOTAL=0 ERRORS=1" "$(counts)"
check "   …named, as a disagreement" yes "$(named "$D/x.cyr" "disagrees")"
walk lint "$T/l_notrail" "$D" 0
check "A6 rc 0 with no '<n> warnings' last line is an error" "TOTAL=0 ERRORS=1" "$(counts)"

# ── B — doc walker × fake cyrdoc ──────────────────────────────────────────────────────
fake d_ok     'echo "2 documented, 1 undocumented (3 total)"; exit 1'
fake d_segv   'echo "3 documented, 0 undocumented (3 total)"; kill -SEGV $$'
fake d_hang   'echo "3 documented, 0 undocumented (3 total)"; exec sleep 30'
fake d_refuse 'echo "cyrdoc: cannot read file: $2" >&2; exit 1'
fake d_lie    'echo "2 documented, 1 undocumented (3 total)"; exit 0'
walk doc "$T/d_ok" "$D" 0
check "B0 control: exit = the undocumented count, and it is summed" "TOTAL=1 ERRORS=0" "$(counts)"
walk doc "$T/d_segv" "$D" 0
check "B1 a crashing cyrdoc is an error" "TOTAL=0 ERRORS=1" "$(counts)"
walk doc "$T/d_hang" "$D" 500
check "B2 a cyrdoc killed at the deadline is an error" "TOTAL=0 ERRORS=1" "$(counts)"
walk doc "$T/d_refuse" "$D" 0
check "B3 a cyrdoc that refuses the file is an error" "TOTAL=0 ERRORS=1" "$(counts)"
walk doc "$T/does_not_exist" "$D" 0
check "B4 a MISSING cyrdoc is an error" "TOTAL=0 ERRORS=1" "$(counts)"
walk doc "$T/d_lie" "$D" 0
check "B5 an exit that disagrees with the trailer is an error" "TOTAL=0 ERRORS=1" "$(counts)"

# ── C — the REAL tools, built from this tree ─────────────────────────────────────────
build_one "$ROOT/programs/cyrlint.cyr" "$T/cyrlint"
build_one "$ROOT/programs/cyrdoc.cyr" "$T/cyrdoc"
C="$T/real"; mkdir -p "$C"
printf '# clean\nfn clean(): i64 {\n    return 0;\n}\n' > "$C/clean.cyr"
printf '# ws\nfn ws(): i64 {\n    return 0; \n}\n' > "$C/ws.cyr"
: > "$C/empty.cyr"
# 'GENERATED' but not the walker's AUTO-GE marker — rekha's header shape, so it is linted.
awk 'BEGIN { print "# GENERATED, do not hand-edit"; for (i = 0; i < 40000; i++) print "var big_" i " = 1234567890;" }' > "$C/big.cyr"
check "C0 (premise: big.cyr is past cyrlint's 1028 KB limit)" yes "$([ "$(wc -c < "$C/big.cyr")" -gt 1052672 ] && echo yes || echo no)"
walk lint "$T/cyrlint" "$C" 0
check "C1 real cyrlint: 1 warning counted, the >1028 KB file and the empty file are ERRORS" "TOTAL=1 ERRORS=2" "$(counts)"
check "   …the too-large refusal is named" yes "$(named "$C/big.cyr" "exit 1")"
check "   …the empty-file refusal is named" yes "$(named "$C/empty.cyr" "exit 1")"
D2="$T/docs"; mkdir -p "$D2"
printf '# has a doc\nfn a(): i64 { return 0; }\nfn b(): i64 { return 0; }\n' > "$D2/d.cyr"
walk doc "$T/cyrdoc" "$D2" 0
check "C2 real cyrdoc: the undocumented fn is counted and the run is trusted" "TOTAL=1 ERRORS=0" "$(counts)"

# ── D — the check driver's lint suite ────────────────────────────────────────────────
build_one "$ROOT/programs/checks/main.cyr" "$T/chk"
R="$T/root"; mkdir -p "$R/build"
ln -s "$ROOT/lib" "$R/lib"
ln -s "$ROOT/tests" "$R/tests"
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
ROW1="lint (stdlib)"
ROW2="cyrlint flags forward-ref var inits (v5.7.32; mabda-surfaced)"
ROW3="cyrlint clean on 7K-line synthetic (mabda 2026-04-28 repro shape; v5.8.41 floor)"
row() {   # $1 PASS|FAIL, $2 row name → yes/no
    if strip < "$T/d.out" | grep -qxF -- "  $1: $2"; then echo yes; else echo no; fi
}
drive() {   # $1 the cyrlint to install
    rm -f "$R/build/cyrlint"; cp "$1" "$R/build/cyrlint"
    DRC=0
    ( cd "$R" && HOME="$T/nohome" timeout 120 "$T/chk" lint ) > "$T/d.out" 2>&1 || DRC=$?
}
# SIGKILL, not SIGSEGV: the driver runs this once per lib/ file, and a coredump handler
# turns ~250 segfaults into ~12 s. A signal death is a signal death to the verdict.
fake k_kill 'echo "=== cyrlint: $1 ==="; echo "0 warnings"; kill -KILL $$'
drive "$T/k_kill"
check "D1 killed-after-'0 warnings': the suite exits non-zero" yes "$([ "$DRC" -ne 0 ] && [ "$DRC" -ne 124 ] && echo yes || echo no)"
check "   …row '$ROW1' is RED" yes "$(row FAIL "$ROW1")"
check "   …row '${ROW2%%(*}' is RED" yes "$(row FAIL "$ROW2")"
check "   …row '${ROW3%%(*}' is RED" yes "$(row FAIL "$ROW3")"
fake k_refuse 'echo "=== cyrlint: $1 ==="; echo "cyrlint: file too large to lint (>1028KB)"; exit 1'
drive "$T/k_refuse"
check "D2 a refusing cyrlint: the suite exits non-zero" yes "$([ "$DRC" -ne 0 ] && [ "$DRC" -ne 124 ] && echo yes || echo no)"
check "   …row '$ROW1' is RED" yes "$(row FAIL "$ROW1")"
check "   …row '${ROW2%%(*}' is RED" yes "$(row FAIL "$ROW2")"
check "   …row '${ROW3%%(*}' is RED" yes "$(row FAIL "$ROW3")"
# The init-order gate's NEGATIVE rows (0 false positives on lib/math.cyr, lib/string.cyr and
# the string-literal fixture) were guarded only by the crash ALSO hitting its positive
# fixture. This fake answers the positive fixture correctly and dies on everything else, so
# only the fail-closed count can turn the row red.
fake k_sel 'case "$1" in
*forward_refs.cyr) echo "=== cyrlint: $1 ==="; for i in 1 2 3; do echo "  warn line $i: global var init refs x" >&2; done; echo "3 warnings" ;;
*) echo "0 warnings"; kill -KILL $$ ;;
esac'
drive "$T/k_sel"
check "D3 a cyrlint that dies on every file but the positive fixture: '${ROW2%%(*}' is RED" yes "$(row FAIL "$ROW2")"
drive "$T/cyrlint"
check "D4 positive control: the real cyrlint, same root — GREEN" "0" "$DRC"
check "   …all three rows PASS" "yes yes yes" "$(row PASS "$ROW1") $(row PASS "$ROW2") $(row PASS "$ROW3")"

# ── E — `cyrius audit` over the rekha shape ──────────────────────────────────────────
B="$T/bin"; mkdir -p "$B" "$T/hh"
build_one "$ROOT/cbt/cyrius.cyr" "$B/cyrius"
build_one "$ROOT/programs/cyrfmt.cyr" "$B/cyrfmt"
cp "$T/cyrlint" "$B/cyrlint"; cp "$T/cyrdoc" "$B/cyrdoc"; cp "$ROOT/build/cycc" "$B/cycc"
audit() {   # $1 project dir → $T/a.out, ARC
    ARC=0
    ( cd "$1" && HOME="$T/hh" CYRIUS_HOME="$T/cyhome" timeout 120 "$B/cyrius" audit ) > "$T/a.out" 2>&1 || ARC=$?
}
P="$T/proj"; mkdir -p "$P/src"
printf '[package]\nname = "p"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
printf '# ok\nfn main(): i64 {\n    return 0;\n}\n' > "$P/src/main.cyr"
audit "$P"
check "E0 control: a clean project reads 'ok: lint clean'" yes "$(grep -qF 'ok: lint clean' "$T/a.out" && echo yes || echo no)"
check "   …and 'ok: docs complete', rc 0" "yes 0" "$(grep -qF 'ok: docs complete' "$T/a.out" && echo yes || echo no) $ARC"
cp "$C/big.cyr" "$P/src/face_data.cyr"
audit "$P"
check "E1 rekha shape: cyrius audit exits non-zero" yes "$([ "$ARC" -ne 0 ] && [ "$ARC" -ne 124 ] && echo yes || echo no)"
check "   …and never says 'ok: lint clean'" no "$(grep -qF 'ok: lint clean' "$T/a.out" && echo yes || echo no)"
check "   …and names the file it did not lint" yes "$(grep -qF 'src/face_data.cyr: ' "$T/a.out" && echo yes || echo no)"

# ── F — CI's lint step is the driver's suite, not an inline re-implementation ─────────
# Read the step's own `run:` block (from its `- name:` line to the next one).
CIY="$ROOT/.github/workflows/ci.yml"
awk '/- name: Lint \(stdlib\)/ { on = 1; next } on && /- name:|^  [a-z]/ { on = 0 } on' "$CIY" \
    | grep -v '^ *#' > "$T/ci_lint"
check "F1 CI's 'Lint (stdlib)' step runs the check driver's lint suite" yes "$(grep -qF './build/cyrius_check lint' "$T/ci_lint" && echo yes || echo no)"
check "   …and parses no trailer itself (no '|| echo 0', no 'tail -1')" no "$(grep -qE 'echo 0|tail -1' "$T/ci_lint" && echo yes || echo no)"

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: $NAME — $checks checks"
exit 0
