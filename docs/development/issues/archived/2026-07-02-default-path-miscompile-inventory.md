# Default-path miscompile inventory — v6.3.34 sweep (surfaced while "evening up" v6.3.35)

**Filed:** 2026-07-02. Found by a 7-dimension adversarial default-path discovery sweep, each
reproduced by a skeptic verifier. All reproduce on plain `build/cycc` (NO env) — default-path.
8 high + 1 medium. Several share a root cause. Independent of the gated generics engine.

## Clusters
- **Sub-i64 SIGNED sign-extension** ([1] local, [2] struct field, [8] call-arg, [7] typed-ptr value):
  `EFLLOAD_W`/`EFIELD_LOAD_W` emit `movzx` (zero-extend) for i8/i16/i32, never `movsx` — so a negative
  value in a signed sub-i64 reads back as a large positive; breaks every signed compare/arith on
  sub-i64. Needs signedness tracking (u8/u16/u32 correctly want zero-extend). [7] is the dual: a
  `*i8/*i16/*i32` typed-POINTER local (SLTYPE 1/2/4, collides with the scalar encoding) is truncated
  to its low bytes on load — pointers must load full 64-bit. Fixing the pair needs scalar-vs-pointer
  + signed-vs-unsigned disambiguation in the sub-i64 load path.
- **>8-byte struct value semantics** ([5] by-value param, [6] copy-init local): a >8-byte struct passed
  by value / copy-initialized (`var b: P = a`) is truncated to 8 bytes AND the callee/reader
  dereferences the value as a pointer → SIGSEGV. 8-byte structs fine; 12/16+ byte fail.
- **Parser**: [3] `&&`/`||` equal precedence (should be `&&` tighter); [4] `for i in IDENT..hi` mis-parses
  the identifier + `..` as field access.
- **Closures**: [9] a capturing closure copied into another local then called via callptr SIGSEGVs
  (capturing dispatch only fires for the syntactic call form).

### [1] (high) sub-i64 signed load: missing sign-extension (zero-extend where sign-extend required)

Signed sub-i64 LOCAL variables (i8/i16/i32) are zero-extended on load instead of sign-extended, so any negative value stored in one reads back as a large positive value and all subsequent signed operations (comparisons, </>, arithmetic, shift, div, mod) are wrong.

- expected: exit 42 — a holds -1 (a signed i32), so a < 0 is true.
- actual: exit 7 — a is loaded as 0x00000000FFFFFFFB-style zero-extended value (4294967295 for -1), so a < 0 is false. Proven by probe `(a>>40)&1` returning 0 (a i32 = -5): a correct sign-extended -5 has bit 40 set, but the value read back has all bits above 31 clear, confirming EFLLOAD_W (src/backend/x86/emit.cyr:485-502) unconditionally emits movzx/mov (zero-extend) for width 1/2/4 and never movsx, regardless of the type being signed (i8/i16/i32). Same defect breaks `a == -1`, `a < b` (i32 -1 vs 1 -> false), `a >> 2` arith-shift, `a * 2`, `a / 4`, `a % 3`, `var b = a` copy, and i8=200 -> should be -56 (a<0). Unsigned u8/u16/u32 (which correctly want zero-extension) and i32 function *parameters* are unaffected; truncation-on-store is correct. Distinct from K1 (left-scalar pointer-scaling addressing bug), K2 (typed-global SIGSEGV), K3 (generics).

Repro:
```
fn main(): i64 {
  var a: i32 = 0 - 1;
  if (a < 0) { return 42; }
  return 7;
}
```

### [2] (high) sub-i64 signed field load: missing sign-extension

Signed sub-i64 STRUCT FIELDS (i8/i16/i32) are likewise zero-extended on load (separate emit path EFIELD_LOAD_W), so a negative value read from a signed narrow field is corrupted into a large positive.

- expected: exit 42 — p.a holds -1 (signed i32 field), so p.a < 0 is true.
- actual: exit 7 — the field load path EFIELD_LOAD_W (src/backend/x86/emit.cyr:543-550) emits movzx (width 1/2) or bare `mov eax` (width 4), never movsx, so p.a reads back zero-extended (4294967295) and p.a < 0 is false. Same root cause as the local case but a distinct emit function / code path; both need a signedness-aware movsx variant for i8/i16/i32.

Repro:
```
struct P { a: i32; b: i32; }
fn main(): i64 {
  var p: P;
  p.a = 0 - 1;
  if (p.a < 0) { return 42; }
  return 7;
}
```

### [3] (high) control flow / operator precedence

Logical && and || have equal precedence and left-associate, instead of && binding tighter than ||, so 'a || b && c' is compiled as '(a || b) && c' and produces the wrong boolean result.

- expected: Exit 42. With standard precedence (&& binds tighter than ||) the condition is 't==1 || (f==1 && f==1)' = 'true || (false && false)' = true, so it returns 42. The explicitly-parenthesized form 'if (t == 1 || (f == 1 && f == 1))' does return 42, confirming 42 is correct.
- actual: Exit 0. The parser evaluates the condition as '(t==1 || f==1) && f==1' = '(true || false) && false' = false, so the if-body is skipped and it returns 0. Root cause: src/frontend/parse_expr.cyr PCMPE parses && (token 53) and || (token 54) in a single flat left-associative 'while (lop == 53 || lop == 54)' loop with each operand a single comparison via PEXPR, giving both operators equal precedence. This affects value expressions, if/elif, and while conditions identically (verified: assigned-to-var, while-cond, and elif-cond all show the buggy result).

Repro:
```
fn main(): i64 {
  if (1 == 1 || 0 == 1 && 0 == 1) {
    return 42;
  }
  return 0;
}
```

### [4] (medium) control flow / for-range parsing

A for-loop with a bare identifier as the lower range bound (for i in lo..hi) fails to compile: the parser mis-parses the identifier followed by '..' as field access and consumes the first '.'.

- expected: Exit 14 (sum of 2+3+4+5). A bare identifier is a legal range lower bound: the equivalent 'for i in (lo)..hi' compiles and returns 14, and 'for i in 0..n' with a variable upper bound also works, so the identifier lower bound is legal syntax.
- actual: compile error: 'error:<source>:5: expected identifier, got \'.\''. In src/frontend/parse_ctrl.cyr the range start is parsed via PCMPE->PEXPR, which on seeing the bare identifier 'lo' followed by '.' begins parsing a field access (lo.<field>), consuming the first '.' of the '..' range operator and then failing when it finds the second '.' instead of a field name. Literal lower bounds ('0..n') and parenthesized/arithmetic lower bounds ('(lo)..6', '1+1..6') all compile correctly; only the bare-identifier lower bound breaks.

Repro:
```
fn main(): i64 {
  var lo = 40;
  for i in lo..43 { }
  return 42;
}
# Fails to compile on the DEFAULT path: error:<source>:3: expected identifier, got '.'
# Any bare identifier (local var OR fn param) as the for-range lower bound triggers it.
```

### [5] (high) struct by-value parameter ABI mismatch (>8-byte struct)

A by-value struct parameter larger than 8 bytes SIGSEGVs when any field is read in the callee: the caller passes the struct's first 8 bytes by value in a register (rdi), but the callee treats the parameter as a pointer and dereferences it.

- expected: exit 42 (geta returns s.a == 42)
- actual: SIGSEGV (exit 139). Disassembly: main marshals the arg with `mov rax,[rbp-0x38]` (loads only s.a, the first 8 bytes) then `push rax; pop rdi` (passes the VALUE 42 in rdi). geta's body does `mov rax,[rbp-0x30]` (the saved rdi = 42) then `mov rcx,rax; mov rax,[rcx]` -- it DEREFERENCES the parameter as if it were a pointer-to-struct, reading address 42 -> fault. The caller passes by value in a register; the callee expects a pointer. Boundary confirmed: 8-byte structs (single i64, or 2x i32) pass and read correctly; 12-byte (3x i32), 16-byte (2x i64 or 4x i32) and larger all SIGSEGV, even reading the FIRST field. A callee that ignores the struct param (returns a constant) does NOT crash, so the call setup itself is fine -- only the field read faults. The existing tests/tcyr/struct_byval_return.tcyr covers struct RETURNS only; no function there takes a struct-typed parameter and reads its field, so this path is untested.

Repro:
```
struct S { a: i64; b: i64; }
fn geta(s: S): i64 { return s.a; }
fn main(): i64 {
  var s: S;
  s.a = 42;
  return geta(s);
}
```

### [6] (high) struct-to-struct copy-init local (>8-byte) treated as pointer

Copy-initializing a struct local larger than 8 bytes from another struct variable (`var b: P = a`) truncates the copy to the first 8 bytes AND makes subsequent field access on the copy dereference the copied value as a pointer, causing a SIGSEGV (or a silently wrong dereferenced value).

- expected: exit 42 (b is a value copy of a, b.x == 42)
- actual: SIGSEGV (exit 139). Disassembly of `var b: P = a`: `mov rax,[rbp-0x38]` loads only a.x (first 8 bytes) and `mov [rbp-0x40],rax` stores that single 8-byte value into b's slot -- b.y is never copied (the 16-byte copy is truncated to 8 bytes). Then `return b.x` emits `mov rcx,rax; mov rax,[rcx]`, dereferencing the copied value (42) as a pointer -> fault. Two proofs of the pointer-indirection: (a) reading the copy via `load64(&b)` instead of `b.x` returns 42 correctly (the byte at &b IS the copied value), so it is the `.x` field-access that wrongly indirects; (b) a variant with `a.x = &target` (target=777) returns exit 9 == 777 & 0xFF, i.e. `b.x` computed load64(load64(&b)) = load64(&target) = 777 instead of the address. Boundary: 8-byte struct copy (`struct P { x: i64; }`) works; 12-byte and 16-byte fail. IMPORTANT distinction: `var b: P = mk()` copy-init from a struct-RETURNING FUNCTION works correctly (returns 42) -- only copy-init from another struct VARIABLE is broken. (`var b = a` inferred, without the `: P` type annotation, fails to even parse `b.x` -- a separate, lesser parse-level limitation.)

Repro:
```
struct P { x: i64; y: i64; }
fn main(): i64 {
  var a: P;
  a.x = 42;
  a.y = 7;
  var b: P = a;
  return b.x;
}
```

### [7] (high) wrong-load / pointer-value truncation (segfault on deref)

A signed sub-i64 typed-pointer local (var p: *i8 / *i16 / *i32) has its 64-bit pointer VALUE truncated to its low 1/2/4 bytes every time it is read; dereferencing it SIGSEGVs, and comparing/passing it yields a corrupted address.

- expected: exit 42 — p holds &a (a full 64-bit stack address); *p loads the byte 42 stored there.
- actual: SIGSEGV (exit 139). The typed-pointer local `var p: *i8` is stored with SLTYPE = pscale = 1 (parse_decl.cyr:1972), the SAME encoding a sub-i64 SCALAR `var x: i8` gets. When p is read as a factor, parse_expr.cyr:514 `if (lt > 0) { if (lt <= 8) { if (lt < 8) { SPSC(S,1); } SEXW(S,lt); EFLLOAD_W(S, li, lt); return 0; } }` takes the sub-i64-scalar width-load branch and emits a width-`lt` (here 8-bit) load, truncating the 64-bit pointer to its low byte(s). The truncated value is then dereferenced -> fault. Independently confirmed non-fatally: `var p: *i32 = &a; var q: i64 = &a; if (p == q) {return 42;} return 1;` returns 1 (p != &a, value truncated). Only the signed names hit it — the parser maps *i8/*i16/*i32 to pscale 1/2/4 (parse_decl.cyr:1150-1153) while *i64 and *u8/*u16/*u32 get pscale 8 (SLTYPE 8), which avoids the width-load branch and works correctly. The v6.3.34 K1-fix comment at parse_expr.cyr:509-513 states 'No sub-i64 typed pointers exist, so 1/2/4 are always scalars' — that premise is false; the parser explicitly creates them, so scalars and sub-i64 typed pointers are indistinguishable at the read site.

Repro:
```
fn main(): i64 {
    var a[16];
    store8(&a, 42);
    var p: *i8 = &a;
    return *p;
}
main();
```

### [8] (high) wrong-value / missing sign-extension on sub-i64 local load (manifests when passing a negative sub-i64 local as a call arg)

A negative value in a signed sub-i64 local (i8/i16/i32) is ZERO-extended (not sign-extended) when loaded, so passing such a local as a call argument delivers a large positive value (e.g. 0x00000000FFFFFFF9) to the callee instead of -7; comparisons and any full-width use inside the callee are wrong.

- expected: 42 — x holds -7, so neg7(x) sees a == -7 and returns 42.
- actual: 1 — the i32 local x is loaded with `mov eax,[rbp+disp]` (zero-extend), so the callee receives 0x00000000FFFFFFF9 (4294967289), a != -7, returns 1. Cross-checked: `fn hibits(a:i64){return (a>>32)&255;}` called with the same x returns 0 (should be 255 for a sign-extended -7), directly proving the high 32 bits are zeroed. The store keeps the low bits correct (`x & 255` == 249), and a POSITIVE i32 local compares fine (x=7; x==7 -> 42), and an i32 PARAM works (literal passed full-width). The defect is purely the width-1/2/4 local LOAD: src/backend/x86/emit.cyr EFLLOAD_W emits movzx/`mov eax` (zero-extend) for widths 1/2/4 where a signed sub-i64 type needs movsx/movsxd. Also reproduces standalone without any call: `var x:i32 = 0-7; if (x == -7) {return 42;} return 1;` -> 1 (and `x == 4294967289` -> 42), and for i16/i8 locals. Distinct from K1 (LEFT-of-+/- pointer scaling, now 5/fixed) and K2 (typed sub-i64 GLOBAL SIGSEGV; this is a LOCAL, no crash, wrong value).

Repro:
```
fn main(): i64 {
  var x: i32 = 0 - 7;
  if (x < 0) { return 42; }
  return 1;
}
// Returns 1; expected 42. The signed i32 local x = -7 is loaded zero-extended
// (0x00000000FFFFFFF9 = 4294967289), so `x < 0` is false. No function call needed.
// Equivalent call form (from claim) also fails:
//   fn neg7(a: i64): i64 { if (a == -7) { return 42; } return 1; }
//   fn main(): i64 { var x: i32 = 0 - 7; return neg7(x); }  -> 1
```

### [9] (high) SIGSEGV / wrong-dispatch on capturing closure via indirection

A capturing closure (heap env object) copied into another local variable and then called via callptr SIGSEGVs — the capturing dispatch only fires for the syntactic CLOSURE_TYID local, so on any copy it falls to the bare-fn-pointer path and jumps to the env-object address as code.

- expected: exit 42 (40 + 2). The control program that keeps `return callptr(f, 2);` on the original closure variable `f` returns 42 correctly.
- actual: SIGSEGV (exit 139). Root cause in src/frontend/parse_expr.cyr:673-677: callptr detects a capturing closure ONLY when the callee token is an identifier (PEEKT(S)==2) that is a local whose GLTYPE == CLOSURE_TYID. A copy `var f2 = f;` gives f2 a plain i64 type, so cp_is_closure stays 0. The non-closure path (line 712) then spills f2 (which holds the env-object POINTER) directly as the call target and does `call [f2]` = call on the env object itself, instead of the closure path (line 697) which does ELOAD64 to fetch the real fn pointer from [obj+0] and passes obj as the hidden env arg. Executing the env object's bytes as instructions faults. The SAME root cause reproduces identically (all SIGSEGV) when the capturing closure flows through ANY indirection that loses the CLOSURE_TYID identity: passed as a fn parameter and called via callptr in the callee; returned from a fn and called in the caller (`var c = make(); callptr(c, 2)`); or stored in a struct field and called via `callptr(b.fp, 2)` (a field access is not even an identifier, so PEEKT!=2). Non-capturing closures are unaffected — they are bare fn addresses, so a copy + fncall1 works fine.

Repro:
```
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn go(): i64 {
    var base = 40;
    var f = |x| base + x;
    var f2 = f;
    return callptr(f2, 2);
}
alloc_init();
syscall(60, go());

```
