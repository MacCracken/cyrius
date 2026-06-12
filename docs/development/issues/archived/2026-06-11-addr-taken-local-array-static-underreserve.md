# Local-array byte-vs-slot convention footgun (address-taken `var a[N]` is N bytes, not N slots)

**Filed:** 2026-06-11 · **Re-diagnosed 2026-06-12** (the original "off-by-one
under-reserve" read was wrong — see below)
**Severity:** MEDIUM — DX footgun, not a codegen bug; the compiler behaves as
documented, but the convention bit a consumer hard (daimon: silent static
corruption → *every* HTTP route 404'd)
**Component:** language convention — local fixed-array sizing (`var a[N]`)
**Reported by:** daimon 1.2.6
**Upstream repro (immutable):** `daimon/docs/development/issues/2026-06-11-cyrius-addr-taken-local-array-static-overlap.md`
**Roadmap:** v6.2.x — Language Refinements (a deliberate convention decision, NOT a
v6.1.x patch)

## Re-diagnosis (disassembly, cycc 6.1.41)

The daimon report (and the first cyrius-side read) said cycc reserves `(N-1)*8`
bytes — an off-by-one. **That is incorrect.** Disassembling the minimal repro:

```
movabs rax, 0x400178        ; &parts  (static .bss)
.bss    400178  00000000 00000000     ; parts = 8 bytes
.rodata 400180  20 00                  ; " " literal, 8 bytes after parts
```

`var parts[4]` got **8 bytes**, not 24 — i.e. **N bytes rounded to 8**, the
**documented local-array convention**: a *local* `var x[N]` is N BYTES (rounded to
8), a *global* `var x[N]` is N i64 SLOTS (N*8 bytes). (See the durable note
`feedback_var_array_byte_sized`; the `parse_decl.cyr:612` "cap is [N]*8 bytes"
message is the *global*/byte-list path.) So `parts[4]` = 8 bytes; daimon's
`store64(&parts + 8/16/24, …)` treats it as 4 i64 slots (32 bytes) and runs off the
end into the next static object. The compiler did what it's documented to do —
daimon's code (and any stdlib doing `store64(&local_arr + i*8)`, e.g. an
`argv_buf[4]`) is using the *global* slot convention on a *local*.

## Why this is NOT a v6.1.x codegen fix

"Reserve `N*8`" would silently re-define the local-array byte convention for
everyone who relies on it (byte buffers, `var foo[N] = { bytes }`). That's a
language change, not a patch.

## The real decision (v6.2.x — Language Refinements)

Unify the convention deliberately. Options:
1. **Make local `var a[N]` = N i64 slots** (consistent with global + the widespread
   `store64(&a + i*8)` idiom). Costs stack/static (8× per local array); must keep
   the byte-list initializer + byte-buffer semantics working. Removes the footgun.
2. **Keep local = N bytes**, but **lint** the `store64(&local_arr + i*8)` idiom (an
   address-taken local fixed array written past its byte capacity) as a warning, and
   audit stdlib for it.
3. A distinct slot-array spelling (e.g. `var a: i64[N]`) vs byte buffer.

Either way: **audit stdlib + consumers** for address-taken local fixed arrays
written per-slot — they're the exposed surface.

## Consumer guidance (now)

Size local fixed arrays by BYTES (`var parts[32]` for four i64 slots), or use a
global / `alloc()` buffer. daimon already did the right thing (inline octet
compute, no address-taken local array).

## Resolution (v6.2.1)

**Decision: Option 3 — distinct element-typed spelling.** Added
`var a: T[N]` = N elements of T (`N * sizeof(T)` bytes), sized identically in
function and top-level scope. `i64[N]` is the unambiguous **slot** spelling that
fixes the footgun; `u8[N]` an explicit byte buffer; widths i8..i64 / u8..u64 /
u128. Bare `var a[N]` keeps its legacy per-scope meaning (byte buffer in a fn,
slots at top level). Pure **frontend** change — the element width threads into the
`0x12A000` var-size table and every backend (x86/aarch64/macho/pe/cx) inherits it.

**Stdlib + compiler audit (the issue's action item).** A fan-out audit confirmed
**17** address-taken local slot-arrays written past their byte capacity. Fixed in
v6.2.1:
- **cycc itself (5):** `PARSE_SWITCH`/`PARSE_MATCH` jump tables (`ends`×3,
  `seen_vcnt`) capped at 32 slots not 256; `_fc_simd_table` (OOB at ≥1 SIMD arg) →
  all `i64[N]`. Two-step bootstrap converged byte-identical.
- **cyrius-native stdlib (5):** `regex` `splits`/`splits2`, `pwd`/`grp`
  `field_starts`, `net` `sa` sockaddr.
- **Ecosystem stdlibs (8 sites, held for release):** patched in *source* —
  sigil ×6 (sgx/snp/tdx attestation cert chains; the source check found one the
  fold-copy audit missed), sakshi `ts` timespec (hot path), agnosys `bc_buf` fmt
  scratch. Held for each lib's release + re-fold — see
  `2026-06-12-ecosystem-lib-daimon-class-refold.md`.

**Verified:** self-host byte-identical (x86 one-step + two-step internal); check.sh
89/89; cross-OS 4/4 (pi/ecb/ach/cass `SELFHOST_OK`); differential corpus 252/252;
tcyr 175/175 (+`element_typed_array.tcyr`, +40-case switch); cross-arch aarch64
(qemu) + PE (wine); bench self_compile 509 ms / cycc 1,063,800 B (+8,016 B).

## Status

**RESOLVED v6.2.1.** Archived.
