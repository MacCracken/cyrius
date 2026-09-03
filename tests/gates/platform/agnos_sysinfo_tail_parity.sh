#!/bin/sh
# agnos_sysinfo_tail_parity.sh — v6.5.45
#
# Third gate in the agnos-parity family, and each covers a class the one above it cannot see:
#   agnos_abi_doc_parity        syscall NUMBERS         (does #N exist on both sides?)
#   agnos_net_config_field_parity  FIELD SELECTORS      (does #61 field 8 have an accessor?)
#   THIS ONE                    STRUCT TAIL LAYOUT      (is #35's band at the right offset?)
#
# ⛔ WHY THE THIRD ONE IS NEEDED. `sysinfo`#35's documented rule is that future fields append at
# the tail and bump the minimum len, while existing offsets are FROZEN ABI the moment a consumer
# reads them. agnos 1.56.59 appended two bands — per-core CPU ticks at +40 and per-device block
# counters at +104 — and grew the struct 40 -> 200 bytes. Both parity gates above stayed GREEN
# through that, correctly: no number changed and no field selector changed. Meanwhile
# `fn sys_sysinfo(out)` hardcoded len=40, so every wrapper consumer kept getting the base struct
# and chakshu — the monitor the tail was built for — could not see one new field.
#
# ⚠ AND THE BLOCK BAND IS WHERE `blkstats`#105 ENDED UP. That number was minted, filed, shipped
# as a cyrius peer in 6.5.44 and WITHDRAWN in 6.5.45 once an audit found a closed 5-value tag
# enum over flat arrays is just a fixed-size tail block. So an off-by-one in SI_BLK_BASE would
# now silently misreport disk statistics, and nothing else in the tree ties that offset to the
# kernel's.
#
# PROPERTY: the tier lengths and band offsets cyrius declares equal the ones agnos's §4.4
# contract states.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SYS="$ROOT/lib/sys.cyr"
ABI="$HOME/Repos/agnos/docs/development/agnos-userland-abi.md"
fail() { echo "FAIL agnos_sysinfo_tail_parity: $1" >&2; exit 1; }

# agnos is a SIBLING repo and may be absent — SKIP loudly rather than pass quietly.
if [ ! -f "$ABI" ]; then
  echo "SKIP agnos_sysinfo_tail_parity: agnos ABI contract not found at $ABI (sibling repo absent)"
  exit 0
fi

# ── the contract side ────────────────────────────────────────────────────────────────
# ⚠ Anchor on " bytes", not "the first number on the line": the heading begins "### 4.4", so a
# lexical `grep -oE '[0-9]+' | head -1` yields 4 — measured, on this gate's first run.
SIZE=$(grep -oE '^### 4\.4 `sysinfo` struct \([0-9]+ bytes' "$ABI" | grep -oE '[0-9]+ bytes' | grep -oE '[0-9]+')
TIERS=$(grep -oE 'The length tiers are [0-9]+ / [0-9]+ / [0-9]+' "$ABI" | grep -oE '[0-9]+' | tr '\n' ' ')
CPUB=$(awk '/^### 4\.4 /{s=1} s&&/^\| [0-9]+ \| `cpu0_user`/{print $2; exit}' "$ABI")
BLKB=$(awk '/^### 4\.4 /{s=1} s&&/^\| [0-9]+ \| `blk0_read`/{print $2; exit}' "$ABI")

# Anti-vacuous: a regex that matches nothing reports nothing wrong and PASSES.
[ -n "$SIZE" ] || fail "could not parse the §4.4 struct size from the agnos contract — the heading format changed and this gate is reading nothing"
[ -n "$CPUB" ] || fail "could not find the cpu0_user row in §4.4 — the gate is reading nothing"
[ -n "$BLKB" ] || fail "could not find the blk0_read row in §4.4 — the gate is reading nothing"
[ "$(printf '%s' "$TIERS" | wc -w)" -eq 3 ] || fail "expected 3 length tiers in the contract, parsed '$TIERS'"

# ── the cyrius side. Read ONLY the AGNOS enum block: lib/sys.cyr defines SYSINFO_SIZE twice
#    (40 for agnos, 120 for the Linux-shaped struct) and a whole-file grep picks up both.
AG=$(awk '/^#ifdef CYRIUS_TARGET_AGNOS$/{a=1} a{print} /^#endif$/{if(a&&/#endif/){a=0}}' "$SYS" \
     | grep -m1 -A6 'enum SysInfoConst')
BASE=$(printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE = [0-9]+'      | grep -oE '[0-9]+' | head -1)
CPU=$( printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE_CPU = [0-9]+'  | grep -oE '[0-9]+' | head -1)
FULL=$(printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE_FULL = [0-9]+' | grep -oE '[0-9]+' | head -1)
OCPU=$(grep -oE 'SI_CPU_BASE = [0-9]+' "$SYS" | grep -oE '[0-9]+' | head -1)
OBLK=$(grep -oE 'SI_BLK_BASE = [0-9]+' "$SYS" | grep -oE '[0-9]+' | head -1)
for v in BASE CPU FULL OCPU OBLK; do
    eval "x=\$$v"; [ -n "$x" ] || fail "could not read $v from lib/sys.cyr's AGNOS enum block — the gate is reading nothing"
done

# ── compare ──────────────────────────────────────────────────────────────────────────
set -- $TIERS
[ "$BASE" = "$1" ] || fail "SYSINFO_SIZE is $BASE but the contract's base tier is $1"
[ "$CPU"  = "$2" ] || fail "SYSINFO_SIZE_CPU is $CPU but the contract's CPU tier is $2 — a caller asking for $CPU would not get the band it thinks it is asking for"
[ "$FULL" = "$3" ] || fail "SYSINFO_SIZE_FULL is $FULL but the contract's full tier is $3"
[ "$FULL" = "$SIZE" ] || fail "SYSINFO_SIZE_FULL is $FULL but §4.4 declares the struct $SIZE bytes"
[ "$OCPU" = "$CPUB" ] || fail "SI_CPU_BASE is $OCPU but cpu0_user is at +$CPUB — every per-core reading would be off by $((OCPU - CPUB)) bytes"
[ "$OBLK" = "$BLKB" ] || fail "SI_BLK_BASE is $OBLK but blk0_read is at +$BLKB — every disk counter would be off by $((OBLK - BLKB)) bytes, silently, as a plausible statistic"

# ── the wrapper that makes the tail reachable at all ──────────────────────────────────
grep -q 'fn sys_sysinfo_n(out, len)' "$SYS" \
    || fail "sys_sysinfo_n is missing — sys_sysinfo(out) hardcodes the base length, so without an overload NO wrapper consumer can reach the tail (the filed defect)"
grep -A4 'fn sys_sysinfo_n(out, len)' "$SYS" | grep -q 'syscall(SYS_SYSINFO, out, len)' \
    || fail "sys_sysinfo_n does not pass the caller's length through to the syscall"

echo "PASS agnos_sysinfo_tail_parity (#35 tiers $BASE/$CPU/$FULL, cpu band +$OCPU, block band +$OBLK — all match the agnos §4.4 contract)"
