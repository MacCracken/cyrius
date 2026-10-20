# Native TLS servers: a ClientHello without the null compression method, with a repeated extension type, or (1.3) with a partial entry at the end of its block still negotiates — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 platform lane (branch l6716-platform, after unit P4's D32
commit d9bc1c3af), x86_64 Linux, the lane's `build/cycc`.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — protocol conformance on the native servers' ClientHello parses (`_tn_12_parse_client_hello`,
lib/tls_native_hs12.cyr; `_tn_parse_client_hello`, lib/tls_native_hs13.cyr). Every handshake still has to pass the
server's signature and both Finished MACs over a transcript that holds these bytes; a peer could send the same choices
well formed, so no attacker crosses a boundary — no ledger id. Found in passing while implementing 6.7.16's D32
(issues/2026-10-18-tls-native-1-2-server-clienthello-other-leniencies.md), whose decided surface is a compression
list or extension list that does not PARSE (no byte, empty, overrunning; an extension overrunning the block). These
shapes parse; they are refused by the RFCs on other grounds, so they are outside D32 and not fixed there.
**Needs a decision:** yes, as D32 / 6.7.15's D40 did — refusing them changes what the servers accept from a peer, and
the alert is a choice (OpenSSL's server, from memory of its source — neither read nor measured here: decode_error for a 1.2 list
without null, illegal_parameter for a 1.3 list other than one null and for a repeated extension).

## Reproduction

The helpers of `tests/tcyr/crypto/tls12_ch_conformance.tcyr` (everything above its first `alloc_init();`), then:

```cyr
fn _pr(s): i64 { print(s, strlen(s)); return 0; }
# a 1.3 server's answer to the client's own 1.3 ClientHello after `k`'s change
fn _h13(k): i64 {
    var srv = _new_srv();
    var cl = tls_native_new_client("localhost", 9);
    var ch = alloc(1024);
    memset(ch, 0, 1024);
    var chn = tls_native_client_build_hello(cl, ch, 1024);
    var eo = _ext_off(ch + 4);
    if (k == 1) {   # a 2-byte tail inside the block
        _tn_be16_w(ch + 4 + eo, _tn_be16_r(ch + 4 + eo) + 2);
        chn = chn + 2;
    }
    if (k == 3) {   # the block's first extension repeated
        var bl = _tn_be16_r(ch + 4 + eo);
        var el = _tn_be16_r(ch + 4 + eo + 4);
        memcpy(ch + 4 + eo + 2 + bl, ch + 4 + eo + 2, 4 + el);
        _tn_be16_w(ch + 4 + eo, bl + 4 + el);
        chn = chn + 4 + el;
    }
    if (k == 2) {   # compression_methods = [1] (not exactly one zero byte)
        store8(ch + 4 + eo - 1, 1);
    }
    tls_native_handshake_write_header(ch, 1, chn - 4);
    var sh = alloc(1024);
    var r = tls_native_server_respond_hello(srv, ch, chn, sh, 1024);
    G_SRV = srv;
    return r;
}
alloc_init();
_ch12();
var eo = _ext_off(G_CH + 4);
store8(G_CH + 4 + eo - 1, 1);
_pr("A 1.2 compression_methods = [1], no null method: "); print_num(_parse(G_CHN - 4)); _pr(" alert="); print_num(_alert()); _pr("\n");
# B: the block's first extension repeated (the block and message grown by its size)
_ch12();
eo = _ext_off(G_CH + 4);
var et = _tn_be16_r(G_CH + 4 + eo + 2);
var el = _tn_be16_r(G_CH + 4 + eo + 4);
var bl = _tn_be16_r(G_CH + 4 + eo);
memcpy(G_CH + 4 + eo + 2 + bl, G_CH + 4 + eo + 2, 4 + el);
_tn_be16_w(G_CH + 4 + eo, bl + 4 + el);
_pr("B 1.2 the first extension (type "); print_num(et); _pr(") twice: "); print_num(_parse(G_CHN - 4 + 4 + el)); _pr(" alert="); print_num(_alert()); _pr("\n");
_pr("D 1.3 a 2-byte tail inside the block: "); print_num(_h13(1) > 0); _pr(" alert="); print_num(_alert()); _pr("\n");
_pr("E 1.3 compression_methods = [1]: "); print_num(_h13(2) > 0); _pr(" alert="); print_num(_alert()); _pr("\n");
_pr("G 1.3 the first extension twice: "); print_num(_h13(3) > 0); _pr(" alert="); print_num(_alert()); _pr("\n");
_pr("F 1.3 control: "); print_num(_h13(0) > 0); _pr(" alert="); print_num(_alert()); _pr("\n");
```

Output:

```
A 1.2 compression_methods = [1], no null method: 49196 alert=0
B 1.2 the first extension (type 0) twice: 49196 alert=0
D 1.3 a 2-byte tail inside the block: 1 alert=0
E 1.3 compression_methods = [1]: 1 alert=0
G 1.3 the first extension twice: 1 alert=0
F 1.3 control: 1 alert=0
```

(49196 = 0xC02C, a negotiated suite; `1` from `tls_native_server_respond_hello` > 0, a ServerHello written; type 0 is
server_name, the client's first extension.)

## Root cause

- **No null compression method (1.2, A).** RFC 5246 §7.4.1.2: compression_methods "MUST contain, and all
  implementations MUST support, CompressionMethod.null"; the server's ServerHello names null, a method the client did
  not offer. `_tn_12_parse_client_hello` checks the list's framing (D32) and never its contents.
- **compression_methods other than exactly one zero byte (1.3, E).** RFC 8446 §4.1.2: "If a TLS 1.3 ClientHello is
  received with any other value in this field, the server MUST abort the handshake with an illegal_parameter alert."
  `_tn_parse_client_hello` skips the list (`pos = pos + 1 + comp_len`) unread.
- **A repeated extension type (1.2 B, 1.3 G).** RFC 5246 §7.4.1.4 / RFC 8446 §4.2: "There MUST NOT be more than one
  extension of the same type." Both servers look extensions up with `_tn_find_ext`, which takes the first; the 1.3
  CLIENT refuses a repeat with illegal_parameter (`_tn_client_ext_walk` / `_tn_ext_seen_before`, 6.7.14).
- **A partial entry at the end of the 1.3 block (D).** `_tn_find_ext` loops `while (pos + 4 <= ext_len)`, so 1-3 bytes
  after the last whole extension are never read; the 1.3 server finds supported_groups and key_share before them and
  answers. The 1.2 server now walks its block once (D32's `_tn_12_ch_ext_frames`) and refuses this shape (its P7 row);
  the 1.3 server's block does not frame and is accepted.

## Fix direction

If refused: the 1.3 server walks its block once as the 1.2 server now does (decode_error for D) and both walks refuse a
repeated type (illegal_parameter, the client walk's alert); the 1.2 parse requires a 0 in compression_methods, the 1.3
parse exactly `01 00` — the alerts per the decision. Rows beside tls12_ch_conformance.tcyr's P rows and
tls13_ch_conformance.tcyr's T rows, a mutation per check; tls_native_client_auth_openssl.sh (OpenSSL s_client) must
stay green — real clients send none of these shapes.
