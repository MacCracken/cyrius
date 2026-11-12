# Struct values cost 2.5× and f64v4 lanes 3.5× over f64 locals in a particle-pair loop — open (performance finding)

**Status:** 🟡 **OPEN** — measured on cyrius 6.7.18 (x86_64 Linux ELF), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M0 step 9, probe 2). impetus measured the same 2.5× on its
contact kernel (154 ns vs 56–63 ns; its `port-parity.md` §4.2, listed under "Compiler" in its port plan §8).
**Reporter:** pravash 2.0.0 port (`pravash/docs/development/port-parity.md` §4.2).
**Severity:** **Medium (performance).** Results are correct, the same bits in every form. But the readable forms are
2.5–3.5× slower, so hot loops are written on scalar locals.

## Summary

One SPH density pass, 4,096 particles and 141,376 candidate pairs. Per pair: `d = x_i − x_j`; `r² = d·d`; if
`r² < h²` then `ρ += m_j · (h² − r²)³`. Four forms, all giving the same bits (digest `0xb7fa6660c11c64c7`), timed in
three pinned runs on a quiet box:

| Form | Per pass | Per pair |
|---|---|---|
| a typed stride array of 144-byte records, fields read into `f64` locals | 1.83 ms | 12.9 ns |
| `f64` columns, `f64` locals | 2.01 ms | 14.2 ns |
| the same records with a struct value `struct V3 { x: f64; y: f64; z: f64; }` and an overloaded `-` (`var d: V3 = pi.pos - pj.pos;`) plus a `len2(d)` helper | **4.6 ms** | **32.5 ns** |
| `f64v4_make(x, y, z, 0)` per particle, `f64v4_sub`, `f64v4_mul`, three `f64v4_lane*` reads | **6.45 ms** | **45.6 ns** |

What the struct-value form adds, as impetus found:
- the 24-byte return through the hidden pointer;
- the field copies.

The f64v4 form pays for its `f64v4_make` (four loads and a pack) and three lane extractions on every pair. Those
outweigh one packed subtract and one packed multiply.

## Reproduction

pravash's bench: `pravash/scripts/probes/p2_layout.bcyr`:

```sh
cd pravash && taskset -c 15 cyrius bench scripts/probes/p2_layout.bcyr
```

## Ask

Performance work, measured against the same bench:
- **Struct values:** return small structs in registers (two xmm for 16 bytes, three for 24), or let `#inline`
  overloads and helpers keep their fields in registers. The goal is the `f64`-locals form's speed for `pi.pos - pj.pos`.
- **f64v4:** a cheaper `f64v4_make` from three or four f64 locals (a gather or insert sequence), and lane reads that
  don't spill.

These are not blockers: pravash writes its hot loops on `f64` locals. Its readable struct-value form waits for this.
