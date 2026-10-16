# The native TLS stack's public bound vars still drive storage their consts size: a raised `TLS12_RANDOM_LEN` smashes the stack — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-11, `40eae8d8`: every read of `TLS_HANDSHAKE_HEADER_LEN` / `TLS_MAX_DIGEST_LEN` / `TLS_RANDOM_LEN` / `TLS_RECORD_MAX_PLAINTEXT` / `TLS12_VERIFY_DATA_LEN` / `TLS12_RANDOM_LEN` / `TLS_SHA384_CTX_LEN` in lib/ reads its `_X` const (198 sites), so a write to the var is inert; `TLS_RECORD_MAX_PLAINTEXT` is the protocol's 2^14 (D17, the user 2026-10-15: a protocol constant). The filed repro prints "returned" and exits 0 (it was exit 139). Rows: NEW `tests/tcyr/crypto/tls12_random_len_writable_bound.tcyr` (the repro + the master secret and key_block at the 32-byte references, 7/7), NEW `tls_public_bound_writes_inert.tcyr` V / C / M (the verify_data, SHA-384 clone and HRR `mh` sites) and R1–R3 (D17) — each 139 or 0/5 on the 6.7.11 lib; `lib_buffers_sized_by_const.sh` axis 6 holds all 14 twins (the TLS exemption is gone); the TLS corpus differential identical on x86_64, qemu-aarch64 and PE, crossos/tls* 298/298 on ecb / ach / cass / pi. Filed alongside: the literal `TLS_SHA256_CTX_LEN` (`2026-10-15-tls-sha256-ctx-len-literal-var-drives-transcript-clone.md`, 6.7.14). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — filed 2026-10-11 from the 6.7.9 quick lane (bite 5), where the same class was fixed for
every non-TLS twin; the TLS stack's 190 read sites and one API question did not pack into that bite.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D17 — a protocol constant.
**Discovered:** 2026-10-11 during 6.7.9's lib-literal-bounds fix (issues/2026-10-08-lib-literal-bounds-and-writable-
public-bounds.md item 5), by deriving every `var X = _X;` twin in cyrius's own lib/ and listing where the var is read.
**Severity:** Medium (the item-5 class: a program that writes a public bound var corrupts memory; no attacker crosses a
boundary — the program writes its own var — so it is a bug, not a ledger id).
**Affects:** cycc 6.7.6 (the const / var split) – 6.7.9-dev.

## Summary

6.7.6 gave every public bound in lib/ a `const _X` twin that sizes its buffers and kept `var X = _X;` for the API. 6.7.9
made the const drive every loop, cap, stride and allocation outside the TLS stack (`TLOCAL_MAX_SLOTS`, `TLS_REG_MAX`,
`SPAWN_ARGV_MAX`, `KEV_SIZE`). In `lib/tls_native*.cyr` the vars are still read at 190 sites, so writing one of them
makes the code disagree with the storage the const sized:

| var (const) | reads | where | the storage it disagrees with |
|---|---|---|---|
| `TLS_HANDSHAKE_HEADER_LEN` (4) | 122 | hs12 55, hs13 64, lowlevel 3 | `var mh[_TLS_HANDSHAKE_HEADER_LEN + _TLS_MAX_DIGEST_LEN]` (hs13 HRR message_hash); every header offset into a caller-sized message |
| `TLS_MAX_DIGEST_LEN` (48) | 27 | hs12 4, hs13 23 | heap allocations sized by the var, filled by a 32 / 48-byte digest — a LOWERED var overflows them |
| `TLS_RANDOM_LEN` (32) | 14 | hs12 6, hs13 8 | randoms allocated and read by the var, written to a fixed 32-byte wire field |
| `TLS_RECORD_MAX_PLAINTEXT` (16384) | 13 | conn 4, hs12 5, hs13 1, lowlevel 2, tls.cyr 1 | record-limit checks, fragment clamps, a ctx write buffer sized var + 64 |
| `TLS12_VERIFY_DATA_LEN` (12) | 7 | hs12 7 | the PRF writes this many bytes into `var expected[_TLS12_VERIFY_DATA_LEN]` |
| `TLS12_RANDOM_LEN` (32) | 4 | hs12 4 | two copies of this many bytes into `var seed[_TLS12_SEED_LEN]` (64 B) — the repro |
| `TLS_SHA384_CTX_LEN` (208) | 3 | lowlevel 3 | `memcpy(&clone, hctx, TLS_SHA384_CTX_LEN)` into `var clone[_TLS_SHA384_CTX_LEN]` |

## Reproduction

`repros/2026-10-11-tls12-random-len-writable-bound.cyr` (x86_64 Linux, the tree's `build/cycc`): after
`TLS12_RANDOM_LEN = 256`, `tls_native_12_master_secret` copies 512 bytes into its 64-byte stack seed.

```sh
cat docs/development/issues/repros/2026-10-11-tls12-random-len-writable-bound.cyr | build/cycc > /tmp/tr \
  && chmod +x /tmp/tr && /tmp/tr; echo "exit $?"
# actual: exit 139 (SIGSEGV), "returned" never printed · expected: "returned", exit 0
```

`tests/gates/memory/lib_buffers_sized_by_const.sh` axis 6 lists every read site; it exempts these seven vars by their
declaring file only while this filing is open.

## Root cause

The 6.7.6 split, as in the parent issue's item 5: the const sizes the storage while the public var, kept for the API,
still drives the code that indexes, copies into and allocates it.

## Proposed fix

1. Every read of these seven vars inside lib/ reads the const (`_X`): value-identical, so the stack behaves exactly as
   it does today unless a program writes a var; the TLS / crypto `.tcyr` corpus must stay green.
2. ⚠ The one question for the user: is `TLS_RECORD_MAX_PLAINTEXT` a tunable? Today a program that LOWERS it gets
   smaller outgoing fragments (hs12:932, tls.cyr:1486) but also refuses incoming records over the lowered size
   (hs12:114, hs13:2896), which breaks interop with any peer that sends a full 2^14 record — so it does not work as a
   max-fragment knob now. Recommended: treat it as the protocol constant it is (read the const everywhere), as for the
   other six; a real max_fragment_length (RFC 6066) is a feature, not this var.
3. Acceptance: the repro prints "returned" and exits 0; a `tests/tcyr/crypto/` row built from it (and one per storage
   site above: verify_data into `expected`, the SHA-384 clone, the HRR `mh`) fails on 6.7.9 and passes after; axis 6
   of `lib_buffers_sized_by_const.sh` holds the TLS twins to the rule (archiving this file ends the exemption by
   itself); the crypto corpus and `crossos/tls*` rows green on x86_64, aarch64 and PE.

## Consumer-side workaround

Do not write the TLS stack's public bound vars; read them only.
