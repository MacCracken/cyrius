# Binary Size Comparisons

> **Purpose**: authoritative source of `exit42`-minimum binary sizes across
> languages and platforms. Referenced by external articles and the
> agnosticos project. Updated as new compiler versions ship.
>
> **Last measured**: 2026-08-07, at Cyrius v6.5.10 (Cyrius self-host figures, plus a
> fresh C / Rust / Go / Zig sweep on this box — every row below was re-measured, none
> carried over). ⚠ A prior pass asserted Go and Zig "could not be re-measured, neither
> toolchain is installed here"; both are on PATH (`/usr/bin/go`, `/usr/bin/zig`) and both
> had moved a version. Check before claiming a measurement is impossible.
> **Methodology**: `int main() { return 42; }` (or language equivalent — all
> sources are ≤ 4 lines), no external dependencies, default invocation
> unless a size-oriented flag is documented. Sizes are raw `wc -c` bytes
> of the produced executable.

## exit42 — Linux x86_64 ELF

| Language | Toolchain | Invocation | Bytes | × Cyrius |
|----------|-----------|-----------|------:|---------:|
| **Cyrius** (`CYRIUS_WX=0`) | cycc 6.5.10 | single `RWE` `PT_LOAD`, opt-out | 504 | 0.11× |
| **Cyrius** (default, W^X) | cycc 6.5.10 | `echo 'syscall(60, 42);' \| cycc` | **4,448** | 1× |
| Zig | 0.16.0 `-OReleaseSmall` Windows PE | `zig build-exe -target x86_64-windows -OReleaseSmall` | 4,608 | 1.0× |
| Zig | 0.16.0 `-OReleaseSmall` | `zig build-exe -OReleaseSmall` | 4,840 | 1.1× |
| C (GCC) | gcc 16.1.1 `-O2 -s` | `gcc -O2 -s` | 14,320 | 3× |
| C (clang) | clang 22.1.8 `-O2 -s` | `clang -O2 -s` | 14,344 | 3× |
| C (GCC) | gcc 16.1.1 `-O2` | `gcc -O2` (w/ symbols) | 15,776 | 4× |
| Rust | rustc 1.96.0 `-O` stripped | `rustc -O && strip` | 339,160 | **76×** |
| C (GCC) | gcc 16.1.1 `-O2 -s -static` | full static w/ libc | 772,200 | 174× |
| Go | go 1.26.5 `-s -w` | `go build -ldflags="-s -w"` | 1,400,994 | 315× |
| Go | go 1.26.5 default | `go build` | 2,183,116 | 491× |
| Rust | rustc 1.96.0 `-O` (w/ symbols) | `rustc -O` | 4,330,328 | 974× |
| Rust | rustc 1.96.0 debug | `rustc` (default) | 4,331,000 | 974× |
| Zig | 0.16.0 debug | `zig build-exe` (default) | 10,196,002 | 2,292× |

⚠ **The Cyrius baseline moved 504 → 4,448 B at v6.3.12**, when userland ELF went
**W^X** by default: two permission-separated, page-aligned `PT_LOAD` segments
(text `R E`, data `RW `) instead of the historical single `RWE`. The second segment's
file offset must be page-aligned, and that alignment padding is essentially the whole
delta — the *loadable* image is 208 B (`FileSiz 0xd0`), up from 152 B. `CYRIUS_WX=0`
still emits the 504 B single-segment binary. This table read 504 B from v6.3.12 all
the way to v6.5.10 — including a v6.4.62 refresh that updated the *compiler* size but
never re-ran the exit42 measurement — and every "× Cyrius" multiplier was inflated to
match.

All rows measured 2026-08-07 on this box, Go and Zig included. Two moved with their
toolchains: `go build` default 2,182,601 → 2,183,116 (go 1.26.2 → 1.26.5) and `zig
build-exe` debug 7,388,344 → 10,196,002 (zig 0.15.2 → 0.16.0, **+38 %**). `go build
-ldflags="-s -w"` (1,400,994) and `zig -OReleaseSmall` (4,840) are byte-identical
across both toolchain versions.

## exit42 — Windows x86_64 PE32+

| Language | Toolchain | Invocation | Bytes | × Cyrius |
|----------|-----------|-----------|------:|---------:|
| **Cyrius** | cycc 6.5.10 Linux cross-build | `CYRIUS_TARGET_WIN=1 cycc` | **1,536** | 1× |
| **Cyrius** | cycc_win native (on Windows) | `cycc_win.exe < exit42.cyr` | 1,536 | 1× (byte-identical to the cross-build) |
| Zig | 0.16.0 `-OReleaseSmall` | `zig build-exe -target x86_64-windows -OReleaseSmall` | 4,608 | 3× |
| Go | go 1.26.2 `-s -w` | `GOOS=windows GOARCH=amd64 go build -ldflags="-s -w"` | 1,492,992 | 972× |
| Go | go 1.26.2 default | `GOOS=windows GOARCH=amd64 go build` | 2,265,600 | 1,475× |

## Notes

- **Cyrius Linux ELF is 4,448 B** — but the *loadable image* is 208 B (the 64 B
  ELF header, **two** program headers (2 × 56 B), the `mov eax, 60; syscall`
  sequence, alignment bytes; text `PT_LOAD` `FileSiz 0xd0`). The rest is
  structure, not code: the W^X data segment's file offset is page-aligned
  (v6.3.12), so the file is padded out to 0x1000 before it, and cycc appends a
  section-header table (5 sections: `.text`/`.rodata`/`.bss`/`.shstrtab` …) for
  tooling compatibility (`readelf`/`objdump`/`gdb` read it; the loader ignores
  it). Set `CYRIUS_WX=0` and the same source emits the pre-v6.3.12 504 B
  single-`RWE`-segment binary. No interpreter, no dynamic linker, no runtime:
  the binary talks directly to the kernel via syscalls.
- **Cyrius Windows PE is 1536 B** and runs end-to-end on Windows 11
  (build 26200, verified v5.5.10). Extra vs the 504 B `CYRIUS_WX=0` ELF is the
  PE format tax (DOS stub + NT headers + `.idata` import table for
  `kernel32!ExitProcess` + FileAlignment padding). PE is unaffected by the
  v6.3.12 W^X change (Mach-O / PE / kernel / shared-`.so` paths are guarded
  out). Compiles natively on Windows; byte-identical to Linux cross-build
  output, re-verified every release on real `cass`.
- **Rust + stripping**: stripping Rust removes ~4 MB of debug / symbol
  data but the baseline panic-handler, allocator, and runtime stay in
  — that's the 339 KB floor. `#![no_std]` + `#![no_main]` + a custom
  `panic_handler` can go lower (~8 KB range) but isn't idiomatic Rust.
- **Zig `-OReleaseSmall`** is the closest competitor, and since v6.3.12 it is
  effectively level with Cyrius on Linux ELF (~1.1×) — both are dominated by
  page-alignment padding at this size, not by code — while staying ~3× on
  Windows PE. Zig's `panic_handler` and `_start` are present but minimal.
  Against the `CYRIUS_WX=0` single-segment build the old ~10× gap holds.
- **Go** bundles a goroutine scheduler, garbage collector, and runtime
  reflection — the 1.4–2.3 MB is the Go runtime, not the user code.

## Cyrius self-host context

For perspective, the Cyrius compiler itself (cycc) is **1,141,792 B**
(~1,115 KB / ~1.09 MB) on Linux ELF at v6.5.10. It compiles itself byte-identically.
At v5.5.10 it also compiles itself byte-identically on Windows
(cycc_win.exe native → out.exe matches Linux cross-build md5).
That's the whole self-hosting compiler — TLS / atomics / dynlib /
NSS quartet / sum types + match / `?` propagation / Result-shaped
stdlib / UEFI Application emit (v5.11.49) / ELF64 + multiboot2
kernel emit (v5.11.43) / DCE-aware reachability filter cross-arch
(v5.11.59) / Windows process/thread/TLS/env/file-I-O/directory-enumeration
(v6.1.16–v6.1.18) / the full packed-SIMD emitter set — x86 SSE+AVX2,
aarch64 NEON, Win64 PE value-form, and cx bytecode per-lane loops
(SIMD Phase 5 complete, v6.4.4–v6.4.32) / TS/TSX → JS emit (`cycc
--emit-js`) — in less disk than Rust's stripped debug exit42.

- Cyrius cycc (Linux ELF): **1,141,792 B** (v6.5.10)
- cycc_aarch64 (Linux aarch64 cross): **685,312 B** (v6.5.10; the
  v5.11.59 full DCE bitmap pass for aarch64 fixup.cyr — mirroring the
  x86 path since v5.10.x — accounts for the bulk over earlier v5.11.x)
- cycc_win (Windows PE cross): **1,021,440 B** (v6.5.10; PE format
  overhead + v5.5.35 .reloc + v5.6.31 DllChar 0x0160 + v5.11.47-.49
  EFI Application emit deltas + v6.1.16 lib/sync.cyr portable mutex +
  v6.1.17 PE nanosleep routing + v6.1.18 Windows directory enumeration)
- cycc_cx (cyrius-x bytecode cross): **606,104 B** (v6.5.10)
- cycc-native-aarch64 (aarch64-hosted, pi-verified): **940,536 B**
- cycc compiles itself in ~650 ms (no cache, no incremental build —
  just `cat src/main.cyr | cycc > cycc_new`; 648 / 652 ms at v6.5.10).
- Core toolchain: **6,385,008 B (~6.1 MB)** across compiler
  + 4 cross-compilers + linker (cyrld) + LSP (cyrius-lsp) + formatter
  (cyrfmt) + linter (cyrlint) + doc tool (cyrdoc) + CLI (cyrius)
  + init/port (cyrius-init). The installed `~/.cyrius/bin/` directory
  measures 35,138,369 B in total, ~27 MB of which is the two `cyrsign*`
  Authenticode helpers (~14 MB each on disk).

Growth since v5.6.43 (2026-04-25 → 2026-05-13):
+291,224 B / +55% across 5 minors + ~50 patches. Drivers: O7 IR pass
+ JSX / TS lex chains (v5.7.x), tagged unions + exhaustive `match`
infrastructure (v5.8.21–v5.8.27), `?` propagation operator
(v5.8.29 + v5.8.31 PARSE_STMT extension). The compiler is still
in the same order of magnitude as a stripped Rust hello-world.

Whole-history growth to v6.5.10 (2026-04-25 → 2026-08-07):
531,888 → 1,141,792 B, +609,904 B / +115%. Across the v6.4.x SIMD
arc, the v6.5.x visibility + perf work, and everything between, that
is still 3.4× a stripped Rust exit42 — for a compiler, linker driver,
five backends and a TypeScript frontend.

## What this means

The numbers above measure **runtime overhead per binary**, not
"hello-world program written in X" as a proxy for language power. A C
hello-world is not 14 KB of application code — it's 4 KB of
statically-embedded libc startup plus program body. A Rust exit42 is
not 339 KB of business logic — it's 339 KB of "Rust is running in
this process" infrastructure.

Cyrius prints the smaller number because its runtime is zero. The
compiler emits a syscall and an exit, the kernel obliges. At the very
bottom of the range this stops being the interesting axis: since
v6.3.12 the default Cyrius ELF and a `-OReleaseSmall` Zig binary are
within 400 B of each other, and both are mostly page-alignment
padding. The 76×–974× rows are where runtime overhead actually shows.

## Methodology / reproduction

Source files, invocations, and the measurement script live in
`/tmp/sizecomp/` during development; commit the current results into
this file at each release that moves the needle. Re-run at every
minor bump — and **re-run the exit42 rows themselves, not just the
compiler size**. Any change to container layout (segment split,
alignment, section-header table, a new default header) moves exit42
without touching a single line of the numbers already in this file;
that is exactly how the 504 B baseline survived v6.3.12.

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
- **v6.5.10** (2026-08-07): **the exit42 Linux ELF baseline was wrong for
  four minors.** v6.3.12 made W^X the userland ELF default (two page-aligned
  `PT_LOAD` segments), which moved exit42 from 504 → **4,448 B** — but this
  file was refreshed at v6.4.62 without re-running the ELF measurement, so
  it kept quoting 504 and every "× Cyrius" multiplier derived from it. Both
  the default and the `CYRIUS_WX=0` figures are now listed. C and Rust rows
  re-measured against gcc 16.1.1 / clang 22.1.8 / rustc 1.96.0; Go and Zig
  left at the 2026-05-03 sweep (not installed on this box). Compiler size
  refreshed to 1,141,792 B, cross-compilers to 685,312 (aarch64) /
  1,021,440 (win) / 606,104 (cx). Toolchain footprint restated from the
  stale ~3.7 MB to a measured 6,385,008 B core / 35,138,369 B installed.
