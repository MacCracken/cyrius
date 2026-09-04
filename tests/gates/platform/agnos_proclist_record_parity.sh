#!/bin/sh
# agnos_proclist_record_parity.sh — v6.5.46
#
# Fourth gate in the agnos-parity family. Each covers a class the ones above cannot see:
#   agnos_abi_doc_parity            syscall NUMBERS
#   agnos_net_config_field_parity   FIELD SELECTORS inside one syscall
#   agnos_sysinfo_tail_parity       STRUCT TAIL layout (#35)
#   THIS ONE                        a RECORD FIELD that stopped being reserved (#99)
#
# ⛔ WHAT IT GUARDS. `proclist`#99's `+56` slot was documented in the cyrius peer as
# "u64 reserved — always 0 today", with a paragraph explaining that rss and cpu time "are not
# tracked by the kernel yet". agnos 1.56.59 filled it: one `store64(pl_rec + 56, (pl_rs << 32) |
# pl_tk)` — low u32 cpu ticks, high u32 rss pages. The record SIZE did not change, so nothing
# any other gate checks moved: the number is the same, the field count is the same, the struct
# is the same 64 bytes. Only the meaning of one slot changed, and the peer's doc block is the
# ONLY description a consumer reads.
#
# ⚠ BOTH WAYS A CONSUMER CAN TRUST THE STALE TEXT ARE BAD. Zero-check the u64 and skip it and
# you stay CORRECT while silently reading no data — which is what chakshu did for a release.
# Render it and you publish ~6.6e12, a positive, plausible, nonsensical number: 2,000 years as
# ticks, 25 PB as pages. This is the SECOND release chakshu lost to a stale note in this file.
#
# PROPERTY: if the live agnos kernel writes the slot, the peer must not call it reserved, and
# must expose the halves by name.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PEER="$ROOT/lib/syscalls_x86_64_agnos.cyr"
KSRC="$HOME/Repos/agnos/kernel/core/syscall.cyr"
fail() { echo "FAIL agnos_proclist_record_parity: $1" >&2; exit 1; }

if [ ! -f "$KSRC" ]; then
  echo "SKIP agnos_proclist_record_parity: agnos kernel source not found at $KSRC (sibling repo absent)"
  exit 0
fi

# Does the kernel write the slot? Derived from the kernel, not from any doc.
WRITES=$(grep -c 'pl_rec + 56' "$KSRC" || true)

if [ "$WRITES" -eq 0 ]; then
  # Still reserved upstream — then the peer SHOULD say so, and the accessors should not exist.
  grep -q 'reserved' "$PEER" \
    || fail "the kernel does not write proclist +56 but the peer no longer documents it as reserved — one of the two is wrong"
  echo "PASS agnos_proclist_record_parity (kernel does not write +56; peer still documents it reserved — consistent)"
  exit 0
fi

# The kernel writes it. The peer must not still call it reserved/always-0.
sed -n '/Record (64 B, little-endian)/,/^# ⚠ GUARD THE CALL SITE/p' "$PEER" | grep -qE '\+56 +u64 +reserved' \
  && fail "the agnos kernel WRITES proclist +56 ($WRITES site(s) in kernel/core/syscall.cyr) but the peer still documents it as 'u64 reserved' — a consumer either skips live data or renders a packed pair as one nonsensical number"
grep -q 'THE RESERVED FIELD IS NOT SPARE SPACE' "$PEER" \
  && fail "the peer still carries the 'not tracked by the kernel yet' paragraph for proclist +56, which is false as of agnos 1.56.59"

# And the halves must be reachable by name — hand-decoding a packed pair at each call site is
# how the halves get swapped, and BOTH halves are plausible positive integers, so a swap
# produces a wrong number rather than a visible failure.
for fn in proclist_cpu_ticks proclist_rss_pages; do
    grep -q "^fn $fn(rec)" "$PEER" || fail "$fn is missing — the peer documents a packed field with no named accessor for its halves"
done
# Low half is ticks, high half is pages. Swapping them is the whole hazard, so pin the direction.
# ⚠ The low-half check must REJECT a shift, not merely accept a mask: the swapped form
# `(load64(rec + 56) >> 32) & 0xFFFFFFFF` still contains `& 0xFFFFFFFF`, so a mask-only test
# passes the exact mutation this axis exists to catch — measured on this gate's first run.
grep '^fn proclist_cpu_ticks(rec)' "$PEER" | grep -q '& 0xFFFFFFFF' \
    || fail "proclist_cpu_ticks does not mask the low 32 bits"
grep '^fn proclist_cpu_ticks(rec)' "$PEER" | grep -q '>> 32' \
    && fail "proclist_cpu_ticks SHIFTS before masking — it is reading the rss half. Both halves are plausible positive integers, so a swap yields a wrong number rather than a visible failure"
grep '^fn proclist_rss_pages(rec)' "$PEER" | grep -q '>> 32' \
    || fail "proclist_rss_pages does not shift to the HIGH 32 bits — it is reading the cpu-tick half"

echo "PASS agnos_proclist_record_parity (kernel writes +56; peer documents the packed pair and exposes both halves in the right direction)"
