# agnos peer: `SYS_PTRSCAN = 98` + a `sys_ptrscan` wrapper for the pointer band

**Status:** 🔵 **REQUEST, unbuilt.** Filed 2026-08-08.
**Repo owning the design:** agnos —
[`planning/pointer.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/planning/pointer.md)
and the peer ticket
[`2026-08-08-syscall-98-ptrscan.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-08-syscall-98-ptrscan.md).
**Cross-repo:** filed in **both** repos, per the standing rule that an agnos↔cyrius issue is recorded on
both sides rather than in whichever one noticed it.
**Severity:** Low for cyrius — two additions, no behaviour change to any existing target. It is a
**blocker** for the agnos side, because consumers must not hard-code the number.
**Precedent:** identical in shape to the `#97 chan_op` request, which cyrius satisfied in **6.5.8**
(`SYS_CHAN_OP = 97` + the `sys_chan_*` wrappers).

---

## What is being asked for

In `lib/syscalls_x86_64_agnos.cyr`:

1. `SYS_PTRSCAN = 98;` added to the agnos `Sys` enum.
2. `fn sys_ptrscan(buf, max)` — a thin wrapper beside the existing `sys_kbscan`, same shape:
   `return syscall(SYS_PTRSCAN, buf, max);`

Contract (kernel side, for reference — agnos owns it):
```
ptrscan(buf, max) -> bytes written, 0 = none this poll, <0 = error
```
Non-blocking drain of merged pointer samples. It is the pointer counterpart to `kbscan #42` and
deliberately **not** a variant of it — see below.

---

## Why the number is `#98`, and why it is not `#44` or `#96`

Verified mechanically on the agnos side rather than assumed:

- Every `num == N` dispatch arm in `agnos/kernel/core/syscall.cyr` covers **0-95 and 97**. `98` has none.
- ⚠ **`#44` looks free to that grep and is not** — `sched_yield` dispatches in the ring-3 entry stub
  (`kernel/arch/x86_64/syscall_hw.cyr:105`), not in `ksyscall`.
- ⚠ **`#96` looks free and is reserved** for `fork` by an operator ruling of 2026-08-05
  (`agnos/docs/development/roadmap.md:41`).
- `lib/syscalls_x86_64_agnos.cyr` currently defines 97 `SYS_*` constants with `SYS_CHAN_OP = 97` the
  highest, so both sides agree that 96 and 98+ are unassigned.
- The `#97` ticket already recorded *"Next free is `#98`"* the last time this was adjudicated.

---

## ⚠ Why this must be its own number, not folded into `kbscan`

A one-pixel-right mouse motion is `dX = 0x01`. Fed through the Set-1 → HID decoder that consumes
`kbscan #42`'s output (`_bhumi_set1_to_hid` in bhumi), `0x01` decodes to HID `0x29` = **Escape**, which the
compositor maps to **quit**. ⇒ If pointer samples shared the scancode ring, **moving the mouse would quit
the desktop** — and the same ring feeds `cyrius-doom`'s `input_poll`.

⇒ The separation is a correctness requirement, not tidiness. Please do not "simplify" it later by routing
pointer data through the keyboard wrapper.

---

## ⛔ What NOT to copy from `sys_kbscan`

Nothing in the cyrius wrapper itself, but for whoever reads both: the kernel's `kbscan` arm spins 256
iterations after `sti` to let the CPU take a pending **PS/2 IRQ1**, and that path is dead code on the
current hardware target (USB keyboard only). The pointer arm deliberately does not copy that spin. The
cyrius-side wrapper is a plain `syscall(...)` either way.

---

## Ordering

The agnos kernel arm can land first, but **consumers must wait for the named constant.** A raw
`syscall(98, …)` in consumer code is precisely the bug class agnos's `roadmap.md` tracks — raw Linux
numbers compiling clean on agnos and dispatching a different arm (`read(0)` → `exit`, and similar, found
shipping). So: cyrius defines `SYS_PTRSCAN`, then bhumi and aethersafha use it by name.

## Acceptance

- `SYS_PTRSCAN` resolves on the agnos target and is absent (or inert) elsewhere, matching how the other
  agnos-only `SYS_*` constants behave.
- `sys_ptrscan` compiles for the agnos target and does not perturb any Linux/host build.
- ⚠ No change to `sys_kbscan` or to the Set-1 decode path.
