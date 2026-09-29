#!/bin/sh
# agnos_async_process.sh — 6.6.10. lib/async_agnos.cyr's async_timeout BOUNDS its body in a forked
# child, async_run_process spawns from disk under a deadline, and async_spawn_process is a serial
# task around that — asserted on the exact syscalls, against the scripted fake kernel
# (tests/fixtures/agnos_sctrace.cyr, its as* modes).
#
# ⛔ THE DEFECT. async_timeout(fp, arg, ms) ran the body INLINE and ignored `ms` — measured on the
# 6.6.10 tree: a body that sleeps 5 s under a 100 ms bound traced `sc 41 5000`, returned the body's
# value, and made no fork#96 and no pipe#25 — and async_run_process / async_spawn_process were the
# constants -1 / 0, although agnos has had fork#96 (1.56.55), the from-disk spawn #43 (1.57.6) and
# a real wait status + kill_tree (1.57.7). The async_timeout contract (the Linux one): the body's
# value, or -1 when it did not finish in time; the child delivers its u64 through a pipe and only
# a WHOLE 8-byte read counts, so a child that died mid-way is -1, never stale bytes.
# ⚠ PTRACE_SYSEMU does not execute fork, so one trace proves ONE side of it: mode `as` answers
# #96 with a pid (the parent's path), `aschild` with 0 (the child's). Only agnos-qemu runs both
# together (CHANGELOG [6.6.10], -smp 1 and 4).
#
# MUTATION LEDGER (6.6.10, each measured RED here):
#   MA1 async_timeout runs the body inline again (the 6.6.8 body)   -> axis 1, axis 3
#   MA2 the result read takes a short read as the result             -> axis 4
#   MA3 no kill at the deadline (the child is left running)          -> axis 3 kill row
#   MA4 async_run_process ignores `ms`                               -> axis 5 deadline row
#   MA5 the caller's argv[0] is sent instead of `path`               -> axis 5 blob row
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_async_process: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL agnos_async_process: no compiler at $CC"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_async_process: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# probe <name> <body> — an agnos program with lib/async.cyr, a body fn `bd(a)` = a + 70 that also
# sleeps 5 s (so an INLINE run shows as `sc 41 5000`), static argv/envp arrays `av` / `ev` (set
# with `sa(i, p)` / `se(i, p)`), a runtime `rt` over a static bump allocator (the fake kernel
# answers mmap#27 with 0, so nothing may allocate), and the report `syscall(999, …)`.
probe() {
    cat > "$T/$1.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/async.cyr"
var av[8];
var ev[8];
var pool[512];
var poolo = 0;
var vt[5];
fn sa(i, p): i64 { store64(&av + i * 8, p); return 0; }
fn se(i, p): i64 { store64(&ev + i * 8, p); return 0; }
fn bd(a): i64 { sys_sleep_ms(5000); return a + 70; }
fn palloc(state, size): i64 { var p = &pool + poolo; poolo = poolo + ((size + 7) / 8) * 8; return p; }
fn pnone(state, p): i64 { return 0; }
store64(&vt, &palloc); store64(&vt + 8, 0); store64(&vt + 16, &pnone); store64(&vt + 24, 0); store64(&vt + 32, 0);
var rt = async_new_in(&vt);
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
args12() { awk -v n="$3" '$1 == "sc" && $2 == n { printf "%s%s:%s", s, $3, $4; s = " " } END { print "" }' "$(L "$1" "$2")"; }
seq_of() { awk '$1 == "sc" && $2 != 999 && $2 != 0 && $2 != 95 && $2 != 46 && $2 != 41 { printf "%s%s", s, $2; s = " " } END { print "" }' "$(L "$1" "$2")"; }
blob() { awk '$1 == "blob" { sub(/^blob /, ""); print; exit }' "$(L "$1" "$2")"; }
envb() { awk '$1 == "env" { sub(/^env /, ""); print; exit }' "$(L "$1" "$2")"; }
inline_sleep() { awk '$1 == "sc" && $2 == 41 && $3 == 5000 { c++ } END { print c + 0 }' "$(L "$1" "$2")"; }

# ── axis 1 — async_timeout, the PARENT side ───────────────────────────────────────────────────
echo "axis 1 — async_timeout forks the body and reads its result from a pipe (the parent's side):"
probe to 'syscall(999, 1, async_timeout(&bd, 7, 100), 0, 0);'
trace to as
check "pipe, fork, close(write end), the result read, close(read end), reap" "25 96 6 5 6 4" "$(seq_of to as)"
check "the value is the one the CHILD wrote through the pipe (4242), not a local run of the body" \
    "4242 0 0" "$(mark to as 1)"
check "the body did not run in the parent (no 5 s sleep here)" "0" "$(inline_sleep to as)"
check "the result read is O_NONBLOCK (a4 = 1): the deadline can interrupt it" "1" \
    "$(awk '$1 == "sc" && $2 == 5 { print $6; exit }' "$(L to as)")"

# ── axis 2 — async_timeout, the CHILD side ────────────────────────────────────────────────────
echo "axis 2 — the child runs the body, writes exactly its 8-byte result to the pipe, and exits:"
trace to aschild
check "the body runs (its 5 s sleep), then ONE 8-byte write of 77 to the write end (fd 4)" "1 | 4 8 77" \
    "$(inline_sleep to aschild) | $(awk '$1 == "wr" { print $2, $3, $4; exit }' "$(L to aschild)")"
check "  …and it exits 0 without reporting back into the caller's code" "exit 0 | none" \
    "$(awk '$1 == "exit" { print "exit", $2 }' "$(L to aschild)") | $(m=$(mark to aschild 1); echo "${m:-none}")"

# ── axis 3 — the deadline ─────────────────────────────────────────────────────────────────────
echo "axis 3 — a body that never delivers: -1 at the deadline, the child's tree SIGKILLed and reaped:"
trace to asslow
check "async_timeout returns -1" "-1 0 0" "$(mark to asslow 1)"
check "  …after killing the child's TREE with SIGKILL (#16 pid 5, 0x100 | 9)" "5:265" "$(args12 to asslow 16)"
check "  …and reaping it (#4 on pid 5 after the kill)" "yes" \
    "$(awk '$1 == "sc" && $2 == 16 { k = 1 } k && $1 == "sc" && $2 == 4 && $3 == 5 { r = 1 } END { print (r ? "yes" : "no") }' "$(L to asslow)")"
check "  …with the 100 ms bound it was given: 2 quarter-second clock reads" "2" "$(nsc to asslow 95)"

# ── axis 4 — a body that dies mid-result ──────────────────────────────────────────────────────
echo "axis 4 — only a whole 8-byte result counts:"
trace to asshort
check "3 bytes then EOF (the child died): -1, never the stale bytes" "-1 0 0" "$(mark to asshort 1)"

# ── axis 5 — async_run_process ────────────────────────────────────────────────────────────────
echo "axis 5 — async_run_process spawns from disk with path + argv[1..] and waits under its deadline:"
probe rp 'sa(0, "whatever-argv0"); sa(1, "one two"); sa(2, "x"); sa(3, 0);
se(0, "K=V"); se(1, 0);
syscall(999, 1, async_run_process(rt, "/bin/p", &av, &ev, 1000), 0, 0);'
trace rp as
check "the blob is PATH then argv[1..] (agnos opens argv[0]; the caller's argv[0] is dropped)" \
    "/bin/p|one two|x|" "$(blob rp as)"
check "  …the env blob carries envp; the spawn has a clean fd table (#43 flags 0x30000)" "K=V| 3" \
    "$(envb rp as) $(awk '$1 == "sc" && $2 == 43 { print int($4 / 65536) % 4; exit }' "$(L rp as)")"
check "exit code 7 (the #4 poll answered -2, then 7)" "7 0 0" "$(mark rp as 1)"
trace rp asslow
check "at the 1 s deadline: -2, the tree killed with SIGKILL" "-2 0 0 | 2:265" "$(mark rp asslow 1) | $(args12 rp asslow 16)"
probe rp0 'sa(0, 0);
se(0, 0);
syscall(999, 1, async_run_process(rt, "/bin/p", &av, &ev, 0), 0, 0);'
trace rp0 as
check "ms 0: no deadline — no clock read at all, exit 7; an empty argv / envp: the path alone, no env" \
    "0 | 7 0 0 | /bin/p| | none" "$(nsc rp0 as 95) | $(mark rp0 as 1) | $(blob rp0 as) | $(e=$(envb rp0 as); echo "${e:-none}")"

# ── axis 6 — async_spawn_process is a serial task ─────────────────────────────────────────────
echo "axis 6 — async_spawn_process returns a task; the spawn happens when the loop runs it:"
probe sp 'sa(0, 0);
se(0, 0);
var h = async_spawn_process(rt, "/bin/p", &av, &ev);
syscall(999, 1, h != 0, 0, 0);
syscall(999, 2, task_join(rt, h), 0, 0);'
trace sp as
check "a non-zero handle, and NO spawn before the join" "1 0 0 | 0" \
    "$(mark sp as 1) | $(awk '$1 == "sc" && $2 == 999 { exit } $1 == "sc" && $2 == 43 { c++ } END { print c + 0 }' "$(L sp as)")"
check "task_join runs it: one #43, result = the exit code 7" "1 | 7 0 0" "$(nsc sp as 43) | $(mark sp as 2)"

if [ "$fails" -ne 0 ]; then echo "FAIL agnos_async_process: $fails check(s)"; exit 1; fi
echo "PASS agnos_async_process"
exit 0
