# Native TLS: bytes after the extension block still pass in the 1.2 client's ServerHello and the servers' ClientHello parses — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on branch l6714-stdlib (unit L4, after the hello-conformance-residue
fix, which made the 1.3 ServerHello and the EncryptedExtensions blocks fill their message).
**Placement:** 6.7.15 — repair 5 (stdlib lane; filed from the 6.7.14 stdlib lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — protocol conformance: a peer message with trailing bytes no structure names is accepted (RFC 8446 §4 /
RFC 5246 §7.4.1: decode_error). Every message still has to pass the handshake's signatures and Finished; no forgery,
no ledger id (no attacker crosses a boundary: the peer could send the same choices well formed).
**Discovered:** 2026-10-17, implementing issues/2026-10-15-tls-native-hello-conformance-residue.md (6.7.14 stdlib L4),
whose filed surface was the 1.3 ServerHello and EncryptedExtensions blocks only (its triage noted the server-side
ClientHello in passing as "outside this filing").

## Reproduction

The helpers of `tests/tcyr/crypto/tls12_sh_conformance.tcyr` (everything above its first `alloc_init();`), then:

```cyr
fn _pr(s): i64 { print(s, strlen(s)); return 0; }
fn _sh12_trail(n): i64 {          # a 1.2 ServerHello whose handshake length runs n bytes past its block
    var cl = tls_native_new_client("localhost", 9);
    var ch = alloc(1024);
    tls_native_12_build_client_hello(cl, ch, 1024);
    var m = alloc(512);
    var b = m + 4;
    _tn_be16_w(b, 0x0303);
    memset(b + 2, 0x11, 32);
    store8(b + 34, 0);
    _tn_be16_w(b + 35, 0xC02C);
    store8(b + 37, 0);
    _tn_be16_w(b + 38, 5);
    memcpy(b + 40, _h("ff01000100"), 5);
    memset(b + 45, 0, n);
    tls_native_handshake_write_header(m, 2, 45 + n);
    G_CL = cl;
    return tls_native_client_parse_server_hello_12(cl, m, 4 + 45 + n);
}
fn _ch13_trail(n): i64 {          # a client's own 1.3 ClientHello with n bytes after its block
    var srv = tls_native_new_server(_h(CERT23), _hn(CERT23), _h(KEY23), _hn(KEY23));
    tls_native_server_load_creds(srv);
    var cl = tls_native_new_client("localhost", 9);
    var ch = alloc(1024);
    var chn = tls_native_client_build_hello(cl, ch, 1024);
    memset(ch + chn, 0, n);
    tls_native_handshake_write_header(ch, 1, chn - 4 + n);
    var sh = alloc(1024);
    var r = tls_native_server_respond_hello(srv, ch, chn + n, sh, 1024);
    G_CL = srv;
    return r;
}
alloc_init();
_pr("1.2 client, ServerHello, 0 bytes after the block: "); print_num(_sh12_trail(0)); _pr("\n");
_pr("1.2 client, ServerHello, 2 bytes after the block: "); print_num(_sh12_trail(2)); _pr(" alert="); print_num(_alert()); _pr("\n");
_pr("1.3 server, ClientHello, 0 bytes after the block: "); print_num(_ch13_trail(0)); _pr("\n");
_pr("1.3 server, ClientHello, 2 bytes after the block: "); print_num(_ch13_trail(2)); _pr(" alert="); print_num(_alert()); _pr("\n");
```

Output (built from the repo root with the lane's `build/cycc`):

```
1.2 client, ServerHello, 0 bytes after the block: 0
1.2 client, ServerHello, 2 bytes after the block: 0 alert=0
1.3 server, ClientHello, 0 bytes after the block: 90
1.3 server, ClientHello, 2 bytes after the block: 90 alert=0
```

(the 1.3 server's 90 is the ServerHello length it wrote: accepted).

## Root cause

The same `>` the residue fix replaced in the 1.3 client, in three more parsers: `tls_native_client_parse_server_hello_12`
(lib/tls_native_hs12.cyr, `if (pos + ext_total > blen)` in its extension arm), the 1.3 server's ClientHello parse
(lib/tls_native_hs13.cyr, `if (pos + ext_total > body_len)` before its extension walk) and the 1.2 server's
`_tn_12_parse_client_hello` (lib/tls_native_hs12.cyr, `if (pos + ext_total <= blen)`, documented "lenient").

## Fix direction

`!=` in each (decode_error, through `_tn_hs_refuse` / `_tn_hs_fail` as each parser records its alerts), with a row per
parser beside tests/tcyr/crypto/tls12_sh_conformance.tcyr and tls13_sh_unoffered_ext.tcyr and a mutation per check.
The 1.2 server's ClientHello parse is documented lenient on purpose (an EMS / ALPN lookup that never fails the
handshake); making it refuse is a behaviour change for that server, not only a conformance check.
