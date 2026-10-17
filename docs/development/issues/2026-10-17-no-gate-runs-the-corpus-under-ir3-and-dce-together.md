# No gate runs the .tcyr corpus under CYRIUS_IR=3 and CYRIUS_DCE=1 together — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-17 from the 6.7.14 infra lane's review. The IR=3 seam's stale losing-body ranges
(fixed in the lane's review fix, `_wp_fnr_shift`) killed tests/tcyr/crossos/fn_redefinition_last_wins.tcyr with SIGILL under
`CYRIUS_IR=3 CYRIUS_DCE=1`, yet passed every gate and the lane's full check.sh: nothing builds the corpus with both flags.
**Placement:** 6.7.15 — repair 5 (infra lane; filed from the 6.7.14 infra review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low (test coverage). Each mode has corpus coverage of its own; the combination, where the IR=3 seam's
compaction runs before FIXUP's dead-code pass reads positions recorded at parse time, has none.
**Affects:** the gates, not src/: scripts/differential.sh (default and `CYRIUS_DCE=1` torture modes),
tests/gates/memory/coverage_mode_corpus.sh (x86 and `CYRIUS_IR=3` legs), tests/gates/ir-opt/ir3_substrate_correctness.sh
(axis 5, an opt-in default-vs-IR=3 sweep), tests/gates/codegen/dce_eliminates.sh axis 8 (W^X, `CYRIUS_WX=0`, aarch64, and since
the review fix one `CYRIUS_IR=3` leg plus 8b: two probes and the one .tcyr).

## Reproduction

```sh
# from the worktree root; one.sh compiles one file with the given env and runs it (exit 0 = pass)
cat > one.sh <<'EOF'
cc=$1; f=$2; od=$3; shift 3
n=$(echo "$f" | tr '/' '_'); o="$od/$n.bin"
env "$@" "$cc" < "$f" > "$o" 2> "$od/$n.err"; rc=$?
if [ $rc -ne 0 ] || [ ! -s "$o" ]; then echo "CFAIL $f rc=$rc"; rm -f "$o"; exit 0; fi
chmod +x "$o"; x=0; timeout 60 "$o" < /dev/null > /dev/null 2>&1 || x=$?; rm -f "$o"
[ $x -eq 0 ] || echo "RFAIL $f exit=$x"
EOF
mkdir -p out
find tests/tcyr -name '*.tcyr' | sort | xargs -P 8 -I{} sh one.sh ./build/cycc {} out CYRIUS_IR=3 CYRIUS_DCE=1 2>/dev/null | sort
```

The infra lane's compiler after the review fix (624 files):

```
RFAIL tests/tcyr/crossos/call_ptr_field_store.tcyr exit=139
RFAIL tests/tcyr/derive/derive_enum_inside_ifdef.tcyr exit=139
```

Before the review fix (lane head 4aee52a58) the run also had `RFAIL tests/tcyr/crossos/fn_redefinition_last_wins.tcyr
exit=132`, with dce_eliminates.sh and the lane's full check.sh green. The slot-open compiler (`git show 2600f67f:build/cycc`)
on the same 624 files:

```
RFAIL tests/tcyr/crossos/call_ptr_field_store.tcyr exit=139
RFAIL tests/tcyr/crossos/derive_accessor_widths.tcyr exit=1
RFAIL tests/tcyr/crossos/derive_nested_scanner.tcyr exit=2
RFAIL tests/tcyr/crossos/ptr_param_bare_struct.tcyr exit=8
RFAIL tests/tcyr/crossos/struct_field_value_copy.tcyr exit=1
RFAIL tests/tcyr/crossos/struct_value_codegen.tcyr exit=139
RFAIL tests/tcyr/derive/derive_enum_inside_ifdef.tcyr exit=139
RFAIL tests/tcyr/lang/generic_instance_inline_binding.tcyr exit=132
RFAIL tests/tcyr/lang/generic_struct_pointer_field.tcyr exit=4
RFAIL tests/tcyr/lang/ptr_param_small_struct.tcyr exit=2
```

The two left are known IR=3 defects, filed: call_ptr_field_store's f64 row is
issues/2026-10-15-ir3-f64-field-store-through-pointer-faults.md; derive_enum_inside_ifdef is the staged
2026-10-16-ir3-const-fold-over-dead-store-nop-fills-its-immediate.md (both fail under `CYRIUS_IR=3` alone).

## Root cause

The corpus gates take one mode per leg. The IR=3 seam (main.cyr, `wp_compact` before FIXUP) moves code that FIXUP's
dead-code pass then reads through positions recorded at parse time (`_fnr`, and any later table of the kind), and only
`CYRIUS_DCE=1` acts on what that pass concludes. A stale table under IR=3 alone shows only as a changed
`N unreachable fns` note, which no corpus gate compares, so the defect class is visible only with both flags.

## Fix direction

A combined `CYRIUS_IR=3 CYRIUS_DCE=1` corpus leg — in scripts/differential.sh beside its `CYRIUS_DCE=1` torture mode, or in
coverage_mode_corpus.sh's IR=3 leg — that requires exit 0 except for a pinned expected-failure list naming the two files
above with their issues; a pinned file that starts passing is reported, so the list shrinks as they are fixed. It costs a
full corpus build and run (~35 s at 8 jobs here), so it belongs with the existing serial corpus legs. Mutation: the review
fix's `_wp_fnr_shift` call dropped makes the leg RED on fn_redefinition_last_wins.tcyr (132).
