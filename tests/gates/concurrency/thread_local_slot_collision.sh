#!/bin/sh
# v6.4.65: sigil + patra were migrated OFF hardcoded thread-local slots onto
# cyrius's slot ALLOCATOR (thread_local_alloc). This gate replaces the v6.3.25
# "pin sigil to slot 8" check: the collision class that produced the
# RECORD_LAYER_FAILURE (a patra query clobbering sigil's crypto bank because both
# squatted overlapping hardcoded slots) is now closed STRUCTURALLY. Allocated
# slots are always >= 16 and handed out monotonically, so they can never alias
# each other or the frozen 0-15 app/legacy range. This gate guards against a
# regression that re-introduces a hardcoded low-integer slot.
# See docs/development/issues/archived/2026-07-01-thread-local-slot-namespace-no-allocator.md
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# 1. cyrius provides the allocator, based at 16 (so allocated slots clear 0-15).
if ! grep -qE '^fn thread_local_alloc\(' "$ROOT/lib/thread_local.cyr"; then
    echo "FAIL: thread_local_alloc() missing from lib/thread_local.cyr"
    exit 1
fi
if ! grep -qE '_tlocal_next_slot = 16' "$ROOT/lib/thread_local.cyr"; then
    echo "FAIL: allocator base is not 16 — allocated slots must clear the frozen 0-15 range"
    exit 1
fi

# 2. sigil must CLAIM its slot from the allocator, not hardcode a literal.
if ! grep -qE '_SIGIL_CBANK_SLOT = 0 - 1' "$ROOT/lib/sigil.cyr"; then
    echo "FAIL: sigil hardcodes _SIGIL_CBANK_SLOT instead of allocating it (re-collision risk)"
    exit 1
fi
if ! grep -qE 'thread_local_alloc\(\)' "$ROOT/lib/sigil.cyr"; then
    echo "FAIL: sigil does not call thread_local_alloc() — migration regressed"
    exit 1
fi

# 3. patra must CLAIM its five slots from the allocator too.
if ! grep -qE 'var TLS_TOKS = 0 - 1' "$ROOT/lib/patra.cyr"; then
    echo "FAIL: patra hardcodes TLS_TOKS instead of allocating it (re-collision risk)"
    exit 1
fi
if ! grep -qE 'thread_local_alloc\(\)' "$ROOT/lib/patra.cyr"; then
    echo "FAIL: patra does not call thread_local_alloc() — migration regressed"
    exit 1
fi

echo "PASS: sigil + patra claim thread-local slots from the allocator (>= 16); v6.3.25 collision class closed structurally (v6.4.65)"
exit 0
