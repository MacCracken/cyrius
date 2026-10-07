#!/bin/sh
# pp_directive_blank_separators.sh — 6.6.20 (LEX-EXPR-03).
#
# A DIRECTIVE'S OPERANDS ARE SEPARATED BY A RUN OF BLANKS — SPACES AND TABS. TAB is ordinary
# whitespace in the language (`var<TAB>r<TAB>=<TAB>9;` compiles), and PP_SKIP_WS,
# PP_NAMEBOUND and _pp_a64_sym already took it; but the directive predicates (ISIFDEF,
# ISIFNDEF, ISDEFINE, ISIF, ISELIF, ISIFPLAT) wanted exactly one SPACE after the keyword,
# PP_HASH ended a name at a space only, and PP_DEFINE skipped exactly one byte before a
# value. Every shape below compiled with rc 0, an EMPTY stderr, and the WRONG ARM:
#
#   p1  `#ifdef CYRIUS_ARCH_X86<TAB>`      → the #else arm on x86
#   p2  `#ifdef FOO<TAB># trailing`        → the #else arm
#   p3  `#define FOO<TAB>1`                → FOO undefined
#   p4  `#ifndef CYRIUS_ARCH_X86<TAB>`     → the #ifndef arm on x86
#   p5  `#ifdef<TAB>NOPE`                  → a COMMENT: the guarded code compiled
#                                            unconditionally and its #endif vanished at depth 0
#   q6b `#ifplat x86<TAB>`                 → the #else arm on x86
#   q7  `#if FOO<TAB>== 3`                 → the #else arm
#   q8  `#define<TAB>FOO 1`                → not a directive: FOO undefined
#   q10 `#define FOO<TAB>` (trailing tab)  → FOO undefined
#   q5  `#if<TAB>FOO == 3`                 → a comment: BOTH arms compiled
#   q6  `#ifplat<TAB>x86`                  → a comment: BOTH arms compiled
#   s1  `#define FOO  1` (two spaces)      → FOO defined as 0 — spaces only, so "treat TAB
#                                            like space" alone would have left it
#   s2  `#if dbg == 1`                     → a comment: ISIF refused any condition starting
#                                            with a lower-case `d` (a "must not be #ifdef"
#                                            check that could never see #ifdef)
#   s3  `#define FOO<TAB>bar(1)`           → stored as a function-like macro `FOO<TAB>bar`
#   s4  `#ifdef  CYRIUS_ARCH_X86` (2 sp)   → the #else arm
#   s6  `#define<TAB>ADD(a, b) (a + b)`    → no macro at all (`undefined function 'ADD'`)
#
# ⭐ EVERY ROW IS SCORED AGAINST ITS SINGLE-SPACE TWIN, NOT A NUMBER: the twin is the same
# file with each blank run in the directive line collapsed to one space (s2: `dbg` renamed
# `Dbg`, the shape the old check let through), and the row requires the SAME EXIT and a
# BYTE-IDENTICAL binary. The twin's spelling is the one every compiler since v5 reads right.
#
# AND THE STRAYS ARE REPORTED (`_pp_stray` / `_pp_unclosed`). An `#else` / `#elif` /
# `#endif` / `#endplat` with no open block was "ignored silently rather than abort" — which
# is what let p5 and s2 pass unnoticed: their opener was a comment, so their `#endif` landed
# at depth 0 and vanished. The mirror — a block still open at the end of input — was silent
# too, and a false one dropped everything after it, the rest of an included file and all
# that followed. Rows e1-e8: each is refused, NAMING the directive and its own file:line
# (e7 and e8 are in an INCLUDED file, the PP_IFDEF_PASS path, whose attribution has to be
# put back on the opener's file). An ecosystem survey (19,635 cyrius files under ~/Repos)
# found no depth-0 stray and no block left open at end of file, so nothing real goes red.
#
# AND `#ifplat` / `#endplat` ARE DIRECTIVES IN AN INCLUDED FILE (rows f1-f3, e9, e10, g).
# PP_IFDEF_PASS — the pass that reads included files — had no arm for either, so both were
# comments there: both arms of an included `#ifplat aarch64` compiled on x86 (rc 0; a
# conflicting definition only drew a duplicate-symbol warning), and once a stray `#endif`
# became an error, an included `#ifplat x86` ... `#endif` — the guide's own spelling — was
# REFUSED as "#endif without a matching #if". Rows f1-f3 are scored against their
# `#ifdef CYRIUS_ARCH_*` / `#endif` twin (same exit, BYTE-IDENTICAL binary): f3 sits past the
# first MiB of the stream, where PP_IFDEF_PASS's S + _SRCB copy ends, so PP_IFPLAT_MATCH must
# read the uncapped buffer it is handed. An ecosystem survey found no included `#ifplat`.
#
# MUTATION LEDGER (2026-10-06, cycc 1,582,456 B; each applied to a scratch copy of src/ + lib/,
# a compiler built from it with the good cycc, the gate run against it via CYRIUS_CC):
#   N1 PP_SEP skips nothing (`return pos;`) → q7, q5, s1, s2 (their TWINS misread: the
#      twin-exit anchor is what catches these), s4, g
#   N2 PP_HASH's TAB terminator deleted → p1, p2, p3, p4, q7, q10, s3
#   N3 ISIF's separator back to `!= 32` → q5
#   N4 _pp_stray reports nothing → e1, e2, e3, e4, e7, e9
#   N5 _pp_unclosed reports nothing → e5, e6, e8, e10
#   N6 _pp_unclosed's marker restore skipped → e8, e10 (the error names <source>, the
#      file the stream had moved on to, instead of the included file)
#   N7 ISIF's lower-case-`d` refusal restored → s2
#   P1 PP_IFDEF_PASS's PP_IFPLAT_MATCH reads S + _SRCB (the 1 MiB copy) → f3
#   P2 PP_IFDEF_PASS's ISIFPLAT arm never taken → f1, f2, f3, e10, g
#   P3 PP_IFDEF_PASS's ISENDPLAT arm never taken → f1, e9, g
#   e696746d's compiler → 30 of 30 rows FAIL (f2, f3 and g on the duplicate-symbol warning
#   both compiled arms draw). 1553be2f's (the lane before the included-#ifplat arms) → f1, f2,
#   f3, e9, e10 and g FAIL; f2 / f3 there are the false "#else without a matching #if".
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYRIUS_CC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: pp_directive_blank_separators: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pp_directive_blank_separators: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true

pass=0; fail=0

# build $1 -> $1.bin; sets rc and got (the exit, or `-` when it did not build)
build_run() {
    rc=0
    ( cd "$D" && "$CC" < "$1.cyr" > "$1.bin" 2> "$1.err" ) || rc=$?
    got=-
    if [ "$rc" -eq 0 ] && [ -s "$D/$1.bin" ]; then
        chmod +x "$D/$1.bin"; got=0; ( "$D/$1.bin" ) >/dev/null 2>&1 || got=$?
    fi
}

# A separator row: $1 name, $2 the source (printf format, `\t` = TAB), $3 the sed program
# that turns it into its single-space twin, $4 the exit the TWIN must give (the arm its
# single-space directives select — read off the source by hand), $5 description.
# ⚠ The twin's own exit is checked too: a compiler that misreads EVERY directive reads the
# pair alike, and mutation N1 (no blank-run skip at all) broke s1's twin exactly that way —
# a pair-only oracle scored it green.
sep_row() {
    printf "$2" > "$D/$1.cyr"
    sed "$3" "$D/$1.cyr" > "$D/$1t.cyr"
    if cmp -s "$D/$1.cyr" "$D/$1t.cyr"; then
        printf '  FAIL: row %s — the twin is the same file (sed %s did nothing); the row would be vacuous\n' "$1" "$3"
        fail=$((fail+1)); return 0
    fi
    build_run "$1t"; twin=$got
    if [ "$twin" != "$4" ]; then
        printf '  FAIL: row %s TWIN exits %s, want %s — even the single-space spelling is misread: %s\n' "$1" "$twin" "$4" \
            "$(head -1 "$D/$1t.err" | cut -c1-80)"
        fail=$((fail+1)); return 0
    fi
    build_run "$1"
    if [ "$got" = "$twin" ] && cmp -s "$D/$1.bin" "$D/$1t.bin"; then
        printf '  ok: row %s — %s (exit %s, byte-identical to the single-space twin)\n' "$1" "$5" "$got"
        pass=$((pass+1))
    else
        printf '  FAIL: row %s — %s: exit %s, single-space twin %s, rc %s, stderr: %s\n' "$1" "$5" "$got" "$twin" "$rc" \
            "$(head -1 "$D/$1.err" | cut -c1-80)"
        fail=$((fail+1))
    fi
}
T1='s/\t/ /g'                       # every TAB -> one space
T2='s/[ \t][ \t]*/ /g'              # every blank run -> one space

sep_row p1 '#ifdef CYRIUS_ARCH_X86\t\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#ifdef X<TAB>` takes the #ifdef arm'
sep_row p2 '#define FOO 1\n#ifdef FOO\t# trailing\nvar r = 11;\n#else\nvar r = 12;\n#endif\nsyscall(60, r);\n' "$T1" 11 '`#ifdef FOO<TAB># note` sees FOO'
sep_row p3 '#define FOO\t1\n#ifdef FOO\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#define FOO<TAB>1` defines FOO'
sep_row p4 '#ifndef CYRIUS_ARCH_X86\t\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 2 '`#ifndef X<TAB>` takes the #else arm'
sep_row p5 'var r = 5;\n#ifdef\tNOPE_NOT_DEFINED\nr = 1;\n#endif\nsyscall(60, r);\n' "$T1" 5 '`#ifdef<TAB>NOPE` is a directive, its body skipped'
sep_row q6b '#ifplat x86\t\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#ifplat x86<TAB>` matches'
sep_row q7 '#define FOO 3\n#if FOO\t== 3\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#if FOO<TAB>== 3` compares'
sep_row q8 '#define\tFOO 1\n#ifdef FOO\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#define<TAB>FOO 1` is a directive'
sep_row q10 '#define FOO\t\n#ifdef FOO\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#define FOO<TAB>` (trailing) defines FOO'
sep_row q5 '#define FOO 3\nvar r = 7;\n#if\tFOO == 3\nr = 1;\n#else\nr = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#if<TAB>FOO == 3` is a directive (one arm)'
sep_row q6 'var r = 7;\n#ifplat\tx86\nr = 1;\n#else\nr = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#ifplat<TAB>x86` is a directive (one arm)'
sep_row s1 '#define FOO  1\n#if FOO == 1\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T2" 1 '`#define FOO  1` (two spaces) is 1, not 0'
sep_row s2 'var r = 7;\n#define dbg 1\n#if dbg == 1\nr = 1;\n#else\nr = 2;\n#endif\nsyscall(60, r);\n' 's/dbg/Dbg/g' 1 '`#if dbg == 1` is a directive (ISIF`s lower-case-d refusal is gone)'
sep_row s3 '#define FOO\tbar(1)\n#ifdef FOO\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T1" 1 '`#define FOO<TAB>bar(1)` defines FOO, not a macro `FOO<TAB>bar`'
sep_row s4 '#ifdef  CYRIUS_ARCH_X86\nvar r = 1;\n#else\nvar r = 2;\n#endif\nsyscall(60, r);\n' "$T2" 1 '`#ifdef  X` (two spaces) sees X'
sep_row s6 '#define\tADD(a, b) (a + b)\nvar r = ADD(3, 4);\nsyscall(60, r);\n' "$T1" 7 '`#define<TAB>ADD(a, b)` is a function-like macro'

# A stray / unclosed row: $1 name, $2 the source, $3 the diagnostic it must print
# (a grep -F fixed string, file:line:col included).
err_row() {
    printf "$2" > "$D/$1.cyr"
    build_run "$1"
    if [ "$rc" -ne 0 ] && grep -qF "$3" "$D/$1.err"; then
        printf '  ok: row %s — refused: %s\n' "$1" "$3"
        pass=$((pass+1))
    else
        printf '  FAIL: row %s — rc %s exit %s, want a refusal reading %s; stderr: %s\n' "$1" "$rc" "$got" "$3" \
            "$(head -1 "$D/$1.err" | cut -c1-90)"
        fail=$((fail+1))
    fi
}
err_row e1 'var r = 5;\n#endif\nsyscall(60, r);\n' 'error:<source>:2:1: #endif without a matching #if'
err_row e2 'var r = 5;\n#else\nr = 7;\nsyscall(60, r);\n' 'error:<source>:2:1: #else without a matching #if'
err_row e3 'var r = 5;\n#elif FOO == 1\nsyscall(60, r);\n' 'error:<source>:2:1: #elif without a matching #if'
err_row e4 'var r = 5;\n\n#endplat\nsyscall(60, r);\n' 'error:<source>:3:1: #endplat without a matching #if'
err_row e5 'var r = 5;\n#ifdef NOPE\nr = 1;\nsyscall(60, r);\n' 'error:<source>:2:1: this #if / #ifdef / #ifndef / #ifplat has no matching #endif'
err_row e6 'var r = 5;\n#ifdef CYRIUS_ARCH_X86\n#ifdef NOPE\n#endif\nr = 1;\nsyscall(60, r);\n' 'error:<source>:2:1: this #if / #ifdef / #ifndef / #ifplat has no matching #endif'
printf '# inc\nvar q = 1;\n#endif\n' > "$D/i7.cyr"
err_row e7 'include "i7.cyr"\nsyscall(60, q);\n' 'error:i7.cyr:3:1: #endif without a matching #if'
printf '# inc\nvar q = 1;\n#ifdef NOPE\nvar z = 2;\n' > "$D/i8.cyr"
printf 'var w8 = 1;\n' > "$D/j8.cyr"
err_row e8 'include "i8.cyr"\ninclude "j8.cyr"\nvar w = 3;\nsyscall(60, q);\n' 'error:i8.cyr:3:1: this #if / #ifdef / #ifndef / #ifplat has no matching #endif'

# An included-`#ifplat` row: $1 name, $2 the INCLUDED file (printf format), $3 the exit it must
# give, $4 description. Its twin spells every `#ifplat x86` / `#ifplat aarch64` / `#endplat` as
# `#ifdef CYRIUS_ARCH_X86` / `#ifdef CYRIUS_ARCH_AARCH64` / `#endif`, which PP_IFDEF_PASS has
# always honoured; the two live under the same file name in sibling directories, so the pair
# must match byte for byte. $5, when set, is a file both include first (f3's padding).
inc_row() {
    mkdir -p "$D/$1/a" "$D/$1/b"
    printf "$2" > "$D/$1/a/inc.cyr"
    sed 's/#ifplat x86/#ifdef CYRIUS_ARCH_X86/; s/#ifplat aarch64/#ifdef CYRIUS_ARCH_AARCH64/; s/#endplat/#endif/' \
        "$D/$1/a/inc.cyr" > "$D/$1/b/inc.cyr"
    for v in a b; do
        if [ -n "${5:-}" ]; then cp "$D/$5" "$D/$1/$v/pad.cyr"; printf 'include "pad.cyr"\n' > "$D/$1/$v/m.cyr"
        else : > "$D/$1/$v/m.cyr"; fi
        printf 'include "inc.cyr"\nsyscall(60, q);\n' >> "$D/$1/$v/m.cyr"
    done
    rc=0; ( cd "$D/$1/b" && "$CC" < m.cyr > m.bin 2> m.err ) || rc=$?
    twin=-; if [ "$rc" -eq 0 ] && [ -s "$D/$1/b/m.bin" ]; then chmod +x "$D/$1/b/m.bin"; twin=0; "$D/$1/b/m.bin" >/dev/null 2>&1 || twin=$?; fi
    if [ "$twin" != "$3" ]; then
        printf '  FAIL: row %s TWIN exits %s, want %s: %s\n' "$1" "$twin" "$3" "$(head -1 "$D/$1/b/m.err" | cut -c1-80)"
        fail=$((fail+1)); return 0
    fi
    rc=0; ( cd "$D/$1/a" && "$CC" < m.cyr > m.bin 2> m.err ) || rc=$?
    got=-; if [ "$rc" -eq 0 ] && [ -s "$D/$1/a/m.bin" ]; then chmod +x "$D/$1/a/m.bin"; got=0; "$D/$1/a/m.bin" >/dev/null 2>&1 || got=$?; fi
    if [ "$got" = "$3" ] && [ ! -s "$D/$1/a/m.err" ] && cmp -s "$D/$1/a/m.bin" "$D/$1/b/m.bin"; then
        printf '  ok: row %s — %s (exit %s, byte-identical to the #ifdef CYRIUS_ARCH_* twin)\n' "$1" "$4" "$got"
        pass=$((pass+1))
    else
        printf '  FAIL: row %s — %s: rc %s exit %s (want %s, silent, byte-identical to the twin), stderr: %s\n' "$1" "$4" "$rc" "$got" "$3" \
            "$(head -1 "$D/$1/a/m.err" | cut -c1-90)"
        fail=$((fail+1))
    fi
}
inc_row f1 'var q = 3;\n#ifplat aarch64\nq = 13;\n#endplat\n' 3 'an included `#ifplat aarch64` arm is skipped on x86'
inc_row f2 '#ifplat x86\nvar q = 1;\n#else\nvar q = 2;\n#endif\n' 1 'an included `#ifplat x86` ... `#else` ... `#endif` builds and takes the x86 arm'
# f3: the same block past the first MiB of the stream (1,320,000 B of comment lines in front).
awk 'BEGIN { for (i = 0; i < 20000; i++) printf "# padding line %05d ............................................\n", i }' > "$D/pad.cyr"
inc_row f3 '#ifplat x86\nvar q = 1;\n#else\nvar q = 2;\n#endif\n' 1 'an included `#ifplat x86` past the first MiB reads its own operand' pad.cyr
printf '# inc\nvar q = 1;\n#endplat\n' > "$D/i9.cyr"
err_row e9 'include "i9.cyr"\nsyscall(60, q);\n' 'error:i9.cyr:3:1: #endplat without a matching #if'
printf '# inc\nvar q = 1;\n#ifplat aarch64\nvar z = 2;\n' > "$D/i10.cyr"
err_row e10 'include "i10.cyr"\nsyscall(60, q);\n' 'error:i10.cyr:3:1: this #if / #ifdef / #ifndef / #ifplat has no matching #endif'

# Over-correction guard: balanced nesting, every directive kind, both passes (main + included).
# g1's `#ifplat aarch64` arm redefines `a` AFTER the x86 one, so an included `#ifplat` that is
# not evaluated shows up here too (exit 19 and a duplicate-symbol warning).
printf '#ifdef NOPE\nvar a = 1;\n#elif FOO == 2\nvar a = 2;\n#else\n#ifplat x86\nvar a = 3;\n#endplat\n#ifplat aarch64\nvar a = 9;\n#endplat\n#ifndef CYRIUS_ARCH_X86\nvar a = 4;\n#endif\n#endif\n' > "$D/g1.cyr"
printf '#define FOO 1\ninclude "g1.cyr"\n#if FOO == 1\nvar b = 10;\n#else\nvar b = 20;\n#endif\nsyscall(60, a + b);\n' > "$D/g.cyr"
build_run g
if [ "$rc" -eq 0 ] && [ "$got" = 13 ] && [ ! -s "$D/g.err" ]; then
    printf '  ok: row g — balanced nesting of every directive kind, main source and included, compiles silently (exit 13)\n'
    pass=$((pass+1))
else
    printf '  FAIL: row g — balanced nesting: rc %s exit %s (want 0 / 13), stderr: %s\n' "$rc" "$got" "$(head -1 "$D/g.err" | cut -c1-90)"
    fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: pp-directive-blank-separators — %s of %s rows failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: pp-directive-blank-separators — %s/%s rows green (16 separator shapes vs their single-space twins, 3 included #ifplat blocks vs their #ifdef twins, 10 stray/unclosed refusals, 1 balanced guard)\n' "$pass" "$pass"
