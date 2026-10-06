#!/bin/sh
# Gate: the sidecar verify attributes symbols in a stdlib FAMILY directory (6.6.18, D1).
#
# ⛔ WHAT IT DID BEFORE. The verify's snapshot index (`_distlib_snap_cache`) read only the
# depth-0 `lib/*.cyr` files. A family directory such as `lib/unicode/` was never indexed, so
# `unicode_category` read as "not a stdlib symbol — the consumer's problem", the fixpoint
# `continue`d past it, and the sidecar was published SHORT at rc 0. Measured at a2c60583 on
# this gate's fixture: no `dist/famprobe.deps` at all, and the bundle left `unicode_category`
# undefined on every target. niyama's sidecar carried `unicode` only because its [deps] stdlib
# declared it and the v6.5.10 union copied that in — remove the union (P4, D4) and niyama
# published a sidecar that fails on all five targets.
#
# ⭐ THE OWNER IS THE FAMILY NAME. `unicode` is what a producer declares and what `cyrius deps`
# expands (members in `_dep_name_cmp` order). A member-file owner (`unicode/categories`, or a
# `_categories_data` peer) would not compile: members read their `_*_data` siblings.
#
# Axes
#   1  a module that calls unicode_category() with no include and no [deps] stdlib entry gets
#      `unicode` in its sidecar
#   2  no member file is ever an owner (no `/`, no `_*_data` leaf)
#   3  the sidecar's leaves (family expanded, sorted) + the bundle compile with 0 undefined on
#      every target the toolchain ships: x86_64 Linux / Windows / macOS / agnos, aarch64
#      Linux / macOS
# MUTATION: `_distlib_snap_cache`'s family arm removed -> RED on axes 1 and 3 (measured: no
# sidecar written, unicode_category undefined on all six targets).
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
SNAP="$HOMEDIR/versions/$VER/lib"
[ -d "$SNAP" ] || SNAP="$HOMEDIR/lib"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: distlib_sidecar_family_leaf: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_sidecar_family_leaf: $1"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
mkdir -p "$WORK/tools" && cp "$CYRIUS" "$WORK/tools/cyrius" && cp "$CC" "$WORK/tools/cycc" \
    && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$WORK/tools/cycc_aarch64" 2>/dev/null ) \
    && chmod +x "$WORK/tools/cyrius" "$WORK/tools/cycc" "$WORK/tools/cycc_aarch64" \
    || { echo "SKIP: distlib_sidecar_family_leaf: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CYRIUS="$WORK/tools/cyrius"
[ -d "$SNAP" ] || { echo "SKIP: distlib_sidecar_family_leaf: no stdlib snapshot at $SNAP"; exit 77; }
[ -d "$SNAP/unicode" ] || fail "premise: the snapshot has no lib/unicode/ family — re-derive the fixture"

P="$WORK/famprobe"; mkdir -p "$P/src"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "famprobe"
version = "0.1.0"
cyrius = "$VER"

[lib]
modules = ["src/lib.cyr"]
EOF
printf 'fn famprobe_cat(cp): i64 {\n    return unicode_category(cp);\n}\n' > "$P/src/lib.cyr"
rc=0; OUT=$( cd "$P" && CYRIUS_HOME="$HOMEDIR" CYRIUS_RESOLVED=1 "$CYRIUS" distlib 2>&1 ) || rc=$?
[ "$rc" -eq 0 ] || fail "distlib exited $rc: $(echo "$OUT" | head -5)"
SC="$P/dist/famprobe.deps"

# ── axis 1 ────────────────────────────────────────────────────────────────────────────
[ -f "$SC" ] || fail "axis 1: no sidecar written — unicode_category was read as 'not stdlib' (the depth-0 index)"
grep -qx 'unicode' "$SC" || fail "axis 1: the sidecar does not name 'unicode': [$(grep -v '^#' "$SC" | tr '\n' ' ')]"

# ── axis 2 ────────────────────────────────────────────────────────────────────────────
if grep -v '^#' "$SC" | grep -qE '/|_data$|^_'; then
    fail "axis 2: a family MEMBER was recorded as an owner: [$(grep -v '^#' "$SC" | tr '\n' ' ')]"
fi

# ── axis 3: the sidecar is SUFFICIENT on every target ────────────────────────────────
E="$WORK/entry.cyr"; : > "$E"
for l in $(grep -v '^#' "$SC"); do
    if [ -d "$SNAP/$l" ]; then
        for f in $(cd "$SNAP/$l" && ls | grep '\.cyr$' | LC_ALL=C sort); do printf 'include "lib/%s/%s"\n' "$l" "$f" >> "$E"; done
    else
        printf 'include "lib/%s.cyr"\n' "$l" >> "$E"
    fi
done
cat "$P/dist/famprobe.cyr" >> "$E"
mkdir -p "$WORK/u" && ln -s "$SNAP" "$WORK/u/lib"
for t in x86_64-linux x86_64-windows x86_64-macos x86_64-agnos aarch64-linux aarch64-macos; do
    case $t in
        x86_64-linux)   c="$WORK/tools/cycc";         e=CYRIUS_FAMPROBE=1 ;;
        x86_64-windows) c="$WORK/tools/cycc";         e=CYRIUS_TARGET_WIN=1 ;;
        x86_64-macos)   c="$WORK/tools/cycc";         e=CYRIUS_MACHO=1 ;;
        x86_64-agnos)   c="$WORK/tools/cycc";         e=CYRIUS_TARGET_AGNOS=1 ;;
        aarch64-linux)  c="$WORK/tools/cycc_aarch64"; e=CYRIUS_FAMPROBE=1 ;;
        aarch64-macos)  c="$WORK/tools/cycc_aarch64"; e=CYRIUS_MACHO_ARM=1 ;;
    esac
    crc=0; ( cd "$WORK/u" && env "$e" "$c" < "$E" > "$WORK/out.$t" 2> "$WORK/err.$t" ) || crc=$?
    und=$(grep -o "undefined [a-z]* '[^']*'" "$WORK/err.$t" | sort -u | sed "s/.*'\(.*\)'/\1/" | tr '\n' ' ' || true)
    [ -z "$und" ] || fail "axis 3: on $t the sidecar's leaves + the bundle leave undefined: $und"
    [ "$crc" -eq 0 ] || fail "axis 3: on $t the sidecar's leaves + the bundle do not compile (rc $crc): $(grep -i error "$WORK/err.$t" | head -3)"
done

echo "PASS: distlib_sidecar_family_leaf (a family symbol is attributed to its family, never a member; the sidecar + bundle compile on 6 targets)"
exit 0
