# No `sock_set_nodelay`, and Windows `sys_setsockopt` is a -38 stub although net.cyr reaches ws2_32 setsockopt — `TCP_NODELAY` is never set on PE (asked by yantra) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: on a `tcp_socket()` fd,
`sys_setsockopt(fd, 6, 1, &one, 4)` (what yantra's `_cdp_set_nodelay` calls) FAILS as a PE32+ under wine while
net.cyr's internal `_net_os_setopt` (ws2_32 setsockopt, 0xF032) succeeds on the same fd — probe exit 3 under wine,
2 on Linux (both succeed). `lib/syscalls_windows.cyr:928` is still `{ return 0 - 38; }`; `lib/net.cyr` has no
`sock_set_nodelay`. Not re-run on cass (real Windows).
**Placement:** unpinned — 6.x-line backlog (asked by the yantra fold) — never 7.x.
**Discovered:** yantra 1.0.7's `_cdp_set_nodelay` move to the stdlib `sys_setsockopt` (folded at cyrius 6.6.11;
`docs/ecosystem.md` yantra row); filed 2026-10-08 from roadmap.md.
**Severity:** Low — latency only (Nagle / delayed-ACK, ~40 ms a CDP round trip on Windows); nothing fails loudly
because the caller ignores the -38.
**Affects:** cycc ≤ 6.7.6 `lib/syscalls_windows.cyr`, `lib/net.cyr` (`CYRIUS_TARGET_WIN`).

## Summary

Two halves of one gap:

1. **No public NODELAY helper.** `lib/net.cyr` has `sock_set_recv_timeout` / `sock_set_send_timeout`
   (`:553`, `:575`) over the private per-target `_net_os_setopt` (`:442`, which on Windows is
   `_net_wsa_rc(syscall(0xF032, …))`), but no `sock_set_nodelay`, so callers drop to the raw syscall wrapper.
2. **The raw wrapper is a stub on Windows.** `sys_setsockopt` returns -38 on PE (`lib/syscalls_windows.cyr:928`) even
   though the PE backend routes ws2_32 `setsockopt` (0xF032) and net.cyr uses it. yantra's
   `_cdp_set_nodelay` (`lib/yantra.cyr:476-479`: `sys_setsockopt(fd, 6, 1, &one, 4)`), called on every CDP connect
   (`:633`, "kill the ~40ms Nagle/delayed-ACK round-trip tax"), therefore never sets `TCP_NODELAY` on Windows.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/result.cyr"
include "lib/net.cyr"
alloc_init();
var t, fd = tcp_socket();
if (is_err_result(t) == 1) { syscall(SYS_EXIT, 99); }
var one = 1;
var a = sys_setsockopt(fd, 6, 1, &one, 4);   # IPPROTO_TCP, TCP_NODELAY — the public wrapper
var b = _net_os_setopt(fd, 6, 1, &one, 4);   # net.cyr's internal route
var r = 0;
if (a != 0) { r = r + 1; }                   # +1: the public wrapper failed
if (b == 0) { r = r + 2; }                   # +2: the internal route worked
syscall(SYS_EXIT, r);
```

```sh
cd /home/macro/Repos/cyrius
./build/cycc < nd.cyr > nd && chmod +x nd && ./nd; echo $?                          # 2
CYRIUS_TARGET_WIN=1 ./build/cycc < nd.cyr > nd.exe && wine ./nd.exe; echo $?         # 3
```

## Root cause

`sys_setsockopt` in the Windows peer predates (or was never pointed at) the 0xF032 reroute that net.cyr's
`_net_os_setopt` uses; no public option helper covers NODELAY.

## Proposed fix

1. `sock_set_nodelay(fd, on)` in `lib/net.cyr` over `_net_os_setopt(fd, IPPROTO_TCP, TCP_NODELAY, &v, 4)` — 6 / 1 on
   Linux, Darwin and Winsock alike; agnos fails closed (-38 — it has no TCP options, and its `sys_setsockopt` is
   already that stub, `lib/syscalls_x86_64_agnos.cyr:761`).
2. Route Windows `sys_setsockopt` through 0xF032 with `_net_wsa_rc`-style error mapping, so the raw wrapper stops
   lying. This turns a -38 into a real call for existing PE callers — a behaviour change toward what the wrapper's
   name promises; the user may prefer to keep the stub and ship only (1).
3. A `tests/tcyr/crossos/` test (set NODELAY, read it back with getsockopt) on ecb / ach / cass / pi; yantra moves
   `_cdp_set_nodelay` to `sock_set_nodelay` in its own release.
