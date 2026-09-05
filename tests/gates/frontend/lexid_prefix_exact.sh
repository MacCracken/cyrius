#!/bin/sh
# lexid_prefix_exact.sh — v6.5.56. Identifier dedup must be an EXACT compare, not a prefix one.
#
# THE DEFECT (P0, live v6.5.50 → v6.5.55). `LEXID`'s dedup loop walked `klen` bytes of a
# candidate entry and never checked that the STORED entry ENDED there. A shorter identifier that
# is a prefix of a longer one in the same hash bucket therefore matched it and took its pool
# offset, so the two names became ONE symbol:
#     var ah = 7; var ahxaa = 99;   ->  reading `ah` gave 99
# Exit 0, no diagnostic, wrong value. 127 repos under ~/Repos carry at least one colliding pair
# (217 in total), `agnos` among them.
#
# ⭐ WHY IT WAS CORRECT BEFORE .50, AND WHY THAT MATTERS FOR THIS GATE. While `bucket = klen`,
# one chain held exactly one length, so entries in a chain could not differ in length and the
# prefix compare WAS exact. v6.5.50 replaced that with a content hash and removed the invariant
# WITHOUT adding the check it had been standing in for — and left the comment asserting "dedup
# remains an exact byte-compare" in place. A property that holds as a side effect of an unrelated
# invariant is exactly what breaks silently when the invariant moves.
#
# ⛔ THE SELF-HOST FIXPOINT CANNOT DETECT THIS AND MUST NOT BE USED AS THE GATE. cycc's own
# source has ZERO colliding prefix pairs out of 54,089 identifiers, and the aliasing is
# deterministic, so it reproduces identically across generations: the fixpoint stays
# byte-identical while consumer output is wrong. That is why this gate pins the PROPERTY on a
# known-colliding pair instead — the v6.5.36 lesson, applied before it cost a release.
#
# ⚠ Builds the compiler FROM SOURCE: the dedup under test lives in the compiler being built.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL lexid_prefix_exact: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL lexid_prefix_exact: stage1 build failed"; exit 1; }
chmod +x "$T/cc"

run() {  # $1 = source, $2 = expected exit
  "$T/cc" < "$1" > "$T/p" 2>"$T/e" || { echo "compile-failed"; return; }
  chmod +x "$T/p"; "$T/p"; echo "$?"
}

fail=0

# axis 1 — locals: the shorter name is a prefix of the longer, same bucket.
cat > "$T/a1.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { var ah = 7; var ahxaa = 99; syscall(60, ah, 0, 0, 0, 0); return 0; }
EOF
G=$(run "$T/a1.cyr"); [ "$G" = "7" ] || { echo "FAIL lexid_prefix_exact axis1: 'ah' read as $G, expected 7 (bound to 'ahxaa')"; fail=1; }

# axis 2 — the shape found live in a consumer (whirl's _cli_body / _cli_bodyerr).
cat > "$T/a2.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { var _cli_body = 11; var _cli_bodyerr = 22; syscall(60, _cli_body, 0, 0, 0, 0); return 0; }
EOF
G=$(run "$T/a2.cyr"); [ "$G" = "11" ] || { echo "FAIL lexid_prefix_exact axis2: '_cli_body' read as $G, expected 11"; fail=1; }

# axis 3 — DECLARATION ORDER REVERSED. The canonical offset is the first occurrence, so the
# longer-first order exercises the other side of the chain walk.
cat > "$T/a3.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { var ahxaa = 99; var ah = 7; syscall(60, ah + ahxaa, 0, 0, 0, 0); return 0; }
EOF
G=$(run "$T/a3.cyr"); [ "$G" = "106" ] || { echo "FAIL lexid_prefix_exact axis3: ah+ahxaa = $G, expected 106 (7+99)"; fail=1; }

# axis 4 — FUNCTION names, not just variables: the same pool backs both.
cat > "$T/a4.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn ah(): i64 { return 7; }
fn ahxaa(): i64 { return 99; }
fn main(): i64 { syscall(60, ah(), 0, 0, 0, 0); return 0; }
EOF
G=$(run "$T/a4.cyr"); [ "$G" = "7" ] || { echo "FAIL lexid_prefix_exact axis4: fn 'ah()' returned $G, expected 7"; fail=1; }

# axis 5 — CONTROL, so the gate cannot pass by breaking dedup entirely. Two names that are NOT
# prefixes must still be distinct, and a repeated name must still dedup to one symbol.
cat > "$T/a5.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var alpha = 3; var beta = 5;
    var s = 0; var i = 0;
    while (i < 4) { s = s + alpha; i = i + 1; }
    syscall(60, s + beta, 0, 0, 0, 0);
    return 0;
}
EOF
G=$(run "$T/a5.cyr"); [ "$G" = "17" ] || { echo "FAIL lexid_prefix_exact axis5 (control): got $G, expected 17 — dedup is broken for NON-prefix names"; fail=1; }

[ $fail -eq 0 ] || exit 1
echo "PASS lexid_prefix_exact: prefix pairs stay distinct (locals, consumer shape, both orders, fns) + non-prefix control"
exit 0
