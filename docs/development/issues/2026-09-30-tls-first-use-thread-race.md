# Native TLS: first use from two threads poisons the process; first use on a worker then on main SIGSEGVs

**Status:** 🟡 **OPEN** — found by an abaco 2.4.9 TLS study; not repaired.
**Placement:** **6.6.13**, bite I3 (memory fixes + reported-issue repair, set by the user 2026-10-01) —
see `roadmap.md` § 6.6.13. The lazy inits and the main-thread TLS block are **sigil source**: they are
fixed in a sigil release and refolded (CLAUDE.md: fix the source repo, not the fold). The `lib/tls*.cyr`
half is cyrius's own.
**Discovered:** 2026-09-30, abaco 2.4.9 TLS study (two threads each doing HTTPS currency
fetches as their first TLS use: every fetch failed, in every run).
**Severity:** High for multi-threaded clients (permanent, silent loss of TLS for the process,
or a crash); Medium overall — single-threaded consumers and anyone who touches TLS on the main
thread first are unaffected.
**Affects:** cyrius 6.6.12 native backend: `lib/sigil.cyr` lazy inits and `crypto_tls_main_init`
(:5140), `lib/tls_native_hs12.cyr` system-CA cache (:1608-1615), reached through
`tls_connect` / `tls_connect_with_ctx_hook` (`lib/tls.cyr` :753 / :763). libssl untested.

## Summary

Nothing in `lib/tls.cyr` initialises sigil before the first handshake, and sigil's lazy
initialisers are a mix of race-safe and race-unsafe. With an ECDSA P-256 chain:

- **A — concurrent first use poisons the process.** Two threads whose first TLS connects
  overlap: **10 of 10** handshakes fail (4/4 runs in the study, 2/2 here).
- **B — the poison is permanent.** A third thread started after both joined: **5 of 5** fail.
- **C — worker first, then main: SIGSEGV.** One worker thread does its connects (they
  succeed), is joined, then the main thread's first connect kills the process (signal 11).
- **D — control.** Calling `crypto_tls_main_init(); ecdsa_p256_warm(); ecdsa_p384_warm();` on
  the main thread first makes A, B and the main-thread follow-up 100% OK.

Narrowing D: `crypto_tls_main_init()` alone does **not** fix A/B; `ecdsa_p256_warm()` alone
does. So the poisoning is in the curve/hash table inits, not only the bank/TLS-block setup.
Only P-256 chains were exercised; the RSA, Ed25519 and x509-PEM init paths are unproven.

## Reproduction

`repros/2026-09-30-tls-first-use-thread-race.sh` (+ `.cyr`). Makes a P-256 CA and server cert
with `openssl`, runs two `openssl s_server`s (s_server is serial, so each thread gets its own
server and the handshakes really overlap), then runs each scenario in a fresh `fork()` so it
starts with cold lazy state. Exit code = failing checks.

```
docs/development/issues/repros/2026-09-30-tls-first-use-thread-race.sh; echo "exit=$?"
# -> exit=3 on 6.6.12 (A: 10/10 fail, B: 5/5 fail, C: signal 11; D passes)
```

## Root cause

- **Race-unsafe lazy inits (A/B).** Many sigil table inits are plain check-then-set with the
  flag stored last, so two first-callers both run the body, both `alloc` (the bump allocator
  is not thread-safe — sigil's own note at `sigil.cyr:5124-5128`, quirk #7) and overwrite the
  shared table pointers while the other is using them: `sha256_global_init` (:6114-6183),
  `_p256_init` (:13324-13335), `_onc_init` (:13634), `_p256_inv_init` (:13690), and the rest of
  the P-256 / P-384 family flagged at :13755, :13911, :13977, :14145, :14259, :14504, :14777,
  :15223, :15724, :15831, :15881, :16017, :16105, :16219, :16392, :16445, :16872, :16970, plus
  `_x509_mdays_inited` (:17707). The AES / SHA-512 / BLAKE2b / Ed25519 inits already use the
  safe 0 → 1 → 2 atomic publish (e.g. `_aes_inited`, :7255, :7309-7328). Same shape outside
  sigil: `tls_native_set_ca_system`'s bundle cache (`tls_native_hs12.cyr:1608-1615`, published
  at :1642-1643) is unsynchronised.
- **TLS block installed on the wrong thread (C).** `cbank()` (:5172) lazily calls
  `crypto_tls_main_init()`, which runs `thread_local_init()` for the **calling** thread and
  claims bank 0 for it (:5140-5147). When the first caller is a worker, the main thread is
  never given a TLS block; `_crypto_tls_inited` is already 1, so main's first `cbank()` most
  likely reads thread-local storage that was never installed.
- **The contract exists, but only inside sigil.** `sigil.cyr:5130-5138` and the
  `ecdsa_p256_warm` header (:17131-17141, ADR 0007) both say a multi-threaded consumer MUST
  prewarm on the main thread. `lib/tls.cyr` hides sigil behind `tls_connect`, never prewarms,
  and never passes the requirement on to its callers.
- Compiler warning seen on every build: `sigil.cyr:26928` `var buf[262144]` is over the frame
  budget and gets static storage shared by all threads (banked by `bk`, so likely fine, but
  worth confirming while here).

## Proposed fix

1. Convert every check-then-set lazy init above (and `_tn_ca_buf`/`_tn_ca_len`) to the
   existing 0 → 1 → 2 atomic publish pattern.
2. Add a public verb, e.g. `tls_init_main()` / `tls_warm()` in `lib/tls.cyr`, that runs
   `crypto_tls_main_init()` and warms every lazy init a handshake can reach (SHA-256/384/512,
   HKDF, AES-GCM, ChaCha20, X25519, P-256, P-384, RSA, Ed25519, x509 date tables, system CA
   cache). Idempotent; cheap after the first call.
3. Make the main-thread TLS-block setup independent of which thread arrives first (install
   main's block at `alloc_init` / process start, or record main's tid and refuse to treat a
   worker as main).
4. Contract note in `docs/development/lib-tls-contract.md`: thread-safety of the client and
   server verbs, and "call `tls_init_main()` on the main thread before spawning TLS threads"
   until (1) and (3) land.

## Consumer-side workaround

Before any thread can touch TLS, on the main thread:
`crypto_tls_main_init(); ecdsa_p256_warm(); ecdsa_p384_warm();` (all three are public in
6.6.12). Sound for ECDSA P-256 chains as measured; for RSA or Ed25519 chains, also do one
throwaway handshake (or one signature verify of that type) on the main thread first.
