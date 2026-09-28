#!/bin/sh
# 6.6.9 — the Windows CLI sizes files, verifies sidecars and finds the tools beside it.
#
# THE BUGS (both in cbt/, both invisible off Windows):
#   1. `_file_size` (cbt/deps.cyr) was a raw `syscall(4, …)` — x86-Linux stat — and syscall 4
#      has no PE reroute, so on cyrius.exe it answered -38 for EVERY path, at 38 call sites.
#      Two of them are user-visible here: `cyrius distlib`'s compile-verified sidecar sized
#      every file it splices with it, compiled an EMPTY unit, saw nothing undefined and
#      published the inferred sidecar as verified (the loop was inert on Windows); and
#      `cyrius distlib --check` byte-compares through `_distlib_files_same`, which bailed on
#      the negative size — so every bundle read as STALE, always. Now open + lseek(SEEK_END).
#   2. `_wrapper_dir` (cbt/core.cyr) scanned argv(0) for '/' only. On Windows argv(0) is
#      `C:\…\bin\cyrius.exe` (under wine `Z:\…`), or a bare name off PATH, so the wrapper never
#      saw its own bin/: `cyrius lint` said "tool not found: <CYRIUS_HOME>/bin/cyrlint" with
#      cyrlint.exe right beside it. Now GetModuleFileNameW, normalised to '/'.
#
# THE AXES.
#   axis 0  (always) no raw `syscall(4,` in cbt/ — the stat number with no PE reroute. Runs
#           where CI runs (no wine), so a revert of bug 1 is red there too.
#   axis 1  (wine) distlib's verify re-adds `math` for an undeclared F64_ONE under cyrius.exe.
#   axis 2  (wine) `distlib --check` right after `distlib` reports the bundle current.
#   axis 3  (wine) `cyrius.exe lint` with an EMPTY CYRIUS_HOME finds cyrlint.exe beside it.
# wine is not hardware: the release gate's cass leg and a real-cass run of these three
# commands are the verification (done for 6.6.9 on cass, see CHANGELOG [6.6.9]).
#
# MUTATION LEDGER (2026-09-28, 6.6.9, wine): the 6.6.8 cbt/ (a full revert) FAILS axes 0-3;
# `_file_size` alone back to syscall(4) FAILS 0 and 2 (axis 1 stays green: the verify's own
# reads moved to file_read_whole, so they no longer depend on it); `_wrapper_dir` without the
# Windows arm FAILS 3 only.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
fail=0

# ── axis 0: no raw stat syscall in the CLI ──────────────────────────────────────────────
# Comment lines are skipped (the fix's own comment names the old call).
RAW=$(grep -nE '^[^#]*syscall\(4 *,' "$ROOT"/cbt/*.cyr || true)
if [ -n "$RAW" ]; then
    echo "  FAIL axis 0: raw syscall(4, …) (stat — no PE reroute, -38 on cyrius.exe) in cbt/:"
    echo "$RAW" | sed 's/^/    /'
    fail=1
else
    echo "  ok axis 0: no raw stat syscall in cbt/"
fi

command -v wine >/dev/null 2>&1 || {
    [ "$fail" -eq 0 ] || { echo "FAIL: cli_pe_file_size_and_sibling_tools"; exit 1; }
    echo "  SKIPPED axes 1-3: wine not installed"
    echo "PASS: cli_pe_file_size_and_sibling_tools (axis 0 only)"; exit 0; }
[ -x "$CC" ] || { echo "SKIP: $CC missing"; exit 0; }

W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: cli_pe_file_size_and_sibling_tools: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
export WINEDEBUG=-all
wp() { winepath -w "$1" 2>/dev/null; }

# The cross compiler (Linux-hosted, emits PE), then the PE toolchain from THIS tree.
( cd "$ROOT" && "$CC" < src/main_win.cyr > "$W/cc_win" 2>/dev/null ) && chmod +x "$W/cc_win" \
    || { echo "FAIL: cli_pe_file_size_and_sibling_tools: could not build the PE cross compiler"; exit 1; }
mkdir -p "$W/home/bin" "$W/home/versions" "$W/sib/bin" "$W/empty"
( cd "$ROOT" && "$W/cc_win" < src/main_win.cyr > "$W/home/bin/cycc.exe" 2>/dev/null \
    && "$W/cc_win" < cbt/cyrius.cyr > "$W/home/bin/cyrius.exe" 2>/dev/null \
    && "$W/cc_win" < programs/cyrlint.cyr > "$W/sib/bin/cyrlint.exe" 2>/dev/null ) \
    || { echo "FAIL: cli_pe_file_size_and_sibling_tools: could not build the PE toolchain"; exit 1; }
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")
mkdir -p "$W/home/versions/$VER"
cp -R "$ROOT/lib" "$W/home/versions/$VER/lib"
cp "$W/home/bin/cycc.exe" "$W/home/bin/cyrius.exe" "$W/sib/bin/"

# ── axes 1-2: distlib verify + --check ──────────────────────────────────────────────────
P="$W/proj"; mkdir -p "$P/src"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "vprobe"
version = "0.1.0"
cyrius = "$VER"

[lib]
modules = ["src/lib.cyr"]

[deps]
stdlib = ["syscalls", "alloc", "string", "io", "fmt", "vec", "str"]
EOF
printf 'fn vprobe_scale(x): i64 {\n    var one = F64_ONE;\n    return f64_mul(x, one);\n}\n' > "$P/src/lib.cyr"
HW=$(wp "$W/home")
( cd "$P" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" distlib > "$W/d1.log" 2>&1 ) || true
if [ ! -f "$P/dist/vprobe.deps" ]; then
    echo "  FAIL premise: cyrius.exe distlib wrote no sidecar"; sed -n '1,5p' "$W/d1.log" | sed 's/^/    /'; fail=1
elif grep -qx 'math' "$P/dist/vprobe.deps"; then
    echo "  ok axis 1: the verify loop runs on cyrius.exe ('math' re-added for F64_ONE)"
else
    echo "  FAIL axis 1: 'math' not re-added under cyrius.exe — the verify spliced nothing (file sizes read as -38) and published the inferred sidecar: [$(grep -v '^#' "$P/dist/vprobe.deps" | tr '\n' ' ')]"; fail=1
fi
# The verify builds its unit in a mirror under dist/ and must take it away again.
if ls -a "$P/dist" | grep -q '^\.dlverify-'; then
    echo "  FAIL axis 1: the verify's scratch mirror was left behind: $(ls -a "$P/dist" | grep '^\.dlverify-')"; fail=1
fi
( cd "$P" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" distlib --check > "$W/d2.log" 2>&1 ) || true
if grep -q 'current: dist/vprobe.cyr' "$W/d2.log" && ! grep -q 'STALE' "$W/d2.log"; then
    echo "  ok axis 2: distlib --check reports a just-built bundle current"
else
    echo "  FAIL axis 2: distlib --check right after distlib did not report the bundle current:"
    sed -n '1,4p' "$W/d2.log" | sed 's/^/    /'; fail=1
fi

# ── axis 3: the tools beside cyrius.exe, with an EMPTY CYRIUS_HOME ──────────────────────
Q="$W/lproj"; mkdir -p "$Q/src"
printf '[package]\nname = "wp"\nversion = "0.1.0"\ncyrius = "%s"\n' "$VER" > "$Q/cyrius.cyml"
printf '# One.\nfn wp_one(): i64 { return 1; }\n' > "$Q/src/lib.cyr"
( cd "$Q" && CYRIUS_HOME="$(wp "$W/empty")" CYRIUS_RESOLVED=1 timeout 120 wine "$W/sib/bin/cyrius.exe" lint src/lib.cyr > "$W/l.log" 2>&1 ) || true
if grep -q 'tool not found' "$W/l.log" || ! grep -q '0 warnings' "$W/l.log"; then
    echo "  FAIL axis 3: cyrius.exe did not use the cyrlint.exe beside it:"; sed -n '1,3p' "$W/l.log" | sed 's/^/    /'; fail=1
else
    echo "  ok axis 3: cyrius.exe resolves cyrlint.exe from its own bin/"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: cli_pe_file_size_and_sibling_tools"; exit 1; }
echo "PASS: cli_pe_file_size_and_sibling_tools (no raw stat; verify, --check and sibling tools work on cyrius.exe)"
