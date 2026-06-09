# ADR-003: Fixed Heap Layout over Dynamic Allocation

**Status**: Accepted
**Date**: 2026-03-28
**Context**: The compiler needs storage for tokens, names, variables, functions, and code.

## Decision

Use fixed-offset heap arrays allocated via a single `brk` syscall. No malloc, no free, no dynamic resizing within a compilation run.

## Rationale

- **Determinism**: Same input always produces same memory layout
- **No allocator needed**: The compiler itself has no alloc library dependency
- **Speed**: Direct offset calculation, no pointer chasing
- **Auditability**: Every buffer has a known address documented in the HEAP MAP

## Layout (summary — reconciled v6.0.73)

The **authoritative** registry is the `HEAP MAP` comment block in
`src/main.cyr` (lines 10–391, 84 regions, verified monotonic + overlap-free
by `tests/heapmap.sh`). This ADR keeps only a high-level summary; when the
two disagree, **`src/main.cyr` wins**. Major regions, in offset order:

```
0x00000   input_buf       1 MB    raw stdin source (tok_names nested at 0x60000)
0x60000   tok_names     256 KB    packed identifier strings (rebuilt by LEX)
0x12A000  var tables    ~128 KB   8192 vars (offsets / sizes / types)
0x14A000  fn_regalloc    64 KB    per-fn #regalloc flags
0x18C100  compiler state ~80 KB   scalars, struct / patch / jump tables, gvar_toks (0x198000), field tables (0x1FC000, v6.0.47)
0x21A000  str_data        2 MB    string-literal bytes
0x41A000  codebuf         3 MB    generated machine code
0x71A000  output_buf      2 MB    ELF / Mach-O / PE output
0x9BA000  fn tables     ~256 KB   4096 functions (names / offsets / params / inline / …)
0x107B000 fixup_tbl      16 MB    1,048,576 fixup entries × 16 bytes
0x2D7C000 tok_types       8 MB    1,048,576 token type slots
0x357C000 tok_values      8 MB    1,048,576 token value slots
0x3D7C000 tok_lines       8 MB    1,048,576 token line slots
0x459D000 preprocess_out  8 MB    include / #derive expansion buffer
0x4D9D000 brk-final     ~77.6 MB  heap end (v5.11.68 reorg; monotonic 0x0 → brk)
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

- Fixed capacity limits (1,048,576 tokens, 8192 vars, 4096 functions, 512 `#derive` structs, 1024 globals)
- Buffer overflow bugs are silent corruption — always add bounds checks
- Relocating buffers requires two-step bootstrap (see ADR-005: Two-Step Bootstrap for Compiler Changes)
- Adjacent buffers with no guard bytes are time bombs (tok_names overflow, v0.9.2)
- Heap consolidation (v2.1) saved 2MB by compacting scattered regions
