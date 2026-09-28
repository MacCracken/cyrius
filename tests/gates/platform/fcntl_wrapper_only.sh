#!/bin/sh
# fcntl_wrapper_only.sh — v6.6.8. fcntl is issued through `sys_fcntl` and O_NONBLOCK through
# `fd_set_nonblocking`, whose flag is PRIVATE and per-target; no in-tree code hand-rolls either.
#
# ⛔ WHY. The stdlib had no fcntl wrapper, so each O_NONBLOCK user wrote a raw
# `syscall(SYS_FCNTL, fd, 4, fl | 2048)` — about 15 sites in-tree (async.cyr, net.cyr with a
# literal 72, the Darwin accept4 composition, cbt, cyrius-init) and 21 across the ecosystem.
# 2048 is Linux's O_NONBLOCK and Darwin's O_EXCL, which F_SETFL ignores, so on macOS the fd
# stayed BLOCKING (sigil's bounded drain, daimon, cyim-lsp, cyrius-doom). And the public name is
# no cure on its own: enum constants are global and the last definition wins program-wide, so
# yukti <= 2.3.12's `enum EjectConst { O_NONBLOCK = 2048; }` turned every O_NONBLOCK in a macOS
# program into O_EXCL. CHANGELOG [6.6.8]
#
# Axes:
#   A  no `syscall(SYS_FCNTL|72|25, …)` in lib/ cbt/ programs/ tests/tcyr/ outside sys_fcntl
#      itself. The vendored sibling folds (lib/sigil.cyr, lib/vani.cyr, …) are the owning
#      repos' to migrate and are listed by name, with a reason, never by glob.
#   B  fd_set_nonblocking / fd_restore_flags never name the PUBLIC O_NONBLOCK (the poisonable
#      one) — the bit comes from `_fd_o_nonblock()`, whose arms are the literals 4 / 2048.
#   C  the three wrappers exist on the two STANDALONE peers (Windows, agnos) as -38 stubs that
#      name no O_NONBLOCK (undefined there: a hard compile error for every consumer).
#   D  RUN tests/tcyr/crossos/fd_nonblocking.tcyr on the host and (visibly skipped without
#      qemu) under qemu-aarch64. That test poisons O_NONBLOCK with the OTHER platform's value,
#      so a wrapper built on the public name fails it on Linux too.
#
# MUTATION LEDGER (each on the working tree, gate re-run, restored):
#   1. fd_set_nonblocking uses `fl | O_NONBLOCK`          -> FAIL B, and FAIL D on both legs
#      ("the kernel holds O_NONBLOCK … got 0, expected 2048")
#   2. put back net.cyr's `syscall(72, fd, 3, 0)`          -> FAIL A naming lib/net.cyr
#   3. delete `fn fd_restore_flags` from the agnos peer     -> FAIL C
#   4. the Windows sys_fcntl stub returns `O_NONBLOCK`      -> FAIL C
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=build/cycc
[ -x "$CC" ] || { echo "FAIL: fcntl_wrapper_only: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: fcntl_wrapper_only: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM
FAIL=0
bad() { echo "FAIL: fcntl_wrapper_only: $1"; FAIL=1; }
ok()  { echo "  ok: $1"; }

python3 - "$ROOT" <<'PY' || FAIL=1
import os, re, sys
ROOT = sys.argv[1]
bad = []
# Sibling folds, vendored byte-identical from their own repos: the fix belongs upstream.
FOLDS = {
    'lib/sigil.cyr': "sigil's bounded capture drain; sigil moves to sys_fcntl when it pins 6.6.8",
    'lib/vani.cyr':  "vani's _audio_open_pcm clears O_NONBLOCK; vani moves when it pins 6.6.8",
}
site = re.compile(r'\bsyscall\(\s*(SYS_FCNTL|72|25)\s*,')
n_files = 0
for top in ('lib', 'cbt', 'programs', 'tests/tcyr'):
    for dp, _, fs in os.walk(os.path.join(ROOT, top)):
        for f in fs:
            if not f.endswith(('.cyr', '.tcyr')):
                continue
            rel = os.path.relpath(os.path.join(dp, f), ROOT)
            n_files += 1
            if rel in FOLDS:
                continue
            for ln, line in enumerate(open(os.path.join(ROOT, rel), encoding='utf-8', errors='replace'), 1):
                code = line.split('#', 1)[0]
                if not site.search(code):
                    continue
                if rel == 'lib/syscalls_linux_common.cyr' and 'return syscall(SYS_FCNTL, fd, cmd, arg);' in code:
                    continue
                # ⚠ 25 is a real number on other peers' tables too; only flag it as fcntl when
                # the call has fcntl's shape (fd, cmd, arg) — three arguments after the number.
                if re.search(r'\bsyscall\(\s*25\s*,', code) and code.count(',') < 3:
                    continue
                bad.append(f"axis A: {rel}:{ln} hand-rolls fcntl: {line.strip()} — use sys_fcntl / fd_set_nonblocking")
if n_files < 500:
    bad.append(f"axis A: only {n_files} source files scanned (floor 500) — the walk is reading nothing")
elif not any(b.startswith('axis A') for b in bad):
    print(f"  ok: axis A: no hand-rolled fcntl in {n_files} files (folds exempt by name: {', '.join(sorted(FOLDS))})")

lc = open(os.path.join(ROOT, 'lib/syscalls_linux_common.cyr'), encoding='utf-8').read()
def body(src, fn):
    m = re.search(rf'^fn {fn}\([^)]*\)[^{{]*\{{(.*?)^\}}', src, re.M | re.S)
    return m.group(1) if m else None
for fn in ('sys_fcntl', 'fd_set_nonblocking', 'fd_restore_flags', '_fd_o_nonblock'):
    b = body(lc, fn)
    if b is None:
        bad.append(f"axis B: lib/syscalls_linux_common.cyr defines no {fn}")
    elif re.search(r'\bO_NONBLOCK\b', re.sub(r'#.*', '', b)):
        bad.append(f"axis B: {fn} names the PUBLIC O_NONBLOCK — any fold that redefines it "
                   f"(yukti's EjectConst did) changes the bit program-wide; use _fd_o_nonblock()")
nb = body(lc, '_fd_o_nonblock') or ''
if not (re.search(r'CYRIUS_TARGET_MACOS\s*\n\s*return 4;', nb) and re.search(r'return 2048;', nb)):
    bad.append("axis B: _fd_o_nonblock is not the literal pair (Darwin 4, Linux 2048)")
if 'fd_set_nonblocking' in lc and '_fd_o_nonblock()' not in (body(lc, 'fd_set_nonblocking') or ''):
    bad.append("axis B: fd_set_nonblocking does not take its bit from _fd_o_nonblock()")
if not any(b.startswith('axis B') for b in bad):
    print("  ok: axis B: the O_NONBLOCK bit is private and per-target (4 / 2048)")

for rel in ('lib/syscalls_windows.cyr', 'lib/syscalls_x86_64_agnos.cyr'):
    t = open(os.path.join(ROOT, rel), encoding='utf-8').read()
    for fn in ('sys_fcntl', 'fd_set_nonblocking', 'fd_restore_flags'):
        if not re.search(rf'^fn {fn}\([^)]*\)[^{{]*\{{\s*return 0 - 38;\s*\}}', t, re.M):
            bad.append(f"axis C: {rel} has no `return 0 - 38;` stub for {fn} (a standalone "
                       f"peer: without it portable source fails to COMPILE there)")
if not any(b.startswith('axis C') for b in bad):
    print("  ok: axis C: PE and agnos decline all three with -38")

for b in bad:
    print("FAIL: fcntl_wrapper_only: " + b)
sys.exit(1 if bad else 0)
PY

T=tests/tcyr/crossos/fd_nonblocking.tcyr
run_leg() {   # run_leg <name> <compiler> <runner-prefix...>
    leg=$1; cc=$2; shift 2
    ( ulimit -c 0; "$cc" < "$T" > "$D/t_$leg" ) 2>"$D/e_$leg" || true
    if [ ! -s "$D/t_$leg" ]; then bad "axis D ($leg): $T produced an EMPTY binary — $(head -c 200 "$D/e_$leg")"; return; fi
    chmod +x "$D/t_$leg"
    out=$( cd "$D" && ulimit -c 0 && "$@" "./t_$leg" 2>&1 ); rc=$?
    if [ "$rc" != 0 ]; then
        bad "axis D ($leg): $T exited $rc:
$(echo "$out" | grep -E 'FAIL|passed' | head -6)"
        return
    fi
    ok "axis D ($leg): $(echo "$out" | tail -1)"
}
run_leg host "$ROOT/$CC"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    ( ulimit -c 0; "$ROOT/$CC" < src/main_aarch64.cyr > "$D/cc_a64" ) 2>/dev/null || true
    if [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; run_leg aarch64 "$D/cc_a64" qemu-aarch64
    else bad "axis D: src/main_aarch64.cyr did not build a cross compiler"; fi
else
    echo "  SKIP: fcntl_wrapper_only axis D (aarch64) — qemu-aarch64 not installed"
fi

if [ "$FAIL" = 0 ]; then echo "PASS: fcntl_wrapper_only"; exit 0; fi
exit 1
