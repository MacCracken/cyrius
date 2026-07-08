#!/bin/sh
# Build the macOS arm64 (Apple Silicon) release tarball — the SINGLE
# SOURCE OF TRUTH for what ships to macOS users. Both the release
# pipeline (.github/workflows/release.yml build-macos-arm64) and the
# `cyrius audit` cross-OS install gate call this, so the thing we verify
# is byte-for-byte the thing we ship. It exists because the old release
# job shipped only a `smoke.macho` toy — every macOS install got NO
# compiler, undetected until a user installed on Apple Silicon and got
# nothing ("found by ports"). See CHANGELOG [6.0.38].
#
# Usage: sh scripts/build-macos-arm64-tarball.sh <out_dir>
#   Produces <out_dir>/cyrius-<VERSION>-aarch64-macos.tar.gz (+ .sha256).
# Requires: build/cycc (the x86_64 Linux seed compiler). Runs on Linux —
# all binaries are CROSS-emitted to arm64 Mach-O; they are unsigned (the
# installer ad-hoc codesigns them on the target).
set -e

OUT_DIR="${1:?usage: build-macos-arm64-tarball.sh <out_dir>}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VER=$(tr -d '[:space:]' < VERSION)
STAGE="cyrius-${VER}-aarch64-macos"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }

# Build the aarch64-emitting cross-compiler (Linux ELF; emits arm64).
cat src/main.cyr          | ./build/cycc > "$WORK/cc_l"  && chmod +x "$WORK/cc_l"
cat src/main_aarch64.cyr  | "$WORK/cc_l" > "$WORK/cc_x"  && chmod +x "$WORK/cc_x"

mkdir -p "$WORK/$STAGE/bin" "$WORK/$STAGE/lib"

# The compiler that RUNS on macOS (native Mach-O, from the macho driver —
# carries the v6.0.37 auto-call-main fix). `cycc` and `cycc_aarch64` are
# the same native arm64 binary (no separate x86 cycc on Apple Silicon).
cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 "$WORK/cc_x" > "$WORK/$STAGE/bin/cycc"
cp "$WORK/$STAGE/bin/cycc" "$WORK/$STAGE/bin/cycc_aarch64"
# Wrapper + quality tools, cross-emitted to arm64 Mach-O.
cat cbt/cyrius.cyr | CYRIUS_MACHO_ARM=1 "$WORK/cc_x" > "$WORK/$STAGE/bin/cyrius"
# cx Release C: cxvm (the portable-.cyx RUNTIME) ships so a binary-install macOS
# user can `cyrius run *.cyx` — the portable-bytecode model is build-once (on
# Linux, where cycc_cx runs) / run-anywhere (cxvm, verified on ecb). The cx
# COMPILER (cycc_cx) is NOT shipped: cross-emitted to Mach-O it FAULTS (signal
# 12) on 2 syscalls ESYSXLAT doesn't route yet — tracked as a follow-on, not
# needed for running .cyx. See issues/2026-07-07-cycc_cx-cross-native-macho-pe.md.
for tool in cyrfmt cyrlint cyrdoc cyrius-init cyrsign cxvm; do
    cat "programs/${tool}.cyr" | CYRIUS_MACHO_ARM=1 "$WORK/cc_x" > "$WORK/$STAGE/bin/${tool}"
done
# Version manager + prompt helper + repl shim. v6.2.40: `cyrius init` and
# `cyrius port` are the native cyrius-init binary (built above), so the
# cyrius-init.sh / cyrius-port.sh shims are gone — only cyrius-repl.sh
# remains as a shell shim.
cp scripts/cyriusly scripts/cyrius-prompt-info "$WORK/$STAGE/bin/"
cp scripts/shims/cyrius-repl.sh "$WORK/$STAGE/bin/"
chmod +x "$WORK/$STAGE/bin"/*

# Validate every Mach-O binary (magic cffaedfe, cputype 0x0100000C) —
# refuse to package a non-arm64 / empty artifact.
for b in cycc cycc_aarch64 cyrius cyrfmt cyrlint cyrdoc cyrius-init cyrsign cxvm; do
    f="$WORK/$STAGE/bin/$b"
    magic=$(xxd -l4 -p "$f" | tr -d ' \n')
    cput=$(xxd -s4 -l4 -p "$f" | tr -d ' \n')
    [ "$magic" = "cffaedfe" ] || { echo "ERROR: $b wrong magic ($magic)"; exit 1; }
    [ "$cput" = "0c000001" ]  || { echo "ERROR: $b not arm64 ($cput)"; exit 1; }
done

# Full stdlib + macOS-specific modules.
sh scripts/release-lib.sh "$WORK/$STAGE/lib" >/dev/null
cp lib/syscalls_macos.cyr lib/alloc_macos.cyr "$WORK/$STAGE/lib/"
cp VERSION LICENSE "$WORK/$STAGE/"
# v6.0.60: cyrius-init scaffolding templates. The cyrius-init binary resolves
# them at <install-root>/programs/cyrius-init-templates (via F_GETPATH of its
# own path); install.sh lands them in versions/<v>/programs/. Without these the
# binary fell through to the bash shim ("VERSION lookup failed").
mkdir -p "$WORK/$STAGE/programs"
cp -r programs/cyrius-init-templates "$WORK/$STAGE/programs/"
[ -f scripts/macos-arm64-README.md ] && cp scripts/macos-arm64-README.md "$WORK/$STAGE/README.md"

mkdir -p "$OUT_DIR"
( cd "$WORK" && tar czf "$STAGE.tar.gz" "$STAGE" && sha256sum "$STAGE.tar.gz" > "$STAGE.tar.gz.sha256" )
cp "$WORK/$STAGE.tar.gz" "$WORK/$STAGE.tar.gz.sha256" "$OUT_DIR/"
echo "built $OUT_DIR/$STAGE.tar.gz ($(wc -c < "$OUT_DIR/$STAGE.tar.gz") bytes)"
