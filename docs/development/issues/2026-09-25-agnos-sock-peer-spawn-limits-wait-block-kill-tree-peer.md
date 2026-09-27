# agnos 1.57.7: `sock_peer`#106, `spawn_limits`#107, blocking `waitpid`, `KILL_TREE`, wait-status helpers, listen classes — constants + wrappers for the agnos peer, and the comments 1.57.7 made wrong — RESOLVED v6.6.7

**Status:** ✅ **RESOLVED v6.6.7** (bite 4) — #106 / #107, WAIT_BLOCK (`sys_waitpid_block` refuses pid < 0 and > 15), `sys_kill_tree`, the §4.9 W* helpers, `sys_getpeername` / `sys_getsockname`, the #48 0-retry in the `sys_write` socket route, and the stale comments. The loopback listen class shipped as CVE-48 in the same bite. `lib/io.cyr`'s comment rows are L-pid1's; the send-all at ws_server/http ignored-count sites was not taken. See `CHANGELOG.md` [6.6.7]. It stays in the open dir for the slot-close archive pass.
**Original status:** 🟡 OPEN: the agnos kernel ships these in 1.57.7; `lib/syscalls_x86_64_agnos.cyr` has no names for
them yet. **Two new syscall NUMBERS** (`#106`, `#107`), so agnos's `syscall ABI (kernel/doc/cyrius agree)` gate is
red by design until this peer lands (the 1.56.55 precedent): it names `#106` and `#107` as absent from cyrius.
**Placement:** **6.6.7 bite 4** — agnos 1.57.6–1.57.9 peer surface; the a4=r10 class (cycc zeroes r10 on short agnos syscalls); monotonic socket-recv deadline; loopback listen class (CVE-48). Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Filed:** 2026-09-25, by agnos. agnos minted the ABI; cyrius owns the peer.
**Severity:** Medium. Nothing breaks for an existing caller except where noted under "consumer code"; the features
daimon asked agnos for (a loopback-only server, the peer address, per-agent caps, stop/pause/resume, a blocking wait)
are reachable today only by raw numbers and hand-packed bits.
**Affects:** cycc 6.6.6 (the pin agnos builds with). The kernel side exists only from agnos 1.57.7.

## Summary

agnos 1.57.7 closes ten issue files, eight of them daimon/patra filings: every wait now blocks only its caller, a
parent can end/stop/continue/cap its child, and TCP/UDP ids are owned. The normative contract is agnos
`docs/development/agnos-userland-abi.md` (rows 4, 14, 16, 27, 37, 40, 41, 43, 44, 47–57, 59, 99, 100, 106, 107,
§4.8, §4.9).

## The ask — syscall numbers

```
SYS_SOCK_PEER    = 106;  # sock_peer(conn_id) → (peer_ip << 16) | peer_port / -1
                         #   ip = r >> 16 (the ip4() form), port = r & 0xFFFF (host order); a live peer is >= 0x10000.
                         #   -1: bad id, not the caller's, CLOSED, LISTEN. a2..a4 never read.
SYS_SPAWN_LIMITS = 107;  # spawn_limits(mem_pages, cpu_ms) → 0 / -1
                         #   one-shot caps for the caller's NEXT spawn#3 / execwait#37 / spawn_path#43, consumed on
                         #   every return; (0, 0) disarms; a refused call leaves the old arm. 0 <= mem_pages <= 2^36
                         #   (4 KiB pages, enforced at 2 MB granularity); 0 <= cpu_ms <= 2^40 (ceil(ms/10) ticks).
                         #   Child cap = min(creator's own cap, arm); fork#96 copies caps, never the arm.
```

## The ask — constants (argument / return values, not syscall numbers)

```
SPAWN_E_LIMIT        = 7;            # #43 returns -7: the image does not fit the effective memory cap
                                     #   (retrying never helps; unlike -3 NOMEM). #3/#37 return -1 for it.
SIGXCPU              = 24;           # a child at its CPU cap dies by it; wait status 280
AGNOS_WAIT_BLOCK     = 0x100;        # waitpid#4 a1 = 0x100 | pid (pid 0..15): BLOCK until that child exits
AGNOS_WAIT_ANY       = 0x1FF;        # waitpid#4 a1 = 0x1FF: block until any child exits
AGNOS_KILL_TREE      = 0x100;        # kill#16 a2 = sig | 0x100: the child and every descendant
SOCK_LISTEN_LOOPBACK = 0x100000000;  # sock_listen#56 a1 = port | (class << 32); class 1 = LOOPBACK
FLOCK_E_TABLE_FULL   = 2;            # flock#59 returns -2: the 16-slot lock table is full (never waits)
```

`proclist`#99 `+8` state values (for a monitor): 1 ready · 2 running · 3 claiming · **4** dying (transient) ·
**5** stopped · **6** blocked in a kernel wait · **7** zombie (exited, unreaped; report-only).

`sock_listen`#56 class bits: arg1 bits 0–15 = port (1..65535), bits 32–39 = class (0 = ANY: net_ip **and**
127/8; 1 = LOOPBACK: admits only SYNs addressed to 127.0.0.0/8, which can only originate on this host); bits 16–31
and 40–63 must be 0, class > 1 → −1. Every pre-1.57.7 value decodes to class 0 byte-for-byte. **A kernel older
than 1.57.7 ignores the class** — the adapter must fail closed (below).

## The ask — wrappers

```
fn sys_sock_peer(conn_id): i64 { return syscall(SYS_SOCK_PEER, conn_id); }
fn sys_spawn_limits(mem_pages, cpu_ms): i64 { return syscall(SYS_SPAWN_LIMITS, mem_pages, cpu_ms); }

# Blocking wait (D22). Returns the wait status (below), -1 when pid is not the caller's child or the
# caller has no children, -2 only when the caller cannot block. A pre-1.57.7 kernel answers -1 for
# any a1 >= 16, so a caller can probe.
fn sys_waitpid_block(pid): i64 { return syscall(SYS_WAITPID, AGNOS_WAIT_BLOCK | pid); }
fn sys_waitpid_any_block(): i64 { return syscall(SYS_WAITPID, AGNOS_WAIT_ANY); }

# agnos getpeername: a tagged socket fd → its conn id → #106 → sockaddr_in {family, port BE, addr BE}.
fn sys_getpeername(fd, out, alen): i64 { ... }
```

**Replace the hard-coded wait-status stubs** (`lib/syscalls_x86_64_agnos.cyr` ~:743–749 — `WIFEXITED` returns 1,
`WIFSIGNALED`/`WTERMSIG` return 0). From 1.57.7 the status of `waitpid`#4 (both forms) and `execwait`#37 is: an exit
→ `code & 0xFF`; a ring-3 fault → `128 + vector` (a #PF = **142**); a death by signal → `0x100 | sig` (SIGKILL =
**265**, SIGXCPU = **280**):

```
fn WIFEXITED(s): i64   { return (s & 0x100) == 0; }
fn WEXITSTATUS(s): i64 { return s & 0xFF; }
fn WIFSIGNALED(s): i64 { return (s & 0x100) != 0; }
fn WTERMSIG(s): i64    { return s & 0xFF; }
```

**The server adapter** (`net.cyr` listen path): stash the bind address; for any 127/8 bind pass
`port | SOCK_LISTEN_LOOPBACK`, and **fail closed** (refuse the bind) when the kernel is older than 1.57.7 — the
older kernel would silently listen on every address. agnos's suggested probe is `#107(0, 0)` (a no-op disarm
that returns 0 on ≥ 1.57.7).

## Comment updates the 1.57.7 kernel made wrong

- `SYS_KILL = 16` (~:71) / `sys_kill`: **9 ends** the target, **19 stops**, **18 continues** (and sets bit 18),
  **0 probes** (authorization only); any other 1..63 sets a pending bit with no default action (SIGTERM included);
  `sig | 0x100` = KILL_TREE — a tree STOP that had to skip a member returns **−2** (e.g. a `#37` foreground child
  while its parent waits). Any other bit above 7 → −1.
- `SYS_WAITPID = 4` (~:59) "→ exit_code / -1": three-valued (−2 = still running) plus the blocking form above.
- `SYS_SLEEP_MS = 41` (~:459) "halts ~ms until the 100 Hz tick" and `sys_nanosleep`: **blocks only the caller**
  (`#99` state 6); ≥ `ms` by `uptime_us`#95, up to one 10 ms tick longer. There is no "pace without yielding"
  call; a caller that must hold its CPU spins on `#95`.
- `SYS_PAUSE = 14` (~:69) "(one hlt)" and `SYS_SCHED_YIELD = 44` (~:514) "cooperative yield": both yield to a
  READY process or **park the CPU for one hlt** (not charged), so a poll+yield loop does not spin a core. ⚠ At
  `-smp > 1` a peer RUNNING on another CPU is not READY: a cross-CPU poll+yield round costs one tick (agnos issue
  `2026-09-25-cross-cpu-poll-and-yield-loops-are-tick-bound.md`, planned 1.57.8).
- `SYS_EXECWAIT = 37` (~:509) "load+run": the child is an **ordinary scheduled process** (IF=1, any CPU; may yield,
  fork, spawn, wait, block, nest `#37`), and the **caller blocks** (#37 now blocks) until it exits; −1 also when
  the child could get only the global fd table.
- `SYS_FLOCK = 59` (~:109) and `xflock` (`lib/io.cyr` ~:440): SH/EX **without `LOCK_NB` wait** (only the caller
  blocks; no timeout; no FIFO fairness); `LOCK_NB` → −1 when contended; **−2 = table full**; a blocking SH↔EX
  conversion drops the old lock first. No ring-3 spin is needed. ⚠ The owner is the PID, not the open file.
- `SYS_UPTIME_MS = 40` (~:458): the calibrated TSC since 1.57.7 (`uptime_ms_base` + TSC ms; ticks × 10 only on a
  boot where calibration refused); it advances under IF=0 and host throttling.
- `SYS_SOCK_CONNECT = 47` (~:476) "BLOCKS ~8s" and `SYS_SOCK_SEND = 48` (~:477) "BLOCKS": block **only the
  caller**; `#47`'s ~8 s ceiling is measured once from entry. `sys_sock_send`: returns `len` when every byte is
  ACKed, else the **committed count (possibly 0) after ~8 s with no ACK progress** (D6 — 0 means "no progress
  yet", not an error); a zero-window peer that keeps answering is never declared dead.
- `SYS_ICMP_ECHO = 55` (~:484) "BLOCKS ~3s (fixed kernel bound)" and `sys_icmp_echo(_ex)`: block only the caller;
  RTT at **1 ms resolution** (10 ms when `#95` is −1); `#100`'s bound is never early.
- `#48`–`#57` ownership: every TCP connection/listener and UDP listener is owned by the process incarnation that
  opened it; every other process (fork/spawn children included) gets −1. An inherited tagged socket fd is
  **inert** in a child (`sys_close` on it no longer FINs the parent's connection). A dead connection (RST,
  retransmit exhaustion) **keeps its id until the owner closes it**. `#50` from ESTABLISHED/CLOSE_WAIT is graceful
  (FIN retransmitted; the id is invalid at once; a second close is −1). `#49` −1 also = EOF after the peer's FIN.
- `SYS_UDP_SEND = 52` (~:481) "→ bytes / 0 / -1": returns the **frame length** accepted (payload + 42; a loopback
  send returned 0), −1 when `src_port` is bound by another owner. `#54` on an already-free id → −1.
- `SYS_SOCK_LISTEN = 56` (~:486) "sock_listen(port)": the class bits above.
- `SYS_MMAP = 27` (~:82): returns 0 past the caller's `#107` memory cap; never overwrites a present mapping.
- `SYS_PROCLIST = 99` (~:165): states 4–7 above; RSS includes the high mmap arena.

## Consumer code in cyrius itself

- `_tn_sock_write_all` (`lib/tls_native_conn.cyr` ~:576–584) treats a `sock_send` return of 0 as fatal — on
  ≥ 1.57.7 that aborts a live, merely stalled connection; retry under the caller's own deadline.
- `lib/ws_server.cyr` (~:119, :226–227) ignores `sock_send`'s count — a short send truncates the response.
- `lib/process_agnos.cyr` `run()` / `wait_pid`: the −2 (still running) return of `waitpid`#4 is not handled
  (pre-existing); `sys_waitpid_block` above removes the need to poll.

## Still open from 1.57.6

The spawn flags / error codes / `#62` ops filing
(`2026-09-24-agnos-spawn-flags-redirect-ops-and-uptime-us-peer.md`) is still OPEN; `SPAWN_E_LIMIT = 7` extends its
`SPAWN_E_*` table. One more 1.57.7 change to that table's meaning: `#43` on the global-fd-table fallback now returns
−3 (`SPAWN_E_NOMEM`) for every form.

## Precedent

Same kernel-mints-it / cyrius-owns-the-peer split as
[`archived/2026-09-01-agnos-sys-statfs-103-peer.md`](archived/2026-09-01-agnos-sys-statfs-103-peer.md) and the
1.57.6 filing above.
