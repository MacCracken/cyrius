# net.cyr `sock_accept` allocates per poll — accept-loop daemons leak the bump heap

**Filed:** 2026-07-12 (surfaced hardening the mishran audio-routing daemon: mishran 0.5.0/0.5.1 made its own serving loop alloc-free, and this stdlib residual is what's left).
**Severity:** P2 (a slow but unbounded leak that OOMs *long-running* non-blocking accept-poll daemons — the exact sovereign-server use case: mishran `mishrand`, agora, descent, the aethersafha setu listener). No corruption; the process just grows until the bump heap is exhausted.
**Component:** `lib/net.cyr` (`sock_accept`) · `lib/result.cyr` (the 16-byte heap `Result`).

## Context

The bump allocator (`lib/alloc.cyr`) has no per-object free. So any function called in a
daemon's hot loop must not allocate, or it leaks unboundedly. A non-blocking server's
accept-poll loop calls `sock_accept(lfd)` **every tick** — almost always with nothing
pending — so `sock_accept`'s per-call allocations accumulate for the life of the daemon.

Derived from source (`lib/net.cyr:305`), `sock_accept` allocates on **every** call,
including the dominant "none pending / would-block" path:

```
fn sock_accept(fd) : Result {
    #ifdef CYRIUS_TARGET_AGNOS
    ...
    if (cid < 0) { return Err(_NET_EAGAIN); }   # <-- Result = alloc(16), every poll
    ...
    return Ok(cfd);                             # <-- Result = alloc(16)
    #endif
    #ifndef CYRIUS_TARGET_AGNOS
    var client_addr = alloc(16);                # <-- 16 B, every call
    var addrlen = alloc(4);                     # <-- 4 B, every call
    store32(addrlen, 16);
    var cfd = syscall(SYS_ACCEPT, fd, client_addr, addrlen);
    if (cfd < 0) { return Err(0 - cfd); }       # <-- Result = alloc(16)
    return Ok(cfd);                             # <-- Result = alloc(16)
    #endif
}
```

`Result` is a 16-byte heap object (`lib/result.cyr`: "tag at +0, payload at +8, 16-byte
alloc total"), so **`Ok(...)`/`Err(...)` each allocate 16 B**.

**Per-poll cost:**
- **agnos** (`#57` non-blocking accept): `Err(_NET_EAGAIN)` → **16 B / poll**.
- **Linux** (host / mirshi): `client_addr`(16) + `addrlen`(4) + `Err` Result(16) → **~36 B / poll**.

A daemon polling accept in a tight `sched_yield` loop reaches millions of polls in minutes;
at 16–36 B each this exhausts the arena and NULL-faults on the next `alloc`.

## Two independent fixes

### Fix A (cheap, Linux only) — `client_addr` / `addrlen` are dead

`sock_accept` writes `client_addr` + `addrlen` but **never reads them** — it returns only
`Ok(cfd)`, discarding the peer address. `accept(2)` accepts `NULL, NULL`, so:

```
var cfd = syscall(SYS_ACCEPT, fd, 0, 0);   # drop both allocs; peer addr was unused
```

removes 20 B/call on the host path with no behavior change. (If a future caller needs the
peer address, add a `sock_accept_from(fd, out_addr)` variant rather than allocating on the
common path.)

### Fix B (the core one, both targets) — the per-poll `Result` box

The "nothing pending" branch (`Err(_NET_EAGAIN)`) is the overwhelmingly common return and
allocates a fresh 16-byte `Result` every poll. Options, cheapest first:

1. **A shared `Err(_NET_EAGAIN)` singleton.** Pre-build one module-global `Result` for the
   would-block case and return it (callers only read the tag + error code via
   `is_ok`/`result_unwrap`, and must not mutate it — true of every current consumer). Makes
   the steady-state poll (nothing pending) allocate **zero**; only a real accept boxes an
   `Ok`. Smallest change, kills ~all the leak in practice.
2. **A non-allocating `sock_try_accept(fd) : i64`** returning the bare cfd (`>= 0`) or a
   negative would-block/error sentinel — a poll-loop-friendly variant with no `Result` box.
   Consumers doing high-frequency accept polls (the daemons above) switch to it; `sock_accept`
   stays as the ergonomic `Result` API for one-shot use.
3. **A non-allocating `Result` representation** (register/stack-passed sum type instead of a
   heap box) — the general fix, but a much larger compiler/stdlib change; (1) or (2) resolve
   this issue without it.

Recommended: **A + B(1)** — both are localized to `lib/net.cyr` (plus a one-line singleton),
zero API change, and take the daemon accept loop to zero steady-state allocation.

## Reproduction / verification

A host probe measuring `alloc_used()` across N accept polls shows monotonic growth of
~36 B × N today; after A + B(1) it should be flat (0 growth once the singleton exists). The
mishran `programs/client_leak_probe.cyr` already isolates this: its client hot path measures
**0** growth, and it explicitly attributes the remaining non-zero `msh_server_poll` residual
to this `sock_accept` allocation ("out of scope — a cyrius-side fix").

## Also (inherent, not a bug)

`sock_accept` returning a `Result` is the right ergonomic API for one-shot accepts; the leak
is only from calling it in a poll loop on a no-free allocator. The daemons could also cache
one `Result` and re-poll less aggressively, but the stdlib fix is the correct home — every
sovereign accept-poll server hits this.

---

**RESOLVED — v6.4.61** (2026-07-12). Fix A (Linux/macho accept(NULL,NULL) — dead peer-addr buffer) + Fix B (lazy shared Err(_NET_EAGAIN) singleton for the would-block path). Probe: 0 B growth over 100k polls (was 4,000,000 B); singleton is a correct Err(11), same pointer reused. Regression gate tests/net_accept_no_leak.sh. lib/net.cyr not in cycc → self-host byte-identical. See CHANGELOG [6.4.61].
