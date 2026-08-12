#!/bin/sh
# tests/gates/frontend/duplicate_fn_attribution.sh — v6.5.19, extended v6.5.20
#
# A diagnostic names the file:line a user can OPEN — including one raised INSIDE a
# `#derive` construct, and one about a fn the derive SYNTHESIZED.
#
# THE FILED DEFECT (agnosai, 2026-08-10). 35 duplicate-fn warnings across seven
# bundles, and the line was wrong in 35 of 35 — `warning:lib/kavach.cyr:11588:` on a
# file 11,321 lines long. Root cause: FM_LOOKUP reconstructs a source line by linear
# arithmetic over a `#@file` span (`expanded - start + base`), which holds only while
# the preprocessor copies a file 1:1 into the expanded buffer. Two transforms broke
# that INSIDE a span and neither re-anchored:
#
#   #ifdef family  directive lines consumed + skipped bodies dropped -> line too SMALL
#                  (kavach: net −55 over 676 lines; all 30 warnings there were true−55)
#   #derive        2-3 source lines replaced by N generated -> line too LARGE
#                  (kavach: +476 by line 11112; one #derive(Serialize) site turned 3
#                   source lines into 112 expanded lines)
#
# Drift ACCUMULATES from the last marker, which is why reported lines ran past EOF.
# Fixed in v6.5.19: the `#ifdef` family pads one newline per consumed/skipped source
# line (line-faithful, no marker, no pressure on the 1024-entry file-map cap) and
# `#derive` — which adds lines and could not be padded — re-anchored with a `#@file`
# marker carrying the resumed source line.
#
# THE v6.5.20 RESIDUAL (axes 9-12). A re-anchor makes everything AFTER a construct
# exact and nothing INSIDE it: `expanded - start + base` is linear, so it cannot
# describe a span that stretches in the middle. A defect inside a `#derive`d struct
# still reported +1, and a warning about a SYNTHESIZED fn (which has no `fn` line in
# the source at all) landed in the generated block PAST EOF — 15..18 for a 14-line
# file. v6.5.20 removes the stretch instead of compensating for it: the consumed
# `#derive(...)` directive lines are PADDED like the `#ifdef` family, the struct is
# copied byte-for-byte (a look-ahead scan used to re-copy the whitespace run after
# every field-terminating `;`, DUPLICATING its newline — that was the +N), and the
# whole generated block is FLATTENED onto the struct's closing-`}` line. The block
# then occupies exactly the source lines it consumed, so the arithmetic is exact
# inside as well as after, and the derive re-anchor markers are GONE.
#
# WHAT THIS GATE ASSERTS. Reported line == the line `grep -n` finds, for each
# construct SEPARATELY (so a fix for one half cannot mask the other), for the two
# combined, and across an include boundary where the FILE must be right too.
#
# ⚠ ANTI-VACUOUS. Axis 0 pins the plain case (no ifdef, no derive), which was ALREADY
# correct before the fix — a gate that only checked the broken shapes could be
# satisfied by an implementation that reported garbage everywhere. Axis 5 requires the
# reported line to be inside the file, which is the filing's literal complaint, and
# axis 6 requires a clean file to emit NO duplicate warning at all.
#
# THREE AXES WERE ADDED AFTER THE FIRST CUT, each closing a hole this gate had:
#
#   axis 7 (`#define`)  The padding above is correct, but it UNMASKED a defect it did
#                       not cause. PP_EXPAND ended with an unconditional newline — +1
#                       output line per function-like invocation — and the unpadded
#                       `#define` line used to contribute a cancelling −1. Once every
#                       consumed directive line was padded, the cancellation went and
#                       each invocation reported one line late. Both `#define` forms are
#                       pinned here: object-like (which cyrius does not expand, exact
#                       only SINCE the padding) and function-like at one AND several
#                       invocations, since a single invocation is exactly the case the
#                       old cancellation hid.
#
#   axis 8 (`#ifdef` in an include, NO derive)  Axis 4 has a `#derive` AFTER its
#                       `#ifdef`, and the derive re-anchor RECOMPUTES the line from the
#                       input stream — so it repairs the drift and MASKS the padding.
#                       Deleting the PP_IFDEF_PASS half of the padding on its own left
#                       axes 0-6 fully green while genuinely changing the compiler.
#                       Axis 8 removes the derive so the drift survives to the warning.
#
#   axis 5b (no trailing newline)  FM_BUILD sized the LAST span from `line`, which
#                       counts newlines + 1 — one short when the buffer does not end in
#                       a newline, so that final line fell out of every span, FM_LOOKUP
#                       fell through to the raw EXPANDED line, and the message lost its
#                       `<file>:` prefix entirely. Axis 5's original fixture ended in a
#                       newline and so could not see it.
#
# MUTATION PROOF. Five mutant compilers, each differing from the shipped one by ONE
# hunk, each BUILT AND RUN against this gate — the outcomes below are measured, not
# argued. Every mutant is caught, and each is caught on a DIFFERENT axis, which is what
# makes the axes non-redundant:
#   * delete the `elif (c == 10) { store8(out + op, 10); op = op + 1; }` skip-padding in
#     PP_PASS only (src/frontend/lex_pp.cyr)
#         -> RED: axis 1 (12->4), axis 1 taken-branch (9->8), axis 3 (14->13)
#         -> green: 0, 2, 4, 5, 5b, 6, 7, 8
#   * delete the same skip-padding in PP_IFDEF_PASS only
#         -> RED: axis 8 ONLY (9->5).  Every other axis green — axis 4 cannot see it,
#            because its `#derive` re-anchor repairs the drift first. This mutant is
#            the reason axis 8 exists.
#   * delete `op = PP_REANCHOR_SRC/CUR(...)` at the six derive sites (v6.5.19 only —
#     v6.5.20 deleted those calls for real, and the padding + flattening below is what
#     replaces them; the same axes catch the padding being removed, see below)
#         -> RED: axis 2 (7->25), axis 3 (14->19), axis 4 (13->20), axis 5 (past EOF)
#         -> green: 1, 7, 8
#   * restore PP_EXPAND's unconditional trailing `store8(out + op, 10)`
#         -> RED: axis 7 one-invocation (4->5), three-invocation (6->9) and WRAPPED
#            (6->5 — it fails the OTHER WAY, so the wrapped assertion is load-bearing)
#         -> green: 0-6, 8
#   * delete FM_BUILD's `if (bl > 0) { if (load8(buf + bl - 1) != 10) ... }` last-line
#     bump (src/frontend/lex.cyr)
#         -> RED: axis 5b only (the `<source>:` prefix vanishes AND the line runs past
#            EOF) -> green: 0-5, 6, 7, 8
#
# v6.5.20 MUTATION PROOF for axes 9-13. Nine more mutant compilers, each ONE hunk off the
# shipped source, each BUILT AND RUN against this gate. Measured, not argued:
#   * M1  drop the `#derive` directive-line PADDING (lex_pp.cyr PP_PARSE_STRUCT_DEF)
#         -> RED: axis 9 (6->5, 9->8 on every kind), and 2/3/4/10 -- everything shifts −1
#   * M2  restore the whitespace DUPLICATION in the field look-ahead scan
#         -> RED: axis 9 (6->9), axis 5 (past EOF), 2/3/4/10 -- the original +N is back
#   * M3  consume the closing-`}` line before the tail copy runs
#         -> RED: axis 11 plus the line axes
#   * M3b drop ONLY the `op = PP_COPY_TAIL(...)` call, leaving the line accounting
#         PERFECT -- this is exactly the "obvious" design-1 implementation the remedy
#         exists to reject
#         -> RED: axis 11 ONLY (of the line axes: green). The shadowing sub-case fails
#            `exit expected 2, got 1` -- a program that compiled clean, warned nothing
#            and returned the wrong answer. Axes 9/10 CANNOT see this; that is why
#            axis 11 is judged on the exit code and not on a line number.
#   * M4  delete the `#` stop in PP_COPY_TAIL (copy the comment through)
#         -> RED: axis 11, comment sub-case ONLY (the comment eats the generated fns)
#   * M5  delete PP_COPY_TAIL's string tracking (`#` stop no longer string-aware)
#         -> RED: axis 11, `"#!/bin/sh"` sub-case ONLY (the literal truncates)
#   * M6  disable `_pp_flatten` (bodies keep their newlines)
#         -> RED: axis 10 (12->past EOF), 2/3/4/5.  Axis 9 stays GREEN -- the struct's
#            own lines precede the block, so only a synthesized-fn axis can see this.
#   * M7  raise `_err_excerpt`'s window threshold out of reach (util.cyr)
#         -> RED: axis 12 ONLY
#   * M8  restore the emitted `# nested struct` comment literal
#         -> RED: axis 13 ONLY (the block goes unbalanced; 4 parse errors)
#
# v6.5.20 FINISH-OUT — axes 11b and 14, and what the first cut of the tail remedy got
# wrong. Every axis-11 sub-case above puts the WHOLE tail on one line, and that is
# precisely why a MULTI-LINE tail shipped broken: the tail was copied FIRST and the
# generated bodies appended behind it, so a tail opening a construct that continues onto
# later lines had the whole generated block spliced INSIDE it. `rc=0`, no diagnostic,
# SIGSEGV at runtime — the remedy for a silent miscompile producing a silent miscompile.
# The fix is ordering: bodies first, user's tail LAST. Two more mutants, built and run:
#   * M9  revert the ordering (tail copied inside PP_PARSE_STRUCT_DEF, bodies behind it)
#         -> RED: axis 11b ONLY, 5 sub-cases — accessors/Serialize/stacked-Deserialize/
#            shadowing all exit 139, and the struct tail fails to compile. Every
#            one-line sub-case of axis 11 stays GREEN, which is the whole point of 11b.
#   * M10 revert PP_DERIVE_DESER to the hand-rolled skip (tail copy KEPT, struct not)
#         -> RED: axis 14 (all four assertions) + the stacked axis-11b sub-case.
#            Axis 11's one-line `Deserialize, fn after }` stays GREEN — it only ever
#            proved the TAIL survived, never the struct, which is how this shipped.
# Measured non-discriminators, recorded rather than glossed: an UNSTACKED
# `#derive(Deserialize)` cannot see M9 (it emits no bodies, so there is nothing to
# splice) and the `if`/`while` tails cannot either (cyrius hoists `fn` definitions out of
# a top-level block). The stacked form replaced the former; the latter stay as cover for
# the risk running the other way — the fix moves the tail, and a tail that opens a block
# must still open it.
#
# One more change was made in the same pass and it is NOT gated here, deliberately:
# `_ra_frame_trim`'s unaligned byte-pattern scan (parse_fn.cyr) now refuses any window
# overlapping a switch jump TABLE. Measured with a mutant that removes the guard
# (`_sw_tbl_hits` bypassed): 352 corpus files compiled by both, **0 binaries differ**.
# It rejects no real match today — it is hardening against a false match on table DATA,
# not a fix for an observed defect, and no assertion here would be honest.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="${CC:-$ROOT/build/cycc}"
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

if [ ! -x "$CC" ]; then
    echo "FAIL: duplicate-fn-attribution — $CC not built"
    exit 1
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Compile $1 (relative to $T) and print the file:line the FIRST duplicate-fn warning
# names, as "file line". Never merges stderr into the binary.
warn_at() {
    ( cd "$T" && "$CC" < "$1" > out.bin 2> err.txt )
    sed -n 's/^warning:\(.*\):\([0-9]*\):[0-9]*: duplicate fn.*/\1 \2/p' "$T/err.txt" | head -1
}
true_line() { grep -n "^fn $2" "$T/$1" | tail -1 | cut -d: -f1; }

# ── AXIS 0 — the shape that was ALREADY correct stays correct.
echo "axis 0 — ANTI-VACUOUS: a plain duplicate (no directives at all) is still exact:"
cat > "$T/plain.cyr" <<'EOF'
fn dup_plain() { return 1; }
fn spacer_a() { return 1; }
fn spacer_b() { return 2; }
fn dup_plain() { return 2; }
fn main() { return dup_plain(); }
var r = main();
EOF
set -- $(warn_at plain.cyr)
check "plain: warning emitted" "yes" "$([ -n "${2:-}" ] && echo yes || echo no)"
check "plain: line" "$(true_line plain.cyr dup_plain)" "${2:-none}"

# ── AXIS 1 — the #ifdef family. 2 directive lines + 8 skipped body lines = −10.
echo "axis 1 — #ifdef consumed/skipped lines no longer shrink the mapping:"
cat > "$T/ifdef.cyr" <<'EOF'
fn dup_ifdef() { return 1; }
#ifdef NEVER_DEFINED_XYZ
fn filler_a() { return 1; }
fn filler_b() { return 2; }
fn filler_c() { return 3; }
fn filler_d() { return 4; }
fn filler_e() { return 5; }
fn filler_f() { return 6; }
fn filler_g() { return 7; }
fn filler_h() { return 8; }
#endif
fn dup_ifdef() { return 2; }
fn main() { return dup_ifdef(); }
var r = main();
EOF
set -- $(warn_at ifdef.cyr)
check "ifdef: warning emitted" "yes" "$([ -n "${2:-}" ] && echo yes || echo no)"
check "ifdef: line" "$(true_line ifdef.cyr dup_ifdef)" "${2:-none}"

# The TAKEN branch drifts too — its #ifdef/#else/#endif lines are consumed even when
# the body is kept. A padding fix that only covered skipped bodies would pass axis 1
# and fail here.
cat > "$T/ifdef_taken.cyr" <<'EOF'
#define WANTED 1
fn dup_taken() { return 1; }
#ifdef WANTED
fn kept_a() { return 1; }
fn kept_b() { return 2; }
#else
fn dropped_a() { return 1; }
#endif
fn dup_taken() { return 2; }
fn main() { return dup_taken(); }
var r = main();
EOF
set -- $(warn_at ifdef_taken.cyr)
check "ifdef taken-branch: line" "$(true_line ifdef_taken.cyr dup_taken)" "${2:-none}"

# ── AXIS 2 — #derive. Expansion ADDS lines, so this half needs the re-anchor marker,
# not the padding. It must pass with the padding reverted and fail with the marker gone.
echo "axis 2 — #derive expansion no longer stretches the mapping:"
cat > "$T/derive.cyr" <<'EOF'
fn dup_derive() { return 1; }
#derive(accessors)
struct Pt {
    a; b; c; d;
    e; f; g; h;
}
fn dup_derive() { return 2; }
fn main() { return dup_derive(); }
var r = main();
EOF
set -- $(warn_at derive.cyr)
check "derive: warning emitted" "yes" "$([ -n "${2:-}" ] && echo yes || echo no)"
check "derive: line" "$(true_line derive.cyr dup_derive)" "${2:-none}"

# ── AXIS 3 — BOTH constructs, so the two errors cannot cancel. The filing's numbers
# were a −55 and a +476 in the same file; a fix for one half alone leaves a residual.
echo "axis 3 — both constructs in one file (the drifts must not merely cancel):"
cat > "$T/both.cyr" <<'EOF'
fn dup_both() { return 1; }
#ifdef NEVER_DEFINED_XYZ
fn gone_a() { return 1; }
fn gone_b() { return 2; }
fn gone_c() { return 3; }
#endif
#derive(accessors)
struct Q {
    x; y;
}
#ifdef NEVER_DEFINED_XYZ
fn gone_d() { return 4; }
#endif
fn dup_both() { return 2; }
fn main() { return dup_both(); }
var r = main();
EOF
set -- $(warn_at both.cyr)
check "both: warning emitted" "yes" "$([ -n "${2:-}" ] && echo yes || echo no)"
check "both: line" "$(true_line both.cyr dup_both)" "${2:-none}"

# ── AXIS 4 — ACROSS AN INCLUDE. This is the filed shape: the duplicate lives in an
# included module and the warning has to name that module AND its own line. The
# included file carries an #ifdef and a #derive of its own so the drift is real.
echo "axis 4 — a duplicate inside an INCLUDED file names that file and its own line:"
mkdir -p "$T/lib"
cat > "$T/lib/modx.cyr" <<'EOF'
fn dup_mod() { return 1; }
#ifdef NEVER_DEFINED_XYZ
fn mod_gone_a() { return 1; }
fn mod_gone_b() { return 2; }
fn mod_gone_c() { return 3; }
fn mod_gone_d() { return 4; }
#endif
#derive(accessors)
struct M {
    p; q; r;
}
fn mod_tail() { return 9; }
fn dup_mod() { return 2; }
EOF
cat > "$T/entry.cyr" <<'EOF'
#ifdef NEVER_DEFINED_XYZ
fn entry_gone() { return 0; }
#endif
include "lib/modx.cyr"
fn main() { return dup_mod(); }
var r = main();
EOF
set -- $(warn_at entry.cyr)
check "include: warning emitted" "yes" "$([ -n "${2:-}" ] && echo yes || echo no)"
check "include: FILE" "lib/modx.cyr" "${1:-none}"
mod_true=$(grep -n "^fn dup_mod" "$T/lib/modx.cyr" | tail -1 | cut -d: -f1)
check "include: line" "$mod_true" "${2:-none}"

# ── AXIS 5 — the filing's literal complaint: the line must EXIST in the named file.
# `awk END{print NR}`, not `wc -l`: wc counts NEWLINES, so it under-reports by one for a
# file whose last line is unterminated — which is exactly axis 5b's fixture.
echo "axis 5 — every reported line is inside the file it names (never past EOF):"
nlines=$(awk 'END{print NR}' "$T/lib/modx.cyr")
set -- $(warn_at entry.cyr)
in_file=no
if [ -n "${2:-}" ]; then [ "$2" -le "$nlines" ] && in_file=yes; fi
check "reported line <= $nlines (file length)" "yes" "$in_file"

# AXIS 5b — the same complaint, on the shape that actually produced it: a source with
# NO TRAILING NEWLINE whose defect is on the last line. FM_BUILD sized the last span
# from a newline count, so that line fell outside every span; the report was the raw
# EXPANDED line (past EOF) AND lost its `<file>:` prefix. `printf` without a final \n —
# a heredoc always adds one, which is why the original fixture could not see this.
printf 'fn dup_eof() { return 1; }\nfn eof_mid() { return 5; }\nfn dup_eof() { return 2; }' > "$T/noeol.cyr"
check "noeol: fixture really is unterminated" "1" \
      "$([ "$(tail -c1 "$T/noeol.cyr" | od -An -tu1 | tr -d ' ')" = "10" ] && echo 0 || echo 1)"
( cd "$T" && "$CC" < noeol.cyr > out.bin 2> err.txt )
eof_true=$(awk '/^fn dup_eof/{n=NR} END{print n}' "$T/noeol.cyr")
eof_len=$(awk 'END{print NR}' "$T/noeol.cyr")
# One assertion, both halves: the pattern REQUIRES the `<source>:` prefix, so a report
# that drops the filename yields the empty string and fails on the line comparison too.
eof_got=$(sed -n 's/^warning:<source>:\([0-9]*\):[0-9]*: duplicate fn.*/\1/p' "$T/err.txt" | head -1)
check "noeol: names <source> and the right line" "$eof_true" "${eof_got:-none}"
check "noeol: reported line <= $eof_len (file length)" "yes" \
      "$([ -n "$eof_got" ] && [ "$eof_got" -le "$eof_len" ] && echo yes || echo no)"

# ── AXIS 6 — a file with NO duplicate emits NO duplicate warning. Without this the
# gate could be satisfied by an implementation that warns about everything.
echo "axis 6 — ANTI-VACUOUS: a clean file emits no duplicate-fn warning:"
cat > "$T/clean.cyr" <<'EOF'
#ifdef NEVER_DEFINED_XYZ
fn clean_gone() { return 1; }
#endif
#derive(accessors)
struct C {
    u; v;
}
fn clean_one() { return 1; }
fn main() { return clean_one(); }
var r = main();
EOF
( cd "$T" && "$CC" < clean.cyr > out.bin 2> err.txt )
check "clean: duplicate warnings" 0 "$(grep -c 'duplicate fn' "$T/err.txt" || true)"
check "clean: still compiles" 0 "$([ -s "$T/out.bin" ] && echo 0 || echo 1)"

# ── AXIS 7 — `#define`, BOTH forms. The object-like case only became exact WITH the
# directive padding. The function-like case is the one the padding unmasked: PP_EXPAND
# emitted an unconditional newline per invocation, and the unpadded `#define` line used
# to cancel exactly the first one — so ONE invocation must be pinned as well as several,
# or the old cancellation passes for the single case and the count-dependence is missed.
echo "axis 7 — object-like and function-like #define are both line-exact:"
# The object-like form is NOT substituted into code by cyrius (it is a `#ifdef` flag),
# so the fixture declares it and gates on it rather than referencing it in an
# expression — what is under test is that its DIRECTIVE LINES are padded back.
cat > "$T/def_obj.cyr" <<'EOF'
fn dup_obj() { return 1; }
#define OBJ_FLAG 1
#ifdef OBJ_FLAG
fn obj_a() { return 1; }
#endif
fn dup_obj() { return 2; }
fn main() { return dup_obj(); }
var r = main();
EOF
set -- $(warn_at def_obj.cyr)
check "object-like #define: line" "$(true_line def_obj.cyr dup_obj)" "${2:-none}"

cat > "$T/def_fn1.cyr" <<'EOF'
fn dup_fn1() { return 1; }
#define SQ(x) ((x) * (x))
fn fn1_use() { return SQ(3); }
fn dup_fn1() { return 2; }
fn main() { return dup_fn1(); }
var r = main();
EOF
set -- $(warn_at def_fn1.cyr)
check "function-like #define, ONE invocation: line" "$(true_line def_fn1.cyr dup_fn1)" "${2:-none}"

# Several invocations: the old defect scaled with the count, so this catches a "fix"
# that merely re-tuned the cancellation for the single-invocation case.
cat > "$T/def_fn3.cyr" <<'EOF'
fn dup_fn3() { return 1; }
#define SQ(x) ((x) * (x))
fn u1() { return SQ(3); }
fn u2() { return SQ(4); }
fn u3() { return SQ(5); }
fn dup_fn3() { return 2; }
fn main() { return dup_fn3(); }
var r = main();
EOF
set -- $(warn_at def_fn3.cyr)
check "function-like #define, THREE invocations: line" "$(true_line def_fn3.cyr dup_fn3)" "${2:-none}"

# An invocation whose ARG LIST WRAPS really does consume those source lines, so the
# right answer is not "emit nothing" — it is "emit exactly what was consumed". A fix
# that just deleted the trailing newline reports 2 lines early here.
cat > "$T/def_wrap.cyr" <<'EOF'
fn dup_wrap() { return 1; }
#define ADD3(a, b, c) ((a) + (b) + (c))
fn w1() { return ADD3(1,
    2,
    3); }
fn dup_wrap() { return 2; }
fn main() { return dup_wrap(); }
var r = main();
EOF
set -- $(warn_at def_wrap.cyr)
check "function-like #define, WRAPPED arg list: line" "$(true_line def_wrap.cyr dup_wrap)" "${2:-none}"

# The expansion must still be CORRECT, not merely well-numbered.
cat > "$T/def_sem.cyr" <<'EOF'
#define SQ(x) ((x) * (x))
#define ADD3(a, b, c) ((a) + (b) + (c))
#define TWICE(x) ((x) + (x))
fn main() {
    var a = SQ(3);
    var b = ADD3(1,
        2,
        4);
    var c = TWICE(1 +
        2);
    return a + b + c;
}
var r = main();
EOF
( cd "$T" && "$CC" < def_sem.cyr > sem.bin 2> sem.err && chmod +x sem.bin )
( cd "$T" && ./sem.bin ); check "macro expansion still evaluates correctly" 22 "$?"

# ── AXIS 8 — `#ifdef` inside an INCLUDED file with NO `#derive` after it. Axis 4 cannot
# see the PP_IFDEF_PASS half of the padding, because its `#derive` re-anchor recomputes
# the line from the input stream and repairs the drift before the duplicate is reached.
# Strip the derive and the drift survives: pre-fix this reported 5 for a line-9 defect.
echo "axis 8 — #ifdef inside an include, with no #derive to mask it:"
cat > "$T/lib/pureifdef.cyr" <<'EOF'
fn dup_pure() { return 1; }
#ifdef NEVER_DEFINED_XYZ
fn pure_gone_a() { return 1; }
fn pure_gone_b() { return 2; }
fn pure_gone_c() { return 3; }
fn pure_gone_d() { return 4; }
#endif
fn pure_tail() { return 9; }
fn dup_pure() { return 2; }
EOF
cat > "$T/pure.cyr" <<'EOF'
include "lib/pureifdef.cyr"
fn main() { return dup_pure(); }
var r = main();
EOF
set -- $(warn_at pure.cyr)
check "include+ifdef only: FILE" "lib/pureifdef.cyr" "${1:-none}"
pure_true=$(grep -n "^fn dup_pure" "$T/lib/pureifdef.cyr" | tail -1 | cut -d: -f1)
check "include+ifdef only: line" "$pure_true" "${2:-none}"

# ── AXIS 9 — a defect INSIDE a `#derive`d struct names the line `grep -n` finds.
# Axes 2-4 only ever placed the duplicate AFTER the construct, which the v6.5.19
# re-anchor already repaired; nothing here looked INSIDE, where the +1 lived. Run
# across derive kinds and field counts so a fix tuned to one shape cannot pass.
echo "axis 9 — a defect INSIDE a #derive'd struct reports its own source line:"
in_struct_case() {
    # $1 label, $2 directive, $3 number of fields before the bad one
    {
        echo "fn lead_a() { return 1; }"
        echo "fn lead_b() { return 2; }"
        echo "$2"
        echo "struct InS {"
        i=0
        while [ "$i" -lt "$3" ]; do echo "    g$i;"; i=$((i + 1)); done
        echo "    bad = ;"
        echo "}"
        echo "fn main() { return 0; }"
        echo "var r = main();"
    } > "$T/ins.cyr"
    want=$(grep -n 'bad = ;' "$T/ins.cyr" | cut -d: -f1)
    ( cd "$T" && "$CC" < ins.cyr > out.bin 2> err.txt )
    got=$(sed -n 's/^error:<source>:\([0-9]*\):[0-9]*: .*/\1/p' "$T/err.txt" | head -1)
    check "in-struct ($1, $3 fields before): line" "$want" "${got:-none}"
}
in_struct_case accessors "#derive(accessors)" 1
in_struct_case accessors "#derive(accessors)" 4
in_struct_case Serialize "#derive(Serialize)" 1
in_struct_case Serialize "#derive(Serialize)" 4
in_struct_case stacked "#derive(Serialize)
#derive(accessors)" 3

# ── AXIS 10 — a warning about a fn the derive SYNTHESIZED. `Dup_a` has no `fn` line
# anywhere in the source, so this is the case a re-anchor structurally cannot fix: it
# fires INSIDE the generated block. Pre-v6.5.20 the four warnings for a 14-line file
# came out at 15, 16, 17, 18 — every one past EOF. They must now name the closing `}`
# of the construct that generated them, which is a line a user can open.
echo "axis 10 — a SYNTHESIZED duplicate names the construct that generated it:"
cat > "$T/syn.cyr" <<'EOF'
fn syn_pad() { return 1; }
#derive(accessors)
struct Dup {
    a;
    b;
}
fn syn_mid() { return 2; }
#derive(accessors)
struct Dup {
    a;
    b;
}
fn main() { return 0; }
var r = main();
EOF
( cd "$T" && "$CC" < syn.cyr > out.bin 2> err.txt )
syn_n=$(awk 'END{print NR}' "$T/syn.cyr")
syn_cnt=$(grep -c "duplicate fn 'Dup_" "$T/err.txt" || true)
check "synthesized: all four accessors warn" 4 "$syn_cnt"
# The SECOND construct's closing `}` — the block that redefines the names.
syn_want=$(awk '/^}/{n=NR} END{print n}' "$T/syn.cyr")
syn_out=$(sed -n "s/^warning:<source>:\([0-9]*\):[0-9]*: duplicate fn 'Dup_.*/\1/p" "$T/err.txt")
syn_bad=0
for l in $syn_out; do
    [ "$l" -le "$syn_n" ] || syn_bad=$((syn_bad + 1))
    [ "$l" = "$syn_want" ] || syn_bad=$((syn_bad + 1))
done
check "synthesized: every warning inside the file AND on the construct's } (line $syn_want)" 0 "$syn_bad"

# ── AXIS 11 — NO SILENT CODE LOSS. ⚠ THE LOAD-BEARING AXIS OF THE v6.5.20 CHANGE.
# Flattening needs the generated block to own the closing-`}` line, and the obvious way
# to get it is to CONSUME that line's tail. `struct Z { a; } fn helper() { return 2; }`
# is legal cyrius: consuming the tail deletes `helper` with no diagnostic at all — the
# program compiles clean and returns the wrong answer. Measured on the first cut:
# `struct Z { a; b; } var g = 77;` went from exit 77 to `undefined variable 'g'`.
# The remedy is to COPY the tail, stop at a `#` outside a string, and never copy the
# newline. Judged on the PROGRAM'S EXIT CODE, because a line-number test cannot see
# code go missing — that is exactly how the first implementation passed while broken.
echo "axis 11 — code after the struct's } survives (no silent code loss):"
tail_case() {
    # $1 label, $2 expected exit code, $3 program text
    printf '%s' "$3" > "$T/tail.cyr"
    ( cd "$T" && "$CC" < tail.cyr > tail.bin 2> tail.err )
    if [ ! -s "$T/tail.bin" ]; then
        check "tail ($1): compiles" "yes" "no"
        return
    fi
    chmod +x "$T/tail.bin"
    ( cd "$T" && ./tail.bin )
    check "tail ($1): exit" "$2" "$?"
}
tail_case "fn after }" 2 '#derive(accessors)
struct Z { a; } fn helper() { return 2; }
fn main() { return helper(); }
var r = main();
'
# ⭐ The GENUINELY SILENT shape. Above, a dropped tail is at least loud (`helper` becomes
# undefined and the build is refused). Here an earlier definition of the same name
# survives, so losing the tail produces a program that compiles clean, warns nothing,
# and quietly returns 1 instead of 2 — nothing but the exit code can tell.
tail_case "fn after } SHADOWING an earlier one (silent)" 2 'fn helper() { return 1; }
#derive(accessors)
struct Z { a; } fn helper() { return 2; }
fn main() { return helper(); }
var r = main();
'
tail_case "var after }" 77 '#derive(accessors)
struct Z { a; b; } var g = 77;
fn main() { return g; }
var r = main();
'
tail_case "Serialize, fn after }" 33 '#derive(Serialize)
struct P { x; y; } fn tailfn() { return 33; }
fn main() { return tailfn(); }
var r = main();
'
# `#derive(Deserialize)` alone used to skip the whole line, tail included — the same
# loss, shipped, before v6.5.20 gave that handler the copy too.
tail_case "Deserialize, fn after }" 44 '#derive(Deserialize)
struct D { u; v; } fn dtail() { return 44; }
fn main() { return dtail(); }
var r = main();
'
# A COMMENT tail must be dropped, not copied: on the flattened line it would comment
# out every generated fn behind it. Proven by the accessors still working.
tail_case "comment after }, accessors still work" 55 '#derive(accessors)
struct Z { a; b; } # trailing note
var zbuf[8];
fn main() { Z_set_b(&zbuf, 55); return Z_b(&zbuf); }
var r = main();
'
# ...and the `#` stop must be STRING-AWARE, or `"#!/bin/sh"` truncates mid-literal.
tail_case "hash inside a string in the tail" 68 '#derive(accessors)
struct Z { a; } var s = "#!/bin/sh";
fn main() { return load8(s) + load8(s + 1); }
var r = main();
'

# ── AXIS 11b — MULTI-LINE TAILS. ⚠ Every sub-case above puts the WHOLE tail on the
# closing-`}` line, and that is exactly why the first cut of the tail remedy shipped
# broken: it copied the tail and then appended the generated fns BEHIND it, which is
# correct only while the tail is self-contained. A tail that OPENS a construct
# continuing onto later source lines —
#     struct Z { a; } fn helper() {
#         return 42;
#     }
# — had every generated fn spliced INSIDE `helper`'s body. Measured on that cut:
# `rc=0`, no diagnostic beyond the routine DCE note, and the binary SIGSEGVs (139).
# A silent miscompile produced by the remedy for a silent miscompile.
#
# The fix is an ORDERING one — bodies first, user's tail LAST — so the opener is the
# final thing on the expanded line and the lines continuing it follow verbatim. These
# sub-cases pin every top-level construct a tail can open. `if` and `while` are legal at
# cyrius top level (verified), `struct` is the shape whose own `}` could confuse a
# brace-counting implementation, and all three derive kinds are covered because each has
# its own entry-point handler and could regress independently.
echo "axis 11b — a tail that OPENS a multi-line construct is not spliced into:"
tail_case "multi-line fn tail (accessors)" 42 '#derive(accessors)
struct Z { a; b; } fn helper() {
    return 42;
}
fn main() { return helper(); }
var r = main();
'
tail_case "multi-line fn tail (Serialize)" 43 '#derive(Serialize)
struct P { x; y; } fn helper() {
    var acc = 40;
    return acc + 3;
}
fn main() { return helper(); }
var r = main();
'
# `#derive(Deserialize)` emits no bodies of its own, so an UNSTACKED Deserialize cannot
# see the ordering at all (there is nothing to splice) — measured: it stays green under
# the reverted-ordering mutant. Stack it with `accessors` so bodies exist. This is the
# only sub-case that catches BOTH mutants: M9 (139) and M10 (compile-fail).
tail_case "multi-line fn tail (Deserialize + accessors stacked)" 44 'var zbuf[16];
#derive(Deserialize)
#derive(accessors)
struct D { u; v; } fn helper() {
    return 44;
}
fn main() { D_set_v(&zbuf, helper()); return D_v(&zbuf); }
var r = main();
'
# ⭐ The SHADOWING form again, now multi-line: an earlier `helper` survives, so splicing
# the generated fns into the new one is not even loud — on the broken cut this shape is
# the difference between exit 45 and a crash, with nothing else to see.
tail_case "multi-line fn tail SHADOWING an earlier one" 45 'fn helper() { return 1; }
#derive(accessors)
struct Z { a; } fn helper() {
    return 45;
}
fn main() { return helper(); }
var r = main();
'
# ⚠ The `if` and `while` sub-cases below are ANTI-VACUOUS COVER, not discriminators, and
# the distinction is recorded rather than glossed: measured against the reverted-ordering
# mutant they stay GREEN, because cyrius hoists `fn` definitions out of a top-level block,
# so generated fns spliced inside an `if`/`while` body still resolve. What they DO pin is
# the risk running the other way — the fix MOVES the tail, and a tail that opens a block
# must still open it. Both were verified legal at top level before being used here.
tail_case "multi-line if tail" 46 'var acc = 0;
#derive(accessors)
struct Z { a; } if (1 == 1) {
    acc = 46;
}
fn main() { return acc; }
var r = main();
'
tail_case "multi-line while tail" 47 'var acc = 0;
#derive(accessors)
struct Z { a; } while (acc < 47) {
    acc = acc + 1;
}
fn main() { return acc; }
var r = main();
'
# A tail opening ANOTHER struct: its `}` is the one a naive brace-matcher would pair
# with the derive struct. The generated accessors must still work, and the second
# struct must still be a usable type.
tail_case "multi-line struct tail, both types usable" 48 '#derive(accessors)
struct Z { a; b; } struct W {
    m;
    n;
}
var zbuf[16];
fn main() { Z_set_b(&zbuf, 48); var w = W { 1, 2 }; return Z_b(&zbuf); }
var r = main();
'

# ── AXIS 14 — `#derive(Deserialize)` KEEPS THE STRUCT. Axis 11's Deserialize sub-cases
# only prove the TAIL survives; the struct itself is a separate loss, and it shipped.
# `PP_DERIVE_DESER` hand-rolled "skip the directive line, scan to the first `}`" and
# emitted only newline padding, so the ONE directive whose name says "this struct is
# data" was the one that deleted it. Two halves, and the second is the serious one:
#   (a) the type is unusable — `D { 5, 7 }` failed `undefined variable 'D'`;
#   (b) a MALFORMED FIELD is SILENTLY ACCEPTED — `struct D { x; y = ; }` compiled rc=0
#       with zero diagnostics, because the parser is what diagnoses field syntax and the
#       parser never saw the text. Silent acceptance of malformed source.
# Both are judged behaviourally: (a) on the program running, (b) on a diagnostic
# existing AND naming the right line. The `#derive(Serialize)` control is what makes
# (b) non-vacuous — it proves the error text is the parser's ordinary one and not
# something special-cased for this axis.
echo "axis 14 — #derive(Deserialize) keeps the struct (usable type, fields checked):"
cat > "$T/deskeep.cyr" <<'EOF'
#derive(Deserialize)
struct D { x; y; }
fn main() {
    var d = D { 12, 48 };
    return d.x + d.y;
}
var r = main();
EOF
( cd "$T" && "$CC" < deskeep.cyr > deskeep.bin 2> deskeep.err )
if [ -s "$T/deskeep.bin" ]; then
    chmod +x "$T/deskeep.bin"; ( cd "$T" && ./deskeep.bin ); dkrc=$?
else
    dkrc="compile-fail: $(sed -n 1p "$T/deskeep.err")"
fi
check "Deserialize: the struct is a usable type" 60 "$dkrc"

# Stacking in the Deserialize-FIRST direction was collateral of the same defect: the
# hand-rolled skip never collected the `#derive(...)` flag bits, so a directive stacked
# BELOW `#derive(Deserialize)` was dropped whole. (The reverse order always worked —
# measured green on every compiler here — which is why it went unnoticed.)
printf 'var zbuf[16];\n#derive(Deserialize)\n#derive(accessors)\nstruct D { u; v; }\nfn main() { D_set_v(&zbuf, 44); return D_v(&zbuf); }\nvar r = main();\n' > "$T/desstack.cyr"
( cd "$T" && "$CC" < desstack.cyr > desstack.bin 2> desstack.err )
if [ -s "$T/desstack.bin" ]; then
    chmod +x "$T/desstack.bin"; ( cd "$T" && ./desstack.bin ); dsrc=$?
else
    dsrc="compile-fail: $(sed -n 1p "$T/desstack.err")"
fi
check "Deserialize-first stacking runs the stacked handler" 44 "$dsrc"

for kind in Deserialize Serialize accessors; do
    printf '#derive(%s)\nstruct D { x; y = ; }\nfn main() { return 3; }\nvar r = main();\n' \
        "$kind" > "$T/desbad.cyr"
    ( cd "$T" && "$CC" < desbad.cyr > desbad.bin 2> desbad.err )
    check "$kind: malformed field is REFUSED (binary not emitted)" "yes" \
          "$([ -s "$T/desbad.bin" ] && echo no || echo yes)"
    check "$kind: malformed field names line 2" "2" \
          "$(sed -n 's/^error:<source>:\([0-9]*\):[0-9]*: .*/\1/p' "$T/desbad.err" | head -1)"
done

# ── AXIS 12 — a diagnostic ON the flattened line must be WINDOWED. A 10-field
# `#derive(Serialize)` flattens to ~9.5 KB; unwindowed, `_err_excerpt` printed the whole
# line plus one space per column of caret padding — ~19 KB of stderr for ONE error.
# Also anti-vacuous in the other direction: a SHORT line must still print in full, so
# the window cannot be implemented by simply truncating every excerpt.
echo "axis 12 — a diagnostic on the flattened line is windowed, short lines are not:"
{
    echo '#derive(Serialize)'
    echo 'struct Big {'
    for c in a b c d e f g h i j; do echo "    $c;"; done
    echo '} fn t() { var q = ; }'
    echo 'fn main() { return 0; }'
    echo 'var r = main();'
} > "$T/big.cyr"
big_want=$(grep -n 'var q = ;' "$T/big.cyr" | cut -d: -f1)
( cd "$T" && "$CC" < big.cyr > out.bin 2> err.txt )
big_got=$(sed -n 's/^error:<source>:\([0-9]*\):[0-9]*: .*/\1/p' "$T/err.txt" | head -1)
check "windowed: line still exact" "$big_want" "${big_got:-none}"
big_len=$(awk 'NR==2{print length($0)}' "$T/err.txt")
check "windowed: excerpt line <= 300 bytes" "yes" \
      "$([ -n "$big_len" ] && [ "$big_len" -le 300 ] && echo yes || echo no)"
check "windowed: whole diagnostic <= 2048 bytes" "yes" \
      "$([ "$(wc -c < "$T/err.txt")" -le 2048 ] && echo yes || echo no)"
printf 'fn shortline() { var q = ; }\nfn main() { return 0; }\nvar r = main();\n' > "$T/short.cyr"
( cd "$T" && "$CC" < short.cyr > out.bin 2> err.txt )
check "short line printed in FULL (not truncated)" "    fn shortline() { var q = ; }" \
      "$(sed -n 2p "$T/err.txt")"

# ── AXIS 13 — NO `#` IN GENERATED TEXT. Flattening makes every `#` in an emitted
# literal a live hazard: it comments out the REST of the block, which on one line means
# every fn behind it. The audit found exactly one — a `# nested struct` comment line in
# the generated `_from_json`, reachable only when a field's declared type is another
# `#derive`d struct, which no existing .tcyr had. This fixture is that shape, and it is
# the only thing standing between the audit and a silent regression if someone adds a
# `#` to an emitted literal later. Judged on the program running: the comment would
# swallow the remainder of Outer_from_json and leave the block unbalanced.
echo "axis 13 — a nested-struct-typed #derive(Serialize) field emits no '#':"
cat > "$T/nested.cyr" <<'EOF'
#derive(Serialize)
struct Inner {
    p;
    q;
}
#derive(Serialize)
struct Outer {
    n: Inner;
    z;
}
fn after_nested() { return 21; }
fn main() { return after_nested(); }
var r = main();
EOF
( cd "$T" && "$CC" < nested.cyr > nested.bin 2> nested.err )
if [ -s "$T/nested.bin" ]; then
    chmod +x "$T/nested.bin"; ( cd "$T" && ./nested.bin ); nrc=$?
else
    nrc="compile-fail"
fi
check "nested-struct field: program still builds and runs" 21 "$nrc"
check "nested-struct field: no parse error" 0 \
      "$(grep -c '^error:' "$T/nested.err" || true)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: duplicate-fn-attribution — file:line names a real location in a real file"
    exit 0
fi
echo "FAIL: duplicate-fn-attribution — $fails assertion(s) failed"
exit 1
