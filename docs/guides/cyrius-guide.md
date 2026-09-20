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
- **Calling with the wrong number of arguments is a hard error** (v6.5.1; there is no
  overloading and no default arguments, so a count mismatch is never intentional). Since
  **6.6.5** that applies to the `obj.m(...)` method form as well — it used to build and bind
  the surplus parameter to whatever was in the register. ⚠ One consequence: an `impl` method
  written with **no `self` parameter** can no longer be called through the dot form, because
  the dot form supplies a receiver the method never declared. Call it by its mangled name
  (`Type_method(args)`), which is how the constructor idiom `fn new(a, b)` inside an `impl` is
  written anyway. Forward calls are exempt from the check — the callee has no body yet.

**Reserved words are a CLASS, not a short list.** `TOKNAME_BUILTIN` in
`src/common/util.cyr` is the single source of truth — **76** builtin/intrinsic names
(re-derived at 6.6.5 with `sed -n '/fn TOKNAME_BUILTIN/,/^}/p' src/common/util.cyr |
grep -c 'return "'`; this line said 67, which was the count when the diagnostic was added at
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

### Where a struct lives (v6.6.5)

A struct declared inside a fn — `var p = Point { 1, 2 };`, `var p: Point;`, `var p: Point = q;`
— is a **per-call frame object**. It is fresh on every call, private to the calling thread, and
its name is visible only inside its own scope. Take its address with `&p`; pass it to a
`p: Point` parameter and the callee receives that address.

A struct declared at TOP LEVEL is a single shared object in the data section, and a local
declared as `var p: Point = <expression>` where the expression yields an ADDRESS (a heap
pointer, or a fn returning one) is a **pointer** to that object — `p.x` reads through it rather
than out of the frame. The compiler records which of the two a variable is at its declaration;
before v6.6.5 it guessed from the shape of the neighbouring stack slot and got it wrong for any
pointer-mode struct declared after a closed `{ ... }` block.

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

⚠ **A copy moves one struct into a variable of that SAME struct type.** `p = q` and
`var p: P3 = q` between two DIFFERENT struct types are a compile error since v6.6.6
(`cannot copy 'q' into a variable of a different struct/vector type: 'p'`), and so is a copy
between two different vector types (`f64v4 = f64v2`). Before v6.6.6 both compiled clean and
fell through to a plain 8-byte store: the assignment copied one word of three and left the rest
of `p` stale, and the declaration stored `q`'s *address* into a struct-typed slot, so `p.x` read
back a stack address. The struct-*literal* form (`var p: P3 = Q3{..}`) has been an error since
v6.6.5. A source that is **not** a struct or vector still binds as a pointer, unchanged.

⚠ **A by-value struct PARAMETER over 8 bytes is address-passed** — the parameter's slot holds
the caller's address, which is why writing `q.z = 5` inside the callee is visible to the caller.
Since v6.6.6 every path that copies or returns such a parameter goes through that address:
`q = r`, `q = mk(..)`, `q = b.mk(..)`, `q = a + b`, `q = G`, `r = q`, `G = q`, `q = w` (a copy,
not an alias) and `return q;` all move the whole struct. Before v6.6.6 they moved the POINTER
instead — `q = r` overwrote it and the next `q.z` SIGSEGV'd, `r = q` put the pointer in `r`'s
first field, and `return q;` returned the address as the value, silently. `Str` (and `Result` /
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
parameter denotes the caller's struct.

⚠ At TOP LEVEL there is no frame to hold the result, so a struct-valued call there
(`mk(1);`, `var g: P3 = mk(1);`, `g = mk(1);`, `take(mk(1))` — and the method and operator
forms alike) is a compile error naming the fn — call it inside a fn. An untyped
`var g = pair_fn(..)` of a 9-16 B struct still yields its first word.
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
cyrius test a.tcyr b.tcyr -D FEATURE     # 1..N files; -D/-DNAME reaches test/run/bench/fuzz/check too (v6.6.5)
cyrius run src/main.cyr host 443         # compile + run; everything AFTER the source is the program's argv (v6.6.5)
cyrius run prog.cyx                      # run cx bytecode via cxvm — arguments are REFUSED (cx has no guest argv yet)
cyrius lint|fmt|doc a.cyr b.cyr          # 1..N files, every one processed (v6.6.5)
cyrius tests [dir]                       # recursively run every .tcyr under dir (default tests/)
cyrius bench [path|dir]                  # discover + run *.bcyr (recursive; v6.5.7)
cyrius fuzz [path|dir]                   # discover + run *.fcyr harnesses (recursive; v6.5.7)
cyrius self                              # self-host check: compile THIS HOST's compiler fork twice, cmp (v6.6.6)
cyrius soak [N]                          # N-iter built-in self-host + tests/scyr/*.scyr (v5.7.38)
cyrius smoke                             # tests/smcyr/*.smcyr fail-fast (v5.7.38)
cyrius distlib [profile]                 # bundle src/ modules into dist/{name}.cyr
cyrius distlib --all                     # regenerate the base bundle AND every [lib.X] profile (v6.5.8)
cyrius distlib --check                   # verify bundles are current — compares BYTES, writes nothing (v6.5.8)
cyrius coverage [--full] [--min <pct>]   # reference coverage of src/ (--min 0..100 gates CI)
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

**`cyrius.lock` is a contract, not a cache (v6.6.4).** When a project has a git dep the
resolver writes `cyrius.lock`: one `commit	…` line per git dep (a repointed tag is refused
against it), one `<sha256>  lib/<file>` line per vendored file (sorted), and a `cyrius	<pin>`
trailer naming the stdlib pin. On every resolve — including the implicit one `cyrius build`
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
`$CYRIUS_HOME/deps/<name>/<tag>` and reused by every project on the machine, so on every
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

⚠ **Native Windows is out of scope for all of this**, as the git-dep flow always has been:
`sys_fork` does not exist there, so no git command can run. A pre-populated cache resolves with
a one-line warning that it was NOT verified, rather than failing with a reason that would be
untrue.

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

```
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
form. Call it with `fncallN` (an ordinary function from `lib/fnptr.cyr`, so it works
at top level too) or, from inside a function, with `callptr` — a bare `callptr` in
top-level code is refused: *an indirect call (callptr / fncallN) must be inside a
function, not at top level*. ⚠ **Before 6.6.6 a block-bodied closure in
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
runtime. `async` generic fns are not yet supported, nor is a value-form vector
PARAMETER (`async fn f(v: f64v2)`) — an `async fn` captures each argument as one
8-byte value, so since v6.6.6 that is a compile error naming the parameter; pass
a pointer to the vector instead (before v6.6.6 it compiled and computed with the
wrong vector). A **by-value struct RETURN** over 8 bytes is likewise unsupported
and, since v6.6.6, a compile error naming the fn: a Future carries one i64, so a
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
- An array's `= { .. }` byte list is a sequence of byte stores, so two byte-list
  declarations of one array both run, in order.
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
(`DeleteFileW`, `MoveFileExW`, `RemoveDirectoryW` since v6.6.6, …) behind the same names. `cyrlint` flags a raw `sys_open`
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

⛔ **A RAW SYSCALL NUMBER IS THE SINGLE MOST PORTABLE-LOOKING THING THAT IS NOT PORTABLE, and
ELF-aarch64 will not tell you.** The aarch64 backend rewrites the x86_64 numbers it knows
(`ESYSXLAT`, a hand-written chain — derive its row count from the source, never quote it) and passes everything else through to the `svc` verbatim — by design,
because a native aarch64 number must survive. So an unrecognised number is not an error, it is
a *different, valid syscall*. Measured under `qemu-aarch64 -strace` before v6.6.5: raw 77
(x86 `ftruncate`) ran **tee**, raw 46 (`sendmsg`) ran **ftruncate**, raw 44 (`sendto`) ran
fstatfs, raw 35 (`nanosleep`) ran `unlinkat(0, NULL, 0)`, raw 87 (`unlink`) ran
timerfd_gettime and raw 83 (`mkdir`) ran fdatasync. The build succeeded and printed nothing.

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

Same trap on the other side: `var SYS_FOO = <x86 number>` in your own source SHADOWS the
stdlib's arch-aware definition (last definition wins), so it is right on x86 and wrong
everywhere else. cycc warns on a conflicting `SYS_*` redefinition.

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
