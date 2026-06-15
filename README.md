# Cyrius

**Sovereign, self-hosting systems language. Assembly up.**

A self-hosting compiler toolchain that bootstraps from a 29 KB binary with zero external dependencies. No Rust, no LLVM, no Python, no libc. Writes the [AGNOS](https://github.com/MacCracken/agnos) kernel, its own package manager, its own build tool, and (as of v5.11.49) bootable UEFI applications.

~1.05 MB compiler. Self-hosting on x86_64 + aarch64 (cross + native), Windows PE cross (directory-listing available since v6.1.18), macOS Mach-O (arm64 + x86), UEFI Application emit (gnoboot bootloader unblocked at v5.11.49), cyrius-x bytecode. Position-independent (PIE) codegen on x86_64 + aarch64 (`--pie`), `.gnu.hash` dynamic linking, and a TS/TSX → JS emitter (`cycc --emit-js`). Sovereign native TLS 1.3 — client + server, sigil-backed X.509 chain verification, no OpenSSL — is the **default** TLS backend since v6.1.21 (`-D CYRIUS_TLS_LIBSSL` opts back to the libssl bridge). 95 stdlib modules + 0 git deps (folded sibling distfiles: sakshi / patra / sigil / vani / yukti / sankoch at v5.8.65; niyama at v5.9.0; mabda 3.0.1; **bayan 1.0.0 at v6.1.25** — data formats & big-int into `lib/bayan.cyr`; **ganita 1.0.0 at v6.1.26** — linear algebra + advanced math: matrix / linalg / transcendental into `lib/ganita.cyr`). 176 .tcyr + 1 soak + 1 smoke + 5 fuzz + 15 bench, 89 check.sh gates.

## Install

```sh
curl -sSf https://raw.githubusercontent.com/MacCracken/cyrius/main/scripts/install.sh | sh
```

Or build from source:

```sh
sh bootstrap/bootstrap.sh
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

# Full audit (format, lint, vet, deny, test, bench, doc)
cyrius audit
```

## Language

```cyrius
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"

struct Point { x; y; }

impl Math for Point {
    fn sum(self) { return load64(self) + load64(self + 8); }
}

fn Point_add(a, b) {
    store64(a, load64(a) + load64(b));
    store64(a + 8, load64(a + 8) + load64(b + 8));
    return a;
}

enum Result { Ok(val) = 0; Err(code) = 1; }

fn main() {
    alloc_init();
    var a = Point { 1, 2 };
    var b = Point { 3, 4 };
    Point_add(&a, &b);
    return Point_sum(&a);
}

var r = main();
syscall(60, r);
```

### Features

- Structs, enums (`Enum.VARIANT` namespacing), match, for-in, closures, impl blocks
- 20+ f64 builtins (add/sub/mul/div + sin/cos/exp/ln/log2/exp2/sqrt/abs/floor/ceil + atan)
- Phase O1–O6 optimizer: FNV-1a fn lookup, strength reduction, flag-result reuse, push/pop cancel, combine-shuttle elim, IR const-fold, DCE, DSE, linear-scan regalloc (default-on), NOP-harvest codebuf compaction
- Explicit overflow operators: `+%`/`-%`/`*%` (wrap), `+|`/`-|`/`*|` (saturate), `+?`/`-?`/`*?` (checked-panic)
- `#derive(Serialize)` for JSON serialization, `#derive(accessors)` for field getters/setters
- `#ref "file.cyml"` directive for CYML config loading
- `#must_use`, `#deprecated("msg")`, `@unsafe` attributes
- `#else` / `#elif` / `#ifndef` / `#ifplat` preprocessor
- Native multi-return: `return (a, b)` + `var x, y = fn()` destructuring
- Switch case blocks: `case N: { ... }` with scoped variables
- Defer on all exit paths (per-defer runtime flags, unreached defers skipped)
- Str/cstr auto-coercion, compile-time string interning, `#assert`, `secret var`
- Expression-position comparisons: `var r = (a == b)` works everywhere
- Inline small functions (token replay), relaxed fn ordering
- Include-once semantics, inline assembly (`asm { }`)

### Metrics

| Metric | Value |
|--------|-------|
| Compiler (`cycc`) | **1,063,800 B** (~1.06 MB) x86_64 at v6.2.5 |
| Cross compilers | `cycc_aarch64` 615,304 B, `cycc_win` 836,096 B (cross-built) |
| Seed binary (`asm`) | **29,016 B** (root of trust, committed to repo) |
| Bootstrap compiler (`cybs`) | **12,344 B** |
| LSP server (`cyrius-lsp`) | **531,688 B** (definition / documentSymbol / references / semanticTokens / hover) |
| Linker (`cyrld`) | **902,184 B** |
| External dependencies | **0** at the compiler level (0 git deps at stdlib level: mabda folded at 3.0.1) |
| Tests | **176** .tcyr + **5** .fcyr fuzz + **15** .bcyr bench + 1 .scyr soak + 1 .smcyr smoke |
| Gates (`scripts/check.sh`) | **89** structural + runtime gates (incl. OVMF UEFI boot smoke at v5.11.49, CVE-05 mangle guard at v5.11.65, PIE exec gate at v6.1.6, TS→JS emit/round-trip gate at v6.1.11) |
| Architectures | x86_64 + aarch64 (cross + native), Windows PE cross, macOS Mach-O (arm64 + x86), UEFI Application emit, cyrius-x bytecode |
| Stdlib modules | **95** (distfiles folded byte-identical; bayan 1.0.0 @ v6.1.25 → `lib/bayan.cyr`, ganita 1.0.0 @ v6.1.26 → `lib/ganita.cyr`, `lib/sys.cyr` system-introspection @ v6.1.28; see [docs/stdlib-modules.md](docs/stdlib-modules.md)) |
| Cross-host CI | aarch64 Linux (Pi 4) + Apple Silicon macOS + Windows 11 PE, all SSH-wired |
| Heap layout | 99 regions, monotonic post-v5.11.68 full reorg (str_data at 0x21A000, codebuf at 0x41A000); backed by an anonymous-mmap **chunk** bump allocator since v6.1.19 (was `brk`-backed — switched so glibc's `brk` arena can't collide with the fdlopen/libssl bridge), `alloc_init()` idempotent since v6.1.23 |

### Toolchain size comparison

Full Cyrius release toolchain (`~/.cyrius/bin/`) totals **~5.4 MB** across the compiler, three cross-compilers (aarch64 / Windows PE / native-aarch64), linker, LSP, formatter, linter, doc tool, init scaffolder, port utility, and `cyrius` CLI dispatcher.

For order-of-magnitude context (approximate, per typical Linux distribution package sizes):

| Toolchain | Approximate size | Notes |
|-----------|------------------|-------|
| **Cyrius** (full release toolchain) | **~5.4 MB** | Compiler + linker + LSP + fmt + lint + doc + 3 cross-compilers + CLI |
| TCC (Tiny C Compiler, self-hosting) | ~500 KB | C compiler binary only; no LSP / linker / fmt |
| `gcc` | ~150-200 MB | Compiler + dependencies; libc not included |
| `rustc` | ~150 MB (binary) | + ~850 MB stdlib metadata |
| `clang` + LLVM | ~1-2 GB | |
| `go` (gc compiler) | ~80-100 MB | Includes stdlib |
| `zig` | ~60-150 MB | Version-dependent |

Per-binary sizes for the Cyrius single-pipeline compile path:

| Stage | Binary | Size |
|-------|--------|------|
| 1. Root of trust (committed) | `bootstrap/asm` | 29 KB |
| 2. Bootstrap compiler | `cybs` | 12 KB |
| 3. Full compiler | `cycc` | 1.0 MB |
| 4. Linker | `cyrld` | 902 KB |

### Language surface

| Category | Reserved-token count | Examples |
|----------|----------------------|----------|
| Core syntactic (control flow, decl, modules) | **~28** | `if` `fn` `var` `for` `else` `elif` `while` `break` `continue` `match` `case` `default` `return` `enum` `struct` `union` `impl` `mod` `pub` `use` `asm` `syscall` `shared` `object` `defer` `stack` `secret` `in` |
| Memory + bit + return ops | **~14** | `load8/16/32/64` `store8/16/32/64` `bitget` `bitset` `bitclr` `ret2` `rethi` `u128` |
| f64 / SIMD math intrinsics | **~32** | `f64_add/sub/mul/div/neg/abs` `f64_sin/cos/exp/ln/sqrt/atan` `f64_to/from` `f64_eq/lt/gt` `f64_ceil/floor/round` `f64_log2/exp2` `f64v_add/sub/mul/div/abs/sqrt/dot/axpy/fmadd/scale` |
| Preprocessor directives (`#`-prefix) | **~5** | `#assert` `#regalloc` `#derive` `#pe_import` `#ifdef` (+ `#else` / `#elif` / `#ifndef` / `#ifplat`) |

**~74 total** lexer-reserved tokens. C23 has 59 keywords for comparison. The math intrinsics (~32) are exposed as keywords because they emit specific instruction sequences and dispatch per-backend (x86 SSE, aarch64 NEON V0, cx bytecode); in C those would be `__builtin_*` or library calls.

### Caps + heap

ident buffer 256 KB (v5.11.18; was 128 KB), input_buf 1 MB (v5.7.10), str_data 2 MB (v5.8.59), token arrays 1M-entry (v5.8.46), distlib per-module 256 KB (v5.7.36), preprocess buf 8 MB (v5.11.33), binary output_buf 16 MB (v6.1.27; was 2 MB — relocated to heap-top).

**Growable as of v6.2.0 (Phase 0).** The three former pressure tables are no longer fixed caps — they relocate off-heap and double on demand, ending the cap-raise treadmill: **fn-tables** (was 8192-fn fixed → grow+rehash, 32768 ceiling), **fixup table** (was 1M fixed → grow, 64M-entry ceiling), **codebuf** (was 3 MB fixed → grow, 64 MiB ceiling; the cx bytecode backend keeps its own 512 KB region).

## Build Tool (cyrius)

```
Build:     build [-v] [--aarch64] [-D NAME], run, test, bench, check, self, clean
Deps:      deps — resolve [deps] from cyrius.cyml into lib/ (auto-runs on build)
Project:   init, package, publish, install, update, port
Quality:   audit, fmt, lint, doc, vet, deny, distlib, capacity
Testing:   coverage, doctest, soak [N], smoke
LSP:       lsp — build/install cyrius-lsp (also auto-installed via cyriusly setup)
Info:      version, which, help
```

Dependencies declared in `cyrius.cyml` are auto-resolved on `build`/`run`/`test`:

```toml
[deps.mabda]
git = "https://github.com/MacCracken/mabda.git"
tag = "2.5.0"
modules = ["dist/mabda.cyr"]
```

Named deps are namespaced: `lib/{depname}_{basename}` (e.g. `lib/mabda_types.cyr`).
Includes are auto-prepended — source files only need project-specific includes.

## Standard Library (95 modules + 0 git deps)

**95 `lib/*.cyr` modules** (first-party + vendored sibling distfiles
folded byte-identical, sandhi-pattern) with **0 git deps** — mabda folded
at 3.0.1, dropping its transitive `agnosys` and leaving zero `[deps.*]`
resolutions. Coverage spans core data structures, types (Option / Result),
concurrency (thread / atomic / async), networking (sovereign native TLS 1.3,
HTTP/2, WebSockets), crypto, Unicode (UAX #15 normalization), regex, GPU,
and OS interop.

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
  main_win.cyr          Windows PE entry
  main_cx.cyr           cyrius-x bytecode entry
  version_str.cyr       Auto-generated version string

  frontend/
    lex.cyr             Lexer + preprocessor (include-once, #derive, #ifdef/#elif/#else/#ifndef/#ifplat)
    parse.cyr           Parser + codegen dispatch (split into parse_decl, parse_expr, parse_fn, parse_ctrl, ...)
    ts/                 TypeScript frontend (lex + parse + JS emit; .ts/.tsx → JS via `cycc --emit-js`)

  backend/x86/          x86_64 instruction emission, jump, fixup, ELF/PE/Mach-O
  backend/aarch64/      aarch64 emission (same structure)
  backend/cx/           cyrius-x bytecode emission

  common/
    util.cyr            State accessors, error functions
    ir.cyr              IR + control-flow graph (LASE, const-fold, DCE, DSE, regalloc, NOP-harvest)
```

### Bootstrap Chain

```
bootstrap/asm (29,016 B committed binary -- root of trust)
  -> cybs (12,344 B compiler)
    -> cycc (modular compiler + IR, 1,063,800 B at v6.2.5)
      -> cycc_aarch64, cycc_win_cross, cycc_macho, cycc_cx (cross-compilers)
```

> The chain shortened at v5.11.66 — `src/bridge.cyr` (2,005 LoC standalone
> Phase 4 compiler) retired after audit confirmed it was never in any
> active build path. CLAUDE.md's Key Principle wording updated from
> "seed → cybs → bridge → cycc" to "seed → cybs → cycc" the same release.

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
notes (Helix / Zed / VS Code / JetBrains).

## Migration

`cyrius port` scaffolds Cyrius projects from Rust repos. See [migration strategy](docs/development/migration-strategy.md) for the porting playbook.

## Development

Setting up a dev / verification environment? Install the **per-environment toolchain** first so cross-target work doesn't stall on a missing tool:

- [docs/development/dev-tools-linux.md](docs/development/dev-tools-linux.md) — x86_64 Linux dev/verification box: build + cross-emit every target, run the aarch64/PE binaries locally (qemu/wine) to reproduce platform self-host bugs without round-tripping to hardware, disassemble (llvm-objdump), and SSH to the real hosts for authoritative verification. macOS/Windows siblings to follow.

```bash
sh bootstrap/bootstrap.sh                                          # seed asm → cybs → cycc
cat src/main.cyr | build/cycc > /tmp/cycc && chmod +x /tmp/cycc
cat src/main.cyr | /tmp/cycc > /tmp/cc5b && cmp /tmp/cycc /tmp/cc5b # self-host byte-identical
sh scripts/check.sh                                                # full Linux audit
sh scripts/cross-os-selfhost.sh ecb                                # real-hardware self-host (per host: ecb/ach/pi/cass)
```

## See also

- [docs/platform-status.md](docs/platform-status.md) — what works on which platform today (refreshed every closeout)
- [docs/ecosystem.md](docs/ecosystem.md) — downstream consumer repos + folded distlibs + live deps (refreshed every closeout)
- [docs/development/roadmap.md](docs/development/roadmap.md) — release plan + pinned slots + long-term considerations
- [docs/development/state.md](docs/development/state.md) — current version, cycc size, in-flight slots
- [docs/development/completed-phases.md](docs/development/completed-phases.md) — historical release narrative

## License

GPL-3.0-only
