# sigil (the crypto / trust fold) has no runtime logging: none of its 68 `src/` files calls sakshi — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-11 during the 6.7.9 fold wave (sigil 3.13.12's agent, reported in passing).
Verified 2026-10-12 at sigil 3.13.12 (`cf03996`): `grep -rn 'sakshi_' src/` in `~/Repos/sigil` is empty across all 68
source files; the only log in sigil is `src/audit.cyr`'s `alog_*`, an append-only audit-event record the caller keeps
and saves, not runtime logging. sakshi is in sigil's `[deps] stdlib` (since its 6.5.17 pin) and is used only by
`tests/tcyr/x509_offdiag.tcyr` (`sakshi_set_level`); `dist/sigil.deps` does not list it.
**Placement:** Unplaced — the user, 2026-10-12: "leave it for later". Only the user places it.
**Discovered:** 2026-10-11, sigil 3.13.12's warning work: the one large-static warning left in sigil's own tree
comes from the sakshi its manifest prepends, which no `src/` file calls.
**Severity:** Medium — no wrong value; a verification failure, a refused trust store, a fail-closed path or a
subprocess failure inside the trust / crypto layer leaves no trace beyond its return code, while the sibling folds
(yukti, patra, mabda, vani, sandhi, yantra) all log through sakshi. A folded-stdlib gap, so high priority once placed.
**Affects:** sigil 3.6 – 3.13.12 (`lib/sigil.cyr` in every cyrius that vendors it, and every `lib/tls.cyr` program).

## Summary

sigil verifies signatures, certificate chains, Secure Boot / IMA / dm-verity / LUKS / TPM state and trust stores,
and every failure is reported only as a return value (`0`, `-1`, an `Err`). Nothing records WHY a chain or signature
was refused, which policy check fired, or that a fail-closed path was taken, so a consumer debugging a refused
handshake or a failed boot-chain check has only the code.

## Reproduction

```sh
cd ~/Repos/sigil
grep -rn 'sakshi_' src/ | wc -l            # 0
grep -rln 'sakshi_' tests/                 # tests/tcyr/x509_offdiag.tcyr only
cat dist/sigil.deps                        # no sakshi leaf
```

## Proposed fix

In sigil's source repo (never the vendored copy), released as a sigil patch and re-vendored byte-identical:

- Log through sakshi at the failure and refusal points: signature and chain verification failures (with the
  reason: expiry, EKU, hostname, path length, unknown algorithm, non-canonical DER, small-order key), trust-store load
  refusals, the fail-closed paths (`sv_verify_boot_chain`, `keyring_validate_chain`, the TPM / Secure Boot / IMA /
  dm-verity / LUKS helpers), CSPRNG failures, and subprocess failures in `agnosys_run_*`.
- **Never** log key material, nonces, shared secrets, plaintext, MAC / tag values or anything derived from a secret,
  and nothing inside constant-time code (no log call whose execution depends on secret data).
- Levels chosen so a consumer that never raises sakshi's level sees nothing new by default; the level for each
  call site, and whether anything prints by default, is the user's decision at placement.
- sakshi becomes a required leaf of the sigil bundle (`dist/sigil.deps`), so every `lib/sigil.cyr` / `lib/tls.cyr`
  build includes it; the cyrius side re-vendors, and the change goes in the CHANGELOG and
  `ecosystem-migration.md`.

## Consumer-side workaround

None: the reason for a refusal is not recoverable from the return code.
