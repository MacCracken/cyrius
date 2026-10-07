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
# THE FIX: cmd_deps_lock always MERGES — the fresh lines, then every inherited `commit\t` line
# whose dep NAME has no fresh line. Keyed on the name only, deliberately: not on (name, git,
# tag), or a url respelled `…/x` ↔ `…/x.git` would duplicate the line and a tag bump would
# accumulate stale pins; and not filtered to manifest-declared names, because a transitive
# dep of a gated-out dep is declared only in that dep's own manifest, which is never read
# while it is gated out.
#
# THE CRLF HALF (CBTB-05). `_dep_lock_load` and `_lock_buf_hash_lookup` were made CRLF-tolerant
# at 6.6.4/6.6.9; their two siblings were not. `_lock_commit_lookup` kept the `\r` on the TAG
# field, matched no line and returned 0 — "no pin" — so on a CRLF checkout (a plain
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
#   K8  a tag bump re-pins the dep and leaves exactly ONE line for it (no stale-pin pile-up)
#   K9  the merged lock verifies (`deps --verify`: N verified, 0 failed)
#   K10 the lock converted to CRLF: a repointed tag is still refused by name (CBTB-05 — the
#       pin lookup kept the `\r` on the TAG field, matched nothing and returned "no pin")
#   K11 `deps --verify` on that CRLF lock: N verified, 0 failed (it read `lib/x.cyr\r` and
#       failed every file "cannot hash")
#
# Mutation ledger (measured in a scratch root): the slot-open (6.6.20) CLI → every axis but
# K1 red; restoring cmd_deps_lock's `if (fresh) … else (inherited)` → K2–K11 red; carrying
# every inherited line without the name match (the fresh-line check always 0) → K2 K3 K8 red
# (a duplicate line per re-verified dep); dropping the CR strip in _lock_commit_lookup → K10
# red; dropping the one in cmd_deps_verify → K11 red. A repoint must make a NEW commit: the
# second repoint of one origin used to be an empty `git commit`, the tag never moved, and the
# CRLF axis passed nothing (caught while measuring this ledger).
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
pinset() { for _n in good opt optdep tgt ovr; do printf '%s=%s ' "$_n" "$(pin_of "$_n" | tr '\n' ',')"; done; }
NREP=0
repoint() {   # $1 = origin name: move its v1 to a NEW commit vendoring different bytes (unique
              # per call — a second repoint of one origin must not be an empty commit)
    NREP=$((NREP + 1))
    ( cd "$W/o/$1" && printf 'fn %s_f(): i64 { return %s; }\n' "$1" "$((665 + NREP))" > "dist/$1.cyr" && git commit -qam "evil $NREP" && git tag -f v1 > /dev/null 2>&1 ) \
      || bad "repoint $1: could not move v1"
}
restore() {   # $1 = origin name, $2 = the original sha: put v1 back, drop the (evil) cache entry
    git -C "$W/o/$1" tag -f v1 "$2" > /dev/null 2>&1; rm -rf "$H/deps/$1"
}
# refused <axis> <origin> <args…>: repoint, clear the cache, resolve, expect a by-name refusal
refused() {
    _ax=$1; _nm=$2; shift 2
    _sha=$(git -C "$W/o/$_nm" rev-parse 'v1^{commit}')
    cp "$P/cyrius.lock" "$W/$_ax.lock"; cp "$P/lib/$_nm.cyr" "$W/$_ax.lib"
    repoint "$_nm"; rm -rf "$H/deps/$_nm"
    _rc=0; if _cy deps "$@" > "$W/$_ax.out" 2>&1; then _rc=0; else _rc=$?; fi
    if [ "$_rc" -ne 0 ] && grep -q "commit-pin mismatch for dep '$_nm'" "$W/$_ax.out" \
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

# ── K8: a deliberate tag bump re-pins, and leaves exactly one line for the dep ───────────
( cd "$W/o/good" && printf 'fn good_f(): i64 { return 2; }\n' > dist/good.cyr && git commit -qam v2 && git tag v2 ) || bad "K8 setup: cannot tag v2"
sed -i '/^\[deps.good\]/,/^modules/ s/^tag = "v1"$/tag = "v2"/' "$P/cyrius.cyml"
good2=$(git -C "$W/o/good" rev-parse 'v2^{commit}')
rc=0; if _cy deps > "$W/k8.out" 2>&1; then rc=0; else rc=$?; fi
gl=$(tr -d '\r' < "$P/cyrius.lock" | awk -F"$TAB" '$1 == "commit" && $3 == "good"' | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$gl" -eq 1 ] && [ "$(pin_of good)" = "$good2" ] \
   && tr -d '\r' < "$P/cyrius.lock" | grep -q "^commit$TAB$good2${TAB}good$TAB.*${TAB}v2$" && [ "$(npins)" -eq 5 ]; then
    ok "K8 tag bump v1 → v2: good re-pinned to v2's commit, one line for it, the other 4 pins kept"
else bad "K8 (rc=$rc, $gl line(s) for good, pins: $(pinset)): $(grep -m2 -i 'error\|refus' "$W/k8.out")"; fi

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

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
