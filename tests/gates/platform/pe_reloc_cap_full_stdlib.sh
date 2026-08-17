#!/bin/sh
# v6.5.26 — a FULL-STDLIB program must build for Windows, and the PE base-relocation table
# must not be a fixed ceiling.
#
# THE BUG. `_pe_layout` collected DIR64 relocation sites into a FIXED 64 KB window at
# S + 0x1DC000 = 8192 u64 slots, and overflowing it was a hard `error: PE reloc table full
# (8192)` with no binary. The 26-module `folds_agnos_parity.sh` preamble + `lib/random.cyr`
# + any one fold is past that ceiling, so **no full-stdlib Windows program could be built at
# all**. Measured: cap 8192 reports FULL, cap 16384 fits, so the real requirement for the
# largest fold (mabda) is between 8k and 16k slots.
#
# ⚠ IT COULD NOT BE RAISED IN PLACE. The window was exactly 64 KB and `0x1DC000 + 0x10000`
# IS `0x1EC000` = `gvar_initval` — zero adjacent slack — so growing it would have MOVED a
# region, i.e. a heap LAYOUT change and a two-step bootstrap. It is now lazily allocated
# (`_pe_reloc_base`, cap `_PE_RELOC_CAP` = 65536) per the v6.4.75 `_fnvb_base` precedent: no
# region moves, no layout change, and non-PE targets allocate nothing.
#
# ⛔ WHY IT WAS INVISIBLE FOR SO LONG, which is the part worth keeping: until v6.5.25 a PE
# build of the folded stdlib died EARLIER on `undefined variable 'SYS_IOCTL'`. A ceiling
# sitting behind a hard error cannot be observed. Fixing the earlier error is what exposed
# this one — so "the build fails" had TWO independent causes stacked, and clearing one only
# revealed the next.
#
# ⭐ THIS GATE IS ALSO THE `cycc_win` AXIS `folds_agnos_parity.sh` NEVER HAD. That gate has
# an agnos axis ONLY, which is precisely why a PE-only ceiling could sit here unnoticed
# while a green suite reported the folds fine.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
cd "$ROOT"
G="tests/gates/platform/folds_agnos_parity.sh"
[ -f "$G" ] || { echo "SKIP: $G missing (source of the dependency-ordered preamble)"; exit 0; }
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fail=0

# Reuse the sibling gate's OWN preamble rather than re-listing it, so the two cannot drift.
# ⚠ A hand-rolled two-include probe is NOT a substitute: including a fold without its
# declared dependencies yields undefined ORDINARY stdlib names (alloc, memcpy, file_open,
# map_new, fncall1..6), which read exactly like missing Windows-peer wrappers and were once
# recorded as such. Use the real preamble or the result is meaningless.
sed -n "/^PREAMBLE='/,/^include \"lib\/yukti.cyr\"'/p" "$G" \
  | sed "s/^PREAMBLE='//; s/'\$//" > "$D/pre.txt"
printf 'include "lib/random.cyr"\n' >> "$D/pre.txt"

npre=$(grep -c '^include' "$D/pre.txt" || true)
# axis 0 — anti-vacuous: if the preamble did not extract, every build below is trivial and
# would pass while testing nothing.
if [ "$npre" -lt 20 ]; then
    echo "  FAIL axis 0 (anti-vacuous): only $npre preamble includes extracted (expected 20+) — the probe is not a full-stdlib build, so it proves nothing about the ceiling"
    exit 1
fi
echo "  ok axis 0: extracted a $npre-module full-stdlib preamble from $G"

# --- axis 1: the largest folds must BUILD for Windows ---
# mabda is the biggest reloc consumer; yukti is the one SYS_IOCTL used to block; sigil is a
# third independent large fold.
for d in mabda yukti sigil; do
    [ -f "lib/$d.cyr" ] || { echo "  note: lib/$d.cyr absent — skipped"; continue; }
    grep -v "lib/$d\.cyr" "$D/pre.txt" > "$D/p.cyr"
    printf 'include "lib/%s.cyr"\nfn main(): i64 { return 0; }\n' "$d" >> "$D/p.cyr"
    CYRIUS_TARGET_WIN=1 "$CC" < "$D/p.cyr" > "$D/o.bin" 2>"$D/e.err" || true
    if grep -q "relocation table full\|reloc table full" "$D/e.err"; then
        echo "  FAIL axis 1 [$d]: PE build hit the base-relocation ceiling — raise _PE_RELOC_CAP"
        fail=1
    elif [ ! -s "$D/o.bin" ]; then
        echo "  FAIL axis 1 [$d]: PE build produced no binary"
        grep -m2 "^error" "$D/e.err" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 1 [$d]: full-stdlib PE build succeeds ($(stat -c%s "$D/o.bin") B)"
    fi
done

# --- axis 2: the same sources must still build for LINUX (no regression) ---
# The reloc table is PE-only, but the lazy-alloc touched a shared emit file.
grep -v "lib/mabda\.cyr" "$D/pre.txt" > "$D/p.cyr"
printf 'include "lib/mabda.cyr"\nfn main(): i64 { return 0; }\n' >> "$D/p.cyr"
"$CC" < "$D/p.cyr" > "$D/o.bin" 2>"$D/e.err" || true
if [ ! -s "$D/o.bin" ]; then
    echo "  FAIL axis 2: the Linux build of the same full-stdlib source regressed"
    grep -m2 "^error" "$D/e.err" | sed 's/^/      /'
    fail=1
else
    echo "  ok axis 2: Linux build of the same source unaffected ($(stat -c%s "$D/o.bin") B)"
fi

# --- axis 3: the fixed 0x1DC000 window must be GONE from the emitter ---
# A future edit that reintroduces the hardcoded base silently reinstates the ceiling.
if grep -q "0x1DC000" src/backend/pe/emit.cyr; then
    if grep -E "(S64|L64)\(\s*S \+ 0x1DC000" src/backend/pe/emit.cyr >/dev/null 2>&1; then
        echo "  FAIL axis 3: src/backend/pe/emit.cyr ACCESSES the fixed 0x1DC000 window again — the ceiling is back"
        fail=1
    else
        echo "  ok axis 3: 0x1DC000 appears only in prose, not as a live access"
    fi
else
    echo "  ok axis 3: no reference to the fixed 0x1DC000 window"
fi

# --- axis 4: the heap map must record 0x1DC000 as freed ---
# The map is machine-read; leaving a live-looking region there invites a future overlap.
if grep -qE '^#   0x1DC000  \(FREED' src/main.cyr; then
    echo "  ok axis 4: heap map records 0x1DC000 as FREED"
else
    echo "  FAIL axis 4: heap map still describes 0x1DC000 as a live region — it is now lazily allocated"
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: pe-reloc-cap-full-stdlib"; exit 1; }
echo "PASS: pe-reloc-cap-full-stdlib — full-stdlib Windows builds succeed; the relocation table is lazily allocated, not a fixed 64 KB ceiling"
