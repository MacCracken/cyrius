# `tls_native` server ctx is not arena-aware and is never freed — per-connection RSS growth on a long-running TLS server

> **PINNED → v6.2.25 (committed).** Deliberately NOT bundled into v6.2.24 (which
> shipped the `tls_accept` wrapper). A v6.2.24 premise-check confirmed this is the
> **full-depth-or-nothing** case: a correct fix requires threading a per-connection
> arena through `tls_native_new_server` + `tls_native_accept` + the keysched/
> transcript HKDF derivations + sigil's `x509_cert_alloc`/ECDHE scratch (~100+
> `alloc()`→`alloc_via()` across 6 modules **plus a sigil source patch + re-fold**),
> NOT a surface-only ctor or a no-op `free()` over the global bump. The bar for
> .25: `tls_native_new_server_in(arena, …)` (mirroring the v6.1.22 `async_new_in`
> precedent) with the full per-handshake footprint drawn from the arena, so a
> server loop `reset_via(arena)` per connection → flat RSS. sandhi documents the
> leak as a known limitation today (no regression from deferring). The `tls_accept`
> wrapper (v6.2.24) is the public surface that will expose the chosen ctor.

**Discovered:** 2026-06-18 during sandhi 1.6.8 server-side TLS (`sandhi_server_run_pooled_tls`).
**Severity:** Medium — a long-running `tls_native` **server** leaks per accepted connection: RSS grows unbounded over the lifetime of the process. No correctness impact on serving; the ceiling is memory.
**Affects:** `lib/tls_native_hs13.cyr` (`tls_native_new_server`), `lib/tls_native_conn.cyr` (`tls_native_accept` / `tls_native_close`), 6.2.22. The client side has the same allocator but is bounded in practice by connection pooling; the server cannot pool inbound connections, so it is exposed.

## Summary

A `tls_native` server creates **one ctx per accepted connection**:

```cyrius
var nctx = tls_native_new_server(cert, cert_len, key, key_len);   # _tn_ctx_new → alloc
tls_native_server_load_creds(nctx);                               # alloc (key mat, leaf)
tls_native_accept(nctx, fd);                                      # alloc (record buffers, flight)
...serve...
tls_native_close(nctx);   # sends close_notify; does NOT free the ctx (bump alloc)
```

`tls_native_close`'s own contract says it: *"the ctx is bump-allocated (no
per-object free), so this does NOT free the ctx storage — that is reclaimed at
arena/process teardown."* For a **client** that's fine — `tls_connect` ctxs are
few and pooled. For a **server** that accepts connection after connection for
days, every handshake's ctx + record/flight buffers accumulate on the global
bump with no reclamation → steady RSS growth.

## Reproduction

Stand up any `tls_native` server (e.g. sandhi's `programs/_server_tls_probe.cyr`,
or `tests/tcyr/tls_native_ed25519.tcyr` in an accept loop) and drive a sustained
stream of connections; RSS climbs monotonically with connection count and never
recovers after the peers disconnect.

## Root cause

The ctx + all per-handshake allocations come from the process-global bump
allocator (`alloc`), and there is no `tls_native_*` server-ctx free nor an
arena-parameterized constructor. `tls_native_close` deliberately doesn't free
(the bump allocator has no per-object free).

## Proposed fix (one of)

1. **Arena-parameterized server ctx** — `tls_native_new_server_in(arena, cert,
   cert_len, key, key_len)` (mirroring the `async_new_in(arena)` precedent that
   fixed the async per-conn task-struct leak at v6.1.22), with `tls_native_accept`
   drawing its record/flight buffers from the same arena, so the consumer can
   `reset_via(arena)` per connection. This is the cleanest fit for a
   per-connection-arena server loop.
2. **Server-ctx free** — a `tls_native_server_ctx_free(ctx)` that releases the
   ctx + its owned buffers, callable after `tls_native_close`, for consumers not
   using an arena.

Option 1 composes best with the existing arena patterns and lets a server reset
one arena per connection (zero residual, RSS flat — the shape
`sandhi_server_run_async` already uses for its per-batch arena).

## Consumer-side workaround (in place)

None available today — sandhi cannot redirect the native stack's internal
`alloc` calls to a consumer arena without forking the primitive (forbidden by
sandhi's compose-don't-reimplement rule). sandhi 1.6.8 documents the
per-connection RSS growth as a known limitation and ships with it (the same
property the yeo-cy-test probe shipped with); a long-running sandhi TLS server
should budget for it until this lands.

## Related

- `2026-06-18-lib-tls-cyr-no-server-handshake-wrapper.md` — the other open
  server-TLS residual (contract asymmetry); a `tls_accept` wrapper there could
  expose whichever fix (arena ctor vs free) this issue picks.
- v6.1.22 `async_new_in(arena)` — the precedent for the arena-parameterized fix.
