#!/bin/sh
# tests/gates/toolchain/gates_run_from_foreign_cwd.sh — 6.6.16 (G1)
#
# EVERY GATE RUNS FROM `/`, AND THE HARNESS MAKES SURE OF IT.
#
# THE DEFECT. 36 gates derived their root from $0 (`R=` / `ROOT=$(cd "$(dirname "$0")/../../.."
# && pwd)`) and never cd'd there. They then compiled `$ROOT/src/main*.cyr`, `programs/*.cyr` or
# a fixture that includes `lib/...` with raw cycc, whose includes resolve against the CWD (raw
# `cat | cycc` gets no #@incdir marker), or read `src/main.cyr` relative to it (heapmap.sh).
# Launched from anywhere but the tree root they failed — "cannot open include file:
# src/version_str.cyr", "could not build src/main_cx.cyr", "src/main.cyr not found" — and
# NOTHING caught it, because scripts/check.sh and the check driver always ran from the root
# and `--run-gate` inherited that cwd. The planning measurement found 22; 14 more were hidden
# from it by cycc's include FALLBACK, `$HOME/.cyrius/versions/<V>/lib/`: a gate whose only
# cwd-relative include is `lib/...` still compiles from a foreign cwd whenever that store slot
# exists — against the STORE's lib, not the tree's. Measured with a HOME that has no store.
#
# THE FIX. Each of the 36 gates cds to the root it derives. And the supervisor every gate runs
# under (programs/checks/run_gate.cyr `_run_gate_main`) chdirs to `/` before it starts the
# gate, so every check.sh run runs every shell gate and every driver-registered gate from a
# foreign cwd: a gate that forgets its `cd` and needs `src/` / `programs/` / a tree file is
# red on the next run instead of green by accident. A relative script path is refused (it
# would resolve against `/`). A `lib/`-only dependence is the one shape the runtime guard
# cannot see under a HOME with a store slot (the fallback answers), so axis 5 pins the 36
# `cd` lines statically.
#
# CONVENTION (every new gate): derive ROOT from $0, `cd "$ROOT"`, honour $CYCC, and pass when
# launched as `cd / && sh <abs path>` — under a HOME with no `.cyrius`, so the include
# fallback cannot answer for the tree.
#
# AXES
#   1  `--run-gate <abs probe>` launched from a scratch dir runs the probe with cwd `/`
#   2  `--run-gate <relative path>` is refused (exit 2, says "absolute"), and the probe never runs
#   3  a REAL cwd-dependent gate (tests/gates/memory/heapmap.sh, which reads src/main.cyr
#      relative to its cwd) passes under `--run-gate` launched from the scratch dir
#   4  the scratch dir the driver was launched from is still empty afterwards
#   5  each of the 36 gates keeps a top-level `cd "$R"` / `cd "$ROOT"`; the detector is
#      self-tested on a fixture without one (it must flag it) and one with it (it must not)
#
# MUTATIONS (each RED; measured when this gate was written):
#   M1 the `sys_chdir("/")` in `_run_gate_main` removed          -> axis 1 RED (cwd = scratch dir)
#   M2 the absolute-path check removed                            -> axis 2 RED (sh cannot open it
#      from `/`: rc 127, no refusal line)
#   M3 heapmap.sh's `cd "$ROOT"` removed                          -> axes 3 and 5 RED
#   M4 any one of the 36 `cd` lines removed                       -> axis 5 RED (and, under
#      --run-gate, that gate itself: all 36 with a store-less HOME, the 22 with any HOME)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: gates_run_from_foreign_cwd: cannot cd to $ROOT"; exit 1; }
NAME=gates_run_from_foreign_cwd
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: $NAME: $CC missing"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
FAILS=0
_fail() { echo "  FAIL: $NAME: $1"; FAILS=$((FAILS + 1)); }

# The driver, built from THIS tree (never build/cyrius_check, which may be stale).
if ! "$CC" < programs/checks/main.cyr > "$T/drv" 2> "$T/drv.err"; then
    echo "FAIL: $NAME: programs/checks/main.cyr does not compile"
    sed -n 1,10p "$T/drv.err"
    exit 1
fi
chmod +x "$T/drv"

mkdir "$T/foreign" "$T/probe"
printf '#!/bin/sh\npwd > "$1"\n' > "$T/probe/probe.sh"

# axis 1 — the probe sees cwd `/`.
RC1=0
( cd "$T/foreign" && "$T/drv" --run-gate "$T/probe/probe.sh" "$T/probe/pwd.out" ) > "$T/a1.out" 2>&1 || RC1=$?
[ "$RC1" = 0 ] || { _fail "axis 1: --run-gate on a probe exited $RC1"; sed -n 1,5p "$T/a1.out"; }
if [ -f "$T/probe/pwd.out" ]; then
    P1=$(cat "$T/probe/pwd.out")
    [ "$P1" = "/" ] || _fail "axis 1: the gate ran with cwd '$P1', not '/' (the supervisor inherited the caller's cwd)"
else
    _fail "axis 1: the probe never wrote its cwd"
fi

# axis 2 — a relative script path is refused and nothing runs.
RC2=0
( cd "$T/probe" && "$T/drv" --run-gate probe.sh "$T/probe/rel.out" ) > "$T/a2.out" 2>&1 || RC2=$?
[ "$RC2" = 2 ] || _fail "axis 2: a relative script path exited $RC2, want 2 (refused)"
grep -q 'must be absolute' "$T/a2.out" || _fail "axis 2: the refusal does not say the path must be absolute"
[ ! -f "$T/probe/rel.out" ] || _fail "axis 2: the probe RAN from a relative path"

# axis 3 — a real gate that reads the tree relative to its cwd passes from a foreign cwd.
RC3=0
( cd "$T/foreign" && "$T/drv" --run-gate "$ROOT/tests/gates/memory/heapmap.sh" ) > "$T/a3.out" 2>&1 || RC3=$?
[ "$RC3" = 0 ] || { _fail "axis 3: tests/gates/memory/heapmap.sh exited $RC3 under --run-gate from a foreign cwd"; sed -n 1,5p "$T/a3.out"; }

# axis 4 — nothing was written into the directory the driver was launched from.
LEFT=$(ls -A "$T/foreign")
[ -z "$LEFT" ] || _fail "axis 4: the launch dir is not empty afterwards: $LEFT"

# axis 5 — the 36 cd lines stay. The detector: a column-0 `cd "$R"` / `cd "$ROOT"` line.
_has_root_cd() { grep -qE '^cd "\$(R|ROOT)"' "$1"; }
printf 'R=$(cd "$(dirname "$0")/../../.." && pwd)\nCC="$R/build/cycc"\n' > "$T/nocd.sh"
printf 'R=$(cd "$(dirname "$0")/../../.." && pwd)\ncd "$R" || exit 1\n' > "$T/withcd.sh"
_has_root_cd "$T/nocd.sh" && _fail "axis 5: the detector does not flag a gate without its cd (self-test)"
_has_root_cd "$T/withcd.sh" || _fail "axis 5: the detector flags a gate that has its cd (self-test)"
for g in codegen/aggregate_copy_all_words codegen/aggregate_copy_assign_slots \
         codegen/call_site_stack_alignment codegen/cx_forward_read_constant_global \
         codegen/dce_eliminates codegen/dce_pe_macho_layout_declines_compaction \
         codegen/decode_len_coverage codegen/dx01_syms_parity codegen/f64_exp_infinite_argument \
         codegen/f64v4_ymm_disasm codegen/inline_directive codegen/inline_simd256_return_lanes \
         codegen/ir_edges_scaling codegen/ir_nop_harvest codegen/simd_direct_form \
         codegen/simd_f32v8_disasm codegen/simd_param_inline_reach \
         codegen/simd_valueform_no_avx_transition codegen/simd_vec_reject \
         codegen/stack_enum_no_alloc codegen/wholeprogram_nop_compaction \
         concurrency/lazy_init_release_fence diagnostics/dx_multi_error \
         frontend/coroutine_midbody_suspend frontend/derive_accessors_inlined \
         frontend/duplicate_fn_arity_mismatch frontend/global_redeclaration_one_definition \
         frontend/lexid_prefix_exact frontend/private_per_item_rejected \
         frontend/stack_enum_lossy_context frontend/toplevel_block_var_scope \
         frontend/toplevel_decl_block_closure memory/hash_seed_flood_resistance memory/heapmap \
         platform/ffi_stack_protected_extern_c toolchain/ci_steps_delegate_to_driver; do
    f="tests/gates/$g.sh"
    if [ ! -f "$f" ]; then _fail "axis 5: $f is missing (renamed? move its entry with it)"; continue; fi
    _has_root_cd "$f" || _fail "axis 5: $f lost its top-level cd to the root it derives — it then compiles against whatever the cwd (or the store's lib) holds"
done

if [ "$FAILS" -ne 0 ]; then
    echo "FAIL: $NAME ($FAILS)"
    exit 1
fi
echo "PASS: $NAME (5 axes: probe cwd is /, relative path refused, heapmap from a foreign cwd, launch dir untouched, 36 root cds pinned)"
exit 0
