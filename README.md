# Cyrius

**Sovereign, self-hosting systems language. Assembly up.**

A self-hosting compiler toolchain that bootstraps from a 29 KB binary with zero external dependencies. No Rust, no LLVM, no Python, no libc. Writes the [AGNOS](https://github.com/MacCracken/agnos) kernel, its own package manager, its own build tool, and (as of v5.11.49) bootable UEFI applications.

~1.05 MB compiler. Self-hosting on x86_64 + aarch64 (cross + native), Windows PE cross (directory-listing available since v6.1.18), macOS Mach-O (arm64 + x86), UEFI Application emit (gnoboot bootloader unblocked at v5.11.49), cyrius-x bytecode. Position-independent (PIE) codegen on x86_64 + aarch64 (`--pie`), `.gnu.hash` dynamic linking, and a TS/TSX → JS emitter (`cycc --emit-js`). 94 stdlib modules + 0 git deps (mabda folded into stdlib at 3.0.1; 7 sibling distfiles folded into stdlib — sakshi / patra / sigil / vani / yukti / sankoch at v5.8.65; niyama at v5.9.0). 170 .tcyr + 1 soak + 1 smoke + 5 fuzz + 15 bench, 87 check.sh gates.

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
| Compiler (`cycc`) | **1,045,120 B** (~1.05 MB) x86_64 at v6.1.18 |
| Cross compilers | `cycc_aarch64` 594,848 B, `cycc_win` 814,592 B (cross-built) |
| Seed binary (`asm`) | **29,016 B** (root of trust, committed to repo) |
| Bootstrap compiler (`cybs`) | **12,344 B** |
| LSP server (`cyrius-lsp`) | **101,392 B** |
| Linker (`cyrld`) | **902,184 B** |
| External dependencies | **0** at the compiler level (0 git deps at stdlib level: mabda folded at 3.0.1) |
| Tests | **170** .tcyr + **5** .fcyr fuzz + **15** .bcyr bench + 1 .scyr soak + 1 .smcyr smoke |
| Gates (`scripts/check.sh`) | **87** structural + runtime gates (incl. OVMF UEFI boot smoke at v5.11.49, CVE-05 mangle guard at v5.11.65, PIE exec gate at v6.1.6, TS→JS emit/round-trip gate at v6.1.11) |
| Architectures | x86_64 + aarch64 (cross + native), Windows PE cross, macOS Mach-O (arm64 + x86), UEFI Application emit, cyrius-x bytecode |
| Stdlib modules | **94** (7 distfiles folded byte-identical from sibling repos; see lineage below) |
| Cross-host CI | aarch64 Linux (Pi 4) + Apple Silicon macOS + Windows 11 PE, all SSH-wired |
| Heap layout | 99 regions, monotonic post-v5.11.68 full reorg (str_data at 0x21A000, codebuf at 0x41A000), brk-final at 0x4D9D000 (~77.6 MB) |

### Toolchain size comparison

Full Cyrius release toolchain (`~/.cyrius/bin/`) totals **3.72 MB** across the compiler, cross-compilers, linker, LSP, formatter, linter, doc tool, init scaffolder, port utility, and `cyrius` CLI dispatcher.

For order-of-magnitude context (approximate, per typical Linux distribution package sizes):

| Toolchain | Approximate size | Notes |
|-----------|------------------|-------|
| **Cyrius** (full release toolchain) | **~3.7 MB** | Compiler + linker + LSP + fmt + lint + doc + cross-compilers + CLI |
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

ident buffer 256 KB (v5.11.18; was 128 KB), fn table 8192 (v5.11.19; was 4096), fixup table 1M (v5.7.7), input_buf 1 MB (v5.7.10), str_data 2 MB (v5.8.59), token arrays 1M-entry (v5.8.46), distlib per-module 256 KB (v5.7.36), aarch64 codebuf 3 MB (v5.7.34), preprocess buf 8 MB (v5.11.33).

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

## Standard Library (94 modules + 0 git deps)

Sibling-distfile **fold-in lineage** (sandhi-pattern: byte-identical
vendor at the patched tag, removed from `[deps]`):

- v5.7.0 — `sandhi` (HTTP/2 + JSON-RPC + service discovery + TLS policy, ~10,500 lines)
- v5.8.0 — `vani` (audio distlib; replaced inlined `lib/audio.cyr`)
- **v5.8.65 stdlib foldin** — sakshi 2.2.3 (tracing), patra 1.9.3 (storage), sigil 3.0.1 (security), yukti 2.2.2 (hardware enumeration), sankoch 2.2.4 (compression), and re-folded vani at 0.9.2
- **v5.9.0** — niyama 1.0.1 (regex; 5 engines: bre / re2 / pcre / fuzzy / vim; ~6,664 lines)

Mabda (GPU integration) folded into stdlib at 3.0.1 (v6.0.x,
sandhi-pattern), removed from `[deps]`; with mabda vendored its
transitive `agnosys` is no longer pulled, leaving zero `[deps.*]`
git resolutions. v5.7.35 added `lib/random.cyr` (kernel entropy via
getrandom) and `lib/security.cyr` (Landlock policy enums) as new
first-party modules. v5.8.49–.52 + .60 added the
`lib/unicode/` family (categories / casefold / NFC / NFD / NFKC
/ NFKD per UAX #15 against Unicode 17.0.0). The compat-decomp
data uses a 2-table IDX+DATA encoding (~87 KB total — 80%
smaller than fixed-width would have been; per the v5.8.60 mid-
slot redesign).

| Category | Modules |
|----------|---------|
| Core | string, fmt, alloc, io, vec, str, args, fnptr, flags |
| Types | tagged (Option), result (Result + ? operator; v5.8.28-.32), hashmap, hashmap_fast, trait, assert, bounds |
| System | syscalls, callback, process, bench |
| Concurrency | thread (clone+mmap, mutex, MPSC), thread_local, atomic, async, freelist |
| Data | json, toml, cyml, csv, base64, regex, math, matrix, linalg, bigint, u128 |
| Unicode | unicode/categories, unicode/casefold, unicode/normalize (NFC/NFD/NFKC/NFKD), unicode/_decode |
| Crypto | sha1, keccak, ct (constant-time primitives), overflow, **random** (kernel entropy via getrandom) |
| Sandboxing | **security** (Landlock policy enums; v5.7.35) |
| Network | net, http, ws, ws_server, tls, **sandhi** (HTTP/2 + RPC; folded v5.7.0) |
| Regex | **niyama** (5 engines: bre / re2 / pcre / fuzzy / vim; folded v5.9.0) |
| Filesystem | fs |
| Audio | **vani** (ALSA PCM + ring buffer + mixer; folded v5.8.0, refolded v5.8.65) |
| Logging | log (structured, over sakshi) |
| Time | chrono |
| Interop | mmap, dynlib, fdlopen (foreign-dlopen), cffi |
| Identity | pwd, grp, shadow, pam |
| Tracing | **sakshi** (folded v5.8.65) |
| Database | **patra** (folded v5.8.65) |
| Security | **sigil** (folded v5.8.65) |
| Hardware | **yukti** (folded v5.8.65) |
| Compression | **sankoch** (folded v5.8.65) |
| GPU | **mabda** (folded v6.0.x at 3.0.1; opt-in `include "lib/mabda.cyr"`) |

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
    -> cycc (modular compiler + IR, 1,045,120 B at v6.1.18)
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
