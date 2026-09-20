#!/bin/sh
# emit_js_refused_off_x86_linux.sh — v6.6.6 (bite 23b).
#
# `cyrius build --target=js` FAILS BY NAME wherever the host's compiler has no
# `--emit-js`, and still WORKS where it does.
#
# ⛔ WHAT IT DID BEFORE, and why "fails without a reason" understates it. The TypeScript
# front end (`src/frontend/ts/*`) and the JS emitter (`src/backend/js/emit.cyr`) — 7,672
# lines — are included by `src/main.cyr` ALONE, and `--emit-js` is parsed only there.
# Bite 9 armed the PE fork, where `sys_fork` is a -1 stub. On the other four forks the
# fork is REAL, so `_emit_js` genuinely exec'd a cycc that does not know the flag: cycc
# ignored it, read its EMPTY stdin, emitted a runnable binary, and the CLI renamed that
# over the `.js` and printed OK. Measured on real pi at 5a583c1e:
#   $ cyrius build --target=js t.ts out.js
#   emit-js t.ts -> out.js [js] OK          (exit 0)
#   $ file out.js -> ELF 64-bit LSB executable, ARM aarch64  (65,888 bytes)
# A green placebo, not a failure — which is why nobody had reported it.
#
# ⭐ AXIS 1 TIES THE CBT ASSUMPTION TO THE ACTUAL INCLUDE GRAPH. cbt refuses on the basis
# that only `src/main.cyr` carries the TS front end. That is a fact about `src/`, not
# about cbt, so it is re-derived here every run: a fork that LATER GAINS the front end
# turns this red rather than silently keeping a wrong refusal.
#
# ⭐ AXIS 3 EVALUATES `_target_cc_has_js()` rather than reading it, the same probe
# technique as `self_host_src_per_target.sh`: the predicate delegates to the
# `#ifdef` chain in `_self_host_src()`, whose ARM ORDER decides the answer, and no grep
# can see an ordering mistake.
#
# ⭐ AXIS 4's POSITIVE CONTROL IS LOAD-BEARING. "Refuses everywhere" satisfies every
# other axis, and would be a worse bug than the one being fixed — so the x86-64 Linux
# CLI must still turn a real `.ts` into real JS in the same run.
#
# MUTATION LEDGER (each built as a full CLI and re-measured)
#   N1. the `_target_cc_has_js()` guard deleted from `_emit_js`     -> RED (axes 2 + 4)
#   N2. `_target_cc_has_js` returns 1 unconditionally               -> RED (axes 3 + 4)
#   N3. `_target_cc_has_js` returns 0 unconditionally               -> RED (axis 3 + the
#       axis-4 POSITIVE control; every other axis stays green, which is the point)
#   N4. a second fork gains `include "src/frontend/ts/lex.cyr"`     -> RED (axis 1)
#   Real tree -> GREEN.
#
# ⚠ qemu-aarch64 is an EMULATOR, not hardware. It is used for axis 4's negative control
# because the refusal is a CLI-side decision with no compiler involved. The real-hardware
# verification for this bite was run by hand on ecb, ach and pi; see CHANGELOG [6.6.6].
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: emit_js_refused: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL emit_js_refused: no build/cycc"; exit 1; }
BUILD_CYR="${EJR_BUILD_CYR:-$R/cbt/build.cyr}"
[ -f "$BUILD_CYR" ] || { echo "FAIL emit_js_refused: missing $BUILD_CYR"; exit 1; }
SRC_DIR="${EJR_SRC_DIR:-$R/src}"
fail=0

# ── axis 1 — only ONE fork carries the TS front end / JS emitter ─────────────────────
nforks=$(ls "$SRC_DIR"/main*.cyr 2>/dev/null | wc -l | tr -d ' ' || true)
if [ "${nforks:-0}" -lt 7 ]; then
  echo "FAIL axis1: expected >= 7 per-target forks, found ${nforks:-0}"
  fail=1
fi
ts_forks=$(grep -l 'src/frontend/ts' "$SRC_DIR"/main*.cyr 2>/dev/null | sed "s|^$SRC_DIR/|src/|" | sort | tr '\n' ' ' || true)
js_forks=$(grep -l 'src/backend/js'  "$SRC_DIR"/main*.cyr 2>/dev/null | sed "s|^$SRC_DIR/|src/|" | sort | tr '\n' ' ' || true)
flag_forks=$(grep -l 'emit-js' "$SRC_DIR"/main*.cyr 2>/dev/null | sed "s|^$SRC_DIR/|src/|" | sort | tr '\n' ' ' || true)
for pair in "TS front end:$ts_forks" "JS emitter:$js_forks" "--emit-js flag:$flag_forks"; do
  what=${pair%%:*}; got=$(printf '%s' "${pair#*:}" | sed 's/ *$//')
  if [ "$got" != "src/main.cyr" ]; then
    echo "FAIL axis1: the $what is carried by '$got', not by src/main.cyr alone —"
    echo "            cbt/build.cyr's _target_cc_has_js() derives the refusal from that"
    echo "            assumption and is now wrong. Update it with the include graph."
    fail=1
  fi
done

# ── axis 2 — cbt ASKS, and asks before it forks ──────────────────────────────────────
body=$(awk '/^fn _emit_js\(source, output\): i64 \{/{inb=1} inb{print} inb && /^\}/{exit}' "$BUILD_CYR" || true)
if [ -z "$body" ]; then
  echo "FAIL axis2: could not extract _emit_js from $BUILD_CYR"
  fail=1
else
  gl=$(printf '%s\n' "$body" | grep -n '_target_cc_has_js()' | head -1 | cut -d: -f1 || true)
  fl=$(printf '%s\n' "$body" | grep -n 'sys_fork()'          | head -1 | cut -d: -f1 || true)
  if [ -z "$gl" ]; then
    echo "FAIL axis2: _emit_js does not ask _target_cc_has_js()"
    fail=1
  elif [ -z "$fl" ]; then
    echo "FAIL axis2: _emit_js has no sys_fork() — did it change shape?"
    fail=1
  elif [ "$gl" -ge "$fl" ]; then
    echo "FAIL axis2: _emit_js asks _target_cc_has_js() at line $gl, AFTER its sys_fork() at $fl"
    fail=1
  fi
fi
pred=$(awk '/^fn _target_cc_has_js\(\): i64 \{/,/^\}/' "$BUILD_CYR" || true)
if [ -z "$pred" ]; then
  echo "FAIL axis2: _target_cc_has_js is missing from $BUILD_CYR"
  fail=1
else
  printf '%s\n' "$pred" | grep -q '_self_host_src()' || {
    echo "FAIL axis2: _target_cc_has_js does not derive from _self_host_src() — a second"
    echo "            copy of the per-target mapping is exactly how the PE arm shipped alone"
    fail=1
  }
  if printf '%s\n' "$pred" | grep -q '#ifdef'; then
    echo "FAIL axis2: _target_cc_has_js has grown its own #ifdef target ladder"
    fail=1
  fi
fi

# ── axis 3 — EVALUATE the predicate under each host's macro set ──────────────────────
awk '/^fn _self_host_src_macos\(\): i64 \{/,/^\}/' "$BUILD_CYR"  > "$D/fns.cyr"
awk '/^fn _self_host_src\(\): i64 \{/,/^\}/'       "$BUILD_CYR" >> "$D/fns.cyr"
awk '/^fn _target_cc_has_js\(\): i64 \{/,/^\}/'    "$BUILD_CYR" >> "$D/fns.cyr"
nfn=$(grep -c '^fn ' "$D/fns.cyr" || true)
if [ "${nfn:-0}" -lt 3 ]; then
  echo "FAIL axis3: extraction is vacuous ($nfn fns) — the mapping fns moved or changed shape"
  echo "FAIL emit_js_refused_off_x86_linux"
  exit 1
fi
# label:macros:expected  (1 = this host's cycc has --emit-js)
ROWS='linux-x86::1
linux-aarch64:CYRIUS_ARCH_AARCH64:0
macos-arm64:CYRIUS_TARGET_MACOS CYRIUS_ARCH_AARCH64:0
macos-x86:CYRIUS_TARGET_MACOS:0
windows:CYRIUS_TARGET_WIN:0'
: > "$D/a3"
printf '%s\n' "$ROWS" | while IFS= read -r row; do
  [ -n "$row" ] || continue
  lab=$(printf '%s' "$row" | cut -d: -f1)
  defs=$(printf '%s' "$row" | cut -d: -f2)
  want=$(printf '%s' "$row" | cut -d: -f3)
  P="$D/j_$lab.cyr"
  : > "$P"
  for d in $defs; do echo "#define $d" >> "$P"; done
  # streq() is the CLI's own; the probe needs a standalone one under a different name.
  cat >> "$P" <<'PRE'
fn streq(a, b): i64 {
    var i = 0;
    while (load8(a + i) != 0) { if (load8(a + i) != load8(b + i)) { return 0; } i = i + 1; }
    if (load8(b + i) != 0) { return 0; }
    return 1;
}
PRE
  cat "$D/fns.cyr" >> "$P"
  cat >> "$P" <<'PROBE'
var _r = _target_cc_has_js();
syscall(60, _r);
PROBE
  if ! cat "$P" | "$CC" > "$D/jb_$lab" 2>"$D/je_$lab"; then
    echo "  axis3 $lab: PROBE FAILED TO COMPILE"; sed 's/^/    /' "$D/je_$lab"
    echo "$lab BADCOMPILE $want" >> "$D/a3"; continue
  fi
  [ -s "$D/jb_$lab" ] || { echo "  axis3 $lab: probe binary is EMPTY"; echo "$lab BADEMPTY $want" >> "$D/a3"; continue; }
  chmod +x "$D/jb_$lab"
  got=0; ( ulimit -c 0; "$D/jb_$lab" ) || got=$?
  echo "$lab $got $want" >> "$D/a3"
done
n3=$(grep -c . "$D/a3" 2>/dev/null || true); [ -n "$n3" ] || n3=0
if [ "$n3" -ne 5 ]; then
  echo "FAIL axis3: expected 5 evaluated rows, got $n3"
  fail=1
fi
while read -r lab got want; do
  if [ "$got" != "$want" ]; then
    echo "FAIL axis3: $lab — _target_cc_has_js() answered '$got', expected $want"
    fail=1
  fi
done < "$D/a3"

# ── axis 4 — the CLI actually refuses off x86-Linux, and actually works on it ────────
# POSITIVE control first: a refusal everywhere satisfies every axis above.
cat cbt/cyrius.cyr | "$CC" > "$D/cli_x86" 2>"$D/cli_x86.err" || true
if [ ! -s "$D/cli_x86" ]; then
  echo "FAIL axis4: could not build the x86-64 Linux CLI"; sed 's/^/    /' "$D/cli_x86.err"
  fail=1
else
  chmod +x "$D/cli_x86"
  printf 'export const x: number = 1;\nexport function f(a: number): number { return a + 1; }\n' > "$D/t.ts"
  prc=0; ( ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli_x86" build --target=js "$D/t.ts" "$D/ok.js" >"$D/pos.out" 2>&1 ) || prc=$?
  if [ "$prc" -ne 0 ] || [ ! -s "$D/ok.js" ]; then
    echo "FAIL axis4 (positive control): x86-64 Linux --target=js exited $prc / produced no JS"
    sed 's/^/    /' "$D/pos.out"
    fail=1
  elif ! grep -q 'export function f(a) {' "$D/ok.js"; then
    echo "FAIL axis4 (positive control): the emitted file is not the expected JS"
    head -5 "$D/ok.js" | sed 's/^/    /'
    fail=1
  fi
fi
# NEGATIVE control: the aarch64-Linux CLI, under qemu (an EMULATOR — not hardware).
if ! command -v qemu-aarch64 >/dev/null 2>&1; then
  echo "  axis4: SKIP the aarch64 negative control — qemu-aarch64 not installed."
  echo "         (install qemu-user; this axis is what proves the refusal actually fires)"
else
  cat src/main_aarch64.cyr | "$CC" > "$D/cc_a64" 2>"$D/cc_a64.err"
  if [ ! -s "$D/cc_a64" ]; then
    echo "FAIL axis4: could not build the aarch64-emitting cross compiler"; sed 's/^/    /' "$D/cc_a64.err"
    fail=1
  else
    chmod +x "$D/cc_a64"
    cat cbt/cyrius.cyr | "$D/cc_a64" > "$D/cli_a64" 2>"$D/cli_a64.err" || true
    if [ ! -s "$D/cli_a64" ]; then
      echo "FAIL axis4: could not build the aarch64 CLI"; sed 's/^/    /' "$D/cli_a64.err"
      fail=1
    else
      chmod +x "$D/cli_a64"
      rm -f "$D/neg.js"
      nrc=0; ( ulimit -c 0; CYRIUS_RESOLVED=1 qemu-aarch64 "$D/cli_a64" build --target=js "$D/t.ts" "$D/neg.js" >"$D/neg.out" 2>&1 ) || nrc=$?
      if [ "$nrc" -eq 0 ]; then
        echo "FAIL axis4: the aarch64 CLI reported SUCCESS for --target=js (the pre-6.6.6 placebo)"
        sed 's/^/    /' "$D/neg.out"
        fail=1
      fi
      if [ -e "$D/neg.js" ]; then
        echo "FAIL axis4: the aarch64 CLI produced $(wc -c < "$D/neg.js") bytes of '.js' it cannot emit"
        fail=1
      fi
      if ! grep -q 'src/main_aarch64_native.cyr' "$D/neg.out"; then
        echo "FAIL axis4: the refusal does not NAME the fork this host's cycc is built from"
        sed 's/^/    /' "$D/neg.out"
        fail=1
      fi
      if ! grep -q 'not available on this target' "$D/neg.out"; then
        echo "FAIL axis4: the aarch64 CLI failed without saying --target=js is unavailable"
        sed 's/^/    /' "$D/neg.out"
        fail=1
      fi
    fi
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL emit_js_refused_off_x86_linux"
  exit 1
fi
echo "PASS emit_js_refused_off_x86_linux: TS front end in src/main.cyr alone; 5 hosts evaluated; x86-64 Linux emits JS, aarch64 refuses by name (qemu, not hardware)"
exit 0
