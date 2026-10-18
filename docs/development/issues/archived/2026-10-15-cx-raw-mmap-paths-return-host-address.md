# cx: two raw `syscall(SYS_MMAP)` paths still hand back a HOST address as success — `mmap_stack` and freelist's `_fl_mmap` — RESOLVED

> ✅ **RESOLVED in v6.7.14** (LIB-5, `549e04057`. 6.7.12's D13 (the user, 2026-10-15) is extended to the two raw paths: `mmap_stack` (lib/thread.cyr) and the freelist's `_fl_mmap` each take the D13 cx arm, `#ifdef CYRIUS_TARGET_CX return 0 - 1; #endif`. In `_fl_mmap` the arm sits after the agnos arm, so agnos's mmap#27 is untouched. On cx, `mmap_stack(4096)` answers -1 (it returned a host address), and `fl_alloc(64)` / `fl_alloc(8192)` return 0, their documented failure. `fl_alloc(64)` had stopped with `cxvm: guest address out of range: <host address>`. Native, aarch64, PE and agnos builds are byte-identical. D55 (LIB-6) also keeps cxvm from mapping anything; these arms answer first, so the value is D13's -1. Rows: `tests/gates/codegen/cx_auto_call_main.sh` M1 (native, exit 33) and M2 (cx, exit 30, no `cxvm:` line), the M2 program 30 on x86_64, qemu-aarch64, wine, pi, ecb, ach and cass. Mutations: either arm removed → M2 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the merged 6.7.12 tree (build/cycc_cx + build/cxvm) by the release-docs
pass: D13's honest cx arms cover `cyr_mmap` and its callers (`mmap_anon`, `mmap_file_*`), but `mmap_stack(4096)`
(lib/thread.cyr) returns a positive host address under cxvm, and `fl_alloc(64)` through lib/freelist.cyr's `_fl_mmap`
dies "cxvm: guest address out of range: 139812091846656". The guest-contract issue's acceptance ("no wrapper reachable
on cx returns a non-guest pointer as success") is met only for the four wrappers D13 named.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — cx is a single-threaded test VM; the freelist path faults loudly.

## Fix

Route both through `cyr_mmap` (or give each the D13 cx arm: -1, the caller's `< 0` path), with cx rows beside D13's.
