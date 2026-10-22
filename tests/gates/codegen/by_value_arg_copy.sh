#!/bin/sh
# tests/gates/codegen/by_value_arg_copy.sh — 6.7.7 (integration: call arguments)
#
# A BY-VALUE ARGUMENT IS ITS VALUE WHERE IT IS WRITTEN. A parameter the callee copies in its
# prologue (a plain struct over 8 B, a Win64 value-form vector — `_pm_copies`) is passed by ADDRESS,
# and the copy ran after every argument was evaluated, so `rd(b, bump(&b))` read the write `bump`
# made (issue 2026-10-09-struct-arg-sees-later-arg-side-effect); a value-form vector loaded into its
# register after the integer arguments the same. An argument a later argument may write
# (`_span_may_write`) is now copied where it stands (`_sarg_snap`, `_simd_arg_snap`); the runtime
# half — every source, call form and backend — is tests/tcyr/crossos/by_value_arg_evaluation_order.tcyr.
#
#   C  the copy costs nothing where nothing can write: each caller `pN` calls `rd(s: Big, z)` and
#      its twin `qN` calls `rp(s: *Big, z)` — a pointer parameter, never copied — with the same
#      arguments; their sizes (CYRIUS_SYMS) are EQUAL for a later argument that only reads (a name,
#      `n + 1`, a field, `&c`, a string, a comparison, an index, a closure literal, `-n`, `n % 3 << 1`,
#      a struct's integer field in arithmetic, `c.a + 1`)
#   K  ... and `pN` is LARGER — the copy — for one that may write: a call, a call inside an
#      expression, a method call, a builtin store, an operator a struct dispatches (`w + w2`), and
#      one on struct-typed fields (`h.w + h.v` — struct values, though today only a NAME on the left
#      dispatches: the rule does not depend on that); 6.7.17: C12-C14 a typed pointer that reaches no
#      struct value (`*pn + 1`, `pn: *i64`; `pw + 1`, pointer arithmetic; `pq.n + 1`, an integer field), C15
#      `- w` and C16 `*pw` (no BINARY operator: a unary `-` / `*` dispatches nothing; C15 copied before) —
#      and K7-K9 one that does: a dereference (`*pw + 1`), a typed pointer's struct field (`pq.w + 1`)
#      and a `*HW` field's (`o2.p.w + 1`), each dispatching W's operator fn (no copy before 6.7.17).
#      6.7.17 (`_fn_nowrite`): C17-C20 a call to a fn that writes no memory — direct (`idn(n)`), a
#      method (`o.nw(n)`), a generic (`gk<i64>(n)`), the `sizeof` intrinsic — takes no copy (each did
#      before); K10-K15 one that may write does: a global store (`wg`), an operator fn its body runs
#      on a struct parameter (`hop(w)`, `v + 1`), a call to a writer (`hw2`), a writing method
#      (`o.wm`), a writing generic (`gw<i64>`), a recursive helper (`rr`, conservatively); K16 / K17 a
#      helper whose if-expression `if (c) { v } else { w } - 1` (`* 1`) runs S1's operator fn (its `}` read
#      as ending no operand, the `-` / `*` was a unary one: no copy before the review fix)
#   T  objdump: `return rd(G, gbump())` (no `&`, which diverts any tail call) is an ordinary call —
#      its copy is in the frame the `jmp` would free — and `return rd(G, n)` keeps its `jmp`
#   TS the copy costs ONLY its own call the `jmp` (`_tc_snap_div`, never the per-fn
#      `_fn_local_addr`): T3 a copying tail call before a self tail call in one fn — the self call
#      keeps its `jmp`; T4 the two in a loop (the self call a pending site, `_tcp_site`) and T4B
#      the self call first, decided at the loop's end (`_tcp_loop_end`); T5 a closure literal
#      among the copying call's arguments runs its own tail arm, and the call still diverts; TR
#      the probe run 3,000,000 deep (the lane's first cut: SIGSEGV). (6.7.17: `gz` stores to a
#      global, so its call still writes and the copy is still taken)
#   TU A CALL TO A FN THAT WRITES NO MEMORY TAKES NO COPY (6.7.17, `_fn_nowrite`). The 6.7.7 ruling
#      (user, 2026-10-09 — "accept the TCO loss") made a tail call whose by-value argument is copied
#      an ORDINARY call, and every call among the later arguments counted as a write; a per-fn
#      summary wins the copying call's `jmp` back where the callee writes nothing (issue
#      2026-10-09-tail-call-by-value-copy-needs-effect-analysis — the ruling's own expiry). TU1 the
#      reviewer's tco2 shape `return f6(G, n - 1, g6(acc))` is a `jmp` now, beside the later self
#      tail call's (objdump: two `jmp`s, no call — one of each before 6.7.17); TU3 a helper that
#      stores to a global keeps the copy and the call; TU4 a helper defined BELOW the caller, TU5 a
#      method (`G.m6(acc)`), TU6 / TU6B a generic called with and without `<i64>` keep the `jmp`;
#      TU7 a recursive helper is a call (a summary in progress reads as a write: conservative);
#      TU2 every `jmp` form run 3,000,000 deep (the issue's tco2 verbatim among them), the call
#      forms 1,000 deep, each with its value: exit 193
#   AS AS1: CYRIUS_ASYNC=1 — the copy in an `async fn`, whose frame is the coroutine's heap frame
#   A  ANTI-VACUOUS: the crossos tcyr built and run — x86 plain, CYRIUS_IR=3 and CYRIUS_DCE=1, then
#      aarch64 (qemu), cx (cxvm) and PE (wine), each with the full assertion count
#
# MUTATION LEDGER (2026-10-09; each a one-edit scratch COPY of the tree, its cycc rebuilt from the
# mutated src, then this gate — which builds the tcyr's cross compilers from the copy — run there):
#   M1 `_arg_push_snap` never copies (`ty` forced 0)          -> K1-K5, T, T1, AS1; the tcyr's 20
#                                                              argument rows on x86 / aarch64 / cx,
#                                                              23 on PE
#   M2 `_self_snap` returns at once                           -> the tcyr's two `self` rows, every leg
#   M3 `_op_lhs_snap` returns at once                         -> the tcyr's three operator rows
#   M4 `_simd_arg_snap` never called                          -> the tcyr's f64v2-between and f64v4
#                                                              rows on x86 / aarch64 / cx (PE passes
#                                                              its vectors by address: M1's)
#   M5 `_span_may_write` without its struct-operator rule     -> K5; the tcyr's `rw(w, w + w2)`
#   M6 `_span_may_write` always 1                             -> C1-C11, T2
#   M9 `_name_struct_val` ignores the `.field` chain          -> C11 (and crossos/
#                                                              tailcall_struct_ptr_params.tcyr's
#                                                              1,000,000-deep `cntv(G, n - 1, acc +
#                                                              p.c)`: SIGSEGV, its `jmp` lost)
#   M10 `_name_struct_val` answers 0 past a `.field`          -> K6
#   M7 `_sarg_snap`'s top-level arm pushes the source again   -> the tcyr's four top-level rows
#   M8 `_sarg_snap` never sets `_tc_snap_div`                 -> T1, T3, T4, T4B, T5 (the tail arm
#                                                              keeps its `jmp` with the copy in the
#                                                              frame it frees)
#   M11 `_sarg_snap` sets `_fn_local_addr` (the first cut)    -> T3, T4, T4B, TR; the tcyr's three
#                                                              1,000,000-deep rows on every leg
#                                                              (x86 / aarch64 SIGSEGV, cx, PE)
#   M12 the tail arm does not restore `_tc_snap_div`          -> T5 (the closure's arm clears it:
#                                                              `jmp rc` with the copy in the frame)
#   (TU1 is killed by M8 — two `jmp`s, no call — and by M11 — two calls; TU2 by M11: SIGSEGV)
# 6.7.9 (issue 2026-10-09-by-value-copy-mask-62-parameter-limit — the tcyr's rows at parameter 62
# and later, past the 62-bit copies mask; each mutant a scratch tree, this gate run there):
#   M13 `_pm_copies` answers 0 past ordinal 61 (the pre-fix line) -> A1-A6: the tcyr's seven rows
#                                                              at 62+ (11 where 1 is right) and its
#                                                              1,000,000-deep walk (SIGSEGV on x86 /
#                                                              aarch64: the address escaped)
#   M14 pass 1 (`_bvcp_note`, `_tup_bvcp`) records nothing past 61 -> A1-A6: the two rows whose
#                                                              callee is defined after the call
#   M15 pass 2 (`_sptr_params_copy`) records nothing past 61    -> A1-A6: the rows after the
#                                                              definition (62, 66, tail, generic,
#                                                              method) and the walk
#   M16 `_bvcp_note` past 61 skips the address-passed test      -> A1-A6: the 8 B control `rs62`
#                                                              (its value taken for an address)
#   (a definition's copies row replaced whole, and none written for a redefined fn, is
#   fn_redefinition_binds_last.sh's)
# 6.7.17 (the struct-operator rule through a typed pointer; each mutant's cycc built from a scratch src copy, this gate
# run with CYCC= it):
#   M17 `_deref_struct_at` answers 0                            -> K7; the tcyr's `rd(G, *pv + 1)` (11) on x86 /
#                                                              IR3 / DCE / PE
#   M18 `_nsv_ptr_base` answers 0                               -> K8; the tcyr's `rd(G, ph.v + 1)`
#   M19 `_name_struct_val` stops at a `*T` field (the pre-fix line) -> K9; the tcyr's `rd(G, o.p.v + 1)`
#   M20 `_tok_binop_at` answers 1 (a unary `-` / `*` an operator)  -> C15 (a copy for `- w`), K7
# 6.7.17 (the no-write summary, `_fn_nowrite`; the same scratch-src method, this gate's x86 legs run with CYCC=):
#   M21 `_fn_nowrite` answers 1 for every fn                  -> K1, K3, K10-K15, T, T1, T3, T4, T4B, TU3, TU7, AS1;
#                                                              the tcyr's writer rows on x86 / IR3 / DCE
#   M22 `_fn_nowrite` answers 0 (6.7.7's every-call rule)     -> C17-C19, TU1, TU1B, TU4-TU6B, TU2 (SIGSEGV); the
#                                                              tcyr's 1,000,000-deep `nwalk` (SIGSEGV)
#   M23 `_fnw_assign_ok` answers 1 (a store reads as none)    -> K10, K12-K14, T, T1, T3-T4B, TU3; the tcyr's
#                                                              global-store rows and the tail arm `rd(G, gbump())`
#   M24 `_fnw_arith_ok` answers 1 (no operator fn judged)     -> K11; the tcyr's `w_op` / `w_deref` / `w_field` rows
#   M25 a callee's own calls read as writing nothing          -> K3, K12, K15, TU7; the tcyr's `w_wrap` row and its
#                                                              two operator rows (`pbump` calls `bump`)
#   M26 a summary in progress reads as writing nothing        -> K15, TU7 (a recursive helper)
#   M27 `_call_meth_fn` resolves no method                    -> C18, TU5, TU2 (SIGSEGV)
#   M28 `_fnw_gen_name` resolves no generic                   -> C19, TU6, TU2 (SIGSEGV)
#   M29 `_fnw_tok_plain` answers 1 (no token writes)          -> K1, K3, AS1; the tcyr's `bump` rows
#   M30 `_tok_opnd_end` without `}` (the pre-fix line)        -> K16, K17; the tcyr's `w_ife_sub` / `w_ife_mul`
#                                                              rows (11) on x86 / IR3 / DCE / aarch64 / cx / PE
#   (`_fnw_brace_ok` answering 1 kills no row: a struct literal builds in the callee's own frame — the rule is the
#   allow-list's, for a `{` the scan does not read)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: by_value_arg_copy: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: by_value_arg_copy: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# ── C / K: the copy's cost, by size ─────────────────────────────────────────────────────────────
# Each row: <id>@<later argument>@<C = same size | K = larger>. `b` is the Big under test, `c` /
# `w` / `w2` other structs, `n` an i64, `a` an i64 array.
ROWS='C1@n@C
C2@n + 1@C
C3@c.a@C
C4@&c@C
C5@"text"@C
C6@n < 3 && !n@C
C7@a[1]@C
C8@|x, y| x + y@C
C9@- n@C
C10@n % 3 << 1@C
C11@c.a + 1@C
K1@bump(&b)@K
K2@n + bump(&b)@K
K3@o.touch(&b)@K
K4@store64(&b, 5)@K
K5@w + w2@K
K6@h.w + h.v@K
C12@*pn + 1@C
C13@pw + 1@C
C14@pq.n + 1@C
C15@- w@C
C16@*pw@C
C17@idn(n)@C
C18@o.nw(n)@C
C19@gk<i64>(n)@C
C20@sizeof(Big) + n@C
K7@*pw + 1@K
K8@pq.w + 1@K
K9@o2.p.w + 1@K
K10@wg(n)@K
K11@hop(w)@K
K12@hw2(n)@K
K13@o.wm(n)@K
K14@gw<i64>(n)@K
K15@rr(n)@K
K16@ife(1, s1, s1)@K
K17@ifm(1, s1, s1)@K'
{
    printf 'struct Big { a: i64; b: i64; c: i64; }\nstruct W { p: i64; q: i64; r: i64; }\nstruct HW { n: i64; w: W; v: W; }\nstruct OP2 { n: i64; p: *HW; }\n'
    printf 'fn bump(p): i64 { store64(p, load64(p) + 10); return 0; }\n'
    printf 'fn W_add(x: *W, y: *W): i64 { x.p = x.p + 10; return 0; }\n'
    printf 'fn Big_touch(self, p): i64 { return bump(p); }\n'
    printf 'fn rd(s: Big, z): i64 { return s.a; }\nfn rp(s: *Big, z): i64 { return s.a; }\n'
    printf 'var GW = 0;\nfn idn(x): i64 { return x + 1; }\nfn Big_nw(self, x): i64 { return x; }\nfn gk<T>(x: T): i64 { return 7; }\n'
    printf 'fn wg(x): i64 { GW = x; return 0; }\nfn hop(v: W): i64 { return v + 1; }\nfn hw2(x): i64 { return wg(x) + 1; }\n'
    printf 'fn Big_wm(self, x): i64 { GW = x; return 0; }\nfn gw<T>(x: T): i64 { GW = 1; return 0; }\nfn rr(x): i64 { if (x > 100) { return rr(x - 1); } return x; }\n'
    printf 'struct S1 { a: i64; }\nfn S1_sub(x: S1, y): i64 { GW = 1; return 5; }\nfn S1_mul(x: S1, y): i64 { GW = 1; return 6; }\n'
    printf 'fn ife(c, v: S1, w: S1): i64 { return if (c) { v } else { w } - 1; }\nfn ifm(c, v: S1, w: S1): i64 { return if (c) { v } else { w } * 1; }\n'
    echo "$ROWS" | while IFS='@' read -r id arg kind; do
        for f in rd rp; do
            nm=p; [ "$f" = rp ] && nm=q
            printf 'fn %s%s(): i64 {\n    var b: Big = Big { 1, 2, 3 };\n    var c: Big = Big { 4, 5, 6 };\n    var o: Big = Big { 0, 0, 0 };\n    var w: W = W { 1, 2, 3 };\n    var w2: W = W { 0, 0, 0 };\n    var h: HW;\n    h.n = 0;\n    h.w.p = 1;\n    h.v.p = 2;\n    var n = 3;\n    var a: i64[4];\n    a[1] = 7;\n    var pw: *W = &w;\n    var pq: *HW = &h;\n    var pn: *i64 = &n;\n    var o2: OP2;\n    o2.n = 0;\n    o2.p = &h;\n    var s1: S1 = S1 { 1 };\n    var r = %s(b, %s);\n    return r + n + c.a + o.a + w.p + w2.p + h.w.p + a[1];\n}\n' "$nm" "$id" "$f" "$arg"
        done
    done
    printf 'fn zend(): i64 { return 0; }\nsyscall(60, zend());\n'
} > "$T/c.cyr"
rc=0; CYRIUS_SYMS="$T/c.syms" "$CC" < "$T/c.cyr" > "$T/c.bin" 2> "$T/c.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "C/K: the probe did not build: $(grep '^error' "$T/c.err" | head -1)"
else
    sort "$T/c.syms" > "$T/c.sorted"
    # A fn's size: the next symbol's address less its own (both hex; POSIX awk has no strtonum).
    size_of() {
        _se=$(awk -v n="$1" 'f { print a " " $1; exit } $2 == n { a = $1; f = 1 }' "$T/c.sorted")
        [ -n "$_se" ] || return 0
        echo $(( 0x${_se#* } - 0x${_se% *} ))
    }
    echo "$ROWS" | while IFS='@' read -r id arg kind; do
        sp=$(size_of "p$id"); sq=$(size_of "q$id")
        if [ -z "$sp" ] || [ -z "$sq" ]; then echo "  FAIL $id: the symbol map does not size p$id / q$id"; continue; fi
        if [ "$kind" = C ]; then
            [ "$sp" -eq "$sq" ] && echo "  ok   $id: rd(b, $arg) adds no copy ($sp B, as rp's)" || echo "  FAIL $id: rd(b, $arg) is $sp B, rp(b, $arg) $sq B — a copy where nothing writes"
        else
            [ "$sp" -gt "$sq" ] && echo "  ok   $id: rd(b, $arg) copies b where it stands ($sp B > rp's $sq B)" || echo "  FAIL $id: rd(b, $arg) is $sp B, rp(b, $arg) $sq B — no copy before a later argument that writes"
        fi
    done > "$T/c.out"
    cat "$T/c.out"
    nf=$(grep -c '^  FAIL' "$T/c.out" || true); fails=$((fails + nf))
    nr=$(grep -c '^  ok' "$T/c.out" || true)
    [ $((nr + nf)) -eq 37 ] || bad "C/K: $((nr + nf)) rows judged, want 37"
fi

# ── T: the tail form (objdump) ──────────────────────────────────────────────────────────────────
printf 'struct Big { a: i64; b: i64; c: i64; }\nvar G: Big = Big { 1, 2, 3 };\nfn gbump(): i64 { G.a = G.a + 10; return 0; }\nfn rd(s: Big, z): i64 { return s.a + z; }\nfn t1(): i64 { return rd(G, gbump()); }\nfn t2(n): i64 { return rd(G, n); }\nfn tend(): i64 { return 0; }\nsyscall(60, t1() * 10 + t2(4) + tend());\n' > "$T/t.cyr"
rc=0; CYRIUS_SYMS="$T/t.syms" "$CC" < "$T/t.cyr" > "$T/t.bin" 2> "$T/t.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "T: the probe did not build: $(grep '^error' "$T/t.err" | head -1)"
else
    chmod +x "$T/t.bin"; got=0; timeout 10 "$T/t.bin" || got=$?
    [ "$got" -eq 25 ] && ok "T: t1() reads G.a = 1 (its copy), then t2(4) reads 11 + 4: exit 25" || bad "T: exit $got, want 25"
    if command -v objdump > /dev/null 2>&1; then
        r=$(awk '$2 == "rd" { print $1 }' "$T/t.syms"); a=$(awk '$2 == "t1" { print $1 }' "$T/t.syms")
        b=$(awk '$2 == "t2" { print $1 }' "$T/t.syms"); e=$(awk '$2 == "tend" { print $1 }' "$T/t.syms")
        if [ -z "$r" ] || [ -z "$a" ] || [ -z "$b" ] || [ -z "$e" ]; then bad "T: the symbol map does not name rd / t1 / t2 / tend"
        else
            rs=$(printf '%x' "0x$r")
            nc=$(objdump -d --start-address=0x"$a" --stop-address=0x"$b" "$T/t.bin" | grep -cE "call +0x$rs\b" || true)
            nj=$(objdump -d --start-address=0x"$a" --stop-address=0x"$b" "$T/t.bin" | grep -cE "jmp +0x$rs\b" || true)
            if [ "$nc" -eq 1 ] && [ "$nj" -eq 0 ]; then ok "T1: return rd(G, gbump()) is a call (its copy lives in the frame)"
            else bad "T1: t1 has $nc call(s) and $nj jmp(s) to rd, want 1 and 0"; fi
            nj2=$(objdump -d --start-address=0x"$b" --stop-address=0x"$e" "$T/t.bin" | grep -cE "jmp +0x$rs\b" || true)
            [ "$nj2" -eq 1 ] && ok "T2: return rd(G, n) keeps its jmp (nothing to copy)" || bad "T2: t2 has $nj2 jmp(s) to rd, want 1"
        fi
    else echo "  SKIP T1/T2: no objdump"; skips=$((skips + 1)); fi
fi

# ── TS: the copy costs only its own call the `jmp` ──────────────────────────────────────────────
printf 'struct Big { a: i64; b: i64; c: i64; }\nvar G: Big = Big { 1, 2, 3 };\nvar GZ = 0;\nfn gz(): i64 { GZ = 0; return 0; }\nfn idf(x): i64 { return x; }\nfn rdz(s: Big, z): i64 { return s.a + z; }\nfn rc(s: Big, cb): i64 { return s.a; }\nfn t3(n, acc): i64 {\n    if (n == 0) { return rdz(G, acc + gz()); }\n    return t3(n - 1, acc + 1);\n}\nfn t4(n, acc): i64 {\n    while (n >= 0) {\n        if (n == 0) { return rdz(G, acc + gz()); }\n        return t4(n - 1, acc + 1);\n    }\n    return 0;\n}\nfn t4b(n, acc): i64 {\n    while (n >= 0) {\n        if (n > 0) { return t4b(n - 1, acc + 1); }\n        return rdz(G, acc + gz());\n    }\n    return 0;\n}\nfn t5(): i64 { return rc(G, |x| { return idf(x); }); }\nfn tend(): i64 { return 0; }\nsyscall(60, (t3(3000000, 0) - 3000001) + (t4(3000000, 0) - 3000001) + (t4b(3000000, 0) - 3000001) + (t5() - 1) + tend());\n' > "$T/ts.cyr"
rc=0; CYRIUS_SYMS="$T/ts.syms" "$CC" < "$T/ts.cyr" > "$T/ts.bin" 2> "$T/ts.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "TS: the probe did not build: $(grep '^error' "$T/ts.err" | head -1)"
else
    chmod +x "$T/ts.bin"; got=0; timeout 20 "$T/ts.bin" || got=$?
    [ "$got" -eq 0 ] && ok "TR: t3 / t4 / t4b run 3,000,000 deep beside their copying tail call: exit 0" || bad "TR: exit $got, want 0 (139: a self tail call lost its jmp)"
    if command -v objdump > /dev/null 2>&1; then
        sort "$T/ts.syms" > "$T/ts.sorted"
        # ts_n <op> <from fn> <to fn (exclusive)> <target fn>: how many <op>s in [from, to) reach target
        ts_n() {
            _a=$(awk -v n="$2" '$2 == n { print $1 }' "$T/ts.sorted"); _e=$(awk -v n="$3" '$2 == n { print $1 }' "$T/ts.sorted")
            _r=$(awk -v n="$4" '$2 == n { print $1 }' "$T/ts.sorted")
            if [ -z "$_a" ] || [ -z "$_e" ] || [ -z "$_r" ]; then echo x; return 0; fi
            objdump -d --start-address=0x"$_a" --stop-address=0x"$_e" "$T/ts.bin" | grep -cE "$1 +0x$(printf '%x' "0x$_r")\b" || true
        }
        # A diverted pending site keeps its dead tail sequence (the `jmp`) beside its stub's call:
        # the self CALL is the count that tells.
        for r in "T3 t3 t4 the self call keeps its jmp" "T4 t4 t4b in a loop, the pending self call keeps its jmp" \
                 "T4B t4b t5 in a loop, the self call first, decided at the loop's end, keeps its jmp"; do
            set -- $r; id=$1; f=$2; nx=$3; shift 3
            nj=$(ts_n jmp "$f" "$nx" "$f"); nsc=$(ts_n call "$f" "$nx" "$f"); nc=$(ts_n call "$f" "$nx" rdz)
            if [ "$nj" = 1 ] && [ "$nsc" = 0 ] && [ "$nc" = 1 ]; then ok "$id: $f calls rdz (its copy); $*"
            else bad "$id: $f has $nj jmp(s) and $nsc call(s) to itself and $nc call(s) to rdz, want 1, 0 and 1"; fi
        done
        # t5's range runs to tend: the closure body is emitted inline (its own symbol sits inside)
        nc=$(ts_n call t5 tend rc); nj=$(ts_n jmp t5 tend rc)
        [ "$nc" = 1 ] && [ "$nj" = 0 ] && ok "T5: a closure's own tail arm among the arguments: t5 still calls rc" || bad "T5: t5 has $nc call(s) and $nj jmp(s) to rc, want 1 and 0"
    else echo "  SKIP T3-T5: no objdump"; skips=$((skips + 1)); fi
fi

# ── TU: a call that writes no memory takes no copy (6.7.17) — the copying tail call keeps its jmp ──
cat > "$T/tu.cyr" <<'TUEOF'
struct Big { a: i64; b: i64; c: i64; }
var G: Big = Big { 1, 2, 3 };
var GW = 0;
fn g6(x): i64 { return x + 1; }
fn w6(x): i64 { GW = x; return x + 1; }
fn r6(x): i64 { if (x > 1000000000) { return r6(x - 1); } return x + 1; }
fn Big_m6(self, x): i64 { return x + 1; }
fn gg6<T>(t: T, k): i64 { return k + 1; }
fn f6(s: Big, n, acc): i64 {
    if (n == 0) { return acc + s.a; }
    if (n < 3) { return f6(G, n - 1, g6(acc)); }
    return f6(G, n - 1, acc + 1);
}
fn f7(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f7(G, n - 1, w6(acc)); }
fn f8(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f8(G, n - 1, b6(acc)); }
fn f9(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f9(G, n - 1, G.m6(acc)); }
fn f10(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f10(G, n - 1, gg6<i64>(0, acc)); }
fn f11(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f11(G, n - 1, gg6(0, acc)); }
fn f12(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f12(G, n - 1, r6(acc)); }
fn b6(x): i64 { return x + 1; }
fn g(x): i64 { return x + 1; }
fn f(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f(G, n - 1, g(acc)); }
fn uend(): i64 { return 0; }
fn uchk(): i64 {
    var e = 0;
    if (f7(G, 1000, 0) != 1001) { e = e + 1; }
    if (f8(G, 3000000, 0) != 3000001) { e = e + 2; }
    if (f9(G, 3000000, 0) != 3000001) { e = e + 4; }
    if (f10(G, 3000000, 0) != 3000001) { e = e + 8; }
    if (f11(G, 3000000, 0) != 3000001) { e = e + 16; }
    if (f12(G, 1000, 0) != 1001) { e = e + 32; }
    if (f(G, 3000000, 0) != 3000001) { e = e + 64; }
    return e;
}
syscall(60, (f6(G, 3000000, 0) & 255) + uchk() + uend());
TUEOF
rc=0; CYRIUS_SYMS="$T/tu.syms" "$CC" < "$T/tu.cyr" > "$T/tu.bin" 2> "$T/tu.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "TU: the probe did not build: $(grep '^error' "$T/tu.err" | head -1)"
else
    chmod +x "$T/tu.bin"; got=0; timeout 30 "$T/tu.bin" || got=$?
    [ "$got" -eq 193 ] && ok "TU2: f6 / f / f8-f11 run 3,000,000 deep (f7 / f12 1,000), every value right: exit 193" || bad "TU2: exit $got, want 193 (139: a tail call lost its jmp; 194..: a walk's value is wrong)"
    if command -v objdump > /dev/null 2>&1; then
        sort "$T/tu.syms" > "$T/tu.sorted"
        # tu_n <op> <fn>: how many <op>s to <fn> itself in [fn, the next symbol)
        tu_n() {
            _se=$(awk -v n="$2" 'f { print $1; exit } $2 == n { a = $1; f = 1 } END { }' "$T/tu.sorted")
            _a=$(awk -v n="$2" '$2 == n { print $1 }' "$T/tu.sorted")
            if [ -z "$_a" ] || [ -z "$_se" ]; then echo x; return 0; fi
            objdump -d --start-address=0x"$_a" --stop-address=0x"$_se" "$T/tu.bin" | grep -cE "$1 +0x$(printf '%x' "0x$_a")\b" || true
        }
        tu_row() {   # <id> <fn> <jmps> <calls> <what>
            _id=$1; _f=$2; _wj=$3; _wc=$4; shift 4
            _nj=$(tu_n jmp "$_f"); _nc=$(tu_n call "$_f")
            if [ "$_nj" = "$_wj" ] && [ "$_nc" = "$_wc" ]; then ok "$_id: $*"
            else bad "$_id: $_f has $_nj jmp(s) and $_nc call(s) to itself, want $_wj and $_wc ($*)"; fi
        }
        tu_row TU1 f6 2 0 "return f6(G, n - 1, g6(acc)) is a jmp (g6 writes nothing: no copy), as the later self tail call"
        tu_row TU1B f 1 0 "the issue's tco2 verbatim: return f(G, n - 1, g(acc)) is a jmp"
        tu_row TU3 f7 0 1 "a helper that stores to a global (w6) keeps the copy and the call"
        tu_row TU4 f8 1 0 "a helper defined below the caller (b6) writes nothing: a jmp"
        tu_row TU5 f9 1 0 "a method that writes nothing (G.m6(acc)): a jmp"
        tu_row TU6 f10 1 0 "a generic that writes nothing, gg6<i64>(0, acc): a jmp"
        tu_row TU6B f11 1 0 "... called without its type argument, gg6(0, acc): a jmp"
        tu_row TU7 f12 0 1 "a recursive helper (r6) reads as a writer: the copy and the call"
    else echo "  SKIP TU1-TU7: no objdump"; skips=$((skips + 1)); fi
fi

# ── AS: an `async fn`'s frame ───────────────────────────────────────────────────────────────────
if [ -f "$ROOT/lib/async.cyr" ]; then
    printf 'include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/async.cyr"\nstruct Big { a: i64; b: i64; c: i64; }\nfn bump(p): i64 { store64(p, load64(p) + 10); return 0; }\nfn rd(s: Big, z): i64 { return s.a; }\nasync fn job(x): i64 { return x; }\nasync fn outer(x): i64 {\n    var b: Big = Big { 1, 2, 3 };\n    var u = await job(x);\n    var r = rd(b, bump(&b));\n    var v = await job(r);\n    return u * 100 + v * 10 + b.a;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = outer(1);\n    var r = 0;\n    var n = 0;\n    while (n < 4) { r = future_force(C); n = n + 1; }\n    if (r != 121) { return r & 255; }\n    return 0;\n}\nvar rr = main();\nsyscall(60, rr);\n' > "$T/as1.cyr"
    rc=0; CYRIUS_ASYNC=1 "$CC" < "$T/as1.cyr" > "$T/as1.bin" 2> "$T/as1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "AS1: rc $rc: $(grep '^error' "$T/as1.err" | head -1)"
    else chmod +x "$T/as1.bin"; got=0; timeout 10 "$T/as1.bin" || got=$?
        [ "$got" -eq 0 ] && ok "AS1: CYRIUS_ASYNC=1: rd(b, bump(&b)) in an async fn across awaits reads 1" || bad "AS1: exit $got (121 & 255 = 0 is right; 221 & 255 = 221 reads the write)"; fi
else echo "  SKIP AS1: no lib/async.cyr"; skips=$((skips + 1)); fi

# ── A: the crossos tcyr on every leg ────────────────────────────────────────────────────────────
TC="$ROOT/tests/tcyr/crossos/by_value_arg_evaluation_order.tcyr"
[ -f "$TC" ] || { bad "A: $TC is missing"; echo "FAIL by_value_arg_copy ($fails)"; exit 1; }
WANT=$(grep -c '^ *assert_eq(' "$TC")
[ "$WANT" -ge 25 ] || bad "A: only $WANT assertions counted in the tcyr (floor 25)"
tcyr_ok() {   # <label> <output> <exit> [<count>]
    n=${4:-$WANT}
    if [ "$3" -eq 0 ] && grep -q "^$n passed, 0 failed ($n total)" "$2"; then ok "$1: $n passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | head -3 | tr '\n' ' ')"; fi
}
for mode in plain IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="A1: x86" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="A2: x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="A3: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$TC" > "$T/tc_$mode" 2> "$T/tc_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/tc_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/tc_$mode"; got=0; timeout 60 "$T/tc_$mode" > "$T/tc_$mode.out" 2>&1 || got=$?
    tcyr_ok "$lbl" "$T/tc_$mode.out" "$got"
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < "$ROOT/src/main_aarch64.cyr" > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        if "$T/cc_a64" < "$TC" > "$T/tc.a" 2> "$T/tc.aerr"; then
            chmod +x "$T/tc.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./tc.a > "$T/tc.aout" 2>&1) || got=$?
            tcyr_ok "A4: aarch64 (qemu)" "$T/tc.aout" "$got"
        else bad "A4: aarch64: the tcyr did not compile: $(grep '^error' "$T/tc.aerr" | head -1)"; fi
    else bad "A4: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A4: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < "$ROOT/src/main_cx.cyr" > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < "$ROOT/programs/cxvm.cyr" > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$TC" > "$T/tc.cyx" 2> "$T/tc.cxerr" && [ -s "$T/tc.cyx" ]; then
        got=0; timeout 300 "$T/cxvm" < "$T/tc.cyx" > "$T/tc.cxout" 2>&1 || got=$?   # 6.7.17: ~50 s of CPU (its walks), 300 under a parallel check.sh
        tcyr_ok "A5: cx (cxvm)" "$T/tc.cxout" "$got"
    else bad "A5: cx: the tcyr did not compile: $(grep '^error' "$T/tc.cxerr" | head -1)"; fi
else bad "A5: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/tc.exe" 2> "$T/tc.werr" && [ -s "$T/tc.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./tc.exe > "$T/tc.wout" 2>/dev/null) || got=$?
        tcyr_ok "A6: PE (wine)" "$T/tc.wout" "$got"
    else bad "A6: PE: the tcyr did not compile: $(grep '^error' "$T/tc.werr" | head -1)"; fi
else echo "  SKIP A6: PE leg — wine not installed"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL by_value_arg_copy ($fails failed, $skips skipped)"; exit 1; fi
echo "PASS by_value_arg_copy ($skips skipped)"
