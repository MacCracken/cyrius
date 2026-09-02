#!/bin/sh
# Gate: the stdlib hashes are SEEDED per process, so an offline-precomputed collision set
# cannot flood a map (v6.5.39).
#
# THE DEFECT (filed 2026-08-30). Every stdlib hash was a published constant with no
# per-process state, and the bucket index is the LOW bits of it (`idx = hash & (cap - 1)`,
# power-of-2 capacity, linear probing). So an attacker who can choose keys computes a
# colliding set ONCE, offline, from the published constants, and reuses it against every
# cyrius process forever. Measured on 6.5.38 with 8192 distinct 39-byte keys: cstr
# `map_set` 4.05 s colliding vs 4.34 ms distinct — **934x** — and `hash_str_v` 329x. Insert
# and every rehash-on-grow degrade to O(n^2). Consumers could not mitigate it: no public
# entry point takes a hash function.
#
# ⚠ THE FILING SCOPED IT TO TWO FUNCTIONS. It is FOUR: `hash_str` and `hash_str_v`
# (lib/hashmap.cyr), `hash_u64` (splitmix64 with fixed constants — INVERTIBLE, so preimages
# for any target bucket are computed directly with no brute force at all), and
# `_fhm_hash` (lib/hashmap_fast.cyr), which was a VERBATIM second copy the filing never
# mentioned and which floods too (N=4096: 22.4 ms colliding vs 1.16 ms distinct).
#
# ⭐ THE FIXTURE IS A REAL ATTACK, NOT A SIMULATION OF ONE. The 13 block-pairs below were
# computed OFFLINE from the published FNV-1a constants alone, with no access to any running
# process — a Joux multicollision: each pair drives the low-16 hash state to the same value,
# so all 2^13 = 8192 selections share one low-16 hash and land in ONE bucket at every
# capacity <= 2^16. That "compute once, reuse forever" property IS the vulnerability.
#
# ⛔ AXIS 2 IS THE ANTI-VACUOUS HALF AND IT CANNOT BE SKIPPED. The probe recomputes each key
# through its own verbatim UNSEEDED FNV-1a and asserts that set still collapses to exactly 1
# bucket. Without it, a fixture that quietly stopped being a collision set — a typo in the
# table, a changed key length — would score axis 1 as a PASS while testing nothing.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: hash_seed_flood_resistance: build/cycc missing"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: hash_seed_flood_resistance: $1"; exit 1; }

cat > "$WORK/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/hashmap.cyr"

# 13 pairs x 2 blocks x 3 bytes, precomputed offline from the published FNV-1a constants.
var PAIRS[78] = {
    0x6B, 0x6A, 0x61, 0x67, 0x61, 0x64,
    0x62, 0x6E, 0x61, 0x6E, 0x61, 0x64,
    0x72, 0x76, 0x61, 0x66, 0x61, 0x64,
    0x68, 0x6E, 0x61, 0x64, 0x61, 0x64,
    0x75, 0x6A, 0x61, 0x61, 0x61, 0x64,
    0x73, 0x6A, 0x61, 0x67, 0x61, 0x64,
    0x6A, 0x6A, 0x61, 0x66, 0x61, 0x64,
    0x6D, 0x6A, 0x61, 0x61, 0x61, 0x64,
    0x6D, 0x6A, 0x61, 0x61, 0x61, 0x64,
    0x6D, 0x6A, 0x61, 0x61, 0x61, 0x64,
    0x6D, 0x6A, 0x61, 0x61, 0x61, 0x64,
    0x6D, 0x6A, 0x61, 0x61, 0x61, 0x64,
    0x6D, 0x6A, 0x61, 0x61, 0x61, 0x64
};
var CAP = 16384;
var seen_lib[2048];      # 16384 bits
var seen_raw[2048];

# A verbatim copy of the UNSEEDED FNV-1a, so the probe can prove its own fixture is still a
# real collision set without depending on the library it is testing.
fn _raw_fnv(s): i64 {
    var h = 0xCBF29CE484222325;
    var hi = 0;
    while (load8(s + hi) != 0) {
        h = h ^ load8(s + hi);
        h = h * 0x100000001B3;
        hi = hi + 1;
    }
    return h;
}

fn main(): i64 {
    alloc_init();
    var key = alloc(64);
    var m = 0;
    var d_lib = 0;
    var d_raw = 0;
    while (m < 8192) {
        var i = 0;
        while (i < 13) {
            var bit = (m >> i) & 1;
            var off = i * 6 + bit * 3;
            store8(key + i * 3 + 0, load8(&PAIRS + off + 0));
            store8(key + i * 3 + 1, load8(&PAIRS + off + 1));
            store8(key + i * 3 + 2, load8(&PAIRS + off + 2));
            i = i + 1;
        }
        store8(key + 39, 0);

        var b1 = hash_str(key) & (CAP - 1);
        var w1 = b1 >> 3;
        var t1 = 1 << (b1 & 7);
        if ((load8(&seen_lib + w1) & t1) == 0) {
            store8(&seen_lib + w1, load8(&seen_lib + w1) | t1);
            d_lib = d_lib + 1;
        }
        var b2 = _raw_fnv(key) & (CAP - 1);
        var w2 = b2 >> 3;
        var t2 = 1 << (b2 & 7);
        if ((load8(&seen_raw + w2) & t2) == 0) {
            store8(&seen_raw + w2, load8(&seen_raw + w2) | t2);
            d_raw = d_raw + 1;
        }
        m = m + 1;
    }
    fmt_int(d_lib);
    syscall(1, 1, " ", 1);
    fmt_int(d_raw);
    syscall(1, 1, "\n", 1);
    return 0;
}
var ec = main();
syscall(60, 0);
EOF

( cd "$ROOT" && cat "$WORK/probe.cyr" | "$CC" > "$WORK/probe" ) 2>/dev/null \
    || fail "the flooding probe did not compile"
chmod +x "$WORK/probe"

R1=$( cd "$ROOT" && "$WORK/probe" ) || fail "the probe did not run"
R2=$( cd "$ROOT" && "$WORK/probe" ) || fail "the probe did not run a second time"
LIB1=$(echo "$R1" | awk '{print $1}'); RAW1=$(echo "$R1" | awk '{print $2}')
LIB2=$(echo "$R2" | awk '{print $1}')

# ── axis 2 first: is the fixture still a real attack set? ──────────────────────────
[ "$RAW1" = "1" ] || fail "axis 2 (anti-vacuous): the 8192 keys land in $RAW1 buckets under the UNSEEDED hash, not 1 — the fixture has stopped being a collision set, so axis 1 would pass without testing anything"

# ── axis 1: the library hash must NOT pile up ──────────────────────────────────────
# 8192 keys into 16384 uniform bins occupy ~6448 distinct buckets. Anything near 1 means the
# precomputed set still works. The floor is deliberately far below 6448 (a seeded-but-weak
# hash should still fail it) and far above the ~1-20 a working attack produces.
[ "$LIB1" -ge 4000 ] || fail "axis 1: the offline-precomputed collision set still floods — $LIB1 distinct buckets for 8192 keys (uniform would be ~6448, the unbucketed attack gives 1)"

# ── axis 3: the seed is PER PROCESS, not a fixed constant ──────────────────────────
# A hardcoded "seed" would spread the keys (passing axis 1) while remaining just as
# precomputable — the attacker simply recomputes against the new constant. Two runs of the
# same binary must disagree.
[ "$LIB1" != "$LIB2" ] || fail "axis 3: two runs of the same binary produced identical bucket counts ($LIB1) — the seed is not varying per process, so the set is still precomputable against a fixed constant"

echo "PASS: hash_seed_flood_resistance (attack set: 1 bucket unseeded -> $LIB1 / $LIB2 seeded across two processes)"
