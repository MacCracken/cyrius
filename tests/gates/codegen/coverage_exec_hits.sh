#!/bin/sh
# tests/gates/codegen/coverage_exec_hits.sh — 6.7.10 (P5-B): the execution-coverage mode
#
# THE USER'S DECISIONS (2026-10-12): "P5-B depth: per-fn hit counters (one per fn, set after its
# prologue), dumped when the program exits (lost on a crash or kill). Every target, no new OS route.
# One release." — "Flag off ⇒ byte-identical output (P5-B)."
#
# GROUP S — THE SWITCH (P5B-1). The mode is decided once, in the shared PREPROCESS right after the
# bounds-checked mode's `_bnd_setup` (src/frontend/parse_cov.cyr `_cov_setup`): CYRIUS_COVERAGE 1
# on; 0, unset or empty off; any other value refused by name (lex_pp.cyr `_pp_env_rung`, the rung
# CYRIUS_BOUNDS uses). On, it needs CYRIUS_COVERAGE_FILE (no default: a predictable relative name
# is a symlink-plantable target in a shared directory) and predefines CYRIUS_COVERAGE. A kernel /
# EFI image and a `shared;` / `object;` build have no process exit to dump at: refused by name after
# pass 1 (`_cov_pass1`). There is no source spelling. (Every runnable fork deciding it alike is
# tests/gates/toolchain/fork_flag_parity.sh's `coverage` rows; the self-build scripts unsetting it
# is tests/gates/frontend/bounds_mode_checked.sh E4 / E4c.)
#
#   S1  unset -> off (the probe's `#ifdef CYRIUS_COVERAGE` arm not taken: exit 3)
#   S2  CYRIUS_COVERAGE=1 + CYRIUS_COVERAGE_FILE -> on, in the entry (exit 7) AND in a file it
#       includes (exit 9; its control 4); the compiler never writes the file
#   S3  CYRIUS_COVERAGE=0 -> off (with and without a FILE)
#   S4  CYRIUS_COVERAGE= (empty) -> off
#   S5  =1 with no FILE, an empty FILE, a 256 B FILE (over _read_env's 255 B, which it warns of) ->
#       refused by name, rc 1, exactly one error line, no binary; a 255 B FILE is accepted (the edge)
#   S6  =2 / true / yes -> refused by name, naming the value; no binary
#   S7  under the mode: `kernel;`, CYRIUS_KERNEL=1 (a bare-metal --target), `shared;`, `object;`,
#       CYRIUS_TARGET_EFI=1 -> refused by name, exactly one error line (fatal at once); each control
#       (the same build, mode off) compiles
#   S8  a plain `#define CYRIUS_COVERAGE` is an ordinary define and switches nothing (a `kernel;`
#       build with it compiles, where the mode + `kernel;` is refused)
#   S9  the 16-slot #define / flag table: the heaviest includer (lib/sandhi.cyr) plus 4 user
#       #defines compiles and runs under CYRIUS_BOUNDS=1 + CYRIUS_COVERAGE=1 (the mode takes one slot;
#       measured 2026-10-12: sandhi + 5 is the edge under both modes, + 7 with neither)
#   S10 mode off is byte-identical: over every 12th .tcyr (floor 30), unset == CYRIUS_COVERAGE=0 ==
#       CYRIUS_COVERAGE= (empty) — the binary, the stderr and the rc
#
# GROUPS H / A / B / M / CC / L — THE COUNTERS, THE MAP AND THE END-OF-PROGRAM DUMP (P5B-2). Every
# fn body bumps its own counter at its first byte (parse_cov.cyr `_cov_body` / `_cov_hit`); the
# counters and the fn map are two hidden globals (`_cov_greg`), the map an image blob; `_cov_tail`
# (one line before EEXIT in each of the seven forks) calls the dump appended to the unit
# (`_cov_finish`), which appends `# cyrius-coverage 1` and one `<count> <file>:<line> <name>` per fn
# entered to CYRIUS_COVERAGE_FILE. Each row compiles under the mode, runs, and holds the exit to the
# plain build's and the dump (sorted) to its expectation exactly. (The exit routes — `syscall(60,
# ..)`, `sys_exit`, `panic` — are P5B-3's; these probes return from `main` or fall off the top level.)
#   H1  `main` returns 4: `2 <source>:1 a`, `1 .. b`, `1 .. main`; `never` absent
#   H2  falling off the top level: the exit is the last var; `f` counted
#   H3  an included fn is named by its include path and its own line
#   H4  no fn entered: the header alone
#   H5  the dump path and the first map line are image bytes on all six writers (x86 ELF, PE, x86
#       Mach-O, agnos, arm64 Mach-O, cx) — and absent from the mode-off image
#   H6  the large-static advisory leaves the band and the map out (src/main.cyr instrumented: the
#       plain figure, within the two's alignment)
#   H7  the hit (x86's push / load / add 1 / pop / store) appears once per counted body under the mode
#       and NEVER with it off — the absolute anchor S10 cannot be (it compares three mode-off runs)
#   H8  a record over the dump's 992 B line budget is written straight out, whole
#   A2  H1-H3 under CYRIUS_IR=1 / IR=3 / DCE=1 / PIE=1 / STACK_ARRAYS=0
#   A4  the argument shapes (a 7-argument fn, Win64's 4, `#regalloc`, a capturing closure, a >16 B
#       struct return, a coroutine counted once across four forces): every result right (exit 50)
#       and the program's records exact — x86, IR=3, aarch64 (qemu), PE (wine)
#   B1  the highest fn indexes (generic instances minted in pass 2, after the dump's own fns) count
#   M3  tests/tcyr/compiler/large_source.tcyr compiles and dumps (falling off its top level)
#   CC1 an instrumented cycc compiles src/main.cyr byte-identical to cycc(src); its dump > 500 records
#       (src/main.cyr's last `syscall(SYS_EXIT, ..)` falls off the top level instead, for now)
#   L1-L5 aarch64 (qemu), the main_aarch64_native fork (qemu), PE through main.cyr and through the
#       main_win fork (wine), cx (cxvm; no `main` auto-call there, so its probes fall off the top level)
#
# MUTATION LEDGER (P5B-1; scratch copies of the tree, each its 2-stage mutant cycc, this gate and the
# named gates run as CYCC=<mutant>; 2026-10-12):
#   MS1  `_cov_setup`'s PP_PREDEFINE dropped                     -> RED S2a S2b S5d
#   MS2  the rung accepts `2` as on                              -> RED S6 (=2)
#   MS3  CYRIUS_COVERAGE_FILE not required                       -> RED S5a S5b S5c
#   MS4  `_cov_pass1`'s shared; / object; refusal dropped        -> RED S7c S7d
#   MS5  one script's `unset ... CYRIUS_COVERAGE` removed        -> RED bounds_mode_checked.sh E4, naming it
#        (install.sh, seed-derive-cycc.sh — E4c too —, check.sh, bootstrap.sh each measured)
#   MS6  `_pp_env_rung`'s refusal text altered (the refactor)    -> RED bounds_mode_checked.sh E2 (x3);
#        fork_flag_parity.sh "bounds <every fork> env2" and "coverage <every fork> env2" (16 of 127)
#   MF   `_cov_setup` not called from PREPROCESS                 -> RED fork_flag_parity.sh "coverage <every
#        fork> env1 / nofile / env2" (24 of 127)
# MUTATION LEDGER (P5B-2; the same procedure, 2026-10-12; "N of 79" = the rows each turned RED):
#   M2   the hit removed (`_cov_body`)                           -> RED 41 of 79: H1-H3 H7, A2 (IR=3 included),
#        A4, B1, M3, CC1b, L1-L5
#   M4   the band left at 8 B (`_cov_tail`'s sizing dropped)       -> RED 32 of 79: B1, H1 H3, A2 H1 / H3, M3, CC1b
#   M5   `_cov_tail` removed from src/main.cyr                    -> RED 36 of 79: H1-H4, H5 on the four main.cyr
#        writers, A2, A4 x86 (the other forks' rows stay green: they run their own line)
#   M8   the file dropped from `_cov_map`                         -> RED 46 of 79: H1-H3, H5 (all six), A2, ...
#   M13  the EPUSHR / EPOPR around the dump call removed          -> RED 39 of 79: H1-H4 (exit 0, not the plain
#        build's), A2, ...
#   M17  the hit emitted with the mode off (the band registered and sized, the dump not) -> RED 2 of 79: H7
#        ("4 off, want 0") and H6; S10 stays GREEN (three mode-off runs agree), which is why H7 exists;
#        scripts/differential.sh sees it too. (Dropping the bare `if (_cov_mode == 1)` cannot self-host:
#        the hits then address a band that was never registered.)
#   ML   `_warn_large_static`'s subtraction removed               -> RED 1 of 79: H6 (303968 B under the mode)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=coverage_exec_hits
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix (and wine's own HOME / XDG_CACHE_HOME) under $T; the EXIT teardown stops
# THIS prefix's wineserver and removes its server dir, which `wineserver -k` leaves behind.
WP="$T/wp"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT" || exit 1
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS
fails=0
rows=0
ok()  { rows=$((rows + 1)); echo "  ok   $1"; }
bad() { rows=$((rows + 1)); echo "  FAIL $1"; fails=$((fails + 1)); }

# The probe: exit 7 when the CYRIUS_COVERAGE predefine is visible, 3 when it is not.
PROBE='var code = 3;
#ifdef CYRIUS_COVERAGE
code = 7;
#endif
syscall(60, code);'
F="$T/cov.out"   # the dump path the mode is given (the compiler must never write it)

# cc <tag> <src file> [env...]: compile in $T (includes resolve there); sets RC, ERRS (error lines)
cc() {
    tag=$1; src=$2; shift 2
    RC=0
    (cd "$T" && env "$@" "$CC" < "$src" > "$T/$tag.bin" 2> "$T/$tag.err") || RC=$?
    ERRS=$(grep -c '^error' "$T/$tag.err" || true)
}
# xc <row> <want exit> <src file> [env...]: compiles clean and the program exits <want>
xc() {
    row=$1; want=$2; src=$3; shift 3
    cc "x$rows" "$src" "$@"
    if [ "$RC" != 0 ]; then bad "$row: did not compile (rc $RC): $(head -2 "$T/x$rows.err" | tr '\n' ' ')"; return; fi
    chmod +x "$T/x$rows.bin"; got=0; "$T/x$rows.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" = "$want" ]; then ok "$row (exit $got)"; else bad "$row: exit $got, want $want"; fi
}
# xe <row> <message> <src file> [env...]: refused — rc 1, exactly ONE error line holding <message>,
# and no binary
xe() {
    row=$1; msg=$2; src=$3; shift 3
    cc "e$rows" "$src" "$@"
    if [ "$RC" != 1 ]; then bad "$row: rc $RC (want 1, a refusal: $msg)"; return; fi
    if ! grep -qF -- "$msg" "$T/e$rows.err"; then bad "$row: rc $RC without '$msg': $(head -2 "$T/e$rows.err" | tr '\n' ' ')"; return; fi
    if [ "$ERRS" != 1 ]; then bad "$row: $ERRS error lines (want exactly 1): $(grep '^error' "$T/e$rows.err" | tr '\n' '|')"; return; fi
    if [ -s "$T/e$rows.bin" ]; then bad "$row: refused, but a binary was written"; return; fi
    ok "$row: $(grep '^error' "$T/e$rows.err" | head -1 | cut -c1-110)"
}
MF='CYRIUS_COVERAGE=1 needs CYRIUS_COVERAGE_FILE=<path> (the file the program appends its coverage to at exit)'
MK='the execution-coverage mode is not available for a kernel / EFI image (it has no process exit to dump at)'
MS='the execution-coverage mode is not available for a shared; or object; build (no process exit of its own; the counters and the dump would be defined in every object)'

# ── S: the switch ───────────────────────────────────────────────────────────────────────────────
printf '%s\n' "$PROBE" > "$T/s.cyr"
xc "S1 unset: off" 3 s.cyr
xc "S2a CYRIUS_COVERAGE=1 + CYRIUS_COVERAGE_FILE: on (the predefine)" 7 s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F"
printf 'fn inc_v(): i64 {\n#ifdef CYRIUS_COVERAGE\n    return 9;\n#endif\n    return 4;\n}\n' > "$T/inc_v.cyr"
printf 'include "inc_v.cyr"\nsyscall(60, inc_v());\n' > "$T/s2.cyr"
xc "S2b the predefine reaches an included file" 9 s2.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F"
xc "S2c the control: the same include, mode off" 4 s2.cyr
# Checked before anything RUNS a binary built under the mode (the program writes the file, never cycc).
rm -f "$F"
cc s2d s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F"
if [ "$RC" = 0 ] && [ ! -e "$F" ]; then ok "S2d the compiler does not write CYRIUS_COVERAGE_FILE"
else bad "S2d rc $RC; the dump file exists after the COMPILE: $(ls -l "$F" 2>&1)"; fi
xc "S3a CYRIUS_COVERAGE=0: off" 3 s.cyr CYRIUS_COVERAGE=0
xc "S3b CYRIUS_COVERAGE=0 with a FILE: off" 3 s.cyr CYRIUS_COVERAGE=0 CYRIUS_COVERAGE_FILE="$F"
xc "S4 CYRIUS_COVERAGE= (empty): off" 3 s.cyr CYRIUS_COVERAGE= CYRIUS_COVERAGE_FILE="$F"
xe "S5a CYRIUS_COVERAGE=1 with no CYRIUS_COVERAGE_FILE" "$MF" s.cyr CYRIUS_COVERAGE=1
xe "S5b CYRIUS_COVERAGE=1 with an empty CYRIUS_COVERAGE_FILE" "$MF" s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE=
L255="$T/$(printf 'p%.0s' $(seq $((254 - ${#T}))))"
L256="${L255}q"
xe "S5c a 256 B CYRIUS_COVERAGE_FILE (over _read_env's 255 B)" "$MF" s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$L256"
if grep -qF 'warning: ignoring CYRIUS_COVERAGE_FILE: its value is longer than 255 bytes' "$T/e$((rows - 1)).err"; then
    ok "S5c' the 256 B value is named by _read_env's warning (${#L256} B)"
else bad "S5c' no 'longer than 255 bytes' warning for the ${#L256} B value: $(head -1 "$T/e$((rows - 1)).err")"; fi
xc "S5d a 255 B CYRIUS_COVERAGE_FILE is accepted (the edge, ${#L255} B)" 7 s.cyr CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$L255"
for v in 2 true yes; do
    xe "S6 CYRIUS_COVERAGE=$v is refused by name" "CYRIUS_COVERAGE must be 0 or 1 (or unset): $v" s.cyr CYRIUS_COVERAGE=$v CYRIUS_COVERAGE_FILE="$F"
done

# S7 — where the mode has no meaning; each control compiles
printf 'kernel;\nvar x = 1;\n' > "$T/s7a.cyr"
printf 'var x = 1;\n' > "$T/s7b.cyr"
printf 'shared;\nfn f(): i64 { return 1; }\n' > "$T/s7c.cyr"
printf 'object;\nfn f(): i64 { return 1; }\n' > "$T/s7d.cyr"
s7() {   # s7 <row> <msg> <src> [env...]: refused under the mode; the control (mode off) compiles
    row=$1; msg=$2; src=$3; shift 3
    xe "$row" "$msg" "$src" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F" "$@"
    cc "c$rows" "$src" "$@"
    if [ "$RC" = 0 ] && [ -s "$T/c$rows.bin" ]; then ok "$row' the control (mode off) compiles"
    else bad "$row' the control (mode off): rc $RC: $(grep -m1 error "$T/c$rows.err")"; fi
}
s7 "S7a kernel;" "$MK" s7a.cyr
s7 "S7b CYRIUS_KERNEL=1 (a bare-metal --target)" "$MK" s7b.cyr CYRIUS_KERNEL=1
s7 "S7c shared;" "$MS" s7c.cyr
s7 "S7d object;" "$MS" s7d.cyr
s7 "S7e CYRIUS_TARGET_EFI=1" "$MK" s7b.cyr CYRIUS_TARGET_EFI=1

# S8 — no source spelling
printf '#define CYRIUS_COVERAGE\nkernel;\nvar x = 1;\n' > "$T/s8.cyr"
cc s8 s8.cyr
if [ "$RC" = 0 ]; then ok "S8 a plain #define CYRIUS_COVERAGE switches nothing (a kernel; build with it compiles)"
else bad "S8 #define CYRIUS_COVERAGE + kernel;: rc $RC: $(head -1 "$T/s8.err")"; fi

# S9 — the flag table's headroom under both modes
{ echo 'include "lib/sandhi.cyr"'; awk 'BEGIN { for (i = 0; i < 4; i++) printf "#define COVCAP_USER%d 1\n", i }'; echo 'syscall(60, 6);'; } > "$T/s9.cyr"
RC=0
env CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$F" "$CC" < "$T/s9.cyr" > "$T/s9.bin" 2> "$T/s9.err" || RC=$?
if [ "$RC" = 0 ]; then
    chmod +x "$T/s9.bin"; got=0; "$T/s9.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" = 6 ]; then ok "S9 lib/sandhi.cyr + 4 user #defines compiles under CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 (exit 6)"
    else bad "S9 lib/sandhi.cyr + 4 #defines under both modes: exit $got, want 6"; fi
else bad "S9 lib/sandhi.cyr + 4 user #defines under CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1: rc $RC: $(grep -m1 error "$T/s9.err")"; fi

# S10 — mode off is byte-identical: unset == =0 == empty (binary, stderr, rc)
find tests/tcyr -name '*.tcyr' | LC_ALL=C sort | awk 'NR % 12 == 1' > "$T/s10.list"
n10=0; d10=0
while read -r f; do
    n10=$((n10 + 1))
    r0=0; env -u CYRIUS_COVERAGE "$CC" < "$f" > "$T/o0" 2> "$T/r0" || r0=$?
    r1=0; env CYRIUS_COVERAGE=0 "$CC" < "$f" > "$T/o1" 2> "$T/r1" || r1=$?
    r2=0; env CYRIUS_COVERAGE= "$CC" < "$f" > "$T/o2" 2> "$T/r2" || r2=$?
    if [ "$r0" != "$r1" ] || [ "$r0" != "$r2" ] || ! cmp -s "$T/o0" "$T/o1" || ! cmp -s "$T/o0" "$T/o2" \
        || ! cmp -s "$T/r0" "$T/r1" || ! cmp -s "$T/r0" "$T/r2"; then
        d10=$((d10 + 1)); echo "  S10 differs: $f (rc $r0 / $r1 / $r2)"
    fi
done < "$T/s10.list"
if [ "$n10" -lt 30 ]; then bad "S10 the corpus holds $n10 .tcyr (floor 30) — the selection is blind"
elif [ "$d10" != 0 ]; then bad "S10 $d10 of $n10 .tcyr differ between unset, CYRIUS_COVERAGE=0 and CYRIUS_COVERAGE="
else ok "S10 $n10 .tcyr (every 12th, floor 30): unset == CYRIUS_COVERAGE=0 == CYRIUS_COVERAGE= (binary, stderr, rc)"; fi

# ════════════════════════════════════════════════════════════════════════════════════════════════
# GROUPS H / A / B / M / CC / L — THE COUNTERS, THE MAP AND THE END-OF-PROGRAM DUMP (P5B-2). Each
# probe is compiled under the mode and run; its exit must equal the plain build's, and its dump
# (sorted, `\r` dropped) must equal the rows' expectation exactly.
# ════════════════════════════════════════════════════════════════════════════════════════════════
D="$T/cov.out"
HAVE_QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && HAVE_QEMU=1
HAVE_WINE=0; command -v wine > /dev/null 2>&1 && HAVE_WINE=1
[ "$HAVE_QEMU" = 1 ] || echo "  SKIP (named): the aarch64 / native-fork legs — qemu-aarch64 is not installed"
[ "$HAVE_WINE" = 1 ] || echo "  SKIP (named): the PE legs — wine is not installed"
# The cross compilers, built once by the compiler under test.
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> /dev/null \
    && [ -s "$T/cc_cx" ] && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" || rm -f "$T/cc_cx" "$T/cxvm"
"$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
"$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null && [ -s "$T/cc_win" ] && chmod +x "$T/cc_win" || rm -f "$T/cc_win"
if [ "$HAVE_QEMU" = 1 ] && [ -x "$T/cc_a64" ]; then
    "$T/cc_a64" < src/main_aarch64_native.cyr > "$T/cc_a64n" 2> /dev/null && [ -s "$T/cc_a64n" ] && chmod +x "$T/cc_a64n" || rm -f "$T/cc_a64n"
fi
export WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'

# run_bin <runner> <binary> -> GOT (its exit; run in $T, where a relative dump path lands)
run_bin() {
    GOT=0
    chmod +x "$2"
    case $1 in
        qemu) (cd "$T" && timeout 120 qemu-aarch64 "$2" > "$2.out" 2>&1) || GOT=$? ;;
        pe) cp "$2" "$2.exe"; (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" timeout 300 wine "$2.exe" > "$2.out" 2>&1) || GOT=$? ;;
        cxvm) (cd "$T" && timeout 120 "$T/cxvm" < "$2" > "$2.out" 2>&1) || GOT=$? ;;
        *) (cd "$T" && timeout 120 "$2" > "$2.out" 2>&1) || GOT=$? ;;
    esac
}
# hx <row> <src> <dir> <runner> <want dump file> <compiler> [env...]: <src> compiled in <dir> under the
# mode and run; the exit must equal the plain build's (same compiler, same env, mode unset) — and
# $HXE when it is set — and the dump must equal <want> line for line once both are sorted ($HXF set:
# the header and the lines holding $HXF only). The PE runner gets a relative dump path (wine resolves
# it against the program's directory, $T).
HXE=""; HXF=""
hx() {
    row=$1; src=$2; dir=$3; runr=$4; want=$5; comp=$6; shift 6
    f="$D"; [ "$runr" = pe ] && f=cov.out
    rm -f "$D"
    rc=0; (cd "$dir" && env "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$f" $comp < "$src" > "$T/hx.bin" 2> "$T/hx.err") || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/hx.bin" ]; then bad "$row: did not compile under the mode (rc $rc): $(grep -m1 '^error' "$T/hx.err")"; return; fi
    rc=0; (cd "$dir" && env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE "$@" $comp < "$src" > "$T/hx.plain" 2> "$T/hx.perr") || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/hx.plain" ]; then bad "$row: the plain build did not compile (rc $rc): $(grep -m1 '^error' "$T/hx.perr")"; return; fi
    run_bin "$runr" "$T/hx.plain"; pgot=$GOT
    rm -f "$D"
    run_bin "$runr" "$T/hx.bin"; got=$GOT
    if [ "$got" != "$pgot" ]; then bad "$row: exit $got under the mode, $pgot plain"; return; fi
    if [ -n "$HXE" ] && [ "$got" != "$HXE" ]; then bad "$row: exit $got (want $HXE: a result is wrong)"; return; fi
    if [ ! -f "$D" ]; then bad "$row: exit $got, but no dump at the CYRIUS_COVERAGE_FILE"; return; fi
    if [ -n "$HXF" ]; then tr -d '\r' < "$D" | grep -F -e "$HDR" -e "$HXF" | LC_ALL=C sort > "$T/hx.got"
    else tr -d '\r' < "$D" | LC_ALL=C sort > "$T/hx.got"; fi
    LC_ALL=C sort "$want" > "$T/hx.want"
    if cmp -s "$T/hx.got" "$T/hx.want"; then ok "$row (exit $got; $(grep -vc '^#' "$T/hx.got") record(s), exact)"
    else bad "$row: exit $got; the dump differs — got: $(tr '\n' '|' < "$T/hx.got") want: $(tr '\n' '|' < "$T/hx.want")"; fi
}
HDR='# cyrius-coverage 1'

# The probes
printf 'fn a(x): i64 { return x + 1; }\nfn b(): i64 { return a(1) + a(0); }\nfn never(): i64 { return 9; }\nfn main(): i64 { b(); return 4; }\n' > "$T/h1.cyr"
printf '%s\n2 <source>:1 a\n1 <source>:2 b\n1 <source>:4 main\n' "$HDR" > "$T/h1.want"
printf 'fn f(x): i64 { return x * 2; }\nvar a = f(3);\nvar z = f(a) + 1;\n' > "$T/h2.cyr"
printf '%s\n2 <source>:1 f\n' "$HDR" > "$T/h2.want"
printf '# an included file\nvar IV = 3;\nfn inc_f(x): i64 { return x + IV; }\nfn inc_never(): i64 { return 0; }\n' > "$T/cov_inc.cyr"
printf 'include "cov_inc.cyr"\nfn ent(): i64 { return inc_f(4); }\nvar r = ent();\n' > "$T/h3.cyr"
printf '%s\n1 cov_inc.cyr:3 inc_f\n1 <source>:2 ent\n' "$HDR" > "$T/h3.want"
printf 'fn never(): i64 { return 1; }\nvar x = 6;\n' > "$T/h4.cyr"
printf '%s\n' "$HDR" > "$T/h4.want"

# ── H: x86 ELF ───────────────────────────────────────────────────────────────────────────────
hx "H1 main returns 4: a x2, b, main counted at their fn lines; never absent" "$T/h1.cyr" "$T" x86 "$T/h1.want" "$CC"
hx "H2 falling off the top level: the exit is the last var; f counted" "$T/h2.cyr" "$T" x86 "$T/h2.want" "$CC"
hx "H3 an included fn is named by its include path and its own line" "$T/h3.cyr" "$T" x86 "$T/h3.want" "$CC"
hx "H4 no fn entered: the header alone" "$T/h4.cyr" "$T" x86 "$T/h4.want" "$CC"

# H5 — the path and the map are image bytes on all six writers (and on none with the mode off)
H5P="$T/h5_COVERAGE_PATH.out"
h5() {   # <writer> <compiler> [env...]
    w=$1; comp=$2; shift 2
    rc=0; (cd "$T" && env "$@" CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$H5P" $comp < "$T/h1.cyr" > "$T/h5.bin" 2> /dev/null) || rc=$?
    rc0=0; (cd "$T" && env "$@" $comp < "$T/h1.cyr" > "$T/h5.off" 2> /dev/null) || rc0=$?
    np=$(grep -c -a -F "$H5P" "$T/h5.bin" || true); nm=$(grep -c -a -F '<source>:1 a' "$T/h5.bin" || true)
    op=$(grep -c -a -F -e "$H5P" -e '<source>:1 a' -e "$HDR" "$T/h5.off" || true)
    if [ "$rc" = 0 ] && [ "$rc0" = 0 ] && [ "$np" -ge 1 ] && [ "$nm" -ge 1 ] && [ "$op" = 0 ]; then
        ok "H5 $w: the dump path and the first map line are in the image (and not in the mode-off image)"
    else bad "H5 $w: rc $rc / $rc0 off; path bytes $np, map line $nm, mode-off image hits $op"; fi
}
h5 "x86 ELF" "$CC"
h5 "PE" "$CC" CYRIUS_TARGET_WIN=1
h5 "x86 Mach-O" "$CC" CYRIUS_MACHO=1
h5 "agnos" "$CC" CYRIUS_TARGET_AGNOS=1
if [ -x "$T/cc_a64" ]; then h5 "arm64 Mach-O" "$T/cc_a64" CYRIUS_MACHO_ARM=1; else bad "H5 arm64 Mach-O: src/main_aarch64.cyr did not build"; fi
if [ -x "$T/cc_cx" ]; then h5 "cx" "$T/cc_cx"; else bad "H5 cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

# H6 — the large-static advisory leaves the band and the map out: the instrumented compile of
# src/main.cyr prints the plain figure, give or take the alignment around the two (each over 8 B, so
# 16-aligned on x86, and the vars after them re-align: a few bytes either way — never the ~70 KB the
# band and the map hold for src/main.cyr)
w0=$("$CC" < src/main.cyr 2>&1 > /dev/null | grep 'large static data' | sed 's/^warning: large static data (\([0-9]*\) bytes).*/\1/' || true)
w1=$(env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$T/h6.out" "$CC" < src/main.cyr 2>&1 > "$T/h6.bin" | grep 'large static data' | sed 's/^warning: large static data (\([0-9]*\) bytes).*/\1/' || true)
dw=$(( ${w1:-0} - ${w0:-0} )); [ "$dw" -lt 0 ] && dw=$((0 - dw))
if [ -n "$w0" ] && [ -n "$w1" ] && [ "$dw" -lt 64 ]; then ok "H6 the large-static advisory does not count the band or the map: $w1 B under the mode, $w0 B plain"
else bad "H6 the large-static figure: '$w0' plain, '$w1' under the mode (want within 64 B)"; fi

# H7 — the hit is emitted under the mode only (an absolute anchor S10's three mode-off spellings
# cannot give): x86's `push rax; mov rax, [rax]; add rax, 1; pop rcx; mov [rcx], rax` appears once
# per counted body (a, b, never, main) under the mode and never with it off
HIT=' 50 48 8b 00 48 05 01 00 00 00 59 48 89 01'
hits() { od -An -v -tx1 "$1" | tr -d '\n' | tr -s ' ' | grep -o "$HIT" | wc -l | tr -d ' '; }
rc=0; (cd "$T" && env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < h1.cyr > h7.on 2> /dev/null) || rc=$?
rc0=0; (cd "$T" && env -u CYRIUS_COVERAGE "$CC" < h1.cyr > h7.off 2> /dev/null) || rc0=$?
if [ "$rc" = 0 ] && [ "$rc0" = 0 ] && [ "$(hits "$T/h7.on")" = 4 ] && [ "$(hits "$T/h7.off")" = 0 ]; then
    ok "H7 the hit: 4 in the instrumented image (one per body), 0 with the mode off"
else bad "H7 rc $rc / $rc0; hits $(hits "$T/h7.on") under the mode (want 4), $(hits "$T/h7.off") off (want 0)"; fi

# H8 — a record over the dump's 992 B line budget is written straight out, whole (a 1000-character
# fn name), between two ordinary records that go through the buffer
NL=$(printf 'n%.0s' $(seq 1000))
printf 'fn a(): i64 { return 1; }\nfn %s(): i64 { return 2; }\nfn b(): i64 { return 3; }\nvar x = a() + %s() + b();\n' "$NL" "$NL" > "$T/h8.cyr"
printf '%s\n1 <source>:1 a\n1 <source>:2 %s\n1 <source>:3 b\n' "$HDR" "$NL" > "$T/h8.want"
hx "H8 a 1013 B record (a 1000-character name) is written whole" "$T/h8.cyr" "$T" x86 "$T/h8.want" "$CC"

# ── A2: H1-H3 under every x86 codegen mode ───────────────────────────────────────────────────
for m in CYRIUS_IR=1 CYRIUS_IR=3 CYRIUS_DCE=1 CYRIUS_PIE=1 CYRIUS_STACK_ARRAYS=0; do
    hx "A2 $m: H1" "$T/h1.cyr" "$T" x86 "$T/h1.want" "$CC" "$m"
    hx "A2 $m: H2" "$T/h2.cyr" "$T" x86 "$T/h2.want" "$CC" "$m"
    hx "A2 $m: H3" "$T/h3.cyr" "$T" x86 "$T/h3.want" "$CC" "$m"
done

# ── A4: the argument shapes — every register is dead at the body start, so a value the hit would
# clobber shows in the result: a 7-argument fn (one on the stack), a 4-argument fn (Win64's four
# registers), a `#regalloc` fn, a capturing closure (its env register), a >16 B struct return (the
# return pointer), a coroutine (Win64's SELF in rcx; counted once, at state 0, across four forces).
# The program exits 50 when every result is right; the dump keeps the lib's records out (grep). ──
cat > "$T/a4.cyr" << 'EOF'
include "lib/alloc.cyr"
struct Big { a; b; c; }
fn mk(x): Big { var g = Big { x, x + 1, x + 2 }; return g; }
fn seven(a, b, c, d, e, f, g): i64 { return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7; }
#regalloc
fn hot(a, b) { var x = a + b; var y = a * b; return x + y; }
fn four(a, b, c, d): i64 { return a * 1000 + b * 100 + c * 10 + d; }
fn capt(k): i64 { var f = |x| k + x; return callptr(f, 2); }
fn main(): i64 {
    alloc_init();
    var r = 0;
    var g: Big = mk(10);
    if (g.a + g.b + g.c != 33) { r = r + 1; }
    if (seven(1, 2, 3, 4, 5, 6, 7) != 140) { r = r + 2; }
    if (hot(3, 4) != 19) { r = r + 4; }
    if (four(1, 2, 3, 4) != 1234) { r = r + 8; }
    if (four(5, 6, 7, 8) != 5678) { r = r + 16; }
    if (capt(40) != 42) { r = r + 32; }
    return r + 50;
}
EOF
printf '%s\n1 <source>:3 mk\n1 <source>:4 seven\n1 <source>:6 hot\n2 <source>:7 four\n1 <source>:8 capt\n1 <source>:9 main\n' "$HDR" > "$T/a4.want"
cat > "$T/a5.cyr" << 'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
    var x = 1;
    var s1 = await nopark();
    x = x + 10;
    var s2 = await nopark();
    x = x + 100;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C); var r2 = future_force(C); var r3 = future_force(C); var r4 = future_force(C);
    if (r4 != 111) { return 1; }
    return 50;
}
EOF
printf '%s\n2 <source>:8 nopark\n1 <source>:9 steps$impl\n1 <source>:17 main\n' "$HDR" > "$T/a5.want"
# ax <row> <src> <runner> <want> <compiler> [env...]: hx in the tree (its lib includes resolve), the
# exit exactly 50, over the program's own records (the lib's vary with the lib)
ax() {
    row=$1; src=$2; runr=$3; want=$4; comp=$5; shift 5
    HXE=50; HXF='<source>'
    hx "$row" "$src" "$ROOT" "$runr" "$want" "$comp" "$@"
    HXE=""; HXF=""
}
ax "A4 x86" "$T/a4.cyr" x86 "$T/a4.want" "$CC"
ax "A4 x86, CYRIUS_IR=3" "$T/a4.cyr" x86 "$T/a4.want" "$CC" CYRIUS_IR=3
ax "A4 coroutine, x86 (CYRIUS_ASYNC=1)" "$T/a5.cyr" x86 "$T/a5.want" "$CC" CYRIUS_ASYNC=1
if [ "$HAVE_QEMU" = 1 ]; then
    if [ -x "$T/cc_a64" ]; then ax "A4 aarch64 (qemu)" "$T/a4.cyr" qemu "$T/a4.want" "$T/cc_a64"
    else bad "A4 aarch64: src/main_aarch64.cyr did not build"; fi
fi
if [ "$HAVE_WINE" = 1 ]; then
    ax "A4 PE (wine; Win64's four argument registers)" "$T/a4.cyr" pe "$T/a4.want" "$CC" CYRIUS_TARGET_WIN=1
    ax "A4 coroutine, PE (wine; SELF in rcx)" "$T/a5.cyr" pe "$T/a5.want" "$CC" CYRIUS_TARGET_WIN=1 CYRIUS_ASYNC=1
fi

# ── B1: the band covers the highest fn index — generic instances minted at their call sites in
# pass 2 (after the dump's own fns) and a closure registered after them ─────────────────────────
printf 'fn a(): i64 { return 1; }\nfn gen<T>(x: T): i64 { return 2; }\nfn b(): i64 { return 3; }\nvar r = a();\nvar s = gen<f64>(1.5);\nvar t = gen<i32>(7);\nvar u = gen(4);\nvar cl = || 3;\nvar z = r + s + t + u + b();\n' > "$T/b1.cyr"
printf '%s\n1 <source>:1 a\n1 <source>:2 gen\n1 <source>:3 b\n1 <source>:2 gen$i\n1 <source>:2 gen$i32\n' "$HDR" > "$T/b1.want"
hx "B1 the highest indexes (instances minted in pass 2) count exactly" "$T/b1.cyr" "$T" x86 "$T/b1.want" "$CC"

# ── M3: a large program (tests/tcyr/compiler/large_source.tcyr, ~6,000 fns through its includes)
# compiles and dumps. Its last line `syscall(60, r);` is an exit the dump does not see yet (the exit
# routes are P5B-3's), so it falls off the top level here with the same exit value. ──────────────
sed '$s/^syscall(60, r);$/var r_exit = r;/' tests/tcyr/compiler/large_source.tcyr > "$T/m3.cyr"
if [ "$(tail -1 "$T/m3.cyr")" != 'var r_exit = r;' ]; then bad "M3: large_source.tcyr no longer ends in 'syscall(60, r);' — re-derive the row"
else
    rm -f "$D"
    rc=0; env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < "$T/m3.cyr" > "$T/m3.bin" 2> "$T/m3.err" || rc=$?
    if [ "$rc" != 0 ]; then bad "M3: rc $rc: $(grep -m1 '^error' "$T/m3.err")"
    else
        run_bin x86 "$T/m3.bin"
        nr=$(grep -cE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$' "$D" 2>/dev/null || true); nr=${nr:-0}
        nbad=$(grep -vcE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$|^# cyrius-coverage 1$' "$D" 2>/dev/null || true); nbad=${nbad:-0}
        if [ "$GOT" = 0 ] && grep -q ' passed, 0 failed' "$T/m3.bin.out" && [ "$nr" -ge 10 ] && [ "$nbad" = 0 ] \
            && grep -qE '^[0-9]+ lib/string\.cyr:[0-9]+ streq$' "$D"; then
            ok "M3 large_source.tcyr: exit 0, its asserts pass, $nr well-formed records (streq at its lib/string.cyr line)"
        else bad "M3 large_source.tcyr: exit $GOT, $nr records, $nbad malformed: $(grep -m1 'passed' "$T/m3.bin.out")"; fi
    fi
fi

# ── CC1: an instrumented cycc reproduces cycc from src, and its dump holds more than 500 records.
# src/main.cyr's last line `syscall(SYS_EXIT, _had_error);` falls off the top level here instead
# (the exit routes are P5B-3's); the same exit value. ─────────────────────────────────────────────
sed '$s/^syscall(SYS_EXIT, _had_error);$/var _cov_cc1_rc = _had_error;/' src/main.cyr > "$T/cc1.cyr"
if [ "$(tail -1 "$T/cc1.cyr")" != 'var _cov_cc1_rc = _had_error;' ]; then bad "CC1: src/main.cyr no longer ends in 'syscall(SYS_EXIT, _had_error);' — re-derive the row"
else
    rm -f "$D"
    rc=0; env CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D" "$CC" < "$T/cc1.cyr" > "$T/cc1.bin" 2> /dev/null || rc=$?
    "$CC" < src/main.cyr > "$T/cc1.ref" 2> /dev/null || true
    if [ "$rc" != 0 ]; then bad "CC1: the instrumented cycc did not compile (rc $rc)"
    else
        chmod +x "$T/cc1.bin"; got=0; env -u CYRIUS_COVERAGE -u CYRIUS_COVERAGE_FILE "$T/cc1.bin" < src/main.cyr > "$T/cc1.out" 2> /dev/null || got=$?
        nr=$(grep -cE '^[0-9]+ [^ ]+:[0-9]+ [^ ]+$' "$D" 2>/dev/null || true); nr=${nr:-0}
        if [ "$got" = 0 ] && [ -s "$T/cc1.ref" ] && cmp -s "$T/cc1.out" "$T/cc1.ref"; then ok "CC1a the instrumented cycc compiles src/main.cyr byte-identical to cycc(src)"
        else bad "CC1a the instrumented cycc: exit $got; its output $(wc -c < "$T/cc1.out") B against cycc(src)'s $(wc -c < "$T/cc1.ref") B"; fi
        if [ "$nr" -gt 500 ] && grep -qE '^[0-9]+ src/common/util\.cyr:[0-9]+ L64$' "$D"; then ok "CC1b its dump: $nr records (> 500), L64 at its src/common/util.cyr line"
        else bad "CC1b its dump: $nr records (want > 500, with src/common/util.cyr's L64)"; fi
    fi
fi

# ── L: the other targets — aarch64 (qemu), the native aarch64 fork (qemu), PE through main.cyr and
# through the main_win fork (wine), cx (cxvm; cx has no `main` auto-call, so its probes fall off the
# top level) ──────────────────────────────────────────────────────────────────────────────────────
if [ "$HAVE_QEMU" = 1 ]; then
    if [ -x "$T/cc_a64" ]; then
        hx "L1 aarch64 (qemu): H1" "$T/h1.cyr" "$T" qemu "$T/h1.want" "$T/cc_a64"
        hx "L1 aarch64 (qemu): H2" "$T/h2.cyr" "$T" qemu "$T/h2.want" "$T/cc_a64"
        hx "L1 aarch64 (qemu): H3" "$T/h3.cyr" "$T" qemu "$T/h3.want" "$T/cc_a64"
    else bad "L1 aarch64: src/main_aarch64.cyr did not build"; fi
    if [ -x "$T/cc_a64n" ]; then
        hx "L2 the main_aarch64_native fork (qemu): H1" "$T/h1.cyr" "$T" qemu "$T/h1.want" "qemu-aarch64 $T/cc_a64n"
        hx "L2 the main_aarch64_native fork (qemu): H3" "$T/h3.cyr" "$T" qemu "$T/h3.want" "qemu-aarch64 $T/cc_a64n"
    else bad "L2 src/main_aarch64_native.cyr did not build"; fi
fi
if [ "$HAVE_WINE" = 1 ]; then
    hx "L3 PE through main.cyr (wine): H1" "$T/h1.cyr" "$T" pe "$T/h1.want" "$CC" CYRIUS_TARGET_WIN=1
    hx "L3 PE through main.cyr (wine): H2" "$T/h2.cyr" "$T" pe "$T/h2.want" "$CC" CYRIUS_TARGET_WIN=1
    hx "L3 PE through main.cyr (wine): H3" "$T/h3.cyr" "$T" pe "$T/h3.want" "$CC" CYRIUS_TARGET_WIN=1
    if [ -x "$T/cc_win" ]; then
        hx "L4 PE through the main_win fork (wine): H1" "$T/h1.cyr" "$T" pe "$T/h1.want" "$T/cc_win"
        hx "L4 PE through the main_win fork (wine): H2" "$T/h2.cyr" "$T" pe "$T/h2.want" "$T/cc_win"
    else bad "L4 src/main_win.cyr did not build"; fi
fi
if [ -x "$T/cc_cx" ]; then
    printf 'fn code(): i64 { return 5; }\nfn deep2(): i64 { return code(); }\nfn deep1(): i64 { return deep2(); }\nvar r = deep1();\nvar q = deep1();\n' > "$T/l5.cyr"
    printf '%s\n2 <source>:1 code\n2 <source>:2 deep2\n2 <source>:3 deep1\n' "$HDR" > "$T/l5.want"
    hx "L5 cx (cxvm): three frames deep, twice; the exit is the last var" "$T/l5.cyr" "$T" cxvm "$T/l5.want" "$T/cc_cx"
    hx "L5 cx (cxvm): H3" "$T/h3.cyr" "$T" cxvm "$T/h3.want" "$T/cc_cx"
else bad "L5 cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS $G: $rows rows — CYRIUS_COVERAGE 1 / 0 / empty / other refused; CYRIUS_COVERAGE_FILE required (255 B edge); the predefine in the entry and an include; kernel / EFI / shared / object refused; no source spelling; flag-table headroom; mode off byte-identical; the per-fn counters, the map and the exit dump exact on x86 (every codegen mode), aarch64, the native fork, PE (main.cyr and main_win) and cx"
exit 0
