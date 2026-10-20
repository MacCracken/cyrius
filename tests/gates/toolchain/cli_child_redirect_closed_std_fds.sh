#!/bin/sh
# tests/gates/toolchain/cli_child_redirect_closed_std_fds.sh — 6.7.16
#
# A CHILD the CLI (cbt/), the check driver (programs/checks/) or a tool in programs/ forks gets
# the std fds its redirects name, whichever std fds the parent started with.
#
# THE DEFECT (issues/2026-10-18-cbt-and-programs-child-redirects-close-their-own-std-fd.md). Each
# child redirect was `sys_dup2(fd, N); sys_close(fd);`. A parent started with std fd N closed
# hands that number to the child's next open, `dup2(N, N)` is a no-op, and the close then closed
# the redirect it had just made. Measured on x86_64 Linux at 480de63eb:
#   cyrius build --target=js x.ts out2.js 1>&-   -> "could not write the output (0 of 29 bytes):
#                                                   errno 9", rc 1, no out2.js (the filed repro)
#   cyrius build h.cyr hb0 0<&-                  -> "OK (4448 bytes)", rc 0 — and hb0 (source
#                                                   `syscall(60, 42);`) exits 0: cycc read an
#                                                   EMPTY stdin and the CLI shipped an empty program
#   cyrius build --target=cx h.cyr h0.cyx 0<&-   -> OK, a 24-byte .cyx (the control is 56)
#   cyrius run h.cyx 0<&-                        -> "error: not a .cyx file", exit 1
#   cyrius run h.cyx 0<&- (no cxvm installed)    -> the cxvm JIT build read an empty stdin and left
#                                                   a 4448-byte EMPTY ./build/cxvm: that run and
#                                                   EVERY later `cyrius run x.cyx` there exit 0
#   check driver --output-row <ok fixture> 0<&- / 1>&-  -> "FAIL: … compile error", rc 1
# A parent-opened fd had a second shape: one started with fd 0 closed opened its capture AT 0,
# and the child's stdin redirect overwrote it before the capture redirect read it.
#
# THE FIX. Every child redirect goes through a same-fd guard — `_cbt_redirect` (cbt/core.cyr),
# lib/regression.cyr's `_regression_redirect` (programs/checks/), a local twin in cyrius-init
# and ts_test_runner — and an fd the PARENT opened is lifted above 2 (`_cbt_lift_fd`,
# `_regression_lift_fd`) before the child's first redirect. A both-streams fd (`dup2(fd, 1);
# dup2(fd, 2)`) is closed only when it is neither 1 nor 2.
#
# AXES (built from THIS tree with $CYCC / build/cycc into the gate's own dir; throwaway HOME and
# CYRIUS_HOME; the CLI resolves cycc / cycc_cx / cxvm beside itself):
#   premise  a probe started the way every row starts its program (the shell runs it, never via
#      `env` — pi's coreutils reopen a closed std fd on /dev/null at startup) exits with the bit of
#      each fd it was started without: fd 0 / 1 / 2 closed -> 1 / 2 / 4, the driver form -> 3
#   1  the filed repro VERBATIM: `cyrius build --target=js x.ts out.js` (control) and
#      `… out2.js 1>&-` -> rc 0 both, out2.js 29 bytes and equal to out.js
#   2  `cyrius build h.cyr` (h.cyr = `syscall(60, 42);`) with fd 0, 1 or 2 closed -> rc 0 and the
#      binary exits 42 (control: all open)
#   3  `cyrius build --target=cx` with fd 0 closed and with fd 1 closed -> rc 0 and the .cyx equals
#      the control's; `cyrius run h.cyx 0<&-` (run_cx) -> 42
#   4  the cx JIT build (`_cx_jit_build`): a CLI with no cxvm beside it, in a dir holding
#      programs/cxvm.cyr + lib/, `cyrius run h.cyx` with fd 0 closed and with fd 1 closed -> 42,
#      and the ./build/cxvm it built equals the gate's own cxvm build
#   5  the check driver (programs/checks/main.cyr) in a throwaway root, `--output-row` on a fixture
#      whose output matches and on one whose output drifts, with fd 0, 1 and 2 closed: the
#      matching one rc 0 (and "PASS:" where stdout is open), the drifting one rc != 0 (and
#      "FAIL:") — the verdict is right both ways, never just "rc 0"
#   6  STATIC census over cbt/**/*.cyr and programs/**/*.cyr, comments and string contents
#      masked: an unguarded `sys_close(X)` as the statement right after `sys_dup2(X, N)` (further
#      `sys_dup2(X, …)` of the same X in between are skipped — the both-streams form) is RED,
#      naming file:line:fn. ALLOW names the sites another 6.7.16 lane owns (a row that matches no
#      live site is RED: drop it when that lane lands). Self-test first: a fixture of 5 bad and 6
#      good shapes reads exactly the 5, a mutant of a good one is caught, and three LIVE mutants
#      go RED naming their fn — compile()'s stdin redirect back to the unguarded pair,
#      `_cbt_redirect`'s guard dropped, and shared.cyr `_exec_in_dir`'s both-streams guard
#      dropped. Floors: >= 100 files, >= 15 sys_dup2 statements read.
#   7  a git dep (a local file:// origin tagged v1 and v2) with fd 0 closed: `cyrius deps` (the clone,
#      then the cached clone re-verified through `hash-object --stdin-paths` — `_git_run`) rc 0 with
#      the v1 file vendored, and `cyrius update` (`ls-remote --tags` — `_dep_wt_run`) rc 0 listing
#      "newer tags: v2"; control with every fd open. Without git the row says so by name.
#
# MUTATION LEDGER — run 2026-10-19 (lane libfix, unit L3; x86_64 Linux), each in a scratch copy of
# the tree, the gate run from that copy:
#   a. compile()'s `_cbt_redirect(sfd, 0)` back to `sys_dup2(sfd, 0); sys_close(sfd);` -> axis 2
#      RED (fd 0 closed: exits 0, not 42) and axis 6 RED naming cbt/build.cyr compile
#   b. `_cbt_redirect`'s `if (fd != target)` dropped (the close unconditional) -> axes 1, 2, 3, 4
#      RED and axis 6 RED naming cbt/core.cyr _cbt_redirect
#   c. selfhost.cyr `_self_host_pipe`'s two lifts dropped (read_fd / out_fd redirected as they
#      are) -> axis 5 RED (fd 0 closed: "compile error", rc 1)
#   d. the tree at 480de63eb (every site unguarded) -> axes 1-5 and 7 RED (axis 5 with fd 0 and with
#      fd 1 closed) and axis 6 RED on 80 sites (the 6 cyrius-lsp ones allowed)
#   e. `_git_run`'s `_cbt_lift_fd(cfd)` turned into `cfd` -> axis 7 RED (deps rc 1: the clean cache
#      refused as "tampered cache: git could not verify it"; update rc 1)
#   f. `_dep_wt_run`'s lift turned into `cfd` -> axis 7 RED (update: "the remote's tags could not be
#      listed (fatal: write failure on standard output: Bad file descriptor)")
#   (a stale ALLOW row: tested by hand with the two cyrius-lsp sites guarded -> RED naming both rows)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=cli_child_redirect_closed_std_fds

[ -x "$CC" ] || { echo "FAIL: $NAME — $CC missing"; exit 1; }
command -v awk > /dev/null 2>&1 || { echo "FAIL: $NAME — no awk (the census needs it)"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT INT TERM
FAIL=0
fail() { echo "FAIL: $NAME: $*"; FAIL=1; }
ok() { echo "  ok: $*"; }

# ── axis 6 first: the static census (cheap, and its self-test proves the matcher) ──
cat > "$W/census.awk" <<'AWK'
function mask(s,    out, i, c, n, instr, esc) {
    out = ""; instr = 0; esc = 0; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (instr) {
            if (esc) { esc = 0; out = out "x"; continue }
            if (c == "\\") { esc = 1; out = out "x"; continue }
            if (c == "\"") { instr = 0; out = out c; continue }
            out = out "x"; continue
        }
        if (c == "\"") { instr = 1; out = out c; continue }
        if (c == "#") break
        out = out c
    }
    return out
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
FNR == 1 { pend = ""; fn = "(top)"; nfiles++ }
/^fn [A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ { fn = $0; sub(/^fn /, "", fn); sub(/[ \t]*\(.*/, "", fn) }
{
    line = mask($0)
    if (trim(line) == "") next
    nst = split(line, st, /[;{}]/)
    for (k = 1; k <= nst; k++) {
        t = trim(st[k])
        if (t == "") continue
        if (t ~ /^sys_dup2\([ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*,[^)]*\)$/) {
            x = t; sub(/^sys_dup2\([ \t]*/, "", x); sub(/[ \t]*,.*/, "", x)
            ndup++
            if (pend == x) continue
            pend = x; pline = FNR; pfn = fn
            continue
        }
        tt = t; gsub(/[ \t]/, "", tt)
        if (pend != "" && tt == "sys_close(" pend ")") print FILENAME ":" pline ":" pfn ":" pend
        pend = ""
    }
}
END { print "#dup2 " ndup + 0; print "#files " nfiles + 0 }
AWK
census() { awk -f "$W/census.awk" "$@"; }   # file:line:fn:X per site, then #dup2 / #files

mkdir -p "$W/fx"
cat > "$W/fx/shapes.cyr" <<'FX'
fn bad_two_lines(a): i64 {
    sys_dup2(a, 0);
    sys_close(a);
    return 0;
}
fn bad_one_line(b): i64 { sys_dup2(b, 1); sys_close(b); return 0; }
fn bad_braced(c): i64 {
    if (c >= 0) { sys_dup2(c, 2); sys_close(c); }
    return 0;
}
fn bad_both(d): i64 {
    sys_dup2(d, 1);
    sys_dup2(d, 2);
    sys_close(d);
    return 0;
}
fn bad_comment_between(e): i64 {
    sys_dup2(e, 1);
    # a comment and a blank line do not end the pair

    sys_close( e );
    return 0;
}
fn ok_guard(f): i64 {
    sys_dup2(f, 1);
    if (f != 1) { sys_close(f); }
    return 0;
}
fn ok_both_guard(g): i64 {
    sys_dup2(g, 1);
    sys_dup2(g, 2);
    if (g != 1 && g != 2) { sys_close(g); }
    return 0;
}
fn ok_other_fd(h, i): i64 { sys_dup2(h, 1); sys_close(i); return 0; }
fn ok_string(): i64 { var s = "sys_dup2(j, 1); sys_close(j);"; return s; }
fn ok_comment(): i64 {
    # sys_dup2(k, 1); sys_close(k);
    return 0;
}
fn ok_return(m): i64 { return sys_dup2(m, 1); }
FX
want_fx="bad_both bad_braced bad_comment_between bad_one_line bad_two_lines"
got_fx=$(cd "$W/fx" && census shapes.cyr | grep -v '^#' | cut -d: -f3 | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$got_fx" = "$want_fx" ]; then ok "axis 6 self-test: the fixture reads exactly its 5 bad shapes (two lines, one line, braced, both-streams, comment between)"
else fail "axis 6 self-test: the fixture read [$got_fx], want [$want_fx]"; fi
sed 's/    if (f != 1) { sys_close(f); }/    sys_close(f);/' "$W/fx/shapes.cyr" > "$W/fx/mut.cyr"
if (cd "$W/fx" && census mut.cyr) | grep -q ':ok_guard:f$'; then ok "axis 6 self-test: ok_guard with its guard dropped is caught"
else fail "axis 6 self-test: ok_guard with its guard dropped is NOT caught — the matcher is blind"; fi

# Live mutants: copies of the real files, each must go RED naming its fn.
mkdir -p "$W/mut/cbt" "$W/mut/programs/checks"
awk '/^fn / { f = $0 } f ~ /^fn compile\(/ && /^        _cbt_redirect\(sfd, 0\);/ { print "        sys_dup2(sfd, 0);"; print "        sys_close(sfd);"; next } { print }' \
    "$ROOT/cbt/build.cyr" > "$W/mut/cbt/build.cyr"
awk '/^fn / { f = $0 } f ~ /^fn _cbt_redirect\(/ && /if \(fd != target\) \{ sys_close\(fd\); \}/ { print "    sys_close(fd);"; next } { print }' \
    "$ROOT/cbt/core.cyr" > "$W/mut/cbt/core.cyr"
awk '/^fn / { f = $0 } f ~ /^fn _exec_in_dir\(/ && /if \(out_fd != 1 && out_fd != 2\) \{ sys_close\(out_fd\); \}/ { print "            sys_close(out_fd);"; next } { print }' \
    "$ROOT/programs/checks/shared.cyr" > "$W/mut/programs/checks/shared.cyr"
mres=$(cd "$W/mut" && census cbt/build.cyr cbt/core.cyr programs/checks/shared.cyr | grep -v '^#')
for m in "cbt/build.cyr:compile:sfd" "cbt/core.cyr:_cbt_redirect:fd" "programs/checks/shared.cyr:_exec_in_dir:out_fd"; do
    f=${m%%:*}; rest=${m#*:}
    if printf '%s\n' "$mres" | grep -q "^$f:[0-9]*:$rest\$"; then ok "axis 6 live mutant RED: $f ${rest%%:*} (the guard dropped)"
    else fail "axis 6 live mutant: $f with ${rest%%:*}'s guard dropped is NOT caught"; fi
done

# The census of the tree. ALLOW: `file:fn` rows another 6.7.16 lane owns — programs/cyrius-lsp.cyr's
# two child setups, which the tools lane (T4 / T5) rewrites and guards. Each row must still match
# a live site; once that lane has landed, a row that matches nothing is RED — delete it then.
ALLOW="programs/cyrius-lsp.cyr:_compile_via_wrapper_run
programs/cyrius-lsp.cyr:compile_and_capture"
files=$(cd "$ROOT" && find cbt programs -name '*.cyr' -type f | sort)
res=$(cd "$ROOT" && census $files)
ndup=$(printf '%s\n' "$res" | sed -n 's/^#dup2 //p')
nfil=$(printf '%s\n' "$res" | sed -n 's/^#files //p')
[ "${nfil:-0}" -ge 100 ] || fail "axis 6 floor: ${nfil:-0} files read under cbt/ and programs/ (want >= 100)"
[ "${ndup:-0}" -ge 15 ] || fail "axis 6 floor: ${ndup:-0} sys_dup2 statements read (want >= 15)"
bad=0; allowed=0
for v in $(printf '%s\n' "$res" | grep -v '^#'); do
    key=$(printf '%s' "$v" | cut -d: -f1,3)
    if printf '%s\n' "$ALLOW" | grep -qx "$key"; then allowed=$((allowed + 1)); continue; fi
    fail "axis 6: $(printf '%s' "$v" | cut -d: -f1,2) ($(printf '%s' "$v" | cut -d: -f3)): sys_close($(printf '%s' "$v" | cut -d: -f4)) right after sys_dup2($(printf '%s' "$v" | cut -d: -f4), …) with no same-fd guard"
    bad=$((bad + 1))
done
for a in $ALLOW; do
    printf '%s\n' "$res" | grep -v '^#' | cut -d: -f1,3 | grep -qx "$a" \
        || fail "axis 6: ALLOW row '$a' matches no unguarded site any more — delete it from this gate"
done
[ "$bad" = 0 ] && ok "axis 6: no unguarded sys_dup2 / sys_close pair in cbt/ or programs/ ($nfil files, $ndup sys_dup2 statements; $allowed allowed site(s) in the tools lane's cyrius-lsp)"

# ── build the tools from THIS tree ──
B="$W/bin"; B2="$W/bin2"; H="$W/home"
mkdir -p "$B" "$B2" "$H/.cyrius" || { echo "FAIL: $NAME: cannot stage $W"; exit 1; }
_build() {  # $1 source (tree-relative), $2 output
    ( cd "$ROOT" && "$CC" < "$1" > "$2" 2> "$2.err" ) && [ -s "$2" ] && chmod +x "$2" \
        || { echo "FAIL: $NAME: $1 does not build:"; tail -3 "$2.err"; exit 1; }
}
_build cbt/cyrius.cyr "$B/cyrius"
_build src/main_cx.cyr "$B/cycc_cx"
_build programs/cxvm.cyr "$B/cxvm"
_build programs/checks/main.cyr "$W/drv"
# The premise probe: exits with a bit per std fd it was started WITHOUT (1 = fd 0, 2 = fd 1, 4 = fd 2).
printf 'include "lib/syscalls.cyr"\nfn main(): i64 {\n    var m = 0;\n    if (sys_fcntl(0, F_GETFD, 0) < 0) { m = m + 1; }\n    if (sys_fcntl(1, F_GETFD, 0) < 0) { m = m + 2; }\n    if (sys_fcntl(2, F_GETFD, 0) < 0) { m = m + 4; }\n    return m;\n}\n' > "$W/fdprobe.cyr"
( cd "$ROOT" && "$CC" < "$W/fdprobe.cyr" > "$W/fdprobe" 2> "$W/fdprobe.err" ) && [ -s "$W/fdprobe" ] && chmod +x "$W/fdprobe" \
    || { echo "FAIL: $NAME: the fd probe does not build:"; tail -3 "$W/fdprobe.err"; exit 1; }
# bin2 holds the CLI and cycc alone: no cxvm beside it, so axis 4's run JIT-builds one.
cp "$CC" "$B/cycc" && cp "$B/cyrius" "$B2/cyrius" && cp "$CC" "$B2/cycc" \
    && chmod +x "$B/cycc" "$B2/cycc" "$B2/cyrius" || { echo "FAIL: $NAME: cannot stage $B / $B2"; exit 1; }

# run_in <dir> <prog> <args…> — <prog> in <dir> with the gate's own home; the caller's redirects
# (`0<&-`, `1>&-`, `2>&-`) apply to it. The shell starts <prog> ITSELF: no `env` in between — a
# libc that reopens a closed std fd on /dev/null at startup (measured: pi's coreutils `env` and
# `readlink`) would hand the CLI an open fd and every row below would read green on the bug.
run_in() {
    _d=$1; shift
    ( cd "$_d" || exit 97
      unset CYRIUS_TARGET_WIN CYRIUS_TARGET_AGNOS CYRIUS_MACHO CYRIUS_MACHO_ARM CYRIUS_POISON CYRIUS_BOUNDS \
          CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_RESOLVED
      export HOME="$H" CYRIUS_HOME="$H/.cyrius"
      "$@" )
}
cli() { _b=$1; _d=$2; shift 2; run_in "$_d" "$_b/cyrius" "$@"; }
_size() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo none; fi; }
_exit_of() { if [ -x "$1" ]; then "$1" > /dev/null 2>&1; echo $?; else echo none; fi; }

P="$W/p"; mkdir -p "$P"

# ── premise: the launchers below really start their program with the fd closed ──
pm=""
for m in none 0 1 2; do
    rc=0
    case $m in
        none) run_in "$P" "$W/fdprobe" || rc=$? ;;
        0) run_in "$P" "$W/fdprobe" 0<&- || rc=$? ;;
        1) run_in "$P" "$W/fdprobe" 1>&- || rc=$? ;;
        2) run_in "$P" "$W/fdprobe" 2>&- || rc=$? ;;
    esac
    pm="$pm $rc"
done
rc=0; ( cd "$P" && TMPDIR="$W" "$W/fdprobe" ) 0<&- 1>&- || rc=$?
if [ "$pm" = " 0 1 2 4" ] && [ "$rc" = 3 ]; then ok "premise: a program the gate starts with fd 0, 1 or 2 closed (or 0 and 1) sees it closed"
else fail "premise: the fd probe answered [$pm] and $rc (want [ 0 1 2 4] and 3) — a closed fd does not reach the program, so no row below could see the defect"; fi

# ── axis 1: the filed repro, verbatim ──
( cd "$P" && printf 'const x: number = 1;\nconsole.log(x);\n' > x.ts )
rc0=0; cli "$B" "$P" build --target=js x.ts out.js > "$W/a1c.out" 2>&1 || rc0=$?
rc1=0; cli "$B" "$P" build --target=js x.ts out2.js 1>&- 2> "$W/a1.err" || rc1=$?
if [ "$rc0" = 0 ] && [ "$(_size "$P/out.js")" = 29 ] && [ "$rc1" = 0 ] && [ "$(_size "$P/out2.js")" = 29 ] && cmp -s "$P/out.js" "$P/out2.js"; then
    ok "axis 1: the filed repro — build --target=js with stdout closed: rc 0 and a 29-byte out2.js equal to the control's"
else
    fail "axis 1: the filed repro — control rc $rc0 out.js $(_size "$P/out.js") B; stdout closed rc $rc1 out2.js $(_size "$P/out2.js") B (want rc 0, 29 B, equal): $(head -c 200 "$W/a1.err")"
fi

# ── axis 2: build with each std fd closed ──
printf 'syscall(60, 42);\n' > "$P/h.cyr"
for m in none 0 1 2; do
    rc=0
    case $m in
        none) cli "$B" "$P" build h.cyr hb_$m > "$W/a2.out" 2>&1 || rc=$? ;;
        0) cli "$B" "$P" build h.cyr hb_$m 0<&- > "$W/a2.out" 2>&1 || rc=$? ;;
        1) cli "$B" "$P" build h.cyr hb_$m 1>&- 2> "$W/a2.out" || rc=$? ;;
        2) cli "$B" "$P" build h.cyr hb_$m 2>&- > "$W/a2.out" || rc=$? ;;
    esac
    ex=$(_exit_of "$P/hb_$m"); lab="with fd $m closed"; [ "$m" = none ] && lab="(control, every std fd open)"
    if [ "$rc" = 0 ] && [ "$ex" = 42 ]; then ok "axis 2: build h.cyr $lab: rc 0, the binary exits 42"
    else fail "axis 2: build h.cyr $lab: rc $rc, the binary exits $ex (want rc 0, 42): $(head -c 200 "$W/a2.out")"; fi
done

# ── axis 3: the cx emit and run_cx ──
rc=0; cli "$B" "$P" build --target=cx h.cyr hc.cyx > "$W/a3.out" 2>&1 || rc=$?
ex=0; cli "$B" "$P" run hc.cyx > /dev/null 2>&1 || ex=$?
if [ "$rc" = 0 ] && [ -s "$P/hc.cyx" ] && [ "$ex" = 42 ]; then
    for m in 0 1; do
        rc=0
        case $m in
            0) cli "$B" "$P" build --target=cx h.cyr h$m.cyx 0<&- > "$W/a3.out" 2>&1 || rc=$? ;;
            1) cli "$B" "$P" build --target=cx h.cyr h$m.cyx 1>&- 2> "$W/a3.out" || rc=$? ;;
        esac
        if [ "$rc" = 0 ] && cmp -s "$P/hc.cyx" "$P/h$m.cyx"; then ok "axis 3: build --target=cx with fd $m closed: rc 0, the .cyx equals the control's"
        else fail "axis 3: build --target=cx with fd $m closed: rc $rc, .cyx $(_size "$P/h$m.cyx") B vs the control's $(_size "$P/hc.cyx"): $(head -c 200 "$W/a3.out")"; fi
    done
    ex=0; cli "$B" "$P" run hc.cyx 0<&- > /dev/null 2>&1 || ex=$?
    if [ "$ex" = 42 ]; then ok "axis 3: run hc.cyx (run_cx) with fd 0 closed exits 42"
    else fail "axis 3: run hc.cyx (run_cx) with fd 0 closed exits $ex (want 42)"; fi
else
    fail "axis 3: control — build --target=cx rc $rc (.cyx $(_size "$P/hc.cyx") B), run exits $ex (want 0 / 42): $(head -c 200 "$W/a3.out")"
fi

# ── axis 4: the cx JIT build (`_cx_jit_build`), no cxvm beside the CLI ──
for m in 0 1; do
    J="$W/jit$m"; mkdir -p "$J/programs"
    cp "$ROOT/programs/cxvm.cyr" "$J/programs/" && cp -R "$ROOT/lib" "$J/lib" && cp "$P/hc.cyx" "$J/" || { fail "axis 4: cannot stage $J"; continue; }
    ex=0
    case $m in
        0) cli "$B2" "$J" run hc.cyx 0<&- > "$W/a4.out" 2>&1 || ex=$? ;;
        1) cli "$B2" "$J" run hc.cyx 1>&- 2> "$W/a4.out" || ex=$? ;;
    esac
    if [ "$ex" = 42 ] && cmp -s "$J/build/cxvm" "$B/cxvm"; then ok "axis 4: the cxvm JIT build with fd $m closed: the run exits 42 and ./build/cxvm equals the gate's cxvm"
    else fail "axis 4: the cxvm JIT build with fd $m closed: the run exits $ex (want 42), ./build/cxvm $(_size "$J/build/cxvm") B vs $(_size "$B/cxvm"): $(head -c 200 "$W/a4.out")"; fi
    rm -rf "$J"
done

# ── axis 5: the check driver, one output row, std fds closed ──
R="$W/root"; DT="$W/drvtmp"; mkdir -p "$R/build" "$R/tests/fixtures" "$DT"
cp "$CC" "$R/build/cycc" && chmod +x "$R/build/cycc" || exit 1
printf 'fn main(): i64 { var w = syscall(1, 1, "exact-bytes\\n", 12); return 152; }\nvar r = main();\nsyscall(60, r);\n' > "$R/tests/fixtures/zz_ok.cyr"
printf 'fn main(): i64 { var w = syscall(1, 1, "other-bytes\\n", 12); return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$R/tests/fixtures/zz_drift.cyr"
printf 'exact-bytes\n' > "$R/tests/fixtures/zz_ok.expected"
printf 'exact-bytes\n' > "$R/tests/fixtures/zz_drift.expected"
drv() {  # drv <fixture> <closed: none|0|1|2> — stdout to $W/a5.out where open; echoes the rc
    _rc=0
    case $2 in
        none) ( cd "$R" && TMPDIR="$DT" CYRIUS_CHECK_TIMEOUT=60 "$W/drv" --output-row "$1" ) > "$W/a5.out" 2>&1 || _rc=$? ;;
        0) ( cd "$R" && TMPDIR="$DT" CYRIUS_CHECK_TIMEOUT=60 "$W/drv" --output-row "$1" ) 0<&- > "$W/a5.out" 2>&1 || _rc=$? ;;
        1) : > "$W/a5.out"; ( cd "$R" && TMPDIR="$DT" CYRIUS_CHECK_TIMEOUT=60 "$W/drv" --output-row "$1" ) 1>&- 2> /dev/null || _rc=$? ;;
        2) ( cd "$R" && TMPDIR="$DT" CYRIUS_CHECK_TIMEOUT=60 "$W/drv" --output-row "$1" ) 2>&- > "$W/a5.out" || _rc=$? ;;
    esac
    echo "$_rc"
}
for m in none 0 1 2; do
    rok=$(drv zz_ok $m); okrow=yes
    [ "$m" = 1 ] || { grep -q 'PASS: zz_ok' "$W/a5.out" || okrow=no; }
    rdr=$(drv zz_drift $m); drrow=yes
    [ "$m" = 1 ] || { grep -q 'FAIL: zz_drift' "$W/a5.out" || drrow=no; }
    lab="with fd $m closed"; [ "$m" = none ] && lab="(control, every std fd open)"
    if [ "$rok" = 0 ] && [ "$okrow" = yes ] && [ "$rdr" != 0 ] && [ "$drrow" = yes ]; then
        ok "axis 5: check driver --output-row $lab: the matching fixture PASSes (rc 0), the drifting one FAILs (rc $rdr)"
    else
        fail "axis 5: check driver --output-row $lab: matching rc $rok (row printed: $okrow), drifting rc $rdr (row printed: $drrow) — want 0 / PASS and non-zero / FAIL: $(tr '\n' '|' < "$W/a5.out" | head -c 200)"
    fi
done
[ -z "$(ls -A "$DT")" ] || fail "axis 5: the driver left $(ls -A "$DT" | head -3 | tr '\n' ' ')in its TMPDIR"

# ── axis 7: a git dep resolved with fd 0 closed (`_git_run`, `_dep_wt_run`: a parent-opened capture) ──
# The CLI opens a capture for git's stdout BEFORE the fork; with fd 0 closed it opens AT 0, and the
# child's stdin redirect (the --stdin-paths list, /dev/null) overwrote it: `hash-object --stdin-paths`
# wrote nowhere and a clean cache was refused as TAMPERED, `ls-remote --tags` listed nothing.
if command -v git > /dev/null 2>&1; then
    V=$(tr -d '[:space:]' < "$ROOT/VERSION")
    G="$W/g"; GH="$G/home"
    mkdir -p "$GH/versions/$V/bin" "$GH/deps" "$G/o/good/dist" && cp -R "$ROOT/lib" "$GH/versions/$V/lib" \
        && cp "$B/cyrius" "$GH/versions/$V/bin/cyrius" && cp "$CC" "$GH/versions/$V/bin/cycc" \
        && chmod +x "$GH/versions/$V/bin/cyrius" "$GH/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$GH/current" \
        || { echo "FAIL: $NAME: axis 7: cannot stage $GH"; exit 1; }
    printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$G/gitconfig"
    printf 'fn good_f(): i64 { return 1; }\n' > "$G/o/good/dist/good.cyr"
    ( cd "$G/o/good" && export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$G/gitconfig" \
        && git init -q . && git add -A && git commit -qm v1 && git tag v1 && cp dist/good.cyr "$G/good.v1" \
        && echo 'fn good_g(): i64 { return 2; }' >> dist/good.cyr && git commit -qam v2 && git tag v2 ) \
        || { echo "FAIL: $NAME: axis 7: cannot build the origin repository"; exit 1; }
    gcli() {  # gcli <project> <args…> — the CLI from the staged home, git confined to the gate's config
        _gd=$1; shift
        ( cd "$_gd" || exit 97
          unset CYRIUS_TARGET_WIN CYRIUS_TARGET_AGNOS CYRIUS_MACHO CYRIUS_MACHO_ARM CYRIUS_POISON CYRIUS_BOUNDS \
              CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE
          export HOME="$G/nohome" CYRIUS_HOME="$GH" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
              GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$G/gitconfig" GIT_ALLOW_PROTOCOL=file
          "$GH/versions/$V/bin/cyrius" "$@" )
    }
    for m in none 0; do
        GP="$G/p_$m"; mkdir -p "$GP"; rm -rf "$GH/deps"; mkdir -p "$GH/deps"
        printf '[package]\nname = "fdp"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nsrc = "main.cyr"\noutput = "out"\n\n[deps.good]\ngit = "file://%s"\ntag = "v1"\nmodules = ["dist/good.cyr"]\n' "$V" "$G/o/good" > "$GP/cyrius.cyml"
        printf 'fn main(): i64 { return 0; }\n' > "$GP/main.cyr"
        lab="with fd 0 closed"; [ "$m" = none ] && lab="(control, every std fd open)"
        r1=0; r2=0; r3=0
        if [ "$m" = none ]; then
            gcli "$GP" deps > "$W/a7a.out" 2>&1 || r1=$?
            gcli "$GP" deps > "$W/a7b.out" 2>&1 || r2=$?
            gcli "$GP" update > "$W/a7c.out" 2>&1 || r3=$?
        else
            gcli "$GP" deps 0<&- > "$W/a7a.out" 2>&1 || r1=$?
            gcli "$GP" deps 0<&- > "$W/a7b.out" 2>&1 || r2=$?
            gcli "$GP" update 0<&- > "$W/a7c.out" 2>&1 || r3=$?
        fi
        if [ "$r1" = 0 ] && cmp -s "$GP/lib/good.cyr" "$G/good.v1"; then ok "axis 7: deps $lab: rc 0, lib/good.cyr is the v1 file"
        else fail "axis 7: deps $lab: rc $r1, lib/good.cyr $(_size "$GP/lib/good.cyr") B (want rc 0 and the v1 file): $(tail -3 "$W/a7a.out" | tr '\n' '|' | head -c 300)"; fi
        if [ "$r2" = 0 ]; then ok "axis 7: deps again $lab (the cached clone re-verified through hash-object --stdin-paths): rc 0"
        else fail "axis 7: deps again $lab (the cached clone re-verified): rc $r2 (want 0): $(tail -3 "$W/a7b.out" | tr '\n' '|' | head -c 300)"; fi
        if [ "$r3" = 0 ] && grep -q 'newer tags: v2' "$W/a7c.out"; then ok "axis 7: update $lab (git ls-remote --tags into a capture): rc 0, 'newer tags: v2'"
        else fail "axis 7: update $lab: rc $r3, newer tags listed: $(grep -c 'newer tags: v2' "$W/a7c.out") (want rc 0 and 'newer tags: v2'): $(grep -i 'good\|error' "$W/a7c.out" | tr '\n' '|' | head -c 300)"; fi
    done
else
    echo "  SKIP-ROW: axis 7 (git dep with fd 0 closed): git is not installed here — the row did not run"
fi

if [ "$FAIL" = 0 ]; then
    echo "PASS: $NAME — child redirects in cbt/ and programs/ keep their std fds with the parent's fd 0, 1 or 2 closed (js / native / cx builds, run_cx, the cx JIT build, the check driver's output row, a git dep's deps / update), and no unguarded sys_dup2 / sys_close pair is left"
    exit 0
fi
exit 1
