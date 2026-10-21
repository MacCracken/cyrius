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
    rc=0; timeout 30 env ${KENV:-} "${KCC:-$CC}" < "$T" > "$O" 2>"$E" || rc=$?
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
# Z1-Z8 (6.7.16, issues/2026-10-18-zone-replay-reports-only-first-latched-error.md) — THE DECLARATION ZONE REPORTS ONE ERROR
#     PER DECLARATION, as a fn's statements do. EMIT_GVAR_INITS replayed its entries without releasing the panic latch,
#     so the first latched error swallowed every later entry's: Z1 (the filed repro, verbatim) printed only 2:13, Z2 one
#     "unknown struct field", Z3 one "expected ','", Z4 (a destructure's zone check between two others) one, Z8 (a bad
#     declaration between good ones) one. Controls: Z5 one bad declaration is one error; Z6 the pair after a first
#     statement (PARSE_VAR: a statement each, two before too); Z7 a vector-call pair (its refusal latches nothing: two
#     before too). RED with the latch clear reverted (6.7.16's 7965f3685 as CYCC): Z1-Z4 Z8.
ZG='fn g(): i64 { return 1; }\n'
ZP='struct P { a; b; }\n'
cascade Z1 2 "$ZG"'var p = g(1 2);\nvar q = g(3 4);\nsyscall(60, 0);\n' "2:13: expected ')', got number 2" "3:13: expected ')', got number 4"
cascade Z2 2 "$ZP"'var p = P { c: 1, b: 2 };\nvar q = P { d: 1, b: 2 };\nsyscall(60, 0);\n' "2:16: unknown struct field in initializer" "3:16: unknown struct field in initializer"
cascade Z3 2 "$ZP"'var p = P { 3 4 };\nvar q = P { 5 6 };\nsyscall(60, 0);\n' "2:15: expected ',' between struct literal elements" "3:15: expected ',' between struct literal elements"
cascade Z4 3 "$ZG"'fn h(): i64 { return 1; }\nvar p = g(1 2);\nvar a, b = h();\nvar q = g(3 4);\nsyscall(60, 0);\n' "3:13: expected ')', got number 2" "4:12: multi-value destructure binds 2 names, but 'h' returns 1 value" "5:13: expected ')', got number 4"
cascade Z5 1 "$ZG"'var p = g(1 2);\nvar q = 5;\nsyscall(60, q);\n' "2:13: expected ')', got number 2"
cascade Z6 2 "$ZG"'syscall(39);\nvar p = g(1 2);\nvar q = g(3 4);\nsyscall(60, 0);\n' "3:13: expected ')', got number 2" "4:13: expected ')', got number 4"
cascade Z7 2 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }\nstruct S { k; }\nimpl S { fn mv(self): f64v2 { return mkv(41, 7); } }\nvar s: S = S { 1 };\nvar w = mkv(41, 7);\nvar v = s.mv();\nsyscall(60, 0);\n' "5:9: 'mkv' returns a vector by value" "6:9: 'mv' returns a vector by value"
cascade Z8 2 "$ZG"'var a = 1;\nvar p = g(1 2);\nvar b = 2;\nvar q = g(3 4);\nvar c = 3;\nsyscall(60, a + b + c);\n' "3:13: expected ')', got number 2" "5:13: expected ')', got number 4"
# Z9-Z13 (6.7.16, issues/2026-10-20-zone-replay-last-entry-latch-swallows-first-statement-error.md) — THE ZONE'S LAST
#     ENTRY'S LATCH NO LONGER SWALLOWS THE FIRST STATEMENT'S ERROR. EMIT_GVAR_INITS ends with the latch as it found it
#     (pass 2's silent re-read of a refused declaration), so an entry's latch is released before PARSE_PROG while the
#     re-read's keeps PARSE_PROG from reporting that declaration twice. Z9 (the filed repro, verbatim) printed 2:13 and
#     4:12 only; Z10 / Z11 (const_checked.sh M1 and enum_member_separator.sh S8 behind a zone entry) and Z12 (a
#     destructure as the last entry) stay one error each / the first statement's own; Z13 the repro in a `kernel;` build
#     (CYRIUS_ELF64_KERNEL=1: the replay runs after PARSE_PROG). Each on the x86_64, aarch64, cx and PE compilers built
#     from this tree (one front end). RED with the restore reverted: Z9 on every leg. Clearing the latch outright at the
#     replay's end (5d2c35caf, reverted): Z10 / Z11 two errors.
A64C=$(mktemp) && [ -f "$A64C" ] || { echo "FAIL: dx_multi_error: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
PEC=$(mktemp) && [ -f "$PEC" ] || { echo "FAIL: dx_multi_error: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -f "$T" "$E" "$O" "$CX" "$A64C" "$PEC"' EXIT
cat "$ROOT/src/main_aarch64.cyr" | "$CC" > "$A64C" 2>/dev/null && chmod +x "$A64C" || { echo "FAIL: could not build the aarch64 fork"; exit 1; }
cat "$ROOT/src/main_win.cyr" | "$CC" > "$PEC" 2>/dev/null && chmod +x "$PEC" || { echo "FAIL: could not build the PE fork"; exit 1; }
# cascade_legs <label> <want> <file> <head>... — `cascade` on each leg.
cascade_legs() {
    _zl=$1; _zw=$2; _zf=$3; shift 3
    for _lg in x86 a64 cx pe; do
        case $_lg in x86) KCC=$CC ;; a64) KCC=$A64C ;; cx) KCC=$CX ;; pe) KCC=$PEC ;; esac
        cascade "$_zl $_lg" "$_zw" "$_zf" "$@"
    done
    KCC=
}
cascade_legs Z9 3 "$ZG"'var p = g(1 2);\nsyscall(60 0);\nsyscall(60 1);\n' "2:13: expected ')', got number 2" "3:12: expected ')', got number 0" "4:12: expected ')', got number 1"
cascade_legs Z10 1 'var a = 1;\nconst X;\nsyscall(60, 1);\n' "2:8: expected '=', got ';'"
cascade_legs Z11 1 'var a = 1;\nenum E { A 5 }\nsyscall(60, E.A);\n' "2:12: expected identifier, got number 5"
cascade_legs Z12 3 'fn h(): i64 { return 1; }\nvar a = 1;\nvar c, b = h();\nsyscall(60 0);\nsyscall(60 1);\n' "3:12: multi-value destructure binds 2 names, but 'h' returns 1 value" "4:12: expected ')', got number 0" "5:12: expected ')', got number 1"
KENV=CYRIUS_ELF64_KERNEL=1
cascade Z13 3 'kernel;\n'"$ZG"'var p = g(1 2);\nsyscall(60 0);\nsyscall(60 1);\n' "3:13: expected ')', got number 2" "4:12: expected ')', got number 0" "5:12: expected ')', got number 1"
KENV=
# G1-G2 (6.7.16, met beside issues/2026-10-20-wide-struct-if-expression-branch-refusal-cascades-at-variable-use.md) —
#     AN UNINITIALIZED VECTOR GLOBAL IN THE ZONE IS ONE ERROR. G1 `var V: f64v2;` was two errors at 1:13: pass 1's
#     "vector global 'V' takes no initializer but 0" (for no initializer at all) and the replay's "uninitialized
#     variable not allowed"; pass 1 now judges only an initializer that is there. G2 (control) a vector global
#     initialised to 5 keeps its own refusal. RED on the lane before this bite: G1 (2 errors).
GU="uninitialized variable not allowed; use \`var X = 0;\` or initial value"
cascade_legs G1 1 'var V: f64v2;\nsyscall(60, 0);\n' "1:13: $GU"
cascade_legs G2 1 'var V: f64v2 = 5;\nsyscall(60, 0);\n' "1:14: vector global 'V' takes no initializer but 0"
# L1-L14 (6.7.16, issues/2026-10-20-literal-of-undeclared-struct-name-cascades-expected-semicolon.md) — A STRUCT LITERAL
#     WHOSE NAME IS NOTHING (no struct, variable or fn) IS ONE ERROR, AT THE NAME. `var x = Q { 1 };` was "undefined
#     variable 'Q'" and then "expected ';', got '{'"; in a fn the resync stopped inside the braces ("unexpected ';'",
#     "unexpected '}'", "return outside a fn body"). Where the literal stands whole in a value place — a declaration's
#     initializer (any balanced wrap), an assignment, `return`, an argument — the name is reported once as before, the
#     `{ .. }` stepped, and a declared variable marked so `x.a` stands down (`_slit_undecl`; the zone sweep's `_gu_slit0`
#     for a fn body compiled before the replay). L1 the top-level repro verbatim (2:11 and 3:11); L2 the fn repro verbatim
#     — 3:15, and line 4's `var y = P { 2 };` (P has two fields) keeps its OWN refusal, a positional literal short of a
#     field (4:19, "missing struct field in initializer" since 6.7.16; "unexpected '}'" before); L3 after the first statement; L4 wrapped, `Q<i64> { .. }`, named elements, `x.a = 2`, `x.m()`; L5 an
#     assignment, L6 `return`, L7 an argument; L8 the zone global read in a fn body before the replay; L9 an annotation
#     naming Q (`var x: Q = Q { 1 };`: the annotation's one error). Controls: L10 `match nn { .. }` (nn nothing) keeps
#     "undefined variable 'nn'" and parses its body; L11 `var x = 5;` then `x.a` keeps its own error; L12 a declared
#     struct's literal compiles. L13 --syntax-only (a sibling file's struct): no error — it was a false "expected ';',
#     got '{'". RED on the lane before this bite: L1-L9 (L2: five errors), L13.
SQ="undefined variable 'Q' (missing include or enum?)"
cascade_legs L1 2 'struct P { a; }\nvar x = Q { 1 };\nvar y = R { 2 };\nsyscall(60, 0);\n' "2:11: $SQ" "3:11: undefined variable 'R'"
cascade_legs L2 2 'struct P { a; b; }\nfn f(): i64 {\n    var x = Q { 1 };\n    var y = P { 2 };\n    return 0;\n}\nsyscall(60, f());\n' "3:15: $SQ" "4:19: missing struct field in initializer"
cascade_legs L3 1 'var z = 1;\nz = 2;\nvar x = Q { 1 };\nsyscall(60, x.a);\n' "3:11: $SQ"
cascade_legs L4 1 'fn f(): i64 {\n    var x = (Q<i64> { a: 1, b: 2 });\n    x.a = 2;\n    x.m();\n    return x.a;\n}\nsyscall(60, f());\n' "2:15: $SQ"
cascade_legs L5 1 'fn f(): i64 { var x = 0; x = Q { 1 }; return x; }\nsyscall(60, f());\n' "1:32: $SQ"
cascade_legs L6 1 'fn f(): i64 { return Q { 1 }; }\nsyscall(60, f());\n' "1:24: $SQ"
cascade_legs L7 1 'fn g(a, b): i64 { return a; }\nfn f(): i64 { return g(Q { 1 }, 2); }\nsyscall(60, f());\n' "2:26: $SQ"
cascade_legs L8 1 'var x = Q { 1 };\nfn f(): i64 { return x.a; }\nsyscall(60, f() + x.a);\n' "1:11: $SQ"
cascade_legs L9 1 'fn f(): i64 { var x: Q = Q { 1 }; return x.a; }\nsyscall(60, f());\n' "1:22: unknown type 'Q' for variable 'x'"
cascade_legs L10 1 'fn f(): i64 {\n    match nn { 5 => { return 1; } _ => { return 2; } }\n    return 0;\n}\nsyscall(60, f());\n' "2:14: undefined variable 'nn'"
cascade_legs L11 1 'var x = 5;\nfn f(): i64 { return x.a; }\nsyscall(60, f());\n' "2:25: no struct type in scope for 'x'"
printf 'struct Q { a; }\nfn f(): i64 { var x = Q { 41 }; return x.a + 1; }\nsyscall(60, f());\n' > "$T"
rc=0; "$CC" < "$T" > "$O" 2>"$E" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$O" ]; then echo "FAIL: L12: a declared struct's literal did not compile:"; cat "$E"; kfail=$((kfail + 1))
else chmod +x "$O"; rc=0; "$O" || rc=$?; [ "$rc" -eq 42 ] || { echo "FAIL: L12: exit $rc, want 42"; kfail=$((kfail + 1)); }; fi
for _sl in 'var x = Q { 1 };\nsyscall(60, x.a);\n' 'fn f(): i64 { var x = Q { 1 }; return x.a; }\nsyscall(60, f());\n'; do
    printf '%b' "$_sl" > "$T"
    rc=0; "$CC" --syntax-only < "$T" > "$O" 2>"$E" || rc=$?
    if [ "$rc" -ne 0 ] || grep -q '^error' "$E"; then echo "FAIL: L13: --syntax-only refused a sibling struct's literal ($_sl):"; cat "$E"; kfail=$((kfail + 1)); fi
done
[ "$kfail" -eq 0 ] || { echo "FAIL: dx_multi_error: $kfail cascade row(s) red (K1-K16, Z1-Z13, G1-G2, L1-L13)"; exit 1; }

# 3) VALID input still compiles + emits (no false positive).
printf 'fn main(): i64 { return 42; }\n' > "$T"
"$CC" < "$T" > "$O" 2>/dev/null || { echo "FAIL: valid program failed to compile"; exit 1; }
[ -s "$O" ] || { echo "FAIL: valid program emitted no output"; exit 1; }

echo "PASS: dx multi-error — N>=2 errors, no output on error, no crash/hang on garbage, truncated input bounded (<=200 lines, no watchdog), error-then-emit does not fault (x86 + cx), one mistake one error (K1-K16), one error per declaration-zone declaration (Z1-Z8), the zone's last latch released for the first statement on x86_64 / aarch64 / cx / PE and in a kernel build (Z9-Z13), an uninitialized vector global in the zone one error (G1-G2), a struct literal whose name is nothing one error at the name (L1-L13), valid emits"
exit 0
