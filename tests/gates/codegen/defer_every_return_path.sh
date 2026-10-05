#!/bin/sh
# defer_every_return_path.sh — 6.6.7 bite 2. A `defer` / `secret var` runs on EVERY return
# path with the return value intact, on every backend, and the shapes a .tcyr cannot reach are
# pinned here.
#
# ⛔ WHY. `return IDENT(args);` was lowered to epilogue + jmp (x86/aarch64) or call + inline
# epilogue (cx), which never reached the defer walker: every tail-shaped return — `return
# Ok(fd);` included, Ok/Err being ctor fns — skipped the fn's defers and left its `secret var`
# un-zeroised (CVE-47). And the walker saved rax/x0/r0 alone, so a call in a defer body
# destroyed the rest of the return convention (pair / Ok-Err payload, arity-3 slot, f64 and
# vector registers). The fix diverts every tail call in a fn with a defer (a whole-body
# prescan) and saves the whole convention (EDEFER_SAVE/RESTORE, per backend).
#
# LEGS — the runtime rows live in tests/tcyr/crossos/defer_every_return_path.tcyr, which the
# release gate runs on real ecb / ach / cass / pi and check.sh runs on this host. This gate adds:
#   host   `async fn` (non-coroutine) with a tail return — CYRIUS_ASYNC=1, which the tcyr runner
#          cannot set; and the `#inline ignored: body has a defer/secret block` warning (a
#          compile-time diagnostic a .tcyr cannot observe)
#   a64    the crossos tcyr + the async row under qemu-aarch64 (qemu is not hardware)
#   pe     the crossos tcyr under wine, when installed (wine is not Windows)
#   cx     its own program below: the tcyr's 16-byte struct rows do not compile on cx (the
#          int-class pair-return ABI is refused there by name), so the cx leg carries 22 rows
#          by hand — tail calls (zero-arg / arg / preceding the defer / self-recursive / pair),
#          the local-first control, `return (a, b)` / `(a, b, c)` / ret2, an f64v2 and an
#          f64v4 return (the r0..r3 quad), a `?` Err propagation and a `return Ok(x)` tail;
#          the defer body's clobber is a 6-arg call plus f64v2 work, so every register of the
#          cx convention (r0-r5) is overwritten unless the walker saves it
# Every compiler is built FROM SOURCE (stage1 = build/cycc < src/main.cyr), so a source revert
# turns this gate RED instead of being masked by a stale build/cycc.
#
# MUTATION LEDGER (6.6.7, each a one-edit scratch src built by build/cycc; tcyr counts are
# x86 — aarch64 matches unless noted):
#   the prescan divert disabled                        -> tcyr 15 RED; async RED (host + a64);
#                                                         pe RED; cx 6 rows RED
#   the walker back to a rax-only push/pop             -> tcyr 12 RED (a64 11); the alignment
#                                                         tcyr 2 RED (x86); cx 8 rows RED
#   the cx walker saving r0/r4/r5 only (r1-r3 dropped) -> cx 2 rows RED (f64v2, f64v4)
#   the prescan not restored by the nested-fn snapshot -> tcyr 2 RED (after a closure / f<T>())
#   the closure body not prescanned                    -> tcyr 1 RED
#   the inline 106/108 exclusion removed               -> tcyr 3 RED; the warning row RED
#   the x86 walker re-align (`and rsp,-16`) dropped    -> the alignment tcyr's `?` row RED
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: defer_every_return_path: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $T, never the user's ~/.wine: its one wineserver is shared by
# every concurrent check.sh on the box. The EXIT kill is scoped to THIS prefix and also removes
# its server socket dir (/tmp/.wine-<uid>/server-<dev>-<ino>). CHANGELOG [6.6.16]
# 6.6.17: wine's own HOME and XDG_CACHE_HOME are under $T too — a fresh prefix writes
# $HOME/.cache (mesa shader caches) — and `wineserver -k` leaves the server dir behind, so
# _wine_down removes it. CHANGELOG [6.6.17]
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
CC="${CYCC:-$R/build/cycc}"
[ -x "$CC" ] || { echo "FAIL defer_every_return_path: no $CC"; exit 1; }
cd "$R"
"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" && [ -s "$T/stage1" ] || {
  echo "FAIL defer_every_return_path: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"
fail=0
pass=0
ok()  { echo "  ok:   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
TC="$R/tests/tcyr/crossos/defer_every_return_path.tcyr"

# ---- host: async non-coroutine tail return (x86; also run on aarch64 below) --------------
cat > "$T/as.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
var cran = 0;
fn _plus(n): i64 { return n + 1; }
fn _clob6(a, b, c, d, e, f): i64 { return a + b + c + d + e + f; }
async fn a_tail(): i64 { defer { cran = cran + 1; _clob6(1, 2, 3, 4, 5, 6); } return _plus(4); }
async fn a_local(): i64 { defer { cran = cran + 1; } var r = _plus(4); return r; }
fn main(): i64 {
    alloc_init();
    cran = 0; var v = await a_tail(); var c1 = cran;
    cran = 0; var w = await a_local(); var c2 = cran;
    if (v != 5) { return 10; }
    if (c1 != 1) { return 11; }
    if (w != 5) { return 20; }
    if (c2 != 1) { return 21; }
    return 0;
}
var rr = main();
sys_exit(rr);
EOF
if CYRIUS_ASYNC=1 "$T/stage1" < "$T/as.cyr" > "$T/as.x" 2>"$T/as.err" && [ -s "$T/as.x" ]; then
  chmod +x "$T/as.x"; timeout 20 "$T/as.x" > /dev/null 2>&1; r=$?
  if [ "$r" -eq 0 ]; then ok "host: async fn tail return runs its defer (and the local-first control)"
  else bad "host: async fn rows exit $r (10/11 = the tail row: value / defer; 20/21 = the control)"; fi
else bad "host: the async probe did not compile"; sed -n 1,3p "$T/as.err"; fi

# ---- host: an ignored `#inline` names the defer ------------------------------------------
cat > "$T/iw.cyr" <<'EOF'
var cran = 0;
#inline
fn g(a): i64 { defer { cran = cran + 1; } return a + 1; }
var x = g(5);
syscall(60, cran * 10 + x);
EOF
if "$T/stage1" < "$T/iw.cyr" > "$T/iw.x" 2>"$T/iw.err" && [ -s "$T/iw.x" ]; then
  if grep -q "#inline ignored: body has a defer/secret block" "$T/iw.err"; then
    ok "host: an #inline fn with a defer is refused by name (warning)"
  else bad "host: an #inline fn with a defer compiled with no 'body has a defer/secret block' warning"; fi
  chmod +x "$T/iw.x"; timeout 20 "$T/iw.x" > /dev/null 2>&1; r=$?
  [ "$r" -eq 16 ] && ok "host: that fn is called, not replayed (exit 16)" || bad "host: the #inline-with-defer probe exited $r, want 16"
else bad "host: the #inline-with-defer probe did not compile"; fi

# ---- aarch64 (qemu) ------------------------------------------------------------------------
if command -v qemu-aarch64 > /dev/null 2>&1; then
  if "$T/stage1" < "$R/src/main_aarch64.cyr" > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
    chmod +x "$T/cc_a64"
    "$T/cc_a64" < "$TC" > "$T/tc.a" 2>"$T/tc.aerr" && chmod +x "$T/tc.a"
    (cd "$T" && timeout 120 qemu-aarch64 ./tc.a > "$T/tc.aout" 2>&1); r=$?
    [ "$r" -eq 0 ] && ok "a64: crossos defer tcyr ($(tail -1 "$T/tc.aout"))" || { bad "a64: crossos defer tcyr exit $r"; grep FAIL "$T/tc.aout" | head -5; }
    CYRIUS_ASYNC=1 "$T/cc_a64" < "$T/as.cyr" > "$T/as.a" 2>/dev/null && chmod +x "$T/as.a"
    (cd "$T" && timeout 60 qemu-aarch64 ./as.a > /dev/null 2>&1); r=$?
    [ "$r" -eq 0 ] && ok "a64: async fn tail return runs its defer" || bad "a64: async fn rows exit $r"
  else bad "a64: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP: a64 leg — qemu-aarch64 not installed"; GATE_SKIPS=$((${GATE_SKIPS:-0} + 1)); fi

# ---- PE (wine) -----------------------------------------------------------------------------
if command -v wine > /dev/null 2>&1; then
  export WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
  CYRIUS_TARGET_WIN=1 "$T/stage1" < "$TC" > "$T/tc.exe" 2>"$T/tc.werr"
  if [ -s "$T/tc.exe" ]; then
    (cd "$T" && timeout 180 wine ./tc.exe > "$T/tc.wout" 2>/dev/null); r=$?
    [ "$r" -eq 0 ] && ok "pe: crossos defer tcyr under wine ($(tail -1 "$T/tc.wout" | tr -d '\r'))" || { bad "pe: crossos defer tcyr exit $r"; grep FAIL "$T/tc.wout" | head -5; }
  else bad "pe: crossos defer tcyr did not compile"; fi
else echo "  SKIP: pe leg — wine not installed"; GATE_SKIPS=$((${GATE_SKIPS:-0} + 1)); fi

# ---- cx ------------------------------------------------------------------------------------
cat > "$T/cx.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
include "lib/simd.cyr"
var cran = 0;
var nfail = 0;
fn chk(got, want, label): i64 {
    if (got != want) { syscall(1, 1, label, strlen(label)); syscall(1, 1, "\n", 1); nfail = nfail + 1; }
    return 0;
}
fn _clob6(a, b, c, d, e, f): i64 { return a + b + c + d + e + f; }
# The defer body's clobber: a 6-arg call (r0-r5) AND f64v2 work, so every register of the
# cx return convention — r0 scalar, r0:r1 pair / Ok-Err, r0:r1:r2 arity-3, r0..r3 the f64v4
# quad — is overwritten unless EDEFER_SAVE/RESTORE carries it.
fn _vclob(): i64 { var q: f64v2 = f64v2_make(1, 2); var w: f64v2 = f64v2_make(5, 6); return f64v2_lo_ptr(&q) + f64v2_lo_ptr(&w); }
fn clob(): i64 { var k = _clob6(1, 2, 3, 4, 5, 6); k = k + _vclob(); cran = cran + 1; return k; }
fn _value(): i64 { return 42; }
fn _plus(n): i64 { return n + 1; }
fn t_zero(): i64 { defer { clob(); } return _value(); }
fn t_arg(): i64 { defer { clob(); } return _plus(41); }
fn t_loop(n): i64 { var i = 0; while (i < n) { if (i == 1) { return _plus(i); } defer { clob(); } i = i + 1; } return 0; }
fn t_selfrec(n): i64 { defer { cran = cran + 1; } if (n == 0) { return 0; } return t_selfrec(n - 1); }
fn t_local(): i64 { defer { clob(); } var r = _value(); return r; }
fn w_tuple(): i64 { defer { clob(); } return (7, 99); }
fn w_tuple3(): i64 { defer { clob(); } return (7, 99, 55); }
fn w_ret2(): i64 { defer { clob(); } ret2(7, 99); }
fn _two(): i64 { return (7, 99); }
fn t_pair(): i64 { defer { clob(); } return _two(); }
fn w_v2(): f64v2 { var v: f64v2 = f64v2_make(11, 22); defer { clob(); } return v; }
fn w_v4(): f64v4 { var v: f64v4 = f64v4_make(31, 32, 33, 34); defer { clob(); } return v; }
fn _errv(x): i64 { return Err(x); }
fn w_q(x): i64 { defer { clob(); } var v = _errv(x)?; return Ok(v); }
fn t_ok(x): i64 { defer { clob(); } return Ok(x); }
fn main(): i64 {
    cran = 0; chk(t_zero(), 42, "cx tail zero-arg: value"); chk(cran, 1, "cx tail zero-arg: defer ran");
    cran = 0; chk(t_arg(), 42, "cx tail with arg: value"); chk(cran, 1, "cx tail with arg: defer ran");
    cran = 0; chk(t_loop(5), 2, "cx tail preceding the defer: value"); chk(cran, 1, "cx tail preceding the defer: defer ran");
    cran = 0; chk(t_selfrec(3), 0, "cx self-recursive tail: value"); chk(cran, 4, "cx self-recursive tail: every level ran");
    cran = 0; chk(t_local(), 42, "cx control local-first: value"); chk(cran, 1, "cx control local-first: defer ran");
    cran = 0; var a, b = w_tuple(); chk(a * 1000 + b, 7099, "cx return (a, b) survives the defer body");
    cran = 0; var c, d, e = w_tuple3(); chk(d * 100 + e, 9955, "cx return (a, b, c) survives the defer body");
    cran = 0; var f, g = w_ret2(); chk(f * 1000 + g, 7099, "cx ret2 survives the defer body");
    cran = 0; var h, i = t_pair(); chk(h * 1000 + i, 7099, "cx pair tail call: value"); chk(cran, 1, "cx pair tail call: defer ran");
    cran = 0; var vr: f64v2 = w_v2(); chk(f64v2_lo_ptr(&vr) * 100 + f64v2_hi_ptr(&vr), 1122, "cx f64v2 return survives the defer body");
    var v4: f64v4 = w_v4();
    chk(f64v4_lane0_ptr(&v4) * 1000000 + f64v4_lane1_ptr(&v4) * 10000 + f64v4_lane2_ptr(&v4) * 100 + f64v4_lane3_ptr(&v4), 31323334, "cx f64v4 return (r0..r3) survives the defer body");
    chk(cran, 2, "cx vector returns: both defers ran");
    cran = 0; var qt, qv = w_q(77); chk(qt * 1000 + qv, 1077, "cx `?` Err propagation: tag + payload survive the defer body"); chk(cran, 1, "cx `?` Err propagation: defer ran");
    cran = 0; var ot, ov = t_ok(99); chk(ot * 1000 + ov, 99, "cx return Ok(x) tail: tag + payload survive the defer body"); chk(cran, 1, "cx return Ok(x) tail: defer ran");
    return nfail;
}
var rr = main();
syscall(60, rr);
EOF
if "$T/stage1" < "$R/src/main_cx.cyr" > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$T/stage1" < "$R/programs/cxvm.cyr" > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
  chmod +x "$T/cc_cx" "$T/cxvm"
  if "$T/cc_cx" < "$T/cx.cyr" > "$T/cx.cyx" 2>"$T/cx.err" && [ -s "$T/cx.cyx" ]; then
    timeout 60 "$T/cxvm" < "$T/cx.cyx" > "$T/cx.out" 2>&1; r=$?
    [ "$r" -eq 0 ] && ok "cx: 22 tail / pair / arity-3 / ret2 / f64v2 / f64v4 / ?-Err / Ok rows" || { bad "cx: $r rows failed"; sed 's/^/        /' "$T/cx.out" | head -8; }
  else bad "cx: the cx program did not compile"; sed -n 1,3p "$T/cx.err"; fi
else bad "cx: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi

echo "  $pass ok, $fail failed"
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "$fail" -eq 0 ] && [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: defer_every_return_path — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
[ "$fail" -eq 0 ] && { echo "PASS: defer_every_return_path"; exit 0; }
echo "FAIL: defer_every_return_path"; exit 1
