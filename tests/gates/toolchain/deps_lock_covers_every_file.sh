#!/bin/sh
# deps_lock_covers_every_file.sh — v6.6.6 bite 17d. `cyrius deps --lock` writes a line for EVERY
# `.cyr` under lib/, or it writes no lock at all. A file it cannot hash is never silently left out.
#
# ⛔ THE DEFECT (cbt/deps.cyr `_deps_lock_dir`, as of 6.6.5):
#     var hash = _sha256sum_file(path);
#     if (hash != 0) { ...write the line...; count = count + 1; }
# A file that could not be hashed skipped the write AND the count, so nothing above it ever knew.
# Measured: `chmod 000 lib/m2.cyr` in a 3-file project, then `cyrius deps --lock` ->
# "cyrius.lock: 2 deps locked", exit 0, and m2.cyr simply absent from cyrius.lock.
#
# ⚠ WHY THAT IS WORSE THAN A WRONG HASH. cyrius.lock is an INTEGRITY record, and `deps --verify`
# checks the lines that are IN it. A file with no line is a file with nothing to check — so the
# one entry an attacker (or a botched permission change) most wants missing is exactly the one
# the tool dropped, quietly, while reporting success. "This file could not be read" is the one
# thing a lock must never record as "this file is fine".
#
# ⭐ FAIL CLOSED, AND LEAVE THE OLD LOCK. The abort is in `cmd_deps_lock`, not in the recursive
# walker: `_aw_abort` discards the sibling temp so the previous cyrius.lock stays byte-for-byte,
# which is the right answer for a record you could not rebuild correctly. The counters are
# globals because `_deps_lock_dir` recurses into subdirectories.
#
# AXES
#   1. ANTI-VACUOUS: everything readable -> rc 0 and the lock has EXACTLY one line per `.cyr`
#      under lib/, the count DERIVED with `find` (not the tool's own printed number), including
#      a nested subdirectory; every hash equals an independent `sha256sum` of the same file.
#   2. A dangling `lib/<name>.cyr` symlink (unhashable for root and non-root alike): rc != 0,
#      the message NAMES the file, and cyrius.lock is byte-for-byte what it was before.
#   3. Two unhashable files: the message says "(and 1 more)", and with NO pre-existing lock none
#      is created — a failed lock must not leave a partial one.
#   4. STATIC: `_deps_lock_dir` RECORDS a hash failure (it does not `if (hash != 0)` past it) and
#      `cmd_deps_lock` aborts the handle on it. Self-tested on the 6.6.5 body.
#
# MUTATION LEDGER (measured 6.6.6; each mutant is a COPY of cbt/deps.cyr in the gate's scratch
# dir, compiled with the tree's build/cycc)
#   a. the 6.6.5 `if (hash != 0) { ... }` skip           -> axes 2, 3 and 4 FAIL (rc 0, "3 deps
#                                                           locked" over 4 files, lock rewritten
#                                                           without the missing entry)
#   b. the cmd_deps_lock abort removed (counter kept)    -> axes 2 and 3 FAIL (rc 0, lock written)
#   c. `_aw_abort` changed to `_aw_commit`               -> axes 2 and 3 FAIL (the lock is
#                                                           REWRITTEN without the entry)
#   d. axis-4 detector's record rule disabled            -> axis 4 self-test FAIL
#   e. axis-4 detector's abort rule disabled             -> axis 4 self-test FAIL
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: deps_lock_covers_every_file: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }
command -v sha256sum > /dev/null 2>&1 || { echo "FAIL: sha256sum missing — this gate's expected hashes come from it"; exit 1; }

CLI="$D/cyrius"
"$CC" < cbt/cyrius.cyr > "$CLI" 2> "$D/build.err"; brc=$?
if [ "$brc" -ne 0 ] || [ ! -s "$CLI" ]; then
    echo "FAIL: cbt/cyrius.cyr does not build (rc=$brc):"; tail -5 "$D/build.err" | sed 's/^/      /'; exit 1
fi
grep -q '^warning: undefined function' "$D/build.err" && { echo "FAIL: the CLI compiled with undefined functions:"; grep '^warning: undefined' "$D/build.err" | sed 's/^/      /'; exit 1; }
chmod +x "$CLI"
mkdir -p "$D/home/versions/0.0.0/bin" "$D/home/versions/0.0.0/lib"
printf '0.0.0\n' > "$D/home/current"

# _proj <name> — a scratch consumer project with 3 lib modules, one of them nested. NOT the
# cyrius repo (cmd_deps_lock skips itself there), and never the real tree.
_proj() {
    P="$D/$1"
    rm -rf "$P"
    mkdir -p "$P/lib/nested" || return 1
    printf '[package]\nname = "lockproj"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
    printf 'fn a(): i64 { return 1; }\n' > "$P/lib/m1.cyr"
    printf 'fn b(): i64 { return 2; }\n' > "$P/lib/m2.cyr"
    printf 'fn c(): i64 { return 3; }\n' > "$P/lib/nested/m3.cyr"
}
_lock() { ( cd "$1" && CYRIUS_HOME="$D/home" exec "$CLI" deps --lock ) > "$2" 2>&1; }

# ── axis 1: ANTI-VACUOUS — one line per .cyr, hashes independently recomputed ──
_proj a1 || { echo "FAIL: cannot stage the axis-1 project"; exit 1; }
rc=0; _lock "$D/a1" "$D/a1.out" || rc=$?
x=0
[ "$rc" -eq 0 ] || { fail "axis 1: a clean lock failed (rc=$rc):"; sed 's/^/      /' "$D/a1.out" | head -3; x=1; }
want=$(find "$D/a1/lib" -name '*.cyr' | wc -l | tr -d ' ')
[ "$want" -eq 3 ] || { fail "axis 1: the fixture has $want .cyr files, expected 3"; x=1; }
got=$(grep -c '^[0-9a-f]\{64\}  ' "$D/a1/cyrius.lock" 2>/dev/null || echo 0)
[ "$got" = "$want" ] || { fail "axis 1: cyrius.lock has $got hash lines for $want .cyr files under lib/"; x=1; }
# every hash recomputed independently
grep '^[0-9a-f]\{64\}  ' "$D/a1/cyrius.lock" > "$D/a1.hashlines" 2>/dev/null || : > "$D/a1.hashlines"
while read -r h p; do
    real=$( cd "$D/a1" && sha256sum "$p" 2>/dev/null | cut -d' ' -f1 )
    [ "$real" = "$h" ] || { fail "axis 1: $p is locked as $h but hashes to ${real:-<unreadable>}"; x=1; }
done < "$D/a1.hashlines"
[ "$x" = 0 ] && echo "  ok: axis 1: $got hash lines for the $want .cyr files under lib/ (incl. the nested one), every hash confirmed by sha256sum"

# ── axis 2: one unhashable file -> fail, name it, keep the old lock ──
_proj a2 || { echo "FAIL: cannot stage the axis-2 project"; exit 1; }
rc=0; _lock "$D/a2" "$D/a2.pre" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: axis 2 setup: the clean lock failed"; exit 1; }
cp "$D/a2/cyrius.lock" "$D/a2.lockbefore"
ln -sfn /nonexistent/gone.cyr "$D/a2/lib/dangle.cyr"
rc=0; _lock "$D/a2" "$D/a2.out" || rc=$?
x=0
[ "$rc" -ne 0 ] || { fail "axis 2: a lock that could not cover lib/dangle.cyr exited 0:"; sed 's/^/      /' "$D/a2.out" | head -2; x=1; }
grep -q 'lib/dangle.cyr' "$D/a2.out" || { fail "axis 2: the error does not name the file it could not hash:"; sed 's/^/      /' "$D/a2.out" | head -3; x=1; }
cmp -s "$D/a2/cyrius.lock" "$D/a2.lockbefore" || { fail "axis 2: cyrius.lock was REWRITTEN by a failed lock ($(wc -c < "$D/a2/cyrius.lock" | tr -d ' ') bytes, was $(wc -c < "$D/a2.lockbefore" | tr -d ' '))"; x=1; }
ls -A "$D/a2" | grep -q 'cyrtmp' && { fail "axis 2: a failed lock left a temp behind"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: an unhashable lib/*.cyr -> rc $rc, named in the error, cyrius.lock byte-for-byte as it was"

# ── axis 3: two unhashable files, and no pre-existing lock ──
_proj a3 || { echo "FAIL: cannot stage the axis-3 project"; exit 1; }
ln -sfn /nonexistent/gone1.cyr "$D/a3/lib/d1.cyr"
ln -sfn /nonexistent/gone2.cyr "$D/a3/lib/nested/d2.cyr"
rc=0; _lock "$D/a3" "$D/a3.out" || rc=$?
x=0
[ "$rc" -ne 0 ] || { fail "axis 3: two unhashable files exited 0"; x=1; }
grep -q '(and 1 more)' "$D/a3.out" || { fail "axis 3: the error does not count the other unhashable file:"; sed 's/^/      /' "$D/a3.out" | head -3; x=1; }
[ -e "$D/a3/cyrius.lock" ] && { fail "axis 3: a failed lock CREATED cyrius.lock ($(wc -c < "$D/a3/cyrius.lock" | tr -d ' ') bytes) where there was none"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 3: two unhashable files -> rc $rc, both counted, no cyrius.lock created"

# ── axis 4: STATIC — the failure is recorded, and the lock handle is ABORTED ──
_fn_body() { awk -v want="$2" '$0 ~ "^fn " want "\\(" { inb = 1 } inb && /^}/ { print; inb = 0 } inb { print }' "$1"; }
_judge() {   # _judge <deps.cyr> -> verdicts, empty when clean
    v=""
    _fn_body "$1" _deps_lock_dir > "$D/j.walk"
    _fn_body "$1" cmd_deps_lock > "$D/j.cmd"
    [ -s "$D/j.walk" ] || { printf 'no_walker'; return; }
    [ -s "$D/j.cmd" ] || { printf 'no_cmd'; return; }
    grep -qE '_dep_lock_unhashable = _dep_lock_unhashable \+ 1' "$D/j.walk" || v="$v failure_not_recorded"
    grep -qE 'if \(hash != 0\)' "$D/j.walk" && v="$v skips_on_hash_failure"
    grep -qE '_aw_abort\(lock_h\)' "$D/j.cmd" || v="$v no_abort"
    grep -qE 'if \(_dep_lock_unhashable != 0\)' "$D/j.cmd" || v="$v no_check"
    printf '%s' "${v# }"
}
x=0
verdict=$(_judge cbt/deps.cyr)
[ -z "$verdict" ] || { fail "axis 4: the lock walker can still drop a file it cannot hash:$verdict"; x=1; }
cat > "$D/prefix.cyr" <<'CYR'
fn _deps_lock_dir(dir, lock_h): i64 {
        var hash = _sha256sum_file(path);
        if (hash != 0) {
            _aw_write(lock_h, hash, 64);
            count = count + 1;
        }
    return count;
}
fn cmd_deps_lock(): i64 {
    var count = _deps_lock_dir("lib", lock_h);
    if (_aw_commit(lock_h) != 0) { return 1; }
    return 0;
}
CYR
want='failure_not_recorded skips_on_hash_failure no_abort no_check'
got=$(_judge "$D/prefix.cyr")
[ "$got" = "$want" ] || { fail "axis 4 self-test: the 6.6.5 body judged '$got', expected '$want' — the detector is blind to a shape it must catch"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: a hash failure is recorded and aborts the lock (detector self-tested on the 6.6.5 body)"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: deps_lock_covers_every_file (4 axes)"
