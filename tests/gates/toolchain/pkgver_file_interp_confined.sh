#!/bin/sh
# pkgver_file_interp_confined.sh — 6.6.20 (SEC-04, CVE-99). `[package] version = "${file:PATH}"`
# puts PATH's contents into the binary (`#@pkgver` -> CYRIUS_PKG_VERSION) and onto
# `cyrius build --print-config`, so PATH is checked by the [embed] rules (`_proj_path_bad`) and
# read through the same link-free open (`_proj_read`), and the VALUE holds no control byte.
#
# WHY: `_dep_expand_file_interp` was `file_exists` + `file_read_all(path, 511)`. Measured on the
# merged 6.6.20 tree (2ac318b0): `${file:../outside.txt}`, `${file:/abs/outside.txt}` and the
# ordinary `${file:VERSION}` over a committed `VERSION -> ../outside.txt` link each built a binary
# PRINTING the outside file; `${file:.git/config}` wrote the file's lines after `#@pkgver` as
# SOURCE, and the compiler echoed them (`[http "https://github.com/"]`, the job token's line) —
# exactly the shapes 6.6.19 refuses for [embed]. A literal `version = "1.0\nsyscall(...)"` ran its
# second line. The ./VERSION fallback (`_project_version`: distlib's `# Version:` stamp, `cyrius
# package`) read the file raw and had the same reach.
#
# AXES (each refusal: the verb exits 1, NAMES the value, builds nothing, and the outside secret is
# in no output)
#   1. paths: `../x`, absolute, a committed `VERSION -> ../x` link, `lnk/VERSION` through a linked
#      directory, `.git/config`, `.GIT/config`, a backslash, a `:`, a second hard link, a
#      directory, a FIFO (refused, no hang), a 600-byte file — under `cyrius build`, and the `../x`
#      and link rows under `--print-config` (which printed the secret) and `cyrius test`.
#   2. values: a two-line file (its second line a `syscall` that prints INJECTED), a literal with a
#      `\n` escape (the same payload), a literal with `\u001b` — refused, INJECTED never printed,
#      and the refusal shows the control byte escaped (\x0a), never raw.
#   3. the ./VERSION fallback: no `[package] version`, `VERSION -> ../x` -> `cyrius package` and
#      `cyrius distlib` are refused by name; the secret is not printed and no bundle carries the
#      file (its second line used to land below `# Version:` as bundle source).
#   4. positive: `${file:VERSION}` (regular file, trailing newline) and a literal build and the
#      binary prints the version; `${file:missing}` builds with the constant ABSENT (as before:
#      absent beats wrong) and `--print-config` says it does not resolve; `cyrius package` prints
#      the MANIFEST's version (it printed ./VERSION read raw, or "unknown").
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=pkgver_file_interp_confined
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME: no compiler at $CC"; exit 77; }
command -v mkfifo >/dev/null 2>&1 || { echo "SKIP: $NAME: no mkfifo"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: $NAME: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
mkdir -p "$W/home/bin"; cp "$CC" "$W/home/bin/cycc"

SECRET=SECRET-OUTSIDE-PROJECT-7f3a
printf '%s\n' "$SECRET" > "$W/outside.txt"
P="$W/p"
mkdir -p "$P/src" "$P/.git" "$P/.GIT" "$P/real" "$P/d"
# The entry lives under src/ so the build materializes a unit (the `#@incdir` marker) and writes
# `#@pkgver`; the program prints CYRIUS_PKG_VERSION.
cat > "$P/src/main.cyr" <<'EOF'
fn main(): i64 {
    var s = CYRIUS_PKG_VERSION;
    var n = 0;
    while (load8(s + n) != 0) { n = n + 1; }
    syscall(1, 1, s, n);
    syscall(1, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(60, r);
EOF
# a program that never names the constant, for the absent row
printf 'syscall(60, 0);\n' > "$P/src/plain.cyr"
printf '[core]\n\textraheader = AUTHORIZATION: basic %s\n' "$SECRET" > "$P/.git/config"
printf '%s\n' "$SECRET" > "$P/.GIT/config"
printf '%s\n' "$SECRET" > "$P/real/VERSION"
ln -s real "$P/lnk"
printf '%s\n' "$SECRET" > "$P/h0"; ln "$P/h0" "$P/hard"
mkfifo "$P/fifo"
head -c 600 /dev/zero | tr '\0' '7' > "$P/big"
printf '1.0\nsyscall(1, 1, "INJECTED\\n", 9);\n' > "$P/two"
printf '4.5.6\n' > "$P/VERSION.real"

cli() { ( cd "$P" && env -u CYRIUS_DCE -u CYRIUS_DEFINES HOME="$W" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ); }
# mf <TOML value of [package] version, raw>  [entry]
mf() {
    e=${2:-src/main.cyr}
    printf '[package]\nname = "p"\nversion = %s\n[build]\nentry = "%s"\noutput = "build/main"\n' "$1" "$e" > "$P/cyrius.cyml"
}
# refused <label> <verb...> -> exit 1, names `[package] version = "`, no binary, no secret, no INJECTED
refused() {
    lbl=$1; shift
    rm -rf "$P/build"
    rc=0; ( cd "$P" && timeout 60 env -u CYRIUS_DCE -u CYRIUS_DEFINES HOME="$W" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ) > "$W/out" 2>&1 || rc=$?
    if [ "$rc" = 124 ]; then fail "$lbl: the verb HUNG (killed at 60 s)"; return; fi
    [ "$rc" = 1 ] || fail "$lbl: exit $rc, expected 1: $(head -2 "$W/out" | tr '\n' ' ')"
    grep -qF "error: cyrius.cyml [package] version = \"" "$W/out" || fail "$lbl: no 'error: cyrius.cyml [package] version = \"' line: $(head -2 "$W/out" | tr '\n' ' ')"
    grep -qF "$SECRET" "$W/out" && fail "$lbl: the outside secret reached the output"
    grep -qx "INJECTED" "$W/out" && fail "$lbl: the injected line RAN (INJECTED printed)"
    [ -e "$P/build/main" ] && fail "$lbl: a binary was built anyway"
    rm -rf "$P/build"
}

# ── axis 1: paths ────────────────────────────────────────────────────────────────────────
x=$FAIL
mf '"${file:../outside.txt}"';      refused "axis 1 ../x" build
grep -qF "climbs out with .." "$W/out" || fail "axis 1 ../x: not refused for the '..'"
mf '"${file:../outside.txt}"';      refused "axis 1 ../x --print-config" build --print-config
mf '"${file:../outside.txt}"';      refused "axis 1 ../x cyrius test" test src/plain.cyr
mf "\"\${file:$W/outside.txt}\"";   refused "axis 1 absolute" build
grep -qF "is absolute" "$W/out" || fail "axis 1 absolute: not refused as absolute"
ln -s ../outside.txt "$P/VERSION"
mf '"${file:VERSION}"';             refused "axis 1 committed VERSION link" build
grep -qF "passes through a symlink (VERSION)" "$W/out" || fail "axis 1 link: not refused for the link"
mf '"${file:VERSION}"';             refused "axis 1 VERSION link --print-config" build --print-config
rm -f "$P/VERSION"
mf '"${file:lnk/VERSION}"';         refused "axis 1 linked dir" build
mf '"${file:.git/config}"';         refused "axis 1 .git/config" build
grep -qF "reaches into .git" "$W/out" || fail "axis 1 .git: not refused for .git"
mf '"${file:.GIT/config}"';         refused "axis 1 .GIT/config" build
mf "'\${file:real\\VERSION}'";      refused "axis 1 backslash" build
mf '"${file:real/VERSION:x}"';      refused "axis 1 colon" build
mf '"${file:hard}"';                refused "axis 1 hard link" build
mf '"${file:d}"';                   refused "axis 1 directory" build
mf '"${file:fifo}"';                refused "axis 1 fifo" build
mf '"${file:big}"';                 refused "axis 1 600 bytes" build
[ "$FAIL" = "$x" ] && echo "  ok axis 1: ../x, absolute, a VERSION link, a linked dir, .git / .GIT, \\, :, a hard link, a directory, a FIFO and 600 bytes are refused by name (build, --print-config, test); nothing built, the secret never shown"

# ── axis 2: values ───────────────────────────────────────────────────────────────────────
x=$FAIL
mf '"${file:two}"';                 refused "axis 2 two-line file" build
mf '"1.0\nsyscall(1, 1, \"INJECTED\\n\", 9);"'; refused "axis 2 literal \\n" build
grep -qF '\x0a' "$W/out" || fail "axis 2 literal \\n: the line break is not shown as \\x0a"
mf '"1.0\u001b[31m"';               refused "axis 2 literal ESC" build
grep -q "$(printf '\033')" "$W/out" && fail "axis 2 literal ESC: the refusal echoed a raw ESC"
[ "$FAIL" = "$x" ] && echo "  ok axis 2: a two-line file, a literal \\n and a literal ESC are refused; INJECTED never ran, the bytes shown escaped"

# ── axis 3: the ./VERSION fallback ───────────────────────────────────────────────────────
x=$FAIL
printf '[package]\nname = "p"\n[build]\nentry = "src/plain.cyr"\noutput = "build/main"\n' > "$P/cyrius.cyml"
ln -s ../outside.txt "$P/VERSION"
rc=0; cli package > "$W/out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "axis 3: cyrius package with VERSION -> ../outside.txt exited $rc: $(head -2 "$W/out" | tr '\n' ' ')"
grep -qF "error: the project's ./VERSION" "$W/out" || fail "axis 3: the ./VERSION refusal is not named: $(head -1 "$W/out")"
grep -qF "$SECRET" "$W/out" && fail "axis 3: cyrius package printed the outside secret as the version"
# distlib stamps the same fallback as `# Version:` — and a second line of the file landed BELOW
# that comment, as bundle source (measured on 2ac318b0: dist/pp.cyr carried the payload fn). The
# stdlib snapshot it verifies against is the tree's lib/.
mkdir -p "$P/lib2"; printf 'fn pfoo(): i64 { return 1; }\n' > "$P/lib2/a.cyr"
printf '[package]\nname = "pp"\n[lib]\nmodules = ["lib2/a.cyr"]\n' > "$P/cyrius.cyml"
printf '1.0\nfn injected_by_version(): i64 { return 7; }\n' > "$W/outside_v"
rm -f "$P/VERSION"; ln -s ../outside_v "$P/VERSION"
[ -d "$W/home/lib" ] || cp -R "$ROOT/lib" "$W/home/lib"
rc=0; cli distlib > "$W/out" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -qF "error: the project's ./VERSION" "$W/out" || fail "axis 3: cyrius distlib with VERSION -> a two-line outside file was not refused by name (exit $rc): $(head -1 "$W/out")"
grep -qs injected_by_version "$P/dist/pp.cyr" && fail "axis 3: distlib wrote the outside file's second line into dist/pp.cyr as bundle source"
rm -rf "$P/dist" "$P/lib2" "$P/VERSION"
[ "$FAIL" = "$x" ] && echo "  ok axis 3: a ./VERSION link is refused by name on the fallback (cyrius package, cyrius distlib); the secret never shown, nothing stamped"

# ── axis 4: positive ─────────────────────────────────────────────────────────────────────
x=$FAIL
cp "$P/VERSION.real" "$P/VERSION"
mf '"${file:VERSION}"'
rm -rf "$P/build"; rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$("$P/build/main")" = "4.5.6" ] || fail "axis 4: \${file:VERSION} did not build a binary printing 4.5.6 (exit $rc): $(grep error "$W/out" | head -1)"
mf '"0.4.2"'
rm -rf "$P/build"; rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$("$P/build/main")" = "0.4.2" ] || fail "axis 4: a literal 0.4.2 did not build a binary printing it (exit $rc)"
rc=0; cli package > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qF "  version: 0.4.2" "$W/out" || fail "axis 4: cyrius package does not print the manifest's version 0.4.2 (exit $rc): $(grep version "$W/out" | head -1)"
mf '"${file:missing}"' src/plain.cyr
rm -rf "$P/build"; rc=0; cli build > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && [ -x "$P/build/main" ] || fail "axis 4: \${file:missing} no longer builds (absent beats wrong): $(head -2 "$W/out" | tr '\n' ' ')"
rc=0; cli build --print-config > "$W/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qF 'does not resolve; the build gets no CYRIUS_PKG_VERSION' "$W/out" || fail "axis 4: --print-config of \${file:missing} (exit $rc): $(grep version "$W/out" | head -1)"
rm -rf "$P/build" "$P/VERSION"
[ "$FAIL" = "$x" ] && echo "  ok axis 4: \${file:VERSION} and a literal build and print; a missing file is absent, not an error; cyrius package prints the manifest's version"

[ "$FAIL" = 0 ] || { echo "FAIL: $NAME ($FAIL)"; exit 1; }
echo "PASS: $NAME"
