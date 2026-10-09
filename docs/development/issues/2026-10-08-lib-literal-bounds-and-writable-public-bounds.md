# Literal bounds left in `lib/`: hand-kept 1024 / 64 / 40 copies, two arrays 8× their stated size, and loops bounded by writable public vars — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: every site below re-read and its line
re-derived; item 3's sizes measured (a top-level `var a[72]` spans 576 B and `var c[256]` 2,048 B — `&next - &a`
probe), and item 5 run on x86_64 Linux (`repros/2026-10-08-tlocal-max-slots-writable-bound.cyr`: after
`TLOCAL_MAX_SLOTS = 200`, `thread_local_alloc` hands out slot 165 while every slot array holds 128).
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.6 lane H (the literal-bound sweep; CHANGELOG [6.7.6] "lane H's remaining literal bounds"); filed
2026-10-08 from roadmap.md.
**Severity:** Medium for item 5 (a program that follows `thread_local_alloc`'s own "bump TLOCAL_MAX_SLOTS" advice
overruns a 128-slot array on macOS / agnos / foreign mode / Windows); Low for items 1–4.
**Affects:** cycc ≤ 6.7.6.

## Summary

6.7.6 replaced most hand-kept bounds in `lib/` with consts (an array size is a const context since 6.7.2). These
were left:

1. **agnos env blob `1024`** — the kernel's #43 env limit is a bare literal at every site, with no
   `SPAWN_ENV_MAX` beside `_SPAWN_ARGV_MAX` (`lib/syscalls_x86_64_agnos.cyr:595-597`):
   `lib/process_agnos.cyr:165` (`_agp_env_vec`: `_agp_put_elem(b, off, 1024, …)`) with its buffers `:385`, `:407`
   (`var e[1024]`); `lib/regression_agnos.cyr:95` (`_rga_env`: `_agnos_blob_ptrs(e, 0, 1024, …)`) with buffers
   `:270`, `:286`, `:314`; `lib/async_agnos.cyr:203` / `:207` (`_async_agnos_run`).
2. **`lib/regex.cyr` split tables** — `var splits: i64[64]` (`:740`) beside a literal `if (sn >= 64)` (`:744`),
   and `splits2` (`:777`) beside `sn2 >= 64` (`:781`). The pair agrees today only because both are typed by hand
   (the v6.2.1 comment records the time they did not: `[64]` was 8 slots → OOB).
3. **Two top-level arrays 8× their stated size** — a bare top-level `var x[N]` is N × 8 bytes:
   `lib/freelist.cyr:101` `var _fl_heads[72];` = 576 B for 9 size-class heads (72 B; the loop at `:163` is a
   literal `while (i < 9)`); `lib/dynlib.cyr:395` `var _dynlib_registry[256];  # 16 entries × 16 bytes` =
   2,048 B for 256 B (the cap at `:425` is a literal `>= 16`). 2,296 B of `.bss` wasted, and the comments mislead.
4. **Async kill-ctx layouts hard-code the 40-byte kill state** instead of `_PROC_KILL_STATE`
   (`lib/process.cyr:371`): `lib/async.cyr:1035` (layout comment), `:1047`, `:1053`, `:1057`, `:1108`
   (`ctx + 40` = the status word after the kill state), `:1078` (`alloc_via(a, 88)`), `:1087-1091` (`+48 … +80`);
   `lib/async_macos.cyr:529`, `:534`, `:540`, `:556` (`alloc_via(…, 72)`), `:571`. A kill state that grows
   silently overlaps the status / pidfd / timer words.
5. **Internal loops bounded by WRITABLE public vars over const-sized storage.**
   `TLOCAL_MAX_SLOTS` (`lib/thread_local.cyr:70`, a `var` initialised from `const _TLOCAL_MAX_SLOTS = 128`) bounds
   `thread_local_alloc` (`:301` — whose comment says "exhausted; bump TLOCAL_MAX_SLOTS"), the agnos serial
   `thread_create` save/restore loops (`lib/thread_agnos.cyr:66`, `:73`) over `var save: i64[_TLOCAL_MAX_SLOTS]`
   (`:64`, a STACK buffer); the storage the handed-out slots index — `_tlocal_macos` / `_tlocal_agnos` /
   `_tlocal_fallback` (`lib/thread_local.cyr:91`, `:242`, `:272`) and the Windows block (`:485`) — is sized by the
   const. (The macOS worker block, `lib/thread_macos.cyr:88-92`, is sized AND zeroed by the var, so it agrees with
   itself; the main thread's `_tlocal_macos` does not.) `TLS_REG_MAX` (`:113`, a `var` from `const _TLS_REG_MAX = 64`) bounds the
   registry scans `:130`, `:148`, `:165` over `_tls_key` / `_tls_blk[_TLS_REG_MAX]` (`:114-115`). Writing either
   var past its const makes those loops run off the end of static or stack storage.

## Reproduction

Item 5 (x86_64 Linux, where the `%fs` block is 512 slots so the store itself still lands):

```sh
cat docs/development/issues/repros/2026-10-08-tlocal-max-slots-writable-bound.cyr | build/cycc > /tmp/tl \
  && chmod +x /tmp/tl && /tmp/tl
# slot handed out: 165  storage slots (const): 128
```

On macOS / agnos / foreign mode / Windows, `thread_local_set(165, v)` then writes past a 128-slot array, and the
agnos `thread_create` copies 200 slots into a 128-slot stack buffer (not run — needs ecb / an agnos VM / cass).

Item 3: `var a[72]; var b = 0; var c[256]; var d = 0;` → `&b - &a` = 576, `&d - &c` = 2,048 (built with
`build/cycc`, exit-code probe).

Items 1, 2, 4: read the cited lines.

## Root cause

As listed — the 6.7.6 const sweep did not reach these sites. Item 5's root is the 6.7.6 split itself: the
const sizes the storage, but the public var kept for API compatibility still drives the loops.

## Proposed fix

1. `const _SPAWN_ENV_MAX = 1024;` (+ a public `var SPAWN_ENV_MAX`) in `lib/syscalls_x86_64_agnos.cyr`, used at every
   site in item 1.
2. One `const _RE_MAX_SPLITS = 64;` sizing both tables and both guards.
3. `var _fl_heads[9];` (or `: i64[_FL_NCLASSES]` with the loop bound on the same const) and
   `var _dynlib_registry[32];` / a `_DYNLIB_MAX = 16` const for the 16 × 16-byte entries. A layout change for
   programs that include these files; no semantics change.
4. Offsets from `_PROC_KILL_STATE` (`_PROC_KILL_STATE + 0` status, `+ 8` pidfd, …) and the ctx sizes from it.
5. Bound every internal loop and allocation by the CONST (`_TLOCAL_MAX_SLOTS`, `_TLS_REG_MAX`), not the var, and fix
   `thread_local_alloc`'s comment. Whether the public vars stay writable (or become read-only mirrors) is a public-API
   question — **the user's call**; bounding the loops by the const is not.
