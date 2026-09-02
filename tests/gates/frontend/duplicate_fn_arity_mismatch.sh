#!/bin/sh
# Gate: a duplicate fn that DISAGREES ABOUT ARITY is an error, not a warning (v6.5.37).
#
# THE DEFECT. `duplicate fn ... last definition wins` reads as benign shadowing, and usually
# is. It is not benign when the two definitions disagree about ARITY, because the duplicate
# path routes AROUND the call-site arity check that has been a hard ERROR since v6.5.1.
# Measured at 6.5.36:
#
#     a.cyr:  private fn _helper(a, b, c) { return 100 + a + b + c; }
#             public  fn a_entry()        { return _helper(1, 2, 3); }
#     b.cyr:  private fn _helper(x)       { return 200 + x; }
#
#     ./out -> exit 201   (b's 1-arg _helper won; arguments 2 and 3 dropped, silently)
#
# The identical mismatch with NO duplicate present is refused outright:
# `error: 'only_one' expects 1 argument, got 3`. So a duplicate is the one way to defeat a
# check the compiler otherwise enforces.
#
# Filed from owl 1.4.7 (2026-08-22): `vyakarana` and `sankoch` each define a
# private-by-convention `_stream_grow` and disagree about arity, buffer offsets AND return
# polarity — a wrong binding there reports every successful buffer grow as a FAILURE, inside
# a tokenizer, on file content. Neither library is doing anything wrong; they collide only
# because a consumer links both.
#
# ⚠ `private` does not exempt an arity mismatch WITHIN ONE FILE, and axis 3 pins that: two
# definitions in the same file are a genuine redefinition of one symbol, so the arity check
# still applies however they are marked.
#
# ⛔ THIS WAS THE CHEAP HALF. When written, same-arity replacement (owl's §1/§2) still
# happened across files and this comment said so. **v6.5.38 closed that half**: `private`
# now scopes at symbol INSERTION, so a private helper can no longer be replaced by another
# file's same-named, same-arity function. See `tests/gates/frontend/private_scoped_at_insertion.sh`
# — and note it must be MULTI-FILE, because every axis here concatenates into ONE file and
# therefore gets a single origin-file id, which is exactly why this gate could not have
# caught the other half. Axis 2 still asserts that a same-arity duplicate between two
# NON-private definitions only warns; that is unchanged and load-bearing.
#
# Blast radius measured before landing: cycc itself and the cyrius CLI produce ZERO
# duplicate-fn warnings; the 284-file corpus produces 5, and the only arity-differing pair
# was two tests defining a local `fn run()` over `lib/process.cyr`'s `run(cmd, arg1, arg2)`
# — renamed in the same change.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: duplicate_fn_arity_mismatch: build/cycc missing"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: duplicate_fn_arity_mismatch: $1"; exit 1; }

# Compiled from a concatenated source against build/cycc directly, NOT through the wrapper:
# in a consumer directory the wrapper resolves the INSTALLED cycc, so a gate that shelled out
# to `cyrius build` would silently test the last released compiler instead of this one. That
# mistake was made four separate times during v6.5.37.
run_cc() {  # run_cc <source-file> -> prints exit code
    set +e
    "$CC" < "$1" > "$WORK/out.bin" 2> "$WORK/out.err"
    printf '%s' "$?"
    set -e
}

# ── axis 1: differing arity is an ERROR ─────────────────────────────────────────────
cat "$ROOT/lib/syscalls.cyr" > "$WORK/mismatch.cyr"
cat >> "$WORK/mismatch.cyr" <<'EOF'
fn _dupa_helper(a, b, c) { return 100 + a + b + c; }
fn dupa_entry() { return _dupa_helper(1, 2, 3); }
fn _dupa_helper(x) { return 200 + x; }
fn main() { syscall(60, dupa_entry()); return 0; }
EOF
RC=$(run_cc "$WORK/mismatch.cyr")
[ "$RC" -ne 0 ] || fail "axis 1: an arity-differing duplicate compiled (exit 0) — the arity check is still being routed around"
grep -q "disagrees about arity" "$WORK/out.err" || fail "axis 1: refused, but not with the arity diagnostic: $(head -2 "$WORK/out.err")"
# The message must name BOTH arities, or it does not tell the reader which call sites moved.
grep -q "takes 1" "$WORK/out.err" || fail "axis 1: diagnostic does not state this definition's arity"
grep -q "takes 3" "$WORK/out.err" || fail "axis 1: diagnostic does not state the other definition's arity"

# ── axis 2: SAME arity still only warns (scope statement, not an oversight) ─────────
# Same-arity duplicates are usually intentional shadowing and are load-bearing across the
# ecosystem — `_sk_emit_err` collides between lib/vani.cyr and lib/mabda.cyr in the corpus
# today, at the same arity. Escalating those would be a different, much larger decision.
cat "$ROOT/lib/syscalls.cyr" > "$WORK/same.cyr"
cat >> "$WORK/same.cyr" <<'EOF'
fn _dupb_h(x) { return 1; }
fn dupb_e1() { return _dupb_h(5); }
fn _dupb_h(x) { return 2; }
fn dupb_e2() { return _dupb_h(6); }
fn main() { syscall(60, dupb_e1() + dupb_e2()); return 0; }
EOF
RC2=$(run_cc "$WORK/same.cyr")
[ "$RC2" -eq 0 ] || fail "axis 2: a SAME-arity duplicate was refused (exit $RC2) — the escalation is too broad: $(grep -m1 error "$WORK/out.err" || true)"
grep -q "duplicate fn" "$WORK/out.err" || fail "axis 2: a same-arity duplicate produced no warning at all"

# ── axis 3: `private` on BOTH sides does not exempt the arity mismatch ──────────────
# Pins the filing's §2: privacy is enforced on reference, not definition, so it cannot be
# relied on to prevent the collision. If this ever passes, visibility scoping has changed
# and this gate's premise needs revisiting rather than deleting.
cat "$ROOT/lib/syscalls.cyr" > "$WORK/priv.cyr"
cat >> "$WORK/priv.cyr" <<'EOF'
private
fn _dupc_h(a, b, c) { return 100 + a + b + c; }
public fn dupc_a() { return _dupc_h(1, 2, 3); }
private
fn _dupc_h(x) { return 200 + x; }
public fn dupc_b() { return _dupc_h(7); }
fn main() { syscall(60, dupc_a()); return 0; }
EOF
RC3=$(run_cc "$WORK/priv.cyr")
[ "$RC3" -ne 0 ] || fail "axis 3: 'private' on both definitions allowed an arity-differing duplicate through"

# ── axis 4: ANTI-VACUOUS — an ordinary program with no duplicates still compiles ────
cat "$ROOT/lib/syscalls.cyr" > "$WORK/clean.cyr"
cat >> "$WORK/clean.cyr" <<'EOF'
fn _dupd_h(a, b) { return a + b; }
fn main() { syscall(60, _dupd_h(3, 4)); return 0; }
EOF
RC4=$(run_cc "$WORK/clean.cyr")
[ "$RC4" -eq 0 ] || fail "axis 4: a clean program was refused (exit $RC4) — the check fires without a duplicate"

echo "PASS: duplicate_fn_arity_mismatch (arity mismatch errors and names both arities, same-arity still warns, private does not exempt, clean program builds)"
