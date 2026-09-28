#!/bin/sh
# Gate: `for x in a..b` / `for x in vec` at TOP LEVEL binds a live global (6.6.8 bite 1).
#
# THE DEFECT (measured at 6.6.7):
#
#     var s = 0;
#     for i in 0..4 { s = s + 1; }      x86_64 / aarch64: SIGSEGV (139)
#     syscall(60, s);                  PE under wine: page fault writing FFFFFFFFFFFFFFF8
#
#     for i in 0..4 { s = s + i; }      error: undefined variable 'i'
#
# PARSE_FOR registered the loop variable as a fn FRAME slot unconditionally. Top-level code
# has no frame on any executable entry, so the store addressed [rbp-8] / [x29-8] off an
# unset frame pointer, and top-level resolution never runs FINDLOCAL, so every READ of the
# name was undefined. At top level it is now a LIVE global (_HTNAMED, parse.cyr) that leaves
# scope at the loop's end, marked 3 so a later use gets a note that fits a loop variable.
#
# EXPECTED VALUES come from a CONTROL program compiled by the same compiler that spells the
# same meaning with a C-style loop over a top-level global (which always worked), so a row
# cannot pass by both sides sharing one defect. Refusal rows assert the exit code, the error
# text, the note, and that no binary was produced.
#
# LEGS: host x86_64 (every row); aarch64 under qemu-aarch64 (a compiler built from this tree's
# src/main_aarch64.cyr) and PE under wine (CYRIUS_TARGET_WIN=1) when installed — rows A B D F. Those are EMULATORS: tests/tcyr/crossos/toplevel_for_in.tcyr is what
# runs on ecb/ach/cass/pi. cx is NOT a leg: cxvm gives top-level code a frame, so the unread
# forms passed there before the fix and it cannot tell RED from GREEN.
#
# MUTATION LEDGER (6.6.8, x86_64 Linux + qemu-aarch64 + wine; each mutant is a scratch tree
# whose src/ carries the mutation, built by the 6.6.7 cycc and run as CYCC=<mutant>, so the
# aarch64 leg's compiler is built from the mutated tree too):
#   1. the 6.6.7 frontend (no fix)                 -> RED 24 of 27: every host runtime row but
#                                                     C2, rows U1-U3 (no loop note), and all
#                                                     8 emulator rows (139 under qemu, 5 = the
#                                                     page fault under wine)
#   2. _HTLOOPEND made a no-op                     -> RED U1 U2 U3 (the 6.6.6 BLOCK note and
#                                                     its "declare it at top level" advice)
#   3. the collection loop's hidden INDEX left a
#      frame slot at top level (item fixed only)   -> RED E F N + aarch64 F + pe F (139 / 5)
#   4. real tree                                   -> GREEN
# Row C2 and U4 are guards (green on 6.6.7 too): C2 that fns keep capture-by-value, U4 that the
# most recent out-of-scope binding of a name picks the note.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: toplevel_for_in: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"   # the collection rows include lib/alloc.cyr + lib/vec.cyr from the tree
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# build <compiler> <src> <out>: a failed compile or an EMPTY binary is a failure, never a
# silent pass (cycc on empty input exits 0 and emits a runnable binary).
build() {
    if ! "$1" < "$2" > "$3" 2> "$3.err"; then return 1; fi
    [ -s "$3" ] || return 1
    chmod +x "$3"
    return 0
}
# ec <compiler> <runner> <src> <tag>: compile + run, print the exit code (or CCFAIL)
ec() {
    if ! build "$1" "$3" "$WORK/b_$4"; then printf 'CCFAIL'; return 0; fi
    set +e
    if [ -n "$2" ]; then (cd "$WORK" && $2 "$WORK/b_$4") > /dev/null 2>&1
    else (cd "$WORK" && "$WORK/b_$4") > /dev/null 2>&1; fi
    r=$?
    set -e
    printf '%s' "$r"
}

VEC='include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\nalloc_init();\nvar v = vec_new();\nvec_push(v, 1); vec_push(v, 2); vec_push(v, 3);\n'
# The `s = 0;` statement ends the declaration zone, so every loop below is top-level CODE.
HD='var s = 0;\nvar n = 0;\ns = 0;\n'

# ── runtime rows: <id> <want> <test> <control> ──────────────────────────────────────────
ROWS=""
_row() {
    NROWS=$((NROWS + 1))
    printf '%b' "$3" > "$WORK/t_$1.cyr"
    printf '%b' "$4" > "$WORK/c_$1.cyr"
    got=$(ec "$CC" "" "$WORK/t_$1.cyr" "t$1"); ctl=$(ec "$CC" "" "$WORK/c_$1.cyr" "c$1")
    [ "$ctl" = "$2" ] || bad "row $1: CONTROL gave $ctl, want $2 (the gate's own premise is off)"
    [ "$got" = "$2" ] || bad "row $1: gave $got, want $2"
    ROWS="$ROWS $1:$2"
}
# A — range, variable read (was `undefined variable 'i'`)
_row A 6 "${HD}for i in 0..4 { s = s + i; }\nsyscall(60, s);\n" \
         "${HD}for (n = 0; n < 4; n = n + 1) { s = s + n; }\nsyscall(60, s);\n"
# B — nested ranges (was 139)
_row B 6 "${HD}for i in 0..3 { for j in 0..2 { s = s + 1; } }\nsyscall(60, s);\n" \
         "${HD}for (n = 0; n < 6; n = n + 1) { s = s + 1; }\nsyscall(60, s);\n"
# D — range, variable never read: the counter store alone was the crash (was 139)
_row D 4 "${HD}for i in 0..4 { s = s + 1; }\nsyscall(60, s);\n" \
         "${HD}for (n = 0; n < 4; n = n + 1) { s = s + 1; }\nsyscall(60, s);\n"
# E — collection, item read (was `undefined variable 'x'`)
_row E 6 "${VEC}${HD}for x in v { s = s + x; }\nsyscall(60, s);\n" \
         "${VEC}${HD}for (n = 0; n < vec_len(v); n = n + 1) { s = s + vec_get(v, n); }\nsyscall(60, s);\n"
# F — collection, item never read (was 139)
_row F 3 "${VEC}${HD}for x in v { s = s + 1; }\nsyscall(60, s);\n" \
         "${VEC}${HD}for (n = 0; n < vec_len(v); n = n + 1) { s = s + 1; }\nsyscall(60, s);\n"
# K — break / continue
_row K 8 "${HD}for i in 0..10 { if (i == 5) { break; } if (i == 2) { continue; } s = s + i; }\nsyscall(60, s);\n" \
         "${HD}s = 0 + 1 + 3 + 4;\nsyscall(60, s);\n"
# Q — the same name in two sequential loops: each gets its own variable
_row Q 23 "${HD}for i in 0..3 { s = s + i; }\nfor i in 0..2 { s = s + 10; }\nsyscall(60, s);\n" \
          "${HD}s = 0 + 1 + 2 + 10 + 10;\nsyscall(60, s);\n"
# H — shadowing an outer global: the loop reads its own variable, the global is untouched,
#     and a fn reading the global's name inside the loop still sees the global.
_row H 3 "var i = 100;\nfn show(): i64 { return i; }\n${HD}for i in 0..3 { s = s + show() + i; }\nsyscall(60, s - 300 + i - 100);\n" \
         "var i = 100;\nfn show(): i64 { return i; }\n${HD}for (n = 0; n < 3; n = n + 1) { s = s + show() + n; }\nsyscall(60, s - 300 + i - 100);\n"
# I — inside a top-level `if`
_row I 7 "var g = 1;\n${HD}s = 1;\nif (g == 1) { for i in 0..4 { s = s + i; } }\nsyscall(60, s);\n" \
         "var g = 1;\n${HD}s = 1;\nif (g == 1) { for (n = 0; n < 4; n = n + 1) { s = s + n; } }\nsyscall(60, s);\n"
# N — a range loop bounded by a collection item
_row N 4 "${VEC}${HD}for x in v { for j in 0..x { s = s + j; } }\nsyscall(60, s);\n" \
         "${VEC}${HD}s = 0 + 0 + 1 + 0 + 1 + 2;\nsyscall(60, s);\n"
# S — after a top-level switch (whose subject temp is a top-level global too)
_row S 47 "var i = 7;\n${HD}switch (s) { case 0: s = 1; }\nfor i in 0..3 { s = s + i; }\nsyscall(60, s * 10 + i);\n" \
          "var i = 7;\n${HD}s = 1 + 0 + 1 + 2;\nsyscall(60, s * 10 + i);\n"
# L — a fn DEFINED after the loop resolves globals normally (the loop name is gone, `s` is not)
_row L 3 "${HD}for k in 0..3 { s = s + k; }\nfn later(): i64 { return s; }\nsyscall(60, later());\n" \
         "${HD}s = 0 + 1 + 2;\nfn later(): i64 { return s; }\nsyscall(60, later());\n"
# C — CLOSURE CAPTURE, PINNED (the user default for 6.6.8): a closure made in a top-level loop
#     reads the LIVE global (3 after the loop -> 13), the rule 6.6.6 top-level block `var`s
#     follow; inside a fn the same code captures by value (10). Changing it is one separate
#     change spanning both binding kinds. The control is a closure over a plain global.
CL='include "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\nalloc_init();\nvar f0 = 0;\n'
_row C 13 "${CL}${HD}for i in 0..3 { if (i == 0) { f0 = |x| x + i; } }\nsyscall(60, fncall1(f0, 10));\n" \
          "${CL}var i = 0;\n${HD}for (i = 0; i < 3; i = i + 1) { if (i == 0) { f0 = |x| x + i; } }\nsyscall(60, fncall1(f0, 10));\n"
# C2 — ...and the in-fn by-value rule is unchanged (a guard that the fix did not leak into fns)
_row C2 10 "${CL}fn run(): i64 { var f = 0; for i in 0..3 { if (i == 0) { f = |x| x + i; } } return fncall1(f, 10); }\nsyscall(60, run());\n" \
           "${CL}fn run(): i64 { var f = 0; var z = 0; f = |x| x + z; return fncall1(f, 10); }\nsyscall(60, run());\n"

# ── refusal rows: the loop variable is out of scope after the loop ─────────────────────────
_refuse() {
    NROWS=$((NROWS + 1))
    printf '%b' "$3" > "$WORK/r.cyr"
    set +e; "$CC" < "$WORK/r.cyr" > "$WORK/r.bin" 2> "$WORK/r.err"; rc=$?; set -e
    [ "$rc" = "1" ] || bad "row $1: compiler exited $rc, want 1"
    [ -s "$WORK/r.bin" ] && bad "row $1: a binary was emitted for a refused program"
    grep -q "undefined variable '$2'" "$WORK/r.err" || bad "row $1: the error does not name '$2'"
    grep -q "'$2' is a \`for ... in\` loop variable" "$WORK/r.err" || bad "row $1: no loop-variable note"
    if grep -q "declare it at top level" "$WORK/r.err"; then
        bad "row $1: the top-level BLOCK note's advice was printed for a loop variable"
    fi
}
# U1 — read after a range loop; U2 — after a collection loop; U3 — assignment after the loop
_refuse U1 i "${HD}for i in 0..4 { s = s + i; }\nsyscall(60, i);\n"
_refuse U2 x "${VEC}${HD}for x in v { s = s + x; }\nsyscall(60, x);\n"
_refuse U3 i "${HD}for i in 0..4 { s = s + i; }\ni = 9;\nsyscall(60, s);\n"
# U4 — the most recent out-of-scope binding of a name picks the note: a block `var` that
#      follows a loop of the same name gets the BLOCK note, not the loop one.
NROWS=$((NROWS + 1))
printf '%b' "var g = 1;\n${HD}for i in 0..2 { s = s + i; }\nif (g == 1) { var i = 5; }\nsyscall(60, i);\n" > "$WORK/u4.cyr"
set +e; "$CC" < "$WORK/u4.cyr" > "$WORK/u4.bin" 2> "$WORK/u4.err"; rc=$?; set -e
[ "$rc" = "1" ] || bad "row U4: compiler exited $rc, want 1"
grep -q "declared inside a top-level block" "$WORK/u4.err" || bad "row U4: the later block var did not get the block note"

# T — top-level `defer` is refused by name, with no binary (it also has no frame to flag in)
NROWS=$((NROWS + 1))
printf '%b' "${HD}defer { s = 4; }\nsyscall(60, s);\n" > "$WORK/d.cyr"
set +e; "$CC" < "$WORK/d.cyr" > "$WORK/d.bin" 2> "$WORK/d.err"; rc=$?; set -e
[ "$rc" = "1" ] || bad "row T: top-level defer: compiler exited $rc, want 1"
[ -s "$WORK/d.bin" ] && bad "row T: a binary was emitted for a top-level defer"
grep -q "defer only allowed inside a function" "$WORK/d.err" || bad "row T: top-level defer not refused by name"

# ── emulator legs: the crashing rows, with compilers built from THIS tree ──────────────────
cross_leg() {  # <name> <compiler> <runner>
    for _r in A B D F; do
        _w=$(printf '%s' "$ROWS" | tr ' ' '\n' | grep "^$_r:" | cut -d: -f2)
        NROWS=$((NROWS + 1)); NX=$((NX + 1))
        xg=$(ec "$2" "$3" "$WORK/t_$_r.cyr" "x$1$_r"); xc=$(ec "$2" "$3" "$WORK/c_$_r.cyr" "y$1$_r")
        [ "$xc" = "$_w" ] || bad "$1 row $_r: CONTROL gave $xc, want $_w"
        [ "$xg" = "$_w" ] || bad "$1 row $_r: gave $xg, want $_w"
    done
}
NX=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if build "$CC" "$ROOT/src/main_aarch64.cyr" "$WORK/cc_a64"; then cross_leg aarch64 "$WORK/cc_a64" qemu-aarch64
    else bad "aarch64 leg: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; fi
if command -v wine > /dev/null 2>&1; then
    # CYRIUS_TARGET_WIN=1 makes the host compiler emit PE32+ directly; the binaries run under
    # wine in a PRIVATE prefix (never the user's ~/.wine).
    WCC="$WORK/wcc.sh"
    printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$CC" > "$WCC"; chmod +x "$WCC"
    WRUN="$WORK/wrun.sh"
    printf '#!/bin/sh\nWINEPREFIX="%s" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1"\n' "$WORK/wp" > "$WRUN"; chmod +x "$WRUN"
    cross_leg pe "$WCC" "$WRUN"
else echo "  SKIP: PE leg (wine not installed)"; fi

HOSTROWS=$(grep -cE "^(_row|_refuse) [A-Z]" "$0")
[ "$NROWS" -ge "$HOSTROWS" ] || bad "only $NROWS rows ran; this file spells $HOSTROWS host rows"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: toplevel_for_in: $NFAIL of $NROWS rows"
    exit 1
fi
echo "PASS: toplevel_for_in ($NROWS rows: host + $NX under qemu/wine)"
exit 0
