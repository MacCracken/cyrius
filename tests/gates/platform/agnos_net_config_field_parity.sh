#!/bin/sh
# agnos_net_config_field_parity.sh — v6.5.44
#
# agnos_abi_doc_parity.sh compares syscall NUMBERS. This compares the FIELD SELECTORS inside one
# syscall, which that gate structurally cannot see — and which is where the drift actually happened.
#
# ⛔ WHAT THIS EXISTS FOR. `#61 net_config` takes a field id and already passes an arbitrary one
# through, so agnos EXTENDS it rather than minting numbers: fields 4..7 (ICMP counters, 1.56.48) and
# 8..11 (interface packet/byte totals, 1.56.59) reached consumers with NO cyrius release at all.
# The upside is that no peer work is needed; the trap is that nothing then forces the cyrius side to
# notice, and cyrius's comments still said the range was `4..7` while the kernel answered `4..11`.
# ⚠ A STALE RANGE IS NOT COSMETIC: it is how a consumer concludes a capability does not exist and
# writes a workaround for something that already works. agnos's own tracker records two of those in
# one week — chakshu nearly filed a phantom `statfs` gap against an arm sitting 20 lines below the
# comment that denied it, and crab carried a blocker for FIVE releases after its fix had shipped.
# The number-level gate was GREEN through all of it, because no number was wrong.
#
# PROPERTY: every field id agnos's `#61` row names has a named accessor in the cyrius peer, and the
# peer's own documented range covers the highest one.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PEER="$ROOT/lib/syscalls_x86_64_agnos.cyr"
ABI="$HOME/Repos/agnos/docs/development/agnos-userland-abi.md"
fail() { echo "FAIL agnos_net_config_field_parity: $1" >&2; exit 1; }

# agnos is a SIBLING repo and may be absent — SKIP loudly rather than pass quietly.
if [ ! -f "$ABI" ]; then
  echo "SKIP agnos_net_config_field_parity: agnos ABI contract not found at $ABI (sibling repo absent)"
  exit 0
fi

ROW=$(grep -m1 '^| 61 | `net_config`' "$ABI") || fail "no #61 net_config row in the agnos contract"

# Two notations are in use in that row and BOTH must be read: `N=name` for fields 0..7 and
# `**N**` for 8..11. Reading only one silently halves the contract.
WANT=$( { printf '%s\n' "$ROW" | grep -oE '(^|[^0-9.])[0-9]+=`?[a-z_]' | grep -oE '[0-9]+'
          printf '%s\n' "$ROW" | grep -oE '\*\*[0-9]+\*\*'            | grep -oE '[0-9]+'
        } | sort -n -u )
HAVE=$(grep -oE 'syscall\(SYS_NET_CONFIG, [0-9]+\)' "$PEER" | grep -oE '[0-9]+' | sort -n -u)

# Anti-vacuous floors on BOTH sides: a regex that matches nothing reports nothing wrong and PASSES.
NW=$(printf '%s\n' "$WANT" | grep -c . || true)
NH=$(printf '%s\n' "$HAVE" | grep -c . || true)
[ "$NW" -ge 8 ] || fail "parsed only $NW field ids from the agnos #61 row (expected >= 8) — the row's notation changed and this gate is reading nothing"
[ "$NH" -ge 8 ] || fail "found only $NH net_config accessors in the peer (expected >= 8) — accessor spelling changed and this gate is reading nothing"

MISSING=$(comm -23 <(printf '%s\n' "$WANT") <(printf '%s\n' "$HAVE") | tr '\n' ' ')
[ -z "$(printf '%s' "$MISSING" | tr -d ' ')" ] || fail "agnos #61 names field(s) [$MISSING] with no accessor in the cyrius peer — a consumer reading the peer concludes the capability is absent and writes a workaround"

# The peer's documented RANGE must cover the highest field, or the comment denies what the code does.
MAXF=$(printf '%s\n' "$WANT" | tail -1)
grep -qE "counter \(4\.\.$MAXF\)" "$PEER" \
  || fail "the peer's #61 range comment does not read 'counter (4..$MAXF)' — this is the exact line that said 4..7 while the kernel answered 4..11"

echo "PASS agnos_net_config_field_parity (#61 fields 0..$MAXF: $NW named by agnos, all $NH present in the peer, range comment current)"
