# Cyrius Language Guide

> The complete reference for writing Cyrius programs and kernels.

## Quick Start

```sh
cyrius build hello.cyr build/hello           # Compile (resolves deps from cyrius.cyml)
./build/hello; echo $?                       # Run → 42
```

## Types

The core type is the 64-bit integer (`i64`) — no separate pointer type at
the value level (see ADR-002). Type annotations are optional and don't
enforce:

```
var x = 42;
var y: i64 = 42;      # Same thing — annotation is documentation
```

`i64` is the core tenet, not the only type. A deliberate, narrow exception
exists for math hot paths: scalar `f64` floats and the SIMD vector types
(`f64v2` / `f64v4`, `f32v4` / `f32v8`, and the integer vectors), backed by
SSE2 / AVX2 / NEON builtins (`lib/math.cyr`, `lib/simd.cyr`). These are
reinterpreted bit patterns — float ops use explicit `f64_from` / `f64_to`
(and `f32_from` / `f32_to` for 32-bit lanes) conversions, not a full float
type system. See [SIMD Vectors](#simd-vectors) for the full type set,
packed-op builtins, and runtime capability gating.

## Number Literals

Integer literals may be written in three bases. Underscore separators
(`_`) are allowed in any base and are ignored:

```
var dec = 1_000_000;   # decimal
var hex = 0x1ED;        # hexadecimal (0x prefix)        → 493
var oct = 0o755;        # octal (0o prefix, base-8)       → 493
var perms = 0o644;      # common Unix file-mode form      → 420
```

Octal uses digits `0`–`7`; a `8` or `9` ends the literal. (There is no
`0b` binary literal form.) A decimal literal with a fractional part
(`3.14`) is lexed as an `f64` float.

## Variables

```
var x = 10;            # Global or local (context-dependent)
var buf[256];          # Bare array — see byte-vs-slot note below
var slots: i64[256];   # Element-typed array — 256 i64 SLOTS (2048 bytes), anywhere
x = x + 1;             # Reassignment
```

### Arrays: byte vs slot sizing (v6.2.1)

`var a: T[N]` declares a fixed array of **N elements of type T** — the
unambiguous, recommended form. The reserved size is `N * sizeof(T)`
(rounded up to 8), identical in function scope and at top level:

| Spelling          | Reserved bytes      | Use for                       |
|-------------------|---------------------|-------------------------------|
| `var a: i64[N]`   | `N * 8`             | **slot arrays** (the `store64(&a + i*8, …)` idiom) |
| `var a: i32[N]`   | `N * 4`             | packed 32-bit data            |
| `var a: u8[N]`    | `N`                 | byte buffers (explicit)       |
| `var a: u128[N]`  | `N * 16`            | 128-bit lanes                 |

The **bare** `var a[N]` keeps its historical, scope-dependent meaning and
is best reserved for byte buffers:

- **in a function:** `N` **bytes** (rounded up to 8) — `var iv[12]` is a
  12-byte buffer.
- **at top level:** `N` **i64 slots** (`N * 8` bytes) — `var table[16]` is
  128 bytes.

> **Footgun (fixed by the explicit form):** writing a *function-local*
> `var a[4]` with the slot idiom `store64(&a + i*8, …)` runs off its 8-byte
> backing — the array only holds 1 slot, not 4. Declare slot arrays as
> `var a: i64[4]` (32 bytes) instead. See CHANGELOG [6.2.1].

## Functions

```
fn add(a, b) {
    return a + b;
}
var r = add(20, 22);   # r = 42
```

- Up to 6 register params, 7+ passed on stack
- Forward calls work (functions can call functions defined later)
- Relaxed ordering: functions can appear after statements (v1.11.0+)
- All functions return a value (`return 0;` if nothing to return)

**Reserved words are a CLASS, not a short list.** `TOKNAME_BUILTIN` in
`src/common/util.cyr` is the single source of truth — **67** builtin/intrinsic names, plus
the statement keywords, and `IS_KEYWORD_TOK` *derives* from that table so the two sets
cannot drift. It covers `syscall`, the `load8/16/32/64` + `store8/16/32/64` family, every
`f64_*` / `f64v_*` / `f32_*` / `f32v_*` / `f32v8_*` / `iv_*` intrinsic, and `union`,
`defer`, `secret`, `async`, `await`, `u128`, `bitget`/`bitset`/`bitclr`, `ret2`/`rethi`,
`pub`, `public`, `private`, `shared`, `match`, `in`, `default`, `stack`. Using any of them
as an identifier is an error, and since v6.4.77 the message **names** the one you hit:

```
var f64_add = 1;
# error:<source>:1:5: expected identifier, got reserved keyword 'f64_add'
#   (cannot be used as an identifier; rename the variable/field/fn)
```

Read the table rather than memorising a subset — the partial lists that used to appear in
docs were the reason people were surprised by the other sixty.

## Control Flow

```
# If / elif / else
if (x == 1) { ... }
elif (x == 2) { ... }
else { ... }

# While
while (x < 10) { x = x + 1; }

# For — all three clauses (init; cond; step) are required and non-empty.
# Cyrius does not accept `for (;;)` / `for (; c;)` (omitted clauses).
# For an unbounded or custom-stepped loop, use `while`; the idiomatic
# forms are the counted `for` above and (where supported) `for x in …`.
for (var i = 0; i < 10; i = i + 1) { ... }

# Break / Continue
# `break` leaves the NEAREST ENCLOSING while, for, switch or match (v6.5.20 — C
#   semantics; before that a `break` inside a switch/match was a MISCOMPILE, see
#   "Switch" below).
# `continue` always belongs to the nearest enclosing LOOP. A switch or match in
#   between is transparent to it — `continue` inside a case skips to the loop's next
#   iteration, it does not fall out of the switch.
# continue works correctly in all loop types (v1.11.1 bug #13 fix)
while (1 == 1) {
    if (done == 1) { break; }
    if (skip == 1) { continue; }
}
```

## Operators

```
# Arithmetic
+ - * / %

# Comparison (return 1 or 0)
== != < > <= >=

# Bitwise
& | ^ ~ << >> >>>

# Logical (short-circuit, chainable)
&&  ||

# Explicit overflow operators (v5.6.2)
+%  -%  *%      # wrapping (alias for bare + - * — 2's complement wrap)
+|  -|  *|      # saturating (clamp to i64 min/max via lib/overflow.cyr)
+?  -?  *?      # checked (panic with exit code 57 on overflow)
```

Right shift comes in two forms (v6.4.46): `>>` is a **logical** shift
(zero-fill) and `>>>` is an **arithmetic**, sign-preserving shift. Note
this is the **reverse** of JS/Java, where `>>` is arithmetic and `>>>` is
the zero-fill logical shift.

Wrapping ops (`+%` etc.) document intent at the call site that a wrap is
expected — bytes are identical to the bare operator. Saturating and
checked variants compile to calls into `lib/overflow.cyr` helpers
(`_sat_add_i64`, `_chk_add_i64`, etc.). Checked-panic uses `syscall(60, 57)`;
exit code 57 is reserved to distinguish overflow panics from POSIX signal
exits and assert-summary returns.

## Memory

```
var buf[16];
store8(&buf, 65);              # Write byte
var c = load8(&buf);           # Read byte → 65

store16(&buf, 0x1234);         # 16-bit
store32(&buf, 0x12345678);     # 32-bit
store64(&buf, 0x123456789ABC); # 64-bit

var v = load16(&buf);          # Corresponding reads
var v = load32(&buf);
var v = load64(&buf);
```

## Pointers

```
var x = 42;
var p = &x;            # Address of x
var v = *p;            # Dereference → 42
*p = 99;               # Write through pointer

# Typed pointers (auto-scale arithmetic)
var buf[64];
store64(&buf, 10);
store64(&buf + 8, 20);
var p: *i64 = &buf;
var a = *p;            # 10
var b = *(p + 1);      # 20 (adds 8 bytes, not 1)
```

## Structs

```
struct Point { x; y; }

var p = Point { 10, 20 };           # Positional — fields in declaration order
var q = Point { x: 10, y: 20 };     # Named — any order, every field required
var sum = p.x + p.y;    # 30
p.x = 42;               # Field assignment

# Nested structs
struct Rect { tl: Point; br: Point; }
var r = Rect { 0, 0, 10, 5 };
var w = r.br.x - r.tl.x;   # 10
```

## Strings

```
syscall(1, 1, "hello\n", 6);   # Write to stdout
# Strings are null-terminated in the data section
```

### Escape sequences

| Escape         | Byte(s)        | Notes                                |
|----------------|----------------|--------------------------------------|
| `\n`           | `0x0A`         | newline (LF)                         |
| `\r`           | `0x0D`         | carriage return                      |
| `\t`           | `0x09`         | tab                                  |
| `\0`           | `0x00`         | NUL byte                             |
| `\\`           | `0x5C`         | literal backslash                    |
| `\"`           | `0x22`         | literal double-quote                 |
| `\'`           | `0x27`         | literal single-quote                 |
| `\a`           | `0x07`         | alert (BEL)         (v5.7.13)        |
| `\b`           | `0x08`         | backspace           (v5.7.13)        |
| `\f`           | `0x0C`         | form feed           (v5.7.13)        |
| `\v`           | `0x0B`         | vertical tab        (v5.7.13)        |
| `\x##`         | one byte       | exactly 2 hex digits, e.g. `\x1b`    |
| `\u####`       | 1-3 UTF-8 b    | exactly 4 hex digits (BMP)           |
| `\u{...}`      | 1-4 UTF-8 b    | 1..6 hex digits, up to `\u{10FFFF}`  |

`\u` codepoints in the surrogate range `D800..DFFF` and any
`\u{...}` codepoint > `U+10FFFF` are lex errors. Malformed
hex digits, missing closing `}`, empty `\u{}`, and 7+ digit
`\u{...}` are lex errors. UTF-8 bytes in source are passed
through verbatim inside string literals — escapes are
optional, not required.

```
# ANSI alt-screen-enter — the canonical example.
syscall(1, 1, "\x1b[?1049h", 8);

# Smiley face emoji (U+1F600) as 4 UTF-8 bytes.
var s = "\u{1F600}";

# Three forms of "é" (U+00E9), all equivalent at the byte level.
var a = "é";          # literal UTF-8 in source: C3 A9
var b = "\u00e9";     # 4-hex form:               C3 A9
var c = "\u{e9}";     # braced form:              C3 A9
```

## Slices

```
include "lib/slice.cyr"

# Two equivalent type forms:
var s: [u8] = 0;          # bracket form
var t: slice<i64> = 0;    # ident form

# Slice points at backing storage. Convention: ptr@0, len@8.
var data[5];
store8(&data, 65); store8(&data + 1, 66);  # ...
slice_set(&s, &data, 5);

# Bounds-aware indexing — element-width-correct load (v5.8.15).
# Out-of-range / negative idx → exit 134 + "slice bounds violation\n" to stderr.
var b = s[0];           # = 65
var c = s[2];           # = 67

# Dot-syntax field access (v5.8.16). .ptr / .len only — other names error.
var p = s.ptr;          # = &data
var n = s.len;          # = 5
s.len = 3;              # truncate the view
s.ptr = &data + 1;      # rewrite view start

# Slice-typed wrapper helpers (v5.8.18) — additive, take slice POINTERS.
sys_read_slice(fd, &s);                 # read up to s.len bytes into s.data
slice_copy_bytes(&dst, &src);           # memcpy with min-length cap
slice_eq_bytes(&a, &b);                 # content equality
```

Subscript and dot-syntax fire on **fn-local** slices only. Top-level
slice vars still need the helper-fn API (`slice_ptr` / `slice_len` /
`slice_unchecked_get_W`). See `lib/slice.cyr` for the full helper list.

A `Str` (heap, `lib/str.cyr`) and a `vec`'s first 16 bytes
(`lib/vec.cyr`) are byte-identical to a slice — they pass directly to
`slice_ptr` / `slice_len` / `slice_eq` etc. without conversion.

## Pointer-to-struct dot syntax (v5.8.17)

```
include "lib/str.cyr"

var s: Str = str_from("hello");
var n = s.len;            # = 5  (heap-pointer auto-deref)
var d = s.data;           # = pointer to "hello" bytes

# Works on `: <StructName>` fn parameters too:
fn print_str(s: Str) {
    syscall(1, 1, s.data, s.len);
    return 0;
}
```

The `: Type` annotation is required — untyped locals storing
struct pointers fall through to the existing error path.
PARSE_FIELD_LOAD/STORE auto-detects pointer-vs-inline by checking
the slot above the named slot for the v5.5.36 sentinel name (-1).

## Syscalls

```
syscall(1, 1, "hello", 5);          # write(fd=1, buf, len=5)
var n = syscall(0, 0, &buf, 256);   # read(fd=0, buf, len=256)
syscall(60, 0);                      # exit(0)
```

## Multi-Return

```
# Native multi-return (v3.7.2) — return (a, b) puts values in rax:rdx
fn divmod(a, b) { return (a / b, a % b); }
var q, r = divmod(10, 3);       # q = 3, r = 1 — destructuring bind

# ⚠ Parens are REQUIRED on the return and FORBIDDEN on the bind:
#   return a, b;        → error: expected ';', got ','
#   var (q, r) = f();   → error: expected identifier, got '('

# Declared multi-value return (v6.5.21) — arity 2 or 3, types in the signature
fn two_product(a, b): (f64, f64) { return (f64_mul(a, b), f64_add(a, b)); }
var prod, err = two_product(x, y);   # both bindings are typed f64
fn dd_pow10(k): (i64, i64, i64) { return (hi, lo, bexp); }
var hi, lo, bexp = dd_pow10(k);

# Declaring the return type is what lets the compiler check a FORWARD call's
# arity and type the bindings. An undeclared `return (a, b);` still works and
# leaves the bindings untyped.

# The destructure requires a CALL as the whole right-hand side (v6.5.21).
# These are rejected rather than silently reading whatever rdx held:
#   var q, r = 42;                    # not a call
#   var q, r = dm(17, 5) + (k / 9);   # call is not the whole RHS
#   var x, y, z = f();                # count disagrees with f's declared arity

# Legacy builtins still work
fn divmod_old(a, b) { ret2(a / b, a % b); }
var q2 = divmod_old(10, 3);     # q2 = 3 (rax)
var r2 = rethi();                # r2 = 1 (rdx)
```

## Switch Case Blocks

```
# case bodies can be blocks with scoped variables (v3.7.4)
switch (cmd) {
    case 1: {
        var buf = alloc(1024);
        process(buf);
    }
    case 2: result = 42;         # inline case still works
    default: { result = 0; }
}
```

## Derive Accessors

```
# Auto-generate getters/setters (v3.7.1)
#derive(accessors)
struct Config { host: Str; port; timeout; }
# Generates: Config_host(p), Config_set_host(p, v),
#            Config_port(p), Config_set_port(p, v), etc.
```

## Derive Serialize on an enum (v6.5.31)

`#derive(Serialize)` and `#derive(Deserialize)` work on an **enum** as well as a struct, and
generate a name-string codec pair:

```
include "lib/result.cyr"        # required — the parse side returns Result

#derive(Serialize)
enum BlendMode { MULTIPLY = 0; SCREEN = 1; OVERLAY = 2; }

var sb = str_builder_new();
BlendMode_to_json(SCREEN, sb);          # sb now holds:  "SCREEN"

var r = BlendMode_from_json_str("\"OVERLAY\"");
if (is_ok(r) == 1) { var v = result_unwrap(r); }   # v == OVERLAY
```

- **`E_to_json(v, sb)`** writes the quoted variant **name**. An unrecognised value writes
  `null` rather than a bogus name, so the surrounding document stays valid JSON.
- **`E_from_json_str(json)`** returns `Ok(value)` or `Err(-1)`, so it composes with `?`. It
  accepts a quoted JSON value (`"OVERLAY"`) or a bare name (`OVERLAY`), which lets the same fn
  read a config string as well as a value lifted out of a document.

The generated code compares against the **enum constants**, never against baked-in numbers, so
renumbering a variant cannot desynchronise the codec. Values need not be contiguous.

⚠ **Why a name and not a number.** `{"fmt":"RGBA8"}` is self-describing; `{"fmt":3}` is
indistinguishable from any other integer field. A tagged object (`{"PixelFormat":"RGBA8"}`)
was rejected because in a struct the field key already names the type, so the tag only
restates it. This matches serde's representation for unit-variant enums.

⚠ `Result` here differs from the **struct** deserializer, which returns a raw pointer. That is
deliberate: an enum parse can genuinely fail on an unrecognised name, where a struct decode
yields a zeroed struct.

### `#derive(...)` applies to a struct or an enum — nothing else

Anything other declaration is a hard error:

```
#derive(Serialize)
fn helper(): i64 { return 0; }
# error: #derive(...) applies to a struct or an enum; the following declaration is neither
```

⚠ Until v6.5.30 a derive on a non-struct was **silently accepted and generated nothing** — the
build was green and the missing codec surfaced as an undefined symbol at link time, if at all.
(Earlier still it generated a *misnamed* codec, because the parser skipped the width of
`"struct "` and read `enum Blend` as a name of `lend`.) Both symptoms had the same cause.

## Defer

```
# Defer runs at function exit, LIFO order
# Only runs if the defer statement was reached (v3.8.0)
fn example() {
    var fd = open("file");
    defer { close(fd); }
    if (error) { return -1; }   # defer runs — fd closed
    defer { free(buf); }        # only runs if we get here
    return 0;                    # both defers run
}
```

## Math Builtins

```
var angle = f64_atan(x);         # Arctangent (f64)
# See lib/math.cyr for additional math functions
```

## SIMD Vectors

Cyrius exposes fixed-width SIMD vectors as first-class types for math /
tensor hot paths. Lanes are stored as **reinterpreted bit patterns**: pass
each lane as its integer bit pattern (`f64_from` for `f64` lanes,
`f32_from` for `f32` lanes, plain integers for the integer vectors) and
read results back with `f64_to` / `f32_to`. The compiler emits packed
machine instructions directly; `lib/simd.cyr` provides typed wrappers over
the raw builtins.

### Vector types

| Type     | Width   | Lanes        | Register | Since   |
|----------|---------|--------------|----------|---------|
| `f64v2`  | 128-bit | 2 × `f64`    | XMM      | v5.10.x |
| `f64v4`  | 256-bit | 4 × `f64`    | XMM pair | v5.10.x |
| `f32v4`  | 128-bit | 4 × `f32`    | XMM      | v6.4.4  |
| `f32v8`  | 256-bit | 8 × `f32`    | YMM      | v6.4.8  |
| `i8v16`  | 128-bit | 16 × `i8`    | XMM      | v6.4.6  |
| `i16v8`  | 128-bit | 8 × `i16`    | XMM      | v6.4.6  |
| `i32v4`  | 128-bit | 4 × `i32`    | XMM      | v6.4.6  |
| `i64v2`  | 128-bit | 2 × `i64`    | XMM      | v6.4.6  |

The integer vectors are signed by default; the unsigned variants
(`u8v16`, `u16v8`, `u32v4`, `u64v2`) share the same lane layout and select
unsigned packed ops where the width distinguishes them.

### Packed-op builtins

The raw builtins take **pointer arguments** (a destination and the operand
addresses) plus a lane count `n`; the integer ops also take a compile-time
lane byte-width literal `w` (1/2/4/8):

```
# 128-bit f32 (x86 SSE) — v6.4.4/v6.4.5
f32v_add(&dst, &a, &b, n);        # packed addps  (also f32v_sub / f32v_mul)
f32v_fmadd(&dst, &a, &b, &c, n);  # a*b + c, fused (mulps + addps)
var s = f32v_dot(&a, &b, n);      # horizontal dot → f32 bit pattern

# Integer 128-bit — v6.4.6/v6.4.7
iv_add(&dst, &a, &b, n, w);       # packed add   (also iv_sub / iv_mul)
var acc = iv_dp8(&a, &b, n);      # u8·i8 → i32 widening dot (BitNet/b1.58 inner loop)

# 256-bit f32 (x86 AVX2) — v6.4.8/v6.4.9
f32v8_add(&dst, &a, &b, n);       # packed vaddps ymm (also f32v8_sub / f32v8_mul)
f32v8_fma(&dst, &a, &b, &c, n);   # vfmadd231ps ymm (single-rounding FMA)
var s8 = f32v8_dot(&a, &b, n);    # 8-lane vextractf128 reduce → f32 bit pattern
```

`iv_mul` supports `i16` / `i32` widths only. The contract for `n` is
"exactly the lane count, or over-allocate and zero-pad" — the dot builtins
over-**read** and `f32v_fmadd` over-**writes** up to 3 destination lanes
past `n`, so under-sizing `dst` is a memory-corruption footgun.

> The bare `f32v8_*` builtins emit **unconditional AVX2** (they `#UD` on a
> pre-AVX2 CPU). Call them only when `simd_has_avx2()` is true, or use the
> `lib/simd.cyr` wrappers below, which pick the AVX2 or SSE-fallback path
> for you.

### `lib/simd.cyr` typed wrappers

Each op has a **value form** and a **pointer form** with the same base
name; the parser's overload dispatch routes `&IDENT` call sites to the
`_ptr` sibling automatically:

```
include "lib/simd.cyr"

# Value form — pass the vectors themselves (all targets)
var a: f32v4 = f32v4_make(f32_from(1), f32_from(2), f32_from(3), f32_from(4));
var b: f32v4 = f32v4_splat(f32_from(10));
var r: f32v4 = f32v4_add(a, b);          # {11, 12, 13, 14}
var l0 = f32v4_lane0(r);                 # → f32 bit pattern of lane 0

# Pointer form — pass addresses; `&IDENT` auto-routes to f32v4_add_ptr
var r2: f32v4 = f32v4_add(&a, &b);

# 256-bit wrappers self-select AVX2 vs 2×SSE at runtime
var x: f32v8 = f32v8_make(/* 8 lanes */);
var y: f32v8 = f32v8_splat(f32_from(2));
var z: f32v8 = f32v8_add_ptr(&x, &y);    # vaddps ymm on AVX2, else 2×SSE addps

# Integer vectors
var p: i32v4 = i32v4_make(1, 2, 3, 4);
var q: i32v4 = i32v4_splat(10);
var s: i32v4 = i32v4_add(p, q);          # {11, 12, 13, 14}
```

Constructors (`*_make`, `*_splat`), lane extractors (`*_lane0` … per lane),
and the arithmetic wrappers exist for every vector type. Value-form
wrappers are gated on `CYRIUS_HAS_VAL_SIMD_PARAMS` (defined by every
`main_*.cyr`); on Win64 PE only the pointer form is present, but the
overload dispatch still routes `f32v4_add(&a, &b)` transparently.

### Runtime capability gating (x86)

AVX2 and FMA are **not** the x86-64 baseline, so the 256-bit path is
guarded by a cached CPUID probe:

```
if (simd_has_avx2() == 1) { /* YMM path available */ }
if (simd_has_fma()  == 1) { /* vfmadd231ps available */ }
```

`simd_has_avx2()` tests `CPUID.7.EBX` bit 5; `simd_has_fma()` tests
`CPUID.1.ECX` bit 12 (a *different* bit). The `f32v8_*` wrappers call these
internally and fall back to the 128-bit SSE ops (2 × 128-bit iterations)
when a feature is absent, so consumer code stays correct on any x86 CPU.
`cycc` itself never calls the AVX2 ops, so the compiler stays pure SSE2 and
self-hosts everywhere.

### Portability

Packed SIMD is **Phase 5 complete on all four backends** as of v6.4.32. The
`f32v4` / `f32v8` / `f64v2` / `f64v4` and integer-vector packed ops (plus
`iv_dp8`) run natively on every target:

- **x86** — SSE + AVX2, CPUID runtime dispatch (v6.4.4–.9).
- **aarch64 NEON** — the `EMIT_F32V_LOOP` / `EMIT_F32V_FMADD` / `EMIT_F32V_DOT`
  and `EMIT_IVEC_BINOP` / `EMIT_IVEC_DP8` emitters in
  `src/backend/aarch64/emit.cyr` (v6.4.28–.30). NEON uses `fmul`+`fadd` (not
  `fmla`) so results round bit-identically to the x86 path.
- **Windows PE** — value-form SIMD params *and* returns (by-pointer copy-in +
  retptr) (v6.4.31).
- **cx bytecode** — every flat-array verb lowers to a per-lane scalar loop
  (`_CX_VLOOP_BIN`, cxvm opcodes through `0x68`) (v6.4.32).

The former `simd_f32v4` / `simd_ints` / `simd_f32v8` ARM `XFAIL`s were all
removed at v6.4.30; the `vr01_simd_f32v4_neon` / `vr01_simd_ints_neon` /
`vr01_simd_cx` cross-OS fixtures run the real emitters on pi (aarch64) and are
verified on real hardware. Every vector type is available on every backend.
The one caveat: the aarch64 *native 256-bit* `f32v8` emitters are return-0
stubs that are never reached at runtime — `lib/simd.cyr` routes `f32v8`
through native `f32v4` NEON, so the verb still works on aarch64; only a native
256-bit path (as opposed to 2×128-bit) stays x86-AVX2-only. The scalar `f64` /
`f64v2` / `f64v4` ops (backed by SSE2 / NEON / cx scalar loops) are likewise
available on every target.

## Includes

```
include "lib/string.cyr"
# Textual inclusion — file contents replace the include line
```

### File-relative resolution — `#@incdir` (v6.5.7)

cycc reads its source from **stdin**, so it never learns where that source lives, and an
`include` resolves against the process CWD. Building `src/sub/a.cyr` from the project root
therefore could not resolve its `include "b.cyr"` — a file sitting right next to it.

`cyrius build` now passes the entry file's directory in-band, as a `#@incdir <dir>` marker
written as the **very first bytes** of the materialised source:

```
#@incdir src/sub
```

You do not write this yourself — the CLI emits it. What matters for using the language:

- Resolution is **CWD-first**. The `#@incdir` retry sits *after* every existing step, so no
  include that resolves today can change meaning; it can only turn an error into a success.
- `#` opens a comment in cyrius, so the marker is inert in every compiler that does not look
  for it — older cycc, cybs, and the cx/JS forks all skip the line.
- ⛔ **The marker is in-band, so a hostile `.cyr` can write one.** Two rules close that: the
  directory must be **relative and `..`-free** (an absolute one would rebuild the
  read-anything primitive CVE-16 removed), and it is read **only at byte 0** — a second
  marker further down the file stays an ordinary comment. A rejected marker is simply unset,
  so the include fails exactly where it fails today.
- `cyrius build /abs/dir/x.cyr` gets no marker when the CLI cannot relativise the path
  against CWD, and keeps the old behaviour. No reach was bought with a hole.

### Entry-file line attribution — `#@srcline` (v6.5.24)

`cyrius build` prepends lines in front of your entry file: `#@incdir`, `#@pkgver`, one
`include` per `[deps].stdlib` module, one `#define` per `-D`, and the **entire text** of
every `[build].modules` file. Until v6.5.24 only `#@incdir` was compensated, so every
`<source>` diagnostic was reported one line late **per prepended line** — with an 18-module
manifest that is +17, and on a short file the reported line can be **past EOF**, which looks
like a compiler fault rather than a defect in your source.

The CLI now writes `#@srcline` as the last thing before your file, and cycc re-anchors
`<source>` to line 1 there. Diagnostics match your editor's line numbers regardless of how
many modules you declare.

- **You never write this marker.** It is emitted by `cyrius build`; it exists in the guide
  only so an unexpected `#@srcline` in a preprocessed dump is recognisable.
- It carries **no line count** — cycc derives the shift from the marker's own position — so
  the accounting cannot drift, and `[build].modules` files of unknown length are handled.
- Raw `cat file.cyr | cycc` gets no marker and keeps the old numbering, which is one more
  reason to build through `cyrius build` rather than piping by hand.
- `#` opens a comment, so the marker is inert to older compilers, cybs and the cx/JS forks.
- Honoured **once**, and it carries no filename, so unlike the `#@file` marker it cannot be
  used to re-point a file span (the hole v6.5.21 closed for `private`). The worst a forged
  `#@srcline` can do is misreport line numbers.

### Kernel-mode module restriction — `#host_only` (v6.5.24)

A stdlib module that depends on a host OS marks itself with `#host_only` in column 0. A
bare-metal build — `--target=<arch>-bare-metal-elf` (which sets `CYRIUS_KERNEL=1`) or a
source `kernel;` declaration — that **includes** such a module now fails with a message
naming it, instead of compiling silently and faulting at runtime inside the kernel:

```
error: bare-metal build includes host-only module: lib/fs.cyr (marked #host_only; not available under CYRIUS_KERNEL)
```

Currently annotated: `lib/fs.cyr`, `lib/process.cyr`, `lib/net.cyr`.

- Only **your own** includes are checked. Modules `cyrius build` prepends from your
  manifest's `[deps].stdlib` are not your kernel's choice and do not fail the build — so an
  existing manifest that lists `fs` keeps working for a kernel target.
- Unannotated modules are always allowed, so adding the marker to a module is opt-in and
  nothing breaks by default.
- `#` opens a comment, so an annotated module compiles normally for every host target.
- Add `#host_only` to your own modules to get the same protection; remove it if a module is
  ever made freestanding.

## Visibility — `private` / `public` (v6.5.0; scoped at insertion since v6.5.38)

By default every fn and global var is visible everywhere, exactly as it always
has been. A file opts IN to encapsulation by declaring `private` at the top:

```
private                        # this FILE is private-by-default

fn helper(): i64 { return 7; } # file-private — callers outside this file error
var _state = 0;                # file-private too

public fn api(): i64 {         # re-exposed to everyone
    return helper();           # in-file calls are unrestricted
}
public var CONFIG = 7;
```

Rules:

- `private` is a bare top-level declaration. It applies to the **file it appears
  in**, not to the files that file includes, and not to the file that includes it.
- `public` marks one item. It is meaningful only inside a `private` file; in an
  ordinary file everything is public already, so it is a no-op you may write for
  documentation.
- A file with **no** `private` declaration is unchanged from pre-6.5.0. Adoption is
  per-file and never forced.
- Referencing a private item from another file is a **hard error**, not a warning:

```
error:main.cyr:12:9: 'helper' is private to lib/thing.cyr
        var x = helper();
            ^
```

- Errors are reported through the multi-error path (v6.4.62), so one compile lists
  every violation instead of stopping at the first.
- `public`/`private` control **visibility, not linkage**: private fns are also
  omitted from the exported symbol table, so they no longer appear in `.dynstr` /
  `nm` output or in `cyrius api-surface`. That is the point — the API surface a
  consumer sees becomes the API surface you declared.
- `pub` is accepted as a synonym for `public` (it is the same lexer token).
- **A private fn cannot be replaced by another file's same-named fn (v6.5.38).** Two files
  may each define a private `_helper`; each file's calls bind to its own, and neither can
  capture the other's. A public fn of the same name stays reachable from everywhere else:

  ```
  # a.cyr                          # b.cyr
  private                          fn _helper(x) { return 7; }   # public
  fn _helper(x) { return 1; }      fn b_entry() { return _helper(0); }  # -> 7
  public fn a_entry() {
      return _helper(0);           # -> 1, always a.cyr's own
  }
  ```

  ⚠ Before 6.5.38 this was **not** true, and it is the reason to pin forward if you rely on
  `private`: the compiler kept one entry per NAME, so `b.cyr`'s definition silently replaced
  `a.cyr`'s — *including for `a.cyr`'s own internal calls* — under a `duplicate fn ... last
  definition wins` warning that read as benign shadowing. Declaring `private` on both sides
  did not help, because visibility was checked only where a name was USED, on top of an
  unchanged global symbol table. Two libraries that each wrote a private `_stream_grow`
  disagreeing about return polarity would silently report every success as a failure.
- Duplicate definitions between two **non-private** files are unchanged: still a
  `duplicate fn ... last definition wins` warning (a hard error if the two disagree about
  arity, since v6.5.37). Two definitions **in one file** are likewise still a duplicate —
  that is a redefinition of one symbol, not a collision between two files.

Both names are reserved words — see the reserved-word note under *Functions*; you
cannot use `public`, `pub`, or `private` as identifiers.

## Preprocessor

```
# Conditional compilation (v5.6.1)
#ifdef CYRIUS_TARGET_LINUX
    var fd = file_open("/proc/self/exe", 0);
#elif CYRIUS_TARGET_WIN
    var fd = win_get_image_handle();
#else
    # macOS / other platforms fall here
#endif

#ifndef CYRIUS_BAREMETAL
    println("running on hosted platform");
#endif
```

The full set: `#ifdef`, `#ifndef`, `#else`, `#elif`, `#endif`. State is
tracked per nesting level — `#elif` after a taken `#ifdef` is correctly
suppressed, and nested blocks skip cleanly inside a parent's skip path.

`#ifplat <plat>` (v5.4.19) is a tighter spelling for arch / OS dispatch:

```
#ifplat aarch64
    asm { dmb ish }
#endif
```

Recognized plat tokens: `x86_64`, `aarch64`, `riscv64` (v5.7.0), `linux`,
`macos`, `windows`, `baremetal`.

## Attributes

Function-level attributes flag intent at declaration; the compiler
warns at call sites or compile time.

```
# v5.6.3 — discarding the return value at statement level is a bug
#must_use
fn checked_op(x): i64 { return x * 2; }

fn main() {
    checked_op(21);     # warning: result of #must_use fn discarded
    var r = checked_op(21);   # OK
}

# v5.6.3 — block marker for ABI-crossing / unchecked memory ops
@unsafe {
    store64(some_raw_ptr, 0);
    var x = load64(some_other_raw_ptr);
}
# Nested @unsafe blocks emit a stylistic warning but compile.

# v5.6.4 — fn-level deprecation; warns at every call site
#deprecated("use sha256_init() — sha1 is collision-broken")
fn sha1_init() { ... }
```

`#must_use` warns only when the result is dropped at expression-statement
level (`fn();`); assignment, `return fn();`, and arg-passing use sites are
unaffected. `#deprecated("reason")` requires a string argument and warns
at every call site (unlike `#must_use`'s discard-only).

## Project Structure

```
myproject/
  cyrius.cyml          manifest (package, build, deps)
  VERSION              version source of truth
  src/
    main.cyr           entry point
    lib.cyr            library entry (for libs)
    *.cyr              source modules
  tests/
    tcyr/              unit test suites — cyrius test scans here
      core.tcyr
      parse.tcyr
    scyr/              soak harnesses (v5.7.38) — cyrius soak runs after the built-in self-host loop
      alloc_pressure.scyr
    smcyr/             smoke harnesses (v5.7.38) — cyrius smoke (fail-fast quick-validation)
      compile_minimal.smcyr
  benches/             benchmarks — cyrius bench scans here
    bench_alloc.bcyr
  fuzz/                fuzz harnesses — cyrius fuzz scans here
    fuzz_parse.fcyr
  dist/                bundled distribution (cyrius distlib)
    myproject.cyr
  lib/                 resolved deps (created by cyrius deps)
  build/               compiled binaries (gitignored)
```

**Discovery roots** — a harness outside every root for its extension is silently ignored:
- `.tcyr` → `tests/` (`tests/tcyr/` is the convention)
- `.bcyr` → `benches/` or `tests/`
- `.fcyr` → `fuzz/` or `tests/`
- `.scyr` → `tests/scyr/` or `soak/`
- `.smcyr` → `tests/smcyr/` or `smoke/`

**Subfolders work (v6.5.7).** `cyrius test` / `bench` / `fuzz` walk their roots
**recursively**, and each also honours an explicit directory argument
(`cyrius bench benches/perf`). Before v6.5.7 the bench and fuzz walkers were flat, so
`benches/perf/core.bcyr` simply never ran *and the command reported success over it*; a
directory argument ran nothing, printed nothing and exited 0. A path that does not exist is
now refused rather than silently building a do-nothing program, and every form prints the
`=== N passed, M failed ===` summary — the single-file form used not to, which made it
unscriptable.

## Build Tool & Dependencies

```sh
# cyrius.cyml declares deps — build auto-resolves them
cyrius build src/main.cyr build/myapp   # resolves deps + compiles
cyrius deps                              # manually resolve deps
cyrius build -v src/main.cyr build/myapp # verbose (shows compiler, binary size)
cyrius test tests/test.tcyr             # resolve deps + compile + run
cyrius tests [dir]                       # recursively run every .tcyr under dir (default tests/)
cyrius bench [path|dir]                  # discover + run *.bcyr (recursive; v6.5.7)
cyrius fuzz [path|dir]                   # discover + run *.fcyr harnesses (recursive; v6.5.7)
cyrius soak [N]                          # N-iter built-in self-host + tests/scyr/*.scyr (v5.7.38)
cyrius smoke                             # tests/smcyr/*.smcyr fail-fast (v5.7.38)
cyrius distlib [profile]                 # bundle src/ modules into dist/{name}.cyr
cyrius distlib --all                     # regenerate the base bundle AND every [lib.X] profile (v6.5.8)
cyrius distlib --check                   # verify bundles are current — compares BYTES, writes nothing (v6.5.8)
cyrius coverage [--full] [--min <pct>]   # reference coverage of src/ (--min gates CI)
cyrius capacity [--check] <src>          # report compiler capacity / CI gate
cyrius lsp                               # build + install cyrius-lsp into ~/.cyrius/bin/
```

⚠ `distlib --check` compares **bytes**, not version strings — a sub-profile can carry a stale
encoder under a fresh version string, which is exactly how sankoch 2.7.6's gzip fix nearly
shipped with all nine sub-bundles still buggy. `--all` replaces the N+1 per-profile ritual.

Each bundle also emits a `dist/<lib>.deps` sidecar naming the stdlib leaves the fold needs in
scope. Since v6.5.10 the base bundle's sidecar is the declared `[deps] stdlib` **unioned** with
an include-scan of the bundled sources, so it cannot under-report against either — an
under-reporting sidecar silently switched OFF `cyrius deps`' own consumer check. Profiles keep
the pruned inference (a profile is a narrow module subset, so unioning the whole declaration in
would over-report and fail a legitimately-narrow consumer).

```toml
# cyrius.cyml
[deps]
stdlib = ["string", "fmt", "alloc", "io", "vec", "str"]

[deps.agnostik]
path = "../agnostik"
modules = ["src/types.cyr", "src/error.cyr"]
# Resolved to: lib/agnostik_types.cyr, lib/agnostik_error.cyr
```

Named deps are namespaced: `lib/{depname}_{basename}`. Stdlib is unprefixed.
Includes are auto-prepended by the build tool — source files only need project includes.

## Linter

```sh
cyrlint myfile.cyr                       # lint a file
cyrius lint                              # lint all stdlib
```

Rules: trailing whitespace, tabs, line length >120 chars, camelCase
fn names, unclosed braces, **global-init forward-ref** (v5.7.32 —
warns when a top-level `var X = expr;` references a var declared
LATER in source order; cyrius initializes globals in declaration
order so the forward ref silently evaluates to 0 at runtime).
`#skip-lint` on a line exempts it from all rules. Brace tracking
skips strings and comments. Identifier scanning is also string-
literal-aware as of v5.7.36 — `var MSG = "FLAG_LATER not yet
defined"; var FLAG_LATER = 1;` does NOT trigger the forward-ref
rule because `FLAG_LATER` is inside a `"..."` literal.

## Ref Directive

```
#ref "config.toml"
# Reads a TOML file and emits key/value pairs as global variables
# Processed during PP_REF_PASS before main compilation
```

## Inline Assembly

```
# Raw bytes
asm { 0x90; }                    # nop

# Mnemonics (kernel instructions)
asm { cli; }                     # Clear interrupts
asm { sti; }                     # Set interrupts
asm { hlt; }                     # Halt CPU
asm { mov cr3, rax; }           # Load page table
asm { lgdt [rax]; }             # Load GDT
asm { lidt [rax]; }             # Load IDT
asm { iretq; }                  # Return from interrupt
asm { int 3; }                  # Software interrupt
asm { invlpg [rax]; }           # Flush TLB entry
asm { in al, dx; }              # Port input
asm { out dx, al; }             # Port output
asm { wrmsr; rdmsr; cpuid; }    # System instructions
```

## Kernel Mode

```
kernel;                          # Emit bare-metal ELF (multiboot1)
# Rest of the file is kernel code
# Entry point: 32-bit boot shim → 64-bit Cyrius code
# Boot: qemu-system-x86_64 -kernel build/kernel -serial stdio
```

## Enums

```
enum Color { RED; GREEN; BLUE; }     # RED=0, GREEN=1, BLUE=2
enum Error { OK = 0; NOT_FOUND = 44; PERM = 13; }  # Explicit values

var c = BLUE;                        # c = 2
var c2 = Color.BLUE;                 # Namespaced access (v1.11.0+)

```

## Sum Types & Tagged Unions (v5.8.21+)

Variants with payload data — first-class sum types built on the existing enum infrastructure.

⭐ **As of v6.6.0 the stdlib types `Result`, `Option` and `Either` are the VALUE FORM** (`: stack`,
below) — they return a `(tag, payload)` register pair and **allocate nothing**. A plain `enum`
you declare yourself still boxes; the value form is opt-in per declaration.

```
# The stdlib shape (lib/result.cyr) — this is what Result IS now:
enum Result<T, E>: stack {
    Ok(v);
    Err(e);
}

var tag, val = Ok(42);   # ZERO allocation — tag in the first register, payload in the second
var et, ev  = Err(7);    # et == 1, ev == 7

# A plain `enum` (no `: stack`) still boxes:
enum Tri<T, U, V> {
    Triple(a, b, c),
    Pair(x, y),
    Single(s),
    Bare                # no parens → auto-incremented int (3 here)
}

var t = Triple(11, 22, 33);   # 32-byte alloc; tag at +0, [11, 22, 33] at +8/+16/+24
```

Boxing is still the right (and only) representation for a variant carrying **two or more**
fields: a register pair holds one tag and one value, so `Pair(a, b)` cannot be a value-form
variant and the compiler says so rather than dropping a field.

### The value form — `enum Name: stack` (v6.5.55, the stdlib default since v6.6.0)

A boxed payload variant **allocates**, from the global bump allocator, whose only reclaim is
`alloc_reset()` — and that invalidates every pointer the allocator has ever handed out, so a
long-running server cannot call it. Through v6.5.x a hundred `sock_send` calls grew the heap by
exactly 1600 bytes and never gave them back. **That is 0 bytes as of v6.6.0.**

```
enum Res: stack { Ok(v); Err(e); }

fn parse(x): i64 {
    if (x > 0) { return Ok(x * 2); }
    return Err(0 - x);
}

fn use(): i64 {
    var tag, val = parse(21);   # ZERO allocation
    if (tag == 0) { return val; }
    return 0 - val;
}
```

- **Zero allocation.** Constructing in a loop grows the allocator by nothing.
- **Zero or one field per payload variant.** The pair carries a tag and one value; `Pair(a, b)`
  in a `: stack` enum is a compile error rather than a silently dropped field. A **nullary**
  variant — `None()` — has no payload to carry, so it returns its tag alone and binds to a
  single variable. (v6.5.67; the rule read "exactly 1" before that, which refused
  `enum Option: stack { None(); Some(v); }` — the shape sum types are actually written in.)
- **Bare (payload-less) variants are unchanged** — still plain integer constants, still sharing
  the same discriminant numbering.
- **The destructuring bind works anywhere**, including at top level (v6.6.0). It was refused
  outside a function before that, which left a top-level Result bind with no legal spelling.
- **A single argument receives the TAG.** `is_ok(t)`, `is_err_result(t)`, `is_none(t)`,
  `is_tag(t, x)` keep their one-argument shape and can even take the call directly —
  `is_ok(f())` reads the tag straight out of the first return register.
- **`?` propagates the pair, with the payload intact** (v6.6.0). It works in expression position
  (`var v = f()?;`) and as a bare statement (`f()?;`). Propagating out of the enclosing function
  means *returning* a pair, so the Err path re-emits **both** halves — a version that restored
  only the tag would hand the caller a stale payload.

#### Bind the pair as a pair — the three refusals

A value-form Result is two values. Any context that keeps only one would silently discard the
payload, which for an `Err` is the error code, so each is a compile error naming the fix:
*"a `: stack` enum returns two values — bind both: `var tag, val = f();`"*.

```
var r = f();             # ✗ single-variable bind      (v6.5.67)
r = f();                 # ✗ assignment                (v6.6.0)
store64(&slot, f());     # ✗ storing into a slot       (v6.6.0)

var t, v = f();          # ✓ bind both halves
var v = f()?;            # ✓ `?` consumes the pair and yields one value
return f();              # ✓ forwarding the pair onward
```

The requirement follows the value through `return`, so forwarding it out of a wrapper and
binding it one-wide there is caught too.

⚠ **A COLLECTION of Results is two parallel slots, not one.** `store64(&arr + i * 8, f())` was
the shape that silently half-stored, and it is how every array of Results was written. Store the
tag and the payload separately (or use a struct).

📎 `stack` is reused rather than a new keyword: it has meant "lives on the stack instead of
being hoisted" since v5.5.36's `stack var buf[N]`, which is the same idea one level up.

Generic params (`<T, E>`) are syntactically accepted but not yet semantically bound (mono-only erasure today). Variant separators may be `;` or `,` — mixed in same decl works. In mixed enums, bare names stay as int constants and paren'd names heap-allocate; convention is paren-consistent (`enum Option { None(); Some(v); }`) for sum types you'll match against.

Helper API:

- `lib/tagged.cyr` — `Option` / `Either` + the shared `tag(t)` /
  `is_tag(t, expected)` primitives.
- `lib/result.cyr` — `Result<T, E>` + Result-specific helpers. Carved
  out of `lib/tagged.cyr` at v5.8.28 so consumers that only want
  `Result` can include just the dedicated module; `lib/tagged.cyr`
  transitively includes it.

⛔ **v6.6.0 changed the ARITY of these helpers**, because rdx does not reach a parameter — no
function can receive a Result in one argument and read its payload:

| helper | v6.6.0 | note |
|---|---|---|
| `is_ok` / `is_err_result` / `is_none` / `is_some` / `is_left` / `is_right` | `(t)` | unchanged — argument 1 receives the tag |
| `is_tag` | `(t, expected)` | unchanged |
| `tag` | `(t)` | now the identity; the tag is already the first half |
| `result_unwrap` / `err_code_of` / `result_print` / `unwrap` | `(t, v)` | **was 1 argument** |
| `result_unwrap_or` / `unwrap_or` | `(t, v, fallback)` | **was 2 arguments** |
| `ok_via` / `err_via` | `(a, v)` | unchanged signature; allocates nothing now, and the allocator argument is ignored |
| `payload` | **DELETED** | no 1-argument replacement — `payload(r)` becomes `r` |
| `tagged_new` | **DELETED** | built a box only `tag()`/`payload()` could read |

```
include "lib/tagged.cyr"          # for Option / Either + primitives
# or:
include "lib/result.cyr"          # for Result alone

var opt = Some(42);
if (is_some(opt) == 1) {
    var v = unwrap(opt);          # = 42
}
var v = unwrap_or(opt, 0);        # 42 if Some, fallback if None

var r = Ok(99);
if (is_ok(r) == 1) {
    var v = result_unwrap(r);     # = 99
}
```

`Option`, `Result`, `Either` are compiler-generated since v5.8.23;
helpers (`is_none` / `is_some` / `unwrap` / `unwrap_or` / `is_ok` /
`is_err_result` / `result_unwrap` / `err_code_of` / `is_left` /
`is_right`) wrap them.

## `?` Propagation Operator (v5.8.29+)

Postfix `?` on a `Result`-shaped expression desugars at the call
site to: check the tag → if `Err`, return that same Result from the
enclosing fn → if `Ok`, yield the payload in rax. Highest precedence
(binds tighter than `*` / `/`), so `foo()? * bar` parses as
`(foo()?) * bar`. It works in expression position (`var v = f()?;`)
and as a bare statement (`f()?;`).

⭐ **On the value form (v6.6.0) the Err path re-emits BOTH halves.**
Propagating a Result *out of* the enclosing function means returning
a pair, so the payload register is restored alongside the tag —
restoring only the tag would hand the caller a correct verdict with a
stale error code. On a boxed enum the Err path returns the pointer,
as it always did.

```
include "lib/alloc.cyr"
include "lib/result.cyr"

fn safe_div(a, b) {
    if (b == 0) { return Err(1); }
    return Ok(a / b);
}

fn chain(a, b, c) {
    var x = safe_div(a, b)?;     # Err short-circuits the chain
    var y = safe_div(x, c)?;
    return Ok(y);
}

alloc_init();
chain(100, 4, 5);                # Ok(5)
chain(100, 0, 5);                # Err(1) from first ?
```

`?` is also valid as a bare statement (`expr?;`) — the unwrapped
`Ok` value is dropped, but the `Err` early-return still fires
(v5.8.31 closed the parse-statement gap; v5.8.29 only handled the
`var x = expr?;` form).

`?` outside any fn body is a parse-time error
(`?: '?' propagation operator only valid inside a fn body`). The
stricter "outside Result-returning fn is type error" check is
pending fn return-type tracking.

## No try / catch — design decision

Cyrius **does not and will not** have unwinding exceptions. There
is no `try` / `catch` / `throw` / `finally`, and none is planned.
`Result<T, E>` + postfix `?` is the only sanctioned propagate-or-
handle mechanism; checked-arithmetic overflow (`+?` / `-?` / `*?`)
is the only "panic"-shaped path and it `syscall(60, 57)`s out
unconditionally — no unwinder, no handlers, no stack walk.

The reasoning, so this question doesn't recur:

- **Bare-metal target hostility** — Cyrius compiles the AGNOS
  kernel (v6.2.x bare-metal target, gnoboot, kernel proper). You
  cannot unwind through an ISR frame; kernel code would have to
  ban `catch` anyway, leaving the language with a userland-only
  feature that can't be used where Cyrius's primary consumer lives.
- **ABI cleanliness** — every call site would become a potential
  unwind point, requiring `.eh_frame` / `.gcc_except_table` /
  SEH tables, landing pads, and a polymorphic exception-object
  protocol. That breaks the i64-everywhere tenet (ADR-002) and
  bloats the self-hosting compiler's emit surface.
- **The pattern already works** — `Result<T, E>` returns in
  registers, propagates via `?` in a single byte of source per
  call site, and pairs with per-module typed error enums (next
  section). Rust + Go-with-errors both converged here for systems
  work; the costs of unwinding don't pay back.
- **Cross-frame context, if pressure surfaces, is solved with
  richer error types**, not with unwinding — `Result<T, ErrorChain>`
  or `result_with_context()` helpers stay in the existing model.

If you find yourself wanting `try` / `catch`, the Cyrius answer
is: return a richer `Result`, propagate with `?`, and match the
`Err` variant where you'd have written `catch`.

## Typed errors in the stdlib (v5.8.30+)

Every Result-returning stdlib fn pairs with a per-module error
enum. Variant names are module-prefixed to coexist in the global
enum-variant namespace.

| Module | Enum | Variants |
|--------|------|----------|
| `lib/io.cyr` | `IoError` | `IoNotFound` `IoAccessDenied` `IoBadFd` `IoFailed` `IoOther` |
| `lib/json.cyr` | `JsonError` | `JsonIoErr` `JsonParseErr` `JsonOther` |
| `lib/toml.cyr` | `TomlError` | `TomlIoErr` `TomlParseErr` `TomlOther` |
| `lib/cyml.cyr` | `CymlError` | `CymlIoErr` `CymlOther` |
| `lib/http.cyr` | `HttpError` | `HttpBadUrl` `HttpNetErr` `HttpNon2xx` `HttpOther` |
| `lib/dynlib.cyr` | `DynlibError` | `DynlibNotFound` `DynlibBadElf` `DynlibSymMissing` `DynlibOther` |
| `lib/pwd.cyr` | `PwdError` | `PwdNotFound` `PwdLoadFailed` `PwdBufTooSmall` `PwdOther` |
| `lib/grp.cyr` | `GrpError` | `GrpNotFound` `GrpLoadFailed` `GrpBufTooSmall` `GrpOther` |
| `lib/shadow.cyr` | `ShadowError` | `ShadowNotFound` `ShadowLoadFailed` `ShadowBufTooSmall` `ShadowOther` |
| `lib/pam.cyr` | `PamError` | `PamAuthFail` `PamHelperMissing` `PamPipeFailed` `PamForkFailed` `PamExecFailed` `PamOther` |

Result-returning fns use the `_r` suffix:

```
var fd_r = file_open_r("/etc/hostname", 0, 0);
if (is_err_result(fd_r) == 1) {
    if (load64(fd_r + 8) == IoNotFound) { ... }
}

# With ? propagation:
fn read_line(path) {
    var fd  = file_open_r(path, 0, 0)?;
    var buf[256];
    var n   = file_read_r(fd, &buf, 256)?;
    file_close_r(fd);
    return Ok(n);
}
```

The legacy int-returning fns (`file_open` / `json_parse_file` /
etc.) remain callable for back-compat alongside the `_r` Result-returning
variants — they were not removed at the v6.0.0 closeout and have no current
removal date. Prefer the `_r` shape in new code.

## Switch

```
fn classify(n) {
    switch (n) {
        case 0: return 0;
        case 1: return 1;
        default: return 99;
    }
    return 0;
}
```

Note: case values must be integer literals. No fallthrough — each case is independent.

### Leaving a case (v6.5.20)

A case body may be left by **any** of `return`, running off the end of the body, or
`break;` — all three are correct, in both dispatch regimes (`switch` compiles to an
if-chain under 4 cases and to a jump table at 4 or more dense cases).

```
fn pick(x) {
    var r = 0;
    switch (x) {
        case 0: { r = 10; }          # falls out of the body
        case 1: { r = 11; break; }   # break leaves the SWITCH
        case 2: { return 12; }       # return leaves the FUNCTION
        default: { r = 99; }
    }
    return r;
}
```

`break` inside a `switch` or `match` leaves **that construct**, exactly as in C — not
the enclosing loop. `continue` is unaffected: it belongs to the nearest enclosing loop
and treats an intervening switch/match as transparent.

```
while (i < 3) {
    switch (x) {
        case 1: { n = n + 1; break; }   # breaks the SWITCH; the while keeps running
        default: { n = n + 100; }
    }
    n = n + 10;
    i = i + 1;
}
```

> ⚠ **Before v6.5.20 none of this was true, and it failed silently.** Falling out of a
> case body in the table regime jumped into the middle of an instruction (SIGSEGV with a
> `default:` present, the WRONG ANSWER with no `default:` and no diagnostic at all), and
> `break` in a case either broke the enclosing loop or, with no loop to attach to, left
> an unpatched jump — also a SIGSEGV. Only `return` bodies were safe, which is why the
> corpus did not catch it. If you are reading code written against an older compiler,
> case bodies phrased entirely as `case N: { return …; }` are likely a workaround.
> **Whether `break` should break the switch (C semantics, what ships today) or be
> rejected outright remains open to the maintainer** — this section documents what the
> compiler does now.

## Match (Pattern Match, v5.8.22+)

```
enum Status { PENDING; ACTIVE; DONE; }

fn label(s) {
    var r = 0;
    match s {
        PENDING => { r = 1; }
        ACTIVE  => { r = 2; }
        DONE    => { r = 3; }
    }
    return r;
}
```

A `match` arm body is left the same three ways a `switch` case is — `return`, running
off the end, or `break;` — and `break` leaves the `match`, not an enclosing loop
(v6.5.20; `match` shared the pre-v6.5.20 miscompile described under *Leaving a case*).

The compiler verifies coverage when at least one arm is a variant of an enum. Missing variants emit a warning; opt out with `_ =>`:

```
match s {
    PENDING => { ... }
    ACTIVE  => { ... }
}
# warning:<file>:<line>:<col>: non-exhaustive match over enum 'Status'
#   — covers 2 of 3 variants; add `_ =>` to opt out

match s {
    PENDING => { ... }
    _       => { ... }    # explicit catch-all — no warning
}
```

Duplicate arms (v5.8.25):

```
match s {
    PENDING => { ... }
    PENDING => { ... }   # warning: duplicate match arm 'PENDING'
}
```

The runtime `cmp/jcc-skip` cascade picks the FIRST matching arm — duplicate arms are dead at runtime (first wins). The check is metadata-only; codegen unchanged.

Match on a tagged value compares against the heap pointer (always unequal), not the tag. Extract the tag explicitly:

```
# Value form (Option is `: stack` since v6.6.0) — bind both halves, match on the tag:
var t, v = Some(42);
match t {
    Some => { ... v is the payload ... }
    None => { ... }
}

# A BOXED payload enum you declared yourself — tag at +0, fields from +8:
enum Shape { Circle(r); Rect(w, h); }
var sh = Rect(3, 4);
match load64(sh) {          # extract tag at +0
    Circle => { var r = load64(sh + 8); ... }
    Rect   => { var w = load64(sh + 8); var h = load64(sh + 16); ... }
}
```

⚠ `match load64(x)` is the **boxed** shape. Applying it to a value-form enum dereferences the
tag (0 or 1) as a pointer and faults — on the value form the tag is already a plain value, so
`match t` is the form.

Or use the helper API (`is_some` / `unwrap_or` / etc.) which encapsulates this.

## Function Pointers

```
fn add(a, b) { return a + b; }
var fp = &add;                       # Get function address
```

Call through a pointer with the `callptr` builtin (v6.0.70+) — a
compiler-emitted indirect call (`IR_CALL_INDIRECT`: x86 `call [rbp-disp]`,
aarch64 `blr`), no library needed:

```
fn run() {                           # callptr needs a function frame
    var fp = &add;
    var result = callptr(fp, 20, 22);   # result = 42 — callptr(callee, args...)
}
```

`callptr(callee, arg1, …, argN)` evaluates the callee, then calls it with
the given args (any count); the result lands in the usual return register.
It works on every backend (x86_64, aarch64, Windows PE) and is the basis
for COM-vtable dispatch (`callptr(load64(load64(obj) + slot*8), obj, …)`).
The callee is spilled to a frame slot, so `callptr` must be used **inside a
function** (top-level use is a compile error — top-level vars are globals,
with no frame).

The older `lib/fnptr.cyr` helper API (`fncall0`..`fncall8`) still works for
existing code:

```
include "lib/fnptr.cyr"
var result = fncall2(&add, 20, 22);  # result = 42
```

Since v6.5.17 a `fncallN(…)` call written **inside a function** compiles to the
same indirect-call sequence as `callptr` rather than to a call into
`lib/fnptr.cyr` — the include is still required (it is what makes the name
resolve), but the marshalling is the compiler's, which is the better one for
more than four arguments on Windows and more than six elsewhere. At top level
it stays an ordinary call into the library.

## Closures

A closure literal `|params| body` is an anonymous function; its value is a
function pointer, so you call it the same way — `callptr` or `fncallN`:

```
fn run() {                           # closures live inside a function
    var add = |a, b| a + b;          # body is an expression …
    var dbl = |x| { var y = x * 2; return y; };   # … or a { block }
    var ans = || 42;                 # zero-param thunk (`||`)
    var r = callptr(add, 40, 2);     # 42  (or fncall2(add, 40, 2))
}
```

The body may be a single expression or a `{ … }` block (with `return`).
Parameters and any locals declared inside the closure are its own; the
enclosing function's locals are untouched (so a closure declared after a local
doesn't clobber it).

**Lexical capture by value (v6.3.8).** A closure body may reference a variable
from the enclosing scope (a *free variable*). Each such variable is captured
**by value** at the point the closure is constructed — copied into a small
heap environment object `[fn_ptr, cap0, cap1, …]`. The closure value is an
**opaque handle** to that object, and `callptr` / `fncallN` recognise it and
dispatch it (load the real code address from the object, pass the object itself
as a hidden trailing argument), so call sites look identical to the
non-capturing case:

```
fn run(): i64 {
    var base = 40;
    var f = |x| base + x;            # captures `base` by value
    return callptr(f, 2);            # 42
}
```

A non-capturing closure stays a bare function pointer (no allocation); only
closures that actually read an enclosing local build an environment object.

**The handle is opaque — do not do arithmetic on it, dereference it, or print
it as an address (v6.5.17).** It is the environment pointer with its top bit
set, which is how any call site can tell a closure from a plain function
pointer *at run time* rather than from the type of the variable it happens to be
sitting in. That is what makes a capturing closure keep working after it leaves
the `var` it was built in — passed to another function, returned, stored in a
global, or round-tripped through `store64`/`load64`:

```
fn apply(f): i64 { return callptr(f, 1); }   # or fncall1(f, 1)
fn make(n): i64 { var f = |x| n + x; return f; }

fn run(): i64 {
    var base = 41;
    var f = |x| base + x;
    return apply(f) + callptr(make(0), 0);   # 42 + 0
}
```

Before v6.5.17 every one of those escapes segfaulted: the "is this a closure"
decision was made at compile time from the declaring variable's type, and the
value outlived that fact.

Capture is **by value**: the closure sees the value the variable held at
construction. Mutating the original afterward does not change what the closure
returns, and the closure cannot write back to the enclosing variable. Two
closures built from the same literal have independent environments.

Because the environment is heap-allocated, a translation unit that constructs a
capturing closure must `include "lib/alloc.cyr"` and call `alloc_init()` before
the closure is built. (A non-capturing closure needs neither.)

**Limitations.** A capturing closure takes at most **five** parameters on
Linux/macOS (x86_64 and aarch64) and **three** on Windows — the hidden
environment argument occupies the next argument register, and it is a compile
error to declare more. A capturing closure with eight arguments cannot be
called through `fncall8` (there is no `fncall9` for the environment to ride in);
use `callptr`, which has no arity ladder. `fncallN` at **top level** is an
ordinary call into `lib/fnptr.cyr` and does not dispatch closures — call it from
inside a function. Captured closures are flat (no capture of a capture across
two nested closure levels).

## Generic Functions

A function may be parameterized over a type with `<T>`:

```
fn id<T>(x: T): T { return x; }
fn add<T>(a: T, b: T): T { return a + b; }
fn run(): i64 {
    return add(id(20), id(22));   # 42
}
```

The type parameter `T` may appear in parameter types (`x: T`), the return type
(`: T`), and inside the body (`var y: T`, `sizeof(T)`, `slice<T>`). At a call,
the concrete type is **inferred** positionally from the arguments.

Type arguments may be **inferred** from the call (`add(1, 2)`) or written
**explicitly** (`add<i64>(x)`, `add<i32>(x)`).

**Monomorphization.** Cyrius is i64-everywhere (ADR-002), so a generic
definition's base *is* its i64 instantiation: the body is emitted once with
`T → i64`, and i64-typed calls are ordinary direct calls to it. A non-i64 type
argument (`add<i32>`, `Box<Point>`) is **monomorphized on demand**: the
specialized instance `add$i32` / `Box$Point` is emitted **once** (deduped — a
second `add<i32>` call reuses it) and called normally. There is no runtime type
dispatch — `T` is resolved entirely at compile time.

### Generic structs

A struct may be parameterized too:

```
struct Pair<T> { a: T; b: T; }
struct Box<T>  { value: T; }
fn run(): i64 {
    var p: Pair<i32>;            # instance with i32 fields
    p.a = 40; p.b = 2;
    return p.a + p.b;            # 42
}
```

The type argument may itself be a struct (`Box<Point>`) — the instance's field
is laid out at the concrete type's size, so a following field lands at the right
offset. Each distinct `Struct<type-args>` mints one deduped instance.

**Status & limits (v6.3.10).** Generic functions and structs are supported over
i64, narrow scalars (`i32`/`i16`/`i8`), and struct type arguments, inferred or
explicit. Function bodies follow the inline-candidate shape (≤2 type-bearing
params, straight-line — no `if`/`while`/`var`-decl control flow). Single type
parameter is the well-tested case; multi-parameter (`Pair<T, U>` with distinct
`T`/`U`) maps both to the first argument for now. Enum generic params
(`<T, E>`) remain syntactically accepted but type-erased.

## Async / Await

`async fn` and `await` are sugar over the cooperative epoll runtime
(`lib/async.cyr`). Calling an `async fn` builds a **Future** — a deferred
computation — rather than running the body immediately; `await` forces the
Future to its value.

```
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"

async fn add(a, b): i64 { return a + b; }

fn main(): i64 {
    alloc_init();
    var f = add(40, 2);        # builds a Future — the body has NOT run yet
    return await f;            # forces it → 40 + 2 = 42
}
```

`await` can also be applied directly to a call (`await add(40, 2)`), and Futures
can be scheduled on a runtime and forced cooperatively:

```
var rt = async_new();
async_spawn_future(rt, fetch(url));   # schedule a Future as a task
async_run(rt);                        # drives spawned Futures to completion
```

**Lowering.** An `async fn f(args)` compiles to a constructor that allocates a
heap Future `[ &f$impl, argc, args… ]` (the body is emitted as a hidden `f$impl`)
and returns its pointer. `await fut` lowers to `future_force(fut)`, which calls
the bundled impl with the bundled args (via `fncallN`) and returns its value.
The Future object reuses the same heap construction as a closure env. Requires
`include "lib/alloc.cyr"` (the Future is heap-allocated) and `lib/async.cyr`
(for `future_force`); `alloc_init()` must run before the first `async`-fn call.

**Gating.** `async`/`await` are opt-in: compile with `CYRIUS_ASYNC=1`. A default
build rejects them with a clear error (so default codegen — which has no
async — stays byte-identical). Enable via the env var or `cyrius build` flags.

**Status & limits (v6.3.11).** `async fn` (0–6 params) + `await` build and force
first-class, spawnable Futures over the existing runtime — same cooperative
semantics, sugarier surface. A Future re-runs its body on each `await`
(force-once memoization is a follow-on). True stackless coroutines that *suspend
and resume mid-body across an `await`* (a poll-driven state machine, without
bundling the whole call) are a planned follow-on requiring a poll-based runtime;
the current model is deferred-then-forced, which matches the run-to-completion
runtime. `async` generic fns and struct-returning `async fn`s are not yet
supported.

## Global Initializers

Variables can be declared among function definitions:

```
fn get_value() { return global_var; }
var global_var = 42;             # Visible to functions above
var r = get_value();             # r = 42
```

**Initialized-globals cap (per compilation unit).** A top-level `var` whose
initializer is anything other than a bare positive integer literal — a call
(`var t = alloc(1024);`), an identifier, or an expression — is a *deferred
initializer*: its RHS runs once, before `main`, and it consumes one slot in the
compiler's `gvar_toks` table. That table holds **4096** slots (raised from 1024
at v6.3.41; see the heap-map note in `src/main.cyr`). Exceeding it is a hard
error, not a silent failure:

```
error:<file>:<line>:<col>: too many initialized globals (max 4096)
```

What does **not** count against the 4096:

- **Bare integer-literal initializers** (`var x = 42;`) — these take a
  static-init fast path (baked into the image), not the deferred table.
- **Enum members** (`enum E { A = 0; B = 1; }`) — const-folded at parse time.
  For a large family of compile-time constants, prefer an `enum` over many
  `var … = <literal>;` decls.

The cap is per *compilation unit* (the whole preprocessed source, including all
`include`d libraries), so vendoring several dist bundles into one program sums
their deferred globals — that is what the 4096 ceiling is sized for.

## String Standard Library

```
include "lib/string.cyr"

strlen(s)              # Length of null-terminated string
streq(a, b)            # Compare strings (1=equal, 0=not)
memeq(a, b, n)         # Compare n bytes
memcpy(dst, src, n)    # Copy n bytes
memset(dst, val, n)    # Fill n bytes
memchr(s, c, n)        # Find byte in buffer (-1 if not found)
strchr(s, c)           # Find byte in string (-1 if not found)
print_num(n)           # Print decimal to stdout
println(s)             # Print string + newline
```

## Standard Libraries

```
include "lib/string.cyr"  # strlen, streq, memcpy, memset, memchr, strchr, print_num, println
include "lib/alloc.cyr"   # alloc_init, alloc, alloc_reset, alloc_used (bump allocator)
                          # + arenas (arena_new/_growable, arena_alloc, arena_reset, arena_free)
                          # + the allocator vtable (allocator_new, alloc_via/realloc_via/free_via/reset_via)
include "lib/str.cyr"     # Str type: str_from, str_len, str_eq, str_cat, str_sub, str_print
include "lib/vec.cyr"     # Dynamic array: vec_new, vec_push, vec_pop, vec_get, vec_set, vec_len
include "lib/io.cyr"      # File I/O: file_open, file_read, file_write, file_close, file_read_all
                          # + the portable x* wrapper set (see below)
include "lib/fmt.cyr"     # Formatting: fmt_int, fmt_hex, fmt_hex0x, fmt_bool, fmt_byte
include "lib/args.cyr"    # CLI args: args_init, argc, argv
include "lib/fnptr.cyr"   # Function pointers: fncall0, fncall1, fncall2
include "lib/thread.cyr"  # Threads (clone+mmap) incl. thread_create_detached / thread_is_done,
                          # mutex (three-state futex), MPSC channels (chan_send/recv + try_ variants)
include "lib/async.cyr"   # Async primitives
include "lib/freelist.cyr"# Freelist allocator (free + reuse, O(1) alloc/free)
include "lib/math.cyr"    # Math functions: f64_atan and extended math ops
include "lib/protobuf.cyr"# proto3 wire codec: pb_write_*/pb_read_* (needs string.cyr + str.cyr)
```

### The portable `x*` wrapper set — never hand-roll `sys_*`

`lib/io.cyr` exports a length-carrying, per-target-bridged wrapper for each filesystem
primitive: `xopen`, `xunlink`, `xrmdir`, `xmkdir`, `xmkdir_p`, `xsymlink`, `xreadlink`,
`xlink`, `xfsync`, `xstat`, `xgetdents`, `xlseek`, `xflock`. Call these instead of the raw
`sys_*` — agnos's syscalls carry an **explicit byte length** and reorder flags, so a
Linux-shaped `sys_open(path, O_RDONLY, 0)` lands `O_RDONLY` in `namelen`: a silent ABI
miscompile, no trap, that breaks every file op off Linux. Windows reroutes through kernel32
(`DeleteFileW`, `MoveFileExW`, …) behind the same names. `cyrlint` flags a raw `sys_open`
with literal flags for exactly this reason and points at the wrappers.

The set was **completed at v6.5.7** (`xmkdir`, `xmkdir_p`, `xsymlink`, `xreadlink`, `xlink`,
plus `sys_chdir` and `signal_default`, which had no counterpart to `signal_ignore` even
though `SIG_IGN` is inherited across `execve`). ⚠ That release is also the cautionary tale
for this whole family: `xrmdir` had been **broken on macOS-arm64 since the day it shipped**,
because the Mach-O branch mapped `unlinkat` to Darwin's `unlink` with an arg-shift that
dropped the dirfd and the flag — right for `unlink`, fatal for `rmdir`, which is the same
syscall distinguished only by `AT_REMOVEDIR`. Five of the seven defects found there were
half-fixes that stopped at the first symptom. If you add a wrapper, add a `vr01_` test with
it, or it is never run off-host.

## Allocators & Arenas

`lib/alloc.cyr` ships three layers: the process-wide bump allocator (`alloc`), independent
**arenas**, and an **allocator vtable** so a library can take its memory source as a parameter.

### `alloc_reset()` invalidates everything

```
alloc_reset();     # rewinds the global bump arena to its first chunk
```

⚠ **This invalidates every pointer the allocator has ever handed out**, including ones the
stdlib itself is holding. Any `Str`, `Vec`, `HashMap`, arena or struct built before the reset
is dangling afterwards — the span is zeroed *and re-issuable*, so a stale pointer reads zeros
until something else is allocated over it, then reads that. Reset only when nothing from the
previous epoch will be read again. (v6.5.7 fixed one instance of this biting the stdlib: the
memoized default allocator cached its vtable *inside the arena it describes*, so `alloc_reset`
invalidated the allocator itself. The vtable now lives in static storage — but consumer-held
pointers are still the caller's problem.)

### Arenas and the exhaustion policy (v6.5.9)

```
var a = arena_new(65536);              # fixed-size
var b = arena_new_growable(65536);     # chains another chunk instead of failing
arena_set_on_full(a, ARENA_FULL_ABORT);

var p = arena_alloc(a, 128);
arena_reset(a);                        # rewind; the chunk chain is RETAINED
arena_free(a);
```

| policy | behaviour |
|---|---|
| `ARENA_FULL_NULL` (0) | return 0 — **the default**, unchanged from every prior release |
| `ARENA_FULL_GROW` (1) | chain another chunk (`arena_new_growable` / `arena_allocator_growable`) |
| `ARENA_FULL_SPILL` (2) | serve overflow from the global allocator — spilled bytes are never reclaimed by reset |
| `ARENA_FULL_ABORT` (3) | die loudly at the allocation instead of faulting three layers away |

Why the policy matters: a returned 0 is **indistinguishable from a valid `Str`** — there is
no option type and no error channel through the `_a` families — so it flows on and the first
thing that touches it dereferences it. "Arena too small" was observable as a SIGSEGV several
layers away, with no indication which allocator ran out.

⚠ **GROW retains its chunks across `arena_reset`.** The bump allocator underneath has no
`free()`, so releasing them is not expressible — and it is not what an arena wants: reset
rewinds to the first chunk and re-uses the chain, so a request loop converges on its
high-water mark and then allocates nothing. Use `arena_capacity_total(a)` for the whole
chain (`arena_used` cannot show it once the arena has grown).

### The allocator vtable

```
var al = arena_allocator(65536);       # or bump_allocator() / arena_allocator_growable(n)
var p = alloc_via(al, 128);
reset_via(al);
```

`alloc_via` / `realloc_via` / `free_via` / `reset_via` read the vtable inline (v6.5.10 — the
dispatch was previously five call frames deep, ~15 ns, and cyrius does not inline, so each was
real; it is now ~11 ns). `allocator_alloc_fn` / `allocator_state` and friends remain as public
accessors — the hot path simply stopped calling them.

## Protobuf (proto3 wire codec)

`lib/protobuf.cyr` is a minimal, hand-driven **proto3 wire-format** encoder/decoder
— no `.proto` compiler, no codegen. You build and parse messages field-by-field.
Pure Cyrius, no syscalls; encode appends to a `str_builder`, decode is `load8` +
pointer math over a raw buffer. It covers the wire subset OTLP / gRPC / proto3 use:

| Wire | Types | Write | Read |
|---|---|---|---|
| 0 VARINT | int32/64, uint32/64, sint (zigzag), bool, enum | `pb_write_int` / `pb_write_bool` / `pb_write_sint` | `pb_read_varint` (+ `pb_unzigzag`) |
| 1 I64 | fixed64, sfixed64, **double** | `pb_write_fixed64` / `pb_write_double` | `pb_read_fixed` / `pb_read_double` |
| 2 LEN | string, bytes, embedded message, packed | `pb_write_string` / `pb_write_bytes` / `pb_write_message` | `pb_read_bytes` |
| 5 I32 | fixed32, sfixed32, **float** | `pb_write_fixed32` / `pb_write_float` | `pb_read_fixed` / `pb_read_float` |

`pb_read_tag` splits a tag into (field number, wire type); `pb_skip` advances past
an unknown field for forward-compatible parsing. Nested messages are just a
length-delimited field whose bytes are another encoded message (`pb_write_message`).

**double / float** take and return a Cyrius `f64` directly — an f64 value *is* its
8-byte IEEE-754 bit pattern, so `pb_write_double` is fixed64 of those bits;
`pb_write_float` narrows to 32-bit via the `f32_from` builtin, and `pb_read_float`
widens back via `f32_to` (both native since 6.2.18 — no `math.cyr` include needed).

```
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/protobuf.cyr"

# Encode a message: field 1 = int 150, field 2 = "hi", field 3 = double 3.5
var sb = str_builder_new();
pb_write_int(sb, 1, 150);
pb_write_string(sb, 2, "hi");
pb_write_double(sb, 3, f64_div(f64_from(7), f64_from(2)));
var msg = str_builder_build(sb);          # str_data(msg), str_len(msg) = the wire bytes

# Decode: read field 1
var buf = str_data(msg); var len = str_len(msg);
var field = 0; var wire = 0;
var pos = pb_read_tag(buf, 0, len, &field, &wire);   # field=1, wire=0
var v = 0; pos = pb_read_varint(buf, pos, len, &v);  # v = 150
```

## AGNOS System Libraries

The AGNOS components (agnostik, agnosys, …) are **downstream sibling
repos**, not bundled in cyrius's `lib/`. Consume them as named deps in
`cyrius.cyml` — the build tool resolves each picked module to a flat,
namespaced file `lib/{depname}_{basename}.cyr` (see *Dependencies* above;
there is no `lib/{depname}/` subdirectory form):

```
# cyrius.cyml
[deps.agnostik]
path = "../agnostik"
modules = ["src/error.cyr", "src/types.cyr", "src/security.cyr",
           "src/agent.cyr", "src/audit.cyr", "src/config.cyr"]

[deps.agnosys]
path = "../agnosys"
modules = ["src/syscall.cyr"]
```

Resolution produces, e.g., `lib/agnostik_error.cyr` (error codes,
`err_is_retriable`, `err_print`), `lib/agnostik_types.cyr` (agent/status
enums), `lib/agnostik_security.cyr` (Permission bitmask, Role,
SecurityContext), plus the agent/audit/config structs, and
`lib/agnosys_syscall.cyr` (syscall numbers + wrappers). The build tool
auto-prepends the resolved includes; source files only reference their own
project includes.

<!-- STALE: the former kybernet init-system block here (console / signals /
     reaper / privdrop / mount / cgroup / eventloop) referenced modules that
     no longer exist in ../kybernet/src (now only bench/main/test.cyr).
     Removed pending a human decision on whether kybernet still exposes an
     includable init-system surface to re-document. -->

## Inline Assembly

```cyrius
fn io_outb(port, val) {
    var p = port;
    var v = val;
    asm { 0xBA; 0xF8; 0x03; }    # raw bytes: mov dx, 0x3F8
    asm { outb; }                  # mnemonic
}
```

**Stack layout** (critical for inline asm):
```
fn foo(a, b) {         # a at [rbp-0x08], b at [rbp-0x10]
    var x = 1;         # x at [rbp-0x18]
    var y = 2;         # y at [rbp-0x20]
    asm { ... }        # rax/rcx may hold temp values
}
```

**Warning**: `asm` writing to `[rbp-0x08]` clobbers param `a`. If you need
asm access to specific memory, use globals or declare dummy locals to push
offsets past the params.

## Known Limitations

- `for` loop step must be simple assignment (`i = i + 1`)
- Exit codes truncated to 0-255 (Linux limitation)
- Max 4096 global vars with *non-literal* initializers per compilation unit
  (raised from 1024 at v6.3.41; integer-literal inits and enum members are free
  — see **Global Initializers** for the counting rule)
- **67** builtin/intrinsic names plus the statement keywords are reserved and cannot be used
  as identifiers — `TOKNAME_BUILTIN` in `src/common/util.cyr` is the list; see the
  reserved-word note under **Functions**. (This bullet used to name four of them, which is
  how the other sixty came as a surprise.)
- Closures (`|x| body`) support lexical capture by value (v6.3.8) — a body may
  reference enclosing locals, captured by value at construction. Windows PE has
  supported capturing closures since v6.4.26 (this bullet claimed otherwise for
  eight minors). A capturing closure is capped at five parameters on
  Linux/macOS and three on Windows, its value is an opaque handle rather than an
  address, and it must be written inside a function. See the **Closures**
  section.

## Gotchas

- **Dynamic loop bounds**: `for (i = 0; i < GLOBAL; ...)` re-evaluates each iteration
- **Operator overloading**: multi-field structs pass addresses, single-field pass values
- **Enum constructors**: auto-generated `Ok(42)` calls `alloc()` — init heap first

## Building

```sh
# Bootstrap from seed
sh bootstrap/bootstrap.sh

# Build a program
cyrius build src/main.cyr build/myapp

# Cross-compile for aarch64
cyrius build --aarch64 src/main.cyr build/myapp_arm

# Run tests
sh scripts/check.sh              # Full audit: self-host + heap + tests + lint
sh tests/gates/memory/heapmap.sh              # Heap map overlap detection

# Boot kernel
qemu-system-x86_64 -kernel build/kernel -serial stdio -display none
```

## Targeting Windows (PE) (v6.1.16+)

Cyrius compiles to Windows PE32+ (x86_64, win_amd64) from Linux or macOS via
the `--win` cross-compilation flag. The compiler injects the `CYRIUS_TARGET_WIN=1`
environment variable into the build pipeline, routing platform-specific code paths
through Windows syscall reroutes (kernel32 and shell32 imports) instead of POSIX
syscalls.

### Cross-Building for Windows

```sh
# Cross-compile a Windows PE32+ executable from Linux/macOS
cyrius build --win src/main.cyr build/myapp.exe

# Or via the environment variable (useful in build scripts)
CYRIUS_TARGET_WIN=1 cycc < src/main.cyr > build/myapp.exe
```

The output is a valid PE32+ executable that runs on Windows x86_64. The flag is
mutually exclusive with `--agnos` (bare-metal kernel target) and `--aarch64`
(ARM64 cross-compile); `--win` implies the x86_64 instruction set.

### Conditional Compilation

Use the `#ifdef CYRIUS_TARGET_WIN` preprocessor guard to write cross-platform
code. The compiler defines exactly one of `CYRIUS_TARGET_LINUX`, `CYRIUS_TARGET_WIN`,
or `CYRIUS_TARGET_MACOS` per build:

```cyrius
#ifdef CYRIUS_TARGET_WIN
    # Windows-only code: use lib/args_win.cyr, lib/process_win.cyr, etc.
    include "lib/process.cyr"  # dispatches to process_win.cyr internally
#else
    # POSIX code (Linux / macOS)
    include "lib/process.cyr"  # dispatches to posix process.cyr
#endif
```

The build tool auto-resolves Windows-specific variants from `lib/`:
- `lib/fs_win.cyr` — directory enumeration (replaces getdents64)
- `lib/args_win.cyr` — command-line parsing (GetCommandLineW + CommandLineToArgvW)
- `lib/process_win.cyr` — process creation (CreateProcessW)
- `lib/thread_win.cyr` — preemptive threading (CreateThread + SRWLOCK)
- `lib/sync_windows.cyr` — mutex primitives
- `lib/syscalls_windows.cyr` — kernel32 syscall numbers (0xF0xx reroutes)

Consumer code includes `lib/io.cyr`, `lib/args.cyr`, `lib/process.cyr`, and
`lib/thread.cyr` normally — the dispatcher (the parent module) selects the
platform variant at compile time, so sources stay target-agnostic.

### What Works on Windows PE (v6.1.16–v6.1.18)

**Process Control**
- `run(cmd, arg1, arg2)` — spawn a process and wait for exit → `Result(exit_code)`
- `run_capture(cmd, arg1, arg2, buf, buflen)` — capture stdout/stderr → `Result(bytes)`
- `spawn(cmd, arg1, arg2)` → `Result(handle)` — background process
- `wait_pid(handle)` → `Result(exit_code)` — join spawned process
- `exec_vec(args)`, `exec_capture(args, buf, buflen)`, `exec_env(args, env)` — vec-based forms
- `exec_vec_str(args)`, `exec_capture_str(args, buf, buflen)`, `exec_env_str(args, env)` — Str fat-pointer forms

All reroute to `CreateProcessW` with UTF-16LE command lines. Command arguments
undergo full Unicode quoting via the real Windows `CommandLineToArgvW`, then
convert back to UTF-8 for the cyrius API.

**Threading & Synchronization**
- `thread_create(fp, arg)` → thread handle (CreateThread)
- `thread_join(handle)` → exit code
- `thread_create_detached(fp, arg)` → fire-and-forget; no handle to join or leak (v6.5.8)
- `thread_is_done(handle)` → 1 once the worker has exited. ⚠ Valid only **before**
  `thread_join` — join consumes the handle, and on Windows `CloseHandle()`s it
- `gettid()` → current thread id (GetCurrentThreadId)
- `mutex_new()`, `mutex_lock(m)`, `mutex_unlock(m)` — SRWLOCK (8-byte exclusive lock)
- `chan_new(cap)`, `chan_send(ch, val)`, `chan_recv(ch)`, `chan_try_recv(ch)`,
  `chan_try_send(ch, val)`, `chan_close(ch)` — thread-safe FIFO ring

Mutexes are preemptive-safe (block contending threads). Channel `recv` is
non-blocking (returns 0 when empty); blocking variants require condition
variables, not yet routed.

**Command-Line Arguments & Environment**
- `args_init()` — parse GetCommandLineW via the real CommandLineToArgvW
- `argc()`, `argv(n)` — access parsed arguments (byte-identical to POSIX form)
- Environment variables (`getenv`) read the parent's block on entry

Full Unicode paths are supported; see *Limitations* below.

**File I/O**
- `file_open(path, flags, mode)` → fd
- `file_read(fd, buf, len)` → bytes read
- `file_write(fd, buf, len)` → bytes written
- `file_close(fd)` — handle must be closed
- `file_read_all(path, buf, buflen)` → bytes (wrapper)

Opening files routes to Windows' `CreateFileW`; reading/writing use the real
`ReadFile`/`WriteFile` (via 0xF001/0xF002 PE reroutes and the POSIX syscall
interface dispatching them). Paths are widened from UTF-8 to UTF-16LE at call time.

**Directory Enumeration** (v6.1.18+)
- `dir_list(path)` → `vec` of `Str` filenames
- `is_dir(path)` → 1 (directory) or 0 (not found / file)
- `dir_walk(path, results)` — recursive enumeration (appends file paths to the `results` vec)

These reroute to `FindFirstFileW`, `FindNextFileW`, `FindClose` (0xF016–0xF018),
and `GetFileAttributesW` (0xF019) on Windows. Paths are converted to UTF-16LE
with `/` translated to `\` for Windows naming. Results come back as UTF-8 Str.

### Syscall Routing Model

On Windows, syscalls do not map to a single kernel boundary. Instead, the compiler
dispatches to kernel32 (or shell32) *reroutes* — compiler-emitted sequences that
call imported DLL functions. Each reroute has a PE-internal syscall number
(0xF0xx) that the compiler recognizes:

```cyrius
include "lib/syscalls.cyr"    # imports the reroute constants

var h = syscall(3, handle);           # CloseHandle → syscall(3)
var ec = syscall(60, 0);              # ExitProcess → syscall(60)
var tid = syscall(61451);             # GetCurrentThreadId → 0xF00B
```

The dispatcher (`EPE_SYSCALL_DYNAMIC` in `src/backend/x86/emit.cyr`) interprets
the syscall arity (number of arguments) and compares against a routing table:

- **Arity 4** (read, write, open, seek): if syscall == 0 → read, == 1 → write, == 2 → open, == 8 → seek
- **Arity 3** (mkdir, getticks, nanosleep): if syscall == 83 → mkdir, == 228 → getticks, == 35 → nanosleep
- **Arity 2** (close, unlink, exit): if syscall == 3 → close, == 87 → unlink, == 60 → exit
- **Arity 5** (getdents64, unsupported): returns -38 (-ENOSYS) — directory listing uses the arity-3 `FindFirstFileW` etc. instead
- **Unknown arity**: returns -38

Each routable pair emits the kernel32 call inline. Unknown syscalls return -38
(ENOSYS), matching POSIX semantics, so code paths that are dead on Windows
(e.g., POSIX fork/execve) can compile without routing them.

### Win64 MS-x64 ABI Details

Cyrius PE code follows the Microsoft x86_64 ABI precisely:

- **Calling convention**: Arguments in RCX, RDX, R8, R9; excess on stack
- **Return values**: RAX (64-bit), RDX:RAX (128-bit pair via multi-return)
- **Shadow space**: 32 bytes (0x20) reserved by the caller above RSP
- **Stack alignment**: 16-byte aligned on entry to any function (RSP % 16 == 0 at entry)
- **Registers**: RAX, RCX, RDX, R8, R9, R10, R11 are volatile; RBX, RBP, RSI, RDI, R12–R15 preserved

The cyrius entry point sets up a 0-aligned RSP (the PE loader enters with RSP ≡ 8,
then the entry shim `sub rsp, 8`s to align). Cyrius function prologues and `callptr`
calls maintain this invariant.

### Limitations

**Path Widening (v6.1.16–v6.1.18)**

Paths are ASCII zero-extended to UTF-16LE — characters outside the ASCII range
(0x00–0x7F) are not supported. This is sufficient for the toolchain's own
cross-compile paths (e.g., `C:\cyrius\lib` vs `/usr/local/cyrius/lib`); Unicode
install paths or filenames with non-ASCII characters will silently truncate or
corrupt. This limitation applies to file open, directory listing, and process
creation. A future release can implement full UTF-8 → UTF-16LE transcoding
(surrogate pair handling, etc.).

**UDP Sockets**

`lib/socket.cyr` does not route UDP on PE. TCP is supported via the WinSock2 ABI
(when a consumer demands it); UDP datagram dispatch to the Winsock API is tracked
for a future release.

**COM and Advanced Windows APIs**

Direct COM object access (IDispatch, dual interfaces, type libraries) and DXGI
graphics are not in scope. Cyrius compiles to a portable x64 binary, not a Windows
.NET or UWP app. Advanced Windows features (WMI, registry, services, network
authentication) require hand-coded interop layers or external helper binaries.

The `callptr` builtin (v6.0.70+) enables COM vtable dispatch (`callptr(load64(load64(obj) + slot*8), obj, …)`),
and `callptr` itself is Win64-ABI–correct (16-aligned on entry), so careful
consumers can implement COM wrappers. See the `Function Pointers` section of
this guide.

### Example: Cross-Platform Argument Parsing

```cyrius
include "lib/string.cyr"
include "lib/args.cyr"

fn main() {
    args_init();

    var ac = argc();
    if (ac < 2) {
        println("usage: myprog <arg1> [arg2]");
        syscall(60, 1);
    }

    var arg1 = argv(1);
    var arg2 = 0;
    if (ac >= 3) { arg2 = argv(2); }

    println("arg1:");
    println(arg1);
    if (arg2 != 0) {
        println("arg2:");
        println(arg2);
    }

    return 0;
}
```

Compiling with `cyrius build --win main.cyr main.exe` on Linux produces a
Windows PE that calls `GetCommandLineW` and `CommandLineToArgvW`, parsing the
full Windows quoting rules (`\"`, backslash escaping, etc.) and converting back
to UTF-8 to match the POSIX API exactly. Same binary on Unix calls `/proc/self/cmdline`.

### Example: Directory Listing and File I/O

```cyrius
include "lib/string.cyr"
include "lib/io.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"

fn main() {
    var entries = dir_list(str_from("tests/tcyr"));

    var i = 0;
    while (i < vec_len(entries)) {
        var name: Str = vec_get(entries, i);
        var is_directory = is_dir(name);

        if (is_directory == 1) {
            print_str("DIR:  ");
        } else {
            print_str("FILE: ");
        }
        println(str_data(name));

        i = i + 1;
    }

    return 0;
}

fn print_str(s) {
    syscall(1, 1, s, strlen(s));
}
```

On Windows PE, `dir_list("tests\\tcyr")` internally converts the path to
UTF-16LE, calls `FindFirstFileW` and `FindNextFileW`, and returns UTF-8 Str
entries. On Linux, it calls `getdents64`. The consumer code is identical.

## Targeting AGNOS (ring-3 userspace) (v6.0.48)

AGNOS is a ring-3 operating system kernel designed for secure, minimal userspace
execution. Cyrius can cross-compile to AGNOS from any host (Linux, macOS, Windows),
producing x86_64 ELF64 binaries that run as agnos ring-3 processes. Unlike hosted targets
(Linux, macOS, Windows), agnos uses a distinct syscall ABI, explicit-length path arguments
(no NUL-termination), and agnos-native open flags; the `#ifdef CYRIUS_TARGET_AGNOS`
preprocessor guard exposes port-specific code paths in `lib/`.

### Building for AGNOS

```sh
# Cross-compile to agnos from any host
cyrius build --agnos src/main.cyr build/myapp

# Equivalent: set the environment variable directly
CYRIUS_TARGET_AGNOS=1 cycc < ...
```

The `--agnos` flag sets the `CYRIUS_TARGET_AGNOS` predefine, which gates the
compiler's emit codegen: the program-exit epilogue emits `syscall(0)` (agnos `exit`,
code in `rdi`), not Linux `syscall(60)`. The binary is a valid x86_64 ELF64 at entry
`≥ 0x200000` (agnos user-range floor).

### AGNOS Syscall ABI

agnos defines an append-only syscall surface: **#0–#95 contiguous, plus #97**, at agnos
1.56.x (`lib/syscalls_x86_64_agnos.cyr`). Beyond the GPU-compute band #82–#91 it now carries
`gpu_shader_op` (#92), `gpu_modeset_op` (#93), `gpu_recover_op` (#94), `uptime_us` (#95) and
the local-IPC **channel band** `chan_op` (#97, minted at v6.5.8). ⚠ **#96 (`fork`) is
reserved but deliberately NOT minted** — on agnos an unknown number falls *through* the
dispatch chain and the caller reads the fall-through value as data, so a
minted-but-unimplemented constant is strictly worse than an absent one. The register
convention is x86_64 SysV (rax=number, rdi/rsi/rdx/r10=args 1–4, rax returns
result ≥0 on success, -1 on error). Key differences from Linux:

```
# agnos syscall numbers — append-only, #0–#95 + #97 (lib/syscalls_x86_64_agnos.cyr)
SYS_EXIT = 0       (not Linux 60)
SYS_WRITE = 1
SYS_READ = 5
SYS_OPEN = 7
SYS_SPAWN = 3      (spawn in-memory ELF; no fork/exec)
SYS_WAITPID = 4    (returns exit_code directly, not wait-status)
SYS_MMAP = 27      (anonymous, 2 MB-granular, no hint support)
```

**Explicit lengths, no NUL assumption**: every path argument carries its length.
`sys_open(name, namelen, flags)` — length is required, not derived from NUL.

**agnos-native open flags** (`AO_*`, NOT Linux `O_*`):
```
AO_RDONLY = 0x0
AO_WRONLY = 0x1
AO_RDWR = 0x2
AO_CREAT = 0x100
AO_TRUNC = 0x200
AO_APPEND = 0x400
AO_DIRECTORY = 0x800
```

**4-argument convention** (for `rename`, `link`): argument 4 rides in r10 (not on
the stack), following the FASTCALL variant of the SysV ABI. The compiler handles
this automatically for `syscall(SYS_RENAME, a1, a2, a3, a4)`.

**Return values**: ≥ 0 = success, -1 = error. agnos does NOT return -errno; instead,
syscalls either fail with -1 or succeed. The `is_err(ret)` function checks this:
```
fn is_err(ret) { return ret < 0; }
```

### Ported Libraries

Cyrius provides agnos-specific peers for core libraries, selected via
`#ifdef CYRIUS_TARGET_AGNOS` in the dispatch files:

```
lib/syscalls.cyr          → lib/syscalls_x86_64_agnos.cyr
lib/alloc.cyr             → lib/alloc_agnos.cyr
lib/args.cyr              → lib/args_agnos.cyr
lib/process.cyr           → lib/process_agnos.cyr
lib/io.cyr (getenv)       → delegates to lib/args_agnos.cyr::_agnos_getenv
```

**`lib/syscalls_x86_64_agnos.cyr`**: the full agnos syscall surface (#0–#95 + #97),
with wrappers (`sys_write`, `sys_read`, `sys_open`, `sys_spawn`, `sys_waitpid`,
`sys_mmap`, `sys_stat`, the socket/UDP/ICMP networking band, framebuffer/blit/keyboard,
the GPU-compute band `sys_gpu_dispatch`..`sys_gpu_blit_bb` (#82–#91), the
`sys_gpu_shader_op` / `sys_gpu_modeset_op` / `sys_gpu_recover_op` / `sys_uptime_us`
tail (#92–#95), and the `sys_chan_*` channel band over #97) and the
agnos `stat` / `getdents` record layouts. ⚠ The **agnos kernel dispatch**
(`agnos/kernel/core/syscall.cyr`) is the single canonical source for every number and
signature — `agnos-userland-abi.md` is a secondary reference, and where the two disagree
the kernel wins.

**`lib/alloc_agnos.cyr`**: bump allocator over agnos's `sys_mmap(27)` chunks
(2 MB-granular, kernel-picked base, no hints). Successive mmaps are discontiguous;
agnos reclaims all at process exit (no individual free). Mirrors the `alloc_*`
API: `alloc_init`, `alloc(size)`, `alloc_reset`, `alloc_used`.

**`lib/args_agnos.cyr`**: command-line argument + environment access via the
agnos ring-3 init stack (ABI §4.6). The kernel stages `[rsp]=argc`, argv pointers,
a NULL, envp, AT_NULL-only auxv. The cycc entry captures the init-rsp, so `argc()`,
`argv(n)`, and `getenv(name)` read the cached rsp.

**`lib/process_agnos.cyr`**: process spawn and wait. agnos has no fork/exec; instead,
`sys_spawn(elf_addr, elf_size)` runs an in-memory ELF image (you must read the file
into heap first). The wrappers are `run(cmd)`, `spawn(cmd)`, `wait_pid(pid)`, and
variants like `exec_vec(args)`, `exec_capture` (capture is a stub — output goes to
terminal). **Limitation**: `sys_spawn` takes no argv/envp, so spawned programs
receive only their own name; arguments cannot be passed.

### Conditional Compilation Pattern

Guard agnos-specific or agnos-incompatible code with the preprocessor:

```
include "lib/syscalls.cyr"
include "lib/args.cyr"

fn main() {
    #ifdef CYRIUS_TARGET_AGNOS
        # agnos: explicit-length paths, AO_* flags
        var fd = sys_open("/tmp/file", 10, AO_CREAT | AO_WRONLY);
    #else
        # Linux/macOS: NUL-terminated, O_* flags
        var fd = sys_open("/tmp/file", 0, O_CREAT | O_WRONLY);
    #endif
    
    if (is_err(fd)) { return 1; }
    sys_write(fd, "hello\n", 6);
    sys_close(fd);
    return 0;
}
```

Portable patterns to support all targets: use the dispatch files (`lib/syscalls.cyr`,
`lib/alloc.cyr`, `lib/args.cyr`, `lib/process.cyr`), which handle the `#ifdef`
branching internally. Avoid platform-specific syscall numbers, flags, or struct layouts.

### Capabilities and Limitations

**Works on agnos**:
- Syscall wrappers (all of #0–#95, plus #97)
- Heap allocation (bump, 2 MB chunks)
- File I/O (read, write, open, close, stat, getdents/readdir)
- Process spawn and wait (in-memory ELF, or from disk via `sys_spawn_path`)
- Arguments and environment variables
- **Passing an environment to a spawned child** — `sys_spawn_path_env(path, len, env, envlen)`
  (v6.5.9). The blob is packed `KEY=VALUE\0…`, ≤1024 B, ≤16 entries. ⛔ The kernel treats a
  garbage `a3`/`a4` as *fallback to the default env*, **never an error**, so a mis-shaped call
  degrades silently — which is why the named wrapper exists rather than a raw 4-arg `syscall()`.
- **Local-IPC channels** — the `sys_chan_*` band over #97 (`caps` / `mint` / `send` / `recv` /
  `close` / `endow`). A channel is minted as a **pair** and has no name, which deletes the
  unlink-before-bind race class AF_UNIX carries. ⛔ Negotiate on the CAPS mask, do not assume:
  one bit per *implemented* op, and a merely-reserved op reads 0. ⚠ `sys_chan_endow` returns an
  **fd, not 0** — the one op in the band that does; the parent passes it to the child as
  `AGNOS_CHAN=<fd>` in the `sys_spawn_path_env` blob. ⚠ The `sys_chan_` prefix is deliberate:
  bare `chan_send`/`chan_recv`/`chan_close` are already the in-process MPSC thread channel, and
  cyrius resolves duplicate fns last-definition-wins.
- Pipes, epoll, signalfd, timerfd (the event loop primitives)
- Signals (sigprocmask, kill, pause)
- Filesystem (mkdir, rmdir, unlink, rename, link on ext2)
- Networking (sockets, UDP, ICMP; #47–#61)
- Framebuffer, blit, keyboard (#38–#42), the GPU-compute band (`sys_gpu_dispatch`..`sys_gpu_blit_bb`, #82–#91) and the #92–#95 tail
- SIMD, function pointers, inline asm (same as Linux/macOS)

**Does NOT work on agnos** (either absent from the surface or stubbed):
- Process **arguments** to spawned programs (`sys_spawn` is elf_addr, elf_size only; the
  from-disk `sys_spawn_path` takes a path and, since v6.5.9, an env blob — but still no argv)
- stdout/stderr redirection (`sys_dup` is a stub returning `fd` unchanged; pipe → spawn → wait
  works, but output goes to the terminal, not a buffer; `run_capture` returns 0 bytes)
- `getppid` (no getppid in the surface; returns 0)
- `getuid` (always 0 / root)
- `chmod` (no permission model; `sys_chmod` is a no-op stub returning 0)
- Thread-local storage (not modeled in agnos ring-3)
- Dynamic linking (`dlopen`, auxv machinery), only static binaries

The agnos syscall surface is **append-only, currently #0–#95 + #97 at agnos 1.56.x**. The
re-freeze rule (§5) names the agnos **kernel dispatch** — `agnos/kernel/core/syscall.cyr` —
as canonical: any number / signature / struct-layout change there must land in this guide and
`lib/syscalls_x86_64_agnos.cyr` in the same change. `agnos/docs/development/agnos-userland-abi.md`
is a *secondary* reference and where it disagrees with the kernel, the doc is the bug. (Until
v6.5.7 the peer's header named that doc as its authority while the doc named the peer as part
of *its* authority — a doc → cyrius → doc circle in which a wrong number could be "verified"
against itself. The kernel was always the tiebreak.) Follow-up arcs are tracked in
`docs/development/issues/`; the spawn-argv gap's original filing
("2026-06-03-agnos-followup-after-boot.md") has since moved to `issues/archived/`.

## Position-Independent Executables (PIE) (v6.1.6)

A position-independent executable (PIE) uses RIP-relative code and relocatable
base addresses, allowing the kernel to load it at a random address under ASLR
(Address Space Layout Randomization). Cyrius supports PIE on both x86_64 (v6.1.6)
and aarch64 (v6.1.8), producing ET_DYN binaries with `p_vaddr=0` and
base-relative entry points. The full tcyr test corpus runs correctly as
ASLR-loaded PIE binaries on both architectures.

Enable PIE via the `--pie` flag or `CYRIUS_PIE=1` environment variable:

```sh
cyrius build --pie src/main.cyr build/myapp       # x86_64 or aarch64
# or
CYRIUS_PIE=1 cyrius build src/main.cyr build/myapp
```

Non-PIE output is **byte-identical** across all corpus inputs — the feature
is fully opt-in and inert when disabled (v6.1.5 vs v6.1.6 differential = zero
drift across 338 corpus programs).

### Architecture & Code Generation

On **x86_64**, PIE uses `lea [rip+disp32]` for address calculations and rel32
call-site fixups. The machinery reuses ~80% of the proven shared-object codegen
path (`_IS_OBJ` in `src/backend/x86/emit.cyr`); only the ELF wrapper differs
(ET_DYN + p_vaddr=0 instead of ET_EXEC). The resulting `.text` has **zero
absolute `movabs`** instructions — all globals, strings, function pointers, and
function calls resolve via RIP-relative offsets that adjust correctly at each ASLR load.

On **aarch64**, PIE emits `adrp`+`add` pairs (2 instructions) instead of the
3-instruction `movz`/`movk` absolute chain. The machinery is inherited from the
byte-proven Mach-O PC-relative code (`FIXUP_ADRP_ADD` and `FIXUP_ADRP_LDR`),
but the base computation is generalized: where Mach-O hardcoded `0x100004000`,
ELF PIE uses `_entry_base(S)` (the load-bias-relative instruction VA), making
the page-aligned base cancel in the adrp page-diff. The result is load-bias
correct and ASLR-safe on every load.

### Capabilities & Patterns

PIE binaries safely handle:
- Global variable access and address-taken globals (`&var`)
- Function pointers, callbacks, and indirect dispatch (`fncallN`)
- Interface/trait method dispatch via vtables stored in globals
- Address-valued global initializers (`var gp = &foo;`)
- Static string literals and global arrays

Example:

```cyrius
var global_int = 42;
var global_ptr = 0: i64;   # Will be filled with &fn_target

fn fn_target() { return 1; }

fn main() {
    global_ptr = &fn_target;
    var x = global_int;    # &var under ASLR load: RIP-relative
    var r = fnc alloc(global_ptr);   # Indirect call at randomized base
    return x;              # 42 — correct under any ASLR offset
}
```

### Relationship to `shared` & Object Mode

PIE reuses the `_IS_OBJ` codegen gate, which gates both shared-object emission
(`kmode==2`) and PIE (`_pie_mode`). The distinction is:
- **Object mode** (`shared;`): emits relocatable `.o` files with external symbol refs, processed by `ld` or `ld.lld`
- **PIE mode** (`--pie`): emits standalone ET_DYN executables that fix up all relocations internally

For `.so` emission, v6.1.9 additionally migrates from SysV `.hash` to `.gnu.hash`
(the loader's O(1) Bloom-filter path), improving symbol resolution speed in
dlopen'd libraries.

### Kernel PIE (v6.1.7)

The `kernel; --pie` form produces an ET_DYN kernel with RIP-relative `.text`
and base-relative `e_entry` (`0xA8`), allowing a KASLR boot loader (AGNOS
gnoboot) to slide the kernel to a random address. The kernel-PIE ELF wrapper
is structurally validated (ET_DYN header, zero absolute `movabs`, RIP-relative
code); non-PIE kernels remain **byte-identical to v6.1.6**. Live boot at a slid
base awaits an AGNOS `--pie` harness (AGNOS is not yet pulling on it).

### Limitations & Non-Support

- PIE is userland-first (x86_64 v6.1.6, aarch64 v6.1.8)
- Kernel-PIE is structurally complete but awaits AGNOS boot harness integration
- Position-independent shared libraries (`.so` with `-fPIE`) are not a separate target;
  `shared;` emits relocatable object files only
- Non-PIE output is always available and carries no performance cost

## TypeScript / TSX → JavaScript (`cycc --emit-js`)

The `--emit-js` flag (v6.1.11+) emits browser-runnable JavaScript from TypeScript
and TSX source, stripping types and lowering JSX to hyperscript calls. Single-file
emission; no bundler. Run directly via `cycc --emit-js <file.tsx>` or surface
through the CLI: `cyrius build --target=js <in.tsx> <out.js>`.

```sh
# Direct invocation
cycc --emit-js app.tsx                  # JS → stdout

# Via the build CLI
cyrius build --target=js app.tsx app.js # x86-Linux-only
```

### Type Stripping

The emitter walks the parsed AST and removes all TypeScript syntax:

```typescript
// Input TypeScript
interface Config { host: string; port: number; }
type Handler<T> = (x: T) => T;

function process(c: Config, f: Handler<number>): number {
    const x: number = c.port;
    const y = f(x as any);
    const z: string = y!.toString();
    return z.length;
}
```

```javascript
// Emitted JavaScript
function process(c, f) {
    const x = c.port;
    const y = f(x);
    const z = y.toString();
    return z.length;
}
```

Strips: interfaces, type aliases, parameter/return/binding type annotations, `as T`
type casts, `x!` non-null assertions, generic type arguments (`<T, U>`), and optional
`?` markers.

### JSX Lowering

JSX syntax is lowered to hyperscript pragma calls. The pragma defaults to `h`
and is configurable via the `CYRIUS_JSX_PRAGMA` environment variable.

```typescript
// Input TSX
function NoteRow({ id, body }: Note): JSX.Element {
    return (
        <li className="note" data-id={id}>
            <span>{body}</span>
        </li>
    );
}
```

```javascript
// Emitted JavaScript (default pragma `h`)
function NoteRow({ id, body }) {
    return h("li", { className: "note", "data-id": id }, h("span", null, body));
}
```

Tag lowering: uppercase names become component identifiers (`<MyComp />`
→ `MyComp(...)`); lowercase names become quoted HTML strings (`<div />` →
`"div"`). Attributes become object keys — valid JS identifiers bare, others
quoted (`className` bare, `data-id` quoted). `{expr}` values inlined, spreads
(`{...obj}`) passed through. `{expr}` children inlined; whitespace-only JSX
text dropped. Self-closing handled.

### Standalone Hyperscript Runtime

When JSX is present and using the default `h` pragma, the emitter prepends
a ~12-line standalone `h` function so the output runs in a browser with zero
dependencies. A custom `CYRIUS_JSX_PRAGMA` suppresses the prelude (consumer
brings the runtime):

```javascript
function h(t, p, ...c) {
  if (typeof t === "function") return t(Object.assign({}, p, { children: c }));
  const e = document.createElement(t);
  for (const k in (p || {})) {
    const v = p[k];
    if (k === "className") e.className = v;
    else if (k.slice(0, 2) === "on" && typeof v === "function") e.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k in e) e[k] = v;
    else if (v != null && v !== false) e.setAttribute(k, v);
  }
  const add = (x) => { if (x == null || x === false || x === true) return; if (Array.isArray(x)) x.forEach(add); else e.append(x.nodeType ? x : String(x)); };
  c.forEach(add);
  return e;
}
```

Custom pragma (e.g., `React.createElement`):

```sh
CYRIUS_JSX_PRAGMA=React.createElement cycc --emit-js app.tsx
# Prelude is suppressed; consumer imports React
```

### ESM Import/Export Pass-Through

Named imports and exports pass through verbatim; type-only names are pruned:

```typescript
// Input
interface Note { id: number; }
export { Note, renderNote, printNote };
import type { Config } from "./config";
import { setup } from "./util";
```

```javascript
// Emitted (Note filtered, import type dropped)
export { renderNote, printNote };
import { setup } from "./util";
```

`export type` declarations and `import type` statements are dropped entirely
since they have no runtime meaning.

### String / Template Literals

String literals (single/double/backtick), number literals, and regex are
re-emitted verbatim. Template literals preserve interpolations:

```typescript
const msg = `Hello, ${name}!`;
const pattern = /foo(bar|baz)/g;
```

```javascript
const msg = `Hello, ${name}!`;
const pattern = /foo(bar|baz)/g;
```

Template literal `${}` expressions are recursively emitted, preserving nesting.

### Indented Output

(v6.1.12+) Structural indentation (2 spaces per level) is applied to block
bodies (class, function, switch, control flow). Indentation is applied only
at structural newlines, never inside verbatim strings or template content,
so template literals carrying their own newlines are never re-indented:

```javascript
function outer() {
  const parts = [1, 2, 3];
  for (const x of parts) {
    console.log(x);
  }
  switch (mode) {
    case 1:
      return `multiline
template
unchanged`;
    default:
      return null;
  }
}
```

### Validation

The emitter keeps a walk-verification gate from v6.1.10: it exits non-zero
if any node is reached twice (indicating a corrupted AST) or a list entry
is out of range. The output is tested to round-trip through `node --check`
(syntax validation) and a re-parse via `--parse-ts` (semantic consistency).

### Platform & Build Support

`cycc --emit-js` and `cyrius build --target=js` are **x86-Linux-only**
(the TS frontend is not compiled for aarch64, Windows PE, or macOS). The
standalone `cycc_aarch64` and `cycc_win` cross-compilers do not include
the TS frontend.

### Limitations

- Single-file emission; no module bundling or tree-shaking
- No JSX component props typing validation (TS type-checking is lost)
- The TS parser is self-hosted (only in the `cycc` x86 binary)
- No source maps

## Example Programs

See `programs/` for 97 examples:
- **CLI tools**: cat, echo, head, wc, grep, hexdump, tail, tr, uniq, sort, basename, cols, count, toupper, rot13, rev, nl, seq, tee, yes, true, false
- **Algorithms**: fizzbuzz, primes, sieve, collatz, ackermann, gcd, brainfuck, life, xor
- **Data structures**: struct_list (linked list), alloctest (heap), strtype (fat strings)
- **Systems**: bitfield (PTE/GDT/IDT), asmtest (18 mnemonics), points (nested structs + typed ptrs)
- **Kernel**: kernel_hello (VGA), isr_stub (interrupt patterns), boot_serial (the `kernel;`
  program `scripts/qemu-boot-gate.sh` really boots under QEMU)

The AGNOS kernel itself is **not** in this repo — it lives in the separate `agnos` repo and
is built with this toolchain.

## Architecture

```
bootstrap/asm (29KB seed)
  → cybs (~12 KB bootstrap compiler)
    → cycc (modular compiler + IR)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win    (Windows PE32+ cross-compiler)
      → cycc_cx     (cyrius-x bytecode; run by programs/cxvm.cyr)
      → the AGNOS kernel (separate `agnos` repo)
```

Current cycc size, IR pipeline state, and cross-compiler stats live in
[`docs/development/state.md`](../development/state.md). Per-release narrative
is in [`docs/development/completed-phases.md`](../development/completed-phases.md).
