# 2026-10-04 — the native TLS server decodes a PEM private key on every accept, on the global heap — ✅ RESOLVED in 6.6.16

**Status:** ✅ **RESOLVED in 6.6.16** (lane thr, bite thr-2, commit `a0bfd181`). A PEM private key is
decoded once per process per distinct key text, not on every accept. sandhi's probe [8], run
unmodified, now reads 0 B/request where it read 120.

See CHANGELOG [6.6.16].

**Filed in:** `sandhi/docs/development/issues/2026-10-04-cyrius-tls-server-pem-key-decoded-per-accept.md` (copied here 2026-10-04, unedited below this header).
**Placement:** **6.6.16** (2026-10-04, with the sandhi 1.10.7 fold).
**Severity:** **P3** — unbounded but slow heap growth in a long-running HTTPS server; no correctness or
security impact. A DER key avoids it entirely.
**Reporter:** sandhi (found while measuring the 1.10.7 pooled-TLS per-request arena fix).
**Toolchain:** cyrius 6.6.15 (sigil 3.13.9 in its snapshot).
**Affects:** every server that hands `tls_accept_alloc_in` (or `tls_accept_alloc`) a **PEM** key. In sandhi
that is `sandhi_server_run_tls` / `sandhi_server_run_pooled_tls` with a PEM key in
`sandhi_server_options_tls`.

## Resolution (6.6.16)

**The second proposal shipped: decode once and reuse, not decode into the accept's arena.** The
filing offered two fixes:
- decode into the per-connection arena `tls_accept_alloc_in` threads;
- decode once per server credential set.

The first is not reachable without editing sigil. `pem_decode_privkey` takes no allocator: it
calls `alloc(pem_len)` itself. The only way round that is to re-implement its label detection and
base64 inside `lib/tls`. Decoding every accept would also keep a per-connection cost the key never
needed. The second fix needs no sigil change.

**Where "once" happens.** cyrius has no call that sets a server's credentials once. `creds` reaches
`lib/tls.cyr` on every accept, and sandhi builds a fresh creds struct on its stack for each one,
on whichever pool worker took the connection. Decoding "where the credentials are set, before any
accept" therefore has no place to happen. So the decode happens at the first load of a given PEM
**text**:
- `_tn_load_privkey` (`lib/tls_native_hs13.cyr`) asks a process-wide cache keyed on the text;
- the first load of a text runs `pem_decode_privkey` once and records its answer: the key
  material and `SIG_PRIVKEY_*`, or the refusal;
- every later load copies that answer into its own ctx (`_tn_alloc`, so the copy lives in the
  accept's arena) and allocates nothing else.

The cache is keyed on the text, not the pointer, because a buffer refilled with another key must
not be served the old one.

**Why not cache DER and re-parse it.** A cached DER parsed per accept through the raw-DER path
would loosen the verdict. That path tries each typed parser in turn, so it would accept a PEM whose
label does not match its body (the PKCS#8 label around a SEC1 key, or the reverse), which
`pem_decode_privkey` refuses. The cache records sigil's own answer, so every key, valid or not,
gets the result it got before. No ctx field was added. `TLS_CTX_OFF_KEY` / `_KEY_LEN` still point at
the caller's PEM.

**Threads, without a wait.** The setup is not single-threaded: a pooled server's workers load
credentials concurrently.
- Entries are immutable once published.
- An entry is prepended under a release fence (aarch64; x86 is TSO), and a lookup walks the list
  lock-free after an acquire fence.
- A miss TRIES a claim word (0 → 1) and, holding it, looks again, decodes, publishes and releases.
- A miss that finds the claim taken does not spin. It decodes uncached exactly as 6.6.15 did, and
  tries again on its next load.

So a cold start can decode a key more than once while workers race on it, but no accept ever
waits on another thread. A child forked while a worker held the claim degrades to the 6.6.15
behaviour instead of hanging. At most 32 distinct texts are cached; a text past that decodes per
load, as before.

**Also covered:** a native client's own key. `tls_native_set_client_key`, and
`tls_ctx_use_private_key_file` on a native client ctx, load through the same function, so an mTLS
client with a PEM key stops leaking per connection too.

**Verification.**
- **The filed repro, unmodified.** sandhi 1.10.7's `programs/_server_tls_probe.cyr` was built
  against this tree, through a throwaway `HOME` + `CYRIUS_HOME` with sandhi's `lib/` vendored from
  the tree:
  - before this bite it reads [8] **120 B/request**, the filed number. The TLS stack and sigil are
    byte-identical between the 6.6.15 tag and the lane's base `b988c064`;
  - with the fix it reads **0 B/request** in three runs out of three. A scratch copy that printed
    `m1 - m0` read exactly 0 bytes over the 41 requests;
  - all eight checks PASS, including [4], the 16 concurrent handshakes against the 4-worker pool.
- **The new test.** `tests/tcyr/crossos/tls_native_pem_key_once.tcyr` has 204 assertions:
  - 10/10 on x86_64, pi, ecb (real threads), ach and cass;
  - 3/3 under qemu-aarch64;
  - the 6.6.15 lib fails 24 of them on each of those five hosts. 40 accepts of the 119-byte key
    cost 4800 B there, the filed 120 B each.
- **Rows.** PEM and DER keys load identical key material and handshake (TLS 1.3 for every form,
  TLS 1.2 for one PEM per algorithm) for Ed25519, P-256 and P-384, in PKCS#8 and SEC1. RSA is
  refused as before (TLS_ERR_KEY_UNSUPPORTED, PEM and DER), because the native stack has no RSA
  signing. A malformed PEM is refused at credential-load time with the error the accept path gave
  before, from the second load on at 0 B.
- **The rest of the corpus.** Every `.tcyr` that includes `lib/tls`, `lib/sandhi` or `lib/sigil`
  (48 files) exits 0 on x86_64.

**For the reporter (sandhi).** No sandhi change is needed: the fix is entirely in cyrius's
`lib/tls_native_hs13.cyr`. After pinning cyrius ≥ 6.6.16, sandhi may:
- drop the guide's DER-key recommendation (`docs/guides/server.md`, Options);
- tighten [8]'s bound from 0..128 to 0.

Both are sandhi's own changes. The notes are in the integration filings.

## What happens

The server credentials are passed to the handshake on every accept. For each one:

1. `lib/tls.cyr:1214` calls `tls_native_server_load_creds(nctx)`.
2. `lib/tls_native_hs13.cyr:1221` (`_tn_load_privkey`) calls sigil's auto-detecting
   `pem_decode_privkey(key, key_len, kmat, 48, &ao)` for any key that is not raw DER.
3. `lib/sigil.cyr:20456` (`pem_decode_privkey`): `var pool = alloc(pem_len);` — from the **global** bump
   allocator, which never frees, and not from the arena the server passed to `tls_accept_alloc_in`.

So every TLS accept leaves `pem_len` bytes (rounded to 8) on the global heap.

## Measured (sandhi 1.10.7, cyrius 6.6.15)

`programs/_server_tls_probe.cyr` check [8] reads the server process's `alloc_used()` before and after 40
HTTPS requests to `sandhi_server_run_pooled_tls` with a per-request arena configured, so every sandhi-side
allocation is rewound:

- Ed25519 `key.pem` (119 bytes): **120 B per request**, all of it this decode.
- The same key as DER: **0 B per request**.

## Workaround (consumer side, today)

Pass the private key as DER (`openssl pkey -in key.pem -outform DER -out key.der`). The native loader takes
raw DER (0x30) without calling the PEM decoder.

## Proposed fix (cyrius-side)

Either:

- decode into the allocator the handshake was given (the per-connection arena that
  `tls_accept_alloc_in` already threads), so the bytes are reclaimed with the connection; or
- decode the key once per server credential set and reuse the DER, since the PEM never changes between
  accepts.

Post-fold note: sandhi composes `tls_accept_alloc_in` and does not decode keys itself (ADR 0001), so this
is not patched in sandhi; the guide (`docs/guides/server.md`, Options) recommends a DER key meanwhile.
