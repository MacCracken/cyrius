#!/bin/sh
# install_atomic_over_running_binary.sh — v6.6.1. Installing a toolchain must never `cp` over a
# binary in place, because `~/.cyrius/bin` symlinks into `versions/<current>/bin` — so
# reinstalling the version you are RUNNING makes the installer overwrite its own running image.
#
# ⛔ WHY THIS EXISTS, AND WHY IT IS A GATE RATHER THAN A COMMENT. v6.5.3 diagnosed this exactly
# — ETXTBSY, `mv` replaces the directory entry instead of writing through it, a failure must not
# abort the loop — and then fixed it in ONE of THREE copy paths. The `--refresh-only` loop got
# the temp+rename; the TARBALL path and the SOURCE-BUILD path kept copying in place. A user on a
# clean machine hit the survivor with the plainest possible command:
#
#     $ cyriusly install 6.6.0
#     cp: cannot create regular file '.../versions/6.6.0/bin/cyriusly': Text file busy
#
# ⚠ And `cyriusly install <v>` fetches install.sh from that version's IMMUTABLE TAG (CVE-21),
# so a broken installer is frozen into the release that carries it — it cannot be hot-fixed for
# an already-published version. That is what makes this worth a gate: the blast radius of the
# next occurrence is a release, not a working tree.
#
# ⭐ AXIS 1 IS FUNCTIONAL, NOT A GREP. It reproduces ETXTBSY for real — runs a binary, then
# installs over it — because a source scan can only ever prove the shapes it knows to look for.
# Axis 2 is the scan, and catches a NEW copy site added later.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'pkill -f "$T/bin/victim" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin"

# ── axis 1 — install over a RUNNING binary (the reported failure) ────────────────────────────
cp /bin/sleep "$T/bin/victim" 2>/dev/null || { echo "SKIP install_atomic_over_running_binary: no /bin/sleep"; exit 0; }
cp /bin/true  "$T/bin/replacement"
"$T/bin/victim" 30 &
sleep 1
kill -0 %1 2>/dev/null || { echo "SKIP install_atomic_over_running_binary: victim did not stay running"; exit 0; }

# The premise: a plain `cp` MUST fail here. If it does not, this platform cannot reproduce
# ETXTBSY and the axis would be vacuous — say so rather than passing silently.
if cp "$T/bin/replacement" "$T/bin/victim" 2>/dev/null; then
  echo "SKIP install_atomic_over_running_binary: this platform allows cp over a running binary"
  exit 0
fi

# The install path must succeed anyway.
if cp "$T/bin/replacement" "$T/bin/.victim.new" 2>/dev/null \
   && chmod 755 "$T/bin/.victim.new" 2>/dev/null \
   && mv -f "$T/bin/.victim.new" "$T/bin/victim" 2>/dev/null; then
  :
else
  echo "FAIL install_atomic_over_running_binary axis1: temp+rename could not replace a running binary"
  exit 1
fi
cmp -s "$T/bin/victim" /bin/true || {
  echo "FAIL install_atomic_over_running_binary axis1: target was not actually replaced"; exit 1; }

# ── axis 2 — no install path may `cp` an executable into the version bin dir ─────────────────
# Data files (dlopen-helper.c) and the lib/ subdir copy are exempt: neither is ever executed.
# ⚠ The exemption list is EXACT on purpose. A first cut excluded any line mentioning `$_eb`,
# to allow the tarball path's `cp -r "$_eb"` directory branch — and that same exclusion then
# excused a plain `cp "$_eb"` file copy, so the mutation test PASSED against a reintroduced bug.
# Exempt the recursive DIRECTORY copy specifically, never the variable.
BAD=$(grep -nE 'cp .*versions/\$VERSION/bin' "$R/scripts/install.sh" \
      | grep -vE 'dlopen-helper\.c|bin/lib/|cp -r "\$_eb"' || true)
if [ -n "$BAD" ]; then
  echo "FAIL install_atomic_over_running_binary axis2: an install path copies an executable in"
  echo "  place instead of using _install_file (temp + atomic rename). ETXTBSY will strand it:"
  echo "$BAD" | sed 's/^/    /'
  exit 1
fi

# ── axis 3 — ANTI-VACUOUS: the helper must exist and be used by every path ───────────────────
USES=$(grep -c '_install_file ' "$R/scripts/install.sh")
grep -q '^_install_file()' "$R/scripts/install.sh" || {
  echo "FAIL install_atomic_over_running_binary axis3: _install_file helper is gone — axis 2's"
  echo "  grep would then pass trivially by matching nothing."; exit 1; }
[ "$USES" -ge 5 ] || {
  echo "FAIL install_atomic_over_running_binary axis3: only $USES _install_file call sites; the"
  echo "  three install paths (refresh / tarball / source-build) need at least 5 between them."
  exit 1; }

echo "PASS install_atomic_over_running_binary: temp+rename replaces a RUNNING binary (plain cp reproduced ETXTBSY first) · no install path copies an executable in place · the helper exists and all three paths use it"
exit 0
