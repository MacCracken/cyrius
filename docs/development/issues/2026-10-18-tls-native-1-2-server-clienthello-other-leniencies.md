# Native TLS 1.2 server: a ClientHello with no or an overrunning compression_methods, or an extension that overruns its block, still negotiates; its short-message refusals send no alert — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform), on the tree that
already carries 6.7.15's D40 fix (the 1.2 server's extension block must fill the ClientHello).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 platform lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — protocol conformance on the native TLS 1.2 server's ClientHello parse
(`_tn_12_parse_client_hello`, lib/tls_native_hs12.cyr). Every handshake still has to pass the ServerKeyExchange
signature and both Finished messages; no attacker crosses a boundary (the peer could send the same choices well
formed), so no ledger id. Found in passing while implementing
issues/2026-10-17-tls-native-hello-bytes-after-extension-block-1-2-sh-and-server-ch.md, whose filed surface (and the
user's D40) is the extension block filling the message only.
**Needs a decision:** yes, as D40 did — refusing these changes what the 1.2 server accepts from a peer.

## Reproduction

The helpers of `tests/tcyr/crypto/tls12_ch_conformance.tcyr` (everything above its first `alloc_init();`: `_ch12`,
`_ext_off`, `_parse`, `_alert`, `G_SRV`), then:

```cyr
fn _pr(s): i64 { print(s, strlen(s)); return 0; }
fn _cs_end(body): i64 {
    var pos = 2 + 32;
    pos = pos + 1 + (load8(body + pos) & 0xFF);
    pos = pos + 2 + _tn_be16_r(body + pos);
    return pos;
}
alloc_init();
_ch12();
var ce = _cs_end(G_CH + 4);
_pr("P1 no compression_methods byte: "); print_num(_parse(ce)); _pr(" alert="); print_num(_alert()); _pr("\n");
_ch12();
store8(G_CH + 4 + ce, 5);
_pr("P2 compression_methods claiming 5, message ends after 1: "); print_num(_parse(ce + 2)); _pr(" alert="); print_num(_alert()); _pr("\n");
_ch12();
var eo = _ext_off(G_CH + 4);
# a block of one extension whose own length (0x00FF) overruns the 4-byte block
_tn_be16_w(G_CH + 4 + eo, 4);
_tn_be16_w(G_CH + 4 + eo + 2, 0x0017);
_tn_be16_w(G_CH + 4 + eo + 4, 0x00FF);
_pr("P3 an extension whose length overruns the block (block fills the message): "); print_num(_parse(eo + 6)); _pr(" alert="); print_num(_alert()); _pr(" ems="); print_num(load64(G_SRV + TLS_CTX_OFF_USE_EMS)); _pr("\n");
_ch12();
_tn_be16_w(G_CH + 4 + 35 + (load8(G_CH + 4 + 34) & 0xFF), 0x7FFF);
_pr("P4 cipher_suites length overrunning the message: "); print_num(_parse(G_CHN - 4)); _pr(" alert="); print_num(_alert()); _pr("\n");
_pr("P5 a body shorter than random + session id length: "); _ch12(); print_num(_parse(20)); _pr(" alert="); print_num(_alert()); _pr("\n");
```

Output (built from the repo root with the lane's `build/cycc`):

```
P1 no compression_methods byte: 49196 alert=0
P2 compression_methods claiming 5, message ends after 1: 49196 alert=0
P3 an extension whose length overruns the block (block fills the message): 49196 alert=0 ems=0
P4 cipher_suites length overrunning the message: -4 alert=0
P5 a body shorter than random + session id length: -4 alert=0
```

(49196 = 0xC02C, a negotiated suite: accepted.) The 1.3 server's parse (`_tn_parse_client_hello`,
lib/tls_native_hs13.cyr) refuses each of these shapes with decode_error and records it.

## Root cause

`_tn_12_parse_client_hello` keeps the lenient reads the D40 fix did not cover:

- `if (pos + 1 <= blen) { … }` — a ClientHello ending after its cipher suites (no compression_methods at all) skips
  the rest and negotiates; `pos = pos + 1 + cm_len` past `blen` (a compression list overrunning the message) leaves
  `pos >= blen`, read as "no extension block" (P1, P2).
- The extension lookups (`_tn_find_ext` for extended_master_secret and supported_groups, and
  `_tn_server_negotiate_alpn`) treat a malformed list (-1: an extension overrunning the block) as "not present", so
  the block is half-read: no EMS, the server's first group, no ALPN (P3). The 1.3 server refuses `fsg < 0` /
  `fks < 0` with decode_error; the 1.2 client walks its block (`_tn_client_ext_walk`).
- The early refusals (`blen < 2 + 32 + 1`, `pos + 2 > blen` before cipher_suites, `pos + cs_len > blen`) return a
  bare `TLS_ERR_BAD_HANDSHAKE` with no alert recorded, so `_tn_12_server_hs` / `tls_native_accept_12` send none
  (`_tn_send_hs_alert` sends only a recorded one) (P4, P5).

## Fix direction

If refused: `_tn_hs_fail(ctx, TLS_AD_DECODE_ERROR, TLS_ERR_BAD_HANDSHAKE)` at each — a missing or overrunning
compression_methods, a `_tn_find_ext` -1 on any lookup (or one walk of the block first), and the three early
returns — with rows beside tls12_ch_conformance.tcyr's S rows and a mutation per check. A well-formed ClientHello is
unaffected; real clients (OpenSSL s_client -tls1_2, tls_native_client_auth_openssl.sh) send none of these shapes.
