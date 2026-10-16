#!/bin/sh
# Gate: a name a closure body declares is not a capture of the enclosing local of that name (6.7.11).
#
# THE DEFECT (measured 6.6.0 - 6.7.10, x86_64 and aarch64):
#
#     fn fi(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i + n; } return s; }; .. }
#     fn fc(): i64 { var k = 5; var cl = |n| { const k = 3; return k + n; }; .. }
#     fn fm(): i64 { var b = 5; var cl = |n| { var a, b = two(); return a + b + n; }; .. }
#
# None of the three closures reads the enclosing local, yet each was refused: "a capturing closure
# needs include "lib/alloc.cyr" for its heap env". The capture pre-scan (`_cl_prescan_body`)
# shadowed only the name right after `var`; a `for … in` variable, a local const's name and the
# second / third name of a destructure were taken for reads. With lib/alloc.cyr the values were
# right, but each closure carried a heap env holding a copy of a local it never read.
#
# THE FIX (src/frontend/parse_expr.cyr): each name is shadowed from where the PARSER binds it.
# `const` names one as `var` does. `_cl_prescan_forin`: the start bound or the collection is read in
# the enclosing scope (PARSE_FOR parses it before it registers the variable), then the variable is
# shadowed for a range's end bound (which reads it) and the body, and dropped after the loop.
# `_cl_prescan_mvar`: a destructure's right-hand side is read first (PARSE_VAR binds the names
# after it), then its second and third names are shadowed.
#
# ROWS: id|mode|want|source (printf %b; the prelude below is prepended). mode n: no lib/alloc.cyr —
# the source compiles and exits `want`. mode a: with lib/alloc.cyr — it exits `want`. mode r: no
# lib/alloc.cyr — the source is REFUSED with exactly `want` "a capturing closure needs" errors (a
# real capture is still a capture). mode x: refused by the PARSER, its report holding `want`. I / IC /
# C / M rows were refused before the fix; the K rows
# are CONTROLS that held before and after: KI1-KI2 a read after the loop, KI3-KI4 a range's start
# bound, KC1-KC2 the collection, KK1-KK4 an enclosing name after a nested block's const and beside
# one, KM1-KM4 a destructure's right-hand side and a read after a nested block's destructure. The
# `a` controls carry a GLOBAL of the same name, so a dropped capture reads it (a wrong value, not
# only a refusal): the 6.6.17 class this pre-scan can fall into.
#
# LEGS: host x86_64; cx via the tree's own main_cx + cxvm; aarch64 under qemu-aarch64 —
# EMULATION, not hardware. The fix is in the shared frontend, so every fork takes it. The filed
# repro file runs on every leg.
#
# MUTATION LEDGER (6.7.11 — each mutant is a scratch copy of the tree whose src/ carries the
# change, built by build/cycc into the scratch tree's build/cycc, with this gate run from the
# scratch tree, so the cx and aarch64 legs are built from the mutated src too):
#   m0 the pre-fix src                              -> RED I1-I3 IC1 C1 C2 M1 M2 and the repro, every leg (27)
#   m1 the `const` arm dropped (`t == 168`)          -> RED C1 C2 and the repro, every leg (9)
#   m2 the destructure arm dropped (`_cl_at_mvar` 0) -> RED M1 M2 and the repro, every leg (9)
#   m3 the for-in arm dropped (`_cl_at_forin` 0)     -> RED I1-I3 IC1 and the repro, every leg (15)
#   m4 the for-in variable shadowed from its name    -> RED KI3 KC1 (refused 'undefined variable'),
#                                                       KI4 (6) and KC2 (64): the GLOBAL read, every leg (12)
#   m5 a destructure's names shadowed at the names   -> RED KM1 (refused 'undefined variable'), KM2 (88:
#                                                       the global `b`), every leg (6)
#   real tree                                        -> GREEN (69: 22 rows and the repro per leg)
#
# 6.7.13 — THE OTHER DIRECTION: A READ DROPPED (issues/2026-10-14-closure-var-initializer-reading-its-
# own-name-drops-the-capture.md, measured 6.6.0 - 6.7.12): `|n| { var a = a + n; .. }` with an
# enclosing `a` read a GLOBAL `a` (101 for 6), or was refused "undefined variable 'a'"; so did a
# destructure's FIRST name (`var a, b = tw(a + n);`: 88 for 67), a typed `var a: i64 = a + n;` and a
# classic `for (var a = a; ..)` header (0 for 18). PARSE_VAR binds after the right-hand side, the
# pre-scan shadowed from the name. The fix: `_cl_prescan_var` walks a `var`'s tail (mode 4) before
# shadowing its name; `_cl_prescan_mvar` shadows the first name with the others.
# V1-V9: the value rows (mode a, a global `a`) and the refusals without lib/alloc.cyr (mode r: the
# read IS a capture, the user's decision D35 A, 2026-10-15); KV1-KV3 controls (no read of the
# enclosing name: they build without lib/alloc.cyr, before and after); the filed repros RV1 / RV1g /
# RV2 verbatim.
#   m6 the pre-fix src                              -> RED V1-V9 RV1 RV1g RV2, every leg (36)
#   m7 the `_cl_prescan_var` arm dropped            -> RED V1 V3 V5-V9 RV1 RV2, every leg (27)
#   m8 a destructure's first name shadowed at it    -> RED V2 V4 RV1g, every leg (9)
#   real tree                                       -> GREEN (114: 34 rows and 4 repros per leg)
#
# 6.7.13 — A NESTED CLOSURE'S PARAMETERS ARE ITS OWN (issues/2026-10-14-nested-closure-parameter-
# taken-as-outer-capture.md, measured 6.6.0 - 6.7.12): `|n| { var g = |m| m + 1; .. }` beside an
# enclosing `m` was refused without lib/alloc.cyr (the outer pre-scan read the nested literal's `m`,
# and its body's reads of it, as reads of the enclosing `m`), or built a heap env holding a copy never
# read. The fix: at a literal's opening `|` (`_cl_at_lit`: an operand position — the walk's first
# token, or after a token that cannot end an operand — and the parser's `| IDENT, .. |` list after
# it) the parameters are shadowed for its body only (`_cl_prescan_lit`). P1-P6: the filed repro's two
# closures, a literal as a call argument, a curried body (`|n| |m| ..`), a classic-for initializer, a
# literal nested in a literal — each builds without lib/alloc.cyr. KP1-KP11 controls: a nested body's
# NON-parameter name still captured through both levels (KP1 / KP2), a bitwise `|` after a name, a
# `)` and a number beside a literal (KP3-KP5: reading one as a literal would DROP the capture between
# its bars), a `||` thunk (KP6 / KP7), a sibling literal reading the enclosing name (KP8), a typed
# `|m: i64|` (KP9: refused by the parser at the `:`, as before — a closure's parameters are untyped),
# the enclosing name read after a block-bodied and an expression-bodied literal (KP10 / KP11: the
# shadow ends with the literal). RN: the filed repro verbatim (26).
#   m9  the pre-fix src (this bite's base)          -> RED P1-P6 RN, every leg (21)
#   m10 `_cl_lit_pos` answering 1 (no position)     -> RED KP3 (103) KP4 (211) KP5 (undefined 'q'), every leg (9)
#   m11 the walk's-first-token rule dropped         -> RED P4, every leg (3)
#   m12 the parameter shadow kept after the literal -> RED KP10 (102) KP11 (233: the global m), every leg (6)
#   real tree                                       -> GREEN (168: 51 rows and 5 repros per leg)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: closure_declared_names_not_captured: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: closure_declared_names_not_captured: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: closure_declared_names_not_captured: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

# The prelude: a two- and a three-value fn, and a `vec_len` / `vec_get` pair the collection
# `for x in c` calls by name (element i of collection v is v + i — no heap, so a mode-n row
# needs no lib/alloc.cyr).
cat > "$WORK/prelude" <<'PRE'
fn two(): (i64, i64) { return (3, 4); }
fn tw(x): (i64, i64) { return (x, x + 1); }
fn three(): (i64, i64, i64) { return (1, 2, 3); }
fn vec_len(v): i64 { return 3; }
fn vec_get(v, i): i64 { return v + i; }
PRE

cat > "$WORK/rows" <<'ROWS'
I1|n|10|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i + n; } return s; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
I2|n|1|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..i { s = s + 1; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
I3|n|5|fn f(): i64 { var i = 3; var j = 4; var cl = |n| { var s = 0; for i in 0..2 { for j in 0..2 { s = s + i + j; } } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
IC1|n|34|fn f(): i64 { var x = 5; var cl = |n| { var s = 0; for x in 10 { s = s + x; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
C1|n|4|fn f(): i64 { var k = 5; var cl = |n| { const k = 3; return k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
C2|n|9|fn f(): i64 { var k = 5; var cl = |n| { var s = 0; if (n > 0) { const k = 4; s = k * 2; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
M1|n|8|fn f(): i64 { var b = 5; var cl = |n| { var a, b = two(); return a + b + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
M2|n|7|fn f(): i64 { var c = 9; var b = 9; var cl = |n| { var a, b, c = three(); return a + b + c + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI1|r|1|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i; } return s + i + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI2|a|10|var i = 40;\nfn f(): i64 { alloc_init(); var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i; } return s + i + n; }; i = 50; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI3|r|1|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in i..5 { s = s + 1; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI4|a|3|var i = 0;\nfn f(): i64 { alloc_init(); var i = 3; var cl = |n| { var s = 0; for i in i..5 { s = s + 1; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KC1|r|1|fn f(): i64 { var x = 10; var cl = |n| { var s = 0; for x in x { s = s + x; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KC2|a|34|var x = 20;\nfn f(): i64 { alloc_init(); var x = 10; var cl = |n| { var s = 0; for x in x { s = s + x; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK1|r|1|fn f(): i64 { var k = 5; var cl = |n| { var s = 0; if (n > 0) { const k = 3; s = k; } return s + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK2|a|9|var k = 70;\nfn f(): i64 { alloc_init(); var k = 5; var cl = |n| { var s = 0; if (n > 0) { const k = 3; s = k; } return s + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK3|r|1|fn f(): i64 { var k = 5; var cl = |n| { const c = 3; return c + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK4|a|9|fn f(): i64 { alloc_init(); var k = 5; var cl = |n| { const c = 3; return c + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM1|r|1|fn f(): i64 { var b = 5; var cl = |n| { var a, b = tw(b + n); return a * 10 + b; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM2|a|67|var b = 100;\nfn f(): i64 { alloc_init(); var b = 5; var cl = |n| { var a, b = tw(b + n); return a * 10 + b; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM3|r|1|fn f(): i64 { var b = 5; var cl = |n| { var s = 0; if (n > 0) { var a, b = two(); s = a + b; } return s + b + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM4|a|13|var b = 100;\nfn f(): i64 { alloc_init(); var b = 5; var cl = |n| { var s = 0; if (n > 0) { var a, b = two(); s = a + b; } return s + b + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
V1|a|6|var a = 100;\nfn f(): i64 { alloc_init(); var a = 5; var cl = |n| { var a = a + n; return a; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
V2|a|67|var a = 100;\nfn g(): i64 { alloc_init(); var a = 5; var cl = |n| { var a, b = tw(a + n); return a * 10 + b; }; return fncall1(cl, 1); }\nsyscall(60, g());\n
V3|r|1|fn f(): i64 { var a = 5; var cl = |n| { var a = a + n; return a; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
V4|r|1|fn g(): i64 { var a = 5; var cl = |n| { var a, b = tw(a + n); return a * 10 + b; }; return fncall1(cl, 1); }\nsyscall(60, g());\n
V5|a|6|var a = 100;\nfn f(): i64 { alloc_init(); var a = 5; var cl = |n| { var a: i64 = a + n; return a; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
V6|r|1|fn f(): i64 { var a = 5; var cl = |n| { var a: i64 = a + n; return a; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
V7|a|18|var a = 100;\nfn f(): i64 { alloc_init(); var a = 5; var cl = |n| { var s = 0; for (var a = a; a < 8; a = a + 1) { s = s + a; } return s + n; }; return fncall1(cl, 0); }\nsyscall(60, f());\n
V8|r|1|fn f(): i64 { var a = 5; var cl = |n| { var s = 0; for (var a = a; a < 8; a = a + 1) { s = s + a; } return s + n; }; return fncall1(cl, 0); }\nsyscall(60, f());\n
V9|a|13|var a = 100;\nfn f(): i64 { alloc_init(); var a = 5; var cl = |n| { var a = a + n; a = a * 2; return a + 1; }; a = 50; return fncall1(cl, 1); }\nsyscall(60, f());\n
KV1|n|2|fn f(): i64 { var a = 5; var cl = |n| { var a = n; return a + 1; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KV2|n|4|fn f(): i64 { var a = 5; var b = 9; var cl = |n| { var a: i64 = n; for (var b = n; b < 3; b = b + 1) { a = a + b; } return a; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KV3|n|7|fn f(): i64 { var a = 5; var cl = |n| { var a, b = tw(n); return a + b + a; }; return fncall1(cl, 2); }\nsyscall(60, f());\n
P1|n|2|fn f(): i64 { var m = 5; var cl = |n| { var g = |m| m + 1; return fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
P2|n|6|fn h(): i64 { var m = 5; var cl = |n| { var g = |m| { return m * 2; }; return fncall1(g, n); }; return fncall1(cl, 3); }\nsyscall(60, h());\n
P3|n|23|fn f(): i64 { var m = 5; var k = 9; var cl = |n| fncall2(|m, k| m * 10 + k, n, 3); return fncall1(cl, 2); }\nsyscall(60, f());\n
P4|n|6|fn f(): i64 { var m = 5; var cl = |n| |m| m * 2; return fncall1(fncall1(cl, 1), 3); }\nsyscall(60, f());\n
P5|n|5|fn f(): i64 { var m = 5; var cl = |n| { var s = 0; for (var i = fncall1(|m| m + 1, n); i < 4; i = i + 1) { s = s + i; } return s; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
P6|n|2|fn f(): i64 { var m = 5; var cl = |n| { var g = |m| { var h = |k| k + 1; return fncall1(h, m); }; return fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP1|a|6|var q = 100;\nfn f(): i64 { alloc_init(); var q = 5; var m = 7; var cl = |n| { var g = |m| m + q; return fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP2|r|2|fn f(): i64 { var q = 5; var m = 7; var cl = |n| { var g = |m| m + q; return fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP3|a|9|var q = 100;\nfn f(): i64 { alloc_init(); var q = 6; var cl = |n| { var g = |m| m + 1; return (n | q | 0) + fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP4|a|23|var q = 100;\nfn f(): i64 { alloc_init(); var q = 6; var cl = |n| { var g = |m| m + 1; return ((n + 0) | q | 0) + (8 | q | 0) + fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP5|r|1|fn f(): i64 { var q = 6; var cl = |n| n | q | 0; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP6|a|6|var m = 100;\nfn f(): i64 { alloc_init(); var m = 5; var cl = |n| { var t = || m + n; return fncall0(t); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP7|r|2|fn f(): i64 { var m = 5; var cl = |n| { var t = || m + 1; return fncall0(t) + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP8|a|13|var m = 100;\nfn f(): i64 { alloc_init(); var m = 5; var cl = |n| { var g = |k| m + k; var h = |m| m * 2; return fncall1(g, n) + fncall1(h, n) + m; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP9|x|got ':'|fn f(): i64 { var m = 5; var cl = |n| { var g = |m: i64| m + 1; return fncall1(g, n); }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP10|a|7|var m = 100;\nfn f(): i64 { alloc_init(); var m = 5; var cl = |n| { var h = |m| { return m * 2; }; return fncall1(h, n) + m; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KP11|a|51|var m = 100;\nfn f(): i64 { alloc_init(); var m = 5; var cl = |n| fncall2(|m, k| m * 10 + k, m, n); return fncall1(cl, 1); }\nsyscall(60, f());\n
ROWS
NTAB=$(grep -c '|' "$WORK/rows")

# run_row <leg> <compiler> <runner> <id> <mode> <want> <src> — runner is "" for native
run_row() {
    {
        printf 'include "lib/fnptr.cyr"\n'
        if [ "$5" = a ]; then printf 'include "lib/alloc.cyr"\n'; fi
        cat "$WORK/prelude"
        printf '%b' "$7"
    } > "$WORK/t.cyr"
    if [ "$5" = x ]; then
        if build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then bad "$1 row $4: compiled, want refused by the parser"; return 0; fi
        grep -qF -- "$6" "$WORK/t.bin.err" || bad "$1 row $4: refused, but without '$6': $(grep '^error' "$WORK/t.bin.err" | head -1 | head -c 300)"
        return 0
    fi
    if [ "$5" = r ]; then
        if build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
            bad "$1 row $4: compiled, want refused (a real capture must still be one)"; return 0
        fi
        n=$(grep -c 'a capturing closure needs include "lib/alloc.cyr"' "$WORK/t.bin.err" || true)
        [ "$n" = "$6" ] || bad "$1 row $4: $n capture refusal(s), want $6: $(head -c 300 "$WORK/t.bin.err")"
        return 0
    fi
    if ! build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
        bad "$1 row $4: compile failed: $(grep error "$WORK/t.bin.err" | head -1 | head -c 300)"; return 0
    fi
    chmod +x "$WORK/t.bin"
    set +e
    if [ -n "$3" ]; then $3 "$WORK/t.bin" > /dev/null 2>&1
    else "$WORK/t.bin" > /dev/null 2>&1; fi
    r=$?
    set -e
    [ "$r" = "$6" ] || bad "$1 row $4: exited $r, want $6"
    return 0
}

# The filed repros, verbatim. RP: rows I1 / C1 / M1 carry its three closures (exit 22). RV1 / RV2:
# issues/2026-10-14-closure-var-initializer-reading-its-own-name-drops-the-capture.md's two (6.7.13):
# RV1 exits 6; RV1g is RV1 with its commented line swapped in (the filing's g variant), 67; RV2 has no
# lib/alloc.cyr, so the read it makes is refused AS A CAPTURE (the user's decision D35 A, 2026-10-15).
RPD="$ROOT/docs/development/issues/repros"
RP="$RPD/2026-10-11-closure-prescan-reads-declared-names-as-captures.cyr"
RV1="$RPD/2026-10-14-closure-var-initializer-reading-its-own-name-1.cyr"
RV2="$RPD/2026-10-14-closure-var-initializer-reading-its-own-name-2.cyr"
RN="$RPD/2026-10-14-nested-closure-parameter-taken-as-outer-capture.cyr"   # 6.7.13: builds without lib/alloc.cyr, 26
# run_repro <leg> <compiler> <runner> <file> <want: an exit code, or r = one capture refusal>
run_repro() {
    NROWS=$((NROWS + 1))
    if [ ! -f "$4" ]; then bad "$1 repro $(basename "$4"): missing"; return 0; fi
    if [ "$5" = r ]; then
        if build "$2" "$4" "$WORK/rp.bin"; then bad "$1 repro $(basename "$4"): compiled, want refused as a capture"; return 0; fi
        n=$(grep -c 'a capturing closure needs include "lib/alloc.cyr"' "$WORK/rp.bin.err" || true)
        e=$(grep -c '^error' "$WORK/rp.bin.err" || true)
        [ "$n" = 1 ] && [ "$e" = 1 ] || bad "$1 repro $(basename "$4"): $n capture refusal(s) in $e error(s), want 1 of 1: $(grep '^error' "$WORK/rp.bin.err" | head -2 | tr '\n' '|' | head -c 300)"
        return 0
    fi
    if ! build "$2" "$4" "$WORK/rp.bin"; then
        bad "$1 repro $(basename "$4"): compile failed: $(grep error "$WORK/rp.bin.err" | head -1 | head -c 300)"; return 0
    fi
    chmod +x "$WORK/rp.bin"
    set +e
    if [ -n "$3" ]; then $3 "$WORK/rp.bin" > /dev/null 2>&1
    else "$WORK/rp.bin" > /dev/null 2>&1; fi
    r=$?
    set -e
    [ "$r" = "$5" ] || bad "$1 repro $(basename "$4"): exited $r, want $5"
    return 0
}
RV1G="$WORK/2026-10-14-closure-var-initializer-reading-its-own-name-1g.cyr"
[ -f "$RV1" ] && sed -e 's/^syscall(60, f());/# &/' -e 's/^# syscall(60, g());/syscall(60, g());/' "$RV1" > "$RV1G"
NREPRO=5

# run_leg <leg> <compiler> <runner>
run_leg() {
    while IFS='|' read -r id mode want src; do
        NROWS=$((NROWS + 1))
        run_row "$1" "$2" "$3" "$id" "$mode" "$want" "$src"
    done < "$WORK/rows"
    run_repro "$1" "$2" "$3" "$RP" 22
    run_repro "$1" "$2" "$3" "$RV1" 6
    run_repro "$1" "$2" "$3" "$RV1G" 67
    run_repro "$1" "$2" "$3" "$RV2" r
    run_repro "$1" "$2" "$3" "$RN" 26
}

echo "host x86_64:"
run_leg host "$CC" ""

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
    echo "  SKIP: qemu-aarch64 not installed (the pi hardware leg still covers the target)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

# Derived floor: the row table (51 rows) and the repros on host + cx, even with qemu absent.
if [ "$NTAB" -lt 51 ]; then bad "the row table holds $NTAB rows (floor 51) — it did not load"; fi
if [ "$NROWS" -lt $(((NTAB + NREPRO) * 2)) ]; then bad "only $NROWS rows ran (floor $(((NTAB + NREPRO) * 2)))"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: closure_declared_names_not_captured ($NFAIL of $NROWS rows)"
    exit 1
fi
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: closure_declared_names_not_captured — $GATE_SKIPS leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: closure_declared_names_not_captured ($NROWS rows)"
