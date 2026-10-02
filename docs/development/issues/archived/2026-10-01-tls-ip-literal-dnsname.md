# Native TLS client: an IP-literal host matches dNSName SAN entries, wildcards included

**Status:** ✅ **RESOLVED v6.6.13** (bite I7, CVE-63) — an IP-literal host is compared with iPAddress SANs only, and `_tn_parse_ipv4` refuses leading zeros. See CHANGELOG [6.6.13].
**Placement:** **6.6.13**, bite I7 (placed by the user 2026-10-01) — see `roadmap.md` § 6.6.13.
**Discovered:** 2026-10-01, abaco 2.4.12 review (a certificate whose only SAN was
`DNS:127.0.0.1`, or `DNS:*.0.0.1`, was accepted for `https://127.0.0.1`).
**Severity:** Low — exploiting it needs a CA the client trusts to issue such a dNSName, which the
CA/Browser Forum Baseline Requirements forbid public CAs to do; but the documented rule (CVE-18,
"dNSName or iPAddress SAN") is RFC 9525's, and this is not it.
**Affects:** cyrius 6.6.12 `lib/tls_native_conn.cyr` `_tn_cert_san_match` (:214), and the
inconsistency below between `_tn_parse_ipv4` (:89) and `lib/net.cyr`'s `net_parse_ipv4` (:1114).

## Summary

`_tn_cert_san_match` runs `_tn_host_match` on every dNSName (tag `0x82`) whatever the host is, and
the iPAddress comparison (tag `0x87`) in addition. So for an IP-literal host:

- a dNSName that spells the address (`DNS:127.0.0.1`) matches, and
- a wildcard dNSName over it (`DNS:*.0.0.1`) matches too.

RFC 9525 §6.3 (RFC 6125 §6.2.1 before it): an IP-address reference identity (IP-ID) matches the
octets of an iPAddress subjectAltName, compared octet for octet; DNS-ID matching, and the wildcard
rules with it, apply to DNS domain names only, so an IP literal never matches a dNSName.

Related inconsistency: `_tn_parse_ipv4` accepts leading zeros (`010.0.0.1` → 10.0.0.1), while
`net_parse_ipv4` — the resolver's literal rule — refuses them and sends the name to DNS. The
verifier can therefore treat as an address a host the resolver treated as a name.

## Reproduction

`repros/2026-10-01-tls-ip-literal-dnsname.sh` (+ `.cyr`): makes a P-256 CA and three leaves with
`openssl` (SAN `DNS:127.0.0.1`; `DNS:*.0.0.1`; `IP:127.0.0.1` as the control), serves each with
`openssl s_server`, and connects to host `127.0.0.1` through `tls_connect_with_ctx_hook` trusting
only that CA.

```
docs/development/issues/repros/2026-10-01-tls-ip-literal-dnsname.sh; echo "exit=$?"
# -> exit=2 on 6.6.12: both dNSName leaves accepted for 127.0.0.1 (the IP leaf, correctly, too)
```

## Root cause

`tls_native_conn.cyr:273-275`:

```
if (ntag == 0x82) {
    if (_tn_host_match(der + ncp, ncl, host, host_len) == 1) { return 1; }
}
```

runs before, and independently of, the `_tn_parse_ip_literal` test at :280.

## Proposed fix

Parse the host once at the top of `_tn_cert_san_match`; when `_tn_parse_ip_literal(host)` > 0,
skip every `0x82` entry and compare `0x87` entries only. Make `_tn_parse_ipv4` refuse a leading
zero, as `net_parse_ipv4` does (or share one parser).

## Consumer-side workaround

abaco 2.4.12: for an IPv4-literal host (`net_parse_ipv4` != -1), after the handshake it reads the
verified leaf (`tls_native_get_peer_cert_der`) and requires an iPAddress entry of exactly those
4 bytes in the first subjectAltName extension (`_ccy_cert_ip_san`, a bounded DER walk), refusing
the fetch otherwise.
