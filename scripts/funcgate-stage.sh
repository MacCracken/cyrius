#!/bin/sh
# funcgate-stage.sh — stage a throwaway CYRIUS_HOME for the functional gate.
#
# Lays out the exact install structure `cyrius lib sync` / the wrapper expect
# (versions/<v>/{bin,lib} + current + bin/lib symlinks), copied straight from a
# repo checkout's freshly-built binaries + lib/. Portable (cp/ln/tr only) so it
# runs identically on x86 Linux, aarch64 Linux, and the AGNOS container — no
# tool-rebuild, no sha256sum dependency. For the macOS funcgate the real release
# tarball + install.sh is used instead (that path tests the shipped artifact).
#
# Usage: funcgate-stage.sh <cycc-bin> <cyrius-bin> <CYRIUS_HOME>
# Run from a cyrius repo root (reads VERSION + lib/).
set -e

CYCC="${1:?usage: funcgate-stage.sh <cycc-bin> <cyrius-bin> <CYRIUS_HOME>}"
CYRIUS="${2:?cyrius wrapper bin}"
H="${3:?CYRIUS_HOME}"
V="$(tr -d '[:space:]' < VERSION)"

rm -rf "$H"
mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib"
cp "$CYCC"   "$H/versions/$V/bin/cycc"
cp "$CYRIUS" "$H/versions/$V/bin/cyrius"
[ -f scripts/cyriusly ] && cp scripts/cyriusly "$H/versions/$V/bin/" || true

# Helper scripts the wrapper shells out to (cyrius-init.sh for `init`, etc.).
# Same lookup as install.sh: scripts/shims/ first, then flat scripts/.
for s in cyrius-init.sh cyrius-port.sh cyrius-repl.sh cyrius-watch.sh cyrius-prompt-info; do
    if   [ -f "scripts/shims/$s" ]; then cp "scripts/shims/$s" "$H/versions/$V/bin/"
    elif [ -f "scripts/$s" ];       then cp "scripts/$s"       "$H/versions/$V/bin/"
    fi
done
chmod +x "$H/versions/$V/bin"/*

# lib snapshot — cp -L dereferences any `cyrius deps` symlinks so the home is
# self-contained (mirrors install.sh's cp -L). lib/ is flat .cyr files.
cp -RL lib/. "$H/versions/$V/lib/"

# init scaffolding templates — `cyrius init` reads these from
# versions/<v>/programs/cyrius-init-templates (install.sh:296). Without them
# init fails, so the gate's very first step would falsely red on staging, not
# the toolchain.
if [ -d programs/cyrius-init-templates ]; then
    mkdir -p "$H/versions/$V/programs"
    cp -r programs/cyrius-init-templates "$H/versions/$V/programs/"
fi

echo "$V" > "$H/current"
echo "$V" > "$H/versions/$V/VERSION"
rm -rf "$H/bin" "$H/lib"
ln -sf "versions/$V/bin" "$H/bin"
ln -sf "versions/$V/lib" "$H/lib"

echo "staged CYRIUS_HOME=$H for $V ($(ls "$H/versions/$V/lib" | wc -l) lib files)"
