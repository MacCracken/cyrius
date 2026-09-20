#!/bin/sh
# Build the Windows x86_64 (PE32+) release tarball — the SINGLE SOURCE OF TRUTH
# for what ships to Windows users. Both the release pipeline
# (.github/workflows/release.yml build-windows) and the `cyrius audit` cross-OS
# install gate call this, so the thing we verify is byte-for-byte the thing we
# ship. v6.0.85: includes `cyrius.exe` (the wrapper) + `install.ps1` so the
# Windows install pillar works — `cyrius build` runs on a real Windows box
# (same bar as the macOS arm64 install, v6.0.38). Mirrors
# build-macos-arm64-tarball.sh.
#
# Usage: sh scripts/build-windows-tarball.sh <out_dir>
#   Produces <out_dir>/cyrius-<VERSION>-x86_64-windows.tar.gz (+ .sha256).
# Requires: build/cycc (the x86_64 Linux seed compiler). Runs on Linux — every
# binary is CROSS-emitted to PE32+ via the cycc_win cross-compiler.
set -e

OUT_DIR="${1:?usage: build-windows-tarball.sh <out_dir>}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VER=$(tr -d '[:space:]' < VERSION)
STAGE="cyrius-${VER}-x86_64-windows"
# v6.6.6: CHECKED — an unchecked mktemp leaves the variable EMPTY on a full or unwritable
# temp dir, and every "$V/x" below then becomes "/x". CHANGELOG [6.6.6]
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }

# cycc_win: Linux-hosted cross-compiler that EMITS PE (built from src/main_win.cyr).
cat src/main.cyr     | ./build/cycc > "$WORK/cc_l"   && chmod +x "$WORK/cc_l"
cat src/main_win.cyr | "$WORK/cc_l" > "$WORK/cc_win" && chmod +x "$WORK/cc_win"

mkdir -p "$WORK/$STAGE/bin" "$WORK/$STAGE/lib"

# Windows-native cycc (PE) + the cyrius wrapper + quality tools, all PE32+.
cat src/main_win.cyr | "$WORK/cc_win" > "$WORK/$STAGE/bin/cycc.exe"
cat cbt/cyrius.cyr   | "$WORK/cc_win" > "$WORK/$STAGE/bin/cyrius.exe"
# cx: both cxvm.exe (RUNTIME) + cycc_cx.exe (COMPILER) ship — v6.4.22 fixed
# cycc_cx's PE cross-native brk-fault (Win32 has no brk → now mmap→VirtualAlloc
# per-target); verified on cass (native compile→run round-trip). A binary-install
# Windows user can `cyrius build --target=cx` AND `cyrius run *.cyx`.
# ⛔ v6.6.6 — THAT LAST SENTENCE WAS FALSE FROM THE DAY IT WAS WRITTEN, and shipping
# cycc_cx.exe is what made it look true. `_emit_cx` (cbt/build.cyr) spawned the cx
# compiler with `sys_fork`, a -1 stub on PE, so `cyrius build --target=cx` printed a bare
# `FAIL` on real cass however present cycc_cx.exe was — measured at 6.6.5. Both halves of
# the sentence hold as of 6.6.6 (the emit spawns through CreateProcessW), and the claim
# now has a gate behind it: tests/gates/platform/cbt_fork_sites_have_pe_arm.sh. A binary
# in the tarball is not a verb that works.
# v6.6.5 — cyaudit + cyrius_api_surface were MISSING, so `cyrius vet`, `cyrius deny`
# and `cyrius api-surface` had no tool to spawn on a Windows install at all. Never
# noticed because the tool spawn itself was a -1 stub (lib/syscalls_windows.cyr
# sys_fork) until 6.6.5, so each of those verbs failed for a different reason first.
# v6.6.6 — `cyrius-init` JOINS THE LIST. It had been absent because it did not
# cross-compile to PE at all: `_self_path` had only a macOS and a /proc/self/exe arm, so
# it reached an unguarded `sys_readlink`, plus `sys_rename`, neither defined in
# lib/syscalls_windows.cyr — the compile refused with 2 reachable undefined fns and would
# have packaged a 0-byte binary. Closed by the 0xF03A GetModuleFileNameW reroute + the
# three Windows wrappers; `cyrius init` and `cyrius port` now exist on a Windows install.
# See docs/development/issues/archived/2026-09-18-cyrius-init-does-not-build-for-windows.md.
for tool in cyrfmt cyrlint cyrdoc cyrius-init cyrsign cxvm cyaudit cyrius_api_surface; do
    if [ -f "programs/${tool}.cyr" ]; then
        cat "programs/${tool}.cyr" | "$WORK/cc_win" > "$WORK/$STAGE/bin/${tool}.exe"
    fi
done
# cycc_cx source is src/main_cx.cyr (a fork), not programs/ — own line.
cat src/main_cx.cyr | "$WORK/cc_win" > "$WORK/$STAGE/bin/cycc_cx.exe"

# Validate every binary is a real PE (MZ magic = 4d5a) — refuse to package an
# empty / non-PE artifact (the "found by ports" guard).
for b in cycc.exe cyrius.exe cyrfmt.exe cyrlint.exe cyrdoc.exe cyrius-init.exe cyrsign.exe \
         cxvm.exe cycc_cx.exe cyaudit.exe cyrius_api_surface.exe; do
    f="$WORK/$STAGE/bin/$b"
    [ -f "$f" ] || continue
    magic=$(xxd -l2 -p "$f" 2>/dev/null)
    [ "$magic" = "4d5a" ] || { echo "ERROR: $b not PE (magic=$magic)"; exit 1; }
done

# Full stdlib + Windows-specific modules.
sh scripts/release-lib.sh "$WORK/$STAGE/lib" >/dev/null
cp lib/syscalls_windows.cyr lib/alloc_windows.cyr "$WORK/$STAGE/lib/"

# v6.6.6: cyrius-init scaffolding templates, the half the binary is useless without.
# cyrius-init.exe resolves them at <install-root>/programs/cyrius-init-templates from
# its OWN module path (GetModuleFileNameW, reroute 0xF03A), exactly as the macOS
# builders ship them for the F_GETPATH arm. Shipping the binary without these would
# scaffold nothing but "error: missing template" lines.
mkdir -p "$WORK/$STAGE/programs"
cp -r programs/cyrius-init-templates "$WORK/$STAGE/programs/"

# The native installer + metadata.
cp scripts/install.ps1 "$WORK/$STAGE/" 2>/dev/null || true
cp VERSION LICENSE "$WORK/$STAGE/"

mkdir -p "$OUT_DIR"
( cd "$WORK" && tar czf "$STAGE.tar.gz" "$STAGE" && sha256sum "$STAGE.tar.gz" > "$STAGE.tar.gz.sha256" )
mv "$WORK/$STAGE.tar.gz" "$WORK/$STAGE.tar.gz.sha256" "$OUT_DIR/"
echo "built $OUT_DIR/$STAGE.tar.gz"
