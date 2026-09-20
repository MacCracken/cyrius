#!/bin/sh
# Gate: a `var` declared inside a TOP-LEVEL block is scoped to that block (6.6.6 bite 19a).
#
# THE DEFECT (measured at 6.6.5, x86_64 Linux, NO diagnostic):
#
#     var c = 1;
#     var x = 0;
#     x = 1;
#     if (c == 1) { var t = 5; }
#     syscall(60, t);            compiled, exit 5
#
# The same shape inside a fn body is `undefined variable 't'`. One spelling, two scoping
# rules: PARSE_VAR's GINFN==0 arm registered a GLOBAL, and the global var table had no scope
# mechanism at all — SCOPE_POP cleared only the frame-local table. The user's decision
# (2026-09-19) is the fn rule for both, with a LOUD error naming the variable.
#
# THE RULE. A top-level block (`if`/`elif`/`else`/`while`/`for`/`switch` body outside every
# fn) scopes its `var`s. Inside the block the name resolves normally and may shadow an outer
# global; at the `}` it is gone, and a later read, write or `&addr` is an error that names the
# variable and says where to declare it instead. Assigning to an OUTER global from inside a
# block is unchanged — only DECLARATIONS are scoped.
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual: every runtime row is checked
# against a CONTROL program that spells the intended meaning without any block at all (the
# inner declaration renamed, or hoisted above the block), compiled by the same compiler — so a
# row cannot pass by both sides sharing one defect. The refusal rows assert the exit code, the
# error text AND that no binary was produced.
#
# LEGS: host x86_64 (every row); cx via the tree's own main_cx + cxvm (rows A/E/F); aarch64
# under qemu-aarch64 when installed (rows A/E/F). qemu and cxvm are EMULATORS, not hardware —
# tests/tcyr/crossos/toplevel_block_var_scope.tcyr is what runs on ecb/ach/cass/pi.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree whose src/ carries the mutation,
# built by build/cycc and run as CYCC=<mutant>, so the cx and aarch64 legs use it too):
#   1. _gvs_pop made a no-op (the 6.6.5 behaviour)     -> RED rows A B C D E I J K
#   2. _gvs_pop marks from index 0, not from the mark   -> RED rows A E F (every earlier global
#                                                         goes out of scope with the block)
#   3. _gvs_push records BEFORE the depth bump          -> RED rows A E F G H J
#   4. _gv_note_blockscoped made a no-op                -> RED rows B C D I J K (the note is the
#                                                         user-visible half of the decision)
#   5. _gvs_pop marks dead with 1, not 2                -> RED rows B C D I J K (a 1 is
#                                                         indistinguishable from a compiler
#                                                         temporary, so no note is printed)
#   6. real tree                                        -> GREEN (12 host rows, 3 cx, 3 aarch64)
# ⚠ HONEST GAP, recorded rather than papered over: the `GINFN(S) != 1` guard inside _gvs_push
#   has NO killing row. Dropping it (so a fn body's blocks record a mark too) leaves every row
#   green, because a fn body registers nothing in the GLOBAL var table — its hidden temporaries
#   are frame slots and its fn-local statics are already marked by _fs_pop, which runs after.
#   The guard is defensive. Do not read this gate's green as proof that it is load-bearing.
# ⚠ The cx and aarch64 rows are REGRESSION GUARDS, not detectors: measured at 6.6.5 both
#   already gave 1 for row A where x86 gave 2, so mutants 1/2/3 redden only the host rows.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: toplevel_block_var_scope: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# build <src> <out>: a failed compile or an EMPTY binary is a failure, never a silent pass
# (cycc on empty input exits 0 and emits a runnable binary, so an unmatched input scores a
# fake PASS — the trap CLAUDE.md names for globbed corpora).
build() {
    if ! "$CC" < "$1" > "$2" 2> "$2.err"; then return 1; fi
    [ -s "$2" ] || return 1
    chmod +x "$2"
    return 0
}
# ec <src> <tag>: compile + run on the host, print the exit code (or CCFAIL)
ec() {
    if ! build "$1" "$WORK/b_$2"; then printf 'CCFAIL'; return 0; fi
    set +e; "$WORK/b_$2" > /dev/null 2>&1; r=$?; set -e
    printf '%s' "$r"
}

# ── runtime rows: <id> <want> <test-src> <control-src> ────────────────────────────────
_row() {
    NROWS=$((NROWS + 1))
    printf '%b' "$3" > "$WORK/t.cyr"
    printf '%b' "$4" > "$WORK/c.cyr"
    got=$(ec "$WORK/t.cyr" t); ctl=$(ec "$WORK/c.cyr" c)
    [ "$ctl" = "$2" ] || bad "row $1: CONTROL gave $ctl, want $2 (the gate's own premise is off)"
    [ "$got" = "$2" ] || bad "row $1: gave $got, want $2"
}

# A — the shadow: an inner declaration of an OUTER name must not overwrite the outer global.
#     Pre-19a this exited 2. The control renames the inner variable, which is what the
#     block-scoped declaration MEANS.
A_T='var a = 1;\nvar g = 0;\ng = 1;\nif (g == 1) { var a = 2; }\nsyscall(60, a);\n'
A_C='var a = 1;\nvar g = 0;\ng = 1;\nif (g == 1) { var a2 = 2; }\nsyscall(60, a);\n'
_row A 1 "$A_T" "$A_C"

# E — the inner name IS visible inside its own block, and may shadow. Control: the inner
#     block reads a differently-named variable holding the same value.
E_T='var a = 1;\nvar s = 0;\nvar g = 0;\ng = 1;\nif (g == 1) { var a = 2; s = a * 10; }\nsyscall(60, s + a);\n'
E_C='var a = 1;\nvar s = 0;\nvar g = 0;\nvar a2 = 2;\ng = 1;\nif (g == 1) { s = a2 * 10; }\nsyscall(60, s + a);\n'
_row E 21 "$E_T" "$E_C"

# F — assignment to an OUTER global from inside a block is NOT a declaration and is unchanged.
F_T='var w = 0;\nvar n = 0;\nwhile (n < 4) { var step = 2; w = w + step; n = n + 1; }\nsyscall(60, w);\n'
F_C='var w = 0;\nvar n = 0;\nvar step = 2;\nwhile (n < 4) { w = w + step; n = n + 1; }\nsyscall(60, w);\n'
_row F 8 "$F_T" "$F_C"

# G — a fn body is untouched: its blocks must not mark GLOBALS dead. A global read after a
#     fn whose body declares a block-local of the same name still resolves.
G_T='var k = 9;\nfn f(): i64 { var c = 1; if (c == 1) { var k = 3; return k; } return 0; }\nvar r = f();\nsyscall(60, r * 10 + k);\n'
G_C='var k = 9;\nfn f(): i64 { var c = 1; if (c == 1) { var k2 = 3; return k2; } return 0; }\nvar r = f();\nsyscall(60, r * 10 + k);\n'
_row G 39 "$G_T" "$G_C"

# H — a DECLARATION-ZONE global declared after a fn that has blocks is still a global (the
#     mark must not survive a fn's scopes and swallow later top-level declarations).
H_T='fn f(): i64 { var c = 1; if (c == 1) { var z = 3; return z; } return 0; }\nvar q = 6;\nvar r = f();\nsyscall(60, q + r);\n'
H_C='fn f(): i64 { var c = 1; var z = 3; if (c == 1) { return z; } return 0; }\nvar q = 6;\nvar r = f();\nsyscall(60, q + r);\n'
_row H 9 "$H_T" "$H_C"

# ── refusal rows: <id> <src> — rc must be 1, the message must name the variable, the note
#    must appear, and NO binary may be produced. ────────────────────────────────────────
_refuse() {
    NROWS=$((NROWS + 1))
    printf '%b' "$2" > "$WORK/r.cyr"
    set +e; "$CC" < "$WORK/r.cyr" > "$WORK/r.bin" 2> "$WORK/r.err"; rc=$?; set -e
    [ "$rc" = "1" ] || bad "row $1: compiler exited $rc, want 1"
    [ -s "$WORK/r.bin" ] && bad "row $1: a binary was emitted for a refused program"
    grep -q "undefined variable 'tbv'" "$WORK/r.err" || bad "row $1: the error does not name 'tbv'"
    grep -q "declared inside a top-level block" "$WORK/r.err" || bad "row $1: no block-scope note"
    grep -q "declare it at top level" "$WORK/r.err" || bad "row $1: the note does not say where to declare it"
}
# B — a READ after the block
_refuse B 'var g = 0;\ng = 1;\nif (g == 1) { var tbv = 5; }\nsyscall(60, tbv);\n'
# C — an ASSIGNMENT after the block (a different resolver path: parse.cyr's statement layer)
_refuse C 'var g = 0;\ng = 1;\nif (g == 1) { var tbv = 5; }\ntbv = 9;\nsyscall(60, g);\n'
# D — an ADDRESS-OF after the block (parse_expr.cyr's `&name` ladder, a third path)
_refuse D 'var g = 0;\ng = 1;\nif (g == 1) { var tbv = 5; }\nvar p = &tbv;\nsyscall(60, g);\n'
# I — a `for` body, and an `else` arm: every top-level block form, not just `if`
_refuse I 'var g = 0;\ng = 1;\nfor (var i = 0; i < 2; i = i + 1) { var tbv = 5; }\nsyscall(60, tbv);\n'
_refuse J 'var g = 0;\ng = 1;\nif (g == 0) { var q = 1; } else { var tbv = 5; }\nsyscall(60, tbv);\n'
# K — a `while` body
_refuse K 'var g = 0;\ng = 1;\nwhile (g == 1) { var tbv = 5; g = 0; }\nsyscall(60, tbv);\n'

# ── negative control for the diagnostic: a name that was NEVER a top-level block var keeps
#    the plain error, with no note. A note on every miss would be noise, and would also pass
#    rows B-K for the wrong reason.
NROWS=$((NROWS + 1))
printf '%b' 'var g = 0;\ng = 1;\nsyscall(60, nosuchname);\n' > "$WORK/n.cyr"
set +e; "$CC" < "$WORK/n.cyr" > "$WORK/n.bin" 2> "$WORK/n.err"; nrc=$?; set -e
[ "$nrc" = "1" ] || bad "row N: a plainly undefined name exited $nrc, want 1"
grep -q "undefined variable 'nosuchname'" "$WORK/n.err" || bad "row N: the error does not name it"
if grep -q "declared inside a top-level block" "$WORK/n.err"; then
    bad "row N: the block-scope note fired for a name that was never a block var"
fi

# ── cx leg: the one target where a global's value is STORED at startup rather than baked
#    into the file image. ⚠ THESE ROWS ARE REGRESSION GUARDS, NOT DETECTORS: measured at
#    6.6.5, cx and aarch64 ALREADY gave 1 for row A where x86 gave 2 (the leak was the x86
#    image-write path). They pin that 19a did not break the targets that were right.
#    cxvm takes the .cyx on STDIN, and the leg carries its own SANITY row so a broken cx
#    build cannot make every row agree on an error code and read green.
NCX=0
CXCC="$WORK/cycc_cx"
CXVM="$WORK/cxvm"
if build "$ROOT/src/main_cx.cyr" "$CXCC" && build "$ROOT/programs/cxvm.cyr" "$CXVM"; then
    cx_ec() {
        printf '%b' "$1" > "$WORK/cx.cyr"
        if ! "$CXCC" < "$WORK/cx.cyr" > "$WORK/cx.cyx" 2>/dev/null; then printf 'CCFAIL'; return 0; fi
        [ -s "$WORK/cx.cyx" ] || { printf 'EMPTY'; return 0; }
        set +e; "$CXVM" < "$WORK/cx.cyx" > /dev/null 2>&1; r=$?; set -e
        printf '%s' "$r"
    }
    # sanity: a program with no block at all, so a cx toolchain that answers the same code to
    # everything (e.g. cxvm's own "not a .cyx file" exit 1) is caught before the rows run.
    cxs=$(cx_ec 'var s = 0;\nvar a2 = 2;\ns = a2 * 10;\nsyscall(60, s);\n')
    if [ "$cxs" = "20" ]; then
        for _p in "A:1:$A_T:$A_C" "E:21:$E_T:$E_C" "F:8:$F_T:$F_C"; do
            _id=${_p%%:*}; _r=${_p#*:}; _w=${_r%%:*}; _r=${_r#*:}
            _t=${_r%%:*}; _c=${_r#*:}
            NCX=$((NCX + 1)); NROWS=$((NROWS + 1))
            cg=$(cx_ec "$_t"); cc2=$(cx_ec "$_c")
            [ "$cc2" = "$_w" ] || bad "cx row $_id: CONTROL gave $cc2, want $_w"
            [ "$cg" = "$_w" ] || bad "cx row $_id: gave $cg, want $_w"
        done
    else
        bad "cx leg: sanity program gave $cxs, want 20 (the cx toolchain is broken; rows would be vacuous)"
    fi
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi
[ "$NCX" -eq 3 ] || bad "floor: $NCX cx rows ran, want 3"

# ── aarch64 leg under qemu-user (an EMULATOR, not hardware — the crossos .tcyr is what runs
#    on ecb/ach/cass/pi). Same regression-guard status as the cx rows.
NA64=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    A64="$WORK/cycc_a64"
    if build "$ROOT/src/main_aarch64.cyr" "$A64"; then
        a64_ec() {
            printf '%b' "$1" > "$WORK/a64.cyr"
            if ! "$A64" < "$WORK/a64.cyr" > "$WORK/a64.bin" 2>/dev/null; then printf 'CCFAIL'; return 0; fi
            [ -s "$WORK/a64.bin" ] || { printf 'EMPTY'; return 0; }
            chmod +x "$WORK/a64.bin"
            set +e; qemu-aarch64 "$WORK/a64.bin" > /dev/null 2>&1; r=$?; set -e
            printf '%s' "$r"
        }
        qs=$(a64_ec 'var s = 0;\nvar a2 = 2;\ns = a2 * 10;\nsyscall(60, s);\n')
        if [ "$qs" = "20" ]; then
            for _p in "A:1:$A_T:$A_C" "E:21:$E_T:$E_C" "F:8:$F_T:$F_C"; do
                _id=${_p%%:*}; _r=${_p#*:}; _w=${_r%%:*}; _r=${_r#*:}
                _t=${_r%%:*}; _c=${_r#*:}
                NA64=$((NA64 + 1)); NROWS=$((NROWS + 1))
                qg=$(a64_ec "$_t"); qc=$(a64_ec "$_c")
                [ "$qc" = "$_w" ] || bad "aarch64 row $_id: CONTROL gave $qc, want $_w"
                [ "$qg" = "$_w" ] || bad "aarch64 row $_id: gave $qg, want $_w"
            done
        else
            bad "aarch64 leg: sanity program gave $qs, want 20 (rows would be vacuous)"
        fi
    else
        bad "aarch64 leg: src/main_aarch64.cyr did not build"
    fi
else
    echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"
fi

# Anti-vacuity: the row counter must have moved past the host rows this file spells out.
HOSTROWS=$(grep -cE "^(_row|_refuse) [A-Z]" "$0")
[ "$NROWS" -ge "$HOSTROWS" ] || bad "only $NROWS rows ran; this file spells $HOSTROWS host rows"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: toplevel_block_var_scope: $NFAIL of $NROWS rows"
    exit 1
fi
echo "PASS: toplevel_block_var_scope ($NROWS rows: host + $NCX cx + $NA64 aarch64-under-qemu)"
exit 0
