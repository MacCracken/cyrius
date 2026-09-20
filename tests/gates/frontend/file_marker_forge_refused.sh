#!/bin/sh
# file_marker_forge_refused.sh — v6.6.6 bite 5b (CVE-44).
#
# `private` IS SUPPOSED TO BE A CHECKABLE GUARANTEE. It is enforced through the
# file map: the preprocessor mints `#@file "NAME" BASE` markers, FM_BUILD turns
# them into spans, and a reference to a private symbol from outside its span is
# refused. FM_BUILD scans the FINAL buffer for `#@file` at ANY offset — no byte-0
# rule and no beginning-of-line rule, unlike `#@incdir` — so any source bytes that
# reach the preprocessor's output can FORGE a span and claim to be another file.
#
# v6.5.21 closed that for the main source by neutralising inside PP_PASS's copy
# loop. A guard shaped like ONE loop is only as wide as that loop, and there are
# FOUR routes from source to `out`. Three were still open at 6.6.5, each measured
# here on 2420b1f8's compiler as a clean build and `exit 42` where the honest
# program is refused:
#
#   1. an INCLUDED file — READFILE writes it STRAIGHT into `out`, in both passes
#   2. a `#define` macro BODY — the directive line is consumed by the handler and
#      the stored body is written out later by PP_EXPAND, in a pass whose comment
#      claimed a neutralisation it never had
#   3. a `#derive` line's TAIL — PP_COPY_TAIL copies it verbatim into `out`
#
# Fixed by neutralising at the ENTRY POINTS instead: PP_NEUT_PASS rewrites the raw
# source once before any pass reads it, and each include's READFILE neutralises the
# bytes it just read. PP_NEUT_FMARK overwrites the `@` with a space (length
# preserved, nothing shifts) and skips string literals via PP_LEXST.
#
# ⭐ WHY THE ORACLE IS A PAIR, NOT A FAILURE. "The program does not compile" is
# worthless on its own — it is what a compiler that rejects everything does. Every
# forge axis is scored against a TWIN that must BUILD AND RUN: the same program
# with the private marker removed from the target file. So each axis asserts both
# "the forge is refused" and "nothing else about this program was broken".
#
# Axes:
#   1  an INCLUDED file forging `#@file` cannot reach a private fn (the reported
#      shape) — and its twin without `private` still exits 42
#   2  anti-vacuous: the honest program (no forged line) is refused the same way,
#      so axis 1 is measuring the visibility check and not a parse error
#   3  a `#define` macro BODY cannot forge the marker
#   4  a `#derive` line's TAIL cannot forge the marker
#   5  a mid-line trailing comment in the MAIN source cannot forge it (v6.5.21's
#      own shape, which must stay closed)
#   6  a string literal holding `#@file` keeps its bytes — the neutraliser must
#      not rewrite program DATA
#   7  REAL markers still work: a diagnostic inside an included file names that
#      file and its own line number (the fix must not be "stop emitting markers")
#   8  census: every READFILE-into-`out` include site is followed by a
#      PP_NEUT_FMARK call, derived from src/frontend/lex_pp.cyr
#   9  THE CONSUMER HALF (bite 5g): a string literal cannot mint a span. The
#      neutraliser skips string literals on purpose, so `var q = "#@file ";`
#      used to mint one whose "filename" ran from the closing quote to the next
#      `"` — it appeared as the file name in a diagnostic. FM_BUILD now requires
#      the marker at a LINE START, the way `#@incdir` requires byte 0.
#   10 census: FM_BUILD's scan is gated on FM_ATBOL
#
# MUTATION LEDGER (2026-09-19, cycc 1,310,856 B, measured). Each mutation is
# applied to the working tree, a compiler built from it with the good cycc, and
# the gate run against that compiler (CYRIUS_CC); the tree is restored after:
#   M1 the two `PP_NEUT_FMARK(out + op, nr);` include calls deleted
#      → 2 FAIL / 10 ok: axis 1 (the forged include COMPILED) and axis 8 (census:
#        2 include READFILE sites, 0 guards)
#   M2 the `PP_NEUT_PASS(S);` call removed from PREPROCESS
#      → 4 FAIL / 8 ok: axes 3, 4, 5 (all three forged programs COMPILED) and
#        axis 8. Axis 1 stays green — that is the point of splitting the two
#        entry points into separate axes.
#   M3 PP_NEUT_FMARK's `PP_LEXST_INSTR(st) == 0` guard replaced by `1 == 1`
#      (neutralise everywhere, strings included) → 1 FAIL / 11 ok: axis 6, the
#      program whose DATA holds `#@file`
#   M4 PP_NEUT_FMARK's body short-circuited with `return 0;`
#      → 4 FAIL / 8 ok: axes 1, 3, 4, 5 — every forge route reopens at once
#   M5 FM_ATBOL replaced by `return 1;` (the pre-6.6.6 any-offset scan)
#      → 1 FAIL: axis 9, whose diagnostic comes back naming `;\nvar w = `
#   M6 FM_ATBOL replaced by `return 0;` (no marker is ever accepted)
#      → 7 FAIL: 1, 2, 3, 4, 5, 7, 9 — WIDER than expected and worth recording:
#        with no file map at all `private` stops being enforced anywhere, so axis
#        2 (the anti-vacuous honest program) reports rc=0. That is what stops
#        axis 9 passing vacuously — a file map that records nothing also records
#        no forgery.
#   real tree → 14/14 green
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYRIUS_CC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ulimit -c 0 2>/dev/null || true

# The file holding the private symbol, and the same file without `private`.
printf 'private\nfn SECRET_ADD(a, b): i64 { return a + b; }\n' > "$D/secret.cyr"
printf 'fn SECRET_ADD(a, b): i64 { return a + b; }\n'          > "$D/open.cyr"

# Compile $D/$1.cyr with secret.cyr as the target ($2 = secret|open). The source is
# written with `TARGET` standing for the included file so the two runs are the same
# bytes apart from that one name.
build_with() {
    sed "s/TARGET/$2/g" "$D/$1.src" > "$D/$1.cyr"
    rc=0
    ( cd "$D" && "$CC" < "$1.cyr" > "$1.bin" 2> "$1.err" ) || rc=$?
    return 0
}

# A forge axis: refused against secret.cyr, but builds and exits 42 against open.cyr.
forge_axis() {
    ax=$1; desc=$2
    build_with "$ax" secret
    if [ "$rc" -eq 0 ]; then
        printf '  FAIL: axis %s — %s: the forged program COMPILED (private defeated)\n' "$ax" "$desc"
        fail=$((fail+1))
    elif ! grep -q "is private to its file" "$D/$ax.err"; then
        printf '  FAIL: axis %s — %s: refused, but not by the visibility check: %s\n' \
            "$ax" "$desc" "$(head -1 "$D/$ax.err" | cut -c1-80)"
        fail=$((fail+1))
    else
        printf '  ok: axis %s — %s (refused: %s)\n' \
            "$ax" "$desc" "$(grep -m1 'is private' "$D/$ax.err" | cut -c1-60)"
        pass=$((pass+1))
    fi
    rm -f "$D/$ax.bin"
    # The twin: identical program, target file not private. Must build and run.
    build_with "$ax" open
    if [ "$rc" -ne 0 ] || [ ! -s "$D/$ax.bin" ]; then
        printf '  FAIL: axis %s TWIN — %s: the NON-private twin did not build: %s\n' \
            "$ax" "$desc" "$(head -1 "$D/$ax.err" | cut -c1-80)"
        fail=$((fail+1)); return 0
    fi
    chmod +x "$D/$ax.bin"
    got=0; ( "$D/$ax.bin" ) || got=$?
    if [ "$got" = 42 ]; then
        printf '  ok: axis %s TWIN — the same program against a non-private file exits 42\n' "$ax"
        pass=$((pass+1))
    else
        printf '  FAIL: axis %s TWIN — exit=%s, want 42\n' "$ax" "$got"
        fail=$((fail+1))
    fi
    rm -f "$D/$ax.bin"
}

# ── axis 1 — the reported shape: an INCLUDED file forges the marker.
#    The attacking include and the entry file are both generated per target, so the
#    forged run and its twin differ only in which file is `private`.
axis1() {
    for tgt in secret open; do
        printf '#@file "%s.cyr" 1\nvar R = SECRET_ADD(20, 22);\nsyscall(60, R);\n' "$tgt" > "$D/attack.cyr"
        printf 'include "%s.cyr"\ninclude "attack.cyr"\nsyscall(60, 7);\n' "$tgt" > "$D/1.cyr"
        rc=0
        ( cd "$D" && "$CC" < "1.cyr" > "1.bin" 2> "1.err" ) || rc=$?
        if [ "$tgt" = secret ]; then
            if [ "$rc" -eq 0 ]; then
                printf '  FAIL: axis 1 — an INCLUDED file forged #@file and reached a private fn\n'
                fail=$((fail+1))
            elif ! grep -q "is private to its file" "$D/1.err"; then
                printf '  FAIL: axis 1 — refused, but not by the visibility check: %s\n' \
                    "$(head -1 "$D/1.err" | cut -c1-80)"
                fail=$((fail+1))
            else
                printf '  ok: axis 1 — an INCLUDED file cannot forge #@file (%s)\n' \
                    "$(grep -m1 'is private' "$D/1.err" | cut -c1-58)"
                pass=$((pass+1))
            fi
        else
            if [ "$rc" -ne 0 ] || [ ! -s "$D/1.bin" ]; then
                printf '  FAIL: axis 1 TWIN — the non-private twin did not build: %s\n' \
                    "$(head -1 "$D/1.err" | cut -c1-80)"
                fail=$((fail+1))
            else
                chmod +x "$D/1.bin"; got=0; ( "$D/1.bin" ) || got=$?
                if [ "$got" = 42 ]; then
                    printf '  ok: axis 1 TWIN — the same include against a non-private file exits 42\n'
                    pass=$((pass+1))
                else
                    printf '  FAIL: axis 1 TWIN — exit=%s, want 42\n' "$got"
                    fail=$((fail+1))
                fi
            fi
        fi
        rm -f "$D/1.bin"
    done
}
axis1

# ── axis 2 — anti-vacuous: the HONEST program is refused the same way, so axis 1
#    is measuring the visibility check rather than a parse error.
printf 'var R = SECRET_ADD(20, 22);\nsyscall(60, R);\n' > "$D/honest.cyr"
printf 'include "secret.cyr"\ninclude "honest.cyr"\nsyscall(60, 7);\n' > "$D/2.cyr"
rc=0; ( cd "$D" && "$CC" < "2.cyr" > "2.bin" 2> "2.err" ) || rc=$?
if [ "$rc" -ne 0 ] && grep -q "is private to its file" "$D/2.err"; then
    printf '  ok: axis 2 — the honest cross-file call is refused (the check is live)\n'
    pass=$((pass+1))
else
    printf '  FAIL: axis 2 — the private visibility check is NOT live: rc=%s %s\n' \
        "$rc" "$(head -1 "$D/2.err" | cut -c1-70)"
    fail=$((fail+1))
fi
rm -f "$D/2.bin"

# ── axis 3 — a `#define` macro BODY forges the marker (PP_EXPAND's route).
printf '#define FORGE(x) #@file "TARGET.cyr" 1\ninclude "TARGET.cyr"\nFORGE(0)\nvar R = SECRET_ADD(20, 22);\nsyscall(60, R);\n' > "$D/3.src"
forge_axis 3 'a #define macro body cannot forge #@file'

# ── axis 4 — a `#derive` line's TAIL forges the marker (PP_COPY_TAIL's route).
printf 'include "TARGET.cyr"\n#derive(Serialize)\nstruct P { a: i64 } #@file "TARGET.cyr" 1\nvar R = SECRET_ADD(20, 22);\nsyscall(60, R);\n' > "$D/4.src"
forge_axis 4 'a #derive line tail cannot forge #@file'

# ── axis 5 — a mid-line trailing comment in the MAIN source (v6.5.21's own shape).
printf 'include "TARGET.cyr"\nvar Z = 0; #@file "TARGET.cyr" 1\nvar R = SECRET_ADD(20, 22);\nsyscall(60, R);\n' > "$D/5.src"
forge_axis 5 'a mid-line comment in the main source cannot forge #@file'

# ── axis 6 — program DATA holding `#@file` must survive byte for byte. Expected
#    comes from a payload file the .cyr is GENERATED from, never re-read from it.
printf 'm\n#@file z\nn' > "$D/want6"
n6=$(wc -c < "$D/want6" | tr -d ' ')
{ printf 'var s = "'; cat "$D/want6"; printf '";\nsyscall(1, 1, s, %s);\nsyscall(60, 0);\n' "$n6"; } > "$D/6.cyr"
rc=0; ( cd "$D" && "$CC" < "6.cyr" > "6.bin" 2> "6.err" ) || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/6.bin" ]; then
    printf '  FAIL: axis 6 — the string program did not build: %s\n' \
        "$(head -1 "$D/6.err" | cut -c1-80)"
    fail=$((fail+1))
else
    chmod +x "$D/6.bin"; ( "$D/6.bin" > "$D/6.out" 2>/dev/null ) || true
    if cmp -s "$D/6.out" "$D/want6"; then
        printf '  ok: axis 6 — a string literal holding #@file keeps its %s bytes\n' "$n6"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 6 — the neutraliser rewrote program DATA\n'
        printf '        want: %s\n' "$(od -c < "$D/want6" | head -1)"
        printf '        got : %s\n' "$(od -c < "$D/6.out" | head -1)"
        fail=$((fail+1))
    fi
fi
rm -f "$D/6.bin"

# ── axis 7 — REAL markers still work. A diagnostic raised inside an included file
#    must name THAT file and its own line, or the fix has simply stopped the file
#    map working, which would make every forge axis pass vacuously.
printf 'fn inc_ok(): i64 { return 1; }\nfn inc_ok2(): i64 { return 2; }\nvar BAD = NOT_DEFINED_ANYWHERE;\n' > "$D/inc7.cyr"
printf 'include "inc7.cyr"\nsyscall(60, 0);\n' > "$D/7.cyr"
rc=0; ( cd "$D" && "$CC" < "7.cyr" > "7.bin" 2> "7.err" ) || rc=$?
if grep -q '^error:inc7.cyr:3:' "$D/7.err"; then
    printf '  ok: axis 7 — a real marker still attributes: %s\n' \
        "$(grep -m1 '^error:inc7' "$D/7.err" | cut -c1-58)"
    pass=$((pass+1))
else
    printf '  FAIL: axis 7 — included-file attribution lost: %s\n' \
        "$(head -1 "$D/7.err" | cut -c1-80)"
    fail=$((fail+1))
fi
rm -f "$D/7.bin"

# ── axis 8 — census, derived from the source: every include READFILE that writes
#    STRAIGHT into `out` must be followed by a PP_NEUT_FMARK call, and the raw
#    source must get one too. Counted a different way from the code itself: the
#    include sites are found by their READFILE shape, the guards by their call.
nreads=$(grep -c 'READFILE(fname, out + op' src/frontend/lex_pp.cyr || true)
nguards=$(grep -c 'PP_NEUT_FMARK(out + op, nr);' src/frontend/lex_pp.cyr || true)
npass=$(grep -c 'PP_NEUT_PASS(S);' src/frontend/lex_pp.cyr || true)
if [ "$nreads" = "$nguards" ] && [ "$nreads" -ge 2 ] && [ "$npass" -ge 1 ]; then
    printf '  ok: axis 8 — %s include READFILE sites, %s neutralised, raw-source pass wired\n' \
        "$nreads" "$nguards"
    pass=$((pass+1))
else
    printf '  FAIL: axis 8 — census: %s include READFILE sites but %s guards, %s raw-source pass calls\n' \
        "$nreads" "$nguards" "$npass"
    fail=$((fail+1))
fi

# ── axis 9 — THE CONSUMER HALF (v6.6.6 bite 5g). The producer-side neutraliser
#    deliberately skips STRING LITERALS, so program DATA could still mint a span:
#    `var q = "#@file ";` ends its literal with the very quote FM_BUILD's scan
#    wants, and the "filename" then ran from there to the next `"` in the file. It
#    never defeated `private` (the byte after a closing quote is punctuation in
#    valid cyrius, so the name is not attacker-chosen), but the forged name DID
#    appear as the filename in a diagnostic. FM_BUILD now requires the marker at a
#    line start, as `#@incdir` requires byte 0.
#    Expected is derived a different way: the line number comes from grep -n over
#    the generated source, not from the compiler.
printf 'include "secret.cyr"\nvar q = "#@file ";\nvar w = "secret.cyr";\nvar R = SECRET_ADD(20, 22);\nsyscall(60, R);\n' > "$D/9.cyr"
want9=$(grep -n 'SECRET_ADD(20, 22)' "$D/9.cyr" | cut -d: -f1)
rc=0; ( cd "$D" && "$CC" < "9.cyr" > "9.bin" 2> "9.err" ) || rc=$?
if [ "$rc" -eq 0 ]; then
    printf '  FAIL: axis 9 — a string literal minted a span and the program COMPILED\n'
    fail=$((fail+1))
elif grep -q "^error:<source>:$want9:" "$D/9.err"; then
    printf '  ok: axis 9 — a string literal cannot mint a file-map span (diagnostic names <source>:%s)\n' "$want9"
    pass=$((pass+1))
else
    printf '  FAIL: axis 9 — the diagnostic carries a FORGED file name: %s\n' \
        "$(head -2 "$D/9.err" | tr '\n' ' ' | cut -c1-90)"
    fail=$((fail+1))
fi
rm -f "$D/9.bin"

# ── axis 10 — census for the consumer half: FM_BUILD's marker scan must be gated
#    on FM_ATBOL. Counted from the source, a different way from axis 9's behaviour.
nbol=$(grep -c 'FM_ATBOL(buf, pos) == 1' src/frontend/lex.cyr || true)
nfmb=$(grep -c 'fn FM_ATBOL(buf, pos)' src/frontend/lex.cyr || true)
if [ "$nbol" -ge 1 ] && [ "$nfmb" = 1 ]; then
    printf '  ok: axis 10 — FM_BUILD gates its marker scan on FM_ATBOL (%s call site)\n' "$nbol"
    pass=$((pass+1))
else
    printf '  FAIL: axis 10 — FM_ATBOL census: %s definitions, %s call sites in FM_BUILD\n' \
        "$nfmb" "$nbol"
    fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: file-marker-forge-refused — %s of %s axes failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: file-marker-forge-refused — %s/%s axes green\n' "$pass" "$pass"
