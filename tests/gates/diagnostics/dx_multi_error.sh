#!/bin/sh
# v6.4.62 (DX multi-error): assert cycc reports MULTIPLE errors per compile (panic-mode
# recovery) instead of fail-fast, emits NO output on error, exits non-zero, and never
# crashes/hangs on malformed input. Guards the _panic/_sync_skip mechanism, the
# _had_error output gate (EMITELF x2 + cx) + per-fork exit, and the PEEKT anti-hang
# watchdog. (Robustness vs byte-mutated input is the VR-02 parser-fuzz gate's job.)
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
T=$(mktemp); E=$(mktemp); O=$(mktemp)
trap 'rm -f "$T" "$E" "$O"' EXIT

# 1) TWO reachable functions, each a missing-semicolon (ERR_EXPECT) → BOTH reported,
#    no output, exit non-zero. (main calls them so they aren't DCE-skipped.)
printf 'fn f(): i64 {\n    var p = 1\n    return p;\n}\nfn g(): i64 {\n    var q = 2\n    return q;\n}\nfn main(): i64 { return f() + g(); }\n' > "$T"
rc=0; "$CC" < "$T" > "$O" 2>"$E" || rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: errored compile exited 0"; exit 1; }
n=$(grep -c '^error:' "$E" || true)
[ "$n" -ge 2 ] || { echo "FAIL: multi-error reported $n errors, want >=2:"; cat "$E"; exit 1; }
[ ! -s "$O" ] || { echo "FAIL: errored compile emitted $(wc -c < "$O") bytes of output (should be 0)"; exit 1; }
grep -q ':3:5: ' "$E" || { echo "FAIL: first error not at :3:5::"; cat "$E"; exit 1; }
grep -q ':7:5: ' "$E" || { echo "FAIL: second error not at :7:5::"; cat "$E"; exit 1; }

# 2) garbage tokens past EOF → must terminate (not SIGSEGV, not hang), no output.
printf 'fn main(): i64 { var x = @@@ ][ }} return' > "$T"
rc=0; timeout 10 "$CC" < "$T" > "$O" 2>/dev/null || rc=$?
[ "$rc" -ne 124 ] || { echo "FAIL: garbage input HUNG (timeout)"; exit 1; }
[ "$rc" -ne 139 ] || { echo "FAIL: garbage input SIGSEGV'd (139)"; exit 1; }
[ "$rc" -ne 0 ] || { echo "FAIL: garbage input compiled clean (exit 0)"; exit 1; }
[ ! -s "$O" ] || { echo "FAIL: garbage input emitted output"; exit 1; }

# 2b) v6.4.78 — TRUNCATED input must not spew. `TOKTYP` is an unchecked L64, so past
#     GTCNT it returned zeroed heap = token type 0, never 12 (EOF). Every `t == 12`
#     EOF test in _sync_skip and the block loops therefore failed silently, recovery
#     could never terminate normally, and PARSE_STMT's forced-progress guard was
#     disarmed too (it only advances while GTI < GTCNT). Result: **166,670** stderr
#     lines before the v6.4.62 watchdog aborted. Case 2 above did NOT catch this —
#     its garbage happens to end in a way that recovers — so the shape that matters
#     is input ending MID-CONSTRUCT. Fixed by clamping PEEKT to EOF past GTCNT,
#     inside the existing `_had_error` guard (zero hot-path cost).
#     Bound is generous (200) so it fails on a 166K regression, not on message churn.
#     (issues/2026-07-24-truncated-input-166k-line-error-cascade.md)
for _trunc in 'include "lib/syscalls.cyr"\nvar x = f64_sqrt' \
              'include "lib/syscalls.cyr"\nfn f() { var a = iv_add;\n' \
              'include "lib/syscalls.cyr"\nvar y = 1 +' \
              'include "lib/syscalls.cyr"\nvar z = f64_to(1'; do
    printf '%b' "$_trunc" > "$T"
    rc=0; timeout 30 "$CC" < "$T" > "$O" 2>"$E" || rc=$?
    [ "$rc" -ne 124 ] || { echo "FAIL: truncated input HUNG: $_trunc"; exit 1; }
    [ "$rc" -ne 139 ] || { echo "FAIL: truncated input SIGSEGV'd: $_trunc"; exit 1; }
    _n=$(wc -l < "$E")
    [ "$_n" -le 200 ] || { echo "FAIL: truncated input produced $_n stderr lines (want <=200) for: $_trunc"; head -3 "$E"; exit 1; }
    grep -q 'recovery aborted' "$E" && { echo "FAIL: watchdog fired on truncated input — the desync spin is back: $_trunc"; exit 1; }
    [ ! -s "$O" ] || { echo "FAIL: truncated input emitted output"; exit 1; }
done

# 3) VALID input still compiles + emits (no false positive).
printf 'fn main(): i64 { return 42; }\n' > "$T"
"$CC" < "$T" > "$O" 2>/dev/null || { echo "FAIL: valid program failed to compile"; exit 1; }
[ -s "$O" ] || { echo "FAIL: valid program emitted no output"; exit 1; }

echo "PASS: dx multi-error — N>=2 errors, no output on error, no crash/hang on garbage, truncated input bounded (<=200 lines, no watchdog), valid emits"
exit 0
