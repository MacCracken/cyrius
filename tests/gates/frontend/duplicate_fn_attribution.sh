#!/bin/sh
# tests/gates/frontend/duplicate_fn_attribution.sh — v6.5.19
#
# A `duplicate fn` warning names the file:line a user can OPEN.
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
# `#derive` — which adds lines and cannot be padded — re-anchors with a `#@file`
# marker carrying the resumed source line.
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
#   * delete `op = PP_REANCHOR_SRC/CUR(...)` at the six derive sites
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

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: duplicate-fn-attribution — file:line names a real location in a real file"
    exit 0
fi
echo "FAIL: duplicate-fn-attribution — $fails assertion(s) failed"
exit 1
