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
#
# MUTATION LEDGER (each applied, gate re-run, reverted):
#   1. lib/syscalls_aarch64_linux.cyr SYS_UMOUNT2 back to native 39 -> FAIL, names it and
#      prints the alias-band fix (v6.5.37)
#   2. move an alias-band row above the x86-compat rows -> FAIL on the ordering axis (v6.5.37)
#   3. rename SYS_FACCESSAT on the x86 peer (i.e. undo what retired the ALLOW entry)
#      -> FAIL "SYS_FACCESSAT = 269 -> reissued as 48" (v6.6.5)
#   4. axis 2: a one-line `enum M { SYS_PPOLL = 73; }` under #ifdef CYRIUS_ARCH_AARCH64 in any
#      scanned file -> FAIL naming the file, the line, and that 73 -> 32 is flock. ⚠ the first
#      cut of axis 2 anchored its regex at line start and this probe sailed through it; the
#      mutation run is the only reason it reads the whole line now. The same constant written
#      as `SYS_PPOLL = 1073` (the private alias band) passes, as it should (v6.6.5)
#   5. axis 2 ANTI-VACUITY (review round 2): narrow the extension tuple to match nothing
#      -> FAIL "did not report lib/yukti.cyr SYS_STATFS = 43, but a direct read still finds
#      it". Before this the same mutation printed `PASS … axis 2: 0 declarations over 0
#      files, 0 known / 0 new` and exited 0, taking the KNOWN LIVE DEFECT line with it.
#   6. restrict the walk to ("lib",) -> FAIL on the corpus floor (105 files < 400).
#   7. axis 3 (review round 2): `GWL_NR_FTRUNCATE = 46` + `pn = 83;` under the guard, both
#      used as a syscall's first argument -> FAIL naming both (46 -> 211 sendmsg,
#      83 -> 34 mkdirat). These are thoth's and attn11's REAL shapes; axis 2's `SYS_*`
#      regex matched neither.
#   8. axis 3 in src/: `syscall(87, "/tmp/x")` under the guard -> FAIL (87 -> 35 unlinkat).
#      Proves src/ is now in the walk; before round 2 no gate read src/ for this at all.
#   9. rename SYS_FACCESSAT on the x86 peer (as in 3) -> the FAIL text now reads "the x86
#      peer does not declare this constant" instead of leaking a Python `None`.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: aarch64_syscall_shadow: $1"; exit 1; }
EMIT="$ROOT/src/backend/aarch64/emit.cyr"
A64="$ROOT/lib/syscalls_aarch64_linux.cyr"
X86="$ROOT/lib/syscalls_x86_64_linux.cyr"
for f in "$EMIT" "$A64" "$X86"; do [ -f "$f" ] || fail "missing $f"; done

python3 - "$EMIT" "$A64" "$X86" "$ROOT" <<'PY' || exit 1
import os, re, sys
emit, a64p, x86p, ROOT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
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
#
# ⭐ v6.6.5 — EMPTY, and that is the point. The one entry it ever held (faccessat, x86 269 ->
# aarch64 48) existed because syscalls_x86_64_linux.cyr declared no SYS_FACCESSAT, so the
# peer comparison had nothing to compare against. The v6.6.5 syscall-naming pass added
# SYS_FACCESSAT = 269 to that peer, which is a STRONGER check than the exemption: the number
# is now confirmed against the x86 peer's own declaration instead of being asserted in a
# comment here. Verified dead before deletion — the gate prints the same PASS line with the
# entry removed. The right response to a new entry is almost always to declare the constant
# on the x86 peer too, not to add a line here. CHANGELOG [6.6.5]
ALLOW = {}

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
        # ⚠ xn is None when the x86 peer does not declare this constant at all. Printing the
        # bare value leaked a Python `None` into the FAIL text ("x86 number for this call is
        # None") — measured under the SYS_FACCESSAT-rename mutation. Say what that means.
        xtxt = f"the x86 number for this call is {xn}" if xn is not None \
               else "the x86 peer does not declare this constant, so the comparison had nothing to check"
        print(f"    {name} = {n} -> reissued as {to[0]}   ({xtxt};")
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

# ══ axis 2 (v6.6.5): the SAME defect in any OTHER in-tree file ═══════════════════════════
# ⛔ WHY THIS AXIS EXISTS. Everything above reads exactly two files, the stdlib peers. But
# the shadow class is a property of an ARCH-GUARDED SYSCALL NUMBER, not of those two files,
# and vendored stdlib folds declare their own. Found by review at 6.6.5:
# `lib/yukti.cyr` line 58, inside `#ifdef CYRIUS_ARCH_AARCH64`, declares SYS_STATFS = 43 —
# the correct aarch64 native number — and ESYSXLAT's ELF arm has carried `43 -> 202` (x86
# accept) since the v6.2.10 socket block. Measured under `qemu-aarch64 -strace`:
# `syscall(SYS_STATFS, "/", buf)` traced as `accept(6293618, 0x7f254c000000, [0]) = -1
# errno=14`, so `yukti_filesystem_usage` returns "statfs failed: errno 14" on every ARM host.
# Older than this release, and invisible to all four existing gates by construction:
# raw_syscall_literals_routed.sh EXEMPTS arch-guarded literals (they are the supported
# spelling), and the other three parse only the two peer files.
#
# THE DISCRIMINATOR IS THE SAME ONE AS ABOVE, sourced differently: a guarded value that the
# chain rewrites is correct only if the row's DESTINATION really is this call on aarch64 —
# checked against the committed kernel table, which is an outside fact, not another artifact
# of this repo. That is what distinguishes yukti's SYS_STATFS = 43 (43 -> 202 = accept: WRONG)
# from the peers' documented SYS_TRUNCATE = 76 (76 -> 45 = truncate: RIGHT).
KTBL = os.path.join(ROOT, "tests/data/syscalls/aarch64.tbl")
if not os.path.exists(KTBL):
    print("FAIL: aarch64_syscall_shadow: axis 2 needs tests/data/syscalls/aarch64.tbl (the")
    print("      committed kernel facts the row DESTINATIONS are judged against). Absent, this")
    print("      axis would not be skipped, it would be gone — so it fails instead.")
    sys.exit(1)
kern = {}
for ln in open(KTBL, encoding='utf-8'):
    ln = ln.strip()
    if not ln or ln.startswith('#'):
        continue
    p = ln.split()
    if len(p) == 2 and p[0].isdigit():
        kern[int(p[0])] = p[1]
if len(kern) < 300:
    print(f"FAIL: aarch64_syscall_shadow: axis 2 parsed only {len(kern)} kernel rows (floor 300)")
    sys.exit(1)

# ⚠ finditer, not match: a declaration is not always alone on its line. A first cut anchored
# at line start and a one-line `enum S { SYS_PPOLL = 73; }` probe sailed straight through it —
# caught by the mutation run, which is the only reason this reads the whole line. The line is
# cut at the first `#` so a number quoted in a comment is not a declaration.
DECL = re.compile(r'\b(SYS_[A-Z0-9_]+)\s*=\s*(\d+)\s*;')

def guarded_lines(text):
    """(lineno, comment-stripped code) for every line live under #ifdef CYRIUS_ARCH_AARCH64."""
    out, stack = [], []
    for i, raw in enumerate(text.splitlines(), 1):
        s = raw.strip()
        if s.startswith('#ifdef '):   stack.append([s[7:].split()[0] if s[7:].split() else '', False, False]); continue
        if s.startswith('#ifndef '):  stack.append([s[8:].split()[0] if s[8:].split() else '', True, False]); continue
        if s.startswith('#ifplat '):  stack.append(['CYRIUS_ARCH_' + (s[8:].split()[0].upper() if s[8:].split() else ''), False, False]); continue
        if s.startswith('#if '):      stack.append(['', False, False]); continue
        if s.startswith('#else'):
            if stack: stack[-1][2] = True
            continue
        if s.startswith('#endif') or s.startswith('#endplat'):
            if stack: stack.pop()
            continue
        if s.startswith('#'):
            continue
        if not any(sym == 'CYRIUS_ARCH_AARCH64' and not neg and not els for sym, neg, els in stack):
            continue
        out.append((i, raw.split('#', 1)[0]))
    return out

def guarded_decls(text):
    """(name, value, lineno) for every SYS_* declaration live under #ifdef CYRIUS_ARCH_AARCH64."""
    return [(m.group(1), int(m.group(2)), i)
            for i, code in guarded_lines(text) for m in DECL.finditer(code)]

# ══ axis 3 (review round 2): the SAME defect wearing a name the kernel table cannot judge ═
# ⛔ WHY. Axis 2's regex is `SYS_[A-Z0-9_]+ = <n>;`, so it cannot see EITHER of the two
# consumer instances this release names: thoth's `GWL_NR_FTRUNCATE = 46` (a domain-prefixed
# constant) and attn11's `n = 83;` (a plain variable — measured, the chain rewrites a
# VARIABLE syscall number too, it is a runtime compare on x8). A gate that only matches the
# stdlib's own spelling checks the one corpus that already has three other gates on it.
#
# The judge above cannot apply: with no `SYS_<CALL>` there is no call name to compare
# against the kernel table. So axis 3 asserts the weaker but still exact property — the
# value IS rewritten — and says to rename it if the x86 number was deliberate.
#
# ⚠ THE NARROWING IS MEASURED, NOT GUESSED. Flagging every arch-guarded `IDENT = <row
# source>;` produced 13 in-tree false positives, every one of them `= 0` or `= 1` (loop
# counters and flags; x86 read=0 and write=1 are genuine row sources). Requiring value >= 2
# AND the identifier to appear as the FIRST argument of a `syscall(` in the same file gives
# 0 in-tree hits and still catches both consumer shapes — see the positive control.
A3_ASSIGN = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)\s*;')
A3_RAW = re.compile(r'\bsyscall\s*\(\s*(\d+)\s*[,)]')
A3_FIRSTARG = re.compile(r'\bsyscall\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,)]')

def nameless_hits(text):
    """(lineno, what, value, why) for guarded syscall numbers axis 2's SYS_* regex misses."""
    out = []
    via_var = {m.group(1) for m in A3_FIRSTARG.finditer(text)}
    for i, code in guarded_lines(text):
        for m in A3_RAW.finditer(code):
            v = int(m.group(1))
            if v in froms:
                out.append((i, f"syscall({v}, …)", v,
                            f"ESYSXLAT rewrites {v} -> {froms[v][0]} (`{kern.get(froms[v][0], 'unassigned')}`)"))
        for m in A3_ASSIGN.finditer(code):
            nm, v = m.group(1), int(m.group(2))
            if nm.startswith("SYS_"):     # axis 2 owns these, and judges them properly
                continue
            if v < 2 or v not in froms or nm not in via_var:
                continue
            out.append((i, f"{nm} = {v}", v,
                        f"ESYSXLAT rewrites {v} -> {froms[v][0]} (`{kern.get(froms[v][0], 'unassigned')}`)"))
    return out

# A POSITIVE CONTROL, so an axis that has stopped parsing cannot read green. The scanner is
# run over a synthetic buffer carrying one known collision and one known-correct declaration;
# if it does not flag exactly the first, the scanner is broken and nothing below it means
# anything. This is the anti-vacuous floor for an axis whose real corpus is legitimately tiny.
CONTROL = (
    "#ifdef CYRIUS_ARCH_AARCH64\n"
    "enum Ctl {\n"
    "    SYS_STATFS = 43;\n"      # 43 -> 202 accept: MUST be flagged
    "    SYS_TRUNCATE = 76;\n"    # 76 -> 45 truncate: the documented intended-x86 pattern
    "    SYS_GETDENTS64 = 61;\n"  # native and unrouted: fine
    "}\n"
    "#endif\n"
    "#ifdef CYRIUS_ARCH_X86\n"
    "enum Ctl2 { SYS_STATFS = 137; }\n"   # not under the aarch64 guard: must not be seen
    "#endif\n"
    "#ifdef CYRIUS_ARCH_AARCH64\n"
    "enum Ctl3 { SYS_PPOLL = 73; }\n"     # one-line enum, 73 -> 32 flock: MUST be flagged
    "#endif\n"
)

# Axis 3's positive control is the two REAL consumer shapes this release names, verbatim:
# thoth/src/gui/gwindow.cyr's `GWL_NR_FTRUNCATE = 46` and attn11/src/fileio.cyr's `n = 83;`,
# plus a bare raw literal and two shapes that must NOT fire (a loop counter whose value is a
# row source, and a constant that is never a syscall's first argument).
CONTROL3 = (
    "#ifdef CYRIUS_ARCH_AARCH64\n"
    "var GWL_NR_FTRUNCATE = 46;\n"        # 46 -> 211 sendmsg: MUST be flagged
    "var n = 83;\n"                       # 83 -> 34 mkdirat: MUST be flagged (a VARIABLE)
    "var i = 0;\n"                        # 0 IS a row source (read 0->63): must NOT fire
    "var RETRIES = 76;\n"                 # never a syscall first arg: must NOT fire
    "fn c3(): i64 { return syscall(87, \"/x\"); }\n"   # raw 87 -> 35: MUST be flagged
    "#endif\n"
    "fn c3b(): i64 { syscall(GWL_NR_FTRUNCATE, 1, 2); return syscall(n, \"y\", 0); }\n"
)
c3 = sorted(w for _, w, _, _ in nameless_hits(CONTROL3))
if c3 != ["GWL_NR_FTRUNCATE = 46", "n = 83", "syscall(87, …)"]:
    print(f"FAIL: aarch64_syscall_shadow: axis 3 POSITIVE CONTROL failed — flagged {c3}, expected "
          "['GWL_NR_FTRUNCATE = 46', 'n = 83', 'syscall(87, …)']. The scanner is broken (or the "
          "chain no longer routes 46/83/87), so the nameless shapes below go unreported.")
    sys.exit(1)

def judge(name, val):
    """None when fine, else the reason it is wrong."""
    if val >= 1000 or val not in froms:
        return None
    dest = froms[val][0]
    call = name[4:].lower()
    if kern.get(dest) == call:
        return None                       # intended x86 number; the row lands on the right call
    return f"ESYSXLAT rewrites {val} -> {dest}, which is aarch64 `{kern.get(dest, 'unassigned')}`, not `{call}`"

ctl = [(n, v, ln) for n, v, ln in guarded_decls(CONTROL)]
ctl_bad = [(n, v) for n, v, _ in ctl if judge(n, v)]
if sorted(n for n, _ in ctl_bad) != ["SYS_PPOLL", "SYS_STATFS"] or len(ctl) != 4:
    print("FAIL: aarch64_syscall_shadow: axis 2 POSITIVE CONTROL failed — the scanner saw "
          f"{len(ctl)} guarded declarations (expected 4) and flagged {sorted(n for n, _ in ctl_bad)} "
          "(expected ['SYS_PPOLL', 'SYS_STATFS']). The #ifdef tracking or the judge is broken, "
          "so a real collision below would go unreported.")
    sys.exit(1)

# The one LIVE defect, named, with the fix. ⚠ This is NOT an allow-list: it is printed on
# every run so it cannot go quiet, and the gate still fails on anything else. It leaves when
# yukti ships the fix upstream and cyrius re-vendors — a fold-only edit here would evaporate
# at the next `cyrius deps`.
KNOWN = {("lib/yukti.cyr", "SYS_STATFS", 43):
         "upstream ~/Repos/yukti: spell sys_statfs, or use the >= 1000 private alias band"}

PEERS = {"lib/syscalls_aarch64_linux.cyr", "lib/syscalls_x86_64_linux.cyr",
         "lib/syscalls_macos.cyr", "lib/syscalls_windows.cyr", "lib/syscalls_x86_64_agnos.cyr"}
found, known_hits, nscanned, ndecl = [], [], 0, 0
a3 = []
# ⚠ `src` is in the walk since review round 2: the compiler's OWN source carried
# `syscall(113, …)` under #ifdef CYRIUS_ARCH_AARCH64 (the aarch64-native clock_gettime) right
# through the release that wrote the rule forbidding it. Latent — 113 is a row PRODUCT, not a
# source — but no gate looked there at all: raw_syscall_literals_routed.sh scans everything
# EXCEPT src/, and exempts arch-guarded literals anyway.
for sub in ("lib", "cbt", "programs", "tests", "benches", "fuzz", "src"):
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, sub)):
        for fn in sorted(files):
            if not fn.endswith((".cyr", ".tcyr", ".fcyr", ".bcyr")):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), ROOT)
            if rel in PEERS:
                continue
            nscanned += 1
            try:
                text = open(os.path.join(dirpath, fn), encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            for name, val, lineno in guarded_decls(text):
                ndecl += 1
                why = judge(name, val)
                if why is None:
                    continue
                if (rel, name, val) in KNOWN:
                    known_hits.append((rel, lineno, name, val, why))
                else:
                    found.append((rel, lineno, name, val, why))
            for lineno, what, _v, why in nameless_hits(text):
                a3.append((rel, lineno, what, why))

# ══ axis 2 anti-vacuity (review round 2) ═════════════════════════════════════════════════
# ⛔ WITHOUT THIS THE AXIS READ GREEN OVER AN EMPTY WALK. Everything above had a synthetic
# positive control for the SCANNER and floors on rows/decls/kernel-rows, but nothing at all
# on the CORPUS. Measured in a scratch copy: narrow the extension tuple to match nothing and
# the gate printed `PASS … axis 2: 0 arch-guarded declarations over 0 files, 0 known / 0 new`
# and exited 0 — taking the `KNOWN LIVE DEFECT lib/yukti.cyr` line, the only thing keeping
# that live bug audible, out with it. Same vacuity shape this release fixed in
# syscall_peer_kernel_agreement.sh (per-peer floors) and syscall_xlat_generated.sh (axes 9+10).
#
# The strong half is the KNOWN RE-DERIVATION, and it is computed a DIFFERENT WAY from the
# walk: open each KNOWN file by its own path and regex it directly. If the declaration is
# still in the file, the walk MUST have reported it. A broken walk therefore fails here
# instead of going quiet, and when yukti ships the fix upstream and cyrius re-vendors, the
# declaration disappears from the file and this check retires itself.
for (rel, name, val), _fix in sorted(KNOWN.items()):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        continue                              # the file left the tree; nothing to re-derive
    direct = re.search(rf'\b{re.escape(name)}\s*=\s*{val}\s*;',
                       open(p, encoding='utf-8', errors='replace').read())
    seen = any(h[0] == rel and h[2] == name and h[3] == val for h in known_hits)
    if direct and not seen:
        print(f"FAIL: aarch64_syscall_shadow: axis 2 did not report {rel} {name} = {val}, but a")
        print(f"      direct read of that file still finds the declaration. The tree walk is")
        print(f"      not reaching the corpus — every other 'clean' result below is vacuous.")
        sys.exit(1)
    if seen and not direct:
        print(f"FAIL: aarch64_syscall_shadow: axis 2 reported {rel} {name} = {val} but a direct")
        print(f"      read of the file does not find it — the scanner and the file disagree.")
        sys.exit(1)

# Corpus floors. Not a tuned threshold — a tripwire for "this axis inspected nothing".
# Measured at v6.6.5: 658 files, 6 arch-guarded SYS_* declarations. The tree only grows.
if nscanned < 400:
    print(f"FAIL: aarch64_syscall_shadow: axis 2 walked only {nscanned} source files (floor 400; "
          f"658 at v6.6.5). The walk or the extension set moved and the axis is inspecting nothing.")
    sys.exit(1)
if ndecl < 3:
    print(f"FAIL: aarch64_syscall_shadow: axis 2 found only {ndecl} arch-guarded SYS_* "
          f"declarations over {nscanned} files (floor 3; 6 at v6.6.5). The #ifdef tracking "
          f"stopped matching — a real collision would be invisible.")
    sys.exit(1)

for rel, lineno, name, val, why in known_hits:
    print(f"  ⚠ KNOWN LIVE DEFECT (not this repo's to fix): {rel}:{lineno} {name} = {val} — {why}")
    print(f"      {KNOWN[(rel, name, val)]}")
if found:
    print("FAIL: aarch64_syscall_shadow: an #ifdef CYRIUS_ARCH_AARCH64 declaration is rewritten")
    print("      by an x86-compat ESYSXLAT row — the call runs as a DIFFERENT syscall on ARM:")
    for rel, lineno, name, val, why in found:
        print(f"    {rel}:{lineno}  {name} = {val}: {why}")
    print("      Fix it where the file is MAINTAINED (a vendored lib/<dep>.cyr edit evaporates")
    print("      at the next `cyrius deps`), by spelling the stdlib wrapper or moving the")
    print("      constant into the >= 1000 private alias band with a row appended LAST.")
    sys.exit(1)

if a3:
    print("FAIL: aarch64_syscall_shadow: axis 3 — an arch-guarded syscall number that is NOT")
    print("      spelled SYS_<CALL> is rewritten by the ESYSXLAT chain, so the call runs as a")
    print("      DIFFERENT syscall on ARM:")
    for rel, lineno, what, why in a3:
        print(f"    {rel}:{lineno}  {what}: {why}")
    print("      If the number was deliberately the X86 spelling (the supported pattern), name")
    print("      it SYS_<CALL> so axis 2's kernel-table discriminator can confirm it. Otherwise")
    print("      spell the stdlib wrapper, or move it to the >= 1000 private alias band.")
    sys.exit(1)

print(f"PASS: aarch64_syscall_shadow ({len(rows)} rows, {len(a64)} declarations, "
      f"0 shadowed, {len(intended)} intended x86-number renumbers, alias band last; "
      f"axis 2: {ndecl} arch-guarded declarations over {nscanned} files, "
      f"{len(known_hits)} known / 0 new; axis 3: 0 nameless guarded numbers rewritten)")
PY
