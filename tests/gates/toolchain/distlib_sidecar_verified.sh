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
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_sidecar_verified: $1"; exit 1; }
[ -d "$SNAP" ] || { echo "  SKIPPED: no stdlib snapshot at $SNAP"; exit 0; }

# ⚠ CYRIUS_RESOLVED=1 on every invocation. Without it, a fixture pinning anything other than
# the running version re-execs `versions/<pin>/bin/cyrius` — a binary built before this
# feature existed — and the gate silently tests the OLD code. That is not hypothetical: it is
# how this feature first appeared not to run at all during development.
run_distlib() { ( cd "$1" && CYRIUS_RESOLVED=1 "$CYRIUS" distlib 2>&1 ); }

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

echo "PASS: distlib_sidecar_verified (missing leaf repaired, sufficient set untouched, dispatcher not peer, all resolve)"
