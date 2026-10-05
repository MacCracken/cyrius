#!/bin/sh
# toplevel_scan_shared.sh — 6.6.17. The top-level declaration scans live ONCE, in
# src/frontend/parse_fn.cyr — `_tl_pass1` (register), `_tl_pass2` (define) and
# `_tl_enum_inits` — and every src/main*.cyr fork calls them.
#
# WHY. Each of the seven forks used to carry its own copy of all three loops (21 copies), so a
# new top-level form had to be added seven times and the fork that missed it broke on its own
# target only: #io (v5.8.20), #pure (v6.2.2), the v6.4.26 PE reroute stubs only cass's cycc_cx
# caught, #inline's consume (6.6.3), the directive arms (6.6.9). The DRY was proven
# logic-preserving: every fork's compiler, old vs new, emitted byte-identical output for its
# own self-build and for the whole tcyr corpus (x86, aarch64 cross + native, both Mach-O on
# ecb/ach, PE, cx).
#
# Rows (static — reads source, needs no compiler):
#   F  the fork list is DERIVED (src/main*.cyr, >= 7), so an eighth fork is covered on day one.
#   C  each fork calls each shared scan exactly once, and passes the SAME `objok` to both
#      passes (pass 1 registering `object;` while pass 2 stops at it ends the declaration
#      phase there).
#   R  no fork reads the token stream (PEEKT / PEEKV) or calls a scan arm itself — a fork
#      that re-grows its own dispatch is exactly how the drift started.
#   H  the shared helpers carry the arms the forks used to (anti-vacuous: an emptied helper
#      fails here, not only in the self-host).
# MUTATION (6.6.17): restoring main_cx.cyr's own pass-1 loop -> RED rows C and R; dropping the
# `_prescan_tail(S)` call from _tl_pass1 -> RED row H; main_win.cyr passing objok 0 to pass 2
# only -> RED row C. The slot-open tree (4a37046b) is RED on C and R for all seven forks.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: toplevel_scan_shared: cannot cd to $ROOT"; exit 1; }
PF=src/frontend/parse_fn.cyr
[ -f "$PF" ] || { echo "FAIL: toplevel_scan_shared: $PF missing"; exit 1; }
fail=0
bad() { echo "  FAIL: toplevel_scan_shared $1"; fail=$((fail + 1)); }

# code lines only: drop whole-line comments and trailing `# ...` comments
code() { grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]#.*$//'; }
# the body of one top-level fn in $PF
body() { awk -v n="fn $1(" 'index($0, n) == 1 {on=1} on {print} on && /^}/ {exit}' "$PF"; }
cnt() { printf '%s\n' "$1" | grep -cF -- "$2" || true; }

# ── F — derive the forks ──
forks=$(ls src/main*.cyr 2>/dev/null | grep -v version_str)
nf=$(printf '%s\n' "$forks" | grep -c . || true)
[ "$nf" -ge 7 ] || bad "row F: expected >= 7 src/main*.cyr forks, found $nf"

ARMS='PARSE_STRUCT_DEF(|PARSE_UNION_DEF(|PARSE_GVAR_REG(|PARSE_ENUM_DEF(|PARSE_FN_DEF(|PARSE_IMPL(|_prescan_fn_sig(|_prescan_impl(|_prescan_tail(|_skip_gvar_decl(|_tl_directive(|_TL_VIS(|_IS_FN_KW(|_TOK_IS_KERNEL(|SUSEC('
for f in $forks; do
  c=$(code "$f")
  # ── C — one call per scan, one objok ──
  p1=$(printf '%s\n' "$c" | grep -oE '_tl_pass1\(S, [01]\);' || true)
  p2=$(printf '%s\n' "$c" | grep -oE '_tl_pass2\(S, [01]\);' || true)
  n1=$(printf '%s\n' "$p1" | grep -c . || true); n2=$(printf '%s\n' "$p2" | grep -c . || true)
  ne=$(cnt "$c" '_tl_enum_inits(S);')
  [ "$n1" = 1 ] && [ "$n2" = 1 ] && [ "$ne" = 1 ] \
    || bad "row C: $f calls _tl_pass1 x$n1, _tl_pass2 x$n2, _tl_enum_inits x$ne (want 1 each)"
  o1=$(printf '%s' "$p1" | sed 's/.*(S, \([01]\)).*/\1/'); o2=$(printf '%s' "$p2" | sed 's/.*(S, \([01]\)).*/\1/')
  [ "$n1" = 1 ] && [ "$n2" = 1 ] && [ "$o1" != "$o2" ] \
    && bad "row C: $f passes objok $o1 to pass 1 and $o2 to pass 2"
  # ── R — no private dispatch ──
  hits=$(grep -nE 'PEEKT\(|PEEKV\(' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | cut -d: -f1 | head -5 | tr '\n' ' ' || true)
  [ -z "$hits" ] || bad "row R: $f reads the token stream itself (lines $hits) — route it through the shared scan"
  arm=$(printf '%s\n' "$c" | grep -oE "$(printf '%s' "$ARMS" | sed 's/(/\\(/g')" | sort -u | tr '\n' ' ' || true)
  [ -z "$arm" ] || bad "row R: $f calls scan arms itself: $arm"
done

# ── H — the shared helpers carry the arms ──
need() { b=$(body "$1"); [ -n "$b" ] || { bad "row H: fn $1 is missing from $PF"; return; }
  shift; for s in "$@"; do [ "$(cnt "$b" "$s")" -ge 1 ] || bad "row H: $s is not in its shared scan"; done; }
need _tl_pass1 '_tl_scan1(S, objok)' '_prescan_tail(S);' 'SMOD(S, 0);'
need _tl_scan1 '_tl_directive(S, 0) == 1' '_prescan_fn_sig(S);' 'PARSE_STRUCT_DEF(S);' 'PARSE_GVAR_REG(S);' '_tl_use(S);'
need _tl_scan1_mode '_prescan_impl(S);' '_tl_kmode(S, 3);'
need _tl_pass2 '_tl_scan2(S, objok)' 'SMOD(S, 0);'
need _tl_scan2 '_tl_directive(S, 1) == 1' 'PARSE_ENUM_DEF(S, 2);'
need _tl_scan2_def 'PARSE_FN_DEF(S);' '_skip_gvar_decl(S);' 'PARSE_IMPL(S);'
need _tl_enum_inits 'PARSE_ENUM_DEF(S, 1);'

if [ "$fail" -ne 0 ]; then
  echo "FAIL toplevel_scan_shared: $fail row(s) red — a top-level form goes in ONE place (src/frontend/parse_fn.cyr _tl_scan1 / _tl_scan2)"
  exit 1
fi
echo "PASS toplevel_scan_shared: $nf forks each call _tl_pass1 / _tl_pass2 / _tl_enum_inits once with one objok, none reads the token stream or dispatches an arm itself, and the shared scans carry every arm"
exit 0
