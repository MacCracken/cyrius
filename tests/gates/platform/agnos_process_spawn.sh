#!/bin/sh
# agnos_process_spawn.sh — v6.6.8. lib/process_agnos.cyr spawns from disk with a real argv and a
# clean fd table, BLOCKS until the child exits, and captures stdout by reading a pipe to EOF
# before it reaps — asserted on the exact syscalls it makes, against a scripted fake kernel.
#
# ⛔ THE DEFECT. process_agnos (v6.0.56) read the whole ELF into an 8 MB alloc it never freed and
# handed it to spawn#3, which refuses any image over 16 KB — so a println hello (15 KB) was about
# the largest program it could start, and each call leaked 8 MB. It then called waitpid#4 ONCE:
# #4 without the 0x100 bit is a POLL that answers -2 while the child lives, so `run` returned
# Err(1) before the child had finished, `wait_pid` returned Err(2), and every `exec_*` reported
# -2 as the child's "exit code". No argument ever reached the child, and no capture variant
# captured. The rewrite uses spawn_path#43 (SPAWN_F_ARGV | SPAWN_F_CLEANFD), WAIT_BLOCK, and a
# pipe armed on child fd 1 through exec_redirect#62.
#
# tests/fixtures/agnos_sctrace.cyr runs each agnos probe under PTRACE_SYSEMU: nothing executes,
# every syscall is logged and answered from its proc* tables, and each #43 is followed by the
# argv blob it was handed (NUL shown as `|`). The probes build their vecs in static memory
# because the fake kernel answers mmap#27 with 0 — which also makes "a spawn allocates nothing"
# checkable: a single #27 would crash the probe. Real children, real pipes and the real kernel
# are exercised on agnos-qemu (see CHANGELOG [6.6.8]); this gate is the off-target contract.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_process_spawn: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_process_spawn: no build/cycc"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_process_spawn: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# probe <name> <body> — an agnos program with two static vecs (`va`, `ve`: set element i with
# `sa(i, p)` / `se(i, p)`, then pass `av(n)` / `ev(n)`), a 64-byte `buf`, and the report
# `syscall(999, tag, x, y, z)`.
probe() {
    cat > "$T/$1.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/tagged.cyr"
include "lib/process.cyr"
var vah[3];
var vad[20];
var veh[3];
var ved[20];
var buf[8];
var st[2];
fn sa(i, p): i64 { store64(&vad + i * 8, p); return 0; }
fn se(i, p): i64 { store64(&ved + i * 8, p); return 0; }
fn av(n): i64 { store64(&vah, &vad); store64(&vah + 8, n); store64(&vah + 16, 20); return &vah; }
fn ev(n): i64 { store64(&veh, &ved); store64(&veh + 8, n); store64(&veh + 16, 20); return &veh; }
$2
sys_exit(0);
EOF
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2>"$T/$1.err" || {
        echo "  FAIL: probe $1 did not build"; grep -E '^error' "$T/$1.err" | head -3; fails=$((fails + 1)); }
    chmod +x "$T/$1.bin" 2>/dev/null
}
trace() { "$T/sct" "$T/$1.bin" "$2" > "$T/$1.$2.log" 2>&1 || true; }       # probe mode
mark() { awk -v t="$3" '$1 == "sc" && $2 == 999 && $3 == t { print $4, $5, $6; exit }' "$T/$1.$2.log"; }
blob() { awk '$1 == "blob" { sub(/^blob /, ""); print; exit }' "$T/$1.$2.log"; }
envb() { awk '$1 == "env" { sub(/^env /, ""); print; exit }' "$T/$1.$2.log"; }
nsc()  { awk -v n="$3" '$1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/$1.$2.log"; }
seq_of() { awk '$1 == "sc" && $2 != 999 && $2 != 0 { printf "%s%s", s, $2; s = " " } END { print "" }' "$T/$1.$2.log"; }
# Every syscall a legacy spawn needed and the rewrite must not make: spawn#3, open#7, mmap#27.
legacy() { echo "$(nsc "$1" "$2" 3) $(nsc "$1" "$2" 7) $(nsc "$1" "$2" 27)"; }

# ── axis 1 — capture: the order is the contract ─────────────────────────────────────────────
echo "axis 1 — exec_capture_status: pipe, arm fd 1, spawn, close the write end, read to EOF, THEN reap:"
probe cap 'sa(0, "/bin/child"); sa(1, "one two"); sa(2, ""); sa(3, "x");
var n = exec_capture_status(av(4), &buf, 64, &st);
syscall(999, 1, n, load64(&st), load64(&st + 8));'
trace cap proc
check "the syscalls, in order: pipe#25 → #62 → #43 → close(w) → read → read(EOF) → close(r) → #4" \
    "25 62 43 6 5 5 6 4" "$(seq_of cap proc)"
check "#62 arms CHILD fd 1 onto the pipe's write end (fd 4)" "1 4" \
    "$(awk '$1 == "sc" && $2 == 62 { print $3, $4; exit }' "$T/cap.proc.log")"
check "#43 is the flagged form: len 22 | SPAWN_F_ARGV | SPAWN_F_CLEANFD (0x30016)" "196630" \
    "$(awk '$1 == "sc" && $2 == 43 { print $4; exit }' "$T/cap.proc.log")"
check "the argv blob carries every argument — a space and an EMPTY one survive" \
    "/bin/child|one two||x|" "$(blob cap proc)"
check "the child's write end is closed BEFORE the first read (else EOF never comes)" "4" \
    "$(awk '$1 == "sc" && $2 == 6 { print $3; exit }' "$T/cap.proc.log")"
check "the wait is WAIT_BLOCK on pid 2 (0x100 | 2 = 258), not the #4 poll" "258" \
    "$(awk '$1 == "sc" && $2 == 4 { print $3; exit }' "$T/cap.proc.log")"
check "5 bytes captured, exit code 7, no signal" "5 7 0" "$(mark cap proc 1)"
check "no spawn#3, no open#7, no mmap#27 (the 8 MB image buffer is gone)" "0 0 0" "$(legacy cap proc)"
trace cap procsig
check "a death by SIGKILL (status 265) reads [0] = 128 + 9, [1] = 1" "5 137 1" "$(mark cap procsig 1)"
trace cap procold
check "1.57.6 kernel: WAIT_BLOCK's -1 falls back to polling #4 (-2, -2, then the status)" "5 7 0" \
    "$(mark cap procold 1)"
check "  …and a read's -2 (a pre-1.57.8 empty pipe) is retried, never taken as EOF" "3" "$(nsc cap procold 5)"
trace cap procbig
check "a child that never stops talking: the read stops at buflen, closes, and reaps (no hang)" \
    "64 7 0" "$(mark cap procbig 1)"
trace cap procarm
check "an arm the kernel refused is CLEARED (#62 REDIR_CLEAR = 512) and nothing is spawned" \
    "512 0" "$(awk '$1 == "sc" && $2 == 62 && $3 == 512 { c = $3 } END { print c + 0 }' "$T/cap.procarm.log") $(nsc cap procarm 43)"
check "  …and exec_capture_status reports -1 / [-1, 0]" "-1 -1 0" "$(mark cap procarm 1)"
trace cap procnoent
check "a spawn refused with -SPAWN_E_NOENT closes the read end and reports -1 / [-1, 0]" "-1 -1 0" \
    "$(mark cap procnoent 1)"
check "  …and closes BOTH pipe ends (write, then read)" "25 62 43 6 6" "$(seq_of cap procnoent)"

# ── axis 2 — run / spawn / wait_pid / exec_* ───────────────────────────────────────────────
echo "axis 2 — the waiting verbs block until the child exits and decode the wait status:"
probe run 'var t, v = run("/bin/child", "a b", 0);
syscall(999, 1, is_ok(t), v, 0);
sa(0, "/bin/child"); sa(1, "-v");
syscall(999, 2, exec_vec(av(2)), 0, 0);
var t2, v2 = spawn("/bin/child", 0, "z");
syscall(999, 3, is_ok(t2), v2, 0);
var t3, v3 = wait_pid(v2);
syscall(999, 4, is_ok(t3), v3, 0);
var t4, v4 = wait_pid(9);
syscall(999, 5, is_ok(t4), v4, 0);'
trace run proc
check "run: Ok(7) — the exit code, not the poll's -2" "1 7 0" "$(mark run proc 1)"
check "run: the blob is cmd + arg1 (arg2 = 0 is absent)" "/bin/child|a b|" "$(blob run proc)"
check "exec_vec: 7" "7 0 0" "$(mark run proc 2)"
check "spawn: Ok(2) and no wait of its own" "1 2 0" "$(mark run proc 3)"
check "  …spawn with arg1 = 0 keeps arg2 (the POSIX _exec3 rule)" "/bin/child|z|" \
    "$(awk '$1 == "blob" { n++; if (n == 3) { sub(/^blob /, ""); print } }' "$T/run.proc.log")"
check "wait_pid(2): Ok(7)" "1 7 0" "$(mark run proc 4)"
check "wait_pid(9) on a pid that is not ours: Err(PROC_ECHILD = 10)" "0 10 0" "$(mark run proc 5)"
# #4 calls: three WAIT_BLOCKs that succeed, plus wait_pid(9)'s WAIT_BLOCK and its fallback poll.
check "three spawns, every wait through #43 / #4 (3 + 2 for pid 9); no #3 / #7 / #27" "3 5 0 0 0" \
    "$(nsc run proc 43) $(nsc run proc 4) $(legacy run proc)"
trace run procsig
check "run on a SIGKILLed child: Ok(137)" "1 137 0" "$(mark run procsig 1)"
check "exec_vec on a SIGKILLed child: -1 (the POSIX exec_* contract)" "-1 0 0" "$(mark run procsig 2)"
trace run procnoent
check "run on a missing program: Err(SPAWN_E_NOENT = 4)" "0 4 0" "$(mark run procnoent 1)"
check "exec_vec on a missing program: -1" "-1 0 0" "$(mark run procnoent 2)"
trace run procold
check "1.57.6 kernel: run still waits for the exit (poll fallback)" "1 7 0" "$(mark run procold 1)"

# ── axis 3 — the argv / env builders refuse what the kernel cannot carry, before any syscall ──
echo "axis 3 — refusals happen up front (no #43 at all), never as a truncation:"
probe refuse 'var i = 0;
while (i < 17) { sa(i, "/bin/child"); i = i + 1; }
syscall(999, 1, exec_vec(av(17)), 0, 0);
syscall(999, 2, exec_vec(av(16)), 0, 0);
var big[140];
i = 0;
while (i < 1100) { store8(&big + i, 97); i = i + 1; }
store8(&big + 1100, 0);
sa(1, &big);
syscall(999, 3, exec_vec(av(2)), 0, 0);
sa(0, "");
syscall(999, 4, exec_vec(av(1)), 0, 0);
syscall(999, 5, exec_vec(av(0)), 0, 0);
sa(0, "/bin/child"); sa(1, "k");
se(0, "NOEQUALS");
syscall(999, 6, exec_env(av(2), ev(1)), 0, 0);
var t, v = run(&big, 0, 0);
syscall(999, 7, is_ok(t), v, 0);'
trace refuse proc
check "17 entries: -1, refused before any spawn" "-1 0 0" "$(mark refuse proc 1)"
check "16 entries still run" "7 0 0" "$(mark refuse proc 2)"
check "an 1100-byte argument (blob > 1024): -1" "-1 0 0" "$(mark refuse proc 3)"
check "an empty argv[0]: -1" "-1 0 0" "$(mark refuse proc 4)"
check "an empty argv vec: -1" "-1 0 0" "$(mark refuse proc 5)"
check "an env entry without '=': -1" "-1 0 0" "$(mark refuse proc 6)"
check "run with a path over the blob: Err(SPAWN_E_ARGS = 6)" "0 6 0" "$(mark refuse proc 7)"
check "exactly ONE #43 reached the kernel (the 16-entry one)" "1" "$(nsc refuse proc 43)"

# ── axis 4 — env blobs, Str vecs, and the command line ──────────────────────────────────────
echo "axis 4 — exec_env passes an env blob; the _str family reads Str lengths; exec_cmd splits a line:"
probe envs 'var s0[2];
var s1[2];
store64(&s0, "/bin/childXX"); store64(&s0 + 8, 10);
store64(&s1, "two words"); store64(&s1 + 8, 9);
sa(0, "/bin/child"); sa(1, "e");
se(0, "A=1"); se(1, "B=two words");
syscall(999, 1, exec_env(av(2), ev(2)), 0, 0);
sa(0, &s0); sa(1, &s1);
syscall(999, 2, exec_vec_str(av(2)), 0, 0);
syscall(999, 3, exec_cmd("  /bin/child  a   b "), 0, 0);'
trace envs proc
check "exec_env: 7" "7 0 0" "$(mark envs proc 1)"
check "exec_env: the env blob is KEY=VALUE entries, NUL-separated" "A=1|B=two words|" "$(envb envs proc)"
check "exec_vec_str: 7, and the blob uses each Str's LENGTH (\"/bin/childXX\" len 10)" \
    "7 0 0 /bin/child|two words|" \
    "$(mark envs proc 2) $(awk '$1 == "blob" { n++; if (n == 2) { sub(/^blob /, ""); print } }' "$T/envs.proc.log")"
check "exec_cmd: runs of spaces split the line (leading/trailing make nothing)" \
    "7 0 0 /bin/child|a|b|" \
    "$(mark envs proc 3) $(awk '$1 == "blob" { n++; if (n == 3) { sub(/^blob /, ""); print } }' "$T/envs.proc.log")"
check "no env line for the argv-only spawns (default env: a3 = 0)" "1" \
    "$(awk '$1 == "env" { c++ } END { print c + 0 }' "$T/envs.proc.log")"

if [ "$fails" -ne 0 ]; then echo "FAIL agnos_process_spawn: $fails check(s)"; exit 1; fi
echo "PASS agnos_process_spawn"
exit 0
