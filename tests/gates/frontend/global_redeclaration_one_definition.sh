#!/bin/sh
# Gate: a top-level name declared twice is ONE global, and the last definition wins (6.6.6).
#
# THE DEFECT (measured at 6.6.5, x86_64 Linux, no diagnostic):
#
#     var a = 5;
#     var b = a;
#     var a = 5;          b read 0     (want 5)
#
# and with `var a = 7;` on line 3 the compiler warned "duplicate symbol 'a' redefined with
# conflicting value (last definition wins)" while b STILL read 0 — neither value. The
# redeclaration was given a SECOND slot: every reference binds to the last declaration, so
# the first declaration's baked-in value sat in a slot nothing read, and the second
# declaration (sent to the runtime-store path because it shadowed) stored after b's
# initializer had already run.
#
# THE RULE (docs/guides/cyrius-guide.md "Global Initializers"): in the declaration zone
# (before the first top-level statement) a redeclaration names the SAME global. A constant
# redeclaration is that global's value from program start, so every read sees it — an earlier
# computed initializer of the name still runs, into a discarded sink. A computed redeclaration
# runs in declaration order. A redeclaration that changes the type or size is an error.
# After the first top-level statement a `var` is a statement and a redeclaration starts a new
# variable for the code after it — unchanged, and row J pins it (two in-tree tests rely on it).
#
# EXPECTED VALUES are absolute AND each is checked against a CONTROL program that contains no
# redeclaration at all (the last definition written once, or an assignment in its place),
# compiled by the same compiler — so a row cannot pass by both sides sharing one defect.
#
# LEGS: host x86_64 (every row), cx (A/B/D/L/N/P, via the tree's own main_cx + cxvm — the only
# target where the value is STORED rather than baked into the image), aarch64 under
# qemu-aarch64 when installed (A/B/D/L/N/P; qemu is not hardware — the crossos tcyr covers that).
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree whose src/ carries the mutation, built
# by build/cycc and run as CYCC=<mutant>, so the cx and aarch64 legs are built from it too):
#   m1 whole fix reverted (6.6.5 parse_decl.cyr)  -> RED rows A B C D E F G I K, cx B D, a64 A B D
#   m2 _gv_fold always returns the fresh slot      -> RED rows A B C D E F G I, cx A B D, a64 A B D
#   m3 _gv_supersede made a no-op                  -> RED rows D G, cx B D, a64 D
#   m4 _gv_cx_prestore made a no-op                -> RED cx A B D only
#   m5 replay re-resolves by FINDVAR (no record)   -> RED row K only
#   m6 shape check dropped from _gv_fold           -> RED row I only
#   (m1-m6 were measured before rows G2-G4/K2/K3/L/M/N/P existed; the review mutants below cover those)
#   m7 enum startup store not limited to an enum's slot -> RED rows L M N, cx N, a64 L N
#   m8 var over an enum not given its value on cx      -> RED cx L only
#   m9 main.cyr no longer records the zone (no hiding)   -> RED row K2 only
#   m10 FINDVAR drops the hidden-match fallback          -> RED row K3 only
#   m11 _gv_target honours only target 0 (k > 0 -> the global) -> RED rows G2 G3 G4
#   m12 _gv_target honours targets 0 and 1 only (k > 1)       -> RED row G3 only
#   m13 a shadow that keeps its own slot is never static (6.6.5's `sit_shadow == 0`)
#                                                    -> RED rows L P, cx L P, a64 L P
#   m14 ... only on cx (the non-cx image path kept)    -> RED cx L P only
#   real tree                                      -> GREEN (20 host rows, 6 cx, 6 aarch64)
# Row H is a guard, not a detector: a fn body already read the last declaration before 6.6.6.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: global_redeclaration: $CC missing"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# build <src> <out>: compile with $CC; a failed compile or an empty binary is a FAIL, never
# a silent pass (cycc on empty input still emits a runnable binary).
build() {
    if ! "$CC" < "$1" > "$2" 2> "$2.err"; then return 1; fi
    [ -s "$2" ] || return 1
    chmod +x "$2"
    return 0
}
# ec <src>: compile + run on the host, print the exit code (or CCFAIL)
ec() {
    if ! build "$1" "$WORK/b"; then printf 'CCFAIL'; return 0; fi
    set +e; "$WORK/b" > /dev/null 2>&1; r=$?; set -e
    printf '%s' "$r"
}
# _row <id> <want> <test-src> <control-src>
_row() {
    NROWS=$((NROWS + 1))
    printf '%b' "$3" > "$WORK/t.cyr"
    printf '%b' "$4" > "$WORK/c.cyr"
    got=$(ec "$WORK/t.cyr"); ctl=$(ec "$WORK/c.cyr")
    [ "$ctl" = "$2" ] || bad "row $1: CONTROL gave $ctl, want $2 (the gate's own premise is off)"
    [ "$got" = "$2" ] || bad "row $1: redeclared program gave $got, want $2"
}

# A — the filed repro verbatim: a same-value redeclaration
_row A 5 'var a = 5;\nvar b = a;\nvar a = 5;\nsyscall(60, b);\n' \
         'var a = 5;\nvar b = a;\nsyscall(60, b);\n'
# B — a conflicting redeclaration: the warning's promise, for an EARLIER read
_row B 7 'var a = 5;\nvar b = a;\nvar a = 7;\nsyscall(60, b);\n' \
         'var a = 7;\nvar b = a;\nsyscall(60, b);\n'
# C — the realistic shape: the second declaration comes from an #ifdef arm; an inactive arm
#     contributes nothing
_row C 5 '#define GRX\nvar a = 5;\nvar b = a;\n#ifdef GRX\nvar a = 5;\n#endif\n#ifdef GRNOPE\nvar a = 9;\n#endif\nsyscall(60, b * 10 + a - 50);\n' \
         'var a = 5;\nvar b = a;\nsyscall(60, b * 10 + a - 50);\n'
# D — earlier COMPUTED, later constant: the constant wins everywhere and the computed
#     initializer still runs once (exit = b*10 + calls)
_row D 91 'var n = 0;\nfn f5() { n = n + 1; return 5; }\nvar a = f5();\nvar b = a;\nvar a = 9;\nsyscall(60, b * 10 + n);\n' \
          'var n = 0;\nfn f5() { n = n + 1; return 5; }\nvar t = f5();\nvar a = 9;\nvar b = a;\nsyscall(60, b * 10 + n);\n'
# E — earlier constant, later COMPUTED: a read before it sees the constant; the control
#     spells the second definition as an assignment
_row E 57 'fn f7() { return 7; }\nvar a = 5;\nvar b = a;\nvar a = f7();\nsyscall(60, b * 10 + a);\n' \
          'fn f7() { return 7; }\nvar a = 5;\nvar b = a;\na = f7();\nsyscall(60, b * 10 + a);\n'
# F — a chain: the LAST constant wins, and every link is reported (the 3rd link was missed)
_row F 4 'var a = 1;\nvar b = a;\nvar a = 2;\nvar a = 4;\nsyscall(60, b);\n' \
         'var a = 4;\nvar b = a;\nsyscall(60, b);\n'
build "$WORK/t.cyr" "$WORK/tf" || true   # the row's TEST source (b.err is the control's)
nw=$(grep -c "duplicate symbol 'a' redefined with conflicting value (last definition wins)" "$WORK/tf.err" || true)
[ "$nw" = "2" ] || bad "row F: want the collision warning on BOTH later links, got $nw"
# G — a destructure target superseded by a later constant; its other target is untouched
_row G 51 'fn p() { return (20, 21); }\nvar m, n = p();\nvar o = m;\nvar m = 30;\nsyscall(60, o + n);\n' \
          'fn p() { return (20, 21); }\nvar m2, n = p();\nvar m = 30;\nvar o = m;\nsyscall(60, o + n);\n'
# G2 — a destructure's SECOND target superseded (target 1 of the replay entry): o sees 30, and
#      the first target keeps its value (exit = o + n + m)
_row G2 80 'fn p() { return (20, 21); }\nvar m, n = p();\nvar o = n;\nvar n = 30;\nsyscall(60, o + n + m);\n' \
           'fn p() { return (20, 21); }\nvar m, n2 = p();\nvar n = 30;\nvar o = n;\nsyscall(60, o + n + m);\n'
# G3 — a three-name destructure's THIRD target superseded (target 2)
_row G3 101 'fn p() { return (20, 21, 22); }\nvar m, n, q = p();\nvar o = q;\nvar q = 30;\nsyscall(60, o + q + m + n);\n' \
            'fn p() { return (20, 21, 22); }\nvar m, n, q2 = p();\nvar q = 30;\nvar o = q;\nsyscall(60, o + q + m + n);\n'
# G4 — a three-name destructure's MIDDLE target superseded (target 1 on the three-name path)
_row G4 102 'fn p() { return (20, 21, 22); }\nvar m, n, q = p();\nvar o = n;\nvar n = 30;\nsyscall(60, o + n + m + q);\n' \
            'fn p() { return (20, 21, 22); }\nvar m, n2, q = p();\nvar n = 30;\nvar o = n;\nsyscall(60, o + n + m + q);\n'
# H — a fn body reads the one global
_row H 7 'var a = 5;\nfn g() { return a; }\nvar a = 7;\nsyscall(60, g());\n' \
         'fn g() { return a; }\nvar a = 7;\nsyscall(60, g());\n'
# L — a var over an ENUM constant, conflicting value: the var is the last definition, for an
#     early read and a fn alike. The enum's startup store used to land in the var's slot after
#     the var became static (6.6.6 pre-review: 55 here, i.e. both reads saw the enum's 5)
_row L 77 'enum E { K = 5; }\nvar b = K;\nvar K = 7;\nfn g() { return K; }\nsyscall(60, b * 10 + g());\n' \
          'var K = 7;\nvar b = K;\nfn g() { return K; }\nsyscall(60, b * 10 + g());\n'
# M — the same through a fold: a var over the enum, then a constant redeclaration of the var
_row M 77 'enum E { K = 5; }\nvar K = 5;\nvar b = K;\nvar K = 7;\nfn g() { return K; }\nsyscall(60, b * 10 + g());\n' \
          'var K = 7;\nvar b = K;\nfn g() { return K; }\nsyscall(60, b * 10 + g());\n'
# N — a var over an enum constant with the value ZERO: an early read sees 0, not the enum's 5
_row N 10 'enum E { K = 5; }\nvar b = K;\nvar K = 0;\nsyscall(60, b + 10);\n' \
          'var K = 0;\nvar b = K;\nsyscall(60, b + 10);\n'
# I — a declaration-zone redeclaration that changes the type or size is refused by name
NROWS=$((NROWS + 1))
printf 'var a = 5;\nvar a: i32 = 7;\nsyscall(60, a);\n' > "$WORK/i1.cyr"
printf 'var q[8];\nvar q[16];\nsyscall(60, 0);\n' > "$WORK/i2.cyr"
for f in i1 i2; do
    if "$CC" < "$WORK/$f.cyr" > "$WORK/$f.bin" 2> "$WORK/$f.err"; then
        bad "row I ($f): a type/size-changing redeclaration COMPILED"
    elif ! grep -q "redeclared with a different type or size" "$WORK/$f.err"; then
        bad "row I ($f): refused without the redeclaration diagnostic: $(head -c 200 "$WORK/$f.err")"
    fi
done
# J — after the first top-level statement a redeclaration is a NEW variable (fresh buffer of
#     the new size) — the pattern tests/tcyr/crypto/tls12_handshake_msgs.tcyr relies on
_row J 1 'var z = 0;\nz = 1;\nvar buf[8];\nstore8(&buf, 9);\nvar buf[48];\nsyscall(60, load8(&buf) + 1);\n' \
         'var z = 0;\nz = 1;\nvar buf[8];\nstore8(&buf, 9);\nvar buf2[48];\nsyscall(60, load8(&buf2) + 1);\n'
# K — a kernel build replays the declaration-zone initializers AFTER the top-level program, so
#     re-resolving the name then found the program's later `var a` and stored `a = f5()` into
#     THAT slot. With the slot recorded at declaration, renaming the later variable changes no
#     byte of the (stripped) image. Not runnable here (multiboot ELF32); compared structurally.
NROWS=$((NROWS + 1))
printf 'kernel;\nfn f5() { return 5; }\nvar a = f5();\nvar z = 0;\nz = 1;\nvar a = 3;\nz = a;\n' > "$WORK/k1.cyr"
printf 'kernel;\nfn f5() { return 5; }\nvar a = f5();\nvar z = 0;\nz = 1;\nvar c = 3;\nz = c;\n' > "$WORK/k2.cyr"
if build "$WORK/k1.cyr" "$WORK/k1" && build "$WORK/k2.cyr" "$WORK/k2"; then
    cmp -s "$WORK/k1" "$WORK/k2" || bad "row K: kernel-mode replay stored into the later declaration's slot"
else
    bad "row K: kernel-mode compile failed: $(head -c 200 "$WORK/k1.err" "$WORK/k2.err" 2>/dev/null)"
fi
# K2 — the same replay READING a name the program redeclares later: `var b = id(a);` resolved `a`
#      to the program's `var a = 3` (the kernel replay runs after it is registered) instead of the
#      declaration-zone `a` every other build reads (a non-kernel build of it gives b = 5). Also
#      a superseded initializer (its sink is registered DURING the replay and must stay visible).
NROWS=$((NROWS + 1))
printf 'kernel;\nvar n = 0;\nvar a = 5;\nfn id(x) { n = n + 1; return x; }\nvar b = id(a);\nvar d = id(7);\nvar d = 9;\nvar z = 0;\nz = 1;\nvar a = 3;\nvar d = 4;\nz = a + b + d + n;\n' > "$WORK/k3.cyr"
printf 'kernel;\nvar n = 0;\nvar a = 5;\nfn id(x) { n = n + 1; return x; }\nvar b = id(a);\nvar d = id(7);\nvar d = 9;\nvar z = 0;\nz = 1;\nvar c = 3;\nvar e = 4;\nz = c + b + e + n;\n' > "$WORK/k4.cyr"
if build "$WORK/k3.cyr" "$WORK/k3" && build "$WORK/k4.cyr" "$WORK/k4"; then
    cmp -s "$WORK/k3" "$WORK/k4" || bad "row K2: kernel-mode replay read a name from the program's later declaration"
else
    bad "row K2: kernel-mode compile failed: $(head -c 200 "$WORK/k3.err" "$WORK/k4.err" 2>/dev/null)"
fi
# K3 (guard) — a name ONLY the program declares still resolves in a kernel replay, as it did
#      before K2's fix (a non-kernel build rejects it; the kernel ordering always accepted it, and
#      the fix must not turn a building kernel into a failing one)
NROWS=$((NROWS + 1))
printf 'kernel;\nfn id(x) { return x; }\nvar b = id(c);\nvar z = 0;\nz = 1;\nvar c = 3;\nz = b;\n' > "$WORK/k5.cyr"
build "$WORK/k5.cyr" "$WORK/k5" || bad "row K3: a kernel replay no longer finds a name only the program declares: $(head -c 200 "$WORK/k5.err")"

# P — a redeclaration with a DIFFERENT visibility owner (`public var` then a private `var` of the
#     same name, in one private file) is a separate global, not a fold — and the later one was
#     sent to the runtime-store path, so a read between the two saw 0 (the same root cause). The
#     rule holds there too: the read sees the last definition. Needs a real file (visibility is
#     per file), so it runs from $WORK/p; the cx and aarch64 legs repeat it below.
NROWS=$((NROWS + 1))
mkdir -p "$WORK/p/lib"
printf 'private\npublic var qx = 5;\npublic var qb = qx;\nvar qx = 7;\npublic fn q1b(): i64 { return qb * 10 + qx; }\n' > "$WORK/p/lib/q.cyr"
printf 'private\npublic var qx0 = 5;\nvar qx = 7;\npublic var qb = qx;\npublic fn q1b(): i64 { return qb * 10 + qx; }\n' > "$WORK/p/lib/c.cyr"
printf 'include "lib/q.cyr"\nsyscall(60, q1b());\n' > "$WORK/p/t.cyr"
printf 'include "lib/c.cyr"\nsyscall(60, q1b());\n' > "$WORK/p/c.cyr"
got=$(cd "$WORK/p" && ec t.cyr); ctl=$(cd "$WORK/p" && ec c.cyr)
[ "$ctl" = "77" ] || bad "row P: CONTROL gave $ctl, want 77 (the gate's own premise is off)"
[ "$got" = "77" ] || bad "row P: a different-owner redeclaration gave $got, want 77"

# ---- cx leg: the tree's own cx compiler + cxvm (value is stored, not baked) ----
NCX=0
if build "$ROOT/src/main_cx.cyr" "$WORK/cycc_cx" && build "$ROOT/programs/cxvm.cyr" "$WORK/cxvm"; then
    for spec in 'A|5|var a = 5;\nvar b = a;\nvar a = 5;\nsyscall(60, b);\n' \
                'B|7|var a = 5;\nvar b = a;\nvar a = 7;\nsyscall(60, b);\n' \
                'D|91|var n = 0;\nfn f5() { n = n + 1; return 5; }\nvar a = f5();\nvar b = a;\nvar a = 9;\nsyscall(60, b * 10 + n);\n' \
                'L|77|enum E { K = 5; }\nvar b = K;\nvar K = 7;\nfn g() { return K; }\nsyscall(60, b * 10 + g());\n' \
                'N|10|enum E { K = 5; }\nvar b = K;\nvar K = 0;\nsyscall(60, b + 10);\n'; do
        id=${spec%%|*}; rest=${spec#*|}; want=${rest%%|*}; src=${rest#*|}
        printf '%b' "$src" > "$WORK/x.cyr"
        if "$WORK/cycc_cx" < "$WORK/x.cyr" > "$WORK/x.cyx" 2> /dev/null && [ -s "$WORK/x.cyx" ]; then
            set +e; "$WORK/cxvm" < "$WORK/x.cyx" > /dev/null 2>&1; r=$?; set -e
            [ "$r" = "$want" ] || bad "cx row $id: gave $r, want $want"
        else
            bad "cx row $id: cx compile failed"
        fi
        NCX=$((NCX + 1))
    done
    if (cd "$WORK/p" && "$WORK/cycc_cx" < t.cyr > "$WORK/p.cyx" 2> /dev/null) && [ -s "$WORK/p.cyx" ]; then
        set +e; "$WORK/cxvm" < "$WORK/p.cyx" > /dev/null 2>&1; r=$?; set -e
        [ "$r" = "77" ] || bad "cx row P: gave $r, want 77"
    else
        bad "cx row P: cx compile failed"
    fi
    NCX=$((NCX + 1))
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi

# ---- aarch64 leg (qemu-aarch64, NOT hardware) ----
NA64=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if build "$ROOT/src/main_aarch64.cyr" "$WORK/cycc_a64"; then
        for spec in 'A|5|var a = 5;\nvar b = a;\nvar a = 5;\nsyscall(60, b);\n' \
                    'B|7|var a = 5;\nvar b = a;\nvar a = 7;\nsyscall(60, b);\n' \
                    'D|91|var n = 0;\nfn f5() { n = n + 1; return 5; }\nvar a = f5();\nvar b = a;\nvar a = 9;\nsyscall(60, b * 10 + n);\n' \
                    'L|77|enum E { K = 5; }\nvar b = K;\nvar K = 7;\nfn g() { return K; }\nsyscall(60, b * 10 + g());\n' \
                    'N|10|enum E { K = 5; }\nvar b = K;\nvar K = 0;\nsyscall(60, b + 10);\n'; do
            id=${spec%%|*}; rest=${spec#*|}; want=${rest%%|*}; src=${rest#*|}
            printf '%b' "$src" > "$WORK/y.cyr"
            if "$WORK/cycc_a64" < "$WORK/y.cyr" > "$WORK/y.bin" 2> /dev/null && [ -s "$WORK/y.bin" ]; then
                chmod +x "$WORK/y.bin"
                set +e; qemu-aarch64 "$WORK/y.bin" > /dev/null 2>&1; r=$?; set -e
                [ "$r" = "$want" ] || bad "aarch64 row $id: gave $r, want $want"
            else
                bad "aarch64 row $id: compile failed"
            fi
            NA64=$((NA64 + 1))
        done
        if (cd "$WORK/p" && "$WORK/cycc_a64" < t.cyr > "$WORK/p.a64" 2> /dev/null) && [ -s "$WORK/p.a64" ]; then
            chmod +x "$WORK/p.a64"
            set +e; qemu-aarch64 "$WORK/p.a64" > /dev/null 2>&1; r=$?; set -e
            [ "$r" = "77" ] || bad "aarch64 row P: gave $r, want 77"
        else
            bad "aarch64 row P: compile failed"
        fi
        NA64=$((NA64 + 1))
    else
        bad "aarch64 leg: could not build src/main_aarch64.cyr"
    fi
else
    echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"
fi

# Floor, DERIVED from this file: every host row that was declared must have run.
DECL=$(grep -c '^_row ' "$0")
DECL=$((DECL + 5))   # rows I, K, K2, K3 and P are hand-rolled
[ "$NROWS" -eq "$DECL" ] || bad "floor: $NROWS host rows ran, $DECL declared"
[ "$NCX" -eq 6 ] || bad "floor: $NCX cx rows ran, want 6"

if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: global_redeclaration_one_definition: $NFAIL check(s) failed"
    exit 1
fi
echo "PASS: a redeclared top-level global is ONE global and the last definition wins ($NROWS host rows, $NCX cx, $NA64 aarch64-under-qemu) (6.6.6)"
exit 0
