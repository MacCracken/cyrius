# aarch64 `EADDRA_IMM` masks its operand to 12 bits → silent corruption for byte-array literals > 4096 elements

- **Filed**: 2026-06-07 (v6.0.91 closeout code-review pass)
- **Reporter**: cyrius self (closeout judgment workflow, adversarially verified)
- **Affects**: the **aarch64** backend's `EADDRA_IMM` (`src/backend/aarch64/emit.cyr`), reached for byte-array literals only via the peephole's `disp >= 4096` legacy fallback (`src/frontend/parse_decl.cyr`).
- **Severity**: LOW / latent. **PRE-EXISTING** — reproduced at `affc8ac4` (before the v6.0.88 peephole) on the pre-peephole aarch64 compiler, so it is **not** a regression from the .88–.90 cluster. **Does not bite in-tree**: no cyrius/stdlib source has a brace-literal byte-array initializer larger than 4096 elements (the `[8192]+` arrays in `parse_types.cyr` / `main_aarch64_native.cyr` are bare zero-init declarations, not `= { ... }` literals).

## Symptom

`fn EADDRA_IMM(S, n)` on aarch64 emits `add x0, x0, #imm12` with the operand
masked to 12 bits:

```
EW(S, 0x91000000 | ((n & 0xFFF) << 10));   # add x0, x0, #(n & 0xFFF)
```

For `n >= 4096`, `n & 0xFFF` drops the high bits. At exactly `n == 4096`,
`4096 & 0xFFF == 0` → `add x0, x0, #0` (a no-op), so the byte is written to
`&var + 0` instead of `&var + 4096` — silently corrupting the array.

Verified: a 4200-byte literal yields `load8(&huge[0]) == 81 == vals[4096]` on
**both** the new (v6.0.90) and the old pre-peephole aarch64 compiler.

## How it's reached (post-v6.0.88)

The byte-array peephole (`ESTOREB_IMM`) caps the aarch64 `STRB w0,[x1,#imm12]`
form at `disp < 4096` and **correctly** returns 1 (not-handled) for
`disp >= 4096`, so those bytes fall to the legacy per-byte chain — which calls
`EADDRA_IMM(S, b_i)` with `b_i >= 4096`. The peephole cap is correct; the bug
is in the legacy `EADDRA_IMM` it falls back to. (The x86 `EADDRA_IMM` is
unaffected — it emits a full disp32 `add rax, imm32`.)

## Fix (deferred to v6.1.x — changes aarch64 codegen, needs cross-OS reverify)

`EADDRA_IMM` needs a `> 4095` path on aarch64: either split into multiple
`add x0, x0, #imm12` (one per 12-bit chunk), or `movz`/`movk` the immediate into
a scratch + `add x0, x0, xscratch`. Mirror the cap reasoning in the x86 path.
Not a closeout byte-identical drop; pick up as a v6.1.x patch alongside the other
aarch64 codegen items. Tracked in `docs/development/roadmap-future.md`.
