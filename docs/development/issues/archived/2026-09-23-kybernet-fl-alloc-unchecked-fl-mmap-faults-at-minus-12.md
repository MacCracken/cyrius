# `fl_alloc` stores through an unchecked `_fl_mmap` return: a refused mapping faults at address -12 instead of returning 0 — OPEN

**Status:** ✅ **RESOLVED v6.6.7** (bite 8) — `fl_alloc` checks its large-path and refill mappings and returns 0 on refusal. The filed 1 GiB repro under `ulimit -v 600000` now prints `returned` / `p == 0` and exits 0 (was 139, fault at -12).
**Placement:** **6.6.7 bite 8** — kybernet PID-1 stdlib and same-class unchecked allocs: non-blocking hash seed; checked fl_alloc mappings; bounded, checked file_read_whole; checked hashmap_fast and flags growth. Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-08-25 during kybernet 1.5.9, reading sigil's Argon2 wrappers. Reproduced
2026-09-23 during kybernet 1.7.8.
**Severity:** Medium: a crash where the API promises an error value, with a known workaround.
**Affects:** cycc 6.6.6 (checked). Earlier releases not checked.

## Summary

`_fl_mmap` returns the raw `mmap` result. On failure that is a small negative errno (-12 for
ENOMEM), not 0. `fl_alloc`'s large-allocation path writes its block header through it on the next
line, so a refused mapping becomes a SIGSEGV at `0xfffffffffffffff4` rather than a 0 the caller could
test. Callers that do test for 0 never get the chance. sigil's `argon2id` / `argon2i` / `argon2d`
wrappers allocate their arena through `fl_alloc` and then check `if (mem == 0)`, and sigil's own
comment on those wrappers warns that the guard cannot fire for this reason.

`alloc()` in `lib/alloc.cyr` already handles the same case: `_linux_new_chunk` returns 0 when `base <
0`, and `alloc` returns 0 from there.

## Reproduction

```cyrius
include "lib/thread_local.cyr"

fn main() {
    alloc_init();
    var p = fl_alloc(1073741824);   # 1 GiB: the large (direct mmap) path
    sys_write(1, "returned\n", 9);
    if (p == 0) { sys_write(1, "p == 0\n", 7); }
    return 0;
}
```

Built in kybernet's tree with cycc 6.6.6. With room to map, it prints `returned`. Under an
address-space limit that refuses the mapping:

```sh
(ulimit -v 600000; ./probe; echo "exit=$?")          # exit=139, nothing printed
```

`qemu-x86_64 -strace` under the same limit:

```
mmap(NULL,268435456,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = 0x00007fa708000000
mmap(NULL,1073741840,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = -1 errno=12 (Cannot allocate memory)
--- SIGSEGV {si_signo=SIGSEGV, si_code=1, si_addr=0xfffffffffffffff4} ---
```

The first mapping is `alloc_init`'s arena. The second is `fl_alloc`'s, and the fault address is -12.

## Root cause

`lib/freelist.cyr` (6.6.6 snapshot), the large path in `fl_alloc`:

```cyrius
var total = csize + 16;
var blk = _fl_mmap(total);
store64(blk, 0);
store64(blk + 8, total);
```

and the arena refill in `_fl_arena_alloc`:

```cyrius
_fl_arena = _fl_mmap(FL_ARENA_SIZE);
_fl_arena_pos = _fl_arena;
_fl_arena_end = _fl_arena + FL_ARENA_SIZE;
```

The refill was read, not reproduced: after a refused refill the arena base is -12, and the next small
allocation hands out a pointer computed from it.

## Proposed fix

Treat a negative `_fl_mmap` return as failure at both sites, as `_linux_new_chunk` does. In the large
path, return 0 before touching the block. In the refill, return 0 and leave the previous arena state
alone, so a later call can retry rather than bumping through a bad base.

## Consumer-side workaround

kybernet does not use `fl_alloc`'s large path in PID 1. Its Argon2 goes through sigil's `argon2id_into`
over an arena from `alloc()`, sized with `argon2_mem_bytes` (kybernet's CLAUDE.md, standing rule 24).
Any consumer can do the same: for a large buffer that may fail, allocate with `alloc()` and check
for 0.
