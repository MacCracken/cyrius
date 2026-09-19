#!/bin/sh
# Gate: a block-bodied closure in a top-level `var` initializer does not end the program (6.6.6).
#
# THE DEFECT (measured at 6.6.5 and 6.6.4, x86_64 Linux, no diagnostic):
#
#     var f = |x| { return 7; };
#     syscall(1, 1, "hi\n", 3);
#     syscall(60, 9);                 prints nothing, exits 186 (the closure's address, 0x4000ba)
#
# A `var` in the DECLARATION ZONE (before the first top-level statement) is registered by pass 1
# (PARSE_GVAR_REG) and stepped over by pass 2 (the `var` arm of every fork's top-level loop);
# its initializer is compiled later by EMIT_GVAR_INITS. Both passes found the end of the
# declaration by scanning to the FIRST `;` — and a block-bodied closure carries one inside its
# body. Both stopped mid-closure, at its `}`, which ends every top-level loop: pass 1 registered
# nothing after it and pass 2 handed PARSE_PROG a `}`, so every statement after the declaration
# was dropped and the exit status was the last global's value. The same `var` AFTER a top-level
# statement is parsed as a statement and was always correct — which is what the CONTROLS use.
#
# THE FIX: one shared skip, `_skip_gvar_decl` (src/frontend/parse_decl.cyr), that ends at the
# first `;` outside every `{ }`, used by PARSE_GVAR_REG (both its plain and destructure arms) and
# by the pass-2 `var` arm of all SEVEN forks. Only brace depth counts: a `;` inside parens alone
# is never valid, and row M pins that a malformed `var x = f(1;` does not swallow the file.
#
# EXPECTED VALUES are absolute AND each is checked against a CONTROL: the same program with one
# top-level statement (`z0 = 1;`) in front, so every declaration goes through PARSE_PROG instead
# of the declaration-zone path — a different path in the compiler, so a row cannot pass by both
# sides sharing one defect.
#
# LEGS: host x86_64 (every row); cx via the tree's own main_cx + cxvm; aarch64 under
# qemu-aarch64 and Win64 PE under wine when installed — qemu and wine are EMULATION, NOT
# hardware (tests/tcyr/crossos/toplevel_block_closure.tcyr is the real-hardware leg, and it is
# the only one that reaches Mach-O). Axis S is static 7-fork parity: the pass-2 skip is copied
# into every fork, so a fork that keeps the old loop is broken on that target only.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree whose src/ carries the mutation, built
# by build/cycc and run as CYCC=<mutant>, so the cx / aarch64 / PE legs are built from it too):
#   m1 whole fix reverted (6.6.5 parse_decl.cyr + all 7 forks) -> RED rows A-G, cx A-G, a64 A-G, wine A E F, S
#   m2 _skip_gvar_decl ignores braces (stops at the first `;`)   -> RED rows A-G, cx A-G, a64 A-G, wine A E F
#   m3 only main.cyr's pass-2 arm reverted (pass 1 fixed)        -> RED rows A-G, S (cx/a64/wine GREEN: other forks)
#   m4 only main_win.cyr's pass-2 arm reverted                   -> RED wine A E F, S only
#   m5 PARSE_GVAR_REG's destructure arm reverted                 -> RED row F on every leg (host, cx, a64, wine)
#      ⚠ row F detects it only because a global is declared BELOW the destructure: pass 2 walks
#      the file correctly either way, so what a pass-1-only revert loses is the REGISTRATION of
#      everything after the declaration (`var af = 9;` is then an undefined name). Measured: with
#      `var af` removed, m5 passes every row.
#   m6 _skip_gvar_decl counts parens too                          -> RED row M only
#   real tree                                                    -> GREEN (9 host rows, 7 cx, 7 aarch64, 3 wine)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: toplevel_decl_block_closure: $CC missing"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# build <compiler> <src> <out>: a failed compile or an empty output is a FAIL, never a silent
# pass (cycc on empty input still emits a runnable binary).
build() {
    if ! "$1" < "$2" > "$3" 2> "$3.err"; then return 1; fi
    [ -s "$3" ] || return 1
    return 0
}

# The rows: id|want-rc|want-stdout|source. Every source's first top-level statement comes
# AFTER the closure declaration(s); the control moves `struct` lines first and then puts
# `var z0 = 0;\nz0 = 1;` ahead of everything else.
cat > "$WORK/rows" <<'ROWS'
A|9|hi|var f = |x| { return 7; };\nsyscall(1, 1, "hi\\n", 3);\nsyscall(60, 9);\n
B|9||var f = |x| { var a = 1; return 7; };\nsyscall(60, 9);\n
C|42||var f = |x| { var a = x + 1; return a * 2; };\nfn call1(p, x): i64 { return callptr(p, x); }\nsyscall(60, call1(f, 20));\n
D|8||var f = || { return 7; };\nfn call0(p): i64 { return callptr(p); }\nsyscall(60, call0(f) + 1);\n
E|46||var f = |n| { var s = 0; for (var i = 0; i < n; i = i + 1) { if (i > 2) { s = s + i; } else { s = s + 10; } } return s; };\nstruct P { a; b; }\nvar p = P { 4, 5 };\nfn call1(q, x): i64 { return callptr(q, x); }\nsyscall(60, call1(f, 5) + p.a + p.b);\n
F|41||fn two(cb): i64 { return ret2(callptr(cb, 1), 30); }\nvar a, b = two(|x| { var y = x + 1; return y; });\nvar af = 9;\nsyscall(60, a + b + af);\n
G|118||struct Q { fp; k; }\nvar q = Q { |x| { return x + 100; }, 2 };\nvar g = |x| { return x * 3; };\nfn call1(p, x): i64 { return callptr(p, x); }\nsyscall(60, call1(q.fp, 1) + q.k + call1(g, 5));\n
ROWS

# run_row <leg> <compiler> <runner> <id> <want> <want-out> <src> — runner is "" for native
run_row() {
    printf '%b' "$7" > "$WORK/t.cyr"
    # The control: struct definitions first (a `struct` is not a statement, so it cannot follow
    # one), then the statement, then the rest of the row in its original order.
    { grep '^struct ' "$WORK/t.cyr" || true; printf 'var z0 = 0;\nz0 = 1;\n'
      grep -v '^struct ' "$WORK/t.cyr" || true; } > "$WORK/c.cyr"
    for side in t c; do
        if ! build "$2" "$WORK/$side.cyr" "$WORK/$side.bin"; then
            bad "$1 row $4 ($side): compile failed: $(head -c 200 "$WORK/$side.bin.err")"; continue
        fi
        chmod +x "$WORK/$side.bin"
        set +e
        if [ -n "$3" ]; then $3 "$WORK/$side.bin" > "$WORK/$side.out" 2> /dev/null
        else "$WORK/$side.bin" > "$WORK/$side.out" 2> /dev/null; fi
        r=$?
        set -e
        out=$(tr -d '\r' < "$WORK/$side.out")
        what="declaration-zone program"; [ "$side" = c ] && what="CONTROL (the gate's own premise is off)"
        [ "$r" = "$5" ] || bad "$1 row $4: $what exited $r, want $5"
        [ "$out" = "$6" ] || bad "$1 row $4: $what printed '$out', want '$6'"
    done
}

# run_leg <leg> <compiler> <runner> [row ids...] — no ids means every row
run_leg() {
    leg=$1; comp=$2; runner=$3; shift 3
    while IFS='|' read -r id want wout src; do
        if [ $# -gt 0 ]; then
            case " $* " in *" $id "*) ;; *) continue ;; esac
        fi
        NROWS=$((NROWS + 1))
        run_row "$leg" "$comp" "$runner" "$id" "$want" "$wout" "$src"
    done < "$WORK/rows"
}

echo "host x86_64:"
run_leg host "$CC" ""

# M — a MALFORMED declaration still resyncs at its own `;`. Only BRACE depth may carry the skip
#     past a `;`: were parens counted, `var x = f(1;` would swallow the rest of the file and the
#     second error would never be reported. A guard, not a detector (6.6.5 behaves the same).
NROWS=$((NROWS + 1))
printf 'fn f(a): i64 { return a; }\nvar x = f(1;\nvar y = nosuchname_m;\nsyscall(60, x);\n' > "$WORK/m.cyr"
if "$CC" < "$WORK/m.cyr" > "$WORK/m.bin" 2> "$WORK/m.err"; then
    bad "row M: a malformed declaration COMPILED"
elif ! grep -q "nosuchname_m" "$WORK/m.err"; then
    bad "row M: the error in the NEXT declaration was not reported (the skip swallowed it): $(head -c 300 "$WORK/m.err")"
fi

# S — static 7-fork parity: every fork's pass-2 `var` arm calls the shared skip, and none still
#     carries the old first-`;` loop. The fork list is derived, not listed.
NROWS=$((NROWS + 1))
NFORK=0
for fk in "$ROOT"/src/main*.cyr; do
    NFORK=$((NFORK + 1))
    n=$(grep -c '_skip_gvar_decl(S);' "$fk" || true)
    [ "$n" = "1" ] || bad "row S: $(basename "$fk") calls _skip_gvar_decl $n times in its top-level loop, want 1"
    if grep -q 'while (vsk == 1)' "$fk"; then bad "row S: $(basename "$fk") still carries the first-';' pass-2 skip"; fi
done
[ "$NFORK" -ge 7 ] || bad "row S: found $NFORK src/main*.cyr forks, want at least 7"

# ---- cx leg: the tree's own cx compiler + cxvm ----
echo "cx (cxvm):"
if build "$CC" "$ROOT/src/main_cx.cyr" "$WORK/cycc_cx" && build "$CC" "$ROOT/programs/cxvm.cyr" "$WORK/cxvm"; then
    chmod +x "$WORK/cycc_cx" "$WORK/cxvm"
    cxr() { timeout 60 "$WORK/cxvm" < "$1"; }
    run_leg cx "$WORK/cycc_cx" cxr
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi

# ---- aarch64 leg (qemu-aarch64, NOT hardware) ----
if command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "aarch64 (qemu-aarch64 — emulation, not hardware):"
    if build "$CC" "$ROOT/src/main_aarch64.cyr" "$WORK/cycc_a64"; then
        chmod +x "$WORK/cycc_a64"
        a64r() { timeout 60 qemu-aarch64 "$1"; }
        run_leg aarch64 "$WORK/cycc_a64" a64r
    else
        bad "aarch64 leg: could not build src/main_aarch64.cyr"
    fi
else
    echo "  SKIP: qemu-aarch64 not installed (the pi hardware leg still covers it)"
fi

# ---- Win64 PE leg (wine, NOT hardware) — the PE fork carries its own pass-2 skip ----
if command -v wine > /dev/null 2>&1; then
    echo "win64 (wine — emulation, not hardware):"
    # A throwaway prefix, so nothing of the user's ~/.wine is read or written.
    export WINEPREFIX="$WORK/wine" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    if build "$CC" "$ROOT/src/main_win.cyr" "$WORK/cycc_win"; then
        chmod +x "$WORK/cycc_win"
        wr_() { cp "$1" "$1.exe"; timeout 180 wine "$1.exe"; }
        run_leg win64 "$WORK/cycc_win" wr_ A E F
    else
        bad "win64 leg: could not build src/main_win.cyr"
    fi
    wineserver -k > /dev/null 2>&1 || true
else
    echo "  SKIP: wine not installed (the cass hardware leg still covers it)"
fi

# Derived floor: 7 rows x (host + cx) + M + S = 16 even with qemu and wine absent.
if [ "$NROWS" -lt 16 ]; then bad "only $NROWS rows ran (floor 16) — the row table did not load"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: toplevel_decl_block_closure ($NFAIL of $NROWS rows)"
    exit 1
fi
echo "PASS: toplevel_decl_block_closure ($NROWS rows)"
