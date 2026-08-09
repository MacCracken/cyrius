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
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
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
# ⚠ chdir is the SECOND occupant of the ≥1000 private-alias band, and it got there the same
# way fchownat did: native 49 is eaten by the x86-compat bind(49→200) shim (so a
# native-numbered call ran bind(path,…) → -EBADF) and the x86 number 80 is this peer's own
# SYS_FSTAT. The host cannot see any of this — the constant reads fine and compiles on every
# target, and only the BACKEND rewrite makes it wrong. Assert every lockstep site.
check "aarch64 peer uses the chdir alias" 1 \
    "$(grep -c '^    SYS_CHDIR = 1049;' lib/syscalls_aarch64_linux.cyr)"
check "aarch64-Linux ESYSXLAT arm 1049→49" 1 \
    "$(grep -c '0xF110651F); EW(S, 0x54000041); EW(S, 0xD2800628)' src/backend/aarch64/emit.cyr)"
check "macho ESYSXLAT arm 1049→12" 1 \
    "$(grep -c '0xF110651F); EW(S, 0x54000041); EW(S, 0xD2800190)' src/backend/aarch64/emit.cyr)"
check "_macho_arm_routes whitelists 1049" 1 \
    "$(grep -c 'if (n == 1049) { return 1; }' src/backend/aarch64/emit.cyr)"
# macOS-x86 resolves the shared linux_common peer, so it needs its own Darwin row — an
# untranslated 80 reaches Darwin unclassed and SIGSYSes, exactly as 231 did at v6.5.6.
check "EMACHO_SYSXLAT maps chdir 80→Darwin 12" 1 \
    "$(grep -c '_msx(S, 80, 0x200000C);' src/backend/x86/emit.cyr)"
ln_bind=$(grep -n '0xD2801908);  # bind        49→200' src/backend/aarch64/emit.cyr | cut -d: -f1)
ln_cd=$(grep -n '0xD2800628);  # chdir 1049→49' src/backend/aarch64/emit.cyr | cut -d: -f1)
if [ -n "$ln_bind" ] && [ -n "$ln_cd" ] && [ "$ln_cd" -gt "$ln_bind" ]; then ord2=after; else ord2=BEFORE; fi
check "chdir arm sits after bind 49→200 (else re-caught)" after "$ord2"

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
# v6.5.7: the aarch64 arm goes through the PRIVATE ALIAS 1054 (native 54 is owned by the
# setsockopt shim, load-bearing for 51 ecosystem repos; the x86 number 260 is this peer's own
# native SYS_WAIT4). An alias is only correct if THREE sites move in lockstep, and a missing
# one is a stale-x16 garbage call that no host test can see — so assert all three, plus the
# ordering rule that makes the Linux arm work at all.
check "aarch64 peer uses the alias" 1 \
    "$(grep -c '^    SYS_FCHOWNAT = 1054;' lib/syscalls_aarch64_linux.cyr)"
check "aarch64-Linux ESYSXLAT arm 1054→54" 1 \
    "$(grep -c '0xF110791F); EW(S, 0x54000041); EW(S, 0xD28006C8)' src/backend/aarch64/emit.cyr)"
check "macho ESYSXLAT arm 1054→468 (macOS-arm64 resolves this peer)" 1 \
    "$(grep -c '0xF110791F); EW(S, 0x54000041); EW(S, 0xD2803A90)' src/backend/aarch64/emit.cyr)"
check "_macho_arm_routes whitelists 1054" 1 \
    "$(grep -c 'if (n == 1054) { return 1; }' src/backend/aarch64/emit.cyr)"
# ⚠ ORDERING. The Linux arm emits x8=54 and the setsockopt entry compares against 54, so an
# arm placed ABOVE it is re-caught and every fchownat is issued as setsockopt — silently, on
# hardware this suite does not run on. Assert it comes after.
ln_sock=$(grep -n '0xD2801A08);  # setsockopt  54→208' src/backend/aarch64/emit.cyr | cut -d: -f1)
ln_own=$(grep -n '0xD28006C8);  # fchownat 1054→54' src/backend/aarch64/emit.cyr | cut -d: -f1)
if [ -n "$ln_sock" ] && [ -n "$ln_own" ] && [ "$ln_own" -gt "$ln_sock" ]; then ord=after; else ord=BEFORE; fi
check "Linux arm sits after setsockopt 54→208 (else re-caught)" after "$ord"

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

# ── AXIS 4c: the DARWIN divergences, every one of which was found by RUNNING
# vr01_syscall_wrappers.tcyr on ecb/ach and none of which the host suite can see. A
# missing Mach-O route does not fail — it SIGSYSes the process (128+12), and a Linux-valued
# AT_* flag does not fail either, it just returns EINVAL forever.
echo "axis 4c — Darwin routes + AT_* flags (found-by-ports class; host-invisible):"
check "AT_* flags are per-target (Darwin 0x20/0x40/0x80)" 1 \
    "$(awk '/ifdef CYRIUS_TARGET_MACOS/,/endif/' lib/syscalls_linux_common.cyr | grep -c 'AT_SYMLINK_NOFOLLOW = 32;')"
check "macOS-x86 stat offsets match syscall 188 (legacy struct, not stat64)" 1 \
    "$(awk '/^enum Stat/,/^}/' lib/syscalls_macos.cyr | grep -c 'STAT_MODE = 8;')"
# unlinkat must be a PURE renumber: the old arg-shift to unlink(10) dropped the dirfd and
# the flag, so every rmdir on macOS-arm64 ran unlink(AT_FDCWD) and returned -1.
check "macho unlinkat 35→472 is a pure renumber (no arg-shift to unlink)" 1 \
    "$(grep -c '0xF1008D1F); EW(S, 0x54000041); EW(S, 0xD2803B10)' src/backend/aarch64/emit.cyr)"
check "macho symlinkat 36→474" 1 \
    "$(grep -c '0xD2803B50);  # symlinkat  36→474' src/backend/aarch64/emit.cyr)"
check "macho readlinkat 78→473" 1 \
    "$(grep -c '0xD2803B30);  # readlinkat 78→473' src/backend/aarch64/emit.cyr)"
check "EMACHO_SYSXLAT maps link 86→9 (an unmapped number SIGSYSes)" 1 \
    "$(grep -c '_msx(S, 86, 0x2000009);' src/backend/x86/emit.cyr)"
# Every number the x86-macOS peer can emit for the x* family must have a Darwin row.
for n in 83 84 86 87 88 89 80 260; do
    check "EMACHO_SYSXLAT covers $n" 1 "$(grep -c "_msx(S, $n," src/backend/x86/emit.cyr)"
done

# ── AXIS 5: a number is minted WHEN ITS KERNEL ARM EXISTS — not before, not after.
# The rule cuts both ways and the gate must too: on agnos an unknown `num` falls THROUGH
# the dispatch chain and the caller reads the fall-through value as DATA, so minting early
# is worse than not minting; but leaving a shipped arm unminted strands the feature.
echo "axis 5 — agnos numbers track their kernel arms (#97 minted, #96 not):"
# #97 chan_op — kernel arm shipped in agnos 1.56.40, so the constant and its five op
# wrappers must be present.
check "SYS_CHAN_OP = 97 minted" 1 \
    "$(grep -c 'SYS_CHAN_OP          = 97;' lib/syscalls_x86_64_agnos.cyr || true)"
for op in caps mint send recv close; do
    check "sys_chan_$op wrapper present" 1 \
        "$(grep -c "^fn sys_chan_$op(" lib/syscalls_x86_64_agnos.cyr || true)"
done
# ⛔ The prefix guard. `chan_send`/`chan_recv`/`chan_close`/`chan_new` are the in-process
# MPSC thread channel in lib/thread.cyr, and cyrius resolves duplicate fns
# last-definition-wins — so a bare `chan_send` in the agnos peer would silently REPLACE
# the thread channel's, on agnos only, for any consumer including both files.
n_bare=$(grep -cE '^fn chan_(send|recv|close|new)\(' lib/syscalls_x86_64_agnos.cyr || true)
check "no bare chan_* in the agnos peer (would shadow thread.cyr)" 0 "$n_bare"
# v6.5.9: CH_ENDOW landed in the kernel AFTER 6.5.8 minted the band, so the peer had no name
# for an op the caps mask already advertised (0x1F -> 0x3F). Endowment is what makes the
# band's authority model usable at all — an inherited fd is inert by construction, so without
# it a child can hold no channel.
check "CH_ENDOW = 0x05 minted" 1 \
    "$(grep -c 'CH_ENDOW  = 0x05;' lib/syscalls_x86_64_agnos.cyr || true)"
check "sys_chan_endow wrapper present" 1 \
    "$(grep -c '^fn sys_chan_endow(' lib/syscalls_x86_64_agnos.cyr || true)"
# ⚠ ENDOW is the ONE op in the band that returns an FD rather than 0 — the kernel cannot
# announce the number itself (the child's env is baked into its init stack before placement),
# so the parent does. A doc comment claiming "-> 0" here would propagate the kernel's own
# stale enum comment (syscall.cyr:4588) over what its ARM actually does (`return tfd`, :7898).
check "sys_chan_endow documents the fd return, not 0" 1 \
    "$(grep -c 'The return is an FD, not a' lib/syscalls_x86_64_agnos.cyr || true)"
check "the enum row says fd, not 0" 1 \
    "$(grep -c 'CH_ENDOW  = 0x05;   # (fd) → the fd index the CHILD will hold' lib/syscalls_x86_64_agnos.cyr || true)"
# #43 has accepted an env blob in a3/a4 since agnos 1.44.19; the 2-arg wrapper reached two of
# four. ⛔ The kernel treats a garbage a3/a4 as fallback-to-default-env, NEVER an error, so a
# mis-shaped call degrades silently — which is the argument for a named wrapper.
check "sys_spawn_path_env (4-arg) present" 1 \
    "$(grep -c '^fn sys_spawn_path_env(path, len, env, envlen)' lib/syscalls_x86_64_agnos.cyr || true)"
check "the 2-arg sys_spawn_path is KEPT (existing callers)" 1 \
    "$(grep -c '^fn sys_spawn_path(path, len)' lib/syscalls_x86_64_agnos.cyr || true)"
# #96 fork — NO kernel arm exists in agnos (re-checked at 1.56.42: `grep -c 'num == 96'
# agnos/kernel/core/syscall.cyr` -> 0). Must stay unminted. This assertion IS the
# enforcement for the reserved-#96 record; it is machine-checked, unlike a doc note.
n_96=$(grep -cE '=[[:space:]]*96;' lib/syscalls_x86_64_agnos.cyr || true)
check "no SysNrAgnos constant on 96 (fork has no kernel arm)" 0 "$n_96"
# #98 ptrscan — agnos 1.56.42 DID mint it (kernel/core/syscall.cyr:8776), so the peer must
# carry it. The two halves of this axis are deliberate opposites: mint what the kernel has,
# refuse what it does not. A number tracking neither direction is how a consumer ends up
# hard-coding one.
n_98=$(grep -cE 'SYS_PTRSCAN[[:space:]]*=[[:space:]]*98;' lib/syscalls_x86_64_agnos.cyr || true)
check "SYS_PTRSCAN = 98 present (agnos 1.56.42 minted it)" 1 "$n_98"
n_98w=$(grep -c '^fn sys_ptrscan(buf, max)' lib/syscalls_x86_64_agnos.cyr || true)
check "sys_ptrscan(buf, max) wrapper present" 1 "$n_98w"

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
