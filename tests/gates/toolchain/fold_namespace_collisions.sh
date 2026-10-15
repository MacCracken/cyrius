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
#
# 6.7.12 (the user's decision D30, 2026-10-15) — EVERY FOLD, AND SAME-VALUE PAIRS. sankoch 2.8.4's
# Brotli encoder declared `var _bre_err = 0;` and niyama already did: one cell for both, no warning
# (a prior `= 0` read as "no constant" — fixed in the compiler, see global_redeclaration_one_definition.sh
# W / XF — and a same-value pair is silent by design, the two-files-one-global rule), found only by
# the 6.7.11 distlib census; sankoch 2.8.7 renamed its side `_bre_ovf`. This gate looked at four folds.
#   axis 3  the fold list is DERIVED from docs/ecosystem.md's folded-distlib table (floor 12): every
#           fold compiles together after the prelude, in table order and reversed, rc 0, with no
#           collision / mixed-return warning located in any fold.
#   axis 4  census: a top-level `var` or `fn` name declared by TWO folds is a collision whatever its
#           value (the compiler is silent on a same-value pair). Read with the floors below, and
#           self-tested on a planted pair so a reader that matches nothing cannot pass.
# MUTATION LEDGER (6.7.12, a scratch tree whose lib/ carries the plant):
#   f1 `var _bre_err = 0;` appended to lib/sankoch.cyr and lib/niyama.cyr  -> RED axis 4 (same value)
#   f2 `var _bre_err = 0;` / `var _bre_err = 5;` in niyama / sankoch      -> RED axis 3 both orders and
#      axis 4; with a compiler before D30 the reverse order (niyama's 0 first, then 5) is silent
#   f3 a fold row dropped from docs/ecosystem.md's table (11 folds)        -> RED the floor
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

# ── axis 3: every fold in docs/ecosystem.md, compiled together ──────────────────────────────────
FOLDS=$(grep -oE '^\| `lib/[a-z_0-9]+\.cyr`' docs/ecosystem.md | sed -E 's/.*lib\/([a-z_0-9]+)\.cyr.*/\1/')
NF=0
for f in $FOLDS; do
    NF=$((NF + 1))
    [ -f "lib/$f.cyr" ] || { echo "FAIL: fold-namespace-collisions: docs/ecosystem.md names lib/$f.cyr, which is missing"; fail=1; }
done
if [ "$NF" -lt 12 ]; then echo "FAIL: fold-namespace-collisions: docs/ecosystem.md's fold table gave $NF folds (floor 12) — the reader matched too little"; exit 1; fi
FALT=$(printf '%s\n' $FOLDS | paste -sd'|' -)
REV=""
for f in $FOLDS; do REV="$f $REV"; done
check_all() {
    tag=$1
    hits=$(grep -E "^warning:lib/($FALT)\.cyr:" "$D/$tag.err" \
        | grep -E "duplicate fn|duplicate symbol .* conflicting value|but a SINGLE value here" || true)
    if [ -n "$hits" ]; then
        echo "FAIL: fold-namespace-collisions ($tag): cross-fold collision or mixed return:"
        echo "$hits" | sed 's/^/  /'
        fail=1
    fi
}
all_build() {
    tag=$1; shift
    { printf '%s\n' "$PRE"; for f in "$@"; do printf 'include "lib/%s.cyr"\n' "$f"; done
      printf 'fn main() { return 0; }\nsyscall(SYS_EXIT, main());\n'; } > "$D/$tag.cyr"
    "$CC" < "$D/$tag.cyr" > "$D/$tag.bin" 2> "$D/$tag.err"; crc=$?
    check_all "$tag"
    [ "$crc" -eq 0 ] || { echo "FAIL: fold-namespace-collisions ($tag): every fold together did not compile: $(grep -m2 '^error' "$D/$tag.err" | tr '\n' ' ')"; fail=1; }
}
all_build all_fwd $FOLDS
all_build all_rev $REV

# ── axis 4: the census — a top-level name two folds declare, whatever its value ──────────────────
# names <file> <tag>: "<tag> <name>" per top-level `var` / `fn` (column 0, `public` / `private` /
# `inline` / `async` allowed), one per name.
names() {
    grep -oE '^(public |private )?var [A-Za-z_][A-Za-z_0-9]*' "$1" | sed -E 's/^(public |private )?var /var /' | sort -u | sed "s/^/$2 /"
    grep -oE '^(public |private )?(inline |async )?fn [A-Za-z_][A-Za-z_0-9]*' "$1" | sed -E 's/^.*fn /fn /' | sort -u | sed "s/^/$2 /"
}
# census <list-file>: the "kind name" pairs two or more tags declare
census() { awk '{ k = $2 " " $3; key = k SUBSEP $1; if (!(key in seen)) { seen[key] = 1; n[k]++; who[k] = who[k] " " $1 } } END { for (k in n) if (n[k] > 1) print k ":" who[k] }' "$1" | sort; }
# self-test: a planted same-value pair across two fixture files is found
printf 'var _fnc_plant = 0;\nfn _fnc_pf(): i64 { return 1; }\n' > "$D/pa.cyr"
printf 'var _fnc_plant = 0;\nfn _fnc_pf(): i64 { return 1; }\n' > "$D/pb.cyr"
{ names "$D/pa.cyr" pa; names "$D/pb.cyr" pb; } > "$D/plant.lst"
census "$D/plant.lst" > "$D/plant.hit"
[ "$(grep -c '_fnc_plant\|_fnc_pf' "$D/plant.hit")" = 2 ] || { echo "FAIL: fold-namespace-collisions: the census missed a planted same-value pair (the reader is broken)"; fail=1; }
: > "$D/folds.lst"
for f in $FOLDS; do names "lib/$f.cyr" "$f" >> "$D/folds.lst"; done
NV=$(grep -c ' var ' "$D/folds.lst"); NFN=$(grep -c ' fn ' "$D/folds.lst")
if [ "$NV" -lt 1000 ] || [ "$NFN" -lt 1000 ]; then echo "FAIL: fold-namespace-collisions: the census read $NV var / $NFN fn names (floor 1000 each)"; fail=1; fi
census "$D/folds.lst" > "$D/folds.hit"
if [ -s "$D/folds.hit" ]; then
    echo "FAIL: fold-namespace-collisions (census): a top-level name declared by two folds (one global for both, by include order; fix it in the fold's SOURCE):"
    sed 's/^/  /' "$D/folds.hit"
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "PASS: fold-namespace-collisions: yukti + mabda + vani + sakshi compile together with no cross-fold collision or mixed return, both orders; both vendor ids keep their values; all $NF folds compile together both ways, and no top-level name is declared by two folds ($NV var / $NFN fn names)"
exit 0
