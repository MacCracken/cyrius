#!/bin/sh
# tests/gates/toolchain/cyrlint_cross_line.sh — v6.6.5
#
# cyrlint's rules see ACROSS A LINE BREAK: a deferral term a formatter wrapped, an
# initializer that continues on the next line, a string literal holding a raw newline,
# a call whose arguments wrap, an enum whose members share a line.
#
# THE FILED DEFECT (mabda 4.1.3, 2026-09-16;
# docs/development/issues/archived/2026-09-16-mabda-cyrlint-misses-deferrals-split-across-lines.md).
# `cyrlint --strict-deferrals` matched each term against ONE physical line, so
#     # The immediate-offset form is a later
#     # bite.
# exited 0 while the same words on one line exited 2. mabda shipped three that way
# (gfx9_compile.cyr:326 and :532, compute.cyr:347) behind a green gate.
#
# THE SAME PER-LINE SHAPE, FIXED IN THE SAME BITE:
#   * init-order: `var A = 1 +\n    B;` against a later `var B = g();` drew NO warning
#     while the compiled program really reads B as 0 — axis 7 proves that with a
#     RUNTIME oracle (the binary exits 1, its reordered twin exits 3) before it asks
#     cyrlint anything;
#   * every brace/depth tracker forgot "inside a string" at each line end, so the raw
#     newline in src/main.cyr's error string made every src/main*.cyr fork draw a false
#     "unclosed braces at end of file", and a `}` inside such a string took a real
#     top-level `var` out of the init-order rule's sight (axis 8);
#   * the sys_open / getdents notes stopped at the line end, and the error-enum note
#     read one token per line (axis 9).
# REVIEW ROUND 2 widened the same shape (each with a RUNTIME oracle where a program is
# involved): an initializer whose `=` opens the NEXT line (`var A` / `    = 1 + B;` exits
# 1, its twin 3); `pub var` / `public var` declarations; a SECOND decl on a line as a
# pass-1 TARGET; `#naked fn f() {` / `#inline fn g() {` — a `#` the lexer reads as an
# attribute TOKEN, not a comment (it cost 15 false brace warnings and blinded init-order;
# cyrfmt had the same reading and rewrote such a fn body flush left, axis 13);
# `sys_open (…)` / `syscall` + `(` on the next line; whitespace inside a multi-line string;
# a trailing comment on the line that CLOSES a multi-line string; and the snake_case rule
# on `pub fn` / `public fn` / `#inline fn` (it saw only a line-initial `fn `).
# REVIEW ROUND 3 made the init-order unit the STATEMENT: a header wrapped anywhere (`var` /
# `A = …`, `var A:` / `i64 = …`, `var A` / `: i64 = …`), a declaration after a `}` or after the
# `;` of a wrapped initializer, and two declarations on ONE line (ordered by OFFSET) — runtime
# twins exit 100 vs 115 — with a walk frontier that keeps it linear and a missing `;` that no
# longer blinds the rest of the file. Also: escaped quotes / char literals (axis 8), cyrfmt's
# unbounded output buffer (it SEGFAULTED on 20K unclosed lines — axis 13), cyrdoc reading
# `pub fn` / `#inline fn` and the WHOLE file (a fixed 64 KB read; axis 14), a census of the
# init-order and lexical fixture directories (axis 0), and compiled fixtures run under the
# same 10 s timeout as cyrlint.
#
# ⭐ AXIS 2 PINS THE POINTER SCOPE. The filing proposed "accept a tracking pointer
# anywhere in the joined block". Measured, that hides one of the filing's own three
# cases — compute.cyr's block carries a `docs/` path, which then "tracks" its
# `for`/`now` — and silently un-flags 98 of 179 existing notes in this repo. The rule
# shipped is: a pointer counts only on a PHYSICAL LINE THE OCCURRENCE TOUCHES. A
# block-scope implementation returns 0 notes on the compute excerpt and FAILS here.
#
# ORACLES. Every expected value is a literal table typed from the fixture text, never
# a cyrlint run. The single-line fixtures are ALSO checked against an awk
# re-implementation of the pre-6.6.5 per-line rule (a different program in a different
# language), which is the single-line-invariance promise made concrete. The cyrlint
# under test is COMPILED HERE from programs/cyrlint.cyr — never build/cyrlint, the
# store or PATH, any of which can be a binary not built from this tree.
#
# ANTI-VACUOUS: a clean fixture exits 0 under --strict-deferrals; the tracked twin of
# the 12-term file gives 0; a genuinely unbalanced file still warns; every rawstr /
# break fixture that must give 0 sits next to one that must NOT.
#
# MUTATION PROOF — every mutant built from a scratch copy of the tree and run through
# THIS gate; "checks failed + hard failures" per mutant, re-measured at review round 3
# with the final gate (GREEN again on the real source, 136 checks). 52 mutants, all RED. A hard failure is a
# crash, a timeout or a missing trailer (lint_run); after the first timeout every later
# run fails at once, which is why the timing mutants fail many rows.
#   m1  per-line deferral rule restored (every member line its own paragraph)   18+0
#   m2  join always inserts a space (no hyphen rule)                              1+0
#   m3  code lines do not break the paragraph (trailing comments join)           24+0
#   m4  paragraph-wide pointer scope (the filing's proposal)                     17+1
#   m5  no case fold on the prose terms                                           1+0
#   m6  CR dropped from the whitespace set                                        1+0
#   m7  a `#`+letter line breaks the paragraph and stands alone                   1+0
#       (the directive class the plan proposed, dropped: a directive's keyword
#       always interrupts the phrase, so the class changed 0 notes over 24,241
#       ecosystem files and only hid `#now`-style wraps — hash_word.cyr)
#   m8  no string carry across lines (_lx_line ignores in_str)                    6+0
#   m9  pointer-verdict cache removed (axis 10 times out)                        13+1
#   m10 init-order scan stops at the line end (the 6.6.4 shape)                   2+0
#   m11 the `=`-before-`;`/`#` guard dropped                                      1+0
#   m12 lint_file's brace delta from a per-line string state                      3+0
#   m13 notes reported at the paragraph's first line                              7+0
#   m14 `;` taken as value position in an enum body                               1+0
#   m15 call search not code-aware (substring match inside strings)               2+0
#   m16 no second `var` after a `;` (the chain stops)                             3+0
#   m17 paragraph state not reset per file, and no final flush                    4+0
#   m18 the generalised version pointer removed (only literal v5./v6. count)      1+0
# REVIEW ROUND 2 — the harness itself, and the widened shapes:
#   mD  cyrlint SEGFAULTS on a line starting in a string in a file > 20 KB        1+7
#       (the round-1 gate read PASS 77/77 on this: every expected-'' / 0 row
#       discarded cyrlint's exit status, so a crash printed nothing and matched)
#   mH  pass 1 records only the FIRST decl on a line                              2+0
#   mI  a code part's term dropped when the line has a trailing comment           1+0
#   mJ  the init scan's decl-start bound removed (missing_semi: the rest blinded)  1+0
#   mK  the getdents continuation walk ignores the call's own `)`                 1+0
#   mL  the header walk stops at the declaration line's end                       2+0
#   mM  the header walk ignores the decl-start bound (missing_semi)               1+0
#   mN  no `pub`/`public` prefix skip                                             2+0
#   mO  a `#` attribute token read as a comment again (_lx_attr_len == 0)         4+0
#   mP  a call's `(` must follow the name immediately (literal `name(`)           2+0
#   mQ  the sys_open search stops at the first call on a line                     1+0
#   mR  trailing-whitespace rule not gated on the string state                    1+0
#   mS  blank-line rule not gated on the string state                             1+0
#   mT  a line starting in a string stands alone (its trailing comment dropped)   1+0
#   mU  a non-terminating loop in the term scan: RED in 12 s, not a hang         85+1
#   mV  cyrfmt reads a `#` attribute token as a comment again                     3+0
#   mW  the snake_case rule sees only a line-initial `fn ` (no pub/attribute)     1+0
# REVIEW ROUND 3 (mJ/mM were quadratic mutants until the walk frontier made every walk
# linear; they are now pinned by missing_semi.cyr instead; the old mL is the header walk
# stopping at a newline):
#   mX1 a bare `var` takes no name from the next line                             1+0
#   mX3 declarations ordered by LINE, not offset                                  1+0
#   mX4 the `;` chain stops at the line end                                       1+0
#   mX5 no declaration tried after a `}` (_gio_brace_decls not called)            1+0
#   mX6 no walk frontier (50K `{} var vN = (` lines: quadratic, times out)        6+1
#   mX7 the after-`}` walk ignores the line-start depth                           1+0
#   mX8 an escaped quote closes the string (_lx_skip_str steps 1, not 2)          2+0
#   mX9 a char literal is never skipped (_lx_skip_char steps one byte)            2+0
#   mDA cyrdoc: no `pub`/`public` before `fn`                                     3+0
#   mDB cyrdoc: an attribute token read as a comment                              3+0
#   mDC cyrdoc: no look past attribute-only lines for the doc comment             3+0
#   mDD cyrdoc: the 6.6.4 fixed 64 KB read                                        2+0
#   mDE cyrdoc: the buffer never grows past its first 1 MB                        1+0
#   mFA cyrfmt: the output cap removed (SIGSEGV on the deep inputs)               6+0
#   mFB cyrfmt: the indent loop keeps spinning past the cap (>10 s)               6+6
#   mFC cyrfmt: stdout mode writes a truncated result instead of refusing         2+0
#   mRP harness: a fixture PROGRAM that never exits — RED in 13 s, not a hang     1+1
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0

check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

if [ ! -x "$ROOT/build/cycc" ]; then
    echo "FAIL: cyrlint-cross-line — build/cycc not built"
    exit 1
fi
command -v timeout > /dev/null 2>&1 || { echo "FAIL: cyrlint-cross-line — needs timeout(1)"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cyrlint_cross_line: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
F="$ROOT/tests/fixtures/lint_deferrals"
IO="$ROOT/tests/fixtures/lint_init_order"
LX="$ROOT/tests/fixtures/lint_lexical"

# ── Build THIS tree's cyrlint (the CLI for axis 12, cyrfmt for 13). A compile that fails, or
# that produces an empty/tiny file, stops the gate: cycc on empty stdin exits 0 and
# emits a runnable binary, so an unbuilt tool would otherwise score a fake PASS.
build_one() {   # $1 source, $2 dest
    if ! "$ROOT/build/cycc" < "$1" > "$2" 2> "$T/build.err"; then
        echo "FAIL: cyrlint-cross-line — could not build $1"; sed -n '1,5p' "$T/build.err"; exit 1
    fi
    if [ ! -s "$2" ] || [ "$(wc -c < "$2")" -lt 20000 ]; then
        echo "FAIL: cyrlint-cross-line — $1 produced a $(wc -c < "$2")-byte binary"; exit 1
    fi
    chmod +x "$2"
}
BIN="$T/home/bin"
mkdir -p "$BIN" "$T/h" "$T/w"
build_one "$ROOT/programs/cyrlint.cyr" "$BIN/cyrlint"
build_one "$ROOT/cbt/cyrius.cyr" "$BIN/cyrius"
cp "$ROOT/build/cycc" "$BIN/cycc"
L="$BIN/cyrlint"
build_one "$ROOT/programs/cyrfmt.cyr" "$BIN/cyrfmt"
build_one "$ROOT/programs/cyrdoc.cyr" "$BIN/cyrdoc"

# Every cyrlint run goes through here: stdout → $T/lo, stderr → $T/le, under a 10 s
# timeout. A timeout, a signal death or a missing "<n> warnings" trailer ("<n> warnings
# total" after several files) is a HARD
# failure: the helper prints a HARD:… sentinel (which no expected value equals, so the
# calling check FAILS and says why) and logs it to $T/hard. ⚠ Round 1 discarded rc on
# every row that expects '' or 0, so a cyrlint that SEGFAULTED on all seven src/main*.cyr
# forks read PASS 77/77. After the first TIMEOUT every later run fails at once, so a
# hanging build costs one timeout, not one per row (a looping mutant used to hang the
# gate — and check.sh — until it was killed by hand). LRC = the exit code; LDIR = the
# directory to run in (default: the repo root). Returns 1 on a hard failure, so a bare
# call is written `lint_run … || :` — the gate is `bash -eo pipefail`-safe: every
# intentionally-failing command is `rc=0; cmd || rc=$?` or sits in a conditional.
: > "$T/hard"
LDIR=""
lint_run() {
    if grep -q '^TIMEOUT' "$T/hard"; then LHARD="HARD:after-timeout"; LRC=x; return 1; fi
    LRC=0
    ( cd "${LDIR:-$ROOT}" && timeout 10 "$L" "$@" ) > "$T/lo" 2> "$T/le" || LRC=$?
    LHARD=""
    if [ "$LRC" -eq 124 ]; then LHARD="HARD:timeout"; echo "TIMEOUT cyrlint $*" >> "$T/hard"
    elif [ "$LRC" -ge 128 ]; then LHARD="HARD:signal-rc=$LRC"; echo "CRASH rc=$LRC cyrlint $*" >> "$T/hard"
    elif ! tail -n 1 "$T/lo" | grep -Eq '^[0-9]+ warnings( total)?$'; then
        LHARD="HARD:no-trailer-rc=$LRC"; echo "NO TRAILER rc=$LRC cyrlint $*" >> "$T/hard"
    fi
    [ -z "$LHARD" ]
}
# The CLI (axis 12) under the same timeout and the same fail-fast.
cli_run() {
    if grep -q '^TIMEOUT' "$T/hard"; then CRC=after-timeout; return; fi
    CRC=0
    ( cd "$T/w" && HOME="$T/h" CYRIUS_HOME="$T/home" timeout 10 "$BIN/cyrius" "$@" > /dev/null 2>&1 ) || CRC=$?
    if [ "$CRC" -eq 124 ]; then echo "TIMEOUT cyrius $*" >> "$T/hard"; fi
}

# compile + run a fixture with build/cycc; RUN_RC = the program's exit code. The program
# runs under the same 10 s timeout as cyrlint (round 3): a fixture miscompiled into a
# loop used to hang the gate, and check.sh with it. A timeout is a HARD failure, logged
# as PROGTIMEOUT (so it does not trip lint_run's fail-fast, which is for a hung cyrlint).
run_prog() {   # $1 source
    if ! "$ROOT/build/cycc" < "$1" > "$T/prog" 2> "$T/prog.err"; then
        echo "  FAIL: $1 does not compile"; sed -n '1,3p' "$T/prog.err"; fails=$((fails + 1)); RUN_RC=x; return
    fi
    if [ ! -s "$T/prog" ]; then echo "  FAIL: $1 compiled to an empty file"; fails=$((fails + 1)); RUN_RC=x; return; fi
    chmod +x "$T/prog"
    RUN_RC=0
    timeout 10 "$T/prog" || RUN_RC=$?
    rm -f "$T/prog"
    if [ "$RUN_RC" = 124 ]; then
        echo "  FAIL: $1 — the compiled program did not finish in 10 s"
        echo "PROGTIMEOUT $1" >> "$T/hard"; RUN_RC=x
    fi
}
# "line:term|line:term" in report order — the deferral notes of one file.
dnotes() {
    lint_run "$@" || { echo "$LHARD"; return; }
    sed -n "s/^  deferral line \([0-9]*\): untracked '\([^']*\)'.*/\1:\2/p" "$T/le" | paste -sd'|' -
}
# the pre-6.6.5 per-line rule, re-implemented in awk: first term (exact case) on a
# line with none of the 7 old pointers and no #skip-lint.
awk_oracle() {
    awk 'BEGIN { n = split("NOT_IMPLEMENTED|SCAFFOLD|TODO|FIXME|XXX|deferred|follow-up|for now|not yet|later bite|future bite|out of scope", t, "|") }
         index($0, "#skip-lint") { next }
         index($0, "CHANGELOG") || index($0, "roadmap") || index($0, "docs/") || index($0, "issue") || index($0, "See ") || index($0, "v6.") || index($0, "v5.") { next }
         { for (i = 1; i <= n; i++) if (index($0, t[i])) { print NR ":" t[i]; break } }' "$1" | paste -sd'|' -
}
expect() {   # $1 fixture path, $2 literal table
    check "$(basename "$1")" "$2" "$(dnotes "$1")"
}

echo "axis 0 — census: every fixture under tests/fixtures/lint_deferrals has a row here"
ROWS="split one split_unwrapped mabda_gfx9 mabda_compute hyphen hash_word trail_head trail_pair skip_break directive_break para_break str_hash rawstr rawstr_todo str_close_trailing code_trailing indent ptr_second ptr_first ptr_other ptr_next ptr_see ptr_version terms12 terms12_tracked clean"
unrowed=0
for f in "$F"/*.cyr; do
    b=$(basename "$f" .cyr)
    case " $ROWS " in *" $b "*) ;; *) echo "  FAIL: fixture $b.cyr has no row"; unrowed=$((unrowed + 1)) ;; esac
done
check "fixtures with no row" 0 "$unrowed"
nf=$(ls "$F"/*.cyr | wc -l | tr -d ' ')
nr=$(echo $ROWS | wc -w | tr -d ' ')
check "fixture count == row count (floor, derived from the directory)" "$nr" "$nf"
# …and every init-order / lexical fixture is named by a row of this gate (round 3: those
# two directories had no census, so a fixture could sit there unexamined)
SELF="$ROOT/tests/gates/toolchain/cyrlint_cross_line.sh"
unused=0; nfx=0
for f in "$IO"/*.cyr "$LX"/*.cyr; do
    nfx=$((nfx + 1))
    b=$(basename "$f")
    grep -q "/$b\"" "$SELF" || { echo "  FAIL: fixture $b is used by no row"; unused=$((unused + 1)); }
done
check "init-order + lexical fixtures used by no row" 0 "$unused"
check "  (floor: >= 26 such fixtures)" yes "$([ "$nfx" -ge 26 ] && echo yes || echo no)"

echo "axis 1 — ⭐ the filed repro, verbatim"
LDIR="$F"; lint_run --strict-deferrals split.cyr || :; LDIR=""
check "cyrlint --strict-deferrals split.cyr exits 2 (was 0)" 2 "$LRC"
check "  …and counts 2" "2 untracked deferrals" "$(grep 'untracked deferrals' "$T/le")"
expect "$F/split.cyr" "1:later bite|3:for now"
LDIR="$F"; lint_run --strict-deferrals one.cyr || :; LDIR=""
check "cyrlint --strict-deferrals one.cyr exits 2" 2 "$LRC"
expect "$F/one.cyr" "1:later bite"
expect "$F/split_unwrapped.cyr" "1:later bite|3:for now"
check "  …and the wrapped file reports the SAME lines as the unwrapped one" "$(dnotes "$F/split_unwrapped.cyr")" "$(dnotes "$F/split.cyr")"

echo "axis 2 — ⭐ the filed real cases (mabda 4.1.2 excerpts) — pins the pointer scope"
expect "$F/mabda_gfx9.cyr" "4:later bite|10:later bite"
expect "$F/mabda_compute.cyr" "6:for now"

echo "axis 3 — join shapes"
expect "$F/hyphen.cyr" "1:follow-up"
expect "$F/hash_word.cyr" "1:for now"
printf '# The immediate-offset form is a later\r\n# bite.\r\nfn crlf_a(): i64 { return 0; }\r\n' > "$T/crlf.cyr"
expect "$T/crlf.cyr" "1:later bite"
check "  (the CRLF fixture really has CRs)" 3 "$(tr -cd '\r' < "$T/crlf.cyr" | wc -c | tr -d ' ')"
expect "$F/trail_head.cyr" "2:for now"
expect "$F/trail_pair.cyr" ""
expect "$F/skip_break.cyr" ""
expect "$F/directive_break.cyr" ""
expect "$F/para_break.cyr" ""
expect "$F/str_hash.cyr" ""
expect "$F/rawstr.cyr" ""
expect "$F/rawstr_todo.cyr" "2:TODO"
expect "$F/str_close_trailing.cyr" "2:for now"
expect "$F/code_trailing.cyr" "2:NOT_IMPLEMENTED"
printf '# The immediate-offset form is a later\n# bite.' > "$T/eof_nonl.cyr"
expect "$T/eof_nonl.cyr" "1:later bite"
expect "$F/indent.cyr" "2:later bite"

echo "axis 4 — pointer scope: only the lines the occurrence touches"
expect "$F/ptr_second.cyr" ""
expect "$F/ptr_first.cyr" ""
expect "$F/ptr_other.cyr" "2:later bite"
expect "$F/ptr_next.cyr" "1:TODO"
expect "$F/ptr_see.cyr" ""
expect "$F/ptr_version.cyr" "7:deferred|9:deferred"

echo "axis 5 — single-line invariance + anti-vacuous"
T12="1:NOT_IMPLEMENTED|3:SCAFFOLD|5:TODO|7:FIXME|9:XXX|11:deferred|13:follow-up|15:for now|17:not yet|19:later bite|21:future bite|23:out of scope"
expect "$F/terms12.cyr" "$T12"
check "terms12 — the awk per-line oracle agrees with the literal table" "$T12" "$(awk_oracle "$F/terms12.cyr")"
for s in one ptr_next ptr_see ptr_second clean; do
    check "$s — cyrlint agrees with the awk per-line oracle" "$(awk_oracle "$F/$s.cyr")" "$(dnotes "$F/$s.cyr")"
done
expect "$F/terms12_tracked.cyr" ""
LDIR="$F"; lint_run --strict-deferrals clean.cyr || :; LDIR=""
check "a clean file exits 0 under --strict-deferrals" 0 "$LRC"
expect "$F/clean.cyr" ""

echo "axis 6 — case and whitespace (prose terms fold; markers do not)"
printf '# For now the table is fixed.\nfn case_a(): i64 { return 0; }\n# NOT YET GREEN on hardware\nfn case_b(): i64 { return 0; }\n# Deferred until the port.\nfn case_c(): i64 { return 0; }\n# the table is fixed for  now\nfn case_d(): i64 { return 0; }\n# the table is not\t\tyet wide\nfn case_e(): i64 { return 0; }\nvar todo_list = 0;\n# a todo list and a fixme note\nfn case_f(): i64 { return todo_list; }\n' > "$T/case_ws.cyr"
expect "$T/case_ws.cyr" "1:for now|3:not yet|5:deferred|7:for now|9:not yet"

echo "axis 7 — ⭐ init-order across lines, with a RUNTIME oracle first"
run_prog "$IO/multiline_forward.cyr"; FWD=$RUN_RC
run_prog "$IO/multiline_ordered.cyr"; ORD=$RUN_RC
check "runtime: the wrapped forward ref reads ZERO (1 + 0)" 1 "$FWD"
check "runtime: the same program in declaration order computes 3" 3 "$ORD"
iw() {
    lint_run "$1" || { echo "$LHARD"; return; }
    sed -n 's/^  warn line \([0-9]*\): global var init refs .\([A-Za-z_0-9]*\). declared at line \([0-9]*\).*/\1:\2:\3/p' "$T/le" | paste -sd'|' -
}
check "cyrlint warns on the wrapped initializer" "2:MLF_B:4" "$(iw "$IO/multiline_forward.cyr")"
check "cyrlint is silent on the ordered twin" "" "$(iw "$IO/multiline_ordered.cyr")"
run_prog "$IO/comment_eq.cyr"
check "runtime: comment_eq is a valid program" 0 "$RUN_RC"
check "an '=' inside a trailing comment is not an initializer" "" "$(iw "$IO/comment_eq.cyr")"
run_prog "$IO/two_statement.cyr"
check "runtime: the second var on a line really reads zero" 0 "$RUN_RC"
check "the second var after a ';' is examined" "2:TWO_LATE:3" "$(iw "$IO/two_statement.cyr")"
run_prog "$IO/statement_after_init.cyr"
check "runtime: statement_after_init is a valid program" 2 "$RUN_RC"
check "a statement after the initializer's ';' is not part of it" "" "$(iw "$IO/statement_after_init.cyr")"
nfw=no
if lint_run "$IO/forward_refs.cyr"; then
    if [ "$(grep -c 'global var init refs' "$T/le" || :)" -ge 3 ]; then nfw=yes; fi
else nfw=$LHARD; fi
check "forward_refs still >= 3 (the v5.7.32 floor)" yes "$nfw"
check "string_literal_safe still 0" "" "$(iw "$IO/string_literal_safe.cyr")"
run_prog "$IO/eq_next_line.cyr"; EQF=$RUN_RC
run_prog "$IO/eq_next_line_ordered.cyr"; EQO=$RUN_RC
check "runtime: an '=' opening the NEXT line still reads the later var as zero (1 + 0)" 1 "$EQF"
check "runtime: …its declaration-order twin computes 3" 3 "$EQO"
check "the '=' is found past the declaration line (and its comments)" "2:EQN_B:5" "$(iw "$IO/eq_next_line.cyr")"
check "  …and the ordered twin stays silent" "" "$(iw "$IO/eq_next_line_ordered.cyr")"
run_prog "$IO/second_decl_recorded.cyr"; SDF=$RUN_RC
run_prog "$IO/second_decl_ordered.cyr"; SDO=$RUN_RC
check "runtime: a ref to the SECOND decl on a later line reads zero" 0 "$SDF"
check "runtime: …its declaration-order twin reads 2" 2 "$SDO"
check "pass 1 records the second decl on a line as a TARGET" "2:SDR_L:3" "$(iw "$IO/second_decl_recorded.cyr")"
check "  …and the ordered twin stays silent" "" "$(iw "$IO/second_decl_ordered.cyr")"
run_prog "$IO/pub_var.cyr"; PVF=$RUN_RC
run_prog "$IO/pub_var_ordered.cyr"; PVO=$RUN_RC
check "runtime: pub/public var initializers read a later pub var as zero (1 + 4)" 5 "$PVF"
check "runtime: …their declaration-order twin computes 3 + 6" 9 "$PVO"
check "pub var / public var are declarations in both passes" "2:PV_B:4|3:PV_B:4" "$(iw "$IO/pub_var.cyr")"
check "  …and the ordered twin stays silent" "" "$(iw "$IO/pub_var_ordered.cyr")"
run_prog "$IO/header_wrapped.cyr"; HWF=$RUN_RC
run_prog "$IO/header_wrapped_ordered.cyr"; HWO=$RUN_RC
check "runtime: a header wrapped anywhere (name, ':', type on the next line) still reads zero (100 + 0)" 100 "$HWF"
check "runtime: …its declaration-order twin reads all four (100 + 1 + 2 + 4 + 8)" 115 "$HWO"
check "the header is walked across lines; a bare 'var' takes its name from the next line (both passes)" "3:HW_B1:10|5:HW_B2:11|7:HW_B3:12|9:HW_B4:13" "$(iw "$IO/header_wrapped.cyr")"
check "  …and the ordered twin stays silent" "" "$(iw "$IO/header_wrapped_ordered.cyr")"
run_prog "$IO/mid_line_decls.cyr"; MLF=$RUN_RC
run_prog "$IO/mid_line_decls_ordered.cyr"; MLO=$RUN_RC
check "runtime: same-line, after-a-wrapped-';' and after-'}' declarations read zero (100 + 0)" 100 "$MLF"
check "runtime: …their declaration-order twin reads all four (100 + 1 + 2 + 4 + 8)" 115 "$MLO"
check "declarations mid-line: order by OFFSET, the ';' chain across lines, after a '}' (ref and target)" "2:SL_B:2|4:SL_D:5|6:SL_F:7|8:SL_H:11" "$(iw "$IO/mid_line_decls.cyr")"
check "  …and the ordered twin stays silent" "" "$(iw "$IO/mid_line_decls_ordered.cyr")"
if "$ROOT/build/cycc" < "$IO/missing_semi.cyr" > /dev/null 2>&1; then ms=compiles; else ms=rejected; fi
check "  (premise: missing_semi does NOT compile — it is the file-in-progress case)" rejected "$ms"
check "a declaration missing its ';' or '=' does not blind the rule to the rest of the file" "6:MS_B:7" "$(iw "$IO/missing_semi.cyr")"

echo "axis 8 — string state crosses lines (brace depth, top-level detection)"
nl_warn() {   # $1 file, $2 message — the warn lines, space-separated
    lint_run "$1" || { echo "$LHARD"; return; }
    grep "$2" "$T/le" | sed -n 's/^  warn line \([0-9]*\):.*/\1/p' | paste -sd' ' -
}
bw() {
    lint_run "$1" || { echo "$LHARD"; return; }
    grep -c 'unclosed braces\|unmatched closing brace' "$T/le" | tr -d ' '
}
run_prog "$LX/brace_rawstr.cyr"
check "runtime: brace_rawstr is a valid program" 0 "$RUN_RC"
check "a raw-newline string inside { } draws no brace warning" 0 "$(bw "$LX/brace_rawstr.cyr")"
check "ANTI-VACUOUS: a genuinely unbalanced file still warns" 1 "$(bw "$LX/brace_unbalanced.cyr")"
run_prog "$LX/toplevel_rawstr.cyr"
check "runtime: TL_A reads zero (TL_B is declared later)" 0 "$RUN_RC"
check "a '}' inside a multi-line string does not end the fn" 0 "$(bw "$LX/toplevel_rawstr.cyr")"
check "  …so the top-level forward ref after it is seen" "6:TL_B:7" "$(iw "$LX/toplevel_rawstr.cyr")"
run_prog "$LX/attr_brace.cyr"
check "runtime: attr_brace reads AT_B as zero after its #inline/#naked fns" 1 "$RUN_RC"
check "'#naked fn f() {' / '#inline fn g() {' are code: no brace warning" 0 "$(bw "$LX/attr_brace.cyr")"
check "  …so the forward ref after them is seen" "9:AT_B:10" "$(iw "$LX/attr_brace.cyr")"
check "the real #naked test file draws no brace warning (was 15)" 0 "$(bw "$ROOT/tests/tcyr/codegen/naked_fn_attribute.tcyr")"
run_prog "$LX/escapes.cyr"
check "runtime: escapes reads ES_B as zero, and every escape/char literal is the byte it names (40 + 0 + 0)" 40 "$RUN_RC"
check "an escaped quote / a quote or brace char literal is not a delimiter: no brace warning" 0 "$(bw "$LX/escapes.cyr")"
check "  …so the forward ref after the fn is seen" "10:ES_B:11" "$(iw "$LX/escapes.cyr")"
run_prog "$LX/fn_name_prefixed.cyr"
check "runtime: fn_name_prefixed is a valid program (pub/public/#inline fn all parse)" 0 "$RUN_RC"
check "snake_case: 'pub fn', 'public fn' and '#inline fn' names are checked too (prose/string/Type_method are not)" "2 3 4 5" "$(nl_warn "$LX/fn_name_prefixed.cyr" 'fn name should be snake_case')"
nmain=0; bad=0
for m in "$ROOT"/src/main*.cyr; do
    nmain=$((nmain + 1))
    if ! lint_run "$m"; then echo "  FAIL: $m — $LHARD"; bad=$((bad + 1))
    elif [ "$(grep -c 'unclosed braces at end of file' "$T/le" || :)" != 0 ]; then echo "  FAIL: $m draws 'unclosed braces'"; bad=$((bad + 1)); fi
done
check "no src/main*.cyr fork draws the false 'unclosed braces'" 0 "$bad"
check "  (fork floor: all 7 forks linted)" yes "$([ "$nmain" -ge 7 ] && echo yes || echo no)"
nraw=$(grep -l 'buffer$' "$ROOT"/src/main*.cyr | wc -l | tr -d ' ' || :)
check "  (premise: >= 6 forks really carry the raw-newline string)" yes "$([ "$nraw" -ge 6 ] && echo yes || echo no)"
printf 'var ws_help = "usage:   \n\n\n  cyr run\n";\nfn ws_f(): i64 { return 0; }\nvar ws_x = 1;   \n\n\nfn ws_g(): i64 { return ws_x; }\nsyscall(60, 0);\n' > "$T/rawstr_ws.cyr"
check "  (premise: the string's line 1 ends in spaces, its lines 2-3 are blank)" "1 2" "$(sed -n 1p "$T/rawstr_ws.cyr" | grep -c ' $') $(sed -n 2,3p "$T/rawstr_ws.cyr" | grep -c '^$')"
run_prog "$T/rawstr_ws.cyr"
check "runtime: rawstr_ws is a valid program" 0 "$RUN_RC"
wsw() {
    lint_run "$1" || { echo "$LHARD"; return; }
    sed -n 's/^  warn line \([0-9]*\): \(trailing whitespace\|multiple consecutive blank lines\)$/\1:\2/p' "$T/le" | paste -sd'|' -
}
check "whitespace INSIDE a multi-line string is data: only the code lines warn" "7:trailing whitespace|9:multiple consecutive blank lines" "$(wsw "$T/rawstr_ws.cyr")"

echo "axis 9 — notes: wrapped calls, enum members"
nl_of() {
    lint_run "$1" || { echo "$LHARD"; return; }
    grep "$2" "$T/le" | sed -n 's/^  note line \([0-9]*\):.*/\1/p' | paste -sd' ' -
}
check "sys_open notes (wrapped x2, single-line x2, _sys_open not a stopper, 'sys_open (' and a '(' on the next line, the 2nd call on a line)" "1 4 12 13 15 17 20" "$(nl_of "$LX/sysopen_wrapped.cyr" 'raw sys_open')"
check "getdents notes (wrapped, single-line, 'syscall (', '(' on the next line, …syscall( kept; a walk stops at the call's own ')')" "2 5 15 18 21" "$(nl_of "$LX/getdents_wrapped.cyr" 'raw getdents')"
run_prog "$LX/enum_members.cyr"
check "runtime: enum_members is valid cyrius (the ;, bare and payload forms parse)" 16 "$RUN_RC"
check "every bare ERR_* member noted, per member" "2 2 4 4 9 18 18 19 19 20" "$(nl_of "$LX/enum_members.cyr" 'bare ERR_')"

echo "axis 10 — linearity on hostile 1 MB inputs (the uncached form took 27 s)"
awk 'BEGIN { ORS = ""; print "#"; for (i = 0; i < 120000; i++) print " not yet"; print " CHANGELOG\n# a later bite\n" }' > "$T/big_tracked.cyr"
lint_run "$T/big_tracked.cyr" || :
check "a 960 KB tracked line + 120K terms finishes under 10 s" 0 "$LRC"
check "  …with exactly one note, on line 2" "2:later bite" "$(sed -n "s/^  deferral line \([0-9]*\): untracked '\([^']*\)'.*/\1:\2/p" "$T/le" | paste -sd'|' -)"
awk 'BEGIN { for (i = 0; i < 50000; i++) { print "# for"; print "# now" } }' > "$T/big_para.cyr"
lint_run "$T/big_para.cyr" || :
check "a 100K-line paragraph finishes under 10 s" 0 "$LRC"
check "  …with exactly 50000 notes" 50000 "$(grep -c '^  deferral line' "$T/le")"
awk 'BEGIN { for (i = 0; i < 90000; i++) print "syscall(a," }' > "$T/big_calls.cyr"
lint_run "$T/big_calls.cyr" || :
check "90K unclosed syscall( lines finish under 10 s" 0 "$LRC"
awk 'BEGIN { for (i = 0; i < 60000; i++) print "var v" i " = (;" }' > "$T/big_init.cyr"
lint_run "$T/big_init.cyr" || :; bi=${LHARD:-ok}
check "60K unterminated initializers (does not parse) finish under 10 s — the decl-start bound" ok "$bi"
awk 'BEGIN { for (i = 0; i < 60000; i++) print "var v" i; print "= 1;" }' > "$T/big_noeq.cyr"
lint_run "$T/big_noeq.cyr" || :; bn=${LHARD:-ok}
check "60K '='-less declarations finish under 10 s — the '=' look-ahead stops at the first token" ok "$bn"
awk 'BEGIN { for (i = 0; i < 50000; i++) print "{} var v" i " = (" }' > "$T/big_brace.cyr"
lint_run "$T/big_brace.cyr" || :; bb=${LHARD:-ok}
check "50K after-'}' declarations with unclosed initializers finish under 10 s — the walk frontier" ok "$bb"

echo "axis 11 — per-file state in a multi-file run"
printf 'fn tail_a(): i64 { return 0; }\n# the form is a later\n' > "$T/tail_a.cyr"
printf '# bite of the encoder\nfn head_b(): i64 { return 0; }\n' > "$T/head_b.cyr"
if lint_run "$T/tail_a.cyr" "$T/head_b.cyr"; then n11=$(grep -c '^  deferral line' "$T/le" || :); else n11=$LHARD; fi
check "a paragraph never joins across files" 0 "$n11"
if lint_run "$F/split.cyr" "$F/clean.cyr"; then n11=$(sed -n 's/^\([0-9]*\) untracked deferrals$/\1/p' "$T/le" | paste -sd'|' -); else n11=$LHARD; fi
check "per-file deferral counts (split, then clean)" "2|0" "$n11"

echo "axis 12 — through the CLI, both flag positions (bite 8 forwards the flag)"
mkdir -p "$T/home/versions/$(cat "$ROOT/VERSION")"
ln -s "$T/home" "$T/h/.cyrius"
cp "$F/split.cyr" "$T/w/split.cyr"
cli_run lint split.cyr --strict-deferrals
check "cyrius lint split.cyr --strict-deferrals" 2 "$CRC"
cli_run lint --strict-deferrals split.cyr
check "cyrius lint --strict-deferrals split.cyr" 2 "$CRC"
cli_run lint split.cyr
check "ANTI-VACUOUS: cyrius lint split.cyr (no flag) exits 0" 0 "$CRC"

echo "axis 13 — cyrfmt reads the same '#' (a fn attribute is code, not a comment)"
for f in "$LX/attr_brace.cyr" "$ROOT/tests/tcyr/codegen/naked_fn_attribute.tcyr"; do
    rc=0
    timeout 10 "$BIN/cyrfmt" --check "$f" > /dev/null 2> "$T/fe" || rc=$?
    check "cyrfmt --check $(basename "$f") (a '#naked fn f() {' body keeps its indent)" 0 "$rc"
done
printf '#inline fn fa_g(): i64 {\nreturn 2;\n}\n' > "$T/fmt_flat.cyr"
rc=0
timeout 10 "$BIN/cyrfmt" --check "$T/fmt_flat.cyr" > /dev/null 2>&1 || rc=$?
check "ANTI-VACUOUS: a flush-left body under '#inline fn' is still NOT canonical" 1 "$rc"
# round 3: the output buffer had no bound — 20K unclosed '(' or '{' lines indent line i by
# ~2i or 4i spaces, and --check / --write SEGFAULTED (rc 139, at 6.6.4 too) while the
# stdout mode streamed >100 MB. Now every mode fails loudly, fast (~60 ms), and writes
# nothing. The sizes (70K / 50K lines, both under the 1 MB input cap) are chosen so an
# indent loop that keeps spinning past the cap takes >10 s — mutant mFB.
awk 'BEGIN { for (i = 0; i < 70000; i++) print "syscall(a," }' > "$T/deep_paren.cyr"
awk 'BEGIN { for (i = 0; i < 50000; i++) print "if (a) {" }' > "$T/deep_brace.cyr"
for f in deep_paren deep_brace; do
    for m in --check --write ""; do
        cp "$T/$f.cyr" "$T/fmt_w.cyr"
        rc=0
        timeout 10 "$BIN/cyrfmt" $m "$T/fmt_w.cyr" > "$T/fo" 2> "$T/fe" || rc=$?
        [ "$rc" -eq 124 ] && echo "TIMEOUT cyrfmt $m $f" >> "$T/hard"
        got="rc=$rc out=$(wc -c < "$T/fo" | tr -d ' ') $(cmp -s "$T/fmt_w.cyr" "$T/$f.cyr" && echo untouched || echo REWRITTEN) $(grep -c 'would exceed 8 MB' "$T/fe" || :)"
        check "cyrfmt ${m:-(stdout)} on 50K+ unclosed lines ($f): a loud refusal, fast, not a crash" "rc=1 out=0 untouched 1" "$got"
    done
done
rc=0
timeout 10 "$BIN/cyrfmt" "$LX/attr_brace.cyr" > "$T/fo" 2> /dev/null || rc=$?
check "ANTI-VACUOUS: the buffered stdout mode still writes a canonical file back whole" "rc=0 same" "rc=$rc $(cmp -s "$T/fo" "$LX/attr_brace.cyr" && echo same || echo DIFFERS)"

echo "axis 14 — cyrdoc: the same '#' and 'pub fn', and the WHOLE file (review round 3)"
doc_run() {   # cyrdoc --check under the same timeout; DRC = its exit code, output in $T/do
    DRC=0
    timeout 10 "$BIN/cyrdoc" --check "$@" > "$T/do" 2>&1 || DRC=$?
    if [ "$DRC" -eq 124 ] || [ "$DRC" -ge 128 ]; then echo "CYRDOC rc=$DRC cyrdoc --check $*" >> "$T/hard"; fi
}
run_prog "$LX/doc_prefixed.cyr"
check "runtime: doc_prefixed is a valid program (pub/public/#inline/#must_use fn all parse)" 36 "$RUN_RC"
doc_run "$LX/doc_prefixed.cyr"
check "cyrdoc sees 'pub fn' / 'public fn' / '#inline fn' / a fn under an attribute line" "dp_pub_undoc dp_public_undoc dp_inline_undoc dp_attr_undoc" "$(sed -n 's/^  undocumented: //p' "$T/do" | paste -sd' ' -)"
check "  …an attribute line is no doc comment, and a doc above one counts" "3 documented, 4 undocumented (8 total)" "$(tail -n 1 "$T/do")"
check "  …exit = the undocumented count" 4 "$DRC"
awk 'BEGIN { for (i = 0; i < 3000; i++) { print "# doc " i; print "fn dg_" i "(): i64 { return 0; }" } print "fn dg_tail(): i64 { return 0; }" }' > "$T/doc_big.cyr"
check "  (premise: doc_big is past the old 64 KB read)" yes "$([ "$(wc -c < "$T/doc_big.cyr")" -gt 65536 ] && echo yes || echo no)"
doc_run "$T/doc_big.cyr"
check "cyrdoc reads the WHOLE file: every fn is counted, and the undocumented one past 64 KB is seen" "3000 documented, 1 undocumented (3001 total)" "$(tail -n 1 "$T/do")"
awk 'BEGIN { for (i = 0; i < 30000; i++) { print "# doc " i; print "fn dh_" i "(): i64 { return 0; }" } print "fn dh_tail(): i64 { return 0; }" }' > "$T/doc_huge.cyr"
check "  (premise: doc_huge is past cyrdoc's first 1 MB buffer)" yes "$([ "$(wc -c < "$T/doc_huge.cyr")" -gt 1048576 ] && echo yes || echo no)"
doc_run "$T/doc_huge.cyr"
check "  …and past the first 1 MB buffer (it grows; sigil's 1.1 MB bundle was judged on 6 %)" "30000 documented, 1 undocumented (30001 total)" "$(tail -n 1 "$T/do")"

echo ""
nhard=$(wc -l < "$T/hard" | tr -d ' ')
if [ "$nhard" -gt 0 ]; then
    echo "  hard failures (cyrlint crashed, hung or printed no trailer):"
    sed 's/^/    /' "$T/hard"
fi
if [ "$fails" -gt 0 ] || [ "$nhard" -gt 0 ]; then
    echo "FAIL: cyrlint-cross-line — $fails of $checks checks failed, $nhard hard failures"
    exit 1
fi
echo "PASS: cyrlint-cross-line — $checks checks"
exit 0
