# ADR-003: Fixed Heap Layout over Dynamic Allocation

**Status**: Accepted
**Date**: 2026-03-28
**Context**: The compiler needs storage for tokens, names, variables, functions, and code.

## Decision

Use fixed-offset heap arrays allocated via a single `brk` syscall (an
anonymous-mmap chunk allocator since v6.1.19). No malloc, no free, no dynamic
resizing within a compilation run — **with the v6.2.0 exception noted below**.

## Status Update — v6.2.0 (Phase 0: growable pressure tables)

Three regions outgrew the fixed-cap model and were migrated to **growable**
storage, ending the cap-raise treadmill (the fixup table alone was bumped
16K → 32K → 262K → 1M across v5.x). Each keeps its original offset as the
*initial* base, then relocates off-heap (`alloc()`) and doubles on demand:

- **fixup_tbl** — `_fixup_base` / `_fixup_grow`, 64M-entry ceiling
- **fn-tables** (16 parallel tables + the `fn_name`/`fn_start` hashes + the
  `live[]` DCE bitmap) — `_fnt_*` behind a single `_fnt_cap`, grow + rehash,
  32,768 ceiling
- **codebuf** — `_codebuf_base` / `_codebuf_grow`, 64 MiB ceiling (the cx
  bytecode backend keeps its own fixed 512 KB region)

The fixed-layout rationale (determinism, auditability, no allocator in the hot
path) **still holds for the remaining regions**; the growable tables stay
input-deterministic (allocation order is a pure function of the input), so
self-host remains byte-identical. See `CHANGELOG [6.2.0]` and `util.cyr`.

## Rationale

- **Determinism**: Same input always produces same memory layout
- **No allocator needed**: The compiler itself has no alloc library dependency
- **Speed**: Direct offset calculation, no pointer chasing
- **Auditability**: Every buffer has a known address documented in the HEAP MAP

## Layout (summary — reconciled v6.0.73)

The **authoritative** registry is the `HEAP MAP` comment block in
`src/main.cyr` (the `HEAP MAP` block, 100 regions, verified monotonic + overlap-free
by `tests/heapmap.sh`). This ADR keeps only a high-level summary; when the
two disagree, **`src/main.cyr` wins**. Major regions, in offset order:

```
0x00000   input_buf       1 MB    raw stdin source (tok_names nested at 0x60000)
0x60000   tok_names     256 KB    packed identifier strings (rebuilt by LEX)
0x12A000  var tables    ~128 KB   8192 vars (offsets / sizes / types)
0x14A000  fn_regalloc    64 KB    per-fn #regalloc flags
0x18C100  compiler state ~80 KB   scalars, struct / patch / jump tables, gvar_toks (0x198000), field tables (0x1FC000, v6.0.47)
0x21A000  str_data        2 MB    string-literal bytes
0x41A000  codebuf         3 MB    generated machine code (INITIAL base — growable @ v6.2.0, 64 MiB ceiling)
0x9BA000  fn tables     ~256 KB   INITIAL base — growable @ v6.2.0 (8192 → 32,768 ceiling; names / offsets / params / masks / …)
0x107B000 fixup_tbl      16 MB    INITIAL base — growable @ v6.2.0 (1,048,576 → 64M-entry ceiling)
0x2D7C000 tok_types       8 MB    1,048,576 token type slots
0x357C000 tok_values      8 MB    1,048,576 token value slots
0x3D7C000 tok_lines       8 MB    1,048,576 token line slots
0x459D000 preprocess_out  8 MB    include / #derive expansion buffer
0x4D9D000 output_buf     16 MB    ELF / Mach-O / PE output (heap-top; cap 2 MB → 16 MB v6.1.27)
0x5D9D000 local tables  512 KB    4 slot-indexed per-fn tables × 128 KB (relocated here @ v6.1.40, CVE-24)
0x5E1D000 brk-final     ~94.1 MB  heap end (v6.1.40 local-table relocate; v6.1.27 output_buf; monotonic 0x0 → brk)
```

### Preprocessing scratch (overlays `tok_types`, 0x13E000–0x23E000)

The `#derive` / include preprocessing pass runs **before** tokenization, so it
scratch-uses part of the `tok_types` 1 MB region (which holds no live token data
until tokenization repopulates it after preprocessing finishes):

```
0x190800.. #ifdef/macro/include preprocessor state (hashes, def text, flags)
0x197000   derive struct count (8B), op, field_count, cumul_off, sname[64]
0x197F00   include count (8B)   — persistent; callers in main*.cyr / util.cyr
0x197F10   pp_state nesting     (64B)
0x198000   gvar_toks[8192]      — deferred global-var inits (NOT preprocessing scratch; persistent)
0x1FC000   field_names[256][32] (8KB)   v6.0.47 field-table band
0x1FE000   field_types[256][32] (8KB)
0x200000   field_offsets[256][8] (2KB; ends 0x200800)
```

v6.0.53 raised the per-file `#derive` cap 64 → 512 (libro `-D LIBRO_TPM` pulls 66
`#derive` structs — the *real* TPM blocker, distinct from the 256→1024 type-table
cap; see issue 2026-06-03-derive-struct-cap-64-is-real-tpm-blocker.md). The
`sizes[512]`/`names[512*32]` tables (20 KB) are **`alloc()`'d from the heap**, NOT
fixed S-offsets: the old `0x197500`/`0x197700` slot fit only 64, and the scratch
band is packed solid (a first cut that relocated them to a fixed `0x198000`
clobbered `gvar_toks` → CI SIGILL). Heap alloc (post-brk) is collision-free.

## Consequences

- Fixed capacity limits remain for tokens (1,048,576), vars (8192), `#derive` structs (512), globals (1024); **fn-tables, fixup_tbl, and codebuf are growable since v6.2.0** (see Status Update above)
- Buffer overflow bugs are silent corruption — always add bounds checks
- Relocating buffers requires two-step bootstrap (see ADR-005: Two-Step Bootstrap for Compiler Changes)
- Adjacent buffers with no guard bytes are time bombs (tok_names overflow, v0.9.2)
- Heap consolidation (v2.1) saved 2MB by compacting scattered regions
