#!/bin/sh
# Gate: cyrius.lock is emitted in SORTED path order (v6.6.3).
#
# THE DEFECT. `_deps_lock_dir` hashed `lib/` straight out of `dir_list`, i.e. readdir
# order. On ext4 with dir_index that is a hash of the FILENAME, so it is stable for a
# given name set on a given filesystem and DIFFERENT on another — which is the worst
# shape a nondeterminism can have: it reproduces perfectly on the machine you are
# debugging on and only ever fails somewhere else.
#
# Consumers commit cyrius.lock and gate it with `git diff --exit-code -- cyrius.lock`.
# That gate therefore failed for every lock committed from a different machine — i.e.
# always. Measured on agnostic, 2026-09-12:
#
#     cyrius.lock | 196 +++++++++++++++++-------------------
#     1 file changed, 98 insertions(+), 98 deletions(-)
#
# ...while `sort committed | diff - <(sort resolved)` was EMPTY: identical hashes for
# all 117 entries, identical commit pins, only the sequence moved. The error text
# ("does not match a clean resolution at this pin") reads as dependency drift, so it
# sends the reader hunting stale pins that are not stale. It cost most of a day across
# two repos and did not reproduce on a clean checkout with a cold CYRIUS_HOME, a cold
# dep cache and the release tarball — the runner was the only place the evidence lived.
#
# ⭐ WHY THIS GATE IS BEHAVIOURAL where its sibling deps_family_expansion_ordered.sh is
# structural: there, the order was internal and unobservable (a directory has no order,
# and `ls` sorts its own output — the first cut of that gate passed against the unsorted
# build). Here the order IS the artefact. cyrius.lock records it literally, one path per
# line, so the assertion reads the real output of the real resolver.
#
# MUTATION PROOF. Delete the `vec_sort_by(entries, &_dep_name_cmp)` line from
# `_deps_lock_dir` in cbt/deps.cyr and this gate reddens: the lock comes back in readdir
# order, which on this filesystem is not sorted. Verified before commit.
#
# See docs/development/issues/2026-09-12-cyrius-lock-unstable-order.md
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: deps_lock_sorted: build/cycc missing"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: deps_lock_sorted: $1"; exit 1; }

# Build the CLI FROM SOURCE — the installed `cyrius` is whatever was last released and
# would test the wrong binary.
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$WORK/cyrius" ) 2>/dev/null \
    || fail "could not build cbt/cyrius.cyr with build/cycc"
chmod +x "$WORK/cyrius"

V=$(cat "$ROOT/VERSION")
[ -d "$HOME/.cyrius/versions/$V/lib" ] \
    || { echo "SKIP: no stdlib snapshot for $V (install not refreshed)"; exit 0; }

# Outside the cyrius repo on purpose: cmd_deps_lock SKIPS lock generation when it
# detects the source repo (_dep_is_cyrius_source_repo), so an in-tree fixture would
# assert nothing at all.
P="$WORK/proj"
mkdir -p "$P"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "locksort"
version = "0.1.0"
language = "cyrius"
cyrius = "$V"

[build]
entry = "src/main.cyr"

[deps]
stdlib = ["str", "vec", "io", "fmt", "alloc", "hashmap", "tagged", "result", "math", "bench"]
EOF
mkdir -p "$P/src"
printf 'fn main(): i64 { return 0; }\n' > "$P/src/main.cyr"

# Two steps on purpose. `deps` RESOLVES (populates lib/); `deps --lock` WRITES the
# lock. A stdlib-only project emits no lock by default ("No lockfile by default",
# first-party-standards.md), and `--lock` on its own would hash an empty lib/ and
# "pass" on zero entries — which is exactly the vacuous shape the entry-count guard
# below exists to refuse.
( cd "$P" && "$WORK/cyrius" deps ) >"$WORK/deps.log" 2>&1 \
    || { sed 's/^/    /' "$WORK/deps.log"; fail "cyrius deps failed to resolve"; }
( cd "$P" && "$WORK/cyrius" deps --lock ) >>"$WORK/deps.log" 2>&1 \
    || { sed 's/^/    /' "$WORK/deps.log"; fail "cyrius deps --lock failed"; }
[ -f "$P/cyrius.lock" ] || fail "no cyrius.lock produced"

# The paths, in the order the resolver wrote them.
awk '$2 ~ /^lib\// { print $2 }' "$P/cyrius.lock" > "$WORK/paths"
N=$(wc -l < "$WORK/paths")

# Guard against a vacuous pass: one entry is sorted by definition.
[ "$N" -ge 2 ] || fail "only $N lib/ entries locked — too few to test ordering"

sort "$WORK/paths" > "$WORK/paths.sorted"
if ! cmp -s "$WORK/paths" "$WORK/paths.sorted"; then
    echo "  lock is NOT in sorted path order; first divergence:"
    diff "$WORK/paths" "$WORK/paths.sorted" | head -6 | sed 's/^/    /'
    fail "cyrius.lock emitted in readdir order ($N entries)"
fi

# Regenerating must not perturb it either.
cp "$P/cyrius.lock" "$WORK/lock.1"
( cd "$P" && "$WORK/cyrius" deps ) >/dev/null 2>&1 || fail "second resolve failed"
( cd "$P" && "$WORK/cyrius" deps --lock ) >/dev/null 2>&1 || fail "second lock failed"
cmp -s "$WORK/lock.1" "$P/cyrius.lock" || fail "lock changed across two identical resolves"

echo "PASS: deps_lock_sorted ($N lib/ entries, sorted and stable across re-resolve)"
