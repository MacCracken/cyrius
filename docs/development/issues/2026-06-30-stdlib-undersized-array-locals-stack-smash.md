# stdlib — undersized `var X[N]` array locals stack-smash under v6.3.13 stack-allocated locals (incomplete sweep)

**Status**: ⏳ **OPEN — incoming from the AGNOS base-stack migration.** Filed 2026-06-30. **Cyrius-side; stdlib source fix.** The `var X[N]` **function-local → thread-stack** change (v6.3.13, `THREAD_STACK_SIZE` 64 KB→2 MB + `PROT_NONE` guard page) turned a class of **latent undersized-buffer overflows in the stdlib's own modules** into hard `SIGSEGV`s. The sweep that accompanied v6.3.13 was **incomplete**: `bench.cyr` was fixed (`var ts[2]`→`var ts[16]`) and the `argv[4]`/`envp[1]` cases were fixed back at v5.11.60 (see `process.cyr:39` comment), but **`process.cyr` / `pam.cyr` / `regression.cyr` / `shadow.cyr` / `net.cyr` / `tls.cyr` / `yukti.cyr` still ship undersized 1-byte locals** written 4–8 bytes.
**Date**: 2026-06-30
**Priority**: **High (ecosystem-wide, latent).** Every consumer that reaches these stdlib paths (any `sys_waitpid` / subprocess reap via `process.cyr` or `regression.cyr`; PAM auth; `shadow`/passwd parse; the `net.cyr` poll/recvfrom paths; `tls.cyr`) inherits a stack-overwrite. Severity per site varies (see below) — some are 3-byte overflows that land in aligned padding today (why they were skipped), others (`shadow.cyr`'s 8-byte `store64` into 1 byte) are unambiguous.
**Where**: `cyrius/lib/{process,pam,regression,shadow,net,tls,yukti}.cyr`.
**Discovered by**: the AGNOS base-security-stack migration to 6.3.15. `majra`'s own `src/envelope.cyr` had the sibling bug — `var ts[2]` (2 bytes) taking a 16-byte `clock_gettime` write — which crashed `test_core` at `test_relay_skip_routing` (it calls `time_now_ns`) the instant its pin moved to 6.3.15. Fixing majra's own buffers made it green; an 11-repo audit then showed the *repos'* code is otherwise clean and the remaining hits are all in the **vendored stdlib** — i.e. these files.

## The rule (for reference)

A **function-local** `var X[N]` allocates exactly **N BYTES** (a module-**global** `var X[N]` is 8N bytes — those are safe). Pre-6.3.13 these locals lived in a shared global/BSS buffer, so writing past N scribbled adjacent globals and usually went unnoticed. Since 6.3.13 they are **stack-allocated with a guard page**, so any write past N bytes corrupts the stack frame (return address / saved regs / adjacent locals) or faults on the guard page → crash or silent corruption.

## Confirmed sites in the 6.3.15 stdlib

| file | lines | decl | writes | should be |
|---|---|---|---|---|
| **process.cyr** | 59, 102, 118 (`status_buf`); 191, 238, 274, 321, 367, 401, 473 (`stbuf`) | `var …[1]` (1 byte) | `sys_waitpid(pid, &buf, 0)` writes a **4-byte** `int` status; read back via `load32(&buf)` | `var …[4]` |
| **regression.cyr** | 222, 264, 320, 361, 392, 424, 519, 549, 579, 611, 670 | `var stbuf[1]` | same 4-byte `wait4` status, `load32` | `var stbuf[4]` |
| **pam.cyr** | 114 | `var status_buf[1]` | 4-byte `wait4` status, `load32` | `var status_buf[4]` |
| **shadow.cyr** | 86 | `var soff_store[1]` | `store64(&soff_store, 0)` = **8 bytes** (then `load64`/`store64` via `soff_ptr`) | `var soff_store[8]` |
| **net.cyr** | 594 (`pfd`), 600 (`sb`), 601 (`slen`) | `var …[1]` | poll-fd / socket-len buffers (verify per-site: a `pollfd` is 8 bytes; a `socklen_t` is 4) | size to the struct/socklen |
| **tls.cyr** | 1070 (`written`), 1088 (`rdb`) | `var …[1]` | verify per-site (looks like a length/byte in/out param) | size to the write width |
| **yukti.cyr** | 3266 | `var src_len[1]` | `store32(&src_len, 12)` (4 bytes) + passed as the `recvfrom` `socklen_t*` addrlen | `var src_len[4]` |

Cross-check: the sibling parsers already use the correct size — `pwd.cyr:112` and `grp.cyr:90` both declare `var soff_store[8]`, so `shadow.cyr:86`'s `[1]` is a clear miss.

## Severity nuance (why some were skipped)

The `wait4` status cases overflow by **3 bytes**; with 8-byte stack-slot alignment those 3 bytes usually land in the same slot's padding, so they are latent-benign in the *current* codegen — which is presumably why the v6.3.13 sweep left them. That's fragile: any change to stack layout, slot packing, or an adjacent live local turns them into corruption. `shadow.cyr`'s **8-byte** `store64` into a 1-byte local and the timespec-class ones (already found + fixed in bench/majra) are unambiguous overflows. All should be sized to the bytes actually written regardless.

## Ask (cyrius-side)

Complete the v6.3.13 sweep: size every stdlib `var X[N]` array local to the bytes actually written/read into it (the table above + a grep for `var [a-z_]+\[1\]` / `\[2\]` across `lib/*.cyr`, checking each against its `syscall`/`store*`/`load*`/`memcpy` usage). The `wait4` status idiom (`var stbuf[1]` → `load32`) is the dominant one; a single helper or a blanket `[4]` fixes `process.cyr`/`regression.cyr`/`pam.cyr` at once.

## Done-criteria

`grep -rnE 'var [a-z_]+\[[12]\]' lib/*.cyr` yields no site whose usage writes/reads past its declared byte count. A repo that reaps subprocesses (`sys_waitpid`) or parses `shadow` under 6.3.13+ runs its test suite without stack-smash SIGSEGV. (AGNOS-side note: the base stack — sakshi/sigil/majra done, libro/bote/consumers in progress — re-vendors the stdlib, so this fix propagates on their next `cyrius lib sync`.)
