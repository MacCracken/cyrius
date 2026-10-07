#!/bin/sh
# deps_commit_pins_kept.sh — 6.6.20. A CVE-21 `commit\t` pin in cyrius.lock survives every
# resolve that does not re-verify its dep, so a repointed tag is still REFUSED afterwards —
# and it is still read when the lock is checked out CRLF.
#
# THE DEFECT (6.6.20 closeout audit, CBTB-01). cmd_deps resets `_dep_commit_lines` to a fresh
# vec on every run and pushes a pin only for a tagged dep it cloned and verified in THAT run;
# cmd_deps_lock wrote either those fresh lines OR (bare `--lock`, the 6.6.4 repair) the
# inherited ones — never both. So any resolve that skipped a tagged dep rewrote the lock
# without its pin, while its lib/ hash row stayed: an `optional = true` dep resolved without its
# feature, a `target =` dep on another target, every transitive dep of a gated-out dep, a dep
# served by an existing `path =` override, and every pin on a no-git (PE) host. Every
# auto-deps verb (`cyrius build`, `run`, `test`, …) is such a resolve. Measured on the 6.6.20
# slot-open CLI: `deps --features gpu` → 2 commit-pinned, plain `deps` → 1; the opt origin's
# tag repointed and its cache cleared, `deps --features gpu` then exited 0, vendored the new
# bytes and RE-PINNED to them — the first-resolve TOFU floor, reached on a routine workflow.
#
# THE FIX: cmd_deps_lock always MERGES — the fresh lines plus every inherited `commit\t` line no
# fresh line supersedes — and SORTS the block. An inherited line is superseded only by a fresh
# line with its (name, git, tag): the key `_lock_commit_lookup` reads a pin by, the git url
# normalised the same way (`…/x` = `…/x.git`), so a respelled url still replaces its line (K14).
# A different repository at the same tag does NOT: a fork's v1 line leaves the origin's v1 line
# in place, so moving back to the origin and finding its v1 repointed is refused (K17).
# NOT by the name alone. The first cut keyed on the name, and review measured the hole: in a
# diamond, a gated root `x@v2` and a required dep's own `x@v1` share the name, the feature-less
# resolve pinned x@v1 and dropped x@v2's pin, and a repointed v2 on a fresh cache was then
# vendored at exit 0 (K12). So an old tag's line now stays after a tag bump (K8) — fail-closed,
# what CVE-21 wants if the dep is moved back to that tag; deleting cyrius.lock re-pins. Not
# filtered to manifest-declared names either: a transitive dep of a gated-out dep is declared
# only in that dep's own manifest, which is never read while it is gated out (K5).
# SORTED by (name, git, tag), then the whole line: fresh-then-carried order wrote one pin set in
# an order set by which deps the run re-verified, so alternating gatings flipped the block — the
# 6.6.3 churn class for `git diff --exit-code -- cyrius.lock` (K13).
# Because an old tag's line stays, the block is no longer bounded by the dep count: the pin
# lookup reads the whole lock, as `_dep_lock_load` and `cmd_deps_verify` have since 6.6.4 (K15).
#
# THE CRLF HALF (CBTB-05). `_dep_lock_load` and `_lock_buf_hash_lookup` have been CRLF-tolerant
# since 6.6.4 (6.6.9 only factored the hash lookup into a buffer form for `--verify`); 6.6.4's
# review fixed those readers and missed their two siblings. `_lock_commit_lookup` kept the `\r`
# on the TAG field, matched no line and returned 0 — "no pin" — so on a CRLF checkout (a plain
# `git -c core.autocrlf=true clone` makes one) a repointed tag was vendored and re-pinned at
# exit 0, exactly where CVE-21 matters (fresh clone, fresh cache). `deps --verify` read each path
# up to the `\n` and failed every file "cannot hash" (fail-closed, but false).
#
# AXES (every origin is a local file:// repo — no network):
#   K1  setup: `deps --features gpu --aarch64` pins all five tagged deps (anti-vacuous floor)
#   K2  a feature-less, x86 `deps` with the override dir present keeps all five pins, same shas
#   K3  a feature-less `cyrius build` (the auto-deps path) keeps them too
#   K4  optional dep: tag repointed + fresh cache → `deps --features gpu` REFUSED, lib untouched
#   K5  transitive dep of the optional dep: same, refused by name
#   K6  target-gated dep: same under `--aarch64`, refused by name
#   K7  path-override dep: override dir removed, tag repointed → refused by name
#   K8  a tag bump v1 → v2 pins the dep at v2 and KEEPS its v1 line (no pin a lookup could
#       read is dropped); K8r: v2 repointed + fresh cache → refused by name
#   K9  the merged lock verifies (`deps --verify`: N verified, 0 failed)
#   K10 the lock converted to CRLF: a repointed tag is still refused by name (CBTB-05 — the
#       pin lookup kept the `\r` on the TAG field, matched nothing and returned "no pin")
#   K11 `deps --verify` on that CRLF lock: N verified, 0 failed (it read `lib/x.cyr\r` and
#       failed every file "cannot hash")
#   K12 diamond: optional root `dx` at v2 + required `dy`, whose own manifest declares dx at v1.
#       K12a: a feature-less `deps` pins dx@v1 and keeps the dx@v2 pin, same sha; K12b: dx's v2
#       repointed + fresh cache → `deps --features gpu` REFUSED by name, lock and lib untouched
#   K13 order: a project declaring its gated dep FIRST — `deps --features gpu`, `deps`,
#       `deps --features gpu` — leaves cyrius.lock byte-identical each time
#   K14 a respelled url (`…/good` → `…/good.git`) replaces its line: one (good, v2) line, the
#       respelled spelling, same sha, no duplicate
#   K15 1000 retained `alpha` lines put good's live v2 line past 64 KB: its repointed tag on a
#       fresh cache is still REFUSED by name (the lookup read a 64 KB window and said "no pin")
#   K16 the same lock re-resolved keeps all 1006 lines, and the summary's `N commit-pinned`
#       counts the 6 deps by name, not the lines (it printed 1006 for 6 deps)
#   K17 a fork at the same tag: fx pinned from its origin at v1, the manifest moved to a fork
#       that also tags v1 (cache cleared). K17a: the lock keeps BOTH v1 lines; K17b: moved back,
#       the origin's v1 repointed + fresh cache → REFUSED by name, lock and lib untouched
#
# Mutation ledger (measured with this file, one mutant of cbt/deps.cyr at a time; the tip is
# 20/20 green):
#   slot-open (6.6.20) CLI ............................ every axis but K1 red
#   first cut, inherited line dropped by NAME (61c88ca3) K8 K12a K12b K13 K14 K15 K16 K17a K17b
#   carry every inherited line (fresh check always 0) . K2 K3 K8 K12a K13 K14, K15 K16 knock-on
#   git field compared byte-for-byte, not normalised .. K14, K15 K16 knock-on (K14's duplicate)
#   drop key ignores git (`return 1` for the url test)  K17a K17b
#   no sort ........................................... K13 K16 (the dep count reads adjacency)
#   no CR strip in _lock_commit_lookup ................ K10
#   no CR strip in cmd_deps_verify .................... K11
#   64 KB read window in _lock_commit_lookup .......... K15
#   summary counts lines, not deps .................... K16
# "Knock-on" axes go red because an earlier axis left a duplicate line in the shared project.
# A repoint must make a NEW commit: the second repoint of one origin used to be an empty `git
# commit`, the tag never moved, and the CRLF axis passed nothing (caught while measuring).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_commit_pins_kept
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/cli.err" && [ -s "$W/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V/bin" "$H/deps" && cp -r lib "$H/versions/$V/lib" \
  && cp "$W/cyrius" "$H/versions/$V/bin/cyrius" && cp "$CC" "$H/versions/$V/bin/cycc" \
  && chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
CY="$H/versions/$V/bin/cyrius"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
TAB=$(printf '\t')

# ── origins: good (required), opt (optional, declares optdep), optdep, tgt (aarch64-only), ovr
mkorigin() {   # $1 = name, $2 = optional cyrius.cyml body
    _o="$W/o/$1"; mkdir -p "$_o/dist"
    printf 'fn %s_f(): i64 { return 1; }\n' "$1" > "$_o/dist/$1.cyr"
    [ -n "$2" ] && printf '%b' "$2" > "$_o/cyrius.cyml"
    ( cd "$_o" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || { echo "FAIL: $G: cannot build origin $1"; exit 1; }
}
mkorigin good ""
mkorigin optdep ""
mkorigin opt "[package]\nname = \"opt\"\nversion = \"1.0.0\"\nlanguage = \"cyrius\"\n\n[deps.optdep]\ngit = \"file://$W/o/optdep\"\ntag = \"v1\"\nmodules = [\"dist/optdep.cyr\"]\n"
mkorigin tgt ""
mkorigin ovr ""

P="$W/p"; mkdir -p "$P"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "pinsp"
version = "0.0.1"
language = "cyrius"
cyrius = "$V"

[build]
src = "main.cyr"
output = "out"

[features]
gpu = ["opt"]

[deps.good]
git = "file://$W/o/good"
tag = "v1"
modules = ["dist/good.cyr"]

[deps.opt]
git = "file://$W/o/opt"
tag = "v1"
modules = ["dist/opt.cyr"]
optional = true

[deps.tgt]
git = "file://$W/o/tgt"
tag = "v1"
modules = ["dist/tgt.cyr"]
target = "aarch64"

[deps.ovr]
git = "file://$W/o/ovr"
tag = "v1"
modules = ["dist/ovr.cyr"]
path = "ovr-local"
EOF
printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$P/main.cyr"

_cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CY" "$@" ); }
pin_of() { tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" -v n="$1" '$1 == "commit" && $3 == n { print $2 }'; }
npins()  { tr -d '\r' < "$P/cyrius.lock" | grep -c "^commit$TAB" || true; }
pin_at() { tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" -v n="$1" -v t="$2" '$1 == "commit" && $3 == n && $5 == t { print $2 }'; }
pinset() { for _n in good opt optdep tgt ovr; do printf '%s=%s ' "$_n" "$(pin_of "$_n" | tr '\n' ',')"; done; }
NREP=0
RTAG=v1       # the tag repoint / restore / refused move (K8r and K12b move v2)
repoint() {   # $1 = origin name: move its $RTAG to a NEW commit vendoring different bytes (unique
              # per call — a second repoint of one origin must not be an empty commit)
    NREP=$((NREP + 1))
    ( cd "$W/o/$1" && printf 'fn %s_f(): i64 { return %s; }\n' "$1" "$((665 + NREP))" > "dist/$1.cyr" && git commit -qam "evil $NREP" && git tag -f "$RTAG" > /dev/null 2>&1 ) \
      || bad "repoint $1: could not move $RTAG"
}
restore() {   # $1 = origin name, $2 = the original sha: put $RTAG back, drop the (evil) cache entry
    git -C "$W/o/$1" tag -f "$RTAG" "$2" > /dev/null 2>&1; rm -rf "$H/deps/$1"
}
# refused <axis> <origin> <args…>: repoint, clear the cache, resolve, expect a by-name refusal
refused() {
    _ax=$1; _nm=$2; shift 2
    _sha=$(git -C "$W/o/$_nm" rev-parse "$RTAG^{commit}")
    cp "$P/cyrius.lock" "$W/$_ax.lock"; cp "$P/lib/$_nm.cyr" "$W/$_ax.lib"
    repoint "$_nm"; rm -rf "$H/deps/$_nm"
    _rc=0; if _cy deps "$@" > "$W/$_ax.out" 2>&1; then _rc=0; else _rc=$?; fi
    if [ "$_rc" -ne 0 ] && grep -q "commit-pin mismatch for dep '$_nm' tag '$RTAG'" "$W/$_ax.out" \
       && cmp -s "$P/cyrius.lock" "$W/$_ax.lock" && cmp -s "$P/lib/$_nm.cyr" "$W/$_ax.lib"; then
        ok "$_ax $_nm: repointed tag + fresh cache refused by name (rc=$_rc); lock and lib/$_nm.cyr untouched"
    else bad "$_ax $_nm (rc=$_rc, pins: $(pinset)): $(grep -m2 -i 'error\|refus\|resolved' "$W/$_ax.out")"; fi
    restore "$_nm" "$_sha"
}

# ── K1: every tagged dep resolved once → five pins ──────────────────────────────────────
rc=0; if _cy deps --features gpu --aarch64 > "$W/k1.out" 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && [ "$(npins)" -eq 5 ]; then ok "K1 setup: 5 commit pins (good opt optdep tgt ovr)"
else bad "K1 setup (rc=$rc, $(npins) pins: $(pinset)): $(tail -3 "$W/k1.out")"; fi
want=$(pinset)

# ── K2: the override dir appears; a feature-less x86 resolve re-verifies only `good` ───────
mkdir -p "$P/ovr-local/dist" && printf 'fn ovr_f(): i64 { return 1; }\n' > "$P/ovr-local/dist/ovr.cyr"
rc=0; if _cy deps > "$W/k2.out" 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'cyrius.lock:' "$W/k2.out" && [ "$(npins)" -eq 5 ] && [ "$(pinset)" = "$want" ]; then
    ok "K2 feature-less, x86, override present: the lock was rewritten and kept all 5 pins unchanged"
else bad "K2 (rc=$rc, $(npins) pins: $(pinset), want $want): $(grep -m1 'cyrius.lock' "$W/k2.out")"; fi

# ── K3: the same through the auto-deps verb ──────────────────────────────────────────────
rc=0; if _cy build main.cyr ./out > "$W/k3.out" 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'cyrius.lock:' "$W/k3.out" && [ "$(npins)" -eq 5 ] && [ "$(pinset)" = "$want" ]; then
    ok "K3 feature-less \`cyrius build\` (auto-deps): all 5 pins kept"
else bad "K3 (rc=$rc, $(npins) pins: $(pinset)): $(grep -m2 -i 'error\|cyrius.lock' "$W/k3.out")"; fi

# ── K4–K7: each kept pin still refuses a repointed tag ───────────────────────────────────
refused K4 opt --features gpu
refused K5 optdep --features gpu
refused K6 tgt --aarch64
rm -rf "$P/ovr-local"
refused K7 ovr

# ── K8: a deliberate tag bump pins the new tag and KEEPS the old tag's line ─────────────
#    The merge drops an inherited line only for a fresh one with its (name, git, tag), so the
#    v1 pin stays: fail-closed if the dep is ever moved back to a repointed v1.
good1=$(pin_of good)
( cd "$W/o/good" && printf 'fn good_f(): i64 { return 2; }\n' > dist/good.cyr && git commit -qam v2 && git tag v2 ) || bad "K8 setup: cannot tag v2"
sed -i '/^\[deps.good\]/,/^modules/ s/^tag = "v1"$/tag = "v2"/' "$P/cyrius.cyml"
good2=$(git -C "$W/o/good" rev-parse 'v2^{commit}')
rc=0; if _cy deps > "$W/k8.out" 2>&1; then rc=0; else rc=$?; fi
gl=$(tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" '$1 == "commit" && $3 == "good"' | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$gl" -eq 2 ] && [ "$(pin_at good v2)" = "$good2" ] && [ -n "$good1" ] \
   && [ "$(pin_at good v1)" = "$good1" ] && [ "$(npins)" -eq 6 ]; then
    ok "K8 tag bump v1 → v2: good pinned at v2's commit, its v1 line kept, the other 4 pins kept"
else bad "K8 (rc=$rc, $gl line(s) for good, pins: $(pinset)): $(grep -m2 -i 'error\|refus' "$W/k8.out")"; fi
RTAG=v2; refused K8r good; RTAG=v1

# ── K9: the merged lock is a valid lock ─────────────────────────────────────────────────
rc=0; if _cy deps --verify > "$W/k9.out" 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -qE '[1-9][0-9]* verified, 0 failed' "$W/k9.out"; then ok "K9 the merged lock verifies: $(tail -1 "$W/k9.out")"
else bad "K9 (rc=$rc): $(tail -2 "$W/k9.out")"; fi

# ── K10/K11: a CRLF checkout of the lock (`git -c core.autocrlf=true clone` makes one) ────
#    K10: the pin is still READ — a repointed tag is refused, not TOFU-re-pinned (CBTB-05)
#    K11: `deps --verify` reads each path without its `\r` (it failed every file "cannot hash")
sed -i 's/$/\r/' "$P/cyrius.lock"
ncr=$(tr -cd '\r' < "$P/cyrius.lock" | wc -c | tr -d ' ')
[ "$ncr" -ge 7 ] || bad "K10 setup: the lock is not CRLF ($ncr CRs)"
refused K10-crlf opt --features gpu
# K11 re-applies the CRLF form itself, so it does not depend on K10 having left it
tr -d '\r' < "$P/cyrius.lock" | sed 's/$/\r/' > "$W/k11.lock" && cp "$W/k11.lock" "$P/cyrius.lock"
ncr=$(tr -cd '\r' < "$P/cyrius.lock" | wc -c | tr -d ' ')
rc=0; if _cy deps --verify > "$W/k11.out" 2>&1; then rc=0; else rc=$?; fi
ncr2=$(tr -cd '\r' < "$P/cyrius.lock" | wc -c | tr -d ' ')
if [ "$rc" -eq 0 ] && grep -qE '[1-9][0-9]* verified, 0 failed' "$W/k11.out" && [ "$ncr2" = "$ncr" ]; then
    ok "K11 CRLF lock: --verify reads it ($(tail -1 "$W/k11.out")), lock left CRLF"
else bad "K11 (rc=$rc): $(head -2 "$W/k11.out" | tr '\r' '~') … $(tail -1 "$W/k11.out")"; fi

# ── K12: a diamond — the gated root declaration and a required dep's own share the NAME ───
#    dx is an optional root dep at v2; dy (required) declares dx at v1 in its own manifest. A
#    skipped optional dep is not marked visited, so the feature-less resolve pins dx@v1 in its
#    place — and a name-keyed merge dropped the dx@v2 pin `deps --features gpu` reads.
mkorigin dx ""
( cd "$W/o/dx" && printf 'fn dx_f(): i64 { return 2; }\n' > dist/dx.cyr && git commit -qam v2 && git tag v2 ) || bad "K12 setup: cannot tag dx v2"
mkorigin dy "[package]\nname = \"dy\"\nversion = \"1.0.0\"\nlanguage = \"cyrius\"\n\n[deps.dx]\ngit = \"file://$W/o/dx\"\ntag = \"v1\"\nmodules = [\"dist/dx.cyr\"]\n"
dx1=$(git -C "$W/o/dx" rev-parse 'v1^{commit}'); dx2=$(git -C "$W/o/dx" rev-parse 'v2^{commit}')
P0=$P; P="$W/p2"; mkdir -p "$P"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "pinsd"
version = "0.0.1"
language = "cyrius"
cyrius = "$V"

[build]
src = "main.cyr"
output = "out"

[features]
gpu = ["dx"]

[deps.dx]
git = "file://$W/o/dx"
tag = "v2"
modules = ["dist/dx.cyr"]
optional = true

[deps.dy]
git = "file://$W/o/dy"
tag = "v1"
modules = ["dist/dy.cyr"]
EOF
cp "$P0/main.cyr" "$P/main.cyr"
rc=0; if _cy deps --features gpu > "$W/k12.out" 2>&1; then rc=0; else rc=$?; fi
[ "$rc" -eq 0 ] && [ "$(pin_at dx v2)" = "$dx2" ] && [ -n "$(pin_of dy)" ] \
  || bad "K12 setup (rc=$rc): dx@v2 + dy not pinned: $(tr -d '\r' < "$P/cyrius.lock" | grep "^commit" | cut -f3,5 | tr '\n' ' ') $(grep -m2 -i 'error\|refus' "$W/k12.out")"
rc=0; if _cy deps > "$W/k12a.out" 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && [ "$(pin_at dx v2)" = "$dx2" ] && [ "$(pin_at dx v1)" = "$dx1" ] && [ "$(npins)" -eq 3 ]; then
    ok "K12a diamond: a feature-less resolve pinned dy's dx@v1 and KEPT the root's dx@v2 pin"
else bad "K12a (rc=$rc, $(npins) pins: $(tr -d '\r' < "$P/cyrius.lock" | grep "^commit" | cut -f3,5 | tr '\n' ' ')): $(grep -m2 -i 'error\|refus' "$W/k12a.out")"; fi
RTAG=v2; refused K12b dx --features gpu; RTAG=v1

# ── K13: the commit block's order is a function of the pin SET, not of the gating ──────────
#    The gated dep is declared FIRST: fresh-then-carried order wrote opt-first under
#    `--features gpu` and good-first without it, so alternating gatings flipped the block.
P="$W/p3"; mkdir -p "$P"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "pinso"
version = "0.0.1"
language = "cyrius"
cyrius = "$V"

[build]
src = "main.cyr"
output = "out"

[features]
gpu = ["opt"]

[deps.opt]
git = "file://$W/o/opt"
tag = "v1"
modules = ["dist/opt.cyr"]
optional = true

[deps.good]
git = "file://$W/o/good"
tag = "v1"
modules = ["dist/good.cyr"]
EOF
cp "$P0/main.cyr" "$P/main.cyr"
r1=0; _cy deps --features gpu > "$W/k13a.out" 2>&1 || r1=$?; cp "$P/cyrius.lock" "$W/k13.l1" 2>/dev/null || :
r2=0; _cy deps > "$W/k13b.out" 2>&1 || r2=$?; cp "$P/cyrius.lock" "$W/k13.l2" 2>/dev/null || :
r3=0; _cy deps --features gpu > "$W/k13c.out" 2>&1 || r3=$?; cp "$P/cyrius.lock" "$W/k13.l3" 2>/dev/null || :
if [ "$r1$r2$r3" = "000" ] && [ "$(npins)" -eq 3 ] && cmp -s "$W/k13.l1" "$W/k13.l2" && cmp -s "$W/k13.l1" "$W/k13.l3"; then
    ok "K13 gated dep declared first: --features gpu / plain / --features gpu leave cyrius.lock byte-identical (3 pins)"
else bad "K13 (rc=$r1/$r2/$r3, $(npins) pins): gpu $(grep "^commit" "$W/k13.l1" | cut -f3 | tr '\n' ' ')| plain $(grep "^commit" "$W/k13.l2" | cut -f3 | tr '\n' ' ')| gpu $(grep "^commit" "$W/k13.l3" | cut -f3 | tr '\n' ' ')"; fi

# ── K14: a respelled url replaces its line (the drop key normalises git as the lookup does) ──
P=$P0
ln -s good "$W/o/good.git" || bad "K14 setup: cannot link good.git"
sed -i "s|^git = \"file://$W/o/good\"\$|git = \"file://$W/o/good.git\"|" "$P/cyrius.cyml"
grep -q "o/good.git\"" "$P/cyrius.cyml" || bad "K14 setup: the url was not respelled"
rc=0; if _cy deps > "$W/k14.out" 2>&1; then rc=0; else rc=$?; fi
g2=$(tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" '$1 == "commit" && $3 == "good" && $5 == "v2"')
if [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$g2" | grep -c .)" -eq 1 ] && [ "$(pin_at good v2)" = "$good2" ] \
   && printf '%s' "$g2" | grep -q "o/good.git${TAB}v2$" && [ "$(npins)" -eq 6 ]; then
    ok "K14 url respelled …/good → …/good.git: one (good, v2) line, the new spelling, same sha"
else bad "K14 (rc=$rc, $(npins) pins): $(printf '%s' "$g2" | cut -f4,5 | tr '\n' ' ') $(grep -m2 -i 'error\|refus' "$W/k14.out")"; fi

# ── K15: a pin past 64 KB is still READ ─────────────────────────────────────────────────
#    The merge keeps an old tag's line after every bump, so the commit block grows with the
#    project's history. 1000 retained lines of a dep `alpha` (sorting before `good`, as the
#    sorted block puts them) carry good's live v2 line past 64 KB; a lookup that read a 64 KB
#    window returned "no pin" and TOFU-re-pinned the repointed tag at exit 0.
awk -v u="file://$W/o/alpha" 'BEGIN { for (i = 1; i <= 1000; i++) printf "commit\t%040d\talpha\t%s\tv%d\n", i, u, i }' > "$W/k15.pins"
cat "$W/k15.pins" "$P/cyrius.lock" > "$W/k15.lock" && cp "$W/k15.lock" "$P/cyrius.lock"
goff=$(grep -b "^commit${TAB}[0-9a-f]*${TAB}good${TAB}[^${TAB}]*${TAB}v2\$" "$P/cyrius.lock" | cut -d: -f1)
[ -n "$goff" ] && [ "$goff" -gt 65536 ] || bad "K15 setup: good's v2 line is at byte ${goff:-none}, not past 64 KB"
RTAG=v2; refused K15 good; RTAG=v1

# ── K16: the summary counts pinned DEPS, not lines ──────────────────────────────────────
#    The same lock re-resolved: every retained line is kept, and `N commit-pinned` names the
#    six deps (alpha good opt optdep ovr tgt), not the 1006 lines it printed before.
rc=0; if _cy deps > "$W/k16.out" 2>&1; then rc=0; else rc=$?; fi
na=$(tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" '$1 == "commit" && $3 == "alpha"' | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$na" -eq 1000 ] && [ "$(npins)" -eq 1006 ] && grep -q '^cyrius.lock: .*, 6 commit-pinned$' "$W/k16.out"; then
    ok "K16 1006 pin lines kept, the summary says 6 commit-pinned (deps, not lines)"
else bad "K16 (rc=$rc, $na alpha lines, $(npins) pins): $(grep -m1 'cyrius.lock' "$W/k16.out")"; fi

# ── K17: the drop key includes GIT — a fork at the same tag keeps the origin's line ─────────
#    fx is pinned from its origin at v1, then the manifest moves to a fork that also tags v1
#    (cache cleared) and back. A drop key of (name, tag) alone let the fork's fresh line
#    replace the origin's, and a repointed origin v1 was then vendored and re-pinned at exit 0.
mkorigin fx ""
mkdir -p "$W/fork/fx/dist" && printf 'fn fx_f(): i64 { return 7; }\n' > "$W/fork/fx/dist/fx.cyr" \
  && ( cd "$W/fork/fx" && git init -q . && git add -A && git commit -qm fork && git tag v1 ) || bad "K17 setup: cannot build the fork"
fxa=$(git -C "$W/o/fx" rev-parse 'v1^{commit}'); fxb=$(git -C "$W/fork/fx" rev-parse 'v1^{commit}')
P="$W/p5"; mkdir -p "$P"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "pinsf"
version = "0.0.1"
language = "cyrius"
cyrius = "$V"

[build]
src = "main.cyr"
output = "out"

[deps.fx]
git = "file://$W/o/fx"
tag = "v1"
modules = ["dist/fx.cyr"]
EOF
cp "$P0/main.cyr" "$P/main.cyr"
pin_git() { tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" -v n="$1" -v g="$2" -v t="$3" '$1 == "commit" && $3 == n && $4 == g && $5 == t { print $2 }'; }
rc=0; if _cy deps > "$W/k17.out" 2>&1; then rc=0; else rc=$?; fi
[ "$rc" -eq 0 ] && [ "$(pin_git fx "file://$W/o/fx" v1)" = "$fxa" ] || bad "K17 setup (rc=$rc): fx not pinned from its origin: $(grep -m2 -i 'error\|refus' "$W/k17.out")"
sed -i "s|^git = \"file://$W/o/fx\"\$|git = \"file://$W/fork/fx\"|" "$P/cyrius.cyml"; rm -rf "$H/deps/fx"
rc=0; if _cy deps > "$W/k17a.out" 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && [ "$(pin_git fx "file://$W/o/fx" v1)" = "$fxa" ] && [ "$(pin_git fx "file://$W/fork/fx" v1)" = "$fxb" ] && [ "$(npins)" -eq 2 ]; then
    ok "K17a fork at the same tag: pinned the fork's v1 and KEPT the origin's v1 line"
else bad "K17a (rc=$rc, $(npins) pins: $(tr -d '\r' < "$P/cyrius.lock" | grep "^commit" | cut -f3,4,5 | tr '\n' ' ')): $(grep -m2 -i 'error\|refus' "$W/k17a.out")"; fi
sed -i "s|^git = \"file://$W/fork/fx\"\$|git = \"file://$W/o/fx\"|" "$P/cyrius.cyml"
grep -q "o/fx\"" "$P/cyrius.cyml" || bad "K17 setup: the url was not switched back"
refused K17b fx

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
