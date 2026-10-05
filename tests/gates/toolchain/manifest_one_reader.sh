#!/bin/sh
# manifest_one_reader.sh — 6.6.17 (P1 item 2). Every [build] / [package] / [sections] read in the
# CLI goes through ONE reader (cbt/manifest.cyr) that reads the WHOLE manifest and parses values
# as TOML.
#
# THE DEFECTS (measured on 6.6.16): each key family had its own capped scanner — [build] and every
# [package] key at 32,767 bytes, `_auto_deps` at 65,535, publish at 4,095 — so a `[build]` at byte
# 44,000 made `cyrius build` print its usage and exit 1 with the keys right there; a single-quoted
# value read as absent; a line inside a multi-line array that began with `[` ended the section; a
# `[build]` written in the CYML body (prose after `---`) was read as configuration; `cyrius
# package` read the manifest and used nothing from it (always src/main.cyr -> build/main).
#
# AXES (each builds and RUNS what the manifest declares, so the expected value is the program's
# exit code, not the reader's say-so)
#   1. [build] starting past byte 65,536 — a bare `cyrius build` builds it.
#   2. a [build] key AFTER a multi-line array whose inner line starts with `[`.
#   3. TOML values: a literal string ('…', no escapes) and a basic string with a \u escape.
#   4. a [build] in the CYML body is NOT configuration (usage, non-zero exit).
#   5. [package] version past byte 65,536 reaches the program as CYRIUS_PKG_VERSION.
#   6. `cyrius package` compiles [build] entry into [build] output.
#   7. a manifest past 16 MiB is refused BY NAME (non-zero exit), not truncated.
#   8. STATIC: no fixed-cap read of a manifest path is left in cbt/ (self-tested on the old body).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: manifest_one_reader: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: manifest_one_reader: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=1; }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: manifest_one_reader: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
# The tree's compiler beside the CLI, so `cyrius build` in a scratch project compiles with it.
mkdir -p "$W/home/bin"; cp "$CC" "$W/home/bin/cycc"
cli() { ( cd "$1" && shift && CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ); }
pad() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "pad_%06d = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n", i }'; }
mkproj() { mkdir -p "$W/$1/src"; printf 'fn main(): i64 { return %s; }\nvar r = main();\nsyscall(60, r);\n' "$2" > "$W/$1/src/main.cyr"; }
runs() { [ -x "$1" ] || { echo none; return; }; rc=0; "$1" > /dev/null 2>&1 || rc=$?; echo "$rc"; }

# ── axis 1: [build] past 64 KiB ─────────────────────────────────────────────────────────
mkproj a1 41
{ printf '[package]\nname = "a1"\n\n[notes]\n'; pad 1800; printf '\n[build]\nentry = "src/main.cyr"\noutput = "build/late"\n'; } > "$W/a1/cyrius.cyml"
off=$(awk '/^\[build\]$/ { print o; exit } { o += length($0) + 1 }' "$W/a1/cyrius.cyml")
[ "$off" -gt 65536 ] || { echo "FAIL: manifest_one_reader: axis-1 fixture puts [build] at byte $off (must be past 65,536)"; exit 1; }
cli "$W/a1" build > "$W/a1.out" 2>&1
[ "$(runs "$W/a1/build/late")" = 41 ] && echo "  ok axis 1: a [build] at byte $off is read (bare cyrius build built and ran it)" \
    || { fail "axis 1: a [build] at byte $off was not read:"; tail -3 "$W/a1.out" | sed 's/^/      /'; }

# ── axis 2: a key after a nested multi-line array ───────────────────────────────────────
mkproj a2 42
printf '[package]\nname = "a2"\n\n[build]\nmatrix = [\n    ["x86_64", "linux"],\n    ["aarch64", "macos"],\n]\nentry = "src/main.cyr"\noutput = "build/nested"\n' > "$W/a2/cyrius.cyml"
cli "$W/a2" build > "$W/a2.out" 2>&1
[ "$(runs "$W/a2/build/nested")" = 42 ] && echo "  ok axis 2: a key after a multi-line array whose inner line starts with [ is read" \
    || { fail "axis 2: the line inside the array was taken for a section header:"; tail -3 "$W/a2.out" | sed 's/^/      /'; }

# ── axis 3: literal and escaped strings ─────────────────────────────────────────────────
mkproj a3 43
printf "[build]\nentry = 'src/main.cyr'\noutput = \"build/esc\\\\u0041\"\n" > "$W/a3/cyrius.cyml"
grep -q "^entry = 'src/main.cyr'\$" "$W/a3/cyrius.cyml" && grep -q '^output = "build/esc\\u0041"$' "$W/a3/cyrius.cyml" \
    || { echo "FAIL: manifest_one_reader: axis-3 fixture is not what it means to be:"; cat "$W/a3/cyrius.cyml"; exit 1; }
cli "$W/a3" build > "$W/a3.out" 2>&1
[ "$(runs "$W/a3/build/escA")" = 43 ] && echo "  ok axis 3: entry = '…' (a TOML literal string) and \\u0041 in a basic string read as TOML" \
    || { fail "axis 3: literal / escaped string not read as TOML (built: $(ls "$W/a3/build" 2>/dev/null | tr '\n' ' ')):"; tail -3 "$W/a3.out" | sed 's/^/      /'; }

# ── axis 4: the CYML body is prose ──────────────────────────────────────────────────────
mkproj a4 44
printf '[package]\nname = "a4"\n---\n\n# Notes\n\n[build]\nentry = "src/main.cyr"\noutput = "build/from_body"\n' > "$W/a4/cyrius.cyml"
rc=0; cli "$W/a4" build > "$W/a4.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$W/a4/build/from_body" ]; then echo "  ok axis 4: a [build] in the CYML body is not configuration (rc $rc, nothing built)"
else fail "axis 4: the CYML body was read as configuration (rc $rc)"; fi

# ── axis 5: [package] version past 64 KiB -> CYRIUS_PKG_VERSION ─────────────────────────
mkdir -p "$W/a5/src"
printf 'syscall(1, 1, CYRIUS_PKG_VERSION, 5);\nsyscall(60, 0);\n' > "$W/a5/src/main.cyr"
{ printf '[notes]\n'; pad 1800; printf '\n[package]\nname = "a5"\nversion = "4.5.6"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/ver"\n'; } > "$W/a5/cyrius.cyml"
cli "$W/a5" build > "$W/a5.out" 2>&1
got=$( [ -x "$W/a5/build/ver" ] && "$W/a5/build/ver" 2>/dev/null )
[ "$got" = "4.5.6" ] && echo "  ok axis 5: a [package] version past byte 65,536 reaches the program as CYRIUS_PKG_VERSION" \
    || { fail "axis 5: CYRIUS_PKG_VERSION is '$got', expected 4.5.6:"; tail -3 "$W/a5.out" | sed 's/^/      /'; }

# ── axis 6: cyrius package builds what [build] declares ─────────────────────────────────
mkdir -p "$W/a6/programs"
printf 'fn main(): i64 { return 46; }\nvar r = main();\nsyscall(60, r);\n' > "$W/a6/programs/app.cyr"
printf '[package]\nname = "a6"\n\n[build]\nentry = "programs/app.cyr"\noutput = "build/app"\n' > "$W/a6/cyrius.cyml"
cli "$W/a6" package > "$W/a6.out" 2>&1
[ "$(runs "$W/a6/build/app")" = 46 ] && echo "  ok axis 6: cyrius package compiled [build] entry into [build] output" \
    || { fail "axis 6: cyrius package ignored [build] (built: $(ls "$W/a6/build" 2>/dev/null | tr '\n' ' ')):"; tail -3 "$W/a6.out" | sed 's/^/      /'; }

# ── axis 7: past 16 MiB -> refused by name ──────────────────────────────────────────────
mkproj a7 47
{ printf '[build]\nentry = "src/main.cyr"\noutput = "build/huge"\n'; head -c 16777216 /dev/zero | tr '\0' '#'; } > "$W/a7/cyrius.cyml"
rc=0; cli "$W/a7" build > "$W/a7.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'larger than 16 MiB' "$W/a7.out" && [ ! -e "$W/a7/build/huge" ]; then
    echo "  ok axis 7: a $(wc -c < "$W/a7/cyrius.cyml" | tr -d ' ')-byte manifest is refused by name (rc $rc)"
else fail "axis 7: a manifest past 16 MiB was not refused by name (rc $rc): $(head -2 "$W/a7.out" | tr '\n' ' ')"; fi
rm -f "$W/a7/cyrius.cyml"

# ── axis 8: STATIC — no fixed-cap manifest read left in cbt/ ────────────────────────────
capped() { grep -nE 'file_read_all\((("cyrius\.(cyml|toml)")|mf|_manifest|_ad_manifest|_pkg_manifest|_tm)[ ]*,' "$@"; }
printf '    var buf = alloc(32768);\n    var n = file_read_all("cyrius.cyml", buf, 32767);\n    var n2 = file_read_all(_ad_manifest, buf, 65535);\n' > "$W/old.cyr"
[ "$(capped "$W/old.cyr" | wc -l | tr -d ' ')" = 2 ] || fail "axis 8 self-test: the detector does not see the two pre-6.6.17 reads"
left=$(capped cbt/*.cyr || true)
[ -z "$left" ] && echo "  ok axis 8: no fixed-cap read of a manifest path in cbt/ (detector self-tested)" \
    || fail "axis 8: a manifest is still read through a fixed cap: $left"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: manifest_one_reader (whole manifest, TOML values, CYML body, package, 16 MiB refusal)"
