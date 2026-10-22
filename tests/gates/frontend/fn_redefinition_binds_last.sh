#!/bin/sh
# fn_redefinition_binds_last.sh — 6.6.20: a redefined fn binds EVERY call to its LAST definition,
# as the `duplicate fn ... (last definition wins ...)` warning has always said, on x86_64,
# aarch64, cx and PE.
#
# ⛔ THE DEFECT (backlog since the 6.6.19 R2/R3 work, promoted into 6.6.20). A call to a fn that is
# ALREADY defined is emitted against the entry it has at that moment — ECALLTO bakes the offset,
# at fifteen frontend sites — while forward calls, tail calls and `&fn` go through fixups that
# resolve to the final entry. So, in ONE file:
#     fn g(): i64 { return 2; }
#     fn h(): i64 { var x = g(); return x; }
#     fn g(): i64 { return 1; }               -> warning: duplicate fn 'g' (last definition wins ...)
#     fn main(): i64 { return h(); }          -> exit 2, and "note: 1 unreachable fns" (the WINNER)
# With h2 = `return g();` and h3 = `return g() + 0;` beside it, h*100 + h2*10 + h3 was 212 on
# x86_64, qemu-aarch64 and cxvm: the tail call bound the last g, the other two the first. The
# backlog bullet guessed the trigger was "specific to that build" (a stub defined after
# `include "lib/ws_server.cyr"` got no calls from ws_server_handshake); it is every build.
#
# ⭐ THE FIX (src/frontend/parse_fn_def.cyr `_fn_redirect`, the per-backend EFNREDIRECT): when a
# redefinition's body starts, the EARLIER entry becomes a jump to it — `jmp rel32` (x86_64 ELF /
# Mach-O / PE), `b imm26` (aarch64 ELF / Mach-O), opcode 80 (cx) — so every reference already
# compiled against it follows, whatever its shape; a third definition chains. An `async fn`'s
# Future constructor takes the same road (`_async_ctor_entry`). The jump sits in no fn's range,
# so the dead-code pass takes it as a root and keeps the winning body; its rel32 is registered
# ONCE for whole-program compaction — a `#naked` body opens with the defer-init jump, which has
# already registered those very bytes, and compaction repairs every registry entry independently,
# so a second entry shifted the displacement twice. Two call shapes never reach an entry, and read
# pass 1's new fn flag 2048 (a later definition exists) instead: the INLINE REPLAY of an #inline
# (or a generic base) body is refused for a redefined fn, and a generic instance is minted from
# the LAST definition's tokens (pass 2 no longer overwrites pass 1's def-start for a
# redefinition). Programs with no redefinition are byte-identical (the code runs only for one).
# Because every call now reaches the last body, a redefinition must be CALLED the same way as the
# one it replaces: like the v6.5.37 arity error, a different return type, multi-value count,
# variadic-ness, parameter mask (vector / struct / Str / cstring / Result / Option / Tagged),
# parameter kind past the masks' width (the overflow row), struct type of an address-passed
# struct parameter, or vector type (Win64 passes every vector under the struct mask) is refused
# (`_dsg_check`), and so is `async fn` against a plain fn, in pass 1 (`_dsg_async_check`).
#
# ROWS (compilers are BUILT FROM THIS TREE into a private dir; build/cycc_* is never read)
#   PT0-PT11 (6.7.16, every backend): a redefined fn's `: *T` return records are its LAST definition's — see `_ptlegs`;
#   BX1-BX8 (6.7.16, x86_64; the .tcyr runs three on every backend): and its bool return / parameter facts — row 1c.
#   1. x86_64: the filed repro exits 1 (was 2) and reports no unreachable fn (the winner was);
#      the three-shape repro exits 111 (was 212); tests/tcyr/crossos/fn_redefinition_last_wins.tcyr
#      exits 0 (25 shapes: forward, direct, tail, expression, &fn, top level, three definitions,
#      recursion, #inline, generic instance + base, struct return, a struct parameter passed by
#      address, multi-value return, methods, a library helper replaced after the library, and a
#      by-value struct parameter redefined as `*T` and the reverse — the per-fn record of which
#      parameters a callee copies, which decides whether a later tail call keeps its `jmp`, is the
#      LAST definition's — and, 6.7.9, the same pair at parameter 62, past the copies mask); under
#      CYRIUS_DCE=1 a dead fn between the earlier entry and the winner is ELIMINATED and the
#      redirect still lands (exits 1); the same for `#naked` definitions under CYRIUS_DCE=1 (was
#      139) and, with live store-heavy fns between them, under CYRIUS_IR=3 (was 60).
#   1b. a redefinition that disagrees about how it is CALLED is an ERROR naming what differs:
#      return type (scalar vs struct, a multi-value count), a struct parameter, variadic, another
#      struct type at the same parameter (it ran: B's body copied 64 bytes out of a 24-byte A), a
#      `Str` at ordinal 63 (the overflow row only), f64v2 against f64v4 and an f64v2 against a
#      16-byte struct under CYRIUS_TARGET_WIN=1 (compile only), and `async fn` against plain in
#      both orders under CYRIUS_ASYNC=1 (async-then-plain SIGSEGV'd; plain-then-async bound the
#      first body with no warning). ANTI-VACUOUS: the same convention spelled differently (`: i64`
#      vs unannotated), the same struct type, the same row kind and the same vector type (also
#      compiled for PE) still compile and bind the last; and an async fn redefined as a coroutine
#      binds the LAST constructor (77; was 139 — the first built a plain Future round the
#      coroutine's body).
#   2. aarch64 under qemu-aarch64 (src/main_aarch64.cyr): both repros and the .tcyr.
#   3. cx under cxvm (src/main_cx.cyr, programs/cxvm.cyr): both repros and the .tcyr. The release
#      gate's cross-OS leg never runs cx; this row is cx's only coverage.
#   4. PE under wine, in a PRIVATE prefix (CYRIUS_TARGET_WIN=1): both repros and the .tcyr.
#   Rows 2 and 4 SKIP (the gate then exits 77, never PASS) when qemu-aarch64 / wine is absent.
#   Mach-O (x86_64 and arm64) runs the .tcyr on ecb / ach through the release gate's crossos leg.
#
# MUTATION LEDGER (measured 6.6.20: each mutant ONE edit to the tree, this gate run against it,
# so every compiler is rebuilt from the mutated source; 32 rows):
#   a. the `_fn_redirect(...)` call removed from PARSE_FN_DEF       -> 20 red: the repros 2 / 212
#        on x86, aarch64, cx and PE, the .tcyr on each (12 of its 23 assertions), the
#        unreachable-fn note, the three DCE / IR=3 rows (2), and the four same-signature rows
#        (sig_same 1, sig_same_struct 11, sig_same_row 2, sig_same_vec 2 — each binds the FIRST
#        definition)
#   b. `_wpjs_add` dropped from x86 EFNREDIRECT                      -> 1 red: x86_dce (139 —
#        elimination moved the winner and left the jump's rel32 stale)
#   b2. EFNREDIRECT's registry scan dropped (register twice)        -> 2 red: x86_naked_dce (139)
#        and x86_naked_ir3 (60) — the naked body's own jump had registered the same rel32
#   c. the pass-1 flag (2048) never set                              -> 7 red: the .tcyr on every
#        backend (its #inline row and three generic rows), sig_vector_pe and
#        sig_vector_struct_pe (vector types are recorded for flag 2048 only), and sig_same_vec
#        (a SIMD-parameter fn is inline-replayed from the first body)
#   d. the inline refusal dropped                                    -> 5 red: the .tcyr on every
#        backend (the #inline row and the generic-base row — a generic base is replayed too)
#        and sig_same_vec
#   e. pass 2's def-start write no longer skipped for a redefinition -> 4 red: the .tcyr on every
#        backend (its two generic-instance rows)
#   f. the `_dsg_check(...)` call removed                            -> 8 red: every row 1b refusal
#        but the async pair compiles (and the return-type pair, run, SIGSEGVs)
#   g. `_dsg_rs_norm` without the unannotated == `: i64` rule        -> 1 red: sig_same refused
#   h. `_dsg_ord_differs` not consulted                              -> 4 red: sig_struct_type,
#        sig_overflow_row, sig_vector_pe, sig_vector_struct_pe; dropping only its struct-id /
#        overflow-kind / vector-type comparison -> 1 red each (the first three, in that order)
#   i. the `_dsg_def_reset(...)` call removed                        -> 1 red: sig_vector_struct_pe
#        (pass 1 left the struct's id under the vector's definition; both sides read the same)
#   j. the `_dsg_async_check(...)` call removed                      -> 2 red: the async pair
#   k. `_async_ctor_entry` without its `_fn_redirect`                -> 1 red: async_ctor (139)
#   l. `_sptr_params_localize` writing the copy record for a redefined fn (the s-ret x s-redef
#        integration, measured on the merged tree)                 -> 4 red: the .tcyr on every
#        backend (rd_kv_check 501, want 32: the tail call kept its `jmp` while the `*T` body held
#        the caller's `&s`; rd_kp_check 72, want 71: an over-divert)
#   pre-fix tree (src/ of the 6.6.20 slot open, e696746d)            -> 31 red, 1 green (the green
#        is sig_same_vec_pe, a compile-only anti-vacuous row)
#   6.7.9 (issue 2026-10-09-by-value-copy-mask-62-parameter-limit — the copies row past ordinal 61;
#   each mutant a scratch tree whose cycc is rebuilt from it, this gate run there):
#   m. `_prescan_params` without its `_bvhi_reset` (pass 1 keeps the first definition's row)
#                                                                    -> 4 red: the .tcyr on every
#        backend (rd_kv62_check 501, want 32)
#   n. `_sptr_params_localize` writing the copies row for a redefined fn
#                                                                    -> 4 red: the .tcyr on every
#        backend (rd_kv62_check 501; rd_kp62_check 72, want 71)
#   o. `_pm_copies` answering 0 past ordinal 61 (the pre-fix line), or pass 1 (`_bvcp_note`)
#        recording nothing there                                     -> 4 red: the .tcyr on every
#        backend (rd_kp62_check 72: an over-divert)
#   6.7.16 (issues/2026-10-19-duplicate-fn-later-non-pointer-return-keeps-first-star-t-records.md, the s16 lane; the same
#   procedure, 2026-10-20; 84 rows):
#   p. `_ret_ptr_owns` answering 1 for every definition (pass 2 records an earlier definition's `*T`)
#                                                                    -> 32 red: PT0 PT2 PT4 PT7 PT8 (124), PT9 PT10
#        (compiled through the first's `*H`) and the .tcyr (rd_p_mid, rd_p_after, rd_pu_after) on every backend
#   q. `_ret_redef_reset` a no-op (pass 1 keeps the first definition's records)
#                                                                    -> 36 red: as p, and PT3 / rd_p_above (the call
#        above both definitions)
#   (the bool facts, row 1c; 92 rows)
#   r. `_bx_fn_reset` without its earlier-definition arm (= the tree before) -> 9 red: BX1-BX5 (refused / accepted against
#        the earlier definition) and the .tcyr on every backend (rd_bl_mid, rd_bp_mid, rd_br refused)
#   s. `_bx_cur_bits` reading the fn's word only -> 9 red: BX1 BX5 BX6-BX8 (an earlier body checked against the last
#        definition's return) and the .tcyr on every backend
#   t. `_bx_param` recording an earlier definition's kinds -> 6 red: BX3 BX4 and the .tcyr on every backend
#   u. PARSE_FN_DEF not putting `_bx_ldef_fi` / `_bx_ldef_bits` back -> 4 red: BX2 BX6 BX7 BX8 (two errors: the
#        last definition's body checked against the earlier one's return)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=fn_redefinition_binds_last
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $T — never the user's
# ~/.wine or ~/.cache. The EXIT teardown stops THIS prefix's wineserver and removes its server dir
# (/tmp/.wine-<uid>/server-<dev>-<ino>), which `wineserver -k` leaves behind. CHANGELOG [6.6.17]
WP="$T/wp"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null
TCYR=tests/tcyr/crossos/fn_redefinition_last_wins.tcyr
[ -f "$TCYR" ] || { echo "FAIL $G: missing $TCYR"; exit 1; }

"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" && [ -s "$T/x86" ] \
  || { echo "FAIL $G: could not build src/main.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
fail=0
pass=0
skips=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# The filed repro, verbatim, and the three call shapes side by side.
cat > "$T/repro.cyr" <<'EOF'
fn g(): i64 { return 2; }
fn h(): i64 { var x = g(); return x; }
fn g(): i64 { return 1; }
fn main(): i64 { return h(); }
var r = main(); syscall(60, r);
EOF
cat > "$T/shapes.cyr" <<'EOF'
fn g(): i64 { return 2; }
fn h(): i64 { var x = g(); return x; }
fn h2(): i64 { return g(); }
fn h3(): i64 { return g() + 0; }
fn g(): i64 { return 1; }
fn main(): i64 { return h() * 100 + h2() * 10 + h3(); }
var r = main(); syscall(60, r);
EOF
# Dead code between the earlier entry and the winner: elimination moves the winner, so the
# redirect's rel32 must be repaired with every other jump.
cat > "$T/dce.cyr" <<'EOF'
fn g(): i64 { return 2; }
fn h(): i64 { var x = g(); return x; }
fn dead1(a, b): i64 { var s = 0; var i = 0; while (i < a) { s = s + i * b; i = i + 1; } return s; }
fn dead2(a): i64 { if (a > 3) { return dead1(a, 2) + 7; } return dead1(a, 3) - 1; }
fn g(): i64 { return 1; }
var r = h(); syscall(60, r);
EOF
# The same with `#naked` definitions. A naked body OPENS with the defer-init jump, whose rel32 is
# already in the whole-program jump registry at the very bytes the redirect rewrites; registered a
# second time, compaction repaired it twice (SIGSEGV under CYRIUS_DCE=1; 60, not 1, under
# CYRIUS_IR=3 with live store-heavy fns between the definitions).
cat > "$T/naked_dce.cyr" <<'EOF'
#naked
fn g(): i64 { asm { 0xB8; 0x02; 0x00; 0x00; 0x00; 0xC3; } }
fn d1(): i64 { var a = 1; var b = 2; var c = a + b; return c * 7 + 3; }
fn d2(): i64 { var a = 4; var b = 5; var c = a * b; return c - 9; }
fn h(): i64 { var x = g(); return x; }
#naked
fn g(): i64 { asm { 0xB8; 0x01; 0x00; 0x00; 0x00; 0xC3; } }
syscall(60, h());
EOF
cat > "$T/naked_ir3.cyr" <<'EOF'
var gs[64];
#naked
fn g(): i64 { asm { 0xB8; 0x02; 0x00; 0x00; 0x00; 0xC3; } }
fn s1(): i64 { var a = 1; a = 2; a = 3; var b = a; b = 4; b = 5; store64(&gs, a + b); return a + b; }
fn s2(): i64 { var a = 1; a = 2; a = 3; var b = a; b = 4; b = 5; store64(&gs + 8, a * b); return a * b; }
fn s3(): i64 { var a = 1; a = 2; a = 3; var b = a; b = 4; b = 5; store64(&gs + 16, a - b); return a - b; }
fn h(): i64 { var x = g(); return x + s1() * 0 + s2() * 0 + s3() * 0; }
#naked
fn g(): i64 { asm { 0xB8; 0x01; 0x00; 0x00; 0x00; 0xC3; } }
syscall(60, h());
EOF

# _leg <label> <compile-cmd> <run-cmd> <source> : compile with "$2" < source, run with "$3"
# (empty = native). Sets BRC (compile rc), BSZ (output size) and LRC (run rc; -1 = not run).
_leg() {
    LRC=-1
    BRC=0; $2 < "$4" > "$T/$1.bin" 2> "$T/$1.err" || BRC=$?
    BSZ=$(wc -c < "$T/$1.bin" | tr -d ' ')
    if [ "$BRC" -ne 0 ] || [ "${BSZ:-0}" -le 64 ]; then return 0; fi
    chmod +x "$T/$1.bin"
    LRC=0
    if [ -n "$3" ]; then { $3 "$T/$1.bin" > "$T/$1.out" 2>&1 < /dev/null; } 2> /dev/null || LRC=$?
    else { "$T/$1.bin" > "$T/$1.out" 2>&1 < /dev/null; } 2> /dev/null || LRC=$?; fi
    return 0
}
# _want <label> <compile-cmd> <run-cmd> <source> <want-rc> <what>
_want() {
    _leg "$1" "$2" "$3" "$4"
    if [ "$LRC" -eq -1 ]; then
        _bad "$1: $6 did not compile (rc $BRC, ${BSZ:-0} bytes; an empty output is executable and exits 0)"
        grep -E '^error' "$T/$1.err" | head -2 | cut -c1-160 | sed 's/^/      /' || true
    elif [ "$LRC" -ne "$5" ]; then
        _bad "$1: $6 exited $LRC, want $5"
        grep -E 'FAIL' "$T/$1.out" | head -4 | cut -c1-160 | sed 's/^/      /' || true
    else
        pass=$((pass + 1))
    fi
}
# _legs <prefix> <compile-cmd> <run-cmd> : the rows every backend runs
_legs() {
    _want "$1_repro" "$2" "$3" "$T/repro.cyr" 1 "the filed repro (h binds the LAST g; was 2)"
    _want "$1_shapes" "$2" "$3" "$T/shapes.cyr" 111 "the three-shape repro (was 212: direct and expression calls bound the first g)"
    _want "$1_tcyr" "$2" "$3" "$TCYR" 0 "fn_redefinition_last_wins.tcyr"
    _ptlegs "$1" "$2" "$3"
}

# ── 6.7.16 (issues/2026-10-19-duplicate-fn-later-non-pointer-return-keeps-first-star-t-records.md): A REDEFINED FN'S
# `: *T` RECORDS ARE THE LAST DEFINITION'S. The step word, the pointee struct and the --syntax-only byte were written
# only by a `: *T` return and never cleared, so `fn gp(): *H` then `fn gp(): i64` kept the first one's `*H` at every
# call: `gp() + 1` stepped sizeof(H) (124, not 101) and `gp().b = 5` stored through the i64 (139), on every backend.
# Pass 1 starts each redefinition's return afresh; pass 2 re-reads an earlier definition without recording its `*T`.
# PT0 the filed repro verbatim (101 and ONE warning line, the duplicate's); PT1 the reverse order (`: i64` then `: *H`,
# the winner steps 24: 124); PT2 a call in a fn between the definitions, PT3 above both; PT4 `: *H` then no annotation;
# PT5 `: *H` then `: *G2` (steps 16: 116); PT6 `: *H` then `: *i64` (steps 8: 108); PT7 a method redefined in its
# impl; PT8 a generic whose inferred call reaches its i64 base; PT9 / PT10 `gp().b = 5;` / `gp().b` after a non-struct
# winner, refused as one definition is ("does not return a struct"; it stored / read through the first's `*H`); PT11
# (control) `: *H` then `: H2` by value stays "disagrees about its return type". The .tcyr's rd_p* rows carry PT0-PT5
# to the real hosts.
cat > "$T/pt0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct H { a; b; c; }
fn gp(): *H { return 0; }
fn gp(): i64 { return 100; }
fn go(): i64 { return gp() + 1; }
syscall(60, go());
EOF
_ptsrc() { printf 'include "lib/syscalls.cyr"\nstruct H { a; b; c; }\nstruct H2 { a; b; c; }\nstruct G2 { a; b; }\nvar buf: i64[8];\n%s\nsyscall(60, go());\n' "$2" > "$T/$1.cyr"; }
_ptsrc pt1 'fn gp(): i64 { return 100; }
fn gp(): *H { return 100; }
fn go(): i64 { return gp() + 1; }'
_ptsrc pt2 'fn gp(): *H { return 0; }
fn go(): i64 { return gp() + 1; }
fn gp(): i64 { return 100; }'
_ptsrc pt3 'fn go(): i64 { return gp() + 1; }
fn gp(): *H { return 0; }
fn gp(): i64 { return 100; }'
_ptsrc pt4 'fn gp(): *H { return 0; }
fn gp() { return 100; }
fn go(): i64 { return gp() + 1; }'
_ptsrc pt5 'fn gp(): *H { return 0; }
fn gp(): *G2 { return 100; }
fn go(): i64 { return gp() + 1; }'
_ptsrc pt6 'fn gp(): *H { return 0; }
fn gp(): *i64 { return 100; }
fn go(): i64 { return gp() + 1; }'
_ptsrc pt7 'impl H { fn gp(self): *H { return 0; } fn gp(self): i64 { return 100; } }
fn go(): i64 { var h: H; return h.gp() + 1; }'
_ptsrc pt8 'fn gp<T>(x: T): *H { return 0; }
fn gp<T>(x: T): i64 { return 100; }
fn go(): i64 { return gp(5) + 1; }'
_ptsrc pt9 'fn gp(): *H { return &buf; }
fn gp(): i64 { return 0; }
fn go(): i64 { gp().b = 5; return buf[1]; }'
_ptsrc pt10 'fn gp(): *H { return &buf; }
fn gp(): *i64 { return &buf; }
fn go(): i64 { buf[1] = 7; return gp().b; }'
_ptsrc pt11 'fn gp(): *H { return 0; }
fn gp(): H2 { var h: H2; return h; }
fn go(): i64 { return 0; }'
# _ptrefused <label> <compile-cmd> <source> <fragment>: rc != 0, no binary, the one `^error` line holds <fragment>
_ptrefused() {
    _rc=0; $2 < "$3" > "$T/$1.bin" 2> "$T/$1.err" || _rc=$?
    _n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$_rc" -eq 0 ]; then _bad "$1: compiled (rc 0) — want refused: $4"
    elif [ "$_n" -ne 1 ]; then _bad "$1: $_n error lines (want 1): $(grep -m1 '^error' "$T/$1.err" | cut -c1-140)"
    elif ! grep '^error' "$T/$1.err" | grep -qF "$4"; then _bad "$1: refused, but not as '$4': $(grep -m1 '^error' "$T/$1.err" | cut -c1-140)"
    else pass=$((pass + 1)); fi
}
_ptlegs() {
    _want "$1_pt0" "$2" "$3" "$T/pt0.cyr" 101 "PT0 the filed repro (\`fn gp(): *H\` then \`fn gp(): i64\`: gp() + 1 stepped 24, 124)"
    if [ "$LRC" -ne -1 ]; then
        _nw=$(grep -c '^warning' "$T/$1_pt0.err" || true)
        if [ "$_nw" -ne 1 ] || ! grep -q "^warning:<source>:4:1: duplicate fn 'gp' (last definition wins" "$T/$1_pt0.err"; then
            _bad "$1_pt0: want ONE warning line, the duplicate's at 4:1: $(grep -c '^warning' "$T/$1_pt0.err" || true) — $(grep -m1 '^warning' "$T/$1_pt0.err" | cut -c1-120)"
        else pass=$((pass + 1)); fi
    fi
    _want "$1_pt1" "$2" "$3" "$T/pt1.cyr" 124 "PT1 \`: i64\` then \`: *H\` (the winner steps 24)"
    _want "$1_pt2" "$2" "$3" "$T/pt2.cyr" 101 "PT2 a call between the definitions"
    _want "$1_pt3" "$2" "$3" "$T/pt3.cyr" 101 "PT3 a call above both definitions"
    _want "$1_pt4" "$2" "$3" "$T/pt4.cyr" 101 "PT4 \`: *H\` then no annotation"
    _want "$1_pt5" "$2" "$3" "$T/pt5.cyr" 116 "PT5 \`: *H\` then \`: *G2\` (steps 16)"
    _want "$1_pt6" "$2" "$3" "$T/pt6.cyr" 108 "PT6 \`: *H\` then \`: *i64\` (steps 8)"
    _want "$1_pt7" "$2" "$3" "$T/pt7.cyr" 101 "PT7 a method redefined in its impl"
    _want "$1_pt8" "$2" "$3" "$T/pt8.cyr" 101 "PT8 a generic's inferred call (its i64 base)"
    _ptrefused "$1_pt9" "$2" "$T/pt9.cyr" "8:18: cannot take a field of the result of 'gp': it does not return a struct"
    _ptrefused "$1_pt10" "$2" "$T/pt10.cyr" "8:37: cannot take a field of the result of 'gp': it does not return a struct"
    _ptrefused "$1_pt11" "$2" "$T/pt11.cyr" "disagrees about its return type"
}

# ── row 1: x86_64 ───────────────────────────────────────────────────────────────────────────
_legs x86 "$T/x86" ""
if grep -q 'unreachable fns' "$T/x86_repro.err"; then
    _bad "x86: the filed repro still reports an unreachable fn — the winning g is not reached"
else
    pass=$((pass + 1))
fi
printf '#!/bin/sh\nCYRIUS_DCE=1 exec "%s"\n' "$T/x86" > "$T/dcc"; chmod +x "$T/dcc"
_want x86_dce "$T/dcc" "" "$T/dce.cyr" 1 "CYRIUS_DCE=1 with dead code between the definitions"
if [ "$LRC" -ne -1 ] && ! grep -q 'dead code eliminated' "$T/x86_dce.err"; then
    _bad "x86_dce: nothing was eliminated, so the row did not move the winner (anti-vacuous)"
fi
_want x86_naked_dce "$T/dcc" "" "$T/naked_dce.cyr" 1 "#naked redefinition under CYRIUS_DCE=1 (was 139: the redirect's rel32 repaired twice)"
if [ "$LRC" -ne -1 ] && ! grep -q 'dead code eliminated' "$T/x86_naked_dce.err"; then
    _bad "x86_naked_dce: nothing was eliminated, so the row did not move the winner (anti-vacuous)"
fi
printf '#!/bin/sh\nCYRIUS_IR=3 exec "%s"\n' "$T/x86" > "$T/ir3cc"; chmod +x "$T/ir3cc"
_want x86_naked_ir3 "$T/ir3cc" "" "$T/naked_ir3.cyr" 1 "#naked redefinition under CYRIUS_IR=3 (was 60)"

# ── row 1b: a redefinition that disagrees about HOW it is called is refused ──────────────────
# Every call now reaches the last body, so a call compiled against an earlier definition arrives
# with that one's calling convention. The arity half has been an error since 6.5.37; the rest of
# the signature is refused the same way (src/frontend/parse_fn_def.cyr `_dsg_check`).
_refused() {  # <label> <want-text> <source-text> [compiler, default the x86 one]
    printf '%s\n' "$3" > "$T/$1.cyr"
    _rc=0; ${4:-"$T/x86"} < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || _rc=$?
    if [ "$_rc" -eq 0 ]; then
        _bad "$1: compiled (exit 0) — a call compiled against the earlier definition reaches a body called differently"
    elif ! grep -q "disagrees about its $2" "$T/$1.err"; then
        _bad "$1: refused, but not with 'disagrees about its $2': $(grep -m1 '^error' "$T/$1.err" | cut -c1-140)"
    else
        pass=$((pass + 1))
    fi
}
# The measured crash: a scalar first mk(), a struct-returning last one, a call between them
# (it bound the first and ran; with the redirect alone it SIGSEGV'd).
_refused sig_ret "return type" 'fn mk(): i64 { return 9; }
fn h(): i64 { var v = mk(); return v; }
struct P { a; b; c; }
fn mk(): P { var p = P { a: 1, b: 2, c: 3 }; return p; }
var r = h(); syscall(60, r);'
_refused sig_multiret "return type" 'fn two(): (i64, i64) { return (1, 2); }
fn two(): (i64, i64, i64) { return (1, 2, 3); }
var r = 0; syscall(60, r);'
_refused sig_param "parameter types" 'struct Big { a; b; c; }
fn f(p: Big): i64 { return 1; }
fn f(p): i64 { return 2; }
var r = 0; syscall(60, r);'
_refused sig_variadic "variadic parameter list" 'fn f(a, ...): i64 { return 1; }
fn h(): i64 { var x = f(1, 2, 3); return x; }
fn f(a): i64 { return 2; }
var r = h(); syscall(60, r);'
# A struct parameter of ANOTHER struct type: the masks agree (both address-passed), the struct id
# does not — B's body copied B's 64 bytes out of the caller's 24-byte A (it ran: exit 1).
_refused sig_struct_type "parameter types" 'struct A { a; b; c; }
struct B { a; b; c; d; e; f; g; h; }
fn f(p: A): i64 { return p.a + p.c; }
fn h(): i64 { var x = A { 1, 2, 3 }; return f(x) + 0; }
fn f(p: B): i64 { return p.a + p.h; }
syscall(60, h());'
# A parameter past the per-fn masks' width (ordinal 63) lives in the overflow row only: a `Str`
# there against a plain one differs nowhere else.
_p62=$(i=0; while [ $i -lt 63 ]; do printf 'p%d, ' $i; i=$((i + 1)); done)
_a62=$(i=0; while [ $i -lt 63 ]; do printf '%d, ' $((i % 5)); i=$((i + 1)); done)
_refused sig_overflow_row "parameter types" "include \"lib/string.cyr\"
include \"lib/str.cyr\"
fn w(${_p62}p63: Str): i64 { return 2; }
fn h(): i64 { return w(${_a62}\"abc\") + 0; }
fn w(${_p62}p63): i64 { return 1; }
syscall(60, h());"
# Win64 passes every vector by address under the struct mask, so only the recorded vector type
# tells a 16-byte from a 32-byte one there (SysV refuses the pair through the SIMD mask). The PE
# compile is the check: no wine needed.
printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$T/x86" > "$T/pecc"; chmod +x "$T/pecc"
_vec_pair='include "lib/simd.cyr"
fn f(v: f64v2): i64 { return 2; }
fn h(): i64 { var a: f64v2 = f64v2_make(1, 2); return f(a) + 0; }
fn f(v: f64v4): i64 { return 1; }
syscall(60, h());'
_refused sig_vector_pe "parameter types" "$_vec_pair" "$T/pecc"
# ...and a vector against a struct of the same 16 bytes at the same ordinal: both set the PE
# struct bit, and pass 1 leaves the struct's id in the row under the vector's definition — the
# per-definition reset of both rows (`_dsg_def_reset`) is what keeps the two sides apart.
_refused sig_vector_struct_pe "parameter types" 'include "lib/simd.cyr"
struct Q { a; b; }
fn f(v: f64v2): i64 { return 2; }
fn h(): i64 { var a: f64v2 = f64v2_make(1, 2); return f(a) + 0; }
fn f(p: Q): i64 { return p.a; }
syscall(60, h());' "$T/pecc"
# `async fn` against a plain one: a call to one receives a Future, to the other the value. Refused
# in pass 1, both orders (async-then-plain SIGSEGV'd at the await; plain-then-async bound the
# first body with no warning, its body being `f$impl`).
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s"\n' "$T/x86" > "$T/acc"; chmod +x "$T/acc"
_ASYNC_PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"'
_refused sig_async_then_plain '`async` marker' "$_ASYNC_PRE
async fn f(): i64 { return 5; }
fn h(): i64 { var fu = f(); return await fu; }
fn f(): i64 { return 7; }
fn main(): i64 { alloc_init(); return h(); }
syscall(60, main());" "$T/acc"
_refused sig_plain_then_async '`async` marker' "$_ASYNC_PRE
fn f(): i64 { return 5; }
fn h(): i64 { return f() + 0; }
async fn f(): i64 { return 7; }
fn main(): i64 { alloc_init(); return h(); }
syscall(60, main());" "$T/acc"
# ANTI-VACUOUS: the same convention spelled differently still only warns, and binds the last.
printf 'fn f(): i64 { return 1; }\nfn h(): i64 { var x = f(); return x; }\nfn f() { return 2; }\nvar r = h(); syscall(60, r);\n' > "$T/sig_same.cyr"
_want sig_same "$T/x86" "" "$T/sig_same.cyr" 2 "an unannotated redefinition of a ': i64' fn (same convention)"
# ...and so do the same struct type, the same overflow-row kind and the same vector type.
printf 'struct A { a; b; c; }\nfn f(p: A): i64 { return p.a + 10; }\nfn h(): i64 { var x = A { 1, 2, 3 }; return f(x) + 0; }\nfn f(p: A): i64 { return p.a + p.c; }\nsyscall(60, h());\n' > "$T/sig_same_struct.cyr"
_want sig_same_struct "$T/x86" "" "$T/sig_same_struct.cyr" 4 "the same struct parameter type (binds the last; was 11)"
printf '%s\n' "include \"lib/string.cyr\"
include \"lib/str.cyr\"
fn w(${_p62}p63: Str): i64 { return 2; }
fn h(): i64 { return w(${_a62}\"abc\") + 0; }
fn w(${_p62}p63: Str): i64 { return 1; }
syscall(60, h());" > "$T/sig_same_row.cyr"
_want sig_same_row "$T/x86" "" "$T/sig_same_row.cyr" 1 "the same overflow-row kind at ordinal 63 (binds the last; was 2)"
printf '%s\n' "$_vec_pair" | sed 's/f64v4): i64 { return 1/f64v2): i64 { return 1/' > "$T/sig_same_vec.cyr"
_want sig_same_vec "$T/x86" "" "$T/sig_same_vec.cyr" 1 "the same vector parameter type (binds the last; was 2)"
_rc=0; "$T/pecc" < "$T/sig_same_vec.cyr" > "$T/sig_same_vec.exe" 2> "$T/sig_same_vec.perr" || _rc=$?
if [ "$_rc" -ne 0 ]; then _bad "sig_same_vec_pe: the same vector type refused on PE (rc $_rc): $(grep -m1 '^error' "$T/sig_same_vec.perr" | cut -c1-140)"
else pass=$((pass + 1)); fi
# ...and an async fn redefined by an async one binds every call to the LAST constructor: a plain
# Future's caller now gets the coroutine's (was SIGSEGV — the first constructor built a plain
# Future around the coroutine's body).
printf '%s\n' "$_ASYNC_PRE
fn g0(): i64 { return 0; }
async fn f(a): i64 { return a + 5; }
fn h(): i64 { var fu = f(0); var r = future_force(fu); r = future_force(fu); r = future_force(fu); return r; }
async fn f(a): i64 { var s1 = await g0(); return a + 7; }
fn h2(): i64 { var fu = f(0); var r = future_force(fu); r = future_force(fu); r = future_force(fu); return r; }
fn main(): i64 { alloc_init(); return h() * 10 + h2(); }
syscall(60, main());" > "$T/async_ctor.cyr"
_want async_ctor "$T/acc" "" "$T/async_ctor.cyr" 77 "an async fn redefined as a coroutine (was 139)"

# ── row 1c (6.7.16): a call between the definitions is CHECKED against the last one's bool facts too ─────────────────
# Pass 2 re-recorded each definition's bool return bits and parameter kinds, so a call compiled between two definitions
# was checked against the earlier one: BX1 `: i64` then `: bool`, `var x: bool = f();` between, was refused (now 3);
# BX2 the reverse was accepted (x held 5) — now refused as one `: i64` definition is; BX3 / BX4 the same for a
# parameter `b: bool` / `b: i64` and `f(5)`; BX5 an earlier body calling its own name reaches the last definition.
# Controls: an earlier body is still checked against its OWN declaration (BX6 `return 5;` in its `: bool` body, BX7 a
# bool element of its `(bool, i64)`, BX8 a bare `return;`). The .tcyr's rd_bl / rd_bp / rd_br rows run BX1 BX3 BX5
# on every backend and host.
_bxsrc() { printf 'include "lib/syscalls.cyr"\n%s\nsyscall(60, go());\n' "$2" > "$T/$1.cyr"; }
_bxsrc bx1 'fn f(): i64 { return 5; }
fn go(): i64 { var x: bool = f(); if (x) { return 3; } return 4; }
fn f(): bool { return 1 == 1; }'
_want bx1 "$T/x86" "" "$T/bx1.cyr" 3 "BX1 \`: i64\` then \`: bool\`, a bool bind between (was refused)"
_bxsrc bx2 'fn f(): bool { return 1 == 1; }
fn go(): i64 { var x: bool = f(); if (x) { return 3; } return 4; }
fn f(): i64 { return 5; }'
_ptrefused bx2 "$T/x86" "$T/bx2.cyr" "3:30: cannot initialize bool 'x' with a value that is not a bool"
_bxsrc bx3 'fn f(b: bool): i64 { return 1; }
fn go(): i64 { return f(5); }
fn f(b: i64): i64 { return b; }'
_want bx3 "$T/x86" "" "$T/bx3.cyr" 5 "BX3 \`b: bool\` then \`b: i64\`, \`f(5)\` between (was refused)"
_bxsrc bx4 'fn f(b: i64): i64 { return b; }
fn go(): i64 { return f(5); }
fn f(b: bool): i64 { return 1; }'
_ptrefused bx4 "$T/x86" "$T/bx4.cyr" "3:25: cannot pass a value that is not a bool to bool parameter 'b' of 'f'"
_bxsrc bx5 'fn f(): i64 { var x: bool = f(); if (x) { return 1; } return 0; }
fn f(): bool { return 1 == 1; }
fn go(): i64 { var x: bool = f(); if (x) { return 3; } return 4; }'
_want bx5 "$T/x86" "" "$T/bx5.cyr" 3 "BX5 an earlier body's own call reaches the last (bool) definition (was refused)"
_bxsrc bx6 'fn f(): bool { return 5; }
fn f(): i64 { return 5; }
fn go(): i64 { return f(); }'
_ptrefused bx6 "$T/x86" "$T/bx6.cyr" "2:23: cannot return a value that is not a bool from bool fn 'f'"
_bxsrc bx7 'fn f(): (bool, i64) { return (5, 1); }
fn f(): (i64, i64) { return (5, 1); }
fn go(): i64 { var a, b = f(); return a + b; }'
_ptrefused bx7 "$T/x86" "$T/bx7.cyr" "2:31: cannot return a value that is not a bool as a bool element of 'f'"
_bxsrc bx8 'fn f(): bool { return; }
fn f(): i64 { return 5; }
fn go(): i64 { return f(); }'
_ptrefused bx8 "$T/x86" "$T/bx8.cyr" "2:16: a bare \`return;\` in bool fn 'f' returns 0"

# ── row 2: aarch64 under qemu ───────────────────────────────────────────────────────────────
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$T/x86" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/eb" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        _legs a64 "$T/cc_a64" qemu-aarch64
    else
        _bad "aarch64: src/main_aarch64.cyr did not build"
    fi
else
    echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; skips=$((skips + 1))
fi

# ── row 3: cx under cxvm ────────────────────────────────────────────────────────────────────
if "$T/x86" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/eb" && [ -s "$T/cc_cx" ] \
   && "$T/x86" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/eb2" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    printf '#!/bin/sh\nexec "%s" < "$1"\n' "$T/cxvm" > "$T/cxrun"; chmod +x "$T/cxrun"
    _legs cx "$T/cc_cx" "$T/cxrun"
else
    _bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"
fi

# ── row 4: PE under wine, private prefix ────────────────────────────────────────────────────
if command -v wine > /dev/null 2>&1; then
    printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$T/x86" > "$T/wcc"; chmod +x "$T/wcc"
    printf '#!/bin/sh\nWINEPREFIX="%s" HOME="%s" XDG_CACHE_HOME="%s/.cache" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1"\n' "$WP" "$WHM" "$WHM" > "$T/wrun"
    chmod +x "$T/wrun"
    _legs pe "$T/wcc" "$T/wrun"
else
    echo "  SKIP: PE leg (wine not installed)"; skips=$((skips + 1))
fi

if [ "$fail" -ne 0 ]; then echo "FAIL $G: $fail row(s) red, $pass green"; exit 1; fi
if [ "$skips" -gt 0 ]; then
    echo "SKIP $G: $skips leg(s) above could not run; all $pass that ran passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS $G: $pass rows — a redefined fn binds every call to its LAST definition (the filed repro exits 1, the three call shapes 111, fn_redefinition_last_wins.tcyr passes on x86_64, aarch64/qemu, cx/cxvm and PE/wine; the winner is not reported unreachable and survives dead-code elimination with the redirect repaired, #naked included; a redefinition called differently, or async against plain, is refused; its \`: *T\` return records are the last definition's, 6.7.16)"
exit 0
