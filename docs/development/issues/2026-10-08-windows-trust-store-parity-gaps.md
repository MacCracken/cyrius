# Windows native-TLS trust store: four gaps against the Windows chain engine (CYRIUS-2026-0020's *Not covered*) — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 against 6.7.6 @ 2fb6ad8b by reading the live loader
(`lib/tls_native_hs12.cyr:2311-2362`, `_tn_w_export` `:2569`, `_tn_ca_read_win` `:2597`): it opens CurrentUser `ROOT`
read-only, filters by the root-program properties and the `Disallowed` STORE, and reads nothing else. Not re-verified
on hardware (needs cass); none of the four was measured there.
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.6.14 (2026-10-02, the wintrust lane's *Not covered* for CYRIUS-2026-0020; backlog entry ca5b83d1);
filed 2026-10-08 from roadmap.md.
**Severity:** Medium — two gaps fail closed (servers Windows accepts are refused), two may trust a root the Windows
chain engine would not.
**Affects:** 6.6.14 (the CurrentUser `ROOT` export) through 6.7.6, Windows only.

## Summary

Since 6.6.14 `tls_native_set_ca_system` on Windows exports the TLS roots of the CurrentUser `ROOT` logical store
(`_TN_W_STORE_FLAGS` = CURRENT_USER | READONLY | OPEN_EXISTING, `:2355`) as a PEM bundle, dropping a root whose
purposes leave out serverAuth (clientAuth for a server ctx), refusing whole a root with a Disable / NotBefore date or
root-program name constraints, and dropping a root also in the `Disallowed` store. Where that differs from what
SChannel / the CurrentUser chain engine trusts:
1. **ProtectedRoots policy — unverified.** CurrentUser `ROOT` includes roots a user added; under the
   `ProtectedRoots` policy (HKLM `…\SystemCertificates\Root\ProtectedRoots`, `Flags`) the chain engine can ignore
   user-added roots (e.g. `CERT_PROT_ROOT_DISABLE_CURRENT_USER_FLAG`). The loader reads the logical store as is, so
   under that policy it may trust roots Windows would not. Never tested.
2. **The auto-updated disallowed CTL is not read** (`:2341-2344`) — only the `Disallowed` store, and only against
   ROOTS (never a server's intermediates or leaf). On cass the store is empty while the CTL holds ~97 hashes (none a
   `ROOT` certificate at 6.6.14).
3. **A root with a dated distrust is refused whole** (`:2326-2333`): a leaf issued before a root's NotBefore date —
   which SChannel accepts — fails here (live at 6.6.14 for SecureTrust CA, NotBefore 2026-09-15).
4. **Roots Windows has not fetched yet are invisible** (`:2344-2345`): Windows' automatic root update downloads an
   AuthRoot root on demand when its chain engine meets it; the native client sees only roots already in the store,
   so those servers fail `TLS_ERR_CERT_INVALID`.

## Reproduction

On cass (none run for this filing):
1. Add a test root to CurrentUser `ROOT` (`certutil -user -addstore Root t.cer`), set `ProtectedRoots\Flags` to
   disable CurrentUser roots, connect natively to a server under that root → expected refused, as SChannel does.
2. Read `HKLM\…\AuthRoot\AutoUpdate\DisallowedCertEncodedCtl` and check whether any hash names a root the bundle
   exports, or an intermediate a test chain uses.
3. A leaf under SecureTrust CA issued before 2026-09-15 → SChannel accepts, native refuses.
4. A server whose root is in AuthRoot but not yet in the local store (a fresh profile) → SChannel fetches it and
   accepts; native refuses.
`tests/tcyr/crossos/tls_system_trust_store.tcyr` is the place for the measurable ones.

## Root cause

Design limits stated at 6.6.14: the verifier has no per-root date or name bound and no network fetch; the loader
reads one store plus `Disallowed` and no registry policy.

## Proposed fix

1. Read `ProtectedRoots\Flags` and, when CurrentUser roots are disabled, export `LocalMachine` `ROOT` (+ AuthRoot,
   Enterprise) instead of the CurrentUser logical store.
2. Parse the disallowed CTL (a PKCS#7 CTL of SHA-1 hashes) and apply it to every certificate of a chain, not only roots.
3. Give the verifier a per-root NotBefore bound so a dated root anchors leaves issued before its date.
4. Fetching roots is a network action the stdlib does not take today — the user's call; the alternative is to keep
   failing closed and say so in `lib-tls-contract.md` (it does).
