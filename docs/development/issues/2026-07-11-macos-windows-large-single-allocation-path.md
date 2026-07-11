# macOS + Windows allocators have no path to large (>256 MiB) single allocations — cap at their fixed reservation, unlike Linux which mmaps a chunk sized to the request

**Discovered:** 2026-07-11 during the v6.4.51 `output_buf` 16 MiB→1 GiB work — cycc
SIGSEGV'd on real ecb (macOS) and failed on cass (Windows) because `alloc(1 GiB)`
returned 0 there (Linux/pi was fine).
**Severity:** Medium — v6.4.51 ships with a **platform-adaptive fallback** (Linux gets
the 1 GiB off-heap `output_buf`; macOS/Windows fall back to the fixed 16 MiB region,
i.e. their pre-.51 behavior), so nothing is broken — but the 1 GiB `output_buf` (and any
other large buffer) is **Linux-only** until this lands. **This is broader than output_buf:**
both macOS and Windows routinely handle **>1 GiB application files** (assets, media,
datasets), and a consumer that needs to `alloc` a buffer for one hits the same wall.
**Affects:** `lib/alloc_macos.cyr`, `lib/alloc_windows.cyr`. Linux (`lib/alloc.cyr`) already
handles it.
**Target:** v6.4.52.

## Root cause

| Allocator | Large-request behavior | Cap |
|---|---|---|
| **Linux** (`lib/alloc.cyr`) | `_linux_new_chunk(size)` mmaps a fresh chunk **sized to the request** (rounded to the 256 MiB grain); Linux overcommits anon mmap. | none in practice |
| **macOS** (`lib/alloc_macos.cyr:47`) | Grows the single heap via a **HINTED** 1 MiB mmap at `_heap_end`; **macOS does not honor mmap address hints**, so the first grow past the 256 MiB initial reservation returns a different base and the contiguity guard (`result != _heap_end`) **fails → returns 0**. | **256 MiB** (`_MACOS_HEAP_RESERVE`) |
| **Windows** (`lib/alloc_windows.cyr:69`) | Fixed `_WIN_HEAP_SIZE` reservation, **no grow** (`if (new_ptr > _heap_end) return 0`). | the reservation |

So on macOS/Windows any single `alloc(size)` larger than the reservation returns 0. cycc
itself never hit this before (its own allocations — codebuf 8 MiB, tables — stay well under),
which is why it surfaced only when `output_buf` tried `alloc(1 GiB)`.

## Impact

- **v6.4.51 `output_buf`**: 1 GiB on Linux; macOS/Windows fall back to the fixed 16 MiB region
  (`_output_base = S+0x4D9D000`, `_output_cap = 16777216` — see `_check_output_cap`,
  `src/common/util.cyr`). A >16 MiB single-translation-unit binary (thoth's test driver, 16.78 MB)
  compiles on Linux but is still rejected on macOS/Windows.
- **Any consumer** needing a >256 MiB (macOS) / >reservation (Windows) buffer — a large file
  mmap/read-into-buffer, a big in-memory structure — cannot allocate it today.

## Proposed fix (v6.4.52)

Give both allocators a **dedicated large-request path** that mirrors Linux's `_linux_new_chunk`:

1. **macOS** (`lib/alloc_macos.cyr`) — for a request that won't fit the current heap, do a
   dedicated **UNHINTED** `mmap(0, size, RW, MAP_ANON|MAP_PRIVATE)` (macOS overcommits anon mmap —
   only touched pages cost RAM) and return it directly, bypassing the hinted-grow contiguity guard.
   Old chunks stay valid (reclaimed at process exit), exactly like the Linux peer.
2. **Windows** (`lib/alloc_windows.cyr`) — for a large request, a dedicated `VirtualAlloc(NULL, size,
   MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE)` region. **Watch the eager commit**: `MEM_COMMIT` charges
   `size` against the system commit limit up front (physical pages still lazy/zero-filled). For a
   1 GiB buffer that's a big commit charge per process; if that's a problem, `MEM_RESERVE` then commit
   sub-ranges on demand (needs a fault/commit-on-write seam) — decide at implementation.

Then `output_buf`'s `alloc(1 GiB)` succeeds on all platforms → drop the .51 16 MiB fallback and make
`_output_cap` 1 GiB everywhere (remove the `if (_output_base == 0)` branch in the 6 drivers).

Verify on real **ecb (macOS)** + **cass (Windows)**: a >16 MiB binary compiles + runs, and
`alloc(1 GiB)` + touch-ends returns non-zero.

## Cross-references

- v6.4.51 `output_buf` cap raise: `docs/development/issues/2026-07-11-output-buf-16mib-cap-blocks-large-test-binaries.md`.
- The adaptive fallback landed in v6.4.51 (`_output_base`/`_output_cap`, `src/common/util.cyr`;
  the 6 native drivers' `if (_output_base == 0)` branch).
