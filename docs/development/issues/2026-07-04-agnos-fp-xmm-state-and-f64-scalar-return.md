# agnos FP arc — XMM-state prerequisites + f64-scalar-return / f64vN-constructor gaps

**Filed:** 2026-07-04
**Filed by:** agnos-side coordination (agnosticos), for the naad FP-enablement arc
**cyrius at filing:** 6.4.2   **agnos at filing:** 1.52.8
**Consumer driving this:** naad 2.1.0 (f64 audio synthesis: oscillators / filters /
envelopes / PolyBLEP; deps hisab + goonj). Downstream: nidhi (f64 sample playback),
on-device ML (rosnet / tyche / hisab — all f64).

This is a **coordination / roadmap** doc, not a defect report. The blocking work for
naad-on-agnos is **kernel-side** (agnos must save/restore XMM and enable SSE). This
doc records the **cyrius-side** facts that gate the *ergonomic* and *SIMD* future of
that arc, with exact reproductions, so the cyrius agent can sequence them against its
own "more int/SIMD support soon" plans.

---

## 0. The load-bearing finding (so nothing is mis-sequenced)

`cyrius build --agnos` lowers scalar `f64_*` builtins to **hardware SSE**, and naad's
f64 path is carried as **f64 bit-patterns in `i64`-typed variables** (soft-typed, not
`: f64` in signatures). Confirmed empirically 2026-07-04:

- A program mirroring `osc_next_sample` — `var sample = 0; sample = f64_mul(...);
  return sample;` with return type `i64` — **builds clean for `--agnos`** and
  disassembles to `mulsd %xmm1,%xmm0`, `roundsd`, and `movq %rax,%xmm0` /
  `movq %xmm0,%rax` shuttles (331 SSE/xmm instructions in a ~20-line program).
- naad has **zero** `): f64` / `): f64v2` / `): f64v4` return signatures across
  `src/*.cyr` and `dist/naad.cyr` (grepped: 0 sites). Every public entry
  (`osc_next_sample`, filter/envelope steps) returns `i64`.

**Consequence:** the cyrius return-type restriction (§1) and the f64vN constructor
gap (§2) **do NOT block naad**. naad compiles for agnos *today*. What stops naad on
agnos is purely that agnos ring-3 has no XMM state enabled — the first `movq %rax,%xmm0`
`#UD`s. That is an **agnos kernel** fix, tracked agnos-side. This doc exists so the
cyrius items below are scheduled on their own merits (ergonomics + the int-SIMD
future), NOT treated as naad blockers and rushed.

---

## 1. Scalar `f64` is not an allowed function RETURN type

### Reproduction (cyrius 6.4.2)
```cyrius
fn get_sample(): f64 {
    return f64_from(1);
}
```
```
$ cyrius build --agnos src/f64ret.cyr build/f64ret
compile src/f64ret.cyr -> build/f64ret [x86_64] error:<source>:1: fn return type must be struct or i8/i16/i32/i64/Result/Option/Tagged/cstring/f64v2/f64v4 ra:
FAIL
```

Exact error string (verbatim, for grep-ability):
> `fn return type must be struct or i8/i16/i32/i64/Result/Option/Tagged/cstring/f64v2/f64v4`

Note the allow-list **includes `f64v2` / `f64v4`** (128/256-bit XMM/YMM vectors) but
**excludes scalar `f64`**. A single `double` cannot be returned in `xmm0` today; a
*pair* of doubles (`f64v2`) reportedly can (modulo §2).

### Impact
- **naad: none today** (returns `i64` bit-patterns — see §0).
- **Ergonomic debt going forward:** the i64-boxed-f64 convention works but is a
  readability tax and an easy correctness trap (a plain `+` on a boxed f64 silently
  does integer add on the bit-pattern; only `f64_add` is correct). If cyrius ever
  wants naad et al. to read as `fn osc_next_sample(self): f64`, scalar-f64-return is
  the unlock.
- **Ask (roadmap, not urgent):** allow scalar `f64` as a return type, returned in
  `xmm0` per SysV. Would let the f64 libraries drop the i64-box idiom. Low priority
  relative to §3 — flagged only so it is on record with a repro.

---

## 2. `f64v2` / `f64v4` intrinsic constructors are undefined symbols

### Reproduction (cyrius 6.4.2)
```cyrius
fn pack(a, b): f64v2 {
    return f64v2(a, b);
}
fn main(): i64 {
    var v = pack(f64_from(1), f64_from(2));   # force `pack` reachable
    return 0;
}
```
```
$ cyrius build --agnos src/v2r.cyr build/v2r
warning: undefined function 'f64v2'
warning: undefined function 'f64v2' (call site may be unreachable)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
FAIL
```

`f64v2` / `f64v4` are accepted as **types** (return-type allow-list, §1) and as
**variable declarations**, but the **value constructor** `f64v2(a, b)` resolves to no
symbol — it is treated as an ordinary (undefined) function call. Note: when `pack` is
*unreachable* (DCE removes it) the build "succeeds" with only a warning — so this gap
is easy to miss unless the vector path is actually exercised. That earlier "green
build" is a DCE artifact, not a working constructor.

### Impact
- **naad: none today** (scalar-only path).
- **Blocks the SIMD future** (§3): a vectorized inner loop (2×/4× f64 per op) needs a
  way to *materialize* a vector from scalars / memory. Without a constructor +
  matching extract, f64v2/f64v4 are declarable but not constructible.
- **Ask (roadmap):** intrinsic constructors `f64v2(a,b)` / `f64v4(a,b,c,d)`, a
  broadcast/splat form, and lane extract (`f64v2_lane(v, i)` or similar), lowering to
  `unpcklpd` / `movapd` / `vbroadcastsd` / `vextractf128`. Sequence this **with** the
  int-SIMD work (§3) — same register file, same emit paths.

---

## 3. The real roadmap ask: XMM is the shared substrate for int-SIMD + float-SIMD + ML

The agnos kernel arc that unblocks naad is **"enable and context-switch the XMM
register file"** — CR4.OSFXSR/OSXMMEXCPT + CR0.MP/EM + `fninit` on every core, plus
per-proc `fxsave`/`fxrstor` across context switches. **That same kernel layer enables
ALL of these, because they all live in XMM/YMM:**

1. scalar `f64` (naad, hisab, goonj — SSE `mulsd`/`addsd`, already emitted today)
2. **integer SIMD** (SSE2 `paddq`/`pmulld`/`pand`/… — the "more int/SIMD support
   soon" that cyrius is planning)
3. float SIMD (`f64v2`/`f64v4` — §1/§2, packed `mulpd`/`vmulpd`)
4. the on-device-ML future (rosnet/tyche tensors, hisab linalg — all f64, and the
   obvious beneficiaries of int-SIMD for tentib-style ternary/int8 kernels)

**Coordination point for cyrius:** when the int-SIMD instruction set lands, it will
`#UD` on agnos ring-3 for the *exact same reason* scalar f64 does today (XMM
disabled). So:

- There is **one** kernel prerequisite (XMM state safety), not one-per-feature. The
  agnos arc is being framed as "the FP/XMM-state layer," explicitly **not** "an audio
  detour," precisely so int-SIMD inherits it for free.
- **Request to cyrius:** when scoping the int-SIMD types, please note in that work's
  doc that the runtime prerequisite on agnos is the same XMM-state layer, and if
  possible land the f64v2/f64v4 constructors (§2) in the same arc so the kernel side
  can validate scalar-f64, int-SIMD, and float-SIMD against **one** `fxsave` proof
  instead of three.
- **No cyrius change is required to start the kernel arc.** Scalar f64 (naad) is
  sufficient to build, validate, and iron-prove the XMM-state layer end to end. §1/§2
  are the *next* consumers of that layer, not blockers of it.

---

## Summary table

| Item | Blocks naad now? | Kind | Priority |
|------|:---:|------|----------|
| §1 scalar `f64` return type | No (naad boxes in i64) | ergonomics | low, roadmap |
| §2 `f64v2`/`f64v4` constructors | No | SIMD enablement | med, land with int-SIMD |
| §3 int-SIMD types | No (future) | new capability | cyrius's own cadence |
| **agnos XMM-state layer** | **YES — this is the blocker** | **agnos kernel** | tracked agnos-side |

The single actionable coordination request: **sequence §2 into the int-SIMD arc**, and
**note the shared agnos XMM-state prerequisite** in that arc's doc. Everything else is
on record for reproducibility; nothing here needs to move before the agnos kernel arc
starts.
