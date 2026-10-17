# Binary Size Comparisons

> **Purpose**: authoritative source of `exit42`-minimum binary sizes across
> languages and platforms. Referenced by external articles and the
> agnosticos project. Updated as new compiler versions ship.
>
> **Last measured**: 2026-10-12, at Cyrius 6.7.9. **Every row was re-measured**, not
> carried: the three Cyrius rows built with `build/cycc` (byte-identical to the tagged
> 6.7.9 install slot's `cycc`) and RUN — both ELF variants exit 42 natively, the PE build
> exits 42 under wine — and the C / Rust / Go / Zig rows built and run with the toolchains
> named in each row (all on PATH on this box). The self-host figures are read from the
> tagged 6.7.9 install slot (`~/.cyrius/versions/6.7.9/bin/`).
> **Methodology**: `int main() { return 42; }` (or language equivalent — all
> sources are ≤ 5 lines, listed under *Methodology / reproduction*), no external
> dependencies, default invocation unless a size-oriented flag is documented.
> Sizes are raw `wc -c` bytes of the produced executable.

## exit42 — Linux x86_64 ELF

| Language | Toolchain | Invocation | Bytes | × Cyrius |
|----------|-----------|-----------|------:|---------:|
| **Cyrius** (`CYRIUS_WX=0`) | cycc 6.7.9 | single `RWE` `PT_LOAD`, opt-out | 504 | 0.11× |
| **Cyrius** (default, W^X) | cycc 6.7.9 | `echo 'syscall(60, 42);' \| cycc` | **4,448** | 1× |
| Zig | 0.16.0 `-OReleaseSmall` Windows PE | `zig build-exe -target x86_64-windows -OReleaseSmall` | 4,608 | 1.0× |
| Zig | 0.16.0 `-OReleaseSmall` | `zig build-exe -OReleaseSmall` | 4,840 | 1.1× |
| C (GCC) | gcc 16.2.1 `-O2 -s` | `gcc -O2 -s` | 14,320 | 3× |
| C (clang) | clang 23.1.1 `-O2 -s` | `clang -O2 -s` | 14,344 | 3× |
| C (GCC) | gcc 16.2.1 `-O2` | `gcc -O2` (w/ symbols) | 15,784 | 4× |
| Rust | rustc 1.97.1 `-O` stripped | `rustc -O && strip` | 338,120 | **76×** |
| C (GCC) | gcc 16.2.1 `-O2 -s -static` | full static w/ libc | 772,200 | 174× |
| Go | go 1.27.1 `-s -w` | `go build -ldflags="-s -w"` | 1,298,592 | 292× |
| Go | go 1.27.1 default | `go build` | 2,085,846 | 469× |
| Rust | rustc 1.97.1 `-O` (w/ symbols) | `rustc -O` | 4,347,296 | 977× |
| Rust | rustc 1.97.1 debug | `rustc` (default) | 4,348,088 | 978× |
| Zig | 0.16.0 debug | `zig build-exe` (default) | 10,196,002 | 2,292× |

⚠ **The Cyrius baseline is 4,448 B, not 504 B, since v6.3.12**, when userland ELF went
**W^X** by default: two permission-separated, page-aligned `PT_LOAD` segments
(text `R E`, data `RW `) instead of the historical single `RWE`. The second segment's
file offset must be page-aligned, and that alignment padding is essentially the whole
delta — the *loadable* image is 208 B (`FileSiz 0xd0`). `CYRIUS_WX=0` still emits the
504 B single-segment binary.

On **aarch64** the same split aligns the data's file offset to 64 KB (`p_align` 0x10000), so the
padding is up to 64 KB: `syscall(60, 7);` cross-built for aarch64 is 65,888 B (520 B with
`CYRIUS_WX=0`; measured at 6.7.14), and an aarch64 binary's size moves in 64 KB steps. That is the
price of exact W^X on 4, 16 and 64 KB-page arm64 kernels, kept by 6.7.13's D45; compare aarch64
code size by the code `PT_LOAD`'s `FileSiz`, not the file size (the guide's *Executable size and
W^X*).

The Go toolchain on this box reports itself as `go1.27.1-X:nodwarf5` (a distribution build
with a `GOEXPERIMENT` set). A default `go build` embeds the module path, so its bytes move by
tens to hundreds with the module name (the `-s -w` rows do not move). Zig 0.16.0 produced the
same sizes as the previous sweep; every other toolchain had moved a version since it.

## exit42 — Windows x86_64 PE32+

| Language | Toolchain | Invocation | Bytes | × Cyrius |
|----------|-----------|-----------|------:|---------:|
| **Cyrius** | cycc 6.7.9 Linux cross-build | `CYRIUS_TARGET_WIN=1 cycc` | **1,536** | 1× |
| **Cyrius** | cycc_win 6.7.9 (the PE32+ compiler) | `cycc_win.exe < exit42.cyr` | 1,536 | 1× (byte-identical to the cross-build) |
| Zig | 0.16.0 `-OReleaseSmall` | `zig build-exe -target x86_64-windows -OReleaseSmall` | 4,608 | 3× |
| Go | go 1.27.1 `-s -w` | `GOOS=windows GOARCH=amd64 go build -ldflags="-s -w"` | 1,482,240 | 965× |
| Go | go 1.27.1 default | `GOOS=windows GOARCH=amd64 go build` | 2,308,608 | 1,503× |

The `cycc_win` row was run under wine on this box; the PE compiler's self-host itself is
verified on real Windows 11 (`cass`) by every release gate.

## Notes

- **Cyrius Linux ELF is 4,448 B** — but the *loadable image* is 208 B (the 64 B
  ELF header, **two** program headers (2 × 56 B), the `mov eax, 60; syscall`
  sequence, alignment bytes; text `PT_LOAD` `FileSiz 0xd0`). The rest is
  structure, not code: the W^X data segment's file offset is page-aligned
  (v6.3.12), so the file is padded out to 0x1000 before it, and cycc appends a
  section-header table (5 entries: the null entry, `.text`, `.rodata`, `.bss`,
  `.shstrtab`) for tooling compatibility (`readelf`/`objdump`/`gdb` read it; the
  loader ignores it). Set `CYRIUS_WX=0` and the same source emits the 504 B
  single-`RWE`-segment binary. No interpreter, no dynamic linker, no runtime:
  the binary talks directly to the kernel via syscalls.
- **Cyrius Windows PE is 1536 B** and runs end-to-end on Windows 11. Extra vs
  the 504 B `CYRIUS_WX=0` ELF is the PE format tax (DOS stub + NT headers +
  `.idata` import table for `kernel32!ExitProcess` + FileAlignment padding). PE
  is unaffected by the v6.3.12 W^X change (Mach-O / PE / kernel / shared-`.so`
  paths are guarded out). The PE32+ compiler `cycc_win` emits the same bytes as
  the Linux cross-build.
- **Rust + stripping**: stripping Rust removes ~4 MB of debug / symbol
  data but the baseline panic-handler, allocator, and runtime stay in
  — that's the 338 KB floor. `#![no_std]` + `#![no_main]` + a custom
  `panic_handler` can go lower (~8 KB range) but isn't idiomatic Rust.
- **Zig `-OReleaseSmall`** is the closest competitor, and since v6.3.12 it is
  effectively level with Cyrius on Linux ELF (~1.1×) — both are dominated by
  page-alignment padding at this size, not by code — while staying ~3× on
  Windows PE. Zig's `panic_handler` and `_start` are present but minimal.
  Against the `CYRIUS_WX=0` single-segment build the ~10× gap holds.
- **Go** bundles a goroutine scheduler, garbage collector, and runtime
  reflection — the 1.3–2.3 MB is the Go runtime, not the user code.

## Cyrius self-host context

For perspective, the Cyrius compiler itself (cycc) is **2,057,736 B**
(~2.06 MB) on Linux ELF at 6.7.9. It compiles itself byte-identically, and every
release gate re-checks that fixpoint on real macOS (arm64 and Intel), Windows and
aarch64 Linux hardware as well.
That's the whole self-hosting compiler — TLS / atomics / dynlib /
NSS quartet / sum types + match / `?` propagation / Result-shaped
stdlib / UEFI Application emit / ELF64 + multiboot2 kernel emit /
DCE-aware reachability filter cross-arch / Windows process / thread /
TLS / env / file-I-O / directory enumeration / the full packed-SIMD
emitter set — x86 SSE+AVX2, aarch64 NEON, Win64 PE value-form, and cx
bytecode per-lane loops / TS/TSX → JS emit (`cycc --emit-js`) / traits,
checked `dyn` trait objects, tuples, `const fn` and the bounds-checked
mode — in less than half the bytes of an unstripped Rust exit42
(4,347,296 B).

- Cyrius cycc (Linux ELF): **2,057,736 B** (6.7.9; `.text` 1,845,440 B)
- cycc_aarch64 (Linux aarch64 cross): **1,619,400 B** (6.7.9)
- cycc_win (the PE32+ compiler): **2,140,160 B** (6.7.9)
- cycc_cx (cyrius-x bytecode cross): **1,521,768 B** (6.7.9)
- cycc-native-aarch64 (aarch64-hosted, verified on pi): **1,881,280 B** (6.7.9)
- cycc compiles itself in ~1.44 s (no cache, no incremental build —
  just `cat src/main.cyr | cycc > cycc_new`; 1,437.7 ms in the `bench-history.csv`
  row the 6.7.9 release gate recorded). Read one run with suspicion: see
  [benchmarks.md](benchmarks.md).
- Core toolchain: **11,534,408 B (~11.5 MB)** across compiler
  + 4 cross-compilers + linker (cyrld) + LSP (cyrius-lsp) + formatter
  (cyrfmt) + linter (cyrlint) + doc tool (cyrdoc) + CLI (cyrius)
  + init/port (cyrius-init), from the tagged 6.7.9 install slot. The installed
  `bin/` directory measures 15,371,434 B in total, ~3.1 MB of which is the two
  `cyrsign*` Authenticode helpers (1,547,752 B and 1,539,056 B).

Whole-history growth to 6.7.9 (2026-04-25 → 2026-10-11):
531,888 → 2,057,736 B, +1,525,848 B / +287%. Across the v6.4.x SIMD
arc, the v6.5.x visibility + perf work, the v6.7.x language features
(traits, `dyn`, tuples, `const fn`, the bounds-checked mode) and
everything between, that is ~6.1× a stripped Rust exit42 (338,120 B) —
for a compiler, linker driver, five backends and a TypeScript frontend.
The per-release sizes are in each `CHANGELOG.md` entry.

## What this means

The numbers above measure **runtime overhead per binary**, not
"hello-world program written in X" as a proxy for language power. A C
hello-world is not 14 KB of application code — it's 4 KB of
statically-embedded libc startup plus program body. A Rust exit42 is
not 338 KB of business logic — it's 338 KB of "Rust is running in
this process" infrastructure.

Cyrius prints the smaller number because its runtime is zero. The
compiler emits a syscall and an exit, the kernel obliges. At the very
bottom of the range this stops being the interesting axis: since
v6.3.12 the default Cyrius ELF and a `-OReleaseSmall` Zig binary are
within 400 B of each other, and both are mostly page-alignment
padding. The 76×–978× rows are where runtime overhead actually shows.

## Methodology / reproduction

Commit the current results into this file at each release that moves
the needle, and re-run at every minor bump — **re-run the exit42 rows
themselves, not just the compiler size**. Any change to container
layout (segment split, alignment, section-header table, a new default
header) moves exit42 without touching a single line of the numbers
already in this file; that is how the 504 B baseline survived v6.3.12
for four minors. A stamp moved without re-running the measurement is
the rot this file is most prone to.

```bash
# Cyrius (Linux x86_64), from the repo root:
echo 'syscall(60, 42);' > /tmp/exit42.cyr
./build/cycc < /tmp/exit42.cyr > /tmp/exit42_cyr && chmod +x /tmp/exit42_cyr
/tmp/exit42_cyr; echo $?; wc -c < /tmp/exit42_cyr                         # 42, 4448
CYRIUS_WX=0 ./build/cycc < /tmp/exit42.cyr > /tmp/exit42_rwe               # 504
CYRIUS_TARGET_WIN=1 ./build/cycc < /tmp/exit42.cyr > /tmp/exit42.exe       # 1536

# The other rows' sources:
#   C     int main(void) { return 42; }
#   Rust  fn main() { std::process::exit(42); }
#   Go    package main; import "os"; func main() { os.Exit(42) }   (one statement per line)
#   Zig   pub fn main() u8 { return 42; }
echo 'int main(void) { return 42; }' > /tmp/exit42.c
gcc -O2 -s /tmp/exit42.c -o /tmp/exit42_c && wc -c < /tmp/exit42_c        # 14320
# ... and so on for each row, with the invocation in its table.
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
- **v6.6.1 – v6.6.20** (2026-09-08 → 2026-10-06): the Cyrius rows re-measured
  and run (504 / 4,448 / 1,536, unchanged); compiler 1,247,608 B at v6.6.1 and
  1,586,184 B at v6.6.19; the toolchain footprint re-measured (8,718,168 B core /
  12,440,524 B installed at v6.6.19). Two claims of the v6.5.10 entry were wrong:
  Go and Zig were on PATH (`/usr/bin/go`, `/usr/bin/zig`) and were re-measured, and
  the 35,138,369 B installed figure was a 10× error about the `cyrsign*` helpers.
- **6.7.9** (2026-10-12): every row re-measured and run. Cyrius rows unchanged
  (504 / 4,448 / 1,536; the PE32+ `cycc_win` emits the same 1,536 B under wine);
  gcc 16.2.1 / clang 23.1.1 / rustc 1.97.1 / go 1.27.1 rows refreshed (Zig 0.16.0
  identical). Compiler 2,057,736 B, cross-compilers 1,619,400 (aarch64) /
  2,140,160 (win, PE32+) / 1,521,768 (cx) / 1,881,280 (native aarch64); core
  toolchain 11,534,408 B, installed `bin/` 15,371,434 B.
