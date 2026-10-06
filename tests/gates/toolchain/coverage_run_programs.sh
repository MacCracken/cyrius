#!/bin/sh
# coverage_run_programs.sh — 6.6.17 (P5-A). `cyrius coverage` takes RUN programs as a corpus:
# `[coverage] programs = ["programs/*_test.cyr"]` in cyrius.cyml, or `--programs <glob>` (which
# wins), each matched file counted exactly as a .tcyr is — TEXT coverage (whole-identifier
# references in code, comments and strings blanked), not execution coverage (P5-B, v6.7.x). Plus
# `--per-entry`: which corpus entry references which public fn.
#
# WHY: rekha tests with 25 programs/*_test.cyr RUN programs (~13,000 lines of checks) and has no
# tests/ dir, so coverage read ~0% for a hard-exercised API — and so did sadish, dhancha, setu,
# mishran. The fixture is rekha-shaped: src/ library, programs/*_test.cyr, a programs/smoke.cyr
# that is not a test, no tests/ at all.
#
# AXES
#   1. the manifest channel: 3 of 5 public fns referenced (6.6.16: 0 of 5, and --min 50 failed).
#   2. a name in a program's comment or string is not a reference.
#   3. `*` does not cross `/`: programs/sub/deep_test.cyr is not matched by programs/*_test.cyr.
#   4. --programs beats the manifest (only its glob is read).
#   5. a glob that matches nothing, and a literal path that does not exist: named failures.
#   6. --per-entry lists each entry's referenced fns.
#   7. the '.' fallback (no src/): a corpus program is a test, not measured surface.
#   8. .tcyr files still count alongside programs.
#   9. an unknown [coverage] key is warned by name.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: coverage_run_programs: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: coverage_run_programs: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: coverage_run_programs: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
cov() { d=$1; shift; RC=0; ( cd "$d" && CYRIUS_RESOLVED=1 "$W/cyrius" coverage "$@" ) > "$W/out" 2>&1 || RC=$?; }
show() { sed 's/^/      /' "$W/out" | head -8; }

R="$W/rk"; mkdir -p "$R/src" "$R/programs/sub"
cat > "$R/src/face.cyr" <<'CYR'
fn face_open(p): i64 { return p; }
fn glyph_outline(f, g): i64 { return f + g; }
fn units_per_em(f): i64 { return 1000; }
CYR
cat > "$R/src/cff.cyr" <<'CYR'
fn cff_parse(b): i64 { return b; }
fn cff_never_called(): i64 { return 0; }
CYR
cat > "$R/programs/face_test.cyr" <<'CYR'
include "src/face.cyr"
# cff_never_called is only named in this comment
var f = face_open(1);
var g = glyph_outline(f, 2);
syscall(60, 0);
CYR
cat > "$R/programs/cff_test.cyr" <<'CYR'
include "src/cff.cyr"
var c = cff_parse(3);
var s = "units_per_em only appears in a string";
syscall(60, 0);
CYR
printf 'var x = units_per_em(1);\n' > "$R/programs/sub/deep_test.cyr"
printf 'var y = units_per_em(1);\n' > "$R/programs/smoke.cyr"
printf '[package]\nname = "rk"\n\n[build]\nentry = "programs/smoke.cyr"\noutput = "build/rk"\n\n[coverage]\nprograms = ["programs/*_test.cyr"]\n' > "$R/cyrius.cyml"

# ── 1 + 2 + 3: the manifest channel ─────────────────────────────────────────────────────
cov "$R" --min 50 -v
if [ "$RC" = 0 ] && grep -q 'Functions referenced: 3/5 (60%)' "$W/out"; then echo "  ok 1: [coverage] programs — 3/5 referenced, --min 50 passes"
else fail "1: rc $RC, want 3/5 and a passing --min 50:"; show; fi
grep -q 'src/cff.cyr: cff_never_called' "$W/out" && grep -q 'src/face.cyr: units_per_em' "$W/out" \
    && echo "  ok 2: a name in a program's comment or string is not a reference" || { fail "2: a comment / string reference counted"; show; }
grep -q '2 RUN program(s)' "$W/out" && echo "  ok 3: programs/*_test.cyr matches 2 files — not programs/sub/, not smoke.cyr" || { fail "3: the glob matched the wrong set"; show; }

# ── 4: --programs beats the manifest ────────────────────────────────────────────────────
cov "$R" --programs 'programs/sub/*_test.cyr' -v
if grep -q 'Functions referenced: 1/5' "$W/out" && grep -q 'src/face.cyr: face_open' "$W/out" && ! grep -q 'src/face.cyr: units_per_em' "$W/out"; then
    echo "  ok 4: --programs replaces [coverage] programs (only deep_test.cyr read)"
else fail "4: --programs did not win over the manifest"; show; fi

# ── 5: matches nothing / missing ────────────────────────────────────────────────────────
x=$FAIL
cov "$R" --programs 'programs/nope_*.cyr'
[ "$RC" -ne 0 ] && grep -q 'matches no file: programs/nope_\*.cyr' "$W/out" || { fail "5: an empty glob was not a named failure (rc $RC)"; show; }
cov "$R" --programs 'programs/missing_test.cyr'
[ "$RC" -ne 0 ] && grep -q 'no such program.*programs/missing_test.cyr' "$W/out" || { fail "5: a missing literal program was not a named failure (rc $RC)"; show; }
[ "$FAIL" = "$x" ] && echo "  ok 5: a glob matching nothing and a missing program are named failures"

# ── 6: --per-entry ──────────────────────────────────────────────────────────────────────
x=$FAIL
cov "$R" --per-entry
grep -q '^  programs/face_test.cyr: 2 of 5 public fns$' "$W/out" || fail "6: no face_test.cyr entry line"
grep -q '^      src/face.cyr: glyph_outline$' "$W/out" || fail "6: face_test.cyr's glyph_outline reference not listed"
grep -q '^  programs/cff_test.cyr: 1 of 5 public fns$' "$W/out" || fail "6: no cff_test.cyr entry line"
[ "$FAIL" = "$x" ] && echo "  ok 6: --per-entry names each entry and the fns it references" || show

# ── 7: the '.' fallback ─────────────────────────────────────────────────────────────────
F="$W/flat"; mkdir -p "$F/programs"
printf 'fn lib_fn(): i64 { return 1; }\nfn lib_unused(): i64 { return 2; }\n' > "$F/lib_main.cyr"
printf 'fn test_helper(): i64 { return lib_fn(); }\nvar r = test_helper();\nsyscall(60, 0);\n' > "$F/programs/a_test.cyr"
cov "$F" --programs 'programs/*_test.cyr' -v
if grep -q 'Functions referenced: 1/2' "$W/out" && ! grep -q 'test_helper' "$W/out"; then echo "  ok 7: no src/: a corpus program is not measured (1/2 — lib_fn of lib_fn, lib_unused)"
else fail "7: a corpus program was counted as surface"; show; fi

# ── 8: .tcyr still count ────────────────────────────────────────────────────────────────
mkdir -p "$R/tests"; printf 'var z = cff_never_called();\nvar r = assert_summary();\n' > "$R/tests/a.tcyr"
cov "$R"
grep -q 'Functions referenced: 4/5' "$W/out" && echo "  ok 8: tests/*.tcyr and programs both count (4/5)" || { fail "8: .tcyr + programs did not combine"; show; }
rm -rf "$R/tests"

# ── 9: an unknown [coverage] key ────────────────────────────────────────────────────────
printf '[package]\nname = "rk"\n\n[coverage]\nprograms = ["programs/*_test.cyr"]\nexclude = ["src/cff.cyr"]\n' > "$R/cyrius.cyml"
cov "$R"
grep -q 'cyrius.cyml \[coverage\] exclude is not a known key' "$W/out" && echo "  ok 9: an unknown [coverage] key is warned by name" || { fail "9: no warning for [coverage] exclude"; show; }

[ "$FAIL" = 0 ] || exit 1
echo "PASS: coverage_run_programs (RUN programs as a text corpus, --programs > manifest, --per-entry)"
