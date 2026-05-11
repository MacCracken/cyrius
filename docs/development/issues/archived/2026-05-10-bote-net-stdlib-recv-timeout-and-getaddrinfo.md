# Cyrius: bote needs `sock_set_recv_timeout` and a `getaddrinfo` stub in `lib/net.cyr`

**Filed:** 2026-05-10
**Reporter:** bote (MCP core service, v2.7.1)
**Cyrius version at time of report:** 5.10.34 (release tarball + source archive)
**Affected stdlib:** `lib/net.cyr`
**Severity:** **P2** — both gaps have *partial* coverage on bote's side
already; neither is a hard ship-blocker, but both leave bote with
documented production risk that consumers have to mitigate at deploy
time (egress firewall, ALB-side timeouts) rather than at the bote
boundary.
**Status:** open. **Expected target:** **5.11.x arc**.

## Summary

Two distinct holes in `lib/net.cyr` that bote tracks as "audit
items" — both flagged in bote's roadmap "Blocked on cyrius / external"
table since the 1.9.5 security audit (~6 releases ago).

| Gap | Audit item | What bote can do today | What bote needs to do |
|---|---|---|---|
| `sock_set_recv_timeout(fd, secs, usecs)` | **H5 (Slowloris recv timeout)** | Accept a connection, read until 64 KB or `\r\n\r\n`. No per-socket recv deadline. | Set `SO_RCVTIMEO` on the accepted client fd so a slow attacker can't hold a worker thread open indefinitely sending one byte per minute. |
| `getaddrinfo(name, family) -> vec<sockaddr>` or equivalent | **DNS for hostname SSRF** | Hostname-blocklist match against a static list (`localhost`, `metadata.google.internal`, `metadata`, etc.). | Resolve the hostname *first*, then run the SSRF classifier against the resolved IP set. Without resolution, a hostile DNS record can publish a private IP and bypass the IP-level guard entirely. |

## Detail per gap

### `sock_set_recv_timeout(fd, secs, usecs)`

Linux `setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeval, sizeof(timeval))`
with `timeval = {tv_sec=secs, tv_usec=usecs}`. The kernel-side machinery
is trivial; the gap is a Cyrius-side wrapper that bote can call from
its accept loop without re-rolling the `setsockopt` raw syscall in
every transport file.

**Today:** bote's HTTP / WS / streamable transports all share the same
4-line accept pattern (`accept` → `read until\r\n\r\n or 65535` →
`dispatch` → `respond` → `close`). The read loop has no deadline; a
Slowloris-style client can sit on `recv` indefinitely. bote's mitigation
(`Connection: close` on every response + small per-fd buffer) caps the
*memory* footprint but not the *thread-blocking* footprint. With
process-global threads (no per-fd worker; see the streaming-dispatch
issue for the threaded-server precursor), one slow client blocks the
whole transport.

**Async-signal-safety:** none required — the call happens on the
parent thread after `accept` returns, well before any signal-handler
context.

**Proposed shape:**

```cyrius
# lib/net.cyr
fn sock_set_recv_timeout(fd, secs, usecs) {
    var tv[16];
    store64(&tv,     secs);
    store64(&tv + 8, usecs);
    return setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, 16);
}
```

`setsockopt` itself is already in `lib/syscalls.cyr` — bote can verify
that. If it isn't, the wrapper needs the raw syscall too (syscall
number 54 on x86_64 Linux, 208 on aarch64).

### `getaddrinfo(name, family) -> vec<sockaddr>`

The hostname-to-IP-set resolver. bote's SSRF classifier
(`src/host.cyr::ssrf_check` + `_ssrf_classify_hostname`) currently
**only** matches hostnames against a static blocklist (`localhost`,
`metadata.google.internal`, `metadata`, plus the IPv4 / IPv6 literal
form paths). A hostile DNS record like
`evil.example.com. A 169.254.169.254` would pass the hostname check
(not in the blocklist), and the IP check never runs because we haven't
resolved.

**Today:** bote's SSRF guard is documented as "conservative; does NOT
resolve DNS" in `src/host.cyr:241`. Production callers are expected to
pair bote with a network-policy egress block that prevents the
unresolved hostname → metadata IP path at the network layer. This is a
real deployment tax we'd like to lift.

**Proposed shape:**

```cyrius
# lib/net.cyr — minimum viable

# Returns a vec of resolved IP literals as cstrs (e.g. "127.0.0.1",
# "::1"). Empty vec on resolution failure. Caller iterates the vec
# and runs the existing ssrf_classify_ipv4 / _ipv6 on each.
fn getaddrinfo_hosts(name, family) -> i64  # family: 0=any, 4=v4 only, 6=v6 only
```

The full `struct addrinfo` is overkill for bote's needs — bote just
wants the IP literals so it can re-run its own classifier. A simpler
"return a vec of cstrs" surface keeps the SSRF guard small and the
classifier path single-stack.

**Caveat — DNS rebinding:** even with `getaddrinfo`, bote can't fully
solve DNS rebinding (the attacker serves a public IP at resolve time,
then flips to private before the actual connect). The right defense
is "resolve once, connect to the resolved IP literal directly, don't
re-resolve". This is a separate bote-side change once the resolver
surface lands. Not in scope for this issue.

## Reproduction

These are absences, not bugs. Reproduction = "read
`docs/development/roadmap.md` of bote 2.7.1 and confirm both items
sit unresolved in the 'Blocked on cyrius / external' table".

bote-side surfaces that wait on each:

- **Slowloris:** `src/transport_http.cyr`, `src/transport_streamable.cyr`,
  `src/transport_ws.cyr`, `src/bridge.cyr` — every accept loop. One
  `sock_set_recv_timeout` call per accepted fd, before the first read.
- **DNS for SSRF:** `src/host.cyr::_ssrf_classify_hostname` — currently
  the terminal classifier path; would gain a "resolve + classify each
  resolved IP" branch.

## Consumer-side workaround

**Slowloris:** bote could inline a `setsockopt` raw syscall in each
transport file. ~5 lines per file × 4 transport files = 20 lines of
duplicated raw-syscall surface. Same async-signal-safety review burden
each time (it's not safety-sensitive here, but a centralized wrapper
makes the audit easier across the AGNOS tree). bote has chosen to
wait on the centralized wrapper rather than ship the duplication.

**DNS for SSRF:** the documented mitigation is "pair bote with a
network-policy egress block that denies 169.254.0.0/16,
10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, RFC 4193 IPv6 ULA, and
link-local IPv6". This pushes the security boundary off-host, which
is the correct posture for defense-in-depth but a real burden for
single-host deployments (CI runners, dev boxes, edge devices).

## Severity rationale

P2 (not P1) because:

- **Slowloris** is a DoS class; bote's process model (single accept
  thread, no per-conn worker yet) caps the blast radius — one slow
  attacker freezes that *one* transport but doesn't crash the
  process, and the network-policy stopgap (per-IP connection rate
  limit at the load balancer) is industry-standard.
- **DNS for SSRF** has the egress-block stopgap that real production
  deployments already run as a separate layer.

Bumps to P1 if:

- An AGNOS-side production deployment ships bote single-host without
  egress filtering (e.g. an edge / IoT scenario).
- A new transport mode (UDP? QUIC? — speculative) lacks an obvious
  socket-deadline surface to lean on.

## Related issues

- [`2026-05-10-bote-streaming-dispatch-thread-async-primitives.md`](2026-05-10-bote-streaming-dispatch-thread-async-primitives.md) — the threading work; if/when bote moves to per-conn workers, the Slowloris blast radius widens unless the recv-timeout is in place first.

## Pointers

- bote roadmap: https://github.com/MacCracken/bote/blob/main/docs/development/roadmap.md
- bote `src/host.cyr:241` — the "DOES NOT resolve DNS" disclaimer.
- bote `src/transport_http.cyr` accept loop — the Slowloris-exposed read path.
- bote `docs/spec-compliance.md` — the 1.9.5 audit reference.
