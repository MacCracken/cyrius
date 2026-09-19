#!/bin/sh
# tests/gates/toolchain/build_temp_no_leak.sh — v6.5.19
#
# `cyrius build` must not leave its PREPROCESSED SOURCE temp behind on ANY exit path.
#
# THE DEFECT. `compile()` (cbt/build.cyr) calls `_materialize_source` to write
# `<tmpdir>/cpp_<pid>` — the dep-prepended, `#@incdir`-marked source cycc actually
# reads — and then unlinks it after `sys_waitpid`, deliberately above the
# success/failure split. But `_materialize_source` is called at :618 and the fork is
# at :679, and TWO `return 1;` paths sit between them: "output directory does not
# exist" and "cannot write output", both inside the pre-fork `probe_fd < 0` bail-out
# added at v6.5.7. Neither reached the unlink, so each leaked one temp per
# invocation. The comment above the unlink claimed BOTH paths were covered and named
# only the two after the fork; the count was wrong, which is the whole reason this
# gate counts rather than reads.
#
# Measured on the maintainer's box: 19,753 leftover `cpp_*` temps at the time this
# gate was written (state.md records 21,289 dirs / 2.8 GB before the v6.5.19 sweep).
# This is a disk-exhaustion leak on any box that builds in a loop, and it is silent.
#
# ⭐ WHY THE PREMISE ROW IS LOAD-BEARING. `_materialize_source` returns its argument
# UNCHANGED when there is nothing to prepend — in which case no temp is ever created
# and every "no new temp" assertion below is trivially true. A gate that only
# asserted the deltas would pass just as happily against a build that never
# materialised anything. Axis 0 therefore proves a temp is genuinely created for this
# fixture, by the one observable that cannot happen without it: `src/main.cyr`
# includes `helper.cyr`, its neighbour in `src/`, which resolves ONLY via the
# `#@incdir` marker that lives at byte 0 of the materialised temp. Built from the
# project root with CWD-relative resolution it could not resolve. If it builds, the
# temp existed.
#
# ⭐ AND AXIS 4 PROVES THE COUNTER. If the counting method could never see a temp,
# every delta is 0 and the gate is a placebo. Axis 4 plants a file named `cpp_probe`
# in a freshly-created `/tmp/cyrius-*` directory and requires the counter to report
# it. Both halves — "a temp is made" and "we can see one" — have to hold before a
# zero delta means anything.
#
# MUTATION PROOF (run at v6.5.19, RED then GREEN):
#   * delete `if (tmp_src != 0) { sys_unlink(tmp_src); }` from the `probe_fd < 0`
#     block in cbt/build.cyr and rebuild the CLI -> axes 1 and 2 RED, each reporting
#     delta 1 (one leaked temp per invocation, exactly one per early return); axes
#     0, 3 and 4 stay green. Restored -> all green, CLI byte-identical.
#   This is a SEMANTIC mutation: it removes the cleanup, not a message.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CYRIUS="$ROOT/build/cyrius"
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

for b in cyrius cycc; do
    if [ ! -x "$ROOT/build/$b" ]; then
        echo "FAIL: build-temp-no-leak — build/$b not built"
        exit 1
    fi
done

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: build_temp_no_leak: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# The unwritable fixture dir must be made writable again or `rm -rf` cannot clear it.
trap 'chmod 700 "$T/ro" 2>/dev/null; rm -rf "$T"' EXIT

# Hermetic toolchain, same reason as lint_reports_unparseable.sh: without this the
# gate exercises whatever cycc happens to be installed rather than this tree's.
mkdir -p "$T/home/bin"
cp "$ROOT/build/cycc" "$T/home/bin/cycc"
chmod +x "$T/home/bin/cycc"
CYRIUS_HOME="$T/home"
export CYRIUS_HOME

# The temp lives in `/tmp/cyrius-<pid>` (cbt/build.cyr::_cbt_tmpdir — no TMPDIR
# support, deliberately fail-closed per CVE-35/36). A box that has ever built
# anything holds thousands of historical leftovers, so counting all of /tmp would
# drown the signal. Count `cpp_*` ONLY inside directories that did not exist before
# the invocation, which is exactly the temp this invocation made.
# ⛔ v6.6.6 — SCOPED TO THE PROCESS, NOT TO "DIRS THAT APPEARED". The count used to cover every
# /tmp/cyrius-* dir created between a listing taken before the build and its exit, which
# includes ANOTHER check.sh's in-flight build on the same box (concurrent worktrees, a CI matrix
# on one runner): its live cpp_* read as this build's leak. The temp is named
# /tmp/cyrius-<pid>[-t<nonce>…] after the CLI's own pid, so the build runs through `run_cli`,
# which records that pid (the `exec` keeps it), and only that process's dirs are counted.
# CHANGELOG [6.6.6]
run_cli() { _pf=$1; shift; timeout 300 sh -c 'echo $$ > "$0"; exec "$@"' "$_pf" "$CYRIUS" "$@"; }
# new_temps <pidfile> -> number of cpp_* files left in that process's temp dir(s)
new_temps() {
    _p=$(cat "$1" 2>/dev/null || true)
    [ -n "$_p" ] || { echo "no-pid"; return; }
    n=0
    for d in /tmp/cyrius-"$_p" /tmp/cyrius-"$_p"-*; do
        [ -d "$d" ] || continue
        c=$(ls "$d" 2>/dev/null | grep -c '^cpp_' || true)
        n=$((n + c))
    done
    echo "$n"
}

# ── The fixture. A source in a SUBDIRECTORY is on its own enough to force
# materialisation (`_source_incdir != 0` => need_tmp = 1), and the sibling include
# makes that fact observable.
mkdir -p "$T/proj/src" "$T/proj/build"
printf 'fn helper_val() { return 7; }\n' > "$T/proj/src/helper.cyr"
printf 'include "helper.cyr"\nfn main() { return helper_val(); }\nvar r = main();\n' > "$T/proj/src/main.cyr"
printf '[project]\nname = "tmpleak"\nversion = "0.0.1"\n' > "$T/proj/cyrius.cyml"

# ── AXIS 0 — ⭐ PREMISE: a temp is genuinely materialised for this fixture.
echo "axis 0 — ⭐ PREMISE: the build materialises a temp (sibling include resolves):"
b_rc=0
( cd "$T/proj" && run_cli "$T/pid0" build src/main.cyr build/ok > "$T/o0" 2>&1 ) || b_rc=$?
check "sibling-include build SUCCEEDS (so #@incdir, hence the temp, existed)" 0 "$b_rc"
check "…and produced a binary" "yes" "$([ -s "$T/proj/build/ok" ] && echo yes || echo no)"

# ── AXIS 4 — ⭐ ANTI-VACUOUS: the counter can actually see a temp.
# Run before the delta axes so a broken counter is caught before it makes them pass.
echo "axis 4 — ⭐ ANTI-VACUOUS: the counting method can see a planted temp:"
# (the probe lives in the CLI's own /tmp/cyrius-* namespace — that is what is being counted —
# under a name no CLI process can take: pids are numeric)
echo "gateprobe-$$" > "$T/p4"
probe_dir="/tmp/cyrius-gateprobe-$$"
mkdir -p "$probe_dir" && : > "$probe_dir/cpp_probe"
check "a planted cpp_ temp is counted" 1 "$(new_temps "$T/p4")"
rm -rf "$probe_dir"

# ── AXIS 1 — the missing-output-directory early return.
echo "axis 1 — 'output directory does not exist' leaves no temp behind:"
r1=0
( cd "$T/proj" && run_cli "$T/pid1" build src/main.cyr build/nope/deeper/out > "$T/o1" 2>&1 ) || r1=$?
check "build fails" "yes" "$([ "$r1" != 0 ] && echo yes || echo no)"
check "…with the missing-directory message" 1 \
    "$(grep -c 'output directory does not exist' "$T/o1" || true)"
check "…and leaks NO preprocessed temp" 0 "$(new_temps "$T/pid1")"

# ── AXIS 2 — the unwritable-output early return.
echo "axis 2 — 'cannot write output' leaves no temp behind:"
mkdir -p "$T/ro" && chmod 500 "$T/ro"
if [ -w "$T/ro" ]; then
    # Running as root defeats the permission bit; the axis cannot be posed.
    echo "  ok: SKIP axis 2 — \$T/ro is writable anyway (running as root?) (skip)"
else
        r2=0
    ( cd "$T/proj" && run_cli "$T/pid2" build src/main.cyr "$T/ro/out" > "$T/o2" 2>&1 ) || r2=$?
    check "build fails" "yes" "$([ "$r2" != 0 ] && echo yes || echo no)"
    check "…with the unwritable-output message" 1 \
        "$(grep -c 'cannot write output' "$T/o2" || true)"
    check "…and leaks NO preprocessed temp" 0 "$(new_temps "$T/pid2")"
fi

# ── AXIS 3 — ANTI-VACUOUS: the SUCCESS path is clean too, so the gate cannot be
# satisfied by making the failure paths never materialise anything.
echo "axis 3 — ANTI-VACUOUS: a SUCCESSFUL build leaves no temp behind either:"
r3=0
( cd "$T/proj" && run_cli "$T/pid3" build src/main.cyr build/ok2 > "$T/o3" 2>&1 ) || r3=$?
check "build succeeds" 0 "$r3"
check "…and leaks NO preprocessed temp" 0 "$(new_temps "$T/pid3")"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: build-temp-no-leak — no exit path leaves a preprocessed source behind"
    exit 0
fi
echo "FAIL: build-temp-no-leak — $fails assertion(s) failed"
exit 1
