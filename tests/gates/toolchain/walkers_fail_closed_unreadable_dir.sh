#!/bin/sh
# Gate: every tree walker FAILS, by name, on a directory it cannot list (6.6.10, bite 15).
#
# THE DEFECT. lib/fs.cyr's dir_list folded an open or getdents error into "an empty
# directory" on every arm (Linux getdents64, Darwin getdirentries, agnos, the Windows
# FindFirstFileW lister), and is_dir — an open+getdents probe — answered 0 for a directory
# the caller could not read, so each walker took an unreadable subdirectory for a FILE,
# filtered it out by extension, and never tried to list it. Measured on 6.6.9 in a project
# with a failing tests/bad/fails.tcyr and a misformatted src/bad/x.cyr, after
# `chmod 000 tests/bad src/bad`:
#   `cyrius test`  "1 passed, 1 failed" rc 1  →  "1 passed, 0 failed" rc 0
#   `cyrius audit` rc 1 (fmt FAIL, 2 lint warnings)  →  rc 0, "ok: format clean", "ok: lint clean"
# (`cyrius coverage` rose 50 % → 100 % the same way; that is coverage_corpus_and_failopen.sh
# axes 15-17.)
#
# THE FIX. lib/fs.cyr: an error channel (dir_list_checked / dir_walk_checked /
# find_files_checked) and a stat-based is_dir (a directory you cannot read is still a
# directory). Every walker in cbt/, lib/audit_walk.cyr and the programs lists through it and
# fails by name. The lister arms themselves run on every host in
# tests/tcyr/crossos/fs_walk_fails_closed.tcyr.
#
# AXES (each: exit status, the directory named, and no green verdict)
#   W0  control: the READABLE fixture — test "1 passed, 1 failed" rc 1; audit fmt FAIL
#   W1  `cyrius test`            (bare auto-discover)   tests/bad unreadable
#   W2  `cyrius tests tests`     (the plural verb)
#   W3  `cyrius audit`           src/bad unreadable — fmt and lint walkers
#   W4  `cyrius fuzz`            fuzz/sub unreadable
#   W5  `cyrius bench benches`   benches/sub unreadable
#   W6  `cyrius deps --lock`     lib/nested unreadable — no lock written
#   W7  `cyrius deps --verify`   lib/nested unreadable after a clean lock
#   W8  `cyrius clean`           build/ unreadable
#   W9  cyrius_type_audit        src/ unreadable
#   W10 cyriusly list            <home>/versions unreadable
# Every row needs a mode-000 directory and a non-root user (root reads one), so under uid 0
# (the AGNOS CI container) they SKIP, by name; W0 still runs.
#
# PROVEN RED: this gate run against the 6.6.9 tree (6d12c1e6, build/cycc unchanged) fails 17
# of its 20 checks — every W1-W10 row; only the two W0 controls and W7's premise pass.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=walkers_fail_closed_unreadable_dir
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $NAME — needs timeout(1)"; exit 1; }
ulimit -c 0 2>/dev/null || :
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# Restore every mode before removing — rm cannot descend a mode-000 directory.
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT

build_one() {   # $1 source (relative to ROOT), $2 dest
    ( cd "$ROOT" && "$CC" < "$1" > "$2" 2> "$T/build.err" ) || {
        echo "FAIL: $NAME — could not build $1"; sed -n '1,5p' "$T/build.err"; exit 1; }
    [ "$(wc -c < "$2")" -gt 20000 ] || { echo "FAIL: $NAME — $1 built to $(wc -c < "$2") bytes"; exit 1; }
    chmod +x "$2"
}
B="$T/bin"; mkdir -p "$B" "$T/hh" "$T/cyhome"
build_one cbt/cyrius.cyr "$B/cyrius"
build_one programs/cyrfmt.cyr "$B/cyrfmt"
build_one programs/cyrlint.cyr "$B/cyrlint"
build_one programs/cyrdoc.cyr "$B/cyrdoc"
build_one programs/cyrius_type_audit.cyr "$B/cyrius_type_audit"
build_one programs/cyriusly.cyr "$B/cyriusly"
cp "$CC" "$B/cycc"
cy() {   # $1 project dir, rest: the verb → $T/o, RC
    _d=$1; shift
    RC=0
    ( cd "$_d" && HOME="$T/hh" CYRIUS_HOME="$T/cyhome" CYRIUS_TEST_TIMEOUT=60 timeout 300 "$B/cyrius" "$@" ) > "$T/o" 2>&1 || RC=$?
}
has() { if grep -qF -- "$1" "$T/o"; then echo yes; else echo no; fi; }

P="$T/proj"; mkdir -p "$P/src/bad" "$P/tests/bad" "$P/fuzz/sub" "$P/benches/sub"
printf '[package]\nname = "wk"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
printf '# main\nfn main(): i64 {\n    return 0;\n}\n' > "$P/src/main.cyr"
printf '# bad\nfn bad_one( ):i64 {return 0;}   \n' > "$P/src/bad/x.cyr"
printf 'var r = 0;\nsyscall(60, r);\n' > "$P/tests/ok.tcyr"
printf 'var r = 1;\nsyscall(60, r);\n' > "$P/tests/bad/fails.tcyr"
printf 'var r = 1;\nsyscall(60, r);\n' > "$P/fuzz/sub/f.fcyr"
printf 'var r = 1;\nsyscall(60, r);\n' > "$P/benches/sub/b.bcyr"

# ── W0: the readable control — what the unreadable runs must never look like ────────────
cy "$P" test
check "W0 control: \`cyrius test\` over the readable tree says '1 passed, 1 failed', rc 1" "yes 1" "$(has '1 passed, 1 failed') $RC"
cy "$P" audit
check "W0 control: \`cyrius audit\` flags src/bad/x.cyr for formatting, rc non-zero" "yes yes" "$(has 'x.cyr') $([ "$RC" -ne 0 ] && echo yes || echo no)"

if [ "$(id -u)" = "0" ]; then
    echo "  SKIP: W1-W10 — running as root (uid 0 reads a mode-000 directory)"
else
    chmod 000 "$P/tests/bad" "$P/src/bad" "$P/fuzz/sub" "$P/benches/sub"

    cy "$P" test
    check "W1 \`cyrius test\` with tests/bad unreadable: rc 1" 1 "$RC"
    check "   …names it" yes "$(has 'cannot list directory: tests/bad')"
    check "   …and never '1 passed, 0 failed'" no "$(has '1 passed, 0 failed')"

    cy "$P" tests tests
    check "W2 \`cyrius tests tests\`: rc 1, tests/bad named" "1 yes" "$RC $(has 'cannot list directory: tests/bad')"

    cy "$P" audit
    check "W3 \`cyrius audit\` with src/bad unreadable: rc non-zero" yes "$([ "$RC" -ne 0 ] && [ "$RC" -ne 124 ] && echo yes || echo no)"
    check "   …names src/bad as a directory it could not list" yes "$(has 'src/bad: cannot list directory')"
    check "   …and never 'ok: format clean'" no "$(has 'ok: format clean')"
    check "   …and never 'ok: lint clean'" no "$(has 'ok: lint clean')"

    cy "$P" fuzz
    check "W4 \`cyrius fuzz\` with fuzz/sub unreadable: rc 1, named" "1 yes" "$RC $(has 'cannot list directory: fuzz/sub')"

    cy "$P" bench benches
    check "W5 \`cyrius bench benches\` with benches/sub unreadable: rc 1, named" "1 yes" "$RC $(has 'cannot list directory: benches/sub')"

    chmod 755 "$P/tests/bad" "$P/src/bad" "$P/fuzz/sub" "$P/benches/sub"

    # ── W6/W7: the lock — an integrity check must not pass over files it cannot see ─────
    L="$T/lockproj"; mkdir -p "$L/lib/nested"
    printf '[package]\nname = "lk"\nversion = "0.1.0"\n' > "$L/cyrius.cyml"
    printf 'fn a(): i64 { return 1; }\n' > "$L/lib/m1.cyr"
    printf 'fn c(): i64 { return 3; }\n' > "$L/lib/nested/m3.cyr"
    chmod 000 "$L/lib/nested"
    cy "$L" deps --lock
    check "W6 \`cyrius deps --lock\` with lib/nested unreadable: rc non-zero" yes "$([ "$RC" -ne 0 ] && echo yes || echo no)"
    check "   …names lib/nested" yes "$(has 'cannot list directory: lib/nested')"
    check "   …and writes no cyrius.lock" no "$([ -e "$L/cyrius.lock" ] && echo yes || echo no)"
    chmod 755 "$L/lib/nested"
    cy "$L" deps --lock
    check "W7 premise: the readable tree locks (rc 0)" 0 "$RC"
    chmod 000 "$L/lib/nested"
    cy "$L" deps --verify
    chmod 755 "$L/lib/nested"
    check "W7 \`cyrius deps --verify\` with lib/nested unreadable: rc 1, named" "1 yes" "$RC $(has 'cannot list directory: lib/nested')"

    # ── W8: cyrius clean ─────────────────────────────────────────────────────────────────
    C="$T/cleanproj"; mkdir -p "$C/build"; : > "$C/build/junk"
    printf '[package]\nname = "cl"\nversion = "0.1.0"\n' > "$C/cyrius.cyml"
    chmod 000 "$C/build"
    cy "$C" clean
    chmod 755 "$C/build"
    check "W8 \`cyrius clean\` with build/ unreadable: rc 1, named (not 'removed 0 files')" "1 yes no" "$RC $(has 'cannot list directory: build') $(has 'removed 0')"

    # ── W9: cyrius_type_audit ────────────────────────────────────────────────────────────
    A="$T/auditproj"; mkdir -p "$A/src" "$A/lib"
    printf 'fn pub_one(x) { return x; }\n' > "$A/src/m.cyr"
    chmod 000 "$A/src"
    RC=0; ( cd "$A" && timeout 60 "$B/cyrius_type_audit" --summary ) > "$T/o" 2>&1 || RC=$?
    chmod 755 "$A/src"
    check "W9 cyrius_type_audit with src/ unreadable: rc 1, named" "1 yes" "$RC $(has 'cannot list directory: src')"

    # ── W10: cyriusly list ───────────────────────────────────────────────────────────────
    H="$T/lhome"; mkdir -p "$H/versions/9.9.9"
    chmod 000 "$H/versions"
    RC=0; ( HOME="$T/hh" CYRIUS_HOME="$H" timeout 60 "$B/cyriusly" list ) > "$T/o" 2>&1 || RC=$?
    chmod 755 "$H/versions"
    check "W10 cyriusly list with versions/ unreadable: rc 1, named, not '(none …)'" "1 yes no" "$RC $(has 'cannot list') $(has '(none')"
fi

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: $NAME — $checks checks"
exit 0
