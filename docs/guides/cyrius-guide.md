# Cyrius Language Guide

> The complete reference for writing Cyrius programs and kernels.

## Quick Start

```sh
cyrius build hello.cyr build/hello           # Compile (resolves deps from cyrius.cyml)
./build/hello; echo $?                       # Run → 42
```

## Types

Everything is a 64-bit integer. No floats, no separate pointer type at the value level. Type annotations are optional and don't enforce:

```
var x = 42;
var y: i64 = 42;      # Same thing — annotation is documentation
```

## Variables

```
var x = 10;            # Global or local (context-dependent)
var buf[256];           # Array (256 * 8 = 2048 bytes)
x = x + 1;             # Reassignment
```

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

# For
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
etc.) stay callable through v5.8.x for back-compat. v6.0.0 closeout
removes the old shape.

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

# Call through pointer (using fnptr library):
include "lib/fnptr.cyr"
var result = fncall2(fp, 20, 22);    # result = 42
```

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

```
# Shared types (agnostik)
include "lib/agnostik/error.cyr"    # Error codes (1001-1010), err_is_retriable, err_print
include "lib/agnostik/types.cyr"    # AgentType, AgentStatus, MessageType, SystemStatus enums
include "lib/agnostik/security.cyr" # Permission (bitmask), Role, SecurityContext struct
include "lib/agnostik/agent.cyr"    # AgentConfig, AgentInfo, AgentStats structs
include "lib/agnostik/audit.cyr"    # AuditSeverity, AuditEntry, audit_print
include "lib/agnostik/config.cyr"   # AgnosConfig, environment profiles

# Syscall bindings (agnosys)
include "lib/agnosys/syscalls.cyr"  # 50 syscall numbers, 20+ wrappers, sigset, epoll, timerfd

# Init system (kybernet)
include "lib/kybernet/console.cyr"  # PID 1 stdio redirect
include "lib/kybernet/signals.cyr"  # Signal blocking + signalfd
include "lib/kybernet/reaper.cyr"   # Zombie process reaper (waitpid loop)
include "lib/kybernet/privdrop.cyr" # Privilege dropping (setgroups/setgid/setuid)
include "lib/kybernet/mount.cyr"    # Essential filesystem mounts
include "lib/kybernet/cgroup.cyr"   # Cgroup v2 service management
include "lib/kybernet/eventloop.cyr"# Epoll + timerfd event loop
```

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

- No `&&`/`||` mixed in same condition — use nested `if`
- `for` loop step must be simple assignment (`i = i + 1`)
- Exit codes truncated to 0-255 (Linux limitation)
- Max ~64 global vars with initializers (use enums for constants)
- No negative literals — use `(0 - N)` instead of `-N`
- `default`, `match`, `in`, `shared` are keywords
- Block closures (`|x| { ... }`) only work inside functions

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

## Example Programs

See `programs/` for 68 examples:
- **CLI tools**: cat, echo, head, wc, grep, hexdump, tail, tr, uniq, sort, basename, cols, count, toupper, rot13, rev, nl, seq, tee, yes, true, false
- **Algorithms**: fizzbuzz, primes, sieve, collatz, ackermann, gcd, brainfuck, life, xor
- **Data structures**: struct_list (linked list), alloctest (heap), strtype (fat strings)
- **Systems**: bitfield (PTE/GDT/IDT), asmtest (18 mnemonics), points (nested structs + typed ptrs)
- **Kernel**: kernel_hello (VGA), isr_stub (interrupt patterns), boot_serial, agnos (full kernel)

## Architecture

```
bootstrap/asm (29KB seed)
  → cyrc (12KB compiler)
    → bridge.cyr (bridge compiler)
      → cc5 (modular compiler + IR, 9 modules)
        → cc5_aarch64 (Linux + macOS Mach-O cross-compiler)
        → cc5_win    (Windows PE32+ cross-compiler)
        → agnos.cyr  (AGNOS kernel)
```

Current cc5 size, IR pipeline state, and cross-compiler stats live in
[`docs/development/state.md`](development/state.md). Per-release narrative
is in [`docs/development/completed-phases.md`](development/completed-phases.md).
