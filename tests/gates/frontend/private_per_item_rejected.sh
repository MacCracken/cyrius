#!/bin/sh
# private_per_item_rejected.sh — v6.5.56. `private fn h()` must be REJECTED, not silently
# reinterpreted as a file-level declaration.
#
# THE DEFECT, twelve releases live. `private` flips the FILE it sits in (`_TL_VIS`,
# src/frontend/parse.cyr) — deliberately, because a running per-item flag would leak into every
# file included after it. But the per-item spelling `private fn h(): i64 { ... }` parsed with
# **no diagnostic** and privatised the ENTIRE FILE, `main` included. It reads exactly like the
# per-item visibility other languages have, so it is the spelling a user reaches for first.
#
# ⭐ THE DISCRIMINATOR IS THE LINE, not the next token. `private` alone on its own line followed
# by `fn h()` on the NEXT line is the legitimate file-level form and must keep working — so a
# naive "reject if the next token is `fn`" test would break every correct use. Axes 2 and 3 are
# what stop that fix from being written.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL: private_per_item_rejected: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: private_per_item_rejected: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# 6.7.17: the piok rows also run under wine, in a PRIVATE prefix under $T (never ~/.wine), torn down with its server dir.
_wine_down() {
  [ -d "$T/wine" ] || return 0
  _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$T/wine" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$T/wine" 2>/dev/null || echo 0)")"
  WINEPREFIX="$T/wine" wineserver -k >/dev/null 2>&1 || true
  WINEPREFIX="$T/wine" wineserver -w >/dev/null 2>&1 || true
  rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL private_per_item_rejected: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL private_per_item_rejected: stage1 build failed"; exit 1; }
chmod +x "$T/cc"
fail=0

# ⛔ 6.6.17 — A THROWAWAY CYRIUS_HOME STAGED FROM THE TREE. Axes 4, 6 and 7 compile inside $T/c,
# where `include "lib/syscalls.cyr"` is not on disk, so cycc resolves it through its fallback:
# $CYRIUS_HOME/versions/<V>/lib/, else $HOME/.cyrius/versions/<V>/lib/. Run from a shell, those
# axes tested the LIVE store's lib instead of this tree's, and failed under a store-less HOME.
# $H/versions/<VERSION>/lib holds links to this tree's lib/ entries (read, never written), and
# axis 7 proves the compiles resolve there. CHANGELOG [6.6.17]
V=$(tr -d '[:space:]' < "$R/VERSION")
H="$T/home"
mkdir -p "$H/versions/$V/lib" || { echo "FAIL private_per_item_rejected: cannot stage a CYRIUS_HOME under $T"; exit 1; }
for e in "$R"/lib/*; do ln -s "$e" "$H/versions/$V/lib/" || { echo "FAIL private_per_item_rejected: cannot stage $e"; exit 1; }; done
[ "$(readlink "$H/versions/$V/lib/syscalls.cyr")" = "$R/lib/syscalls.cyr" ] || { echo "FAIL private_per_item_rejected: the staged home's lib/syscalls.cyr is not this tree's ($(readlink "$H/versions/$V/lib/syscalls.cyr"))"; exit 1; }

# axis 1 — the per-item form must HARD ERROR and say why.
printf 'include "lib/syscalls.cyr"\nprivate fn helper(): i64 { return 7; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a1.cyr"
if "$T/cc" < "$T/a1.cyr" > /dev/null 2>"$T/a1.err"; then
  echo "FAIL private_per_item_rejected axis1: 'private fn h()' COMPILED — it silently privatises the whole file including main"
  fail=1
else
  grep -q "per-item" "$T/a1.err" || { echo "FAIL private_per_item_rejected axis1: rejected without the explaining message"; sed -n 1,2p "$T/a1.err"; fail=1; }
fi

# ⚠ 6.6.5 — every status that is DATA here (a probe's exit code, a refused compile) is
# captured into a variable through `|| rc=$?`, never left bare. Axes 2 and 3 used to run
# `"$T/cc" < a2.cyr … && "$T/a2"` and read `$?`, so under `bash -eo pipefail` the probe's
# exit code 7 killed the script at that line — the file exited 7 with NO output and the
# four axes below it never ran. check.sh invokes gates with `sh`, so nothing was red; a CI
# runner that uses bash -e would have silently skipped most of this file.
run_rc() {   # run_rc <src> <bin> -> echoes the program's exit code, or -1 if it did not build
  _s=$1; _b=$2; _c=0
  "$T/cc" < "$_s" > "$_b" 2>/dev/null || _c=$?
  if [ ! -s "$_b" ]; then echo "-1"; return 0; fi
  chmod +x "$_b"; _r=0; "$_b" || _r=$?; echo "$_r"
}

# axis 2 — the file-level form (own line) must STILL WORK. This is what stops the axis-1 fix
# from being written as "reject if followed by fn".
printf 'include "lib/syscalls.cyr"\nprivate\nfn helper(): i64 { return 7; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a2.cyr"
r2=$(run_rc "$T/a2.cyr" "$T/a2")
[ "$r2" = "7" ] || { echo "FAIL private_per_item_rejected axis2: file-level 'private' on its own line no longer works (got $r2)"; fail=1; }

# axis 3 — the `private;` form must still work too (the trailing semicolon closes the statement,
# so a following `fn` on the SAME line is legal there).
printf 'include "lib/syscalls.cyr"\nprivate; fn helper(): i64 { return 9; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a3.cyr"
r3=$(run_rc "$T/a3.cyr" "$T/a3")
[ "$r3" = "9" ] || { echo "FAIL private_per_item_rejected axis3: 'private;' form regressed (got $r3)"; fail=1; }

# ⛔ 6.6.5 — axis 3b. `private` as the LAST TOKEN of a compiland, with no trailing newline.
# LEX appends its EOF token with ADDTOK(S, 12, 0) on whatever line the source ended on, so
# the EOF shares the marker's line and the line discriminator read it as the per-item form:
# the first cut of the 6.6.5 pre-pass answered "per-item `private` is not supported" to a
# source that breaks no such rule. The file-level form must be accepted wherever it appears,
# including as the final byte. ⚠ The fixture is written with printf and NO trailing \n — a
# heredoc would add one and the row would test nothing.
printf 'include "lib/syscalls.cyr"\nfn helper(): i64 { return 11; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\nprivate' > "$T/a3b.cyr"
r3b=$(run_rc "$T/a3b.cyr" "$T/a3b")
[ "$r3b" = "11" ] || { echo "FAIL private_per_item_rejected axis3b: 'private' as the final token (no trailing newline) did not build+run (got $r3b)"; fail=1; }
"$T/cc" < "$T/a3b.cyr" > /dev/null 2> "$T/a3b.err" || true
if grep -q "per-item" "$T/a3b.err" 2>/dev/null; then
  echo "FAIL private_per_item_rejected axis3b: 'private' at EOF was reported as the per-item form — the EOF token is not 'something on the line'"; fail=1
fi

# ⛔ 6.6.5 — axes 4 and 5. The v6.5.56 rejection was emitted from `_TL_VIS`, which BOTH
# parser passes walk, and it marked the file private BEFORE it rejected. Two consequences,
# both live for nine releases and neither visible to axes 1-3:
#   * the diagnostic printed TWICE for one `private fn h()`;
#   * the file was flipped private anyway, so a LEGITIMATE sibling fn in it was then
#     reported "is private to its file" at its caller — a false cascade blaming innocent
#     code for a mistake made elsewhere in the file, which is worse than the original
#     silence because it points the reader at the wrong line.
# Both are fixed by doing the work once, in the pre-pass that runs before either parser
# pass (`_PRIV_PRESCAN`, src/frontend/parse.cyr), and marking ONLY the accepted form.
mkdir -p "$T/c/lib"
cat > "$T/c/lib/a4.cyr" <<'EOF'
fn a4_g(): i64 { return 7; }
private fn a4_h(): i64 { return 1; }
EOF
cat > "$T/c/a4.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/a4.cyr"
fn main(): i64 { return a4_g(); }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/c" && CYRIUS_HOME="$H" "$T/cc" < a4.cyr > a4.bin 2> a4.err ) || true
c4=$(grep -c "per-item" "$T/c/a4.err" 2>/dev/null || true)
[ -n "$c4" ] || c4=0
[ "$c4" = "1" ] || { echo "FAIL private_per_item_rejected axis4: the diagnostic was emitted $c4 times, expected exactly 1"; fail=1; }
if grep -q "is private to its file" "$T/c/a4.err" 2>/dev/null; then
  echo "FAIL private_per_item_rejected axis5: the REJECTED per-item form still privatised the file — a legitimate sibling fn is now reported private:"
  grep -m2 "is private to its file" "$T/c/a4.err" | sed 's/^/      /' || true
  fail=1
fi

# axis 6 — anti-vacuous for axis 5: with the per-item line REMOVED, the same two files must
# compile and run, so axis 5 cannot be satisfied by a fixture that never linked anyway. The
# expected exit is computed here, not read back from the compiler.
G=7
cat > "$T/c/lib/a6.cyr" <<EOF
fn a6_g(): i64 { return $G; }
fn a6_h(): i64 { return 1; }
EOF
cat > "$T/c/a6.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/a6.cyr"
fn main(): i64 { return a6_g(); }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/c" && CYRIUS_HOME="$H" "$T/cc" < a6.cyr > a6.bin 2>/dev/null ) || true
if [ -s "$T/c/a6.bin" ]; then
  chmod +x "$T/c/a6.bin"; g6=0; ( cd "$T/c" && ./a6.bin ) || g6=$?
  [ "$g6" = "$G" ] || { echo "FAIL private_per_item_rejected axis6: control program exited $g6, expected $G"; fail=1; }
else
  echo "FAIL private_per_item_rejected axis6: the control program (no per-item line) did not build"; fail=1
fi

# axis 7 — axes 4 and 6 resolved their lib through the STAGED home, not through whatever store
# the invoking environment holds: a lib file that exists ONLY in the staged home must resolve
# from $T/c. With the compiles run bare (the pre-6.6.17 shape) the include falls through to
# the live store, which has no such file, and this axis is red.
printf 'fn ppir_canary(): i64 { return 42; }\n' > "$T/ppir_canary.cyr"
ln -s "$T/ppir_canary.cyr" "$H/versions/$V/lib/ppir_canary.cyr"
cat > "$T/c/a7.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/ppir_canary.cyr"
fn main(): i64 { return ppir_canary(); }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/c" && CYRIUS_HOME="$H" "$T/cc" < a7.cyr > a7.bin 2>/dev/null ) || true
if [ -s "$T/c/a7.bin" ]; then
  chmod +x "$T/c/a7.bin"; g7=0; ( cd "$T/c" && ./a7.bin ) || g7=$?
  [ "$g7" = "42" ] || { echo "FAIL private_per_item_rejected axis7: the staged-home canary program exited $g7, expected 42"; fail=1; }
else
  echo "FAIL private_per_item_rejected axis7: a lib file present only in the staged CYRIUS_HOME did not resolve — the compiles are not reading the staged home"; fail=1
fi

# ── PI: BELOW MODULE SCOPE AND AFTER THE FIRST STATEMENT (6.7.16) ─────────────────────────────────────────────────
# issues/archived/2026-10-19-per-item-private-below-module-scope-is-two-errors.md. In the declaration zone `private var x = 1;`
# was one error (`_TL_VIS` steps the marker); in a fn body, a block or after the first top-level statement PARSE_STMT
# met the token the pre-pass had already reported: "unexpected private" too, and `private fn g` in a fn body "fn 'g'
# is defined inside fn 'f'" as well — two or three errors for one mistake. Now `_dl_priv` (src/frontend/
# parse_fn_def.cyr, from `_decl_inner`) steps the marker (`_priv_is_item`, the pre-pass's own test): a `var` /
# `const` / statement after it parses and declares; a `fn` where a fn is defined (module scope, a top-level block) is
# defined; a `fn` in a fn body, or a declaration the declaration-section rule refuses, is stepped as that refusal
# steps it, its names and fns entered as reported. Pass 1's tail walk steps a `private` alone, so a `fn` after it is
# prescanned and a late declaration's names are filled before any use is parsed. Every row on five legs: the
# x86_64, PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1) compilers and the aarch64 / cx compilers built from
# this tree — the exact error lines, rc != 0, no binary; the controls compile clean on each and run on x86_64.
#   PI1-PI3  the filed repros verbatim: one error each (two, two and three before)
#   PI4  the body parses on: `private var x` used (no "undefined variable 'x'"), `private const C`, `private x = 2;`,
#        a switch arm, after the first statement — each one error + the next mistake (`zz`) reported
#   PI5  a `fn` where a fn is defined is DEFINED: after the first statement (its body's `zz`, a call's arity), called
#        before it (prescanned: no "undefined function"), in a top-level block
#   PI6  a `fn` in a fn body is stepped: its body unread, a call of it adds nothing, the outer body parses on
#   PI7  a declaration after the marker: `private struct` / `enum` / `pub var` in a fn body and a block, a late
#        `private struct Q` used before (an earlier fn's `q: *Q`) and after (`Q { 5 }`, `q.y`) — one error + `zz`
#   PI8  a generic fn at two instances: once
#   PI9  a late include whose file holds `private struct Q`: the per-item error and the include line's (two sites)
#   PC1-PC2 controls: the zone's `private var x = 1;` one error; the file-level `private` line (compiles, runs 7);
#        PC3 (6.7.17, D31) is in the PL section below
# MUTATION LEDGER (2026-10-21, f16; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from that copy, so every leg's compiler carries the mutant):
#   the lane before it (448601b3d)                    -> RED PI1-PI9, 45 row-legs (PI9: "unexpected private" too)
#   `_decl_inner` without its `_dl_priv` line         -> RED PI1-PI9, 45
#   `_dl_priv` leaving a fn-body `fn` to PARSE_PROG   -> RED PI3 PI6 PI8, 15 ("fn 'g' is defined inside fn 'f'")
#   `_dl_priv` stepping a module-scope `fn` too       -> RED PI5, 5 (g's body unread, its call's arity unchecked)
#   pass 1's tail walk without its `private` step     -> RED PI7, 5 ("type 'Q' is declared after its use")
#   `_dl_incl_at` reporting for `rep` 1 only          -> RED PI9, 5 (the include line not reported)
LEGS="x86 pe macho"
if "$T/cc" < "$R/src/main_aarch64.cyr" > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"; LEGS="$LEGS a64"
else echo "FAIL private_per_item_rejected: src/main_aarch64.cyr did not build"; fail=1; fi
if "$T/cc" < "$R/src/main_cx.cyr" > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ]; then chmod +x "$T/cc_cx"; LEGS="$LEGS cx"
else echo "FAIL private_per_item_rejected: src/main_cx.cyr did not build"; fail=1; fi
PIN=0
pcomp() {   # <leg> <src> <out>: rc in PRC
  PRC=0
  case "$1" in
    x86)   timeout 60 "$T/cc" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
    pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$T/cc" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
    macho) CYRIUS_MACHO=1 timeout 60 "$T/cc" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
    a64)   timeout 60 "$T/cc_a64" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
    cx)    timeout 60 "$T/cc_cx" < "$2" > "$3" 2> "$3.err" || PRC=$? ;;
  esac
}
# pirow <id> <what> <source> <want-lines>: refused on every leg (rc != 0, no binary), its error / warning lines exactly
pirow() {
  printf '%s' "$3" > "$T/$1.cyr"
  printf '%s\n' "$4" > "$T/$1.want"
  for leg in $LEGS; do
    o="$T/$1_$leg"
    pcomp "$leg" "$T/$1.cyr" "$o"
    PIN=$((PIN + 1))
    grep -E '^(error|warning)' "$o.err" > "$o.got" || true
    if [ "$PRC" -eq 0 ]; then echo "FAIL private_per_item_rejected $1 $leg: $2: rc 0 - want the refusal"; fail=1
    elif ! cmp -s "$o.got" "$T/$1.want"; then echo "FAIL private_per_item_rejected $1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"; fail=1
    elif [ -s "$o" ]; then echo "FAIL private_per_item_rejected $1 $leg: $2: refused, but a binary was written"; fail=1
    else echo "  ok $1 $leg: $2"; fi
  done
}
# piok <id> <what> <source> <exit>: compiles clean on every leg (no error / warning line, a binary), runs <exit> on x86_64
# and (6.7.17) on aarch64 under qemu-aarch64, cx under the tree's cxvm and PE under wine (a private prefix) where the box
# has the runner — each missing one said by name below; Mach-O compiles only
piok() {
  printf '%s' "$3" > "$T/$1.cyr"
  for leg in $LEGS; do
    o="$T/$1_$leg"
    pcomp "$leg" "$T/$1.cyr" "$o"
    PIN=$((PIN + 1))
    if [ "$PRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
      echo "FAIL private_per_item_rejected $1 $leg: $2: rc $PRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"; fail=1
    elif pexec "$leg" "$o"; then
      if [ "$x" = "$4" ]; then echo "  ok $1 $leg: $2 (exit $4)"; else echo "FAIL private_per_item_rejected $1 $leg: $2: exit $x, want $4"; fail=1; fi
    else echo "  ok $1 $leg: $2"; fi
  done
}
# pexec <leg> <binary>: x = its exit code; 1 = this leg is not run here (Mach-O; a runner this box lacks)
pexec() {
  x=0
  case "$1" in
    x86) chmod +x "$2"; timeout 30 "$2" > /dev/null 2>&1 || x=$? ;;
    a64) [ "$PQEMU" = 1 ] || return 1; chmod +x "$2"; timeout 300 qemu-aarch64 "$2" > /dev/null 2>&1 || x=$? ;;
    cx)  [ -s "$T/cxvm" ] || return 1; timeout 300 "$T/cxvm" < "$2" > /dev/null 2>&1 || x=$? ;;
    pe)  [ "$PWINE" = 1 ] || return 1
         cp "$2" "$2.exe"
         (cd "$T" && WINEPREFIX="$T/wine" HOME="$T/whome" XDG_CACHE_HOME="$T/whome/.cache" WINEDEBUG=-all \
             WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$2.exe" > /dev/null 2>&1) || x=$? ;;
    *)   return 1 ;;
  esac
  return 0
}
PQEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && PQEMU=1
PWINE=0; command -v wine > /dev/null 2>&1 && PWINE=1
[ "$PQEMU" = 1 ] || echo "  SKIP: the piok rows' aarch64 RUNS (qemu-aarch64 not installed; the compiles still run)"
[ "$PWINE" = 1 ] || echo "  SKIP: the piok rows' PE RUNS (wine not installed; the compiles still run)"
"$T/cc" < "$R/programs/cxvm.cyr" > "$T/cxvm" 2> /dev/null && [ -s "$T/cxvm" ] && chmod +x "$T/cxvm" \
  || { echo "FAIL private_per_item_rejected: programs/cxvm.cyr did not build"; fail=1; }
PI='per-item `private` is not supported; put `private` alone on a line to make the file private'
ZZ="undefined variable 'zz' (missing include or enum?)"

pirow PI1 "filed: private var in a fn body" "$(printf 'fn f(): i64 { private var x = 1; return x; }\nsyscall(60, f());\n')
" "error:<source>:1:15: $PI"
pirow PI2 "filed: private var after the first statement" "$(printf 'var a = 1;\na = 2;\nprivate var x = 1;\nsyscall(60, x);\n')
" "error:<source>:3:1: $PI"
pirow PI3 "filed: private fn in a fn body" "$(printf 'fn f(): i64 { private fn g(): i64 { return 1; } return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: $PI"
pirow PI4 "the body parses on: var / const / a statement / a switch arm / top level" 'fn f(): i64 {
    private var x = 1;
    private const C = 5;
    var y = 1;
    private y = 2;
    switch (y) { case 2: private var w = 3; return x + C + w + zz; }
    return x + y + C + zz;
}
var a = 1;
a = 2;
private var x = 1;
syscall(60, f() + x + zz);
' "error:<source>:2:5: $PI
error:<source>:3:5: $PI
error:<source>:5:5: $PI
error:<source>:6:26: $PI
error:<source>:11:1: $PI
error:<source>:6:64: $ZZ
error:<source>:7:24: $ZZ
error:<source>:12:23: $ZZ"
pirow PI5 "a fn where a fn is defined: defined (after code, called before it, in a block)" 'var a = 1;
a = 2;
a = g(1) + h();
private fn g(n): i64 { return n + zz; }
private fn h(): i64 { return 3; }
if (a == 1) { private fn k(): i64 { return qq; } a = k(); }
syscall(60, h(7) + a);
' "error:<source>:4:1: $PI
error:<source>:5:1: $PI
error:<source>:6:15: $PI
error:<source>:4:35: $ZZ
error:<source>:6:44: undefined variable 'qq' (missing include or enum?)
error:<source>:7: 'h' expects 0 arguments, got 1"
pirow PI6 "a fn in a fn body: stepped, its call quiet, the body parses on" 'fn f(): i64 {
    private fn g(): i64 { return qq; }
    private fn h(n);
    return g() + h(1) + zz;
}
syscall(60, f());
' "error:<source>:2:5: $PI
error:<source>:3:5: $PI
error:<source>:4:25: $ZZ"
pirow PI7 "a declaration after the marker: stepped, its names used quietly" 'fn h(q: *Q): i64 { return q.y; }
fn f(): i64 {
    private struct S { y; }
    private enum E { A, B }
    private pub var x = 1;
    var s = S { 4 };
    return s.y + E.B + x + zz;
}
var a = 1;
a = 2;
if (a == 2) { private struct T { t; } var t = T { 1 }; a = t.t + zz; }
private struct Q { y; }
var q = Q { 5 };
syscall(60, h(&q) + q.y + f() + zz);
' "error:<source>:3:5: $PI
error:<source>:4:5: $PI
error:<source>:5:5: $PI
error:<source>:11:15: $PI
error:<source>:12:1: $PI
error:<source>:7:28: $ZZ
error:<source>:11:66: $ZZ
error:<source>:14:33: $ZZ"
pirow PI8 "a generic fn at two instances: once" 'fn f<T>(v: T): i64 {
    private var x = 1;
    private fn g(): i64 { return 1; }
    return x + zz;
}
syscall(60, f<i64>(1) + f<i32>(2));
' "error:<source>:2:5: $PI
error:<source>:3:5: $PI
error:<source>:4:16: $ZZ"
mkdir -p "$T/pi9"
printf 'fn pa(): i64 { return 1; }\nprivate struct PQ { y; }\nfn pf(): i64 { return 2; }\n' > "$T/pi9/pq.cyr"
CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1; export CYRIUS_ALLOW_ABSOLUTE_INCLUDES   # the included file lives in the scratch dir
pirow PI9 "a late include holding a per-item private struct: both sites" "var a = 1;
a = 2;
include \"$T/pi9/pq.cyr\"
syscall(60, pa() + pf());
" "error:$T/pi9/pq.cyr:2:1: $PI
error:<source>:3:1: an include of a file that declares a \`struct\` ($T/pi9/pq.cyr:2) must come before the first top-level statement (line 2)"
unset CYRIUS_ALLOW_ABSOLUTE_INCLUDES
pirow PC1 "control: the zone's private var (one error, as before)" "$(printf 'private var x = 1;\nsyscall(60, x + zz);\n')
" "error:<source>:1:1: $PI
error:<source>:2:17: $ZZ"
piok PC2 "control: the file-level private line" "$(printf 'private\nfn helper(): i64 { return 7; }\nsyscall(60, helper());\n')
" 7
# ── PL: THE FILE-LEVEL LINE AFTER THE FIRST STATEMENT (6.7.17, the user's D31, 2026-10-22: "Accept it") ──────────────
# issues/2026-10-21-directive-line-tails-unread-use-without-path-late-private.md (row 5). `_PRIV_PRESCAN` already marked
# the file from the line wherever it sits (the guide: "the WHOLE file, wherever in it the marker sits"); only PARSE_STMT
# refused it — "unexpected private", and with no `;` the refusal's latch swallowed the next statement's own error
# (`zz` never reported). `_dl_priv_file` (src/frontend/parse_fn_def.cyr) steps the marker and an optional `;` at module
# scope, as `_TL_VIS` does in the declaration zone; in a fn body or a block it stays "unexpected private", now in sync.
#   PC3  re-pinned: the line after the first statement compiles and runs (exit 2; "unexpected private" through 6.7.16)
#   PL1  row 5 verbatim: its one error is the next line's `zz`
#   PL2  `private;` after the first statement, and a statement after the `;` on its line: both run
#   PL3  a late line in an INCLUDED file makes that whole file private: a caller of its fn is refused, a fn above the
#        line included ('bh' is private to its file), and PL3b its `public fn` is reachable (exit 6)
#   PL4  a fn body, a top-level block and a switch arm (where the line is no file-level marker): "unexpected private"
#        as before, and now the next statement's own `zz` too (the resync skipped it)
#   PL5  a generic fn at two instances: once
# MUTATION LEDGER (2026-10-22, lane fea FA1; a scratch copy of the tree with the one change, its 2-stage cycc run, this
# gate run from that copy, so every leg's compiler carries the mutant):
#   `_dl_priv` answering 0 for the file-level line again (6.7.16) -> RED PC3 PL1-PL5 PL3b, 35 row-legs ("unexpected
#                                                                    private", `zz` swallowed)
#   the body refusal without its in-sync step and latch release    -> RED PL4 PL5, 10 (the next statement's `zz` lost)
piok PC3 "D31: the file-level line after the first statement compiles" "$(printf 'var a = 1;\na = 2;\nprivate\nsyscall(60, a);\n')
" 2
pirow PL1 "row 5 verbatim: the next line's zz is the one error" "$(printf 'var a = 1;\na = 2;\nprivate\nsyscall(60, a + zz);\n')
" "error:<source>:4:17: $ZZ"
piok PL2 "private; after the first statement, a statement after it on the line" "$(printf 'var a = 1;\na = 2;\nprivate;\na = a + 1; private; a = a + 1;\nsyscall(60, a);\n')
" 4
mkdir -p "$T/pl3"
printf 'public fn bp(): i64 { return bh() + 1; }\nfn bh(): i64 { return 5; }\nvar bx = 1;\nbx = 2;\nprivate\n' > "$T/pl3/b.cyr"
CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1; export CYRIUS_ALLOW_ABSOLUTE_INCLUDES   # the included file lives in the scratch dir
pirow PL3 "a late line in an included file: the whole file private" "include \"$T/pl3/b.cyr\"
syscall(60, bh());
" "error:<source>:2:16: 'bh' is private to its file"
piok PL3b "... its public fn is reachable" "include \"$T/pl3/b.cyr\"
syscall(60, bp());
" 6
unset CYRIUS_ALLOW_ABSOLUTE_INCLUDES
pirow PL4 "a fn body, a top-level block, a switch arm: unexpected private, then the next statement's zz" 'fn f(): i64 { var a = 1;
private
a = zz;
switch (a) { case 1:
private
a = zz2; }
return a; }
var b = 1;
if (b == 1) {
private
b = zz3; }
syscall(60, f() + b);
' "error:<source>:2:1: unexpected private
error:<source>:3:5: $ZZ
error:<source>:5:1: unexpected private
error:<source>:6:5: undefined variable 'zz2' (missing include or enum?)
error:<source>:10:1: unexpected private
error:<source>:11:5: undefined variable 'zz3' (missing include or enum?)"
pirow PL5 "a generic fn at two instances: once" 'fn g<T>(x: T): i64 { var a = 1;
private
a = zz;
return a; }
syscall(60, g<i64>(1) + g<i32>(2));
' "error:<source>:2:1: unexpected private
error:<source>:3:5: $ZZ"
# The corpus floor (6.7.16): 12 rows on five legs; 6.7.17: 18. A row or a leg lost reads RED, never green.
[ "$PIN" -ge 90 ] || { echo "FAIL private_per_item_rejected: the PI / PL rows ran $PIN row-legs (floor 90) - rows or legs were lost"; fail=1; }

[ $fail -eq 0 ] || exit 1
echo "PASS private_per_item_rejected: per-item form errors ONCE, does not privatise the file, and the own-line / 'private;' / at-EOF forms still work (lib resolved from a CYRIUS_HOME staged from the tree); below module scope and after the first statement it is the one error, $PIN row-legs on $LEGS"
exit 0
