# `lib/net.cyr` IPv6 surface not Darwin-ported + INET path broken on aarch64-Linux

- **Filed**: 2026-06-15
- **Reporter**: sandhi (downstream stdlib; filed `sandhi/docs/issues/2026-06-15-cyrius-net-v6-darwin.md`
  while closing the IPv4 half of its macOS nb-connect defect at sandhi 1.6.1 / cyrius 6.2.9).
- **Affects**: stdlib `lib/net.cyr`. Two distinct gaps, both surfaced here:
  1. **Darwin (aarch64 macOS / Mach-O)** — no Darwin-correct IPv6 surface to compose.
  2. **aarch64-Linux (real ARM)** — the *entire* INET socket path mis-routed (found while
     verifying #1; see "Second gap" below). x86_64 Linux unaffected by either.
- **Severity**: medium. macOS v6 connect fell back to v4 (#1); the aarch64-Linux path (#2)
  meant `tcp_socket` / `net_connect_nb` / the new v6 surface — and `chrono.cyr sleep_ms` —
  never worked on native ARM.
- **Status (2026-06-15): RESOLVED in v6.2.10.**

## Gap 1 — Darwin IPv6 surface (sandhi's request)

`lib/net.cyr` was Darwin-ported for the IPv4 + sockopt surface at v6.0.59, but the IPv6
surface was never carried along, so sandhi could not compose a Darwin-correct v6 connect:

1. `SockDomain.AF_INET6 = 10` was unbranched (Linux value; Darwin's is **30**, xnu
   `sys/socket.h`).
2. No `sockaddr_in6` builder (Darwin needs the BSD `sin6_len` byte @0 + `sin6_family=30` @1,
   vs Linux's `u16 sin6_family=10` @0 — the same length-byte split `sockaddr_in` already has).
3. No v6 non-blocking connect (`net_connect_nb` was IPv4-only, built `sockaddr_in` inline).
4. No exported `sock_set_nonblocking` / `sock_clear_nonblocking` for the server listen socket.

### Fix (v6.2.10)

Mirroring the existing v4 Darwin-port pattern, `lib/net.cyr` gained:
- per-target `SockDomain.AF_INET6` (Linux 10 / Darwin 30) under `#ifdef CYRIUS_TARGET_MACOS`;
- `sockaddr_in6(addr16, port)` — 28-byte struct, Darwin-branched `sin6_len`/family;
- `net_connect_sa_nb(fd, sa, salen, timeout_ms)` (generic, already-built sockaddr — the
  extracted core of `net_connect_nb`) + `net_connect_nb6(fd, addr16, port, timeout_ms)`;
- `sock_set_nonblocking(fd)` / `sock_clear_nonblocking(fd, saved)`.

`net_connect_nb`'s v4 behaviour is unchanged (it now delegates to `net_connect_sa_nb`).
sandhi retires its hand-rolled `_sandhi_conn_connect_sa_nb_a` / `_sandhi_conn_sockaddr_in6_a`
+ the server's raw `O_NONBLOCK` fcntl onto this surface in a follow-on sandhi slot (tracked
in `sandhi/docs/development/roadmap.md`).

## Gap 2 — aarch64-Linux INET path mis-routed (found by the pi cross-OS lib-test)

`lib/net.cyr` issues the **x86 socket syscall NUMBERS** (`SYS_SOCKET=41`, `SYS_CONNECT=42`,
`SYS_BIND=49`, `SYS_LISTEN=50`, `SYS_ACCEPT=43`, `SYS_SHUTDOWN=48`, `SYS_SETSOCKOPT=54`,
`getsockopt 55`, raw `fcntl 72` / `poll 7`) and relies on the aarch64 backend's `ESYSXLAT`
to renumber them. Those renumbers were added **only to the `_TARGET_MACHO==2` (Darwin)
branch** at v6.0.59/.65 — they were **never mirrored to the aarch64-Linux branch**. So on
native ARM Linux every net.cyr INET call hit the wrong syscall:

- `socket 41` → aarch64 `pivot_root` → `-EPERM`
- `fcntl 72` → aarch64 `pselect6` → `-EFAULT`
- `poll 7`   → aarch64 `fsetxattr` → `-EFAULT`

i.e. `tcp_socket` / `net_connect_nb` / the new v6 surface were **silently broken on
aarch64-Linux**, and `chrono.cyr sleep_ms` (also `poll(7,0,0,ms)`) never slept. cycc's own
self-host never exercises sockets, so the gap was invisible until `net_v6_connect.tcyr` ran
on real pi hardware via `cross-os-selfhost.sh pi net_v6_connect`. **Confirmed directly**:
explicit `syscall(198,…)` (aarch64 socket) creates a v6 socket on pi; `syscall(41,…)` fails.

### Fix (v6.2.10)

Added the missing socket-family renumbers to the **aarch64-Linux** `ESYSXLAT` branch in
`src/backend/aarch64/emit.cyr` (pure `movz x8` renumbers — x86 & aarch64-Linux share the
socket/fcntl arg layouts): socket 41→198, connect 42→203, accept 43→202, shutdown 48→210,
bind 49→200, listen 50→201, getsockname 51→204, setsockopt 54→208, getsockopt 55→209,
fcntl 72→25. Plus a **`poll 7 → ppoll 73` arg-shift** (aarch64 has no `poll(2)`): the int-ms
timeout in `x2` is converted to a `{tv_sec, tv_nsec}` timespec on scratch below `sp` (the
`svc` fires immediately after `ESYSXLAT` with nothing touching the stack, so no `sp` adjust
is owed), `x3`/`x4` zeroed, `ms<0` → NULL `tmo_p`. This also fixes `chrono.cyr sleep_ms` on
aarch64-Linux. Encodings assembled + verified with `aarch64-linux-gnu-as`.

## Acceptance / verification (v6.2.10)

- `net_v6_connect.tcyr`: 17/17 on x86_64 Linux, on **ecb (real macOS arm64)** via the
  cross-OS lib-test (Darwin `sin6_len=28`/`AF_INET6=30` layout + Darwin `O_NONBLOCK=0x0004`
  `sock_set_nonblocking` asserts actually executed), and on **pi (real aarch64 Linux)**.
- aarch64-Linux self-host byte-identical (the `ESYSXLAT` change is in the aarch64 backend;
  cycc reproduces itself); x86_64 cycc byte-identical (the aarch64 backend is not in the
  x86 build); macOS/Windows self-host re-verified (shared `emit.cyr`, macho path unchanged).
- `poll→ppoll`: poll(1500ms) blocks ~1.5s (tv_sec=1 + tv_nsec=5e8), poll(0ms) immediate.
- Linux + AGNOS connect semantics unchanged; check.sh green.

## Related

- `sandhi/docs/issues/2026-06-15-cyrius-net-v6-darwin.md` — the consumer request this fulfils.
- `docs/development/issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md` — the
  yantra-reported macOS nb-connect defect; v4 + per-op-timeout halves closed at sandhi 1.6.1,
  the v6 / listen-socket halves enabled by this stdlib surface.
- `2026-06-04-macos-net-socket-syscalls-unported.md` — the v6.0.59 IPv4 Darwin port of
  `lib/net.cyr` this extends to IPv6 (and to aarch64-Linux).
