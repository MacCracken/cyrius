#!/bin/sh
# tests/gates/toolchain/check_stale_home_reaper.sh — 6.6.6 (bite 27b)
#
# A KILLED CHECK RUN'S STAGED CYRIUS_HOME IS RECLAIMED — AND A LIVE RUN'S IS NOT.
#
# THE DEFECT. Since v6.6.4 scripts/check.sh stages a ~19 MB throwaway CYRIUS_HOME under
# $TMPDIR and removes it from its EXIT/INT/TERM trap; bite 25b fixed the one path that
# `exec`ed past that trap. Neither helps against SIGKILL — no trap runs at all — and a
# killed run leaks the whole tree for ever. Five of them (95 MB) were sitting in /tmp when
# this was written, the oldest three hours old, on a box where /tmp is RAM.
#
# ⚠ THE DANGEROUS HALF IS THE REAP, NOT THE LEAK. Several lanes run check.sh on this box at
# once, and a reaper that deletes a LIVE run's home destroys that run — a worse failure than
# the leak it fixes. So the rule is the same one cross-os-selfhost.sh's `_co_reap_stale`
# follows for its `_cyaud_*` dirs: reap by AGE and by OWNERSHIP, never by count. Every home
# carries `.owner` (the creating shell's PID, written as the FIRST thing after mktemp) and
# a home is reclaimed only when it is older than $CYRIUS_CHECK_REAP_MINS minutes AND that
# PID is gone.
#
# AXES
#   1  a stale home whose owner is DEAD is reaped
#   2  a stale home whose owner is ALIVE survives — with the age gate turned OFF, so the
#      ONLY thing keeping it is the ownership check
#   3  a fresh home survives the default threshold (the age gate alone is enough)
#   4  ⭐ a REAL second check.sh run, staging a REAL home, survives a reaper running
#      concurrently with the age gate off — and that same run's home is gone once it
#      finishes, by its own trap. This is the concurrency proof; axis 2 is its unit form.
#   5  anti-vacuous for axis 4: the same old home with `.owner` REMOVED is reaped under the
#      same settings. Without this, axis 4 would also pass if the age gate had quietly
#      stayed on and nothing was ever eligible.
#   7-11 (6.6.20) the CLI's own `cyrius-<pid>[-t<nonce>][-<n>]` temp dirs: empty + old + dead
#      pid is reaped in every name shape (7); a NON-empty one is kept — the CLI's post-mortem
#      contract (8); a LIVE pid's survives with the age gate off (9, and its anti-vacuous
#      twin: the fresh dead one is then reaped); a fresh one survives the default (10); and
#      no other `cyrius-*` name is touched (11). Mutations (measured): the
#      `_chk_reap_dead_cli_tmpdirs` call removed -> axes 7 and 9b RED; `rmdir` -> `rm -rf`
#      -> axis 8 RED; the liveness check removed -> axis 9 RED; the name-shape filter
#      removed -> axis 11 RED.
#   12-16 (6.7.11, user decision 2026-10-13) — BY CONTENTS: a dead, old dir whose every entry is a
#      regular file in the CLI's scratch vocabulary is removed whole, in each shape this box's
#      /tmp held (cpp_<n>; the killed `cyrius check`'s cc_err + check_<n>.tmp.<n> + cpp_<n>;
#      wt_err; distlib's dlverify* + four cpp_; sha_out) and counted on its own line (12);
#      test_bin (with scratch beside it), test_out, the lsp build, an unknown name, a
#      subdirectory, a symlink, the no-home `deps/` cache and seven look-alike names each keep
#      their dir (13); the age gate (14) and a LIVE pid (15) still protect scratch; and the
#      vocabulary is DERIVED from cbt/ — every `_cbt_tmpfile("…")` literal and the computed names
#      (`_fuzz_leg`'s captures, the numbered str_builder names), the six computed call sites pinned
#      — and equals check.sh's two lists but the four named exclusions (16). Mutations (measured,
#      in a scratch copy of check.sh): reap anything -> 10 RED (axis 8's test_bin, axis 12's
#      count, every axis-13 row); rmdir-only again -> 7 RED (axis 12 six times, 15b); the
#      regular-file test dropped -> 3 RED (axis 12's count, the subdirectory and symlink rows);
#      the number check loosened to a prefix -> 4 RED (axis 12's count, look-alikes cpp_12x,
#      check_.tmp.5, cpp_); test_out added to the list -> 3 RED (axes 12, 13, 16); sha_out
#      dropped -> 3 RED (axis 12 twice, 16).
#   6  a NON-NUMERIC $CYRIUS_CHECK_REAP_MINS does not silently turn the age gate OFF. As
#      first written the threshold went straight into `[ "$n" -gt 0 ]`, so `=4h` made that
#      test error (`[: 4h: integer expected`, rc 2 -> false), the `-mmin` filter was skipped
#      and EVERY unowned home became eligible at ANY age — measured, a two-minute-old home
#      was reaped. That is live on a box where other lanes run an older check.sh and stage
#      homes with no `.owner`: one typo and a running lane's home is deleted. The knob is
#      validated and the complaint is loud.
#
# INDEPENDENT DERIVATION: every verdict is `[ -d "$home" ]` on the filesystem afterwards,
# never check.sh's "reaped N" line. The live owner in axis 2 is a process this gate started
# and can see; the live owner in axis 4 is a check.sh this gate started and whose home it
# located by listing $TMPDIR, not by reading check.sh's output.
#
# ⚠ The harness stubs scripts/install.sh (the stager — a real --refresh-only is a full
# toolchain pass and must never be pointed at a live store) and build/cyrius_check (a real
# run is the 13-minute suite). scripts/check.sh itself is the REAL file, copied.
#
# MUTATION PROOF (6.6.6, in a git-archive scratch tree, never the repo):
#   * the `_chk_reap_stale_homes` call removed -> 2 RED: axis 1 (the dead-owner home
#     survives) and axis 5 (so does the unowned one).
#   * the `_chk_home_is_owned` guard removed from the reap loop -> 4 RED across axes 1, 2b
#     and 4: the live unit home AND the live check.sh run's home are both deleted out from
#     under their owners.
#   * the `.owner` stamp removed from the staging path -> 2 RED, both on axis 4 (a real
#     run's home is unowned and is reaped); axes 1, 2b, 3 and 5 stay GREEN, so the stamp
#     and the guard are proven independently.
#   * the age gate disabled (every unowned home eligible) -> 1 RED: axis 3, a home created
#     seconds ago is destroyed.
#   * (bite 27's review) the `case`/`*[!0-9]*` validation of $CYRIUS_CHECK_REAP_MINS removed
#     -> 3 RED on axis 6: a 2-minute-old home is reaped, nothing in the output mentions the
#     knob, and the raw `[: 4h: integer expected` leaks through. Axes 1-5 stay green, so the
#     validation and the reap rule are proven independently.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
LIVE_PID=""
_cleanup() {
    [ -n "$LIVE_PID" ] && kill "$LIVE_PID" 2>/dev/null
    rm -rf "$D"
}
trap _cleanup EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

W="$D/w"
mkdir -p "$W/root/scripts" "$W/root/build" "$W/root/programs/checks" "$W/root/lib" \
         "$W/tmp" "$W/home"
cp "$ROOT/scripts/check.sh" "$W/root/scripts/check.sh"
cp VERSION "$W/root/"
: > "$W/root/lib/placeholder.cyr"
: > "$W/root/programs/checks/main.cyr"
printf '#!/bin/sh\nexit 0\n' > "$W/root/build/cycc"
chmod +x "$W/root/build/cycc"
printf '#!/bin/sh\nmkdir -p "$CYRIUS_HOME/bin"\nexit 0\n' > "$W/root/scripts/install.sh"
chmod +x "$W/root/scripts/install.sh"
# The stub driver: normally instant, and blocks on a sentinel file when the ENVIRONMENT
# says to, so this gate can hold ONE real check.sh run open at a known point (axis 4) while
# other runs of the same harness still finish instantly. Keying it on the sentinel file
# alone deadlocked: the reaper run that axis 4 fires also runs the driver, and it blocked
# on the same file (measured).
cat > "$W/root/build/cyrius_check" <<STUB
#!/bin/sh
if [ "\$1" = "--list-suites" ]; then printf 'alpha\n'; exit 0; fi
if [ "\${CHK_STUB_BLOCK:-}" = "1" ]; then
    echo "\$CYRIUS_HOME" > "$W/live.home"
    while [ -f "$W/block" ]; do sleep 0.2; done
fi
exit 0
STUB
chmod +x "$W/root/build/cyrius_check"
touch -d '2038-01-01' "$W/root/build/cyrius_check"

# Run the real check.sh in the harness. $1 = CYRIUS_CHECK_REAP_MINS, rest = argv.
_run() {
    _rm=$1
    shift
    RC=0
    ( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" \
        CYRIUS_CHECK_REAP_MINS="$_rm" sh scripts/check.sh "$@" ) > "$W/out" 2>&1 || RC=$?
}

# A PID that is certainly gone: start something and reap it.
sh -c 'exit 0' &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null || true
# A PID that is certainly alive for the length of this gate.
sleep 120 >/dev/null 2>&1 &
LIVE_PID=$!

_mkhome() {  # $1 = suffix, $2 = owner pid (or "" for none), $3 = age in minutes
    _h="$W/tmp/cyrius-check-home.$1"
    mkdir -p "$_h/versions"
    [ -n "$2" ] && printf '%s\n' "$2" > "$_h/.owner"
    if [ "$3" != "0" ]; then
        touch -d "$3 minutes ago" "$_h"
    fi
    echo "$_h"
}

echo "axis 1/2/3: stale+dead is reaped, stale+alive and fresh are not"
H_DEAD=$(_mkhome dead "$DEAD_PID" 300)
H_LIVE=$(_mkhome live "$LIVE_PID" 300)
H_FRESH=$(_mkhome fresh "" 0)
# Default threshold (240 min): the two 300-minute homes are eligible by age, the fresh one
# is not. Ownership then decides between the two eligible ones.
_run 240 alpha
[ -d "$H_DEAD" ]  && _fail "a 5-hour-old home whose owner is dead was NOT reaped"
[ -d "$H_LIVE" ]  || _fail "a home owned by a LIVE process was reaped — a concurrent run would have been destroyed"
[ -d "$H_FRESH" ] || _fail "a home created seconds ago was reaped"

echo "axis 2b: with the age gate OFF, ownership alone still protects the live home"
_run 0 alpha
[ -d "$H_LIVE" ] || _fail "with CYRIUS_CHECK_REAP_MINS=0 the live-owner home was reaped — the ownership check is not what protects it"

echo "axis 5: with the age gate off and no owner, an old home IS reaped"
rm -f "$H_LIVE/.owner"
_run 0 alpha
[ -d "$H_LIVE" ] && _fail "an unowned home survived a reap with the age gate off — axis 2b is vacuous"

echo "axis 4: a REAL concurrent check.sh run's home survives a reaper"
: > "$W/block"
rm -f "$W/live.home"
( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" \
    CYRIUS_CHECK_REAP_MINS=240 CHK_STUB_BLOCK=1 sh scripts/check.sh alpha ) > "$W/bg.out" 2>&1 </dev/null &
BG=$!
# Wait for that run to have staged and entered the driver.
_i=0
while [ ! -s "$W/live.home" ] && [ "$_i" -lt 100 ]; do
    sleep 0.1
    _i=$((_i + 1))
done
BGHOME=$(cat "$W/live.home" 2>/dev/null || true)
case "$BGHOME" in
    "$W/tmp/cyrius-check-home."*) : ;;
    *) _fail "the concurrent run staged no home under the harness TMPDIR (got '$BGHOME') — axis 4 is vacuous" ;;
esac
[ -d "$BGHOME" ] || _fail "the concurrent run's home does not exist while it is running"
# Age it past any threshold AND run a reaper with the age gate off: the ONLY thing that can
# save it now is its .owner stamp naming a process that is still alive.
if [ -n "$BGHOME" ] && [ -d "$BGHOME" ]; then
    touch -d '300 minutes ago' "$BGHOME"
    _run 0 alpha
    [ -d "$BGHOME" ] || _fail "a reaper deleted a LIVE check.sh run's staged CYRIUS_HOME"
    OWNED=$(cat "$BGHOME/.owner" 2>/dev/null || true)
    case "$OWNED" in
        ''|*[!0-9]*) _fail "the live run's home carries no usable .owner stamp ('$OWNED')" ;;
        *) kill -0 "$OWNED" 2>/dev/null || _fail ".owner=$OWNED is not a live process — the stamp is not the running check.sh" ;;
    esac
fi
# Let it finish; its own trap must take the home with it.
rm -f "$W/block"
wait "$BG" 2>/dev/null || true
[ -n "$BGHOME" ] && [ -d "$BGHOME" ] && _fail "the concurrent run finished and left its staged home behind"

echo "axis 6: a non-numeric CYRIUS_CHECK_REAP_MINS does not disable the age gate"
# Two unowned homes — one two minutes old, one five hours. A knob the script cannot parse
# must fall back to the default threshold, NOT to "no threshold": the young one survives,
# the old one is still reaped (otherwise a fallback of "never reap" would pass this too).
H_YOUNG=$(_mkhome young "" 2)
H_OLD=$(_mkhome oldish "" 300)
_run 4h alpha
[ -d "$H_YOUNG" ] || _fail "CYRIUS_CHECK_REAP_MINS=4h reaped a 2-minute-old home — a bad value turned the age gate OFF instead of failing"
[ -d "$H_OLD" ] && _fail "CYRIUS_CHECK_REAP_MINS=4h left a 5-hour-old unowned home — the fallback is 'never reap', not the default threshold"
grep -q "CYRIUS_CHECK_REAP_MINS" "$W/out" || _fail "a non-numeric CYRIUS_CHECK_REAP_MINS was ignored SILENTLY — nothing in the output mentions it"
grep -qE "integer expected|not a valid identifier" "$W/out" && _fail "the raw shell error from an unvalidated threshold is still reaching the output"

echo "axis 7-11 (6.6.20): the CLI's own cyrius-<pid> temp dirs of DEAD processes, rmdir-only"
# A signal death skips the CLI's cleanup (SIGPIPE from `cyrius … | head` leaves an EMPTY
# dir; SIGKILL leaves test_bin), and 6.6.0–6.6.5 CLIs never cleaned up at all. check.sh
# reaps them by age and by the pid in the NAME, and only with rmdir.
_mkcli() {  # $1 = name under the harness TMPDIR, $2 = age in minutes, $3 = a file to put inside (or "")
    _c="$W/tmp/$1"
    mkdir -p "$_c"
    [ -n "$3" ] && echo x > "$_c/$3"
    [ "$2" != "0" ] && touch -d "$2 minutes ago" "$_c"
    echo "$_c"
}
C_DEAD=$(_mkcli "cyrius-$DEAD_PID" 300 "")
C_DEAD_T=$(_mkcli "cyrius-$DEAD_PID-t12345" 300 "")
C_DEAD_N=$(_mkcli "cyrius-$DEAD_PID-t12345-3" 300 "")
C_DEAD_FULL=$(_mkcli "cyrius-$DEAD_PID-7" 300 "test_bin")
C_LIVE=$(_mkcli "cyrius-$LIVE_PID" 300 "")
C_FRESH=$(_mkcli "cyrius-$DEAD_PID-9" 0 "")
C_OTHER1=$(_mkcli "cyrius-check-skips.abc123" 300 "")
C_OTHER2=$(_mkcli "cyrius-${DEAD_PID}x" 300 "")
C_OTHER3=$(_mkcli "cyrius-$DEAD_PID-lsp" 300 "")
_run 240 alpha
# axis 7: empty + old + dead pid, in each name shape the CLI makes -> reaped
[ -d "$C_DEAD" ]   && _fail "axis 7: an empty, 5-hour-old cyrius-<dead pid> dir was NOT reaped"
[ -d "$C_DEAD_T" ] && _fail "axis 7: an empty cyrius-<dead pid>-t<nonce> dir was NOT reaped"
[ -d "$C_DEAD_N" ] && _fail "axis 7: an empty cyrius-<dead pid>-t<nonce>-<n> dir was NOT reaped"
grep -q 'reaped 3 empty cyrius-<pid> temp dir' "$W/out" || _fail "axis 7: check.sh did not report the 3 reaped temp dirs: $(grep reaped "$W/out" || true)"
# axis 8: NON-empty is the CLI's post-mortem contract -> kept, contents intact
[ -f "$C_DEAD_FULL/test_bin" ] || _fail "axis 8: a dead pid's NON-empty temp dir was deleted — rmdir-only is the contract"
# axis 10: the age gate — a fresh empty dead-pid dir survives the default threshold
[ -d "$C_FRESH" ] || _fail "axis 10: a cyrius-<pid> dir created seconds ago was reaped at the default threshold"
# axis 11: names of any other shape are never touched
[ -d "$C_OTHER1" ] || _fail "axis 11: cyrius-check-skips.* was reaped by the CLI-temp reaper"
[ -d "$C_OTHER2" ] || _fail "axis 11: cyrius-<digits>x was reaped — not a CLI temp-dir name"
[ -d "$C_OTHER3" ] || _fail "axis 11: cyrius-<pid>-lsp was reaped — not a CLI temp-dir name"
# axis 9: with the age gate OFF, a LIVE pid's empty dir survives — the pid alone protects it
_run 0 alpha
[ -d "$C_LIVE" ] || _fail "axis 9: an empty cyrius-<LIVE pid> dir was reaped — a running CLI would lose its temp dir"
[ -d "$C_FRESH" ] && _fail "axis 9 (anti-vacuous): with the age gate off the fresh dead-pid dir survived — nothing was eligible"
rm -rf "$C_DEAD_FULL" "$C_LIVE" "$C_OTHER1" "$C_OTHER2" "$C_OTHER3"

echo "axis 12-16 (6.7.11): a dead pid's dir holding ONLY compile scratch is reaped whole; anything else keeps it"
# A run killed mid-compile leaves the in-flight compile's temporaries — measured on this box
# 2026-10-13: 485 dead-pid dirs in /tmp held only these names (cpp_<n>, cc_err,
# check_<n>.tmp.<n>, wt_err, dlverify*, sha_out), 3 held test_bin + test_out. check.sh removes a
# dir whose every entry is a regular file named in the CLI's scratch vocabulary (user decision
# 2026-10-13); a post-mortem (test_bin / test_out / the lsp build), a directory, a link or any
# name not listed keeps the dir and everything in it.
_mkcli2() {  # $1 = name under the harness TMPDIR, $2 = age in minutes, rest = files to put inside
    _c="$W/tmp/$1"; _a=$2; shift 2
    mkdir -p "$_c"
    for _f in "$@"; do echo x > "$_c/$_f"; done
    [ "$_a" != "0" ] && touch -d "$_a minutes ago" "$_c"
    echo "$_c"
}
S_CPP=$(_mkcli2 "cyrius-$DEAD_PID-21" 300 "cpp_4242")
S_KILL=$(_mkcli2 "cyrius-$DEAD_PID-22" 300 cc_err "check_4242.tmp.4242" cpp_4242)
S_WT=$(_mkcli2 "cyrius-$DEAD_PID-t77-23" 300 wt_err)
S_DL=$(_mkcli2 "cyrius-$DEAD_PID-24" 300 dlverifyerr0 dlverifyerr5 "dlverifyout2.tmp.4243" cpp_4244 cpp_4245 cpp_4246 cpp_4247)
S_SHA=$(_mkcli2 "cyrius-$DEAD_PID-25" 300 sha_out)
K_TEST=$(_mkcli2 "cyrius-$DEAD_PID-31" 300 test_bin test_out cpp_4242)
K_TOUT=$(_mkcli2 "cyrius-$DEAD_PID-32" 300 test_out)
K_LSP=$(_mkcli2 "cyrius-$DEAD_PID-33" 300 lsp)
K_UNK=$(_mkcli2 "cyrius-$DEAD_PID-34" 300 cpp_4242 cc_err gate_keepme)
K_DIR=$(_mkcli2 "cyrius-$DEAD_PID-35" 300 cc_err)
mkdir -p "$K_DIR/cpp_9" && echo x > "$K_DIR/cpp_9/inner" && touch -d '300 minutes ago' "$K_DIR"
K_LNK=$(_mkcli2 "cyrius-$DEAD_PID-36" 300 wt_err)
echo keep > "$W/lnk_target" && ln -s "$W/lnk_target" "$K_LNK/cc_err" && touch -h -d '300 minutes ago' "$K_LNK" 2>/dev/null; touch -d '300 minutes ago' "$K_LNK"
# look-alikes, one per dir (one non-scratch name keeps a whole dir, so they cannot share one)
K_LIKE=""
_i=40
for _n in cpp_12x "check_.tmp.5" "cc_err.tmp." "cc_err.tmp.5x" cpp_ cc_err2 "xcpp_12"; do
    _i=$((_i + 1))
    K_LIKE="$K_LIKE $(_mkcli2 "cyrius-$DEAD_PID-$_i" 300 "$_n")"
done
K_DEPS=$(_mkcli2 "cyrius-$DEAD_PID-38" 300 sha_out)
mkdir -p "$K_DEPS/deps/sib" && echo x > "$K_DEPS/deps/sib/f" && touch -d '300 minutes ago' "$K_DEPS"
S_LIVE=$(_mkcli2 "cyrius-$LIVE_PID-39" 300 cc_err cpp_4242)
S_YOUNG=$(_mkcli2 "cyrius-$DEAD_PID-50" 0 cc_err cpp_4242)
_run 240 alpha
# axis 12: scratch only + old + dead -> reaped whole, in every shape the census found
for _s in "$S_CPP" "$S_KILL" "$S_WT" "$S_DL" "$S_SHA"; do
    [ -d "$_s" ] && _fail "axis 12: a dead pid's dir holding only scratch ($(ls -A "$_s" | tr '\n' ' ')) was NOT reaped"
done
grep -q 'reaped 5 cyrius-<pid> temp dir(s) holding only compile scratch' "$W/out" \
    || _fail "axis 12: check.sh did not report the 5 scratch dirs separately: $(grep reaped "$W/out" || true)"
# axis 13: a post-mortem, an unknown name, a directory, a link, a look-alike -> kept, contents intact
[ -f "$K_TEST/test_bin" ] && [ -f "$K_TEST/cpp_4242" ] || _fail "axis 13: a dir holding test_bin (with scratch beside it) was touched — the post-mortem contract"
[ -f "$K_TOUT/test_out" ] || _fail "axis 13: a dir holding test_out was reaped"
[ -f "$K_LSP/lsp" ] || _fail "axis 13: a dir holding the lsp build was reaped"
[ -f "$K_UNK/gate_keepme" ] && [ -f "$K_UNK/cpp_4242" ] || _fail "axis 13: a dir holding an unknown name lost files — all or nothing"
[ -f "$K_DIR/cpp_9/inner" ] && [ -f "$K_DIR/cc_err" ] || _fail "axis 13: a dir holding a SUBDIRECTORY was reaped"
[ -L "$K_LNK/cc_err" ] && [ -f "$W/lnk_target" ] || _fail "axis 13: a dir holding a SYMLINK named like scratch was reaped (or its target)"
for _k in $K_LIKE; do
    [ -d "$_k" ] || _fail "axis 13: a dir holding only a look-alike of a scratch name was reaped (${_k##*/})"
done
[ -f "$K_DEPS/deps/sib/f" ] || _fail "axis 13: a dir holding the no-home dep cache (deps/) was reaped"
# axis 14: the age gate holds for scratch too
[ -f "$S_YOUNG/cc_err" ] || _fail "axis 14: a scratch dir created seconds ago was reaped at the default threshold"
# axis 15: with the age gate OFF, a LIVE pid's scratch survives (a running compile's temporaries)
_run 0 alpha
[ -f "$S_LIVE/cpp_4242" ] || _fail "axis 15: a LIVE pid's in-flight compile scratch was reaped"
[ -d "$S_YOUNG" ] && _fail "axis 15 (anti-vacuous): with the age gate off the young dead-pid scratch dir survived — nothing was eligible"
# axis 16: the vocabulary is the CLI's, derived from cbt/ — never a hand list that drifts
#   literal  `_cbt_tmpfile("X")`: X scratch, X ending in `_` a numbered prefix, unless excluded;
#   computed (pinned site count): `_fuzz_leg(…, "X")` captures; a `str_builder_add_cstr(…, "X")`
#   followed by `str_builder_add_int(` in a fn that passes a built name to `_cbt_tmpfile` (numbered).
#   EXCLUDED, by name and why: test_out (beside test_bin, the post-mortem), lsp (the build `cyrius
#   lsp` tells the user to copy), deps / locked-deps (directories: a no-home dep cache, a vendored tree).
EXCL="test_out lsp deps locked-deps"
grep -ho '_cbt_tmpfile("[^"]*")' "$ROOT"/cbt/*.cyr | sed 's/^_cbt_tmpfile("//; s/")$//' | sort -u > "$D/lit"
NLIT=$(wc -l < "$D/lit" | tr -d ' ')
[ "$NLIT" -ge 25 ] || _fail "axis 16: only $NLIT _cbt_tmpfile(\"…\") literals found in cbt/ — the reader is not reading (floor 25)"
NCOMP=$(grep -h '_cbt_tmpfile(' "$ROOT"/cbt/*.cyr | grep -v '_cbt_tmpfile("' | grep -vc '^fn _cbt_tmpfile' || true)
[ "$NCOMP" = 6 ] || _fail "axis 16: cbt/ has $NCOMP computed _cbt_tmpfile( names (6 classified: _cbt_tmpexe's two, _fuzz_cap_new, _covx_dump_path, dlverifyerr/out) — classify the new one here and in check.sh"
grep -ho '_fuzz_leg([^,]*, "[^"]*")' "$ROOT"/cbt/*.cyr | sed 's/.*"\([^"]*\)")$/\1/' | sort -u > "$D/comp"
for f in "$ROOT"/cbt/*.cyr; do
    awk '/^fn / { if (inb) for (k in c) print k; inb = 0; split("", c); prev = "" }
         /_cbt_tmpfile\(str_data\(str_builder_build/ { inb = 1 }
         { if (prev != "" && $0 ~ /str_builder_add_int\(/) c[prev] = 1; prev = "" }
         match($0, /str_builder_add_cstr\([a-z_]+, "[^"]*"\);/) { t = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", t); sub(/".*/, "", t); prev = t }
         END { if (inb) for (k in c) print k }' "$f"
done | sort -u > "$D/compn"
for w in fuzz_outa fuzz_outb; do grep -qx "$w" "$D/comp" || _fail "axis 16: the derivation lost computed name $w"; done
for w in cov_ dlverifyerr dlverifyout; do grep -qx "$w" "$D/compn" || _fail "axis 16: the derivation lost computed numbered name $w"; done
{ grep -v '_$' "$D/lit"; cat "$D/comp"; } | sort -u > "$D/want_plain"
{ grep '_$' "$D/lit"; cat "$D/compn"; } | sort -u > "$D/want_n"
for x in $EXCL; do grep -vx "$x" "$D/want_plain" > "$D/w2" || true; mv "$D/w2" "$D/want_plain"; done
VOC=$(sed -n 's/^_CHK_CLI_SCRATCH="\(.*\)"$/\1/p' "$ROOT/scripts/check.sh")
VOCN=$(sed -n 's/^_CHK_CLI_SCRATCH_N="\(.*\)"$/\1/p' "$ROOT/scripts/check.sh")
[ -n "$VOC" ] && [ -n "$VOCN" ] || _fail "axis 16: scripts/check.sh carries no _CHK_CLI_SCRATCH / _CHK_CLI_SCRATCH_N list"
printf '%s\n' $VOC | sort -u > "$D/have_plain"
printf '%s\n' $VOCN | sort -u > "$D/have_n"
cmp -s "$D/want_plain" "$D/have_plain" || _fail "axis 16: check.sh's scratch names differ from cbt/'s: missing [$(comm -23 "$D/want_plain" "$D/have_plain" | tr '\n' ' ')] extra [$(comm -13 "$D/want_plain" "$D/have_plain" | tr '\n' ' ')]"
cmp -s "$D/want_n" "$D/have_n" || _fail "axis 16: check.sh's numbered scratch names differ from cbt/'s: missing [$(comm -23 "$D/want_n" "$D/have_n" | tr '\n' ' ')] extra [$(comm -13 "$D/want_n" "$D/have_n" | tr '\n' ' ')]"
rm -rf "$K_TEST" "$K_TOUT" "$K_LSP" "$K_UNK" "$K_DIR" "$K_LNK" $K_LIKE "$K_DEPS" "$S_LIVE" "$S_YOUNG"

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: stale staged CYRIUS_HOMEs and dead CLIs' empty or scratch-only temp dirs are reaped; live ones and post-mortems are not"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
