#!/bin/sh
# deps_lock_new_leaf_locked.sh — 6.6.9 bite 9. cyrius.lock covers EVERY .cyr `cyrius deps`
# leaves in lib/, and `deps --verify` FAILS on one it does not cover.
#
# ⛔ THE DEFECT (filed by patra 2026-09-23, its 1.15.0 cut; reproduced on 6.6.6-6.6.8):
#   1. a stdlib leaf newly declared under a lock stamped at the current pin was vendored into
#      lib/ and NEVER locked — `cyrius deps` printed nothing, and `cyrius build` did not lock
#      it either (patra: 29 lock lines over 31 files);
#   2. `cyrius deps --verify` checked only the lines the lock HAS, so that file — even
#      tampered — verified "15 verified, 0 failed", rc 0;
#   3. a stdlib-only project never got a lock at all from `cyrius deps` / `cyrius build`
#      (41 ecosystem repos had none), and an EMPTY lock was reported as "no cyrius.lock found".
# Root cause: cmd_deps wrote the lock on `copied > 0` — a count of NAMED git/path deps — or on
# --relock / a legacy-or-moved pin stamp; stdlib leaves never counted. The verifier had no
# walk of lib/.
#
# ⭐ THE FIX: a vendored leaf the loaded lock has no line for (a new leaf, or every leaf when
# there is no lock) triggers the lock write; `--verify` walks lib/ through `_deps_lock_files`,
# the SAME walker cmd_deps_lock writes from, and fails each uncovered file by name.
#
# AXES
#   1. The filing's repro, VERBATIM (pin "6.6.6", syscalls + string, then + chrono): the first
#      `cyrius deps` writes a lock with one line per .cyr under lib/ (count DERIVED with find,
#      every hash re-confirmed by sha256sum); adding chrono locks lib/chrono.cyr; tampering it
#      makes `--verify` exit non-zero naming it.
#   2. `--verify` FAILS a .cyr under lib/ that has no lock line, by name (anti-vacuous: the
#      same tree verifies rc 0 before the file is planted).
#   3. An EMPTY cyrius.lock is present-but-empty: `--verify` says so and names every file;
#      the next `cyrius deps` writes the full lock.
#   4. `cyrius build` of a fresh stdlib-only project writes the first lock.
#   5. ANTI-CHURN: a second `cyrius deps` with nothing changed leaves the lock byte-identical
#      and prints no lock line (the new trigger fires only on an uncovered file).
#   6. STATIC: cmd_deps_verify and _deps_lock_dir both take their file list from
#      `_deps_lock_files` (one walker — the checker cannot drift from the writer).
#   7. Help: `deps --help` no longer says deps are "symlinked into lib/" and documents that
#      --relock locks files --verify reports; the top-level line lists --relock.
#
# MUTATION LEDGER (measured 6.6.9, each a copy of the tree with ONE edit, CLI rebuilt):
#   a. the `_dep_lock_new_leaf` trigger removed from cmd_deps' write condition
#                                                   -> axes 1, 3, 4 FAIL (no first lock,
#                                                      chrono unlocked)
#   b. cmd_deps_verify's lib/ walk removed           -> axes 2, 3 FAIL (rc 0 over an unlocked
#                                                      file; the empty lock "verifies")
#   c. the empty-lock arm back to "no cyrius.lock found"
#                                                   -> axis 3 FAIL
#   d. the new-leaf flag set on EVERY copy (not only an uncovered one)
#                                                   -> axis 5 FAIL (the lock is rewritten on
#                                                      every resolve)
#   pre-fix tree (the 6.6.9 slot-open commit bd6dad5f) -> axes 1-7 FAIL
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: deps_lock_new_leaf_locked: $CC missing"; exit 1; }
command -v sha256sum > /dev/null 2>&1 || { echo "FAIL: deps_lock_new_leaf_locked: sha256sum missing — the expected hashes come from it"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: deps_lock_new_leaf_locked: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
ulimit -c 0 2>/dev/null

mkdir -p "$W/bin"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
cp "$CC" "$W/bin/cycc" && chmod +x "$W/bin/cyrius" "$W/bin/cycc" || { echo "FAIL: cannot stage $W/bin"; exit 1; }
CLI="$W/bin/cyrius"
# A throwaway home holding the pinned snapshot the filing names ("6.6.6"), copied from THIS
# tree's lib/ — nothing resolves out of the live store.
H="$W/home"
mkdir -p "$H/versions/6.6.6" && cp -r lib "$H/versions/6.6.6/lib" && printf '6.6.6\n' > "$H/current" \
  || { echo "FAIL: cannot stage the throwaway home"; exit 1; }
# CYRIUS_RESOLVED=1: never re-exec into a pinned version's CLI; this tree's is under test.
_cy() { _d=$1; shift; ( cd "$_d" && CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CLI" "$@" ); }
_hashlines() { _n=$(grep -c '^[0-9a-f]\{64\}  ' "$1" 2>/dev/null); echo "${_n:-0}"; }   # grep -c exits 1 on 0
_ncyr() { find "$1/lib" -name '*.cyr' | wc -l | tr -d ' '; }
_manifest() { printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = [%s]\n' "$2" > "$1/cyrius.cyml"; }

# ── axis 1: the filing's repro ────────────────────────────────────────────────────────
P="$W/r"; mkdir -p "$P"
_manifest "$P" '"syscalls", "string"'
x=0
rc=0; _cy "$P" deps > "$W/a1a.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 1: the first cyrius deps failed (rc=$rc):"; sed 's/^/      /' "$W/a1a.out" | head -3; x=1; }
if [ ! -f "$P/cyrius.lock" ]; then
    fail "axis 1 (case 3): the first cyrius deps of a stdlib-only project wrote NO cyrius.lock"; x=1
else
    want=$(_ncyr "$P"); got=$(_hashlines "$P/cyrius.lock")
    [ "$want" -ge 2 ] || { fail "axis 1: the fixture vendored only $want .cyr files"; x=1; }
    [ "$got" = "$want" ] || { fail "axis 1 (case 3): the first lock has $got hash lines for $want .cyr files under lib/"; x=1; }
    grep '^[0-9a-f]\{64\}  ' "$P/cyrius.lock" > "$W/a1.lines"
    while read -r h p; do
        real=$( cd "$P" && sha256sum "$p" 2>/dev/null | cut -d' ' -f1 )
        [ "$real" = "$h" ] || { fail "axis 1: $p is locked as $h but hashes to ${real:-<unreadable>}"; x=1; }
    done < "$W/a1.lines"
fi
sed -i 's/"string"\]/"string", "chrono"]/' "$P/cyrius.cyml"
grep -q '"chrono"' "$P/cyrius.cyml" || { echo "FAIL: axis 1 setup: the manifest edit did not land"; exit 1; }
rc=0; _cy "$P" deps > "$W/a1b.out" 2>&1 || rc=$?
[ -f "$P/lib/chrono.cyr" ] || { fail "axis 1: chrono was not vendored (rc=$rc)"; x=1; }
n=$(grep -c 'lib/chrono.cyr' "$P/cyrius.lock" 2>/dev/null); n=${n:-0}
[ "$n" = 1 ] || { fail "axis 1 (case 1): lib/chrono.cyr — declared and vendored — has $n lines in cyrius.lock, expected 1"; x=1; }
want=$(_ncyr "$P"); got=$(_hashlines "$P/cyrius.lock")
[ "$got" = "$want" ] || { fail "axis 1 (case 1): the lock has $got hash lines for $want .cyr files"; x=1; }
echo '# tampered' >> "$P/lib/chrono.cyr"
rc=0; _cy "$P" deps --verify > "$W/a1c.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'FAIL: lib/chrono.cyr' "$W/a1c.out"; } \
  || { fail "axis 1 (case 2): a TAMPERED new leaf verified (rc=$rc):"; sed 's/^/      /' "$W/a1c.out" | tail -2; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: the filing's repro — a first lock of $(_hashlines "$P/cyrius.lock") lines (one per .cyr, sha256sum-confirmed), the new leaf locked, its tamper caught"

# ── axis 2: an unlocked file under lib/ FAILS --verify, by name ───────────────────────
P2="$W/r2"; mkdir -p "$P2"
_manifest "$P2" '"syscalls", "string"'
_cy "$P2" deps > /dev/null 2>&1
x=0
rc=0; _cy "$P2" deps --verify > "$W/a2a.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 2 (anti-vacuous): a fully locked lib/ does not verify (rc=$rc):"; sed 's/^/      /' "$W/a2a.out" | tail -2; x=1; }
mkdir -p "$P2/lib/sub"
printf 'fn planted(): i64 { return 1; }\n' > "$P2/lib/sub/planted.cyr"
rc=0; _cy "$P2" deps --verify > "$W/a2b.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 2: a .cyr under lib/ with NO lock line verified rc 0:"; sed 's/^/      /' "$W/a2b.out" | tail -2; x=1; }
grep -q 'FAIL: lib/sub/planted.cyr (not in cyrius.lock' "$W/a2b.out" \
  || { fail "axis 2: the unlocked file is not named:"; sed 's/^/      /' "$W/a2b.out" | tail -2; x=1; }
grep -q ' 1 failed' "$W/a2b.out" || { fail "axis 2: the unlocked file is not counted as failed: $(tail -1 "$W/a2b.out")"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: a nested lib/ file with no lock line fails --verify by name (the same tree verifies rc 0 without it)"

# ── axis 3: an EMPTY lock is present-but-empty ─────────────────────────────────────────
x=0
rm -f "$P2/lib/sub/planted.cyr"
: > "$P2/cyrius.lock"
rc=0; _cy "$P2" deps --verify > "$W/a3a.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 3: an EMPTY lock over $(_ncyr "$P2") files verified rc 0"; x=1; }
grep -q 'no cyrius.lock found' "$W/a3a.out" && { fail "axis 3: an empty lock is reported as MISSING"; x=1; }
grep -q 'cyrius.lock is empty' "$W/a3a.out" || { fail "axis 3: the empty lock is not reported as empty:"; sed 's/^/      /' "$W/a3a.out" | head -2; x=1; }
nf=$(grep -c 'not in cyrius.lock' "$W/a3a.out" || true)
[ "$nf" = "$(_ncyr "$P2")" ] || { fail "axis 3: $nf files named as not in the lock, $(_ncyr "$P2") under lib/"; x=1; }
_cy "$P2" deps > "$W/a3b.out" 2>&1
got=$(_hashlines "$P2/cyrius.lock")
[ "$got" = "$(_ncyr "$P2")" ] || { fail "axis 3: cyrius deps over an empty lock wrote $got hash lines for $(_ncyr "$P2") files"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 3: an empty lock is reported as empty and fails --verify naming all $nf files; the next cyrius deps writes all $got lines"

# ── axis 4: cyrius build writes the first lock ────────────────────────────────────────
P4="$W/r4"; mkdir -p "$P4/src"
_manifest "$P4" '"syscalls", "string"'
printf 'fn main(): i64 { return strlen("abcd"); }\nvar r = main();\nsyscall(60, r);\n' > "$P4/src/main.cyr"
x=0
rc=0; _cy "$P4" build src/main.cyr out > "$W/a4.out" 2>&1 || rc=$?
erc=0; [ -s "$P4/out" ] && { ( exec "$P4/out" ) > /dev/null 2>&1 || erc=$?; }
{ [ "$rc" -eq 0 ] && [ "$erc" -eq 4 ]; } || { fail "axis 4: the build failed (rc=$rc, binary exits $erc, expected 4):"; tail -3 "$W/a4.out" | sed 's/^/      /'; x=1; }
if [ -f "$P4/cyrius.lock" ]; then
    got=$(_hashlines "$P4/cyrius.lock")
    [ "$got" = "$(_ncyr "$P4")" ] || { fail "axis 4: the build's lock has $got lines for $(_ncyr "$P4") files"; x=1; }
else
    fail "axis 4: cyrius build of a stdlib-only project wrote no cyrius.lock"; x=1
fi
[ "$x" = 0 ] && echo "  ok: axis 4: cyrius build of a fresh stdlib-only project writes the first lock ($got lines)"

# ── axis 5: ANTI-CHURN ─────────────────────────────────────────────────────────────────
x=0
cp "$P4/cyrius.lock" "$W/a5.before"
rc=0; _cy "$P4" deps > "$W/a5.out" 2>&1 || rc=$?
cmp -s "$P4/cyrius.lock" "$W/a5.before" || { fail "axis 5: a no-change cyrius deps REWROTE the lock"; x=1; }
grep -q 'cyrius.lock:' "$W/a5.out" && { fail "axis 5: a no-change cyrius deps re-locked: $(grep 'cyrius.lock:' "$W/a5.out")"; x=1; }
[ "$rc" -eq 0 ] || { fail "axis 5: a no-change cyrius deps failed (rc=$rc)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 5: a no-change cyrius deps leaves the lock byte-identical and says nothing"

# ── axis 6: STATIC — one walker ────────────────────────────────────────────────────────
_fn_body() { awk -v want="$2" '$0 ~ "^fn " want "\\(" { inb = 1 } inb && /^}/ { print; inb = 0 } inb { print }' "$1"; }
x=0
_fn_body cbt/deps.cyr cmd_deps_verify > "$W/v.body"
_fn_body cbt/deps.cyr _deps_lock_dir > "$W/l.body"
[ -s "$W/v.body" ] && [ -s "$W/l.body" ] || { fail "axis 6: cmd_deps_verify / _deps_lock_dir not found in cbt/deps.cyr"; x=1; }
grep -q '_deps_lock_files("lib")' "$W/v.body" || { fail "axis 6: cmd_deps_verify does not walk lib/ through _deps_lock_files"; x=1; }
grep -q '_deps_lock_files(dir)' "$W/l.body" || { fail "axis 6: _deps_lock_dir does not take its list from _deps_lock_files"; x=1; }
grep -q 'dir_list' "$W/l.body" && { fail "axis 6: _deps_lock_dir walks the directory itself again (a second walker)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 6: the lock writer and --verify share _deps_lock_files"

# ── axis 7: help text ──────────────────────────────────────────────────────────────────
x=0
_cy "$W" deps --help > "$W/a7a.out" 2>&1
_cy "$W" help > "$W/a7b.out" 2>&1
grep -q 'symlinked into lib' "$W/a7a.out" && { fail "axis 7: deps --help still says deps are symlinked into lib/"; x=1; }
grep -q 'not in cyrius.lock' "$W/a7a.out" || { fail "axis 7: deps --help does not say --relock locks files --verify reports as not in the lock"; x=1; }
grep -E '^  deps ' "$W/a7b.out" | grep -q -- '--relock' || { fail "axis 7: the top-level help line for deps does not list --relock: $(grep -E '^  deps ' "$W/a7b.out")"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 7: the help describes what --relock and --verify now do"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: deps_lock_new_leaf_locked (7 axes — every vendored leaf locked, the first lock written, an unlocked file fails --verify)"
