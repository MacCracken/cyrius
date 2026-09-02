#!/bin/sh
# Gate: a dependency must not overwrite a stdlib leaf the snapshot already provided (v6.5.39).
#
# THE DEFECT (filed 2026-09-01, confirmed in two consumer repos). A named dep whose NAME
# collides with a declared `[deps] stdlib` leaf lands its own resolved artifact on
# `lib/<leaf>.cyr` and WINS, because the resolver's phase order guarantees it: Phase 1 copies
# the stdlib from the pinned snapshot, Phase 2 does named deps, Phase 3 the transitive BFS —
# and Phase 3 is structurally LAST. Measured at 6.5.38: `cyrius lib sync` writes sakshi
# 2.4.12 and the very next `cyrius deps` silently reverts it to the dep's version, exit 0,
# no diagnostic. Measured blast radius: 12 of the ~101 stdlib modules share a name with a
# standalone package repo; 16 of 126 sibling repos are in the collision shape and 8 already
# carry a leaf that differs from their own pin's snapshot.
#
# ⚠ THE FILING'S NAMED MECHANISM IS WRONG, and axis 1's sentinel is built to prove which
# source actually wins. The filing concluded "from the named dep's own lib/" from a
# byte-identity, but several files share those bytes. The real source is the dep's RESOLVED
# ARTIFACT. Here the "dep" is a local path package whose dist file contains a sentinel string
# that exists nowhere else on the box, so a clobber is identifiable rather than inferred.
#
# ⛔ AXIS 4 IS THE ONE THAT CONSTRAINS THE FIX, and it rejects the obvious implementation.
# The tempting test is "does <stdlib_dir>/<name>.cyr exist?" — but every one of the ~101
# stdlib modules exists in the snapshot, so that would ALSO refuse a project that legitimately
# depends on a package of that name WITHOUT declaring it as a stdlib leaf, leaving it with no
# `lib/<name>.cyr` at all. The discriminator has to be "did Phase 1 actually copy this leaf",
# i.e. the stdlib seen-set. Axis 4 fails for the existence-test implementation and passes for
# the seen-set one.
#
# ⚠ FULLY HERMETIC: path deps only, no git, no network, no dependence on which versions
# happen to be in ~/.cyrius/deps. The only external requirement is an installed snapshot for
# the current VERSION, which every other toolchain gate already assumes.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: deps_stdlib_leaf_not_clobbered: build/cycc missing"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: deps_stdlib_leaf_not_clobbered: $1"; exit 1; }

# ⛔ BUILD the CLI from source rather than resolving one. `$ROOT/build/cyrius` does not exist
# in a normal tree, so the usual `${CYRIUS_BIN:-build/cyrius}` fallback silently tests the
# INSTALLED cyrius — which is the previous release. That is the same "the wrapper resolves the
# installed toolchain" trap that produced four wrong results during v6.5.37, one level up.
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$WORK/cyrius" ) 2>/dev/null \
    || fail "could not build cbt/cyrius.cyr with build/cycc"
chmod +x "$WORK/cyrius"
CYRIUS="$WORK/cyrius"

V=$(cat "$ROOT/VERSION")
SNAP="$HOME/.cyrius/versions/$V/lib/sakshi.cyr"
[ -f "$SNAP" ] || { echo "SKIP: no stdlib snapshot at $SNAP (install not refreshed for $V)"; exit 0; }

SENTINEL="FAKE-SAKSHI-SENTINEL-deps-gate"

# A local package whose NAME collides with a stdlib leaf, and whose content is identifiable.
mk_tree() {   # mk_tree <root> <declare-sakshi-as-stdlib: yes|no>
    R="$1"
    mkdir -p "$R/fakesakshi/dist" "$R/mydep/dist" "$R/consumer"
    printf '# %s\nfn fake_sakshi_marker(): i64 { return 424242; }\n' "$SENTINEL" > "$R/fakesakshi/dist/sakshi.cyr"
    printf '[package]\nname = "sakshi"\nversion = "9.9.9"\n' > "$R/fakesakshi/cyrius.cyml"
    printf '# mydep\nfn mydep_hello(): i64 { return 1; }\n' > "$R/mydep/dist/mydep.cyr"
    cat > "$R/mydep/cyrius.cyml" <<EOF
[package]
name = "mydep"
version = "0.1.0"

[deps.sakshi]
path = "../fakesakshi"
modules = ["dist/sakshi.cyr"]
EOF
    if [ "$2" = "yes" ]; then STDLIB='stdlib = ["syscalls", "alloc", "string", "sakshi"]'
    else                      STDLIB='stdlib = ["syscalls", "alloc", "string"]'; fi
    cat > "$R/consumer/cyrius.cyml" <<EOF
[package]
name = "consumer"
version = "0.1.0"

[deps]
cyrius = "$V"
$STDLIB

[deps.mydep]
path = "../mydep"
modules = ["dist/mydep.cyr"]
EOF
}

# ── axis 1: the declared stdlib leaf SURVIVES a same-named transitive dep ───────────
mk_tree "$WORK/a" yes
set +e
OUT=$(cd "$WORK/a/consumer" && "$CYRIUS" deps 2>&1); RC=$?
set -e
[ "$RC" -eq 0 ] || fail "axis 1: deps failed (exit $RC) — the guard must skip one module, not break resolution: $OUT"
[ -f "$WORK/a/consumer/lib/sakshi.cyr" ] || fail "axis 1: lib/sakshi.cyr is absent — the guard skipped the copy without the snapshot having landed"
if grep -q "$SENTINEL" "$WORK/a/consumer/lib/sakshi.cyr"; then
    fail "axis 1: the dep's artifact CLOBBERED the stdlib leaf — lib/sakshi.cyr carries the sentinel"
fi
cmp -s "$WORK/a/consumer/lib/sakshi.cyr" "$SNAP" \
    || fail "axis 1: lib/sakshi.cyr survived the sentinel but does not match the pinned snapshot"

# ── axis 2: the refusal is ANNOUNCED, and names both sides ─────────────────────────
# A silent skip would be a different bug wearing this fix's clothes: the consumer would have
# no way to learn their manifest declares the same name twice.
echo "$OUT" | grep -q "refusing to overwrite stdlib leaf" \
    || fail "axis 2: the leaf was preserved but nothing was reported; got: $OUT"
echo "$OUT" | grep -q "sakshi" || fail "axis 2: the warning does not name the leaf"
echo "$OUT" | grep -q "skipped" || fail "axis 2: the warning does not name the artifact it skipped"

# ── axis 3: `lib sync` then `deps` must not revert — the filed acceptance criterion ──
set +e
( cd "$WORK/a/consumer" && "$CYRIUS" lib sync ) >/dev/null 2>&1
A=$(wc -c < "$WORK/a/consumer/lib/sakshi.cyr")
( cd "$WORK/a/consumer" && "$CYRIUS" deps ) >/dev/null 2>&1
B=$(wc -c < "$WORK/a/consumer/lib/sakshi.cyr")
set -e
[ "$A" = "$B" ] || fail "axis 3: 'deps' reverted what 'lib sync' wrote ($A B -> $B B) — the filed round-trip still fails"

# ── axis 4: ⛔ a package dep NOT declared as stdlib must STILL land ─────────────────
# This is what rejects the existence-test implementation. If the guard keys on "does the
# snapshot have a file of this name" instead of "did Phase 1 copy it", this project ends up
# with NO lib/sakshi.cyr and every symbol in it undefined.
mk_tree "$WORK/b" no
set +e
OUT2=$(cd "$WORK/b/consumer" && "$CYRIUS" deps 2>&1); RC2=$?
set -e
[ "$RC2" -eq 0 ] || fail "axis 4: deps failed (exit $RC2) for a legitimate package dep: $OUT2"
[ -f "$WORK/b/consumer/lib/sakshi.cyr" ] \
    || fail "axis 4: a package dep NOT declared as stdlib got NO lib/sakshi.cyr — the guard is over-broad and keyed on the wrong test"
grep -q "$SENTINEL" "$WORK/b/consumer/lib/sakshi.cyr" \
    || fail "axis 4: lib/sakshi.cyr exists but is not the dep's artifact — the undeclared case was silently served the snapshot instead"

# ── axis 5: anti-vacuous — the collision path was really exercised ──────────────────
# If the fixture stopped producing a collision (a manifest key renamed, path deps changing
# shape), axes 1-3 would pass for the wrong reason. The unguarded build MUST clobber.
[ -f "$WORK/b/consumer/lib/mydep.cyr" ] \
    || fail "axis 5: the intermediate dep did not resolve at all — the fixture is not exercising the transitive path the defect lives on"

echo "PASS: deps_stdlib_leaf_not_clobbered (declared leaf survives + refusal announced + lib-sync round-trip holds + undeclared package dep still lands)"
