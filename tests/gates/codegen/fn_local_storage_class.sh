#!/bin/sh
# fn_local_storage_class.sh — 6.6.5. A fn-local aggregate's STORAGE CLASS, and the NAME it
# occupies, are the compiler's business and must not leak into the program's global namespace.
#
# ⛔ THE FILED SHAPE (docs/development/issues/2026-09-13-…-shadow-other-files.md): a struct
# literal inside a fn registered a GLOBAL slot, and FINDVAR is one flat last-match table over
# every file — so a private lib's `fn f() { var cfg = P { 1, 2 }; }` captured the CONSUMER's
# `var cfg = 5`. On 6.6.3 that was a silent 2 for 6; on 6.6.4 it became an error naming the
# CONSUMER's own variable, and ONLY for `private` files — the public case stayed silently
# wrong. The same for an array over the per-fn frame budget and for any array under
# CYRIUS_STACK_ARRAYS=0, which fall back to static storage.
#
# ⭐ WHY THIS IS A SHELL GATE AND NOT A .tcyr. Four of its axes cannot be expressed in the
# tcyr corpus: axis 1 needs TWO FILES (the collision is cross-file by construction and the
# private half needs a `private` file), axis 3 needs an ENVIRONMENT VARIABLE
# (CYRIUS_STACK_ARRAYS=0, which the tcyr runner cannot set), axis 5 needs a source with NO
# INCLUDES (name offset 0 is the FIRST LEXED WORD of the program, so any `include` takes it),
# and axes 7/8 need the cross compilers plus qemu/cxvm.
#
# ⭐ EXPECTED VALUES COME FROM A DIFFERENT COMPUTATION THAN THE THING UNDER TEST:
#   (i)   hand-derived constants written in the axis;
#   (ii)  RENAME-INVARIANCE — the same program with the colliding local renamed must give the
#         same exit code, so a build that resolves BOTH to the same wrong slot is caught;
#   (iii) a CONTROL fn written without the construct under test (no switch, no u128, no
#         intervening block).
#
# RULE OBSERVED THROUGHOUT: a compile is a failure unless its exit code is 0 AND the output
# file is NON-EMPTY, checked BEFORE anything runs. An empty file "runs" and exits 0, so
# without that guard a failed compile reads GREEN — this repo has scored that false pass.
#
# MUTATION LEDGER — nine mutants, each applied to THIS tree, rebuilt to the fixpoint and
# measured; every one reddens a DIFFERENT axis, and no axis is redundant:
#   1. `_local_struct_is_ptr` back to the -1-predecessor guess
#        -> axis 7 aarch64 exit=1 AND cx exit=1 (bit 1 = the dead-scope leg).
#           tests/tcyr/crossos/aggregate_storage_class.tcyr: dead_scope reads a frame word
#           (6295057) for 22, callptr 4251443 for 22, the stiva shape ACCEPTS the undersized
#           node (1 for 0), and the unreached defer runs.
#   2. route `var p = T{..}` back through PARSE_STRUCT_INIT (the global slot)
#        -> axis 1 public exit=2 (want 6); axis 1 private FAILS TO COMPILE
#           ("'cfg' is private to its file" — the v6.6.4 misattribution, naming the
#           consumer's own variable). The rename-invariant row stays 6, which is exactly
#           why it is there: the shape is a COLLISION, not a broken struct.
#   3. drop `_fs_push` (fn-static name scoping)
#        -> axis 2 public 7 (want 3), axis 2 private compile failure, axis 3 7 (want 3),
#           axis 4 7 (want 5), axis 6 leaked buffer 77 (want 0).
#   4. hidden temporaries back on GVCNT with name 0 (and FINDVAR not skipping dead slots)
#        -> axis 5 the two `&setup` values DIFFER (exit 1).
#   5. keep the slice/u128 high-half frame slot named 0 instead of -1
#        -> axis 5b `return setup;` inside a u128-declaring fn COMPILES (rc 0) while the
#           control without the u128 is correctly refused (rc 1).
#   6. decide `secret` by the stack-arrays FLAG instead of the slot delta
#        -> axis 6 both rows fail to compile ("secret requires array declaration").
#   7. cx `EVLOAD_W` / `EFLLOAD_W` / `EFIELD_LOAD_W` back to 64-bit stubs
#        -> axis 8 x86=25 cx=30.
#   8. `WARN_AT` back to `WARN` at the over-budget array
#        -> axis 2's warning row FAILs with line=4 (want 3). Added in review round 2, which
#           found the warning naming the statement AFTER the declaration while this release's
#           sibling-repo note promises downstreams a file:line.
#   9. drop the `_CL_CAP_OPTYPE` call from the closure-capture rung (parse_expr.cyr)
#        -> axis 10 rows 1 and 3 give 2 and 32, and the no-`T_op` row COMPILES (rc 0) — the
#           silent capability loss, since 6.6.4 refuses that program. Added in review round 2.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL fn_local_storage_class: no build/cycc"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: fn_local_storage_class: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$D"' EXIT

pass=0; fail=0
note() { printf '  %s\n' "$1"; }

# build <label> <srcfile> <outfile> [env assignments...] — refuses an empty artifact.
build() {
    _lbl="$1"; _src="$2"; _out="$3"; shift 3
    if [ $# -gt 0 ]; then env "$@" "$CC" < "$_src" > "$_out" 2> "$_out.err"; else "$CC" < "$_src" > "$_out" 2> "$_out.err"; fi
    _rc=$?
    if [ "$_rc" -ne 0 ]; then echo "__CFAIL__$_rc"; return 0; fi
    if [ ! -s "$_out" ]; then echo "__CEMPTY__"; return 0; fi
    chmod +x "$_out"
    echo "__OK__"
}
# run_case <label> <srcfile> <want> [env...]
# ⚠ NEVER call this inside `( ... )`. A subshell gets its own copy of `pass`/`fail`, so the
# rows would print but not COUNT, and the floor below would then fail for the wrong reason.
# Multi-file axes pass their directory through $RUNDIR instead.
RUNDIR=""
run_case() {
    _lbl="$1"; _src="$2"; _want="$3"; shift 3
    _o="$D/a.$$"
    _here=$(pwd)
    # ⚠ A `cd` that fails must COUNT AS A FAILURE, not vanish. `|| return 0` here silently
    # dropped the row and the row-count check below then had one fewer row to find — a gate
    # losing a row without saying so is the shape this whole file exists to prevent.
    if [ -n "$RUNDIR" ]; then
        if ! cd "$RUNDIR"; then printf '  FAIL: %-52s cannot cd %s\n' "$_lbl" "$RUNDIR"; fail=$((fail+1)); return 0; fi
    fi
    _st=$(build "$_lbl" "$_src" "$_o" "$@")
    if ! cd "$_here"; then printf '  FAIL: %-52s cannot return to %s\n' "$_lbl" "$_here"; fail=$((fail+1)); return 0; fi
    case "$_st" in
      __CFAIL__*) printf '  FAIL: %-52s compile %s\n' "$_lbl" "${_st#__CFAIL__}"; sed -n 1,2p "$_o.err"; fail=$((fail+1)); return 0 ;;
      __CEMPTY__) printf '  FAIL: %-52s empty binary\n' "$_lbl"; fail=$((fail+1)); return 0 ;;
    esac
    timeout 60 "$_o" >/dev/null 2>&1; _got=$?
    rm -f "$_o" "$_o.err"
    if [ "$_got" = "$_want" ]; then printf '  ok:   %-52s exit=%s\n' "$_lbl" "$_got"; pass=$((pass+1));
    else printf '  FAIL: %-52s exit=%s (want %s)\n' "$_lbl" "$_got" "$_want"; fail=$((fail+1)); fi
}

# ── axis 1 — the FILED two-file shape, public and private, plus rename-invariance ─────────
mkdir -p "$D/a1/lib"
cat > "$D/a1/lib/a.cyr" <<'EOF'
struct P { x; y; }
fn f() { var cfg = P { 1, 2 }; return cfg.x; }
fn api() { return f(); }
EOF
cat > "$D/a1/main.cyr" <<'EOF'
include "lib/a.cyr"
var cfg = 5;
fn main() { return api() + cfg; }
var r = main();
syscall(60, r);
EOF
# the private variant: same program, the lib file opts into private-by-default.
mkdir -p "$D/a1p/lib"
{ echo "private"; cat "$D/a1/lib/a.cyr"; } > "$D/a1p/lib/a.cyr"
sed 's/^fn api/public fn api/' "$D/a1p/lib/a.cyr" > "$D/a1p/lib/a.tmp" && mv "$D/a1p/lib/a.tmp" "$D/a1p/lib/a.cyr"
cp "$D/a1/main.cyr" "$D/a1p/main.cyr"
# rename-invariance: the SAME program with the lib's local renamed must give the same answer.
mkdir -p "$D/a1r/lib"
sed 's/\bcfg\b/lcl/g' "$D/a1/lib/a.cyr" > "$D/a1r/lib/a.cyr"
cp "$D/a1/main.cyr" "$D/a1r/main.cyr"

echo "axis 1 — a fn-local struct literal does not capture another file's global:"
RUNDIR="$D/a1";  run_case "public lib: api() + cfg == 6"           main.cyr 6
RUNDIR="$D/a1p"; run_case "private lib: api() + cfg == 6"          main.cyr 6
RUNDIR="$D/a1r"; run_case "rename-invariance: renamed local == 6"  main.cyr 6
RUNDIR=""

# ── axis 2 — the array FALLBACK shape (over the per-fn frame budget) ──────────────────────
mkdir -p "$D/a2/lib"
cat > "$D/a2/lib/a.cyr" <<'EOF'
fn f() { var big[200000]; store64(&big, 7); return load64(&big); }
fn api() { return f(); }
EOF
cat > "$D/a2/main.cyr" <<'EOF'
include "lib/a.cyr"
var big = 3;
fn main() { api(); return big; }
var r = main();
syscall(60, r);
EOF
mkdir -p "$D/a2p/lib"
{ echo "private"; sed 's/^fn api/public fn api/' "$D/a2/lib/a.cyr"; } > "$D/a2p/lib/a.cyr"
cp "$D/a2/main.cyr" "$D/a2p/main.cyr"
echo "axis 2 — an over-budget array local keeps STATIC storage but a SCOPED name:"
RUNDIR="$D/a2";  run_case "public lib: the consumer's own big == 3"  main.cyr 3
RUNDIR="$D/a2p"; run_case "private lib: the consumer's own big == 3" main.cyr 3
RUNDIR=""
# ⛔ The warning must name the DECLARATION. Review round 2: with `var bigbuf[200000];` on line
# 3, the compiler printed `warning:<source>:4:5:` with the excerpt and caret on the NEXT
# statement, because `WARN` reads the cursor and the `]` and `;` are consumed by then — while
# this release's sibling-repo note promises downstreams a file:line they can grep. The
# expected line is COMPUTED FROM THE PROBE FILE, never written here.
cat > "$D/a2w.cyr" <<'EOF'
fn f(): i64 {
    var z = 1;
    var bigbuf[200000];
    store64(&bigbuf, 7);
    return load64(&bigbuf) + z;
}
var r = f();
syscall(60, r);
EOF
"$CC" < "$D/a2w.cyr" > "$D/a2w.x" 2> "$D/a2w.err"; a2wrc=$?
a2wline=$(grep -m1 'per-fn frame budget' "$D/a2w.err" | sed -n 's/^warning:<source>:\([0-9][0-9]*\):.*/\1/p')
a2wwant=$(grep -n 'var bigbuf\[200000\];' "$D/a2w.cyr" | cut -d: -f1)
if [ "$a2wrc" -eq 0 ] && [ -n "$a2wline" ] && [ "$a2wline" = "$a2wwant" ]; then
    printf '  ok:   %-52s line=%s\n' "over-budget warning names its declaration" "$a2wline"; pass=$((pass+1))
else
    printf '  FAIL: %-52s rc=%s line=%s (want %s)\n' "over-budget warning must name its declaration" "$a2wrc" "${a2wline:-absent}" "$a2wwant"
    sed -n 1,3p "$D/a2w.err"; fail=$((fail+1))
fi

# ── axis 3 — CYRIUS_STACK_ARRAYS=0 (the opt-out path takes the same fallback) ─────────────
cat > "$D/a3.cyr" <<'EOF'
fn f() { var buf[16]; store64(&buf, 7); return load64(&buf); }
var buf = 3;
fn main() { f(); return buf; }
var r = main();
syscall(60, r);
EOF
echo "axis 3 — the same with array locals opted out entirely:"
run_case "CYRIUS_STACK_ARRAYS=0: consumer's own \`buf\` == 3" "$D/a3.cyr" 3 CYRIUS_STACK_ARRAYS=0
run_case "default (stack arrays on): == 3"                    "$D/a3.cyr" 3

# ── axis 4 — an outer LOCAL of the same name is not clobbered by a static array ───────────
cat > "$D/a4.cyr" <<'EOF'
fn f() { var big = 5; if (big == 5) { var big[200000]; store64(&big, 7); } return big; }
var r = f();
syscall(60, r);
EOF
echo "axis 4 — the static array hides, and restores, an enclosing local of its name:"
run_case "outer scalar survives: == 5" "$D/a4.cyr" 5

# ── axis 5 — NAME OFFSET 0 is the first lexed word, not a variable ────────────────────────
# ⚠ NO INCLUDES, deliberately: an `include` would take name offset 0 for itself and the axis
# would test nothing. The two `&setup` readers are DISTINCT fns declared on either side of a
# fn containing a `switch` — one fn called twice resolves the name once and passes anyway.
cat > "$D/a5.cyr" <<'EOF'
setup();
fn setup() { return 42; }
fn before() { var p = &setup; return p; }
fn between(x) { switch (x) { case 1: return 10; default: return 20; } return 0; }
fn after() { var p = &setup; return p; }
var a = before();
var b = after();
var c = between(1);
if (a == b) { syscall(60, 0); }
syscall(60, 1);
EOF
# CONTROL: the identical program with an if/else where the switch was.
sed 's/switch (x) { case 1: return 10; default: return 20; }/if (x == 1) { return 10; } return 20;/' "$D/a5.cyr" > "$D/a5c.cyr"
# the u128 variant of the same class (the slice/u128 high-half slot was named 0 too)
sed 's/fn between(x) { switch (x) { case 1: return 10; default: return 20; } return 0; }/fn between(x) { var u: u128 = 0; return x; }/' "$D/a5.cyr" > "$D/a5u.cyr"
echo "axis 5 — an intervening switch / u128 does not rebind the first lexed word:"
run_case "&setup is stable across a fn containing a switch" "$D/a5.cyr"  0
run_case "control: the same program with an if/else"        "$D/a5c.cyr" 0
run_case "&setup is stable across a fn declaring a u128"    "$D/a5u.cyr" 0

# axis 5b — the frame slots named 0 must not RESOLVE either. `return setup;` (a bare fn name
# as a value) is a resolution error; a u128 in the same fn used to make it succeed silently.
cat > "$D/a5b.cyr" <<'EOF'
setup();
fn setup() { return 42; }
fn h() { var u: u128 = 0; return setup; }
var b = h();
syscall(60, b);
EOF
sed 's/var u: u128 = 0; return setup;/return setup;/' "$D/a5b.cyr" > "$D/a5bc.cyr"
"$CC" < "$D/a5b.cyr"  > "$D/a5b.out"  2>/dev/null; sub_rc=$?
"$CC" < "$D/a5bc.cyr" > "$D/a5bc.out" 2>/dev/null; ctl_rc=$?
if [ "$sub_rc" -eq "$ctl_rc" ] && [ "$ctl_rc" -ne 0 ]; then
    printf '  ok:   %-52s both refused (rc=%s)\n' "\`return setup;\` refused with and without a u128" "$ctl_rc"; pass=$((pass+1))
else
    printf '  FAIL: %-52s subject rc=%s control rc=%s\n' "\`return setup;\` with a u128" "$sub_rc" "$ctl_rc"; fail=$((fail+1))
fi

# ── axis 6 — `secret var buf[N]` over the budget still zeroises ───────────────────────────
cat > "$D/a6.cyr" <<'EOF'
fn f() { secret var big[200000]; store64(&big, 7); return load64(&big); }
var r = f();
syscall(60, r);
EOF
cat > "$D/a6z.cyr" <<'EOF'
var leak = 0;
fn f() {
    var big = 1;
    if (big == 1) {
        secret var big[200000];
        store64(&big, 77);
        leak = &big;
    }
    return 0;
}
var r = f();
syscall(60, load64(leak));
EOF
echo "axis 6 — secret over the frame budget compiles AND clears its buffer:"
run_case "secret var big[200000]: readable inside the fn == 7" "$D/a6.cyr"  7
run_case "the static buffer reads 0 after return"              "$D/a6z.cyr" 0

# ── axis 7 — the recorded-layout legs on aarch64 (qemu) and cx (cxvm) ─────────────────────
# ⚠ EMULATORS, NOT HARDWARE. The hardware legs are the crossos .tcyr files, which the release
# gate runs on ecb/ach/cass/pi. These exist because the cx backend has no host at all and the
# aarch64 leg catches an emitter divergence before the cross-host run costs a slot.
cat > "$D/a7.cyr" <<'EOF'
struct P { x; y; }
struct B1 { val; }
var heap[64];
fn mk() { store64(&heap, 11); store64(&heap + 8, 22); return &heap; }
fn dead_scope() { if (1 == 1) { var t = 5; t = t + 1; } var p: P = mk(); return p.y; }
fn two_b1() { var b: B1; b.val = 42; var c: B1; c.val = 1; return b.val + c.val; }
fn rec(n) { var p = P { n, n * 2 }; if (n > 0) { rec(n - 1); } return p.x + p.y; }
var r = 0;
if (dead_scope() != 22) { r = 1; }
if (two_b1() != 43) { r = r + 2; }
if (rec(3) != 9) { r = r + 4; }
syscall(60, r);
EOF
echo "axis 7 — the same recorded-layout legs on the aarch64 and cx emitters:"
# ⚠ THE x86 ROW IS FREE AND IT WAS MISSING. This axis used to run a7.cyr only under qemu and
# cxvm, so the host backend — the one every other axis compiles with — never answered these
# three legs at all. Both of this file's layout mutants (the -1-predecessor guess, and the
# literal back through PARSE_STRUCT_INIT) redden it on x86 alone. Added in the 6.6.5 review.
run_case "x86: dead_scope 22 + two_b1 43 + rec 9" "$D/a7.cyr" 0
a64_skipped=0
if command -v qemu-aarch64 >/dev/null 2>&1; then
    "$CC" < "$ROOT/src/main_aarch64.cyr" > "$D/cc_a64" 2>/dev/null
    if [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"
        "$D/cc_a64" < "$D/a7.cyr" > "$D/a7.a64" 2>/dev/null
        if [ -s "$D/a7.a64" ]; then
            chmod +x "$D/a7.a64"; timeout 60 qemu-aarch64 "$D/a7.a64" >/dev/null 2>&1; g=$?
            if [ "$g" -eq 0 ]; then printf '  ok:   %-52s exit=0\n' "aarch64 (qemu-user, NOT hardware)"; pass=$((pass+1));
            else printf '  FAIL: %-52s exit=%s (1=dead_scope 2=two_b1 4=rec)\n' "aarch64 (qemu-user)" "$g"; fail=$((fail+1)); fi
        else printf '  FAIL: %-52s empty aarch64 binary\n' "aarch64 leg"; fail=$((fail+1)); fi
    else printf '  FAIL: %-52s aarch64 cross compiler did not build\n' "aarch64 leg"; fail=$((fail+1)); fi
else
    note "SKIP: qemu-aarch64 not installed (aarch64 leg)"
    a64_skipped=1
fi
"$CC" < "$ROOT/src/main_cx.cyr" > "$D/cc_cx" 2>/dev/null
"$CC" < "$ROOT/programs/cxvm.cyr" > "$D/cxvm" 2>/dev/null
if [ -s "$D/cc_cx" ] && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"
    "$D/cc_cx" < "$D/a7.cyr" > "$D/a7.cyx" 2>/dev/null
    if [ -s "$D/a7.cyx" ]; then
        timeout 60 "$D/cxvm" < "$D/a7.cyx" >/dev/null 2>&1; g=$?
        if [ "$g" -eq 0 ]; then printf '  ok:   %-52s exit=0\n' "cx (cxvm, the backend with no host)"; pass=$((pass+1));
        else printf '  FAIL: %-52s exit=%s (1=dead_scope 2=two_b1 4=rec)\n' "cx (cxvm)" "$g"; fail=$((fail+1)); fi
    else printf '  FAIL: %-52s empty .cyx\n' "cx leg"; fail=$((fail+1)); fi
else
    printf '  FAIL: %-52s cx toolchain did not build\n' "cx leg"; fail=$((fail+1))
fi

# ── axis 8 — cx narrow / SIGNED loads agree with x86 ──────────────────────────────────────
# EFIELD_LOAD_W ignored signed widths and EVLOAD_W / EFLLOAD_W were 64-bit stubs, so a signed
# i8/i16/i32 field or local compared EXACTLY against a negative literal passed on x86 and
# aarch64 and failed on cx. The expected value is the X86 RESULT for the same source, not a
# constant written here.
cat > "$D/a8.cyr" <<'EOF'
struct N8 { a: i8; b: i32; c; }
var Gn = N8 { 0 - 1, 0 - 2, 7 };
fn field_signed() { var n = N8 { 0 - 1, 0 - 2, 7 }; return n.a * 1000 + n.b * 10 + n.c; }
fn typed_signed() { var n: N8; n.a = 0 - 1; n.b = 0 - 2; n.c = 7; return n.a + n.b + n.c; }
fn global_signed() { return Gn.a + Gn.b + Gn.c; }
fn local_signed() { var x: i32 = 0 - 5; var y: i8 = 0 - 3; return x * 10 + y; }
var r = field_signed() + typed_signed() * 7 + global_signed() * 13 + local_signed() * 17;
syscall(60, (r + 100000) % 251);
EOF
if [ -s "$D/cc_cx" ]; then
    "$CC" < "$D/a8.cyr" > "$D/a8.x86" 2>/dev/null
    "$D/cc_cx" < "$D/a8.cyr" > "$D/a8.cyx" 2>/dev/null
    if [ -s "$D/a8.x86" ] && [ -s "$D/a8.cyx" ]; then
        chmod +x "$D/a8.x86"; timeout 60 "$D/a8.x86" >/dev/null 2>&1; x86=$?
        timeout 60 "$D/cxvm" < "$D/a8.cyx" >/dev/null 2>&1; cxr=$?
        if [ "$x86" -eq "$cxr" ]; then printf '  ok:   %-52s x86=%s cx=%s\n' "signed narrow loads agree across backends" "$x86" "$cxr"; pass=$((pass+1));
        else printf '  FAIL: %-52s x86=%s cx=%s\n' "signed narrow loads DISAGREE" "$x86" "$cxr"; fail=$((fail+1)); fi
    else printf '  FAIL: %-52s a compile produced no binary\n' "axis 8"; fail=$((fail+1)); fi
else
    # Not a silent skip: axis 7 already FAILed for the missing cx toolchain, and this axis
    # dropping its row on the same condition is how a gate quietly shrinks.
    printf '  FAIL: %-52s cx compiler unavailable\n' "axis 8"; fail=$((fail+1))
fi

# ── axis 9 — the fn-static name table's CAP is a diagnostic, not a silent fall-open ───────
# ⛔ `_fs_push` opened `if (_fs_n >= 64) { return 0; }`, so the 65th fn-local static in one
# body got NEITHER the new scoping NOR the v6.6.4 `_GVAR_VIS` stamp the else-arm applies: it
# silently reverted to the 6.6.3 shape this release removes. Measured then: N=64 answered 3
# (right), N=65 answered 64 (the static shadowing the consumer's global). The cap is now 256
# and hitting it stops the compile.
# ⭐ N IS DERIVED FROM THE DECLARATION, never written here — `var _fs_vi[N];` in parse.cyr is
# the table, so the gate cannot drift away from the code it guards. CYRIUS_STACK_ARRAYS=0
# makes EVERY array local static, which is what makes the cap reachable in a small program.
FSCAP=$(sed -n 's/^var _fs_vi\[\([0-9][0-9]*\)\];.*/\1/p' "$ROOT/src/frontend/parse.cyr" | head -1)
echo "axis 9 — $FSCAP fn-local statics scope correctly; $((FSCAP + 1)) is refused, not ignored:"
if [ -z "$FSCAP" ]; then
    printf '  FAIL: %-52s could not derive the cap from parse.cyr\n' "axis 9"; fail=$((fail+1))
    printf '  FAIL: %-52s (skipped, cap unknown)\n' "axis 9 overflow"; fail=$((fail+1))
else
    gen_statics() {   # $1 = count, $2 = outfile
        { echo "var probe = 3;"
          printf 'fn f() {\n'
          _i=0; while [ "$_i" -lt "$1" ]; do echo "  var probe$_i[16]; store64(&probe$_i, 7);"; _i=$((_i+1)); done
          printf '  return load64(&probe0);\n}\n'
          echo "fn main() { f(); return probe; }"
          echo "var r = main();"
          echo "syscall(60, r);"
        } > "$2"
    }
    # The LAST static is named `probe<N-1>`; rename the enclosing consumer global to `probe`
    # and have one static shadow it, so a lost scoping answers 7 instead of 3.
    gen_statics "$FSCAP" "$D/a9.cyr"
    sed -i "s/var probe$((FSCAP - 1))\[16\]/var probe[16]/; s/store64(\&probe$((FSCAP - 1)),/store64(\&probe,/" "$D/a9.cyr"
    run_case "$FSCAP statics: the consumer's own probe == 3" "$D/a9.cyr" 3 CYRIUS_STACK_ARRAYS=0
    gen_statics "$((FSCAP + 1))" "$D/a9o.cyr"
    sed -i "s/var probe$FSCAP\[16\]/var probe[16]/; s/store64(\&probe$FSCAP,/store64(\&probe,/" "$D/a9o.cyr"
    env CYRIUS_STACK_ARRAYS=0 "$CC" < "$D/a9o.cyr" > "$D/a9o.x" 2> "$D/a9o.err"; ovrc=$?
    if [ "$ovrc" -ne 0 ] && grep -q "too many static array locals in one fn" "$D/a9o.err"; then
        printf '  ok:   %-52s refused (rc=%s)\n' "$((FSCAP + 1)) statics names the cap" "$ovrc"; pass=$((pass+1))
    else
        printf '  FAIL: %-52s rc=%s, diagnostic missing\n' "$((FSCAP + 1)) statics must be refused" "$ovrc"
        sed -n 1,2p "$D/a9o.err"; fail=$((fail+1))
    fi
fi

# ── axis 10 — a CAPTURED inline aggregate dispatches its operator overload ────────────────
# ⛔ Review round 2. Making `var a = Num{1}` a frame local (axis 1) moved it off the global
# rung and onto the CLOSURE-CAPTURE rung, which never set the expression's struct type — so
# `|x| a + x` compiled to an INTEGER ADD of the captured word and answered 2 where 102 is
# right, where 6.6.4 (with `a` a global) dispatched `Num_add`. The decisive row is the LAST
# one: with `Num_add` deleted, 6.6.4 REFUSES the program and the un-repaired 6.6.5 compiles it
# clean — a silent capability loss, not just a wrong number.
# ⭐ The two value rows are computed from the operands, not from a constant: row 1's operator
# fn returns `100 + a + b` over a single-word (by-VALUE) capture, row 2's reads BOTH multi-word
# captures through their addresses, so a shared or mis-based env offset shows as a wrong sum.
# ⭐ The GLOBAL control is the same source with the struct hoisted to top level — the rung that
# always worked — so a build that stops dispatching everywhere is not mistaken for this fix.
cat > "$D/a10.cyr" <<'EOF'
include "lib/alloc.cyr"
struct Num { v; }
fn Num_add(a, b) { return 100 + a + b; }
fn apply(f, x) { return callptr(f, x); }
fn main(): i64 {
    alloc_init();
    var a = Num { 1 };
    var c = |x| a + x;
    syscall(60, apply(c, 1));
    return 0;
}
var e = main();
EOF
# the GLOBAL control: identical program, the struct declared at top level.
cat > "$D/a10g.cyr" <<'EOF'
include "lib/alloc.cyr"
struct Num { v; }
fn Num_add(a, b) { return 100 + a + b; }
fn apply(f, x) { return callptr(f, x); }
var a = Num { 1 };
fn main(): i64 {
    alloc_init();
    var c = |x| a + x;
    syscall(60, apply(c, 1));
    return 0;
}
var e = main();
EOF
cat > "$D/a10m.cyr" <<'EOF'
include "lib/alloc.cyr"
struct V2 { x; y; }
fn V2_add(a, b) { return load64(a) * 10 + load64(a + 8) + load64(b) * 100 + load64(b + 8) * 1000; }
fn apply0(f) { return callptr(f); }
fn main(): i64 {
    alloc_init();
    var p = V2 { 1, 2 };
    var q = V2 { 3, 4 };
    var c = || p + q;
    syscall(60, apply0(c) & 0xFF);
    return 0;
}
var e = main();
EOF
echo "axis 10 — an inline aggregate captured by a closure still dispatches T_op:"
run_case "captured 8 B struct + int == 102"          "$D/a10.cyr"  102
run_case "control: the same, struct global == 102"   "$D/a10g.cyr" 102
run_case "two captured 16 B structs == 4312 & 0xFF"  "$D/a10m.cyr" 216
# no T_op: the same diagnostic the non-closure form gives, not a silent integer add.
sed '/^fn Num_add/d' "$D/a10.cyr" > "$D/a10n.cyr"
"$CC" < "$D/a10n.cyr" > "$D/a10n.x" 2> "$D/a10n.err"; a10rc=$?
if [ "$a10rc" -ne 0 ] && grep -q 'reachable undefined function' "$D/a10n.err"; then
    printf '  ok:   %-52s refused (rc=%s)\n' "captured struct with no Num_add" "$a10rc"; pass=$((pass+1))
else
    printf '  FAIL: %-52s rc=%s — a missing T_op compiled as an integer add\n' "captured struct with no Num_add must be refused" "$a10rc"
    sed -n 1,2p "$D/a10n.err"; fail=$((fail+1))
fi

# ── row count: DERIVED TWICE, and the two derivations must agree ──────────────────────────
# ⛔ This used to be `[ "$total" -lt 14 ]` against SEVENTEEN rows — a floor three rows below
# the truth, so three could disappear and the gate still read GREEN. (Its neighbour
# call_site_stack_alignment.sh, registered a dozen lines away in check.sh, already makes two
# independent counts agree; this one did not.) The expected count now comes from the SCRIPT'S
# OWN TEXT — a static grep of the `run_case` call sites plus the SEVEN rows that are not
# run_case (axis 2's warning-position row, axis 5b's refusal pair, the aarch64 leg, the cx
# leg, axis 8, axis 9's overflow refusal, axis 10's no-`T_op` refusal) — which is a
# different computation from the counter the rows increment. The ONLY legitimate subtraction
# is a genuinely absent qemu-aarch64. CHANGELOG [6.6.5]
total=$((pass + fail))
want_rows=$(grep -cE '^[[:space:]]*(RUNDIR="[^"]*";[[:space:]]*)?run_case ' "$0")
want_rows=$((want_rows + 7))
if [ "$a64_skipped" -eq 1 ]; then want_rows=$((want_rows - 1)); fi
if [ "$total" -ne "$want_rows" ]; then
    echo "FAIL fn_local_storage_class: $total rows ran, $want_rows expected — a row was lost (or added without updating the derivation)"
    exit 1
fi
if [ "$fail" -ne 0 ]; then
    echo "FAIL fn_local_storage_class: $fail of $total rows failed"
    exit 1
fi
echo "PASS fn_local_storage_class: $pass of $want_rows rows — a fn-local struct literal and an over-budget / opted-out array local are scoped to their fn (two files, private and public, rename-invariant), the first lexed word is not a hidden temporary, secret over the budget still zeroises, and the recorded-layout legs agree on aarch64 (qemu) and cx (cxvm)"
