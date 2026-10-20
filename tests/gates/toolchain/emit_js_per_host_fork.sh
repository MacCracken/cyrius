#!/bin/sh
# emit_js_per_host_fork.sh — v6.6.6 (bite 23b, as emit_js_refused_off_x86_linux.sh); 6.7.15; 6.7.16.
#
# `cyrius build --target=js` RUNS wherever the host's compiler has `--emit-js`, and FAILS BY
# NAME where it does not — and which hosts those are is read off the include graph, never
# typed in a list.
#
# ⛔ WHAT IT DID BEFORE 6.6.6. The TypeScript front end (`src/frontend/ts/*`) and the JS
# emitter (`src/backend/js/emit.cyr`) were included by `src/main.cyr` ALONE. On the other
# forks the fork in `_emit_js` was REAL, so it exec'd a cycc that did not know the flag: cycc
# ignored it, read its EMPTY stdin, emitted a runnable binary, and the CLI renamed that over
# the `.js` and printed OK (measured on real pi at 5a583c1e: `emit-js t.ts -> out.js [js] OK`,
# exit 0, out.js a 65,888-byte aarch64 ELF). 6.6.6 refused it by name off x86-64 Linux.
#
# ⭐ 6.7.15 (6.7.15's D38): every host fork carries the front end and the three TS flags
# (src/frontend/ts/driver*.cyr), so the CLI runs `--target=js` on every POSIX host; this gate
# was emit_js_refused_off_x86_linux.sh and its axis 1 turned red the day the forks gained the
# front end, as it was built to. Windows still refuses — its CLI has no spawn for the emit —
# and says so (tests/gates/platform/cbt_fork_sites_have_pe_arm.sh, under wine).
#
#   axis 1  THE INCLUDE GRAPH. A fork carries the front end when it includes all six TS files
#           (ts/lex, ts/parse, js/emit, ts/driver_flags, ts/driver_input, ts/driver) — a fork
#           with some and not the others is RED by itself (the flags without the modes, or the
#           modes without the front end). The forks `_target_cc_has_js()` names must be exactly
#           the HOST forks (the ones `_self_host_src()` can name) that carry it.
#   axis 2  cbt ASKS, before it forks, and derives the answer from `_self_host_src()` with no
#           `#ifdef` ladder of its own.
#   axis 3  EVALUATES `_self_host_src()` and `_target_cc_has_js()` under each host's macro set
#           (the predicate's ARM ORDER decides the answer, and no grep can see an ordering
#           mistake); each host's answer must be whether ITS fork carries the front end.
#   axis 4  the CLI turns a real .ts into real JS on x86-64 Linux (the positive control) AND as
#           an aarch64-Linux CLI under qemu exec'ing an aarch64 native cycc — the same bytes.
#   axis 5  (6.7.16, issues/2026-10-18-cmdline-read-cuts-ts-path-at-255-bytes.md) every driver
#           that reads /proc/self/cmdline — cycc, the aarch64 cross, the Linux-hosted Windows
#           cross, the cx compiler and the aarch64 native compiler (qemu) — reads it WHOLE. They
#           read 255 bytes once: a TS path past byte 255 was cut and the cut name opened, a flag
#           past it dropped. 5a the filed repro, `--emit-js <a 290-odd-byte directory>/a.ts`,
#           prints `let x = 1;` (not cx: no TS front end); 5b `<300-byte arg> --version` prints
#           the version; 5c a command line of exactly 2,097,151 bytes, --version last, prints it;
#           5d one of exactly 2,097,152 bytes (it fills the 2 MiB mapping) is refused by name; 5e
#           `--emit-js <path>` with the path across byte 2,097,152 is refused by name, the cut path
#           never opened. 5c-5e raise the stack limit (Linux's ARG_MAX follows it).
#
# MUTATION LEDGER (measured at 6.7.15; each a scratch copy of the tree, the gate pointed at it
# with EJR_SRC_DIR / EJR_BUILD_CYR, or the CLI rebuilt from it)
#   N1. src/main_aarch64_native.cyr loses `include "src/frontend/ts/driver.cyr"`
#                                          -> RED (axis 1: 5 of 6 files; axes 3, 4)
#   N2. it loses all six TS includes (the 6.7.14 driver)             -> RED (axes 1, 3, 4)
#   N3. `_target_cc_has_js` back to `src/main.cyr` alone (6.6.6)     -> RED (axes 1, 3, 4)
#   N4. the `_target_cc_has_js()` guard deleted from `_emit_js`      -> RED (axis 2)
#   Real tree -> GREEN.
# Axis 5 (measured at 6.7.16; a scratch copy of the tree with src/common/util.cyr's
# _cmdline_read edited and build/cycc rebuilt from it):
#   C1. one read of 255 bytes (the pre-6.7.16 scan)  -> RED all 23 rows (5a "cannot open '<cut>'")
#   C2. the refusal of a full mapping dropped         -> RED 5d, 5e on every driver (5e x86: the
#                                                       scan ran off the mapping, SIGSEGV)
#   C3. the refusal at n >= 2097151 (one byte early)  -> RED 5c on every driver
#
# ⚠ qemu-aarch64 is an EMULATOR, not hardware. The real-hardware `--emit-js` runs on pi, ecb,
# ach and cass are the cross-OS legs (scripts/cross-os-selfhost.sh) and ts_flags_every_driver.sh.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: emit_js_per_host_fork: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL emit_js_per_host_fork: no build/cycc"; exit 1; }
BUILD_CYR="${EJR_BUILD_CYR:-$R/cbt/build.cyr}"
[ -f "$BUILD_CYR" ] || { echo "FAIL emit_js_per_host_fork: missing $BUILD_CYR"; exit 1; }
SRC_DIR="${EJR_SRC_DIR:-$R/src}"
fail=0

# ── axis 1 — the include graph ───────────────────────────────────────────────────────
TSFILES="src/frontend/ts/lex.cyr src/frontend/ts/parse.cyr src/backend/js/emit.cyr src/frontend/ts/driver_flags.cyr src/frontend/ts/driver_input.cyr src/frontend/ts/driver.cyr"
nforks=$(ls "$SRC_DIR"/main*.cyr 2>/dev/null | wc -l | tr -d ' ' || true)
if [ "${nforks:-0}" -lt 7 ]; then
  echo "FAIL axis1: expected >= 7 per-target forks, found ${nforks:-0}"
  fail=1
fi
: > "$D/carries"
for f in "$SRC_DIR"/main*.cyr; do
  rel="src/$(basename "$f")"
  have=0
  for t in $TSFILES; do
    if grep -q "^include \"$t\"" "$f"; then have=$((have + 1)); fi
  done
  if [ "$have" -eq 6 ]; then
    echo "$rel" >> "$D/carries"
  elif [ "$have" -ne 0 ]; then
    echo "FAIL axis1: $rel includes $have of the 6 TS driver files — the front end, the JS emitter"
    echo "            and the three driver files go together (flags with no modes, or modes with no"
    echo "            front end, is a compiler that accepts --parse-ts and cannot run it)"
    fail=1
  fi
done
sort -u "$D/carries" -o "$D/carries"
# The host forks: every fork name `_self_host_src*` can return.
awk '/^fn _self_host_src(_macos)?\(\): i64 \{/,/^\}/' "$BUILD_CYR" \
  | grep -o '"src/main[a-z0-9_]*\.cyr"' | tr -d '"' | sort -u > "$D/hosts"
nh=$(grep -c . "$D/hosts" || true)
if [ "${nh:-0}" -lt 5 ]; then
  echo "FAIL axis1: _self_host_src names ${nh:-0} host forks (want >= 5) — did it change shape?"
  fail=1
fi
comm -12 "$D/hosts" "$D/carries" > "$D/want_js"
awk '/^fn _target_cc_has_js\(\): i64 \{/,/^\}/' "$BUILD_CYR" \
  | grep -o '"src/main[a-z0-9_]*\.cyr"' | tr -d '"' | sort -u > "$D/pred_js"
if ! cmp -s "$D/want_js" "$D/pred_js"; then
  echo "FAIL axis1: _target_cc_has_js() names '$(tr '\n' ' ' < "$D/pred_js")' but the host forks"
  echo "            carrying the TS front end are '$(tr '\n' ' ' < "$D/want_js")' — update it with"
  echo "            the include graph"
  fail=1
fi
if [ "$(grep -c . "$D/want_js" || true)" -lt 5 ]; then
  echo "FAIL axis1: only $(grep -c . "$D/want_js" || true) host forks carry the TS front end (6.7.15's D38: all five)"
  fail=1
fi

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

# ── axis 3 — EVALUATE the mapping and the predicate under each host's macro set ──────
awk '/^fn _self_host_src_macos\(\): i64 \{/,/^\}/' "$BUILD_CYR"  > "$D/fns.cyr"
awk '/^fn _self_host_src\(\): i64 \{/,/^\}/'       "$BUILD_CYR" >> "$D/fns.cyr"
awk '/^fn _target_cc_has_js\(\): i64 \{/,/^\}/'    "$BUILD_CYR" >> "$D/fns.cyr"
nfn=$(grep -c '^fn ' "$D/fns.cyr" || true)
if [ "${nfn:-0}" -lt 3 ]; then
  echo "FAIL axis3: extraction is vacuous ($nfn fns) — the mapping fns moved or changed shape"
  echo "FAIL emit_js_per_host_fork"
  exit 1
fi
# label:macros
ROWS='linux-x86:
linux-aarch64:CYRIUS_ARCH_AARCH64
macos-arm64:CYRIUS_TARGET_MACOS CYRIUS_ARCH_AARCH64
macos-x86:CYRIUS_TARGET_MACOS
windows:CYRIUS_TARGET_WIN'
: > "$D/a3"
printf '%s\n' "$ROWS" | while IFS= read -r row; do
  [ -n "$row" ] || continue
  lab=$(printf '%s' "$row" | cut -d: -f1)
  defs=$(printf '%s' "$row" | cut -d: -f2)
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
var _fk = _self_host_src();
var _n = 0;
while (load8(_fk + _n) != 0) { _n = _n + 1; }
syscall(1, 1, _fk, _n);
var _r = _target_cc_has_js();
syscall(60, _r);
PROBE
  if ! cat "$P" | "$CC" > "$D/jb_$lab" 2>"$D/je_$lab"; then
    echo "  axis3 $lab: PROBE FAILED TO COMPILE"; sed 's/^/    /' "$D/je_$lab"
    echo "$lab BADCOMPILE -" >> "$D/a3"; continue
  fi
  [ -s "$D/jb_$lab" ] || { echo "  axis3 $lab: probe binary is EMPTY"; echo "$lab BADEMPTY -" >> "$D/a3"; continue; }
  chmod +x "$D/jb_$lab"
  got=0; ( ulimit -c 0; "$D/jb_$lab" > "$D/jo_$lab" ) || got=$?
  echo "$lab $got $(cat "$D/jo_$lab")" >> "$D/a3"
done
n3=$(grep -c . "$D/a3" 2>/dev/null || true); [ -n "$n3" ] || n3=0
if [ "$n3" -ne 5 ]; then
  echo "FAIL axis3: expected 5 evaluated rows, got $n3"
  fail=1
fi
while read -r lab got fk; do
  want=0
  if grep -qxF "$fk" "$D/carries"; then want=1; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL axis3: $lab — its fork is '$fk' and _target_cc_has_js() answered '$got', expected $want"
    echo "            (1 = the fork includes the TS front end, axis 1's include graph)"
    fail=1
  fi
done < "$D/a3"

# ── axis 4 — the CLI emits the JS: x86-64 Linux, and the aarch64-Linux CLI under qemu ────
printf 'export const x: number = 1;\nexport function f(a: number): number { return a + 1; }\n' > "$D/t.ts"
cat cbt/cyrius.cyr | "$CC" > "$D/cli_x86" 2>"$D/cli_x86.err" || true
if [ ! -s "$D/cli_x86" ]; then
  echo "FAIL axis4: could not build the x86-64 Linux CLI"; sed 's/^/    /' "$D/cli_x86.err"
  fail=1
else
  chmod +x "$D/cli_x86"
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
if ! command -v qemu-aarch64 >/dev/null 2>&1; then
  echo "  axis4: SKIP the aarch64 CLI — qemu-aarch64 not installed."
  GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
else
  cat src/main_aarch64.cyr | "$CC" > "$D/cc_a64" 2>"$D/cc_a64.err"
  if [ ! -s "$D/cc_a64" ]; then
    echo "FAIL axis4: could not build the aarch64-emitting cross compiler"; sed 's/^/    /' "$D/cc_a64.err"
    fail=1
  else
    chmod +x "$D/cc_a64"
    # An aarch64 install layout: bin/cyrius and, beside it, bin/cycc — the native aarch64 fork,
    # run through qemu by a one-line wrapper (no binfmt here: a guest execve of an aarch64 ELF
    # fails, a shell script is run by the host). The CLI prefers the cycc beside it.
    mkdir -p "$D/a64/bin" "$D/a64/w"
    cat cbt/cyrius.cyr | "$D/cc_a64" > "$D/a64/bin/cyrius" 2>"$D/cli_a64.err" || true
    cat src/main_aarch64_native.cyr | "$D/cc_a64" > "$D/a64/nat" 2>"$D/nat.err" || true
    if [ ! -s "$D/a64/bin/cyrius" ] || [ ! -s "$D/a64/nat" ]; then
      echo "FAIL axis4: could not build the aarch64 CLI / native compiler"; sed 's/^/    /' "$D/cli_a64.err" "$D/nat.err"
      fail=1
    else
      chmod +x "$D/a64/bin/cyrius" "$D/a64/nat"
      printf '#!/bin/sh\nexec qemu-aarch64 "%s" "$@"\n' "$D/a64/nat" > "$D/a64/bin/cycc"
      chmod +x "$D/a64/bin/cycc"
      cp "$D/t.ts" "$D/a64/w/t.ts"
      # stdin from /dev/null and a timeout: a compiler without the front end ignores --emit-js
      # and reads its stdin as the source, which would block the gate on a terminal.
      arc=0; ( cd "$D/a64/w" && ulimit -c 0; CYRIUS_RESOLVED=1 CYRIUS_HOME="$D/a64/home" timeout 300 qemu-aarch64 "$D/a64/bin/cyrius" build --target=js t.ts a.js >"$D/a64.out" 2>&1 < /dev/null ) || arc=$?
      if [ "$arc" -ne 0 ] || [ ! -s "$D/a64/w/a.js" ]; then
        echo "FAIL axis4: the aarch64 CLI's --target=js exited $arc / produced no JS"
        sed 's/^/    /' "$D/a64.out"
        fail=1
      elif ! cmp -s "$D/ok.js" "$D/a64/w/a.js"; then
        echo "FAIL axis4: the aarch64 CLI's JS differs from x86-64 Linux's"
        diff "$D/ok.js" "$D/a64/w/a.js" | head -5 | sed 's/^/    /'
        fail=1
      elif ! grep -qE '^emit-js t\.ts -> a\.js \[js\] OK$' "$D/a64.out"; then
        echo "FAIL axis4: the aarch64 CLI did not report the emit on its header line"
        sed 's/^/    /' "$D/a64.out"
        fail=1
      fi
    fi
  fi
fi

# ── axis 5 — the WHOLE command line, on every /proc driver (6.7.16) ──────────────────
# Each driver that reads its flags from /proc/self/cmdline read 255 bytes once, so a TS path
# that ended past byte 255 was cut and the cut name opened ("cannot open '<prefix>'" for a file
# that exists), and a flag past it was dropped (`cycc <300-byte arg> --version` compiled its
# empty stdin and wrote a binary). They now read it whole (_cmdline_read, src/common/util.cyr)
# into a 2 MiB mapping, and a line that fills it is refused by name.
X5="$D/x5"
mkdir -p "$X5"
VER=$(cat VERSION 2>/dev/null || true)
LD="$X5/longpath/$(printf 'd%.0s' $(seq 1 120))/$(printf 'e%.0s' $(seq 1 120))"
mkdir -p "$LD" && printf 'let x: number = 1;\n' > "$LD/a.ts"
cp "$CC" "$X5/x86"
DRV5="x86"
for b5 in "a64x|src/main_aarch64.cyr" "winx|src/main_win.cyr" "cx|src/main_cx.cyr"; do
  l5=${b5%%|*}
  if cat "${b5#*|}" | "$CC" > "$X5/$l5" 2> "$X5/$l5.err" && [ -s "$X5/$l5" ]; then
    chmod +x "$X5/$l5"; DRV5="$DRV5 $l5"
  else
    echo "FAIL axis5: could not build $l5 from ${b5#*|}"; sed -n 1,5p "$X5/$l5.err" | sed 's/^/    /'; fail=1
  fi
done
if ! command -v qemu-aarch64 >/dev/null 2>&1; then
  echo "  axis5: SKIP the aarch64 native compiler's rows — qemu-aarch64 not installed."
  GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
elif [ -x "$X5/a64x" ] && cat src/main_aarch64_native.cyr | "$X5/a64x" > "$X5/a64n" 2> "$X5/a64n.err" && [ -s "$X5/a64n" ]; then
  chmod +x "$X5/a64n"; DRV5="$DRV5 a64n"
else
  echo "FAIL axis5: could not build the aarch64 native compiler"; sed -n 1,5p "$X5/a64n.err" | sed 's/^/    /'; fail=1
fi
# run5 LABEL ARGS... — one driver (a64n through qemu), stdin empty; stdout $X5/o, stderr $X5/e,
# exit status rc5. The stack limit is raised for the 2 MiB rows (Linux's ARG_MAX follows it).
run5() {
  _l=$1; shift
  rc5=0
  if [ "$_l" = a64n ]; then
    ( ulimit -c 0; ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -Hs)" 2>/dev/null; qemu-aarch64 "$X5/$_l" "$@" > "$X5/o" 2> "$X5/e" < /dev/null ) || rc5=$?
  else
    ( ulimit -c 0; ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -Hs)" 2>/dev/null; "$X5/$_l" "$@" > "$X5/o" 2> "$X5/e" < /dev/null ) || rc5=$?
  fi
}
n5=0
red5() { echo "FAIL axis5 $1: $2"; echo "    rc $rc5; stdout: $(head -c 80 "$X5/o" | tr -c '[:print:]' '.'); stderr: $(head -c 160 "$X5/e")"; fail=1; }
is_ver5() { [ "$rc5" = 0 ] && [ "$(head -1 "$X5/o" | awk '{print $2}')" = "$VER" ] && head -1 "$X5/o" | grep -q '^cycc'; }
REFUSE5='the command line is longer than 2097151 bytes'
is_refused5() { [ "$rc5" = 1 ] && [ ! -s "$X5/o" ] && grep -qF "$REFUSE5" "$X5/e" && ! grep -q 'cannot open' "$X5/e"; }
# 5a — the filed repro: `--emit-js <a 290-odd-byte path>` prints `let x = 1;` (not cx: it has no
# TS front end).
for l5 in $DRV5; do
  [ "$l5" = cx ] && continue
  n5=$((n5 + 1)); run5 "$l5" --emit-js "$LD/a.ts"
  if [ "$rc5" != 0 ] || [ "$(cat "$X5/o")" != 'let x = 1;' ]; then red5 "5a $l5" "--emit-js of a ${#LD}-byte directory's a.ts did not print 'let x = 1;' and exit 0"; fi
done
# 5b — a --version after a 300-byte argument prints the version.
L300=$(printf 'z%.0s' $(seq 1 300))
for l5 in $DRV5; do
  n5=$((n5 + 1)); run5 "$l5" "$L300" --version
  is_ver5 || red5 "5b $l5" "--version after a 300-byte argument did not print 'cycc… $VER'"
done
# 5c-5e — the 2 MiB mapping's edge, with command lines of an exact size (each argument + its
# NUL; argv[0] is the driver's path, under qemu the guest's). They need an ARG_MAX past 2 MiB.
am5=$( (ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -Hs)" 2>/dev/null; getconf ARG_MAX) 2>/dev/null || true)
case $am5 in ''|*[!0-9]*) am5=0 ;; esac
Q5=$(head -c 131000 /dev/zero | tr '\0' q)
if [ "$am5" -lt 2400000 ]; then
  echo "  axis5: SKIP 5c-5e — the stack limit cannot be raised for a 2 MiB command line (ARG_MAX $am5; hard limit $(ulimit -Hs))"
  GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
else
  p5="$LD/a.ts"
  for l5 in $DRV5; do
    a0=$((${#X5} + 1 + ${#l5}))
    for k5 in c d e; do
      if [ "$k5" = e ] && [ "$l5" = cx ]; then continue; fi
      # The fillers take r5 bytes: argv[0] and its NUL, then the trailing arguments, make the rest.
      case $k5 in
        c) r5=$((2097151 - (a0 + 1) - 10)) ;;
        d) r5=$((2097152 - (a0 + 1) - 10)) ;;
        e) r5=$((2097252 - (a0 + 1) - 10 - (${#p5} + 1))) ;;
      esac
      set --
      while [ "$r5" -gt 131003 ]; do set -- "$@" "$Q5"; r5=$((r5 - 131001)); done
      set -- "$@" "$(head -c $((r5 - 1)) /dev/zero | tr '\0' q)"
      n5=$((n5 + 1))
      case $k5 in
        # 5c — exactly 2,097,151 bytes, --version last: read whole, the version printed.
        c) run5 "$l5" "$@" --version
           is_ver5 || red5 "5c $l5" "a command line of exactly 2097151 bytes with --version last did not print the version" ;;
        # 5d — exactly 2,097,152 bytes: it fills the mapping, so it is refused by name.
        d) run5 "$l5" "$@" --version
           is_refused5 || red5 "5d $l5" "a command line of exactly 2097152 bytes was not refused by name ('$REFUSE5')" ;;
        # 5e — `--emit-js <path>` with the path across byte 2,097,152: refused by name, the cut
        # path never opened (not cx: it has no TS front end).
        e) run5 "$l5" "$@" --emit-js "$p5"
           is_refused5 || red5 "5e $l5" "--emit-js with its path across byte 2097152 was not refused by name (or a cut path was opened)" ;;
      esac
    done
  done
  set --
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL emit_js_per_host_fork"
  exit 1
fi
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: emit_js_per_host_fork — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS emit_js_per_host_fork: $(grep -c . "$D/want_js") host forks carry the TS front end, _target_cc_has_js() names them; 5 hosts evaluated; x86-64 Linux and the aarch64 CLI (qemu, not hardware) emit the same JS; axis 5: $n5 rows on $DRV5 — the whole command line read (a TS path past byte 255, a --version after a 300-byte argument, 2097151 bytes), 2097152 refused by name"
exit 0
