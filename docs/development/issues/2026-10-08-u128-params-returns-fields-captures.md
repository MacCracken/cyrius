# u128 beyond `+` / `-` / comparisons: parameters, returns, struct fields and closure captures — OPEN

**Status:** 🟡 **OPEN** — all four reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` (x86_64): a
`v: u128` parameter compares as a SIGNED 64-bit word and `&v + 8` reads the neighbouring frame slot; `: u128` as a
return type and as a struct field type are refused with a misleading "reserved keyword" error; a captured u128 reads
as the address of its env copy.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.6 D2 lane (u128 `+` / `-` / comparisons) and the 6.7.6 review (the capture, roadmap commit
d2d5309b); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — silent wrong comparisons / values on a parameter or capture (workaround: pass `&b` and
`load64` the words, or copy into a local `u128`); the refusals are loud but name the wrong thing.
**Affects:** cycc 6.7.6 (the parameter's compare: before 6.7.6 every u128 compare was signed 64-bit, locals too —
6.7.5 gives the same wrong answer for a local); the return / field refusals and the capture since `u128` existed.

## Summary

6.7.6 made `+`, `-`, comparisons, truth tests, `match` / `switch` and plain assignment on a `u128` carry all 128 bits —
for locals, globals and arrays. Four positions are still not a 16-byte value:

1. **A `v: u128` parameter is an 8-byte slot holding the low word** (the guide says so: "A `u128` parameter is an
   8-byte slot (the low word)"), but the callee also does not treat it as a u128: `v > 0xFFFFFFFFFFFFFFFF` is a SIGNED
   64-bit compare (`setg` against -1), so `big(0)` is true, where the guide promises "a comparison with a `u128` on
   either side compares all 128 bits, unsigned". `load64(&v + 8)` reads the next frame slot (on x86_64 the saved r15),
   not a high word.
2. **A `: u128` return type is refused** — `fn mk(): u128 { .. }` → `expected identifier, got reserved keyword 'u128'
   (cannot be used as an identifier; rename the variable/field/fn)`, which names a non-problem.
3. **A `u128` struct field is refused** the same way — `struct S { n; w: u128; }`.
4. **A u128 captured by a closure reads as the ADDRESS of its env copy**: `|q| { c == 5 }` is false for `c = 5`, and
   `c + 0` adds the address; `hi(&c)` inside the closure reads the copy's high word correctly.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn big(v: u128): i64 { if (v > 0xFFFFFFFFFFFFFFFF) { return 1; } return 0; }       # (1)
fn bigl(): i64 { var v: u128 = 0; if (v > 0xFFFFFFFFFFFFFFFF) { return 1; } return 0; }
fn hi(v: u128): i64 { return load64(&v + 8); }                                    # (1)
fn main(): i64 {
    alloc_init();
    var e = 0;
    if (big(0) != 0) { e = e | 1; }           # 0 > 2^64 - 1 is false
    if (bigl() != 0) { e = e | 2; }           # control: a local is right since 6.7.6
    var b: u128 = 5;
    store64(&b + 8, 7);
    if (hi(b) == 7) { e = e | 4; }            # documented: the parameter holds the low word only
    var c: u128 = 5;
    var f = |q| { if (c == 5) { return 1; } return 0; };                          # (4)
    var g = |q| { return c + 0; };                                                # (4)
    if (callptr(f, 0) != 1) { e = e | 8; }
    if (callptr(g, 0) != 5) { e = e | 16; }
    return e;
}
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?      # run from the repo root
```

Expected: 0. Actual: **25** (= 1 | 8 | 16). Each half was run on its own on 2026-10-08: `big(0)` = 1, `bigl()` = 0,
`f` → 0, `g` → not 5; `hi(b)` → 0 (the neighbouring slot), never 7. Items 2 and 3:

```cyrius
fn mk(): u128 { var b: u128 = 5; return b; }     # error:<source>:1:10: expected identifier, got reserved keyword 'u128' ...
struct S { n; w: u128; }                         # error:<source>:1:18: expected identifier, got reserved keyword 'u128' ...
```

`big`'s code on x86_64 (6.7.6): `mov rax,[rbp-0x30]; push rax; movabs rax,0xffffffffffffffff; mov rcx,rax; pop rax;
cmp rax,rcx; setg al` — a signed 64-bit compare; the parameter's slot is `[rbp-0x30]`, so `&v + 8` is `[rbp-0x28]`,
the saved r15.

## Root cause

1. A `u128` parameter gets one 8-byte slot and no u128 marking, so none of 6.7.6's `_W128_IS` / `_w128_*` paths
   (`src/frontend/parse_expr.cyr`, e.g. `_w128_pexpr` at `_PEXPR_IMPL`'s loop head, `_neg_int` at `:1299`) see it;
   the caller pushes the low word (`A u128 read where an integer is expected — an argument … — is its low word`).
2. / 3. The return-type and field-type parsers do not list `u128` among the type names they accept, so the token
   falls to the identifier check, whose message assumes a reserved word used as a NAME (not traced to the line).
4. The capture read (`parse_expr.cyr:2778`–`2795`) treats any multi-word capture (`_cl_cap_w > 1`; a u128 spans two
   words) as an aggregate whose value is its ADDRESS (`if (L64(&_cl_cap_w + cl_capi * 8) > 1) { SPSC(S, 1); return 0; }`
   at `:2793`), and nothing marks the read as a u128, so `==` and `+` operate on the address.

## Proposed fix

1. Pass a `u128` parameter as 16 bytes (two argument words, or by address as a > 8 B struct is) and mark the slot
   u128 so every 6.7.6 path applies — an ABI change on every backend (x86, aarch64, PE, Mach-O, cx); or, the smaller
   step, refuse `: u128` on a parameter by name until it is carried. Either changes what compiles / what a program does
   today — **the user's decision**, as is removing the guide's "8-byte slot" sentence.
2. / 3. Accept `u128` as a return type (rax:rdx — the 9–16 B pair ABI) and as a 16-byte field, or until then refuse it
   by name ("`u128` is not supported as a fn return / field type yet") instead of the reserved-keyword message.
4. Mark a u128 capture's read as a u128 value at its env words (as `_CL_CAP_OPTYPE` marks a captured struct), so
   `==` / `+` / truth tests take the 6.7.6 paths. A `tests/tcyr/crossos/` row per item (the u128 rows already there:
   `u128_add_sub_carry`, `u128_compare_all_bits`, …).
