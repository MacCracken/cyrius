#!/bin/sh
# Gate: `cyrius soak` says what a failed self-host step DID — never a status it did not return
# (6.6.11, K7).
#
# THE DEFECT. 6.6.9 bite 10 routed `cyrius self`'s step failures through `_raw_fail_describe`,
# and left cmd_soak's two copies of the message printing the raw `_self_host_step` return:
# `FAIL: self-host step N exited ` + fmt_int(sN). That return is not an exit code —
# `_pulsar_raw_compile` answers a flat 1 for a signal, an empty output and a failed rename, and
# `_self_host_step_macos` answers -1 after naming its own failure. Measured at 6.6.10 on a
# scratch checkout whose src/main.cyr compiles to a program that segfaults: soak printed
# `FAIL: self-host step 2 exited 1` while `cyrius self` on the same tree said `killed by signal 11`.
#
# Axes (a scratch checkout; the CLI and the real compiler staged side by side):
#   1. step 2 dies of SIGSEGV: `step 2 was killed by signal 11`, and no `exited` at all.
#   2. step 2 exits 0 and writes nothing: `exited 0 but wrote no output`, never `exited 1`.
#   3. ANTI-VACUOUS: step 2 exits 3 — a real status is still quoted, `step 2 exited 3`.
#   4. source: cmd_soak writes no raw fmt_int of a `_self_host_step` result, and its step-failure
#      line goes through `_raw_fail_describe`.
# Exit 77 when it could not run (no compiler or CLI).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
CY=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CC" ] || { echo "SKIP: cyrius_soak_describes_failures: no compiler at $CC"; exit 77; }
[ -x "$CY" ] || { echo "SKIP: cyrius_soak_describes_failures: no CLI at $CY"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cyrius_soak_describes_failures: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# The CLI resolves cycc beside itself, so this run uses THIS compiler.
mkdir -p "$D/bin" "$D/proj/src"
cp "$CY" "$D/bin/cyrius" && cp "$CC" "$D/bin/cycc" && chmod +x "$D/bin/cyrius" "$D/bin/cycc" \
    || { echo "SKIP: cyrius_soak_describes_failures: could not stage the CLI and compiler"; exit 77; }
soak() {   # soak <src/main.cyr body>
    printf '%s\n' "$1" > "$D/proj/src/main.cyr"
    OUT=$( cd "$D/proj" && ulimit -c 0; CYRIUS_RESOLVED=1 timeout 120 "$D/bin/cyrius" soak 1 2>&1 ); RC=$?
}

# 1 — SIGSEGV in step 2 (step 1 compiles src/main.cyr into a program that stores through NULL).
soak 'var p = 0;
store64(p, 1);'
if [ "$RC" != 0 ] && echo "$OUT" | grep -qF 'FAIL: self-host step 2 was killed by signal 11' && ! echo "$OUT" | grep -q 'exited'; then
    ok "a step 2 killed by SIGSEGV is said as such, no status quoted (rc $RC)"
else bad "SIGSEGV in step 2 not described (want 'self-host step 2 was killed by signal 11', no 'exited'; rc $RC): $OUT"; fi

# 2 — step 2 exits 0 and writes no output.
soak 'var x = 0;'
if [ "$RC" != 0 ] && echo "$OUT" | grep -qF 'FAIL: self-host step 2 exited 0 but wrote no output' && ! echo "$OUT" | grep -q 'exited 1'; then
    ok "an empty step-2 output is said as such (rc $RC)"
else bad "an empty step-2 output not described (want 'exited 0 but wrote no output', no 'exited 1'; rc $RC): $OUT"; fi

# 3 — anti-vacuous: a real exit status is still quoted.
soak 'syscall(60, 3);'
if [ "$RC" != 0 ] && echo "$OUT" | grep -qF 'FAIL: self-host step 2 exited 3'; then
    ok "a real step-2 exit status is quoted (exited 3, rc $RC)"
else bad "step 2's real status (3) not quoted (rc $RC): $OUT"; fi

# 4 — source: no raw status print in cmd_soak; the helper describes.
BODY=$(awk '/^fn cmd_soak\(/{f=1} f&&/^}/{print; exit} f' "$ROOT/cbt/commands.cyr")
[ -n "$BODY" ] || bad "source: cmd_soak not found in cbt/commands.cyr"
if echo "$BODY" | grep -qE 'fmt_int\((s1|s2)\)|self-host step [12] exited'; then
    bad "source: cmd_soak prints a raw _self_host_step status: $(echo "$BODY" | grep -nE 'fmt_int\((s1|s2)\)|self-host step [12] exited' | head -2)"
else ok "source: cmd_soak quotes no raw _self_host_step status"; fi
HELP=$(awk '/^fn _soak_step_failed\(/{f=1} f&&/^}/{print; exit} f' "$ROOT/cbt/commands.cyr")
if echo "$HELP" | grep -q '_raw_fail_describe(' && echo "$BODY" | grep -q '_soak_step_failed(2, s2)'; then
    ok "source: soak's step-failure line goes through _raw_fail_describe"
else bad "source: _soak_step_failed missing, not describing, or not called for step 2"; fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: cyrius_soak_describes_failures — a signal, an empty output and a real status are each said as what they were"
    exit 0
fi
echo "FAIL: cyrius_soak_describes_failures — $fails assertion(s) failed"
exit 1
