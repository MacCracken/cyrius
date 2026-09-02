#!/bin/sh
# Gate: the serial thread peers' TLS save-window covers the FULL slot range (v6.5.39).
#
# THE DEFECT. macOS and agnos have no real thread path, so `thread_create` runs the body
# INLINE and emulates thread-local isolation by hand: snapshot the caller's slots, zero them
# for the body, restore afterwards. Both peers snapshotted only the first **16** slots while
# `TLOCAL_MAX_SLOTS` is **128** — so a body's write to any slot >= 16 leaked straight back
# into the caller, which is precisely what that code exists to prevent. Slots 16-127 are the
# range `thread_local_alloc()` hands out, i.e. every library added since v6.4.65: sigil's
# crypto bank, patra's SQL scratch. Four vendored stdlibs are live consumers.
#
# ⚠ THE STALE VALUE WAS DOCUMENTED AS CORRECT, which is why reading the code did not catch
# it: both peers carried `# TLOCAL_MAX_SLOTS (16)` in their headers, and `thread_local.cyr`'s
# own slot-range comment said "16 slots" too, while the constant beneath it said 128 and the
# backing arrays were `[128]`. Three comments agreeing with each other and disagreeing with
# the code.
#
# ⛔ WHY THIS GATE EXISTS RATHER THAN AN ASSERTION IN THE SOURCE. The save buffer's size must
# be a LITERAL — `#assert` accepts only numbers and `sizeof()`, not a global (verified: it
# reports "expected number or sizeof()" on a global constant) — so `var save: i64[128]`
# necessarily duplicates `TLOCAL_MAX_SLOTS`. A hand-maintained copy of a derivable fact is the
# exact shape this cycle keeps finding wrong (heap-map sizes vs regions, gate counts vs files,
# declared string lengths vs strings). This gate is the mechanical check that makes the
# duplicate safe: raise the constant past the literal and the build goes red here.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: tls_window_matches_max_slots: $1"; exit 1; }

MAX=$(grep -E '^var TLOCAL_MAX_SLOTS = [0-9]+;' "$ROOT/lib/thread_local.cyr" | grep -oE '[0-9]+' | head -1)
[ -n "$MAX" ] || fail "could not read TLOCAL_MAX_SLOTS from lib/thread_local.cyr — the gate is blind, not the code clean"
[ "$MAX" -gt 0 ] || fail "TLOCAL_MAX_SLOTS parsed as '$MAX'"

for f in lib/thread_macos.cyr lib/thread_agnos.cyr; do
    # ── axis 1: the save buffer is at least as large as the slot range ─────────────
    # ⚠ Extract the BRACKETED number, not "the first number on the line": a naive
    # `grep -oE '[0-9]+'` yields 64 first — out of the TYPE NAME `i64` — and silently
    # compares the wrong value. Caught by this gate failing loudly on its own first run.
    SZ=$(grep -oE 'var save: i64\[[0-9]+\];' "$ROOT/$f" | sed -E 's/.*\[([0-9]+)\].*/\1/' | head -1)
    [ -n "$SZ" ] || fail "$f: no 'var save: i64[N];' found — the serial TLS snapshot buffer moved or was renamed"
    [ "$SZ" -ge "$MAX" ] \
        || fail "$f: the TLS snapshot buffer is i64[$SZ] but TLOCAL_MAX_SLOTS is $MAX — the save loop would write $((MAX - SZ)) slots PAST the end of the buffer"

    # ── axis 2: the loops are bounded by the CONSTANT, never a literal ─────────────
    # This is the half that actually broke. A literal bound silently under-copies instead of
    # overflowing, so it produces wrong data rather than a crash — invisible to axis 1.
    LOOPS=$(grep -cE 'while \(i < TLOCAL_MAX_SLOTS\) \{' "$ROOT/$f" || true)
    [ "$LOOPS" -eq 2 ] \
        || fail "$f: expected 2 loops bounded by TLOCAL_MAX_SLOTS (save + restore), found $LOOPS — a literal bound here under-copies silently and leaks the caller's high slots"
done

# ── axis 3: the backing arrays cover the range too ─────────────────────────────────
# If the storage were smaller than the constant, the (now correct) loops would run off the
# end of the process-global array instead.
for pair in "_tlocal_macos:lib/thread_local.cyr" "_tlocal_agnos:lib/thread_local.cyr"; do
    NAME=${pair%%:*}; FILE=${pair#*:}
    N=$(grep -oE "var ${NAME}\[[0-9]+\];" "$ROOT/$FILE" | sed -E 's/.*\[([0-9]+)\].*/\1/' | head -1)
    [ -n "$N" ] || fail "$FILE: could not find the '$NAME[N]' backing array"
    [ "$N" -ge "$MAX" ] \
        || fail "$FILE: $NAME is [$N] but TLOCAL_MAX_SLOTS is $MAX — slot stores past $((N - 1)) run off the end of the process-global array"
done

echo "PASS: tls_window_matches_max_slots (TLOCAL_MAX_SLOTS=$MAX; both serial peers save the full range and are bounded by the constant)"
