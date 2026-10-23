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
#   * embed_link_race_pe.sh, pe_lockfileex_reroute.sh, pe_reroute_failure_errno.sh (6.7.17) — a
#     fn-body helper `code FILE | awk '… { exit }'`: awk exits at the fn's closing brace while
#     `grep -v` is still writing the rest of a large file (cbt/manifest.cyr 123 KB, lib/io.cyr,
#     lib/syscalls_windows.cyr), grep dies of SIGPIPE, and `eo=$(fnbody …)` stopped the gate with
#     rc 141 and NO output — embed_link_race_pe on 89 of 100 runs, the other two on 3-4 of 100.
#     awk now reads the file itself, and no reader below a pipe exits before its input ends —
#     anywhere in the three (the 6.7.17 review): `objdump -p X | grep -qE …` under `if` read a
#     present import as missing (a 15.5 KB listing: 49 of 300 runs), a `tr … | grep -q` could miss
#     a SKIP line, `printf "$body" | grep -q` / `| grep -n … | head -1` and a failing run's
#     `tr … | grep -m6 'FAIL:'` stopped or lied once their input outgrew one write. Axis 3 scans
#     them for the shape.
#   * stack_enum_closure_return_scope.sh, stack_enum_mixed_return_warning.sh (6.7.17, met reviewing D26) — a
#     refusal row's build `"$T/$1" < .. 2> ..; BRC=$?` (and `rc=$?`, a run's `RRC=$?`) and a zero-count
#     `n=$(grep -c ..)`: `-e` ended each gate on its first refused build or silent fixture, rc 1 and NO output. Each is
#     `X=0; cmd || X=$?` / `|| true` now.
#   * coroutine_midbody_suspend.sh (6.7.17) — a probe run `timeout 30 "$T/a1"; got=$?`: the probe exits 42 when it
#     passes, so `-e` ended the gate on its first passing probe with rc 42; each is `got=0; .. || got=$?` now.
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
#           so by name). check.sh runs each of them under `sh` as its own row. They run in a
#           pool bounded the way check.sh bounds its own (6.7.18), a `# check: serial` one after
#           it, alone.
#   axis 3  STATIC, over NOPIPE: no early-exiting reader below a pipe — `grep` with -q / -m / -l /
#           -L, head, read, cmp, an awk whose script exits, a sed whose script quits — on any
#           command line (comments skipped, `\` continuations joined). Its latent cases pass axis 2
#           (a writer whose output fits one write never meets the early exit), so only a scan holds
#           them. The scanner proves it sees on two fixtures: every early spelling is reported, and
#           the safe ones (a file grepped where it lies, a here-document, grep -c / -n, tail, an awk
#           that stops printing, `||`, a `while read` loop) are not.
#   axis 4  a RED gate reaches its own FAIL verdict under bash -eo pipefail: STATIC, no
#           assignment in a NOPIPE gate runs grep without `|| true` / `|| :` (fixtures: 4 failing,
#           6 safe); and pe_lockfileex_reroute.sh with _xflock_win's negative-fd check deleted and
#           embed_link_race_pe.sh with _embed_open's Windows arm renamed, each run from a scratch
#           root where every build fails, end with their own `FAIL: <gate>` line naming that row.
# Mutation (6.7.15): any gate's fix reverted (axis 2's `|| true` dropped, the census's
# `for-each-ref` back to `git tag … | head -1`, axis 5's `prc=0; ( … ) || prc=$?` back to
# `( … ); prc=$?`) -> RED here naming the gate, its rc and its last lines; 6.7.16: the
# agnos-crossbuild-gate.sh server-probe greps back to `echo "$sdis" | grep -q` -> RED (FAIL, rc 1);
# 6.7.17: embed_link_race_pe.sh's fnbody back behind `code "$1" |` -> RED (STOPPED, rc 141, no
# output); pe_lockfileex_reroute.sh's UnlockFileEx import check back to `objdump … | grep -qE` ->
# axis 3 RED naming the line; the scanner's grep-option test dropped -> axis 3 RED (the early
# fixture's grep rows unreported); lno's `|| :` dropped -> axis 4 RED (the mutant stops at
# `neg=$(lno …)`); a build's `|| true` dropped -> axis 4 RED (the mutant stops at that build).
# Add a gate to GATES when its pipefail stop or false verdict is fixed. CHANGELOG [6.7.17]
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
tests/gates/toolchain/cli_temp_dir_no_leak.sh
tests/gates/toolchain/embed_link_race_pe.sh
tests/gates/platform/pe_lockfileex_reroute.sh
tests/gates/platform/pe_reroute_failure_errno.sh
tests/gates/frontend/stack_enum_closure_return_scope.sh
tests/gates/frontend/stack_enum_mixed_return_warning.sh
tests/gates/frontend/coroutine_midbody_suspend.sh"

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
# The gates run side by side in a BOUNDED pool — check.sh's own worker rule (CYRIUS_CHECK_JOBS, else
# half the online CPUs, capped at 8), not one process per listed gate — and a gate marked
# `# check: serial` (a timing measurement check.sh runs alone) runs after the pool, alone, as check.sh
# runs it. Each one's rc lands in its own file, and every PID is waited on. CHANGELOG [6.7.18]
_jobs() {
    _j="${CYRIUS_CHECK_JOBS:-}"
    if [ -z "$_j" ]; then
        _j=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
        case "$_j" in ''|*[!0-9]*) _j=2 ;; esac
        _j=$((_j / 2))
        if [ "$_j" -gt 8 ]; then _j=8; fi
    fi
    case "$_j" in ''|*[!0-9]*|0) _j=1 ;; esac
    echo "$_j"
}
_running() {  # how many started pool gates have not written their rc yet
    _r=0
    for _n in $STARTED; do
        if [ ! -f "$D/gate$_n.rc" ]; then _r=$((_r + 1)); fi
    done
    echo "$_r"
}
_run_one() {  # $1 = N, $2 = gate
    grc=0; bash -eo pipefail "$2" > "$D/gate$1.out" 2>&1 < /dev/null || grc=$?; echo "$grc" > "$D/gate$1.rc"
}
JOBS=$(_jobs)
N=0; PIDS=""; STARTED=""; : > "$D/serial.list"
for g in $GATES; do
    N=$((N + 1))
    [ -f "$g" ] || continue
    if grep -q '^# check: serial' "$g"; then echo "$N $g" >> "$D/serial.list"; continue; fi
    while [ "$(_running)" -ge "$JOBS" ]; do sleep 0.2; done
    _run_one "$N" "$g" &
    PIDS="$PIDS $!"; STARTED="$STARTED $N"
done
for p in $PIDS; do wait "$p" || true; done
while read -r n g; do _run_one "$n" "$g"; done < "$D/serial.list"
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

# ── axis 3: no early-exiting reader below a pipe in the NOPIPE gates ────────────────────
NOPIPE="tests/gates/toolchain/embed_link_race_pe.sh
tests/gates/platform/pe_lockfileex_reroute.sh
tests/gates/platform/pe_reroute_failure_errno.sh"
# _early FILE: "LINE: text" for each command line with a reader below a single `|` that can stop
# before its input ends.
_early() {
    awk '
    function word_after(s, i,    t) { t = substr(s, i); sub(/^[[:space:]]+/, "", t); return t }
    function script(t,    a, b, n, k, w) {   # the first single-quoted script, else the first operand
        a = index(t, "\047")
        if (a > 0) { b = index(substr(t, a + 1), "\047"); if (b > 0) return substr(t, a + 1, b - 1) }
        n = split(t, w, /[[:space:]]+/)
        for (k = 1; k <= n; k++) if (w[k] != "" && substr(w[k], 1, 1) != "-") return w[k]
        return ""
    }
    function early(t,    cmd, rest, n, k, tok) {
        if (!match(t, /^[A-Za-z_][A-Za-z_0-9]*/)) return 0
        cmd = substr(t, 1, RLENGTH); rest = substr(t, RLENGTH + 1)
        if (cmd == "head" || cmd == "read" || cmd == "cmp" || cmd == "line") return 1
        if (cmd == "grep") {
            n = split(rest, tok, /[[:space:]]+/)
            for (k = 1; k <= n; k++) {
                if (tok[k] == "") continue
                if (substr(tok[k], 1, 1) != "-") break
                if (tok[k] ~ /^-[A-Za-z0-9]*[qlLm]/ || tok[k] ~ /^--(quiet|silent|max-count|files-with)/) return 1
            }
            return 0
        }
        if (cmd == "awk") return script(rest) ~ /(^|[^A-Za-z_0-9])exit([^A-Za-z_0-9]|$)/
        if (cmd == "sed") return script(rest) ~ /(^|[;{}[:space:]0-9$\/])[qQ][0-9]*[[:space:]]*($|[;}])/
        return 0
    }
    !cont && /^[[:space:]]*#/ { next }
    {
        if (!cont) { start = FNR; buf = "" }
        if ($0 ~ /\\$/) { buf = buf substr($0, 1, length($0) - 1) " "; cont = 1; next }
        buf = buf $0; cont = 0
        L = length(buf)
        for (i = 1; i <= L; i++) {
            if (substr(buf, i, 1) != "|") continue
            if (i > 1 && substr(buf, i - 1, 1) == "|") continue
            if (i < L && substr(buf, i + 1, 1) == "|") continue
            if (early(word_after(buf, i + 1))) { printf "%d: %s\n", start, buf; break }
        }
    }' "$1"
}
# The scanner sees: each of the 15 early spellings (one command line each) is reported ...
cat > "$D/early.fx" <<'XEOF'
x=$(printf '%s\n' "$b" | grep -q 'p')
printf '%s\n' "$b" | grep -qE 'p' || bad x
objdump -p f | grep -E -q 'p'
tr -d '\r' < f | grep -m6 'FAIL:' | sed 's/^/ /'
cat f | grep -m 2 '^error'
cat f | grep -l x
cat f | grep --quiet x
a=$(printf '%s\n' "$b" | grep -n 'p' | head -1 | cut -d: -f1)
awk '{ print }' f \
    | awk '/x/ { print; exit }'
yes | sed 1q
yes | sed -n '/x/{p;q}'
cmd | read v
cmd | cmp -s - f
bad "it reads: $(cat a b | grep -m2 '^error' | tr '\n' ' ')"
yes | sed -n 5q
XEOF
# ... and none of the safe ones is.
cat > "$D/safe.fx" <<'XEOF'
grep -q 'p' f
grep -m6 'FAIL:' f | tr -d '\r' | sed 's/^/ /'
n=$(printf '%s\n' "$b" | grep -c 'p' || true)
x=$(tr -d '\r' < f | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' | tail -1)
fnbody "$1" | awk 'w < 2 && /^#ifdef/ { w = 1; next } w == 1 { print; w = 2 }'
awk '/^fn x\(/ { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }' "$IO" \
    | awk 'w == 1 { print }'
cmd || head -1 f
printf '%s' "$x" | tr -s ' '
cmd | while read l; do :; done
    # a comment | grep -q x
awk '/^error/ && n++ < 2' f1 f2 | tr '\n' ' '
    grep -n -m1 -e "$2" <<EOF | cut -d: -f1
od -An -v -tx4 -w4 f | tr -d ' ' > g
BEGIN { np = split("^cmp +\\$0x2,%rax|^ja |G|^cmp +\\$0x1,%rax", pat, "|") }
XEOF
f3=$FAILS
ne=$(_early "$D/early.fx" | wc -l | tr -d ' ')
[ "$ne" = 15 ] || _fail "axis 3: the scanner reports $ne of the fixture's 15 early readers (the lines it saw: $(_early "$D/early.fx" | cut -d: -f1 | tr '\n' ' ')) — it is blind to the rest"
if [ -n "$(_early "$D/safe.fx")" ]; then
    _fail "axis 3: the scanner reports a safe spelling: $(_early "$D/safe.fx" | tr '\n' ' ')"
fi
ng=0
for g in $NOPIPE; do
    ng=$((ng + 1))
    if [ ! -f "$g" ]; then _fail "axis 3: $g is listed but missing"; continue; fi
    _early "$g" > "$D/early.out"
    if [ -s "$D/early.out" ]; then
        _fail "axis 3: $g has a reader below a pipe that can stop before its input ends (its writer dies of SIGPIPE, which pipefail reads as the pipeline failing):"
        sed 's/^/        /' "$D/early.out"
    fi
done
[ "$ng" -ge 3 ] || _fail "axis 3: only $ng gates listed in NOPIPE (floor 3)"
[ "$FAILS" = "$f3" ] && echo "  ok: axis 3: no early-exiting reader below a pipe in the $ng NOPIPE gates (the scanner reports all 15 early spellings and none of the safe ones)"

# ── axis 4: a RED gate reaches its own FAIL verdict under bash -eo pipefail ─────────────
# Axis 2 runs the passing path only. A failure path meets `-e` too: a grep assignment that finds
# nothing, a build that fails, an empty FAIL listing ended the gate before the row naming the
# failure — red, but with no FAIL line. (a) STATIC over NOPIPE: an assignment from a command
# substitution that runs grep ends `|| true` or `|| :`. (b) Two mutants run under bash -eo pipefail
# in a scratch root holding only what their static axes read (so every build there fails), and each
# must reach its own last line `FAIL: <gate>` with the mutated row named.
_grep_assign() {  # $1 = a shell file -> "LINE: text" for each grep assignment that can fail
    awk '
    !cont && /^[[:space:]]*#/ { next }
    {
        if (!cont) { start = FNR; buf = "" }
        if ($0 ~ /\\$/) { buf = buf substr($0, 1, length($0) - 1) " "; cont = 1; next }
        buf = buf $0; cont = 0
        if (buf !~ /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z_0-9]*=\$\(/) next
        if (buf !~ /(^|[|(;&[:space:]])grep([[:space:]]|$)/) next
        if (buf ~ /\|\|[[:space:]]*(true|:)([[:space:])]|$)/) next
        printf "%d: %s\n", start, buf
    }' "$1"
}
cat > "$D/gassign.fx" <<'XEOF'
n=$(grep -c x f)
x=$(printf '%s\n' "$b" | grep -n y | cut -d: -f1)
w=$(grep -A2 'p' <<EOF
    export Z=$(grep q f)
XEOF
cat > "$D/gsafe.fx" <<'XEOF'
n=$(grep -c x f || true)
F=$(grep -o y f | tr '\n' ' ' || true)
w=$(grep -A2 'p' <<EOF || true
s=$(awk '{ print }' f)
if x=$(grep a f); then :; fi
nsym=$(printf '%s\n' "$s" | grep -c 'syscall(61502,' || :)
XEOF
f4=$FAILS
na=$(_grep_assign "$D/gassign.fx" | wc -l | tr -d ' ')
[ "$na" = 4 ] || _fail "axis 4: the assignment scanner reports $na of the fixture's 4 failing grep assignments"
if [ -n "$(_grep_assign "$D/gsafe.fx")" ]; then
    _fail "axis 4: the assignment scanner reports a safe spelling: $(_grep_assign "$D/gsafe.fx" | tr '\n' ' ')"
fi
for g in $NOPIPE; do
    [ -f "$g" ] || continue
    _grep_assign "$g" > "$D/gassign.out"
    if [ -s "$D/gassign.out" ]; then
        _fail "axis 4: $g assigns a grep's output with no \`|| true\` (with nothing found, \`-e\` ends the gate there):"
        sed 's/^/        /' "$D/gassign.out"
    fi
done
# _mutant <name> <gate path> <mutated row's text>: run the scratch root's copy of the gate.
_mutant() {
    mrc=0
    CYCC="${CYCC:-$ROOT/build/cycc}" bash -eo pipefail "$D/m_$1/$2" > "$D/m_$1.out" 2>&1 < /dev/null || mrc=$?
    mlast=$(grep -v '^[[:space:]]*$' "$D/m_$1.out" | tail -1 || true)
    case "$mrc:$mlast" in
        "1:FAIL: $1"*) ;;
        *) _fail "axis 4: the mutant $1 under bash -eo pipefail exited $mrc without its own verdict (last line: '$mlast')"; return 0 ;;
    esac
    grep -qF "$3" "$D/m_$1.out" || _fail "axis 4: the mutant $1 reached FAIL but never named the mutated row ('$3')"
}
L4="$D/m_pe_lockfileex_reroute"
mkdir -p "$L4/tests/gates/platform" "$L4/lib" "$L4/tests/tcyr/crossos"
cp tests/gates/platform/pe_lockfileex_reroute.sh "$L4/tests/gates/platform/"
grep -vF 'if (fd < 0) { return 0 - 9; }' lib/io.cyr > "$L4/lib/io.cyr" || true
printf 'not cyrius\n' > "$L4/tests/tcyr/crossos/xflock_two_handle.tcyr"
printf 'not cyrius\n' > "$L4/tests/tcyr/crossos/xflock_relock_keeps_lock.tcyr"
_mutant pe_lockfileex_reroute tests/gates/platform/pe_lockfileex_reroute.sh \
    'axis 4: _xflock_win does not answer a negative fd -9 before its first lock call'
E4="$D/m_embed_link_race_pe"
mkdir -p "$E4/tests/gates/toolchain" "$E4/cbt" "$E4/lib" "$E4/tests/tcyr/crossos"
cp tests/gates/toolchain/embed_link_race_pe.sh "$E4/tests/gates/toolchain/"
cp lib/fs_win.cyr "$E4/lib/"
awk 'index($0, "fn _embed_open(") == 1 { s = 1 }
     s == 1 && $0 == "    #ifdef CYRIUS_TARGET_WIN" { $0 = "    #ifdef MUTANT_CYRIUS_TARGET_WIN" }
     { print } s == 1 && /^}/ { s = 0 }' cbt/manifest.cyr > "$E4/cbt/manifest.cyr"
printf 'not cyrius\n' > "$E4/tests/tcyr/crossos/embed_open_under_root.tcyr"
_mutant embed_link_race_pe tests/gates/toolchain/embed_link_race_pe.sh \
    "axis 4: _embed_open's CYRIUS_TARGET_WIN arm does not return _embed_open_win(path, fl)"
[ "$FAILS" = "$f4" ] && echo "  ok: axis 4: no grep assignment can end a NOPIPE gate; two mutants reach their own FAIL verdict under bash -eo pipefail, naming the mutated row"

if [ "$FAILS" != 0 ]; then echo "FAIL: $NAME ($FAILS)"; exit 1; fi
echo "PASS: $NAME ($N gates reach their verdict under bash -eo pipefail; the checker tells a stop from a verdict; no early-exiting reader below a pipe in the $ng NOPIPE gates; a red one reaches its own FAIL verdict)"
