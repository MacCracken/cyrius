#!/bin/sh
# compiler_arena_refused.sh — 6.6.20. A compiler that cannot map its 246 MiB arena says so.
#
# Every Linux-hosted fork grew its arena with `syscall(SYS_BRK, S + 0xF600000)` and IGNORED the
# result (main.cyr, main_aarch64.cyr, main_aarch64_native.cyr, main_cx.cyr's Linux arm), and
# main_win.cyr / main_cx.cyr's Windows arm used the mmap / VirtualAlloc result unchecked. Under an
# rlimit (`ulimit -v`, `ulimit -d` — a CI runner, a container, a shared box) the arena was simply
# not there, and cycc died on its first heap store: SIGSEGV, exit 139, not one word. The Mach-O
# paths already refused by name.
#
# Rows: each Linux-runnable fork under `ulimit -v` exits 1 naming the arena (and never 139); x86
# under `ulimit -d` too; the native aarch64 fork under qemu-aarch64, swept across limits because
# qemu itself needs a share of the address space — every limit must end in qemu's own refusal,
# the named arena refusal or a clean compile, never a guest SIGSEGV, and at least one must reach
# the named refusal (anti-vacuous). Positive control: with no limit every fork compiles the probe.
# The PE VirtualAlloc arms (cycc.exe, cx.exe) cannot be starved under wine; they are checked by
# reading only. cycc_cx's agnos arm cannot run here either (no agnos userland on this host): it
# grew its arena with brk, and agnos syscall 12 is sync(), which returns 0, so S was 0 and no
# arena existed. Its rows build the agnos cycc_cx, require the named agnos refusal in that binary
# (and not in the Linux one), and read the arm: mmap(27), never brk / syscall 12.
#
# MUTATION LEDGER (6.6.20, scratch copies of src/, never the repo):
#   real tree                                       -> GREEN
#   main.cyr's check deleted (`if (_arena_top < …)` -> `if (0 == 1)`), cycc rebuilt
#                                                   -> RED "x86 ulimit -v 200000: rc 139" + "x86 ulimit -d"
#   the native fork's check deleted the same way    -> RED "native_qemu: 5 limit(s) ended in a signal"
#                                                      + "no limit in the sweep reached the named refusal"
#   main_cx.cyr's agnos arm put back to `var S = syscall(SYS_BRK, 0); syscall(SYS_BRK, S + 0xF600000);`
#                                                   -> RED "agnos_cx: the agnos build lacks the named refusal"
#                                                      + "agnos_cx: the arm calls brk / syscall 12"
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: compiler_arena_refused: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: compiler_arena_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: compiler_arena_refused: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: compiler_arena_refused $1"; fail=$((fail + 1)); }
ulimit -c 0   # the pre-fix shape is a SIGSEGV; never leave a core behind

mk() {   # $1 = out, $2 = source, $3 = compiler
    if ! cat "$2" | $3 > "$T/$1" 2> "$T/$1.err" || [ "$(wc -c < "$T/$1" | tr -d ' ')" -lt 1024 ]; then
        echo "FAIL: compiler_arena_refused: building $1 from $2 failed: $(grep -m1 -i error "$T/$1.err")"; exit 1
    fi
    chmod +x "$T/$1"
}
mk a64x src/main_aarch64.cyr "$CC"
mk cx   src/main_cx.cyr      "$CC"
mk xwin src/main_win.cyr     "$CC"
printf 'var x = 7;\nsyscall(60, x);\n' > "$T/p.cyr"

# one row: $1 label, $2 ulimit flag, $3 limit (KiB), $4 command
limited() {
    rows=$((rows + 1))
    rc=0
    sh -c "ulimit -c 0; ulimit $2 $3; exec $4" < "$T/p.cyr" > "$T/o" 2> "$T/e" || rc=$?
    if [ "$rc" != 1 ] || ! grep -q 'cannot map the 246 MiB compiler arena' "$T/e"; then
        bad "$1 ulimit $2 $3: rc $rc, stderr '$(head -c 160 "$T/e" | tr '\n' ' ')' (want rc 1 naming the compiler arena)"
    fi
}
for f in "x86|$CC" "a64_cross|$T/a64x" "cx|$T/cx" "win_host|$T/xwin"; do
    l=${f%%|*}; c=${f#*|}
    rows=$((rows + 1)); rc=0
    $c < "$T/p.cyr" > "$T/o" 2> "$T/e" || rc=$?
    [ "$rc" = 0 ] && [ -s "$T/o" ] || bad "$l positive control: rc $rc with no limit"
    limited "$l" -v 200000 "$c"
done
limited x86 -d 150000 "$CC"

if command -v qemu-aarch64 >/dev/null 2>&1; then
    mk a64n src/main_aarch64_native.cyr "$T/a64x"
    named=0; segv=0
    for v in 300000 350000 400000 450000 500000 600000; do
        rc=0
        sh -c "ulimit -c 0; ulimit -v $v; exec qemu-aarch64 $T/a64n" < "$T/p.cyr" > "$T/o" 2> "$T/e" || rc=$?
        grep -q 'cannot map the 246 MiB compiler arena' "$T/e" && named=$((named + 1))
        [ "$rc" -ge 128 ] && [ "$rc" != 255 ] && { segv=$((segv + 1)); echo "    native_qemu ulimit -v $v: rc $rc (a signal)"; }
    done
    rows=$((rows + 1))
    [ "$segv" = 0 ] || bad "native_qemu: $segv limit(s) ended in a signal, not a refusal"
    [ "$named" -ge 1 ] || bad "native_qemu: no limit in the sweep reached the named arena refusal (the row is vacuous)"
else
    echo "  SKIP (named): native aarch64 row — qemu-aarch64 is not installed"
fi

# cycc_cx's agnos arm (read-only rows; see the header).
AGMSG='cannot map the 246 MiB compiler arena (agnos mmap refused it)'
rows=$((rows + 1))
if ! CYRIUS_TARGET_AGNOS=1 sh -c "cat src/main_cx.cyr | $CC > $T/cx_ag 2> $T/cx_ag.err" \
   || [ "$(wc -c < "$T/cx_ag" | tr -d ' ')" -lt 1024 ]; then
    bad "agnos_cx: CYRIUS_TARGET_AGNOS=1 build of src/main_cx.cyr failed: $(grep -m1 -i error "$T/cx_ag.err")"
elif ! grep -aqF "$AGMSG" "$T/cx_ag"; then
    bad "agnos_cx: the agnos build lacks the named refusal '$AGMSG'"
fi
rows=$((rows + 1))
grep -aqF "$AGMSG" "$T/cx" && bad "agnos_cx: the LINUX cycc_cx carries the agnos refusal (the arm is not #ifdef'd)"
awk '/^#ifdef CYRIUS_TARGET_AGNOS/{b=1; t=""; next} b&&/^#endif/{if (t ~ /var S =/) printf "%s", t; b=0; next} b{t=t $0 "\n"}' \
    src/main_cx.cyr > "$T/agarm"
rows=$((rows + 1))
if [ ! -s "$T/agarm" ]; then
    bad "agnos_cx: no '#ifdef CYRIUS_TARGET_AGNOS' arm assigning the arena base S in src/main_cx.cyr"
else
    grep -v '^ *#' "$T/agarm" | grep -Eq 'SYS_BRK|syscall\(12[,)]' && bad "agnos_cx: the arm calls brk / syscall 12 (sync() on agnos: S = 0, no arena)"
    grep -v '^ *#' "$T/agarm" | grep -q 'syscall(27, 0xF600000)' || bad "agnos_cx: the arm does not map the arena with agnos mmap(27)"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL compiler_arena_refused: $fail of $rows row(s) red"; exit 1; fi
echo "PASS compiler_arena_refused: $rows rows — x86, the aarch64 cross, cx, the PE host stage and native aarch64 (qemu) refuse an unmappable arena by name; cycc_cx's agnos arm maps with mmap(27) and refuses by name"
exit 0
