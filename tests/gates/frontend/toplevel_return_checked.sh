#!/bin/sh
# tests/gates/frontend/toplevel_return_checked.sh — 6.7.11 (the frontend lane, F1)
#
# A `return` OUTSIDE A FN BODY IS REFUSED BY NAME (the user's decision (a), 2026-10-13: `return outside a fn body`,
# at top level and in top-level blocks, reported once while the parse continues).
#
# Before 6.7.11 a top-level `return` compiled with no diagnostic and did not return. PARSE_RETURN recorded its jump in
# rp_vec, and only a fn's end patches rp_vec, over the range that fn owns, so a top-level entry kept displacement 0:
# `jmp +0` on x86_64 / PE (`return 6; syscall(60, 9);` exited 9), a branch to itself on aarch64 / cx (a hang). No
# version from 5.11.69 to 6.7.10 returned from one. (issues/archived/2026-10-12-top-level-return-decision.md)
#
#   R1-R9  R1-R8 the issue's table, each program verbatim (its last row's two programs are R7 and R8); R9 its
#          reproduction's file (`printf 'return 6;\nsyscall(60, 9);\n'`). Each is refused once by name, rc 1, on
#          x86 (the compiler under test), aarch64 (cycc_aarch64), cx (cycc_cx), PE (CYRIUS_TARGET_WIN=1) and PE
#          through cycc_win (src/main_win.cyr), the cross compilers built from this tree. A leg that BUILDS one runs
#          it under `timeout 5` (qemu-aarch64 / cxvm / wine), so a reintroduced self-jump is a red row, never a hang
#   B1-B7  a top-level block: a while body, a for-in body, a switch case, an else branch, a nested block, a match arm,
#          a `loop` body — refused once, at the `return`'s own line
#   P1-P5  the parse goes on: the next statement's own error is reported too (2 lines) — one starting with a keyword
#          (P1), one starting with a name (P4) and a builtin call (P5), which the error resync would skip whole if the
#          report left its latch set; two returns are two lines (P2); a value nesting `( [ {` is one line (P3)
#   X      --syntax-only (cyrius lint's pre-pass) refuses it, once
#   C1-C5  controls: a fn body is a fn body wherever it sits. They compile and run on every leg: a return in a
#          top-level closure body (5), in a closure in a top-level block (5), in an #inline fn called at top level
#          (4), in a fn defined in a top-level block (3), early returns in a fn defined after top-level code (10)
#          — on ecb / ach / cass / pi too, as tests/tcyr/crossos/toplevel_return_controls.tcyr (6.7.12)
#   TR1-TR7 (6.7.13; D20 A, the user's decision, 2026-10-15) a `ret2(a, b)` outside a fn body is refused by name
#          (`ret2 outside a fn body`), once: it lands as `return (a, b);` does, through the same unpatched jump (x86 /
#          PE ran on past it — `ret2(6, 7); syscall(60, 9);` exited 9 — aarch64 / cx hung at it). TR1-TR3 the issue's
#          table verbatim (TR1r its reproduction's file), TR4 a global initializer in both zones, TR5 the parse goes
#          on (a next builtin call's own error, 2 lines), TR6 --syntax-only, TR7 the control: a ret2 in a fn, a
#          top-level closure and an #inline fn still runs on every leg (54)
#          (issues/archived/2026-10-14-top-level-ret2-never-returns.md)
#
# MUTATION LEDGER (2026-10-14; each a one-edit copy of the tree, its compiler built by the fixed one, this gate run
# from that copy with CYCC= it, so the cross legs are built from the mutated src too):
#   MH  PARSE_RETURN without its `_ret_toplevel` call -> RED R1-R9 B1-B7 P1-P5 X on every leg (each BUILT; x86 / PE
#       run past the return, aarch64 / cx: "hung (timeout 5)"); C1-C5 green
#   MG  `_ret_toplevel` without its GINFN test (every return refused) -> RED C1-C5 and P2 (its fn's return refused
#       too) on x86 / PE, and every row of the aarch64 / cx / cycc_win legs (their compilers' own sources no longer
#       build)
#   MS  `_ret_toplevel` without its `_ret_skip_stmt` (the statement not stepped over) -> RED R1-R9 B1-B7 P1-P5 X on
#       every leg (the value parsed as the next statement: a second error, `unexpected number 5`)
#   MP  the latch left set after the report -> RED P4 P4b P5 P5b (the resync skips a next statement that does not
#       start with a keyword: its own error lost); P1 green (the resync stops at `var`)
#   the compiler before this bite (3a7febfb, the lane's G units) -> RED R1-R9 B1-B7 P1-P5 X (each BUILT: x86 / PE
#       exit the fall-through's value, aarch64 / cx hang at the `return` until `timeout 5`); C1-C5 green
# 6.7.13 (2026-10-15, the same method):
#   MR2a the ret2 arm without its `_ret2_ctx` call (no refusal, the landing always recorded) -> RED TR1-TR4b on
#       every leg (each BUILT: x86 / PE exit 9 / 6, aarch64 / cx "hung (timeout 5)"), TR5 / TR5b (the next
#       statement's error alone), TR6; TR7 green
#   MR2b `_ret2_ctx` without its GINFN test (every ret2 refused) -> RED TR7 on every leg; TR1-TR6 green
#   MR2c `_ret2_ctx` leaving the latch set -> RED TR5 TR5b (the next statement's own error lost)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=toplevel_return_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
HAVE_WINE=0
if command -v wine > /dev/null 2>&1; then HAVE_WINE=1
else echo "  SKIP the PE legs' runs (C rows; a mutant's built R / B rows) — wine not installed"; skips=$((skips + 1)); fi
HAVE_QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then HAVE_QEMU=1
else echo "  SKIP the aarch64 legs' runs — qemu-aarch64 not installed"; skips=$((skips + 1)); fi

# The cross compilers, built once from this tree by the compiler under test.
"$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
    && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" \
    || rm -f "$T/cc_cx" "$T/cxvm"
"$CC" < src/main_win.cyr > "$T/cc_win" 2> "$T/cc_win.err" && [ -s "$T/cc_win" ] && chmod +x "$T/cc_win" || rm -f "$T/cc_win"

LEGS="x86 a64 cx pe pew"
# leg_cc <leg> <src> <out> <err>: compile with that leg's compiler; sets rc (127: the leg's compiler did not build)
leg_cc() {
    rc=0
    case "$1" in
        x86) timeout 60 "$CC" < "$2" > "$3" 2> "$4" || rc=$? ;;
        pe)  CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$4" || rc=$? ;;
        a64) if [ -x "$T/cc_a64" ]; then timeout 60 "$T/cc_a64" < "$2" > "$3" 2> "$4" || rc=$?; else rc=127; fi ;;
        cx)  if [ -x "$T/cc_cx" ]; then timeout 60 "$T/cc_cx" < "$2" > "$3" 2> "$4" || rc=$?; else rc=127; fi ;;
        pew) if [ -x "$T/cc_win" ]; then timeout 60 "$T/cc_win" < "$2" > "$3" 2> "$4" || rc=$?; else rc=127; fi ;;
    esac
}
# leg_run <leg> <bin>: run a built program under `timeout 5`; sets got (124: it hung; 77: no runner)
leg_run() {
    got=0
    case "$1" in
        x86) chmod +x "$2"; timeout 5 "$2" > /dev/null 2>&1 || got=$? ;;
        a64) if [ "$HAVE_QEMU" -eq 1 ]; then chmod +x "$2"; timeout 5 qemu-aarch64 "$2" > /dev/null 2>&1 || got=$?; else got=77; fi ;;
        cx)  timeout 5 "$T/cxvm" < "$2" > /dev/null 2>&1 || got=$? ;;
        pe|pew)
            if [ "$HAVE_WINE" -eq 1 ]; then
                cp "$2" "$T/run.exe"
                (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 60 wine ./run.exe > /dev/null 2>&1) || got=$?
            else got=77; fi ;;
    esac
}

MSG="return outside a fn body"
# refused <name> <what> <want error lines> <location fragment or ""> <body>: on every leg, the compile fails with
# exactly <want> error lines, each holding "$MSG" (P1: only the first), the first at <location>
refused() {
    printf '%b' "$5" > "$T/$1.cyr"
    for L in $LEGS; do
        leg_cc "$L" "$T/$1.cyr" "$T/$1.$L.bin" "$T/$1.$L.err"
        n=$(grep -c '^error' "$T/$1.$L.err" || true)
        if [ "$rc" -eq 127 ]; then bad "$1 [$L]: $2: the leg's compiler did not build"
        elif [ "$rc" -eq 0 ]; then
            leg_run "$L" "$T/$1.$L.bin"
            if [ "$got" -eq 124 ]; then bad "$1 [$L]: $2: BUILT (rc 0) and hung (timeout 5) — want \"$MSG\""
            else bad "$1 [$L]: $2: BUILT (rc 0), ran: exit $got — want \"$MSG\""; fi
        elif [ "$rc" -eq 124 ]; then bad "$1 [$L]: $2: the compiler did not finish (timeout)"
        elif [ "$n" -ne "$3" ]; then bad "$1 [$L]: $2: $n error lines, want $3: $(grep '^error' "$T/$1.$L.err" | head -3 | tr '\n' '|')"
        elif ! grep '^error' "$T/$1.$L.err" | head -1 | grep -qF "$MSG"; then
            bad "$1 [$L]: $2: wrong refusal: $(grep '^error' "$T/$1.$L.err" | head -1)"
        elif [ -n "$4" ] && ! grep '^error' "$T/$1.$L.err" | head -1 | grep -qF "$4"; then
            bad "$1 [$L]: $2: refused, not at $4: $(grep '^error' "$T/$1.$L.err" | head -1)"
        else ok "$1 [$L]: $2"; fi
    done
}
# exits <name> <want> <what> <body>: compiles and exits <want> on every leg
exits() {
    printf '%b' "$4" > "$T/$1.cyr"
    for L in $LEGS; do
        leg_cc "$L" "$T/$1.cyr" "$T/$1.$L.bin" "$T/$1.$L.err"
        if [ "$rc" -eq 127 ]; then bad "$1 [$L]: $3: the leg's compiler did not build"; continue; fi
        if [ "$rc" -ne 0 ]; then bad "$1 [$L]: $3: rc $rc: $(grep '^error' "$T/$1.$L.err" | head -1)"; continue; fi
        leg_run "$L" "$T/$1.$L.bin"
        if [ "$got" -eq 77 ]; then continue; fi
        if [ "$got" -eq "$2" ]; then ok "$1 [$L]: $3: exit $got"; else bad "$1 [$L]: $3: exit $got, want $2"; fi
    done
}

# ── R: the issue's table, verbatim ───────────────────────────────────────────────────────────────────
refused R1 '`return 5;`' 1 '<source>:1:1:' 'return 5;\n'
refused R2 '`return 6; syscall(60, 9);`' 1 '<source>:1:1:' 'return 6; syscall(60, 9);\n'
refused R3 '`var a = 1; a = 2; return a + 3;`' 1 '' 'var a = 1; a = 2; return a + 3;\n'
refused R4 '`var a = 1; return 4;`' 1 '' 'var a = 1; return 4;\n'
refused R5 'a return in a top-level if block' 1 '' 'var a = 1; if (a == 1) { return 6; } syscall(60, 9);\n'
refused R6 '`return 5; var a = 7; syscall(60, a);`' 1 '' 'return 5; var a = 7; syscall(60, a);\n'
refused R7 'a bare `return;`' 1 '' 'var a = 1; return;\n'
refused R8 'a tuple `return (1, 2);`' 1 '' 'var a = 1; return (1, 2);\n'
refused R9 'the reproduction'"'"'s file, verbatim' 1 '<source>:1:1:' 'return 6;\nsyscall(60, 9);\n'

# ── B: top-level blocks ──────────────────────────────────────────────────────────────────────────────
refused B1 'a while body' 1 '<source>:4:' 'var a = 1;\nwhile (a < 3) {\n    a = a + 1;\n    return a;\n}\nsyscall(60, 9);\n'
refused B2 'a for-in body' 1 '<source>:2:' 'for i in 0..3 {\n    return i;\n}\nsyscall(60, 9);\n'
refused B3 'a switch case' 1 '<source>:3:' 'var a = 1;\nswitch (a) {\n    case 1: return 6;\n    default: syscall(60, 8);\n}\nsyscall(60, 9);\n'
refused B4 'an else branch' 1 '<source>:3:' 'var a = 2;\nif (a == 1) { syscall(60, 8); } else {\n    return 6;\n}\nsyscall(60, 9);\n'
refused B5 'a while in an if in an if' 1 '<source>:4:' 'var a = 1;\nif (a == 1) {\n    if (a > 0) {\n        while (a == 1) { return 6; }\n    }\n}\nsyscall(60, 9);\n'
refused B6 'a match arm' 1 '<source>:3:' 'var a = 1;\nmatch (a) {\n    1 => { return 6; }\n    _ => { syscall(60, 8); }\n}\nsyscall(60, 9);\n'
refused B7 'a loop body' 1 '<source>:3:' 'var a = 1;\nloop {\n    return 6;\n}\n'

# ── P: the parse goes on ─────────────────────────────────────────────────────────────────────────────
refused P1 'the next statement reports its own error (2 lines)' 2 '<source>:1:1:' 'return 5;\nvar x = y;\n'
printf 'return 5;\nvar x = y;\n' > "$T/p1.cyr"
"$CC" < "$T/p1.cyr" > /dev/null 2> "$T/p1.err" || true
if grep '^error' "$T/p1.err" | sed -n 2p | grep -qF "undefined variable 'y'"; then ok "P1b: the second line is the next statement's own error"
else bad "P1b: the second error line is not \"undefined variable 'y'\": $(grep '^error' "$T/p1.err" | tr '\n' '|')"; fi
refused P2 'two returns, two lines' 2 '<source>:1:1:' 'return 5;\nreturn 6;\nfn f(): i64 { return 7; }\nsyscall(60, f());\n'
printf 'return 5;\nreturn 6;\n' > "$T/p2.cyr"
"$CC" < "$T/p2.cyr" > /dev/null 2> "$T/p2.err" || true
if [ "$(grep '^error' "$T/p2.err" | grep -cF "$MSG")" -eq 2 ] && grep '^error' "$T/p2.err" | sed -n 2p | grep -qF '<source>:2:1:'; then
    ok "P2b: both returns named, the second at 2:1"
else bad "P2b: $(grep '^error' "$T/p2.err" | tr '\n' '|')"; fi
refused P3 'a value nesting ( [ { and a tuple, one line' 1 '<source>:1:1:' 'return f(1, (2, 3), [4], { 5 });\nsyscall(60, 9);\n'
# p_next <name> <what> <body>: x86, the second error line is the next statement's own `undefined variable 'y'`
p_next() {
    printf '%b' "$3" > "$T/$1n.cyr"
    "$CC" < "$T/$1n.cyr" > /dev/null 2> "$T/$1n.err" || true
    if grep '^error' "$T/$1n.err" | sed -n 2p | grep -qF "undefined variable 'y'"; then ok "$1: $2"
    else bad "$1: $2: $(grep '^error' "$T/$1n.err" | tr '\n' '|')"; fi
}
refused P4 'a next statement starting with a name reports its own error (2 lines)' 2 '<source>:2:1:' 'var x = 1;\nreturn 5;\nx = y;\n'
p_next P4b 'the second line is `x = y;`'"'"'s own error' 'var x = 1;\nreturn 5;\nx = y;\n'
refused P5 'a next statement that is a builtin call reports its own error (2 lines)' 2 '<source>:1:1:' 'return 5;\nsyscall(60, y);\n'
p_next P5b 'the second line is `syscall(60, y);`'"'"'s own error' 'return 5;\nsyscall(60, y);\n'

# ── X: --syntax-only (cyrius lint's pre-pass) ────────────────────────────────────────────────────────
printf 'var a = 1;\nif (a == 1) { return 6; }\nsyscall(60, 9);\n' > "$T/x.cyr"
rc=0; "$CC" --syntax-only < "$T/x.cyr" > /dev/null 2> "$T/x.err" || rc=$?
n=$(grep -c '^error' "$T/x.err" || true)
if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ] && grep -qF "$MSG" "$T/x.err"; then ok "X: --syntax-only refuses it, once"
else bad "X: --syntax-only: rc $rc, $n error lines: $(grep '^error' "$T/x.err" | head -2 | tr '\n' '|')"; fi

# ── C: controls — a fn body wherever it sits ─────────────────────────────────────────────────────────
exits C1 5 'a return in a top-level closure body' 'include "lib/fnptr.cyr"\nvar f = |x| { return x + 2; };\nsyscall(60, fncall1(f, 3));\n'
exits C2 5 'a return in a closure in a top-level block' 'include "lib/fnptr.cyr"\nvar a = 1;\nif (a == 1) {\n    var f = |x| { return x + 2; };\n    syscall(60, fncall1(f, 3));\n}\nsyscall(60, 9);\n'
exits C3 4 'a return in an #inline fn called at top level' '#inline\nfn four(): i64 { return 4; }\nsyscall(60, four());\n'
exits C4 3 'a return in a fn defined in a top-level block' 'var on = 1;\nif (on == 1) { fn g(): i64 { return 3; } }\nsyscall(60, g());\n'
exits C5 10 'early returns in a fn defined after top-level code' 'var a = 1;\nwhile (a < 5) { a = a + 1; }\nfn h(n): i64 { if (n > 2) { return n * 2; } return 0; }\nsyscall(60, h(a));\n'

# ── TR (6.7.13): a ret2 outside a fn body ───────────────────────────────────────────────────────────
MSG="ret2 outside a fn body"
refused TR1 '`ret2(6, 7); syscall(60, 9);`' 1 '<source>:1:1:' 'ret2(6, 7); syscall(60, 9);\n'
refused TR1r 'the reproduction'"'"'s file, verbatim' 1 '<source>:1:1:' 'ret2(6, 7);\nsyscall(60, 9);\n'
refused TR2 '`ret2(6, 7);`' 1 '<source>:1:1:' 'ret2(6, 7);\n'
refused TR3 'a ret2 in a top-level if block' 1 '<source>:1:26:' 'var a = 1; if (a == 1) { ret2(6, 7); } syscall(60, 9);\n'
refused TR4 'a global initializer, the declaration zone' 1 '<source>:1:9:' 'var G = ret2(6, 7);\nsyscall(60, 9);\n'
refused TR4b 'a global initializer after a statement' 1 '<source>:3:9:' 'var z = 1;\nz = 2;\nvar G = ret2(6, 7);\nsyscall(60, 9);\n'
refused TR5 'a next statement that is a builtin call reports its own error (2 lines)' 2 '<source>:1:1:' 'ret2(6, 7);\nsyscall(60, y);\n'
p_next TR5b 'the second line is `syscall(60, y);`'"'"'s own error' 'ret2(6, 7);\nsyscall(60, y);\n'
printf 'var a = 1;\nif (a == 1) { ret2(6, 7); }\nsyscall(60, 9);\n' > "$T/tr6.cyr"
rc=0; "$CC" --syntax-only < "$T/tr6.cyr" > /dev/null 2> "$T/tr6.err" || rc=$?
n=$(grep -c '^error' "$T/tr6.err" || true)
if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ] && grep -qF "$MSG" "$T/tr6.err"; then ok "TR6: --syntax-only refuses it, once"
else bad "TR6: --syntax-only: rc $rc, $n error lines: $(grep '^error' "$T/tr6.err" | head -2 | tr '\n' '|')"; fi
exits TR7 54 'a ret2 in a fn, a top-level closure and an #inline fn' 'include "lib/fnptr.cyr"\nfn f(x) { ret2(x, x + 1); }\n#inline\nfn fi(x) { ret2(x * 2, x + 3); }\nfn g(x) { var a, b = fi(x); return a * 10 + b; }\nvar cl = |x| { ret2(x + 1, x + 2); };\nfn main(): i64 { var a, b = f(3); var c, d = fncall1(cl, 1); return a * 10 + b + g(1) + c * 1000 + d * 100; }\nsyscall(60, main() & 255);\n'

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips runner(s) missing; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a return outside a fn body refused by name, once, on x86 / aarch64 / cx / PE / cycc_win (R1-R9, B1-B7), the parse goes on (P1-P5), --syntax-only (X); a return in a closure, an #inline fn and a fn in a top-level block still runs on every leg (C1-C5); a ret2 outside a fn body refused the same way, once, a ret2 in a fn / closure / #inline fn still runs (TR1-TR7)"
