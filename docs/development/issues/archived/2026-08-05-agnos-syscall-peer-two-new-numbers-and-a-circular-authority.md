> ## ✅ CLOSED — v6.5.13. Archived 2026-08-08. Nothing here is cyrius-actionable.
>
> All three items are resolved or enforced:
>
> - **Item 2 (`SYS_CHAN_OP = 97`)** — shipped v6.5.8, six wrappers live.
> - **Item 3 (circular authority)** — shipped v6.5.7; the peer header names
>   `agnos/kernel/core/syscall.cyr` as the single canonical source.
> - **Item 1 (`SYS_FORK = 96`)** — re-checked against agnos **1.56.42**:
>   `grep -c 'num == 96' kernel/core/syscall.cyr` → **0**. Still no kernel arm, so the
>   correct cyrius state is exactly what it is today: **unminted**.
>
> ⭐ **Why this archives rather than staying open as a reservation record.** The
> do-not-mint constraint is MACHINE-CHECKED, not doc-checked:
> `tests/gates/platform/syscall_wrapper_pass.sh` axis 5 asserts
> `no SysNrAgnos constant on 96 (fork has no kernel arm)` and fails the build if anyone
> adds one. An issue file cannot enforce that; the gate does, on every run. Keeping a file
> open to restate an invariant a gate already holds is how a queue fills with things nobody
> can act on — and the same axis now asserts the positive direction too (`#98` MUST be
> present, since agnos minted it), so the pair tracks the kernel in both directions.
>
> When agnos mints `#96`, the gate turns RED by design and names the number — that is the
> signal to add it, and it does not depend on anyone remembering this file exists.

# `SYS_FORK = 96` is reserved on the agnos peer, awaiting the agnos kernel arm

> **Retitled at v6.5.11.** This opened as *"two new numbers are coming, and the file's stated
> authority is circular with the doc it mirrors"*. Two of those three items have shipped, so the
> old title advertised work that no longer exists — the exact shape of a stale-but-open issue.
> **Only item 1 remains**, and it is gated on an agnos-side precondition, not on cyrius
> scheduling. The file stays open as the RESERVATION RECORD for `#96` so nobody assigns it
> elsewhere; the audit detail below is kept rather than deleted (archive, don't delete).
>
> Re-verified against live code at v6.5.11: `SYS_CHAN_OP = 97`
> (`lib/syscalls_x86_64_agnos.cyr:147`) with all six wrappers at `:207`/`:212`/`:217`/`:223`/
> `:229`/`:238`, and the authority header at `:5-8` naming `agnos/kernel/core/syscall.cyr` as the
> single canonical source. `SYS_FORK`/`#96` still absent, correctly.

**Status:** 🟡 **OPEN for ITEM 1 ONLY — items 2 and 3 have SHIPPED; nothing here blocks agnos any
more.** Re-verified against live code on cycc **6.5.10**, 2026-08-07:

| item | state | evidence (live, 2026-08-07) |
|---|---|---|
| **2 — `SYS_CHAN_OP = 97`** | ✅ **SHIPPED v6.5.8** | `lib/syscalls_x86_64_agnos.cyr:147` `SYS_CHAN_OP = 97;` plus six wrappers driving it (`:207` CAPS, `:212` MINT, `:217` SEND, `:223` RECV, `:229` CLOSE, `:238` **ENDOW**, the last added v6.5.9). ⚠ They are spelled `sys_chan_*`, **not** `chan_send`/`chan_recv`/`chan_close` — those names are already the in-process MPSC thread channel and last-definition-wins would have silently replaced it on agnos only (CHANGELOG [6.5.8]). |
| **3 — circular authority + stale stamp** | ✅ **SHIPPED v6.5.7** | `lib/syscalls_x86_64_agnos.cyr:1-20`: the header now reads *"Mirrors agnos's SYSCALL DISPATCH — `agnos/kernel/core/syscall.cyr` — which is the single canonical source"* and demotes the ABI doc to *"a secondary reference … NOT authority"*, with the doc→cyrius→doc loop written up in place. The `(agnos 1.41.x)` stamp is gone. |
| **1 — `SYS_FORK = 96`** | 🟡 **OPEN, correctly** | `grep -n 'SYS_FORK' lib/syscalls_x86_64_agnos.cyr` → nothing; `fn sys_fork` exists on the linux/aarch64/macos/windows peers but **not** the agnos one. This is deliberate: the header at `:42` records *"#96 = fork — STILL NOT MINTED. No dispatch arm exists in agnos 1.56.40 (`grep 'num == 96'` finds nothing)"*, and CHANGELOG [6.5.8] states the gate now asserts **both** directions. Unblocked only when the agnos kernel arm lands. |

**Placement:** unpinned — 6.x-line stdlib backlog, never 7.x. Item 1 is gated on an **agnos-side**
precondition, not on cyrius scheduling; it is not work cyrius can pull forward. Keep this file open
as the record of the reserved `#96` so nobody assigns it elsewhere.
**Severity:** Low. Nothing here blocks a consumer today — agnos `check.sh` went green when `#97`
minted at v6.5.8.
**Affects:** item 1 — cycc 6.5.10 and earlier. Items 2/3 — fixed at 6.5.8 / 6.5.7.
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

## 2. `SYS_CHAN_OP = 97` — ✅ **MINTED v6.5.8. CLOSED.**

> **SHIPPED.** `SYS_CHAN_OP = 97` landed at v6.5.8 exactly as specified below, verified against
> `agnos/kernel/core/syscall.cyr:7620` (all five ops CAPS/MINT/SEND/RECV/CLOSE dispatching,
> `CH_OP_SUPPORTED = 0x1F`) rather than against the ABI doc. v6.5.9 added the sixth op,
> `CH_ENDOW` (`lib/syscalls_x86_64_agnos.cyr:174`, `:238`), and `sys_spawn_path_env`
> (`:1026`) alongside it. The wrapper naming diverges from the sketch below — see the Status
> table. **Do not re-open this section.**

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

## 3. ✅ The circular authority, and a 15-version-stale provenance stamp — **FIXED v6.5.7**

> **SHIPPED.** Cyrius's half is done exactly as §3 recommended — the header now names the agnos
> kernel dispatch as canonical and the ABI doc as a secondary reference, and the stale
> `(agnos 1.41.x)` stamp is gone (`lib/syscalls_x86_64_agnos.cyr:1-20`). The **agnos-side** half —
> `agnos-userland-abi.md:191` still naming the cyrius peer as part of its authority — is an agnos
> edit, not a cyrius one, and is not tracked by this file.

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
