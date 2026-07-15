# Win64: calls with ≥10 args silently corrupt argument 1 and never write the stack args

**Status:** ✅ **FIXED v6.4.64** (2026-07-14). **Severity:** was **P0** — silent wrong code, no
diagnostic, on a Tier-1 target. **Found:** 2026-07-14, by the maintainer pushing back on a
mis-filed sigil issue (see "How this hid" — that part matters more than the bug).

## The defect

`ECALLPOPS` (`src/backend/x86/emit.cyr`), `_TARGET_PE` branch, `n > 4`.

Win64 passes 4 args in `rcx/rdx/r8/r9`; the rest go on the stack at `[rsp+32..]` (above the 32 B
shadow), and the callee reads them at `[rbp+16+32+(pidx-4)*8]` (`ESTORESTACKPARM`). Because args are
pushed left-to-right (aN on top) but Win64 wants a5 at the LOWEST stack slot, the caller must
**reverse** the extras. The old code did that by shuttling them through a fixed 5-register table:

```
if (nextra >= 1) { pop rax; mov r10, rax }   # ... up to
if (nextra >= 5) { pop rax; mov r12, rax }   # r10/r11/r14/r15/r12 — FIVE registers
pop r9; pop r8; pop rdx; pop rcx             # the 4 register args
if (nextra == 1) { ... }  ...  if (nextra == 5) { ... }   # write-backs
```

`nextra = n - 4`, so **n ≥ 10 ⇒ nextra ≥ 6** falls off the end of its own table, two ways at once:

1. Only 5 of the ≥6 extras were popped → the following `pop r9/r8/rdx/rcx` read **shifted** stack
   slots → **`rcx` (argument 1) got the wrong value.**
2. No `nextra ==` branch matched → **the stack args were never written at all** → the callee read
   whatever garbage sat at `[rsp+32..]`.

Both silent. No error, no warning, wrong answers.

## Measured (real cass, before the fix)

| arity | result |
|---|---|
| 5–9 | OK |
| **10, 11, 12** | **exit=1 — argument 1 corrupted** |

x86-64 SysV and aarch64 were **unaffected** at every arity tested (5–20) — SysV had already been
migrated off the register shuttle to rsp-relative addressing at v5.6.24/v6.0.57 for exactly this
class of bug. The Win64 branch was simply never brought along.

## Live consumer

sigil 3.12.0 (`argon2id_into` = **10 args**, `argon2_hash_into` = **17**). A password KDF is the
worst possible place for this: a wrong hash is still a hash, so it fails silently-wrong.

## The fix (v6.4.64)

Drop the register shuttle; mirror what SysV already does. Uniform for every `n > 4`, no per-`nextra`
branches to run out of:

- Load `rcx/rdx/r8/r9` **in place** via `_emov_rsp_disp` (disp8/disp32 auto-select) — no pops.
- Carve the call frame **below** the pushed args, so the reversed copy's destination is strictly
  below its source and **cannot overlap at any arity** (an in-place reversal can't be done by a
  single ascending or descending shift — every order clobbers a slot a later read still needs).
- Reverse-copy the extras with `r10` (**caller**-saved; the v5.6.24 lesson is that r12–r15 are
  callee-saved and regalloc may pin caller locals to them → silent clobber).
- New `_pe_call_frame(n)` is the single shared formula for `ECALLPOPS`/`ECALLCLEAN` (32 shadow +
  nextra*8, 16-rounded, + 8 parity pad when n is odd — the old path got alignment for free by
  popping all n slots first; this pays for it explicitly).
- New `_esub_rsp_imm`/`_eadd_rsp_imm`: a 17-arg call needs a 136 B frame, past the imm8 ceiling.
- `ECALLCLEAN` reclaims `frame + n*8` (the args are now dead space above the frame, not popped).

## Verified

- Real cass arity sweep **5–20: all correct** (was: 10+ broken).
- **`cycc.exe` SELFHOST_OK on real Windows** — the compiler is itself full of >4-arg calls, so this
  is the load-bearing test.
- x86 self-host byte-identical; aarch64 unaffected.
- Permanent gate: `tests/tcyr/vr01_win64_stack_args.tcyr` (arity 5/9/10/17 + nested), which runs on
  real hardware via the release gate's `vr01_` glob.

## How this hid for ~a year — the part worth keeping

CLAUDE.md carried this as a **language rule**:

> *"fns take ≤6 args cleanly (register ABI); args 7+ go on the stack and have shown corruption —
> restructure instead."*

That sentence is a codegen bug wearing a style guide's clothes. Consequences:

1. **It was wrong in both directions** — 7–9 always worked; the real cliff was 10, on one target.
   Nobody re-measured it because it read as settled.
2. **It inverted responsibility.** On 2026-07-14 an agent (me) found sigil's argon2 at 9–17 args,
   cited this rule, and filed an issue **against sigil** proposing sigil restructure to a
   params-struct — i.e. asked a stdlib to contort around a defect in the compiler that compiles it.
   In the language repo. The maintainer caught it.
3. **The release gate structurally could not see it.** sigil is outside cycc's include closure, so
   cross-OS self-host never exercised argon2; and cycc's own PE calls happened to stay ≤9 args.

CLAUDE.md's rule is now replaced with the measured behavior plus the durable lesson: **if a rule in
this repo tells you to work around codegen, treat the rule as the bug report.** Cf.
`feedback_no_codegen_parking_in_v7` and the standing "when a gate blocks a legitimate feature, fix
the gate — never drop the feature" principle, which this violated for a year.
