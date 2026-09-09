#!/bin/sh
# Gate: the BOXED tagged-union primitives exist, and every retired spelling fails LOUDLY.
#
# ⛔ WHY THIS GATE EXISTS. v6.6.0 deleted `tagged_new` and `payload` from lib/tagged.cyr,
# justified as "nothing in the ecosystem called it (verified across all 12 sibling stdlibs)".
# The survey was real and correct for those twelve. The CLAIM was ecosystem-wide, and the class
# that actually used the primitive — DOMAIN libraries — was never in scope: agnostik calls
# `tagged_new` 19 times, agnova 9. The full release gate went GREEN through all of it, because
# cycc's own source includes neither tagged.cyr nor result.cyr: the self-host fixpoint and
# seed-derive are STRUCTURALLY BLIND to this module and always will be.
#
# ⭐ AXIS 1 IS THE ONE THAT WOULD HAVE CAUGHT IT. An ecosystem survey cannot be PROVED from
# inside this repo — but a capability can be pinned, so that removing it reds a gate here
# instead of reddening a consumer's build days later. Deleting any of the five boxed_*
# functions fails axis 1.
#
# ⭐ AXIS 2 IS THE OTHER HALF, AND IT IS THE SUBTLER ONE. The damage at 6.6.0 was not only the
# deletion (loud) but two SILENT REDEFINITIONS: `tag(t)` went from `load64(t)` to `return t;`
# and `is_tag(t,e)` from `load64(t) == e` to `t == e`. Same names, same arity, opposite meaning
# on a box — measured `tag(box)` returning the POINTER while three documents certified the row
# as "unchanged". This axis asserts every retired spelling produces `undefined function` rather
# than a plausible number. THE RULE: a name whose meaning changed must be RETIRED, not redefined.
#
# Axis 4 is anti-vacuous: a "fix" that made the boxed primitives work by reverting the value
# form would pass axes 1-3. The value form must still bind as a pair in the same file.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC=${CYCC_BIN:-"$ROOT/build/cycc"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: boxed_union_primitives: $1"; exit 1; }

[ -x "$CYCC" ] || fail "no cycc at $CYCC"
[ -f "$ROOT/lib/boxed.cyr" ] || fail "lib/boxed.cyr is MISSING — the boxed capability was removed"

cd "$ROOT"

# ── axis 1: THE CAPABILITY. Build a box, read it back through a one-arg accessor. ───────
# Deliberately exercises every one of the five entry points, so deleting ANY of them reds this.
cat > "$WORK/cap.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
enum K { KA(); KB(); KC(); }
fn kind(cb): i64 { return boxed_tag(cb); }
fn val(cb): i64  { return boxed_payload(cb); }
fn main(): i64 {
    alloc_init();
    var b = boxed_new(KC, 4242);
    var t = tagged_new(KB, 7);
    if (load64(b) != KC) { return 11; }
    if (load64(b + 8) != 4242) { return 12; }
    if (kind(b) != KC) { return 13; }
    if (val(b) != 4242) { return 14; }
    if (boxed_is(b, KC) != 1) { return 15; }
    if (boxed_is(b, KA) != 0) { return 16; }
    if (boxed_tag(t) != KB) { return 17; }
    if (boxed_payload(t) != 7) { return 18; }
    return 0;
}
EOF
"$CYCC" < "$WORK/cap.cyr" > "$WORK/cap" 2>"$WORK/cap.err" \
    || fail "axis 1: the boxed capability does not COMPILE: $(grep -m3 error "$WORK/cap.err" || true)"
chmod +x "$WORK/cap"
set +e; "$WORK/cap"; RC1=$?; set -e
[ "$RC1" -eq 0 ] || fail "axis 1: boxed primitives compiled but returned $RC1 (see the return codes in cap.cyr)"

# ── axis 2: LOUDNESS. Every retired spelling must refuse, not return a number. ──────────
# `tag` and `payload` are deleted; `unwrap`/`unwrap_or` gained the tag argument. A stale
# consumer must meet a named error at its own line.
_expect_refusal() {
    _name=$1; _expr=$2; _msg=$3
    cat > "$WORK/loud.cyr" <<EOF
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
fn main(): i64 {
    alloc_init();
    var b = tagged_new(3, 7);
    var t, v = Some(5);
    return $_expr;
}
EOF
    set +e
    "$CYCC" < "$WORK/loud.cyr" > "$WORK/loud.bin" 2>"$WORK/loud.err"; _rc=$?
    set -e
    [ "$_rc" -ne 0 ] || fail "axis 2: \`$_name\` COMPILED — a retired spelling must refuse, not return a value"
    grep -q "$_msg" "$WORK/loud.err" \
        || fail "axis 2: \`$_name\` refused but not with '$_msg': $(head -3 "$WORK/loud.err")"
}
_expect_refusal "tag(b)"           "tag(b)"           "undefined function 'tag'"
_expect_refusal "payload(b)"       "payload(b)"       "undefined function 'payload'"
_expect_refusal "unwrap(t)"        "unwrap(t)"        "argument"
_expect_refusal "unwrap_or(t, 0)"  "unwrap_or(t, 0)"  "argument"

# ── axis 3: the two representations must not be the same thing ─────────────────────────
# If someone "simplifies" boxed_new to return its tag, axis 1 still passes on the layout reads
# but a box stops being distinguishable from a value-form tag. Two boxes must have two addresses.
cat > "$WORK/distinct.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
enum K2 { PA(); PB(); }
fn main(): i64 {
    alloc_init();
    var a = boxed_new(PA, 1);
    var b = boxed_new(PB, 2);
    if (a == b) { return 21; }
    if (boxed_tag(a) != PA) { return 22; }
    if (boxed_payload(a) != 1) { return 23; }
    if (boxed_tag(b) != PB) { return 24; }
    return 0;
}
EOF
"$CYCC" < "$WORK/distinct.cyr" > "$WORK/distinct" 2>/dev/null || fail "axis 3: did not compile"
chmod +x "$WORK/distinct"
set +e; "$WORK/distinct"; RC3=$?; set -e
[ "$RC3" -eq 0 ] || fail "axis 3: boxes are not distinct allocations (rc $RC3) — boxed_new is not boxing"

# ── axis 4 (ANTI-VACUOUS): the VALUE FORM must still be a pair in the same file ─────────
# Restoring the box by reverting the flip would satisfy axes 1-3 and silently undo v6.6.0.
# Two independent checks: the pair still binds, and a single-var bind of it is still REFUSED.
cat > "$WORK/coexist.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
enum K3 { QA(); }
fn main(): i64 {
    alloc_init();
    var t, v = Some(11);
    if (t != Some) { return 31; }
    if (v != 11) { return 32; }
    if (is_some(t) != 1) { return 33; }
    var bx = boxed_new(QA, 11);
    if (boxed_tag(bx) != QA) { return 34; }
    return 0;
}
EOF
"$CYCC" < "$WORK/coexist.cyr" > "$WORK/coexist" 2>/dev/null || fail "axis 4: coexistence did not compile"
chmod +x "$WORK/coexist"
set +e; "$WORK/coexist"; RC4=$?; set -e
[ "$RC4" -eq 0 ] || fail "axis 4: the value form regressed alongside the boxed form (rc $RC4)"

cat > "$WORK/lossy.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
fn main(): i64 {
    alloc_init();
    var r = Some(5);
    return r;
}
EOF
set +e
"$CYCC" < "$WORK/lossy.cyr" > "$WORK/lossy.bin" 2>"$WORK/lossy.err"; RCL=$?
set -e
[ "$RCL" -ne 0 ] || fail "axis 4: a single-var bind of a pair COMPILED — the value form's safety net is gone"

echo "PASS: boxed_union_primitives (4 axes: capability, loudness, distinct-allocations, anti-vacuous-value-form)"
