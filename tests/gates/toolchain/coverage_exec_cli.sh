#!/bin/sh
# coverage_exec_cli.sh — 6.7.10 (P5-B). `cyrius coverage --exec[=<glob>]` / `[coverage] exec`:
# EXECUTION coverage. Every tests/**/*.tcyr (as `cyrius test` builds, runs and grades it) and every
# RUN program the globs name (as `cyrius run` builds it) is compiled with CYRIUS_COVERAGE=1 and a
# CYRIUS_COVERAGE_FILE of its own, run, and its dump read: a public fn of the measured tree counts
# as executed once a run records entering it — by NAME, the identifier-set model the reference count
# uses. `[coverage] programs` stays TEXT coverage in both modes (the user's decision, 2026-10-12).
#
# WHY: reference coverage counts a fn a test merely NAMES (ok_test.cyr below names sh_d in a branch
# it never takes, and its own `shapes` — reference coverage reads 7/7); execution coverage counts
# what ran (5/7). A run that fails — a nonzero exit, a signal, a timeout, or an exit 0 with no
# coverage record (an asm exit the dump cannot see) — is named and fails the run, after the report.
#
# The fixture is tests/fixtures/coverage_exec/ (rekha-shaped: src/ + programs/*_test.cyr + one
# .tcyr), copied to a scratch directory; its tests/tcyr/t.tcyr.in is renamed t.tcyr there (a .tcyr
# under this repo's tests/ would join this repo's own `cyrius test` corpus). The tree CLI runs with
# CYRIUS_HOME staged to the tree compiler and lib/, and a private TMPDIR.
#
# ROWS
#   X1  --exec=programs/ok_test.cyr -v: rc 0; `Functions executed: 5/7 (71%)` (sh_a, sh_b, sh_inl
#       (an #inline replay), sh_gen (a generic instance, `sh_gen$i`) from ok_test; sh_c from t.tcyr);
#       the mode / files / reference lines byte-identical to the text run's; -v lists exactly sh_d
#       and shapes as unexecuted; `1/7 fns, 5/7 executed` per file
#   X2  `[coverage] exec = ["programs/*_test.cyr"]`, no flag: the mode is on; rc 1; bad_test (exit 1)
#       and asm_test (no record) named in `cyrius test`'s FAIL wording; the report still printed,
#       `Corpus runs: 4 (1 .tcyr, 3 program(s)), 2 failed`. X2b: an exec glob that matches nothing
#       and a missing exec program are named failures
#   X3  no --exec, no key: stdout byte-identical to the 6.7.9 CLI's (two goldens: a plain run, and
#       -v --per-entry --programs --min 50); nothing resolved (no lib/, no cyrius.lock)
#   X4  .tcyr are executed: sh_c is entered only by t.tcyr — executed with it, unexecuted (4/7)
#       without tests/
#   X5  `shapes` — a component of every record's path (src/shapes.cyr), and ok_test's OWN `shapes`
#       (a `<source>` record; premise checked in the dump) — never marks src's `shapes` executed
#   X6  asm_test.cyr exits 0 (premise) through an asm exit_group: "exited 0 but left no coverage
#       record", rc 1
#   X7  `[coverage] programs` alone stays text: no exec line, no executed figure, nothing built
#   X8  --min gates the EXECUTED %: 60 passes (`71% executed >= --min 60%`), 80 fails naming the
#       unexecuted fns
#   X9  programs/sub/deep_test.cyr spells its include `./src/shapes.cyr` (premise: its record's
#       path is that spelling): its sh_d counts (6/7, `shapes` the one miss)
#   X10 `[coverage] exec = 3` refused by name, nothing built
#   X11 a TMPDIR long enough that the dump path is over 255 bytes: refused by name, nothing built
#   X12 no temp leftovers in the private TMPDIR after the runs
#   X13 `cyrius help manifest` lists `[coverage] exec read - - --exec`; `build --print-config` shows
#       coverage.exec with its origin (manifest / default)
#   X14 nothing to run (no .tcyr, bare --exec, no exec list): a named failure, not a 0% pass
#   W1  (wine) the Windows arm: cyrius.exe hands cycc.exe both variables (the program is
#       instrumented and its dump read: 1/2 executed), and the program run next sees neither
#       (it exits 1 / 2 / 3 when GetEnvironmentVariableA finds one)
#   XH  (static) every host scripts/release-gate.sh's step 4 walks has a leg in
#       scripts/cross-os-selfhost.sh that runs X1 and X2 on the hardware (_co_cov_stage, its X1 run,
#       `_co_cov_check <host>`) and fails as `SELFHOST_FAIL: <host> — coverage --exec`; the checker
#       still grades X1's exit 0 and exact 5/7, and X2's exit 1 and named bad_test failure
#
# MUTANTS (each measured RED in a scratch copy, 2026-10-12; the rows each turned RED):
#   N1  the coverage entries not injected (_cc_flag_inject)       X1 X2 X4 X8 X9 W1 (no record)
#   N2  a program's exit code ignored                              X2
#   N3  the exec text printed in text mode                         X3 X7
#   N4  the .tcyr skipped                                          X1 X4 X8 X9
#   N5  the header check removed                                   X2 X6
#   N6  --min reads the reference %                                X8
#   N7  the whole record line tokenised into the set               X1 X5 (+ X2 X4 X8 X9)
#   N8  no `$` cut                                                  X1 (sh_gen) (+ X2 X4 X8 X9)
#   N9  `<source>` records not skipped                             X1 X5 (+ X2 X4 X8 X9)
#   N10 no Windows delete after the compile                        W1 (the program exits 3)
#   N11 the AUTO_DEPS conditional removed                          X1 (undefined stdlib fns) X2 X4 X6
#       X8 X9; auto_deps_verb_gate.sh axis 2
#   NH1 the ach leg's coverage step deleted                        XH (stage, check, SELFHOST_FAIL, run)
#   NH2 the cass leg's X1 run deleted                              XH
#   NH3 _co_cov_check's 5/7 weakened to a prefix                   XH
#   NH4 a fifth host added to release-gate.sh's loop, no leg       XH
#   NH5 _co_cov_check's X2 exit-code grade deleted                 XH
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: coverage_exec_cli: no compiler at $CC"; exit 77; }
FIX="$ROOT/tests/fixtures/coverage_exec"
[ -f "$FIX/src/shapes.cyr" ] && [ -f "$FIX/tests/tcyr/t.tcyr.in" ] || { echo "FAIL: coverage_exec_cli: the fixture $FIX is missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: coverage_exec_cli: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$W/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
show() { sed 's/^/      /' "$W/out" | head -14; sed 's/^/      err: /' "$W/err" | grep -v 'unreachable fns' | head -8; }

"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: coverage_exec_cli: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
mkdir -p "$W/home/bin" "$W/tmp"
cp "$CC" "$W/home/bin/cycc" && chmod +x "$W/home/bin/cycc"
cp -r "$ROOT/lib" "$W/home/lib"

# fx [<extra manifest text>] — a fresh copy of the fixture in $W/p (t.tcyr.in -> t.tcyr)
fx() {
    rm -rf "$W/p"
    cp -r "$FIX" "$W/p"
    mv "$W/p/tests/tcyr/t.tcyr.in" "$W/p/tests/tcyr/t.tcyr"
    [ -n "${1:-}" ] && printf '%b' "$1" >> "$W/p/cyrius.cyml"
    return 0
}
# cov <args...> — the tree CLI's `coverage` in $W/p: stdout $W/out, stderr $W/err, status RC
cov() {
    RC=0
    ( cd "$W/p" && env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE -u CYRIUS_TEST_TIMEOUT -u CYRIUS_BOUNDS -u CYRIUS_DCE -u CYRIUS_DEFINES \
        TMPDIR="${COV_TMP:-$W/tmp}" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 600 "$W/cyrius" coverage "$@" ) > "$W/out" 2> "$W/err" || RC=$?
}
# dump <program> — build and run one fixture program with the mode on through `cyrius run`; its
# dump in $W/dump (the premise rows read what the CLI's reader is handed)
dump() {
    rm -f "$W/dump"
    ( cd "$W/p" && env -u CYRIUS_TEST_TIMEOUT CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$W/dump" TMPDIR="$W/tmp" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 "$W/cyrius" run "$1" ) > /dev/null 2>&1 || true
}
line() { grep -F "$1" "$W/out" | head -1; }

# ── X3: the text mode, byte-identical to 6.7.9 (goldens taken from the 6.7.9 CLI) ─────────────
cat > "$W/golden1" <<'EOF'
=== Coverage Report ===
  mode: local repo sources (src/, recursive); reference coverage

  shapes.cyr                        1/7 fns

-- Summary --
  Files referenced:   1/1
  Functions referenced: 1/7 (14%)  [reference coverage — a floor, not a correctness proof]
EOF
cat > "$W/golden2" <<'EOF'
=== Coverage Report ===
  mode: local repo sources (src/, recursive); reference coverage
  corpus: tests/**/*.tcyr + 3 RUN program(s), as text (references, not execution)

  shapes.cyr                        7/7 fns

-- Summary --
  Files referenced:   1/1
  Functions referenced: 7/7 (100%)  [reference coverage — a floor, not a correctness proof]

-- Unreferenced (0) --

-- References by corpus entry --
  tests/tcyr/t.tcyr: 1 of 7 public fns
      src/shapes.cyr: sh_c
  programs/asm_test.cyr: 1 of 7 public fns
      src/shapes.cyr: sh_b
  programs/bad_test.cyr: 1 of 7 public fns
      src/shapes.cyr: sh_c
  programs/ok_test.cyr: 6 of 7 public fns
      src/shapes.cyr: sh_a
      src/shapes.cyr: sh_b
      src/shapes.cyr: sh_d
      src/shapes.cyr: sh_inl
      src/shapes.cyr: sh_gen
      src/shapes.cyr: shapes
  gate OK: 100% >= --min 50%
EOF
x=$FAIL
fx
cov
[ "$RC" = 0 ] && cmp -s "$W/out" "$W/golden1" || { fail "X3: a plain text run (rc $RC) is not 6.7.9's stdout:"; diff "$W/golden1" "$W/out" | head -8; }
cp "$W/out" "$W/text1"
cov -v --per-entry --programs 'programs/*_test.cyr' --min 50
[ "$RC" = 0 ] && cmp -s "$W/out" "$W/golden2" || { fail "X3: a -v --per-entry --programs --min run (rc $RC) is not 6.7.9's stdout:"; diff "$W/golden2" "$W/out" | head -8; }
[ -e "$W/p/lib" ] || [ -e "$W/p/cyrius.lock" ] && fail "X3: the text mode resolved dependencies (lib/ or cyrius.lock written)"
[ "$FAIL" = "$x" ] && echo "  ok X3: the text mode prints 6.7.9's stdout byte for byte (2 goldens) and resolves nothing"

# ── X1 + X4 + X5 + X12: one program executed ──────────────────────────────────────────────────
x=$FAIL
fx
cov --exec=programs/ok_test.cyr -v
cp "$W/out" "$W/x1out"
if [ "$RC" = 0 ] && grep -qx '  Functions executed: 5/7 (71%)  \[execution coverage — entered at least once by a corpus run\]' "$W/out"; then :
else fail "X1: rc $RC, want 0 and 'Functions executed: 5/7 (71%)':"; show; fi
grep -qx '  shapes.cyr                        1/7 fns, 5/7 executed' "$W/out" || fail "X1: no '1/7 fns, 5/7 executed' per-file line"
for l in '  mode: local repo sources (src/, recursive); reference coverage' '  Files referenced:   1/1' \
         '  Functions referenced: 1/7 (14%)  [reference coverage — a floor, not a correctness proof]'; do
    grep -qxF "$l" "$W/text1" && grep -qxF "$l" "$W/out" || fail "X1: the reference line '$l' differs from the text run's"
done
grep -qx '  exec: tests/\*\*/\*.tcyr + 1 RUN program(s), built instrumented and run (execution coverage)' "$W/out" || fail "X1: no exec line naming 1 program"
unx=$(sed -n '/^-- Unexecuted (/,$p' "$W/out" | grep '^  src/' | tr '\n' ';')
[ "$unx" = "  src/shapes.cyr: sh_d;  src/shapes.cyr: shapes;" ] && grep -qx -- '-- Unexecuted (2) --' "$W/out" \
    || fail "X1: -v must list exactly sh_d and shapes as unexecuted, got '$unx'"
[ "$FAIL" = "$x" ] && echo "  ok X1: --exec=programs/ok_test.cyr — 5/7 executed (sh_a sh_b sh_inl sh_gen + t.tcyr's sh_c), the reference lines as text mode prints them, -v names sh_d and shapes"
x=$FAIL
sed -n '/^-- Unexecuted (/,$p' "$W/out" | grep -q 'sh_c$' && fail "X4: sh_c (entered only by t.tcyr) listed unexecuted"
rm -rf "$W/p/tests"
cov --exec=programs/ok_test.cyr -v
grep -qx '  Functions executed: 4/7 (57%)  \[execution coverage — entered at least once by a corpus run\]' "$W/out" && sed -n '/^-- Unexecuted (/,$p' "$W/out" | grep -q 'src/shapes.cyr: sh_c$' \
    || { fail "X4: without tests/, sh_c should be the extra miss (4/7)"; show; }
[ "$FAIL" = "$x" ] && echo "  ok X4: .tcyr are executed — sh_c counts through t.tcyr, and is a miss (4/7) without it"
x=$FAIL
fx
dump programs/ok_test.cyr
grep -qE '^1 <source>:[0-9]+ shapes$' "$W/dump" && grep -qE '^[1-9][0-9]* src/shapes\.cyr:[0-9]+ sh_a$' "$W/dump" \
    || { fail "X5 premise: ok_test's dump holds no '<source> ... shapes' record or no src/shapes.cyr path"; sed 's/^/      /' "$W/dump" 2>/dev/null | head -8; }
sed -n '/^-- Unexecuted (/,$p' "$W/x1out" | grep -q '^  src/shapes.cyr: shapes$' \
    || fail "X5: src/shapes.cyr's \`shapes\` read as executed — a record's path or a <source> fn of that name counted"
[ "$FAIL" = "$x" ] && echo "  ok X5: \`shapes\` — every record's path component, and ok_test's own <source> \`shapes\` (in its dump) — never marks src's shapes executed"
x=$FAIL
left=$(find "$W/tmp" -mindepth 1 2>/dev/null | head -3)
[ -z "$left" ] || fail "X12: temp leftovers in the private TMPDIR: $left"
[ "$FAIL" = "$x" ] && echo "  ok X12: the runs leave nothing in the private TMPDIR"

# ── X2: [coverage] exec, no flag ──────────────────────────────────────────────────────────────
x=$FAIL
fx '\n[coverage]\nexec = ["programs/*_test.cyr"]\n'
cov
[ "$RC" = 1 ] || { fail "X2: [coverage] exec with a failing program exited $RC, not 1"; show; }
grep -qx '  FAIL: programs/bad_test.cyr (exit 1)' "$W/err" || fail "X2: bad_test.cyr's exit 1 is not named"
grep -q '^  FAIL: programs/asm_test.cyr (exited 0 but left no coverage record' "$W/err" || fail "X2: asm_test.cyr's missing record is not named"
grep -qx '  Corpus runs: 4 (1 .tcyr, 3 program(s)), 2 failed' "$W/out" && grep -q '^  Functions executed: 5/7' "$W/out" \
    || { fail "X2: the report was not printed in full (want 4 runs, 2 failed, 5/7)"; show; }
grep -q 'error: coverage --exec: 2 of 4 corpus run(s) failed' "$W/err" || fail "X2: no closing error naming 2 of 4 failed runs"
[ "$FAIL" = "$x" ] && echo "  ok X2: [coverage] exec alone turns the mode on; bad_test (exit 1) and asm_test (no record) are named, the report is printed, rc 1"
x=$FAIL
fx
cov --exec='programs/nope_*.cyr'
[ "$RC" -ne 0 ] && grep -q 'coverage: this exec glob matches no file: programs/nope_\*.cyr' "$W/err" || { fail "X2b: an exec glob matching nothing was not a named failure (rc $RC)"; show; }
cov --exec=programs/missing_test.cyr
[ "$RC" -ne 0 ] && grep -q 'no such program (--exec / \[coverage\] exec): programs/missing_test.cyr' "$W/err" || { fail "X2b: a missing exec program was not a named failure (rc $RC)"; show; }
[ "$FAIL" = "$x" ] && echo "  ok X2b: an exec glob that matches nothing and a missing exec program are named failures"

# ── X6: the asm exit leaves no record ─────────────────────────────────────────────────────────
x=$FAIL
fx
prc=0; ( cd "$W/p" && TMPDIR="$W/tmp" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 "$W/cyrius" run programs/asm_test.cyr ) > /dev/null 2>&1 || prc=$?
[ "$prc" = 0 ] || fail "X6 premise: asm_test.cyr built plain exits $prc, not 0"
cov --exec=programs/asm_test.cyr
[ "$RC" = 1 ] && grep -q '^  FAIL: programs/asm_test.cyr (exited 0 but left no coverage record' "$W/err" || { fail "X6: an exit 0 with no record was not a named failure (rc $RC)"; show; }
[ "$FAIL" = "$x" ] && echo "  ok X6: asm_test.cyr exits 0 through an asm exit_group — 'exited 0 but left no coverage record', rc 1"

# ── X7: [coverage] programs alone stays text ──────────────────────────────────────────────────
x=$FAIL
fx '\n[coverage]\nprograms = ["programs/*_test.cyr"]\n'
cov
[ "$RC" = 0 ] && grep -q '^  Functions referenced: 7/7' "$W/out" || { fail "X7: [coverage] programs alone: rc $RC, want the text 7/7"; show; }
grep -q 'executed\|^  exec:' "$W/out" && fail "X7: [coverage] programs alone turned the exec mode on"
[ -e "$W/p/lib" ] || [ -e "$W/p/cyrius.lock" ] && fail "X7: [coverage] programs alone resolved dependencies (a build was prepared)"
[ "$FAIL" = "$x" ] && echo "  ok X7: [coverage] programs alone stays TEXT coverage (no exec line, nothing resolved or built)"

# ── X8: --min gates the executed percentage ───────────────────────────────────────────────────
x=$FAIL
fx
cov --exec=programs/ok_test.cyr --min 60
[ "$RC" = 0 ] && grep -qx '  gate OK: 71% executed >= --min 60%' "$W/out" || { fail "X8: --min 60 over 71% executed: rc $RC"; show; }
cov --exec=programs/ok_test.cyr --min 80
[ "$RC" = 1 ] && grep -qx 'coverage gate FAILED: 71% executed < --min 80%' "$W/err" || { fail "X8: --min 80 over 71% executed did not fail (rc $RC)"; show; }
sed -n '/^-- Unexecuted (/,$p' "$W/out" | grep -q 'src/shapes.cyr: sh_d$' || fail "X8: a failed --min did not name the unexecuted fns"
[ "$FAIL" = "$x" ] && echo "  ok X8: --min gates the executed % (71: 60 passes; 80 fails naming the misses)"

# ── X9: a different include spelling still counts by name ─────────────────────────────────────
x=$FAIL
fx
dump programs/sub/deep_test.cyr
grep -qE '^1 \./src/shapes\.cyr:[0-9]+ sh_d$' "$W/dump" || { fail "X9 premise: deep_test's record is not './src/shapes.cyr:<line> sh_d'"; sed 's/^/      /' "$W/dump" 2>/dev/null | head -4; }
cov --exec=programs/ok_test.cyr --exec=programs/sub/deep_test.cyr -v
[ "$RC" = 0 ] && grep -q '^  Functions executed: 6/7' "$W/out" && [ "$(sed -n '/^-- Unexecuted (/,$p' "$W/out" | grep -c '^  src/')" = 1 ] \
    || { fail "X9: deep_test.cyr's sh_d did not count (want 6/7, shapes the one miss)"; show; }
[ "$FAIL" = "$x" ] && echo "  ok X9: programs/sub/deep_test.cyr's './src/shapes.cyr' record counts by name (6/7)"

# ── X10 + X11 + X14: refusals before anything is built ───────────────────────────────────────
x=$FAIL
fx '\n[coverage]\nexec = 3\n'
cov
[ "$RC" -ne 0 ] && grep -q 'cyrius.cyml \[coverage\] exec must be a glob or an array of globs' "$W/err" || { fail "X10: [coverage] exec = 3 was not refused by name (rc $RC)"; show; }
grep -q 'Functions' "$W/out" && fail "X10: a refused [coverage] exec still reported"
[ "$FAIL" = "$x" ] && echo "  ok X10: [coverage] exec = 3 is refused by name"
x=$FAIL
fx
LT="$W/tmp/$(printf 'L%.0s' $(seq 1 120))/$(printf 'M%.0s' $(seq 1 120))"
mkdir -p "$LT"
COV_TMP=$LT cov --exec=programs/ok_test.cyr
[ "$RC" -ne 0 ] && grep -q 'the coverage dump path is over 255 bytes' "$W/err" || { fail "X11: a dump path past 255 bytes was not refused by name (rc $RC)"; show; }
grep -q 'Functions executed' "$W/out" && fail "X11: the over-long dump path still ran the corpus"
rm -rf "$W/tmp"/L*
[ "$FAIL" = "$x" ] && echo "  ok X11: a TMPDIR that puts the dump path past 255 bytes is refused by name before any build"
x=$FAIL
fx
rm -rf "$W/p/tests"
cov --exec
[ "$RC" -ne 0 ] && grep -q 'coverage --exec: nothing to run' "$W/err" || { fail "X14: an exec run with nothing to run was not a named failure (rc $RC)"; show; }
[ "$FAIL" = "$x" ] && echo "  ok X14: an exec run with no .tcyr and no program is a named failure, not a 0% pass"

# ── X13: the vocabulary and --print-config ────────────────────────────────────────────────────
x=$FAIL
"$W/cyrius" help manifest > "$W/out" 2>&1
grep -qE '^  \[coverage\] +exec +read +- +- +--exec +cyrius coverage --exec:' "$W/out" || fail "X13: 'cyrius help manifest' does not list [coverage] exec"
fx '\n[coverage]\nexec = ["programs/*_test.cyr"]\n'
( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_BOUNDS -u CYRIUS_DEFINES CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" build --print-config ) > "$W/out" 2>&1 || true
grep -qxF '  coverage.exec = ["programs/*_test.cyr"]  (manifest: [coverage] exec)' "$W/out" || { fail "X13: --print-config does not show coverage.exec from the manifest"; grep coverage "$W/out" | head -3; }
fx
( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_BOUNDS -u CYRIUS_DEFINES CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" build --print-config ) > "$W/out" 2>&1 || true
grep -qxF '  coverage.exec = []  (default)' "$W/out" || fail "X13: --print-config does not show coverage.exec's default"
[ "$FAIL" = "$x" ] && echo "  ok X13: 'cyrius help manifest' lists [coverage] exec; --print-config shows coverage.exec with its origin"

# ── W1: the Windows arm, under wine ───────────────────────────────────────────────────────────
x=$FAIL
if ! command -v wine >/dev/null 2>&1; then
    echo "  SKIP W1: wine is not installed — the Windows arm's coverage rows did not run (cass, P5B-7, is the hardware leg)"
    GATE_SKIPS=1
else
    mkdir -p "$W/whome"
    export WINEPREFIX="$WP" HOME="$W/whome" XDG_CACHE_HOME="$W/whome/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    mkdir -p "$W/wh/bin" "$W/wp/src" "$W/wp/programs"
    if "$CC" < src/main_win.cyr > "$W/cc_win" 2>/dev/null && chmod +x "$W/cc_win" \
        && "$W/cc_win" < cbt/cyrius.cyr > "$W/wh/bin/cyrius.exe" 2>/dev/null && [ -s "$W/wh/bin/cyrius.exe" ] \
        && "$W/cc_win" < src/main_win.cyr > "$W/wh/bin/cycc.exe" 2>/dev/null && [ -s "$W/wh/bin/cycc.exe" ]; then
        printf '[package]\nname = "w"\nversion = "0.1.0"\n' > "$W/wp/cyrius.cyml"
        printf 'fn w_a(): i64 { return 0; }\n\nfn w_b(): i64 { return 1; }\n' > "$W/wp/src/w.cyr"
        cat > "$W/wp/programs/env_test.cyr" <<'CYR'
# Exits 1 / 2 / 3 when it can see CYRIUS_COVERAGE / CYRIUS_COVERAGE_FILE: the Windows arm sets
# them on cyrius.exe's own environment for the compiler, and must delete them before this runs.
include "src/w.cyr"

fn seen(name): i64 {
    var b: i64[40];
    return syscall(0xF015, name, &b, 300);
}

var bad = 0;
if (seen("CYRIUS_COVERAGE") != 0) { bad = bad + 1; }
if (seen("CYRIUS_COVERAGE_FILE") != 0) { bad = bad + 2; }
var r = w_a() + bad;
syscall(60, r);
CYR
        wine cmd /c exit 0 > /dev/null 2>&1 || true
        wrc=0
        ( cd "$W/wp" && env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE -u CYRIUS_TEST_TIMEOUT CYRIUS_HOME="$W/wh" CYRIUS_RESOLVED=1 timeout 600 wine "$W/wh/bin/cyrius.exe" coverage --exec=programs/env_test.cyr ) > "$W/out" 2> "$W/err" || wrc=$?
        tr -d '\r' < "$W/out" > "$W/out.u" && mv "$W/out.u" "$W/out"
        tr -d '\r' < "$W/err" > "$W/err.u" && mv "$W/err.u" "$W/err"
        [ "$wrc" = 0 ] && grep -q '^  Functions executed: 1/2 (50%)' "$W/out" \
            || { fail "W1: cyrius.exe coverage --exec under wine: rc $wrc, want 0 and 1/2 executed (exit 1/2/3 = the program saw CYRIUS_COVERAGE / _FILE; no record = the compiler was not handed the mode)"; show; }
    else
        fail "W1: could not build the PE cross compiler, cyrius.exe or cycc.exe"
    fi
    [ "$FAIL" = "$x" ] && echo "  ok W1: (wine) cyrius.exe hands cycc.exe the coverage mode (1/2 executed) and the program run next sees neither variable"
fi

# ── XH: every hardware leg runs X1 and X2 (static: this reads scripts/cross-os-selfhost.sh) ──────
# The hardware legs (release-gate step 4) are the only RUN of the Darwin open, arm64 Mach-O's rows,
# the two Mach-O forks' `_cov_tail` line and Windows' append open. A leg that drops the coverage step
# reads green on exactly the host that lacks it (the one-host-missed shape cross_os_legs_cx_parity.sh
# guards for cx). Each host release-gate.sh walks must stage the fixture, check X1 / X2's output
# under its own name and fail as `SELFHOST_FAIL: <host> — coverage --exec`. The checker must still
# grade X1's exit 0 and exact 5/7 and X2's exit 1 and named bad_test failure, and the X1 run must
# still be `--exec=programs/ok_test.cyr -v` in both the POSIX runner and the cass leg.
x=$FAIL
CO="$ROOT/scripts/cross-os-selfhost.sh"
HOSTS=$(sed -n 's/^for H in \([a-z0-9 ]*\); do$/\1/p' "$ROOT/scripts/release-gate.sh" | head -1)
coleg() { awk -v h="  $1)" '$0 == h { on = 1; next } on && /^    ;;$/ { exit } on { print }' "$CO"; }
cofn() { awk -v f="$1() {" '$0 == f { on = 1 } on { print } on && /^}$/ { exit }' "$CO"; }
nh=0
for h in $HOSTS; do
    L=$(coleg "$h")
    [ -n "$L" ] || { fail "XH: $CO has no '  $h)' leg"; continue; }
    printf '%s\n' "$L" | grep -q '^ *_co_cov_stage ' || fail "XH: the $h leg stages no coverage fixture (_co_cov_stage)"
    printf '%s\n' "$L" | grep -q "_co_cov_check $h '" || fail "XH: the $h leg does not check X1 / X2's output (_co_cov_check $h)"
    printf '%s\n' "$L" | grep -qF "SELFHOST_FAIL: $h — coverage --exec" || fail "XH: the $h leg's coverage failure is not named 'SELFHOST_FAIL: $h — coverage --exec'"
    if [ "$h" = cass ]; then
        printf '%s\n' "$L" | grep -qF -- '--exec=programs/ok_test.cyr -v' || fail "XH: the cass leg does not run X1 (--exec=programs/ok_test.cyr -v)"
    else
        printf '%s\n' "$L" | grep -q "_co_cov_posix $h " || fail "XH: the $h leg does not run X1 / X2 (_co_cov_posix $h)"
    fi
    nh=$((nh + 1))
done
[ "$nh" -ge 4 ] || fail "XH: only $nh host leg(s) read from release-gate.sh's step 4 ($HOSTS) — expected at least ecb ach cass pi"
cofn _co_cov_posix | grep -qF -- "' --exec=programs/ok_test.cyr -v" || fail "XH: _co_cov_posix does not run X1 (--exec=programs/ok_test.cyr -v)"
CK=$(cofn _co_cov_check)
printf '%s\n' "$CK" | grep -qF '[ "$_COV_RC1" = 0 ]' && printf '%s\n' "$CK" | grep -qF '[ "$_COV_RC2" = 1 ]' || fail "XH: _co_cov_check no longer grades X1's exit 0 and X2's exit 1"
printf '%s\n' "$CK" | grep -qF "'  Functions executed: 5/7 (71%)  [execution coverage" || fail "XH: _co_cov_check no longer holds X1's exact 'Functions executed: 5/7 (71%)'"
printf '%s\n' "$CK" | grep -qF "'  FAIL: programs/bad_test.cyr (exit 1)'" || fail "XH: _co_cov_check no longer holds X2's named 'FAIL: programs/bad_test.cyr (exit 1)'"
[ "$FAIL" = "$x" ] && echo "  ok XH: all $nh hardware legs ($HOSTS) run X1 + X2 and fail as 'SELFHOST_FAIL: <host> — coverage --exec'; the checker grades both exit codes, 5/7 and bad_test's exit 1"

[ "$FAIL" = 0 ] || { echo "FAIL: coverage_exec_cli — $FAIL row(s)"; exit 1; }
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: coverage_exec_cli — every row that ran passed; W1 could not run (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: coverage_exec_cli (cyrius coverage --exec / [coverage] exec: .tcyr and RUN programs built instrumented and run, by name; text mode byte-identical; the Windows arm under wine)"
