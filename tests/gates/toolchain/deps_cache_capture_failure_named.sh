#!/bin/sh
# deps_cache_capture_failure_named.sh — 6.6.9 bite 9. A temp dir the CLI cannot write into is
# reported AS THAT — never as a tampered dep cache, a missing sha256sum, or a clean lint — and
# an absolute $TMPDIR routes the CLI around it.
#
# ⛔ THE DEFECT (filed from aethersafha 0.16.27, 2026-09-27; its /tmp is a usrquota tmpfs):
# at quota, every `cyrius build`/`test`/`deps` refused ALL ten deps with
#     error: cached checkout for dep 'bhumi' tag '1.4.5' does not match its source — refusing
#     tampered cache: HEAD is not the tag's commit … or: rm -rf <cache>
# and a bare commit sha on the terminal. `_git_run`'s child opened its stdout capture itself
# and, when that failed (EDQUOT/ENOSPC/no inodes), ran git with the PARENT's stdout: the answer
# went to the terminal, the capture read back empty, `_git_rev` returned 0 — the same value as
# "the tag does not resolve" — and the verifier named a tamper and advised deleting a HEALTHY
# cache. Reproduced with nr_inodes 4/3 (reason 2) and 2 (reason 1: "its .git is missing").
# Same shape, two more sites: `_sha256sum_file` (a full temp dir read as "sha256sum
# missing?"), and `cyrius lint`'s syntax pre-pass, which FAILED OPEN — a file that does not
# parse linted `0 warnings`, rc 0. And `_cbt_tmpbase` returned the literal "/tmp", so TMPDIR
# could not route around any of it.
#
# ⭐ THE FIX: every capture is opened by the PARENT before the fork; a refusal reached while a
# capture could not be written — or while the private temp dir refuses a fresh 4 KB file —
# is reason 10, which names the temp dir and errno, says the cache was NOT judged, and prints
# no restore recipe and no `rm -rf`. The hasher and the lint pre-pass report the temp dir the
# same way. An absolute $TMPDIR is the temp base (trailing slashes dropped); a relative one is
# ignored. The hasher also falls back to `shasum -a 256` (macOS 13 has no sha256sum).
#
# AXES (N = a private tmpfs's nr_inodes, mounted over /tmp in a user+mount namespace — the
# filing's own recipe; the fixture is bind-mounted OUTSIDE /tmp so the mount cannot hide it)
#   0. ANTI-VACUOUS: N=64 resolves the tagged git dep, rc 0.
#   1. N=4, 3, 2 (the filing's two + the widening to reason 1): non-zero, "could NOT be
#      verified", an errno, NO "tampered", NO "rm -rf", no bare sha on the output.
#   2. $TMPDIR routes around it: N=2 on /tmp with TMPDIR at a roomy dir resolves rc 0; a
#      RELATIVE TMPDIR is ignored (the refusal names /tmp).
#   3. The hasher: `deps --verify` / `deps --lock` at N=2 name the hash capture, never
#      "sha256sum missing" / "neither sha256sum nor shasum"; the lock is left as it was.
#   4. `cyrius lint` on a file that does not parse, at N=3 and 2: rc 1, "could not run its
#      syntax pre-pass" (N=64: "does not parse").
#   5. (no namespace needed) TMPDIR is READ: a squeeze of all 16 candidates under
#      "$W/roomy" with TMPDIR="$W/roomy/" fails closed naming "$W/roomy" (the trailing slash
#      dropped); a relative TMPDIR does not become the base.
#   6. The hasher's shasum fallback: with ONLY shasum on PATH, `deps --lock` writes hashes
#      equal to sha256sum's; with neither, the error says so.
#   7. STATIC: `_git_run` and `_sha_run` open the capture BEFORE `sys_fork()` and the child
#      never opens it.
# Axes 0-4 SKIP, named, where unprivileged user namespaces are unavailable; 5-7 always run.
#
# MUTATION LEDGER (measured 6.6.9, each a copy of the tree with ONE edit, CLI rebuilt):
#   a. `_git_cap_judge` returning `r` unchanged      -> axis 1 FAIL ("tampered", rm -rf)
#   b. `_git_run` back to the 6.6.8 shape (no parent pre-open; the child opens its capture
#      and fails open onto our stdout), reason-10 judge KEPT
#                                                    -> axes 1, 7 FAIL ("tampered", rm -rf,
#                                                       a bare sha on the output — the
#                                                       probe alone does not save it)
#   b'. the child re-opening a capture the parent already created
#                                                    -> axis 7 FAIL (static only: the
#                                                       parent's file makes it harmless today)
#   pre-fix tree (the 6.6.9 slot-open commit bd6dad5f) -> axes 1-7 FAIL, axis 0 passes
#   c. `_cbt_tmpbase` back to the literal "/tmp"     -> axes 2, 5 FAIL
#   d. `_sha_finish` without its capture arm (fail 3 read as "could not read it")
#                                                    -> axis 3 FAIL
#   e. the lint pre-pass's empty-capture arm back to `return 0`
#                                                    -> axis 4 FAIL (0 warnings, rc 0)
#   f. no shasum fallback (`_sha_tool = 2` never set) -> axis 6 FAIL
#   g. trailing slashes kept on TMPDIR               -> axis 5 FAIL
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: deps_cache_capture_failure_named: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "FAIL: deps_cache_capture_failure_named: git missing"; exit 1; }
command -v sha256sum > /dev/null 2>&1 || { echo "FAIL: deps_cache_capture_failure_named: sha256sum missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: deps_cache_capture_failure_named: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
ulimit -c 0 2>/dev/null

mkdir -p "$W/bin"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
cp "$CC" "$W/bin/cycc" && chmod +x "$W/bin/cyrius" "$W/bin/cycc" || { echo "FAIL: cannot stage $W/bin"; exit 1; }
# cyrlint beside the CLI (the sibling lookup), so axis 4's rc is the pre-pass's verdict and not
# "tool not found".
"$CC" < programs/cyrlint.cyr > "$W/bin/cyrlint" 2> "$W/lint.err" && [ -s "$W/bin/cyrlint" ] && chmod +x "$W/bin/cyrlint" \
  || { echo "FAIL: programs/cyrlint.cyr does not build:"; tail -3 "$W/lint.err" | sed 's/^/      /'; exit 1; }
H="$W/home"
mkdir -p "$H/versions/6.6.6" && cp -r lib "$H/versions/6.6.6/lib" && printf '6.6.6\n' > "$H/current" \
  || { echo "FAIL: cannot stage the throwaway home"; exit 1; }

# The git dep: a local origin with a tag, resolved ONCE normally so its cache exists.
O="$W/o"
mkdir -p "$O/dist" && printf 'fn foo_val(): i64 { return 7; }\n' > "$O/dist/foo.cyr"
( cd "$O" && git init -q && git add . && git -c user.email=g@g -c user.name=g commit -qm i && git tag 1.0.0 ) \
  || { echo "FAIL: cannot build the origin repo"; exit 1; }
mkdir -p "$W/p"
printf '[package]\nname = "p"\nversion = "0.1.0"\n\n[deps.foo]\ngit = "file://%s"\ntag = "1.0.0"\nmodules = ["dist/foo.cyr"]\n' "$O" > "$W/p/cyrius.cyml"
# A stdlib-only project with a lock, for the hasher axes.
mkdir -p "$W/s"
printf '[package]\nname = "s"\nversion = "0.1.0"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > "$W/s/cyrius.cyml"
# A file that does not parse, for the lint axis.
mkdir -p "$W/l" && printf 'fn main(): i64 { return (; }\n' > "$W/l/bad.cyr"

_cy() { _d=$1; shift; ( cd "$_d" && CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$W/bin/cyrius" "$@" ); }
rc=0; _cy "$W/p" deps > "$W/prime.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: the git-dep fixture does not resolve at all (rc=$rc):"; sed 's/^/      /' "$W/prime.out" | head -4; exit 1; }
# `deps --lock` explicitly: this gate is about captures, not about when a first lock is written
rc=0; { _cy "$W/s" deps && _cy "$W/s" deps --lock; } > "$W/prime2.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ -f "$W/s/cyrius.lock" ] || { echo "FAIL: the stdlib fixture does not resolve+lock (rc=$rc):"; sed 's/^/      /' "$W/prime2.out" | head -4; exit 1; }

# ── the namespace runner ──────────────────────────────────────────────────────────────────
# _ns <N> <outfile> <project> <tmpdir-or-"-"> <verb...>: a private mount of $W at $MP (outside
# /tmp), a tmpfs with N inodes over /tmp, then the CLI from $MP. TMPDIR is UNSET unless given
# ("-"), so the CLI's base is the starved /tmp exactly as in the filing.
MP=""
for d in /mnt /srv /opt; do [ -d "$d" ] && { MP=$d; break; }; done
NS=0
if [ -n "$MP" ] && unshare -r -m sh -c "mount --bind '$W' '$MP' && mount -t tmpfs -o nr_inodes=8 tmpfs /tmp && [ -x '$MP/bin/cyrius' ]" > /dev/null 2>&1; then NS=1; fi
_ns() {
    _n=$1; _o=$2; _pj=$3; _td=$4; shift 4
    unshare -r -m sh -c '
        n=$1; w=$2; mp=$3; pj=$4; td=$5; shift 5
        mount --bind "$w" "$mp" || exit 97
        mount -t tmpfs -o nr_inodes="$n" tmpfs /tmp || exit 98
        cd "$mp/$pj" || exit 96
        unset TMPDIR
        [ "$td" = "-" ] || export TMPDIR="$td"
        CYRIUS_HOME="$mp/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$mp/bin/cyrius" "$@"
    ' _ "$_n" "$W" "$MP" "$_pj" "$_td" "$@" > "$_o" 2>&1
}
_nobad() {  # _nobad <outfile> <axis>: no tamper accusation, no rm -rf, no bare sha
    grep -q 'tampered' "$1" && { fail "$2: a capture failure was reported as a TAMPERED cache:"; grep -m2 'tampered' "$1" | sed 's/^/      /'; }
    grep -q 'rm -rf' "$1" && { fail "$2: the refusal still advises rm -rf on a cache nobody judged"; }
    grep -qE '^[0-9a-f]{40}$|^[0-9a-f]{64}$' "$1" && { fail "$2: a bare sha reached the output — git ran with an UNCAPTURED stdout"; }
    return 0
}

if [ "$NS" = 1 ]; then
    # ── axis 0: ANTI-VACUOUS ──
    rc=0; _ns 64 "$W/a0.out" p - deps || rc=$?
    { [ "$rc" -eq 0 ] && grep -q '1 deps resolved' "$W/a0.out"; } \
      && echo "  ok: axis 0: a roomy private /tmp (64 inodes) resolves the git dep" \
      || { fail "axis 0: the namespace run does not resolve with a ROOMY /tmp (rc=$rc) — every other axis would be vacuous:"; sed 's/^/      /' "$W/a0.out" | head -4; }

    # ── axis 1: the filing's starved runs ──
    x=0
    for n in 4 3 2; do
        rc=0; _ns "$n" "$W/a1_$n.out" p - deps || rc=$?
        [ "$rc" -ne 0 ] || { fail "axis 1: nr_inodes=$n resolved rc 0 — a cache NOBODY judged was vendored"; x=1; }
        grep -q 'could NOT be verified' "$W/a1_$n.out" || { fail "axis 1: nr_inodes=$n does not say the cache could not be verified:"; sed 's/^/      /' "$W/a1_$n.out" | head -4; x=1; }
        grep -q 'errno' "$W/a1_$n.out" || { fail "axis 1: nr_inodes=$n names no errno"; x=1; }
        grep -q 'temp dir: /tmp/cyrius-' "$W/a1_$n.out" || { fail "axis 1: nr_inodes=$n does not name the temp dir"; x=1; }
        c0=$FAIL; _nobad "$W/a1_$n.out" "axis 1 (nr_inodes=$n)"; [ "$FAIL" = "$c0" ] || x=1
    done
    [ "$x" = 0 ] && echo "  ok: axis 1: nr_inodes 4/3/2 each refuse with 'could NOT be verified' + the temp dir + errno — no tamper, no rm -rf, no stray sha"

    # ── axis 2: TMPDIR routes around it; a relative one is ignored ──
    x=0
    mkdir -p "$W/roomy"
    rc=0; _ns 2 "$W/a2a.out" p "$MP/roomy" deps || rc=$?
    { [ "$rc" -eq 0 ] && grep -q '1 deps resolved' "$W/a2a.out"; } \
      || { fail "axis 2: with /tmp starved and TMPDIR at a roomy dir the resolve still failed (rc=$rc) — TMPDIR not honoured:"; sed 's/^/      /' "$W/a2a.out" | head -3; x=1; }
    rc=0; _ns 2 "$W/a2b.out" p "roomy" deps || rc=$?
    { [ "$rc" -ne 0 ] && grep -q 'temp dir: /tmp/cyrius-' "$W/a2b.out"; } \
      || { fail "axis 2: a RELATIVE TMPDIR became the temp base (rc=$rc):"; sed 's/^/      /' "$W/a2b.out" | head -3; x=1; }
    [ "$x" = 0 ] && echo "  ok: axis 2: an absolute TMPDIR routes around a starved /tmp; a relative one is ignored"

    # ── axis 3: the hasher ──
    x=0
    cp "$W/s/cyrius.lock" "$W/a3.lock"
    rc=0; _ns 2 "$W/a3a.out" s - deps --verify || rc=$?
    [ "$rc" -ne 0 ] || { fail "axis 3: deps --verify with no way to hash verified rc 0"; x=1; }
    grep -q 'could not write the hash capture under /tmp/cyrius-' "$W/a3a.out" || { fail "axis 3: --verify does not name the hash capture:"; sed 's/^/      /' "$W/a3a.out" | head -2; x=1; }
    rc=0; _ns 2 "$W/a3b.out" s - deps --lock || rc=$?
    [ "$rc" -ne 0 ] || { fail "axis 3: deps --lock with no way to hash exited 0"; x=1; }
    grep -q 'could not write the hash capture' "$W/a3b.out" || { fail "axis 3: --lock does not name the hash capture:"; sed 's/^/      /' "$W/a3b.out" | head -2; x=1; }
    cmp -s "$W/s/cyrius.lock" "$W/a3.lock" || { fail "axis 3: a lock that could not hash anything REWROTE cyrius.lock"; x=1; }
    grep -qE 'sha256sum missing|neither sha256sum nor shasum' "$W/a3a.out" "$W/a3b.out" && { fail "axis 3: a full temp dir was blamed on a missing hasher"; x=1; }
    [ "$x" = 0 ] && echo "  ok: axis 3: --verify and --lock name the hash capture (not the hasher), and the lock is left as it was"

    # ── axis 4: lint's syntax pre-pass ──
    x=0
    printf 'fn main(): i64 { return 0; }\n' > "$W/l/good.cyr"
    rc=0; _ns 64 "$W/a4g.out" l - lint good.cyr || rc=$?
    [ "$rc" -eq 0 ] || { fail "axis 4 (anti-vacuous): a file that parses does not lint rc 0 in the namespace (rc=$rc):"; sed 's/^/      /' "$W/a4g.out" | head -3; x=1; }
    rc=0; _ns 64 "$W/a4a.out" l - lint bad.cyr || rc=$?
    { [ "$rc" -eq 1 ] && grep -q 'does not parse' "$W/a4a.out"; } \
      || { fail "axis 4 (anti-vacuous): with a roomy /tmp the pre-pass did not report the parse error (rc=$rc):"; sed 's/^/      /' "$W/a4a.out" | head -3; x=1; }
    for n in 3 2; do
        rc=0; _ns "$n" "$W/a4_$n.out" l - lint bad.cyr || rc=$?
        [ "$rc" -ne 0 ] || { fail "axis 4: nr_inodes=$n — a file that does not parse linted rc 0:"; sed 's/^/      /' "$W/a4_$n.out" | tail -2; x=1; }
        grep -q 'could not run its syntax pre-pass' "$W/a4_$n.out" || { fail "axis 4: nr_inodes=$n does not say the pre-pass could not run:"; sed 's/^/      /' "$W/a4_$n.out" | head -3; x=1; }
    done
    [ "$x" = 0 ] && echo "  ok: axis 4: with /tmp starved (3, 2 inodes) lint refuses by name instead of passing a file that does not parse"
else
    echo "  SKIP axes 0-4 — unprivileged user+mount namespaces (or a bind target outside /tmp) are unavailable; the starved-/tmp runs need them"
fi

# ── axis 5: TMPDIR is read, trailing slashes dropped, a relative value ignored ──────────
x=0
mkdir -p "$W/roomy"
( cd "$W/s" && TMPDIR="$W/roomy/" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 sh -c '
    for s in "" -1 -2 -3 -4 -5 -6 -7 -8 -9 -10 -11 -12 -13 -14 -15; do mkdir -p "$0/cyrius-$$$s" || exit 90; done
    exec "$1" deps --lock' "$W/roomy" "$W/bin/cyrius" ) > "$W/a5a.out" 2>&1 || true
grep -q "cannot create a private temp directory under $W/roomy (fail-closed)" "$W/a5a.out" \
  || { fail "axis 5: with TMPDIR=\"$W/roomy/\" and its 16 candidates taken, the CLI did not fail closed naming $W/roomy (TMPDIR not read, or its trailing slash kept):"; sed 's/^/      /' "$W/a5a.out" | head -3; x=1; }
rm -rf "$W/roomy"/cyrius-*
rc=0; ( cd "$W/s" && TMPDIR="relative/dir" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$W/bin/cyrius" deps --lock ) > "$W/a5b.out" 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && ! grep -q 'relative/dir' "$W/a5b.out"; } \
  || { fail "axis 5: a RELATIVE TMPDIR was used as the temp base (rc=$rc):"; sed 's/^/      /' "$W/a5b.out" | head -3; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 5: an absolute TMPDIR is the temp base (trailing slash dropped); a relative one is ignored"

# ── axis 6: the shasum fallback, and the no-hasher message ──────────────────────────────
x=0
SHA=$(command -v shasum 2>/dev/null || true)
[ -z "$SHA" ] && [ -x /usr/bin/core_perl/shasum ] && SHA=/usr/bin/core_perl/shasum
if [ -n "$SHA" ]; then
    mkdir -p "$W/onlyshasum" && ln -sf "$SHA" "$W/onlyshasum/shasum"
    rm -f "$W/s/cyrius.lock"
    rc=0; ( cd "$W/s" && PATH="$W/onlyshasum" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$W/bin/cyrius" deps --lock ) > "$W/a6a.out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || { fail "axis 6: with only shasum on PATH, deps --lock failed (rc=$rc):"; sed 's/^/      /' "$W/a6a.out" | head -3; x=1; }
    nl=$(grep -c '^[0-9a-f]\{64\}  ' "$W/s/cyrius.lock" 2>/dev/null); nl=${nl:-0}
    [ "$nl" -ge 2 ] || { fail "axis 6: the shasum-built lock has $nl hash lines"; x=1; }
    grep '^[0-9a-f]\{64\}  ' "$W/s/cyrius.lock" 2>/dev/null | while read -r h p; do
        real=$( cd "$W/s" && sha256sum "$p" | cut -d' ' -f1 )
        [ "$real" = "$h" ] || echo "$p"
    done > "$W/a6.bad"
    [ -s "$W/a6.bad" ] && { fail "axis 6: shasum-built hashes differ from sha256sum's for: $(tr '\n' ' ' < "$W/a6.bad")"; x=1; }
else
    echo "  note: axis 6: no shasum on this host — the fallback half is exercised on macOS (ach) only"
fi
mkdir -p "$W/nohash"
rc=0; ( cd "$W/s" && PATH="$W/nohash" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$W/bin/cyrius" deps --verify ) > "$W/a6b.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'neither sha256sum nor shasum is on PATH' "$W/a6b.out"; } \
  || { fail "axis 6: with no hasher on PATH, --verify does not say so (rc=$rc):"; sed 's/^/      /' "$W/a6b.out" | head -2; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 6: shasum stands in for a missing sha256sum (same hashes); with neither, the error says so"

# ── axis 7: STATIC — the capture is opened by the parent ────────────────────────────────
_fn_body() { awk -v want="$2" '$0 ~ "^fn " want "\\(" { inb = 1 } inb && /^}/ { print; inb = 0 } inb { print }' "$1"; }
x=0
for f in _git_run _sha_run; do
    _fn_body cbt/deps.cyr "$f" > "$W/$f.body"
    [ -s "$W/$f.body" ] || { fail "axis 7: $f not found in cbt/deps.cyr"; x=1; continue; }
    ol=$(grep -n 'cfd = sys_open(' "$W/$f.body" | head -1 | cut -d: -f1)
    fl=$(grep -n 'sys_fork()' "$W/$f.body" | head -1 | cut -d: -f1)
    { [ -n "$ol" ] && [ -n "$fl" ] && [ "$ol" -lt "$fl" ]; } || { fail "axis 7: $f does not open its capture before sys_fork() (open line ${ol:-none}, fork line ${fl:-none})"; x=1; }
    n=$(grep -cE 'sys_open\((outf|tmpf),' "$W/$f.body"); n=${n:-0}
    [ "$n" -le 1 ] || { fail "axis 7: $f opens its capture $n times — the child opens it again"; x=1; }
done
[ "$x" = 0 ] && echo "  ok: axis 7: _git_run and _sha_run create their capture in the parent, before the fork, and only there"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: deps_cache_capture_failure_named (a temp dir the CLI cannot write is named as that — no tamper, no missing-hasher, no clean lint — and an absolute TMPDIR routes around it)"
