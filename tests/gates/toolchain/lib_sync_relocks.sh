#!/bin/sh
# lib_sync_relocks.sh — 6.6.17. `cyrius lib sync` re-locks the files it wrote, and is held to
# the 6.6.4 stdlib-leaf guard like `cyrius deps`.
#
# THE DEFECT (kriya 1.7.3 and yantra, at their pin moves): `lib sync` copied the pinned
# snapshot over lib/ and never touched cyrius.lock, so every row for a file it changed kept the
# OLD pin's hash and `deps --verify` failed until the lock was regenerated from empty. Measured
# on the 6.6.17 slot-open CLI: pin 6.6.6 -> 6.6.7 with chrono moved, `lib sync --full`, then
# `deps --verify` reads "FAIL: lib/chrono.cyr (hash mismatch)".
# ⛔ The first cut of the fix rehashed ALL of lib/ after a sync, which re-opened what 6.6.4
# closed: a snapshot that moved under an unchanged pin was synced and locked in silence, and a
# local edit to a file the sync never wrote was locked too (review, 6.6.17).
#
# THE FIX: the sync plans every destination, runs the stdlib-leaf guard over all of them (an
# unchanged pin whose locked hash differs from the snapshot is refused by name and NOTHING is
# written; a pin change re-locks; `--relock` accepts), then re-hashes only the rows it wrote,
# drops rows for files gone from disk and keeps every other row byte for byte. A project with
# no cyrius.lock gets none from `lib sync` (its first lock comes from `cyrius deps`).
#
# AXES
#   1. Pin move, `lib sync --full` first: `deps --verify` passes, one line per .cyr (count from
#      find), every hash matches sha256sum, the trailer names the new pin; a second sync leaves
#      the lock byte-identical.
#   2. Pin move after `deps` re-stamped the lock: `lib sync` refuses by name (naming
#      `lib sync --relock`), writes nothing; `lib sync --full --relock` then verifies.
#   3. Same pin, moved snapshot: `lib sync` (and `--dry-run`) refuse, lock and lib/ unchanged,
#      and `cyrius deps` still refuses.
#   4. A locked file the sync does not write, edited locally: its row is kept and
#      `deps --verify` names it.
#   5. A file removed from lib/ loses its row.   6. A `commit` pin line survives.
#   7. `--no-lock` and `--dry-run` leave the lock byte-identical.
#   8. No cyrius.lock before the sync: none after it.
# Slot-open CLI: axes 1, 2, 3, 5 and 7 FAIL. The first-cut fix (5124f2a1): axes 2, 3, 4 and 8 FAIL.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=lib_sync_relocks
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v sha256sum > /dev/null 2>&1 || { echo "SKIP: $G: sha256sum missing — the expected hashes come from it"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $G: $*"; FAIL=1; }
ulimit -c 0 2>/dev/null

mkdir -p "$W/bin"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
chmod +x "$W/bin/cyrius"
CLI="$W/bin/cyrius"
# A throwaway home with two snapshots from THIS tree's lib/; 6.6.7 moves two leaves, one of
# them (chrono) outside the project's declared closure.
H="$W/home"
mkdir -p "$H/versions/6.6.6" "$H/versions/6.6.7" \
  && cp -r lib "$H/versions/6.6.6/lib" && cp -r lib "$H/versions/6.6.7/lib" \
  && echo '# moved in 6.6.7' >> "$H/versions/6.6.7/lib/chrono.cyr" \
  && echo '# moved in 6.6.7' >> "$H/versions/6.6.7/lib/string.cyr" \
  && printf '6.6.7\n' > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
P="$W/p"
_mkp() { rm -rf "$P"; mkdir -p "$P"
    printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' "$1" > "$P/cyrius.cyml"; }
_pin() { sed -i "s/^cyrius = \".*\"/cyrius = \"$1\"/" "$P/cyrius.cyml"; }
_cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CLI" "$@" ); }
_hashlines() { _n=$(grep -c '^[0-9a-f]\{64\}  ' "$1" 2>/dev/null); echo "${_n:-0}"; }   # grep -c exits 1 on 0
_hashes_true() {
    grep '^[0-9a-f]\{64\}  ' "$P/cyrius.lock" > "$W/lines"
    while read -r h p; do
        real=$( cd "$P" && sha256sum "$p" 2>/dev/null | cut -d' ' -f1 )
        [ "$real" = "$h" ] || { echo "$p locked as $h but hashes to ${real:-<unreadable>}"; return 1; }
    done < "$W/lines"
    return 0
}
_locked_at_666() {   # a project fully synced and locked at pin 6.6.6
    _mkp 6.6.6
    _cy lib sync --full > /dev/null 2>&1 && _cy deps > /dev/null 2>&1 && [ -f "$P/cyrius.lock" ] \
      || { echo "FAIL: $G: setup at pin 6.6.6 failed"; exit 1; }
}

# ── axis 1: pin move, `lib sync --full` first ───────────────────────────────────────────
x=0
_locked_at_666
_pin 6.6.7
rc=0; _cy lib sync --full > "$W/a1.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 1: lib sync --full after the pin move (rc=$rc):"; tail -3 "$W/a1.out" | sed 's/^/      /'; x=1; }
cmp -s "$P/lib/chrono.cyr" "$H/versions/6.6.7/lib/chrono.cyr" || { fail "axis 1: chrono was not synced"; x=1; }
rc=0; _cy deps --verify > "$W/a1v.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 1: deps --verify after lib sync --full (rc=$rc):"; grep -E 'FAIL|verified' "$W/a1v.out" | head -3 | sed 's/^/      /'; x=1; }
want=$(find "$P/lib" -name '*.cyr' | wc -l | tr -d ' '); got=$(_hashlines "$P/cyrius.lock")
[ "$got" = "$want" ] || { fail "axis 1: the lock has $got hash lines for $want .cyr files under lib/"; x=1; }
why=$(_hashes_true) || { fail "axis 1: $why"; x=1; }
[ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.7')" ] || { fail "axis 1: the trailer is '$(tail -1 "$P/cyrius.lock")', not the new pin"; x=1; }
cp "$P/cyrius.lock" "$W/a1.lock"; _cy lib sync --full > /dev/null 2>&1
cmp -s "$W/a1.lock" "$P/cyrius.lock" || { fail "axis 1: a second lib sync --full rewrote an already-correct lock"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: after the pin move, lib sync --full re-locked $got lines (sha256sum-confirmed); deps --verify passes; a resync is a no-op"

# ── axis 2: pin move after `deps` re-stamped the lock ────────────────────────────────────
x=0
_locked_at_666
_pin 6.6.7
_cy deps > /dev/null 2>&1
cp "$P/cyrius.lock" "$W/a2.lock"; cp "$P/lib/chrono.cyr" "$W/a2.chrono"
rc=0; _cy lib sync --full > "$W/a2.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'lib/chrono.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE' "$W/a2.out" \
  && grep -q 'cyrius lib sync --relock' "$W/a2.out"; } \
  || { fail "axis 2: lib sync did not refuse the stale chrono row by name (rc=$rc)"; x=1; }
cmp -s "$W/a2.lock" "$P/cyrius.lock" || { fail "axis 2: the refused sync rewrote cyrius.lock"; x=1; }
cmp -s "$W/a2.chrono" "$P/lib/chrono.cyr" || { fail "axis 2: the refused sync wrote lib/chrono.cyr"; x=1; }
rc=0; _cy lib sync --full --relock > "$W/a2r.out" 2>&1 || rc=$?
rc2=0; _cy deps --verify > "$W/a2v.out" 2>&1 || rc2=$?
{ [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ]; } || { fail "axis 2: lib sync --full --relock (rc=$rc) then deps --verify (rc=$rc2)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: a deps-stamped stale row is refused by name, nothing written; --relock accepts"

# ── axis 3: same pin, moved snapshot ─────────────────────────────────────────────────────
x=0
_locked_at_666
echo '# moved under the same pin' >> "$H/versions/6.6.6/lib/string.cyr"
cp "$P/cyrius.lock" "$W/a3.lock"; cp "$P/lib/string.cyr" "$W/a3.string"
rc=0; _cy lib sync > "$W/a3.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'lib/string.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE' "$W/a3.out" && grep -q 'reinstall that' "$W/a3.out"; } \
  || { fail "axis 3: lib sync accepted a snapshot that moved under an unchanged pin (rc=$rc)"; x=1; }
rc=0; _cy lib sync --dry-run > "$W/a3d.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 3: lib sync --dry-run reported success for a sync that refuses"; x=1; }
cmp -s "$W/a3.lock" "$P/cyrius.lock" || { fail "axis 3: cyrius.lock changed"; x=1; }
cmp -s "$W/a3.string" "$P/lib/string.cyr" || { fail "axis 3: lib/string.cyr was overwritten"; x=1; }
rc=0; _cy deps > "$W/a3x.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'DISAGREE' "$W/a3x.out"; } || { fail "axis 3: cyrius deps no longer refuses after the sync (rc=$rc)"; x=1; }
sed -i '$d' "$H/versions/6.6.6/lib/string.cyr"
cmp -s "$H/versions/6.6.6/lib/string.cyr" lib/string.cyr || { echo "FAIL: $G: axis 3 could not restore the snapshot"; exit 1; }
[ "$x" = 0 ] && echo "  ok: axis 3: a snapshot moved under the same pin is refused by lib sync (and --dry-run); lock, lib/ and the deps refusal unchanged"

# ── axis 4: a locked file the sync does not write keeps its row ─────────────────────────
x=0
_locked_at_666
printf 'fn gd(): i64 { return 1; }\n' > "$P/lib/gitdep.cyr"
_cy deps --lock > /dev/null 2>&1
echo '# local edit' >> "$P/lib/gitdep.cyr"
_cy lib sync > /dev/null 2>&1
rc=0; _cy deps --verify > "$W/a4.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'FAIL: lib/gitdep.cyr' "$W/a4.out"; } \
  || { fail "axis 4: a local edit to a file lib sync did not write was locked (rc=$rc)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: a file the sync did not write keeps its row; its local edit still fails --verify"

# ── axis 5: a removed file loses its row ─────────────────────────────────────────────────
x=0
_locked_at_666
rm -f "$P/lib/chrono.cyr"
rc=0; _cy lib sync > "$W/a5.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 5: the scoped lib sync failed (rc=$rc)"; x=1; }
grep -q 'lib/chrono.cyr' "$P/cyrius.lock" && { fail "axis 5: cyrius.lock still has a row for the removed lib/chrono.cyr"; x=1; }
rc=0; _cy deps --verify > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 5: deps --verify after the scoped sync (rc=$rc)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 5: a file gone from lib/ has no row after lib sync"

# ── axis 6: commit pins are carried forward ──────────────────────────────────────────────
x=0
pin=$(printf 'commit\t0123456789abcdef0123456789abcdef01234567\tdemo\thttps://example.invalid/demo\t1.0.0')
{ printf '%s\n' "$pin"; cat "$P/cyrius.lock"; } > "$W/lock" && cp "$W/lock" "$P/cyrius.lock"
_cy lib sync > /dev/null 2>&1
grep -qxF "$pin" "$P/cyrius.lock" || { fail "axis 6: the commit pin line was dropped by the re-lock"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 6: a commit pin survives the re-lock"

# ── axis 7: --no-lock and --dry-run write no lock ────────────────────────────────────────
x=0
_locked_at_666
rm -f "$P/lib/chrono.cyr"
cp "$P/cyrius.lock" "$W/before"
rc=0; _cy lib sync --full --no-lock > "$W/a7.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 7: lib sync --no-lock failed (rc=$rc):"; tail -2 "$W/a7.out" | sed 's/^/      /'; x=1; }
cmp -s "$W/before" "$P/cyrius.lock" || { fail "axis 7: lib sync --no-lock rewrote cyrius.lock"; x=1; }
rm -f "$P/lib/chrono.cyr"; _cy deps --lock > /dev/null 2>&1; cp "$P/cyrius.lock" "$W/before"
_cy lib sync --full --dry-run > /dev/null 2>&1
cmp -s "$W/before" "$P/cyrius.lock" || { fail "axis 7: lib sync --dry-run rewrote cyrius.lock"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 7: --no-lock and --dry-run leave cyrius.lock alone"

# ── axis 8: no lock before, none after ───────────────────────────────────────────────────
x=0
_mkp 6.6.6
rc=0; _cy lib sync > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 8: lib sync in a project with no lock failed (rc=$rc)"; x=1; }
[ -f "$P/cyrius.lock" ] && { fail "axis 8: lib sync created a cyrius.lock (the first lock is cyrius deps' to write)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 8: lib sync in a lockless project writes no lock"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: $G"
exit 0
