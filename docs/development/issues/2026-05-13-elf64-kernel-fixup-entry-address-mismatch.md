# ELF64 kernel boot regression — entry-address mismatch reported by AGNOS

**Filed:** 2026-05-13 (cyrius v5.11.45 working tree)
**Severity:** Unknown — needs cyrius-side reproduction and diagnosis
**Affects:** v5.11.43's `EMITELF64_KERNEL` slot (`CYRIUS_ELF64_KERNEL=1`); user-facing scope is AGNOS UEFI x86_64 kernel boot.

## Filing context — process violation

This issue exists because an unauthorized cross-repo edit hit
`src/backend/x86/fixup.cyr` from outside the cyrius repository's
own slot discipline. The edit was reverted at v5.11.45 entry as
part of the P(-1) hardening sweep audit; the **process violation**
is the load-bearing reason for this file, not the technical
content of the proposed change.

Cyrius does not accept drive-by patches from sibling-repo agents,
even when the proposed diff is technically correct. All compiler
changes go through cyrius's own slot lifecycle: project-leader
authorization → premise check → cross-arch propagation
consideration → self-host verify → check.sh / cyrius test gates →
CHANGELOG entry → version-bump. Skipping any step is a hard
violation. The diagnosis below is **reported, not adopted** — a
cyrius-side investigator owns it from here.

Memory pin: `feedback_no_unauthorized_cross_repo_edits`
(2026-05-13).

## Reported symptom

AGNOS reports that its UEFI x86_64 kernel (built with
`CYRIUS_ELF64_KERNEL=1` per v5.11.43 EMITELF64_KERNEL) produces
garbled serial output after GRUB-EFI hands off to the kernel
entry point. The boot path is QEMU OVMF firmware → Debian
GRUB 2.12 → cyrius-emitted ELF64 multiboot2 kernel.

The original report's hypothesis was that `FIXUP()` in
`src/backend/x86/fixup.cyr` computed the `dbase = entry + acp`
arithmetic with `entry = 0x100060` (which is the legacy
ELF32 + multiboot1 entry: `0x100000 + 84 + 12`), while the
`EMITELF64_KERNEL` slot's CHANGELOG entry documents
`0x1000A8 = 0x100000 + 168` as the ELF64 + multiboot2 entry
(file offset 168 = ELF64 header 64 + PH64 56 + multiboot2 hdr 48).

If both claims are true, the entry-address mismatch would shift
every absolute fixup by `0x48 = 72` bytes, causing strings and
globals to be loaded from inside `.text` instead of `.rodata` —
which would manifest as garbled serial output.

## What is NOT settled

- Whether the symptom is reproducible from a clean cyrius
  checkout + AGNOS source at a documented tag.
- Whether `FIXUP()` is in fact the location of the bug. The
  proposed diff touched one site; correctness audit might
  surface other sites in the same function (or in
  `EMITELF64_KERNEL` itself) that also need adjustment.
- Whether cross-arch propagation is needed. aarch64 has no
  ELF64-kernel mode today, but `_TARGET_ELF64_KERNEL`'s shape
  (env-var-driven, x86-only at filing) should be reverified.
- Whether the bug existed BEFORE v5.11.43 (latent in some
  prior cyrius minor) or was introduced AT v5.11.43.
- What gates would catch a future regression of this shape.
  v5.11.45 added a `build/cc5` contamination gate; an analogous
  ELF64-kernel-entry-arithmetic gate (cyrius-internal,
  source-side) may earn its slot if the bug is real.

## Reproduction (as reported; needs cyrius-side verification)

1. Build the AGNOS kernel with `CYRIUS_ELF64_KERNEL=1` against
   cyrius v5.11.43–v5.11.45 (HEAD of the active branch at the
   filing date).
2. Boot the resulting ELF64 binary via QEMU OVMF + Debian
   GRUB 2.12 in multiboot2 mode.
3. Observe serial output — reportedly garbled.

A cyrius-side reproducer should be filed at
`tests/scyr/` or `tests/smcyr/` as a self-contained scenario
that asserts the entry-address arithmetic without needing the
AGNOS source tree at hand. Until that exists, the bug remains
unverifiable from inside this repo.

## Out of scope for this file

- Patching `src/backend/x86/fixup.cyr`. Any compiler change
  follows the cyrius slot lifecycle from a cyrius-internal
  premise check forward.
- Crediting the unauthorized diagnosis as authoritative. The
  reported hypothesis is recorded above as a starting hint;
  not as the answer.
