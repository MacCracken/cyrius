#!/bin/sh
# Gate: yukti, mabda, vani and sakshi compile together with no cross-fold name collision
# and no mixed-return fn, in either include order that the collisions depended on.
#
# WHY. cyrius has ONE global namespace, and a duplicate definition only WARNS ("last
# definition wins"), so two folds that pick the same name silently re-route each other by
# include order. Found at 6.6.12 (B14), all three live in the vendored folds:
#   * `PCI_VENDOR_AMD`: yukti's PciVendor enum says 0x1022 (PCI-SIG AMD), mabda's var said
#     0x1002 (the AMD/ATI GPU id WGPUAdapterInfo reports). Whichever came first compared
#     against the other's value. mabda 4.1.6 renames its side WGPU_VENDOR_ID_AMD.
#   * `_sk_emit_err`: mabda and vani each defined it; with both in scope one library's
#     errors were named through the other's `*_err_name` and gated on the other's
#     observability flag. mabda 4.1.6 / vani 1.2.8 prefix their own.
#   * vani_drain / vani_drop / vani_state returned Err on the null guard and the RAW
#     integer on the live path, so a two-value bind read the integer as the TAG (a device
#     in state SETUP read as Err). vani 1.2.8 returns a Result on every path.
# Each axis also RUNS the build: both vendor constants must keep their own values.
#
# MUTATION PROOF (6.6.12): restoring the 6.6.11 lib/mabda.cyr + lib/vani.cyr reddens axes
# 1 and 2: the PCI_VENDOR_AMD conflict, the _sk_emit_err duplicate and three mixed-return
# warnings are reported, and the run probe no longer compiles (WGPU_VENDOR_ID_AMD undefined).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: fold-namespace-collisions: no compiler at $CC"; exit 77; }
for f in yukti mabda vani sakshi patra; do
    [ -f "lib/$f.cyr" ] || { echo "FAIL: fold-namespace-collisions: lib/$f.cyr missing"; exit 1; }
done
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: fold-namespace-collisions: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

PRE='include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/result.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/args.cyr"
include "lib/fnptr.cyr"
include "lib/freelist.cyr"
include "lib/tagged.cyr"
include "lib/mmap.cyr"
include "lib/chrono.cyr"
include "lib/thread.cyr"
include "lib/thread_local.cyr"
include "lib/atomic.cyr"
include "lib/sync.cyr"
include "lib/process.cyr"
include "lib/dynlib.cyr"
include "lib/fdlopen.cyr"
include "lib/sakshi.cyr"
include "lib/patra.cyr"'
# Exit 0 only when BOTH vendor ids kept their own value (and yukti's AMD vendor matched).
MAIN='fn main() {
    if (PCI_VENDOR_AMD != 0x1022) { return 10; }
    if (WGPU_VENDOR_ID_AMD != 0x1002) { return 11; }
    if (_wgpu_vendor_wgpu_deprecated(0x1002) != 1) { return 12; }
    return 0;
}
syscall(SYS_EXIT, main());'

fail=0
# Collision / mixed-return warnings located in one of the four folds. Other warning
# classes are out of this gate's scope.
check_warn() {
    tag=$1
    hits=$(grep -E '^warning:lib/(yukti|mabda|vani|sakshi)\.cyr:' "$D/$tag.err" \
        | grep -E "duplicate fn|duplicate symbol .* conflicting value|but a SINGLE value here" || true)
    if [ -n "$hits" ]; then
        echo "FAIL: fold-namespace-collisions ($tag): cross-fold collision or mixed return:"
        echo "$hits" | sed 's/^/  /'
        fail=1
    fi
}
build_run() {
    tag=$1
    "$CC" < "$D/$tag.cyr" > "$D/$tag.bin" 2> "$D/$tag.err"; crc=$?
    # Warnings first: a compile failure must not hide the collision report.
    check_warn "$tag"
    if [ "$crc" -ne 0 ]; then
        echo "FAIL: fold-namespace-collisions ($tag): compile failed: $(grep -m2 '^error' "$D/$tag.err" | tr '\n' ' ')"
        fail=1; return
    fi
    chmod +x "$D/$tag.bin"
    "$D/$tag.bin"; rc=$?
    [ "$rc" -eq 0 ] || { echo "FAIL: fold-namespace-collisions ($tag): vendor-id run exited $rc (10: yukti's PCI_VENDOR_AMD lost 0x1022; 11/12: mabda's WGPU_VENDOR_ID_AMD / guard lost 0x1002)"; fail=1; }
}

# axis 1: yukti before mabda before vani (the order the collisions were reproduced in).
printf '%s\ninclude "lib/yukti.cyr"\ninclude "lib/mabda.cyr"\ninclude "lib/vani.cyr"\n%s\n' "$PRE" "$MAIN" > "$D/ymv.cyr"
build_run ymv
# axis 2: the reverse fold order — a last-definition-wins collision flips its victim.
printf '%s\ninclude "lib/mabda.cyr"\ninclude "lib/yukti.cyr"\ninclude "lib/vani.cyr"\n%s\n' "$PRE" "$MAIN" > "$D/myv.cyr"
build_run myv

[ "$fail" -eq 0 ] || exit 1
echo "PASS: fold-namespace-collisions: yukti + mabda + vani + sakshi compile together with no cross-fold collision or mixed return, both orders; both vendor ids keep their values"
exit 0
