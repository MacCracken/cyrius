#!/bin/sh
# lib_sync_relocks.sh — 6.6.17. `cyrius lib sync` re-locks cyrius.lock from what it vendored.
#
# THE DEFECT (kriya 1.7.3 and yantra, at their pin moves): `lib sync` copied the pinned
# snapshot over lib/ and never touched cyrius.lock, so every row for a file the sync changed
# kept the OLD pin's hash. `cyrius deps` re-locks only after its own resolve, and that walks
# the build's closure, so the rows for the files a repo does not vendor stayed stale until the
# lock was regenerated from empty. Measured on the 6.6.17 slot-open CLI: pin 6.6.6 -> 6.6.7
# with chrono moved, `deps` then `lib sync --full`, and `deps --verify` reads
# "FAIL: lib/chrono.cyr (hash mismatch)".
#
# THE FIX: a sync that wrote lib/ re-locks through cmd_deps_lock (the `deps --lock` writer),
# commit pins carried forward. `--dry-run` and `--no-lock` write no lock.
#
# AXES
#   1. The pin-move repro: after `lib sync --full`, `deps --verify` passes, the lock has one
#      line per .cyr under lib/ (count from find), every hash matches sha256sum, and the
#      trailer names the new pin.
#   2. A file removed from lib/ loses its row on the next (scoped) `lib sync`.
#   3. A `commit` pin line in the lock survives the re-lock.
#   4. `lib sync --no-lock` and `lib sync --dry-run` leave the lock byte-identical.
# Old code: axes 1, 2 and 4 FAIL (axis 4 because `--no-lock` is refused for `lib`).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: lib_sync_relocks: $CC missing"; exit 1; }
command -v sha256sum > /dev/null 2>&1 || { echo "SKIP: lib_sync_relocks: sha256sum missing — the expected hashes come from it"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: lib_sync_relocks: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: lib_sync_relocks: $*"; FAIL=1; }
ulimit -c 0 2>/dev/null

mkdir -p "$W/bin"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: lib_sync_relocks: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
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
  || { echo "FAIL: lib_sync_relocks: cannot stage the throwaway home"; exit 1; }
P="$W/p"; mkdir -p "$P"
printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > "$P/cyrius.cyml"
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

# ── axis 1: the pin-move repro ──────────────────────────────────────────────────────────
x=0
_cy lib sync --full > /dev/null 2>&1 && _cy deps > /dev/null 2>&1 \
  || { echo "FAIL: lib_sync_relocks: setup at pin 6.6.6 failed"; exit 1; }
sed -i 's/cyrius = "6.6.6"/cyrius = "6.6.7"/' "$P/cyrius.cyml"
_cy deps > "$W/a1a.out" 2>&1
rc=0; _cy lib sync --full > "$W/a1b.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 1: lib sync --full failed (rc=$rc):"; sed 's/^/      /' "$W/a1b.out" | tail -3; x=1; }
cmp -s "$P/lib/chrono.cyr" "$H/versions/6.6.7/lib/chrono.cyr" || { fail "axis 1 setup: chrono was not synced"; x=1; }
rc=0; _cy deps --verify > "$W/a1c.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 1: deps --verify after lib sync --full (rc=$rc):"; grep -E 'FAIL|verified' "$W/a1c.out" | head -3 | sed 's/^/      /'; x=1; }
want=$(find "$P/lib" -name '*.cyr' | wc -l | tr -d ' '); got=$(_hashlines "$P/cyrius.lock")
[ "$got" = "$want" ] || { fail "axis 1: the lock has $got hash lines for $want .cyr files under lib/"; x=1; }
why=$(_hashes_true) || { fail "axis 1: $why"; x=1; }
[ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.7')" ] || { fail "axis 1: the lock trailer is '$(tail -1 "$P/cyrius.lock")', not the new pin"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: after the pin move, lib sync --full re-locked $got lines (sha256sum-confirmed); deps --verify passes"

# ── axis 2: a removed file loses its row ────────────────────────────────────────────────
x=0
rm -f "$P/lib/chrono.cyr"
rc=0; _cy lib sync > "$W/a2.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 2: the scoped lib sync failed (rc=$rc)"; x=1; }
[ -f "$P/lib/chrono.cyr" ] && { fail "axis 2 setup: the scoped sync vendored chrono"; x=1; }
grep -q 'lib/chrono.cyr' "$P/cyrius.lock" && { fail "axis 2: cyrius.lock still has a row for the removed lib/chrono.cyr"; x=1; }
rc=0; _cy deps --verify > "$W/a2v.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 2: deps --verify after the scoped sync (rc=$rc)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: a file gone from lib/ has no row after lib sync"

# ── axis 3: commit pins are carried forward ─────────────────────────────────────────────
x=0
pin=$(printf 'commit\t0123456789abcdef0123456789abcdef01234567\tdemo\thttps://example.invalid/demo\t1.0.0')
{ printf '%s\n' "$pin"; cat "$P/cyrius.lock"; } > "$W/lock" && cp "$W/lock" "$P/cyrius.lock"
_cy lib sync > /dev/null 2>&1
grep -qxF "$pin" "$P/cyrius.lock" || { fail "axis 3: the commit pin line was dropped by the re-lock"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 3: a commit pin survives the re-lock"

# ── axis 4: --no-lock and --dry-run write no lock ───────────────────────────────────────
x=0
echo '# local edit' >> "$P/lib/string.cyr"
_cy deps --lock > /dev/null 2>&1
cp "$P/cyrius.lock" "$W/before"
rc=0; _cy lib sync --no-lock > "$W/a4.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 4: lib sync --no-lock failed (rc=$rc):"; sed 's/^/      /' "$W/a4.out" | tail -2; x=1; }
cmp -s "$W/before" "$P/cyrius.lock" || { fail "axis 4: lib sync --no-lock rewrote cyrius.lock"; x=1; }
echo '# local edit' >> "$P/lib/string.cyr"
_cy deps --lock > /dev/null 2>&1
cp "$P/cyrius.lock" "$W/before"
_cy lib sync --dry-run > /dev/null 2>&1
cmp -s "$W/before" "$P/cyrius.lock" || { fail "axis 4: lib sync --dry-run rewrote cyrius.lock"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: --no-lock and --dry-run leave cyrius.lock alone"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: lib_sync_relocks"
exit 0
