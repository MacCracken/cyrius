# `tls_native_set_ca_system` re-reads and re-allocates the whole trust bundle on every call — 1 MiB per TLS connect on the no-free bump

**Status:** ✅ **RESOLVED v6.5.36** — the bundle is read and allocated once per process. ⚠ The failure is cached too, deliberately (`_tn_ca_len == -1`): without that, a machine with no trust store re-walks all four candidate paths on every connect, forever.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-08-27 while closing whirl's roadmap item B3 ("retire the agnos CA hook") — the retirement turned out to be blocked by this.
**Severity:** Medium — a shipping consumer works around it, but the allocation on the TLS connect path is ~5× what it needs to be and the excess is never reclaimed.
**Affects:** cycc **6.2.23 → 6.5.35** (every snapshot checked: 6.2.23, 6.2.52, 6.3.45, 6.4.25, 6.5.35 — `alloc(cap)` present, zero cache logic in all five). Live `lib/tls_native_hs12.cyr` at 6.5.35 is unchanged. Not target-specific: the allocation is outside any `#ifdef`.

## Summary

`tls_native_set_ca_system` allocates a 1 MiB buffer, reads the system trust
bundle into it, hands it to `tls_native_set_ca_bundle`, and returns. It keeps
nothing. The next call allocates another 1 MiB and reads the same file again.

Because `_tls_native_alloc` (`lib/tls.cyr:316`) calls it on every native-backend
client connect, and because the default allocator is a bump allocator with no
`free`, **every TLS connection permanently retains 1 MiB** — regardless of the
bundle's actual size (~185 KB in the case measured, ~250 KB typically).

The cost is invisible in a one-shot tool and compounds in anything that opens
more than a handful of connections: an HTTPS crawl at whirl's 64-resource cap
would retain ~64 MiB of dead heap, and a long-lived client would grow without
bound. This is the same shape as
[`2026-07-28-sock-send-result-allocates-per-call.md`](./2026-07-28-sock-send-result-allocates-per-call.md)
— a per-call allocation on a hot path landing on the no-free global bump — but
six orders of magnitude larger per occurrence.

## Reproduction

Measured on a real AGNOS kernel under QEMU (KVM, virtio-net + SLIRP), cycc
6.5.35, via `tests/agnos_probe.cyr` in the whirl repo — staged as `/bin/agnsh`
so it runs unattended at boot. The probe brackets N handshake-setup rounds with
`alloc_used()` and compares two ways of installing the same roots:

```
var rounds = 4;

# (a) cached: read the bundle once, install from the cache each time
var h0 = alloc_used();
var i = 0;
while (i < rounds) {
    var c1 = tls_native_new_client(host, strlen(host));
    if (c1 != 0) { _agnos_ca_hook(0, c1); tls_native_close(c1); }   # cached install
    i = i + 1;
}
var hook_cost = alloc_used() - h0;

# (b) set_ca_system: a fresh 1 MiB read every time
var s0 = alloc_used();
var j = 0;
while (j < rounds) {
    var c2 = tls_native_new_client(host, strlen(host));
    if (c2 != 0) { tls_native_set_ca_system(c2); tls_native_close(c2); }
    j = j + 1;
}
var sys_cost = alloc_used() - s0;
```

Observed, verbatim from the serial console:

```
PROBE: INFO b3-cost-rounds 4
PROBE: INFO b3-cost-hook-bytes 1072320
PROBE: INFO b3-cost-set-ca-system-bytes 5266624
```

Both loops allocate an identical TLS ctx per round, so the ctx cost cancels:

```
5266624 - 1072320 = 4194304 = 4 x 1048576
```

**Exactly `cap` per call.** The trust bundle actually read was 185,311 bytes, so
~82% of each allocation is slack that is also never reclaimed.

The measurement is on AGNOS only because that is where the consumer runs, but
nothing in the allocation is target-conditional — a host build calling
`set_ca_system` in a loop should reproduce it identically.

## Root cause

`lib/tls_native_hs12.cyr:1591-1620`:

```
fn tls_native_set_ca_system(ctx): i64 {
    if (ctx == 0) { return TLS_ERR_INVALID_PARAM; }
    var cap = 1048576;                          # 1 MiB; system bundles are ~250 KB
    var buf = alloc(cap);                       # <-- every call, never reused
    ...
    return tls_native_set_ca_bundle(ctx, buf, total, 0);
}
```

Two compounding choices: the buffer is allocated per call rather than once, and
it is sized to a 1 MiB worst case rather than to the file. The function has no
state to reuse across calls, and no caller is in a position to hoist it —
`_tls_native_alloc` calls it as part of building each ctx.

Not speculation: the four candidate paths and the read loop are unchanged across
every snapshot in the affected range, and the call site in `lib/tls.cyr:316` is
unconditional for the native backend.

## Proposed fix

Cache the parsed bundle at module scope and install from the cache. Sketch:

```
var _tn_ca_sys_buf = 0;
var _tn_ca_sys_len = 0;

fn tls_native_set_ca_system(ctx): i64 {
    if (ctx == 0) { return TLS_ERR_INVALID_PARAM; }
    if (_tn_ca_sys_buf == 0) {
        ... existing probe + read, but size the alloc to the file ...
        _tn_ca_sys_buf = buf;
        _tn_ca_sys_len = total;
    }
    return tls_native_set_ca_bundle(ctx, _tn_ca_sys_buf, _tn_ca_sys_len, 0);
}
```

Worth deciding alongside it, since they are the maintainer's calls, not mine:

1. **Does `set_ca_bundle` retain the caller's buffer or copy it?** If it retains,
   a shared cached buffer is only safe if no ctx mutates it. Worth confirming
   before sharing one allocation across ctxs.
2. **Is a process-lifetime cache the right staleness contract?** A long-lived
   process would not notice a trust-store update. If that matters, an explicit
   `tls_native_reload_ca_system()` is the usual escape hatch — but note the
   status quo already has the opposite problem in the same place.
3. **Sizing.** Even uncached, `stat`-then-`alloc` (or a grow loop) would drop the
   waste from ~860 KB to ~0 per call. That is the smaller, independent half of
   the fix and could land first.

## Consumer-side workaround (whirl)

whirl carries `_agnos_ca_hook` (`src/transport.cyr`), which reads the same four
candidate paths **once**, caches the bytes, and installs them via
`tls_native_set_ca_bundle` on each connect. It was originally written for a
different reason — the agnos `sys_open` ABI defect in
[`archived/2026-06-18-tls-native-set-ca-system-agnos-sys-open-abi.md`](./archived/2026-06-18-tls-native-set-ca-system-agnos-sys-open-abi.md),
fixed at v6.2.23 — and whirl planned to delete it once that fix landed
(roadmap B3).

**That retirement is blocked by this issue.** With v6.2.23's fix confirmed
working on a real kernel (`set_ca_system` returns 0, verifies a valid chain to
`TLS_OK`, and still rejects a self-signed one), the hook's trust-loading job is
genuinely redundant — but deleting it would reintroduce the per-connect 1 MiB
leak, so whirl now keeps it *as a cache* and has closed B3 as "won't do" with
the measurement above.

Any other consumer on the native TLS backend that opens more than a few
connections is paying the same cost silently, and can adopt the same shape
(read once, `set_ca_bundle` per ctx) until this is fixed upstream. Once
`set_ca_system` caches, whirl's hook becomes a one-line deletion.
