#!/bin/sh
# preprocessor_scratch_bounds.sh — v6.5.45 (CVE-39, CVE-40)
#
# ⛔ TWO SOURCE-FED WRITE LOOPS WROTE PAST THEIR SCRATCH REGIONS, BOTH SILENTLY.
#
# CVE-39 — include/#ref filename capture. The heap map declared `0x190400 include_fname [4096]`
# and all three capture loops guarded at 4095 FROM THAT NUMBER. But two live things sit inside
# that declared span: PP_EXPAND's output-cursor return slot at S+0x190700 (768 B in) and the
# `#ifdef` FEATURE-FLAG TABLE at S+0x190800 (1024 B in). MEASURED at v6.5.45 with a pre-fix
# compiler: a 1210-character include path makes `#ifdef CYRIUS_ARCH_X86` select the WRONG BRANCH
# — the probe returns 7 where 42 is correct, exit 0, no diagnostic. A path LENGTH changed the
# generated code.
# ⚠ 768 IS THE BOUND, NOT 1024. The first cut of this fix used 1024, reasoning from the flag
# table alone and missing the cursor slot 256 bytes below it. That is why this gate derives the
# bound from the live writes rather than from any comment.
#
# CVE-40 — `#define` body copy into the macro text pool at S+0x193000. The loop ran to
# end-of-line with no check on the length OR on the ACCUMULATING write position, so a long body
# — or enough ordinary ones in sequence — walked out of the pool into live compiler state.
#
# PROPERTY: every one of these loops is bounded, and bounded by the space that is ACTUALLY free.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PP="$ROOT/src/frontend/lex_pp.cyr"
MAIN="$ROOT/src/main.cyr"
fail() { echo "FAIL preprocessor_scratch_bounds: $1" >&2; exit 1; }

# ── axis 1: the include_fname bound equals the distance to the first LIVE writer above it ──
# Derived, never quoted: grep the real store/load addresses in that band and take the lowest.
BASE=$((0x190400))
# ⚠ COMMENTS ARE STRIPPED FIRST, and this gate's own first run is why. src/frontend/lex_pp.cyr
# carries a v6.4.81 note explaining that the heap map once documented a phantom scratch at
# 0x190500 "an address NO code has ever written" — and the unfiltered grep read that sentence as
# a live writer, computed a 256-byte span, and failed a correct bound. Reading a number out of
# prose is the same defect the note itself is about.
NEXT=$(sed 's/#.*//' "$PP" \
       | grep -oE '0x1904[0-9A-Fa-f]{2}|0x1905[0-9A-Fa-f]{2}|0x1906[0-9A-Fa-f]{2}|0x1907[0-9A-Fa-f]{2}' \
       | sort -u | while read a; do printf '%d\n' "$a"; done | sort -n | awk -v b="$BASE" '$1>b{print $1; exit}')
[ -n "$NEXT" ] || fail "found no live writer above include_fname in 0x190400..0x190800 — the gate is reading nothing (that band is where PP_EXPAND's cursor slot lives)"
USABLE=$((NEXT - BASE))
GUARDS=$(grep -oE '\(r?fi >= [0-9]+\) \{ PP_FNAME_TOO_LONG' "$PP" | grep -oE '[0-9]+' | sort -u)
[ "$(printf '%s\n' "$GUARDS" | grep -c .)" -eq 1 ] \
    || fail "the three filename capture loops disagree on their bound ($(printf '%s' "$GUARDS" | tr '\n' ' ')) — one of them is the hole"
[ "$GUARDS" -lt "$USABLE" ] \
    || fail "filename capture is bounded at $GUARDS but only $USABLE bytes are free above 0x190400 (next live writer at $(printf '0x%X' $NEXT)) — a long path corrupts it silently"
NG=$(grep -cE '\(r?fi >= [0-9]+\) \{ PP_FNAME_TOO_LONG' "$PP")
[ "$NG" -eq 3 ] || fail "expected 3 guarded filename capture loops, found $NG — CVE-32 bounded three and a fourth would be unguarded"

# ── axis 2: the macro body copy is bounded, and on the ACCUMULATING position ──────────
grep -q 'PP_MACRO_TEXT_FULL' "$PP" || fail "the #define body copy has no overflow guard (CVE-40)"
sed -n '/var mdst = S + 0x193000/,/^ *}/p' "$PP" | grep -q '_pp_macro_text_pos + mlen + 1 >= mcap' \
    || fail "the #define body guard does not test the ACCUMULATING write position — bounding this macro's length alone still overruns on the sixteenth #define"

# ── axis 3: the map declares what is really there ─────────────────────────────────────
# A map that overstates a region is what set the 4095 guard in the first place.
grep -qE '^#   0x190400  include_fname \[768\]' "$MAIN" \
    || fail "the heap map does not declare include_fname as [768] — an overstated size is exactly how the 4095 guard was chosen"
grep -q '0x190700  pp_expand_outpos' "$MAIN" \
    || fail "the heap map does not declare the PP_EXPAND cursor slot at 0x190700 — the next reader re-derives the 768 the hard way, or gets it wrong"

echo "PASS preprocessor_scratch_bounds (filename capture bounded at $GUARDS of $USABLE free bytes across 3 loops; #define body bounded on the accumulating position; map declares both)"
