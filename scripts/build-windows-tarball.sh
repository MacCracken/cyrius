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
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }

# cycc_win: Linux-hosted cross-compiler that EMITS PE (built from src/main_win.cyr).
cat src/main.cyr     | ./build/cycc > "$WORK/cc_l"   && chmod +x "$WORK/cc_l"
cat src/main_win.cyr | "$WORK/cc_l" > "$WORK/cc_win" && chmod +x "$WORK/cc_win"

mkdir -p "$WORK/$STAGE/bin" "$WORK/$STAGE/lib"

# Windows-native cycc (PE) + the cyrius wrapper + quality tools, all PE32+.
cat src/main_win.cyr | "$WORK/cc_win" > "$WORK/$STAGE/bin/cycc.exe"
cat cbt/cyrius.cyr   | "$WORK/cc_win" > "$WORK/$STAGE/bin/cyrius.exe"
for tool in cyrfmt cyrlint cyrdoc; do
    if [ -f "programs/${tool}.cyr" ]; then
        cat "programs/${tool}.cyr" | "$WORK/cc_win" > "$WORK/$STAGE/bin/${tool}.exe"
    fi
done

# Validate every binary is a real PE (MZ magic = 4d5a) — refuse to package an
# empty / non-PE artifact (the "found by ports" guard).
for b in cycc.exe cyrius.exe cyrfmt.exe cyrlint.exe cyrdoc.exe; do
    f="$WORK/$STAGE/bin/$b"
    [ -f "$f" ] || continue
    magic=$(xxd -l2 -p "$f" 2>/dev/null)
    [ "$magic" = "4d5a" ] || { echo "ERROR: $b not PE (magic=$magic)"; exit 1; }
done

# Full stdlib + Windows-specific modules.
sh scripts/release-lib.sh "$WORK/$STAGE/lib" >/dev/null
cp lib/syscalls_windows.cyr lib/alloc_windows.cyr "$WORK/$STAGE/lib/"

# The native installer + metadata.
cp scripts/install.ps1 "$WORK/$STAGE/" 2>/dev/null || true
cp VERSION LICENSE "$WORK/$STAGE/"

mkdir -p "$OUT_DIR"
( cd "$WORK" && tar czf "$STAGE.tar.gz" "$STAGE" && sha256sum "$STAGE.tar.gz" > "$STAGE.tar.gz.sha256" )
mv "$WORK/$STAGE.tar.gz" "$WORK/$STAGE.tar.gz.sha256" "$OUT_DIR/"
echo "built $OUT_DIR/$STAGE.tar.gz"
