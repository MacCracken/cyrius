#!/bin/sh
# build_print_config.sh — 6.6.17 (P1 item 3). `cyrius build --print-config` resolves the whole
# configuration, prints each value with its origin — argument, environment, manifest or default —
# and exits 0 WITHOUT building or resolving deps.
#
# WHY: the precedence ladder had to be inferred from side effects (which file got written). A gate
# can now assert origins directly. And the reader is checked against MANIFESTS CONSUMERS WROTE
# (tests/fixtures/manifest/consumers/, verbatim copies), with the expected value of each key taken
# from the fixture by an independent awk parse — never from the reader's own idea of the spelling
# (the v6.5.49 slice shipped inert because its fixture used the key the code read).
#
# AXES
#   1. every consumer fixture: build.entry / build.output / package.name equal the fixture's own
#      values, origin `manifest` naming the key actually written (`[build] src` for hisab), and
#      no key a consumer writes is warned "not a known key" (6.6.17 review: `src` was).
#   2. operands win: `--print-config a.cyr out` reports both as `argument`, over the manifest.
#   3. no manifest: entry / output are `(unset)  (default)`; strict false; defines [].
#   3b. package.version is what the build gets: `${file:VERSION}` expanded, `(unset)` when the
#      file is missing (it printed the raw template while the build had no CYRIUS_PKG_VERSION).
#   4. `--strict` and `-D X` are `argument` (strict marked held: no effect since 6.3.2).
#   5. it builds nothing and resolves nothing: a project with [deps] stdlib gets no lib/ and no
#      build/, exit 0.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build_print_config: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: build_print_config: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: build_print_config: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
mkdir -p "$W/home/bin"; cp "$CC" "$W/home/bin/cycc"
# CYRIUS_RESOLVED=1: the consumer fixtures pin older toolchains; without it the CLI re-execs one.
pc() { d=$1; shift; ( cd "$d" && env -u CYRIUS_DCE -u CYRIUS_STRICT -u CYRIUS_DEFINES CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" build --print-config "$@" ); }
has() { grep -qF -- "$2" "$1" || { fail "$3: no line '$2' in:"; sed 's/^/      /' "$1"; }; }
# the fixture's own value of [section] key, by awk (the header only; first occurrence)
fx() { awk -v S="[$2]" -v K="$3" '/^---/ { exit } /^[ \t]*\[/ { s = $0; sub(/[ \t]*#.*/, "", s); in_s = (s == S); next }
    in_s { l = $0; if (match(l, "^[ \t]*" K "[ \t]*=[ \t]*\"")) { v = substr(l, RLENGTH + 1); sub(/".*/, "", v); print v; exit } }' "$1"; }

# ── axis 1: what consumers wrote ────────────────────────────────────────────────────────
n=0
for f in tests/fixtures/manifest/consumers/*.cyml; do
    nm=$(basename "$f" .cyml)
    mkdir -p "$W/c/$nm"; cp "$f" "$W/c/$nm/cyrius.cyml"
    rc=0; pc "$W/c/$nm" > "$W/c/$nm.out" 2>&1 || rc=$?
    [ "$rc" = 0 ] || { fail "axis 1 ($nm): --print-config exited $rc"; continue; }
    ek=entry; ev=$(fx "$f" build entry)
    [ -n "$ev" ] || { ek=src; ev=$(fx "$f" build src); }
    ov=$(fx "$f" build output); pn=$(fx "$f" package name)
    [ -n "$ev" ] && [ -n "$ov" ] && [ -n "$pn" ] || { fail "axis 1 ($nm): the fixture parse found nothing — the expected values are empty"; continue; }
    has "$W/c/$nm.out" "  build.entry = \"$ev\"  (manifest: [build] $ek)" "axis 1 ($nm)"
    has "$W/c/$nm.out" "  build.output = \"$ov\"  (manifest: [build] output)" "axis 1 ($nm)"
    has "$W/c/$nm.out" "  package.name = \"$pn\"  (manifest: [package] name)" "axis 1 ($nm)"
    # a key consumers write is never "unknown" — hisab's `src` is entry's declared synonym
    grep -q 'is not a known key' "$W/c/$nm.out" && fail "axis 1 ($nm): a key this consumer writes was warned as unknown: $(grep 'is not a known key' "$W/c/$nm.out" | head -1)"
    n=$((n + 1))
done
[ "$n" -ge 6 ] || fail "axis 1: only $n consumer fixtures checked (floor 6)"
[ "$FAIL" = 0 ] && echo "  ok axis 1: $n verbatim consumer manifests — entry (incl. the src synonym), output, name read with their origin"

# ── axis 2: operands are arguments, and they win ────────────────────────────────────────
x=$FAIL
pc "$W/c/kashi" other.cyr build/other > "$W/a2.out" 2>&1 || true
has "$W/a2.out" '  build.entry = "other.cyr"  (argument: <source>)' "axis 2"
has "$W/a2.out" '  build.output = "build/other"  (argument: <output>)' "axis 2"
[ "$FAIL" = "$x" ] && echo "  ok axis 2: <source> / <output> beat the manifest and say so"

# ── axis 3: defaults ────────────────────────────────────────────────────────────────────
x=$FAIL
mkdir -p "$W/none"
pc "$W/none" > "$W/a3.out" 2>&1 || true
has "$W/a3.out" '  manifest: (none)' "axis 3"
has "$W/a3.out" '  build.entry = (unset)  (default)' "axis 3"
has "$W/a3.out" '  build.output = (unset)  (default)' "axis 3"
has "$W/a3.out" '  build.strict = false  (default)  [held: no effect since 6.3.2]' "axis 3"
has "$W/a3.out" '  build.defines = []  (default)' "axis 3"
[ "$FAIL" = "$x" ] && echo "  ok axis 3: with no manifest every key reports its default"

# ── axis 3b: package.version is what the BUILD gets ────────────────────────────────────
x=$FAIL
mkdir -p "$W/v"
printf '[package]\nname = "v"\nversion = "${file:VERSION}"\n' > "$W/v/cyrius.cyml"
pc "$W/v" > "$W/a3b.out" 2>&1 || true
has "$W/a3b.out" '  package.version = (unset)  (manifest: [package] version ${file:VERSION} does not resolve; the build gets no CYRIUS_PKG_VERSION)' "axis 3b (VERSION missing)"
printf '7.8.9\n' > "$W/v/VERSION"
pc "$W/v" > "$W/a3b.out" 2>&1 || true
has "$W/a3b.out" '  package.version = "7.8.9"  (manifest: [package] version)' "axis 3b (VERSION present)"
[ "$FAIL" = "$x" ] && echo "  ok axis 3b: package.version prints the expanded \${file:VERSION}, and (unset) when it does not resolve"

# ── axis 4: flags are arguments ─────────────────────────────────────────────────────────
x=$FAIL
pc "$W/none" --strict -D ALPHA -DBETA > "$W/a4.out" 2>&1 || true
has "$W/a4.out" '  build.strict = true  (argument: --strict)  [held: no effect since 6.3.2]' "axis 4"
has "$W/a4.out" '  build.defines = ["ALPHA", "BETA"]  (argument: -D)' "axis 4"
[ "$FAIL" = "$x" ] && echo "  ok axis 4: --strict and -D report as arguments"

# ── axis 5: builds nothing, resolves nothing ────────────────────────────────────────────
x=$FAIL
mkdir -p "$W/d/src"
printf '[package]\nname = "d"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/d"\n\n[deps]\nstdlib = ["string", "alloc"]\n' > "$W/d/cyrius.cyml"
printf 'fn main(): i64 { return 0; }\nvar r = main();\n' > "$W/d/src/main.cyr"
rc=0; pc "$W/d" > "$W/a5.out" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "axis 5: --print-config exited $rc"
[ -e "$W/d/lib" ] && fail "axis 5: --print-config resolved deps (lib/ was written)"
[ -e "$W/d/build" ] && fail "axis 5: --print-config built something (build/ exists)"
[ "$FAIL" = "$x" ] && echo "  ok axis 5: --print-config exits 0 and writes neither lib/ nor build/"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: build_print_config (consumer manifests, argument > manifest > default, no side effects)"
