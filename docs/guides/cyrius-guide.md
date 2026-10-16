# Cyrius Language Guide

> The complete reference for writing Cyrius programs and kernels.

## Quick Start

```sh
cyrius build hello.cyr build/hello           # Compile (resolves deps from cyrius.cyml)
./build/hello; echo $?                       # Run → 42
```

## Types

The core type is the 64-bit integer (`i64`) — no separate pointer type at
the value level (see ADR-002). Type annotations are optional, and an `i64`
one changes no code — it only marks the name a declared scalar, which forming a
[`dyn`](#trait-objects-dyn-678) from it needs:

```
var x = 42;
var y: i64 = 42;      # Same thing — an i64 annotation is documentation
```

Other annotations do carry meaning: a narrow integer variable (`i8`..`i32`, `u8`..`u32`) is stored
at its width (a struct field's widths are in [Field types](#field-types-v6610)), an `f64` / `f32`
makes arithmetic on it float, a `*T` steps `sizeof(T)` and takes `p[i]`,
a `bool` checks every write into it, and a struct type is checked on copies and arguments — see
[Type names](#type-names-6616) and the sections each one points to.

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
(v6.5.21), which types `x` from the declared return, as it does (6.7.9) a whole method call
ending the initialiser: `var a = p.area();`, `w.v.area()`, `p.me().area()`, `mk(1).area()`
with `fn area(self): f64`. A leading `: f64` call types the binding only while the whole
initialiser is still an f64 (6.7.13): `var x = f() * 2.0;` is an f64, `var c = f() < 1.0;` and
`var c = f() > 0.1 && k == 1;` are the integer 0 / 1 a comparison is (through 6.7.12 `c` was typed
f64, so `-c` flipped its sign bit and `0 - c` warned). It does NOT cover an **untyped**
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
since 6.6.10 each WARNS: `an integer stored into an f64/f32 slot keeps its integer bits`. An
ARGUMENT for an `f64` / `f32` parameter is such a slot too (6.7.11): `f(3)`, `p.m(3)`, `return
f(3);`, a call to a fn defined below, an `#inline` fn and an operator fn's right operand (`p + 3`
into `fn P_add(a: P, b: f64)`) warn the same way, and still pass `0x3` (through 6.7.10 silently).
Write `1.0`, or `f64_from(n)` for a runtime integer. `0` is exempt (its bits are 0.0), and
so is a hex bit pattern at or above 2^52 (`0x3FF0000000000000` is 1.0 on purpose); a runtime
untyped value (`var x: f64 = load64(p);`) is the legal boxed-float idiom and is not judged.

**An f64 value initializing an `f32` rounds to f32 (6.7.6).** `var x: f32 = 1.5;` — a local, a
global (before or after the first top-level statement) or a `for` init — stores 1.5 rounded to the
nearest `f32`, ties to even: what `f32_from(1.5)` gives, and what an `f32[N]` list element takes.
The value is an f64 when the compiler sees one: a float literal, f64 const arithmetic, an `f64`
variable, field or `: f64` fn, or a float builtin's result. An `f32` value is stored as it is, an
integer constant keeps its bits (with the warning above) and an untyped word (`load32(p)`) is the
boxed idiom, not converted. Until 6.7.6 the initializer stored the f64 bits, so `x` read as 0.0,
silently. **Every other write into an `f32` rounds the same way (6.7.6)**: an assignment `x = 1.5`
(a local or a global, a statement or a classic-`for` step), a field store `p.x = 1.5` (through a
`*T` too), a struct-literal field `P { 1.5 }` and an argument to an `f32` parameter (`f(1.5)`, a
method, a fn defined below the call, and the right operand of an operator overload: `r + 1.5` with
`fn R_add(self, b: f32)`). Each stored the f64 bits as well. An `f32` operator still
reads its right operand as f32 bits (the next paragraph): `x = x + 1.5` adds 1.5's low 32 bits, then
stores an `f32` — write `x + f32_from(1.5)`.

⚠ Binary operators are typed by their LEFT operand. `0 - 1.5` is an INTEGER subtraction
of 1.5's bit pattern (it is -3.0), and `2 * x` with `x: f64` multiplies x's bits. Write
the left operand as a float — `0.0 - x`, `2.0 * x`, or just `-x`. Both directions warn:
an f64 left with a non-f64 right (`f64 arithmetic with a non-f64 right operand`) and,
since 6.6.8, an integer left with an f64 right (`integer arithmetic with an f64 right
operand`). An **f32** left takes the LOW 32 BITS of its right operand, so an `f64` literal
or an integer there is reinterpreted, not converted — with `x: f32`, `x * 2.0` is 0 and
`x + 1.0` is `x`. Since 6.6.11 it warns too (`f32 arithmetic with a non-f32 right operand`);
write `x * f32_from(2.0)`. They are warnings, not errors (ADR-002: the untyped `i64`-boxed
float idiom stays legal); `CYRIUS_TYPE_CHECK=0` silences them. One integer + f64 mix warns once,
however far its result is carried (6.7.11): `x = x + (x + 1.5)`, `2 * (x + 1.5)` and `x += x + 1.5`
warned twice, `x - (x * (x + 1.5))` three times — the mix's result keeps the f64 type, so each
enclosing integer operator saw an f64 right operand again. Two mixes still warn twice, and `x + 1.5
+ 2` still warns kind 1 for the `+ 2`.
A comparison, an `&&` / `||` link and `& | ^ % << >> >>>` give an INTEGER whatever their right
operand (6.7.13; `& | ^ % << >> >>>` the user's decision D12, 2026-10-15): with `n` an integer and `x:
f64`, `(n < x) * 3` is 3 (the comparison still warns `comparison mixes f64 and integer operands`),
and `(n & x) * 3` multiplies integers. Through 6.7.12 the result kept the f64 type of its right operand,
so the next operator took the f64 arm (`(n < x) * 3` was 0, with a kind-1 warning naming the wrong mix).
Only `+ - * /` keep an f64 right operand's type (they have f64 forms).

**Compound assignment on a float (6.6.11).** `x += y`, `-=`, `*=` and `/=` on an `f64` /
`f32` variable are float operations — for a local, a **global**, a top-level statement and a
`for` step alike — and the right operand is checked exactly as in `x = x + y` (`t += 1` on
an `f64` warns: 1's bits are a subnormal, write `t += 1.0`). Until 6.6.11 only a local got
the float arithmetic: `G += 1.0` on an `f64` global added the two bit patterns as integers,
and `for (var x: f64 = 0.0; x < 1.0; x += 0.25)` ran twice instead of four times, silently.
`%=`, `&=`, `|=`, `^=`, `<<=`, `>>=` and `>>>=` are integer operations on any variable. On an
INTEGER place, `x += 1.5` (and `-=`, `*=`, `/=`, on a variable, a field, an element or `*p`) warns
`integer arithmetic with an f64 right operand`, as `x = x + 1.5` does (6.7.7). A
`for` step accepts all eleven compound operators (it used to accept five; `>>>=` since 6.7.5).
Since 6.7.5 the same float rules hold on an `f64` / `f32` **field** (`p.x *= 2.0`) — see
[Compound assignment](#compound-assignment-every-lvalue-675).

## Variables

```
var x = 10;            # Global or local (context-dependent)
var buf[256];          # Bare array — see byte-vs-slot note below
var slots: i64[256];   # Element-typed array — 256 i64 SLOTS (2048 bytes), anywhere
slots[3] = 7;          # Subscript: an element-typed array, a *T or a slice (see Subscripts)
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
| `Vec` / `Vec<T>` | 8 | a `vec_new()` handle, as a struct field has always taken it; `T` is read (6.7.11, below) |
| a vector type (`f64v2` … `u64v2`, `f64v4`, `f32v8`) | 16 / 32 | |
| a struct or union (`Pt`) | its size | a struct **named** like a scalar (`u8pair`) is the struct |
| a type parameter in scope (`T`) | its argument's size | the `i64` base: 8 |
| a tuple `(i64, f64)` (6.7.7) | — | 8 bytes per element; only a `var`, a parameter, a struct field and a multi-value return take it (`sizeof((..))` is refused) — see [Tuples](#tuples) |
| `dyn Tr` (6.7.8) | — | two opaque words (16 bytes), wherever a struct type goes after a `:`; `sizeof(dyn Tr)` is refused — see [Trait objects](#trait-objects-dyn-678) |

`var a: T[N]` reserves exactly `N * sizeof(T)`. Inside a generic fn's instance a type
parameter IS its argument: in `g<f64>`, `var y: T` and a parameter `x: T` are `f64`s (their `+`
is a float add; the parameter still arrives in an integer register, as a non-generic `x: f64`
does), a `: T` return is an `f64` return, typed `f64` at every call (6.7.9), and `var a: T[N]`
holds `f64`s; in `g<i8>`, `var y: T` sign-extends like any `i8`. (Before
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
by name, without their `include`. A return type is a struct, `i8`..`i64`, `f64`, `bool`
(6.7.3), a vector type, `Result`, `Option`, `Tagged`, `cstring`, a pointer `*T` (6.6.17), a
multi-value `(T1, T2)` / `(T1, T2, T3)` (see [Multi-Return](#multi-return)), `dyn Tr` (6.7.8) or
a generic fn's first or second type parameter — `fn f(): u8`, `: u64`, `: f32` and an enum are
refused by name (`type 'u8' cannot be a fn return type`; return an `i64`), with a note that lists
this whole set (6.7.11; it used to leave out `bool`, the multi-value form, `dyn` and `T`).
`cyrius lint` (`--syntax-only`) resolves no type names, so it never reports these.

**A `Vec<T>` annotation reads its `T` (6.7.11)** as a struct field `items: Vec<T>` always has — a
local, a global (either zone), a parameter, `*Vec<T>` (a variable, a parameter, a field, a return),
`**Vec<T>`, a `*fn(Vec<T>)` parameter and `sizeof(Vec<T>)`. `T` is a struct or union, an integer or
float, `bool`, `cstring`, `Result` / `Option` / `Tagged`, an enum, `Vec` (a nested `Vec<..>` is read
the same way) or a type parameter in scope; any other element's own `<..>` is not read
(`Vec<Box<i64>>`). Everything else is refused by name, once: a tuple (`a tuple type cannot be a Vec
element`), an unknown name (`unknown type 'Nope' as the Vec element of 'v'`), a vector type, a slice,
`u128`, a token that is no type (`expected a Vec element type for 'v', got number 1`; a pointer element
`Vec<*Pt>` too, as the field form refuses it) or a second argument (`Vec<i64, i64>`). The handle is unchanged: `Vec<T>` declares the 8-byte word it always did.
Through 6.7.10 these positions skipped the `<..>` unread, so `var v: Vec<(i64, i64)>`,
`Vec<nosuchtype>` and `Vec<1 + 2>` compiled (the user's decision (a), 2026-10-13).

**A parameter's type is read whole (6.7.11)**, by the grammar a trait member's signature uses (6.7.8),
plus a bare `*fn`: any number of `*`, then `u128`, a tuple, `*fn( .. )` with an optional `: T`, a bare
`*fn`, or a name with its `<..>` — `fn f(p: **i64)`, `fn g(p: ***Pt)`, `fn ap(cb: *fn(i64): i64, x)`.
`**T` is a pointer whose step is a pointer's 8, as a `**T` local's is, and `*p` of it is a `*T` (6.7.13, see
[Pointers](#pointers)); `*fn( .. )` is one word, its
names are checked, and a call does not check the fn it is given against them. Anything else is refused
by name, once, with no cascade — `fn f(a: 5)` is `expected a type for parameter 'a', got number 5`,
and so are an operator, `;`, a string, a keyword, a missing type (`a:`), a lone `*` and `fn( .. )`
with no `*` (a grammar refusal: `cyrius lint` reports it). ⚠ Before 6.7.11 both of the compiler's
passes read ONE token after at most one `*`: `fn f(p: **i64)` was `expected ')', got identifier
'i64'`, `cb: *fn(i64): i64` was `expected ')', got '('`, and `fn f(a: 5)` / `(a: +)` / `(a: "s")`
compiled with the token skipped.

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
`f32` array element is 4 bytes, and so is an `f32` struct FIELD since 6.7.10
(it took 8 before — see [Field types](#field-types-v6610)); an `f32` scalar
variable still occupies an 8-byte slot.

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
> `var a: i64[4]` (32 bytes) instead. See CHANGELOG [6.2.1]. Since 6.7.11 `cyrius lint` warns
> on the constant-offset form — `store64(&a + 8, …)` on a local `var a[4]` — see
> [Linter](#linter).

`N` is any integer **const expression** (6.7.2 — [Constants and `const fn`](#constants-and-const-fn-672)):
a literal, a `const`, an enum constant bare or qualified, `sizeof(T)`, a `const fn` call,
arithmetic — `const BUF = 16;` or `enum Sz { BUF = 16; }` then `var b[BUF]`, `var b[Sz.BUF * 2]`
or `var a: i64[f(4)]`, in a function or at top level. (Until 6.7.2: a literal or an enum
constant only, the qualified form since 6.6.10.) A plain `var` is not a constant and is
refused as a size, as is a negative value. The qualifier must be the constant's OWN enum (since
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

- An element is any **constant expression** — since 6.7.4 each one is a const context
  run by the compile-time evaluator, as an array size or a `const` is: literals, enum
  constants (`A` or `E.A`, the enum declared on either side), consts, `sizeof`, const
  fn calls, arithmetic, comparisons, `&&` / `||`, `!` and the if-expression (`1 << 4`,
  `E.A * 2`, `-5`, `if (K == 2) { 5 } else { 7 }`). An `f64` / `f32` element takes an
  f64 value (a literal or f64 const arithmetic); an `f32` element is the value rounded
  to the nearest `f32`, ties to even — what `f32_from` gives. An integer in a float
  element keeps its bits, with the warning `var g: f64 = 2;` gives; an f64 value in an
  integer element is refused. A `bool[N]` element must be a bool (`true`, a comparison,
  `!x`, a bool const).
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
  elements explicitly. A call to an ordinary fn, a variable or a string is not a
  constant and is refused, in the const context's words.
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

### Subscripts: `a[i]` (6.6.12), `p[i]` (6.7.8)

An element-typed array `var a: T[N]` and a typed pointer `*T` take a subscript — read,
assignment and every compound operator — in a function, at top level, in a `for` step and
inside a closure, for `T` an integer (`i8`..`i64`, `u8`..`u64`), `f64`, `f32` or `bool`:

```
var t: i16[8];
t[i] = 0 - 5;          # stores 2 bytes
t[i] += 1;             # all eleven compound operators (+= -= *= /= %= &= |= ^= <<= >>= >>>=)
var v = t[i];          # -4: an i8/i16/i32 element is sign-extended, u8/u16/u32 zero-extended
if (t[0]) { ... }      # tests the element

fn sum(p: *u8, n): i64 {           # a pointer subscripts too (6.7.8)
    var s = 0;
    for (var i = 0; i < n; i += 1) { s = s + p[i]; }
    return s;
}
var d: f64[4];
d[1] = 2.5;
var r: f64 = d[1] * 2.0;           # an f64 element is an f64 value: a float multiply
```

`a[i]` is exactly the element at `&a + i * sizeof(T)`, and `p[i]` the one at
`p + i * sizeof(T)` — the pointer's VALUE is the base — loaded and stored at T's width: the
same bytes as `load16(&t + i * 2)` / `store16(p + i * 2, v)`, which stay valid (and are what
`var a: i64[N]` code wrote before 6.6.12: `store64(&a + i * 8, v)`). A store truncates to the
element as `store8/16/32` do. There is **no bounds check** — unless the program is built in the
[**bounds-checked mode**](#the-bounds-checked-mode-678) (6.7.8: `#bounds`, `--bounds`), where `a[i]`
is checked against the array's N and `p[i]` for a negative index only (`slice<T>` is the checked
spelling of a pointer with a length). Inside a capturing closure an
array's subscript reads and writes the closure's captured COPY, as `&a` there does; a
captured pointer's subscript reaches the memory it points at.

The element is a value of its declared type, as a variable of `T` would be (6.7.8): an `f64`
is an f64 (`p[1] * 2.0`, `p[1] < 3.0` are float operations); an `f32` is its 4 bytes, in
single precision (`p[0] += q` with `q: f32` stays an f32); a `bool` is a boolean value
(`if (p[i])`, `var b: bool = p[i]`). A store is checked as a store into a field of `T` is: an
`f64` value into an `f32` element rounds to f32, a value that is not a boolean into a `bool`
element is refused (and `OP=` on one, as `b += 1` is), an integer constant into a float
element warns (its integer bits are kept), and a narrow integer element warns when the value
is wider.

The pointer is a name declared `*T`: a `var p: *T` local, a `p: *T` parameter, a `*T` global,
a closure's capture of one, or a generic instance's `p: *T` at its `T` — or a field or a call
DECLARED one (6.7.8): `h.p[i]` for a field `p: *T` (of a local, a global, a `*H`, `a.b.p[i]`,
`self.p[i]`, a call's struct result `mk(4).p[i]`), and `f()[i]`, `g<i32>()[i]`, `o.m()[i]` for a
callee declared `: *T`. The base is evaluated first — the field read, the call made once — and
then the index; `f()[i] = v`, `h.p[i] += 1` and both in a `for` step store through the pointer.
A pointer laundered through an untyped name (`var q = p;`) is a plain word and takes no
subscript. Through a narrow `*T` (`*u8`..`*u32`, `*i8`..`*i32`, `*f32`) `*p` is `p[0]` (6.7.8,
[Pointers](#pointers)).

Refused, by name (`cannot subscript 'a': ...`):

- a **bare** `var a[N]` (and `stack var a[N]`) — it states no element width
  (bytes in a function, slots at top level), so a subscript would be a guess;
  declare `var a: u8[N]` or `var a: i64[N]`, or keep `load*`/`store*` at an
  explicit byte offset;
- an array or pointer whose element is a **struct, pointer, enum, string or vector**
  (`Pt[N]`, `*Pt`, `*T[N]`, `**T`, `Color[N]`, `cstring[N]`, `*Str`, `i8v16[N]`) — keep
  `load*`/`store*` at `&a + i * sizeof(T)`, or step the pointer (`p + i`), whose step is
  `sizeof(T)`. Before 6.6.13 a vector-element array in the leading declaration block was read
  as the scalar its name starts with (`i8v16` as `i8`), so `g[i]` compiled there;
- an **untyped name or a scalar** — it is not a typed array, a `*T` or a slice local;
- a `u128` element, which does not fit one register (use `load64`/`store64`
  on its two halves);
- a **field that is no `*T`** (`cannot subscript field 'n': it is not a *T field`) and a **call
  whose callee is not declared `: *T`** (`cannot subscript the result of 'f': ...`) — a builtin
  (`load64(..)`), `callptr` and `fncallN` included; a parenthesised expression or a literal
  (`(p + 1)[i]`): name the pointer first, `var q: *T = p + 1; q[i]`;
- `a[i][j]` — a subscript's result is an element, not an array — and `&a[i]`: write
  `&a + i * sizeof(T)` (or `p + i`).

⚠ Before 6.7.8 a pointer (`var p: *i64`) and an `f64` / `f32` / `bool` element array were
refused here; `p[i]` was spelled `load16(p + i * 2)` and an `f32[N]` element
`load32(&a + i * 4)`. `h.p[i]` and `f()[i]` were syntax errors (`expected ';', got '['`):
`load32(h.p + i * 4)`.

A `slice<T>` local keeps its own bounds-checked `s[i]` — a signed element sign-extended, as here
(6.7.8) — and since 6.7.8 stores into one too — `s[i] = v`, `s[i] OP= v`, the `for` step
([Slices](#slices)).

## Functions

```
fn add(a, b) {
    return a + b;
}
var r = add(20, 22);   # r = 42
```

- Up to 6 register params, 7+ passed on stack (4 / 5+ on Windows). A fn takes any number of
  parameters on every target; on the cx bytecode target the first 232 integer arguments ride
  registers and the rest the guest stack. ⚠ **Before 6.7.6 a cx call of more than 248 arguments
  was wrong**: cx held every argument in a register, so from 249 arguments the callee read wrong
  values and from 252 cxvm trapped "guest stack overflow" — and a value-form vector argument
  (`f64v2`, `f64v4`, `f32v4`, `i32v4`) beside 14 or more integer arguments overwrote the 14th
  one there, because cx's vector registers were integer argument registers from that point.
- Forward calls work (functions can call functions defined later)
- Relaxed ordering: functions can appear after top-level statements. A `struct`, `enum`, `trait`
  or `impl` cannot — they belong to the declaration section, before the first top-level statement
  (one after it is `unexpected struct` / `enum` / `trait` / `impl`).
- **A fn is defined at top level** (or inside a top-level block). A named `fn` / `async fn` inside
  a fn body, a closure, an `impl` method or a generic body is a compile error naming both
  (`fn 'inner' is defined inside fn 'outer'`) — before 6.6.16 it compiled and crashed (SIGILL /
  SIGSEGV). A local function is a closure: `var sq = |x| x * x;`.
- **An unmatched `}` at module scope is refused** (6.7.9): `error: unmatched '}' at module scope`,
  with a hint that an extra `}` inside a fn closes it early and leaves the fn's own closing brace
  over. Before 6.7.9 the brace silently ended the unit: everything after it was dropped, the build
  said OK, and in a multi-file build the lost definitions surfaced as "undefined" errors in other
  files.
- All functions return a value (`return 0;` if nothing to return) — one value, or two or three
  from a fn declared `: (T1, T2)` / `: (T1, T2, T3)` (see [Multi-Return](#multi-return) and
  [Tuples](#tuples))
- **`return` belongs to a fn body** (6.7.11). A `return` at top level, or in a top-level block (an
  `if`, a loop, a `switch` case), is refused: `return outside a fn body`, reported once, and the
  compile goes on to the next statement. A top-level `break`, `continue`, `defer` and `?` are
  refused the same way: the top level has no frame and no epilogue to return to. A program exits
  with `syscall(60, v);`, by running off the end of its top level, or by returning from a `fn
  main` (the auto-call). A closure body and an `#inline` fn are fn bodies, so a `return` in one
  is fine anywhere. ⚠ Before 6.7.11 a top-level `return` compiled with no diagnostic and did not
  return: x86_64 and PE ran on past it (`return 6; syscall(60, 9);` exited 9), and aarch64 and cx
  hung at it. `ret2(a, b)` returns as `return (a, b);` does, so it is refused the same way outside a
  fn body: `ret2 outside a fn body` (6.7.13, the user's decision of 2026-10-15; it compiled and did not
  return on any target).
- **Calling with the wrong number of arguments is a hard error** (v6.5.1; there is no
  overloading by arity, so a count mismatch is never intentional). The count must lie between
  the fn's required parameters and all of them: a fn that declares parameter defaults
  (`fn f(a, b = 2, c = 3)`, **6.7.7**) takes 1 to 3 arguments and a direct call fills the rest
  from the defaults (`'f' expects 1 to 3 arguments, got 4`; see *Default and named arguments*
  below); any other fn takes exactly its count.
  Since **6.6.5** that applies to the `obj.m(...)` method form as well — it used to build and bind
  the surplus parameter to whatever was in the register. ⚠ One consequence: an `impl` method
  written with **no `self` parameter** can no longer be called through the dot form, because
  the dot form supplies a receiver the method never declared. Call it by its mangled name
  (`Type_method(args)`), which is how the constructor idiom `fn new(a, b)` inside an `impl` is
  written anyway. Since **6.7.7** a **forward call is checked too** — a call to a fn defined
  further down, in a later include or inside a later top-level block, on every call path (a
  plain call, a method, `return f(..)`, an operator): pass 1 records every definition's
  parameter count before any call is compiled. Before 6.7.7 such a call built with a surplus
  argument dropped or a missing one unbound.
- **`x.m()` passes `self` exactly as `T_m(x)` would.** An untyped `self` in an `impl` is a `*T`
  (since **6.7.0**): `self.x` reads and writes the receiver's fields, `T_m(x)` / `T_m(&x)` / `x.m()`
  agree, and arithmetic on it (`self + 8`, `self[i]`, `self += n`) is refused — read fields with
  `self.field`, or declare `self: *T` to step whole elements (see *Traits and impl blocks*). A typed `self: T` follows the parameter rule: a struct is a **value**
  at every width — one of 8 bytes or less arrives in a register, a wider one by address and is
  copied on entry (v6.6.16) — so `fn Odd_sum(self: Odd)` and `fn P3_bump(self: P3)` see a copy,
  and writing `self.a` inside them does not change `x`. Before v6.6.11 the dot form pushed `&x`
  for a small typed `self` too and the method read its fields out of the address; before v6.6.16
  a typed `self` over 8 bytes was the receiver itself, so `x.bump()` changed `x`. A method that
  must change its receiver takes an untyped `self` or `self: *T`.

**Reserved words are a CLASS, not a short list.** `TOKNAME_BUILTIN` in
`src/common/util.cyr` is the single source of truth for the builtin/intrinsic names — count them
from the table (`sed -n '/fn TOKNAME_BUILTIN/,/^}/p' src/common/util.cyr | grep -c 'return "'`)
rather than from any doc, since the table grows — plus the statement keywords. `IS_KEYWORD_TOK`
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

Read the table rather than memorising a subset: the names above are examples, not the list.

**`do` is reserved; `loop` is not (6.7.5).** `do` (the `do … while` statement) is a full
statement keyword: `fn do()`, `var do` and a field named `do` are refused by name. `loop` is
**contextual**, the way `kernel` is (a keyword only as the top-level `kernel;`): it is the
loop statement only when `loop {` starts a statement, and an ordinary identifier everywhere
else, so the `var loop` flags that existing code is full of keep compiling. It is in neither
table, and `cyrius.cyml`'s `[embed]` accepts it as a NAME.

**`dyn` is reserved (6.7.8).** It spells the checked trait-object type (`o: dyn Show`), so
`fn dyn`, `var dyn`, a field or a method named `dyn` are refused by name, and `[embed]` refuses it
as a NAME. ⚠ It was an ordinary identifier before 6.7.8: rename one.

Eleven more names are reserved although that table does not hold them: the
**identifier-spelled intrinsics** `sizeof`, `mulh64` and `fncall0` … `fncall8`. They lex as
ordinary identifiers and the compiler lowers every call to them BY NAME (`_is_ident_intrinsic`
in `src/frontend/parse.cyr`, `_IS_FNCALL_NAME` in `src/frontend/parse_expr.cyr`), so since
6.6.20 declaring one — a fn, a parameter, a closure parameter, a `var` of any kind (local,
global, destructured, `stack`, `secret`), a `for` binding, a `use mod.NAME;` alias (which binds
the bare name), or a payload enum variant (whose constructor is a bare fn) — is refused at the
name:

```
fn mulh64(a, b): i64 { return a + b; }
# error:<source>:1:4: reserved intrinsic name 'mulh64'
#   (cannot be used as an identifier: the compiler lowers every call to it; rename the fn/variable/param)
```

Before 6.6.20 such a declaration was accepted and never honoured: a user `fn mulh64` compiled
but every `mulh64(..)` was still the intrinsic, a user `fn fncall1(a, b)` compiled and
`fncall1(5, 6)` called THROUGH `5`, and a `var sizeof` made every later read a parse error.
The one legitimate declarer is `lib/fnptr.cyr`, whose `fncall0`..`fncall8` definitions are what
make the indirect-call lowering available — an INCLUDED file named `fnptr.cyr` may declare
those. The main source has no file name, so `lib/fnptr.cyr` itself cannot be compiled as the
entry (`cat lib/fnptr.cyr | cycc`, `cyrius build lib/fnptr.cyr`, or the LSP's `cyrius check` on
that open file report its nine definitions); it is a library — include it. A mangled definition
is accepted, so an impl method `x.sizeof()` or a `mod` fn of that name compiles (call it
`m_sizeof()`); re-exposing it under the bare name with `use m.sizeof;` is the refused alias.
A PAYLOAD enum variant spelled with one of the eleven (`mulh64(a, b);`, `fncall1(a);`,
`sizeof();`, heap or `: stack`) is refused: its constructor is registered as a fn under the BARE
variant name and there is no qualified constructor (`E.mulh64(4, 8)` does not parse), so it
declared the intrinsic's name — before 6.6.20 `mulh64(..)` ran the intrinsic instead of
constructing, and `fncall1(5, 6)` faulted. A UNIT variant (`mulh64 = 77;`) declares no fn and
is accepted, but must be read qualified (`E.mulh64`): the bare name parses as the intrinsic, so
`#derive(Serialize)` on that enum fails too.

### Default and named arguments (6.7.7)

A trailing parameter may declare a **default**, and a direct call may **name** its arguments
(user decision, 2026-10-08):

```
const LEVEL = 3;
const fn twice(n): i64 { return n * 2; }

fn tag(a, b = 2, c = twice(LEVEL)): i64 { return a * 100 + b * 10 + c; }

var t1 = tag(1);                  # 126 — b and c from their defaults
var t2 = tag(1, 5);               # 156
var t3 = tag(1, 5, 7);            # 157
var t4 = tag(1, c: 0);            # 120 — b from its default, c by name
var t5 = tag(c: 9, a: 4, b: 5);   # 459 — any order: placed as tag(4, 5, 9)
```

**Defaults**

- **A default is a compile-time constant**: whatever a top-level `const X = …;` takes — a
  literal, a `const`, an enum constant, `sizeof(T)`, a `const fn` call, arithmetic on them
  (see *Constants and `const fn`*) — except a block or an if-expression (declare a const and
  name it). Defaults are **trailing**: every parameter after the first default has one.
- **It is evaluated once, at its definition**: at the end of pass 1, in the top-level scope of
  the file that defines the fn, whether or not anything calls it. A caller's locals never reach
  it (a local `const K` in the caller does not change `b = K`); a const or an enum declared
  further down is fine; a `private` const or `const fn` of the defining file resolves even when
  the call is in another file. A default that names a parameter or type parameter of its own fn
  (`fn g(a, b = a * 2)`) is refused, even when a global of that name exists.
- **The parameter's type decides what its default may be:**

  | Parameter | Its default may be |
  |---|---|
  | untyped | an integer, a bool, or a string (its literal's address, as a positional `"…"` passes) |
  | `i8` … `i64`, `u8` … `u64`, an enum type | an integer in the type's range, or a bool |
  | `bool` | a bool |
  | `f64`, `f32` | a float; an integer only as `0` or an IEEE bit pattern (write `1.0`, not `1`). Into an `f32` it rounds, as every f32 write does |
  | `cstring` | a string, or `0` |
  | `*T` | an integer (`p: *u8 = 0`) |
  | `Str`, a struct, a vector, `u128`, `Result` / `Option` / a tagged enum, a tuple, a type parameter, `self` | nothing: these take no default |

  A float default on an untyped parameter is refused: untyped, a float is only its bits
  (ADR-002), so declare the parameter `: f64` or `: f32`. A `Str` takes none because its
  literal is wrapped (a heap allocation) at every call, which is not a constant.
- **A short call fills from the right.** A direct call passes anywhere from the required
  parameters to all of them (`'tag' expects 1 to 3 arguments, got 4`). The missing trailing ones
  are pushed after the written arguments, in parameter order, each exactly as its literal would
  be, so the callee cannot tell a filled argument from a written one. Pass 1 records every
  definition's defaults before any call is compiled, so a call to a fn defined further down, in
  a later include or inside a later top-level block fills like any other. A generic fn's
  instances fill from their base's defaults; an `async fn` fills at its constructor.

**Named arguments**

- **`f(1, c: 3)`**: after the positional arguments, `name: value` pairs in any order, each
  parameter at most once. A parameter given neither way takes its default; a required one left
  out is refused (`missing argument for parameter 'b' of 'g' (it has no default)`), and so is a
  positional argument after a named one.
- **Evaluated as written, placed in parameter order.** In `w(c: h(), a: k())`, `h()` runs before
  `k()`, and `w` still receives `a` first. A call whose names follow parameter order costs
  nothing extra; an out-of-order call evaluates each argument into a hidden temporary (a frame
  slot in a fn, a hidden global at top level) and then passes them in parameter order.
- **A named argument meets its parameter's rules** exactly as a positional one does: the
  `: cstring` literal check, the bool check, a `: Str` literal's wrap, a struct passed by value,
  an `f32`'s rounding, a vector in its parameter's register. A generic infers `T` through a
  name: `gid(n: 2, x: p)` instantiates the same `gid` as `gid(p, 2)`.
- **Names go to a direct call of a declared fn**: `f(..)`, `o.m(..)` and `T_m(..)`, a
  struct-returning call, a generic, a fn defined later, an `async fn`, and the `const fn` calls
  of a const context. In the dot form `self` is the receiver and cannot be named; in
  `T_m(self: &p, k: 1)` it is an ordinary parameter.
- **Refused, by name:** a name through `fncallN` / `callptr` (they pass by position); a name to
  a builtin (`syscall(n: 60, 3)` keeps its two errors and adds a note saying so); to a variadic
  fn; to a fn defined twice; to a variant constructor (`Ok(v: 1)`: no declared parameter list);
  to a fn with a `_str` / `_int` / `_ptr` overload sibling (a named call is never routed: call the
  one you mean); and a reordered call inside a `#naked` fn, which has no frame for the
  temporaries.

**With the rest of the language**

- **Arity** is checked as min..max (the bullet above). Overloading by arity stays out: a count
  mismatch is never intentional.
- **A call through a fn pointer passes every argument.** `fncallN` and `callptr` pass exactly
  what they are given, so `fncall1(&f, 1)` or `callptr(&f, 1)` to `fn f(a, b = 1, c = 2)` is
  refused ("a call through a fn pointer passes every argument: 'f' takes 3 (defaults fill only
  direct calls)"). Through a pointer held in a variable the compiler cannot see the callee,
  as for any fn: pass all of its parameters.
- **Tail calls.** A `return f(..)` that fills a default or names an argument is an ordinary call,
  not a `jmp` (as in a fn with a `defer`). A `return f(..)` that passes every argument by
  position keeps its `jmp`, so write deep recursion that way.
- **`#inline`.** A fn with defaults is never inlined: `#inline` on one warns `#inline ignored:
  fn has parameter defaults`. A named call to an inlinable fn is an ordinary call, because the
  inlined body binds by position.
- **Const contexts** call a `const fn` with fills and names as run time does: `const N =
  cf(1);`, `const M = cf(1, c: 9);`, `#assert`, an array size, an enum value, a `case` label, a
  local const. A default defined in terms of itself (`const fn cf(a, b = cf(1))`) is refused.
  The arity is the run time's too (6.7.11): a parameter typed `p: Pair<i64, i64>` is ONE
  parameter, so `pick(0, 7)` calls `const fn pick(p: Pair<i64, i64>, b)` and `pick(0, 1, 7)` is
  refused (`a const fn called with the wrong number of arguments`). Before 6.7.11 a const
  context split the type at its comma: the two-argument call was refused and the three-argument
  one bound a phantom parameter named `i64` (user decision (a), 2026-10-13).
- **Methods and traits.** An inherent `impl T` method may declare defaults (`p.m()`,
  `p.m(k: 5)`, `T_m(&p)`). A trait's methods may not, in a required signature or a default
  body, and neither may a method of `impl Trait for T`: the trait's signature is the contract.
  ⚠ **Before 6.7.7 a default in a trait's required signature** (`fn sh(self, n = 1): i64;`)
  **compiled and was ignored**; it is now refused (user decision, 2026-10-09). An operator fn
  (`V2_add`) declares no default: an operator passes exactly its two operands — reported once, at
  the default, when an operator reaches the fn (6.7.11: it was once per use, at the use, and again
  after an `impl Trait for T` method's own refusal). A direct call `V2_add(a, b)` fills it as usual.
- **`cyrius lint`** (`--syntax-only`) accepts a file that calls a sibling module's fn by name, or
  whose default names a sibling's const. The grammar refusals (a positional argument after a
  named one, a name through `fncallN`) still fire there.
- **For stdlib authors:** the compiler itself calls some library fns with a FIXED argument
  count: `alloc`, `vec_len`, `vec_get`, `str_from`, `future_force`, `future_pending`, the
  `_slice_idx_get_N` family and `_slice_idx_addr` (6.7.8, the slice store), the `_chk_*` /
  `_sat_*` overflow helpers, the `_f64_*_polyfill`
  family and `f64v2_make` / `f64v4_make`. None of them may take a default, because such a
  call would never fill it. Row S-R5 of `tests/gates/frontend/default_named_args_checked.sh`
  derives that list from `src/` and fails on a definition that declares one.

Each of these is refused once, at the token it names:

```
fn f(a = 1, b): i64 { return a + b; }
# error: parameter 'b' of 'f' needs a default: it follows one that has a default (defaults are trailing)
fn g(a, b = a * 2): i64 { return b; }
# error: a default must be a compile-time constant: 'a' is a parameter of 'g'
fn h(a, b = if (a > 1) { 2 } else { 3 }): i64 { return b; }
# error: a parameter default cannot hold a block or an if-expression - declare a const and name it
fn k(a, x = 1.5): i64 { return a; }
# error: parameter 'x' of 'k' is untyped: a float default needs it declared ': f64' (or ': f32')
fn m(a, x: f64 = 1): i64 { return a; }
# error: parameter 'x' of 'm' is ': f64': an integer default is its bit pattern - write 1.0
fn n(a, x: u8 = 300): i64 { return a; }
# error: the default 300 does not fit parameter 'x' of 'n' (': u8')
var c = |a, b = 1| a + b;
# error: a closure's parameters take no defaults
tag(1, d: 3);
# error: 'tag' has no parameter named 'd' - its parameters are: a, b, c
tag(1, a: 3);
# error: parameter 'a' of 'tag' is given by position and by name
tag(1, c: 3, b: 4, c: 5);
# error: parameter 'c' of 'tag' is named twice
tag(1, c: 3, 4);
# error: a positional argument cannot follow a named one (in a call to 'tag')
```

The same holds for a default on `self`, defaults in a variadic fn, defaults on a fn defined
twice, and a default that is not one expression (`b = 1 2`).

## Control Flow

```
# If / elif / else
if (x == 1) { ... }
elif (x == 2) { ... }
else { ... }

# While
while (x < 10) { x = x + 1; }

# Loop (6.7.5) — no condition at all; leave it with `break` or `return`.
loop { x = x + 1; if (x == 10) { break; } }

# Do … while (6.7.5) — the body runs once before the first test.
do { x = x + 1; } while (x < 10);

# For — all three clauses (init; cond; step) are required and non-empty.
# Cyrius does not accept `for (;;)` / `for (; c;)` (omitted clauses).
# For an unbounded loop use `loop { … }`, and `while` for a custom-stepped
# one; the idiomatic counted forms are the `for` above and `for x in …`.
for (var i = 0; i < 10; i = i + 1) { ... }

# For-in — a half-open range, or every element of a vec (lib/vec.cyr).
# Works inside a fn AND at top level (since 6.6.8 — before it, a top-level
# for-in crashed or failed to compile). The loop variable belongs to the loop.
for i in 0..10 { ... }          # i = 0, 1, ..., 9
for x in v { ... }              # x = vec_get(v, 0), vec_get(v, 1), ...

# Break / Continue
# `break` leaves the NEAREST ENCLOSING while, loop, do, for, switch or match (v6.5.20 —
#   C semantics; before that a `break` inside a switch/match was a MISCOMPILE, see
#   "Switch" below). It takes no value (`break 5;` is a syntax error).
# `continue` always belongs to the nearest enclosing LOOP. A switch or match in
#   between is transparent to it — `continue` inside a case skips to the loop's next
#   iteration, it does not fall out of the switch. In a `do … while` it goes to the
#   CONDITION (as in C), never straight back to the top.
# Both must have something to leave IN THE SAME FUNCTION (v6.6.7): a `break` with no
#   enclosing loop/switch/match, or a `continue` with no enclosing loop, is a compile
#   error ("break outside a loop or switch" / "continue outside a loop") — including one
#   inside a closure body whose only loop is the ENCLOSING fn's. Before v6.6.7 both
#   compiled clean: `break` became a wild jump and `continue` jumped to the loop top of
#   whichever fn last had a loop.
loop {
    if (done == 1) { break; }
    if (skip == 1) { continue; }
}
```

### `loop` and `do … while` (6.7.5)

`loop { … }` is `while (1) { … }` written plainly: no condition is emitted or tested at its
top (a `while (1)` tests its constant every pass), so `break` and `return` are its only
exits. `do { … } while (c);` runs its body once, then tests `c` after every pass; the
trailing `;` is required. Both are statements — neither produces a value, and `break`
takes none.

```
fn first_square_over(lim): i64 {
    var i = 0;
    loop {
        i = i + 1;
        if (i * i > lim) { return i; }
    }
}

fn digits(n): i64 {
    var d = 0;
    do { d = d + 1; n = n / 10; } while (n > 0);   # digits(0) is 1: the body ran once
    return d;
}
```

- **`continue` in a `do` goes to the condition.** `do { i += 1; if (i < 5) { continue; } }
  while (i < 3);` stops at 3 — the `continue` re-tests `i < 3`; jumping back to the top
  instead would have run on to 5.
- **The `do` body is its own scope**, like every braced body (6.6.17): the condition cannot
  see a `var` declared inside it. `do { var t = next(); } while (t != 0);` is refused with
  `undefined variable 't'` — declare `t` before the `do`.
- **`do` is a reserved word** (it was never an identifier in cyrius or its ecosystem).
  **`loop` is contextual**, like `kernel`: it is the loop statement only as `loop {` at the
  start of a statement, and an ordinary identifier everywhere else — `var loop = 1;`,
  `while (loop == 1) { … loop = 0; }`, a fn, a field or a struct named `loop` all compile as
  they always did. (An identifier at the start of a statement is never followed by `{`, so
  the two never meet.)
- **Anywhere a `while` goes**: inside fns, closures and generic instances, and at top level
  (entry code, as a top-level `while` is). A `switch` / `match` inside one is left by its own
  `break`. A tail call (`return f(..);`) inside one keeps its `jmp` unless the loop takes a
  frame address — a `do`'s condition included, since it is decided after the whole statement.
- **In a `const fn`** both are part of the pure subset (see *Constants and `const fn`*), run by
  the compile-time evaluator under the same 10,000,000-step budget, so an endless `loop` in a
  const context is refused by name rather than hanging the compiler.
- An if-expression branch holds one expression, so a `loop` or `do` there is refused by name
  ("takes one expression, not a statement"), as a `while` is.

## Operators

```
# Arithmetic
+ - * / %

# Comparison (return 1 or 0)
== != < > <= >=

# Bitwise
& | ^ ~ << >> >>>

# Logical (short-circuit, chainable); `!` is logical not (6.7.3)
&&  ||  !

# Conditional (6.7.4): an if-expression — see "The if-expression"
if (c) { a } else { b }

# Explicit overflow operators (v5.6.2)
+%  -%  *%      # wrapping (alias for bare + - * — 2's complement wrap)
+|  -|  *|      # saturating (clamp to i64 min/max via lib/overflow.cyr)
+?  -?  *?      # checked (panic with exit code 57 on overflow)
```

Right shift comes in two forms (v6.4.46): `>>` is a **logical** shift
(zero-fill) and `>>>` is an **arithmetic**, sign-preserving shift. Note
this is the **reverse** of JS/Java, where `>>` is arithmetic and `>>>` is
the zero-fill logical shift.

`~x` is the bitwise complement (all 64 bits flipped) on every target. ⚠ **Before
6.7.6, on the cx bytecode target `~x` was `x`** — the emitter XORed with a register
nothing ever set — so `var x = 6; return ~x + 10;` gave 16 there (3 everywhere else),
and `bitset` / `bitclr`, which complement their mask, kept the bits they were asked to
clear. Pinned by `tests/tcyr/codegen/cx_backend_parity.tcyr`, run natively and on
cxvm by `tests/gates/codegen/cx_backend_parity.sh`.

**`u128` arithmetic (6.7.6).** `+` and `-` on a `u128` carry and borrow across all 128 bits, in
both spellings — `b = b + x` and `b += x`, `b = b - x` and `b -= x` — with a `u128` or an integer
on either side, chains and parentheses included; unary `-b` is `0 - b`. An integer operand is its
64-bit pattern **zero-extended**, the rule a `u128` initializer and a `u128[N]` list element follow:
`b + (0 - 1)` adds 2^64 - 1 — write `b - 1`. A `u128` declaration and a plain assignment take the
whole value (`var a: u128 = c;` and `a = c;` copy all 16 bytes, `var a: u128 = 5;` and `a = 5;` leave
a high word of 0). Every **other**
operator with a `u128` operand — `* / % << >> >>> & | ^ ~`, `*% *| *? +| +? -| -?` and their `OP=`
— is refused by name until it is implemented (`` `*` on u128 'b' is refused - it is not implemented
for u128 yet ``); `lib/bayan.cyr`'s `bayan_u128_*` helpers cover them. A **comparison** — `==`,
`!=`, `<`, `<=`, `>`, `>=` — with a `u128` on either side compares all 128 bits, **unsigned**, against
a `u128` or a zero-extended integer, wherever a comparison is written (a condition, an `&&` / `||`
operand, a value, an if-expression condition): `b < c` is true for `b` 2^64 - 1 and `c` 2^64. A
**truth test** is a comparison with zero, so it reads all 128 bits too: a bare condition (`if (b)`,
`elif`, `while`, `do .. while`, a `for` condition, an if-expression condition), an `&&` / `||`
operand, and `!b` (`b == 0`) — `if (b)` is true for `b` 2^64, whose low word is 0. A `match b` /
`switch (b)` on a `u128` subject compares it on all 128 bits with each arm or case value, an integer
zero-extended (`case -1:` is 2^64 - 1) and a `u128` arm as it is; the subject is read once, before
any arm is tested. A `match n` on an INTEGER subject compares a `u128` arm on all 128 bits too,
the subject zero-extended, as `n == b` does: `match 0 { b => .. }` does not take the arm for `b`
2^64. A `u128` read where an integer is expected — an argument, `var n = b`,
`return b` — is its low word, as it always was. A `u128` parameter is an 8-byte slot (the low word).
Before 6.7.6 neither spelling carried (both worked on the low word and left the high word alone),
the other operators did the same silently, a comparison read the low words as SIGNED integers, a
truth test and a `match` / `switch` subject (and a `u128` arm of an integer `match`) read the low
word, a plain `b = c` / `b = 5` stored the
low word and kept the old high word, and a `u128` local initializer stored its value into BOTH
halves.

Wrapping ops (`+%` etc.) document intent at the call site that a wrap is
expected — bytes are identical to the bare operator. Saturating and
checked variants compile to calls into `lib/overflow.cyr` helpers
(`_sat_add_i64`, `_chk_add_i64`, etc.). Checked-panic uses `syscall(60, 57)`;
exit code 57 is reserved to distinguish overflow panics from POSIX signal
exits and assert-summary returns.

### Compound assignment: every lvalue (6.7.5)

`x OP= e` takes eleven operators — `+= -= *= /= %= &= |= ^= <<= >>= >>>=` (`>>>=`, the
arithmetic shift, since 6.7.5) — on **every lvalue**: a variable, a subscript `a[i]`, a field at
any depth (`p.x`, `o.i.b`, `a.next.v` through a `*T` field, `h.name.len` through a `Str`, a
slice's `s.len`), through a `*T` local, parameter or global, `self: *T`, a field or element of a
closure capture, and `*p`. A closure captures by value, so `|d| { h.n += d; }` and `a[1] += d`
change the closure's own copy (it persists from call to call; the enclosing fn's `h` is untouched)
and `p.n += d` through a captured `*T` reaches the pointee. A captured NAME is not an lvalue in
the closure: `x += d`, like `x = x + d`, a `for` init or step and `a, x = f()`, is refused naming the
capture — ``'x' is captured by value; a captured name is not assignable in a closure — copy it into a
local (`var y = x;`)`` (6.7.11; it said `undefined variable 'x'`, though `x` is readable in the same
body). `x = v` is reported at `x`, before `v` is parsed (6.7.11: a whole tuple `v` was refused a
second time). It works in a statement, at
top level, in a classic-`for` step (`for (h.n = 0; h.n < 5;
h.n += 1)` — a field or `*p` step takes `=` too, and a struct-valued field step copies the whole
struct) and, on a local, in a `const fn`. Before 6.7.5 a field, `*p`, `>>>=` and a field or `*p`
`for` step were all syntax errors (`expected '=', got '+'`).

It operates at the place's width and kind, exactly as reading it does: an `i8` / `i16` / `i32`
field or element is loaded sign-extended and stored at its own width (so it wraps there),
`+= -= *= /=` on an `f64` / `f32` place are float operations with the same warnings as
`x = x + e`, `p += n` on a `*T` place steps `sizeof(T)`, and `*p OP= v` works on the element
through a narrow `*T` and on a word otherwise, as `*p` reads (6.7.8; see [Pointers](#pointers)).

```
struct H { n; m; }
var h = H { 1, 2 };
h.n += 4;            # 5
h.m <<= 3;           # 16
var t: i32[4];
t[1] -= 7;           # -7, stored in 4 bytes
var v = 0 - 64;
v >>>= 2;            # -16: the sign is kept (`>>=` would fill with zeros)
```

⚠ **The address is taken first.** A compound assignment computes the lvalue's address ONCE,
BEFORE it evaluates the right-hand side — as `a[i] OP= v` always has — while a plain assignment
`x.f = e` evaluates `e` first and then stores. The two differ only when the right-hand side moves
the lvalue:

```
struct H { n; m; }
var A = H { 10, 0 };
var B = H { 20, 0 };
var GP: *H = &A;
fn repoint(): i64 { GP = &B; return 1; }
GP.n += repoint();             # A.n becomes 11: GP named A when the address was taken
```

From the same start, `GP.n = GP.n + repoint();` reads `A.n` (10), moves `GP`, and writes 11 into
`B.n`.

Refused by name: a compound assignment to a **struct value** — a struct variable (`a += b`, a
local of any size, a by-value parameter or a global) or a struct-typed field (`r.tl += 1`) — which
used to operate on the struct's first word and never call an overloaded `P_add` (13 where
`a = a + b` gives 33): write `a = a + b`. Likewise a `bool` (variable or field: its result is not a
bool — write `b = b && c`), a const or an enum constant, and a field of a call's result
(`mk(3).n += 1`: the result is a temporary; a `: *T` call's `gp().n += 1` is a pointer's, 6.7.13). A handle keeps its pointer arithmetic: `p += 1` on a
`*T` steps `sizeof(T)`, and a pointer-mode struct variable or a `Str` is an address.

Since 6.7.6 the same refusal covers the other values that are not one integer or float, each of
which operated on its first word: a **SIMD vector** (`v += w` on an `i64v2` / `f64v2` … local or
parameter added to lane 0 only — use the packed-op builtins), a **typed array** (`var a: i64[4];
a += 8` added to `a[0]`, an `f64[N]` added bit patterns — write `a[i] += b`) and a **slice**
(`s += 1` moved `.ptr` — write `s.ptr += 1` / `s.len -= 1`) — and, also since 6.7.6, a **bare
array** (`var b[N]` — local, global or in static storage — and `stack var b[N]`: `b += 8` added to
its first word; it has no element type, so write the word, `store64(&b, load64(&b) + 8)`). On a
`u128`, `b += x` and `b -= x` are `b = b + x` / `b = b - x`, carrying across all 128 bits; every
other `OP=` on a `u128` is refused (see [`u128` arithmetic](#operators)), and its right-hand side
is not parsed (6.7.11: a `: stack` pair there was refused a second time).

A plain assignment to a whole **typed array** is refused by name too (6.7.6): `var a: i64[4];
a = 8;` (or `a = b`) stored into `a[0]`, silently — assign an element, `a[i] = v`. A bare array's
`b = v` still writes its first word.

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
*p += 1;               # 100: a word load, add and store (6.7.5)

# Typed pointers (auto-scale arithmetic)
var buf[64];
store64(&buf, 10);
store64(&buf + 8, 20);
var p: *i64 = &buf;
var a = *p;            # 10
var b = *(p + 1);      # 20 (adds 8 bytes, not 1)

# A narrow pointee is read and written at its width (6.7.8)
var e: i32[2];
e[1] = 7;
var q: *i32 = &e;
*q = 0 - 5;            # stores 4 bytes: e[1] stays 7
*(q + 1) += 3;         # e[1] = 10
var c = *q;            # -5: an i32 element is sign-extended
```

A `*T` variable is an 8-byte address whatever `T` is. **Through a narrow `*T` — `*u8` / `*i8`,
`*u16` / `*i16`, `*u32` / `*i32`, `*f32` — `*p` is the ELEMENT** (6.7.8), exactly as `p[0]` is
([Subscripts](#subscripts-ai-6612-pi-678)): a read loads T's bytes, an iN sign-extended, a uN
zero-extended, an `f32` its 4 bytes typed f32 (`*p + x` with `x: f32` is an f32 add, `-*p`
flips its sign bit); `*p = v` stores T's bytes (an `f64` into a `*f32` rounds to f32, an integer constant
into one warns, a wider integer into a narrow one warns "narrowing"); `*p OP= v` (6.7.5) loads,
combines and stores at that width, so it wraps there (an `f32` combines in single precision). The
pointer is narrow wherever the compiler knows it is one: a name declared `*T` (a local, a parameter,
a global, a closure capture, a generic instance's at its `T`), a field declared `*T` (`*h.p`,
`*self.p`, `*mk(4).p`), a call declared `: *T` (`*f()`, `*g<i16>(k)`, `*o.m()`), `p + n`, `p - n`,
`n + p`, parenthesised, an if-expression whose branches all are, or the dereference of a pointer to
one (`*pp` of a `pp: **T`, below). **Every other operand is a WORD
address, read and written 8 bytes as before**: an untyped name (`var w = p;` is the spelling for a
word through a typed pointer), a `*i64` / `*u64` / `*f64` / `*bool` (`*p` through a `*f64` is the
untyped word — `p[0]` is the typed spelling), and a value that is no longer that pointer: a
bitwise or comparison result (`*(m & p)`), a negation, a call result's untyped field (`*mk(p).n`).
**`*pp` of a `pp: **T` is a `*T`** (6.7.13, the user's decision D9 (a), 2026-10-15) — through a `**T`
local, parameter, global, closure capture, field, `: **T` call, generic instance or `pp + n`: `*pp + n`
steps `n` elements of `T` and `*pp += n` steps them too, `*pp - *qq` is an element count (refused, as for
any two pointers, when the element sizes differ), `var q: *T = *pp;` / `q = *pp;` are silent, and `**pp`
through a narrow `T` (`**u8`, `**i32`, `**f32`) is the element, read and written at its width. A
`***T`'s `*ppp` is a `**T` (it steps a pointer's 8) and `**ppp` a `*T`. Through 6.7.12 `*pp` was the
untyped word: `*pp + 1` stepped one BYTE, `**pp` read and wrote 8 bytes whatever `T`, and the
declaration warned *assigning non-pointer to typed pointer*. A program may name at most 126 distinct
pointees of a pointer to a pointer (*too many pointer-to-pointer pointee types*).
Through a pointer to a STRUCT (`p: *S`) `*p` is the struct value (6.7.10) and `*p = v` copies the struct
(6.7.11 — see *A store through a `*S` copies the struct*).
`n + p` on a `*u8` / `*i8` is that pointer, as `p + n` is (6.7.9): `*(1 + p)` is the element,
`var q: *u8 = 1 + p;` is silent and `(1 + p) - q` is a pointer difference, refused when `q` points
at another size (before 6.7.9 a one-byte `n + p` was no typed pointer: that declaration warned and
the difference was a byte count). A pointer to a one-byte STRUCT (`pb: *B1`) is such a pointer too
(6.7.11, the user's decision of 2026-10-13): `m + pb` and `0 + pb` are that pointer, `var r: *B1 = 1 +
pb;` is silent and `(1 + pb) - q32` is refused as `(pb + 1) - q32` is (through 6.7.10 the
difference was a byte count and the declaration warned). So is `&x`, a byte address, on either side
of `+` (6.7.11, the user's decision of 2026-10-13): `n + &x` is the pointer `&x + n` is, so
`var r: *u32 = 4 + &B;` is silent and `(4 + &B) - q32` is refused (through 6.7.10 the first warned
and the second was a byte difference). `load8` / `store16` / … stay valid for an
explicit width. **`&x` takes the address of a NAME** — a local, a parameter, a global, a closure
capture or a fn — never of a field or an element: `&x.f` (6.7.13, the user's decision D3 (b),
2026-10-15; *the address of a field is not taken - write `&x + offset` or reach it through a `*T`*)
and `&a[i]` are refused by name — write `&x + offset` (`&a + i * sizeof(T)`), or reach the field
through a pointer (`var p: *S = &x; p.f`). Through 6.7.12 `&x.f` failed to parse at its `.`
(`expected ')', got '.'`). ⚠ Before
6.7.8 every `*p` loaded 8 bytes and every `*p = v` / `*p OP= v` stored 8, whatever `T`: `*q = 5`
through a `*i32` zeroed the next element, `*p = 1.5` through a `*f32` stored 1.5's f64 bits as a
word, `*s` on a `*u8` string read eight characters. `T` must name a type
([Type names](#type-names-6616)). **`p + n`, `p - n`, `p += n` and `p -= n` step
`sizeof(T)` elements, wherever `p` is declared** — a local, a parameter, a global, a
closure capture, a struct field or a fn result: `*u8` / `*i8` step 1, `*i16` 2, `*i32` /
`*u32` / `*f32` 4, `*i64` 8, `*Pt` `sizeof(Pt)`, a pointer to a pointer 8. A `*T` value
is a pointer, not a `T`: `p + 1` on a `p: *f32` parameter is address arithmetic (not a
float add), and on a `p: *Pt` parameter it is not `Pt`'s `+` overload — `p.x` still reads
through it. To step in bytes, use an untyped address (`&buf + i * 4`, or `var q = p;`).
`n + p` steps like `p + n`. A narrow scalar — a `u8` / `i8` / … / `i32` local, global or parameter —
is an integer, never a pointer: `w - q` is `n - p`, `w + q` steps `q`'s `sizeof(T)`, and
`var r: *u32 = w;` warns. (Through 6.7.10 a narrow LOCAL was a one-byte pointer to these rules:
`w - q32` was refused as a pointer difference, `var r: *u32 = w;` was silent, and with `q: *i32`
`w + q` added `w` unscaled — `q` + 1 for `w = 1`.) `q - p` of two pointers with the same element size is the number
of elements between them (`(q - p) / sizeof(T)`, a plain integer); two pointers with
different element sizes (`*i64 - *u8`, `*Pt - &buf`) are a compile error — there is no
honest unit — so subtract plain addresses for a byte count. A call's result is a pointer
only when the fn declares `: *T`; `f(p) + 1` adds 1 whatever `p` is. So is every other value
computed FROM a pointer a plain integer: a comparison, `&&` / `||`, `* / % << >> >>>`, `& | ^`,
the saturating / checked `+| +? -| -?` (integer operators: `q +| 1` adds one byte, and the sum is
no pointer), unary `-` / `~`, `p?`, `await f`, an operator fn's result (unless the operator fn declares `: *T`:
then, as its free call `V_add(v, p)` does, it steps by `T`) and a field that is no `*T` — `(x == p) + 1`,
`(k * p) + 1`, `(m & p) + 1`, `(-p) + 1` and `mk(p).n + 1` add 1, and such a value assigned to a
`*T` warns "assigning non-pointer to typed pointer". (Before 6.7.9 the pointer's step leaked
through them: with `p: *i32`, `(x == p) + 100` was 401; before 6.7.11 through `await f` too, in a
coroutine or not: with `f: *i32`, `(await f) + 1` added 4, and `+| +? -| -?` handed their sum the
left operand's step: with `q: *i32`, `(q +| 1) + 1` was `q` + 5 bytes, now + 2 — the user's decision
of 2026-10-13.) (Before 6.6.17,
`q - p` scaled `q`'s partner and read garbage, `n + p` stepped 1, and a call's result kept
its last argument's step.)
⚠ Before 6.6.17 the step depended on where `p` was declared: a local `*i8` / `*i16` /
`*i32` stepped 1 and every other local `*T` 8 (`*u8` too), a parameter or a captured
`*T` 1, a global 8 in the leading declaration block and 1 / 2 / 4 / 8 by `T` after the
first statement, and `p += n` 1 everywhere. No source in the ecosystem declared a `*T`,
so the rule changed without a transition error.
⛔ Before 6.6.16 a **local** `var p: *i8` / `*i16` / `*i32` was stored in 1 / 2 / 4
bytes, truncating the address: `p == &buf` was false and `load8(p + 1)` crashed.

**`&p` of a pointer is the slot that holds it** — a `*T` local, global or parameter, an untyped
impl `self` — so `load64(&p)` is `p` and `store64(&p, o)` re-points `p` (6.7.9). ⚠ From 6.6.6 to
6.7.8 a `*T` PARAMETER whose `T` is a struct over 8 bytes was the exception: its `&p` was `p`
itself, the pointee, so `load64(&p)` read the struct's first field and `store64(&p, o)` wrote `o`
into the caller's struct. (A by-value struct parameter is its own copy, so its `&q` is the copy's
address — see [Returning a struct by value](#returning-a-struct-by-value-v666).)

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
(`first(h).next.val`, `first(h).m(..)`), and since 6.7.11 that of a METHOD declared `: *Struct`
(`h.get().b`, `h.get().m(..)`, through a `dyn` too). Before 6.6.17 only a parameter did; a `*Node`
local or global was "no struct type in scope", and such a call's result "does not return a struct"
(a method's until 6.7.11).
A struct VALUE assigned to a `*Struct` local or parameter copies INTO the pointee (`p = l`,
`p = mk(..)`), and `l = p` copies the pointee into the struct value `l`, at every size (6.7.10 —
see [Where a struct lives](#where-a-struct-lives-v665)).

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
p.x += 8;               # 50: every compound operator, at the field's width (6.7.5)

# Nested structs
struct Rect { tl: Point; br: Point; }
var r = Rect { 0, 0, 10, 5 };
var w = r.br.x - r.tl.x;   # 10
var a = Point { 1, 2 };
var r2 = Rect { a, 10, 5 };  # a nested field also takes a whole struct value (v6.6.12)
```

⚠ Known defect (6.7.9): the **named** literal is refused in the declaration section — at top level
before the first top-level statement, `var q = Point { x: 10, y: 20 };` reports `undefined variable
'x'`. It works inside a fn and after the first top-level statement; in the declaration section,
write the positional form (`Point { 10, 20 }`). Tracked in `docs/development/issues/` (the declaration-zone named struct
literal).

A tuple (`(i64, f64)`, 6.7.7) is an anonymous struct of 8-byte slots named `0`, `1`, …: what this
section says about a struct value holds for it. See [Tuples](#tuples).

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

A field takes every compound operator (6.7.5): `p.x += 1`, `r.br.x *= 2`, `n.next.val -= 1`, an
`f64` field's `p.x *= 2.0` as a float operation — see
[Compound assignment](#compound-assignment-every-lvalue-675). A `bool` field (`b.ok += 1`) and a
struct-typed field (`r.tl += 1`: a struct value is not an integer) are refused by name, as a bool
or struct variable is.

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
itself (`mk(3).total()` calls `Box_total`, as a value or as the statement `mk(3).total();`) and,
since 6.7.0, to a nested field of it (`mk(3).v.sum()` calls `Pt_sum` with the field's address, as
`b.v.sum()` does — see *Traits and impl blocks*). At top level there is no frame:
`var G = mk(3).n;` is refused by name — call it inside a fn. A field of a call to a fn that
does not return a struct is refused too, and so is an assignment to a result's field
(`mk(3).n = 5;`, `mk(3).n += 1;`, and a method's, `b.mk(4).n = 5;` — which was
`expected ';', got '='` until 6.7.5): the result is a temporary. A call declared `: *Struct` returns
no temporary but a pointer, so a field of its result IS an lvalue (6.7.13, the user's decision D8 (a),
2026-10-15): `gp().n = 5;`, `gp().m += 5;` (the address computed once), `gp().h.n = 5;`, `gpg<H>().n =
5;` and a method's `o.gp().n = 5;` store through the returned pointer, as `var p: *H = gp(); p.n = 5;`
does — through 6.7.12 they were refused as a temporary. An untyped `var p = gp();` is still an untyped
word (`p.n` needs `var p: *H = gp();`).

⚠ Before v6.6.12 a chain stopped after two levels — `n.v.v.x` was the syntax error
`expected ';', got '.'` — and a `.field` after a call was `expected ')', got '.'` in every
position; `var s = mk(3).n + 1;` also typed `s` as `Box` and looked for an undefined `Box_add`.
All of these were loud: nothing compiled wrong.

A **method's** result takes `.field` and `.method(..)` the same way, chained to any depth, as a
value or as a bare statement (since 6.6.17): `var u: Str = s.clone().cat(t);`,
`p.bump().bump().sum()`, `p.big().c`. Each link's result is held like a call's (a frame
temporary), so the receiver is untouched. A method declared `: *Struct` is a pointer, as a free
call's `*Struct` result is: `h.get().b`, `h.get().q.b`, `h.get().m(..)` read and call through it, in
a fn and at top level (6.7.11; it was refused, "it does not return a struct"), and `h.get().b = 5;`
stores through it as `get2(&h).b = 5;` does (6.7.13; both were refused as a temporary). At top level a chain on a struct-returning method is refused by
name, as a call result's field is, and a chain on a method that returns neither a struct nor a
`*Struct` is `cannot take a field of the result of 'T_m': it does not return a struct`. Before 6.6.17
the `.` after a method call was `expected ';', got '.'` in every position.

### Field types (v6.6.10)

A field is untyped (`x;`, 8 bytes, i64) or annotated `x: T`, where `T` is one of:

| `T` | Bytes | Notes |
|-----|-------|-------|
| `i8` / `i16` / `i32` | 1 / 2 / 4 | Narrow and **signed**: `p.x` sign-extends. |
| `i64` | 8 | The same as no annotation. |
| `u8` / `u16` / `u32` | 1 / 2 / 4 | Narrow and **unsigned** (6.7.10): `p.x` zero-extends, and a write or an `OP=` stores only the field's bytes, so it wraps there (`c.r = 250; c.r += 10;` gives 4). |
| `u64` | 8 | |
| `f64` | 8 | **Typed** — `p.x + p.y`, `p.x * 2.0`, `-p.x` and `p.x < p.y` are float operations. |
| `f32` | 4 | Typed (single-precision arithmetic): its binary32 bits (6.7.10). |
| `bool`, `cstring`, `Result`, `Option`, `Tagged`, an enum | 8 | An enum may be declared before or after the struct. `bool` since 6.6.16 (it was refused). |
| a struct or union | its size | Stored **inline**. It must be declared ABOVE the struct that uses it. |
| `Vec` / `Vec<T>` | 8 | A handle. A bare `Vec` is the file's own `struct Vec` / `union Vec` when one is declared above the field; declared below it, the field is refused by name (6.7.13, below). |
| `*T` (any type name `T`) | 8 | A pointer: `p.f + n` steps `sizeof(T)` (see [Pointers](#pointers)). Since 6.6.17. |
| a tuple `(T1, T2, ..)` | 8 × elements | Stored **inline**, an anonymous struct of 8-byte slots: `h.p.0`, `h.p = (1, 2);`. Since 6.7.7 — see [Tuples](#tuples). |
| `dyn Tr` | 16 | Two opaque words, stored inline; formed or copied whole (`h.o = &p;`) and called through (`h.o.m()`). A struct local holding one is declared with its value. Not in a generic struct, a union or a `#derive`d struct. Since 6.7.8 — see [Trait objects](#trait-objects-dyn-678). |
| a type parameter of the struct being declared (`struct Box<T> { v: T; }`) | per instance | |

⚠ **The field widths are layout (and ABI), and they are packed** — every field sits right after
the one before it, with no padding, the rule `i8` / `i16` / `i32` fields have always followed
(`struct { a: i8; b: i64; }` is 9 bytes). Since 6.7.10 `u8` / `u16` / `u32` and `f32` follow it
too; through 6.7.9 each took 8 bytes (an `f32` in the low half), so a struct that declares one
changed size and field offsets:

```cyrius
struct C4 { r: u8; g: u8; b: u8; a: u8; }    # 4 bytes (32 through 6.7.9)
struct UB { a: u8; b: i64; }                 # 9 bytes, b at offset 1 (16, b at 8)
struct F2 { x: f32; y: f32; }                # 8 bytes (16)
union  UU { a: u8; b: u32; c: f32; }         # 4 bytes (8)
```

Everything that keys on a struct's size follows the new one: `sizeof`, a `*C4` steps 4, `C4[2]`
is 8 bytes, and the by-value class (a struct of 8 bytes or less is passed and returned in one
register, one of 9-16 in two) with what keys on it — `dyn`'s `self: T` refusal now meets a
struct that shrinks to 8 bytes or less (see [Trait objects](#trait-objects-dyn-678)), and the
refusals that key on a size over 8 bytes stop applying to it: an if-expression branch, an
`async fn`'s by-value parameter, a top-level call result (`var G: C4 = mk4(9);`). Code that
reached such a struct by hand — `load64(p + 8)` for the second field, a literal size,
`load64(&s + 8)` at a narrow field's offset (it now reads the next fields too), a file or wire format
written with `sizeof` — must be re-checked; the fields, `sizeof` and the `#derive(accessors)`
functions follow the layout. **Packed means unaligned:** a `u32` / `f32` after a `u8` sits at
offset 1. A plain field read or write is fine on every target, but an atomic or a futex word
needs its natural alignment — declare it first, or pad explicitly (`_pad: u8; _pad2: u16;`). A
struct redefined with another narrow kind of the same width (`i8` vs `u8`, `i32` vs `f32`)
warns, as one with another layout does.

Anything else is a **compile error that names the type**. Before v6.6.10 an unknown name was
silently an 8-byte i64, and three cases were silent miscompiles:

* `a: Nonexist` compiled (a typo, or a missing `include`).
* A struct used as a field type **above** its own declaration got a different layout than the
  same text below it: `struct A { b: B; x; }` written before `struct B { p; q; }` made A 16
  bytes instead of 24, and `a.b` read 8 bytes of a 16-byte value. It now reports
  `struct field type 'B' is declared after its use; declare it before 'A'`. Since 6.7.13 a bare
  `Vec` field follows the same rule: with the file's own `struct Vec` (or `union Vec`) declared
  below the field it is refused with the same words, where it was silently lib's 8-byte handle (the
  same declaration above the field made it the struct: two layouts for one text). Declared above,
  it is that struct; with no `Vec` of the file's own, the handle.
* `v: i16v8` (a vector type) registered as a 2-byte `i16` field. A vector cannot be a field
  type.

A struct cannot contain itself (`struct Node { next: Node; }` crashed the compiler before
v6.6.10); a link to another node is a pointer field, `next: *Node` (6.6.17 — see
[Pointers](#pointers)), or an untyped `i64` one.

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

⚠ **The handle line: one rule at every size, for locals and globals (6.7.10).** A struct
variable declared from a struct VALUE of its type holds its own bytes (it is *inline*); declared
from anything else it is a *handle*, whose slot holds the address of the struct it reads and
writes. A struct value is a literal; another inline struct of the type — a local, a by-value
parameter, a global, a closure's captured copy of one, parenthesised or not; a struct-typed field
(`b.v`); a `*T` name, or a dereference of a `*T` in any spelling — `*p`, `(*p)`, `*(p + 1)`,
`*h.p`, `*gp()`, `*w.mp()` with `p`, `h.p`, `gp()`, `w.mp()` typed `*T` (copied through the
pointer), and since 6.7.13 `*(&x)` / `*&x` of an inline `x`; and a call, method, operator or if-expression that returns the struct (a generic or a
parenthesised call too, and since 6.7.11 a call through `fncallN(&f, ..)` / `callptr(&f, ..)` whose
callee `f` returns it). Everything else is a handle: `alloc(..)`, `&x`, an untyped value (a
dereference of one, `*x`, included), a call returning a `*T` or an untyped value (a call through a
fn pointer held in a variable included: see *Returning a struct by value*), an integer —
`var q: S8 = 0;` is a NULL handle, and `var a: Num = 1;` a handle to address 1, so `a + b` is
pointer arithmetic with no `Num_add` dispatch (declare it from a struct value, `Num { 1 }` or
`mkn(1)`, for the operator) — and another handle, a captured one included, which **binds**: the
new name is a second handle to the same object. A struct value of ANOTHER
type is refused by name, a dereference of a `*U` included — `*pu`, `(*pu)`, `*gu()`, `*w.pu`
(`cannot copy 'pu' into a variable of a different struct/vector type: 'q'`).

```cyrius
struct S8 { v; }
fn demo(): i64 {
    var h = alloc(8);
    store64(h, 7);
    var q: S8 = h;           # a handle: q.v reads h's word
    q.v = q.v + 30;          # writes the heap object
    var c: S8 = q;           # binds: c is a second handle to it
    var l: S8 = S8 { 1 };    # inline (a literal)
    l = q;                   # copies the struct q points at
    return load64(h) + c.v + l.v;   # 37 + 37 + 37 = 111
}
```

Through 6.7.9 the line held only over 8 bytes: a struct local or global of 8 bytes or less was
inline whatever its initialiser, so `var q: S8 = h;` (or `= alloc(8)`, `= &s`, `= gp()` with
`fn gp(): *S8`, `= 1`) held the ADDRESS as `q.v`, and `q.v = 5` never reached the object —
silently (`demo` read the address back as `q.v`). And over 8 bytes `var q: P3 = *p;` was a
handle holding the word `*p` read, so its first field write crashed. **A handle used as a value
is the struct it points at**, at every size: passed to a by-value struct parameter, returned from
a fn declared `: S8`, an operator's right operand, an if-expression branch, and either side of a
copy (below), in a fn and at top level. A closure captures the handle and reads through it. As
an operator's LEFT operand a handle is pointer arithmetic (no dispatch), and `&q` is its slot.

An operator whose LEFT operand is a struct-typed FIELD or a DEREFERENCE dispatches (6.7.10): `var q:
S8 = w.s + a;` calls `S8_add` and copies its result, as `l + a` with a struct variable `l` does
(see *Parentheses, struct operands and `Str` fields*). Through 6.7.9 the first words were added,
and in 6.7.10 before the fix `q` was a handle holding that sum.

⚠ Not yet settled: a global declared from a `*T` GLOBAL's name (`var G: S8 = P;`) keeps its 6.7.9
layout — inline, holding the pointer word, at 8 bytes or less; a handle bound to `P`'s object
over 8.

⚠ **An assignment between a pointer and a struct copies the struct (v6.6.16).** Call a variable
whose slot holds a struct's ADDRESS a *handle*: a pointer-mode local (`var a: P3 = alloc(24);`),
a pointer-mode global (`var G: P3 = 0;` then `G = alloc(24);`), or a `*P3` local or parameter.
For a struct of any size (6.7.10; through 6.7.9 only over 8 bytes):

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
`Option` and `Tagged` (heap handles by name) are unchanged (an inline `Str` assigned into a `Str` handle
binds it to its header: see *An inline `Str` passes its header*). Through 6.7.9 a struct of 8 bytes or
less was outside the rule: no struct variable of that size was a handle (the handle line above),
and a `*T` of one was no struct operand, so `l = p` and `G = p` with `p: *S8` stored the POINTER
into the first field, and `q = r` through a `q: *S8` parameter rebound `q` (the caller's struct
never changed) — each silently; a copy between two different struct types through such a `*T`
(`l = pu`) compiled and stored a word, and is refused now, as over 8 bytes. A `*T` GLOBAL, a call
or method declared `: *T` and a `*T` field were no copy operands at ANY size until 6.7.10: `l =
GP`, `G = GP`, `l = gp()` and `l = w.p` stored the pointer word into the first field, over 8 bytes
too. They copy the struct into a struct value now, as a `*T` local does (a `*U` of another struct
refused by name); into a handle or a `*T` they rebind (`q = GP` through `q: *S` repoints `q`). So
does pointer arithmetic on a `*T` (`l = p + 1`, `l = (p + 1)`, `l = 1 + GP`, `G = q - 1`: the struct
the result points at), which stored the pointer word too; `q = q + 1` through a `*T` still steps it.
A GENERIC call declared `: *T` is such a source too (6.7.11), with T bound by its type arguments or
inferred from its arguments: `l = gp<S>()`, `var q: S = *gp<S>()`, `take(*gp<S>())`, `a - *gp<S>()` and
`gp<S>().v` read the `S` it points at, as `fn gp(): *S` does; a `*U` instance is refused by name (naming
the call). Through 6.7.10 the instance recorded T's step but not its struct: the pointer word was stored,
the dereferences faulted, and `gp<S>().v` was refused.
A `*T` GLOBAL is a copy destination too (6.7.11, the user's decision of 2026-10-13): `GP = l` copies the
struct value `l` — a variable, a by-value parameter, a call, a field `w.s`, `*p`, a method, an operator
result — into the struct `GP` points at, as `q = l` does through a `*T` local or parameter, in a fn, at top
level and in a for step; `GP` still points where it did. `GP = q` from another `*T` (a local, a global, a
`: *T` call, a field) or a handle, and `GP = &x` / `GP = alloc(..)` / `GP = 0`, rebind it; a struct of
another type is refused by name; at top level a call, method or operator result over 8 bytes has no frame
to land in and is refused, as into a struct global. Through 6.7.10 `GP = l` stored `l`'s first word into
`GP` itself — a wild pointer, silently.
Into a struct-typed FIELD these sources copy too (6.7.11): `o.s = GP`, `o.s = gp()`, `o.s = w.p`,
`o.s = GP + 0`, `o.s = (gp())`, through a `*O` (`po.s = GP`), at top level and in a for step; a `*U` of
another struct is refused by name (`cannot copy 'GU' into a struct field of a different struct type`).
Through 6.7.10 the field kept the pointer word, silently.
An ASSIGNMENT from a dereference copies the struct, as the declaration `var l2: S = *p;` does (6.7.11):
`l = *p`, `G = *p`, `o.s = *p` (through a `*O` too), and `q = *p` into the pointee of a `*S` or a handle
(as `q = l`), in any spelling — `(*p)`, `*(p + 1)`, `*gp()`, `*w.p` — at top level and in a for step; a
`*U` of another struct is refused by name. Through 6.7.10 it stored the first word (`q = *p` rebound `q`
to it), with a false "assigning non-pointer to typed pointer" warning.

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

An untyped `var x = mk(9);` takes the struct's type from the call, and so does `var x = (mk(9));`
or `((mk(9)))`: parentheses around the whole call are transparent (6.7.11; before, `x` held the
struct's first word, `x.z` was refused and `take(x)` passed that word as the struct's address —
a crash), at every size since 6.7.13: `var x = (mk1());` with `mk1` returning an 8-byte struct is
that struct (`x.a` was refused, *no struct type in scope*), and `var x = (f());` with `f` returning
`: f64` is an f64, as `var x = f();` is. An annotation that names no struct is never replaced by the callee's struct:
`var x: i64 = mk(9);` — or `: u8`, `: f64`, `: bool`, any scalar or handle type — from a fn
returning a struct over 8 bytes is a compile error since 6.7.11, at the call:

```
error: cannot initialise 'x: i64' from 'mk', which returns the struct 'P3' - declare 'x: P3' or bind a field
```

Before 6.7.11 the declaration silently became a `P3` behind its annotation (`x.y` compiled, and a
`u8` held a value over 255). Declare the struct (`var x: P3 = mk(9);`) or bind the field you want
(`var x: i64 = mk(9).z;`). A struct of 8 bytes or less and a `Str` are one word, which a scalar
keeps; inside a generic fn, `var x: T = mk(9);` is judged per instance (`T = P3` is the struct).
The same holds through a fn pointer whose callee is written `&f` (6.7.12; the user's decision D28,
2026-10-15): `var x: i64 = fncall1(&mk, 9);` and `var x: i64 = callptr(&mk, 9);` carry `mk`'s struct
result, so they are refused with the same words, naming `mk` (through 6.7.11 they read its first
field); so is the callee in parentheses, `fncall1((&mk), 9)` (6.7.13). A callee held in a variable is unknown: its result stays a word. A global declaration is judged
the same (6.7.13): `var G: i64 = mk2(5);` at top level — in the declaration zone or after the first
statement — with `mk2` returning a 9-16 byte struct is refused with the same words, directly or
through `&mk2` (through 6.7.12 it stored the first field). Over 16 bytes a top-level call is refused
anyway (a struct result needs a fn's frame).

⚠ **A fn returning a 9-16 byte struct (two registers) can `return` only what those two registers
can carry**: a local of that struct, a call to a fn returning the same struct, a method or
overloaded operator returning it, or (6.7.11) a pointer to that struct (below). Anything else — a call returning a *different* struct, an
integer, a field, a bare `return;` — is a compile error since v6.6.6 naming what it got. Before
v6.6.6 every one of those compiled clean and handed back the first register plus a second that
was never written. Since 6.7.11 that includes a call that only STARTS the value: `return mk2(1) ==
p;` (any operator that does not dispatch — a comparison, `& | ^ % << >>`, `&& ||`) is refused *… got
`mk2`*, where it returned the comparison in the first register and mk2's stale second word;
`return mk2(1);`, `return (mk2(1));` and a dispatching `return mk2(1) + p;` are unchanged. (The >16-byte form has error'd on an uncarryable shape since v5.5.36.)

⚠ **A tuple literal is not the struct (6.7.11).** `return (a, b);` or `return (a, b, c);` in a fn
declared `: P` is a compile error at every size — a tuple is an anonymous struct, another type
([Tuples](#tuples)), as `var t = (a, b); return t;` already was:

```
error: a fn returning the struct `P3` returns that struct — `(a, b)` is a tuple, another type
```

Through 6.7.10 it took the multi-value path: over 16 bytes the caller's result was never written
(it read 0, 0, 0), at 8 bytes or less the second value was dropped, and at 9-16 bytes it gave the
two words only because that class's registers are the multi-value ones. Build the struct and return
it: `var p: P3 = P3 { a, b, 0 }; return p;`. A fn declared `: (T1, T2)`, or with no return type,
returns `(a, b)` as before.

The builtin `ret2(a, b)` is the same two values, so it is refused there the same way, in every class and
`return ret2(..);` too (6.7.13, the user's decision of 2026-10-15): ``a fn returning the struct `P3`
returns that struct — `ret2` writes two values``. It compiled through 6.7.12 with the same three
outcomes (0, 0, 0 over 16 bytes; the second value dropped at 8 bytes or less; the two words by
coincidence at 9-16 bytes). A `ret2` in a closure, or in an `#inline` fn replayed there, is that fn's
own and still compiles — and an `#inline` fn's `return ret2(..);` replayed in a 9-16 byte struct fn,
refused ("got `this expression`") through 6.7.12, compiles now too; a fn returning a `dyn` keeps its
own refusal.

⚠ **A fn returning a struct of 8 bytes or less returns a value of that struct (6.7.11).** The struct
travels in one register, and its `return` is checked as the two wider classes check theirs: a value
of ANOTHER struct — a local, a by-value parameter, a global, `(u)`, a call (`return mk();` too), a
field, a method or operator result, a dereference `*pu` of a `*U` — a `*U` local or parameter, and a
handle of another struct (a local or a global) are each a compile error naming it:

```
error: a fn returning the struct `S8` takes a value of that struct, or a pointer to one — got `u` (a `U8`)
```

Through 6.7.10 each compiled and handed back the other struct's word (a `*U`: its address) as the
`S8`, silently. A pointer to the fn's own struct returns the struct it points at (below). An untyped
value (`var x = 3; return x;`) is still the struct's one word.

⚠ **`return E;` with `E` a pointer to the struct returns the struct it points at, at every size
(6.7.11).** In a fn declared `: S`, `E` a `*S` — a local or a parameter, a global, a call or method
declared `: *S` (a generic one too), a `*S` field, pointer arithmetic on one, inside parentheses or not
— or a dereference `*E` of one returns a copy of the struct `E` points at, as `l = GP` copies it (struct
copies are size-independent):

```cyrius
struct S8 { v; }
var GS = S8 { 9 };
var GP: *S8 = &GS;
fn gp(): *S8 { return GP; }
fn f(): S8 { return GP; }        # GS's struct: f().v is 9
fn g(): S8 { return gp(); }      # the same (not taken as a tail call)
```

Before 6.7.11 a fn of 8 bytes or less returned the POINTER as the struct's word, silently (`f().v` was
`&GS`; only a `p: *S8` parameter copied, since 6.6.17), and over 8 bytes every form but a `*S` local or
parameter was a compile error (*… got `GP`*, *identifier is not a local*). A `*U` of another struct is
refused by name at every size (*… takes a value of that struct, or a pointer to one — got `GU` (a
`*U`)*).

⚠ **`return &s;` is `return s;` (6.7.13).** `&s` of an inline struct of the fn's struct — a local, a
by-value parameter, a value global, inside parentheses or not — returns the struct `&s` points at, at
every size, as `bs(&s)` passes it into a by-value parameter. Through 6.7.12 a fn of 8 bytes or less
returned the ADDRESS as the struct's word (for a local, a dead frame's), and over 8 bytes it was a
compile error in other words (*… two registers … got `this expression`*, *return must be a bare local
identifier …*). `&u` of another struct is refused by name at every size (*… got `&u` (a `*U`)*), and
`return &w.s;` — the address of a field — with the one message `&x.f` gets anywhere (*the address of a field
is not taken …*), at every size. A handle's or a `*T`'s `&h` is its slot — the address of the word that holds the pointer — not a struct.

⚠ **Through a fn pointer (6.7.11), the callee written `&f`.** `fncall1(&mk, 5)` and `callptr(&mk, 5)`
know their callee, and carry its struct result as `mk(5)` does — the hidden pointer over 16 bytes,
the register pair at 9-16 — so the result goes wherever `mk(5)` goes: `var p: P3 = fncall1(&mk, 5);`
(`var x = callptr(&mk, 5);` infers `P3`), `p = callptr(&mk, 5);`, `take(fncall1(&mk, 7))`, `b.v =
fncall1(&mk, 1)`, `return callptr(&mk, a);` from a fn returning `P3`, and its struct is checked
against the destination's as `mk(5)`'s is. At top level a result over 8 bytes is refused by name, as
`mk(5)`'s is (there is no frame to put it in). Before 6.7.11 a call through a pointer carried no
struct result at all: over 16 bytes the callee wrote the struct through its FIRST ARGUMENT (a
SIGSEGV on every target), 9-16 bytes lost the second register, and from 6.7.10 an 8-byte result
was a handle holding the struct's value. **A callee held in a variable** (`var fp = &mk;
callptr(fp, 5)`) is unknown at the call: its result is one word, and `var p: P3 = callptr(fp, 5);`
binds it as a handle (the handle line above). That is right for a callee returning a pointer (`fn
gp(a): *P3`, whose `p` reads and writes the object) and is NOT supported for a callee returning a
struct by value, which faults. Through a variable, receive a 9-16 byte struct's two words (`var a,
b = fncall1(fp, 5);`), or, at any size, give the target an out-pointer and have it store the fields
(`fn mko(a, out: *P3)`, then `var p: P3 = P3 { 0, 0, 0 }; var ig = callptr(fp, 5, &p);`).
The callee may sit inside parentheses that wrap the whole callee — `callptr((&mk), 5)`,
`fncall1(((&mk)), 5)` — and is the same known callee, at every destination above (6.7.13; through
6.7.12 a parenthesised `&f` was unknown, so the struct result convention was lost: a SIGSEGV, or
`return callptr((&mk), a);` refused). `callptr((fp), 5)` is still a callee held in a variable.

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
  9-16 byte *struct*, not of a vector. It stays legal for the scalar multi-value `var a, b =
  f();` form; a fn returning a named struct refuses it too since 6.7.11 (a tuple is another
  type — [Returning a struct by value](#returning-a-struct-by-value-v666)). To build a vector,
  store the lanes into a local and return the local.
* `return callptr(fp, ..);` has no declared callee type to check, so the compiler cannot know
  the target returns this vector; it happened to work on x86_64 and aarch64 and returned the
  wrong lane on Windows.

⚠ **A value-form vector LOCAL takes a vector, or nothing (6.7.11).** `var v: f64v2 = <src>;` and
`v = <src>;` take their 16 / 32 bytes only from a source that IS that vector: a local of the type,
or a call declared to return it — by name (`mkv(41, 7)`), inside parentheses (`(mkv(41, 7))`), or
through `fncallN(&mkv, ..)` / `callptr(&mkv, ..)` with the callee written `&f`, in parentheses too
(`callptr((&mkv), ..)`, 6.7.13) (on Windows the call
then passes the local's address as its hidden result pointer, as `mkv(..)` does). Every other
source is refused by name (`a value-form vector local is initialised only from a local of its
type or a call declared to return it .. - got `callptr``): a callee held in a variable
(`callptr(fp, 41, 7)`, `fncall2(fp, 41, 7)`), a word (`5`, `load64(&w)`, `&w`, a scalar local or
call), a method call, `*p`. Through a fn pointer held in a variable, give the target an
out-pointer and have it store the lanes — `var v: f64v2 = mkv(0, 0); var ig = callptr(fp, &v, 41,
7);` — which carries every lane on every target.

A vector-returning call that nothing receives — a statement `mkv(41, 7);` or `callptr(&mkv, 41,
7);`, an untyped `var x = callptr(&mkv, ..)`, an argument to an untyped parameter, a method call
`s.mv(..)`, an operator fn declared to return a vector, at top level too — runs, and its vector is
discarded, on every target (6.7.12). ⚠ Through 6.7.11 on Windows such a call passed no hidden
result pointer, so the callee wrote the vector through its first argument: a page fault, or
`s.mv(..)` overwriting `s`.

⚠ **A struct-typed FIELD is a copy destination too (v6.6.10).** With `struct Box { v: P3; n; }`,
`b.v = p` copies the whole struct into the field. So does a call, method or operator that
returns a `P3` (`b.v = mk(1)`, `b.v = a.mk(1)`, `b.v = a + c`), a by-value `P3` parameter, a
pointer-mode `P3` local (the struct it points at, not the pointer), a global, and another `P3`
field (`b.v = o.b.v`) — and since 6.7.11 a `*P3` global, a call or method declared `: *P3`, a `*P3`
field and pointer arithmetic on one (`b.v = GP`, `b.v = gp()`, `b.v = w.p`, `b.v = GP + 1`: the
struct it points at; through 6.7.10 the field kept the pointer word). A struct of a different type is a compile error naming it, at every
size — a method or operator result of 8 bytes or less included (v6.6.11). Before v6.6.10
every one of these stored ONE word: `b.v.y` kept its old value, and from a parameter the stored
word was the parameter's address. A source that is not a struct (an integer, an untyped
pointer) still stores one word, capped at the field's size. An odd-sized struct field (3, 5, 6
or 7 bytes, such as `struct Odd { a: i8; b: i16; }`) gets exactly that many bytes from any
source, so the fields after it are never touched. Before v6.6.10 a method, an operator, a
top-level call or an integer stored 8 bytes into such a field, silently overwriting its
neighbours. A ZERO-SIZE struct field (`struct E { }`, `struct O { s: E; n; }`) takes no byte from any
source (6.7.13): `o.s = GP`, `o.s = gp()`, `o.s = (GP)` (a `*E`), `o.s = mk()` and `o.s = 5` leave `o.n`
as it was. Through 6.7.12 each of those stored an 8-byte word over the field's neighbour.

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
then wrote. A field of a different struct type is refused (`cannot pass 'q' to a parameter of a
different struct type in a call to 'take'`). Before v6.6.12 the field's first word was passed as the struct's
address, and the callee SIGSEGV'd. **A top-level copy-init** — `var B: P3 = A;` from an inline
global, or `var G: P3 = BX.v;` from a global's field, in the leading declaration block or after
the first statement — gives `B` its own STRUCTSZ bytes and copies them. Before v6.6.12 `B` got one
8-byte slot holding `A`'s first word, and `B.x` SIGSEGV'd. A field reached through a POINTER is
such a source too (6.7.11): `var G: P3 = P.v;` with `P` a `*Box` global, `= (P.v)`, `= gp().v` with
`fn gp(): *Box`, `= VV.p.v` through a `p: *Box` field — through 6.7.10 `G` held the field's first
word and `G.x` SIGSEGV'd (a guest fault on cx), while the same line in a fn copied. A pointer-mode source
(`var p: P3 = mk();`, or a global initialised that way) still binds a second pointer to the same
struct, exactly as in a fn. The source must be declared ABOVE the copy: `var B: P3 = A;` before
`var A = P3 { .. };` is refused (`cannot copy-init 'B' from a global declared below it`), since
globals are initialised in declaration order and `A` has not been initialised when `B` copies it;
so is a call's field whose fn is declared below the copy in the leading block (`cannot copy-init 'G'
from a field of a call to a fn declared below it`).

⚠ **A struct ARGUMENT is checked against its parameter (v6.7.3).** An argument whose static struct
type differs from the parameter's is refused by name, as the same copy into a variable is
(`var q: Q = p;`): `bq(p)` with `p: Pt` and `fn bq(b: Q)` reports `cannot pass 'p' to a parameter of
a different struct type in a call to 'bq'`. It covers every argument that HAS a struct type — a
named local (inline, pointer-mode `var p: Pt = alloc(16)`, or `u: *Pt`), a global, a closure
capture, a field, a call or method / operator result (named by the fn: `'mkp'`, `'Pt_dup'`) —
into a by-value parameter of any size, a `p: *T` parameter or a `s: Str` handle, through a call, a
method's arguments, a tail call and an operator's two operands (parameters 0 and 1 of `Q_add`), and
a method's `self` (`impl Pt { fn m(self: Q) }` with `p.m()`). A generic INSTANCE is its own struct:
a `Box<Pt>` passed where `b: Box` is declared is refused, and the reverse. (`gx(b)` for
`fn gx<T>(b: Box<T>)` was refused here from 6.7.3 to 6.7.7: `T` was not inferred through `Box<T>`,
so the call reached the `Box` base. Since 6.7.8 it infers `T = Pt` and calls `gx$Pt` — see
[Generic Functions](#generic-functions).) Parentheses around the WHOLE argument change nothing: `bs1((t))`,
`bs1(((t)))`, `bs1((mk(7)))` and `bs1((w.t))` are refused as `bs1(t)` is, at every size (6.7.11 — through
6.7.10 a by-value struct of 8 bytes or less took the wrapped spelling unchecked and read the other
struct's word; `(t.w)` and `(x) + 1` are values, as without the parentheses). A tuple literal's element
is read the same way: `((p), 1)` is refused as `(p, 1)` is, and since 6.7.13 so is a whole dereference of a `*P`
— `(*pp, 1)`, `((*pp), 1)`, `(*gp(), 1)`, `(*w.pp, 1)`, `(*(&p), 1)` — a struct value (the user's decision D2 (a),
2026-10-15; through 6.7.12 it stored P's first word); `(pp, 1)` and `(pp.a, 1)` are i64s. An argument with NO
struct type stays accepted: `&p` (an address, as
`var q: *Q = &p;` is), an untyped variable (`var u = &p; bq(u)`), a literal, a call returning an
integer or a pointer, and a fn pointer (`fncall1(&bq, &p)`). Before v6.7.3 only a FIELD into an
address-passed parameter was checked: every other mismatch compiled clean and the callee read the
argument with its own layout — `bq(p)` read past the 16-byte `Pt` (0), `bs(mk1(p))` returned `b.v.y`
where `b.n` was 8, and `q + mkp()` or `sl(p)` for `sl(s: Str)` SIGSEGV'd.

⚠ **A struct value into a pointer of another kind is refused by name (6.7.13; the user's decision D5
(a), 2026-10-15).** `ri(s)` with `fn ri(p: *i64)` — or `*u8`, `*f64`, `**T`, any `*T` whose `T` is
no struct — and `s` an inline struct (a local, a by-value parameter, a value global, a closure's
captured copy, inside parentheses or not) reports `cannot pass 's' to a parameter that is not a
pointer to its struct type in a call to 'ri' - pass &s for its address`, as a vector local is refused
there (6.7.12) and a struct of another type into a `*Q` is (6.7.3). Write `ri(&s)` for the address.
Through 6.7.12 it compiled and passed s's first field as the address (a fault on every target, or a
read through whatever that field held). A handle (`var h: Pt = alloc(16);`), a `*Pt` and a `Str`
hold the address in their word and pass it as before; a `*Pt` parameter still takes `&s` itself
(6.6.20), and an untyped parameter the word.

**A pointer into a BY-VALUE struct parameter passes the struct it points at, at every size
(6.7.10).** `bs1(&s)`, `bs1(sp)` with `sp: *S1`, `bs1(gp())` with `fn gp(): *S1`, `bs1(h.p)` with a
`*S1` field, `bs1(sp + i)`, and an operator's right operand (`o + sp`, `o + &s`) give `fn bs1(b:
S1)` a copy of the struct — a `*T` local, parameter, global or capture, in a fn and at top level;
the callee's writes never reach the pointee. A `*U` of another struct converts, as it always did,
and is read with the parameter's layout. Since 6.7.11 so do an if-expression whose every branch is a
pointer, whatever their steps (`t7(if (c == 1) { py } else { &s })`, `py` beside a `*B4`), and an
integer on the LEFT of a struct pointer (`t1(m + pb)`, `t1(n + pb)` with `n: i32`, `bs1(n + sp)`) —
through 6.7.10 those passed the address as the struct; an if-expression of a pointer and a value is
still the value's word. Over 8 bytes this is what the address-passed parameter
always did; through 6.7.9 a struct of 8 bytes or less got the POINTER as its one word, and the
callee read the address as its fields, silently. An UNTYPED value is still the struct's word: an
untyped local holding an address (`var u = &s; bs1(u)`), an integer, an `i8` / `i16` / `i32` value.
The word a struct of 8 bytes or less travels in holds nothing but the struct (6.7.13): its bytes past
`sizeof(S)` are 0 — from a pointer into a by-value parameter, a by-value `self` from a `*S` receiver, a
handle (or a captured one) passed by value and `return q` of a `q: *S` parameter, as from a dereference
since 6.7.11. Through 6.7.12 the word of a 3, 5, 6 or 7-byte struct (and `return q`'s at 1, 2 and 4
bytes) carried whatever the frame held there, so `load8(&s + 3)` in the callee read a stale byte.

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
an untyped value is expected (`raw(q)` into an untyped parameter, `load64(q)`, `return q;` from an
`i64` fn) is its first field, as for an inline local and for a struct of 8 bytes or less — before
v6.6.16 it was the caller's address. An untyped `var k = q;` is a copy of the struct (6.7.12, see
*An untyped binding*). Write `&q` for the address (of the copy). A struct of 8 bytes or less was
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
`p + r` there is POINTER ARITHMETIC and does not dispatch, and `&p` is the slot — at every size
since 6.7.10 (the handle line: `var a: Num = 1; a + b` too). Only a
`p: *T` parameter denotes the caller's struct (`p.z` reads it) — and its `&p` is its slot too, as
for any pointer (6.7.9; see [Pointers](#pointers)).

⚠ At TOP LEVEL there is no frame to hold the result, so a struct-valued call there
(`mk(1);`, `var g: P3 = mk(1);`, `g = mk(1);`, `take(mk(1))` — and the method and operator
forms alike) is a compile error naming the fn — call it inside a fn. That includes a global
declared ahead of the first top-level statement, generic calls (`var G: W1<Pt> = mkw(p);`)
and non-generic ones (`var G: Pt = mkp(2);`) alike: before v6.6.11 that leading block was
never checked, so both compiled and `G.x` SIGSEGV'd, and after a statement the generic form
was checked against its 8-byte base and built too. The method and operator forms in that
leading block (`var G2: Q = Q0.mk();`, a generic method, `(Q0.mk())`, `Q0 + Q1`) are refused
since 6.7.9: before it they built and `G2.a` SIGSEGV'd. An untyped `var g = pair_fn(..)` of a
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

The position names the DECLARATION.

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

### Parentheses, struct operands and `Str` fields (6.7.6)

**Parentheses around a whole struct source are transparent**, at every depth and for every source
shape — a name, a field, a call, a method or an operator result — into every struct destination:
an argument (`rd3((a))`), a struct-typed field (`o.i = (z.k)`), a struct variable (`w = (j)`), a
declaration in a fn or at top level (`var q: P3 = (z.k);`, `var G: P3 = (A);`), a for step, and
(6.7.11) a nested-struct literal element (`H { 7, (mkq(4, 9)), 8 }`).
Parentheses that are only PART of the source keep their meaning (`sz((a) + (b))` adds first).
Before 6.7.6 every one of these took the struct's FIRST WORD: an address-passed argument and a
declaration SIGSEGV'd, and a field or variable kept one word of the copy, silently. Until 6.7.11
a free call in parentheses as a literal element was a scalar for the nested struct's first leaf:
*unexpected '}'* at 16 and 24 bytes and at 8 bytes with two leaves, and a one-leaf struct took the
call's word even from another struct (refused by name now, as the unwrapped call is).
Until 6.7.13 a 9-16 byte METHOD or OPERATOR result in parentheses as a nested literal element
(`H { 7, (q.dup()), 8 }`, `(q + r)`) and a wrapped struct-typed field (`H { 7, (h.q), 8 }`) were
*unexpected '}'* too; they are the element the unwrapped source is now, refused by name where it is
(another struct, no frame at top level).
The same holds for a struct fn's **return value** (6.7.6): `return (j);`, `return (mk3(v));`,
`return ((j));` and `return (a + b);` are `return j;`, `return mk3(v);` and `return a + b;`, in
both return classes (a retptr struct over 16 bytes, a 9-16 byte struct in two registers) — they
were refused (*return must be a bare local identifier ...*, *... got `(...)`*) — and so is
`return (a) + b;`, a parenthesised left operand. A refused shape inside the parentheses is
refused as it is without them.

**A struct result over 8 bytes is a valid RIGHT operand** of an operator whose parameter takes it
by address (a `*T` parameter, or a by-value struct over 8 bytes): `s - mk3(4)`, `s - s.dbl()`,
`p + p.dup()` for a 16-byte `p` — the result lands in a frame temporary whose address is passed.
At top level there is no frame, so `G + G.dup()` and `G + mk2(3)` are refused by name (*... is
passed by address (a struct over 8 bytes) ...*; *(a `*` parameter)* when the operator fn takes a
`*T`), as a `*T` operand of 8 bytes or less already was. Before 6.7.6 the operand's first word was passed as
the struct's address: SIGSEGV.

```cyrius
struct P3 { x; y; z; }
fn P3_sub(a: *P3, b: *P3): i64 { return a.z - b.z; }
fn mk3(v): P3 { var t: P3 = P3 { v, v, v }; return t; }
fn rd3(p: *P3): i64 { return p.z; }
fn demo(): i64 {
    var s: P3 = P3 { 9, 9, 9 };
    var q: P3 = (s);            # a copy, as `var q: P3 = s;`
    q.z = 4;
    return (s - mk3(4)) + rd3((q)) + s.z;   # 5 + 4 + 9
}
```

**A struct result is a LEFT operand too, and dispatches from its own type** (6.7.6): the result
of a call, a method or an operator that returns a struct by value — `mk3(4) - s`, `p.dup() + p`,
`a + b + c` with a struct-returning `+`, `(mk3(4)) - s`, `mk3(4) * s` — calls `T_op` for the struct
it returns, exactly as a struct variable in that place does: an operand of 8 bytes or less is
passed by value (or, to a `*T` parameter, through a temporary), a larger one by its temporary's
address. A missing `T_op` is refused by name (*refusing to emit binary with 1 reachable undefined
function(s)*, naming `T_op`) — `mkw(3) + 4` for an 8-byte `W` with no `W_add` too — and so is an
operator fn whose first parameter is another struct. At top level, a left operand that needs a
frame (an address-passed one) is refused by name, as the right operand is. Before 6.7.6 only a
NAME typed the left operand: a call's result was an untyped word, so `p.dup() + p` added the two
first words (2 where 6 is right), `a + b + c` added an address to a first word and crashed, and
`mk3(4) - s + 10` dispatched `P3_add` — from the struct type `s` left behind. A `Str` result is a
heap handle and never dispatches (`gs() + 8` is pointer arithmetic). The same expression works as
an argument (`sz(mk3(1) + a)`), a declaration's initialiser (`var r = mk3(4) - s;`, `var q: P3 =
mk3(1) + a;`) and a struct fn's return value (`return mk3(1) + a;`) — those two were `expected
';', got '-'` before 6.7.6, the receive having taken the call alone.

**A struct-typed field or a `*T` dereference is a LEFT operand too** (6.7.10, the user's decision):
`w.s + a`, `p.s + a` through a `*W`, `mk(1).s + a`, `self.s * a`, `o.w.s - a`, `(w.s) + a`, `*p + a`,
`(*p) + a`, `*gp() + a` and `*w.ps / a` call `S_add` (`S_sub`, `S_mul`, `S_div`) for the field's
struct, or the struct the `*S` points at, exactly as a struct variable in that place does, at every
size: into a `*S` parameter or over 8 bytes the field's own address (or the pointer) is passed — a
write through it reaches the field — else its value. The result is a struct value: it is copied by
a declaration or an assignment, passed, returned (`return w.s + a;` from a struct fn) and chained
(`w.s + a + a`). A missing `S_op` is refused by name as for a variable (`w.s + 1` with no `S_add`),
as is an operator fn whose first parameter is another struct, and, at top level, a 9-16 byte result
(`var G: H = GW.s + A;`). Through 6.7.9 only a variable or a struct result typed the left operand:
`h.p - s` subtracted the first words (250 where `P2_sub` gives 139), silently, at every size. A
`*T` field itself is a pointer (`w.p + 1` steps it), a `Str` field a handle, and `-w.s + a`
negates a word first (no dispatch) — as `-s + a` does since 6.7.11 (see below). A whole field of 3, 5,
6 or 7 bytes used as a value — this operand, an argument (`take(w.s)`), `return w.s`, a right operand, an
untyped `var u = w.s`, a top-level `var G: S3 = GW.s` — reads exactly the field's bytes, its word's padding
0, and a zero-size one reads none (6.7.13), as a dereference of a `*S` of 1 to 7 bytes does since 6.7.11
(see below). Through 6.7.12 it was loaded as an 8-byte word: up to 5 bytes past the object landed in the
padding, and an object ending exactly at the end of a mapping faulted.

**An integer operator's result is an integer** (6.7.11): with an integer left operand, `n - s` on a
struct `s` is arithmetic on the struct's first word (its word, at 8 bytes or less), and the result is an
integer whatever the operator — `+ - * / % << >> >>>`, `& | ^`, a comparison, `&&` / `||`, `+| +? -| -?
*| *?` and `~s` — so `n - s + 10` is `(n - s) + 10`. Through 6.7.10 the result kept the right operand's
struct type, and the next `+ - * /` dispatched on it: `n - s + 10` called `S_add(&s, 10)` and discarded
`n - s` (a crash when `S_add` read its right operand as a struct), `(n < s) + 1` and `(~s) + 1` likewise,
and with no `S_add` each was refused as an undefined function. (`!s` was always an integer.)

**Unary minus on a struct is integer negation of its word** (6.7.11, the user's decision of
2026-10-13): `-s` negates the struct's first word (its word, at 8 bytes or less) and the result has
no struct type, exactly as `-w.s` on a struct-typed field — so `-s + t` is an integer add at every
size, never `S_add`, and as a right operand `t + -s` passes the negated word, as `t + -w.s` does.
Through 6.7.10 the negation kept `s`'s struct type and slot: `-s + t` over 8 bytes called `S_add(&s,
&t)` with the minus dropped (`s + t`'s value), at 8 bytes `S_add` with the negated word as the
struct, and `t + -s` over 8 bytes passed `s` itself. Nothing is refused. `-` on an f64 / f32 is a
float negation, and on a `u128` the 128-bit `0 - x`, as before.

**A whole dereference is a struct value as an argument and a right operand too** (6.7.10, decision 6):
`take(*p)`, `take((*p))`, `take(*gp())`, `take(*w.ps)`, `take(*(p + 1))` and `a - *p`, `a + (*p)` pass
the struct `p` points at exactly as a struct variable in that place does — to a by-value parameter over
8 bytes (or an operator's) the pointer, which the callee copies, so its writes stay in its copy; to a
`*S` parameter of any size the pointee itself, so a write reaches it. A dereference-led operator result
is an argument like any other (`take(*p + a)`; at top level a 9-16 byte one is refused by name, as
`take(GW.s + a)` is). A `*U` of another struct is refused by name (*cannot pass 'pu' to a parameter of a
different struct type*) at every size and into a `Str` parameter — since 6.7.11 a by-value parameter of 8
bytes or less too (`take8(*pu)`, `take8((*pu))`, `take8(*w.pu)`, `take8(*self)` in another struct's impl:
through 6.7.10 it compiled and passed U's bytes); the pointer `take8(pu)` still converts. An untyped `*x`
is still the word it reads. Through 6.7.9 the word the
dereference read was passed as the struct's address — a crash on every target. Under 8 bytes a
dereference reads exactly the struct's bytes wherever it is a value — a global declared from it (in
the declaration zone or after it), a by-value argument, `return *p`, an operator's operand — and its
word's padding is 0 (6.7.11): through 6.7.10 it loaded the whole word at `p`, so the bytes after the
object filled the padding (`load8(&G + 3)` of a 3-byte `G` read the next byte) and an object ending
a mapping faulted. A dereference of a ZERO-SIZE struct reads no byte (6.7.13): as a value its word is 0,
into a `*S` parameter it passes the pointer, and `*p + l` dispatches `S_add` as at every other size;
through 6.7.12 it loaded the 8 bytes at `p` (a fault when the object ended a mapping).

**A dereference of an address-of is the struct it names** (6.7.13): `*(&x)` / `*&x`, with `x` an inline
struct — a local, a by-value parameter (`&q` of an address-passed one is the caller's struct, 6.6.6), a
value global, a closure's captured copy of one — is the struct value `x` is, wherever a dereference of a
`*S` is one: `take(*(&x))`, `bp(*(&x))` into a `*S` parameter (the struct itself), `var d: S = *(&x);`,
`l = *(&x)`, `o.s = *(&x)`, `q = *(&x)` through a `*S`, `*(&x) = v` (copies `v` into `x`), `return
*(&x)`, `*(&x) + a` (dispatched) and `a - *(&x)`, in a fn and at top level; another struct's is refused by
name, as `x` itself is. Through 6.7.12 it was an untyped word load: over 8 bytes `take(*(&x))` passed x's
first field as the struct's address and `var d: S = *(&x);` was a handle holding it (a crash on every
target), the assignments stored one word, `return *(&x)` was refused, and another struct's compiled. A
handle's or a `*T`'s `&h` is its slot (the handle line), so `*(&h)` is still the untyped word the slot
holds; `&x + n` is still a byte pointer, so `*(&x + 8)` is the word at that address; and `*(&x) OP= v`
still operates on x's first word (6.7.5), where `*p OP= v` through a `*S` is refused.

**A store through a `*S` copies the struct** (6.7.11, the user's decision of 2026-10-13): `*p = v` with
`p` typed `*S` — a local or parameter (`*self` in an impl method too), a global (`*GP = v`), `*(p + n)`,
`*gp()`, `*w.p` — copies exactly `sizeof(S)` bytes (none for a zero-size struct) from any `S` value
`G = v` takes: a local, a by-value parameter, a global, a field `w.s`, a call, a method or operator
result, a handle or a `*S` (`*p = q` copies the struct `q` points at; `q` is not rebound), `*q` — in a
fn, at top level and in a for step, so `*p = l`, `p = l` and `G = l` (with `p = &G`) agree. A struct of another type is refused by name
(*cannot copy 'u' into a variable of a different struct/vector type: 'p'*), and `*p OP= v` as `l += a`
is (*compound assignment to the struct 'p' points at is refused*; write `*p = *p + b`). Any other value
— an untyped one, an integer — is stored as the struct's word at `sizeof(S)` bytes, at most 8, never
past the object (`*p = 0` clears a 3-byte struct's 3 bytes, a 16-byte struct's first 8). At top level a
call, method or operator result over 8 bytes has no frame to land in and is refused, as into a struct
global. Through 6.7.10 the store was the 8-byte word whatever the struct: a zero-size struct took 8
bytes over the next global, one of 3 to 7 bytes overran the object, one over 8 bytes kept only its first
8 (a 16-byte one's second field stale), `*p = q` stored the pointer, and `*p += a` added to the first word.
A call returning several values is no `S` value: `*p = mk();` is refused as `G = mk();` is (*a multi-value
call 'mk' is not assigned to struct 'P2' - bind it first*; 6.7.13, the user's decision of 2026-10-15) —
through 6.7.12 it stored the call's first value as the struct's word. A `*i64` still takes that word.

**An untyped binding of a struct-returning operator takes its struct type at every size** (6.7.10,
the user's decision): `var c = a + b;` with `fn S_add(..): T` declares `c` an inline `T` — `c.f` reads
and writes it, `c + c` dispatches again, `take(c)` passes it — whatever the left operand is (a
variable, a field, a dereference, a call, wrapped, chained); the operator's return type wins over a
leading call's (`var c = mk(4) * b;` is `S_mul`'s type), as it did over 8 bytes, where the result's
temporary becomes `c`. Through 6.7.9 a result of 8 bytes or less was an untyped word: `c.f` was *no
struct type in scope for 'c'* and `c + c` added integers — and 6.7.10's packed fields moved `struct
C4 { r: u8; g: u8; b: u8; a: u8; }` from 32 bytes to 4, so `var c = A + B; c.g = 1;` stopped
compiling until this. An operator returning an integer leaves the binding untyped, and an untyped
global keeps the result's word at every size. So does a comparison, and so does either one after a
LEADING CALL (6.7.11): a call's struct types the binding only when the call is the whole initialiser —
through 6.7.10 `var r = mk3(4) - s;` with an integer `P3_sub` took `mk3`'s `P3`, so `r.x` dereferenced
the integer, and `var r = mk2(1) == p; return r;` returned a 16-byte struct from an 8-byte slot; both
are refused now (*no struct type in scope for 'r'*, *... got `r`*).

The same rule holds for **every whole struct result** (6.7.11, the user's decision of 2026-10-13): a
method chain of 8 bytes or less (`var c = a.d().d();`), an if-expression whose branches are a struct of 8
bytes or less (`var c = if (k == 1) { mk(7) } else { mk(9) };`) and a 9-16 byte operator or method result
in parentheses (`var c = (a + b);`, `var e = (a.m());`) each declare `c` the struct, as the annotated
form does and as a single method and the same chain over 8 bytes always did. Through 6.7.10 each was an
untyped word: `c.v` was *no struct type in scope for 'c'*, `c + 1` added to the word (now it dispatches
`S_add`, or is refused if there is none), and `take(c)` passed the parenthesised 9-16 byte result's
first word as its address. A method chain ending in an integer method stays untyped; a scalar
annotation (`var c: i64 = (a + b);`) keeps the first word; an untyped global keeps the word.

**So does an untyped name of a struct value** (6.7.12, the user's decision of 2026-10-15): `var q = p;`
(or `var q = (p);`) in a fn, with `p` an inline struct local, a by-value struct parameter (`self: T`
included) or a closure's captured copy of one, declares `q` a copy of `p`'s struct, as `var q: P = p;`
does — `q.y` reads and writes the copy (`p` is untouched), in a fn and inside a closure that captures `q`,
`take(q)` passes it, and `q + p` dispatches `P_add`. Through 6.7.11 `q` was `p`'s first word: `q.y` was *no
struct type in scope for 'q'* (*undefined variable 'q'* in a closure), `take(q)` passed the word as the
struct's address, and `q + 1` added to it (now it dispatches `P_add`, or is refused if there is none). A
bare `q` where a value is expected is still the first word (`return q;` from an `i64` fn). Since 6.7.13
(the user's decision D6 (b), 2026-10-15) an inline struct GLOBAL named in a fn is such a source too:
`var q = G;` (or `var q = (G);`) with `var G: P = P { 3, 4 };` is a copy of `G`, as `var q: P = G;` is —
`q.y = 9` leaves `G` untouched, `take(q)` passes it, `q + G` dispatches `P_add` (through 6.7.12 `q` was
`G`'s first word: `q.y` *no struct type in scope for 'q'*, `take(q)` a fault, `q + 1` an integer add).
Unchanged: a `*T` source stays a plain word (an untyped impl `self` is one), and so does a HANDLE — a
local, a handle global (`var GH: P = 0;` then `GH = alloc(16);`), a local that shadows the global — whose
word is the struct's address: `var q = h;` is that address, `q + n` byte arithmetic on it; an untyped
global keeps the word (`var H = G;` at top level); a tuple stays refused (*tuple 't' used as a value*).

**A `: Str` field is a `Str` handle as a source.** `h.name` into a `Str` parameter, variable or
field, or an untyped one, is the handle as ever (a pointer-mode struct variable rebinds to it,
the 6.6.16 handle rule). Into a struct VALUE of another type it is refused by name, as a `Str`
variable is: `bq(h.name)` for `fn bq(b: Q)` reports `cannot pass 'name' to a parameter of a
different struct type in a call to 'bq'`, and `var q: Q = h.name;`, `q = h.name`, `o.q = h.name`
and `q + h.name` are refused alike. Before 6.7.6 they compiled and read `Q`'s fields out of the
Str's 16-byte header and past it.

The result of a name intrinsic — `mulh64(..)`, `fncall0`..`fncall8(..)`, `callptr(..)` — is an
untyped word whatever its last argument was: `fncall1(&f, n) + 1` with `n` a struct adds 1. Before
6.7.6 it kept the last argument's struct type and dispatched that struct's `_add`. The one case
where that old typing was right is kept: when the callee is written `&f` and `f` returns `: f64`,
and the last argument is an f64, the result is an f64 (`fncall1(&dbl, d) + 1.0` is an f64 add), as
it was before 6.7.6. Through a variable or a closure, or with any other last argument, the result
is an untyped word: write `f64_add(fncall1(fp, d), 1.0)` or bind it to a `var r: f64`. Since 6.7.11
an `&f` callee that returns a struct by value makes the result that struct, as `f(..)`'s is (see
*Returning a struct by value*).

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

fn slices_demo(fd): i64 {     # a slice is a fn-local (6.7.8)
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

    # Element stores (6.7.8) — checked the same way, in every mode.
    s[1] = 90;              # one byte: data[1]
    s[1] += 2;              # every compound operator: 92
    for (var i = 0; i < 4; s[i] = 0) { i = i + 1; }   # the for step too

    # Dot-syntax field access (v5.8.16). .ptr / .len only — other names error.
    var p = s.ptr;          # = &data
    var n = s.len;          # = 5
    s.len = 3;              # truncate the view
    s.ptr = &data + 1;      # rewrite view start

    # Slice-typed wrapper helpers (v5.8.18) — additive, take slice POINTERS.
    sys_read_slice(fd, &s);                 # read up to s.len bytes into s.ptr
    slice_copy_bytes(&dst, &src);           # memcpy with min-length cap
    slice_eq_bytes(&a, &b);                 # content equality
    return 0;
}
```

**Reads.** `s[i]` loads the element at `s.ptr + i * sizeof(T)` at T's width, after checking `i`
against `s.len` (out of range or negative: `slice bounds violation`, exit 134 — under the
[bounds-checked mode](#the-bounds-checked-mode-678) the mode's own `bounds: index …` line, same
exit). An `[i8]` / `[i16]` /
`[i32]` (or `slice<i8>` ..) element is **sign-extended** (6.7.8): a stored `-3` reads `-3` and
`s[0] < 0` holds, as for the same bytes in an `i8[N]` array, through a `*i8` or in an `i8` field. A
`u8` / `u16` / `u32` element zero-extends; an `f64` / `f32` / `bool` element is read as an untyped
word (its bits). ⚠ Before 6.7.8 a signed element was zero-extended — `-3` in an `[i8]` read `253` and
`s[0] < 0` was false; code that wants the unsigned value writes `s[i] & 0xFF` (`& 0xFFFF`,
`& 0xFFFFFFFF`) or declares the slice `[u8]`.

**Stores (6.7.8).** `s[i] = v` stores the element at `s.ptr + i * sizeof(T)` at T's width, after
checking `i` against `s.len` exactly as a read does — out of range (or negative) prints `slice bounds
violation` and exits 134, in every build. The value is checked as a store into an element of `T`:
an `f64` into an `f32` element rounds, a `bool` element takes only a boolean, an integer constant
into a float element warns, a wider integer into a narrow element warns "narrowing". `s[i] OP= v`
(all eleven operators) and a `for` step store the same way; `OP=` combines with the element as
`s[i]` reads it (an `[i8]` `-7 /= 2` is `-3`). Refused by name: a store into a struct or `u128`
element (`store*` at `slice_ptr(&s) + i * sizeof(T)`), `OP=` on an `f64` / `f32` / `bool` element
(the read `s[i]` is an untyped word, so write `s[i] = v`), and a slice subscripted inside a closure
that captured it (pass `slice_ptr(&s)` / `slice_len(&s)`, or declare the slice in the closure).
⚠ Before 6.7.8 a store was "cannot subscript 's'"; the spelling was `store8(slice_ptr(&s) + i, v)`,
which stays valid.

**Slices are fn-locals (6.7.8).** `[T]` / `slice<T>` declares a `var` in a function (or a closure, or
a generic instance at its `T`). Every other position is refused by name, once, the whole type
consumed: a **parameter** (`fn f(s: [u8])` — pass `&s` and read `slice_ptr` / `slice_len`, or the
pointer and the length), a **return type** (also as a multi-value element), a **struct or union
field**, a **pointer to a slice** `*[T]` / `*slice<T>` (anywhere: pass `&s` as a plain pointer), a
**global in the declaration zone** (before the first top-level statement), a **slice of slices**,
a **type argument** (`g<[u8]>`) and a **tuple element**. Before 6.7.8 each was a generic parse error
(`expected ')', got identifier 'u8'`, `expected identifier, got '['`, `unknown type 'slice'`, ...).
A top-level `var s: [T]` AFTER the first top-level statement is still a 16-byte global, used through
the helper API — `slice_set(&s, ..)`, `slice_ptr(&s)` / `slice_len(&s)`, `slice_unchecked_get_W` —
as before: subscript and dot syntax fire on **fn-local** slices only — and the dot syntax's reads
on a closure's captured copy (6.7.11, the user's decision of 2026-10-13): inside a closure that
captured `s`, `s.len` / `s.ptr` read the copy the closure was built with (a later `slice_set` on
the enclosing `s` is not seen, as for any capture). A store into the copy (`s.len = n`,
`s.ptr = p`, `s.len += 1`) is refused by name ("a closure cannot assign a field of the captured
slice 's'"), as `s[i]` is. ⚠ Before 6.7.11 the read was "undefined variable 's'". See
`lib/slice.cyr` for the full helper list.

**`slice` is not reserved.** A program may declare its own `struct slice` (or `struct slice<T>`), and
then the name is that struct everywhere — a parameter, a pointer target, a field, a global, a type
argument and (6.7.11) a fn-local `var x: slice;` / `var y: slice<Pt>;`; the built-in slice stays
reachable as `[T]`. Through 6.7.10 the fn-local annotation alone still meant the built-in 16-byte slot
(`x.a`: "no struct type in scope for 'x'"; the user's decision (b), 2026-10-13) — so a program that
declares `struct slice` and used a fn-local `slice<u8>` as the built-in now meets its own struct there
(`s.len`: "unknown field 'len' on struct 'slice'"): spell the built-in `[u8]`.

A `Str` (heap, `lib/str.cyr`) and a `vec`'s first 16 bytes
(`lib/vec.cyr`) are byte-identical to a slice — they pass directly to
`slice_ptr` / `slice_len` / `slice_eq` etc. without conversion.

## The bounds-checked mode (6.7.8)

Off by default, the **bounds-checked mode** checks every subscript at run time — `a[i]` on a typed
array, `s[i]` on a slice, `p[i]` on a typed pointer — and stops the program at the first index out
of range, naming the file and the line the subscript is written on. It is switched on for a whole
program; a program built without it carries not a byte of it.

```
#bounds
var a: u8[5];

fn fill(v): i64 {
    for (var i = 0; i <= 5; i += 1) { a[i] = v; }   # <= : one element too many
    return 0;
}

fn main(): i64 {
    fill(7);
    return 0;
}
```

```text
bounds: index 5 out of [0, 5) at <source>:5        <- stderr; the exit status is 134
```

Without the mode the sixth store lands in the spare bytes of the array's 8-byte slot, nothing is
reported, and the program exits 0.

**Switching it on.** Four spellings, one precedence — highest first:

| Rung | Spelling | Off |
|---|---|---|
| argument | `--bounds` on `cyrius build` / `run` / `test` / `fuzz` (`run`: before the source) | — |
| environment | `CYRIUS_BOUNDS=1` — read by every compile, `cycc` included | `CYRIUS_BOUNDS=0` |
| manifest | `bounds = true` under `[build]` (build / run / test / fuzz) | `bounds = false` |
| source | a `#bounds` line in the entry file's leading block | — |

So `CYRIUS_BOUNDS=0` or `[build] bounds = false` turns a `#bounds` program's mode off.
`CYRIUS_BOUNDS` unset or empty is no rung; any value but `0` / `1` is refused by name
(`CYRIUS_BOUNDS must be 0 or 1 (or unset): <v>`). `cyrius build --print-config` shows the resolved
`build.bounds` and the rung it came from. With the mode on the compiler predefines `CYRIUS_BOUNDS`
for `#ifdef` — in every file, one included above the `#bounds` line too; a plain `#define
CYRIUS_BOUNDS` is an ordinary define and switches nothing.

`#bounds` is honoured only in the entry file's **leading block**: before it may stand blank lines,
`#` comment lines and `include "…"` lines; a declaration, a statement, a `#define`, an `#if*` or an
attribute ends the block.

```
# tool.cyr — checked in every build
include "lib/io.cyr"
#bounds

fn main(): i64 { ... }
```

Anywhere else — after code, inside an `#ifdef` (taken or not), in an included file, in a `[build]
modules` file — the line is refused by name: it switches the whole program, so a library must not
be able to. `#bounds <anything>` is refused too; a `#bounds` inside a string is data. The mode is
refused for a kernel or EFI image (`kernel;`, a bare-metal `--target`, `CYRIUS_TARGET_EFI=1`: a
violation would have no stderr and no exit) and for a `shared;` / `object;` build (the checker would
be defined in every object). Every hosted target carries it: x86-64 and aarch64 Linux, macOS
(arm64, x86-64), Windows, agnos and cx.

**What is checked.**

| Subscript | Checked against |
|---|---|
| `a[i]` on `var a: T[N]` — local, global, static-storage local, capture, a generic `T[N]` instance | the declared `N`: `0 <= i < N` (a `u8[5]` is 5 elements, not its 8-byte slot) |
| `s[i]` on a slice — read, `=`, `OP=`, the `for` step | its length: `0 <= i < s.len` |
| `p[i]` on a `*T` — a name, `h.p[i]`, `f()[i]`, `o.m()[i]` | a NEGATIVE index only — a pointer has no extent; `slice<T>` is the checked spelling |

A subscript is checked wherever it is written — a fn, top level, a closure, a `defer` body, a `for`
step, an `#inline` fn's body, an `async fn` — once its index is evaluated and before it is used.
**Not checked:** `load*` / `store*` at an explicit address, `*p`, and `*(p - 1)` — the spelling for
a deliberate step before a pointer. `vec` and `lib/bounds.cyr` keep their own checks (exit 1). A
redeclared global array (`var A: u8[5]; var A: u8[6];`, one storage) is the FIRST declaration's
array: its `N` and its element type.

**A violation** prints one line on stderr and exits **134**:

```text
bounds: index 5 out of [0, 5) at <source>:12
bounds: index -1 out of [0, ...) at src/ring.cyr:40      <- a *T: no length to print
```

The file is named as every compiler diagnostic names it — `<source>` for the entry file (through
`cyrius build` / `run` too), an included file by its include path — and the line is the one the
subscript is WRITTEN on: an `#inline` fn's body, a generic instance and a `for` step name their own
line, not their caller's. 134 is the code a slice's own check has always used: outside the mode a
slice is still checked, every read and store, with its `slice bounds violation` line.

**Constant indexes — in every build.** An index made only of integer literals, `+ - *`, parentheses
and names that resolve to an integer `const` or an enum constant (a local of the same name wins, as
anywhere) is judged at compile time, mode or not. In range, no run-time check is emitted: it costs
nothing. Out of range, it is a warning in every build and an **error** under the mode:

```text
warning:<source>:4:6: index 5 is out of range [0, 5) for 'a' (an error under the bounds-checked mode)
```

(a `*T` or a slice: `index -1 is negative for 'p'`). `/`, `%`, shifts, calls and variables make the
index a run-time one. A generic fn's instances report a constant once.

**`@unsafe { }` turns the check off** for a subscript whose `[` lies inside the block (a constant out
of range there is a warning, not an error). The block is LEXICAL: an `#inline` fn that subscripts
keeps its check when it is called inside `@unsafe` — its body is not written there. A `#naked` fn
cannot make the checker's call, so a checked subscript in one is refused by name under the mode
(`the bounds check is a call, which a #naked fn cannot make - wrap the access in @unsafe { }`).

**Cost.** Each checked access is a call into the checker — six small fns the compiler appends to the
program when the mode is on (the `__cyrius_bounds_*` names are the compiler's); an in-range constant
index costs nothing. Fns the program never reaches are counted by the `N unreachable fns` note and
dropped by `CYRIUS_DCE=1`. Measure a hot loop under the mode before shipping it on.

## The execution-coverage mode (6.7.10)

Off by default, the **execution-coverage mode** gives every fn body a hit counter and, when the
program exits, appends the fns it entered — and how many times — to a file. It answers what a
reference count cannot: whether a fn a test names was ever actually run. `cyrius coverage --exec`
(*Build Tool & Dependencies*, below) builds and runs a project's tests and programs this way and
reports the executed figure; the mode itself is a compiler switch, so any compile can use it. A
program built without it carries not a byte of it.

```
fn sq(x): i64 { return x * x; }
fn never(): i64 { return 9; }
#naked
fn nk() { asm { 0xC3; } }
fn main(): i64 {
    var inc = |a| a + 1;
    var t = 0;
    for (var i = 0; i < 3; i = i + 1) { t = t + sq(i) + callptr(inc, i); }
    return t;
}
```

```sh
CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE=$PWD/build/demo.cov cyrius build demo.cyr build/demo
./build/demo; echo $?         # 11, as without the mode
cat build/demo.cov
```

```text
# cyrius-coverage 1
3 <source>:1 sq
- <source>:4 nk
1 <source>:5 main
3 <source>:6 __cl00008
```

`never` was not entered, so it has no line; `nk` is `#naked`, so it is listed but not counted.

**Switching it on.** Two environment variables, read by every compile — `cycc` itself, and so every
`cyrius` verb that compiles:

| Variable | Value | Effect |
|---|---|---|
| `CYRIUS_COVERAGE` | `1` | the mode on |
| | `0`, unset or empty | off |
| | anything else | refused by name: `CYRIUS_COVERAGE must be 0 or 1 (or unset): <v>` |
| `CYRIUS_COVERAGE_FILE` | a path | **required** with the mode: the file the program appends to when it exits |

There is no default file: a predictable name would let an instrumented program run in a shared
directory append into whatever a planted symlink there names. A missing or empty
`CYRIUS_COVERAGE_FILE` is refused by name (`CYRIUS_COVERAGE=1 needs CYRIUS_COVERAGE_FILE=<path> …`),
and so is one over 255 bytes (`ignoring CYRIUS_COVERAGE_FILE: its value is longer than 255 bytes`,
then the same refusal). The path is fixed into the binary when it is compiled, and the program opens
it when it exits — a relative path against its working directory at that moment — so give an
absolute one. The file is created (mode 0644) when missing and opened for append, so each run adds a
block. The compiler never writes it.

There is no source spelling and no `--coverage` flag on `build` / `run` / `test`:
`cyrius coverage --exec` sets both variables for each entry it builds, with a file of its own. With
the mode on the compiler predefines `CYRIUS_COVERAGE` for `#ifdef`; a plain `#define
CYRIUS_COVERAGE` is an ordinary define and switches nothing. The mode is refused by name for a kernel
or EFI image (`kernel;`, `CYRIUS_KERNEL=1`, `CYRIUS_TARGET_EFI=1`: no process exit to dump at) and for a
`shared;` / `object;` build (no process exit of its own; the counters and the dump would be defined in
every object). It combines with the [bounds-checked mode](#the-bounds-checked-mode-678). Every hosted
target carries it: x86-64 and aarch64 Linux, macOS (arm64, x86-64), Windows, agnos and cx.

**The dump.** Each process that dumps appends one block of whole lines:

```text
# cyrius-coverage 1
<count> <file>:<line> <name>          <- a fn entered <count> times (count >= 1)
- <file>:<line> <name>                <- a #naked fn: not instrumented, ran or not
```

A fn never entered has no line. `<file>` is named as every compiler diagnostic names it — an included
file by its include path as written (`lib/assert.cyr`, `src/parse.cyr`), `<source>` for the entry
file (through `cyrius build` / `run` too). `<line>` is the line of the `fn` keyword; a closure's is its
closing `|` (or its `||`); a fn a `#derive` writes has no `fn` of its own and is named at its struct's closing `}`.
`<name>` is the name the compiler registers: `P_sum` for a method,
`gen$i32` for `gen<i32>` and `gen$f64` for `gen<f64>` (an `i64` instance is `gen` itself; a struct
type argument is its name, `gen$Pt`, and one named exactly like a scalar is marked, `gen$.f64` for a
`struct f64`), `f$impl` for an `async fn f`'s body,
`__clNNNNN` for a closure (the number is an index, so it moves as fns are added). The counts are
this process's. A dump that cannot open its file — an open the program's own sandbox denies, a path
that cannot be created — writes nothing and says nothing.

**What is counted.** Every fn body the program compiles: fns, methods, generic instances, the fns a
`#derive` writes, closures, and an `async fn`'s body — once per future, when it first runs, never per
resume. An `#inline` fn's body is copied into each caller with no call, so each copy counts as an
entry. Every entry counts, a self tail call's included. Not counted: the async and enum-variant
constructors (no source fn to name), the compiler's own `__cyrius_` fns, and `#naked` fns — they have
no frame and a raw-`asm` body, so they get no counter and are listed with `-`. A fn's counter is
bumped at the first byte of its body: after the frame, the parameters and the by-value struct copies,
before its first statement.

**When it dumps.**

- the program falls off the end of its top level, or the `main` it defines returns (the auto-call,
  on every target — cx's since 6.7.11);
- the program makes an exit syscall whose NUMBER is a compile-time constant — a literal, a `const` or
  an `enum` value: `sys_exit`, `sys_exit_group`, `panic`, the stdlib's aborts, a bounds violation's
  exit 134, `syscall(SYS_EXIT, main())`. The dump runs after the syscall's arguments are evaluated, so
  `syscall(60, f())` counts `f`.

The exit numbers are the target's own:

| Target | Exit numbers |
|---|---|
| x86-64 Linux, x86-64 macOS, cx | 60, 231 |
| aarch64 Linux, arm64 macOS | 60, 93, 94 — a raw 231 is `munlockall` on aarch64 Linux, not an exit |
| Windows | 60 — a raw 231 is not rerouted there (it returns -38 and the program goes on); `sys_exit_group` issues 60 |
| agnos | 0 |

**What it cannot see.** These end a run without writing a block: an exit through `asm`, an exit
syscall whose number is a run-time value (`var n = 60; syscall(n, 0);`), an exit inside a `#naked` fn
(no call can be made there), a successful `execve`, a signal, a crash and a kill.
`cyrius coverage --exec` fails such a run by name: it `exited 0 but left no coverage record`.

**Threads and fork.** The counters belong to the process. `lib/thread.cyr` workers leave through raw
`asm`, so the process's own exit writes one block that holds every worker's entries. The increment is
not atomic: two threads entering one fn at once can lose a count, but an entered fn never reads 0. A
thread that ends itself with `sys_exit` (on Linux, the exit of that thread alone) writes a block of its
own. A forked child starts with its parent's counts and appends its own block when it exits, so the
counts from before the fork appear in both; the file is opened for append, so neither block
overwrites the other. Only whether a fn was entered is stable from run to run, and that is all
`cyrius coverage --exec` reads.

**Per target.** The dump opens its file through the routes every target already has — no new OS
call: `O_WRONLY | O_CREAT | O_APPEND` on Linux, Windows and cx, the Darwin flags (0x209) on macOS, and
on agnos `AO_WRONLY | AO_CREAT | AO_APPEND` followed by a seek to the end (its kernel does not honour
`AO_APPEND` yet). cx takes no `#naked`, so such a fn is an ordinary counted one there.
`cyrius coverage --exec` runs host binaries only, so it never runs cx bytecode.

**Reserved names.** The dump is four fns the compiler appends to the program —
`__cyrius_cov_cp`, `__cyrius_cov_num`, `__cyrius_cov_w` and `__cyrius_cov_dump`; the `__cyrius_`
prefix is the compiler's, as for the bounds checker. Under the mode a program's own fn whose name
starts `__cyrius_` gets no counter and no line, and one that reuses a `__cyrius_cov_` name is replaced
by the compiler's (the `duplicate fn` warning names it).

**Cost.** Each fn body gains its counter bump (30 bytes of code on x86-64) and the image 8 bytes of
counter per fn plus the fn map — the dump path and one `<file>:<line> <name>` line per fn, which the
dump reads at exit. The counters and the map are left out of the `large static data` warning. Built
under the mode, `cycc` itself is about 13 % larger and compiles itself about 12 % slower (measured at
6.7.10).

## Traits and impl blocks (6.7.0)

A **trait** declares a method set; an **impl** gives a type those methods. Dispatch is static — a
method call is a direct call to a mangled name, as [ADR-004](../adr/004-convention-based-dispatch.md)
set out; [ADR-007](../adr/007-traits.md) records the trait design.

```cyrius
struct Point { x; y; }

trait Show {
    fn show(self): i64;                                   # required
    fn twice(self): i64 { return self.show() * 2; }      # a default
}

impl Show for Point {
    fn show(self): i64 { return self.x * 10 + self.y; }
}

impl Point {                                              # inherent: no trait
    fn new(x, y): Point { var p: Point; p.x = x; p.y = y; return p; }
    fn norm1(self): i64 { return self.x + self.y; }
}

fn demo(): i64 {
    var p = Point_new(1, 2);      # a 16-byte struct result: it needs a fn's frame
    var a = p.show();             # 12  -> Point_show(&p)
    var b = p.twice();            # 24  -> the default, instantiated for Point
    var c = Point_Show_show(p);   # 12  -> the trait-qualified name
    return a + b + c;             # 48
}
```

- **`impl X for T` is checked.** An undeclared trait, a method `X` does not declare, a different
  parameter count, and a required method left out are compile errors naming the trait. A trait may
  be declared above or below its impls. Traits and impls go in the declaration section (before the
  first top-level statement), like `struct` and `enum` — unlike a `fn`, which may also follow
  statements.
- **A member's signature is parsed (6.7.8)** where the trait declares it, with a `fn` definition's
  grammar and messages, whether or not an impl uses it: the parameters (`name`, `name: Type`, `...`),
  their types, the return type, then `;` or the body. Junk (`fn sh(self, n + foo bar): i64;`), a type
  name that names nothing, or a stray token before the `;` is an error — in a required member and in
  a default every impl overrides alike (a default an impl inherits is parsed as that impl's method).
  ⚠ Before 6.7.8 only the parameter count was read; the rest compiled unread. The impl's own check
  is unchanged: its parameter count must match.
- **Parameter defaults (6.7.7).** A trait's methods take none, in a required signature or a
  default body, and neither does a method of `impl X for T`: the trait's signature is the
  contract. An inherent `impl T` method may declare them (see *Default and named arguments*
  under **Functions**). ⚠ A default in a required signature compiled and was ignored before
  6.7.7; it is refused now.
- **Defaults** (a member with a body) are instantiated for every impl that does not define its own —
  each impl type gets its own copy, so `self.show()` inside one calls that type's `show`.
- **Names.** A method is `T_m`; every trait method is also `T_Trait_m`. If **two traits** give `T`
  an `m`, the plain `T_m` / `p.m()` is ambiguous and refused (the error names a qualified spelling)
  — call `T_A_m(p)` or `T_B_m(p)`. Inside an impl or default of one of those traits, `self.m()`
  means that trait's own. An inherent `m` keeps the plain name: `p.m()` picks it, the trait's is
  `T_Trait_m`.
- **`self`.** Untyped, it is a `*T`: fields read and write through it (`self.x = 1` changes the
  receiver). Arithmetic on it is refused, because a `*T` steps `sizeof(T)` and `load64(self + 8)`
  would otherwise silently mean something new — write `self.field`, or declare `self: *T` when you
  do want element steps. `self: T` (typed by value) is a copy, as for any struct parameter.
- **`var q: T = p;` with `p: *T` copies `*p`** at every size; write `var q: *T = p;` to alias.
- **Methods on nested fields and chains**: `b.v.sum()`, `p.v.sum()` through a pointer,
  `mk(3).v.sum()` on a call result, `c.w.v.scale(2);` as a statement — the field's address is the
  method's `self`, so a write through it lands in the outer struct.
- **Trait objects** — run-time dispatch through a vtable the compiler builds and checks — are
  `dyn Tr` (6.7.8), the next section. `lib/trait.cyr` stays as an unchecked library pattern.

## Trait objects: `dyn` (6.7.8)

A trait's methods dispatch statically: `p.area()` is a direct call to the type's method. When the
type is known only at run time — a list of shapes, a table of handlers — write **`dyn Tr`**: a value
of any type that implements `Tr`, whose method calls go through a table the compiler builds from
`impl Tr for T` and checks. Static dispatch stays the default ([ADR-004](../adr/004-convention-based-dispatch.md));
a trait never turned into a dyn costs nothing.

```cyrius
trait Shape {
    fn area(self): i64;
    fn twice(self): i64 { return self.area() * 2; }   # a default
}
struct Sq { s; }
struct Rect { w; h; }
impl Shape for Sq { fn area(self): i64 { return self.s * self.s; } }
impl Shape for Rect { fn area(self): i64 { return self.w * self.h; } }

fn scaled(o: dyn Shape, k): i64 { return o.area() * k; }   # one fn, any Shape

fn main(): i64 {
    var q = Sq { 3 };
    var r = Rect { 2, 5 };
    var a: dyn Shape = &q;           # the dyn holds &q and Sq's table
    var b: dyn Shape = &r;
    return scaled(a, 1) + scaled(b, 1) + b.twice();   # 9 + 10 + 20 = 39
}
syscall(60, main());
```

**What a dyn is.** `dyn Tr` is an ordinary 16-byte struct of two words: the **data word** (word 0)
and a pointer to the **vtable** (word 1) — so [ADR-002](../adr/002-everything-is-i64.md)'s
one-word values stay as they are, and a dyn goes wherever a 16-byte struct goes: a local, a global
(after the first statement or in the declaration section), a parameter, a return value, a struct
field, a trait member's signature, a closure's capture (by value), a `secret var`. A copy copies both
words: `var o2: dyn Shape = o;`, or `var x = mk();` for a fn returning one. The vtable has one slot
per trait member, in declaration order.

**Forming one.** Where the destination is typed `dyn Tr` — a `var o: dyn Tr = ..`, an assignment
`o = ..` (a classic-`for` step too), a field store `h.o = ..`, an argument to a `dyn Tr` parameter,
a `return` in a fn declared `: dyn Tr` — the compiler forms a dyn from a source it can type:

| Source | Type `T` | Data word |
|---|---|---|
| `&p` — an inline struct local, a by-value struct parameter, an inline struct global | p's struct | `&p` |
| a `*T` local, parameter or global; an untyped impl `self`; a pointer-mode handle (`var h: Sq = alloc(8);`) | `T` | the pointer |
| a `*T` field (`h.pp`); a call or a method returning `*T` | `T` | the pointer |
| a **declared** scalar — a local, global or parameter annotated with an integer type, `f64`, `f32`, `bool`, an enum or `cstring` | the annotation | the **value** |
| a literal: `5`, `-5`, `'A'` (`i64`), `2.5` (`f64`), `true` / `false` (`bool`) | as listed | the value |
| another dyn of the same trait (a name, a field, a call returning one) | — | a copy |

Parentheses around the whole source change nothing. `T` must implement `Tr`; otherwise the forming
is refused, naming the missing `impl Tr for T`. A scalar impl (`impl Num for i64`) receives the
value as `self`:

```cyrius
trait Num { fn num(self): i64; }
impl Num for i64 { fn num(self): i64 { return self * 2; } }
impl Num for f64 { fn num(self: f64): i64 { return f64_to(self * 10.0); } }

var LIMIT: i64 = 4;

fn get(o: dyn Num): i64 { return o.num(); }

fn main(): i64 {
    var n: i64 = 5;
    var o: dyn Num = n;          # the data word holds 5, not &n
    n = 6;                       # o still holds 5
    return o.num() + get(LIMIT) + get(7) + get(2.5);   # 10 + 8 + 14 + 25 = 57
}
syscall(60, main());
```

Every other source is refused by name, at the source:

- an **untyped name** — under ADR-002 it is an `i64` that may hide a pointer: pass `&x` for a
  struct, or bind it to a declared type first (`var n: i64 = x;`);
- a **bare struct** `p` — there is no implicit `&`: write `&p`;
- `&q` of a pointer (write `q`), `&n` of a scalar (write `n`: a scalar's dyn holds its value), `&o`
  of a dyn (copy it), and a pointer to a scalar such as `q: *i64` (bind the value: `var n: i64 = *q;`);
- a closure's captured name (bind it to a declared local first);
- any other expression — `alloc(..)`, arithmetic, a string literal, an enum constant, `&a + i *
  sizeof(T)`, a call returning an `i64`: bind it to a declared variable first (`&a[i]` and `&h.f` are
  not expressions at all — refused by name);
- at top level, forming into an assignment, a field or an argument — there is no frame to build the
  dyn in (a top-level `var G: dyn Tr = ..;` is fine, in the declaration section or after it).

**A dyn holds the address, not a copy.** `var o: dyn Shape = &q;` sees every later change to `q`, and
so does every copy of `o`. A dyn formed from `&local` and returned outlives the local exactly as
`return &local;` does — it dangles.

**The check, once per pair.** The first forming of a (trait, type) pair checks `impl Tr for T`
against the trait in full: each parameter after `self` and the return by its resolved type (an
untyped parameter, or an omitted return, is `i64`), generic-ness and `...`; the value class — a
method returning a `: stack` pair (`return Ok(..);`) fills a slot only when the trait member declares
that enum (`: Result`), so the call through the dyn returns what the trait declares; and the `self` a dyn can
feed. For a struct `T` that is an untyped `self`, `self: *T`, or a `self: T` over 8 bytes (passed by
address and copied on entry). **A `self: T` of 8 bytes or less is refused**, naming the method: it
arrives in a register, and the data word is a pointer — declare `self` untyped or `self: *T`. (A
struct with `u8` / `u16` / `u32` / `f32` fields can shrink into it: since 6.7.10 `struct C4 { r:
u8; g: u8; b: u8; a: u8; }` is 4 bytes, so `dyn Show` from a `C4` whose `show` takes `self: C4` is
refused, where at 32 bytes it formed one — see [Field types](#field-types-v6610).) For a
scalar `T`, `self` is untyped or `self: T`; `self: *T` is refused. A `#naked` method cannot fill a
slot. A pair is reported once; a pair never formed keeps the parameter-count check of
*Traits and impl blocks* — nothing about static traits changes. Every forming site also applies the
`&f` rule to each method in the table: one private to another file is refused, a `#deprecated` one
warns.

**Defaults and names.** A member with a default body fills its slot with `T`'s own instance of it,
so `self.area()` inside `twice` is `T`'s `area`, a static call. When a name collides, the slot holds
`T_Tr_m`, never an inherent `T_m`.

**The call.** `o.m(args)` is an indirect call through `m`'s slot with the data word as `self`, from
every receiver a method call takes: a local, a parameter, a global, a capture, `h.o.m()`, `hp.o.m()`
through a pointer, `self.o.m()`, a call's result, a chain, and at top level. The arguments and the
result follow the **trait member's** signature exactly as a direct call follows a fn's: by-value
structs, a dyn formed in place, `: Str` literals, `f64` / `f32` / `bool`, vectors, any number of
arguments; a struct result of any size, a dyn, a `*T`, an `f64` (typed: `o.rf() + 1.0` is a float
add). A member declared `: Result` (a `: stack` enum) returns its pair, as a direct call does:
`o.div(d)?` propagates, a destructure binds both, and a one-name bind is refused (`bind both`); any
other member returns one value, so a destructure of it is refused. The callee and `self` are read
before the arguments run. Refused by name:

- a member the trait does not declare;
- a **generic** member (`fn pick<U>`): the trait can still be a dyn, but a call through one has no
  instance of `pick` to run — call it on the concrete type;
- a member the trait declares without an untyped `self` first (no parameter, or `self: T`);
- a variadic member, and one returning multiple values or a vector;
- **named arguments** — a call through a dyn passes them by position;
- the wrong count, in every call's words (`'dyn Shape.area' expects 1 argument, got 2` — `self`
  counted).

**The two words are opaque.** A dyn is not a value and has no fields: a dyn used as a value (an
operator, `if (o)`, `print(o)`, an untyped argument, `var x = o;`), `&o`, `o.data` / `o.vtable`, a
multi-value destructure, `return (a, b)` in a fn returning a dyn, and a struct literal writing a dyn
field's words (`H { 1, 2, 3, 4 }`) are all refused. So is a dyn RESULT anywhere but a dyn: `x = mk();`
into an untyped, `i64` or `*T` variable (a `for` step too), `var y: i64 = mk();` (any annotation that is
no struct), a top-level `var G = mk();`, and `return mk();` from a fn that does not return that dyn. Copy a dyn whole or call its methods. Raw memory
stays raw: `load64(&w)` of a record holding a dyn, or `rethi()` after a call returning one, reads the
words as it reads any bytes — unchecked, as `load64` always is.

**Where a dyn may not go.** `dyn Tr` is written after a `:`. It is not a type argument
(`Vec<dyn Shape>`, `Box<dyn Shape>`, `f<dyn Shape>(..)`), a pointer (`*dyn Shape`), an array,
slice, tuple or multi-value element, an operand of `sizeof`, an `impl` target, or `dyn A + B` (one
dyn holds one vtable). A generic, `async`, `const` or `#naked` fn holds none, and neither does a
generic struct, a union or a `#derive`d struct. To keep many, hold each in a record and keep the
records:

```cyrius
trait Shape { fn area(self): i64; }
struct Sq { s; }
impl Shape for Sq { fn area(self): i64 { return self.s * self.s; } }

struct Item { id; o: dyn Shape; }          # a record holding a dyn

fn item(id, o: dyn Shape): i64 {
    var it: Item = alloc(sizeof(Item));    # a heap record (a pointer-mode handle)
    it.id = id;
    it.o = o;
    return it;
}

fn main(): i64 {
    alloc_init();
    var a = Sq { 2 };
    var b = Sq { 3 };
    var v = vec_new();                     # a Vec of records, never of dyn
    vec_push(v, item(1, &a));
    vec_push(v, item(2, &b));
    var sum = 0;
    for (var i = 0; i < vec_len(v); i = i + 1) {
        var it: Item = vec_get(v, i);
        sum = sum + it.id * it.o.area();
    }
    a.s = 4;                               # each dyn holds &a / &b, not a copy
    var first: Item = vec_get(v, 0);
    return sum + first.o.area();           # 1*4 + 2*9 + 16 = 38
}
syscall(60, main());
```

**Initialise it.** Struct locals are not zeroed, so `var o: dyn Shape;` is refused, and so is a
struct local holding a dyn (directly, through a nested struct or a generic instance) declared
without its value, or an array of such structs. A heap record holds whatever the allocator gave it
until a dyn is stored.

**How it is built.** The vtable is a hidden global, one per (trait, type) pair formed, filled where
each dyn is formed: no target relocates a word in data (PIE, Mach-O arm64, PE). A method in a vtable
is address-taken, as `&f` makes a fn, so dead-code elimination keeps it. The call is
`call [rbp+disp32]` on x86 (PE included), `blr` on aarch64. Each trait member a dyn calls is a bodiless fn named `dyn Tr.m`, which an `object;` build
lists as one undefined symbol (GNU ld links it). [ADR-007](../adr/007-traits.md) records the
design.

`lib/trait.cyr` keeps its run-time vtables as an unchecked library pattern; its `{ vtable, data }`
order is the reverse of a dyn's, and the two do not interconvert.

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

The `: Type` annotation is required — an untyped local holding a
struct pointer is refused at `.field` (`no struct type in scope`).
Whether a struct-typed name holds the struct inline or a pointer to
it is recorded at its declaration (see [Where a struct lives](#where-a-struct-lives-v665)).

### A string literal passed to a `: Str` parameter is wrapped for you

```
fn slen(s: Str): i64 { return str_len(s); }

var n = slen("abcde");        # = 5 — the compiler emits str_from("abcde")
```

The wrap is driven by the CALLEE's `: Str` annotation, so it happens
wherever the call is written — and *wherever* means on every target as well
as in every call syntax: a direct call, a method `obj.m("lit")`, a tail call
`return f("lit")`, a named argument, and a vector-returning receive
(`var v: f64v2 = f("lit", k)`, which on Windows writes through a hidden
pointer). ⚠ Before v6.6.5 the method, tail-call and Windows vector-receive
paths skipped the wrap: the callee received a raw cstring pointer and every
`Str` accessor read the wrong shape, silently (`var r = f("abcde")` and
`return f("abcde")` returned 5 and 0 in the same program).

If you would rather not depend on the wrap at all, `f(str_from("abcde"))` is
always correct and always has been.

### An inline `Str` passes its header (6.7.13)

A `Str` is a heap handle by name: a `Str` variable holds the ADDRESS of a 16-byte `{ data; len; }`
header (`str_new`, `str_from`). A `Str { p, n }` literal is an INLINE header, in
the frame or, at top level, in the data section. Wherever a `Str` VALUE is taken, its bare name is that
header's address (the user's decision D7 (1), 2026-10-15), with no allocation:

```cyrius
fn slen(s: Str): i64 { return str_len(s); }
fn demo(): i64 {
    var t: Str = Str { "abcdefg", 7 };
    var n = slen(t) + str_len((t));   # 7 + 7: `&t` is passed
    var h: Str = t;                   # a second handle to t's header (`var h = t;` too)
    h.len = 3;                        # writes t.len
    return n + t.len;                 # 17
}
```

So do `h = t` into a `Str` handle (a rebind), a method's or a generic's `Str` parameter, a `p: *Str`
parameter (`&t`, as `fp(&t)` passes), and an inline `Str` global (its static address) anywhere. ⛔ A
frame's inline `Str` cannot outlive the frame, so these are refused by name: `return t;` from a fn returning `Str` (*cannot return the inline Str 't' from a fn
returning Str - its header lives in this frame and would dangle (return a handle: str_new(data, len))*),
and a store into a `Str` global, a `Str` field (a struct literal's too) or through a `*Str` (*cannot store
the inline Str 't' into a global* / *into a field* / *through a pointer*). Build a `Str` that outlives its
fn with `str_new(p, n)`. An inline `Str` global is never refused, and a closure that captures `t` holds a
copy of the header in its environment, which lives as long as the closure. A position that takes no `Str`
value — an untyped parameter or variable, an untyped fn's `return` — still takes the header's first word.
A `var t: Str;` declared with no initialiser is not covered: its bare name is still its first word, as is
a copy of it (`var h: Str = t;`), so `t = a` with `a` a handle stores `a` there and `str_len(t)` reads a's
string, as through 6.7.12 (whether `t = a` should copy the header instead is an open question).
Through 6.7.12 every `Str` position took that word: `slen(t)` read the length from the bytes after the
string (0 for this `t`) on every target, and `var h: Str = t;` was a copy whose own first word was passed.

## Syscalls

```
syscall(1, 1, "hello", 5);          # write(fd=1, buf, len=5)
var n = syscall(0, 0, &buf, 256);   # read(fd=0, buf, len=256)
syscall(60, 0);                      # exit(0)
```

## Multi-Return

```
# Native multi-return (v3.7.2) — return (a, b) puts values in two return registers (rax:rdx on x86_64)
fn divmod(a, b) { return (a / b, a % b); }
var q, r = divmod(10, 3);       # q = 3, r = 1 — destructuring bind
q, r = divmod(20, 3);           # q = 6, r = 2 — re-assigns existing variables (6.7.7)

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

# A fn declared `: (T1, T2[, T3])` returns its values (6.7.11). Every `return` is one of:
#   return (a, b);                    # a literal of the declared arity
#   return t;                         # a tuple of the declared values (see Tuples)
#   return g(x);                      # a call returning as many values, forwarded — `(g(x))`,
#                                     # an undeclared `g` whose returns are `(a, b)`, a method —
#                                     # or one whose callee is unknown (`callptr(fp, ..)`)
# Anything else is refused — `'f' returns 2 values - return (a, b)` — because it fills only
# the first return register and the caller's `b` read whatever an earlier call left:
#   return 5;   return p;   return;   # one value; a struct local (its first word); bare
#   return (a, b, c);                 # another arity
#   return one(x);   return mk();     # a one-value callee; a struct callee (a struct is
#                                     # not multiple values)
#   ret2(a, b);                       # two values in a fn declared with three (6.7.13): the
#                                     # caller's third read what an earlier call left
# A body that reaches its closing `}` returns 0 for every value (6.7.13, the user's decision of
# 2026-10-15), as running off the end of a bool fn returns `false` — every `return` is untouched,
# and nothing is refused. Through 6.7.12 the caller read whatever an earlier call left in the
# second (and third) return register:
#   fn f(x): (i64, i64) { if (x > 0) { return (1, 2); } }    # f(0) is (0, 0); f(1) is (1, 2)

# A sync fn declared ONE type may still return several values — kept (6.7.13, the user's decision
# of 2026-10-15) — but spell it `: (T1, T2)`: that names each value's type and checks every return.
#   fn g2(): i64 { return (1, 2); }   # `ret2(1, 2);` likewise
# The declared type types each value: a `: f64` fn's values are each an f64 (its bindings are f64,
# and `var t: (i64, i64) = g(..);` is refused), and a `: bool` fn's first value is checked as its
# bool. Pass 1 counts it as it counts an undeclared fn (every `return` `(a, b)`, the body left only
# through them), so `var a, b, c = g2();` and a 3-tuple capture are refused. A one-name bind,
# `var a = g2();`, keeps the first value, as for any multi-value callee (`rethi()` reads the second).

# The destructure requires a CALL as the whole right-hand side (v6.5.21) — `f(..)`, `g<T>(..)`,
# `x.m(..)`, and a call through a fn pointer, `fncallN(fp, ..)` or `callptr(fp, ..)` (6.7.13: `callptr`
# was refused "needs a call"); a callee held in a variable is unknown, so its count is not checked.
# These are rejected rather than silently reading whatever rdx held:
#   var q, r = 42;                    # not a call
#   var q, r = dm(17, 5) + (k / 9);   # call is not the whole RHS
#   var x, y, z = f();                # count disagrees with f's declared arity
#   var q, r, z = dm(17, 5);          # `dm` is undeclared, but every `return` is `(a, b)` and its
#                                     # body is left only through them: it returns 2 values, and
#                                     # the count is checked as a declared one is (6.7.11)
#   var q, r = h3(5);                 # and in the other direction: `h3` undeclared, every `return`
#                                     # `(a, b, c)` — "binds 2 names, but 'h3' returns 3 values"
#                                     # (6.7.11, kept by the user 2026-10-15; through 6.7.10 the
#                                     # leading two were taken)
#   var a, b = one(1);                # `one` returns ONE value (6.6.17): every `return` is a
#                                     # single value and the body ends in one — at fn scope and
#                                     # at top level, a forward-declared `one` included. A body
#                                     # ending in `loop { }`, `while (1) { }` or
#                                     # `do { } while (1);` that no `break` leaves ends in its
#                                     # returns too (6.7.11), and `while (true) { }` /
#                                     # `do { } while (true);` (6.7.13)
#   var a, b = mk(5);                 # `mk` returns a struct over 16 B: it comes back through a
#                                     # hidden pointer, not registers, so there is no second word —
#                                     # `cannot destructure 'mk' - it returns struct 'Q', which is
#                                     # not in registers` (6.7.11). A 9-16 B struct's two words ARE
#                                     # its return registers: `var a, b = mk(5);` binds them, and a
#                                     # third name is refused; an 8 B struct is one value
# (Before 6.6.17 the top-level destructure above the first statement checked none of these.)

# Legacy builtins still work
fn divmod_old(a, b) { ret2(a / b, a % b); }
var q2 = divmod_old(10, 3);     # q2 = 3 (rax)
var r2 = rethi();                # r2 = 1 (rdx)
```

To keep a multi-value result whole, capture it in a tuple — `var t: (i64, i64) = divmod(10, 3);`,
then `t.0` / `t.1` — see [Tuples](#tuples).

**A multi-value call is not a struct value** (6.7.11). Where a named struct is expected — a by-value
struct argument (`take(mk(3))`, `take(b.mk(3))`, a named argument), a struct-typed declaration (`var p:
P = mk(3);`, at fn scope and at top level), a struct field (`h.p = mk(3);`) or an assignment to a struct
variable (`p = mk(3);`, a classic-`for` step too) — a call returning several values is refused by name at
every struct size, parentheses around it transparent: ``a multi-value call 'mk' is not a struct 'P'
argument - bind it first: `var a, b = mk(..);` `` (and `does not initialize struct 'P'`, `is not stored
into a struct 'P' field`, `is not assigned to struct 'P'`). It used to hand over its FIRST value as the
struct's address (a crash) or as one field. Bind the values and build the struct: `var a, b = mk(3);
var p = P { a, b }; take(p);`. A callee declared `: P` returns a `P` and is accepted everywhere a `P` is (its
`return (x, y);` is refused since 6.7.11: a tuple is not the struct). A `*P` and a `Str` handle take a word — the call's first value, as `var x = mk(3);`
does — and are not refused.
A `return` is the fifth such destination (6.7.13, the user's decision of 2026-10-15): in a fn returning a
struct of 8 bytes or less, `return mk(3);` (`(mk(3))`, `b.mk(3)` too) returned the call's first value as
the struct's word, and is refused as ``a multi-value call 'mk' is not returned as struct 'P1' - bind it
first: `var a, b = mk(..);` ``; the 9-16 byte and over-16-byte classes already refused it by their own
texts.

## Tuples

A tuple is a fixed group of values, each in its own 8-byte slot (6.7.7). `(a, b)` builds one,
`(i64, f64)` is its type, and `t.0`, `t.1`, … name its elements:

```
fn tuples(): i64 {
    var t = (5, 9);                  # (i64, i64): an un-annotated literal's elements are i64
    var p: (i64, f64) = (1, 2.5);    # a float element needs the type declared
    t.0 = t.0 + 1;                   # an element reads and writes like a field
    t.1 *= 2;                        # every compound operator
    t = (t.1, t.0);                  # every element is read before any is stored: a swap
    var u: (i64, i64) = t;           # a copy, by value
    u.0 = 100;                       # t is untouched
    if (p.1 > 2.0) { return t.0 * 10 + t.1; }   # 186 — p.1 is an f64: a float compare
    return 0;
}
```

A tuple is an **anonymous struct**: `(i64, f64)` is a struct of two 8-byte fields named `0` and
`1`, interned once per element list, so a struct's storage rules hold for it — it is stored
inline, copied byte for byte, passed to a parameter by address and copied on entry — except that
where a struct's first word would stand in for it as one value, a tuple is refused
([A tuple is not a number](#a-tuple-is-not-a-number)). Two
tuple types are the same type exactly when their element lists are equal: `(i64,i64)` and
`(i64, i64)` copy into each other, and a copy between any other pair is the struct copy's type
error. Diagnostics name a tuple by its spelling, `(i64, f64)`.

**Where the type goes.** A `var` (a local, or a global in either zone), a parameter, a struct
field, and a fn's multi-value return `: (T1, T2)` / `: (T1, T2, T3)`:

```
struct Seg { id; span: (i64, i64); }    # the tuple is laid out inline: Seg is 24 bytes

fn width(s: (i64, i64)): i64 {          # by value: the callee works on its own copy
    s.1 = s.1 - s.0;
    return s.1;
}

fn bounds(n): (i64, i64) {              # two values, in the multi-value return registers
    var t = (n - 1, n + 1);
    return t;                           # a tuple from a fn declared with its values
}

fn seg_demo(): i64 {
    var g: Seg;
    g.id = 1;
    g.span = (3, 10);                   # a literal stored into a tuple field
    var w = width(g.span);              # 7 — g.span is still (3, 10)
    var b: (i64, i64) = bounds(5);      # captures BOTH values: (4, 6)
    var lo = 0;
    var hi = 0;
    lo, hi = bounds(w);                 # re-assigns two existing variables: 6, 8
    return w + b.0 + hi + g.span.1;     # 7 + 4 + 8 + 10 = 29
}
```

A positional struct literal fills a tuple field's elements as leaves (`Seg { 1, 3, 10 }`) or takes
a whole tuple (`Seg { 1, t }`). A top-level `var ORIGIN = (3, 4);` is a global tuple; when every
element is a constant it is baked into the image, as `var G = P { 3, 4 };` is. `secret var t =
( .. );` is wiped whole at the fn's exit.

**Elements are `i64`, `f64` or `bool`**, 2 to 256 of them. An `f64` element is typed (`t.1 + t.1`
is a float add); a `bool` element is checked like a `bool` field. Everything else is refused by
name, each open to a later release: the narrow integers and `f32`, `u64` (its identity with `i64`
is undecided), `u128`, a pointer, a slice, a vector, a struct or union, a nested tuple. Store a
narrow value in an `i64` element. **An un-annotated literal is `(i64, …, i64)`**: an untyped
float is an integer bit pattern (ADR-002), so `var p = (1, 2.5);` is refused — declare the
tuple's type, `var p: (i64, f64) = (1, 2.5);`. In an annotated literal an integer into an `f64`
element keeps its bits and is warned, as in a struct literal.

**`t.N` is a selector only when the digit touches the `.`.** `t.0.1` is two selectors; `t. 0`
(a space) is a name, a `.` and the number 0. A selector past the arity is an unknown field
(`unknown field '2' on struct '(i64, i64)'`), and so are `t.01` and `t.0x1`: the selector is the
whole run of letters and digits. `p.0` on a named struct is an unknown field too. A tuple has no methods: `t.m()`, `t.0()` and `impl (i64, i64)` are refused.

**Where a literal goes.** A `var` initializer, an assignment to a tuple variable (`t = (..);`),
a store into a tuple field (`h.p = (..);`), a tuple argument (`width((3, 10))`) and `return (a,
b);`. In the var, assignment, field and argument positions, parentheses around the whole literal
are transparent (`((1, 2))`); a multi-value return keeps its exact spelling, `return (a, b);`
(`return ((a, b));` is refused), and only in a fn declared `: (T1, T2[, T3])` or with no return
type — a fn returning a named struct refuses it (6.7.11). Anywhere else — an operand, an untyped or `callptr` argument, an
if-expression branch, `(1, 2).0`, a struct literal's element — it is refused by name. At top level
only the declaration works: `G = (3, 4);` and `take((1, 2))` build the literal in a frame temporary
first, so they need a fn.

### Capture by type: `var t: T = f();`

A tuple-typed destination **captures every value of a multi-value call** — `var t: (i64, f64) =
f();` in a fn or at top level, and `t = f();` into an existing tuple. A plain `var x = f();` is
still the call's **first** value (the documented `ret2` / `rethi()` idiom): nothing that compiled
before tuples changed meaning.

```
fn divmod(a, b): (i64, i64) { return (a / b, a % b); }
fn halves(x): (i64, f64) { return (x, f64_div(f64_from(x), 2.0)); }
fn pair_of(x) { return (x, x + 1); }       # undeclared: the capture does not check it

fn capture(): i64 {
    var x = divmod(20, 3);                 # 6 — one name is still the FIRST value
    var t: (i64, i64) = divmod(20, 3);     # (6, 2) — a tuple keeps every value
    var h: (i64, f64) = halves(5);         # (5, 2.5): the f64 element takes the f64 value
    t = divmod(t.0 * 10, 7);               # re-capture into an existing tuple: (8, 4)
    var u: (i64, i64) = pair_of(t.1);      # (4, 5)
    if (h.1 != 2.5) { return 0; }
    return x * 1000 + t.0 * 100 + t.1 * 10 + u.1;   # 6845
}
```

The right-hand side is what the destructure `var a, b = f();` takes ([Multi-Return](#multi-return)):
one whole call — `f(..)`, `g<T>(..)` or `x.m(..)` — and nothing around it. A callee declared
`: (T1, T2[, T3])` is checked element by element: its arity must equal the tuple's, an `f64`
element takes an `f64` value, a `bool` element a declared `bool`, an `i64` element any other
value. A callee that declares no values — an undeclared `return (a, b)`, `ret2`, a `: stack`
pair, a `Result` / `Option` / `Tagged` pair — is not checked, exactly as the destructure does not
check it (its `bool` element is refused: an unknown value is not a bool). Every value is read
before any is stored, so `t = f(t.1, t.0);` reads the old `t`.

**`a, b = f();` re-assigns existing variables** (two or three plain variables: locals,
parameters, globals; a classic-`for` step too) with the destructure's contract, except that a
struct- or vector-returning callee is refused by name, as the capture refuses it: a struct return
is not multiple values. A loop that re-polls no longer binds a fresh pair on every pass:

```
fn reading(k): (i64, i64) {                # (status, value): status 0 = the last one
    if (k < 3) { return (1, k + 4); }
    return (0, 9);
}

fn drain(): i64 {
    var st = 1;
    var v = 0;
    var acc = 0;
    var k = 0;
    while (st != 0) {
        st, v = reading(k);                # re-assigns both on every pass
        acc = acc * 10 + v;
        k = k + 1;
    }
    return acc;                            # 4569
}
```

**`return t;` returns a tuple** — a local, a parameter or a global — from a fn **declared with
its values** (`: (i64, i64)`, the element classes matching exactly), in the same registers
`return (t.0, t.1);` uses. From any other fn (undeclared, scalar, struct, a closure, an `async
fn`) it is refused by name.

**A closure captures a tuple as it captures a struct**: a by-value copy of the whole tuple, taken
when the closure is made.

```
fn closure_demo(): i64 {
    var t = (1, 2);
    var c = || t.0 * 10 + t.1;     # c holds its own copy of t, taken here
    t.0 = 9;                       # ... so this write is not seen
    return fncall0(c);             # 12
}
```

### A tuple is not a number

A whole tuple is not one value, so it has no meaning in a scalar position. Under the plain
struct rule `t == u` would compare first words and `var x = t;` would copy one; both are refused:

```text
var t = (1, 2);
var u = (3, 4);
if (t == u) { .. }      # error: tuple 't' used as a value - take an element (`t.0`)
                        #        or copy it whole into a tuple
var x = t;              # the same: write `var x: (i64, i64) = t;`, or read `t.0`
t = 5;                  # error: cannot assign a value that is not a tuple to tuple 't'
```

The same holds for `if (t)`, `print(t)`, `t + 1`, an untyped-parameter argument and a whole
tuple FIELD (`h.p == 5`). Compare elements, or copy the tuple into a tuple place.

### Refused by name

| Shape | The error |
|---|---|
| `(i32, i64)`, `(*T, i64)`, `(P, i64)` | `a tuple element is i64, f64 or bool, not 'i32'` (…) |
| `var p = (1, 2.5);` | `a float element needs the tuple's type declared …` |
| `(1, 2) + 3`, `g((1, 2))` (untyped `g`) | ``a tuple `( .. )` is a value only as a `var` initializer, …`` |
| `return ((1, 2));` | ``a multi-value return is written `return (a, b);` - drop the extra parentheses`` |
| `return (a, b);` from a fn declared `: P` (a named struct, any size; 6.7.11) | ``a fn returning the struct `P` returns that struct — `(a, b)` is a tuple, another type`` |
| `ret2(a, b);` in a fn declared `: P` (any size; 6.7.13) | ``a fn returning the struct `P` returns that struct — `ret2` writes two values`` |
| `var k: i64 = (1, 2);` | `a tuple literal cannot initialize 'k' - its declared type is not a tuple` |
| `G = (3, 4);` at top level | `a tuple literal assigned at top level has no frame to be built in …` |
| `var t: (i64, i64) = mk();` (`mk` returns `P`) | `cannot capture 'mk' into tuple (i64, i64) - it returns struct 'P', not a tuple` |
| `a, b = mk();` (`mk` returns `P`) | `cannot re-assign from 'mk' - it returns struct 'P', not multiple values` |
| `var a, b = mk();` (`mk` returns a 24 B `Q`), `var a, b, c = mk();` (a 16 B `P`; 6.7.11) | `cannot destructure 'mk' - it returns struct 'Q', which is not in registers …` / `cannot destructure 'mk' into 3 names - it returns struct 'P', whose 2 words are its return registers …` |
| `var t: (i64, i64) = f();` (`f` is `: (i64, f64)`) | `cannot capture 'f' into tuple (i64, i64) - it returns 2 values, (i64, f64)` |
| `var t: (i64, i64, i64) = dm(17, 5);` (`dm` undeclared, every `return` is `(a, b)`; 6.7.11) | `cannot capture 'dm' into tuple (i64, i64, i64) - it returns 2 values` |
| `var t: (i64, i64) = (f());`, `= one(1)`, `= 5` | `cannot initialize tuple 't' with a value that is not a tuple` |
| `take(f())` / `take(b.f())` into a tuple parameter (`f` declared, or undeclared with every `return` `(a, b)`; 6.7.13) | ``a multi-value call 'f' is not a tuple argument - bind it first: `var t: (i64, i64) = f(..);` …`` |
| `take(mk())` / `take(b.mk())` into a struct `P` parameter, `var p: P = mk();`, `h.p = mk();`, `p = mk();` (`mk` returns several values; 6.7.11) | ``a multi-value call 'mk' is not a struct 'P' argument - bind it first: `var a, b = mk(..);` `` (… `does not initialize struct 'P'`, `is not stored into a struct 'P' field`, `is not assigned to struct 'P'`) |
| `h.p = f();` | `a multi-value call 'f' is not stored into a tuple field - bind it first …` |
| `f().0` | ``cannot take a field of the result of 'f': it returns 2 values - bind them first …`` |
| `return t;` from a fn not declared `: (i64, i64)` | ``cannot return tuple 't' (i64, i64) - a tuple is returned by a fn declared with its values …`` |
| `return 5;`, `return p;` (a struct), `return one(x);` from a fn declared `: (i64, i64)` (6.7.11) | `'f' returns 2 values - return (a, b)` |
| `h.x, b = f();`, `a[i], b`, `*p, q` | ``a multi-value assignment `a, b = f();` re-assigns plain variables - a field is not one`` (…) |
| `a, b = 5;`, `a, b = t;` | `multi-value destructure needs a call on the right-hand side` |
| `first(t)` (`first` is generic) | `a tuple cannot bind a type parameter: 'first' is generic …` |
| a tuple type in a generic fn, a tuple field in a generic struct | `a tuple type in a generic fn is refused …` / `a tuple field in a generic struct is refused …` |
| `const C = (1, 2);`, a tuple in a `const fn` | `a tuple in a const context …` |
| `*(i64, i64)`, `[(i64, i64)]`, `(i64, i64)[4]`, `sizeof((i64, i64))`, `Box<(i64, i64)>` | `a tuple type cannot be a pointer target` (… a slice / array element, a sizeof operand, a type argument) |
| `#derive(..)` on a struct with a tuple field | `#derive reads named field types; 't' is a tuple …` |

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
`load8/16/32` and `store8/16/32`, and so (6.7.10) does a `u8` / `u16` / `u32` field and an `f32`
one (4 bytes); everything else (untyped, `i64`, `u64`, `Str`, `Vec<T>`, `f64`, a nested
`#derive`d struct) an 8-byte slot (v6.6.7; before that every accessor was `load64` /
`store64`, so a narrow field's setter wrote into its neighbours). An `i8` / `i16` / `i32` getter
**sign-extends**, exactly as `p.field` reads one: after `P_set_x(p, -1)` on an `i8` field, both
`P_x(p)` and `p.x` are `-1` (a bare `load8` would give 255). A `u8` / `u16` / `u32` getter
**zero-extends**, as `p.field` reads one: after `P_set_a(p, -1)` on a `u8` field, `P_a(p)` is
255. An `f32` getter returns the field's binary32 bits, untyped, as an `f64` getter returns
binary64 bits (see *f64 fields are typed* above). Every `#derive` reads the body the way the
parser does — comments, blank lines, `a : T` spacing, `;`-less fields and `,`-separated enum
members are all fine — and the build FAILS if its field offsets disagree
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

## Derive Serialize on a struct

`#derive(Serialize)` (or `#derive(Deserialize)`: either one gives both directions) on a struct
generates `T_to_json(p, sb)`, which appends the struct at `p` to a `str_builder` as a JSON object,
and two decoders that each return a newly `alloc`'d `T` filled from a document: the scanner
`T_from_json_str(text)` over the JSON text (it zeroes the struct first, so a key the document
lacks leaves its field 0), and the pairs form `T_from_json(pairs)` over `bayan_json_parse(..)`'s
result (a missing key leaves the field as allocated). It needs `lib/bayan.cyr` in scope.

```cyrius
include "lib/bayan.cyr"

#derive(Serialize)
struct Px { r: u8; n: u32; w: f32; host: cstring; note: cstring; s: Str; }

fn demo(): i64 {
    var p: Px;
    p.r = 255; p.n = 4000000000; p.w = 0.1;
    p.host = "a\"b"; p.note = 0; p.s = str_from("x\ty");
    var sb = str_builder_new();
    Px_to_json(&p, sb);
    var js = str_builder_build(sb);
    # {"r":255,"n":4000000000,"w":0.10000000149011612,"host":"a\"b","note":null,"s":"x\ty"}
    var q = Px_from_json_str(str_data(js));       # the scanner
    var r = Px_from_json(bayan_json_parse(js));   # the pairs form
    return load8(q) + load8(r);                   # 510: each gives every field back
}
```

A field is untyped or `i8`..`i64` (a JSON number; an `i8` / `i16` / `i32` written sign-extended),
`u8` / `u16` / `u32`, `f64`, `f32`, `bool` (`true` / `false`), `Str`, `cstring`, `Vec<T>` of
integers, `f64` or a `#derive`d struct (a JSON array), or a nested `#derive`d struct (an object).
A `u64` field is not supported (the build fails naming `u64_to_json`), nor is `Vec<Str>`. Since
6.7.10 (through 6.7.9 each of these four was refused as an undefined `u8_to_json` /
`cstring_to_json` / …):

- **`u8` / `u16` / `u32`** are a JSON number read zero-extended (`4000000000`, never negative).
  Decoding stores at the field's width, so an out-of-range number truncates, as any narrow store
  does (`300` into a `u8` is 44) — no range check, as for `i8`..`i32`.
- **`f32`** is written widened to f64, through bayan's f64 printer: 0.1f is `0.10000000149011612`,
  1.5f `1.5`. Decoding parses an f64 and rounds it to the nearest f32, so every value written comes
  back bit for bit, and a hand-written `0.1` decodes to 0.1f.
- **`cstring`** is `null` for a NULL pointer and otherwise an escaped JSON string — the `Str`
  escaper's bytes (`"`, `\` and U+0000..U+001F escaped, every other byte as is). Decoding gives NULL
  for `null` and otherwise a FRESH NUL-terminated copy (`alloc`'d; the field never points into the
  document): a JSON string unescaped per RFC 8259 — `\uHHHH` written as UTF-8, a surrogate pair
  joined into one 4-byte code point, a lone surrogate U+FFFD — and any other value its text (`42`
  gives `"42"`). A quoted `"null"` is the four-byte string `null` in both decoders, never NULL. A
  decoded `\u0000` ends the C string there.
- **`Str`** decodes every escape the same way in both decoders, into a fresh `Str` whose length
  counts a decoded U+0000. Through 6.7.9 the scanner decoded only `\n` `\t` `\r` and kept the letter
  of every other escape (`"\u0001\b"` read `u0001b`), and the pairs form stored bayan's value
  itself — every escape raw, and a borrow into the parsed document rather than a copy.

A **nested `#derive`d struct** decodes in both decoders: the scanner decodes the object through
the inner struct's own `T_from_json_str` and copies it in place, as the pairs form does. A nested
value that is not an object (`null`, a number, a string) leaves the field 0, and a field typed with
a struct no `#derive(Serialize)` / `#derive(Deserialize)` above it registered (an accessors-only
struct among them) is skipped. The scanner walks every value it does not
take — that one, an unknown key's — WHOLE, string- and depth-aware, so an object, an array or a
string holding `,` / `}` never derails it. Through 6.7.10 both skipped to the first `,` or `}` at
any depth: the nested field stayed 0, the inner object's keys were read as the outer struct's (an
outer field of the same name took the inner value) and its `}` ended the scan, so every field after
it was lost; an unknown key holding an object fed its keys to the outer struct.

A **scalar field** — an integer (typed or untyped), `f64` / `f32`, `bool`, `Str`, `cstring` — whose value
is another JSON shape is walked whole too (6.7.13): the scanner takes what its type can take and then
skips the rest of the value, so an object or an array where a number, a `bool` or a string was expected
leaves the field 0 (a `cstring`, its text) and its inner keys stay inside it — `{"a":{"q":7,"b":9},"b":4}`
decodes with `b` 4, as the pairs form reads it. Through 6.7.12 those arms stopped at the value's `{` /
`[` (a `bool` at the first inner `,`), and the scan read the inner keys as the outer struct's: `b` was 9.

The escaper and the decoders are public in `lib/str.cyr`: `str_builder_add_json_str(sb, s)`,
`str_builder_add_json_cstr(sb, p)` (`null` for a NULL `p`), `str_json_unescape(p, n)` (a fresh
`Str`) and `str_json_unescape_cstr(p, n)` (a fresh C string), the last two over the `n` bytes
between a JSON string's quotes.

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

**A `*V` parameter is a pointer (6.7.11).** `fn rd(p: *f64v2)` takes one integer word, as
`p: *Pt` does — `p + 1` steps one whole vector (16 / 32 bytes), as a `*f64v2` local's does — and
is passed `&b`, a `*f64v2`, or a vector **local** `b` itself, whose address is passed, as a struct
passed to a `*T` parameter is (6.6.20; the user's decision, 2026-10-13). A vector local of another
type is refused by name — `cannot pass 'f' to a parameter of a different vector type in a call to
'rd'` — as a struct of another type is (6.7.3), the same-size ones too (`i64v2` into `*i32v4`). ⚠
Before 6.7.11 the `*` was dropped and the parameter was a value-form vector: `rd(&b)` was refused
(`value-form SIMD arg must be a local IDENT`), and `rd(b)` compiled and faulted (the body
dereferenced lane 0's bits). A fn with a `*V` parameter that C calls, or that is called through
`fncallN`, now takes it in an integer register (the C ABI's pointer), where it took vector
registers (SysV / aarch64 / cx) or a by-pointer copy (Win64).

**A vector value that is not a named local passes an address too (6.7.12; the user's decision
D27, 2026-10-15: B).** A call declared to return the vector — `rd(mkv(42, 7))`, `rd((mkv(..)))`,
`rd(fncall2(&mkv, ..))`, `rd(callptr(&mkv, ..))` — is received into a frame temporary whose
address is passed (on Win64 the temporary is the call's hidden result pointer), as a struct call
result into `*T` is (6.6.20); a dereference `rd(*pv)` of a `*V` — a local, a parameter, a capture,
a field, a global, a `: *V` call, `pv + n` — passes `pv` itself, as `take(*p)` passes a struct's
pointer (6.7.10). A call result or a `*` of another vector type is refused with the words above. At
top level there is no frame: `'mkv' returns a vector by value, and a vector result needs storage in
a fn's frame - call it inside a fn`. `*f32v8` is a `*V` like the others (`r8(e)` passes `&e`; a
value-form `v: f32v8` parameter is a separate matter). A vector **local** passed to a pointer of
another kind — `p: *Pt`, `p: *i64`, `p: *u8`, `p: **T` — is refused by name: `cannot pass 'b' to a
parameter that is not a pointer to its vector type in a call to 'rp' - pass &b for its address`
(as a struct of another type is). ⚠ Through 6.7.11 each of these passed lane 0's bits as the
address (139 on x86_64 and aarch64, a cx guest fault, an access violation on Win64; x86_64 refused
the `*V` call result and dereference through 6.7.10 by the value-form path's text) — except on
Win64, where `rp(b)` into `p: *Pt` happened to pass `&b` and ran; it now stops compiling there too
(pass `&b`).

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
# bits, a denormal ~5e-324, and narrows to f32 ZERO. Use real float literals.
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
wrappers are gated on `CYRIUS_HAS_VAL_SIMD_PARAMS`, which every compiler
fork predefines — the Win64 PE one included (value-form SIMD parameters
and returns since v6.4.31) — and the overload dispatch routes
`f32v4_add(&a, &b)` to the pointer form on every target.

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
removed at v6.4.30; the `tests/tcyr/crossos/simd_f32v4_neon.tcyr` /
`simd_ints_neon.tcyr` / `simd_cx.tcyr` cross-OS fixtures run the real emitters on
pi (aarch64) and are verified on real hardware. Every vector type is available on every backend.
The one caveat: aarch64 has no *native 256-bit* path — its `f32v8` emitters
delegate to the 4-lane NEON emitters (since 6.5.49; they were return-0 stubs
before), and `lib/simd.cyr` routes `f32v8` through native `f32v4` NEON, so the
verb works on aarch64; only a native 256-bit path (as opposed to 2×128-bit)
stays x86-AVX2-only. The scalar `f64` /
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
  read-anything primitive the absolute-include path bug removed), and it is read **only at byte 0** — a second
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
- **A source file cannot forge its own identity (v6.6.6, the file-marker forge (private visibility) bug).** Visibility is decided from
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
  reachability gate). So does a `const fn` called in a const context — a `const`, an array
  size, an enum value, `#assert`, a `case` label (6.7.11; it ran silently before). Top-level **arrays** are covered too: `var _buf[N]` in a private file
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
#else
#ifdef CYRIUS_TARGET_WIN
    var fd = win_get_image_handle();
#else
    # macOS / other platforms fall here
#endif
#endif

#ifndef CYRIUS_BAREMETAL
    println("running on hosted platform");
#endif

#define LEVEL 2
#if LEVEL == 1
    var mode = 1;
#elif LEVEL == 2
    var mode = 2;
#else
    var mode = 0;
#endif
```

The full set: `#ifdef`, `#ifndef`, `#if`, `#else`, `#elif`, `#endif`. State is
tracked per nesting level — `#elif` after a taken `#ifdef` is correctly
suppressed, and nested blocks skip cleanly inside a parent's skip path.

`#if` and `#elif` take a CONDITION, `NAME OP NUMBER` (`==`, `!=`, `<`, `>`, `<=`,
`>=`), or a bare `NAME`, which reads the name's VALUE (0 when it is undefined). Neither
asks whether a name is DEFINED. The target builtins (`CYRIUS_ARCH_*`,
`CYRIUS_TARGET_*`, ...) are defined with the value 0, so `#elif CYRIUS_TARGET_WIN`
is never taken, on Windows or anywhere else. To test a second name for definition,
nest an `#ifdef` under `#else`, as the first block above does.

A directive's keyword, name and value are separated by any run of spaces and TABS
(v6.6.20). Before that only a single space separated them, silently: `#ifdef X<TAB>`
looked up a name ending in a tab and took the other arm, `#ifdef<TAB>X` was a comment
(so its body compiled unconditionally), and `#define FOO  1` with two spaces defined
FOO as 0. An `#else` / `#elif` / `#endif` / `#endplat` with no open block, and a block
still open at the end of the input, are ERRORS naming the directive's file and line
(v6.6.20) — they used to be ignored, which is how the malformed openers above went
unnoticed.

**Preprocessor limits.** Each table below is fixed-size, and past its limit the
compile is refused with an error that names the limit (and the entry, where there
is one). Until 6.6.20 several of these were silent.
- **Nesting: 64 levels** of `#if` / `#ifdef` / `#ifndef` / `#ifplat` in the main
  source and within each included file (an included file starts its own count;
  `#ifplat` is evaluated there too since 6.6.20). The 65th is refused at its line.
  (Before 6.6.20 deeper nesting wrote through compiler state and could silently
  change the binary.)
- **Function-like macros (`#define NAME(a, b) …`): 16, in the main source only.**
  The 17th is refused by name, a second `#define` of the same function-like name
  is refused (expansion runs after every definition is read, so only one
  definition could ever apply), and a function-like `#define` in an included file
  is refused by name — it was never a macro there. (Before 6.6.20 all three were
  silently ignored.) An invocation must pass exactly as many arguments as the
  macro has parameters — `Z()` or `Z( )` for none — and a mismatch is refused,
  naming the macro. (Before 6.6.20 an extra argument was dropped and a missing one
  read a previous invocation's argument.) Arguments are split at every comma
  outside parentheses; known gap: that includes a comma inside a string literal.
- **`#define` names: 16, including the target's builtins** (`CYRIUS_ARCH_*`,
  `CYRIUS_TARGET_*`, … — three on x86_64 Linux). A name counts once however often it
  is defined, and a redefinition's value applies to the `#if`s that follow it in
  the same file — there the latest definition wins. (Before 6.6.20 every repeat
  took a slot of its own — `include "lib/sandhi.cyr"` used 12 of the 16 — and the
  FIRST value was read forever.) Known gap: a file's `#if` / `#ifdef` is evaluated
  before the `#define`s of a file it includes are registered, so a conditional
  after an `include` sees neither a name nor a new value that the included file
  defines.
- **A function-like macro's parameter list, and one invocation's arguments: 511
  bytes each**, counting the separators. Past either the compile is refused,
  naming the macro. (Before 6.6.20 a 516-byte argument silently expanded to
  nothing, and longer ones crashed the compiler.)

`#ifplat <plat>` (v5.4.19) is a tighter spelling for architecture dispatch,
the same as `#ifdef CYRIUS_ARCH_<PLAT>`. It closes with `#endplat` or `#endif`:

```
#ifplat aarch64
    asm { dmb ish }
#endif
```

Recognized plat tokens: `x86` and `aarch64`. Any other token (`x86_64`, `riscv64`,
`linux`, `macos`, `windows`, ...) is not an error: it never matches, so the block is
skipped and an `#else` arm is taken. For an OS, use `#ifdef CYRIUS_TARGET_*`.
`#ifplat` works in the main source and in included files. (Before v6.6.20 it was not
evaluated in an included file, where both arms compiled.)

`#bounds` (6.7.8) — a line of its own in the entry file's leading block (blank lines, `#` comments
and `include "…"` lines may precede it) — switches the
[bounds-checked mode](#the-bounds-checked-mode-678) on for the whole program, and the compiler then
predefines `CYRIUS_BOUNDS` for `#ifdef`. Anywhere else, and with an argument, it is refused by name.

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
# 6.7.8 — under the bounds-checked mode a subscript inside @unsafe is not checked.

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
impl Acct {
    #must_use
    fn take(self, n): i64 { self.bal = self.bal - n; return self.bal; }
    #deprecated("use take")
    fn withdraw(self, n): i64 { return Acct_take(self, n); }
}
```

`#assert EXPR, "message";` checks a compile-time fact and stops the build
with `#assert failed: message` when it does not hold. EXPR is any const expression
(6.7.2 — [Constants and `const fn`](#constants-and-const-fn-672)): literals, consts, enum
constants (`EB` / `E.EB`), `sizeof(T)`, `const fn` calls, arithmetic, one comparison,
`&&` / `||` — `#assert sizeof(Hdr) == E.N * 8;`. (From 6.6.10 to 6.7.1 an operand was ONE
atom and arithmetic was refused.) Only `,`, the message string, `;` or the end of the line
may follow the expression; anything else (a stray word) is refused with ``expected `,` or
`;` after the expression`` — before 6.6.10 it was skipped unchecked, so a false
`#assert E.EB * 2 == 9;` compiled clean. A name that is not a constant is reported once,
by name (`unknown name 'foo'`, `'p' is a variable`), and `sizeof` must be the whole word —
`sizeofzz(P)` is refused (`unknown fn 'sizeofzz'`), not read as `sizeof`. So must its TYPE (since 6.6.11, in `#assert` and in
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
now refused rather than silently building a do-nothing program, and every `bench` / `fuzz` form
prints the `=== N passed, M failed ===` summary — their single-file form used not to, which made
it unscriptable. A bare `cyrius bench`, `cyrius fuzz` or `cyrius smoke` that finds nothing to run
exits 1 with `error: no benchmarks found (looked in benches/ and tests/, recursively)` (and the
fuzz / smoke equivalents), as a bare `cyrius test` does — ⚠ before 6.7.9 they printed "No … found"
and exited 0. `cyrius test <file>` prints the test's own output (its `N passed, M failed (T
total)` assert summary, not a `===` line) and its exit status is the test's: non-zero, with a
`FAIL:` line naming the file, when the test exits non-zero, dies of a signal, times out, or exits
0 with an assert summary that reports failures (or, when its source calls `assert_summary()`, with
none or one of 0 assertions). The `FAIL:` line says which: `(exit 3)`, `(killed by signal 11
SIGSEGV — …)`, `(timed out after …)`. The signal is read from the wait status, so a test that
EXITS with 232 or 139 says `(exit 232)` / `(exit 139)` (6.7.6 — any status over 128 used to be
called a signal: exit 232 was "killed by signal 104"); `cyrius test <file>`'s own exit status stays
the shell's `128 + signal` for a signal. The suite forms (bare, a directory, several operands) end
with an `N passed, M failed` tally of the files they ran.

**One test verb (6.7.6).** `cyrius test <file>` runs that file, `cyrius test <dir>` runs every
`.tcyr` under the directory (recursive — `cyrius test tests/tcyr/crossos`), several operands
may mix files and directories and each file runs once, and a bare `cyrius test` is unchanged.
A directory holding no `.tcyr` is a failure, by name. Until 6.7.6 `cyrius test <dir>` was
`error: not a file` and the directory walk was a second verb, `cyrius tests [dir]`; that
spelling was a deprecated alias from 6.7.6 and was removed at 6.7.12: `cyrius tests` is an
unknown command (rc 1) whose refusal names the replacement (`cyrius test <dir>`; a bare
`cyrius tests` was `cyrius test tests`).

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
bounds = true                # the bounds-checked mode (6.7.8); --bounds / CYRIUS_BOUNDS=1, also for
                             # run / test / fuzz (CYRIUS_BOUNDS=0 turns it off); see The bounds-checked mode
```

They configure every `cyrius build` in the project — a bare one AND `cyrius build <other source>
<out>` (sigil's fuzz loop builds each harness with `-D SIGIL_SMOKE` from its manifest); `-D` on
`run` stays a command-line choice, and the test scope has its own `[test] defines` (6.7.6, *Tests*
below). `CYRIUS_DCE` takes `1` or `0`; unset or
empty is no rung at all, and any other value (`CYRIUS_DCE=true`) is refused by name — cycc
itself reads every value but `1` as off, so it used to be a silent no.
`[build] test` (a file, a directory, or a list of either; since 6.7.6 the older spelling of
`[test] files`, which is what `cyrius init` writes) is what a bare `cyrius test` runs FIRST,
before every `.tcyr` under `tests/`; a file both
name runs once, and a declared path that does not exist is a named failure. Before 6.6.17
nothing read the key, so a declared `src/test.cyr` never ran — 41 manifests declared one.
`[build] test_standalone = true` (6.7.6) makes `cyrius test` — every form, and `cyrius audit`'s
test sweep — compile each test with only the includes the file itself writes: no `[deps] stdlib`
prepend. It is for a project whose tests are self-contained, the way cycc compiles a file fed to
it directly: there, a test that defines a fn some prepended stdlib module also defines (this
repo's tests that define `fn run()`, against `lib/process.cyr`'s `fn run(cmd, arg1, arg2)`) is a
duplicate-fn error under the prepend and compiles fine without it. Absent or `false` changes
nothing; `[embed]`, `[build] modules` and defines still apply. A
mistyped value (`dce = "yes"`) is refused by name, and so is a define holding a control
character (it would start a new source line in the compiled unit). `[build] target` is **held**
(pass `--target` / `--aarch64` / `--win` / `--agnos`), `[build] features` is **dropped** (features
are `[features]` + `--features`), and a key the vocabulary does not know — a typo — is warned
by name instead of being silently inert; a declared synonym (`src`) is not unknown.
`[build] strict` is **held** and warned when present: `cycc --strict` has had no effect since
6.3.2 — a reachable undefined function is an error by default and `--allow-undef` downgrades it
— so there is nothing for the key to switch. `cyrius build --strict` is still accepted and passed
through, for scripts that spell it; it changes nothing.

**The toolchain pin.** cycc compares `[package] cyrius = "X.Y.Z"` in the working directory's
`cyrius.cyml` with its own version on every compile: a drifted pin warns (`warning: cyrius.cyml
pins 0.0.1 but cycc is 6.7.12 — toolchain drift …`; `CYRIUS_NO_WARN_PIN_DRIFT=1` silences it), and
`cyrius build --strict-pin` (`CYRIUS_STRICT_PIN=1`) makes it an error — rc 1, nothing written — so
a CI build fails on drift. Since 6.7.12 that holds for every host's compiler: through 6.7.11 the
check was Linux-only, so cycc.exe and both macOS compilers built a drifted pin with no message and
`--strict-pin` passed there.

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
| `[build]` | `test` | read | — | — | `<path>...` | bare cyrius test: these (file / dir / list), then tests/ (read when [test] files is absent) |
| `[build]` | `test_standalone` | read | — | — | — | cyrius test: each test compiles standalone, its own includes only (no [deps] stdlib prepend; bool) |
| `[build]` | `modules` | read | — | — | — | every compile: these files prepended before the entry |
| `[build]` | `dce` | read | — | `CYRIUS_DCE` | `--dce` | cyrius build: dead-code elimination (bool) |
| `[build]` | `bounds` | read | — | `CYRIUS_BOUNDS` | `--bounds` | build / run / test / fuzz: the bounds-checked mode (bool); an entry file's #bounds line is the lowest rung |
| `[build]` | `strict` | held | — | — | `--strict` | has had no effect since 6.3.2: a reachable undefined function is an error by default; --allow-undef downgrades it |
| `[build]` | `defines` | read | — | `CYRIUS_DEFINES` | `-D` | cyrius build: one #define per name |
| `[build]` | `target` | held | — | — | — | pass --target / --aarch64 / --win / --agnos on the command line |
| `[build]` | `features` | dropped | — | — | — | features are [features] + --features |
| `[coverage]` | `programs` | read | — | — | `--programs` | cyrius coverage: RUN programs in the corpus (globs) |
| `[coverage]` | `exec` | read | — | — | `--exec` | cyrius coverage --exec: RUN programs built instrumented and run; the fns they enter are counted (globs) |
| `[sections]` | `base` | read | — | — | — | bare-metal builds: the image load base |
| `[embed]` | `*` | read | — | — | — | every compile: the file's bytes as NAME() / NAME_len(), prepended before the entry |
| `[test]` | `files` | read | — | — | `<path>...` | bare cyrius test: these (file / dir / list) first, then tests/ ([build] test is the older spelling) |
| `[test]` | `modules` | read | — | — | — | test / bench / fuzz compiles only: these files prepended before the entry |
| `[test]` | `defines` | read | — | `CYRIUS_DEFINES` | `-D` | test / bench / fuzz compiles only: one #define per name |
| `[test]` | `timeout` | read | — | `CYRIUS_TEST_TIMEOUT` | `--timeout` | test / bench / fuzz: seconds each may run (0 = no deadline; default 300) |
| `[test]` | `stdlib` | read | — | — | — | cyrius deps vendors them into lib/; prepended to test / bench / fuzz compiles only (never a build, never a dist sidecar) |
| `[test.embed]` | `*` | read | — | — | — | test / bench / fuzz compiles only: as [embed] (NAME() / NAME_len()) |
| `[deps]` | `stdlib` | read | — | — | — | cyrius deps: stdlib leaves vendored into lib/ and auto-prepended |
| `[deps.*]` | `git` | read | — | — | — | cyrius deps: the repository to clone |
| `[deps.*]` | `tag` | read | — | — | — | cyrius deps: the tag to check out |
| `[deps.*]` | `path` | read | — | `CYRIUS_LOCAL` | `--local` | cyrius deps: beside git/tag a dev override, read only in local mode; alone, the dep's source |
| `[deps.*]` | `modules` | read | — | — | — | cyrius deps: the files to vendor |
| `[deps.*]` | `modular` | read | — | — | — | cyrius deps: sub-modules from `dist/<name>/` |
| `[deps.*]` | `requires` | read | — | — | — | cyrius deps: stdlib leaves the dep needs in scope |
| `[deps.*]` | `optional` | read | — | — | `--features` | cyrius deps: resolve only when a feature names it |
| `[deps.*]` | `target` | read | — | — | `--target` | cyrius deps: resolve only for a matching target |
| `[deps.*]` | `scope` | read | — | — | — | "test": resolved by every resolve, prepended to test / bench / fuzz compiles only; a dependency's own are never walked |
| `[lib]` | `modules` | read | — | — | — | cyrius distlib: the base bundle |
| `[lib.*]` | `modules` | read | — | — | `<profile>` | `cyrius distlib <profile>` |
| `[lib]` | `embed` | read | — | — | — | cyrius distlib: the [embed] entries the base bundle carries |
| `[lib.*]` | `embed` | read | — | — | `<profile>` | `cyrius distlib <profile>`: the [embed] entries this bundle carries |
| `[features]` | `default` | read | — | — | `--no-default-features` | cyrius deps: features on by default |
| `[features]` | `*` | read | — | — | `--features` | cyrius deps: a feature and the optional deps it turns on |
| `[groups]` | `*` | read | — | — | — | cyrius deps: a named group of stdlib leaves |
| `[release]` | `bins` | read | — | — | — | release.yml, install.sh, cyrius pulsar |
| `[release]` | `cross_bins` | read | — | — | — | release.yml, install.sh, cyrius pulsar |
| `[release]` | `scripts` | read | — | — | — | release.yml, install.sh, scripts/release-scripts.sh |

## Embedding data files: `[embed]`

`[embed]` (6.6.19) puts a file's bytes into the program, so a binary can answer from data baked
into it — presets, a font, a dictionary, a web page — with no generator script and no generated
`.cyr` to keep in sync:

```toml
[embed]
PRESET_LEAN = "presets/quality-lean.json"
FACE = "assets/face.ttf"
```

```cyrius
syscall(1, 1, PRESET_LEAN(), PRESET_LEAN_len());   # the bytes, then their count
```

Each entry `NAME = "path"` gives every compile two functions: `NAME()` returns a pointer to the
file's bytes and `NAME_len()` their count. The bytes are exact — binary is fine, NULs included —
and are followed by one NUL, so a text file can be used as a C string as long as it holds no NUL
of its own. The file is read when the build runs, so an edited data file is in the next build;
there is nothing to regenerate and nothing to go stale.

**How it works.** cbt generates, ahead of your entry file, one module per entry —
`fn NAME(): i64 { return "…"; }` and `fn NAME_len(): i64 { return N; }` — with the bytes escaped
(printable ASCII as itself except `"` and `\`, every other byte as `\xHH`), so each literal is one
pure-ASCII source line that no preprocessor rule can see into. The module is line-neutral: an
error on line 3 of your entry still reports `<source>:3`. It is a **function, not a `var`**: a
top-level `var X = "…";` is a store that runs when the top-level code does (after the program, in
an x86 `kernel;` build), while a function's literal is a static address from the first
instruction.

**The rules** — every refusal names `cyrius.cyml [embed] NAME` and the reason:

- `NAME` is an identifier (`[A-Za-z_][A-Za-z0-9_]*`, at most 64 characters) and not a reserved
  word (`match`, `syscall`, `sizeof`, `load8`, …): it becomes `fn NAME()`. `X` and `X_len` cannot
  both be declared, and a name may appear once. A `NAME` or `NAME_len` that is already declared —
  by any leaf of the pinned stdlib snapshot, by `[build] entry` or `[build] modules`, or by a `.cyr`
  under `src/` or `lib/` — is refused (`[embed] vec` is, because of `vec_len`): left to "the last
  definition wins", the stdlib would silently win in your build, and the embed would silently
  replace the stdlib function in every consumer of a bundle that carries it. The one leaf not
  counted is the project's own fold — the snapshot leaf named for its `[package] name`, which
  declares `NAME` because this `[embed]` generated it (sankoch building sankoch, 6.7.6).
- The path is relative to the project and stays inside it: no leading `/`, no `\`, no `:` (a
  drive, or an NTFS stream such as `.git::$INDEX_ALLOCATION`), no `..`, no control character, no
  8.3 short-name component (`~` and a digit, as in `GIT~1`), no code point HFS+ ignores (U+200C–200F,
  U+202A–202E, U+206A–206F, U+FEFF), no `.git` component (in any case), and the file has a single
  hard link. **No symlink anywhere
  on the path** — `[embed]` is the one key that copies a file into a built artifact, and a link
  committed into an untrusted checkout could ship any file on the build machine inside a release
  binary. The file must exist and be a regular file; it is opened once and the bytes the build
  embeds are the bytes that were checked. The open itself refuses a link too, so a directory
  swapped for one after the check (a second writer racing the build) is not followed: on Linux
  and macOS it walks the path from a handle on the project root, never following a link; on
  Windows, which has no such walk, the opened file's final path must lie inside the project
  root's, so a junction or directory link leading outside is refused (6.7.12 — Windows and Apple
  Silicon followed one). `${file:}` reads through the same open.
- One path string per entry. A `{ dir, glob, prefix }` set, an array or an `[embed.X]` section is
  refused: list each file (an order that depends on a directory listing is a trap).
- **Size.** Every string literal lives in cycc's string pool, 2 MiB (2,097,152 bytes, NUL
  terminators included). One file may be at most 2,097,150 bytes and all embeds together at most
  2,097,151 (each plus its NUL); past that the build is refused with every entry's size listed.
  The pool is **shared with the program's own strings** — the stdlib's, the `[package] version`,
  your own — so real embeds should stay well under it. Anything larger (a 40 MB asset) is not an
  embed: read it at run time.

**What it costs.** The whole string pool is copied into the binary, so **every compile carries
every embed** — each test binary of the project, each program, even one that never calls
`NAME()`, and even under dead-code elimination (DCE removes the function, not its bytes).

**Bundles.** `cyrius distlib` carries only the embeds a bundle names: `[lib] embed = ["NAME"]`
for the base bundle, `[lib.PROFILE] embed` for a profile, nothing by default. A profile may be
embed-only (`[lib.face]` with `embed = ["FACE"]` and no modules is a bundle of the bytes). A
bundle module that calls an embed the bundle does not carry is refused by name, and
`cyrius distlib --check` names a bundle STALE once its data file changes — so a committed bundle
gets the freshness check a generator script never had. `--modular` writes each carried embed as
its own `embed_<NAME>` sub-module.

`cyrius-lsp` does not read the manifest, so it shows `NAME()` as undefined.

## Tests: `[test]`, `scope = "test"`, `test.cyml` (6.7.6)

Test-only configuration has its own section, and it reaches the **test scope** — the compiles of
`cyrius test`, `cyrius bench` and `cyrius fuzz` (and `cyrius audit`'s test / bench sweep) — and
nothing else: `cyrius build`, `run`, `distlib` and `package` never see it. A manifest without it
behaves exactly as before.

```toml
[test]
files   = ["src/test.cyr"]                 # what a bare `cyrius test` runs first, then tests/
stdlib  = ["assert", "bench"]              # stdlib leaves for the test scope only
modules = ["tests/support/fixtures.cyr"]   # prepended after [build] modules, test scope only
defines = ["TESTING"]                      # one `#define NAME` each, test scope only
timeout = 300                              # seconds per unit; 0 = no deadline

[test.embed]
GOLDEN = "tests/data/golden.bin"           # the [embed] rules, test scope only

[deps.mockpeer]
git     = "https://github.com/MacCracken/mockpeer"
tag     = "0.3.1"
modules = ["dist/mockpeer.cyr"]
scope   = "test"                           # resolved and pinned like any dep; test scope only
```

- **`files`** is what a bare `cyrius test` runs before every `.tcyr` under `tests/` (a file, a
  directory, or a list of either). `[build] test` is its older spelling and is read
  when `[test] files` is absent; with both, `[test] files` is read and `[build] test` is warned
  by name.
- **`stdlib`** leaves are vendored into `lib/` and locked by EVERY resolve, whichever verb ran it,
  so `lib/` and `cyrius.lock` are one function of the manifest — a build and a test never take
  turns rewriting the lock. Only the test scope prepends them (after the `[deps]` prepend). So a
  production binary no longer carries `assert` / `bench` (a hello world, measured at 6.7.6:
  111,456 B with them in `[deps] stdlib`, 98,280 B with them here), and a published `dist/<pkg>.deps` sidecar never
  names them (the sidecar is compile-verified from the bundle alone since 6.6.18; measured on the
  12 fold repos' bundles, their sidecars are byte-identical either way). `cyrius init` writes
  `assert` / `bench` here. A manifest whose only dependency is a test leaf still resolves.
- **`modules`** are prepended after `[build] modules`; one that cannot be read is named and the
  unit fails, not compiled.
- **`defines`**: `-D` beats `CYRIUS_DEFINES`, which beats `[test] defines` — each REPLACES the
  list, as on `cyrius build`. `cyrius fuzz` harnesses still get `[build] defines` too (since
  6.6.18), ahead of `[test] defines`; `[build] defines` do not reach `test` or `bench`.
- **`timeout`**: `--timeout N` > `CYRIUS_TEST_TIMEOUT` > `[test] timeout` > 300 s; `0` turns the
  deadline off. A unit past it is killed with its whole process tree and named.
- **`[test.embed]`** follows every `[embed]` rule (below). Its NAMEs must differ from
  `[embed]`'s (and from an enclosing level's `[test.embed]`), and a clash names the table that
  has the NAME: `cyrius.cyml [test.embed] PROD: is declared twice — cyrius.cyml [embed] declares
  it too (a test unit compiles both)`. The check against the stdlib and the project's sources
  runs after the dependency resolve, as `[embed]`'s does.
- **`scope = "test"`** on a `[deps.NAME]` is the one scope there is (any other value is refused
  by name). The dep is cloned, vendored and commit-pinned by every resolve, but resolved AFTER every
  production dependency — so a name both sides reach is the production one (a production dep's
  `leaf@v1` beats the root's test-scope `leaf@v2`, and the diamond notice names the v2 not used)
  — and its modules and their own dependencies are prepended to the test scope only. A
  dependency's own `scope = "test"` entries are its own test business: a consumer never walks
  them. `deps -v` and `deps --dry-run` mark the project's `[test scope]`; `--locked` covers them.
- `--no-deps` and `[build] test_standalone = true` drop the test scope's `stdlib` and
  `scope = "test"` prepends along with `[deps]`'s; `modules`, `defines` and the embeds still apply.

**`test.cyml` — a directory's own `[test]`.** A `test.cyml` beside a project's tests holds `[test]`
keys (`stdlib`, `modules`, `defines`, `timeout`) and `[test.embed]`, and applies to every
test-scope unit under its directory:

```toml
# tests/net/test.cyml
[test]
stdlib  = ["net"]
defines = ["NET_TESTS"]
timeout = 60

[test.embed]
CAPTURE = "capture.bin"        # tests/net/capture.bin — paths are relative to this directory
```

- Each level APPENDS to the lists above it — `cyrius.cyml`'s `[test]`, then `./test.cyml`,
  `tests/test.cyml`, `tests/net/test.cyml` — and an inner `timeout` REPLACES the outer one.
- It carries **no pin and no dependencies**: `[package]`, `[deps]`, `[build]` or any other table
  is refused by name, and so is `[test] files` (what a bare `cyrius test` runs is the project's).
  So there is nothing in it to drift from the project — the job per-test sub-manifests with their
  own pins (kept equal to the root's by a script) used to do. A `[test]` key nothing reads is
  warned by name.
- `cyrius deps` (every resolve) vendors the `stdlib` leaves of the `test.cyml` beside
  `cyrius.cyml`, of every one under `tests/`, `benches/` and `fuzz/`, and of those on the way to
  `[test] files`. A `test.cyml` elsewhere still applies when its unit runs; a leaf it names that
  the resolve did not vendor is named. A directory the resolve cannot list is warned by name.
- However the unit is spelt, it is one directory and one chain: `tests/net/x.tcyr`,
  `./tests/./net/x.tcyr`, the absolute `<project>/tests/net/x.tcyr` and, on Windows,
  `tests\net\x.tcyr` all read `tests/net/test.cyml` and the levels above it, each once. An absolute
  path is matched to the working directory by identity (6.7.12), so under a symlinked working
  directory the logical `$PWD/tests/net/x.tcyr` and the physical spelling are the same unit.
- A unit outside the project (an absolute path elsewhere, a `..`; on Windows a drive-relative
  `C:x…` or a rooted `\…` path) gets `cyrius.cyml`'s `[test]` only. On Windows a drive-rooted
  `C:\proj\tests\net\x.tcyr` (or `c:/proj/…`) inside the working directory is the project's own
  unit (6.7.12; until then every drive-qualified path counted as outside).

**At run time** each unit gets `CYRIUS_TEST_FILE` (the unit) and `CYRIUS_TEST_DIR` (its
directory) in its environment — absolute, Windows included since 6.7.12 — so a test finds data
beside itself whatever the cwd. Compile-time fixtures are `[test] modules` and `[test.embed]`.

**The exit code is the contract.** `cyrius test` — a file, a directory, several operands, or bare
— exits non-zero on any failing test (an assertion, a signal, a timeout, an assert summary that
reports a failure), any compile failure (of a test, of a refused `[test]` value, of the dependency
resolve), and when it finds no tests at all; 0 exactly when every test it found passed. A CI step
is one line, `cyrius test` or `cyrius test tests/net`, under `set -e`: no loop over files, no grep
of the summary. An operand that does not exist — any of them, `cyrius test a.tcyr missing.tcyr`
too — is refused by name BEFORE the dependency resolve (no clone, no `lib/`, no lock written), as
for `run`, `bench`, `fuzz` and `build`. `test`, `run`, `bench` and `fuzz` take `--no-deps`, `--no-lock`, `--locked` and
`--local` as `cyrius build` does; `test`, `bench` and `fuzz` take `--timeout N`.

## Build Tool & Dependencies

```sh
# cyrius.cyml declares deps — build auto-resolves them
cyrius build src/main.cyr build/myapp   # resolves deps + compiles
cyrius deps                              # manually resolve deps
cyrius deps -v                           # ...and list where each dependency came from (6.7.6)
cyrius deps --dry-run                    # each dependency and where it WOULD come from; writes nothing
cyrius deps --locked                     # CI: resolve the tags, compare with lib/ + cyrius.lock, write nothing
CYRIUS_LOCAL=1 cyrius build              # build each [deps.X] `path` override (sibling checkouts); lib/ + lock untouched
cyrius update                            # lib sync from the pin, re-fetch untagged deps, list newer tags, re-resolve (never edits cyrius.cyml)
cyrius update --full                     # ...with the whole pinned snapshot in lib/ (as lib sync --full)
cyrius build -v src/main.cyr build/myapp # verbose (shows compiler, binary size)
cyrius test tests/test.tcyr             # resolve deps + compile + run
cyrius test                              # [test] files first (6.6.17; [build] test is the older spelling), then every .tcyr under tests/, each once
cyrius test --timeout 60 --no-deps       # 6.7.6: a deadline per test; no [deps] / test-scope prepend
cyrius test a.tcyr b.tcyr -D FEATURE     # 1..N files; -D/-DNAME reaches test/run/bench/fuzz/check too (v6.6.5)
cyrius test tests/tcyr/crossos           # a directory: every .tcyr under it, recursive (6.7.6)
cyrius run src/main.cyr host 443         # compile + run; everything AFTER the source is the program's argv (v6.6.5)
cyrius run prog.cyx                      # run cx bytecode via cxvm — arguments are REFUSED (cx has no guest argv yet)
cyrius lint|fmt|doc a.cyr b.cyr          # 1..N files, every one processed (v6.6.5)
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
cyrius coverage --exec='programs/*_test.cyr' [--min <pct>]     # EXECUTION coverage (6.7.10): every .tcyr + these programs built instrumented and run; --min gates the executed %
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
>
> ⚠ **The CLI's self-builds ignore the compile-mode switches** (6.7.11). `pulsar` (every stage,
> the tool builds and the install step) and the cx arc's on-demand `build/cycc_cx` / `build/cxvm`
> builds run without `CYRIUS_POISON`, `CYRIUS_BOUNDS`, `CYRIUS_COVERAGE` and
> `CYRIUS_COVERAGE_FILE`, as the self-build scripts do: an exported `CYRIUS_POISON=1` used to make
> `pulsar` rebuild — and install — a poison-mode `build/cycc`. Since 6.7.12 the self-host
> verifiers do too: both steps of `cyrius self` and of each `cyrius soak` iteration build the
> default compiler, so an exported `CYRIUS_POISON=1` no longer turns their verdict into one about
> two poison-mode compilers. Your own compiles still see them (`cyrius build --target=cx x.cyr`
> hands them to `cycc_cx` for `x.cyr`, and `soak`'s test suite and `.scyr` harnesses compile
> with them). Pinned by `tests/gates/toolchain/cbt_self_builds_scrub_env.sh`.

> ⚠ **`fmt`: a continuation line is canonical at 2, accepted at 4** (the 2026-08-18 contract).
> Inside an open `(`, a wrapped line's indent is 2 spaces per open paren level beyond the
> statement's. `cyrius fmt <file>` (and `cyrfmt <file>`, `--write`) always writes the canonical
> 2, so it rewrites an accepted 4 as 2; `cyrius fmt --check` passes 2 or 4 and rejects anything
> deeper, naming the first differing line. Since 6.7.12 `cyrius audit`'s fmt stage asks
> `cyrfmt --check` (D26), so it agrees with it: it used to compare the file with cyrfmt's
> canonical output and so flagged the 4-step file `--check` passed. Pinned by
> `tests/gates/toolchain/fmt_continuation_contract.sh` axis 5.

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
> reference count, the same measure `.tcyr` corpora get — not execution coverage, which is
> `--exec` (below). `[coverage] programs` stays text in both modes.
> Pinned by `tests/gates/toolchain/coverage_run_programs.sh`.
>
> ⚠ **`coverage --exec` measures what RUNS** (6.7.10). `cyrius coverage --exec[=<glob>]`
> (repeatable), or `[coverage] exec = ["programs/*_test.cyr"]` in cyrius.cyml (which alone turns
> the mode on; `--exec=<glob>` replaces its list), builds every `tests/**/*.tcyr` — exactly as
> `cyrius test` builds and grades it — and every program the globs name (as `cyrius run` builds
> it) with the [execution-coverage mode](#the-execution-coverage-mode-6710) on (`CYRIUS_COVERAGE=1`,
> a dump file of its own), runs each one, and counts a public fn as executed once a run's dump
> records entering it. The report
> keeps every reference figure as text mode prints it and adds `E/T executed` per file and
> `Functions executed: E/T (p%)`; `--min` gates the executed percentage, and `-v` (or a failed
> `--min`) lists the unexecuted fns (`#naked` ones say they are not instrumented). The count is
> by NAME, as the reference count is: a record's path, the entry file's own fns (`<source>`) and
> a generic instance's `$` suffix never mark a different fn executed. A run that fails — a
> nonzero exit, a signal, a timeout, or an exit 0 that left no coverage record (an `asm` exit,
> a runtime-variable exit number, an exec) — is named (`FAIL: <path> (exit N)`); every entry
> still runs, the report is still printed, and the run exits 1. A dump path over 255 bytes (a
> very long `TMPDIR`) is refused by name before anything is built. Pinned by
> `tests/gates/toolchain/coverage_exec_cli.sh`.
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
the operands. `cyrius <verb> --help` (or `-h`) prints exactly the flags the parser accepts, on
every verb — since 6.7.12 the raw-tail verbs `init`, `port` and `sign-efi` too, whose helpers
(`cyrius-init`, `cyrsign-efi`) print their usage on stdout and exit 0 (`cyrsign-efi` takes the
help only as its lone argument and still refuses every other `-` token). `run` is the
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
umbrella includes and its test-only leaves (`assert`, `bench` — since 6.7.6 declared in `[test]
stdlib`, out of the production prepend too) do not reach it — from v6.5.10 to
6.6.17 the whole declaration was merged in, which published every producer's test leaves to every
consumer and hid real gaps behind a declaration. `[deps] stdlib` still drives auto-prepend and
`cyrius deps` for the package's OWN builds. A family directory (`lib/unicode/`) is one leaf, named
by the family; a profile's sidecar is verified the same way as the base bundle's.
The leaf a round adds for an undefined name follows one rule whether every target or only some
left it undefined (since 6.7.11; the every-target path took the first declarer by file name
before): a declarer already in the unit is skipped (it demonstrably does not define the name
there); a fold bundle counts only when nothing else declares the name; then the one dispatcher
whose peer declares it (`syscalls` for `O_RDWR`, never a per-arch peer); else the one other
declarer. Two or more candidates is a refusal that names them all — `'X' is undefined on every
target, and more than one stdlib leaf could own it (a, b)` — and no sidecar is written: `include`
the right leaf from a bundled module.
A leaf a NAMED DEP brings is that dep's, not the bundle's: one its sidecar lists, and (6.7.12) one
of those leaves brings by its own include — `tagged` lists `boxed` in for `tagged_new`, as
`cyrius deps` vendors it for the dep — so a bundle that calls nothing gets no sidecar (until 6.7.12
it published `boxed`). The bundle's OWN call into such a leaf is recorded, listed or not. So is
(6.7.13) a fold `cyrius deps` keeps in place of a named dep's thin profile (`note: [deps.sigil]
dist/sigil-mldsa.cyr not vendored — 'sigil' is a stdlib leaf here …`, a `modules` file or a
`modular` sub-module): the fold, and what it includes, stand in for that dep's module, so they are
its need — until 6.7.13 a named dep with no sidecar of its own got them written into the bundle's
(bote-core: `sigil ct`).

The bundle carries the same leaves, in the same order, as a compile-verified **requires block**
(`# Requires (compile-verified; the leaves of dist/<pkg>.deps):` and one `include
"lib/<leaf>.cyr"` per leaf), so `include "dist/<pkg>.cyr"` alone compiles. `--check` against an
older bundle says `the committed bundle predates cyrius 6.6.18's requires block — run cyrius
distlib --all`. A name the converged verify could attribute to no leaf, named dep or bundled module
is printed as a warning with the targets it fails on (a deliberate consumer hook shows up there).
A non-symbol failure on agnos alone is a warning too. A consumer whose build fails on a leaf it
never declared gets the remedy under the error — `hint: '<name>' is defined by stdlib leaf
'<leaf>' — add it to [deps] stdlib in cyrius.cyml`; see
[ecosystem-migration.md](../development/ecosystem-migration.md) § 6.6.18.

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
A `path` is relative to the manifest's directory; an absolute one is taken as given — `/…`, and on
Windows a drive-rooted `C:/…` / `C:\\…` or a rooted `\…` (6.7.13: cyrius.exe used to join a
drive-rooted path onto the manifest's directory and report the module missing).
Includes are auto-prepended by the build tool — source files only need project includes.

**Git first; local development is a switch (6.7.6).** The committed manifest means the TAGS. A
`[deps.X]` with `git` + `tag` resolves that tag — its commit pin checked — on every machine, a
developer's included, and `lib/` + `cyrius.lock` record that resolution. A `path` beside `git` /
`tag` is a **dev override**, read only in **local mode**:

```toml
[deps.sigil]
git  = "https://github.com/MacCracken/sigil"
tag  = "3.9.9"
path = "../sigil"          # dev override: read ONLY in local mode
modules = ["dist/sigil.cyr"]
```

```sh
export CYRIUS_LOCAL=1                   # every declared override (put it in your shell profile once)
CYRIUS_LOCAL=sigil,libro cyrius build   # only these names
cyrius build --local                    # the flag form (any resolving verb); --local=sigil,libro
cyrius build --no-local                 # the tags for this run, whatever CYRIUS_LOCAL says
```

Precedence: `--local[=…]` / `--no-local` > `CYRIUS_LOCAL` (`1`, `0`, or a comma list of names) >
off. The manifest can never switch it on, so no commit flips what CI builds.

- **No switch** — CI and a dev box alike — builds the tag. When a declared checkout exists but was
  not used, ONE line says so:
  `hint: 1 dep has a local checkout not in use (sigil); CYRIUS_LOCAL=1 builds it (this run built the tag)`.
  It is said only where the switch works — never under `--locked` or a release verb (`publish`,
  `package`, `distlib`, `update`), which resolve the tags whatever `CYRIUS_LOCAL` says.
- **Local mode**, per selected override whose `path` is a directory: the working tree is used, no
  clone, and one line names it:
  `local: sigil <- ../sigil @1a2b3c4, 118 commits past 3.9.9, dirty — CI builds 3.9.9`.
  The state is the checkout's own: git's discovery stops at the parent of the directory's
  physical path, so a `path` reached through a symlink into another repository's subdirectory
  says `(not a git checkout)`, as its physical spelling does (6.7.12).
  A selected `path` that is not a directory is named and the tag builds instead.
- **Local mode writes no tracked file.** The whole resolution goes to `build/local-deps/lib/` and
  `cyrius.lock` is not written, so `lib/` and the lock stay what the tag resolution wrote and
  switching modes churns nothing (keep `build/` in `.gitignore` — local mode warns when it is not).
  Every include string stays `lib/<file>`: the compiler reads `lib/` through the local resolve first
  (`CYRIUS_LIB_OVERLAY=build/local-deps/lib`, set by `cyrius` for its compiles — never set it by
  hand; an inherited value is removed), so a source's own `include "lib/sigil.cyr"` reads the
  override too. Local mode with no override actually in use resolves exactly as the default.
- **A path-only dep** (no `git`) has no tag to prefer: it resolves from its path in every mode, as
  before. `--locked` refuses it by name — a release cannot resolve a path.
- **A dependency's own manifest.** A dependency resolved from its tag has its own `path` entries
  IGNORED (its developers' override, never its published meaning), and a path-only, local-`git`
  (`git = "../x"`) or absolute entry is REFUSED by name: `error: mid's manifest names [deps.leaf]
  path = "../leaf" with no git / tag — a published dependency must name git + tag; refused`.
  Before 6.7.6 such an entry resolved on its author's box and failed in CI. A dependency that is
  itself a local checkout has its overrides followed for the SELECTED names (`CYRIUS_LOCAL=1`
  selects all; `local: leaf <- ../leaf (via mid) …`), so a sibling stack builds from working trees.
  A selected name no manifest declares a `path` for is warned (a typo must not read as "no override").
- `--locked`, `cyrius publish`, `package`, `distlib` and `update` resolve what a release ships: the
  switch is off there, `--local` is refused by name, and a set `CYRIUS_LOCAL` gets one `note:` line.
- Adoption rides the pin: a repo pinned below 6.7.6 keeps the old resolution (a present `path`
  wins) until it bumps `[package].cyrius`. The `# path =` lines kept commented out, the "never
  commit `path`" policies and the CI guards against a committed path are no longer needed.
- `cyrius build --print-config` shows the switch as `deps.local` and `deps.locked`.

**Where each dependency came from.** `cyrius deps -v` (and any resolving verb with `-v`) ends with
one line per dependency, and `cyrius deps --dry-run` prints the same without resolving — no clone,
no `lib/`, no lock; a transitive dep is listed as far as a local checkout or the cache shows it,
and the dry run fails where the real run fails:

```
dependency sources:
  sigil  tag 3.9.9 @1a2b3c4 (cache)
  libro  local ../libro @9f8e7d6, 3 commits past 2.1.0
  leaf   tag 1.0 @5e6f7a8 (fetched) via mid
```

A **diamond** — a dependency already resolved, wanted again at another tag — still resolves
closest-first, and now says so: `note: leaf 2.0 (wanted by p2) not used; 1.0 (p1) resolved first`.
Only an entry the run would resolve is "wanted": one gated out (`optional` with no active feature,
another `target`) is not named.
A key nothing reads in your own `[deps]` / `[deps.NAME]`, and a table nothing reads
(`[dev-dependencies]`, `[[bin]]`), is warned by name, as `[build]`'s unknown keys are.

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
to `[deps] stdlib` (both used to be left out), so commit it — and since 6.7.13 whenever the lock
has a row for a file that is no longer in `lib/`, so `rm lib/<file> && cyrius deps` drops that row
(a stdlib-only resolve kept it, and `deps --verify` and `--locked` stayed red). `cyrius deps --verify`
checks every locked hash **and** that every `.cyr` under `lib/` has a line: an unlocked file fails by
name (`not in cyrius.lock — run cyrius deps --relock`), a locked file that is gone fails as
`missing from lib/` (6.7.13; it read `cannot hash: the hasher could not read it`), and an empty lock
is reported as empty, not missing. On every resolve — including the implicit one `cyrius build`
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
re-hashes `lib/` **keeping** the commit pins (it used to drop them). A resolve never drops a
`commit` line it did not re-verify (6.6.20, fail-closed — a repointed old tag stays refused), so
after a `[deps.NAME] tag` moves the lock keeps the old tag's line beside the new one; since 6.7.12
every resolve, and `--locked` (which still passes), names it: `note: cyrius.lock keeps
darshana@1.2.1's pin (the manifest declares darshana at 1.3.0), fail-closed; delete cyrius.lock to
re-pin`. A line a manifest the resolve read still declares (a diamond's transitive `x@v1`) is live,
and not named.

**A pin bump in a project that vendors the whole snapshot (6.7.12).** The lock records ONE pin
for every row, so a resolve at a moved `[package].cyrius` does **not** re-lock while `lib/` holds
stdlib files it did not vendor (outside the declared closure — a `cyrius lib sync --full` project's)
that the new pin's snapshot ships with other bytes: re-locking stamped the new pin over the old
pin's rows, `deps --verify` and `--locked` agreed, and the next `lib sync --full` refused as if the
snapshot had moved under an unchanged pin. `cyrius deps` — and `cyrius build`, every resolving
verb — exits 1 naming each file, leaves `cyrius.lock` **and `lib/`** unchanged (6.7.13, D41: the
refusal comes before anything is written, so `deps --verify` stays green; until then the closure's
own files were already re-vendored at the new pin), and gives the two ways on:

```
error: cyrius.lock not re-locked: [package].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 1 file this resolve did not vendor that the 6.6.7 snapshot ships with other bytes:
  lib/chrono.cyr
  cyrius.lock records ONE pin for every row; re-locking would stamp 6.6.7 over these rows. Either:
    cyrius lib sync --full     moves them to 6.6.7 and re-locks (a project that vendors the whole snapshot)
    rm <file> && cyrius deps   drops them from lib/ and the lock
```

So after a pin bump a full-vendored project runs `cyrius lib sync --full` first. `cyrius deps
--locked` (CI) at such a bump names the same files and gives the same two ways instead of its usual
"run `cyrius deps` and commit the result" (6.7.13; it sent CI to the `deps` that refuses):
`… nothing was written — [package].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 1 file the
resolve does not vendor that the 6.6.7 snapshot ships with other bytes, so `cyrius deps` will not
re-lock:`, the files, `Either, then commit the result:` and the two lines above. A file the new
snapshot does not ship, or ships with the same bytes, does not depend on the pin and is re-locked
as before; a project whose `lib/` is only its closure re-locks silently, as it always did. To know
the closure before it writes, a resolve at a moved pin (when some `lib/` file differs from the new
snapshot at all) runs once first into a private scratch, silently — one extra resolve at such a
bump, its named dependencies from the clone cache; whatever that pass printed, the real resolve
prints once.

The two other lock writers are held to the same rule (6.7.13, D42). The bare `cyrius deps --lock`
(and `cyrius publish`'s lock step) resolves nothing, so at a moved pin it refuses while `lib/` holds
any file the new snapshot ships with other bytes — the closure's own files included — and its first
way is the resolve that re-vendors them:

```
error: cyrius.lock not re-locked: [package].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 2 files that the 6.6.7 snapshot ships with other bytes (a bare re-lock vendors nothing):
  lib/chrono.cyr
  lib/string.cyr
  cyrius.lock records ONE pin for every row; re-locking would stamp 6.6.7 over these rows. Either:
    cyrius deps                re-vendors the declared closure at 6.6.7 and re-locks
    cyrius lib sync --full     moves them to 6.6.7 and re-locks (a project that vendors the whole snapshot)
  cyrius.lock is unchanged (it records 6.6.6).
```

A scoped `cyrius lib sync` (the declared `[deps] stdlib` subset; `cyrius update` refreshes `lib/`
the same way) refuses **before it copies anything** while `lib/` holds files outside that subset
which the new snapshot ships with other bytes: `error: lib sync: nothing was copied: … lib/ holds 1
file outside the declared [deps].stdlib subset that the 6.6.7 snapshot ships with other bytes:`, the
files, and `cyrius lib sync --full` as the way on (`--dry-run` refuses too). `--full` vendors them;
`--no-lock` re-locks nothing, stamps no pin, and is not refused. Until 6.7.13 both writers stamped
the new pin over the old pin's rows, as `deps` did before D19.

A resolve never deletes a file, so since 6.7.12 it **names** each `lib/` file it did not vendor —
a leaf dropped from `[deps] stdlib`, the module of a dep dropped from the manifest — which `lib/`
and the lock still hold (`note: 1 file in lib/ is outside the declared footprint …`, the file,
then `` `rm <file> && cyrius deps --lock` drops one from lib/ and cyrius.lock ``). Nothing is
written or deleted for it; a `lib/` that holds the whole pinned snapshot (`cyrius lib sync
--full`) is not told, and neither is `-q`.

**`--locked`: the CI check (6.7.6).** `cyrius deps --locked` — and `cyrius build --locked`, every
resolving verb, or `CYRIUS_LOCKED=1` — resolves the TAGS into a private scratch, verifies every
commit pin against its clone, compares the would-be `lib/` and `cyrius.lock` with the committed
ones, **writes nothing**, and fails naming each difference:

```
  differs: lib/sigil.cyr: lib/ holds other bytes than the tags resolve (stale)
  differs: cyrius.lock has no commit pin for sigil tag 3.9.9 (the tag resolves to 1a2b3c4…)
error: --locked: 2 difference(s) between what the tags resolve and the committed lib/ + cyrius.lock (named above); nothing was written — run `cyrius deps` and commit the result
```

It also names a lock hash the tag disagrees with, a `lib/` file the lock does not cover, a lock
line for a file that exists nowhere, a file the tags resolve that `lib/` lacks, and a lock that
records another stdlib pin; with no `cyrius.lock` at all it refuses by name. A clean tree says
`--locked: lib/ and cyrius.lock are exactly what the tags resolve`.

**A CRLF checkout of `lib/` (6.7.12).** The lock records the exact bytes `cyrius deps` wrote (LF),
and git's `core.autocrlf` (Git for Windows' default) rewrites a committed `lib/` to CRLF on
checkout. Exact bytes stay the proof, so such a checkout still fails `deps --verify` and `--locked`
(rc 1) — normalising would let a CRLF-only rewrite of a locked file pass — but a file whose bytes,
read with every CRLF as LF, hash to the locked value is named for what it is:

```
  FAIL: lib/alpha.cyr (hash mismatch — CRLF checkout: add `lib/** -text` to .gitattributes)
0 verified, 2 failed
note: 2 files in lib/ differ only by CRLF line endings: git converted lib/ on checkout (core.autocrlf), and cyrius.lock holds the exact bytes. Commit `lib/** -text` in .gitattributes and check lib/ out again (before any `cyrius deps`, which would lock the converted bytes)
```

`--locked` names the same files (`… — CRLF checkout: add …`), and when every difference is one its
remedy is the `.gitattributes` line, not "run `cyrius deps`" (which would re-lock the CRLF bytes and
churn the lock between a Windows and a Linux checkout). `cyrius init` writes that `.gitattributes`
(`lib/** -text`), and `cyrius port` creates it or appends the line to an existing one. Through
6.7.11 every such file was a bare `hash mismatch`.

**A project that does not commit `lib/`** (it is in `.gitignore`, so a fresh CI checkout has none —
the lock is the committed artifact there): with no vendored `lib/` (absent, or holding no `.cyr`)
`--locked` checks the resolve against `cyrius.lock` alone and says so in one line —
`note: --locked: no vendored lib/ here — the resolve is checked against cyrius.lock alone` — naming
every lock hash, lock line and pin that differs, and ending
`--locked: cyrius.lock is exactly what the tags resolve (no vendored lib/ to compare)`. A compiling
verb (`cyrius build --locked`, `test --locked`, …) then compiles that proven resolution from
`build/locked-deps/lib/` (read through the compiler's `lib/` overlay, as local mode reads
`build/local-deps/lib/`); `lib/` and the lock are still not written. When `lib/` IS there, every
difference with it is named as above. It replaces the hand-rolled CI
guards (`git diff --exit-code -- cyrius.lock`, `lock-check.sh`, `verify-lock.sh`) and the
`cyrius deps && cyrius deps --verify` sequence, whose first step rewrote the lock the second then
checked. `--locked` does not combine with `--local`, `--relock`, `--verify` or `--lock`.
Locked means nothing is written in ANY verb: under `CYRIUS_LOCKED=1` a verb whose job is a write —
`cyrius update`, `deps --lock`, `deps --relock`, `lib sync` — is refused by name
(`error: cyrius update writes lib/ and cyrius.lock, and CYRIUS_LOCKED=1 means nothing is written —
refused …`); `deps --verify` and `lib sync --dry-run`, which write nothing, still run.

**`cyrius update` (6.7.6).** `update` first refreshes `lib/` exactly as `cyrius lib sync` does
(6.7.12, D18): the declared `[deps] stdlib` set, its per-OS peers and the test scope's leaves, from
the snapshot of the manifest's `[package].cyrius` pin (the CLI's own version when the manifest pins
none) — `cyrius update --full` takes the whole snapshot — with lib sync's lock guard and re-lock,
and it writes that version into an existing `.cyrius-toolchain`. (Until 6.7.12 it copied every
file of `$CYRIUS_HOME/current`'s snapshot, whatever the manifest declared or pinned.) Then `update`
re-fetches each UNTAGGED dependency — it floats by design, and the cache froze it at its first
fetch — re-resolves the manifest (`lib/` + `cyrius.lock`), and lists each root dependency's newer
version tags, newest first: `sigil: 3.9.9 pinned; newer tags: 3.10.0, 3.9.10 (cyrius.cyml is not
edited)`. It never edits `cyrius.cyml`: moving a tag is a decision made in the file.

**The git-dep CACHE is verified too (v6.6.5, the dep-cache tamper-check hardening item).** A git dep is cloned once into
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
for local development declare `path = "../sibling"` beside `git` / `tag` and switch local mode
on (`CYRIUS_LOCAL=1` or `--local`), which is the supported route (6.7.6, above).

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
are computed by the CLI itself (6.7.12) — SHA-256, byte for byte what `sha256sum` prints — so no
external hasher runs, a full temp dir cannot touch the lock, and the lock is written on every host,
wine included (through 6.7.11 they came from `sha256sum`, `shasum -a 256` or `certutil`).

**A CLI stopped mid-compile leaves nothing in its temp dir (6.7.12).** SIGTERM, SIGINT (Ctrl-C)
or SIGHUP while a compile runs stops the compiler the CLI started (a distlib verify passes the
signal to its per-target children, which clean up their own), unlinks the compile's scratch —
the preprocessed `cpp_<pid>`, the `cc_err` capture, the child's `<out>.tmp.<pid>` (beside the
output for `cyrius build`), a check's own output — removes the then-empty temp dir and then dies
by that same signal, as a CLI with no handler does: a shell's `$?` reads 128+N (143, 130, 129),
and a parent's wait sees a signal death (`exec_capture_status`: `st[1]` = 1), so a Ctrl-C'd
`cyrius` stops a shell loop (6.7.13; 6.7.12 exited 128+N, which a parent read as an exit). A
file in that dir that is not compile scratch, such as a `cyrius test` binary, stays, and so does
the dir. `cyrius capacity` (its `cap_err` capture and the compiler it
forks) and the git queries of a local-mode resolve or `cyrius update` (their `wt_err` / `wt_out` /
`ls_remote` captures and the git they run) are
stopped and cleaned the same way (6.7.13; before, a kill left the capture and that child running),
and a distlib verify's copy of the pinned stdlib in the project, `dist/.dlverify-<pid>/` (with the
round's `entry.cyr`), is removed too (6.7.13; before, a kill left the ~114-file mirror there).
A signal that arrives while the CLI is starting one of these children is held until the child is
tracked, then handled (6.7.13; before, a signal in that window left the child running).
A signal that was IGNORED when the CLI started (`nohup`, a background job of a non-interactive
shell) stays ignored. Through 6.7.11 a kill left all three
names until `scripts/check.sh`'s reaper removed the dead pid's dir. SIGKILL cannot be caught, so
its leftovers are still the reaper's; on Windows, which has no POSIX signals, nothing is caught.

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

The switch underneath is the environment variable `CYRIUS_POISON`, read by every compile (`cycc`
included, on every target) the way `CYRIUS_BOUNDS` and `CYRIUS_COVERAGE` are: `1` on; `0`, empty or
unset off; any other value refused by name (`CYRIUS_POISON must be 0 or 1 (or unset): <v>`), rc 1,
nothing written. On, the compiler predefines `CYRIUS_POISON` for `#ifdef`. `--poison` hands the
compiler `CYRIUS_POISON=1` ahead of whatever the shell exported, so it wins over an inherited `0`.
(Before 6.7.11 any set value — `0` and an empty one included — turned the mode on.)

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

A bare `cyrius lint` (no file) prints usage and exits 1 — it does not lint the stdlib. Flags
may appear **in any position**, an undeclared `-`-prefixed token is an error that names it, and
every file you pass is linted (⚠ before v6.6.5 it linted the FIRST one and reported that verdict
for the lot). See
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

**Bare-array overruns and write lengths (6.7.11).** A bare `var a[N]` in a function is N
**bytes**, rounded up to 8 ([Arrays: byte vs slot sizing](#arrays-byte-vs-slot-sizing-v621)),
and the compiler refuses `a[i]` on it, so the overrun left to make is the explicit offset.
`cyrlint` records each local of a fn body, scoped to its block, and warns on a
`load8/16/32/64(&a + K)` or `store8/16/32/64(&a + K, ..)` — K an integer literal, or no `+ K` at
all — whose K plus the access width runs past those bytes: `var a[16]; store64(&a + 16, 3);`
draws ``store64(&a + 16) reaches bytes 16..23 of local `var a[16]`, which is 16 bytes …``. Since
6.7.12 N is read as the compiler reads it for the shapes a line scanner can see: an integer
literal, a `const NAME = <literal>;`, an enum constant with a literal value (bare or `E.X`), and
`+ - *` over those (`*` first) — `var a[BUF]`, `var b[Sz.SMALL]`, `var c[4 + 4]` — and the
warning names the spelling and its value (``of local `var a[BUF]` (N = 8)``). A top-level bare
`var g[N]` is N i64 slots (N * 8 bytes) and is checked in every fn whose own local or parameter
does not shadow the name (``of top-level `var g[2]`, which is 16 bytes``); before 6.7.12 only a
literal N in a function was checked. A typed local (`var a: i64[4]`), a scalar or a size it
cannot read (`sizeof`, a `const fn` call, parentheses, a name from another file, a const or
enum constant defined twice with two values) shadows the name and is not checked. An intended
offset is marked with `# lint: offset-ok` on the line of the call's name.
And a write of a string literal with a literal length — `syscall(SYS_WRITE, fd, "…", N)` (or
`syscall(1, …)`), `sys_write(fd, "…", N)`, `_aw_write(fd, "…", N)` — warns when N is not the
literal's byte length (`write length 5, but its literal is 6 bytes …`): a raw byte counts once,
so an em dash `—` is 3, and an escape counts what the lexer stores (`\n` 1, `\xHH` 1, `\u…` its
UTF-8 length). `#skip-lint` exempts a line from both rules; `# lint: offset-ok` does not
silence a write.

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
them too (it also used to read only the first 64 KB of a file) — and, since 6.7.11, a
`const fn`, an `async fn` and a `#deprecated("…") fn`: cyrdoc and `cyrius type-audit` read a
declaration with the same reader as `cyrius header`, `coverage` and the LSP
(`cbt/srcscan.cyr`), so an undocumented public `const fn` now fails `cyrdoc --check`.
`cyrius header`, `cyrius api-surface` and the LSP balance a generic type's `<` `>` in a
parameter (`p: Pair<i64, i64>` is one parameter; after the parameter's `=` a `<` is the
operator), and `cyrius header` writes a variadic tail as C's `...` and a fully variadic
`fn f(...)` as `f(void)`. Since 6.7.12 `cyrius type-audit` counts a generic fn (`fn g<T>(a: T)`,
blanks around the `<..>` allowed as the compiler allows them; it required the `(` right after
the name, so a public generic fn was missing from its counts), and `cyrius api-surface` writes a
variadic fn as `name/MIN-` — `va/1-` for `fn va(n, ...)`, `zv/0-` for `fn zv(...)`: the `...`
tail is no parameter, and the open upper bound (6.7.7's `name/MIN-MAX` form for trailing
defaults) keeps it apart from a fixed fn of the same count (it read `va/2`, `zv/1`). Since 6.7.11 `cyrius header` also reads a fn's RETURN type (it printed
`cyr_val f(..)` for every fn): a scalar, a pointer, `Str` and a struct of 8 bytes or less stay
`cyr_val`; a struct of 9-16 bytes and a `dyn Tr` are `cyr_val2` (two int64 words, as cycc returns
them in rax:rdx / AAPCS64 x0:x1) under `#ifndef _WIN64` — Win64 C returns 16 bytes through a hidden
pointer, so there the fn gets a comment and no prototype; a two-value return `(T1, T2)` is
`cyr_val2` on x86_64 SysV only (`#if defined(__x86_64__) && !defined(_WIN64)`: cycc lands the
second value in x0:x2 on aarch64, where C reads x0:x1); a struct over 16 bytes is `cyr_valN` (N
words, the size rounded up: the callee writes whole words), returned by value through the hidden
result pointer cycc uses too (SysV rdi, AAPCS64 x8, Win64 rcx); and a return the tool cannot size
from the file itself — another file's struct, a generic instance, a struct holding one, a struct
declared twice or whose fields sit under `#ifdef`, three values (rax:rdx:r8) — is refused by name
on stderr with no prototype, and the verb exits 1. Since 6.7.12 so is a SIMD vector return (D24:
``'rv2' returns 'f64v2': a SIMD vector return, which no C11 return type carries``) — it printed
`cyr_val`, which C reads from rax / x0, and a C vector type is a compiler extension; make such a fn
private, or return its lanes another way, to generate a header for the rest of the file. Since
6.7.13 a SIMD vector PARAMETER is refused the same way (``'pv' takes 'v: f64v2': a SIMD vector
parameter, which no C11 type carries``): cycc receives it in a vector register (xmm / v), where the
printed `cyr_val v` had a C caller pass it in rdi / x0. A pointer to a vector (`v: *f64v2`) and a
`: Result` / `: Option` / `: Tagged` parameter (one word, the tag) stay `cyr_val`.
Since 6.7.12 a `: stack` enum's return is the pair it is (D23): `: Result`, `: Option`, `: Tagged`
(and a file's own `enum E: stack`) are `cyr_val2` with the tag in `w0` and the payload in `w1`, on
x86_64 SysV only — cycc returns the pair in rax:rdx there and on Win64 (where C passes a hidden
result pointer), and in x0:x2 on aarch64 (C reads x0:x1) — so `lib/process.cyr`'s `run`,
`run_capture`, `spawn` and `wait_pid` are `cyr_val2`. A fn whose signature says a word (no
annotation, or `: i64`) but whose body returns the pair — `return Ok(x);` (any payload
constructor of the stdlib's Result / Option / Either or of the file's own stack enum; a nullary
`None()` returns its tag alone), or `return f(..);` of a fn of the same file that returns it,
followed to a fixpoint — is refused by name (``'mk' returns a `: stack` enum's (tag, payload)
pair through 'Ok(..)', which its signature does not declare …``), rc 1: a source scanner cannot see
that pair from the signature. Since 6.7.13 the same holds for a `?` on such a call
(`var v = parse(x)?;` — its Err path returns the callee's pair, so the compiler makes the fn
pair-returning): refused as ``… pair through 'parse(..)?' …``, followed to the same fixpoint.
Declare such a fn `: Result`, `: Option` or `: Tagged`, or make it
private. A closure's own `return` or `?` is not the fn's (a block or an expression body); a pair
reached through another file's fn or a method is not seen.
Sizes are cycc's `sizeof`, field by field: a bare `Vec` field is the file's own `struct Vec` when
one is declared above it, else the 8-byte handle (as `Vec<T>` always is); one whose `struct Vec` is
declared below it is refused by name, as cycc refuses it (6.7.13).
Whitespace at the end of a
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

⛔ **And an invocation opened in a `#` comment used to delete your code.** A `#define` body
stops at the newline, but that covers only what an expansion *writes*. What it *reads* ran to the
matching `)` wherever that was, so with `#define M(a) 0` in scope the comment

```
# TODO: fix M(
var r = 42;
var t = 1;
syscall(60, r + t);
```

expanded `M(` against the `)` of the `syscall` and swallowed everything between them — the program
body was gone, and it exited 0 with nothing on stderr. Since v6.6.6 an invocation that *starts*
inside a comment must also *close* on that line; if it does not, it is not an invocation and the
bytes stay comment. A single-line `# see M(1)` is still expanded, and still changes nothing. An
ATTRIBUTE line (`#inline fn f(): i64 { return N(5); }`) is not a comment, to the preprocessor
any more than to the lexer (v6.6.20), so a macro call there expands like anywhere else in code —
including one whose arguments wrap onto the next line, which from v6.6.6 to v6.6.19 failed with
`undefined function` because the preprocessor read the line as a comment.

⚠ **A `#` is not always a comment.** `#naked`, `#inline`, `#pure`, `#io`, `#alloc`,
`#must_use`, `#regalloc`, `#deprecated`, `#assert` and `#pe_import` are attribute TOKENS, and
the lexer keeps reading the line after them — so `#naked fn isr() {` opens a real brace.
`cyrlint`, `cyrfmt` and `cyrdoc` read them as the lexer does (v6.6.5; before that
`#naked fn f() {` drew false `unmatched closing brace` warnings and `cyrius fmt` rewrote the fn
body flush left), and since v6.6.20 so does the preprocessor, from the lexer's own list. Before
that it read the rest of an attribute line as a comment, so a string literal there that ran onto
the next line (`#assert ok, "first` / `second"`) put it one quote out of step for the whole of
that next line: a real `#ifdef` there was skipped, a `#define` inside the string was executed,
and a forged `#@file` marker got past the guard that keeps `private` honest.

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

`CYRIUS_DCE=1` removes the unreachable fns from an x86 kernel image (ELF32 multiboot1 and
`CYRIUS_ELF64_KERNEL=1`) as it does from a host executable (6.7.11; 6.6.20 through 6.7.10 only
NOP-filled them); a `--pie` kernel still declines (its data is reached through rip-relative
displacements) and NOP-fills. The image's `.bss` and `.rodata` follow the code, so they move down
with it, and every data address in the code moves with them; the move is a multiple of 16, so an
array keeps its 16-byte alignment. A dead fn the compiler keeps because it cannot size one of its
instructions (an `out dx, al` in an `asm` block) keeps its body, and its calls into removed fns
become `ud2`. `CYRIUS_WX=0` executables, whose data also follows the code, compact the same way.

## Enums

```
enum Color { RED; GREEN; BLUE; }     # RED=0, GREEN=1, BLUE=2
enum Error { OK = 0; NOT_FOUND = 44; PERM = 13; }  # Explicit values

var c = BLUE;                        # c = 2
var c2 = Color.BLUE;                 # Namespaced access (v1.11.0+)

```

**An enum constant is a value, not a variable** (6.7.3). `RED = 4;`, `RED += 1;`, `&RED`,
`Color.RED = 4;` and `&Color.RED` are refused by name, as on a `const` — and so is a `for` step
that writes one. Every read of `RED` is its declared value, so before 6.7.3 such a write changed
nothing a read could see, and `&RED` handed out a dead copy. `&Ctor` of a payload variant is
refused the same way (it was never the constructor's address). A local `var RED`, a closure's
capture of one, or a later top-level `var RED` is its own variable and stays assignable.

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

#### Bind the pair as a pair — the refusals

A value-form Result is two values. Any context that keeps only one would silently discard the
payload, which for an `Err` is the error code, so each is a compile error naming the fix:
*"a `: stack` enum returns two values — bind both: `var tag, val = f();`"*.

```
var r = f();             # ✗ single-variable bind      (v6.5.67)
r = f();                 # ✗ assignment                (v6.6.0)
store64(&slot, f());     # ✗ storing into a slot       (v6.6.0)
h.n = f();               # ✗ a field, any field type   (6.7.7)
a[i] = f();              # ✗ an element                (6.7.7)
*p = f();                # ✗ through a pointer         (6.7.7)
x += f();                # ✗ any compound `OP=`        (6.7.7)
var p = P { f(), 3 };    # ✗ a struct-literal element  (6.7.11) — named, a global's, a nested leaf too

var t, v = f();          # ✓ bind both halves
t, v = f();              # ✓ re-assign both halves     (6.7.7)
var v = f()?;            # ✓ `?` consumes the pair and yields one value
h.n = f()?;              # ✓ ... at any store: a field, an element, `*p`, `x += f()?`, `P { f()?, 3 }`
return f();              # ✓ forwarding the pair onward
is_ok(f());              # ✓ a single ARGUMENT receives the tag (above) — and so does an operand
```

A store is judged by the call it starts with, so `h.n = f() + 1;` and `P { f() + 1, 3 }` are refused
too; an argument (`g(f())`) and an operand anywhere else (`f() == 0`, `return f() + 1;`) read the tag,
by the single-argument rule above (the user's decision, 2026-10-13).

The requirement follows the value through `return`, so forwarding it out of a wrapper and
binding it one-wide there is caught too.

`f` is any call spelling: an explicit generic `g<T>(..)` and a method `p.m(..)` are refused,
destructured and propagated with `?` exactly like `f(..)` (v6.6.16 — before that, `?` on them
crashed and a single bind dropped the payload silently). The method's `impl` may sit above or below
the call (6.7.11 — with the `impl` below its caller, `p.m(..)?` crashed and `var v = p.m(..);`
kept the tag in silence), and so may the `trait` whose DEFAULT body the impl inherits (6.7.13 — an
inherited default below its caller crashed the same way).

**Parentheses around a whole pair call are transparent** (6.7.13, the user's decision of 2026-10-15),
as around a whole struct source: `var v = (f());`, `x = ((f()));`, `h.n = (f());`, `P { (f()), 3 }`
and every other store above are refused as their unwrapped spelling is, `(f())?` propagates like
`f()?`, `return (f());` forwards the pair as `return f();` does, and `g((f()))` receives the tag as
`g(f())` does. Before, the wrap hid the call from every check: `(f())?` crashed (it took the boxed
`?` lowering) and each wrapped store kept the tag in silence. `x = (3) + (f());` is an operand, as
`x = 3 + f();` is.

The single-variable bind is refused for a **global** too (6.7.6): `var r = f();` at top level —
before the first top-level statement or after it — kept the tag and dropped the payload, silently
(`Ok(42)` read as 0). Bind both with `var t, v = f();`, which works at top level.

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
Their bodies were rewritten from `load64(box)` to a direct register compare. On a value-form tag that is correct; on
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

The example below is the value-form spelling; `tests/gates/toolchain/guide_examples_compile.sh`
compiles the fenced blocks in this file and fails on a stale-API error, so it cannot rot back.

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
(`?: '?' propagation operator only valid inside a fn body`). Inside a
fn that otherwise returns one value (`fn f(x): i64 { var v = g(x)?; … }`),
`?` makes its `Err` path return a `: stack` pair, so the compiler WARNS
with the every-path rule (*"returns a `: stack` pair on another path but
a SINGLE value here"*, see *Bind the pair as a pair*) — a warning, not an
error: declare the fn `: Result` and return a variant on every path.

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
| `lib/bayan.cyr` (json) | `JsonError` | `JsonIoErr` `JsonParseErr` `JsonOther` |
| `lib/bayan.cyr` (toml) | `TomlError` | `TomlIoErr` `TomlParseErr` `TomlOther` |
| `lib/bayan.cyr` (cyml) | `CymlError` | `CymlIoErr` `CymlOther` |
| `lib/http.cyr` | `HttpError` | `HttpBadUrl` `HttpNetErr` `HttpNon2xx` `HttpOther` |
| `lib/dynlib.cyr` | `DynlibError` | `DynlibNotFound` `DynlibBadElf` `DynlibSymMissing` `DynlibOther` |
| `lib/pwd.cyr` | `PwdError` | `PwdNotFound` `PwdLoadFailed` `PwdBufTooSmall` `PwdOther` |
| `lib/grp.cyr` | `GrpError` | `GrpNotFound` `GrpLoadFailed` `GrpBufTooSmall` `GrpOther` |
| `lib/shadow.cyr` | `ShadowError` | `ShadowNotFound` `ShadowLoadFailed` `ShadowBufTooSmall` `ShadowOther` |
| `lib/pam.cyr` | `PamError` | `PamAuthFail` `PamHelperMissing` `PamPipeFailed` `PamForkFailed` `PamExecFailed` `PamOther` |

Result-returning fns use the `_r` suffix:

```
var t, fd = file_open_r("/etc/hostname", 0, 0);   # bind both: the tag, then the fd or the error
if (is_err_result(t) == 1) {
    if (fd == IoNotFound) { ... }
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

Note: a case value is any integer const expression — a literal, a `const`, an enum constant, `sizeof`, a `const fn` call, arithmetic (6.7.2; before it, an integer literal only). No fallthrough — each case is independent.

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
> `break` leaving the switch / match (C semantics) is settled language, confirmed by the
> maintainer at v6.5.20 (CHANGELOG [6.5.20]).

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
The callee is spilled to a frame slot; at top level (since 6.6.16) the compiler gives the
call its own micro-frame, so `callptr` works there too.

A call through a pointer passes exactly the arguments written: parameter defaults and named
arguments belong to direct calls (6.7.7, see *Default and named arguments*). So
`callptr(&f, 1)` or `fncall1(&f, 1)` with fewer arguments than `f`'s parameters is refused by
name when `f` declares defaults, and so is a `name:` argument. A struct result comes back only
when the callee is written `&f` (6.7.11): a callee held in a variable returns one word (see
*Returning a struct by value*).

A parameter that holds a fn pointer can say so (6.7.11): `fn ap(cb: *fn(i64): i64, x: i64)`, or a
bare `cb: *fn`. It is one word; `fncall1(cb, x)` / `callptr(cb, x)` call through it, and the
signature is not checked against the fn a caller passes (see *Type names*).

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
more than four arguments on Windows and more than six elsewhere. Since 6.6.16 a
top-level call is lowered the same way, in its own micro-frame.

The library body runs only when `fncallN` itself is called through a pointer —
`fncall2(&fncall1, &add1, 41)`, or `&fncall3` handed to code that calls it. On the
cx bytecode target each `fncallN` is `callptr(fp, …)` (there is no asm on cx). ⚠
**Before 6.7.6 `lib/fnptr.cyr` had no cx arm**, so an address-taken `&fncallN`
returned 0 there for every callee (`fncall2(&fncall1, &add1, 41)` gave 0, 42
everywhere else). Pinned by `tests/tcyr/codegen/cx_backend_parity.tcyr`.
⚠ **Before 6.7.6 the x86_64 SysV `fncall8` body (Linux, macOS, agnos) passed arguments 7
and 8 in C's order**, while a cyrius callee reads its LAST argument at `[rsp]`: an
address-taken `&fncall8` handed a cyrius callee 7 and 8 swapped (`12345687` for `1..8`;
a direct `fncall8(..)` was right, the compiler marshals it). It now passes them in
cyrius's order, as a direct call does; an 8-argument C function on x86_64 therefore needs a
shim, as one with 7+ arguments on aarch64 always has (`docs/ffi/fncall-abi.md`). Pinned by
`tests/tcyr/crossos/fncall_stack_args.tcyr`.

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
doesn't clobber it). That holds for every name the body declares: a `var`, a local
`const`, a `for … in` variable (for the loop only) and each name of a destructure
`var a, b = f();`. A range's start bound and a collection are read before the loop
variable is bound, so `for i in i..5` and `for x in x` read (and capture) the enclosing
`i` / `x`; a range's end bound reads the loop variable. A destructure binds its names after
its right-hand side, so `var a, b = f(b);` passes (and captures) the enclosing `b`.
⚠ Before 6.7.11 a `for … in` variable, a local `const` and a destructure's second or
third name were taken for a read of the enclosing local of that name: the closure was
refused without lib/alloc.cyr, or carried a heap copy it never read. Pinned by
`tests/gates/frontend/closure_declared_names_not_captured.sh`.

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
contained a nested closure lost its own captures after it (refused the same way). Pinned by
`tests/tcyr/crossos/closure_nested_capture.tcyr`.

## Constants and `const fn` (6.7.2)

```
const LIMIT = 7;                  # an integer
const PI = 3.14159;               # an f64
const NAME = "cyrius";            # a string
const BUF = LIMIT * 64;           # from other consts (in any order)

const fn fib(n) {                 # runs at compile time in a const context
    var a = 0;
    var b = 1;
    for (var i = 0; i < n; i = i + 1) { var t = a + b; a = b; b = t; }
    return a;
}
const F20 = fib(20);              # 6765, computed by the compiler
var table[fib(10)];               # an array size is a const context
enum Op { ADD = 1; MUL = fib(7); }
#assert fib(10) == 55, "fib";

fn f(v): i64 {
    const SCALE = 3;              # a local const: visible to the rest of its block
    switch (v) { case fib(5): return 1; default: return 0; }
    return v * SCALE + fib(3);    # fib(3) here is an ordinary RUNTIME call
}
```

- **A `const` has no storage.** Every use is its value — an integer folds like an enum
  constant, an f64 is its float literal, a string is its literal (passed where a `Str` is
  expected it is wrapped like the literal). `N = ..`, `N += ..` and `&N` are refused by name
  (a `for` step included, 6.7.3).
  It takes no type annotation: its type is its value's (`const H = 1.5;` is an f64).
- **Top level and inside fns.** Top-level consts are found by one pre-scan, so they may be used
  above their declaration and in any order (a const defined in terms of itself is refused);
  `pub` / `private` apply as to any declaration, and one top-level name is a const or a global,
  never both. A local const is visible to the rest of its block like a `var`; a var and a const
  of one name in one scope are refused, and a closure reads a local const by name.
- **Const contexts** take any integer const expression — literals, consts, enum constants,
  `sizeof`, `const fn` calls, arithmetic: a const's value, an array size (top level and in a fn,
  bare or element-typed), `#assert` (any expression since 6.7.2, `&&` / `||` included), a
  `case` label, an enum value. Anything else — a variable, an ordinary fn's call — is refused
  by name. A `const fn` call there is a call like any other (6.7.11): another file's `private`
  const fn is refused at the call (`'pk' is private to its file`), and a `#deprecated` one warns
  once per call site — before 6.7.11 every const context ran both silently. ⚠ An enum value and a top-level array size are read in pass 1, in source order: a
  `const fn` they call must be declared above them (a top-level const need not be).
- **A `const fn` runs at compile time only in a const context**; everywhere else it is an
  ordinary runtime call, so the disassembly shows the call you wrote (user decision,
  2026-10-07). Its body is the pure subset, **checked at the definition, called or not**:
  integer and f64 arithmetic, comparisons, `&&` / `||`, shifts with the runtime's semantics
  (`>>` logical, `>>>` arithmetic), locals (`var x = ..;`, typed `i64` / `i32` / `i16` / `i8` /
  `f64`, a narrow one narrowing as at run time), local consts, assignment and `OP=`, if / elif
  / else, while, `loop` and `do … while` (6.7.5), `for (..; ..; ..)`, `for i in a..b`, return,
  break, continue, calls of const fns (recursion included), the exact f64 builtins
  (`f64_add`..`f64_div`, `f64_from`,
  `f64_to`, `f64_eq` / `lt` / `gt` / `le` / `ge`, `f64_neg`, `f64_abs`, `f64_floor`,
  `f64_ceil`, `f64_trunc`). Not: memory (`load64`, arrays, `&x`, fields), syscalls, globals, an
  ordinary fn's call, a transcendental builtin, a generic const fn.
- **The same answer as run time.** Typing is the runtime's: an operator takes its f64 form when
  its LEFT operand is f64, and an integer right operand contributes its bits. f64 is computed
  by an integer-only IEEE-754 implementation (the bootstrap compiler has no float), bit-exact
  with x86-64 and AArch64 — round to nearest even, subnormals, infinities, signed zeros. A NaN
  is refused (its bits differ between targets), as are division by zero, an f64 out of the
  i64 range in `f64_to`, more than 10,000,000 steps, and calls nested deeper than 2,000.

## Booleans: `bool`, `true`, `false`, `!` (6.7.3)

```
var ready: bool = false;          # true is 1, false is 0
var big: bool = n > 100;          # a comparison is a bool
var ok: bool = !failed && big;    # so are !, && and ||
fn even(n): bool { return n % 2 == 0; }
fn set(on: bool) { .. }

var count = 10 + ready;           # a bool READS as the integer 0 or 1
```

`bool` is an 8-byte word (ADR-002 keeps `i64` the core: `sizeof(bool) == 8`) holding 0 or 1.
`true` and `false` are reserved words.

**A write into a bool is checked** (the user's decision, 2026-10-07). A bool variable (local or
global), field, parameter, fn return, multi-value-return element or const takes only a
**boolean value**: `true` / `false`, a comparison (`==` `!=` `<` `>` `<=` `>=`, and the
`f64_eq` / `f64_lt` / `f64_gt` / `f64_le` / `f64_ge` builtins), `!x`, `&&` / `||`, another bool
(a bool variable, field, parameter, capture or const, a call to a `: bool` fn), or any of these
in parentheses. Everything else is refused by name — the literals `0` and `1` included:

```
var b: bool = 1;      # error: cannot initialize bool 'b' with a value that is not a bool
b = n;                # error: cannot assign a value that is not a bool to bool 'b'
b += 1;               # error: compound assignment to bool 'b' is refused - its result is not a bool (write `b = b && c`, `b = !b`)
p.on = 2;             # error: cannot store a value that is not a bool into bool field 'on'
set(1);               # error: cannot pass a value that is not a bool to bool parameter 'on' of 'set'
fn g(): bool { return 1; }   # error: cannot return a value that is not a bool from bool fn 'g'
```

Write `x != 0` to make a bool of an integer. Arithmetic over a bool is an integer, not a bool:
`ok + 0`, `-ok`, `~ok` and `(a < b) + 1` are refused into a bool. An untyped variable stays an
integer whatever initialised it (`var x = a < b;` then `var c: bool = x;` is refused) — inference
would change what existing programs do. Raw memory is not checked: `store64(p, 7)` and `*p = 7`
through a `*bool`, and `ret2`, write what they are given; a `*p` read is an integer.

**A bool reads as the integer 0 or 1 everywhere** — `n + ok`, `ok * 4`, a bool passed to an
`i64` parameter — and a condition (`if`, `while`, `&&`) still takes any integer.

**`!e`** is 1 when `e`'s word is 0, else 0. It binds like unary minus — its operand is a factor,
so `!x + 1` is `(!x) + 1` — and an `f64` operand is tested by its raw bits, as `if (x)` tests it
(`!(-0.0)` is 0). ⚠ Until 6.7.3 the lexer silently DROPPED a lone `!`, so `!x` compiled as `x`
(the dropped-bang lexer bug).

**`fn g(): bool`**: a bare `return;` in it is refused (it returns 0); running off the end
returns `false`; a tail call `return h(..);` must call a bool fn. **Consts**: a const is a bool
when its value is (`const DEBUG = true;`, `const ON = !OFF;`, a `: bool` const fn's result), and
every const context takes it as 0 / 1 (`#assert`, case labels, enum values, array sizes). A
`bool[N]` initializer list takes boolean elements — `true`, `false`, bool consts and, since 6.7.4
(a list element is a const context), comparisons and `!`. **`#derive`**: Serialize writes
JSON `true` / `false`; both decoders store 1 for `true` and 0 for any other value;
`#derive(accessors)` gives a typed getter `: bool` and a setter `v: bool`.

The checks are skipped under `cyrius lint`'s `--syntax-only` (a sibling file's names are unknown
there) and are not switched off by `CYRIUS_TYPE_CHECK=0`. The refusals are pinned by
`tests/gates/frontend/bool_checked.sh`; the runtime half by `tests/tcyr/crossos/bool_values.tcyr`.

## The if-expression (6.7.4)

```
var v = if (n > 0) { 1 } elif (n < 0) { 0 - 1 } else { 0 };
var s = f(if (debug) { 2 } else { 1 }, x);
return if (ok) { a } else { b };
const MODE = if (DEBUG) { 3 } else { 1 };      # const contexts too
var lim: i64[if (BIG) { 4096 } else { 64 }];
```

An `if` that appears where an EXPRESSION is parsed is an if-expression: each branch holds **one
expression** in braces — no statements, no `;` — and **`else` is required** (without it there is no
value). Only the taken branch runs. At the **start of a statement** `if` is still the if statement,
and a closure's `{ block }` body is statements as before.

**Every branch is the same kind** — an integer (pointers and bools included), an `f64`, an `f32`, or
one struct type of 8 bytes or less, whose type the result keeps (so `var z: S = if ..`, struct
arguments and operator overloads see it). Mixing kinds is refused by name (`if expression branches
differ in type: an integer here, an f64 before it`), and so is a struct value over 8 bytes, a vector,
a `u128` (a `u128` name, and since 6.7.6 a `u128` `+` / `-` result such as `{ b - 1 }`, which compiled
and lost its high word) or a `: stack` pair — branch on a pointer (`&x`) instead. A whole dereference
of a `*S` — `{ *p }`, `{ (*p) }`, `{ *gp() }`, `{ *(&t) }` — is a struct value of S like `{ t }` (6.7.13,
6.7.10 decision 6): of 8 bytes or less it joins `{ *q }`, `{ s }` or a call returning S, the
destination copying it, and over 8 bytes it is refused as `{ t }` is — branch on the pointer, `if (c)
{ p } else { q }` (the user's decision D1 (a), 2026-10-15). Through 6.7.12 it was an integer: `var v: S
= if (c) { *p } else { *q };` bound a handle to the word `*p` read (a crash at every size) and `{ *p }
else { s }` was refused as two kinds. A `u128` comparison
(`{ b == c }`) is an integer, as everywhere. The result is a `bool` when every
branch is boolean (6.7.3): `var b: bool = if (c) { x > 0 } else { false };`. ⚠ An untyped variable
holding a float is an integer (ADR-002), so `if (c) { u } else { 2.5 }` with `var u = 1.5;` is a
mix — declare it `: f64`. And an untyped `var t = if (c) { 1.5 } else { 2.5 };` stays untyped (as
`var t = 1.5;` does); write `var t: f64 = ..`.

It is a **factor**: `if (c) {a} else {b} + 1` is `(if ..) + 1`, and `-if ..` negates it. A call
inside a branch is never a tail call, so deep recursion written as `return if (n == 0) {acc} else
{loop(..)};` grows the stack where `if (n == 0) { return acc; } return loop(..);` does not. An
explicit `#inline` fn whose body holds one keeps the "control flow" warning.

**In const contexts** (a const's value, a local const, an array size, `#assert`, a `case` label, an
enum value, a `const fn` body, and — since 6.7.4 — every element of a global array initializer list)
the compile-time evaluator runs the taken branch and only walks the others, so `if (N > 0) { 100 / N }
else { 0 }` never divides by zero. There a string is its own kind: `const B = if (DEBUG) {"dbg"} else
{"rel"};` is a string const, and a string mixed with an integer is refused. At run time a string
literal is a pointer word, so `if (c) {"a"} else {0}` compiles. Every array-list element now goes
through that evaluator: comparisons, `&&` / `||`, `!`, const fn calls and f64 const arithmetic are
legal elements (a `bool[N]` list takes `{1 < 2, !false}`), and a non-constant one is refused in the
const context's words. A kernel build bakes a constant-condition if-expression global.

The refusals are pinned by `tests/gates/frontend/if_expr_checked.sh`; the runtime half by
`tests/tcyr/crossos/if_expr_values.tcyr`.

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
parameter, a struct global, a call returning a struct (a generic call at the instance
it reaches, 6.7.11: `g(id(p))`, `g(mk1(p))` bind `Pt` and `Box<Pt>`) — binds `T` to that struct
on every call path (an expression, `var r = g(p)`, `r = g(p);`, `b.v = g(p);`,
`return g(p);`, an argument, a struct receive), exactly as the explicit
`g<Pt>(p)` does (6.6.10; before that only an inlined body inferred a struct, and
every other path ran the i64 base). Only a WHOLE argument binds `T`: `g(p.y)`,
`g(p.x + p.y)` and `g(p + 1)` infer `i64`, and so does a `pp: *Pt` pointer
parameter (a pointer, like a `var q: *Pt` local). An **f64** argument — an `f64`
local or parameter, an `f64` global, a float literal, a call returning `f64` (a
generic one at its `f64` instance) — binds `T = f64` and calls the `f64` instance,
exactly as `g<f64>(h)` does, and a `: T` return there is an `f64`: `gid(h) * 2.0`
is a float multiply and `var v = gid(h);` declares an `f64` (6.7.9; before it the
call ran the i64 base — `dbl(h)` with `x + x` added the double's bits — and its
result was an untyped word, so `gid(h) * 2.0` multiplied the bits as integers with
a warning; so did `gg<f64>(&q) * 2.0`, a `T` named only in the return). The same
WHOLE-argument rule holds — `g(h * 2.0)` infers `i64` — and an `f32` is not a type
argument, so `g(f)` with `f: f32` infers `i64`. A **generic method** binds its
type parameters from its arguments exactly as its free spelling does: a struct
argument (`p.pick(q)` calls `P_pick$Q`, as `P_pick(p, q)` does), an `f64` one
(`p.id(h)` calls the `f64` instance, 6.7.9), a struct carrier (`p.cm(b)` with
`b: Box<Pt>`), and a type parameter on `self` binds the receiver's struct
(`fn me<V>(self: V)`: `p.me()` calls `P_me$P`) — on every call path, a chain
`mk().pick(q)` and `var w = p.pick(q);` included (6.7.11; before it every binding
but `f64` called the i64 base — the dead stub when the body uses the parameter as a
struct, so `p.pick(q)` returned 0, and a carrier was refused as a different struct
type). A bound is then met at `f64`: `gb(h)` with
`fn gb<T: Show>` calls `impl Show for f64`'s method, and is refused without one, as
`gb<f64>(h)` is — and it needs no `impl Show for i64` (6.7.11: without one, `gb(h)`,
`gb<f64>(h)` and `p.bm(h)` were refused naming `i64`, or ran the dead stub). Any other
argument infers `i64`, or the width a scalar-returning call declares.

**Through a generic struct parameter** (6.7.8). A `T` that no `x: T` parameter
carries is inferred through a parameter whose generic struct names it as a whole
type argument — `fn gx<T>(b: Box<T>)`, `fn g2<T>(p: Pair<i64, T>)`: the argument's
instance binds `T` to its type argument in `T`'s slot, so `gx(b)` with
`b: Box<Pt>` calls `gx$Pt` and `b: Box<i32>` calls `gx$i32`, as `gx<Pt>(b)` /
`gx<i32>(b)` do (before 6.7.8 the call reached the `Box` base and was refused). The
WHOLE argument must be the instance: a local or by-value parameter, a struct
global, or a call returning it — or a pointer to one, which binds what it POINTS AT:
`&b`, a `bp: *Box<Pt>` name or a call returning one, a field declared
`bp: *Box<Pt>` reached through a chain (`h.bp`, `hp.bp`, `self.bp`, `G.h.bp`). That
holds through a `*Box<T>` parameter, which also takes a `Box<Pt>` value (the call
passes its address), and through a by-value `b: Box<T>` — address-passed when the
instance is over 8 B, so `gx(&b)` / `gx(bp)` hand `gx$Pt` the same address, as
`gx<Pt>(&b)` does. Before
6.7.8 (6.7.9 for the by-value parameter) these pointer calls compiled, ran the `i64`
base and read `b.n` at `Box<i64>`'s offset — `b.v.y`, silently. Parentheses around the
WHOLE argument and a whole dereference of such a pointer bind `T` as the plain spelling
does (6.7.11): `gx((b))`, a wrapped call returning the instance, `gx(*bp)` and `gx((*bp))` call `gx$Pt`, and
`gw((w))` / `gw(*wp)` with `w: W1<i32>` call `gw$i32` — they reached the base, refused
as a different struct type (through 6.7.10 a carrier of 8 bytes or less compiled there and
read `W1<i32>` with `W1<i64>`'s layout). A tuple literal (`gx((b, 3))`) binds nothing. A plain `p: *T` keeps
the rule above. A **generic** call's own result binds `T` as the instance that call
reaches (6.7.11): `gx(mk1(p))` with `fn mk1<T>(x: T): Box<T>` calls `gx$Pt`, as
`gx<Pt>(mk1(p))` does — inferred or explicit (`gx(mk1<Pt>(p))`), nested
(`gx(mk1(mk1(p)))`), and through a `: T` generic (`gx(id(b))`); before 6.7.11 the call
was typed by `mk1`'s base return, the generic `Box`, and refused as a different struct
type. An `x: T` parameter wins over a struct one; `T` nested deeper (`Box<Pair<T>>`)
is not inferred — write `gx<Pt>(..)`.

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
dispatch — `T` is resolved entirely at compile time. An instance is named by its
type argument — `i8` / `i16` / `i32` / `f64` for a scalar, the struct's own name
for a struct — and a struct named exactly like a scalar (`struct f64`, which
`add<f64>` then binds) is marked `.f64`, so a scalar type argument never shares an
instance with a struct one (6.7.11: `add<f64>` was `add$i`, the instance of a `struct i`
too, and the second call ran the first's body). ⚠ Still open: a two-parameter generic
whose type argument is itself a generic struct's instance — `g2<P<R>, i32>` and
`g2<P, R<i32>>` both mint `g2$P$R$i32`, so the second call runs the first's body
(`docs/development/issues/2026-10-14-two-param-generic-nested-instance-names-collide.md`).

**A generic that uses `T` as a struct has no i64 instance.** When a `T`-typed
value — a parameter or a `var q: T` local, or a struct carrier's `T` field (`b.v.y`
with `b: Box<T>` / `b: *Box<T>` or a `var x: Box<T>` local, where `Box` declares
`v: T`; 6.7.11, before it such a definition failed to parse, called or not) — is
used as a struct (`p.y`), there is
no valid i64 form, so the base is a dead stub, and any use that would reach it is
a compile error naming the fn: a scalar call (`g(5)`, `g<i64>(5)`, `g<i32>(5)`,
in any position, tail included), `&g`, and a generic that FORWARDS its own `T` to
such a generic (`fn outer<T>(p: T) { return g(p); }` makes `outer(5)` an error
too, whichever order the two are defined in). Call it with a struct argument or a
struct type argument (6.6.10; before that each of these compiled and returned 0).
The carrier rule looks one field deep: a field typed `Box<T>` inside another carrier
(`o.inner.v.y` with `o: Out<T>`) is not followed — bind the value to a `T`-typed
local first (`var t: T = o.inner.v; return t.y;`), which makes the base the stub.
A generic method's scalar call is refused the same way, naming the method's fn:
`p.pick(9)` and `p.pick(h)` (an `f64`) are refused as `P_pick(p, 9)` is (6.7.11;
before it they compiled and returned 0), and a generic that forwards a `T`-typed
name into such a method — `fn o<T>(p: P, t: T) { return p.pick(t); }`, or a
generic method's `self.pick(w)` — is a stub too: `o(p, 5)` is refused, `o(p, q)`
calls `o$Q`. The receiver may be a name, a field chain (`h.p.pick(t)`, `x.hp.p.pick(t)`
through a `*H` field) or a call's result (`mk().pick(t)`, `mkh().p.pick(t)`, a method
call's `h.gp().pick(t)`, a generic's plain `: P` return).

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

**A field may name a generic struct instance (6.7.1)** — `struct H { a: i64; b: Box<i32>; c: i64; }`,
`p: Box<Pt>`, `q: Pair<i32, Pt>`, `nb: Box<Box<i32>>`, in a struct or a union — laid out at the
instance's size (packed: `Box<i32>` is 4 + 8 = 12 B, so `H` is 28). Inside a generic struct, `w: Box<T>`
follows the instance (`W<Pt>`'s field is a `Box<Pt>`) and is the base `Box` in the base `W`. A field
naming the struct being defined — `b: W<i32>` in `W<T>`, or `b: Box<A>` in `A` — is refused: the struct
would contain itself (hold it by pointer, `b: *A`). Before 6.7.1 such a field was `expected identifier,
got '<'`. `#derive` reads nested type arguments too (`xs: Vec<Box<i64>>`, `ps: Vec<Pair<i64, i64>>`;
before 6.7.1 they stopped its field walk, and every field after one had no derived code). ⚠ A
`#derive`d struct cannot hold a generic instance INLINE: the derive computes its layout before
types exist and refuses it at its layout check, as it refuses any inline struct that is not itself
derived.

**Type arguments nest (6.6.17)** wherever a type is written — `var x: Vec<Box<i64>>`,
`var b: Box<Vec<i64>>`, `var z: Box<Box<i32>>`, a parameter, a global, a `Vec<Box<i64>>`
field, `idv<Vec<i64>>(x)`, and a multi-value return element `(Box<i64>, i64)` — with the
lexer's `>>` closing two lists. `sizeof(T<..>)` is the size of the instance the same
annotation declares — what `var b: Box<i32>` occupies (4 for the `Box` above, 16 for
`Pair<i64>`); `sizeof(Vec<i64>)` is a handle's 8. Before 6.6.17 `Vec<Box<i64>>` ran to the end of the file
(`expected '=', got end of file`), `Box<Vec<i64>>` and a `Vec<Box<..>>` field were refused,
and `sizeof(Box<i64>)` and `(Box<i64>, i64)` were `expected ')', got '<'`.

**Status & limits.** Generic functions and structs are supported over
i64, `f64` (inferred from a whole f64 argument since 6.7.9), narrow scalars
(`i32`/`i16`/`i8`), and struct type arguments, inferred or explicit, with any body (a small straight-line body is inlined at its call sites;
anything else is an ordinary call). At most two type parameters are recorded. A
struct type argument works in either slot of a two-parameter generic — explicit
(`g<Pt, i64>`, `g<i64, Pt>`) or inferred (`g(p, 2)`, `g(5, p)`, `g(p, q)` with two
structs) — on every call path, struct receives and assignments included (6.7.1;
from 6.6.10 to 6.7.0 it was a compile error, and before 6.6.10 the inferred form
ran the i64 base). Enum generic params (`<T, E>`) remain syntactically accepted
but type-erased.

### Trait bounds (6.7.1)

A type parameter may be **bounded** by one or more traits ([Traits and impl blocks](#traits-and-impl-blocks-670)):

```
trait Show { fn show(self): i64; fn twice(self): i64 { return self.show() * 2; } }
trait Eq   { fn eq(self, o: Pt): i64; }
impl Show for Pt  { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 1000; } }

fn describe<T: Show>(v: T): i64 { return v.show(); }
fn same<T: Show + Eq>(a: T, b: T): i64 { if (a.eq(b) == 1) { return a.show(); } return 0; }
struct Shown<T: Show> { v: T; n; }

describe(p);        # Pt's show
describe(5);        # the i64 base: impl Show for i64
describe<i32>(7);   # needs impl Show for i32
```

- **A bound is a contract.** On a bounded `T`-typed parameter or local (`v: T`, `p: *T`,
  `var q: T`), `v.m()` must be a method of one of the bound's traits — a method no bound declares,
  or one two bounds both declare, is a compile error at the generic's **definition**, whether or not
  it is ever called. The call is that trait's method for `T`'s impl: when `T` has two traits giving it
  an `m` (`Pt_Size_size`, `Pt_Other_size`), `<T: Size>` calls `Size`'s. Fields are not part of a
  trait — `v.x` on a bounded `T` resolves per instance, as on an unbounded one. An **unbounded** `T`
  keeps per-instance resolution: `fn f<T>(v: T) { return v.show(); }` compiles and works for any `T`
  that has a `show`.
- **`T: A + B`** requires every impl. A bound names a declared trait (an undeclared one is refused),
  takes no type arguments, and goes on one of the first two type parameters (at most two are
  recorded); up to 8 per parameter.
- **Every instantiation is checked**, and is refused when its type has no impl — naming the trait
  and the `impl` it needs: an inferred or explicit type argument, the **i64 base** an i64 call
  reaches (`describe(5)` needs `impl Show for i64`; without one, `describe`'s base is not emitted and
  every path to it — a call, a tail call, `&describe`, a generic method's `p.bm(7)` (6.7.11: it
  returned 0) — is refused), and a generic struct's instance,
  its i64 base included (a bare `Shown`, a written `Shown<i64>`). An instance is judged at its own type
  alone: `describe(h)` with `h: f64` needs `impl Show for f64` and nothing for `i64`, and a refused
  instance's one note names the type the call binds (6.7.11).
- **Any type satisfies a bound through its impl**, a scalar too: `impl Show for i64` defines
  `i64_show`, a bounded call on an i64 `T` calls it with the value, and a trait default instantiated
  for a scalar calls `self.show()` (6.7.1; before it, `self.m()` in a scalar impl was "no struct type
  in scope for 'self'").
- **A generic that instantiates a bounded struct with its own `T`** (`fn mk<T>(x: T): Shown<T>`, or
  `struct W<T> { s: Shown<T>; }`) is fine for every `T` that satisfies the struct's bound; its i64
  base is refused where it is used (`mk(5)`, a bare `W`) when i64 does not — not at its definition.

Before 6.7.1 `<T: Show>` minted a SECOND type parameter named `Show`, so `describe(p)` with a struct
was refused as "a struct beside a second type argument", and no bound was checked. Dispatch is
static throughout: a bounded call is a direct call to the impl's method, as `p.show()` is.

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
return a pointer to the vector. A **tuple** parameter (6.7.7: pass its elements as separate
parameters) and a tuple return (`return t;` from an `async fn`) are refused by name, and so is
any `dyn` type in an `async fn` (6.7.8). A **multi-value return** is refused for the same
reason (6.7.11): `async fn g(): (i64, i64)` at its declaration, and `return (a, b);`,
`return (a, b, c);` or `ret2(a, b)` in an `async fn` declared with no return type —
"`` `async fn g` returns 2 values, and a Future carries one i64 - return a pointer to a struct
holding them ``". Before 6.7.11 it compiled, `await g()` gave the first value, and the second
was gone: `rethi()` after the `await` read it only on the force that ran the body, and a
memoised (`await f` again) or reactor-driven force read whatever the last call left there.
`return h(..);` that forwards a multi-value call — `h` declared `: (T1, T2[, T3])`, an
undeclared fn whose every `return` is `(a, b)`, a method or a generic instance, parentheses
around the call transparent — is the same loss and is refused the same way, at the call (6.7.13,
the user's decision of 2026-10-15); `return callptr(fp, ..);` (its callee unknown) is not judged.

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
float literal in a float field — in an `f32` field its binary32 bits since 6.7.10; through 6.7.9
the image held its binary64 bits, which a `kernel;` build, whose replay runs after the program,
read as 0.0); a field that is a call, a name, a string or a `Str` leaves
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
(`too many initialized globals (max 4096)`). Since 6.6.9 there is no cap; the table grows. Enum members (`enum E { A = 0; B = 1; }`) are
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
  `#ifdef` arm, end up declaring one global. A later integer literal that **differs**
  from the earlier constant warns, whatever that constant was — `var a = 0;` then
  `var a = 5;` included (6.7.12, the user's decision of 2026-10-15: through 6.7.11 an
  earlier constant zero read as "no value" and the pair compiled silently, so two
  files' `var _shared = 0;` / `= 5;` became one cell unseen). An earlier *computed*
  initializer has no value to compare, and stays silent.
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

`println(x)` routes by its argument: a `Str` to `println_str`, a NUMBER to `println_int`. A number
is a call declared to return `: i64`, or (6.7.6) a NAME declared an integer — a local, parameter,
closure capture or global annotated `i8`..`i64` / `u8`..`u64` — as the whole argument
(`var n: i64 = 42; println(n);` prints 42; until 6.7.6 it ran the cstring body over 42 and crashed).
An untyped name is passed as a cstring (it may hold one); write `println_int(x)` or annotate it.
Any base with a `: cstring` parameter 0, an `: i64` return and a `<base>_int` sibling routes the same way.
A sibling takes the call only when it is DEFINED: one that is merely named somewhere — undefined under
`--allow-undef`, or defined in another object of an `object;` build — never does, and the call reaches
the base it names (6.7.11; it reached the undefined sibling, which trapped under `--allow-undef`).

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
include "lib/fnptr.cyr"   # Function pointers: fncall0 .. fncall8
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
since v6.6.7, `LockFileEx` / `UnlockFileEx` for `xflock` since 6.7.12, …) behind the same names.
`xflock` on Windows locks ONE sentinel byte at offset 2^63 − 1, never the file's data: Windows
byte locks are mandatory, so it excludes other lockers and leaves every handle's reads and writes
alone, as flock does; a refused `LOCK_NB` is -11 (-EAGAIN on PE; Darwin's is -35), where it used
to answer -1 for every lock. `cyrlint` flags a raw `sys_open`
with literal flags for exactly this reason and points at the wrappers.

The set was **completed at v6.5.7** (`xmkdir`, `xmkdir_p`, `xsymlink`, `xreadlink`, `xlink`,
plus `sys_chdir` and `signal_default`, which had no counterpart to `signal_ignore` even
though `SIG_IGN` is inherited across `execve`). ⚠ That release is also the cautionary tale
for this whole family: `xrmdir` had been **broken on macOS-arm64 since the day it shipped**,
because the Mach-O branch mapped `unlinkat` to Darwin's `unlink` with an arg-shift that
dropped the dirfd and the flag — right for `unlink`, fatal for `rmdir`, which is the same
syscall distinguished only by `AT_REMOVEDIR`. Five of the seven defects found there were
half-fixes that stopped at the first symptom. If you add a wrapper, add a test for it under
`tests/tcyr/crossos/`, or it is never run off-host — the release gate's cross-OS leg selects
that DIRECTORY (the old `vr01_` filename prefix was retired at v6.5.11; a file named that way
anywhere else is not run on the other hosts).

**The recorded exception — the agnos-only wrappers** (6.7.12; the user's decision, 2026-10-15). Three
wrappers exist only in the agnos peer (`lib/syscalls_x86_64_agnos.cyr`, 6.7.11): `sys_console_mode`
(#110), `sys_fd_kind` (#111) and `sys_sock_send_dl` (#109). No cross-OS host runs agnos, so a
`tests/tcyr/crossos/` file could only compile them under `CYRIUS_TARGET_AGNOS` and skip on all four
hosts, a pass that covers nothing. They have no crossos file. Their companion is
`tests/gates/platform/agnos_peer_fake_kernel.sh` axes 10–12, which run each wrapper against the fake
kernel (`tests/fixtures/agnos_sctrace.cyr`) and check the syscall it hands the kernel and the answer it
returns. #109's real-kernel leg (`sys_sock_send_dl`'s deadline on a live agnos kernel) **cannot run: no
agnos host**. That leg is named as not run; it is not counted as coverage.

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
namespaced file `lib/{depname}_{basename}.cyr` (see *Build Tool & Dependencies* above;
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

- A classic `for` step is ONE assignment — any assignment a statement takes, `=` or a compound
  operator (6.7.5) — ending at its `)` (6.7.8): not a call, not `i++`, not a comma list. Its
  destination resolves as the statement's does: `for (i = 0; i < 5; j = i + 1)` with `j` declared
  nowhere (or a fn's name) is `undefined variable 'j'`, and a closure's captured name is the
  capture refusal (`'j' is captured by value; ...`, 6.7.11) — before 6.7.9 it compiled and stored
  nothing, so the loop never advanced
- Exit codes truncated to 0-255 (Linux limitation)
- At most 1,048,576 globals, enum members and top-level arrays per compilation unit
  (the var table). The separate 4096 cap on deferred initializers is gone since 6.6.9
  — see **Global Initializers**
- Every builtin/intrinsic name plus the statement keywords is reserved and cannot be used
  as an identifier — `TOKNAME_BUILTIN` in `src/common/util.cyr` is the list (count it from
  there); see the reserved-word note under **Functions**. So, since 6.6.20, are the 11
  identifier-spelled intrinsics `sizeof`, `mulh64` and `fncall0`..`fncall8`, which that table
  does not hold.
- Closures (`|x| body`) support lexical capture by value (v6.3.8) — a body may
  reference enclosing locals, captured by value at construction, on every target (Windows PE
  since v6.4.26). A capturing closure is capped at five parameters (three on Windows) and its
  value is an opaque handle rather than an address. Capture by value is of an enclosing fn's
  locals: a closure written at top level captures nothing and reads top-level variables live
  (it sees a later assignment). See the **Closures** section.

## Gotchas

- **Dynamic loop bounds**: `for (i = 0; i < GLOBAL; ...)` re-evaluates each iteration
- **Operator overloading**: a struct operand over 8 bytes is passed by address (and copied on
  entry when the parameter is by value); one of 8 bytes or less is passed by value
- **Enum constructors**: a BOXED payload variant (an `enum` without `: stack`) calls `alloc()` —
  init the heap first. The stdlib's `Ok` / `Err` / `Some` / `None` are `: stack` since v6.6.0 and
  allocate nothing

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
the `--win` cross-compilation flag. `cyrius build --win` sets `CYRIUS_TARGET_WIN=1` in the
compiler's environment, routing platform-specific code paths
through Windows syscall reroutes (kernel32 and shell32 imports) instead of POSIX
syscalls.

### Cross-Building for Windows

```sh
# Cross-compile a Windows PE32+ executable from Linux/macOS
cyrius build --win src/main.cyr build/myapp.exe

# Or via the environment variable (useful in build scripts)
CYRIUS_TARGET_WIN=1 cycc < src/main.cyr > build/myapp.exe
```

The output is a valid PE32+ executable that runs on Windows x86_64; `--win` implies the
x86_64 instruction set. The aarch64 Linux CLI **refuses** `--win` by name, rc 1, before anything
compiles — its cycc emits aarch64 only (6.7.13; through 6.7.12 it wrote an aarch64 ELF named
`.exe` and said OK at rc 0):

```
error: --win is not available from the aarch64 Linux CLI: its cycc emits aarch64 only (build PE images on x86_64 Linux or Windows)
```

ONE target selector per run: `--win`, `--agnos` (the agnos ring-3
userspace target), `--aarch64` (ARM64 cross-compile) and `--target=<v>` (`js`, `cx`, a bare-metal
triple) each select a different emit target, and since 6.7.12 two of them are refused by name
before anything resolves or compiles — `error: --win and --aarch64 select two emit targets; pass
one`, rc 1, no output — on every verb that takes the target block (`build`, `run`, `test`, …). The
one consistent pair, `--aarch64 --target=aarch64-bare-metal-elf`, is accepted and builds exactly
what the `--target` alone does (decision D20). Through 6.7.11 a combination silently kept one:
`--win --aarch64` built the aarch64 ELF, `--win --agnos` a PE matching neither, and
`--aarch64 --target=js` an aarch64 ELF named `.js` (its compiler read stdin, so on a terminal it
waited for ever).

### Conditional Compilation

Use the `#ifdef CYRIUS_TARGET_WIN` preprocessor guard to write cross-platform
code. The compiler defines exactly one of `CYRIUS_TARGET_LINUX`, `CYRIUS_TARGET_WIN`,
`CYRIUS_TARGET_MACOS`, `CYRIUS_TARGET_AGNOS` or `CYRIUS_TARGET_CX` per build (a UEFI
image, `CYRIUS_TARGET_EFI=1`, is a PE build: it gets `CYRIUS_TARGET_WIN` plus
`CYRIUS_TARGET_EFI`). ⚠ Before v6.6.6 the cx driver predefined none of them, so every
per-target `#ifdef` arm in the stdlib matched nothing on cx (`include "lib/assert.cyr"` did
not compile for cx at all).

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
- `args_init()` — parse GetCommandLineW via the real CommandLineToArgvW; the blob's
  length, or -5 / -12 when the command line cannot be read (6.7.12)
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

> ⛔ **A POSIX fork path is NOT dead on Windows.** `fork`/`execve`/`waitpid`
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

> ⚠ Before 6.6.5 the PE landing had no `sub rsp, 8`, so the whole PE base ran one parity off:
> every statement-level call entered its callee at RSP ≡ 0, and `f(0, open(path))` crashed
> inside kernelbase's own `movaps` in CreateFileW. See CHANGELOG [6.6.5].

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

**Paths: UTF-8, widened at the kernel32 boundary (6.6.11)**

A path is UTF-8 in the cyrius API and is widened to UTF-16LE where it meets kernel32 —
`MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS)`, surrogate pairs included. Invalid UTF-8,
or a path with no room, is REFUSED (the call returns -1) — never guessed or cut — and a path
whose full form is 248 units or more is passed as `\\?\<full>` (`\\?\UNC\…` for a share). That
holds for open / create / mkdir / unlink / rename / rmdir since 6.6.11, for the directory
calls (`is_dir`, `dir_list`, `is_symlink`, `sys_access`, `xmkdir_p`) since 6.6.12, and for
the link path of `xsymlink` since 6.7.12 (it was widened in the stdlib, capped at 519 units and
never prefixed, so a link path over 260 units failed -1). A link's TARGET is stored verbatim, so a
relative one is widened as written — never made absolute, `/` becoming `\` — and resolves against
the link's directory; an ABSOLUTE target (`X:\…`, `\\server\…`) whose full form is 248 units or
more takes the same `\\?\` prefix (6.7.12 — it failed -1 past MAX_PATH). ⚠ Before 6.6.11 a
path was copied one byte per UTF-16 unit and cut at 260 units: a non-ASCII name failed, and a long
relative `O_CREAT` open returned a handle for the name cut short.

**Sockets**

`lib/net.cyr` reaches Winsock (ws2_32) since 6.6.11: `tcp_socket` / `udp_socket`, bind,
connect, listen, accept, send / recv, shutdown, the socket options and the non-blocking forms
work as on Linux — the SOCKET is the fd, and a failure is `-WSAGetLastError`, with
WSAEWOULDBLOCK (and, for send / recv, WSAETIMEDOUT) reported as -EAGAIN. `sock_set_nodelay`
sets TCP_NODELAY there too (6.7.9). The raw `sys_*` socket wrappers keep the PE peer's -38
decline: go through `lib/net.cyr`'s verbs.

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

`args_init()` returns the bytes it read on Linux and Windows (0 on macOS and agnos, which read
the entry stack), and a **negative errno** when the command line cannot be read: the open's or
the read's on Linux, -12 when a buffer cannot be allocated, -5 / -12 on Windows. Test `< 0`,
never `== 0` — 0 is macOS's success (6.7.12, D7). Linux reads `/proc/self/cmdline` to its end:
ARG_MAX follows `ulimit -s` (up to 6 MiB), and a command line past 2 MiB is read whole (it was
cut at 2,097,152 bytes with no error before 6.7.12).

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

On Linux and macOS the listers open the path with `O_DIRECTORY` (6.7.11), so a path that is not
a directory fails at the open: `dir_list_checked` returns -20 (`-ENOTDIR`) for a regular file or a
FIFO and -2 for a dangling link, `dir_list_into` returns -1, and `dir_list` an empty vec. Before
6.7.11 they opened with `O_RDONLY` alone, and a FIFO at the path blocked the call in `open(2)`
until a writer came — for good, in a server. A regular file read -20 on Linux and -22 on macOS.

## Targeting AGNOS (ring-3 userspace) (v6.0.48)

AGNOS is a ring-3 operating system kernel designed for secure, minimal userspace
execution. Cyrius cross-compiles to AGNOS from an x86_64 Linux host,
producing x86_64 ELF64 binaries that run as agnos ring-3 processes. Unlike hosted targets
(Linux, macOS, Windows), agnos uses a distinct syscall ABI, explicit-length path arguments
(no NUL-termination), and agnos-native open flags; the `#ifdef CYRIUS_TARGET_AGNOS`
preprocessor guard exposes port-specific code paths in `lib/`.

### Building for AGNOS

```sh
# Cross-compile to agnos (from an x86_64 Linux host)
cyrius build --agnos src/main.cyr build/myapp

# Equivalent: set the environment variable directly
CYRIUS_TARGET_AGNOS=1 cycc < ...
```

The Windows and macOS CLIs **refuse** `--agnos` and both bare-metal targets
(`--target=x86_64-bare-metal-elf`, `--target=aarch64-bare-metal-elf`) by name, rc 1, before
anything compiles: their compilers emit PE or Mach-O only. The aarch64 Linux CLI refuses
`--agnos` and `--target=x86_64-bare-metal-elf` the same way (6.7.12): its compiler emits aarch64
and reads `CYRIUS_KERNEL` alone — through 6.7.11 it wrote a plain aarch64 binary (or an aarch64
image under an x86_64 kernel line) at rc 0 — while `--target=aarch64-bare-metal-elf` stays allowed
there. Build agnos and x86_64 kernel images on an x86_64 Linux host. On the aarch64 Linux CLI
`--target=aarch64-bare-metal-elf` and `--aarch64` run the host's own cycc, which emits aarch64 and
honours `CYRIUS_KERNEL` (6.7.13): `--aarch64` is a no-op there, and the bare-metal target writes the
aarch64 kernel image. Through 6.7.12 both looked for `cycc_aarch64` — the x86_64-hosted cross
compiler, which no aarch64 host can run — and failed with `compiler not found`.

```
error: --agnos is not available from the Windows CLI: cycc.exe emits PE only (build agnos / bare-metal images on Linux)
error: --agnos is not available from the macOS CLI: cycc emits Mach-O only (build agnos / bare-metal images on Linux)
error: --agnos is not available from the aarch64 Linux CLI: its cycc emits aarch64 only (build agnos / x86_64 bare-metal images on x86_64 Linux)
```

⚠ Before 6.7.11 they accepted the flag, built the host format, printed `OK` and exited 0
(a bare-metal build also printed a `kernel: entry …` line for an ELF that was never written).

The `--agnos` flag sets the `CYRIUS_TARGET_AGNOS` predefine, which gates the
compiler's emit codegen: the program-exit epilogue emits `syscall(0)` (agnos `exit`,
code in `rdi`), not Linux `syscall(60)`. The binary is a valid x86_64 ELF64 at entry
`≥ 0x200000` (agnos user-range floor).

### AGNOS Syscall ABI

agnos defines an append-only syscall surface: **#0–#104 and #106–#111**
(`lib/syscalls_x86_64_agnos.cyr`; #105 was withdrawn and is never re-added). Beyond the
GPU-compute band #82–#91 it carries `gpu_shader_op` (#92), `gpu_modeset_op` (#93),
`gpu_recover_op` (#94), `uptime_us` (#95), **`fork` (#96, minted at v6.5.37 / agnos 1.56.55 —
its arm is in the ring-3 entry stub)**, the local-IPC **channel band** `chan_op` (#97, v6.5.8),
and on up to `sched_yield_to` (#108, agnos 1.57.9), then `sock_send_dl` (#109), `console_mode` (#110) and
`fd_kind` (#111) (agnos 1.57.13; peers since v6.7.11); the next free number is #112. ⚠ A number
is minted only once its kernel arm exists — on agnos an unknown number falls *through* the
dispatch chain and the caller reads the fall-through value as data, so a
minted-but-unimplemented constant is strictly worse than an absent one. The register
convention is x86_64 SysV (rax=number, rdi/rsi/rdx/r10=args 1–4, rax returns
result ≥0 on success, -1 on error). Key differences from Linux:

```
# agnos syscall numbers — append-only, #0–#104 + #106–#111 (lib/syscalls_x86_64_agnos.cyr)
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

**`lib/syscalls_x86_64_agnos.cyr`**: the full agnos syscall surface (#0–#104 + #106–#111),
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
   later silently steals it. Since 6.7.12 a **raw literal** in such a region that a compat row
   renumbers is warned at compile time — `raw syscall 9 inside a native-aarch64 region is
   renumbered → 222 (mmap); write 1009 for native lgetxattr`, or `no 1000+N alias exists for
   native …` when the private band (below) has no row for it. The number is still translated
   (the user's decision, 2026-10-15: warn only — no program changes behaviour). The warning
   judges a number written as one integer literal, inside a region opened in the call's own
   file: a `SYS_*` or `enum` constant is not judged (the stdlib's renumber by design), and
   neither is a file `include`d from inside a region (the stdlib's shared syscall files sit in
   `lib/syscalls.cyr`'s aarch64 region and deliberately write x86 numbers). ⚠ This applies to a **variable** syscall number too — the chain
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
   ⭐ 6.7.12: `sys_sigprocmask(how, set, oldset)` is real on both Macs (it returned -78, so code
   that relied on that now gets 0). It changes the calling thread's mask, as on Linux: it is
   Darwin's `__pthread_sigmask` (329) through the private alias 1329 — not Darwin's
   sigprocmask (48), which is process-wide — a shim rather than a renumber: Darwin's set is 32
   bits, so it reads the low half of the 8-byte set and the shim writes 0 over `oldset`'s upper
   word. `how` is the peer's own `SIG_BLOCK` / `SIG_UNBLOCK` / `SIG_SETMASK` (1 / 2 / 3 on
   Darwin). The exec family (`run`, `exec_vec`, …) now empties a mask inherited from a launcher
   on macOS too.
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
- Syscall wrappers (all of #0–#104 and #106–#111; #105 was withdrawn)
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
  `sock_set_recv_timeout`; a server bound to 127.0.0.1 listens on loopback only (CYRIUS-2026-0008 —
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
- Socket options: `sys_setsockopt` is a -38 decline stub (6.6.16), and `sock_set_nodelay`
  declines -38 (6.7.9: agnos has no TCP options); deadlines go through
  `sock_set_recv_timeout` / `sock_set_send_timeout`
- `sys_ppoll`, `sys_ioctl` and `sys_fstatat` link but decline -38 (6.7.9 — no agnos number is
  minted for them), so portable source that names them compiles without an `#ifdef`
- The `cyrius` CLI: built for agnos (6.6.17) it answers `version` and `help` only — its verbs
  run cycc as a child process through fork / execve / waitpid. Compile with `cycc` directly

The agnos syscall surface is **append-only, currently #0–#104 + #106–#111 (#109–#111 since agnos 1.57.13; #105 withdrawn)**. The
re-freeze rule (§5) names the agnos **kernel dispatch** — `agnos/kernel/core/syscall.cyr` —
as canonical: any number / signature / struct-layout change there must land in this guide and
`lib/syscalls_x86_64_agnos.cyr` in the same change. `agnos/docs/development/agnos-userland-abi.md`
is a *secondary* reference and where it disagrees with the kernel, the doc is the bug. Follow-up arcs are tracked in
`docs/development/issues/`; the spawn-argv gap's original filing
("2026-06-03-agnos-followup-after-boot.md") has since moved to `issues/archived/`.

## Position-Independent Executables (PIE) (v6.1.6)

A position-independent executable (PIE) uses RIP-relative code and relocatable
base addresses, allowing the kernel to load it at a random address under ASLR
(Address Space Layout Randomization). Cyrius supports PIE on both x86_64 (v6.1.6)
and aarch64 (v6.1.8), producing ET_DYN binaries with `p_vaddr=0` and
base-relative entry points. The full tcyr test corpus runs correctly as
ASLR-loaded PIE binaries on both architectures.

Enable PIE via the `--pie` flag or `CYRIUS_PIE=1` environment variable (`--pie` sets
`CYRIUS_PIE=1` in the compiler's environment; ⚠ before v6.6.5 the CLI refused the flag as
`unknown flag '--pie'` and only the environment variable worked):

```sh
cyrius build --pie src/main.cyr build/myapp       # x86_64 or aarch64
# or
CYRIUS_PIE=1 cyrius build src/main.cyr build/myapp
```

PIE is a Linux ELF mode. The Windows CLI refuses `--pie` by name — `error: --pie is not available
from the Windows CLI: cycc.exe emits PE only, which has no --pie mode …`, rc 1, nothing written —
since 6.7.12; before, cycc.exe ignored it and wrote the same image as a plain build. On macOS
(6.7.13, decision D43) the arm64 CLI accepts `--pie` as already met: every arm64 Mach-O cycc writes
is position-independent (`MH_PIE` set, mach_header flags `0x00200084`), so the image is the plain
build's. The x86_64 macOS CLI refuses it by name, rc 1, nothing written — `error: --pie is not
available from the macOS x86_64 CLI: its cycc writes a fixed-address Mach-O (no MH_PIE mode)`.
Through 6.7.12 both Macs passed `CYRIUS_PIE=1` to a compiler that reads none and said OK at rc 0.

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
var global_ptr = 0;        # filled with &fn_target at run time

fn fn_target() { return 1; }

fn main() {
    global_ptr = &fn_target;
    var x = global_int;    # a global read: RIP-relative under an ASLR load
    var r = callptr(global_ptr);   # an indirect call at the randomized base
    return x + r - 1;      # 42 — correct under any ASLR offset
}
syscall(60, main());
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

> On every other host `cyrius build --target=js` **refuses by name** (v6.6.6), naming the
> fork that host's compiler is built from, and writes no output file. ⛔ Before v6.6.6 the
> CLI ran the host's cycc with `--emit-js`, which that compiler ignored: it compiled its empty
> stdin into a runnable binary, the CLI renamed that over the `.js` and printed `OK`. Pinned
> by `tests/gates/toolchain/emit_js_refused_off_x86_linux.sh`. See CHANGELOG [6.6.6].

### Limitations

- Single-file emission; no module bundling or tree-shaking
- No JSX component props typing validation (TS type-checking is lost)
- The TS parser is self-hosted (only in the `cycc` x86 binary)
- No source maps

## Example Programs

See `programs/` for example programs (beside the toolchain's own tools and target probes):
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
  → cybs (~21 KB bootstrap compiler)
    → cycc (modular compiler + IR)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win    (Windows PE32+ cross-compiler)
      → cycc_cx     (cyrius-x bytecode; run by programs/cxvm.cyr)
      → the AGNOS kernel (separate `agnos` repo)
```

Current cycc size, IR pipeline state, and cross-compiler stats live in
[`docs/development/state.md`](../development/state.md). Per-release narrative
is in [`docs/development/completed-phases.md`](../development/completed-phases.md).
