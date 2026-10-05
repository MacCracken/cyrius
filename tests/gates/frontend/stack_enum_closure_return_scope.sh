#!/bin/sh
# stack_enum_closure_return_scope.sh — 6.6.16 (H2). A closure's `return` belongs to the CLOSURE.
# A `return <call of a : stack fn>` inside a closure body (`|x| { .. }`, `|| { .. }`) must not
# be booked against the fn that encloses the closure.
#
# ⛔ THE DEFECT (hisab, filed 2026-10-03 against pins 6.6.0 - 6.6.14; 6.6.15 carries the same
# scans and reproduces it). The two token scans that reason about pair returns after parsing —
# `_pair_prescan` (propagates fn flag 256 through `return f(..)`) and `_warn_mixed_pair_returns`
# (the "SINGLE value here" warning), both in src/frontend/parse.cyr — skipped a nested body only
# on the `fn` token. A closure literal has no `fn` token, so its body was scanned as the
# enclosing fn's. Then:
#   - `fn mk(b) { var g = |x| { return h(x + b); }; return g; }` was flagged pair-returning
#     although it returns ONE value (the closure), so every `var g = mk(41);` inside a fn was
#     REFUSED "bind both", and the refusal's own hint (`var t, v = mk(41);`) compiled clean and
#     read an unset rdx (fncall1 on it: exit 139);
#   - the flag propagated through forwarding wrappers (`fn fwd(b) { return mk(b); }`);
#   - the mixed-return warning fired on the enclosing fn's own plain `return g;`, falsely
#     warned a REAL pair fn at a closure's `return 0`, and warned a real mixed-return fn at the
#     CLOSURE's return instead of its own.
# The in-parse flagging is not at fault: a closure body parses with `_cur_fn_ix` = the closure.
#
# ⭐ THE FIX: both scans skip a `{` that opens a closure body (`_tok_is_closure_body`: the `{`
# is immediately preceded by `|` or `||`; `_tok_skip_block` jumps to its matching `}`). And
# because a closure IS a fn, the mixed-return warning then judges every closure body as its OWN
# unit (`_warn_closure_block`, at any depth: top level, an unflagged fn, a nested closure). The
# skip alone had taken away the only warning a GENUINELY mixed closure had —
# `|x| { if (x > 0) { return h(x); } return 0; }` built silent, and `var t, v = fncall1(g, 0)`
# on it read a stale rdx. A closure is pair-returning by the same test that flags a fn: its own
# body (nested closures and fns skipped) says `return f(..)` or `f(..)?` with f a pair fn.
#
# ROWS
#   1. The filed repro, VERBATIM (docs/development/issues/repros/2026-10-03-hisab-closure-stack-
#      return-blamed-on-enclosing-fn.sh), run against THIS TREE through a throwaway HOME +
#      CYRIUS_HOME whose versions/<VERSION> slot holds lib/ from the tree and bin/{cyrius,cycc}
#      built from it — never the live store, whose slot for the in-flight version is the slot-
#      open build. Exit 0 (its controls C1-C3 must hold, or it exits 99), and every `compiler:`
#      line names the staged cycc.
#   2. Raw rows, built from the repo root: a forwarding wrapper, a `?` closure body, a zero-param
#      `|| { }`, nested closures, a closure literal returned directly, a brace-less closure, a
#      top-level closure, the closure's OWN pair consumed through fncall1, and closures returning
#      Some / None() (a nullary variant is a whole value; None-or-0 never returns a pair). Each
#      builds, prints no `: stack` diagnostic and runs to exit 0.
#   3. A REAL pair fn holding a closure whose body says `return 0;`: no warning.
#   4. A REAL mixed-return fn holding a closure: warned exactly once, at the column of the OUTER
#      fn's plain `return` (derived from the fixture text), not at the closure's.
#   5. Controls: a real mixed return still warns; a real single-variable bind of a pair is still
#      refused.
#   6. Rows 2-5 and 7 again through the aarch64 cross compiler built from this tree (compile and
#      diagnostics only — the scans are target-independent, this pins the second backend fork).
#   7. A GENUINELY mixed closure is warned as its own unit — exactly once, at ITS plain `return`
#      (column derived from the fixture text), naming "a closure in `<fn>`" or, at top level,
#      "a closure": inside an unflagged fn, a zero-param `||` one, at top level, a `?` body with a
#      plain return, an inner mixed closure in a clean outer one, an outer mixed closure holding
#      a clean pair closure, and a mixed closure inside a REAL pair fn whose own returns are clean.
#
# MUTATION LEDGER (measured 6.6.16 against a copy of the tree with ONE edit, each mutant's
# compilers rebuilt from source by this gate; x86 + aarch64 rows counted separately):
#   a. `_pair_prescan`'s closure skip removed (back to `bd + 1`)  -> 23 red: row 1 (the repro
#        exits 3), 6 row-2 fixtures refused "bind both", optclean warned, and cl_infn / cl_zero /
#        cl_inner / cl_outer warned TWICE (the enclosing fn flagged through its closure) — each
#        on x86 and aarch64
#   b. `_warn_mixed_pair_returns`'s closure skip removed          -> 6 red: pairfn warned, mixed
#        warned at 8:28 (the closure's return) and cl_inpair warned twice, on both targets
#   c. the closure-unit check removed (`_warn_closure_block` never called — the first cut of
#        this fix, where a mixed closure built SILENT)               -> 14 red: all 7 row-7
#        fixtures, 0 warnings, on both targets
#   d. `_warn_closure_block` stops skipping NESTED closures         -> 4 red: nested (a clean
#        outer closure warned for its inner one's return) and cl_inner (warned twice)
#   e. `_warn_closure_block` ignores `f(..)?`                       -> 2 red: cl_q, 0 warnings
#   pre-fix tree (the 6.6.16 slot open, 0bf9b773)                 -> 33 red, 8 green: the mixed
#        closures warned at the right column but blamed on the enclosing fn (`main` returns ..),
#        and cl_top / cl_q not at all
# The brace-less and top-level row-2 fixtures are clean on every tree (an expression body holds
# no `return`; a top-level closure has no enclosing fn): they guard the skip against over-reach,
# not the defect. Real tree -> PASS, 41 rows.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=stack_enum_closure_return_scope
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null
# The compilers under test are BUILT FROM THIS TREE, so reverting the fix in src/ turns this RED
# whether or not build/cycc was rebuilt; the cross compiler is never read from build/.
"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" && [ -s "$T/x86" ] \
  || { echo "FAIL $G: could not build src/main.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
"$T/x86" < src/main_aarch64.cyr > "$T/aarch64" 2> "$T/eb" && [ -s "$T/aarch64" ] \
  || { echo "FAIL $G: could not build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/aarch64"
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
NEEDLE='SINGLE value here'

# ── row 1: the filed repro, verbatim, against the tree ──────────────────────────────────────
REPRO="$ROOT/docs/development/issues/repros/2026-10-03-hisab-closure-stack-return-blamed-on-enclosing-fn.sh"
V=$(cat VERSION)
H="$T/home"
SB="$H/versions/$V/bin"
if [ ! -f "$REPRO" ]; then
  _bad "row 1: the filed repro is missing: $REPRO"
elif ! mkdir -p "$SB" "$T/fakehome" "$T/rt"; then
  _bad "row 1: cannot stage the throwaway home"
elif ! "$T/x86" < cbt/cyrius.cyr > "$SB/cyrius" 2> "$T/cli.err" || [ ! -s "$SB/cyrius" ]; then
  _bad "row 1: cbt/cyrius.cyr does not build"; tail -3 "$T/cli.err" | sed 's/^/      /'
else
  cp "$T/x86" "$SB/cycc" && chmod +x "$SB/cyrius" "$SB/cycc" && cp -r lib "$H/versions/$V/lib" \
    && printf '%s\n' "$V" > "$H/current" || { echo "FAIL $G: cannot stage $H"; exit 1; }
  # CYRIUS_RESOLVED=1: never re-exec into a pinned version's CLI — this tree's is under test.
  rc=0
  ( HOME="$T/fakehome" TMPDIR="$T/rt" CYRIUS="$SB/cyrius" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 \
      CYRIUS_NO_WARN_PIN_DRIFT=1 sh "$REPRO" "$V" ) > "$T/r1.out" 2>&1 || rc=$?
  ncl=$(grep -c 'compiler: ' "$T/r1.out")
  nst=$(grep -c "compiler: $SB/cycc\$" "$T/r1.out")
  if [ "$rc" -ne 0 ]; then
    _bad "row 1: the filed repro exited $rc (0 = fixed, 1-3 = defect rows, 99 = a control failed)"
    sed 's/^/      /' "$T/r1.out" | cut -c1-170 | head -20
  elif [ "$ncl" -ne 6 ] || [ "$nst" -ne 6 ]; then
    _bad "row 1: $nst of $ncl compiler: lines name the staged $SB/cycc (expected 6 of 6)"
    grep 'compiler: ' "$T/r1.out" | sed 's/^/      /'
  else
    pass=$((pass + 1))
  fi
fi

# ── fixtures for rows 2-6 (raw compiles from the repo root) ─────────────────────────────────
HDR='include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/result.cyr"
include "lib/fnptr.cyr"
fn h(x) { return Ok(x); }'
TAIL='alloc_init();
var r = main();
sys_exit_group(r);'
fx() { printf '%s\n%s\n%s\n' "$HDR" "$2" "$TAIL" > "$T/$1.cyr"; }
# row 2 — the closure's returns are its own
fx fwd      'fn mk(b) { var g = |x| { return h(x + b); }; return g; }
fn fwd(b) { return mk(b); }
fn main() { var g = fwd(1); return 0; }'
fx propq    'fn mk(b) { var g = |x| { var r = h(x + b)?; return Ok(r); }; return g; }
fn main() { var g = mk(1); var t, v = fncall1(g, 1); return t + v - 2; }'
fx zeroparm 'fn mk(b) { var g = || { return h(b); }; return g; }
fn main() { var g = mk(1); var t, v = fncall0(g); return t + v - 1; }'
fx nested   'fn mk(b) { var g = |x| { var k = |y| { return h(y); }; return 0; }; return g; }
fn main() { var g = mk(1); return fncall1(g, 1); }'
fx direct   'fn mk(b) { return |x| { return h(x + b); }; }
fn main() { var g = mk(41); var t, v = fncall1(g, 1); return t + v - 42; }'
fx braceless 'fn mk(b) { var g = |x| h(x + b); return g; }
fn main() { var g = mk(41); var t, v = fncall1(g, 1); return t + v - 42; }'
fx toplevel 'var gg = |x| { return h(x); };
fn main() { var t, v = fncall1(gg, 5); return t + v - 5; }'
fx ownpair  'fn mk(b) { var g = |x| { return h(x + b); }; return g; }
fn main() { var g = mk(41); var t, v = fncall1(g, 1); return t + v - 42; }'
fx optclean 'fn main() { var g = |x| { if (x > 0) { return Some(x); } return None(); }; var k = |y| { if (y > 0) { return None(); } return 0; }; var t, v = fncall1(g, 5); return t + v - 6; }'
# row 3 — a real pair fn whose closure returns a plain value
fx pairfn   'fn pr(b) { var g = |x| { return 0; }; return Ok(b); }
fn main() { var t, v = pr(1); return t + v - 1; }'
# row 4 — a real mixed-return fn holding a closure (line 8 of the fixture)
fx mixed    'fn bad2(x) { var g = |y| { return 0; }; if (x > 0) { return h(x); } return 0; }
fn main() { var t, v = bad2(1); return 0; }'
# row 5 — controls
fx ctl_mix  'fn bad(x) { if (x > 0) { return h(x); } return 0; }
fn main() { var t, v = bad(1); return 0; }'
fx ctl_bind 'fn main() { var t = h(1); return 0; }'
# row 7 — a GENUINELY mixed closure, judged as its own unit (the plain return is on line 8)
fx cl_infn  'fn main() { var g = |x| { if (x > 0) { return h(x); } return 0; }; return 0; }'
fx cl_zero  'fn main() { var g = || { if (1 > 0) { return h(1); } return 0; }; return 0; }'
fx cl_top   'var gg = |x| { if (x > 0) { return h(x); } return 0; };
fn main() { return 0; }'
fx cl_q     'fn main() { var g = |x| { var r = h(x)?; return r; }; return 0; }'
fx cl_inner 'fn main() { var g = |x| { var k = |y| { if (y > 0) { return h(y); } return 0; }; return 0; }; return 0; }'
fx cl_outer 'fn main() { var g = |x| { var k = |y| { return h(y); }; if (x > 0) { return h(x); } return 0; }; return 0; }'
fx cl_inpair 'fn pr(b) { var g = |x| { if (x > 0) { return h(x); } return 0; }; return Ok(b); }
fn main() { var t, v = pr(1); return t + v - 1; }'
# fixture : the plain return the warning must point at : the subject the message must name
ROW7="cl_infn:return 0;:a closure in \`main\`
cl_zero:return 0;:a closure in \`main\`
cl_top:return 0;:a closure
cl_q:return r;:a closure in \`main\`
cl_inner:return 0;:a closure in \`main\`
cl_outer:return 0;:a closure in \`main\`
cl_inpair:return 0;:a closure in \`pr\`"
ROW2="fwd propq zeroparm nested direct braceless toplevel ownpair optclean"

# 1-based column of the FIRST and LAST `return 0;` on line 8 of the mixed fixture.
COL_IN=$(awk 'NR == 8 { print index($0, "return 0;") }' "$T/mixed.cyr")
COL_OUT=$(awk 'NR == 8 { t = $0; p = 0; last = 0; while ((i = index(t, "return 0;")) > 0) { p = p + i; last = p; t = substr(t, i + 1) } print last }' "$T/mixed.cyr")
[ "${COL_IN:-0}" -gt 0 ] && [ "${COL_OUT:-0}" -gt "${COL_IN:-0}" ] \
  || { echo "FAIL $G: setup: could not locate the two returns in the mixed fixture ($COL_IN/$COL_OUT)"; exit 1; }

# _build <compiler> <fixture>: compile; sets BRC, leaves $T/<c>.<fx>.err and the binary $T/<c>.<fx>
_build() { "$T/$1" < "$T/$2.cyr" > "$T/$1.$2" 2> "$T/$1.$2.err"; BRC=$?; }
for c in x86 aarch64; do
  for f in $ROW2 pairfn; do
    _build "$c" "$f"
    if [ "$BRC" -ne 0 ]; then
      _bad "$c $f: build rc $BRC (the closure's return was booked to the enclosing fn?)"
      grep -E '^(error|warning)' "$T/$c.$f.err" | head -2 | cut -c1-170 | sed 's/^/      /'
      continue
    fi
    if grep -qF ': stack' "$T/$c.$f.err"; then
      _bad "$c $f: a \`: stack\` diagnostic on a clean program"
      grep -F ': stack' "$T/$c.$f.err" | head -2 | cut -c1-170 | sed 's/^/      /'
      continue
    fi
    if [ "$c" = x86 ]; then
      chmod +x "$T/$c.$f"; "$T/$c.$f" > /dev/null 2>&1; RRC=$?
      [ "$RRC" -eq 0 ] || { _bad "$c $f: built clean but ran to exit $RRC, expected 0"; continue; }
    fi
    pass=$((pass + 1))
  done
  # row 4: exactly one warning, on bad2, at the OUTER fn's plain return
  _build "$c" mixed
  if [ "$BRC" -ne 0 ]; then
    _bad "$c mixed: build rc $BRC (the fixture must build — the warning is a warning)"
  else
    n=$(grep -c "$NEEDLE" "$T/$c.mixed.err")
    if [ "$n" -ne 1 ]; then
      _bad "$c mixed: $n mixed-return warning(s), expected exactly 1"
      grep "$NEEDLE" "$T/$c.mixed.err" | cut -c1-120 | sed 's/^/      /'
    elif ! grep "$NEEDLE" "$T/$c.mixed.err" | grep -q "^warning:<source>:8:$COL_OUT: \`bad2\`"; then
      _bad "$c mixed: warned at the wrong place (want 8:$COL_OUT, the outer return; the closure's return is 8:$COL_IN)"
      grep "$NEEDLE" "$T/$c.mixed.err" | cut -c1-120 | sed 's/^/      /'
    else
      pass=$((pass + 1))
    fi
  fi
  # row 5: controls
  _build "$c" ctl_mix
  n=$(grep -c "$NEEDLE" "$T/$c.ctl_mix.err")
  if [ "$BRC" -ne 0 ] || [ "$n" -ne 1 ]; then
    _bad "$c control: a REAL mixed return gave build rc $BRC and $n warning(s), expected rc 0 and 1"
  else
    pass=$((pass + 1))
  fi
  _build "$c" ctl_bind
  if [ "$BRC" -eq 0 ] || ! grep -q 'bind both' "$T/$c.ctl_bind.err"; then
    _bad "$c control: a REAL single-variable bind of a pair was not refused (rc $BRC)"
  else
    pass=$((pass + 1))
  fi
  # row 7: a mixed closure is warned once, at its OWN plain return, as a closure
  printf '%s\n' "$ROW7" > "$T/row7"
  while IFS=: read -r f ret subj; do
    col=$(awk -v r="$ret" 'NR == 8 { print index($0, r) }' "$T/$f.cyr")
    [ "${col:-0}" -gt 0 ] || { _bad "$c $f: setup: no \`$ret\` on line 8 of the fixture"; continue; }
    _build "$c" "$f"
    if [ "$BRC" -ne 0 ]; then
      _bad "$c $f: build rc $BRC (the warning is a warning)"
      grep -E '^(error|warning)' "$T/$c.$f.err" | head -2 | cut -c1-170 | sed 's/^/      /'
      continue
    fi
    n=$(grep -c "$NEEDLE" "$T/$c.$f.err")
    if [ "$n" -ne 1 ]; then
      _bad "$c $f: $n mixed-return warning(s), expected exactly 1 (the closure's own)"
      grep "$NEEDLE" "$T/$c.$f.err" | cut -c1-120 | sed 's/^/      /'
    elif ! grep "$NEEDLE" "$T/$c.$f.err" | grep -qF "warning:<source>:8:$col: $subj returns"; then
      _bad "$c $f: want the warning at 8:$col (the closure's \`$ret\`) naming \"$subj\""
      grep "$NEEDLE" "$T/$c.$f.err" | cut -c1-120 | sed 's/^/      /'
    else
      pass=$((pass + 1))
    fi
  done < "$T/row7"
done

if [ "$fail" -ne 0 ]; then echo "FAIL $G: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS $G: $pass rows — a closure's returns are its own (the filed repro exits 0 against the tree; wrapper, ?, ||, nested, direct, brace-less, top-level and Option closures clean; a pair fn's closure unwarned; a mixed fn warned at its own return; a mixed closure warned at ITS return, as a closure; controls hold) on x86 and aarch64"
exit 0
