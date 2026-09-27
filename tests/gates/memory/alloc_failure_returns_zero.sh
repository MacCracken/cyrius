#!/bin/sh
# Gate: a REFUSED MAPPING is a 0 return (or a loud abort at init), never a store through the
# kernel's error value (6.6.7, bite 8).
#
# ⛔ THE DEFECT (kybernet, 2026-09-23). lib/freelist.cyr's `_fl_mmap` returns the raw kernel
# result — -errno on Linux/Darwin, 0 on agnos and PE — and both callers stored through it
# unchecked: the large (>4096) path wrote its header at `blk`, and the ARENA REFILL adopted the
# result as the new arena base, so the next block header landed at -12. A refused mapping
# SIGSEGV'd at 0xfffffffffffffff4 instead of returning 0, and every consumer's `== 0` guard
# (sigil's argon2 wrappers and policy reader) was dead code. Its Windows sibling:
# lib/alloc_windows.cyr's `alloc_init` adopted VirtualAlloc's 0 unchecked, so every later
# alloc() re-ran init and returned 0 silently, while the Linux and macOS peers abort loudly.
#
# AXES
#   1. lib/freelist.cyr compiles INCLUDED ALONE on x86-Linux, aarch64, PE, agnos and Mach-O —
#      before 6.6.7 it was a HARD error (`undefined variable 'SYS_MMAP'`), because it never
#      included the syscall peer. (Not the stricter "no undefined function" bar of
#      stdlib_modules_self_sufficient.sh: lib/syscalls.cyr's own peers still warn on `alloc`.)
#   2. The ARENA REFILL under address-space exhaustion (Linux, `ulimit -v`): the probe takes
#      the first arena, maps everything the rlimit leaves, then asks for 5000 small blocks —
#      more than one arena holds. They must come back 0, not fault, and the allocator must
#      still reissue a freed block afterwards. ANTI-VACUOUS: the probe exits 4 if no request
#      was refused, so a rlimit that stopped biting cannot score a PASS. The large path is
#      pinned portably on real hardware by tests/tcyr/crossos/freelist_map_failure.tcyr.
#   3. PE `alloc_init` with a heap size VirtualAlloc refuses must exit 1 and say
#      `alloc_init: mmap failed` (wine; SKIPs, named, without it — wine is not hardware).
#   3s. STATIC half of 3, which runs everywhere: alloc_windows.cyr's alloc_init checks the
#      mapping (`<= 0`) before adopting it.
#
# MUTATION LEDGER (6.6.7, each built as a scratch lib/ copy)
#   * the 6.6.6 freelist                                  -> axis 1 FAIL (SYS_MMAP undefined)
#   * 6.6.6 freelist + the syscalls include only          -> axis 2 FAIL (rc 139)
#   * the refill `na <= 0` check removed                  -> axis 2 FAIL (rc 139)
#   * fl_alloc's `blk == 0` after the refill removed      -> axis 2 FAIL (rc 139)
#   * the 6.6.6 alloc_windows.cyr                         -> axis 3 FAIL (rc 7: init returned)
#                                                            and axis 3s FAIL
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
CCA="$ROOT/build/cycc_aarch64"

[ -x "$CC" ] || { echo "FAIL: alloc_failure_returns_zero: build/cycc missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: alloc_failure_returns_zero: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: alloc_failure_returns_zero: $*"; FAIL=1; }

# ── axis 1: freelist.cyr included alone compiles on every target ─────────────────────
printf 'include "lib/freelist.cyr";\nvar _p = fl_alloc(8);\nsyscall(60, 0);\n' > "$W/alone.cyr"
n1=0
for te in "x86:$CC:" "aarch64:$CCA:" "pe:$CC:CYRIUS_TARGET_WIN=1" "agnos:$CC:CYRIUS_TARGET_AGNOS=1" "macho:$CC:CYRIUS_MACHO=1"; do
    tn=${te%%:*}; rest=${te#*:}; tc=${rest%%:*}; tenv=${rest#*:}
    [ -x "$tc" ] || { fail "axis 1: compiler for $tn missing ($tc)"; continue; }
    if [ -n "$tenv" ]; then env "$tenv" "$tc" --allow-undef < "$W/alone.cyr" > "$W/alone.bin" 2> "$W/alone.err"; rc=$?
    else "$tc" --allow-undef < "$W/alone.cyr" > "$W/alone.bin" 2> "$W/alone.err"; rc=$?; fi
    if [ "$rc" -ne 0 ] || grep -q 'undefined variable' "$W/alone.err"; then
        fail "axis 1: \`include \"lib/freelist.cyr\"\` alone does not compile for $tn:"; grep -m3 'error' "$W/alone.err" | sed 's/^/      /'
    fi
    n1=$((n1 + 1))
done
[ "$n1" -eq 5 ] || fail "axis 1: checked $n1 of 5 targets"

# ── axis 2: the arena refill under address-space exhaustion (Linux) ──────────────────
cat > "$W/refill.cyr" <<'EOF'
include "lib/freelist.cyr"

fn main(): i64 {
    var first = fl_alloc(8);
    if (first == 0) { return 3; }
    # Exhaust the address space the rlimit leaves: 1 MiB maps, then 4 KiB maps.
    while (syscall(SYS_MMAP, 0, 1048576, 3, 0x22, 0 - 1, 0) > 0) { }
    while (syscall(SYS_MMAP, 0, 4096, 3, 0x22, 0 - 1, 0) > 0) { }
    # 5000 x 32-byte blocks = 160 KB > one 64 KiB arena: a refill MUST be attempted.
    var zeros = 0;
    var last = 0;
    var i = 0;
    while (i < 5000) {
        var p = fl_alloc(8);
        if (p == 0) { zeros = zeros + 1; } else { store64(p, i); last = p; }
        i = i + 1;
    }
    if (zeros == 0) { return 4; }
    if (last == 0) { return 5; }
    fl_free(last);
    var again = fl_alloc(8);
    if (again != last) { return 6; }
    syscall(1, 1, "returned\n", 9);
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
"$CC" < "$W/refill.cyr" > "$W/refill" 2> "$W/refill.err" || fail "axis 2: the refill probe did not compile"
chmod +x "$W/refill" 2>/dev/null
out=$( ulimit -c 0; ulimit -v 600000 2>/dev/null; "$W/refill" 2>&1 ); rc=$?
case "$rc" in
    0) [ "$out" = "returned" ] || fail "axis 2: probe exited 0 but printed '$out'" ;;
    4) fail "axis 2 (anti-vacuous): no fl_alloc was refused under ulimit -v 600000 — the exhaustion did not bite, so this axis tested nothing" ;;
    6) fail "axis 2: after refused refills, a freed block was not reissued — the failed refill corrupted allocator state" ;;
    *) fail "axis 2: fl_alloc under address-space exhaustion exited $rc (139 = it stored through the refused mapping's -ENOMEM)" ;;
esac

# ── axis 3s: alloc_windows' alloc_init checks VirtualAlloc before adopting it ────────
awk '/^fn alloc_init/{f=1} f&&/^}/{exit} f' lib/alloc_windows.cyr > "$W/init.txt"
grep -q 'if (base <= 0)' "$W/init.txt" && grep -q 'alloc_init: mmap failed' "$W/init.txt" \
    || fail "axis 3s: lib/alloc_windows.cyr alloc_init does not check the VirtualAlloc result before adopting it as the heap base"

# ── axis 3: PE alloc_init fails LOUDLY under wine ────────────────────────────────────
cat > "$W/winit.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"

fn main(): i64 {
    _WIN_HEAP_SIZE = 1 << 46;      # 64 TiB: VirtualAlloc refuses it
    var b = alloc_init();
    syscall(1, 1, "alloc_init returned\n", 20);
    if (b == 0) { return 7; }
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
# The PE probe is built by build/cycc with CYRIUS_TARGET_WIN=1 (how install.sh builds the PE
# compiler), not by build/cycc_win, which IS a PE32+ binary and only runs through wine.
if ! command -v wine >/dev/null 2>&1; then
    echo "  SKIP: axis 3 (PE alloc_init abort) — wine not installed; axis 3s still checked"
else
    CYRIUS_TARGET_WIN=1 "$CC" < "$W/winit.cyr" > "$W/winit.exe" 2>/dev/null || fail "axis 3: the PE probe did not compile"
    ( cd "$W" && WINEDEBUG=-all timeout 120 wine ./winit.exe > wo.txt 2> we.txt ); wrc=$?
    if [ "$wrc" -ne 1 ]; then
        fail "axis 3: PE alloc_init with a refused VirtualAlloc exited $wrc, expected 1 (7 = it RETURNED with a 0 heap base, the silent pre-6.6.7 behaviour)"
    elif ! tr -d '\r' < "$W/we.txt" | grep -q 'alloc_init: mmap failed'; then
        fail "axis 3: PE alloc_init exited 1 but did not say 'alloc_init: mmap failed' on stderr"
    fi
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: alloc_failure_returns_zero (freelist.cyr includes alone on 5 targets; refused arena refills return 0 and the allocator recovers; PE alloc_init aborts loudly)"
