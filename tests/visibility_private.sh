#!/bin/sh
# tests/visibility_private.sh — v6.5.0 Phase 2 (public/private visibility, WARN mode)
#
# A top-level `private` flips its FILE to private-by-default; a per-item `public`
# re-exposes. Default (no declaration anywhere) is unchanged — everything public — so
# the feature is opt-in per file and inert until a file asks for it.
#
# WHAT THIS GATE IS REALLY FOR: enforcement has to cover EVERY path that resolves a
# name to an fn index and emits a call, not just the obvious one. The plan named two;
# there are at least thirteen. v6.4.81 shipped a bug of exactly that shape — the `_cfo`
# const-fold class was declared fixed three times, each fix scoped to the tier its
# repro landed in, and the fourth occurrence was in a resolution path nobody had
# enumerated. So this asserts per-PATH, and a new path is expected to add a case here.
#
# Paths covered: ordinary call · TAIL call (`return f();`, which bypasses PARSE_FNCALL
# entirely) · operator overloading (EMIT_OP_DISPATCH — the v6.4.81 path).

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: visibility-private — %s not built\n" "$CC"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib"
fail=0

cat > "$T/lib/secret.cyr" <<'EOF'
private
fn vis_hidden(): i64 { return 7; }
fn vis_same_file_caller(): i64 { return vis_hidden(); }
public fn vis_exposed(): i64 { return vis_hidden(); }
EOF

cat > "$T/m.cyr" <<'EOF'
include "lib/secret.cyr"
fn vis_ordinary(): i64 { var q = vis_hidden(); return q; }
fn vis_tail(): i64 { return vis_hidden(); }
fn vis_legit(): i64 { return vis_exposed(); }
fn main(): i64 { return vis_ordinary() + vis_tail() + vis_legit(); }
EOF

( cd "$T" && cat m.cyr | "$CC" >/dev/null 2>err.txt ) || true
W=$(grep -c "is private to its file" "$T/err.txt" 2>/dev/null || echo 0)

# Two cross-file calls to a private fn: the ordinary one and the TAIL one. If the tail
# path were missed the count would be 1 — and it silently was, in the first cut.
[ "$W" = "2" ] || { echo "  FAIL: visibility-private — expected 2 cross-file warnings (ordinary + TAIL), got $W"; cat "$T/err.txt" | head -4; fail=1; }

# `public` must genuinely re-expose: no warning for the call to vis_exposed.
grep -q "'vis_exposed' is private" "$T/err.txt" 2>/dev/null && { echo "  FAIL: visibility-private — 'public' did not re-expose vis_exposed"; fail=1; }

# Same-file call to a private fn must be silent — that is the whole point of file scope.
grep -q "vis_same_file_caller" "$T/err.txt" 2>/dev/null && { echo "  FAIL: visibility-private — same-file private call warned"; fail=1; }

# ── operator overloading is its own resolution path (the v6.4.81 lesson) ──────────
mkdir -p "$T/op/lib" && cd "$T/op"
cat > lib/ops.cyr <<'EOF'
private
struct OpVis { v; }
fn OpVis_add(a, b) { return 3000 + b; }
EOF
cat > m.cyr <<'EOF'
include "lib/ops.cyr"
var opv: OpVis = 5;
var opr = opv + 3;
fn main(): i64 { return opr; }
EOF
cat m.cyr | "$CC" >/dev/null 2>err2.txt || true
grep -q "'OpVis_add' is private to its file" err2.txt 2>/dev/null \
    || { echo "  FAIL: visibility-private — operator-overload path (EMIT_OP_DISPATCH) not enforced"; head -3 err2.txt; fail=1; }
cd "$ROOT"

# ── the default must stay completely inert ───────────────────────────────────────
cat > "$T/plain.cyr" <<'EOF'
fn plain_helper(): i64 { return 1; }
fn main(): i64 { return plain_helper(); }
EOF
( cd "$T" && cat plain.cyr | "$CC" >/dev/null 2>err3.txt ) || true
grep -q "is private to its file" "$T/err3.txt" 2>/dev/null && { echo "  FAIL: visibility-private — warned on a file with no 'private' declaration"; fail=1; }

# ── Phase 3: it is a HARD ERROR, and no binary may be emitted ────────────────────
( cd "$T" && cat m.cyr | "$CC" > out.bin 2>/dev/null ) || true
[ -s "$T/out.bin" ] && { echo "  FAIL: visibility-private — a violating program still produced a binary"; fail=1; }
grep -q "^error:" "$T/err.txt" 2>/dev/null || { echo "  FAIL: visibility-private — violation reported as a warning, not an error"; fail=1; }

# Multi-error: every violation in ONE run (the v6.4.62 contract). A fail-fast exit
# would make adopting `private` on a big file an N-compiles-to-find-N-callers job.
[ "$W" -ge 2 ] || { echo "  FAIL: visibility-private — not reporting all violations in one run"; fail=1; }

# The real adoption: lib/regex.cyr is private-by-default with a 9-fn public surface.
# This asserts the shipped tree actually enforces, not just the synthetic fixture.
cat > "$T/rx.cyr" <<'EOF'
include "lib/regex.cyr"
fn main(): i64 { return _re_alloc_class(); }
EOF
( cd "$ROOT" && cat "$T/rx.cyr" | "$CC" >/dev/null 2>"$T/rx.err" ) || true
grep -q "'_re_alloc_class' is private to its file" "$T/rx.err" 2>/dev/null     || { echo "  FAIL: visibility-private — lib/regex.cyr adoption is not enforcing"; fail=1; }
cat > "$T/rx2.cyr" <<'EOF'
include "lib/regex.cyr"
fn main(): i64 { return regex_compile(0, 0); }
EOF
( cd "$ROOT" && cat "$T/rx2.cyr" | "$CC" >/dev/null 2>"$T/rx2.err" ) || true
grep -q "is private to its file" "$T/rx2.err" 2>/dev/null     && { echo "  FAIL: visibility-private — regex.cyr's PUBLIC surface was rejected"; fail=1; }

if [ "$fail" = "0" ]; then
    echo "  PASS: visibility-private — hard-error on ordinary/tail/operator paths, no binary emitted, multi-error; 'public' re-exposes; lib/regex.cyr adoption live; default inert"
fi
exit $fail
