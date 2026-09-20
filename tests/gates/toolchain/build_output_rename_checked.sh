#!/bin/sh
# build_output_rename_checked.sh — v6.6.6 (bite 24a).
#
# cbt's atomic tmp-then-rename finalization goes through the PORTABLE NAMED WRAPPER
# `file_rename` (lib/io.cyr), and its RESULT IS CHECKED — a rename that fails is a
# FAILED build, not a successful one.
#
# ⛔ WHAT IT DID BEFORE. Three sites in cbt/build.cyr (`_emit_js`, `_emit_cx`, `compile`)
# finalized with a RAW `syscall(82, tmp_out, output)` — the x86-64 Linux SYS_RENAME
# number spelled out in arch-neutral CLI code — and DISCARDED its return value. Measured
# at 55d7819 on x86-64 Linux, with `out` an existing DIRECTORY:
#   $ cyrius build --target=js t.ts out.js       # out.js/ is a directory
#   emit-js t.ts -> out.js [js] OK               (exit 0)
#   $ ls -ld out.js -> drw-r--r--                (the chmod landed on the DIRECTORY:
#                                                 0755 -> 0644, no longer traversable)
#   $ ls out.js.tmp.737213                       (the temp left behind)
#   $ cyrius build a.cyr bin.d                   # bin.d/ is a directory
#   compile a.cyr -> bin.d [x86_64] OK           (exit 0, NO binary anywhere)
# Exit 0 with no artifact is the worst possible answer for a build tool: a script that
# checks `$?` proceeds, and a CI step "succeeds" having produced nothing.
#
# ⭐ WHY THE EXISTING RAW-LITERAL GATE DID NOT CATCH IT, and why this one is separate.
# `tests/gates/platform/raw_syscall_literals_routed.sh` DOES scan cbt/ (widened to the
# whole tree at 6.6.5) — it passed because its question is "is this number routed on
# ELF-aarch64", and 82 IS: ESYSXLAT carries an 82 -> renameat(38) row with the AT_FDCWD
# arg-shift, added at v6.0.68 for THIS VERY CALL SITE. That gate's claim is one axis,
# correctly scoped; the defect here is a different one (an unchecked result, and a raw
# number where a portable wrapper exists), so it gets its own gate rather than a widening
# that would make the other gate claim more than it measures.
#
# ⭐ AXIS 3/4 ARE THE LOAD-BEARING ONES — the structural axes 1/2 would both pass a fix
# that swapped in `file_rename` and still threw the result away.
#
# ⭐ AXIS 5 (POSITIVE CONTROL) IS LOAD-BEARING TOO: "fail every rename" satisfies axes
# 3 and 4 and would be a far worse bug, so both verbs must still succeed normally in the
# same run.
#
# MUTATION LEDGER (measured; each mutant a `git archive HEAD cbt lib build tests/gates/
# toolchain src/version_str.cyr` copy with the one file overlaid, gate re-run against it)
#   M1. all three sites reverted to `syscall(82, tmp_out, output);` (the HEAD shape)
#       -> RED: axis 1 names both sites, axis 2 goes VACUOUS (5 file_rename sites, < 6),
#          a3 and a4 both report `exit 0` for a build that produced nothing
#   M2. `file_rename(…)` called but its result DISCARDED (the half-fix)
#       -> RED: axis 2 names all three lines, a3 + a4 still report exit 0. Axis 1 is
#          GREEN here — which is exactly why axis 2 exists.
#   M3. the `compile()` site alone reverted (one of three)
#       -> RED: axis 1, a3; a4 then trips on the temp a3 left behind
#   M4. `file_rename` made to `return 1` unconditionally
#       -> RED: axis 5 ONLY. Axes 1-4 all stay GREEN, which is why the positive
#          control is in the same run.
#   Real tree -> GREEN (9 cbt files, 8 file_rename sites, all checked).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: build_output_rename_checked: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL build_output_rename_checked: no build/cycc"; exit 1; }
fail=0

# ── axis 1 — no cbt/ site spells the rename syscall by NUMBER ────────────────────────
# The number is DERIVED from the stdlib peers, not typed here, and derived TWICE from
# independent files: the x86-64 Linux peer and the macOS peer both declare SYS_RENAME and
# must agree (they do — Darwin inherited the BSD number Linux also uses).
N_LIN=$(sed -n 's/^[ \t]*SYS_RENAME[ \t]*=[ \t]*\([0-9]\+\);.*/\1/p' lib/syscalls_x86_64_linux.cyr | head -1)
N_MAC=$(sed -n 's/^[ \t]*SYS_RENAME[ \t]*=[ \t]*\([0-9]\+\);.*/\1/p' lib/syscalls_macos.cyr | head -1)
if [ -z "${N_LIN:-}" ] || [ -z "${N_MAC:-}" ]; then
  echo "FAIL axis1: could not derive SYS_RENAME from the stdlib peers (lin='${N_LIN:-}' mac='${N_MAC:-}')"
  echo "FAIL build_output_rename_checked"; exit 1
fi
if [ "$N_LIN" != "$N_MAC" ]; then
  echo "FAIL axis1: the two peers disagree on SYS_RENAME ($N_LIN vs $N_MAC) — re-derive this axis"
  fail=1
fi
nfiles=$(ls cbt/*.cyr 2>/dev/null | wc -l | tr -d ' ')
if [ "${nfiles:-0}" -lt 8 ]; then
  echo "FAIL axis1: scanned only ${nfiles:-0} cbt/*.cyr files (want >= 8) — the scan matched nothing"
  fail=1
fi
# Comments are dropped before matching — this gate's own fix carries the old spelling in
# a WHY-comment, and a scan that cannot tell a comment from a call would report itself.
# `nraw` is the anti-vacuous control: cbt/ has many legitimate raw syscalls, so a scan
# that finds NO `syscall(` at all has stopped working rather than found a clean tree.
scan=$(awk -v n="$N_LIN" '{ c=$0; sub(/#.*$/, "", c)
  if (index(c, "syscall(") > 0) { any++ }
  if (index(c, "syscall(" n ",") > 0) { printf "    %s:%d:%s\n", FILENAME, FNR, $0 } }
  END { printf "ANY=%d\n", any }' cbt/*.cyr)
nraw=$(printf '%s\n' "$scan" | sed -n 's/^ANY=\([0-9]*\)$/\1/p')
raw=$(printf '%s\n' "$scan" | grep -v '^ANY=' || true)
if [ "${nraw:-0}" -lt 10 ]; then
  echo "FAIL axis1: the cbt/ syscall scan found only ${nraw:-0} raw syscall sites (want >= 10) — it is not scanning"
  fail=1
fi
if [ -n "$raw" ]; then
  echo "FAIL axis1: cbt/ still spells rename as a raw syscall($N_LIN, …). Call file_rename (lib/io.cyr)."
  printf '%s\n' "$raw"
  fail=1
fi

# ── axis 2 — every file_rename() call in cbt/ CONSUMES its result ────────────────────
# A call whose line neither tests it (`if (file_rename`) nor binds it (`= file_rename`)
# is the exact half-fix M2: portable, still silently ignored.
sites=$(grep -n 'file_rename(' cbt/*.cyr | grep -v '^\s*#' | grep -v ':[0-9]*:[ \t]*#' || true)
nsites=$(printf '%s\n' "$sites" | grep -c . || true); [ -n "$nsites" ] || nsites=0
if [ "$nsites" -lt 6 ]; then
  echo "FAIL axis2: found only $nsites file_rename() sites in cbt/ (want >= 6) — extraction is vacuous"
  fail=1
fi
unchecked=$(printf '%s\n' "$sites" | grep -v 'if (file_rename(' | grep -v '= *file_rename(' || true)
if [ -n "$unchecked" ]; then
  echo "FAIL axis2: file_rename() result discarded — a failed rename is a FAILED build:"
  printf '%s\n' "$unchecked" | sed 's/^/    /'
  fail=1
fi

# ── build the CLI under test once, from THIS tree ────────────────────────────────────
cat cbt/cyrius.cyr | "$CC" > "$D/cli" 2>"$D/cli.err" || true
if [ ! -s "$D/cli" ]; then
  echo "FAIL: could not build the CLI from cbt/cyrius.cyr"; sed 's/^/    /' "$D/cli.err"
  echo "FAIL build_output_rename_checked"; exit 1
fi
chmod +x "$D/cli"
W="$D/w"; mkdir -p "$W"
printf 'fn main(): i64 { return 0; }\n' > "$W/a.cyr"
printf 'export const x: number = 1;\nexport function f(a: number): number { return a + 1; }\n' > "$W/t.ts"

# A rename onto an existing DIRECTORY fails with EISDIR/ENOTDIR on every POSIX host, and
# needs no permissions games (which behave differently under root in a container).
# The expected outcome is computed a DIFFERENT way from the CLI's own report: the
# directory must still BE a directory, must still have its original mode, and no temp
# sibling may survive — none of which the CLI prints.
check_fail_path() {   # $1 label, $2 blocking dir path, then the CLI argv
  lab=$1; dir=$2; shift 2
  rm -rf "$dir"; mkdir -p "$dir"
  mode_before=$(ls -ld "$dir" | cut -c1-10)
  rc=0; ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" "$@" >"$D/$lab.out" 2>&1 ) || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL $lab: the CLI reported SUCCESS (exit 0) for a build whose rename could not happen"
    sed 's/^/    /' "$D/$lab.out"
    return 1
  fi
  if ! grep -qi 'rename' "$D/$lab.out"; then
    echo "FAIL $lab: the failure does not NAME the rename that could not happen"
    sed 's/^/    /' "$D/$lab.out"
    return 1
  fi
  if ! grep -q "$(basename "$dir")" "$D/$lab.out"; then
    echo "FAIL $lab: the failure does not name the output path"
    sed 's/^/    /' "$D/$lab.out"
    return 1
  fi
  if [ ! -d "$dir" ]; then
    echo "FAIL $lab: the blocking directory is gone — the failed path destroyed the destination"
    return 1
  fi
  mode_after=$(ls -ld "$dir" | cut -c1-10)
  if [ "$mode_before" != "$mode_after" ]; then
    echo "FAIL $lab: the destination's mode changed ($mode_before -> $mode_after) — the chmod ran on a rename that never happened"
    return 1
  fi
  leftover=$(find "$W" -maxdepth 1 -name '*.tmp.*' 2>/dev/null | head -3)
  if [ -n "$leftover" ]; then
    echo "FAIL $lab: the temp output was left behind after the failure:"
    printf '%s\n' "$leftover" | sed 's/^/    /'
    return 1
  fi
  return 0
}

# ── axis 3 — the native compile path reports the failure ─────────────────────────────
check_fail_path a3 "$W/bin.d" build a.cyr bin.d || fail=1

# ── axis 4 — the --target=js path reports it too (the same fix, a different fn) ───────
check_fail_path a4 "$W/out.js" build --target=js t.ts out.js || fail=1

# ── axis 5 — POSITIVE CONTROL: both verbs still succeed on a normal path ─────────────
rc=0; ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" build a.cyr good.bin >"$D/a5n.out" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$W/good.bin" ]; then
  echo "FAIL axis5 (positive control): a normal native build exited $rc / produced no binary"
  sed 's/^/    /' "$D/a5n.out"; fail=1
else
  brc=0; ( ulimit -c 0; "$W/good.bin" ) || brc=$?
  [ "$brc" -eq 0 ] || { echo "FAIL axis5: the built binary exited $brc, expected 0"; fail=1; }
fi
rc=0; ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" build --target=js t.ts good.js >"$D/a5j.out" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$W/good.js" ]; then
  echo "FAIL axis5 (positive control): a normal --target=js build exited $rc / produced no JS"
  sed 's/^/    /' "$D/a5j.out"; fail=1
elif ! grep -q 'export function f(a) {' "$W/good.js"; then
  echo "FAIL axis5 (positive control): the emitted file is not the expected JS"
  head -5 "$W/good.js" | sed 's/^/    /'; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL build_output_rename_checked"
  exit 1
fi
echo "PASS build_output_rename_checked: no raw syscall($N_LIN) in $nfiles cbt files; $nsites file_rename sites all checked; native + js failures named and non-zero; both verbs still succeed"
exit 0
