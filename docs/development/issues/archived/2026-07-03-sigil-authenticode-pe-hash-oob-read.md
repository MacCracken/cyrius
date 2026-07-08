# sigil `authenticode_pe_hash` — 1–2 byte OOB read of the PE optional-header magic before the size guard

> **RESOLVED v6.4.27** (2026-07-08, folded-stdlib repair). Fixed at the sigil SOURCE
> (`~/Repos/sigil/src/authenticode.cyr`): hoisted `if (opt + 2 > pe_len) { return 0 - 1; }` above
> the 2-byte magic read (the prior guard only ensured `opt <= pe_len`); downstream reads are covered
> by the existing `secdir_off + 8 > pe_len` guard. Released as **sigil 3.10.1** + re-vendored into
> `lib/sigil.cyr`. cycc byte-identical (lib-only).

**Filed:** 2026-07-03 (v6.3.45 closeout security re-scan). **Severity:** Low — an over-read of 1–2
bytes on a MALFORMED PE, on the UEFI Authenticode signing path that is not exercised until the v6.4.x
UEFI Secure Boot arc. No in-repo callers, so no current regression surface.
**Cross-repo:** `sigil` is a VENDORED dependency (`lib/sigil.cyr` is re-vendored from `~/Repos/sigil`
`dist/`). **Do NOT patch `lib/sigil.cyr` directly** — it will be clobbered on the next re-vendor. Fix
at sigil's SOURCE and re-vendor, OR fold into the v6.4.x UEFI arc (which builds out this authenticode
module anyway — sigil 3.10.0 shipped the crypto floor at v6.3.43).

## Symptom / vector
`authenticode_pe_hash` (lib/sigil.cyr:~17741) reads the PE optional-header magic via
`_pe_rd16(pe, opt)` BEFORE validating that `opt + 2 <= pe_len`. The existing guard at ~:17746
(`secdir_off`) rejects a too-small image only AFTER the magic (and the checksum_off / ddir_off reads)
have already dereferenced past the buffer. On a truncated/hostile PE fed to `cyrius sign-efi`, that is
a 1–2 byte out-of-bounds read.

## Fix
Hoist a bounds check above the first optional-header read:
```
if (opt + 2 > pe_len) { return 0 - 1; }
```
and confirm the `checksum_off` / `ddir_off` reads are likewise covered before use. Add a malformed-PE
fixture (truncated at the optional header) that confirms the guard fires AND that a valid PE still
hashes identically.

## Related (same path, lower priority — INFO, no regression)
`authenticode_pe_sign` / `authenticode_pkcs7_sign` take an `out` buffer whose size is an UNCHECKED
caller contract. This is consistent with the shipped sigil DER/tool convention (caller owns+sizes the
top-level out buffer), so it is not a new class — but it is a new instance of caller-pre-sizing on a
security-signing path. Consider a size-out parameter or a documented minimum when the UEFI arc lands.
