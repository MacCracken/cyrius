#!/bin/sh
# cli_path_reporting_leftovers.sh — 6.7.12. The CLI leftovers of the 6.7.6 review
# (issues/2026-10-08-cli-path-and-reporting-leftovers.md), one row per item, each with a mutation.
#
#   item 3  `_abs_path(".")` returned `<cwd>/.`, so every path joined onto the consumer's directory
#           carried a `/./` — git was run as `git -C <proj>/./../mono/libs/foo`. `.` is the cwd now
#           and a trailing `/.` is dropped.
#   item 4  `_process_named_deps` clamped its error count to 1, and the callers SUM it into the
#           summary: two refused `[deps.…]` sections printed two errors and `0 deps resolved, 1
#           errors`. It returns the count; only the exit status is clamped (256 errors still exit 1).
#   item 5  `cyrius lib sync --dry-run` printed each destination with `println(i64)` — a pointer
#           (`  would sync: 140127586328120`). It prints the path.
#
# ROWS
#   R3   a local-mode resolve of `path = "../mono/libs/foo"`: the logged `git -C` is <proj>/../mono/
#        libs/foo, with no `/./` (a logging `git` first on PATH)
#   R4   [deps.] + [deps..y]: two `error:` lines, `0 deps resolved, 2 errors`, rc 1
#   R4b  256 refused sections: `0 deps resolved, 256 errors` and rc 1 (the exit-status clamp holds)
#   R5   `lib sync --dry-run` for stdlib = ["string", "alloc"]: six `  would sync: lib/<f>.cyr` lines,
#        exactly the files `lib sync` then writes; the dry run writes nothing
#
# Mutations (measured, one at a time; CYRIUS_BIN=<a CLI built from the mutated cbt/> runs this gate
# on it): `_abs_path` without `_abs_drop_dot` → R3 RED; `_process_named_deps` returning the old
# clamp → R4 R4b RED; `_deps_finish` without its own clamp → R4 R4b RED (exit 2, and 0 at 256);
# the dry run's `println(vec_get(pd, wi))` restored → R5 RED.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=cli_path_reporting_leftovers
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found (R3 runs the local-mode git query)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

CLI=${CYRIUS_BIN:-}
if [ -z "$CLI" ]; then
    mkdir -p "$W/bin"
    "$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
      || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
    chmod +x "$W/bin/cyrius"
    CLI="$W/bin/cyrius"
fi
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V" "$H/deps" && cp -r lib "$H/versions/$V/lib" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

P="$W/p"
_cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CLI" "$@" ); }
_mkp() {   # $1 = the [deps] stdlib list; $2 = extra manifest text
    rm -rf "$P"; mkdir -p "$P"
    printf '[package]\nname = "leftovers"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "main.cyr"\noutput = "build/main"\n\n[deps]\nstdlib = [%s]\n%b' "$V" "$1" "$2" > "$P/cyrius.cyml"
    printf 'syscall(SYS_EXIT, 0);\n' > "$P/main.cyr"
}

# A `git` first on PATH that logs its ceiling and arguments, then runs the real one.
RG=$(command -v git)
mkdir -p "$W/fakegit"
printf '#!/bin/sh\nprintf "CEIL=%%s ARGS=%%s\\n" "$GIT_CEILING_DIRECTORIES" "$*" >> "%s"\nexec "%s" "$@"\n' "$W/git.log" "$RG" > "$W/fakegit/git"
chmod +x "$W/fakegit/git"

# The local-mode fixture: mono/ a git repository, mono/libs/foo inside it but no checkout of its
# own, an origin for foo's tag. Shared by R3 and (later) the ceiling rows.
M="$W/mono"
mkdir -p "$M/libs/foo/dist" "$W/o/foo/dist" \
  && printf 'fn foo_f(): i64 { return 1; }\n' > "$M/libs/foo/dist/foo.cyr" \
  && cp "$M/libs/foo/dist/foo.cyr" "$W/o/foo/dist/" \
  && ( cd "$M" && git init -q . && printf 'x\n' > README && git add README && git commit -qm init ) \
  && ( cd "$W/o/foo" && git init -q . && git add -A && git commit -qm v1 && git tag 1.0.0 ) \
  || { echo "FAIL: $G: cannot build the local-mode fixture"; exit 1; }
_foo() {   # $1 = foo's `path`
    printf '\n[deps.foo]\ngit = "file://%s/o/foo"\ntag = "1.0.0"\npath = "%s"\nmodules = ["dist/foo.cyr"]\n' "$W" "$1"
}

# ── R3: the consumer's directory carries no `/./` ─────────────────────────────────────────────
_mkp '"string"' "$(_foo ../mono/libs/foo)"
: > "$W/git.log"
( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 PATH="$W/fakegit:$PATH" \
  exec "$CLI" deps --local ) > "$W/r3.out" 2>&1
cdir=$(grep -m1 -- ' -C ' "$W/git.log" | sed 's/.* -C \([^ ]*\) .*/\1/')
if [ "$cdir" = "$P/../mono/libs/foo" ]; then ok "R3 local mode runs git -C <proj>/../mono/libs/foo (no /./)"
else bad "R3 git -C '$cdir' (want '$P/../mono/libs/foo'); $(head -2 "$W/r3.out")"; fi

# ── R4: the error count is the count ─────────────────────────────────────────────────────────
_mkp '"string"' '\n[deps.]\ngit = "file:///nonexistent"\ntag = "1"\n\n[deps..y]\ngit = "file:///nonexistent"\ntag = "1"\n'
rc=0; _cy deps > "$W/r4.out" 2>&1 || rc=$?
ne=$(grep -c '^error: \[deps\.' "$W/r4.out")
if [ "$rc" -eq 1 ] && [ "$ne" -eq 2 ] && grep -q '^0 deps resolved, 2 errors$' "$W/r4.out"; then
    ok "R4 [deps.] + [deps..y]: two errors named, '0 deps resolved, 2 errors', rc 1"
else bad "R4 (rc=$rc, $ne error lines): $(grep resolved "$W/r4.out")"; fi

# ── R4b: 256 errors still exit 1 ─────────────────────────────────────────────────────────────
x=""; i=0
while [ $i -lt 256 ]; do x="$x\n[deps..e$i]\ngit = \"file:///nonexistent\"\ntag = \"1\"\n"; i=$((i+1)); done
_mkp '"string"' "$x"
rc=0; _cy deps > "$W/r4b.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && grep -q '^0 deps resolved, 256 errors$' "$W/r4b.out"; then
    ok "R4b 256 refused sections: '0 deps resolved, 256 errors', rc 1"
else bad "R4b (rc=$rc): $(grep resolved "$W/r4b.out")"; fi

# ── R5: lib sync --dry-run names the files ───────────────────────────────────────────────────
_mkp '"string", "alloc"'
rc=0; _cy lib sync --dry-run > "$W/r5.out" 2>&1 || rc=$?
grep '^  would sync: ' "$W/r5.out" | sed 's/^  would sync: //' | sort > "$W/r5.dry"
nolib=1; [ -e "$P/lib" ] && nolib=0
_cy lib sync > "$W/r5s.out" 2>&1 || bad "R5 setup: lib sync failed: $(tail -2 "$W/r5s.out")"
( cd "$P" && find lib -name '*.cyr' | sort ) > "$W/r5.real"
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$W/r5.dry")" -eq 6 ] && cmp -s "$W/r5.dry" "$W/r5.real" && [ "$nolib" -eq 1 ] \
   && grep -q '^dry-run: would sync 6 \.cyr files' "$W/r5.out"; then
    ok "R5 lib sync --dry-run: six 'would sync: lib/<f>.cyr' lines, the files lib sync writes; nothing written"
else bad "R5 (rc=$rc, lib/ written: $((1-nolib))): $(head -2 "$W/r5.dry" | tr '\n' ' ') vs $(head -2 "$W/r5.real" | tr '\n' ' ')"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
