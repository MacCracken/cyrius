# fdlopen: a trusted helper path for setuid consumers

**Filed:** 2026-06-02 by shakti (AGNOS privilege-escalation tool)
**Severity:** High *for setuid-root consumers* — the `fdlopen` helper is
`execve`'d with the consumer's privileges, and today it resolves to a
path inside the **invoking user's** `$HOME`, which a non-root caller can
replace. Non-issue for ordinary (non-setuid) consumers.
**Affects:** `lib/fdlopen.cyr` helper resolution + `threat-model.md`
trust-boundary assumptions. Blocks two shakti roadmap items; will affect
any future AGNOS setuid consumer that wants NSS/TLS via fdlopen.

## Summary

`threat-model.md` lists `~/.cyrius/dlopen-helper` as **Trusted — built by
`install.sh` from cyrius source**. That holds for the developer running
their own toolchain. It does **not** hold for a **setuid-root** consumer:

- shakti installs setuid-root (it is `sudo` for AGNOS). When invoked by an
  unprivileged user `mallory`, shakti runs with `euid=0` but
  `$HOME=/home/mallory`.
- If shakti called any `fdlopen`-backed stdlib path, `fdlopen` would
  `execve` `~/.cyrius/dlopen-helper` = `/home/mallory/.cyrius/dlopen-helper`
  — a file `mallory` owns and can replace — **as root, before shakti has
  authenticated anyone**. That is arbitrary root code execution.

So the helper's location in the caller's `$HOME` is a privilege-escalation
vector for the exact class of program AGNOS is built around. shakti
therefore cannot use `fdlopen` at all today, which blocks:

1. **NSS group resolution (LDAP/sssd).** `getgrouplist(3)` with real NSS
   dispatch needs libc via `fdlopen` (Path B in the archived
   `dynlib-nss-bootstrap.md`). Without it shakti parses local
   `/etc/group` only (see shakti ADR-005); LDAP/sssd group membership is
   a known gap.
2. **Remote policy fetch (fleet management).** `lib/tls.cyr` migrated to
   `fdlopen` at v5.6.37, so any HTTPS path inherits the same helper-trust
   requirement.

## What shakti needs from cyrius

A way to use `fdlopen` from a privileged process **without** trusting a
`$HOME`-resident helper. Concretely, any one (ideally all) of:

1. **A root-owned system helper path.** Install the helper at e.g.
   `/usr/lib/cyrius/dlopen-helper` (root:root, `0755`, not a symlink) in
   addition to / instead of `~/.cyrius/dlopen-helper`. `fdlopen` resolves
   the system path first, and **when `geteuid() != getuid()` (running
   setuid) ignores the `$HOME` copy entirely.**
2. **Ownership + mode + non-symlink enforcement at resolution time.**
   Before `execve`, `fstat` the helper and refuse it unless it is a
   regular file owned by uid 0 and not group/other-writable — the same
   check shakti already applies to its policy file and session-log dir.
3. **Integrity verification.** Let a consumer pin the helper's hash (or a
   signature) so even a writable trusted path can't be silently swapped.
   A compiled-in hash that `fdlopen` checks before exec would suffice.

### Proposed API shape (for discussion)

A trust-requiring entry point, leaving today's `fdlopen_init` /
`fdlopen_init_full` unchanged for non-privileged consumers:

```
# Resolve + verify a root-owned helper; refuse ($HOME copy is never
# consulted). Returns FDL_ERR_UNTRUSTED if no trusted helper is found.
fn fdlopen_init_trusted(): i64
```

shakti would call `fdlopen_init_trusted` and treat any non-OK return as
"NSS/TLS unavailable, fail closed" — never silently fall back to the
`$HOME` helper.

## Today's workaround (shakti side)

Both features are parked. NSS is local-files-only (ADR-005); remote
policy fetch is unimplemented. shakti's roadmap tracks both under
"Blocked (later)" pending this proposal.

## Notes / references

- `docs/development/threat-model.md` — the `~/.cyrius/dlopen-helper` trust
  row this proposal asks to qualify for setuid callers.
- `docs/development/issues/archived/dynlib-nss-bootstrap.md` — the NSS
  bootstrap investigation (Path B = `fdlopen` → libc `getgrouplist`).
- shakti `docs/development/roadmap.md` §"Blocked (later)", `docs/adr/005`.
- This is a security-hardening request, not a feature request: the goal
  is to let a privileged program use `fdlopen` without inheriting a
  user-writable code path into its root context.
