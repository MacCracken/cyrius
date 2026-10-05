#!/bin/sh
# nested_fn_refused.sh — 6.6.16 (C5). A named `fn` / `async fn` inside a fn body — or a closure,
# an impl method, a generic body — is ONE named compile error, and its tokens are skipped so
# nothing cascades. A fn inside a TOP-LEVEL block stays legal.
#
# ⛔ THE DEFECT. Every fn body, block and closure body is parsed by PARSE_PROG, whose `fn` arm is
# the relaxed-ordering feature for TOP-LEVEL code (jump over the body, PARSE_FN_DEF, patch). It
# fired inside a fn body too, and PARSE_FN_DEF for the inner fn overwrote the OUTER fn's per-fn
# state while the outer was still being emitted — locals and frame, return patches,
# `_cur_fn_ix`, and `SINFN(S, 0)` at the inner fn's end, so the rest of the outer body parsed as
# top-level code. Measured on the slot open (x86): the roadmap one-liner
#   fn outer(): i64 { fn inner(): i64 { return 3; } return inner(); }
# compiled rc 0 and ran SIGILL (132), and did with the call replaced by `return 7;`; a
# multi-line form, an untyped one, one in an `if` and one in a generic instance ran SIGSEGV
# (139). A switch case said `unexpected fn` plus `expected ';'`, a nested `async fn` said
# `unexpected async`, one inside a closure said `undefined variable 'x'`, one in an impl method
# `undefined function 'inner'` plus "refusing to emit binary". Zero nested fns exist in the 7
# compiler forks, cyrius's tests/programs/lib/cbt, or 1,350 ecosystem units (instrumented survey).
#
# ⭐ THE FIX (src/frontend/parse.cyr `_refuse_nested_fn`), reached from PARSE_PROG's `fn` arm when
# GINFN == 1, from the end of _PARSE_STMT_IMPL (positions that bypass PARSE_PROG: a switch case,
# `@unsafe { }`, `async fn`) and from PARSE_FN_DEF's generic stub-body skip. It reports
#   error:<loc>: fn 'inner' is defined inside fn 'outer'; define it at top level
# (`inside a closure` for a closure body) ONCE per definition — a generic instance and an
# `#inline` replay re-parse the same tokens — consumes the fn through its body's `}` (or a
# bodiless header's `;`, never past EOF) with `_skip_nested_body`, the skip the two pair scans
# share, and enters the name as already reported so a call to it adds no "undefined function".
#
# ROWS (each through the x86 compiler AND the aarch64 cross, both built from THIS tree):
#   1. refusals — one-liner, multi-line, if block, while, switch case, `async fn`, `@unsafe`,
#      closure in a fn, closure at top level, impl method, uninstantiated generic, a generic whose
#      base body is a stub (the PARSE_FN_DEF skip), an instantiated generic and an `#inline` fn
#      with two call sites (each reported ONCE), a bodiless `fn inner(a, b);`: exit 1, no binary,
#      the named message exactly once naming both fns, and no other `error` line, no
#      `undefined function` (no cascade).
#   2. two nested fns, the second's generic instantiated before the first is parsed: TWO reports
#      (the once-per-definition record must not swallow a different definition), plus a
#      syntax error after one of them is still reported (the outer body parses on).
#   3. pair scans: a refused fn whose body returns a `: stack` call puts no "bind both" refusal
#      and no mixed-return warning on its outer fn; a REAL pair fn holding a refused fn with a
#      plain return draws no mixed-return warning either.
#   4. controls — a fn inside a top-level block builds and runs 3; an ordinary program runs 0
#      (x86 run; aarch64 compile — and run, under qemu-aarch64 when present).
#   5. the one-liner through the PE cross and the cx compiler built from this tree: one error,
#      no output (cx printed a second "undefined function(s) called" error before the fix's
#      main_cx.cyr arm).
#
# MUTATION LEDGER (measured 6.6.16: a copy of the tree with ONE edit, its compilers rebuilt from
# source by this gate with CYCC=build/cycc; 46 rows, each one pass or one fail):
#   a. PARSE_PROG's `fn` arm always takes the relaxed-ordering path        -> 32 red: every
#        PARSE_PROG-position refusal compiles (rc 0 — the SIGILL/SIGSEGV binaries) or cascades,
#        on x86, aarch64, PE and cx
#   b. the _PARSE_STMT_IMPL arm removed                                    -> 6 red: switchcase,
#        asyncfn (`unexpected async`), unsafeblk, on x86 and aarch64
#   c. the PARSE_FN_DEF stub-body arm removed                              -> 2 red: gen_stub
#        compiles rc 0 (its base body is skipped, so nothing else sees the nested fn)
#   d. `_nested_fn_seen` never records                                     -> 6 red: gen_inst 4
#        reports, inl 3 (the replays name `main`), two reports i2 twice
#   e. `_nested_fn_mark` does nothing                                      -> 22 red: every row
#        whose outer body calls `inner` adds "undefined function" / "refusing to emit binary"
#        (cx: "undefined function(s) called")
#   f. `_pair_prescan`'s nested-fn skip removed                            -> 2 red: pair_ret, the
#        outer fn flagged pair-returning and its `var r = outer(1)` refused "bind both"
#   g. `_warn_mixed_pair_returns`'s nested-fn skip removed                 -> 2 red: pair_fn warned
#        "SINGLE value here" at the refused fn's `return 0;`
#   h. main_cx.cyr's undefined-call check back to `< 0`                    -> 2 red: cx one /
#        clos_top print a second error
#   i. `_skip_nested_body` without its `;` stop                            -> 2 red: bodiless, the
#        skip swallows `var x = 1;` through the next block's `}`: "undefined variable 'x'"
#   slot open (0bf9b773)                                                   -> 40 red, 6 green (the
#        controls)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=nested_fn_refused
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null
# The compilers under test are BUILT FROM THIS TREE (never read from build/), so reverting the
# fix in src/ turns this RED whether or not build/cycc was rebuilt.
_mk() {   # _mk <name> <source>: a compiler built by the tree's own x86 cycc
  "$T/x86" < "$2" > "$T/$1" 2> "$T/eb" || true
  [ -s "$T/$1" ] || { echo "FAIL $G: could not build $2"; sed -n 1,3p "$T/eb" || true; exit 1; }
  chmod +x "$T/$1"
}
"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" && [ -s "$T/x86" ] \
  || { echo "FAIL $G: could not build src/main.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
_mk aarch64 src/main_aarch64.cyr
_mk pe src/main_win.cyr
_mk cx src/main_cx.cyr
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
NEEDLE='; define it at top level'

# fixture <name> : body written to $T/<name>.cyr
fx() { printf '%s\n' "$2" > "$T/$1.cyr"; }
fx one 'fn outer(): i64 { fn inner(): i64 { return 3; } return inner(); }
var r = outer();
syscall(60, r);'
fx multi 'fn outer(): i64 {
    fn inner(): i64 {
        return 3;
    }
    var x = inner();
    return x;
}
fn main(): i64 { return outer(); }
var r = main();
syscall(60, r);'
fx ifblk 'fn outer(a): i64 {
    if (a == 1) {
        fn inner() { return 3; }
        return inner();
    }
    return 0;
}
var r = outer(1);
syscall(60, r);'
fx whileblk 'fn outer(a): i64 {
    while (a < 3) {
        fn inner(x) { return x + 1; }
        a = inner(a);
    }
    return a;
}
var r = outer(1);
syscall(60, r);'
fx switchcase 'fn outer(a): i64 {
    switch (a) {
        case 1: fn inner() { return 3; }
        default: return 0;
    }
    return 1;
}
var r = outer(1);
syscall(60, r);'
fx asyncfn 'fn outer(): i64 {
    async fn inner() { return 3; }
    return 1;
}
var r = outer();
syscall(60, r);'
fx unsafeblk 'fn outer(): i64 { @unsafe { fn inner() { return 3; } } return inner(); }
var r = outer();
syscall(60, r);'
fx clos_infn 'include "lib/fnptr.cyr"
fn outer(): i64 {
    var g = |x| { fn inner() { return 3; } return x + inner(); };
    return fncall1(g, 1);
}
var r = outer();
syscall(60, r);'
fx clos_top 'include "lib/fnptr.cyr"
var g = |x| { fn inner() { return 3; } return x + inner(); };
var r = fncall1(g, 1);
syscall(60, r);'
fx implm 'struct P { a: i64; }
impl T for P {
    fn m(self) { fn inner() { return 3; } return inner(); }
}
fn main(): i64 { var p: P; p.a = 1; return p.m(); }
var r = main();
syscall(60, r);'
fx gen_base 'fn outer<T>(x: T): i64 { fn inner() { return 3; } return x; }
var r = 0;
syscall(60, r);'
fx gen_stub 'struct Pt { x: i64; y: i64; }
fn outer<T>(p: T): i64 { fn inner() { return 3; } return p.x; }
var r = 0;
syscall(60, r);'
fx gen_inst 'fn outer<T>(x: T): i64 { fn inner(): i64 { return 3; } return inner(); }
fn main(): i64 { return outer<i32>(4) + outer<i64>(1); }
var r = main();
syscall(60, r);'
fx inl '#inline
fn outer(a): i64 { fn inner() { return 3; } return a; }
fn main(): i64 { return outer(1) + outer(2); }
var r = main();
syscall(60, r);'
fx bodiless 'fn outer(): i64 {
    fn inner(a, b);
    var x = 1;
    if (x == 1) { x = 2; }
    return x;
}
var r = outer();
syscall(60, r);'
# fixture : the enclosing subject the message names
ROW1="one:fn 'outer'
multi:fn 'outer'
ifblk:fn 'outer'
whileblk:fn 'outer'
switchcase:fn 'outer'
asyncfn:fn 'outer'
unsafeblk:fn 'outer'
clos_infn:a closure
clos_top:a closure
implm:fn 'P_m'
gen_base:fn 'outer'
gen_stub:fn 'outer'
gen_inst:fn 'outer'
inl:fn 'outer'
bodiless:fn 'outer'"

fx two 'fn main(): i64 { return g2<i32>(4); }
fn a1(): i64 { fn i1() { return 1; } var z = ; return 0; }
fn g2<T>(x: T): i64 { fn i2() { return 2; } return x; }
var r = main() + a1();
syscall(60, r);'
fx pair_ret 'enum Res : stack { Ok(v), Err(e) }
fn h(x) { return Ok(x); }
fn outer(x) {
    fn inner(y) { return h(y); }
    return 0;
}
fn main(): i64 { var r = outer(1); return r; }
var rr = main();
syscall(60, rr);'
fx pair_fn 'enum Res : stack { Ok(v), Err(e) }
fn h(x) { return Ok(x); }
fn outer(x) {
    fn inner(y) { return 0; }
    return h(x);
}
fn main(): i64 { var t, v = outer(1); return t + v; }
var rr = main();
syscall(60, rr);'
fx ctl_block 'var r = 0;
if (r == 0) { fn inner() { return 3; } r = inner(); }
syscall(60, r);'
fx ctl_plain 'fn add(a, b) { return a + b; }
var r = add(0, 0);
syscall(60, r);'

# _build <compiler> <fixture>: compile from the repo root; sets BRC; leaves $T/<c>.<fx>(.err)
_build() { BRC=0; "$T/$1" < "$T/$2.cyr" > "$T/$1.$2" 2> "$T/$1.$2.err" || BRC=$?; }
# _refused <compiler> <fixture> <subject> <want-count>: exit 1, no output, the message <want>
# times naming `inner` and <subject>, no other error line, no "undefined function", and no
# `: stack` pair diagnostic (a refused fn's `return` booked to the outer fn by the pair scans).
_refused() {
  _build "$1" "$2"
  nm=$(grep -c "$NEEDLE" "$T/$1.$2.err" || true)
  ns=$(grep -c "fn 'inner' is defined inside $3$NEEDLE" "$T/$1.$2.err" || true)
  ne=$(grep -c '^error' "$T/$1.$2.err" || true)
  nu=$(grep -c 'undefined function' "$T/$1.$2.err" || true)
  if [ "$BRC" -ne 1 ]; then _bad "$1 $2: compile exit $BRC, expected 1"
  elif [ -s "$T/$1.$2" ]; then _bad "$1 $2: a refused compile still wrote $(wc -c < "$T/$1.$2") bytes"
  elif [ "$nm" -ne "$4" ] || [ "$ns" -ne "$4" ]; then _bad "$1 $2: $nm nested-fn report(s), $ns of them naming \`inner\` inside $3; expected $4"
  elif [ "$ne" -ne "$4" ]; then _bad "$1 $2: $ne error line(s), expected only the $4 nested-fn report(s) — a cascade"
  elif [ "$nu" -ne 0 ]; then _bad "$1 $2: an \`undefined function\` line beside the refusal — a cascade"
  elif grep -qE 'SINGLE value here|bind both' "$T/$1.$2.err"; then _bad "$1 $2: a \`: stack\` diagnostic on the OUTER fn — the pair scans counted the refused fn's return"
  else pass=$((pass + 1)); return 0
  fi
  grep -E '^(error|warning)' "$T/$1.$2.err" | head -4 | cut -c1-170 | sed 's/^/      /' || true
  return 0
}

printf '%s\n' "$ROW1" > "$T/row1"
for c in x86 aarch64; do
  # row 1
  while IFS=: read -r f subj; do
    _refused "$c" "$f" "$subj" 1
  done < "$T/row1"
  # row 2: two definitions, two reports; a later syntax error is still reported
  _build "$c" two
  n1=$(grep -c "fn 'i1' is defined inside fn 'a1'$NEEDLE" "$T/$c.two.err" || true)
  n2=$(grep -c "fn 'i2' is defined inside fn 'g2'$NEEDLE" "$T/$c.two.err" || true)
  nx=$(grep -c "unexpected ';'" "$T/$c.two.err" || true)
  if [ "$BRC" -ne 1 ] || [ "$n1" -ne 1 ] || [ "$n2" -ne 1 ] || [ "$nx" -ne 1 ] || [ -s "$T/$c.two" ]; then
    _bad "$c two: rc $BRC, i1 x$n1, i2 x$n2, the later \`unexpected ';'\` x$nx (want 1, 1, 1, 1, no binary)"
  else pass=$((pass + 1)); fi
  # row 3: the pair scans skip the refused fn's body
  for f in pair_ret pair_fn; do _refused "$c" "$f" "fn 'outer'" 1; done
  # row 4: controls
  for f in ctl_block:3 ctl_plain:0; do
    fxn=${f%%:*}; want=${f##*:}
    _build "$c" "$fxn"
    if [ "$BRC" -ne 0 ] || [ ! -s "$T/$c.$fxn" ] || grep -q "$NEEDLE" "$T/$c.$fxn.err"; then
      _bad "$c $fxn: a legal program was refused (rc $BRC)"; grep -E '^error' "$T/$c.$fxn.err" | head -2 | sed 's/^/      /' || true; continue
    fi
    chmod +x "$T/$c.$fxn"
    if [ "$c" = x86 ]; then RRC=0; "$T/$c.$fxn" > /dev/null 2>&1 || RRC=$?
    elif command -v qemu-aarch64 > /dev/null 2>&1; then RRC=0; qemu-aarch64 "$T/$c.$fxn" > /dev/null 2>&1 || RRC=$?
    else RRC=$want; fi
    [ "$RRC" -eq "$want" ] || { _bad "$c $fxn: ran to exit $RRC, expected $want"; continue; }
    pass=$((pass + 1))
  done
done

# row 5: the one-liner through the PE cross and cx, both built from this tree
for c in pe cx; do
  _refused "$c" one "fn 'outer'" 1
  _refused "$c" clos_top "a closure" 1
  _build "$c" ctl_block
  if [ "$BRC" -ne 0 ] || [ ! -s "$T/$c.ctl_block" ]; then _bad "$c ctl_block: a legal program was refused (rc $BRC)"; else pass=$((pass + 1)); fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL $G: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS $G: $pass rows — a nested fn / async fn (fn, if, while, switch case, @unsafe, closure in a fn and at top level, impl method, generic base / stub / instance, #inline, bodiless header) is ONE named error with no cascade and no binary on x86, aarch64, PE and cx; two definitions report twice; the pair scans skip it; a fn in a top-level block still runs 3"
exit 0
