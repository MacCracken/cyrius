#!/bin/sh
# Gate: the v6.5.7 syscall-wrapper pass — sys_chdir, signal_default, the io.cyr x*
# family, and sys_fchownat — behave on the host AND compile on every target.
#
# WHY A CROSS-TARGET COMPILE AXIS IS THE POINT. Every wrapper here exists because the
# per-target peers DIVERGE, and the divergence is invisible on the host:
#   - agnos wrappers are LENGTH-CARRYING (`sys_mkdir(path, pathlen)`, no mode; symlink /
#     readlink / link are 4/4/4 args where POSIX is 2/3/2), so a consumer reaching for
#     `sys_*` directly is correct on Linux and silently wrong on agnos — the surplus
#     argument binds to garbage. That is the whole reason the x* forms exist.
#   - Windows and agnos peers are STANDALONE: they do NOT include
#     syscalls_linux_common.cyr, so a wrapper added only there is missing on two targets,
#     and so are the AT_* constants its arguments need.
#   - macOS-arm64 resolves the AARCH64 peer, not a macOS one.
# A host-only test passes while any of those is broken. `cyrius build` on each target is
# the cheapest thing that does not.
#
# ⛔ AXIS 5 IS A DO-NOT-DO ASSERTION. agnos reserved #96 (fork) and #97 (chan_op) on
# 2026-08-05 but the kernel arms do not exist yet. On agnos an unknown `num` falls THROUGH
# the dispatch chain and the caller reads the fall-through value as data, so a
# minted-but-unimplemented constant is strictly WORSE than an absent one — and a host build
# of the same consumer looks healthy either way, so nothing off-target catches it. This axis
# fails if someone mints them early.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"; rm -rf /tmp/cyx_gate_probe; rm -f /tmp/cyx_gate_file' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"'

mkprobe() { printf '%s\n%s\n' "$PRE" "$1" > "$D/p.cyr"; }
runhost() {
    "$CC" < "$D/p.cyr" > "$D/p.bin" 2>/dev/null
    chmod +x "$D/p.bin" 2>/dev/null
    timeout 30 "$D/p.bin" >/dev/null 2>&1
    echo $?
}

# ── AXIS 1: sys_chdir. It was CALLED at lib/regression.cyr:658 and DEFINED NOWHERE, so
# that cyrius-deps-shipped stdlib file could not compile for any consumer reaching
# regression_exec_in_dir3.
echo "axis 1 — sys_chdir works, and lib/regression.cyr resolves it:"
mkprobe 'fn main(): i64 {
    alloc_init();
    if (sys_chdir("/tmp") != 0) { return 3; }
    return 42;
}
var r = main();
sys_exit_group(r);'
check "sys_chdir(/tmp)" 42 "$(runhost)"
n_def=$(grep -lE '^fn sys_chdir' lib/syscalls_linux_common.cyr lib/syscalls_windows.cyr \
    lib/syscalls_x86_64_agnos.cyr 2>/dev/null | wc -l | tr -d ' ')
check "defined on all 3 peer families" 3 "$n_def"

# ── AXIS 2: signal_default — the counterpart signal_ignore never had. SIG_IGN is
# INHERITED across execve (a handler is not), so without this a process that ignores a
# signal hands the ignore to every child it execs, permanently.
echo "axis 2 — signal_default round-trips against signal_ignore:"
mkprobe 'fn main(): i64 {
    alloc_init();
    if (signal_ignore(SIGPIPE) != 0) { return 3; }
    if (signal_default(SIGPIPE) != 0) { return 4; }
    return 42;
}
var r = main();
sys_exit_group(r);'
check "ignore then default" 42 "$(runhost)"

# ── AXIS 3: the x* family. xmkdir_p must build a nested tree AND be idempotent (an
# existing directory is success, which is what makes it callable unconditionally).
echo "axis 3 — x* family: nested mkdir_p, idempotence, symlink round-trip:"
mkprobe 'fn main(): i64 {
    alloc_init();
    if (xmkdir_p("/tmp/cyx_gate_probe/a/b/c", 493) != 0) { return 3; }
    if (_xdir_exists("/tmp/cyx_gate_probe/a/b/c") != 1) { return 4; }
    if (xmkdir_p("/tmp/cyx_gate_probe/a/b/c", 493) != 0) { return 5; }
    if (xsymlink("/tmp/cyx_gate_probe/a", "/tmp/cyx_gate_probe/lnk") != 0) { return 6; }
    var rb[256];
    if (xreadlink("/tmp/cyx_gate_probe/lnk", &rb, 256) <= 0) { return 7; }
    xunlink("/tmp/cyx_gate_probe/lnk");
    return 42;
}
var r = main();
sys_exit_group(r);'
check "xmkdir_p + xsymlink + xreadlink" 42 "$(runhost)"

# ── AXIS 4: sys_fchownat with AT_FDCWD + AT_SYMLINK_NOFOLLOW == lchown semantics, which is
# why it is the ONE wrapped primitive of the chown family. uid/gid of -1 means "leave
# unchanged", so this is a no-op on a file we own.
echo "axis 4 — sys_fchownat gives lchown semantics via AT_FDCWD:"
: > /tmp/cyx_gate_file
mkprobe 'fn main(): i64 {
    alloc_init();
    var rc = sys_fchownat(AT_FDCWD, "/tmp/cyx_gate_file", 0 - 1, 0 - 1, AT_SYMLINK_NOFOLLOW);
    if (rc != 0) { return 3; }
    return 42;
}
var r = main();
sys_exit_group(r);'
check "fchownat(AT_FDCWD, …, -1, -1, NOFOLLOW)" 42 "$(runhost)"
# The aarch64 arm is a DELIBERATE -ENOSYS stub, not an oversight: native 54 is owned by the
# setsockopt shim (load-bearing for 51 ecosystem repos incl. consumer-authored source), and
# the x86 number 260 collides with aarch64 SYS_WAIT4. See roadmap.md W1 item 1.
n_stub=$(grep -c 'fn sys_fchownat(dirfd, path, uid, gid, flags): i64 { return 0 - 38; }' \
    lib/syscalls_aarch64_linux.cyr)
check "aarch64 stubs to -ENOSYS (documented block, not an oversight)" 1 "$n_stub"

# ── AXIS 4b: STRUCTURAL, and it exists because axis 6 provably CANNOT catch this.
# The agnos divergence is SEMANTIC, not arity: `sys_mkdir(path, mode)` and agnos's
# `sys_mkdir(path, pathlen)` are both 2-arg, so passing a mode where a length is expected
# compiles clean on agnos and is simply wrong at runtime — mutation-verified, the
# cross-compile axis stayed green against exactly that edit. Nothing short of running on
# agnos catches it behaviourally, so assert the SHAPE: every agnos arm of a
# length-carrying wrapper must compute a strlen (`while (load8(... ) != 0)`) before the
# call. Same class as the trap xrmdir was added for at v6.5.2.
echo "axis 4b — each x* agnos arm computes a length (arity matches, so nothing else can see this):"
for fn in xmkdir xsymlink xreadlink xlink; do
    body=$(awk "/^fn $fn\(/,/^}/" lib/io.cyr)
    agnos=$(printf '%s\n' "$body" | awk '/#ifdef CYRIUS_TARGET_AGNOS/,/#endif/')
    n_len=$(printf '%s\n' "$agnos" | grep -c 'while (load8(' || true)
    want=1
    if [ "$fn" = "xsymlink" ] || [ "$fn" = "xlink" ]; then want=2; fi
    check "$fn agnos arm computes $want length(s)" "$want" "$n_len"
done

# ── AXIS 5: agnos #96/#97 must NOT be minted before their kernel arms exist.
echo "axis 5 — agnos 96/97 reserved but NOT minted (a bad constant is worse than none):"
n_96=$(grep -cE '=[[:space:]]*9[67];' lib/syscalls_x86_64_agnos.cyr || true)
check "no SysNrAgnos constant on 96/97" 0 "$n_96"

# ── AXIS 6: cross-target. This is the axis a host-only test cannot replace.
echo "axis 6 — every wrapper compiles on every target the peers claim:"
cat > "$D/x.cyr" <<'EOF'
fn main(): i64 {
    alloc_init();
    sys_chdir("/tmp");
    signal_default(SIGPIPE);
    xmkdir("/tmp/cyx_gate_probe2", 493);
    xmkdir_p("/tmp/cyx_gate_probe2/x", 493);
    xsymlink("/a", "/b");
    var rb[64];
    xreadlink("/a", &rb, 64);
    xlink("/a", "/b");
    sys_fchownat(AT_FDCWD, "/a", 0 - 1, 0 - 1, AT_SYMLINK_NOFOLLOW);
    return 0;
}
var r = main();
sys_exit_group(r);
EOF
printf '%s\n' "$PRE" > "$D/xt.cyr"; cat "$D/x.cyr" >> "$D/xt.cyr"
tgt() {
    rc=0
    # shellcheck disable=SC2086
    env $2 "$1" < "$D/xt.cyr" > "$D/o.bin" 2>/dev/null || rc=$?
    if [ "$rc" = "0" ] && [ -s "$D/o.bin" ]; then echo yes; else echo no; fi
}
check "x86-64 Linux"   yes "$(tgt "$CC" CYRIUS_X=0)"
check "macOS x86 (Mach-O)" yes "$(tgt "$CC" CYRIUS_MACHO=1)"
check "agnos"          yes "$(tgt "$CC" CYRIUS_TARGET_AGNOS=1)"
[ -x build/cycc_aarch64 ] && check "aarch64" yes "$(tgt build/cycc_aarch64 CYRIUS_X=0)"
[ -x build/cycc_win ]     && check "Windows PE" yes "$(tgt build/cycc_win CYRIUS_X=0)"
# cx is EXCLUDED on purpose: src/main_cx.cyr predefines no target macro, so lib/syscalls.cyr
# includes no peer at all and lib/io.cyr has never compiled there. Pre-existing, not this
# pass's regression — verified against the committed io.cyr, which fails identically.

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: syscall-wrapper-pass — chdir/signal_default/x*/fchownat behave and cross-compile"
    exit 0
fi
echo "FAIL: syscall-wrapper-pass — $fails assertion(s) failed"
exit 1
