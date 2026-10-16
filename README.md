# Cyrius

**Sovereign, self-hosting systems language. Assembly up.**
 
A self-hosting compiler toolchain that bootstraps from a 29 KB binary with zero external dependencies. No Rust, no LLVM, no Python, no libc. Writes the [AGNOS](https://github.com/MacCracken/agnos) kernel, its own package manager, its own build tool, and bootable UEFI applications.

A ~2.06 MB compiler (`cycc`, x86_64 Linux) that reproduces itself byte-identically on x86_64 and aarch64 Linux, macOS (arm64 and Intel Mach-O) and Windows (PE32+) — checked on real hardware at every release — and also emits UEFI applications, bare-metal kernels and cyrius-x bytecode (run by `cxvm`). Position-independent code (`--pie`), `.gnu.hash` dynamic linking, **W^X** userland ELF by default (separate `R E` / `RW ` `PT_LOAD` segments; `CYRIUS_WX=0` restores the single `RWE` segment), and a TS/TSX → JS emitter (`cycc --emit-js`). Packed SIMD — f32 / f64 / integer 128-bit and **256-bit AVX2** (elementwise, FMA, horizontal dot) with CPUID runtime dispatch — on every backend: x86 (SSE + AVX2), aarch64 NEON, Windows PE, and cx bytecode per-lane loops. Sovereign native TLS 1.3 — client + server, sigil-backed X.509 chain verification, no OpenSSL — is the **default** TLS backend (`-D CYRIUS_TLS_LIBSSL` opts back to the libssl bridge). `Result` / `Option` / `Either` are **value-form** — a payload variant returns `(tag, payload)` in a register pair, so construction allocates **zero bytes**. 106 stdlib modules with **0 git dependencies**: twelve sibling libraries are folded into `lib/` byte-identical from their tags (see *Standard Library* below). Sizes and counts are in *Metrics* below; the live figures are in [docs/development/state.md](docs/development/state.md).

## Install

```sh
curl -sSf https://raw.githubusercontent.com/MacCracken/cyrius/main/scripts/install.sh | sh
```

Or bootstrap from source, in a clone (Linux x86_64):

```sh
sh bootstrap/bootstrap.sh          # the 29 KB seed assembles cybs (+ the closure check)
sh scripts/seed-derive-cycc.sh     # seed → cybs → cycc, byte-identical to the committed build/cycc
```

## Quick Start

```sh
# Compile and run
cyrius run hello.cyr

# Create a project
cyrius init myproject
cd myproject
cyrius build src/main.cyr build/myproject

# Port a Rust project
cyrius port /path/to/rust-project

# Project sweep (format, lint, doc, test, bench)
cyrius audit
```

## Language

```cyrius
include "lib/alloc.cyr"

struct Point { x; y; }

trait Shape {
    fn area(self): i64;                               # required
    fn twice(self): i64 { return self.area() * 2; }   # a default
}

impl Shape for Point {
    fn area(self): i64 { return self.x * self.y; }
}

enum Dir { North; East; South; West; }

const STEP = 2;                                       # a compile-time constant

fn grow(p: *Point, by = STEP) {                       # a default argument
    p.x += by;
    p.y += by;
}

fn order(a, b): (i64, i64) {                          # two return values
    if (a < b) { return (a, b); }
    return (b, a);
}

fn main(): i64 {
    alloc_init();
    var p = Point { 3, 2 };
    grow(&p);                                         # { 5, 4 }
    grow(&p, by: 1);                                  # named argument: { 6, 5 }
    var lo, hi = order(p.x, p.y);                     # lo = 5, hi = 6
    var d = Dir.East;
    var wide: bool = hi > lo;
    return if (wide && d == Dir.East) { p.twice() - lo } else { 0 };   # 60 - 5 = 55
}

var r = main();
syscall(60, r);
```

The language reference is [docs/guides/cyrius-guide.md](docs/guides/cyrius-guide.md); [docs/guides/tutorial.md](docs/guides/tutorial.md) walks through it.

### Features

- Structs, enums (`Enum.VARIANT` namespacing), match, for-in, closures, function pointers, `async` / `await`
- Sum types and `match` (`Result` / `Option` / `Either` are value-form), `?` to propagate a `Result`'s error; no try / catch by design
- Generics — `fn f<T>`, `struct Box<T>`, inferred or explicit type arguments
- Traits (6.7.0): `trait` declarations with required and default methods, checked `impl Trait for T`, inherent `impl T`, trait-qualified names when two traits collide; trait bounds on generics, `fn f<T: Show + Eq>` (6.7.1). Dispatch is static
- Checked trait objects (6.7.8): `o: dyn Show` is a two-word {data, vtable} value whose vtable the compiler builds and verifies from the impl; `o.show()` is an indirect call
- `const` and `const fn` (6.7.2): a const context — a `const`'s value, an array size, `#assert`, a `case` label, an enum value — takes any constant expression, and a `const fn` called there runs at compile time (elsewhere it is an ordinary call)
- `bool` / `true` / `false` / `!` (6.7.3), with checked writes into a bool
- If-expressions (6.7.4): `var v = if (c) { a } elif (d) { b } else { e };`
- `loop { … }` and `do { … } while (c);` (6.7.5); compound assignment on every lvalue — fields, `*p`, slices — including `>>>=`
- Tuples (6.7.7): `(i64, f64)` is a type, `t.0` / `t.1` its elements; `var t: (i64, i64) = f();` keeps every value of a multi-value call
- Default and named arguments (6.7.7): `fn f(a, b = 2, c = 3)`, called `f(1, c: 9)`
- An opt-in bounds-checked mode (6.7.8): `--bounds` / `CYRIUS_BOUNDS=1` / `[build] bounds` / `#bounds` checks typed-array and slice subscripts (and a `*T` subscript for a negative index), and `@unsafe { }` opts a block out; `p[i]` subscripts a typed pointer and `*p` reads and writes at the element's width
- 20+ f64 builtins (add/sub/mul/div + sin/cos/exp/ln/log2/exp2/sqrt/abs/floor/ceil/round/trunc + atan)
- Phase O1–O6 optimizer: FNV-1a fn lookup, strength reduction, flag-result reuse, push/pop cancel, combine-shuttle elim, IR const-fold, DCE, DSE, linear-scan regalloc (default-on), NOP-harvest codebuf compaction
- Explicit overflow operators: `+%`/`-%`/`*%` (wrap), `+|`/`-|`/`*|` (saturate), `+?`/`-?`/`*?` (checked-panic)
- `>>>` arithmetic (sign-preserving) right-shift (v6.4.46; `>>` stays logical — reverse of JS/Java)
- `#derive(Serialize)` for JSON serialization, `#derive(accessors)` for field getters/setters
- `#ref "file.cyml"` directive for CYML config loading
- `#must_use`, `#deprecated("msg")`, `@unsafe` attributes
- `#else` / `#elif` / `#ifndef` / `#ifplat` preprocessor
- File-scoped visibility (v6.5.0): a bare `private` flips a file to private-by-default, `public fn` / `public var` re-exposes; a file with no declaration stays fully public
- `#@incdir <dir>` (v6.5.7) — file-relative `include` resolution, carried in-band on line 1
- Native multi-return: `return (a, b)`, `var x, y = f();` to bind, `x, y = f();` to re-assign (6.7.7)
- Switch case blocks: `case N: { ... }` with scoped variables
- Defer on all exit paths (per-defer runtime flags, unreached defers skipped)
- Str/cstr auto-coercion, compile-time string interning, `#assert`, `secret var`
- Expression-position comparisons: `var r = (a == b)` works everywhere
- Inline small functions (token replay), relaxed fn ordering
- Include-once semantics, inline assembly (`asm { }`)

### Metrics

Measured at 6.7.9 — the compilers and tools from the tagged install slot (`~/.cyrius/versions/6.7.9/bin/`), the counts from the tree. Every figure here moves; [docs/development/state.md](docs/development/state.md) carries the live ones.

| Metric | Value |
|--------|-------|
| Compiler (`cycc`) | **2,057,736 B** (~2.06 MB; `.text` 1,845,440 B) x86_64 at 6.7.9 |
| Cross compilers | `cycc_aarch64` 1,619,400 B, `cycc_win` 2,140,160 B (the PE32+ compiler), `cycc_cx` 1,521,768 B; `cycc-native-aarch64` 1,881,280 B (aarch64-native, built by `cyrius pulsar`, verified on pi) — at 6.7.9 |
| Seed binary (`asm`) | **29,024 B** (committed binary root of trust; re-derivable from `archive/seed/` via `bootstrap/verify.sh`) |
| Bootstrap compiler (`cybs`) | **21,780 B** (assembled by the seed; compiles all of `src/main.cyr`) |
| LSP server (`cyrius-lsp`) | **162,296 B** (definition / documentSymbol / references / semanticTokens / hover / diagnostics) |
| Linker (`cyrld`) | **945,672 B** |
| External dependencies | **0** at the compiler level, **0** git deps at the stdlib level (every sibling library is folded) |
| Tests | **562** .tcyr (**267** in `tests/tcyr/crossos/`, the set the release gate runs on real ecb / ach / cass / pi) + **6** .fcyr fuzz + **18** .bcyr bench (`benches/`) + 1 .scyr soak + 1 .smcyr smoke — every reader is recursive; the corpus lives in topical subfolders |
| Gates (`scripts/check.sh`) | **471** registered shell gates — **467** under `tests/gates/<bucket>/*.sh` (8 buckets: codegen, concurrency, diagnostics, frontend, ir-opt, memory, platform, toolchain) plus 4 `scripts/` gates (the QEMU kernel boot, sign-efi and agnos cross-build `*-gate.sh` and `differential-smoke.sh`), registered in `scripts/check.sh` or by path in `programs/checks/*.cyr` — plus the check driver's built-in rows. The 6.7.9 release gate ran it GREEN: 471 of 471, 0 failed, 2 named agnos-parity SKIPs. ⚠ Re-derive before quoting: `sh scripts/check.sh --registry \| wc -l` and `find tests/gates -name '*.sh' \| wc -l` |
| Architectures | x86_64 + aarch64 (cross + native), Windows PE (cross + the native PE32+ compiler), macOS Mach-O (arm64 + x86), UEFI Application emit, cyrius-x bytecode (SIMD lowered to per-lane loops) |
| Stdlib modules | **106** `lib/*.cyr` (plus the `lib/unicode/` tables; twelve folded sibling libraries among them — see *Standard Library* and [docs/stdlib-modules.md](docs/stdlib-modules.md)) |
| Public API surface | **5,835** public fns (`docs/api-surface.snapshot`, regenerated by `cyrius_api_surface`) |
| Cross-host CI | aarch64 Linux (Pi 4) + Apple Silicon macOS (ecb) + Intel macOS x86_64 Mach-O (ach) + Windows 11 PE (cass), all SSH-wired; the release gate self-hosts on each |
| Heap layout | **121** mapped regions (the `heapmap` gate's own count — shared layout 119, cx layout 114; run `sh tests/gates/memory/heapmap.sh`, never a raw `grep` over the map, which also matches `FREED` entries), at fixed offsets from the map in `src/main.cyr` (str_data at 0x21A000); the code buffer is off-heap and growable, the var / fn / fixup tables relocate off-heap as they grow, and the binary output buffer is a 1 GiB off-heap region. A program's `alloc()` (`lib/alloc.cyr`) is an anonymous-mmap **chunk** bump allocator on Linux (no `brk`, so glibc's arena cannot collide with the fdlopen / libssl bridge); `alloc_init()` is idempotent |

### Toolchain size comparison

The core Cyrius toolchain totals **11,534,408 B (~11.5 MB)**, measured at 6.7.9 in the tagged install slot, across the compiler, four cross-compilers (aarch64 / Windows PE / native-aarch64 / cx bytecode), linker, LSP, formatter, linter, doc tool, init scaffolder (which is also the port utility), and `cyrius` CLI dispatcher. The whole installed `bin/` directory is larger — **15,371,434 B** (~15.4 MB, symlinks dereferenced) — mostly the two `cyrsign*` Authenticode helpers (1,547,752 B and 1,539,056 B). Re-measure rather than re-stamp: `wc -c` over the slot's `bin/`.

For order-of-magnitude context (approximate, per typical Linux distribution package sizes):

| Toolchain | Approximate size | Notes |
|-----------|------------------|-------|
| **Cyrius** (core toolchain) | **~11.5 MB** | Compiler + linker + LSP + fmt + lint + doc + 4 cross-compilers + init + CLI |
| TCC (Tiny C Compiler, self-hosting) | ~500 KB | C compiler binary only; no LSP / linker / fmt |
| `gcc` | ~150-200 MB | Compiler + dependencies; libc not included |
| `rustc` | ~150 MB (binary) | + ~850 MB stdlib metadata |
| `clang` + LLVM | ~1-2 GB | |
| `go` (gc compiler) | ~80-100 MB | Includes stdlib |
| `zig` | ~60-150 MB | Version-dependent |

Per-binary sizes for the Cyrius single-pipeline compile path:

| Stage | Binary | Size |
|-------|--------|------|
| 1. Root of trust (source) | `bootstrap/asm` | 29 KB |
| 2. Bootstrap compiler | `cybs` | ~22 KB |
| 3. Full compiler | `cycc` | ~2.06 MB |
| 4. Linker | `cyrld` | 946 KB |

### Language surface

Source of truth: `TOKNAME_BUILTIN` + `IS_KEYWORD_TOK` in `src/common/util.cyr`. Don't re-derive these counts by grepping the lexer; two keyword paths and >8-char u64-compare names make a regex sweep under-count. `IS_KEYWORD_TOK` takes its builtin half from `TOKNAME_BUILTIN` but lists the keywords and two builtins by hand, so the two halves can drift — the table below is derived from both (at 6.7.9), not carried.

| Category | Reserved-token count | Examples |
|----------|----------------------|----------|
| Keywords (control flow, declarations, modules, visibility, types) | **30** | `if` `elif` `else` `while` `do` `for` `in` `switch` `case` `default` `match` `break` `continue` `return` `fn` `var` `const` `struct` `enum` `trait` `impl` `dyn` `mod` `use` `asm` `pub`/`public` `private` `shared` `object` `stack` |
| Boolean literals | **2** | `true` `false` |
| Memory + bit + return ops | **14** | `load8/16/32/64` `store8/16/32/64` `bitget` `bitset` `bitclr` `ret2` `rethi` `u128` |
| Other builtins | **6** | `syscall` `union` `defer` `secret` `async` `await` |
| f64 / f32 / 128-bit SIMD math intrinsics | **50** | `f64_*` (24) `f64v_*` (10) `f32_from/to` (2) `f32v_*` (5) `iv_*` (4) `f32v8_*` (5) |
| 256-bit AVX2 f64 vector intrinsics | **9** | `f64v256_add/sub/mul/div/abs/sqrt/dot/fmadd/scale` |
| Builtins `IS_KEYWORD_TOK` lists BY HAND (not in `TOKNAME_BUILTIN`) | **2** | `f64_sqrt` (token 136) `callptr` (137) |
| Identifier-spelled intrinsics — reserved names, not tokens | (11) | `sizeof` `mulh64` `fncall0` … `fncall8`: lowered by name at the call, so declaring one is refused |
| Contextual words — not reserved | — | `loop` (a keyword only as `loop {` at a statement's start), `kernel` (only as the top-level `kernel;`) |
| Preprocessor directives (`#`-prefix) | — (not lexer tokens) | `#assert` `#regalloc` `#derive` `#pe_import` `#ref` `#@incdir` `#bounds` `#define` `#ifdef` (+ `#else` / `#elif` / `#ifndef` / `#ifplat`) |

**113 total** lexer-reserved tokens (32 keyword tokens + 79 in `TOKNAME_BUILTIN` + 2 hand-listed builtins; the sets are disjoint — zero overlap), plus the 11 identifier-spelled intrinsics refused as names. C23 has 59 keywords for comparison. The math intrinsics (60 across both vector widths, `f64_sqrt` included) are exposed as keywords because they emit specific instruction sequences and dispatch per-backend (x86 SSE/AVX2, aarch64 NEON, cx bytecode per-lane loops); in C those would be `__builtin_*` or library calls.

### Caps + heap

Re-derived at 6.7.9 from the heap map in `src/main.cyr` (the authority): identifier pool / `tok_names` **8 MB** at `S + 0xEC00000`, input_buf **24 MB**, preprocess_out **24 MB**, str_data **2 MB**, token arrays **4,194,304** entries, distlib per-module 1 MB, binary output **1 GiB** off-heap on all platforms, the compiler's own `alloc()` off-heap on all platforms.

**Growable tables.** These relocate off-heap and grow on demand instead of being fixed caps: **fn tables** (grow + rehash from 2,048; **131,072** ceiling), **fixup table** (64M-entry ceiling; the cx driver keeps a fixed table), **codebuf** (an 8 MiB off-heap base growing in +8 MiB steps, 64 MiB ceiling; the cx bytecode backend keeps its own fixed 512 KB region), and the var table (1,048,576 ceiling).

## Build Tool (cyrius)

```
Build & run:             build [--aarch64|--win|--agnos] [--no-deps] [--pie] [--dce] [--bounds] [--features <list>]
                               [-D NAME]... [--print-config] [<src> [<out>]]  (default: [build] entry / output)
                         ([--strict] is accepted and passed to cycc, but has had no effect since 6.3.2: a reachable
                          undefined function is an error by default; --allow-undef downgrades it)
                         run [--bounds] <src.cyr> [args...], check, clean
Test:                    test [--bounds] [file.tcyr|dir]... (a dir is walked recursively; none: the whole suite),
                         bench, fuzz, doctest, smoke, soak [N],
                         coverage [--full] [--min <pct>] [--programs <glob>] [--per-entry] [--exec[=<glob>]]
Code quality & API:      fmt, lint, doc, vet, deny, audit [--internal[=platform-check]], api-surface, header
Project & dependencies:  init, port, update, package, publish, install
                         deps [--verify|--lock|--relock|--no-lock|--dry-run|--locked|--local[=a,b]]
                           — resolve [deps] from cyrius.cyml into lib/ + cyrius.lock (auto-runs on build)
                         lib sync [--dry-run] [--full] — vendor declared [deps].stdlib from pin
                         distlib [--all|--check] [--modular] [profile] — bundle src/ into dist/
Toolchain:               self, pulsar, capacity, which, version [--project], hooks install
                         lsp — build/install cyrius-lsp (the installer and `cyriusly setup` already ship it)
                         sign-efi <pe> <key.der> <cert.der> <out> — Authenticode-sign a PE for UEFI Secure Boot
Interactive:             repl
Help:                    help [manifest] — `cyrius --help` lists every command, `cyrius <command> --help` its flags
```

Dependencies declared in `cyrius.cyml` are auto-resolved on `build`/`run`/`test`:

```toml
[deps.mylib]
git = "https://github.com/you/mylib.git"
tag = "1.2.0"
modules = ["dist/mylib.cyr"]
```

Git comes first: every machine builds the TAG, its commit pinned in `cyrius.lock`. A `path` beside
`git` / `tag` is a development override, used only in local mode (`--local`, `CYRIUS_LOCAL=1`), and
`--locked` / `CYRIUS_LOCKED=1` checks `lib/` and the lock against the tags without writing anything.
A module is vendored as `lib/<basename>` when its file name starts with the dependency's name
(`dist/mylib.cyr` → `lib/mylib.cyr`), otherwise as `lib/<depname>_<basename>`.
Includes are auto-prepended — source files only need project-specific includes.
`cyrius help manifest` lists every `cyrius.cyml` key and what reads it.

## Standard Library (106 modules + 0 git deps)

**106 `lib/*.cyr` modules** (first-party + vendored sibling distfiles
folded byte-identical, sandhi-pattern) with **0 git deps** — no
`[deps.*]` resolution is needed for any of it. Coverage spans core data
structures, types (Option / Result), concurrency (thread / atomic / async),
networking (sovereign native TLS 1.3, HTTP/2, WebSockets), crypto, Unicode
(UAX #15 normalization), regex, GPU, and OS interop.

The twelve folded sibling libraries, at the versions `lib/` carries
(each file's `# Version:` header): sakshi 2.5.10 (tracing) · patra 1.16.3
(storage) · sigil 3.13.12 (security / crypto) · vani 1.2.10 (audio) ·
yukti 2.3.17 (hardware) · sankoch 2.8.7 (compression) · sandhi 1.13.1
(HTTP/2, JSON-RPC, TLS policy) · niyama 1.1.0 (regex) · mabda 4.2.0
(GPU / compute) · bayan 1.9.0 (data formats + big-int) · ganita 1.2.15
(linear algebra + advanced math) · yantra 1.0.11 (UI / E2E testing).
Each is opt-in with an explicit `include "lib/<name>.cyr"`;
[docs/ecosystem.md](docs/ecosystem.md) records the tag each was folded from
(`fold_table_matches_vendored` checks both against the headers).

See **[docs/stdlib-modules.md](docs/stdlib-modules.md)** for the full
categorized module index + fold-in lineage, and
**[docs/stdlib-reference.md](docs/stdlib-reference.md)** for the per-function
API reference.

## Compiler Architecture

```
src/
  main.cyr              Entry point (orchestration, passes)
  main_aarch64.cyr      aarch64 cross-compiler entry
  main_aarch64_native.cyr   Native aarch64 (Pi) entry
  main_aarch64_macho.cyr    macOS aarch64 Mach-O entry
  main_x86_macho.cyr    macOS x86_64 Mach-O entry (Intel Mac)
  main_win.cyr          Windows PE entry
  main_cx.cyr           cyrius-x bytecode entry
  version_str.cyr       Auto-generated version string

  frontend/
    lex.cyr             Lexer (+ lex_pp.cyr preprocessor: include-once, #derive, #@incdir, #bounds, #ifdef/#elif/#else/#ifndef/#ifplat)
    parse.cyr           Parser + codegen dispatch (split into parse_decl, parse_expr, parse_fn, parse_ctrl, parse_types)
    ts/                 TypeScript frontend (lex + parse + JS emit; .ts/.tsx → JS via `cycc --emit-js`)

  backend/x86/          x86_64 emission (emit/jump/fixup/decode) + float.cyr = SSE/AVX scalar-f64 + ALL SIMD emitters
  backend/aarch64/      aarch64 emission + NEON SIMD emitters (same emit/jump/fixup structure)
  backend/pe/           Windows PE/COFF container emission
  backend/macho/        macOS Mach-O container emission (arm64 + x86_64)
  backend/cx/           cyrius-x bytecode emission (scalar VM; SIMD lowers to per-lane loops)
  backend/js/           TS/TSX → JS emitter (`cycc --emit-js`)
  backend/common/       Shared runtime + token tables across backends

  common/
    util.cyr            State accessors, error functions, the reserved-word tables
    ir.cyr              IR + control-flow graph (LASE, const-fold, DCE, DSE, regalloc, NOP-harvest)
    heap_regions.cyr    Heap-region bases + caps, one copy for the native drivers (the map is in main.cyr)
    syscall_xlat.cyr    x86_64 -> aarch64 syscall-number table (generated by programs/gen_syscall_xlat.cyr)
```

### Bootstrap Chain

```
bootstrap/asm (29,024 B committed binary -- root of trust)
  -> cybs (21,780 B bootstrap compiler, assembled from bootstrap/cybs.cyr)
    -> cycc (modular compiler + IR, 2,057,736 B at 6.7.9)
      -> cycc_aarch64, cycc_win, cycc-native-aarch64, cycc_cx (cross-compilers)
```

> **Trust root, precisely:** `bootstrap/asm` is the *committed binary* root,
> backed by two distinct checks. (1) `bootstrap/verify.sh` re-derives
> `bootstrap/asm` from the archived **Rust seed** (`archive/seed/`) and checks
> byte-identity — the independent leg that makes the asm binary itself
> trustworthy; it needs rustc/cargo, so it runs **offline**, not in CI.
> (2) Given that asm binary, `scripts/seed-derive-cycc.sh` proves `build/cycc`
> descends from it with no intermediate rung: asm assembles `cybs`, `cybs`
> reproduces asm (closure) and compiles `src/main.cyr` → gen1, gen1 → gen2 ==
> `build/cycc` (self-host fixpoint, gen2 == gen3). So `cycc` is
> machine-derivable from the seed in two hops — the **closure** leg is
> validated in CI (`trust-root-attest`) and by every release gate, the
> **asm-from-Rust-source** leg offline by `verify.sh`; full trusting-trust
> resistance needs both. See [SECURITY.md](SECURITY.md).

## Editor Integration

`cyrius-lsp` ships in-tree (`cyrius lsp` to build/install). The Claude
Code wiring lives in the sibling repo
[`MacCracken/cyrius-plugins`](https://github.com/MacCracken/cyrius-plugins) —
install once and every Cyrius project on the machine picks up the LSP:

```sh
/plugin marketplace add MacCracken/cyrius-plugins
/plugin install cyrius-lsp@cyrius-plugins
```

See [docs/guides/editor-integration.md](docs/guides/editor-integration.md) for the
`.lsp.json` shape, supported extensions, capabilities, and per-editor
notes (Helix / Zed / VS Code / Neovim / JetBrains).

## Migration

`cyrius port` scaffolds Cyrius projects from Rust repos. Moving an existing project to a newer cyrius: [ecosystem migration](docs/development/ecosystem-migration.md).

## Development

Setting up a dev / verification environment? Install the **per-environment toolchain** first so cross-target work doesn't stall on a missing tool:

- [docs/development/dev-tools-linux.md](docs/development/dev-tools-linux.md) — x86_64 Linux dev/verification box: build + cross-emit every target, run the aarch64/PE binaries locally (qemu/wine) to reproduce platform self-host bugs without round-tripping to hardware, disassemble (llvm-objdump), and SSH to the real hosts for authoritative verification. macOS/Windows siblings to follow.

```bash
sh bootstrap/bootstrap.sh                                          # seed asm → cybs (+ closure check)
sh scripts/seed-derive-cycc.sh                                     # seed → cybs → cycc == build/cycc
cat src/main.cyr | build/cycc > /tmp/cycc && chmod +x /tmp/cycc
cat src/main.cyr | /tmp/cycc > /tmp/cc5b && cmp /tmp/cycc /tmp/cc5b # self-host byte-identical
sh scripts/check.sh                                                # full Linux audit
sh scripts/cross-os-selfhost.sh ecb                                # real-hardware self-host (per host: ecb/ach/pi/cass)
```

## See also

- [docs/guides/cyrius-guide.md](docs/guides/cyrius-guide.md) — the language reference; [docs/guides/faq.md](docs/guides/faq.md) — common questions
- [docs/stdlib-reference.md](docs/stdlib-reference.md) — the per-function stdlib reference
- [docs/platform-status.md](docs/platform-status.md) — what works on which platform today (refreshed every closeout)
- [docs/benchmarks.md](docs/benchmarks.md) — where the benchmark numbers live; [docs/size-comparisons.md](docs/size-comparisons.md) — binary sizes against C / Rust / Go / Zig
- [docs/ecosystem.md](docs/ecosystem.md) — downstream consumer repos + folded distlibs + live deps (refreshed every closeout)
- [docs/development/roadmap.md](docs/development/roadmap.md) — release plan + pinned slots + long-term considerations
- [docs/development/state.md](docs/development/state.md) — current version, cycc size, in-flight slots
- [docs/development/completed-phases.md](docs/development/completed-phases.md) — historical release narrative

## License

GPL-3.0-only
