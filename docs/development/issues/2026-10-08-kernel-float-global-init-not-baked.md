# In an x86 `kernel;` build a float-literal global scalar is a dead store after the program — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`. For the repro below the compiler prints its own "runs after the top-level program" warning. G's image bytes are 0 while H's hold 7. The disassembly shows `movabs $0x3ff8000000000000,%rax` plus the store to G coming right after `call kmain`. `var F: f32 = 2.5`, `var G: f64 = -1.5` and an untyped `var K = 1.5` behave the same way. Static image and disassembly only; not booted under qemu-system.
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog; the late-replay warning shipped in 6.6.16 (C6)); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — the kernel reads 0 for the global, and a kernel that never returns never runs the store. The compiler warns, and the workaround is to assign it in the program.
**Affects:** cycc ≤ 6.7.6, x86 `kernel;` builds (multiboot), not an EFI application that defines `efi_main`.

## Summary

An x86 `kernel;` build emits the deferred global-initializer replay AFTER its top-level program
(`src/main.cyr:1687-1691`, the v5.7.19 multiboot order). 6.6.16 fixed most of this by BAKING constants into
the image instead: integer and enum scalars (`_gvk_pre` / `_gvk_one`), struct literals including float
leaves (`_spc_try`), and array lists including f64 / f32 elements (`_gai_*`). A float-literal SCALAR is
still not baked. `_gvk_one` folds only through the integer folder `_CF_TRY`, so `var G: f64 = 1.5;`
stays a runtime store in the late replay and the program reads 0.

## Reproduction

`docs/development/issues/repros/2026-10-08-kernel-float-global-init-not-baked.cyr`:

```sh
R=docs/development/issues/repros/2026-10-08-kernel-float-global-init-not-baked.cyr
cat $R | build/cycc > /tmp/k
#   warning:<source>:7:5: in a kernel build the initializer of 'G' runs after the top-level program: …
readelf -S /tmp/k | grep bss             # G at .bss start (0x1000e8, file offset 0xe8)
xxd -s 0xe8 -l 16 /tmp/k                 # actual: G = 00…00, H = 07 00…  — expected: G = 00 00 00 00 00 00 f8 3f
objdump -D -b binary -mi386:x86-64 --start-address=0x54 /tmp/k | grep -A2 'call '
#   af: e8 …  call 0x65 (kmain)
#   b4: 48 b8 … movabs $0x3ff8000000000000,%rax   ← G's store, after the program
```

Expected: no warning. G's image bytes are 1.5's binary64 bits (an f32 global: the binary32 bits in the
low 4 bytes), as an f64 array element or struct field already is.

## Root cause

- `src/frontend/parse_decl.cyr:4264` `_gvk_one`: `_CF_TRY(S, ti, 5)` is the integer constant folder. A
  float literal leaves `_cf_ok == 0` and the entry is not baked. `_gvk_left` / `_gvk_warn` (4283 / 4297)
  then name it.
- The bits are already available: `_spc_try` (`:4316`) writes a float literal's binary64 bits into a float
  field, and the array path (`:2818`, `_gai_f32`) narrows to binary32. 6.7.2's const evaluator also
  produces f64 bits.

## Proposed fix

In `_gvk_one`, when the slot is a float scalar (an `f64` / `f32` annotation, or an untyped float-literal
initializer) and the initializer is a float literal, optionally negated, write its bits into `_vgsi_base`
the way the struct and array walkers do (binary32 for f32). Return 1 so `_gvk_left` stays silent. The
warning then fires only for what truly cannot bake. Add a gate row that builds the repro and checks the
image bytes plus the absence of the warning, next to the existing 6.6.16 C6 rows.
