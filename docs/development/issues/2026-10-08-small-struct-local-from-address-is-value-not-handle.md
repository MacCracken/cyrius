# An 8-byte struct local initialised from an address is a VALUE holding the address, not a handle — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` (x86_64). ⚠ The
roadmap framed this as a closure-capture inconsistency (`_CL_CAP_BASE_RA`); the live compiler shows the capture is
consistent with the declaration — the asymmetry is at the DECLARATION, closure or not.
**Placement:** 6.7.9 — features: B7 + P5-B (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 B8 review (roadmap commit e95f295d: "a captured 8-byte pointer-mode struct local is copied
into the closure env while a 16-byte one is captured by reference"); filed 2026-10-08 from roadmap.md.
**Severity:** Medium
**Affects:** cycc 6.6.5 – 6.7.6 (`MARK_SMALL_STRUCT`, the ≤ 8 B by-value policy)

## Summary

`var hq: H = alloc(16);` (a 16 B struct) declares a *handle*: the slot holds the address and `hq.a = 7` writes the
heap object (the guide's handle rule, "for a plain struct over 8 bytes"). The same spelling for an 8 B struct,
`var q: S8 = alloc(8);` — or `var q: S8 = gp();` with `fn gp(): *S8` — declares an INLINE 8-byte struct whose one
field is initialised to the address: `q.v` reads the address back, and `q.v = 5` overwrites the slot and never
reaches the heap. No diagnostic either way. A closure capture follows the declaration (capture by value copies the
8 B value; the 16 B handle's one-word capture is the address), which is what the B8 review observed. The guide
says structs of 8 bytes or less "are unchanged" by the handle rule but never says that a handle-style initialiser
turns into the struct's value.

## Reproduction

```cyrius
include "lib/alloc.cyr"
struct S8 { v; }
struct H { a; b; }
var h8 = 0;
var h16 = 0;
fn run(): i64 {
    h8 = alloc(8);
    h16 = alloc(16);
    var q: S8 = h8;          # same result with alloc(8) or a `fn gp(): *S8` call
    var hq: H = h16;
    q.v = 5;
    hq.a = 7;
    var f = |d| { q.v = q.v + d; hq.a = hq.a + d; return 0; };
    callptr(f, 10);
    return load64(h8) * 100 + load64(h16);   # heap words behind each local
}
alloc_init();
var r = run();
syscall(60, r % 256);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Actual: exits 17 — `load64(h8)` is 0 (neither `q.v = 5` nor the closure's `+ 10` reached the 8 B object) and
`load64(h16)` is 17 (both writes reached the 16 B object). Also measured: before `q.v = 5`, `q.v` reads back the
address itself. If both were handles the exit would be (15 * 100 + 17) % 256 = 237.

## Root cause

`MARK_SMALL_STRUCT` (`src/frontend/parse_types.cyr:1020`, 6.6.5) records every struct local of ≤ 8 B as inline
(GLAGG = 1) regardless of its initialiser, so `_local_struct_is_ptr` (`src/frontend/parse_fn.cyr:1735`) answers
"inline" and field access addresses the slot. A > 8 B local initialised from an address is registered pointer-mode.
`_CL_CAP_BASE_RA` (`src/frontend/parse_decl.cyr:481`) then does the right thing for each: an env word of a ≤ 8 B
struct IS the struct; a one-word capture of a > 8 B struct holds its address.

## Proposed fix

The USER's call — every option changes what an existing program does or whether it compiles:

1. make a ≤ 8 B struct local initialised from an untyped address / a `*T` value a handle, as the > 8 B one is
   (changes what `q.v` reads today);
2. refuse (or warn on) a ≤ 8 B struct declaration whose initialiser is a pointer (`*T`, `alloc`), naming
   `var q: *S8 = …` as the handle spelling;
3. keep the rule and document it in the guide's handle section beside "structs of 8 bytes or less are unchanged".

Whichever is chosen, the closure capture needs no change — it follows the declaration.
