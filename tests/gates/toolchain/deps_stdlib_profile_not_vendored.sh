#!/bin/sh
# Gate: a named dep's THIN PROFILE of a package the consumer declares as a stdlib leaf is not
# vendored and not auto-included — the fold is the package, and the build succeeds on it alone
# (6.6.11, S2).
#
# THE DEFECT. bote declares the stdlib leaf `sigil` (the monolith fold) and depends on libro,
# whose `[deps.sigil]` is the thin `dist/sigil-mldsa.cyr` plus `src/{sha_ni,sha256,hex}.cyr`.
# The resolver vendored both into one unit — `_dep_refuse_stdlib_clobber` only caught an
# artifact named exactly `lib/sigil.cyr` — so the build carried 233 `duplicate fn` warnings
# while the two sigil versions matched, and FAILED (compiler exit 1, five arity errors) once the
# 6.6.10 fold moved to 3.13.4 while libro's thin profile stayed at 3.12.18.
#
# The fixture is libro-shaped and BUILDS (a resolve alone would not catch the second half — a
# file dropped from the vendor step but left in the auto-include list is a missing include):
#   thinsig/  package "sigil": dist/sigil-mldsa.cyr + src/hexz.cyr; the profile redefines the
#             fold's `sha256_bsig0` with a DIFFERENT ARITY (and a 0 result), as 3.12.18 vs
#             3.13.4 did
#   librox/   depends on [deps.sigil] = thinsig's two modules; dist/librox.cyr calls the fold's
#             `sha256_bsig0(1)` with the fold's arity (non-zero only from the fold)
#   consumer/ declares stdlib `sigil` (+ libro's stdlib list) and [deps.librox]
# Axes:
#   1. `cyrius deps` succeeds, names the kept fold, and vendors neither profile file
#      (lib/sigil-mldsa.cyr, lib/sigil_hexz.cyr); lib/sigil.cyr is the snapshot's.
#   2. `cyrius build` succeeds: no `duplicate fn`, no missing include, and the program runs.
#   3. a stale lib/sigil-mldsa.cyr from an earlier resolution is removed, not locked.
#   4. ANTI-VACUOUS: with `sigil` NOT declared as a stdlib leaf, the thin profile IS vendored.
# Exit 77 when it could not run (no compiler, no CLI, no stdlib to stage).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
CY=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
VER=$(cat "$ROOT/VERSION")
[ -x "$CC" ] || { echo "SKIP: deps_stdlib_profile_not_vendored: no compiler at $CC"; exit 77; }
[ -x "$CY" ] || { echo "SKIP: deps_stdlib_profile_not_vendored: no CLI at $CY"; exit 77; }
[ -f "$ROOT/lib/sigil.cyr" ] || { echo "SKIP: deps_stdlib_profile_not_vendored: no lib/sigil.cyr in the tree"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: deps_stdlib_profile_not_vendored: mktemp -d failed"; exit 1; }
trap 'rm -rf "$W"' EXIT
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# A hermetic home: the tree's lib/ as the pinned snapshot, and the CLI beside its compiler.
mkdir -p "$W/home/versions/$VER" "$W/home/bin"
cp -R "$ROOT/lib" "$W/home/versions/$VER/lib" && cp "$CY" "$W/home/bin/cyrius" && cp "$CC" "$W/home/bin/cycc" \
    && chmod +x "$W/home/bin/cyrius" "$W/home/bin/cycc" \
    || { echo "SKIP: deps_stdlib_profile_not_vendored: could not stage the hermetic home"; exit 77; }
CLI="$W/home/bin/cyrius"

mkdir -p "$W/thinsig/dist" "$W/thinsig/src" "$W/librox/dist" "$W/consumer/src"
printf '[package]\nname = "sigil"\nversion = "3.12.18"\n' > "$W/thinsig/cyrius.cyml"
printf '# thin profile (an older sigil)\nfn sha256_bsig0(a, b, c): i64 { return 0; }\n' > "$W/thinsig/dist/sigil-mldsa.cyr"
printf 'fn thin_hexz(x): i64 { return x; }\n' > "$W/thinsig/src/hexz.cyr"
cat > "$W/librox/cyrius.cyml" <<EOF
[package]
name = "librox"
version = "1.0.0"

[deps.sigil]
path = "../thinsig"
modules = ["dist/sigil-mldsa.cyr", "src/hexz.cyr"]
EOF
printf 'fn librox_do(): i64 { return sha256_bsig0(1); }\n' > "$W/librox/dist/librox.cyr"
# bote's own stdlib list up to sigil — what the sigil fold needs in scope.
LEAVES='"string", "fmt", "alloc", "vec", "str", "slice", "syscalls", "io", "args", "assert", "hashmap", "bayan", "fnptr", "chrono", "tagged", "freelist", "thread", "atomic", "sync", "thread_local", "sakshi", "ct", "keccak", "random"'
mkcons() {  # mkcons <with-sigil-leaf: yes|no>
    if [ "$1" = yes ]; then ST="$LEAVES, \"sigil\""; else ST="$LEAVES"; fi
    cat > "$W/consumer/cyrius.cyml" <<EOF
[package]
name = "consumer"
version = "0.1.0"
cyrius = "$VER"

[deps]
stdlib = [$ST]

[deps.librox]
path = "../librox"
modules = ["dist/librox.cyr"]
EOF
}
printf 'fn main(): i64 {\n    var r = librox_do();\n    if (r == 0) { return 1; }\n    return 0;\n}\nsyscall(60, main());\n' > "$W/consumer/src/main.cyr"
run() { ( cd "$W/consumer" && CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 "$CLI" "$@" 2>&1 ); }

# ── axis 1: the resolve keeps the fold and vendors no profile file ─────────────────────
mkcons yes
O1=$(run deps); R1=$?
[ "$R1" = 0 ] && ok "cyrius deps succeeds (rc 0)" || bad "cyrius deps failed (rc $R1): $(echo "$O1" | tail -3)"
[ -f "$W/consumer/lib/sigil-mldsa.cyr" ] && bad "lib/sigil-mldsa.cyr was vendored beside the stdlib fold" || ok "lib/sigil-mldsa.cyr not vendored"
[ -f "$W/consumer/lib/sigil_hexz.cyr" ] && bad "lib/sigil_hexz.cyr was vendored beside the stdlib fold" || ok "lib/sigil_hexz.cyr not vendored"
cmp -s "$W/consumer/lib/sigil.cyr" "$ROOT/lib/sigil.cyr" && ok "lib/sigil.cyr is the snapshot's fold" \
    || bad "lib/sigil.cyr is not the snapshot's fold"
echo "$O1" | grep -q "\[deps.sigil\] dist/sigil-mldsa.cyr not vendored" && ok "the kept fold is named" \
    || bad "no note names the skipped profile module: $(echo "$O1" | tail -3)"

# ── axis 2: the build succeeds on the fold alone ───────────────────────────────────────
O2=$(run build src/main.cyr "$W/consumer/app"); R2=$?
[ "$R2" = 0 ] && ok "cyrius build succeeds (rc 0)" || bad "cyrius build failed (rc $R2): $(echo "$O2" | grep -iE 'error|duplicate' | head -3)"
echo "$O2" | grep -q 'duplicate fn' && bad "the build still carries duplicate fns: $(echo "$O2" | grep 'duplicate fn' | head -2)" || ok "no duplicate fn"
echo "$O2" | grep -qiE 'not found|cannot open|missing include' && bad "a missing include: $(echo "$O2" | grep -iE 'not found|cannot open|missing include' | head -2)" || ok "no missing include"
if [ "$R2" = 0 ]; then
    "$W/consumer/app"; RA=$?
    [ "$RA" = 0 ] && ok "the program runs on the fold's sha256_bsig0 (rc 0)" || bad "the program exited $RA (1 = it ran the thin profile's sha256_bsig0)"
fi

# ── axis 3: a stale profile copy from an earlier resolution is removed ─────────────────
cp "$W/thinsig/dist/sigil-mldsa.cyr" "$W/consumer/lib/sigil-mldsa.cyr"
O3=$(run deps); R3=$?
[ "$R3" = 0 ] && [ ! -f "$W/consumer/lib/sigil-mldsa.cyr" ] && ok "a stale lib/sigil-mldsa.cyr is removed" \
    || bad "a stale lib/sigil-mldsa.cyr survived the resolve (rc $R3)"
grep -q 'sigil-mldsa' "$W/consumer/cyrius.lock" 2>/dev/null && bad "cyrius.lock still lists sigil-mldsa" || ok "cyrius.lock does not list it"

# ── axis 4: ANTI-VACUOUS — no stdlib `sigil`, and the thin profile IS the package ──────
rm -rf "$W/consumer/lib" "$W/consumer/cyrius.lock"
mkcons no
O4=$(run deps); R4=$?
[ "$R4" = 0 ] && [ -f "$W/consumer/lib/sigil-mldsa.cyr" ] && [ -f "$W/consumer/lib/sigil_hexz.cyr" ] \
    && ok "without the stdlib leaf the thin profile is vendored (the fixture exercises the path)" \
    || bad "without the stdlib leaf the thin profile was not vendored (rc $R4): $(echo "$O4" | tail -3)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: deps_stdlib_profile_not_vendored — a thin profile of a stdlib leaf is neither vendored nor included; the fold builds alone"
    exit 0
fi
echo "FAIL: deps_stdlib_profile_not_vendored — $fails assertion(s) failed"
exit 1
