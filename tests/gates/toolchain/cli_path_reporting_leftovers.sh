#!/bin/sh
# cli_path_reporting_leftovers.sh — 6.7.12. The CLI leftovers of the 6.7.6 review
# (issues/2026-10-08-cli-path-and-reporting-leftovers.md), one row per item, each with a mutation.
#
#   item 3  `_abs_path(".")` returned `<cwd>/.`, so every path joined onto the consumer's directory
#           carried a `/./` — `not found in the local path <proj>/./../mono/libs/foo`, and git ran
#           as `git -C <proj>/./../mono/libs/foo`. `.` is the cwd now and a trailing `/.` is dropped.
#   item 4  `_process_named_deps` clamped its error count to 1, and the callers SUM it into the
#           summary: two refused `[deps.…]` sections printed two errors and `0 deps resolved, 1
#           errors`. It returns the count; only the exit status is clamped (256 errors still exit 1).
#   item 5  `cyrius lib sync --dry-run` printed each destination with `println(i64)` — a pointer
#           (`  would sync: 140127586328120`). It prints the path.
#   item 2  `_tc_unit_dir` compared an absolute unit path with getcwd byte for byte. getcwd answers
#           the PHYSICAL directory, so under a symlinked working directory the logical `$PWD`
#           spelling missed, the unit counted as outside the project and lost its test.cyml
#           (`FAIL: …/link/tests/sub/x.tcyr (exit 1)`). The cwd is found by identity now: the
#           shortest prefix of the path whose stat dev/ino is the cwd's.
#   item 7  `_dep_wt_run` put GIT_CEILING_DIRECTORIES at the parent of the dep directory's
#           SPELLING: a local dep reached through a symlink got the link's parent, git walked up
#           from the physical target into the enclosing repository, and `links/foo` reported
#           mono's HEAD and dirt where `../mono/libs/foo` (the same directory) said `(not a git
#           checkout)`. The git child resolves the physical directory (chdir + cwd) and puts the
#           ceiling at its parent; `_git_run` (the clone cache) does the same.
#   item 6  `cyrius update` copied the whole snapshot of `$CYRIUS_HOME/current` (113 files for
#           stdlib = ["string", "alloc"]), whatever the manifest declared or pinned. D18 (the user,
#           2026-10-15): it writes what `lib sync` writes — the declared set at the manifest's pin,
#           `--full` for the whole snapshot.
#   item 1  On cyrius.exe `_abs_path` was the identity: the cwd came from getcwd (syscall 79), which
#           has no PE reroute (-38), and only a leading `/` counted as absolute. So an absolute
#           in-project unit (`C:\proj\tests\sub\x.tcyr`) was "outside the project" and lost its
#           test.cyml, and CYRIUS_TEST_FILE / CYRIUS_TEST_DIR were exported relative (`tests\sub\e.tcyr`,
#           `.`). The cwd comes from GetCurrentDirectoryW now, a drive-rooted path is absolute, and the
#           drive-relative refusal (`C:x`, a rooted `\x`) stays.
#   item 8  The lock's digests came from a spawned `sha256sum` / `shasum` (certutil.exe on PE):
#           under wine, which has no certutil, `cyrius deps` printed `warning: cyrius.lock NOT
#           written — cannot hash lib/alloc.cyr (and 15 more)` and wrote no lock. The SHA-256 is
#           computed in process now, byte-identical to sha256sum (no existing lock churns).
#
# ROWS
#   R3   a path dep `../mono/libs/foo` whose module is missing: the error names the local path
#        <proj>/../mono/libs/foo, with no `/./`
#   R4   [deps.] + [deps..y]: two `error:` lines, `0 deps resolved, 2 errors`, rc 1
#   R4b  256 refused sections: `0 deps resolved, 256 errors` and rc 1 (the exit-status clamp holds)
#   R5   `lib sync --dry-run` for stdlib = ["string", "alloc"]: six `  would sync: lib/<f>.cyr` lines,
#        exactly the files `lib sync` then writes; the dry run writes nothing
#   R2a  the filed repro: `cd link; cyrius test $PWD/tests/sub/x.tcyr` passes (test.cyml's FOO)
#   R2b  …and the physical, the relative and the `link/./` spellings pass too
#   R2c  a unit of ANOTHER project (its own test.cyml) is still outside: it gets no FOO, fails
#   R7a  `path = "links/foo"` (a symlink to mono/libs/foo) says `(not a git checkout)`, exactly as
#        `path = "../mono/libs/foo"` does; neither names mono's HEAD
#   R7b  the logged ceiling for both spellings is the physical parent, <mono>/libs
#   R7c  the clone cache reached through a symlink (`<home>/deps/foo/1.0.0 -> elsewhere/1.0.0`):
#        the cache's git runs get the physical parent `elsewhere` as their ceiling
#   R6a  `cyrius update` with stdlib = ["string", "alloc"]: lib/ holds exactly the six files
#        `lib sync` writes (R5's set), from versions/<pin>/lib
#   R6b  `cyrius update --full`: lib/ holds every .cyr of the snapshot
#   R6c  `current` names another installed version whose string.cyr differs: update copies the
#        PIN's string.cyr, writes the pin into .cyrius-toolchain, and `deps --verify` passes
#   R8a  the lock-hash row: lib/ = the whole lib/ corpus plus files of 0, 1, 55-57, 63-65,
#        119-121, 127-129, 32767-32769 and 100001 random bytes (the padding and read-chunk
#        edges): `deps --lock` writes one row per file, every row sha256sum's
#   R8b  no hasher on PATH at all: a stdlib-only `deps` writes its first lock, rows sha256sum's
#   W8   (wine, named SKIP without it) the PE CLI's `deps` writes cyrius.lock, rows sha256sum's
#   W1a  (wine) `cyrius.exe test <drive>:\…\proj\tests\sub\x.tcyr` (absolute, in the project):
#        test.cyml applies, rc 0
#   W1b  (wine) the `<drive>:/…/tests/sub/x.tcyr` and lower-case-drive spellings: rc 0
#   W1c  (wine) the drive-relative `<drive>:tests\sub\x.tcyr` is still outside: exit 1
#   W1d  (wine) the relative `tests\sub\e.tcyr` gets CYRIUS_TEST_FILE / CYRIUS_TEST_DIR absolute,
#        DIR = <drive>:\…\proj/tests\sub
#
# Mutations (measured, one at a time; CYRIUS_BIN=<a CLI built from the mutated cbt/> runs this gate
# on it): `_abs_path` without `_abs_drop_dot` → R3 RED; `_process_named_deps` returning the old
# clamp → R4 R4b RED; `_deps_finish` without its own clamp → R4 R4b RED (exit 2, and 0 at 256);
# the dry run's `println(vec_get(pd, wi))` restored → R5 RED; `_tc_below_cwd` back to the byte
# compare against getcwd → R2a R2b RED; the identity test replaced by "the nearest prefix holding a
# cyrius.cyml" (the unit's own project) → R2c RED; `_dep_wt_run`'s child without the physical
# ceiling → R7a R7b RED; `_git_run`'s → R7c RED; 6.7.11's cmd_update (the whole snapshot of
# `current`) → R6a R6b R6c RED (R6b: `--full` refused as unknown); the `--full` switch not set for
# update → R6b RED (6 of 113 files);
# .cyrius-toolchain written from `current` → R6c RED; the second padding block taken at tl > 56
# (not >= 56) → R8a RED (the 56-byte tails); the length bits written little-endian → R8a R8b RED;
# 6.7.11's sha256sum spawn → R8b RED (no lock, `neither sha256sum nor shasum`) and W8 RED (no
# lock: wine has no certutil); `_win_cwd_read` returning -1 (the 6.7.11 identity) → W1a W1b W1d
# RED; the drive compared case-sensitively → W1b RED; the `:` refusal dropped (a drive-relative
# path read as a project path) → W1c RED.
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
mkdir -p "$H/versions/$V" "$H/deps" "$H/bin" && cp -r lib "$H/versions/$V/lib" && printf '%s\n' "$V" > "$H/current" \
  && cp "$CC" "$H/bin/cycc" || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
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
_mkp '"string"' '\n[deps.foo]\npath = "../mono/libs/foo"\nmodules = ["dist/nope.cyr"]\n'
rc=0; _cy deps > "$W/r3.out" 2>&1 || rc=$?
want="error: [deps.foo] modules entry \"dist/nope.cyr\" not found in the local path $P/../mono/libs/foo"
if [ "$rc" -eq 1 ] && grep -qxF "$want" "$W/r3.out"; then ok "R3 the missing module's error names <proj>/../mono/libs/foo (no /./)"
else bad "R3 (rc=$rc): $(grep -m1 'not found in the local path' "$W/r3.out")"; fi

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

# ── R2: a unit under a symlinked working directory keeps its test.cyml ──────────────────────
T="$W/t2"
mkdir -p "$T/proj/tests/sub" "$T/other/tests/sub" && ln -s proj "$T/link"
for d in proj other; do
    printf '[package]\nname = "%s"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls"]\n' "$d" "$V" > "$T/$d/cyrius.cyml"
    printf '[test]\ndefines = ["FOO"]\n' > "$T/$d/tests/sub/test.cyml"
    printf '#ifdef FOO\nsyscall(SYS_EXIT, 0);\n#endif\nsyscall(SYS_EXIT, 1);\n' > "$T/$d/tests/sub/x.tcyr"
done
_ct() {   # $1 = the working directory as the shell spells it, $2 = the unit; prints the rc
    ( cd "$1" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
      exec "$CLI" test "$2" ) > "$W/r2.out" 2>&1
    echo $?
}
r=$(_ct "$T/link" "$T/link/tests/sub/x.tcyr")
if [ "$r" -eq 0 ]; then ok "R2a cd link; cyrius test \$PWD/tests/sub/x.tcyr: test.cyml applies, rc 0"
else bad "R2a the logical \$PWD spelling (rc $r): $(grep -m1 FAIL "$W/r2.out")"; fi
r1=$(_ct "$T/link" "$T/proj/tests/sub/x.tcyr"); r2=$(_ct "$T/link" tests/sub/x.tcyr)
r3=$(_ct "$T/link" "$T/link/./tests/sub/x.tcyr"); r4=$(_ct "$T/proj" "$T/proj/tests/sub/x.tcyr")
if [ "$r1$r2$r3$r4" = "0000" ]; then ok "R2b the physical, relative, link/./ and in-project absolute spellings: rc 0"
else bad "R2b physical $r1, relative $r2, link/./ $r3, from proj $r4"; fi
r=$(_ct "$T/proj" "$T/other/tests/sub/x.tcyr")
if [ "$r" -eq 1 ] && grep -q 'FAIL: .*other/tests/sub/x.tcyr (exit 1)' "$W/r2.out"; then
    ok "R2c another project's unit stays outside: no test.cyml, exit 1"
else bad "R2c another project's unit (rc $r): $(grep -m1 -E 'FAIL|ok' "$W/r2.out")"; fi

# ── R7: the git ceiling is the PHYSICAL parent ───────────────────────────────────────────────
mkdir -p "$W/p7l/links" && ln -s ../../mono/libs/foo "$W/p7l/links/foo"
_r7() {   # $1 = foo's path; leaves the `local:` line in r7.out and the git log in git.log
    rm -f "$W/p7l/cyrius.cyml"; mkdir -p "$W/p7l"
    printf '[package]\nname = "p7"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[deps]\nstdlib = ["string"]\n%s\n' "$V" "$(_foo "$1")" > "$W/p7l/cyrius.cyml"
    : > "$W/git.log"
    ( cd "$W/p7l" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 PATH="$W/fakegit:$PATH" \
      exec "$CLI" deps --local ) > "$W/r7.out" 2>&1
}
_r7 links/foo;        la=$(grep -m1 '^local: foo' "$W/r7.out"); ca=$(grep -m1 -- ' -C ' "$W/git.log" | sed 's/^CEIL=\([^ ]*\) .*/\1/')
_r7 ../mono/libs/foo; lb=$(grep -m1 '^local: foo' "$W/r7.out"); cb=$(grep -m1 -- ' -C ' "$W/git.log" | sed 's/^CEIL=\([^ ]*\) .*/\1/')
case "$la|$lb" in
    "local: foo <- links/foo (not a git checkout) — CI builds 1.0.0|local: foo <- ../mono/libs/foo (not a git checkout) — CI builds 1.0.0")
        ok "R7a links/foo and ../mono/libs/foo: both '(not a git checkout)'" ;;
    *) bad "R7a links/foo: '$la' | ../mono/libs/foo: '$lb'" ;;
esac
if [ "$ca" = "$M/libs" ] && [ "$cb" = "$M/libs" ]; then ok "R7b both spellings' git ceiling: the physical parent <mono>/libs"
else bad "R7b ceilings '$ca' and '$cb' (want '$M/libs')"; fi
# the clone cache through a symlink
_mkp '"string"' "\n[deps.foo]\ngit = \"file://$W/o/foo\"\ntag = \"1.0.0\"\nmodules = [\"dist/foo.cyr\"]\n"
_cy deps > "$W/r7c0.out" 2>&1 || bad "R7c setup: the first resolve failed: $(tail -2 "$W/r7c0.out")"
mkdir -p "$W/elsewhere" && mv "$H/deps/foo/1.0.0" "$W/elsewhere/" && ln -s "$W/elsewhere/1.0.0" "$H/deps/foo/1.0.0" \
  || bad "R7c setup: cannot move the cache behind a symlink"
rm -rf "$P/lib" "$P/cyrius.lock"; : > "$W/git.log"
rc=0; ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 PATH="$W/fakegit:$PATH" \
  exec "$CLI" deps ) > "$W/r7c.out" 2>&1 || rc=$?
ceils=$(grep -- '--no-replace-objects' "$W/git.log" | sed 's/^CEIL=\([^ ]*\) .*/\1/' | sort -u)
if [ "$rc" -eq 0 ] && [ "$ceils" = "$W/elsewhere" ]; then ok "R7c the cache behind a symlink: every cache git run's ceiling is the physical parent"
else bad "R7c (rc $rc) ceilings: $(echo "$ceils" | tr '\n' ' ')"; fi

# ── R6: update writes what lib sync writes (D18) ─────────────────────────────────────────────
_mkp '"string", "alloc"'
rc=0; _cy update > "$W/r6a.out" 2>&1 || rc=$?
( cd "$P" && find lib -name '*.cyr' | sort ) > "$W/r6a.files"
if [ "$rc" -eq 0 ] && cmp -s "$W/r6a.files" "$W/r5.real" && grep -qF "synced from $H/versions/$V/lib" "$W/r6a.out"; then
    ok "R6a update: the six files lib sync writes, from versions/$V/lib"
else bad "R6a (rc=$rc, $(wc -l < "$W/r6a.files") files): $(grep -m1 -E 'synced|updated|error' "$W/r6a.out")"; fi
rc=0; _cy update --full > "$W/r6b.out" 2>&1 || rc=$?
nl=$(cd "$P" && find lib -name '*.cyr' | wc -l | tr -d ' '); ns=$(cd "$H/versions/$V" && find lib -name '*.cyr' | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$nl" -eq "$ns" ] && [ "$ns" -gt 50 ]; then ok "R6b update --full: all $ns .cyr files of the snapshot"
else bad "R6b (rc=$rc): $nl of $ns files; $(grep -m1 -E 'error|synced' "$W/r6b.out")"; fi
# another installed version named by `current`, its string.cyr different
O="0.0.9"
mkdir -p "$H/versions/$O" && cp -r lib "$H/versions/$O/lib" && printf '# another version\n' >> "$H/versions/$O/lib/string.cyr" \
  && printf '%s\n' "$O" > "$H/current" || bad "R6c setup: cannot stage $O"
_mkp '"string", "alloc"'
_cy deps > "$W/r6c0.out" 2>&1 || bad "R6c setup: deps failed: $(tail -2 "$W/r6c0.out")"
printf '%s\n' "$O" > "$P/.cyrius-toolchain"
rc=0; _cy update > "$W/r6c.out" 2>&1 || rc=$?
v=0; _cy deps --verify > "$W/r6cv.out" 2>&1 || v=$?
if [ "$rc" -eq 0 ] && cmp -s "$P/lib/string.cyr" lib/string.cyr && [ "$(cat "$P/.cyrius-toolchain")" = "$V" ] && [ "$v" -eq 0 ]; then
    ok "R6c current = $O: update copies the pin's ($V) string.cyr, .cyrius-toolchain = $V, deps --verify passes"
else bad "R6c (rc=$rc, verify rc=$v, .cyrius-toolchain '$(cat "$P/.cyrius-toolchain")'): string.cyr $(cmp -s "$P/lib/string.cyr" lib/string.cyr && echo "is the pin's" || echo "is NOT the pin's"); $(grep -m1 -E 'synced|updated|error' "$W/r6c.out")"; fi
printf '%s\n' "$V" > "$H/current"

# ── R8: the lock's SHA-256 is in process and equals sha256sum's ──────────────────────────────
if command -v sha256sum > /dev/null 2>&1; then
    rm -rf "$P"; mkdir -p "$P/lib/edge"
    printf '[package]\nname = "hashes"\nversion = "0.0.1"\nlanguage = "cyrius"\n' > "$P/cyrius.cyml"
    cp -r lib/. "$P/lib/"
    for n in 0 1 55 56 57 63 64 65 119 120 121 127 128 129 32767 32768 32769 100001; do
        head -c "$n" /dev/urandom > "$P/lib/edge/e$n.cyr"
    done
    rc=0; _cy deps --lock > "$W/r8a.out" 2>&1 || rc=$?
    nf=$(cd "$P" && find lib -name '*.cyr' | wc -l | tr -d ' ')
    nr=$(grep -c '^[0-9a-f]\{64\}  ' "$P/cyrius.lock" 2>/dev/null); nr=${nr:-0}
    nbad=$( cd "$P" && grep '^[0-9a-f]\{64\}  ' cyrius.lock 2>/dev/null | sha256sum -c 2>/dev/null | grep -vc ': OK$' )
    if [ "$rc" -eq 0 ] && [ "$nr" -eq "$nf" ] && [ "$nf" -gt 100 ] && [ "$nbad" -eq 0 ]; then
        ok "R8a deps --lock over the lib/ corpus + 18 edge sizes: $nr rows, every one sha256sum's"
    else bad "R8a (rc=$rc): $nr rows for $nf files, $nbad differ from sha256sum; $(head -2 "$W/r8a.out")"; fi
    _mkp '"syscalls", "string"'
    mkdir -p "$W/nohash"
    rc=0; ( cd "$P" && PATH="$W/nohash" HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
      exec "$CLI" deps ) > "$W/r8b.out" 2>&1 || rc=$?
    nf=$(cd "$P" && find lib -name '*.cyr' | wc -l | tr -d ' ')
    nr=$(grep -c '^[0-9a-f]\{64\}  ' "$P/cyrius.lock" 2>/dev/null); nr=${nr:-0}
    if [ "$rc" -eq 0 ] && [ "$nr" -eq "$nf" ] && [ "$nf" -gt 0 ] && ( cd "$P" && grep '^[0-9a-f]\{64\}  ' cyrius.lock | sha256sum -c --quiet ) > /dev/null 2>&1; then
        ok "R8b no hasher on PATH: deps writes the first lock ($nr rows, sha256sum's)"
    else bad "R8b (rc=$rc): $nr rows for $nf files; $(grep -m1 -E 'warning|error' "$W/r8b.out")"; fi
else
    echo "  SKIP: R8a R8b — no sha256sum to compare the in-process digest with"
fi

# ── W: the PE CLI under wine ─────────────────────────────────────────────────────────────────
if command -v wine > /dev/null 2>&1 && command -v sha256sum > /dev/null 2>&1; then
    WP="$W/wine"; WHM="$W/whome"
    _wine_down() {
        [ -d "$WP" ] || return 0
        _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
        WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
        WINEPREFIX="$WP" wineserver -w > /dev/null 2>&1 || true
        rm -rf "$_ws" || true
    }
    trap '_wine_down; rm -rf "$W"' EXIT
    "$CC" < src/main_win.cyr > "$W/cc_win" 2> /dev/null && chmod +x "$W/cc_win" \
      && "$W/cc_win" < cbt/cyrius.cyr > "$W/cyrius.exe" 2> "$W/pe.err" && [ -s "$W/cyrius.exe" ] \
      || { bad "W setup: the PE CLI does not cross-build: $(grep -m1 -E 'error' "$W/pe.err")"; }
    _wcy() {   # run the PE CLI in $P with the throwaway home (as a Windows path)
        ( cd "$P" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
          WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' CYRIUS_HOME="$(WINEPREFIX="$WP" HOME="$WHM" winepath -w "$H" 2>/dev/null)" \
          CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 timeout 300 wine "$W/cyrius.exe" "$@" )
    }
    _mkp '"string"'
    rc=0; _wcy deps > "$W/w8.out" 2>&1 || rc=$?
    nf=$(cd "$P" && find lib -name '*.cyr' 2> /dev/null | wc -l | tr -d ' ')
    nr=$(grep -c '^[0-9a-f]\{64\}  ' "$P/cyrius.lock" 2>/dev/null); nr=${nr:-0}
    if [ "$rc" -eq 0 ] && [ "$nr" -eq "$nf" ] && [ "$nf" -gt 0 ] && ( cd "$P" && grep '^[0-9a-f]\{64\}  ' cyrius.lock | sha256sum -c --quiet ) > /dev/null 2>&1; then
        ok "W8 wine: cyrius.exe deps writes cyrius.lock ($nr rows, each sha256sum's)"
    else bad "W8 wine (rc=$rc): $nr rows for $nf files; $(grep -m1 -E 'warning|error' "$W/w8.out" | tr -d '\r')"; fi
    # item 1: the PE compiler beside the PE CLI, a project with tests/sub/test.cyml
    mkdir -p "$W/wbin" && cp "$W/cyrius.exe" "$W/wbin/cyrius.exe" \
      && "$W/cc_win" < src/main_win.cyr > "$W/wbin/cycc.exe" 2> /dev/null && [ -s "$W/wbin/cycc.exe" ] \
      || bad "W1 setup: the PE compiler does not cross-build"
    P="$W/w1"; rm -rf "$P"; mkdir -p "$P/tests/sub"
    printf '[package]\nname = "w1"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls", "string", "alloc", "io"]\n' "$V" > "$P/cyrius.cyml"
    printf '[test]\ndefines = ["FOO"]\n' > "$P/tests/sub/test.cyml"
    printf '#ifdef FOO\nsyscall(SYS_EXIT, 0);\n#endif\nsyscall(SYS_EXIT, 1);\n' > "$P/tests/sub/x.tcyr"
    printf 'alloc_init();\nvar f = getenv("CYRIUS_TEST_FILE");\nvar d = getenv("CYRIUS_TEST_DIR");\nif (f != 0) { syscall(1, 1, "FILE=", 5); syscall(1, 1, f, strlen(f)); syscall(1, 1, "\\n", 1); }\nif (d != 0) { syscall(1, 1, "DIR=", 4); syscall(1, 1, d, strlen(d)); syscall(1, 1, "\\n", 1); }\nsyscall(60, 0);\n' > "$P/tests/sub/e.tcyr"
    PW=$(WINEPREFIX="$WP" HOME="$WHM" winepath -w "$P" 2> /dev/null)
    _wt() {   # $1 = the unit as cyrius.exe is given it; prints the rc, output in w1.out
        ( cd "$P" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
          WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' CYRIUS_HOME="$(WINEPREFIX="$WP" HOME="$WHM" winepath -w "$H" 2>/dev/null)" \
          CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 timeout 300 wine "$W/wbin/cyrius.exe" test "$1" ) > "$W/w1.out" 2>&1
        echo $?
    }
    r=$(_wt "$PW\\tests\\sub\\x.tcyr")
    if [ "$r" -eq 0 ]; then ok "W1a wine: cyrius.exe test $PW\\tests\\sub\\x.tcyr — test.cyml applies, rc 0"
    else bad "W1a wine: the absolute in-project unit (rc $r): $(grep -m1 -E 'FAIL|error' "$W/w1.out" | tr -d '\r')"; fi
    PF=$(printf '%s' "$PW" | tr '\\' /)
    PL=$(printf '%s' "$PW" | cut -c1 | tr 'A-Z' 'a-z')$(printf '%s' "$PW" | cut -c2-)
    r1=$(_wt "$PF/tests/sub/x.tcyr"); r2=$(_wt "$PL\\tests\\sub\\x.tcyr")
    if [ "$r1$r2" = "00" ]; then ok "W1b wine: the forward-slash and lower-case-drive spellings: rc 0"
    else bad "W1b wine: forward-slash rc $r1, lower-case drive rc $r2"; fi
    DR=$(printf '%s' "$PW" | cut -c1-2)
    r=$(_wt "${DR}tests\\sub\\x.tcyr")
    if [ "$r" -eq 1 ] && grep -q 'FAIL: .*tests.sub.x.tcyr (exit 1)' "$W/w1.out"; then ok "W1c wine: the drive-relative ${DR}tests\\sub\\x.tcyr stays outside: exit 1"
    else bad "W1c wine: the drive-relative unit (rc $r): $(grep -m1 -E 'FAIL|error|ok' "$W/w1.out" | tr -d '\r')"; fi
    r=$(_wt 'tests\sub\e.tcyr')
    wf=$(grep '^FILE=' "$W/w1.out" | tr -d '\r' | sed 's/^FILE=//'); wd=$(grep '^DIR=' "$W/w1.out" | tr -d '\r' | sed 's/^DIR=//')
    if [ "$r" -eq 0 ] && [ "$wd" = "$PW/tests\\sub" ] && [ "$wf" = "$PW/tests\\sub\\e.tcyr" ]; then
        ok "W1d wine: CYRIUS_TEST_FILE / CYRIUS_TEST_DIR are absolute ($wd)"
    else bad "W1d wine (rc $r): FILE='$wf' DIR='$wd' (want DIR '$PW/tests\\sub')"; fi
else
    echo "  SKIP: W8 — wine (or sha256sum) not found; the PE leg runs where wine is installed, and on cass"
fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
