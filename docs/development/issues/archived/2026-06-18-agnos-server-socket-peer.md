# Wire the CYRIUS_TARGET_AGNOS server-socket peer to kernel sock_listen#56 / sock_accept#57

**Status**: Open — request from the agnos side (incoming kernel-surface change). Action is cyrius-side: wire `lib/net.cyr`'s AGNOS server shims.
**Date**: 2026-06-18
**Priority**: **HIGH — AGNOS closed-beta Phase-1 gate.** The 2026-06-14 beta rescope makes the founder **Docker AGNOS service-sweep at the server base** (agora / descent / sandhi / web *accepting* connections) the closed-beta opening gate (Late June / Early July 2026). This peer is the one piece between "the AGNOS kernel can `accept()`" and "a Cyrius service binary compiled `--agnos` can `accept()`." Until it lands, no `--agnos` service can host a socket.
**Mirror of**: `agnos/docs/development/issues/2026-06-18-cyrius-agnos-server-socket-peer.md` (the agnos-side filing with the full kernel ABI).
**Supersedes the "not wanted yet" framing** in `docs/development/issues/2026-06-15-cyrius-thread-agnos-clone-dispatch.md` / the agnos `2026-06-15-cyrius-stdlib-missing-syscalls.md` cross-file: those were filed when AGNOS exposed only band 45–55 and inbound-TCP server was "Phase B, not wanted." Both premises changed — the kernel landed #56/#57 (1.45.5/.6) and the server is now the gate.

## What changed

The v6.2.3 client-band peer and the 6.2.7 completeness pass deliberately fail-loud the AGNOS server shims because, at the time, AGNOS had no ring-3 listen/accept surface. **That surface now exists:**

- **agnos 1.45.5** — `sock_listen#56` + `sock_accept#57` (bind+listen merged; accept non-blocking, `net_poll`-driven). `tcp-listen-smoke` 2/2 (host `netcat` → AGNOS accept).
- **agnos 1.45.6** — hardening fixed the CRITICAL LISTEN-slot reuse aliasing (`tcp_close` reaps pending children).

So the comment in `lib/net.cyr:260-262` — *"the ring-3 listen/accept surface isn't exposed yet"* — is now **stale**.

## Kernel ABI to wire against (from `agnos/kernel/core/syscall.cyr`, verified 1.45.10)

- **`sock_listen#56`**: `sock_listen(port = arg1) -> listen_id (0..7)` or `-1`. Validates `1 <= port <= 65535`. **Merges bind+listen** (kernel `tcp_bind` == `tcp_listen`, ip unused) — BSD `bind()`+`listen()` fold onto this one call. Non-blocking. `a2..a4` unused.
- **`sock_accept#57`**: `sock_accept(listen_id = arg1) -> conn_id (0..7)` or `-1` (none-pending = WOULD_BLOCK / bad listen_id / not a LISTEN slot). **Non-blocking**, calls `net_poll()` first (drives `SYN→SYN_RCVD→ESTABLISHED`) then `tcp_accept`. The returned conn_id is a **normal connection** usable with the already-wired `sock_send#48` / `sock_recv#49` / `sock_close#50`. `a2..a4` unused.

## cyrius shims to replace (`lib/net.cyr` @ 6.2.21)

```
sock_bind(fd, addr, port) : Result   # L263 — #ifdef CYRIUS_TARGET_AGNOS return Err(1)
sock_listen(fd, backlog)  : Result   # L276 — #ifdef CYRIUS_TARGET_AGNOS return Err(1)
sock_accept(fd)           : Result   # L288 — #ifdef CYRIUS_TARGET_AGNOS return Err(1)
```

## Requested wiring

1. **`sock_bind` + `sock_listen` → one `sock_listen#56(port)`.** Kernel merges bind+listen, so collapse the BSD two-call split (have `sock_bind` stash the port; `sock_listen` issue `#56`, or fold both into the AGNOS path). `#56` returns a **listen_id**, not a BSD fd → add a **listen_id ↔ fd adapter** mirroring the existing conn_id ↔ tagged-fd adapter (the one routing `sys_read`/`sys_write` for socket fds via `#48`/`#49`). `backlog` advisory (8-slot conn table) — accept + ignore.
2. **`sock_accept` → `sock_accept#57(listen_id)`.** Map the listen-fd back to its listen_id, issue `#57`. On `-1` return `Err(EWOULDBLOCK)` (mirror the client `sock_recv#49` WOULD_BLOCK handling) so the non-blocking accept poll-loop works. On success, **wrap the returned conn_id in a tagged socket fd** via the existing client-band adapter → the accepted connection transparently uses `sock_send#48`/`sock_recv#49`/`sock_close#50`.
3. **Drop the stale `AGNOS Phase B / not exposed yet` comments** (`lib/net.cyr:260-262` + per-fn notes).

No new kernel work is needed — the kernel ABI is complete and hardened. The optional `SO_REUSEADDR` / `shutdown` socket-options (the 6.2.7 issue) stay no-op; they are nice-to-haves once server workloads stress them, not gates.

## Consumers unblocked

`agora` (telnet BBS — note: its fork-per-connection model has no AGNOS analog; the port maps onto `spawn#3`/`spawn_path#43` + `waitpid#4` or a single-process accept loop — service-side concern), `cyrius-yeomans-descent` (MUD), `sandhi` HTTP server, sovereign remote-shell, web server.

## Verification

Build a trivial Cyrius echo-server `--agnos`, stage to `/bin`, boot under QEMU+OVMF+gnoboot with SLIRP hostfwd (reuse `agnos/scripts/tcp-listen-smoke.sh`), confirm a host `netcat`/`curl` round-trips `#56 → #57 → #48/#49 → #50`. Kernel half already passes `tcp-listen-smoke` 2/2; this proves the cyrius peer end-to-end.

## Resolution — v6.2.22 (2026-06-18)

**RESOLVED (cyrius-side).** Wired the listen↔fd adapter exactly as requested:
`sock_bind` stashes the port, `sock_listen` issues `#56` (listen_id stored in the
fd's adapter slot), `sock_accept` issues `#57` + wraps the accepted conn_id in a
fresh tagged `#48`/`#49`/`#50` fd; `Err(EAGAIN=11)` on none-pending for the
non-blocking poll-loop. Stale "Phase B" comments dropped. Pure stdlib — 1-arg
syscalls, **no codegen change** (cycc byte-identical on every target).
`agnos-crossbuild-gate.sh` probe **1d** guards the surface (compile + emit-inspect
`syscall(56/57)`, not a stub).

A 4-dimension adversarial review caught + fixed **two real bugs** the compile-only
gate misses (both verified against the agnos kernel `net_tcp.cyr`): (1) `sock_accept`
**leaked the just-`#57`'d kernel conn** when the cyrius 8-slot fd table is full —
`#57` commits the accept kernel-side, so a dropped `cid` orphaned an 8-slot conn
forever; now reaps it via `#50` on the full-table path. (2) `sys_close`'s non-listen
path left `_agnos_listen_port` stale → a recycled slot could silently mis-listen;
now every socket-fd close zeroes all three slot tables uniformly.

End-to-end QEMU echo-server smoke (the §Verification above) is the agnos-side /
consumer run; the cyrius peer is compile-/emit-/review-verified here. The optional
`SO_REUSEADDR` / `shutdown` socket-options stay no-op (not gates).
