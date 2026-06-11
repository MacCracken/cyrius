# Native TLS: post-handshake records collapse to false EOF — CVE-30

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High
**Affects:** `lib/tls_native.cyr` 6.1.31 — the **default** backend since v6.1.21.

## Summary

`tls_native_open_app` returns `0` for any decrypted record whose inner type is
handshake (22) — the fall-through `return 0;` at `tls_native.cyr:2091` (comment
at `:2053-2055`: *"0 for a post-handshake handshake record (NewSessionTicket /
KeyUpdate — full handling later)"*). `tls_native_read` passes that 0 straight up
(`:5277`) and its own contract (`:5264-5265`) defines `0` as "peer-initiated
close_notify"/EOF. The 1.3 client connect (`:5089-5100`) stops right after the
client Finished and never drains the NewSessionTicket that standard TLS 1.3
servers (OpenSSL, nginx) send post-handshake.

Net effects on the default stack:
- First read of a server's **NewSessionTicket** → false EOF / truncated app
  stream (a truncation-class robustness + security bug).
- A peer **KeyUpdate** is silently dropped (`tls_native_key_update_secret` has
  no production caller — only `scaffold.tcyr:1523`), so receive keys never
  advance → all subsequent records fail to decrypt.

The repo already knows the shape — `realpeer.tcyr:53` loops "past
NewSessionTicket records (return 0)" — but it's untracked in roadmap/issues.

## Reproduction

Connect the native client to any stock OpenSSL/nginx TLS 1.3 server that emits
an NST immediately after the handshake, then `tls_native_read`. The first read
returns 0 (interpreted as EOF) before any application data; a server that sends
a KeyUpdate mid-stream desyncs all later reads.

## Root cause

`open_app` does no socket IO, so the drain loop belongs one layer up in
`tls_native_read`; `open_app` needs an out-`ct` param so the caller can tell a
real `close_notify` from an NST/KeyUpdate.

## Proposed fix

In `tls_native_read`, loop-drain post-handshake records: store/ignore
NewSessionTicket; on KeyUpdate re-derive the app secret via
`tls_native_key_update_secret`, reset the sequence number, and answer
`update_requested`. Reserve `0 == EOF` **strictly** for a real `close_notify`.
Add a tcyr that handshakes against a real NST-sending peer and asserts the first
app read returns data, not EOF.

## Status

Filed 2026-06-10. Distinct from the v6.1.31 Ed25519 cert fix (archived). v7-public
prerequisite; track alongside [tls-chain-verification-gaps](2026-06-10-tls-chain-verification-gaps.md).
