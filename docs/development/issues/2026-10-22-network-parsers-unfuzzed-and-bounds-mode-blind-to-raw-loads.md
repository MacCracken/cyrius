# The network parsers are unfuzzed, and bounds mode cannot see how they read — OPEN

**Status:** 🟡 **OPEN** — filed at the user's request (2026-10-22), after PHP2Shell (CVE-2026-109618 / 109619: memory
corruption in PHP's C core, reachable unauthenticated from the network). No defect is known; this is the coverage the
6.7.18 security audit owes the parsers a peer feeds.
**Placement:** 6.7.18 — the full security audit (the user, 2026-10-22: "put fuzz harnesses for the network parsers
(HTTP, WebSocket, DNS, X.509/DER, JSON) and bounds-checked builds of the network libs into 6.7.18's security audit
scope") — never 7.x.
**Discovered:** 2026-10-22, measuring the security posture after the 6.7.17 close.
**Severity:** Medium — a coverage gap on attacker-fed parsing in a memory-unsafe language, not a known defect. A
crash or over-read a fuzzer finds there gets a ledger id only if it meets CLAUDE.md's rule (attacker + boundary named).
**Affects:** cyrius 6.7.17 — `fuzz/`, `lib/async.cyr`, `lib/http.cyr`, `lib/ws.cyr`, `lib/ws_server.cyr`, and the
folds `lib/sandhi.cyr` (sandhi 1.13.6), `lib/sigil.cyr` (sigil 3.13.13), `lib/bayan.cyr` (bayan 1.11.0).

## Summary

1. **One network parser is fuzzed.** `fuzz/` holds 6 harnesses; `tls_client_hello.fcyr` (VR-02, 6.3.22 — the TLS 1.3
   server's `_tn_parse_client_hello`) is the only one fed attacker-shaped bytes. The other five exercise `vec`,
   `hashmap`, `freelist` and strings. They run in CI only (`.github/workflows/ci.yml`: `./build/cyrius fuzz`) — neither
   check.sh nor `release-gate.sh` runs a `.fcyr`, so a harness that starts crashing is first seen after a push. All six
   pass today.
2. **These parsers read peer-chosen bytes and have no harness:**

   | Family | Entry points (6.7.17) | File |
   |---|---|---|
   | DNS answers | `_async_dns_parse_a`, `_async_dns_skip_name` | `lib/async.cyr` |
   | DNS answers (sandhi's resolver) | `_sandhi_resolve_parse_response_a`, `_sandhi_resolve_parse_response_aaaa_a` | `lib/sandhi.cyr` (fold) |
   | HTTP/1 response | `_http_parse_response_a` | `lib/http.cyr` |
   | HTTP headers, HTTP/2 HPACK | `sandhi_headers_parse_a`, `_hpack_int_decode`, `_hpack_string_decode_a`, `sandhi_hpack_huffman_decode_a`, `sandhi_hpack_decode_field_a` | `lib/sandhi.cyr` (fold) |
   | WebSocket | `ws_recv_frame` (client), `ws_server_recv_frame`, `ws_server_handshake` | `lib/ws.cyr`, `lib/ws_server.cyr` |
   | X.509 / DER | `x509_parse_into`, `_x509_parse_time`, `_cp_der_tlv` | `lib/sigil.cyr` (fold) |
   | JSON | `bayan_json_parse_a`, `bayan_json_v_parse_ctx_a` | `lib/bayan.cyr` (fold) |

3. **Bounds mode checks subscripts; these parsers read through raw loads.** `#bounds` / `--bounds` / `CYRIUS_BOUNDS=1`
   (guide § *The bounds-checked mode*, 6.7.8) checks `a[i]`, `s[i]` and `p[i]`. Measured over twelve of the entry fns
   (`_async_dns_parse_a`, `_async_dns_skip_name`, `_http_parse_response_a`, `ws_recv_frame`, `ws_server_recv_frame`,
   `ws_server_handshake`, `sandhi_headers_parse_a`, `_hpack_int_decode`, `_sandhi_resolve_parse_response_a`,
   `x509_parse_into`, `_cp_der_tlv`, `bayan_json_parse_a` — the reads in each fn's own body; the helpers they call,
   where `x509_parse_into` does most of its reading, not counted): **87** buffer reads are `load8/16/32/64(base + off)`
   and **7** are subscripts. A bounds-checked build of these libs as written therefore checks about 7 % of the reads
   counted. The tool that does see raw loads is `cyrius fuzz --poison` (6.6.18, guide § *Fuzzing with `--poison`*):
   the stdlib allocators poison and redzone their blocks, an OVERWRITE traps (exit 86), an over-read yields the fill
   instead of live heap, and `--poison=ab` runs each harness at two fills and fails when the outputs diverge — the
   over-read class (the filed gap behind it: a delta interpreter that leaked 127 heap bytes past 10 M plain fuzz
   rounds). It covers
   allocator-backed buffers, not a static or stack `var b[N]`, and an over-read that changes nothing a harness prints
   stays silent. With no harness on these parsers, none of it runs on them.

## Reproduction

```sh
find fuzz -name '*.fcyr' | wc -l                                          # 6 — one network parser
grep -rln '\.fcyr\|cyrius fuzz' scripts/release-gate.sh scripts/check.sh  # nothing: CI runs them, the gates do not
cat > /tmp/bnd.cyr <<'EOF'
#bounds
include "lib/alloc.cyr"
var a: u8[8];
fn rd(off): i64 { return load8(&a + off); }
fn sub(off): i64 { return a[off]; }
fn main(): i64 { alloc_init(); var x = rd(100); syscall(1, 2, "raw read past: no report\n", 25); return sub(100); }
syscall(60, main());
EOF
build/cycc < /tmp/bnd.cyr > /tmp/bnd && chmod +x /tmp/bnd && /tmp/bnd; echo "exit=$?"
# 6.7.17:
# raw read past: no report                       <- load8(&a + 100): unchecked
# bounds: index 100 out of [0, 8) at <source>:5   <- a[100]: caught
# exit=134
```

## What 6.7.18 does (acceptance)

1. **A harness per family** in `fuzz/` — DNS (both resolvers), HTTP/1 response + sandhi headers + HPACK, WebSocket
   (client frames, server frames, the server handshake), X.509 / DER, JSON — each built as `tls_client_hello.fcyr` is:
   a valid seed input, deterministic seeded mutation (truncations, length fields at 0 / the buffer's end / past it /
   2^31 / 2^63, nesting depth, repeated and out-of-order elements), a fresh parser state per iteration; a graceful
   error return passes, a fault fails, the failing seed printed so it reproduces.
2. **Each harness passes plain, under `cyrius fuzz --poison`, under `--poison=ab`, and in the bounds-checked form
   item 3 settles.**
3. **Bounds-checked builds of the network libs — decided at 6.7.18's open, one question:** (a) the parsers read
   through forms the mode checks (a slice / a typed pointer with its extent) — a lib change, the folds' parts in their
   source repos; or (b) the mode extends to a raw `load*` / `store*` on a buffer whose extent the compiler knows — a
   language change, the user's call; or both. Either way a row shows an over-read in each family caught.
4. **The gates run them** — a registered gate (or `release-gate.sh` step) runs every `fuzz/*.fcyr` plain and under
   `--poison`, with a floor on the harness count, so a crash is seen before a tag, not after a push.
5. **Allocation on peer-chosen lengths** (PHP2Shell's out-of-memory half): every allocation a parser sizes from a
   peer field is capped and its failure handled (a refusal, never a write through a failed allocation) — a row per
   family with the length at its maximum.
6. **Every crash found is fixed in 6.7.18**, its input kept as a regression row; a fold's defect is fixed in its
   SOURCE repo (sigil, bayan, sandhi), released as a patch and re-vendored byte-identical (CLAUDE.md § *Ecosystem &
   stdlib*). A ledger id only for a finding that meets the rule.

Not in this issue (the audit's surface map decides them): the native TLS stack's parsers past the ClientHello
(`lib/tls_native_hs12.cyr`, `_hs13.cyr`, `_conn.cyr`), and `lib/net.cyr`'s own reads.
