#!/bin/sh
# Gate: the language guide's WORKED EXAMPLES must not teach a stale or silently-wrong API.
#
# ⛔ WHAT THIS CAUGHT WHEN IT WAS WRITTEN (v6.6.2), all of it live in the shipped guide:
#
#   1. The Result worked example was the PRE-FLIP one — five compile errors, two lines under the
#      table that ANNOUNCES the arity change: `var opt = Some(42);` (a single-var bind of a pair),
#      `unwrap(opt)` at 1 arg, `unwrap_or(opt, 0)` at 2, `var r = Ok(99);`, `result_unwrap(r)`.
#   2. A SECOND instance in the `#derive(Serialize)` enum section, same shape.
#   3. ⭐ THE ONE NOTHING COULD HAVE CAUGHT BY COMPILING: every SIMD example passed
#      `f32_from(<integer>)`. `f32_from` takes an f64 BIT PATTERN (cvtsd2ss) — integer 1 read as
#      f64 bits is a denormal ~5e-324 and narrows to f32 **ZERO**. The examples COMPILE and build
#      all-zero vectors. The same mistake had made `tests/tcyr/simd/simd_f32v8.tcyr` VACUOUS:
#      it used the broken expression on BOTH sides of every assertion, so all 15 were `0 == 0`
#      and passed whether or not f32v8 SIMD worked at all.
#
# ⚖️ SCOPE, STATED HONESTLY. Blocks that DECLARE THEMSELVES COMPLETE (they contain an
# `include "lib/...`) are compiled as written — 18 of the guide's ~103 cyrius/unlabeled blocks. Of
# those, several are ALSO illustrative (`f32v8_make(/* 8 lanes */)`), so this gate does NOT require
# them all to compile.
#
# The other ~85 have no include. Until 6.6.16 the gate DELETED them before compiling anything, so a
# reserved-word fn name (`fn use()`, a hard parse error) and a wrong-arity `file_open(path, 0)`
# shipped in the guide with this gate green. Axis 4 now compiles every one of them too, behind a
# fixed PRELUDE of the libs the guide's complete examples use (string, alloc, str, fmt, vec, io,
# tagged, fnptr). Many are still deliberate fragments — `...`, helpers that do not exist — and
# they stay EXCUSED exactly as axis 1 excuses them: an undefined illustrative name is not a red.
# Two classes are not excused, by axis 1 OR axis 4 (one shared STALE_PAT): the stale-API errors
# and `got reserved keyword`. A block with a line starting `# error:` is a deliberate error demo
# and is skipped. Output tables / trees / diagnostics belong in a ```text fence, not an unlabeled
# one, or axis 4 compiles them.
#
# Plus axis 2, a pure text check for the `f32_from(<int>)` shape, because that one COMPILES.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC=${CYCC:-${CYCC_BIN:-"$ROOT/build/cycc"}}
GUIDE="$ROOT/docs/guides/cyrius-guide.md"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: guide_examples_compile: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: guide_examples_compile: $1"; exit 1; }
[ -x "$CYCC" ] || fail "no cycc at $CYCC"
[ -f "$GUIDE" ] || fail "docs/guides/cyrius-guide.md missing"
cd "$ROOT"

# ── extract the self-declaring blocks ───────────────────────────────────────────────────
# ⚠ FENCE STATE MUST BE TRACKED FOR *EVERY* FENCE, NOT ONLY THE ONES WE WANT. The first cut of
# this only set `infence` for cyrius blocks, so a ```sh block's CLOSING fence was read as an
# OPENING one and every subsequent block was mis-paired — it extracted 2 of 18 and then the
# anti-vacuous floor (correctly) refused to let that pass as a clean run.
awk -v out="$WORK" '
  /^```/ {
    if (infence) { infence = 0; next }
    infence = 1
    lang = substr($0, 4); gsub(/[ \t\r]/, "", lang)
    want = (lang == "" || lang == "cyrius")
    fname = out "/blk_" NR ".cyr"
    if (want) print "" > fname
    next
  }
  infence && want { print $0 >> fname }
' "$GUIDE"
# Axes 1 and 3 take the blocks that declare themselves complete; the include-less ones move to
# $WORK/frag for axis 4 (they were deleted here until 6.6.16 — see SCOPE above).
mkdir -p "$WORK/frag"
for f in "$WORK"/blk_*.cyr; do
    [ -e "$f" ] || continue
    grep -q 'include "lib/' "$f" || mv "$f" "$WORK/frag/"
done
NBLK=$(ls "$WORK"/blk_*.cyr 2>/dev/null | wc -l | tr -d ' ')

# ⚠ ANTI-VACUOUS FLOOR. If the extractor breaks — a fence-style change, an awk quirk — it yields
# zero blocks and every check below trivially passes while inspecting nothing.
[ "${NBLK:-0}" -ge 10 ] || fail "extracted only ${NBLK} self-declaring examples from the guide — the extractor is broken, so a clean result proves nothing"

# ── axis 1: no example may fail with a STALE-API error ──────────────────────────────────
# ONE pattern for every axis (detection AND display): the stale-API errors plus a reserved word
# used as an identifier (`fn use()`). Axis 4 reuses it unchanged, so the two non-excused classes
# hold guide-wide, not only for the include-less blocks.
STALE_PAT="expects [0-9]+ arguments, got [0-9]+|undefined function '(payload|tag|tagged_new)'|returns two values|got reserved keyword"
STALE=""
for f in "$WORK"/blk_*.cyr; do
    "$CYCC" < "$f" > /dev/null 2>"$f.err" || true
    if grep -qE "$STALE_PAT" "$f.err"; then
        # ⚠ The DISPLAY pattern must equal the DETECTION pattern. An earlier cut used a looser
        # one and reported "undefined function 'fmt_int'" for a failure actually triggered by an
        # arity error — a gate that misnames its own reason costs the reader the debugging time
        # the gate was supposed to save.
        echo "  ⛔ $(basename "$f" .cyr | sed 's/blk_/guide line /'): $(grep -m1 -E "$STALE_PAT" "$f.err" | cut -c1-110)"
        STALE="$STALE $(basename "$f")"
    fi
done
[ -z "$STALE" ] || fail "the guide teaches an API the compiler no longer has, or a reserved-word identifier:$STALE"

# ── axis 2: the f32_from contract, which a compile CANNOT catch ─────────────────────────
# `f32_from(<integer literal>)` compiles and silently yields ZERO. Checked as text across the
# guide AND the corpus, because the corpus instance is what made a SIMD gate vacuous.
BADF=$(grep -rn 'f32_from([0-9][0-9]*)' "$GUIDE" "$ROOT/tests" "$ROOT/lib" 2>/dev/null \
       | grep -v '^\s*#' | grep -vE '#.*f32_from\([0-9]' || true)
if [ -n "$BADF" ]; then
    echo "$BADF" | sed 's/^/  ⛔ /'
    fail "f32_from takes an f64 BIT PATTERN — an integer literal narrows to f32 ZERO. Use 1.0, not 1."
fi

# ── axis 3 (ANTI-VACUOUS): a meaningful number of examples must actually COMPILE ────────
# Axis 1 only reds on a specific error class, so a guide whose every example was garbage would
# pass it. This asserts the corpus is genuinely exercising the compiler.
OK=0
for f in "$WORK"/blk_*.cyr; do
    "$CYCC" < "$f" > /dev/null 2>/dev/null && OK=$((OK + 1))
done
[ "$OK" -ge 5 ] || fail "only ${OK} of ${NBLK} self-declaring examples compile at all — axis 1 is not meaningfully exercised"

# ── axis 4: the include-less blocks, compiled behind a fixed prelude ────────────────────
# Prelude lines are counted so a `<source>:N` diagnostic maps back to the GUIDE line:
# block line k sits at guide line fence+k-1 (the extractor writes a blank first line for the
# fence itself), so guide line = fence + N - NPRE - 1.
PRELUDE="$WORK/prelude.cyr"
: > "$PRELUDE"
for l in string alloc str fmt vec io tagged fnptr; do
    [ -f "$ROOT/lib/$l.cyr" ] || fail "axis 4 prelude lib lib/$l.cyr is missing"
    echo "include \"lib/$l.cyr\"" >> "$PRELUDE"
done
NPRE=$(wc -l < "$PRELUDE" | tr -d ' ')
NFRAG=0; NDEMO=0; FOK=0; FBAD=""
for f in "$WORK"/frag/blk_*.cyr; do
    [ -e "$f" ] || continue
    NFRAG=$((NFRAG + 1))
    # A deliberate error demo (`# error: ...` under the code it refuses) is not compiled.
    if grep -q '^# error:' "$f"; then NDEMO=$((NDEMO + 1)); continue; fi
    FENCE=$(basename "$f" .cyr | sed 's/blk_//')
    cat "$PRELUDE" "$f" > "$f.p"
    if "$CYCC" < "$f.p" > /dev/null 2>"$f.err"; then FOK=$((FOK + 1)); fi
    if grep -qE "$STALE_PAT" "$f.err"; then
        MSG=$(grep -m1 -E "$STALE_PAT" "$f.err")
        SL=$(echo "$MSG" | sed -n 's/.*<source>:\([0-9][0-9]*\).*/\1/p')
        if [ -n "$SL" ]; then WHERE="guide line $((FENCE + SL - NPRE - 1)) (block at $FENCE)"
        else WHERE="guide block at line $FENCE"; fi
        echo "  ⛔ $WHERE: $(echo "$MSG" | cut -c1-110)"
        FBAD="$FBAD $FENCE"
    fi
done
# ⚠ ANTI-VACUOUS FLOORS (84 include-less blocks and 42 clean compiles at 6.6.16 — 85 / 39 before
# that release's guide edits).
# A broken extractor or a prelude that stopped resolving would otherwise pass axis 4 by
# compiling nothing — every fragment then "fails" with an excused undefined name.
[ "$NFRAG" -ge 60 ] || fail "axis 4 extracted only ${NFRAG} include-less blocks (floor 60) — the extractor is broken"
[ "$FOK" -ge 30 ] || fail "axis 4: only ${FOK} of $((NFRAG - NDEMO)) include-less blocks compile clean behind the prelude (floor 30) — the prelude is not resolving"
[ -z "$FBAD" ] || fail "axis 4: an include-less guide example teaches a stale API or a reserved-word identifier (blocks at:$FBAD)"

echo "PASS: guide_examples_compile (${NBLK} self-declaring examples, ${OK} compile clean, 0 stale-API / reserved-word, f32_from contract held; axis 4: ${NFRAG} include-less blocks, ${NDEMO} error demos skipped, ${FOK} compile clean behind the prelude, 0 stale-API / reserved-word)"
