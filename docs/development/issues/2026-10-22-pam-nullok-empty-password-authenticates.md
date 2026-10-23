# `pam_unix_authenticate` passes `nullok`: an account with an empty password field authenticates — OPEN

**Status:** 🟡 **OPEN** — kept as is in 6.7.18 by the user's decision; the refusal is planned.
**Placement:** 6.8.0 (the user, 2026-10-22: "keep nullok but plan it refuse empty as a part of 2.8.0 work", then "6.8.0
sorry") — never 7.x.
**Discovered:** 2026-10-22, the 6.7.18 security audit (`docs/audit/2026-10-22-security-audit.md`, the auth-secrets
surface; hardening, no ledger id).
**Severity:** Low (hardening) — a policy default, not a bypass: unix_chkpwd's `nullok` is what interactive PAM stacks
commonly pass.
**Affects:** `lib/pam.cyr` (`pam_unix_authenticate`) as of 6.7.17.

## Summary

`pam_unix_authenticate` runs unix_chkpwd(8) with the mode argument hard-coded to `nullok`, so an account whose shadow
password field is empty authenticates with an empty password. A program that uses cyrius's PAM helper to gate access
cannot ask for `nonull`.

## Reproduction

```sh
grep -n 'nullok' lib/pam.cyr        # the mode argument passed to unix_chkpwd
```

## The planned change

Pass `nonull`: an account with no password never authenticates through `pam_unix_authenticate` (a behaviour change —
the user decided it belongs to 6.8.0, not 6.7.18). A row: an account with an empty password field is refused;
a set password still authenticates.
