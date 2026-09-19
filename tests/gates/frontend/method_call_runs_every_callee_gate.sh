#!/bin/sh
# tests/gates/frontend/method_call_runs_every_callee_gate.sh — 6.6.5
#
# ⛔ THE DEFECT CLASS. `s.m(x)` and `M_m(&s, x)` are ONE call syntax with TWO marshalling
# paths in the compiler, and the method one (parse_decl.cyr's own argument loop) ran NONE of
# PARSE_FNCALL's callee gates. Four separate silent failures lived in that one loop, and they
# were found one at a time, each review round turning up the next:
#
#   _fnt_structmask  a >8 B struct param pushed BY VALUE into a callee that derefs it   SIGSEGV
#   _fnt_strmask     a `"lit"` into a `: Str` param, never wrapped in str_from()        0 for 5
#   _fnt_simdmask    a vector pushed as an int arg, shifting every LATER argument       920 for 923
#   _fnt_cstrmask    an integer literal into a `: cstring` param — v6.5.3's HARD ERROR  SIGSEGV
#   (+ no _CHECK_ARITY at all: `q.one(5,99)` built and returned 6; `q.one()` built and
#    returned whatever was in the register nothing set)
#
# ⭐ WHY THIS GATE IS A DIFFERENTIAL AND NOT A LIST. The lesson of the four is not any one
# mask; it is that a list in a gate would have been written from the bug report in hand and
# would have grown one row per round, exactly like the fix did. So every row here compiles
# the method call AND an identical FREE FUNCTION with the same body and the same parameter
# annotations, and requires the two to AGREE — on the value, on the exit status, and on
# whether a diagnostic was emitted. The free-fn arm has always gone through PARSE_FNCALL, so
# the expected value is produced by a DIFFERENT code path in the compiler rather than by this
# file. A fifth mask added to PARSE_FNCALL and forgotten here fails without an edit.
#
# ⚠ ANTI-VACUOUS FLOOR. A differential alone passes when BOTH arms are broken the same way,
# so each value row also asserts a number the shell computed independently (a string length
# from `wc -c`, an arithmetic expression over the literals) and each diagnostic row asserts
# that the free-fn arm really did refuse — an "equal" pair of empty outputs is a failure.
#
# MUTATION LEDGER — every mutant BUILT as a full cycc from mutated source and RUN:
#   N1 drop `_check_int_lit_cstring_arg` from the method loop (parse_decl.cyr)
#        -> row cstr_lit red: the method arm emits a binary where the identical free arm is
#           refused (that binary then SIGSEGVs, rc 139 — measured directly). 6.6.4's behaviour.
#   N2 drop `_CHECK_ARITY` from the method loop
#        -> rows arity_over, arity_under and no_self red: all three build and run (exit 6 /
#           exit 1 / exit 7) where the identical free arm is refused. Also 6.6.4's behaviour.
#           ctor_mangled stays GREEN under it, which is the pair showing the escalation is
#           scoped to the DOT form and leaves the `Type_new(a, b)` constructor idiom alone.
#   N3 drop `_try_push_str_literal_arg` from the method loop
#        -> row str_lit red: method 0, free 5. (Round-1 mutant M13, re-proven here.)
#   N4 never take the SIMD arm (`m_cls > 0` -> `m_cls > 99`) in the method loop
#        -> row simd_mix red: method printed 920, free fn 923 — the vector went in as an int
#           arg, so `j` received the vector's low half and every later arg shifted a register.
#   N5 make `_check_int_lit_cstring_arg` fire on literal 0 as well (drop the NULL exemption)
#        -> row cstr_null red: BOTH arms refuse a legitimate `f(0)`, so the differential
#           still "agrees" — the floor (the control must BUILD) is what catches it.
#   (6.6.6, bite 14 review — the structural row after the gates moved into `_call_arg_one`)
#   N6 drop `_simd_arg_record(` from `_call_arg_one`       -> [helpers] red (and row simd_mix)
#   N7 the method loop calls a bare PCMPE+EPUSHR instead of `_call_arg_one`
#                                                          -> [helpers] red
#   14a as committed (4a351a9a..76a5a614), old structural row -> [helpers] red on a correct tree —
#        the false RED this edit removes
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
fail=0

PRE='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/simd.cyr"
struct MG { a: i64; }
'

# build <name> <source-body>; sets $rc (run status), $out (stdout), $refused (1 = no binary)
build_run() {
    _n=$1; _src=$2
    printf '%s%s' "$PRE" "$_src" > "$T/$_n.cyr"
    "$CC" < "$T/$_n.cyr" > "$T/$_n.bin" 2> "$T/$_n.err" || true
    if [ -s "$T/$_n.bin" ]; then
        refused=0
        chmod +x "$T/$_n.bin"
        out=$("$T/$_n.bin" 2>/dev/null)
        rc=$?
    else
        refused=1; out=""; rc=-1
    fi
}

# A VALUE row: the method arm and the free arm must print the same thing, and that thing must
# equal a value the shell worked out for itself.
vrow() {
    _row=$1; _mbody=$2; _fbody=$3; _want=$4
    build_run "m_$_row" "$_mbody"; _mref=$refused; _mout=$out; _mrc=$rc
    build_run "f_$_row" "$_fbody"; _fref=$refused; _fout=$out; _frc=$rc
    if [ "$_mref" != 0 ] || [ "$_fref" != 0 ]; then
        echo "  FAIL: method_call_gates [$_row]: a control program did not build (method refused=$_mref free refused=$_fref)"
        head -3 "$T/m_$_row.err" "$T/f_$_row.err" | sed 's/^/      /'; fail=1; return
    fi
    if [ "$_fout" != "$_want" ]; then
        echo "  FAIL: method_call_gates [$_row]: the FREE-FN arm printed '$_fout', but the shell computed '$_want' — the floor is gone, so the differential means nothing"; fail=1; return
    fi
    if [ "$_mout" != "$_fout" ] || [ "$_mrc" != "$_frc" ]; then
        echo "  FAIL: method_call_gates [$_row]: method printed '$_mout' rc=$_mrc, identical free fn printed '$_fout' rc=$_frc"; fail=1
    fi
}

# A DIAGNOSTIC row: both arms must be REFUSED, and the free arm must really carry the message
# (so "both produced nothing" cannot pass).
drow() {
    _row=$1; _mbody=$2; _fbody=$3; _msg=$4
    build_run "m_$_row" "$_mbody"; _mref=$refused
    build_run "f_$_row" "$_fbody"; _fref=$refused
    if ! grep -q "$_msg" "$T/f_$_row.err"; then
        echo "  FAIL: method_call_gates [$_row]: the FREE-FN arm did not emit \"$_msg\" — the floor is gone"
        head -3 "$T/f_$_row.err" | sed 's/^/      /'; fail=1; return
    fi
    if [ "$_fref" != 1 ]; then echo "  FAIL: method_call_gates [$_row]: the free-fn arm emitted a binary despite the error"; fail=1; fi
    if [ "$_mref" != 1 ]; then
        echo "  FAIL: method_call_gates [$_row]: the METHOD arm compiled and emitted a binary where the identical free fn is refused"
        fail=1; return
    fi
    if ! grep -q "$_msg" "$T/m_$_row.err"; then
        echo "  FAIL: method_call_gates [$_row]: the method arm refused, but not with \"$_msg\""
        head -3 "$T/m_$_row.err" | sed 's/^/      /'; fail=1
    fi
}

# ── row str_lit — _fnt_strmask. Expected length computed by wc, not typed in. ────────────
LIT=abcde
WANT_LEN=$(printf %s "$LIT" | wc -c | tr -d ' ')
vrow str_lit \
"impl MT for MG { fn slen(self, s: Str): i64 { return str_len(s); } }
fn main(): i64 { alloc_init(); var g: MG; g.a = 0; print_num(g.slen(\"$LIT\")); return 0; }
var e = main(); syscall(60, e);" \
"fn free_slen(self, s: Str): i64 { return str_len(s); }
fn main(): i64 { alloc_init(); print_num(free_slen(0, \"$LIT\")); return 0; }
var e = main(); syscall(60, e);" \
"$WANT_LEN"

# ── row str_lit_tail — the same argument in TAIL position (`return f(\"lit\")`), which is a
# THIRD emit path (PARSE_RETURN's own epilogue+jmp) and was wrong there too. ──────────────
vrow str_lit_tail \
"impl MT for MG { fn slen(self, s: Str): i64 { return str_len(s); } }
fn mcall(g: MG): i64 { return g.slen(\"$LIT\"); }
fn main(): i64 { alloc_init(); var g: MG; g.a = 0; print_num(mcall(g)); return 0; }
var e = main(); syscall(60, e);" \
"fn free_slen(self, s: Str): i64 { return str_len(s); }
fn fcall(): i64 { return free_slen(0, \"$LIT\"); }
fn main(): i64 { alloc_init(); print_num(fcall()); return 0; }
var e = main(); syscall(60, e);" \
"$WANT_LEN"

# ── row simd_mix — _fnt_simdmask. A vector BETWEEN two scalars: pushed as an int arg it
# shifts every later argument by one register, so `j` silently receives the vector's low
# half. Expected value is shell arithmetic over the literals. ────────────────────────────
HI=9; K=2; J=3
WANT_MIX=$(( HI * 100 + K * 10 + J ))
vrow simd_mix \
"impl MT for MG { fn vmix(self, k, v: f64v2, j): i64 { return f64v2_hi(&v) * 100 + k * 10 + j; } }
fn main(): i64 { alloc_init(); var g: MG; g.a = 0; var v = f64v2_make(0, $HI); print_num(g.vmix($K, v, $J)); return 0; }
var e = main(); syscall(60, e);" \
"fn free_vmix(self, k, v: f64v2, j): i64 { return f64v2_hi(&v) * 100 + k * 10 + j; }
fn main(): i64 { alloc_init(); var v = f64v2_make(0, $HI); print_num(free_vmix(0, $K, v, $J)); return 0; }
var e = main(); syscall(60, e);" \
"$WANT_MIX"

# ── row struct_big — _fnt_structmask, the mask the first cut of the fix DID add. Kept so a
# later consolidation cannot drop it while the three newer rows stay green. ──────────────
SA=10; SB=20; SC=12
WANT_SUM=$(( SA + SB + SC ))
vrow struct_big \
"struct MBig { a: i64; b: i64; c: i64; }
impl MT for MG { fn take(self, b: MBig): i64 { return b.a + b.b + b.c; } }
fn main(): i64 { alloc_init(); var g: MG; g.a = 0; var b: MBig; b.a = $SA; b.b = $SB; b.c = $SC; print_num(g.take(b)); return 0; }
var e = main(); syscall(60, e);" \
"struct MBig { a: i64; b: i64; c: i64; }
fn free_take(self, b: MBig): i64 { return b.a + b.b + b.c; }
fn main(): i64 { alloc_init(); var b: MBig; b.a = $SA; b.b = $SB; b.c = $SC; print_num(free_take(0, b)); return 0; }
var e = main(); syscall(60, e);" \
"$WANT_SUM"

# ── row cstr_lit — _fnt_cstrmask. v6.5.3 made this a HARD ERROR because the alternative is a
# runtime crash; the method path SIGSEGV'd instead. ──────────────────────────────────────
drow cstr_lit \
"impl MT for MG { fn pr(self, p: cstring): i64 { return strlen(p); } }
fn main(): i64 { var g: MG; g.a = 0; return g.pr(42); }" \
"fn free_pr(self, p: cstring): i64 { return strlen(p); }
fn main(): i64 { return free_pr(0, 42); }" \
"which expects a cstring"

# ── row cstr_null — the NULL exemption. `0` is the idiomatic null cstring and must still
# BUILD on both arms; this is the anti-vacuous control for cstr_lit. ─────────────────────
vrow cstr_null \
"impl MT for MG { fn pn(self, p: cstring): i64 { if (p == 0) { return 7; } return strlen(p); } }
fn main(): i64 { alloc_init(); var g: MG; g.a = 0; print_num(g.pn(0)); return 0; }
var e = main(); syscall(60, e);" \
"fn free_pn(self, p: cstring): i64 { if (p == 0) { return 7; } return strlen(p); }
fn main(): i64 { alloc_init(); print_num(free_pn(0, 0)); return 0; }
var e = main(); syscall(60, e);" \
"7"

# ── rows arity_over / arity_under — no _CHECK_ARITY at all on the method path. Available
# only because the fix resolves the callee BEFORE the argument loop. ─────────────────────
drow arity_over \
"impl MT for MG { fn one(self, x): i64 { return x + 1; } }
fn main(): i64 { var g: MG; g.a = 0; return g.one(5, 99); }" \
"fn free_one(self, x): i64 { return x + 1; }
fn main(): i64 { return free_one(0, 5, 99); }" \
"expects 2 arguments, got 3"

drow arity_under \
"impl MT for MG { fn one(self, x): i64 { return x + 1; } }
fn main(): i64 { var g: MG; g.a = 0; return g.one(); }" \
"fn free_one(self, x): i64 { return x + 1; }
fn main(): i64 { return free_one(0); }" \
"expects 2 arguments, got 1"

# ── row no_self — the ONE shape whose acceptance changed. `obj.m()` on a method that declares
# no `self` parameter pushes `&obj` as an argument the callee never asked for; 6.6.4 built it
# and it "worked" only because the callee never read rdi. It is an arity mismatch and is now
# reported as one, in the same words the equivalent `NS_zero(&n)` has always used. Measured
# before escalating: zero instances across ~/Repos outside cyrius. ⚠ The MANGLED form of the
# same definition (`Type_new(a, b)`, the constructor idiom all 19 in-tree self-less impl fns
# use) is untouched — the positive control below it proves that half. ───────────────────────
drow no_self \
"impl MT for MG { fn zero(): i64 { return 7; } }
fn main(): i64 { var g: MG; g.a = 0; return g.zero(); }" \
"fn free_zero(): i64 { return 7; }
fn main(): i64 { var g: MG; g.a = 0; return free_zero(&g); }" \
"expects 0 arguments, got 1"

# ── row ctor_mangled — the positive control for no_self: the SAME self-less definition called
# in the mangled form must still build and return its value. Without this, "refuse every
# self-less impl fn" would pass the row above. ──────────────────────────────────────────────
vrow ctor_mangled \
"impl MT for MG { fn make(x): i64 { return x + 7; } }
fn main(): i64 { alloc_init(); print_num(MG_make(3)); return 0; }
var e = main(); syscall(60, e);" \
"fn free_make(x): i64 { return x + 7; }
fn main(): i64 { alloc_init(); print_num(free_make(3)); return 0; }
var e = main(); syscall(60, e);" \
"10"

# ── row arity_ok — the positive control: a correctly-arity'd method call must still BUILD
# and run. Without it, "refuse everything" would pass both rows above. ───────────────────
vrow arity_ok \
"impl MT for MG { fn one(self, x): i64 { return x + 1; } }
fn main(): i64 { alloc_init(); var g: MG; g.a = 0; print_num(g.one(5)); return 0; }
var e = main(); syscall(60, e);" \
"fn free_one(self, x): i64 { return x + 1; }
fn main(): i64 { alloc_init(); print_num(free_one(0, 5)); return 0; }
var e = main(); syscall(60, e);" \
"6"

# ── row derived floor — the method loop must consult as many callee tables as PARSE_FNCALL's
# loop does. DERIVED from the source, so adding a fifth gate to one and not the other is a
# FAILURE here rather than a silent divergence discovered by the next consumer. ──────────
# ⚠ 6.6.6: the four per-argument gates moved into `_call_arg_one` (parse_fn.cyr), which the method
# loop, both struct-valued `var` receives and the four PE own-calls now share. This check still
# looked for them INLINE in the method loop, so 14a turned it RED while the method path itself was
# fine (bite 14's review found it). It now follows the call: the loop must call `_call_arg_one`,
# the vector second pass and the arity check, and `_call_arg_one` must call each gate.
MASKS_FNCALL=$(grep -cE '_fnt_(str|struct|simd|cstr)mask' src/frontend/parse_fn.cyr)
MLOOP=$(sed -n '/THIS LOOP RUNS PARSE_FNCALL/,/ECALLCLEAN(S, m_int_argc)/p' src/frontend/parse_decl.cyr)
ARGONE=$(sed -n '/^fn _call_arg_one(/,/^}/p' src/frontend/parse_fn.cyr)
[ -n "$ARGONE" ] || { echo "  FAIL: method_call_gates [helpers]: fn _call_arg_one not found in parse_fn.cyr"; fail=1; }
for h in _call_arg_one _simd_arg_second_pass _CHECK_ARITY; do
    echo "$MLOOP" | grep -q "$h(" || { echo "  FAIL: method_call_gates [helpers]: the method-call argument loop no longer calls $h"; fail=1; }
done
for h in _check_int_lit_cstring_arg _try_push_str_literal_arg _try_push_struct_addr_arg _simd_arg_record; do
    echo "$ARGONE" | grep -q "$h(" || { echo "  FAIL: method_call_gates [helpers]: _call_arg_one (the method loop's per-argument body) no longer calls $h"; fail=1; }
done
[ "$MASKS_FNCALL" -ge 4 ] || { echo "  FAIL: method_call_gates [helpers]: expected PARSE_FNCALL's file to reference all four callee masks, found $MASKS_FNCALL"; fail=1; }

[ "$fail" = 0 ] && echo "  PASS: method-call args run every callee gate PARSE_FNCALL runs (str/struct/simd/cstr masks + arity), each proven against the identical free fn and a value the shell computed itself"
exit $fail
