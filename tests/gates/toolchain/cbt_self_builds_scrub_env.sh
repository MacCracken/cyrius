#!/bin/sh
# tests/gates/toolchain/cbt_self_builds_scrub_env.sh — 6.7.11
#
# The CLI's own SELF-BUILDS never inherit a compile-mode switch — CYRIUS_POISON, CYRIUS_BOUNDS,
# CYRIUS_COVERAGE, CYRIUS_COVERAGE_FILE — and the user's own compile still does.
#
# THE FILED DEFECT (docs/development/issues/archived/2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md,
# with its 6.7.10 addendum). Two CLI paths build a compiler or tool from the checkout and KEEP it,
# and both passed the CLI's whole environment (`_envp`):
#   * `cyrius pulsar` — the raw compiles of src/main.cyr (twice) over the TRACKED build/cycc, the
#     aarch64 cross and the native-aarch64 compiler, compile()'s tool builds, then the install step
#     (`scripts/install.sh --refresh-only` copies build/cycc into the store as it is). Under an
#     inherited CYRIUS_POISON=1 both stages were poison-mode compilers, they agreed, and pulsar
#     installed one; under CYRIUS_COVERAGE=1 every stage was refused or instrumented.
#   * the cx arc's on-demand builds (`_cx_jit_build`): src/main_cx.cyr -> build/cycc_cx on the first
#     `cyrius build --target=cx`, programs/cxvm.cyr -> build/cxvm on the first `cyrius run x.cyx` —
#     a POSIX execve with `_envp`, and on Windows a cmd.exe spawn that inherits the process's own
#     environment (where compile()'s Windows arm also WRITES CYRIUS_POISON / CYRIUS_BOUNDS for
#     `--poison` / `--bounds`).
# The fix: cbt/core.cyr `_envp_self_build()` (`_envp` minus the four); `cmd_pulsar` sets `_envp` to
# it at entry; `_cx_jit_build`'s POSIX child execs with it; its Windows arm saves, clears and
# restores the four around the spawn (`_win_mode_switches_clear` / `_restore`).
#
# HOW — the filed repro, widened (never a real `cyrius pulsar` in the tree: it rewrites build/cycc
# and the store). The CLI is built from THIS tree's cbt/ into a mktemp dir; each probe runs in a
# scratch "repo" whose compiler is a STUB that logs the four variables it sees, tagged with the
# `MARK_<what>` word of the source it was fed, and emits itself (so pulsar's stage 1 == stage 2 and
# every tool it "builds" is the stub again). HOME / CYRIUS_HOME are throwaways and the scratch
# repo's scripts/install.sh is a stub that only logs: no store is touched.
#   P  `cyrius pulsar` with all four inherited: the two src/main.cyr stages, the aarch64 cross, the
#      native compiler (built BY the cross, itself a stub), a tool (programs/cyrfmt.cyr) and the CLI
#      (cbt/cyrius.cyr) through compile(), and the install step each read all four unset.
#   C  `cyrius build --target=cx x.cyr`: the cycc_cx build reads them unset, the user's x.cyr keeps
#      all four; `cyrius run out.cyx`: the cxvm build reads them unset.
#   S  (6.7.12) the self-host VERIFIERS, `cyrius self` and `cyrius soak 1`, with all four inherited:
#      both steps of each read all four unset, and soak's test leg (the user's .tcyr through
#      compile()) keeps all four (issues/archived/2026-10-14-cyrius-self-and-soak-inherit-compile-mode-switches.md).
#   W  (wine) the PE CLI with a PE stub compiler: the cycc_cx self-build reads them unset, and the
#      user's x.cyr compiled next IN THE SAME PROCESS still sees all four (they were restored); the
#      cxvm build likewise unset; (6.7.12) `cyrius.exe self` and `cyrius.exe soak 1`: both steps
#      unset, soak's test leg keeps all four. wine is not hardware: the cass leg is the real Windows.
#
# MUTATION PROOF (scratch copies of the tree with cbt/ mutated, run through THIS gate; GREEN 17/17
# on the real tree):
#   M0  the fix reverted (cbt/core.cyr, pulsar.cyr, build.cyr as before it)   RED 10: P1-P4, C1, C3,
#                                                                             W1, W3
#   M1  pulsar raw: `_envp = _envp_self_build()` moved to after step 2         RED 3: P1, P2 x2
#   M2  pulsar tool compile: `_envp` put back before step 3                    RED 3: P3 x2, P4
#   M3  cx POSIX: `_cx_jit_build`'s child execs with `_envp`                  RED 2: C1, C3
#   M4  cx PE: no clear / restore around `_win_compile_spawn`                 RED 2: W1, W3
#   M5  cx PE: cleared, never restored                                        RED 1: W2
# 6.7.12 (the S axis and W4-W8; GREEN 29/29 on the real tree):
#   M0' the 6.7.12 fix reverted (cbt/commands.cyr, build.cyr, pulsar.cyr)      RED 4: S1, S3, W5, W7
#   M6  cmd_self: no `_envp = _envp_self_build()`                              RED 1: S1
#   M7  cmd_soak: the steps exec with `_envp` (no swap)                        RED 1: S3
#   M8  cmd_soak: `_envp` scrubbed for the whole run (the test leg too)        RED 1: S4
#   M9  _win_cmd_self: no clear / restore around its two spawns               RED 1: W5
#   M10 _pulsar_raw_compile's PE arm: no clear / restore (soak's steps)       RED 1: W7
set -u
G=cbt_self_builds_scrub_env
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G — no compiler at $CC"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $G — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$T/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
fails=0
checks=0
skips=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
UNSET="POISON=unset BOUNDS=unset COVERAGE=unset COVFILE=unset"
SET="POISON=1 BOUNDS=1 COVERAGE=1 COVFILE=cov.out"
# logged LOG MARK -> the variables every line tagged MARK saw, one distinct reading per line
logged() { { grep "^MARK_$2 " "$1" 2> /dev/null || :; } | sed "s/^MARK_$2 //" | sort -u | paste -sd'|' -; }
nlines() { { grep -c "^MARK_$2 " "$1" 2> /dev/null || :; } | head -n 1; }

# THIS tree's CLI (never build/cyrius, the store or PATH).
if ! "$CC" < cbt/cyrius.cyr > "$T/cyrius" 2> "$T/cli.err" || [ "$(wc -c < "$T/cyrius" | tr -d ' ')" -lt 100000 ]; then
    echo "FAIL: $G — cbt/cyrius.cyr does not build: $(grep -m1 -i error "$T/cli.err")"; exit 1
fi
chmod +x "$T/cyrius"

# The POSIX stub compiler: logs `MARK_<what> POISON=… BOUNDS=… COVERAGE=… COVFILE=…` and emits itself.
mkstub() {
    mkdir -p "$1/build" "$1/src"
    cat > "$1/build/cycc" <<'EOF'
#!/bin/sh
m=$(grep -o 'MARK_[a-z0-9]*' | head -n 1)
echo "${m:-MARK_none} POISON=${CYRIUS_POISON-unset} BOUNDS=${CYRIUS_BOUNDS-unset} COVERAGE=${CYRIUS_COVERAGE-unset} COVFILE=${CYRIUS_COVERAGE_FILE-unset}" >> "$STUBLOG"
cat "$0"
EOF
    chmod +x "$1/build/cycc"
}
# the four switches, inherited from the caller's shell
inherit() { env CYRIUS_POISON=1 CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE=cov.out "$@"; }

echo "== P: cyrius pulsar =="
P="$T/p"; mkstub "$P"; mkdir -p "$P/programs" "$P/cbt" "$P/scripts" "$T/home"
echo '# MARK_main' > "$P/src/main.cyr"
echo '# MARK_aarch64' > "$P/src/main_aarch64.cyr"
echo '# MARK_native' > "$P/src/main_aarch64_native.cyr"
echo '# MARK_cyrfmt' > "$P/programs/cyrfmt.cyr"
echo '# MARK_cli' > "$P/cbt/cyrius.cyr"
echo 6.7.11 > "$P/VERSION"
cat > "$P/scripts/install.sh" <<'EOF'
echo "MARK_install POISON=${CYRIUS_POISON-unset} BOUNDS=${CYRIUS_BOUNDS-unset} COVERAGE=${CYRIUS_COVERAGE-unset} COVFILE=${CYRIUS_COVERAGE_FILE-unset}" >> "$STUBLOG"
EOF
ino0=$(ls -i "$P/build/cycc" | awk '{print $1}')
rc=0
(cd "$P" && inherit STUBLOG="$T/p.log" HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" PATH=/usr/bin:/bin \
    timeout 120 "$T/cyrius" pulsar) > "$T/p.out" 2>&1 || rc=$?
check "P0 pulsar finishes (its install step is a stub)" 0 "$rc"
check "P1 two src/main.cyr stages ran" 2 "$(nlines "$T/p.log" main)"
check "P1 the src/main.cyr stages read every switch unset" "$UNSET" "$(logged "$T/p.log" main)"
check "P2 the aarch64 cross build" "$UNSET" "$(logged "$T/p.log" aarch64)"
check "P2 the native-aarch64 build (run by the cross it just built)" "$UNSET" "$(logged "$T/p.log" native)"
check "P3 a tool through compile() (programs/cyrfmt.cyr)" "$UNSET" "$(logged "$T/p.log" cyrfmt)"
check "P3 the CLI through compile() (cbt/cyrius.cyr)" "$UNSET" "$(logged "$T/p.log" cli)"
check "P4 the install step" "$UNSET" "$(logged "$T/p.log" install)"
ino1=$(ls -i "$P/build/cycc" | awk '{print $1}')
[ "$ino1" != "$ino0" ] && ino1=replaced
check "P5 pulsar installed its (stub) self-build over build/cycc (a new inode: renamed in)" replaced "$ino1"

echo "== C: the cx arc's on-demand builds =="
C="$T/c"; mkstub "$C"; mkdir -p "$C/programs"
echo '# MARK_cx' > "$C/src/main_cx.cyr"
echo '# MARK_cxvm' > "$C/programs/cxvm.cyr"
echo '# MARK_user' > "$C/x.cyr"
rc=0
(cd "$C" && inherit STUBLOG="$T/c.log" HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" PATH="$C/build:/usr/bin:/bin" \
    timeout 120 "$T/cyrius" build --target=cx x.cyr out.cyx) > "$T/c.out" 2>&1 || rc=$?
check "C0 build --target=cx exits 0" 0 "$rc"
check "C1 the cycc_cx build (src/main_cx.cyr) reads every switch unset" "$UNSET" "$(logged "$T/c.log" cx)"
check "C2 the user's x.cyr, compiled by it, keeps all four" "$SET" "$(logged "$T/c.log" user)"
(cd "$C" && inherit STUBLOG="$T/c.log" HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" PATH="$C/build:/usr/bin:/bin" \
    timeout 120 "$T/cyrius" run out.cyx) > "$T/r.out" 2>&1 || :
check "C3 the cxvm build (programs/cxvm.cyr) reads every switch unset" "$UNSET" "$(logged "$T/c.log" cxvm)"

echo "== S: the self-host verifiers, cyrius self and cyrius soak =="
# src/main.cyr is the x86_64 Linux self-host source (`_self_host_src`); the stub emits itself, so
# step 2 (the stub's copy) emits the same bytes and the verdict is a PASS. The test binary soak
# runs is the stub again: it logs MARK_none and exits 0.
SV="$T/s"; mkstub "$SV"; mkdir -p "$SV/tests/tcyr"
echo '# MARK_self' > "$SV/src/main.cyr"
echo '# MARK_utest' > "$SV/tests/tcyr/u.tcyr"
rc=0
(cd "$SV" && inherit STUBLOG="$T/s_self.log" HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" PATH=/usr/bin:/bin \
    timeout 120 "$T/cyrius" self < /dev/null) > "$T/s_self.out" 2>&1 || rc=$?
check "S0 cyrius self exits 0 with its PASS line" "0 1" "$rc $(grep -c 'PASS: cycc==cycc byte-identical' "$T/s_self.out")"
check "S1 cyrius self: both steps ran" 2 "$(nlines "$T/s_self.log" self)"
check "S1 cyrius self: both steps read every switch unset" "$UNSET" "$(logged "$T/s_self.log" self)"
rc=0
(cd "$SV" && inherit STUBLOG="$T/s_soak.log" HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" PATH=/usr/bin:/bin \
    timeout 120 "$T/cyrius" soak 1 < /dev/null) > "$T/s_soak.out" 2>&1 || rc=$?
check "S2 cyrius soak 1 exits 0, its one iteration passed" "0 1" "$rc $(grep -c 'soak complete: 1/1 passed' "$T/s_soak.out")"
check "S3 cyrius soak 1: both steps ran" 2 "$(nlines "$T/s_soak.log" self)"
check "S3 cyrius soak 1: both steps read every switch unset" "$UNSET" "$(logged "$T/s_soak.log" self)"
check "S4 cyrius soak 1: its test leg (the user's .tcyr through compile()) keeps all four" "$SET" "$(logged "$T/s_soak.log" utest)"

echo "== W: the PE arm, under wine =="
if ! command -v wine > /dev/null 2>&1 || ! command -v winepath > /dev/null 2>&1; then
    echo "  SKIP (named): the W rows — wine is not installed; the PE arm is covered only by the cass leg"
    skips=$((skips + 1))
else
    # A PRIVATE prefix, and wine's own HOME / XDG_CACHE_HOME under $T (a fresh prefix writes $HOME/.cache).
    export WINEPREFIX="$WP" HOME="$T/whome" XDG_CACHE_HOME="$T/whome/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    mkdir -p "$T/whome" "$T/w/home/bin" "$T/w/c/src" "$T/w/c/programs" "$T/w/log"
    "$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null && chmod +x "$T/cc_win" \
        || { echo "FAIL: $G — could not build the PE cross compiler"; exit 1; }
    "$T/cc_win" < cbt/cyrius.cyr > "$T/w/home/bin/cyrius.exe" 2> "$T/wcli.err" && [ -s "$T/w/home/bin/cyrius.exe" ] \
        || { echo "FAIL: $G — cbt/cyrius.cyr does not build for PE: $(grep -m1 -i error "$T/wcli.err")"; exit 1; }
    wine cmd /c exit 0 > /dev/null 2>&1 || true   # create the prefix before winepath needs it
    LOGW=$(winepath -w "$T/w/log" 2> /dev/null)
    SELFW=$(winepath -w "$T/w/home/bin/cycc.exe" 2> /dev/null)
    [ -n "$LOGW" ] && [ -n "$SELFW" ] || { echo "FAIL: $G — winepath could not map the stub's paths"; exit 1; }
    LOGC=$(printf '%s' "$LOGW" | sed 's/\\/\\\\/g')
    SELFC=$(printf '%s' "$SELFW" | sed 's/\\/\\\\/g')
    # The PE stub compiler: reads the source on stdin for its MARK_ word, writes
    # `<log>\<word>.log` with the four variables (GetEnvironmentVariableA), and emits a copy of
    # itself (so the cycc_cx it "builds" is the stub again, for the user's compile).
    cat > "$T/wstub.cyr" <<CYR
include "lib/io.cyr"
fn _wv(out, o, tag, name, eb): i64 {
    var tl = strlen(tag);
    memcpy(out + o, tag, tl);
    o = o + tl;
    var n = syscall(0xF015, name, eb, 512);
    if (n == 0) { memcpy(out + o, "unset", 5); return o + 5; }
    memcpy(out + o, eb, n);
    return o + n;
}
fn main(): i64 {
    alloc_init();
    var src = alloc(70000);
    var sn = 0;
    var r = sys_read(0, src, 65536);
    while (r > 0 && sn < 65536) {
        sn = sn + r;
        r = sys_read(0, src + sn, 65536 - sn);
    }
    var w = alloc(64);
    var wl = 0;
    var i = 0;
    while (i + 5 <= sn && wl == 0) {
        if (memeq(src + i, "MARK_", 5) == 1) {
            var j = i + 5;
            while (j < sn && wl < 32) {
                var c = load8(src + j);
                if ((c >= 97 && c <= 122) || (c >= 48 && c <= 57)) { store8(w + wl, c); wl = wl + 1; j = j + 1; }
                else { break; }
            }
            if (wl == 0) { i = i + 1; }
        } else { i = i + 1; }
    }
    if (wl == 0) { memcpy(w, "none", 4); wl = 4; }
    store8(w + wl, 0);
    var eb = alloc(600);
    var lp = alloc(1024);
    var ll = strlen("$LOGC");
    memcpy(lp, "$LOGC", ll);
    store8(lp + ll, 92);
    memcpy(lp + ll + 1, w, wl);
    memcpy(lp + ll + 1 + wl, ".log", 4);
    store8(lp + ll + 5 + wl, 0);
    var out = alloc(8192);
    var o = file_read_all(lp, out, 4096);   # append: a second step on the same word adds a line
    if (o < 0) { o = 0; }
    o = _wv(out, o, "POISON=", "CYRIUS_POISON", eb);
    o = _wv(out, o, " BOUNDS=", "CYRIUS_BOUNDS", eb);
    o = _wv(out, o, " COVERAGE=", "CYRIUS_COVERAGE", eb);
    o = _wv(out, o, " COVFILE=", "CYRIUS_COVERAGE_FILE", eb);
    store8(out + o, 10);
    o = o + 1;
    file_write_all(lp, out, o);
    var me = alloc(4194304);
    var mn = file_read_all("$SELFC", me, 4194304);
    if (mn > 0) { sys_write(1, me, mn); }
    return 0;
}
var rr = main();
syscall(60, rr);
CYR
    "$T/cc_win" < "$T/wstub.cyr" > "$T/w/home/bin/cycc.exe" 2> "$T/wstub.err" && [ -s "$T/w/home/bin/cycc.exe" ] \
        || { echo "FAIL: $G — the PE stub compiler does not build:"; tail -3 "$T/wstub.err"; exit 1; }
    echo '# MARK_cx' > "$T/w/c/src/main_cx.cyr"
    echo '# MARK_cxvm' > "$T/w/c/programs/cxvm.cyr"
    echo '# MARK_user' > "$T/w/c/x.cyr"
    wlog() { if [ -f "$T/w/log/$1.log" ]; then tr -d '\r' < "$T/w/log/$1.log" | sort -u | paste -sd'|' -; else echo "(never ran)"; fi; }
    wlines() { if [ -f "$T/w/log/$1.log" ]; then wc -l < "$T/w/log/$1.log" | tr -d ' '; else echo 0; fi; }
    rc=0
    (cd "$T/w/c" && inherit CYRIUS_HOME="$T/w/home" CYRIUS_RESOLVED=1 timeout 300 wine "$T/w/home/bin/cyrius.exe" build --target=cx x.cyr out.cyx) > "$T/w.out" 2>&1 || rc=$?
    check "W0 cyrius.exe build --target=cx exits 0" 0 "$rc"
    check "W1 the cycc_cx self-build reads every switch unset" "$UNSET" "$(wlog cx)"
    check "W2 the user's x.cyr next, in the same process, sees all four again (restored)" "$SET" "$(wlog user)"
    (cd "$T/w/c" && inherit CYRIUS_HOME="$T/w/home" CYRIUS_RESOLVED=1 timeout 300 wine "$T/w/home/bin/cyrius.exe" run out.cyx) > "$T/wr.out" 2>&1 || :
    check "W3 the cxvm self-build reads every switch unset" "$UNSET" "$(wlog cxvm)"
    # 6.7.12 — the PE self-host verifiers (src/main_win.cyr is the PE self-host source).
    mkdir -p "$T/w/c/tests/tcyr"
    echo '# MARK_wself' > "$T/w/c/src/main_win.cyr"
    rc=0
    (cd "$T/w/c" && inherit CYRIUS_HOME="$T/w/home" CYRIUS_RESOLVED=1 timeout 300 wine "$T/w/home/bin/cyrius.exe" self < /dev/null) > "$T/ws.out" 2>&1 || rc=$?
    check "W4 cyrius.exe self exits 0 with its PASS line" "0 1" "$rc $(tr -d '\r' < "$T/ws.out" | grep -c 'PASS: cycc==cycc byte-identical')"
    check "W5 cyrius.exe self: both steps read every switch unset" "2 $UNSET" "$(wlines wself) $(wlog wself)"
    rm -f "$T/w/log/wself.log"
    echo '# MARK_wutest' > "$T/w/c/tests/tcyr/u.tcyr"
    rc=0
    (cd "$T/w/c" && inherit CYRIUS_HOME="$T/w/home" CYRIUS_RESOLVED=1 timeout 300 wine "$T/w/home/bin/cyrius.exe" soak 1 < /dev/null) > "$T/wk.out" 2>&1 || rc=$?
    check "W6 cyrius.exe soak 1 exits 0, its one iteration passed" "0 1" "$rc $(tr -d '\r' < "$T/wk.out" | grep -c 'soak complete: 1/1 passed')"
    check "W7 cyrius.exe soak 1: both steps read every switch unset" "2 $UNSET" "$(wlines wself) $(wlog wself)"
    check "W8 cyrius.exe soak 1: its test leg (the user's .tcyr) keeps all four" "$SET" "$(wlog wutest)"
    _wine_down
fi

echo ""
if [ "$fails" -gt 0 ]; then
    for f in p.out c.out s_self.out s_soak.out w.out ws.out wk.out; do [ -s "$T/$f" ] && { echo "  ($f, first lines)"; sed -n '1,6p' "$T/$f" | sed 's/^/    /'; }; done
    echo "FAIL: $G — $fails of $checks checks failed"
    exit 1
fi
if [ "$skips" -gt 0 ]; then
    echo "SKIP: $G — $skips leg(s) could not run here (named above); all $checks checks that ran passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS: $G — $checks checks"
exit 0
