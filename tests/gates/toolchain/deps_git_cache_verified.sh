#!/bin/sh
# deps_git_cache_verified.sh — the CVE-21 cached-checkout check (cbt/deps.cyr) refuses a
# tampered dep cache in every shape we can build, accepts an untouched one whatever its
# metadata says, and NEVER writes inside a cached checkout. (The exec-bit probe writes ONE
# file BESIDE one, in `<home>/deps/<name>/`, and unlinks it — it has to be on the cache's own
# filesystem to answer its question. Axes B13/B13b drive that path.)
#
# v6.6.5 (CVE-43). Filed as a FALSE REFUSAL (mabda 4.1.3): `git diff-index --quiet HEAD`
# judges the working tree from the cache's own index stat data and never refreshes it, so
# a `touch` / `cp -a` / a uid-mapped-namespace `git status` made an UNTOUCHED checkout
# read as "tampered" — for every project on the box, until someone refreshed the index or
# deleted the clone (which needs the network). The premise-check found the same check
# ACCEPTING real tampering in seven shapes, so this gate is mostly about the accept half.
#
# ⛔ NOTHING HERE MAY WRITE THE SHARED CACHE. scripts/check.sh aliases the LIVE
# ~/.cyrius/deps into its staged home, so both remedies the filing proposed (refresh the
# real index / `git diff --quiet HEAD`, which writes it opportunistically) would corrupt
# the maintainer's cache while this gate ran. Every axis snapshots <cache>/.git
# (`find -printf '%p %T@ %s'`, a FILESYSTEM fact, not a git query) immediately before the
# resolve under test and compares it after.
#
# ⚠ HOSTS. This needs git, a POSIX sh (no bashisms: `$'\r'` is spelled `$CR`) and either
# `sha256sum` or `shasum -a 256`; `python3` (R17/R17b/R20) and `unshare -r` (B7) are
# optional and SKIP by name when absent. `find -printf` is optional too — without it the
# .git snapshot falls back to path-list + content digest, which still catches a write but
# not a pure mtime touch (measured: mutant M2, which writes the shared index, reds 33 axes
# with the GNU snapshot and 21 with the portable one). CYRIUS_GATE_POSIX_SNAP=1 forces the
# portable form so the fallback is exercised on a GNU host; CYRIUS_GATE_CLI=<built cyrius>
# supplies the binary where build/cycc is a foreign ELF (ecb/ach/cass/pi).
#
# ⛔ EXPECTED VALUES COME FROM THE ORIGIN, NEVER FROM THE RESOLVER. EXPECT is the sha256
# of `git -C <origin> show 1.0.0:dist/foo.cyr`. A gate that asked the cache, or diffed the
# resolver against itself, would share the defect and read GREEN (v6.6.2's lesson).
#
# ⛔ EVERY POST-MUTATION RESOLVE RUNS UNDER GIT_ALLOW_PROTOCOL=none. Without it a verdict
# could come from a silent re-clone that repaired the mutation, not from the check.
#
# Axes: B1-B16 benign (rc 0, module bytes == EXPECT), R1-R30 refusals (rc != 0, the named
# reason, the cache path printed, module bytes, cyrius.lock and the CLI's temp dir
# untouched), O1 recovery
# (every refusal is reversible OFFLINE — which also proves each refusal was caused by its
# own mutation and not by a broken fixture; for the reason-7 axes the reversal is removing
# the SETTING, which a reset/clean does not do), C1 clone status, U1/U2 untagged deps.
# 65 in total; the count is asserted, not floored (see the end).
#
# ⚠ WHAT THIS GATE CANNOT PROVE, because nothing offline can: that the objects came from the
# declared remote. Everything the check reads lives inside the cache, so a local tamper
# commit with `git tag -f` moved onto it is indistinguishable from the real tag (measured:
# exit 0). R11 is the same shape WITHOUT the tag moved, and cyrius.lock's commit pin —
# trust-on-first-use — is what holds the real bound on every later resolve.
#
# Mutation ledger — MEASURED, one buildable edit to cbt/deps.cyr at a time, the gate re-run
# against the mutant CLI via CYRIUS_GATE_CLI. The red list is what the run PRINTED, not what
# was predicted. Re-measured in full at 6.6.5 review round 2 (M1-M19 shifted: the new axes
# catch several of the old mutants too):
#   M1  restore the 6.6.4 `diff-index --quiet HEAD` body
#       -> B2 B3 B4 B7 B8 B13 R2 R3 R4 R5 R6 R7 R8 R11 R15 R15b R16 R16b R17 R17b R17c R20
#          R21 R22 R22b R23 R24 R25 R26 R27 R27b O1
#   M2  the filing's proposal A (refresh the REAL index, then diff-index)
#       -> B1 B2 B3 B4 B7 B8 B9 B13 R1 R2 R3 R4-R11 R14 R15 R15b R16 R16b R17 R17b R17c R20
#          R21 R22 R22b R23 R24 R25 R26 R27 R27b R29 O1 U1
#          (every refusal axis also reds on the SNAPSHOT assertion: it writes the shared index)
#   M3  the filing's proposal B (`git diff --quiet HEAD`)
#       -> B2 B3 B4 B7 B8 B13 R2-R8 R11 R14 R15 R15b R16 R16b R17 R17b R17c R20 R21 R22 R22b
#          R23 R23b R24 R25 R26 R27 R27b R29 O1
#   M4  drop GIT_INDEX_FILE=<throwaway> (use the cache's own index)
#       -> B1-B9 R1-R10 R14 R15 R16 U1
#   M5  drop the GIT_* scrub from the CLONE                   -> B10
#   M6  drop the GIT_* scrub from the VERIFY                  -> B8
#   M7  drop GIT_CEILING_DIRECTORIES                          -> R19
#   M7b M7 + drop the .git real-directory check               -> R12 R18 R19
#   M8  restore the silent `_head == 0` skip                  -> R12 R13 R18 R19
#   M9  drop `ls-files -o`                                    -> R4 R5 R6
#   M10 drop the populated-gitlink step                       -> R16 R16b
#   M11 drop fsck                                             -> R17 R17b R17c R20
#   M11b fsck --connectivity-only instead of a FULL fsck      -> R20
#   M12 drop --no-replace-objects                             -> R14
#   M13 drop core.fsmonitor=false                             -> R15b
#   M14 never force core.fileMode=true (trust the cache)      -> R3
#   M15 drop the HEAD == refs/tags/<tag> step                 -> R11 O1
#   M16 drop the clone exit-status check                      -> C1
#   M17 skip verification for UNTAGGED deps (the 6.6.4 shape) -> U1
#   M18 make the verify return 0 unconditionally              -> every R axis except R12 R13
#       R18 R19 R28 (refused before the verify is reached), plus B13, O1 and U1
#   M19 drop the `.git` real-directory check                  -> R18
#   M20 drop GIT_WORK_TREE=<cache>                            -> NOTHING (see below)
#   M20b M20 + allow extensions.worktreeConfig                -> R29
#   M21 drop the config-hazard scan entirely
#       -> R21 R22 R22b R23 R23b R25 R26 R27 R27b
#   M21b scan for `filter.` only, and drop the attributes-file check (the obvious first cut)
#       -> R21 R25 R26 R27 R27b
#   M22 drop the remote.origin.url comparison                 -> R24 O1
#   M23 drop the fsck message-id policy                       -> B12
#   M24 force core.fileMode=true unconditionally (6.6.5 rc1)  -> B13
#   M25 drop `_git_err_clear()` on the pin-mismatch path      -> R28
#   M26 stop quoting git's stderr for reason 3                -> R17c
# Review round 2 (the axes above could not see any of these — they resolve ONE literal url
# spelling from ONE origin that carries no .gitattributes):
#   M27 compare remote.origin.url EXACTLY (the 6.6.5 rc1 body)  -> B15
#   M28 drop the raw-byte check                                 -> R30
#   M29 unprobeable exec bit answers "not storable" (rc1 body)  -> B13b
#   M30 drop `_git_err_clear()` on the CORRUPT-pin branch       -> R28c
#   M31 the conversion always "explains" the difference         -> R30
#   M32 the conversion never explains it                        -> B9 R30b (+ FLOOR: two
#       setups fail, which is the harness-died-early assertion doing its job)
#   (no mutant) the origin also tracks `odd names/a file.cyr`, `ünïcode-ファイル.cyr` and
#       `-dashname.cyr`, so every axis carries them through the raw-byte pass's
#       `hash-object --stdin-paths` list. No buildable mutant reds that on its own — the
#       implementation it guards against (quoting or word-splitting the path list) is a
#       rewrite, not an edit — but a tamper of each shape was measured refused, and
#       restoring each resolves again.
#   M34 look the COMMIT PIN up by an exact url (the same suffix bug one fn over) -> R28d
#   M33 drop `_git_err_clear()` at the end of _git_cache_refuse  -> R1-R11 R14-R17 R20-R27
#       R29 R30 R30b (26 axes: every refusal now also asserts the CLI's private temp dir is
#       left as it was found, which is what R28's delta check only did for the pin branches)
# ⚠ FOUR axes exist BECAUSE a ledger run could not prove the check they cover. M7 and M11b
# reddened NOTHING against B1-B18: R19 (a gutted-but-real `.git` inside a git-repo home —
# git's discovery keeps CLIMBING past an invalid `.git`) is what makes the ceiling
# load-bearing on its own; R20 (the R17 forgery with the cache index removed, a state axis B4
# proves is benign) is what makes the fsck a FULL one. `--connectivity-only` exits 0 on R20 —
# it caught R17 only through the cache index's cache-tree, an accident of that fixture. The
# premise-check's "connectivity-only catches it" is corrected here. R27 (`.git/info/attributes`
# ALONE) exists because R23/R25 also carry a config key and refuse on that instead, and R29
# (core.worktree hidden in `.git/config.worktree`) because a `--local` config scan cannot see
# that file at all.
# ⚠ M20 reddens NOTHING and GIT_WORK_TREE stays anyway. Every work-tree redirect we could
# build is ALSO refused by the config scan, so the two overlap completely today — M20b (drop
# both) shows they cover the same hole. It is kept as the layer that does not depend on
# having enumerated the right config key, which is exactly the assumption the 6.6.5 first cut
# got wrong. Do not "simplify" it away on the strength of a green ledger line.
# ⚠ R2 likewise proved nothing in its first form: `touch -t` rounds to the second and git's
# racily-clean rule re-hashes an entry whose mtime is not older than the index's, so the 6.6.4
# check caught it too. See the axis for the three things that make it a real bypass.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
OS=$(uname -s 2>/dev/null || echo unknown)
command -v git >/dev/null 2>&1 || { echo "SKIP: deps_git_cache_verified: git not found"; exit 0; }
HAVE_PY=1; command -v python3 >/dev/null 2>&1 || HAVE_PY=0
# `sha256sum` is GNU, `shasum -a 256` is what macOS/BSD ship — same digest. A gate that
# skipped wholesale on either spelling could never run on ecb/ach, which is exactly where
# the CYRIUS_GATE_CLI route is meant to take it.
if command -v sha256sum >/dev/null 2>&1; then SHACMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then SHACMD="shasum -a 256"
else echo "SKIP: deps_git_cache_verified: no sha256sum/shasum"; exit 0; fi
# `find -printf` is GNU too. With it, the .git snapshot is path+mtime+size, a FILESYSTEM
# fact; without it, it is path-list + content digest, which still catches every WRITE (the
# thing the ⛔ rule above is about) but not a pure mtime touch inside .git. Set
# CYRIUS_GATE_POSIX_SNAP=1 to exercise the portable form on a GNU host.
FINDP=1; find . -maxdepth 0 -printf '' >/dev/null 2>&1 || FINDP=0
[ -n "${CYRIUS_GATE_POSIX_SNAP:-}" ] && FINDP=0

W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: deps_git_cache_verified: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT
pass=0; fail=0; skipped=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }
skip() { echo "  SKIP $1"; skipped=$((skipped+1)); }
V=$(tr -d '[:space:]' < "$ROOT/VERSION")

# GNU/BSD `sed -i` disagree about the backup suffix; every in-place edit here goes through
# this so the gate is not Linux-only for that reason alone.
sedi() { e=$1; shift; sed "$e" "$1" > "$1.sedi" && mv -f "$1.sedi" "$1"; }
CR=$(printf '\r')   # never $'\r': this gate runs under /bin/sh, which may be dash

# ── the CLI under test ───────────────────────────────────────────────────────────────────
# CYRIUS_GATE_CLI=<path> supplies a pre-built `cyrius` so the gate can run on a host where
# build/cycc is a foreign binary (ecb/ach/cass/pi: it is a Linux ELF). Without it the CLI is
# built from source here — and a build failure is a LOUD FAIL on Linux, where it is expected
# to work, and a SKIP elsewhere, where build/cycc cannot execute at all.
nohost() {   # $1 = why
    if [ "$OS" = Linux ]; then echo "FAIL: deps_git_cache_verified: $1"; exit 1; fi
    echo "SKIP: deps_git_cache_verified: $1 (pass CYRIUS_GATE_CLI=<built cyrius> to run here)"
    exit 0
}
if [ -n "${CYRIUS_GATE_CLI:-}" ]; then
    [ -x "$CYRIUS_GATE_CLI" ] || { echo "FAIL: deps_git_cache_verified: CYRIUS_GATE_CLI=$CYRIUS_GATE_CLI is not executable"; exit 1; }
    cp "$CYRIUS_GATE_CLI" "$W/cyrius"
else
    [ -x "$CC" ] || nohost "build/cycc missing"
    ( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null ) \
        || nohost "could not build cbt/cyrius.cyr"
    [ -s "$W/cyrius" ] || nohost "cbt/cyrius.cyr built an EMPTY binary"
fi
chmod +x "$W/cyrius"
"$W/cyrius" --version >/dev/null 2>&1 || nohost "the CLI under test does not execute here"
H="$W/home"; mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib" "$H/deps"
cp -r "$ROOT/lib/." "$H/versions/$V/lib/"
cp "$W/cyrius" "$H/versions/$V/bin/cyrius"; cp "$CC" "$H/versions/$V/bin/cycc" 2>/dev/null || true
chmod +x "$H/versions/$V/bin/"*
printf '%s\n' "$V" > "$H/current"; ln -s "$H/versions/$V/bin" "$H/bin"; ln -s "$H/versions/$V/lib" "$H/lib"
CY="$H/versions/$V/bin/cyrius"
export CYRIUS_HOME="$H"
# hermetic git: no /etc/gitconfig, no ~/.gitconfig — the user's own settings (autocrlf,
# safe.directory, a global fsmonitor) must not decide any axis.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# ── the origin fixture ───────────────────────────────────────────────────────────────────
# dist/foo.cyr is the module. The rest exists so a naive fix reddens a BENIGN axis:
# tools/run.sh is +x (a mode-only fix over-refuses), lib/foolink.cyr is a tracked symlink,
# .gitignore hides build/, and vendor/sub is a shravan-shaped gitlink with no .gitmodules
# — `git add -A` + write-tree, the obvious first cut, falsely refuses every cache holding
# one, and two real ones do (shravan 2.8.0/2.8.1).
O="$W/origin"; SUB="$W/sub"
mkdir -p "$SUB"
( cd "$SUB" && git init -q . && echo sub > s.txt && git add -A && git commit -qm sub )
SUBSHA=$(git -C "$SUB" rev-parse HEAD)
mkdir -p "$O/dist" "$O/lib" "$O/tools"
printf 'fn foo_answer(): i64 { return 42; }\n' > "$O/dist/foo.cyr"
printf 'fn foo_bar(): i64 { return 1; }\n' > "$O/lib/bar.cyr"
printf '#!/bin/sh\necho run\n' > "$O/tools/run.sh"; chmod +x "$O/tools/run.sh"
printf 'build/\n' > "$O/.gitignore"
# Odd tracked path names, in the origin every axis uses: the raw-byte pass feeds tracked paths
# to `git hash-object --stdin-paths`, which is LF-separated, so a path with a space, a
# non-ASCII name or a leading dash is exactly where a quoting/word-splitting implementation
# would false-refuse EVERY dep carrying one. Measured through the plumbing first, then wired
# into the fixture rather than into one axis, so every axis carries them.
mkdir -p "$O/odd names"
printf 'fn foo_space(): i64 { return 2; }\n' > "$O/odd names/a file.cyr"
printf 'fn foo_uni(): i64 { return 3; }\n' > "$O/ünïcode-ファイル.cyr"
printf 'fn foo_dash(): i64 { return 4; }\n' > "$O/-dashname.cyr"
( cd "$O/lib" && ln -s bar.cyr foolink.cyr )
( cd "$O" && git init -q . && git add -A && git update-index --add --cacheinfo "160000,$SUBSHA,vendor/sub" \
  && git commit -qm v1 && git tag 1.0.0 )
EXPECT=$(git -C "$O" show 1.0.0:dist/foo.cyr | $SHACMD | cut -d' ' -f1)
TAGC=$(git -C "$O" rev-parse '1.0.0^{commit}')
[ -n "$EXPECT" ] && [ "${#EXPECT}" = 64 ] || { echo "FAIL: deps_git_cache_verified: EXPECT not computed from the origin"; exit 1; }
[ -n "$TAGC" ] || { echo "FAIL: deps_git_cache_verified: origin tag has no commit"; exit 1; }

C="$H/deps/foo/1.0.0"          # the shared cache the resolver uses for the tagged dep
CU="$H/deps/foo/main"          # ...and for the untagged one
REC_FAIL=""; REC_RUN=0

sha_of()  { [ -f "$1" ] && $SHACMD "$1" | cut -d' ' -f1 || echo MISSING; }
snap()    {
    [ -d "$1/.git" ] || { echo NOGIT; return; }
    if [ "$FINDP" = 1 ]; then
        ( cd "$1" && find .git -printf '%p %T@ %s\n' 2>/dev/null | LC_ALL=C sort | $SHACMD | cut -d' ' -f1 )
    else
        ( cd "$1" && { find .git -print | LC_ALL=C sort
                       find .git -type f -print | LC_ALL=C sort | xargs $SHACMD; } 2>/dev/null \
          | $SHACMD | cut -d' ' -f1 )
    fi
}
freshcache() { chmod -R u+w "$H/deps" 2>/dev/null || true; rm -rf "$H/deps"; mkdir -p "$H/deps"; }

mkconsumer() {   # $1=dir  $2=extra modules (",\"dist/baz.cyr\"" or empty)  $3=tag? (1/0)
    mkdir -p "$1/src"
    {   printf '[package]\nname = "cachep"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n' "$V"
        printf '[build]\nentry = "src/main.cyr"\noutput = "build/main"\n\n'
        printf '[deps.foo]\ngit = "file://%s"\n' "$O"
        [ "$3" = 1 ] && printf 'tag = "1.0.0"\n'
        printf 'modules = ["dist/foo.cyr"%s]\n' "$2"
    } > "$1/cyrius.cyml"
    printf 'fn main(): i64 { return 0; }\n' > "$1/src/main.cyr"
}

# first resolve: populates the cache. The ONLY place a clone is allowed.
first() {   # $1=proj  [$2=1 → untagged]
    rc=0
    if ( cd "$1" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/first.out" 2>&1 ); then rc=0; else rc=$?; fi
    [ "$rc" -eq 0 ] || { bad "$AX setup: first resolve rc=$rc: $(tail -2 "$W/first.out")"; return 1; }
    [ "$(sha_of "$1/lib/foo.cyr")" = "$EXPECT" ] || { bad "$AX setup: vendored module != origin bytes"; return 1; }
    if [ "${2:-0}" = 0 ]; then
        grep -q "^commit	$TAGC	foo	" "$1/cyrius.lock" 2>/dev/null \
            || { bad "$AX setup: lock carries no commit pin for the tag's commit"; return 1; }
    fi
    return 0
}

# the resolve UNDER TEST: never allowed to reach a remote.
rerun() {   # $1=proj $2=out   (extra env in $ENVX)
    rc=0
    if ( cd "$1" && eval "${ENVX:-}" GIT_ALLOW_PROTOCOL=none PIDFILE="$W/last.pid" "$W/pidwrap" "$CY" deps > "$2" 2>&1 ); then rc=0; else rc=$?; fi
    echo "$rc"
}

benign() {  # $1=axis $2=desc $3=proj $4=cachedir $5=expected sha
    s0=$(snap "$4")
    r=$(ENVX="" rerun "$3" "$W/$1.out")
    s1=$(snap "$4")
    if [ "$r" -eq 0 ] && [ "$(sha_of "$3/lib/foo.cyr")" = "$5" ] && [ "$s0" = "$s1" ]; then
        ok "$1 $2"
    else
        bad "$1 $2 (rc=$r, module $(sha_of "$3/lib/foo.cyr") want $5, .git snapshot $s0 -> $s1): $(grep -m1 -i 'error' "$W/$1.out" || true)"
    fi
}

# Every refusal also has to leave the CLI's private temp dir as it found it: the throwaway
# index, its lock, the stdout capture, the stderr capture and the raw-path list are all
# created per resolve, and a refusal is the path that returns early past their cleanup.
# ⛔ v6.6.6: counted over THIS gate's last `cyrius deps` process only. The count used to glob
# every /tmp/cyrius-* dir, so ANOTHER check.sh resolving deps on the same box (concurrent
# worktrees, a CI matrix on one runner) moved it. `rerun` records the CLI's pid through
# $W/pidwrap (the `exec` keeps it); the CLI names its temp /tmp/cyrius-<pid>[-t<nonce>…], and a
# missing pidfile counts 0, so callers clear it before the "before" sample. CHANGELOG [6.6.6]
printf '#!/bin/sh\necho $$ > "$PIDFILE"\nexec "$@"\n' > "$W/pidwrap" && chmod +x "$W/pidwrap" \
  || { echo "FAIL: deps_git_cache_verified: cannot write $W/pidwrap"; exit 1; }
tmpn() {
    _p=$(cat "$W/last.pid" 2>/dev/null || true)
    [ -n "$_p" ] || { echo 0; return; }
    ls /tmp/cyrius-"$_p"/git_err /tmp/cyrius-"$_p"/dep_verify_* /tmp/cyrius-"$_p"/git_rev_out \
       /tmp/cyrius-"$_p"-*/git_err /tmp/cyrius-"$_p"-*/dep_verify_* /tmp/cyrius-"$_p"-*/git_rev_out 2>/dev/null | wc -l
}

refused() { # $1=axis $2=desc $3=proj $4=reason-substring $5=cachedir
    s0=$(snap "$5"); rm -f "$W/last.pid"; t0=$(tmpn)
    [ -f "$3/cyrius.lock" ] && cp "$3/cyrius.lock" "$W/$1.lock" || rm -f "$W/$1.lock"
    r=$(ENVX="${ENVX:-}" rerun "$3" "$W/$1.out")
    s1=$(snap "$5"); t1=$(tmpn)
    m=$(sha_of "$3/lib/foo.cyr")
    lk=1; if [ -f "$W/$1.lock" ]; then cmp -s "$3/cyrius.lock" "$W/$1.lock" || lk=0; fi
    if [ "$r" -ne 0 ] && grep -q "$4" "$W/$1.out" && grep -q "refusing tampered cache" "$W/$1.out" \
       && grep -q "cache: $5" "$W/$1.out" && [ "$m" = "$EXPECT" ] && [ "$s0" = "$s1" ] && [ "$lk" = 1 ] \
       && [ "$t1" -le "$t0" ]; then
        ok "$1 $2"
    else
        bad "$1 $2 (rc=$r, module=$m, lock-intact=$lk, .git $s0 -> $s1, temp delta $((t1 - t0))): $(grep -m1 -i 'error' "$W/$1.out" || echo 'NO ERROR LINE')"
    fi
}

# O1: the refusal message's own offline recipe must undo the mutation, with no network.
# Also the anti-vacuity check: if a fixture were simply broken, recovery would not resolve.
recover() {  # $1=axis $2=proj [$3=extra pre-command]
    REC_RUN=$((REC_RUN+1))
    rm -f "$2/lib/foo.cyr"        # force a real re-vendor, so EXPECT cannot pass vacuously
    [ -n "${3:-}" ] && eval "$3" >/dev/null 2>&1
    rm -f "$C/.git/index"
    GIT_ALLOW_PROTOCOL=none git --no-replace-objects -C "$C" -c core.fsmonitor=false \
        -c core.hooksPath=/dev/null reset -q --hard refs/tags/1.0.0 >/dev/null 2>&1 || true
    GIT_ALLOW_PROTOCOL=none git -C "$C" clean -qffdx >/dev/null 2>&1 || true
    r=$(ENVX="" rerun "$2" "$W/$1.rec")
    if [ "$r" -eq 0 ] && [ "$(sha_of "$2/lib/foo.cyr")" = "$EXPECT" ]; then :; else REC_FAIL="$REC_FAIL $1"; fi
}

# ══ BENIGN ═══════════════════════════════════════════════════════════════════════════════

AX=B1; freshcache; P="$W/b1"; mkconsumer "$P" "" 1
if first "$P"; then benign B1 "fresh clone (gitlink, symlink, +x file, .gitignore): re-resolve is clean" "$P" "$C" "$EXPECT"; fi

AX=B2; freshcache; P="$W/b2"; mkconsumer "$P" "" 1
if first "$P"; then
    touch -d '2001-01-01 00:00:00' "$C/dist/foo.cyr"
    benign B2 "FILED REPRO: touch (metadata only, bytes identical) is accepted" "$P" "$C" "$EXPECT"
fi

AX=B3; freshcache; P="$W/b3"; mkconsumer "$P" "" 1
if first "$P"; then
    cp -a "$C" "$W/b3copy"; chmod -R u+w "$C"; rm -rf "$C"; cp -a "$W/b3copy" "$C"
    benign B3 "FILED REPRO: cp -a of the checkout (new inodes/ctimes) is accepted" "$P" "$C" "$EXPECT"
fi

AX=B4; freshcache; P="$W/b4"; mkconsumer "$P" "" 1
if first "$P"; then
    rm -f "$C/.git/index"
    benign B4 ".git/index deleted: accepted (the verify builds its own)" "$P" "$C" "$EXPECT"
fi

AX=B5; freshcache; P="$W/b5"; mkconsumer "$P" "" 1
if first "$P"; then
    : > "$C/.git/index.lock"
    benign B5 "stale .git/index.lock present: accepted (nothing locks the shared index)" "$P" "$C" "$EXPECT"
    rm -f "$C/.git/index.lock"
fi

AX=B6; freshcache; P="$W/b6"; mkconsumer "$P" "" 1
if first "$P"; then
    chmod -R a-w "$C/.git"
    benign B6 "read-only .git: accepted (the verify writes nothing there)" "$P" "$C" "$EXPECT"
    chmod -R u+w "$C/.git"
fi

AX=B7; freshcache; P="$W/b7"; mkconsumer "$P" "" 1
if first "$P"; then
    if unshare -r true >/dev/null 2>&1; then
        unshare -r git -C "$C" status >/dev/null 2>&1 || true
        benign B7 "uid-mapped namespace rewrote the cache index (st_uid=0): accepted" "$P" "$C" "$EXPECT"
    else
        # skip(), never a bare echo: an uncounted skip breaks the EXACT-count assertion at
        # the end, and this is the one axis that cannot run on macOS/Windows/a container
        # with unprivileged userns off — i.e. on every host the CYRIUS_GATE_CLI route was
        # added for. Measured with a failing `unshare` first in PATH: the bare echo came up
        # one axis short of the asserted total and the whole gate FAILED; through skip() the
        # same run reports one SKIPPED and exits 0.
        skip "B7: unshare -r unavailable — the uid-mapped-namespace row is not exercised"
    fi
fi

AX=B8; freshcache; P="$W/b8"; mkconsumer "$P" "" 1
if first "$P"; then
    mkdir -p "$W/foreign" && ( cd "$W/foreign" && git init -q . && echo x > x && git add -A && git commit -qm f )
    b8=1
    for leak in "GIT_DIR=$W/foreign/.git" "GIT_WORK_TREE=$W/foreign" "GIT_INDEX_FILE=$W/foreign/.git/index" "GIT_OBJECT_DIRECTORY=$W/foreign/.git/objects"; do
        s0=$(snap "$C"); fsha=$(sha_of "$W/foreign/.git/index")
        r=$(ENVX="$leak" rerun "$P" "$W/b8.out")
        [ "$r" -eq 0 ] || { b8=0; echo "    B8 leak '$leak' rc=$r: $(grep -m1 -i error "$W/b8.out" || true)"; }
        [ "$s0" = "$(snap "$C")" ] || { b8=0; echo "    B8 leak '$leak' wrote the cache .git"; }
        [ "$fsha" = "$(sha_of "$W/foreign/.git/index")" ] || { b8=0; echo "    B8 leak '$leak' rewrote the FOREIGN index"; }
    done
    [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ] || b8=0
    if [ "$b8" = 1 ]; then ok "B8 leaked GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE / GIT_OBJECT_DIRECTORY: all four accepted, neither index written"
    else bad "B8 leaked location env"; fi
fi

AX=B9; freshcache; P="$W/b9"
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n[core]\n\tautocrlf = true\n' > "$W/gitconfig"
mkconsumer "$P" "" 1
EXPECT_CRLF=$(git -C "$O" show 1.0.0:dist/foo.cyr | sed 's/$/\r/' | $SHACMD | cut -d' ' -f1)
rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/b9first.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ]; then
    benign B9 "global core.autocrlf=true (CRLF checkout): accepted, no false refusal" "$P" "$C" "$EXPECT_CRLF"
else bad "B9 setup: first resolve under autocrlf rc=$rc"; fi
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# B10/B11: a consumer repo whose pre-commit hook runs `cyrius deps`. Git exports an
# absolute GIT_INDEX_FILE (.git/index.lock) into every hook, so through 6.6.4 the COLD
# run's `git clone` rewrote the user's in-progress commit index and their commit died
# with "invalid object … Error building trees"; the WARM run refused every time.
AX=B10; freshcache; P="$W/b10"; mkconsumer "$P" "" 1
( cd "$P" && git init -q . && printf 'lib/\nbuild/\ncyrius.lock\n' > .gitignore && git add -A && git commit -qm init )
mkdir -p "$P/.git/hooks"
printf '#!/bin/sh\nCYRIUS_HOME=%s GIT_ALLOW_PROTOCOL=file %s deps > /dev/null 2>&1\nexit 0\n' "$H" "$CY" > "$P/.git/hooks/pre-commit"
chmod +x "$P/.git/hooks/pre-commit"
printf '\n# user edit during the commit\n' >> "$P/cyrius.cyml"
rc=0; if ( cd "$P" && git commit -qam "user edit" > "$W/b10.out" 2>&1 ); then rc=0; else rc=$?; fi
after=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=none "$CY" deps > "$W/b10b.out" 2>&1 ); then after=0; else after=$?; fi
if [ "$rc" -eq 0 ] && git -C "$P" show HEAD:cyrius.cyml 2>/dev/null | grep -q 'user edit during the commit' \
   && [ -f "$C/.git/index" ] && [ "$after" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; then
    ok "B10 pre-commit hook + COLD cache: the commit succeeds, the user's edit is in HEAD, the cache keeps its own index"
else bad "B10 hook/cold (commit rc=$rc, later resolve rc=$after, cache index $([ -f "$C/.git/index" ] && echo present || echo MISSING)): $(tail -2 "$W/b10.out")"; fi

AX=B11
printf '\n# second user edit\n' >> "$P/cyrius.cyml"
rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=none git commit -qam "second edit" > "$W/b11.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && git -C "$P" show HEAD:cyrius.cyml 2>/dev/null | grep -q 'second user edit'; then
    ok "B11 pre-commit hook + WARM cache: the hook resolve is clean and the commit succeeds"
else bad "B11 hook/warm (commit rc=$rc): $(tail -2 "$W/b11.out")"; fi

# B12: a dep whose TAG COMMIT trips an fsck POLICY check — an author line with no email,
# which git 2.55 reports as `error … missingEmail` and exits 1 for. Treating that as
# object-store damage made the dep permanently unresolvable with a false diagnosis: the
# advertised `rm -rf <cache>` re-clones the same objects and refuses again. The commit is
# built with `hash-object --literally` (git only, no python3), and the axis first CHECKS
# that a plain fsck really does exit 1 on it — otherwise it would prove nothing.
AX=B12; freshcache
O2="$W/origin2"; mkdir -p "$O2/dist"
printf 'fn foo_answer(): i64 { return 42; }\n' > "$O2/dist/foo.cyr"
( cd "$O2" && git init -q . && git add -A && git commit -qm base )
T2=$(git -C "$O2" rev-parse 'HEAD^{tree}')
LEGACYC=$(printf 'tree %s\nauthor legacy 1700000000 +0000\ncommitter gate <gate@example.invalid> 1700000000 +0000\n\nold\n' "$T2" \
          | git -C "$O2" hash-object -t commit -w --stdin --literally 2>/dev/null || true)
EXPECT2=$(git -C "$O2" show 'HEAD:dist/foo.cyr' | $SHACMD | cut -d' ' -f1)
b12ok=0
if [ -n "$LEGACYC" ]; then
    git -C "$O2" update-ref refs/heads/main "$LEGACYC"
    git -C "$O2" reset -q --hard main >/dev/null 2>&1 || true
    git -C "$O2" tag -f 2.0.0 "$LEGACYC" >/dev/null 2>&1
    ( cd "$O2" && git fsck --no-dangling --no-progress >/dev/null 2>&1 ) || b12ok=1
fi
if [ "$b12ok" = 1 ]; then
    P="$W/b12"; mkdir -p "$P/src"
    {   printf '[package]\nname = "cachep"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n' "$V"
        printf '[build]\nentry = "src/main.cyr"\noutput = "build/main"\n\n'
        printf '[deps.foo]\ngit = "file://%s"\ntag = "2.0.0"\nmodules = ["dist/foo.cyr"]\n' "$O2"
    } > "$P/cyrius.cyml"
    printf 'fn main(): i64 { return 0; }\n' > "$P/src/main.cyr"
    rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/b12.out" 2>&1 ); then rc=0; else rc=$?; fi
    r2=$(ENVX="" rerun "$P" "$W/b12b.out")
    if [ "$rc" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT2" ]; then
        ok "B12 a tag commit that fails an fsck POLICY check (missingEmail) resolves — only integrity failures refuse"
    else bad "B12 (first rc=$rc, re-resolve rc=$r2, module $(sha_of "$P/lib/foo.cyr") want $EXPECT2): $(grep -m1 -i error "$W/b12b.out" || true)"; fi
else
    skip "B12: this git does not flag the legacy author line, so the axis would prove nothing"
fi

# B13: the filesystem cannot represent the exec bit (vfat/exfat/NTFS-3g/9p — a USB stick, a
# WSL /mnt/c). `core.fileMode=true` was FORCED, overriding the value git-clone writes from
# its own probe, so every 755 entry read as mode-changed and the dep refused FOREVER: the
# printed `reset --hard` cannot set a bit the filesystem has no room for. Such a mount needs
# root to create here, so the axis drives the same code path by making the probe itself
# impossible (its parent directory read-only) and asserts BOTH halves: a mode-only
# difference no longer bricks the dep, and content tampering is still refused in that state.
AX=B13; freshcache; P="$W/b13"; mkconsumer "$P" "" 1
# When the exec bit cannot be PROBED (nothing writable beside the cache), the check forces
# nothing and falls back to the value git's own clone-time probe wrote into the cache —
# which is the only other measurement of the same question. The two halves below are the
# two answers that value can have, and they must differ:
#   B13  `core.filemode=false` (what a clone onto vfat/exfat/9p writes): a mode-only
#        difference is ACCEPTED. Forcing `true` here would refuse such a dep for ever, and
#        the advertised recovery cannot fix it — `reset --hard` cannot set a bit the
#        filesystem has no room for. 104 of the 138 live checkouts carry a 755 file.
#   B13b `core.filemode=true` (this box, ext4): the same mode-only difference is REFUSED.
#        Answering "not storable" whenever the probe merely could not RUN was a fail-open
#        needing no attacker control of the cache config at all — found in review round 2,
#        measured as rc 0 on a chmod -x tamper with a read-only parent directory.
if first "$P"; then
    chmod -x "$C/tools/run.sh"                 # a tracked 755 file arriving as 644
    git -C "$C" config --local core.fileMode false   # ...as a vfat clone would have written
    chmod a-w "$H/deps/foo"                    # ...and no way to probe the filesystem
    r=$(ENVX="" rerun "$P" "$W/b13.out")
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    r2=$(ENVX="" rerun "$P" "$W/b13b.out")
    chmod u+w "$H/deps/foo"
    if [ "$r" -eq 0 ] && [ "$r2" -ne 0 ] && grep -q 'content, mode or type differs' "$W/b13b.out"; then
        ok "B13 exec-bit probe impossible + the cache's own core.fileMode=false: a mode-only difference is accepted (no permanent brick on a filesystem that cannot store it), content tampering still refused"
    else bad "B13 (mode-only rc=$r want 0, content-tamper rc=$r2 want != 0): $(grep -m1 -i error "$W/b13.out" || true)"; fi
    git -C "$C" checkout -q -- dist/foo.cyr 2>/dev/null || true
    git -C "$C" config --local core.fileMode true
    chmod -x "$C/tools/run.sh"
    chmod a-w "$H/deps/foo"
    r3=$(ENVX="" rerun "$P" "$W/b13c.out")
    chmod u+w "$H/deps/foo"
    if [ "$r3" -ne 0 ] && grep -q 'content, mode or type differs' "$W/b13c.out" \
       && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; then
        ok "B13b ...but with the cache's own core.fileMode=true, an unprobeable directory does NOT become a free pass for a mode tamper"
    else bad "B13b (rc=$r3 want != 0): $(grep -m1 -i error "$W/b13c.out" || echo 'NO ERROR — the unprobeable path fell open')"; fi
    chmod +x "$C/tools/run.sh"
fi

# ══ REFUSALS ═════════════════════════════════════════════════════════════════════════════

AX=R1; freshcache; P="$W/r1"; mkconsumer "$P" "" 1
if first "$P"; then
    printf 'fn foo_answer(): i64 { return 66; }\n' > "$C/dist/foo.cyr"
    ENVX="" refused R1 "same-size content edit" "$P" "content, mode or type differs" "$C"
    recover R1 "$P"
fi

AX=R2; freshcache; P="$W/r2"; mkconsumer "$P" "" 1
if first "$P"; then
    # the shape EVERY stat-trusting variant misses, including both remedies the filing
    # proposed: same size, mtime restored, and the config told not to look at ctime.
    # ⚠ THREE things are load-bearing here, and the first cut of this axis had none of
    # them — it was caught by the 6.6.4 check too, i.e. it proved nothing:
    #   1. the index must be written at least a SECOND after the file's mtime, or git's
    #      racily-clean rule re-hashes the entry and any stat-trusting check catches it.
    #      Any porcelain command run in a warm cache does exactly this rewrite.
    #   2. the restored mtime must be nanosecond-exact (`touch -r`, not `touch -t`).
    #   3. core.trustctime=false, because an in-place write moves ctime.
    git -C "$C" config core.trustctime false; git -C "$C" config core.checkStat minimal
    cp -a "$C/dist/foo.cyr" "$W/r2.ref"
    sleep 1.1; git -C "$C" status >/dev/null 2>&1 || true
    printf 'fn foo_answer(): i64 { return 66; }\n' > "$C/dist/foo.cyr"
    touch -r "$W/r2.ref" "$C/dist/foo.cyr"
    ENVX="" refused R2 "in-place edit, mtime restored, trustctime=false + checkStat=minimal" "$P" "content, mode or type differs" "$C"
    recover R2 "$P" "git -C $C config --unset core.trustctime; git -C $C config --unset core.checkStat"
fi

AX=R3; freshcache; P="$W/r3"; mkconsumer "$P" "" 1
if first "$P"; then
    # ⚠ THIS AXIS IS ALSO THE ONE THAT PROVES THE EXEC-BIT PROBE READS st_mode CORRECTLY,
    # and it can only prove it on the host it runs on: st_mode is at byte 24 on x86-Linux,
    # 16 on aarch64-Linux and 4 on macOS-arm64. Measured under qemu-aarch64 while this was
    # written — a hand-written 24 made the ARM build read st_uid and ACCEPT this tamper at
    # rc 0. Run the gate on pi/ecb with CYRIUS_GATE_CLI=<built cyrius> to cover it there.
    git -C "$C" config core.fileMode false
    chmod +x "$C/dist/foo.cyr"
    ENVX="" refused R3 "chmod +x under the cache's own core.fileMode=false" "$P" "content, mode or type differs" "$C"
    recover R3 "$P" "git -C $C config --unset core.fileMode"
fi

AX=R4; freshcache; P="$W/r4"; mkconsumer "$P" "" 1
if first "$P"; then
    sedi 's|^modules = .*|modules = ["dist/foo.cyr", "dist/baz.cyr"]|' "$P/cyrius.cyml"
    printf 'fn foo_baz(): i64 { return 666; }\n' > "$C/dist/baz.cyr"
    ENVX="" refused R4 "untracked file planted at a DECLARED-but-absent module path" "$P" "files the tag does not" "$C"
    [ -e "$P/lib/foo_baz.cyr" ] && bad "R4 the planted module was vendored as lib/foo_baz.cyr" || ok "R4b ...and lib/foo_baz.cyr was NOT vendored"
    recover R4 "$P" "sedi 's|^modules = .*|modules = [\"dist/foo.cyr\"]|' $P/cyrius.cyml"
fi

AX=R5; freshcache; P="$W/r5"; mkconsumer "$P" "" 1
if first "$P"; then
    sedi 's|^modules = .*|modules = ["dist/foo.cyr", "dist/qux.cyr"]|' "$P/cyrius.cyml"
    printf 'fn foo_qux(): i64 { return 666; }\n' > "$C/lib/qux.cyr"
    ENVX="" refused R5 "untracked file planted at the lib/<basename> FALLBACK path" "$P" "files the tag does not" "$C"
    [ -e "$P/lib/foo_qux.cyr" ] && bad "R5 the planted fallback module was vendored" || ok "R5b ...and lib/foo_qux.cyr was NOT vendored"
    recover R5 "$P" "sedi 's|^modules = .*|modules = [\"dist/foo.cyr\"]|' $P/cyrius.cyml"
fi

AX=R6; freshcache; P="$W/r6"; mkconsumer "$P" "" 1
if first "$P"; then
    mkdir -p "$C/build"; printf 'x\n' > "$C/build/x.cyr"
    ENVX="" refused R6 "file hidden by the cache's own .gitignore (ls-files -o has no --exclude-standard)" "$P" "files the tag does not" "$C"
    recover R6 "$P"
fi

AX=R7; freshcache; P="$W/r7"; mkconsumer "$P" "" 1
if first "$P"; then
    git -C "$C" update-index --assume-unchanged dist/foo.cyr
    printf 'fn foo_answer(): i64 { return 66; }\n' > "$C/dist/foo.cyr"
    ENVX="" refused R7 "assume-unchanged bit + content edit" "$P" "content, mode or type differs" "$C"
    recover R7 "$P" "git -C $C update-index --no-assume-unchanged dist/foo.cyr"
fi

AX=R8; freshcache; P="$W/r8"; mkconsumer "$P" "" 1
if first "$P"; then
    git -C "$C" update-index --skip-worktree dist/foo.cyr
    printf 'fn foo_answer(): i64 { return 66; }\n' > "$C/dist/foo.cyr"
    ENVX="" refused R8 "skip-worktree bit (sparse checkout sets it) + content edit" "$P" "content, mode or type differs" "$C"
    recover R8 "$P" "git -C $C update-index --no-skip-worktree dist/foo.cyr"
fi

AX=R9; freshcache; P="$W/r9"; mkconsumer "$P" "" 1
if first "$P"; then
    rm -f "$C/lib/foolink.cyr"; ( cd "$C/lib" && ln -s /etc/passwd foolink.cyr )
    ENVX="" refused R9 "tracked symlink retargeted" "$P" "content, mode or type differs" "$C"
    recover R9 "$P"
fi

AX=R10; freshcache; P="$W/r10"; mkconsumer "$P" "" 1
if first "$P"; then
    rm -f "$C/tools/run.sh"
    ENVX="" refused R10 "a non-module tracked file deleted" "$P" "content, mode or type differs" "$C"
    recover R10 "$P"
fi

AX=R11; freshcache; P="$W/r11"; mkconsumer "$P" "" 1
if first "$P"; then
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    git -C "$C" add -A >/dev/null 2>&1; git -C "$C" commit -qm "local tamper" >/dev/null 2>&1
    LOCALC=$(git -C "$C" rev-parse HEAD)
    rm -f "$P/cyrius.lock"                       # TOFU: no lock, so only HEAD == tag can catch it
    ENVX="" refused R11 "local commit in the cache with the lock removed (TOFU)" "$P" "HEAD is not the tag's commit" "$C"
    if [ -f "$P/cyrius.lock" ] && grep -q "$LOCALC" "$P/cyrius.lock"; then bad "R11 the local commit was PINNED into cyrius.lock"; else ok "R11b ...and the local commit was not pinned"; fi
    recover R11 "$P"
fi

AX=R12; freshcache
# CYRIUS_HOME inside a git repo + a cache with no .git: `git -C` discovery used to climb
# into the ENCLOSING repo, so the check passed and cyrius.lock pinned that repo's HEAD.
EH="$W/enclosing"; mkdir -p "$EH/home/deps"
( cd "$EH" && git init -q . && echo enc > enc.txt && git add -A && git commit -qm enclosing )
ENC_HEAD=$(git -C "$EH" rev-parse HEAD)
P="$W/r12"; mkconsumer "$P" "" 1
rc=0; if ( cd "$P" && CYRIUS_HOME="$EH/home" GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r12a.out" 2>&1 ); then rc=0; else rc=$?; fi
C12="$EH/home/deps/foo/1.0.0"
if [ "$rc" -eq 0 ] && [ -d "$C12/.git" ]; then
    rm -rf "$C12/.git"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C12/dist/foo.cyr"
    cp "$P/cyrius.lock" "$W/r12.lock"
    rc=0; if ( cd "$P" && CYRIUS_HOME="$EH/home" GIT_ALLOW_PROTOCOL=none "$CY" deps > "$W/r12.out" 2>&1 ); then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] && grep -q 'its .git is missing' "$W/r12.out" && grep -q "cache: $C12" "$W/r12.out" \
       && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ] && ! grep -q "$ENC_HEAD" "$P/cyrius.lock"; then
        ok "R12 CYRIUS_HOME inside a git repo, cache .git removed: refused as unreadable; the ENCLOSING repo's HEAD was not pinned"
    else bad "R12 (rc=$rc, enclosing HEAD pinned=$(grep -c "$ENC_HEAD" "$P/cyrius.lock" 2>/dev/null || echo 0)): $(grep -m1 -i error "$W/r12.out" || echo 'NO ERROR')"; fi
    # O1 for reason 1: the advertised recovery is `rm -rf <cache>` + re-resolve (needs the remote)
    rm -rf "$C12"; rm -f "$P/lib/foo.cyr"
    rc=0; if ( cd "$P" && CYRIUS_HOME="$EH/home" GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r12r.out" 2>&1 ); then rc=0; else rc=$?; fi
    REC_RUN=$((REC_RUN+1))
    { [ "$rc" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; } || REC_FAIL="$REC_FAIL R12"
else bad "R12 setup: resolve into the enclosing-repo home rc=$rc"; fi

AX=R13; freshcache; P="$W/r13"; mkconsumer "$P" "" 1
if first "$P"; then
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    s0=$(snap "$C"); cp "$P/cyrius.lock" "$W/r13.lock"
    r=$(ENVX="GIT_TEST_ASSUME_DIFFERENT_OWNER=1" rerun "$P" "$W/r13.out")
    if [ "$r" -ne 0 ] && grep -q 'its .git is missing' "$W/r13.out" && grep -q 'dubious ownership\|safe.directory' "$W/r13.out" \
       && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ] && [ "$s0" = "$(snap "$C")" ] && cmp -s "$P/cyrius.lock" "$W/r13.lock"; then
        ok "R13 dubious ownership + edit: refused as unreadable, git's own safe.directory hint quoted"
    else bad "R13 (rc=$r): $(grep -m1 -i 'error\|git:' "$W/r13.out" || echo 'NO ERROR')"; fi
    recover R13 "$P"
fi

AX=R14; freshcache; P="$W/r14"; mkconsumer "$P" "" 1
if first "$P"; then
    ORIGC=$(git -C "$C" rev-parse HEAD)
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    git -C "$C" add -A >/dev/null 2>&1; git -C "$C" commit -qm evil >/dev/null 2>&1
    EVILC=$(git -C "$C" rev-parse HEAD)
    git -C "$C" checkout -q 1.0.0 >/dev/null 2>&1
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    git -C "$C" replace -f "$ORIGC" "$EVILC" >/dev/null 2>&1
    ENVX="" refused R14 "refs/replace over HEAD's commit (honouring it accepts the tamper)" "$P" "content, mode or type differs" "$C"
    recover R14 "$P" "git -C $C replace -d $ORIGC"
fi

AX=R15; freshcache; P="$W/r15"; mkconsumer "$P" "" 1
if first "$P"; then
    # core.fsmonitor is not just a blindfold: it is a program the cache tells git to RUN.
    printf '#!/bin/sh\necho ran >> %s\nprintf "tok"\nprintf "\\0"\n' "$W/r15.ran" > "$W/fsmon"; chmod +x "$W/fsmon"
    git -C "$C" config core.fsmonitor "$W/fsmon"
    git -C "$C" status >/dev/null 2>&1 || true          # arm the index's fsmonitor state
    rm -f "$W/r15.ran"                                  # ...then clear the witness: only the RESOLVER's runs count
    printf 'fn foo_answer(): i64 { return 66; }\n' > "$C/dist/foo.cyr"
    ENVX="" refused R15 "core.fsmonitor hook reporting no change + edit" "$P" "content, mode or type differs" "$C"
    if [ -f "$W/r15.ran" ]; then bad "R15b the cache's core.fsmonitor program was EXECUTED by the resolver"; else ok "R15b ...and the cache's fsmonitor program was never executed"; fi
    recover R15 "$P" "git -C $C config --unset core.fsmonitor"
fi

AX=R16; freshcache; P="$W/r16"; mkconsumer "$P" "" 1
if first "$P"; then
    mkdir -p "$C/vendor/sub"; printf 'planted\n' > "$C/vendor/sub/evil.cyr"
    ENVX="" refused R16 "file planted inside the gitlink directory (invisible to diff-files and ls-files -o)" "$P" "submodule directory is populated" "$C"
    grep -q "populated submodule: $C/vendor/sub" "$W/R16.out" && ok "R16b ...and the message names the directory to empty" || bad "R16b the message does not name the populated directory"
    recover R16 "$P" "rm -rf $C/vendor/sub/evil.cyr"
fi

AX=R17; freshcache; P="$W/r17"; mkconsumer "$P" "" 1
# Only R17/R20 need python3 (writing a forged object at another object's path); through
# 6.6.5 its absence SKIPped all 41 axes to protect these two. Skipped BY NAME instead.
if [ "$HAVE_PY" = 0 ]; then
    skip "R17: python3 not found (the forged-object axes need it)"
    skip "R17b: python3 not found"
    skip "R17c: python3 not found"
elif first "$P"; then
    # a forged loose subtree: the pack is exploded, an evil tree is written at the ORIGINAL
    # tree's object path, and the evil bytes are planted in the working tree. read-tree
    # reads the forgery whole and diff-files then AGREES with it.
    PK=$(ls "$C"/.git/objects/pack/*.pack 2>/dev/null | head -1)
    if [ -n "$PK" ]; then cp "$PK" "$W/r17.pack"; rm -f "$C"/.git/objects/pack/*; ( cd "$C" && git unpack-objects < "$W/r17.pack" >/dev/null 2>&1 ); fi
    T=$(git -C "$C" rev-parse 'HEAD:dist')
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$W/r17.evil"
    EB=$(git -C "$C" hash-object -w "$W/r17.evil")
    ET=$(printf '100644 blob %s\tfoo.cyr\n' "$EB" | git -C "$C" mktree)
    python3 -c 'import sys,os; o,t,e=sys.argv[1:4]; p=lambda h: os.path.join(o,h[:2],h[2:]); d=p(t); os.chmod(d,0o644); open(d,"wb").write(open(p(e),"rb").read())' "$C/.git/objects" "$T" "$ET"
    cp "$W/r17.evil" "$C/dist/foo.cyr"
    ENVX="" refused R17 "forged loose subtree spliced under the original tree's name (only fsck sees it)" "$P" "object-store damage" "$C"
    grep -q 'cannot be repaired locally' "$W/R17.out" && ok "R17b ...and the message does NOT advertise an offline restore for a damaged object store" || bad "R17b the message offers an offline restore that cannot work here"
    # Reason 3 quotes git's own first stderr line (added 6.6.5). Without it "object-store
    # damage" was the whole diagnosis, and a policy complaint (B12's shape) read the same
    # as this forgery.
    grep -q '^  git: ' "$W/R17.out" && ok "R17c ...and it quotes git's own diagnosis" || bad "R17c the reason-3 message quotes nothing from git: $(grep -m1 'git:' "$W/R17.out" || echo none)"
    # reason 3 has no local repair, so its advertised recovery is the rm -rf one (needs the remote)
    REC_RUN=$((REC_RUN+1)); rm -rf "$C"; rm -f "$P/lib/foo.cyr"
    rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r17r.out" 2>&1 ); then rc=0; else rc=$?; fi
    { [ "$rc" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; } || REC_FAIL="$REC_FAIL R17"
fi

AX=R18; freshcache; P="$W/r18"; mkconsumer "$P" "" 1
if first "$P"; then
    cp -a "$C/.git" "$W/r18git"
    rm -rf "$C/.git"; ln -s "$W/r18git" "$C/.git"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    s0=NOGIT; cp "$P/cyrius.lock" "$W/r18.lock"
    r=$(ENVX="" rerun "$P" "$W/r18.out")
    if [ "$r" -ne 0 ] && grep -q 'its .git is missing' "$W/r18.out" && grep -q "cache: $C" "$W/r18.out" \
       && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ] && cmp -s "$P/cyrius.lock" "$W/r18.lock"; then
        ok "R18 .git replaced by a SYMLINK to a copy of itself: refused (a link can point at another repo)"
    else bad "R18 (rc=$r): $(grep -m1 -i error "$W/r18.out" || echo 'NO ERROR')"; fi
    rm -f "$C/.git"; cp -a "$W/r18git" "$C/.git"
    recover R18 "$P"
fi

AX=R19; freshcache
# A `.git` that EXISTS but is not a valid repository: git's discovery does not stop there,
# it keeps CLIMBING. So `_git_has_repo` (a real directory) passes and only the ceiling
# keeps the resolve out of the enclosing repo. Measured: without it, `rev-parse HEAD`
# answers from the enclosing repo and its HEAD is pinned as the dep's commit.
EH2="$W/enclosing2"; mkdir -p "$EH2/home/deps"
( cd "$EH2" && git init -q . && echo enc > enc.txt && git add -A && git commit -qm enclosing2 )
ENC2_HEAD=$(git -C "$EH2" rev-parse HEAD)
P="$W/r19"; mkconsumer "$P" "" 1
rc=0; if ( cd "$P" && CYRIUS_HOME="$EH2/home" GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r19a.out" 2>&1 ); then rc=0; else rc=$?; fi
C19="$EH2/home/deps/foo/1.0.0"
if [ "$rc" -eq 0 ] && [ -d "$C19/.git" ]; then
    rm -rf "$C19/.git/objects" "$C19/.git/refs" "$C19/.git/HEAD"      # a real dir, an invalid repo
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C19/dist/foo.cyr"
    rc=0; if ( cd "$P" && CYRIUS_HOME="$EH2/home" GIT_ALLOW_PROTOCOL=none "$CY" deps > "$W/r19.out" 2>&1 ); then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] && grep -q 'refusing tampered cache' "$W/r19.out" && grep -q "cache: $C19" "$W/r19.out" \
       && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ] && ! grep -q "$ENC2_HEAD" "$P/cyrius.lock"; then
        ok "R19 a GUTTED .git (real directory, invalid repo) inside a git-repo home: refused, discovery never reached the enclosing repo"
    else bad "R19 (rc=$rc, enclosing HEAD pinned=$(grep -c "$ENC2_HEAD" "$P/cyrius.lock" 2>/dev/null || echo 0)): $(grep -m1 -i error "$W/r19.out" || echo 'NO ERROR')"; fi
    rm -rf "$C19"; rm -f "$P/lib/foo.cyr"
    rc=0; if ( cd "$P" && CYRIUS_HOME="$EH2/home" GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r19r.out" 2>&1 ); then rc=0; else rc=$?; fi
    REC_RUN=$((REC_RUN+1))
    { [ "$rc" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; } || REC_FAIL="$REC_FAIL R19"
else bad "R19 setup: resolve into the second enclosing-repo home rc=$rc"; fi

AX=R20; freshcache; P="$W/r20"; mkconsumer "$P" "" 1
if [ "$HAVE_PY" = 0 ]; then
    skip "R20: python3 not found (the forged-object axes need it)"
elif first "$P"; then
    # R17 again, with the cache's own index REMOVED (B4 says that state is benign, so an
    # attacker reaches it for free). ⛔ THIS is the axis that makes the fsck a FULL one:
    # `--connectivity-only` exits 0 here. On R17 it exits 8 only because that cache still
    # has an index whose cache-tree names the mangled object — an accident, not a check.
    PK=$(ls "$C"/.git/objects/pack/*.pack 2>/dev/null | head -1)
    if [ -n "$PK" ]; then cp "$PK" "$W/r20.pack"; rm -f "$C"/.git/objects/pack/*; ( cd "$C" && git unpack-objects < "$W/r20.pack" >/dev/null 2>&1 ); fi
    T=$(git -C "$C" rev-parse 'HEAD:dist')
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$W/r20.evil"
    EB=$(git -C "$C" hash-object -w "$W/r20.evil")
    ET=$(printf '100644 blob %s\tfoo.cyr\n' "$EB" | git -C "$C" mktree)
    python3 -c 'import sys,os; o,t,e=sys.argv[1:4]; p=lambda h: os.path.join(o,h[:2],h[2:]); d=p(t); os.chmod(d,0o644); open(d,"wb").write(open(p(e),"rb").read())' "$C/.git/objects" "$T" "$ET"
    cp "$W/r20.evil" "$C/dist/foo.cyr"
    rm -f "$C/.git/index"
    ENVX="" refused R20 "the same forgery with the cache index removed (only a FULL fsck sees it)" "$P" "object-store damage" "$C"
    REC_RUN=$((REC_RUN+1)); rm -rf "$C"; rm -f "$P/lib/foo.cyr"
    rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r20r.out" 2>&1 ); then rc=0; else rc=$?; fi
    { [ "$rc" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; } || REC_FAIL="$REC_FAIL R20"
fi

# ── R21-R27, R29: the cache's own CONFIG decides what git compares ───────────────────────
# Everything below is inside `.git`, so `ls-files -o` cannot see it and the working tree
# looks untouched to every content command. Every one was measured ACCEPTING the tamper at
# exit 0 against the first cut of this release, which pinned five `-c` values on the cache's
# config and considered the config handled. A fixed `-c` list can only override keys whose
# NAMES you know — and the driver name in `filter.<name>.clean` is the attacker's to pick.

AX=R21; freshcache; P="$W/r21"; mkconsumer "$P" "" 1
if first "$P"; then
    # core.worktree points the comparison at a DIFFERENT directory: a pristine copy beside
    # the tampered cache. Every content command then reads the copy and agrees with it,
    # while the resolver vendors from the cache. `_git_env_argv` unset GIT_WORK_TREE but
    # never SET it, so discovery took the work tree from this key.
    cp -a "$C" "$W/r21pristine"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    git -C "$C" config core.worktree "$W/r21pristine"
    ENVX="" refused R21 "core.worktree redirecting the comparison at a pristine copy" "$P" "rewrites or redirects" "$C"
    recover R21 "$P" "git -C $C config --unset core.worktree"
fi

AX=R22; freshcache; P="$W/r22"; mkconsumer "$P" "" 1
if first "$P"; then
    # A clean filter is a PROGRAM git runs over the working tree while hashing it, and it
    # rewrites the bytes it feeds the comparison. `-c` cannot neutralise it: the driver name
    # is attacker-chosen. The key alone is the refusal.
    git -C "$C" config filter.launder.clean "cat"
    ENVX="" refused R22 "a filter driver declared in the cache's own config" "$P" "rewrites or redirects" "$C"
    grep -q "offending setting: filter.launder.clean" "$W/R22.out" && ok "R22b ...and the message names the key" || bad "R22b the message does not name filter.launder.clean"
    recover R22 "$P" "git -C $C config --unset-all filter.launder.clean"
fi

AX=R23; freshcache; P="$W/r23"; mkconsumer "$P" "" 1
if first "$P"; then
    # The full laundering setup: the driver prints the HONEST bytes, .git/info/attributes
    # assigns it to the edited file. Measured against the first cut: exit 0, "1 deps
    # resolved", the 666 bytes vendored, and the cache-named program run twice.
    printf '#!/bin/sh\necho ran >> %s\nprintf "fn foo_answer(): i64 { return 42; }\\n"\n' "$W/r23.ran" > "$W/launder"
    chmod +x "$W/launder"
    git -C "$C" config filter.launder.clean "$W/launder"
    mkdir -p "$C/.git/info"; printf 'dist/foo.cyr filter=launder\n' > "$C/.git/info/attributes"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    rm -f "$W/r23.ran"
    ENVX="" refused R23 "an edit laundered by a clean filter + .git/info/attributes" "$P" "rewrites or redirects" "$C"
    if [ -f "$W/r23.ran" ]; then bad "R23b the cache's filter program was EXECUTED by the resolver"; else ok "R23b ...and the cache's filter program was never executed"; fi
    recover R23 "$P" "git -C $C config --unset-all filter.launder.clean; rm -f $C/.git/info/attributes"
fi

AX=R24; freshcache; P="$W/r24"; mkconsumer "$P" "" 1
if first "$P"; then
    # The cache directory is keyed on dep NAME and TAG only, so a checkout of a DIFFERENT
    # repository that carries the same tag is reused as this dep. Staged the way an attacker
    # (or a name collision) would: clone the other repo over the cache directory.
    EV="$W/r24evil"; mkdir -p "$EV/dist"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$EV/dist/foo.cyr"
    ( cd "$EV" && git init -q . && git add -A && git commit -qm evil && git tag 1.0.0 )
    chmod -R u+w "$C"; rm -rf "$C"
    GIT_ALLOW_PROTOCOL=file git clone -q --depth 1 -b 1.0.0 "file://$EV" "$C" 2>/dev/null
    rm -f "$P/cyrius.lock"                       # TOFU: only the declared url can catch it
    ENVX="" refused R24 "a checkout of a DIFFERENT repo carrying the same tag" "$P" "origin remote is not the URL" "$C"
    # reason 8 has no offline repair either — the advertised recovery is rm -rf + re-clone
    REC_RUN=$((REC_RUN+1)); chmod -R u+w "$C"; rm -rf "$C"; rm -f "$P/lib/foo.cyr"
    rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/r24r.out" 2>&1 ); then rc=0; else rc=$?; fi
    { [ "$rc" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; } || REC_FAIL="$REC_FAIL R24"
fi

AX=R25; freshcache; P="$W/r25"; mkconsumer "$P" "" 1
if first "$P"; then
    # ⛔ THE AXIS A "scan for filter.*" FIX MISSES. git FOLLOWS include.path when it reads
    # the config, but `git config --local --name-only --list` does NOT print what the
    # include pulls in (measured: the listing shows only `include.path`, and the included
    # filter laundered the edit anyway). So the include itself has to be the refusable thing.
    printf '#!/bin/sh\nprintf "fn foo_answer(): i64 { return 42; }\\n"\n' > "$W/r25launder"
    chmod +x "$W/r25launder"
    printf '[filter "inc"]\n\tclean = %s\n' "$W/r25launder" > "$W/r25.cfg"
    git -C "$C" config include.path "$W/r25.cfg"
    mkdir -p "$C/.git/info"; printf 'dist/foo.cyr filter=inc\n' > "$C/.git/info/attributes"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    ENVX="" refused R25 "a filter hidden behind include.path (invisible to --local --list)" "$P" "rewrites or redirects" "$C"
    recover R25 "$P" "git -C $C config --unset include.path; rm -f $C/.git/info/attributes"
fi

AX=R26; freshcache; P="$W/r26"; mkconsumer "$P" "" 1
if first "$P"; then
    # End-of-line conversion is applied while hashing, so a local core.autocrlf launders a
    # CRLF/LF-only edit. It cannot be forced off on the command line either: a user whose
    # GLOBAL autocrlf is on has a legitimately CRLF working tree (axis B9), so a forced
    # `false` would refuse THAT. Hence a refusal on the key.
    git -C "$C" config core.autocrlf true
    git -C "$C" show 'HEAD:dist/foo.cyr' | sed 's/$/\r/' > "$C/dist/foo.cyr"
    ENVX="" refused R26 "core.autocrlf in the cache's config (launders a CRLF-only edit)" "$P" "rewrites or redirects" "$C"
    recover R26 "$P" "git -C $C config --unset core.autocrlf"
fi

AX=R27; freshcache; P="$W/r27"; mkconsumer "$P" "" 1
if first "$P"; then
    # `.git/info/attributes` ALONE, with no filter driver anywhere: `* text eol=crlf` makes
    # git convert while hashing, so a CRLF-only edit compares EQUAL (measured rc 0 with it,
    # rc 1 without). This axis exists because the ledger could not otherwise prove the
    # attributes-file check — R23/R25 also carry a config key and refuse on that.
    mkdir -p "$C/.git/info"; printf '* text eol=crlf\n' > "$C/.git/info/attributes"
    git -C "$C" show 'HEAD:dist/foo.cyr' | sed 's/$/\r/' > "$C/dist/foo.cyr"
    ENVX="" refused R27 ".git/info/attributes alone (eol conversion launders a CRLF edit)" "$P" "rewrites or redirects" "$C"
    grep -q "offending setting: $C/.git/info/attributes" "$W/R27.out" && ok "R27b ...and the message names the file" || bad "R27b the message does not name .git/info/attributes"
    recover R27 "$P" "rm -f $C/.git/info/attributes"
fi

AX=R29; freshcache; P="$W/r29"; mkconsumer "$P" "" 1
if first "$P"; then
    # The SAME redirect as R21, hidden in git's second config file. `extensions.worktreeConfig
    # = true` makes git read `.git/config.worktree`, whose keys `config --local --name-only
    # --list` does NOT print (measured: only `extensions.worktreeconfig` shows), so a scan of
    # the local config alone never sees the core.worktree in it — and the redirect works
    # (measured: diff-files rc 0 against a pristine copy). Two independent things catch it:
    # the extensions key is refused, and GIT_WORK_TREE overrides the redirect anyway.
    cp -a "$C" "$W/r29pristine"
    printf 'fn foo_answer(): i64 { return 666; }\n' > "$C/dist/foo.cyr"
    git -C "$C" config extensions.worktreeConfig true
    printf '[core]\n\tworktree = %s\n' "$W/r29pristine" > "$C/.git/config.worktree"
    ENVX="" refused R29 "core.worktree hidden in .git/config.worktree (invisible to --local --list)" "$P" "refusing tampered cache" "$C"
    recover R29 "$P" "git -C $C config --unset extensions.worktreeConfig; rm -f $C/.git/config.worktree"
fi

# R28: the commit-pin mismatch — a REFUSAL the gate had no axis for at all, which is how a
# temp-file leak on that path (it refuses without going through `_git_cache_refuse`, so it
# never cleared the stderr capture) stayed invisible. Both halves are asserted here.
# ⚠ The leak half counts `{git_err,dep_verify_*,git_rev_out}` — names only the dep git flow
# creates — in the temp dir of THIS resolve's process only (tmpn, v6.6.6): the old delta over
# every /tmp/cyrius-* dir moved whenever another check.sh resolved deps on the same box.
AX=R28; freshcache; P="$W/r28"; mkconsumer "$P" "" 1
if first "$P"; then
    cp "$P/cyrius.lock" "$W/r28.lock"
    sedi "s|^commit	[0-9a-f]*|commit	0000000000000000000000000000000000000000|" "$P/cyrius.lock"
    rm -f "$W/last.pid"; t0=$(tmpn)
    r=$(ENVX="" rerun "$P" "$W/r28.out")
    t1=$(tmpn)
    if [ "$r" -ne 0 ] && grep -q 'commit-pin mismatch' "$W/r28.out" && [ "$t1" -le "$t0" ]; then
        ok "R28 commit-pin mismatch refuses and leaves no temp file behind (delta $((t1 - t0)))"
    else bad "R28 (rc=$r, temp-file delta $((t1 - t0))): $(grep -m1 -i error "$W/r28.out" || echo 'NO ERROR')"; fi
    cp "$W/r28.lock" "$P/cyrius.lock"; rm -f "$P/lib/foo.cyr"
    r=$(ENVX="" rerun "$P" "$W/r28r.out")
    { [ "$r" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; } \
        && ok "R28b ...and restoring the pin resolves again" || bad "R28b the restored pin did not resolve (rc=$r)"
fi

# ══ round-2 axes: url spelling, tag-carried attributes, the pin branches ═════════════════
# Everything above resolves ONE literal url spelling from ONE origin that carries no
# .gitattributes, so no axis above could see any of the defects below.

# A second origin, byte-identical module (so EXPECT and recover() still apply) plus a
# tracked `* text=auto`. The attributes are carried BY THE TAG, so they are legitimate —
# they cannot be refused the way `.git/info/attributes` (R27) is.
OA="$W/oattr"; mkdir -p "$OA/dist"
cp "$O/dist/foo.cyr" "$OA/dist/foo.cyr"
printf '* text=auto\n' > "$OA/.gitattributes"
( cd "$OA" && git init -q . && git add -A && git commit -qm v1 && git tag 1.0.0 )
[ "$(git -C "$OA" show 1.0.0:dist/foo.cyr | $SHACMD | cut -d' ' -f1)" = "$EXPECT" ] \
    || { echo "FAIL: deps_git_cache_verified: the attributes origin's module is not EXPECT"; exit 1; }
# The CRLF spelling of the SAME module, computed from the origin — never from the cache.
# (B9 above already proves the no-attributes half of this; B16/R30b add the attribute-driven
# conversion on top of it, which is a different code path inside git's convert layer.)
EXPECT_CRLF_A=$(git -C "$OA" show 1.0.0:dist/foo.cyr | sed 's/$/\r/' | $SHACMD | cut -d' ' -f1)

mkconsumer2() {  # $1=dir $2=url  — mkconsumer with the url spelled out
    mkconsumer "$1" "" 1
    sedi "s|git = \"file://$O\"|git = \"$2\"|" "$1/cyrius.cyml"
}
# first() asserts the MAIN origin's tag commit, so these use their own first resolve.
firstx() {  # $1=proj $2=expected module sha
    rc=0
    if ( cd "$1" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/firstx.out" 2>&1 ); then rc=0; else rc=$?; fi
    [ "$rc" -eq 0 ] || { bad "$AX setup: first resolve rc=$rc: $(tail -2 "$W/firstx.out")"; return 1; }
    [ "$(sha_of "$1/lib/foo.cyr")" = "$2" ] || { bad "$AX setup: vendored module != the origin's bytes"; return 1; }
    return 0
}

AX=B14; freshcache; P="$W/b14"; mkconsumer2 "$P" "file://$OA"
if firstx "$P" "$EXPECT"; then
    benign B14 "a tag that carries .gitattributes (* text=auto), untouched: accepted" "$P" "$C" "$EXPECT"
fi

AX=R30
# A CRLF-ONLY rewrite. `text=auto` normalises while hashing, so diff-files AGREES with the
# tamper: 6.6.5 rc1 accepted this at exit 0 and vendored the changed bytes (measured).
# Same laundering class as R26 (core.autocrlf) and R27 (.git/info/attributes).
sedi 's/$/\r/' "$C/dist/foo.cyr"
grep -q "$CR" "$C/dist/foo.cyr" || bad "R30 setup: the CRLF rewrite did not take"
refused R30 "a CRLF-only edit laundered by the TAG's own .gitattributes is refused" "$P" 'content conversion was hiding it' "$C"
recover R30 "$P"

AX=B16
# ...and the honest twin, which is why this cannot simply refuse conversions: with
# core.autocrlf=true in the USER's global config the checkout is legitimately CRLF.
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n[core]\n\tautocrlf = true\n' > "$W/gitconfig"
freshcache; P="$W/b16"; mkconsumer2 "$P" "file://$OA"
if firstx "$P" "$EXPECT_CRLF_A"; then
    grep -q "$CR" "$C/dist/foo.cyr" || bad "B16 setup: autocrlf=true did not produce a CRLF checkout"
    benign B16 "a legitimately CRLF working tree (global core.autocrlf=true AND a tag-carried * text=auto): accepted, not refused" "$P" "$C" "$EXPECT_CRLF_A"
    printf 'fn foo_answer(): i64 { return 666; }\r\n' > "$C/dist/foo.cyr"
    # `refused` asserts the ALREADY-vendored module is untouched, and under autocrlf that
    # module is the CRLF spelling — still computed from the origin, never from the cache.
    EXPECT_SAVE="$EXPECT"; EXPECT="$EXPECT_CRLF_A"; AX=R30b
    refused R30b "...and a REAL edit under that same conversion is still refused" "$P" 'content, mode or type differs' "$C"
    EXPECT="$EXPECT_SAVE"
fi
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

AX=B15
# `…/x` and `…/x.git` are ONE repository on every forge, and the cache is keyed on dep
# name+tag, so both spellings land on the same directory. Comparing the strings exactly
# refused 19 declarations across 11 repos on this box with NO fixed point — removing the
# cache as the message says makes the OTHER consumer refuse instead.
OG="$W/oeq.git"; cp -a "$O" "$OG"
freshcache; PA="$W/b15a"; PB="$W/b15b"
mkconsumer2 "$PA" "file://$OG"; mkconsumer2 "$PB" "file://$W/oeq"
if firstx "$PA" "$EXPECT"; then
    cu=$(git -C "$C" config --local --get remote.origin.url)
    case "$cu" in *.git) ;; *) bad "B15 setup: the cache's origin is not the .git spelling ($cu)" ;; esac
    s0=$(snap "$C"); r=$(ENVX="" rerun "$PB" "$W/b15.out"); s1=$(snap "$C")
    if [ "$r" -eq 0 ] && [ "$(sha_of "$PB/lib/foo.cyr")" = "$EXPECT" ] && [ "$s0" = "$s1" ]; then
        ok "B15 the same cache resolves from BOTH url spellings (…/x and …/x.git)"
    else bad "B15 (rc=$r, module=$(sha_of "$PB/lib/foo.cyr")): $(grep -m1 -i error "$W/b15.out" || echo 'NO ERROR')"; fi
fi

AX=R28d
# The COMMIT PIN is looked up by (name, url, tag) too, so the same suffix equivalence decides
# whether it binds — and there the failure mode is not a refusal but a SILENT TOFU RE-PIN: the
# moved-tag check the pin exists for is skipped for that resolve. Resolve with one spelling,
# respell the manifest, poison the pin, and the mismatch must still fire.
freshcache; P="$W/r28d"; mkconsumer2 "$P" "file://$OG"
if firstx "$P" "$EXPECT"; then
    grep -q "^commit	" "$P/cyrius.lock" || bad "R28d setup: no commit pin was written"
    sedi "s|git = \"file://$OG\"|git = \"file://$W/oeq\"|" "$P/cyrius.cyml"
    sedi "s|^commit	[0-9a-f]*|commit	0000000000000000000000000000000000000000|" "$P/cyrius.lock"
    r=$(ENVX="" rerun "$P" "$W/r28d.out")
    if [ "$r" -ne 0 ] && grep -q 'commit-pin mismatch' "$W/r28d.out"; then
        ok "R28d the commit pin still binds when the manifest respells the url (…/x vs …/x.git) — it does not silently re-pin"
    else bad "R28d (rc=$r): $(grep -m1 -i error "$W/r28d.out" || echo 'NO ERROR — the pin was looked up by an exact url and silently re-pinned')"; fi
fi

AX=R28c
# R28 covers the pin MISMATCH branch; this is the other branch fixed in 6.6.5 — a corrupt
# `commit\t` line, which fails closed rather than silently re-pinning over corruption, and
# clears its own stderr capture (it does not go through _git_cache_refuse).
freshcache; P="$W/r28c"; mkconsumer "$P" "" 1
if first "$P"; then
    sedi "s|^commit	[0-9a-f]*	foo	.*|commit	zznotasha	foo|" "$P/cyrius.lock"
    rm -f "$W/last.pid"; t0=$(tmpn)
    r=$(ENVX="" rerun "$P" "$W/r28c.out")
    t1=$(tmpn)
    if [ "$r" -ne 0 ] && grep -q 'corrupt commit-pin line' "$W/r28c.out" && [ "$t1" -le "$t0" ]; then
        ok "R28c a corrupt commit-pin line refuses and leaves no temp file behind (delta $((t1 - t0)))"
    else bad "R28c (rc=$r, temp-file delta $((t1 - t0))): $(grep -m1 -i error "$W/r28c.out" || echo 'NO ERROR')"; fi
fi

# ══ O1 — every refusal is undone by the recovery the message advertises ═══════════════════
# The floor is DERIVED, not tuned: R1-R27, R29 and R30 each recover exactly once (R28/R28c are
# pin refusals, not cache refusals, and assert their own recovery inline), less the two (R17,
# R20) that cannot run without python3. It fired under mutants M1 and M4.
# ⚠ WHAT O1 PROVES is that each refusal was caused by its own mutation and is reversible
# OFFLINE — not that one printed recipe undoes every axis. For the config refusals (reason 7)
# the recipe is to REMOVE THE SETTING, which `recover()` passes as its $3: a reset/clean
# leaves `.git/config` alone, so the refusal correctly survives one (measured).
REC_MIN=29; [ "$HAVE_PY" = 0 ] && REC_MIN=27
if [ "$REC_RUN" -lt "$REC_MIN" ]; then
    bad "O1 only $REC_RUN recovery runs were attempted (floor is $REC_MIN) — axes were skipped"
elif [ -z "$REC_FAIL" ]; then
    ok "O1 all $REC_RUN refusals are reversible OFFLINE (each was caused by its own mutation, not by a broken fixture; the reason-7 axes need the SETTING removed, not just a reset)"
else
    bad "O1 recovery failed for:$REC_FAIL"
fi

# ══ C1 / U1 / U2 ═════════════════════════════════════════════════════════════════════════

AX=C1; freshcache; P="$W/c1"; mkconsumer "$P" "" 1
sedi "s|git = \"file://$O\"|git = \"file://$W/does-not-exist\"|" "$P/cyrius.cyml"
rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/c1.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'git clone failed for dep' "$W/c1.out" && ! grep -q 'not found at tag' "$W/c1.out"; then
    ok "C1 a clone that fails is reported as a clone failure ONCE (was: the misleading 'not found at tag', and nothing else)"
else bad "C1 (rc=$rc): $(grep -m1 -i error "$W/c1.out" || echo 'NO ERROR')"; fi

AX=U2; freshcache; P="$W/u2"; mkconsumer "$P" "" 0
rc=0; if ( cd "$P" && GIT_ALLOW_PROTOCOL=file "$CY" deps > "$W/u2.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ]; then
    ok "U2 an UNTAGGED git dep resolves clean (the float is not broken by the new check)"
else bad "U2 (rc=$rc): $(tail -2 "$W/u2.out")"; fi

AX=U1
printf 'fn foo_answer(): i64 { return 666; }\n' > "$CU/dist/foo.cyr"
s0=$(snap "$CU")
r=$(ENVX="" rerun "$P" "$W/u1.out")
if [ "$r" -ne 0 ] && grep -q 'content, mode or type differs' "$W/u1.out" && grep -q "cache: $CU" "$W/u1.out" \
   && [ "$(sha_of "$P/lib/foo.cyr")" = "$EXPECT" ] && [ "$s0" = "$(snap "$CU")" ]; then
    ok "U1 an UNTAGGED dep's tampered cache is refused (through 6.6.4 it skipped verification entirely and vendored the bytes)"
else bad "U1 (rc=$r, module=$(sha_of "$P/lib/foo.cyr")): $(grep -m1 -i error "$W/u1.out" || echo 'NO ERROR')"; fi

# ══ floors ═══════════════════════════════════════════════════════════════════════════════
# 16 benign (B1-B16) + 30 refusal (R1-R30) + 15 sub-axes (B13b R4b R5b R11b R15b R16b R17b
# R17c R22b R23b R27b R28b R28c R28d R30b — R18/R19 inline) + O1 + C1 + U1 + U2 = 65. DERIVED, not
# tuned: `grep -c 'ok "' ` over this file is the same 65. Counted as pass+fail+SKIPPED
# rather than as a floor below the total: a skip is bookkeeping, not a missing axis, so a
# harness that dies early can never read green by "skipping". The three skippable axes (B7
# without `unshare -r`, R17/R17b/R20 without python3, B12 on a git that does not flag the
# legacy author line) still have to be COUNTED.
TOTAL=$((pass + fail + skipped))
if [ "$TOTAL" -ne 65 ]; then
    bad "FLOOR: $TOTAL axes accounted for (65 expected: $pass passed, $fail failed, $skipped skipped) — the harness died early"
fi

echo "deps_git_cache_verified: $pass passed, $fail failed, $skipped skipped"
[ "$fail" -eq 0 ]
