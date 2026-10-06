#!/bin/sh
# Gate: every `cyrius distlib` bundle carries a compile-verified REQUIRES BLOCK, so the bundle
# is raw-includable — `include "dist/<pkg>.cyr"` and nothing else compiles (6.6.18, D5).
#
# ⛔ WHAT IT DID BEFORE. A bundle kept only the `lib/` includes its modules happened to write;
# most modules include nothing (they lean on `[deps] stdlib` auto-prepend or an umbrella), so
# included alone 10 of the 12 vendored folds left 3-207 names undefined, and lib/log.cyr,
# lib/ws.cyr and lib/ws_server.cyr could not include their folds. The sidecar knew the leaves;
# the bundle did not say them.
#
# ⭐ THE BLOCK IS THE SIDECAR AS INCLUDE LINES — same leaves, same order (the final verify
# unit's), families expanded in `_dep_name_cmp` order by the SAME expander the verify unit uses
# (`_distlib_unit_leaf`), written after the header lines lib_freshness.sh and the fold detector
# parse. Named deps are not emitted. A `cyrius deps` consumer is unaffected: include-once is
# keyed on the literal path, the same lines it auto-prepends.
#
# Axes
#   1  a program that is ONLY `include "dist/rq.cyr"` + a call compiles with 0 undefined on
#      x86_64 Linux / Windows / macOS / agnos and aarch64 Linux / macOS (old: strlen, vec_new,
#      unicode_category undefined everywhere)
#   2  the block's include lines equal the sidecar's leaves, in order, the family expanded
#   3  a second `distlib --check` exits 0 (the output is deterministic)
#   4  a leaf-less package's bundle has NO block
#   5  an old-format bundle (the block stripped) under `--check` is STALE and names the cause
#      ("predates cyrius 6.6.18's requires block")
#   6  the header lines are untouched and still first (lib_freshness / the fold detector)
# MUTATION: the `_distlib_write_requires` call removed -> RED on axes 1 and 2 (measured with the
# a2c60583 CLI: no block, three names undefined on all six targets).
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
SNAP="$HOMEDIR/versions/$VER/lib"
[ -d "$SNAP" ] || SNAP="$HOMEDIR/lib"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: distlib_bundle_raw_includable: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_bundle_raw_includable: $1"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
mkdir -p "$WORK/tools" && cp "$CYRIUS" "$WORK/tools/cyrius" && cp "$CC" "$WORK/tools/cycc" \
    && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$WORK/tools/cycc_aarch64" 2>/dev/null ) \
    && chmod +x "$WORK/tools/cyrius" "$WORK/tools/cycc" "$WORK/tools/cycc_aarch64" \
    || { echo "SKIP: distlib_bundle_raw_includable: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CYRIUS="$WORK/tools/cyrius"
[ -d "$SNAP" ] || { echo "SKIP: distlib_bundle_raw_includable: no stdlib snapshot at $SNAP"; exit 77; }
[ -d "$SNAP/unicode" ] || fail "premise: the snapshot has no lib/unicode/ family — re-derive the fixture"

mkproj() {  # mkproj <dir> <body of src/lib.cyr>   — nothing declared, nothing included
    d="$WORK/$1"; mkdir -p "$d/src"
    printf '[package]\nname = "rq"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$VER" > "$d/cyrius.cyml"
    printf '%s\n' "$2" > "$d/src/lib.cyr"
    echo "$d"
}
run_distlib() { ( cd "$1" && shift && CYRIUS_HOME="$HOMEDIR" CYRIUS_RESOLVED=1 "$CYRIUS" distlib "$@" 2>&1 ); }

P=$(mkproj p 'fn rq_go(): i64 {
    var v = vec_new();
    return strlen("ab") + unicode_category(65) + vec_len(v);
}')
rc=0; OUT=$(run_distlib "$P") || rc=$?
[ "$rc" -eq 0 ] || fail "distlib exited $rc: $(echo "$OUT" | head -4)"
B="$P/dist/rq.cyr"; SC="$P/dist/rq.deps"
[ -f "$SC" ] || fail "premise: no sidecar written"

# ── axis 1: raw-includable on six targets ──────────────────────────────────────────────
U="$WORK/u"; mkdir -p "$U/dist" && ln -s "$SNAP" "$U/lib" && cp "$B" "$U/dist/rq.cyr"
printf 'include "dist/rq.cyr"\nvar r = rq_go();\n' > "$U/prog.cyr"
for t in x86_64-linux x86_64-windows x86_64-macos x86_64-agnos aarch64-linux aarch64-macos; do
    case $t in
        x86_64-linux)   c="$WORK/tools/cycc";         e=CYRIUS_RAWPROBE=1 ;;
        x86_64-windows) c="$WORK/tools/cycc";         e=CYRIUS_TARGET_WIN=1 ;;
        x86_64-macos)   c="$WORK/tools/cycc";         e=CYRIUS_MACHO=1 ;;
        x86_64-agnos)   c="$WORK/tools/cycc";         e=CYRIUS_TARGET_AGNOS=1 ;;
        aarch64-linux)  c="$WORK/tools/cycc_aarch64"; e=CYRIUS_RAWPROBE=1 ;;
        aarch64-macos)  c="$WORK/tools/cycc_aarch64"; e=CYRIUS_MACHO_ARM=1 ;;
    esac
    crc=0; ( cd "$U" && env "$e" "$c" < prog.cyr > "$WORK/out.$t" 2> "$WORK/err.$t" ) || crc=$?
    und=$(grep -o "undefined [a-z]* '[^']*'" "$WORK/err.$t" | sort -u | sed "s/.*'\(.*\)'/\1/" | tr '\n' ' ' || true)
    [ -z "$und" ] || fail "axis 1: on $t \`include \"dist/rq.cyr\"\` alone leaves undefined: $und"
    [ "$crc" -eq 0 ] || fail "axis 1: on $t \`include \"dist/rq.cyr\"\` alone does not compile (rc $crc): $(grep -i error "$WORK/err.$t" | head -2)"
done

# ── axis 2: the block IS the sidecar, in order, families expanded ──────────────────────
grep -n '^# Requires (compile-verified; the leaves of dist/rq.deps):$' "$B" >/dev/null \
    || fail "axis 2: no requires block (or a mis-named one) in the bundle: $(sed -n '1,8p' "$B" | tr '\n' '|')"
WANT="$WORK/want"; : > "$WANT"
for l in $(grep -v '^#' "$SC"); do
    if [ -d "$SNAP/$l" ]; then
        for f in $(cd "$SNAP/$l" && ls | grep '\.cyr$' | LC_ALL=C sort); do printf 'include "lib/%s/%s"\n' "$l" "$f" >> "$WANT"; done
    else
        printf 'include "lib/%s.cyr"\n' "$l" >> "$WANT"
    fi
done
sed -n '/^# Requires (compile-verified/,/^$/p' "$B" | grep '^include ' > "$WORK/got" || true
cmp -s "$WANT" "$WORK/got" || fail "axis 2: the block is not the sidecar — want [$(tr '\n' ' ' < "$WANT")], got [$(tr '\n' ' ' < "$WORK/got")]"
grep -qx 'unicode' "$SC" || fail "axis 2 premise: the sidecar lacks the family 'unicode' (D1)"

# ── axis 3: deterministic — --check right after is current ─────────────────────────────
rc=0; OC=$(run_distlib "$P" --check) || rc=$?
[ "$rc" -eq 0 ] || fail "axis 3: distlib --check right after distlib exited $rc: $(echo "$OC" | grep -i 'stale\|error' | head -3)"

# ── axis 4: no leaves, no block ─────────────────────────────────────────────────────────
Q=$(mkproj q 'fn rq_plain(x): i64 {
    return x + 1;
}')
rc=0; OQ=$(run_distlib "$Q") || rc=$?
[ "$rc" -eq 0 ] || fail "axis 4: distlib exited $rc on a leaf-less package: $(echo "$OQ" | head -3)"
grep -q '^# Requires' "$Q/dist/rq.cyr" && fail "axis 4: a leaf-less package's bundle got a requires block"

# ── axis 5: an old-format bundle names the cause under --check ─────────────────────────
sed '/^# Requires (compile-verified/,/^$/d' "$B" > "$WORK/old.cyr" && cp "$WORK/old.cyr" "$B"
grep -q '^# Requires' "$B" && fail "axis 5 premise: could not strip the block"
rc=0; O5=$(run_distlib "$P" --check) || rc=$?
[ "$rc" -ne 0 ] || fail "axis 5: --check passed a bundle with no requires block"
echo "$O5" | grep -q "predates cyrius 6.6.18's requires block — run cyrius distlib --all" \
    || fail "axis 5: --check did not name the cause: $(echo "$O5" | grep -A1 STALE | head -3)"

# ── axis 6: the header comes first, untouched ──────────────────────────────────────────
run_distlib "$P" >/dev/null 2>&1 || true
[ "$(sed -n 1p "$B")" = "# rq.cyr -- bundled distribution" ] && [ "$(sed -n 3p "$B")" = "# Generated by: cyrius distlib" ] \
    && [ "$(sed -n 4p "$B")" = "# Do not edit -- rebuild with: cyrius distlib" ] \
    || fail "axis 6: the header lines moved: $(sed -n '1,5p' "$B" | tr '\n' '|')"

echo "PASS: distlib_bundle_raw_includable (include \"dist/<pkg>.cyr\" alone compiles on 6 targets; the block is the sidecar, families expanded; deterministic; none without leaves; an old bundle names the cause)"
exit 0
