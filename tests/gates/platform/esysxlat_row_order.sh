#!/bin/sh
# esysxlat_row_order.sh — v6.6.5. No ESYSXLAT row RE-CAPTURES an earlier row's product.
#
# ⛔ THE CLASS, WHICH HAS SHIPPED FOUR TIMES. `ESYSXLAT`'s ELF-aarch64 arm
# (src/backend/aarch64/emit.cyr) is a SEQUENTIAL `cmp x8,#src / b.ne / movz x8,#dst` chain
# with no early exit: once a row rewrites x8, every row BELOW it still compares against the
# NEW value. So a row whose SOURCE equals an earlier row's PRODUCT silently re-rewrites a
# call that was already correct:
#   v6.2.x  flock 73→32 had to be placed ABOVE poll 7→73, or every ppoll became flock;
#   v6.4.42 epoll_wait 232→22 had to go BELOW pipe 22→59, or every epoll became pipe2;
#   v6.1.3  newfstatat 262→79 / utimensat 280→88 had to go BELOW getcwd 79→17 / symlink
#           88→36, or the at-family was re-caught;
#   v6.5.36 ppoll/signalfd4 hit it from the other side, and kybernet's ENTIRE aarch64
#           target was non-functional for two releases because of it.
# Every one of those was found by a human reading the chain, or by a consumer. Each fix
# wrote the ordering rule into a COMMENT next to its own row. A comment is not a check.
#
# ⭐ WHAT THIS ASSERTS IS THE PROPERTY, NOT A ROW LIST. Decode the chain into (src, dst)
# pairs in EMISSION ORDER and fail if any later row's src equals any earlier row's dst.
# That is the whole invariant, it needs no maintenance when a row is added, and it is the
# thing the four comments above are each a special case of. v6.6.5 added fourteen rows whose
# order is load-bearing in three separate places at once (nanosleep 35→101 before the
# unlinkat rows that produce 35; ftruncate 77→46 after sendmsg 46→211; truncate 76→45 after
# recvfrom 45→207), which is what made a structural check worth writing.
#
# ⚠ SCOPE: the ELF arm ONLY. The `_TARGET_MACHO == 2` branch cannot have this bug at all —
# it compares x8 and writes x16, two different registers — so including it would produce
# false positives (e.g. rt_sigaction 134→46 "produces" 46, which is a Darwin number).
#
# Anti-vacuous: a floor on decoded rows, and a positive control that the decoder really
# sees a known row. A decoder that returns 0 pairs would otherwise report "0 re-captures".
#
# MUTATION LEDGER (each applied to src/backend/aarch64/emit.cyr, gate re-run, then reverted):
#   1. move the mkdir 83→34 row BELOW fdatasync 75→83   -> FAIL "row 37 (83→34) re-captures"
#   2. move unlinkat 263→35 ABOVE nanosleep 35→101      -> FAIL (35→101 re-captures 263→35)
#   3. swap sendmsg 46→211 and ftruncate 77→46          -> FAIL (46→211 re-captures 77→46)
#   4. delete every EW() row (empty chain)              -> FAIL on the floor, not "0 found"
# Behaviourally, mutation 3 also fails **12** assertions in
# tests/tcyr/crossos/syscall_shm_fd_passing.tcyr — MEASURED, not estimated: swap the pair,
# rebuild the aarch64 fork, run under qemu-aarch64 -> "40 passed, 12 failed", exit 12.
# (ftruncate + its two oracles, the memfd trio, the SCM_RIGHTS pair, raw 77 + its oracle, and
# the raw pass-fd pair; every ftruncate returns -EFAULT because 46 is sendmsg.) This line said
# "6" through review round 1 — a hand-guessed count in the header of a gate whose whole point
# is that a comment is not a check.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
EMIT=src/backend/aarch64/emit.cyr
[ -f "$EMIT" ] || { echo "FAIL: esysxlat_row_order: $EMIT missing"; exit 1; }

# ── decode ──────────────────────────────────────────────────────────────────────────
# cmp x8,#imm  = 0xF1000000 | imm<<10 | 8<<5 | 0x1F   -> mask 0xFFC003FF == 0xF100011F
# movz x8,#imm = 0xD2800000 | imm<<5 | 8              -> mask 0xFFE0001F == 0xD2800008
# The Rn/Rd fields are part of the mask on purpose: dropping them admits ETESTAZ's
# `cmp x0,#0` and the arg-shift `movz x1/x2/x3,#…` words, which yields plausible-but-wrong
# numbers — the trap macho_route_parity.sh's header already records from its own decoder.
# A cmp may be followed by arg-shift instructions before the movz (the stat/rename/unlink
# rows insert AT_FDCWD), so the pending source is held until the next `movz x8`.
ROWS=$(awk '
/^fn ESYSXLAT\(/ { on = 1 }
on && /^fn / && !/^fn ESYSXLAT\(/ { on = 0 }
on && /_TARGET_MACHO == 2/ { macho = 1 }
on && macho && /^        return 0;/ { macho = 0; next }
on && !macho {
    line = $0
    while (match(line, /EW\(S, 0x[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]\)/)) {
        w = strtonum("0x" substr(line, RSTART + 8, 8))
        line = substr(line, RSTART + RLENGTH)
        if (and(w, 0xFFC003FF) == 0xF100011F) { pend = rshift(w - 0xF100011F, 10); havep = 1 }
        else if (and(w, 0xFFE0001F) == 0xD2800008 && havep) { printf "%d %d\n", pend, and(rshift(w, 5), 0xFFFF); havep = 0 }
    }
}
' "$EMIT")

nrows=$(printf '%s\n' "$ROWS" | grep -c '^[0-9]' || true)
# Floor: 58 rows at v6.6.5 (44 before this release). Rows only ever get added, so a drop
# means the decoder or the emitter shape moved, not that the chain shrank.
if [ "$nrows" -lt 58 ]; then
    echo "FAIL: esysxlat_row_order: decoded only $nrows (src,dst) rows from ESYSXLAT's ELF arm (floor 58)."
    echo "      The decoder or the emitter shape moved — this gate is not inspecting anything."
    exit 1
fi
# Positive control: a row this gate MUST see, chosen because it is one of the four historical
# ordering fixes. If the decoder silently stops early, this disappears before the floor does.
printf '%s\n' "$ROWS" | grep -qx '7 73' \
  || { echo "FAIL: esysxlat_row_order: the control row (poll 7→73) was not decoded — the decoder is wrong, not the chain"; exit 1; }
printf '%s\n' "$ROWS" | grep -qx '35 101' \
  || { echo "FAIL: esysxlat_row_order: the nanosleep row (35→101) is missing from the ELF arm (v6.6.5)"; exit 1; }

# ── the invariant ───────────────────────────────────────────────────────────────────
report=$(printf '%s\n' "$ROWS" | awk '
{ src[NR] = $1; dst[NR] = $2; n = NR }
END {
    bad = 0
    for (i = 2; i <= n; i++)
        for (j = 1; j < i; j++)
            if (src[i] == dst[j]) {
                printf "    RE-CAPTURE  row %d (%d->%d): its SOURCE is the PRODUCT of row %d (%d->%d).\n", i, src[i], dst[i], j, src[j], dst[j]
                printf "                Row %d rewrites x8 to %d, and row %d then matches that value, so every\n", j, dst[j], i
                printf "                %d->%d call is silently reissued as %d. Move row %d ABOVE row %d.\n", src[j], dst[j], dst[i], i, j
                bad++
            }
    printf "RECAP=%d\n", bad
}')
bad=$(printf '%s\n' "$report" | sed -n 's/^RECAP=\([0-9]*\)$/\1/p')
printf '%s\n' "$report" | grep -v '^RECAP=' || true
if [ "${bad:-1}" -ne 0 ]; then
    echo "FAIL: esysxlat_row_order: $bad re-capture(s) in ESYSXLAT's ELF-aarch64 chain ($nrows rows)."
    echo "      The chain has no early exit: a row below another sees the value that one wrote."
    exit 1
fi

# ── the alias band stays last ───────────────────────────────────────────────────────
# Restated here in (src,dst) terms rather than deferred to aarch64_syscall_shadow.sh, because
# it is the same invariant: an alias row PRODUCES a native number that a compat row above it
# matches, and the two gates decode the chain differently (this one in sh/awk, that one in
# python), so agreeing is evidence rather than a shared assumption.
last_compat=$(printf '%s\n' "$ROWS" | awk '$1 < 1000 { last = NR } END { print last + 0 }')
first_alias=$(printf '%s\n' "$ROWS" | awk '$1 >= 1000 { print NR; exit }')
if [ -n "${first_alias:-}" ] && [ "$first_alias" -lt "$last_compat" ]; then
    echo "FAIL: esysxlat_row_order: an alias-band row (index $first_alias) sits above an x86-compat row (index $last_compat)."
    exit 1
fi

echo "PASS esysxlat_row_order: $nrows ESYSXLAT ELF rows, 0 re-captures, alias band last"
