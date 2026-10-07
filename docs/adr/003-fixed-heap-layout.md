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
*initial* base, then relocates off-heap (`alloc()`) and grows on demand (the
codebuf has since moved off-heap from the start — see its bullet):

- **fixup_tbl** — `_fixup_base` / `_fixup_grow`, 64M-entry ceiling
- **fn-tables** (16 parallel tables + the `fn_name`/`fn_start` hashes + the
  `live[]` DCE bitmap) — `_fnt_*` behind a single `_fnt_cap`, grow + rehash from
  2,048, **131,072** ceiling since v6.5.40 (it was 32,768 when this was written)
- **codebuf** — `_codebuf_base` / `_codebuf_grow`, an 8 MiB off-heap `alloc()` base
  growing in +8 MiB steps since v6.4.49 (it doubled from the fixed 3 MB region
  before), 64 MiB ceiling (the cx bytecode backend keeps its own fixed region)

v6.3.0 made the var family growable the same way (`_var_grow`, 1,048,576
entries), and v6.6.9 moved the deferred global-init list past its first 4,096
entries to doubling `alloc()` storage.

The fixed-layout rationale (determinism, auditability, no allocator in the hot
path) **still holds for the remaining regions**; the growable tables stay
input-deterministic (allocation order is a pure function of the input), so
self-host remains byte-identical. See `CHANGELOG [6.2.0]` and `util.cyr`.

## Rationale

- **Determinism**: Same input always produces same memory layout
- **No allocator needed**: The compiler itself has no alloc library dependency (true
  when decided; since v6.0.6 cycc includes `lib/alloc.cyr` + `lib/vec.cyr`, which the
  growable tables above are built on)
- **Speed**: Direct offset calculation, no pointer chasing
- **Auditability**: Every buffer has a known address documented in the HEAP MAP

## Layout (summary — re-derived from `src/main.cyr` at 6.6.20)

The **authoritative** registry is the `HEAP MAP` comment block in
`src/main.cyr` (verified monotonic + overlap-free by
`tests/gates/memory/heapmap.sh`, which counts **102 regions** at 6.6.20). This ADR
keeps only a high-level summary; when the two disagree, **`src/main.cyr` wins** —
read the map, not this table, before touching an offset.

> ⚠ **This table was five releases of relocations stale until 6.6.20** (HEAP-11 at
> the v6.6.x closeout): it still put input_buf at 0x00000, tok_names at 0x60000,
> tok_types at 0x2D7C000, output_buf at 0x4D9D000 and the heap top at 0x5E1D000,
> and called the fn ceiling 32,768 — all retired by v6.4.49–v6.5.40. Only the
> addresses below were re-derived; each region's history is in the map.

The heap is one `S + 0xF600000` (~246 MiB, lazily touched) region — `brk` on
x86-64 Linux, an anonymous `mmap` on the targets without a usable `brk`. Major
regions, in offset order (the low 0x00000–0x110000 band is free since v6.5.22 /
v6.5.40):

```
0x110000  fn hashes        32 KB    fn_name_hash + fn_start_hash (initial bases, rehashed on grow)
0x11A000  var tables      192 KB    var_noffs / var_sizes / var_types (INITIAL bases — growable @ v6.3.0, 1,048,576 ceiling)
0x14A000  (FREED band)    256 KB    v6.4.75 moved fn_regalloc / fn_ret_sid / fn_variadic / fn_flags to alloc()
0x18C100  compiler state ~568 KB    scalars, loop / patch / use-alias / pp tables, include + struct tables,
                                     enum + gvar side tables, #derive field scratch (0x1FC000–0x200800)
0x21A000  str_data          2 MB    string-literal bytes
0x41A000  (codebuf band)    3 MB    the pre-v6.4.49 in-heap codebuf; x86 / aarch64 code goes to an off-heap
                                     alloc() now — the cx backend's own fixed code region sits inside it (0x54A000)
0x71A000  file map + gvar_toks      file:line map (1024 entries) + the first 4,096 deferred global inits (0x729000)
0x91A000  struct field pools 128 KB  packed field types / names (v6.0.47)
0x93A000  fn tables       ~1 MB     INITIAL bases — growable @ v6.2.0 (2,048 → 131,072 ceiling)
0xB3A000  IR blocks / state / edges ~5 MB (CYRIUS_IR only)
0x107B000 fixup_tbl        16 MB    INITIAL base — growable @ v6.2.0 (1,048,576 → 64M-entry ceiling)
0x207B000 IR liveness       2 MB    ir_live_in / ir_live_out
0x457C000 lexid heads     ~130 KB   identifier-interning chain heads (entries live at 0xF400000)
0x459D000 preprocess_out   24 MB    include / #derive expansion buffer (v6.5.39)
0x5D9D000 local tables    512 KB    4 slot-indexed per-fn tables × 128 KB (CVE-24, v6.1.40)
0x5E9D000 IR nodes / cp    20 MB    the IR arena (v6.3.28)
0x7400000 input_buf        24 MB    raw stdin + the preprocessor's working buffer (v6.5.39)
0x8C00000 tok_types        32 MB    4,194,304 token type slots (v6.5.39)
0xAC00000 tok_values       32 MB    4,194,304 token value slots
0xCC00000 tok_lines        32 MB    4,194,304 token line slots
0xEC00000 tok_names         8 MB    packed identifier strings (v6.5.40: 512 KB @ 0x60000 → 8 MB here)
0xF400000 lexid_entries     2 MB    262,144 interning nodes
0xF600000 heap top                  S + 0xF600000
```

The final output image (ELF / Mach-O / PE) is NOT in this map: since v6.4.51–.52 it is
a 1 GiB lazily-mapped `alloc()` on every platform, and the TypeScript front end's arena
is `alloc()`-backed too (v6.4.82).

### Preprocessing scratch (inside the compiler-state band)

The `#derive` / include / `#ifdef` preprocessing pass runs **before** tokenization and
keeps its state in the compiler-state band:

```
0x190400.. include filename scratch, pp_expand_outpos, #ifdef flag table, macro tables
0x197000   derive struct count (8B), op, field_count, cumul_off, sname[64]
0x197F00   include count (8B)   — persistent; callers in main*.cyr / util.cyr
0x197F10   pp_state nesting     (one byte per #ifdef nesting level)
0x1FC000   PP #derive field-name scratch   (8KB, cap 256 fields)
0x1FE000   PP #derive field-types          (8KB)
0x200000   PP #derive field-offsets        (2KB; ends 0x200800)
```

(`gvar_toks`, which this section used to place at 0x198000, moved to 0x729000 at
v6.3.41; 0x198000 is a FREED hole.)

v6.0.53 raised the per-file `#derive` cap 64 → 512 (libro `-D LIBRO_TPM` pulls 66
`#derive` structs — the *real* TPM blocker, distinct from the 256→1024 type-table
cap; see issue 2026-06-03-derive-struct-cap-64-is-real-tpm-blocker.md). The
`sizes[512]`/`names[512*32]` tables (20 KB) are **`alloc()`'d from the heap**, NOT
fixed S-offsets: the old `0x197500`/`0x197700` slot fit only 64, and the scratch
band is packed solid (a first cut that relocated them to a fixed `0x198000`
clobbered what was then `gvar_toks` → CI SIGILL). Heap alloc (post-brk) is
collision-free.

## Consequences

- Fixed capacity limits remain for tokens (4,194,304 since v6.5.39), the identifier pool (8 MB), `#derive` structs (512) and the per-fn tables; **fn-tables, fixup_tbl and codebuf are growable since v6.2.0, the var family since v6.3.0, deferred global inits since v6.6.9** (see Status Update above). (This line said tokens 1,048,576, vars 8192 and globals 1024 until 6.6.20.)
- Buffer overflow bugs are silent corruption — always add bounds checks
- Relocating buffers requires two-step bootstrap (see ADR-005: Two-Step Bootstrap for Compiler Changes)
- Adjacent buffers with no guard bytes are time bombs (tok_names overflow, v0.9.2)
- Heap consolidation (v2.1) saved 2MB by compacting scattered regions
