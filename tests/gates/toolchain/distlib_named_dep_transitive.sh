#!/bin/sh
# distlib_named_dep_transitive.sh — 6.7.12. `cyrius distlib`'s sidecar verify credits a symbol to a
# named dep when its defining leaf is in the include CLOSURE of the dep's sidecar leaves, not only
# when it is one of the listed leaves (issues/2026-10-12-distlib-records-a-named-deps-transitive-
# leaf-as-the-bundles-own.md).
#
# THE DEFECT (anuenue 1.4.0, filed 2026-10-12). agnostik's sidecar lists `tagged`; its module calls
# `tagged_new`, which lives in boxed.cyr — tagged.cyr's own `include "lib/boxed.cyr"` brings it,
# and `cyrius deps` vendors boxed for agnostik. The verify matched the owner against the LISTED
# leaves only, so `boxed` was recorded as the bundle's own need: a pure module (it calls nothing)
# published `dist/dla.deps` = `boxed`.
#
# THE FIX: the closure (`_distlib_nd_closure`, the resolver's own include rule
# `_dep_stdlib_inc_names` over the pinned snapshot) counts as the dep's, exactly as a listed leaf
# does: the leaf enters the unit's scope and is not recorded. The bundle's OWN use of such a leaf
# is still recorded — as it already is for a listed leaf (D3: a module calling `is_none`, from the
# listed `tagged`, records `tagged`). ⚠ The 6.7.12 brief's row for D2 expected "no record" for a
# module that itself calls `tagged_new`; that would treat a closure leaf differently from a listed
# one (D3, measured on 6.7.11 and unchanged), so D2 asserts the one rule: `boxed` recorded.
#
# ROWS (a local file:// stand-in named dep `sd`: dist/sd.cyr calls the named symbols, its sidecar
# dist/sd.deps lists `tagged`; the bundle's module is src/a.cyr)
#   D1  the filed repro: a pure module — `boxed in scope (a named dep's)`, nothing recorded, no
#       sidecar written (no stdlib leaves); a stale dist/dla.deps reading `boxed` (anuenue's
#       committed one) is removed
#   D2  a module that itself calls tagged_new: `boxed` recorded (the bundle's own need)
#   D3  a module that itself calls is_none (the listed leaf tagged): `tagged` recorded (anchor)
#   D4  two includes deep: sd calls vec_new (tagged → result → fmt → vec): in scope, no sidecar
#   D5  anti-vacuous: sd's sidecar removed (it lists nothing) — its tagged_new is recorded as
#       `boxed`, so D1's silence is the closure's doing, not a blind pass
#   K1-K4 (6.7.13) a named dep `nd` with no sidecar whose manifest selects a thin profile of a leaf the
#       bundle declares, so `cyrius deps` keeps the fold (6.6.11 S2): the fold is nd's need — K1 a
#       `modules` profile (dist/ct-thin.cyr) and K2 a `modular` one (lib/ct_thin.cyr): `ct in scope
#       (a named dep's)`, nothing recorded, no sidecar for a pure module; K3 what the fold includes
#       (tagged -> boxed) likewise; K4 anti-vacuous: the bundle's own ct_eq_bytes records ct
# Mutation (measured): the two closure arms removed (the list-only match of 6.7.11) → D1 D3 D4
# RED; the closure built without following includes (the listed leaves alone) → D1 D3 D4 RED;
# 6.7.11's CLI → D1 D3 D4 RED (D2 and D5 hold on it: the rule they anchor is unchanged).
# 6.7.13: no `_dep_note_nd_leaf` in the module loop's kept-fold branch → K1 K3 K4 RED (ct / boxed
# recorded; K4's ct recorded for nd's ct_eq_bytes_lens, not the bundle's ct_eq_bytes); none in
# `_dep_pull_submodule`'s → K2 RED; the CLI before the fix → K1-K4 RED.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=distlib_named_dep_transitive
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found (the named dep is a file:// origin)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

# The sidecar verify compiles for every target: cycc and cycc_aarch64 beside the CLI.
mkdir -p "$W/bin"
if [ -n "${CYRIUS_BIN:-}" ]; then cp "$CYRIUS_BIN" "$W/bin/cyrius"
else "$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
fi
cp "$CC" "$W/bin/cycc" && "$CC" < src/main_aarch64.cyr > "$W/bin/cycc_aarch64" 2> /dev/null \
  && chmod +x "$W/bin/cyrius" "$W/bin/cycc" "$W/bin/cycc_aarch64" \
  || { echo "SKIP: $G: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V" && cp -r lib "$H/versions/$V/lib" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# _origin <tag> <sd.cyr body> <sidecar text or "-" for none>: a new commit + tag of the sd origin
O="$W/o/sd"
mkdir -p "$O/dist" && ( cd "$O" && git init -q . ) || { echo "FAIL: $G: cannot create the sd origin"; exit 1; }
_origin() {
    printf '%s\n' "$2" > "$O/dist/sd.cyr"
    if [ "$3" = "-" ]; then rm -f "$O/dist/sd.deps"; else printf '%s\n' "$3" > "$O/dist/sd.deps"; fi
    ( cd "$O" && git add -A && git commit -qm "$1" && git tag "$1" ) || bad "setup: cannot tag sd $1"
}
P="$W/p"
# _proj <sd tag> <src/a.cyr body>
_proj() {
    rm -rf "$P"; mkdir -p "$P/src"
    printf '[package]\nname = "dla"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "main.cyr"\noutput = "build/m"\n\n[lib]\nmodules = ["src/a.cyr"]\n\n[deps]\nstdlib = ["syscalls"]\n\n[deps.sd]\ngit = "file://%s"\ntag = "%s"\nmodules = ["dist/sd.cyr"]\n' "$V" "$O" "$1" > "$P/cyrius.cyml"
    printf '%s\n' "$2" > "$P/src/a.cyr"
    printf 'include "src/a.cyr"\nsyscall(SYS_EXIT, 0);\n' > "$P/main.cyr"
}
_cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$W/bin/cyrius" "$@" ); }
_dl() {   # deps, then distlib -v; output in $W/$1.out, the sidecar's leaves (or NONE) in $W/$1.sc
    _cy deps > "$W/$1.deps" 2>&1 || bad "$1 setup: deps failed: $(tail -2 "$W/$1.deps")"
    rc=0; _cy distlib -v > "$W/$1.out" 2>&1 || rc=$?
    if [ -f "$P/dist/dla.deps" ]; then grep -v '^#' "$P/dist/dla.deps" | grep . | tr '\n' ' ' | sed 's/ $//' > "$W/$1.sc"
    else printf 'NONE' > "$W/$1.sc"; fi
}

PURE='# pure
fn pure_add(a, b): i64 { return a + b; }'

# ── D1: the filed repro ──────────────────────────────────────────────────────────────────────
_origin v1 'fn sd_make(v): i64 { return tagged_new(1, v); }' '# sd sidecar
tagged'
_proj v1 "$PURE"
mkdir -p "$P/dist" && printf '# stale (anuenue 1.4.0 committed this)\nboxed\n' > "$P/dist/dla.deps"
_dl d1
if [ "$rc" -eq 0 ] && grep -q "boxed in scope (a named dep's) for 'tagged_new'" "$W/d1.out" && ! grep -q ' recorded for ' "$W/d1.out" \
   && [ "$(cat "$W/d1.sc")" = "NONE" ] && grep -q 'sidecar: removed .*dla.deps (no stdlib leaves remain)' "$W/d1.out"; then
    ok "D1 a pure module: boxed in scope (sd's), nothing recorded, the stale 'boxed' sidecar removed"
else bad "D1 (rc=$rc, sidecar: $(cat "$W/d1.sc")): $(grep -E "recorded|named dep's|error" "$W/d1.out" | head -2)"; fi

# ── D2: the bundle's own call into a closure leaf is recorded ────────────────────────────────
_proj v1 'fn own_b(x): i64 { return tagged_new(1, x); }'
_dl d2
if [ "$rc" -eq 0 ] && [ "$(cat "$W/d2.sc")" = "boxed" ] && grep -q "boxed recorded for 'tagged_new'" "$W/d2.out"; then
    ok "D2 a module that itself calls tagged_new: boxed recorded (its own need)"
else bad "D2 (rc=$rc, sidecar: $(cat "$W/d2.sc")): $(grep -E "recorded|named dep's|error" "$W/d2.out" | head -2)"; fi

# ── D3: the listed-leaf rule, unchanged ──────────────────────────────────────────────────────
_proj v1 'fn own_t(x): i64 { return is_none(x); }'
_dl d3
if [ "$rc" -eq 0 ] && [ "$(cat "$W/d3.sc")" = "tagged" ] && grep -q "boxed in scope (a named dep's) for 'tagged_new'" "$W/d3.out"; then
    ok "D3 a module that itself calls is_none (the listed tagged): tagged recorded; sd's tagged_new stays sd's"
else bad "D3 (rc=$rc, sidecar: $(cat "$W/d3.sc")): $(grep -E "recorded|named dep's|error" "$W/d3.out" | head -2)"; fi

# ── D4: three includes deep ──────────────────────────────────────────────────────────────────
_origin v2 'fn sd_list(): i64 { return vec_new(); }' '# sd sidecar
tagged'
_proj v2 "$PURE"
_dl d4
if [ "$rc" -eq 0 ] && grep -q "vec in scope (a named dep's) for 'vec_new'" "$W/d4.out" && ! grep -q ' recorded for ' "$W/d4.out" \
   && [ "$(cat "$W/d4.sc")" = "NONE" ]; then
    ok "D4 sd calls vec_new (tagged -> result -> fmt -> vec): in scope, nothing recorded"
else bad "D4 (rc=$rc, sidecar: $(cat "$W/d4.sc")): $(grep -E "recorded|named dep's|error" "$W/d4.out" | head -2)"; fi

# ── D5: anti-vacuous — a dep whose sidecar lists nothing ─────────────────────────────────────
_origin v3 'fn sd_make(v): i64 { return tagged_new(1, v); }' '-'
_proj v3 "$PURE"
_dl d5
if [ "$rc" -eq 0 ] && [ "$(cat "$W/d5.sc")" = "boxed" ] && grep -q "boxed recorded for 'tagged_new'" "$W/d5.out"; then
    ok "D5 sd with no sidecar: its tagged_new is recorded as boxed (the closure is anchored to sd's listed leaves)"
else bad "D5 (rc=$rc, sidecar: $(cat "$W/d5.sc")): $(grep -E "recorded|named dep's|error" "$W/d5.out" | head -2)"; fi

# ── K: a named dep whose thin profile of a leaf the bundle declares was not vendored (6.7.13) ──
# issues/archived/2026-10-15-bote-distlib-kept-fold-over-thin-profile-records-named-deps-need.md. `nd`'s
# manifest selects a thin `[deps.<L>]` profile; the bundle declares <L> in `[deps] stdlib`, so
# `cyrius deps` keeps the fold (6.6.11 S2: "'<L>' is a stdlib leaf here") and the fold stands in
# for the profile. nd's sidecar lists nothing (its profile's requires block carried its needs), so
# the fold was nd's need that nobody recorded as nd's: the verify recorded it as the bundle's own.
_thin() {   # <name> <file path under the origin> <tag>: a tagged origin holding one thin module
    _t="$W/o/$1"; mkdir -p "$(dirname "$_t/$2")" && printf 'fn %s_thin(): i64 { return 1; }\n' "$1" > "$_t/$2" \
      && ( cd "$_t" && git init -q . 2> /dev/null; git add -A && git commit -qm "$3" && git tag "$3" ) || bad "setup: cannot tag $1 $3"
}
_thin ctthin dist/ct-thin.cyr v1
_thin ctthin2 dist/ct/thin.cyr v2   # another tag: the cache keys a clone by (name, tag)
_thin tagthin dist/tagged-thin.cyr v1
ND="$W/o/nd"
mkdir -p "$ND/dist" && ( cd "$ND" && git init -q . ) || { echo "FAIL: $G: cannot create the nd origin"; exit 1; }
_ndtag() {   # <tag> <nd.cyr body> <nd's [deps.X] table>: nd has no sidecar
    printf '%s\n' "$2" > "$ND/dist/nd.cyr"
    printf '[package]\nname = "nd"\nversion = "0.1.0"\n\n%s\n' "$3" > "$ND/cyrius.cyml"
    ( cd "$ND" && git add -A && git commit -qm "$1" && git tag "$1" ) || bad "setup: cannot tag nd $1"
}
_ndtag k1 'fn nd_eq(a, b): i64 { return ct_eq_bytes_lens(a, 1, b, 1); }' "$(printf '[deps.ct]\ngit = "file://%s/o/ctthin"\ntag = "v1"\nmodules = ["dist/ct-thin.cyr"]' "$W")"
_ndtag k2 'fn nd_eq(a, b): i64 { return ct_eq_bytes_lens(a, 1, b, 1); }' "$(printf '[deps.ct]\ngit = "file://%s/o/ctthin2"\ntag = "v2"\nmodular = ["thin"]' "$W")"
_ndtag k3 'fn nd_make(v): i64 { return tagged_new(1, v); }' "$(printf '[deps.tagged]\ngit = "file://%s/o/tagthin"\ntag = "v1"\nmodules = ["dist/tagged-thin.cyr"]' "$W")"
_projk() {   # <nd tag> <the bundle's stdlib leaf> <src/a.cyr body>
    rm -rf "$P"; mkdir -p "$P/src"
    printf '[package]\nname = "dla"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "main.cyr"\noutput = "build/m"\n\n[lib]\nmodules = ["src/a.cyr"]\n\n[deps]\nstdlib = ["syscalls", "%s"]\n\n[deps.nd]\ngit = "file://%s"\ntag = "%s"\nmodules = ["dist/nd.cyr"]\n' "$V" "$2" "$ND" "$1" > "$P/cyrius.cyml"
    printf '%s\n' "$3" > "$P/src/a.cyr"
    printf 'include "src/a.cyr"\nsyscall(SYS_EXIT, 0);\n' > "$P/main.cyr"
}
# K1: the filed shape (bote / libro / sigil, synthetic): nd's module calls ct_eq_bytes_lens, its thin
#     `[deps.ct] modules = ["dist/ct-thin.cyr"]` is not vendored — a pure module's sidecar is EMPTY
_projk k1 ct "$PURE"
_dl k1
if [ "$rc" -eq 0 ] && grep -q "^note: \[deps.ct\] dist/ct-thin.cyr not vendored — 'ct' is a stdlib leaf here" "$W/k1.deps" \
   && grep -q "ct in scope (a named dep's) for 'ct_eq_bytes_lens'" "$W/k1.out" && ! grep -q ' recorded for ' "$W/k1.out" \
   && [ "$(cat "$W/k1.sc")" = "NONE" ]; then
    ok "K1 the fold kept over nd's thin ct profile is nd's: ct in scope (nd's), nothing recorded, no sidecar"
else bad "K1 (rc=$rc, sidecar: $(cat "$W/k1.sc")): $(grep -E "recorded|named dep's|error" "$W/k1.out" | head -2)"; fi
# K2: the same through a MODULAR sub-module (`modular = ["thin"]`, lib/ct_thin.cyr)
_projk k2 ct "$PURE"
_dl k2
if [ "$rc" -eq 0 ] && grep -q "^note: \[deps.ct\] thin not vendored — 'ct' is a stdlib leaf here" "$W/k2.deps" \
   && grep -q "ct in scope (a named dep's) for 'ct_eq_bytes_lens'" "$W/k2.out" && ! grep -q ' recorded for ' "$W/k2.out" \
   && [ "$(cat "$W/k2.sc")" = "NONE" ]; then
    ok "K2 a modular thin sub-module of ct kept as the fold: ct in scope (nd's), nothing recorded, no sidecar"
else bad "K2 (rc=$rc, sidecar: $(cat "$W/k2.sc")): $(grep -m1 'note' "$W/k2.deps") / $(grep -E "recorded|named dep's|error" "$W/k2.out" | head -2)"; fi
# K3: what the kept fold INCLUDES is nd's too: nd calls tagged_new (boxed.cyr, which tagged.cyr includes)
_projk k3 tagged "$PURE"
_dl k3
if [ "$rc" -eq 0 ] && grep -q "boxed in scope (a named dep's) for 'tagged_new'" "$W/k3.out" && ! grep -q ' recorded for ' "$W/k3.out" \
   && [ "$(cat "$W/k3.sc")" = "NONE" ]; then
    ok "K3 a leaf the kept fold includes (tagged -> boxed) is nd's: in scope, nothing recorded, no sidecar"
else bad "K3 (rc=$rc, sidecar: $(cat "$W/k3.sc")): $(grep -E "recorded|named dep's|error" "$W/k3.out" | head -2)"; fi
# K4: anti-vacuous — the bundle's OWN call into the kept leaf is still recorded
_projk k1 ct 'fn own_eq(a, b): i64 { return ct_eq_bytes(a, b, 1); }'
_dl k4
if [ "$rc" -eq 0 ] && [ "$(cat "$W/k4.sc")" = "ct" ] && grep -q "ct recorded for 'ct_eq_bytes'" "$W/k4.out"; then
    ok "K4 a module that itself calls ct_eq_bytes: ct recorded (its own need)"
else bad "K4 (rc=$rc, sidecar: $(cat "$W/k4.sc")): $(grep -E "recorded|named dep's|error" "$W/k4.out" | head -2)"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
