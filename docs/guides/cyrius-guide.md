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
(`3.14`) is lexed as an `f64` float, and its value is the **correctly rounded** binary64 of
the digits as written (round-half-even, any number of digits, subnormals, +inf past
~1.8e308) — the compiler converts it exactly and emits the bits as one immediate. There is
no exponent form (`1e-9`): spell small constants out (`0.000000001`). Until 6.6.10 a literal
with more than 18 fraction digits or a digit string ≥ 2^63 was silent garbage (often
negative), and 16–18 digit literals were 1 ulp off on some values.

An integer literal must fit in 64 bits: anything ≥ 2^64 — decimal, hex or octal — is a
compile error (`integer literal does not fit in 64 bits`; until 6.6.10 it wrapped silently).
2^63 … 2^64 − 1 is accepted and reads as the negative i64 with those bits
(`0xFFFFFFFFFFFFFFFF` is -1).

Unary minus flips the **sign bit** of a float the compiler can see is a float: a float
literal, a value typed `f64` / `f32`, or the result of a float-returning builtin — directly
or in parentheses (`-f64_sqrt(v)`, `-(f64_exp(v))`, `-f32_from(v)`, …). So `-1.5` is -1.5,
`-0.0` is negative zero and `-x` negates an `f64` exactly (6.6.8; before it, `-1.0`
evaluated to -4.0 and `-0.0` to +0, silently; the parenthesised builtin form was integer
negation until 6.6.10). A struct or union field declared `f64` / `f32` counts as typed too
(6.6.10 — see [Field types](#field-types-v6610)), and since 6.6.11 so does a `var` with no
annotation that is a pure **copy** of a declared float: `var t = p.y;` (an `f64` field, or a
chain `o.i.x`), `var u = y;` (an `f64` / `f32` local or parameter) and `var g = G;` (a typed
global) type `t`, `u` and `g` the same way, so `t + t` is a float add and `-t` a float
negation. Before 6.6.11 the copy stayed `i64` and `t + t` added the bit patterns. Only a
bare name or a field chain counts — the same rule as `var x = f();` with `fn f(): f64`
(v6.5.21), which types `x` from the declared return. It does NOT cover an **untyped**
variable, an untyped field holding float bits, or an untyped expression (`-(a + b)` over
untyped vars, `var z = 0.0;`, `var t = p.y * 2.0;`) — those are `i64` as far as the compiler
knows, and `-v` is integer negation of the bits. Negate them with `f64_neg(v)`, or declare
the variable `: f64`. Since 6.6.10 an untyped variable initialised from a float (`var c = 1.5;`,
`var z = 0.0;`, `var x = f64_sqrt(u);`, or a copy of such a variable) WARNS when negated:
`unary minus on an untyped variable holding a float is integer negation (declare it f64)`.
`-c` of 1.5 is -3.0, `-z` of 0.0 is +0 and `-n` of -2.5 is 1.75. Since 6.6.11 every plain
assignment re-judges it: `var g = 0; g = 1.5; -g` warns and `var h = 1.5; h = 7; -h` does not
(a compound assignment such as `h += 1` leaves the judgement as it was). The judgement is not
flow-sensitive: it is whatever the last assignment the compiler READ said — source order
inside a fn, and for a global, source order across fns — not what happens to run last.

**Float builtin results in arithmetic (6.6.10).** The result of a float-returning builtin
(`f64_sqrt`, `f64_add`, `f64_sin`, `f64_exp`, `f32_from`, … — every `f64_*` / `f32_*` that
returns a float) is a float operand of `+ - * /`, on either side, directly, in parentheses
or after unary minus: `f64_sqrt(u) * 2.0`, `f64_sin(z) - f64_cos(z)`, `2.0 * f64_sqrt(u)`,
`f64_mul(u, v) / v` and `-f64_sqrt(u) * 2.0` are all float arithmetic now, whatever the
builtin's arguments were typed. Until 6.6.10 they were INTEGER operations over the bit
patterns — `f64_sqrt(u) * f64_sqrt(u)` was 0 and `f64_sin(0) - f64_cos(0)` -4.0 — and the
answer depended on the ORDER of the arguments (`f64_add(p, u)` took the last argument's
type). The result is still not a typed *value*: `==`, `!=`, `<` … on builtin results remain
INTEGER compares of the bit patterns (so `f64_neg(z) == z` is 0 for z = 0.0, and
`f64_neg(a) < f64_neg(b)` is wrong for negative values — compare with `f64_lt` /
`f64_gt` / `f64_eq` / `f64_le` / `f64_ge`), and `var x = f64_sqrt(u);` declares an untyped
`x` (declare it `: f64` to make later arithmetic on it float). Code that wants the integer
ulp distance of two results goes through an untyped variable first:
`var a = f64_atan(x); d = a - b;`.

An integer CONSTANT stored into an `f64` / `f32` slot keeps its integer bits — `var t: f64 =
1;`, `t = 1;`, `p.x = 1;` (an `f64` field) and `P { 1, 2 }` store `0x1`, a subnormal — and
since 6.6.10 each WARNS: `an integer stored into an f64/f32 slot keeps its integer bits`.
Write `1.0`, or `f64_from(n)` for a runtime integer. `0` is exempt (its bits are 0.0), and
so is a hex bit pattern at or above 2^52 (`0x3FF0000000000000` is 1.0 on purpose); a runtime
untyped value (`var x: f64 = load64(p);`) is the legal boxed-float idiom and is not judged.

⚠ Binary operators are typed by their LEFT operand. `0 - 1.5` is an INTEGER subtraction
of 1.5's bit pattern (it is -3.0), and `2 * x` with `x: f64` multiplies x's bits. Write
the left operand as a float — `0.0 - x`, `2.0 * x`, or just `-x`. Both directions warn:
an f64 left with a non-f64 right (`f64 arithmetic with a non-f64 right operand`) and,
since 6.6.8, an integer left with an f64 right (`integer arithmetic with an f64 right
operand`). An **f32** left takes the LOW 32 BITS of its right operand, so an `f64` literal
or an integer there is reinterpreted, not converted — with `x: f32`, `x * 2.0` is 0 and
`x + 1.0` is `x`. Since 6.6.11 it warns too (`f32 arithmetic with a non-f32 right operand`);
write `x * f32_from(2.0)`. They are warnings, not errors (ADR-002: the untyped `i64`-boxed
float idiom stays legal); `CYRIUS_TYPE_CHECK=0` silences them.

**Compound assignment on a float (6.6.11).** `x += y`, `-=`, `*=` and `/=` on an `f64` /
`f32` variable are float operations — for a local, a **global**, a top-level statement and a
`for` step alike — and the right operand is checked exactly as in `x = x + y` (`t += 1` on
an `f64` warns: 1's bits are a subnormal, write `t += 1.0`). Until 6.6.11 only a local got
the float arithmetic: `G += 1.0` on an `f64` global added the two bit patterns as integers,
and `for (var x: f64 = 0.0; x < 1.0; x += 0.25)` ran twice instead of four times, silently.
`%=`, `&=`, `|=`, `^=`, `<<=` and `>>=` are integer operations on any variable. A `for`
step accepts all ten compound operators (it used to accept five).

## Variables

```
var x = 10;            # Global or local (context-dependent)
var buf[256];          # Bare array — see byte-vs-slot note below
var slots: i64[256];   # Element-typed array — 256 i64 SLOTS (2048 bytes), anywhere
slots[3] = 7;          # Subscript (element-typed arrays only, since 6.6.12)
x = x + 1;             # Reassignment
```

### Type names (6.6.16)

Every place that names a type — a `var` annotation (local or global), `*T`, `[T]` /
`slice<T>`, a parameter, a return type, a multi-value return element, a struct field, an
array element, `sizeof(T)` and `#assert sizeof(T)` — reads it from one vocabulary, and
matches the **whole** name:

| Name | `sizeof` | Notes |
|------|----------|-------|
| `i8` `i16` `i32` `i64` | 1 / 2 / 4 / 8 | |
| `u8` `u16` `u32` `u64` | 1 / 2 / 4 / 8 | |
| `u128` | 16 | |
| `f32` / `f64` | 4 / 8 | |
| `bool`, `cstring`, `Result`, `Option`, `Tagged`, an enum | 8 | an enum may be declared on either side |
| `Vec` / `Vec<T>` | 8 | a `vec_new()` handle, as a struct field has always taken it |
| a vector type (`f64v2` … `u64v2`, `f64v4`, `f32v8`) | 16 / 32 | |
| a struct or union (`Pt`) | its size | a struct **named** like a scalar (`u8pair`) is the struct |
| a type parameter in scope (`T`) | its argument's size | the `i64` base: 8 |

`var a: T[N]` reserves exactly `N * sizeof(T)`. Inside a generic fn's instance a type
parameter IS its argument: in `g<f64>`, `var y: T` and a parameter `x: T` are `f64`s (their `+`
is a float add; the parameter still arrives in an integer register, as a non-generic `x: f64`
does) and `var a: T[N]` holds `f64`s; in `g<i8>`, `var y: T` sign-extends like any `i8`. (Before
6.6.16 `T = f64` made a 9-byte untyped word and `T = i8` / `i16` / `i32` loaded
zero-extended; before 6.6.17 an instance INLINED at a call inside a fn — a one-statement
body such as `return sizeof(T);` or a generic forwarding its `T` — still ran as the `i64` base,
and a parameter `x: T` at `f64` was an untyped word, as was any inlined `x: f64`.)

A name that is not a type is a compile error that names it — `unknown type 'Nope' for
variable 'a'`, `... for parameter 'x'`, `... as a fn return type`, `... in sizeof` — and a
name that only *starts* like one gets a hint (`'i8x' is not 'i8' - a type name must match
whole`). A type with no place at a site is refused once, its `<..>` with it
(`fn f(): Vec<i64>` is one error). Before 6.6.16 most sites matched a prefix
(`var a: i8x = 300` was an `i8` and read 44, `var p: u8pair;` was a `u8`)
and read any other name as a silent `i64`; `sizeof(f64)`, `sizeof(u8)` and `sizeof(bool)`
did not compile. A parameter still takes `Str`, `cstring`, `Result`, `Option` and `Tagged`
by name, without their `include`. A return type is a struct, `i8`..`i64`, `f64`, a vector
type, `Result`, `Option`, `Tagged`, `cstring` or a pointer `*T` (6.6.17) — `fn f(): u8` is
refused by name (return an `i64`). `cyrius lint` (`--syntax-only`) resolves no type names, so it never reports these.

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
| `var a: f64[N]`   | `N * 8`             | doubles (`f64_*` bit patterns) |
| `var a: f32[N]`   | `N * 4`             | **packed** singles — stride 4 (`store32(&a + i*4, …)`), the layout `f32v4` lanes and interop buffers use |
| `var a: Pt[N]`    | `N * sizeof(Pt)`    | a struct, union or generic instance (`Box<Pt>[N]`) |
| `var a: *T[N]`    | `N * 8`             | pointers (whatever `T` is)    |
| `var a: f64v2[N]` | `N * 16` / `N * 32` | any vector type: 16 for the 128-bit ones (`i8v16` … `u64v2`, `f64v2`, `f32v4`), 32 for `f64v4` / `f32v8` |
| `var a: bool[N]`  | `N * 8`             | `bool`, `cstring` and an enum name are 8 bytes each |

Every element type sizes `N * sizeof(T)` in a function, in the leading
declaration block and after the first top-level statement alike (since
6.6.13 — before it, every element that is not an integer was sized like a
bare `var a[N]`: a local `var a: f64[4]` or `var a: Pt[2]` held **8 bytes**,
a top-level `Pt[2]` 16 of its 32, and a write inside the declared bounds ran
over the next variable, silently). A struct element's stride is
`sizeof(T)`, which is **unpadded**: `struct G { d: f64; c: i8; }` is 9 bytes,
so `G[3]` is 27 (rounded up to 32) and its elements are not 8-aligned. An
`f32` array element is 4 bytes while an `f32` struct FIELD (and an `f32`
scalar) still occupies 8.

An element type that names nothing is refused by name — `unknown array
element type 'Nope'` — and so is a struct or union used as the element of a
top-level array declared **above** it (`array element type 'P3' is declared
after the array`; it was silently 8 bytes per element). An enum may be
declared on either side (its values are i64). The element is the type
the WHOLE name spells: `struct u8pair { a; b; }` is a 16-byte struct, so
`u8pair[2]` is 32 bytes and refuses `a[i]` (before 6.6.13 its name's `u8`
prefix made it a 1-byte element), and `i8x`, which names nothing, is
refused rather than read as an `i8`. Inside a generic fn,
`var a: T[N]` is sized by the type argument (`T = P3` gives `N * 24`; the
`i64` base gives `N * 8`). `N * sizeof(T)` over 2 GiB is refused
(`array too large`) rather than wrapped to a small size.

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

`N` is an integer literal or an **enum constant**, bare or qualified —
`enum Sz { BUF = 16; }` then `var b[BUF]`, `var b[Sz.BUF]` or
`var a: i64[Sz.BUF]`, in a function or at top level (the qualified form
since 6.6.10). A plain `var` is not a constant and is refused as a size, as is
a negative enum value. The qualifier must be the constant's OWN enum (since
6.6.11, here and in every expression): `Foo.BUF` with no enum `Foo` is refused
with `'Foo' is not an enum`, and `Other.BUF` with `'BUF' is not a variant of
'Other'` — before 6.6.11 the qualifier was ignored. When two enums share a
variant name, `A.X` and `B.X` each read their own enum's value (the bare `X`
keeps "last definition wins", with its warning).

### Array initializers: `var a: T[N] = { .. }` (6.6.16)

At module scope an array takes a list of constants — **N elements of T**,
written into the program image:

```
enum Op { ADD = 1; SUB = 2; }
var table: u16[4] = {0xFFFF, Op.SUB, 1 << 8, -1};  # 0xFFFF, 2, 256, 0xFFFF
var scale: f64[2] = {1.5, -0.25};
var wide: u128[1] = {0xFF};                        # the low 8 bytes; the high 8 are 0
var utf16[1] = {0x67, 0x00, 0x6E, 0x00};           # the bare form: a BYTE list
```

- An element is an integer literal, an enum constant (`A` or `E.A`, the enum
  declared on either side), or a constant expression of them (`1 << 4`,
  `E.A * 2`, `-5`). An `f64` / `f32` element also takes a float literal,
  optionally negated; an `f32` element is the literal rounded to the nearest
  `f32`, ties to even — what `f32_from` gives. An integer in a float element
  keeps its bits, with the warning `var g: f64 = 2;` gives.
- A value must fit its element: an `N`-byte integer element takes
  `-2^(8N-1) .. 2^(8N)-1`, so `0xFF` in an `i8` and `-1` in a `u8` are the same
  bits, while `256` in an `i8` is refused (`array initializer value 256 does not
  fit a 1-byte element (-128 .. 255)`). `i64`, `u64`, `bool`, an enum and `*T`
  take any 64-bit value. The bare `var b[N] = { .. }` stays a list of **bytes**
  in `[0, 255]`, at most `N * 8` of them, and now takes enum constants and
  constant expressions too.
- Elements past the list are 0. More elements than `N` is refused, naming `N`.
- A struct, union, vector, slice, `cstring`, `Str` (a struct), `Result`,
  `Option`, `Tagged` or `Vec` element type is refused by name — store the
  elements explicitly. A call, a variable or a string is not a constant and is
  refused.
- The values are **in the image**: no code stores them at startup, so they hold
  from the first instruction — in a `kernel;` build too, and on cx (in the
  `.cyx`'s var data). An initializer that runs earlier, even one that reads the
  array before its declaration, sees the list.
- The same declaration after the first top-level statement means the same
  thing. Inside a top-level block (`while`, `if` / `elif` / `else`, `for` and
  its init clause, a `switch` case or `default` arm, `match`, `@unsafe`, a bare
  `{ }`) a list is refused: it would hold its values once, where a scalar's
  initializer runs each time the block does — assign the elements in the block.
  A function-local array takes no list.

⚠ Before 6.6.16 the list was a byte list whatever `T` was:
`var t: i64[3] = {1, 2, 42};` read `t[0] == 0x2A0201` and `t[1] == t[2] == 0`, on
every target. A value over 255, `-3`, `1.5` and an enum constant were refused,
`Pt[2]` / `bool[2]` / `i8v16[2]` lists compiled silently into bytes, and the
bytes were stored at startup — after the program, in a `kernel;` build, so a
kernel that never returns read 0.

### Subscripts: `a[i]` (6.6.12)

An integer element-typed array `var a: T[N]` (T one of `i8`..`i64`,
`u8`..`u64`) takes a subscript — read, assignment and every compound
operator — in a function, at top level, in a `for` step and inside a
closure:

```
var t: i16[8];
t[i] = 0 - 5;          # stores 2 bytes
t[i] += 1;             # all ten compound operators (+= -= *= /= %= &= |= ^= <<= >>=)
var v = t[i];          # -4: an i8/i16/i32 element is sign-extended, u8/u16/u32 zero-extended
if (t[0]) { ... }      # tests the element
```

`a[i]` is exactly the element at `&a + i * sizeof(T)`, loaded and stored at
T's width — the same bytes as `load16(&t + i * 2)` / `store16(&t + i * 2, v)`,
which stay valid (and are what `var a: i64[N]` code wrote before 6.6.12:
`store64(&a + i * 8, v)`). A store truncates to the element as `store8/16/32`
do. There is **no bounds check**. Inside a capturing closure the subscript
reads and writes the closure's captured COPY, as `&a` there does.

Refused, by name (`cannot subscript 'a': ...`):

- a **bare** `var a[N]` (and `stack var a[N]`) — it states no element width
  (bytes in a function, slots at top level), so a subscript would be a guess;
  declare `var a: u8[N]` or `var a: i64[N]`, or keep `load*`/`store*` at an
  explicit byte offset;
- a **float, bool, pointer, vector or struct element** (`var a: f64[N]`,
  `f32[N]`, `bool[N]`, `*T[N]`, `i8v16[N]`, `Pt[N]`) — the subscript is
  integer-element only; keep `load*`/`store*` at `&a + i * sizeof(T)` (8 for
  f64, bool, an enum and a pointer, **4 for f32**, 16/32 for a vector). Before
  6.6.13 a vector-element array in the leading declaration block was read as
  the scalar its name starts with (`i8v16` as `i8`), so `g[i]` compiled there;
  it is refused like every other non-integer element;
- a scalar or a pointer (`var p: *i64`) — pointer subscripts are not in the
  language;
- a `u128` element, which does not fit one register (use `load64`/`store64`
  on its two halves).

A `slice<T>` local keeps its own bounds-checked `s[i]` (`lib/slice.cyr`).

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
- **A fn is defined at top level** (or inside a top-level block). A named `fn` / `async fn` inside
  a fn body, a closure, an `impl` method or a generic body is a compile error naming both
  (`fn 'inner' is defined inside fn 'outer'`) — before 6.6.16 it compiled and crashed (SIGILL /
  SIGSEGV). A local function is a closure: `var sq = |x| x * x;`.
- All functions return a value (`return 0;` if nothing to return)
- **Calling with the wrong number of arguments is a hard error** (v6.5.1; there is no
  overloading and no default arguments, so a count mismatch is never intentional). Since
  **6.6.5** that applies to the `obj.m(...)` method form as well — it used to build and bind
  the surplus parameter to whatever was in the register. ⚠ One consequence: an `impl` method
  written with **no `self` parameter** can no longer be called through the dot form, because
  the dot form supplies a receiver the method never declared. Call it by its mangled name
  (`Type_method(args)`), which is how the constructor idiom `fn new(a, b)` inside an `impl` is
  written anyway. Forward calls are exempt from the check — the callee has no body yet.
- **`x.m()` passes `self` exactly as `T_m(x)` would.** An untyped `self` (the `impl` form) is
  the receiver's address. A typed `self: T` follows the parameter rule: a struct is a **value**
  at every width — one of 8 bytes or less arrives in a register, a wider one by address and is
  copied on entry (v6.6.16) — so `fn Odd_sum(self: Odd)` and `fn P3_bump(self: P3)` see a copy,
  and writing `self.a` inside them does not change `x`. Before v6.6.11 the dot form pushed `&x`
  for a small typed `self` too and the method read its fields out of the address; before v6.6.16
  a typed `self` over 8 bytes was the receiver itself, so `x.bump()` changed `x`. A method that
  must change its receiver takes an untyped `self` or `self: *T`.

**Reserved words are a CLASS, not a short list.** `TOKNAME_BUILTIN` in
`src/common/util.cyr` is the single source of truth — **79** builtin/intrinsic names
(re-derived at 6.6.13 with `sed -n '/fn TOKNAME_BUILTIN/,/^}/p' src/common/util.cyr |
grep -c 'return "'`, after `f64_le` / `f64_ge` / `f64_trunc` moved from `lib/math.cyr` fns to
builtins; this line said 67 until 6.6.5, which was the count when the diagnostic was added at
v6.4.77 and the table has grown since), plus the statement keywords. `IS_KEYWORD_TOK`
*derives* from that table for the BUILTIN half — ⚠ but it enumerates the statement keywords
SEPARATELY, so those two CAN drift; the table, not this paragraph, is the authority. It covers `syscall`, the `load8/16/32/64` + `store8/16/32/64` family, every
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
# forms are the counted `for` above and `for x in …`.
for (var i = 0; i < 10; i = i + 1) { ... }

# For-in — a half-open range, or every element of a vec (lib/vec.cyr).
# Works inside a fn AND at top level (since 6.6.8 — before it, a top-level
# for-in crashed or failed to compile). The loop variable belongs to the loop.
for i in 0..10 { ... }          # i = 0, 1, ..., 9
for x in v { ... }              # x = vec_get(v, 0), vec_get(v, 1), ...

# Break / Continue
# `break` leaves the NEAREST ENCLOSING while, for, switch or match (v6.5.20 — C
#   semantics; before that a `break` inside a switch/match was a MISCOMPILE, see
#   "Switch" below).
# `continue` always belongs to the nearest enclosing LOOP. A switch or match in
#   between is transparent to it — `continue` inside a case skips to the loop's next
#   iteration, it does not fall out of the switch.
# continue works correctly in all loop types (v1.11.1 bug #13 fix)
# Both must have something to leave IN THE SAME FUNCTION (v6.6.7): a `break` with no
#   enclosing loop/switch/match, or a `continue` with no enclosing loop, is a compile
#   error ("break outside a loop or switch" / "continue outside a loop") — including one
#   inside a closure body whose only loop is the ENCLOSING fn's. Before v6.6.7 both
#   compiled clean: `break` became a wild jump and `continue` jumped to the loop top of
#   whichever fn last had a loop.
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

### Where globals land: natural alignment (6.6.13)

A global occupies exactly its own size — `var a: u8[363]` has 363 usable bytes, a
`var x: u8` one — and **every global starts at its natural alignment**:

| Global, by its size                                    | Starts at a multiple of |
|--------------------------------------------------------|-------------------------|
| 1 byte (`u8` / `i8` scalar, or a 1-byte struct)        | 1                       |
| 2 bytes (`u16` / `i16` scalar, or a 2-byte struct)     | 2                       |
| 4 bytes (`u32` / `i32` scalar, or a 4-byte struct)     | 4                       |
| anything else — i64, pointers, f64, `u128`, every array, every other struct | 8 |

So `var a: u8[363]; var lock = 0;` puts `lock` at `&a + 368`, not `&a + 363`, and
`atomic_cas(&lock, 0, 1)` is safe on aarch64. Before 6.6.13 globals were packed at their exact
size: the global after a `u8[363]`, a narrow scalar, an `i32[3]` or a 12-byte struct was
misaligned, and the first atomic on it (`ldaxr`/`stlxr`) died with SIGBUS on a Raspberry Pi 4
and on Apple Silicon (x86 tolerated it). Adjacent narrow globals stay **packed**
(`var a: u8; var b: u8;` puts `b` at `&a + 1`), on purpose: an atomic needs only natural
alignment, and a store wider than its global still lands on the neighbour, where a test can
see it, instead of vanishing into padding. Do not reach a global by adding an offset to the
address of the one declared before it; the gap between them is the compiler's.

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

A `*T` variable is an 8-byte address whatever `T` is, and `*p` always loads 8 bytes
(use `load8` / `load16` / `load32` for narrower reads). `T` must name a type
([Type names](#type-names-6616)). **`p + n`, `p - n`, `p += n` and `p -= n` step
`sizeof(T)` elements, wherever `p` is declared** — a local, a parameter, a global, a
closure capture, a struct field or a fn result: `*u8` / `*i8` step 1, `*i16` 2, `*i32` /
`*u32` / `*f32` 4, `*i64` 8, `*Pt` `sizeof(Pt)`, a pointer to a pointer 8. A `*T` value
is a pointer, not a `T`: `p + 1` on a `p: *f32` parameter is address arithmetic (not a
float add), and on a `p: *Pt` parameter it is not `Pt`'s `+` overload — `p.x` still reads
through it. To step in bytes, use an untyped address (`&buf + i * 4`, or `var q = p;`).
`n + p` steps like `p + n`. `q - p` of two pointers with the same element size is the number
of elements between them (`(q - p) / sizeof(T)`, a plain integer); two pointers with
different element sizes (`*i64 - *u8`, `*Pt - &buf`) are a compile error — there is no
honest unit — so subtract plain addresses for a byte count. A call's result is a pointer
only when the fn declares `: *T`; `f(p) + 1` adds 1 whatever `p` is. (Before 6.6.17,
`q - p` scaled `q`'s partner and read garbage, `n + p` stepped 1, and a call's result kept
its last argument's step.)
⚠ Before 6.6.17 the step depended on where `p` was declared: a local `*i8` / `*i16` /
`*i32` stepped 1 and every other local `*T` 8 (`*u8` too), a parameter or a captured
`*T` 1, a global 8 in the leading declaration block and 1 / 2 / 4 / 8 by `T` after the
first statement, and `p += n` 1 everywhere. No source in the ecosystem declared a `*T`,
so the rule changed without a transition error.
⛔ Before 6.6.16 a **local** `var p: *i8` / `*i16` / `*i32` was stored in 1 / 2 / 4
bytes, truncating the address: `p == &buf` was false and `load8(p + 1)` crashed.

`*T` is also a struct or union **field** type and a fn **return** type (and a multi-value
return element) — `struct PH { name: *Str; }`, `fn first(q: *Q): *Pt`. Either is an 8-byte
pointer whose value steps `sizeof(T)` like any other, so it binds to a `*T` local without a
warning. A field may point at the struct being declared or at one declared below it
(`struct Node { val; next: *Node; }`, two structs pointing at each other); it steps the
complete struct's size. A pointer to a generic instance (`*Box<i32>`) steps the instance's
size, `sizeof(Box<i32>)`. Before 6.6.17 both positions were the parse error
`expected identifier, got '*'`.

A `*Struct` variable — a local, a global or a parameter — takes **dot syntax**: `p.val`,
`p.val = 3`, `p.next.val`, `p.m(..)` read and write through the pointer, and `p = q` rebinds
the pointer (it never copies the struct). So does the result of a fn declared `: *Struct`
(`first(h).next.val`, `first(h).m(..)`). Before 6.6.17 only a parameter did; a `*Node` local
or global was "no struct type in scope", and such a call's result "does not return a struct".

A field chain goes **through** a pointer field to a struct the way `p.val` does: `a.next.val`, `a.next.next.val = 3`, `a.next.twice()`, from a local, a global, a
parameter, a closure capture, a call result (`mk().first.next.val`) or a longer chain, in a fn
and at top level. (Before 6.6.17 it was `expected ';', got '.'`.)

```
struct Node { val; next: *Node; }
fn sum(head: *Node): i64 {
    var s = 0;
    var p: *Node = head;
    while (p != 0) { s = s + p.val; p = p.next; }
    return s;
}
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
var a = Point { 1, 2 };
var r2 = Rect { a, 10, 5 };  # a nested field also takes a whole struct value (v6.6.12)
```

A positional literal fills the **leaves** of the struct in declaration order, descending into
every nested struct field (at any depth), and writes each leaf at its own offset and width. For
a nested struct field it also takes a whole struct **value** of that field's type — a local, a
parameter, a global, a struct-typed field (`b.v`), or a call, method or operator returning it —
copied byte for byte. A value whose type is the FIRST field of the nested struct fills that
inner struct (`struct Outer { t; b: Box; }` with `struct Box { v: Point; n; }`:
`Outer { 1, a, 4 }`), and a struct of any other type is a compile error naming both. At top
level a call returning a 9-16 byte struct has no frame to land in and is refused by name (call
it inside a fn).

⚠ Before v6.6.12 a nested field was flattened at **8 bytes per inner field**, whatever the inner
fields' widths, and never descended further: `struct HO { o: Odd; t: i8; u: i32; }` with
`struct Odd { a: i8; b: i16; }` (8 bytes) had its literal write 13 bytes past the object — over
the next global, or the calling fn's frame — and a struct nested two levels deep took the wrong
number of values. Both were silent, on every target.

### Field chains and call results (v6.6.12)

A field chain reaches any depth, for reading and writing, through a local, a global, a by-value
parameter or a `*T` parameter alike: `n.v.v.x = 3;`, `var r = h.w.v.v.y;`. A `.field` also
applies to a **call** that returns a struct, in any expression position and as a bare
statement, and chains on from there:

```
struct Pt { x; y; }
struct Box { v: Pt; n; }
fn mk(a): Box { var b: Box; b.v.x = a; b.v.y = a + 1; b.n = 5; return b; }
fn take(p: Pt): i64 { return p.x + p.y; }
fn demo(): i64 {
    var y = mk(3).v.y;         # 4
    var s = mk(3).n + 1;       # 6, an integer
    var q: Pt = mk(7).v;       # a struct-typed field, copied whole
    return y + s + take(mk(1).v) + q.x;
}
```

Inside a fn the result lands in a frame temporary and the field is read from it, exactly as for
a named struct: the same widths, sign-extension and `f64` typing. A method applies to the result
itself (`mk(3).total()` calls `Box_total`, as a value or as the statement `mk(3).total();`); as
for a named struct, not to a nested field (`mk(3).v.sum()`, like `b.v.sum()`, is a syntax error). At top level there is no frame:
`var G = mk(3).n;` is refused by name — call it inside a fn. A field of a call to a fn that
does not return a struct is refused too, and so is an assignment to a result's field
(`mk(3).n = 5;`): the result is a temporary.

⚠ Before v6.6.12 a chain stopped after two levels — `n.v.v.x` was the syntax error
`expected ';', got '.'` — and a `.field` after a call was `expected ')', got '.'` in every
position; `var s = mk(3).n + 1;` also typed `s` as `Box` and looked for an undefined `Box_add`.
All of these were loud: nothing compiled wrong.

A **method's** result takes `.field` and `.method(..)` the same way, chained to any depth, as a
value or as a bare statement (since 6.6.17): `var u: Str = s.clone().cat(t);`,
`p.bump().bump().sum()`, `p.big().c`. Each link's result is held like a call's (a frame
temporary), so the receiver is untouched. At top level a chain on a struct-returning method is
refused by name, as a call result's field is, and a chain on a method that returns no struct is
`cannot take a field of the result of 'T_m': it does not return a struct`. Before 6.6.17 the `.`
after a method call was `expected ';', got '.'` in every position.

### Field types (v6.6.10)

A field is untyped (`x;`, 8 bytes, i64) or annotated `x: T`, where `T` is one of:

| `T` | Bytes | Notes |
|-----|-------|-------|
| `i8` / `i16` / `i32` | 1 / 2 / 4 | Narrow and **signed**: `p.x` sign-extends. |
| `i64` | 8 | The same as no annotation. |
| `u8` / `u16` / `u32` / `u64` | **8 each** | ⚠ Not narrow. The name is accepted but the field is a full word, so `struct { a: u8; b: u8; }` is 16 bytes, not 2. For a binary layout, use `i8` / `i16` / `i32` and mask the value. |
| `f64` | 8 | **Typed** — `p.x + p.y`, `p.x * 2.0`, `-p.x` and `p.x < p.y` are float operations. |
| `f32` | **8** | Typed (single-precision arithmetic), stored in the low 32 bits of a full word. |
| `bool`, `cstring`, `Result`, `Option`, `Tagged`, an enum | 8 | An enum may be declared before or after the struct. `bool` since 6.6.16 (it was refused). |
| a struct or union | its size | Stored **inline**. It must be declared ABOVE the struct that uses it. |
| `Vec` / `Vec<T>` | 8 | A handle. |
| `*T` (any type name `T`) | 8 | A pointer: `p.f + n` steps `sizeof(T)` (see [Pointers](#pointers)). Since 6.6.17. |
| a type parameter of the struct being declared (`struct Box<T> { v: T; }`) | per instance | |

⚠ The field widths are layout (and ABI). `u8`..`u32` and `f32` have always taken 8 bytes;
v6.6.10 documents that rather than changing it.

Anything else is a **compile error that names the type**. Before v6.6.10 an unknown name was
silently an 8-byte i64, and three cases were silent miscompiles:

* `a: Nonexist` compiled (a typo, or a missing `include`).
* A struct used as a field type **above** its own declaration got a different layout than the
  same text below it: `struct A { b: B; x; }` written before `struct B { p; q; }` made A 16
  bytes instead of 24, and `a.b` read 8 bytes of a 16-byte value. It now reports
  `struct field type 'B' is declared after its use; declare it before 'A'`.
* `v: i16v8` (a vector type) registered as a 2-byte `i16` field. A vector cannot be a field
  type.

A struct cannot contain itself (`struct Node { next: Node; }` crashed the compiler before
v6.6.10); a link to another node is an `i64` (pointer) field.

**f64 fields are typed; `#derive(accessors)` getters are not.** For
`struct P { x: f64; y: f64; }`, `p.x + p.y` is a float add. Before v6.6.10 every operator on
such a field was an INTEGER operation on the bit pattern (`p.x + p.y` read as NaN for 1.5 + 2.0,
`p.x * p.y` as 0) with no warning, and correct code like `2.0 * p.x` drew a false
`f64 arithmetic with a non-f64 right operand` warning. A generated getter is `load64(...)` and
stays **untyped** on purpose, so `P_x(&p) + P_y(&p)` is still an integer add: code in the
ecosystem compares getter results bit-for-bit (`==` on the bit pattern), and a typed getter
would turn those into float compares with different NaN and ±0 answers. When you want float
arithmetic on a getter's result, hold it in an `f64` variable (`var x: f64 = P_x(&p);`) or use
the field directly. Since 6.6.11 a plain copy of the field is typed as well: `var t = p.y;`
makes `t` an `f64`, where it used to be an untyped `i64` holding the bits.

### Where a struct lives (v6.6.5)

A struct declared inside a fn — `var p = Point { 1, 2 };`, `var p: Point;`, `var p: Point = q;`
— is a **per-call frame object**. It is fresh on every call, private to the calling thread, and
its name is visible only inside its own scope. Take its address with `&p`. Pass it to a
`q: Point` parameter and the callee gets its own copy (v6.6.16); pass `&p` to a `q: *Point`
parameter and the callee works on `p` itself.

A struct declared at TOP LEVEL is a single shared object in the data section, and a local
declared as `var p: Point = <expression>` where the expression yields an ADDRESS (a heap
pointer, or a fn returning one) is a **pointer** to that object — `p.x` reads through it rather
than out of the frame. The compiler records which of the two a variable is at its declaration;
before v6.6.5 it guessed from the shape of the neighbouring stack slot and got it wrong for any
pointer-mode struct declared after a closed `{ ... }` block.

⚠ **An assignment between a pointer and a struct copies the struct (v6.6.16).** Call a variable
whose slot holds a struct's ADDRESS a *handle*: a pointer-mode local (`var a: P3 = alloc(24);`),
a pointer-mode global (`var G: P3 = 0;` then `G = alloc(24);`), or a `p: *P3` parameter. For a
plain struct over 8 bytes:

* `q = a` — a struct VALUE (an inline local or global, a by-value parameter) assigned from a
  handle — copies the struct `a` points at into `q`.
* `a = q` — a handle assigned a struct value (a variable, a by-value parameter, a field `b.v`, a
  call `mk(..)`, a method `q.dbl()`, an operator `l + r`) — copies INTO the struct `a` points at,
  as `*a = q` does in C. `a` still points where it did.
* `a = b` between two handles is a pointer **rebind**, at any pair of struct types, as it always
  was. So is a handle assigned something that is not a struct value: an untyped pointer
  (`a = alloc(24)`, `a = p`) or a call returning `Str`. Between two `*P3` parameters `a = b`
  rebinds too; before v6.6.16 it copied `*b` into `*a`.

A struct value of a different type assigned into a handle is refused
(`cannot copy 'r' into a variable of a different struct/vector type: 'a'`), as into an inline
struct. Before v6.6.16 each of these stored ONE word: `q = a` put `a`'s address in `q.x` and left
`q.y` stale, `a = q` put `q.x`'s value in `a`'s slot so the next `a.x` crashed, and `a = q` from a
by-value parameter made `a` point at the CALLER's struct, so `a.x = 9` changed it. `Str`, `Result`,
`Option` and `Tagged` (heap handles by name) and structs of 8 bytes or less are unchanged.

⚠ **The declaration and the assignment differ on purpose.** `var q: P3 = a;` takes its storage
class from its source: from a pointer-mode local or global it declares `q` as a second pointer to
the same struct, so a write through either is seen by both (the v6.6.5 alias). From a parameter it
copies, a `p: *P3` parameter included: `var q: P3 = p;` is the by-value parameter copy of v6.6.11,
so a later `p.x = 9` does not reach `q`. `q = a;` cannot change what `q` already is: an inline
`q` receives a copy, a handle `q` is rebound. For a private copy of a handle's struct, declare
first and assign: `var q: P3; q = a;`. One shape changed meaning: code that used
the one-word store to carry a handle through an inline struct variable (`var w: P3; w = a;` then
`f(w)` where an untyped `f(v)` reads `load64(v + 8)`) now passes `w`'s first field. Pass `a`, or
`&w`.

### Returning a struct by value (v6.6.6)

A fn declared `: Point` returns the struct itself — a struct over 16 bytes through a hidden
pointer the caller supplies, one of 9-16 bytes in two registers. Inside a fn the call may be
written anywhere, and the result gets frame storage wherever it is. That holds for all three
kinds of call: a plain fn call, a method call (`b.mk(1)` for an `impl` method declared `: P3`)
and an overloaded operator (`a + b` when `P3_add` is declared `: P3`):

```cyrius
struct P3 { x; y; z; }
fn mk(a): P3 { var p: P3; p.x = a; p.y = a + 1; p.z = a + 2; return p; }
fn take(q: P3): i64 { return q.z; }
fn fwd(a): P3 { return mk(a); }       # forwards the whole struct
fn P3_add(a, b): P3 { var p: P3; p.x = load64(a) + load64(b); p.y = 0; p.z = load64(a + 16) + load64(b + 16); return p; }

fn f(): i64 {
    var p: P3 = mk(1);                # every field
    p = mk(5);                        # assignment copies every field (p may appear in the args)
    var z = take(mk(7));              # a `q: P3` param receives the result's address — 9
    var x = mk(9);                    # inferred as a P3
    var s: P3 = p + x;                # an operator returning a P3 — s.z is 18
    return z + p.z + mk(3);           # as a plain value, a struct is its FIRST word (3), as a local's is
}
```

⚠ **A fn returning a 9-16 byte struct (two registers) can `return` only what those two registers
can carry**: a local of that struct, a call to a fn returning the same struct, or a method or
overloaded operator returning it. Anything else — a call returning a *different* struct, an
integer, a field, a bare `return;` — is a compile error since v6.6.6 naming what it got. Before
v6.6.6 every one of those compiled clean and handed back the first register plus a second that
was never written. (The >16-byte form has error'd on an uncarryable shape since v5.5.36.)

⚠ **A fn returning a vector can `return` only what the vector return ABI carries**: a local of
that vector type, or a call to a fn *declared* to return the same one. Anything else — an
integer, a scalar local, `load64(&v)`, a bare `return;`, `x + y` (there is no vector `+`), a
multi-value `return (a, b);`, a `callptr(..)` through a function pointer, a **global** of the
right vector type, or a call returning a scalar or a different-width vector — is a compile error
since v6.6.6 naming what it got. Before v6.6.6 every one of those compiled clean and handed back
a half-written register pair; `return x + y;` returned `y` unchanged and `return G;` for a
global read a stale register rather than `G`. The two that are worth spelling out because they
look reasonable:

* `return (a, b);` is the **ret2 int-register** convention (rax:rdx), which is the ABI of a
  9-16 byte *struct*, not of a vector. It stays legal for a struct return and for the scalar
  multi-value `var a, b = f();` form — only the vector classes refuse it. To build a vector,
  store the lanes into a local and return the local.
* `return callptr(fp, ..);` has no declared callee type to check, so the compiler cannot know
  the target returns this vector; it happened to work on x86_64 and aarch64 and returned the
  wrong lane on Windows. ⚠ There is **no** working spelling for a vector-returning `callptr`
  today: `var v: f64v2 = callptr(fp, 41, 7);` is broken too, and has been — measured at 6.6.5
  and at 6.6.6 it reads `0` and a garbage high lane on x86_64, with no diagnostic. Reported for
  a later bite. Two spellings that DO work, both verified: call the function by name into a
  vector local (`var v: f64v2 = mkv(41, 7);`), or, when the target really must be indirect,
  give it an out-pointer and have it store the lanes —
  `var v: f64v2; var ig = callptr(fp, &v, 41, 7); return v;` — which carries both lanes
  correctly.

⚠ **A struct-typed FIELD is a copy destination too (v6.6.10).** With `struct Box { v: P3; n; }`,
`b.v = p` copies the whole struct into the field. So does a call, method or operator that
returns a `P3` (`b.v = mk(1)`, `b.v = a.mk(1)`, `b.v = a + c`), a by-value `P3` parameter, a
pointer-mode `P3` local (the struct it points at, not the pointer), a global, and another `P3`
field (`b.v = o.b.v`). A struct of a different type is a compile error naming it, at every
size — a method or operator result of 8 bytes or less included (v6.6.11). Before v6.6.10
every one of these stored ONE word: `b.v.y` kept its old value, and from a parameter the stored
word was the parameter's address. A source that is not a struct (an integer, an untyped
pointer) still stores one word, capped at the field's size. An odd-sized struct field (3, 5, 6
or 7 bytes, such as `struct Odd { a: i8; b: i16; }`) gets exactly that many bytes from any
source, so the fields after it are never touched. Before v6.6.10 a method, an operator, a
top-level call or an integer stored 8 bytes into such a field, silently overwriting its
neighbours.

⚠ **A copy moves one struct into a variable of that SAME struct type.** `p = q` and
`var p: P3 = q` between two DIFFERENT struct types are a compile error since v6.6.6
(`cannot copy 'q' into a variable of a different struct/vector type: 'p'`), and so is a copy
between two different vector types (`f64v4 = f64v2`). Before v6.6.6 both compiled clean and
fell through to a plain 8-byte store: the assignment copied one word of three and left the rest
of `p` stale, and the declaration stored `q`'s *address* into a struct-typed slot, so `p.x` read
back a stack address. The struct-*literal* form (`var p: P3 = Q3{..}`) has been an error since
v6.6.5. A source that is **not** a struct or vector still binds as a pointer, unchanged.

The other direction is a copy too (v6.6.11): a struct **variable** taken from a struct-typed
FIELD — `q = b.v`, `var p: P3 = b.v`, into a local, a global or a by-value parameter — copies the
whole struct, byte-exact, and `p` is its own copy. Before v6.6.11 the assignment copied one word
and the declaration stored that word into a slot typed `P3`, so the next `p.x` SIGSEGV'd. A
struct-valued **call** assigned to a struct variable must return that struct, at every size and
through every call form: `p = mkq()` with `mkq` returning a different struct is refused
(`cannot copy 'mkq' into a variable of a different struct/vector type: 'p'`) as
`var p: P3 = mkq()` already was, and so are `z = y.same()`, `var z: Odd = y + y` and a generic
call whose inferred instance differs (`s = mk(r.v)` into a `Box<Pt>`: a FIELD argument infers
`T = i64`, so the call reaches `Box<i64>` — copy the field into a `Pt` variable first,
`var p: Pt = r.v; s = mk(p);`). The same holds for a struct-typed **global**, at top level and in
the leading declaration block: `var G: Odd = mkod2();` is refused wherever it appears. Before
v6.6.11 each of those stored one word, silently.

Two more field / global sources became copies in v6.6.12. **A struct-typed FIELD passed as a
by-value struct argument** (`take(r.v)` into a `: P3` parameter over 8 bytes), from any base (a
local, a global, a by-value parameter, a pointer-mode local), and through a generic instance
(`mk<P3>(r.v)`). The callee gets a COPY of the field, so writing through the parameter does not
reach `r.v`, at top level as in a fn — since v6.6.16 that copy is the callee's own, made on entry
as for every by-value struct argument (see below). From v6.6.12 to v6.6.15 a fn copied the field
into a frame temporary and top level, with no frame, passed the field itself, which the callee
then wrote. A field of a different struct type is refused (`cannot pass 'q' to a by-value
parameter of a different struct type in a call to 'take'`). Before v6.6.12 the field's first word was passed as the struct's
address, and the callee SIGSEGV'd. **A top-level copy-init** — `var B: P3 = A;` from an inline
global, or `var G: P3 = BX.v;` from a global's field, in the leading declaration block or after
the first statement — gives `B` its own STRUCTSZ bytes and copies them. Before v6.6.12 `B` got one
8-byte slot holding `A`'s first word, and `B.x` SIGSEGV'd. A pointer-mode source
(`var p: P3 = mk();`, or a global initialised that way) still binds a second pointer to the same
struct, exactly as in a fn. The source must be declared ABOVE the copy: `var B: P3 = A;` before
`var A = P3 { .. };` is refused (`cannot copy-init 'B' from a global declared below it`), since
globals are initialised in declaration order and `A` has not been initialised when `B` copies it.

⚠ **A by-value struct PARAMETER is a COPY, at every width (v6.6.16).** A `q: P3` parameter over
8 bytes still TRAVELS by address — the caller passes its struct's address, so the calling
convention is unchanged — but the callee copies the struct into its own frame on entry, before
the body runs, and from there `q` is an ordinary local struct. Writing `q.z = 5` inside the callee
changes the copy and never the caller's struct, whatever the argument was: a named local, a
global, a pointer-mode local's heap object, a parameter passed on (`mid(q)` calling `bump(q)`),
a typed `self: P3` receiver (`p.bump()` and `P3_bump(p)` agree), a generic instance
(`bumpg<T>(p: T)` with `T = P3`), a call through a fn pointer (`fncall1(&bump, &p)`) or a field
(`take(b.v)`), in a fn or at top level. Before v6.6.16 the parameter WAS the caller's struct, so
every one of those writes reached the caller, and this guide said so here; only a field argument
inside a fn was copied. A callee that must change the caller's struct says so in its signature:
`fn bump(p: *P3)`, called `bump(&p)` — or a method with an untyped `self` or `self: *T`. Because
the copy is made on entry, an argument that is not a struct (`take(0)` for a `q: P3`) now faults
there even when the body never reads `q`. And `q` reads like any struct variable: a bare `q` where
an untyped value is expected (`var k = q;`, `raw(q)` into an untyped parameter, `load64(q)`) is its
first field, as for an inline local and for a struct of 8 bytes or less — before v6.6.16 it was
the caller's address. Write `&q` for the address (of the copy). A struct of 8 bytes or less was
already a value: it travels in a register. An `async fn` refuses such a parameter (see *Other
limits* under async).

From v6.6.6 to v6.6.15 every path that copied or returned such a parameter went through that
address: `q = r`, `q = mk(..)`, `q = b.mk(..)`, `q = a + b`, `q = G`, `r = q`, `G = q`, `q = w` (a
copy, not an alias) and `return q;` all moved the whole struct (with the copy on entry they are
the plain local-struct paths, and they still do). Before v6.6.6 they moved the POINTER
instead — `q = r` overwrote it and the next `q.z` SIGSEGV'd, `r = q` put the pointer in `r`'s
first field, and `return q;` returned the address as the value, silently. The declaration
`var y: P3 = q;` joined the list at v6.6.11 — before, it bound `y` as a second pointer to the
CALLER's struct, so `y.a = 9` changed the caller and `return y;` returned garbage. `Str` (and `Result` /
`Option` / `Tagged`) are unaffected: they are heap handles passed by value, so `a = b` between
two of them is still a rebind.

Two more shapes joined that list later in v6.6.6. Such a parameter now **dispatches an
overloaded operator** (`q + w`, in either operand position, for a scalar- or struct-returning
operator fn) — before, only an *inline* local dispatched, so `q + w` silently ADDED THE TWO
POINTERS and `var c: P3 = q + w` SIGSEGV'd. And **`&q` is the struct, not the slot**:
`load64(&q + 16)` now reads the same word `q.z` reads, where before it read the frame word
holding the pointer and returned 0. Both were silent, exit 0.

⚠ This is a rule about PARAMETERS, not about pointer-mode locals in general. A struct local
whose slot holds a heap handle (`var p: P3 = alloc(24);`) is unchanged and deliberately so:
`p + r` there is POINTER ARITHMETIC and does not dispatch, and `&p` is the slot. Only a
`p: *T` parameter denotes the caller's struct.

⚠ At TOP LEVEL there is no frame to hold the result, so a struct-valued call there
(`mk(1);`, `var g: P3 = mk(1);`, `g = mk(1);`, `take(mk(1))` — and the method and operator
forms alike) is a compile error naming the fn — call it inside a fn. That includes a global
declared ahead of the first top-level statement, generic calls (`var G: W1<Pt> = mkw(p);`)
and non-generic ones (`var G: Pt = mkp(2);`) alike: before v6.6.11 that leading block was
never checked, so both compiled and `G.x` SIGSEGV'd, and after a statement the generic form
was checked against its 8-byte base and built too. An untyped `var g = pair_fn(..)` of a
9-16 B struct still yields its first word.
Before v6.6.6 a struct result had storage only in the two declaration forms inside a fn —
`var p: T = f(..)` and the inferred `var p = f(..)` — and only for a plain fn call. Every other
form, at top level or not, compiled clean and crashed (a >16 B result was written through the
first argument — for a method, through `self`; for an operator, through its left operand) or
silently lost the second half of a 9-16 B one.

⚠ **An array local over the per-fn frame budget (about 120 KB) keeps STATIC storage** — one
buffer shared by every call and every thread — and the compiler says so:

```
warning:<source>:12:15: array local over the per-fn frame budget gets STATIC storage: one
buffer shared by all calls and all threads; use alloc() for per-call storage
        var bigbuf[200000];
                  ^
```

The position names the DECLARATION. (Before v6.6.5 the line was a `note:` with no position at
all, and the first v6.6.5 cut of it named the statement AFTER the declaration.)

Its NAME is still scoped to its fn, so it cannot collide with a global elsewhere in the
program. Use `alloc()` when you need per-call or per-thread storage for a buffer that large.
The same applies to every array local when `CYRIUS_STACK_ARRAYS=0` is set.

⚠ **A struct-typed LOCAL used with a binary operator needs the matching `T_op` fn**, exactly as
a struct-typed GLOBAL always has. Before v6.6.5 the local form silently did an integer add on
the struct's first word instead of dispatching, so the same expression meant two different
things depending on where the operand lived:

```cyrius
struct H { v; }
fn H_add(a, b) { return a + b; }        # required — `h + 3` below dispatches here

fn f() { var h: H; h.v = 5; return h + 3; }
```

Without `H_add`, that now fails the build with *refusing to emit binary with 1 reachable
undefined function(s)*. The same holds for a struct **captured by a closure** — `var a = N { 1 };
var c = |x| a + x;` dispatches `N_add` from v6.6.5, where before it silently added the struct's
first word. Related: `var p: T = U { ... }` with `T != U` was silently accepted (`p` took U's
layout under T's name) and is a hard error from v6.6.5.

⚠ **An operator fn takes exactly two parameters**, and since v6.6.6 the compiler says so
(`'V2_add' expects 3 arguments, got 2`). Before v6.6.6 operator dispatch was the one call
position with no arity check, so `fn V2_add(a, b, c)` built clean and bound `c` to whatever was
in the third argument register — `a + b` returned a number computed partly from garbage. A
struct-returning operator is still two parameters: the hidden return pointer is not one of them.

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
| `\` + newline  | `0x0A`         | KEEPS the newline (not a C splice)   |

That is the whole list. **Any other byte after a `\` is a lex error**
(`unknown string escape`, pointing at the backslash) since v6.6.11;
before that it was stored with the backslash dropped, so `"ab\q"`
compiled to `abq`. A `\` at the end of a line inside a string is an
escape that keeps its line feed (`\` + CR LF keeps both bytes): the
string still contains the newline, it is not joined to the next line.
A newline inside a string, raw or escaped, is counted as a source
line, so diagnostics after a multi-line string name the right line
(and the right file) — before v6.6.11 every later token was reported
one line high per newline.

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

### A string literal passed to a `: Str` parameter is wrapped for you

```
fn slen(s: Str): i64 { return str_len(s); }

var n = slen("abcde");        # = 5 — the compiler emits str_from("abcde")
```

The wrap is driven by the CALLEE's `: Str` annotation, so it happens
wherever the call is written — and *wherever* means on every target as well
as in every call syntax. **This was uniform only from v6.6.5**, and it took
three passes to make the claim true:

- `obj.m("lit")` — the method-dot path marshals its arguments through its own
  loop and never ran the wrap.
- `return f("lit")` — the tail position emits its own epilogue and jump, and
  never ran it either. `var r = f("abcde")` and `return f("abcde")` returned
  **5 and 0 in the same program**.
- `var v: f64v2 = f("lit", k)` **on Windows only** — a 16/32-byte vector
  return is written through a hidden pointer there, so the receive emits its
  own call, with its own argument loop. The same source gave 5 on Linux and
  0 on Windows.

In each case the callee received a raw cstring pointer and every `Str`
accessor read the wrong shape, silently. If you are reading a bug report from
before 6.6.5 that blames `str_len`, check which call syntax it used — and
which target it ran on.

If you would rather not depend on the wrap at all, `f(str_from("abcde"))` is
always correct and always has been.

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
#   var a, b = one(1);                # `one` returns ONE value (6.6.17): every `return` is a
#                                     # single value and the body ends in one — at fn scope and
#                                     # at top level, a forward-declared `one` included
# (Before 6.6.17 the top-level destructure above the first statement checked none of these.)

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

`#derive(accessors)` applies to a **struct** only. On an `enum` it is a compile error, by
name, whether it is the first directive or stacked under `#derive(Serialize)` /
`#derive(Deserialize)` (v6.6.10; before that an enum's members were emitted as 8-byte
"fields" — `col_RED(p)` read `p + 0`, and the members' values were never involved). Derive an
enum's name codec with `#derive(Serialize)` / `#derive(Deserialize)` instead (below).

Stacked derives emit the same fns in **any order**: `#derive(accessors)` above or below
`#derive(Serialize)` or `#derive(Deserialize)` gives the accessors AND both JSON codecs
(v6.6.10; before that, accessors directly above Deserialize emitted no codecs, and the first
call to `X_from_json_str` failed as an undefined function).

An accessor reads and writes at the field's own width: an `i8` / `i16` / `i32` field gets
`load8/16/32` and `store8/16/32`, everything else (untyped, `i64`, `Str`, `Vec<T>`, `f64`, a
nested `#derive`d struct) an 8-byte slot (v6.6.7; before that every accessor was `load64` /
`store64`, so a narrow field's setter wrote into its neighbours). A narrow getter
**sign-extends**, exactly as `p.field` reads an `i8` / `i16` / `i32`: after `P_set_x(p, -1)` on
an `i8` field, both `P_x(p)` and `p.x` are `-1` (a bare `load8` would give 255). Every `#derive`
reads the body the way the parser does — comments, blank lines, `a : T` spacing, `;`-less fields
and `,`-separated enum members are all fine — and the build FAILS if its field offsets disagree
with the struct's real layout, which today means a field typed with a struct that is not itself
`#derive`d: derive the inner struct too. A struct NAME `#derive`d twice is checked too
(v6.6.11): the parser keeps the FIRST layout, so a second definition whose field names, order or
size differ is a compile error (`#derive: struct 'A' is defined again with different field names,
order or size`) — its accessors would read and write the first layout's bytes. Before v6.6.11
that second definition built with only warnings: a larger one's setters wrote past the first's
`sizeof`, and `{ x; y; }` redefined as `{ y; x; }` had every setter write the other field. The
same field names at the same offsets still build — an identical copy (one struct vendored by two
libraries), or one whose field TYPES differ at the same width (`f64` in one, `i64` in the other).

A preprocessor directive (`#ifdef`, `#ifndef`, `#if`, `#elif`, `#else`, `#endif`, `#ifplat`,
`#endplat`, `#define`) **inside** a `#derive`d declaration, or between the `#derive(...)` line
and the declaration, is a compile error naming the directive (v6.6.8). The derived code is
generated from every line of the body, so a conditional field cannot follow the branch the
parser compiles; put the conditional around the whole `#derive` + declaration instead. A `#`
comment in the body is fine. `#derive(Serialize)` writes a negative `i8` / `i16` / `i32`
field as the negative number it holds (v6.6.8; it was zero-extended — `-1` in an `i8` wrote
`255`).

## Derive Serialize on an enum (v6.5.31)

`#derive(Serialize)` and `#derive(Deserialize)` work on an **enum** as well as a struct, and
generate a name-string codec pair:

```
include "lib/result.cyr"        # required — the parse side returns Result

#derive(Serialize)
enum BlendMode { MULTIPLY = 0; SCREEN = 1; OVERLAY = 2; }

var sb = str_builder_new();
BlendMode_to_json(SCREEN, sb);          # sb now holds:  "SCREEN"

# ⚠ Bind BOTH halves — v6.6.0 made Result a register pair, and a single-var bind is a hard error.
var r_t, r_v = BlendMode_from_json_str("\"OVERLAY\"");
if (is_ok(r_t) == 1) { var v = result_unwrap(r_t, r_v); }   # v == OVERLAY
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

Where a `defer` may appear, and what its body may do (v6.6.7 — each rule below used to
compile clean and do something silent instead):

- **Only inside a function** — including a closure body or an `async fn`. At top level it is
  refused (`defer only allowed inside a function`), like `secret var` and `stack var`: there
  is no frame for its reached-flag and no epilogue to run the block. (It used to compile and
  SIGSEGV on x86/aarch64, or never run on cx.)
- **A defer body cannot leave its function.** It runs FROM the function's return path, so
  `return` (any form, a tail call `return g(x);` included), `?` and `ret2` inside it are
  refused (`return inside a defer body …`), and so is a
  `break`/`continue` that would jump out of it into the loop the `defer` sits in (`break
  cannot leave a defer body`). A loop or switch OPENED inside the defer body is fine.
- **A defer inside a closure belongs to the closure** — it runs when the closure returns, not
  when the enclosing function does (the same for `secret var`, whose zeroise is a defer).
  (v6.6.7; before, a closure's defer was registered on the ENCLOSING function.)
- **A body that falls off its end** (no `return`) runs its defers too (v6.6.7; before, it looped).
  That includes a coroutine `async fn`, which falls off to completion with the value 0
  (6.6.10; before, it looped on its own resume dispatch and the completing force never returned).
- **In a coroutine `async fn`** (one that `await`s mid-body) a defer runs exactly once, when
  the body completes — not at each suspend. An `await` inside a defer body is refused there,
  because the suspend would abandon the walker mid-run.

What a defer guarantees on the way out (v6.6.7):

- **It runs on EVERY return path**, a tail-shaped `return f(x);` included — `return Ok(fd);`
  and `return Err(e);` are exactly that shape. Before 6.6.7 such a return was compiled to a
  jump straight into `f` and skipped every defer, and every `secret var` zeroise, in the
  function.
- **So a function with a `defer` or a `secret var` anywhere in its body never tail-calls.**
  `return f(x);` is an ordinary call there. For a deep SELF-recursion that matters: each level
  keeps its frame, so write the recursion as a loop, or move the `defer` into a small wrapper
  that calls a defer-free recursive helper. (A defer inside a nested closure literal counts
  for the enclosing function too — the scan is lexical.)
- **The return value survives the defer body, whatever its shape**: an `Ok`/`Err` payload, a
  `(a, b)` / `(a, b, c)` tuple, `ret2`, a two-word struct, an `f64`, an `f64v2`/`f64v4`. A
  defer body is ordinary code and may call anything (a `sys_write`, a 6-argument helper, float
  or vector math); before 6.6.7 only the first return register was kept, so such a call
  zeroed an `Ok` payload.
- **A function with a `defer`/`secret var` is never inlined** — not by `#inline` (which warns
  `#inline ignored: body has a defer/secret block`) and not by the implicit inlining of small
  generic and SIMD-parameter functions. Its defer runs at ITS return, once per call; before
  6.6.7 an inlined body's defer ran at the CALLER's return.

## Math Builtins

```
var angle = f64_atan(x);         # Arctangent (f64)
var n = f64_to(x);               # f64 → i64, truncating toward zero
var m = f64_neg(x);              # sign-bit flip: f64_neg(+0) is -0, NaN keeps its payload
# See lib/math.cyr for additional math functions
```

`f64_to` gives the same integer on every target (6.6.8): a NaN converts to 0, a value at
or above 2^63 (including +inf) to `0x7FFFFFFFFFFFFFFF`, and one below -2^63 (including
-inf) to `0x8000000000000000` — aarch64 FCVTZS's rule. x86 used to return
`0x8000000000000000` for all three.

`f64_exp`, `f64_ln`, `f64_log2` and `f64_exp2` (6.6.8) promise the same things on every
target: a finite result within **1 ulp** of the correctly rounded value, and the IEEE-754 /
C special values — `ln`/`log2` of ±0 is -inf, of **any** negative number is NaN, of +inf is
+inf; `exp`/`exp2` overflow to +inf and underflow through the subnormals to +0; NaN in gives
NaN out (its sign and payload are not promised). `log2(2^k)` is exactly `k`. On aarch64 they
call `lib/math.cyr`'s `_f64_*_polyfill` fns (fdlibm ports), so include `lib/math.cyr` there.

What is NOT promised is the same **bits** on every target. x86 runs x87 instructions and
aarch64 runs the polyfill; both are within 1 ulp, but they can land on different sides of a
rounding boundary. When a program needs identical output everywhere (a golden file, a seeded
simulation), call `_f64_exp_polyfill` / `_f64_ln_polyfill` / `_f64_log2_polyfill` /
`_f64_exp2_polyfill` directly: they use only f64 add/sub/mul/div and integer bit operations,
so they give the same bits on every target, and `tests/tcyr/crossos/f64_log_exp_polyfill.tcyr`
pins them. Despite the `_` prefix these four are supported entry points (listed in
`docs/stdlib-reference.md`, *math.cyr*), as are the sin / cos / atan ones since 6.6.9.
(Before 6.6.8 the aarch64 polyfills returned finite values for ln of 0, of +inf and of most
negatives — `ln(-1.5)` was +4.27e9 — wrapped `exp(1000)` to a negative number,
and were up to 2,300 ulp off; and on Windows the x87 `f64_exp` ran at 53-bit precision and
was up to 350 ulp off.)

`f64_sin`, `f64_cos` and `f64_atan` (6.6.9) make the same promise: within **1 ulp** of the
correctly rounded value for **every** finite argument, `DBL_MAX` included — not just small
ones. `sin(±0)` is ±0 and a tiny `x` comes back unchanged, `sin`/`cos` of ±inf or NaN is NaN,
`atan(±inf)` is ±π/2 and `atan(±1)` is exactly the double nearest ±π/4. On **every** target
`f64_sin` / `f64_cos` call `lib/math.cyr`'s `_f64_sin_polyfill` / `_f64_cos_polyfill` (fdlibm
ports), so **include `lib/math.cyr` wherever you use them, x86 included** — without it the
compile fails with a message naming the include. Because the builtin is the same code
everywhere, sin and cos give the same **bits** on every target (except a NaN's sign). `f64_atan`
is x87 `fpatan` on x86 and `_f64_atan_polyfill` on aarch64: both within 1 ulp, not always the
same bits; call `_f64_atan_polyfill` directly for identical output. (Before 6.6.9 x86 ran the
x87 `fsin`/`fcos`, which reduce with a 66-bit π — `sin(π)` was 1.6e11 ulp off and `sin(1e19)`
returned 1e19 — and the aarch64 polyfills were up to millions of ulp off near multiples of π/2,
returned `sin(π) = -0`, and gave +inf or NaN for huge arguments.) Huge arguments cost more:
above 2^20·π/2 the reduction multiplies by as many bits of 2/π as it needs, about 0.5 µs a call.

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

A vector-typed **global** (`var g: f64v2 = 0;`) owns its 16 / 32 bytes and is used
through its address — `&g` with the pointer forms (`f64v2_add(&g, &h)` routes to
`f64v2_add_ptr`). A value-form read or write of it (`g = f(..)`, `var v: f64v2 = g;`,
`g = v;`) or an initializer other than `0` is refused by name: a value-form vector is a
local. (Before 6.6.17 it was one 8-byte slot, and each of those moved one word of it.)

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
# ⚠ `f32_from` takes an f64 BIT PATTERN, not an integer — `f32_from(1)` reads integer 1 as f64
# bits, a denormal ~5e-324, and narrows to f32 ZERO. Use real float literals. This example said
# `f32_from(1)` until v6.6.2 and therefore built an all-zero vector.
var a: f32v4 = f32v4_make(f32_from(1.0), f32_from(2.0), f32_from(3.0), f32_from(4.0));
var b: f32v4 = f32v4_splat(f32_from(10.0));
var r: f32v4 = f32v4_add(a, b);          # {11, 12, 13, 14}
var l0 = f32v4_lane0(r);                 # → f32 bit pattern of lane 0

# Pointer form — pass addresses; `&IDENT` auto-routes to f32v4_add_ptr
var r2: f32v4 = f32v4_add(&a, &b);

# 256-bit wrappers self-select AVX2 vs 2×SSE at runtime
var x: f32v8 = f32v8_make(f32_from(1.0), f32_from(2.0), f32_from(3.0), f32_from(4.0),
                          f32_from(5.0), f32_from(6.0), f32_from(7.0), f32_from(8.0));
var y: f32v8 = f32v8_splat(f32_from(2.0));
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
  used to re-point a file span (the hole v6.5.21 began closing for `private` and v6.6.6
  finished — see *Visibility*). The worst a forged `#@srcline` can do is misreport line
  numbers.

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
  in**, not to the files that file includes, and not to the file that includes it —
  and to the WHOLE file, wherever in it the marker sits (6.6.5; before that a
  definition written above the marker was stamped as if the file were public).
- There is **no per-item `private`**. `private fn h()` on one line is a hard error naming
  the file-level form (v6.5.56) — `private` alone on its own line, or `private;`, which
  closes the statement and lets an item follow on the same line. ⚠ Until 6.6.5 that
  rejection still flipped the file private and printed itself twice, so a *legitimate* fn
  in the same file was then reported "private to its file" at its caller.
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
- **A source file cannot forge its own identity (v6.6.6, CVE-45).** Visibility is decided from
  the preprocessor's `#@file` markers, and `FM_BUILD` accepts one at any offset, so a line
  spelling `#@file "other.cyr" 1` used to make the code after it belong to `other.cyr` — which
  is exactly a way to reach that file's private items. v6.5.21 closed that for the main source;
  until v6.6.6 an **included file**, a **`#define` macro body** and a **`#derive` line's tail**
  each still got through (measured: a forged include called a private fn and the program built
  and ran). Such a line is now rewritten to an inert comment wherever source enters the
  preprocessor, in every fork. ⚠ `#@file` inside a **string literal** is data and is left
  alone. This is not a sandbox — whoever writes the forged line already controls the source
  being compiled — but `private` is meant to be checkable, and now is.
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
- **The boundary covers every way of reaching a fn, not just a direct call (v6.6.4).**
  `&_helper` (address-of, then `callptr` / `fncallN`), `s.method()`, a struct-returning
  call bound with `var s: T = _mk()` or `var s = _mk()`, and the Win64 SIMD receive/return
  forms all report `'_helper' is private to its file` exactly like a direct call — before
  6.6.4 every one of them compiled and ran (hisab found `&_helper` while writing a
  reachability gate). Top-level **arrays** are covered too: `var _buf[N]` in a private file
  is file-private like any other global (it was never stamped before 6.6.4). A `public fn
  f<T>` in a private file is reachable at every instantiation (`f<i32>(x)` from another file
  used to be refused while `f(x)` was accepted — the instance inherited the file default).
  Enum constants and type names carry no visibility; they are always public.
- **`public` marks exactly one item, and only an item that can carry visibility (v6.6.4).**
  On a `struct`, `union`, `enum`, `impl` or `use` it is accepted as documentation and
  consumed by that item — it never carries over to the declaration after it. Before 6.6.4 it
  did: `public enum E { … }` in a private file silently re-exposed the NEXT fn or var (hisab
  found a private `_ad_pow` reachable this way), and so did a bare `public struct`, `public
  union`, `public impl`, `public use` and `public var a[N]`. Consequences worth knowing:
  `public impl Tr for T { … }` marks **no** method — put `public fn` on each method you
  export (its first method used to be public by the leak); one `public var a, b = f();`
  exposes **every** bound name (it used to expose `a` only); and a `public struct` /
  `public enum` with `#derive(Serialize)` gets **public codecs** (`T_to_json`, `T_from_json`
  and `T_from_json_str` for a struct; `E_to_json` and `E_from_json_str` for an enum), exactly
  as its `#derive(accessors)` getters already did.
  A global declared after the first top-level statement is file-private like any other
  (it used to be unstamped on that path).
- **Where the `private` marker sits in the file does not matter, and a FORWARD reference is
  checked like any other (6.6.5).** The marker applies to the whole file it appears in —
  including definitions written *above* it, and including globals. And a reference that
  comes EARLIER in the concatenated stream than the definition it names is enforced exactly
  like one that comes after: `q.m()` / `Q_m(&q)` on an impl method, `a + b` through an
  operator `impl`, a `mod`-scoped fn, and a fn defined after the first top-level statement
  all report `'…' is private to its file`.
  ⚠ Before 6.6.5 every one of those was **reachable** from any file purely because the call
  was parsed first, and the same root produced the mirror-image defects: two files each with
  a private helper of the same name got false `is private to its file` and false
  `expects N arguments` errors, the two-file `_helper` example above was REFUSED when `b.cyr`
  was included first, and a forward call passing a `>8`-byte struct by value SIGSEGV'd.
  See `docs/development/issues/archived/2026-09-13-private-impl-method-forward-call-fail-open.md`.

Both names are reserved words — see the reserved-word note under *Functions*; you
cannot use `public`, `pub`, or `private` as identifiers.

## Preprocessor

```
# Conditional compilation (v5.6.1)
#ifdef CYRIUS_TARGET_LINUX
    var fd = file_open("/proc/self/exe", 0, 0);
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
at every call site (unlike `#must_use`'s discard-only); a bare `#deprecated`
is refused by name. These attributes (and `#pure`/`#io`/`#alloc`) warn the
same way on every target and whether they sit before or after the first
top-level statement — before 6.6.9 only x86_64 honoured them ahead of it.
A top-level `#assert` is a declaration-phase directive, on one line or
wrapped: structs, enums and fns may follow it.

An attribute belongs to the **fn definition it precedes**, with any statements in between:
`#must_use` / `y = g<i32>(1);` / `fn b()` marks `b`, not the `g$i32` instance the statement
mints (before 6.6.17 the instance took it — `b();` was silent and every `g<i32>` call warned
`#deprecated`). Every directive also works **inside an `impl` body**, on the method it precedes
(6.6.17; it was `expected '}', got unknown`), and the dot call `p.m(..)` gets the checks a
plain call gets — `#deprecated` at every call (a call parsed before the `impl` included),
`#must_use` when `p.m(..);` discards the result (the last method of a chain, `p.bump().m();`),
`#pure`'s `#io` / `#alloc` check:

```
struct Acct { bal; }
impl Ops for Acct {
    #must_use
    fn take(self, n): i64 { store64(self, load64(self) - n); return load64(self); }
    #deprecated("use take")
    fn withdraw(self, n): i64 { return Acct_take(self, n); }
}
```

`#assert A OP B, "message";` checks a compile-time fact and stops the build
with `#assert failed: message` when it does not hold. Each operand is ONE
atom — an integer literal, `sizeof(T)`, or an enum constant (`EB` or
`E.EB`, since 6.6.10) — and `OP` is one of `== != < > <= >=` (a lone atom
asserts non-zero). There is no arithmetic inside an `#assert`: write
`#assert sizeof(Hdr) == 16;`, not `== E.N * 8`. Only `,`, the message
string, `;` or the end of the line may follow the operands; anything else (`E.N * 8`, a stray word) is
refused with ``expected `,` or `;` after the operands`` — before 6.6.10 it was
skipped unchecked, so a false `#assert E.EB * 2 == 9;` compiled clean. An
operand that is none of
these is reported once, by name (`expected a number, sizeof(T) or an enum
constant`), and `sizeof` must be the whole word — `sizeofzz(P)` is refused,
not read as `sizeof`. So must its TYPE (since 6.6.11, in `#assert` and in
expressions alike): `sizeof(i8zz)` is refused, not 1. Since 6.6.16 both read
the one type-name vocabulary ([Type names](#type-names-6616)): `sizeof(u8)`,
`sizeof(f64)`, `sizeof(bool)`, `sizeof(u128)` (in `#assert` too), an enum and a
vector type (`sizeof(i16v8)` is 16) all size, and a miss names the type —
`unknown type 'i8zz' in #assert sizeof` — with no second `#assert failed`. An
`#assert` with no message and no `;` ends at the end of its line —
before 6.6.11 it swallowed the whole NEXT line (`#assert 1 == 1` then
`return 42;` dropped the return). A failing `#assert` no longer stops the
compile on the spot: every failing assert and any other error in the file is
reported, and no binary is written.

```
enum Wire { HDR = 16; }
struct Hdr { magic; len; }
#assert sizeof(Hdr) == Wire.HDR, "Hdr must match the wire header";
```

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

## Manifest keys (`cyrius.cyml`)

Every key the docs, the `cyrius init` templates or the ecosystem use is declared once in the
CLI (`cbt/manifest.cyr`) with what reads it; `cyrius help manifest` prints that table and this
one mirrors it (`tests/gates/toolchain/manifest_key_inventory.sh` checks both against each
other and against what the ecosystem's manifests actually write). Status: **read** — something
reads it; **held** — recognised, deliberately not read yet, warned by name when present;
**dropped** — never read, warned by name when present; **info** — metadata for people and
package recipes, never changes a build. Synonyms are resolved in that one place: `[build] src`
is read only when `entry` is absent. (Before 6.6.17 `[build] test` and `[build] defines` were
declared by 41 and 3 manifests and read by nothing.)

**One precedence for every key: argument > environment > manifest > default.** An operand or
flag beats an environment variable, which beats the manifest, which beats the built-in default;
a key with no argument or environment channel (a `—` above) simply has no such rung. The whole
manifest is read (a manifest past 16 MiB is refused by name) and values are TOML: `"…"` with
escapes, `'…'` verbatim, `true`/`false`, arrays (multi-line, with comments); a CYML body after
a `---` line is prose, never configuration. Keys compare whole — `dev-stdlib` is not `stdlib`,
`test-only` is not `test` — and that holds in `[deps.NAME]` too, where `path` / `git` / `tag` /
`target` must be TOML strings (`tag = 'v1'` reads `v1`; a bare `tag = v1` is refused by name).

`[build]` carries what used to be retyped on every CI line (6.6.17):

```toml
[build]
entry = "programs/smoke.cyr"
output = "build/sakshi-smoke"
defines = ["SAKSHI_SMOKE"]   # one `#define NAME` each; -D NAME / CYRIUS_DEFINES=A,B replace the list
dce = true                   # dead-code elimination; --dce / CYRIUS_DCE=1 (CYRIUS_DCE=0 turns it off)
```

They configure every `cyrius build` in the project — a bare one AND `cyrius build <other source>
<out>` (sigil's fuzz loop builds each harness with `-D SIGIL_SMOKE` from its manifest); `-D` on
`test` / `run` / `bench` stays a command-line choice. `CYRIUS_DCE` takes `1` or `0`; unset or
empty is no rung at all, and any other value (`CYRIUS_DCE=true`) is refused by name — cycc
itself reads every value but `1` as off, so it used to be a silent no.
`[build] test` (a file, a directory, or a list of either — `src/test.cyr` is what `cyrius init`
writes) is what a bare `cyrius test` runs FIRST, before every `.tcyr` under `tests/`; a file both
name runs once, and a declared path that does not exist is a named failure. Before 6.6.17
nothing read the key, so a declared `src/test.cyr` never ran — 41 manifests declared one. A
mistyped value (`dce = "yes"`) is refused by name, and so is a define holding a control
character (it would start a new source line in the compiled unit). `[build] target` is **held**
(pass `--target` / `--aarch64` / `--win` / `--agnos`), `[build] features` is **dropped** (features
are `[features]` + `--features`), and a key the vocabulary does not know — a typo — is warned
by name instead of being silently inert; a declared synonym (`src`) is not unknown.
`[build] strict` is **held** and warned when present: `cycc --strict` has had no effect since
6.3.2 — a reachable undefined function is an error by default and `--allow-undef` downgrades it
— so there is nothing for the key to switch. `cyrius build --strict` is still accepted and passed
through, for scripts that spell it; it changes nothing.

`cyrius build --print-config [<source> [<output>]]` resolves the configuration and prints each
value with the rung it came from, then exits 0 — it builds nothing and resolves no deps:

```
$ cyrius build --print-config
cyrius build configuration (argument > environment > manifest > default)
  manifest: cyrius.cyml
  build.entry = "src/main.cyr"  (manifest: [build] src)
  build.output = "build/hisab"  (manifest: [build] output)
  build.dce = true  (environment: CYRIUS_DCE)
  build.strict = false  (default)  [held: no effect since 6.3.2]
  build.defines = []  (default)
  ...
```

| Section | Key | Status | Synonyms | Environment | Argument | Read by |
|---|---|---|---|---|---|---|
| `[package]` | `name` | read | — | — | — | bundle name (cyrius distlib); the cyrius-source-repo check |
| `[package]` | `version` | read | — | — | — | CYRIUS_PKG_VERSION (`${file:PATH}` expands) |
| `[package]` | `cyrius` | read | — | — | — | the toolchain pin: re-exec into `versions/<v>`, its stdlib |
| `[package]` | `description` | info | — | — | — | people and package recipes |
| `[package]` | `license` | info | — | — | — | people and package recipes |
| `[package]` | `language` | info | — | — | — | people and package recipes |
| `[package]` | `repository` | info | — | — | — | people and package recipes |
| `[build]` | `entry` | read | `src` | — | `<source>` | cyrius build, cyrius package: the source |
| `[build]` | `output` | read | — | — | `<output>` | cyrius build, cyrius package: the output (a default) |
| `[build]` | `test` | read | — | — | `<file>...` | bare cyrius test: these (file / dir / list), then tests/ |
| `[build]` | `modules` | read | — | — | — | every compile: these files prepended before the entry |
| `[build]` | `dce` | read | — | `CYRIUS_DCE` | `--dce` | cyrius build: dead-code elimination (bool) |
| `[build]` | `strict` | held | — | — | `--strict` | has had no effect since 6.3.2: a reachable undefined function is an error by default; --allow-undef downgrades it |
| `[build]` | `defines` | read | — | `CYRIUS_DEFINES` | `-D` | cyrius build: one #define per name |
| `[build]` | `target` | held | — | — | — | pass --target / --aarch64 / --win / --agnos on the command line |
| `[build]` | `features` | dropped | — | — | — | features are [features] + --features |
| `[coverage]` | `programs` | read | — | — | `--programs` | cyrius coverage: RUN programs in the corpus (globs) |
| `[sections]` | `base` | read | — | — | — | bare-metal builds: the image load base |
| `[embed]` | `*` | read | — | — | — | every compile: the file's bytes as NAME() / NAME_len(), prepended before the entry |
| `[deps]` | `stdlib` | read | — | — | — | cyrius deps: stdlib leaves vendored into lib/ and auto-prepended |
| `[deps.*]` | `git` | read | — | — | — | cyrius deps: the repository to clone |
| `[deps.*]` | `tag` | read | — | — | — | cyrius deps: the tag to check out |
| `[deps.*]` | `path` | read | — | — | — | cyrius deps: a local checkout instead of git |
| `[deps.*]` | `modules` | read | — | — | — | cyrius deps: the files to vendor |
| `[deps.*]` | `modular` | read | — | — | — | cyrius deps: sub-modules from `dist/<name>/` |
| `[deps.*]` | `requires` | read | — | — | — | cyrius deps: stdlib leaves the dep needs in scope |
| `[deps.*]` | `optional` | read | — | — | `--features` | cyrius deps: resolve only when a feature names it |
| `[deps.*]` | `target` | read | — | — | `--target` | cyrius deps: resolve only for a matching target |
| `[lib]` | `modules` | read | — | — | — | cyrius distlib: the base bundle |
| `[lib.*]` | `modules` | read | — | — | `<profile>` | `cyrius distlib <profile>` |
| `[lib]` | `embed` | read | — | — | — | cyrius distlib: the [embed] entries the base bundle carries |
| `[lib.*]` | `embed` | read | — | — | `<profile>` | `cyrius distlib <profile>`: the [embed] entries this bundle carries |
| `[features]` | `default` | read | — | — | `--no-default-features` | cyrius deps: features on by default |
| `[features]` | `*` | read | — | — | `--features` | cyrius deps: a feature and the optional deps it turns on |
| `[groups]` | `*` | read | — | — | — | cyrius deps: a named group of stdlib leaves |
| `[release]` | `bins` | read | — | — | — | release.yml, install.sh, cyrius pulsar |
| `[release]` | `cross_bins` | read | — | — | — | release.yml, install.sh, cyrius pulsar |
| `[release]` | `scripts` | read | — | — | — | release.yml, install.sh |

## Build Tool & Dependencies

```sh
# cyrius.cyml declares deps — build auto-resolves them
cyrius build src/main.cyr build/myapp   # resolves deps + compiles
cyrius deps                              # manually resolve deps
cyrius build -v src/main.cyr build/myapp # verbose (shows compiler, binary size)
cyrius test tests/test.tcyr             # resolve deps + compile + run
cyrius test                              # [build] test first (6.6.17), then every .tcyr under tests/, each once
cyrius test a.tcyr b.tcyr -D FEATURE     # 1..N files; -D/-DNAME reaches test/run/bench/fuzz/check too (v6.6.5)
cyrius run src/main.cyr host 443         # compile + run; everything AFTER the source is the program's argv (v6.6.5)
cyrius run prog.cyx                      # run cx bytecode via cxvm — arguments are REFUSED (cx has no guest argv yet)
cyrius lint|fmt|doc a.cyr b.cyr          # 1..N files, every one processed (v6.6.5)
cyrius tests [dir]                       # recursively run every .tcyr under dir (default tests/)
cyrius bench [path|dir]                  # discover + run *.bcyr (recursive; v6.5.7)
cyrius fuzz [path|dir]                   # discover + run *.fcyr harnesses (recursive; v6.5.7)
cyrius fuzz --poison [path|dir]          # poisoning allocators + redzones; an overwrite exits 86 (6.6.18)
cyrius fuzz --poison=ab [path|dir]       # also run each harness at fill 0xA5 and 0x5A; outputs must match (6.6.18)
cyrius self                              # self-host check: compile THIS HOST's compiler fork twice, cmp (v6.6.6)
cyrius soak [N]                          # N-iter built-in self-host + tests/scyr/*.scyr (v5.7.38)
cyrius smoke                             # tests/smcyr/*.smcyr fail-fast (v5.7.38)
cyrius distlib [profile]                 # bundle src/ modules into dist/{name}.cyr
cyrius distlib --all                     # regenerate the base bundle AND every [lib.X] profile (v6.5.8)
cyrius distlib --check                   # verify bundles are current — compares BYTES, writes nothing (v6.5.8)
cyrius coverage [--full] [--min <pct>]   # reference coverage of src/ (--min 0..100 gates CI; -v or a failed --min names the misses, 6.6.8; `main` is not counted, 6.6.11)
cyrius coverage --programs 'programs/*_test.cyr' --per-entry   # RUN programs join the corpus (6.6.17); which entry references which fn
cyrius capacity [--check] [src]          # report compiler capacity / CI gate; no arg = THIS HOST's fork (v6.6.6)
cyrius pulsar                            # x86-64 LINUX ONLY: rebuild cycc + cross bins + tools, then install
cyrius lsp                               # build + install cyrius-lsp into ~/.cyrius/bin/
```

> ⚠ **`self` and `soak` compile the fork that belongs to the host they run on** — not
> `src/main.cyr`. That file is the x86-64 **Linux** fork; it is valid cyrius everywhere, so on
> aarch64 or macOS it compiles into a host-native binary carrying the x86 backend, and the
> self-host verdict is then about a compiler nobody ships (measured at 6.6.6: `FAIL: cycc!=cycc`
> on pi for a compiler that self-hosts, `Killed: 9` on ecb). `_self_host_src()` (`cbt/build.cyr`)
> owns the host → fork mapping — `main.cyr` / `main_aarch64_native.cyr` /
> `main_aarch64_macho.cyr` / `main_x86_macho.cyr` / `main_win.cyr` — and a missing fork is
> refused by name rather than substituted. Pinned by
> `tests/gates/toolchain/self_host_src_per_target.sh`. See CHANGELOG [6.6.6].
>
> ⚠ **`capacity` with no argument asks the same question** (v6.6.6). It used to default to
> the bare literal `src/main.cyr`, so inside a cyrius checkout on ARM or macOS it metered a
> compiler that host does not build and reported its table occupancy as the local one's —
> and `capacity --check`'s whole job is to warn before a cap bites. It now takes the host's
> fork first (`_capacity_default_src`, `cbt/build.cyr`) and falls back to `src/main.cyr` /
> `src/lib.cyr`, which is what a *non*-cyrius project — no per-target fork — has. Pinned by
> `tests/gates/toolchain/capacity_meters_host_fork.sh`.
>
> ⚠ **`pulsar` is an x86-64-Linux-HOST verb and now says so** (v6.6.6). It rebuilds the
> *tracked* x86-64 Linux `build/cycc` from `src/main.cyr` and then the x86-hosted cross
> compilers from it, so every stage execs an x86-64 Linux ELF. On ecb / ach / pi it used to
> die on that exec with `error: cycc compile failed` — a message about the compiler for a
> problem that is about the verb; it now refuses by name, before printing any progress, and
> names the fork this host's compiler IS built from. Pinned by
> `tests/gates/toolchain/pulsar_is_x86_linux_host_verb.sh`.

> ⚠ **`coverage` does not count the entry point `main`** (v6.6.11). Coverage counts a public
> fn as covered only when a test NAMES it, and a program's depth-0 `main` is invoked by its own
> file's `syscall(60, main())` (or the epilogue's auto-call), never by a test — so it could never
> count, and a project with an entry point could not reach 100 % (ganita read 139/141 and bayan
> 501/503 with `main` the only misses). It is excluded by the same rule `cyrius header` uses
> (`_src_is_entry_fn`, `cbt/srcscan.cyr`); only the exact name — `mainx` and `domain` still
> count. A `src/` whose only public fn is `main` has nothing to measure and gets the
> "no public functions found … not a pass" error. Pinned by
> `tests/gates/toolchain/coverage_corpus_and_failopen.sh` axis 20.
>
> ⚠ **`coverage` takes RUN programs as a corpus** (6.6.17). A project that tests with
> self-checking programs (`programs/*_test.cyr`, no `tests/`) read ~0 %: the corpus was
> `tests/**/*.tcyr` only. `[coverage] programs = ["programs/*_test.cyr"]` in cyrius.cyml, or
> `--programs <glob>` (repeatable; it replaces the manifest list), adds each matched file to the
> corpus, counted exactly as a `.tcyr` is — whole identifiers in code, comments and strings
> blanked. `*` / `?` stay inside one path segment (`programs/*_test.cyr` does not reach
> `programs/sub/`); a glob that matches nothing, or a program that does not exist, is a named
> failure; a corpus program is a test, so it is never counted as measured surface. `--per-entry`
> lists, for every corpus entry, the public fns it references. ⚠ This is TEXT coverage — a
> reference count, the same measure `.tcyr` corpora get — not execution coverage: building and
> running instrumented programs (P5-B) is v6.7.x, alongside the bounds-checked build mode.
> Pinned by `tests/gates/toolchain/coverage_run_programs.sh`.
>
> ⚠ **`distlib` regenerates and `--check`s sidecars on an x86-64 Linux host only** (v6.6.11).
> The `.deps` sidecar is compile-verified against EVERY target — x86-64 Linux, Windows, macOS
> and agnos (6.6.18), aarch64 Linux and macOS — and records every leaf any of them needs, so it no
> longer depends on the host that ran it (it used to be the host's `#ifdef` arms only, and `--check` drifted between a Mac
> and Linux CI). Only an x86-64 Linux CLI has a compiler per target (`cycc` by environment, plus
> `cycc_aarch64`), so on macOS, Windows and aarch64 `distlib` refuses by name instead of
> publishing a host-shaped sidecar. A verify that does not converge in 6 rounds is a refusal,
> not a "compile-verified" sidecar. `-v` prints each leaf a round adds and why.
>
> ⚠ **`cyrius test` / `tests` grade the assert summary, not the exit code alone** (v6.6.11).
> When a `.tcyr` calls `assert_summary(`, the LAST stdout line starting `N passed, M failed`
> must exist with N >= 1 and M == 0, on top of exit 0 — the rule every `.tcyr` reader applies.
> A test that dies before its summary with exit 0, runs its body twice (a defined `main` plus a
> top-level `main();` — the epilogue calls it again) or asserts nothing now FAILS, by name. The
> test's stdout is captured and echoed back. A test with a `main` returns `assert_summary()`
> from it and ends `syscall(60, main());`; one without ends `var r = assert_summary();`.

**The argument rule (v6.6.5), for every verb.** Flags may appear in any position
(`cyrius lint f.cyr --strict` == `cyrius lint --strict f.cyr`); a `-`-prefixed token the verb
does not declare is an **error that names it**; operand counts are enforced — an extra
operand is processed or rejected, never silently dropped; and a global `-q`/`-v` never shifts
the operands. `cyrius <verb> --help` prints exactly the flags the parser accepts. `run` is the
one stop-at-first-positional verb: a flag written after the source belongs to the program
(`cyrius run -- prog.cyr a` is the same as `cyrius run prog.cyr a`). A value flag given twice
is an error that names it (`--target=js --target=cx` used to mean cx, silently) — except the
two that accumulate: `-D NAME` and `--features`, where `--features a --features b` ==
`--features a,b`. The delegated tools (cyrlint, cyrfmt, cyrdoc, cyaudit, cyrsign, cyrsign-efi,
cyrld, ark, cyriusly, cyrius-init) follow the same rule, and `cyrlint --exit-with-count` no
longer switches `--strict`/`--strict-deferrals` off: the exit code is the larger of the count
and the strict verdict (2).
Before 6.6.5 each verb hand-rolled its own loop, and several spellings were silent *and*
mutating — `cyrius clean --dryrun` deleted `build/`, `cyrius fmt f --chekc` rewrote the file,
`cyrius build s --strict` wrote the binary to a file named `--strict`.

⚠ `distlib --check` compares **bytes**, not version strings — a sub-profile can carry a stale
encoder under a fresh version string, which is exactly how sankoch 2.7.6's gzip fix nearly
shipped with all nine sub-bundles still buggy. `--all` replaces the N+1 per-profile ritual.

Each bundle also emits a `dist/<lib>.deps` sidecar naming the stdlib leaves the fold needs in
scope. **Since 6.6.18 the compile-verify is the only authority for it** (P4 option 2): the sidecar
starts from the `lib/` includes the bundled modules keep, and the verify fixpoint adds exactly the
leaves the bundle needs to compile on every target. The producer's `[deps] stdlib` declaration, its
umbrella includes and its test-only leaves (`assert`, `bench`) do not reach it — from v6.5.10 to
6.6.17 the whole declaration was merged in, which published every producer's test leaves to every
consumer and hid real gaps behind a declaration. `[deps] stdlib` still drives auto-prepend and
`cyrius deps` for the package's OWN builds. A family directory (`lib/unicode/`) is one leaf, named
by the family; a profile's sidecar is verified the same way as the base bundle's.

The bundle carries the same leaves, in the same order, as a compile-verified **requires block**
(`# Requires (compile-verified; the leaves of dist/<pkg>.deps):` and one `include
"lib/<leaf>.cyr"` per leaf), so `include "dist/<pkg>.cyr"` alone compiles. `--check` against an
older bundle says `the committed bundle predates cyrius 6.6.18's requires block — run cyrius
distlib --all`. A name the converged verify could attribute to no leaf, named dep or bundled module
is printed as a warning with the targets it fails on (a deliberate consumer hook shows up there).
A non-symbol failure on agnos alone is a warning too. A consumer whose build fails on a leaf it
never declared gets the remedy under the error — `hint: '<name>' is defined by stdlib leaf
'<leaf>' — add it to [deps] stdlib in cyrius.cyml`; see
[ecosystem-migration-6.6.18.md](../development/ecosystem-migration-6.6.18.md).

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

**A `[deps.X]` with no `modules` (6.6.13).** A block that lists neither `modules` nor
`modular` means `modules = ["dist/X.cyr"]` when the tag (or `path`) ships that file — which
every `cyrius distlib` bundle does — so it is cloned, vendored as `lib/X.cyr` and
commit-pinned like any other, and the closest declaration wins. When the file is absent,
`cyrius deps` warns by name (`warning: [deps.X] declares no modules and tag '…' ships no
dist/X.cyr — nothing vendored; a transitive [deps.X] will resolve instead …`) and counts it
in the summary (`0 deps resolved, 1 vendored nothing`); the exit status stays 0. Write
`modules = []` for a dep that is **declared but not linked** (a binary, say): it is cloned
and pinned, nothing is vendored, and nothing is printed. Before 6.6.13 a modules-less block
was silently dropped and a transitive declaration of the same name resolved in its place. A
`[deps.NAME]` whose NAME contains `/` or `..` is refused — it would make the clone directory a
path outside the dep cache.

**`cyrius.lock` is a contract, not a cache (v6.6.4).** The resolver writes `cyrius.lock`:
one `commit	…` line per git dep (a repointed tag is refused against it), one
`<sha256>  lib/<file>` line per vendored file (sorted), and a `cyrius	<pin>` trailer naming
the stdlib pin. It is written whenever `lib/` gains a file the lock does not cover — since
6.6.9 that includes the **first** lock of a stdlib-only project and a stdlib leaf newly added
to `[deps] stdlib` (both used to be left out), so commit it. `cyrius deps --verify` checks
every locked hash **and** that every `.cyr` under `lib/` has a line: an unlocked file fails by
name (`not in cyrius.lock — run cyrius deps --relock`), and an empty lock is reported as
empty, not missing. On every resolve — including the implicit one `cyrius build`
runs — a stdlib leaf whose bytes in `~/.cyrius/versions/<pin>/lib` disagree with the locked
hash **under an unchanged `[package].cyrius`** is refused by name, with both hashes, and
neither `lib/` nor the lock is written:

```
error: lib/math.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE under an unchanged pin 6.6.4
  cyrius.lock records  a765…
  snapshot now hashes  e3e1…
  source: /home/you/.cyrius/versions/6.6.4/lib/math.cyr
  refusing to vendor or re-lock this leaf. Either bump [package].cyrius, or run `cyrius deps --relock` …
```

Bumping the pin re-locks silently (that is a dependency-spec change); `cyrius deps --relock`
is the explicit accept when the snapshot legitimately moved (e.g. after
`scripts/verify-store.sh --restore`). Before 6.6.4 the resolver re-vendored and re-locked the
mutated file silently and `deps --verify` then passed on it. A lock written before 6.6.4 has
no trailer: it fails open for one resolve and comes back stamped. `cyrius deps --lock`
re-hashes `lib/` **keeping** the commit pins (it used to drop them).

**The git-dep CACHE is verified too (v6.6.5, CVE-43).** A git dep is cloned once into
`$CYRIUS_HOME/deps/<name>/<tag>` (an untagged dep into `<name>/.untagged`, so it never shares
a clone with a `tag = "main"` dep — 6.6.17) and reused by every project on the machine, so on every
resolve the resolver checks that the checkout is still consistent with the tag it claims:
`.git` is a real directory, `HEAD == refs/tags/<tag>^{commit}`, `remote.origin.url` is the url
your manifest declares (compared with a trailing `/` and `.git` normalised away — `…/x` and
`…/x.git` are one repository), `git fsck` passes, and the working tree hashes back to HEAD's
tree with no extra files, both as git compares it and as RAW BYTES — a `.gitattributes` carried
by the tag would otherwise let a line-ending-only edit through. A raw difference is only
accepted if re-running the tag's blob through the same conversion reproduces your working tree
exactly, so a legitimately CRLF checkout (`core.autocrlf=true`) still resolves. It is computed in a private throwaway index, so nothing inside the shared cache
is written and the cache's own index, `assume-unchanged` bits and config get no vote — the
config keys that cannot be overridden on the command line (a `filter.*` driver, an `include.*`
that hides one, `core.autocrlf`, `core.worktree`, `extensions.worktreeConfig`) are refused
outright, as is a `.git/info/attributes`. Untagged git deps get the content half as well.

⚠ This is not a proof that the objects came from the remote: everything it reads lives inside
the cache, so someone who can write it can also make it self-consistent. The `cyrius.lock`
commit pin is what holds that line, and it is trust-on-first-use — pinned on the first resolve,
enforced on every later one. Keep `cyrius.lock` committed.

What changed for you: **metadata-only changes are now fine** — `touch`, `cp -a`, `rsync -a`,
or running git in the cache under `unshare -r` no longer produce "refusing tampered cache"
(through 6.6.4 a single `cp -a` of `~/.cyrius/deps` made every checkout fail). **Real changes
are refused in more shapes**: an edit whose mtime is restored, an edit hidden by
`assume-unchanged`/`skip-worktree`, a local commit in the cache, an untracked file the tag
does not carry (even one `.gitignore` hides), a cache with `.git` removed, a populated
submodule directory, a checkout of a different repository parked at that name and tag, and an
edit laundered by the cache's own git config. Hand-staging a cache directory is refused rather
than silently trusted unless you make it a faithful clone of the declared url at that tag —
for local resolution use `path = "../sibling"`, which is the supported route.

The refusal names the cache and an **offline** recovery:

```
error: cached checkout for dep 'foo' tag '1.0.0' does not match its source — refusing tampered
cache: a tracked file's content, mode or type differs from the tag.
  cache: /home/you/.cyrius/deps/foo/1.0.0
  offline restore: rm -f …/.git/index && git --no-replace-objects -C … reset -q --hard
  refs/tags/1.0.0 && git -C … clean -qffdx
  or: rm -rf …   (re-clones from the remote on the next resolve).
```

Four reasons have no local repair and say so instead of pretending: an unreadable `.git`, a
damaged object store, hostile configuration inside `.git`, and a cache of the wrong repository
— for those the message says to remove the cache and re-resolve. A damaged-object-store refusal
also quotes git's own first line, so you can see what git actually objected to. A dep whose tag
commit only trips an fsck *policy* check (an author line with no email, a bad date) still
resolves: those are not integrity failures, and reading them as such would make a legitimate old
dependency unresolvable for ever. Cost is a full `git fsck` plus two tree hashes — about
50-200 ms per dep on a warm cache, measured on real ones (585 files: 48 ms; 274 files with a
larger object store: 195 ms).

**A temp dir the check cannot write is not a verdict (v6.6.9).** The verify writes its
captures into the CLI's private temp dir. When that dir is full, at quota or out of inodes, the
dep is still refused — nothing unchecked is vendored — but the message says so and tells you
not to delete the cache:

```
error: cached checkout for dep 'foo' tag '1.0.0' could NOT be verified — refusing to vendor it
unchecked: the check could not write its temp files, so the cache was NOT judged.
  temp dir: /tmp/cyrius-4242 (errno 122 — full, at quota, or out of inodes)
  cache: /home/you/.cyrius/deps/foo/1.0.0  (not judged; do NOT delete it)
  fix: free space under that temp dir, or set TMPDIR to an absolute path elsewhere, and re-run.
```

(Through 6.6.8 this read as "refusing tampered cache … rm -rf", for every dep at once.) The CLI's
temp base is an **absolute** `$TMPDIR` when one is set, else `/tmp` (`%TEMP%` on Windows); a
relative `TMPDIR` is ignored, and one that does not exist or cannot be written is an error
that names it (`TMPDIR=… does not exist or is not writable`). The hashes behind `cyrius.lock`
come from `sha256sum`, or `shasum -a 256` where there is no `sha256sum` (macOS 13), or `certutil` on Windows.

⚠ **Native Windows is out of scope for all of this**, as the git-dep flow always has been:
`sys_fork` does not exist there, so no git command can run. A pre-populated cache resolves with
a one-line warning that it was NOT verified, rather than failing with a reason that would be
untrue.

## Fuzzing with `--poison`

`cyrius fuzz --poison` builds every harness with `#define CYRIUS_POISON`, which turns the stdlib
allocators into poisoning ones (6.6.18, P6):

- **What is covered.** `alloc()` (the bump heap and the `big` own-mapping path, on Linux, macOS and
  Windows), arenas, `fl_alloc`, and any `_a` API you hand `poison_allocator()` or
  `poison_allocator_over(inner)`. Each block gets a 32-byte LEADING and a trailing redzone filled
  with the poison byte (0xA5 by default; `poison_fill_set(b)` takes 1..255), sits on a live list,
  and is filled and quarantined when freed — never reused. agnos and cx `alloc()` are not
  instrumented (the seam still compiles there).
- **When a write is seen.** Every poisoned allocation checks the previous block's redzones; a full
  `poison_sweep()` runs each time the poisoned-allocation count reaches a power of two (from
  1,024 on); `assert_summary()` sweeps before it reports. You can call `poison_sweep()` yourself —
  it returns how many blocks are bad.
- **What happens.** The first overwrite prints one line on stderr —
  `poison: redzone overwrite — <alloc|arena|fl|seam> block <addr> (<req> bytes): <n> byte(s)
  changed [leading|trailing|after-free|header]` — and the harness exits **86**, a code reserved for
  poison. A harness that wants to keep going (to assert on `poison_violations()`, say) calls
  `poison_trap_set(0)`; one may also assert on the stderr line. Without the compile flag,
  `fl_poison_enable()` at run time poisons `fl_alloc` blocks and only counts.
- **Reads.** An overread does not trap: the harness reads the fill and carries on.
  `--poison=ab` catches it by compiling and running every harness twice — fill 0xA5, then 0x5A
  (`#define CYRIUS_POISON_B`) — and passing only when both legs exit 0 with byte-identical stdout
  (`FAIL (A/B diverged at byte N)` otherwise). It doubles the time, and a harness that prints
  timings or seeds from the clock diverges by itself. A harness may also compare a read against
  `poison_fill()`.
- **Arenas under poison** run their bookkeeping on the request, so `arena_used` /
  `arena_remaining` and every accept / refuse decision are the non-poison values, but an arena
  never re-issues an address after `arena_reset` — do not assert pointer identity across a reset
  in a fuzz harness.
- **NOT covered:** a read that jumps a whole redzone into a live neighbour, a read past a logical
  bound inside one allocation, stack and static memory, agnos and cx. There are no guard pages.

**Routing your own allocator through it.** A hook-style seam points at `poison_alloc` (the
`fn(n): ptr` shape — `sd_alloc_set(&poison_alloc)` for sadish's); an `_a` API takes
`poison_allocator()` (`vec_new_a(poison_allocator())`); an existing Allocator is wrapped with
`poison_allocator_over(inner)`, which zeroes what it hands out and checks and forgets its blocks on
reset. The seam needs no compile flag; after `alloc_reset()` such code calls `poison_forget_all()` to
drop the live list.
`poison_reset()` resets the violation counter only.

## Linter

```sh
cyrlint myfile.cyr                                  # lint a file
cyrius lint src/*.cyr                               # lint N files in ONE cyrlint run
cyrius lint --strict src/main.cyr                   # exit 2 when there are warnings
cyrius lint src/main.cyr --strict-deferrals         # exit 2 on an UNTRACKED deferral marker
cyrius lint --exit-with-count a.cyr b.cyr           # exit = TOTAL warnings over all files, clamped to 255
```

`--exit-with-count` means the same thing through `cyrius lint` and through `cyrlint`: the
warning count summed over every file, clamped to 255 (an exit code is 8 bits — 256 used to
exit **0**). An unreadable file always forces a non-zero exit, even when the count is 0.

⚠ This block read `cyrius lint  # lint all stdlib` until v6.6.5, and a bare `cyrius lint`
has never done that — it prints usage and exits 1. Corrected together with the argument
handling itself: flags may now appear **in any position**, an undeclared `-`-prefixed token
is an error that names it, and every file you pass is linted (it used to lint the FIRST one
and report that verdict for the lot, which is how ranga's CI linted 1 of 41 files). See
`docs/development/issues/archived/2026-09-16-mabda-lint-wrapper-drops-strict-deferrals.md`.

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

**Rules see across line breaks (v6.6.5).** A cyrius string may hold a raw newline, and the
brace counter carries "inside a string" from one line to the next (it used to reset, which
gave every `src/main*.cyr` a false `unclosed braces`). The forward-ref rule scans the whole
initializer up to its `;`, so a wrapped one is checked too:

```cyrius
var A = 1 +
    B;              # warn line 1: global var init refs 'B' declared at line 3
var B = g();        # A is 1 at runtime, not 1 + g()
```

The untracked-deferral rule (`--strict-deferrals`) reads a **comment paragraph** — consecutive
comment-only lines, plus a code line's trailing comment and the comment lines continuing it —
joined with one space, so a term wrapped by a formatter is still seen (`a later` / `bite`,
`for` / `now`, `follow-` / `up`). The terms: `NOT_IMPLEMENTED`, `SCAFFOLD`, `TODO`, `FIXME`,
`XXX` (exact case) and `deferred`, `follow-up`, `for now`, `not yet`, `later bite`,
`future bite`, `out of scope` (any case, any run of spaces). A **tracking pointer** —
`CHANGELOG`, `roadmap`, `docs/`, `issue`, `See `, or a version such as `v6.6` / `v0.8.0` —
counts only on a line the term itself touches; a pointer elsewhere in the paragraph does not
track it. A blank `#` line, a code line or a `#skip-lint` line ends the paragraph.

The same across-the-line reading covers the other statement shapes the compiler accepts:
a declaration header wrapped anywhere (`var` / `A = 1 + B;`, `var A:` / `i64 = …`,
`var A` / `: i64 = …`, `var A` / `= 1 + B;`, past comment lines), a `pub var` / `public var`
declaration, a second `var` after a `;` — on the same line, or after an initializer that
wrapped — and a declaration after a `}` (`fn h() { … } var A = 1 + B;`) are all checked by
the forward-ref rule, which compares declaration ORDER, so `var A = B; var B = g();` on one
line warns too; `sys_open (p, 0, 0)` and `syscall` followed by `(` on the next
line are calls to the sys_open/getdents notes; `pub fn`, `public fn` and `#inline fn` names get
the snake_case check (it used to see only a line-initial `fn `), and `cyrdoc --check` counts
them too (it also used to read only the first 64 KB of a file). Whitespace at the end of a
line INSIDE a multi-line string, and blank lines inside one, are string data — neither the
trailing-whitespace rule nor the blank-line rule warns on them.

**The preprocessor reads it the same way (v6.6.6).** A line inside a multi-line string that
begins with `#ifdef` / `#ifndef` / `#if` / `#else` / `#elif` / `#endif` / `#ifplat` /
`#endplat` / `#define` / `#@file` / `#@srcline` / `#ref` is string DATA. Until 6.6.6 it was
EXECUTED: the directive line and any false branch vanished from the string data, silently and
with no diagnostic — `"ab` / `#ifdef NOPE` / `cd` / `#endif` / `ef"` compiled to the bytes
`ab\n\n\n\nef`. The four line-oriented passes now share one state machine (`PP_LEXST`) whose
string state crosses newlines, so a string literal means what it says wherever it starts. The
fourth is the `#host_only` scanner: an included file holding `var doc = "intro` / `#host_only` /
`end";` used to be recorded as a host-only module, so every `--target=…-bare-metal-elf` build
that pulled it was refused. A `#host_only` really at column 0 still annotates the file.

**And so does macro expansion (v6.6.6).** A `#define NAME(a) …` macro is expanded only where an
IDENTIFIER STARTS and only outside a string literal. Until 6.6.6 the macro pass — the FIFTH, and
the one the sentence above did not cover, because it is byte-oriented rather than line-oriented —
matched the name anywhere: `myID(5)` with `#define ID(a) (a)` in scope was rewritten to `my((5))`,
so a program with both `myID` and `my` defined silently CALLED THE WRONG ONE, and `"ID(5) literal"`
lost two bytes of its own data. Both are fixed; a name that merely ends an identifier, and a name
inside a string, are now left alone.

⛔ **And an invocation opened in a `#` comment used to delete your code.** This guide said, for one
release, that a macro inside a comment "cannot change what is compiled — a `#define` body stops at
the newline". That covers only what an expansion *writes*. What it *reads* ran to the matching `)`
wherever that was, so with `#define M(a) 0` in scope the comment

```
# TODO: fix M(
var r = 42;
var t = 1;
syscall(60, r + t);
```

expanded `M(` against the `)` of the `syscall` and swallowed everything between them — the program
body was gone, and it exited 0 with nothing on stderr. Since v6.6.6 an invocation that *starts*
inside a comment must also *close* on that line; if it does not, it is not an invocation and the
bytes stay comment. A single-line `# see M(1)` is still expanded, and still changes nothing. One
consequence to know: on an ATTRIBUTE line (`#inline fn f(): i64 { return N(5); }`, which the
preprocessor's state machine reads as a comment) a macro call still expands, but one whose
arguments **wrap onto the next line** no longer does — it fails loudly with `undefined function`
rather than compiling something you did not write.

⚠ **A `#` is not always a comment.** `#naked`, `#inline`, `#pure`, `#io`, `#alloc`,
`#must_use`, `#regalloc`, `#deprecated`, `#assert` and `#pe_import` are attribute TOKENS, and
the lexer keeps reading the line after them — so `#naked fn isr() {` opens a real brace.
`cyrlint`, `cyrfmt` and `cyrdoc` read them as the lexer does (v6.6.5; before that
`#naked fn f() {` drew false `unmatched closing brace` warnings and `cyrius fmt` rewrote the fn
body flush left).

An attribute name ENDS at a word boundary: the next byte must be whitespace or end of input.
Anything else and the `#` opens an ordinary comment, so `#ioctl numbers`, `#allocator notes`,
`#assertion holds`, `#naked-eye check` and `#io(fd) reads a byte` are all comments and compile
to the same bytes as `# ioctl numbers` does. ⚠ Until v6.6.6 the lexer matched these names as
byte PREFIXES with no boundary, so those same lines did NOT compile — `#ioctl numbers` lexed as
`#io` + the identifier `ctl` and reported `expected '=', got identifier 'numbers'`, pointing at
the comment's second word. That was a lexer defect written up as if it were a language rule
("put a space after the `#`"); it is fixed, and the boundary is the rule.

**Preprocessor directive names end at a word boundary too (v6.6.6).** `#endif`, `#endplat`,
`#host_only`, `#derive(…)` and `#@srcline` are matched with the same rule, so `#endifoo note`
and `#host_onlyish note` are comments. Until 6.6.6 they were byte prefixes, and there the
failure was **silent rather than a diagnostic**: `#endifoo note` inside a skipped `#ifdef`
CLOSED the conditional, so the code that should have been skipped was compiled into the binary;
`#derive(Serialize)x note` armed the derive machinery and changed the emitted bytes;
`#host_onlyish note` in an included module refused every `--target=…-bare-metal-elf` build; and
`#@srclinex 10` shifted every diagnostic in the file by one line. `#else` carried the rule from
the start, which is why it was the only one that behaved.

**Three attribute names also end at `(`**: `#deprecated("…")` and `#pe_import(…)`, where the parenthesis
is part of the syntax, and `#assert(…)`, where it is NOT — the compiler rejects that form with
`#assert: expected constant expression`, and it stays a loud error on purpose rather than
becoming a silent comment, because a dropped compile-time assertion is worth more noise than a
rare prose comment opening `#assert(`. For the other seven, `#pure(ly) awesome` and friends are
comments. (v6.6.6's first cut took `(` as a boundary for all ten, which left `#io(fd) reads a
byte` failing with `unexpected '('` — the filed defect, one input class narrower.)

## Ref Directive

```
#ref "config.toml"
# Reads a TOML file and emits key/value pairs as global variables
# Processed during PP_REF_PASS before main compilation
```

The quoted filename is required, and it must follow `#ref ` immediately. A line that merely
*begins* `#ref ` and has no quote is an ordinary comment — `#ref counting is fine` is prose and
compiles to the same bytes as `# ref counting is fine`. ⚠ Until v6.6.6 it was not: the pass
consumed the five bytes `#ref ` the moment the line matched and only then looked for the quote,
so the comment reached the lexer as `counting is fine` and was parsed as code. It was invisible
unless the same file also held a real `#ref "x"` (only that triggers the pass's copy-back), and
then the comment's neighbour failed with an error naming a word from the middle of the comment.
`include ` had the same shape and now reports `include expects a quoted filename` instead of
passing mangled bytes on.

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

fn use_res(): i64 {
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

`f` is any call spelling: an explicit generic `g<T>(..)` and a method `p.m(..)` are refused,
destructured and propagated with `?` exactly like `f(..)` (v6.6.16 — before that, `?` on them
crashed and a single bind dropped the payload silently).

**Every path of a pair-returning fn returns a variant.** In a fn that returns `Ok(x)` /
`Some(v)` on one path, a `return rv;`, `return 0;` or `return wrapper();` on another hands the
caller that value AS ITS TAG and a stale payload, so it is warned (*"returns a `: stack` pair on
another path but a SINGLE value here"*, v6.6.0). Any constructor of the enum is a whole value,
including a **nullary** one: `return None();` (or `return None;`) beside `return Some(v);` is
correct and silent (v6.6.9; it used to warn and suggest `Err`). A fn that returns a raw status on
one path still sees the warning even when its callers only sign-test that path, and it is still a
defect: vani's `vani_drain` / `vani_state` were kept that way through vani 1.2.7, and a two-value
bind read a device in state SETUP as `Err` (fixed in vani 1.2.8). Read the callers before acting
on it: they change with the return.

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

| helper | v6.6.x | note |
|---|---|---|
| `is_ok` / `is_err_result` / `is_none` / `is_some` / `is_left` / `is_right` | `(t)` | arity unchanged — argument 1 receives the tag. ⚠ **NOT "unchanged"** — see the warning below |
| `is_tag` | `(t, expected)` | arity unchanged; body rewritten. Same warning |
| `tag` | **DELETED (v6.6.2)** | v6.6.0 kept the name and made it the identity; on a BOX that silently returned the pointer. Retired rather than redefined — boxed reads use `boxed_tag` |
| `result_unwrap` / `err_code_of` / `result_print` / `unwrap` | `(t, v)` | **was 1 argument** |
| `result_unwrap_or` / `unwrap_or` | `(t, v, fallback)` | **was 2 arguments** |
| `ok_via` / `err_via` | `(a, v)` | unchanged signature; allocates nothing now, and the allocator argument is ignored |
| `payload` | **DELETED** | stays deleted deliberately — see below |
| `tagged_new` | **RESTORED (v6.6.2)** | in `lib/boxed.cyr`; it builds the same 16-byte box it always did, so every call site is correct as written |

⛔ **THE `is_*` ROW SAYS "ARITY UNCHANGED", NOT "SAFE", AND THE DIFFERENCE COSTS REAL BUGS.**
This table read *"unchanged"* for that whole row until v6.6.2, and it was wrong. Their bodies were
rewritten from `load64(box)` to a direct register compare. On a value-form tag that is correct; on
a **raw box** every one of them answers wrongly, compiling clean and exiting 0:

```text
tag(box)           = 140399372926976   # the POINTER, not the tag (fn now deleted)
is_tag(box, MSome) = 0                 # the value IS MSome
is_some(box) = 0   is_none(box) = 0    # simultaneously not-Some and not-None
is_ok(box)   = 0                       # `if (is_ok(r))` takes the error branch, always
```

**An arity change is loud** — `'f' expects 2 arguments, got 1` is a hard error. A same-arity
redefinition is **silent**, and it is the one class no consumer build can catch. If you hold a box
built by `tagged_new`, read it with `boxed_tag` / `boxed_payload` / `boxed_is` and nothing else.

⛔ **`payload()` is not coming back, and that is a choice rather than an impossibility.** For the
value form it is forced: rdx never reaches a parameter. The v6.6.0 note generalised that to "no
1-argument replacement", which is **false for a box** — `load64(p + 8)` works and is exactly what
`boxed_payload` is. It stays deleted because consumers use that one spelling on *both* classes, so
restoring it would make stale `Result` reads compile and dereference a tag (0 or 1) as a pointer:
a named compile error traded for a SIGSEGV.

⚠ **The example below used to be the pre-flip one** — five compile errors, two lines under the
table that announces the change. It is now the working form, and
`tests/gates/toolchain/guide_examples_compile.sh` compiles every fenced block in this file so it
cannot rot back.

```
include "lib/tagged.cyr"          # Option / Either (+ lib/boxed.cyr transitively)
# or:
include "lib/result.cyr"          # Result alone

# ⭐ BIND BOTH HALVES. A single-var bind of a pair is a hard error naming the fix.
var opt_t, opt_v = Some(42);
if (is_some(opt_t) == 1) {
    var v = unwrap(opt_t, opt_v);            # = 42
}
var v2 = unwrap_or(opt_t, opt_v, 0);         # 42 if Some, the fallback if None

var r_t, r_v = Ok(99);
if (is_ok(r_t) == 1) {
    var got = result_unwrap(r_t, r_v);       # = 99
}
```

For a hand-rolled tagged union with more than two variants — the shape `Result` cannot model, and
what `tagged_new` is actually for — use the boxed primitives, which survive a struct field, a vec
element and a one-argument boundary:

```
include "lib/boxed.cyr"

enum Kind { KText(); KBin(); KImage(); }

fn block_kind(b) { return boxed_tag(b); }    # a box fits in ONE argument; a pair does not

var b = tagged_new(KImage, 4242);            # or boxed_new — same constructor
var k = block_kind(b);                       # KImage
var p = boxed_payload(b);                    # 4242
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
fn run() {                           # inside a function …
    var add = |a, b| a + b;          # body is an expression …
    var dbl = |x| { var y = x * 2; return y; };   # … or a { block }
    var ans = || 42;                 # zero-param thunk (`||`)
    var r = callptr(add, 40, 2);     # 42  (or fncall2(add, 40, 2))
}

var g_dbl = |x| { var y = x * 2; return y; };     # … or as a top-level `var`
```

The body may be a single expression or a `{ … }` block (with `return`).

A closure literal is also a legal top-level initializer, including the `{ block }`
form. Call it with `fncallN` or `callptr`, inside a function or at top level: since
6.6.16 an indirect call in top-level code brings its own small stack frame, so it
dispatches a capturing closure exactly as it does inside a function. ⚠ **Before 6.6.16
a top-level `fncallN` on a capturing closure that a function had built and returned
(or stored in a global, or passed through memory) crashed** (SIGSEGV; 0xC0000005 on
Windows; on the cx target every top-level `fncallN` returned 0), and a top-level
`callptr` did not compile. The usual workaround, calling it from inside a function,
is no longer needed. Pinned by `tests/tcyr/crossos/closure_escape_dispatch.tcyr` and
`tests/gates/codegen/toplevel_indirect_call.sh`. ⚠ **Before 6.6.6 a block-bodied closure in
a top-level `var` declared before the first top-level statement silently dropped the
rest of the program**: the declaration was skipped to its first `;`, which the
closure body contains, so both parser passes stopped inside the body and nothing
below it was compiled. Nothing warned, and the program exited with the closure's
address. Fixed in 6.6.6; pinned by `tests/tcyr/crossos/toplevel_block_closure.tcyr`.

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
use `callptr`, which has no arity ladder. `fncallN` and `callptr` dispatch
closures the same way at **top level** as inside a function (since 6.6.16; before
that a top-level `fncallN` on a capturing closure crashed).

**Nested closures capture through every enclosing level (6.6.17).** A closure written inside
another closure may read the inner closure's own locals, the outer closure's params and
locals, and the enclosing function's locals and params — at any depth. Each level captures by
value at its own construction: the outer closure captures what any closure nested in it reads,
and the inner closure copies that captured value out of the outer one's environment when it is
built.

```
fn adder(a): i64 {
    var f = |x| |y| a + x + y;       # curried: the inner closure reads `a` and `x`
    return callptr(callptr(f, 10), 2);   # a + 12
}
```

⚠ Before 6.6.17 this did not compile: the inner closure's reference to an enclosing
function's variable was refused `undefined variable`, and an outer capturing closure that merely
contained a nested closure lost its own captures after it (refused the same way). This section
used to call it "captured closures are flat", which was a compiler limit, not a rule. Pinned by
`tests/tcyr/crossos/closure_nested_capture.tcyr`.

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
the concrete type is **inferred** from the argument in the parameter `T` types —
the first such parameter, wherever it sits (`fn g<T>(n, p: T)` infers `T` from
`g(2, p)`'s `p`). A struct argument — a struct local or by-value struct
parameter, a struct global, a call returning a struct — binds `T` to that struct
on every call path (an expression, `var r = g(p)`, `r = g(p);`, `b.v = g(p);`,
`return g(p);`, an argument, a struct receive), exactly as the explicit
`g<Pt>(p)` does (6.6.10; before that only an inlined body inferred a struct, and
every other path ran the i64 base). Only a WHOLE argument binds `T`: `g(p.y)`,
`g(p.x + p.y)` and `g(p + 1)` infer `i64`, and so does a `pp: *Pt` pointer
parameter (a pointer, like a `var q: *Pt` local). Any other argument infers
`i64`, or the width a scalar-returning call declares.

Type arguments may be **inferred** from the call (`add(1, 2)`) or written
**explicitly** (`add<i64>(x)`, `add<i32>(x)`). Inside a generic body a type
parameter may be **forwarded** — `fn outer<T>(p: T) { return inner<T>(p); }` calls
`inner`'s instance for whatever `T` is bound to (v6.6.8; before that `T` read as
"no type" and the call silently hit the i64 base, returning 0 for a struct `T`). A
type argument is a struct, `i8`/`i16`/`i32`/`i64`, `f64`, or a type parameter in
scope — the same names a return type accepts; anything else (an undeclared name, a
variable, `u8`..`u64`, `bool`, `ptr`, `f32`, an enum name) is a compile error naming
it (v6.6.8; an enum's values are i64, so write `i64`).

**Monomorphization.** Cyrius is i64-everywhere (ADR-002), so a generic
definition's base *is* its i64 instantiation: the body is emitted once with
`T → i64`, and i64-typed calls are ordinary direct calls to it. A non-i64 type
argument (`add<i32>`, `Box<Point>`) is **monomorphized on demand**: the
specialized instance `add$i32` / `Box$Point` is emitted **once** (deduped — a
second `add<i32>` call reuses it) and called normally. There is no runtime type
dispatch — `T` is resolved entirely at compile time.

**A generic that uses `T` as a struct has no i64 instance.** When a `T`-typed
value — a parameter or a `var q: T` local — is used as a struct (`p.y`), there is
no valid i64 form, so the base is a dead stub, and any use that would reach it is
a compile error naming the fn: a scalar call (`g(5)`, `g<i64>(5)`, `g<i32>(5)`,
in any position, tail included), `&g`, and a generic that FORWARDS its own `T` to
such a generic (`fn outer<T>(p: T) { return g(p); }` makes `outer(5)` an error
too, whichever order the two are defined in). Call it with a struct argument or a
struct type argument (6.6.10; before that each of these compiled and returned 0).

```
struct Pt { x; y; }
fn sum<T>(p: T): i64 { return p.x + p.y; }
fn run(): i64 {
    var p: Pt; p.x = 40; p.y = 2;
    return sum(p);               # 42 — T inferred as Pt
    # sum(5) / sum<i64>(5) / &sum — error: 'sum' has no i64 (or other scalar) instance
}
```

A signature may name a generic struct instance: `fn mk<T>(x: T): Box<T>` returns
`Box<Pt>` from its `Pt` instance, and a plain `fn f(r: Box<Pt>): Box<Pt>` takes and
returns the instance — `return mk(p);` and `return mk<Pt>(p);` included, in the
register-pair (9-16 byte) and retptr classes alike (6.6.10; before that such a
type was sized as the base `Box`, where `v: T` is an i64 — `r.v.x` failed to
parse). As for a `var`, an all-`i64` argument list names the base struct itself.
A `: T` return in an instance whose `T` is a struct returns that struct by value,
as a `: Pt` fn does (`fn id<T>(x: T): T` — `var q: Pt = id(p)`; 6.6.10, it used to
return the struct's address); `Str` keeps its heap-handle return.

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

A **literal** of a generic struct names its type arguments the same way — `Box<Point> { p, 5 }`,
`Box<Point> { 1, 2, 5 }`, `Pair<i32> { 40, 2 }` — in a fn, in the leading declaration block and
after the first top-level statement (6.6.12; before it every one was
`undefined variable 'Box'`). It is the same instance an annotation names, so
`var b: Box<Point> = Box<i64> { 1, 2 };` is a compile error, and `Box { .. }` with no
arguments is the base (all-i64) struct.

A **global** takes the instance too, wherever it is declared: `var G: W1<Pt> =
alloc(16);` ahead of the first top-level statement reads and writes `G.v.x` and passes
`G` where a `W1<Pt>` is expected (6.6.11; before it a global declared in that leading
block was typed as the base `W1`, where `v: T` is an i64 — `G.v.x` failed to parse and
`w1s(G)` read the wrong storage). A global declared after a statement already did.

**Type arguments nest (6.6.17)** wherever a type is written — `var x: Vec<Box<i64>>`,
`var b: Box<Vec<i64>>`, `var z: Box<Box<i32>>`, a parameter, a global, a `Vec<Box<i64>>`
field, `idv<Vec<i64>>(x)`, and a multi-value return element `(Box<i64>, i64)` — with the
lexer's `>>` closing two lists. `sizeof(T<..>)` is the size of the instance the same
annotation declares — what `var b: Box<i32>` occupies (4 for the `Box` above, 16 for
`Pair<i64>`); `sizeof(Vec<i64>)` is a handle's 8. Before 6.6.17 `Vec<Box<i64>>` ran to the end of the file
(`expected '=', got end of file`), `Box<Vec<i64>>` and a `Vec<Box<..>>` field were refused,
and `sizeof(Box<i64>)` and `(Box<i64>, i64)` were `expected ')', got '<'`.

**Status & limits (6.6.10).** Generic functions and structs are supported over
i64, narrow scalars (`i32`/`i16`/`i8`), and struct type arguments, inferred or
explicit, with any body (a small straight-line body is inlined at its call sites;
anything else is an ordinary call). At most two type parameters are recorded. A
struct type argument is supported on a generic with ONE type parameter: a struct
beside a second type argument — explicit (`g<Pt, i64>`) or inferred (`g(p, q)`
with two structs, or a struct and a scalar) — is a compile error on every call
path, struct receives and assignments included (6.6.10 for the inferred form; it
ran the i64 base). Enum generic params (`<T, E>`) remain syntactically accepted
but type-erased.

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
heap Future and returns its pointer; the body is emitted as a hidden `f$impl`.
The Future reuses the same heap construction as a closure env. Requires
`include "lib/alloc.cyr"` (the Future is heap-allocated), `lib/fnptr.cyr` and
`lib/async.cyr` (for `future_force`); `alloc_init()` must run before the first
`async`-fn call. The constructor and `lib/async.cyr` ship in lockstep: a program
built by one release needs that release's `lib/async.cyr`.

**Force-once.** An `async fn` whose body has no `await` builds a plain Future
`[ &f$impl, argc|256, args…, done, value ]`. `await fut` lowers to
`future_force(fut)`: the first force calls the impl with the bundled args (via
`fncallN`) and keeps the value; every later force returns that value and runs
nothing (6.6.10 — before, every `await` of the same Future re-ran the body). A
Future you build by hand, `[ fp, argc, args… ]` with no marker, is re-run on each
force.

**Enabling it.** `async`/`await` are opt-in: set `CYRIUS_ASYNC=1` in the
compiler's environment (`CYRIUS_ASYNC=1 cyrius build …` passes it on). There is
no command-line flag. A default build rejects them with a clear error, so
default codegen, which has no async, stays byte-identical.

**Arity.** A plain `async fn` takes 0–8 parameters. One with 9 or more is refused
at its declaration, naming the fn (6.6.10; it used to compile and exit 70 at its
first force). A coroutine (below) takes any number.

**Coroutines.** An `async fn` that `await`s in its own body is a **coroutine**
(v6.5.69) — on x86_64 Linux, x86_64 macOS and Windows (PE) only; the aarch64 and
cx backends refuse it at compile time, naming the backend. It is a stackless
state machine: its locals live in a heap frame, each force resumes it at the
`await` where it last stopped and runs to the next `await` (answering 0) or to
its end. Once its body has returned — by `return`, or by falling off its end,
which completes it with 0 and runs its defers (6.6.10; it used to hang) —
forcing it again returns the same value and runs nothing, neither body nor
`defer` (v6.6.8). A `return f(x);` in its body is an ordinary call, never a tail
call.

**What `await e` yields inside a coroutine** (6.6.10; it used to be the suspend
index — `var s = await five();` three times returned 123 for 555). `e` is
evaluated, the coroutine suspends, and at the next force:

- if `e` is a call to an `async fn`, or a bare variable (a Future, as `await`'s
  operand is everywhere else), it is forced and `await` yields its value. While
  it is a coroutine Future that has not finished, the outer coroutine suspends
  again at the same point, so each force of the outer one drives the inner one a
  step until it completes;
- anything else — a call to an ordinary fn, such as the park idiom
  `await async_wait_fd(rt, fd)` — yields that value.

The test is on the operand's **shape**, and parentheses do not change it:
`await (inner(a))` forces like `await inner(a)`. A Future reached any other way
— a field (`await s.fut`), `vec_get` (`await vec_get(futs, i)`), an index — is
"anything else" and yields the Future's pointer; bind it to a variable first
(`var F = vec_get(futs, i); var v = await F;`).

`await` may sit anywhere in an expression: `total = total + await f`,
`add(1000, await g())`, `s += await g()`, `store64(p + 8, await g())`. Whatever
the expression had already evaluated before the `await` — a left operand,
earlier call arguments, an address — is kept in the coroutine frame across the
suspend (6.6.10; it used to be lost, so `b + await five()` gave 5 and the
`store64` form crashed).

**Under the reactor.** `async_spawn_future(rt, co(..))` + `async_run(rt)` (or
`task_join(rt, h)`) drives a coroutine to its value. A coroutine that PARKS
before it suspends (`await async_wait_fd(rt, fd)` / `async_wait_writable`)
sleeps until its fd is ready and resumes where it stopped, interleaved with the
others. A coroutine whose `await` did not park — an `await` of a Future, or of a
call that does not park — stays runnable and is resumed on the reactor's next
step; while one does, the reactor still polls (without blocking) for the fds,
timers and deadline sentinels other tasks are parked on, so neither side starves.
(Until 6.6.11 every backend finished such a coroutine with the 0 its suspend
returned, and this guide told you to force it yourself with `future_force`.)

**Other limits.** `async` generic fns are not yet supported, nor is a value-form vector
PARAMETER (`async fn f(v: f64v2)`) — an `async fn` captures each argument as one
8-byte value, so since v6.6.6 that is a compile error naming the parameter; pass
a pointer to the vector instead (before v6.6.6 it compiled and computed with the
wrong vector). Nor is a **struct over 8 bytes passed by value**
(`async fn f(p: P3)`): its body runs when the Future is forced, so the copy a
by-value parameter makes on entry would read the caller's struct LATE. Before
v6.6.16 the body read and wrote the caller's struct itself at force time —
`f(p)` with `p.x == 3`, then `p.x = 10`, then `await` gave 11 and left `p.x` 11.
Since v6.6.16 it is a compile error naming the parameter and the spelling to
use, `p: *P3`; a struct of 8 bytes or less and a `p: *P3` parameter still work.
A **by-value struct RETURN** over 8 bytes is likewise unsupported and, since
v6.6.6, a compile error naming the fn: a Future carries one i64, so a
>16 B return (hidden retptr) came back as garbage and a 9–16 B one (rax:rdx) lost
its high half — both silently, exit 0, before v6.6.6. A struct of 8 bytes or less
IS one i64 and works, as does `Str` (a heap handle); for anything wider, return a
pointer. A **value-form vector RETURN** (`async fn f(): f64v2`) is refused for the
same reason and in the same words — a vector travels in XMM/V, or by pointer on
Win64, never in rax — so it too yielded 0 with no diagnostic before v6.6.6. Every
16-byte and 32-byte class is covered, `f64v2`/`f32v4`/`f64v4`/`i32v4` alike;
return a pointer to the vector.

## Global Initializers

Variables can be declared among function definitions:

```
fn get_value() { return global_var; }
var global_var = 42;             # Visible to functions above
var r = get_value();             # r = 42
```

**Deferred initializers — no count cap (6.6.9).** A top-level `var` is baked into
the image when its initializer folds to a **nonzero** integer constant (`var x = 42;`,
`var m = 1 << 4;`, `var n = -1;`), and so is every array initializer
`var b: T[N] = { … };` (6.6.16 — see *Array initializers* above; it was a run of byte
stores at startup). Every other top-level `var` — a call
(`var t = alloc(1024);`), an identifier or other non-constant expression, `= 0`, a
string literal, a top-level destructure
`var a, b = f();` — is a *deferred initializer*: its right-hand side runs once at
startup, in declaration order. (`= 0` is deferred only
because the static path reserves 0 for "no value"; the store is redundant and harmless.)
An uninitialized top-level `var x;` is an error — write `var x = 0;`.

**An initializer that names an enum constant is a constant too (6.6.16).** `var x = A;`,
`var x = E.A;`, `var x = A + 1;`, `var x: u8 = A;` — any initializer that folds once enum
constants are known, the enum declared above or below — is baked into the image like
`var x = 42;`. The name resolves exactly as a read of it does: if a later global hides the
enum constant (`enum E { A = 3; } var x = A; var A = 9;`), `x` is 9. So is a struct literal
whose every field is a constant (`var p = Pt { A, 0x66 };`, nested struct fields included, a
float literal in a float field); a field that is a call, a name, a string or a `Str` leaves
the whole literal to the startup store. The startup store still runs (the code does not
change), so the visible difference is the value before it: an initializer that runs earlier —
`var y = g();` above `var x = A;`, `g` reading `x` — now sees it, as it already saw a literal.

**Kernel builds.** An x86 `kernel;` (or `CYRIUS_KERNEL=1`) build runs the deferred
initializers **after** the top-level program — its top-level asm (the multiboot shim) must run
first. A kernel whose program never returns never runs them, and the program reads what the
image holds: the value, for everything baked above; 0 for the rest. The compiler names each
declaration it leaves to that late replay, once:

```
# in a `kernel;` build:
fn hostname() { return "agnos"; }
var host = hostname();     # warning: in a kernel build the initializer of 'host' runs after
                           # the top-level program: the program does not see its value, ...
```

It is a warning, not an error, and it is only issued where it is true: not by a host build,
not by an aarch64 kernel build (it runs the initializers before the program), and not by an
EFI application that defines `efi_main` (`CYRIUS_TARGET_EFI=1`: they run before `efi_main` is
called). The fix is a constant, an assignment in the program, or a function that returns the
value (a string literal inside a fn is an address baked into its code).

Until 6.6.8 deferred initializers were capped at **4096 per compilation unit**
(`too many initialized globals (max 4096)`), and this section documented the counting
rule wrongly: `= -1` never counted, while `= 0` and string literals did. Since 6.6.9
there is no cap; the table grows. Enum members (`enum E { A = 0; B = 1; }`) are
const-folded at parse time and never were deferred. The limit that remains is the var
table itself — 1,048,576 globals, enum members and top-level arrays together.

Compile time is linear in the number of globals (6.6.9): 20,000 globals compile in a
fraction of a second, where they took about five seconds before.

**Declaring a global twice (6.6.6).** Before the first top-level statement — where
modules declare their globals — a name declared twice is **one global, and the last
definition wins**, exactly as a duplicate `fn` resolves:

```
var a = 5;
var b = a;        # b == 7: every read sees the last definition, even one written earlier
var a = 7;        # warning: duplicate symbol 'a' redefined with conflicting value (last definition wins)
```

- A redeclaration whose initializer is a compile-time **constant** (an integer
  literal or a foldable integer expression, zero included) is the global's value
  **from program start**. An earlier *computed* initializer of the same name
  (`var a = f();`) still runs — its side effects happen — but its result is
  discarded.
- A **computed** redeclaration runs in declaration order like any deferred
  initializer: `var a = 5; var b = a; var a = f();` gives `b == 5` and `a == f()`.
- Two `= { .. }` lists for one array both apply, in order: the later list's
  elements overwrite the earlier one's, and the bytes it does not list keep the
  earlier values. A constant **scalar** redeclaration after an array list wins
  whole, as above.
- A list is a constant initializer, so the first rule covers it too (6.6.16): over
  an earlier `= 0` or computed initializer of the name it is the value from
  program start — `var a = f(); var a[1] = {0, 4};` runs `f()` and reads `0x400`
  — and over an earlier scalar **constant** it keeps the bytes it does not list
  (`var a = 0x0506; var a[1] = {9};` reads `0x0509`).
- A redeclaration that changes the **type or size** (`var a = 5;` then
  `var a: i32 = 7;`, `var q[8];` then `var q[16];`) is an error naming the global —
  one of the two would read the other's storage in the wrong shape. Same rule as a
  duplicate `fn` that disagrees about arity.
- A same-value redeclaration is silent; that is the usual way two files, or an
  `#ifdef` arm, end up declaring one global.
- A `var` over an **enum constant** of the same name (only an integer literal is
  allowed there) is the last definition too: `enum E { K = 5; } var b = K; var K = 7;`
  gives `b == 7`, and every later `K` is the var.
- In a `private` file, a `public var x` and a later private `var x` are two globals
  (visibility is part of a global's identity), but a read between them still sees
  the later, constant definition — never 0.

After the first top-level statement a `var` is a statement, and redeclaring a name
there starts a **new** variable for the code after it (a fresh buffer of the new
size, for an array); code before it — including fns defined earlier — keeps the
earlier one.

⚠ Before 6.6.6 the redeclaration was given a second storage slot, and the first
declaration's value landed in the slot nothing read: `var a = 5; var b = a; var a = 5;`
set `b` to **0**, silently, and with `var a = 7` it was still 0 under the warning above.

### A top-level block scopes its `var`s (6.6.6)

A `var` declared inside a **top-level block** — the body of an `if` / `elif` / `else` /
`while` / `for` / `switch` written outside every function — belongs to that block and is
gone at its `}`, exactly like a `var` in a function body:

```
var limit = 1;
var go = 0;
go = 1;

if (go == 1) {
    var limit = 2;      # a NEW variable, scoped to this block
    var t = 5;          # ...and so is this one
}                       # both end here

# syscall(60, t);       # error: undefined variable 't'
syscall(60, limit);     # 1 — the outer global was never touched
```

Assigning to an **outer** global from inside a block is unchanged; only *declarations*
are scoped. To use a value after the block, declare it above the block and assign inside:

```
var t = 0;
if (go == 1) { t = 5; }   # assignment, not a declaration
syscall(60, t);           # 5
```

Reading, writing or taking the address of a block-scoped name after its block is a
compile error that names the variable and says where to declare it instead:

```
error:<source>:5:14: undefined variable 't' (missing include or enum?)
    syscall(60, t);
                 ^
note: 't' was declared inside a top-level block and goes out of scope at its '}'
      (since 6.6.6 a top-level block scopes its `var`s like a fn body does)
      declare it at top level, before the block, to use it after the block
```

The note accompanies **every** form of the reference — a plain read, an assignment,
`&t`, an index `t[0]`, and a struct-field read or write (`t.a`, `t.a = 1`).

⚠ **This is a deliberate language change, made by the maintainer on 2026-09-19.** Before
6.6.6 a top-level block's `var` registered a *global*: the name stayed visible after the
block, and an inner declaration of an outer name **overwrote the outer global** (measured
2 where 1 is correct in the example above). One spelling had two scoping rules depending
on whether it sat inside a `fn`. The compile error above is the intended, loud outcome for
code that relied on the leak — a survey of ~12,600 `.cyr` sources across the ecosystem at
the time of the change found no file that did. Pinned by
`tests/tcyr/crossos/toplevel_block_var_scope.tcyr` and
`tests/gates/frontend/toplevel_block_var_scope.sh`.

### A top-level `for x in …` (6.6.8)

`for i in a..b { }` and `for x in v { }` work at top level. The loop variable is scoped to
the loop, like a block `var`; using it after the loop is an error with its own note:

```
note: 'i' is a `for ... in` loop variable and goes out of scope at the end of its loop
      to use a value after the loop, assign it to a variable declared before the loop
```

Before 6.6.8 every top-level for-in was broken — the loop variable was given a function
frame slot, and top-level code has no frame: it segfaulted on Linux (x86_64 and aarch64),
page-faulted on Windows, wrote into the loader's frame on arm64 macOS, and any read of the
variable was `undefined variable`.

⚠ **A closure made inside a top-level loop reads the loop variable's current value**, not
the value when the closure was made — the same rule as a closure over a top-level block
`var`. Inside a function the closure captures by value:

```
var f0 = 0;
for i in 0..3 { if (i == 0) { f0 = |x| x + i; } }
fncall1(f0, 10);   # 13 at top level (i is 3 by now); 10 for the same code in a fn
```

Pinned by `tests/tcyr/crossos/toplevel_for_in.tcyr` and `tests/gates/frontend/toplevel_for_in.sh`.

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
                          # mutex (three-state futex), MPMC channels (chan_send/recv + try_ variants; blocking where `CHAN_BLOCKING == 1`)
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
(`DeleteFileW`, `MoveFileExW`, `RemoveDirectoryW` since v6.6.6, `FlushFileBuffers` for `xfsync`
since v6.6.7, …) behind the same names. `cyrlint` flags a raw `sys_open`
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
    asm { out dx, al; }            # mnemonic
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
- At most 1,048,576 globals, enum members and top-level arrays per compilation unit
  (the var table). The separate 4096 cap on deferred initializers is gone since 6.6.9
  — see **Global Initializers**
- **79** builtin/intrinsic names (re-derived at 6.6.13; this bullet still said 67, the v6.4.77
  count) plus the statement keywords are reserved and cannot be used
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
`CYRIUS_TARGET_MACOS`, `CYRIUS_TARGET_AGNOS` or `CYRIUS_TARGET_CX` per build.
(This line listed only the first three until v6.6.6. `CYRIUS_TARGET_AGNOS` has
been predefined since v6.0.48 and is used throughout `lib/`; `CYRIUS_TARGET_CX`
is new in v6.6.6 — before it, the cx driver predefined NOTHING, so every
per-target `#ifdef` arm in the stdlib matched nothing on cx and those modules
compiled to *nothing*, which is why `include "lib/assert.cyr"` did not compile
for the cx target at all.)

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
- `exec_capture_status(args, buf, buflen, st)` — capture plus the child's exit code in `st[0]` (6.6.7)
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

Mutexes are preemptive-safe (block contending threads). Since 6.6.16 the channel
blocks exactly as on Linux (`CHAN_BLOCKING = 1`): `chan_recv` waits for a value and
`chan_send` waits for room, each waiter parked on an I/O completion port taken from a
small process-wide pool (no kernel handle is held per channel).

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

The POSIX flag word is decoded into CreateFileW's `dwDesiredAccess` /
`dwCreationDisposition` pair (v6.6.6 — before that only `O_CREAT` and `O_EXCL`
were read, so `O_TRUNC` silently did not truncate and `O_APPEND` silently
overwrote from offset 0):

| flags | Win32 |
|---|---|
| `O_RDONLY` / `O_WRONLY` / `O_RDWR` | `GENERIC_READ` / `GENERIC_WRITE` / both |
| `O_APPEND` | the write bit becomes `FILE_APPEND_DATA` — a real per-write append |
| `O_CREAT｜O_EXCL` | `CREATE_NEW` (fails if the file exists) |
| `O_CREAT｜O_TRUNC` | `CREATE_ALWAYS` |
| `O_TRUNC` alone | `TRUNCATE_EXISTING` |
| `O_CREAT` alone | `OPEN_ALWAYS` |
| neither | `OPEN_EXISTING` |

The two words are not independent: Win32 **refuses** `TRUNCATE_EXISTING` unless
`dwDesiredAccess` carries `GENERIC_WRITE` (`ERROR_INVALID_PARAMETER` — `FILE_WRITE_DATA`
and `FILE_APPEND_DATA` do *not* satisfy it), so the translation adds that bit whenever it
selects that disposition. Two residual divergences follow, both harmless in practice but
worth knowing: on Windows a handle from `O_RDONLY|O_TRUNC` can also be written (Linux
gives `EBADF`), and `O_TRUNC|O_APPEND` *without* `O_CREAT` writes at the file pointer
rather than at EOF (with `O_CREAT` the disposition is `CREATE_ALWAYS`, which needs no
extra access, so the real append survives).

`O_NOFOLLOW`, `O_DIRECTORY` and `O_CREAT|O_EXCL` have their POSIX meaning on Windows since
v6.6.9 — asserted by the same `tests/tcyr/crossos/open_flags_per_target.tcyr` rows on real
Windows, Linux, macOS and aarch64:

| Flags | Linux | Windows (v6.6.9) |
|---|---|---|
| `O_CREAT\|O_EXCL` on a name that exists — even a **dangling** symlink | -17 | refused (`file_open` -1, `file_create_exclusive` -17); the link's target is never created |
| `O_NOFOLLOW` on a symlink or junction (to a file or a directory) | -40 (-62 macOS) | -40; the target is never opened or truncated |
| `O_NOFOLLOW` with write access, `O_CREAT` or `O_TRUNC`, on a directory | -21 | -21 |
| `O_NOFOLLOW` on any other reparse point (cloud placeholder, dedup) | — | opens the file normally (the reopen must be the same file) |
| `O_DIRECTORY` on a directory / a file | fd / -20 | handle / -20 |
| `O_DIRECTORY` with write access, `O_CREAT` or `O_TRUNC`, on a directory | -21 | -21 |
| `O_DIRECTORY\|O_NOFOLLOW` on a link to a directory | -20 | -20 (macOS too — the unfollowed link is not a directory) |

How: CreateFileW resolves a final reparse point for **every** disposition, so the attribute
word carries `FILE_FLAG_OPEN_REPARSE_POINT` for `O_NOFOLLOW` and for `CREATE_NEW` (which never
opens an existing object, so the flag only stops it following one), and
`FILE_FLAG_BACKUP_SEMANTICS` for `O_DIRECTORY`. `sys_open` then asks the **opened handle**
(`GetFileInformationByHandleEx`) what it is — no check-then-open window — and an
`O_NOFOLLOW|O_TRUNC` open is truncated only after that check. A junction or a link to a
directory is a directory object, which CreateFileW refuses before there is a handle to ask; a
failed `O_NOFOLLOW` open therefore asks the name why, with a read-only probe that never follows,
truncates or creates, and only the errno comes from it. The one reopen by name (a non-surrogate
reparse point, opened normally so its filter presents the file) is compared with the verified
handle by file id and refused if the name changed in between. The refusals live in `sys_open`,
which every stdlib open goes through; a raw `syscall(2, p, O_NOFOLLOW, 0)` still never follows
a link, but hands back the link's own handle instead of -40.

⚠ One divergence remains, fail-closed: a plain `open()` of a directory (no `O_DIRECTORY`) is -1
on Windows, where Linux returns a read fd. `FILE_FLAG_BACKUP_SEMANTICS` is set **only** for
`O_DIRECTORY` — set always, it would let `O_WRONLY` open a directory.

Before v6.6.9 all three flags were accepted and ignored: `O_CREAT|O_EXCL` over a dangling
symlink **created the symlink's target** (with or without `O_NOFOLLOW` — sigil's keyfile,
`file_create_exclusive`, the CLI's temp creates), `O_NOFOLLOW|O_TRUNC` on a link truncated the
file it named, and `O_DIRECTORY` refused a directory while opening a file. `is_symlink` was 0 for
everything, so `dir_walk` descended junctions. `xsymlink` (`CreateSymbolicLinkW`, needing
Developer Mode or an elevated process), `sys_ftruncate` and `sys_truncate` (`SetEndOfFile`) are
real on Windows since the same release.

**Durability** (v6.6.7)

`fsync` and `fdatasync` — `xfsync(fd)`, or a raw `syscall(74, fd)` / `syscall(75, fd)` — call
`FlushFileBuffers` on Windows; there is one flush for data and metadata, so both numbers do the
same thing. A number held in a `var` flushes too since v6.6.9 (before it, the runtime switch a
`var` number goes through did not carry 74/75 and returned -38 with no warning). A failure is -1. `file_rename` passes
`MOVEFILE_WRITE_THROUGH`, so `file_write_atomic`'s write → flush → rename is durable as well as
atomic.

Before v6.6.7 `xfsync` returned 0 on Windows **without flushing, for any fd** (even one that did not
exist), a raw 74/75 returned -38, and the rename was not write-through. Code that checked for
durability on Windows was told it had it.

> ⚠ One divergence from POSIX: Windows will not flush a handle opened **without write access**.
> `xfsync` of an `O_RDONLY` fd is 0 on Linux and macOS and **-1 on Windows**. An `O_APPEND` handle
> (whose Windows access is `FILE_APPEND_DATA`, not `GENERIC_WRITE`) is expected to flush — the NT
> flush accepts either write right — and `tests/tcyr/crossos/fsync_flushes.tcyr` checks exactly
> that, and the `O_RDONLY` refusal, on real Windows at every release.

**Directory Enumeration** (v6.1.18+)
- `dir_list(path)` → `vec` of `Str` filenames
- `is_dir(path)` → 1 (directory) or 0 (not found / file)
- `dir_walk(path, results)` — recursive enumeration (appends file paths to the `results` vec)

These reroute to `FindFirstFileW`, `FindNextFileW`, `FindClose` (0xF016–0xF018),
and `GetFileAttributesW` (0xF019) on Windows. Since 6.6.12 the path goes to the
reroute as UTF-8 and is widened the way `open`/`mkdir` widen theirs: invalid UTF-8
is refused, and a path of 248 units or more is made absolute and `\\?\`-prefixed,
so `is_dir`, `dir_list`, `is_symlink`, `sys_access` and `xmkdir_p` work on long
paths too. Results come back as UTF-8 Str. A listing that fails part-way is an
error, not a short directory: after `FindNextFileW` returns 0 the lister reads
`GetLastError` (0xF04B) and only `ERROR_NO_MORE_FILES` ends it. `dir_list_into`
(the caller-owned-buffer lister) has a Windows arm as well, with the same
-1/-2/-3/-4 contract.

**Environment**
- `getenv(name)` → pointer to value, or 0

Windows has no `/proc/self/environ`; the lookup routes to
`GetEnvironmentVariableA` (0xF015). The compiler reads its own `CYRIUS_*` knobs
the same way — `CYRIUS_STATS`, `CYRIUS_DCE`, `CYRIUS_SYMS` and the rest all work
against `cycc.exe` from v6.6.6 (before that `cycc.exe` saw none of them).

> ⚠ Setting one from `cmd.exe`: write `set CYRIUS_STATS=1&& cycc.exe …` with **no
> space before the `&&`**. `set VAR=1 & prog` puts a trailing space *in the value*,
> and the compiler's knobs test for exactly `"1"`, so the variable silently fails
> to match and the run looks like an unfixed compiler.

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
- **Arity 2** (close, unlink, fsync, exit): if syscall == 3 → close, == 87 → unlink, == 74/75 → fsync/fdatasync (v6.6.9), == 60 → exit
- **Arity 5** (getdents64, unsupported): returns -38 (-ENOSYS) — directory listing uses the arity-3 `FindFirstFileW` etc. instead
- **Unknown arity**: returns -38

⚠ A number held in a `var` is known only at run time, so the compiler warns about it only for an
arity with **no** routable member. At an arity that has members, a number outside them returns
-38 with no compile-time diagnostic — which is why the runtime switch and the literal routes
must carry the same Linux numbers.

Each routable pair emits the kernel32 call inline. Unknown syscalls return -38
(ENOSYS), matching POSIX semantics, so a path that is genuinely dead on Windows can
compile without being routed.

> ⛔ **v6.6.6 — the example that used to close that sentence was the opposite of dead.**
> It read *"(e.g., POSIX fork/execve) can compile without routing them"*, and that belief
> is what licensed twelve unguarded `sys_fork` sites in `cbt/`. `fork`/`execve`/`waitpid`
> are not unrouted syscalls returning -38 — they are **wrappers**
> (`lib/syscalls_windows.cyr`) that `return 0 - 1`. So a POSIX fork/wait on PE does not
> fail; it **succeeds wrongly**: `pid` is `-1`, the parent takes the `pid != 0` branch,
> `sys_waitpid` also answers -1 without touching the buffer, and the caller then decodes
> an **uninitialised stack slot** as the child's exit status. Whenever that garbage reads
> as `WIFEXITED` with status 0, the code reports success for a child that never existed —
> measured on real cass, `cyrius self` printed its header and exited 0 without compiling
> anything. **A fork path on Windows needs an `#ifdef CYRIUS_TARGET_WIN` arm that spawns
> (`_win_compile_spawn`, `exec_cmd`, …) or refuses by name; "it is dead there" is not a
> property the stub gives you.** Pinned by
> `tests/gates/platform/cbt_fork_sites_have_pe_arm.sh`. See CHANGELOG [6.6.6].

### Win64 MS-x64 ABI Details

Cyrius PE code follows the Microsoft x86_64 ABI precisely:

- **Calling convention**: Arguments in RCX, RDX, R8, R9; excess on stack
- **Return values**: RAX (64-bit), RDX:RAX (128-bit pair via multi-return)
- **Shadow space**: 32 bytes (0x20) reserved by the caller above RSP
- **Stack alignment**: RSP must be 16-byte aligned **at the `call` instruction**, so the
  callee is entered with RSP ≡ 8 (mod 16) — the return address the CALL pushed is what
  makes the difference. This is the same rule SysV states the other way round ("rsp+8 is
  16-aligned at entry"); it is NOT `RSP % 16 == 0` at entry.
- **Registers**: RAX, RCX, RDX, R8, R9, R10, R11 are volatile; RBX, RBP, RSI, RDI, R12–R15 preserved

Since 6.6.5 the entry landing emits `sub rsp, 8`, which puts the PE base on the same
footing as every other target: with nothing pending on the expression stack, RSP is
16-aligned, and the call emitters pad for an odd number of pending values. Cyrius function
prologues, the kernel32 reroutes and `callptr` all maintain that invariant.

> ⛔ **This paragraph used to describe a shim that did not exist.** It claimed the entry
> "`sub rsp, 8`s to align" — disassembly of any 6.6.4 PE shows the landing going straight
> from the entry jump into user code. The whole PE base therefore ran one parity off: every
> statement-level call entered its callee at RSP ≡ 0, and the calls that happened to be
> correctly aligned were the ones nested at odd depth inside an expression. It was
> survivable only because cyrius-emitted code uses no aligned SSE, while the seven
> fixed-frame kernel32 reroutes had each been hand-tuned to the inverted base — so
> `f(0, open(path))` crashed inside kernelbase's own `movaps` in CreateFileW. The shim
> described here is real as of 6.6.5, and the reroute frames were retuned in the same
> change. See CHANGELOG [6.6.5].

**UEFI (`CYRIUS_TARGET_EFI=1`) shares that entry convention and adds one rule of its own.**
A UEFI Application's entry point IS an MS-x64 function and firmware reads `rax` as the
`EFI_STATUS`, so the image exits with a `ret` rather than a syscall — and `ret` pops `[rsp]`
itself, so it is correct only where RSP is exactly the RSP firmware entered with. Since
6.6.5 the landing parks that value (`lea r13, [rsp]`, immediately before the seed) and every
exit emits `mov rsp, r13; ret`, so `syscall(60, status)` terminates the image correctly from
any call depth — including from inside a fn, which is how `lib/alloc.cyr` and
`lib/bounds.cyr` abort. **If you hand-write an asm block in a UEFI image that returns to
firmware through its own `ret`, it must undo its own frame AND the 8-byte landing seed** —
see `programs/efi_probe.cyr`, whose deliberately asymmetric `sub rsp,0x20` / `add rsp,0x28`
is the worked example. **R13 is reserved from the register allocator in UEFI builds**
(`#regalloc` caps at rbx + r12 there); inline asm that clobbers R13 breaks the exit path.

### macOS x86_64 (Mach-O) entry alignment

**Darwin does not hand a static Mach-O executable a 16-byte-aligned RSP, and the parity is
not even fixed per binary — it varies with the byte count of the argv/env string area.**
Measured on real Intel-Mac hardware at 6.6.5: the same executable, renamed, reports both
parities (`./_l` misaligned, `./_ltxx` aligned; `PADVAR=x` misaligned, `PADVAR=xxxxxxx`
aligned), and a 20-argv0-length × 16-env-pad sweep splits 160/160. This is a per-KERNEL
fact, not something to infer from the SysV ABI: Linux ELF *does* guarantee `RSP % 16 == 0`
at `_start`, Darwin does not.

Since 6.6.5 the Mach-O landing emits `and rsp, -16` immediately after the `mov r15, rsp`
argv park, so the base is 16-aligned whatever the kernel handed over (it rounds DOWN, and
is free when the entry was already aligned). **R15 stays reserved and still holds the
kernel's init RSP** — that is what `argc()` / `argv()` / `_read_env` read, and it is parked
*before* the alignment for exactly that reason. If you hand-write asm in a Mach-O image,
read argv through R15, not through RSP.

⚠ **Re-running a test under one name is not a verification on Darwin.** Any check of entry
alignment there has to sweep argv0 length and environment size; the recipe is in the header
of `tests/gates/codegen/call_site_stack_alignment.sh`.

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
and `callptr` itself is Win64-ABI–correct — it force-aligns with an rbx-anchored
`and rsp, -16` at the call site, which is why it was correct even while the PE base was
inverted (see the alignment note above) and remains correct now that the base is seeded.
So careful consumers can implement COM wrappers. See the `Function Pointers` section of
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

agnos defines an append-only syscall surface: **#0–#104 and #106–#108** at agnos 1.57.10
(`lib/syscalls_x86_64_agnos.cyr`; #105 was withdrawn and is never re-added). Beyond the
GPU-compute band #82–#91 it carries `gpu_shader_op` (#92), `gpu_modeset_op` (#93),
`gpu_recover_op` (#94), `uptime_us` (#95), **`fork` (#96, minted at v6.5.37 / agnos 1.56.55 —
its arm is in the ring-3 entry stub)**, the local-IPC **channel band** `chan_op` (#97, v6.5.8),
and on up to `sched_yield_to` (#108, agnos 1.57.9); the next free number is #109. ⚠ A number
is minted only once its kernel arm exists — on agnos an unknown number falls *through* the
dispatch chain and the caller reads the fall-through value as data, so a
minted-but-unimplemented constant is strictly worse than an absent one. The register
convention is x86_64 SysV (rax=number, rdi/rsi/rdx/r10=args 1–4, rax returns
result ≥0 on success, -1 on error). Key differences from Linux:

```
# agnos syscall numbers — append-only, #0–#104 + #106–#108 (lib/syscalls_x86_64_agnos.cyr)
SYS_EXIT = 0       (not Linux 60)
SYS_WRITE = 1
SYS_READ = 5
SYS_OPEN = 7
SYS_SPAWN = 3      (legacy: spawn an in-memory ELF ≤ 16 KB; from disk use #43 spawn_path)
SYS_WAITPID = 4    (NON-blocking poll: a WAIT STATUS, -2 while the child lives, -1 not ours;
                    0x100|pid blocks (WAIT_BLOCK, 1.57.7) — decode with WIFEXITED/WEXITSTATUS/…)
SYS_MMAP = 27      (anonymous, 2 MB-granular, no hint support)
SYS_FORK = 96      (fork: the child's pid / 0 in the child / -1; NO execve — start a program with #43)
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

**`lib/process_agnos.cyr`**: process spawn and wait (rewritten 6.6.8; agnos ≥ 1.57.6).
agnos has fork (#96) but no execve, so a program is started from disk by the parent:
`spawn_path` #43 with a real argv (`SPAWN_F_ARGV`, arguments may hold spaces) and a clean fd
table (`SPAWN_F_CLEANFD`), waited for with WAIT_BLOCK (1.57.7), and captured through a pipe
armed on the child's fd 1 by `exec_redirect` #62. The wrappers are `run`, `spawn`, `wait_pid`,
`exec_vec`, `exec_capture` / `exec_capture_status`, `exec_env` and `exec_cmd`. argv[0] is an
absolute path — there is no PATH search and no shell. `lib/regression.cyr`'s spawn and capture
verbs and `lib/async.cyr`'s `async_timeout` / `async_run_process` run real processes on agnos
too (6.6.10).

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

⛔ **A RAW SYSCALL NUMBER IS THE SINGLE MOST PORTABLE-LOOKING THING THAT IS NOT PORTABLE, and
ELF-aarch64 will not tell you.** The aarch64 backend rewrites the x86_64 numbers it knows
(`ESYSXLAT`, a hand-written chain — derive its row count from the source, never quote it) and passes everything else through to the `svc` verbatim — by design,
because a native aarch64 number must survive. So an unrecognised number is not an error, it is
a *different, valid syscall*. Measured under `qemu-aarch64 -strace` before v6.6.5: raw 77
(x86 `ftruncate`) ran **tee**, raw 46 (`sendmsg`) ran **ftruncate**, raw 44 (`sendto`) ran
fstatfs, raw 35 (`nanosleep`) ran `unlinkat(0, NULL, 0)`, raw 87 (`unlink`) ran
timerfd_gettime and raw 83 (`mkdir`) ran fdatasync. The build succeeded and printed nothing.

Since 6.6.18 a literal (compile-time-constant) syscall number is translated at compile time, by
simulating the `ESYSXLAT` chain in its own order — so every ordering rule below still applies, and
the site carries only the row bodies that would run; a number held in a variable calls one shared
stub that runs the chain at run time. Neither changes WHICH syscall a number reaches.
A generic `syscall()` with more than six arguments after the number is refused by name
(PE's Winsock reroutes, which take more, are unaffected).

The rules, in order:

1. **Spell the `SYS_*` name from `lib/syscalls.cyr`.** Each peer defines it as the right
   number for that target, and the wrapper (`sys_ftruncate`, `sys_sendmsg`, `sys_nanosleep`,
   `sys_statfs`, …)
   also carries the macOS/Windows/agnos arm where the call does not exist. This is the answer
   for the six x86 numbers cyrius deliberately does NOT route, because aarch64's native
   meaning for each is a call somebody uses: **24** (`sched_yield` on x86, **dup3** on
   aarch64), **53** (`socketpair` / fchmodat), **52** (`getpeername` / fchmod), **21**
   (`access` / epoll_ctl), **90** (`chmod` / capget) and **17** (`pread64` / getcwd).
2. **If you must write a number, write the x86_64 one.** That is the supported convention —
   cyrius's own `enum Sys` does it — and `ESYSXLAT` renumbers it. A number the chain routes is
   silent; a number it does not is reported by name (`raw syscall 294 is x86_64
   \`inotify_init1\`; on ELF-aarch64 that number is …`), *provided both Linux peers declare a
   `SYS_*` for it*. An UNNAMED number gets no diagnostic at all — that is the gap v6.6.5
   closed, and it is why rule 1 comes first.
   Since v6.6.12 the report is **not** made for a call inside a region compiled only for
   aarch64 — the taken side of `#ifdef CYRIUS_ARCH_AARCH64` / `#ifplat aarch64`, of
   `#ifndef CYRIUS_ARCH_X86`, or the `#else` of their opposites — because a number there is
   the native one by construction (`syscall(8, ..)` IS getxattr), whether spelled as a
   literal or through an `enum` constant. That silences a wrong "use SYS_LSEEK"; it does not
   make such a number safe — rule 3 still applies.
3. **Never write the aarch64-native number under an `#ifdef CYRIUS_ARCH_AARCH64`.** It looks
   like the careful thing to do and it is the fragile one: a compat row matches a NUMBER and
   cannot tell your native number from the x86 number it is chasing, so a routing row added
   later silently steals it. ⚠ This applies to a **variable** syscall number too — the chain
   runs on the value in `x8` at run time, so `var n = 83; syscall(n, fd);` is rewritten
   exactly as a literal would be. ⚠ It also applies to a `SYS_*` you declare in your OWN
   `enum` — measured at v6.6.5, `lib/yukti.cyr` declares `SYS_STATFS = 43` under exactly this
   guard and the `43 → 202` socket row makes every call `accept()`. ⭐ v6.6.6 gave that call
   the name it was missing: both Linux peers now declare `SYS_STATFS = 137` / `SYS_FSTATFS =
   138` (the x86 numbers, per rule 2) with `ESYSXLAT` rows `137→43` and `138→44`, plus
   `sys_statfs` / `sys_fstatfs` wrappers and Darwin routes `137→345` / `138→346`. A consumer
   that deletes its own declaration and calls the wrapper is correct on every target; one
   that keeps `SYS_STATFS = 43` under the aarch64 guard still runs `accept()`, and now gets
   a `duplicate symbol 'SYS_STATFS' redefined with conflicting value` warning saying so.
   ⭐ v6.6.8 did the same for eight more: `SYS_UNSHARE` 272, `SYS_CHROOT` 161,
   `SYS_PIVOT_ROOT` 155, `SYS_CAPGET` 125, `SYS_CAPSET` 126, `SYS_PROCESS_VM_READV` /
   `_WRITEV` 310 / 311 and `SYS_MKNODAT` 259, each with a `sys_*` wrapper (Darwin -78, PE and
   agnos -38) and a row to the aarch64 call. Before it, the native chroot (51) and pivot_root
   (41) were unreachable behind the socket compat rows, and the x86 numbers ran sethostname,
   getpgid, kcmp and the scheduler priority queries. The seccomp arch tag is
   `AUDIT_ARCH_NATIVE` in the Linux (and x86-macOS) peers.
   ⭐ 6.6.12 named the extended-attribute family, `fchown`, `statx` and `getrlimit`:
   `sys_{,l,f}setxattr`, `sys_{,l,f}getxattr`, `sys_{,l,f}listxattr`, `sys_{,l,f}removexattr`,
   `sys_fchown`, `sys_statx` and `sys_getrlimit`. Neither the native nor the x86 number was
   usable for most of them — native 5/6/7/9/10/11/12/16 and 55 are compat-row SOURCES (raw
   lgetxattr 9 ran mmap, fchown 55 getsockopt) and x86 198/199 are aarch64's own socket /
   socketpair — so the aarch64 peer spells them through the **private alias band**: a source
   number **≥ 1000** that no OS will ever mint, written `1000 + the native number`
   (`SYS_SETXATTR` 1005 … `SYS_FREMOVEXATTR` 1016, `SYS_FCHOWN` 1055, `SYS_STATX` 1291) and
   renumbered by rows at the very END of `ESYSXLAT`'s chain, below every compat row whose
   source their product would match (`tests/gates/platform/esysxlat_row_order.sh` checks the
   order, and that every alias the peer declares has its row). `getrlimit` needed no alias:
   its native 163 is neither a row source nor a row product. On macOS `sys_fchown` and
   `sys_getrlimit` are real (Darwin 123 / 194 — but `RLIMIT_NOFILE` is 8 there, not 7), and the
   xattr calls and `sys_statx` return -78: Darwin's xattr calls take two extra arguments and
   Darwin has no statx. PE and agnos decline all fifteen with -38.
   In-tree all three shapes — a `SYS_*` declaration, any identifier assigned a literal that is
   then a syscall's first argument, and a bare `syscall(<literal>)` — are enforced by
   `tests/gates/platform/aarch64_syscall_shadow.sh` (axes 2 and 3), across `src/`, `lib/`,
   `cbt/`, `programs/`, `tests/`, `benches/` and `fuzz/`. cyrius's own compiler source was
   breaking this rule when the rule was written: `src/backend/common/runtime.cyr` issued
   `syscall(113, …)` for aarch64 `clock_gettime` until review round 2 of that same release.
4. **One routed call is not an exact synonym: `dup2`.** Raw x86 `33` is renumbered to
   aarch64 `dup3(oldfd, newfd, 0)` because aarch64-Linux dropped `dup2`. Every case agrees
   except the self-dup idiom: `dup2(fd, fd)` returns `fd`, while `dup3(fd, fd, 0)` returns
   `-EINVAL`. If your fd-shuffling loop leans on the self-dup, branch on `old == new`. It is
   still far better than the alternative — untranslated, aarch64 33 is `mknodat`, which would
   read your fds as `(path, mode)`.
5. **Routing the number is only half of portability — the STRUCT the call fills is the other
   half, and it differs in WIDTH as well as offset.** Read every field through the peer's own
   offset enum (`STAT_*`, `STATFS_*`), never a number you counted on x86. Two live examples:
   `st_mode` is at +24 on x86_64-Linux, +16 on aarch64-Linux and +4 on Darwin arm64; and
   Darwin's `struct statfs` starts with a **32-bit** `f_bsize` immediately followed by
   `f_iosize`, where Linux's is a full 8 bytes — so `load64(&buf + STATFS_BSIZE)` on macOS
   returns `f_bsize | (f_iosize << 32)`, i.e. 4503599627374592 for a 4096-byte block on a
   1 MiB-iosize volume, which then multiplies straight into a capacity figure. That is why
   `statfs_bsize(buf)` exists: an accessor, not a convenience. When a peer publishes one, use
   it instead of a raw `load64`.
6. **On macOS an unrouted number FAILS — it never runs something else.** Both Mach-O backends
   renumber Linux syscalls to Darwin's (`EMACHO_SYSXLAT` on x86_64, `ESYSXLAT`'s Mach-O arm on
   arm64), and since 6.6.8 a number no row handles kills the process with **SIGSYS** on both
   Macs, or returns **-ENOSYS (-78)** if SIGSYS is ignored. Before 6.6.8 arm64-macOS left
   Darwin's syscall register holding its previous value, so an unrouted call silently re-ran
   the PREVIOUS syscall with the new arguments and returned a plausible answer. cycc reports
   every such number at compile time — `warning: syscall N not routed by the Mach-O …
   translation` — and in this repo `tests/gates/platform/darwin_syscall_literals_routed.sh`
   fails on one. Four numbers are rerouted at PARSE time rather than by a table row, and
   only at one arity: **228** (the clock; ns in the return register, the buffer argument
   unspecified — x86-macOS happens to fill a timeval, arm64-macOS never touches it; PE
   returns ms) and **35** (nanosleep, x86-macOS) need the number plus exactly 2 arguments,
   **1700** (pthread_create, arm64-macOS) the number plus 4, and **1701** (libSystem
   `fork()`, arm64-macOS, v6.6.13 — the child runs the atfork handlers, so it can create
   threads) the number alone. Any other arity is reported by name (`syscall 228 not routed
   at this arity`). Portable code calls `clock_now_ns()` / `sleep_ms()` /
   `thread_create()` / `sys_fork()` instead.
7. **Set O_NONBLOCK with `fd_set_nonblocking(fd)` / `fd_restore_flags(fd, saved)`, and every
   other fcntl with `sys_fcntl(fd, cmd, arg)` (v6.6.8) — never a raw `syscall(SYS_FCNTL, …)`
   and never `fl | 2048`.** 2048 is Linux's O_NONBLOCK and Darwin's O_EXCL, which F_SETFL
   ignores, so the fd silently stays blocking on macOS. The wrapper's bit is PRIVATE and
   per-target for a reason worth knowing: enum constants are global and the LAST definition
   wins retroactively, program-wide, so one included module that declares its own
   `O_NONBLOCK = 2048` (yukti <= 2.3.12 did) changes the public name for every user in a macOS
   build. PE and agnos have no fcntl; the three decline with -38 there. `lib/net.cyr`'s
   `sock_set_nonblocking` is the same call under a socket name. A socket that must deliver a
   whole buffer uses `sock_send_all(fd, buf, len)`, which completes or reports a short write
   (`len` or -errno) — a bare `sock_send` / `sys_write` can return fewer bytes under
   SO_SNDTIMEO or a signal.

Same trap on the other side: `var SYS_FOO = <x86 number>` in your own source SHADOWS the
stdlib's arch-aware definition (last definition wins), so it is right on x86 and wrong
everywhere else. cycc warns on a conflicting `SYS_*` redefinition.

### Capabilities and Limitations

**Works on agnos**:
- Syscall wrappers (all of #0–#104 and #106–#108; #105 was withdrawn)
- Heap allocation (bump, 2 MB chunks)
- File I/O (read, write, open, close, stat, getdents/readdir)
- Process spawn, wait and capture from disk (`sys_spawn_argv` / #43, WAIT_BLOCK, #62 redirects),
  and `fork` (#96) — but no execve
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
  bare `chan_send`/`chan_recv`/`chan_close` are already the in-process MPMC thread channel, and
  cyrius resolves duplicate fns last-definition-wins.
- Pipes, epoll, signalfd, timerfd (the event loop primitives). ⭐ v6.6.7: `sys_read` / `sys_write`
  (and every short raw `syscall`, which cycc now emits with a4 = 0) BLOCK on an empty / full pipe
  or channel on agnos 1.57.8+ — the kernel reads a4 = r10 as O_NONBLOCK, and it used to be left
  undefined; `sys_read_nb` / `sys_write_nb` are the non-blocking forms
- Blocking waits and a real wait status (v6.6.7, agnos 1.57.7): `sys_waitpid_block`, W* per ABI §4.9
- Socket reads bounded by a real clock: a timeout is -11 (EAGAIN), per-socket via
  `sock_set_recv_timeout`; a server bound to 127.0.0.1 listens on loopback only (CVE-48 —
  it refuses to start on agnos < 1.57.7 rather than listen on the network)
- Signals (sigprocmask, kill, pause)
- Filesystem (mkdir, rmdir, unlink, rename, link on ext2)
- Networking (sockets, UDP, ICMP; #47–#61). Since 6.6.17 the BSD verbs link too: `sys_socket`
  (AF_INET + SOCK_STREAM only), `sys_bind`, `sys_listen`, `sys_connect` and `sys_accept4` are built
  on the same tagged-fd adapter as `lib/net.cyr` (#47 / #56 / #57); `sys_accept4` is
  non-blocking (-11 when nothing is pending) and every other shape declines -38
- Framebuffer, blit, keyboard (#38–#42), the GPU-compute band (`sys_gpu_dispatch`..`sys_gpu_blit_bb`, #82–#91) and the #92–#95 tail
- SIMD, function pointers, inline asm (same as Linux/macOS)

**Does NOT work on agnos** (either absent from the surface or stubbed):
- Process **arguments** to an in-memory `sys_spawn` (elf_addr, elf_size only). From disk,
  `sys_spawn_argv` (v6.6.7, agnos 1.57.6) passes a real argv — arguments may contain spaces —
  where the line-form `sys_spawn_path` splits on spaces
- `dup2`-style redirection in the CURRENT process (`sys_dup` is a stub returning `fd` unchanged).
  A CHILD's fds are redirected at spawn time instead (`sys_exec_redirect`, #62), which is how
  `run_capture` / `exec_capture` capture stdout since 6.6.8
- `getppid` (no getppid in the surface; returns 0)
- `getuid` (always 0 / root)
- `chmod` (no permission model; `sys_chmod` is a no-op stub returning 0)
- Thread-local storage (not modeled in agnos ring-3)
- Dynamic linking (`dlopen`, auxv machinery), only static binaries
- Socket options: `sys_setsockopt` is a -38 decline stub (6.6.16); deadlines go through
  `sock_set_recv_timeout` / `sock_set_send_timeout`
- The `cyrius` CLI: built for agnos (6.6.17) it answers `version` and `help` only — its verbs
  run cycc as a child process through fork / execve / waitpid. Compile with `cycc` directly

The agnos syscall surface is **append-only, currently #0–#104 + #106–#108 at agnos 1.57.9 (#105 withdrawn)**. The
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

⚠ Until v6.6.5 the wrapper had no `--pie` arm, so the documented command below errored with
`unknown flag '--pie'` and only the environment variable worked. The flag is real now (it
sets `CYRIUS_PIE=1` on the compiler's environment); the doc had been wrong, not the reader.


```sh
cyrius build --pie src/main.cyr build/myapp       # x86_64 or aarch64 (real since v6.6.5)
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
cyrius build --target=js app.tsx app.js # x86-Linux-only; refused BY NAME elsewhere (v6.6.6)
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

> ⛔ **v6.6.6 — until this release "x86-Linux-only" was documentation, not behaviour, and
> what happened elsewhere was worse than a failure.** The CLI forked the host's cycc with
> `--emit-js`; that compiler does not know the flag, so it **ignored it**, read its
> **empty** stdin, emitted a runnable binary, and the CLI renamed that over the `.js` and
> printed `OK`. Measured on real pi at 6.6.6: `emit-js t.ts -> out.js [js] OK`, exit 0,
> `out.js` a 65,888-byte aarch64 ELF. `cyrius build --target=js` now **refuses by name**
> on every host whose compiler is not built from `src/main.cyr`, naming that host's fork,
> and writes no output file. Verified on real ecb, ach and pi; pinned by
> `tests/gates/toolchain/emit_js_refused_off_x86_linux.sh`, whose axis 1 re-derives
> "`src/main.cyr` alone carries the TS front end" from the include graph each run.
> See CHANGELOG [6.6.6].

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
