#!/bin/sh
# statfs_family_routed.sh — v6.6.6. `statfs`/`fstatfs` reach the KERNEL'S statfs on every
# target that has one, and the aarch64 rows stay below the compat rows they produce into.
#
# ⛔ THE DEFECT THIS PINS, MEASURED ON HEAD BEFORE THE FIX. aarch64-Linux's native statfs is
# 43 and fstatfs is 44, and BOTH are already x86-compat ESYSXLAT row SOURCES (accept 43→202,
# sendto 44→206). A compat row matches a NUMBER and cannot tell a native one from the x86
# one it is chasing, so a native-numbered `syscall(43, path, buf)` was reissued as accept(2):
#
#     2812264 accept(6293449,0x00007fb58354d220,[0]) = -1 errno=14 (Bad address)
#
# (qemu-aarch64 -strace, this tree, 2026-09-19.) statfs also had no NAME in either Linux peer,
# so the one ecosystem consumer — yukti's `filesystem_usage` — had to hardcode a number per
# arch and picked that 43; every ARM host has answered "statfs failed: errno 14" since the
# socket block landed at v6.2.10. A nameless syscall is structurally invisible to the
# raw-literal diagnostic too (its table is derived from names declared in BOTH peers), so
# nothing warned. The peers now spell the x86 numbers 137/138 and two ESYSXLAT rows renumber
# them. CHANGELOG [6.6.6]
#
# ⭐ WHY A GATE OF ITS OWN WHEN FOUR SYSCALL GATES ALREADY EXIST. They are all STATIC and all
# read artifacts of this repo: syscall_peer_kernel_agreement judges the PEER against a
# committed kernel table, esysxlat_row_order checks the chain against ITSELF, the shadow
# sweep compares the peers TO EACH OTHER. None of them RUNS the call. CLAUDE.md's rule — "a
# wrapper that COMPILES on five targets is not a wrapper that RUNS" — is exactly what was
# violated here, and the crossos tcyr that fixes it only executes on the cross-OS leg. Axes
# D and E below run the syscall on this box, on x86 and (under emulation) on aarch64, so a
# re-broken row reddens in `check.sh` rather than at the next release gate.
#
# ⚠ EMULATION IS NOT HARDWARE. Axis E runs under qemu-aarch64. It is a real aarch64 kernel
# ABI over a real Linux host, which is enough to see WHICH syscall was issued — and that is
# the whole defect — but tests/tcyr/crossos/statfs_family.tcyr on pi/ecb/ach/cass is the
# hardware verification, not this.
#
# MUTATION LEDGER (each applied to a scratch overlay, gate re-run, then discarded):
#   1. delete the `statfs 137→43` EW row from the ELF arm      -> FAIL axis A, naming it and
#      saying 137 now reaches the aarch64 kernel as `rt_sigtimedwait`; axis E FAILs too (the
#      probe exits 21, and -strace names neither statfs nor accept)
#   2. point the fstatfs row at 138→45 instead of 138→44       -> FAIL axis A: 45 is aarch64
#      `truncate`, not `fstatfs`, judged from tests/data/syscalls/aarch64.tbl. Probe exits 23.
#   3. move BOTH statfs rows above the ELF `accept 43→202` row -> FAIL axis A on ordering
#      ("row 16 (43->202) BELOW it matches that number"), and axis E prints the original
#      defect verbatim: `accept(6293507,0x7fac489f3a60,[0]) = -1 errno=14 (Bad address)`
#   4. change the arm64 Mach-O row to 137→157 (Darwin's LEGACY
#      statfs, a different and shifted struct)                 -> FAIL axis C on parity with
#      the x86 Mach-O backend ("arm64 137->157, x86 137->345. One of them was edited alone.")
#   5. point the probe's include at a module that does not exist -> FAIL loudly on the empty
#      binary on BOTH legs, not a silent skip (cycc on empty stdin exits 0 and emits a
#      runnable file, which is how an unmatched glob used to score a fake PASS in this tree)
#   6. shadow `stat` with a BSD-shaped stub on PATH (the Mac case) -> axis D prints its
#      no-oracle note, keeps its structural assertions, and the ok line stops claiming
#      agreement with coreutils. A GNU `stat` that then fails to answer is still a FAIL.
#   7. delete `fn sys_fstatfs` from the AGNOS peer (the shape this
#      gate shipped with, review fix 11c)                      -> FAIL axis B twice: the WRAP
#      row and the derived whole-family check, the second naming linux_common as the peer it
#      fails to mirror
#   8. delete `fn sys_fstatfs` from the PE peer                -> FAIL axis B the same two ways
#      for lib/syscalls_windows.cyr, which proves the derived check is not agnos-specific
#   9. rename all three wrappers in lib/syscalls_linux_common.cyr -> FAIL on the derived
#      check's own floor ("only 0 statfs-family wrappers found … floor 3"), so a canonical
#      peer that moves cannot silently leave the mirror check inspecting nothing
#  10. shadow `stat` on PATH with a GNU-shaped stub reporting f_bsize 4096 but f_frsize 1024
#      (legal — ext2 fragments, UFS) -> the `%S` version this gate shipped with FAILs both legs
#      ("f_bsize 4096, coreutils says 1024"), the `%s` version PASSes; and with the stub's `%s`
#      itself moved to 1024 the `%s` version FAILs, so the fix did not just silence the oracle
#  11. mutation 3 again, run against BOTH gate versions -> the shipped one printed "ok: …
#      below the compat row that claims 43" immediately BEFORE its own "FAIL: … row 16
#      (43->202) BELOW it"; this one prints the FAIL alone. Both exit 1 — the defect was the
#      log contradicting itself, which is what a reader skimming for `ok:` acts on
#  12. delete the `accept 43→202` compat row entirely -> the note fires AND the ok line now
#      reads "with nothing above it claiming 43" instead of asserting a compat row that is
#      gone; gate stays GREEN, because the borrow is then unforced but still correct
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

ARM=src/backend/aarch64/emit.cyr
X86=src/backend/x86/emit.cyr
KA=tests/data/syscalls/aarch64.tbl
KX=tests/data/syscalls/x86_64.tbl
CC=build/cycc
for f in "$ARM" "$X86" "$KA" "$KX" "$CC"; do
    [ -e "$f" ] || { echo "FAIL: statfs_family_routed: missing $f"; exit 1; }
done

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: statfs_family_routed: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM
FAIL=0
bad() { echo "FAIL: statfs_family_routed: $1"; FAIL=1; }
ok()  { echo "  ok: $1"; }

# ── axes A + B + C: static ─────────────────────────────────────────────────────────────
# The EXPECTED numbers are taken from the committed kernel tables (an outside fact) and the
# ACTUAL ones are decoded out of the emitter's instruction words — two different derivations,
# never the same file read twice.
python3 - "$ARM" "$X86" "$KA" "$KX" "$ROOT" <<'PY' || FAIL=1
import re, sys, os
arm, x86, ka, kx, ROOT = sys.argv[1:6]
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
    print(f"FAIL: statfs_family_routed: kernel tables parsed {len(tx)}/{len(ta)} rows "
          f"(floors 380/320) — this axis would judge everything 'not in the table'")
    sys.exit(1)

# The expected numbers, derived from the tables rather than written here.
inv_x = {v: k for k, v in tx.items()}
inv_a = {v: k for k, v in ta.items()}
try:
    SRC = {'statfs': inv_x['statfs'], 'fstatfs': inv_x['fstatfs']}
    DST = {'statfs': inv_a['statfs'], 'fstatfs': inv_a['fstatfs']}
except KeyError as e:
    print(f"FAIL: statfs_family_routed: {e} is not in the committed kernel tables")
    sys.exit(1)

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
macho, elf = body[k:e], body[:m] + body[e:]

# ── axis A: the ELF chain ──────────────────────────────────────────────────────────────
# cmp x8,#imm = 0xF1000000 | imm<<10 | 8<<5 | 0x1F ; movz x8,#imm = 0xD2800000 | imm<<5 | 8.
# Rn/Rd are inside the mask on purpose — dropping them admits the arg-shift movz words and
# yields plausible-but-wrong numbers (the trap two sibling gates already record).
words = [int(w, 16) for w in re.findall(r'EW\(S,\s*0x([0-9A-Fa-f]{8})\)', elf)]
rows, pend = [], None
for w in words:
    if (w & 0xFF00001F) == 0xF100001F:
        pend = (w >> 10) & 0xFFF
    elif (w & 0xFFE0001F) == 0xD2800008 and pend is not None:
        rows.append((pend, (w >> 5) & 0xFFFF)); pend = None
if len(rows) < 40:
    print(f"FAIL: statfs_family_routed: only {len(rows)} ELF rows decoded (floor 40) — the "
          f"encoding or the function shape moved and this axis inspects nothing")
    sys.exit(1)

for call in ('statfs', 'fstatfs'):
    s, want = SRC[call], DST[call]
    # ⚠ THE OK LINE BELOW IS GATED ON THIS MARK, which is the whole reason it is taken. It
    # used to sit in the else-branch of the alias-band check alone and never consulted `bad`,
    # so a row moved ABOVE the compat row it produces into printed "ok: … below the compat row
    # that claims 43" immediately BEFORE its own "FAIL: … row 16 (43->202) BELOW it matches
    # that number" — the log contradicting itself at the moment it matters most (the exit code
    # was right; a reader skimming for `ok:` was not). A per-call mark makes every failure this
    # loop can append — duplicate sources, wrong ordering, the alias band — suppress it.
    n_before = len(bad)
    hits = [(idx, dst) for idx, (a, dst) in enumerate(rows) if a == s]
    if not hits:
        bad.append(f"axis A: the ELF-aarch64 chain has NO row for x86 {call} ({s}). "
                   f"The peer declares {s}, so it reaches the aarch64 kernel verbatim as "
                   f"`{ta.get(s, 'unassigned')}` — the defect this gate exists for.")
        continue
    if len(hits) > 1:
        bad.append(f"axis A: {len(hits)} rows share source {s}; only the first can ever fire")
    idx, dst = hits[0]
    if dst != want:
        bad.append(f"axis A: {call} routes {s} -> {dst}, which is aarch64 "
                   f"`{ta.get(dst, 'unassigned')}`, not `{call}` ({want})")
        continue
    # ORDERING, both directions. The row PRODUCES `want`, which an x86-compat row above it
    # compares against; below that row it is safe, above it the call is re-rewritten.
    above = [k2 for k2, (a, _) in enumerate(rows) if a == want and k2 < idx]
    after = [k2 for k2, (a, _) in enumerate(rows) if a == want and k2 > idx]
    if after:
        k2 = after[0]
        bad.append(f"axis A: the {call} row (index {idx}) produces {want}, and row {k2} "
                   f"({want}->{rows[k2][1]}) BELOW it matches that number — every {call} "
                   f"would be reissued as `{ta.get(rows[k2][1], 'unassigned')}`. Move it down.")
    elif not above:
        # Not an error today, but say so: it means the compat row went away and the borrow
        # is no longer necessary, which is a fact worth reading in the log.
        print(f"  note: nothing in the chain now claims {want}; the {call} borrow of "
              f"{s} is no longer forced (it is still correct)")
    first_alias = min((k2 for k2, (a, _) in enumerate(rows) if a >= 1000), default=len(rows))
    if idx > first_alias:
        bad.append(f"axis A: the {call} row (index {idx}) sits INSIDE the >=1000 private "
                   f"alias band (starts at {first_alias}); the band must stay last")
    if len(bad) == n_before:
        # Say which compat row it is below, or that none claims the number any more — the
        # generic wording asserted a compat row existed even when the note above said it did not.
        where = (f"below the compat row at index {above[-1]} that claims {dst}" if above
                 else f"with nothing above it claiming {dst}")
        print(f"  ok: ELF-aarch64 routes {call} {s} -> {dst} at index {idx}, {where} and "
              f"outside the >=1000 alias band")

# ── axis C: both Mach-O backends, by capability ────────────────────────────────────────
# Darwin numbers are NOT derivable from the committed Linux tables, so they are pinned here
# and the pin carries its evidence: on ecb (arm64) and ach (Intel), 2026-09-19,
# `syscall(345,"/",buf)` and `syscall(346,fd,buf)` returned 0 and filled a buffer
# byte-identical to libc statfs()/fstatfs(), and <sys/syscall.h> on both says
# SYS_statfs64=345 / SYS_fstatfs64=346. Darwin's legacy statfs(157) was probed in the same
# run and fills a DIFFERENT, shifted struct — which is why 157 is wrong here even though it
# "works". What the gate enforces is that both backends agree, so a one-sided edit reddens.
DARWIN = {'statfs': 345, 'fstatfs': 346}
arm_rows = {int(a): int(b) for a, b in
            re.findall(r'_esx_arm\(S,\s*(\d+),\s*(\d+)\)', macho)}
xt = open(x86, encoding='utf-8').read()
i = xt.index('fn EMACHO_SYSXLAT(S): i64 {')
d, j = 0, i
while j < len(xt):
    if xt[j] == '{': d += 1
    elif xt[j] == '}':
        d -= 1
        if d == 0: break
    j += 1
x86_rows = {int(a): int(b, 16) & 0xFFFFFF for a, b in
            re.findall(r'_msx3?2?\(S,\s*(\d+),\s*0x([0-9A-Fa-f]+)\)', xt[i:j])}
if len(arm_rows) < 40 or len(x86_rows) < 40:
    print(f"FAIL: statfs_family_routed: axis C parsed {len(arm_rows)} arm / {len(x86_rows)} "
          f"x86 Mach-O rows (floor 40 each) — the row spelling moved")
    sys.exit(1)
for call, want in sorted(DARWIN.items()):
    s = SRC[call]
    a_dst, x_dst = arm_rows.get(s), x86_rows.get(s)
    if a_dst is None:
        bad.append(f"axis C: arm64-macOS has no Mach-O row for {call} ({s}); arm64-macOS "
                   f"resolves the aarch64-LINUX peer, so it emits {s} and would reach "
                   f"Darwin with a stale x16")
    if x_dst is None:
        bad.append(f"axis C: x86-macOS (EMACHO_SYSXLAT) has no row for {call} ({s}); the "
                   f"number reaches Darwin unclassed and SIGSYS-kills the process")
    if a_dst is not None and x_dst is not None:
        if a_dst != x_dst:
            bad.append(f"axis C: the two Mach-O backends DISAGREE on {call}: arm64 {s}->"
                       f"{a_dst}, x86 {s}->{x_dst}. One of them was edited alone.")
        elif a_dst != want:
            bad.append(f"axis C: both Mach-O backends route {call} {s}->{a_dst}, but the "
                       f"hardware-probed Darwin number is {want} (statfs64/fstatfs64). "
                       f"Darwin 157/158 are the LEGACY pair with a different struct.")
        else:
            print(f"  ok: both Mach-O backends route {call} {s} -> {want}")

# ── axis B: the peers name it, and none of them spells the shadowed native number ──────
DECL = re.compile(r'\b(SYS_[A-Z0-9_]+)\s*=\s*(\d+)\s*;')
PEERS = {
    'lib/syscalls_x86_64_linux.cyr':  SRC,
    'lib/syscalls_aarch64_linux.cyr': SRC,   # the BORROW: the x86 number, not native 43/44
    'lib/syscalls_macos.cyr':         SRC,
    'lib/syscalls_windows.cyr':       SRC,   # declared so PE source compiles; stub declines
}
NATIVE = {'statfs': DST['statfs'], 'fstatfs': DST['fstatfs']}
for rel, want in sorted(PEERS.items()):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        bad.append(f"axis B: {rel} is missing")
        continue
    got = {n: int(v) for n, v in DECL.findall(open(p, encoding='utf-8').read())}
    if len(got) < 20:
        bad.append(f"axis B: only {len(got)} SYS_* declarations parsed from {rel} (floor 20)"
                   f" — the peer's formatting moved and this axis is reading nothing")
        continue
    for call, num in sorted(want.items()):
        nm = 'SYS_' + call.upper()
        if nm not in got:
            bad.append(f"axis B: {rel} does not declare {nm}. Every peer names it, which is "
                       f"what stops a consumer hardcoding a number (yukti did, and its "
                       f"aarch64 arm ran accept)")
        elif got[nm] == NATIVE[call] and rel.endswith('aarch64_linux.cyr'):
            bad.append(f"axis B: {rel} declares {nm} = {got[nm]}, the aarch64 NATIVE number. "
                       f"That number is an x86-compat row source, so the call is reissued as "
                       f"something else. Use the x86 number {num} with the ESYSXLAT row.")
        elif got[nm] != num:
            bad.append(f"axis B: {rel} declares {nm} = {got[nm]}, want {num}")
n_ok = len(PEERS) * 2 - len([b for b in bad if b.startswith('axis B')])
if n_ok > 0:
    print(f"  ok: {n_ok} of {len(PEERS) * 2} peer declarations name the statfs pair correctly")

# The wrappers, one per shape. A name with no wrapper is what made ioctl latent for years.
WRAP = [
    ('lib/syscalls_linux_common.cyr', r'^fn sys_statfs\(path, buf\)',   'the 2-arg Linux/Darwin wrapper'),
    ('lib/syscalls_linux_common.cyr', r'^fn sys_fstatfs\(fd, buf\)',    'the fd wrapper'),
    ('lib/syscalls_linux_common.cyr', r'^fn statfs_bsize\(buf\)',       'the per-target f_bsize accessor'),
    ('lib/syscalls_windows.cyr',      r'^fn sys_statfs\(path, buf\)',   'the PE decline'),
    ('lib/syscalls_windows.cyr',      r'^fn sys_fstatfs\(fd, buf\)',    'the PE fd decline'),
    ('lib/syscalls_windows.cyr',      r'^fn statfs_bsize\(buf\)',       'the PE f_bsize accessor'),
    ('lib/syscalls_x86_64_agnos.cyr', r'^fn sys_statfs\(path, pathlen, buf\)', "agnos's own 3-arg shape"),
    ('lib/syscalls_x86_64_agnos.cyr', r'^fn sys_fstatfs\(fd, buf\)',    "agnos's fd decline"),
    ('lib/syscalls_x86_64_agnos.cyr', r'^fn statfs_bsize\(buf\)',       "agnos's f_bsize accessor"),
]
for rel, pat, what in WRAP:
    p = os.path.join(ROOT, rel)
    if not (os.path.exists(p) and re.search(pat, open(p, encoding='utf-8').read(), re.M)):
        bad.append(f"axis B: {rel} is missing {what} (/{pat}/)")

# ⛔ AND THE PEER SET CHECKED WHOLE — the name list DERIVED from the canonical peer, not
# hand-listed like WRAP above. A wrapper shipped on FOUR of the five targets hides in the
# gap between two WRAP rows, which is exactly what happened here: `sys_fstatfs` landed in
# linux_common (x86_64 / aarch64 / macOS) and on the PE peer, and the agnos peer got the
# enum and the accessor but not the wrapper, so `CYRIUS_TARGET_AGNOS=1` on portable source
# was a hard `refusing to emit binary with 1 reachable undefined function(s)` — a build
# failure, not a degraded answer. Adding the missing WRAP row alone would leave the NEXT
# name in the family depending on someone remembering to add a row, so the family is read
# off lib/syscalls_linux_common.cyr and the two STANDALONE peers (Windows and agnos; every
# other target includes linux_common) must mirror it, whatever each signature is.
lc = open(os.path.join(ROOT, 'lib/syscalls_linux_common.cyr'), encoding='utf-8').read()
FAMILY = sorted(set(re.findall(r'^fn ([a-z0-9_]*statfs[a-z0-9_]*)\(', lc, re.M)))
if len(FAMILY) < 3:
    bad.append(f"axis B: only {len(FAMILY)} statfs-family wrappers found in "
               f"lib/syscalls_linux_common.cyr (floor 3) — the canonical peer moved and this "
               f"check has nothing to mirror")
else:
    for rel in ('lib/syscalls_windows.cyr', 'lib/syscalls_x86_64_agnos.cyr'):
        t = open(os.path.join(ROOT, rel), encoding='utf-8').read()
        gap = [f for f in FAMILY if not re.search(rf'^fn {f}\(', t, re.M)]
        if gap:
            bad.append(f"axis B: {rel} is STANDALONE and defines no {', '.join(gap)}, which "
                       f"lib/syscalls_linux_common.cyr does — portable source naming it "
                       f"fails to COMPILE for that target rather than to answer")

# Every peer publishes the offset enum, so cross-platform source names the fields
# unconditionally — the half-fix trap syscalls_windows.cyr's Stat comment records.
for rel in ('lib/syscalls_linux_common.cyr', 'lib/syscalls_windows.cyr',
            'lib/syscalls_x86_64_agnos.cyr'):
    t = open(os.path.join(ROOT, rel), encoding='utf-8').read()
    miss = [m for m in ('STATFS_BSIZE', 'STATFS_BLOCKS', 'STATFS_BFREE', 'STATFS_BAVAIL',
                        'STATFS_BUFSZ') if not re.search(rf'\b{m}\s*=\s*\d+\s*;', t)]
    if miss:
        bad.append(f"axis B: {rel} does not define {', '.join(miss)} — a PE or agnos build of "
                   f"a consumer that names them fails to COMPILE")

for b in bad:
    print("FAIL: statfs_family_routed: " + b)
sys.exit(1 if bad else 0)
PY

# ── axes D + E: RUN it ─────────────────────────────────────────────────────────────────
cat > "$D/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"

# Deliberately no fmt/str include: this probe is built by BOTH the host fork and the
# aarch64 cross fork, and the fewer modules it drags in the fewer unrelated reasons it has
# to go red. A hand-rolled decimal writer is four lines.
fn put_num(n): i64 {
    var d[24];
    var i = 24;
    var v = n;
    if (v == 0) { i = i - 1; store8(&d + i, 48); }
    while (v > 0) {
        i = i - 1;
        store8(&d + i, 48 + (v % 10));
        v = v / 10;
    }
    sys_write(1, &d + i, 24 - i);
    sys_write(1, " ", 1);
    return 0;
}

fn main(): i64 {
    alloc_init();
    var buf[STATFS_BUFSZ];
    if (sys_statfs("/", &buf) < 0) { return 21; }
    put_num(statfs_bsize(&buf));
    put_num(load64(&buf + STATFS_BLOCKS));
    put_num(load64(&buf + STATFS_BAVAIL));
    sys_write(1, "\n", 1);
    # fstatfs on a descriptor for the same mount must describe the same filesystem.
    var fd = sys_open("/", 0, 0);
    if (fd < 0) { return 22; }
    var fbuf[STATFS_BUFSZ];
    if (sys_fstatfs(fd, &fbuf) < 0) { return 23; }
    sys_close(fd);
    if (statfs_bsize(&fbuf) != statfs_bsize(&buf)) { return 24; }
    if (load64(&fbuf + STATFS_BLOCKS) != load64(&buf + STATFS_BLOCKS)) { return 25; }
    return 0;
}
EOF

# The EXPECTED values come from coreutils' statfs binding, not from the probe — a different
# implementation of the same syscall against the same mount.
#
# ⚠ Gated on GNU coreutils being PRESENT rather than on an OS guess, and the two branches are
# deliberately different: where `stat` can answer, a disagreement is a FAILURE; where it cannot
# (BSD `stat -f` is a format string, not a filesystem query — this file is runnable from a Mac),
# the comparison is skipped with a note and the structural assertions below still run. Silently
# dropping the oracle on the host that HAS it would be the vacuous shape; failing on a host that
# never had it would be a false red.
WANT=""
if stat --version 2>/dev/null | grep -q GNU; then
    # ⚠ `%s`, NOT `%S`. coreutils calls `%s` the "block size (for faster transfers)" — f_bsize,
    # which is what the probe prints — and `%S` the "fundamental block size (for block counts)",
    # which is f_frsize, a DIFFERENT field. This gate shipped with `%S` and read green anyway
    # because ext4 sets both to 4096, so the oracle was not the comparison the header claims and
    # would have false-RED on any filesystem where the two differ (ext2 with a fragment size, UFS).
    # An oracle that happens to agree on the developer's box is the vacuous shape one step out.
    WANT=$(stat -f -c '%s %b' / 2>/dev/null || true)
    case "$WANT" in
        [0-9]*" "[0-9]*) ;;
        *) bad "axis D: GNU stat is installed but \`stat -f -c '%s %b' /\` gave '$WANT'; this
      axis needs coreutils' own statfs to compare against and will not assert against itself"
           WANT="" ;;
    esac
else
    echo "  note: no GNU coreutils \`stat\` — axis D keeps its structural assertions but has no
        independent oracle to compare the numbers against on this host"
fi

run_leg() {   # run_leg <name> <compiler-src-fork> <runner...>
    leg=$1; fork=$2; shift 2
    ( ulimit -c 0; cat "$ROOT/$fork" | "$ROOT/$CC" > "$D/cc_$leg" ) 2>/dev/null || true
    if [ ! -s "$D/cc_$leg" ]; then
        bad "$leg: $fork did not build a compiler (empty output)"; return
    fi
    chmod +x "$D/cc_$leg"
    ( ulimit -c 0; cat "$D/probe.cyr" | "$D/cc_$leg" > "$D/p_$leg" ) 2>"$D/e_$leg" || true
    if [ ! -s "$D/p_$leg" ]; then
        bad "$leg: the probe produced an EMPTY binary — $(head -c 200 "$D/e_$leg")"; return
    fi
    chmod +x "$D/p_$leg"
    set +e
    out=$( ulimit -c 0; "$@" "$D/p_$leg" 2>"$D/r_$leg" )
    rc=$?
    set -e
    if [ "$rc" != 0 ]; then
        bad "$leg: the probe exited $rc (21 statfs failed, 22 open, 23 fstatfs, 24/25 the two
      calls disagree) — $(head -c 200 "$D/r_$leg")"
        return
    fi
    bs=$(echo "$out"  | awk '{print $1}')
    blk=$(echo "$out" | awk '{print $2}')
    av=$(echo "$out"  | awk '{print $3}')
    case "$bs$blk$av" in ''|*[!0-9]*) bad "$leg: probe printed '$out', not three numbers"; return ;; esac
    # Structural facts no wrong syscall produces: a power-of-two block size in range, a
    # non-empty filesystem, and free <= total.
    if [ "$bs" -lt 512 ] || [ "$bs" -gt 1048576 ] || [ $(( bs & (bs - 1) )) -ne 0 ]; then
        bad "$leg: f_bsize = $bs is not a power of two in [512, 1048576]"; return
    fi
    if [ "$blk" -le 0 ] || [ "$av" -lt 0 ] || [ "$av" -gt "$blk" ]; then
        bad "$leg: f_blocks = $blk / f_bavail = $av is not a plausible filesystem"; return
    fi
    if [ -n "$WANT" ]; then
        wbs=$(echo "$WANT" | awk '{print $1}'); wblk=$(echo "$WANT" | awk '{print $2}')
        [ "$bs" = "$wbs" ] || { bad "$leg: f_bsize $bs, coreutils says $wbs"; return; }
        [ "$blk" = "$wblk" ] || { bad "$leg: f_blocks $blk, coreutils says $wblk"; return; }
    fi
    if [ -n "$WANT" ]; then
        ok "$leg: statfs/fstatfs agree with each other and with coreutils (bsize $bs, blocks $blk)"
    else
        ok "$leg: statfs/fstatfs agree with each other, values structurally sane (bsize $bs, blocks $blk) — no oracle on this host"
    fi
}

run_leg host src/main.cyr

# aarch64 under emulation. NOT hardware — tests/tcyr/crossos/statfs_family.tcyr on pi/ecb/
# ach/cass is. What this leg settles is WHICH syscall the chain issues, which is the defect.
if command -v qemu-aarch64 > /dev/null 2>&1; then
    run_leg aarch64 src/main_aarch64.cyr timeout 120 qemu-aarch64
    if [ -s "$D/p_aarch64" ]; then
        ( ulimit -c 0; timeout 120 qemu-aarch64 -strace "$D/p_aarch64" ) > /dev/null 2>"$D/st" || true
        if grep -q 'accept(' "$D/st"; then
            bad "aarch64: -strace shows accept(), the original defect: $(grep -m1 'accept(' "$D/st")"
        elif grep -q 'statfs(' "$D/st"; then
            ok "aarch64: -strace names the issued call statfs, not accept"
        else
            # Neither name present means the number reached the kernel as a THIRD call (with
            # the row deleted, 137 is aarch64 rt_sigtimedwait) — or the trace stopped working.
            # Both are failures, and the trace tail says which.
            bad "aarch64: -strace names NEITHER statfs nor accept, so the chain issued some
      other call entirely (or -strace stopped working). Last traced calls:
      $(grep -oE '[a-z_0-9]+\(' "$D/st" | tail -5 | tr '\n' ' ')"
        fi
    fi
else
    echo "  SKIP: qemu-aarch64 not installed (the crossos tcyr covers pi hardware)"
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: statfs_family_routed (ELF rows ordered below the compat rows they produce, both"
echo "      Mach-O backends agree, 4 peers name the pair, and the call RUNS on x86 + aarch64)"
