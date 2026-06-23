> **RESOLVED v6.2.39** — `SYS_NET_CONFIG=61` + `sys_net_config(field)` + 4 typed
> getters (`sys_net_ip`/`_netmask`/`_gateway`/`_dns_server`) added to
> `lib/syscalls_x86_64_agnos.cyr` (kernel-verified at `syscall.cyr:1826`). Consumers
> (taar/yo/whirl/dig) can now drop the raw `syscall(61,3)`. See CHANGELOG [6.2.39].

# Add a `sys_net_config` wrapper for the new AGNOS `net_config` syscall (#61) so net-tool consumers stop calling raw `syscall(61, …)`

**Filed:** 2026-06-23 (by the agnos/taar/yo net-tools cohort — agnos 1.45.16 added the
`net_config` syscall; `taar` 0.3.x and `yo` 0.5.x consume it via a raw `syscall(61, 3)`
pending this wrapper).
**Severity:** P3 — request / hygiene. The consumers WORK today via the raw form; this
is the long-term cleanup so they route through the typed `sys_*` peer like every other
agnos syscall, removing a hardcoded number from consumer code.
**Component:** stdlib — `lib/syscalls_x86_64_agnos.cyr` (the `CYRIUS_TARGET_AGNOS`
syscall peer) + its constant block.
**Toolchain:** consumers pinned cyrius 6.2.6 (taar) / 6.2.24 (yo); the wrapper can land
in any ≥ release the cohort next bumps to.

## Background

agnos 1.45.16 added syscall **#61 `net_config(field)`** — a non-blocking, buffer-less
getter (same shape as `uptime_ms`#40 / `winsize`#60) that returns a kernel
network-config datum in `rax`:

| field (arg1) | returns |
|---|---|
| 0 | `net_ip` (this host's IPv4, packed first-octet-high-byte) |
| 1 | `net_netmask` |
| 2 | `net_gateway` (default-route next hop) |
| 3 | `net_dns_server` (DHCP option-6 resolver, else the leased gateway) |

Each value is a packed IPv4 in `[0, 0xFFFFFFFF]` (always a positive `i64`); `0` =
unconfigured; `-1` = unknown field. No args beyond `field`, no user buffer, no
preempt/sti window — IF=0-safe.

**Why it exists:** it lets a ring-3 resolver target the **DHCP-leased on-subnet**
resolver instead of a hardcoded **off-subnet** public IP (1.1.1.1 / 8.8.8.8). The
off-subnet fallback needs working gateway-MAC egress + a reachable public resolver —
the exact QEMU-passed / iron-failed gap that froze `yo google.com` /
`whirl https://google.com` on real hardware (QEMU's `dig` smoke used an explicit
on-subnet `@10.0.2.3`, never exercising the fallback). Kernel-side detail: agnos
`kernel/core/syscall.cyr` (`if (num == 61)`), reading the `net.cyr` globals populated
by `net_dhcp.cyr` on ACK.

## Request

Add the wrapper + constant to `lib/syscalls_x86_64_agnos.cyr`, alongside the existing
net band (`sys_udp_*`/`sys_sock_*`/`sys_icmp_echo`/`sys_uptime_ms`):

```cyrius
# in the SYS_ constant block (next to SYS_ICMP_ECHO = 55 … SYS_WINSIZE = 60):
    SYS_NET_CONFIG = 61;   # net_config(field) → packed IPv4 datum / 0 unset / -1 bad field

# with the other wrappers:
fn sys_net_config(field): i64 { return syscall(SYS_NET_CONFIG, field); }
```

Optionally a thin convenience set (`sys_net_dns_server()` → `sys_net_config(3)`, etc.),
but the single typed getter is sufficient.

## Consumers to update once it lands (drop the raw form)

- **taar** `src/socket.cyr` — AGNOS block: `var _TAAR_AG_SYS_NET_CONFIG = 61;` +
  `fn _taar_plat_dns_server(): i64 { return syscall(_TAAR_AG_SYS_NET_CONFIG, 3); }`
  → `return sys_net_config(3);` (delete the local constant). `whirl` inherits via taar.
- **yo** `src/platform_agnos.cyr` — `fn platform_dns_server(): i64 { return syscall(61, 3); }`
  → `return sys_net_config(3);`.

This mirrors the prior cohort cleanup where `dig`/`yo` dropped their direct
`syscall(40)/(41)` once 6.2.6 bound chrono and added `sys_uptime_ms`/`sys_sleep_ms`
(see `2026-06-14-chrono-agnos-monotonic-sleep-stale-stubs`). Same pattern: raw number
in consumer code now, typed peer wrapper long-term.

## Hazard note (the reason the wrapper matters)

The raw `syscall(61, …)` form is correct **only** under `CYRIUS_TARGET_AGNOS` — #61 is
the agnos number. On Linux #61 is `wait4`. The consumers gate the raw call behind their
agnos `#ifdef` backend (Linux backends return 0 / read `/etc/resolv.conf`), so there is
no current mis-dispatch, but a typed `sys_net_config` in the agnos-only peer removes the
bare number from consumer source and keeps the Linux↔AGNOS number-overlap hazard
contained to the stdlib peer (consistent with the "consumers MUST use the `sys_*`
wrappers" guidance from the #45–#55 net-peer work).
