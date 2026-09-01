#!/bin/sh
# Gate: manifest key scans read DECLARATIONS, not prose (v6.5.37, A5).
#
# ⛔ THE `stdlib` HOLE IS THE FOURTH OCCURRENCE OF THE COMMENT-PROSE CLASS, AND IT WAS IN THE
# SHARED HELPER INTRODUCED TO END THE CLASS. v6.5.17 fixed it in `cmd_deps` (bayan's
# `[package] description` saying "foldable into stdlib per the sandhi pattern") and created
# `_toml_key_at`; v6.5.30 fixed the un-swept second copy (niyama, same phrase). Both fixes
# relied on `_toml_key_at`'s comment guard — which walks only the LEADING whitespace of a
# line and breaks at the first non-space, so a `#` that opens a comment MID-LINE was never
# seen. Reproduced at 6.5.36 with one line of ordinary prose:
#
#     modules = ["src/lib.cyr"]   # TODO: split; stdlib = ["math"] will move here
#
# -> the sidecar contained exactly `math`, and `cyrius deps` vendored math.cyr and NOTHING
# ELSE, silently, exit 0. Seven declared leaves reduced to one wrong one, in BOTH directions
# at once, because producer and consumer share the helper.
#
# ⚠ The decoy does not have to mention `stdlib` — the scan locks onto any array literal after
# the `#`. Axis 1's decoy is deliberately ordinary developer prose, not a crafted attack.
#
# ⛔ THE `name` SCAN HAD NO GUARDS AT ALL, and it decides the output FILENAME: no left
# boundary, no comment guard, no quote guard, no `[package]` anchor, and no
# `_dep_reject_unsafe_name` (which ran only on the --modular path). Three measured hijacks,
# axes 2-4: a comment, a `display_name` tail, and `../victim/pwned` — the last writing BOTH
# files outside dist/ before any message appeared.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
VER=$(cat "$ROOT/VERSION")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: manifest_scan_decoys: $1"; exit 1; }
# CYRIUS_RESOLVED=1: a fixture pinning another version would re-exec a binary built before
# these fixes and the gate would silently test OLD code.
run() { ( cd "$1" && CYRIUS_RESOLVED=1 "$CYRIUS" distlib 2>&1 ); }

mk() {  # mk <dir> <manifest-body>
    d="$WORK/$1"; mkdir -p "$d/src"
    echo 'fn probe_entry(): i64 { return 1; }' > "$d/src/lib.cyr"
    printf '%s\n' "$2" > "$d/cyrius.cyml"
    echo "$d"
}

# ── axis 1: an inline-comment `stdlib = [...]` must NOT win ─────────────────────────
A=$(mk a "[package]
name = \"probe\"
version = \"0.1.0\"
cyrius = \"$VER\"

[lib]
modules = [\"src/lib.cyr\"]   # TODO: split; stdlib = [\"math\"] will move here

[deps]
stdlib = [\"string\", \"fmt\", \"alloc\", \"io\", \"vec\", \"str\", \"syscalls\"]")
run "$A" >/dev/null 2>&1 || true
[ -f "$A/dist/probe.deps" ] || fail "axis 1: no sidecar written"
N=$(grep -c '^[a-z]' "$A/dist/probe.deps" || true)
[ "$N" -ge 7 ] || fail "axis 1: sidecar has $N leaves (expected >= 7) — the inline-comment decoy won the scan"
grep -qx 'string' "$A/dist/probe.deps" || fail "axis 1: the real [deps] stdlib was not used"

# ── axis 2: a commented `name = ...` must NOT name the bundle ───────────────────────
B=$(mk b "# The package name = \"the crate identifier\"
[package]
name = \"realprobe\"
version = \"0.1.0\"
cyrius = \"$VER\"
[lib]
modules = [\"src/lib.cyr\"]
[deps]
stdlib = [\"alloc\"]")
run "$B" >/dev/null 2>&1 || true
[ -f "$B/dist/realprobe.cyr" ] || fail "axis 2: dist/realprobe.cyr missing — a comment named the bundle ($(ls "$B/dist" 2>/dev/null | tr '\n' ' '))"

# ── axis 3: `display_name` must NOT match on its `name` tail ────────────────────────
C=$(mk c "[package]
display_name = \"WRONG\"
name = \"realprobe\"
version = \"0.1.0\"
cyrius = \"$VER\"
[lib]
modules = [\"src/lib.cyr\"]
[deps]
stdlib = [\"alloc\"]")
run "$C" >/dev/null 2>&1 || true
[ -f "$C/dist/realprobe.cyr" ] || fail "axis 3: dist/realprobe.cyr missing — 'display_name' matched ($(ls "$C/dist" 2>/dev/null | tr '\n' ' '))"
[ -f "$C/dist/WRONG.cyr" ] && fail "axis 3: dist/WRONG.cyr was written from display_name"

# ── axis 4: a traversal name is refused, and writes NOTHING outside dist/ ───────────
D=$(mk d "[package]
name = \"../victim/pwned\"
version = \"0.1.0\"
cyrius = \"$VER\"
[lib]
modules = [\"src/lib.cyr\"]
[deps]
stdlib = [\"alloc\"]")
run "$D" >/dev/null 2>&1 || true
ESCAPED=$(find "$WORK/d" -name 'pwned*' 2>/dev/null | wc -l | tr -d ' ')
[ "$ESCAPED" -eq 0 ] || fail "axis 4: $ESCAPED file(s) written outside dist/ from a traversal name"

# ── axis 5: ANTI-VACUOUS — an ordinary manifest still works ─────────────────────────
# Without this, refusing everything passes axes 1-4.
E=$(mk e "[package]
name = \"cleanprobe\"
version = \"0.1.0\"
cyrius = \"$VER\"
[lib]
modules = [\"src/lib.cyr\"]
[deps]
stdlib = [\"alloc\", \"io\"]")
run "$E" >/dev/null 2>&1 || true
[ -f "$E/dist/cleanprobe.cyr" ] || fail "axis 5: an ordinary manifest produced no bundle — the guards reject valid input"
[ -f "$E/dist/cleanprobe.deps" ] || fail "axis 5: an ordinary manifest produced no sidecar"
grep -qx 'alloc' "$E/dist/cleanprobe.deps" || fail "axis 5: ordinary sidecar lost its declared leaves"

echo "PASS: manifest_scan_decoys (inline-comment stdlib, comment name, display_name, traversal, ordinary manifest)"
