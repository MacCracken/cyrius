#!/bin/sh
# Build the macOS x86_64 (Intel) release tarball — the SINGLE SOURCE OF TRUTH
# for what ships to Intel-Mac users. Both the release pipeline
# (.github/workflows/release.yml build-macos-x86) and the `cyrius audit`
# cross-OS install gate should call this, so the thing we verify is
# byte-for-byte the thing we ship. Mirror of build-macos-arm64-tarball.sh.
#
# It exists because release.yml's build-macos job shipped only the quality
# tools (cyrfmt/cyrlint/cyrdoc) — NO cycc — so an Intel-Mac user running
# install.sh got no compiler, exactly the "found by ports" hole the arm64
# script was created to close at .38. The x86 Mach-O cycc itself has worked
# (self-hosts byte-identical on `ach`) since the .43-.45 carry-negate +
# main_x86_macho.cyr driver work; this just packages it. See CHANGELOG [6.0.58].
#
# Usage: sh scripts/build-macos-x86-tarball.sh <out_dir>
#   Produces <out_dir>/cyrius-<VERSION>-x86_64-macos.tar.gz (+ .sha256).
# Requires: build/cycc (the x86_64 Linux seed). Runs on Linux — all binaries
# are CROSS-emitted to x86_64 Mach-O via CYRIUS_MACHO=1 (build/cycc emits the
# x86 Mach-O container directly; no aarch64 cross step). Unsigned — the
# installer ad-hoc codesigns them on the target.
set -e

OUT_DIR="${1:?usage: build-macos-x86-tarball.sh <out_dir>}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VER=$(tr -d '[:space:]' < VERSION)
STAGE="cyrius-${VER}-x86_64-macos"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }

mkdir -p "$WORK/$STAGE/bin" "$WORK/$STAGE/lib"

# The compiler that RUNS on Intel macOS (native x86_64 Mach-O, from the
# dedicated x86 macho driver — carries the .44 DCE-stub fix + .43 carry-negate
# keystone). build/cycc + CYRIUS_MACHO=1 emits the x86 Mach-O directly.
cat src/main_x86_macho.cyr | CYRIUS_MACHO=1 ./build/cycc > "$WORK/$STAGE/bin/cycc"
# Wrapper + quality tools, cross-emitted to x86_64 Mach-O.
cat cbt/cyrius.cyr | CYRIUS_MACHO=1 ./build/cycc > "$WORK/$STAGE/bin/cyrius"
for tool in cyrfmt cyrlint cyrdoc cyrius-init; do
    cat "programs/${tool}.cyr" | CYRIUS_MACHO=1 ./build/cycc > "$WORK/$STAGE/bin/${tool}"
done
# Version manager + prompt helper + scaffolding shims. The cyrius wrapper looks
# for cyrius-init (binary, preferred) and the cyrius-{init,port,repl}.sh shims in
# <home>/bin. v6.0.58: they were missing from the macOS tarball, so `cyrius
# init`/`port`/`repl` failed "script not found" even though install was fine.
cp scripts/cyriusly scripts/cyrius-prompt-info "$WORK/$STAGE/bin/"
cp scripts/shims/cyrius-init.sh scripts/shims/cyrius-port.sh scripts/shims/cyrius-repl.sh "$WORK/$STAGE/bin/"
chmod +x "$WORK/$STAGE/bin"/*

# Validate every Mach-O binary (magic cffaedfe = MH_MAGIC_64, cputype
# 07000001 = CPU_TYPE_X86_64) — refuse to package a non-x86 / empty artifact.
for b in cycc cyrius cyrfmt cyrlint cyrdoc cyrius-init; do
    f="$WORK/$STAGE/bin/$b"
    magic=$(xxd -l4 -p "$f" | tr -d ' \n')
    cput=$(xxd -s4 -l4 -p "$f" | tr -d ' \n')
    [ "$magic" = "cffaedfe" ] || { echo "ERROR: $b wrong magic ($magic)"; exit 1; }
    [ "$cput" = "07000001" ]  || { echo "ERROR: $b not x86_64 ($cput)"; exit 1; }
done

# Full stdlib + macOS-specific modules.
sh scripts/release-lib.sh "$WORK/$STAGE/lib" >/dev/null
cp lib/syscalls_macos.cyr lib/alloc_macos.cyr "$WORK/$STAGE/lib/"
cp VERSION LICENSE "$WORK/$STAGE/"
[ -f scripts/macos-x86-README.md ] && cp scripts/macos-x86-README.md "$WORK/$STAGE/README.md"

mkdir -p "$OUT_DIR"
( cd "$WORK" && tar czf "$STAGE.tar.gz" "$STAGE" && sha256sum "$STAGE.tar.gz" > "$STAGE.tar.gz.sha256" )
cp "$WORK/$STAGE.tar.gz" "$WORK/$STAGE.tar.gz.sha256" "$OUT_DIR/"
echo "built $OUT_DIR/$STAGE.tar.gz ($(wc -c < "$OUT_DIR/$STAGE.tar.gz") bytes)"
