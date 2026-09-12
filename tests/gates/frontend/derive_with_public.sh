#!/bin/sh
# Gate: `#derive(...)` composes with `public`, and the generated accessors inherit it.
#
# THE DEFECT (v6.6.3). PP_PARSE_STRUCT_DEF byte-compares the literal "struct " / "enum "
# AT the declaration position, so `public struct P { ... }` matched neither probe and fell
# into `error: #derive(...) applies to a struct or an enum; the following declaration is
# neither`. That made `#derive` and file visibility mutually exclusive — unusable together
# in any file that derives accessors, which in practice is every foundation type. Filed
# while adopting private/public across hisab's 35 modules; no workaround existed.
#
# ⚠ COMPILING IS NOT ENOUGH, which is why axis 4 exists. A `public struct` whose accessors
# came out at default visibility would leave a caller in another file able to NAME the type
# and unable to reach a single field — the same dead end as not compiling, and it would not
# lift the filing's actual complaint. So `public` propagates onto the generated fns.
#
# ⛔ AXIS 5 IS THE ANTI-VACUOUS HALF and must not be dropped: it proves the fix did not
# simply make every derived accessor public. A NON-public struct in a private file must
# still produce PRIVATE accessors and be rejected across a file boundary. Without it,
# `vis = "public "` unconditionally would pass axes 1-4.
#
# Mutation-proven: reverting the visibility skip reddens axis 1; forcing `vis` unconditional
# reddens axis 5.
#
# See docs/development/issues/2026-09-11-derive-cannot-combine-with-public.md
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: derive_with_public: build/cycc missing"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: derive_with_public: $1"; exit 1; }

cd "$ROOT"   # includes resolve relative to the repo root

# The two cross-file axes need a module OUTSIDE the tree, and absolute includes are
# refused by default (a path-traversal control). Permit them for this gate only —
# the alternative is writing fixtures into the repo root, which litters on failure.
export CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1

# --- axis 1: #derive + `public struct` compiles -----------------------------------
printf '#derive(accessors)\npublic struct P { x; y; }\n\nfn main(): i64 { return 0; }\n' > "$WORK/a.cyr"
"$CC" < "$WORK/a.cyr" > /dev/null 2>"$WORK/a.err" \
    || { sed 's/^/    /' "$WORK/a.err"; fail "axis1: #derive + 'public struct' rejected"; }

# --- axis 2: the `pub` spelling (same token 73) -----------------------------------
printf '#derive(accessors)\npub struct Q { a; b; }\n\nfn main(): i64 { return 0; }\n' > "$WORK/b.cyr"
"$CC" < "$WORK/b.cyr" > /dev/null 2>"$WORK/b.err" \
    || { sed 's/^/    /' "$WORK/b.err"; fail "axis2: #derive + 'pub struct' rejected"; }

# --- axis 3: control — the plain form must not regress ----------------------------
printf '#derive(accessors)\nstruct R { m; n; }\n\nfn main(): i64 { return 0; }\n' > "$WORK/c.cyr"
"$CC" < "$WORK/c.cyr" > /dev/null 2>"$WORK/c.err" \
    || { sed 's/^/    /' "$WORK/c.err"; fail "axis3: plain '#derive + struct' regressed"; }

# --- axis 4: public accessors are REACHABLE from another file ---------------------
cat > "$WORK/pubmod.cyr" <<'EOF'
private

#derive(accessors)
public struct P { x; y; }
EOF
cat > "$WORK/use_pub.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "$WORK/pubmod.cyr"

fn main(): i64 {
    alloc_init();
    var p = alloc(16);
    P_set_x(p, 11);
    P_set_y(p, 22);
    print_num(P_x(p) + P_y(p));
    return 0;
}
EOF
"$CC" < "$WORK/use_pub.cyr" > "$WORK/pub.bin" 2>"$WORK/pub.err" \
    || { sed 's/^/    /' "$WORK/pub.err"; fail "axis4: public derived accessors not reachable cross-file"; }
chmod +x "$WORK/pub.bin"
OUT=$("$WORK/pub.bin")
[ "$OUT" = "33" ] || fail "axis4: expected 33 from the cross-file accessors, got '$OUT'"

# --- axis 5 (ANTI-VACUOUS): a NON-public struct keeps PRIVATE accessors -----------
cat > "$WORK/privmod.cyr" <<'EOF'
private

#derive(accessors)
struct R { m; n; }
EOF
cat > "$WORK/use_priv.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "$WORK/privmod.cyr"

fn main(): i64 {
    alloc_init();
    var p = alloc(16);
    R_set_m(p, 5);
    print_num(R_m(p));
    return 0;
}
EOF
if "$CC" < "$WORK/use_priv.cyr" > /dev/null 2>"$WORK/priv.err"; then
    fail "axis5: a non-public struct's accessors were reachable cross-file — the fix publicised everything"
fi
grep -q "is private to its file" "$WORK/priv.err" \
    || { sed 's/^/    /' "$WORK/priv.err"; fail "axis5: rejected, but not with the visibility diagnostic"; }

echo "PASS: derive_with_public — public/pub compose with #derive; accessors inherit visibility; non-public stays private"
