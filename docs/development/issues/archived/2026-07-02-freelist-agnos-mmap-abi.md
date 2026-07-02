# stdlib `freelist` allocator is not agnos-aware — 6-arg mmap → `mmap(0)` → SIGSEGV

> **STATUS: ✅ RESOLVED (v6.3.31).** `_fl_mmap(length)` dispatcher added to `lib/freelist.cyr` (`#ifdef CYRIUS_TARGET_AGNOS → syscall(SYS_MMAP, length)`, else 6-arg); both alloc sites route through it. cycc byte-identical; Linux round-trip=42; consumer-verified on real agnos. Gate `tests/freelist_agnos_mmap.sh`. See CHANGELOG [6.3.31].

**Filed**: 2026-07-02 · **Component**: `lib/freelist.cyr` (`fl_alloc` / `fl_calloc` / arena) · **Severity**: high (crashes every agnos `fl_alloc` consumer on first use) · **Confirmed on**: cyrius **6.3.30** (the current pin, 2026-07-02) — source lines 95 + 113 still carry the 6-arg mmap; minimal repro below SIGSEGVs.

## Minimal reproduction (cyrius 6.3.30)

```cyrius
include "lib/syscalls.cyr"
include "lib/freelist.cyr"
fn main(): i64 {
    var p = fl_alloc(32);              # freelist alloc -> the arena mmap (line 95)
    if (p == 0) { var m = "FL-NULL\n"; sys_write(1, m, 8); return 1; }
    store64(p, 42);                    # deref -> SIGSEGV on agnos (p came back 0)
    var msg = "FL-OK\n"; sys_write(1, msg, 6);
    return 0;
}
fn _entry(): i64 { var r = main(); syscall(SYS_EXIT, r); return 0; }
_entry();
```

```
$ cyrius build --agnos flrepro.cyr flrepro      # current pin 6.3.30, unpatched stdlib freelist
OK
$ mirshi ./flrepro                              # runs the agnos ELF, no QEMU
$ echo $?
139                                             # SIGSEGV — crashed before printing FL-OK/FL-NULL
```

Prints nothing (crashes inside `fl_alloc`, before the `FL-OK`/`FL-NULL` write). With the fix
below applied to the toolchain's `lib/freelist.cyr`, the same program prints `FL-OK` and exits 0.

## Symptom

Any agnos-target program whose first `fl_alloc` fires SIGSEGVs immediately. Found via the
agnosticos **mirshi-fanout** work running `cyrius-yeomans-descent` under mirshi: descent loads its
world, then crashes in `persist_init` at libro's `chain_new()` → `fl_alloc(32)` → the freelist
**arena mmap**. Same crash on a freshly rebuilt binary (6.3.28/6.3.30). Fault: `mov %rax,(%rcx)` with
`rcx = 0` — i.e. the mmap returned 0 and the very next store dereferenced it.

This is **not** mirshi's fault: mirshi's `mmap#27` is correct (a `sys_mmap(2 MB)` test + a 48 MB
many-chunk alloc-stress both pass under mirshi), and it matches the agnos kernel ABI.

## Root cause

`lib/freelist.cyr` handles the macOS `MAP_ANON` divergence (`_fl_map_flags`, `#ifdef
CYRIUS_TARGET_MACOS`) but **not** the agnos mmap ABI. Both mmap sites use the Linux/BSD 6-arg form:

```cyrius
# _fl_arena_alloc (arena, small allocations)
_fl_arena = syscall(SYS_MMAP, 0, FL_ARENA_SIZE, prot, flags, 0 - 1, 0);
# fl_alloc large path
var blk   = syscall(SYS_MMAP, 0, total,         prot, flags, 0 - 1, 0);
```

Here the **length is arg2 (`rsi`)** and arg1 (`rdi`) is `addr = 0`. But **agnos `mmap#27` is
single-arg** — the kernel reads the length from **arg1 (`rdi`)** and ignores addr/prot/flags/fd/off
(always anonymous R/W; `kernel/core/syscall.cyr`: `if (num == 27) return sys_mmap(arg1)`, and
`lib/syscalls_x86_64_agnos.cyr`: `fn sys_mmap(length) { return syscall(SYS_MMAP, length); }`). So on
agnos the freelist calls `mmap` with `arg1 = 0` → the kernel sees **length 0** → returns 0
(MAP_FAILED) → the caller's first `store64` hits address 0.

Every agnos `fl_alloc` consumer is affected — libro's audit chain (`chain_new` → `fl_alloc`) and
sigil's crypto (`sha256`/`x25519`/`hex_decode`, per the existing macOS note in `_fl_map_flags`) —
so the whole libro/sigil surface is non-functional on agnos.

## Fix

Dispatch the mmap by target, exactly like `_fl_map_flags` does, and route both sites through it:

```cyrius
fn _fl_mmap(length): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return syscall(SYS_MMAP, length);          # agnos mmap#27: length in arg1, anon R/W
    #endif
    var prot = PROT_READ | PROT_WRITE;
    var flags = _fl_map_flags();
    return syscall(SYS_MMAP, 0, length, prot, flags, 0 - 1, 0);
}
```

- `_fl_arena_alloc`: `_fl_arena = _fl_mmap(FL_ARENA_SIZE);`
- `fl_alloc` large path: `var blk = _fl_mmap(total);`

Verified: with this fix vendored into `libro/lib/freelist.cyr` + `cyrius-yeomans-descent/lib/freelist.cyr`,
descent rebuilds, `persist_init` completes (`persist: player saves + audit chain ready`), the server
binds `:4000`, and a telnet client reaches the login banner under mirshi.

## Note

The fix was applied to the **vendored** copies (`libro/lib/`, descent `lib/`) as an interim so descent
runs today — but those are stdlib mirrors and a `cyrius lib sync` reverts them. The canonical fix
belongs here in `lib/freelist.cyr`; once it lands, the consumers re-sync and drop their local patch.
