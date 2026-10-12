# FAQ & Troubleshooting

## Common Questions

### What is Cyrius?
A self-hosting systems language that bootstraps from a 29KB binary. No Rust, no LLVM, no Python. Designed to write the AGNOS operating system kernel.

### What can I build with it?
CLI tools, system utilities, kernels, init systems, package managers, and networked services (a native TLS 1.3 stack ships in `lib/tls_native.cyr` — no OpenSSL). Anything that runs on Linux (x86_64/aarch64), macOS (arm64 + x86_64 Mach-O), or Windows (x86_64 PE32+) — cycc self-hosts byte-identical on all of them — plus portable `.cyx` bytecode (run by `cxvm`), AGNOS userspace, bare-metal kernels and UEFI applications. `programs/` holds the toolchain's own tools (the LSP, formatter, linter, doc generator, …) and small demo programs (`cat`, `wc`, `grep`, `life`, `brainfuck`, `sieve`, …).

### How is everything i64?
The core type is the 64-bit integer (see ADR-002): strings are pointers (which are integers), and structs are contiguous memory accessed via integer offsets. This simplifies the compiler enormously while still being practical for systems code. The one deliberate, narrow exception is math hot paths — scalar `f64`/`f32` floats plus the full SIMD vector set: `f64v2`/`f64v4`, `f32v4`/`f32v8`, and the integer vectors `i8v16`/`i16v8`/`i32v4`/`i64v2` (`lib/math.cyr`, `lib/simd.cyr`), on every backend — which are bit-pattern values, not a full float type system. Everything else is built from i64 words: a `bool` is a word holding 0 or 1, a slice is a (pointer, length) pair, a `u128` or a tuple is two or more words.

### Where are the types?
An `i64` annotation (`var x: i64 = 42`) is documentation — an untyped `var` is already an i64 word. Other annotations change what the code does, and the compiler checks them: an `f64` / `f32` makes its arithmetic floating-point (every write into an `f32` rounds to f32), a write into a `bool` must be a boolean value, a `*T` steps and subscripts by `sizeof(T)`, a struct type gives field access and by-value copies, and a struct argument must match its parameter's struct type. A typed pointer assigned a non-pointer (`var p: *i64 = 7`) warns, and so does integer arithmetic with a float operand. Generics (`fn foo<T>()`, `struct Box<T>`) are instantiated per type argument; traits and `impl` blocks are checked, trait bounds (`<T: Show>`) are checked at the definition and at every instantiation, and `dyn Trait` is a checked trait object. See the guide's *Traits and impl blocks*, *Trait objects: `dyn`* and *Generic Functions*.

### Is it fast?
The compiler compiles itself in a second or two on a desktop x86_64 box, and the result is byte-identical to the compiler that built it (a 3-step fixpoint). Each release's self_compile time and cycc size are recorded in its `CHANGELOG.md` entry (**Bench** and **Size**); `BENCHMARKS.md` tracks self_compile across runs. ⚠ Treat a single self_compile figure as noise: it moves between runs with no code change, and with the box's load. The small `programs/` utilities (`cat`, `wc`, `head`, …) build to static, libc-free binaries of a few KB. See [size comparisons](../size-comparisons.md) for the canonical exit42 numbers across languages and platforms.

---

## Troubleshooting

### Reading a syntax error
Every diagnostic is `error:<file>:<line>:<col>: <message>` (`<source>` names the
entry file, an included file's path names that file), followed by the offending
source line and a caret (`^`) under the exact column. cycc runs in
**panic-mode recovery**: it reports *many* errors in one compile (not just the
first), emits **no** output binary when any error fired, and never hangs or
crashes on hostile input. Common syntax causes:
- **Missing expression before `;`** — empty assignments like `var x = ;`.
- **A reserved keyword used as an identifier** (`default`, `secret`, `pub`,
  `shared`, …) — the message names the word.
- **`<` parsed as comparison when you meant generics** — generics live on
  function/struct *definitions* (`fn foo<T>()`), not in expressions.

(If you ever see `error: parser recovery aborted (desync — too many errors)`,
the recovery watchdog tripped on deeply malformed input — fix the earliest
reported error and recompile.)

### "duplicate variable"
Two `var` declarations with the same name in the same block. Every braced body (`if`, `while`, `for`, a plain `{ }` block, a fn body) is its own scope: a `var` declared inside a block is not visible after it, and one of the same name as an outer variable hides that variable only inside the block. Rename the duplicate, or assign to the existing variable. (A top-level `var` redeclared is not this error — see the guide's *Global Initializers*.)

### "a `: stack` enum returns two values — bind both"
`Result`, `Option` and `Either` (and any `enum Name: stack`) return a (tag, payload) register pair, so `var r = f();` would keep the tag and drop the payload — it is refused. Bind both halves: `var tag, val = f();`, then test the tag (`is_ok(tag)`) and use `val` as the payload. `f()?` propagates both halves.

### fixup / function / code-buffer capacity
The three former pressure tables are **growable** — each grows on demand into
off-heap memory:
- **fixup table** — grows to a 64M-entry ceiling
- **fn-tables** — grow + rehash to a 131,072-function ceiling
- **codebuf** — 8 MiB initial, grows +8 MiB per step to a 64 MiB ceiling

(On the cx bytecode target the fixup table and the code buffer are fixed-size.)
You'd only hit a ceiling on a genuinely pathological compilation. `cyrius capacity
--check src/main.cyr` reports headroom against every table; splitting into
separately-compiled units remains the fallback for the rare ceiling case.

### Program exits with wrong code
Exit codes are truncated to 0-255 (Linux limitation). Use `print_num()` or `fmt_int()` to display values larger than 255.

### aarch64 binary crashes with SIGILL
Check that you built it for aarch64 — `cyrius build --aarch64 <src> <out>` (which runs the `cycc_aarch64` cross-compiler) — and that you run it on aarch64 hardware or under `qemu-aarch64`. An x86_64 binary on an aarch64 host, or the reverse, fails before your code runs.

### Vec bounds check aborts
`vec_get`/`vec_set` abort on out-of-bounds access. Check your indices. Use `vec_len()` to verify before accessing.

### `alloc()` returns 0
The request was zero or negative, larger than `ALLOC_MAX` (2 GiB), or the OS refused the memory. It is not a missing `alloc_init()`: that call is optional, and the first `alloc()` sets up the heap.

### Strings print garbage
String literals are null-terminated, but if you're building strings manually, make sure to `store8(buf + len, 0)` for the null terminator.

---

## Known Limitations

1. A classic `for` step is ONE assignment — `=` or a compound operator (`i = i + 1`, `i += 2`, `p.n += 1`) — not a call, not `i++`, not a comma list
2. Exit codes truncated to 0-255
3. At most 1,048,576 globals, enum members and top-level arrays per compilation unit (the var table); globals with non-literal initializers have no separate cap
4. Fixup entries: growable to a 64M-entry ceiling (`cyrius capacity --check` to monitor headroom)
5. Functions per compilation: growable to a 131,072 ceiling
6. Negative literals work (`-5`, `-1.5`, `-x`). For a FLOAT, never write `0 - N`: an operator is typed by its LEFT operand, so `0 - 1.5` is integer arithmetic on 1.5's bits (it is -3.0 — the compiler warns). Write `-1.5`, `-x` or `0.0 - x` — with `x` typed `f64`; on an UNTYPED var or struct field holding float bits, `-x` is integer negation too (warned when an untyped variable was initialised from a float), so write `f64_neg(x)`.
7. Reserved words are a class, not a short list — the builtins and intrinsics (`syscall`, `load64`, the `f64_*` builtins, `sizeof`, `fncall0`..`fncall8`, …) and the statement keywords (`default`, `match`, `in`, `trait`, `impl`, `dyn`, `do`, `true`, `false`, `const`, …) cannot be identifiers. The error names the word you hit; see the guide's reserved-word note under *Functions*. `loop` and `kernel` are contextual and stay usable as names.
8. A capturing closure (one that reads an enclosing local) takes at most five parameters on Linux and macOS, three on Windows — its environment rides in one argument register — and needs `include "lib/alloc.cyr"` for its heap environment. Closures work at top level as well as inside functions.
9. `f64_exp` / `f64_ln` / `f64_log2` / `f64_exp2` and `f64_atan` are within 1 ulp with IEEE special values on every target, but not bit-identical ACROSS targets: x86 uses x87, aarch64 a software port. For identical bits everywhere call `_f64_exp_polyfill` / `_f64_ln_polyfill` / `_f64_log2_polyfill` / `_f64_exp2_polyfill` / `_f64_atan_polyfill` in `lib/math.cyr` directly — supported entry points despite the `_` prefix (see `docs/stdlib-reference.md`, *math.cyr*). `f64_sin` / `f64_cos` already run the same polyfill on every target (include `lib/math.cyr` to use them). See the guide's *Math Builtins*.

## Gotchas

1. **Dynamic loop bounds**: `for (var i = 0; i < GLOBAL; i = i + 1)` re-evaluates
   `GLOBAL` each iteration. If the body modifies `GLOBAL`, the loop count changes.
   Fix: `var limit = GLOBAL; for (var i = 0; i < limit; ...)`.

2. **Operator overloading passes a struct by its size**: `a + b` on struct values
   calls `T_add(a, b)`; an operand of 8 bytes or less arrives by value, a larger one
   (`var a = Point { 1, 2 }`) by address. Type the operator fn's parameters
   (`fn Point_add(a: *Point, b: *Point)` or `a: Point`) so `a.x` resolves.

3. **Boxed enum constructors need `lib/alloc.cyr`**: a payload variant of a plain
   `enum` (no `: stack`) allocates its box with `alloc()`, so include `lib/alloc.cyr`
   wherever you construct one (`alloc_init()` is optional). `Ok(42)` does not
   allocate: `Result`, `Option`, `Either` and any `enum Name: stack` return a
   (tag, payload) register pair.
