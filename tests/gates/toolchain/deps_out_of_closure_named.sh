#!/bin/sh
# deps_out_of_closure_named.sh — 6.7.12. A `cyrius deps` resolve NAMES every lib/ file it did not
# vendor (outside the declared footprint), and writes and deletes nothing more than before.
#
# THE DEFECT (darshana 1.1.3, filed 2026-10-12: issues/2026-10-12-deps-keeps-a-removed-stdlib-
# leaf-vendored-and-locked.md). A resolve copies the declared closure into lib/ and the lock
# covers ALL of lib/, but nothing ever removes a file: a leaf dropped from `[deps] stdlib` stayed
# vendored and locked, `deps --verify` agreed (`16 verified, 0 failed` where a fresh resolve of
# the same manifest locks 15), and nothing reported it.
#
# THE FIX: every path the resolve vendors (written or already identical) is recorded at the one
# write choke point (`_dep_copy_file`), and after a successful default resolve each lib/ `.cyr`
# outside that set is named on stderr, with `rm <file> && cyrius deps --lock` to drop it. Notice
# only: lib/ and cyrius.lock are what they were. Silent when lib/ holds the whole pinned snapshot
# (`lib sync --full` vendors files outside the closure on purpose), and under -q.
#
# ROWS
#   R1  the filed repro: drop `vec` → rc 0, exactly one file named, lib/vec.cyr; the lock
#       byte-unchanged (its vec row kept), lib/vec.cyr kept, `deps --verify` 16 verified
#   R1b the remedy it names: `rm lib/vec.cyr && cyrius deps --lock` → no vec row, 15 verified,
#       and the next `deps` says nothing
#   R1q `deps -q` on the R1 state names nothing
#   R2  the same manifest resolved into an empty directory: silent (anti-vacuous for R1)
#   R3  a `lib sync --full` project: `deps` silent, twice (the identical-copy path)
#   R4  a named dep's module (lib/dd.cyr) and a `[test] stdlib` leaf are never named — on the
#       first resolve (written) and the second (unchanged)
#   R5  the named dep dropped from the manifest: its module IS named, alone
# Mutations (measured, one at a time on cbt/deps.cyr): the notice call dropped → R1 R5 RED; the
# identical-copy path not recorded in the closure → R1 R1b R4 R5 RED (every unchanged file named;
# R3 stays silent, its lib/ holding the whole snapshot).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_out_of_closure_named
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found (R4 / R5 need a file:// origin)"; exit 77; }
command -v sha256sum > /dev/null 2>&1 || { echo "SKIP: $G: sha256sum missing — cyrius.lock is written from it"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

mkdir -p "$W/bin"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
chmod +x "$W/bin/cyrius"
CLI="$W/bin/cyrius"
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V" "$H/deps" && cp -r lib "$H/versions/$V/lib" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
mkdir -p "$W/o/dd/dist" && printf 'fn dd_f(): i64 { return 1; }\n' > "$W/o/dd/dist/dd.cyr" \
  && ( cd "$W/o/dd" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) \
  || { echo "FAIL: $G: cannot build the dd origin"; exit 1; }

P="$W/p"
_cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CLI" "$@" ); }
_mkp() {   # $1 = the [deps] stdlib list; $2 = extra manifest text
    rm -rf "$P"; mkdir -p "$P"
    printf '[package]\nname = "lockprune"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "main.cyr"\noutput = "build/main"\n\n[deps]\nstdlib = [%s]\n%b' "$V" "$1" "$2" > "$P/cyrius.cyml"
    printf 'syscall(SYS_EXIT, 0);\n' > "$P/main.cyr"
}
NOTE='outside the declared footprint'
named() { grep '^  lib/' "$1" | sed 's/^  //' | tr '\n' ' ' | sed 's/ $//'; }   # the files a note lists

# ── R1: the filed repro ──────────────────────────────────────────────────────────────────────
_mkp '"syscalls", "alloc", "vec"'
_cy deps > "$W/r1a.out" 2>&1 || bad "R1 setup: the first deps failed: $(tail -2 "$W/r1a.out")"
grep -q "$NOTE" "$W/r1a.out" && bad "R1 setup: the first resolve already named a file: $(named "$W/r1a.out")"
cp "$P/cyrius.lock" "$W/r1.lock"
sed -i 's/, "vec"\]/]/' "$P/cyrius.cyml"
rc=0; _cy deps > "$W/r1.out" 2>&1 || rc=$?
v=0; _cy deps --verify > "$W/r1v.out" 2>&1 || v=$?
if [ "$rc" -eq 0 ] && grep -q "^note: 1 file in lib/ is $NOTE" "$W/r1.out" && [ "$(named "$W/r1.out")" = "lib/vec.cyr" ] \
   && grep -qF '`rm <file> && cyrius deps --lock` drops one from lib/ and cyrius.lock' "$W/r1.out" \
   && cmp -s "$W/r1.lock" "$P/cyrius.lock" && grep -q '  lib/vec.cyr$' "$P/cyrius.lock" && [ -f "$P/lib/vec.cyr" ] \
   && [ "$v" -eq 0 ] && grep -q '^16 verified, 0 failed$' "$W/r1v.out"; then
    ok "R1 vec dropped from [deps] stdlib: rc 0, the note names lib/vec.cyr alone; lock byte-unchanged, file kept, 16 verified"
else bad "R1 (rc=$rc, verify rc=$v '$(tail -1 "$W/r1v.out")', named '$(named "$W/r1.out")'): $(head -3 "$W/r1.out")"; fi

# ── R1q: -q names nothing ──────────────────────────────────────────────────────────────────
rc=0; _cy deps -q > "$W/r1q.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q "$NOTE" "$W/r1q.out"; then ok "R1q deps -q: no note"
else bad "R1q (rc=$rc): $(head -2 "$W/r1q.out")"; fi

# ── R1b: the remedy the note names ───────────────────────────────────────────────────────────
rm -f "$P/lib/vec.cyr"
rc=0; _cy deps --lock > "$W/r1b.out" 2>&1 || rc=$?
v=0; _cy deps --verify > "$W/r1bv.out" 2>&1 || v=$?
rc2=0; _cy deps > "$W/r1b2.out" 2>&1 || rc2=$?
if [ "$rc" -eq 0 ] && ! grep -q 'lib/vec.cyr' "$P/cyrius.lock" && [ "$v" -eq 0 ] && grep -q '^15 verified, 0 failed$' "$W/r1bv.out" \
   && [ "$rc2" -eq 0 ] && ! grep -q "$NOTE" "$W/r1b2.out"; then
    ok "R1b rm lib/vec.cyr && cyrius deps --lock: no vec row, 15 verified, the next deps says nothing"
else bad "R1b (rc=$rc/$rc2, verify rc=$v '$(tail -1 "$W/r1bv.out")'): $(grep -c 'lib/vec.cyr' "$P/cyrius.lock") vec row(s); $(head -2 "$W/r1b2.out")"; fi

# ── R2: the same manifest in an empty directory ──────────────────────────────────────────────
_mkp '"syscalls", "alloc"'
rc=0; _cy deps > "$W/r2.out" 2>&1 || rc=$?
n=$(grep -c '^[0-9a-f]\{64\}  ' "$P/cyrius.lock" 2>/dev/null)
if [ "$rc" -eq 0 ] && ! grep -q "$NOTE" "$W/r2.out" && [ "${n:-0}" -eq 15 ]; then ok "R2 a fresh resolve of the same manifest: 15 locked, no note"
else bad "R2 (rc=$rc, ${n:-0} rows): $(head -2 "$W/r2.out")"; fi

# ── R3: a `lib sync --full` project ─────────────────────────────────────────────────────────
_mkp '"syscalls", "string"'
_cy lib sync --full > "$W/r3s.out" 2>&1 || bad "R3 setup: lib sync --full failed: $(tail -2 "$W/r3s.out")"
rc=0; _cy deps > "$W/r3a.out" 2>&1 || rc=$?
rc2=0; _cy deps > "$W/r3b.out" 2>&1 || rc2=$?
nl=$(find "$P/lib" -name '*.cyr' | wc -l | tr -d ' ')
if [ "$rc$rc2" = "00" ] && [ "$nl" -gt 50 ] && ! grep -q "$NOTE" "$W/r3a.out" "$W/r3b.out"; then
    ok "R3 lib sync --full ($nl files): deps twice, no note"
else bad "R3 (rc=$rc/$rc2, $nl files): $(named "$W/r3a.out" | cut -c1-120) | $(named "$W/r3b.out" | cut -c1-120)"; fi

# ── R4: a named dep's module and a test-scope leaf are in the footprint ──────────────────────
_mkp '"syscalls"' "\n[deps.dd]\ngit = \"file://$W/o/dd\"\ntag = \"v1\"\nmodules = [\"dist/dd.cyr\"]\n\n[test]\nstdlib = [\"assert\"]\n"
rc=0; _cy deps > "$W/r4a.out" 2>&1 || rc=$?
rc2=0; _cy deps > "$W/r4b.out" 2>&1 || rc2=$?
if [ "$rc$rc2" = "00" ] && [ -f "$P/lib/dd.cyr" ] && [ -f "$P/lib/assert.cyr" ] && ! grep -q "$NOTE" "$W/r4a.out" "$W/r4b.out"; then
    ok "R4 lib/dd.cyr (a named dep's module) and lib/assert.cyr ([test] stdlib): not named, written or unchanged"
else bad "R4 (rc=$rc/$rc2): $(named "$W/r4a.out") | $(named "$W/r4b.out") $(grep -m1 -i error "$W/r4a.out")"; fi

# ── R5: the named dep dropped from the manifest ──────────────────────────────────────────────
sed -i '/^\[deps.dd\]/,/^modules/d' "$P/cyrius.cyml"
grep -q 'deps.dd' "$P/cyrius.cyml" && bad "R5 setup: [deps.dd] still in the manifest"
rc=0; _cy deps > "$W/r5.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(named "$W/r5.out")" = "lib/dd.cyr" ] && [ -f "$P/lib/dd.cyr" ]; then
    ok "R5 [deps.dd] dropped: lib/dd.cyr named alone, kept"
else bad "R5 (rc=$rc): named '$(named "$W/r5.out")'"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
