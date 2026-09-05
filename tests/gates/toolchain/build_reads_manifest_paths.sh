#!/bin/sh
# build_reads_manifest_paths.sh — v6.5.49
#
# `cyrius build` falls back to `[build] src` / `[build] output` in ./cyrius.cyml when the
# corresponding positional argument is not given.
#
# ⛔ WHY: the manifest already declared both paths and the command demanded them again on every
# invocation. Nothing read those keys at all — which is also how cyrius's OWN manifest sat with
# `output = "build/cc5"` (the tracked PRIOR-MAJOR compiler, kept as a break-glass reference)
# unnoticed: an inert key cannot be wrong in a way anyone observes. Making the key live is
# exactly what would have made that value destructive, so it was corrected to `build/cycc` in
# the same release.
#
# THE OVERRIDE LADDER, which is the property this gate pins:
#   cyrius build                 -> manifest src + manifest output
#   cyrius build <src>           -> that src     + manifest output
#   cyrius build <src> <out>     -> both explicit, manifest NOT consulted
#
# ⚠ AXIS 3 IS THE ONE THAT MATTERS. The manifest must be read only for the arguments NOT given.
# Consulting it when both are present would let a stale manifest key override an explicit command
# line — the opposite of what an argument is for, and a silent wrong-output-path at that.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL build_reads_manifest_paths: $1" >&2; exit 1; }

# Build the wrapper from source against build/cycc directly — never the installed `cyrius`,
# which in a scratch dir is the LAST RELEASE and would test the wrong binary.
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" ) 2>/dev/null || fail "could not build cbt/cyrius.cyr"
chmod +x "$W/cyrius"

mkdir -p "$W/p/src" "$W/p/build"
printf '[package]\nname = "g"\nversion = "0.1.0"\n\n[build]\nsrc = "src/main.cyr"\noutput = "build/from_manifest"\n' > "$W/p/cyrius.cyml"
printf 'fn main(): i64 { return 42; }\nvar e = main();\nsyscall(60, e);\n' > "$W/p/src/main.cyr"
printf 'fn main(): i64 { return 7; }\nvar e = main();\nsyscall(60, e);\n'  > "$W/p/src/other.cyr"

run() { ( cd "$W/p" && "$W/cyrius" build "$@" >/dev/null 2>&1 ); }
ec()  { ( cd "$W/p" && "$1" >/dev/null 2>&1 ); echo $?; }

# ── axis 1: no positional args — both paths from the manifest ─────────────────────
rm -f "$W/p/build/from_manifest"
run || fail "axis 1: 'cyrius build' with no arguments failed while the manifest declares [build] src/output"
[ -x "$W/p/build/from_manifest" ] || fail "axis 1: nothing was written to the manifest's output path"
[ "$(ec "$W/p/build/from_manifest")" = "42" ] || fail "axis 1: the manifest's src was not what got compiled"

# ── axis 2: one positional arg — source overrides, output still from the manifest ──
rm -f "$W/p/build/from_manifest"
run src/other.cyr || fail "axis 2: 'cyrius build <src>' failed"
[ "$(ec "$W/p/build/from_manifest")" = "7" ] \
    || fail "axis 2: the command-line source did not override the manifest's"

# ── axis 3: two positional args — the manifest must NOT be consulted ───────────────
rm -f "$W/p/build/from_manifest" "$W/p/build/explicit"
run src/main.cyr build/explicit || fail "axis 3: the fully-explicit form failed"
[ -x "$W/p/build/explicit" ] || fail "axis 3: nothing was written to the explicit output path"
[ -e "$W/p/build/from_manifest" ] \
    && fail "axis 3: the manifest output path was ALSO written — an explicit argument must win outright, not merge with the manifest"

# ── axis 4: no manifest keys — usage, and a NON-ZERO exit ─────────────────────────
mkdir -p "$W/q"; printf '[package]\nname = "q"\n' > "$W/q/cyrius.cyml"
out=$( cd "$W/q" && "$W/cyrius" build 2>&1 ) && fail "axis 4: 'cyrius build' with nothing to build exited 0"
printf '%s' "$out" | grep -q "may be omitted when ./cyrius.cyml declares" \
    || fail "axis 4: the usage text does not tell the user the arguments are optional, so the feature is undiscoverable"

# ⚠ MUTATE THIS GATE AT THE SOURCE, NOT THE BINARY. It builds its own wrapper from
# cbt/cyrius.cyr in the working tree (see the fixture note above), so swapping build/cyrius
# for an older one changes NOTHING and every axis stays green — measured 2026-09-04, a
# pre-v6.5.51 build/cyrius passes all six. Reverting cbt/cyrius.cyr turns axis 5 RED.
# Same trap as tests/gates/diagnostics/sys_shadow_names_consequence.sh.
#
# ── axis 5: ⭐ THE ECOSYSTEM'S ACTUAL KEY IS `entry`, NOT `src` ────────────────────
# v6.5.49 shipped this fallback reading ONLY `src` — the key THIS repo's manifest happens
# to use — and axes 1-4 above passed because they were written against that same key. So
# the gate agreed with the implementation while the feature was INERT for almost every
# consumer: measured across ~/Repos on 2026-09-04, 120 of 125 cyrius.cyml files declare
# `entry` and only 5 declare `src`. A pre-v6.5.51 CLI given an `entry=` manifest prints
# the usage text and exits 1. Both keys are accepted now, `entry` first.
# ⚠ Do not "simplify" this axis away by making the fixture use one key. Testing the key
# the implementation reads is exactly the mistake that let this ship inert.
mkdir -p "$W/e/src" "$W/e/build"
printf '[package]\nname = "e"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/from_entry"\n' > "$W/e/cyrius.cyml"
printf 'fn main(): i64 { return 42; }\nvar r = main();\n' > "$W/e/src/main.cyr"
( cd "$W/e" && "$W/cyrius" build > /dev/null 2>&1 ) \
    || fail "axis 5: 'cyrius build' failed on a manifest using the ecosystem's [build] entry key"
[ -x "$W/e/build/from_entry" ] \
    || fail "axis 5: [build] entry was not read — the fallback still only understands src, so it is inert for 120 of 125 ecosystem manifests"
[ "$(ec "$W/e/build/from_entry")" = "42" ] || fail "axis 5: [build] entry resolved to the wrong source"

# ── axis 6: `entry` WINS when a manifest carries both ─────────────────────────────
mkdir -p "$W/b/src" "$W/b/build"
printf '[package]\nname = "b"\n\n[build]\nentry = "src/win.cyr"\nsrc = "src/lose.cyr"\noutput = "build/both"\n' > "$W/b/cyrius.cyml"
printf 'fn main(): i64 { return 42; }\nvar r = main();\n' > "$W/b/src/win.cyr"
printf 'fn main(): i64 { return 7; }\nvar r = main();\n' > "$W/b/src/lose.cyr"
( cd "$W/b" && "$W/cyrius" build > /dev/null 2>&1 ) || fail "axis 6: build failed on a manifest declaring both keys"
[ "$(ec "$W/b/build/both")" = "42" ] \
    || fail "axis 6: src beat entry — the ecosystem convention must win when both are present"

echo "PASS build_reads_manifest_paths (entry + src fallback for both paths, per-argument override, explicit args win outright, honest usage + non-zero exit)"
