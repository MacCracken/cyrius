# FAQ & Troubleshooting

## Common Questions

### What is Cyrius?
A self-hosting systems language that bootstraps from a 29KB binary. No Rust, no LLVM, no Python. Designed to write the AGNOS operating system kernel.

### What can I build with it?
CLI tools, system utilities, kernels, init systems, package managers. Anything that runs on Linux x86_64 or aarch64. See `programs/` for 59 examples.

### How is everything i64?
Every value is a 64-bit integer. Strings are pointers (which are integers). Structs are contiguous memory (accessed via integer offsets). This simplifies the compiler enormously while still being practical for systems code.

### Where are the types?
Type annotations (`var x: i64 = 42`) are documentation. Generics (`fn foo<T>()`) are parsed but not enforced. The compiler warns on pointer/scalar mismatches at assignment. Full type checking is on the roadmap.

### Is it fast?
The compiler self-compiles in ~387 ms (cycc → cc5b 3-step fixpoint, ~875 KB output at v5.11.59). Total compile time fell from 1037 ms → 387 ms (-63%, 2.7×) across the v5.10.40+v5.10.41 compile-time-perf miniarc. Programs are 10-233x smaller than GNU equivalents. `wc` is 20x faster than GNU on large files. See [size comparisons](size-comparisons.md) for the canonical exit42 numbers across languages and platforms.

---

## Troubleshooting

### "error at token N (type=T)"
The compiler hit unexpected syntax. Common causes:
- **type=5 (SEMICOLON)**: Missing expression before `;`. Check for empty assignments like `var x = ;`
- **type=17 (==)**: Comparison in wrong context. Did you put `==` inside a function call before the comparison-in-args fix?
- **type=33 (RETURN)**: `return` outside a function body, or `default` used as a parameter name (it's a keyword)
- **type=19 (LT)**: `<` being parsed as comparison when you meant generics. Make sure generics are on function/struct definitions, not in expressions.

### "error: duplicate var at token N"
Two `var` declarations with the same name in the same function. Cyrius has no block scoping — all vars in a function share one scope. Rename the duplicate.

### "error: fixup table full"
Too many variable / function references in one compilation. The cap has been raised three times across v5.x (16K → 32K → 262K at v5.7.1 → 1M at v5.7.7). If you hit the 1M cap, the source genuinely needs splitting — or file an issue and we'll consider the fourth bump (which would convert to a dynamic vec; see roadmap §"fixup table dynamic conversion").
- Run `cyrius capacity --check src/main.cyr` to see how close you are to each cap
- Split into smaller files compiled separately
- Reduce the number of includes

### Program exits with wrong code
Exit codes are truncated to 0-255 (Linux limitation). Use `print_num()` or `fmt_int()` to display values larger than 255.

### Enum values are 0 inside functions
This was a bug (fixed in 0.9.0). If you're on an older version, update. The fix: enum init code must run before global var init code in the compiler entry point.

### "include" string literal breaks compilation
The preprocessor eats `"include "` patterns in string literals. Workaround: build the pattern at runtime using `store8()`. See the cybs source for an example.

### aarch64 binary crashes with SIGILL
Check that you're using `cycc_aarch64` (the cross-compiler) and running via `qemu-aarch64`. Common encoding bugs were fixed in 0.9.0.

### Vec bounds check aborts
`vec_get`/`vec_set` abort on out-of-bounds access. Check your indices. Use `vec_len()` to verify before accessing.

### `alloc()` returns 0
You forgot to call `alloc_init()` at the start of `main()`.

### Strings print garbage
String literals are null-terminated, but if you're building strings manually, make sure to `store8(buf + len, 0)` for the null terminator.

---

## Known Limitations

1. No `&&`/`||` mixed in same condition — use nested `if`
2. For loop step must be simple assignment (`i = i + 1`)
3. Exit codes truncated to 0-255
4. Max ~64 global vars with initializers (use enums for constants)
5. Max 1M fixup entries per compilation (v5.7.7; was 1024 pre-v5.x — `cyrius capacity --check` to monitor)
6. Max 4096 functions per compilation (was 256 pre-v5.x; raised to 4096 in alpha series)
7. No negative literals — use `(0 - N)` instead of `-N`
8. `default`, `match`, `in` are keywords — don't use as variable names
9. Block closures (`|x| { ... }`) only work inside functions, not at global scope

## Gotchas

1. **Dynamic loop bounds**: `for (var i = 0; i < GLOBAL; i = i + 1)` re-evaluates
   `GLOBAL` each iteration. If the body modifies `GLOBAL`, the loop count changes.
   Fix: `var limit = GLOBAL; for (var i = 0; i < limit; ...)`.

2. **Operator overloading with stack structs**: `a + b` where `a` is a struct
   literal (`var a = Point { 1, 2 }`) passes the first field value, not the address.
   Works correctly for pointer-based types (`Str`, `Vec`).

3. **Enum constructors need alloc**: `Ok(42)` calls `alloc(16)` internally.
   Must call `alloc_init()` before using auto-generated constructors.
