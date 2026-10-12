#!/bin/sh
# tests/gates/codegen/small_struct_handle_line.sh — 6.7.10 (B7-1, B7-1g, B7-1b)
#
# THE HANDLE LINE (the user's decision, 2026-10-12): a struct local of 8 B or less initialised from
# anything that is not a struct value of its type is a HANDLE, as one over 8 B is — its slot holds
# the address, its field writes reach the object, and every consumer that takes its struct copies
# through it. Through 6.7.9 MARK_SMALL_STRUCT marked every such local inline whatever its
# initialiser, so `var q: S8 = alloc(8);` held the ADDRESS as `q.v` and `q.v = 5` never reached the
# heap. Filed: docs/development/issues/2026-10-08-small-struct-local-from-address-is-value-not-
# handle.md (its repro: 17 measured, 237 right). With it (the user's planning decision 6): `var q:
# S = *p;` with `p: *S` COPIES at every size — over 8 B it was a handle holding the word `*p` read.
#
# The runtime half is tests/tcyr/crossos/small_struct_handle_line.tcyr (its header carries the
# rule, initialiser by initialiser and consumer by consumer, every 8 B row against its 16 B twin,
# and every size 1..8 B). The release gate's cross-OS leg runs it on ecb / ach / cass / pi; this
# gate runs it on the legs this box has, compilers built from this tree:
#   R0 the filed repro, VERBATIM: exit 237 on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine)
#   R1 the crossos file on the same legs: "N passed, 0 failed (N total)", N derived from the file
#   C  compile rows (x86): C1 a handle <- handle of ANOTHER struct type compiles and rebinds (exit
#      58), as over 8 B; C2 a struct value of another type is still refused by name — `var q: S8 =
#      mku(1);` and, into a handle, `q = mku(1);`; C3 `bs1((t))` with `t: T1` into `p: S1` still
#      compiles (the paren-argument issue's decision, 6.7.11 — the paren peel added no refusal); C4
#      `var q: S8 = *pu;` with `pu: *U8` (a local or a global) is refused by name, as `= pu` is, at
#      8 and 16 B; C5 `return (a, 1)` with a handle compiles and the element is the handle's word,
#      as at 16 B; C6 a handle of another struct returned from an 8 B struct fn returns its struct
#      (3, the value it gave when it was inline), not its address
#   P  (Linux x86_64 + aarch64) a 7 B handle onto the LAST 7 bytes of a 2-page anonymous mapping
#      whose second page is unmapped: passed by value, returned, an operator's right operand, an
#      if-expression branch, a closure capture's argument and `c = a` — exit 0, no fault (no byte
#      past the object is read)
#   AS (x86_64, CYRIUS_ASYNC=1 — a mid-body suspend is x86-only so far) an `async fn` body: a
#      handle, a bind, a by-value argument, a copy into the object and a returned handle across two
#      awaits — exit 0
#
# B7-1g — THE HANDLE LINE FOR GLOBALS (the user's decision 5, 2026-10-12: one rule for locals and
# globals at every size): a struct global of 8 B or less initialised from anything that is not a
# struct value of its type is a handle (GVPM 1), as over 8 B. Its runtime half is
# tests/tcyr/crossos/small_struct_global_handle_line.tcyr (the declaration zone — judged from its
# tokens at the end of pass 1, a fn declared below included — and after the first statement; every
# consumer in a fn and at top level; every size 1..8 B):
#   R2 that file on the same legs as R1, N derived from it (floor 243)
#   GC compile rows (x86): GC1 `var ga: Num = 1;` is a handle global — `ga + gb` is pointer
#      arithmetic (3, no `Num_add`), as at 16 B; a struct value global still dispatches (102); GC2
#      `var G: S8 = *GU;` with `GU: *U8` refused by name in the zone and after it, at 8 and 16 B;
#      GC3 `var G: H = *P;` with P declared below G refused by name (pass 1 could not register G
#      inline; `_gci_below`'s refusal); GC4 one global declared a value and a handle refused by name
#      (two shapes), two handle declarations fold; GC5 the sweep repeats: a global bound to a handle
#      declared below it binds, and an operator on such a handle is pointer arithmetic
#   GP (Linux x86_64 + aarch64) a 7 B handle GLOBAL onto the last 7 bytes of a mapping: by value,
#      returned, an operator's right operand, an if-expression branch, `c = G`, and at TOP LEVEL
#      (a hidden global, no frame) — exit 0, no byte past the object read
#
# B7-1b — A POINTER INTO A BY-VALUE STRUCT PARAMETER OF 8 B OR LESS (the user's decision 7, 2026-10-12:
# `&c` into a by-value struct parameter copies through the pointer at every size): a typed pointer or
# an address passes the struct it points at, as over 8 B (that parameter is address-passed). Through
# 6.7.9 the pointer was pushed as the struct's one word and the callee read the address's bits as its
# fields. Filed: docs/development/issues/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md
# (its repro: 0 measured, 111 right). Its runtime half is tests/tcyr/crossos/small_struct_pointer_arg.tcyr
# (every pointer form and consumer against its 16 B twin, the untyped boundary, sizes 1..8 B, top level):
#   R3 that file on the same legs as R1, N derived from it (floor 69)
#   R4 the filed repro, VERBATIM: exit 111 on the same legs (0 = each callee read the pointer's bits)
#   PP (Linux x86_64 + aarch64) a `*S7` onto the last 7 bytes of a mapping passed by value — a `*T`
#      local, a `: *S7` call, an operator's right operand, a `*S7` global, a closure, and at TOP LEVEL
#      (a hidden global temp) — exit 0, no byte past the object read
#
# MUTATION LEDGER (2026-10-12; each a scratch copy of the tree with the one change, its compiler
# built from that copy, this gate run from the copy with CYCC=<that compiler>):
#   real tree                                         -> GREEN
#   the B7-0 tree (daae99ed, no handle line)        -> RED 22: R0 exit 17 x7; R1 does not compile x7 (`a = u`
#                                                      between an inline S8 and a U8 is refused); C1; C4 x3
#                                                      (`*pu` compiled); C5 SIGSEGV; P x2; AS
#   M2  PARSE_VAR's mark back to MARK_SMALL_STRUCT    -> RED 19: R0 17 x7, R1 does not compile x7, C1,
#                                                      C5, P x2, AS
#   M3  `_CL_CAP_BASE_RA` without the handle arm     -> RED 16: R0 exit 5 x7 (the capture copied the
#                                                      address word), R1 19 rows x7, P x2
#   M4  `_hl_call_whole` answering 0                  -> RED 11: R1 SIGSEGV (`var q: S8 = mk8(5)` a handle
#                                                      at address 5; cxvm "guest address out of range"), C6, P x2, AS
#   M5  `_sci_sval` never set                         -> RED 7: R1 SIGSEGV (`var q: S8 = a` a handle to 5)
#   M6  `_ret_small_ptrp` without the handle          -> RED 11: R1 20 rows x7 (the address returned), C6,
#                                                      P x2, AS
#   M7  `_sarg_byval_small` without `_hl_bare_val`    -> RED 10: R1 58 rows x7, P x2, AS
#   M8  `_op_rhs` without its arm                     -> RED 9: R1 12 rows x7, P x2
#   M9  `_ie_branch` without its arm                  -> RED 9: R1 10 rows x7, P x2
#   M10 `_hl_small_copy` never copying                -> RED 10: R1 26 rows x7, P x2, AS
#   M11 the rebind after the type check               -> RED 8: R1 does not compile x7, C1
#   M12a `_hl_res_into` answering 0 (method / operator / if-expression results into a handle)
#                                                   -> RED 7: R1 5 rows x7
#   M12b `_hl_call_into` answering 0 (a free call into a handle) -> RED 7: R1 12 rows x7
#   M13a `_hl_bare_val` without the paren peel        -> RED 7: R1 10 rows x7
#   M13b `_hl_ret_k` without the wrap                  -> RED 7: R1 10 rows x7
#   M14 `_hdl_val_ra` loading 8 bytes for 3 / 5 / 6 / 7 B -> RED 2: P x86 and P aarch64 exit 139
#   M15 `_agc_handle_local` without the small arm    -> RED 11: R1 43 rows x7, C2 (`q = mku(1)` into a
#                                                      handle no longer refused), P x2, AS
#   M16 `_sci_star` answering 0 (`*p` to the scalar init) -> RED 10: R1 SIGSEGV x7 (the 16 B `*p` twin
#                                                      a handle holding the first field), C4 x3
#   M17 `_hl_cap_hdl` answering 0                     -> RED 9: R1 15 rows x7, P x2
#   M18 `_ret_small_ptrp` refusing another type's handle -> RED 1: C6 (the address returned)
#   M19 `_sci_sval` neither reset nor cleared on read -> RED 7: R1 does not compile x7 (a stale 1 marks
#                                                      the next handle inline)
#   M20 a CAPTURED handle source counted before the rebind test (`h = cap` rebinds h instead of copying
#       through it, as 16 B does)                   -> RED 7: R1 2 rows x7
# B7-1g MUTATION LEDGER (2026-10-12, the same method; the B7-1 compiler cannot build the R2 file at
# all — `X8 = AU8` between two inline globals of different types is refused, a dyn wants `&QG8`):
#   MG1  `_gz_sweep` returns at once (no zone global becomes a handle) -> RED 15: R2 does not compile x7
#                                                      (`X8 = AU8`), GC1 102, GC4 x3 / GC5 x2 / GP x2 refused
#                                                      by the replay's check (`_gz_agree`: "misread")
#   MG2  `_gz_sval` answering 0 (every zone global a handle) -> RED 8: R2 refused by `_gz_agree` x7 (IN8),
#                                                      GC4 (the check fires before the shape refusal)
#   MG3  `_gz_op` answering 0 (operators typed as no struct) -> RED 7: R2 refused by `_gz_agree` x7 (IO8)
#   MG3b MG3 with `_gz_agree` never refusing        -> RED 7: R2 x7 (a fault on x86 x4 / aarch64 / PE, 3
#                                                      rows on cxvm: the operator results held as addresses)
#                                                      — the replay's check is the net
#   MG4  `_gz_late` answering 2 (after the first statement, the old value slot) -> RED 9: R2 x7 (a fault
#                                                      on x86 x4 / aarch64 / PE, 3 rows on cxvm: the alloc /
#                                                      &x writes stay in the global), GP x2
#   MG5  `_agc_handle_global` without the small arm -> RED 9: R2 x7 (`q = G` copied the address: a fault
#                                                      on x86 x4 / aarch64 / PE, cxvm out of range), GP x2
#   MG6  `_hl_gbare` answering 0                     -> RED 9: R2 61 rows x7 (arguments, operands, branches
#                                                      took the address), GP x2
#   MG7  `_ret_small_ptrp` without `_ret_small_gh`  -> RED 9: R2 19 rows x7 (`return G` the address), GP x2
#   MG8  no top-level temp (`_hl_res_into` / `_hl_call_into` back behind GINFN) -> RED 7: R2 x7 (`X8 =
#                                                      mk8(6)` at top level rebinds X8 to address 6: a fault
#                                                      on every leg, cxvm out of range)
#   MG9  `_hg_val_ra` loading 8 bytes at every size  -> RED 2: GP x86 and GP aarch64 exit 139
#   MG10 `_gz_star` answering 0                      -> RED 7: R2 refused x7 (`var IDH: H = *PSH;` not inline
#                                                      in pass 1: "declared below")
#   MG11 `_gz_star_src` without the type check       -> RED 3: GC2 x3 (`*GU` of a U8 / UH compiled)
#   MG12 the sweep walks once (no repeat)            -> RED 2: GC5 x2 (refused by `_gz_agree`)
#   MG13 `_gz_shapes` returns at once                -> RED 2: GC4 x2 (the literal-then-handle redeclaration
#                                                      compiled; the call-then-handle one caught by `_gz_agree`)
#   MG14 `_gz_reg` not noting a literal              -> RED 1: GC4 (the literal-then-handle redeclaration)
#   MG15 `_gz_chain` without the method arm          -> RED 7: R2 refused by `_gz_agree` x7 (IM8)
#   MG16 `_gz_ie` answering 0                         -> RED 7: R2 refused by `_gz_agree` x7 (IE8)
#   MG17 `_hl_capn` answering 0 (a capture is never checked) -> RED 16: R1 13 rows x7 (a captured handle's
#                                                      consumers), R2 1 row x7 (a capture named like a global),
#                                                      P x2
#   MG18 `_gz_split` without the generic-call skip   -> RED 7: R2 refused by `_gz_agree` x7 (`idg<S8>(..)`)
# B7-1b MUTATION LEDGER (2026-10-12, the same method):
#   the B7-1g tree (f72166c0, no pointer arm)         -> RED 16: R3 3 of 69 rows x7, R4 exit 0 x7, PP exit 1 x2
#                                                      (and struct_arg_type_refused.sh B1-B4)
#   MB1 `_hl_byval_arg` never takes the pointer arm   -> RED 16: R3 x7, R4 exit 0 x7, PP x2 (and B1-B4)
#   MB2 `_hl_parg`: step 1 never a pointer            -> RED 14: R3 33 rows x7 (every `&s` / `&G` / `&b` form),
#                                                      R4 exit 11 x7 (and B1, B2, B4)
#   MB3 `_hl_parg`: step 1 always a pointer (no `_hl_p1`) -> RED 7: R3 x7 (an i8 / i16 / i32 local read
#                                                      through as an address: SIGSEGV; cxvm out of range)
#   MB4 `_hl_p1` without the leftmost-term recursion -> RED 7: R3 1 row x7 (`t1(pa + i)`, i: i32, a value)
#   MB5 `_hl_pval_ra` loading 8 bytes at every size  -> RED 2: PP x86 and PP aarch64 exit 139
#   MB6 `_op_rhs` without its pointer arm            -> RED 9: R3 6 rows x7 (`o + sp`, `o + &s`, the 3 / 7 B
#                                                      operands, top level), PP x2
#   MB7 `_hl_narrow_at` without the `&` / `.` skip   -> RED 7: R3 1 row x7 (`t1(&c8)`, `t1(xb.p)` values)
#   MB8 `_hl_pval_ra` without its top-level arm      -> RED 9: R3 x7 (a frame temp at top level: SIGSEGV /
#                                                      SIGILL, cxvm out of range), PP x2
#   MB9 `_sarg_byval_small` without `_hl_byval_arg`  -> RED 16: R3 5 of 69 rows x7, R4 exit 0 x7, PP x2 (and
#                                                      B1-B4)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=small_struct_handle_line
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/small_struct_handle_line.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=220
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
TG=tests/tcyr/crossos/small_struct_global_handle_line.tcyr
[ -f "$TG" ] || { echo "FAIL: $G: $TG is missing"; exit 1; }
NG=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TG")
GFLOOR=243
if [ "$NG" -lt "$GFLOOR" ]; then echo "FAIL: $G: only $NG rows in $TG (floor $GFLOOR) — rows were lost"; exit 1; fi
TP=tests/tcyr/crossos/small_struct_pointer_arg.tcyr
[ -f "$TP" ] || { echo "FAIL: $G: $TP is missing"; exit 1; }
NP=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TP")
PFLOOR=69
if [ "$NP" -lt "$PFLOOR" ]; then echo "FAIL: $G: only $NP rows in $TP (floor $PFLOOR) — rows were lost"; exit 1; fi

# The filed repro, verbatim (docs/development/issues/2026-10-08-small-struct-local-from-address-is-value-not-handle.md).
cat > "$D/repro.cyr" <<'EOF'
include "lib/alloc.cyr"
struct S8 { v; }
struct H { a; b; }
var h8 = 0;
var h16 = 0;
fn run(): i64 {
    h8 = alloc(8);
    h16 = alloc(16);
    var q: S8 = h8;          # same result with alloc(8) or a `fn gp(): *S8` call
    var hq: H = h16;
    q.v = 5;
    hq.a = 7;
    var f = |d| { q.v = q.v + d; hq.a = hq.a + d; return 0; };
    callptr(f, 10);
    return load64(h8) * 100 + load64(h16);   # heap words behind each local
}
alloc_init();
var r = run();
syscall(60, r % 256);
EOF

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"
XLEGS="x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1"

echo "R0. the filed repro, verbatim (exit 237; 17 = the 8 B local held the address as its value)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/repro.cyr" "$D/r0_$n"
    if [ "$RC" -eq -1 ]; then bad "R0 $leg: did not build: $(grep '^error' "$D/r0_$n.err" | head -1)"
    elif [ "$RC" -eq 237 ]; then ok "R0 $leg: exit 237"
    else bad "R0 $leg: exit $RC, want 237"; fi
done

echo "R1. $TC ($N rows)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "R1 $leg: the values file did not build: $(grep '^error' "$D/t_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "R1 $leg: $LAST"
    else bad "R1 $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

echo "R2. $TG ($NG rows: the handle line for globals)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TG" "$D/g_$n"
    if [ "$RC" -eq -1 ]; then bad "R2 $leg: the values file did not build: $(grep '^error' "$D/g_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NG passed, 0 failed ($NG total)" ]; then ok "R2 $leg: $LAST"
    else bad "R2 $leg: exit $RC, '$LAST' (want '$NG passed, 0 failed ($NG total)') $(grep -m3 'FAIL' "$D/g_$n.out" | tr '\n' ' ')"; fi
done

echo "R3. $TP ($NP rows: a pointer into a by-value struct parameter of 8 B or less)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TP" "$D/pa_$n"
    if [ "$RC" -eq -1 ]; then bad "R3 $leg: the values file did not build: $(grep '^error' "$D/pa_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NP passed, 0 failed ($NP total)" ]; then ok "R3 $leg: $LAST"
    else bad "R3 $leg: exit $RC, '$LAST' (want '$NP passed, 0 failed ($NP total)') $(grep -m3 'FAIL' "$D/pa_$n.out" | tr '\n' ' ')"; fi
done

# The filed repro, verbatim (docs/development/issues/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md).
cat > "$D/repro_b.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S1 { u; }
struct S4 { a: i32; }
fn bs1(b: S1): i64 { return b.u; }
fn bs4(b: S4): i64 { return b.a; }
fn go(): i64 {
    var s: S1; s.u = 5;
    var t: S4; t.a = 6;
    var sp: *S1 = &s;
    var tp: *S4 = &t;
    var r = 0;
    if (bs1(sp) == 5) { r = r + 1; }      # a `*S1` local into `b: S1` (8 B, passed by value)
    if (bs4(tp) == 6) { r = r + 10; }     # a `*S4` local into `b: S4` (4 B)
    if (bs1(&s) == 5) { r = r + 100; }    # `&s` into `b: S1`
    return r;
}
syscall(60, go());
EOF
echo "R4. the filed pointer-argument repro, verbatim (exit 111; 0 = each callee read the pointer's bits)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/repro_b.cyr" "$D/r4_$n"
    if [ "$RC" -eq -1 ]; then bad "R4 $leg: did not build: $(grep '^error' "$D/r4_$n.err" | head -1)"
    elif [ "$RC" -eq 111 ]; then ok "R4 $leg: exit 111"
    else bad "R4 $leg: exit $RC, want 111"; fi
done

# crow <label> <want-exit | refuse:<text>> <program> — an x86 compile (and run) row.
crow() {
    printf '%b' "$3" > "$D/c.cyr"
    if "$CC" < "$D/c.cyr" > "$D/c.bin" 2> "$D/c.err"; then
        case "$2" in
            refuse:*) bad "$1: compiled, want the refusal '${2#refuse:}'"; return ;;
        esac
        chmod +x "$D/c.bin"; rc=0; timeout 60 "$D/c.bin" > /dev/null 2>&1 || rc=$?
        if [ "$rc" = "$2" ]; then ok "$1: exit $rc"; else bad "$1: exit $rc, want $2"; fi
    else
        case "$2" in
            refuse:*) if grep -q "${2#refuse:}" "$D/c.err"; then ok "$1: refused by name"
                      else bad "$1: refused, but not with '${2#refuse:}': $(grep -m1 '^error' "$D/c.err")"; fi ;;
            *) bad "$1: does not compile: $(grep -m1 '^error' "$D/c.err")" ;;
        esac
    fi
}
echo "C. compile rows (x86)"
crow "C1 handle <- handle of another struct type rebinds" 58 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nstruct U8 { u; }\nfn f() { var x = alloc(8); var a: S8 = x; a.v = 5; var u: U8 = alloc(8); u.u = 3; a = u; a.v = 8; return load64(x) * 10 + u.u; }\nalloc_init();\nsyscall(60, f());\n'
crow "C1 its 16 B twin" 58 \
  'include "lib/alloc.cyr"\nstruct H { v; w; }\nstruct UH { u; x; }\nfn f() { var x = alloc(16); var a: H = x; a.v = 5; var u: UH = alloc(16); u.u = 3; a = u; a.v = 8; return load64(x) * 10 + u.u; }\nalloc_init();\nsyscall(60, f());\n'
crow "C2 var q: S8 = mku(1) (a U8 value) refused" "refuse:fn return struct-id differs from declared var type" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn mku(n): U8 { var r: U8; r.u = n; return r; }\nfn f() { var q: S8 = mku(1); return q.v; }\nsyscall(60, f());\n'
crow "C2 q = mku(1) into an S8 handle refused" "refuse:cannot copy 'mku' into a variable of a different struct/vector type: 'q'" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nstruct U8 { u; }\nfn mku(n): U8 { var r: U8; r.u = n; return r; }\nfn f() { var q: S8 = alloc(8); q = mku(1); return q.v; }\nalloc_init();\nsyscall(60, f());\n'
crow "C3 bs1((t)) with t: T1 into p: S1 still compiles (6.7.11 owns it)" 7 \
  'struct S1 { a: i8; }\nstruct T1 { b: i8; }\nfn bs1(p: S1) { return p.a; }\nfn f() { var t: T1; t.b = 7; return bs1((t)); }\nsyscall(60, f());\n'
crow "C4 var q: S8 = *pu (pu: *U8) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn f() { var u: U8; u.u = 4; var pu: *U8 = &u; var q: S8 = *pu; return q.v; }\nsyscall(60, f());\n'
crow "C4 var q: H = *pu (pu: *UH) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn f() { var u: UH; u.u = 4; var pu: *UH = &u; var q: H = *pu; return q.v; }\nsyscall(60, f());\n'
crow "C4 var q: S8 = *GU (GU: *U8) refused" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GU: *U8 = 0;\nfn f() { var u: U8; u.u = 4; GU = &u; var q: S8 = *GU; return q.v; }\nsyscall(60, f());\n'
crow "C5 return (a, 1) with a handle: the element is its word" 3 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn f(): (i64, i64) { var a: S8 = alloc(8); a.v = 3; return (a, 1); }\nalloc_init();\nvar x, y = f();\nsyscall(60, load64(x));\n'
crow "C5 its 16 B twin" 3 \
  'include "lib/alloc.cyr"\nstruct H { v; w; }\nfn f(): (i64, i64) { var a: H = alloc(16); a.v = 3; return (a, 1); }\nalloc_init();\nvar x, y = f();\nsyscall(60, load64(x));\n'
crow "C6 a U8 handle returned from an S8 fn returns its struct" 3 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nstruct U8 { u; }\nfn f(): S8 { var u: U8 = alloc(8); u.u = 3; return u; }\nfn g() { var q: S8 = f(); return q.v; }\nalloc_init();\nsyscall(60, g());\n'

echo "GC. compile rows for globals (x86)"
crow "GC1 var ga: Num = 1 is a handle global: ga + gb is pointer arithmetic, no dispatch" 3 \
  'struct Num { v; }\nfn Num_add(a, b) { return a * 100 + b; }\nvar ga: Num = 1;\nvar gb: Num = 2;\nfn f() { return ga + gb; }\nsyscall(60, f());\n'
crow "GC1 its 16 B twin" 3 \
  'struct V2 { a; b; }\nfn V2_add(a, b) { return 77; }\nvar ga: V2 = 1;\nvar gb: V2 = 2;\nfn f() { return ga + gb; }\nsyscall(60, f());\n'
crow "GC1 a global struct value still dispatches" 102 \
  'struct Num { v; }\nfn Num_add(a, b) { return a * 100 + b; }\nvar ga = Num { 1 };\nvar gb = Num { 2 };\nfn f() { return ga + gb; }\nsyscall(60, f());\n'
crow "GC2 var G: S8 = *GU (GU: *U8) refused in the declaration zone" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nvar GU: *U8 = &GV;\nvar G: S8 = *GU;\nsyscall(60, G.v);\n'
crow "GC2 var G: H = *GU (GU: *UH) refused in the declaration zone" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar GV = UH { 4, 0 };\nvar GU: *UH = &GV;\nvar G: H = *GU;\nsyscall(60, G.v);\n'
crow "GC2 var G: S8 = *GU refused after the first statement" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nvar GU: *U8 = &GV;\nvar k = 0;\nk = 1;\nvar G: S8 = *GU;\nsyscall(60, G.v);\n'
crow "GC3 var G: H = *P with P declared below it refused by name" "refuse:from a global declared below it" \
  'struct H { v; w; }\nvar G: H = *P;\nvar A = H { 4, 0 };\nvar P: *H = &A;\nsyscall(60, G.v);\n'
crow "GC4 a global declared a value and then a handle is refused" "refuse:redeclared with a different type or size" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nvar G = S8 { 1 };\nvar G: S8 = alloc(8);\nsyscall(60, G.v);\n'
crow "GC4 ... a call value and then a handle" "refuse:redeclared with a different type or size" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn mk(n): S8 { var r: S8; r.v = n; return r; }\nvar G: S8 = mk(1);\nvar G: S8 = alloc(8);\nsyscall(60, G.v);\n'
crow "GC4 two handle declarations of one global fold" 6 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nvar G: S8 = alloc(8);\nvar G: S8 = alloc(8);\nfn f() { G.v = 6; return load64(load64(&G)); }\nsyscall(60, f());\n'
crow "GC5 a global bound to a handle declared BELOW it binds (the sweep repeats)" 4 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nvar G2: S8 = G1;\nvar G1: S8 = alloc(8);\nfn f() { G1.v = 1; G2 = G1; G2.v = 4; return G1.v; }\nsyscall(60, f());\n'
crow "GC5 a dispatch on a handle declared below it is pointer arithmetic (the sweep repeats)" 0 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn S8_add(a: S8, b: S8): S8 { var r: S8; r.v = 77; return r; }\nvar G2: S8 = G1 + 8;\nvar G1: S8 = alloc(8);\nsyscall(60, load64(&G2) - 8);\n'

cat > "$D/gp.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
var GA: S7 = 0;
var GZ = S7 { 0, 0, 0 };
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn r7(): S7 { return GA; }
fn S7_add(l: S7, r: S7): S7 { var t: S7; t.a = l.a + r.a; t.b = l.b + r.b; t.c = l.c + r.c; return t; }
fn run(): i64 {
    var p = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (p <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, p + 4096, 4096) != 0) { return 91; }
    GA = p + 4096 - 7;
    GA.a = 100;
    GA.b = 20;
    GA.c = 3;
    if (take7(GA) != 123) { return 1; }
    var q: S7 = r7();
    if (take7(q) != 123) { return 2; }
    var w: S7 = GZ + GA;
    if (take7(w) != 123) { return 3; }
    var v: S7 = if (q.a == 100) { GA } else { GZ };
    if (take7(v) != 123) { return 4; }
    var c: S7;
    c = GA;
    if (take7(c) != 123) { return 5; }
    return 0;
}
var e = run();
if (e == 0) { if (take7(GA) != 123) { e = 6; } }
var t: S7 = GZ + GA;
if (e == 0) { if (take7(t) != 123) { e = 7; } }
syscall(60, e);
EOF
echo "GP. a 7 B handle GLOBAL ending a mapping, in a fn and at top level: no byte past it is read"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/gp.cyr" "$D/gp_$leg"
    if [ "$RC" -eq -1 ]; then bad "GP $leg: did not build: $(grep '^error' "$D/gp_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "GP $leg: exit 0"
    else bad "GP $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

cat > "$D/pp.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn S7_add(l: S7, r: S7): i64 { return take7(l) * 1000 + take7(r); }
fn mk7(): S7 { var t: S7; t.a = 0; t.b = 0; t.c = 0; return t; }
fn pid(p: *S7): *S7 { return p; }
var GP: *S7 = 0;
fn run(): i64 {
    var p = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (p <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, p + 4096, 4096) != 0) { return 91; }
    var x: *S7 = 0;
    x = p + 4096 - 7;
    x.a = 100;
    x.b = 20;
    x.c = 3;
    GP = x;
    if (take7(x) != 123) { return 1; }
    if (take7(pid(x)) != 123) { return 2; }
    if (mk7() + x != 123) { return 3; }
    if (take7(GP) != 123) { return 4; }
    var f = |d| take7(x) + d;
    if (callptr(f, 0) != 123) { return 5; }
    return 0;
}
var e = run();
if (e == 0) { if (take7(GP) != 123) { e = 6; } }
if (e == 0) { if (mk7() + GP != 123) { e = 7; } }
syscall(60, e);
EOF
echo "PP. a *S7 onto the last 7 bytes of a mapping, passed by value, in a fn and at top level: no byte past it is read"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/pp.cyr" "$D/pp_$leg"
    if [ "$RC" -eq -1 ]; then bad "PP $leg: did not build: $(grep '^error' "$D/pp_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "PP $leg: exit 0"
    else bad "PP $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

cat > "$D/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn r7(x): S7 { var h: S7 = x; return h; }
fn S7_add(l: S7, r: S7): S7 { var t: S7; t.a = l.a + r.a; t.b = l.b + r.b; t.c = l.c + r.c; return t; }
fn run(): i64 {
    var p = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (p <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, p + 4096, 4096) != 0) { return 91; }
    var x = p + 4096 - 7;
    var a: S7 = x;
    a.a = 100;
    a.b = 20;
    a.c = 3;
    var s = take7(a);
    if (s != 123) { return 1; }
    var q: S7 = r7(x);
    if (take7(q) != 123) { return 2; }
    var z: S7;
    z.a = 0;
    z.b = 0;
    z.c = 0;
    var w: S7 = z + a;
    if (take7(w) != 123) { return 3; }
    var v: S7 = if (s == 123) { a } else { z };
    if (take7(v) != 123) { return 4; }
    var f = |d| { return take7(a) + d; };
    if (callptr(f, 0) != 123) { return 5; }
    var c: S7;
    c = a;
    if (take7(c) != 123) { return 6; }
    return 0;
}
syscall(60, run());
EOF
echo "P. a 7 B handle ending a mapping: no byte past it is read (Linux x86_64, aarch64)"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/p.cyr" "$D/p_$leg"
    if [ "$RC" -eq -1 ]; then bad "P $leg: did not build: $(grep '^error' "$D/p_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "P $leg: exit 0"
    else bad "P $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

cat > "$D/as.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
struct S8 { v; }
struct T6 { a: i32; b: i16; }
fn take8(s: S8): i64 { return s.v; }
fn take6(s: T6): i64 { return s.a * 10 + s.b; }
fn mk8(n): S8 { var r: S8; r.v = n; return r; }
fn ret8(): S8 { var h: S8 = alloc(8); h.v = 4; return h; }
fn nopark(): i64 { return 0; }
var GX = 0;
var GY = 0;
async fn st(): i64 {
    var a: S8 = GX;
    a.v = 5;
    var s1 = await nopark();
    var q: S8 = a;
    a.v = a.v + take8(a);
    var t: T6 = GY;
    t.a = 7;
    t.b = 0 - 2;
    var s2 = await nopark();
    if (q.v != 10) { return 1; }
    var c: S8 = mk8(3);
    a = c;
    c.v = 0;
    var r: S8 = ret8();
    return take8(a) * 1000 + load64(GX) * 100 + take6(t) + r.v * 10000;
}
fn main(): i64 {
    alloc_init();
    GX = alloc(8);
    GY = alloc(8);
    var C = st();
    var r1 = future_force(C);
    var r2 = future_force(C);
    var r3 = future_force(C);
    if (r3 != 43368) { syscall(60, 10 + r3 % 100); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
echo "AS. an async fn body across two awaits (CYRIUS_ASYNC=1; x86_64)"
for leg in x86:CYRIUS_ASYNC=1; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/as.cyr" "$D/as_$n"
    if [ "$RC" -eq -1 ]; then bad "AS $leg: did not build: $(grep '^error' "$D/as_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "AS $leg: exit 0"
    else bad "AS $leg: exit $RC, want 0"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a struct local or global of 8 B or less from a non-struct-value initialiser is a handle, as over 8 B: the filed repro (R0) and every initialiser / consumer / size row for locals (R1) and globals (R2) on x86_64 / IR / DCE / aarch64 / cx / PE, the compile rows (C, GC), no read past a 7 B object, local or global (P, GP), an async body (AS); a pointer into a by-value struct parameter of 8 B or less passes its struct (R3, the filed repro R4, no read past it: PP)"
