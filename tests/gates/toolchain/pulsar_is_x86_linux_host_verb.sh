#!/bin/sh
# pulsar_is_x86_linux_host_verb.sh — v6.6.6 (bite 24c).
#
# `cyrius pulsar` SAYS it is an x86-64-Linux-host verb, before it does anything, and still
# runs on an x86-64 Linux host.
#
# ⛔ WHAT IT DID BEFORE. `cmd_pulsar` is an orchestrator for one host and nothing said so:
# it rebuilds the TRACKED x86-64 Linux `build/cycc` from `src/main.cyr`, then builds the
# aarch64 cross compilers *with that binary* (x86-hosted by construction), then the tools,
# then runs `scripts/install.sh --refresh-only`. Both literals are right FOR THAT HOST —
# which is why they stay — but off it the first `_pulsar_raw_compile` execs an x86-64 Linux
# ELF that cannot run, the child exits 127, and the verb prints `error: cycc compile
# failed`: a message about the COMPILER for a problem that is about the VERB. A user on
# ecb or pi reads that as a broken toolchain and goes looking in the wrong place.
#
# ⭐ AXIS 4 TIES THE REFUSAL TO THE RECIPE IT IS ABOUT. "pulsar is x86-64-Linux-only" is a
# claim about what `cmd_pulsar` actually compiles, not about cbt in general, so the recipe
# is re-derived every run: if pulsar ever becomes per-target (asking `_self_host_src()` for
# its own stages), this turns RED rather than leaving a now-wrong refusal in place — the
# same reason `emit_js_refused_off_x86_linux.sh` re-derives the include graph.
#
# ⭐ AXIS 3's POSITIVE CONTROL IS LOAD-BEARING: refusing everywhere satisfies axes 1, 2 and
# 4 and would break the only host that can run the verb at all.
#
# ⭐ AXIS 2 ALSO CHECKS THE PROGRESS LINE IS NOT PRINTED. The check is the first statement
# of `cmd_pulsar` deliberately — `_status("pulsar: rebuilding from source...")` used to be
# first, and a refusal after it reads as a rebuild that then failed (bite 24d's defect,
# pinned here at the site that would otherwise reintroduce it).
#
# MUTATION LEDGER (measured; each mutant a `git archive HEAD` copy with one file overlaid,
# the aarch64 cross compiler and BOTH CLIs rebuilt from it, gate re-run against it)
#   M1. the host check deleted (the HEAD shape)
#       -> RED: axis 1, axis 2 (the aarch64 CLI prints `pulsar: rebuilding from source...`
#          and then `error: cycc compile failed`)
#   M2. the check moved BELOW the `_status(...)` progress line
#       -> RED: axis 1 (order) and axis 2 (the progress line is printed first)
#   M3. `_pulsar_host_is_x86_linux()` returns 0 unconditionally
#       -> RED: axis 3, the positive control, ALONE
#   M4. `_pulsar_host_is_x86_linux()` grows its own `#ifdef` ladder instead of asking
#       `_self_host_src()`  -> RED: axis 1 (the duplicate-mapping check)
#   Real tree -> GREEN.
#
# ⚠ qemu-aarch64 is an EMULATOR, not hardware. The REAL-HARDWARE pass was run by hand on
# pi (aarch64, Linux 6.8.0-1064-raspi), with the tracked aarch64-native cycc placed as
# build/cycc so the verb could get as far as possible. Pre-fix:
#   pulsar: rebuilding from source...
#     cycc...
#   error: cycc stage-2 compile failed            (exit 1)
# Fixed: the named refusal, no progress line (exit 1). In a REAL ARM checkout build/cycc
# is the tracked x86-64 ELF, so the pre-fix message is `cycc compile failed` from stage 1
# instead — same shape, one stage earlier. See CHANGELOG [6.6.6].
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pulsar_is_x86_linux_host_verb: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL pulsar_is_x86_linux_host_verb: no build/cycc"; exit 1; }
P=cbt/pulsar.cyr
[ -f "$P" ] || { echo "FAIL pulsar_is_x86_linux_host_verb: missing $P"; exit 1; }
fail=0

# ── axis 1 — the check is FIRST, and derives from the one mapping ────────────────────
body=$(awk '/^fn cmd_pulsar\(\): i64 \{/{on=1} on{print} on && /^\}/{exit}' "$P" || true)
if [ -z "$body" ]; then
  echo "FAIL axis1: could not extract cmd_pulsar from $P"
  echo "FAIL pulsar_is_x86_linux_host_verb"; exit 1
fi
gl=$(printf '%s\n' "$body" | grep -n '_pulsar_host_is_x86_linux()' | head -1 | cut -d: -f1 || true)
sl=$(printf '%s\n' "$body" | grep -n '_status(' | head -1 | cut -d: -f1 || true)
cl=$(printf '%s\n' "$body" | grep -n '_pulsar_raw_compile(' | head -1 | cut -d: -f1 || true)
if [ -z "${gl:-}" ]; then
  echo "FAIL axis1: cmd_pulsar does not ask _pulsar_host_is_x86_linux() — it will exec an"
  echo "            x86-64 Linux ELF on any host and report 'cycc compile failed'"
  fail=1
else
  if [ -n "${sl:-}" ] && [ "$gl" -ge "$sl" ]; then
    echo "FAIL axis1: the host check is at line $gl of cmd_pulsar, AFTER the _status()"
    echo "            progress line at $sl — the refusal then reads as a rebuild that failed"
    fail=1
  fi
  if [ -n "${cl:-}" ] && [ "$gl" -ge "$cl" ]; then
    echo "FAIL axis1: the host check is at line $gl, AFTER the first _pulsar_raw_compile at $cl"
    fail=1
  fi
fi
pred=$(awk '/^fn _pulsar_host_is_x86_linux\(\): i64 \{/,/^\}/' "$P" || true)
if [ -z "$pred" ]; then
  echo "FAIL axis1: _pulsar_host_is_x86_linux is missing from $P"
  fail=1
else
  printf '%s\n' "$pred" | grep -q '_self_host_src()' || {
    echo "FAIL axis1: _pulsar_host_is_x86_linux does not derive from _self_host_src() — a"
    echo "            second copy of the per-target mapping is how bite 23a's defect returns"
    fail=1
  }
  if printf '%s\n' "$pred" | grep -q '#ifdef'; then
    echo "FAIL axis1: _pulsar_host_is_x86_linux has grown its own #ifdef target ladder"
    fail=1
  fi
fi

# ── axis 4 — the RECIPE the refusal is about is still the x86-64 Linux one ────────────
printf '%s\n' "$body" | grep -q '_pulsar_raw_compile("build/cycc", "src/main.cyr"' || {
  echo "FAIL axis4: cmd_pulsar no longer builds src/main.cyr with build/cycc. The refusal"
  echo "            claims pulsar is x86-64-Linux-only BECAUSE of that recipe; if the verb"
  echo "            became per-target the refusal is now wrong, not merely stale."
  fail=1
}
nstage=$(printf '%s\n' "$body" | grep -c '_pulsar_raw_compile(' || true)
if [ "${nstage:-0}" -lt 3 ]; then
  echo "FAIL axis4: found only ${nstage:-0} _pulsar_raw_compile stages (want >= 3) — extraction is vacuous"
  fail=1
fi

# ── build the CLIs ───────────────────────────────────────────────────────────────────
cat cbt/cyrius.cyr | "$CC" > "$D/cli_x86" 2>"$D/cli_x86.err" || true
if [ ! -s "$D/cli_x86" ]; then
  echo "FAIL: could not build the x86-64 Linux CLI"; sed 's/^/    /' "$D/cli_x86.err"
  echo "FAIL pulsar_is_x86_linux_host_verb"; exit 1
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
  echo "  SKIP axis 2 — qemu-aarch64 not installed. (install qemu-user; axis 2 is what"
  echo "       proves the refusal actually fires rather than merely being written down)"
fi

# A throwaway workspace: pulsar must not be pointed at the real checkout, and a fake one
# is enough — the decision under test happens before anything is compiled.
W="$D/w"; mkdir -p "$W/src" "$W/build"
cp "$CC" "$W/build/cycc"
printf 'fn main(): i64 { return 0; }\n' > "$W/src/main.cyr"
printf 'fn main(): i64 { return 0; }\n' > "$W/src/main_aarch64_native.cyr"
echo "0.0.0-probe" > "$W/VERSION"

# ── axis 2 — the aarch64 CLI refuses BY NAME, before printing any progress ───────────
if [ "$HAVE_A64" -eq 1 ]; then
  rc=0
  ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 qemu-aarch64 "$D/cli_a64" pulsar >"$D/a2.out" 2>&1 ) || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL axis2: the aarch64 CLI exited 0 for a verb it cannot run"
    sed 's/^/    /' "$D/a2.out"; fail=1
  fi
  grep -q 'x86-64 Linux-host verb' "$D/a2.out" || {
    echo "FAIL axis2: the failure does not say pulsar is an x86-64 Linux-host verb"
    sed 's/^/    /' "$D/a2.out"; fail=1; }
  grep -q 'src/main_aarch64_native.cyr' "$D/a2.out" || {
    echo "FAIL axis2: the refusal does not NAME the fork this host's compiler is built from"
    sed 's/^/    /' "$D/a2.out"; fail=1; }
  if grep -q 'rebuilding from source' "$D/a2.out"; then
    echo "FAIL axis2: the progress line was printed before the refusal — it reads as a"
    echo "            rebuild that then failed, not as a verb that does not apply here"
    sed 's/^/    /' "$D/a2.out"; fail=1
  fi
  if grep -q 'cycc compile failed' "$D/a2.out"; then
    echo "FAIL axis2: still reports 'cycc compile failed' — a message about the compiler"
    echo "            for a problem that is about the verb"
    sed 's/^/    /' "$D/a2.out"; fail=1
  fi
fi

# ── axis 3 — POSITIVE CONTROL: the x86-64 Linux CLI gets PAST the check ──────────────
# It is not expected to finish (the workspace is a stub), only to be allowed to start.
( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli_x86" pulsar >"$D/a3.out" 2>&1 ) || true
if grep -q 'x86-64 Linux-host verb' "$D/a3.out"; then
  echo "FAIL axis3 (positive control): the x86-64 Linux CLI refused its own verb"
  sed 's/^/    /' "$D/a3.out"; fail=1
fi
grep -q 'rebuilding from source' "$D/a3.out" || {
  echo "FAIL axis3 (positive control): the x86-64 Linux CLI never started the rebuild"
  sed 's/^/    /' "$D/a3.out"; fail=1; }

if [ "$fail" -ne 0 ]; then
  echo "FAIL pulsar_is_x86_linux_host_verb"
  exit 1
fi
if [ "$HAVE_A64" -eq 1 ]; then
  echo "PASS pulsar_is_x86_linux_host_verb: check is first and derives from _self_host_src(); $nstage x86 build stages; aarch64 CLI refuses by name with no progress line; x86-64 Linux CLI still starts (qemu, not hardware)"
else
  echo "PASS pulsar_is_x86_linux_host_verb: check is first and derives from _self_host_src(); $nstage x86 build stages; x86-64 Linux half only (no qemu-aarch64)"
fi
exit 0
