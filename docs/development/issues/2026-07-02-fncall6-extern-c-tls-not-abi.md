# "Class B FFI / `fncall6` ABI bug" was a misdiagnosis — the real issue is TLS/`%fs`

**Filed:** 2026-07-02 (investigating the scheduled v6.3.26 slot)
**Severity:** Low (the ABI is correct) / the coexistence fix is Medium.
**Component:** `lib/fnptr.cyr` (fncallN), `lib/thread_local.cyr` (`%fs` install),
mabda wgpu C hooks (consumer, separate repo).

## The scheduled premise was false

v6.3.26 was carried from v5.9.x–v5.11.x as *"fix Cyrius's `fncall6` vs SysV AMD64
calling-convention bug that mabda's wgpu integration needs."* There is **no such
bug**. Proven empirically (a real gcc-compiled, stack-protected C library called
from cyrius):

- `fncall4/5/6/7` arg-passing (`rdi,rsi,rdx,rcx,r8,r9`) is correct.
- The stack is correctly **16-byte aligned** at the `call` (disasm: `push rbp` +
  16-multiple frame; a C callee reads `rbp & 15 == 0`, i.e. incoming `%rsp % 16
  == 8`, exactly SysV).
- A stack-protected C function taking 4/5/6/7 integer args **returns the right
  result** via `fncallN` — once a glibc-compatible `%fs` exists.

## The real mechanism

Any glibc-compiled C function with an array/buffer local carries
`-fstack-protector` → its prologue is `mov %fs:0x28, %rax` (canary read). If `%fs`
is not a glibc thread block, that faults **regardless of arg count**. It merely
*correlated* with mabda's 6-arg wgpu entry points (`copy_buffer_to_buffer`,
`resolve_query_set`, `queue_write_texture`) because those have local buffers.
mabda's "pack args into a struct, call `fncall2` instead of `fncall6`" workaround
sidestepped it only by accident. This is the same root cause ADR-004 cites for the
C launcher (*"calling libc's dlopen from a non-libc process crashes — TLS not
initialized"*).

Third consecutive consumer misdiagnosis (v6.3.24 string-global→enum-shadow, v6.3.25
TLS-state→slot-collision, this one fncall6-ABI→TLS).

## Fix (shipped v6.3.26)

The C-launcher model already gives glibc's `%fs`, so the wgpu C-hook path works
today. The residual hazard is cyrius **clobbering** that `%fs`: `thread_local_init`
does `arch_prctl(ARCH_SET_FS, cyrius_block)`, and `thread_local_set(5, …)` writes
`%fs:0x28` — either wipes the host canary / self-pointer and breaks every
stack-protected C callee. This bites any process combining wgpu C hooks with a
cyrius lib that uses thread-locals (sigil crypto banking, patra).

- **`thread_local_use_foreign_tls()`** (`lib/thread_local.cyr`) — the glibc-hosted
  consumer declares itself once at startup; cyrius then leaves `%fs` untouched and
  keeps slots in a process-global fallback array (macOS/agnos path). **Explicit,
  not auto-detected** — a native `CLONE_SETTLS` worker also has non-zero `%fs`, so
  `fs != 0 => foreign` would misclassify native workers and collapse per-thread
  crypto lanes (v6.3.25 class). Native path unchanged / byte-identical behavior.
- **Gate** `tests/ffi_stack_protected_extern_c.sh` (check.sh): stack-protected
  extern-C via `fncall4/5/6/7` + foreign-`%fs` no-clobber / canary-intact proof.
- **Docs**: `lib/fnptr.cyr` header + `docs/ffi/fncall-abi.md` "Extern-C
  prerequisite" section.

cycc byte-identical (lib/doc/test only — neither `fnptr.cyr` nor `thread_local.cyr`
is compiled into the compiler).

## Consumer follow-up (mabda, separate repo — user's call)

With the ABI proven correct and `thread_local_use_foreign_tls()` available, mabda
can (a) drop the struct-packing `fncall2`-instead-of-`fncall6` workarounds and use
the natural wgpu C signatures directly, and (b) call `thread_local_use_foreign_tls()`
in `deps/wgpu_main.c` (or `mabda_main`) if it links any cyrius thread-local user.
Not required for correctness today; it's backwards-compat cleanup for the NVIDIA
wgpu route's remaining life (through mabda v5.0, ADR-006).

## Open follow-up

Foreign mode is process-global (single cyrius-thread assumption inside the host).
A foreign multi-threaded consumer would need a pthread-key-backed per-thread block.
Tracked; no consumer needs it yet.
