# In an x86 `kernel;` build a float global whose constant initializer is not a bare literal (`= CF`, `= (1.5)`, `= 1.5 + 1.0`) is still a dead store after the program — RESOLVED

> ✅ **RESOLVED in v6.7.15** (FE-16, `549b39651` — D46 (the user, 2026-10-18: Keep 6.7.14's float-literal bake) applied to a constant f64 expression, as the filed fix asks. `_gvk_flt` asks `_gvk_fx`: a token pre-scan (float literals, f64 consts, `( )`, `+ - * /`), then the const evaluator at the top context, quietly (`_ce_top_quiet`); an f64 result is baked, binary32-rounded for an f32. The filed repro (`CYRIUS_ELF64_KERNEL=1`) builds with no warning and exits 100 (it warned at 3:5 / 4:5 / 5:5 and exited 1, G reading 0); `= -CF`, f64 arithmetic of consts, an untyped `var K = CF;` and an f32 `= CF` likewise. In any build an earlier initializer's read sees the value and an earlier call's write is kept. A call, a NaN and arithmetic with an integer or enum operand stay late and named (the mixed shapes filed, 6.7.16, `2026-10-18-kernel-float-global-mixed-int-operand-left-late.md`). Rows: `kmode_enum_initializer_baked.sh` RC (the filed repro's shapes and more), KC, RS check 9; `const_init_bake_and_fold.sh` T9 – T12 (`tests/tcyr/crossos/zone_float_constant_initializer.tcyr` on x86_64 / qemu / cxvm / wine; 13 of 13 there and on pi, ecb, ach and cass); mutations RED as the gate's ledger says. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F4, after 3f8bb9b6,
which bakes a float scalar's float LITERAL, `-` optional — issues/archived/2026-10-08-kernel-float-global-init-not-baked.md),
x86_64 (CYRIUS_ELF64_KERNEL=1, run as a Linux process).
**Placement:** 6.7.15 — repair 5 (frontend lane, wave 1, unit F5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F4: the filed issue's surface (and its fix) is "a float
literal, optionally negated"; the warning's own advice ("use a constant") does not hold for an f64 const.
**Severity:** Low — a `kernel;` build's program reads 0 for such a global and the compiler warns by name; the bare
literal (`var G: f64 = 1.5;`) is the workaround.
**Kind:** platform (x86 kernel builds; the bake is target-independent).

## Reproduction

```cyrius
kernel;
const CF = 1.5;
var G: f64 = CF;
var P: f64 = (1.5);
var A: f64 = 1.5 + 1.0;
var H = 7;
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(load64(&G), 0x3FF8000000000000, 1);
ck(load64(&P), 0x3FF8000000000000, 2);
ck(load64(&A), 0x4004000000000000, 3);
syscall(60, 100);
```

```sh
CYRIUS_ELF64_KERNEL=1 build/cycc < r.cyr > r && chmod +x r && ./r; echo $?
# warning:<source>:3:5: in a kernel build the initializer of 'G' runs after the top-level program: ... (use a constant, ...)
# warning:<source>:4:5: ... 'P' ...
# warning:<source>:5:5: ... 'A' ...
# exit 1   (G reads 0; expected 100: every value in the image, no warning)
```

## Root cause

`_gvk_one` (src/frontend/parse_decl.cyr) bakes an integer constant through `_CF_TRY` and, since 6.7.14, a float
scalar's bare float literal through `_gvk_flt` (`-`? FLOAT `;`). An f64 const name, a parenthesized literal and f64
constant arithmetic are constants 6.7.2's const evaluator already computes as binary64 bits, but neither path asks it,
so the entry stays a replayed store — after the program in an x86 kernel build. (On every other build the value is
right, stored at startup.)

## Proposed fix

In `_gvk_flt`, evaluate a float scalar's initializer with the const evaluator when it is a constant f64 expression
(an f64 const, parentheses, f64 arithmetic of constants) and bake its bits as the literal's are (binary32 rounded
for an `f32` global, `_gai_f32`). Rows beside kmode_enum_initializer_baked.sh RS: the three shapes above read their
values with no warning; a call stays late and named.
