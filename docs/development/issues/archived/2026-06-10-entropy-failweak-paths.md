# Entropy fail-weak / fragmented sources — CVE-19

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High
**Affects:** `lib/ws.cyr`, `lib/sandhi.cyr`, `lib/random.cyr`, `lib/syscalls_x86_64_agnos.cyr` 6.1.31

## Summary

Randomness is sourced inconsistently across the network/crypto stdlib, with
silent fail-weak paths on exactly the non-Linux targets the sovereignty story
emphasizes.

- **WebSocket client mask, uninitialized on RNG failure** — `_ws_gen_mask`
  opens `/dev/urandom` via raw `syscall(2)`; on open failure it skips the read
  and stores the **uninitialized** `var mask[4]` stack bytes as the RFC 6455
  client mask (`ws.cyr:55-64`), with no error. The 16-byte `Sec-WebSocket-Key`
  has the same raw-syscall pattern (`ws.cyr:70-71`).
- **DNS query-ID fallback to clock** — sandhi falls back to clock-ns low bits on
  `/dev/urandom` failure (`sandhi.cyr:3444-3459`), reopening the Kaminsky
  cache-poisoning window.
- **Raw `/dev/urandom` bypasses `sys_getrandom`** — ws/sandhi use raw
  `syscall(2)`/`(0)` instead of `random_bytes()`/`sys_getrandom`, so on **Windows**
  (no `/dev/urandom`; `CreateFile` fails) and **AGNOS** these paths fail-weak.
- **AGNOS has no entropy primitive at all** — `lib/syscalls_x86_64_agnos.cyr`
  (67 `SYS_` consts) exposes no getrandom-class syscall, and `lib/random.cyr`
  (`:34`) has no AGNOS branch. Native TLS (the default backend) and all crypto on
  the flagship AGNOS userspace target therefore have **no RNG source**.

## Impact

Predictable WebSocket masks / Sec-WebSocket-Key, predictable DNS query IDs, and —
on AGNOS — keys/nonces with no real entropy. Crypto on the AGNOS target is not
currently safe.

## Proposed fix

- Route ws/sandhi/sigil entropy through `random_bytes()` / `sys_getrandom`
  (single source of truth in `lib/random.cyr`).
- Make `_ws_gen_mask` fail loudly (return error / abort the frame) instead of
  emitting an uninitialized mask; same for the Sec-WebSocket-Key path.
- Add an AGNOS entropy syscall to the (otherwise frozen) ABI surface — coordinate
  with the AGNOS kernel team; this is a real ABI addition, not a renumber — and a
  `random.cyr` AGNOS branch. Until then, document that crypto on AGNOS has no RNG.

## Status

Filed 2026-06-10. The AGNOS-entropy half is cross-repo (kernel ABI) and has been
**filed upstream**: `agnos/docs/development/issue/2026-06-10-cyrius-tls-entropy-syscall-gap.md`
(asks the kernel for a `getrandom`-class syscall — the in-kernel RDRAND source
already exists via `kaslr_seed`). The cyrius-side `lib/random.cyr` AGNOS branch +
ws/sandhi/sigil rerouting land once the kernel assigns the syscall number. See
also the AGNOS-security-model note in [unreviewed-dimensions](2026-06-10-unreviewed-dimensions.md).
