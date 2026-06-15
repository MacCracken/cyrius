# 2026-06-14 — sandhi non-blocking connect uses fcntl/getsockopt, not agnos-ported

> **Class:** vendored-stdlib (sandhi) gap surfaced by the v6.2.3 AGNOS
> net/entropy/clock peer. **Not a v6.2.3 blocker** — sandhi is not on the
> tls_native / http / dig agnos client path (the v6.2.3 probes + agnos gate
> build clean without it). Filed for when a sandhi consumer needs agnos.
> **Status:** filed for triage.

## What

`sandhi`'s own non-blocking-connect primitive `_sandhi_conn_connect_nb_a`
(lib/sandhi.cyr ~1607-1661) issues raw Linux syscalls — `fcntl` (72) for the
`O_NONBLOCK` flag dance and `getsockopt` (55) for `SO_ERROR` — none of which
exist in the AGNOS frozen syscall surface (0-33 + the 1.45.x net band 45-55).
It has **no `#ifdef CYRIUS_TARGET_AGNOS` branch**, so if sandhi is compiled for
`CYRIUS_TARGET_AGNOS` and a caller sets `connect_ms > 0` (the non-blocking
path), it will invoke undefined syscalls.

This is the sandhi analogue of the v6.2.3 fix to cyrius's own
`lib/net.cyr::net_connect_nb`, which now routes to the blocking AGNOS
`sock_connect` (#47) under `#ifdef CYRIUS_TARGET_AGNOS` (the kernel #47 blocks
~8 s polling for the SYN-ACK, which is itself a bounded-timeout connect — AGNOS
has no non-blocking connect). `regression.cyr::regression_network_probe`
already composes on `net_connect_nb`, so it inherits the agnos path for free;
`_sandhi_conn_connect_nb_a` is sandhi's own duplicate of that pattern and was
never folded onto the shared primitive.

## Why it's not a v6.2.3 blocker

The v6.2.3 deliverable (TLS/HTTP on agnos) does **not** pull sandhi:
`tls_native.cyr` and `http.cyr` include `net.cyr` + their crypto/util deps,
not `sandhi.cyr`. The agnos cross-build gate (`scripts/agnos-crossbuild-gate.sh`,
the net/TLS probe) builds tls_native + http + net for agnos with zero sandhi
in the tree. So the gap is latent for any *future* agnos consumer that pulls
sandhi's connection layer with a non-blocking timeout.

## Fix direction (when needed)

sandhi is a **vendored ecosystem stdlib** (`lib/sandhi.cyr` is `cyrius deps`
output — do NOT hand-edit the vendored copy; see
`feedback_ecosystem_libs_are_language_stdlibs_not_upstream`). The fix:

1. Patch sandhi's **source repo** (`~/Repos/sandhi`): give
   `_sandhi_conn_connect_nb_a` an `#ifdef CYRIUS_TARGET_AGNOS` branch that
   routes to the blocking `sock_connect`/`sys_sock_connect` (#47) path —
   mirroring cyrius's `net_connect_nb` agnos branch — or better, fold sandhi
   onto the shared `net_connect_nb` primitive so there is one agnos-aware
   implementation (the v5.10.11 consolidation intent).
2. Release sandhi, then re-fold into cyrius `lib/sandhi.cyr`.

## References

- v6.2.3 cyrius-side fix: `lib/net.cyr::net_connect_nb` + `sock_connect` agnos
  branches; proposal `2026-06-14-agnos-net-entropy-clock-syscalls.md`.
- The v5.10.11 net_connect_nb consolidation (sandhi + regression shared
  primitive) — sandhi kept a private duplicate.

## Resolution (cyrius 6.2.7, 2026-06-15)

RESOLVED via the sandhi 1.5.3 refold. sandhi's C1 work (1.5.1) wrapped
`_sandhi_conn_connect_nb_a` + every raw fcntl/getsockopt socket-syscall site in
`#ifdef CYRIUS_TARGET_AGNOS` / `#ifndef` guards; folding sandhi 1.4.11 → 1.5.3
into `lib/sandhi.cyr` brings those guards in (verified: nb-connect fn guarded at
1627, getsockopt sites inside the `#ifndef AGNOS` blocks). See CHANGELOG [6.2.7].
