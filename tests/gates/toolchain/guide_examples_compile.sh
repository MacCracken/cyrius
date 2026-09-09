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
# ⚖️ SCOPE, STATED HONESTLY. Only fenced blocks that DECLARE THEMSELVES COMPLETE (they contain an
# `include "lib/...`) are compiled — 18 of the guide's 105 code blocks. The rest are deliberate
# fragments referencing helpers that do not exist, and demanding they compile would produce a wall
# of false failures that nobody would keep green. Of the 18, several are ALSO illustrative
# (`f32v8_make(/* 8 lanes */)`), so this gate does NOT require them all to compile.
#
# ⭐ WHAT IT DOES REQUIRE is that none of them fails with a STALE-API error — a wrong arity, a
# deleted symbol, or a single-var bind of a pair. That is exactly the class where the doc teaches
# an API the compiler no longer has, and it is narrow enough to stay green without babysitting.
# Plus axis 2, a pure text check for the `f32_from(<int>)` shape, because that one COMPILES.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC=${CYCC_BIN:-"$ROOT/build/cycc"}
GUIDE="$ROOT/docs/guides/cyrius-guide.md"
WORK=$(mktemp -d)
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
# Keep only the blocks that declare themselves complete.
for f in "$WORK"/blk_*.cyr; do
    [ -e "$f" ] || continue
    grep -q 'include "lib/' "$f" || rm -f "$f"
done
NBLK=$(ls "$WORK"/blk_*.cyr 2>/dev/null | wc -l | tr -d ' ')

# ⚠ ANTI-VACUOUS FLOOR. If the extractor breaks — a fence-style change, an awk quirk — it yields
# zero blocks and every check below trivially passes while inspecting nothing.
[ "${NBLK:-0}" -ge 10 ] || fail "extracted only ${NBLK} self-declaring examples from the guide — the extractor is broken, so a clean result proves nothing"

# ── axis 1: no example may fail with a STALE-API error ──────────────────────────────────
STALE=""
for f in "$WORK"/blk_*.cyr; do
    "$CYCC" < "$f" > /dev/null 2>"$f.err" || true
    if grep -qE "expects [0-9]+ arguments, got [0-9]+|undefined function '(payload|tag|tagged_new)'|returns two values" "$f.err"; then
        # ⚠ The DISPLAY pattern must equal the DETECTION pattern. An earlier cut used a looser
        # one and reported "undefined function 'fmt_int'" for a failure actually triggered by an
        # arity error — a gate that misnames its own reason costs the reader the debugging time
        # the gate was supposed to save.
        echo "  ⛔ $(basename "$f" .cyr | sed 's/blk_/guide line /'): $(grep -m1 -E "expects [0-9]+ arguments, got [0-9]+|undefined function '(payload|tag|tagged_new)'|returns two values" "$f.err" | cut -c1-110)"
        STALE="$STALE $(basename "$f")"
    fi
done
[ -z "$STALE" ] || fail "the guide teaches an API the compiler no longer has:$STALE"

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

echo "PASS: guide_examples_compile (${NBLK} self-declaring examples, ${OK} compile clean, 0 stale-API, f32_from contract held)"
