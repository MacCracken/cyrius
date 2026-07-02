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

## v6.3.25 investigation — the FILED FRAMING IS WRONG on two counts (reproduced 2026-07-01)

Reproduced against the real `secureyeoman/yeo-cy-test` (flip `db_path()` note: TLS
`max_conns` 1→4, run `python3 tests/verify.py` → 9h `RECORD_LAYER_FAILURE`). A fast
minimal repro (fresh `ssl.create_default_context()` per connection, GET /api/health)
then corrected the diagnosis:

1. **The aborted handshake is a RED HERRING.** With NO abort at all, handshakes
   **4, 8, 12 fail** — **every 4th handshake fails**, deterministically. 9g merely sat
   one before a 4th.
2. **NOT a multi-worker/concurrency bug.** It reproduces identically at **`max_conns=1`**
   (single worker, single thread) — the offset shifts with startup crypto ops but the
   PERIOD is always 4. "max_conns=1 clean / needs concurrency + accumulated state" is
   inaccurate. The real bug: **every 4th TLS handshake makes the server emit handshake
   records the client cannot decrypt/verify** — deterministic, single-threaded.

**Ruled out by experiment + a 4-angle read (workflow):** the arena allocator
(`lib/alloc.cyr` — clean `[base,pos,end]`, overflow returns 0 without corruption,
`reset_via` fully rewinds); the ctx is **fully memset** every construction
(`_tn_ctx_new_in`, `tls_native_ctx.cyr:131-135`, all 488 B incl. SRV_SEQ@304/CLI_SEQ@312);
sigil's crypto banking (64 banks, **pinned per-thread** → constant for one worker);
the cipher (server always negotiates AES-256-GCM regardless of client offer);
thread-local state (fails single-threaded); entropy batching (`_tn_rand_bytes` →
`sys_getrandom` directly, no buffer). So the period-4 lives in **global per-handshake
state that cycles with period 4** — NOT any per-connection reset.

**Leading hypothesis — a sigil 3.9.7 refold REGRESSION.** Nearly everything the
investigation surfaced is new in the just-refolded sigil 3.9.4→3.9.7 (streaming
Poly1305 `_p1305_state` `sigil.cyr:7355`, the per-lane banking, the `_*_warm` fns).
The bug is almost certainly in vendored sigil (or how tls_native drives it), so the
fix is a **sigil source-repo patch + version bump + re-vendor**, not a native
`lib/tls_native*.cyr` edit. NEXT STEPS to nail it: (a) bisect — re-vendor sigil 3.9.4
(pre-streaming-Poly1305) and re-run the every-4th repro; if it vanishes, it's a 3.9.7
regression; (b) smoking gun — instrument the SERVER HANDSHAKE-FLIGHT seal (the path
that seals with SRV_HS_KEY, NOT `tls_native_record_seal` which only handles app-data)
to dump the handshake traffic key/nonce on a passing vs a failing (4th) handshake.
A minimal repro: `run_pooled_tls` server + a loop of ≥5 fresh TLS 1.3 handshakes,
assert none fail — locks the regression once fixed.

## RESOLVED v6.3.25 — ROOT CAUSE: a thread-local SLOT COLLISION between sigil and patra

Not the record seq / key schedule / arena reset the filing guessed. **sigil's
per-thread crypto-bank lane (`_SIGIL_CBANK_SLOT`) and patra's SQL-parse scratch both
hardcoded cyrius thread-local slot 0** (patra owns 0-4). cyrius's `thread_local_get/set`
is a tiny (16-slot) shared integer space with **no allocator** — two libs picking the
same slot silently clobber each other. In a server linking BOTH (a `run_pooled_tls`
pool serving a patra-backed API — exactly yeo-cy-test), a patra query wrote patra's
scratch into slot 0, overwriting sigil's pinned bank; the next `cbank()` read that
scratch value as the bank index and pointed sigil at the **wrong lane of the
process-global banked crypto buffers** (`var X[N*64]`, indexed `&X + cbank()*N`),
corrupting an in-flight handshake's key schedule → the client's `RECORD_LAYER_FAILURE`.

Root-caused by bisection down to a heisenbug: the failure needed the concurrent HTTP
worker pool (4 workers) running — disabling it, OR adding *any* syscall in the TLS
worker loop, OR growing the pool to 8, all made it vanish (a timing/layout-sensitive
race on the shared bank buffer). Disambiguated fd-vs-timing (getpid fixed it → timing),
then confirmed the collision by moving sigil's slot 0 → 8 and re-running: the full
`verify.py` at `max_conns=4` went **34/34, 9h included**.

**Fix:** sigil source `src/crypto_scratch.cyr` `_SIGIL_CBANK_SLOT` 0 → 8 (sigil 3.9.9),
re-vendored into cyrius `lib/sigil.cyr`. Documented the slot-namespace registry in
`lib/thread_local.cyr`. Regression gate `tests/thread_local_slot_collision.sh`. Consumer
fix: bump the sigil dep to ≥3.9.9 and `max_conns` can return to >1. Two follow-ups filed:
a proper `thread_local_alloc()` slot allocator, and sandhi's `_SANDHI_RPC_POLICY_SLOT=16`
out-of-bounds on macOS/agnos. Filing's "aborted handshake / multi-worker-state / needs
concurrency" framing was all incidental — the bug is a deterministic per-4th-handshake
slot collision.

### Bisect result (2026-07-01) — intermediate note, SUPERSEDED by the RESOLVED root cause above

> **SUPERSEDED.** The bisect *data* below is correct — every sigil version fails the
> every-4th repro — but the *conclusion* ("bug is in tls_native, not sigil; deferred") was
> wrong. The reason ALL sigil versions fail is exactly the root cause found above: every
> version hardcoded `_SIGIL_CBANK_SLOT = 0`, colliding with patra's slots 0-4. It is a
> cross-lib **slot collision**, not a per-version *regression* — so "present across every
> sigil version" and "the fix is in sigil" are both true and not in tension. Fixed in
> sigil 3.9.9 (slot 0→8). Kept for the investigation record.

Bisected sigil by vendoring old dists into the consumer (`git show <tag>:dist/sigil.cyr`
→ consumer `lib/sigil.cyr`, rebuild, re-run the every-4th repro):
- sigil **3.9.7** (current): every-4th FAILS.
- sigil **3.9.5** (pre-TLS-banking, 3.9.6 added banking): every-4th FAILS.
- sigil **3.9.1** (oldest recent): every-4th FAILS.

So the period-4 failure is **present across every sigil version** and **independent of the
3.9.6/3.9.7 banking work** — the "sigil 3.9.7 regression" hypothesis is DISPROVEN. (Correct
reading, per the superseding note: every version collides with patra at slot 0. The banking
work only made the collision's *effect* the crypto-lane corruption; the slot clash predates
it.)

Also ruled out this pass: no 4-entry session/ticket cache (STEK is per-ctx, lazy,
arena-backed; session tickets are per-ctx). The flight-seal instrumentation flagged as the
"next step" here is what ultimately pinned it — dumping the server handshake-traffic
key/DHE across handshakes showed the key schedule going wrong, tracing back to the banked
crypto buffer, then to `cbank()` reading a corrupted slot 0. Consumer returns to
`max_conns>1` once it bumps the sigil dep to ≥3.9.9.
