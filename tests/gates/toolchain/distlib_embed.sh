#!/bin/sh
# distlib_embed.sh — 6.6.19 (P2, E3). `cyrius distlib` carries the [embed] entries a bundle NAMES —
# `[lib] embed` for the base bundle, `[lib.P] embed` for profile P — and nothing else; the bundle
# is verified ALONE, without the producer's own [embed] prelude or [build] modules.
#
# WHY: the four consumer generators (agnosai, agnostic, rekha, sankoch) check a generated .cyr in
# and hope it is fresh. A bundle that carries its embed gets `distlib --check` as the freshness
# gate. And the verify must not borrow from the producer: its prelude would satisfy NAME() for a
# bundle that lacks it, and _materialize_source prepends [build] modules whatever _skip_deps says.
#
# AXES (measured on 1ea6757b's CLI: every axis but 7 is RED — 12 rows; axis 7, lint, is a guard
# that the generated literal line stays lint-clean)
#   1. `[lib.p] embed = ["D"]`: dist/x-p.cyr carries D; the base dist/x.cyr does not.
#   2. that bundle compiles in a CONSUMER with no [embed], and the bytes round-trip (`cmp`).
#   3. `cyrius distlib --check` is GREEN, then names dist/x-p.cyr STALE after the data file is edited.
#   4. a [lib.p] module calling D() / D_len() with no `embed` listed makes distlib FAIL naming D and
#      `[lib.p] embed` — not the 6.6.18 "still undefined" warning, which a bundle calling a
#      consumer's hook legitimately gets.
#   5. `[lib] embed = ["NOPE"]` (not declared in [embed]) is refused by name; an [embed] NAME the
#      pinned stdlib snapshot declares (vec_new) is refused before any bundle is written.
#   6. `--modular` writes dist/x/embed_D.cyr and an index row `embed_D = []`, and the module that
#      calls D() lists "embed_D" as a sibling.
#   7. `cyrius lint` passes on the bundle (the literal's line carries #skip-lint).
#   8. an EMBED-ONLY profile is legal (rekha's `[lib.face]`): no modules, `embed = ["F"]` → a bundle
#      of the bytes; a profile with neither is still refused ("no modules found for profile").
#   9. [build] modules are not in the verify: a [lib.p] bundle that reads a global only a [build]
#      module defines is refused ("does not compile"); 6.6.18 verified it green, because both the
#      bundle self-check and every per-target verify child prepended [build] modules.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: distlib_embed: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: distlib_embed: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
# A throwaway home: the tree's CLI, cycc, cycc_aarch64 (the verify compiles for every target),
# cyrlint, and the tree's lib as the stdlib snapshot.
H="$W/home"
mkdir -p "$H/bin"
"$CC" < cbt/cyrius.cyr > "$H/bin/cyrius" 2> "$W/b.err" || { echo "FAIL: distlib_embed: cbt/cyrius.cyr does not build"; tail -3 "$W/b.err"; exit 1; }
cp "$CC" "$H/bin/cycc"
"$CC" < src/main_aarch64.cyr > "$H/bin/cycc_aarch64" 2> "$W/b.err" || { echo "SKIP: distlib_embed: cannot build cycc_aarch64 for the verify"; exit 77; }
"$CC" < programs/cyrlint.cyr > "$H/bin/cyrlint" 2> "$W/b.err" || { echo "SKIP: distlib_embed: cannot build cyrlint"; exit 77; }
chmod +x "$H/bin/"*
cp -R "$ROOT/lib" "$H/lib"
CY="$H/bin/cyrius"
P="$W/x"
mkdir -p "$P/src" "$P/data"
run() { d=$1; shift; ( cd "$d" && env -u CYRIUS_DCE -u CYRIUS_DEFINES CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 timeout 300 "$CY" "$@" ); }
printf 'line one "q" \\\n\001\000\377 tail\n' > "$P/data/d.bin"
printf 'face bytes\000\001\n' > "$P/data/f.bin"
printf 'fn a_one(): i64 { return 1; }\n' > "$P/src/a.cyr"
printf 'fn p_len(): i64 { return D_len(); }\nfn p_ptr(): i64 { return D(); }\n' > "$P/src/p.cyr"
manifest() {  # manifest <[lib.p] extra line>
    { printf '[package]\nname = "x"\n\n[embed]\nD = "data/d.bin"\nF = "data/f.bin"\n\n[lib]\nmodules = ["src/a.cyr"]\n\n'
      printf '[lib.p]\nmodules = ["src/p.cyr"]\n%s\n\n[lib.face]\nembed = ["F"]\n' "$1"; } > "$P/cyrius.cyml"
}
manifest 'embed = ["D"]'

# ── axis 1 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
rc=0; run "$P" distlib > "$W/o" 2>&1 || rc=$?; [ "$rc" = 0 ] || fail "axis 1: distlib (base) exited $rc: $(grep error "$W/o" | head -1)"
rc=0; run "$P" distlib p > "$W/o" 2>&1 || rc=$?; [ "$rc" = 0 ] || fail "axis 1: distlib p exited $rc: $(grep error "$W/o" | head -1)"
dn=$(wc -c < "$P/data/d.bin" | tr -d ' ')
grep -q '^fn D(): i64 {' "$P/dist/x-p.cyr" 2>/dev/null && grep -q "^fn D_len(): i64 { return $dn; }" "$P/dist/x-p.cyr" \
    || fail "axis 1: dist/x-p.cyr does not carry fn D() / D_len() = $dn"
grep -q 'fn D(' "$P/dist/x.cyr" 2>/dev/null && fail "axis 1: the base bundle carries D, which only [lib.p] names"
[ "$FAIL" = "$x" ] && echo "  ok axis 1: [lib.p] embed = [\"D\"] puts D in dist/x-p.cyr and not in dist/x.cyr"

# ── axis 2 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
C="$W/consumer"
mkdir -p "$C"
cp "$P/dist/x-p.cyr" "$C/x-p.cyr" 2>/dev/null
printf 'include "x-p.cyr"\nsyscall(1, 1, p_ptr(), p_len());\nsyscall(60, 0);\n' > "$C/main.cyr"
printf '[package]\nname = "c"\n[build]\nentry = "main.cyr"\noutput = "build/c"\n' > "$C/cyrius.cyml"
rc=0; run "$C" build > "$W/o" 2>&1 || rc=$?
if [ "$rc" = 0 ]; then "$C/build/c" > "$W/got"; cmp -s "$P/data/d.bin" "$W/got" || fail "axis 2: the consumer's bytes differ from data/d.bin"
else fail "axis 2: a consumer including the bundle does not build (exit $rc): $(grep -E 'error|undefined' "$W/o" | head -1)"; fi
[ "$FAIL" = "$x" ] && echo "  ok axis 2: the bundle builds in a consumer with no [embed], and the bytes round-trip"

# ── axis 3 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
run "$P" distlib face > /dev/null 2>&1
rc=0; run "$P" distlib --check > "$W/o" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "axis 3: --check on fresh bundles exited $rc: $(grep -E 'STALE|error' "$W/o" | head -1)"
printf 'edited\n' >> "$P/data/d.bin"
rc=0; run "$P" distlib --check > "$W/o" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -q 'STALE: dist/x-p.cyr' "$W/o" || fail "axis 3: --check after editing data/d.bin did not name dist/x-p.cyr STALE (exit $rc)"
grep -q 'STALE: dist/x.cyr$' "$W/o" && fail "axis 3: the base bundle went STALE although it carries no embed"
run "$P" distlib p > /dev/null 2>&1
[ "$FAIL" = "$x" ] && echo "  ok axis 3: distlib --check is green, then names the bundle STALE when its data file changes"

# ── axis 4 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
manifest ''
rc=0; run "$P" distlib p > "$W/o" 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "axis 4: a [lib.p] bundle calling D() without listing it exited 0"
grep -q "calls D(), the accessor of \[embed\] D, but cyrius.cyml \[lib.p\] embed does not list D" "$W/o" \
    || fail "axis 4: the refusal does not name D and [lib.p] embed: $(grep -E 'error|warn' "$W/o" | head -2 | tr '\n' ' ')"
manifest 'embed = ["D"]'
[ "$FAIL" = "$x" ] && echo "  ok axis 4: a bundle that calls an embed it does not carry is refused, naming D and [lib.p] embed (the verify ran without the producer's prelude)"

# ── axis 5 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
cp "$P/cyrius.cyml" "$W/keep.cyml"
sed 's/^modules = \["src\/a.cyr"\]$/modules = ["src\/a.cyr"]\nembed = ["NOPE"]/' "$W/keep.cyml" > "$P/cyrius.cyml"
rc=0; run "$P" distlib > "$W/o" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -qF 'error: cyrius.cyml [lib] embed names NOPE, which [embed] does not declare' "$W/o" \
    || fail "axis 5: [lib] embed = [\"NOPE\"] was not refused by name (exit $rc): $(head -2 "$W/o" | tr '\n' ' ')"
cp "$W/keep.cyml" "$P/cyrius.cyml"
# 5b: a NAME the pinned stdlib snapshot declares (vec_new, in the home's lib) is refused before any
# bundle is written — a consumer including the bundle after its stdlib would have vec_new()
# REPLACED by the bytes (measured: `vec: alloc failed`, exit 1, a duplicate-fn warning only).
sed 's/^F = "data\/f.bin"$/F = "data\/f.bin"\nvec_new = "data\/f.bin"/; s/^embed = \["F"\]$/embed = ["F", "vec_new"]/' "$W/keep.cyml" > "$P/cyrius.cyml"
rm -f "$P/dist/x-face.cyr"
rc=0; run "$P" distlib face > "$W/o" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -qF 'error: cyrius.cyml [embed] vec_new: vec_new is already declared by the stdlib leaf vec' "$W/o" \
    || fail "axis 5b: [embed] vec_new (a stdlib fn) was not refused by name (exit $rc): $(head -2 "$W/o" | tr '\n' ' ')"
[ -e "$P/dist/x-face.cyr" ] && fail "axis 5b: a bundle was written anyway"
cp "$W/keep.cyml" "$P/cyrius.cyml"
[ "$FAIL" = "$x" ] && echo "  ok axis 5: an undeclared NAME in [lib] embed is refused by name; a NAME the stdlib snapshot declares is refused before any bundle is written"

# ── axis 6 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
rc=0; run "$P" distlib --modular p > "$W/o" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "axis 6: distlib --modular p exited $rc"
grep -q '^fn D(): i64 {' "$P/dist/x/embed_D.cyr" 2>/dev/null || fail "axis 6: no dist/x/embed_D.cyr carrying fn D()"
grep -qx 'embed_D = \[\]' "$P/dist/x/index.cyml" 2>/dev/null || fail "axis 6: index.cyml has no 'embed_D = []' row"
grep -qx 'p = \["embed_D"\]' "$P/dist/x/index.cyml" 2>/dev/null || fail "axis 6: the module calling D() does not list embed_D as a sibling: $(grep '^p ' "$P/dist/x/index.cyml" 2>/dev/null)"
[ "$FAIL" = "$x" ] && echo "  ok axis 6: --modular emits embed_D.cyr + its index row, and the caller lists it"

# ── axis 7 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
head -c 3000 /dev/urandom > "$P/data/d.bin"
run "$P" distlib p > /dev/null 2>&1
rc=0; run "$P" lint dist/x-p.cyr > "$W/o" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -q '^0 warnings' "$W/o" || fail "axis 7: cyrius lint on the bundle (a 3,000-byte literal line) exited $rc: $(grep -E 'warn|error' "$W/o" | head -1)"
[ "$FAIL" = "$x" ] && echo "  ok axis 7: cyrius lint passes on the bundle (#skip-lint on the literal's line)"

# ── axis 8 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
rm -f "$P/dist/x-face.cyr"
rc=0; run "$P" distlib face > "$W/o" 2>&1 || rc=$?
fnn=$(wc -c < "$P/data/f.bin" | tr -d ' ')
[ "$rc" = 0 ] && grep -q "^fn F_len(): i64 { return $fnn; }" "$P/dist/x-face.cyr" 2>/dev/null \
    || fail "axis 8: an embed-only [lib.face] did not produce dist/x-face.cyr with F (exit $rc): $(grep error "$W/o" | head -1)"
printf '\n[lib.empty]\nnothing = 1\n' >> "$P/cyrius.cyml"
rc=0; run "$P" distlib empty > "$W/o" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -q 'no modules found for profile' "$W/o" || fail "axis 8: a profile with neither modules nor embed was not refused (exit $rc)"
cp "$W/keep.cyml" "$P/cyrius.cyml"
[ "$FAIL" = "$x" ] && echo "  ok axis 8: an embed-only profile is a bundle of its bytes; a profile with neither is still refused"

# ── axis 9 ───────────────────────────────────────────────────────────────────────────────
x=$FAIL
Y="$W/y"
mkdir -p "$Y/src"
printf '[package]\nname = "y"\n[build]\nmodules = ["src/all.cyr"]\n[lib.p]\nmodules = ["src/p.cyr"]\n' > "$Y/cyrius.cyml"
printf 'var G_ONLY_HERE = 5;\nfn all_one(): i64 { return G_ONLY_HERE; }\n' > "$Y/src/all.cyr"
printf 'fn p_get(): i64 { return G_ONLY_HERE; }\n' > "$Y/src/p.cyr"
rc=0; run "$Y" distlib p > "$W/o" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -q 'the generated bundle does not compile' "$W/o" \
    || fail "axis 9: a [lib.p] bundle reading a global only a [build] module defines verified green (exit $rc) — [build] modules leaked into the verify"
printf 'var G_ONLY_HERE = 5;\nfn p_get(): i64 { return G_ONLY_HERE; }\n' > "$Y/src/p.cyr"
rc=0; run "$Y" distlib p > "$W/o" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "axis 9 control: a self-contained [lib.p] bundle was refused (exit $rc): $(grep error "$W/o" | head -1)"
[ "$FAIL" = "$x" ] && echo "  ok axis 9: [build] modules stay out of the bundle verify (a borrowed global is refused; a self-contained bundle passes)"

[ "$FAIL" = 0 ] || { echo "FAIL: distlib_embed ($FAIL)"; exit 1; }
echo "PASS: distlib_embed"
