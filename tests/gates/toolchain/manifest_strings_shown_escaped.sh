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
# 6.6.20 review, MEASURED on a9d9d523:
#   E6  a git dep cached from one URL and re-declared with an OSC sequence in its URL: the CVE-43
#       origin refusal printed `declared: file://…^[]0;pwned^G` raw (the clone path's unsafe-
#       character check never runs on a reused cache; reachable from a TRANSITIVE manifest)
#   E7  `cyrius distlib` / `--modular`: "module not found: <[lib] modules entry>" raw
#   E8  `cyrius = "9.9.9\u001b]0;pwned\u0007"`: the wrapper's and the resolver's "pins version …
#       not installed" lines, and `--version`'s manifest-pin line, raw. Since the 6.6.20 pin-shape
#       rule (CBT-01) a pin is [0-9A-Za-z._-] only, so a control byte can no longer reach those
#       lines at all: the ONE reader refuses the pin first, and E8 now asserts that refusal shows
#       the pin escaped on all three paths (deps, CYRIUS_RESOLVED=1 deps, CYRIUS_RESOLVED=1
#       --version) and exits 1 on each.
# 6.6.20 review round 2, MEASURED on 4360c717:
#   E9  `cyrius distlib` with `[lib] embed = ["x\u001b]0;pwned\u0007"]`: "[lib] embed names <entry>,
#       which [embed] does not declare" raw — a live OSC window-title sequence on stderr
#
# Hermetic: a mktemp CYRIUS_HOME with the CLI built FROM SOURCE as the pin's own wrapper; path
# deps, and for E6 one local file:// git origin (no network; /etc/gitconfig and ~/.gitconfig
# ignored; E6 skips by name where git is absent). CYRIUS_GATE_CLI=<built cyrius> runs it where
# build/cycc is foreign; else a non-Linux host SKIPs by name.
#
# Mutation ledger (MEASURED via CYRIUS_GATE_CLI, each mutant built from cbt/):
#   the e696746d CLI                                   -> E1 E2 E3 E4 E4b red
#   _ew_shown writes its argument raw                   -> E1 E2 E3 red
#   the sub-module refusal back on the printing validator -> E3 red
#   the bundle name back on the dep-name rule            -> E4b red
#   the declared git URL printed raw (_git_cache_refuse)  -> E6 red
#   distlib's module-not-found ctx raw                    -> E7 (distlib) red
#   distlib --modular's module-not-found ctx raw          -> E7 (--modular) red
#   the pin-shape refusal prints the pin raw (_ew, not _ew_shown) -> E8 red (6.6.20 integration)
#   distlib's undeclared [lib] embed entry raw              -> E9 red
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

# E6: a git dep whose cache was cloned from one URL, then declared with an ESC/BEL in its URL
# (the shape a TRANSITIVE manifest can take). The clone path's unsafe-character check never runs
# — the cache is reused — so the CVE-43 origin refusal is the line that echoes the URL.
floor=11
if command -v git >/dev/null 2>&1; then
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
    printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
    GO="$W/gorigin"; mkdir -p "$GO/dist"
    ( cd "$GO" && git init -q . && printf 'fn g_v(): i64 { return 1; }\n' > dist/g.cyr && git add -A && git commit -qm v1 && git tag 1.0.0 )
    P="$W/e6a"; mkp "$P" <<EOF6
name = "e6a"

[deps.g]
git = "file://$GO"
tag = "1.0.0"
modules = ["dist/g.cyr"]
EOF6
    run "$P" deps; rc6a=$rc
    P="$W/e6"; mkp "$P" <<EOF6
name = "e6"

[deps.g]
git = "file://$GO\\u001b]0;pwned\\u0007"
tag = "1.0.0"
modules = ["dist/g.cyr"]
EOF6
    run "$P" deps
    if [ "$rc6a" -eq 0 ] && [ "$rc" -eq 1 ] && noraw "$P" && ! grep -q "$(printf '\007')" "$P.err" \
       && grep -qxF "  declared:     file://$GO\\x1b]0;pwned\\x07" "$P.err" && grep -qxF "  cache origin: file://$GO" "$P.err"; then
        ok "E6 a cached git dep re-declared with an OSC sequence in its URL: the origin refusal shows it as \\x1b ... \\x07, rc 1, nothing raw"
    else bad "E6 (first rc=$rc6a, rc=$rc): $(grep -A1 'cache origin' "$P.err" | od -c | head -4)"; fi
else
    echo "  skip: E6 (git not found)"; floor=10
fi

# E7: `cyrius distlib` (and --modular) naming a `[lib] modules` entry that holds an OSC sequence.
for fl in "" --modular; do
    P="$W/e7$fl"; mkp "$P" <<'EOF7'
name = "e7"

[lib]
modules = ["src/a\u001b]0;pwned\u0007.cyr"]
EOF7
    if [ -n "$fl" ]; then run "$P" distlib "$fl"; pre="distlib --modular"; else run "$P" distlib; pre="distlib"; fi
    if [ "$rc" -eq 1 ] && noraw "$P" && ! grep -q "$(printf '\007')" "$P.err" \
       && grep -qxF "error: $pre: module not found: src/a\\x1b]0;pwned\\x07.cyr" "$P.err"; then
        ok "E7 $pre with an OSC sequence in a [lib] modules entry: module not found, shown as \\x1b ... \\x07, rc 1, nothing raw"
    else bad "E7 $pre (rc=$rc): $(head -2 "$P.err" | od -c | head -3)"; fi
done

# E9: `cyrius distlib` naming a `[lib] embed` entry that holds an OSC sequence (the key beside the
# `[lib] modules` of E7) — refused as undeclared in [embed], the entry shown escaped.
P="$W/e9"; mkp "$P" <<'EOF9'
name = "e9"

[lib]
modules = ["src/a.cyr"]
embed = ["x\u001b]0;pwned\u0007"]
EOF9
printf 'fn e9_a(): i64 { return 1; }\n' > "$P/src/a.cyr"
run "$P" distlib
if [ "$rc" -eq 1 ] && noraw "$P" && ! grep -q "$(printf '\007')" "$P.err" "$P.out" \
   && grep -qF "cyrius.cyml [lib] embed names x\\x1b]0;pwned\\x07, which [embed] does not declare" "$P.err"; then
    ok "E9 distlib with an OSC sequence in a [lib] embed entry: refused as undeclared, shown as \\x1b ... \\x07, rc 1, nothing raw"
else bad "E9 (rc=$rc): $(head -2 "$P.err" | od -c | head -3)"; fi

# E8: the `cyrius` PIN. Since 6.6.20 (CBT-01) the one reader refuses a pin that is not a version's
# shape before anything else reads it, so all three paths — the wrapper (deps), the resolver
# (CYRIUS_RESOLVED=1 skips the wrapper) and --version — stop at that refusal, which must show the
# pin escaped and exit 1.
P="$W/e8"; mkdir -p "$P/src"
printf '[package]\nname = "e8"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "9.9.9\\u001b]0;pwned\\u0007"\n\n[deps]\nstdlib = ["string"]\n' > "$P/cyrius.cyml"
PIN_REFUSED="error: cyrius.cyml [package] cyrius = '9.9.9\\x1b]0;pwned\\x07' is not a version"
run "$P" deps; rc8a=$rc; cp "$P.err" "$P.err.a"; cp "$P.out" "$P.out.a"
rc8b=0; ( cd "$P" && CYRIUS_RESOLVED=1 "$CY" deps > "$P.out.b" 2> "$P.err.b" ) || rc8b=$?
rc8c=0; ( cd "$P" && CYRIUS_RESOLVED=1 "$CY" --version > "$P.out.c" 2> "$P.err.c" ) || rc8c=$?
cat "$P.err.a" "$P.err.b" "$P.err.c" > "$P.err"; cat "$P.out.a" "$P.out.b" "$P.out.c" > "$P.out"
if [ "$rc8a" -eq 1 ] && [ "$rc8b" -eq 1 ] && [ "$rc8c" -eq 1 ] && noraw "$P" && ! grep -q "$(printf '\007')" "$P.err" "$P.out" \
   && grep -qF "$PIN_REFUSED" "$P.err.a" && grep -qF "$PIN_REFUSED" "$P.err.b" && grep -qF "$PIN_REFUSED" "$P.err.c"; then
    ok "E8 a cyrius pin holding an OSC sequence: refused as not a version on all three paths (wrapper, resolver, --version), shown as \\x1b ... \\x07, rc 1, nothing raw"
else bad "E8 (rc=$rc8a/$rc8b/$rc8c): $(cat "$P.err" "$P.out" | head -4 | od -c | head -4)"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -ge "$floor" ] || { echo "FAIL: $G: only $pass axes ran (floor $floor)"; exit 1; }
echo "PASS: $G — manifest strings in deps / distlib errors and the pin lines are shown escaped, once, by the caller that refused them"
