#!/bin/sh
# lexid_buckets_by_content.sh — v6.5.50. LEXID's dedup index must bucket identifiers by
# CONTENT, not by length alone, so a unit full of same-length names does not degenerate.
#
# WHAT THIS PINS. LEXID (src/frontend/lex.cyr) keys its dedup chains with what used to be
# `bucket = klen` saturated at 255. Every identifier of the SAME LENGTH therefore shared one
# chain, and the per-lookup walk over that chain is exactly the O(N²) scan the index was added
# at v5.10.40 to remove — reintroduced for any realistic unit, because real code is full of
# same-length names. A 60,000-fn unit named f0..f59999 put ~50,000 entries on a single chain:
# 20.2 s to compile, against 1.0 s once the key includes content. The whole-file effect was
# 4562 ms -> 405 ms at 32,000 fns and 20168 ms -> 1005 ms at 60,000.
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND, AND THAT IS DELIBERATE. An absolute
# "must compile in under N ms" gate measures the box, not the compiler — this repo has already
# been burned by that (leaked test children flipped the release gate's 14 ns alloc tripwire RED
# and two implementers wrote the result off as "environmental load"). Both halves here are
# compiled back-to-back on the same box in the same run, so shared load cancels out.
#
# ⚠ THE TWO INPUTS MUST BE THE SAME SIZE or the ratio measures source volume instead of
# bucketing. The first cut of this gate compared 10-char names against names up to 180 chars
# and the "slow" case came out FASTER, purely because it fed 1.8 MB more source. They are now
# matched on MEAN NAME LENGTH (uniform 10, varied 6..14 averaging 10) and land within 10 bytes
# of each other — assert that, so a future edit to the generator cannot silently reintroduce
# the skew.
#
# ⚠ NO `set -e`: timings and arithmetic here are DATA.
#
# MEASURED 2026-09-04, best-of-3 each: pre-fix uniform 4547 ms / varied 997 ms = 4.56;
# post-fix 543 ms / 419 ms = 1.30. Threshold 2.5 sits about 2x from both sides.
# MUTATION PROOF: restoring `var bucket = klen; if (bucket > 255) { bucket = 255; }` as the key
# and rebuilding the host compiler takes the ratio to 4.56 and the gate goes RED.
#
# ⛔ v6.6.9 — THAT ROW WAS BLIND TO THE KEY IT WAS MEANT TO GUARD. The v6.5.50 key sampled only
# the length and the first, middle and last byte, so it degenerated on GENERATED names too: this
# gate's own "uniform" fixture (f%09d) landed in 20 buckets of 16384 and its "varied" one in
# 380, and a ratio of two degenerate distributions read 1.30 — GREEN, a check sharing the defect
# it checks. Row 2 compares the SAME uniform fixture against a CONTROL of the same size and the
# same name length whose names are random in every byte (so any key that reads content spreads
# them, the sampled one included), and it reads the LEX phase from CYRIUS_PROF rather than the
# wall clock, because the registration work every fn pays is the same for both and hides the
# lexer. Row 1 still catches `bucket = klen` (the control is all one length, so row 2 cannot).
# MEASURED 2026-09-28, best-of-3 lex ms: sampled key uniform 268 / control 25 = 10.7x;
# FNV-1a over every byte 24 / 25 = 0.96x. Limit 3.0x.
# MUTATION PROOF (row 2): restoring the v6.5.50 sampled key in lex.cyr and rebuilding -> RED
# ("uniform-name lex 268ms vs control 25ms").
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
# ⛔ v6.6.6 — CHECK THE TEMP DIR. With an unusable TMPDIR `mktemp -d` printed nothing, the
# fixture writer below joined "" + "uni.cyr" and wrote BOTH 20000-fn fixtures into the repo
# root (cwd), then the timing read "/uni.cyr", compiled nothing twice and PASSED ("1ms vs 1ms").
# Measured with TMPDIR at a missing and at a read-only dir. CHANGELOG [6.6.6]
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: lexid_buckets_by_content: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC=${CYCC:-"$ROOT/build/cycc"}

python3 - "$D" <<'PY' || { echo "FAIL: lexid_buckets_by_content: could not write the fixtures under $D"; exit 1; }
import sys, os
d = sys.argv[1]; n = 20000
uni = ['fn f%09d(): i64 { return %d; }' % (i, i % 97) for i in range(n)]
var = []
for i in range(n):
    L = 6 + (i % 9)                      # lengths 6..14, mean 10 — same as uniform
    var.append('fn f%s(): i64 { return %d; }' % (str(i).zfill(L - 1), i % 97))
# v6.6.9 row 2's control: same count, same name length (10), every byte random.
import random
rnd = random.Random(669)
A = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
B = A + '0123456789'
seen = set(); ctl = []
while len(ctl) < n:
    nm = rnd.choice(A) + ''.join(rnd.choice(B) for _ in range(9))
    if nm in seen: continue
    seen.add(nm); ctl.append('fn %s(): i64 { return %d; }' % (nm, len(ctl) % 97))
for nm, body in (('uni', uni), ('var', var), ('ctl', ctl)):
    open(os.path.join(d, nm + '.cyr'), 'w').write(
        'object;\n' + '\n'.join(body) + '\nfn main(): i64 { return 42; }\n')
PY

SU=$(wc -c < "$D/uni.cyr"); SV=$(wc -c < "$D/var.cyr")
DIFF=$(( SU > SV ? SU - SV : SV - SU ))
if [ "$DIFF" -gt 64 ]; then
    echo "FAIL: the two fixtures differ by $DIFF bytes ($SU vs $SV) — the ratio would measure source volume, not bucketing"
    exit 1
fi

best() {  # best-of-3 wall ms for compiling $1
    b=99999999
    for _ in 1 2 3; do
        s=$(date +%s%N); "$CC" < "$1" > /dev/null 2>&1; e=$(( ($(date +%s%N) - s) / 1000000 ))
        [ "$e" -lt "$b" ] && b=$e
    done
    echo "$b"
}
TU=$(best "$D/uni.cyr")
TV=$(best "$D/var.cyr")
[ "$TV" -lt 1 ] && TV=1
R10=$(( TU * 10 / TV ))

if [ "$R10" -gt 25 ]; then
    echo "FAIL: same-length identifiers cost ${R10}/10x varied-length ones (uniform ${TU}ms vs varied ${TV}ms, limit 2.5x)"
    echo "FAIL: LEXID is bucketing by length alone — the dedup chain has degenerated to a linear scan"
    exit 1
fi
echo "  ok: uniform-length ${TU}ms vs varied-length ${TV}ms — ratio ${R10}/10 (limit 2.5)"

# ── row 2 (v6.6.9): the key reads EVERY byte, not a sample ───────────────────────────────
SC=$(wc -c < "$D/ctl.cyr")
if [ "$SC" -ne "$SU" ]; then
    echo "FAIL: the control fixture is $SC bytes, the uniform one $SU — row 2 would measure source volume"
    exit 1
fi
lexbest() {  # best-of-3 LEX-phase ms (CYRIUS_PROF) for compiling $1; -1 when unreadable
    b=99999999
    for _ in 1 2 3; do
        l=$(CYRIUS_PROF=1 "$CC" < "$1" 2>&1 > /dev/null | sed -n 's/.*[( ]lex=\([0-9]*\).*/\1/p' | head -1)
        [ -n "$l" ] || { echo -1; return; }
        [ "$l" -lt "$b" ] && b=$l
    done
    echo "$b"
}
LU=$(lexbest "$D/uni.cyr")
LC=$(lexbest "$D/ctl.cyr")
if [ "$LU" -lt 0 ] || [ "$LC" -lt 0 ]; then
    echo "FAIL: CYRIUS_PROF printed no lex= phase — row 2 cannot measure the lexer"
    exit 1
fi
if ! "$CC" < "$D/ctl.cyr" > /dev/null 2>&1; then
    echo "FAIL: the control fixture does not compile — row 2 would time an error path"
    exit 1
fi
[ "$LC" -lt 1 ] && LC=1
L10=$(( LU * 10 / LC ))
if [ "$L10" -gt 30 ]; then
    echo "FAIL: uniform-name lex ${LU}ms vs control ${LC}ms — ratio ${L10}/10 (limit 3.0)"
    echo "FAIL: LEXID's bucket key samples the name instead of hashing every byte — generated names pile onto a few chains"
    exit 1
fi
echo "  ok: uniform-name lex ${LU}ms vs random-name control ${LC}ms — ratio ${L10}/10 (limit 3.0)"
echo "PASS lexid_buckets_by_content (identifier dedup buckets on every byte of content)"
