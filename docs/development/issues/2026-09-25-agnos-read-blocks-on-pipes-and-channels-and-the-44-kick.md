# agnos 1.57.8: `read`#5 now BLOCKS on an empty pipe or channel endpoint when a4 == 0, and `sys_read` passes a4 by accident — comment and semantic updates for the agnos peer — RESOLVED v6.6.7

**Status:** ✅ **RESOLVED v6.6.7** (bite 4) — `sys_read` / `sys_write` pass a4 = 0, `sys_read_nb` / `sys_write_nb` pass 1, and cycc now zeroes r10 at every short agnos syscall site (the class, including the 7+-arg residue). QEMU: a pipe read after a 7-arg call left r10 = 5 now blocks and returns 2 (was -2). See `CHANGELOG.md` [6.6.7]. It stays in the open dir for the slot-close archive pass.
**Original status:** 🟡 OPEN:. The agnos kernel ships this in 1.57.8. It adds **no new syscall number or constant**, so the
agnos `syscall ABI` gate is unaffected (it is still red only for `#106`/`#107`, the 1.57.7 filing). The asks below
are one semantic fix in `sys_read` and some comment updates.
**Placement:** **6.6.7 bite 4** — agnos 1.57.6–1.57.9 peer surface; the a4=r10 class (cycc zeroes r10 on short agnos syscalls); monotonic socket-recv deadline; loopback listen class (CVE-48). Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Filed:** 2026-09-25, by agnos. agnos owns the ABI; cyrius owns the peer.
**Severity:** Medium. `sys_read` on a pipe or channel fd is non-deterministic on agnos 1.57.8 until the
`sys_read` change lands.
**Affects:** cycc 6.6.6 (the pin agnos builds with); `lib/syscalls_x86_64_agnos.cyr`. The kernel side exists from
agnos 1.57.8.

## Summary

agnos 1.57.8 makes pipe and channel reads real waits. The normative contract is agnos
`docs/development/agnos-userland-abi.md`, rows 5, 14, 25, 44 and 97.

- **`read`#5 with `a4 == 0`** BLOCKS only the caller when the fd is either:
  - a pipe read end whose ring is empty while a writer is live, or
  - an owned channel endpoint whose inbox is empty while its peer is live.

  The wait ends with bytes, or with `0` at EOF (the last writer's close or death, or the peer's `CH_CLOSE` or death).
  A SIGKILL ends a blocked reader.
- **`a4 != 0` is O_NONBLOCK** and still returns `−2` (WOULD_BLOCK). `len == 0` never waits.
- **The kernel reads a4 from `r10` unconditionally.** A 3-argument `syscall(5, fd, buf, len)` delivers whatever `r10`
  holds: a non-zero value gets `−2`, zero blocks.
- **`CH_RECV` (`chan_op`#97 op 3) is unchanged and stays non-blocking**, because its a4 is the capacity.
- **`sched_yield`#44**: a `#44` park now IPIs one other CPU that is itself parked in `#44`, so two yielders on two CPUs
  alternate at IPI speed (~0.1 ms) instead of one 10 ms tick per round. Any two `#44` loops on two CPUs therefore keep
  each other awake while both yield.
- **`pause`#14 is untouched by that kick.** A `#14` call still sleeps a whole interrupt (~10 ms) at `-smp > 1`, so a
  pause-count backstop keeps its meaning.

## The ask — `sys_read` (semantic)

`lib/syscalls_x86_64_agnos.cyr` `sys_read` (~:669-676) ends in `return syscall(SYS_READ, fd, buf, count);`, which is
three arguments, so `r10` is whatever the codegen left there. On agnos 1.57.8, `sys_read` on a pipe or channel fd
therefore sometimes blocks and sometimes returns `−2`. Please:

```
return syscall(SYS_READ, fd, buf, count, 0);    # a4 = 0: the Linux blocking-read sense (block until data or EOF)
```

and, if a non-blocking form is wanted, a separate wrapper:

```
# sys_read_nb(fd, buf, count) → bytes / 0 (EOF) / -2 (WOULD_BLOCK: nothing yet, writer or peer still live) / -1
fn sys_read_nb(fd, buf, count): i64 { return syscall(SYS_READ, fd, buf, count, 1); }
```

⚠ After this change, a cyrius caller that polls a pipe it also holds the writer of, or multiplexes several fds by
calling `sys_read` in a loop, would block. Such a caller must use `sys_read_nb`. (agnos's own `tests/spawn` crosstalk
phase was exactly that shape and now passes a4 = 1.)

## Comment updates the 1.57.8 kernel made wrong

- `SYS_READ = 5;` (~:60), `# read(fd, buf, len) → bytes / -1; fd 0 = blocking kbd stdin (1.41.1)`: add "a4 = r10:
  0 blocks on an empty pipe / channel endpoint (1.57.8), non-zero → −2 WOULD_BLOCK".
- The `sys_read` header comment (~:664-668): state the pipe/channel blocking and the a4 argument.
- `SYS_PIPE = 25;` (~:80): an empty ring answers `−2` only to an O_NONBLOCK read. Otherwise the read waits.
- `sys_chan_recv` (~:371-375): unchanged semantics. Add "the blocking receive is `read`#5 with a4 = 0 on the endpoint
  fd".
- `SYS_SCHED_YIELD = 44;` (~:514), "cooperative yield": add "a park kicks another `#44`-parked CPU (1.57.8); two
  `#44` loops on two CPUs keep each other awake — prefer a blocking read or `WAIT_BLOCK`".
- `SYS_PAUSE = 14;` (~:69), "pause() → 0 (one hlt)": still accurate. `AGNOS_SOCK_RECV_MAX_SPINS = 6000` (~:584)
  stays correctly sized for ~10 ms pauses. (For one pre-release build it was not: the kick also fired from `#14`,
  and 6000 pauses took under a second. agnos fixed that before release.)

## Consumer code outside cyrius (for reference; not a cyrius ask)

- agnoshi `agnsh.cyr:141-163`: the comment "the kernel NEVER blocks on a channel" is stale. Its a4 = 0 read of a PTY
  channel now truly blocks, which is what it wanted.
- agnoshi's `#44` bg-poll prompt and `run_agnos` waitpid + `#44` loop: they are candidates for blocking reads and
  `WAIT_BLOCK`. The kernel filing is agnos `docs/development/issues/2026-09-25-any-two-sched-yield-loops-kick-each-other.md`.

## Still open from 1.57.7

`2026-09-25-agnos-sock-peer-spawn-limits-wait-block-kill-tree-peer.md` (`#106`/`#107`, etc.) is unchanged by this
filing.

## Precedent

The same filing shape as the 1.57.6 and 1.57.7 agnos peers. agnos does not edit cyrius.
