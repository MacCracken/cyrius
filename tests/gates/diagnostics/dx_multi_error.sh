#!/bin/sh
# v6.4.62 (DX multi-error): assert cycc reports MULTIPLE errors per compile (panic-mode
# recovery) instead of fail-fast, emits NO output on error, exits non-zero, and never
# crashes/hangs on malformed input. Guards the _panic/_sync_skip mechanism, the
# _had_error output gate (EMITELF x2 + cx) + per-fork exit, and the PEEKT anti-hang
# watchdog. (Robustness vs byte-mutated input is the VR-02 parser-fuzz gate's job.)
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: dx_multi_error: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
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

# 2e) 6.7.14 — one mistake, one error (issues/archived/2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md).
#     Each case prints EXACTLY the errors listed — `cascade <label> <want error count> <file> <head>...`
#     names every `error:` head it must print (after `error:<source>:`), and any other `error:`
#     or `warning:` line is a cascade. Before 6.7.14:
#     K1 a const fn's unknown name: the definition check's "unknown name 't' in a const context",
#        then the run-time compile of the same body's "undefined variable 't'" one column on (K2
#        `nosuch`, K3 `t = 1;`). K4 control: a second, different unknown name `u` is still reported.
#     K5-K10 an unclosed call: the `)` miss stepped the `;`, the statement's `;` check stepped
#        the `for` / `while`, and the resync re-entered inside its header ("expected '=', got
#        '<'", "return outside a fn body"); `g(1;` added "'g' expects 2 arguments, got 1"; an
#        unclosed `syscall(39, 0;` added "syscall arity mismatch".
#     K11 a method-call for step: the step went on to compile `inc()` as a FREE call, so the
#        end of the compile added "undefined function 'inc'" twice and "refusing to emit binary";
#        the one error now carries a note naming the rule. K12 a free-call step `f()`: it added a
#        false "undefined variable 'f'"; one error and the note. K13 control: a bare-name step `i`
#        is one error with no note (no call).
#     RED on 87ef0dd9 (the lane before this bite): K1-K12 (K4 printed the duplicate 't' too).
kfail=0
cascade() {
    _cl=$1; _cw=$2; _cf=$3; shift 3
    printf '%b' "$_cf" > "$T"
    rc=0; timeout 30 "$CC" < "$T" > "$O" 2>"$E" || rc=$?
    [ "$rc" -eq 1 ] || { echo "FAIL: $_cl: rc $rc, want 1"; cat "$E"; kfail=$((kfail + 1)); return 0; }
    _cn=$(grep -c '^error' "$E" || true)
    _wn=$(grep -c '^warning' "$E" || true)
    if [ "$_cn" -ne "$_cw" ] || [ "$_wn" -ne 0 ]; then
        echo "FAIL: $_cl: $_cn error(s) + $_wn warning(s), want $_cw + 0:"; grep '^error\|^warning' "$E"
        kfail=$((kfail + 1)); return 0
    fi
    for _ch in "$@"; do
        grep -qF "error:<source>:$_ch" "$E" || { echo "FAIL: $_cl: no 'error:<source>:$_ch':"; grep '^error' "$E"; kfail=$((kfail + 1)); return 0; }
    done
    return 0
}
KF='fn main() { return 0; }\nvar r = main();\n'
cascade K1 1 'const fn f(n) {\n    if (n > 0) { var t = 1; }\n    return t;\n}\n'"$KF" "3:12: unknown name 't' in a const context"
cascade K2 1 'const fn f(n) {\n    return n + nosuch;\n}\n'"$KF" "2:16: unknown name 'nosuch' in a const context"
cascade K3 1 'const fn f(n) {\n    t = 1;\n    return 0;\n}\n'"$KF" "2:5: 't' is not a local of this const fn"
cascade K4 2 'const fn f(n) {\n    return n + t + u;\n}\n'"$KF" "2:16: unknown name 't' in a const context" "2:21: undefined variable 'u'"
KG='fn g(a, b) { return a + b; }\nfn main() {\n    var x = 0;\n'
KL='    for (var i = 0; i < 3; i = i + 1) { x = x + 1; }\n    return x;\n}\nvar r = main();\n'
KW='    while (x < 3) { x = x + 1; }\n    return x;\n}\nvar r = main();\n'
cascade K5 1 "$KG"'    g(1, 2;\n'"$KL" "4:11: expected ')', got ';'"
cascade K6 1 "$KG"'    g(1, 2;\n'"$KW" "4:11: expected ')', got ';'"
cascade K7 1 "$KG"'    var y = g(1, 2;\n'"$KW" "4:19: expected ')', got ';'"
cascade K8 1 "$KG"'    g(1;\n'"$KL" "4:8: expected ')', got ';'"
cascade K9 1 "$KG"'    var y = syscall(39, 0;\n'"$KL" "4:26: expected ')', got ';'"
cascade K10 1 "$KG"'    syscall(39, 0;\n'"$KL" "4:18: expected ')', got ';'"
cascade K11 1 'struct C { n; }\nimpl C { fn inc(self) { self.n = self.n + 1; return 0; } }\nfn main() {\n    var c = C { 0 };\n    for (var i = 0; c.n < 3; c.inc()) { i = i + 1; }\n    return c.n;\n}\nvar r = main();\n' "5:31: expected '=', got '.'"
grep -q "note: a for step is an assignment" "$E" || { echo "FAIL: K11: the note naming the rule is missing"; kfail=$((kfail + 1)); }
grep -q "undefined function\|refusing to emit" "$E" && { echo "FAIL: K11: the step's call reached the undefined-function check"; kfail=$((kfail + 1)); }
KS='fn f(): i64 { return 0; }\nfn go(): i64 {\n    var i = 0;\n'
cascade K12 1 "$KS"'    for (i = 0; i < 3; f()) { i = i + 1; }\n    return i;\n}\nvar r = go();\n' "4:25: expected '=', got '('"
grep -q "note: a for step is an assignment" "$E" || { echo "FAIL: K12: the note naming the rule is missing"; kfail=$((kfail + 1)); }
cascade K13 1 "$KS"'    for (i = 0; i < 3; i) { i = i + 1; }\n    return i;\n}\nvar r = go();\n' "4:25: expected '=', got ')'"
grep -q "note: a for step" "$E" && { echo "FAIL: K13: a bare-name step got the call note"; kfail=$((kfail + 1)); }
# K14-K16 (6.7.14, found beside the const-field fix) — a `.field` / `.m(..)` on a name declared nowhere is
#     "undefined variable 't'" once: its `sid == 0` arm added "no struct type in scope for 't'; ...
#     (missing include?)" for the same base. The next statement still reports its own (K15's `u`).
#     RED on 90883a62: K14-K16.
KU='struct P { x; }\nfn main() {\n'
cascade K14 1 "$KU"'    t.x = 1;\n    return 0;\n}\nvar r = main();\n' "3:9: undefined variable 't'"
cascade K15 2 "$KU"'    t.x += 1;\n    var v = u.x;\n    return v;\n}\nvar r = main();\n' "3:9: undefined variable 't'" "4:16: undefined variable 'u'"
cascade K16 1 "$KU"'    t.m(1);\n    return 0;\n}\nvar r = main();\n' "3:8: undefined variable 't'"
[ "$kfail" -eq 0 ] || { echo "FAIL: dx_multi_error: $kfail cascade row(s) red (K1-K16)"; exit 1; }

# 3) VALID input still compiles + emits (no false positive).
printf 'fn main(): i64 { return 42; }\n' > "$T"
"$CC" < "$T" > "$O" 2>/dev/null || { echo "FAIL: valid program failed to compile"; exit 1; }
[ -s "$O" ] || { echo "FAIL: valid program emitted no output"; exit 1; }

echo "PASS: dx multi-error — N>=2 errors, no output on error, no crash/hang on garbage, truncated input bounded (<=200 lines, no watchdog), error-then-emit does not fault (x86 + cx), one mistake one error (K1-K16), valid emits"
exit 0
