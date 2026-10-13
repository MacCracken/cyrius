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
# ROWS (60, all required — the count is checked, so a row that silently stops running is RED)
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
#   R5  tests/tcyr/crossos/generic_struct_inference.tcyr — native: every assertion (164, floor 164);
#       cxvm: every assertion outside `#ifndef CYRIUS_TARGET_CX` blocks, indented ones included
#       (163, floor 163 — all but the TC row: cx emits no tail call) — the B02 LIT group, B04's
#       CF group and, since 6.7.8, the 16 B pair-return rows and the SC rows (T inferred through a
#       generic struct parameter) run there.
#   R6  tests/tcyr/crossos/struct_field_value_copy.tcyr — native and cxvm in full (96, floor 96).
#       Until 6.7.8 cx refused it (`mkpt`/`twice` return a 16 B Pt, "cx: int-class 16B struct
#       pair-return ABI not supported") and the row pinned that refusal by name; cx now has the
#       r0:r4 struct pair, so the file must compile and pass in full there.
#   R8  (6.7.8) every crossos file the cx 16 B pair refusal kept from compiling for cx and no other
#       gate runs on cxvm — native and cxvm each print `<N> passed, 0 failed`, N derived from the
#       source (floors: today's counts). The files whose `#ifndef CYRIUS_TARGET_CX` pair fences
#       6.7.8 lifted run on cx in their own gates (default_named_args_checked.sh A5 / AC5,
#       struct_value_codegen.sh A6, global_struct_store_width.sh, defer_every_return_path.sh,
#       struct_pair_multi_value_crossing.sh) and R5 here.
#   R7  tests/tcyr/crossos/tuple_values.tcyr (6.7.7, B4: tuples as values) — native and cxvm each
#       print `<N> passed, 0 failed` with N derived from the source (65 at T3, 111 at T4, 168 at T5, 191 at T6: floor 191)
#       and exit 0.
#   R9  (6.7.8, dyn D5 / D6) tests/tcyr/crossos/dyn_objects.tcyr — forming a checked `dyn` (every FORM
#       source, the declared scalars, the defaults, every destination, the records, the #inline
#       replay; dispatched by hand through the vtable) and (D6) calling through one (every receiver,
#       argument and result shape, the callee read before the arguments, copies, closures, defer /
#       secret, recursion, #regalloc, top level): native and cxvm each print `<N> passed, 0 failed`,
#       N derived from the source (37 at D5, 78 at D6, 81 at the review's §pairs: floor 81) — the whole
#       file, no cx fence.
#   R10 (6.7.9) `var t, v = fncallN(..)` — x86_64 / aarch64 / PE compiled it and cx alone refused it
#       ("binds 2 names, but 'fncall1' returns 1 value"): lib/fnptr.cyr's cx arms read
#       `result = callptr(..); return result;`, a body `_prescan_ret_single` proves one-valued, while
#       every other target's body is an `asm` block. (a) the filed repro verbatim: native and cxvm
#       exit 83; (b) fncall0..8 each destructured (every arm), plus `fncall2(&fncall1, ..)` and
#       `callptr(&fncall8, ..)`, which run lib/fnptr.cyr's BODY and must carry the pair: exit 0 AND
#       the `cx-rows fncall ok` marker.
#   R11 (6.7.9) tests/tcyr/crossos/method_pair_result.tcyr (6.6.16, C4) — it destructures
#       `fncall1(g, d)`, so it had never compiled for cx: native and cxvm each print `<N> passed,
#       0 failed`, N derived from the source (31, floor 31), the whole file.
#   R12 (6.7.9) tests/tcyr/crossos/const_fold_int_min_div.tcyr (6.6.20, RPD-06) — cx replayed a
#       constant-folded global's initializer at run time, so `var Q = INT_MIN / -1;` (folded to
#       INT_MIN since 6.6.20) ran cxvm's idiv and died SIGFPE (136): native and cxvm each print
#       `<N> passed, 0 failed`, N derived from the source (13, floor 13), the whole file (the
#       critical lane's hand-off; its own rows are cx_forward_read_constant_global.sh G-J).
#   R13 (6.7.10, B7-1) tests/tcyr/crossos/small_struct_handle_line.tcyr — the handle line: a struct
#       local of 8 B or less initialised from a non-struct-value is a handle, every initialiser,
#       consumer and size 1..8 B against its 16 B twin: native and cxvm each print `<N> passed,
#       0 failed`, N derived from the source (220, floor 220), the whole file (its own gate,
#       small_struct_handle_line.sh, runs it on x86 / IR / DCE / aarch64 / cx / PE too).
#   R14 (6.7.10, B7-1g) tests/tcyr/crossos/small_struct_global_handle_line.tcyr — the handle line for
#       globals: a struct global of 8 B or less initialised from a non-struct-value is a handle,
#       every initialiser (the declaration zone and after the first statement), consumer (in a fn and
#       at top level) and size 1..8 B against its 16 B twin: native and cxvm each print `<N> passed,
#       0 failed`, N derived from the source (243, floor 243), the whole file (its own gate rows,
#       small_struct_handle_line.sh R2, run it on x86 / IR / DCE / aarch64 / cx / PE too).
#   R15 (6.7.10, B7-1b) tests/tcyr/crossos/small_struct_pointer_arg.tcyr — a typed pointer or `&s` into a
#       by-value struct parameter of 8 B or less passes the struct it points at, every form, consumer
#       and size 1..8 B against its 16 B twin: native and cxvm each print `<N> passed, 0 failed`, N
#       derived from the source (69, floor 69), the whole file (its own gate rows,
#       small_struct_handle_line.sh R3, run it on x86 / IR / DCE / aarch64 / cx / PE too).
#   R16 (6.7.10, B7-1c) tests/tcyr/crossos/small_struct_pointer_copy.tcyr — struct copies are
#       size-independent: `l = p` / `G = p` (`p: *S`) copy the struct p points at and `q = r` through
#       `q: *S` copies into the pointee at every size, every shape and size 1..8 B against its 16 B
#       twin: native and cxvm each print `<N> passed, 0 failed`, N derived from the source (67, floor
#       67), the whole file (its own gate rows, small_struct_handle_line.sh R5, run it on x86 / IR /
#       DCE / aarch64 / cx / PE too).
#   R17 (6.7.10, B7-2) tests/tcyr/crossos/narrow_unsigned_f32_fields.tcyr — u8 / u16 / u32 / f32 struct
#       fields are their widths (packed, zero-extended): sizeof / offsets, wrap, unaligned `*T` access,
#       f32, literals, the by-value class sweep at every size 1..17 and 20: native and cxvm each print
#       `<N> passed, 0 failed`, N derived from the source (199, floor 199), the whole file (its own
#       gate, narrow_fields_checked.sh A, runs it on x86 / IR / DCE / aarch64 / cx / PE too).
#   R18 (6.7.10) the sakshi fold on cx (sakshi 2.5.9's CYRIUS_TARGET_CX arm — before it every program
#       that included lib/sakshi.cyr stopped on cx with 10 "undefined variable '_SK_SYS_*'" errors): a
#       log line, a span and, on cx only, sakshi_output_udp's refusal (-1) — native and cxvm each exit 0
#       with the `cx-rows sakshi ok` marker, and each leg's stderr carries the `[INFO] cx-sakshi log
#       line` the program logged (4 rows).
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
#   6.7.9, R10 / R11 (a scratch copy of the tree; the real tree 44/44, 46/46 with R12):
#   e. lib/fnptr.cyr's nine cx arms back to `result = callptr(..);` -> R10a, R10b and R11 cxvm RED
#      ("binds 2 names, but 'fncall1' returns 1 value"; R10b names fncall0), 41 green.
#   f. fncall8's cx arm alone back -> R10b cxvm RED (names fncall8), 43 green; fncall0's alone ->
#      R10b cxvm RED (names fncall0), 43 green.
#   g. (R12) the critical lane's bite 18 reverted in parse_decl.cyr (cx keeps the deferred replay of
#      a folded global), that tree's cycc_cx passed as CYCC_CX -> R12 cxvm RED (exit 136, SIGFPE),
#      45 green.
#   h. (R18 — R13 in the refold worktree, measured there; that tree 50/50) lib/sakshi.cyr back to 2.5.8 (the
#      6.7.9 fold, no cx arm) -> R18 cxvm RED twice ("undefined variable '_SK_SYS_WRITE'" at
#      lib/sakshi.cyr:248; no log line), both native legs green, 48 green.
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
tcyr_native tests/tcyr/crossos/generic_struct_inference.tcyr 164
tcyr_cx     tests/tcyr/crossos/generic_struct_inference.tcyr 163

echo "R6 — struct_field_value_copy.tcyr, native then cxvm in full (cx refused it until 6.7.8):"
tcyr_native tests/tcyr/crossos/struct_field_value_copy.tcyr 96
tcyr_cx     tests/tcyr/crossos/struct_field_value_copy.tcyr 96

echo "R7 — tuple_values.tcyr (6.7.7, B4), native then cxvm, the count derived from the source:"
tcyr_native tests/tcyr/crossos/tuple_values.tcyr 203
tcyr_cx     tests/tcyr/crossos/tuple_values.tcyr 203

echo "R8 — the crossos files cx's 16 B pair refusal kept off cxvm (6.7.8), native then cxvm:"
for _r8 in aggregate_storage_class:46 for_step_struct_assign:14 generic_two_param_struct:25 \
           impl_inherent:4 method_chain:18 pair_return_shapes:6 struct_arg_type_accepted:38 \
           struct_param_byvalue_copy:32 struct_ptrmode_assign_copy:59 struct_ptrmode_return_copy:17 \
           struct_valued_call_sites:57; do
    tcyr_native "tests/tcyr/crossos/${_r8%%:*}.tcyr" "${_r8##*:}"
    tcyr_cx     "tests/tcyr/crossos/${_r8%%:*}.tcyr" "${_r8##*:}"
done

echo "R9 — dyn_objects.tcyr (6.7.8, dyn D5 forming / D6 the call), native then cxvm, the count derived from the source:"
tcyr_native tests/tcyr/crossos/dyn_objects.tcyr 81
tcyr_cx     tests/tcyr/crossos/dyn_objects.tcyr 81

# rc_both LABEL SRC WANT_RC — native leg, then cx leg; each must exit WANT_RC (no marker: the filed
# repro prints nothing, and its 83 = 41 + 42 needs both destructured values right).
rc_both() {
    lab=$1; src=$2; want=$3
    if "$CC" < "$src" > "$T/n" 2> "$T/ne"; then
        chmod +x "$T/n"
        rc=0; (cd "$T" && timeout 60 ./n > "$T/no" 2>&1) || rc=$?
        if [ "$rc" = "$want" ]; then ok "$lab native: exit $rc"; else bad "$lab native: exit $rc (want $want)"; fi
    else
        bad "$lab native: does not compile: $(grep -m1 '^error' "$T/ne")"
    fi
    if "$CX" < "$src" > "$T/c.cyx" 2> "$T/ce"; then
        rc=0; timeout 60 "$VM" < "$T/c.cyx" > "$T/co" 2>&1 || rc=$?
        if [ "$rc" = "$want" ]; then ok "$lab cxvm: exit $rc"
        else bad "$lab cxvm: exit $rc (want $want) $(grep -m1 '^cxvm:' "$T/co")"; fi
    else
        bad "$lab cxvm: cycc_cx does not compile it: $(grep -m1 '^error' "$T/ce")"
    fi
}

# The filed repro, verbatim (docs/development/issues/repros/2026-10-10-fncall-destructure-refused-on-cx-only.cyr).
cat > "$T/fc_repro.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
fn g(d): (i64, i64) { return (d, d + 1); }
fn main(): i64 {
    var t, v = fncall1(&g, 41);
    return t + v;
}
var rc = main();
syscall(60, rc);
EOF

cat > "$T/fc_arms.cyr" <<'EOF'
# fncall0..8 destructured (a direct call is lowered by the compiler, but the one-value check reads
# lib/fnptr.cyr's body), and two calls that run that BODY. exit 0 when every row is right, else the
# OR of the failing rows' bits.
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
fn g0(): (i64, i64) { return (7, 8); }
fn g1(a): (i64, i64) { return (a, a + 1); }
fn g2(a, b): (i64, i64) { return (a + b, b); }
fn g3(a, b, c): (i64, i64) { return (a + b + c, c); }
fn g4(a, b, c, d): (i64, i64) { return (a + b + c + d, d); }
fn g5(a, b, c, d, e): (i64, i64) { return (a + b + c + d + e, e); }
fn g6(a, b, c, d, e, f): (i64, i64) { return (a + b + c + d + e + f, f); }
fn g7(a, b, c, d, e, f, g): (i64, i64) { return (a + b + c + d + e + f + g, g); }
fn g8(a, b, c, d, e, f, g, h): (i64, i64) { return (a + b + c + d + e + f + g + h, h * 10 + g); }
fn w8(fp): i64 { return callptr(&fncall8, fp, 1, 2, 3, 4, 5, 6, 7, 8); }
fn go(): i64 {
    var bad = 0;
    var t0, v0 = fncall0(&g0);
    if (t0 != 7 || v0 != 8) { bad = bad | 1; }
    var t1, v1 = fncall1(&g1, 41);
    if (t1 != 41 || v1 != 42) { bad = bad | 2; }
    var t2, v2 = fncall2(&g2, 1, 2);
    if (t2 != 3 || v2 != 2) { bad = bad | 4; }
    var t3, v3 = fncall3(&g3, 1, 2, 3);
    if (t3 != 6 || v3 != 3) { bad = bad | 8; }
    var t4, v4 = fncall4(&g4, 1, 2, 3, 4);
    if (t4 != 10 || v4 != 4) { bad = bad | 16; }
    var t5, v5 = fncall5(&g5, 1, 2, 3, 4, 5);
    if (t5 != 15 || v5 != 5) { bad = bad | 32; }
    var t6, v6 = fncall6(&g6, 1, 2, 3, 4, 5, 6);
    if (t6 != 21 || v6 != 6) { bad = bad | 64; }
    var t7, v7 = fncall7(&g7, 1, 2, 3, 4, 5, 6, 7);
    if (t7 != 28 || v7 != 7) { bad = bad | 128; }
    var t8, v8 = fncall8(&g8, 1, 2, 3, 4, 5, 6, 7, 8);
    if (t8 != 36 || v8 != 87) { bad = bad | 256; }
    var a1, b1 = fncall2(&fncall1, &g1, 41);
    if (a1 != 41 || b1 != 42) { bad = bad | 512; }
    var a8, b8 = w8(&g8);
    if (a8 != 36 || b8 != 87) { bad = bad | 1024; }
    return bad;
}
var _b = go();
if (_b == 0) { syscall(1, 1, "cx-rows fncall ok\n", 18); }
syscall(60, _b);
EOF

echo "R10 — \`var t, v = fncallN(..)\` (6.7.9: cx alone refused it), native then cxvm:"
rc_both "R10a the filed repro, fncall1 destructured" "$T/fc_repro.cyr" 83
inline  "R10b fncall0..8 destructured + the body through &fncall1 / &fncall8" "$T/fc_arms.cyr" 0 "cx-rows fncall ok"

echo "R11 — method_pair_result.tcyr (6.6.16 C4; never compiled for cx until 6.7.9), native then cxvm:"
tcyr_native tests/tcyr/crossos/method_pair_result.tcyr 31
tcyr_cx     tests/tcyr/crossos/method_pair_result.tcyr 31

echo "R12 — const_fold_int_min_div.tcyr (6.6.20 RPD-06; cx replayed the folded INT_MIN / -1 until 6.7.9), native then cxvm:"
tcyr_native tests/tcyr/crossos/const_fold_int_min_div.tcyr 13
tcyr_cx     tests/tcyr/crossos/const_fold_int_min_div.tcyr 13

echo "R13 — small_struct_handle_line.tcyr (6.7.10 B7-1: the handle line), native then cxvm:"
tcyr_native tests/tcyr/crossos/small_struct_handle_line.tcyr 220
tcyr_cx     tests/tcyr/crossos/small_struct_handle_line.tcyr 220

echo "R14 — small_struct_global_handle_line.tcyr (6.7.10 B7-1g: the handle line for globals), native then cxvm:"
tcyr_native tests/tcyr/crossos/small_struct_global_handle_line.tcyr 243
tcyr_cx     tests/tcyr/crossos/small_struct_global_handle_line.tcyr 243

echo "R15 — small_struct_pointer_arg.tcyr (6.7.10 B7-1b: a pointer into a by-value struct of 8 B or less), native then cxvm:"
tcyr_native tests/tcyr/crossos/small_struct_pointer_arg.tcyr 69
tcyr_cx     tests/tcyr/crossos/small_struct_pointer_arg.tcyr 69

echo "R16 — small_struct_pointer_copy.tcyr (6.7.10 B7-1c: struct copies through a *T of 8 B or less), native then cxvm:"
tcyr_native tests/tcyr/crossos/small_struct_pointer_copy.tcyr 67
tcyr_cx     tests/tcyr/crossos/small_struct_pointer_copy.tcyr 67

echo "R17 — narrow_unsigned_f32_fields.tcyr (6.7.10 B7-2: u8 / u16 / u32 / f32 fields are their widths), native then cxvm:"
tcyr_native tests/tcyr/crossos/narrow_unsigned_f32_fields.tcyr 199
tcyr_cx     tests/tcyr/crossos/narrow_unsigned_f32_fields.tcyr 199

# ── R18 — the sakshi fold on cx (6.7.10) ──
cat > "$T/sk.cyr" <<'EOF'
# R13: the sakshi fold on cx (sakshi 2.5.9's cx arm): a log line to stderr, a span, the UDP refusal.
include "lib/syscalls.cyr"
include "lib/sakshi.cyr"
fn go(): i64 {
    var bad = 0;
    sakshi_set_level(SK_INFO);
    sakshi_info("cx-sakshi log line", 18);
    sakshi_span_enter("cxspan", 6);
    if (sakshi_span_depth() != 1) { bad = bad | 1; }
    sakshi_span_exit();
    if (sakshi_span_depth() != 0) { bad = bad | 2; }
    #ifdef CYRIUS_TARGET_CX
    if (sakshi_output_udp(0x0100007F, 9999) != 0 - 1) { bad = bad | 4; }
    #endif
    return bad;
}
var _b = go();
if (_b == 0) { syscall(1, 1, "cx-rows sakshi ok\n", 18); }
syscall(60, _b);
EOF

echo "R18 — the sakshi fold on cx (6.7.10: sakshi 2.5.9's cx arm), native then cxvm:"
inline "R18 a log line, a span and the cx UDP refusal" "$T/sk.cyr" 0 "cx-rows sakshi ok"
for _leg in native:no cxvm:co; do
    if grep -q '\[INFO\] cx-sakshi log line$' "$T/${_leg#*:}"; then ok "R18 ${_leg%%:*}: the log line reached stderr"
    else bad "R18 ${_leg%%:*}: no '[INFO] cx-sakshi log line' in its output"; fi
done

WANT=60
if [ "$fail" -ne 0 ]; then echo "FAIL: cx_crossos_rows_run — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: cx_crossos_rows_run — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: cx_crossos_rows_run — $pass/$WANT rows: V1-V4 hold on cxvm and natively (B01/B02/B03 inline rows, narrow_slot_width + generic_struct_inference + struct_field_value_copy + tuple_values counts derived from source), every crossos file the 16 B pair kept off cx runs there in full, dyn_objects (the checked dyn's forming and calls) runs there whole, var t, v = fncallN(..) + method_pair_result build and run on cx as natively, a folded INT_MIN / -1 global never traps cxvm, the handle line for locals and globals (small_struct_handle_line, small_struct_global_handle_line) holds on cxvm as natively, a pointer into a small by-value struct parameter passes its struct (small_struct_pointer_arg), a struct copy through a small *T copies the struct (small_struct_pointer_copy), u8 / u16 / u32 / f32 fields are their widths (narrow_unsigned_f32_fields), and the sakshi fold logs and spans on cx"
exit 0
