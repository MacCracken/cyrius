# `return &h;` in a fn returning `S`, with `h` a handle, a `*S` local or an untyped `self`: at 8 B or less the slot's ADDRESS is the struct's word; over 8 B refused in other words — OPEN

**Status:** 🟡 **OPEN** — a question for the user. Found 2026-10-15 by the 6.7.13 structs lane (unit S3) while landing
D4 (a) (`return &s;` of an inline struct is `return s;`, issues/archived/2026-10-14-return-address-of-struct-local-decision.md).
Measured on the lane tree after that bite, x86_64 / aarch64 (qemu) / cx / PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane; filed from the 6.7.13 structs lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — silent at 8 B or less: the caller reads a stack address (the slot of a dead frame's handle or
pointer) as the struct's field; over 8 B a refusal that names nothing.
**Kind:** language (decision) — D4 (a) reads `&s` of an inline struct as the struct; the guide's handle line (6.7.10
decision 5) says a handle's or a `*T`'s `&h` is its SLOT (a pointer to the word holding the address), which is no
pointer to `S`. What `return &h;` means in a fn declared `: S` is not decided.

## Repro

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S8 { v; }
fn h(): S8 { var q: S8 = alloc(8); q.v = 3; return &q; }
fn main(): i64 { alloc_init(); var c: S8 = h(); return c.v == 3; }
syscall(60, main());
```

```
x86_64 0, aarch64 0, cx 0, PE 0     (no diagnostic; c.v is &q, the handle's frame slot)
```

The same at 8 B with `var s: S8; var p: *S8 = &s; return &p;` (exit 0) and with an untyped `self` (a pointer) in
`impl S8 { fn cp(self): S8 { return &self; } }` (exit 0). Over 8 B the handle form is refused in other words:

```
16 B: error: a fn returning the 9-16 byte struct `P2` is returned in two registers, so `return` takes a local of
      that struct or a call returning it — got `this expression`
24 B: error: struct-return fn: return must be a bare local identifier, or a call to a fn returning the same struct
```

## Root cause

The return arms (`_ret_small_ptr` for 8 B or less, `_ret_ptr_src` for the pair and retptr classes,
src/frontend/parse_fn.cyr) type the value with `_hl_dpsid`: its `& IDENT` arm (`_hl_amp_sid`, parse_decl.cyr) answers
only for an inline struct (a local, a by-value parameter, a value global, a captured copy) and answers 0 for a handle,
a `*T` or an untyped `self` (their `&` is the slot). An untyped value then stays the struct's word at 8 B or less,
and over 8 B falls to the class's generic refusal.

## Options (the user's)

- (a) Refuse by name at every size ("`&q` is the address of q's slot, not a struct — return q"): 8 B programs that
  compile today stop compiling.
- (b) The struct the handle / pointer points at (`return &q;` as `return q;`): a new double-indirection reading.
- (c) Leave it (the 8 B word; the over-8 B refusals keep their wording).
