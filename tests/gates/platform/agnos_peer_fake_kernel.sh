#!/bin/sh
# agnos_peer_fake_kernel.sh — v6.6.7. RUNS agnos-target code against a scripted fake kernel
# and asserts on the exact registers each peer wrapper hands the kernel.
#
# ⛔ WHY RUN IT. Every defect this gate pins is in an ARGUMENT, and every one compiles clean:
#   - a4 (r10) left undefined on a short syscall — read#5/write#1 block or not by call history;
#   - a spawn length above 0xFFFF bleeding into #43's flag bits (a silent SPAWN_F_ARGV/CLEANFD);
#   - an exec_redirect src of 0x100+ becoming #62's ADD/CLEAR op;
#   - CH_ENDOW(-1), which since agnos 1.57.6 means DISARM and returns 0 — "the child gets fd 0".
# A source grep sees the call, not the value; a disassembly sees the value only when it is a
# literal. tests/fixtures/agnos_sctrace.cyr runs the agnos ELF under PTRACE_SYSEMU (nothing it
# asks for executes), logs `sc <nr> <a1> <a2> <a3> <a4>` per syscall and answers from a table,
# so the assertions read what the kernel would have been given. The probe reports its own
# results through an unused number (`syscall(999, tag, value)`), which the tracer logs too.
# CHANGELOG [6.6.7]
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_peer_fake_kernel: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_peer_fake_kernel: no build/cycc"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_peer_fake_kernel: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }
# The tracer itself must work before any assertion means anything: a 1-syscall agnos program
# must log exactly its write and its exit.
printf 'include "lib/syscalls.cyr"\nsys_write(1, "x", 1);\nsys_exit(7);\n' > "$T/h.cyr"
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/h.cyr" > "$T/h.bin" 2>/dev/null && chmod +x "$T/h.bin"
"$T/sct" "$T/h.bin" plain > "$T/h.log" 2>&1
check "the fake kernel traces a trivial agnos program (write, then exit 7)" "1 0 7" \
    "$(awk '$1 == "sc" && $2 == 1 { w++ } $1 == "sc" && $2 == 0 { e++ } $1 == "exit" { c = $2 } END { print w + 0, (e == 1 ? 0 : 9), c + 0 }' "$T/h.log")"

run() {  # $1 = probe body file, $2 = mode → $T/run.log
    printf 'include "lib/syscalls.cyr"\ninclude "lib/string.cyr"\n' > "$T/p.cyr"
    cat "$1" >> "$T/p.cyr"
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
        echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; fails=$((fails + 1)); return; }
    chmod +x "$T/p.bin"
    "$T/sct" "$T/p.bin" "$2" > "$T/run.log" 2>&1
}
# mark <tag> → the value the probe reported with syscall(999, tag, value)
mark() { awk -v t="$1" '$1 == "sc" && $2 == 999 && $3 == t { print $4; exit }' "$T/run.log"; }
# after <tag> <nr> → "a1 a2 a3 a4" of the first syscall <nr> after marker <tag>
after() { awk -v t="$1" -v n="$2" '$1 == "sc" && $2 == 999 && $3 == t { on = 1; next } on && $1 == "sc" && $2 == n { print $3, $4, $5, $6; exit }' "$T/run.log"; }
# between <tag> <nr> → how many syscalls <nr> occur between marker <tag> and the next marker
between() { awk -v t="$1" -v n="$2" '$1 == "sc" && $2 == 999 { if (on) exit; if ($3 == t) { on = 1; next } } on && $1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/run.log"; }

# ── axis 1 — a4 is DEFINED at runtime, even straight after a 7-arg call left r10 = 5 ─────────
echo "axis 1 — the kernel sees a4 = 0 on short syscalls (no r10 residue):"
cat > "$T/a1.cyr" <<'EOF'
fn f7(a, b, c, d, e, f, g): i64 { return a + g; }
var b[16];
f7(1, 2, 3, 4, 5, 6, 5);
syscall(999, 1, 0);
println("p");
f7(1, 2, 3, 4, 5, 6, 5);
syscall(999, 2, 0);
sys_read(0, &b, 1);
f7(1, 2, 3, 4, 5, 6, 5);
syscall(999, 3, 0);
sys_write(1, "w", 1);
syscall(999, 4, 0);
sys_read_nb(0, &b, 1);
sys_exit(0);
EOF
run "$T/a1.cyr" plain
check "println's raw 3-arg write#1 carries a4 = 0" "0" "$(after 1 1 | awk '{ print $4 }')"
check "sys_read's read#5 carries a4 = 0 (blocking)" "0" "$(after 2 5 | awk '{ print $4 }')"
check "sys_write's write#1 carries a4 = 0 (blocking)" "0" "$(after 3 1 | awk '{ print $4 }')"
check "sys_read_nb's read#5 carries a4 = 1 (O_NONBLOCK)" "1" "$(after 4 5 | awk '{ print $4 }')"

# ── axis 2 — the 1.57.6 spawn / redirect / endow surface packs exactly what the kernel decodes
echo "axis 2 — spawn_path#43, exec_redirect#62 and CH_ENDOW#97 arguments (agnos 1.57.6):"
cat > "$T/a2.cyr" <<'EOF'
var blob = "/bin/x\0a b\0";
syscall(999, 10, 0);
sys_spawn_argv(blob, 11, 0, 0, SPAWN_F_CLEANFD);
syscall(999, 11, 0);
sys_spawn_argv(blob, 11, 0, 0, 0);
syscall(999, 12, 0);
sys_spawn_argv(blob, 0x20005, 0, 0, 0);
syscall(999, 13, 0);
sys_spawn_argv(blob, 11, 0, 0, SPAWN_F_ARGV);
syscall(999, 14, 0);
sys_spawn_path("/bin/x", 0x10005);
syscall(999, 15, 0);
sys_spawn_path("/bin/x", 6);
syscall(999, 16, 0);
sys_spawn_path_env("/bin/x", 0x30006, "K=V\0", 4);
syscall(999, 20, sys_exec_redirect(0x105, 3));
syscall(999, 21, 0);
sys_exec_redirect(1, 3);
syscall(999, 22, 0);
sys_exec_redirect_add(2, 1);
syscall(999, 23, sys_exec_redirect_add(0x101, 1));
syscall(999, 24, 0);
sys_exec_redirect_clear();
syscall(999, 30, sys_chan_endow(0 - 1));
syscall(999, 31, 0);
sys_chan_endow(3);
syscall(999, 32, 0);
sys_chan_endow_stdio(3);
syscall(999, 33, 0);
sys_chan_endow_disarm();
syscall(999, 34, 0);
syscall(999, 40, SPAWN_E_OTHER * 1000000 + SPAWN_E_NOPROC * 100000 + SPAWN_E_NOMEM * 10000 + SPAWN_E_NOENT * 1000 + SPAWN_E_NOEXEC * 100 + SPAWN_E_ARGS * 10 + SPAWN_E_LIMIT);
sys_exit(0);
EOF
run "$T/a2.cyr" plain
check "sys_spawn_argv(CLEANFD) packs len | ARGV | CLEANFD, env (0, 0)" "196619 0 0" "$(after 10 43 | cut -d' ' -f2-)"
check "sys_spawn_argv(0) packs len | ARGV" "65547" "$(after 11 43 | awk '{ print $2 }')"
check "an oversized argv len never reaches the flag bits (refused via bit 18)" "262144" "$(after 12 43 | awk '{ print $2 }')"
check "flags = SPAWN_F_ARGV is refused (only 0 / CLEANFD are callers' flags)" "262144" "$(after 13 43 | awk '{ print $2 }')"
check "sys_spawn_path(len 0x10005) is refused, not an ARGV spawn" "262144" "$(after 14 43 | awk '{ print $2 }')"
check "sys_spawn_path passes env (0, 0)" "6 0 0" "$(after 15 43 | cut -d' ' -f2-)"
check "sys_spawn_path_env(len 0x30006) is refused" "262144" "$(after 16 43 | awk '{ print $2 }')"
check "sys_exec_redirect(src 0x105) is refused before the kernel" "-1 0" "$(mark 20) $(between 16 62)"
check "sys_exec_redirect(1, 3) is op 0" "1 3" "$(after 21 62 | cut -d' ' -f1-2)"
check "sys_exec_redirect_add(2, 1) is REDIR_ADD | 2" "258 1" "$(after 22 62 | cut -d' ' -f1-2)"
check "sys_exec_redirect_add(src 0x101) is refused" "-1" "$(mark 23)"
check "sys_exec_redirect_clear is exactly (0x200, 0)" "512 0" "$(after 24 62 | cut -d' ' -f1-2)"
check "sys_chan_endow(-1) is refused (-CH_E_BADFD), never a silent disarm" "-5 0" "$(mark 30) $(between 24 97)"
check "sys_chan_endow(3) passes a4 = 0" "5 3 0 0" "$(after 31 97)"
check "sys_chan_endow_stdio(3) passes a4 = CH_ENDOW_STDIO" "5 3 0 1000" "$(after 32 97)"
check "sys_chan_endow_disarm is CH_ENDOW(-1)" "5 -1 0 0" "$(after 33 97)"
check "SPAWN_E_OTHER..SPAWN_E_LIMIT are 1..7 (kernel syscall.cyr:137-146)" "1234567" "$(mark 40)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_peer_fake_kernel — the agnos peer hands the kernel exactly the registers it decodes"
    exit 0
fi
echo "FAIL: agnos_peer_fake_kernel — $fails assertion(s) failed"
exit 1
