#!/bin/sh
# agnos_regression_spawn.sh — 6.6.10. lib/regression_agnos.cyr's spawn / capture / deadline verbs
# RUN REAL CHILDREN on agnos, asserted on the exact syscalls they make against a scripted fake
# kernel (tests/fixtures/agnos_sctrace.cyr, its stateful rg* modes).
#
# ⛔ THE DEFECT. The ten verbs were v6.2.7 constant stubs — exec_run -1, exec_capture 0 bytes,
# run_with_timeout -1, pipe_to_bin -1, capture_status [-1, 0], … — and regression_deadline_kills /
# regression_last_deadline_ms / regression_terminate_children answered 0, although agnos has
# spawned from disk with an argv and a clean fd table (#43, 1.57.6), redirected a child's fds at
# spawn time (#62), reported real wait statuses and ended process trees (1.57.7) for three cuts.
# Measured on the 6.6.10 tree before the port: a probe calling all ten verbs made ZERO #25 / #43 /
# #62 / #4 / #16. The POSIX verbs are fork + dup2 + execve + /dev/null + temp files + poll(2), none
# of which agnos has, so the port is not a translation; the axes pin the four ways it had to differ:
#   * every child fd is a PIPE, and the outputs are DRAINED — never discarded through a closed read
#     end (the child's writes would fail where a /dev/null write succeeds), never a file fd
#     redirected into the child (vfs_fd_inherit copies a FAT write entry by value);
#   * ONE interleaved non-blocking pump — "write all of stdin, then read" deadlocks once the child
#     has written more than the 4080 B ring before it has read all of its input (axis 4, mode rgin);
#   * the source is streamed in chunks (no 1 MB alloc: the fake kernel answers mmap#27 with 0, so a
#     single allocation would crash the probe);
#   * the deadline kill is kill_tree(9) AT ONCE (SIGTERM has no default action on agnos), counted
#     in the SHARED regression_deadline_kills, and the wait polls #4 (WAIT_BLOCK has no timeout).
# PTRACE_SYSEMU runs nothing, so real children, real pipes and the real kernel are exercised on
# agnos-qemu at -smp 1 and 4 (CHANGELOG [6.6.10]); this gate is the off-target contract.
#
# MUTATION LEDGER (6.6.10, each measured RED here):
#   M1 _rga_pump writes ALL of stdin before its first read       -> axis 4 rgin: -2, stdin short
#   M2 the discard verbs close the stdout read end instead of draining -> axis 3 row "drained"
#   M3 _agnos_kill_reap sends SIGTERM (15) instead of kill_tree(9)  -> axis 1 rghang rows
#   M4 the deadline kill is not counted                           -> axis 1 rghang counters row
#   M5 stderr captured into the buffer on the stdout-only verb     -> axis 1 "stderr is not captured"
#   M6 the output pipes read with the BLOCKING sys_read             -> axis 1 "O_NONBLOCK" row
#   M7 _agnos_blob_ptrs drops its SPAWN_ARGC_MAX refusal            -> axis 6 "17 entries" row
#   M8 _rga_deliver ignores the output file's write result          -> axis 4 rgwfail + rgwshort rows
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_regression_spawn: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL agnos_regression_spawn: no compiler at $CC"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_regression_spawn: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# probe <name> <body> — an agnos program with regression.cyr, a static envp `ev` (set `sv(i, p)`,
# terminate with sv(n, 0)), a 64-byte `buf`, a status pair `st`, and the report `syscall(999, …)`.
probe() {
    cat > "$T/$1.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/regression.cyr"
var ev[24];
var buf[8];
var st[2];
fn sv(i, p): i64 { store64(&ev + i * 8, p); return 0; }
$2
sys_exit(0);
EOF
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2>"$T/$1.err" || {
        echo "  FAIL: probe $1 did not build"; grep -E '^error' "$T/$1.err" | head -3; fails=$((fails + 1)); }
    chmod +x "$T/$1.bin" 2>/dev/null
}
trace() { "$T/sct" "$T/$1.bin" "$2" > "$T/$1.$2.log" 2>&1 || true; }
L() { echo "$T/$1.$2.log"; }
mark() { awk -v t="$3" '$1 == "sc" && $2 == 999 && $3 == t { print $4, $5, $6; exit }' "$(L "$1" "$2")"; }
nsc()  { awk -v n="$3" '$1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$(L "$1" "$2")"; }
# The a1/a2 pairs of every call number $3, space-joined, in order.
args12() { awk -v n="$3" '$1 == "sc" && $2 == n { printf "%s%s:%s", s, $3, $4; s = " " } END { print "" }' "$(L "$1" "$2")"; }
# fds closed (close#6 a1), in order, up to the first read#5.
closed_before_read() { awk '$1 == "sc" && $2 == 5 { exit } $1 == "sc" && $2 == 6 { printf "%s%s", s, $3; s = " " } END { print "" }' "$(L "$1" "$2")"; }
# The a4 (O_NONBLOCK) of every read#5 on a pipe read end (odd fd 3..15), distinct.
pipe_read_a4() { awk '$1 == "sc" && $2 == 5 && $3 >= 3 && $3 <= 15 && $3 % 2 == 1 { print $6 }' "$(L "$1" "$2")" | sort -u | tr '\n' ' ' | sed 's/ $//'; }
blob() { awk '$1 == "blob" { sub(/^blob /, ""); print; exit }' "$(L "$1" "$2")"; }
envb() { awk '$1 == "env" { sub(/^env /, ""); print; exit }' "$(L "$1" "$2")"; }
# The stdin bytes the rgin child ACCEPTED (the fixture's `in <n>` lines), summed.
insum() { awk '$1 == "in" { s += $2 } END { print s + 0 }' "$(L "$1" "$2")"; }
wcount() { awk -v f="$3" '$1 == "sc" && $2 == 1 && $3 == f { c++ } END { print c + 0 }' "$(L "$1" "$2")"; }

# ── axis 0 — the verbs are no longer stubs ────────────────────────────────────────────────────
echo "axis 0 — each spawn verb reaches the kernel (the v6.2.7 stubs made no #43 at all):"
probe all 'sv(0, 0);
regression_exec_run("/bin/c", &ev);
regression_run_with_timeout("/bin/c", 1000, &ev);
regression_exec_capture("/bin/c", &buf, 64, &ev);
regression_exec_capture_status("/bin/c", &buf, 64, &ev, &st);
regression_exec_with_arg_capture("/bin/c", "a", &buf, 64, &ev);
regression_exec_with_arg_capture_status("/bin/c", "a", &buf, 64, &ev, &st);
regression_exec_with_arg_capture_both("/bin/c", "a", &buf, 64, &ev);
regression_exec_with_arg_capture_both_status("/bin/c", "a", &buf, 64, &ev, &st);
regression_pipe_to_bin("/bin/c", "/s", &ev);
regression_pipe_to_bin_capture("/bin/c", "/s", "/o", &ev);'
trace all rg
check "ten verbs, ten spawns (#43), each reaped (#4 answers -2 once, then 7 — one global count)" "10" \
    "$(nsc all rg 43)"
check "no spawn#3, no execwait#37, no mmap#27 (nothing allocated, no legacy in-memory spawn)" "0 0 0" \
    "$(nsc all rg 3) $(nsc all rg 37) $(nsc all rg 27)"
check "every child gets a clean fd table and a real argv (#43 a2 & 0x30000)" "196608" \
    "$(awk '$1 == "sc" && $2 == 43 && $3 != 0 { if (int($4 / 65536) % 4 != 3) bad = 1 } END { print (bad ? 0 : 196608) }' "$(L all rg)")"

# ── axis 1 — exec_capture_status: pipes, arms, close order, drain, status ─────────────────────
echo "axis 1 — exec_capture_status: three pipes, fds 0/1/2 armed, our child-ends closed, non-blocking drain:"
probe cap 'sv(0, "A=1"); sv(1, "B=two"); sv(2, 0);
var n = regression_exec_capture_status("/bin/child", &buf, 64, &ev, &st);
syscall(999, 1, n, load64(&st), load64(&st + 8));
syscall(999, 2, load8(&buf), regression_deadline_kills(), regression_last_deadline_ms());
syscall(999, 3, load8(&buf + 5), 0, 0);'
trace cap rg
check "three pipes: stdin (3/4), stdout (5/6), stderr (7/8)" "3" "$(nsc cap rg 25)"
check "#62: child 0 <- 3 (op 0 replaces the set), ADD 1 -> 6, ADD 2 -> 8" "0:3 257:6 258:8" "$(args12 cap rg 62)"
check "the argv blob is the path alone; the env blob carries envp" "/bin/child| A=1|B=two|" \
    "$(blob cap rg) $(envb cap rg)"
check "our copies of the child's ends (3, 6, 8) AND the stdin write end (4: EOF, as /dev/null) close before the first read" \
    "3 6 8 4" "$(closed_before_read cap rg)"
check "every pipe read is O_NONBLOCK (a4 = 1): no read can hang the verb" "1" "$(pipe_read_a4 cap rg)"
check "5 bytes captured, exit 7, no signal" "5 7 0" "$(mark cap rg 1)"
check "the captured bytes are STDOUT's (fd 5 -> 'E' = 69); no deadline kill counted" "69 0 0" "$(mark cap rg 2)"
check "stderr (fd 7, 'G') is drained but NOT captured" "0" "$(mark cap rg 3 | cut -d' ' -f1)"
check "  …and it WAS drained, to EOF (two reads of fd 7)" "2" \
    "$(awk '$1 == "sc" && $2 == 5 && $3 == 7 { c++ } END { print c + 0 }' "$(L cap rg)")"
trace cap rgsig
check "a death by SIGKILL (status 265) reads [0] = 128 + 9, [1] = 1" "5 137 1" "$(mark cap rgsig 1)"
trace cap rghang
check "a child that never ends: the deadline fires — 0 bytes, [0] = -2" "0 -2 0" "$(mark cap rghang 1)"
check "  …its TREE is killed with SIGKILL at once (#16 pid 2, 0x100 | 9 = 265), exactly once" "2:265" \
    "$(args12 cap rghang 16)"
check "  …and the kill is COUNTED in the shared counters, with the bound that fired (120 s default)" \
    "0 1 120000" "$(mark cap rghang 2)"
check "  …the bound is the CYRIUS_CHECK_TIMEOUT default: 1 + 480 quarter-second clock reads" "481" \
    "$(nsc cap rghang 95)"
trace cap rgold
check "a pre-1.57.7 kernel refuses the tree bit: the child alone gets SIGKILL" "2:265 2:9" "$(args12 cap rgold 16)"
trace cap rgbig
check "a child that never stops talking: buflen bytes kept, the rest drained, the deadline ends it" \
    "64 -2 0" "$(mark cap rgbig 1)"

# ── axis 2 — the arg verbs and the merged-stderr verb ─────────────────────────────────────────
echo "axis 2 — with_arg: the argument reaches the blob; _both merges fd 2 onto fd 1:"
probe both 'sv(0, 0);
var n = regression_exec_with_arg_capture_both_status("/bin/child", "-v x", &buf, 64, &ev, &st);
syscall(999, 1, n, load64(&st), load64(&st + 8));'
trace both rg
check "two pipes only (stdin, stdout+stderr)" "2" "$(nsc both rg 25)"
check "#62: 0 <- 3, ADD 1 -> 6, ADD 2 -> child fd 1 (shell 2>&1)" "0:3 257:6 258:1" "$(args12 both rg 62)"
check "the argument (with its space) is its own argv entry; an empty envp sends no env blob" \
    "/bin/child|-v x| none" "$(blob both rg) $(e=$(envb both rg); echo "${e:-none}")"
check "5 bytes, exit 7" "5 7 0" "$(mark both rg 1)"
probe arg 'sv(0, 0);
var n = regression_exec_with_arg_capture_status("/bin/child", "a", &buf, 64, &ev, &st);
syscall(999, 1, n, load64(&st), load64(&st + 8));'
trace arg rg
check "with_arg_capture_status: three pipes, stdout captured, exit 7" "3 | 5 7 0" "$(nsc arg rg 25) | $(mark arg rg 1)"

# ── axis 3 — the exit-code verbs discard by DRAINING ──────────────────────────────────────────
echo "axis 3 — exec_run / run_with_timeout: outputs drained (never a closed read end), exit codes, the bound:"
probe run 'sv(0, 0);
syscall(999, 1, regression_exec_run("/bin/child", &ev), 0, 0);'
trace run rg
check "exec_run: exit 7" "7 0 0" "$(mark run rg 1)"
check "  …its merged output pipe is DRAINED to EOF (read end 5 read twice, closed after)" "2" \
    "$(awk '$1 == "sc" && $2 == 5 && $3 == 5 { c++ } END { print c + 0 }' "$(L run rg)")"
trace run rgsig
check "exec_run on a SIGKILLed child: 128 + 9" "137 0 0" "$(mark run rgsig 1)"
probe rwt 'sv(0, 0);
syscall(999, 1, regression_run_with_timeout("/bin/child", 1000, &ev), 0, 0);
syscall(999, 2, regression_deadline_kills(), regression_last_deadline_ms(), 0);'
trace rwt rg
check "run_with_timeout: exit 7 inside the bound" "7 0 0" "$(mark rwt rg 1)"
trace rwt rghang
check "run_with_timeout at its bound: -2, the tree killed, counted with 1000 ms" "-2 0 0 | 1 1000 0 | 2:265" \
    "$(mark rwt rghang 1) | $(mark rwt rghang 2) | $(args12 rwt rghang 16)"
check "  …a 1 s bound is 1 + 4 quarter-second clock reads" "5" "$(nsc rwt rghang 95)"

# ── axis 4 — pipe_to_bin_capture: streamed, interleaved, written by the parent ────────────────
echo "axis 4 — pipe_to_bin_capture: the source streamed in chunks, stdin interleaved with stdout, the file written by us:"
probe pipe 'sv(0, 0);
syscall(999, 1, regression_pipe_to_bin_capture("/bin/cc", "/src/in.cyr", "/rx/outf", &ev), regression_deadline_kills(), 0);'
trace pipe rgin
check "a child that reads no more stdin until its stdout is drained: it completes, exit 7, no deadline" \
    "7 0 0" "$(mark pipe rgin 1)"
check "  …ALL 2100 source bytes reach its stdin (fd 4), in <= 512 B pieces the pipe accepted" "2100" \
    "$(insum pipe rgin)"
check "  …and each of its six stdout answers was written to the output file (fd 20)" "6" "$(wcount pipe rgin 20)"
check "the output file is opened AO_WRONLY|AO_CREAT|AO_TRUNC (0x301 = 769), then the source read-only" \
    "8:769 11:0" "$(awk '$1 == "sc" && $2 == 7 { printf "%s%s:%s", s, $4, $5; s = " " } END { print "" }' "$(L pipe rgin)")"
check "no file fd is ever redirected into the child (#62 targets are pipe ends only)" "0:3 257:6 258:8" \
    "$(args12 pipe rgin 62)"
check "the source is read in chunks of at most 2048 (no whole-file buffer)" "2048" \
    "$(awk '$1 == "sc" && $2 == 5 && $3 == 21 { if ($5 > m) m = $5 } END { print m + 0 }' "$(L pipe rgin)")"
trace pipe rghang
check "a child that never ends: -2 and one deadline kill" "-2 1 0" "$(mark pipe rghang 1)"
trace pipe rgwfail
check "the output file cannot be written (write#1 on fd 20 answers -1): -1, never exit 7 over a truncated file" \
    "-1 0 0" "$(mark pipe rgwfail 1)"
check "  …one write attempted and no retry after it; the child is still drained to EOF and reaped" "1 | 2 | 2" \
    "$(wcount pipe rgwfail 20) | $(awk '$1 == "sc" && $2 == 5 && $3 == 5 { c++ } END { print c + 0 }' "$(L pipe rgwfail)") | $(nsc pipe rgwfail 4)"
trace pipe rgwshort
check "a SHORT write to the output file is continued, not dropped: 5 bytes as 2 + 2 + 1, exit 7" "2 2 1 | 7 0 0" \
    "$(awk '$1 == "fw" { printf "%s%s", s, $2; s = " " } END { print "" }' "$(L pipe rgwshort)") | $(mark pipe rgwshort 1)"
probe pipe0 'sv(0, 0);
syscall(999, 1, regression_pipe_to_bin("/bin/cc", "/src/in.cyr", &ev), 0, 0);'
trace pipe0 rg
check "pipe_to_bin (discard): no output file is opened, only the source" "1 | 7 0 0" \
    "$(nsc pipe0 rg 7) | $(mark pipe0 rg 1)"

# ── axis 5 — terminate_children / reap_orphans ────────────────────────────────────────────────
echo "axis 5 — terminate_children ends the RUNNING direct children (proclist#99), reap_orphans reaps without waiting:"
probe tree 'syscall(999, 1, regression_terminate_children(5000), 0, 0);'
trace tree rgtree
check "one running direct child: counted (not the zombie, not the grandchild)" "1 0 0" "$(mark tree rgtree 1)"
check "  …ended with kill_tree(9) at once — no SIGTERM (it has no default action on agnos)" "2:265" \
    "$(args12 tree rgtree 16)"
check "  …and the loop ends when WAIT-ANY answers -1 (no children left): 4 polls" "4" "$(nsc tree rgtree 4)"
probe reap 'syscall(999, 1, regression_reap_orphans(), 0, 0);'
trace reap rg
check "reap_orphans with nothing ended: 0, one WAIT-ANY poll, no sleep" "0 0 0 | 1 0" \
    "$(mark reap rg 1) | $(nsc reap rg 4) $(nsc reap rg 41)"

# ── axis 6 — refusals leave nothing armed ─────────────────────────────────────────────────────
echo "axis 6 — an argv/env the kernel would refuse is refused before any pipe, THROUGH a #43:"
probe ref 'sv(0, "NOEQUALS"); sv(1, 0);
var n = regression_exec_capture_status("/bin/child", &buf, 64, &ev, &st);
syscall(999, 1, n, load64(&st), load64(&st + 8));
sv(0, 0);
syscall(999, 2, regression_exec_run("", &ev), 0, 0);'
trace ref rg
check "a non-KEY=VALUE env entry: 0 bytes, [-1, 0], no pipe made, one refusal #43 (a1 = 0)" \
    "0 -1 0 | 0" "$(mark ref rg 1) | $(awk '$1 == "sc" && $2 == 25 { c++ } $1 == "sc" && $2 == 999 { exit } END { print c + 0 }' "$(L ref rg)")"
check "an empty path: -1" "-1 0 0" "$(mark ref rg 2)"
check "  …both refusals reach the kernel as the peer's refusal #43 (a1 = 0, a2 = 0x40000)" "0:262144 0:262144" \
    "$(args12 ref rg 43)"
probe envn 'var i = 0;
while (i < 17) { sv(i, "K=V"); i = i + 1; }
sv(17, 0);
var n = regression_exec_capture_status("/bin/child", &buf, 64, &ev, &st);
syscall(999, 1, n, load64(&st), load64(&st + 8));
sv(16, 0);
n = regression_exec_capture_status("/bin/child", &buf, 64, &ev, &st);
syscall(999, 2, n, load64(&st), load64(&st + 8));'
trace envn rg
check "an envp of 17 KEY=VALUE entries (over #43's 16): 0 bytes, [-1, 0], no pipe, the refusal #43 — never truncated" \
    "0 -1 0 | 0 | 0:262144" "$(mark envn rg 1) | $(awk '$1 == "sc" && $2 == 25 { c++ } $1 == "sc" && $2 == 999 { exit } END { print c + 0 }' "$(L envn rg)") | $(args12 envn rg 43 | cut -d' ' -f1)"
check "  …16 entries (the limit) are sent whole: 5 bytes, exit 7, an env blob of 16 entries" "5 7 0 | 16" \
    "$(mark envn rg 2) | $(envb envn rg | tr -cd '|' | wc -c | tr -d ' ')"

if [ "$fails" -ne 0 ]; then echo "FAIL agnos_regression_spawn: $fails check(s)"; exit 1; fi
echo "PASS agnos_regression_spawn"
exit 0
