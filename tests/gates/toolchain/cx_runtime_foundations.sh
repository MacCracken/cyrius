#!/bin/sh
# Gate: the cx runtime foundations a .cyx guest stands on (v6.6.8).
#
# THREE DEFECTS, ONE SYMPTOM — every cx process hashed with the same published seed:
#   (a) lib/atomic.cyr had no cx arm. Its x86 / aarch64 bodies are inline asm under
#       CYRIUS_ARCH_*, cx predefines neither, so atomic_cas and atomic_fetch_add compiled to
#       EMPTY bodies: every CAS reported failure and swapped nothing. lib/hashseed.cyr drew a
#       seed, lost the "race" against nobody, and returned the unpublished `_hm_seed` — 0.
#       (Any `while (atomic_cas(...) == 0)` lock would have spun forever.)
#   (b) cxvm translated guest pointers only for read/write/open. getrandom(318) handed the
#       host a raw guest OFFSET as its buffer and got EFAULT; the clock fallback,
#       clock_gettime(228), did the same — so even with (a) fixed the seed was the constant
#       the fallback computes from -EFAULT (0xf758f75a05, measured). Translating was not
#       enough on real hardware: 318 is unassigned on aarch64-Linux (pi: ENOSYS), Windows has
#       no getrandom syscall, and neither macOS clock route fills a timespec — so both calls
#       are served by the HOST's stdlib (sys_getrandom, lib/chrono.cyr) in the guest's
#       Linux shape.
#   (c) cxvm's register file was alloc(256) — 32 registers — while a register operand is a
#       full byte and the backend keeps fp/sp in r253/r254. fp/sp therefore lived INSIDE the
#       next allocation, _cx_mem, at guest offsets 1768/1776: every call rewrote guest data
#       there and a guest store there rewrote the stack pointer. Pass or fail tracked CODE
#       SIZE (6.6.7 triage: adding one unrelated fn flipped a cx row).
# And (d): tests/tcyr/crossos/call_site_stack_alignment.tcyr said its value rows "run on every
# target including cx", but the file did not compile for cx at all (one f64_exp row).
#
# ROWS
#   1. register file: a guest array spanning offsets 1768..1784 survives a 20-deep recursion
#      intact (exit 42). The probe itself checks that the array really covers the aliased
#      offsets (exit 201/202) so code growth cannot quietly move it out of range. 6.6.7: SIGSEGV.
#   2. atomic_cas / atomic_fetch_add semantics on cxvm (swap, refuse, old value, add), and the
#      same probe natively (x86 lock cmpxchg / xadd) — one probe, two targets, same answers.
#   3. tests/tcyr/crossos/hashseed_os_rng_source.tcyr passes on cxvm: the seed is non-zero,
#      drawn ONCE, and came from the OS RNG (`_hm_seed_src == 1`), not the time fallback.
#   4. the seed VARIES across three cxvm runs of one .cyx (a .tcyr cannot see this).
#   5. clock_gettime through cxvm keeps the LINUX contract on the host it runs on: rc 0 and a
#      filled timespec, for CLOCK_REALTIME (tv_sec past 2020) and CLOCK_MONOTONIC. The host's
#      raw syscall(228) does not keep it everywhere — arm64-macOS returned ns and left the
#      timespec at 0 (measured on ecb) — so cxvm serves it from lib/chrono.cyr.
#   6. call_site_stack_alignment.tcyr compiles for cx and its value rows pass on cxvm.
#   7. rows 3 and 5's fixtures on an aarch64-Linux cxvm (qemu-aarch64) and a PE cxvm (wine),
#      where the host's raw 318 / 228 do NOT keep the guest's contract. Real hardware (pi,
#      ecb, ach, cass) was run by hand at 6.6.8: rows 1-6 green on all four.
#
# MUTATION LEDGER (6.6.8, measured; each mutation alone)
#   * cxvm register file back to 256 bytes               -> row 1 FAIL (rc 139)
#   * lib/atomic.cyr's CYRIUS_TARGET_CX arms removed      -> rows 2, 3, 4 FAIL (row 2 exits 11 —
#                                                            the first CAS "fails"; seed 0 on
#                                                            every run)
#   * cxvm's getrandom(318) translation removed           -> rows 3, 4 FAIL (`_hm_seed_src` 2; the
#                                                            clock fallback repeats within a second)
#   * cxvm's clock_gettime(228) translation removed       -> row 5 FAIL (exit 10: rc -EFAULT)
#   * the #ifndef CYRIUS_TARGET_CX around the f64_exp row  -> row 6 FAIL ("this float op is not
#                                                            yet supported on the cx bytecode target")
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: cx_runtime_foundations: build/cycc missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: cx_runtime_foundations: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: cx_runtime_foundations: $*"; FAIL=1; }

"$CC" < src/main_cx.cyr > "$W/cycc_cx" 2> "$W/b1.err" || { echo "FAIL: cx_runtime_foundations: building cycc_cx failed"; exit 1; }
"$CC" < programs/cxvm.cyr > "$W/cxvm" 2> "$W/b2.err" || { echo "FAIL: cx_runtime_foundations: building cxvm failed"; exit 1; }
chmod +x "$W/cycc_cx" "$W/cxvm"

# cx <name> <source file> : compile for cx into $W/<name>.cyx; 1 on failure
cx() {
    if ! "$W/cycc_cx" < "$2" > "$W/$1.cyx" 2> "$W/$1.err"; then
        return 1
    fi
    return 0
}
# vm <name> : run $W/<name>.cyx on cxvm; stdout in $W/<name>.out, status in VMRC
vm() { VMRC=0; ( ulimit -c 0; timeout 60 "$W/cxvm" < "$W/$1.cyx" > "$W/$1.out" 2>&1 ) || VMRC=$?; }

# ── row 1: fp/sp no longer alias guest memory ────────────────────────────────────────
cat > "$W/alias.cyr" <<'CYR'
var arr[512];
fn fill(v): i64 { var i = 0; while (i < 512) { store64(&arr + i * 8, v + i); i = i + 1; } return 0; }
fn deep(n): i64 { if (n == 0) { return 0; } return deep(n - 1) + 1; }
fn check(v): i64 { var i = 0; while (i < 512) { if (load64(&arr + i * 8) != v + i) { return i + 1; } i = i + 1; } return 0; }
fn main(): i64 {
    var a = &arr;
    if (a > 1768) { return 201; }
    if (a + 4096 < 1784) { return 202; }
    fill(7000);
    deep(20);
    if (check(7000) != 0) { return 100; }
    return 42;
}
var e = main();
syscall(60, e);
CYR
if ! cx alias "$W/alias.cyr"; then fail "row 1: the alias probe does not compile for cx: $(head -2 "$W/alias.err")"
else
    vm alias
    case "$VMRC" in
        42) echo "  row 1: guest data at offsets 1768..1784 survives calls (fp/sp are in the register file)" ;;
        201|202) fail "row 1: the probe's array no longer covers guest offsets 1768..1784 (exit $VMRC) — the cx code grew; shrink the probe" ;;
        *) fail "row 1: guest data at the fp/sp offsets was clobbered (exit $VMRC)" ;;
    esac
fi

# ── row 2: atomic_cas / atomic_fetch_add semantics, cx and native ──────────────────────
cat > "$W/atom.cyr" <<'CYR'
include "lib/atomic.cyr"
var cell = 5;
fn main(): i64 {
    if (atomic_cas(&cell, 5, 9) != 1) { return 11; }
    if (cell != 9) { return 12; }
    if (atomic_cas(&cell, 5, 1) != 0) { return 13; }
    if (cell != 9) { return 14; }
    if (atomic_fetch_add(&cell, 3) != 9) { return 15; }
    if (cell != 12) { return 16; }
    if (atomic_fetch_add(&cell, 0 - 12) != 12) { return 17; }
    if (cell != 0) { return 18; }
    return 42;
}
var e = main();
syscall(60, e);
CYR
if ! cx atom "$W/atom.cyr"; then fail "row 2: the atomic probe does not compile for cx: $(head -2 "$W/atom.err")"
else
    vm atom
    if [ "$VMRC" = 42 ]; then echo "  row 2: atomic_cas / atomic_fetch_add swap, refuse, return old and add on cxvm"
    else fail "row 2: the atomic probe exited $VMRC on cxvm (11-18 = the failing step)"; fi
fi
"$CC" < "$W/atom.cyr" > "$W/atom_nat" 2>/dev/null && chmod +x "$W/atom_nat"
nrc=0; "$W/atom_nat" || nrc=$?
[ "$nrc" = 42 ] || fail "row 2: the same probe exited $nrc NATIVELY — the cx answers would prove nothing"

# ── row 3: the hashseed .tcyr on cxvm ─────────────────────────────────────────────────
HS=tests/tcyr/crossos/hashseed_os_rng_source.tcyr
if ! cx hs "$HS"; then fail "row 3: $HS does not compile for cx: $(head -2 "$W/hs.err")"
else
    vm hs
    if [ "$VMRC" = 0 ] && grep -q ' 0 failed' "$W/hs.out"; then echo "  row 3: $HS passes on cxvm (seed non-zero, drawn once, from the OS RNG)"
    else fail "row 3: $HS on cxvm exited $VMRC: $(grep 'FAIL' "$W/hs.out" | head -3 | tr '\n' ' ')"; fi
fi

# ── row 4: the seed varies across runs ──────────────────────────────────────────────
cat > "$W/seed.cyr" <<'CYR'
include "lib/hashseed.cyr"
var hexbuf[4];
fn main(): i64 {
    var v = _hm_seed_get();
    var p = &hexbuf;
    var i = 0;
    while (i < 16) {
        var d = (v >> (60 - i * 4)) & 15;
        if (d < 10) { store8(p + i, 48 + d); } else { store8(p + i, 87 + d); }
        i = i + 1;
    }
    syscall(1, 1, p, 16);
    syscall(1, 1, "\n", 1);
    return 0;
}
var e = main();
syscall(60, e);
CYR
if ! cx seed "$W/seed.cyr"; then fail "row 4: the seed probe does not compile for cx: $(head -2 "$W/seed.err")"
else
    : > "$W/seeds"
    for i in 1 2 3; do vm seed; cat "$W/seed.out" >> "$W/seeds"; done
    nz=$(grep -c -v '^0000000000000000$' "$W/seeds" || true)
    nd=$(sort -u "$W/seeds" | wc -l | tr -d ' ')
    if [ "$nz" != 3 ]; then fail "row 4: a cx seed was 0 (the unpublished sentinel): $(tr '\n' ' ' < "$W/seeds")"
    elif [ "$nd" -lt 3 ]; then fail "row 4: the cx seed repeated across three runs: $(tr '\n' ' ' < "$W/seeds")"
    else echo "  row 4: three cxvm runs, three distinct non-zero seeds"; fi
fi

# ── row 5: clock_gettime fills the guest's timespec ─────────────────────────────────
cat > "$W/clk.cyr" <<'CYR'
var ts[2];
fn main(): i64 {
    store64(&ts, 0);
    store64(&ts + 8, 0 - 1);
    var r = syscall(228, 0, &ts);                       # CLOCK_REALTIME
    if (r != 0) { return 10; }
    if (load64(&ts) < 1577836800) { return 11; }        # tv_sec past 2020
    if (load64(&ts + 8) < 0) { return 12; }             # tv_nsec written, in range
    if (load64(&ts + 8) >= 1000000000) { return 12; }
    store64(&ts, 0 - 1);
    store64(&ts + 8, 0 - 1);
    r = syscall(228, 1, &ts);                           # CLOCK_MONOTONIC
    if (r != 0) { return 13; }
    if (load64(&ts) < 0) { return 14; }
    if (load64(&ts + 8) < 0) { return 14; }
    if (load64(&ts + 8) >= 1000000000) { return 14; }
    return 42;
}
var e = main();
syscall(60, e);
CYR
if ! cx clk "$W/clk.cyr"; then fail "row 5: the clock probe does not compile for cx"
else
    vm clk
    if [ "$VMRC" = 42 ]; then echo "  row 5: clock_gettime through cxvm fills the guest timespec"
    else fail "row 5: clock_gettime on cxvm exited $VMRC (10/13 = non-zero rc; 11/12 realtime, 14 monotonic timespec not filled)"; fi
fi

# ── row 6: call_site_stack_alignment.tcyr runs its value rows on cx ─────────────────────
CS=tests/tcyr/crossos/call_site_stack_alignment.tcyr
if ! cx cs "$CS"; then fail "row 6: $CS does not compile for cx: $(grep -m1 error "$W/cs.err")"
else
    vm cs
    if [ "$VMRC" = 0 ] && grep -q ' 0 failed' "$W/cs.out"; then echo "  row 6: $CS compiles for cx and passes on cxvm"
    else fail "row 6: $CS on cxvm exited $VMRC: $(grep 'FAIL' "$W/cs.out" | head -3 | tr '\n' ' ')"; fi
fi

# ── row 7: the same .cyx on an aarch64-Linux and a PE cxvm (qemu-aarch64 / wine) ──────
# Rows 3 and 5 on an x86-Linux host cannot see the host-routing half of (b): the host's raw
# 318/228 happen to work here. On aarch64-Linux 318 is ENOSYS and on PE neither exists, so
# the same fixtures run on those cxvms too. Emulators are not hardware (the real legs are
# pi and cass — recorded in the CHANGELOG entry); each leg SKIPs, named, without its tool.
foreign() {   # $1 label, $2 runner prefix ("" or "qemu-aarch64" / "wine"), $3 cxvm binary
    # Returns non-zero when this leg failed, so the caller prints its success line only
    # for a leg that added no failure (a red log must not also claim the leg passed).
    LEGFAIL=0
    for fx in hs clk; do
        FRC=0
        ( cd "$W" && ulimit -c 0; WINEDEBUG=-all timeout 180 $2 "$3" < "$W/$fx.cyx" > "$W/$fx.$1.out" 2>&1 ) || FRC=$?
        if [ "$fx" = hs ]; then
            if [ "$FRC" != 0 ] || ! tr -d '\r' < "$W/$fx.$1.out" | grep -q ' 0 failed'; then
                fail "row 7: $HS on the $1 cxvm exited $FRC: $(tr -d '\r' < "$W/$fx.$1.out" | grep FAIL | head -2 | tr '\n' ' ')"
                LEGFAIL=1
            fi
        elif [ "$FRC" != 42 ]; then
            fail "row 7: clock_gettime on the $1 cxvm exited $FRC (10/13 = non-zero rc; 11/12 realtime, 14 monotonic timespec not filled)"
            LEGFAIL=1
        fi
    done
    return "$LEGFAIL"
}
if [ -f "$W/hs.cyx" ] && [ -f "$W/clk.cyx" ]; then
    if command -v qemu-aarch64 >/dev/null 2>&1; then
        if "$CC" < src/main_aarch64.cyr > "$W/cc_a64" 2>/dev/null && chmod +x "$W/cc_a64" \
            && "$W/cc_a64" < programs/cxvm.cyr > "$W/cxvm_a64" 2>/dev/null && chmod +x "$W/cxvm_a64"; then
            if foreign aarch64 qemu-aarch64 "$W/cxvm_a64"; then
                echo "  row 7: aarch64-Linux cxvm (qemu-aarch64): OS-RNG seed + filled timespec"
            fi
        else fail "row 7: building the aarch64 cxvm failed"; fi
    else echo "  row 7: SKIP aarch64 leg (qemu-aarch64 not installed)"; fi
    if command -v wine >/dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < programs/cxvm.cyr > "$W/cxvm.exe" 2>/dev/null; then
            if foreign pe wine "$W/cxvm.exe"; then
                echo "  row 7: PE cxvm (wine): ProcessPrng seed + filled timespec"
            fi
        else fail "row 7: building the PE cxvm failed"; fi
    else echo "  row 7: SKIP PE leg (wine not installed)"; fi
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: cx_runtime_foundations (register file holds fp/sp; atomics work on cx; the hash seed is published, OS-drawn and varies; clock_gettime translated; call_site_stack_alignment runs on cx)"
exit 0
