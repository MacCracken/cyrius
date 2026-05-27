# Binary Size Comparisons

> **Purpose**: authoritative source of `exit42`-minimum binary sizes across
> languages and platforms. Referenced by external articles and the
> agnosticos project. Updated as new compiler versions ship.
>
> **Last measured**: 2026-05-03, at Cyrius v5.8.31.
> **Methodology**: `int main() { return 42; }` (or language equivalent — all
> sources are ≤ 4 lines), no external dependencies, default invocation
> unless a size-oriented flag is documented. Sizes are raw `wc -c` bytes
> of the produced executable.

## exit42 — Linux x86_64 ELF

| Language | Toolchain | Invocation | Bytes | × Cyrius |
|----------|-----------|-----------|------:|---------:|
| **Cyrius** | cycc 5.8.31 | `echo 'syscall(60, 42);' \| cycc` | **152** | 1× |
| Zig | 0.15.2 `-OReleaseSmall` | `zig build-exe -OReleaseSmall` | 4,840 | 32× |
| Zig | 0.15.2 `-OReleaseSmall` Windows PE | `zig build-exe -target x86_64-windows -OReleaseSmall` | 4,608 | 30× |
| C (GCC) | gcc 15.2.1 `-O2 -s` | `gcc -O2 -s` | 14,248 | 94× |
| C (clang) | clang 20 `-O2 -s` | `clang -O2 -s` | 14,272 | 94× |
| C (GCC) | gcc 15.2.1 `-O2` | `gcc -O2` (w/ symbols) | 15,712 | 103× |
| C (GCC) | gcc 15.2.1 `-O2 -s -static` | full static w/ libc | 694,408 | 4,568× |
| Rust | rustc 1.93.0 `-O` stripped | `rustc -O && strip` | 344,856 | **2,269×** |
| Go | go 1.26.2 `-s -w` | `go build -ldflags="-s -w"` | 1,400,994 | 9,217× |
| Go | go 1.26.2 default | `go build` | 2,182,601 | 14,359× |
| Rust | rustc 1.93.0 `-O` (w/ symbols) | `rustc -O` | 3,887,480 | 25,575× |
| Rust | rustc 1.93.0 debug | `rustc` (default) | 3,888,160 | 25,580× |
| Zig | 0.15.2 debug | `zig build-exe` (default) | 7,388,344 | 48,608× |

## exit42 — Windows x86_64 PE32+

| Language | Toolchain | Invocation | Bytes | × Cyrius |
|----------|-----------|-----------|------:|---------:|
| **Cyrius** | cycc_win 5.8.31 native (on Windows) | `cycc_win.exe < exit42.cyr` | **1,536** | 1× |
| **Cyrius** | cycc 5.8.31 Linux cross-build | `CYRIUS_TARGET_WIN=1 cycc` | 1,536 | 1× (byte-identical to native) |
| Zig | 0.15.2 `-OReleaseSmall` | `zig build-exe -target x86_64-windows -OReleaseSmall` | 4,608 | 3× |
| Go | go 1.26.2 `-s -w` | `GOOS=windows GOARCH=amd64 go build -ldflags="-s -w"` | 1,492,992 | 972× |
| Go | go 1.26.2 default | `GOOS=windows GOARCH=amd64 go build` | 2,265,600 | 1,475× |

## Notes

- **Cyrius Linux ELF is 152 B** because cycc emits a stripped minimum-viable
  ELF: the 64 B ELF header, one program header (56 B), a 5 B `mov eax, 60;
  syscall(42)` sequence, a handful of alignment bytes. No interpreter,
  no dynamic linker, no runtime. The binary talks directly to the
  kernel via syscalls.
- **Cyrius Windows PE is 1536 B** and runs end-to-end on Windows 11
  (build 26200, verified v5.5.10). Extra vs ELF is the PE format tax
  (DOS stub + NT headers + `.idata` import table for `kernel32!ExitProcess`
  + FileAlignment padding). Compiles natively on Windows; byte-identical
  to Linux cross-build output.
- **Rust + stripping**: stripping Rust removes ~3.6 MB of debug / symbol
  data but the baseline panic-handler, allocator, and runtime stay in
  — that's the 344 KB floor. `#![no_std]` + `#![no_main]` + a custom
  `panic_handler` can go lower (~8 KB range) but isn't idiomatic Rust.
- **Zig `-OReleaseSmall`** is the closest competitor at ~32× on Linux
  ELF / ~3× on Windows PE. Zig's `panic_handler` and `_start` are
  present but minimal.
- **Go** bundles a goroutine scheduler, garbage collector, and runtime
  reflection — the 1.4–2.3 MB is the Go runtime, not the user code.

## Cyrius self-host context

For perspective, the Cyrius compiler itself (cycc) is **874,280 B**
(~874 KB) on Linux ELF at v6.0.3. It compiles itself byte-identically.
At v5.5.10 it also compiles itself byte-identically on Windows
(cycc_win.exe native → out.exe matches Linux cross-build md5).
That's the whole self-hosting compiler — TLS / atomics / dynlib /
NSS quartet / sum types + match / `?` propagation / Result-shaped
stdlib / UEFI Application emit (v5.11.49) / ELF64 + multiboot2
kernel emit (v5.11.43) / DCE-aware reachability filter cross-arch
(v5.11.59) — in less disk than Rust's stripped debug exit42.

- Cyrius cycc (Linux ELF): **874,280 B** (v6.0.3)
- cycc_aarch64 (Linux aarch64 cross): **564,512 B** (v6.0.3; the
  v5.11.59 full DCE bitmap pass for aarch64 fixup.cyr — mirroring the
  x86 path since v5.10.x — accounts for the bulk over earlier v5.11.x)
- cycc_win (Windows PE cross): **686,632 B** (v6.0.3; PE format
  overhead + v5.5.35 .reloc + v5.6.31 DllChar 0x0160 + v5.11.47-.49
  EFI Application emit deltas)
- cycc compiles itself in milliseconds (no cache, no incremental build —
  just `cat src/main.cyr | cycc > cc5_new`).
- Full release toolchain (`~/.cyrius/bin/`): **~3.7 MB** across compiler
  + cross-compilers + linker (cyrld) + LSP (cyrius-lsp) + formatter
  (cyrfmt) + linter (cyrlint) + doc tool (cyrdoc) + CLI (cyrius)
  + init (cyrius-init) + manager (cyriusly) + utilities.

Growth since v5.6.43 (2026-04-25 → 2026-05-13):
+291,224 B / +55% across 5 minors + ~50 patches. Drivers: O7 IR pass
+ JSX / TS lex chains (v5.7.x), tagged unions + exhaustive `match`
infrastructure (v5.8.21–v5.8.27), `?` propagation operator
(v5.8.29 + v5.8.31 PARSE_STMT extension). The compiler is still
in the same order of magnitude as a stripped Rust hello-world.

## What this means

The numbers above measure **runtime overhead per binary**, not
"hello-world program written in X" as a proxy for language power. A C
hello-world is not 14 KB of application code — it's 4 KB of
statically-embedded libc startup plus program body. A Rust exit42 is
not 345 KB of business logic — it's 345 KB of "Rust is running in
this process" infrastructure.

Cyrius prints the smaller number because its runtime is zero. The
compiler emits a syscall and an exit, the kernel obliges.

## Methodology / reproduction

Source files, invocations, and the measurement script live in
`/tmp/sizecomp/` during development; commit the current results into
this file at each release that moves the needle. Re-run at every
minor bump.

```bash
# Minimum-viable repro (Linux x86_64):
echo 'syscall(60, 42);' | ./build/cycc > /tmp/exit42_cyr; wc -c /tmp/exit42_cyr
echo 'int main(void) { return 42; }' > /tmp/exit42.c && \
    gcc -O2 -s /tmp/exit42.c -o /tmp/exit42_c && wc -c /tmp/exit42_c
# ... and so on for each row.
```

## Updates

- **v5.5.10** (2026-04-20): first comprehensive multi-platform measurement.
  Native Windows self-host byte-identical fixpoint achieved; Cyrius PE
  confirmed at 1536 B on real Windows 11.
- **v5.5.40** (2026-04-21): compiler size refreshed to 507,136 B after the
  v5.5.x minor closed (40-patch arc: Win64 ABI end-to-end, NSS-free
  identity quartet, foreign-dlopen, thread-local + atomics, parser/lexer
  split, legacy cc3 retirement). Exit42 PE/ELF numbers unchanged.
- **v5.6.43** (2026-04-25): compiler size refreshed to 531,888 B after the
  v5.6.x minor closed (44-patch arc: O1–O6 optimization arc, regalloc
  default-on, codebuf compaction, ALPN/mTLS hook surface, SysV stack
  alignment fix, preprocessor cap raises, output_buf cap raise, dep
  bumps to patra 1.8.3 / sigil 2.9.3 / sankoch 2.1.0). Exit42 PE/ELF
  numbers unchanged. cc5_aarch64_macho_cross (411,040 B) and
  cycc_aarch64 (411,616 B) added as listed cross-build artifacts.
- **v5.8.31** (2026-05-03): compiler size refreshed to 739,672 B after
  the v5.7.x minor closed (49-patch arc: cyrius-ts JSX + advanced TS
  surface, JSON depth + streaming + pointer + lib/test.cyr testing
  helper, RISC-V deferred to v5.9.x) and the v5.8.x cycle reached its
  Result+? sub-suite midpoint (slots 28-31 of 44 pinned). Drivers in
  v5.8.x specifically: tagged-unions + exhaustive `match` infrastructure
  (v5.8.21–v5.8.27, +5,568 B), `?` propagation operator (v5.8.29 +968 B
  + v5.8.31 PARSE_STMT extension +816 B). Stdlib Result migrations at
  v5.8.30 / v5.8.31 ship zero compiler delta — pure stdlib reorganization.
  Exit42 PE/ELF numbers unchanged. cycc_win_cross bumped to 534,888 B
  (was 526,856 — +8,032 from the v5.7.x JSON / TS additions migrating
  through the cross-build path).
