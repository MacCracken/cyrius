#!/bin/sh
# Gate: a `.deps` sidecar is the same whichever host (and whichever target env) runs
# `cyrius distlib` — it is the UNION of what every target needs (6.6.11, K5).
#
# THE DEFECT. The sidecar verify compiled its unit ONCE, for the host target, so the recorded
# leaf set was whatever THAT target's `#ifdef` arms left undefined. `distlib --check` then
# drifted between a Mac or ARM box and Linux CI, and a fold published from Linux could be short
# on Windows. Measured over 60 ecosystem bundles at 6.6.10: 15 had different undefined sets per
# target (14 on PE, nous on aarch64). The verify now compiles for x86_64 Linux / Windows / macOS
# / agnos (6.6.18, D3) and aarch64 Linux / macOS each round and classifies the union.
#
# ⚖️ AND THE UNION NEEDS AN OWNER RULE. A symbol undefined on only SOME targets was credited to
# the first snapshot file declaring it. mihi's EINTR is undefined on PE only (syscalls_windows
# lacks it) and `sigil.cyr` sorts before every syscalls peer, so a union with that rule records
# the sigil MONOLITH for mihi on every host. Now (6.6.18, D3): a declarer already in the unit
# that still left it undefined is skipped (it demonstrably does not define it there); a FOLD
# bundle is never the owner while a non-fold file declares the name; else the one dispatcher
# whose PEER declares it; else the one non-peer declarer; else a named refusal.
#
# Axes (a hermetic CYRIUS_HOME whose snapshot is the tree's lib/ plus fixture leaves, and a
# private tool dir holding the CLI, cycc and a cycc_aarch64 built from src/ for this run):
#   1. a leaf whose per-target arms call five different leaves: all five are recorded.
#   2. the same sidecar with CYRIUS_TARGET_WIN=1 / CYRIUS_MACHO=1 / CYRIUS_MACHO_ARM=1 /
#      CYRIUS_TARGET_AGNOS=1 in the
#      environment (the CLI's children inherit it since 6.6.11 B09) — byte-identical.
#   3. the mihi shape: EINTRZ undefined on PE only, owned by the recorded dispatcher's peers;
#      the monoliths that also declare it (`aaa_mono`, …) are NOT recorded.
#   4. the canonical definer: the same shape with the dispatcher NOT declared — the dispatcher
#      (whose peers declare it) is recorded, never a monolith.
#   5. two non-peer leaves could own a PE-only symbol: a named refusal, no sidecar.
#   6. a symbol declared only by a peer OF A PEER (syscalls_linux_common's shape: included by the
#      Linux and macOS syscalls peers, never by syscalls.cyr) is owned by the DISPATCHER — the
#      helper itself in a sidecar puts Linux wrappers in a consumer's Windows build (measured on
#      agnodrm, dhancha, dhvani and agnosai while the union was being built).
#   7. …but only a PRIVATE one: a `sysz_`-prefixed leaf that a peer AND another leaf include is
#      its own owner (thread_local's shape — crediting it to `thread` dropped it from majra's,
#      prakash's, szal's and sigil's sidecars).
# Exit 77 when it could not run (no compiler, no CLI, the aarch64 compiler would not build).
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
VER=$(cat "$ROOT/VERSION")
[ -x "$CC" ] || { echo "SKIP: distlib_sidecar_host_independent: no compiler at $CC"; exit 77; }
[ -x "$CYRIUS" ] || { echo "SKIP: distlib_sidecar_host_independent: no CLI at $CYRIUS"; exit 77; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: distlib_sidecar_host_independent: mktemp -d failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_sidecar_host_independent: $1"; exit 1; }

# The tool dir: the CLI resolves cycc / cycc_aarch64 beside itself, so this run tests THESE.
mkdir -p "$WORK/bin" "$WORK/home/versions/$VER"
cp "$CYRIUS" "$WORK/bin/cyrius"; cp "$CC" "$WORK/bin/cycc"; chmod +x "$WORK/bin/cyrius" "$WORK/bin/cycc"
( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$WORK/bin/cycc_aarch64" 2>/dev/null ) \
    || { echo "SKIP: distlib_sidecar_host_independent: cycc_aarch64 did not build from src/main_aarch64.cyr"; exit 77; }
chmod +x "$WORK/bin/cycc_aarch64"
L="$WORK/home/versions/$VER/lib"
cp -R "$ROOT/lib" "$L"

# ── fixtures ─────────────────────────────────────────────────────────────────────────
cat > "$L/tgtleaf.cyr" <<'EOF'
fn tgtleaf_do(x): i64 {
    var r = x;
    #ifdef CYRIUS_TARGET_LINUX
    #ifdef CYRIUS_ARCH_X86
    r = r + tla_lin_do(x);
    #endif
    #ifdef CYRIUS_ARCH_AARCH64
    r = r + tla_a64_do(x);
    #endif
    #endif
    #ifdef CYRIUS_TARGET_WIN
    r = r + tla_win_do(x);
    #endif
    #ifdef CYRIUS_TARGET_MACOS
    #ifdef CYRIUS_ARCH_X86
    r = r + tla_mac_do(x);
    #endif
    #ifdef CYRIUS_ARCH_AARCH64
    r = r + tla_macarm_do(x);
    #endif
    #endif
    return r;
}
EOF
for a in lin a64 win mac macarm; do
    printf 'fn tla_%s_do(x): i64 { return x + 1; }\n' "$a" > "$L/tla$a.cyr"
done
# mihi shape: a dispatcher whose PE peer lacks the symbol, and monoliths that also declare it.
cat > "$L/sysz.cyr" <<'EOF'
#ifdef CYRIUS_TARGET_WIN
include "lib/sysz_windows.cyr"
#endif
#ifdef CYRIUS_TARGET_LINUX
include "lib/sysz_linux.cyr"
#endif
#ifdef CYRIUS_TARGET_MACOS
include "lib/sysz_macos.cyr"
#endif
var _sysz_marker = 0;
EOF
printf 'var EINTRZ = 4;\nvar SYSZ_READ = 0;\ninclude "lib/sysz_common.cyr"\n' > "$L/sysz_linux.cyr"
printf 'var EINTRZ = 4;\nvar SYSZ_READ = 3;\ninclude "lib/sysz_common.cyr"\ninclude "lib/sysz_pub.cyr"\n' > "$L/sysz_macos.cyr"
# `sysz_`-prefixed and included by a peer, but a leaf in its OWN right (another leaf includes it
# too) — lib/thread_local.cyr's shape: included by thread_macos, patra and tls_native.
printf 'var SYSZ_PUB_Y = 7;\n' > "$L/sysz_pub.cyr"
printf 'include "lib/sysz_pub.cyr"\nvar _otherz_marker = 0;\n' > "$L/otherz.cyr"
# a peer of the PEERS (never included by sysz.cyr itself) — lib/syscalls_linux_common.cyr's shape
printf 'var SYSZ_COMMON_X = 4096;\n' > "$L/sysz_common.cyr"
printf 'var SYSZ_READ = 0;\n' > "$L/sysz_windows.cyr"
# ⚠ The monoliths are written LAST and there are three: the pre-6.6.11 rule credited the FIRST
# declarer in directory order, and tmpfs lists newest-first — so a first-declarer regression
# picks a monolith here deterministically on tmpfs, and with 3-in-5 odds on a hashed ext4 dir.
# ⚠ 6.6.18 (D3): they carry a FOLD header, because that is what they model — sigil is a
# `cyrius distlib` bundle, and since an in-unit declarer no longer ends the search, the fold
# rule is what keeps them out (three header-less leaves would be a genuine ambiguity).
for mono in aaa_mono mmm_mono zzz_mono; do
    printf '# %s.cyr -- bundled distribution\n# Generated by: cyrius distlib\nvar EINTRZ = 4;\nfn %s_x(x): i64 { return x; }\n' "$mono" "$mono" > "$L/$mono.cyr"
done
# two non-peer leaves that both declare a symbol only PE needs
printf 'var AMBZ = 1;\n' > "$L/ambz_one.cyr"
printf 'var AMBZ = 2;\n' > "$L/ambz_two.cyr"
cat > "$L/ambuser.cyr" <<'EOF'
fn ambuser_do(x): i64 {
    var r = x;
    #ifdef CYRIUS_TARGET_WIN
    r = r + AMBZ;
    #endif
    return r;
}
EOF

mkproj() {  # mkproj <dir> <body of src/lib.cyr> <declared stdlib list>
    d="$WORK/$1"; mkdir -p "$d/src"
    cat > "$d/cyrius.cyml" <<EOF
[package]
name = "hprobe"
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
# env -u: the target selectors of the CALLER's shell must not leak into the baseline run.
run_distlib() { ( cd "$1" && env -u CYRIUS_TARGET_WIN -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM -u CYRIUS_TARGET_AGNOS \
    CYRIUS_HOME="$WORK/home" CYRIUS_RESOLVED=1 "$WORK/bin/cyrius" distlib 2>&1 ); }
leaves() { grep -v '^#' "$1/dist/hprobe.deps" 2>/dev/null | tr '\n' ' '; }

# ── axis 1: every target's arm is recorded ───────────────────────────────────────────
P1=$(mkproj p1 'fn hp_a(x): i64 { return tgtleaf_do(x); }' '"tgtleaf"')
O1=$(run_distlib "$P1" || true)
[ -f "$P1/dist/hprobe.deps" ] || fail "axis 1: no sidecar written: $(echo "$O1" | grep -i error | head -3)"
for a in lin a64 win mac macarm; do
    grep -qx "tla$a" "$P1/dist/hprobe.deps" \
        || fail "axis 1: 'tla$a' missing from [$(leaves "$P1")] — the sidecar holds only the host's arm, not the union over targets"
done

# ── axis 2: the target env of the shell does not change the answer ─────────────────────
cp "$P1/dist/hprobe.deps" "$WORK/base.deps"
for ev in CYRIUS_TARGET_WIN=1 CYRIUS_MACHO=1 CYRIUS_MACHO_ARM=1 CYRIUS_TARGET_AGNOS=1; do
    rm -f "$P1/dist/hprobe.deps"
    O2=$( cd "$P1" && env "$ev" CYRIUS_HOME="$WORK/home" CYRIUS_RESOLVED=1 "$WORK/bin/cyrius" distlib 2>&1 ) || true
    [ -f "$P1/dist/hprobe.deps" ] || fail "axis 2: no sidecar written under $ev: $(echo "$O2" | grep -i error | head -3)"
    cmp -s "$WORK/base.deps" "$P1/dist/hprobe.deps" \
        || fail "axis 2: under $ev the sidecar is [$(leaves "$P1")], not [$(grep -v '^#' "$WORK/base.deps" | tr '\n' ' ')]"
done

# ── axis 3: the mihi shape — a PE-only gap in a RECORDED dispatcher adds nothing ─────────
P3=$(mkproj p3 'fn hp_m(x): i64 { return x + EINTRZ + SYSZ_READ; }' '"sysz"')
O3=$(run_distlib "$P3" || true)
[ -f "$P3/dist/hprobe.deps" ] || fail "axis 3: no sidecar written: $(echo "$O3" | grep -i error | head -3)"
grep -qx 'sysz' "$P3/dist/hprobe.deps" || fail "axis 3 premise: 'sysz' not in [$(leaves "$P3")]"
grep -qE '^(aaa|mmm|zzz)_mono$' "$P3/dist/hprobe.deps" \
    && fail "axis 3: [$(leaves "$P3")] — EINTRZ (undefined on PE only) was credited to a monolith, the first declarer in directory order"

# ── axis 4: the canonical definer — the dispatcher whose peers declare it ─────────────────
P4=$(mkproj p4 'fn hp_n(x): i64 {
    #ifdef CYRIUS_TARGET_LINUX
    return x + EINTRZ;
    #endif
    return x;
}' '')
O4=$(run_distlib "$P4" || true)
[ -f "$P4/dist/hprobe.deps" ] || fail "axis 4: no sidecar written: $(echo "$O4" | grep -i error | head -3)"
grep -qE '^(aaa|mmm|zzz)_mono$' "$P4/dist/hprobe.deps" \
    && fail "axis 4: [$(leaves "$P4")] — a Linux-only EINTRZ went to a monolith, not to sysz (its peers declare it)"
grep -qx 'sysz' "$P4/dist/hprobe.deps" || fail "axis 4: 'sysz' not recorded in [$(leaves "$P4")]"

# ── axis 5: two non-peer owners for a PE-only symbol is a named refusal ─────────────────
P5=$(mkproj p5 'fn hp_o(x): i64 { return ambuser_do(x); }' '"ambuser"')
if O5=$(run_distlib "$P5"); then fail "axis 5: distlib exited 0 though AMBZ has two possible owners on PE"; fi
[ -f "$P5/dist/hprobe.deps" ] && fail "axis 5: a sidecar was written: [$(leaves "$P5")]"
echo "$O5" | grep -q "'AMBZ' is undefined only on x86_64-windows" || fail "axis 5: the refusal did not name the symbol and target: $(echo "$O5" | grep -i error | head -3)"
echo "$O5" | grep -q 'ambz_one' && echo "$O5" | grep -q 'ambz_two' || fail "axis 5: the refusal did not name both candidates: $(echo "$O5" | grep -i error | head -3)"

# ── axis 6: a peer of a peer belongs to the dispatcher ───────────────────────────────────
P6=$(mkproj p6 'fn hp_q(x): i64 { return x + SYSZ_COMMON_X; }' '"sysz"')
O6=$(run_distlib "$P6" || true)
[ -f "$P6/dist/hprobe.deps" ] || fail "axis 6: no sidecar written: $(echo "$O6" | grep -i error | head -3)"
grep -qx 'sysz_common' "$P6/dist/hprobe.deps" \
    && fail "axis 6: [$(leaves "$P6")] — SYSZ_COMMON_X (undefined on PE only) went to the private helper sysz_common, not its dispatcher"
P6B=$(mkproj p6b 'fn hp_r(x): i64 {
    #ifdef CYRIUS_TARGET_LINUX
    return x + SYSZ_COMMON_X;
    #endif
    return x;
}' '')
O6B=$(run_distlib "$P6B" || true)
[ -f "$P6B/dist/hprobe.deps" ] || fail "axis 6b: no sidecar written: $(echo "$O6B" | grep -i error | head -3)"
grep -qx 'sysz_common' "$P6B/dist/hprobe.deps" && fail "axis 6b: [$(leaves "$P6B")] — the peer of a peer was recorded"
grep -qx 'sysz' "$P6B/dist/hprobe.deps" || fail "axis 6b: 'sysz' (the dispatcher) not recorded in [$(leaves "$P6B")]"

# ── axis 7: a peer-included leaf that is not private stays its own owner ──────────────────
P7=$(mkproj p7 'fn hp_s(x): i64 { return x + SYSZ_PUB_Y; }' '"sysz"')
O7=$(run_distlib "$P7" || true)
[ -f "$P7/dist/hprobe.deps" ] || fail "axis 7: no sidecar written: $(echo "$O7" | grep -i error | head -3)"
grep -qx 'sysz_pub' "$P7/dist/hprobe.deps" \
    || fail "axis 7: [$(leaves "$P7")] — SYSZ_PUB_Y is missing on every target but macOS, and its leaf sysz_pub was not recorded (credited to the dispatcher sysz instead)"

echo "PASS: distlib_sidecar_host_independent (the union over six targets, identical under any target env, owner = the recorded/peer definer, a private peer of a peer is its dispatcher, ambiguity refused)"
