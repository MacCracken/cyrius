# Cyrius: `lib/ws_server.cyr` accepts malformed `Sec-WebSocket-Key` lengths

**Filed:** 2026-05-10
**Reporter:** bote (MCP core service, v2.7.1)
**Cyrius version at time of report:** 5.10.34 (release tarball + source archive)
**Affected stdlib:** `lib/ws_server.cyr`
**Severity:** **Low** — RFC 6455 conformance gap; not exploitable for
remote code execution or info disclosure, but lets a malformed client
through the handshake when a conformant server would 400. bote tracks
this as **audit M4** (medium-conformance, low-exploitability) from
the 1.9.5 security audit.
**Status:** open. **Expected target:** **5.11.x arc**.

## Summary

RFC 6455 §4.1 requires the `Sec-WebSocket-Key` request header value to
be **exactly** a 16-byte value, base64-encoded — i.e. a 24-character
base64 string (16 bytes × 4/3, no padding question because 16 % 3 == 1
implies `==` padding → 24 chars). `lib/ws_server.cyr::ws_server_handshake`
in cyrius 5.10.34 accepts any non-empty `Sec-WebSocket-Key` value as
long as the `Upgrade: websocket` + `Connection: Upgrade` + version 13
checks pass, then base64-decodes whatever it got into the SHA-1 input
for the accept-key derivation.

The accept-key the server returns is still well-formed (it's
SHA-1(client-key || GUID) base64-encoded, and SHA-1 is fine with
any input length), so the handshake "succeeds" from both sides. But
a conformant server should reject:

| Bad input | RFC says | cyrius 5.10.34 stdlib says |
|---|---|---|
| `Sec-WebSocket-Key: ` (empty) | 400 | accepts (computes SHA-1 of empty || GUID) |
| `Sec-WebSocket-Key: short` (5 chars) | 400 | accepts |
| `Sec-WebSocket-Key: <17-byte base64>` | 400 | accepts |
| `Sec-WebSocket-Key: <not valid base64>` | 400 | accepts (base64 decode is lenient) |

## Reproduction

Minimal — assumes you have a bote build with the ws transport wired:

```sh
# Start bote ws transport
./build/bote ws 8393 &

# Send a handshake with a 1-char key (RFC says: 400)
printf 'GET /mcp HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: x\r\nSec-WebSocket-Version: 13\r\n\r\n' | nc localhost 8393 | head -1
# Actual:   HTTP/1.1 101 Switching Protocols
# Expected: HTTP/1.1 400 Bad Request
```

Repro applies to **any** consumer of `lib/ws_server.cyr` — not
bote-specific. bote is just the consumer that ran an explicit
RFC-6455 audit pass.

## Root cause (speculation — flag for verification)

`lib/ws_server.cyr::ws_server_handshake` probably has a "find header,
copy value, run SHA-1" sequence with no length check on the copied
value. The fix is a single conditional before the SHA-1 step:

```cyrius
# In ws_server_handshake, after extracting the key value:
if (key_len != 24) {
    sandhi_server_send_status(cfd, 400, "Bad Request");
    return 0 - 1;
}
# Optional belt-and-suspenders: validate base64 alphabet on each char.
```

A stricter check would also validate that the 16 decoded bytes don't
violate any "must be cryptographically random per request" property
the RFC suggests (§4.1), but bote considers that out of scope — RFC
itself says "It is not necessary for the server to base any decision
on this value" beyond the accept-key derivation.

## Proposed fix

Two changes in `lib/ws_server.cyr`:

1. Reject `Sec-WebSocket-Key` values where `key_len != 24` with HTTP
   400 before SHA-1 derivation.
2. Optional: reject if any of the 24 chars is outside the base64
   alphabet `[A-Za-z0-9+/=]`. Belt-and-suspenders against decoder
   quirks; not strictly RFC-required but cheap.

## Consumer-side workaround

bote could intercept the WS handshake in `src/transport_ws.cyr` and
run its own validation before calling into `ws_server_handshake`.
~15 lines of pre-handshake parsing (find header, check length, 400 if
wrong). bote has not shipped this because:

- The stdlib `ws_server_handshake` is supposed to be the single source
  of truth for WS protocol conformance. Doing parallel validation in
  every consumer means each consumer has to track future RFC
  amendments (e.g. permessage-deflate handshake extensions) in
  parallel with cyrius.
- The audit M4 rating is "low exploitability" — the consequence of
  accepting a malformed key is that a buggy client thinks it
  succeeded; there's no security boundary crossed, no info leaked.
  bote chose the cleaner upstream fix.

## Severity rationale

**Low** because:

- No security boundary is crossed. The malformed-key path doesn't
  authenticate the client (WS handshake doesn't authenticate
  *anything* — that's the application layer's job, which bote handles
  via bearer-token middleware in 1.9.0+).
- No info disclosure — the accept-key derivation is deterministic
  from inputs both sides have.
- The conformance gap is **server-permissive** (we accept more than
  the spec allows), not **server-restrictive** (we reject conformant
  clients). Permissive bugs in handshake code rarely escalate.

Bumps to **Medium** if:

- A future MCP spec amendment requires servers to validate WS
  handshake conformance (current MCP 2025-11-25 doesn't).
- A second WS conformance gap shows up in `lib/ws_server.cyr` and the
  combination starts breaking interop with strict clients.

## Pointers

- bote roadmap: https://github.com/MacCracken/bote/blob/main/docs/development/roadmap.md
- RFC 6455 §4.1 — handshake requirements.
- bote `docs/spec-compliance.md` — the M4 audit entry.
