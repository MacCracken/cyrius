# `lib/syscalls_x86_64_agnos.cyr` has no `CM_NOSERIAL` (console_mode#110 bit 4) peer

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-08). agnos has defined and built the bit in its 1.57.18 cut, where it is reviewed and gated (`scripts/smoke/console-ansi-smoke.sh`, phase N). Do not add it here before agnos's `1.57.18` tag.
**Placement:** the stdlib lane. `lib/syscalls_x86_64_agnos.cyr`: one constant in `enum AgnosConsoleMode`, after `CM_FLUSH = 2`. `sys_console_mode(set, clear)` (v6.7.11) is unchanged — the bit travels in `set` / `clear` like the other two.
**Filed:** 2026-11-08, by agnos. agnos owns the ABI; cyrius owns the peer.
**Affects:** cyrius **6.7.18**. The bit exists from agnos **1.57.18**; an older kernel answers -1 to it (an unknown bit).
**Severity:** low. A program can pass the literal 4 today; the constant is what keeps it from being a magic number, and what `agnos_abi_doc_parity` will read.

## The ask

```
enum AgnosConsoleMode {
    CM_NOECHO   = 1;
    CM_FLUSH    = 2;
    CM_NOSERIAL = 4;      # agnos 1.57.18 — PER PROCESS: this process's console writes are drawn, not mirrored to COM1
}
```

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2, row 110 — authoritative)

- **`CM_NOSERIAL` = 4 is NOT the console's mode.** NOECHO is the console's, held by its setter. NOSERIAL is a property of the **calling process**, for **its own** writes:
  - while it is set, what the process writes to a console fd (fd 1, fd 2, a dup — `fd_kind`#111 = 1) is drawn on the framebuffer and kept in the klug ring, but **not mirrored to COM1**;
  - the kernel's own lines, panics, and every other process's writes — the caller's children included — stay mirrored;
  - it **dies with the process** (it lives in the process's slot, scrubbed when the slot is reused), and a fork / spawn child starts **without** it;
  - any process may set or clear only its own; there is no holder and no line involved.
- `new = (old & ~clear) | set` as before: `set` wins over `clear`. The return (the flags **before** the call) now carries the caller's bit 4 beside the console's bit 1: NOECHO held by anyone + this process opted out = `5`.
- Any other bit — 8 and up, or FLUSH in `clear` — is still -1 with nothing changed.
- **Probe:** `#110(4, 0)` answers ≥ 0 on a supporting kernel (then clear it with `#110(0, 4)`), -1 before 1.57.18.

**Why:** a full-screen program on the console (thoth's TUI, cyim, chakshu) repaints often, and every console byte was also written to the 16550. Measured under KVM at 2048x2048 (128x64 cells): one 8,634-byte frame takes **236 ms** mirrored and **35 ms** opted out; on a real 16550 at 115200 the mirror alone would be ~0.75 s per frame.

## Self-proving repro (once the constant lands)

```
var p = sys_console_mode(CM_NOSERIAL, 0);     # >= 0 on agnos 1.57.18+
sys_write(1, "hidden from COM1\n", 17);       # drawn on the console, absent from the serial log
var q = sys_console_mode(0, 0);               # q & CM_NOSERIAL == CM_NOSERIAL
sys_console_mode(0, CM_NOSERIAL);
sys_write(1, "back on COM1\n", 13);           # in the serial log again
```
A fake-kernel row like axis 10's: `(CM_NOSERIAL, 0)` and `(0, CM_NOSERIAL)` reach #110 as given; the constant is 4.

## Compatibility

Additive: one constant. Nothing existing changes.

## Related

- `archived/2026-10-13-agnos-sys-console-mode-110-peer.md` — the number and its first two bits (v6.7.11).
- agnos issue `2026-11-06-the-console-is-short-of-a-terminal.md` (filed from thoth 0.55.2) — the console's escape support grew in the same cut; that needs no cyrius change.
