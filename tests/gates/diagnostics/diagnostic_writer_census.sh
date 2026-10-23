#!/bin/sh
# diagnostic_writer_census.sh — every diagnostic byte the parser and the emitters write goes through `_ew`, every exit through `_die` (6.7.17).
#
# WHY. A trait default no impl inherits and a generic base pass 2 steps (a stub, or a bounded generic i64 does not
# satisfy) are never parsed by the build; 6.7.17 reads each once for its syntax after the image is built
# (`_unp_run`, src/frontend/parse/fn/def.cyr), and that read must say NOTHING but a syntax error or an undefined
# name: every other refusal, note and warning it meets is about an instance that does not exist. The parser is the
# emitter, so the only mute is the one writer every diagnostic byte goes through — `_ew` (src/common/util.cyr), which
# writes nothing while `_ew_mute` is set unless `_ew_say` is. A raw `syscall(SYS_WRITE, 2, ..)` in these files would
# print through the mute: a valid program's never-instantiated generic body could print a refusal about T = i64.
#
# THE FILES: everything the parse reaches — every .cyr under src/frontend/parse/ and src/frontend/lex/, folders
# included (6.7.18: parse/fn/; the file map's writers a diagnostic's head
# calls live in the preprocessor), src/common/util.cyr, src/common/ir.cyr, and src/backend/<target>/{emit,jump,float}.cyr
# and src/backend/common/*.cyr (not js/, the TypeScript front end's). (FIXUP / the image writers and the drivers run
# outside a parse.) The one raw write left is `_ew`'s.
# ANTI-VACUOUS: the file list and the `_ew(` call count carry floors, so a glob or a regex that matches nothing is RED.
# MUTATION (2026-10-22): one `_ew(` put back as `syscall(SYS_WRITE, 2, ` in parse/fn.cyr (since 6.7.18 parse/fn/) -> RED.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
fail=0
# 6.7.18: the frontend is read RECURSIVELY — a top-level `parse/*.cyr` glob stopped seeing a file once parse/fn.cyr
# was split into parse/fn/, and the floor below (a count, not a list) could not tell.
FILES=$( { find src/frontend/parse src/frontend/lex -name '*.cyr'; ls src/common/util.cyr src/common/ir.cyr \
    src/backend/*/emit.cyr src/backend/*/jump.cyr src/backend/*/float.cyr src/backend/common/*.cyr; } 2> /dev/null \
    | grep -v '^src/backend/js/' | LC_ALL=C sort || true)
nf=$(printf '%s\n' "$FILES" | grep -c '\.cyr$' || true)
[ "$nf" -ge 21 ] || { echo "  FAIL: the census reads $nf files (floor 21)"; fail=$((fail+1)); }
# Raw stderr writes: `syscall(SYS_WRITE, 2` / `syscall(1, 2`, comments excluded, and the text of a program the
# preprocessor writes (a string literal: bounds mode's checker, `_bnd_ln`), which is the user program's, not ours.
raw=$(grep -nE 'syscall\((SYS_WRITE|1), *2' $FILES | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -vE '"[^"]*syscall\((SYS_WRITE|1), *2' || true)
nraw=$(printf '%s\n' "$raw" | grep -c . || true)
own=$(printf '%s\n' "$raw" | grep -c '^src/common/util.cyr:.*return syscall(SYS_WRITE, 2, b, n);' || true)
if [ "$nraw" -ne 1 ] || [ "$own" -ne 1 ]; then
    echo "  FAIL: raw stderr writes outside \`_ew\` ($nraw found, want only _ew's own):"
    printf '%s\n' "$raw" | grep -v 'return syscall(SYS_WRITE, 2, b, n);' | sed 's/^/        /' | head -20
    fail=$((fail+1))
else
    echo "  ok: no raw stderr write in the $nf files but \`_ew\`'s own"
fi
ncalls=$(cat $FILES | grep -o '[^A-Za-z0-9_]_ew(' | wc -l)
[ "$ncalls" -ge 600 ] || { echo "  FAIL: only $ncalls \`_ew(\` calls (floor 600)"; fail=$((fail+1)); }
grep -q '^fn _ew(b, n): i64 {' src/common/util.cyr || { echo "  FAIL: \`_ew\` is not defined in util.cyr"; fail=$((fail+1)); }
# ⛔ 6.7.17 — AND EVERY EXIT IN THESE FILES GOES THROUGH `_die` (util.cyr). The parse HOLDS its diagnostics to print them
# in source order (zone-replay, `_eb_end`), so a raw `syscall(SYS_EXIT, ..)` reached mid-parse — an error's own exit, a
# cap's refusal, an internal error — would end the process with them unwritten. Raw exits: `syscall(SYS_EXIT|60|93, `
# and agnos's two-argument `syscall(0, x)`, comments and string literals excluded. The one left is `_die`'s own.
# MUTATION (2026-10-22): one `_die(1)` in parse/fn/def.cyr put back as `syscall(SYS_EXIT, 1)` -> RED.
rawx=$(grep -nE 'syscall\((SYS_EXIT|60|93), |syscall\(0, [^,()]*\)' $FILES | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -vE '"[^"]*syscall\(' || true)
nrawx=$(printf '%s\n' "$rawx" | grep -c . || true)
ownx=$(printf '%s\n' "$rawx" | grep -c '^src/common/util.cyr:.*    syscall(SYS_EXIT, code);' || true)
if [ "$nrawx" -ne 1 ] || [ "$ownx" -ne 1 ]; then
    echo "  FAIL: raw exits outside \`_die\` ($nrawx found, want only _die's own):"
    printf '%s\n' "$rawx" | grep -v '    syscall(SYS_EXIT, code);' | sed 's/^/        /' | head -20
    fail=$((fail+1))
else
    echo "  ok: no raw exit in the $nf files but \`_die\`'s own"
fi
ndie=$(cat $FILES | grep -o '[^A-Za-z0-9_]_die(' | wc -l)
[ "$ndie" -ge 90 ] || { echo "  FAIL: only $ndie \`_die(\` calls (floor 90)"; fail=$((fail+1)); }
grep -q '^fn _die(code): i64 {' src/common/util.cyr || { echo "  FAIL: \`_die\` is not defined in util.cyr"; fail=$((fail+1)); }
if [ "$fail" -ne 0 ]; then echo "FAIL: diagnostic_writer_census — $fail"; exit 1; fi
echo "PASS: diagnostic_writer_census — $ncalls diagnostic writes in $nf files, all through \`_ew\`; $ndie exits, all through \`_die\`"
