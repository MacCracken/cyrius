#!/bin/sh
# tests/gates/frontend/loop_do_checked.sh — 6.7.5 (B5)
#
# `loop { … }` AND `do { … } while (c);`. The user's decisions (2026-10-08): `loop` is CONTEXTUAL —
# the loop statement only as `loop {` at the start of a statement, an identifier everywhere else (the
# `kernel` precedent; 215 `var loop` flags in six ecosystem repos keep compiling); `do` is a FULL
# reserved word (token 172). `loop` is a statement only and `break` takes no value. A `continue` in a
# `do` goes to the CONDITION. The do body is its own scope: the condition does not see its `var`s.
# Both join the const fn pure subset under the existing step budget. The runtime half is
# tests/tcyr/crossos/loop_do_values.tcyr; the in-loop tail-call verdicts (a do's condition included)
# are tests/tcyr/crossos/tailcall_loop_frame_address.tcyr.
#
#   R  refused once, by name, at the right token
#   K  CONTEXTUAL: `loop` as an identifier still compiles and runs (a var, a fn, a field, a struct,
#      a closure's enclosing local)
#   W  `#inline` on a body holding a `loop` / `do` is ignored by name, and the call is a call
#   C  const fn: loop / do run by the compile-time evaluator in every const context (R10-R14 are
#      its refusals: the step budget, the evaluator's if-expression arm, the definition check)
#   A  ANTI-VACUOUS: the crossos tcyr built and run — x86 under CYRIUS_IR=3 and CYRIUS_DCE=1, then
#      aarch64 (qemu), cx (cxvm) and PE (wine), each with the full assertion count; an x86
#      disassembly row (a `loop` emits no condition test at its top)
#
# MUTATION LEDGER (2026-10-08; each a one-edit scratch COPY of the tree, its build/cycc rebuilt from
# the mutated src, then this gate and the two crossos tcyrs run from the copy):
#   L1  `_loop_open` without the continue-mode zeroing   -> A1-A6 (tcyr N1, continue in a loop inside
#                                                          a for: 0, want 9)
#   L2  `_loop_open` without the `_efl_store_cp` reset    -> A1-A3, A6, K4, W2: the x86 / PE loops
#                                                          never end (timeout); aarch64 / cx have no
#                                                          reload elimination
#   L4  PARSE_DO with continue mode 0 (to the top)        -> A1-A6 (tcyr D2, the discriminator: 5)
#   L5  `_tcp_loop_end` stamped before a do's condition   -> gate green; the tailcall tcyr's `d_cond`
#                                                          RED (904, the freed frame) — check.sh's
#                                                          tcyr suite and the release gate's hosts
#   L5' `_tcp_loop_end` dropped after loop / do           -> the tailcall tcyr: the loop / do kept rows
#                                                          RED and `after_do` overflows (139)
#   L6  `_loop_open` without the IR_NOP pad               -> A2 (CYRIUS_IR=3: SIGSEGV, 139)
#   L7  the inline-scan line dropped                      -> W1's warning row (the replay itself turns
#                                                          a `return` into a jump to the replay's end,
#                                                          so the value stays 76 — the plan's "leaves
#                                                          the CALLER" did not reproduce)
#   L10 `_ie_stmt_tok` without 172                        -> R6 ("unexpected do")
#   L11 `_ie_stmt_at` without the `loop {` test           -> R5 ("undefined variable 'loop'")
#   L12 `_cl_prescan_ident` without the `loop {` skip     -> K4 (113: the closure captured `loop`)
#   L13 the dispatch's `loop {` arm dropped               -> R7 R9 K4 W1 A1-A7 (every `loop` is an
#                                                          identifier statement again)
#   L8  `_ce_stmt`'s `_ce_loopx` arm dropped              -> R13 R14 C1 A1-A6 ("unknown name 'loop'
#                                                          in a const context" / "not in a const fn")
#   L9  `_ce_do` not walking the condition after a break  -> C1 A1-A6 (the cursor stops at `(`:
#                                                          "expected ';', got '('")
#   L14 `_ce_xarm` back on `_ie_stmt_tok` (no `loop {`)   -> R12 ("unknown name 'loop'")
# Defensive, no killing row (named): the `_flags_reflect_rax` resets at a loop / do top and after
# the do's `_cont_close` (every condition and statement emits a defining instruction first), and
# `_sync_skip`'s stops at `do` / `loop {` (an error inside a call's argument list before a loop is a
# cascade today for `while` too — rec rows probed, no change).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: loop_do_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: loop_do_checked: mktemp -d failed"; exit 1; }
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
build() { rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
E='\nsyscall(60, f(1));\n'
STMT="takes one expression, not a statement"

refused r01 "reserved keyword 'do'" "R1: fn do() — \`do\` is reserved" 'fn do(): i64 { return 0; }\nsyscall(60, 0);\n'
refused r02 "reserved keyword 'do'" "R2: a field named do" 'struct H { do; }\nsyscall(60, 0);\n'
refused r03 "expected ';', got return" "R3: do … while (c) with no ';'" "fn f(c): i64 { var i = 0; do { i = i + 1; } while (i < 3) return i; }$E"
refused r04 "expected while, got return" "R4: do { } with no while" "fn f(c): i64 { var i = 0; do { i = i + 1; } return i; }$E"
refused r05 "$STMT" "R5: a loop as an if-expression branch" "fn f(c): i64 { var x = if (c) { loop { break; } } else { 1 }; return x; }$E"
refused r06 "$STMT" "R6: a do as an if-expression branch" "fn f(c): i64 { var x = if (c) { do { } while (c == 0); } else { 1 }; return x; }$E"
refused r07 "expected ';', got number 5" "R7: break takes no value" "fn f(c): i64 { var i = 0; loop { i = i + 1; if (i > 3) { break 5; } } return i; }$E"
refused r08 "undefined variable 't'" "R8: the do condition does not see the body's var" "fn f(c): i64 { var i = 0; do { var t = 1; i = i + t; } while (t < 3); return i; }$E"
refused r09 "continue outside a loop" "R9: a closure's continue does not reach the enclosing loop" "fn f(c): i64 { var i = 0; loop { var g = |x| { continue; }; i = i + 1; if (i > 2) { break; } } return i; }$E"

BUDGET="compile-time evaluation exceeded 10,000,000 steps"
refused r10 "$BUDGET" "R10: an endless loop in a const fn, run in a const context" 'const fn spin(n) { loop { n = n + 1; } return n; }\nconst X = spin(1);\nsyscall(60, X);\n'
refused r11 "$BUDGET" "R11: an endless do in a const fn, run in a const context" 'const fn spin2(n) { do { n = n + 1; } while (n > 0); return n; }\nconst X = spin2(1);\nsyscall(60, X);\n'
refused r12 "$STMT" "R12: a loop as a const-context if-expression branch (the evaluator's arm)" 'const X = if (1) { loop { break; } } else { 1 };\nsyscall(60, X);\n'
refused r13 "not in a const fn: its body takes var / const / assignment / if / elif / else / while / for / loop / do-while" "R13: a loop body is checked at the definition (store64 in it)" 'const fn bad(n) { loop { store64(n, 1); break; } return n; }\nsyscall(60, 0);\n'
# The const fn variant of R8. ⚠ Reported TWICE (the definition check, then the parser), exactly as an
# `if` body's `var` read after its `}` is today — a pre-existing double report, filed, not this row's
# subject; the row pins the evaluator's half by name.
printf 'const fn g(n) { var i = 0; do { var t = 1; i = i + t; } while (t < 3); return i + n; }\nconst X = g(1);\nsyscall(60, X);\n' > "$T/r14.cyr"
build r14
if [ "$rc" -ne 0 ] && grep -qF "unknown name 't' in a const context" "$T/r14.err"; then ok "R14: a const fn's do condition does not see the body's var (refused by the evaluator)"
else bad "R14: rc $rc: $(grep '^error' "$T/r14.err" | head -1)"; fi
exits c01 0 "C1: loop / do const fns in every const context — consts, an array size, #assert, a case label — equal to the same fns at run time" 'const fn tri(n) { var s = 0; var i = 0; loop { i = i + 1; if (i > n) { break; } s = s + i; } return s; }\nconst fn cnt(n) { var i = 0; do { i += 1; if (i < 5) { continue; } } while (i < n); return i; }\nconst fn once(n) { var k = 0; do { k = k + 10; } while (0 == 1); return k + n; }\nconst fn brk(n) { var i = 0; do { i = i + 1; if (i == 2) { break; } } while (i < n); return i * 100 + n; }\nconst fn retl(n) { var i = 0; loop { i = i + 1; if (i * i > n) { return i; } } }\nconst fn retd(n) { var i = 0; do { i = i + 1; if (i == n) { return i * 7; } } while (i < 100); return 0; }\nconst A = tri(4);\nconst B = cnt(3);\nconst C = once(5);\nconst D = brk(9);\nconst E = retl(50);\nconst F = retd(3);\nvar arr: i64[tri(3)];\n#assert tri(5) == 15, "tri"\nfn main(): i64 {\n    var s = 0;\n    switch (6) { case tri(3): s = 1; default: s = 2; }\n    if (A != 10) { return 1; }\n    if (B != 3) { return 2; }\n    if (C != 15) { return 3; }\n    if (D != 209) { return 4; }\n    if (E != 8) { return 5; }\n    if (F != 21) { return 6; }\n    if (s != 1) { return 7; }\n    arr[2] = 4; if (arr[2] != 4) { return 8; }\n    if (tri(4) != A || cnt(3) != B || once(5) != C) { return 9; }\n    if (brk(9) != D || retl(50) != E || retd(3) != F) { return 10; }\n    return 0;\n}\nsyscall(60, main());\n'

exits k01 30 "K1: kriya's \`var loop\` flag driving a while" "fn f(c): i64 { var loop = 1; var n = 0; while (loop == 1) { n = n + 1; if (n == 3) { loop = 0; } } return n * 10 + loop; }$E"
exits k02 47 "K2: \`loop\` without \`{\` is the identifier (assignments, reads, a call)" "fn loop(x): i64 { return x + 40; }\nfn f(c): i64 { var n = loop(3); var loop = 3; loop = loop + 1; loop += 0; return n + loop; }$E"
exits k03 56 "K3: a field and a struct named loop" 'struct loop { a; b; }\nstruct H { loop; n; }\nfn f(c): i64 { var p = loop { 2, 3 }; var h: H; h.loop = p.a * 20 + 6 * c; h.n = p.b; return h.loop + h.n * 2 + 4; }\nsyscall(60, f(1));\n'
# A capturing closure's value carries the env tag in bit 63; a closure that captures nothing is a
# plain fn pointer (tag 0). `loop {` in the body is the statement, not a read of the local `loop`.
exits k04 13 "K4: a closure's \`loop {\` does not capture an enclosing \`loop\` local (no env tag)" 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\nfn f(c): i64 { alloc_init(); var loop = 7; var g = |x| { var i = 0; loop { i = i + x; if (i > 5) { break; } } return i; }; return fncall1(g, 2) + loop + (g >> 63) * 100; }\nsyscall(60, f(1));\n'

printf 'var cran = 0;\n#inline\nfn g(a): i64 { loop { return a + 1; } }\nfn h(): i64 { var x = g(5); cran = 7; return x; }\nvar r = h();\nsyscall(60, cran * 10 + r);\n' > "$T/w01.cyr"
build w01
if [ "$rc" -ne 0 ]; then bad "W1: the #inline-with-loop probe did not build: $(grep '^error' "$T/w01.err" | head -1)"
else
    grep -q "#inline ignored: body has control flow" "$T/w01.err" && ok "W1: #inline on a body holding a loop is ignored by name" || bad "W1: no '#inline ignored: body has control flow' warning"
    chmod +x "$T/w01.bin"; got=0; timeout 10 "$T/w01.bin" || got=$?
    [ "$got" -eq 76 ] && ok "W1: ... and g's loop returns to h: exit 76" || bad "W1: exit $got, want 76"
fi
printf 'var cran = 0;\n#inline\nfn g(a): i64 { var i = 0; do { i = i + a; } while (i < 9); return i; }\nfn h(): i64 { var x = g(5); cran = 7; return x; }\nvar r = h();\nsyscall(60, cran * 10 + r);\n' > "$T/w02.cyr"
build w02
if [ "$rc" -ne 0 ]; then bad "W2: the #inline-with-do probe did not build"
else
    grep -q "#inline ignored: body has control flow" "$T/w02.err" && ok "W2: #inline on a body holding a do is ignored by name" || bad "W2: no warning for the do body"
    chmod +x "$T/w02.bin"; got=0; timeout 10 "$T/w02.bin" || got=$?
    [ "$got" -eq 80 ] && ok "W2: ... exit 80" || bad "W2: exit $got, want 80"
fi

# ── A: the crossos tcyr, every leg, with its full assertion count ────────────────────────────
TC="$ROOT/tests/tcyr/crossos/loop_do_values.tcyr"
WANT=$(grep -cE '^ *assert_eq\(' "$TC")
[ "$WANT" -ge 30 ] || bad "A0: only $WANT assertions derived from the tcyr (floor 30)"
tcyr_ok() {   # <label> <output file> <exit>
    if [ "$3" -eq 0 ] && grep -q "^$WANT passed, 0 failed" "$2"; then ok "$1: $WANT passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
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
        got=0; timeout 120 "$T/cxvm" < "$T/tc.cyx" > "$T/tc.cxout" 2>&1 || got=$?
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

# ── A7: x86 disassembly — `loop` tests no condition at its top; `while (1)` does ───────────────
if command -v objdump > /dev/null 2>&1; then
    printf 'fn wl(n): i64 { var i = 0; loop { i = i + 1; if (i == n) { break; } } return i; }\nfn ww(n): i64 { var i = 0; while (1) { i = i + 1; if (i == n) { break; } } return i; }\nfn wend(): i64 { return 0; }\nsyscall(60, wl(3) + ww(4) + wend());\n' > "$T/dis.cyr"
    rc=0; CYRIUS_SYMS="$T/dis.syms" "$CC" < "$T/dis.cyr" > "$T/dis.bin" 2>/dev/null || rc=$?
    a=$(awk '$2 == "wl" { print $1 }' "$T/dis.syms" 2>/dev/null)
    b=$(awk '$2 == "ww" { print $1 }' "$T/dis.syms" 2>/dev/null)
    c=$(awk '$2 == "wend" { print $1 }' "$T/dis.syms" 2>/dev/null)
    if [ "$rc" -ne 0 ] || [ -z "$a" ] || [ -z "$b" ] || [ -z "$c" ]; then bad "A7: the disassembly probe did not build or name its fns"
    else
        tl=$(objdump -d --start-address=0x"$a" --stop-address=0x"$b" "$T/dis.bin" | grep -c 'test ')
        tw=$(objdump -d --start-address=0x"$b" --stop-address=0x"$c" "$T/dis.bin" | grep -c 'test ')
        if [ "$tw" -ge 2 ] && [ "$tl" -eq $((tw - 1)) ]; then ok "A7: loop emits one test fewer than while (1) ($tl vs $tw: no condition at its top)"
        else bad "A7: loop has $tl test(s), while (1) $tw — want exactly one fewer (and while >= 2)"; fi
    fi
else echo "  SKIP A7: no objdump"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: loop_do_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: loop_do_checked — $skips leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: loop_do_checked — loop / do … while: refusals (R), the contextual identifier (K), #inline (W), const fn (C), every backend (A)"
