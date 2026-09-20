#!/bin/sh
# capacity_meters_host_fork.sh — v6.6.6 (bite 24b).
#
# A bare `cyrius capacity` (no file argument) meters THIS HOST'S compiler fork, and still
# falls back to the generic project entries where there is no per-target fork.
#
# ⛔ WHAT IT DID BEFORE. The default was the bare literal `src/main.cyr` — which is the
# x86-64 LINUX fork, one of seven. Inside a cyrius checkout on ARM or macOS, a bare
# `cyrius capacity` therefore compiled a compiler that host does not build and cannot run,
# and printed its fn_table / var_table / fixup_table / code_size occupancy as though they
# were the local compiler's. Every number in that table was about the wrong binary, and
# nothing in the output said so — `capacity --check`'s whole job is to warn before a cap
# bites, and it was watching a fork nobody on that host ships. Same class as bite 23a
# (`cyrius self` / `cyrius soak` self-hosting from the x86 fork on every host).
#
# ⭐ THE FIX ASKS `_self_host_src()` (cbt/build.cyr) rather than growing a second copy of
# the per-target mapping — the mapping is an `#ifdef` chain whose ARM ORDER decides the
# answer (TARGET_MACOS before ARCH_AARCH64, or Apple Silicon takes the Linux-ARM arm), and
# a duplicate is how bite 23a's defect would come back one caller at a time.
#
# ⭐ AXIS 2b IS THE REAL-CHECKOUT AXIS: it puts BOTH forks on disk (with different fn
# counts, so the capacity table itself names the one metered) — the shape every cyrius
# checkout has, and the one a source-order mistake hides in.
#
# ⭐ AXIS 3 (the FALLBACK) IS LOAD-BEARING and is the reason the two literals stayed. A
# fix that ONLY consults `_self_host_src()` satisfies axis 2 and breaks `cyrius capacity`
# for every non-cyrius project on ARM and macOS, which is a much larger blast radius than
# the bug. The gate measures both directions in one run.
#
# MUTATION LEDGER (measured; each mutant a `git archive HEAD` copy with cbt/ overlaid,
# the aarch64 cross compiler and BOTH CLIs rebuilt from it, gate re-run against it)
#   M1. the pre-fix shape (the dispatch resolves its own default from `src/main.cyr`)
#       -> RED: axis 1 names all three problems and stops there (a missing resolver is
#          loud, not a silent pass)
#   M2. `_self_host_src()` consulted but the two literal fallbacks DELETED
#       -> RED: axis 3 ONLY. Axes 1, 2 and 2b stay GREEN — which is why the positive
#          control is in the same run.
#   M3. the two `file_exists` arms swapped so `src/main.cyr` is tested FIRST
#       -> RED: axis 1 (order) and axis 2b (the aarch64 CLI meters fn_table 2, the
#          src/main.cyr probe, where 9 is its own fork). ⚠ This mutant is why axis 2b
#          exists and why axis 1 orders the `file_exists` rather than the CALL: the gate's
#          first cut compared where `_self_host_src()` was called, and M3 leaves that line
#          where it is, so it PASSED — an unreachable improvement reading as a fix, inside
#          a real checkout where both files exist.
#   M4. the resolution inlined back into `main` (the first cut of this fix)
#       -> RED: axis 1. ⚠ This is not hypothetical — that first cut SHIPPED for one
#          commit and turned `self_host_src_per_target.sh` axis 6 red with
#          `cbt/cyrius.cyr main asks _self_host_src() AND hard-codes a fork`, because
#          `main` also runs a compiler (the pin re-exec) and therefore counts as a
#          self-host loop. The helper is load-bearing, not tidiness.
#   Real tree -> GREEN.
#
# ⚠ qemu-aarch64 is an EMULATOR, not hardware. It is used because the choice under test is
# a CLI-side `#ifdef` decision with no compiler behaviour involved; the exec'd cycc is the
# host's own x86-64 binary either way. The REAL-HARDWARE pass was run by hand on pi
# (aarch64, Linux 6.8.0-1064-raspi) with the same two-fork workspace and the tracked
# aarch64-native cycc: the pre-fix CLI reported `note: 1 unreachable fns` (it metered the
# 2-fn src/main.cyr probe) and the fixed CLI `note: 8 unreachable fns` (the 9-fn
# src/main_aarch64_native.cyr). See CHANGELOG [6.6.6].
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: capacity_meters_host_fork: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL capacity_meters_host_fork: no build/cycc"; exit 1; }
fail=0

# ── axis 1 — the resolver ASKS, and asks BEFORE the generic fallbacks ────────────────
# ⚠ The resolution is a HELPER (`_capacity_default_src` in cbt/build.cyr), not inline in
# the dispatch. That is not style: `self_host_src_per_target.sh` axis 6 discovers every fn
# that both asks `_self_host_src()` and runs something, and `main` runs plenty — the first
# cut of this fix put the chain inline and turned that gate RED with "main asks
# _self_host_src() AND hard-codes a fork". So axis 1 checks the dispatch DELEGATES and the
# helper decides.
blk=$(awk '/if \(streq\(cmd, "capacity"\) == 1\) \{/{on=1} on{print; if (/return cmd_capacity\(/) exit}' cbt/cyrius.cyr || true)
if [ -z "$blk" ]; then
  echo "FAIL axis1: could not extract the capacity dispatch from cbt/cyrius.cyr"
  echo "FAIL capacity_meters_host_fork"; exit 1
fi
printf '%s\n' "$blk" | grep -q '_capacity_default_src()' || {
  echo "FAIL axis1: the capacity dispatch does not call _capacity_default_src() — it is"
  echo "            resolving the default itself, and on ARM/macOS that means src/main.cyr"
  fail=1; }
inline=$(printf '%s\n' "$blk" | sed 's/#.*$//' | grep -n '"src/main[A-Za-z0-9_]*\.cyr"' || true)
if [ -n "$inline" ]; then
  echo "FAIL axis1: the capacity dispatch names a compiler fork inline — that is what made"
  echo "            main a self-host loop that both asks and hard-codes (axis 6 of"
  echo "            self_host_src_per_target.sh):"
  printf '%s\n' "$inline" | sed 's/^/    /'
  fail=1
fi
# ⚠ The order that matters is where the fork is TESTED, not where `_self_host_src()` is
# CALLED — the gate's own first cut compared the call site and passed mutant M3, which
# hoists the call and then tests `src/main.cyr` first (an unreachable improvement inside
# any cyrius checkout, since both files exist there). So the variable the call is bound to
# is derived from the helper and its `file_exists` is what gets ordered.
res=$(awk '/^fn _capacity_default_src\(\): i64 \{/,/^\}/' cbt/build.cyr || true)
if [ -z "$res" ]; then
  echo "FAIL axis1: _capacity_default_src is missing from cbt/build.cyr"
  echo "FAIL capacity_meters_host_fork"; exit 1
fi
if printf '%s\n' "$res" | grep -q '#ifdef'; then
  echo "FAIL axis1: _capacity_default_src has grown its own #ifdef target ladder instead of"
  echo "            asking _self_host_src() — a second copy of the mapping drifts"
  fail=1
fi
sv=$(printf '%s\n' "$res" | sed -n 's/^[ \t]*var[ \t]*\([A-Za-z_][A-Za-z_0-9]*\)[ \t]*=[ \t]*_self_host_src();.*/\1/p' | head -1)
ml=$(printf '%s\n' "$res" | grep -n 'file_exists("src/main.cyr")' | head -1 | cut -d: -f1 || true)
if [ -z "${sv:-}" ]; then
  echo "FAIL axis1: _capacity_default_src does not bind _self_host_src() — it is metering"
  echo "            src/main.cyr, the x86-64 Linux fork, on every host"
  fail=1
else
  sl=$(printf '%s\n' "$res" | grep -n "file_exists($sv)" | head -1 | cut -d: -f1 || true)
  if [ -z "${sl:-}" ]; then
    echo "FAIL axis1: '$sv' is bound from _self_host_src() but never tested with file_exists"
    fail=1
  elif [ -n "$ml" ] && [ "$sl" -ge "$ml" ]; then
    echo "FAIL axis1: the host fork ('$sv') is tested at line $sl of _capacity_default_src,"
    echo "            AFTER the src/main.cyr fallback at $ml — a cyrius checkout has BOTH"
    echo "            files, so the fallback wins and the improvement is unreachable"
    fail=1
  fi
fi
grep -q '^fn _self_host_src(): i64 {' cbt/build.cyr || {
  echo "FAIL axis1: _self_host_src is missing from cbt/build.cyr — the mapping moved"
  fail=1
}
nforks=$(ls src/main*.cyr 2>/dev/null | wc -l | tr -d ' ')
if [ "${nforks:-0}" -lt 7 ]; then
  echo "FAIL axis1: expected >= 7 per-target forks in src/, found ${nforks:-0} — this gate's premise"
  fail=1
fi

# ── build the two CLIs under test ────────────────────────────────────────────────────
cat cbt/cyrius.cyr | "$CC" > "$D/cli_x86" 2>"$D/cli_x86.err" || true
if [ ! -s "$D/cli_x86" ]; then
  echo "FAIL: could not build the x86-64 Linux CLI"; sed 's/^/    /' "$D/cli_x86.err"
  echo "FAIL capacity_meters_host_fork"; exit 1
fi
chmod +x "$D/cli_x86"
HAVE_A64=0
if command -v qemu-aarch64 >/dev/null 2>&1; then
  cat src/main_aarch64.cyr | "$CC" > "$D/cc_a64" 2>"$D/cc_a64.err"
  if [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"
    cat cbt/cyrius.cyr | "$D/cc_a64" > "$D/cli_a64" 2>"$D/cli_a64.err" || true
    if [ -s "$D/cli_a64" ]; then chmod +x "$D/cli_a64"; HAVE_A64=1
    else echo "FAIL: could not build the aarch64 CLI"; sed 's/^/    /' "$D/cli_a64.err"; fail=1; fi
  else
    echo "FAIL: could not build the aarch64-emitting cross compiler"; sed 's/^/    /' "$D/cc_a64.err"; fail=1
  fi
else
  echo "  SKIP the aarch64 halves of axes 2/3 — qemu-aarch64 not installed."
  echo "       (install qemu-user; they are what prove the per-target default actually fires)"
fi

# `capacity` forks the host's cycc, so every workspace carries a build/cycc. Under
# qemu-user an execve is handed to the host kernel, so the x86-64 cycc runs natively in
# both scenarios — the ONLY thing that differs is which source the CLI chose.
# Each fork is written with a DIFFERENT number of fns so the capacity table itself says
# which one was metered — `fn_table: N`. N is checked against a count taken a different
# way (grep over the probe source), never against what the CLI printed.
mkws() {   # $1 = dir, then pairs "<fork basename>:<fn count>"
  d=$1; shift
  mkdir -p "$d/src" "$d/build"
  cp "$CC" "$d/build/cycc"
  for spec in "$@"; do
    f=${spec%%:*}; k=${spec#*:}
    : > "$d/src/$f"
    i=1
    while [ "$i" -lt "$k" ]; do echo "fn p_${f%%.*}_$i(): i64 { return $i; }" >> "$d/src/$f"; i=$((i + 1)); done
    echo 'fn main(): i64 { return 0; }' >> "$d/src/$f"
  done
}
want_fns() { grep -c '^fn ' "$1"; }   # the expected fn_table, derived from the source
runcap() {  # $1 = label, $2 = workspace, $3 = "" for native or "qemu-aarch64", $4 = cli
  lab=$1; ws=$2; emu=$3; cli=$4
  rc=0
  ( cd "$ws" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 $emu "$cli" capacity >"$D/$lab.out" 2>&1 ) || rc=$?
  echo "$rc"
}

# ── axis 2 — a checkout carrying ONLY the aarch64-native fork ────────────────────────
# The x86-64 CLI must NOT meter it (that fork is not its compiler); the aarch64 CLI must.
mkws "$D/only_a64" main_aarch64_native.cyr:3
rc=$(runcap a2x "$D/only_a64" "" "$D/cli_x86")
if [ "$rc" -eq 0 ]; then
  echo "FAIL axis2: the x86-64 CLI metered a checkout that has no src/main.cyr — it picked"
  echo "            a fork it does not build"
  sed 's/^/    /' "$D/a2x.out"; fail=1
fi
if [ "$HAVE_A64" -eq 1 ]; then
  rc=$(runcap a2a "$D/only_a64" "qemu-aarch64" "$D/cli_a64")
  if [ "$rc" -ne 0 ]; then
    echo "FAIL axis2: the aarch64 CLI exited $rc in a checkout carrying ITS fork"
    echo "            (src/main_aarch64_native.cyr) — it is still defaulting to src/main.cyr"
    sed 's/^/    /' "$D/a2a.out"; fail=1
  elif ! grep -q 'fn_table:' "$D/a2a.out"; then
    echo "FAIL axis2: the aarch64 CLI exited 0 but printed no capacity table"
    sed 's/^/    /' "$D/a2a.out"; fail=1
  fi
fi

# ── axis 2b — a REAL checkout: BOTH forks present, and they must be told apart ───────
# This is the shape every cyrius checkout has, and the one a source-order mistake hides
# in: with `src/main.cyr` also on disk, a fix that tests it first is unreachable. The two
# probe forks carry different fn counts, so the capacity table names the file it metered.
mkws "$D/both" main.cyr:2 main_aarch64_native.cyr:9
W_MAIN=$(want_fns "$D/both/src/main.cyr")
W_A64=$(want_fns "$D/both/src/main_aarch64_native.cyr")
if [ "$W_MAIN" = "$W_A64" ]; then
  echo "FAIL axis2b: the two probe forks are indistinguishable ($W_MAIN fns each)"
  fail=1
fi
rc=$(runcap a2bx "$D/both" "" "$D/cli_x86")
got=$(sed -n 's/^ *fn_table: *\([0-9]*\) .*/\1/p' "$D/a2bx.out" | head -1)
if [ "$rc" -ne 0 ] || [ "${got:-}" != "$W_MAIN" ]; then
  echo "FAIL axis2b: the x86-64 CLI exited $rc and metered fn_table='${got:-none}', expected $W_MAIN (src/main.cyr)"
  sed 's/^/    /' "$D/a2bx.out"; fail=1
fi
if [ "$HAVE_A64" -eq 1 ]; then
  rc=$(runcap a2ba "$D/both" "qemu-aarch64" "$D/cli_a64")
  got=$(sed -n 's/^ *fn_table: *\([0-9]*\) .*/\1/p' "$D/a2ba.out" | head -1)
  if [ "$rc" -ne 0 ] || [ "${got:-}" != "$W_A64" ]; then
    echo "FAIL axis2b: the aarch64 CLI exited $rc and metered fn_table='${got:-none}', expected"
    echo "            $W_A64 (src/main_aarch64_native.cyr). ${got:-none} == $W_MAIN means it metered"
    echo "            src/main.cyr — the x86-64 Linux fork — inside a checkout carrying its own."
    sed 's/^/    /' "$D/a2ba.out"; fail=1
  fi
fi

# ── axis 3 — POSITIVE CONTROL: the generic fallback still answers ────────────────────
# A non-cyrius project has no per-target fork. Both CLIs must still meter src/main.cyr —
# a fix that consults ONLY _self_host_src() passes axis 2 and breaks every ARM/macOS
# project, a far bigger blast radius than the bug.
mkws "$D/only_main" main.cyr:2
rc=$(runcap a3x "$D/only_main" "" "$D/cli_x86")
if [ "$rc" -ne 0 ] || ! grep -q 'fn_table:' "$D/a3x.out"; then
  echo "FAIL axis3 (positive control): the x86-64 CLI exited $rc on a plain src/main.cyr project"
  sed 's/^/    /' "$D/a3x.out"; fail=1
fi
if [ "$HAVE_A64" -eq 1 ]; then
  rc=$(runcap a3a "$D/only_main" "qemu-aarch64" "$D/cli_a64")
  if [ "$rc" -ne 0 ] || ! grep -q 'fn_table:' "$D/a3a.out"; then
    echo "FAIL axis3 (positive control): the aarch64 CLI exited $rc on a plain src/main.cyr"
    echo "            project — the generic fallback was dropped"
    sed 's/^/    /' "$D/a3a.out"; fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL capacity_meters_host_fork"
  exit 1
fi
if [ "$HAVE_A64" -eq 1 ]; then
  echo "PASS capacity_meters_host_fork: the dispatch delegates and _capacity_default_src asks _self_host_src() first; aarch64 CLI meters its own fork where x86-64 refuses; both still meter a plain src/main.cyr project (qemu, not hardware)"
else
  echo "PASS capacity_meters_host_fork: the dispatch delegates and _capacity_default_src asks _self_host_src() first; x86-64 half only (no qemu-aarch64)"
fi
exit 0
