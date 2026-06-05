# cyrius: asm-block global-symbol pseudo for fixup-aware loads

**Filed:** 2026-05-21
**Reporter:** sigil (AGNOS trust-verification library, v3.2.0 prep)
**Cyrius version at time of report:** 6.0.1
**Severity:** **P3 — defensive enhancement.** No project is
currently blocked; sigil 3.2.0 shipped a runtime self-test gate
that catches the symptomatic class of bug at boot time. The
upstream feature requested here would let downstream stop coupling
asm-block parameter loads to the cyrius prologue layout entirely
— a structural fix rather than a runtime fallback.
**Status:** ✅ RESOLVED in v6.0.67 — shipped **Option 2 `param_load(reg, idx)`**
(the lower-surface-area fix for the parameter-load bug class). Inline asm loads a
parameter from its ACTUAL prologue slot (disp = -(idx+1+_cur_fn_regalloc)*8) — x86
`mov reg,[rbp+disp]`, aarch64 `ldur reg,[x29,#disp]` — so downstream stops coupling
asm-block param loads to the cyrius prologue layout. Byte-identical proof: migrating
cyrius's own `lib/atomic.cyr` + `lib/thread.cyr` off their `[rbp-N]`/`[x29,#-N]`
literals produced a byte-identical cycc. `param_load.tcyr` 5/5 on x86 + aarch64.
**Sigil follow-up** (its committed plan): migrate `aes256_encrypt_block_ni` /
`_aes_ni_cpuid_probe` / `_sha_ni_compress_one` / `_sha_ni_cpuid_probe` off the
`[rbp-N]` byte literals to `param_load`, compiled by a ≥6.0.67 cycc. **Option 1
`sym32(name)`** (arbitrary-global PC32 fixup, the general long-term shape) left as a
future enhancement — no current consumer needs the arbitrary-global case. See CHANGELOG [6.0.67].

## Summary

Cyrius's `asm { … }` block today emits a raw byte stream plus a
fixed whitelist of mnemonics (`cli`, `sti`, `hlt`, `nop`, `cpuid`,
`lgdt`, `lidt`, `mov` (cr), `invlpg`, `int`, `in`, `out`, `ltr`,
`pushfq`, `popfq`, `wrmsr`, `rdmsr`, `iretq` — see
`src/backend/x86/emit.cyr:2284`). There is no syntax for
referencing a Cyrius global by name from inside the asm block
with a proper relocation, so any load from a global has to go
through a stack-relative path: spill the global to a local via
Cyrius IR, then read `[rbp-N]` from the asm body using a
hardcoded `N` that matches the current prologue's local-slot
layout.

That coupling is the root of the recurring class of bugs typified
by [sigil/issues/2026-05-10-cyrius-510-asm-stack-frame-drift-breaks-ni-paths.md](https://github.com/MacCracken/sigil/blob/main/docs/development/issues/2026-05-10-cyrius-510-asm-stack-frame-drift-breaks-ni-paths.md)
— cyrius 5.10.x's expanded prologue shifted local slots and
sigil's AES-NI / SHA-NI dispatch (which encoded `mov rdi,
[rbp-8]` etc. as byte literals) read the wrong values. The bug
silenced again in cyrius 6.0.1 because the prologue happens to
match the hardcoded offsets again, but every future prologue
change is a potential silent regression for every downstream
that ships inline asm.

## Concrete request

Add a pseudo-op recognised inside `asm { … }` that emits a
fixup-aware memory operand against a named Cyrius global. Two
shapes worth considering:

### Option 1 — Symbol literal at byte-stream position

Like the existing raw-byte stream, but with a special syntax for
"emit a `disp32` that the linker will resolve to `&_my_global` at
fixup time":

```cyrius
asm {
    # mov rdi, [rip + _aes_ni_arg0]
    0x48; 0x8B; 0x3D; sym32(_aes_ni_arg0);
    # mov rsi, [rip + _aes_ni_arg1]
    0x48; 0x8B; 0x35; sym32(_aes_ni_arg1);
    # mov rdx, [rip + _aes_ni_arg2]
    0x48; 0x8B; 0x15; sym32(_aes_ni_arg2);
    # ...rest of the asm body...
}
```

`sym32(name)` would:
1. Emit four placeholder zero bytes at the current code position.
2. Register a fixup record `(codebuf_offset=CP, kind=PC32, var_index=&name)`.
3. The existing fixup pass in `src/backend/x86/fixup.cyr`
   resolves the disp32 to `&name - (codebuf_offset + 4)` after
   layout is final.

The `(kind=PC32)` distinction matters: existing fixups in cyrius
are mostly `ABS32` (absolute) or `ABS64`. A PC-relative-32
variant for RIP-addressing already lives in the x86 backend
implicitly (every relative `jmp` / `call` emits one), so the
plumbing is largely there — just needs a user-accessible front
door.

### Option 2 — Param-by-ordinal pseudo

Less general, more targeted at the parameter-load shape. A
pseudo that emits "load this register from the Nth parameter,
regardless of where the prologue spilled it":

```cyrius
asm {
    param_load(rdi, 0);     # equivalent to current `[rbp-8]`
    param_load(rsi, 1);
    param_load(rdx, 2);
}
```

The codegen resolves `param_load(reg, idx)` at emit time using
the same disp the prologue chose for that param (see
`src/frontend/parse_fn.cyr:2403` — `idx = -ra_d/8 - 1 - N`). The
asm body never bakes the disp into a byte literal; cyrius emits
the correct disp byte at compile time per the active prologue.

Option 2 is the lower-surface-area fix for the specific bug
class. Option 1 is more general (lets asm blocks reach any
global, not just parameters) and is the right long-term shape.

## Why this matters for downstream stability

Three downstream projects today carry `[rbp-N]` asm patterns:

| Project | Files | Affected paths |
|---|---|---|
| **sigil** | `src/aes_ni.cyr`, `src/sha_ni.cyr` | AES-NI block encrypt + CPUID probe, SHA-NI compress + CPUID probe |
| **cyrius stdlib** | `lib/atomic.cyr`, `lib/thread.cyr` | CMPXCHG / XADD / clone / clone-aarch64 |
| (others) | TBD | Any future module that needs inline asm with > 0 parameters |

All three break identically if a future cyrius prologue change
shifts local slots. Sigil's 3.2.0 ship works around this with a
runtime self-test gate that downgrades the NI dispatch to the
software path when the FIPS 197 / FIPS 180-4 vectors don't
match — but that only catches the *wrong-output* failure mode.
The *SIGILL on garbage pointer* failure mode (the original 2.9.1
→ 3.0.x bug shape) cannot be caught without cyrius signal-handling
primitives. The cleanest defence is structural: don't bake the
local-slot disp into asm byte literals in the first place.

## Suggested placement

Cyrius's 6.0.x line shipped the cc6 ABI overhaul + "REAL TYPE
SYSTEM"; the 6.1 or 6.2 cycle's natural fit is the asm-side
ABI: clean up the asm-block surface so downstream inline asm
isn't a hidden coupling to private cyrius layout choices. Both
options above are independent of the existing asm grammar
(additive, not breaking).

If neither lands in the near term, the runtime-self-test pattern
sigil ships in 3.2.0 is the recommended workaround for any other
downstream that wants to harden against prologue drift — see
sigil `src/aes_ni.cyr:_aes_ni_self_test` and
`src/sha_ni.cyr:_sha_ni_self_test`.

## What downstream commits to if the pseudo lands

Sigil will migrate `aes256_encrypt_block_ni` /
`_aes_ni_cpuid_probe` / `_sha_ni_compress_one` /
`_sha_ni_cpuid_probe` off the `[rbp-N]` byte literals in a
3.2.x or 3.3 follow-up patch. The self-test gate stays — it's
useful defence-in-depth even after the structural fix lands,
and costs essentially zero on the happy path (one CPUID + one
block encrypt at process start, cached for the lifetime of the
process).

Cyrius stdlib's `atomic.cyr` / `thread.cyr` would benefit
identically; their migration is a smaller patch (no FIPS-vector
self-test needed for syscall thunks).
