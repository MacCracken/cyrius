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
#      environment (the CLI's children inherit it since 6.6.11 B09) — byte-identical. And
#      (6.6.20) with more than 8 KiB of environment: each target compile's selector used to be
#      APPENDED after the inherited entries, past the 8191 bytes cycc's `_read_env` reads, so
#      Windows / macOS / agnos all verified as Linux and their leaves fell out of the union.
#   3. the mihi shape: EINTRZ undefined on PE only, owned by the recorded dispatcher's peers;
#      the fold monoliths that also declare it (`aaa_mono`, …) are NOT recorded. ⚠ Since the
#      6.6.18 fixpoint seeds nothing, round 1 sees EINTRZ undefined on EVERY target, so this axis
#      runs the every-target owner rule first and the partial rule only in round 2.
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
#   8. only NON-fold leaves declare a name every target lacks: the owner is the first of them in
#      BYTE order, never the first the filesystem lists.
#
# ⛔ NOTHING HERE MAY PASS BY THE FILESYSTEM'S LISTING ORDER (6.7.7). The owner rule took the
# first declarer in `dir_list` order, and tmpfs lists newest-first while ext4 lists by a
# per-filesystem name hash — so axis 3 failed on every run with TMPDIR on tmpfs and passed on
# ext4 by hash luck (~3 in 5), which is how a release gate read GREEN over the bug. The CLI now
# reads the snapshot in byte order, and the two halves of the fix are each caught on ANY
# filesystem: axis 3's monoliths SORT first (`aaa_mono`), so a dropped fold rule fails it; axis
# 8's right owner sorts first but is ARRANGED never to list first — the gate reads the
# snapshot's own order (`ls -f`, the getdents order the CLI reads) and retries with a fresh
# right name until a wrong one leads (a wrong leaf is created before it for a creation-order
# lister and after it for tmpfs; a hash-order lister puts a fresh name first among n declarers
# with odds 1/n) — so a snapshot read in listing order fails it. A fixture that cannot be
# arranged is a FAIL by name, never a vacuous pass. Axis 3's monoliths are also created around
# the peers (`aaa_mono` before, the rest after), so a creation-order lister and tmpfs list one
# first there too.
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
# first_listed <leaf>...: which of the leaves the snapshot's OWN order lists first — `ls -f`
# never sorts, so it is the getdents order the CLI's dir_list reads.
first_listed() {
    ls -f "$L" > "$WORK/order"
    : > "$WORK/want"
    for w in "$@"; do printf '%s.cyr\n' "$w" >> "$WORK/want"; done
    grep -Fx -f "$WORK/want" "$WORK/order" | sed -n '1s/\.cyr$//p' || true
}
# A fold monolith declaring EINTRZ: a `cyrius distlib` header, as sigil's bundle carries.
MONOS=""
mkmono() {
    printf '# %s.cyr -- bundled distribution\n# Generated by: cyrius distlib\nvar EINTRZ = 4;\nfn %s_x(x): i64 { return x; }\n' "$1" "$1" > "$L/$1.cyr"
    MONOS="$MONOS $1"
}
# Before the peers: a creation-order lister (btrfs, a small XFS directory) lists it first.
mkmono aaa_mono
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
# ⚠ The monoliths carry a FOLD header, because that is what they model — sigil is a `cyrius
# distlib` bundle, and the fold rule is what keeps them out (header-less leaves would be a
# genuine ambiguity). After the peers: tmpfs lists newest-first.
mkmono mmm_mono
mkmono zzz_mono
# Axis 8: TIEZ, declared only by non-fold leaves. The right owner `tiez_a<k>` sorts before every
# wrong one (`tiez_w…`) and must not list first (the header): each try makes a wrong leaf, a
# fresh right one, another wrong one, and keeps the wrong ones.
TIE_R=""
TIES=""
k=0
while :; do
    [ -z "$TIE_R" ] || rm -f "$L/$TIE_R.cyr"
    k=$((k + 1))
    [ "$k" -le 32 ] || fail "fixture: a fresh tiez_a<k> listed first among TIEZ's declarers 32 times — axis 8 would pass a listing-order regression vacuously"
    printf 'var TIEZ = 2;\n' > "$L/tiez_w${k}a.cyr"
    TIE_R="tiez_a$k"
    printf 'var TIEZ = 1;\n' > "$L/$TIE_R.cyr"
    printf 'var TIEZ = 3;\n' > "$L/tiez_w${k}b.cyr"
    TIES="$TIES tiez_w${k}a tiez_w${k}b"
    [ "$(first_listed "$TIE_R" $TIES)" = "$TIE_R" ] || break
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
for ev in CYRIUS_TARGET_WIN=1 CYRIUS_MACHO=1 CYRIUS_MACHO_ARM=1 CYRIUS_TARGET_AGNOS=1 \
          "PAD=$(head -c 9000 /dev/zero | tr '\0' x)"; do
    rm -f "$P1/dist/hprobe.deps"
    evn=$(printf '%s' "$ev" | cut -c1-32)
    O2=$( cd "$P1" && env "$ev" CYRIUS_HOME="$WORK/home" CYRIUS_RESOLVED=1 "$WORK/bin/cyrius" distlib 2>&1 ) || true
    [ -f "$P1/dist/hprobe.deps" ] || fail "axis 2: no sidecar written under $evn: $(echo "$O2" | grep -i error | head -3)"
    cmp -s "$WORK/base.deps" "$P1/dist/hprobe.deps" \
        || fail "axis 2: under $evn the sidecar is [$(leaves "$P1")], not [$(grep -v '^#' "$WORK/base.deps" | tr '\n' ' ')]"
done

# ── axis 3: the mihi shape — a PE-only gap in a RECORDED dispatcher adds nothing ─────────
P3=$(mkproj p3 'fn hp_m(x): i64 { return x + EINTRZ + SYSZ_READ; }' '"sysz"')
O3=$(run_distlib "$P3" || true)
[ -f "$P3/dist/hprobe.deps" ] || fail "axis 3: no sidecar written: $(echo "$O3" | grep -i error | head -3)"
grep -qx 'sysz' "$P3/dist/hprobe.deps" || fail "axis 3 premise: 'sysz' not in [$(leaves "$P3")]"
grep -qE '^(aaa|mmm|zzz)_mono$' "$P3/dist/hprobe.deps" \
    && fail "axis 3: [$(leaves "$P3")] — EINTRZ was credited to a fold monolith although the non-fold sysz peers declare it (first listed: $(first_listed $MONOS sysz_linux sysz_macos); first in byte order: aaa_mono)"

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

# ── axis 8: a non-fold tie on every target goes to the first in BYTE order ──────────────────
P8=$(mkproj p8 'fn hp_t(x): i64 { return x + TIEZ; }' '')
O8=$(run_distlib "$P8" || true)
[ -f "$P8/dist/hprobe.deps" ] || fail "axis 8: no sidecar written: $(echo "$O8" | grep -i error | head -3)"
[ "$(grep -c '^tiez_' "$P8/dist/hprobe.deps")" = 1 ] && grep -qx "$TIE_R" "$P8/dist/hprobe.deps" \
    || fail "axis 8: [$(leaves "$P8")] — TIEZ's owner is not $TIE_R, the first of its declarers in byte order (first listed: $(first_listed "$TIE_R" $TIES)): the snapshot was read in the filesystem's order"

echo "PASS: distlib_sidecar_host_independent (the union over six targets, identical under any target env, owner = the recorded/peer definer, a private peer of a peer is its dispatcher, ambiguity refused, the owner independent of the snapshot's listing order)"
