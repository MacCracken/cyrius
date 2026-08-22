#!/bin/sh
# Gate: `ir_const_fold`'s overwrite span must never swallow a following jump.
#
# THE BUG (v6.5.2). `ir_emit` stamps a node's codebuf position from GCP(S) **at call
# time** (src/common/ir.cyr:295), and every x86 emitter records BEFORE emitting bytes —
# the `_IR_REC0/1/2`-as-first-statement convention — so a node's CP is the START of its
# instruction. `ir_const_fold` depends on exactly that: it overwrites
# `IR_NODE_CP(ni+1) - IR_NODE_CP(ni_a)` bytes and 0x90-fills the remainder
# (src/common/ir.cyr:800-806).
#
# `EJCC` and `EJMP0` (src/backend/x86/jump.cyr) were the ONLY two emitters that emitted
# bytes first and recorded after, putting their CP at the END of the jump. So whenever a
# foldable constant expression was immediately followed by a jump — the canonical case
# being `return <const-expr>;` in a non-tail position, which emits the value then jmps to
# the epilogue — the span ran 5 (jmp) or 6 (jcc) bytes long and the NOP-fill ERASED THE
# JUMP. Control fell through into the next statement.
#
# Only reachable under CYRIUS_IR=3, which is why default builds were correct and this sat
# unnoticed: it presented as "the IR=3 fixpoint cascade over-eliminates", and the filed
# issue's bisection table pointed at a pass interaction. It is neither a cascade nor a
# fixpoint problem — const_fold ALONE miscompiles.
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

# ── AXIS 1: the minimal repro. `return 0 - 1;` guarded by an if, then `return 42;`.
# Folding `0 - 1` must not delete the jmp that skips the `return 42`.
# Mutation: move either ir_emit call in jump.cyr back below its EB() bytes → 142.
cat > "$D/fold.cyr" <<'EOF'
fn f(n) { if (n > 0) { return 0 - 1; } return 42; }
var x = f(1);
syscall(60, x + 100);
EOF
run() { cat "$D/fold.cyr" | env $1 "$CC" > "$D/f.bin" 2>/dev/null; chmod +x "$D/f.bin" 2>/dev/null; "$D/f.bin" >/dev/null 2>&1; echo $?; }
echo "axis 1 — fold must not erase the following jump (99 = correct, 142 = fell through):"
check "default mode"  99 "$(run CYRIUS_X=0)"
check "CYRIUS_IR=3"   99 "$(run CYRIUS_IR=3)"

# ── AXIS 2: the three programs the issue named. All exited 139/139/124 before the fix.
echo "axis 2 — the filed repros under CYRIUS_IR=3 (want 0):"
# v6.5.11: the corpus is in topical subfolders, so resolve by NAME rather than pinning a
# directory — a `find` that matches nothing must fail loudly, not compile empty stdin
# (cycc exits 0 on empty input and emits a runnable binary, which would score 0 = PASS).
for t in alloc_str_extras alloc_collections bigint; do
    src=$(find tests/tcyr -name "$t.tcyr" | head -1)
    if [ -z "$src" ]; then check "$t (source found)" "yes" "no"; continue; fi
    cat "$src" | CYRIUS_IR=3 "$CC" > "$D/$t" 2>/dev/null
    chmod +x "$D/$t" 2>/dev/null
    timeout 40 "$D/$t" >/dev/null 2>&1
    check "$t" 0 "$?"
done

# ── AXIS 3: the capstone — a CYRIUS_IR=3-built cycc must REPRODUCE the default-built cycc
# byte-identically. Read that precisely: the assertion is about the IR=3-built compiler's
# OUTPUT, not its own bytes. The IR=3-built binary is itself ~4.7 % LARGER (1,182,520 B vs
# 1,129,272 B at v6.5.2) — IR=3 is semantics-preserving here, not size-neutral, and an
# earlier version of this comment wrongly claimed the latter. What the axis proves is the
# strongest available semantics statement on the largest program in the tree. Before the fix
# the IR=3-built compiler rejected its own source with bogus "fn return type must be struct
# or i8/..." errors and emitted 0 bytes.
echo "axis 3 — an IR=3-built cycc reproduces build/cycc byte-identically (its OWN bytes differ, ~+4.7%):"
cat src/main.cyr | CYRIUS_IR=3 "$CC" > "$D/ir3cc" 2>/dev/null
if [ ! -s "$D/ir3cc" ]; then
    echo "  FAIL: CYRIUS_IR=3 produced no compiler"; fails=$((fails + 1))
else
    chmod +x "$D/ir3cc"
    cat src/main.cyr | "$D/ir3cc" > "$D/gen2" 2>/dev/null
    if cmp -s "$D/gen2" "$CC"; then
        echo "  ok: IR=3-built cycc reproduces build/cycc byte-identically"
    else
        echo "  FAIL: IR=3-built cycc does NOT reproduce build/cycc ($(stat -c%s "$D/gen2" 2>/dev/null) B)"
        fails=$((fails + 1))
    fi
fi

# ── RESIDUAL: NONE. This block used to name eight surviving default-vs-IR=3 mismatches.
# All eight are closed: switch_dispatch at v6.5.5; float / math_inverse_trig /
# math_pack_integration fell out of the band-B block-cap raise and were confirmed passing at
# v6.5.27; and the last four — subword_signed_load, types, const_chained_multiply_fold,
# field_name_shadows_global — at v6.5.34, where they bisected to three root causes, one per
# pass. Re-derived on the full 282-file corpus at v6.5.34: ZERO divergences in exit code AND
# stdout. The ceiling assertion now lives in tests/gates/ir-opt/ir3_substrate_correctness.sh
# (axis 5, CYRIUS_IR3_FULL=1). Do not re-add a residual list here without re-deriving it.

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: ir3-fold-jump-span — const-fold preserves following jumps; IR=3 output is byte-correct"
    exit 0
fi
echo "FAIL: ir3-fold-jump-span — $fails assertion(s) failed"
exit 1
