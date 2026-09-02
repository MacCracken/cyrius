#!/bin/sh
# Gate: the raised source-size ceiling holds end to end, and the paired caps stay equal
# (v6.5.40).
#
# THE DEFECT. `preprocess_out` was a fixed 8 MB arena slot and exceeding it was a HARD build
# failure with no flag, no env var and no manifest key. A project that hit it had exactly one
# move: make its source smaller — which in practice meant hand-vendoring a subset of its
# dependencies rather than declaring them. thoth was at ~96 % of the cap before adding
# anything, and a dozen sibling repos measure 8-12 MB.
#
# ⭐ RAISING IT EXPOSED FOUR MORE CAPS, EACH OF WHICH BECAME THE NEXT WALL. This is the whole
# reason the release is dedicated to the cascade rather than to the filed bug alone:
#   8 MB preprocess_out  ->  1,048,576 tokens (hit at ~12 MB of realistic source)
#                        ->  512 KB identifier pool (thoth alone needs ~798 KB)
#                        ->  32,768 functions (hit at ~12 MB)
#                        ->  65,536 identifier-dedup entries (hit at ~23 MB)
# Fixing only the filed one would have moved the usable ceiling from 8 MB to about 10-11 MB —
# a ~30 % gain reported as a 3x one. Axis 1 is an END-TO-END compile precisely so it measures
# the ceiling a consumer actually experiences, not any single constant.
#
# ⚠ AXIS 2 IS A CORRECTNESS INVARIANT, NOT TIDINESS. `PP_REF_PASS` copies its expanded output
# from `preprocess_out` back into `_SRCB`. If the preprocess cap ever exceeds `_SRC_CAP`, that
# copy runs off the end of the input buffer — and since input_buf now sits at the arena top,
# off the end of the arena. The two caps must stay equal.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: preprocess_arena_caps: build/cycc missing"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: preprocess_arena_caps: $1"; exit 1; }

# ── axis 2 first (cheap, and it constrains axis 1's meaning) ───────────────────────
SRC_CAP=$(grep -E '^var _SRC_CAP = [0-9]+;' "$ROOT/src/common/util.cyr" | grep -oE '[0-9]+' | head -1)
# ⚠ Take the MAXIMUM, not the first: `if (op > 0)` is an unrelated emptiness test in the same
# file, and a lexical `sort -u | head -1` picks it, yielding a cap of 0 that fails the gate for
# the wrong reason. (It did exactly that on this gate's first run.)
PP_CAP=$(grep -oE 'if \(op > [0-9]+\) \{' "$ROOT/src/frontend/lex_pp.cyr" | grep -oE '[0-9]+' | sort -n | tail -1)
[ -n "$SRC_CAP" ] || fail "axis 2: could not read _SRC_CAP from src/common/util.cyr"
[ -n "$PP_CAP" ]  || fail "axis 2: could not read the preprocess_out cap from src/frontend/lex_pp.cyr"
[ "$SRC_CAP" = "$PP_CAP" ] \
    || fail "axis 2: _SRC_CAP ($SRC_CAP) != preprocess_out cap ($PP_CAP) — PP_REF_PASS copies expanded output from preprocess_out back into _SRCB, so a larger preprocess cap overruns the input buffer and, since it now sits at the arena top, the arena"

# ── axis 3: the cap is actually ABOVE the old ceiling ──────────────────────────────
# Guards against someone "fixing" a future overflow by lowering the cap back down.
[ "$PP_CAP" -gt 8388608 ] || fail "axis 3: the preprocess cap is $PP_CAP, back at or below the old 8 MB ceiling this release exists to raise"

# ── axis 1: END-TO-END — a source past the old ceiling compiles AND runs correctly ──
# ⚠ Deliberately generated at REALISTIC density (~45 % comment, reused identifier vocabulary),
# because a token-dense synthetic hits the token cap first and a unique-identifier synthetic
# hits the pool first — both would report a failure that has nothing to do with what a real
# consumer would experience. It must also RUN and return the right answer: a ceiling raise that
# compiles garbage is worse than the hard error it replaced.
python3 - "$WORK/big.cyr" <<'PY'
import sys
out=['include "lib/syscalls.cyr"\n']; n=0; i=0
while n < 9*1024*1024:
    blk=(f'# helper {i} — house-style comment block carrying the WHY-invariant and a version\n'
         f'# pointer; roughly 45 % of real stdlib bytes are comment rather than code, and the\n'
         f'# identifiers below come from a small reused vocabulary, as in real source.\n'
         f'fn _cap_fn_{i}(alpha, beta): i64 {{\n'
         f'    var acc = alpha + beta;\n    var scaled = acc * 3;\n    var out = scaled - alpha;\n    return out;\n}}\n\n')
    out.append(blk); n+=len(blk); i+=1
out.append('fn main(): i64 { return _cap_fn_0(1, 2) - 5; }\nvar ec = main();\nsyscall(60, ec);\n')
open(sys.argv[1],'w').write(''.join(out))
PY
BYTES=$(wc -c < "$WORK/big.cyr")
[ "$BYTES" -gt 8388608 ] || fail "axis 1 anti-vacuous: the probe is only $BYTES bytes, not past the old 8 MB ceiling — it would pass without testing anything"

set +e
( cd "$ROOT" && "$CC" < "$WORK/big.cyr" > "$WORK/big.bin" ) 2> "$WORK/big.err"; RC=$?
set -e
[ "$RC" -eq 0 ] || fail "axis 1: a ${BYTES}-byte source (past the old 8 MB ceiling) did not compile: $(head -1 "$WORK/big.err")"
chmod +x "$WORK/big.bin"
set +e
( cd "$ROOT" && "$WORK/big.bin" ); AR=$?
set -e
[ "$AR" -eq 3 ] || fail "axis 1: the ${BYTES}-byte source compiled but produced the WRONG ANSWER (exit $AR, expected 3) — a raised ceiling that miscompiles is worse than the hard error it replaced"

echo "PASS: preprocess_arena_caps (caps paired at $PP_CAP; a $BYTES-byte source compiles and runs correctly, past the old 8388608 ceiling)"
