#!/bin/sh
# cx_auto_call_main.sh — 6.7.11. A cx program runs the `fn main` it defines, as every image target
# does: the entry epilogue calls it after the top level and the last-var load, and its return value
# is the exit code (issues/archived/2026-10-11-cx-does-not-auto-call-main.md; the user's decision (a),
# 2026-10-13).
#
# THE DEFECT. The x86, aarch64 (cross and native), Mach-O and PE drivers end the entry with v5.9.37's
# auto-call (`_find_fn_by_name(S, "main", 4)`, then `ECALLTO` when the fn has code). src/main_cx.cyr's
# epilogue was only the last-var load and EEXIT, so on cx `main` never ran: `var g = 3; fn main():
# i64 { return 7; }` exited 7 on x86_64 and qemu-aarch64 and 3 under cxvm, `fn main(): i64 { return
# 7; }` alone exited 0, and a .tcyr that leaves `main` to the epilogue printed nothing and exited 0 —
# a pass that ran no assertion. THE FIX. main_cx.cyr ports the block (no `kernel;` / `shared;` guard:
# cx refuses both before the epilogue). A `main` called at top level AND left to the epilogue runs
# twice, as on every image target (the guide's *the three correct shapes*).
#
# ROWS — each program run NATIVELY (x86_64, the oracle) and on cxvm; both must give the row's answer.
#   A1  the filed repro verbatim (a global, then `fn main` returning 7): exit 7
#   A2  `fn main(): i64 { return 7; }` alone: exit 7
#   A3  `main` called at top level AND left to the epilogue: it runs twice (a counter global, exit
#       n * 10 = 20) and prints its marker line twice
#   A4  `main` called at top level, then an explicit `syscall(60, r)`: it runs once (exit 10)
#   A5  the epilogue's call comes after the top level: `g = g + 1;` at top level, `main` returns g * 10
#       (exit 40)
#   A6  no `fn main` — only `fn mainframe` / `fn mai`: the exit is the last global (3); the lookup is
#       the exact name
#   A7  `main`'s output reaches stdout once, and its own `syscall(60, 5)` is the exit
#   T1-T3  tests/tcyr/crossos/chan_try_send.tcyr, crossos/multi_return.tcyr and
#       math/float_nan_compare.tcyr leave `main` to the epilogue: native and cxvm each print
#       `<N> passed, 0 failed`, N derived from the source (floors 20 / 31 / 41) and exit 0. Before the
#       fix cxvm printed nothing and exited 0.
#   T4-T10 (6.7.12, D13 — the user, 2026-10-15: honest cx arms; issues/2026-10-14-cx-main-running-
#       tcyr-fail-at-guest-contract-limits.md) the seven files whose `main` stopped at the cx guest
#       contract once it ran: mmap_anon_flag (T4, was X1), uid_identity (T5, was X2),
#       mmap_include_order, sys_pipe_every_target, concurrency/async_relay_once_no_deadlock,
#       crossos/signal_errno_peer_values, concurrency/integration_closures_threads. cyr_mmap answers -1
#       on cx (mmap_anon 0), sys_pipe / sys_fstat / sys_unlink -38; each file's cx arm asserts that
#       refusal and names its SKIP. Native and cxvm each print `<N> passed, 0 failed`, N derived per
#       leg (n_tgt per target; n_span for an early-return skip block), floors today's counts; the cx
#       leg must print its SKIP line (not signal_errno, whose cx arm asserts the x86_64-Linux values
#       a .cyx carries). T5 also: no probe file is left in the cx leg's cwd.
#   W1-W3 (6.7.12) the issue's wrapper repro verbatim: native exit 0 (the probe file unlinked); cx
#       traps the store at guest 0 — mmap_anon answered 0 — never at a host address (W1). Its own
#       variant (the store replaced by `syscall(60, bad)`): native 0, cx 15 (it was 7) (W2). Each
#       refusal exactly: -38 three times, the pipe buffer untouched, cyr_mmap -1, mmap_anon 0 (W3).
#       ⚠ The repro's open(2) is translated and creates `_cx_probe.bin`; unlink refuses on cx (D13), so
#       the file stays — cxvm runs it in $T.
#   M1-M2 (6.7.14, issues/2026-10-15-cx-raw-mmap-paths-return-host-address.md) the two raw mmap paths
#       D13 missed: natively mmap_stack, fl_alloc(64), fl_alloc(8192) and _fl_mmap map writable memory
#       (M1, exit 33); on cx mmap_stack and _fl_mmap answer exactly -1 and both fl_allocs 0, with no
#       cxvm fault line (M2, exit 30). Before: cx mmap_stack > 0 (a host address) and fl_alloc(64)
#       faulted `cxvm: guest address out of range: <host address>`.
# Anti-vacuous: the native leg of every row is its control, each .tcyr count is derived from its
# source and held to a floor, and the row count is checked.
# MUTATION LEDGER (6.7.12, D13; the real tree green 40/40) — each against the tree's lib/ copy:
#   MD1 the slot-open lib/ (no cx arms) -> RED 9: T4-T7 cx (cyr_mmap / mmap_anon a host address, -14 from
#       pipe / fstat / unlink), W1 cx (the trap at a host address), W2 cx (exit 7), W3 cx (61), T8 both
#       legs (that lib/ predates this lane's EPOLL_EVENT_SIZE, a build error — not this row's signal)
#   MD2 sys_pipe's cx arm alone removed -> RED 3: T7 cx and T8 cx (-14), W3 cx (bit 1)
#   MD3 cyr_mmap's cx arm alone removed -> RED 2: T4 cx (cyr_mmap answered 0, not -1), W3 cx (bit 16)
# MUTATION LEDGER (6.7.14, the raw mmap arms; the real tree green 42/42):
#   MM1 lib/thread.cyr mmap_stack's cx arm removed -> RED 1: M2 (the host address it answered faults
#       the row's store: `cxvm: guest address out of range: 1398…`)
#   MM2 lib/freelist.cyr _fl_mmap's cx arm removed -> RED 1: M2 (fl_alloc(64) faults the same way)
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and — unless CYCC_CX is set — the cx
# compiler from THIS tree's src/main_cx.cyr, and cxvm from programs/cxvm.cyr (CXVM overrides it).
#
# MUTATION LEDGER (6.7.11, measured; the real tree green 24/24):
#   MA1 the `ECALLTO(S, _main_off);` dropped from src/main_cx.cyr (its cycc_cx passed as CYCC_CX)
#       -> RED 10: A1 / A2 / A3 / A5 / A7 cx (exit 3 / 0 / 10 / 4 / 1: the last global), T1-T3 cx
#          (nothing printed, exit 0), X1 / X2 cx (exit 0, nothing printed: "the failure moved")
#   MA2 the call emitted BEFORE the last-var load, which then overwrites main's r0 -> RED 4: A1 /
#       A3 / A5 cx (exit 3 / 10 / 4: the last global) and X2 cx (exit 0, the last global's value
#       instead of 2); A2 and T1-T3 stay green (their last global is 0 or absent)
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "${CYCC:-$ROOT/build/cycc}")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
G=cx_auto_call_main
[ -x "$CC" ] || { echo "SKIP: $G — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: $G — no timeout(1) (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0 2>/dev/null || true

if [ -n "$CYCC_CX" ]; then
    [ -x "$CYCC_CX" ] || { echo "FAIL: $G — CYCC_CX=$CYCC_CX is not executable"; exit 1; }
    CX=$CYCC_CX
else
    CX=$T/cycc_cx
    "$CC" < src/main_cx.cyr > "$CX" 2> "$T/eb"; chmod +x "$CX"
    [ -s "$CX" ] || { echo "FAIL: $G — cannot build the cx compiler from src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi
if [ -n "$CXVM" ]; then
    [ -x "$CXVM" ] || { echo "FAIL: $G — CXVM=$CXVM is not executable"; exit 1; }
    VM=$CXVM
else
    VM=$T/cxvm
    "$CC" < programs/cxvm.cyr > "$VM" 2> "$T/eb"; chmod +x "$VM"
    [ -s "$VM" ] || { echo "FAIL: $G — cannot build cxvm from programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# build_run LEG SRC OUT — compile SRC for LEG (native / cx) and run it in $T; RC = its exit (or
# "nobuild"), its stdout + stderr in OUT.
build_run() {
    RC=0
    if [ "$1" = native ]; then
        "$CC" < "$2" > "$T/n.bin" 2> "$T/n.err" || RC=nobuild
        [ -s "$T/n.bin" ] || RC=nobuild
        [ "$RC" = nobuild ] && { cp "$T/n.err" "$3"; return; }
        chmod +x "$T/n.bin"; (cd "$T" && timeout 120 ./n.bin > "$3" 2>&1) || RC=$?
    else
        "$CX" < "$2" > "$T/c.cyx" 2> "$T/c.err" || RC=nobuild
        [ -s "$T/c.cyx" ] || RC=nobuild
        [ "$RC" = nobuild ] && { cp "$T/c.err" "$3"; return; }
        (cd "$T" && timeout 120 "$VM" < c.cyx > "$3" 2>&1) || RC=$?
    fi
}

# row NAME WANT_RC MARKER WHAT SOURCE — native, then cxvm; each must exit WANT_RC and, when MARKER
# is set, print MARKER exactly MARKER_N times (default 1). A SOURCE of `@path` is that file verbatim.
MARKER_N=1
row() {
    case $5 in @*) cp "${5#@}" "$T/$1.cyr" ;; *) printf '%b' "$5" > "$T/$1.cyr" ;; esac
    for leg in native cx; do
        build_run "$leg" "$T/$1.cyr" "$T/$1.$leg.out"
        if [ "$RC" = nobuild ]; then bad "$4 ($leg): does not build: $(grep -m1 '^error' "$T/$1.$leg.out")"; continue; fi
        if [ "$RC" != "$2" ]; then bad "$4 ($leg): exit $RC, want $2 $(grep -m1 '^cxvm:' "$T/$1.$leg.out")"; continue; fi
        if [ -n "$3" ]; then
            n=$(grep -cx "$3" "$T/$1.$leg.out")
            if [ "$n" != "$MARKER_N" ]; then bad "$4 ($leg): exit $RC, but '$3' printed $n time(s), want $MARKER_N"; continue; fi
        fi
        ok "$4 ($leg): exit $RC"
    done
}

# Assertion lines outside the arms a Linux / cx build drops (`#ifdef CYRIUS_TARGET_MACOS` / `_WIN` /
# `_AGNOS` … `#endif`; none of these files nests one).
n_lin() { awk '/^[[:space:]]*#ifdef CYRIUS_TARGET_(MACOS|WIN|AGNOS)/{s=1; next} s && /^[[:space:]]*#endif/{s=0; next} !s && /^[[:space:]]*assert(_[a-z]+)?\(/{n++} END{print n+0}' "$1"; }

# tcyr ID FILE FLOOR — native and cxvm each print `<N> passed, 0 failed` (the last line) and exit 0.
tcyr() {
    w=$(n_lin "$2")
    [ "$w" -ge "$3" ] || { bad "$1 $2: only $w assertions in the source (floor $3)"; return; }
    for leg in native cx; do
        build_run "$leg" "$2" "$T/t.$leg.out"
        if [ "$RC" = nobuild ]; then bad "$1 $2 ($leg): does not build: $(grep -m1 '^error' "$T/t.$leg.out")"; continue; fi
        if [ "$RC" = 0 ] && tail -1 "$T/t.$leg.out" | grep -q "^$w passed, 0 failed"; then ok "$1 $2 ($leg): $w passed, 0 failed"
        else bad "$1 $2 ($leg): exit $RC, want '$w passed, 0 failed', got: '$(tail -1 "$T/t.$leg.out")' $(grep -m2 'FAIL' "$T/t.$leg.out" | tr '\n' ' ')"; fi
    done
}

# 6.7.12 (D13, issues/archived/2026-10-14-cx-main-running-tcyr-fail-at-guest-contract-limits.md): the files
# whose `main` stopped at the cx guest contract now take honest cx arms, so their counts differ per
# target. n_tgt FILE TARGET — the assertion lines one target compiles: `#ifdef` / `#ifndef
# CYRIUS_TARGET_<X>` nest (`#else` flips the innermost), any other macro reads as undefined.
n_tgt() {
    awk -v t="CYRIUS_TARGET_$2" '
        /^[[:space:]]*#ifdef[[:space:]]/  { d++; on[d] = ($2 == t); next }
        /^[[:space:]]*#ifndef[[:space:]]/ { d++; on[d] = ($2 != t); next }
        /^[[:space:]]*#else/  { on[d] = !on[d]; next }
        /^[[:space:]]*#endif/ { d--; next }
        /^[[:space:]]*assert(_[a-z]+)?\(/ { a = 1; for (i = 1; i <= d; i++) if (!on[i]) a = 0; if (a) n++ }
        END { print n + 0 }' "$1"
}
# n_span FILE ERE — the assertion lines of an early-return skip block: from the first line matching
# ERE through the next `return assert_summary();` (a block that runs instead of the rest of main).
n_span() {
    awk -v re="$2" 'on == 0 && $0 ~ re { on = 1 }
        on == 1 && /^[[:space:]]*assert(_[a-z]+)?\(/ { n++ }
        on == 1 && /return assert_summary\(\);/ { exit }
        END { print n + 0 }' "$1"
}
# tc ID FILE NATIVE_N CX_N FLOOR_N FLOOR_C SKIP — native and cxvm each print `<N> passed, 0 failed`
# (the last line) and exit 0, N per leg; SKIP=1: the cx leg also prints a line naming its SKIP.
tc() {
    [ "$3" -ge "$5" ] || { bad "$1 $2: only $3 native assertions derived from the source (floor $5)"; return; }
    [ "$4" -ge "$6" ] || { bad "$1 $2: only $4 cx assertions derived from the source (floor $6)"; return; }
    for leg in native cx; do
        if [ "$leg" = native ]; then w=$3; else w=$4; fi
        build_run "$leg" "$2" "$T/t.$leg.out"
        if [ "$RC" = nobuild ]; then bad "$1 $2 ($leg): does not build: $(grep -m1 '^error' "$T/t.$leg.out")"; continue; fi
        if [ "$RC" = 0 ] && tail -1 "$T/t.$leg.out" | grep -q "^$w passed, 0 failed"; then
            if [ "$leg" = cx ] && [ "$7" = 1 ] && ! grep -q 'SKIP' "$T/t.$leg.out"; then
                bad "$1 $2 (cx): $w passed, but no SKIP line names what cx does not run"; continue
            fi
            ok "$1 $2 ($leg): $w passed, 0 failed"
        else bad "$1 $2 ($leg): exit $RC, want '$w passed, 0 failed', got: '$(tail -1 "$T/t.$leg.out")' $(grep -m2 'FAIL\|^cxvm:' "$T/t.$leg.out" | tr '\n' ' ')"; fi
    done
}

R1=docs/development/issues/repros/2026-10-11-cx-does-not-auto-call-main.cyr
if [ -f "$R1" ]; then row a1 7 "" "A1: the filed repro verbatim" "@$R1"
else bad "A1: the filed repro $R1 is missing"; fi
row a2 7 "" "A2: \`fn main(): i64 { return 7; }\` alone" 'fn main(): i64 { return 7; }\n'
MARKER_N=2
row a3 20 "main-ran" "A3: main called at top level AND left to the epilogue runs twice (n * 10 = 20)" 'var n = 0;\nfn main(): i64 { n = n + 1; syscall(1, 1, "main-ran\\n", 9); return n * 10; }\nvar r = main();\n'
MARKER_N=1
row a4 10 "main-ran" "A4: main called at top level, then syscall(60, r): it runs once" 'var n = 0;\nfn main(): i64 { n = n + 1; syscall(1, 1, "main-ran\\n", 9); return n * 10; }\nvar r = main();\nsyscall(60, r);\n'
row a5 40 "" "A5: the top level runs first (g = g + 1), then main (g * 10)" 'var g = 3;\ng = g + 1;\nfn main(): i64 { return g * 10; }\n'
row a6 3 "" "A6: no fn main — mainframe / mai are not main; the exit is the last global" 'fn mainframe(): i64 { return 9; }\nfn mai(): i64 { return 8; }\nvar g = 3;\n'
row a7 5 "cx-main-out" "A7: main's output reaches stdout once, and its own syscall(60, 5) is the exit" 'var g = 1;\nfn main(): i64 { syscall(1, 1, "cx-main-out\\n", 12); syscall(60, 5); return 0; }\n'

tcyr T1 tests/tcyr/crossos/chan_try_send.tcyr 20
tcyr T2 tests/tcyr/crossos/multi_return.tcyr 31
tcyr T3 tests/tcyr/math/float_nan_compare.tcyr 41

# ── T4-T10 (6.7.12, D13): the seven files that stopped at the cx guest contract, X1 / X2 promoted ──
F=tests/tcyr/crossos/mmap_anon_flag.tcyr
tc T4 $F "$(n_tgt $F LINUX)" "$(n_tgt $F CX)" 5 3 1
F=tests/tcyr/crossos/uid_identity.tcyr
tc T5 $F "$(n_tgt $F LINUX)" "$(n_tgt $F CX)" 13 12 1
F=tests/tcyr/crossos/mmap_include_order.tcyr
tc T6 $F "$(n_tgt $F LINUX)" "$(n_tgt $F CX)" 5 2 1
F=tests/tcyr/crossos/sys_pipe_every_target.tcyr
tc T7 $F "$(n_tgt $F LINUX)" "$(n_tgt $F CX)" 6 2 1
F=tests/tcyr/concurrency/async_relay_once_no_deadlock.tcyr
tc T8 $F "$(n_tgt $F LINUX)" "$(n_span $F '^[[:space:]]*#ifdef CYRIUS_TARGET_CX')" 8 1 1
F=tests/tcyr/crossos/signal_errno_peer_values.tcyr
tc T9 $F "$(n_tgt $F LINUX)" "$(n_tgt $F CX)" 13 5 0
F=tests/tcyr/concurrency/integration_closures_threads.tcyr
_tcb=$(n_span $F 'if [(]THREADS_CONCURRENT == 0[)]')
tc T10 $F "$(( $(n_tgt $F LINUX) - _tcb ))" "$_tcb" 2 1 1
# No probe file is left by uid_identity on cx: its cx arm makes none (it used to, and the -EFAULT
# unlink left `_uid_identity_probe.bin.<pid>` in the cwd — the cx leg runs in $T).
if ls "$T"/_uid_identity_probe.bin* > /dev/null 2>&1; then bad "T5: a _uid_identity_probe.bin file was left in the cx leg's cwd"
else ok "T5: no _uid_identity_probe.bin left behind"; fi

# ── W1-W3 (6.7.12, D13): the filed wrapper repro (the issue's Reproduction, verbatim) ──
cat > "$T/w1.cyr" <<'EOF'
# cx: stdlib wrappers that compile for cx and cannot work under cxvm (x86_64 is the oracle).
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
var fds[16];
var rp = sys_pipe(&fds);                       # pipe(22): the fd-pair buffer is a guest offset
var fd = sys_open("_cx_probe.bin", 577, 384);  # open(2) is translated: the file is created
var st[160];
var rs = sys_fstat(fd, &st);                   # fstat(5): the stat buffer is a guest offset
sys_close(fd);
var ru = sys_unlink("_cx_probe.bin");          # unlink(87): the path is a guest offset
var p = mmap_anon(4096);                       # mmap(9): the host maps it and returns a HOST address
var bad = 0;
if (rp != 0) { bad = bad | 1; }
if (rs != 0) { bad = bad | 2; }
if (ru != 0) { bad = bad | 4; }
if (p == 0) { bad = bad | 8; }
syscall(1, 1, "before store\n", 13);
store64(p, 7);
syscall(60, bad);
EOF
# W1 the verbatim file: native exits 0 (every wrapper works, the store lands); on cx mmap_anon is 0,
# so the store is a null store — cxvm traps it at guest 0 (the null page), never at a host address.
rm -f "$T/_cx_probe.bin"; build_run native "$T/w1.cyr" "$T/w1.n.out"
if [ "$RC" = 0 ] && grep -qx 'before store' "$T/w1.n.out" && [ ! -e "$T/_cx_probe.bin" ]; then ok "W1 the filed repro (native): exit 0, the probe file unlinked"
else bad "W1 the filed repro (native): exit $RC, $(head -1 "$T/w1.n.out")"; fi
rm -f "$T/_cx_probe.bin"; build_run cx "$T/w1.cyr" "$T/w1.c.out"
if [ "$RC" = 1 ] && grep -qx 'before store' "$T/w1.c.out" && grep -qE '^cxvm: guest address out of range: 0 at pc [0-9]+$' "$T/w1.c.out"; then
    ok "W1 the filed repro (cx): mmap_anon answered 0 — the store traps at guest 0, not at a host address"
else bad "W1 the filed repro (cx): exit $RC, want 1 and 'guest address out of range: 0': $(grep -m1 '^cxvm:' "$T/w1.c.out")"; fi
# W2 the issue's own variant (`store64(p, 7);` replaced by `syscall(60, bad);`): cx exits bad = 15,
# all four refusals (it exited 7: pipe / fstat / unlink failed with -EFAULT, mmap_anon "succeeded").
sed 's/^store64(p, 7);$/syscall(60, bad);/' "$T/w1.cyr" > "$T/w2.cyr"
rm -f "$T/_cx_probe.bin"; build_run native "$T/w2.cyr" "$T/w2.n.out"
if [ "$RC" = 0 ]; then ok "W2 the variant (native): exit 0"; else bad "W2 the variant (native): exit $RC, want 0"; fi
rm -f "$T/_cx_probe.bin"; build_run cx "$T/w2.cyr" "$T/w2.c.out"
if [ "$RC" = 15 ]; then ok "W2 the variant (cx): exit 15 — pipe, fstat and unlink refused, mmap_anon 0"
else bad "W2 the variant (cx): exit $RC, want 15 (it was 7: mmap_anon handed back a host address)"; fi
# W3 the exact answers: each refusal is -ENOSYS (-38), never -EFAULT, and pipe leaves the buffer alone.
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/mmap.cyr"' 'var fds[16];' 'store64(&fds, 0 - 1);' \
    'var st[160];' 'var bad = 0;' \
    'if (sys_pipe(&fds) != 0 - 38) { bad = bad | 1; }' 'if (load64(&fds) != 0 - 1) { bad = bad | 2; }' \
    'if (sys_fstat(1, &st) != 0 - 38) { bad = bad | 4; }' 'if (sys_unlink("_cx_w3_never") != 0 - 38) { bad = bad | 8; }' \
    'if (cyr_mmap(0, 4096, 3, 34, 0 - 1, 0) != 0 - 1) { bad = bad | 16; }' 'if (mmap_anon(4096) != 0) { bad = bad | 32; }' \
    'syscall(60, bad);' > "$T/w3.cyr"
build_run cx "$T/w3.cyr" "$T/w3.c.out"
if [ "$RC" = 0 ]; then ok "W3 (cx): sys_pipe / sys_fstat / sys_unlink answer -38, the fd buffer untouched, cyr_mmap -1, mmap_anon 0"
else bad "W3 (cx): exit $RC (a bitmask: 1 pipe, 2 its buffer, 4 fstat, 8 unlink, 16 cyr_mmap, 32 mmap_anon)"; fi

# ── M1-M2 (6.7.14, issues/2026-10-15-cx-raw-mmap-paths-return-host-address.md): the two raw
# `syscall(SYS_MMAP)` paths D13 missed — lib/thread.cyr mmap_stack and lib/freelist.cyr _fl_mmap —
# take the same cx arm (-1). A bitmask: 1 mmap_stack mapped (and its first word writable), 2 it
# answered exactly -1, 4 fl_alloc(64) == 0, 8 fl_alloc(8192) (the large path) == 0, 16 _fl_mmap
# answered exactly -1, 32 _fl_mmap mapped, 64 a store did not read back. Exactly -1 pins the lib arms
# themselves: cxvm answers mmap(9) -38 since 6.7.14 (D55), which would also fail the callers.
cat > "$T/m1.cyr" <<'EOF'
include "lib/thread.cyr"
include "lib/freelist.cyr"
var s = mmap_stack(4096);
var a = fl_alloc(64);
var b = fl_alloc(8192);
var f = _fl_mmap(4096);
var r = 0;
if (s > 0) { r = r | 1; store64(s, 7); if (load64(s) != 7) { r = r | 64; } }
if (s == 0 - 1) { r = r | 2; }
if (a == 0) { r = r | 4; } else { store64(a, 9); if (load64(a) != 9) { r = r | 64; } }
if (b == 0) { r = r | 8; } else { store64(b + 8184, 11); if (load64(b + 8184) != 11) { r = r | 64; } }
if (f == 0 - 1) { r = r | 16; }
if (f > 0) { r = r | 32; }
syscall(60, r);
EOF
build_run native "$T/m1.cyr" "$T/m1.n.out"
if [ "$RC" = 33 ]; then ok "M1 (native): mmap_stack, fl_alloc(64), fl_alloc(8192) and _fl_mmap map writable memory (33)"
else bad "M1 (native): exit $RC, want 33 (1 stack, 32 _fl_mmap; 4 / 8 an fl_alloc refused, 64 a store lost)"; fi
build_run cx "$T/m1.cyr" "$T/m1.c.out"
if [ "$RC" = 30 ] && ! grep -q '^cxvm:' "$T/m1.c.out"; then ok "M2 (cx): mmap_stack -1, fl_alloc(64) and fl_alloc(8192) 0, _fl_mmap -1, no cxvm fault (30)"
else bad "M2 (cx): exit $RC, want 30 (1: mmap_stack handed back a host address; a fault line means fl_alloc stored through one) $(grep -m1 '^cxvm:' "$T/m1.c.out")"; fi

WANT=42
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: $G — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: $G — $pass/$WANT rows: cx calls the fn main a program defines from the entry epilogue, as natively (the filed repro, main alone, twice when also called, once before an explicit exit, after the top level, the exact name, its output); three .tcyr that leave main to it pass under cxvm, and the seven that met the cx guest contract pass there with honest refusals (cyr_mmap -1, sys_pipe / sys_fstat / sys_unlink -38) and named SKIPs; the wrapper repro traps at guest 0, never a host address; mmap_stack and _fl_mmap answer -1 on cx (fl_alloc 0), natively they map"
exit 0
