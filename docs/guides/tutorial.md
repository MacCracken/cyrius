# Getting Started with Cyrius

## Install

```sh
curl -sSf https://raw.githubusercontent.com/MacCracken/cyrius/main/scripts/install.sh | sh
```

Or build from source:

```sh
git clone https://github.com/MacCracken/cyrius.git
cd cyrius && sh bootstrap/bootstrap.sh       # the 29 KB seed assembles build/cybs, which rebuilds build/asm
cat src/main.cyr | ./build/cycc > /tmp/cycc && chmod +x /tmp/cycc   # rebuild cycc with the committed compiler
sh scripts/seed-derive-cycc.sh               # or derive it from the seed alone: seed → cybs → cycc, == build/cycc
```

## Hello World

```sh
echo 'syscall(1, 1, "Hello, world!\n", 14); syscall(60, 0);' | cycc > hello
chmod +x hello
./hello
```

That's it. No runtime. No linker. The `cycc` compiler reads source from stdin, writes a Linux ELF binary to stdout.

## Your First Program

Create `hello.cyr`:

```
fn main() {
    syscall(1, 1, "Hello from Cyrius!\n", 19);
    return 0;
}
var r = main();
syscall(60, r);
```

Compile and run:

```sh
cyrius build hello.cyr hello && ./hello      # or, in one step: cyrius run hello.cyr
```

`cyrius build` drives `cycc` for you: it resolves a project's dependencies, resolves
`include` paths relative to the source file, and handles cross-targets
(`cyrius build --aarch64 …`). Use it for anything past a one-liner.

## Variables and Expressions

The core type is the 64-bit integer (`i64`) — one register width, one
storage size (see ADR-002). Most code is just integers:

```
var x = 42;
var y = x + 8;
var z = x * y / 2;
var remainder = 100 % 7;     # 2
```

`i64` stays the core tenet, but it isn't the *only* type. A deliberate,
narrow exception exists for math hot paths: scalar `f64` / `f32` floats plus the
SIMD vector types — `f32v4` / `f32v8` and `f64v2` / `f64v4`, along with
the integer vectors (`i8v16` / `i16v8` / `i32v4` / `i64v2` and their
unsigned forms) (see `lib/math.cyr`, `lib/simd.cyr`). These are
bit-pattern values backed by packed SIMD emitters on every backend
(x86 SSE/AVX2, aarch64 NEON, Windows PE, cx bytecode) — not a full float
type system, just enough for numeric kernels. Everything else is built
from i64 words (a `bool` is a word holding 0 or 1). A few declarations
you will meet early:

```
const LIMIT = 7;                  # a compile-time constant: no storage
var ready: bool = false;          # true / false; a write into a bool is checked
var ratio: f64 = 1.5;             # a declared f64: its arithmetic is floating-point
var scaled = f64_to(ratio * 4.0); # 6
```

The guide covers the rest: *Constants and `const fn`*, *Booleans*, tuples
(*Tuples*), slices (*Slices*) and typed pointers (*Pointers*).

## Functions

```
fn add(a, b) {
    return a + b;
}

fn factorial(n) {
    if (n <= 1) { return 1; }
    return n * factorial(n - 1);
}

var result = add(20, 22);     # 42
var f5 = factorial(5);        # 120
```

A trailing parameter may have a default, and a call may name its arguments:

```
fn tag(a, b = 2, c = 3) { return a * 100 + b * 10 + c; }

var t1 = tag(1);              # 123 — b and c take their defaults
var t2 = tag(1, c: 9);        # 129 — b from its default, c by name
```

## Control Flow

```
# If / elif / else
if (x == 1) { println("one"); }
elif (x == 2) { println("two"); }
else { println("other"); }

# While
var i = 0;
while (i < 10) {
    i = i + 1;
}

# For
for (var i = 0; i < 10; i = i + 1) {
    println("iteration");
}

# Break
while (1 == 1) {
    if (done == 1) { break; }
}

# loop / do … while
var n = 0;
loop { n = n + 1; if (n == 3) { break; } }
do { n = n - 1; } while (n > 0);

# if as an expression: one expression per branch, else required
var sign = if (x > 0) { 1 } elif (x < 0) { 0 - 1 } else { 0 };
```

## Strings

String literals are null-terminated pointers to the data section.

```
syscall(1, 1, "hello\n", 6);     # write to stdout

include "lib/string.cyr"
var len = strlen("hello");        # 5
println("message");               # prints + newline
```

For dynamic strings, use the Str type:

```
include "lib/str.cyr"
var s = str_from("hello");
var t = str_from(" world");
var combined = str_cat(s, t);     # "hello world"
str_println(combined);
```

## Structs

```
struct Point { x; y; }

var p = Point { 10, 20 };
var sum = p.x + p.y;              # 30
p.x = 42;                         # field assignment
```

Methods live in `impl` blocks, and a `trait` declares a checked method set
(keep these declarations above your top-level statements):

```
struct Point { x; y; }

impl Point {                      # methods: an untyped `self` is the receiver
    fn norm1(self): i64 { return self.x + self.y; }
}

trait Show { fn show(self): i64; }    # a checked method set
impl Show for Point {
    fn show(self): i64 { return self.x * 10 + self.y; }
}

var p = Point { 4, 2 };
var n = p.norm1();                # 6  — a direct call: Point_norm1(&p)
var s = p.show();                 # 42
```

See the guide's *Traits and impl blocks* (default methods, trait bounds) and
*Trait objects: `dyn`* (dynamic dispatch).

## Enums

```
enum Color { RED; GREEN; BLUE; }
var c = BLUE;                      # c = 2

enum Error { OK = 0; NOT_FOUND = 44; PERM = 13; }
```

## Error Handling

`Result<T, E>` lives in `lib/result.cyr`, and its constructors `Ok(v)` and
`Err(e)` are compiler-generated. It is a value-form enum: a call returns a
(tag, payload) register pair and allocates nothing.

```
include "lib/result.cyr"

fn divide(a, b) {
    if (b == 0) { return Err(1); }
    return Ok(a / b);
}

# Bind BOTH halves; binding one would keep the tag and drop the payload, and is refused.
var tag, value = divide(42, 2);
if (is_ok(tag) == 1) {
    # `value` IS the payload — 21. No unwrap step needed.
}
```

The `?` propagation operator makes chained
Result-returning calls one-liners. It evaluates the expression,
short-circuits the enclosing fn on `Err` (passing the error on),
and unwraps `Ok` to the payload value:

```
include "lib/result.cyr"

fn safe_div(a, b) {
    if (b == 0) { return Err(1); }
    return Ok(a / b);
}

fn chain(a, b, c) {
    var x = safe_div(a, b)?;       # Err short-circuits chain
    var y = safe_div(x, c)?;
    return Ok(y);
}

var t1, ok    = chain(100, 4, 5);  # Ok(5):  is_ok(t1) == 1, ok == 5
var t2, miss1 = chain(100, 0, 5);  # Err(1) from the first ?
var t3, miss2 = chain(100, 4, 0);  # Err(1) from the second ?
```

The stdlib's I/O surface ships `Result`-returning `*_r`
variants alongside the legacy `-1`-on-error fns:

```
include "lib/io.cyr"            # IoError + file_open_r etc.

fn read_config(path) {
    var fd = file_open_r(path, 0, 0)?;     # Err(IoNotFound) / etc.
    var buf[8192];
    var n  = file_read_r(fd, &buf, 8192)?;
    file_close_r(fd);
    return Ok(n);
}
```

Per-module typed errors land alongside the `*_r` variants —
`IoError` (`lib/io.cyr`), `JsonError` / `TomlError` / `CymlError`
(`lib/bayan.cyr`, with `json_parse_file_r` and its peers), `HttpError`,
`DynlibError`, `PwdError`, `GrpError`, `ShadowError`, `PamError`.
See `docs/stdlib-reference.md` for the variant lists.

## Using Libraries

Include with textual inclusion:

```
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"

fn main() {
    var v = vec_new();              # the first allocation sets up the heap
    vec_push(v, 42);
    vec_push(v, 99);
    print_num(vec_get(v, 0));       # 42
    return 0;
}
```

When the top-level code runs to its end without exiting, the program calls
`fn main()` (if there is one) and exits with its return value — so this
example needs no call. A program that calls `main()` itself exits explicitly
(`syscall(60, r)`, as the earlier examples do), or `main` runs a second time.

## Create a Project

```sh
cyrius init myproject
cd myproject
cyrius build              # [build] entry -> output in cyrius.cyml: src/main.cyr -> build/myproject
./build/myproject
cyrius test               # every test the manifest and tests/ hold
```

This creates a complete project: a `cyrius.cyml` manifest, `src/main.cyr`,
the stdlib vendored into `lib/`, starter test / bench / fuzz files under
`tests/`, docs and CI workflows. The modules named in the manifest's
`[deps] stdlib` list are included for you, so `src/main.cyr` needs no
`include` lines for them. `cyrius build` resolves `[deps]` before it
compiles; `cyrius deps` does that step on its own.

## Testing

```
include "lib/assert.cyr"

fn main() {
    assert(1 + 1 == 2, "math works");
    assert_eq(strlen("abc"), 3, "strlen");
    return assert_summary();        # the number of failures
}
var exit_code = main();
if (exit_code > 0) { exit_code = 1; }   # an exit status is 8 bits: 256 failures would read as 0
syscall(60, exit_code);
```

Save it as `tests/math.tcyr` and run it with `cyrius test` (every `.tcyr`
under `tests/`) or `cyrius test tests/math.tcyr`.

## Next Steps

- [Language Guide](cyrius-guide.md) — complete reference
- [Standard Library](../stdlib-reference.md) — every function documented
- [Size comparisons](../size-comparisons.md) — exit42 across languages, compiler footprint
- [Examples](../../programs/) — the toolchain's own tools and small demo programs
