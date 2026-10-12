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
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=coverage_exec_hits
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
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

if [ "$fails" -ne 0 ]; then echo "FAIL $G: $fails of $rows row(s) red"; exit 1; fi
echo "PASS $G: $rows rows — CYRIUS_COVERAGE 1 / 0 / empty / other refused; CYRIUS_COVERAGE_FILE required (255 B edge); the predefine in the entry and an include; kernel / EFI / shared / object refused; no source spelling; flag-table headroom; mode off byte-identical"
exit 0
