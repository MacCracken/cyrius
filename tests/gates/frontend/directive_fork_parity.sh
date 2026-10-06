#!/bin/sh
# directive_fork_parity.sh — v6.6.3. A directive must be handled by EVERY compiler fork,
# and must not be INERT on any of them.
#
# WHY THIS GATE EXISTS. cyrius has seven per-target forks of the entry point
# (src/main.cyr + main_aarch64{,_macho,_native}.cyr, main_win.cyr, main_x86_macho.cyr,
# main_cx.cyr). Each carries its OWN copy of the top-level directive dispatch, in TWO
# regions: a pass-1 declaration scan that must CONSUME the token, and a pass-2 dispatch
# that ARMS the pending flag. A new directive needs BOTH halves in ALL forks, and the
# failure modes of missing each half are different and BOTH silent-ish:
#
#   missing CONSUME -> the pass-1 scan falls into its catchall else and TERMINATES, so
#                      every declaration after the directive is unregistered. Surfaces as
#                      a nonsense diagnostic pointing at an innocent later line
#                      ("unexpected struct"), hundreds of lines from the real trigger.
#   missing ARM     -> the directive compiles cleanly and DOES NOTHING, forever, on that
#                      target only. No error, no warning, correct results. This is the
#                      v6.5.63 defect (#inline had no handler at all and silently did
#                      nothing while consumers wrote it and recorded measuring it).
#
# v6.6.3 shipped #inline's pass-1 consume into all seven forks and its pass-2 ARM into
# ONE (main.cyr). Result: CI red on native aarch64 (compile failure from the missing
# consume at the SECOND region in four forks) and — underneath that, invisible — #inline
# INERT on aarch64, aarch64-macho, x86-macho and PE. Measured before the fix: the emitted
# binary was BYTE-IDENTICAL with and without the directive on every one of those targets.
#
# ⭐ Axis 2 is the one that cannot be faked. A static grep can be satisfied by adding a
# token to a guard list while arming nothing — which is exactly the half-fix that makes
# CI green and leaves the feature dead. So axis 2 does not read the source at all: it
# COMPILES the same fixture twice through each fork's own compiler, once with the
# directive and once without, and requires the two outputs to DIFFER. Byte-identical
# output is proof the directive is inert. No disassembler needed, so it cannot degrade
# into a skip.
#
# ⛔ 6.6.9 — THIS GATE READ GREEN ON THE CLASS IT WAS BUILT FOR. Axis 1 paired only #naked with
# #inline and axis 2 measured only #inline, so when six forks consumed #must_use / #deprecated /
# #pure / #io / #alloc before the first top-level statement and ARMED NOTHING — every one of those
# warnings silent on aarch64, both Mach-O targets, PE and cx, for every library attribute — it
# passed. The fix removed the fifteen copies of the dispatch (7 forks x 2 passes + PARSE_PROG)
# in favour of ONE fn, `_tl_directive` (src/frontend/parse_fn.cyr), and this gate now checks:
#   axis 1   STRUCTURE — no fork and no PARSE_PROG dispatches a directive token itself; each
#            fork runs the shared scans (6.6.17: _tl_pass1 / _tl_pass2, src/frontend/parse_fn.cyr),
#            which call _tl_directive once per pass. (A fork that re-grows its own branch for a
#            token is exactly how the drift started.)
#   axis 2   #inline non-inert + the #inline→#derive survival shape (unchanged, v6.6.3).
#   axis 2c  THE WARNINGS: #deprecated("m"), a discarded #must_use result, #pure→#io and
#            #pure→#alloc print all four on every runnable fork, in BOTH positions (before the
#            first statement, via pass 2; after it, via PARSE_PROG). An attribute-free control
#            with the same calls prints none — without it an always-on warning would pass.
#   axis 2d  a top-level #assert is a DECLARATION-phase directive: a struct after it is still
#            accepted (it used to end pass 2, and "unexpected struct" followed), and a false one
#            still fails the build. A WRAPPED #assert (operands, `,` or message on the next
#            line) must leave both passes on the same token: pass 1 used to skip only the
#            directive's own line, stop on the continuation, and leave every later struct/enum/
#            global unregistered. It must build, and on x86 RUN to 42; a false wrapped one fails.
#   axis 2e  a bare `#deprecated` is refused BY NAME in both positions (it was a silent no-op
#            before the first statement and "expected '(', got fn" after it).
#   axis 2f  #naked stays INERT on cx in both positions (a bytecode VM has no return address to
#            leave unframed; lib/fdlopen.cyr's cx arm is a framed `return 0`), and is ARMED on
#            x86 (the same body is refused there, which proves the arm).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: directive_fork_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL directive_fork_parity: no compiler at $CC"; exit 1; }
cd "$R" || exit 1

FORKS="main.cyr main_aarch64.cyr main_aarch64_macho.cyr main_aarch64_native.cyr main_win.cyr main_x86_macho.cyr main_cx.cyr"

# ── axis 1 — STRUCTURE: one dispatcher, and nobody else dispatches ──────────────────────
# The directive tokens: 107 #assert, 109 #regalloc, 122 #must_use, 124 #deprecated, 125 #pure,
# 126 #io, 127 #alloc, 133 #naked, 163 #inline. The pending flags they arm are listed below.
TOKS='107|109|122|124|125|126|127|133|163'
FLAGS='_regalloc_pending|_must_use_pending|_deprecated_pending|_deprecated_msg_pending|_pure_pending|_io_pending|_alloc_pending|_naked_pending|_inline_pending'
bad=""
for f in $FORKS; do
  # 1a — a fork that tests a directive token itself has re-grown its own dispatch
  hits=$(grep -nE "PEEKT\(S\) == ($TOKS)\b" "src/$f" | cut -d: -f1 | tr '\n' ' ')
  [ -n "$hits" ] && bad="$bad\n    src/$f:$hits tests a directive token (route it through _tl_directive)"
  # 1b — ... or arms a pending flag itself
  hits=$(grep -nE "($FLAGS) = " "src/$f" | cut -d: -f1 | tr '\n' ' ')
  [ -n "$hits" ] && bad="$bad\n    src/$f:$hits arms a directive flag itself"
  # 1c — the fork runs the SHARED scans (6.6.17), which make the consume and the arm call;
  # toplevel_scan_shared.sh pins the rest of that structure
  n0=$(grep -c '^_tl_pass1(S, [01]);' "src/$f"); n1=$(grep -c '^_tl_pass2(S, [01]);' "src/$f")
  [ "$n0" -eq 1 ] && [ "$n1" -eq 1 ] || bad="$bad\n    src/$f: _tl_pass1 x$n0, _tl_pass2 x$n1 (expected 1 and 1)"
done
# 1c' — the shared pass-1 scan consumes (arm=0) and the shared pass-2 scan arms (arm=1), once each
for pr in "_tl_scan1 0" "_tl_scan2 1"; do
  set -- $pr
  nb=$(awk -v n="fn $1(" 'index($0, n) == 1 {on=1} on {print} on && /^}/ {exit}' src/frontend/parse_fn.cyr | grep -c "_tl_directive(S, $2) == 1")
  [ "$nb" -eq 1 ] || bad="$bad\n    src/frontend/parse_fn.cyr: $1 calls _tl_directive(S, $2) x$nb (expected 1)"
done
# 1d — PARSE_PROG (the post-first-statement path) goes through the same fn
pp=$(awk '/^fn PARSE_PROG\(S\)/{on=1} on{print} on&&/^}/{exit}' src/frontend/parse.cyr)
echo "$pp" | grep -q '_tl_directive(S, 1) == 1' || bad="$bad\n    src/frontend/parse.cyr: PARSE_PROG does not call _tl_directive(S, 1)"
echo "$pp" | grep -qE "typ == ($TOKS)\b" && bad="$bad\n    src/frontend/parse.cyr: PARSE_PROG tests a directive token itself"
if [ -n "$bad" ]; then
  printf "FAIL directive_fork_parity axis1: a directive is dispatched outside _tl_directive:%b\n" "$bad"
  echo "  Each private copy is a place for a fork to consume a token and arm nothing — the silent"
  echo "  half (6.6.3 #inline, 6.6.9 #deprecated/#must_use/#pure). Add a directive in ONE place."
  exit 1
fi

# ── axis 2 — the directive must not be INERT on any fork buildable here ────────────────
# The two macho forks cannot RUN on Linux (they abort with 'mmap heap init failed'), so
# they are covered by the cross-OS leg on ecb/ach, not here. Everything else is measured.
cat > "$T/tmpl.cyr" <<'EOF'
include "lib/syscalls.cyr"
var ST = 0;
MARK
fn A_f0(s) { return load64(s + 0); }
MARK
fn A_f1(s) { return load64(s + 8); }
MARK
fn A_f2(s) { return load64(s + 16); }
MARK
fn A_f3(s) { return load64(s + 24); }
fn main(): i64 {
    var b[32];
    var i = 0;
    while (i < 4) { store64(&b + i * 8, i + 1); i = i + 1; }
    ST = &b;
    var acc = 0;
    var k = 0;
    while (k < 1000) { acc = acc + A_f0(ST) + A_f1(ST) + A_f2(ST) + A_f3(ST); k = k + 1; }
    return acc & 0xFF;
}
var e = main();
EOF
sed 's/^MARK$/#inline/' "$T/tmpl.cyr" > "$T/yes.cyr"
sed 's/^MARK$//'        "$T/tmpl.cyr" > "$T/no.cyr"

# The SHAPE that actually trips the second dispatch region: an #inline followed LATER by a
# #derive'd struct. A fixture with #inline before plain fns alone is NOT enough — measured:
# it still compiles and still differs when the second region's guard drops 163, so a gate
# built on it reads GREEN on the exact defect that turned CI red.
cat > "$T/shape.cyr" <<'EOF'
include "lib/syscalls.cyr"
#inline
fn sh_helper(a): i64 { return a + 1; }
#derive(accessors)
struct AfterInline { gamma; delta; }
fn main(): i64 { return sh_helper(1); }
var e = main();
EOF

RUNNABLE="main.cyr main_aarch64.cyr main_win.cyr main_cx.cyr"
checked=0
for f in $RUNNABLE; do
  "$CC" < "src/$f" > "$T/cc_$f" 2>/dev/null || { echo "FAIL directive_fork_parity axis2: could not build src/$f"; exit 1; }
  chmod +x "$T/cc_$f"
  # 2a — SURVIVAL. #inline followed by a #derive'd struct must still compile. A directive
  # the second region does not consume terminates the pass-1 scan, and the struct after it
  # is never registered: "error: unexpected struct", pointing at an innocent later line.
  "$T/cc_$f" < "$T/shape.cyr" > "$T/o_shape" 2>"$T/e_shape"
  if [ ! -s "$T/o_shape" ]; then
    echo "FAIL directive_fork_parity axis2a: src/$f cannot compile #inline followed by #derive"
    sed 's/^/      /' "$T/e_shape" | head -3
    echo "  A directive region is not consuming 163 — the pass-1 scan terminated and every"
    echo "  declaration after the #inline went unregistered."
    exit 1
  fi
  # 2b — NON-INERTNESS.
  "$T/cc_$f" < "$T/yes.cyr" > "$T/o_yes" 2>/dev/null
  "$T/cc_$f" < "$T/no.cyr"  > "$T/o_no"  2>/dev/null
  [ -s "$T/o_yes" ] && [ -s "$T/o_no" ] || { echo "FAIL directive_fork_parity axis2b: src/$f emitted nothing for the fixture"; exit 1; }
  if cmp -s "$T/o_yes" "$T/o_no"; then
    echo "FAIL directive_fork_parity axis2b: #inline is INERT in src/$f"
    echo "  The fixture compiled to a BYTE-IDENTICAL binary with and without the directive."
    echo "  The token is being consumed and ignored — the pass-2 region arms no flag."
    echo "  This is the v6.5.63 defect (a directive that silently does nothing), per-target."
    exit 1
  fi
  checked=$((checked + 1))
done

# Anti-vacuous: if the fork list ever shrinks to nothing, the loop above passes trivially.
[ "$checked" -ge 4 ] || { echo "FAIL directive_fork_parity axis2: only $checked fork(s) measured, expected >= 4"; exit 1; }

# ── axis 2c/2d/2e/2f — the warnings, #assert, bare #deprecated, cx #naked ─────────────────
# One body, two positions: "pre" puts the attributes before the first top-level statement (the
# forks' pass 2 handles them — where every library writes them); "post" puts a statement first
# (PARSE_PROG handles them). Both must behave the same on every fork.
cat > "$T/attr_body.cyr" <<'EOF'
#deprecated("use new_thing")
fn old_thing(a): i64 { return a + 1; }
#must_use
fn mu(a): i64 { return a * 2; }
#io
fn doio(a): i64 { return a; }
#alloc
fn doalloc(a): i64 { return a; }
#pure
fn p_io(a): i64 { return doio(a); }
#pure
fn p_alloc(a): i64 { return doalloc(a); }
fn main(): i64 {
    var x = old_thing(2);
    mu(3);
    return x + p_io(4) + p_alloc(1);
}
var r = main();
EOF
printf 'var e0 = 0;\n' > "$T/pre.cyr";  cat "$T/attr_body.cyr" >> "$T/pre.cyr"
printf 'var e0 = 0;\ne0 = 1;\n' > "$T/post.cyr"; cat "$T/attr_body.cyr" >> "$T/post.cyr"
# the control: the same calls, no attributes
grep -v '^#' "$T/attr_body.cyr" > "$T/ctl.cyr"
cat > "$T/assert.cyr" <<'EOF'
struct Q { x: i8; y: i8; }
#assert sizeof(Q) == 2, "sz";
struct R { a; b; }
fn main(): i64 { var q: R; q.a = 40; q.b = 2; return q.a + q.b; }
var r = main();
EOF
sed 's/== 2, "sz"/== 3, "sz"/' "$T/assert.cyr" > "$T/assert_false.cyr"
# The wrapped shapes: after the `,`, mid-comparison, and before the `,`.
cat > "$T/assert_wrap.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x: i8; y: i8; }
#assert 1 == 1,
  "wrapped after the comma";
#assert sizeof(P) ==
  2, "wrapped mid-comparison";
#assert 3 > 2
  , "wrapped before the comma";
struct Z { a; b; }
enum ZE { ZA = 40, ZB = 2 }
var zg = 0;
fn main(): i64 { var z: Z; z.a = ZA; z.b = ZB; zg = z.a + z.b; return zg; }
var rr = main();
sys_exit(rr);
EOF
sed 's/^  2, "wrapped mid-comparison"/  3, "wrapped mid-comparison"/' "$T/assert_wrap.cyr" > "$T/assert_wrap_false.cyr"
printf '#deprecated\nfn f(a): i64 { return a; }\nvar r = f(1);\n' > "$T/bare_pre.cyr"
printf 'var z = 0;\nz = 1;\n#deprecated\nfn f(a): i64 { return a; }\nvar r = f(1);\n' > "$T/bare_post.cyr"
# lib/fdlopen.cyr's cx shape: a #naked fn whose body is ordinary framed code
printf '#naked\nfn nk(): i64 { return 0; }\nvar r = nk();\n' > "$T/naked_pre.cyr"
printf 'var z = 0;\nz = 1;\n#naked\nfn nk(): i64 { return 0; }\nvar r = nk();\n' > "$T/naked_post.cyr"

W1="is deprecated: use new_thing"; W2="#must_use result of 'mu' is discarded"
W3="#pure fn calls #io fn 'doio'"; W4="#pure fn calls #alloc fn 'doalloc'"
rows=0
for f in $RUNNABLE; do
  c="$T/cc_$f"
  for pos in pre post; do
    "$c" < "$T/$pos.cyr" > "$T/o" 2>"$T/e"
    [ -s "$T/o" ] || { echo "FAIL directive_fork_parity axis2c: src/$f could not compile the $pos-position attribute fixture"; sed 's/^/      /' "$T/e" | grep -v 'routes n=' | head -3; exit 1; }
    for w in "$W1" "$W2" "$W3" "$W4"; do
      if ! grep -qF "$w" "$T/e"; then
        echo "FAIL directive_fork_parity axis2c: src/$f ($pos first statement) does not print: $w"
        echo "  The attribute is consumed and ARMS NOTHING on this fork — the warning is silent here and"
        echo "  loud on x86. This is the 6.6.9 defect; the fork must route through _tl_directive(S, 1)."
        exit 1
      fi
    done
    rows=$((rows + 1))
  done
  "$c" < "$T/ctl.cyr" > "$T/o" 2>"$T/e"
  if [ ! -s "$T/o" ] || grep -qE 'is deprecated|#must_use result|#pure fn calls' "$T/e"; then
    echo "FAIL directive_fork_parity axis2c: src/$f: the attribute-FREE control failed to build or printed attribute warnings"; exit 1
  fi
  # 2d — #assert is a declaration-phase directive
  "$c" < "$T/assert.cyr" > "$T/o" 2>"$T/e"
  if [ ! -s "$T/o" ]; then echo "FAIL directive_fork_parity axis2d: src/$f refuses a struct declared after a top-level #assert"; sed 's/^/      /' "$T/e" | grep -v 'routes n=' | head -3; exit 1; fi
  "$c" < "$T/assert_false.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -eq 0 ] || ! grep -q '#assert failed: sz' "$T/e"; then echo "FAIL directive_fork_parity axis2d: src/$f accepted a FALSE top-level #assert (rc $rc)"; exit 1; fi
  "$c" < "$T/assert_wrap.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then
    echo "FAIL directive_fork_parity axis2d: src/$f cannot compile a WRAPPED top-level #assert followed by a struct, an enum and a global (rc $rc)"
    sed 's/^/      /' "$T/e" | grep -v 'routes n=' | grep -E 'error' | head -3
    echo "  Pass 1 (_tl_assert arm=0) stopped somewhere other than where PARSE_STMT's #assert arm"
    echo "  stops; its scan ended there and everything declared below went unregistered."
    exit 1
  fi
  if [ "$f" = main.cyr ]; then
    chmod +x "$T/o"; "$T/o"; rc=$?
    [ "$rc" -eq 42 ] || { echo "FAIL directive_fork_parity axis2d: the wrapped-#assert fixture built on x86 but ran to $rc, expected 42"; exit 1; }
  fi
  "$c" < "$T/assert_wrap_false.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -eq 0 ] || ! grep -q '#assert failed: wrapped mid-comparison' "$T/e"; then echo "FAIL directive_fork_parity axis2d: src/$f accepted a FALSE wrapped #assert (rc $rc)"; exit 1; fi
  # 2e — bare #deprecated refused by name, both positions
  for pos in pre post; do
    "$c" < "$T/bare_$pos.cyr" > "$T/o" 2>"$T/e"; rc=$?
    if [ "$rc" -eq 0 ] || ! grep -q '#deprecated needs a message' "$T/e"; then
      echo "FAIL directive_fork_parity axis2e: src/$f: bare #deprecated ($pos) rc $rc, not refused by name"; sed 's/^/      /' "$T/e" | grep -v 'routes n=' | head -3; exit 1
    fi
  done
  # 2f — #naked: inert on cx (compiles, framed), armed elsewhere (the framed `return` is refused)
  for pos in pre post; do
    "$c" < "$T/naked_$pos.cyr" > "$T/o" 2>"$T/e"; rc=$?
    if [ "$f" = main_cx.cyr ]; then
      if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then echo "FAIL directive_fork_parity axis2f: cx armed #naked ($pos) — a naked body falls through into the next fn on a bytecode VM"; sed 's/^/      /' "$T/e" | head -3; exit 1; fi
    else
      if [ "$rc" -eq 0 ] || ! grep -q 'not allowed in a #naked fn' "$T/e"; then
        echo "FAIL directive_fork_parity axis2f: src/$f did not arm #naked ($pos first statement)"; exit 1
      fi
    fi
  done
  rows=$((rows + 1))
done
[ "$rows" -ge 12 ] || { echo "FAIL directive_fork_parity axis2c: only $rows row(s) measured, expected >= 12"; exit 1; }

echo "PASS directive_fork_parity: 7 forks + PARSE_PROG route every directive through _tl_directive · #inline non-inert on $checked forks · #deprecated/#must_use/#pure->#io/#alloc warn before AND after the first statement, control silent · #assert declaration-phase, wrapped or not · bare #deprecated refused · #naked inert on cx only (macho pair structural here, run on ecb/ach)"
exit 0
