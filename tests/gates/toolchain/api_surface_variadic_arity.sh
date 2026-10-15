#!/bin/sh
# api_surface_variadic_arity.sh — 6.7.12 (the tools lane). `cyrius api-surface` writes a variadic
# fn as `name/MIN-` (the user's decision D22, 2026-10-15): 6.7.7's `name/MIN-MAX` form with the
# upper bound left open.
#
# WHY: _asf_arity counted depth-1 commas plus one, and a `...` tail is just more non-blank bytes,
# so `fn va(n, ...)` read `va/2` and `fn zv(...)` `zv/1` — exact counts a variadic fn does not
# have; a variadic fn and a fixed fn of the same count looked the same, so a change between the
# two was no signature change in the snapshot. A last parameter that is exactly `...` (the
# lexer's one ELLIPSIS token) is now not counted and the entry reads `name/MIN-`.
#
# ROWS (each fixture COMPILES first — a premise; the tool built from programs/ by build/cycc)
#   1  the filed repro verbatim (issues/2026-10-13-api-surface-variadic-arity.md): it exits 11;
#      `--update --scope=project` writes exactly v::two/2, v::va/1-, v::zv/0-
#   2  shapes: a fixed `fn f(a, b)` stays f/2 and `fn f3(a, b, c)` f3/3; a defaulted fn keeps
#      MIN-MAX (d/1-2); a tail on its own line after a comment holding a comma (wv/1-); a
#      default holding `...` in a string, or three `.` in code (`1.5 * 2.5 * 0.5`), is a
#      parameter (sd/1-2, fd/1-2); `fn ze()` stays ze/0
#   3  the snapshot round-trips (the diff reads `surface matches snapshot exactly`), and the
#      variadic fn turned fixed at the same count (`fn va(n)`) is reported BREAKING, naming
#      v::va/1- — the change the exact count hid
#   4  removed_symbol_census.sh's strip (`s|/.*||`) reads `va/1-` as the bare name
#
# MUTATION LEDGER (6.7.12) — each a scratch copy of the tree (git archive + the mutant):
#   M1  the 6.7.11 tool (the tail counted: va/2, zv/1)                         RED 1, 2, 3
#   M2  the tail dropped but written as a fixed arity (`name/MIN`)              RED 1, 2, 3
#   M3  any parameter holding three dots read as the tail (pdots only)          RED 2
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=api_surface_variadic_arity
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < programs/cyrius_api_surface.cyr > "$W/asf" 2> "$W/asf.err" || { echo "FAIL: $G: programs/cyrius_api_surface.cyr does not build"; tail -3 "$W/asf.err"; exit 1; }
[ "$(wc -c < "$W/asf")" -ge 10000 ] || { echo "FAIL: $G: the tool built a $(wc -c < "$W/asf")-byte binary"; exit 1; }
chmod +x "$W/asf"
# premise <file> <want exit>: the fixture compiles and exits as written
premise() { prc=0; "$CC" < "$1" > "$W/p.bin" 2> "$W/p.err" || prc=$?; chmod +x "$W/p.bin" 2> /dev/null; xrc=0; [ "$prc" = 0 ] && { "$W/p.bin" || xrc=$?; }; [ "$prc" = 0 ] && [ "$xrc" = "$2" ]; }
# snap <dir> [--update]: the tool over <dir>/src into <dir>/v.snap; stdout+stderr to $W/out, RC
snap() { d=$1; shift; RC=0; ( cd "$W/$d" && "$W/asf" "$@" --scope=project --snapshot=v.snap ) > "$W/out" 2>&1 < /dev/null || RC=$?; }

# ── 1: the filed repro, verbatim ──
mkdir -p "$W/t/src"
printf 'fn va(n, ...): i64 { return n; }\nfn zv(...): i64 { return 7; }\nfn two(a, b): i64 { return a + b; }\nsyscall(60, va(1, 2, 3) + zv() + two(1, 2));\n' > "$W/t/src/v.cyr"
if premise "$W/t/src/v.cyr" 11; then
    snap t --update
    got=$(tr '\n' ' ' < "$W/t/v.snap" 2> /dev/null)
    if [ "$RC" = 0 ] && [ "$got" = "v::two/2 v::va/1- v::zv/0- " ]; then echo "  ok 1: the filed repro — v::two/2 v::va/1- v::zv/0-"
    else fail "1: rc $RC, got '$got', want 'v::two/2 v::va/1- v::zv/0- '"; fi
else fail "1 premise: the repro does not compile and exit 11 (compile rc $prc, exit $xrc)"; fi

# ── 2: the shapes ──
mkdir -p "$W/s/src"
cat > "$W/s/src/v.cyr" <<'EOF'
fn f(a, b): i64 { return a + b; }
fn f3(a, b, c): i64 { return a + b + c; }
fn d(a, b = 1): i64 { return a + b; }
fn wv(a, # the rest, if any
  ...): i64 { return a; }
fn sd(a, s = "..."): i64 { return a; }
fn fd(a, p: f64 = 1.5 * 2.5 * 0.5): i64 { return a; }
fn ze(): i64 { return 0; }
syscall(60, f(1, 2) + f3(1, 2, 3) + d(1) + wv(1, 2, 3) + sd(1) + fd(1) + ze() - 14);
EOF
if premise "$W/s/src/v.cyr" 0; then
    snap s --update
    got=$(tr '\n' ' ' < "$W/s/v.snap" 2> /dev/null)
    want='v::d/1-2 v::f/2 v::f3/3 v::fd/1-2 v::sd/1-2 v::wv/1- v::ze/0 '
    if [ "$RC" = 0 ] && [ "$got" = "$want" ]; then echo "  ok 2: shapes — f/2 f3/3 ze/0 fixed, d/1-2 defaulted, wv/1- (tail after a comment), sd/1-2 and fd/1-2 (a \"...\" or three-dot default is a parameter)"
    else fail "2: rc $RC, got '$got', want '$want'"; fi
else fail "2 premise: the shapes fixture does not compile and exit 0 (compile rc $prc, exit $xrc)"; head -3 "$W/p.err"; fi

# ── 3: the round trip, and a variadic fn turned fixed is a changed signature ──
snap t
if [ "$RC" = 0 ] && grep -q 'surface matches snapshot exactly' "$W/out"; then r3a=1; else r3a=0; fi
printf 'fn va(n): i64 { return n; }\nfn zv(...): i64 { return 7; }\nfn two(a, b): i64 { return a + b; }\nsyscall(60, va(1) + zv() + two(1, 2) - 11);\n' > "$W/t/src/v.cyr"
if premise "$W/t/src/v.cyr" 0; then
    snap t
    if [ "$r3a" = 1 ] && [ "$RC" = 1 ] && grep -q '^BREAKING' "$W/out" && grep -qxF '  - v::va/1-' "$W/out"; then
        echo "  ok 3: the snapshot round-trips; va(n, ...) -> va(n) is BREAKING, naming v::va/1-"
    else fail "3: round trip $r3a (want 1), diff rc $RC (want 1)"; sed 's/^/      /' "$W/out" | head -5; fi
else fail "3 premise: the fixed va does not compile (compile rc $prc, exit $xrc)"; fi

# ── 4: the census's own strip (tests/gates/toolchain/removed_symbol_census.sh) ──
got=$(printf 'v::va/1-\nv::zv/0-\nv::d/1-2\nv::two/2\n' | sed 's|/.*||' | tr '\n' ' ')
grep -qF "s|/.*||" tests/gates/toolchain/removed_symbol_census.sh || fail "4: removed_symbol_census.sh no longer strips with s|/.*|| — re-read its expression"
[ "$got" = "v::va v::zv v::d v::two " ] && echo "  ok 4: removed_symbol_census.sh's strip reads /MIN- as the bare name" || fail "4: the strip gives '$got'"

[ "$FAIL" = 0 ] || { echo "FAIL: $G — $FAIL row(s) failed"; exit 1; }
echo "PASS: $G (a variadic fn is name/MIN-: va/1-, zv/0-; fixed and defaulted fns unchanged; a variadic-to-fixed change is BREAKING)"
