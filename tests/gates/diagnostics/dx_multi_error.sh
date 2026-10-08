#!/bin/sh
# v6.4.62 (DX multi-error): assert cycc reports MULTIPLE errors per compile (panic-mode
# recovery) instead of fail-fast, emits NO output on error, exits non-zero, and never
# crashes/hangs on malformed input. Guards the _panic/_sync_skip mechanism, the
# _had_error output gate (EMITELF x2 + cx) + per-fork exit, and the PEEKT anti-hang
# watchdog. (Robustness vs byte-mutated input is the VR-02 parser-fuzz gate's job.)
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: dx_multi_error: cannot cd to $ROOT"; exit 1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
T=$(mktemp) && [ -f "$T" ] || { echo "FAIL: dx_multi_error: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: dx_multi_error: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
O=$(mktemp) && [ -f "$O" ] || { echo "FAIL: dx_multi_error: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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
#    ⚠ 6.6.10: the fixture was `var x = @@@ ][ }} return`, and it only exercised the
#    PARSER because the lexer silently dropped a stray `@` (the dropped-at-sign lexer bug). With `@` refused at
#    the lexer, `@@@` exits before one token reaches the parser and the case would pass
#    without testing recovery at all — so the `@@@` is gone, and the last row proves the
#    diagnostic comes from the parser, not the lexer. CHANGELOG [6.6.10]
printf 'fn main(): i64 { var x = ][ }} return' > "$T"
rc=0; timeout 10 "$CC" < "$T" > "$O" 2>"$E" || rc=$?
[ "$rc" -ne 124 ] || { echo "FAIL: garbage input HUNG (timeout)"; exit 1; }
[ "$rc" -ne 139 ] || { echo "FAIL: garbage input SIGSEGV'd (139)"; exit 1; }
[ "$rc" -ne 0 ] || { echo "FAIL: garbage input compiled clean (exit 0)"; exit 1; }
[ ! -s "$O" ] || { echo "FAIL: garbage input emitted output"; exit 1; }
grep -q 'unexpected character' "$E" && { echo "FAIL: garbage input stopped in the LEXER — case 2 no longer reaches parser recovery:"; cat "$E"; exit 1; }

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
#     (issues/archived/2026-07-24-truncated-input-166k-line-error-cascade.md)
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

# 2c) v6.6.4 — a diagnostic that is followed by MORE EMISSION must not crash the
#     compiler: a capturing closure without lib/alloc.cyr reported correctly and then
#     fell through to `ECALLFIX(S, -1)`, a SIGSEGV on the cx fork after a correct
#     error line (x86 happened to survive the same -1). Run through the cx compiler
#     built from the working tree, since that is where it faulted.
CX=$(mktemp) && [ -f "$CX" ] || { echo "FAIL: dx_multi_error: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -f "$T" "$E" "$O" "$CX"' EXIT
cat "$ROOT/src/main_cx.cyr" | "$CC" > "$CX" 2>/dev/null && chmod +x "$CX" || { echo "FAIL: could not build the cx fork"; exit 1; }
printf 'fn main(): i64 { var k = 3; var f = |x| x + k; return callptr(f, 1); }\nvar r = main();\nsyscall(60, r);\n' > "$T"
for _cc in "$CC" "$CX"; do
    rc=0; timeout 30 "$_cc" < "$T" > "$O" 2>"$E" || rc=$?
    [ "$rc" -ne 139 ] || { echo "FAIL: closure-without-alloc SIGSEGV'd after its diagnostic ($_cc)"; exit 1; }
    [ "$rc" -ne 0 ] || { echo "FAIL: closure-without-alloc compiled clean ($_cc)"; exit 1; }
    grep -q 'a capturing closure needs include' "$E" || { echo "FAIL: closure-without-alloc lost its diagnostic ($_cc)"; cat "$E"; exit 1; }
    [ ! -s "$O" ] || { echo "FAIL: closure-without-alloc emitted output ($_cc)"; exit 1; }
done

# 2d) 6.6.10 — a bare `#deprecated` must not clear a panic latch it did not set. An
#     earlier, unresynced error (the struct field) already held the latch, so ERR_MSG
#     swallowed the directive's own error — and the unconditional `_panic = 0` after it
#     un-suppressed the struct error's cascade: 2 errors ('expected identifier', then
#     "unexpected ')'") for one mistake. Exactly 1 now.
printf 'struct Q { a; b: ; }\n#deprecated ) )\nfn f(): i64 { return 1; }\nsyscall(60, f());\n' > "$T"
rc=0; "$CC" < "$T" > "$O" 2>"$E" || rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: struct error + bare #deprecated compiled clean"; exit 1; }
n=$(grep -c '^error:' "$E" || true)
[ "$n" -eq 1 ] || { echo "FAIL: struct error + bare #deprecated reported $n errors, want 1 (the latch was cleared):"; cat "$E"; exit 1; }

# 3) VALID input still compiles + emits (no false positive).
printf 'fn main(): i64 { return 42; }\n' > "$T"
"$CC" < "$T" > "$O" 2>/dev/null || { echo "FAIL: valid program failed to compile"; exit 1; }
[ -s "$O" ] || { echo "FAIL: valid program emitted no output"; exit 1; }

echo "PASS: dx multi-error — N>=2 errors, no output on error, no crash/hang on garbage, truncated input bounded (<=200 lines, no watchdog), error-then-emit does not fault (x86 + cx), valid emits"
exit 0
