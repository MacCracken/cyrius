# x86-macOS (Mach-O) cycc cannot compile byte-array literals — `var foo[N] = { ... };` → spurious parse error

- **Filed**: 2026-06-07
- **Reporter**: cyrius self (surfaced by the v6.0.88 cross-OS lib-test on `ach`)
- **Affects**: the **x86-macOS (Mach-O) `cycc`** only — `src/main_x86_macho.cyr` driver. **x86-Linux, aarch64-Linux (pi), aarch64-macOS (ecb), Windows-PE (cass) all compile byte-array literals fine.**
- **Severity**: LOW. Pre-existing; x86-macOS is Intel/EOL and its self-compile is already HELD (see [`2026-06-02-macos-x86-release-no-compiler.md`](2026-06-02-macos-x86-release-no-compiler.md)). The byte-array-literal feature (v5.11.51) targets gnoboot/EFI on x86, not macOS.
- **Status (2026-06-15): RESOLVED (stale) — verified on `ach` at cyrius 6.2.10.** Re-tested on real Intel-macOS hardware while picking this up for v6.2.11: the x86-Mach-O `cycc` (cross-emitted from current source) now **compiles AND runs `byte_array_literal.tcyr` 26/26** (was `compile rc=126` at .87). Broader x86-macho health confirmed on `ach` — `element_typed_array` 11/11, `gvar_static_init` 11/11 (the exact `PARSE_GVAR_ARR` path), `enum_generics` 31/31, `enums` 10/10, `exhaustive_match` 10/10 all green. The general parse-state corruption no longer reproduces. Fixed by intervening x86-macho runtime-state work between .88 and 6.2.10 — most plausibly the **v6.1.30 x86-macho argv prologue (reserve `r15` for the parked init-stack pointer)**, which is exactly the "clobbered runtime register → corrupted parser state" class; not bisected to a single commit (disproportionate for a Low/EOL issue whose symptom is provably gone on hardware). No code change needed in v6.2.11; closing.
- **Status (2026-06-07): OPEN, NOT a v6.0.88 regression.** Verified against the **released .87 source** on `ach`: it fails identically (`compile rc=126`), so the v6.0.88 byte-array peephole did **not** introduce this. The peephole is an emit-layer change and cannot cause a *parse* error.

## Symptom

On `ach` (macOS x86_64, Intel), the native Mach-O `cycc` compiling
`tests/tcyr/byte_array_literal.tcyr` aborts with:

```
error:2358: expected ';', got '='
  at fail: fn=164/8192 ident=5208/262144 var=189/8192 fixup=327/32768
```

It produces a 0-byte binary (hence the `LIBTEST_FAIL` / permission-denied
downstream). A trivial `syscall(60, 42);` program compiles + runs fine on the
same native Mach-O cycc, so Mach-O execution itself is healthy — the failure is
at **parse/compile time**, specific to this source on the x86-Mach-O build.

## Why self-host never caught it

`cycc`'s own source contains **no** `var x[N] = { ... }` byte-array literals, so
the byte-array **parsing** path (`PARSE_GVAR_ARR` in `src/frontend/parse_decl.cyr`)
is never exercised when cycc compiles itself. The x86-Mach-O cycc therefore
self-hosts **byte-identical** (verified green on `ach` every slot) while carrying
a latent miscompile of a parser path it never runs on itself — the classic
"green checkmark over untested codegen" class (cf. the macOS-rot incident,
`feedback_macos_windows_ci_gate_mandatory`).

## Likely cause

A function on the x86-Mach-O codegen path (parser or a lib helper it depends on)
is miscompiled by the x86-Mach-O `cycc` such that a normal `x = y;` assignment
mid-stream is misparsed as needing `;` before `=`. The error line (expanded
stream line 2358) lands inside the prepended stdlib includes, not the test's
byte-array lines — pointing at a *general* parse-state corruption triggered only
on the x86-Mach-O build, not at the byte-array grammar itself.

## Resolution path

Needs narrowing **on `ach`** (the x86-Mach-O cycc is the only repro; the
cross-emitter can't run on Linux — "mmap heap init failed"). Bisect which fn the
x86-Mach-O backend miscompiles by diffing its emitted code for `PARSE_GVAR_ARR`
and the surrounding parser fns against the x86-Linux build. Gated behind the
broader x86-macOS-self-compile HELD decision; pick up if/when x86-macOS leaves
HELD.
