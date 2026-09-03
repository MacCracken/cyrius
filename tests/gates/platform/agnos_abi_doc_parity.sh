#!/bin/sh
# Gate: cyrius's AGNOS syscall peer agrees with agnos's frozen ABI contract (v6.5.42).
#
# ⭐ THIS MECHANIZES A CHECK CLAUDE.md ASKS A HUMAN TO DO BY HAND EVERY REACTIVE WINDOW:
# "Diff `agnos/docs/development/agnos-userland-abi.md` against `lib/syscalls_x86_64_agnos.cyr`
# once per window. That doc is the designated frozen normative contract both sides code
# against, and it is the only cheap place to catch an ABI **widen** of an existing number —
# the failure class no compile-time check can see." A once-per-window manual diff is exactly
# the kind of task that silently stops happening; this is the same reasoning that put the
# capacity-meter denominators and the TLS slot window under gates.
#
# ⛔ THE FAILURE CLASS IT EXISTS FOR is a number whose MEANING changed on one side. Nothing in
# either tree can catch that: cyrius compiles fine issuing `syscall(N, ...)` for any N, and the
# kernel happily dispatches it — the program just does the wrong thing. agnos's own ABI doc
# records why a widen is so tempting and so wrong: unused syscall argument registers carry
# STALE VALUES rather than zero, so widening a 0-argument number hands every already-shipped
# caller an arbitrary pointer (the `#100`/`#101` rule; it is why `mountlist` was minted as
# `#104` instead of widening `mount`#11).
#
# ⚖️ A DOC-ONLY NUMBER IS NOT A FAILURE, and this gate deliberately does not treat it as one.
# agnos mints a number, ships the kernel arm, and files for the cyrius peer — which lands on
# cyrius's schedule. `symlink`#63 and `readlink`#70 both shipped in exactly that state. agnos's
# own state.md carries the ruling: *do not "fix" that gate by editing cyrius, and do not weaken
# the gate.* So gaps are REPORTED, and only genuine disagreements fail.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
ABI="$HOME/Repos/agnos/docs/development/agnos-userland-abi.md"
PEER="$ROOT/lib/syscalls_x86_64_agnos.cyr"

# ⚠ agnos is a SIBLING repo and may legitimately be absent (CI, a fresh clone). Surface that
# rather than passing quietly — a cross-repo check that skips in silence is indistinguishable
# from one that passed, which is the failure this repo has been bitten by before.
[ -f "$ABI" ] || { echo "SKIP: agnos ABI contract not found at $ABI — cyrius/agnos ABI parity NOT verified this run"; exit 0; }
[ -f "$PEER" ] || { echo "FAIL: agnos_abi_doc_parity: $PEER missing"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; exit 0; }

python3 - "$ABI" "$PEER" <<'PY'
import re, sys
abi_path, peer_path = sys.argv[1], sys.argv[2]
lines = open(abi_path, encoding='utf-8').read().split('\n')

# ⚠ SCOPE TO THE SYSCALL TABLES ONLY. The contract also carries §3.4's gpu op-code table and
# §4.x's struct-layout tables, whose rows have the SAME `| N | name |` shape but mean
# offset->field, not number->syscall. An unscoped parse reports `#0 = f_bsize` against
# `SYS_EXIT` and a dozen more like it — measured, on the first version of this gate.
try:
    start = next(i for i, l in enumerate(lines) if l.startswith('## 2. '))
    stop  = next(i for i, l in enumerate(lines) if l.startswith('### 3.4 '))
except StopIteration:
    print("FAIL: agnos_abi_doc_parity: could not locate the syscall-table section bounds "
          "(§2 .. §3.4) in the ABI contract — its structure changed and this gate is now blind")
    sys.exit(1)

abi = {}
for l in lines[start:stop]:
    m = re.match(r'^\|\s*(\d+)\s*\|\s*`([a-z_0-9]+)`\s*\|', l)
    if m:
        abi[int(m.group(1))] = m.group(2)

peer = {}
for m in re.finditer(r'\b(SYS_[A-Z_0-9]+)\s*=\s*(\d+);', open(peer_path, encoding='utf-8').read()):
    peer.setdefault(int(m.group(2)), []).append(m.group(1))

# ── anti-vacuous floor. A regex that matches nothing reports nothing wrong and PASSES; this
# repo has scored a fake green exactly that way before. Both sides must be substantial.
if len(abi) < 80:
    print(f"FAIL: agnos_abi_doc_parity: only {len(abi)} syscall rows parsed from the ABI contract "
          f"(expected 80+) — the table format changed and this gate is measuring nothing")
    sys.exit(1)
if len(peer) < 60:
    print(f"FAIL: agnos_abi_doc_parity: only {len(peer)} SYS_* constants parsed from the peer "
          f"(expected 60+) — the gate is blind, not the peer empty")
    sys.exit(1)

# ── axis 1: a shared number must MEAN the same thing on both sides. ────────────────
mismatch = []
for n in sorted(set(abi) & set(peer)):
    if abi[n] not in [c[4:].lower() for c in peer[n]]:
        mismatch.append((n, abi[n], peer[n]))
if mismatch:
    print("FAIL: agnos_abi_doc_parity: a syscall number MEANS something different on each side —")
    print("      this is the ABI-widen class that no compile-time check can see; the program will")
    print("      issue the wrong syscall and the kernel will dispatch it happily.")
    for n, d, c in mismatch:
        print(f"        #{n}: contract says `{d}`, cyrius peer says {c}")
    sys.exit(1)

# ── axis 2: cyrius must not claim a number the contract does not define. ───────────
extra = sorted(set(peer) - set(abi))
if extra:
    print("FAIL: agnos_abi_doc_parity: the cyrius peer defines syscall number(s) absent from the")
    print("      frozen contract — issuing one is an undefined call into the kernel:")
    for n in extra:
        print(f"        #{n}: {peer[n]}")
    sys.exit(1)

# ── axis 3: gaps are REPORTED, never fatal (see the header). ───────────────────────
missing = sorted(set(abi) - set(peer))
if missing:
    print(f"note: {len(missing)} contract syscall(s) have no cyrius peer yet (expected for newly")
    print( "      minted numbers — the kernel arm ships first and the peer lands on cyrius's")
    print( "      schedule; symlink#63 and readlink#70 both did):")
    for n in missing:
        print(f"        #{n} `{abi[n]}`")

print(f"PASS: agnos_abi_doc_parity (contract {len(abi)} syscalls, peer {len(peer)}; "
      f"{len(set(abi) & set(peer))} shared, 0 disagreements, {len(missing)} awaiting a peer)")
PY
