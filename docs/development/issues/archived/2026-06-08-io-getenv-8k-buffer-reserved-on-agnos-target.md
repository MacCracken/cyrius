# `lib/io.cyr` `getenv()` reserves its 8 KB `var buf[8192]` on the agnos target — frame is allocated past the `#ifdef CYRIUS_TARGET_AGNOS` early-return

- **Filed**: 2026-06-08
- **Reporter**: agnoshi (surfaced by the `agnoshi_147` iron burn on archaemenid, agnos 1.43.7)
- **Affects**: `lib/io.cyr` `getenv()` when built with `CYRIUS_TARGET_AGNOS`. Pin context: agnoshi pinned cyrius **6.0.87** (the pin that introduced the agnos `getenv()`/`_agnos_getenv` branch).
- **Severity**: **HIGH for the agnos target.** agnos gives a ring-3 process only ~12 KB of init stack (`agnos/kernel/core/elf.cyr`: rsp starts at stack offset `0x3000`), so an unintended 8 KB frame in a leaf helper is enough to overflow it. Same *class* as the `cyml.cyr` var-array stack overflow fixed in 6.0.79 (oversized function-local `var[]` on a constrained target), here triggered by frame allocation surviving a dead branch rather than by a single oversized buffer.

## Symptom

agnsh (agnoshi 1.4.6+) booted cleanly on real hardware all the way to its banner, then **hung with no prompt** — a ring-3 #PF immediately after the banner, before the first prompt render. Boot was otherwise healthy (ext2/jbd2/FAT mount → scheduler → real DHCP lease → `kybernet: exec /bin/agnsh` → full banner → dead).

The first thing agnsh does after the banner is call `history_path()`, which calls `getenv("HOME")`. That single call overflowed the ring-3 stack.

## Root cause

`lib/io.cyr` `getenv()` is shaped:

```cyrius
fn getenv(name): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return _agnos_getenv(name);      // agnos: buffer-free envp walk, returns here
    #endif
    var buf[8192];                   // <-- NOT guarded; compiled into the agnos frame too
    var fd = file_open("/proc/self/environ", 0, 0);
    ...
}
```

The `var buf[8192]` (8 KB function-local — `N` bytes at function scope) sits **after** the `#endif`, so it is **not** excluded from the agnos build. On agnos the function returns at `return _agnos_getenv(name);` and never *uses* `buf`, but the prologue still **reserves** the 8 KB (frame size is fixed at function entry, independent of which `return` executes). So every `getenv()` call on agnos pushes an 8 KB frame for a buffer it never touches.

agnos hands ring-3 only ~12 KB of stack below the initial rsp; agnoshi's `interactive_loop` already holds a `var buf[4096]`, so the extra 8 KB frame from the first `getenv` call overflowed → ring-3 #PF.

## Consumer stopgap (already applied in agnoshi 1.4.8)

agnoshi stopped calling `getenv` on agnos in the two affected helpers (`history_path`/`audit_log_path` now return the static `/.agnsh_history` / `/.agnsh_audit.log` under `#ifdef CYRIUS_TARGET_AGNOS`, since the kernel default env is always `HOME=/`). This unblocks the agnsh prompt but means **no agnos consumer can safely call `getenv` until the stdlib is fixed** — any agnos program that calls `getenv` eats an 8 KB phantom frame.

## Resolution path (Cyrius-side — two parts)

1. **Immediate stdlib fix (primary ask):** guard the `var buf[8192]` (and the rest of the `/proc/self/environ` reader) behind `#ifndef CYRIUS_TARGET_AGNOS` so the agnos build's `getenv()` frame carries nothing but the early `return _agnos_getenv(name)`. After this, agnos consumers can call `getenv` freely.

2. **Compiler consideration (secondary, optional):** the broader pattern is that a function-local `var[]` declared in a statically-dead region (here, code after an unconditional `#ifdef`-gated `return`) still contributes to the reserved frame. If `cycc` scoped frame reservation to reachable locals — or at least dropped locals that are provably never live on the taken path — this class of "dead buffer still reserves stack" bug would not recur. Lower priority than (1); the `#ifndef` guard fully resolves the reported case. Related prior art: the 6.0.79 `cyml.cyr` var-array stack-overflow fix.

## Resolution (Cyrius 6.1.12, 2026-06-08)

Part 1 (the primary ask) shipped: the `/proc/self/environ` reader — `var buf[8192]`
and the parse loop — is now guarded behind `#ifndef CYRIUS_TARGET_AGNOS`, so the
agnos `getenv()` carries nothing but `return _agnos_getenv(name)`. agnos consumers
can call `getenv` freely again.

**Mechanism correction (verified on the real `--agnos` build, not assumed).** The
8 KB is **not a stack frame** — in cycc a function-local `var[]` of this size is
allocated in **`.bss` static storage**. Confirmed by section deltas before/after
the guard on an agnos-target build:

- `.bss`: `0x2f18` → `0xf08` (−8,208 B — the `buf` + alignment)
- `.text`: −928 B (the now-dead environ-reader code)
- no `sub rsp, 0x2000` ever existed; the max frame is unchanged at `0xd0`.

So the agnos #PF the symptom describes is **`.bss`-image / loader-mapping
related, not init-stack overflow**. The fix still fully resolves the reported
case (the phantom buffer is gone), but the agnos-side note about widening the
ring-3 init stack (`elf.cyr` rsp `0x3000`) is aimed a layer off — if a latent
cliff remains it'll be in how the loader maps an oversized `.bss`/PT_LOAD memsz,
not the stack. Part 2 (compiler-side dead-region storage elision) remains the
lower-priority follow-on it was filed as.

## Cross-references

- Consumer fix: agnoshi 1.4.8 CHANGELOG (`history_path`/`audit_log_path` no-getenv-on-agnos).
- agnos ring-3 init-stack size: `agnos/kernel/core/elf.cyr` (rsp = stack offset `0x3000`). The constrained stack is itself a latent cliff worth widening agnos-side, but that is an agnos concern, not Cyrius — noted here only to explain why an 8 KB phantom frame is fatal rather than merely wasteful.
