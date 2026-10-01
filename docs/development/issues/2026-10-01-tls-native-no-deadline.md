# Native TLS client: no deadline, and plaintext ChangeCipherSpec skipped without limit (handshake and after)

**Status:** 🟡 **OPEN** — found by the abaco 2.4.12 HTTPS review; not repaired.
**Placement:** **6.6.13**, bite I8 (placed by the user 2026-10-01) — see `roadmap.md` § 6.6.13. It shares
`tls_native_read` with I2 (c), the alerts read as EOF: take the two in sequence in the TLS lane, with one
error-mapping table.
**Discovered:** 2026-10-01, abaco 2.4.12 review (an HTTPS currency fetch never returned while a
peer — or anyone on the path, with no key — sent a byte, or a ChangeCipherSpec record, more often
than the socket's read timeout).
**Severity:** Medium — any peer, and any on-path box without a certificate or key, can hold a
client thread for ever; the caller has no way to bound or cancel it. Low for (c).
**Affects:** cyrius 6.6.12 `lib/tls_native_conn.cyr` (`_tn_sock_read_full` :529,
`_tn_sock_read_record_skip_ccs` :561, `tls_native_read` :739), `lib/tls_native_hs12.cyr` and
`lib/tls_native_hs13.cyr` (the same skip at every handshake read).

## Summary

**(a) ChangeCipherSpec records are skipped without limit, in the handshake and after it.**
`_tn_sock_read_record_skip_ccs` loops over any number of plaintext CCS records (`14 03 03 00 01 01`)
before returning the next record, and every handshake read and `tls_native_read` go through it.
RFC 8446 §5: a TLS 1.3 implementation may receive an unprotected CCS only "at any time after the
first ClientHello message has been sent or received and prior to the receipt of the peer's
Finished message", and "MUST terminate the connection with an `unexpected_message` alert" for one
outside that window — and middlebox compatibility needs at most one. A CCS needs no key, so an
on-path attacker can inject one per second into a verified session and the client waits for ever.

**(b) No deadline.** `_tn_sock_read_full` loops `read(2)` until `n` bytes arrive. With
`SO_RCVTIMEO` set, each `read` is bounded but the loop is not: a peer that sends one byte just
inside the timeout holds a 16 KB record read for days (a record header announcing 16,000 bytes,
then a byte every 9 s: ~40 h). Nothing in the client takes a deadline, and the transport vtable
(`_tn_tx_read`) is process-global, so a caller cannot install a per-connection one either.

**(c) Every record-read failure is reported as `TLS_ERR_IO`.** `tls_native_read` (:776) and the
handshake drivers map any negative `_tn_sock_read_record*` result to `TLS_ERR_IO`, including
`TLS_ERR_BUFFER_FULL` / `TLS_ERR_BAD_RECORD` for a record longer than TLS allows — a protocol
violation reads as a socket failure, so a caller cannot tell "the network failed" (retry) from
"the peer broke the protocol" (report).

## Reproduction

`repros/2026-10-01-tls-native-no-deadline.sh` (+ `.cyr`): makes a P-256 CA and leaf with
`openssl`, forks a server per case, and runs a client with `SO_RCVTIMEO` = 2 s that is killed at
10 s. Case 1: a raw server reads the ClientHello, then sends a CCS record every 500 ms. Case 2: a
real `tls_accept` handshake, then CCS records every 500 ms on the raw socket after the request.

```
docs/development/issues/repros/2026-10-01-tls-native-no-deadline.sh; echo "exit=$?"
# -> exit=2 on 6.6.12: both clients still blocked after 10 s with a 2 s read timeout
```

The abaco review also measured a 1-byte-per-3-s drip inside one handshake record (blocked when
killed at 240 s) and a CCS flood at line rate (reads keep returning data until the socket is cut).

## Root cause

- (a) `_tn_sock_read_record_skip_ccs` (`tls_native_conn.cyr:561-571`) has no count and no state:
  it does not know whether the peer's Finished has arrived.
- (b) `_tn_sock_read_full` (`:529-540`) loops while `r > 0` with no clock; the ctx has no deadline
  field.
- (c) `tls_native_read` `:776` (`if (rl < 0) { return _tn_ctx_fail(ctx, TLS_ERR_IO); }`), and the
  same line at each handshake read site (`:497`, `:503`, `tls_native_hs13.cyr:339`, hs12 ×5).

## Proposed fix

1. Accept at most one CCS, and only before the peer's Finished (track it on the ctx); any other CCS
   → `_tn_ctx_fail(ctx, TLS_ERR_PROTOCOL)` and an `unexpected_message` alert (RFC 8446 §5). TLS 1.2
   has exactly one CCS per direction in the handshake (RFC 5246 §7.1).
2. A per-connection deadline: `tls_native_set_deadline(ctx, abs_ns)` (and a `tls_set_deadline` on
   the shim) that `_tn_sock_read_full` / `_tn_sock_write_all` honour by polling with the time left,
   failing with a distinct `TLS_ERR_TIMEOUT`.
3. Pass the record-read error through instead of collapsing it to `TLS_ERR_IO`.

## Consumer-side workaround

abaco 2.4.12 runs each HTTPS fetch under a per-fetch watchdog thread: at its deadline it
`shutdown(fd, SHUT_RD)`s the socket (which wakes the blocked read with end of stream) and `dup2`s
`/dev/null` over the descriptor (Linux still hands out data already queued after `SHUT_RD`, up to
the receive buffer). `SHUT_RD`, not `SHUT_RDWR`: a later write after `SHUT_WR` raises SIGPIPE.
