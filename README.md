# Cyrius

**Sovereign, self-hosting systems language. Assembly up.**
 
A self-hosting compiler toolchain that bootstraps from a 29 KB binary with zero external dependencies. No Rust, no LLVM, no Python, no libc. Writes the [AGNOS](https://github.com/MacCracken/agnos) kernel, its own package manager, its own build tool, and (as of v5.11.49) bootable UEFI applications.

~1.09 MB compiler. Self-hosting on x86_64 + aarch64 (cross + native), Windows PE cross (directory-listing available since v6.1.18), macOS Mach-O (arm64 + x86), UEFI Application emit (gnoboot bootloader unblocked at v5.11.49), cyrius-x bytecode. Position-independent (PIE) codegen on x86_64 + aarch64 (`--pie`), `.gnu.hash` dynamic linking, **W^X** userland ELF by default since v6.3.12 (separate `R E` / `RW ` `PT_LOAD` segments; `CYRIUS_WX=0` opts back to the historical single `RWE`), and a TS/TSX → JS emitter (`cycc --emit-js`). Packed-SIMD compute (v6.4.x, Phase 5 complete) — f32/f64/integer 128-bit + **256-bit AVX2** f32v8 (elementwise + FMA + horizontal dot) with CPUID runtime dispatch — complete on all four backends: x86 (SSE + AVX2), aarch64 NEON (v6.4.28–.30), Windows PE value-form params + returns (v6.4.31), and cx bytecode per-lane scalar loops (v6.4.32). Sovereign native TLS 1.3 — client + server, sigil-backed X.509 chain verification, no OpenSSL — is the **default** TLS backend since v6.1.21 (`-D CYRIUS_TLS_LIBSSL` opts back to the libssl bridge). 99 stdlib modules + 0 git deps (folded sibling distfiles: sakshi 2.4.8 / patra 1.12.12 / sigil 3.12.2 / vani 1.1.3 / yukti 2.3.2 / sankoch 2.7.6 / sandhi 1.9.9 / niyama 1.0.6; mabda 4.0.8; **bayan 1.4.1** — data formats & big-int into `lib/bayan.cyr`; **ganita 1.0.4** — linear algebra + advanced math: matrix / linalg / transcendental into `lib/ganita.cyr`; **yantra 1.0.2** — UI/E2E testing into `lib/yantra.cyr`). 260 .tcyr + 1 soak + 1 smoke + 6 fuzz + 18 bench, 162 check.sh gates + QEMU boot gate.

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
- `>>>` arithmetic (sign-preserving) right-shift (v6.4.46; `>>` stays logical — reverse of JS/Java)
- `#derive(Serialize)` for JSON serialization, `#derive(accessors)` for field getters/setters
- `#ref "file.cyml"` directive for CYML config loading
- `#must_use`, `#deprecated("msg")`, `@unsafe` attributes
- `#else` / `#elif` / `#ifndef` / `#ifplat` preprocessor
- File-scoped visibility (v6.5.0): a bare `private` flips a file to private-by-default, `public fn` / `public var` re-exposes; a file with no declaration stays fully public
- `#@incdir <dir>` (v6.5.7) — file-relative `include` resolution, carried in-band on line 1
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
| Compiler (`cycc`) | **1,141,792 B** (~1.09 MB) x86_64 at v6.5.10 |
| Cross compilers | `cycc_aarch64` 685,312 B, `cycc_win` 1,021,440 B, `cycc_cx` 606,104 B (cross-built); `cycc-native-aarch64` 940,536 B (aarch64-native, pi-verified) |
| Seed binary (`asm`) | **29,024 B** (committed binary root of trust; re-derivable from `archive/seed/` via `bootstrap/verify.sh`) |
| Bootstrap compiler (`cybs`) | **12,344 B** (compiles all of `src/main.cyr`) |
| LSP server (`cyrius-lsp`) | **115,488 B** (definition / documentSymbol / references / semanticTokens / hover) |
| Linker (`cyrld`) | **915,488 B** |
| External dependencies | **0** at the compiler level (0 git deps at stdlib level: mabda folded, now 4.0.8) |
| Tests | **260** .tcyr + **6** .fcyr fuzz + **18** .bcyr bench + 1 .scyr soak + 1 .smcyr smoke |
| Gates (`scripts/check.sh`) | **162** structural + runtime gates (162 passed / 0 failed at v6.5.10) + QEMU kernel boot gate. **41** of them are shell gates under `tests/*.sh` — 31 registered by exact path in `programs/checks/main.cyr`, the rest reached through named gate fns (`_heapmap_gate`, …); all 41 are live. (Incl. PIE exec gate at v6.1.6, QEMU kernel boot gate at v6.2.28, deps-resolver gates `_deps_requires`/`_deps_sidecar`/`_deps_groups`/`_deps_modular` @ v6.2.46–.50, CVE-32 modular-traversal gate @ v6.2.51, the 8300-var `_var_grow_gate` @ v6.3.0, the lever-2 `_deps_features_gate` @ v6.3.1.) |
| Architectures | x86_64 + aarch64 (cross + native), Windows PE cross, macOS Mach-O (arm64 + x86), UEFI Application emit, cyrius-x bytecode (with SIMD codegen since v6.4.32) |
| Stdlib modules | **99** (distfiles folded byte-identical; bayan 1.4.1 → `lib/bayan.cyr`, ganita 1.0.4 → `lib/ganita.cyr`, `lib/sys.cyr` system-introspection @ v6.1.28; see [docs/stdlib-modules.md](docs/stdlib-modules.md)) |
| Public API surface | **4,817** public fns (`docs/api-surface.snapshot`, regenerated by `cyrius_api_surface`) |
| Cross-host CI | aarch64 Linux (Pi 4) + Apple Silicon macOS (ecb) + Intel macOS x86_64 Mach-O (ach, first-class release-gate host since v6.4.59) + Windows 11 PE, all SSH-wired |
| Heap layout | 100 regions, monotonic post-v5.11.68 full reorg (str_data at 0x21A000, codebuf at 0x41A000); the var-family + fn/fixup/codebuf tables are growable (relocatable bases) as of the v6.2.0/v6.3.0 Phase-0 migration; backed by an anonymous-mmap **chunk** bump allocator since v6.1.19 (was `brk`-backed — switched so glibc's `brk` arena can't collide with the fdlopen/libssl bridge), `alloc_init()` idempotent since v6.1.23 |

### Toolchain size comparison

The core Cyrius toolchain totals **6,385,008 B (~6.1 MB)** measured at v6.5.10 across the compiler, four cross-compilers (aarch64 / Windows PE / native-aarch64 / cx bytecode), linker, LSP, formatter, linter, doc tool, init scaffolder (which is also the port utility), and `cyrius` CLI dispatcher. The installed `~/.cyrius/bin/` directory is larger — 35,138,369 B — because the two `cyrsign*` Authenticode helpers are ~14 MB each on disk.

For order-of-magnitude context (approximate, per typical Linux distribution package sizes):

| Toolchain | Approximate size | Notes |
|-----------|------------------|-------|
| **Cyrius** (core toolchain) | **~6.1 MB** | Compiler + linker + LSP + fmt + lint + doc + 4 cross-compilers + init + CLI |
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
| 2. Bootstrap compiler | `cybs` | ~12 KB |
| 3. Full compiler | `cycc` | ~1.09 MB |
| 4. Linker | `cyrld` | 915 KB |

### Language surface

Source of truth: `TOKNAME_BUILTIN` + `IS_KEYWORD_TOK` in `src/common/util.cyr` — `IS_KEYWORD_TOK` *derives* from `TOKNAME_BUILTIN`, so the "is it reserved?" and "what is it called?" sets cannot drift. Don't re-derive these counts by grepping the lexer; two keyword paths and >8-char u64-compare names make a regex sweep under-count.

| Category | Reserved-token count | Examples |
|----------|----------------------|----------|
| Statement keywords (control flow, decl, modules, visibility) | **26** | `if` `while` `else` `elif` `for` `switch` `case` `default` `break` `continue` `return` `fn` `var` `struct` `enum` `impl` `mod` `use` `match` `in` `asm` `pub`/`public` `private` `shared` `object` `stack` |
| Memory + bit + return ops | **14** | `load8/16/32/64` `store8/16/32/64` `bitget` `bitset` `bitclr` `ret2` `rethi` `u128` |
| Other builtins | **6** | `syscall` `union` `defer` `secret` `async` `await` |
| f64 / f32 / SIMD math intrinsics | **47** | `f64_*` (21) `f64v_*` (10) `f32_from/to` (2) `f32v_*` (5) `iv_*` (4) `f32v8_*` (5) |
| Preprocessor directives (`#`-prefix) | — (not lexer tokens) | `#assert` `#regalloc` `#derive` `#pe_import` `#ref` `#@incdir` `#ifdef` (+ `#else` / `#elif` / `#ifndef` / `#ifplat`) |

**93 total** lexer-reserved tokens (26 statement keywords + 67 in `TOKNAME_BUILTIN`). C23 has 59 keywords for comparison. The math intrinsics (47) are exposed as keywords because they emit specific instruction sequences and dispatch per-backend (x86 SSE/AVX2, aarch64 NEON, cx bytecode per-lane loops); in C those would be `__builtin_*` or library calls.

### Caps + heap

ident buffer / `tok_names` 512 KB (v6.4.76; 128 KB → 256 KB at v5.11.18 → 512 KB — the pool END must stay ≤ 0x100000), input_buf 1 MB (v5.7.10), str_data 2 MB (v5.8.59), token arrays 1M-entry (v5.8.46), distlib per-module 1 MB (v6.4.10; was 256 KB at v5.7.36, matching cycc's own input_buf), preprocess buf 8 MB (v5.11.33), binary output_buf 1 GiB, off-heap `alloc()` on all platforms (v6.4.52; the 16 MB heap-top region it replaced is retired).

**Growable as of v6.2.0 (Phase 0).** The three former pressure tables are no longer fixed caps — they relocate off-heap and double on demand, ending the cap-raise treadmill: **fn-tables** (was 8192-fn fixed → grow+rehash, 32768 ceiling), **fixup table** (was 1M fixed → grow, 64M-entry ceiling), **codebuf** (was 3 MB fixed → grow, 64 MiB ceiling; the cx bytecode backend keeps its own 512 KB region).

## Build Tool (cyrius)

```
Build:     build [--aarch64|--win|--agnos] [--no-deps] [--strict] [--features <list>],
           run, test, tests [dir], bench, check, self, clean
           distlib [--all|--check] [--modular] [profile] — bundle src/ into dist/
           lib sync [--dry-run] [--full] — vendor declared [deps].stdlib from pin
Deps:      deps [--no-lock|--verify] — resolve [deps] from cyrius.cyml into lib/ (auto-runs on build)
Project:   init, package, publish, install, update, port
Quality:   audit [--internal[=platform-check]], fuzz, fmt, lint, doc, vet, deny, capacity
Testing:   coverage [--full] [--min <pct>], doctest, soak [N], smoke
Signing:   sign-efi <pe> <key.der> <cert.der> <out> — Authenticode-sign a PE for UEFI Secure Boot (v6.4.47)
LSP:       lsp — build/install cyrius-lsp (also auto-installed via cyriusly setup)
Info:      version [--project], which, repl, hooks install, help
```

Dependencies declared in `cyrius.cyml` are auto-resolved on `build`/`run`/`test`:

```toml
[deps.mabda]
git = "https://github.com/MacCracken/mabda.git"
tag = "4.0.8"
modules = ["dist/mabda.cyr"]
```

Named deps are namespaced: `lib/{depname}_{basename}` (e.g. `lib/mabda_types.cyr`).
Includes are auto-prepended — source files only need project-specific includes.

## Standard Library (99 modules + 0 git deps)

**99 `lib/*.cyr` modules** (first-party + vendored sibling distfiles
folded byte-identical, sandhi-pattern) with **0 git deps** — mabda folded
at 4.0.8, dropping its transitive `agnosys` and leaving zero `[deps.*]`
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
  main_x86_macho.cyr    macOS x86_64 Mach-O entry (Intel Mac)
  main_win.cyr          Windows PE entry
  main_cx.cyr           cyrius-x bytecode entry
  version_str.cyr       Auto-generated version string

  frontend/
    lex.cyr             Lexer (+ lex_pp.cyr preprocessor: include-once, #derive, #@incdir, #ifdef/#elif/#else/#ifndef/#ifplat)
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
    util.cyr            State accessors, error functions
    ir.cyr              IR + control-flow graph (LASE, const-fold, DCE, DSE, regalloc, NOP-harvest)
```

### Bootstrap Chain

```
bootstrap/asm (29,024 B committed binary -- root of trust)
  -> cybs (12,344 B compiler)
    -> cycc (modular compiler + IR, 1,141,792 B at v6.5.10)
      -> cycc_aarch64, cycc_win, cycc-native-aarch64, cycc_cx (cross-compilers)
```

> **Trust root, precisely (CVE-20 — resolved 2026-06-20):** `bootstrap/asm` is
> the *committed binary* root, backed by two distinct checks. (1)
> `bootstrap/verify.sh` re-derives `bootstrap/asm` from the archived **Rust
> seed** (`archive/seed/`) and checks byte-identity — the independent leg that
> makes the asm binary itself trustworthy; it needs rustc/cargo, so it runs
> **offline**, not in CI. (2) Given that asm binary, `scripts/seed-derive-cycc.sh`
> proves `build/cycc` descends from it with no bridge rung: asm assembles
> `cybs`, `cybs` reproduces asm (closure) and compiles `src/main.cyr` → gen1,
> gen1 → gen2 == `build/cycc` (self-host fixpoint, gen2 == gen3). So `cycc` is
> machine-derivable from the seed in two hops — the **closure** leg is validated
> in CI (`trust-root-attest`), the **asm-from-Rust-source** leg offline by
> `verify.sh`; full trusting-trust resistance needs both. (The CVE-20 completing
> fix: `cybs`'s string lexer wasn't NUL-terminating literals, so the
> preprocessor's macro-hash over-read and the Linux `#ifdef` block was dropped —
> the alloc fns went undefined and the generated `cycc` trapped.) See
> [SECURITY.md](SECURITY.md).

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
