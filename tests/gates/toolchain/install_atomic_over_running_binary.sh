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
# ⚠ And `cyriusly install <v>` fetches install.sh from that version's IMMUTABLE TAG (the release-integrity hardening item),
# so a broken installer is frozen into the release that carries it — it cannot be hot-fixed for
# an already-published version. That is what makes this worth a gate: the blast radius of the
# next occurrence is a release, not a working tree.
#
# ⭐ AXIS 1 IS FUNCTIONAL, NOT A GREP. It reproduces ETXTBSY for real — runs a binary, then
# installs over it — because a source scan can only ever prove the shapes it knows to look for.
# Axis 2 is the scan, and catches a NEW copy site added later.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
# ⛔ v6.6.6: CHECK THE TEMP DIR, AND REAP THE VICTIM BY PID. This line was
# `T=$(mktemp -d); trap 'pkill -f "$T/bin/victim" …' EXIT` — with an unusable TMPDIR, T was empty,
# the `cp` into "/bin/victim" failed and was misreported as "SKIP … no /bin/sleep" (rc 0), and the
# EXIT trap ran a BOX-WIDE `pkill -f /bin/victim`, which matches every OTHER run's
# "<its T>/bin/victim" — two check.sh runs on one box could kill each other's victim mid-axis.
# The gate now kills only the PID it started. CHANGELOG [6.6.6]
# Mutation (6.6.6, `pkill` shimmed on PATH to a logger): the 6.6.5 gate under TMPDIR=/nonexistent
# -> rc 0 and the log holds `pkill -f /bin/victim`; this gate -> FAIL, and the log stays empty on
# both that run and a normal PASS run.
VPID=""
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL install_atomic_over_running_binary: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# ⛔ 6.6.8: every command in the cleanup is `|| true`. `wait` on the victim WE killed returns
# 143, and under `bash -eo pipefail` (how CLAUDE.md says shell gates must be tested) that
# failing command inside the EXIT trap became the script's exit status: the gate printed PASS
# and exited 143. Pinned by axis 4 below. CHANGELOG [6.6.8]
_ia_cleanup() {
    if [ -n "$VPID" ]; then
        kill "$VPID" 2>/dev/null || true
        wait "$VPID" 2>/dev/null || true
    fi
    rm -rf "$T" || true
}
trap _ia_cleanup EXIT
mkdir -p "$T/bin" || { echo "FAIL install_atomic_over_running_binary: cannot create $T/bin"; exit 1; }

# ── axis 1 — install over a RUNNING binary (the reported failure) ────────────────────────────
[ -x /bin/sleep ] && [ -x /bin/true ] || { echo "SKIP install_atomic_over_running_binary: no /bin/sleep or /bin/true on this host"; exit 77; }
cp /bin/sleep "$T/bin/victim" && cp /bin/true "$T/bin/replacement" \
  || { echo "FAIL install_atomic_over_running_binary: cannot stage /bin/sleep and /bin/true into $T/bin"; exit 1; }
"$T/bin/victim" 30 &
VPID=$!
sleep 1
kill -0 "$VPID" 2>/dev/null || { echo "SKIP install_atomic_over_running_binary: victim did not stay running"; exit 77; }

# The premise: a plain `cp` MUST fail here. If it does not, this platform cannot reproduce
# ETXTBSY and the axis would be vacuous — say so rather than passing silently.
if cp "$T/bin/replacement" "$T/bin/victim" 2>/dev/null; then
  echo "SKIP install_atomic_over_running_binary: this platform allows cp over a running binary"
  exit 77
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
# Data files (dlopen-helper.c) are exempt: never executed. (The `bin/lib/` exemption that stood
# here covered the copy of scripts/lib/*.sh, deleted with that dir at 6.6.7 — an exemption that
# matches nothing would only excuse a future line.)
# ⚠ The exemption list is EXACT on purpose. A first cut excluded any line mentioning `$_eb`,
# to allow the tarball path's `cp -r "$_eb"` directory branch — and that same exclusion then
# excused a plain `cp "$_eb"` file copy, so the mutation test PASSED against a reintroduced bug.
# Exempt the recursive DIRECTORY copy specifically, never the variable.
BAD=$(grep -nE 'cp .*versions/\$VERSION/bin' "$R/scripts/install.sh" \
      | grep -vE 'dlopen-helper\.c|cp -r "\$_eb"' || true)
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

# ── axis 4 — 6.6.8: the gate itself exits 0 under `bash -eo pipefail` ────────────────────────
# Re-runs THIS file once under bash -eo pipefail (the inner run skips this axis). It printed
# PASS and exited 143 there, because its EXIT trap's `wait` on the victim it had killed failed.
if [ -z "${CY_IA_INNER:-}" ] && command -v bash > /dev/null 2>&1; then
  IRC=0
  CY_IA_INNER=1 bash -eo pipefail "$0" > "$T/inner.out" 2>&1 || IRC=$?
  if [ "$IRC" != "0" ] || ! grep -q '^PASS install_atomic_over_running_binary' "$T/inner.out"; then
    echo "FAIL install_atomic_over_running_binary axis4: under bash -eo pipefail the gate exited $IRC:"
    sed 's/^/    /' "$T/inner.out"
    exit 1
  fi
fi

echo "PASS install_atomic_over_running_binary: temp+rename replaces a RUNNING binary (plain cp reproduced ETXTBSY first) · no install path copies an executable in place · the helper exists and all three paths use it · exits 0 under bash -eo pipefail"
exit 0
