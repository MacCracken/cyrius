#!/bin/sh
# agnos_syscall_a4_defined.sh — v6.6.7. On AGNOS every `syscall` instruction cycc emits must
# hand the kernel a DEFINED a4 (r10): either the site's own 4th argument (`pop r10`) or an
# explicit zero (`xor r10d, r10d`).
#
# ⛔ WHY. The agnos kernel reads a4 = r10 on EVERY syscall entry (syscall_hw.cyr stores it
# unconditionally), and two of the busiest arms branch on it: read#5 BLOCKS on an empty pipe /
# channel only when a4 == 0 (agnos 1.57.8), and write#1 blocks on a full pipe only when
# a4 == 0 (1.57.9) — a4 != 0 is O_NONBLOCK and a full-pipe write returns 0. Before 6.6.7 a site
# passing fewer than four arguments never wrote r10, so it carried whatever was left there:
# the user CR3 the SYSRET stub loads (never 0 → non-blocking), or the LAST ARGUMENT of the
# latest 7+-argument cyrius call (the SysV stack-arg shuttle writes r10 → possibly 0 →
# blocking). The same `println` therefore either blocked or silently dropped its line in an
# agnsh pipeline depending on what ran before it, and ~128 raw 3-arg `syscall(1, …)` print
# sites in portable lib (string/str/fmt/assert/flags/…) could not be reached by a wrapper fix.
#
# Axis 1 is the class check over a whole program; axis 2 keeps it from passing vacuously;
# axis 3 proves no other target's output changed. CHANGELOG [6.6.7].
#
# SHELL-AGNOSTIC: disassemble to a file, then read it — never `objdump | grep -q` (SIGPIPE
# under pipefail) — and `|| true` on every count (grep -c exits 1 on 0).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_syscall_a4_defined: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_syscall_a4_defined: no build/cycc"; exit 1; }
command -v llvm-objdump > /dev/null 2>&1 || {
    echo "FAIL agnos_syscall_a4_defined: llvm-objdump is required (a skipped disassembly would"
    echo "  make this gate pass over exactly the defect it exists for)"; exit 1; }

# The probe reaches every shape: the stdlib raw print (println → 3-arg syscall(1, …)), the
# peer wrappers, a raw 3-arg write straight after a 7-arg call (the r10 = 0 residue), a
# non-literal syscall number, and a genuine 4-arg site that must keep its `pop r10`.
cat > "$T/p.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/syscalls.cyr"
fn f7(a, b, c, d, e, f, g): i64 { return a + g; }
fn main(): i64 {
    var b[16];
    println("a4");
    f7(1, 2, 3, 4, 5, 6, 0);
    syscall(1, 1, "x\n", 2);
    sys_read(0, &b, 1);
    sys_write(1, "y\n", 2);
    var n = 1;
    syscall(n, 1, "z\n", 2);
    var n4 = 999;
    if (n == 2) { syscall(n4, 0, 0, 0, 0); }   # a 4-arg site; never runs
    return 0;
}
var r = main();
sys_exit(r);
EOF

scan() {  # $1 = disassembly → prints "<sites> <xor> <pop_r10> <exit> <bad>"
    awk '
    { line[NR] = $0 }
    /\tsyscall$/ || /\tsyscall[ \t]*$/ {
        sites++
        p = line[NR - 1]
        if (p ~ /xorl\t%r10d, %r10d/) { xr++; next }
        if (p ~ /xorl\t%eax, %eax/ && line[NR - 2] ~ /movq\t%rax, %rdi/) { ex++; next }
        ok = 0
        for (k = NR - 1; k > 0 && k >= NR - 8; k--) {
            if (line[k] !~ /\tpopq\t/) break
            if (line[k] ~ /popq\t%r10$/) { ok = 1; break }
        }
        if (ok) { pr++ } else { bad++; print "    BAD site: " p > "/dev/stderr" }
    }
    END { printf "%d %d %d %d %d\n", sites, xr, pr, ex, bad }' "$1"
}

# ── axis 1 — no agnos syscall site leaves a4 undefined ───────────────────────────────────────
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/a.out" 2>"$T/a.err" || {
    echo "FAIL agnos_syscall_a4_defined axis1: the CYRIUS_TARGET_AGNOS build failed"
    grep -E '^error' "$T/a.err" | head -3 | sed 's/^/    /'; exit 1; }
llvm-objdump -d --no-show-raw-insn "$T/a.out" > "$T/a.dis" 2>/dev/null || true
set -- $(scan "$T/a.dis" 2>"$T/bad.txt")
sites=$1; xr=$2; pr=$3; ex=$4; bad=$5
if [ "$bad" != "0" ]; then
    echo "FAIL agnos_syscall_a4_defined axis1: $bad of $sites agnos syscall sites reach the kernel"
    echo "  with r10 (a4) UNDEFINED — read#5/write#1 then block or not by call history."
    head -5 "$T/bad.txt"; exit 1
fi
echo "  ok: axis 1 — $sites agnos syscall sites: $xr zero a4, $pr pass their own a4, $ex exit"

# ── axis 2 — ANTI-VACUOUS: the probe really produced the shapes it claims to cover ───────────
# ≥ 5 zeroed sites (println, the raw write, sys_read, sys_write, the non-literal number) and
# ≥ 1 genuine 4-arg site whose `pop r10` must NOT have been clobbered by the zero.
[ "$xr" -ge 5 ] && [ "$pr" -ge 1 ] || {
    echo "FAIL agnos_syscall_a4_defined axis2: expected >= 5 zeroed and >= 1 pop-r10 site,"
    echo "  got $xr and $pr — the probe no longer exercises the class"; exit 1; }
echo "  ok: axis 2 — the probe covers zeroed sites and keeps each 4-arg site's own a4"

# ── axis 3 — the zero is agnos-ONLY: Linux, Mach-O and PE output carry none of it ───────────
for t in CYRIUS_X=0 CYRIUS_MACHO=1 CYRIUS_TARGET_WIN=1; do
    env "$t" "$CC" < "$T/p.cyr" > "$T/o.out" 2>/dev/null || {
        echo "FAIL agnos_syscall_a4_defined axis3: the $t build failed"; exit 1; }
    llvm-objdump -d --no-show-raw-insn "$T/o.out" > "$T/o.dis" 2>/dev/null || true
    n=$(grep -c 'xorl.%r10d, %r10d' "$T/o.dis" || true)
    [ "$n" = "0" ] || {
        echo "FAIL agnos_syscall_a4_defined axis3: the $t build emits $n 'xor r10d, r10d' —"
        echo "  the agnos-only zero leaked into another target's output"; exit 1; }
done
echo "  ok: axis 3 — Linux / Mach-O / PE output carries no r10 zero"

echo "PASS: agnos_syscall_a4_defined — every agnos syscall site hands the kernel a defined a4"
exit 0
