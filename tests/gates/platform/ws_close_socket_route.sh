#!/bin/sh
# ws_close_socket_route.sh — 6.6.20. lib/ws.cyr's ws_close closes its socket through lib/net.cyr's
# sock_close, never a raw syscall(3).
#
# ⛔ THE DEFECT. ws_close ended with `syscall(3, ws_fd(ws));`. That number is close(2) only where a
# translation table makes it so (Linux x86_64 natively, aarch64 / macOS through ESYSXLAT /
# EMACHO_SYSXLAT). Elsewhere it is something else:
#   - agnos: #3 is spawn(elf_addr, elf_size). The socket was never closed (no sock_close#50, no
#     FIN), its slot in the peer's 8-slot conn table was never freed — so the 9th ws_close'd
#     socket made tcp_socket() return Err — and every failure path of that stray spawn runs
#     endow_disarm on the caller, consuming any armed CH_ENDOW endowment.
#   - Windows: syscall 3 at arity 1 is CloseHandle, which does not close a SOCKET (closesocket
#     does; lib/net.cyr's header and lib/syscalls_windows.cyr say so) — Winsock's per-socket state
#     leaked.
# Neither is visible on a gate host: ecb/ach/cass/pi either close correctly or cannot tell
# CloseHandle from closesocket by a handle count, so a crossos tcyr would pass with the bug in.
#
# THE AXES.
#   axis 1  agnos, under the scripted fake kernel (tests/fixtures/agnos_sctrace.cyr, PTRACE_SYSEMU:
#           nothing executes, every syscall is logged with its registers): between the markers
#           around ws_close the peer issues sock_close#50 on conn 0 and NO #3, the handle reads
#           WS_CLOSED, and the next tcp_socket() reuses slot 0.
#   axis 2  agnos: ten tcp_socket + ws_new + ws_close cycles all get a socket (the conn table has
#           8 slots, so a close that does not free its slot fails at the 9th).
#   axis 3  PE: the ws_close body (located with the CYRIUS_SYMS dump) makes a direct call to
#           sock_close and no call through the CloseHandle import slot (the IAT address is read
#           from objdump -p). Skipped by name without an objdump that reads PE.
#
# MUTATION (6.6.20): restoring `syscall(3, ws_fd(ws));` FAILS axis 1 (a #3, no #50, slot 1 handed
# out), axis 2 (Err at cycle 8) and axis 3 (a CloseHandle call, no sock_close call).
# Exit 77 = an axis could not run (the SKIP protocol). CHANGELOG [6.6.20]
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: ws_close_socket_route: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: ws_close_socket_route: no build/cycc"; exit 1; }
fails=0
skips=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL: ws_close_socket_route: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# ── axis 1 — one ws_close on agnos: sock_close#50, never spawn#3, the slot comes back ──────────
echo "axis 1 — agnos: ws_close issues sock_close#50 (not #3) and frees its conn slot:"
# The handle is built in a GLOBAL buffer rather than by ws_new: the fake kernel answers the
# allocator's #27 with 0, so there is no heap under it.
cat > "$T/a1.cyr" <<'EOF'
include "lib/ws.cyr"
var fd_t, fd = tcp_socket();
sock_connect(fd, INADDR_LOOPBACK(), 8080);
var wsb[32];
store64(&wsb, fd);
store64(&wsb + 8, WS_CONNECTING);
var ws = &wsb;
syscall(999, 1, fd);
ws_close(ws);
syscall(999, 2, ws_state(ws));
var g_t, g = tcp_socket();
syscall(999, 3, g_t, g);
sys_exit(0);
EOF
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/a1.cyr" > "$T/a1.bin" 2>"$T/a1.err" && chmod +x "$T/a1.bin" || {
    echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/a1.err" | head -3; fails=$((fails + 1)); }
"$T/sct" "$T/a1.bin" plain > "$T/a1.log" 2>&1 || true
# m <tag> <field> → field of marker <tag> (field 4 = a2, 5 = a3)
m() { awk -v t="$1" -v f="$2" '$1 == "sc" && $2 == 999 && $3 == t { print $f; exit }' "$T/a1.log"; }
# between <nr> → the a1 of every syscall <nr> between markers 1 and 2, space-joined
between() { awk -v n="$1" '$1 == "sc" && $2 == 999 && $3 == 1 { on = 1; next } on && $1 == "sc" && $2 == 999 { exit }
    on && $1 == "sc" && $2 == n { printf "%s%s", s, $3; s = " " }' "$T/a1.log"; }
FD=$(m 1 4)
check "the probe ran to its last marker (a socket was made and connected)" "yes" \
    "$([ -n "$FD" ] && [ -n "$(m 3 4)" ] && echo yes || echo no)"
check "ws_close issues sock_close#50 on conn 0 (the FIN)" "0" "$(between 50)"
check "ws_close issues no #3 (agnos spawn)" "" "$(between 3)"
check "the handle reads WS_CLOSED (3) after ws_close" "3" "$(m 2 4)"
check "the next tcp_socket() is Ok and reuses the same slot (fd $FD)" "0 $FD" "$(m 3 4) $(m 3 5)"

# ── axis 2 — the conn table does not run dry: 10 close cycles on an 8-slot table ───────────────
echo "axis 2 — agnos: 10 tcp_socket + ws_close cycles on the 8-slot conn table:"
cat > "$T/a2.cyr" <<'EOF'
include "lib/ws.cyr"
var wsb[32];
var i = 0;
var ok = 0;
while (i < 10) {
    var t, fd = tcp_socket();
    if (t == Ok) {
        ok = ok + 1;
        store64(&wsb, fd);
        store64(&wsb + 8, WS_CONNECTING);
        ws_close(&wsb);
    }
    i = i + 1;
}
syscall(999, 4, ok);
sys_exit(0);
EOF
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/a2.cyr" > "$T/a2.bin" 2>"$T/a2.err" && chmod +x "$T/a2.bin" || {
    echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/a2.err" | head -3; fails=$((fails + 1)); }
"$T/sct" "$T/a2.bin" plain > "$T/a2.log" 2>&1 || true
check "all 10 tcp_socket() calls are Ok (a leaked slot fails the 9th)" "10" \
    "$(awk '$1 == "sc" && $2 == 999 && $3 == 4 { print $4; exit }' "$T/a2.log")"
check "and no cycle issued a #3" "0" "$(awk '$1 == "sc" && $2 == 3 { c++ } END { print c + 0 }' "$T/a2.log")"

# ── axis 3 — PE: ws_close reaches closesocket through sock_close, never CloseHandle ────────────
echo "axis 3 — PE: ws_close calls sock_close, not the CloseHandle import:"
OBJDUMP=$(command -v objdump 2>/dev/null || true)
if [ -z "$OBJDUMP" ] || ! "$OBJDUMP" --help 2>/dev/null | grep -q 'pei-x86-64'; then
    echo "  SKIP: no objdump that reads PE (pei-x86-64)"; skips=$((skips + 1))
else
    # A marker fn defined right after the include bounds ws_close's body from above, whatever
    # follows it in lib/ws.cyr.
    printf 'include "lib/ws.cyr"\nfn ws_probe_end(): i64 { return 7; }\nvar ws = ws_new(5);\nws_close(ws);\nsyscall(60, ws_probe_end());\n' > "$T/w.cyr"
    CYRIUS_TARGET_WIN=1 CYRIUS_SYMS="$T/w.syms" "$CC" < "$T/w.cyr" > "$T/w.exe" 2>"$T/w.err" || {
        echo "  FAIL: the PE probe did not build"; grep -E '^error' "$T/w.err" | head -3; fails=$((fails + 1)); }
    S=$(awk '$2 == "ws_close" { print $1; exit }' "$T/w.syms" 2>/dev/null)
    E=$(sort "$T/w.syms" 2>/dev/null | awk -v s="$S" 'f { print $1; exit } $1 == s { f = 1 }')
    SC=$(awk '$2 == "sock_close" { print $1; exit }' "$T/w.syms" 2>/dev/null | sed 's/^0*//')
    CH=$("$OBJDUMP" -p "$T/w.exe" 2>/dev/null | awk '$NF == "CloseHandle" { print $1; exit }')
    check "the symbol dump and import table name ws_close, its successor, sock_close and CloseHandle" "yes" \
        "$([ -n "$S" ] && [ -n "$E" ] && [ -n "$SC" ] && [ -n "$CH" ] && echo yes || echo no)"
    if [ -n "$S" ] && [ -n "$E" ] && [ -n "$SC" ] && [ -n "$CH" ]; then
        CHVA=$(printf '%x' $((0x140000000 + 0x$CH)))
        "$OBJDUMP" -d --start-address=0x"$S" --stop-address=0x"$E" "$T/w.exe" > "$T/w.dis" 2>/dev/null
        check "ws_close makes a direct call to sock_close (0x$SC)" "1" \
            "$(grep -c "call *0x$SC\$" "$T/w.dis")"
        check "ws_close makes no call through the CloseHandle import slot (0x$CHVA)" "0" \
            "$(grep -c "call.*# 0x$CHVA\$" "$T/w.dis")"
    fi
fi

echo ""
if [ "$fails" = "0" ]; then
    if [ "$skips" -gt 0 ]; then echo "SKIP: ws_close_socket_route — $skips axis/axes above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
    echo "PASS: ws_close_socket_route — ws_close closes its socket through sock_close on agnos and PE"
    exit 0
fi
echo "FAIL: ws_close_socket_route — $fails assertion(s) failed"
exit 1
