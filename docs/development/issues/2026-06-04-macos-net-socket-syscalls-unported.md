# 2026-06-04 — macOS: socket surface (`lib/net.cyr`) uses Linux syscall numbers, unported to Darwin

**Discovered:** 2026-06-04 bringing up yantra's M4 (iOS/Appium) backend on
`ecb` (arm64 macOS 26.x). yantra + sandhi build and the unit suite passes on
macOS, but every networked backend (CDP / WebDriver / Appium) fails to connect.
Same Darwin-syscall-surface family as
[`2026-06-02-macos-getdirentries-dir-listing-port.md`](./2026-06-02-macos-getdirentries-dir-listing-port.md)
and [`2026-06-02-macos-arm64-deps-stdlib-pin-check.md`](./2026-06-02-macos-arm64-deps-stdlib-pin-check.md).
**Severity:** High for any networking consumer on macOS — **all** TCP/UDP
socket operations fail. Unlike the getdirentries gap (degraded → empty), this
is fully broken: `socket()` returns garbage and every subsequent call errors.
Blocks sandhi HTTP, yantra (CDP/WebDriver/Appium), and any `lib/net.cyr` user
on Darwin. (Linux x86_64/arm64 unaffected.)
**Affects:** arm64 Mach-O (verified on `ecb`) and — by inspection — x86_64
Mach-O. `lib/net.cyr` has never run on Darwin.

## Summary

`lib/net.cyr` hardcodes **Linux** socket syscall numbers and a Linux
`sockaddr`/`sockopt` ABI:

```
var SYS_SOCKET = 41;   var SYS_CONNECT = 42;   var SYS_ACCEPT = 43;
var SYS_BIND = 49;     var SYS_LISTEN = 50;     var SYS_SETSOCKOPT = 54;
var SYS_SHUTDOWN = 48;
```

The top-of-file comment assumes "Mach-O ARM64 … pick up the same numbers via
`lib/syscalls_*.cyr`" — that assumption is **false**. Darwin's BSD socket
syscalls are entirely different (socket 97, connect 98, …). `lib/syscalls_macos.cyr`
also carries `SYS_SOCKET = 41`, so it inherits the same wrong number.

On macOS `syscall(41, …)` is **not** `socket`, so `tcp_socket()` returns a
bogus value and `connect` (syscall 42) hits a bad descriptor.

## Reproduction (ecb, arm64 macOS, cyrius 6.0.57)

A minimal `lib/net.cyr` probe against a port a `curl` reaches fine (Appium :4723):

```
tcp_socket is_err=0            # NO error flagged…
fd=4338188288                  # …but fd is garbage (should be a small int)
INADDR_LOOPBACK=100007f
connect is_err=1 errno=9       # EBADF — connecting the garbage "fd"
```

`curl http://127.0.0.1:4723/status` on the same box succeeds, so the server is
reachable; only `net.cyr`'s socket path is broken.

## Darwin deltas to port (verify on hardware — do not trust from memory)

**Syscall numbers** (BSD "unix" class; arm64 Darwin uses the raw numbers):
socket **97**, connect **98**, accept **30**, bind **104**, listen **106**,
setsockopt **105**, getsockopt **118**, shutdown **134**, socketpair **135**.
The non-blocking-connect path (`net_connect_nb`) also uses Linux **fcntl=72 /
poll=7**; Darwin is **fcntl=92 / poll=230**.

**`sockaddr_in` layout** — BSD prefixes a length byte:
- Linux: `family` is a `u16` at offset 0.
- Darwin: `sin_len` (u8, = 16) at byte 0, `sin_family` (u8, = AF_INET=2) at byte 1.
- `net.cyr`'s `sockaddr_in()` does `store16(sa, AF_INET)` → wrong on BSD.

**Socket option / errno constants:**
- `SO_REUSEADDR` 2 → **0x0004**; `SO_RCVTIMEO` 20 → **0x1006**; `SO_ERROR` 4 → **0x1007**.
- `O_NONBLOCK` 0x800 → **0x0004**; `EINPROGRESS` 115 → **36**.
- `SO_RCVTIMEO` `timeval.tv_usec` is 32-bit on Darwin (net.cyr writes a 64-bit `usecs`).

`AF_INET=2`, `SOCK_STREAM=1`, `F_GETFL=3`, `F_SETFL=4` are the same on both.

## Fix sketch

Make the socket surface platform-conditional, the way the rest of the stdlib
splits `syscalls_<platform>.cyr`:

1. Move the socket syscall numbers + `SO_*`/`O_NONBLOCK`/`EINPROGRESS` constants
   out of the hardcoded Linux block into the per-platform syscall tables
   (`syscalls_macos.cyr` getting the Darwin values above), and have `net.cyr`
   read them rather than defining Linux literals inline.
2. Branch `sockaddr_in()` to write the BSD `sin_len`/`sin_family` byte pair on
   Darwin.
3. Fix the `timeval` width in `sock_set_recv_timeout` for Darwin.
4. Re-verify `net_connect_nb` (fcntl/poll numbers + `EINPROGRESS`).

Until then, networking-dependent consumers (sandhi, yantra) build on macOS but
cannot open sockets there. yantra's M4 iOS path is verified correct up to the
socket boundary — `curl` with yantra's exact Appium capabilities creates an
XCUITest session and launches WebDriverAgent — so the only gap is this stdlib
socket port.
