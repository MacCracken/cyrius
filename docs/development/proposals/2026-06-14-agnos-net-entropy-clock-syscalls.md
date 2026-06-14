# CYRIUS_TARGET_AGNOS peer: net / entropy / wall-clock syscalls (the TLS + net-tools enabler)

**Filed:** 2026-06-14 during AGNOS 1.45.x (TLS → HTTPS → `ark`-fetch arc; cuts 1.45.0–1.45.4)
**Severity:** Stdlib peer gap — `tls_native`, `http`, `net`, and the AGNOS network-tools family (`yo`/`dig`/`whirl`) cannot run on AGNOS because the `CYRIUS_TARGET_AGNOS` stdlib peer has no entropy, no wall-clock, and no socket transport. The AGNOS kernel just exposed all of these as ring-3 syscalls (#45–#54); cyrius owes the mirroring wrappers.
**Affects:** `lib/syscalls_x86_64_agnos.cyr` (the agnos syscall peer — already carries a fail-closed `sys_getrandom` stub waiting for exactly this), `lib/chrono.cyr` (agnos wall-clock branch), `lib/net.cyr` (the socket model — see the **model-mismatch** section; this is the one non-mechanical item), and the consumers `lib/tls_native.cyr` / `lib/http.cyr`.
**Target slot:** v6.x agnos-target expansion — same lane as the FS-syscall peer that landed at cyrius 6.0.55/6.0.56 for the `/bin/agnsh` shell. User direction on sequencing.
**Source of truth (AGNOS owns the ABI; cyrius mirrors it):** `agnos/kernel/core/syscall.cyr` (the `ksyscall` dispatch, `if (num == 45)` … `if (num == 54)`), `agnos/kernel/core/net_tcp.cyr` (TCP), `agnos/kernel/core/net.cyr` (UDP transport + listener table). These numbers are **frozen** as of AGNOS 1.45.3.

## Summary

AGNOS 1.45.x added eleven ring-3 syscalls — the complete set `tls_native` binds to, plus the UDP surface `dig` needs and the ICMP echo `yo` needs:

| # | AGNOS syscall | Signature (kernel) | Returns | Blocking? |
|---|---|---|---|---|
| 45 | `getrandom` | `(buf, len, flags)` | bytes written; `-1` bad range; `0` if `len<=0` | no |
| 46 | `time_unix` | `()` | wall-clock **Unix seconds (UTC)**; `0` if RTC unreadable | no |
| 47 | `sock_connect` | `(dst_ip, dst_port, src_port)` | `conn_id` 0..7; `-1` (table full / ~8 s SYN-ACK timeout / RST) | **yes (~8 s)** |
| 48 | `sock_send` | `(conn_id, buf, len)` | bytes accepted (`<len` if conn drops); `-1` bad range | **yes** |
| 49 | `sock_recv` | `(conn_id, buf, maxlen)` | bytes; **`0` = WOULD_BLOCK**; **`-1` = EOF / bad arg** | no |
| 50 | `sock_close` | `(conn_id)` | `0`; `-1` bad conn_id | no |
| 51 | `udp_bind` | `(port)` | `listener_id` 0..7; `-1` (already bound / table full) | no |
| 52 | `udp_send` | `(dst_ip, ports, buf, len)` | bytes; `-1` (NIC down / bad range); `0` if `len<=0` | no |
| 53 | `udp_recv` | `(listener_id, buf, maxlen, addr_out)` | bytes; **`0` = none yet**; **`-1` = bad arg** | no |
| 54 | `udp_unbind` | `(listener_id)` | `0`; `-1` bad id | no |
| 55 | `icmp_echo` | `(dst_ip)` | round-trip **milliseconds** (≥ 0); `-1` (timeout / NIC down) | **yes (~3 s)** |
| 56 | `sock_listen` | `(port)` | listen_id 0..7; `-1` (port already bound / conn table full) | no |
| 57 | `sock_accept` | `(listen_id)` | conn_id 0..7; **`-1` = none pending yet (WOULD_BLOCK) / bad listen_id** | no |

(#55 added AGNOS 1.45.4 — completes Phase A `yo`. **#56/#57 added AGNOS 1.45.5 — Phase B: the inbound/server surface** so agora/descent/sandhi/sit-serve can `accept()` on AGNOS; `tcp-listen-smoke` 2/2 host→AGNOS.)

## Register ABI (unchanged from the FS-syscall peer)

AGNOS uses the `syscall` instruction. `rax` = number, `rdi` = arg1, `rsi` = arg2, `rdx` = arg3, **`r10` = arg4** (the entry stub preserves the user's `r10` into the `ksyscall_a4` global before the CR3-switch scratch clobbers it — the same `a4=r10` extension the 1.41.3 `rename`/`link` wrappers already use). Return in `rax`. cyrius's existing `syscall(num, a1, a2, a3, a4)` builtin already lowers to this on `CYRIUS_TARGET_AGNOS`; no codegen change is needed — only new wrappers.

Two syscalls use `a4` (`r10`):
- **#52 `udp_send`**: `len` rides `a4`. The two 16-bit ports are **packed into `arg2`**: `src_port = (arg2 >> 16) & 0xFFFF`, `dst_port = arg2 & 0xFFFF` — `dst_ip` needs a full 32 bits (`arg1`) and the 4-arg ABI can't pass five separates.
- **#53 `udp_recv`**: `addr_out` rides `a4`. If non-zero it's a 16-byte user region: peer `src_ip` at `+0`, `src_port` at `+8` (pass `0` to skip).

`dst_ip` everywhere is the **`ip4()`-packed form**: `(oct1<<24)|(oct2<<16)|(oct3<<8)|oct4` (e.g. `1.1.1.1` → `0x01010101`). The peer resolves a hostname to this via `dig`/DNS (UDP #51–#54) before connecting.

## Per-consumer mapping (what each number fills)

### #45 `getrandom` → fills the existing fail-closed stub — **do this first, it's a one-liner**

`lib/syscalls_x86_64_agnos.cyr` already carries:

```cyrius
# CVE-19 (v6.1.36): fail-CLOSED entropy on AGNOS userspace ... return -1 so
# random_bytes() (and its ws/sandhi/sigil consumers) fail loudly ...
fn sys_getrandom(buf, len, flags): i64 {
    return 0 - 1;
}
```

AGNOS #45 is the syscall that comment was waiting for (Zen `RDRAND`, bounded-retry, never hands back a zeroed buffer). Replace the body with `return syscall(45, buf, len, flags);`. This immediately un-fail-closes `random_bytes()` and its `ws`/`sandhi`/`sigil`/**`tls_native`** consumers on AGNOS. Keep the fail-closed contract for any *other* arch; only the AGNOS branch gains the real call. (The "filed upstream" note + `issues/2026-06-11-windows-entropy-primitive.md` can be updated to "landed AGNOS 1.45.0 / syscall 45".)

### #46 `time_unix` → wall-clock for cert validity

`tls_native` needs an absolute UTC clock to check certificate `notBefore`/`notAfter`. AGNOS exposes only monotonic `uptime` (#40) until now; #46 is RTC-derived Unix seconds. Add `fn sys_time_unix(): i64 { return syscall(46); }` to the agnos peer and wire `lib/chrono.cyr`'s "now (Unix seconds)" entry to it under `CYRIUS_TARGET_AGNOS`. Note it is **whole-seconds** (no sub-second; RTC granularity) and returns `0` if the RTC is mid-update — treat `0` as "unknown," not epoch.

### #47–#50 TCP sockets → `tls_native` / `http` / `whirl` — **the one design call**

This is the non-mechanical item. AGNOS's socket model is **not** the BSD fd/sockaddr model `lib/net.cyr` is built on:

| | cyrius `lib/net.cyr` (Linux/BSD) | AGNOS #47–#50 |
|---|---|---|
| handle | `fd` (from `socket()`) | `conn_id` (small int 0..7, **from `connect`**) |
| addressing | `sockaddr_in` struct + `bind`/`connect(fd, sa)` | `dst_ip` (packed u32) + ports as scalars |
| create vs connect | `socket()` then `connect()` | one `sock_connect` does both |
| options | `setsockopt` (`SO_REUSEADDR`, `SO_RCVTIMEO`) | none — `recv` is non-blocking; caller times out via #46/#40 |
| recv semantics | `0` = EOF, `<0` = errno (`EAGAIN` for would-block) | **`0` = WOULD_BLOCK, `-1` = EOF/err** (inverted from Linux!) |
| concurrency | per-process fds | **8 global conn slots, no per-process ownership** (single-consumer MVP) |

So `lib/net.cyr`'s API cannot call AGNOS syscalls 1:1. The cyrius-side choice (user/implementer to make):

- **Option A — agnos adapter inside `lib/net.cyr`**: branch the existing `tcp_socket`/`sock_connect`/`recv`/`send`/`close` functions so the agnos build maps the BSD-shaped API onto `conn_id` syscalls (synthesize a fake-fd↔conn_id table, ignore `setsockopt`, invert the recv would-block/EOF sense). Keeps `tls_native`/`http` source-identical across targets.
- **Option B — a thin agnos-native socket module** (`lib/net_agnos.cyr`) that `tls_native`'s transport vtable binds to directly on AGNOS, leaving `lib/net.cyr` Linux/Darwin-only.

`tls_native` is already transport-agnostic (abstract `send`/`recv`/`random`/`now`), so whichever option, the binding point is small: `send` → `sock_send`#48, `recv` → `sock_recv`#49 (mind the inverted would-block sense), `connect` → `sock_connect`#47, `close` → `sock_close`#50, `random` → #45, `now` → #46. Recommend **Option A** for source-parity unless the fd-synthesis proves uglier than a native module.

**Behavioral notes the binding must honor:**
- `sock_connect` / `sock_send` **block** (the kernel runs an interrupt-window internally; the calling proc is suspended up to ~8 s). Fine for a single foreground fetch; do not assume they return promptly.
- `sock_recv` is **non-blocking** and returns `0` for would-block — a `tls_native` recv loop must poll with its own deadline (using #46/#40), not rely on a blocking recv with `SO_RCVTIMEO`.
- Only **8 concurrent connections** exist process-wide. `ark`-fetch must `sock_close` between fetches (the kernel reclaims the slot on close as of 1.45.2; an unclosed leak still caps at 8).

### #55 `icmp_echo` → `yo` (`ping`)

`yo` sends one ICMP echo and reports the round-trip time. AGNOS #55 does exactly that in one call:
`syscall(55, dst_ip)` → RTT in **milliseconds** (≥ 0) or `-1` (timeout / NIC down). No raw-socket / `SOCK_RAW`
/ privilege dance like Linux `ping` — AGNOS gives a single high-level primitive (the kernel owns the echo
id/seq + reply matching). Add `fn sys_icmp_echo(dst_ip): i64 { return syscall(55, dst_ip); }` to the agnos
peer; `yo`'s agnos path calls it directly (it resolves the hostname via `dig`/UDP first, then pings the
packed IP). Notes for the binding: it **blocks ~3 s** (kernel-bounded; the calling proc is suspended for the
duration), the RTT resolution is the 100 Hz tick (**10 ms**; a sub-10 ms reply reads as `0` ms — display
`<10 ms` or `0`), and the timeout is fixed (a configurable `-W` would need an AGNOS-side `icmp_ping` change,
noted there as a future enhancement).

### #51–#54 UDP → `dig` / DNS

`dig` (and any DNS resolution `whirl` needs) constructs/parses DNS packets itself over raw UDP. The flow: `udp_bind`(ephemeral port) → `udp_send`(resolver_ip, `(eport<<16)|53`, query, qlen) → poll `udp_recv` → `udp_unbind`. The listener mailbox holds **one** datagram (most-recent-wins) — correct for one-query-in-flight DNS. Same 8-slot cap + reclaim as TCP; **always `udp_unbind`** after a query or the table exhausts. A cyrius agnos UDP binding (in the same module as the TCP one) wraps these four.

### Transitive consumer: `owl` → `sit` (and why this gates a `bat`-like viewer on AGNOS)

`owl` (1.4.0 — the AGNOS `bat`-equivalent file viewer) is **blocked from compiling for `CYRIUS_TARGET_AGNOS`
by this same TLS stack**, transitively: owl's VCS change-marker gutter consumes **`sit`** (the Cyrius-native
git replacement — `sit_repo_open`/`sit_diff_path`/`sit_repo_close`), and `sit`'s library bundle drags in its
**wire/serve/https** remote layer (`src/wire.cyr` / `src/wire_http.cyr` / `src/serve.cyr`), whose stdlib
footprint is exactly **`net` + `tls` + `tls_native` + `ws` + `http`** — all of which appear verbatim in owl's
`cyrius.cyml` `[deps].stdlib`. So owl-on-AGNOS has **two prerequisites, not one**:

1. **This TLS peer (#45–#55)** — so `net`/`tls`/`tls_native`/`http`/`ws` build for `CYRIUS_TARGET_AGNOS` at
   all (today they're Linux/Darwin-only). Without it the stdlib tail won't compile for agnos and owl won't link.
2. **A `sit` agnos port** — `sit`'s object store (patra B+tree / sigil hashing / sankoch compression) and its
   wire layer must build + run under `CYRIUS_TARGET_AGNOS`. owl already `#ifdef CYRIUS_TARGET_AGNOS`-gates the
   gutter *call* off (`owl/src/vcs.cyr:193` — "sit's object store is not wired for agnos yet"), but the gating
   only removes the *call site*; owl's `cyrius.cyml` still pulls sit's stdlib tail into the agnos build, so the
   TLS peer (#1) is needed even for the gutter-disabled agnos build, and the sit port (#2) is needed before the
   gutter can be *re-enabled* on agnos.

Net: a fully-featured `owl` on AGNOS waits on **both** this proposal **and** a separate `sit`→agnos port (its
own future bite). The minimal unblock (owl compiles for agnos with the gutter disabled) needs only #1, *if*
owl's agnos build can be made to exclude the sit-only `net`/`tls`/`http`/`ws` stdlib tail — otherwise #1 must
actually provide those wrappers for agnos. (The owl `cyrius.cyml` comment already anticipates "the later 6.x
lib-streamlining arc is expected to let owl drop the sit-only tail.")

## Scope boundary

- **Phase A is fully kernel-unblocked** as of AGNOS 1.45.4: `yo` (ICMP #55), `dig` (UDP #51–#54), `whirl`
  (TCP #47–#50 + TLS via #45/#46). The earlier "ICMP for `yo` is still owed" note is **resolved** — #55 landed
  1.45.4. (A configurable ping timeout `-W` would still need an AGNOS-side `icmp_ping` parameterisation, but
  the default 3 s bound is fine for MVP `yo`.)
- **TLS kernel-freestanding linkage**: tracked on the cyrius v6.2.x roadmap as "the AGNOS-kernel crypto prereq"; orthogonal to these userspace wrappers.
- **Phase B (server/inbound — `agora`, `cyrius-yeomans-descent`, sandhi web, sit-serve)**: ✅ **LANDED AGNOS 1.45.5**
  as `sock_listen`#56 + `sock_accept`#57 (`tcp-listen-smoke` 2/2 host→AGNOS). Cyrius-side mapping for the agnos peer:
  - **`sock_listen`(port) → #56** does **bind + listen in one call** — AGNOS merges them (`tcp_listen` creates the
    LISTEN slot on `net_ip`; the kernel `tcp_bind` is just `tcp_listen`, `ip` unused). So the BSD `lib/net.cyr` shape
    `socket()`→`bind(fd,addr,port)`→`listen(fd,backlog)` collapses on agnos to **one** `syscall(56, port)` → listen_id.
    The adapter folds `socket()`+`bind()` into a stored port and fires #56 at `listen()`. No `sock_bind` syscall on
    agnos yet (deferred until a bind-without-listen consumer needs it; mirrors the kernel's own `tcp_bind==tcp_listen`).
  - **`sock_accept`(listen_id) → #57** is **non-blocking** — returns a conn_id or **−1 = none pending yet (WOULD_BLOCK)**.
    A server loop polls #57 (it `net_poll()`s internally to advance the handshake), with its own timeout via #46/#40.
    The accepted conn_id reuses `sock_send`#48 / `sock_recv`#49 / `sock_close`#50 — identical to a client conn.
  - **Concurrency is the service/adapter's problem, not the kernel's.** agora's **fork-per-accept** (ADR 0007) needs an
    AGNOS-specific path — agnos has `spawn`#3/#43 + `waitpid`#4, **not** Unix `fork()` (no COW address-space dup). So
    agora-on-agnos must either spawn a worker per connection or fall back to a single-process serial/poll loop. descent's
    **single-thread epoll** model maps cleanly (poll #57 + the accepted conns' #49). Flag this for whoever ports the
    servers to `CYRIUS_TARGET_AGNOS`.
  - Caps unchanged: 8 conn slots total (LISTEN slot included), with the 1.45.2 + 1.45.5 reclaim so listen/accept/close
    churn doesn't leak the table.

## Workaround until landed

None needed on the AGNOS side — the syscalls are live and the numbers are frozen. Until the cyrius peer lands, the net-tools simply can't be built for `CYRIUS_TARGET_AGNOS` (they build fine for Linux today). A consumer that wants to experiment early can call `syscall(45..54, …)` with magic numbers directly, exactly as `hapi` did for `fsync(74)` before its wrapper — but the bare-name wrappers are the right home, and `sys_getrandom` already exists to fill.

## Relationship to prior proposals

Companion to the FS-syscall agnos peer (the `/bin/agnsh` enabler, cyrius 6.0.55/56) — same "AGNOS owns the ABI, cyrius mirrors it" pattern, next subsystem. Distinct from `2026-06-04-macos-net-socket-syscalls-unported.md` (that is Darwin BSD-socket porting; this is the agnos non-BSD socket model). The `sys_getrandom` fail-closed stub references `issues/2026-06-11-windows-entropy-primitive.md` — this proposal is the AGNOS resolution of that entropy gap.
