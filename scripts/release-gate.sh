#!/bin/sh
# scripts/release-gate.sh — THE consolidated pre-tag release gate.
#
# Run this and get GREEN before EVERY `.NN` version-bump + tag + handoff. It is the
# SINGLE source of truth for "what must pass before a release", so no individual gate
# gets run à la carte and skipped.
#
# Why this exists: the v6.3.0 seed break (2026-06-28). A compiler change passed the
# cycc self-host fixpoint + check.sh + cross-OS, so it looked release-ready — but
# `seed-derive-cycc.sh` was NOT run (it had only ever been framed as a minor/major
# *closeout* check). The change broke the seed -> cybs -> cycc chain; CI caught it,
# not us. KEY LESSON, baked in here: **the cycc self-host fixpoint does NOT cover the
# seed chain.** cybs (the hand-assembly bootstrap compiler the seed assembles) is far
# more limited than build/cycc and fails SILENTLY on things build/cycc compiles fine.
# So seed-derive is its own mandatory gate, EVERY release, for ANY src/ change.
# See: feedback_seed_derive_mandatory_cybs_limits.
#
# Gates (fail-fast — stops at the first RED):
#   1. self-host fixpoint   build/cycc reproduces itself + == cycc(src)
#   2. SEED DERIVE          seed -> cybs -> cycc byte-identical          [the critical one]
#   3. check.sh             all gates green
#   4. cross-OS self-host   ecb (macOS) + cass (Windows) + pi (aarch64), REAL hardware
#   5. bench                record self_compile + cycc size              (non-blocking)
#
# Usage:
#   sh scripts/release-gate.sh            full gate (run before tag/handoff)
#   sh scripts/release-gate.sh --quick    steps 1-3 only (LOCAL ITERATION — NOT release-ready)

cd "$(dirname "$0")/.." || exit 2
QUICK=0
[ "$1" = "--quick" ] && QUICK=1

T=$(mktemp -d)
fail() {
    echo ""
    echo "================================================================"
    echo "RELEASE GATE: RED — $1"
    echo "Do NOT version-bump / tag / hand off until this is GREEN."
    echo "================================================================"
    rm -rf "$T"
    exit 1
}
step() { echo ""; echo "=== [$1] $2 ==="; }

chmod +x bootstrap/asm build/cycc 2>/dev/null

# 1. self-host fixpoint -------------------------------------------------------
step "1/5" "self-host fixpoint (build/cycc reproduces itself byte-identical)"
cat src/main.cyr | ./build/cycc > "$T/g1" 2>/dev/null || fail "cycc failed to compile src/main.cyr"
chmod +x "$T/g1"
cat src/main.cyr | "$T/g1" > "$T/g2" 2>/dev/null || fail "gen1 (cycc's self-build) crashed compiling src/main.cyr"
cmp -s "$T/g1" "$T/g2" || fail "self-host fixpoint broken (gen1 != gen2)"
cmp -s "$T/g1" build/cycc || fail "build/cycc is NOT cycc(src) — rebuild build/cycc, it's stale or wrong"
echo "  OK: byte-identical ($(wc -c < build/cycc) B)"

# 2. SEED DERIVE — the gate v6.3.0 missed ------------------------------------
step "2/5" "seed -> cybs -> cycc derivation (the cycc fixpoint does NOT cover this)"
sh scripts/seed-derive-cycc.sh > "$T/seed.out" 2>&1
if ! grep -q "machine-derivable from the" "$T/seed.out"; then
    tail -8 "$T/seed.out"
    fail "SEED DERIVATION BROKEN — cybs cannot reproduce build/cycc from the 29KB seed. NEVER tag this."
fi
echo "  OK: build/cycc is machine-derivable from the seed"

# 3. check.sh -----------------------------------------------------------------
step "3/5" "check.sh (full gate suite)"
sh scripts/check.sh > "$T/check.out" 2>&1
LINE=$(grep -E "passed, [0-9]+ failed" "$T/check.out" | tail -1)
echo "  $LINE"
echo "$LINE" | grep -q ", 0 failed" || { tail -8 "$T/check.out"; fail "check.sh has failures"; }

if [ "$QUICK" = "1" ]; then
    rm -rf "$T"
    echo ""
    echo "RELEASE GATE: --quick PASSED steps 1-3."
    echo "*** NOT RELEASE-READY *** — cross-OS (4) + bench (5) were SKIPPED."
    echo "Run without --quick before version-bump / tag / handoff."
    exit 0
fi

# 4. cross-OS self-host + VR-01 platform LIBTEST (SEQUENTIAL — fixed /tmp+_cyaud
# paths clobber if concurrent). v6.3.43: the `vr01_` glob promotes LIBTEST from an
# opt-in fallback to a STANDING per-host gate — the 8 platform-variant tcyr
# (fs/thread/sync/alloc/args/process/syscalls on cass+ecb) run on real hardware every
# release, so macOS/Windows stdlib rot is caught here, not by ports.
step "4/5" "cross-OS self-host + VR-01 platform tcyr: ecb (macOS) + cass (Windows) + pi (aarch64) — REAL hardware"
for H in ecb cass pi; do
    echo "  --- $H ---"
    sh scripts/cross-os-selfhost.sh "$H" "vr01_" > "$T/co.out" 2>&1
    if ! grep -q "SELFHOST_OK: $H" "$T/co.out"; then
        tail -8 "$T/co.out"
        fail "cross-OS self-host FAILED on $H (a green CI check is NOT this — run the compiler on the hardware)"
    fi
    if ! grep -q "LIBTEST_OK: $H" "$T/co.out"; then
        tail -8 "$T/co.out"
        fail "VR-01 platform tcyr FAILED on $H (found-by-ports stdlib rot — see the failing vr01_ test)"
    fi
    echo "  OK: $H SELFHOST_OK + VR-01 LIBTEST_OK"
done

# 5. bench (non-blocking — record the delta, triage per the growth-tax rule) ---
step "5/5" "bench (self_compile + cycc size — record in CHANGELOG; non-blocking)"
sh scripts/bench-history.sh 2>&1 | grep -iE "self_compile|size/cycc" | head || echo "  (bench ran)"

rm -rf "$T"
echo ""
echo "================================================================"
echo "RELEASE GATE: GREEN — safe to version-bump + tag + hand off."
echo "  Record the bench self_compile + cycc-size delta in the CHANGELOG."
echo "================================================================"
