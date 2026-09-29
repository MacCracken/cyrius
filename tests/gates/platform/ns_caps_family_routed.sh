#!/bin/sh
# ns_caps_family_routed.sh — v6.6.8. unshare / chroot / pivot_root / capget / capset /
# process_vm_readv / process_vm_writev / mknodat are NAMED in every peer, WRAPPED on every
# target, and on ELF-aarch64 the x86 number each peer spells reaches the kernel as THAT call.
#
# ⛔ THE DEFECT THIS PINS, MEASURED ON THE 6.6.7 TREE under `qemu-aarch64 -strace`:
#     syscall(161, "/nonexistent-root")  →  sethostname(…) = -1 errno=1
#     syscall(272, 0)                    →  kcmp(0, …)     = -1 errno=3
#     syscall(155, "/nx1", "/nx2")       →  getpgid(…)     = -1 errno=3
#     syscall(125, 0, 0)                 →  sched_get_priority_max(0, …) = 0
#     syscall(126, 0, 0)                 →  sched_get_priority_min(0, …) = 0
#     syscall(310, …) / (259, …)         →  Unknown syscall
# None of the eight had a name in either Linux peer, so consumers wrote numbers: kavach
# (namespaces + rootfs entry, refused on aarch64 until this landed), takumi, shakti (its
# capability drop ran the scheduler queries — silently a no-op on every ARM host), mirshi,
# vani (its aarch64 FIFO tests skipped: native mknodat 33 is the dup2 33→dup3 row source).
# A NAMELESS number is structurally invisible to the raw-literal diagnostic (its table is
# derived from names declared in BOTH peers), so nothing warned. The peers now spell the x86
# numbers and eight ESYSXLAT rows renumber them. CHANGELOG [6.6.8]
#
# Axes:
#   A  the ELF-aarch64 chain has exactly one row per x86 number, landing on the aarch64
#      number the COMMITTED KERNEL TABLE gives for that name (tests/data/syscalls/*.tbl — an
#      outside fact; the rows are DECODED from the instruction words, never read off a
#      comment), below every row that compares against its product, above the alias band.
#   B  x86_64-linux / aarch64-linux / macOS / Windows peers declare each SYS_* as the x86
#      number; the agnos peer declares NONE (a Linux number there issues a live agnos call —
#      that peer's own documented rule); AUDIT_ARCH_NATIVE is the right AUDIT_ARCH_* value.
#   C  every wrapper exists in lib/syscalls_linux_common.cyr with a Darwin -78 arm, and in the
#      two STANDALONE peers (Windows, agnos) as a -38 stub — the family list is DERIVED from
#      linux_common, so a ninth wrapper cannot ship on three targets and not the other two.
#   D  RUN it: a probe built by the aarch64 cross compiler (built from THIS tree) under
#      `qemu-aarch64 -strace` issues each call by name and none of the calls above. Visibly
#      skipped without qemu. ⚠ Emulation is not hardware — tests/tcyr/crossos/
#      ns_rootfs_syscalls.tcyr on pi is; this leg settles WHICH syscall the chain issues.
#
# MUTATION LEDGER (each on a scratch copy, gate re-run, discarded):
#   1. delete the `chroot 161→51` EW row                 -> FAIL A ("NO row for x86 chroot
#      (161) … reaches the aarch64 kernel verbatim as `sethostname`") and FAIL D (strace shows
#      sethostname, no chroot)
#   2. move the `chroot 161→51` row ABOVE getsockname 51→204 -> FAIL A (row … BELOW it matches
#      51) and FAIL D (strace shows getsockname)
#   3. point capget at 125→91                             -> FAIL A (`capset`, not `capget`)
#   4. declare SYS_CHROOT = 51 (native) in the aarch64 peer -> FAIL B (the native number)
#   5. delete `fn sys_mknodat` from the agnos peer          -> FAIL C (STANDALONE … no sys_mknodat)
#   6. drop sys_unshare's Darwin arm in linux_common        -> FAIL C (no -78 macOS arm)
#   7. declare `SYS_UNSHARE = 272;` in the agnos peer       -> FAIL B
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

ARM=src/backend/aarch64/emit.cyr
KA=tests/data/syscalls/aarch64.tbl
KX=tests/data/syscalls/x86_64.tbl
CC=build/cycc
for f in "$ARM" "$KA" "$KX" "$CC"; do
    [ -e "$f" ] || { echo "FAIL: ns_caps_family_routed: missing $f"; exit 1; }
done

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: ns_caps_family_routed: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM
FAIL=0
bad() { echo "FAIL: ns_caps_family_routed: $1"; FAIL=1; }
ok()  { echo "  ok: $1"; }

CALLS="unshare chroot pivot_root capget capset process_vm_readv process_vm_writev mknodat"

# ── axes A + B + C: static ─────────────────────────────────────────────────────────────
python3 - "$ARM" "$KA" "$KX" "$ROOT" "$CALLS" <<'PY' || FAIL=1
import re, sys, os
arm, ka, kx, ROOT, calls = sys.argv[1:6]
CALLS = calls.split()
bad = []

def table(p):
    t = {}
    for ln in open(p, encoding='utf-8'):
        s = ln.split('#', 1)[0].split()
        if len(s) == 2 and s[0].isdigit():
            t[int(s[0])] = s[1]
    return t

ta, tx = table(ka), table(kx)
if len(ta) < 320 or len(tx) < 380:
    print(f"FAIL: ns_caps_family_routed: kernel tables parsed {len(tx)}/{len(ta)} rows (floors 380/320)")
    sys.exit(1)
inv_x = {v: k for k, v in tx.items()}
inv_a = {v: k for k, v in ta.items()}
try:
    SRC = {c: inv_x[c] for c in CALLS}
    DST = {c: inv_a[c] for c in CALLS}
except KeyError as e:
    print(f"FAIL: ns_caps_family_routed: {e} is not in the committed kernel tables")
    sys.exit(1)

# The ELF arm of ESYSXLAT = the function body minus its `_TARGET_MACHO == 2` branch.
src = open(arm, encoding='utf-8').read()
i = src.index('fn ESYSXLAT(S): i64 {')
d, j = 0, i
while j < len(src):
    if src[j] == '{': d += 1
    elif src[j] == '}':
        d -= 1
        if d == 0: break
    j += 1
body = src[i:j]
m = body.find('_TARGET_MACHO == 2')
k = body.index('{', m); d, e = 0, k
while e < len(body):
    if body[e] == '{': d += 1
    elif body[e] == '}':
        d -= 1
        if d == 0: break
    e += 1
elf = body[:m] + body[e:]

# cmp x8,#imm = 0xF100011F | imm<<10 ; movz x8,#imm = 0xD2800008 | imm<<5. Rn/Rd are in the
# mask on purpose: dropping them admits the arg-shift movz words (x0..x5) as fake rows.
words = [int(w, 16) for w in re.findall(r'EW\(S,\s*0x([0-9A-Fa-f]{8})\)', elf)]
rows, pend = [], None
for w in words:
    if (w & 0xFF0003FF) == 0xF100011F:
        pend = (w >> 10) & 0xFFF
    elif (w & 0xFFE0001F) == 0xD2800008 and pend is not None:
        rows.append((pend, (w >> 5) & 0xFFFF)); pend = None
if len(rows) < 40:
    print(f"FAIL: ns_caps_family_routed: only {len(rows)} ELF rows decoded (floor 40) — the "
          f"encoding or the function shape moved and axis A inspects nothing")
    sys.exit(1)
first_alias = min((n for n, (a, _) in enumerate(rows) if a >= 1000), default=len(rows))

# ── axis A ─────────────────────────────────────────────────────────────────────────────
for c in CALLS:
    s, want = SRC[c], DST[c]
    n0 = len(bad)
    hits = [(n, dst) for n, (a, dst) in enumerate(rows) if a == s]
    if not hits:
        bad.append(f"axis A: the ELF-aarch64 chain has NO row for x86 {c} ({s}); the peer "
                   f"declares {s}, so it reaches the aarch64 kernel verbatim as "
                   f"`{ta.get(s, 'unassigned')}`")
        continue
    if len(hits) > 1:
        bad.append(f"axis A: {len(hits)} rows share source {s}; only the first can ever fire")
    n, dst = hits[0]
    if dst != want:
        bad.append(f"axis A: {c} routes {s} -> {dst}, which is aarch64 "
                   f"`{ta.get(dst, 'unassigned')}`, not `{c}` ({want})")
        continue
    later = [n2 for n2, (a, _) in enumerate(rows) if a == want and n2 > n]
    if later:
        n2 = later[0]
        bad.append(f"axis A: the {c} row (index {n}) produces {want}, and row {n2} "
                   f"({want}->{rows[n2][1]}) BELOW it matches that number — every {c} would "
                   f"be reissued as `{ta.get(rows[n2][1], 'unassigned')}`. Move it down.")
    if n > first_alias:
        bad.append(f"axis A: the {c} row (index {n}) sits inside the >=1000 private alias "
                   f"band (starts at {first_alias}); the band must stay last")
    if len(bad) == n0:
        print(f"  ok: ELF-aarch64 routes {c} {s} -> {want} at index {n}")

# ── axis B ─────────────────────────────────────────────────────────────────────────────
DECL = re.compile(r'\b(SYS_[A-Z0-9_]+)\s*=\s*(\d+)\s*;')
def rd(rel): return open(os.path.join(ROOT, rel), encoding='utf-8').read()
for rel in ('lib/syscalls_x86_64_linux.cyr', 'lib/syscalls_aarch64_linux.cyr',
            'lib/syscalls_macos.cyr', 'lib/syscalls_windows.cyr'):
    got = {nm: int(v) for nm, v in DECL.findall(rd(rel))}
    if len(got) < 20:
        bad.append(f"axis B: only {len(got)} SYS_* declarations parsed from {rel} (floor 20)")
        continue
    n0 = len(bad)
    for c in CALLS:
        nm = 'SYS_' + c.upper()
        if nm not in got:
            bad.append(f"axis B: {rel} does not declare {nm} — a consumer that names it fails to "
                       f"COMPILE there, and the fallback is a hardcoded number")
        elif got[nm] == DST[c] and 'aarch64' in rel and DST[c] != SRC[c]:
            bad.append(f"axis B: {rel} declares {nm} = {got[nm]}, the aarch64 NATIVE number; "
                       f"spell the x86 number {SRC[c]} and let the ESYSXLAT row renumber it")
        elif got[nm] != SRC[c]:
            bad.append(f"axis B: {rel} declares {nm} = {got[nm]}, want the x86 number {SRC[c]}")
    if len(bad) == n0:
        print(f"  ok: {rel} names all {len(CALLS)} as the x86 numbers")
ag = {nm for nm, _ in DECL.findall(rd('lib/syscalls_x86_64_agnos.cyr'))}
minted = sorted(nm for nm in ('SYS_' + c.upper() for c in CALLS) if nm in ag)
if minted:
    bad.append(f"axis B: lib/syscalls_x86_64_agnos.cyr declares {', '.join(minted)}. agnos owns "
               f"its own syscall space; a Linux number there issues whatever agnos call owns it "
               f"(the peer's documented rule) — decline in the wrapper instead")
AUDIT = {'lib/syscalls_x86_64_linux.cyr': 0xC000003E, 'lib/syscalls_aarch64_linux.cyr': 0xC00000B7,
         'lib/syscalls_macos.cyr': 0xC000003E}
for rel, want in AUDIT.items():
    mm = re.findall(r'\bAUDIT_ARCH_NATIVE\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*;', rd(rel))
    if len(mm) != 1 or int(mm[0], 0) != want:
        bad.append(f"axis B: {rel} must declare AUDIT_ARCH_NATIVE = {want:#x} exactly once "
                   f"(found {mm})")
if not any(b.startswith('axis B: lib/syscalls_x86_64_agnos') or 'AUDIT' in b for b in bad):
    print("  ok: agnos mints none of them; AUDIT_ARCH_NATIVE is right in all three peers")

# ── axis C ─────────────────────────────────────────────────────────────────────────────
lc = rd('lib/syscalls_linux_common.cyr')
fam = []
for c in CALLS:
    fn = 'sys_' + c
    mm = re.search(rf'^fn {fn}\(([^)]*)\)[^{{]*\{{(.*?)^\}}', lc, re.M | re.S)
    if not mm:
        bad.append(f"axis C: lib/syscalls_linux_common.cyr defines no {fn}")
        continue
    fam.append((fn, mm.group(1)))
    if not re.search(r'#ifdef CYRIUS_TARGET_MACOS\s*\n\s*return 0 - 78;', mm.group(2)):
        bad.append(f"axis C: {fn} has no `#ifdef CYRIUS_TARGET_MACOS return 0 - 78;` arm — "
                   f"Darwin has no such call, so the number would reach the Mach-O emit")
for rel in ('lib/syscalls_windows.cyr', 'lib/syscalls_x86_64_agnos.cyr'):
    t = rd(rel)
    gap = [fn for fn, _ in fam
           if not re.search(rf'^fn {fn}\([^)]*\)[^{{]*\{{\s*return 0 - 38;\s*\}}', t, re.M)]
    if gap:
        bad.append(f"axis C: {rel} is STANDALONE and has no -38 stub for {', '.join(gap)} — "
                   f"portable source naming it fails to COMPILE for that target")
if len(fam) == len(CALLS) and not any(b.startswith('axis C') for b in bad):
    print(f"  ok: all {len(fam)} wrappers exist with a Darwin -78 arm, and as -38 stubs on PE and agnos")

for b in bad:
    print("FAIL: ns_caps_family_routed: " + b)
sys.exit(1 if bad else 0)
PY

# ── axis D: RUN it (aarch64 under qemu, -strace names the call) ─────────────────────────
if command -v qemu-aarch64 > /dev/null 2>&1; then
    ( ulimit -c 0; "$ROOT/$CC" < "$ROOT/src/main_aarch64.cyr" > "$D/cc_a64" ) 2>/dev/null || true
    if [ ! -s "$D/cc_a64" ]; then
        bad "axis D: src/main_aarch64.cyr did not build a cross compiler (empty output)"
    else
        chmod +x "$D/cc_a64"
        cat > "$D/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var hdr[8];
    var buf[32];
    store32(&hdr, 0);
    store32(&hdr + 4, 0);
    sys_unshare(0);
    sys_chroot("/cyr_ns_gate_no_root");
    sys_pivot_root("/cyr_ns_gate_a", "/cyr_ns_gate_b");
    sys_capget(&hdr, 0);
    sys_capset(&hdr, &buf);
    sys_process_vm_readv(1, &buf, 0, &buf, 0, 0);
    sys_process_vm_writev(1, &buf, 0, &buf, 0, 0);
    sys_mknodat(0 - 100, "/cyr_ns_gate_no_dir/node", 4480, 0);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
        ( ulimit -c 0; "$D/cc_a64" < "$D/probe.cyr" > "$D/probe" ) 2>"$D/probe.err" || true
        if [ ! -s "$D/probe" ]; then
            bad "axis D: the aarch64 probe produced an EMPTY binary — $(head -c 200 "$D/probe.err")"
        else
            chmod +x "$D/probe"
            ( cd "$D" && ulimit -c 0 && qemu-aarch64 -strace ./probe ) > "$D/strace" 2>&1 || true
            for c in $CALLS; do
                if grep -q "^[0-9]* $c(" "$D/strace"; then :; else
                    bad "axis D: -strace shows no $c( call — the probe's sys_$c reached the kernel as something else"
                fi
            done
            wrong=$(grep -E '^[0-9]+ (sethostname|kcmp|getpgid|sched_get_priority_(max|min)|getsockname|socket|dup3)\(|Unknown syscall' "$D/strace" || true)
            if [ -n "$wrong" ]; then
                bad "axis D: the probe issued a call it never asked for:
$wrong"
            fi
            [ "$FAIL" = 0 ] && ok "axis D: qemu-aarch64 -strace shows all eight by name, none of the calls they used to become"
        fi
    fi
else
    echo "  SKIP: ns_caps_family_routed axis D — qemu-aarch64 not installed (the static axes still ran)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

if [ "$FAIL" = 0 ]; then
    # 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
    if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: ns_caps_family_routed — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
    echo "PASS: ns_caps_family_routed"
    exit 0
fi
exit 1
