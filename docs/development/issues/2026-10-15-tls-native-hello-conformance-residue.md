# Native TLS hello conformance, the residue past the 6.7.12 bite: duplicate extensions, bytes after an extension block, a malformed or multi-protocol ALPN answer, and a 1.2 client ServerHello that walks nothing — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on branch l6712-stdlib with the 6.7.12 conformance bite applied (every
probe below built by the tree's `build/cycc` and run; each line is TLS_OK = 0, i.e. accepted).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-15, while fixing issues/archived/2026-10-08-tls-native-conformance-bite.md (6.7.12 stdlib L4). That
filing's surface was the 1.3 ServerHello / EncryptedExtensions extension walk (unoffered → unsupported_extension,
offered-but-forbidden → illegal_parameter), the EE ALPN membership check, the 1.3 CertificateVerify curve and length,
the 1.2 SKE length and leaf curve, and the 1.2 server's session-id cap. These shapes sit beside it and were not in it.
**Severity:** Low–Medium — protocol conformance: out-of-contract peer messages accepted. Every one still needs the
handshake's signatures and Finished to verify; none is a forgery. No ledger id (no attacker crosses a boundary: a
peer that sends these could equally send well-formed messages carrying the same choices).
**Affects:** `lib/tls_native_hs13.cyr` (`tls_native_client_parse_server_hello`, `tls_native_client_recv_flight`,
`_tn_client_ext_walk`), `lib/tls_native_hs12.cyr` (`tls_native_client_parse_server_hello_12`,
`_tn_store_alpn_selected`).

## Summary

1. **Duplicate extensions pass** (RFC 8446 §4.2: "There MUST NOT be more than one extension of the same type in a
   given extension block"). `_tn_client_ext_walk` checks each type against the offer and the message's table but not
   against the types already seen; `_tn_find_ext` then takes the first. A 1.3 ServerHello with supported_versions
   twice, and an EncryptedExtensions with supported_groups twice, are accepted. (The HelloRetryRequest walk refuses a
   repeated known type; the ClientHello side is the server's own parser.)
2. **Bytes after an extension block pass.** The 1.3 ServerHello checks `pos + ext_total > blen` and EncryptedExtensions
   `ee_ext_total + 2 > ml`, so a block shorter than the rest of the message leaves trailing bytes no structure
   names (RFC 8446 §4: decode_error). Measured: two bytes after a ServerHello's block, one after an EE's block.
3. **The server's ALPN answer is read leniently** (RFC 7301 §3.1: the server's extension "MUST be restricted to a
   single protocol name"). `_tn_store_alpn_selected` stores the first name of a list of two and ignores a malformed
   body (no protocol selected, no error); the 6.7.12 membership check (`_tn_alpn_offered`) follows the same parse.
   Measured on the 1.3 EE: a body naming two protocols selects the first (TLS_OK); a body whose name runs past the list
   selects nothing (TLS_OK).
4. **The 1.2 client's ServerHello walks nothing.** `tls_native_client_parse_server_hello_12` looks up
   supported_versions, renegotiation_info, extended_master_secret and ALPN, and accepts the rest: an unsolicited
   `0x1234` (RFC 5246 §7.4.1.4: "the client MUST abort the handshake" with unsupported_extension), an ALPN answer when
   the client offered none (selected: h2), an ALPN protocol the client did not offer (selected: spdy/3, RFC 7301 §3.2
   illegal_parameter), and a 33-byte legacy_session_id (RFC 5246 SessionID<0..32>) all parse TLS_OK. The 1.2 client
   records no alert for any ServerHello refusal (its parse returns `_tn_ctx_fail` codes only).

## Reproduction

The probes are copies of the 6.7.12 rows' harnesses (tests/tcyr/crypto/tls13_ee_cv_conformance.tcyr's `_row` / `_ee`
and tests/tcyr/crypto/tls13_sh_unoffered_ext.tcyr's ServerHello splice) with these mains, built from the repo root:

```cyr
# (EE / 1.2 probe — appended to tls13_ee_cv_conformance.tcyr's helpers, its main replaced)
fn _sh12(sid, exts_hex, alpn): i64 {     # a hand-built 1.2 ServerHello, suite 0xC02C
    var cl = tls_native_new_client("localhost", 9);
    if (alpn == 1) { tls_native_set_alpn(cl, ALPN_OFFER, 12); }
    var ch = alloc(1024);
    tls_native_12_build_client_hello(cl, ch, 1024);
    var el = _hn(exts_hex);
    var m = alloc(512);
    var b = m + 4;
    _tn_be16_w(b, 0x0303);
    memset(b + 2, 0x11, 32);
    store8(b + 34, sid);
    memset(b + 35, 0x22, sid);
    var p = 35 + sid;
    _tn_be16_w(b + p, 0xC02C);
    store8(b + p + 2, 0);
    _tn_be16_w(b + p + 3, el);
    if (el > 0) { memcpy(b + p + 5, _h(exts_hex), el); }
    var blen = p + 5 + el;
    tls_native_handshake_write_header(m, 2, blen);
    G_CL = cl;
    return tls_native_client_parse_server_hello_12(cl, m, 4 + blen);
}
#   _row(ee, _ee("000a00040002001d000a00040002001d", ee), 0, 0)   EE supported_groups twice
#   _row(ee, _ee_raw("0000ff", ee), 0, 0)                           EE, one byte after the block
#   G_ALPN = 1; _row(ee, _ee("0010000700050268320268", ee), 0, 0)  EE ALPN naming two protocols
#   G_ALPN = 1; _row(ee, _ee("00100004000268ff", ee), 0, 0)         EE ALPN, malformed body
#   _sh12(0, "12340000", 0)                                         1.2 SH, unsolicited 0x1234
#   _sh12(0, "001000050003026832", 0)                               1.2 SH, ALPN h2, none offered
#   _sh12(0, "00100009000706737064792f33", 1)                       1.2 SH, ALPN spdy/3, h2 + http/1.1 offered
#   _sh12(33, "", 0)                                                1.2 SH, a 33-byte session id
```

Output:

```
EE duplicate supported_groups:
0
EE one byte after the extension block:
0
EE ALPN body naming two protocols (h2, h?):
0 selected=
2
EE ALPN body malformed (list says 2, proto len 0x68):
0 selected=
0
1.2 SH unsolicited 0x1234:
0
1.2 SH ALPN h2, none offered:
0 selected=
2
1.2 SH ALPN spdy/3, h2+http/1.1 offered:
0 selected=
6
1.2 SH 33-byte session id:
0
```

And the 1.3 ServerHello (the server's own ServerHello, spliced as the 6.7.12 SH rows do): two bytes appended after
the extension block (the handshake length grown, the extension total not) → `0`; supported_versions repeated inside
the block → `0`.

## Root cause

Checks never written: no seen-type set in either walk, `>` where the block must fill the message, a first-name-wins
ALPN parse that ignores what it cannot read, and no extension walk (or session-id cap) in the 1.2 client's ServerHello
parse. The 6.7.12 walk (`_tn_client_ext_walk` with `_tn_client_offered_ext` reading the bytes we sent) is the shape the
1.2 side can reuse against `tls_native_12_build_client_hello`'s block.

## Proposed fix

1. A seen-type check in `_tn_client_ext_walk` (and the 1.2 walk): a repeated type is refused (RFC 8446 §4.2 names
   no alert for it; the HelloRetryRequest walk's illegal_parameter is the house precedent).
2. `!=` for the 1.3 ServerHello and EncryptedExtensions blocks (decode_error).
3. The server's ALPN extension must be exactly one well-formed name filling the extension (decode_error otherwise).
4. The 1.2 client ServerHello walks its block against the 1.2 ClientHello it sent (unsupported_extension), checks the
   ALPN answer against the offer (illegal_parameter) and caps the session id at 32 (decode_error), recording the alerts
   for `tls_native_connect_12` to send.
Rows for each in tests/tcyr/crypto/ beside the 6.7.12 conformance files, with a mutation per check.
