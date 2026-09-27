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
# ⛔ 6.6.7 — N TIERS, NOT THREE. agnos 1.57.9 appended `sched_kicks` at +200 and the contract grew
# a FOURTH tier ("40 / 104 / 200 / 208"). This gate's regex hard-coded three numbers, extracted
# "40 / 104 / 200", and then asserted FULL == tier 3 (200) AND FULL == the struct size (208) — no
# lib edit could satisfy both, so check.sh went RED on every box with agnos >= 1.57.9 and stayed
# green in CI (which SKIPs without the sibling). The parser now reads EVERY tier: the first is
# SYSINFO_SIZE, the second SYSINFO_SIZE_CPU, the last SYSINFO_SIZE_FULL (== the §4.4 size), and
# each middle tier must have a named SYSINFO_SIZE_* constant of that value — so the next tail
# band fails here by NAME until lib/sys.cyr names it. SI_SCHED_KICKS is tied to its row.
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
TIERS=$(grep -oE 'The length tiers are [0-9]+( / [0-9]+)+' "$ABI" | head -1 | grep -oE '[0-9]+' | tr '\n' ' ')
CPUB=$(awk '/^### 4\.4 /{s=1} s&&/^\| [0-9]+ \| `cpu0_user`/{print $2; exit}' "$ABI")
BLKB=$(awk '/^### 4\.4 /{s=1} s&&/^\| [0-9]+ \| `blk0_read`/{print $2; exit}' "$ABI")
KICKB=$(awk '/^### 4\.4 /{s=1} s&&/^\| [0-9]+ \| `sched_kicks`/{print $2; exit}' "$ABI")

# Anti-vacuous: a regex that matches nothing reports nothing wrong and PASSES.
[ -n "$SIZE" ] || fail "could not parse the §4.4 struct size from the agnos contract — the heading format changed and this gate is reading nothing"
[ -n "$CPUB" ] || fail "could not find the cpu0_user row in §4.4 — the gate is reading nothing"
[ -n "$BLKB" ] || fail "could not find the blk0_read row in §4.4 — the gate is reading nothing"
[ -n "$KICKB" ] || fail "could not find the sched_kicks row in §4.4 — the gate is reading nothing"
NT=$(printf '%s' "$TIERS" | wc -w)
[ "$NT" -ge 3 ] || fail "expected at least 3 length tiers in the contract, parsed '$TIERS'"

# ── the cyrius side. Read ONLY the AGNOS enum block: lib/sys.cyr defines SYSINFO_SIZE twice
#    (40 for agnos, 120 for the Linux-shaped struct) and a whole-file grep picks up both.
#    6.6.7: the WHOLE enum (header to its closing brace), not `grep -A6` — a fixed window
#    silently drops whatever constant the next tier pushes past its last line.
AGB=$(awk '/^#ifdef CYRIUS_TARGET_AGNOS$/{a=1} a{print} /^#endif$/{if(a&&/#endif/){a=0}}' "$SYS")
AG=$(printf '%s\n' "$AGB" | awk '/enum SysInfoConst/{e=1} e{print} e&&/}/{exit}')
BASE=$(printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE = [0-9]+'      | grep -oE '[0-9]+' | head -1)
CPU=$( printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE_CPU = [0-9]+'  | grep -oE '[0-9]+' | head -1)
FULL=$(printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE_FULL = [0-9]+' | grep -oE '[0-9]+' | head -1)
# every tier-length constant the enum names, as "NAME=VALUE" words
NAMED=$(printf '%s' "$AG" | grep -oE 'SYSINFO_SIZE(_[A-Z]+)? = [0-9]+' | tr -d ' ' | tr '\n' ' ')
OCPU=$(grep -oE 'SI_CPU_BASE = [0-9]+' "$SYS" | grep -oE '[0-9]+' | head -1)
OBLK=$(grep -oE 'SI_BLK_BASE = [0-9]+' "$SYS" | grep -oE '[0-9]+' | head -1)
OKICK=$(printf '%s' "$AGB" | grep -oE 'SI_SCHED_KICKS = [0-9]+' | grep -oE '[0-9]+' | head -1)
for v in BASE CPU FULL OCPU OBLK OKICK; do
    eval "x=\$$v"; [ -n "$x" ] || fail "could not read $v from lib/sys.cyr's AGNOS enum block — the gate is reading nothing"
done

# ── compare ──────────────────────────────────────────────────────────────────────────
set -- $TIERS
[ "$BASE" = "$1" ] || fail "SYSINFO_SIZE is $BASE but the contract's base tier is $1"
[ "$CPU"  = "$2" ] || fail "SYSINFO_SIZE_CPU is $CPU but the contract's CPU tier is $2 — a caller asking for $CPU would not get the band it thinks it is asking for"
eval "LAST=\${$NT}"
[ "$FULL" = "$LAST" ] || fail "SYSINFO_SIZE_FULL is $FULL but the contract's last (full) tier is $LAST — tiers '$TIERS'"
[ "$FULL" = "$SIZE" ] || fail "SYSINFO_SIZE_FULL is $FULL but §4.4 declares the struct $SIZE bytes"
# every MIDDLE tier (3 .. NT-1) needs its own named constant, or a caller has no way to ask for
# exactly that band without a magic number
i=3
while [ "$i" -lt "$NT" ]; do
    eval "MID=\${$i}"
    case " $NAMED " in
        *"="$MID" "*) ;;
        *) fail "the contract's tier $i ($MID bytes) has no SYSINFO_SIZE_* constant in lib/sys.cyr's AGNOS enum (named: $NAMED)" ;;
    esac
    i=$((i + 1))
done
[ "$OKICK" = "$KICKB" ] || fail "SI_SCHED_KICKS is $OKICK but sched_kicks is at +$KICKB — sys_sched_kicks would read the wrong u64"
[ "$OCPU" = "$CPUB" ] || fail "SI_CPU_BASE is $OCPU but cpu0_user is at +$CPUB — every per-core reading would be off by $((OCPU - CPUB)) bytes"
[ "$OBLK" = "$BLKB" ] || fail "SI_BLK_BASE is $OBLK but blk0_read is at +$BLKB — every disk counter would be off by $((OBLK - BLKB)) bytes, silently, as a plausible statistic"

# ── the wrapper that makes the tail reachable at all ──────────────────────────────────
grep -q 'fn sys_sysinfo_n(out, len)' "$SYS" \
    || fail "sys_sysinfo_n is missing — sys_sysinfo(out) hardcodes the base length, so without an overload NO wrapper consumer can reach the tail (the filed defect)"
grep -A4 'fn sys_sysinfo_n(out, len)' "$SYS" | grep -q 'syscall(SYS_SYSINFO, out, len)' \
    || fail "sys_sysinfo_n does not pass the caller's length through to the syscall"

# 6.6.7: the one-call reader for the 1.57.9 field asks for the whole struct into a buffer sized
# by the same constant, and pre-fills the slot so an older kernel (which leaves it unwritten)
# reads back -1 rather than stack residue.
KF=$(awk '/^fn sys_sched_kicks\(\)/,/^}/' "$SYS" | sed 's/#.*//')
[ -n "$KF" ] || fail "sys_sched_kicks is missing — the sched_kicks field has no reader"
printf '%s\n' "$KF" | grep -q 'var buf\[SYSINFO_SIZE_FULL\]' \
    || fail "sys_sched_kicks does not size its buffer by SYSINFO_SIZE_FULL — the kernel writes the full length it is asked for"
printf '%s\n' "$KF" | grep -q 'sys_sysinfo_n(&buf, SYSINFO_SIZE_FULL)' \
    || fail "sys_sched_kicks does not ask sys_sysinfo_n for SYSINFO_SIZE_FULL — a shorter length leaves +$KICKB unwritten"
printf '%s\n' "$KF" | grep -q 'store64(&buf + SI_SCHED_KICKS, 0 - 1)' \
    || fail "sys_sched_kicks does not pre-fill +SI_SCHED_KICKS with -1 — on agnos < 1.57.9 it would return stack residue as a count"

# 6.6.7 RUNTIME, under mirshi when present. mirshi writes only the 40-byte base struct and
# accepts a longer length, which is exactly an agnos older than the sched_kicks band — so
# sys_sched_kicks must come back -1 there. The probe dirties the stack first, so a reader that
# forgot the pre-fill returns the 0x55… pattern (exit 7) instead of an accidental -1 or 0.
# Measured: without the store64 pre-fill the probe exits 7. If a future mirshi fills +200 the
# pre-band path is unreachable and the axis SKIPs by name.
RT="mirshi absent — runtime axis skipped"
MIRSHI="$HOME/Repos/mirshi/build/mirshi"
CC="$ROOT/build/cycc"
if [ -x "$MIRSHI" ] && [ -x "$CC" ]; then
    T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL agnos_sysinfo_tail_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
    trap 'rm -rf "$T"' EXIT
    cat > "$T/k.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/sys.cyr"
fn dirty(): i64 { var d[512]; var i = 0; while (i < 512) { store64(&d + i, 0x5555555555555555); i = i + 8; } return load64(&d + 256); }
fn main(): i64 {
    dirty();
    var k = sys_sched_kicks();
    if (k == 0 - 1) { return 0; }
    if (k == 0x5555555555555555) { return 7; }
    if (k >= 0) { return 9; }
    return 8;
}
var r = main();
sys_exit(r);
EOF
    ( cd "$ROOT" && CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/k.cyr" > "$T/k.out" 2> "$T/k.err" ) \
        || fail "the CYRIUS_TARGET_AGNOS build of the sys_sched_kicks probe failed: $(grep -E '^error' "$T/k.err" | head -1)"
    chmod +x "$T/k.out"
    krc=0; ( cd "$T" && "$MIRSHI" ./k.out > /dev/null 2>&1 ) || krc=$?
    case "$krc" in
        0) RT="mirshi (base struct only): sys_sched_kicks = -1, not stack residue" ;;
        9) RT="SKIP runtime axis by name: this mirshi fills sched_kicks, so the pre-1.57.9 path is unreachable here" ;;
        7) fail "sys_sched_kicks returned STACK RESIDUE under mirshi (which leaves +$OKICK unwritten, like agnos < 1.57.9) — the pre-fill is missing" ;;
        *) fail "sys_sched_kicks probe under mirshi exited $krc (expected 0: -1 from a kernel that did not write the field)" ;;
    esac
fi

echo "PASS agnos_sysinfo_tail_parity (#35 tiers $TIERS— SYSINFO_SIZE/_CPU/…/_FULL $BASE/$CPU/$FULL, cpu band +$OCPU, block band +$OBLK, sched_kicks +$OKICK — all match the agnos §4.4 contract · $RT)"
