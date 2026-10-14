#!/bin/sh
# selfbuild_poison_scrubbed.sh — 6.7.8. An inherited CYRIUS_POISON never reaches a SELF-BUILD,
# and still reaches the tests of a `CYRIUS_POISON=1 sh scripts/check.sh` run.
#
# WHY: the compiler includes lib/alloc.cyr, which reads CYRIUS_POISON at compile time (until
# 6.7.11 any value — an EMPTY one included — switched the allocator poison mode on; since 6.7.11
# `1` is on, `0` or empty off, and any other value is refused by name), so a CYRIUS_POISON exported
# in the caller's shell built a poison-mode compiler wherever a script compiled src/: measured,
# `CYRIUS_POISON=1 sh scripts/seed-derive-cycc.sh` FAILED ("seed-derived cycc != committed
# build/cycc" — cybs reads no environment, gen1 does), and the release gate's step-1 fixpoint
# could never pass under it. The self-build scripts now unset it as they unset CYRIUS_BOUNDS
# (C2-7) — the user's decision, 2026-10-10 — with check.sh the other way round: its SUITE keeps
# the variable (a poison run of the whole suite is a workflow), only its own two self-builds (the
# staged toolchain refresh, the check driver) run through `_chk_selfbuild`, which unsets it.
#
#   P0  (premise, anti-vacuous) cycc compiling src/main.cyr with CYRIUS_POISON=1 writes a
#       compiler that differs from the one it writes with the variable unset, and with
#       CYRIUS_POISON=no writes nothing (refused by name, 6.7.11) — so the scrub matters: an
#       inherited value builds a different compiler or stops the build. It UNSETS (P3b). (Until
#       6.7.11 an EMPTY value built the poisoned compiler too; it is off now — the rule itself is
#       tests/gates/platform/poison_env_rung.sh's.)
#   P1  scripts/seed-derive-cycc.sh, release-gate.sh, version-bump.sh and bootstrap/bootstrap.sh
#       unset CYRIUS_POISON before their first line that builds src/main.cyr. (6.7.9: every OTHER
#       self-build script — DERIVED, both variables — is E4's in bounds_mode_checked.sh.)
#   P2  `CYRIUS_POISON=1 sh scripts/seed-derive-cycc.sh` is green (it was red). A seed-derive that
#       is red WITHOUT the variable too fails here BY NAME — this gate cannot judge it then.
#   P3  scripts/check.sh: (a) unsets CYRIUS_POISON nowhere at top level — the suite keeps it;
#       (b) `_chk_selfbuild`, run out of check.sh itself, hands its command an environment with
#       CYRIUS_POISON unset (from =1 and from an empty value) and leaves the caller's in place;
#       (c) derived: every line of check.sh that runs the compiler ("$CC") or scripts/install.sh
#       goes through `_chk_selfbuild` (floor 2: the staging refresh and the driver build).
#
# MUTATION LEDGER (each measured RED in a scratch copy of the tree):
#   MP1 seed-derive-cycc.sh's `unset CYRIUS_POISON` removed            -> RED P1, P2
#   MP2 release-gate.sh's removed                                      -> RED P1
#   MP3 version-bump.sh's removed                                      -> RED P1
#   MP4 bootstrap/bootstrap.sh's removed                               -> RED P1
#   MP5 seed-derive's unset replaced by `CYRIUS_POISON=` (blanked)     -> RED P1, P2 (6.7.8);
#       RED P1 since 6.7.11 (a blank is off now, so seed-derive under =1 stays green)
#   MP6 check.sh unsets CYRIUS_POISON at top level                     -> RED P3a
#   MP7 `_chk_selfbuild` blanks the variable instead of unsetting it   -> RED P3b
#   MP8 check.sh's staging refresh not routed through _chk_selfbuild   -> RED P3c
#   MP9 check.sh's driver build not routed through _chk_selfbuild      -> RED P3c
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: selfbuild_poison_scrubbed: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: selfbuild_poison_scrubbed: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

# ── P0 — the premise ──────────────────────────────────────────────────────────────────────────
x=$FAIL
( unset CYRIUS_POISON; "$CC" < src/main.cyr > "$T/c.off" 2> /dev/null ) || fail "P0: cycc could not compile src/main.cyr (variable unset)"
( CYRIUS_POISON=1; export CYRIUS_POISON; "$CC" < src/main.cyr > "$T/c.on" 2> /dev/null ) || fail "P0: cycc could not compile src/main.cyr under CYRIUS_POISON=1"
no_rc=0
( CYRIUS_POISON=no; export CYRIUS_POISON; "$CC" < src/main.cyr > "$T/c.no" 2> "$T/c.no.err" ) || no_rc=$?
if [ "$FAIL" = "$x" ]; then
    cmp -s "$T/c.off" "$T/c.on" && fail "P0: CYRIUS_POISON=1 does not change a self-build — the premise of this gate is gone (re-derive it)"
    if [ "$no_rc" = 0 ] || [ -s "$T/c.no" ] || ! grep -q 'CYRIUS_POISON must be 0 or 1 (or unset): no' "$T/c.no.err"; then
        fail "P0: CYRIUS_POISON=no is not refused by name (rc $no_rc, $(wc -c < "$T/c.no" | tr -d ' ') B written) — re-derive the premise (6.7.11)"
    fi
fi
[ "$FAIL" = "$x" ] && echo "  ok P0: CYRIUS_POISON=1 changes cycc(src) ($(wc -c < "$T/c.off") B unset, $(wc -c < "$T/c.on") B poisoned) and CYRIUS_POISON=no stops it (refused by name)"
rm -f "$T/c.off" "$T/c.on" "$T/c.no" "$T/c.no.err"

# ── P1 — the four self-build scripts unset it before they build ───────────────────────────────
x=$FAIL
for s in scripts/seed-derive-cycc.sh scripts/release-gate.sh scripts/version-bump.sh bootstrap/bootstrap.sh; do
    u=$(grep -nE '^[[:space:]]*unset([[:space:]]+[A-Z_]+)*[[:space:]]+CYRIUS_POISON([[:space:]]|$)' "$s" | head -1 | cut -d: -f1 || true)
    b=$(grep -nE 'src/main\.cyr' "$s" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1 || true)
    if [ -z "$u" ]; then fail "P1: $s does not unset CYRIUS_POISON (an inherited one builds a poison-mode compiler)"
    elif [ -n "$b" ] && [ "$u" -gt "$b" ]; then fail "P1: $s unsets CYRIUS_POISON at line $u, after its first build line $b"
    else echo "  ok P1: $s unsets CYRIUS_POISON (line $u) before it builds${b:+ (line $b)}"; fi
done

# ── P2 — seed-derive under an inherited CYRIUS_POISON=1 ──────────────────────────────────────
x=$FAIL
rc=0
( CYRIUS_POISON=1; export CYRIUS_POISON; sh scripts/seed-derive-cycc.sh ) > "$T/sd.on" 2>&1 || rc=$?
if [ "$rc" = 0 ] && grep -q 'machine-derivable from the' "$T/sd.on"; then
    echo "  ok P2: CYRIUS_POISON=1 sh scripts/seed-derive-cycc.sh is green"
else
    rc0=0
    ( unset CYRIUS_POISON; sh scripts/seed-derive-cycc.sh ) > "$T/sd.off" 2>&1 || rc0=$?
    if [ "$rc0" = 0 ]; then
        fail "P2: seed-derive is green alone and RED under an inherited CYRIUS_POISON=1 (rc $rc): $(grep -m1 'FAIL' "$T/sd.on")"
    else
        fail "P2: cannot judge — seed-derive is RED without CYRIUS_POISON too (rc $rc0): $(grep -m1 'FAIL' "$T/sd.off")"
    fi
fi

# ── P3 — check.sh keeps it for the suite and scrubs its own self-builds ──────────────────────
x=$FAIL
# (a) no top-level scrub: an unset / blanking assignment at column 0 (inside `_chk_selfbuild`'s
# subshell it is the point).
g=$(sed 's/#.*//' scripts/check.sh | grep -nE '^(unset([[:space:]]+[A-Z_]+)*[[:space:]]+CYRIUS_POISON([[:space:]]|$)|(export[[:space:]]+)?CYRIUS_POISON=)' | head -1 || true)
[ -z "$g" ] || fail "P3a: check.sh drops CYRIUS_POISON for the whole suite (line $g) — a poison run of the suite would test nothing in the poison mode"
# (b) the real helper, out of check.sh.
grep -E '^_chk_selfbuild\(\)' scripts/check.sh > "$T/sb.sh"
if [ ! -s "$T/sb.sh" ]; then
    fail "P3b: check.sh defines no _chk_selfbuild"
else
    for v in 1 ''; do
        got=$(CYRIUS_POISON="$v" sh -c '. "$1"; export CYRIUS_POISON; _chk_selfbuild sh -c '"'"'echo "child=${CYRIUS_POISON-unset}"'"'"'; echo "parent=${CYRIUS_POISON-unset}"' _ "$T/sb.sh" 2>&1 | tr '\n' ' ')
        [ "$got" = "child=unset parent=$v " ] || fail "P3b: _chk_selfbuild with CYRIUS_POISON='$v': want 'child=unset parent=$v', got '$got'"
    done
fi
# (c) derived: every line that runs the compiler or the installer.
sed 's/#.*//' scripts/check.sh | grep -nE '(\|[[:space:]]*(_chk_selfbuild[[:space:]]+)?"\$CC"|sh[[:space:]]+"\$ROOT/scripts/install\.sh")' > "$T/sites" || true
n=$(grep -c . "$T/sites" || true)
if [ "$n" -lt 2 ]; then
    fail "P3c: found $n self-build line(s) in check.sh (want >= 2: the staging refresh and the driver build) — the scan is blind"
else
    while IFS= read -r l; do
        case "$l" in *_chk_selfbuild*) ;; *) fail "P3c: check.sh line ${l%%:*} builds without _chk_selfbuild: ${l#*:}" ;; esac
    done < "$T/sites"
fi
[ "$FAIL" = "$x" ] && echo "  ok P3: check.sh keeps CYRIUS_POISON for its suite; _chk_selfbuild unsets it for the child (from =1 and from empty) and not for the caller; its $n self-build lines run through it"

[ "$FAIL" = 0 ] || { echo "FAIL: selfbuild_poison_scrubbed ($FAIL)"; exit 1; }
echo "PASS: selfbuild_poison_scrubbed (an inherited CYRIUS_POISON reaches no self-build; check.sh's suite keeps it)"
