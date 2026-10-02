# Native TLS client: 1 MiB retained per custom-CA load, no allocator-aware connect, alerts read as EOF, stale contract

**Status:** ✅ **RESOLVED v6.6.13** (bite I2 (a)–(e), CVE-60) — the CA-file load retains nothing per call, `tls_connect_alloc_in` / `tls_native_new_client_in` and a shared system root set, one error table (a fatal alert is `TLS_ERR_ALERT`), the contract re-pinned, and `tls_native_ca_skipped`; the libssl `tls_read` / `tls_write` sign defect found here is CVE-60. See CHANGELOG [6.6.13].
**Placement:** **6.6.13**, bite I2 (memory fixes + reported-issue repair, set by the user 2026-10-01) —
see `roadmap.md` § 6.6.13. (e)'s parser half is sigil's: fixed in a sigil release, then refolded.
**Discovered:** 2026-09-30, abaco 2.4.9 TLS study (a long-lived process doing periodic HTTPS
currency fetches with a pinned CA grew the bump heap on every fetch and never gave it back).
**Severity:** Medium for (a) and (b) — unbounded heap growth in any long-lived client; Low for
(c)-(e). One combined issue because they share a fix site and a reviewer.
**Affects:** cyrius 6.6.12 `lib/tls.cyr`, `lib/tls_native_conn.cyr`, `lib/tls_native_hs12.cyr`,
`lib/tls_native.cyr`, `docs/development/lib-tls-contract.md`.

## Summary

**(a) `tls_ctx_load_verify_locations` retains 1 MiB per call.** The native path `alloc`s a
fresh 1 MiB read buffer every call and never frees or caches it — the same bug v6.5.36 fixed
for the system bundle in `tls_native_set_ca_system`, left in its sibling. Measured:
**1,054,864 B retained per call** for a one-cert CA file (20 calls, after a warm-up).

**(b) No allocator-aware client connect.** The server side has
`tls_accept_alloc_in(a, …)` (6.2.25) so a server can `reset_via(a)` each connection's footprint;
the client has no mirror. Every native connect therefore lands on the global no-free bump heap:
the ctx and handshake state (~0.5 MB per connect in the study), plus a full re-parse of the
system trust store into the new ctx (**268,080 B per connect**, measured), and the ctx is never
freed by `tls_close`.

**(c) Every alert record reads as EOF.** `tls_native_read` returns 0 for any alert, so a fatal
alert (`bad_record_mac`, `decode_error`, …) is indistinguishable from a clean `close_notify`.
`TLS_ERR_ALERT` ("peer sent a fatal alert", `tls_native.cyr:104`) exists but is never returned
here. A caller reading a length-less body treats a truncated, attacked stream as complete.

**(d) Docs are stale.** `lib-tls-contract.md` is pinned at v5.10.42 (:3-5, :19) and omits the
6.2.8 trust/mTLS verbs (`tls_ctx_load_verify_locations`, `tls_ctx_set_verify_paths`,
`tls_ctx_use_certificate_file`, `tls_ctx_use_private_key_file`) and the 6.2.24/6.2.25 server
verbs (`tls_accept_alloc`, `tls_accept_complete`, `tls_accept`, `tls_accept_alloc_in`); it
describes only the libssl defaults (:71-76). `tls_native.cyr:12-15` still lists
`tls_native_set_alpn`, `tls_native_set_version_range` and `tls_native_close` as
`TLS_ERR_NOT_IMPLEMENTED`; all three are implemented (`tls_native_hs12.cyr:1481`,
`tls_native_conn.cyr:321`, `:827`). The "TLS 1.2 backport IN PROGRESS" / "NOT YET DONE" lines
(:16-22) look stale too.

**(e) Trust-store roots are skipped silently.** On Arch's `/etc/ssl/cert.pem`, 121 PEM blocks
yield **113 installed roots**; 8 are dropped with no count or diagnostic. Which 8 and why was
not established. A server chaining to one of them fails as `TLS_ERR_CERT_INVALID` with nothing
pointing at the store.

## Reproduction

`repros/2026-09-30-tls-load-verify-locations-1mib-per-call.sh` (+ `.cyr`) checks (a) and prints
the (b) re-parse cost and the (e) block/root counts as info. Makes its CA with `openssl`.

```
docs/development/issues/repros/2026-09-30-tls-load-verify-locations-1mib-per-call.sh; echo "exit=$?"
# -> exit=1 on 6.6.12: 1054864 B/call (limit 65536); info 268080 B/call; 121 blocks / 113 roots
```

(b)'s ~0.5 MB per connect and (c) were measured in the abaco study against a live server and
are not in the repro.

## Root cause

- (a) `lib/tls.cyr:426-438`: `alloc(1048576)` at :430-431 on every call, no cache, no free.
  Compare `tls_native_set_ca_system` (`tls_native_hs12.cyr:1612-1643`), which caches the read.
- (b) `_tls_native_alloc` (`tls.cyr:319-338`) uses `tls_native_new_client` (global heap,
  `tls_native_ctx.cyr:278`, host copy at :286) and re-runs `tls_native_set_ca_system` →
  `tls_native_set_ca_bundle` (`tls_native_hs12.cyr:1544`), an `x509_cert_alloc` per root, on
  every connect. `tls_native_close` documents that it frees nothing
  (`tls_native_conn.cyr:823-826`), and despite that comment's last line the `tls_close` native
  branch (`tls.cyr:964`) does not free the shim either. Server mirror for comparison: `_tls_native_accept_alloc_in` (`tls.cyr:789`) →
  `tls_native_new_server_in` (`tls_native_hs13.cyr:905`).
- (c) `lib/tls_native_conn.cyr:808`: `if (ict == TLS_CT_ALERT) { return 0; }   # close_notify → EOF`.
- (e) `tls_native_hs12.cyr:1570-1579`: a root whose `x509_parse` != 1 is skipped; only the
  stored count survives (:1581).
  **Diagnosed 2026-10-01** (planning; sigil 3.13.5 against this box's `/etc/ssl/cert.pem`, 121 blocks).
  The 8 skipped blocks are:
  - #1, #25, #98: RSA roots self-signed with sha1WithRSAEncryption;
  - #26, #27, #29, #31: RSA-4096 roots self-signed with sha512WithRSAEncryption — Certum ×2,
    D-TRUST BR Root CA 2 2023 and D-TRUST EV Root CA 2 2023, which are current roots;
  - #115: ECDSA P-521 (Microsec).

  sigil's `x509_parse` refuses each on the root's OWN signature algorithm or curve. A trust anchor's
  self-signature is never verified (RFC 5280 §6.1), so the seven RSA roots are usable anchors, and the
  parser fix belongs in sigil. P-521 needs a curve sigil does not have.

## Proposed fix

- (a) Read the file into a buffer sized from `fstat` (or cache by path like the system bundle),
  and allocate it from the ctx's allocator so it dies with the ctx.
- (b) Add `tls_connect_alloc_in(a, sock, host, hook_fp, hook_ctx)` (+ a `tls_native_new_client_in`)
  mirroring `tls_accept_alloc_in`; parse the system store **once** per process into an immutable
  root set shared by reference across ctxs, instead of per connect.
- (c) Inspect the alert: description 0 (`close_notify`) → return 0; any fatal-level alert, or any
  description other than `close_notify` / `user_canceled`, → `_tn_ctx_fail(ctx, TLS_ERR_ALERT)`
  (RFC 8446 §6, RFC 5246 §7.2). Mirror the fix in the libssl branch's error mapping if needed.
- (d) Re-pin `lib-tls-contract.md` to the current surface (trust, server, `_in` verbs, native
  defaults, hostname semantics); drop the KNOWN HOLES block from `tls_native.cyr`.
- (e) Expose the skipped count (e.g. `tls_native_ca_skipped(ctx)`) or log it once under a debug
  flag; investigate which key/signature types sigil cannot parse.

## Consumer-side workaround

(a) Call `tls_ctx_load_verify_locations` sparingly; (a)+(b) run TLS fetches in a short-lived
child process, or accept the growth and bound the fetch rate. (c) Require `Content-Length` (or
chunked framing) and treat a short body as an error; the abaco study's currency fetch rejects a
body whose length disagrees with its `Content-Length`.
