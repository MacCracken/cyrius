#!/bin/sh
# Gate: no aarch64 syscall is SHADOWED by an x86-compat ESYSXLAT row (v6.5.37).
#
# THE CLASS. `ESYSXLAT` (src/backend/aarch64/emit.cyr) is a sequential cmp/b.ne chain that
# rewrites x86 syscall numbers into aarch64 ones so x86-authored code runs on ARM. A compat
# row matches on a NUMBER and cannot tell an x86 number from an aarch64 native number that
# happens to equal it. So whenever `lib/syscalls_aarch64_linux.cyr` declares a NATIVE number
# that collides with an x86 number the chain rewrites, the call is silently reissued as a
# completely different syscall — no diagnostic, every gate green.
#
# Shipped occurrences:
#   v6.5.36  ppoll(73)      -> flock(2)     and  signalfd4(74) -> fsync(2)
#            kybernet's entire aarch64 target was non-functional; filed from outside.
#   v6.5.37  umount2(39)    -> getpid(2)          [LIVE — measured]
#            epoll_pwait(22)-> pipe2(59)           [latent: nothing called it]
#
# `sys_umount2("/nonexistent", 0)` returned **1179922** under qemu-aarch64 — a PID.
#
# ⭐ WHY A STRUCTURAL SWEEP RATHER THAN TWO MORE ASSERTIONS: the 6.5.36 fix added the two
# numbers it was told about, and this gate's sweep then found two more in the same table. A
# gate that pins the two known symptoms would have shipped green over both. This one asserts
# the PROPERTY — no declared native number is rewritten — so occurrence five cannot ship.
#
# ⛔ THE DISCRIMINATOR IS LOAD-BEARING, AND A RAW COLLISION LIST IS WRONG WITHOUT IT.
# Five declarations (fsync 74, fdatasync 75, newfstatat 262, faccessat 269, utimensat 280)
# ARE rewritten and are CORRECT: the documented pattern is to declare the X86 number and let
# ESYSXLAT renumber it. The test is therefore not "is it rewritten?" but "is the declared
# value the x86 number for THIS syscall (intended) or the aarch64 native one (shadowed)?" —
# answered by comparing against the x86 peer's declaration of the same name.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: aarch64_syscall_shadow: $1"; exit 1; }
EMIT="$ROOT/src/backend/aarch64/emit.cyr"
A64="$ROOT/lib/syscalls_aarch64_linux.cyr"
X86="$ROOT/lib/syscalls_x86_64_linux.cyr"
for f in "$EMIT" "$A64" "$X86"; do [ -f "$f" ] || fail "missing $f"; done

python3 - "$EMIT" "$A64" "$X86" <<'PY' || exit 1
import re, sys
emit, a64p, x86p = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(emit, encoding='utf-8').read()

# Isolate ESYSXLAT, then drop the Mach-O block: those rows target BSD numbers and say
# nothing about the ELF chain under test.
i = src.index('fn ESYSXLAT(S): i64 {')
d = 0; j = i
while j < len(src):
    if src[j] == '{': d += 1
    elif src[j] == '}':
        d -= 1
        if d == 0: break
    j += 1
body = src[i:j]
m = body.find('_TARGET_MACHO == 2')
if m > 0:
    k = body.index('{', m); d = 0; e = k
    while e < len(body):
        if body[e] == '{': d += 1
        elif body[e] == '}':
            d -= 1
            if d == 0: break
        e += 1
    body = body[:m] + body[e:]

# cmp x8,#imm = 0xF1000000 | imm<<10 | 8<<5 | 0x1F   ;   movz x8,#imm = 0xD2800000 | imm<<5 | 8
words = [int(w, 16) for w in re.findall(r'EW\(S,\s*0x([0-9A-Fa-f]{8})\)', body)]
rows = []; pend = None
for w in words:
    if (w & 0xFF00001F) == 0xF100001F:
        pend = (w >> 10) & 0xFFF
    elif (w & 0xFFE0001F) == 0xD2800008 and pend is not None:
        rows.append((pend, (w >> 5) & 0xFFFF)); pend = None

if len(rows) < 20:
    print(f"FAIL: aarch64_syscall_shadow: only {len(rows)} ESYSXLAT rows decoded (expected >= 20) "
          f"— the encoding or the function shape changed and this gate is not inspecting anything")
    sys.exit(1)

froms = {}
for a, b in rows:
    froms.setdefault(a, []).append(b)

def decls(path):
    return {n: int(v) for n, v in re.findall(r'^\s*(SYS_[A-Z0-9_]+)\s*=\s*(\d+)\s*;', open(path, encoding='utf-8').read(), re.M)}

# Declarations that ARE rewritten and are CORRECT, but that the x86-peer comparison cannot
# confirm because the x86 peer does not declare the constant at all. Each entry is a
# deliberate, reviewable statement that the number is the X86 one for that syscall and the
# ESYSXLAT row renumbers it to the aarch64 native. Keep this list minimal: a new entry is a
# claim that must be checked against the real syscall tables, not a way to silence the gate.
#   faccessat — x86 269 -> aarch64 48. syscalls_x86_64_linux.cyr has no SYS_FACCESSAT
#   because nothing on that peer needs the constant.
ALLOW = {"SYS_FACCESSAT": 269}

a64, x86 = decls(a64p), decls(x86p)
if len(a64) < 50:
    print(f"FAIL: aarch64_syscall_shadow: only {len(a64)} aarch64 declarations parsed (expected >= 50)")
    sys.exit(1)

shadowed, intended = [], []
for name, n in sorted(a64.items()):
    if n >= 1000:          # the private alias band: deliberately un-mintable numbers
        continue
    if n not in froms:
        continue
    if x86.get(name) == n:  # declared the x86 number on purpose; the row is the renumber
        intended.append((name, n, froms[n]))
    elif ALLOW.get(name) == n:
        intended.append((name, n, froms[n]))
    else:
        shadowed.append((name, n, froms[n], x86.get(name)))

if shadowed:
    print("FAIL: aarch64_syscall_shadow: declared NATIVE numbers are rewritten by x86-compat rows:")
    for name, n, to, xn in shadowed:
        print(f"    {name} = {n} -> reissued as {to[0]}   (x86 number for this call is {xn};")
        print(f"        move it to the private alias band: {name} = {1000 + n}, with an")
        print(f"        ESYSXLAT row {1000 + n}->{n} appended LAST in the chain)")
    sys.exit(1)

# The band's ordering invariant: an alias row PRODUCES a native number, and a compat row
# above it compares against that same number. Placed earlier, the alias is silently reissued
# as the shim's syscall — i.e. the identical bug, reintroduced by a reordering.
last_compat = max((idx for idx, (a, _) in enumerate(rows) if a < 1000), default=-1)
first_alias = min((idx for idx, (a, _) in enumerate(rows) if a >= 1000), default=len(rows))
if first_alias < last_compat:
    print(f"FAIL: aarch64_syscall_shadow: an alias-band row (index {first_alias}) sits ABOVE an "
          f"x86-compat row (index {last_compat}). The band must stay LAST: an alias produces a "
          f"native number that a compat row above it matches, so the alias would be re-rewritten.")
    sys.exit(1)

print(f"PASS: aarch64_syscall_shadow ({len(rows)} rows, {len(a64)} declarations, "
      f"0 shadowed, {len(intended)} intended x86-number renumbers, alias band last)")
PY
