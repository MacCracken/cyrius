#!/bin/sh
# deps_relock_refused.sh — the resolver REFUSES to re-lock a stdlib leaf whose pinned
# snapshot bytes disagree with cyrius.lock while `[package].cyrius` is unchanged.
#
# v6.6.4. hisab (3.0.1 bump): a `cyrius build` with the pin unchanged and nothing edited
# rewrote the tracked lib/ganita.cyr (1.2.4 → 1.2.5) and moved its lock hash, printing the
# same two lines a no-op prints; `deps --verify` then PASSED on the mutated content. The
# lock existed to catch exactly this and was instead updated to agree with it: Phase 1
# copied from `versions/<pin>/lib` unconditionally and cmd_deps_lock re-hashed the disk with
# O_TRUNC, never reading the lock it inherited. The git-dep half has had the check since
# CVE-21 (v6.2.30) — a repointed tag is refused against the `commit\t` line — this is the
# stdlib half, keyed on the pin: the lock now carries a `cyrius\t<pin>` trailer, and a leaf
# whose snapshot hash differs from the locked one under the same pin is refused by name.
# `cyrius deps --relock` is the explicit accept; a pin bump re-locks silently.
#
# ⛔ FIXTURE SHAPE IS LOAD-BEARING (bite-4 review): a stdlib-ONLY consumer writes no lock by
# default (`copied == 0`), so a stdlib-only fixture cannot reproduce the filed symptom and
# A1's "lock untouched" would pass VACUOUSLY on the old resolver. Every axis that must see
# the silent RE-LOCK carries a local `file://` git dep (no network) so `build` writes the lock.
#
# Two more defects the review found ride along: bare `cyrius deps --lock` re-hashed lib/ with
# `_dep_commit_lines == 0` and DROPPED every CVE-21 commit pin (A6); a CRLF checkout of the
# lock silently turned the guard OFF (A7 — it now fails closed, like `--verify` always did).
#
# Everything runs in a mktemp CYRIUS_HOME with the CLI built FROM SOURCE dropped in as the
# pin's own wrapper (pin == its version → no re-exec), so the resolver under test is the
# tree's. Expected-failure calls use `if cmd; then ..; else rc=$?; fi` (set -e rule).
#
# Mutation ledger (MEASURED in a scratch ROOT with buildable mutants — a `:` no-op is a
# cyrius syntax error and reads as "could not build", not as a caught mutant). The gate has
# 14 ok() axes; the A1 setup assertions (lock written, ≥2 entries, trailer present) are
# extra `bad` lines, not axes.
#   the bite-4 (pre-fix) resolver                              → every axis but A5 red
#   drop the `_dep_lock_guard_stdlib_leaf` call at the copy site → A1 A2b A4c A4d2 A5b A7 A8 red
#   drop `if (_dep_lock_pin_same == 0) return 0` (over-refusal)  → A3 A4 red
#   drop the trailer write in cmd_deps_lock                      → A1 A2 A2b A3 A4 A4b A4c A4d A7 A8 red
#   drop `|| _dep_relock == 1` at the lock-write gate            → A8 red
#   drop the legacy re-stamp (`_stamp_legacy`)                   → A4b A4d A8 red
#   drop the stale-pin re-stamp (`_dep_lock_pin_same == 0`)      → A4d red
#   make the hasher-missing branch return 0 (fail open)          → A5b red
#   drop the commit-line carry in cmd_deps_lock                  → A6 red
#   drop the CR tolerance                                        → A7 red
#   drop CYRIUS_RESOLVED=1 from A5 after a version bump          → A5 measures the NEW reader (vacuous)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: deps_relock_refused: build/cycc missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: deps_relock_refused: git not found"; exit 0; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
V=$(tr -d '[:space:]' < "$ROOT/VERSION")

# ── the CLI from source, staged as the pin's own wrapper in a throwaway home ─────────────
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null ) || { echo "FAIL: deps_relock_refused: could not build cbt/cyrius.cyr"; exit 1; }
chmod +x "$W/cyrius"
H="$W/home"; mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib" "$H/deps"
cp -r "$ROOT/lib/." "$H/versions/$V/lib/"
cp "$W/cyrius" "$H/versions/$V/bin/cyrius"; cp "$CC" "$H/versions/$V/bin/cycc"; chmod +x "$H/versions/$V/bin/"*
printf '%s\n' "$V" > "$H/current"; ln -s "$H/versions/$V/bin" "$H/bin"; ln -s "$H/versions/$V/lib" "$H/lib"
CY="$H/versions/$V/bin/cyrius"
export CYRIUS_HOME="$H"

# ── a local git dep (file://, tagged) so a lock is written and commit-pinned ────────────
GD="$W/gd"; mkdir -p "$GD/dist"
printf 'fn gd_one(): i64 { return 1; }\n' > "$GD/dist/gd.cyr"
printf '[package]\nname = "gd"\nversion = "1.0.0"\nlanguage = "cyrius"\n' > "$GD/cyrius.cyml"
( cd "$GD" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm v1 && git tag v1 )

mkproj() {   # $1 = dir  $2 = pin  $3 = with-git-dep (1/0)
    mkdir -p "$1"
    {
        printf '[package]\nname = "relockp"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nsrc = "main.cyr"\noutput = "out"\n\n[deps]\nstdlib = ["syscalls", "math"]\n' "$2"
        [ "$3" = 1 ] && printf '\n[deps.gd]\ngit = "file://%s"\ntag = "v1"\nmodules = ["dist/gd.cyr"]\n' "$GD"
    } > "$1/cyrius.cyml"
    printf 'fn main() { return 0; }\nvar rc = main();\nsys_exit_group(rc);\n' > "$1/main.cyr"
}

# ── A1: mutate the snapshot under an unchanged pin → `build` refused, nothing rewritten ──
P="$W/p1"; mkproj "$P" "$V" 1
( cd "$P" && "$CY" deps > "$W/a1-deps.out" 2>&1 ) || { bad "A1 setup: initial resolve failed: $(tail -2 "$W/a1-deps.out")"; }
[ -f "$P/cyrius.lock" ] || bad "A1 setup: no cyrius.lock written (the fixture must carry a git dep)"
before="$(grep ' lib/math.cyr$' "$P/cyrius.lock" | cut -d' ' -f1 || true)"
n_entries="$(grep -c '  lib/' "$P/cyrius.lock" || true)"
[ "$n_entries" -ge 2 ] || bad "A1 setup: lock has $n_entries entries (anti-vacuous floor is 2)"
grep -q "^cyrius	$V$" "$P/cyrius.lock" || bad "A1 setup: the fresh lock carries no \`cyrius\t$V\` trailer"
cp "$P/cyrius.lock" "$W/a1.lock.before"; cp "$P/lib/math.cyr" "$W/a1.math.before"
sed -i '1s/^/# snapshot mutated under an unchanged pin\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P" && "$CY" build main.cyr ./out > "$W/a1.out" 2>&1 ); then rc=0; else rc=$?; fi
after="$(grep ' lib/math.cyr$' "$P/cyrius.lock" | cut -d' ' -f1 || true)"
snaph="$(sha256sum "$H/versions/$V/lib/math.cyr" | cut -d' ' -f1)"
if [ "$rc" -ne 0 ] && grep -q 'DISAGREE under an unchanged pin' "$W/a1.out" && grep -q 'lib/math.cyr' "$W/a1.out" \
   && grep -q "$before" "$W/a1.out" && grep -q "$snaph" "$W/a1.out" \
   && cmp -s "$P/cyrius.lock" "$W/a1.lock.before" && cmp -s "$P/lib/math.cyr" "$W/a1.math.before" && [ ! -e "$P/out" ]; then
    ok "A1 mutated snapshot, same pin: build refused (rc=$rc), names the leaf + both hashes; lock, lib/ and output untouched"
else bad "A1 (rc=$rc, before=$before after=$after): $(grep -m2 -i 'error\|refus' "$W/a1.out")"; fi

# ── A2: `deps --relock` accepts explicitly → lock moves, trailer present, verify clean ───
rc=0; if ( cd "$P" && "$CY" deps --relock > "$W/a2.out" 2>&1 ); then rc=0; else rc=$?; fi
after2="$(grep ' lib/math.cyr$' "$P/cyrius.lock" | cut -d' ' -f1 || true)"
rc2=0; if ( cd "$P" && "$CY" deps --verify > "$W/a2v.out" 2>&1 ); then rc2=0; else rc2=$?; fi
if [ "$rc" -eq 0 ] && [ "$after2" = "$snaph" ] && grep -q "^cyrius	$V$" "$P/cyrius.lock" && [ "$rc2" -eq 0 ] && grep -q ' 0 failed' "$W/a2v.out"; then
    ok "A2 --relock: accepted, lock hash = the new snapshot hash, trailer kept, --verify 0 failed"
else bad "A2 (rc=$rc verify=$rc2 after=$after2 want=$snaph): $(tail -2 "$W/a2v.out")"; fi
# ...and a SECOND mutation is refused again (the accept is one-shot)
sed -i '1s/^/# second mutation\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P" && "$CY" build main.cyr ./out > "$W/a2b.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'DISAGREE' "$W/a2b.out"; then ok "A2b a further mutation after --relock is refused again"; else bad "A2b (rc=$rc)"; fi

# ── A3: a LEGITIMATE pin bump re-locks silently (the anti-over-refusal axis) ─────────────
V2="$V-bumped"
mkdir -p "$H/versions/$V2"; cp -r "$H/versions/$V/." "$H/versions/$V2/"
sed -i '1s/^/# the bumped pin ships different bytes\n/' "$H/versions/$V2/lib/math.cyr"
sed -i "s/^cyrius = \"$V\"$/cyrius = \"$V2\"/" "$P/cyrius.cyml"
# the wrapper re-execs versions/<pin>/bin/cyrius for a foreign pin — it is the same binary
rc=0; if ( cd "$P" && "$CY" build main.cyr ./out > "$W/a3.out" 2>&1 ); then rc=0; else rc=$?; fi
h2="$(sha256sum "$H/versions/$V2/lib/math.cyr" | cut -d' ' -f1)"
after3="$(grep ' lib/math.cyr$' "$P/cyrius.lock" | cut -d' ' -f1 || true)"
if [ "$rc" -eq 0 ] && ! grep -q 'DISAGREE' "$W/a3.out" && [ "$after3" = "$h2" ] && grep -q "^cyrius	$V2$" "$P/cyrius.lock" && [ -e "$P/out" ]; then
    ok "A3 pin bump: re-locked silently to the new snapshot, trailer reads the new pin, build produced output"
else bad "A3 (rc=$rc after=$after3 want=$h2): $(grep -m2 -i 'error\|refus' "$W/a3.out")"; fi
rm -f "$P/out"

# ── A4: a LEGACY lock (no trailer, pre-6.6.4) fails open ONCE and comes back stamped ─────
sed -i "s/^cyrius = \"$V2\"$/cyrius = \"$V\"/" "$P/cyrius.cyml"
( cd "$P" && "$CY" deps --relock > /dev/null 2>&1 ) || bad "A4 setup: relock at $V failed"
sed -i '/^cyrius\t/d' "$P/cyrius.lock"
grep -q '^cyrius	' "$P/cyrius.lock" && bad "A4 setup: trailer not stripped"
sed -i '1s/^/# mutation against a legacy lock\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P" && "$CY" build main.cyr ./out > "$W/a4.out" 2>&1 ); then rc=0; else rc=$?; fi
snap4="$(sha256sum "$H/versions/$V/lib/math.cyr" | cut -d' ' -f1)"
after4="$(grep ' lib/math.cyr$' "$P/cyrius.lock" | cut -d' ' -f1 || true)"
if [ "$rc" -eq 0 ] && ! grep -q 'DISAGREE' "$W/a4.out" && grep -q "^cyrius	$V$" "$P/cyrius.lock" \
   && cmp -s "$P/lib/math.cyr" "$H/versions/$V/lib/math.cyr" && [ "$after4" = "$snap4" ]; then
    ok "A4 legacy lock: one documented fail-open resolve (leaf vendored, hash moved) and the rewritten lock carries the trailer"
else bad "A4 (rc=$rc after=$after4 want=$snap4): $(grep -m2 -i 'error\|refus' "$W/a4.out")"; fi
sed -i '1s/^/# mutation after the stamp\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P" && "$CY" build main.cyr ./out > "$W/a4c.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'DISAGREE' "$W/a4c.out"; then ok "A4c ...and the very next mutation is caught"; else bad "A4c (rc=$rc)"; fi

# ── A4b: a legacy lock on a STDLIB-ONLY consumer (copied == 0) is still stamped ──────────
P2="$W/p2"; mkproj "$P2" "$V" 0
( cd "$P2" && "$CY" deps > /dev/null 2>&1 && "$CY" deps --lock > /dev/null 2>&1 ) || bad "A4b setup: stdlib-only lock"
sed -i '/^cyrius\t/d' "$P2/cyrius.lock"
rc=0; if ( cd "$P2" && "$CY" deps > "$W/a4b.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q "^cyrius	$V$" "$P2/cyrius.lock" && cmp -s "$P2/lib/math.cyr" "$H/versions/$V/lib/math.cyr" \
   && [ "$(grep ' lib/math.cyr$' "$P2/cyrius.lock" | cut -d' ' -f1 || true)" = "$(sha256sum "$H/versions/$V/lib/math.cyr" | cut -d' ' -f1)" ]; then
    ok "A4b stdlib-only legacy lock: re-written once to gain the trailer, leaf vendored, hash current (no git dep needed)"
else bad "A4b (rc=$rc): $(tail -2 "$W/a4b.out")"; fi

# ── A4d: a lock whose trailer names a DIFFERENT pin (stdlib-only consumer after a pin bump)
#    is re-written too — otherwise the old pin + old hashes stay, --verify fails on the leaf
#    just vendored, and the guard sits OFF under the new pin (bite-5 review) ──────────────
sed -i "s/^cyrius = \"$V\"$/cyrius = \"$V2\"/" "$P2/cyrius.cyml"
rc=0; if ( cd "$P2" && "$CY" deps > "$W/a4d.out" 2>&1 ); then rc=0; else rc=$?; fi
rc2=0; if ( cd "$P2" && "$CY" deps --verify > "$W/a4dv.out" 2>&1 ); then rc2=0; else rc2=$?; fi
if [ "$rc" -eq 0 ] && grep -q "^cyrius	$V2$" "$P2/cyrius.lock" && [ "$rc2" -eq 0 ] && grep -qE '[1-9][0-9]* verified, 0 failed' "$W/a4dv.out"; then
    ok "A4d stdlib-only pin bump: the lock is re-written under the new pin and verifies"
else bad "A4d (rc=$rc verify=$rc2): $(tail -1 "$W/a4dv.out")"; fi
sed -i '1s/^/# mutation under the bumped pin\n/' "$H/versions/$V2/lib/math.cyr"
rc=0; if ( cd "$P2" && "$CY" deps > "$W/a4d2.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'DISAGREE' "$W/a4d2.out"; then ok "A4d2 ...and the guard is armed under the new pin"; else bad "A4d2 (rc=$rc)"; fi
sed -i "s/^cyrius = \"$V2\"$/cyrius = \"$V\"/" "$P2/cyrius.cyml"
( cd "$P2" && "$CY" deps --relock > /dev/null 2>&1 ) || true

# ── A5: an OLDER installed wrapper still verifies a trailer lock (the trailer is LAST) ────
#    ⛔ CYRIUS_RESOLVED=1 is load-bearing: without it the old wrapper re-execs into
#    `$H/versions/$V/bin/cyrius` — the NEW reader staged by this gate — whenever the
#    consumer's pin differs from its own version, i.e. from the very next version-bump on,
#    and the axis would measure the code under test (bite-5 review). The floor on the
#    verified count keeps `0 verified, 0 failed` from reading as green. Older slots are
#    read from ${CYRIUS_HOME:-$HOME/.cyrius} — under check.sh's staging they are aliased.
OLDCY=""
for d in "${CYRIUS_HOME:-$HOME/.cyrius}"/versions/*/bin/cyrius; do
    [ -x "$d" ] || continue
    ov=$(basename "$(dirname "$(dirname "$d")")")
    case "$ov" in 6.6.0|6.6.1|6.6.2|6.6.3) OLDCY="$d"; OLDV="$ov" ;; esac
done
if [ -n "$OLDCY" ]; then
    ( cd "$P" && "$CY" deps --relock > /dev/null 2>&1 ) || true
    rc=0; if ( cd "$P" && CYRIUS_RESOLVED=1 CYRIUS_HOME="$H" "$OLDCY" deps --verify > "$W/a5.out" 2>&1 ); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && grep -qE '[1-9][0-9]* verified, 0 failed' "$W/a5.out" && ! grep -q 'relock' "$W/a5.out"; then
        ok "A5 the pre-6.6.4 wrapper ($OLDV, no re-exec) verifies a trailer lock: 0 failed"
    else bad "A5 (rc=$rc): $(tail -1 "$W/a5.out")"; fi
else
    echo "  SKIP A5: no pre-6.6.4 wrapper installed under ${CYRIUS_HOME:-$HOME/.cyrius}/versions — old-reader tolerance not exercised"
fi

# ── A5b: no hasher on PATH → the guard fails CLOSED (like --verify), nothing rewritten ────
NOSHA="$W/nosha"; mkdir -p "$NOSHA"
for t in sh git cp mv rm mkdir cat sed grep cut tr basename dirname readlink env ln find awk head tail sort uniq wc; do p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NOSHA/$t"; done
( cd "$P" && "$CY" deps --relock > /dev/null 2>&1 ) || true
cp "$P/cyrius.lock" "$W/a5b.lock.before"
sed -i '1s/^/# mutation with no hasher on PATH\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P" && PATH="$NOSHA" "$CY" deps > "$W/a5b.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'cannot hash' "$W/a5b.out" && cmp -s "$P/cyrius.lock" "$W/a5b.lock.before"; then
    ok "A5b no sha256sum on PATH: refused ('cannot hash'), lock untouched"
else bad "A5b (rc=$rc): $(grep -m1 -i 'error\|hash' "$W/a5b.out")"; fi
( cd "$P" && "$CY" deps --relock > /dev/null 2>&1 ) || true

# ── A6: bare `deps --lock` KEEPS the CVE-21 commit pins ──────────────────────────────────
before_c="$(grep -c '^commit	' "$P/cyrius.lock" || true)"
[ "$before_c" -ge 1 ] || bad "A6 setup: no commit pin in the lock ($before_c)"
rc=0; if ( cd "$P" && "$CY" deps --lock > "$W/a6.out" 2>&1 ); then rc=0; else rc=$?; fi
after_c="$(grep -c '^commit	' "$P/cyrius.lock" || true)"
if [ "$rc" -eq 0 ] && [ "$after_c" = "$before_c" ]; then ok "A6 bare --lock keeps the commit pins ($before_c → $after_c)"; else bad "A6 (rc=$rc): commit pins $before_c → $after_c"; fi

# ── A7: a CRLF lock fails CLOSED (the guard still fires) ─────────────────────────────────
( cd "$P" && "$CY" deps --relock > /dev/null 2>&1 ) || true
sed -i 's/$/\r/' "$P/cyrius.lock"
sed -i '1s/^/# mutation against a CRLF lock\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P" && "$CY" build main.cyr ./out > "$W/a7.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'DISAGREE' "$W/a7.out"; then ok "A7 CRLF lock: the guard fails closed"; else bad "A7 (rc=$rc): $(grep -m1 -i 'error\|refus' "$W/a7.out")"; fi

# ── A8: stdlib-only consumer that ran --lock: mutate → deps refused; --relock → verify 0 ──
( cd "$P2" && "$CY" deps > /dev/null 2>&1 ) || true
sed -i '1s/^/# stdlib-only mutation\n/' "$H/versions/$V/lib/math.cyr"
rc=0; if ( cd "$P2" && "$CY" deps > "$W/a8.out" 2>&1 ); then rc=0; else rc=$?; fi
rc2=0; if ( cd "$P2" && "$CY" deps --relock > "$W/a8r.out" 2>&1 && "$CY" deps --verify > "$W/a8v.out" 2>&1 ); then rc2=0; else rc2=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'DISAGREE' "$W/a8.out" && [ "$rc2" -eq 0 ] && grep -q ' 0 failed' "$W/a8v.out"; then
    ok "A8 stdlib-only with a lock: refused (rc=$rc); --relock then --verify 0 failed"
else bad "A8 (deps rc=$rc relock+verify rc=$rc2): $(tail -1 "$W/a8v.out")"; fi

echo "deps_relock_refused: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
