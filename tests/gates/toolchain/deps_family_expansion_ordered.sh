#!/bin/sh
# Gate: package-DIRECTORY family expansion is sorted before it is walked (v6.5.37, A8).
#
# THE DEFECT. `dir_list` returns readdir order, which is filesystem-dependent. Measured on
# `lib/unicode` at 6.5.36:
#
#     _casefold_data.cyr  casefold.cyr  _normalize_data.cyr  normalize.cyr  _decode.cyr ...
#
# `unicode` is the one stdlib module that is a package DIRECTORY rather than a flat
# `lib/<name>.cyr`, so it expanded into a consumer's `lib/` — and into that consumer's
# prepended include list — in whatever order the machine's filesystem returned.
#
# ⭐ WHY IT IS NOT COSMETIC HERE. cyrius is a self-hosting toolchain whose central promise is
# byte-identical reproduction; a resolution whose output order depends on directory layout is
# a reproducibility hole. And "every ordering happens to compile" is doing real work — cyrius
# requires globals to be DECLARED BEFORE USE, so a family member ordered ahead of the data
# file it reads is a hard compile error. The failure shape is "builds here, fails on CI".
#
# ⛔ THIS GATE IS STRUCTURAL, DELIBERATELY, AND THE REASON IS WORTH READING BEFORE ANYONE
# "UPGRADES" IT TO A BEHAVIOURAL ONE. The ordering is not externally observable:
#   * the vendored files land in a DIRECTORY, and a directory has no order — `ls` and shell
#     globs both sort their own output, so listing `lib/unicode/` measures `ls`, not the
#     resolver. A behavioural gate written that way PASSES AGAINST THE UNSORTED BUILD. That
#     is not hypothetical: the first version of this gate did exactly that and its mutation
#     run came back green, which is the only reason it was caught.
#   * `ls -U` shows destination readdir order, which the filesystem assigns on write, not the
#     order the resolver copied in.
#   * the order that actually matters is `_dep_includes`, which is internal — `cyrius.lock`
#     does not record it and `deps -v` prints only the declared name (`stdlib: unicode`).
# So there is nothing to assert behaviourally without first adding an observability surface.
# Until that exists, the honest thing is to pin the mechanism and SAY it is the mechanism,
# rather than ship a behavioural-looking check that cannot fail.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: deps_family_expansion_ordered: $1"; exit 1; }
D="$ROOT/cbt/deps.cyr"
C="$ROOT/cbt/commands.cyr"
for f in "$D" "$C"; do [ -f "$f" ] || fail "missing $f"; done

# ── axis 1: the comparator exists and orders by BYTES, not by anything incidental ───
grep -q '^fn _dep_name_cmp(a, b): i64 {' "$D" || fail "axis 1: _dep_name_cmp is gone — nothing can order the expansion"
awk '/^fn _dep_name_cmp/,/^}/' "$D" | grep -q 'load8(pa + i)' || fail "axis 1: _dep_name_cmp no longer compares bytes"

# ── axis 2: the RESOLVER's family expansion sorts before walking ────────────────────
# `_dep_copy_stdlib_recursive`'s expansion is what populates a consumer's lib/.
grep -q 'var entries = dir_list(dir_path);' "$D" || fail "axis 2: the resolver's family expansion moved — re-point this gate"
awk '/var entries = dir_list\(dir_path\);/{found=1; next} found && c<2 {print; c++}' "$D" \
  | grep -q 'vec_sort_by(entries, &_dep_name_cmp)' \
  || fail "axis 2: the resolver expands a package directory WITHOUT sorting — include order is filesystem-dependent"

# ── axis 3: the sidecar VERIFY loop's expansion sorts too ───────────────────────────
# A3's compile-verify splices family members into one source; unsorted there means the
# verification compiles a different program than the consumer will.
grep -q 'var fents = dir_list(str_from(lbase));' "$C" || fail "axis 3: the verify-loop family expansion moved — re-point this gate"
awk '/var fents = dir_list\(str_from\(lbase\)\);/{found=1; next} found && c<2 {print; c++}' "$C" \
  | grep -q 'vec_sort_by(fents, &_dep_name_cmp)' \
  || fail "axis 3: the sidecar verify loop splices family members in filesystem order"

# ── axis 4: ANTI-VACUOUS — the family this protects still exists ────────────────────
# Without this, deleting lib/unicode/ would make axes 1-3 pass while protecting nothing.
[ -d "$ROOT/lib/unicode" ] || fail "axis 4: lib/unicode is gone — the only package-directory family; this gate now guards nothing"
N=$(ls "$ROOT/lib/unicode"/*.cyr 2>/dev/null | wc -l | tr -d ' ')
[ "$N" -ge 3 ] || fail "axis 4: lib/unicode has only $N members — too few for ordering to matter; re-check this gate's premise"

echo "PASS: deps_family_expansion_ordered (structural: comparator present, both expansion sites sort, $N-member family intact)"
