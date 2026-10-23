#!/bin/sh
# dce_propagation_closure.sh — 6.7.18 (optimize). FIXUP's dead-code reachability reaches EVERY fn a live fn calls,
# however deep the chain, on the x86 and the aarch64 backend.
#
# THE DEFECT. The propagation was a fixpoint: each round scanned the body of every live fn for calls (E8 / E9 on
# x86, BL / B on aarch64) and marked their targets, and rounds repeated until one marked nothing — capped at 512
# rounds. A round walks the fns in index (definition) order, so a call to a fn defined EARLIER is only followed in
# the next round: a call chain defined callee-first (f699 .. f0, the top level calling f0) needs one round per
# link, and the cap left everything past the 512th link unmarked. The `N unreachable fns` note then counted live
# fns (187 for this 700-deep chain), and CYRIUS_DCE=1 NOP-filled them: the program died of SIGILL (exit 132),
# where it exits 188. Every
# round also re-walked every live body — a self-compile walked ~28 M bytes in 10 rounds.
# Now a worklist (`_dce_x86_prop`, `_dce_a64_prop`): each live body is scanned once, a fn its scan marks joins
# the list, and there is no cap. Reachability has one closure, so every program the cap did not cut gets the
# same live set — cycc's own output and the whole tests/tcyr corpus are byte-identical.
#
# ROWS
#   C1  x86: f699 .. f0 defined callee-first, three fns nobody calls, the top level calls f0. The note counts
#       exactly 3 unreachable fns; with CYRIUS_DCE=1 the binary exits 700 & 255 = 188 (the default build too).
#   C2  aarch64 (the cross compiler from src/main_aarch64.cyr): the same note; the CYRIUS_DCE=1 binary exits 188
#       under qemu-aarch64 — a loud SKIP by name when it is not installed (the note is still checked).
#
# MUTATION PROOF (6.7.18): the parent's compiler (the 512-round fixpoint) -> RED on C1 (note 190, the DCE binary
# dies of SIGILL, exit 132) and C2 (note 190); the cap lowered to 64 rounds in a scratch copy of the parent -> RED
# (note 638).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=dce_propagation_closure
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_DCE CYRIUS_COVERAGE
FAIL=0

awk 'BEGIN { n = 700
             for (i = n - 1; i >= 0; i--) {
                 if (i == n - 1) printf "fn f%d(a: i64): i64 { return a + 1; }\n", i
                 else printf "fn f%d(a: i64): i64 { return f%d(a) + 1; }\n", i, i + 1 }
             for (k = 1; k <= 3; k++) printf "fn dead%d(a: i64): i64 { return a * %d; }\n", k, k
             print "syscall(60, f0(0) & 255);" }' > "$D/chain.cyr"

# note <stderr file>: the unreachable-fn count the note gives, 0 when there is no note.
note() { n=$(sed -n 's/^note: \([0-9][0-9]*\) unreachable fns.*/\1/p' "$1" | head -1); echo "${n:-0}"; }

# ── C1: x86 ────────────────────────────────────────────────────────────────────────────────────────────────
"$CC" < "$D/chain.cyr" > "$D/x" 2> "$D/x.err"; xrc=$?
CYRIUS_DCE=1 "$CC" < "$D/chain.cyr" > "$D/xd" 2> "$D/xd.err"; xdrc=$?
chmod +x "$D/x" "$D/xd" 2>/dev/null
r1=0; "$D/x" || r1=$?
r2=0; "$D/xd" || r2=$?
n1=$(note "$D/x.err")
if [ "$xrc" -ne 0 ] || [ "$xdrc" -ne 0 ]; then echo "FAIL: $G [C1]: the chain did not compile (rc $xrc / DCE $xdrc)"; sed -n 1,3p "$D/x.err"; FAIL=1
elif [ "$n1" != 3 ] || [ "$r1" -ne 188 ] || [ "$r2" -ne 188 ]; then
    echo "FAIL: $G [C1]: x86 — note $n1 unreachable fns (want 3), exit $r1 / CYRIUS_DCE=1 exit $r2 (want 188 / 188)"; FAIL=1
else echo "  ok [C1] x86: 3 unreachable fns noted, the chain exits 188 with and without CYRIUS_DCE=1"; fi

# ── C2: aarch64 ────────────────────────────────────────────────────────────────────────────────────────────
(cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$D/xa64" 2> "$D/xa64.err"); arc=$?
if [ "$arc" -ne 0 ] || [ ! -s "$D/xa64" ]; then echo "FAIL: $G [C2]: cycc could not cross-build src/main_aarch64.cyr"; sed -n 1,3p "$D/xa64.err"; FAIL=1
else
    chmod +x "$D/xa64"
    "$D/xa64" < "$D/chain.cyr" > "$D/a" 2> "$D/a.err"; arc1=$?
    CYRIUS_DCE=1 "$D/xa64" < "$D/chain.cyr" > "$D/ad" 2> "$D/ad.err"; arc2=$?
    n2=$(note "$D/a.err")
    if [ "$arc1" -ne 0 ] || [ "$arc2" -ne 0 ]; then echo "FAIL: $G [C2]: the aarch64 compile failed (rc $arc1 / DCE $arc2)"; sed -n 1,3p "$D/a.err"; FAIL=1
    elif [ "$n2" != 3 ]; then echo "FAIL: $G [C2]: aarch64 — note $n2 unreachable fns (want 3)"; FAIL=1
    elif command -v qemu-aarch64 >/dev/null 2>&1; then
        chmod +x "$D/ad"; q=0; qemu-aarch64 "$D/ad" || q=$?
        if [ "$q" -ne 188 ]; then echo "FAIL: $G [C2]: aarch64 — the CYRIUS_DCE=1 binary exits $q under qemu-aarch64 (want 188)"; FAIL=1
        else echo "  ok [C2] aarch64: 3 unreachable fns noted, the CYRIUS_DCE=1 chain exits 188 under qemu-aarch64"; fi
    else echo "  ok [C2] aarch64: 3 unreachable fns noted — SKIP the run: qemu-aarch64 is not installed"; fi
fi

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "PASS: $G"
exit 0
