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
#   2. Pin move, `deps` BEFORE `lib sync --full` (6.7.12, D19): `deps` exits 1 naming
#      lib/chrono.cyr alone (outside the closure, other bytes at 6.6.7) — not lib/string.cyr (in
#      it), lib/math.cyr (the same bytes at 6.6.7) or a hand-written lib/mine.cyr (no snapshot
#      file) — with both remedies; cyrius.lock byte-unchanged; `cyrius build` stops at the same
#      refusal before compiling;
#      `lib sync --full` then re-locks at 6.6.7 and verifies. (6.7.13) `deps --locked` at the bump and
#      after the refused deps exits 1 with D19's remedy naming lib/chrono.cyr — not "run `cyrius
#      deps`" — and passes once `lib sync --full` has run. (6.7.13, D42) At the bump the bare
#      `deps --lock` exits 1 naming lib/chrono.cyr and lib/string.cyr (it vendored nothing) with
#      `cyrius deps` as its first way, and the scoped `lib sync` (and its --dry-run) exits 1 naming
#      lib/chrono.cyr alone before it copies — lib/ and cyrius.lock byte-unchanged by both. (6.7.13,
#      D41) the refused deps / build write NOTHING: lib/string.cyr (in the closure, moved at 6.6.7)
#      and all of lib/ byte-unchanged, `deps --verify` green after the refusal. 2c: a lock an older `deps` re-stamped
#      (trailer 6.6.7 over 6.6.6 rows): `lib sync` refuses by name, writes nothing, its summary
#      names `lib sync --full --relock`, which then verifies. 2d: a closure-only project whose pin
#      moves re-locks silently (rc 0, trailer 6.6.7, string's row the new hash, no refusal).
#      2e: under an UNCHANGED pin an out-of-closure file off the snapshot is not refused
#      (`deps --relock` re-locks it, as before). 2f: a closure-only project at the move: `deps
#      --lock` refuses lib/string.cyr (6.7.13); the lock an older `deps --lock` re-stamped
#      (simulated): `lib sync` refuses lib/string.cyr and its summary names the SCOPED
#      `cyrius lib sync --relock` (not only `--full`, which vendors the whole snapshot), which then
#      verifies with lib/ the same file count. 2g (D41): the pin-move dry pass — its own home, 6.7.1
#      moving string and ws_server.cyr, a path dep `ws` whose module is a thin profile of the leaf —
#      is silent (a closure-only move prints the resolve's note once, rc 0) and decides what D19
#      decided (a full-vendored lib/ws_server.cyr the resolve deletes is not held against it).
#   3. Same pin, moved snapshot: `lib sync` (and `--dry-run`) refuse, lock and lib/ unchanged,
#      and `cyrius deps` still refuses.
#   4. A locked file the sync does not write, edited locally: its row is kept and
#      `deps --verify` names it.
#   5. A file removed from lib/ loses its row.   6. A `commit` pin line survives.
#   7. `--no-lock` and `--dry-run` leave the lock byte-identical; a scoped `--no-lock` sync at a
#      moved pin (it stamps nothing) is not refused (6.7.13).
#   8. No cyrius.lock before the sync: none after it.
# Slot-open CLI: axes 1, 2, 3, 5 and 7 FAIL. The first-cut fix (5124f2a1): axes 2, 3, 4 and 8 FAIL.
# 6.7.12 (D19): the 6.7.11 CLI (deps re-stamps the moved pin) FAILS axes 2 and 2c (rc 0, the trailer
# 6.6.7 over chrono's 6.6.6 row); `_dep_pin_move_refused` returning 0 (the check dropped) FAILS axis
# 2; refusing every out-of-closure file (no byte compare, no snapshot test) FAILS axis 2 (111 named);
# the snapshot test alone dropped FAILS axis 2 (lib/mine.cyr named); the unchanged pin not exempt
# FAILS axis 2e; the summary naming only `--full --relock` (the review's catch) FAILS axis 2f.
# 6.7.13: --locked's D19 remedy dropped (the old "run `cyrius deps`" line) FAILS axis 2 at both
# --locked rows; the stale set read from the scratch closure unmapped (every lib/ file out of scope)
# FAILS the at-the-bump row (lib/string.cyr, still 6.6.6 bytes, named beside chrono). D42: the bare
# `--lock` branch dropped (it re-stamps again) FAILS axis 2's --lock row and 2f's; the scoped sync's
# check dropped FAILS axis 2's sync and --dry-run rows; `--no-lock` not exempt FAILS axis 7's last row.
# D41: no dry pass FAILS axis 2's string / lib/ / --verify rows and the build row; no mute FAILS 2g
# (the note twice); the stale profile copy not recorded (`_dep_dry_drop`) FAILS 2g (rc 1); no pass
# reset after the dry pass FAILS 2g (the note 0 times, a lock row that lies).
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

# ── axis 2: pin move, `deps` before `lib sync --full` (6.7.12, D19) ─────────────────────────
x=0
_locked_at_666
printf 'fn mine(): i64 { return 1; }\n' > "$P/lib/mine.cyr"   # outside the closure, no snapshot file
_cy deps --lock > /dev/null 2>&1 && grep -q '  lib/mine.cyr$' "$P/cyrius.lock" || { fail "axis 2 setup: lib/mine.cyr not locked"; x=1; }
_pin 6.6.7
printf '\n[build]\nentry = "main.cyr"\noutput = "build/m"\n' >> "$P/cyrius.cyml"; printf 'syscall(SYS_EXIT, 0);\n' > "$P/main.cyr"
cp "$P/cyrius.lock" "$W/a2.lock"; cp "$P/lib/chrono.cyr" "$W/a2.chrono"; cp "$P/lib/string.cyr" "$W/a2.string"
# 6.7.13: `deps --locked` (CI) at the moved pin gives D19's remedy, naming chrono — never "run
# `cyrius deps`", which refuses here (issues/2026-10-15-deps-locked-remedy-names-deps-after-a-d19-refusal.md)
_locked_remedy() {   # <tag>: rc 1, the D19 remedy naming lib/chrono.cyr alone, not "run `cyrius deps`"
    rc=0; _cy deps --locked > "$W/a2l$1.out" 2>&1 || rc=$?
    { [ "$rc" -eq 1 ] && grep -q '^error: --locked: .*\[package\].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 1 file the resolve does not vendor that the 6.6.7 snapshot ships with other bytes, so `cyrius deps` will not re-lock:$' "$W/a2l$1.out" \
      && [ "$(grep '^  lib/' "$W/a2l$1.out" | tr -d ' \n')" = "lib/chrono.cyr" ] \
      && grep -q 'cyrius lib sync --full     moves them to 6.6.7 and re-locks' "$W/a2l$1.out" \
      && grep -q 'rm <file> && cyrius deps   drops them' "$W/a2l$1.out" \
      && ! grep -q 'run `cyrius deps`' "$W/a2l$1.out" && cmp -s "$W/a2.lock" "$P/cyrius.lock"; } \
      || { fail "axis 2 ($1): deps --locked at the moved pin did not give D19's remedy naming lib/chrono.cyr (rc=$rc):"; grep -v '^  differs' "$W/a2l$1.out" | head -4 | sed 's/^/      /'; x=1; }
}
_locked_remedy "at the pin bump"
# 6.7.13 (D42): the two other lock writers are held to D19 at the move
# (issues/2026-10-15-deps-lock-and-scoped-lib-sync-restamp-a-moved-pin.md). The bare `--lock`
# vendored nothing, so every lib/ file 6.6.7 ships with other bytes is named — chrono and string,
# not math (the same bytes) or mine (no snapshot file) — and its first way is `cyrius deps`; the
# scoped `lib sync` names chrono alone (string is in its subset) before it copies anything.
_libsum() { ( cd "$P" && find lib -type f | LC_ALL=C sort | xargs sha256sum ) | sha256sum | cut -d' ' -f1; }
lib0=$(_libsum)
rc=0; _cy deps --lock > "$W/a2k.out" 2>&1 || rc=$?
{ [ "$rc" -eq 1 ] && grep -q '^error: cyrius.lock not re-locked: \[package\].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 2 files that the 6.6.7 snapshot ships with other bytes (a bare re-lock vendors nothing):$' "$W/a2k.out" \
  && [ "$(grep '^  lib/' "$W/a2k.out" | tr -d ' \n')" = "lib/chrono.cyrlib/string.cyr" ] \
  && grep -q '^    cyrius deps                re-vendors the declared closure at 6.6.7 and re-locks$' "$W/a2k.out" \
  && grep -q 'cyrius lib sync --full     moves them to 6.6.7 and re-locks' "$W/a2k.out" \
  && grep -q '^  cyrius.lock is unchanged (it records 6.6.6).$' "$W/a2k.out" \
  && cmp -s "$W/a2.lock" "$P/cyrius.lock" && [ "$(_libsum)" = "$lib0" ]; } \
  || { fail "axis 2: bare deps --lock after the pin move did not refuse lib/chrono.cyr + lib/string.cyr with the lock unchanged (rc=$rc):"; head -4 "$W/a2k.out" | sed 's/^/      /'; x=1; }
rc=0; _cy lib sync > "$W/a2y.out" 2>&1 || rc=$?
{ [ "$rc" -eq 1 ] && grep -q '^error: lib sync: nothing was copied: \[package\].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 1 file outside the declared \[deps\].stdlib subset that the 6.6.7 snapshot ships with other bytes:$' "$W/a2y.out" \
  && [ "$(grep '^  lib/' "$W/a2y.out" | tr -d ' \n')" = "lib/chrono.cyr" ] \
  && grep -q '^    cyrius lib sync --full     moves them to 6.6.7 and re-locks' "$W/a2y.out" \
  && ! grep -q '^synced from' "$W/a2y.out" \
  && cmp -s "$W/a2.lock" "$P/cyrius.lock" && [ "$(_libsum)" = "$lib0" ]; } \
  || { fail "axis 2: the scoped lib sync after the pin move did not refuse lib/chrono.cyr before copying, lib/ and the lock unchanged (rc=$rc):"; head -3 "$W/a2y.out" | sed 's/^/      /'; x=1; }
rc=0; _cy lib sync --dry-run > "$W/a2yd.out" 2>&1 || rc=$?
{ [ "$rc" -eq 1 ] && grep -q '^error: lib sync: nothing was copied' "$W/a2yd.out"; } \
  || { fail "axis 2: the scoped lib sync --dry-run at the moved pin reported success for a sync that refuses (rc=$rc)"; x=1; }
rc=0; _cy deps > "$W/a2d.out" 2>&1 || rc=$?
# named: chrono alone — not string (in the closure), math (outside it, the same bytes at 6.6.7) or
# mine (no snapshot file: pin-independent)
{ [ "$rc" -eq 1 ] && grep -q '^error: cyrius.lock not re-locked: \[package\].cyrius moved from 6.6.6 to 6.6.7' "$W/a2d.out" \
  && [ "$(grep '^  lib/' "$W/a2d.out" | tr -d ' \n')" = "lib/chrono.cyr" ] \
  && grep -q 'cyrius lib sync --full     moves them to 6.6.7' "$W/a2d.out" \
  && grep -q 'rm <file> && cyrius deps   drops them' "$W/a2d.out"; } \
  || { fail "axis 2: deps after the pin move did not refuse lib/chrono.cyr by name (rc=$rc):"; head -3 "$W/a2d.out" | sed 's/^/      /'; x=1; }
cmp -s "$W/a2.lock" "$P/cyrius.lock" || { fail "axis 2: the refused deps rewrote cyrius.lock ($(tail -1 "$P/cyrius.lock"))"; x=1; }
cmp -s "$W/a2.chrono" "$P/lib/chrono.cyr" || { fail "axis 2: the refused deps wrote lib/chrono.cyr"; x=1; }
# 6.7.13 (D41): refused BEFORE Phase 1 writes — string (in the closure, moved at 6.6.7) is not
# re-vendored, so lib/ is the old pin's throughout and `deps --verify` stays green
# (issues/2026-10-15-d19-refusal-leaves-closure-files-revendored-at-the-new-pin.md)
cmp -s "$W/a2.string" "$P/lib/string.cyr" || { fail "axis 2: the refused deps re-vendored lib/string.cyr at 6.6.7 (D41: refused before anything is written)"; x=1; }
[ "$(_libsum)" = "$lib0" ] || { fail "axis 2: the refused deps changed lib/"; x=1; }
rc=0; _cy deps --verify > "$W/a2dv.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 2: deps --verify after the refused deps fails (rc=$rc):"; grep -E 'FAIL|verified' "$W/a2dv.out" | head -3 | sed 's/^/      /'; x=1; }
_locked_remedy "after the refused deps"
rc=0; _cy build > "$W/a2b.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q '^error: cyrius.lock not re-locked' "$W/a2b.out" && ! grep -q '^compile ' "$W/a2b.out" \
  && cmp -s "$W/a2.lock" "$P/cyrius.lock" && [ "$(_libsum)" = "$lib0" ]; } \
  || { fail "axis 2: cyrius build after the pin move did not stop at the refusal, lib/ and the lock unchanged (rc=$rc):"; head -2 "$W/a2b.out" | sed 's/^/      /'; x=1; }
rc=0; _cy lib sync --full > "$W/a2s.out" 2>&1 || rc=$?
rc2=0; _cy deps --verify > "$W/a2v.out" 2>&1 || rc2=$?
rc3=0; _cy deps > "$W/a2x.out" 2>&1 || rc3=$?
{ [ "$rc$rc2$rc3" = "000" ] && cmp -s "$P/lib/chrono.cyr" "$H/versions/6.6.7/lib/chrono.cyr" \
  && [ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.7')" ]; } \
  || { fail "axis 2: lib sync --full (rc=$rc) then deps --verify (rc=$rc2) and deps (rc=$rc3) after the refusal"; x=1; }
why=$(_hashes_true) || { fail "axis 2: $why"; x=1; }
rc=0; _cy deps --locked > "$W/a2lz.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 2: deps --locked after the remedy (lib sync --full) fails (rc=$rc):"; tail -2 "$W/a2lz.out" | sed 's/^/      /'; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: deps (and build) at a moved pin refuse lib/chrono.cyr by name, lock untouched; so do the bare deps --lock (chrono + string) and the scoped lib sync (chrono, before copying; --dry-run too); deps --locked gives that remedy (at the bump and after the refusal), not 'run cyrius deps'; lib sync --full then re-locks at 6.6.7 and --locked passes"

# ── axis 2c: a lock an older `deps` re-stamped (6.6.17's case) ──────────────────────────────
x=0
_locked_at_666
_pin 6.6.7
sed -i 's/^cyrius\t6.6.6$/cyrius\t6.6.7/' "$P/cyrius.lock"
[ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.7')" ] || { fail "axis 2c setup: the trailer was not re-stamped"; x=1; }
cp "$P/cyrius.lock" "$W/a2c.lock"; cp "$P/lib/chrono.cyr" "$W/a2c.chrono"
rc=0; _cy lib sync --full > "$W/a2c.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'lib/chrono.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE' "$W/a2c.out" \
  && grep -q 'cyrius lib sync --full --relock' "$W/a2c.out" && grep -q 'reinstall' "$W/a2c.out"; } \
  || { fail "axis 2c: lib sync did not refuse the re-stamped chrono row by name (rc=$rc)"; x=1; }
cmp -s "$W/a2c.lock" "$P/cyrius.lock" || { fail "axis 2c: the refused sync rewrote cyrius.lock"; x=1; }
cmp -s "$W/a2c.chrono" "$P/lib/chrono.cyr" || { fail "axis 2c: the refused sync wrote lib/chrono.cyr"; x=1; }
rc=0; _cy lib sync --full --relock > "$W/a2r.out" 2>&1 || rc=$?
rc2=0; _cy deps --verify > "$W/a2rv.out" 2>&1 || rc2=$?
{ [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ]; } || { fail "axis 2c: lib sync --full --relock (rc=$rc) then deps --verify (rc=$rc2)"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2c: a re-stamped stale row is refused by lib sync by name, nothing written; --full --relock accepts"

# ── axis 2d: a closure-only project whose pin moves re-locks silently ───────────────────────
x=0
_mkp 6.6.6
_cy deps > /dev/null 2>&1 || { fail "axis 2d setup: deps at 6.6.6 failed"; x=1; }
_pin 6.6.7
rc=0; _cy deps > "$W/a2e.out" 2>&1 || rc=$?
sh7=$(sha256sum "$H/versions/6.6.7/lib/string.cyr" | cut -d' ' -f1)
{ [ "$rc" -eq 0 ] && ! grep -q 'not re-locked' "$W/a2e.out" && [ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.7')" ] \
  && grep -q "^$sh7  lib/string.cyr\$" "$P/cyrius.lock"; } \
  || { fail "axis 2d: a closure-only pin move (rc=$rc): $(head -2 "$W/a2e.out")"; x=1; }
why=$(_hashes_true) || { fail "axis 2d: $why"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2d: a closure-only project re-locks silently at the new pin"

# ── axis 2e: the refusal is a PIN-MOVE rule — an unchanged pin re-locks as before ───────────
#    A full-vendored lib/ whose out-of-closure chrono differs from the snapshot under the SAME pin
#    (a local edit) is re-locked by an explicit `deps --relock`, as it always was.
x=0
_locked_at_666
echo '# local edit' >> "$P/lib/chrono.cyr"
rc=0; _cy deps --relock > "$W/a2f.out" 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && ! grep -q 'not re-locked' "$W/a2f.out" && [ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.6')" ]; } \
  || { fail "axis 2e: deps --relock under the unchanged pin (rc=$rc): $(head -2 "$W/a2f.out")"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2e: an unchanged pin re-locks (deps --relock) with an out-of-closure file off the snapshot"

# ── axis 2f: a closure-only lock `deps --lock` re-stamped: the remedy is the SCOPED relock ──
#    `--full` there would vendor the whole snapshot into a project that declared two leaves.
x=0
_mkp 6.6.6
_cy deps > /dev/null 2>&1 || { fail "axis 2f setup: deps at 6.6.6 failed"; x=1; }
n0=$(find "$P/lib" -name '*.cyr' | wc -l | tr -d ' ')
_pin 6.6.7
# 6.7.13 (D42): `deps --lock` no longer re-stamps this lock — it refuses lib/string.cyr (6.6.6's
# bytes) and leaves the lock alone — so the lock an older CLI's `deps --lock` wrote is simulated.
cp "$P/cyrius.lock" "$W/a2g0.lock"
rc=0; _cy deps --lock > "$W/a2gk.out" 2>&1 || rc=$?
{ [ "$rc" -eq 1 ] && [ "$(grep '^  lib/' "$W/a2gk.out" | tr -d ' \n')" = "lib/string.cyr" ] && cmp -s "$W/a2g0.lock" "$P/cyrius.lock"; } \
  || { fail "axis 2f: deps --lock at the moved pin of a closure-only project did not refuse lib/string.cyr alone (rc=$rc):"; head -2 "$W/a2gk.out" | sed 's/^/      /'; x=1; }
sed -i 's/^cyrius\t6.6.6$/cyrius\t6.6.7/' "$P/cyrius.lock"
[ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.6.7')" ] || { fail "axis 2f setup: the trailer was not re-stamped"; x=1; }
cp "$P/cyrius.lock" "$W/a2g.lock"
rc=0; _cy lib sync > "$W/a2g.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'lib/string.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE' "$W/a2g.out" \
  && grep -q '`cyrius lib sync --relock` then' "$W/a2g.out"; } \
  || { fail "axis 2f: lib sync did not name the scoped \`cyrius lib sync --relock\` (rc=$rc):"; tail -2 "$W/a2g.out" | sed 's/^/      /'; x=1; }
cmp -s "$W/a2g.lock" "$P/cyrius.lock" || { fail "axis 2f: the refused sync rewrote cyrius.lock"; x=1; }
rc=0; _cy lib sync --relock > "$W/a2h.out" 2>&1 || rc=$?
rc2=0; _cy deps --verify > "$W/a2hv.out" 2>&1 || rc2=$?
n1=$(find "$P/lib" -name '*.cyr' | wc -l | tr -d ' ')
{ [ "$rc$rc2" = "00" ] && [ "$n1" = "$n0" ] && grep -q "^$n0 verified, 0 failed" "$W/a2hv.out" \
  && cmp -s "$P/lib/string.cyr" "$H/versions/6.6.7/lib/string.cyr"; } \
  || { fail "axis 2f: lib sync --relock (rc=$rc) then deps --verify (rc=$rc2): lib/ $n0 -> $n1 files, $(tail -1 "$W/a2hv.out")"; x=1; }
why=$(_hashes_true) || { fail "axis 2f: $why"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2f: deps --lock refuses the closure-only move (lib/string.cyr); a lock an older deps --lock re-stamped: lib sync names the scoped --relock, which verifies $n1 files (lib/ unchanged in size)"

# ── axis 2g: the pin-move dry pass (6.7.13, D41) is invisible and decides what D19 decided ──
#    Its own home: 6.7.1 moves string (in the closure) and ws_server.cyr. A path dep `ws` whose
#    module is dist/ws_server.cyr is a thin profile of the declared leaf `ws`, so the resolve keeps
#    the fold, prints one note, and deletes a lib/ws_server.cyr an earlier sync left.
x=0
H2="$W/home2"
mkdir -p "$H2/versions/6.7.0" "$H2/versions/6.7.1" \
  && cp -r lib "$H2/versions/6.7.0/lib" && cp -r lib "$H2/versions/6.7.1/lib" \
  && echo '# moved in 6.7.1' >> "$H2/versions/6.7.1/lib/string.cyr" \
  && echo '# moved in 6.7.1' >> "$H2/versions/6.7.1/lib/ws_server.cyr" \
  && printf '6.7.1\n' > "$H2/current" && mkdir -p "$W/wsthin/dist" \
  && printf 'fn wsthin(): i64 { return 1; }\n' > "$W/wsthin/dist/ws_server.cyr" \
  && printf '[package]\nname = "wsthin"\nversion = "0.1.0"\n' > "$W/wsthin/cyrius.cyml" \
  || { echo "FAIL: $G: cannot stage axis 2g's home"; exit 1; }
_mkws() { rm -rf "$P"; mkdir -p "$P"
    printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.7.0"\n\n[deps]\nstdlib = ["syscalls", "string", "ws"]\n\n[deps.ws]\npath = "../wsthin"\nmodules = ["dist/ws_server.cyr"]\n' > "$P/cyrius.cyml"; }
_cy2() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H2" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CLI" "$@" ); }
# (a) closure-only: the dry pass runs (lib/string.cyr differs at 6.7.1), refuses nothing, and is
#     silent — the resolve's note appears ONCE, as from a resolve with no dry pass
_mkws
_cy2 deps > /dev/null 2>&1 || { fail "axis 2g setup: deps at 6.7.0 failed"; x=1; }
_pin 6.7.1
rc=0; _cy2 deps > "$W/a2w.out" 2>&1 || rc=$?
nn=$(grep -c "^note: \[deps.ws\] dist/ws_server.cyr not vendored" "$W/a2w.out")
{ [ "$rc" -eq 0 ] && [ "$nn" = 1 ] && [ "$(grep -c '^1 deps resolved' "$W/a2w.out")" = 1 ] \
  && [ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.7.1')" ] && cmp -s "$P/lib/string.cyr" "$H2/versions/6.7.1/lib/string.cyr"; } \
  || { fail "axis 2g: a closure-only pin move with a dry pass (rc=$rc, the note $nn times):"; head -4 "$W/a2w.out" | sed 's/^/      /'; x=1; }
# (b) full-vendored, lib/ws_server.cyr re-synced: outside the closure and moved at 6.7.1, but the
#     resolve deletes it (the fold is kept), so D19 never held it — nor does the dry pass
_mkws
{ _cy2 lib sync --full && _cy2 deps && _cy2 lib sync --full; } > /dev/null 2>&1
[ -f "$P/lib/ws_server.cyr" ] || { fail "axis 2g setup: lib/ws_server.cyr was not re-synced"; x=1; }
_pin 6.7.1
rc=0; _cy2 deps > "$W/a2x2.out" 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && ! grep -q 'not re-locked' "$W/a2x2.out" && [ ! -f "$P/lib/ws_server.cyr" ] \
  && [ "$(tail -1 "$P/cyrius.lock")" = "$(printf 'cyrius\t6.7.1')" ]; } \
  || { fail "axis 2g: the dry pass held the thin-profile copy the resolve deletes (rc=$rc):"; head -3 "$W/a2x2.out" | sed 's/^/      /'; x=1; }
why=$(_hashes_true) || { fail "axis 2g: $why"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2g: the pin-move dry pass is silent (the resolve's note once) and keeps D19's verdict on a thin-profile copy the resolve deletes"

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
# 6.7.13 (D42): a scoped --no-lock sync at a moved pin stamps no pin, so D19's refusal is not its:
# it copies the subset (string at 6.6.7) and leaves the lock alone
_locked_at_666
_pin 6.6.7
cp "$P/cyrius.lock" "$W/before"
rc=0; _cy lib sync --no-lock > "$W/a7n.out" 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && cmp -s "$W/before" "$P/cyrius.lock" && cmp -s "$P/lib/string.cyr" "$H/versions/6.6.7/lib/string.cyr" \
  && ! grep -q 'nothing was copied' "$W/a7n.out"; } \
  || { fail "axis 7: a scoped lib sync --no-lock at the moved pin (rc=$rc):"; head -2 "$W/a7n.out" | sed 's/^/      /'; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 7: --no-lock and --dry-run leave cyrius.lock alone (a scoped --no-lock sync at a moved pin is not refused: it stamps nothing)"

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
