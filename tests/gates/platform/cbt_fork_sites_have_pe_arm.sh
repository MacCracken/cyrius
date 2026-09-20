#!/bin/sh
# tests/gates/platform/cbt_fork_sites_have_pe_arm.sh — v6.6.6
#
# EVERY `sys_fork()` site in `cbt/` must be unreachable on PE, behind an arm that either
# spawns through CreateProcessW or refuses BY NAME. Never a silent nothing.
#
# THE DEFECT. `lib/syscalls_windows.cyr` defines `fn sys_fork(): i64 { return 0 - 1; }`
# and `sys_waitpid` the same. A fork/wait written for POSIX therefore does not fail on
# Windows — it SUCCEEDS WRONGLY: `pid` is -1, so the parent takes the `pid != 0` branch,
# "waits" on nothing, and decodes an UNINITIALISED stack slot as the child's status.
# Whenever that garbage happens to read as WIFEXITED with status 0, the caller reports
# success for a child that never existed. Of the 17 sites in cbt/, five were armed before 6.6.6
# (the compile spawn, the tool spawn, the program run and the cx run at 6.6.5/6.0.85, plus
# `_sha256sum_file`'s `exec_capture` from CVE-14) and TWELVE were not. Measured on REAL cass at
# 6.6.5, before this gate's fix:
#
#   cyrius self                -> exit 0, prints "=== Self-Hosting Check ===" and NOTHING
#                                 else. A green self-host verdict for a self-host that
#                                 never ran. Still exit 0 with src\main_win.cyr DELETED.
#   cyrius build --target=cx   -> "FAIL", exit 1, no reason (cycc_cx.exe ships on Windows
#                                 and the tarball's own comment claims this verb works).
#   cyrius build --target=js   -> "FAIL", exit 1, no reason.
#   cyrius capacity            -> "no stats output from compiler" for a compiler that was
#                                 never started.
#   git deps                   -> "git clone failed for dep 'X' from <url>" — a statement
#                                 about git that git never made.
#
# WHY A DERIVED GATE AND NOT A LIST. The site list is read out of `cbt/*.cyr` on every
# run, so a NEW fork site cannot be added without an arm: it appears in axis 1 the moment
# it is written. Same shape as `directive_fork_parity.sh` for the seven compiler forks.
#
# ⭐ AXIS 2 IS THE ONE A LAZY FIX CANNOT SATISFY. Axis 1 is satisfied by ANY
# `#ifdef CYRIUS_TARGET_WIN ... return 0; #endif` — which is precisely the silent nothing
# the roadmap item forbids, and it would read greener than the bug. So axis 2 requires
# each arm to NAME what it does: a `_win_*` spawn helper, a named-error emitter
# (`_err` / `_err_ctx` / `_ew`), or the `_git_exec_available()` platform question.
#
# ⭐ AXIS 3 PROVES THE ARMS ARE WIRED IN, not merely written. It cross-builds the CLI for
# PE and requires every `_win_*` handler axis 2 found to be REACHABLE in that binary
# (cycc's own DCE says which fns are not). An arm behind a condition that is never true,
# or a helper nothing calls, shows up here and nowhere else. Its own anti-vacuous half
# plants a helper no one calls and requires the detector to report THAT one unreachable.
#
# ⭐ AXIS 4 RUNS THE VERBS. Static text cannot tell a working spawn from a broken one.
# Its negative control is the important row: with `src/main_win.cyr` removed, `cyrius
# self` must FAIL BY NAME — the 6.6.5 binary exits 0 with no verdict in exactly that
# situation, on wine AND on real cass, so this row is what separates the fix from the
# defect. SKIPs loudly without wine; wine is NOT hardware.
#
# ⭐ AXIS 6 — NO ARM BUILDS ITS COMMAND LINE IN A FIXED BUFFER (6.6.6 review). The first
# cut of `_win_capacity_spawn` used a fixed 16 KiB allocation with unchecked appends — the
# exact shape `_win_cmdline` had been changed away from one release earlier ("a fixed
# buffer is a heap overwrite waiting for a large enough project"). The rule is therefore
# DERIVED from the sources here rather than fixed once by hand, so the next builder cannot
# be written that way either.
#
# ⭐ AXIS 5 AND AXIS 4'S SOAK ROWS — AN ARM MUST NOT LIE ABOUT THE RESULT (6.6.6 review).
# A fix that arms a fork and then reports a verdict it did not earn is the defect wearing
# the fix's clothes, and the first cut did it twice:
#   * `cmd_soak`'s new arm self-hosted from `src/main.cyr` — the LINUX fork — so step 2
#     page-faulted and every iteration printed "self-host output differs", blaming the
#     self-host for a source-selection bug; and it threw the spawn's exit code away, so
#     the byte compare answered for a child that had died. Axis 4 pins both.
#   * `_win_files_equal` returned 1 for two EMPTY files, so `cyrius self` could print
#     "PASS: cycc==cycc byte-identical" over two zero-byte outputs — and cass is exactly
#     the host that produces zero-byte outputs (Defender quarantines an unsigned .exe
#     mid-write). Axis 5 compiles the REAL helper, extracted from cbt/build.cyr, for this
#     host and proves it fails closed.
#
# REAL-HARDWARE LEDGER (cass, Windows 11, 2026-09-19, C:\cyrius-tests\bite9-probe,
# removed afterwards). old = the CLI cross-built from this tree's parent commit,
# new = from the fixed tree; cycc.exe / cycc_cx.exe / cxvm.exe cross-built from
# src/main_win.cyr, src/main_cx.cyr, programs/cxvm.cyr:
#   build --target=cx   old rc=1 "FAIL", no .cyx   ->  new rc=0 "OK", p_new.cyx written
#   run <that .cyx>                                    new rc=5 (the program's own code)
#   build --target=js   old rc=1 "FAIL", no reason ->  new rc=1 + "error: build
#                                                      --target=js is not available on
#                                                      Windows" + the three-line reason
#   self                old rc=0, header only      ->  new rc=0 "PASS: cycc==cycc
#                                                      byte-identical" (a REAL PE
#                                                      self-host from src/main_win.cyr)
#   self, main_win.cyr renamed away
#                       old rc=0, header only      ->  new rc=1 "error: self-host: the
#                                                      Windows compiler source is
#                                                      missing: src/main_win.cyr"
#   capacity            old rc=1 "no stats"        ->  new rc=1 "no stats" + the named
#                                                      reason (CYRIUS_STATS is read by
#                                                      _read_env, which reads
#                                                      /proc/self/environ — a COMPILER
#                                                      gap, not a spawn one)
#
# MUTATION PROOF (6.6.6, scratch trees built with `git archive` + the fixed cbt/ overlaid
# — RED then GREEN; every mutation is SEMANTIC, none is a message):
#   M1  drop `_emit_cx`'s `#ifdef CYRIUS_TARGET_WIN` arm      axes 1+4 RED (4 assertions:
#                                                             1 UNARMED site; cx emit
#                                                             fails, no .cyx, wrong code)
#   M2  `cmd_self`'s arm body -> `return 0;`                  axes 2+3+4 RED (4: silent
#                                                             arm, _win_cmd_self dead,
#                                                             self exits 0 with no source)
#   M3  `cap_rc = _win_capacity_spawn(...)` -> `cap_rc = 0;`  axes 2+3 RED (silent arm,
#                                                             _win_capacity_spawn dead)
#   M4  restore the 6.6.5 `cmd_self` (no PE arm at all)       axes 1+3+4 RED (4)
#   — added with axes 5/6 at the 6.6.6 review, same recipe —
#   M5  `_win_capacity_spawn` -> `var wbuf = alloc(16384);`   axis 6 RED alone (1: the
#                                                             builder is reported FIXED)
#   M6  drop `_win_files_equal`'s `if (seen <= 0)` floor      axis 5 RED (2: empty vs
#                                                             empty answers 1, and the
#                                                             axis's own mutant control
#                                                             sees no difference to make)
#   M7  `soak_src = _self_host_src()` -> `"src/main.cyr"`     axis 4 RED (1: soak names
#                                                             the Linux fork)
#   M8  drop soak's `if (src2 != 0)` exit-code check          axis 4 RED (2: no "exited 3",
#                                                             and "output differs" back)
#   real tree -> all axes GREEN, 17 sites.
#
# ⚠ THE LEDGER FOUND TWO DEFECTS IN THIS GATE, both of which made a mutant read GREEN, and
# both are written into the code below rather than quietly fixed: the comment strip ate
# `#endif` (so every arm stayed open and the scan saw 1 site of 17), and axis 2's shell
# glob `*_win_*` matched the LOCAL `cap_win_rc`, admitting M3's empty arm. A gate whose
# own detector is untested is the thing it is supposed to prevent.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
[ -x "$ROOT/build/cycc" ] || { echo "FAIL: cbt-fork-sites-have-pe-arm — build/cycc not built"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cbt_fork_sites_have_pe_arm: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# ⚠ THE KILL IS SCOPED TO *OUR* PREFIX, and only once axis 4 has created it. The first
# cut ran a bare `wineserver -k` from the trap while `WINEPREFIX` was exported inside
# axis 4's else-branch: if axis 3 failed, axis 4 bailed out before that export and the
# trap then killed the DEFAULT prefix's server — i.e. another lane's wine jobs, on a box
# where several gates run wine concurrently. The two sibling gates that kill wineserver
# (cli_args_never_dropped.sh, stack_param_homing_matrix.sh) do it inline after the
# prefix is set, never from a trap. CHANGELOG [6.6.6].
WP="$T/wine"
trap '[ -d "$WP" ] && WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1; rm -rf "$T"' EXIT

# ── THE DETECTOR. For one source file, print one line per `sys_fork()` CALL (comments and
# string literals masked first, because three files in cbt/ discuss `sys_fork` in prose
# and one quotes its Windows definition verbatim):
#     <file>:<line> fn=<enclosing fn> pe=<ok|UNARMED> arm=<the arm's handler names>
# "pe=ok" means the fork cannot execute on PE: either it sits inside an open
# `#ifndef CYRIUS_TARGET_WIN`, or an `#ifdef CYRIUS_TARGET_WIN` region containing a
# `return` closed earlier in the SAME fn, or the fn asked `_git_exec_available()` first.
cat > "$T/sites.awk" <<'AWK'
function reset() { armed = 0; nd = 0; hand = ""; inwin = 0; winret = 0; winbody = "" }
/^fn [A-Za-z_]/ { reset(); fname = $2; sub(/\(.*/, "", fname) }
{
    code = $0
    gsub(/"[^"]*"/, "", code)                      # string literals first
    # Strip a `#` comment — but NOT a preprocessor directive, which starts with the same
    # character. (The first cut of this gate stripped `#endif` as a comment, because
    # `#[^i]` matches `#e`; every arm then stayed open and the scan found 1 site of 17.)
    if (code !~ /^[ \t]*#(ifdef|ifndef|endif|else|elif)/) { sub(/#.*/, "", code) }
}
code ~ /^[ \t]*#ifdef[ \t]+CYRIUS_TARGET_WIN/  { inwin = 1; winret = 0; winbody = ""; next }
code ~ /^[ \t]*#ifndef[ \t]+CYRIUS_TARGET_WIN/ { nd = 1; next }
code ~ /^[ \t]*#endif/ {
    if (inwin == 1) {
        # `armed` needs the arm to RETURN (otherwise control falls into the fork), but the
        # arm TEXT is collected either way: `cmd_soak` spawns in its #ifdef block and puts
        # the fork in the sibling #ifndef, so its handler name is only in a non-returning
        # block. Collecting only returning blocks reported that arm as silent.
        if (winret == 1) { armed = 1 }
        hand = hand winbody
        inwin = 0
    } else { nd = 0 }
    next
}
inwin == 1 {
    winbody = winbody " " code
    if (code ~ /return/) { winret = 1 }
    next
}
code ~ /_git_exec_available\(\)/ { armed = 1; hand = hand " _git_exec_available()" }
code ~ /sys_fork\(\)/ {
    pe = "UNARMED"
    if (nd == 1 || armed == 1) { pe = "ok" }
    printf "%s:%d fn=%s pe=%s arm=%s\n", FILENAME, FNR, fname, pe, hand
}
AWK
scan() { awk -f "$T/sites.awk" "$@"; }

# ── AXIS 0 — ⭐ DETECTOR SELF-TEST. Five synthetic shapes, so a detector that reports
# nothing (or everything) is caught before it is believed.
echo "axis 0 — ⭐ the detector is proved on synthetic shapes:"
mkdir -p "$T/self"
cat > "$T/self/a.cyr" <<'EOF'
fn unarmed(): i64 {
    var pid = sys_fork();
    return pid;
}
fn in_ifndef(): i64 {
    #ifdef CYRIUS_TARGET_WIN
    return _win_thing();
    #endif
    #ifndef CYRIUS_TARGET_WIN
    var pid = sys_fork();
    return pid;
    #endif
}
fn ifdef_returns(): i64 {
    #ifdef CYRIUS_TARGET_WIN
    return _win_other();
    #endif
    var pid = sys_fork();
    return pid;
}
fn ifdef_no_return(): i64 {
    #ifdef CYRIUS_TARGET_WIN
    var x = 1;
    #endif
    var pid = sys_fork();
    return pid;
}
fn only_prose(): i64 {
    # this comment mentions sys_fork() and must not count
    var s = "sys_fork()";
    return 0;
}
EOF
scan "$T/self/a.cyr" > "$T/self/out"
check "the detector finds exactly the 4 real call sites" 4 "$(grep -c 'fn=' "$T/self/out" || true)"
check "  …and flags the unguarded one" 1 "$(grep -c 'fn=unarmed pe=UNARMED' "$T/self/out" || true)"
check "  …and the #ifdef that does not return" 1 "$(grep -c 'fn=ifdef_no_return pe=UNARMED' "$T/self/out" || true)"
check "  …clears the #ifndef-wrapped fork" 1 "$(grep -c 'fn=in_ifndef pe=ok' "$T/self/out" || true)"
check "  …clears the returning #ifdef arm" 1 "$(grep -c 'fn=ifdef_returns pe=ok' "$T/self/out" || true)"
check "  …and counts nothing in the prose-only fn" 0 "$(grep -c 'fn=only_prose' "$T/self/out" || true)"

# ── AXIS 1 — every real site in cbt/ is PE-unreachable, with a derived floor.
echo "axis 1 — every sys_fork() site in cbt/ is unreachable on PE:"
scan cbt/*.cyr > "$T/sites"
NSITE=$(grep -c 'fn=' "$T/sites" || true)
NFILE=$(cut -d: -f1 "$T/sites" | sort -u | wc -l)
# Floors, not equalities: a new site is welcome, it just has to be armed. 17 sites across
# 4 files at 6.6.6 (build.cyr 10, commands.cyr 3, deps.cyr 3, pulsar.cyr 1). A detector
# that suddenly matches nothing must fail loudly rather than report "0 unarmed".
check "the scan finds at least the 17 known sites (found $NSITE)" yes "$([ "$NSITE" -ge 17 ] && echo yes || echo no)"
check "…across at least 4 cbt/ files (found $NFILE)" yes "$([ "$NFILE" -ge 4 ] && echo yes || echo no)"
grep 'pe=UNARMED' "$T/sites" > "$T/unarmed" || true
if [ -s "$T/unarmed" ]; then
    echo "  the following fork sites have no PE arm:"
    sed 's/^/    /' "$T/unarmed"
fi
check "no site is UNARMED" 0 "$(grep -c 'pe=UNARMED' "$T/sites" || true)"

# ── AXIS 2 — ⭐ each arm NAMES what it does; an arm that silently returns is the defect.
echo "axis 2 — ⭐ every PE arm names a spawn helper, a named error, or the platform question:"
: > "$T/silent"
: > "$T/handlers"
while IFS= read -r ln; do
    case "$ln" in *pe=ok*) ;; *) continue ;; esac
    arm=${ln#*arm=}
    # What an arm may be, and nothing else:
    #   _win_*                          a CreateProcessW spawn or a named-refusal helper
    #   exec_capture / exec_cmd / exec_vec / exec_env   lib/process_win.cyr's spawn API
    #   _err / _err_ctx / _ew           a named error on the terminal
    #   _git_exec_available             the platform question, answered before the fork
    #   return 0 - 1                    an explicit FAILURE sentinel (fails closed)
    # A bare `return 0;` — success without work — is admitted by none of these, which is
    # the whole point: it is the silent nothing the roadmap item forbids.
    # ⚠ Matched as a CALL (`name` immediately followed by `(`), never as a substring: the
    # first cut used shell globs and a local named `cap_win_rc` contained `_win_`, so
    # cmd_capacity's arm was admitted with its spawn removed (mutation M3 read GREEN).
    if echo "$arm" | grep -Eq '(_win_[A-Za-z0-9_]*|exec_(capture|cmd|vec|env)[A-Za-z0-9_]*|_err[A-Za-z0-9_]*|_ew|_git_exec_available) *\(|return 0 - 1'; then :
    else echo "$ln" >> "$T/silent"; fi
    for w in $arm; do
        case "$w" in _win_*) echo "$w" | sed 's/[^A-Za-z0-9_].*//' >> "$T/handlers" ;; esac
    done
done < "$T/sites"
if [ -s "$T/silent" ]; then echo "  arms that do nothing and say nothing:"; sed 's/^/    /' "$T/silent"; fi
check "no armed site has a silent arm" 0 "$(wc -l < "$T/silent" | tr -d ' ')"
sort -u "$T/handlers" > "$T/handlers.u"
NH=$(wc -l < "$T/handlers.u" | tr -d ' ')
check "the scan recovered PE spawn/refusal helpers (floor 6, found $NH)" yes "$([ "$NH" -ge 6 ] && echo yes || echo no)"
# The detector's own control: an arm written as a bare `return 0;` must be reported.
cat > "$T/self/b.cyr" <<'EOF'
fn silently_nothing(): i64 {
    #ifdef CYRIUS_TARGET_WIN
    return 0;
    #endif
    var pid = sys_fork();
    return pid;
}
EOF
cat > "$T/self/c.cyr" <<'EOF'
fn looks_armed_is_not(): i64 {
    #ifdef CYRIUS_TARGET_WIN
    var cap_win_rc = 0;
    if (cap_win_rc < 0) { return 1; }
    return 0;
    #endif
    var pid = sys_fork();
    return pid;
}
EOF
adm() { echo "$1" | grep -Eq '(_win_[A-Za-z0-9_]*|exec_(capture|cmd|vec|env)[A-Za-z0-9_]*|_err[A-Za-z0-9_]*|_ew|_git_exec_available) *\(|return 0 - 1' && echo missed || echo caught; }
sres=$(adm "$(scan "$T/self/b.cyr" | sed 's/.*arm=//')")
sres2=$(adm "$(scan "$T/self/c.cyr" | sed 's/.*arm=//')")
check "  …and a bare return-0 arm is CAUGHT by that same test" "caught" "$sres"
check "  …and a local merely NAMED *_win_* does not admit an empty arm" "caught" "$sres2"

# ── AXIS 3 — the handlers are REACHABLE in the PE binary, not merely written.
echo "axis 3 — every PE handler is reachable in the cross-built Windows CLI:"
if ! "$ROOT/build/cycc" < "$ROOT/src/main_win.cyr" > "$T/cc_win" 2> "$T/ccwin.err"; then
    echo "  FAIL: could not cross-build the PE compiler from src/main_win.cyr"; sed -n '1,4p' "$T/ccwin.err"; fails=$((fails + 1))
else
    chmod +x "$T/cc_win"
    if ! CYRIUS_DCE_VERBOSE=1 "$T/cc_win" < "$ROOT/cbt/cyrius.cyr" > "$T/cyrius.exe" 2> "$T/dce.err"; then
        echo "  FAIL: could not cross-build cbt/cyrius.cyr for PE"; grep -v '^warning: syscall' "$T/dce.err" | sed -n '1,4p'; fails=$((fails + 1))
    else
        check "the PE CLI is a real PE image" "MZ" "$(head -c 2 "$T/cyrius.exe")"
        # cycc's DCE listing names every fn nothing reaches. Anti-vacuous FIRST: a helper
        # deliberately called by nobody has to appear, or the listing is not being read.
        printf 'fn _win_gate_probe_unused(): i64 { return 0; }\n' > "$T/probe.cyr"
        cat "$ROOT/cbt/cyrius.cyr" "$T/probe.cyr" > "$T/cyrius_probe.cyr"
        ( cd "$ROOT" && CYRIUS_DCE_VERBOSE=1 "$T/cc_win" < "$T/cyrius_probe.cyr" > "$T/probe.exe" 2> "$T/probe.err" ) || true
        check "  ⭐ ANTI-VACUOUS: an uncalled helper IS listed unreachable" 1 \
            "$(grep -c '_win_gate_probe_unused' "$T/probe.err" || true)"
        # ⭐ 3b — DEFINITION-DERIVED, not arm-derived. An arm that stops calling its helper
        # drops that name from axis 2's list, so the arm-derived half above cannot see the
        # helper go dead (measured: mutation M3 was invisible until this half existed).
        # Every `fn _win_*` DEFINED in cbt/ has exactly one reason to exist — a PE arm
        # calls it — so an unreachable one is an arm that no longer does.
        grep -h '^fn _win_' cbt/*.cyr | sed 's/^fn \([A-Za-z0-9_]*\).*/\1/' | sort -u > "$T/defined.u"
        ND=$(wc -l < "$T/defined.u" | tr -d ' ')
        check "  cbt/ defines PE helpers (floor 6, found $ND)" yes "$([ "$ND" -ge 6 ] && echo yes || echo no)"
        cat "$T/defined.u" >> "$T/handlers.u"
        sort -u "$T/handlers.u" -o "$T/handlers.u"
        NH=$(wc -l < "$T/handlers.u" | tr -d ' ')
        dead=0
        for h in $(cat "$T/handlers.u"); do
            # ⚠ anchored at BOTH ends including end-of-line: cycc prints one name per line
            # as "  dead: <name>", so a trailing [^A-Za-z0-9_] never matches and the first
            # cut of this loop found nothing (mutation M3 read GREEN through it).
            if grep -Eq "(^|[^A-Za-z0-9_])$h([^A-Za-z0-9_]|\$)" "$T/dce.err" 2>/dev/null; then
                echo "    unreachable in the PE build: $h"
                dead=$((dead + 1))
            fi
        done
        check "no PE handler is dead code in the Windows build ($NH checked)" 0 "$dead"
    fi
fi

# ── AXIS 4 — ⭐ RUN THE VERBS. wine is not hardware; the cass ledger is in the header.
echo "axis 4 — ⭐ the affected verbs under wine (SKIP when wine is absent — NOT hardware):"
if ! command -v wine > /dev/null 2>&1 || ! command -v winepath > /dev/null 2>&1; then
    echo "  SKIP: wine/winepath not installed — this leg is covered on real cass only"
elif [ ! -s "$T/cc_win" ]; then
    echo "  FAIL: axis 4 cannot run — the PE compiler was not built in axis 3"; fails=$((fails + 1))
else
    export WINEPREFIX="$WP" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    WN="$T/wn"; mkdir -p "$WN/bin" "$WN/w/src" "$WN/w/lib"
    build_pe() {
        if ! "$T/cc_win" < "$1" > "$2" 2> "$T/bp.err"; then
            echo "  FAIL: could not cross-build $1 for PE"; sed -n '1,4p' "$T/bp.err"; fails=$((fails + 1)); return 1
        fi
        if [ "$(head -c 2 "$2")" != "MZ" ] || [ "$(wc -c < "$2")" -lt 20000 ]; then
            echo "  FAIL: $1 produced a non-PE / $(wc -c < "$2")-byte file"; fails=$((fails + 1)); return 1
        fi
    }
    build_pe "$ROOT/cbt/cyrius.cyr"    "$WN/bin/cyrius.exe"  || true
    build_pe "$ROOT/src/main_win.cyr"  "$WN/bin/cycc.exe"    || true
    build_pe "$ROOT/src/main_cx.cyr"   "$WN/bin/cycc_cx.exe" || true
    build_pe "$ROOT/programs/cxvm.cyr" "$WN/bin/cxvm.exe"    || true
    printf 'fn main(): i64 { return 5; }\nvar r = main();\n' > "$WN/w/p.cyr"
    printf 'export function f(): number { return 1; }\n'      > "$WN/w/t.ts"
    # The self-host negative control needs the source tree present but src/main_win.cyr
    # ABSENT, which is the whole point of the row — so stage a stand-in `src/` that has
    # everything except it. The POSITIVE self-host (a full PE self-host, minutes of work)
    # is the cass ledger's job, not a per-check.sh cost.
    cp "$ROOT/src/main.cyr" "$WN/w/src/main.cyr"
    WH=$(winepath -w "$WN" 2> /dev/null)
    check "wine: the staging path translated (floor)" yes "$([ -n "$WH" ] && echo yes || echo no)"
    WT=$(WINEDEBUG=-all timeout 120 wine cmd /c 'echo %TEMP%' 2> /dev/null | tr -d '\r')
    WTU=$(winepath -u "$WT" 2> /dev/null)
    ls -d "$WTU"/cyrius-* 2> /dev/null | LC_ALL=C sort > "$T/wt_before"
    wrun() { ( cd "$WN/w" && WINEDEBUG=-all CYRIUS_HOME="$WH" timeout 900 wine "$WN/bin/cyrius.exe" "$@" > "$T/out" 2> "$T/err" ); RC=$?; }

    wrun build --target=cx p.cyr p.cyx
    check "wine: build --target=cx succeeds" 0 "$RC"
    check "  …and wrote the .cyx" yes "$([ -s "$WN/w/p.cyx" ] && echo yes || echo no)"
    wrun run p.cyx
    check "  …and running that .cyx returns the program's own exit code" 5 "$RC"

    wrun build --target=js t.ts t.js
    check "wine: build --target=js FAILS" 1 "$RC"
    check "  …BY NAME, not silently" 1 "$(grep -c 'target=js is not available on Windows' "$T/err" || true)"
    check "  …and names the reason (no --emit-js in the PE fork)" 1 "$(grep -c 'no --emit-js' "$T/err" || true)"

    wrun capacity p.cyr
    check "wine: capacity FAILS rather than reporting numbers it does not have" 1 "$RC"
    check "  …naming CYRIUS_STATS as the reason" 1 "$(grep -c 'cannot see CYRIUS_STATS' "$T/err" || true)"

    # ⭐ THE NEGATIVE CONTROL. The 6.6.5 binary exits 0 here, printing only its header —
    # on wine and on real cass both.
    wrun self
    check "⭐ wine: self with no src/main_win.cyr FAILS (6.6.5 exits 0 here)" 1 "$RC"
    check "  …naming the missing per-target source" 1 \
        "$(grep -c 'Windows compiler source is missing' "$T/err" || true)"

    # ⭐ SOAK NAMES THE PER-TARGET SOURCE TOO. The first cut of soak's PE arm compiled
    # `src/main.cyr` — the LINUX fork — so step 2 ran a PE built from Linux syscall
    # numbers, page-faulted, and every iteration printed "self-host output differs":
    # a false verdict blaming the self-host for a source-selection bug. The staging
    # `src/` holds main.cyr and NOT main_win.cyr, so a driver that still names the
    # Linux fork says "src/main.cyr" here and one that asks `_self_host_src()` says
    # "src/main_win.cyr". (The POSITIVE soak — a real PE self-host per iteration — is
    # minutes of work and belongs in the cass ledger, not in check.sh.)
    wrun soak 1
    check "⭐ wine: soak with no src/main_win.cyr FAILS" 1 "$RC"
    check "  …naming src/main_win.cyr, NOT the Linux fork" 1 \
        "$(grep -c 'missing: src/main_win.cyr' "$T/err" || true)"
    check "  …and never claims an iteration self-hosted" 0 \
        "$(grep -c 'self-host output differs' "$T/out" || true)"

    # ⭐ AND THE SPAWN'S EXIT CODE IS THE VERDICT. The first cut called
    # `_win_compile_spawn` for effect and threw the code away, so a step-2 child that
    # died still reached the byte compare and was reported as "output differs" — again
    # naming the wrong cause. Stand-in source: a program that compiles fine and then
    # exits 3 when step 2 RUNS it, so the only honest report is "exited 3".
    W2="$T/w2"; mkdir -p "$W2/src"
    printf 'fn main(): i64 { return 3; }\nvar r = main();\n' > "$W2/src/main_win.cyr"
    ( cd "$W2" && WINEDEBUG=-all CYRIUS_HOME="$WH" timeout 900 wine "$WN/bin/cyrius.exe" soak 1 > "$T/out2" 2> "$T/err2" ) || true
    check "⭐ wine: soak reports the step-2 EXIT CODE" 1 "$(grep -c 'step 2 exited 3' "$T/out2" || true)"
    check "  …instead of blaming the byte compare" 0 "$(grep -c 'output differs' "$T/out2" || true)"

    ls -d "$WTU"/cyrius-* 2> /dev/null | LC_ALL=C sort > "$T/wt_after"
    for d in $(comm -13 "$T/wt_before" "$T/wt_after"); do rmdir "$d" 2> /dev/null || true; done
    SOCK="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WINEPREFIX" 2> /dev/null)-$(printf '%x' "$(stat -c '%i' "$WINEPREFIX" 2> /dev/null || echo 0)")"
    wineserver -k > /dev/null 2>&1 || true
    wineserver -w > /dev/null 2>&1 || true
    [ -d "$SOCK" ] && rm -rf "$SOCK"
fi

# ── AXIS 5 — ⭐ THE ARM'S OWN VERDICT FAILS CLOSED. An arm that spawns correctly and then
# reports a PASS over two empty files is the same green placebo one layer along, and cass
# is exactly the host that produces empty outputs (Defender quarantines an unsigned .exe
# mid-write). `_win_files_equal` is PE-only source, so it is EXTRACTED from cbt/build.cyr
# and compiled for this host — the real text, not a copy that can drift.
echo "axis 5 — ⭐ the PE byte-compare verdict fails closed:"
awk '/^fn _win_files_equal\(/,/^}/' cbt/build.cyr > "$T/wfe.cyr"
check "the helper was extracted from cbt/build.cyr" yes \
    "$([ -s "$T/wfe.cyr" ] && grep -q 'sys_read' "$T/wfe.cyr" && echo yes || echo no)"
D="$T/fe"; mkdir -p "$D"
: > "$D/empty_a"; : > "$D/empty_b"
head -c 100000 /dev/urandom > "$D/same_a"; cp "$D/same_a" "$D/same_b"
cp "$D/same_a" "$D/diff"; printf 'X' | dd of="$D/diff" bs=1 seek=99999 conv=notrunc 2> /dev/null
head -c 65536 "$D/same_a" > "$D/short"
rm -f "$D/missing"
mk_fe_probe() {   # $1 = helper source, $2 = output .cyr
    {
        echo 'include "lib/syscalls.cyr"'
        echo 'include "lib/string.cyr"'
        echo 'include "lib/alloc.cyr"'
        echo 'include "lib/fmt.cyr"'
        cat "$1"
        cat <<EOF
fn ans(a, b): i64 { fmt_int(_win_files_equal(a, b)); sys_write(1, "\n", 1); return 0; }
fn main(): i64 {
    alloc_init();
    ans("$D/empty_a", "$D/empty_b");
    ans("$D/same_a", "$D/same_b");
    ans("$D/same_a", "$D/diff");
    ans("$D/same_a", "$D/short");
    ans("$D/same_a", "$D/missing");
    return 0;
}
var e = main();
syscall(60, e);
EOF
    } > "$2"
}
# The expectation is computed a DIFFERENT way: cmp(1) plus a non-empty test.
expect_eq() { if [ -s "$1" ] && [ -s "$2" ] && cmp -s "$1" "$2"; then echo 1; else echo 0; fi; }
run_fe() {   # $1 = helper source -> prints 5 lines, or "BUILD-FAILED"
    mk_fe_probe "$1" "$T/fe_p.cyr"
    if ! "$ROOT/build/cycc" < "$T/fe_p.cyr" > "$T/fe_p" 2> "$T/fe_p.err"; then
        grep -E '^error' "$T/fe_p.err" | head -2 | sed 's/^/    /'
        echo BUILD-FAILED; return
    fi
    [ -s "$T/fe_p" ] || { echo BUILD-FAILED; return; }
    chmod +x "$T/fe_p"
    ( ulimit -c 0; "$T/fe_p" ) 2> /dev/null
}
run_fe "$T/wfe.cyr" > "$T/fe.out"
check "the extracted helper compiled and ran (5 answers)" 5 "$(grep -c . "$T/fe.out" || true)"
i=1
for pair in "empty_a empty_b" "same_a same_b" "same_a diff" "same_a short" "same_a missing"; do
    set -- $pair
    want=$(expect_eq "$D/$1" "$D/$2")
    got=$(sed -n "${i}p" "$T/fe.out")
    check "  $1 vs $2 -> $want" "$want" "${got:-none}"
    i=$((i + 1))
done
# ⭐ THE AXIS'S OWN MUTATION CONTROL. Remove the byte floor from the EXTRACTED copy: the
# empty/empty answer must flip to 1. If it does not, this axis is not testing anything.
sed '/seen <= 0/d' "$T/wfe.cyr" > "$T/wfe_mut.cyr"
check "  ⭐ ANTI-VACUOUS: the mutant differs from the real helper" yes \
    "$(cmp -s "$T/wfe.cyr" "$T/wfe_mut.cyr" && echo no || echo yes)"
run_fe "$T/wfe_mut.cyr" > "$T/fe_mut.out"
check "  ⭐ ANTI-VACUOUS: without the floor, two EMPTY files read as identical" 1 \
    "$(sed -n 1p "$T/fe_mut.out")"

# ── AXIS 6 — ⭐ NO `cmd /s /c` COMMAND LINE IS BUILT IN A FIXED BUFFER. `_w_append_cstr`
# does not bound-check, so a fixed allocation is a silent heap overwrite for a long enough
# path. `_win_cmdline` was changed from that shape at 6.6.5 ("a fixed buffer is a heap
# overwrite waiting for a large enough project") and 6.6.6's new `_win_capacity_spawn`
# reintroduced it — which is why the rule is DERIVED from the sources here rather than
# fixed once by hand. A builder is a fn that both ALLOCATES `wbuf` and appends to it.
echo "axis 6 — ⭐ every UTF-16 command line is sized from its inputs:"
cat > "$T/bld.awk" <<'AWK'
function flush() {
    if (builder == 1 && alloc != "") {
        v = "sized"
        # A size with no identifier in it is a compile-time constant: the defect.
        if (alloc ~ /alloc\([0-9 +*()]*\)/) { v = "FIXED" }
        # Otherwise it must be derived from the caller's own lengths, one way or another.
        if (v != "FIXED" && alloc !~ /_w_cmdbuf\(/ && body !~ /strlen\(/ && body !~ /vec_len\(/) { v = "UNSIZED" }
        printf "%s:%s %s | %s\n", FILENAME, fname, v, alloc
    }
    builder = 0; alloc = ""; body = ""
}
/^fn [A-Za-z_]/ { flush(); fname = $2; sub(/\(.*/, "", fname) }
{ body = body " " $0 }
/wbuf[ \t]*=[ \t]*alloc\(/ || /wbuf[ \t]*=[ \t]*_w_cmdbuf\(/ {
    alloc = $0; sub(/^[ \t]*/, "", alloc)
}
/_w_append_cstr\(wbuf/ || /_w_append_arg\(wbuf/ { builder = 1 }
/^}/ { flush() }
END { flush() }
AWK
awk -f "$T/bld.awk" cbt/*.cyr lib/process_win.cyr > "$T/builders"
NB=$(grep -c ':' "$T/builders" || true)
check "the scan found the command-line builders (floor 8, found $NB)" yes \
    "$([ "$NB" -ge 8 ] && echo yes || echo no)"
if grep -Eq ' (FIXED|UNSIZED) ' "$T/builders"; then
    echo "  builders whose buffer is not sized from their inputs:"
    grep -E ' (FIXED|UNSIZED) ' "$T/builders" | sed 's/^/    /'
fi
check "no builder uses a fixed-size buffer" 0 "$(grep -c ' FIXED ' "$T/builders" || true)"
check "no builder sizes from nothing at all" 0 "$(grep -c ' UNSIZED ' "$T/builders" || true)"
# The detector's own control: one fixed builder and one sized builder in the same file.
cat > "$T/self/d.cyr" <<'EOF'
fn fixed_builder(a, b): i64 {
    var wbuf = alloc(16384);
    var o = 0;
    o = _w_append_cstr(wbuf, o, a);
    o = _w_append_cstr(wbuf, o, b);
    return wbuf;
}
fn sized_builder(a, b): i64 {
    var wbuf = _w_cmdbuf(strlen(a) + strlen(b));
    if (wbuf == 0) { return 0; }
    var o = 0;
    o = _w_append_cstr(wbuf, o, a);
    return wbuf;
}
fn not_a_builder(): i64 {
    var wbuf = alloc(16384);
    return wbuf;
}
EOF
awk -f "$T/bld.awk" "$T/self/d.cyr" > "$T/bld.self"
check "  ⭐ ANTI-VACUOUS: the detector flags a synthetic fixed builder" 1 \
    "$(grep -c ' FIXED ' "$T/bld.self" || true)"
check "  …clears the sized one" 1 "$(grep -c ' sized ' "$T/bld.self" || true)"
check "  …and does not count a fn that never appends" 2 "$(grep -c ':' "$T/bld.self" || true)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: cbt-fork-sites-have-pe-arm — $NSITE fork sites, every one armed and named"
    exit 0
fi
echo "FAIL: cbt-fork-sites-have-pe-arm — $fails assertion(s) failed"
exit 1
