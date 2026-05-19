# Getting Started with Cyrius

## Install

```sh
curl -sSf https://raw.githubusercontent.com/MacCracken/cyrius/main/scripts/install.sh | sh
```

Or build from source:

```sh
git clone https://github.com/MacCracken/cyrius.git
cd cyrius && sh bootstrap/bootstrap.sh
cat src/main.cyr | ./build/cc5 > /tmp/cc5 && chmod +x /tmp/cc5
```

## Hello World

```sh
echo 'syscall(1, 1, "Hello, world!\n", 14); syscall(60, 0);' | cc5 > hello
chmod +x hello
./hello
```

That's it. No runtime. No linker. The `cc5` compiler reads source from stdin, writes a Linux ELF binary to stdout.

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
cat hello.cyr | cc5 > hello && chmod +x hello && ./hello
```

## Variables and Expressions

Everything is a 64-bit integer. No floats, no separate types.

```
var x = 42;
var y = x + 8;
var z = x * y / 2;
var remainder = 100 % 7;     # 2
```

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

## Enums

```
enum Color { RED; GREEN; BLUE; }
var c = BLUE;                      # c = 2

enum Error { OK = 0; NOT_FOUND = 44; PERM = 13; }
```

## Error Handling

`Result<T, E>` lives in `lib/result.cyr` (carved out of
`lib/tagged.cyr` at v5.8.28). Constructors `Ok(v)` and `Err(e)`
are compiler-generated since v5.8.23.

```
include "lib/alloc.cyr"
include "lib/result.cyr"

fn divide(a, b) {
    if (b == 0) { return Err(1); }
    return Ok(a / b);
}

alloc_init();

var r = divide(42, 2);
if (is_ok(r) == 1) {
    var value = result_unwrap(r);   # 21
}
```

The `?` propagation operator (v5.8.29) makes chained
Result-returning calls one-liners. It evaluates the expression,
short-circuits the enclosing fn on `Err`, and unwraps `Ok` to
the payload value:

```
fn safe_div(a, b) {
    if (b == 0) { return Err(1); }
    return Ok(a / b);
}

fn chain(a, b, c) {
    var x = safe_div(a, b)?;       # Err short-circuits chain
    var y = safe_div(x, c)?;
    return Ok(y);
}

var ok    = chain(100, 4, 5);      # Ok(5)
var miss1 = chain(100, 0, 5);      # Err(1) from first ?
var miss2 = chain(100, 4, 0);      # Err(1) from second ?
```

The stdlib's I/O surface ships `Result`-returning `*_r`
variants alongside the legacy `-1`-on-error fns:

```
include "lib/io.cyr"            # IoError + file_open_r etc.
include "lib/json.cyr"          # JsonError + json_parse_file_r

fn read_config(path) {
    var fd = file_open_r(path, 0, 0)?;     # Err(IoNotFound) / etc.
    var buf[8192];
    var n  = file_read_r(fd, &buf, 8192)?;
    file_close_r(fd);
    return Ok(n);
}
```

Per-module typed errors land alongside the `*_r` variants —
`IoError`, `JsonError`, `TomlError`, `CymlError`, `HttpError`,
`DynlibError`, `PwdError`, `GrpError`, `ShadowError`, `PamError`.
See `docs/stdlib-reference.md` for the variant lists.

## Using Libraries

Include with textual inclusion:

```
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"

fn main() {
    alloc_init();                   # required before any heap allocation
    var v = vec_new();
    vec_push(v, 42);
    vec_push(v, 99);
    print_num(vec_get(v, 0));       # 42
    return 0;
}
```

## Create a Project

```sh
cyrius init myproject
cd myproject
sh scripts/build.sh
./build/myproject
sh scripts/test.sh
```

This creates a complete project with vendored stdlib, build scripts, and test file.

## Testing

```
include "lib/assert.cyr"

fn main() {
    alloc_init();
    assert(1 + 1 == 2, "math works");
    assert_eq(strlen("abc"), 3, "strlen");
    return assert_summary();
}
var exit_code = main();
syscall(60, exit_code);
```

## Next Steps

- [Language Guide](cyrius-guide.md) — complete reference
- [Standard Library](stdlib-reference.md) — every function documented
- [Size comparisons](size-comparisons.md) — exit42 across languages, compiler footprint
- [Examples](../programs/) — 59 working programs
