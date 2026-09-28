#!/bin/sh
# Gate: the Linux heap comes up on a board smaller than its 256 MB first chunk (v6.6.8).
#
# ⛔ THE DEFECT (audit). lib/alloc.cyr's Linux arm reserves its first chunk as ONE 256 MB
# anonymous mmap. The reservation is virtual, but a plain anonymous mapping is still charged
# against the kernel's overcommit HEURISTIC (vm.overcommit_memory = 0, the default), which
# refuses a single mapping larger than RAM + swap. On a board with less than ~256 MB the first
# chunk was refused, alloc_init printed "alloc_init: mmap failed" and exited 1 — and as PID 1
# that is a kernel panic:
#     alloc_init: mmap failed
#     Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100
# THE FIX, two layers: a grain-sized chunk is mapped MAP_NORESERVE (the heuristic stops sizing a
# reservation nobody promised to touch), and a refusal that survives that (strict overcommit
# mode 2 ignores NORESERVE; RLIMIT_AS counts every mapping) drops the grain to 16 MB, for this
# chunk and every later one.
#
# ROWS (x86_64 Linux; the aarch64 arm is the same source, verified on pi at 6.6.8)
#   1. NORESERVE: the probe reads /proc/self/smaps and asserts the mapping holding its first
#      allocation carries VmFlags `nr` (MAP_NORESERVE). 6.6.7: no `nr`.
#   2. FALLBACK: under `ulimit -v 200000` (~195 MB of address space — less than one 256 MB
#      grain) the heap comes up, serves 64 B, then 40 MB (past one 16 MB grain, so it must GROW
#      at the small grain), then 100 x 1 MB, and reports the 16 MB grain. 6.6.7: exit 1,
#      "alloc_init: mmap failed". ANTI-VACUOUS: the same probe WITHOUT the limit must report the
#      256 MB grain — otherwise the fallback could be firing on every box and row 2 would prove
#      nothing about refusal.
#   3. A refused BIG REQUEST is not a small board: under `ulimit -v 600000` the 256 MB first
#      chunk maps, alloc(400 MB) is refused (its request-sized chunk does not fit) and returns 0,
#      and the grain STAYS 256 MB — the heap does not shrink to 16 MB steps because one
#      oversized request failed.
#   4. OPT-IN — THE STARVED-VM PID-1 RECIPE (CYRIUS_ALLOC_VM=1; SKIPs, named, otherwise). Boots
#      the host kernel in `qemu-system-x86_64 -m 256M` with a one-file initramfs whose /init is a
#      cyrius static binary that allocates and powers the VM off. `random.trust_cpu=off` keeps
#      the CRNG unseeded at PID 1 (the RNG-less-board condition lib/hashseed.cyr's non-blocking
#      draw exists for). Needs /boot/vmlinuz-linux (or CYRIUS_VM_KERNEL), cpio and
#      qemu-system-x86_64; KVM is used when /dev/kvm is writable. By hand:
#          cat init.cyr | build/cycc > init          # alloc(64), alloc(40 MB), reboot(POWER_OFF)
#          echo init | cpio -o -H newc > initrd.cpio
#          qemu-system-x86_64 -enable-kvm -m 256M -nographic -no-reboot \
#              -kernel /boot/vmlinuz-linux -initrd initrd.cpio \
#              -append "console=ttyS0 panic=1 random.trust_cpu=off quiet"
#      Measured 2026-09-27 on the 6.6.7 heap: -m 256M PANICS (the two lines above); -m 512M
#      boots. On the 6.6.8 heap: -m 256M, -m 160M and -m 96M all print PID1-ALLOC-OK.
#
# MUTATION LEDGER (6.6.8, scratch copies of lib/alloc.cyr)
#   * the 6.6.7 lib/alloc.cyr                      -> rows 1, 2 and 3 FAIL (row 2: exit 1, "alloc_init:
#                                                      mmap failed"; row 3's probe names the new
#                                                      `_linux_grain` and does not compile)
#   * NORESERVE dropped, fallback kept              -> row 1 FAIL; row 2 still green (RLIMIT_AS
#                                                      is not the heuristic — that is why row 1 exists)
#   * fallback dropped, NORESERVE kept              -> row 2 FAIL (exit 1); row 1 green
#   * the `min > g` guard dropped (a refused big
#     request lowers the grain)                     -> row 3 FAIL (grain 16 MB)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: alloc_first_chunk_small_board: build/cycc missing"; exit 1; }
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) : ;;
    *) echo "SKIP: alloc_first_chunk_small_board: x86_64 Linux only"; exit 0 ;;
esac
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: alloc_first_chunk_small_board: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: alloc_first_chunk_small_board: $*"; FAIL=1; }

# ── row 1: the first chunk is MAP_NORESERVE ──────────────────────────────────────────
cat > "$W/nr.cyr" <<'CYR'
include "lib/alloc.cyr"

# Parse lowercase hex at p..; stops at the first non-hex byte. *endp <- index past it.
fn _hex(buf, i, endp): i64 {
    var v = 0;
    while (1 == 1) {
        var c = load8(buf + i);
        var d = 0 - 1;
        if (c >= 48) { if (c <= 57) { d = c - 48; } }
        if (c >= 97) { if (c <= 102) { d = c - 87; } }
        if (d < 0) { break; }
        v = v * 16 + d;
        i = i + 1;
    }
    store64(endp, i);
    return v;
}

fn main(): i64 {
    var p = alloc(64);
    if (p == 0) { return 3; }
    store64(p, 1);
    var cap = 4194304;
    var buf = alloc(cap);
    if (buf == 0) { return 4; }
    var fd = syscall(2, "/proc/self/smaps", 0, 0);
    if (fd < 0) { return 5; }
    var n = 0;
    while (n < cap - 1) {
        var r = syscall(0, fd, buf + n, cap - 1 - n);
        if (r <= 0) { break; }
        n = n + r;
    }
    syscall(3, fd);
    store8(buf + n, 0);
    # Walk lines: a range line "start-end ..." sets `inside`; the next VmFlags line decides.
    var i = 0;
    var inside = 0;
    var e = 0;
    while (i < n) {
        var ls = i;
        var c0 = load8(buf + i);
        var ishex = 0;
        if (c0 >= 48) { if (c0 <= 57) { ishex = 1; } }
        if (c0 >= 97) { if (c0 <= 102) { ishex = 1; } }
        if (ishex == 1) {
            var lo = _hex(buf, i, &e);
            if (load8(buf + load64(&e)) == 45) {
                var hi = _hex(buf, load64(&e) + 1, &e);
                inside = 0;
                if (p >= lo) { if (p < hi) { inside = 1; } }
            }
        }
        if (inside == 1) {
            if (load8(buf + ls) == 86) {          # 'V'mFlags:
                var j = ls;
                while (load8(buf + j) != 10) {
                    if (load8(buf + j) == 32) { if (load8(buf + j + 1) == 110) { if (load8(buf + j + 2) == 114) {
                        syscall(1, 1, "nr\n", 3); return 0; } } }
                    j = j + 1;
                }
                syscall(1, 1, "no-nr\n", 6);
                return 0;
            }
        }
        while (i < n) { if (load8(buf + i) == 10) { break; } i = i + 1; }
        i = i + 1;
    }
    syscall(1, 1, "not-found\n", 10);
    return 0;
}
var ec = main();
syscall(60, ec);
CYR
"$CC" < "$W/nr.cyr" > "$W/nr" 2> "$W/nr.err" || fail "row 1: the smaps probe did not compile"
chmod +x "$W/nr" 2>/dev/null
rc=0; out=$( ulimit -c 0; "$W/nr" ) || rc=$?
if [ "$rc" -ne 0 ]; then fail "row 1: the smaps probe exited $rc"
elif [ "$out" = "not-found" ]; then fail "row 1: the heap's mapping was not found in /proc/self/smaps"
elif [ "$out" != "nr" ]; then fail "row 1: the first heap chunk is not MAP_NORESERVE (VmFlags has no 'nr') — the overcommit heuristic still sizes it"
else echo "  row 1: the first 256 MB chunk carries VmFlags nr (MAP_NORESERVE)"; fi

# ── rows 2-3: the small-grain fallback, and a refused big request keeps the grain ───────
cat > "$W/rl.cyr" <<'CYR'
include "lib/alloc.cyr"

fn main(): i64 {
    var p = alloc(64);
    if (p == 0) { return 3; }
    store64(p, 7);
    var q = alloc(40000000);                 # 40 MB: past one 16 MB grain
    if (q == 0) { return 4; }
    store64(q + 39999992, 9);
    var i = 0;
    while (i < 100) {
        var z = alloc(1000000);
        if (z == 0) { return 5; }
        store64(z, i);
        i = i + 1;
    }
    if (load64(p) != 7) { return 6; }
    # The FIRST chunk's size — read from the 6.6.7-era bookkeeping, so this probe compiles
    # (and fails by behaviour, not by an undefined name) against the old heap too.
    var first = _heap_first_end - _heap_first_base;
    if (first == 0x1000000) { syscall(1, 1, "grain16\n", 8); return 0; }
    if (first == 0x10000000) { syscall(1, 1, "grain256\n", 9); return 0; }
    return 7;
}
var ec = main();
syscall(60, ec);
CYR
cat > "$W/big.cyr" <<'CYR'
include "lib/alloc.cyr"

fn main(): i64 {
    var p = alloc(64);
    if (p == 0) { return 3; }
    var big = alloc(400000000);              # its request-sized chunk cannot fit under the limit
    if (big != 0) { return 4; }
    var after = alloc(64);
    if (after == 0) { return 5; }
    if (_linux_grain == 0x10000000) { syscall(1, 1, "grain256\n", 9); return 0; }
    if (_linux_grain == 0x1000000) { syscall(1, 1, "grain16\n", 8); return 0; }
    return 6;
}
var ec = main();
syscall(60, ec);
CYR
"$CC" < "$W/rl.cyr" > "$W/rl" 2> "$W/rl.err" || fail "row 2: the fallback probe did not compile"
BIGOK=1
"$CC" < "$W/big.cyr" > "$W/big" 2> "$W/big.err" || { BIGOK=0; fail "row 3: the big-request probe did not compile"; }
chmod +x "$W/rl" "$W/big" 2>/dev/null
rc=0; out=$( ulimit -c 0; ulimit -v 200000; "$W/rl" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ]; then fail "row 2: under ulimit -v 200000 the probe exited $rc: $out"
elif [ "$out" != "grain16" ]; then fail "row 2: under ulimit -v 200000 the heap reported '$out', not the 16 MB grain"
else echo "  row 2: under a 195 MB address-space limit the heap comes up and grows at the 16 MB grain"; fi
rc=0; out=$( ulimit -c 0; "$W/rl" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ] || [ "$out" != "grain256" ]; then
    fail "row 2 (anti-vacuous): with no limit the probe gave rc=$rc '$out', not the 256 MB grain — the fallback fires without a refusal"
fi
rc=0; out=""
[ "$BIGOK" = 1 ] && { out=$( ulimit -c 0; ulimit -v 600000; "$W/big" 2>&1 ) || rc=$?; }
if [ "$BIGOK" = 0 ]; then :
elif [ "$rc" -ne 0 ]; then fail "row 3: under ulimit -v 600000 the big-request probe exited $rc: $out"
elif [ "$out" != "grain256" ]; then fail "row 3: one refused 400 MB request dropped the grain ('$out')"
else echo "  row 3: a refused 400 MB request returns 0 and keeps the 256 MB grain"; fi

# ── row 4 (opt-in): the starved-VM PID-1 recipe ─────────────────────────────────────
if [ "${CYRIUS_ALLOC_VM:-0}" != "1" ]; then
    echo "  row 4: SKIP (the starved-VM PID-1 boot is opt-in: CYRIUS_ALLOC_VM=1)"
else
    K="${CYRIUS_VM_KERNEL:-/boot/vmlinuz-linux}"
    if [ ! -r "$K" ] || ! command -v cpio >/dev/null 2>&1 || ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        fail "row 4: CYRIUS_ALLOC_VM=1 but the kernel ($K), cpio or qemu-system-x86_64 is missing"
    else
        cat > "$W/init.cyr" <<'CYR'
include "lib/alloc.cyr"
fn main(): i64 {
    var p = alloc(64);
    if (p == 0) { syscall(1, 1, "PID1-ALLOC-NULL\n", 16); }
    else {
        store64(p, 7);
        var q = alloc(40000000);
        if (q == 0) { syscall(1, 1, "PID1-BIG-NULL\n", 14); }
        else { store64(q + 39999992, 9); syscall(1, 1, "PID1-ALLOC-OK\n", 14); }
    }
    syscall(169, 0xfee1dead, 672274793, 0x4321fedc, 0);   # reboot(POWER_OFF)
    return 0;
}
var r = main();
syscall(60, r);
CYR
        mkdir -p "$W/rootfs"
        "$CC" < "$W/init.cyr" > "$W/rootfs/init" 2> "$W/init.err" || fail "row 4: the /init probe did not compile"
        chmod 755 "$W/rootfs/init"
        ( cd "$W/rootfs" && echo init | cpio -o -H newc --quiet > "$W/initrd.cpio" )
        ACC=""; [ -w /dev/kvm ] && ACC="-enable-kvm"
        out=$(timeout 120 qemu-system-x86_64 $ACC -m 256M -nographic -no-reboot \
            -kernel "$K" -initrd "$W/initrd.cpio" \
            -append "console=ttyS0 panic=1 random.trust_cpu=off quiet" 2>&1 | tr -d '\r' || true)
        if printf '%s' "$out" | grep -q 'PID1-ALLOC-OK'; then
            echo "  row 4: PID 1 in a -m 256M VM allocates and powers off"
        else
            fail "row 4: PID 1 in a -m 256M VM did not come up: $(printf '%s' "$out" | grep -E 'PID1-|alloc_init|Kernel panic' | head -3 | tr '\n' ' ')"
        fi
    fi
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: alloc_first_chunk_small_board (first chunk MAP_NORESERVE; under a 195 MB limit the heap falls back to 16 MB chunks; a refused big request keeps the grain)"
exit 0
