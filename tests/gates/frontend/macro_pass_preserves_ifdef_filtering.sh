#!/bin/sh
# Gate: a function-like `#define` must not change the source every other pass produced
# (6.6.6 bite 19f).
#
# THE DEFECT (measured at 6.6.5, x86_64 Linux). Merely HAVING one function-like `#define`
# anywhere in the file — used or not — broke the build, content-dependently:
#
#     printf '#define M(a) (a)\ninclude "lib/assert.cyr"\nvar x = 1;\nsyscall(60, x);\n' | cycc
#       -> error:4261:6: expected '}', got end of file        (rc 1)
#     ...with lib/alloc.cyr instead:
#       -> error:lib/atomic.cyr:94:20: unexpected identifier 'x0'
#
# `x0` is an aarch64 register, inside `#ifdef CYRIUS_ARCH_AARCH64`. The `#ifdef` filtering had
# been UNDONE. An OBJECT-like `#define` was fine, which is why this stood: the feature worked
# in every small test with no `#ifdef` under it.
#
# THE ROOT CAUSE is a buffer contract, not the macro logic. The preprocessor has two buffers:
# input_buf at `S+_SRCB` and preprocess_out at `S+0x459D000`, and the heap map's rule is
# "passes write to preprocess_out and copy BACK here". PP_IFDEF_PASS does NOT copy back; it
# leaves `S+_SRCB` holding its own INPUT, truncated to the 1 MB helper window. PP_MACRO_PASS —
# whose ONLY entry condition is `_pp_macro_count > 0` — reads `S+_SRCB` and writes
# preprocess_out, so running it REPLACED the filtered source with the unfiltered one, and
# threw away everything past 1 MB while it was at it. Fix: PP_SYNC_SRCB (src/frontend/lex_pp.cyr).
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual. Rows A/B/E/F compare against
# the SAME source with the `#define` line deleted, compiled by the same compiler; row C is a
# BYTE-FOR-BYTE binary differential (an unused macro may not change one byte of output), and
# row D checks the macro still really expands, so C cannot pass by the pass being disabled.
#
# MUTATION LEDGER (6.6.6 — the mutant is a scratch tree whose src/ carries the mutation, built
# by build/cycc and run as CYCC=<mutant>):
#   1. PP_SYNC_SRCB made a no-op (the 6.6.5 behaviour) -> RED rows A B C D E F (row G, the
#      object-like control, stays GREEN — that is the point of it)
#   2. PP_SYNC_SRCB bounded at 1048576 (the old helper
#      window), i.e. only the >1 MB half left broken    -> RED row F only
#   3. real tree                                        -> GREEN
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: macro_pass_preserves_ifdef_filtering: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

DEF='#define GATE_M(a) (a)'

# cc <dir> <src> <out>: compile from <dir> so relative includes resolve; a failed compile or an
# EMPTY output is a failure, never a silent pass.
cc_in() {
    _d=$1; _s=$2; _o=$3
    ( cd "$_d" && "$CC" < "$_s" > "$_o" 2> "$_o.err" ) && [ -s "$_o" ]
}
# run <out>: exit code, or CCFAIL
run_ec() {
    [ -s "$1" ] || { printf 'CCFAIL'; return 0; }
    chmod +x "$1"
    set +e; "$1" > /dev/null 2>&1; r=$?; set -e
    printf '%s' "$r"
}

# ── rows A/B: the two filed repros. The stdlib include must be unaffected by a `#define`
#    that is never used, and the CONTROL is the same source with the define line removed.
_stdlib_row() {
    NROWS=$((NROWS + 1))
    _id=$1; _inc=$2
    printf '%s\ninclude "%s"\nvar gm_x = 7;\nsyscall(60, gm_x);\n' "$DEF" "$_inc" > "$WORK/t.cyr"
    printf 'include "%s"\nvar gm_x = 7;\nsyscall(60, gm_x);\n' "$_inc" > "$WORK/c.cyr"
    cc_in "$ROOT" "$WORK/t.cyr" "$WORK/t.bin" || true
    cc_in "$ROOT" "$WORK/c.cyr" "$WORK/c.bin" || true
    cg=$(run_ec "$WORK/t.bin"); cl=$(run_ec "$WORK/c.bin")
    [ "$cl" = "7" ] || bad "row $_id: CONTROL ($_inc, no define) gave $cl, want 7 (the gate's premise is off)"
    [ "$cg" = "7" ] || bad "row $_id: $_inc with an unused function-like #define gave $cg, want 7"
    if grep -q "expected '}'" "$WORK/t.bin.err" 2>/dev/null; then
        bad "row $_id: the 6.6.5 brace error is back"
    fi
    if grep -q "unexpected identifier 'x0'" "$WORK/t.bin.err" 2>/dev/null; then
        bad "row $_id: an aarch64 #ifdef arm survived into an x86 build"
    fi
}
_stdlib_row A lib/assert.cyr
_stdlib_row B lib/alloc.cyr

# ── row C: an UNUSED function-like `#define` must produce a BYTE-IDENTICAL binary. This is
#    the differential that does not depend on knowing which stdlib file carries an `#ifdef`.
NROWS=$((NROWS + 1))
if cc_in "$ROOT" "$WORK/t.cyr" "$WORK/cmp_t.bin" && cc_in "$ROOT" "$WORK/c.cyr" "$WORK/cmp_c.bin"; then
    cmp -s "$WORK/cmp_t.bin" "$WORK/cmp_c.bin" \
        || bad "row C: an unused function-like #define changed the emitted binary"
else
    bad "row C: one of the two compiles failed"
fi

# ── row D: ...and the macro still really expands beside an include, so row C cannot pass by
#    the macro pass having been turned off.
NROWS=$((NROWS + 1))
printf '%s\ninclude "lib/assert.cyr"\nvar gm_y = GATE_M(41) + 1;\nsyscall(60, gm_y);\n' "$DEF" > "$WORK/d.cyr"
cc_in "$ROOT" "$WORK/d.cyr" "$WORK/d.bin" || true
dg=$(run_ec "$WORK/d.bin")
[ "$dg" = "42" ] || bad "row D: the macro did not expand beside an include (gave $dg, want 42)"

# ── row E: a self-contained include of our own, so the row does not depend on any stdlib
#    file's internals. Its inactive `#ifdef` arm holds code that CANNOT compile on this host.
NROWS=$((NROWS + 1))
mkdir -p "$WORK/e/inc"
cat > "$WORK/e/inc/guarded.cyr" <<'CYR'
#ifdef CYRIUS_ARCH_NEVER_DEFINED
this is not cyrius at all ((( }}} ;;;
#endif
fn gm_guarded(): i64 { return 5; }
CYR
printf '%s\ninclude "inc/guarded.cyr"\nvar gm_z = gm_guarded();\nsyscall(60, gm_z);\n' "$DEF" > "$WORK/e/t.cyr"
printf 'include "inc/guarded.cyr"\nvar gm_z = gm_guarded();\nsyscall(60, gm_z);\n' > "$WORK/e/c.cyr"
cc_in "$WORK/e" t.cyr "$WORK/e.bin" || true
cc_in "$WORK/e" c.cyr "$WORK/ec.bin" || true
eg=$(run_ec "$WORK/e.bin"); ec2=$(run_ec "$WORK/ec.bin")
[ "$ec2" = "5" ] || bad "row E: CONTROL gave $ec2, want 5 (the gate's premise is off)"
[ "$eg" = "5" ] || bad "row E: an inactive #ifdef arm came back with a function-like #define in scope (gave $eg)"

# ── row F: the OTHER half of the same root cause — the stale buffer was also truncated to the
#    1 MB helper window, so a >1 MB preprocessed source lost everything past it
#    (`error: ...: unexpected character (0x00)`).
NROWS=$((NROWS + 1))
mkdir -p "$WORK/f/inc"
i=0
: > "$WORK/f/inc/big.cyr"
while [ "$i" -lt 20000 ]; do
    printf 'fn gm_bg_%s(a): i64 { var gm_q_%s = a + %s; return gm_q_%s; }\n' "$i" "$i" "$i" "$i" >> "$WORK/f/inc/big.cyr"
    i=$((i + 1))
done
BIGSZ=$(wc -c < "$WORK/f/inc/big.cyr")
[ "$BIGSZ" -gt 1048576 ] || bad "row F: the generated include is only $BIGSZ B; it must exceed the 1 MB window"
printf '%s\ninclude "inc/big.cyr"\nvar gm_b = gm_bg_19999(1);\nsyscall(60, gm_b - 19993);\n' "$DEF" > "$WORK/f/t.cyr"
printf 'include "inc/big.cyr"\nvar gm_b = gm_bg_19999(1);\nsyscall(60, gm_b - 19993);\n' > "$WORK/f/c.cyr"
cc_in "$WORK/f" t.cyr "$WORK/f.bin" || true
cc_in "$WORK/f" c.cyr "$WORK/fc.bin" || true
fg=$(run_ec "$WORK/f.bin"); fc=$(run_ec "$WORK/fc.bin")
[ "$fc" = "7" ] || bad "row F: CONTROL gave $fc, want 7 (the gate's premise is off)"
[ "$fg" = "7" ] || bad "row F: a >1 MB source with a function-like #define gave $fg, want 7"
if grep -q "unexpected character (0x00)" "$WORK/f.bin.err" 2>/dev/null; then
    bad "row F: the source was truncated at the 1 MB helper window"
fi

# ── row G: an object-like `#define` was always fine — a regression guard, and it proves the
#    rows above are about the FUNCTION-LIKE path specifically.
NROWS=$((NROWS + 1))
printf '#define GATE_OBJ 1\ninclude "lib/assert.cyr"\nvar gm_o = 7;\nsyscall(60, gm_o);\n' > "$WORK/g.cyr"
cc_in "$ROOT" "$WORK/g.cyr" "$WORK/g.bin" || true
gg=$(run_ec "$WORK/g.bin")
[ "$gg" = "7" ] || bad "row G: an object-like #define beside an include gave $gg, want 7"

# Anti-vacuity: every row this file spells out must have run. The floor is DERIVED from the
# file's own row markers (the `_stdlib_row <id>` calls plus the `# ── row <id>:` headers), not
# hand-counted — a row added and not run must fail here.
WANT=$(( $(grep -cE '^_stdlib_row [A-Z]' "$0") + $(grep -cE '^# ── row [A-Z]:' "$0") ))
[ "$NROWS" -eq "$WANT" ] || bad "only $NROWS rows ran; this file spells $WANT"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: macro_pass_preserves_ifdef_filtering: $NFAIL of $NROWS rows"
    exit 1
fi
echo "PASS: a function-like #define does not undo #ifdef filtering or truncate the source ($NROWS rows; the >1 MB include was $BIGSZ B)"
exit 0
