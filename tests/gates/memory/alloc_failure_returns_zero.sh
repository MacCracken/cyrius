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
#   4. `fhm_new` (lib/hashmap_fast.cyr) and `flags_new` (lib/flags.cyr) return 0 over an
#      exhausted heap (Linux, `ulimit -v`; anti-vacuous: the probe proves alloc is refusing).
#   5. EVERY allocation check in fhm_new (4), flags_new (3), _fhm_grow (3) and the FLAG_LIST
#      first push (2), ONE AT A TIME: per-call fault injection refuses only the k-th alloc, for
#      each k over the site's whole count. Axes 2/4 refuse by size, which is monotonic, so the
#      first check to fire masks the rest — with fhm_new's keys OR vals check removed they still
#      passed. Anti-vacuous both ways: the k-th call must be reached, and k = count + 1 succeeds.
#
# MUTATION LEDGER (6.6.7, each built as a scratch lib/ copy)
#   * the 6.6.6 freelist                                  -> axis 1 FAIL (SYS_MMAP undefined)
#   * 6.6.6 freelist + the syscalls include only          -> axis 2 FAIL (rc 139)
#   * the refill `na <= 0` check removed                  -> axis 2 FAIL (rc 139)
#   * fl_alloc's `blk == 0` after the refill removed      -> axis 2 FAIL (rc 139)
#   * the 6.6.6 alloc_windows.cyr                         -> axis 3 FAIL (rc 7: init returned)
#                                                            and axis 3s FAIL
#   * the 6.6.6 hashmap_fast.cyr                          -> axis 4 FAIL (rc 139)
#   * flags_new's three checks removed                    -> axis 4 FAIL (rc 139)
#   * ANY ONE of the 12 checks below removed ALONE         -> axis 5 FAIL (axis 4 and the tcyrs
#     stay green for most of them — that masking is why axis 5 exists):
#       fhm_new m / meta, _fhm_grow new_meta / new_keys / new_vals,
#       flags_new h / entries, _flags_list_push nblk / arr  -> rc 139
#       fhm_new keys / vals, flags_new positional           -> rc 1 (returned an object)
set -u
# Every expected-non-zero status is captured as `rc=0; ... || rc=$?`, so the gate reports the
# same verdict under `bash -eo pipefail` as under sh (a bare `( ... ); rc=$?` trips -e first).
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
rc=0; out=$( ulimit -c 0; ulimit -v 600000 2>/dev/null; "$W/refill" 2>&1 ) || rc=$?
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
    wrc=0; ( cd "$W" && WINEDEBUG=-all timeout 120 wine ./winit.exe > wo.txt 2> we.txt ) || wrc=$?
    if [ "$wrc" -ne 1 ]; then
        fail "axis 3: PE alloc_init with a refused VirtualAlloc exited $wrc, expected 1 (7 = it RETURNED with a 0 heap base, the silent pre-6.6.7 behaviour)"
    elif ! tr -d '\r' < "$W/we.txt" | grep -q 'alloc_init: mmap failed'; then
        fail "axis 3: PE alloc_init exited 1 but did not say 'alloc_init: mmap failed' on stderr"
    fi
fi

# ── axis 4: constructors over an EXHAUSTED heap return 0 (Linux, `ulimit -v`) ──────────
# fhm_new and flags_new stored through their allocations unchecked. The probe exhausts the
# address space, then drains the bump heap's current chunk (alloc until 0) so the next alloc
# genuinely has nowhere to go. Their GROWTH halves are pinned deterministically on every host
# by tests/tcyr/stdlib/hashmap_fast_grow_refused.tcyr and tests/tcyr/crossos/flags.tcyr.
cat > "$W/ctor.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/vec.cyr"
include "lib/hashmap_fast.cyr"
include "lib/flags.cyr"

fn main(): i64 {
    alloc_init();
    while (syscall(SYS_MMAP, 0, 1048576, 3, 0x22, 0 - 1, 0) > 0) { }
    while (syscall(SYS_MMAP, 0, 4096, 3, 0x22, 0 - 1, 0) > 0) { }
    while (alloc(4096) != 0) { }
    while (alloc(8) != 0) { }
    if (alloc(8) != 0) { return 4; }          # anti-vacuous: the heap really is exhausted
    if (fhm_new() != 0) { return 5; }
    if (flags_new() != 0) { return 6; }
    syscall(1, 1, "returned\n", 9);
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
"$CC" < "$W/ctor.cyr" > "$W/ctor" 2> "$W/ctor.err" || fail "axis 4: the constructor probe did not compile"
chmod +x "$W/ctor" 2>/dev/null
rc=0; out=$( ulimit -c 0; ulimit -v 600000 2>/dev/null; "$W/ctor" 2>&1 ) || rc=$?
case "$rc" in
    0) [ "$out" = "returned" ] || fail "axis 4: probe exited 0 but printed '$out'" ;;
    4) fail "axis 4 (anti-vacuous): alloc still succeeded after the drain — the heap was not exhausted, so this axis tested nothing" ;;
    5|6) fail "axis 4: a constructor returned non-zero over an exhausted heap (rc $rc: 5 = fhm_new, 6 = flags_new)" ;;
    *) fail "axis 4: a constructor over an exhausted heap exited $rc (139 = it stored through a refused allocation)" ;;
esac

# ── axis 5: EVERY allocation check, ONE AT A TIME (per-call fault injection, Linux) ────
# Axes 2/4 and the tcyr rows refuse by SIZE (address-space exhaustion, a planted capacity past
# ALLOC_MAX). A size refusal is MONOTONIC — once one request fails, every later request as large
# fails too — so the first check to fire hides the ones after it: fhm_new's keys and vals are
# the same size, and with either check removed the other still returns 0. Only refusing the Nth
# call ALONE separates them. This axis compiles the probe against a copy of lib/ whose `alloc`
# is wrapped: armed with k, the k-th alloc from now returns 0 and every other call is served.
# Each constructor / grow runs once per k over its whole allocation count and must, for every
# k, fail cleanly (0 / -1 / FLAG_ERR_NOMEM) with the object unchanged, must actually have
# reached the k-th call (anti-vacuous), and must SUCCEED at k = count + 1 (so the count is
# exact, and an allocation added later is covered by the same loop). The wrapper is derived
# from the live lib/alloc.cyr by renaming its Linux `fn alloc`, so it cannot drift from it.
FI="$W/fi"
mkdir -p "$FI"
cp -R "$ROOT/lib" "$FI/lib"
if [ "$(grep -c '^fn alloc(size): i64 {$' "$ROOT/lib/alloc.cyr")" != "1" ]; then
    fail "axis 5: lib/alloc.cyr no longer has exactly one 'fn alloc(size): i64 {' to wrap — update the fault-injection harness"
else
    sed 's/^fn alloc(size): i64 {$/fn _fi_real_alloc(size): i64 {/' "$ROOT/lib/alloc.cyr" > "$FI/lib/alloc.cyr"
    cat >> "$FI/lib/alloc.cyr" <<'CYR'

# ── gate-only fault injection (tests/gates/memory/alloc_failure_returns_zero.sh axis 5) ──
var _fi_at = 0;      # armed: the _fi_at-th alloc from now returns 0; 0 = disarmed
var _fi_seen = 0;
fn alloc(size): i64 {
    if (_fi_at > 0) {
        _fi_seen = _fi_seen + 1;
        if (_fi_seen == _fi_at) { _fi_at = 0; return 0; }
    }
    return _fi_real_alloc(size);
}
fn _fi_arm(k): i64 { _fi_at = k; _fi_seen = 0; return 0; }
CYR
    cat > "$FI/fi.cyr" <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/vec.cyr"
include "lib/hashmap_fast.cyr"
include "lib/flags.cyr"

# Report "<site> k=<k>: <what>" on stderr and exit 1 (an 8-bit status cannot carry the site).
fn _bad(site, k, what): i64 {
    _fi_at = 0;
    var d = alloc(8);
    store8(d, 48 + k);
    syscall(1, 2, site, strlen(site));
    syscall(1, 2, " k=", 3);
    syscall(1, 2, d, 1);
    syscall(1, 2, ": ", 2);
    syscall(1, 2, what, strlen(what));
    syscall(1, 2, "\n", 1);
    return 1;
}

fn _key(i): i64 {
    var k = alloc(8);
    store8(k, 97 + (i % 26));
    store8(k + 1, 65 + (i / 26));
    store8(k + 2, 0);
    return k;
}

fn main(): i64 {
    alloc_init();
    # fhm_new: m, meta, keys, vals
    var k = 1;
    while (k <= 5) {
        _fi_arm(k);
        var m = fhm_new();
        if (k <= 4) {
            if (m != 0) { return _bad("fhm_new", k, "returned a map although that allocation was refused"); }
            if (_fi_at != 0) { return _bad("fhm_new", k, "never reached the k-th allocation"); }
        } else { if (m == 0) { return _bad("fhm_new", k, "failed with every allocation served (count is no longer 4)"); } }
        k = k + 1;
    }
    # flags_new: h, entries, positional
    k = 1;
    while (k <= 4) {
        _fi_arm(k);
        var h = flags_new();
        if (k <= 3) {
            if (h != 0) { return _bad("flags_new", k, "returned a context although that allocation was refused"); }
            if (_fi_at != 0) { return _bad("flags_new", k, "never reached the k-th allocation"); }
        } else { if (h == 0) { return _bad("flags_new", k, "failed with every allocation served (count is no longer 3)"); } }
        k = k + 1;
    }
    # _fhm_grow (behind fhm_set): new_meta, new_keys, new_vals. 14 keys fill a 16-slot table to
    # the 87.5% trigger, so the 15th set grows.
    _fi_at = 0;
    var keys = alloc(15 * 8);
    var i = 0;
    while (i < 15) { store64(keys + i * 8, _key(i)); i = i + 1; }
    k = 1;
    while (k <= 4) {
        _fi_at = 0;
        var gm = fhm_new();
        if (gm == 0) { return _bad("_fhm_grow", k, "setup: fhm_new failed"); }
        i = 0;
        while (i < 14) { fhm_set(gm, load64(keys + i * 8), i + 100); i = i + 1; }
        if (fhm_cap(gm) != 16) { return _bad("_fhm_grow", k, "setup: 14 keys did not stay in a 16-slot table"); }
        var meta0 = load64(gm);
        _fi_arm(k);
        var r = fhm_set(gm, load64(keys + 14 * 8), 114);
        if (k <= 3) {
            if (r != 0 - 1) { return _bad("_fhm_grow", k, "fhm_set did not return -1 for a refused grow"); }
            if (_fi_at != 0) { return _bad("_fhm_grow", k, "never reached the k-th allocation"); }
            if (load64(gm) != meta0) { return _bad("_fhm_grow", k, "the live table was replaced"); }
            if (fhm_cap(gm) != 16) { return _bad("_fhm_grow", k, "the capacity changed"); }
            if (fhm_count(gm) != 14) { return _bad("_fhm_grow", k, "the count changed"); }
            i = 0;
            while (i < 14) {
                if (fhm_get(gm, load64(keys + i * 8)) != i + 100) { return _bad("_fhm_grow", k, "a held key no longer maps to its value"); }
                i = i + 1;
            }
        } else {
            _fi_at = 0;
            if (r != 0) { return _bad("_fhm_grow", k, "the grow failed with every allocation served (count is no longer 3)"); }
            if (fhm_cap(gm) != 32) { return _bad("_fhm_grow", k, "the table did not grow to 32"); }
        }
        k = k + 1;
    }
    # FLAG_LIST first push (_flags_list_push): the {ptr,cap,count} block, then its array
    k = 1;
    while (k <= 3) {
        _fi_at = 0;
        var fh = flags_new();
        if (fh == 0) { return _bad("_flags_list_push", k, "setup: flags_new failed"); }
        var li = flags_add_list(fh, 68, "define", "define");
        var ep = _flags_entry(fh, li);
        _fi_arm(k);
        var lr = _flags_list_push(ep, "A");
        if (k <= 2) {
            if (lr != FLAG_ERR_NOMEM) { return _bad("_flags_list_push", k, "not FLAG_ERR_NOMEM for a refused allocation"); }
            if (_fi_at != 0) { return _bad("_flags_list_push", k, "never reached the k-th allocation"); }
            if (load64(ep + 24) != 0) { return _bad("_flags_list_push", k, "a half-built list was installed"); }
        } else {
            _fi_at = 0;
            if (lr != FLAG_ERR_NONE) { return _bad("_flags_list_push", k, "failed with every allocation served (count is no longer 2)"); }
            if (flags_list_count(fh, li) != 1) { return _bad("_flags_list_push", k, "the value was not kept"); }
        }
        k = k + 1;
    }
    syscall(1, 1, "returned\n", 9);
    return 0;
}
var ec = main();
syscall(60, ec);
CYR
    ( cd "$FI" && "$CC" < fi.cyr > fi 2> fi.err ) || fail "axis 5: the fault-injection probe did not compile: $(grep -m2 -i 'error' "$FI/fi.err")"
    if grep -q '^warning: undefined function' "$FI/fi.err"; then
        fail "axis 5: the fault-injection probe has undefined functions: $(grep -m2 '^warning: undefined' "$FI/fi.err")"
    fi
    chmod +x "$FI/fi" 2>/dev/null
    rc=0; out=$( ulimit -c 0; "$FI/fi" 2> "$FI/fi.stderr" ) || rc=$?
    if [ "$rc" -ne 0 ] || [ "$out" != "returned" ]; then
        why=""; [ "$rc" = 139 ] && why=" (SIGSEGV: a store through the refused allocation)"
        fail "axis 5: per-call fault injection exited $rc$why: $(head -1 "$FI/fi.stderr")"
    fi
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: alloc_failure_returns_zero (freelist.cyr includes alone on 5 targets; refused arena refills return 0 and the allocator recovers; PE alloc_init aborts loudly; fhm_new/flags_new return 0 over an exhausted heap; every allocation check in fhm_new / flags_new / _fhm_grow / _flags_list_push holds when ITS call alone is refused)"
