#!/bin/sh
# build_progress_line_not_spliced.sh — v6.6.6 (bite 24d).
#
# A NAMED error from `cyrius build` never lands INSIDE the progress header, and the
# success result still lands ON it.
#
# ⛔ WHAT IT DID BEFORE. `cmd_build` writes an unterminated header — `compile a.cyr -> out
# [x86_64] `, `emit-js t.ts -> out.js [js] `, `emit-cx a.cyr -> out.cyx [cx] ` — so that
# `OK` finishes the line. Every verb was then CALLED with that line open, so each one's own
# named diagnostic was spliced into it. Measured at 55d7819 / 0bcdbbc1:
#   emit-cx a.cyr -> out.cyx [cx] error: cycc not found — cannot build the cx compiler
#   FAIL
#   compile a.cyr -> bin.d [x86_64] error: could not rename the temp output onto: bin.d
#   FAILED (compiler exit 1)
# and on aarch64, bite 23b's five-line refusal opened mid-header. The information is all
# there, which is why it survived — but it reads as one corrupted line, and the `FAIL`
# that follows looks like part of the error rather than the verdict.
#
# ⭐ THIS GATE PINS THE PROPERTY, NOT THE MECHANISM. Either remedy is correct: don't open
# the line until the verb is going to run, or close it before the error. (The 6.6.6 fix
# uses both — a pre-flight check for `--target=js` / `--target=cx`, and a `_progress_open`
# flag that `_err`/`_err_ctx` close, which is the only option for errors raised from inside
# `compile()`.) A gate that pinned one of them would pass while the other was broken.
#
# ⭐ THE POSITIVE CONTROL IS THE LOAD-BEARING AXIS. "Always newline after the header" makes
# every negative axis green and throws away the v6.5.50 design in which the result lands on
# the header line — so `OK` and `OK (N bytes)` must still be on the SAME physical line as
# `compile `/`emit-js ` in the same run.
#
# ⚠ ANTI-VACUOUS: each negative axis requires the error to be PRESENT as well as unspliced.
# Otherwise a build that printed nothing at all would pass every one of them.
#
# MUTATION LEDGER (measured; each mutant a `git archive HEAD` copy with cbt/ overlaid, the
# CLIs rebuilt from it, gate re-run against it)
#   M1. the whole bite reverted (both pre-flight checks and `_progress_open` removed)
#       -> RED: axes 1, 2, 3, 4 — every named error back inside its header
#   M2. only the two pre-flight checks removed (the `_progress_open` flag kept)
#       -> GREEN, DELIBERATELY. The flag alone is the OTHER valid remedy: the header is
#          printed and then closed before the refusal. The output is uglier (a dangling
#          `emit-js t.ts -> neg.js [js]` line for a verb that never ran) but the defect —
#          a diagnostic INSIDE the header — is gone. A gate that reddened here would be
#          pinning the mechanism, which is the thing this gate deliberately does not do.
#   M3. only `_progress_close()` neutered (the pre-flight checks kept)
#       -> RED: axes 3 and 4, the errors raised INSIDE `compile()`, which no pre-flight
#          check can cover. Axes 1 and 2 stay GREEN.
#   M4. a bare newline written after each header (the naive "always newline" fix)
#       -> RED: the POSITIVE CONTROL alone. Every negative axis stays GREEN, which is
#          exactly why axis 5 is in the same run.
#          ⚠ The gate's own first M4 made `_progress_close()` unconditional and PASSED —
#          that fn is only ever CALLED from `_err`/`_err_ctx`, so it changes nothing on a
#          successful build. The mutant has to be the naive fix at the WRITE site.
#   Real tree -> GREEN.
#
# ⚠ qemu-aarch64 is an EMULATOR, not hardware; it is only used to reach the aarch64
# refusal, which is a CLI-side decision. Axes 2-5 are native.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: build_progress_line_not_spliced: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL build_progress_line_not_spliced: no build/cycc"; exit 1; }
fail=0

cat cbt/cyrius.cyr | "$CC" > "$D/cli" 2>"$D/cli.err" || true
if [ ! -s "$D/cli" ]; then
  echo "FAIL: could not build the CLI from cbt/cyrius.cyr"; sed 's/^/    /' "$D/cli.err"
  echo "FAIL build_progress_line_not_spliced"; exit 1
fi
chmod +x "$D/cli"

W="$D/w"; mkdir -p "$W" "$D/emptyhome"
printf 'fn main(): i64 { return 0; }\n' > "$W/a.cyr"
printf 'export const x: number = 1;\nexport function f(a: number): number { return a + 1; }\n' > "$W/t.ts"

# A spliced line is one that BEGINS with a progress header and also carries an `error:`.
# The header verbs are read off cmd_build rather than typed here, so a renamed verb makes
# this vacuous-loud instead of silently unchecked.
VERBS=$(sed -n 's/^[ \t]*sys_write(STDOUT_FD, "\(compile\|emit-js\|emit-cx\) ", [0-9]*);.*/\1/p' cbt/commands.cyr | sort -u | tr '\n' '|' | sed 's/|$//')
if [ -z "$VERBS" ] || [ "$(printf '%s' "$VERBS" | tr '|' '\n' | grep -c .)" -lt 3 ]; then
  echo "FAIL: could not derive the three progress verbs from cbt/commands.cyr (got '$VERBS')"
  echo "FAIL build_progress_line_not_spliced"; exit 1
fi

check_unspliced() {   # $1 = label, $2 = output file
  lab=$1; f=$2
  if ! grep -q 'error:' "$f"; then
    echo "FAIL $lab: no 'error:' in the output at all — the axis is vacuous, not passing"
    sed 's/^/    /' "$f"; return 1
  fi
  sp=$(grep -nE "^($VERBS) .*error:" "$f" || true)
  if [ -n "$sp" ]; then
    echo "FAIL $lab: a named error is spliced INTO the progress header:"
    printf '%s\n' "$sp" | sed 's/^/    /'
    return 1
  fi
  return 0
}

# ── axis 1 — the aarch64 --target=js refusal (bite 23b's five lines) ─────────────────
if command -v qemu-aarch64 >/dev/null 2>&1; then
  cat src/main_aarch64.cyr | "$CC" > "$D/cc_a64" 2>"$D/cc_a64.err"
  if [ ! -s "$D/cc_a64" ]; then
    echo "FAIL axis1: could not build the aarch64-emitting cross compiler"; sed 's/^/    /' "$D/cc_a64.err"; fail=1
  else
    chmod +x "$D/cc_a64"
    cat cbt/cyrius.cyr | "$D/cc_a64" > "$D/cli_a64" 2>"$D/cli_a64.err" || true
    if [ ! -s "$D/cli_a64" ]; then
      echo "FAIL axis1: could not build the aarch64 CLI"; sed 's/^/    /' "$D/cli_a64.err"; fail=1
    else
      chmod +x "$D/cli_a64"
      ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 qemu-aarch64 "$D/cli_a64" build --target=js t.ts neg.js >"$D/a1.out" 2>&1 ) || true
      check_unspliced axis1 "$D/a1.out" || fail=1
    fi
  fi
else
  echo "  SKIP axis 1 — qemu-aarch64 not installed (the aarch64 --target=js refusal)."
fi

# ── axis 2 — the cx arm's own named failure ──────────────────────────────────────────
# A throwaway CYRIUS_HOME with no tools dir makes `_ensure_cc_cx` fail by name. Nothing
# under the real ~/.cyrius is read or written.
( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 CYRIUS_HOME="$D/emptyhome" "$D/cli" build --target=cx a.cyr out.cyx >"$D/a2.out" 2>&1 ) || true
check_unspliced axis2 "$D/a2.out" || fail=1

# ── axis 3 — an error raised INSIDE compile(): the rename that cannot happen ──────────
rm -rf "$W/bin.d"; mkdir -p "$W/bin.d"
( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" build a.cyr bin.d >"$D/a3.out" 2>&1 ) || true
check_unspliced axis3 "$D/a3.out" || fail=1

# ── axis 4 — a second error raised inside compile(): a missing output directory ───────
( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" build a.cyr "$D/absent/deeper/out" >"$D/a4.out" 2>&1 ) || true
check_unspliced axis4 "$D/a4.out" || fail=1

# ── axis 5 — POSITIVE CONTROL: the result still lands ON the header line ─────────────
rc=0; ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" build a.cyr ok.bin >"$D/a5n.out" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL axis5 (positive control): a normal native build exited $rc"
  sed 's/^/    /' "$D/a5n.out"; fail=1
elif ! grep -qE '^compile .* OK( \([0-9]+ bytes\))?$' "$D/a5n.out"; then
  echo "FAIL axis5 (positive control): the result is no longer on the header line — the"
  echo "            v6.5.50 single-line build report was thrown away to unsplice the errors"
  sed 's/^/    /' "$D/a5n.out"; fail=1
fi
rc=0; ( cd "$W" || exit 1; ulimit -c 0; CYRIUS_RESOLVED=1 "$D/cli" build --target=js t.ts ok.js >"$D/a5j.out" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$W/ok.js" ]; then
  echo "FAIL axis5 (positive control): a normal --target=js build exited $rc / produced no JS"
  sed 's/^/    /' "$D/a5j.out"; fail=1
elif ! grep -qE '^emit-js .* OK$' "$D/a5j.out"; then
  echo "FAIL axis5 (positive control): the emit-js result is no longer on the header line"
  sed 's/^/    /' "$D/a5j.out"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL build_progress_line_not_spliced"
  exit 1
fi
echo "PASS build_progress_line_not_spliced: 4 named-failure paths, none spliced into the '$VERBS' header; native + js results still land ON the header line"
exit 0
