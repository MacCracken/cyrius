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

## Layout (v2.6, consolidated from v0.9.5)

```
0x00000  input_buf      128KB    Source text
0x20000  codebuf        256KB    Generated machine code
0x60000  tok_names       64KB    Identifier strings (dedup)
0x8A000  struct tables    24KB   Field types, names, counts
0x8C100  compiler state   14KB   Counters, scalars, patches
0x98000  gvar_toks        8KB    1024 deferred global inits
0xA0000  fixup_tbl      128KB    8192 fixup entries × 16 bytes
0xC0000  fn tables        48KB   names, offsets, params, inline
0xCC000  struct_fnames    8KB    32×32 field name offsets
0xCE000  output_buf     256KB    ELF output
0x10E000 var tables     192KB    8192 vars (noffs, sizes, types)
0x13E000 tok_types        1MB    131072 token type slots
0x23E000 tok_values       1MB    131072 token value slots
0x33E000 tok_lines        1MB    131072 token line number slots
0x43E000 preprocess_out 512KB    Include expansion buffer
brk: 0x4BE000 (~4.7MB total)
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

- Fixed capacity limits (131072 tokens, 8192 vars, 1024 functions, 256 locals, 1024 globals)
- Buffer overflow bugs are silent corruption — always add bounds checks
- Relocating buffers requires two-step bootstrap (ADR documented in vidya)
- Adjacent buffers with no guard bytes are time bombs (tok_names overflow, v0.9.2)
- Heap consolidation (v2.1) saved 2MB by compacting scattered regions
