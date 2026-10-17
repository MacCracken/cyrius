# cx: two raw `syscall(SYS_MMAP)` paths still hand back a HOST address as success — `mmap_stack` and freelist's `_fl_mmap` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the merged 6.7.12 tree (build/cycc_cx + build/cxvm) by the release-docs
pass: D13's honest cx arms cover `cyr_mmap` and its callers (`mmap_anon`, `mmap_file_*`), but `mmap_stack(4096)`
(lib/thread.cyr) returns a positive host address under cxvm, and `fl_alloc(64)` through lib/freelist.cyr's `_fl_mmap`
dies "cxvm: guest address out of range: 139812091846656". The guest-contract issue's acceptance ("no wrapper reachable
on cx returns a non-guest pointer as success") is met only for the four wrappers D13 named.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — cx is a single-threaded test VM; the freelist path faults loudly.

## Fix

Route both through `cyr_mmap` (or give each the D13 cx arm: -1, the caller's `< 0` path), with cx rows beside D13's.
