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
#   axis 0b (always) the exe path's UTF-16 -> UTF-8 buffer is sized from its length, so a long
#           non-ASCII path is not silently truncated (a host probe of `_wrapper_w2u8`).
#   axis 1  (wine) distlib's verify re-adds `math` for an undeclared F64_ONE under cyrius.exe.
#   axis 2  (wine) `distlib --check` right after `distlib` reports the bundle current.
#   axis 3  (wine) `cyrius.exe lint` with an EMPTY CYRIUS_HOME finds cyrlint.exe beside it.
# wine is not hardware: the release gate's cass leg and a real-cass run of these three
# commands are the verification (done for 6.6.9 on cass, see CHANGELOG [6.6.9]).
#
# MUTATION LEDGER (2026-09-28, 6.6.9, wine): the 6.6.8 cbt/ (a full revert) FAILS axes 0-3;
# `_file_size` alone back to syscall(4) FAILS 0 and 2 (axis 1 stays green: the verify's own
# reads moved to file_read_whole, so they no longer depend on it); `_wrapper_dir` without the
# Windows arm FAILS 3 only. `_wrapper_w2u8` back to a fixed 4096-byte buffer FAILS 0b (rc 2).
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

# ── axis 0b: the exe path's UTF-8 buffer is sized from its length ─────────────────────────
# `_wrapper_exe_win` converted GetModuleFileNameW's answer into a FIXED 4096-byte buffer, and
# `_args_w2u8` silently drops a code point that does not fit — so a long non-ASCII install path
# came back truncated (a wrong sibling dir) and its `b - 1 >= wn` check could not tell. The
# conversion is the host-testable `_wrapper_w2u8`: 2000 CJK units must come back as 6000 bytes,
# and a surrogate pair as its 4-byte form.
[ -x "$CC" ] || { echo "SKIP: $CC missing"; exit 0; }
P0=$(mktemp -d) && [ -d "$P0" ] || { echo "FAIL: cli_pe_file_size_and_sibling_tools: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
sed -n '/^include "lib\//p; /^include "src\/version_str.cyr"/p' "$ROOT/cbt/cyrius.cyr" > "$P0/p.cyr"
cat >> "$P0/p.cyr" <<'EOF0'
include "cbt/core.cyr"
fn w2u8_probe(): i64 {
    var n = 2000;
    var w = alloc(n * 2 + 8);
    var i = 0;
    while (i < n) { store8(w + i * 2, 0x2D); store8(w + i * 2 + 1, 0x4E); i = i + 1; }  # U+4E2D
    store8(w + n * 2, 0); store8(w + n * 2 + 1, 0);
    var u = _wrapper_w2u8(w, n);
    if (u == 0) { return 1; }
    if (strlen(u) != n * 3) { return 2; }
    if (load8(u + n * 3 - 3) != 0xE4 || load8(u + n * 3 - 1) != 0xAD) { return 3; }
    # U+1F600 as a surrogate pair (2 units, 4 bytes), then 'a'
    var s = alloc(16);
    store8(s, 0x3D); store8(s + 1, 0xD8); store8(s + 2, 0x00); store8(s + 3, 0xDE);
    store8(s + 4, 0x61); store8(s + 5, 0); store8(s + 6, 0); store8(s + 7, 0);
    var v = _wrapper_w2u8(s, 3);
    if (v == 0 || strlen(v) != 5) { return 4; }
    if (load8(v) != 0xF0 || load8(v + 4) != 0x61) { return 5; }
    return 0;
}
var _w2u8_rc = w2u8_probe();
syscall(60, _w2u8_rc);
EOF0
if ( cd "$ROOT" && "$CC" < "$P0/p.cyr" > "$P0/p" 2>"$P0/p.err" ) && chmod +x "$P0/p"; then
    set +e; "$P0/p"; prc=$?; set -e
    if [ "$prc" -eq 0 ]; then
        echo "  ok axis 0b: 2000 CJK units -> 6000 UTF-8 bytes, a surrogate pair -> 4"
    else
        echo "  FAIL axis 0b: _wrapper_w2u8 probe exited $prc (1 none, 2 truncated, 3 wrong bytes, 4/5 surrogate)"
        fail=1
    fi
else
    echo "  FAIL axis 0b: the _wrapper_w2u8 probe did not compile: $(grep -i error "$P0/p.err" | head -2)"
    fail=1
fi
rm -rf "$P0"

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
