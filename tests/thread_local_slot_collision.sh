#!/bin/sh
# v6.3.25 regression: sigil's crypto-bank thread-local slot must NOT collide with
# patra's thread-local slots. cyrius's thread_local_get/set namespace is a tiny
# shared integer space (TLOCAL_MAX_SLOTS = 16, no allocator); libs hardcode slots.
# patra owns slots 0-4 (0-2 = SQL-parse scratch, TLS_SLAB_STACK=3, TLS_SLAB_TOP=4).
# sigil squatted slot 0 — so in a server linking BOTH (a TLS pool over a patra API,
# e.g. SecureYeoman's yeo-cy-test), a patra query clobbered sigil's pinned crypto
# bank; a later cbank() read patra's scratch as the bank index and pointed sigil at
# the WRONG lane of the process-global banked crypto buffers → an in-flight
# handshake's key schedule corrupted → client RECORD_LAYER_FAILURE ("every 4th
# handshake"). Fixed by moving sigil's slot to 8 (sigil 3.9.9). This gate locks it +
# guards the whole vendored namespace against re-collision on patra's 0-4 range.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

sigil_slot=$(grep -oE '_SIGIL_CBANK_SLOT = [0-9]+' "$ROOT/lib/sigil.cyr" 2>/dev/null | head -1 | grep -oE '[0-9]+$')
if [ -z "$sigil_slot" ]; then
    echo "FAIL: _SIGIL_CBANK_SLOT not found in lib/sigil.cyr"
    exit 1
fi

# patra reserves thread-local slots 0-4.
if [ "$sigil_slot" -le 4 ]; then
    echo "FAIL: sigil crypto-bank thread-local slot $sigil_slot collides with patra's reserved 0-4"
    echo "  → a patra query clobbers sigil's crypto bank → TLS RECORD_LAYER_FAILURE"
    exit 1
fi

# Must also fit the 16-slot block (0-15) so macOS/agnos (_tlocal_macos[128]) don't overflow.
if [ "$sigil_slot" -ge 16 ]; then
    echo "FAIL: sigil slot $sigil_slot >= TLOCAL_MAX_SLOTS (16) — out of bounds on macOS/agnos"
    exit 1
fi

echo "PASS: sigil crypto-bank thread-local slot ($sigil_slot) is clear of patra's 0-4 and in-bounds (v6.3.25)"
exit 0
