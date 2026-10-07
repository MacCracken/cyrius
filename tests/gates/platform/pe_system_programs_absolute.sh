#!/bin/sh
# 6.6.20 (CVE-102) — on Windows a SYSTEM program is started by its absolute System32 path, never
# by a bare name.
#
# THE BUG. Every Windows spawn of a system program named it bare: `cmd /s /c …` for every compile
# (`cyrius build`, `run`, `test`, `capacity`, the cx legs, `exec_cmd`) and `certutil -hashfile`
# for `cyrius deps --lock` / `--verify`. CreateProcessW resolves a bare first token by SEARCHING,
# and Microsoft's documented order visits the caller's own directory and then the PARENT'S CURRENT
# DIRECTORY before System32. The CLI runs inside the project, so a `cmd.exe` committed to a
# checkout ran on its first `cyrius build`, and a committed `certutil.exe` chose the hashes
# `--lock` wrote. Measured on cass (Windows 11, 6.6.20): `compile src\main.cyr -> build\main.exe
# [x86_64] PLANTED-CMD-RAN`, and a lock line `deadbeef…  lib/x.cyr` for a file whose SHA-256 is
# df76cfac…. And cmd's OWN search for a bare program inside a command (`git tag …` from
# `cyrius publish`, run through `exec_cmd`) visits the current directory too.
# THE FIX. lib/process_win.cyr `_win_sys_exe(name)` = `"<GetSystemDirectoryW>\<name>"`, quoted,
# as the command line's first token (a token with a directory in it is never searched for); it
# refuses BY NAME when the system directory cannot be read — never a bare-name fallback. And
# `exec_cmd` runs its command with NoDefaultCurrentDirectoryInExePath set (cmd honours it on
# Windows; measured on cass), so its inner search skips the current directory as /bin/sh does.
#
# ⚠ WINE CANNOT SHOW THE CWD VECTOR: its CreateProcess does not search the current directory, and
# its cmd ignores NoDefaultCurrentDirectoryInExePath (both measured, wine 11.19). It DOES search
# the caller's own directory first — the same bare-name search, one entry earlier — so the wine
# axes plant beside the caller. The current-directory vector itself is graded on real Windows by
# tests/tcyr/crossos/system_programs_not_from_cwd.tcyr (the release gate's cass leg).
#
# THE AXES.
#   axis 0  (always) no lib/ or cbt/ string literal starts a command line with a bare System32
#           program name (cmd, certutil, powershell, …) — only `_win_sys_exe("<name>.exe")`.
#   axis 1  (wine) `cyrius.exe build` with a planted cmd.exe beside cyrius.exe: builds, the
#           binary runs (exit 7), the plant never ran.
#   axis 2  (wine) `cyrius.exe test` (the `_win_cmdline_cap` run) and `cyrius.exe capacity`
#           (`_win_capacity_spawn`) with the same plant: the plant never ran.
#   axis 3  (wine) `cyrius.exe deps --lock` with a planted certutil.exe beside cyrius.exe that
#           prints a forged digest: the forged digest is never written. (Wine has no certutil.exe,
#           so the fixed CLI refuses the hash instead; real Windows hashes — measured on cass.)
#   axis 4  (wine) the stdlib's own spawns, from a probe with a cmd.exe planted beside it:
#           `exec_cmd("exit /b 3")` is 3, its command sees NoDefaultCurrentDirectoryInExePath,
#           and `_win_compile_spawn` returns the compiler's own exit code (9).
#
# MUTATION LEDGER (2026-10-07, 6.6.20; wine 11.19 for the gate, real cass for the .tcyr):
#   M1 lib exec_cmd back to a bare "cmd"                   → axis 0 + axis 4 (rc 42 42 9, exit 3); cass .tcyr 3 FAIL
#   M2 exec_cmd without the NoDefaultCurrentDirectoryInExePath prefix → axis 4 (exit 2: rc2 6); cass .tcyr 2 FAIL
#   M3 lib _win_compile_spawn back to a bare "cmd"         → axis 0 + axis 4 (rc 3 5 42, exit 4)
#   M4 cbt _win_compile_spawn_err back to a bare "cmd"     → axis 0 + axis 1 (compiler exit 42) + axis 2
#   M5 cbt _win_cmdline_cap back to a bare "cmd"           → axis 0 + axis 2 (test exit 42)
#   M6 cbt _win_capacity_spawn back to a bare "cmd"        → axis 0 + axis 2 (capacity rc 1, PLANTED)
#   M7 cbt deps certutil back to a bare "certutil"         → axis 0 + axis 3 (the forged digest written)
# The first M2 run PASSED: the shell it ran from exported NoDefaultCurrentDirectoryInExePath=1, so
# the gate now unsets it and the .tcyr clears it from its own environment before its rows.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
fail=0
NAME=pe_system_programs_absolute

# ── axis 0: no bare System32 program at the head of a command line ────────────────────────
# Comment lines are skipped (the fix's own comments name the old command lines).
BARE=$(grep -nE '^[^#]*"(cmd|certutil|powershell|pwsh|cscript|wscript|reg|icacls|findstr|tasklist|taskkill|robocopy|xcopy|attrib|whoami|where)([ ."/]|")' \
        "$ROOT"/lib/*.cyr "$ROOT"/cbt/*.cyr | grep -vE '_win_sys_exe\("[a-z]+\.exe"\)' || true)
if [ -n "$BARE" ]; then
    echo "  FAIL axis 0: a System32 program started by a BARE name (CreateProcessW searches the current directory first):"
    echo "$BARE" | sed 's/^/    /'
    fail=1
else
    echo "  ok axis 0: lib/ and cbt/ name System32 programs only through _win_sys_exe"
fi

command -v wine >/dev/null 2>&1 || {
    [ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
    echo "SKIP: $NAME — axes 1-4 need wine (axis 0 passed; exit 77: a SKIP, not a PASS)"; exit 77; }
[ -x "$CC" ] || { echo "SKIP: $CC missing"; exit 77; }

W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix under $W (never ~/.wine — its one wineserver is shared by every
# concurrent check.sh); the EXIT kill is scoped to it and removes its server socket dir.
# Same shape as tests/gates/toolchain/cli_pe_file_size_and_sibling_tools.sh. CHANGELOG [6.6.17]
WP="$W/wine"
WHM="$W/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT
# The switch exec_cmd sets must not arrive from OUTSIDE, or axis 4's row reads green with the fix
# reverted (measured: the shell this gate was first run from exported NoDefaultCurrentDirectoryInExePath=1,
# and wine hands the Unix environment to every Windows process).
unset NoDefaultCurrentDirectoryInExePath 2>/dev/null || true
export WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
wp() { winepath -w "$1" 2>/dev/null; }

# The cross compiler (Linux-hosted, emits PE), then the PE toolchain from THIS tree.
( cd "$ROOT" && "$CC" < src/main_win.cyr > "$W/cc_win" 2>/dev/null ) && chmod +x "$W/cc_win" \
    || { echo "FAIL: $NAME: could not build the PE cross compiler"; exit 1; }
mkdir -p "$W/home/bin" "$W/probe"
( cd "$ROOT" && "$W/cc_win" < src/main_win.cyr > "$W/home/bin/cycc.exe" 2>/dev/null \
    && "$W/cc_win" < cbt/cyrius.cyr > "$W/home/bin/cyrius.exe" 2>/dev/null ) \
    || { echo "FAIL: $NAME: could not build the PE toolchain"; exit 1; }
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")
mkdir -p "$W/home/versions/$VER"

# The plants: a cmd.exe that says it ran and exits 42, and a certutil.exe that prints a forged
# digest in certutil's own three-line shape.
printf 'syscall(1, 1, "PLANTED-CMD-RAN\\n", 16);\nsyscall(60, 42);\n' > "$W/plant.cyr"
cat > "$W/plant_cu.cyr" <<'EOF'
var m = "SHA256 hash of planted:\ndeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\nCertUtil: PLANTED-CERTUTIL-RAN\n";
fn plen(): i64 { var n = 0; while (load8(m + n) != 0) { n = n + 1; } return n; }
syscall(1, 1, m, plen());
syscall(60, 0);
EOF
printf 'syscall(60, 9);\n' > "$W/exit9.cyr"
( cd "$ROOT" && "$W/cc_win" < "$W/plant.cyr" > "$W/plant.exe" 2>/dev/null \
    && "$W/cc_win" < "$W/plant_cu.cyr" > "$W/plant_cu.exe" 2>/dev/null \
    && "$W/cc_win" < "$W/exit9.cyr" > "$W/probe/exit9.exe" 2>/dev/null ) \
    || { echo "FAIL: $NAME: could not build the plants"; exit 1; }
cp "$W/plant.exe" "$W/home/bin/cmd.exe"
HW=$(wp "$W/home")

# ── axis 1: cyrius build ──────────────────────────────────────────────────────────────────
P="$W/proj"; mkdir -p "$P/src" "$P/build"
printf '[package]\nname = "sp"\nversion = "0.1.0"\ncyrius = "%s"\n' "$VER" > "$P/cyrius.cyml"
printf 'syscall(60, 7);\n' > "$P/src/main.cyr"
B1=0; ( cd "$P" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" build src/main.cyr build/main.exe > "$W/b1.log" 2>&1 ) || B1=$?
M1=0; if [ -f "$P/build/main.exe" ]; then ( cd "$P" && timeout 60 wine build/main.exe >/dev/null 2>&1 ) || M1=$?; fi
if [ "$B1" = 0 ] && [ "$M1" = 7 ] && ! grep -q PLANTED "$W/b1.log"; then
    echo "  ok axis 1: cyrius.exe build ran the System32 cmd.exe, not the one planted beside it (binary exit $M1)"
else
    echo "  FAIL axis 1: cyrius.exe build (rc $B1, binary exit $M1) — the planted cmd.exe ran or the build broke:"
    sed -n '1,4p' "$W/b1.log" | sed 's/^/    /'; fail=1
fi

# ── axis 2: cyrius test (the captured run) and cyrius capacity ───────────────────────────
printf 'syscall(60, 0);\n' > "$P/t.tcyr"
T2=0; ( cd "$P" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" test t.tcyr > "$W/t2.log" 2>&1 ) || T2=$?
C2=0; ( cd "$P" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" capacity src/main.cyr > "$W/c2.log" 2>&1 ) || C2=$?
if [ "$T2" = 0 ] && ! grep -q PLANTED "$W/t2.log" && ! grep -q PLANTED "$W/c2.log" && ! grep -q 'compiler exit 42\|failed to spawn' "$W/c2.log"; then
    echo "  ok axis 2: cyrius.exe test and capacity ran the System32 cmd.exe (test rc $T2, capacity rc $C2)"
else
    echo "  FAIL axis 2: cyrius.exe test (rc $T2) / capacity (rc $C2) — the planted cmd.exe ran or the run broke:"
    sed -n '1,3p' "$W/t2.log" "$W/c2.log" | sed 's/^/    /'; fail=1
fi

# ── axis 3: cyrius deps --lock with a planted certutil.exe ────────────────────────────────
cp "$W/plant_cu.exe" "$W/home/bin/certutil.exe"
L="$W/lproj"; mkdir -p "$L/lib"
printf '[package]\nname = "lp"\nversion = "0.1.0"\ncyrius = "%s"\n' "$VER" > "$L/cyrius.cyml"
printf 'fn lp_one(): i64 { return 1; }\n' > "$L/lib/x.cyr"
L3=0; ( cd "$L" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" deps --lock > "$W/l3.log" 2>&1 ) || L3=$?
rm -f "$W/home/bin/certutil.exe"
if grep -q deadbeef "$L/cyrius.lock" 2>/dev/null; then
    echo "  FAIL axis 3: cyrius.exe deps --lock wrote the planted certutil.exe's forged digest:"
    sed 's/^/    /' "$L/cyrius.lock"; fail=1
else
    echo "  ok axis 3: the planted certutil.exe's digest was never written (rc $L3; wine has no System32 certutil)"
fi

# ── axis 4: the stdlib's spawns (exec_cmd, _win_compile_spawn) ────────────────────────────
cat > "$W/probe.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/syscalls.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/args.cyr"
include "lib/tagged.cyr"
include "lib/process.cyr"
args_init();
var rc1 = exec_cmd("exit /b 3");
var rc2 = exec_cmd("if defined NoDefaultCurrentDirectoryInExePath (exit /b 5) else (exit /b 6)");
var rc3 = _win_compile_spawn(argv(1), argv(2), argv(3));
fmt_int_fd(1, rc1); sys_write(1, " ", 1); fmt_int_fd(1, rc2); sys_write(1, " ", 1); fmt_int_fd(1, rc3); sys_write(1, "\n", 1);
var code = 0;
if (rc1 != 3) { code = code + 1; }
if (rc2 != 5) { code = code + 2; }
if (rc3 != 9) { code = code + 4; }
syscall(60, code);
EOF
( cd "$ROOT" && "$W/cc_win" < "$W/probe.cyr" > "$W/probe/probe.exe" 2>/dev/null ) \
    || { echo "FAIL: $NAME: could not build the stdlib probe"; exit 1; }
cp "$W/plant.exe" "$W/probe/cmd.exe"
printf 'x\n' > "$W/probe/in.txt"
P4=0; ( cd "$W/probe" && timeout 120 wine probe.exe "$(wp "$W/probe/exit9.exe")" in.txt out.txt > "$W/p4.log" 2>&1 ) || P4=$?
if [ "$P4" = 0 ] && ! grep -q PLANTED "$W/p4.log"; then
    echo "  ok axis 4: exec_cmd and _win_compile_spawn ran the System32 cmd.exe (rc $(tr -d '\r\n' < "$W/p4.log"))"
else
    echo "  FAIL axis 4: the stdlib probe exited $P4 (1 exec_cmd, 2 no NoDefaultCurrentDirectoryInExePath, 4 _win_compile_spawn; rc1 rc2 rc3 = $(tr -d '\r' < "$W/p4.log" | tail -1))"
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (System32 programs by absolute path: build, test, capacity, deps --lock, exec_cmd, _win_compile_spawn)"
