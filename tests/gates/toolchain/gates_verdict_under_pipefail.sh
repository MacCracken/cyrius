#!/bin/sh
# tests/gates/toolchain/gates_verdict_under_pipefail.sh — 6.7.15. The gates filed for stopping
# WITHOUT A VERDICT under `bash -eo pipefail` reach their verdict there.
#
# THE DEFECT. check.sh and the driver run every shell gate with `sh` (no pipefail, and several
# gates have no `set -e`), where they pass. GitHub's `run:` shell is `bash -eo pipefail`, and
# CLAUDE.md asks every shell gate to be tested under it — and there these gates ended early with
# a non-zero rc and neither PASS nor FAIL:
#   * syscall_xlat_generated.sh — `fp=$(grep -c 'raw syscall' …)`: grep -c prints 0 AND exits 1
#     on the PASSING case, so `-e` ended the gate on axis 2 (rc 1);
#   * removed_symbol_census.sh — `git tag … | head -1`: head exits after one line, git dies of
#     SIGPIPE, pipefail makes the assignment fail (rc 141); behind it, the census helper's
#     `… | head -400` and its loop's last-file miss did the same to `HITS=$(…)` / `PROBE=$(…)`;
#   * stdlib_modules_self_sufficient.sh — `( … ./p_io … ); prc=$?`: axis 5's probes exit
#     NON-ZERO on success (io exits 42), so `-e` ended the gate on the first passing probe with
#     its rc (42); behind it, axis 6's zero-warning `u=$(grep … | …)` and axis 7's out-of-scope
#     compiles and cxvm runs, which all fail by design;
#   * io_rdwr_agnos.sh (6.7.16) — `"$TMP/rw_lin" …; el=$?`: the probe exits 42 when it passes,
#     so `-e` ended the gate on the first passing probe with rc 42;
#   * gates_read_only_the_tree.sh (6.7.16) — new, written pipefail-safe, and listed so it stays so;
#   * scripts/agnos-crossbuild-gate.sh (6.7.16) — not a stop but a FALSE verdict: `echo "$sdis" |
#     grep -q 'mov +eax,0x38\b' || FAIL` over a large disassembly — grep -q exits at its first
#     match, the echo dies of SIGPIPE, pipefail fails the pipeline, so a PRESENT syscall read as
#     missing ("FAIL: server probe emits no syscall 56", rc 1); and its `objdump … | grep -q … &&
#     FAIL` Linux-band check would have read a real hit as GREEN. Every disassembly is now written
#     to a file and grepped there.
#   * redefinition_layout_and_enum_over_var.sh (6.7.16) — `n=$(grep -c "$3" "$T/e")`: the same
#     zero-count grep -c, on the gate's first silent row (sp_same), so `-e` ended it with rc 1;
#   * cli_temp_dir_no_leak.sh (6.7.16) — a cleanup `kill -KILL` of a git stand-in the CLI had
#     already stopped (ESRCH, rc 1 after 107 of 166 rows), and behind it the same kill at axis 7's
#     real-clone row, a killed FIFO holder's `wait` (143) and `k9k=$(ls <dir not made yet> | … |
#     head -1)` (rc 2): each now `|| true`.
# (issues/archived/2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md,
#  issues/archived/2026-10-17-stdlib-modules-self-sufficient-gate-stops-under-pipefail.md,
#  issues/archived/2026-10-18-redefinition-layout-gate-stops-under-pipefail.md,
#  issues/archived/2026-10-18-cli-temp-dir-gate-stops-under-pipefail.md)
#
# WHAT IS PINNED
#   axis 1  the checker tells a stop from a verdict: three fixture gates run the same way — a
#           `n=$(grep -c …)` at a zero count and a `$(yes | head -1)` each stop with no verdict
#           and must be read as STOPPED; the `|| true` spelling must be read as PASS.
#   axis 2  each gate in GATES, run as `bash -eo pipefail <gate>`, exits 0 with a last line
#           starting PASS (or 77 with a last line starting SKIP: a gate that could not run says
#           so by name). check.sh runs each of them under `sh` as its own row.
# Mutation (6.7.15): any gate's fix reverted (axis 2's `|| true` dropped, the census's
# `for-each-ref` back to `git tag … | head -1`, axis 5's `prc=0; ( … ) || prc=$?` back to
# `( … ); prc=$?`) -> RED here naming the gate, its rc and its last lines; 6.7.16: the
# agnos-crossbuild-gate.sh server-probe greps back to `echo "$sdis" | grep -q` -> RED (FAIL, rc 1).
# Add a gate to GATES when its pipefail stop or false verdict is fixed.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
NAME=gates_verdict_under_pipefail
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
command -v bash > /dev/null 2>&1 || { echo "SKIP: $NAME (no bash on PATH — the shell under test)"; exit 77; }

GATES="tests/gates/platform/syscall_xlat_generated.sh
tests/gates/toolchain/removed_symbol_census.sh
tests/gates/toolchain/stdlib_modules_self_sufficient.sh
tests/gates/platform/io_rdwr_agnos.sh
tests/gates/toolchain/gates_read_only_the_tree.sh
scripts/agnos-crossbuild-gate.sh
tests/gates/frontend/redefinition_layout_and_enum_over_var.sh
tests/gates/toolchain/cli_temp_dir_no_leak.sh"

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

# _verdict <rc> <out>: PASS (rc 0, last line PASS…), SKIP (rc 77, last line SKIP…), FAIL (a FAIL
# line was printed — a verdict, if a red one), else STOPPED (no verdict at all).
_verdict() {
    _last=$(grep -v '^[[:space:]]*$' "$2" | tail -1 || true)
    case "$1:$_last" in
        0:PASS*) echo PASS ;;
        77:SKIP*) echo SKIP ;;
        *) if grep -q '^FAIL' "$2"; then echo FAIL; else echo STOPPED; fi ;;
    esac
}

# ── axis 1: the checker tells a stop from a verdict ─────────────────────────────────────
printf '#!/bin/sh\nn=$(grep -c zzz /dev/null)\necho "PASS: fx_grep $n"\n' > "$D/fx_grep.sh"
printf '#!/bin/sh\nt=$(yes | head -1)\necho "PASS: fx_pipe $t"\n' > "$D/fx_pipe.sh"
printf '#!/bin/sh\nn=$(grep -c zzz /dev/null || true)\necho "PASS: fx_ok $n"\n' > "$D/fx_ok.sh"
for fx in fx_grep:STOPPED fx_pipe:STOPPED fx_ok:PASS; do
    f=${fx%%:*}; want=${fx#*:}
    frc=0; bash -eo pipefail "$D/$f.sh" > "$D/$f.out" 2>&1 || frc=$?
    got=$(_verdict "$frc" "$D/$f.out")
    [ "$got" = "$want" ] || _fail "axis 1: fixture $f read as $got (rc $frc), want $want — the checker cannot see a stop"
done
[ "$FAILS" = 0 ] && echo "  ok: axis 1: a zero-count grep -c and a SIGPIPE'd pipe read as STOPPED, the || true spelling as PASS"

# ── axis 2: each listed gate reaches its verdict under bash -eo pipefail ────────────────
# The gates run side by side (check.sh runs gates in parallel already); each one's rc lands in
# its own file, and every PID is waited on.
N=0; PIDS=""
for g in $GATES; do
    N=$((N + 1))
    [ -f "$g" ] || continue
    ( grc=0; bash -eo pipefail "$g" > "$D/gate$N.out" 2>&1 < /dev/null || grc=$?; echo "$grc" > "$D/gate$N.rc" ) &
    PIDS="$PIDS $!"
done
for p in $PIDS; do wait "$p" || true; done
N=0
for g in $GATES; do
    N=$((N + 1))
    if [ ! -f "$g" ]; then _fail "axis 2: $g is listed but missing"; continue; fi
    o="$D/gate$N.out"
    grc=$(cat "$D/gate$N.rc" 2>/dev/null || true)
    [ -n "$grc" ] || grc="(no status)"
    got=$(_verdict "$grc" "$o")
    case "$got" in
        PASS) echo "  ok: axis 2: $g — PASS under bash -eo pipefail" ;;
        SKIP) echo "  ok: axis 2: $g — SKIP under bash -eo pipefail (said so by name: $(tail -1 "$o"))" ;;
        *)
            _fail "axis 2: under bash -eo pipefail $g exited $grc with $got (want PASS); its last lines:"
            tail -6 "$o" | sed 's/^/        /' || true
            [ -s "$o" ] || echo "        (no output at all)"
            ;;
    esac
done
[ "$N" -ge 3 ] || _fail "axis 2: only $N gates listed (floor 3) — the list was emptied"

if [ "$FAILS" != 0 ]; then echo "FAIL: $NAME ($FAILS)"; exit 1; fi
echo "PASS: $NAME ($N gates reach their verdict under bash -eo pipefail; the checker tells a stop from a verdict)"
