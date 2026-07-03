# ≤8-byte struct passed BY VALUE reads 0 on the SECOND call (default-path, pre-existing)

**Filed:** 2026-07-03 (surfaced while building the v6.3.37 monomorph-repairs fixture)
**Severity:** P2 — default-path miscompile, but a narrow shape (a ≤8-byte struct local
passed by value to the SAME callee more than once). Pre-existing: reproduces on the
v6.3.35 release binary (44779816), v6.3.36 (bd032fbe), and current — NOT introduced by
the v6.3.36 struct-param address-passing (`_fnt_structmask` only touches **>8-byte**
structs; this bug is ≤8-byte, value-passed).

## Symptom

```
struct S { v: i64; }
fn getv(s: S): i64 { return s.v; }
fn main(): i64 {
    var s: S; s.v = 5;
    var a = getv(s);      # a = 5   (correct)
    var b = getv(s);      # b = 0   (WRONG — expected 5)
    return b;             # exit 0
}
```

A SINGLE call (`return getv(s)`) returns 5 correctly. Two calls to the same struct-by-value
callee with the same struct local → the second reads 0. Also reproduces as
`getv(s); return getv(s)` (bare statement + call).

## Root cause (disassembly)

`s` (a ≤8-byte struct local) is register-allocated to a callee-saved register (rbx) by the
regalloc picker's time-sliced sharing. But `s.v = 5` (field store) writes MEMORY
`[rbp-disp]` via `lea rcx,[rbp-disp]; mov [rcx],rax`, while the by-value call arg is
materialized by reading the REGISTER (`mov rax,rbx; push; pop rdi`). The field-store and
the value-pass disagree on where `s` lives:
```
  lea  rcx, [rbp-0x30]        ; &s
  mov  [rcx], rax             ; s.v = 5  -> MEMORY
  mov  rax, rbx               ; arg = s  -> REGISTER (stale rbx, never loaded from [rbp-0x30])
  ...
  call getv
```
So the value-pass reads a stale/garbage rbx. The first call happens to work when rbx still
holds a usable value from an earlier assignment; the second call reads whatever the callee
convention left (0).

The fix direction: a ≤8-byte struct local that is EITHER field-accessed via `&s` (memory)
OR passed by value must be pinned to memory (barred from register routing), the same way
`&`-taken locals already bar the regalloc picker — OR the value-pass must read from the
canonical memory slot, not the register. (Consistent with the v5.8.16 §8 / v6.3.16 struct
addressing invariants: a struct local's canonical home is its stack slot.)

## Verification for the repair

Reproduce-then-fix with the minimal repro above; add a `struct_byval_local_reuse.tcyr`
that calls a struct-by-value fn twice with the same local and checks both results. Default
codegen for non-struct-by-value programs must stay byte-identical (differential).

Not scheduled yet — a default-path P2 for a future slot (candidate v6.3.38 alongside the
B3 generics work, or its own bite).
