#!/bin/sh
# 6.6.11 (I3) — cyrius.exe honours CYRIUS_RESOLVED and redirects to a pinned version.
#
# THE BUGS (both on the Windows arm of `_try_redirect_to_pinned`, cbt/cyrius.cyr):
#   1. `_cyrius_resolved` was set only by find_tools' /proc/self/environ scan, which reads
#      nothing on PE — so CYRIUS_RESOLVED=1, the documented escape from a pin, was ignored:
#      a project pinning an uninstalled version exited 1 ("not installed") even with it set.
#   2. The redirect itself could not succeed: it looked for `versions/<pin>/bin/cyrius` (no
#      .exe — install.ps1 installs cyrius.exe) and then called `sys_execve`, a -1 stub on
#      PE ("error: cyrius execve to pinned version failed"). So on Windows every repo pinning
#      another version could run NO verb. Now cyrius.exe sets CYRIUS_RESOLVED=1 on itself,
#      runs `versions/<pin>/bin/cyrius.exe` as a child through the CLI's CreateProcessW
#      path, waits, and exits with the child's code.
#
# THE AXES (wine; exit 77 when wine is absent — wine is not hardware, the cass leg of the
# release gate and a real-cass run are the verification):
#   axis 1  pin to an UNINSTALLED version + CYRIUS_RESOLVED=1: `--version` exits 0 and prints
#           the `manifest-pin: <pin> (drift` note.
#   axis 1b the same WITHOUT CYRIUS_RESOLVED: exits 1 naming `.../bin/cyrius.exe` (control).
#   axis 2  the pinned slot holds a probe cyrius.exe: the verb and a spaced argument reach it,
#           it sees CYRIUS_RESOLVED=1, and its exit code (37) is cyrius.exe's exit code.
#   axis 3  the pinned slot holds the tree's own cyrius.exe: the child honours the guard it
#           was handed and runs the verb (no redirect loop) — `--version` exits 0.
#
# MUTATION LEDGER (2026-09-29, 6.6.11, wine): deleting the find_tools CYRIUS_RESOLVED line
# FAILS 1 and 3; deleting the `.exe` suffix FAILS 1b, 2 and 3; deleting the
# `_win_redirect_to_pinned` call FAILS 2 and 3 ("execve to pinned version failed").
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=cli_pe_pinned_redirect

command -v wine >/dev/null 2>&1 && command -v winepath >/dev/null 2>&1 \
    || { echo "SKIP: $NAME — wine not installed"; exit 77; }
[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }

W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
export WINEDEBUG=-all
wp() { winepath -w "$1" 2>/dev/null; }

# The cross compiler (Linux-hosted, emits PE), then cyrius.exe from THIS tree.
( cd "$ROOT" && "$CC" < src/main_win.cyr > "$W/cc_win" 2>/dev/null ) && chmod +x "$W/cc_win" \
    || { echo "FAIL: $NAME — could not build the PE cross compiler"; exit 1; }
mkdir -p "$W/home/bin"
( cd "$ROOT" && "$W/cc_win" < cbt/cyrius.cyr > "$W/home/bin/cyrius.exe" 2>/dev/null ) \
    || { echo "FAIL: $NAME — could not build cyrius.exe"; exit 1; }

# The probe that stands in for a pinned cyrius.exe: 37 when it got CYRIUS_RESOLVED=1 and
# argv = [probe-verb, "x y"]; 40-43 name what was missing.
cat > "$W/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/args.cyr"
var _rbuf[64];
fn main(): i64 {
    alloc_init();
    args_init();
    var n = syscall(0xF015, "CYRIUS_RESOLVED", &_rbuf, 64);   # GetEnvironmentVariableA
    if (n != 1) { return 40; }
    if (load8(&_rbuf) != 49) { return 41; }
    if (argc() != 3) { return 42; }
    if (streq(argv(1), "probe-verb") == 0) { return 43; }
    if (streq(argv(2), "x y") == 0) { return 44; }
    return 37;
}
var r = main();
syscall(60, r);
EOF
( cd "$ROOT" && "$W/cc_win" < "$W/probe.cyr" > "$W/probe.exe" 2>"$W/probe.err" ) \
    || { echo "FAIL: $NAME — could not build the probe: $(head -2 "$W/probe.err")"; exit 1; }

PIN=0.0.1
P="$W/proj"; mkdir -p "$P"
printf '[package]\nname = "pinprobe"\nversion = "0.1.0"\ncyrius = "%s"\n' "$PIN" > "$P/cyrius.cyml"
HW=$(wp "$W/home")
fail=0

# ── axis 1 / 1b: the pinned version is NOT installed ─────────────────────────────────────
( cd "$P" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 120 wine "$W/home/bin/cyrius.exe" --version > "$W/a1.log" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && grep -q "manifest-pin: $PIN (drift" "$W/a1.log"; then
    echo "  ok axis 1: CYRIUS_RESOLVED=1 is honoured (exit 0, drift note)"
else
    echo "  FAIL axis 1: CYRIUS_RESOLVED=1 with an uninstalled pin: exit $rc"; sed -n '1,3p' "$W/a1.log" | sed 's/^/    /'; fail=1
fi
( cd "$P" && CYRIUS_HOME="$HW" timeout 120 wine "$W/home/bin/cyrius.exe" --version > "$W/a1b.log" 2>&1 )
rc=$?
if [ "$rc" -eq 1 ] && grep -q "versions/$PIN/bin/cyrius.exe" "$W/a1b.log"; then
    echo "  ok axis 1b: without it, an uninstalled pin is refused naming bin/cyrius.exe"
else
    echo "  FAIL axis 1b: an uninstalled pin without CYRIUS_RESOLVED: exit $rc"; sed -n '1,3p' "$W/a1b.log" | sed 's/^/    /'; fail=1
fi

# ── axis 2: the pinned slot is installed (a probe) ───────────────────────────────────────
mkdir -p "$W/home/versions/$PIN/bin"
cp "$W/probe.exe" "$W/home/versions/$PIN/bin/cyrius.exe"
( cd "$P" && CYRIUS_HOME="$HW" timeout 120 wine "$W/home/bin/cyrius.exe" probe-verb "x y" > "$W/a2.log" 2>&1 )
rc=$?
if [ "$rc" -eq 37 ]; then
    echo "  ok axis 2: redirected to versions/$PIN/bin/cyrius.exe with the args and the guard; its exit code (37) propagated"
else
    echo "  FAIL axis 2: expected the pinned probe's exit 37 (40/41 no CYRIUS_RESOLVED, 42-44 args), got $rc"
    sed -n '1,3p' "$W/a2.log" | sed 's/^/    /'; fail=1
fi

# ── axis 3: the pinned slot is a real cyrius.exe — no redirect loop ───────────────────────
cp "$W/home/bin/cyrius.exe" "$W/home/versions/$PIN/bin/cyrius.exe"
# A short deadline: without the guard each cyrius.exe spawns the next one, forever (the
# job object each runs in ends the chain when `timeout` ends the first).
( cd "$P" && CYRIUS_HOME="$HW" timeout 30 wine "$W/home/bin/cyrius.exe" --version > "$W/a3.log" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && grep -q "manifest-pin: $PIN" "$W/a3.log"; then
    echo "  ok axis 3: the redirected cyrius.exe honours the guard and runs the verb"
else
    echo "  FAIL axis 3: the pinned cyrius.exe did not run the verb (exit $rc; 124 = a redirect loop)"
    sed -n '1,3p' "$W/a3.log" | sed 's/^/    /'; fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (cyrius.exe honours CYRIUS_RESOLVED and runs a pinned cyrius.exe, exit code propagated)"
