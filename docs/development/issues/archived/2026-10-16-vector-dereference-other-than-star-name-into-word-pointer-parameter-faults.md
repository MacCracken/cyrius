# A `*V` dereference other than `* NAME` — `**ppb`, `*gp(pb)`, `*h.pv`, `*GPV`, `*(pb + 0)`, `*&b` — passed to a `*i64` / `*u8` / `**T` parameter still pushes lane 0 as the address (139), where the same argument into `*Pt` is refused by name (D31) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-10, `a3829d63d` (no new decision: 6.7.13's D31, the user, 2026-10-15: A — every vector value into a pointer of another kind is refused by name). The not-address-passed arm no longer judges a dereference by its tokens. `_sarg_vdo` watches the argument's `*` while it is parsed and pushed as before. `_dro_vnote` (in `_deref_read`) notes the operand's vector from its step word, and the argument is refused by name; `_svo_vderef` is retired, and the struct path is byte-identical. The filed repro `ri(**ppb)` and the five other filed spellings — `*gp(pb)`, `*h.pv`, `*GPV`, `*(pb + 0)`, `*&b` — gave 139 on x86_64, IR=3 and aarch64, 253 on cx, 5 on PE. Into `*i64`, `*u8`, `**T` or a by-value struct of 8 B or less — wrapped, in a closure, method or `#inline` fn, at top level — each is now refused once on all five legs and by the four hosts' native compilers: "cannot pass '*ppb' to a parameter that is not a pointer to its vector type in a call to 'ri'". `ri(*ppi)` of a `**i64` and `ri(*pps)` of a `**Pt` still pass their word. Rows: `simd_pointer_param.sh` OKD1 (the filed repro verbatim) – OKD14 (70 rows on five legs), OKDX (11 refusals counted by their words, three nested), and OKDK1 – OKDK4. Mutations M-OKD1 / M-OKD2 RED. Staged from the review: the refusal names the operand's last name ('*pb' for `*gp(pb)`; Low). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V3; the D31 bite 05dc6c58 and the
structs lane's D9 (a) in): each repro below compiles with no diagnostic and faults — x86_64 139, x86_64 `CYRIUS_IR=3`
139, aarch64 (qemu) 139, cx 253 (a guest fault), PE (wine) 5. The same arguments into an address-passed `p: *Pt` are
refused by name on all five (`cannot pass '*ppb' to a parameter that is not a pointer to its vector type in a call to
'rp'`), as is `ri(*pb)` itself.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean and faults on every target, no diagnostic.
**Kind:** bug — D31 A (the user, 2026-10-15: every vector value into a pointer of another kind is refused by name)
already decides it; the not-address-passed arm recognises only one spelling of the dereference.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane (V3), beside the deref-through bite
(issues/archived/2026-10-15-vector-deref-through-address-of-or-double-pointer-into-vector-pointer-param.md), which makes
`rp(*&b)` refused by the shared park (`_dlo_vec`) and leaves `ri(*&b)` here.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Hv { k; pv: *f64v2; }
var GPV: *f64v2 = 0;
fn ri(p: *i64): i64 { return *p; }
fn gp(p: *f64v2): *f64v2 { return p; }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var pb: *f64v2 = &b;
    var ppb: **f64v2 = &pb;
    return ri(**ppb);          # and ri(*gp(pb)), ri(*h.pv), ri(*GPV), ri(*(pb + 0)), ri(*&b): each the same
}
syscall(60, main());
```

```
x86_64 139, IR=3 139, aarch64 139, cx 253, PE 5      (each of the six; no diagnostic)
`rp(**ppb)` with `fn rp(p: *Pt)`: error:<source>:..: cannot pass '*ppb' to a parameter that is not a pointer to its
vector type in a call to 'rp'   (every target)
```

## Root cause

An argument to a parameter that is not address-passed (`*i64`, `*u8`, `**T`, a by-value struct of 8 B or less) takes
`_sarg_byval_small` → `_sarg_vec_other` (src/frontend/parse_fn.cyr), which judges a dereference BY ITS TOKENS:
`_svo_vderef` takes exactly `* NAME` with NAME a local whose step word names a vector. Every other `*V` operand — a
dereference (`**ppb`, typed by D9 (a)'s pin), a `: *V` call, a `*V` field, a `*V` global, pointer arithmetic, an
address-of a vector — is typed only once it is parsed (the step word, `_dlo_vec`), which the address-passed arm arms
(`_sarg_deref` / `_dro_vt_for`) and this arm does not. The word the dereference loaded (lane 0) is pushed.

## Fix direction

Give the not-address-passed arm the parse-time typing the address-passed one has (park the whole `*` argument and
refuse when `_dlo_vec` names a vector), or extend `_svo_vderef` to every operand D27's park types. Rows beside
simd_pointer_param.sh OK2 / OK4.
