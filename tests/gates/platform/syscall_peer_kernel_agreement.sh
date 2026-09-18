#!/bin/sh
# syscall_peer_kernel_agreement.sh — v6.6.5. Every number a stdlib peer declares means, ON
# THE KERNEL, the call its NAME claims — checked against committed UAPI tables, not against
# another artifact of this repo.
#
# ⛔ WHY THIS AXIS EXISTS, AND WHY IT IS THE ONLY NON-CIRCULAR ONE. The syscall machinery has
# four checks and, until this one, every pair of them shared a source:
#   * syscall_xlat_generated.sh re-derives src/common/syscall_xlat.cyr FROM the two peers, so
#     a wrong number in a peer produces a table that agrees with it perfectly;
#   * raw_syscall_literals_routed.sh derives its allowlist FROM the emitter, so a wrong row
#     admits the literal that matches it;
#   * aarch64_syscall_shadow.sh compares the two peers TO EACH OTHER;
#   * esysxlat_row_order.sh checks the chain against ITSELF.
# A check that shares a defect with the thing it checks reads GREEN — the pattern this repo
# found seven times in one release at v6.6.2. The kernel tables are the outside fact.
#
# ⚠ THE AARCH64 PEER HAS THREE LEGITIMATE SPELLINGS and the discriminator is load-bearing.
# A declaration is correct if it is:
#   (a) NATIVE          — kernel_a64[v] is this call AND ESYSXLAT does not route v (a compat
#       row matches a NUMBER and cannot tell a native one from the x86 one it is chasing, so
#       "native but routed" is the SHADOW class that made kybernet's whole aarch64 target
#       non-functional at v6.5.36 — measured, `sys_umount2` returned a PID); or
#   (b) an INTENDED x86 NUMBER — v is what the x86 peer declares for the SAME name, ESYSXLAT
#       routes v, and kernel_a64[route(v)] is this call. The peer does this deliberately when
#       the native number is already consumed by an x86-compat row (SYS_FSYNC = 74,
#       SYS_NEWFSTATAT = 262, SYS_FACCESSAT = 269, and from v6.6.5 SYS_TRUNCATE = 76,
#       SYS_FTRUNCATE = 77, SYS_UNLINKAT = 263); or
#   (c) a PRIVATE ALIAS — v >= 1000, and kernel_a64[v - 1000] is this call (the v6.5.7 band).
# Judging (b) as if it were (a) reports five-to-nine false positives — the exact mistake the
# first sweep at v6.5.37 made, and the reason aarch64_syscall_shadow.sh's header spends a
# paragraph on the same discriminator.
#
# MUTATION LEDGER (each applied, gate re-run, then reverted):
#   1. lib/syscalls_aarch64_linux.cyr SYS_SENDMSG = 212  -> FAIL "kernel a64 says recvmsg"
#   2. point the ESYSXLAT row at 263→36 instead of 263→35 -> FAIL SYS_UNLINKAT (resolves to
#      symlinkat); deleting the row outright fails on the row floor instead
#   2b. move SYS_UNLINKAT back to 35 (native, but 35→101 routes it) -> FAIL as SHADOWED
#   3. add lib/syscalls_aarch64_linux.cyr SYS_CAPSET = 91 -> FAIL axis B (it would silently
#      DELETE the fchmod-91 diagnostic row that syscall_xlat_generated.sh axis 3 probes)
#   4. truncate tests/data/syscalls/aarch64.tbl          -> FAIL on the table floor
#   5. (v6.6.5 review) reformat lib/syscalls_macos.cyr so its 111 declarations stop matching
#      decl()'"'"'s regex -> before the per-peer floors below this printed the IDENTICAL PASS
#      line with the macOS arm contributing nothing; now FAIL "only 0 SYS_* declarations
#      parsed from the macOS peer". The macOS arm is the one that caught a planted
#      SYS_FTRUNCATE = 78, so a silent zero there is not a skip, it is a false green.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
KX=tests/data/syscalls/x86_64.tbl
KA=tests/data/syscalls/aarch64.tbl
EMIT=src/backend/aarch64/emit.cyr
PX=lib/syscalls_x86_64_linux.cyr
PA=lib/syscalls_aarch64_linux.cyr
PM=lib/syscalls_macos.cyr
PW=lib/syscalls_windows.cyr
for f in "$KX" "$KA" "$EMIT" "$PX" "$PA" "$PM" "$PW"; do
    [ -f "$f" ] || { echo "FAIL: syscall_peer_kernel_agreement: missing $f"; exit 1; }
done

# Anti-vacuous floors on the OUTSIDE facts: an empty or truncated table would let every
# declaration through as "not in the table, nothing to say".
nkx=$(grep -cE '^[0-9]+ [a-z0-9_]+$' "$KX")
nka=$(grep -cE '^[0-9]+ [a-z0-9_]+$' "$KA")
[ "$nkx" -ge 380 ] || { echo "FAIL: syscall_peer_kernel_agreement: $KX has only $nkx rows (floor 380)"; exit 1; }
[ "$nka" -ge 320 ] || { echo "FAIL: syscall_peer_kernel_agreement: $KA has only $nka rows (floor 320)"; exit 1; }
# Spot-check the tables against three facts this whole release turns on, so a table swapped
# for the WRONG arch's fails loudly instead of quietly re-blessing the peers.
awk '$1 == 77 && $2 == "ftruncate" { f = 1 } END { exit !f }' "$KX" \
  || { echo "FAIL: $KX does not say 77 = ftruncate — this is not the x86_64 table"; exit 1; }
awk '$1 == 77 && $2 == "tee" { f = 1 } END { exit !f }' "$KA" \
  || { echo "FAIL: $KA does not say 77 = tee — this is not the aarch64 table"; exit 1; }
awk '$1 == 46 && $2 == "ftruncate" { f = 1 } END { exit !f }' "$KA" \
  || { echo "FAIL: $KA does not say 46 = ftruncate — this is not the aarch64 table"; exit 1; }

# ── the routed rows, decoded from the emitter (ELF arm only; see esysxlat_row_order.sh) ──
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
awk '
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
' "$EMIT" > "$D/rows"
nrows=$(wc -l < "$D/rows" | tr -d ' ')
[ "$nrows" -ge 58 ] || { echo "FAIL: syscall_peer_kernel_agreement: decoded only $nrows ESYSXLAT rows (floor 58)"; exit 1; }

report=$(awk '
FILENAME == ARGV[1] { if ($0 !~ /^#/ && NF == 2) { kx[$1] = $2; kxn[$2] = $1 } next }
FILENAME == ARGV[2] { if ($0 !~ /^#/ && NF == 2) { ka[$1] = $2; kan[$2] = $1 } next }
FILENAME == ARGV[3] { if (!($1 in rt)) rt[$1] = $2; next }       # first row wins: the chain is sequential
function decl(which,   l, p) {
    if (match($0, /^[ \t]*SYS_[A-Z0-9_]+[ \t]*=[ \t]*[0-9]+[ \t]*;/)) {
        l = $0; sub(/#.*$/, "", l); gsub(/[ \t;]/, "", l); split(l, p, "=")
        if (which == "x") { xp[p[1]] = p[2] + 0; nxp++ }
        if (which == "a") { ap[p[1]] = p[2] + 0; nap++ }
        if (which == "m") { mp[p[1]] = p[2] + 0; nmp++ }
        if (which == "w") { wp[p[1]] = p[2] + 0; nwp++ }
    }
}
FILENAME == ARGV[4] { decl("x"); next }
FILENAME == ARGV[5] { decl("a"); next }
FILENAME == ARGV[6] { decl("m"); next }
FILENAME == ARGV[7] { decl("w"); next }
function kname(n,   s) { s = tolower(n); sub(/^sys_/, "", s); return s }

# ── EVERY allow-list entry is a reviewable CLAIM with its reason, never a way to silence a
# number. Keep it to the two structural rules plus the one named deviation.
function allowed(peer, n, v) {
    # (1) The DARWIN PRIVATE-ALIAS BAND. On the macOS peer, >= 1000 is "1000 + the Darwin BSD
    # number" — Linux has no such call to borrow from (there is no live sysctl; kqueue,
    # bsdthread_* and __ulock_* are Darwin-only), so a Linux table says nothing about them.
    # EMACHO_SYSXLAT routes them; macho_route_parity.sh is what checks that.
    if (peer == "MACOS" && v >= 1000) return 1
    # (2) The same band on the aarch64 peer, for the two Darwin-ONLY occupants. Every other
    # >= 1000 entry there IS checked, against kernel_a64[v - 1000].
    if (peer == "A64" && (n == "SYS_GETTIMEOFDAY" || n == "SYS_SYSCTL")) return 1
    # (3) SYS_IOCTL on the macOS peer is 29, the AARCH64-native number, not the x86 16 — a
    # deliberate v6.5.36 choice so ONE spelling serves both Mach-O backends (the arm peer
    # says 29 too, and EMACHO_SYSXLAT carries 29→Darwin 54 as well as 16→54). It is the one
    # documented deviation from this peer'"'"'s "Linux x86_64 numbers" convention.
    if (peer == "MACOS" && n == "SYS_IOCTL" && v == 29) return 1
    return 0
}
END {
    bad = 0
    # ── axis A: the x86-numbered peers ──────────────────────────────────────────────
    for (n in xp) if (!allowed("X86", n, xp[n])) { k = kname(n); v = xp[n]
        if (!(v in kx) || kx[v] != k) { printf "  FAIL  x86 peer  %-24s = %-5d : kernel x86_64 %d is %s (the real %s is %s)\n", n, v, v, (v in kx) ? kx[v] : "unassigned", k, (k in kxn) ? kxn[k] : "not an x86_64 syscall"; bad++ } }
    for (n in mp) if (!allowed("MACOS", n, mp[n])) { k = kname(n); v = mp[n]
        if (!(v in kx) || kx[v] != k) { printf "  FAIL  macOS peer %-23s = %-5d : kernel x86_64 %d is %s (this peer declares LINUX numbers by convention)\n", n, v, v, (v in kx) ? kx[v] : "unassigned"; bad++ } }
    for (n in wp) if (!allowed("WIN", n, wp[n])) { k = kname(n); v = wp[n]
        if (!(v in kx) || kx[v] != k) { printf "  FAIL  PE peer   %-24s = %-5d : kernel x86_64 %d is %s (this peer declares LINUX numbers by convention)\n", n, v, v, (v in kx) ? kx[v] : "unassigned"; bad++ } }
    # ── axis A2: the aarch64 peer, with its three legitimate spellings ──────────────
    for (n in ap) if (!allowed("A64", n, ap[n])) { k = kname(n); v = ap[n]
        if (v >= 1000)                                    { w = v - 1000; ok = ((w in ka) && ka[w] == k); why = sprintf("private alias -> native %d", w) }
        else if ((n in xp) && xp[n] == v && (v in rt))    { ok = ((rt[v] in ka) && ka[rt[v]] == k); why = sprintf("intended x86 number, ESYSXLAT routes %d -> %d", v, rt[v]) }
        else if (v in rt)                                 { ok = 0; why = sprintf("read as native, but ESYSXLAT REWRITES %d -> %d before the svc", v, rt[v]); got = (rt[v] in ka) ? ka[rt[v]] : "an unassigned number" }
        else                                              { ok = ((v in ka) && ka[v] == k); why = "native aarch64 number"; got = (v in ka) ? ka[v] : "an unassigned number" }
        if (v >= 1000) { got = ((v - 1000) in ka) ? ka[v - 1000] : "an unassigned number" }
        else if ((n in xp) && xp[n] == v && (v in rt)) { got = (rt[v] in ka) ? ka[rt[v]] : "an unassigned number" }
        if (!ok) { printf "  FAIL  a64 peer  %-24s = %-5d (%s): that resolves to %s, not %s\n", n, v, why, got, k
                   printf "                  the real aarch64 %s is %s\n", k, (k in kan) ? kan[k] : "absent from the generic table"
                   bad++ } }
    # ── axis B: the AMBIGUOUS set is PINNED ─────────────────────────────────────────
    # An x86 number that the aarch64 peer declares NATIVELY for a DIFFERENT call can never be
    # diagnosed (a literal there is plausibly correct) and can never be routed (a compat row
    # would break the native call). Declaring a new one therefore SILENTLY DELETES a row from
    # src/common/syscall_xlat.cyr — nothing else notices, and syscall_xlat_generated.sh axis 3
    # probes one of them (fchmod 91) as its own positive control.
    for (n in xp) { if (!(n in ap)) continue; v = xp[n]; if (ap[n] == v) continue; if (v in rt) continue
        for (m in ap) { if (ap[m] != v || m == n || ap[m] >= 1000) continue
            if ((m in xp) && xp[m] == ap[m] && (ap[m] in rt)) continue
            printf "AMB %s %d %s\n", n, v, m } }
    printf "NDECL %d %d %d %d\n", nxp + 0, nap + 0, nmp + 0, nwp + 0
    printf "BAD=%d\n", bad
}
' "$KX" "$KA" "$D/rows" "$PX" "$PA" "$PM" "$PW")

printf '%s\n' "$report" | grep '^  FAIL' || true
bad=$(printf '%s\n' "$report" | sed -n 's/^BAD=\([0-9]*\)$/\1/p')

# ── anti-vacuous floors on the INSIDE facts too (v6.6.5) ────────────────────────────────
# The table floors above stop a truncated kernel table re-blessing the peers. Nothing stopped
# the mirror image: if `decl()`'s regex stops matching a peer's declarations, that peer simply
# contributes nothing and the gate still prints "4 peers agree". Measured before adding this:
# reformatting lib/syscalls_macos.cyr so its 111 declarations no longer match left the gate
# GREEN — and the macOS arm is the one that caught a planted SYS_FTRUNCATE = 78. The x86 and
# aarch64 arms were only ACCIDENTALLY covered (the amb_want pin reddens when xp/ap empty),
# which is not a check, it is a side effect. Floors are ~90 % of the measured counts at 6.6.5
# (109 / 99 / 111 / 18) — low enough not to trip on ordinary additions, high enough that a
# whole peer going dark is impossible. CHANGELOG [6.6.5]
read_ndecl=$(printf '%s\n' "$report" | sed -n 's/^NDECL //p')
set -- $read_ndecl
[ $# -eq 4 ] || { echo "FAIL: syscall_peer_kernel_agreement: the per-peer declaration counts were not reported"; exit 1; }
for pair in "x86:$1:100" "a64:$2:90" "macOS:$3:100" "PE:$4:15"; do
    pn=${pair%%:*}; rest=${pair#*:}; pc=${rest%%:*}; pf=${rest#*:}
    [ "$pc" -ge "$pf" ] || { echo "FAIL: syscall_peer_kernel_agreement: only $pc SYS_* declarations parsed from the $pn peer (floor $pf) — the declaration regex or the file layout moved, and that peer was checked against NOTHING"; exit 1; }
done
printf '%s\n' "$report" | grep '^AMB ' | sed 's/^AMB //' | sort > "$D/amb"
namb=$(wc -l < "$D/amb" | tr -d ' ')

# The reasoned ambiguous set. Each line is "<x86 name> <x86 number> <aarch64 name that owns
# it natively>". Adding to this list is a claim that the collision is UNAVOIDABLE — that the
# aarch64 peer genuinely needs the native number and no private alias will do.
cat > "$D/amb_want" <<'EOF'
SYS_CHDIR 80 SYS_FSTAT
SYS_CLONE 56 SYS_OPENAT
SYS_EXECVE 59 SYS_PIPE2
SYS_FCHOWNAT 260 SYS_WAIT4
SYS_GETPEERNAME 52 SYS_FCHMOD
SYS_KILL 62 SYS_LSEEK
SYS_PRCTL 157 SYS_SETSID
SYS_SCHED_YIELD 24 SYS_DUP3
SYS_SOCKETPAIR 53 SYS_FCHMODAT
SYS_UNAME 63 SYS_READ
SYS_WAIT4 61 SYS_GETDENTS64
EOF
if ! diff -u "$D/amb_want" "$D/amb" > "$D/amb.diff"; then
    echo "  FAIL  the AMBIGUOUS set moved (expected 11 entries, found $namb):"
    sed 's/^/        /' "$D/amb.diff"
    echo "        A LINE ADDED here means a new aarch64 declaration just DELETED a row from"
    echo "        src/common/syscall_xlat.cyr — raw use of that x86 number on ELF-aarch64 is now"
    echo "        undiagnosable. Use the >= 1000 private alias band instead, or accept it here"
    echo "        with a written reason. A line REMOVED means a collision was resolved; update"
    echo "        the list. (v6.6.5 added exactly one: SYS_SCHED_YIELD 24, because aarch64 24 IS"
    echo "        dup3 and a compat row for it would break every raw dup3.)"
    bad=$((${bad:-0} + 1))
fi

if [ "${bad:-1}" -ne 0 ]; then
    echo "FAIL: syscall_peer_kernel_agreement: $bad disagreement(s) against the committed kernel tables"
    exit 1
fi
echo "PASS syscall_peer_kernel_agreement: 4 peers agree with the kernel ($nkx x86_64 + $nka aarch64 facts, $nrows routed rows, $namb pinned ambiguities, $1/$2/$3/$4 peer declarations)"
