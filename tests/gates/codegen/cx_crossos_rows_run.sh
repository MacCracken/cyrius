#!/bin/sh
# cx_crossos_rows_run.sh — 6.6.12 (B12 part 2). The V1-V4 fixes of 6.6.12 hold on the cx bytecode
# target, not only natively: every row set below runs NATIVELY (x86, the oracle) and on cxvm, and
# both must give the answer the row set states.
#
# ⛔ WHY THIS GATE EXISTS. V1 (narrow slot width), V2 (nested / generic positional struct literals),
# V3 (a struct-typed field as a by-value struct argument) and V4 (a top-level struct copy-init) ALL
# reproduced wrong on cx as well as natively. The crossos corpus runs natively on the four hosts; NO
# runner executes a crossos .tcyr on cxvm, so the cx half of those fixes would otherwise ship as a
# false green — a row in tests/tcyr/crossos/ proves nothing about cx until something runs it there.
#
# ROWS (14, all required — the count is checked, so a row that silently stops running is RED)
#   R1  B01 inline rows (V1: plain / compound for steps and compound-op loads on packed u8 / i8 /
#       u16 globals and narrow locals): exit 0 AND the `cx-rows B01 ok` marker — native, then cxvm.
#       On cx this needs B06's width-correct EVSTORE_W / EFLSTORE_W as well as B01's frontend fix.
#   R2  B02 inline rows (V2: one- and two-level nested positional literals with canaries, a whole
#       struct value for a nested field, call results, the first-field chain, generic literal
#       heads): exit 0 AND `cx-rows B02 ok` — native, then cxvm.
#   R3  B03 inline rows (V3 + V4: field arguments in a fn and at top level, through a generic,
#       copy semantics; top-level copy-init in the leading block and after a statement): exit 128
#       AND `cx-rows B03 ok` — native, then cxvm. ⚠ 128, not 0, is success here: before the cxvm host-memory bug a
#       faulting cx guest could exit 0, and "0" must never read as a pass for these rows.
#   R4  tests/tcyr/crossos/narrow_slot_width.tcyr — native and cxvm each print
#       `<N> passed, 0 failed` with N derived from the source (58 today, floor 58) and exit 0.
#   R5  tests/tcyr/crossos/generic_struct_inference.tcyr — native: every assertion (113, floor 113);
#       cxvm: every assertion outside `#ifndef CYRIUS_TARGET_CX` blocks, indented ones included
#       (70, floor 70) — the B02 LIT group and B04's CF group run there.
#   R6  tests/tcyr/crossos/struct_field_value_copy.tcyr — native: 94 (floor 94). cx: it does NOT
#       compile (pre-existing: `mkpt`/`twice` return a 16 B Pt, "cx: int-class 16B struct
#       pair-return ABI not supported"), so R3 carries its V3/V4 shapes for cx. The row pins that
#       refusal as the ONLY kind of error (nine sites today), by name; the day cx compiles the
#       file, the row instead requires it to pass on cxvm with the full count — it can never go
#       quietly unrun.
#   R7  tests/tcyr/crossos/tuple_values.tcyr (6.7.7, B4: tuples as values) — native and cxvm each
#       print `<N> passed, 0 failed` with N derived from the source (65 at T3, 111 at T4, 168 at T5, 191 at T6: floor 191)
#       and exit 0.
#   Anti-vacuous: each inline file's native leg is the control (a cx green on a file that is wrong
#   everywhere is impossible), each .tcyr must match a count derived from its source, and each
#   inline success needs a stdout marker printed only when every row in it is right.
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs, and — unless CYCC_CX is set — the cx
# compiler from THIS tree's src/main_cx.cyr, and cxvm from programs/cxvm.cyr (CXVM overrides it).
# So a cx-backend mutation is picked up by running the gate from a mutated COPY of the tree (it
# derives cycc_cx from that tree's src/); a frontend mutation needs the mutant native compiler too:
#     cp the tree to $M; edit $M/src/...; build/cycc < $M/src/main.cyr > mut_cycc   (from $M)
#     CYCC=mut_cycc sh $M/tests/gates/codegen/cx_crossos_rows_run.sh
# or, against the real tree: CYCC=mut_cycc CYCC_CX=mut_cycc_cx sh tests/gates/codegen/...
# (relative CYCC / CYCC_CX / CXVM are resolved against the CALLER's directory before the cd)
# (mut_cycc_cx = build/cycc < $M/src/main_cx.cyr, built from inside $M).
#
# MUTATION LEDGER (6.6.12, measured on the merged tree, each in a scratch copy; real tree 12/12)
#   a. B06: cx EVSTORE_W / EFLSTORE_W back to `EVSTORE(S, idx)` / `EFLSTORE(S, idx)` (8-byte
#      stores); the gate run from the mutated copy with the real build/cycc -> R1 cx RED (exit 191 =
#      bits 1|2|4|8|16|32|128, B01's predicted pre-B06 cx value), R4 cx RED (24 passed, 34 failed);
#      every native leg green. The same mutant cycc_cx passed as CYCC_CX to the real tree's gate
#      -> the same two rows RED.
#   b. B02: _spi_nested's `_spi_fields(S, tidx, li, ft - 1, off);` back to the pre-6.6.12 flatten
#      (8 bytes per inner field, no recursion) -> R2 RED on both legs (the two-level literals no
#      longer compile: "expected '}', got number 4") and R6 native RED. With the two-level rows
#      dropped the one-level rows still reach runtime and exit 3 (bits 1|2, the HO literal overran
#      its canaries) natively AND on cxvm, 0 on the real tree.
#   c. B03 V3: `_fla_want = st;` deleted from _push_struct_expr_arg (parse_fn.cyr) -> R3 RED (native
#      SIGSEGV; cxvm traps "guest address out of range: 3"), R5 RED on both legs, R6 native RED
#   d. B03 V4: `_gci_src` returns 0 first (parse_decl.cyr) -> R3 RED (native SIGSEGV; cxvm traps
#      "guest address out of range: 3"), R6 native RED
#   (Before the cxvm host-memory bug's cxvm bounds checks the c/d cx legs exited 63 / 64 — B03's hand-off numbers;
#   cxvm now traps the stray access, exit 1, which the row reads as RED just the same.)
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
# The gate cd's to $ROOT before it runs anything, so a RELATIVE compiler path (the mutation
# recipe above) is resolved against the caller's CWD here — else it fails as a harness error that
# reads RED without the mutant ever running: a false catch.
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "$CC")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
[ -x "$CC" ] || { echo "SKIP: cx_crossos_rows_run — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: cx_crossos_rows_run — no timeout(1) (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cx_crossos_rows_run — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0

if [ -n "${CYCC_CX:-}" ]; then
    [ -x "$CYCC_CX" ] || { echo "FAIL: cx_crossos_rows_run — CYCC_CX=$CYCC_CX is not executable"; exit 1; }
    CX=$CYCC_CX
else
    CX=$T/cycc_cx
    "$CC" < src/main_cx.cyr > "$CX" 2> "$T/eb"; chmod +x "$CX"
    [ -s "$CX" ] || { echo "FAIL: cx_crossos_rows_run — cannot build the cx compiler from src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi
if [ -n "${CXVM:-}" ]; then
    [ -x "$CXVM" ] || { echo "FAIL: cx_crossos_rows_run — CXVM=$CXVM is not executable"; exit 1; }
    VM=$CXVM
else
    VM=$T/cxvm
    "$CC" < programs/cxvm.cyr > "$VM" 2> "$T/eb"; chmod +x "$VM"
    [ -s "$VM" ] || { echo "FAIL: cx_crossos_rows_run — cannot build cxvm from programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# inline LABEL SRC WANT_RC MARKER — native leg, then cx leg; each must exit WANT_RC and print MARKER.
inline() {
    lab=$1; src=$2; want=$3; mark=$4
    if "$CC" < "$src" > "$T/n" 2> "$T/ne"; then
        chmod +x "$T/n"
        rc=0; (cd "$T" && timeout 60 ./n > "$T/no" 2>&1) || rc=$?
        if [ "$rc" = "$want" ] && grep -qx "$mark" "$T/no"; then ok "$lab native: exit $rc, marker"
        else bad "$lab native: exit $rc (want $want), marker $(grep -cx "$mark" "$T/no")/1"; fi
    else
        bad "$lab native: does not compile: $(grep -m1 '^error' "$T/ne")"
    fi
    if "$CX" < "$src" > "$T/c.cyx" 2> "$T/ce"; then
        rc=0; timeout 60 "$VM" < "$T/c.cyx" > "$T/co" 2>&1 || rc=$?
        if [ "$rc" = "$want" ] && grep -qx "$mark" "$T/co"; then ok "$lab cxvm: exit $rc, marker"
        else bad "$lab cxvm: exit $rc (want $want), marker $(grep -cx "$mark" "$T/co")/1 $(grep -m1 '^cxvm:' "$T/co")"; fi
    else
        bad "$lab cxvm: cycc_cx does not compile it: $(grep -m1 '^error' "$T/ce")"
    fi
}

# Every assertion line; and the cx subset: outside `#ifndef CYRIUS_TARGET_CX` ... `#endif` (either
# may be indented — generic_struct_inference.tcyr's TC row is).
n_all() { grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$1"; }
n_cx()  { awk '/^[[:space:]]*#ifndef CYRIUS_TARGET_CX/{s=1; next} /^[[:space:]]*#endif/{s=0; next} !s && /^[[:space:]]*assert(_[a-z]+)?\(/{n++} END{print n+0}' "$1"; }

# summary LABEL OUT RC WANT — exit 0 and the LAST line reads `WANT passed, 0 failed`.
summary() {
    if [ "$3" = 0 ] && tail -1 "$2" | grep -q "^$4 passed, 0 failed"; then ok "$1: $4 passed, 0 failed"
    else bad "$1: exit $3, want '$4 passed, 0 failed', got: $(tail -1 "$2") $(grep -m2 'FAIL' "$2" | tr '\n' ' ')"; fi
}
tcyr_native() {  # FILE FLOOR
    w=$(n_all "$1")
    [ "$w" -ge "$2" ] || { bad "$1 native: only $w assertions in the source (floor $2)"; return; }
    if "$CC" < "$1" > "$T/n" 2> "$T/ne"; then
        chmod +x "$T/n"; rc=0; (cd "$T" && timeout 120 ./n > "$T/no" 2>&1) || rc=$?
        summary "$1 native" "$T/no" "$rc" "$w"
    else bad "$1 native: does not compile: $(grep -m1 '^error' "$T/ne")"; fi
}
tcyr_cx() {  # FILE FLOOR
    w=$(n_cx "$1")
    [ "$w" -ge "$2" ] || { bad "$1 cxvm: only $w cx assertions in the source (floor $2)"; return; }
    if "$CX" < "$1" > "$T/c.cyx" 2> "$T/ce"; then
        rc=0; timeout 120 "$VM" < "$T/c.cyx" > "$T/co" 2>&1 || rc=$?
        summary "$1 cxvm" "$T/co" "$rc" "$w"
    else bad "$1 cxvm: cycc_cx does not compile it: $(grep -m1 '^error' "$T/ce")"; fi
}

# ── the inline row files (from the B01 / B02 / B03 hand-offs; a stdout marker added to each) ──
cat > "$T/b01.cyr" <<'EOF'
# B01 narrow-slot row shapes, inline (no assert/fmt): exit 0 = all rows right; else a bitmask.
var P_A: u8 = 5;
var P_B: u8 = 7;
var P_C: u8 = 9;
var P_D: u8 = 13;
var K_A: u8 = 5;
var K_B: u8 = 7;
var S_A: u8 = 4;
var S_B: u8 = 1;
var S_E: i8 = 0 - 4;
var S_F: i8 = 0 - 1;
var H_A: u16 = 3;
var H_B: u16 = 0x1234;
var S_S: i8 = 0 - 8;
var S_T: i8 = 5;
fn go(): i64 {
    var bad = 0;
    for (P_A = 250; P_A != 252; P_A = P_A + 1) { }
    if (P_A != 252 || P_B != 7 || P_C != 9 || P_D != 13) { bad = bad | 1; }
    for (K_A = 254; K_A != 1; K_A += 1) { }
    if (K_A != 1 || K_B != 7) { bad = bad | 2; }
    var i: u8 = 5;
    for (i = 254; i != 1; i += 1) { }
    i >>= 1;
    if (i != 0) { bad = bad | 4; }
    var q: u8 = 5;
    store64(&q, 0);
    for (q = 254; q != 0; q += 1) { }
    if (load64(&q) != 0) { bad = bad | 4; }
    S_A >>= 1;
    if (S_A != 2 || S_B != 1) { bad = bad | 8; }
    S_E += 1;
    if (S_E != 0 - 3 || S_F != 0 - 1) { bad = bad | 16; }
    for (H_A = 0xFFFE; H_A != 1; H_A += 1) { }
    if (H_A != 1 || H_B != 0x1234) { bad = bad | 32; }
    var c: i8 = 0 - 8;
    c /= 2;
    if (c != 0 - 4) { bad = bad | 64; }
    S_S /= 2;
    if (S_S != 0 - 4 || S_T != 5) { bad = bad | 128; }
    return bad;
}
var _b = go();
if (_b == 0) { syscall(1, 1, "cx-rows B01 ok\n", 15); }
syscall(60, _b);
EOF

cat > "$T/b02.cyr" <<'EOF'
# B02 nested / generic struct-literal rows, no lib: exit 0 when every row is right, else the OR of
# the failing rows' bits.
struct Pt { x; y; }
struct Box { v: Pt; n; }
struct Big { a; b; c; }
struct BB { k; w: Big; }
struct Outer { t; b: Box; }
struct Odd { a: i8; b: i16; }
struct HasOdd { o: Odd; tail: i8; }
struct HO { o: Odd; t: i8; u: i32; }
struct HH { h: HO; z: i8; }
struct GBx<T> { v: T; n; }
fn mkbig(a): Big { var p: Big; p.a = a; p.b = a + 1; p.c = a + 2; return p; }
fn mkodd(a): Odd { var o: Odd; o.a = a; o.b = a * 100; return o; }
fn ou4(o): i64 { return load64(o) + load64(o + 8) * 10 + load64(o + 16) * 100 + load64(o + 24) * 1000; }
fn hh5(h): i64 { return load8(h) + load16(h + 1) * 10 + load8(h + 3) * 100 + load32(h + 4) * 1000 + load8(h + 8) * 10000; }
fn ho4(h): i64 { return load8(h) + load16(h + 1) * 10 + load8(h + 3) * 100 + load32(h + 4) * 1000; }

var GHO = HO { 1, 2, 3, 4 };
var GHO_C1 = 0x5A5A5A5A5A5A5A5A;
var GHO_C2 = 0x5A5A5A5A5A5A5A5A;
var GOU = Outer { 1, 2, 3, 4 };
var GOU_C = 0x5A5A5A5A5A5A5A5A;
var GHH = HH { 1, 2, 3, 4, 5 };
var GHH_C = 0x5A5A5A5A5A5A5A5A;
var GP = Pt { 2, 3 };
var GBOX = Box { GP, 4 };
var GGB: GBx<Pt> = GBx<Pt>{ GP, 4 };
var GGI = GBx<i64>{ 7, 5 };

fn ho_local(): i64 {
    var c0 = 0x5A5A5A5A5A5A5A5A;
    var h = HO { 1, 2, 3, 4 };
    var c1 = 0x5A5A5A5A5A5A5A5A;
    if (c0 != 0x5A5A5A5A5A5A5A5A) { return 0; }
    if (c1 != 0x5A5A5A5A5A5A5A5A) { return 0; }
    return ho4(&h);
}
fn ou_local(): i64 { var c0 = 7; var o = Outer { 1, 2, 3, 4 }; var c1 = 8; return ou4(&o) + c0 * 10000 + c1 * 100000; }
fn hh_local(): i64 { var c0 = 7; var h = HH { 1, 2, 3, 4, 5 }; var c1 = 8; return hh5(&h) + c0 * 100000 + c1 * 1000000; }
fn box_local(): i64 { var p: Pt; p.x = 1; p.y = 2; var b = Box { p, 5 }; p.x = 9; return b.v.x + b.v.y * 10 + b.n * 100; }
fn box_field(): i64 { var a: Box; a.v.x = 6; a.v.y = 8; a.n = 1; var b = Box { a.v, 2 }; return b.v.x + b.v.y * 10 + b.n * 100; }
fn bb_call(): i64 { var b = BB { 9, mkbig(1) }; return b.w.a + b.w.b * 10 + b.w.c * 100 + b.k * 1000; }
fn odd_call(): i64 { var h = HasOdd { mkodd(2), 5 }; return h.o.a + h.o.b * 10 + h.tail * 10000; }
fn ou_descend(): i64 { var p: Pt; p.x = 2; p.y = 3; var o = Outer { 1, p, 4 }; return ou4(&o); }
fn gen_local(): i64 { var p: Pt; p.x = 1; p.y = 2; var b: GBx<Pt> = GBx<Pt>{ p, 5 }; return b.n + b.v.x * 10 + b.v.y * 100; }
fn gen_i64(): i64 { var b = GBx<i64>{ 7, 5 }; return b.n + b.v * 10; }

fn main(): i64 {
    var bad = 0;
    if (ho4(&GHO) != 4321) { bad = bad | 1; }
    if (GHO_C1 != 0x5A5A5A5A5A5A5A5A) { bad = bad | 1; }
    if (GHO_C2 != 0x5A5A5A5A5A5A5A5A) { bad = bad | 1; }
    if (ho_local() != 4321) { bad = bad | 2; }
    if (ou4(&GOU) != 4321) { bad = bad | 4; }
    if (GOU_C != 0x5A5A5A5A5A5A5A5A) { bad = bad | 4; }
    if (ou_local() != 874321) { bad = bad | 4; }
    if (hh5(&GHH) != 54321) { bad = bad | 8; }
    if (GHH_C != 0x5A5A5A5A5A5A5A5A) { bad = bad | 8; }
    if (hh_local() != 8754321) { bad = bad | 8; }
    if (box_local() != 521) { bad = bad | 16; }
    if (box_field() != 286) { bad = bad | 16; }
    if (GBOX.v.x + GBOX.v.y * 10 + GBOX.n * 100 != 432) { bad = bad | 16; }
    if (bb_call() != 9321) { bad = bad | 32; }
    if (odd_call() != 52002) { bad = bad | 32; }
    if (ou_descend() != 4321) { bad = bad | 64; }
    if (gen_local() != 215) { bad = bad | 128; }
    if (gen_i64() != 75) { bad = bad | 128; }
    if (GGB.v.x + GGB.v.y * 10 + GGB.n * 100 != 432) { bad = bad | 128; }
    if (GGI.v + GGI.n * 10 != 57) { bad = bad | 128; }
    return bad;
}
var _m = main();
if (_m == 0) { syscall(1, 1, "cx-rows B02 ok\n", 15); }
syscall(60, _m);
EOF

cat > "$T/b03.cyr" <<'EOF'
# B03 struct copies whose source is a field or a global, no lib: exit 128 when every row is right,
# else the OR of the failing rows' bits, 1..127.
struct Pt { x; y; }
struct Box { v: Pt; n; }
struct Q { a; b; c; }
struct RQ { q: Q; n; }
fn fa_take(p: Pt): i64 { var r = p.x * 10 + p.y; p.x = 99; return r; }
fn fa_mid(k, p: Pt, j): i64 { return k * 1000 + p.x * 10 + p.y + j * 100; }
fn fa_q(q: Q): i64 { return q.a + q.b * 10 + q.c * 100; }
fn fa_gen<T>(p: T): i64 { return p.x * 10 + p.y; }
var GFA = Box { 3, 4, 9 };
var GFQ = RQ { 1, 2, 3, 4 };
var GCA = Pt { 3, 4 };
var GCB: Pt = GCA;
var GCF: Pt = GFA.v;
var GCQ: Q = GFQ.q;
fn r_local(): i64 { var r: Box; r.v.x = 3; r.v.y = 4; r.n = 9; return fa_take(r.v); }
fn r_global(): i64 { return fa_q(GFQ.q) * 100 + fa_mid(0, GFA.v, 0); }
fn r_param(r: Box): i64 { return fa_mid(0, r.v, 0); }
fn r_ptr(): i64 { var buf: i64[3]; var r: Box = &buf; r.v.x = 3; r.v.y = 4; r.n = 9; return fa_take(r.v); }
fn r_gen(): i64 { var r: Box; r.v.x = 3; r.v.y = 4; r.n = 9; return fa_gen<Pt>(r.v); }
fn r_copy(): i64 { var r: Box; r.v.x = 3; r.v.y = 4; r.n = 9; var a = fa_mid(5, r.v, 6) + fa_take(r.v); return a + r.v.x * 100000; }
fn go(): i64 {
    var bad = 0;
    if (r_local() != 34) { bad = bad | 1; }
    if (r_global() != 32134) { bad = bad | 2; }
    var pb: Box; pb.v.x = 3; pb.v.y = 4; pb.n = 9;
    if (r_param(pb) != 34) { bad = bad | 2; }
    if (r_ptr() != 34) { bad = bad | 4; }
    if (r_gen() != 34) { bad = bad | 8; }
    if (r_copy() != 5634 + 34 + 300000) { bad = bad | 16; }
    return bad;
}
var bad = go();
if (fa_mid(1, GFA.v, 2) != 1234) { bad = bad | 32; }
if (fa_gen<Pt>(GFA.v) != 34) { bad = bad | 32; }
if (GCB.x * 10 + GCB.y != 34) { bad = bad | 64; }
if (GCF.x * 10 + GCF.y != 34) { bad = bad | 64; }
if (GCQ.a + GCQ.b * 10 + GCQ.c * 100 != 321) { bad = bad | 64; }
GCA.x = 9; GFA.v.y = 8;
if (GCB.x * 10 + GCB.y + GCF.x * 1000 + GCF.y * 100 != 3434) { bad = bad | 64; }
var GPA: Pt = GCA;
var GPF: Pt = GFA.v;
GCA.y = 0;
if (GPA.x * 10 + GPA.y + GPF.x * 1000 + GPF.y * 100 != 3894) { bad = bad | 64; }
if (bad == 0) { bad = 128; syscall(1, 1, "cx-rows B03 ok\n", 15); }
syscall(60, bad);
EOF

echo "R1-R3 — the B01 / B02 / B03 inline rows, native (the control) then cxvm:"
inline "R1 B01 narrow slots (V1)" "$T/b01.cyr" 0 "cx-rows B01 ok"
inline "R2 B02 nested/generic struct literals (V2)" "$T/b02.cyr" 0 "cx-rows B02 ok"
inline "R3 B03 field argument + top-level copy-init (V3, V4)" "$T/b03.cyr" 128 "cx-rows B03 ok"

echo "R4-R5 — the crossos .tcyr files, native then cxvm, counts derived from the source:"
tcyr_native tests/tcyr/crossos/narrow_slot_width.tcyr 58
tcyr_cx     tests/tcyr/crossos/narrow_slot_width.tcyr 58
tcyr_native tests/tcyr/crossos/generic_struct_inference.tcyr 113
tcyr_cx     tests/tcyr/crossos/generic_struct_inference.tcyr 70

echo "R6 — struct_field_value_copy.tcyr: native in full; on cx either refused BY NAME or run in full:"
F=tests/tcyr/crossos/struct_field_value_copy.tcyr
tcyr_native "$F" 94
if "$CX" < "$F" > "$T/c.cyx" 2> "$T/ce"; then
    echo "  note: cycc_cx now compiles $F — it must pass in full on cxvm"
    tcyr_cx "$F" 94
else
    nerr=$(grep -c '^error' "$T/ce")
    npr=$(grep -c '^error:.*cx: int-class 16B struct pair-return ABI not supported$' "$T/ce")
    if [ "$nerr" -ge 1 ] && [ "$npr" = "$nerr" ]; then
        ok "$F cxvm: refused by name, every error ($nerr) the known cx 16 B pair-return limit (R3 carries its V3/V4 shapes)"
    else
        bad "$F cxvm: $nerr error(s), $npr of them the 16 B pair-return refusal — any other is new: $(grep '^error' "$T/ce" | grep -v 'pair-return ABI not supported' | head -2 | tr '\n' ' ')"
    fi
fi

echo "R7 — tuple_values.tcyr (6.7.7, B4), native then cxvm, the count derived from the source:"
tcyr_native tests/tcyr/crossos/tuple_values.tcyr 203
tcyr_cx     tests/tcyr/crossos/tuple_values.tcyr 203

WANT=14
if [ "$fail" -ne 0 ]; then echo "FAIL: cx_crossos_rows_run — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: cx_crossos_rows_run — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: cx_crossos_rows_run — $pass/$WANT rows: V1-V4 hold on cxvm and natively (B01/B02/B03 inline rows, narrow_slot_width + generic_struct_inference + tuple_values counts derived from source, struct_field_value_copy's cx refusal pinned by name)"
exit 0
