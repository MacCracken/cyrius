# Integer vector bitwise ops, shifts and a byte table lookup, to unpack bit-packed data at SIMD speed

**Filed:** 2026-11-09 from tentib 1.5.1 (the 2-bit ternary weight store), cyrius 6.7.18.
**Status:** 🟡 **PROPOSED**. A capability gap with a measured consumer workaround. Nothing is blocked.
**Placement:** the maintainer's call. The minimal ask (A) is small and uniform across targets. The table lookup (B)
can follow on its own.
**Severity:** Performance. Every correct program still compiles and runs, but any kernel that reads packed bits
(2-bit or 4-bit fields, bit planes, nibbles) has to unpack them one scalar byte at a time. It then feeds them to
vector ops that are 10× faster than the unpack.
**Affects:**
- **tentib.** Its 2-bit weight store (`_tmf_simd2`, internal in 1.5.1) is the trigger.
- **Likely others.** Any bit-unpacking or byte-permuting kernel: compression bit readers, packed pixel formats,
  bitset and bloom-filter scans, hex / base64 encoding, UTF-8 validation. I have not surveyed these; they are the
  usual users of these instructions.
**Precedent:** `proposals/archived/2026-06-23-integer-simd.md`, also filed from tentib. It became the integer
vectors and `iv_dp8` (6.4.6 / 6.4.7, aarch64 at 6.4.30), and this asks for the next few ops in that family.

## Summary

cyrius's integer vectors have `iv_add` / `iv_sub` / `iv_mul` and the widening dot `iv_dp8`. They have no bitwise op
(`and` / `or` / `xor`), no shift and no byte permute. So a 16-byte vector of packed fields cannot be split into its
fields in-register. The fields must be extracted byte by byte in scalar code, and that extraction, not the
arithmetic, sets the speed.

This proposal asks, at minimum, for:

- **(A) bitwise ops and logical shifts by an immediate**, on the existing integer vector widths:

  ```cyrius
  iv_and(&dst, &a, &b, n, w);     # also iv_or / iv_xor           (w = 1 / 2 / 4 / 8, a literal, as iv_add)
  iv_shr(&dst, &a, k, n, w);      # logical right shift by k bits  (k a literal, 0 <= k < 8 * w)
  iv_shl(&dst, &a, k, n, w);      # left shift
  ```

  with value-form `i8v16` / `u8v16` (and the other widths') wrappers in `lib/simd.cyr`, as the arithmetic has.

- **(B), optional and separable: a byte table lookup**, `pshufb` / `tbl`:

  ```cyrius
  iv_tbl8(&dst, &table, &idx, n); # dst[i] = table[idx[i] & 15], table one 16-byte vector
  ```

The names and forms are suggestions. The ask is the operations.

## Trigger: tentib's 2-bit weight store

tentib serves ternary (b1.58) models whose weights are {−1, 0, +1}. Its serving kernel,
`ternary_matmul_free_simd`, keeps one i8 byte per weight and runs `iv_dp8` over 16 at a time. tentib 1.5.1 adds a
store with 2 bits per weight, a quarter of the memory. At b1.58 scale the weights are nearly all of a model's
memory, so on a 2 GB Raspberry Pi 4 a 2B-parameter model fits only at 2 bits.

Without bitwise vector ops, its kernel (`_tmf_simd2`, tentib `src/kernel.cyr`) unpacks every weight row in scalar
code through a 256-entry table, one code byte to four i8 weights:

```cyrius
while (j < Kp) { store32(wrow + j * 4, load32(&pk_lut + load8(src + j) * 4)); j = j + 1; }
# ... then the i8 kernel's own iv_dp8 over wrow
```

It is bit-identical to the i8 kernel, and slow. tentib 1.5.1's run of record on a Raspberry Pi 4 (Cortex-A72,
1.5 GHz, cyrius 6.7.18, median of 3, `docs/benchmarks.md` there) gives:

| one ternary layer, M = 1 row (a decode step) | i8 store (`iv_dp8`) | 2-bit store (scalar unpack + `iv_dp8`) |
|---|---:|---:|
| 128 × 128 | 19.7 µs | 105.1 µs (5.3×) |
| 256 × 256 | 52.7 µs | 385.4 µs (7.3×) |
| 512 × 512 | 172.4 µs | 1.48 ms (8.6×) |
| 768 × 768 | 350.2 µs | 3.29 ms (9.4×) |

- **The cost is the unpack.** At 768 × 768 the 2-bit layer is slower even than the plain f64 matmul (2.32 ms).
- **Whole model:** over a 32-row forward each weight row is unpacked once for 32 dots and the cost nearly vanishes
  (+6.6%). A one-token decode step pays it in full: 0.81 → 1.93 ms (2.4×).
- **x86_64:** a Ryzen 5800H shows the same shape, 6.8× at 128² and 13× at 768² (one run on a busy host).

## What the ops would buy

With (A), a 2-bit store can be laid out so that one 16-byte load holds 64 weights in four bit planes. Byte `i`
carries the codes of weights `i`, `i + 16`, `i + 32` and `i + 48`, in bits 0–1, 2–3, 4–5 and 6–7. This is the
layout family bitnet.cpp's I2_S uses. Unpacking then needs only per-byte shifts and masks:

```cyrius
# 64 weights from one 16-byte vector B of codes (0 = 0, 1 = +1, 2 = -1), plane j = 0..3:
#   p = (B >> 2j) & 0x01        the +1 lanes, as 0 / 1 bytes
#   q = (B >> (2j + 1)) & 0x01  the -1 lanes
#   w = p - q                   i8 weights {-1, 0, +1}            (iv_sub, which exists)
#   acc += iv_dp8(x + 16 j, w, 16)
```

- **Operation count:** about 5 vector ops per 16 weights, against 4 scalar table loads and 4 `store32`s for the
  same 16 today.
- **Expected effect:** that should bring the 2-bit layer within a small factor of the i8 one. tentib will measure
  it and report the number either way. It already gates any replacement for the unpack as bit-identical, in its
  suite and fuzz property P1.
- **What (B) adds.** It enables the other family, table-lookup kernels (bitnet.cpp's TL1 / TL2). Those precompute
  partial sums of a few activations against every weight combination and read them with `pshufb` / `tbl`,
  replacing the multiply-accumulate entirely. It is also the general byte permute behind hex / base64 and UTF-8
  validation.

## Lowering: every target already has the instructions

| op | x86_64 | aarch64 (NEON, base ARMv8.0) | cx |
|---|---|---|---|
| `iv_and` / `or` / `xor` | `pand` / `por` / `pxor` (SSE2) | `and` / `orr` / `eor` `.16b` | per-lane loop |
| `iv_shr` / `shl`, w = 2 / 4 / 8 | `psrlw` / `psrld` / `psrlq`, `psllw` … imm8 (SSE2) | `ushr` / `shl` `.8h` / `.4s` / `.2d` #k | per-lane loop |
| `iv_shr` / `shl`, w = 1 | `psrlw` + `pand` with `0xFF >> k` per byte (SSE has no byte shift) | `ushr` / `shl` `.16b` #k | per-lane loop |
| `iv_tbl8` (B) | `pand 0x0F` + `pshufb` (SSSE3) | `and 0x0F` + `tbl` (1 register) | per-lane loop |

- **No new ISA floor.** `iv_dp8` already lowers to `pmaddubsw`, an SSSE3 instruction, so `pshufb` does not raise
  x86's floor.
- **The Pi 4 has them all.** On aarch64 every instruction above is base NEON, present on the Cortex-A72 that has
  no dot-product extension.
- **Defined edge behaviour.** Masking `idx & 15` first gives `pshufb` (zero when bit 7 is set) and `tbl` (zero
  when ≥ 16) the same defined result.
- **Byte shifts on x86.** `psrlw` by k, then `pand` with a splat of `0xFF >> k`, gives the per-byte logical shift
  exactly. Bits shifted in from the neighbouring byte land only in the bits the mask clears. `shl` is symmetric,
  with `0xFF << k`.

## Tests that would pin it

- **Every width:** each op on all-ones, alternating-bit and random vectors, against a scalar reference per lane.
- **The edges:**
  - shifts by 0 and by the largest legal k;
  - the w = 1 shift on lanes whose neighbour has its high bits set;
  - `iv_tbl8` with indices 0, 15, 16 and 255;
  - an `n` that is not a multiple of 16, under the existing "exact or zero-padded" contract.
- **Every backend:** x86, aarch64 (under qemu, and on the cross-OS pi fixture as the `simd_ints_neon` tests run
  today), and cx.
- **A consumer check:** tentib can run its 2-bit kernel on the new ops behind its bit-identity gate (suite plus fuzz
  P1, 5,000 rounds) as an end-to-end check, as it did for `iv_dp8` at 6.4.7.

## What tentib does meanwhile

tentib 1.5.1 ships the scalar unpack behind internal names: correct, measured, and not exposed. Its roadmap's
1.5.x band records the choice for its maintainer:
- expose the 2-bit store as it is, a memory-for-speed trade, for models that fit only that way;
- or wait for these ops and expose a store that is also fast.

Nothing in tentib depends on this proposal's timing.
