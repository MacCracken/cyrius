# Native TLS conformance, as one bite: six handshake checks that are missing, loose or untested — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b, every program built by the tree's
`build/cycc`: items 2 (the 1.2 half), 3, 4 and 5 reproduced live (repros below — each accepts what it must refuse,
with a well-formed control); item 6 by mutation (each of the four checks disabled alone, all 46 TLS `.tcyr` still
exit 0, while four neighbouring checks disabled the same way each turn a test red); items 1, 2 (the 1.3 half) and 3's
EncryptedExtensions half by reading the live code.
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** items 3-6 by the 6.6.15 TLS lane (2026-10-03, pre-existing); items 1-2 by the 6.6.16 planning premise
checks (2026-10-04); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — protocol conformance: malformed or out-of-contract peer messages are accepted (every one still
needs the handshake's signatures and Finished to verify), and four length / type guards could be deleted with no
test noticing.
**Affects:** the native TLS stack (`lib/tls_native_hs12.cyr`, `lib/tls_native_hs13.cyr`) through 6.7.6.

## Summary

1. **1.3 ECDSA schemes are not bound to the leaf's curve** (RFC 8446 §4.2.3: `ecdsa_secp256r1_sha256` is P-256 only,
   `ecdsa_secp384r1_sha384` P-384 only). `_tn_verify_sig_scheme` (`lib/tls_native_hs13.cyr:533-550`), the server
   CertificateVerify's verifier (`:742`), hands the leaf's key to the scheme's verifier whatever its curve; only the
   Ed25519 arm checks `x509_cert_curve` (`:541-548`). The server-side twin `_tn_verify_client_sig` binds both
   (`:2469-2473`). Not run: a mismatched key is read from sigil's 96-byte key slot (`x509_cert_pubkey`,
   `lib/sigil.cyr:18596`) at the other curve's width, which should not verify — so today this is a missing refusal
   (and the wrong error), not an accepted forgery.
2. **Trailing bytes after the signature are accepted** — the length checks use `>`:
   1.3 CertificateVerify `if (4 + sig_len > ml)` (`lib/tls_native_hs13.cyr:728`); 1.2 ServerKeyExchange
   `if (plen + 4 + sig_len > body_len)` (`lib/tls_native_hs12.cyr:697`). Reproduced for the 1.2 half: an SKE that
   verifies (control: `TLS_OK`) still returns `TLS_OK` with one extra byte inside its body.
3. **The 1.3 client accepts a ServerHello carrying an extension it never offered** (RFC 8446 §4.2:
   unsupported_extension). `tls_native_client_parse_server_hello` (`lib/tls_native_hs13.cyr:333`) looks up
   supported_versions (`:390`) and key_share (`:398`) and never walks the rest of the block. Reproduced: a real
   ServerHello with `{0x1234, len 0}` appended parses `TLS_OK`. The HelloRetryRequest path already refuses this
   (`tls_native_client_process_hrr`, via `_tn_client_offered_ext`, `:292`). EncryptedExtensions is the same shape:
   `tls_native_client_recv_flight` only searches it for ALPN and is "lenient on malformed exts" (`:625-637`). The walk
   must still admit `pre_shared_key` in a ServerHello once the client offers resumption (it offers none today; the
   offered-from-the-bytes-we-sent test, `_tn_client_offered_ext`, gives that for free).
4. **The 1.2 client does not check the server certificate's curve against its own supported_groups** (RFC 8422 §5.1;
   OpenSSL's client refuses it as "wrong curve", per the 6.6.15 note at `lib/tls_native_hs12.cyr:1329-1333`).
   `_tn_12_parse_server_kex` checks the ServerKeyExchange's GROUP against `_tn_groups(ctx)` (`:688`) but verifies with
   `_tn_ecdsa_verify_12`, which takes the key's curve as it comes (`lib/tls_native_hs13.cyr:2434-2448`). Reproduced: a
   client restricted to x25519 + secp256r1 accepts a P-384 leaf's ServerKeyExchange (`TLS_OK`).
5. **The 1.2 server takes a `legacy_session_id` longer than 32 bytes** (RFC 5246 §7.4.1.2: `SessionID<0..32>`;
   decode_error). `_tn_12_parse_client_hello` reads the length and skips it (`lib/tls_native_hs12.cyr:1345-1346`);
   the 1.3 parser refuses `sid_len > 32` (`_tn_parse_client_hello`, `lib/tls_native_hs13.cyr:1541`). Reproduced: a
   33-byte id negotiates a suite. Never stored or echoed — conformance only.
6. **Four 1.2-client ServerKeyExchange checks have no test that fails without them** (`lib/tls_native_hs12.cyr`;
   the roadmap's ~679 / 688 / 691 / 711 are the 6.6.15 numbering): `body_len < 4` (`:685`), `body_len < plen + 4`
   (`:694`), `plen + 4 + sig_len > body_len` (`:697`, also item 2) and `ok < 0 → TLS_ERR_KEY_UNSUPPORTED` (`:717`).

## Reproduction

```sh
# 3 and 5 — standalone; exit 1 = accepted (the bug), 0 = refused
for r in docs/development/issues/repros/2026-10-08-tls-native-conformance-1-sh-unoffered-ext.cyr \
         docs/development/issues/repros/2026-10-08-tls-native-conformance-2-12-server-sid33.cyr; do
  cat $r | build/cycc > $S/r && chmod +x $S/r && $S/r; echo "rc=$?"; done
```

Actual: `ACCEPTED: ServerHello with unoffered extension 0x1234 parsed TLS_OK` rc=1;
`ACCEPTED: 1.2 server negotiated a suite for a 33-byte legacy_session_id` rc=1. Controls: overstating the
ServerHello's extensions length by 4 is refused (the splice offsets are right); a 32-byte session id is accepted (the
re-emitted ClientHello is well formed).

2 (1.2) and 4 — added to a scratch copy of `tests/tcyr/crossos/tls12_client_ecdhe.tcyr` (its fixtures: `CERT384`,
`SIG_A` = OpenSSL's P-384 key signing SHA-256 over the secp256r1 params, `_client`, `_params`, `_ske_with_sig`) and
called from `_ecdhe_all()`:

```cyr
fn test_cert_curve_not_offered(): i64 {
    var pa = alloc(128);
    var pal = _params(TLS_GROUP_SECP256R1, _h(GR256), 65, pa);
    var ske = alloc(512);
    var sn = _ske_with_sig(pa, pal, TLS_SIG_ECDSA_SECP256R1_SHA256, SIG_A, ske);
    var c = _client(G_C384, _hn(CERT384));
    var gs: i64[2];
    store64(&gs, TLS_GROUP_X25519);
    store64(&gs + 8, TLS_GROUP_SECP256R1);
    assert_eq(tls_native_set_groups(c, &gs, 2), TLS_OK, "client offers x25519, secp256r1 only");
    assert_neq(_tn_12_parse_server_kex(c, ske, sn), TLS_OK, "a P-384 leaf's ServerKeyExchange is refused");
    store8(ske + sn, 0xEE);
    var c2 = _client(G_C384, _hn(CERT384));
    assert_eq(_tn_12_parse_server_kex(c2, ske, sn), TLS_OK, "control: the exact SKE verifies");
    var c3 = _client(G_C384, _hn(CERT384));
    assert_neq(_tn_12_parse_server_kex(c3, ske, sn + 1), TLS_OK, "one trailing byte is refused");
    return 0;
}
```

Actual: both `assert_neq` FAIL (the control passes) — `114 passed, 2 failed (116 total)`.

6 — on a `git archive` copy of `lib/` + `tests/`, each check rewritten to `if (0 == 1 && …)` alone, every
`tests/tcyr/**.tcyr` naming `tls_native` or `lib/tls.cyr` (46; the two `compiler/large_*` excluded) built with
`build/cycc` and run: 46 / 46 exit 0 for `:685`, `:694`, `:697`, `:717`. Controls, same method: `:686` (curve_type) →
`tls12_client_ecdhe` red; `:688` (group) → `tls_native_ecdhe_groups` red; `:692` (point length) →
`tls12_client_ecdhe` red; `:718` (`ok != 1`) → three red. Not run: `tests/gates/platform/tls_native_client_auth_openssl.sh`
(needs `openssl s_server`).

## Root cause

As itemised above — each is a check never written (1, 3, 4, 5), written loose (2), or written without its test (6).

## Proposed fix

One bite, each with a test that fails without it:
1. In the 1.3 caller (or `_tn_verify_sig_scheme` with an `is13` flag, as `_tn_verify_client_sig` has), refuse an
   ECDSA scheme whose curve is not the leaf's — `illegal_parameter` / `TLS_ERR_AUTHN` per the RFC's alert table.
2. `!=` for both lengths (decode_error).
3. Walk every ServerHello and EncryptedExtensions extension: one we did not offer → unsupported_extension; one we
   offered that the message may not carry → illegal_parameter (the HRR walk's rule).
4. In `_tn_12_parse_server_kex` (or at the 1.2 Certificate), refuse an ECDSA leaf whose curve the client's
   supported_groups does not list (Ed25519 is not bound by the list).
5. `if (sid_len > 32)` in `_tn_12_parse_client_hello`, as the 1.3 parser.
6. Tests in `tls12_client_ecdhe.tcyr` for the four SKE guards (a 3-byte body; params with no room for the scheme; a
   signature length past the body; an unknown scheme → `TLS_ERR_KEY_UNSUPPORTED`, not `TLS_ERR_AUTHN`).

## To verify with this bite (found 2026-10-08 while filing)

- `lib/tls_native_hs13.cyr:625-637`: EncryptedExtensions stores the server's ALPN through `_tn_store_alpn_selected`.
  Whether the selected protocol is checked against the list the client offered was not examined — check it here
  (RFC 8446 / RFC 7301: a protocol the client did not offer is a fatal `illegal_parameter`).
