#!/bin/sh
# Gate: the `.deps` sidecar is COMPILE-VERIFIED, not merely inferred (v6.5.37, A3).
#
# THE DESIGN DEFECT THIS CLOSES. Everything upstream of it INFERS the leaf set from source
# text — an include-scan, the declared `[deps] stdlib`, and a prune that keeps a leaf only if
# the bundle appears to reference one of its definitions. That inference is unverifiable by
# construction AND is the only surviving record of what a fold needs: folding destroys the
# `include` lines (`lib/sandhi.cyr` has zero), so when the prune drops a leaf nothing
# downstream can recover it — not the consumer, not the resolver, not a human reading the
# bundle. An unverifiable oracle that is also the sole source of truth is a design defect.
#
# Measured at 6.5.36: 45 of 118 ecosystem sidecars fail a clean-room build from exactly the
# leaves they declare, 13 with hard compiler errors. The worked example is sigil's `sha`
# profile: it named `alloc freelist string process thread thread_local` and NOT `syscalls`,
# while `freelist` uses SYS_MMAP/SYS_MUNMAP four times and includes only mmap.cyr and
# atomic.cyr. Clean-room: 64 undefined symbols. After verification: 4 leaves re-added
# (`syscalls`, `vec`, `str`, `fmt`) and 2 undefined left, both sum-type variant constructors
# (`Ok`/`Err`) that no leaf declares as a fn.
#
# ⭐ SELF-HEALING, NOT REJECTING — that is what makes it shippable. It repairs the
# under-report rather than failing on it, so it does not convert 45 publishable bundles into
# 45 hard errors overnight.
#
# ⛔ THREE TRAPS THIS GATE ENCODES, each of which silently produced a wrong answer first:
#   1. Absolute `include` paths are REJECTED (CVE-16). An entry built from
#      `include "<abs>/alloc.cyr"` yields only rejection errors, so the loop saw zero
#      undefined symbols and re-added nothing while appearing to work. Sources are spliced.
#   2. A PRIVATE PEER is not the answer, its DISPATCHER is. SYS_MMAP is defined in
#      syscalls_x86_64_linux/_windows/_macos/_agnos, never in syscalls.cyr. The first cut
#      re-added `syscalls_windows` and `syscalls_macos` — putting Windows syscalls in a Linux
#      build — and still not `syscalls`. Axis 3 pins this.
#   3. `pub fn` is invisible to a bare `fn `/`var ` scan, and the snapshot has 322 of them.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
SNAP="$HOMEDIR/versions/$VER/lib"
[ -d "$SNAP" ] || SNAP="$HOMEDIR/lib"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: distlib_sidecar_verified: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_sidecar_verified: $1"; exit 1; }
# 6.6.11 (K5): the sidecar verify compiles for EVERY target, so the CLI needs cycc AND
# cycc_aarch64 beside it (it resolves its tools from its own directory). Stage a private tool
# dir from this tree; a staging failure means the gate could not run (77), never a FAIL.
CC=${CYCC:-"$ROOT/build/cycc"}
mkdir -p "$WORK/tools" && cp "$CYRIUS" "$WORK/tools/cyrius" && cp "$CC" "$WORK/tools/cycc" \
    && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$WORK/tools/cycc_aarch64" 2>/dev/null ) \
    && chmod +x "$WORK/tools/cyrius" "$WORK/tools/cycc" "$WORK/tools/cycc_aarch64" \
    || { echo "SKIP: distlib_sidecar_verified: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CYRIUS="$WORK/tools/cyrius"
[ -d "$SNAP" ] || { echo "SKIP: distlib_sidecar_verified: no stdlib snapshot at $SNAP"; exit 77; }

# ⚠ CYRIUS_RESOLVED=1 on every invocation. Without it, a fixture pinning anything other than
# the running version re-execs `versions/<pin>/bin/cyrius` — a binary built before this
# feature existed — and the gate silently tests the OLD code. That is not hypothetical: it is
# how this feature first appeared not to run at all during development.
# ⚠ CYRIUS_HOME is passed EXPLICITLY, so the CLI and the verify's cycc read the home under
# test: since 6.6.16 cycc's `lib/<leaf>.cyr` fallback reads CYRIUS_HOME's slot before HOME's
# (it read HOME's only, so this gate had to pin HOME to a throwaway — a staged run otherwise
# verified the tree's leaves against the LIVE store's slot, CHANGELOG [6.6.13]). HOMEDIR may
# come from $HOME/.cyrius, and then both readers agree anyway. The real HOME is left alone.
# CHANGELOG [6.6.16]
run_distlib() { ( cd "$1" && CYRIUS_HOME="$HOMEDIR" CYRIUS_RESOLVED=1 "$CYRIUS" distlib 2>&1 ); }

mkproj() {  # mkproj <dir> <body-of-src/lib.cyr> <declared stdlib list>
    d="$WORK/$1"; mkdir -p "$d/src"
    cat > "$d/cyrius.cyml" <<EOF
[package]
name = "vprobe"
version = "0.1.0"
cyrius = "$VER"

[lib]
modules = ["src/lib.cyr"]

[deps]
stdlib = [$3]
EOF
    printf '%s\n' "$2" > "$d/src/lib.cyr"
    echo "$d"
}

# ── axis 1: a symbol from an UNDECLARED, UNINCLUDED leaf gets that leaf re-added ──────
# F64_ONE lives in math.cyr, which is neither declared nor included anywhere — exactly the
# shape the include-scan and the prune both miss.
A=$(mkproj a 'fn vprobe_scale(x): i64 {
    var one = F64_ONE;
    return f64_mul(x, one);
}' '"syscalls", "alloc", "string", "io", "fmt", "vec", "str"')
run_distlib "$A" >/dev/null 2>&1 || true
[ -f "$A/dist/vprobe.deps" ] || fail "axis 1: no sidecar written"
grep -qx 'math' "$A/dist/vprobe.deps" || fail "axis 1: 'math' was not re-added — F64_ONE is undefined and the verification did not repair it"

# ── axis 2: ANTI-VACUOUS — a sufficient sidecar is NOT inflated ───────────────────────
# Without this, re-adding every leaf in the stdlib passes axis 1.
B=$(mkproj b 'fn vprobe_plain(x): i64 {
    return x + 1;
}' '"syscalls", "alloc", "string", "io", "fmt", "vec", "str"')
OUTB=$(run_distlib "$B" 2>&1 || true)
[ -f "$B/dist/vprobe.deps" ] || fail "axis 2: no sidecar written"
NB=$(grep -c '^[a-z]' "$B/dist/vprobe.deps" || true)
[ "$NB" -le 12 ] || fail "axis 2: a self-sufficient bundle grew to $NB leaves — the verification is inflating, not repairing"
echo "$OUTB" | grep -q 're-added' && fail "axis 2: verification re-added leaves to a bundle that needed none"

# ── axis 3: a peer-defined symbol resolves to the DISPATCHER, not the peer ────────────
# SYS_MMAP is defined only in the per-arch peers. Adding a peer directly would put another
# platform's syscalls in the build; the correct answer is `syscalls`.
C=$(mkproj c 'fn vprobe_map(n): i64 {
    return syscall(SYS_MMAP, 0, n, 3, 34, 0 - 1, 0);
}' '"alloc", "string"')
run_distlib "$C" >/dev/null 2>&1 || true
[ -f "$C/dist/vprobe.deps" ] || fail "axis 3: no sidecar written"
if grep -qE '^syscalls_' "$C/dist/vprobe.deps"; then
    fail "axis 3: a per-arch PEER was added ($(grep -E '^syscalls_' "$C/dist/vprobe.deps" | tr '\n' ' ')) instead of the dispatcher 'syscalls'"
fi
grep -qx 'syscalls' "$C/dist/vprobe.deps" || fail "axis 3: 'syscalls' was not re-added for an undefined SYS_MMAP"

# ── axis 4: every leaf in a verified sidecar resolves ─────────────────────────────────
for f in "$A/dist/vprobe.deps" "$B/dist/vprobe.deps" "$C/dist/vprobe.deps"; do
    while IFS= read -r l; do
        case "$l" in ''|'#'*) continue;; esac
        [ -f "$SNAP/$l.cyr" ] || [ -d "$SNAP/$l" ] || fail "axis 4: $f names '$l', which does not resolve in $SNAP"
    done < "$f"
done

# ── axes 5-9 (6.6.9, libro filing): THE UNIT IS WHAT A CONSUMER'S BUILD HAS IN SCOPE ────
# libro takes sigil as a THIN named dep. The verify spliced only the stdlib leaves and the
# bundle, so every sigil symbol read as undefined, was credited to the stdlib sigil MONOLITH,
# and the next round recorded the monolith's own need (`sys`) as libro's. Hermetic home with
# three fake stdlib leaves and one PATH named dep — no git dep, so no <home>/deps is touched:
#   fold.cyr      the monolith, SAME NAME as the named dep; its fold_sign/fold_extra need helperlib
#   bigfold.cyr   a monolith under ANOTHER name that also declares thin_sign, and needs helperlib
#   helperlib.cyr what the monoliths need and the bundle (normally) does not
# and the named dep `fold` = ../foldsrc/dist/fold-thin.cyr (fold_sign, thin_sign, no needs).
NH="$WORK/nhome"
mkdir -p "$NH/versions/$VER" "$NH/bin" "$WORK/foldsrc/dist"
cp -R "$ROOT/lib" "$NH/versions/$VER/lib"
cp "$CC" "$NH/bin/cycc"; chmod +x "$NH/bin/cycc"
printf 'fn helperlib_do(x): i64 { return x; }\nfn helperlib_two(x): i64 { return x + 2; }\n' > "$NH/versions/$VER/lib/helperlib.cyr"
printf 'fn fold_sign(x): i64 { return helperlib_do(x); }\nfn fold_extra(x): i64 { return helperlib_do(x) + 1; }\n' > "$NH/versions/$VER/lib/fold.cyr"
printf 'fn thin_sign(x): i64 { return helperlib_do(x) + 2; }\n' > "$NH/versions/$VER/lib/bigfold.cyr"
printf '[package]\nname = "fold"\nversion = "1.0.0"\ncyrius = "%s"\n' "$VER" > "$WORK/foldsrc/cyrius.cyml"
printf 'fn fold_sign(x): i64 { return x + 1; }\nfn thin_sign(x): i64 { return x + 2; }\n' > "$WORK/foldsrc/dist/fold-thin.cyr"

mknd() {  # mknd <dir> <body-of-src/np.cyr> <src/lib.cyr umbrella body>
    d="$WORK/$1"; mkdir -p "$d/src"
    cat > "$d/cyrius.cyml" <<EOF
[package]
name = "np"
version = "0.1.0"
cyrius = "$VER"

[lib]
modules = ["src/np.cyr"]

[deps]
stdlib = ["syscalls", "alloc"]

[deps.fold]
path = "../foldsrc"
modules = ["dist/fold-thin.cyr"]
EOF
    printf '%s\n' "$2" > "$d/src/np.cyr"
    printf '%s\n' "$3" > "$d/src/lib.cyr"
    echo "$d"
}
run_nd() { ( cd "$1" && CYRIUS_HOME="$NH" CYRIUS_RESOLVED=1 "$CYRIUS" distlib 2>&1 ); }
nd_leaves() { grep -v '^#' "$1/dist/np.deps" 2>/dev/null | tr '\n' ' '; }

# axis 5: a symbol the bundle takes from the named dep is DEFINED in the unit (module splice).
# thin_sign's only stdlib declarer is bigfold, which is not a named dep, so neither the owner
# guard nor the leaf skip can hide a missing splice here.
P5=$(mknd p5 'fn np_a(x): i64 { return thin_sign(x); }' 'include "src/np.cyr"')
O5=$(run_nd "$P5" || true)
[ -f "$P5/dist/np.deps" ] || fail "axis 5: no sidecar written: $(echo "$O5" | head -3)"
case " $(nd_leaves "$P5") " in
    *" helperlib "*|*" bigfold "*) fail "axis 5: [$(nd_leaves "$P5")] — thin_sign comes from the named dep's module, but the verify unit left it out and credited it to the stdlib's bigfold (the libro 'sys' shape)" ;;
esac

# axis 6: a leaf that IS a named dep is the consumer's pinned module, not the stdlib fold.
# The umbrella includes lib/fold.cyr, so `fold` is captured as a leaf; splicing the stdlib's
# fold.cyr brings its helperlib need into the sidecar.
P6=$(mknd p6 'fn np_c(x): i64 { return fold_sign(x); }' 'include "lib/fold.cyr"
include "src/np.cyr"')
O6=$(run_nd "$P6" || true)
[ -f "$P6/dist/np.deps" ] || fail "axis 6: no sidecar written: $(echo "$O6" | head -3)"
case " $(nd_leaves "$P6") " in
    *" helperlib "*) fail "axis 6: [$(nd_leaves "$P6")] — the leaf 'fold' is a named dep, but the verify spliced the STDLIB fold and recorded its needs" ;;
esac

# axis 7: no named dep is ever an OWNER. fold_extra exists only in the stdlib fold (the thin
# module lacks it); crediting it to `fold` re-adds a leaf the writer then silently drops.
P7=$(mknd p7 'fn np_b(x): i64 { return fold_sign(x) + fold_extra(x); }' 'include "src/np.cyr"')
O7=$(run_nd "$P7" || true)
[ -f "$P7/dist/np.deps" ] || fail "axis 7: no sidecar written: $(echo "$O7" | head -3)"
echo "$O7" | grep -q 're-added' && fail "axis 7: the verify re-added a leaf for fold_extra — a named dep ('fold') was taken as the owner: $(echo "$O7" | grep re-added)"

# axis 8 (ANTI-VACUOUS for 5-7): a bundle that genuinely calls a helperlib fn still gets it.
P8=$(mknd p8 'fn np_d(x): i64 { return thin_sign(x) + helperlib_do(x); }' 'include "src/np.cyr"')
run_nd "$P8" >/dev/null 2>&1 || true
case " $(nd_leaves "$P8") " in
    *" helperlib "*) : ;;
    *) fail "axis 8 (anti-vacuous): [$(nd_leaves "$P8")] — np_d calls helperlib_do, and helperlib was not re-added" ;;
esac

# axis 9: FAIL LOUD. A unit that fails to compile for a reason other than a missing symbol
# (here: an include that resolves nowhere) used to read as "nothing undefined" — the sidecar
# was published UNVERIFIED, silently. Now distlib exits non-zero and writes no sidecar.
P9=$(mknd p9 'include "lib/no_such_leaf_zz.cyr"
fn np_e(x): i64 { return x; }' 'include "src/np.cyr"')
if O9=$(run_nd "$P9"); then fail "axis 9: distlib exited 0 over a verify unit that cannot compile"; fi
[ -f "$P9/dist/np.deps" ] && fail "axis 9: a sidecar was written although its verify could not run: [$(nd_leaves "$P9")]"
echo "$O9" | grep -q 'sidecar NOT written' || fail "axis 9: the refusal did not say why: $(echo "$O9" | head -3)"

# axis 10: a named dep's OWN needs stay out. `fold2`'s module calls helperlib_do and hd_do, and
# its sidecar names `helperlib` and `hd_impl`. Its module is in the unit, so those symbols
# surface as undefined too; recorded, every named dep's leaves are copied into the bundle's
# sidecar (measured on agnosai's `guard` profile: +12 leaves: tls, async, dynlib, …). A symbol
# whose owner a named dep's leaf list brings, and which nothing of ours names, is taken into the
# unit and NOT recorded. `hd_impl` is a private PEER whose dispatcher is `hd`, so the check must
# accept either spelling. `math` is the anti-vacuous half: the bundle's own F64_ONE is still
# re-added (axis 10b below covers the other half of the rule: OUR use of such a leaf is recorded).
printf 'include "lib/hd_impl.cyr"\nvar _hd_marker = 0;\n' > "$NH/versions/$VER/lib/hd.cyr"
printf 'fn hd_do(x): i64 { return x + 4; }\n' > "$NH/versions/$VER/lib/hd_impl.cyr"
mkdir -p "$WORK/fold2src/dist"
printf '[package]\nname = "fold2"\nversion = "1.0.0"\ncyrius = "%s"\n' "$VER" > "$WORK/fold2src/cyrius.cyml"
printf 'fn fold2_do(x): i64 { return helperlib_do(x) + hd_do(x); }\n' > "$WORK/fold2src/dist/fold2.cyr"
printf '# cyrius dep sidecar\nhelperlib\nhd_impl\n' > "$WORK/fold2src/dist/fold2.deps"
P10=$(mknd p10 'fn np_f(x): i64 {
    var one = F64_ONE;
    return fold2_do(x) + one;
}' 'include "src/np.cyr"')
printf '\n[deps.fold2]\npath = "../fold2src"\nmodules = ["dist/fold2.cyr"]\n' >> "$P10/cyrius.cyml"
O10=$(run_nd "$P10" || true)
[ -f "$P10/dist/np.deps" ] || fail "axis 10: no sidecar written: $(echo "$O10" | head -3)"
[ -f "$P10/lib/hd_impl.cyr" ] || fail "axis 10 premise: cyrius deps did not pull fold2's sidecar leaf hd_impl: $(echo "$O10" | head -3)"
case " $(nd_leaves "$P10") " in
    *" helperlib "*|*" hd "*|*" hd_impl "*) fail "axis 10: [$(nd_leaves "$P10")] — helperlib/hd_impl are fold2's needs (its sidecar carries them), not the bundle's" ;;
esac
case " $(nd_leaves "$P10") " in
    *" math "*) : ;;
    *) fail "axis 10 (anti-vacuous): [$(nd_leaves "$P10")] — np_f reads F64_ONE and 'math' was not re-added" ;;
esac

# axis 11: EACH FILE ONCE. The unit used to SPLICE leaf text, while the bundle (and other
# leaves) still carried `include "lib/<leaf>.cyr"` — so the leaf arrived twice, and every
# `#define` in it was spent twice from cycc's 16-entry table (majra's `backends` profile: the
# sigil fold's seven `#define LINUX`, pulled in again through tls_native). `defs` carries nine;
# twice is past the cap, once is not. The overflow printed no `undefined` line, so the old loop
# read it as "fixpoint" and `math` (F64_ONE, below) was silently never re-added.
printf '#define DEFS_A\n#define DEFS_B\n#define DEFS_C\n#define DEFS_D\n#define DEFS_E\n#define DEFS_F\n#define DEFS_G\n#define DEFS_H\n#define DEFS_I\nfn defs_do(x): i64 { return x + 9; }\n' > "$NH/versions/$VER/lib/defs.cyr"
P11=$(mknd p11 'include "lib/defs.cyr"
fn np_h(x): i64 {
    var one = F64_ONE;
    return defs_do(x) + one;
}' 'include "src/np.cyr"')
sed -i.bak 's/^stdlib = \["syscalls", "alloc"\]/stdlib = ["syscalls", "alloc", "defs"]/' "$P11/cyrius.cyml" && rm -f "$P11/cyrius.cyml.bak"
O11=$(run_nd "$P11" || true)
[ -f "$P11/dist/np.deps" ] || fail "axis 11: no sidecar written — the unit carried defs.cyr twice and overflowed the #define table: $(echo "$O11" | grep -i error | head -2)"
grep -qx 'math' "$P11/dist/np.deps" || fail "axis 11: 'math' not re-added for F64_ONE in [$(nd_leaves "$P11")] — the unit failed (a leaf included twice) and the loop took the failure for a fixpoint"

# axis 10b: the rule is "a named dep's need AND not ours". np_k calls helperlib_do ITSELF, so
# helperlib is recorded even though fold2 brings it too — the sidecar must not lean on a
# named dep's leaf list for what the bundle uses (measured: that is how rosnet's `gpu` sidecar
# lost `alloc`, which its leaf mabda needs, because tyche happened to bring it).
P10B=$(mknd p10b 'fn np_k(x): i64 { return fold2_do(x) + helperlib_do(x); }' 'include "src/np.cyr"')
printf '\n[deps.fold2]\npath = "../fold2src"\nmodules = ["dist/fold2.cyr"]\n' >> "$P10B/cyrius.cyml"
O10B=$(run_nd "$P10B" || true)
grep -qx 'helperlib' "$P10B/dist/np.deps" 2>/dev/null || fail "axis 10b: [$(nd_leaves "$P10B")] — np_k calls helperlib_do itself, so helperlib must be recorded, not left to fold2: $(echo "$O10B" | grep -i error | head -2)"

# axis 10c: "ours" includes a recorded leaf's PRIVATE PEERS. `pd` is a dispatcher whose peer
# pd_impl calls helperlib_do; the bundle uses pd, never helperlib. helperlib is a need of OUR
# leaf, so it is recorded although fold2 brings it too (syscalls.cyr is this shape: its x86
# peer is where `alloc` is used).
printf 'include "lib/pd_impl.cyr"\nvar _pd_marker = 0;\n' > "$NH/versions/$VER/lib/pd.cyr"
printf 'fn pd_do(x): i64 { return helperlib_do(x) + 5; }\n' > "$NH/versions/$VER/lib/pd_impl.cyr"
P10C=$(mknd p10c 'fn np_m(x): i64 { return fold2_do(x) + pd_do(x); }' 'include "src/np.cyr"')
sed -i.bak 's/^stdlib = \["syscalls", "alloc"\]/stdlib = ["syscalls", "alloc", "pd"]/' "$P10C/cyrius.cyml" && rm -f "$P10C/cyrius.cyml.bak"
printf '\n[deps.fold2]\npath = "../fold2src"\nmodules = ["dist/fold2.cyr"]\n' >> "$P10C/cyrius.cyml"
O10C=$(run_nd "$P10C" || true)
grep -qx 'pd' "$P10C/dist/np.deps" 2>/dev/null || fail "axis 10c premise: 'pd' not in [$(nd_leaves "$P10C")]: $(echo "$O10C" | grep -i error | head -2)"
grep -qx 'helperlib' "$P10C/dist/np.deps" || fail "axis 10c: [$(nd_leaves "$P10C")] — pd's peer pd_impl calls helperlib_do; a recorded leaf's need was left to fold2"

# axis 10d: WHOSE NEED does not depend on the ORDER of the diagnostics. fold2's module calls
# helperlib_do and the bundle calls helperlib_TWO — a different symbol of the same leaf. The
# modules sit before the bundle in the unit, so fold2's name is classified first and helperlib
# goes to the unit-only scope; the bundle's own name, checked against that scope BEFORE it was
# checked against what is ours, was skipped — and from the next round helperlib is in the unit,
# so the bundle's use never surfaced again and helperlib was never recorded.
P10D=$(mknd p10d 'fn np_n(x): i64 { return fold2_do(x) + helperlib_two(x); }' 'include "src/np.cyr"')
printf '\n[deps.fold2]\npath = "../fold2src"\nmodules = ["dist/fold2.cyr"]\n' >> "$P10D/cyrius.cyml"
O10D=$(run_nd "$P10D" || true)
[ -f "$P10D/dist/np.deps" ] || fail "axis 10d: no sidecar written: $(echo "$O10D" | head -3)"
grep -qx 'helperlib' "$P10D/dist/np.deps" || fail "axis 10d: [$(nd_leaves "$P10D")] — np_n calls helperlib_two itself; it was hidden behind fold2's helperlib_do, which the unit reported first"

# axis 10e: nor on the ROUND. rr is a leaf the bundle uses but neither declares nor includes, so
# it is only recorded in round 1 — the round that also put helperlib in the scope for fold2.
# rr calls helperlib_do; from round 2 helperlib was in the unit, so rr's need never surfaced
# and a RECORDED leaf's need was left to fold2. A round that records a leaf re-decides the
# scope with that leaf counted as ours.
printf 'fn rr_do(x): i64 { return helperlib_do(x) + 7; }\n' > "$NH/versions/$VER/lib/rr.cyr"
P10E=$(mknd p10e 'fn np_p(x): i64 { return fold2_do(x) + rr_do(x); }' 'include "src/np.cyr"')
printf '\n[deps.fold2]\npath = "../fold2src"\nmodules = ["dist/fold2.cyr"]\n' >> "$P10E/cyrius.cyml"
O10E=$(run_nd "$P10E" || true)
grep -qx 'rr' "$P10E/dist/np.deps" 2>/dev/null || fail "axis 10e premise: 'rr' not re-added in [$(nd_leaves "$P10E")]: $(echo "$O10E" | head -3)"
grep -qx 'helperlib' "$P10E/dist/np.deps" || fail "axis 10e: [$(nd_leaves "$P10E")] — the re-added leaf rr calls helperlib_do; its need was hidden by the scope an earlier round gave fold2"

# axis 13 (6.6.11, K6): THE ROUND CAP IS NOT CONVERGENCE. zc1..zc8 is a chain (zcK_f calls
# zc(K+1)_f), so each round finds exactly one more leaf. The loop ran out of rounds with zc7 and
# zc8 never added, returned the same answer as a real fixpoint, and published zc1..zc6 as
# "compile-verified" at rc 0 — a consumer then failed on an undefined zc7_f. Now it exits
# non-zero, names the non-convergence and writes no sidecar. 13b is the anti-vacuous control:
# a 5-leaf chain converges inside the cap and records all five.
k=1
while [ "$k" -le 8 ]; do
    if [ "$k" -lt 8 ]; then zb="zc$((k + 1))_f(x) + 1"; else zb="x"; fi
    printf 'fn zc%s_f(x): i64 { return %s; }\n' "$k" "$zb" > "$NH/versions/$VER/lib/zc$k.cyr"
    if [ "$k" -le 5 ]; then
        if [ "$k" -lt 5 ]; then yb="yc$((k + 1))_f(x) + 1"; else yb="x"; fi
        printf 'fn yc%s_f(x): i64 { return %s; }\n' "$k" "$yb" > "$NH/versions/$VER/lib/yc$k.cyr"
    fi
    k=$((k + 1))
done
mkchain() {  # mkchain <dir> <body of src/np.cyr> — no declared leaves, no named deps
    d="$WORK/$1"; mkdir -p "$d/src"
    printf '[package]\nname = "np"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/np.cyr"]\n' "$VER" > "$d/cyrius.cyml"
    printf '%s\n' "$2" > "$d/src/np.cyr"
    echo "$d"
}
P13=$(mkchain p13 'fn np_z(x): i64 { return zc1_f(x); }')
if O13=$(run_nd "$P13"); then fail "axis 13: distlib exited 0 on an 8-leaf chain the 6-round verify cannot finish: [$(nd_leaves "$P13")]"; fi
[ -f "$P13/dist/np.deps" ] && fail "axis 13: an unverified sidecar was written: [$(nd_leaves "$P13")]"
echo "$O13" | grep -q 'did not converge in 6 rounds' || fail "axis 13: the refusal did not name the non-convergence: $(echo "$O13" | grep -i error | head -3)"
P13B=$(mkchain p13b 'fn np_y(x): i64 { return yc1_f(x); }')
O13B=$(run_nd "$P13B" || true)
[ -f "$P13B/dist/np.deps" ] || fail "axis 13b (anti-vacuous): no sidecar for a 5-leaf chain: $(echo "$O13B" | grep -i error | head -3)"
for k in 1 2 3 4 5; do
    grep -qx "yc$k" "$P13B/dist/np.deps" || fail "axis 13b (anti-vacuous): 'yc$k' missing from [$(nd_leaves "$P13B")]"
done

# axis 14 (6.6.16, C10): the verify's cycc reads CYRIUS_HOME's slot, not HOME's. HOME is a
# throwaway whose slot holds the 6.6.13 shape — a stale math.cyr that still defines the f64_le
# builtin, which fails with nothing undefined, so the verify fails loud — and axis 1's bundle
# must not see it. Measured: the slot-open cycc reads HOME's slot here and writes no sidecar.
SH="$WORK/stalehome"
mkdir -p "$SH/.cyrius/versions/$VER/lib"
printf 'var F64_ONE = 4607182418800017408;\nfn f64_le(a, b): i64 { return 0; }\n' > "$SH/.cyrius/versions/$VER/lib/math.cyr"
A14=$(mkproj a14 'fn vprobe_scale(x): i64 {
    var one = F64_ONE;
    return f64_mul(x, one);
}' '"syscalls", "alloc", "string", "io", "fmt", "vec", "str"')
( cd "$A14" && HOME="$SH" CYRIUS_HOME="$HOMEDIR" CYRIUS_RESOLVED=1 "$CYRIUS" distlib ) >/dev/null 2>&1 || true
[ -f "$A14/dist/vprobe.deps" ] || fail "axis 14: no sidecar written under a HOME whose slot is stale — the verify read HOME's slot, not CYRIUS_HOME's"
grep -qx 'math' "$A14/dist/vprobe.deps" || fail "axis 14: 'math' was not re-added under a HOME whose slot is stale"

# axis 12: the verify's scratch mirror (dist/.dlverify-<pid>) never outlives the run — on the
# success path or on the fail-loud one.
for d in "$P5" "$P6" "$P9" "$P10" "$P10B" "$P10C" "$P10D" "$P10E" "$P11" "$P13" "$P13B" "$A14"; do
    if ls -a "$d/dist" 2>/dev/null | grep -q '^\.dlverify-'; then
        fail "axis 12: $d/dist still holds the verify's scratch mirror"
    fi
done

echo "PASS: distlib_sidecar_verified (missing leaf repaired, sufficient set untouched, dispatcher not peer, all resolve, named deps in the unit, fails loud, the round cap is not convergence, CYRIUS_HOME's slot not HOME's)"
