# `lib/alloc.cyr` brk(2) bump-heap collides with glibc malloc's brk arena under `fdlopen` libssl — process SIGSEGV

> **RESOLVED v6.1.19** — the Linux heap is now an anonymous-`mmap` chunk-based
> bump allocator (no `brk`), so it can't collide with glibc malloc's arena. The
> repro runs all 8 iterations clean. See CHANGELOG [6.1.19].

**Discovered:** 2026-06-09 during sandhi 1.4.5 P1 triage (hoosh v2.2.0 remote-provider gateway crashing after a few HTTPS requests)
**Severity:** Critical — process-fatal heap corruption; crashes any program that grows the brk heap while the `fdlopen`-libssl TLS backend is loaded
**Affects:** cycc 6.1.18 (and back through the whole `lib/fdlopen.cyr` + `lib/alloc.cyr` Linux era; not native-TLS-specific)

## Summary

On Linux, `lib/alloc.cyr`'s bump allocator grows its heap with the raw
`brk(2)` syscall (syscall 12). `lib/tls.cyr`'s default (libssl) backend loads
`libssl.so.3` + `libcrypto.so.3` via `lib/fdlopen.cyr`, which bootstraps the
**real glibc** dynamic loader. All of libssl's internal allocations then go
through **glibc malloc**, whose main arena is *also* managed via `brk`/`sbrk`.

Two independent managers now own the single program break. While the cyrius
bump heap stays inside its initial 1 MB reservation they don't interact. The
first time the cyrius heap grows — its first `brk(new_end)` after the initial
reservation — it collides with glibc malloc's arena. The result is heap/stack
corruption: a subsequent libssl call dereferences a pointer into unmapped
(or clobbered) memory and the process **SIGSEGVs inside `libssl.so.3`** with a
smashed call stack.

This was reported downstream as a "sandhi TLS lifecycle bug" (sandhi
`docs/issues/2026-06-09-https-repeated-request-segfault.md`), but it reproduces
with **zero sandhi code** — pure `lib/alloc.cyr` + `lib/tls.cyr` — so it is a
stdlib-side issue.

## Reproduction

`docs/development/issues/repros/2026-06-09-brk-bump-vs-fdlopen-libssl.cyr`
(self-contained; only stdlib includes).

```sh
cyrius build docs/development/issues/repros/2026-06-09-brk-bump-vs-fdlopen-libssl.cyr /tmp/brk_repro
/tmp/brk_repro
```

The program loops: open a TLS connection to 1.1.1.1:443 (loads libssl), close
it, then leak a 256 KB buffer via `alloc()` (brk) and touch every page —
roughly mirroring a consumer that leaks ~256 KB/request into `default_alloc()`.

Observed (deterministic across runs):

```
backend(0=libssl): 0
iter 0
iter 1
iter 2
iter 3
iter 4
Segmentation fault            <-- brk heap first grows past its initial 1 MB here
```

**Smoking gun:** flip `USE_MMAP = 1` in the repro (leak via anonymous `mmap`
instead of `brk` `alloc()`) and the **crash disappears** — 8 clean iterations.
Same libssl, same handshakes, same 256 KB/iter, same page-touching. The only
change is whether the leak contends for the program break. (Confirmed with the
matching pair of sandhi-side harnesses.)

### Crash forensics (gdb)

```
#0  0x00007ffff7325397 in ?? ()        <- inside libssl.so.3 r-xp segment
#1  0x0000000000000034 in ?? ()        <- smashed return address
rip 0x7ffff7325397   rdi 0x6aadf0  rax 0
=> mov (%rdi),%ecx                      <- libssl deref of a clobbered pointer
```

`info proc mappings` at the crash:

```
0x000000000044c000 0x0000000000600000  rw-p  [heap]   <- cyrius brk heap ends at 0x600000
... huge free gap ...
0x00007ffff72fd000 ...                  r-xp  /usr/lib/libssl.so.3
```

`rdi = 0x6aadf0` is ~700 KB **past** the mapped heap end (`0x600000`), yet the
allocator handed it out — i.e. cyrius's `_heap_ptr` advanced while the actual
`brk` (shared with glibc) did not track it. There is plenty of free virtual
space above `0x600000`, so this is contention/clobber, not address-space
exhaustion.

## Root cause

`lib/alloc.cyr` (Linux block), `alloc()` grow path:

```
if (_heap_ptr > _heap_end) {
    var new_end = (_heap_ptr + 0xFFFFF) & (0 - 0x100000);
    var result = syscall(12, new_end);     # brk(new_end)
    if (result < new_end) { _heap_ptr = ptr; _alloc_lock_release(); return 0; }
    _heap_end = new_end;
}
```

`brk` is a **process-global** resource. glibc malloc (linked in transitively by
`fdlopen` → libssl) assumes it owns `brk`/`sbrk` for its main arena. cyrius's
direct `brk` calls move the break out from under glibc (or vice versa), so one
allocator's "owned" region is silently reused/unmapped by the other. The
initial 1 MB reservation in `alloc_init()` masks it until the first grow — which
is exactly when consumers that accumulate state (sandhi's `default_alloc()`
leaks ~256 KB/request, so request #4) tip over.

This is fundamental: **any** brk-based bump allocator is incompatible with a
glibc-malloc-using shared library loaded into the same process. It is not
libssl-specific — it will bite any future `fdlopen`/`dlopen` of a glibc
consumer.

## Proposed fix

Make the Linux `lib/alloc.cyr` heap **mmap-backed** instead of `brk`-backed:
grow by `mmap(MAP_ANONYMOUS | MAP_PRIVATE)` chunks (rounded to a grain) and bump
within them, never touching the program break. Anonymous mappings can't collide
with glibc's brk arena. The file already anticipates this — see the comment near
the `bump`/region note ("A future variant could be mmap-backed for true …").
This removes the contention for **all** backends (it also future-proofs any
`fdlopen` of other glibc libraries), independent of the native-TLS work.

Note: the sovereign native TLS path (`-D CYRIUS_TLS_NATIVE`) sidesteps this by
not loading glibc/libssl at all (confirmed: the repro built native does **not**
crash). But the mmap-backed heap fix is still wanted so the libssl backend isn't
a latent process-killer, and so any other `fdlopen` consumer is safe.

## Consumer-side workaround (sandhi)

sandhi 1.4.5 hard-defaults to the native TLS backend (`tls_set_backend`) and
relegates libssl to an explicit opt-in flag, which avoids loading glibc malloc
on the default path. Consumers that must use the libssl backend should avoid
unbounded growth of `default_alloc()` (pass a per-request `mmap`-backed arena to
the `_a` variants) — but that only delays the first brk-grow, it does not fully
remove the hazard. The real fix is the mmap-backed heap above.
