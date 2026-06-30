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
exists for math hot paths: scalar `f64` floats and the `f64v2` / `f64v4`
SIMD vector types (`lib/math.cyr`, `lib/simd.cyr`), backed by SSE2/NEON
builtins. These are reinterpreted bit patterns — float ops use explicit
`f64_from` / `f64_to` conversions, not a full float type system.

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

# Break / Continue (in while and for)
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
& | ^ ~ << >>

# Logical (short-circuit, chainable)
&&  ||

# Explicit overflow operators (v5.6.2)
+%  -%  *%      # wrapping (alias for bare + - * — 2's complement wrap)
+|  -|  *|      # saturating (clamp to i64 min/max via lib/overflow.cyr)
+?  -?  *?      # checked (panic with exit code 57 on overflow)
```

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

## Includes

```
include "lib/string.cyr"
# Textual inclusion — file contents replace the include line
```

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

**Important**: test/bench/fuzz/soak/smoke files MUST be in the correct subdirectories.
- `.tcyr` files → `tests/tcyr/` (NOT `tests/` root)
- `.bcyr` files → `benches/` (NOT `tests/bcyr/`)
- `.fcyr` files → `fuzz/`
- `.scyr` files → `tests/scyr/` or `soak/`
- `.smcyr` files → `tests/smcyr/` or `smoke/`

Files in the wrong location will be silently ignored by the toolchain.

## Build Tool & Dependencies

```sh
# cyrius.cyml declares deps — build auto-resolves them
cyrius build src/main.cyr build/myapp   # resolves deps + compiles
cyrius deps                              # manually resolve deps
cyrius build -v src/main.cyr build/myapp # verbose (shows compiler, binary size)
cyrius test tests/test.tcyr             # resolve deps + compile + run
cyrius bench                             # discover + run benches/*.bcyr
cyrius fuzz                              # discover + run fuzz/*.fcyr harnesses
cyrius soak [N]                          # N-iter built-in self-host + tests/scyr/*.scyr (v5.7.38)
cyrius smoke                             # tests/smcyr/*.smcyr fail-fast (v5.7.38)
cyrius distlib                           # bundle src/ modules into dist/{name}.cyr
cyrius capacity [--check] <src>          # report compiler capacity / CI gate
cyrius lsp                               # build + install cyrius-lsp into ~/.cyrius/bin/
```

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

```
enum Result<T, E> {
    Ok(v),
    Err(e)
}

var ok = Ok(42);    # 16-byte heap alloc — tag at +0, payload at +8
var bad = Err(7);   # 16-byte heap alloc — tag at +0, payload at +8

# Multi-arg variants — alloc(8 + 8*N), payload[i] at +8 + 8*i
enum Tri<T, U, V> {
    Triple(a, b, c),
    Pair(x, y),
    Single(s),
    Bare                # no parens → auto-incremented int (3 here)
}

var t = Triple(11, 22, 33);   # 32-byte alloc; tag, [11, 22, 33]

# Empty parens = nullary tagged variant (8-byte alloc, tag-only)
enum Option {
    None();
    Some(v);
}
var n = None();      # 8-byte heap, tag at +0 only
var s = Some(42);    # 16-byte heap, tag at +0, payload 42 at +8
```

Generic params (`<T, E>`) are syntactically accepted but not yet semantically bound (mono-only erasure today). Variant separators may be `;` or `,` — mixed in same decl works. In mixed enums, bare names stay as int constants and paren'd names heap-allocate; convention is paren-consistent (`enum Option { None(); Some(v); }`) for sum types you'll match against.

Helper API:

- `lib/tagged.cyr` — `Option` / `Either` + the underlying `tag(t)` /
  `payload(t)` / `is_tag(t, expected)` / `tagged_new(tag, value)`
  primitives shared across all sum types.
- `lib/result.cyr` — `Result<T, E>` + Result-specific helpers
  (`is_ok` / `is_err_result` / `result_unwrap` / `result_unwrap_or` /
  `err_code_of` / `result_print`). Carved out of `lib/tagged.cyr`
  at v5.8.28 so consumers that only want `Result` can include just
  the dedicated module. `lib/tagged.cyr` transitively includes
  `lib/result.cyr` for back-compat — old code keeps working.

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
site to: load tag → if `Err`, return the Result heap pointer from
the enclosing fn → if `Ok`, unwrap the payload (`load64(rax + 8)`)
into rax. Highest precedence (binds tighter than `*` / `/`), so
`foo()? * bar` parses as `(foo()?) * bar`.

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

The compiler verifies coverage when at least one arm is a variant of an enum. Missing variants emit a warning; opt out with `_ =>`:

```
match s {
    PENDING => { ... }
    ACTIVE  => { ... }
}
# warning:<file>:<line>: non-exhaustive match over enum 'Status'
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
var opt = Some(42);
match load64(opt) {     # extract tag at +0
    Some => { var v = load64(opt + 8); ... }
    None => { ... }
}
```

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
heap environment object `[fn_ptr, cap0, cap1, …]`; the closure value *is* that
object. `callptr` auto-detects a captured closure and dispatches it (loads the
fn pointer from the object and passes the object itself as the hidden first
argument), so call sites look identical to the non-capturing case:

```
fn run(): i64 {
    var base = 40;
    var f = |x| base + x;            # captures `base` by value
    return callptr(f, 2);            # 42
}
```

A non-capturing closure stays a bare function pointer (no allocation); only
closures that actually read an enclosing local build an environment object.

Capture is **by value**: the closure sees the value the variable held at
construction. Mutating the original afterward does not change what the closure
returns, and the closure cannot write back to the enclosing variable.

Because the environment is heap-allocated, a translation unit that constructs a
capturing closure must `include "lib/alloc.cyr"` and call `alloc_init()` before
the closure is built. (A non-capturing closure needs neither.)

**Limitations.** Capturing closures are not yet supported on the Windows PE
target — constructing one there is a compile error; pass the needed values as
parameters instead. Captured closures are flat (no capture of a capture across
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

## Global Initializers

Variables can be declared among function definitions:

```
fn get_value() { return global_var; }
var global_var = 42;             # Visible to functions above
var r = get_value();             # r = 42
```

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
include "lib/str.cyr"     # Str type: str_from, str_len, str_eq, str_cat, str_sub, str_print
include "lib/vec.cyr"     # Dynamic array: vec_new, vec_push, vec_pop, vec_get, vec_set, vec_len
include "lib/io.cyr"      # File I/O: file_open, file_read, file_write, file_close, file_read_all
include "lib/fmt.cyr"     # Formatting: fmt_int, fmt_hex, fmt_hex0x, fmt_bool, fmt_byte
include "lib/args.cyr"    # CLI args: args_init, argc, argv
include "lib/fnptr.cyr"   # Function pointers: fncall0, fncall1, fncall2
include "lib/thread.cyr"  # Threads (clone+mmap), mutex (futex), MPSC channels
include "lib/async.cyr"   # Async primitives
include "lib/freelist.cyr"# Freelist allocator (free + reuse, O(1) alloc/free)
include "lib/math.cyr"    # Math functions: f64_atan and extended math ops
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
- Max ~64 global vars with initializers (use enums for constants)
- `default`, `match`, `in`, `shared` are keywords
- Closures (`|x| body`) are non-capturing — the body can't reference enclosing
  locals yet (pass them as parameters); lexical capture is a planned follow-up.
  Closures must be written inside a function. See the **Closures** section.

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
sh tests/heapmap.sh              # Heap map overlap detection

# Boot kernel
qemu-system-x86_64 -kernel build/agnos -serial stdio -display none
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
- `gettid()` → current thread id (GetCurrentThreadId)
- `mutex_new()`, `mutex_lock(m)`, `mutex_unlock(m)` — SRWLOCK (8-byte exclusive lock)
- `chan_new(cap)`, `chan_send(ch, val)`, `chan_recv(ch)`, `chan_try_recv(ch)` — thread-safe FIFO ring

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

agnos defines a frozen syscall surface (numbers 0–33, agnos 1.41.x+). The register
convention is x86_64 SysV (rax=number, rdi/rsi/rdx/r10=args 1–4, rax returns
result ≥0 on success, -1 on error). Key differences from Linux:

```
# agnos syscall numbers — FROZEN (lib/syscalls_x86_64_agnos.cyr)
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

**`lib/syscalls_x86_64_agnos.cyr`**: the full agnos syscall surface (0–33),
with wrappers (`sys_write`, `sys_read`, `sys_open`, `sys_spawn`, `sys_waitpid`,
`sys_mmap`, `sys_stat`, etc.) and the agnos `stat` / `getdents` record layouts.

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
- Syscall wrappers (all 0–33)
- Heap allocation (bump, 2 MB chunks)
- File I/O (read, write, open, close, stat, getdents)
- Process spawn and wait (in-memory ELF)
- Arguments and environment variables
- Pipes, epoll, signalfd, timerfd (the event loop primitives)
- Signals (sigprocmask, kill, pause)
- Filesystem (mkdir, rmdir, unlink, rename, link on ext2)
- SIMD, function pointers, inline asm (same as Linux/macOS)

**Does NOT work on agnos** (either frozen out of syscalls 0–33 or stubbed):
- Process arguments to spawned programs (`sys_spawn` is elf_addr, elf_size only)
- stdout/stderr redirection (`sys_dup` is a stub; pipe → spawn → wait works, but
  output goes to the terminal, not a buffer; `run_capture` returns 0 bytes)
- `getppid` (no getppid in frozen surface; returns 0)
- `getuid` (always 0 / root)
- `chmod` (no permission model; `sys_chmod` is a no-op stub returning 0)
- Thread-local storage (not modeled in agnos ring-3)
- Dynamic linking (`dlopen`, auxv machinery), only static binaries

The agnos syscall surface is **frozen as of 1.41.x** per its `docs/development/agnos-userland-abi.md`
protocol (§5): any number/signature change in that doc is authoritative, and this guide +
`lib/syscalls_x86_64_agnos.cyr` must be updated in sync. See `docs/development/issues/` for
follow-up arcs (e.g., "2026-06-03-agnos-followup-after-boot.md" covers the spawn-argv gap).

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

See `programs/` for 81 examples:
- **CLI tools**: cat, echo, head, wc, grep, hexdump, tail, tr, uniq, sort, basename, cols, count, toupper, rot13, rev, nl, seq, tee, yes, true, false
- **Algorithms**: fizzbuzz, primes, sieve, collatz, ackermann, gcd, brainfuck, life, xor
- **Data structures**: struct_list (linked list), alloctest (heap), strtype (fat strings)
- **Systems**: bitfield (PTE/GDT/IDT), asmtest (18 mnemonics), points (nested structs + typed ptrs)
- **Kernel**: kernel_hello (VGA), isr_stub (interrupt patterns), boot_serial, agnos (full kernel)

## Architecture

```
bootstrap/asm (29KB seed)
  → cybs (~21 KB bootstrap compiler)
    → cycc (modular compiler + IR)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win    (Windows PE32+ cross-compiler)
      → agnos.cyr  (AGNOS kernel)
```

Current cycc size, IR pipeline state, and cross-compiler stats live in
[`docs/development/state.md`](development/state.md). Per-release narrative
is in [`docs/development/completed-phases.md`](development/completed-phases.md).
