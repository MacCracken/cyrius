#!/bin/sh
# cyriusly_use_switch_integrity.sh — v6.6.6 bite 17b. `cyriusly use <v> --global` switches the
# whole toolchain or it switches NOTHING, and it never reports a switch it did not make.
#
# ⛔ THE DEFECT (programs/cyriusly.cyr `_cmd_use_v2`, as of 6.6.5):
#     sys_unlink(bin_link);  sys_unlink(lib_link);
#     sys_symlink(ver_bin, bin_link);  sys_symlink(ver_lib, lib_link);
#     syscall(1, 1, "Now using Cyrius ", 17);
# Not one return value checked. Three failures in one sequence:
#   (a) between the unlink and the symlink `~/.cyrius/bin` DOES NOT EXIST. Anything that fails
#       there — ENOSPC, a concurrent `cyriusly use`, a kill — leaves the user with no toolchain,
#       from a command whose whole job is to keep one.
#   (b) a failed symlink was reported as SUCCESS ("Now using Cyrius X", exit 0).
#   (c) the two links were switched independently, so one succeeding and the other failing left
#       NEW binaries over an OLD stdlib — and `~/.cyrius/current`, written FIRST, named the new
#       version either way.
# Measured on 6.6.5 (axes 1 and 2 below, against the 6.6.5 binary): with `bin` an ordinary
# directory it printed "Now using Cyrius 9.9.9", exited 0 and left `bin` untouched; with `bin` a
# symlink and `lib` a directory it re-pointed `bin` to 9.9.9, left `lib` on 1.0.0 and wrote
# `current` = 9.9.9 — a mixed toolchain, exit 0.
#
# ⭐ THE FIX IS rename(), NOT A CHECK AROUND unlink+symlink. A checked unlink+symlink still has
# window (a): the check comes after the damage. `symlink()` cannot replace an existing entry,
# `rename()` can, in ONE step — so the link is never absent, and a failure leaves it exactly as
# it was. Window (a) is what axis 4 pins, STATICALLY: it is a window, not an outcome, so no
# deterministic single-process run can observe it (forcing symlink(2) to fail between the two
# calls needs ENOSPC or a second process), and a flaky race axis is worse than an honest
# static one. What axes 1-3 pin dynamically is the reported-success half and the
# both-or-neither half, which is where a regression would actually surface.
#
# AXES
#   1. `bin` is an ordinary non-empty directory (an older install, or a user who copied binaries
#      in): the command FAILS (rc != 0), says which path and why, prints no "Now using", and
#      leaves `bin`, `lib` and `current` exactly as they were.
#   2. `bin` is a symlink and `lib` is a directory — the half-switch: rc != 0, and `bin` is
#      ROLLED BACK to the version it named before, so the pair never disagrees. `current` still
#      names the old version.
#   3. ANTI-VACUOUS: a normal switch (both links, and a fresh install with neither) succeeds,
#      re-points both links at the requested version, writes `current`, and leaves no
#      `.cyrtmp.` sibling behind.
#   4. STATIC: `_cmd_use_v2` contains no `sys_unlink(bin_link)` / `sys_unlink(lib_link)` — the
#      switch goes through `_relink_atomic` (symlink to a unique sibling, then rename), every
#      call's result is checked, and `current` is written AFTER the links. Self-tested against
#      the 6.6.5 body so the detector cannot read green on anything.
#
# MUTATION LEDGER (measured 6.6.6; each mutant is a COPY of programs/cyriusly.cyr in the
# gate's scratch dir, compiled with the tree's build/cycc)
#   a. the 6.6.5 body verbatim (unlink/unlink/symlink/   -> axes 1, 2 and 4 FAIL (axis 1: rc 0 +
#      symlink, current first, nothing checked)             "Now using"; axis 2: bin on 9.9.9,
#                                                           lib on 1.0.0, current 9.9.9)
#   b. `_relink_atomic`'s rename result dropped          -> axes 1 and 2 FAIL (rc 0, "Now using")
#   c. the lib-failure rollback removed                  -> axis 2 FAIL (bin left on 9.9.9)
#   d. `current` written BEFORE the links again          -> axes 1 and 2 FAIL (current = 9.9.9)
#   e. axis-4 detector's unlink pattern disabled         -> axis 4 self-test FAIL
#   f. axis-4 detector's `_relink_atomic` requirement    -> axis 4 self-test FAIL
#      disabled
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cyriusly_use_switch_integrity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }

CY="$D/cyriusly"
"$CC" < programs/cyriusly.cyr > "$CY" 2> "$D/build.err"; brc=$?
if [ "$brc" -ne 0 ] || [ ! -s "$CY" ]; then
    echo "FAIL: programs/cyriusly.cyr does not build (rc=$brc):"; tail -5 "$D/build.err" | sed 's/^/      /'; exit 1
fi
grep -q '^warning: undefined function' "$D/build.err" && { echo "FAIL: cyriusly compiled with undefined functions:"; grep '^warning: undefined' "$D/build.err" | sed 's/^/      /'; exit 1; }
chmod +x "$CY"

# _home <name> — a scratch CYRIUS_HOME with 1.0.0 and 9.9.9 installed and current = 1.0.0.
# Never the real ~/.cyrius: this gate makes cyriusly re-point a toolchain, and the one it is
# allowed to re-point is its own.
_home() {
    H="$D/$1"
    rm -rf "$H"
    mkdir -p "$H/versions/1.0.0/bin" "$H/versions/1.0.0/lib" "$H/versions/9.9.9/bin" "$H/versions/9.9.9/lib" || return 1
    printf 'old\n' > "$H/versions/1.0.0/bin/cycc"
    printf 'new\n' > "$H/versions/9.9.9/bin/cycc"
    printf '1.0.0\n' > "$H/current"
}
# _points_at <link> — the basename-2 of the target a link names ("1.0.0", "9.9.9"), "NOTLINK"
# for anything else, "ABSENT" when there is nothing there.
_points_at() {
    [ -e "$1" ] || [ -L "$1" ] || { echo ABSENT; return; }
    [ -L "$1" ] || { echo NOTLINK; return; }
    t=$(readlink "$1"); echo "${t%/*}" | sed 's|.*/||'
}
_run() { ( cd "$D" && CYRIUS_HOME="$1" exec "$CY" use 9.9.9 --global ) > "$2" 2>&1; }

# ── axis 1: `bin` is an ordinary directory -> fail loudly, change nothing ──
_home a1 || { echo "FAIL: cannot stage the axis-1 home"; exit 1; }
mkdir -p "$D/a1/bin"; printf 'the user put this here\n' > "$D/a1/bin/keepme"
ln -sfn "$D/a1/versions/1.0.0/lib" "$D/a1/lib"
rc=0; _run "$D/a1" "$D/a1.out" || rc=$?
x=0
[ "$rc" -ne 0 ] || { fail "axis 1: a switch that could not happen exited 0"; x=1; }
grep -q 'Now using' "$D/a1.out" && { fail "axis 1: it reported 'Now using' although bin was not switched"; x=1; }
grep -q "$D/a1/bin" "$D/a1.out" || { fail "axis 1: the error does not name the path it could not re-point:"; sed 's/^/      /' "$D/a1.out" | head -2; x=1; }
[ -f "$D/a1/bin/keepme" ] || { fail "axis 1: the user's bin/ directory was destroyed"; x=1; }
[ "$(_points_at "$D/a1/lib")" = "1.0.0" ] || { fail "axis 1: lib moved to $(_points_at "$D/a1/lib") although the switch failed"; x=1; }
[ "$(cat "$D/a1/current")" = "1.0.0" ] || { fail "axis 1: current says $(cat "$D/a1/current") after a failed switch"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 1: bin a directory -> rc $rc, the path named, bin/lib/current untouched"

# ── axis 2: the half-switch — bin re-points, lib cannot; bin must be rolled back ──
_home a2 || { echo "FAIL: cannot stage the axis-2 home"; exit 1; }
ln -sfn "$D/a2/versions/1.0.0/bin" "$D/a2/bin"
mkdir -p "$D/a2/lib"; printf 'x\n' > "$D/a2/lib/keep"
rc=0; _run "$D/a2" "$D/a2.out" || rc=$?
x=0
[ "$rc" -ne 0 ] || { fail "axis 2: a half-switch exited 0"; x=1; }
grep -q 'Now using' "$D/a2.out" && { fail "axis 2: it reported 'Now using' after a half-switch"; x=1; }
[ "$(_points_at "$D/a2/bin")" = "1.0.0" ] || { fail "axis 2: bin is on $(_points_at "$D/a2/bin") while lib is still 1.0.0 — a MIXED toolchain (new binaries, old stdlib)"; x=1; }
[ -f "$D/a2/lib/keep" ] || { fail "axis 2: the user's lib/ directory was destroyed"; x=1; }
[ "$(cat "$D/a2/current")" = "1.0.0" ] || { fail "axis 2: current says $(cat "$D/a2/current") after a failed switch"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 2: lib unswitchable -> rc $rc, bin rolled back to 1.0.0, current untouched"

# ── axis 3: ANTI-VACUOUS — a normal switch, and a fresh install, both work ──
x=0
_home a3 || { echo "FAIL: cannot stage the axis-3 home"; exit 1; }
ln -sfn "$D/a3/versions/1.0.0/bin" "$D/a3/bin"
ln -sfn "$D/a3/versions/1.0.0/lib" "$D/a3/lib"
rc=0; _run "$D/a3" "$D/a3.out" || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 3: a normal switch failed (rc=$rc):"; sed 's/^/      /' "$D/a3.out" | head -3; x=1; }
grep -q 'Now using Cyrius 9.9.9' "$D/a3.out" || { fail "axis 3: a successful switch did not say so"; x=1; }
for l in bin lib; do
    [ "$(_points_at "$D/a3/$l")" = "9.9.9" ] || { fail "axis 3: $l points at $(_points_at "$D/a3/$l") after a successful switch"; x=1; }
done
[ "$(cat "$D/a3/current")" = "9.9.9" ] || { fail "axis 3: current says $(cat "$D/a3/current") after a successful switch"; x=1; }
_home a3b || { echo "FAIL: cannot stage the axis-3b home"; exit 1; }
rm -f "$D/a3b/current"
rc=0; _run "$D/a3b" "$D/a3b.out" || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 3: a FRESH install (no bin/lib yet) failed (rc=$rc):"; sed 's/^/      /' "$D/a3b.out" | head -3; x=1; }
for l in bin lib; do
    [ "$(_points_at "$D/a3b/$l")" = "9.9.9" ] || { fail "axis 3: fresh install left $l as $(_points_at "$D/a3b/$l")"; x=1; }
done
left=$(ls -A "$D/a3" "$D/a3b" | grep 'cyrtmp' | tr '\n' ' ')
[ -z "$left" ] || { fail "axis 3: a switch left a temp behind: $left"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 3: a normal switch and a fresh install both re-point bin+lib, write current, leave no temp"

# ── axis 4: STATIC — the switch is atomic and checked, and current comes last ──
# _use_body <file> — the body of _cmd_use_v2 (to the next top-level fn)
_use_body() { awk '/^fn _cmd_use_v2\(/ { inb = 1 } inb && /^}/ { print; inb = 0 } inb { print }' "$1"; }
x=0
_use_body programs/cyriusly.cyr > "$D/body.now"
[ -s "$D/body.now" ] || { fail "axis 4: _cmd_use_v2 not found in programs/cyriusly.cyr — renamed? the detector is blind"; x=1; }
# _judge <bodyfile> -> a space-separated verdict list; empty means clean
_judge() {
    v=""
    grep -qE 'sys_unlink\((bin_link|lib_link)\)' "$1" && v="$v unlink_live_link"
    grep -qE '^[^#]*sys_symlink\((ver_bin|ver_lib), *(bin_link|lib_link)\)' "$1" && v="$v direct_symlink"
    grep -qE '^[^#]*_relink_atomic\(bin_link' "$1" || v="$v no_atomic_bin"
    grep -qE '^[^#]*_relink_atomic\(lib_link' "$1" || v="$v no_atomic_lib"
    # `current` must be written AFTER both links are in place
    cw=$(grep -n 'file_write_atomic(current_path' "$1" | head -1 | cut -d: -f1)
    lr=$(grep -nE '_relink_atomic\(lib_link|sys_symlink\(ver_lib' "$1" | head -1 | cut -d: -f1)
    if [ -n "$cw" ] && [ -n "$lr" ] && [ "$cw" -lt "$lr" ]; then v="$v current_before_links"; fi
    [ -z "$cw" ] && v="$v current_unchecked"
    printf '%s' "${v# }"
}
verdict=$(_judge "$D/body.now")
[ -z "$verdict" ] || { fail "axis 4: _cmd_use_v2 is not an atomic checked switch:$verdict"; x=1; }
grep -q '^fn _relink_atomic(' programs/cyriusly.cyr || { fail "axis 4: _relink_atomic is gone"; x=1; }
grep -qE '^[^#]*file_rename\(tmp, link_path\)' programs/cyriusly.cyr || { fail "axis 4: _relink_atomic does not rename its temp over the link — the link can still be ABSENT mid-switch"; x=1; }
# self-test: the 6.6.5 body must be REPORTED on every count
cat > "$D/body.665" <<'CYR'
fn _cmd_use_v2(ver_cstr, is_global): i64 {
    if (file_write_atomic(current_path, content, vlen + 1) != 0) { return 1; }
    var bin_link = _path_join(home, "bin");
    var lib_link = _path_join(home, "lib");
    sys_unlink(bin_link);
    sys_unlink(lib_link);
    sys_symlink(ver_bin, bin_link);
    sys_symlink(ver_lib, lib_link);
    return 0;
}
CYR
want='unlink_live_link direct_symlink no_atomic_bin no_atomic_lib current_before_links'
got=$(_judge "$D/body.665")
[ "$got" = "$want" ] || { fail "axis 4 self-test: the 6.6.5 body judged '$got', expected '$want' — the detector is blind to a shape it must catch"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: no unlink of a live link, both links through _relink_atomic (symlink + rename), current written last (detector self-tested on the 6.6.5 body)"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: cyriusly_use_switch_integrity (4 axes)"
