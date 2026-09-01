#!/bin/sh
# Gate: `distlib --check` compares WHOLE bundles, not the first megabyte (v6.5.37, A6).
#
# THE DEFECT. `_distlib_files_same` read 1,048,575 bytes of each side into fixed 1 MB buffers
# and compared only that prefix, so two files both longer than the cap read back as identical
# truncated prefixes. Measured at 6.5.36 on a 1,489,948-byte bundle:
#
#     byte flipped @   500,000  ->  STALE     (caught)
#     byte flipped @ 1,200,000  ->  current   (MISSED, exit 0)
#     truncated to 1,048,575    ->  current   (MISSED — 441 KB silently dropped)
#
# ⚠ SIX ECOSYSTEM BUNDLES ARE ALREADY PAST THE CAP: agnosai 1,606,588 · drishti 1,403,806 ·
# mabda 1,304,858 · shravan 1,263,123 · avatara 1,163,428 · sigil 1,105,848. `--check` was a
# partial compare on every one of them.
#
# ⭐ WHY THAT MATTERS MORE THAN A NORMAL OFF-BY-ONE: this IS the gate written to prevent a
# repeat of the sankoch 2.7.6 incident, where a source fix reached the main bundle and none
# of the nine profiles, and every profile looked fresh because only the version string was
# compared. v6.5.8's own comment says content comparison "is the only thing that answers
# 'was this bundle regenerated'". A prefix compare does not answer it — it answers a question
# about the first megabyte and reports it as the whole answer.
#
# ⛔ THE FLIP MUST BE PAST 1,048,575. A test that flips an early byte passes against the
# defective build and proves nothing; axis 2 is the only axis that fails against it. Axis 3
# (truncation) is separate because a size-only fix catches it while a prefix-only compare
# does not — the two failures have different shapes.
#
# ⚠ The bundle is built from THREE modules, not one: there is a separate, correct, 1024 KB
# per-MODULE read cap that fails loudly ("module exceeds 1024KB read cap"), so a single large
# module cannot produce a large bundle. That cap is not the defect under test.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
VER=$(cat "$ROOT/VERSION")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_check_full_compare: $1"; exit 1; }

mkdir -p "$WORK/p/src"
# Build one ~1000-line block ONCE, then concatenate it — a per-line shell loop over 12,000
# lines cost ~12s of the gate's runtime, which is not a cost this assertion is worth.
BLOCK="$WORK/block.txt"
: > "$BLOCK"
j=0
while [ "$j" -lt 1000 ]; do
    printf '# %s\nfn blk_%s(): i64 { return %s; }\n' \
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
        "$j" "$j" >> "$BLOCK"
    j=$((j + 1))
done
i=0
while [ "$i" -lt 3 ]; do
    # Each module gets its own fn names (the bundle must compile), so the block is rewritten
    # with a per-module prefix rather than repeated verbatim.
    sed "s/fn blk_/fn m${i}_/" "$BLOCK" >  "$WORK/p/src/m$i.cyr"
    sed "s/fn blk_/fn n${i}_/" "$BLOCK" >> "$WORK/p/src/m$i.cyr"
    sed "s/fn blk_/fn o${i}_/" "$BLOCK" >> "$WORK/p/src/m$i.cyr"
    sed "s/fn blk_/fn q${i}_/" "$BLOCK" >> "$WORK/p/src/m$i.cyr"
    i=$((i + 1))
done
cat > "$WORK/p/cyrius.cyml" <<EOF
[package]
name = "a6probe"
version = "0.1.0"
cyrius = "$VER"
[lib]
modules = ["src/m0.cyr", "src/m1.cyr", "src/m2.cyr"]
[deps]
stdlib = ["alloc"]
EOF

# CYRIUS_RESOLVED=1: a fixture pinning another version would re-exec an older binary.
run() { ( cd "$WORK/p" && CYRIUS_RESOLVED=1 "$CYRIUS" "$@" 2>&1 ); }

run distlib >/dev/null 2>&1 || true
B="$WORK/p/dist/a6probe.cyr"
[ -f "$B" ] || fail "no bundle produced"
SZ=$(wc -c < "$B" | tr -d ' ')
[ "$SZ" -gt 1048576 ] || fail "fixture premise: bundle is only $SZ bytes, needs > 1048576 to exercise the cap"
cp "$B" "$WORK/pristine.cyr"

flip_at() {  # flip one byte at offset $1, return the verdict word
    cp "$WORK/pristine.cyr" "$B"
    printf 'Z' | dd of="$B" bs=1 seek="$1" count=1 conv=notrunc status=none 2>/dev/null
    run distlib --check | grep -oE 'STALE|current' | head -1
}

# ── axis 1: a byte inside the first megabyte is caught (premise check) ──────────────
V1=$(flip_at 500000)
[ "$V1" = "STALE" ] || fail "axis 1: a flip at 500,000 reported '$V1' — --check is not detecting drift at all"

# ── axis 2: THE DEFECT — a byte PAST the 1 MB cap must also be caught ───────────────
V2=$(flip_at 1200000)
[ "$V2" = "STALE" ] || fail "axis 2: a flip at 1,200,000 reported '$V2' — only the first megabyte is being compared"

# ── axis 3: truncation to exactly the old cap must be caught ───────────────────────
cp "$WORK/pristine.cyr" "$B"
head -c 1048575 "$WORK/pristine.cyr" > "$B"
V3=$(run distlib --check | grep -oE 'STALE|current' | head -1)
[ "$V3" = "STALE" ] || fail "axis 3: a bundle truncated to 1,048,575 bytes reported '$V3'"

# ── axis 4: ANTI-VACUOUS — an unmodified bundle reports current ─────────────────────
# Without this, reporting STALE unconditionally passes axes 1-3.
cp "$WORK/pristine.cyr" "$B"
V4=$(run distlib --check | grep -oE 'STALE|current' | head -1)
[ "$V4" = "current" ] || fail "axis 4: an UNMODIFIED bundle reported '$V4' — --check now fails on correct bundles"

echo "PASS: distlib_check_full_compare (drift caught before and after 1 MB, truncation caught, clean bundle still current)"
