# `lib/syscalls_x86_64_agnos.cyr` — two new numbers are coming, and the file's stated authority is circular with the doc it mirrors

**Status:** 🟡 **OPEN** — filed 2026-08-05 from a full agnos ↔ cyrius syscall coverage audit.
**Placement:** unpinned. Items 1–2 are ~2 lines each and land **in lockstep with the agnos kernel arm**,
never before it. Item 3 is a one-line header correction available now.
**Severity:** Low for cyrius — ⭐ **the file is COMPLETE and correct today.** This is forward notice plus
a provenance fix, not a defect report.
**Affects:** cycc 6.5.6 and earlier.
**Filed from:** agnos. Originals — [`2026-08-05-syscall-96-fork.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-syscall-96-fork.md) ·
[`2026-08-05-syscall-97-chan-op.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-syscall-97-chan-op.md) ·
[`2026-08-05-abi-doc-covers-two-thirds-of-the-syscalls.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-abi-doc-covers-two-thirds-of-the-syscalls.md).

## ⭐ First, the audit result, because it is the opposite of what was being looked for

Measured at agnos 1.56.39 / cycc 6.5.6:

| | result |
|---|---|
| agnos kernel dispatch arms | **96** — `#0`–`#95`, contiguous |
| **cyrius `SysNrAgnos` constants** | **96 — complete, zero gaps** |
| cyrius wrappers | present for every number with a ring-3 consumer |
| agnos ABI doc individual rows | **65 of 96** |

The gap is entirely on the agnos documentation side. **No coverage work is owed by cyrius.**

Two audit traps worth recording so the next person does not re-file them as bugs:

- `sys_uname` / `sys_sysinfo` live in **`lib/sys.cyr`**, not in the syscall-number file, and both are
  correctly `#ifdef CYRIUS_TARGET_AGNOS`-armed onto the agnos numbers. An audit that greps only
  `syscalls_x86_64_agnos.cyr` reports them missing. They are not.
- `SYS_WRITE_BOOT_CHECKPOINT` (`#26`) genuinely has no wrapper. It is a kernel diagnostic with no ring-3
  consumer — **correct as-is**, do not add one to make a count come out even.

## 1. `SYS_FORK = 96` — reserved, not yet minted

agora is fork-per-connection (`agora/src/main.cyr:2702` calls `sys_fork()`) and cannot serve a second
connection on agnos. Needs `SYS_FORK = 96` plus a `sys_fork()` wrapper.

⛔ **Not until the agnos kernel arm exists.** On agnos an unknown `num` falls through the dispatch chain
and the caller reads the fall-through value as data — so a minted-but-unimplemented constant is worse
than none. A host build of the same consumer looks perfectly healthy either way; see
[[reference_target_arm_contract_bugs_are_invisible_offtarget]].

## 2. `SYS_CHAN_OP = 97` — the local-IPC channel band

agnos is replacing TCP-on-loopback as the desktop's control transport with a kernel-owned channel band
(`chan_*`, VFS tag `VFS_CHAN = 11`, ops `CH_*`) on **one** syscall. Design is complete and ruled on;
implementation is agnos 1.56.40. setu 0.8.0 will consume it and will declare a hard kernel floor.

⚠ **`#96` and `#97` were contested and are now assigned:** `#96` = `fork`, `#97` = `chan_op`, next free
`#98`. Whichever is built first must **not** take the other's number on the grounds that it got there
first — the operator assigned both, on 2026-08-05.

## 3. ⛔ The circular authority, and a 15-version-stale provenance stamp

- **This file, line 5** — *"**Faithful mirror of** `agnos/docs/development/agnos-userland-abi.md` (agnos 1.41.x)"*
- **That doc, line 191** — *"authoritative map is `kernel/core/syscall.cyr`'s header **+ the cyrius `syscalls_x86_64_agnos.cyr` peer**"*

For agnos syscalls `45–59` the chain is doc → cyrius → doc. **Neither file is canonical and each names
the other.** A wrong number introduced in either can then be "verified" against the other.

⭐ **This file's own §5 already has the right answer** — *"the agnos kernel is canonical"* — it is the
agnos doc that contradicts it. Cyrius's side of the fix is one sentence: keep §5, and drop the
implication in the header that the *doc* is the source rather than the kernel.

⚠ Separately: the `(agnos 1.41.x)` stamp is 15 minor versions behind a kernel at **1.56.39**. The
file's *contents* are current — it is only the stamp that is stale, which is worse than no stamp,
because it invites a reader to distrust a file that is actually right.

## What actually closes this class

Not another manual pass. agnos is adding a `scripts/check/syscall-abi-check.sh` that extracts all three
lists — kernel dispatch arms (⚠ including `#44 sched_yield`, which is dispatched only from the ring-3
entry stub and is invisible to a `grep 'if (num == '`), ABI-doc rows, and this file's `SysNrAgnos` — and
fails on any disagreement in number or name. **That gate is what makes this file's correctness checkable
rather than asserted**, and the 31 undocumented syscalls it just surfaced accumulated precisely because
nothing diffed them.
