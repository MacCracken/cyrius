#!/bin/sh
# manifest_strings_shown_escaped.sh — a string read from a manifest (the project's own, or a
# dependency's, which the user never wrote) reaches the terminal in an error ONLY through the one
# escaping printer (`_shown` / `_ew_shown`, cbt/deps.cyr): a byte below 32, 127 or above is shown
# as `\xNN`. A raw ESC in an error line is a terminal escape sequence the manifest's author
# chose (clear the screen, retitle the window, forge an earlier line); a raw newline forges a
# whole line. And each refusal is ONE line, from the caller that knows what was refused.
#
# 6.6.20 (REFACTOR-06). MEASURED on e696746d:
#   E1  a `path` with an ESC went raw into the "declares no modules" warning
#   E2  a `modules` entry with an ESC went raw into "modules entry … not found"
#   E3  a modular sub-module name was refused by the shared validator's own generic line
#       ("unsafe dep name (path traversal rejected): …", no dep, no key) with an ESC in it raw;
#       the same printing validator made the [deps.NAME] header refusal two lines
#   E4  `[package] name = "nm\nvar INJECTED = 7;\n#"`: `cyrius distlib` wrote
#       `dist/nm?var INJECTED = 7;?#.cyr` with a LIVE `var INJECTED = 7;` line in the bundle
#       header (the name took the dep-name rule, which allowed a newline); E4b `name = "my lib"`
#       wrote `dist/my lib.cyr` — the bundle name is now the profile rule, an identifier
# E5 is the anti-over-reach row: an ordinary bundle name still bundles.
#
# Hermetic: a mktemp CYRIUS_HOME with the CLI built FROM SOURCE as the pin's own wrapper; path
# deps only (no network, no git). CYRIUS_GATE_CLI=<built cyrius> runs it where build/cycc is
# foreign; else a non-Linux host SKIPs by name.
#
# Mutation ledger (MEASURED via CYRIUS_GATE_CLI, each mutant built from cbt/):
#   the e696746d CLI                                   -> E1 E2 E3 E4 E4b red
#   _ew_shown writes its argument raw                   -> E1 E2 E3 red
#   the sub-module refusal back on the printing validator -> E3 red
#   the bundle name back on the dep-name rule            -> E4b red
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
OS=$(uname -s 2>/dev/null || echo unknown)
G=manifest_strings_shown_escaped
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
V=$(tr -d '[:space:]' < "$ROOT/VERSION")
ESC=$(printf '\033')

nohost() {
    if [ "$OS" = Linux ]; then echo "FAIL: $G: $1"; exit 1; fi
    echo "SKIP: $G: $1 (pass CYRIUS_GATE_CLI=<built cyrius> to run here)"; exit 77
}
[ -x "$CC" ] || nohost "build/cycc missing"
if [ -n "${CYRIUS_GATE_CLI:-}" ]; then
    [ -x "$CYRIUS_GATE_CLI" ] || { echo "FAIL: $G: CYRIUS_GATE_CLI=$CYRIUS_GATE_CLI is not executable"; exit 1; }
    cp "$CYRIUS_GATE_CLI" "$W/cyrius"
else
    ( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null ) || nohost "could not build cbt/cyrius.cyr"
    [ -s "$W/cyrius" ] || nohost "cbt/cyrius.cyr built an EMPTY binary"
fi
chmod +x "$W/cyrius"
"$W/cyrius" --version >/dev/null 2>&1 || nohost "the CLI under test does not execute here"
H="$W/home"; mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib" "$H/deps"
cp -r "$ROOT/lib/." "$H/versions/$V/lib/"
cp "$W/cyrius" "$H/versions/$V/bin/cyrius"; cp "$CC" "$H/versions/$V/bin/cycc"
# distlib's sidecar verify also compiles for aarch64 (E5): the cross-compiler, built from the tree.
"$CC" < src/main_aarch64.cyr > "$H/versions/$V/bin/cycc_aarch64" 2>/dev/null || nohost "could not build the aarch64 cross-compiler"
chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" "$H/versions/$V/bin/cycc_aarch64"
printf '%s\n' "$V" > "$H/current"; ln -s "$H/versions/$V/bin" "$H/bin"; ln -s "$H/versions/$V/lib" "$H/lib"
CY="$H/versions/$V/bin/cyrius"
export CYRIUS_HOME="$H"

mkp() {   # $1 = project dir; stdin = everything after [package] name
    mkdir -p "$1/src"
    { printf '[package]\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n' "$V"; cat; } > "$1/cyrius.cyml"
    printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$1/src/main.cyr"
}
run() {   # $1 = dir, $2.. = verb; sets rc, writes $1.out / $1.err
    d=$1; shift
    rc=0; if ( cd "$d" && "$CY" "$@" > "$d.out" 2> "$d.err" ); then rc=0; else rc=$?; fi
}
noraw() { ! grep -qF "$ESC" "$1.err" "$1.out"; }
PD="$W/pathdep"; mkdir -p "$PD/dist/sub"; printf 'fn pd_v(): i64 { return 2; }\n' > "$PD/dist/pathdep.cyr"

# E1: a `path` holding ESC, in the "declares no modules" warning.
P="$W/e1"; mkp "$P" <<'EOF'
name = "e1"

[deps.nod]
path = "/nonexistent/a\u001b[2Jb"
EOF
run "$P" deps
if noraw "$P" && grep -qF 'a\x1b[2Jb ships no dist/nod.cyr' "$P.err"; then
    ok "E1 a path holding ESC: the warning shows it as \\x1b, no raw ESC on either stream"
else bad "E1 (rc=$rc): $(head -2 "$P.err" | od -c | head -3)"; fi

# E2: a `modules` entry holding ESC, in "modules entry … not found".
P="$W/e2"; mkp "$P" <<EOF
name = "e2"

[deps.pathdep]
path = "$PD"
modules = ["dist/a\\u001b]0;pwned\\u0007b.cyr"]
EOF
run "$P" deps
if [ "$rc" -eq 1 ] && noraw "$P" && ! grep -q "$(printf '\007')" "$P.err" \
   && grep -qF 'modules entry "dist/a\x1b]0;pwned\x07b.cyr" not found' "$P.err"; then
    ok "E2 a modules entry holding an OSC title sequence: rc 1, shown as \\x1b ... \\x07, nothing raw"
else bad "E2 (rc=$rc): $(head -2 "$P.err" | od -c | head -3)"; fi

# E3: a modular sub-module name — ONE refusal line, escaped.
P="$W/e3"; mkp "$P" <<EOF
name = "e3"

[deps.pathdep]
path = "$PD"
modular = ["../x", "s\\u001bt"]
EOF
run "$P" deps
n3=$(grep -c "x'\|\.\./x" "$P.err" || true)
if [ "$rc" -eq 1 ] && noraw "$P" \
   && grep -qxF "error: [deps.pathdep] modular sub-module '../x' is not a usable name (empty, \`.\`-led, or holding \`/\`, \`\\\`, \`..\` or a control byte) — refused" "$P.err" \
   && grep -qF "modular sub-module 's\\x1bt' is not a usable name" "$P.err" && [ "$n3" -eq 1 ] \
   && ! grep -q 'path traversal rejected' "$P.err"; then
    ok "E3 modular sub-modules '../x' and one holding ESC: each refused by ONE named line (no second validator line), shown escaped, rc 1"
else bad "E3 (rc=$rc lines naming ../x: $n3): $(head -4 "$P.err")"; fi

# E4: [package] name with newlines — refused by the bundle-name rule; nothing written.
P="$W/e4"; mkp "$P" <<'EOF'
name = "nm\nvar INJECTED = 7;\n#"

[lib]
modules = ["src/a.cyr"]
EOF
printf 'fn e4_a(): i64 { return 1; }\n' > "$P/src/a.cyr"
run "$P" distlib
if [ "$rc" -eq 1 ] && grep -qxF "error: distlib: [package] name 'nm\\x0avar INJECTED = 7;\\x0a#' cannot name a bundle (allowed: [A-Za-z0-9_-], 1-32 characters) — nothing written" "$P.err" \
   && ! grep -rqs 'INJECTED' "$P/dist" && ! grep -q '^var INJECTED' "$P.err" "$P.out"; then
    ok "E4 [package] name holding newlines: distlib refuses by the bundle-name rule (shown \\x0a), rc 1, no bundle written"
else bad "E4 (rc=$rc dist=[$(ls "$P/dist" 2>/dev/null | od -c | head -2)]): $(head -2 "$P.err")"; fi

# E4b: the bundle name is an IDENTIFIER (the profile rule), not merely a safe path component — a
# space (or a quote, a `.`, a 33rd character) cannot name dist/<name>.cyr either.
P="$W/e4b"; mkp "$P" <<'EOF'
name = "my lib"

[lib]
modules = ["src/a.cyr"]
EOF
printf 'fn e4b_a(): i64 { return 1; }\n' > "$P/src/a.cyr"
run "$P" distlib
if [ "$rc" -eq 1 ] && grep -qF "error: distlib: [package] name 'my lib' cannot name a bundle" "$P.err" && [ ! -e "$P/dist/my lib.cyr" ]; then
    ok "E4b [package] name = \"my lib\": refused by the bundle-name rule, rc 1, no dist/my lib.cyr"
else bad "E4b (rc=$rc dist=[$(ls "$P/dist" 2>/dev/null | tr '\n' '|')]): $(head -2 "$P.err")"; fi

# E5: anti-over-reach — an ordinary name bundles.
P="$W/e5"; mkp "$P" <<'EOF'
name = "my-lib_2"

[lib]
modules = ["src/a.cyr"]
EOF
printf 'fn e5_a(): i64 { return 1; }\n' > "$P/src/a.cyr"
run "$P" distlib
if [ "$rc" -eq 0 ] && [ -f "$P/dist/my-lib_2.cyr" ] && grep -q 'fn e5_a' "$P/dist/my-lib_2.cyr"; then
    ok "E5 [package] name = \"my-lib_2\": bundles to dist/my-lib_2.cyr, rc 0"
else bad "E5 (rc=$rc): $(head -3 "$P.err")"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -ge 6 ] || { echo "FAIL: $G: only $pass axes ran (floor 6)"; exit 1; }
echo "PASS: $G — manifest strings in errors are shown escaped, once, by the caller that refused them"
