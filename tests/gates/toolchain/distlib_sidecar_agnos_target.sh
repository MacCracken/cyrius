#!/bin/sh
# Gate: the sidecar verify compiles for agnos too, and a partial-target owner is never an
# in-unit declarer that failed there (6.6.18, D3).
#
# ⛔ WHAT IT DID BEFORE. The verify compiled five targets (x86_64 Linux / Windows / macOS,
# aarch64 Linux / macOS) — never agnos, although 10 of the 12 folds (49 ecosystem bundles)
# carry `#ifdef CYRIUS_TARGET_AGNOS` arms. And a name undefined on SOME targets whose declarer
# was already in the unit read as "the target's own gap, nothing to add": mabda includes
# lib/syscalls.cyr, whose peers declare O_RDWR, but on agnos only lib/io.cyr's agnos arm
# defines it — so `io` was never found, and mabda's sidecar (once the [deps] union stopped
# hiding it, D4) failed on agnos with O_RDWR undefined.
#
# Axes
#   a  a module that calls clock_now_ns() ONLY inside `#ifdef CYRIUS_TARGET_AGNOS`, nothing
#      declared: the sidecar names `chrono` (old: no sidecar at all)
#   b  mabda's shape — includes lib/syscalls.cyr and returns O_RDWR: the sidecar names `io`, and
#      the sidecar + bundle compile clean with CYRIUS_TARGET_AGNOS=1 (old: `syscalls` only)
#   c  a NON-symbol failure on agnos ALONE (an agnos-only include of a missing file) is a NAMED
#      WARNING, not a refusal: rc 0, the sidecar is written, the warning names x86_64-agnos.
#      The five other targets stay authoritative, so a producer never built for agnos is not
#      refused at its pin bump (critic #4).
#   d  the anti-vacuous half of (c): the same failure on a NON-agnos target (Windows) still
#      refuses — rc != 0, no sidecar.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
SNAP="$HOMEDIR/versions/$VER/lib"
[ -d "$SNAP" ] || SNAP="$HOMEDIR/lib"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: distlib_sidecar_agnos_target: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_sidecar_agnos_target: $1"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
mkdir -p "$WORK/tools" && cp "$CYRIUS" "$WORK/tools/cyrius" && cp "$CC" "$WORK/tools/cycc" \
    && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$WORK/tools/cycc_aarch64" 2>/dev/null ) \
    && chmod +x "$WORK/tools/cyrius" "$WORK/tools/cycc" "$WORK/tools/cycc_aarch64" \
    || { echo "SKIP: distlib_sidecar_agnos_target: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CYRIUS="$WORK/tools/cyrius"
[ -d "$SNAP" ] || { echo "SKIP: distlib_sidecar_agnos_target: no stdlib snapshot at $SNAP"; exit 77; }

mkproj() {  # mkproj <dir> <body of src/lib.cyr>   — nothing declared
    d="$WORK/$1"; mkdir -p "$d/src"
    printf '[package]\nname = "agp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$VER" > "$d/cyrius.cyml"
    printf '%s\n' "$2" > "$d/src/lib.cyr"
    echo "$d"
}
run_distlib() { ( cd "$1" && CYRIUS_HOME="$HOMEDIR" CYRIUS_RESOLVED=1 "$CYRIUS" distlib 2>&1 ); }
leaves() { grep -v '^#' "$1/dist/agp.deps" 2>/dev/null | tr '\n' ' '; }

# ── axis a ───────────────────────────────────────────────────────────────────────────
A=$(mkproj a 'fn agp_now(): i64 {
#ifdef CYRIUS_TARGET_AGNOS
    return clock_now_ns();
#endif
    return 0;
}')
rc=0; OA=$(run_distlib "$A") || rc=$?
[ "$rc" -eq 0 ] || fail "axis a: distlib exited $rc: $(echo "$OA" | head -3)"
grep -qx 'chrono' "$A/dist/agp.deps" 2>/dev/null || fail "axis a: an agnos-only clock_now_ns() did not record 'chrono': [$(leaves "$A")] — agnos is not a verify target"

# ── axis b ───────────────────────────────────────────────────────────────────────────
B=$(mkproj b 'include "lib/syscalls.cyr"
fn agp_mode(): i64 { return O_RDWR; }')
rc=0; OB=$(run_distlib "$B") || rc=$?
[ "$rc" -eq 0 ] || fail "axis b: distlib exited $rc: $(echo "$OB" | head -3)"
grep -qx 'io' "$B/dist/agp.deps" 2>/dev/null || fail "axis b: mabda's shape did not record 'io' for O_RDWR on agnos: [$(leaves "$B")] — the in-unit syscalls peers short-circuited the owner search"
E="$WORK/entry_b.cyr"; : > "$E"
for l in $(grep -v '^#' "$B/dist/agp.deps"); do printf 'include "lib/%s.cyr"\n' "$l" >> "$E"; done
cat "$B/dist/agp.cyr" >> "$E"
mkdir -p "$WORK/u" && ln -s "$SNAP" "$WORK/u/lib"
crc=0; ( cd "$WORK/u" && CYRIUS_TARGET_AGNOS=1 "$WORK/tools/cycc" < "$E" > "$WORK/out_b" 2> "$WORK/err_b" ) || crc=$?
und=$(grep -o "undefined [a-z]* '[^']*'" "$WORK/err_b" | sort -u | tr '\n' ' ' || true)
[ "$crc" -eq 0 ] && [ -z "$und" ] || fail "axis b: the sidecar + bundle do not compile clean for agnos (rc $crc): $und $(grep -i error "$WORK/err_b" | head -2)"

# ── axis c ───────────────────────────────────────────────────────────────────────────
C=$(mkproj c '#ifdef CYRIUS_TARGET_AGNOS
include "lib/no_such_leaf_agnos_zz.cyr"
#endif
fn agp_c(x): i64 { return strlen(x); }')
rc=0; OC=$(run_distlib "$C") || rc=$?
[ "$rc" -eq 0 ] || fail "axis c: an agnos-ONLY non-symbol failure refused the sidecar (rc $rc) — agnos must warn, not refuse: $(echo "$OC" | grep -i error | head -3)"
[ -f "$C/dist/agp.deps" ] || fail "axis c: no sidecar written: $(echo "$OC" | head -3)"
grep -qx 'string' "$C/dist/agp.deps" || fail "axis c: the five authoritative targets' need 'string' is missing: [$(leaves "$C")]"
echo "$OC" | grep -q 'does not compile for x86_64-agnos' || fail "axis c: the agnos-only failure was not NAMED: $(echo "$OC" | head -4)"

# ── axis d ───────────────────────────────────────────────────────────────────────────
D=$(mkproj d '#ifdef CYRIUS_TARGET_WIN
include "lib/no_such_leaf_win_zz.cyr"
#endif
fn agp_d(x): i64 { return strlen(x); }')
rc=0; OD=$(run_distlib "$D") || rc=$?
[ "$rc" -ne 0 ] || fail "axis d: a Windows-only non-symbol failure exited 0 — only agnos is advisory"
[ -f "$D/dist/agp.deps" ] && fail "axis d: a sidecar was written although x86_64-windows does not compile: [$(leaves "$D")]"
echo "$OD" | grep -q 'does not compile for x86_64-windows' || fail "axis d: the refusal did not name the target: $(echo "$OD" | grep -i error | head -3)"

echo "PASS: distlib_sidecar_agnos_target (agnos is a verify target; an in-unit declarer that failed is not the owner; an agnos-only hard failure warns, any other refuses)"
exit 0
