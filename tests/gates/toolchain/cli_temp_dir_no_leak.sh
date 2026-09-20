#!/bin/sh
# tests/gates/toolchain/cli_temp_dir_no_leak.sh — v6.6.6
#
# The `cyrius` CLI must not leave its PRIVATE TEMP DIRECTORY behind on any exit path.
#
# THE DEFECT. `_cbt_tmpdir()` (cbt/build.cyr) creates `<base>/cyrius-<pid>` on first
# use — added at v6.4.81 to close CVE-35/CVE-36, which were about the SHARED `/tmp`
# namespace, not about lifetime — and from that release to 6.6.5 NOTHING ever removed
# it. Every `cyrius run` / `lint` / `test` / `lsp` / `deps` left one empty directory in
# `/tmp` for good. Measured on the maintainer's box at 6.6.5: 5,005 `/tmp/cyrius-<pid>`
# directories, 398 of the 400 newest of them EMPTY. Each one is 4 KB of inode and a
# name in a directory every other tool on the box has to scan.
#
# THE FIX (CHANGELOG [6.6.6]). `_cbt_tmpdir_cleanup()` rmdirs it, called from the CLI's
# single normal exit at the bottom of cbt/cyrius.cyr and from `_cbt_exit` on the
# parent-side `sys_exit` paths that can run after a temp dir exists.
#
# ⭐ WHY AXIS 1 IS LOAD-BEARING. Most of this gate asserts "no directory was left", and
# a verb that never creates one satisfies that trivially — a gate made only of deltas
# would pass just as happily against a CLI whose temp dir was never built. Axis 1 proves
# each verb genuinely calls `_cbt_tmpdir()`, by a completely different observable from
# the leak count: it OCCUPIES all 16 candidate names for the CLI's own pid, which forces
# the documented fail-closed refusal ("16 candidates were taken"). A verb that never
# asks for a temp dir cannot produce that message.
#
# ⭐ AND AXIS 0 PROVES THE COUNTER. A counting method that can never see a directory
# makes every delta 0. Axis 0 plants one under a name no CLI process can take and
# requires the counter to report it.
#
# ⭐ AXIS 4 PINS THE SHAPE OF THE FIX: rmdir, never a recursive sweep. `cyrius lsp` with
# no CYRIUS_HOME prints this path and tells the user to copy the binary out of it, and a
# SIGKILLed `cyrius test` leaves its `test_bin` for a post-mortem (that is exactly what
# the 2 non-empty directories in the sample above were). A cleanup that deleted them
# would be data loss, so a file planted in the live directory must SURVIVE.
#
# ⚠ WINDOWS IS NOT COVERED AND THAT IS NOT AN OVERSIGHT. `xrmdir` (lib/io.cyr) degrades
# to -1 on PE: no RemoveDirectoryW reroute is wired and wiring one is a COMPILER change.
# This gate is POSIX-only by construction (it counts `/tmp/cyrius-*`).
#
# MUTATION PROOF (run at 6.6.6, in a scratch tree — RED then GREEN):
#   * delete `_cbt_tmpdir_cleanup();` from the bottom of cbt/cyrius.cyr and rebuild the
#     CLI -> axis 2 RED for every temp-creating verb (1 directory left each) and axis 3
#     RED on both error paths; axes 0, 1 and 4 stay GREEN.
#   * replace the `xrmdir(d)` body of `_cbt_tmpdir_cleanup` with a recursive sweep
#     (unlink every entry, then rmdir) -> axis 4 RED (the planted file is gone); axes 2
#     and 3 stay green, which is the point: axis 4 is the only one that sees it.
#   * real tree, unmutated -> all axes GREEN.
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
        echo "FAIL: cli-temp-dir-no-leak — build/$b not built"
        exit 1
    fi
done

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cli_temp_dir_no_leak: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# Hermetic toolchain — this tree's cycc, not whatever is installed.
mkdir -p "$T/home/bin"
cp "$ROOT/build/cycc" "$T/home/bin/cycc"
chmod +x "$T/home/bin/cycc"
CYRIUS_HOME="$T/home"
export CYRIUS_HOME

# ── The fixture. Every source lives in `src/`, a SUBDIRECTORY, because that is what
# makes `compile()` materialise a preprocessed temp (`_source_incdir != 0` => the
# `#@incdir` marker has to be written) — with a flat source and no deps to prepend,
# `_materialize_source` returns its argument unchanged and `cyrius build` never asks for
# a temp directory at all. The sibling include makes that fact observable, and axis 1
# then measures it rather than assuming it.
mkdir -p "$T/proj/src" "$T/proj/build"
printf '[project]\nname = "tmpdirleak"\nversion = "0.0.1"\n'  > "$T/proj/cyrius.cyml"
printf 'fn helper_val(): i64 { return 0; }\n'                  > "$T/proj/src/helper.cyr"
printf 'include "helper.cyr"\nfn main(): i64 { return helper_val(); }\nvar r = main();\n' > "$T/proj/src/ok.cyr"
printf 'include "helper.cyr"\nfn main(): i64 { return helper_val(); }\nvar r = main();\n' > "$T/proj/src/ok.tcyr"
printf 'include "helper.cyr"\nfn main(): i64 { return @@@; }\n' > "$T/proj/src/bad.cyr"

# ── The counter. The temp dir is `/tmp/cyrius-<pid>` with up to 15 `-N` retries
# (cbt/build.cyr::_cbt_tmpdir — no TMPDIR support, deliberately, per CVE-35/36), so it
# is addressed by the CLI's OWN pid. `run_cli` records that pid in a file and `exec`s,
# which keeps it. Counting by pid rather than by "directories that appeared" is what
# makes this safe to run beside another check.sh on the same box.
run_cli() { _pf=$1; shift; timeout 300 sh -c 'echo $$ > "$0"; exec "$@"' "$_pf" "$CYRIUS" "$@"; }
# dirs_for <pidfile> -> how many of that process's temp directories still exist
dirs_for() {
    _p=$(cat "$1" 2>/dev/null || true)
    [ -n "$_p" ] || { echo "no-pid"; return; }
    n=0
    for d in "/tmp/cyrius-$_p" "/tmp/cyrius-$_p"-*; do
        [ -d "$d" ] && n=$((n + 1))
    done
    echo "$n"
}
# Belt and braces: whatever this gate's own runs leave, it removes.
sweep_for() { _p=$(cat "$1" 2>/dev/null || true); [ -n "$_p" ] && rm -rf "/tmp/cyrius-$_p" "/tmp/cyrius-$_p"-* 2>/dev/null; return 0; }

# ── AXIS 0 — ⭐ ANTI-VACUOUS: the counting method can see a directory at all.
echo "axis 0 — ⭐ ANTI-VACUOUS: the counter sees a planted temp directory:"
echo "gateprobe-$$" > "$T/p0"
mkdir -p "/tmp/cyrius-gateprobe-$$"
check "a planted temp dir is counted" 1 "$(dirs_for "$T/p0")"
rmdir "/tmp/cyrius-gateprobe-$$" 2>/dev/null
check "…and 0 once it is gone" 0 "$(dirs_for "$T/p0")"

# ── AXIS 1 — ⭐ PREMISE: these verbs really do create a private temp directory.
# Occupy all 16 candidate names for the CLI's pid before it starts. A verb that calls
# `_cbt_tmpdir()` must then fail closed with its documented message; a verb that never
# calls it runs to completion and is reported as NOT temp-creating.
echo "axis 1 — ⭐ PREMISE: the verbs under test allocate a temp dir (16-candidate squeeze):"
occupy_run() {
    _pf=$1; _out=$2; shift 2
    timeout 300 sh -c '
        echo $$ > "$0"
        for s in "" -1 -2 -3 -4 -5 -6 -7 -8 -9 -10 -11 -12 -13 -14 -15; do
            mkdir -p "/tmp/cyrius-$$$s" || exit 90
        done
        shift
        exec "$@"' "$_pf" x "$@" > "$_out" 2>&1
}
creators=0
for v in "run src/ok.cyr" "lint src/ok.cyr" "test src/ok.tcyr" "build src/ok.cyr build/out.bin"; do
    vn=$(echo "$v" | cut -d' ' -f1)
    # shellcheck disable=SC2086
    ( cd "$T/proj" && occupy_run "$T/p1-$vn" "$T/o1-$vn" "$CYRIUS" $v ) || true
    if grep -q '16 candidates were taken' "$T/o1-$vn" 2>/dev/null; then
        echo "  ok: '$vn' allocates a private temp dir (fails closed when squeezed)"
        creators=$((creators + 1))
        echo "$vn" >> "$T/creators"
    else
        echo "  ok: '$vn' does NOT allocate a private temp dir (not counted)"
    fi
    sweep_for "$T/p1-$vn"
done
# Derived floor: the count comes from the squeeze above, the expectation from a
# DIFFERENT source — how many of these four verbs reach a `_cbt_tmpfile`/`_cbt_tmpexe`
# call in cbt/. All four do (`cmd_run`/`cmd_lint`/`cmd_test`/`compile`'s materialise),
# so anything less than 4 means the premise stopped holding and the deltas below stopped
# meaning anything.
check "all four probe verbs are temp-dir creators" 4 "$creators"

# ── AXIS 2 — the SUCCESS paths leave nothing behind.
echo "axis 2 — successful verbs leave no temp directory:"
for v in "run src/ok.cyr" "lint src/ok.cyr" "test src/ok.tcyr" "build src/ok.cyr build/out.bin" "fmt --check src/ok.cyr" "check src/ok.cyr" "version"; do
    vn=$(echo "$v" | tr ' /.-' '____')
    # shellcheck disable=SC2086
    ( cd "$T/proj" && run_cli "$T/p2-$vn" $v > "$T/o2-$vn" 2>&1 ) || true
    check "'$v' leaves 0 temp dirs" 0 "$(dirs_for "$T/p2-$vn")"
    sweep_for "$T/p2-$vn"
done

# ── AXIS 3 — the ERROR paths leave nothing behind either. This is the half the
# 6.5.19 sibling gate (build_temp_no_leak.sh) had to be written for: a cleanup that
# only runs on success is not a cleanup.
echo "axis 3 — error paths leave no temp directory:"
( cd "$T/proj" && run_cli "$T/p3a" build src/bad.cyr build/out2.bin > "$T/o3a" 2>&1 ) || true
check "a COMPILE ERROR is reported" "yes" "$([ -s "$T/o3a" ] && echo yes || echo no)"
check "…and leaves 0 temp dirs" 0 "$(dirs_for "$T/p3a")"
sweep_for "$T/p3a"
( cd "$T/proj" && run_cli "$T/p3b" run src/missing_source.cyr > "$T/o3b" 2>&1 ) || true
check "a MISSING SOURCE leaves 0 temp dirs" 0 "$(dirs_for "$T/p3b")"
sweep_for "$T/p3b"
( cd "$T/proj" && run_cli "$T/p3c" build src/ok.cyr build/nope/deeper/out > "$T/o3c" 2>&1 ) || true
check "an UNWRITABLE OUTPUT leaves 0 temp dirs" 0 "$(dirs_for "$T/p3c")"
sweep_for "$T/p3c"

# ── AXIS 4 — ⭐ CONTRACT: rmdir, never a recursive sweep. A file planted in the LIVE
# temp directory must still be there afterwards, and the directory with it.
echo "axis 4 — ⭐ CONTRACT: a non-empty temp directory is NOT removed:"
printf 'include "helper.cyr"\nfn main(): i64 { var i = helper_val(); while (i < 600000000) { i = i + 1; } return 0; }\nvar r = main();\n' > "$T/proj/src/slow.cyr"
( cd "$T/proj" && run_cli "$T/p4" run src/slow.cyr > "$T/o4" 2>&1 ) &
bg=$!
planted=""
w=0
while [ "$w" -lt 600 ]; do
    p=$(cat "$T/p4" 2>/dev/null || true)
    if [ -n "$p" ]; then
        for d in "/tmp/cyrius-$p" "/tmp/cyrius-$p"-*; do
            if [ -d "$d" ]; then planted="$d"; break; fi
        done
    fi
    [ -n "$planted" ] && break
    w=$((w + 1))
    sleep 0.05
done
if [ -z "$planted" ]; then
    echo "  FAIL: axis 4 — the live temp directory never appeared (cannot pose the axis)"
    fails=$((fails + 1))
    wait "$bg" 2>/dev/null || true
else
    : > "$planted/gate_keepme"
    wait "$bg" 2>/dev/null || true
    check "the planted file survives" "yes" "$([ -f "$planted/gate_keepme" ] && echo yes || echo no)"
    check "…and so does its directory" "yes" "$([ -d "$planted" ] && echo yes || echo no)"
    rm -rf "$planted"
fi
sweep_for "$T/p4"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: cli-temp-dir-no-leak — no CLI exit path leaves its private temp directory behind"
    exit 0
fi
echo "FAIL: cli-temp-dir-no-leak — $fails assertion(s) failed"
exit 1
