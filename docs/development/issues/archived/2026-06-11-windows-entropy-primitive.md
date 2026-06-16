# Windows (and AGNOS) lack a real CSPRNG primitive — `sys_getrandom` is a fail-closed `-1` stub — OPEN

- **Filed**: 2026-06-11
- **Source**: carved out of CVE-19 (entropy fail-weak paths) during F2 / v6.1.36. The Phase-F decision was "fix Linux/macOS now, file the Windows primitive as a follow-on."
- **Affects**: `lib/syscalls_windows.cyr`, `lib/syscalls_x86_64_agnos.cyr` — `sys_getrandom`; all entropy consumers (`lib/ws.cyr`, `lib/sandhi.cyr`, `lib/sigil.cyr` keypair/nonce/salt sites, `lib/tls_native.cyr`) on those targets.
- **Severity**: **Medium** — fail-CLOSED, not fail-weak. On Windows/AGNOS the affected operations now error loudly (no weak/uninitialized entropy is emitted), but CSPRNG-dependent features (native TLS, websocket masking, DNS TXID, sigil keygen) are **non-functional** on those targets until a real source lands.
- **Status (2026-06-15): RESOLVED (both targets) — closed.** The CSPRNG *primitive* now exists on
  every target. **Windows (cyrius 6.2.12):** `lib/syscalls_windows.cyr` `sys_getrandom` composes
  **bcryptprimitives.dll!ProcessPrng** via a new `0xF01A` PE reroute (DLL id 3 in `src/backend/pe/emit.cyr`
  `_pe_ensure_procprng`/`_pe_dll_name`, `src/backend/x86/emit.cyr` `EPROCPRNG_PE`, `src/frontend/parse_expr.cyr`
  dispatch); returns `len`/`-1`, no weak fallback (CVE-19). Required a `_pe_layout` fix (`while (dll < 3)`
  → `< 4` so the 4th DLL's import descriptor is emitted). Verified: `tests/tcyr/getrandom.tcyr` PASSES on
  **real Windows (cass)** + wine; PE imports `bcryptprimitives.dll!ProcessPrng`. **AGNOS:** already
  resolved — a real kernel `getrandom` (syscall #45, Zen RDRAND) landed at **agnos 1.45.0**, and the
  vendored `lib/syscalls_x86_64_agnos.cyr` `sys_getrandom` calls it (no longer a `-1` stub; the issue's
  AGNOS premise had gone stale). **Follow-on (separate issue):** `lib/sigil.cyr` + `lib/tls_native.cyr`
  read `/dev/urandom` directly instead of routing through `sys_getrandom`, so their keygen/nonce paths
  stay non-functional on Windows — tracked in `2026-06-15-sigil-windows-entropy-not-via-getrandom.md`.
- **Status (2026-06-11): OPEN.**

## Background

CVE-19 routed `lib/ws.cyr` (`_ws_gen_mask`, `_ws_handshake_request`), `lib/sandhi.cyr`
(`_sandhi_resolve_random_u16`), and sigil's keygen/nonce/salt sites through
`sys_getrandom` and made every consumer **fail closed** on a short/failed read
(no uninitialized buffers, no clock-derived DNS TXID). On Linux this is
`getrandom(2)`; on macOS it ESYSXLAT's to `getentropy` (both work today).

But `sys_getrandom` lives only in `lib/syscalls_linux_common.cyr` (shared by the
Linux + macOS peers). The **Windows** peer (`syscalls_windows.cyr`) and the
**AGNOS** peer (`syscalls_x86_64_agnos.cyr`) have no getrandom/getentropy
equivalent. To keep those targets compiling AND fail-closed, CVE-19 added a
**`sys_getrandom` stub returning `-1`** to each. So entropy consumers on
Windows/AGNOS now fail loudly instead of silently emitting weak values — correct,
but the feature is dark on those platforms.

## What's needed

### Windows — a real CSPRNG primitive
Replace the `-1` stub in `syscalls_windows.cyr` with a real source via the PE
import shim:
- **`ProcessPrng`** (bcryptprimitives.dll) — the modern, dependency-light Win32
  CSPRNG (preferred; one call, no provider handle), **or**
- **`BCryptGenRandom`** (bcrypt.dll) with `BCRYPT_USE_SYSTEM_PREFERRED_RNG`.

Wire it through the existing PE import/syscall shim (mirrors how the Windows
process/threading/dir-listing primitives were added in v6.1.16). Return the
filled byte count (== len) on success, `-1` on failure. Verify on `cass`:
a websocket mask + a native-TLS client nonce + a DNS lookup all succeed and
produce unique values across calls.

### AGNOS — kernel getrandom syscall
AGNOS has no userspace entropy syscall in its frozen ABI. This is **filed
upstream** (the AGNOS kernel getrandom request). Once the kernel assigns a
syscall number, add `SYS_GETRANDOM` + the wrapper to `syscalls_x86_64_agnos.cyr`
(replacing the stub) and re-verify. Until then, AGNOS TLS/crypto remain
documented-unsafe (no RNG).

## Do NOT

- Do **not** re-introduce a weak fallback (uninitialized buffer, clock-ns,
  PID-mix) on any target to "make it work". A predictable mask/TXID/key is worse
  than a failed operation — that regression is exactly what CVE-19 closed.

## References
- CVE-19 (entropy fail-weak paths) — `issues/2026-06-10-entropy-failweak-paths.md`
- The CVE-19 fix shipped in v6.1.36 (Phase F, F2). See CHANGELOG.
