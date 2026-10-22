# The native TLS 1.3 server checks each key_share against supported_groups by a linear scan — one 16 KB ClientHello costs ~24 ms of server CPU, quadratic in peer-chosen counts (CYRIUS-2026-0037) — OPEN

**Status:** 🟡 **OPEN** — recorded at the 6.7.16 close as CYRIUS-2026-0037 (P3, tracked); not fixed.
**Placement:** 6.7.17 — the cleanup of the remaining issues (plat lane, wave 1, unit PL1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Discovered:** 2026-10-20, by the 6.7.16 p16 lane (unit PP3, fixing
issues/archived/2026-10-19-tls-native-servers-clienthello-null-compression-repeated-ext-block-tail.md), reported in one line in
its handoff ("met, not swept; not fixed") and neither fixed nor filed; met again by the release-docs pass at the close.
**Severity:** Medium — a remote, unauthenticated CPU-amplification denial of service against a program serving TLS 1.3
with the native stack (`lib/tls_native_hs13.cyr`); bounded per hello by the 16 KB record.
**Kind:** security (CYRIUS-2026-0037, P3) — the ledger's test: the attacker is any network peer that can send a
ClientHello; the boundary is the network into the server's CPU.
**Affects:** cycc 6.7.x native TLS 1.3 server (every target the native stack builds on).

## Summary

The 1.3 server's key_share loop (`lib/tls_native_hs13.cyr`, the `while (kp < ksl)` loop near line 1840) refuses a share
for a group the client did not list (RFC 8446 § 4.2.8, illegal_parameter) by calling `_tn_sg_has(sg, sgl, kg)` for
EACH share — a linear scan of the whole supported_groups list. Both counts are the peer's: a ClientHello that fills its
16 KB record with many one-byte shares on groups listed at the END of a long supported_groups list makes the server do
shares × groups comparisons before the handshake is refused.

## Reproduction (the p16 lane's measurement, x86_64, 2026-10-20 — not re-run at the close)

One 16 KB ClientHello carrying a supported_groups extension of 4,025 groups and a key_share extension of 1,610 one-byte
shares on groups listed at the end of that list: the server spends ~24 ms of CPU, then refuses the handshake
(handshake_failure, no shared group). A peer repeating such hellos on fresh connections keeps a core busy at a small
fraction of the bandwidth the server spends answering.

## Root cause

`_tn_sg_has` (`lib/tls_native_hs13.cyr:1946`) re-validates the list framing and walks it from the start on every call,
and the key_share loop calls it once per share. The p16 lane made the extension walk's repeat check linear (an
earlier-entry scan there was quadratic: 0.1 – 0.3 s per hello for ~4,000 empty extensions); this loop kept the
per-share scan.

## Proposed fix

Validate supported_groups once per hello and answer membership in O(1): a 65,536-bit set (8 KB, per handshake — heap or
the handshake's arena, never a frame) filled by one pass over the list, or a sorted copy and a binary search. The
key_share loop then costs O(shares) and the RFC 8446 § 4.2.8 refusal is unchanged. A row: the hello above, timed, under a
bound that fails at the quadratic cost (the pattern of `simd_valueform_no_avx_transition.sh`'s re-measured timing rows),
plus the existing refusal rows for a share outside the list. Detail:
`docs/audit/2026-09-03-security-audit.md` § CYRIUS-2026-0037.
