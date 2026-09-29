#!/bin/sh
# 6.6.10: every compiler table cap that REPORTS must also STOP STORING.
#
# v6.4.62 (multi-error) turned ERR_MSG from exit into print-and-return. Caps written
# before that relied on ERR_MSG not coming back, so they silently became
# report-then-store: the error was printed and the write it guarded still ran, past
# the end of a fixed heap-map region. One root cause, six sites, one gate:
#   await      _coro_rcp[] past _CORO_MAX_SUSP        -> compiler SIGSEGV (rc 139)
#   continue   S+0x18F8A0 patch slots, 9th onward      -> swept ~16 KB of heap-map state
#                                                         (use_count at 0x1903D0 -> rc 139)
#   REGSTRUCT  struct 1025+ written over fcount[0]    -> struct 0's size corrupted; and
#                                                         DUMP_STRUCTS ran per refused struct
#                                                         (80,753 stderr lines at 1100)
#   ADDFIELD   field 257+ stored anyway               -> sizeof grew past the cap
#   ADDFIELD   pool entry 8192+ written over the name pool
#   PP_DEFINE  17th hash landed on value[0]; the count grew, so the flag was DEFINED
#   PP_PREDEFINE the same cap (builtin-only callers: a source-premise row)
# Each behavioural row FAILS on the pre-6.6.10 compiler. CHANGELOG [6.6.10]
#
# ⚠ The cx await row passes vacuously until the cx compiler reads CYRIUS_ASYNC (6.6.10
# bite 10): today it refuses `async` at rc 1 before reaching the cap. On the merged
# tree it is a real check.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: cap_errors_stop_storing: no build/cycc"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cap_errors_stop_storing: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
cd "$ROOT"

fail=0
bad() { echo "FAIL: cap_errors_stop_storing: $*"; fail=1; }

# compile COMPILER FIXTURE -> sets rc, stderr in $D/err
comp() {
    rc=0
    CYRIUS_ASYNC=1 timeout 120 "$1" < "$2" > "$D/out" 2> "$D/err" || rc=$?
}

# Cross compilers built FROM SOURCE with $CC, so a source revert flips the rows red
# rather than being masked by a stale build/cycc_* binary.
"$CC" < src/main_aarch64.cyr > "$D/cc_aa" 2>/dev/null && chmod +x "$D/cc_aa" || bad "aarch64 cross-compiler build failed"
"$CC" < src/main_cx.cyr > "$D/cc_cx" 2>/dev/null && chmod +x "$D/cc_cx" || bad "cx cross-compiler build failed"

# ── await: 600 suspend points in one coroutine (cap 63) ─────────────────────────────
{
    printf 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\n'
    printf 'include "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\n'
    echo 'fn nopark(): i64 { return 0; }'
    echo 'async fn steps(C): i64 {'
    echo '    var x = 0;'
    awk 'BEGIN { for (i = 0; i < 600; i++) printf "    var s%d = await nopark();\n", i }'
    echo '    return x;'
    echo '}'
    echo 'fn main(): i64 { alloc_init(); var C = steps(0); var r = future_force(C); return 0; }'
    echo 'var e = main();'
    echo 'syscall(60, e);'
} > "$D/aw.cyr"
comp "$CC" "$D/aw.cyr"
[ "$rc" = 1 ] || bad "await x86: rc $rc, want 1 (139 = the _coro_rcp overflow)"
grep -q 'too many `await` suspend points' "$D/err" || bad "await x86: cap message missing"
if [ -x "$D/cc_aa" ]; then
    comp "$D/cc_aa" "$D/aw.cyr"
    [ "$rc" = 1 ] || bad "await aarch64: rc $rc, want 1"
fi
if [ -x "$D/cc_cx" ]; then
    comp "$D/cc_cx" "$D/aw.cyr"
    [ "$rc" = 1 ] || bad "await cx: rc $rc, want 1"
fi

# ── continue: 400 in one for-loop (cap 8), then a real error in a later fn ─────────
{
    echo 'var gg = 3;'
    echo 'fn main(): i64 { var s = 0; for (var i = 0; i < 3; i = i + 1) {'
    awk 'BEGIN { for (i = 0; i < 400; i++) printf "  if (i == %d) { continue; }\n", i }'
    echo '  var k = 5; s = s + k;'
    echo '} return s; }'
    echo 'fn h(): i64 { var t = 9; return t + gg + cap_marker_after_continues; }'
    echo 'var e = main(); syscall(60, e);'
} > "$D/ct.cyr"
comp "$CC" "$D/ct.cyr"
[ "$rc" = 1 ] || bad "continue: rc $rc, want 1 (139 = patch slots swept over use_count)"
grep -q 'too many continue statements' "$D/err" || bad "continue: cap message missing"
grep -q "cap_marker_after_continues" "$D/err" || bad "continue: the later error was not reported (state corrupted?)"

# ── REGSTRUCT: 1100 structs (cap 1024), then a union and a struct past the cap ─────
# The two callers must SKIP a refused body: indexing it with sid - 1 = -1 writes the union
# flag over struct 1023's name slot and reads a garbage field count for the struct.
{
    awk 'BEGIN { for (i = 0; i < 1100; i++) printf "struct S%d { a; }\n", i }'
    echo 'union UPast { a; b; }'
    echo 'struct SPast { a; b; }'
    echo '#assert sizeof(S0) == 8;'
    echo '#assert sizeof(S1023) == 8;'
    echo 'syscall(60, 0);'
} > "$D/st.cyr"
comp "$CC" "$D/st.cyr"
[ "$rc" = 1 ] || bad "structs: rc $rc, want 1"
grep -q 'too many struct definitions' "$D/err" || bad "structs: cap message missing"
grep -q '#assert failed' "$D/err" && bad "structs: a refused struct was stored (over struct 0's field count, or at index -1 over struct 1023's name)"
grep -q 'unknown type in sizeof' "$D/err" && bad "structs: a refused union/struct body wrote at index -1 (struct 1023's name slot)"
n=$(grep -c 'structs registered' "$D/err")
[ "$n" = 1 ] || bad "structs: DUMP_STRUCTS ran $n times, want once"
lines=$(wc -l < "$D/err")
[ "$lines" -le 1200 ] || bad "structs: $lines stderr lines, want <= 1200 (the dump is once, not per refused struct)"

# ── ADDFIELD: 300 fields in one struct (cap 256) ───────────────────────────────────
{
    echo 'struct Big {'
    awk 'BEGIN { for (i = 0; i < 300; i++) printf "  f%d;\n", i }'
    echo '}'
    echo 'struct After { x; y; }'
    echo '#assert sizeof(Big) == 2048;'
    echo '#assert sizeof(After) == 16;'
    echo 'syscall(60, 0);'
} > "$D/fl.cyr"
comp "$CC" "$D/fl.cyr"
[ "$rc" = 1 ] || bad "fields: rc $rc, want 1"
grep -q 'too many struct fields' "$D/err" || bad "fields: cap message missing"
grep -q '#assert failed' "$D/err" && bad "fields: fields 257+ were stored (sizeof(Big) != 256 x 8)"

# ── ADDFIELD pool: 40 x 250 = 10000 entries (pool 8192), then one more struct ─────
{
    awk 'BEGIN { for (s = 0; s < 40; s++) { printf "struct T%d {\n", s; for (i = 0; i < 250; i++) printf "  f%d;\n", i; print "}" } }'
    echo 'struct TPast { a; b; }'
    echo '#assert sizeof(TPast) == 0;'
    echo 'syscall(60, 0);'
} > "$D/pool.cyr"
comp "$CC" "$D/pool.cyr"
[ "$rc" = 1 ] || bad "pool: rc $rc, want 1"
grep -q 'struct field pool exhausted' "$D/err" || bad "pool: cap message missing"
grep -q '#assert failed' "$D/err" && bad "pool: entries past 8192 were stored (over the field-name pool)"

# ── PP_DEFINE: 20 user #defines (table of 16 incl. builtins) ──────────────────────
{
    awk 'BEGIN { for (i = 0; i < 20; i++) printf "#define D%d %d\n", i, i }'
    echo 'var a = 1;'
    echo 'var b = 2;'
    echo '#ifdef D19'
    echo 'var c = pp_marker_past_the_cap;'
    echo '#endif'
    echo 'syscall(60, 0);'
} > "$D/pp.cyr"
comp "$CC" "$D/pp.cyr"
[ "$rc" = 1 ] || bad "pp define: rc $rc, want 1"
grep -q 'too many preprocessor #define/flag entries' "$D/err" || bad "pp define: cap message missing"
grep -q 'pp_marker_past_the_cap' "$D/err" && bad "pp define: #define past the cap was stored (D19 is defined)"

# ── PP_PREDEFINE: only builtin callers (no user input reaches it) — source premise ──
awk '/^fn PP_PREDEFINE\(/ { f = 1 } f && /_pp_flag_count >= 16/ { print; exit }' src/frontend/lex_pp.cyr | grep -q 'return 0;' \
    || bad "pp predefine: the cap in PP_PREDEFINE does not return after ERR_MSG"
awk '/^fn PP_DEFINE\(/ { f = 1 } f && /_pp_flag_count >= 16/ { print; exit }' src/frontend/lex_pp.cyr | grep -q 'return 0;' \
    || bad "pp define: the cap in PP_DEFINE does not return after ERR_MSG"

[ "$fail" = 0 ] || exit 1
echo "PASS: every report-then-store cap stops storing (await x86/aarch64/cx, continue, REGSTRUCT, ADDFIELD, pool, PP_DEFINE/PREDEFINE; 6.6.10)"
