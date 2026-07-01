# Multi-worker server TLS: `RECORD_LAYER_FAILURE` under a mixed/accumulated request pattern (max_conns > 1)

**Filed:** 2026-07-01 (by the `yeo-cy-test` consumer; cyrius 6.3.23, sandhi 1.7.0 /
sigil 3.9.7 folded)
**Severity:** Medium — the last blocker to a multi-worker HTTPS server. Pure
concurrent load is clean; this is a state-dependent record-layer failure at
`max_conns > 1`.
**Component:** `tls_native` record/handshake state per connection, and/or sandhi's
`run_pooled_tls` per-connection arena reset (`lib/tls_native_*.cyr` +
`src/server/mod.cyr` `_sandhi_server_pool_tls_worker`). Distinct from the (now-fixed)
`str_builder` `BAD_SIGNATURE` — this is `RECORD_LAYER_FAILURE`.

## Context — the good news first

With str_builder fixed (6.3.15) and sigil 3.9.7 auto-banking, multi-worker HTTPS
mostly works: `sandhi_server_run_pooled_tls` at `max_conns=4` serves **100/100
concurrent HTTPS POSTs cleanly** (all unique ids, no crash, no BAD_SIGNATURE). This
issue is the one remaining gap.

## Symptom

Under the probe's **full test suite** (`tests/verify.py`) at `max_conns=4`, HTTPS
scenario **9h deterministically fails** (3/3 runs) with
`ssl.SSLError: [SSL: RECORD_LAYER_FAILURE]` on the TLS handshake — a client-side
record-layer/decrypt failure meaning the server emitted a record whose MAC/framing
the client can't verify. The failing handshake is a plain trusted HTTPS GET; what
precedes it is:
- 34 plaintext HTTP scenarios (incl. a server restart + 250-concurrent POSTs),
- 9 **sequential** HTTPS handshakes (fresh conn each, `Connection: close`), one of
  which (9g) is an **untrusted-cert client that the handshake rejects/aborts**.

## What's ruled out / narrowed

- **Not str_builder** (fixed; `concurrency_repro.sh` 0/300; the failure mode here is
  RECORD_LAYER, not the old BAD_SIGNATURE).
- **Not pure concurrency** — 100 simultaneous HTTPS POSTs are clean.
- **Not the untrusted-abort in isolation** — a fresh server doing `trusted → untrusted
  (rejected) → trusted ×5` is clean (5/5).
- It needs the **accumulated state** (the full prior HTTP+HTTPS traffic) to surface,
  which points at a per-connection TLS-state buildup / stale-state-not-reset on a
  pooled worker at `max_conns > 1` (single worker = clean; the probe ships
  `max_conns=1`).

## Ask

Reproduce under a pooled-TLS server (>1 worker) driven by a mixed sequential pattern
(many fresh HTTPS conns including one client that aborts mid-handshake, interleaved
with other traffic) and check whether a worker's per-connection state (record seq /
key schedule / arena reset after an aborted handshake) leaks into the next handshake
it serves. A `run_pooled_tls` gate that drives an aborted handshake then asserts the
next N handshakes on the same pool succeed would lock it.

## Consumer status

`yeo-cy-test` pins its TLS pool to `max_conns=1` (suite green + stable) until this is
root-caused; it bumps to 4 the moment it's fixed. Filed probe-side in
`yeo-cy-test/FINDINGS.md` + the `src/main.cyr` serve-loop comment.
