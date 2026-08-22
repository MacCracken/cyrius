#!/bin/sh
# Gate: the CYRIUS_IR=3 optimizer substrate must agree with the default backend.
#
# Three independent defects closed at v6.5.34, one per pass. All three were invisible to
# `cyrius test`, because the corpus runs in DEFAULT mode where every one of them is correct
# — they only appear when the same source is compiled under CYRIUS_IR=3. That is the whole
# reason this gate exists: the tests were already in the tree and already passing.
#
# ── AXIS 1 — LASE ate a load whose WIDTH conversion was load-bearing.
# `ir_lase` (src/common/ir.cyr) eliminated an IR_LOAD_LOCAL following an IR_STORE_LOCAL of
# the same slot, on the reasoning "the value is still in rax from the store". True only at
# full width. A sub-i64 store narrows into memory (`mov [rbp+d], al`) and leaves the
# UNTRUNCATED value in rax; the matching load is a `movzx`/`movsx`/`movsxd` that performs the
# truncation or sign-extension giving the value its declared type. Eliminating it made
# `var x: i8 = 256` read back 256, and an i16 holding 0xFFFF read 65535 instead of -1.
# EFLLOAD_W/EFLSTORE_W had recorded the width in the node's flags field since v6.3.35;
# ir_lase simply never read it.
# ⚠ IR_NODE_FL is a load16 and _ir_pack_op masks 0xFFFF, so the v6.3.35 SIGNED widths
# (negative) read back as 65535/65534/65532 — the guard is `fl == 0`, never a width compare.
#
# ── AXIS 2 — ir_const_fold folded against a stale operand across its own NOPs.
# The pass rewrites folded nodes to IR_NOP, and the top-of-loop skip stepped over NOPs while
# PRESERVING the state machine's `st`. On the fixpoint driver's second iteration a LOAD_IMM
# from BEFORE a fold could therefore pair with the PUSH/LOAD_IMM AFTER it, the actual left
# operand being in rax and invisible. `3 + 1 - 5 + 2` folded to 5. Needs 4+ terms AND an
# intermediate that crosses zero: shorter or all-positive chains fold in ONE iteration and
# never take the second pass, which is why 3-term chains always looked fine.
# IR_NOP is also the landing pad ir_build_bbs splits blocks on, so folding across one was
# unsound a second, independent way — a jump can arrive there and the LOAD_IMM never ran.
#
# ── AXIS 3 — ESTOC recorded no IR node, so DCE killed the address it stores through.
# `ESTOC` (src/backend/x86/emit.cyr) emits `mov [rcx], rax` — the struct field store — with
# bytes byte-identical to ESTORE64, which records IR_STORE64. ESTOC recorded NOTHING, so
# liveness never saw that the store reads rcx; DCE classified the preceding `mov rcx, rax`
# as a pure RCX def nothing reads, killed it, and the store wrote through a garbage pointer.
# SIGSEGV for any struct with two or more field stores. Its sibling ELODC (`mov rax, [rcx]`)
# had recorded IR_RAX_CLOBBER all along — this was the store half, never brought along.
# ⚠ The test that caught it is named `field_name_shadows_global`, and the shadowing is
# IRRELEVANT: it reproduces with the field renamed and the global deleted. Do not go hunting
# a name-resolution interaction.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

# Compile $1 under the env in $2, run it, echo the exit code.
run() {
    env $2 "$CC" < "$1" > "$D/r.bin" 2>/dev/null || { echo "CERR"; return; }
    chmod +x "$D/r.bin" 2>/dev/null
    timeout 40 "$D/r.bin" >/dev/null 2>&1
    echo $?
}

# ── AXIS 1: sub-i64 width conversions survive LASE.
# Mutation: revert BOTH arms of the ir_lase guard — the IR_STORE_LOCAL arm back to a bare
# `last_store_idx = a1;` AND the IR_LOAD_LOCAL arm back to `if (a1 == last_store_idx)`.
# ⚠ Reverting only the LOAD arm SURVIVES this gate, and that is not a gap in the fixture:
# the STORE arm is the load-bearing half. Refusing to TRACK a narrow store means no later
# load can match it, which alone closes every case in the corpus. The LOAD-arm conjunct
# covers the converse shape (full-width store, narrow load of the same slot) which the
# current parser does not appear to generate — it is kept because the rule "only a
# full-width pair is redundant" is the correct one to state, not because a fixture forces
# it. Anyone re-mutating this must revert both arms or conclude the fix is untested.
cat > "$D/w_i8.cyr" <<'EOF'
fn t(): i64 { var x: i8 = 256; if (x == 0) { return 0; } return 1; }
var r = t();
syscall(60, r);
EOF
cat > "$D/w_i16.cyr" <<'EOF'
fn t(): i64 { var x: i16 = 65535; if (x == 0 - 1) { return 0; } return 1; }
var r = t();
syscall(60, r);
EOF
cat > "$D/w_wrap.cyr" <<'EOF'
fn t(): i64 { var x: i8 = 255; x = x + 1; if (x == 0) { return 0; } return 1; }
var r = t();
syscall(60, r);
EOF
echo "axis 1 — sub-i64 width conversion is not eliminable (0 = correct):"
for w in w_i8 w_i16 w_wrap; do
    check "$w default"    0 "$(run "$D/$w.cyr" CYRIUS_X=0)"
    check "$w CYRIUS_IR=3" 0 "$(run "$D/$w.cyr" CYRIUS_IR=3)"
done

# ── AXIS 2: constant chains with a negative intermediate.
# Mutation: restore the single `if (op == IR_NOP || op == IR_ELIMINATED)` skip in
# ir_const_fold (i.e. let IR_NOP carry `st`) → the 4-term cases go red, 3-term stay green.
# ⚠ A 3-term chain is NOT a discriminator; it folds in one iteration. Any replacement
# fixture must keep at least one 4-term chain crossing zero.
cat > "$D/fold4.cyr" <<'EOF'
fn a(): i64 { var v = 3 + 1 - 5 + 2; if (v == 1) { return 0; } return 1; }
fn b(): i64 { var v = 100 + 1 - 200 + 5; if (v == 0 - 94) { return 0; } return 1; }
fn c(): i64 { var v = 3 * 2 - 10 + 1; if (v == 0 - 3) { return 0; } return 1; }
fn d(): i64 { var v = 0 + 1 - 5 + 2; if (v == 0 - 2) { return 0; } return 1; }
fn e(): i64 { var v = 3 + 1 - 5 + 2 + 1; if (v == 2) { return 0; } return 1; }
var r = a() + b() + c() + d() + e();
syscall(60, r);
EOF
echo "axis 2 — 4+ term constant chains crossing zero (0 = all five correct):"
check "fold4 default"     0 "$(run "$D/fold4.cyr" CYRIUS_X=0)"
check "fold4 CYRIUS_IR=3" 0 "$(run "$D/fold4.cyr" CYRIUS_IR=3)"

# ── AXIS 3: struct field stores keep their address register alive.
# Mutation: revert ESTOC to `if (IR_ENABLED(S) == 2) { return 0; }` → both go 139 (SIGSEGV).
# ⚠ A ONE-field-store struct does not reproduce; two or more stores are required.
cat > "$D/fstore.cyr" <<'EOF'
struct Rec { a; c; }
struct Big { p; q; r; s; }
fn two(): i64 { var b[64]; var x: Rec = &b; x.a = 1; x.c = 7; return x.c - 7; }
fn four(): i64 { var b[64]; var x: Big = &b; x.p = 1; x.q = 2; x.r = 3; x.s = 9; return x.s - 9; }
fn viaptr(p): i64 { var x: Rec = p; return x.c; }
fn indirect(): i64 { var b[64]; var x: Rec = &b; x.a = 1; x.c = 7; return viaptr(&b) - 7; }
var r = two() + four() + indirect();
syscall(60, r);
EOF
echo "axis 3 — struct field store keeps rcx live (0 = correct, 139 = SIGSEGV):"
check "fstore default"     0 "$(run "$D/fstore.cyr" CYRIUS_X=0)"
check "fstore CYRIUS_IR=3" 0 "$(run "$D/fstore.cyr" CYRIUS_IR=3)"

# ── AXIS 4: the four corpus files that carried these defects, end to end.
# These are ORDINARY corpus tests — they pass under `cyrius test` and always did, because
# that runs the default backend. Compiling them under IR=3 is the only thing that ever
# showed the bugs, which is the point of the axis.
echo "axis 4 — the corpus files that carried the three defects, under CYRIUS_IR=3 (0 = pass):"
for t in subword_signed_load types const_chained_multiply_fold field_name_shadows_global; do
    src=$(find tests/tcyr -name "$t.tcyr" | head -1)
    # A find matching nothing must fail loudly: cycc on EMPTY stdin exits 0 and emits a
    # runnable binary, so an unmatched glob would score a fake PASS (the v6.5.11 lesson).
    if [ -z "$src" ]; then check "$t (source found)" "yes" "no"; continue; fi
    check "$t" 0 "$(run "$src" CYRIUS_IR=3)"
done

# ── AXIS 5 (opt-in): the whole corpus, default vs IR=3, exit code AND stdout.
# ~8 minutes for 282 files x 2 compiles, so it is NOT run by default — set
# CYRIUS_IR3_FULL=1 to include it. This is stated rather than silently skipped: the bounded
# axes above cover the three known defects, and this one is the ceiling assertion that no
# FOURTH divergence has appeared. Run it at the release gate.
# ⚠ tests/tcyr/stdlib/sakshi_full.tcyr prints nanosecond timestamps and so differs from
# ITSELF between runs — it is excluded by name, not by tolerating stdout mismatches
# generally, which would blind the axis to real output divergence.
if [ "${CYRIUS_IR3_FULL:-0}" = "1" ]; then
    echo "axis 5 — FULL corpus sweep, default vs CYRIUS_IR=3:"
    total=0; div=0
    for f in $(find tests/tcyr -name '*.tcyr' | sort); do
        case "$f" in *stdlib/sakshi_full.tcyr) continue ;; esac
        total=$((total + 1))
        "$CC" < "$f" > "$D/a" 2>/dev/null || continue
        CYRIUS_IR=3 "$CC" < "$f" > "$D/b" 2>/dev/null || continue
        chmod +x "$D/a" "$D/b"
        timeout 60 "$D/a" > "$D/ao" 2>&1; ea=$?
        timeout 60 "$D/b" > "$D/bo" 2>&1; eb=$?
        if [ "$ea" != "$eb" ] || ! cmp -s "$D/ao" "$D/bo"; then
            div=$((div + 1)); echo "  DIVERGES: $f (exit $ea vs $eb)"
        fi
    done
    check "full-corpus divergences (of $total)" 0 "$div"
else
    echo "axis 5 — full-corpus sweep SKIPPED (set CYRIUS_IR3_FULL=1; ~8 min, 281 files)"
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: ir3-substrate-correctness — LASE widths, const-fold chains, field-store liveness"
    exit 0
fi
echo "FAIL: ir3-substrate-correctness — $fails assertion(s) failed"
exit 1
