# `TLS_CA_MAX_ROOTS` bounds nothing since 6.7.9 — keep the public name or retire it — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (a removed-symbol call). Raised by the 6.7.9 quick lane (bite 7),
whose fix removed the last reader; the 6.7.9 selection kept the name. Verified 2026-10-11 against the merged 6.7.9
tree: `grep -rn TLS_CA_MAX_ROOTS lib src cbt programs` finds only its declaration (`lib/tls_native_hs12.cyr:1991`,
`var TLS_CA_MAX_ROOTS = 300;`) and two comments; the only other reader is the 6.7.9 test that proves it bounds
nothing (`tests/tcyr/crypto/tls_client_cert_pem_sizing.tcyr:124-129`).
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D15 — keep.
already lists "`TLS_CA_MAX_ROOTS` is kept (default) or retired") (the user's call, asked at that release's open) —
placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's
[client-cert PEM sizing fix](2026-10-08-tls-client-cert-pem-decode-sized-at-ca-max-roots.md), which this decision
outlived (the roadmap carried it on that issue, now resolved).
**Severity:** Low — no defect; a public name that does nothing.
**Affects:** `lib/tls_native_hs12.cyr`, 6.7.9 on.

## Summary

`TLS_CA_MAX_ROOTS` (300) once capped a trust bundle's chain scratch (until 6.6.13, now sized from the bundle's own
block count) and a client certificate's PEM decode (until 6.7.9, now sized from the input). Nothing reads it now. A
program that assigns it still compiles and changes nothing — the quiet shape the bound-vars decision is about
([2026-10-11-tls-public-bound-vars-api-decision.md](2026-10-11-tls-public-bound-vars-api-decision.md)).

## The decision

- **(a) Keep it (default, the 6.7.9 selection):** the name stays, documented as inert in its comment (it is).
- **(b) Retire it:** delete the declaration, account for it in `docs/retired-symbols.allow`
  (`removed_symbol_census.sh`), drop the test's group that assigns it, and add a CHANGELOG + `ecosystem-migration.md`
  line (a consumer that assigns or reads it stops compiling at its pin bump).
