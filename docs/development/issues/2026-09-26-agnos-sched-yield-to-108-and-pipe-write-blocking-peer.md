# agnos 1.57.9: `sched_yield_to`#108 (new), `sched_yield`#44 is quiet again, pipe writes block — constants, a wrapper, comments — OPEN

**Status:** 🟡 **OPEN**: agnos 1.57.9 ships these; `lib/syscalls_x86_64_agnos.cyr` has no name for #108 yet. agnos's `syscall ABI`
gate is red for #106 / #107 / #108 until the peer lands (kernel 108 · abi-doc 108 · cyrius 105).
**Placement:** **6.6.7 bite 4** — agnos 1.57.6–1.57.9 peer surface; the a4=r10 class (cycc zeroes r10 on short agnos syscalls); monotonic socket-recv deadline; loopback listen class (CVE-47). Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Filed:** 2026-09-26, by agnos. agnos minted the ABI; cyrius owns the peer. Normative text: agnos
`docs/development/agnos-userland-abi.md` rows 1, 5, 44, 108.
**Supersedes part of:** `2026-09-25-agnos-read-blocks-on-pipes-and-channels-and-the-44-kick.md` — the "#44 kick" it describes was
withdrawn in 1.57.9.

## The ask

```
SYS_SCHED_YIELD_TO = 108

# Directed yield: switch to `pid` if it is READY on this CPU, else park like #44 and kick only the CPU where `pid` is
# parked in a yield. pid = self, an epoch-valid child, or the epoch-valid parent; anything else -> -1 (after the yield).
fn sys_sched_yield_to(pid): i64 { return syscall(SYS_SCHED_YIELD_TO, pid); }
```

Probe: `sys_sched_yield_to(sys_getpid())` returns 0 on agnos ≥ 1.57.9 and −1 before (an unknown number).

## Comment / semantic updates

- `sched_yield`#44: a QUIET, local yield (no cross-CPU kick), as Linux `sched_yield`. The 1.57.8 kick is gone. Waiting for another
  process belongs in `read` (a4 = 0) or `waitpid` `WAIT_BLOCK`, not a `#44` loop.
- `write`#1 on a pipe: with a4 = 0 a write that does not fit BLOCKS until a reader makes room and returns `len`; with no read end
  open it returns the partial count, else −1 (no SIGPIPE). `PIPE_BUF` on agnos = **512** (a write of ≤ 512 bytes is atomic); the
  ring is 4 KB, so the Linux 4096 figure is wrong for agnos. a4 ≠ 0 keeps the short write.
- ⛔ The 3-argument `sys_write` / `sys_read` leave a4 as whatever is in r10, so whether a pipe/channel read or write blocks depends on
  a leftover register. Pass a4 = 0 explicitly (blocking) or a named non-zero (non-blocking).
