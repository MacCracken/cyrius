#!/bin/sh
# Gate: the serial thread peers' TLS save-window covers the FULL slot range (v6.5.39).
#
# THE DEFECT. A serial peer (agnos today; x86 macOS until 6.6.19) has no real thread path, so
# `thread_create` runs the body INLINE and emulates thread-local isolation by hand: snapshot the caller's slots, zero them
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
# ⛔ WHY THIS GATE EXISTS. Until 6.7.2 an array size had to be a LITERAL (`#assert` took only
# numbers and `sizeof()`, not a global), so `var save: i64[128]` and the `[128]` backing arrays
# necessarily duplicated `TLOCAL_MAX_SLOTS` — a hand-maintained copy of a derivable fact, the
# shape this cycle keeps finding wrong (heap-map sizes vs regions, gate counts vs files,
# declared string lengths vs strings), and this gate compared the copies. 6.7.2 made an array
# size a const context, so since 6.7.6 there is ONE fact: `const _TLOCAL_MAX_SLOTS` sizes the
# save buffer, every backing array, the Windows per-thread block and the x86-macOS TLS header,
# and the public `var TLOCAL_MAX_SLOTS` (kept for the API) is initialised from it. The gate now
# pins that shape: a literal size anywhere, or a public var that stops deriving from the const,
# is RED. Mutation ledger (6.7.6, each RED in a scratch copy): the save buffer back to
# `i64[128]`; `_tlocal_fallback[128]`; `var TLOCAL_MAX_SLOTS = 128;`; the Windows block back to
# `alloc(1024)`; `_THR_HDR = 1040`.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: tls_window_matches_max_slots: $1"; exit 1; }

MAX=$(grep -E '^const _TLOCAL_MAX_SLOTS = [0-9]+;' "$ROOT/lib/thread_local.cyr" | grep -oE '[0-9]+' | head -1)
[ -n "$MAX" ] || fail "could not read 'const _TLOCAL_MAX_SLOTS = N;' from lib/thread_local.cyr — the gate is blind, not the code clean"
[ "$MAX" -gt 0 ] || fail "_TLOCAL_MAX_SLOTS parsed as '$MAX'"
# ── axis 0 (6.7.6): the public var IS the const, not a second copy of the number ─────────
grep -qE '^var TLOCAL_MAX_SLOTS = _TLOCAL_MAX_SLOTS;' "$ROOT/lib/thread_local.cyr" \
    || fail "lib/thread_local.cyr: 'var TLOCAL_MAX_SLOTS = _TLOCAL_MAX_SLOTS;' is gone — a literal there is a second copy of the slot count, and the loops bounded by the var would drift from the buffers sized by the const"

for f in lib/thread_agnos.cyr; do
    # ── axis 1: the save buffer is sized by the const (6.7.6; it was a literal 128) ──
    grep -qE 'var save: i64\[_TLOCAL_MAX_SLOTS\];' "$ROOT/$f" \
        || fail "$f: no 'var save: i64[_TLOCAL_MAX_SLOTS];' — the serial TLS snapshot buffer is sized by something other than the const (a literal is a hand-kept copy of the slot count), or it moved"
    grep -qE 'var save: i64\[[0-9]+\];' "$ROOT/$f" \
        && fail "$f: a literal-sized 'var save: i64[N];' is back — size it by _TLOCAL_MAX_SLOTS"

    # ── axis 2: the loops are bounded by the CONSTANT, never a literal ─────────────
    # This is the half that actually broke. A literal bound silently under-copies instead of
    # overflowing, so it produces wrong data rather than a crash — invisible to axis 1.
    # ⚠ v6.5.44: this asserted `-eq 2` — the MECHANISM (save + restore, and nothing else)
    # rather than the PROPERTY (no TLS loop is bounded by a literal). Band J phase 2 adds a
    # THIRD correctly-bounded loop to lib/thread_macos.cyr — zeroing a fresh per-thread block
    # for a real Darwin thread — and the gate went red on a change that strengthens exactly
    # what it protects. A gate that pins the mechanism fails good changes and, worse, passes
    # bad ones that keep the shape (v6.5.36's enum gate stayed green through five bad releases
    # for precisely this reason). So: at least the save+restore pair, and ZERO literal bounds.
    LOOPS=$(grep -cE 'while \(i < TLOCAL_MAX_SLOTS\) \{' "$ROOT/$f" || true)
    [ "$LOOPS" -ge 2 ] \
        || fail "$f: expected at least 2 loops bounded by TLOCAL_MAX_SLOTS (save + restore), found $LOOPS"
    LIT=$(grep -cE 'while \(i < [0-9]+\) \{' "$ROOT/$f" || true)
    [ "$LIT" -eq 0 ] \
        || fail "$f: found $LIT TLS loop(s) bounded by a numeric LITERAL — that is the v6.5.39 defect exactly (the window was 16 while TLOCAL_MAX_SLOTS was 128), and it under-copies silently rather than overflowing"
done

# ── axis 3: the backing storage is sized by the const too ─────────────────────────
# If the storage were smaller than the constant, the (now correct) loops would run off the
# end of the process-global array instead. 6.7.6: every one is sized BY the const — the three
# process-global arrays, the Windows per-thread block, the x86-macOS per-thread TLS header.
for NAME in _tlocal_macos _tlocal_agnos _tlocal_fallback; do
    grep -qE "^var ${NAME}\[_TLOCAL_MAX_SLOTS\];" "$ROOT/lib/thread_local.cyr" \
        || fail "lib/thread_local.cyr: '$NAME' is not 'var $NAME[_TLOCAL_MAX_SLOTS];' — a literal size is a second copy of the slot count, and a smaller one lets slot stores run off the end"
done
grep -qE 'const NB = _TLOCAL_MAX_SLOTS \* 8;' "$ROOT/lib/thread_local.cyr" \
    && grep -qE 'blk = alloc\(NB\);' "$ROOT/lib/thread_local.cyr" \
    || fail "lib/thread_local.cyr: the Windows per-thread block is not alloc(NB) with NB = _TLOCAL_MAX_SLOTS * 8"
grep -qE 'alloc\(1024\)' "$ROOT/lib/thread_local.cyr" \
    && fail "lib/thread_local.cyr: a literal alloc(1024) is back — the Windows slot block is _TLOCAL_MAX_SLOTS * 8 bytes"
grep -qE '^const _THR_HDR = \(\(_TLOCAL_MAX_SLOTS \+ 1\) \* 8 \+ 15\) / 16 \* 16;' "$ROOT/lib/thread_macos.cyr" \
    || fail "lib/thread_macos.cyr: _THR_HDR is not derived from _TLOCAL_MAX_SLOTS — the x86-macOS TLS header (word 0 + the slots) would not grow with the slot count"

# ── axis 4 (v6.5.44): the arm64-macOS REAL-thread path must NOT snapshot ──────────
# Snapshot/zero/restore emulates isolation around an INLINE call. Once thread_create actually
# spawns, that same code is a RACE on the caller's own slots — it is not merely redundant, it
# is wrong. Real isolation comes from a genuinely separate per-thread block, so the arm64
# branch must contain no `var save:` and the accessors must route through `_tlocal_base()`
# rather than addressing the process-global array directly.
ARM=$(awk '/^#ifdef CYRIUS_ARCH_AARCH64$/{a=1} /^#endif$/{a=0} a' "$ROOT/lib/thread_macos.cyr")
printf '%s' "$ARM" | grep -q 'fn thread_create' \
    || fail "lib/thread_macos.cyr: could not find thread_create inside the CYRIUS_ARCH_AARCH64 branch — the gate is reading nothing"
printf '%s' "$ARM" | grep -q 'var save:' \
    && fail "lib/thread_macos.cyr: the arm64 real-thread path still snapshots TLS — with a real thread that is a race on the CALLER's slots, not isolation"
for fn in thread_local_get thread_local_set; do
    grep -A6 "^fn $fn" "$ROOT/lib/thread_local.cyr" | grep -q '_tlocal_base()' \
        || fail "lib/thread_local.cyr: $fn does not go through _tlocal_base() — every thread would share one slot array"
done

# ── axis 5 (6.6.19): lib/thread_macos.cyr carries NO inline-snapshot path at all ─────
# Both Mach-O arches start real threads now (x86 over bsdthread, with gs-base TLS), so the
# save/zero/restore emulation must not survive anywhere in the file: on a real thread it is a
# race on the caller's slots, and a body run inline is the serial backend THREADS_CONCURRENT = 1
# denies. x86's isolation comes from a per-thread header behind the gs base, so the x86-macOS
# `_tlocal_base()` must read it rather than hand every thread the process-global array.
grep -q 'var save:' "$ROOT/lib/thread_macos.cyr" \
    && fail "lib/thread_macos.cyr still carries a TLS snapshot buffer (var save:) — both macOS arches run real threads, so that emulation is a race on the caller's slots"
grep -q 'fncall1(fp, arg)' "$ROOT/lib/thread_macos.cyr" \
    && fail "lib/thread_macos.cyr runs a thread body inline (fncall1(fp, arg)) — the serial backend is gone from both macOS arches"
XB=$(awk '/^#ifndef CYRIUS_ARCH_AARCH64$/{a=1} a&&/^#endif$/{a=0} a' "$ROOT/lib/thread_local.cyr" \
    | awk 'index($0, "fn _tlocal_base(") == 1 {p=1} p {print} p && /^}/ {exit}')
printf '%s' "$XB" | grep -q '_tls_gs_word0()' \
    || fail "lib/thread_local.cyr: the x86-macOS _tlocal_base() does not read the per-thread gs header — every real thread would share one slot array"

echo "PASS: tls_window_matches_max_slots (_TLOCAL_MAX_SLOTS=$MAX sizes every slot buffer and TLOCAL_MAX_SLOTS derives from it; the serial peer saves the full range; macOS snapshots nothing and x86-macOS reads per-thread gs slots)"
