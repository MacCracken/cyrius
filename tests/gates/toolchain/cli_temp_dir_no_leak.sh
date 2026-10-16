#!/bin/sh
# tests/gates/toolchain/cli_temp_dir_no_leak.sh — v6.6.6
#
# The `cyrius` CLI must not leave its PRIVATE TEMP DIRECTORY behind on any exit path.
#
# THE DEFECT. `_cbt_tmpdir()` (cbt/build.cyr) creates `<base>/cyrius-<pid>` on first
# use — added at v6.4.81 to close CYRIUS-2026-0005/CYRIUS-2026-0006, which were about the SHARED `/tmp`
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
# ⚠ THIS GATE IS POSIX-ONLY BY CONSTRUCTION (it counts `/tmp/cyrius-*`). Windows IS
# covered — 6.6.6 wired the `RemoveDirectoryW` reroute `xrmdir` was missing on PE — but
# the rows that prove it need wine and the cross-built PE CLI, so they live in
# `tests/gates/platform/cbt_fork_sites_have_pe_arm.sh` axis 4 (a `%TEMP%` delta over the
# verbs it already runs, plus a direct five-behaviour `xrmdir` probe as the premise).
#
# MUTATION PROOF (run at 6.6.6, in a scratch tree — RED then GREEN):
#   * delete `_cbt_tmpdir_cleanup();` from the bottom of cbt/cyrius.cyr and rebuild the
#     CLI -> axis 2 RED for every temp-creating verb (1 directory left each) and axis 3
#     RED on both error paths; axes 0, 1 and 4 stay GREEN.
#   * turn one routed `_cbt_exit(1)` (cbt/deps.cyr) back into a bare `sys_exit(1)` and
#     rebuild -> axis 5 RED, naming the file and line; axes 0-4 stay GREEN (nothing
#     drives that path, which is the point of the axis).
#   * replace the `xrmdir(d)` body of `_cbt_tmpdir_cleanup` with a recursive sweep
#     (unlink every entry, then rmdir) -> axis 4 RED (the planted file is gone); axes 2
#     and 3 stay green, which is the point: axis 4 is the only one that sees it.
#   * real tree, unmutated -> all axes GREEN.
#   * (6.7.10) `_dep_wt_run` keeping its stderr capture for the process's life again (the pre-fix
#     `_dep_wt_err` CLI) -> axis 6 RED on all three git rows (1 directory left each, holding wt_err);
#     its anti-vacuous rows stay GREEN (the queries ran).
#   * (6.7.11, axis 7) compile() keeping `cpp_<pid>` on a failed compile -> 4 RED (axis 3's compile
#     error, 7's check on a compile error and on an undefined fn, the compiler killed); distlib's
#     collect keeping `dlverifyerr<t>` -> 1 RED (7's distlib row); `_cbt_tmpbase` ignoring
#     $TMPDIR -> 5 RED (axis 1's squeeze, axis 4, and 7's three kill rows); `cc_err` dropped from
#     check.sh's scratch vocabulary -> 1 RED (7's last row: the kill leaves a name the reaper keeps).
#   * (6.7.12, axis 7's kill rows; each mutant replaces build/cyrius) no `_cbt_sig_install()` in
#     main, or the 6.7.11 CLI -> 19 RED (every kill row's dir and compiler, build's k7out.tmp, the
#     planted dir's leftover names, the nohup row's TERM, the distlib kill); `_cbt_sig_stop` not
#     stopping children -> 8 RED (each run's compiler still running, the distlib dir and compilers);
#     distlib's children tracked as exec'd tools (SIGKILLed, not forwarded) -> 2 RED (the distlib
#     dir, its six compilers); an inherited SIG_IGN overridden -> 1 RED (the nohup row).
#   * (6.7.13) capacity's `cap_err` / compiler and `_dep_wt_run`'s `wt_err` / git child untracked
#     again (the 6.7.13-open CLI) -> 4 RED (capacity's dir and compiler, the --local git row's dir
#     and git); their anti-vacuous rows stay GREEN. `_dep_wt_run`'s stdout capture untracked again
#     (that commit's CLI) -> 2 RED (the rev-parse and ls-remote rows' dirs, holding wt_out / ls_remote).
#     The distlib mirror's slot never set (`_cbt_sig_tree_set` dropped from `_distlib_mirror_make`), or
#     the round's entry.cyr untracked -> 1 RED each (the distlib kill row's dist/.dlverify-<pid>).
#
# AXIS 7 (6.7.11) — every compile FAILURE with the CLI alive leaves nothing (a compile error and
# an undefined fn under `cyrius check`, a build renamed onto a directory, a distlib verify refused
# mid-round, the compiler killed by a signal). Measured before writing it: every one of those
# failure paths already unlinked its scratch (6.5.19 / 6.6.6 / 6.6.20); the leftovers on this box
# were all kills mid-compile. Since 6.7.12 a CLI stopped by SIGTERM / SIGINT / SIGHUP mid-compile
# (check, build, a distlib verify) stops its compiler, leaves no dir under the absolute $TMPDIR and
# exits 128+N; the in-flight names (what a SIGKILL still leaves) are ones check.sh's reaper removes
# (`_chk_cli_scratch`, read out of scripts/check.sh).
set -u
# The CLI's temp base, derived exactly as cbt/build.cyr::_cbt_tmpbase derives it (6.6.9 bite
# 9): an ABSOLUTE $TMPDIR with trailing slashes dropped, else /tmp. A fixed /tmp here would
# count nothing under a set TMPDIR and read GREEN over directories it never looked at.
case "${TMPDIR:-}" in /*) CTB=$(printf '%s' "$TMPDIR" | sed 's:/*$::'); [ -n "$CTB" ] || CTB=/ ;; *) CTB=/tmp ;; esac
export CTB
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
# under the base below ($CTB — an absolute $TMPDIR since 6.6.9, else /tmp; cbt/build.cyr::_cbt_tmpdir), so it
# is addressed by the CLI's OWN pid. `run_cli` records that pid in a file and `exec`s,
# which keeps it. Counting by pid rather than by "directories that appeared" is what
# makes this safe to run beside another check.sh on the same box.
run_cli() { _pf=$1; shift; timeout 300 sh -c 'echo $$ > "$0"; exec "$@"' "$_pf" "$CYRIUS" "$@"; }
# dirs_for <pidfile> -> how many of that process's temp directories still exist
dirs_for() {
    _p=$(cat "$1" 2>/dev/null || true)
    [ -n "$_p" ] || { echo "no-pid"; return; }
    n=0
    for d in "$CTB/cyrius-$_p" "$CTB/cyrius-$_p"-*; do
        [ -d "$d" ] && n=$((n + 1))
    done
    echo "$n"
}
# Belt and braces: whatever this gate's own runs leave, it removes.
sweep_for() { _p=$(cat "$1" 2>/dev/null || true); [ -n "$_p" ] && rm -rf "$CTB/cyrius-$_p" "$CTB/cyrius-$_p"-* 2>/dev/null; return 0; }

# ── AXIS 0 — ⭐ ANTI-VACUOUS: the counting method can see a directory at all.
echo "axis 0 — ⭐ ANTI-VACUOUS: the counter sees a planted temp directory:"
echo "gateprobe-$$" > "$T/p0"
mkdir -p "$CTB/cyrius-gateprobe-$$"
check "a planted temp dir is counted" 1 "$(dirs_for "$T/p0")"
rmdir "$CTB/cyrius-gateprobe-$$" 2>/dev/null
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
            mkdir -p "$CTB/cyrius-$$$s" || exit 90
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
# ⚠ 6.6.10: this row used to check only that the output was non-empty — and `@@@` was
# silently dropped by the lexer (the dropped-at-sign lexer bug), so `build src/bad.cyr` printed `OK (4448 bytes)`
# at rc 0 and this "COMPILE ERROR" row passed on a SUCCESSFUL build. It now requires the
# build to FAIL, with the compiler's own diagnostic. CHANGELOG [6.6.10]
rc3a=0
( cd "$T/proj" && run_cli "$T/p3a" build src/bad.cyr build/out2.bin > "$T/o3a" 2>&1 ) || rc3a=$?
check "a COMPILE ERROR fails the build (rc != 0)" "yes" "$([ "$rc3a" != 0 ] && echo yes || echo no)"
check "…and is reported by the compiler" "yes" "$(grep -q 'unexpected character (0x40)' "$T/o3a" && echo yes || echo no)"
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
        for d in "$CTB/cyrius-$p" "$CTB/cyrius-$p"-*; do
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

# ── AXIS 5 — ⭐ EVERY PARENT-SIDE EXIT IS ROUTED. Axes 2 and 3 can only watch the exits
# that EXIST today; this one is about the next one somebody writes. Every `sys_exit(` in
# cbt/ must be either inside a FORKED CHILD (a different process — the parent's temp dir
# is not its to remove) or inside `_cbt_tmpdir` / `_cbt_exit` themselves, or the kill
# handler's `_cbt_sig_exit` (6.7.12), which removes the dir itself — only in the process that
# created it, so a forked child's handler never removes its parent's. A new
# parent-side `sys_exit` anywhere else is a new leak, and it is invisible to a
# leave-nothing-behind delta because nothing drives that path yet.
#
# ⚠ THIS AXIS IS ALSO THE HONEST VERSION OF A CLAIM 6.6.6 OVERSTATED. `_cbt_exit`'s
# comment said it covered "the four parent-side sys_exit paths that can run after a temp
# directory exists"; three of those four are in `_try_redirect_to_pinned`, which main()
# calls BEFORE anything allocates a temp dir, and the fourth is reached from `cyrius
# deps`, which allocates none of its own. They are defensive, not load-bearing — so the
# thing worth gating is not those four sites but the RULE they follow.
echo "axis 5 — ⭐ every sys_exit() in cbt/ is child-side or routed through _cbt_exit:"
cat > "$T/exits.awk" <<'AWK'
# A `sys_exit` is CHILD-side when it sits inside an `if (<v> == 0) { ... }` whose <v> was
# assigned from `sys_fork()` earlier in the same fn — derived from the source, never a
# name list (the fork variable is `pid`, `pid2`, `gpid`, `cpid`, ... across cbt/). Since 6.7.13 a
# tracked fork is `_cbt_fork_tracked(fwd)` (cbt/sigclean.cyr), which answers as sys_fork() does.
/^fn [A-Za-z_]/ { fname = $2; sub(/\(.*/, "", fname); depth = 0; child = -1; delete forkv }
{
    line = $0
    gsub(/"[^"]*"/, "", line)
    if (line !~ /^[ \t]*#(ifdef|ifndef|endif|else|elif)/) { sub(/#.*/, "", line) }
    if (match(line, /var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(sys_fork\(\)|_cbt_fork_tracked\()/)) {
        v = substr(line, RSTART, RLENGTH)
        sub(/^var[ \t]+/, "", v); sub(/[ \t]*=.*/, "", v)
        forkv[v] = 1
    }
    ischild = 0
    if (match(line, /if[ \t]*\([ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*==[ \t]*0[ \t]*\)/)) {
        w = substr(line, RSTART, RLENGTH)
        sub(/^if[ \t]*\([ \t]*/, "", w); sub(/[ \t]*==.*/, "", w)
        if (w in forkv) { ischild = 1 }
    }
    if (line ~ /sys_exit\(/) {
        st = "PARENT"
        if (child >= 0) { st = "child" }
        printf "%s:%d fn=%s %s\n", FILENAME, FNR, fname, st
    }
    nop = gsub(/\{/, "{", line)
    ncl = gsub(/\}/, "}", line)
    if (ischild == 1 && child < 0) { child = depth }
    depth = depth + nop - ncl
    if (child >= 0 && depth <= child) { child = -1 }
}
AWK
awk -f "$T/exits.awk" cbt/*.cyr > "$T/exits"
NEX=$(grep -c 'fn=' "$T/exits" || true)
NCH=$(grep -c ' child$' "$T/exits" || true)
check "the scan found cbt/'s sys_exit sites (floor 30, found $NEX)" yes \
    "$([ "$NEX" -ge 30 ] && echo yes || echo no)"
check "  …most of them child-side (floor 25, found $NCH)" yes \
    "$([ "$NCH" -ge 25 ] && echo yes || echo no)"
grep ' PARENT$' "$T/exits" | grep -Ev 'fn=(_cbt_tmpdir|_cbt_exit|_cbt_sig_exit) ' > "$T/stray" || true
if [ -s "$T/stray" ]; then
    echo "  parent-side sys_exit() outside _cbt_tmpdir/_cbt_exit/_cbt_sig_exit — each one leaks the temp dir:"
    sed 's/^/    /' "$T/stray"
fi
check "no parent-side sys_exit bypasses _cbt_exit" 0 "$(wc -l < "$T/stray" | tr -d ' ')"
# The detector's own control: three shapes in one file, one of each verdict.
mkdir -p "$T/ax5"
cat > "$T/ax5/probe.cyr" <<'EOF'
fn forked(): i64 {
    var gpid = sys_fork();
    if (gpid == 0) {
        if (1 == 0) { sys_exit(126); }
        sys_exit(127);
    }
    return 0;
}
fn after_the_child(): i64 {
    var pid = sys_fork();
    if (pid == 0) {
        sys_exit(127);
    }
    sys_exit(1);
    return 0;
}
fn no_fork_at_all(): i64 {
    sys_exit(3);
    return 0;
}
fn tracked_fork(): i64 {
    var tpid = _cbt_fork_tracked(0);
    if (tpid == 0) {
        sys_exit(127);
    }
    return 0;
}
EOF
awk -f "$T/exits.awk" "$T/ax5/probe.cyr" > "$T/ax5/out"
check "  ⭐ ANTI-VACUOUS: a child-side exit is cleared (a _cbt_fork_tracked child too, 6.7.13)" 4 "$(grep -c ' child$' "$T/ax5/out" || true)"
check "  ⭐ ANTI-VACUOUS: an exit AFTER the child block is flagged" 1 \
    "$(grep -c 'fn=after_the_child PARENT' "$T/ax5/out" || true)"
check "  ⭐ ANTI-VACUOUS: a fork-free exit is flagged" 1 \
    "$(grep -c 'fn=no_fork_at_all PARENT' "$T/ax5/out" || true)"

# ── AXIS 6 — THE GIT QUERIES (6.7.10). `_dep_wt_run` (cbt/deps.cyr) captured git's stderr in
# `<tmp>/wt_err` and kept it for the process's life, so the rmdir at exit failed and every local-mode
# resolve (the checkout's state line, `check-ignore`) and `cyrius update`'s newer-tags listing left its
# temp dir behind holding it — 17 of them after one check.sh run. Anti-vacuous: each row must show it
# ran the git query — the `local:` line naming the checkout's state; `update` naming the newest tag,
# then quoting git's own error once the origin is gone (the quote now comes from `_dep_wt_why`).
echo "axis 6 — the git queries (a --local build, update) leave no temp directory:"
if ! command -v git > /dev/null 2>&1; then
    echo "  SKIP (named): axis 6 — git is not installed; the git-query rows did not run"
else
    G6="$T/g6"
    mkdir -p "$G6/o/sib/dist" "$G6/ws"
    # a versioned throwaway home: `cyrius update` finds its stdlib only at versions/<v>/lib
    V6=$(tr -d '[:space:]' < "$ROOT/VERSION")
    H6="$G6/home"
    mkdir -p "$H6/versions/$V6/bin" "$H6/deps" && cp "$ROOT/build/cycc" "$H6/versions/$V6/bin/cycc" \
        && cp -r "$ROOT/lib" "$H6/versions/$V6/lib" && printf '%s\n' "$V6" > "$H6/current"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$G6/gitconfig" GIT_ALLOW_PROTOCOL=file
    printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$G6/gitconfig"
    printf 'fn sib_v(): i64 { return 1; }\n' > "$G6/o/sib/dist/sib.cyr"
    ( cd "$G6/o/sib" && git init -q . && git add -A && git commit -qm v1 && git tag v1.0.0 ) > /dev/null 2>&1
    git clone -q "$G6/o/sib" "$G6/ws/sib" > /dev/null 2>&1
    printf 'fn sib_v(): i64 { return 2; }\n' > "$G6/ws/sib/dist/sib.cyr"
    P6="$G6/ws/app"
    mkdir -p "$P6/src"
    printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/app"\n\n[deps]\nstdlib = ["syscalls"]\n\n[deps.sib]\ngit = "file://%s/o/sib"\ntag = "v1.0.0"\npath = "../sib"\nmodules = ["dist/sib.cyr"]\n' "$G6" > "$P6/cyrius.cyml"
    printf 'build/\n' > "$P6/.gitignore"
    printf 'fn main(): i64 { return sib_v(); }\nvar r = main();\nsyscall(SYS_EXIT, r);\n' > "$P6/src/main.cyr"
    ( cd "$P6" && export HOME="$G6/nohome" CYRIUS_HOME="$H6" CYRIUS_RESOLVED=1 && run_cli "$T/p6a" build --local > "$T/o6a" 2>&1 ) || true
    check "a --local build ran its git queries (the checkout's state line)" yes \
        "$(grep -q '^local: sib <- ../sib @[0-9a-f]*, at v1.0.0, dirty' "$T/o6a" && echo yes || echo no)"
    check "  …and leaves 0 temp dirs" 0 "$(dirs_for "$T/p6a")"
    sweep_for "$T/p6a"
    ( cd "$P6" && export HOME="$G6/nohome" CYRIUS_HOME="$H6" CYRIUS_RESOLVED=1 && run_cli "$T/p6b" update > "$T/o6b" 2>&1 ) || true
    check "update listed the origin's tags through git" yes \
        "$(grep -q 'sib: v1.0.0 pinned; it is the newest version tag' "$T/o6b" && echo yes || echo no)"
    check "  …and leaves 0 temp dirs" 0 "$(dirs_for "$T/p6b")"
    sweep_for "$T/p6b"
    mv "$G6/o/sib" "$G6/o/gone"
    ( cd "$P6" && export HOME="$G6/nohome" CYRIUS_HOME="$H6" CYRIUS_RESOLVED=1 && run_cli "$T/p6c" update > "$T/o6c" 2>&1 ) || true
    check "update on a gone origin quotes git's own error" yes \
        "$(grep -q "sib: v1.0.0 pinned; the remote's tags could not be listed (fatal: " "$T/o6c" && echo yes || echo no)"
    check "  …and leaves 0 temp dirs" 0 "$(dirs_for "$T/p6c")"
    sweep_for "$T/p6c"
fi

# ── AXIS 7 — COMPILE FAILURES leave no scratch (6.7.11), and a caught KILL leaves no dir (6.7.12).
# A dead pid's dir is removed by check.sh only when every entry is compile scratch (the reaper,
# scripts/check.sh `_chk_cli_scratch`, user decision 2026-10-13). So: every way a compile FAILS
# with the CLI still alive unlinks its `cpp_<pid>`, `cc_err` and `<out>.tmp.<pid>` (the dir is then
# empty and goes at exit); a CLI stopped by SIGTERM / SIGINT / SIGHUP mid-compile unlinks them in
# its handler and removes the dir; and what a SIGKILL leaves is exactly names the reaper's
# vocabulary accepts, under an ABSOLUTE $TMPDIR (trailing slash dropped), never /tmp.
echo "axis 7 — compile failures leave no scratch; a SIGTERM / SIGINT / SIGHUP mid-compile leaves no dir under \$TMPDIR:"
printf 'include "helper.cyr"\nfn main(): i64 { return nope_undefined_fn(); }\nvar r = main();\n' > "$T/proj/src/undef.cyr"
mkdir -p "$T/proj/outdir"
rc7=0; ( cd "$T/proj" && run_cli "$T/p7a" check src/bad.cyr > "$T/o7a" 2>&1 ) || rc7=$?
check "check on a compile error fails" yes "$([ "$rc7" != 0 ] && echo yes || echo no)"
check "  …and leaves 0 temp dirs (no cpp_ / cc_err / check_<pid>.tmp)" 0 "$(dirs_for "$T/p7a")"
sweep_for "$T/p7a"
rc7=0; ( cd "$T/proj" && run_cli "$T/p7b" check src/undef.cyr > "$T/o7b" 2>&1 ) || rc7=$?
check "check on an undefined fn fails, naming it" yes "$([ "$rc7" != 0 ] && grep -q nope_undefined_fn "$T/o7b" && echo yes || echo no)"
check "  …and leaves 0 temp dirs" 0 "$(dirs_for "$T/p7b")"
sweep_for "$T/p7b"
rc7=0; ( cd "$T/proj" && run_cli "$T/p7c" build src/ok.cyr outdir > "$T/o7c" 2>&1 ) || rc7=$?
check "build onto an existing DIRECTORY fails (the rename)" yes "$([ "$rc7" != 0 ] && echo yes || echo no)"
check "  …and leaves 0 temp dirs" 0 "$(dirs_for "$T/p7c")"
check "  …and no outdir.tmp.<pid> beside it" 0 "$(ls -d "$T/proj"/outdir.tmp.* 2>/dev/null | wc -l | tr -d ' ')"
sweep_for "$T/p7c"
# A distlib verify that REFUSES mid-round (two stdlib leaves declare the name every target
# lacks): its six per-target children wrote dlverifyerr<t> / dlverifyout<t> and cpp_<child pid>.
D7="$T/d7"
mkdir -p "$D7/bin" "$D7/home/versions/$(tr -d '[:space:]' < "$ROOT/VERSION")" "$D7/p/src"
V7=$(tr -d '[:space:]' < "$ROOT/VERSION")
cp "$CYRIUS" "$D7/bin/cyrius" && cp "$ROOT/build/cycc" "$D7/bin/cycc" && chmod +x "$D7/bin/cyrius" "$D7/bin/cycc"
if ( cd "$ROOT" && "$ROOT/build/cycc" < src/main_aarch64.cyr > "$D7/bin/cycc_aarch64" 2>/dev/null ) && chmod +x "$D7/bin/cycc_aarch64"; then
    cp -R "$ROOT/lib" "$D7/home/versions/$V7/lib"
    printf 'fn d7tie(): i64 { return 1; }\n' > "$D7/home/versions/$V7/lib/d7_one.cyr"
    printf 'fn d7tie(): i64 { return 2; }\n' > "$D7/home/versions/$V7/lib/d7_two.cyr"
    printf '[package]\nname = "d7"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$V7" > "$D7/p/cyrius.cyml"
    printf 'fn d7_a(): i64 { return d7tie(); }\n' > "$D7/p/src/lib.cyr"
    rc7=0; ( cd "$D7/p" && CYRIUS_HOME="$D7/home" CYRIUS_RESOLVED=1 timeout 300 sh -c 'echo $$ > "$0"; exec "$@"' "$T/p7e" "$D7/bin/cyrius" distlib > "$T/o7e" 2>&1 ) || rc7=$?
    check "a distlib verify refused mid-round (a tie) fails" yes "$([ "$rc7" != 0 ] && grep -q "more than one stdlib leaf could own it" "$T/o7e" && echo yes || echo no)"
    check "  …and leaves 0 temp dirs (no dlverify* / cpp_)" 0 "$(dirs_for "$T/p7e")"
    check "  …and no dist/.dlverify-<pid> mirror" 0 "$(ls -d "$D7/p/dist"/.dlverify-* 2>/dev/null | wc -l | tr -d ' ')"
    sweep_for "$T/p7e"
else
    echo "  SKIP (named): axis 7 distlib row — cycc_aarch64 did not build from src/main_aarch64.cyr"
fi
# Stand-in compilers beside a private copy of the CLI (the CLI runs the cycc beside it).
mkdir -p "$T/k1" "$T/k2"
cp "$CYRIUS" "$T/k1/cyrius" && cp "$CYRIUS" "$T/k2/cyrius" && chmod +x "$T/k1/cyrius" "$T/k2/cyrius"
printf '#!/bin/sh\ncat > /dev/null\necho partial\nkill -9 $$\n' > "$T/k1/cycc"
printf '#!/bin/sh\necho $$ > "%s/k2.cc"\ncat > /dev/null\necho partial\nexec sleep 60\n' "$T" > "$T/k2/cycc"
chmod +x "$T/k1/cycc" "$T/k2/cycc"
rc7=0; ( cd "$T/proj" && timeout 120 sh -c 'echo $$ > "$0"; exec "$@"' "$T/p7d" "$T/k1/cyrius" check src/ok.cyr > "$T/o7d" 2>&1 ) || rc7=$?
check "the COMPILER killed by a signal fails the check" yes "$([ "$rc7" != 0 ] && echo yes || echo no)"
check "  …and leaves 0 temp dirs" 0 "$(dirs_for "$T/p7d")"
sweep_for "$T/p7d"
# ── The KILL shape (6.7.12). A CLI stopped by SIGTERM / SIGINT / SIGHUP while its compiler runs
# stops that compiler, unlinks the compile's in-flight names (`cpp_<pid>`, `cc_err`, the check's
# `check_<pid>[.tmp.<pid>]`, build's `<out>.tmp.<pid>` beside the output), removes its private dir
# and exits 128+N (cbt/build.cyr `_cbt_sig_fire`). Until 6.7.12 no handler existed: the dir kept
# all three names until check.sh's reaper found the dead pid. SIGKILL cannot be caught, so the
# in-flight names must still be ones the reaper removes. Every run sits under an ABSOLUTE
# $TMPDIR with a trailing slash (`_cbt_tmpbase`), never /tmp. The k2 stand-in records its pid
# and sleeps, so the compile is still running when the signal lands.
TB="$T/tbase"
mkdir -p "$TB"
# A `&` job starts with SIGINT IGNORED, and the CLI keeps an ignore it inherits (nohup's
# contract), so the INT runs put INT back to default with env(1) — Ctrl-C at a terminal reaches
# a foreground CLI that has it at default. Named SKIP (exit 77) where env has no such flag.
K7_INT=yes
env --default-signal=INT true > /dev/null 2>&1 || K7_INT=no
K7_SKIPS=0
# kill_run <tag> <SIG> <verb> [args...] — run the k2 CLI in the background, wait for its compiler,
# record the live dir's names in $T/k7-<tag>.live (and plant $T/k7-<tag>.plant's name in it when
# that file exists), deliver SIG to the CLI, wait. Leaves the CLI's pid in $T/p7-<tag>, its exit
# status in $T/k7-<tag>.rc, and "gone" / "running" for the compiler in $T/k7-<tag>.cc.
kill_run() {
    _kt=$1; _ks=$2; shift 2
    rm -f "$T/k2.cc" "$T/p7-$_kt" "$T/k7-$_kt.rc" "$T/k7-$_kt.live" "$T/k7-$_kt.cc"
    _ke=""
    [ "$_ks" = INT ] && _ke="env --default-signal=INT"
    # (the subshell outlives the CLI it runs, so a signal death is reported to its /dev/null)
    # shellcheck disable=SC2086
    ( _kr=0; cd "$T/proj" && TMPDIR="$TB/" sh -c 'echo $$ > "$0"; exec "$@"' "$T/p7-$_kt" $_ke "$T/k2/cyrius" "$@" > "$T/o7-$_kt" 2>&1 || _kr=$?
      echo "$_kr" > "$T/k7-$_kt.rc" ) 2>/dev/null &
    _kb=$!
    _kw=0
    while [ ! -s "$T/k2.cc" ] && [ "$_kw" -lt 600 ]; do sleep 0.05; _kw=$((_kw + 1)); done
    _kp=$(cat "$T/p7-$_kt" 2>/dev/null || true)
    _kd=""
    for _d in "$TB/cyrius-$_kp" "$TB/cyrius-$_kp"-*; do [ -d "$_d" ] && _kd="$_d"; done
    [ -n "$_kd" ] && ls -A "$_kd" > "$T/k7-$_kt.live"
    [ -n "$_kd" ] && [ -f "$T/k7-$_kt.plant" ] && : > "$_kd/gate_keepme"
    [ -n "$_kp" ] && kill "-$_ks" "$_kp" 2>/dev/null || true
    { wait "$_kb"; } 2>/dev/null || true
    _kc=$(cat "$T/k2.cc" 2>/dev/null || true)
    if [ -n "$_kc" ] && kill -0 "$_kc" 2>/dev/null; then
        echo running > "$T/k7-$_kt.cc"; kill -KILL "$_kc" 2>/dev/null
    else
        echo gone > "$T/k7-$_kt.cc"
    fi
}
# the dirs of tag's pid under $TB / under /tmp
k7_dirs() { _p=$(cat "$T/p7-$1" 2>/dev/null || echo none); n=0; for d in "$2/cyrius-$_p" "$2/cyrius-$_p"-*; do [ -d "$d" ] && n=$((n + 1)); done; echo "$n"; }
# the reaper's own matcher, read out of scripts/check.sh (never a copy of it)
sed -n '/^_CHK_CLI_SCRATCH=/,/^_chk_reap_scratch_dir() {/p' "$ROOT/scripts/check.sh" | sed '$d' > "$T/scratch.sh"
# shellcheck disable=SC1090
. "$T/scratch.sh"
for k7v in check build; do
    for k7s in TERM INT HUP; do
        case $k7s in TERM) k7n=15 ;; INT) k7n=2 ;; HUP) k7n=1 ;; esac
        if [ "$k7s" = INT ] && [ "$K7_INT" = no ]; then
            echo "  SKIP (named): axis 7 $k7v SIGINT row — env(1) has no --default-signal on this host"
            K7_SKIPS=$((K7_SKIPS + 1)); continue
        fi
        k7t="$k7v$k7s"
        if [ "$k7v" = check ]; then kill_run "$k7t" "$k7s" check src/ok.cyr
        else rm -f "$T/proj/build/k7out"*; kill_run "$k7t" "$k7s" build src/ok.cyr build/k7out; fi
        nlive=$(wc -l < "$T/k7-$k7t.live" 2>/dev/null | tr -d ' ')
        check "$k7v SIG$k7s mid-compile — the live dir is under the absolute \$TMPDIR, holding the compile's names (anti-vacuous: ${nlive:-0})" yes \
            "$([ "${nlive:-0}" -ge 2 ] && echo yes || echo no)"
        nbad=0; bad=""
        while IFS= read -r f; do
            _chk_cli_scratch "$f" || { nbad=$((nbad + 1)); bad="$bad $f"; }
        done < "$T/k7-$k7t.live"
        check "  …each one a name check.sh's reaper removes (what a SIGKILL leaves:$(tr '\n' ' ' < "$T/k7-$k7t.live" | sed 's/ $//; s/^/ /'))" 0 "$nbad"
        check "  …the CLI exits 128+$k7n" "$((128 + k7n))" "$(cat "$T/k7-$k7t.rc" 2>/dev/null || echo none)"
        check "  …its private dir is gone" 0 "$(k7_dirs "$k7t" "$TB")"
        check "  …nothing of that pid under /tmp" 0 "$(k7_dirs "$k7t" /tmp)"
        check "  …the compiler it was running is stopped" gone "$(cat "$T/k7-$k7t.cc")"
        if [ "$k7v" = build ]; then
            check "  …and no k7out.tmp.<pid> beside the output" 0 "$(ls "$T/proj/build" | grep -c '^k7out' || true)"
        fi
        for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
    done
done
# `cyrius capacity` forks its own compiler (CYRIUS_STATS=1, stderr into `cap_err`) outside
# compile(): until 6.7.13 neither was tracked, so a SIGTERM left `cap_err` (and the dir) behind and
# the compiler running (issues/2026-10-15-capacity-killed-leaves-cap-err-and-its-compiler-running.md).
kill_run cap TERM capacity src/ok.cyr
check "capacity SIGTERM mid-compile — the live dir holds cap_err and the materialized source (anti-vacuous)" yes \
    "$(grep -qx cap_err "$T/k7-cap.live" 2>/dev/null && grep -q '^cpp_' "$T/k7-cap.live" && echo yes || echo no)"
check "  …the CLI exits 143" 143 "$(cat "$T/k7-cap.rc" 2>/dev/null || echo none)"
check "  …its private dir is gone (no cap_err left)" 0 "$(k7_dirs cap "$TB")"
check "  …the compiler it was running is stopped" gone "$(cat "$T/k7-cap.cc")"
for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
# A local-mode resolve's git queries (`_dep_wt_run`, cbt/deps.cyr) capture git's stderr in `wt_err`,
# which the child creates: a SIGTERM while git runs left it (and the dir) and git running until
# 6.7.13. A stand-in `git` first on PATH (`_dep_wt_run` execs `env … git`) records its pid and
# sleeps on `check-ignore` (no stdout capture: wt_err is the query's only scratch); every other
# query runs the real git. Runs on axis 6's fixture; named SKIP without git.
if [ -n "${P6:-}" ] && [ -d "$P6" ] && command -v git > /dev/null 2>&1; then
    G7GIT=$(command -v git)
    mkdir -p "$T/g7bin"
    # g7_run <tag> <git subcommand to sleep on> <verb...>: the verb in the background, stopped by
    # SIGTERM once the stand-in sleeps; leaves the live names in $T/k7-<tag>.live, the exit status
    # in $T/k7-<tag>.rc and "gone" / "running" for the stand-in git in $T/k7-<tag>.cc.
    g7_run() {
        _gt=$1; _gs=$2; shift 2
        printf '#!/bin/sh\nfor a in "$@"; do\n  if [ "$a" = "%s" ]; then\n    echo $$ > "%s/g7.cc"\n    exec sleep 60\n  fi\ndone\nexec "%s" "$@"\n' "$_gs" "$T" "$G7GIT" > "$T/g7bin/git"
        chmod +x "$T/g7bin/git"
        rm -f "$T/g7.cc" "$T/p7-$_gt" "$T/k7-$_gt.rc" "$T/k7-$_gt.live" "$T/k7-$_gt.cc"
        ( _kr=0; cd "$P6" && HOME="$G6/nohome" CYRIUS_HOME="$H6" CYRIUS_RESOLVED=1 PATH="$T/g7bin:$PATH" TMPDIR="$TB/" \
            sh -c 'echo $$ > "$0"; exec "$@"' "$T/p7-$_gt" "$CYRIUS" "$@" > "$T/o7-$_gt" 2>&1 || _kr=$?
          echo "$_kr" > "$T/k7-$_gt.rc" ) 2>/dev/null &
        _gb=$!
        _gw=0
        while [ ! -s "$T/g7.cc" ] && [ "$_gw" -lt 600 ]; do sleep 0.05; _gw=$((_gw + 1)); done
        _gp=$(cat "$T/p7-$_gt" 2>/dev/null || true)
        ls -A "$TB/cyrius-$_gp" > "$T/k7-$_gt.live" 2>/dev/null || : > "$T/k7-$_gt.live"
        [ -n "$_gp" ] && kill -TERM "$_gp" 2>/dev/null || true
        { wait "$_gb"; } 2>/dev/null || true
        _gc=$(cat "$T/g7.cc" 2>/dev/null || true)
        if [ -n "$_gc" ] && kill -0 "$_gc" 2>/dev/null; then
            echo running > "$T/k7-$_gt.cc"; kill -KILL "$_gc" 2>/dev/null
        else
            echo gone > "$T/k7-$_gt.cc"
        fi
    }
    g7_run gci check-ignore build --local
    check "a --local build SIGTERM'd in its check-ignore query — git's stderr capture is in flight (anti-vacuous)" yes \
        "$(grep -qx wt_err "$T/k7-gci.live" 2>/dev/null && echo yes || echo no)"
    check "  …the CLI exits 143" 143 "$(cat "$T/k7-gci.rc" 2>/dev/null || echo none)"
    check "  …its private dir is gone (no wt_err left)" 0 "$(k7_dirs gci "$TB")"
    check "  …the git it was running is stopped" gone "$(cat "$T/k7-gci.cc")"
    for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
    # A query with a stdout capture: the parent creates it (`wt_out` for the checkout's state line,
    # `ls_remote` for update's tag listing) and the caller unlinks it once read — a SIGTERM while
    # git ran left it, and the dir, until 6.7.13.
    g7_run grp rev-parse build --local
    check "a --local build SIGTERM'd in its rev-parse query — the stdout capture is in flight (anti-vacuous)" yes \
        "$(grep -qx wt_out "$T/k7-grp.live" 2>/dev/null && echo yes || echo no)"
    check "  …the CLI exits 143" 143 "$(cat "$T/k7-grp.rc" 2>/dev/null || echo none)"
    check "  …its private dir is gone (no wt_out / wt_err left)" 0 "$(k7_dirs grp "$TB")"
    check "  …the git it was running is stopped" gone "$(cat "$T/k7-grp.cc")"
    for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
    g7_run gls ls-remote update
    check "update SIGTERM'd in its ls-remote query — the tag listing's capture is in flight (anti-vacuous)" yes \
        "$(grep -qx ls_remote "$T/k7-gls.live" 2>/dev/null && echo yes || echo no)"
    check "  …the CLI exits 143" 143 "$(cat "$T/k7-gls.rc" 2>/dev/null || echo none)"
    check "  …its private dir is gone (no ls_remote / wt_err left)" 0 "$(k7_dirs gls "$TB")"
    check "  …the git it was running is stopped" gone "$(cat "$T/k7-gls.cc")"
    for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
else
    echo "  SKIP (named): axis 7 --local git kill row — git is not installed (axis 6's fixture did not run)"
    K7_SKIPS=$((K7_SKIPS + 1))
fi
# rmdir, never a sweep (axis 4's contract, on the kill path): a file in the live dir that is not
# the compile's survives, and so does the dir; the compile's own names are gone.
: > "$T/k7-plant.plant"
kill_run plant TERM check src/ok.cyr
K7P=""
for d in "$TB/cyrius-$(cat "$T/p7-plant" 2>/dev/null)"*; do [ -d "$d" ] && K7P="$d"; done
check "SIGTERM with a foreign file in the live dir: the file survives, and its dir" yes \
    "$([ -n "$K7P" ] && [ -f "$K7P/gate_keepme" ] && echo yes || echo no)"
check "  …and it is the only name left (the compile's are unlinked)" gate_keepme "$(ls -A "$K7P" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
[ -n "$K7P" ] && rm -rf "$K7P"
# An ignore inherited at start stays (nohup): SIGHUP ignored -> the CLI keeps compiling; the
# SIGTERM that follows still cleans up.
rm -f "$T/k2.cc" "$T/p7-nohup"
( cd "$T/proj" && trap '' HUP; TMPDIR="$TB/" sh -c 'echo $$ > "$0"; exec "$@"' "$T/p7-nohup" "$T/k2/cyrius" check src/ok.cyr > "$T/o7-nohup" 2>&1 ) 2>/dev/null &
k7b=$!
w=0
while [ ! -s "$T/k2.cc" ] && [ "$w" -lt 600 ]; do sleep 0.05; w=$((w + 1)); done
k7p=$(cat "$T/p7-nohup" 2>/dev/null || true)
[ -n "$k7p" ] && kill -HUP "$k7p" 2>/dev/null || true
sleep 0.5
check "SIGHUP ignored at start stays ignored: the CLI is still compiling after a SIGHUP" yes \
    "$([ -n "$k7p" ] && kill -0 "$k7p" 2>/dev/null && echo yes || echo no)"
[ -n "$k7p" ] && kill -TERM "$k7p" 2>/dev/null || true
{ wait "$k7b"; } 2>/dev/null || true
check "  …and the SIGTERM after it still leaves no dir" 0 "$(k7_dirs nohup "$TB")"
k7c=$(cat "$T/k2.cc" 2>/dev/null || true)
[ -n "$k7c" ] && kill -KILL "$k7c" 2>/dev/null || true
for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
# A distlib verify SIGTERM'd mid-round: the signal is FORWARDED to its forked per-target
# children, whose own handlers stop their compilers and unlink their `cpp_<pid>` /
# `dlverifyout<t>.tmp.<pid>`; the parent then unlinks `dlverifyerr<t>`. Stand-in compilers for
# every target (cycc and cycc_aarch64) sleep; each records its pid.
D7K="$T/d7k"
if [ -d "$D7/home/versions/$V7/lib" ]; then
    mkdir -p "$D7K/bin" "$D7K/p/src"
    cp "$CYRIUS" "$D7K/bin/cyrius"
    printf '#!/bin/sh\necho $$ >> "%s/d7k.cc"\ncat > /dev/null\necho partial\nexec sleep 60\n' "$T" > "$D7K/bin/cycc"
    cp "$D7K/bin/cycc" "$D7K/bin/cycc_aarch64"
    chmod +x "$D7K/bin/cyrius" "$D7K/bin/cycc" "$D7K/bin/cycc_aarch64"
    printf '[package]\nname = "d7k"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$V7" > "$D7K/p/cyrius.cyml"
    printf 'fn d7k_a(): i64 { return 1; }\n' > "$D7K/p/src/lib.cyr"
    rm -f "$T/d7k.cc" "$T/p7-dl"
    ( _kr=0; cd "$D7K/p" && CYRIUS_HOME="$D7/home" CYRIUS_RESOLVED=1 TMPDIR="$TB/" sh -c 'echo $$ > "$0"; exec "$@"' "$T/p7-dl" "$D7K/bin/cyrius" distlib > "$T/o7-dl" 2>&1 || _kr=$?
      echo "$_kr" > "$T/k7-dl.rc" ) 2>/dev/null &
    k7b=$!
    w=0
    while [ "$(wc -l 2>/dev/null < "$T/d7k.cc" || echo 0)" -lt 6 ] && [ "$w" -lt 600 ]; do sleep 0.05; w=$((w + 1)); done
    k7p=$(cat "$T/p7-dl" 2>/dev/null || true)
    nlive=$(ls -A "$TB/cyrius-$k7p" 2>/dev/null | wc -l | tr -d ' ')
    check "distlib SIGTERM mid-round — the verify's six compiles are running, their scratch in flight (anti-vacuous: $nlive names)" yes \
        "$([ "$(wc -l 2>/dev/null < "$T/d7k.cc" || echo 0)" -ge 6 ] && [ "$nlive" -ge 12 ] && echo yes || echo no)"
    nmir=$(find "$D7K/p/dist" -path '*/.dlverify-*' -type f 2>/dev/null | wc -l | tr -d ' ')
    check "  …its stdlib mirror is in the project's dist/, entry.cyr beside it (anti-vacuous: $nmir files)" yes \
        "$([ "$nmir" -ge 20 ] && [ -f "$D7K/p/dist/.dlverify-$k7p/entry.cyr" ] && echo yes || echo no)"
    [ -n "$k7p" ] && kill -TERM "$k7p" 2>/dev/null || true
    { wait "$k7b"; } 2>/dev/null || true
    check "  …the CLI exits 143" 143 "$(cat "$T/k7-dl.rc" 2>/dev/null || echo none)"
    check "  …its private dir is gone (no cpp_ / dlverify* left by the parent or a child)" 0 "$(k7_dirs dl "$TB")"
    # 6.7.13: the mirror is a scratch TREE the handler removes (cbt/sigclean.cyr `_cbt_sig_tree_set`);
    # until then a kill left all of it (issues/2026-10-15-distlib-verify-killed-leaves-its-stdlib-mirror-in-dist.md).
    check "  …and no dist/.dlverify-<pid> mirror is left in the project" 0 "$(ls -d "$D7K/p/dist"/.dlverify-* 2>/dev/null | wc -l | tr -d ' ')"
    nrun=0
    for c in $(cat "$T/d7k.cc" 2>/dev/null); do kill -0 "$c" 2>/dev/null && { nrun=$((nrun + 1)); kill -KILL "$c" 2>/dev/null; }; done
    check "  …every target's compiler is stopped" 0 "$nrun"
    for d in "$TB"/cyrius-*; do [ -d "$d" ] && rm -rf "$d"; done
else
    echo "  SKIP (named): axis 7 distlib kill row — the distlib row above did not stage its snapshot (cycc_aarch64 did not build)"
    K7_SKIPS=$((K7_SKIPS + 1))
fi

echo ""
if [ "$fails" = "0" ]; then
    if [ "$K7_SKIPS" -gt 0 ]; then
        echo "SKIP: cli-temp-dir-no-leak — $K7_SKIPS axis 7 row(s) above could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"
        exit 77
    fi
    echo "PASS: cli-temp-dir-no-leak — no CLI exit path leaves its private temp directory behind"
    exit 0
fi
echo "FAIL: cli-temp-dir-no-leak — $fails assertion(s) failed"
exit 1
