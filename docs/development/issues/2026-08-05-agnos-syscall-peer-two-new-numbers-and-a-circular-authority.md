# `lib/syscalls_x86_64_agnos.cyr` — two new numbers are coming, and the file's stated authority is circular with the doc it mirrors

**Status:** 🔴 **ACTIONABLE NOW — item 2 is BLOCKING agnos.** Filed 2026-08-05 from a full agnos ↔ cyrius
syscall coverage audit; **updated the same day: `#97`'s kernel arm has LANDED**, so the precondition this
ticket set for minting the constant is met and agnos `check.sh` is red until cyrius moves. Item 1
(`fork`/`#96`) is still forward notice. See §2.
**Placement:** ⭐ **Item 2 is ready to land NOW** — its agnos arm shipped in 1.56.40, which is the
lockstep condition this ticket set. Item 1 (`fork`) still waits for its own arm. Item 3 is a one-line
header correction available any time.
**Severity:** ⭐ **Item 2 is now BLOCKING a consumer** (agnos `check.sh` red). Items 1 and 3 remain low —
forward notice and a provenance fix. The file is not *wrong*; it is one constant behind a kernel that
shipped today.
**Affects:** cycc 6.5.7 and earlier.
**Filed from:** agnos. Originals — [`2026-08-05-syscall-96-fork.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-syscall-96-fork.md) ·
[`2026-08-05-syscall-97-chan-op.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-syscall-97-chan-op.md) ·
[`2026-08-05-abi-doc-covers-two-thirds-of-the-syscalls.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-abi-doc-covers-two-thirds-of-the-syscalls.md).

## ⭐ First, the audit result, because it is the opposite of what was being looked for

Measured at agnos 1.56.39 / cycc 6.5.6 (the audit that opened this ticket; agnos is now 1.56.40 with `#97` live — see §2):

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

## 2. `SYS_CHAN_OP = 97` — ⭐ **THE KERNEL ARM HAS LANDED. MINT IT.**

⭐ **UPDATED 2026-08-05 — this is no longer forward notice.** agnos **1.56.40** ships `#97 chan_op` with
a live dispatch arm, a boot-reserved 2 MB region, and `CH_CAPS`. The condition this ticket itself set —
*"not until the agnos kernel arm exists"* — is satisfied.

**agnos is BLOCKED on these two lines.** Its `scripts/check/syscall-abi-check.sh` gate (added in the
same cut, and this ticket's own recommended fix) now reports:

```
kernel 97 · abi-doc 97 · cyrius 96
FAIL: 1 syscall(s) the kernel implements are absent from cyrius:
        #97  chan_op
```

**The edit**, in `lib/syscalls_x86_64_agnos.cyr` after `SYS_UPTIME_US = 95` (line ~135):

```cyrius
    SYS_CHAN_OP          = 97;    # chan_op(op, a1, a2, a3) -> 0 / -CH_E_*; local-IPC channel band (agnos 1.56.40)
```

and a wrapper beside `sys_uptime_us`:

```cyrius
fn sys_chan_op(op, a1, a2, a3): i64 { return syscall(SYS_CHAN_OP, op, a1, a2, a3); }
```

⚠ **`#96` stays free for `fork`** — do not slide `chan_op` into it because it is the lower number.

⛔ **agnos deliberately did NOT route around this with a raw `syscall(97, …)`.** Raw numbers on agnos
paths are a confirmed shipping defect class in this ecosystem (jalwa: `poll`(7) → `open` *per frame*,
`read`(0) → `exit`), and the gate exists to stop exactly that. The ring-3 half of the band's region
kill-criterion test is also waiting on this constant.

### Original entry (kept — the design context still applies)

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
