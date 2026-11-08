# `lib/syscalls_x86_64_agnos.cyr` has no peer for `#97`'s `CH_WINSZ_SET` / `CH_WINSZ_GET` ops (agnos 1.57.17)

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-04). agnos built the two ops in its 1.57.17 cut (no new syscall
number: two ops in `#97 chan_op`'s op-dispatched band), where they are reviewed and gated. Do not add the constants
before agnos's `1.57.17` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — the two `ChanOp` members after `CH_ENDOW = 0x05` (:376), and the
wrappers after `sys_chan_endow_disarm` (:463). The `CH_OP_SUPPORTED` note (:392) gains "0xFF from agnos 1.57.17".
**Filed:** 2026-11-04, by agnos. agnos owns the ops; cyrius owns the peer.
**Affects:** cyrius **6.7.18**. The ops exist from agnos **1.57.17**.
**Severity:** **Low as a defect, blocking for the consumers.** puka's agnos `pty_set_winsize` is `return 0`
(`puka/src/pty.cyr:312`); darshana's agnos `tty_winsize(fd)` reads the console's `winsize`#60 whatever `fd` is, and
its `tty_isatty(fd)` cannot tell a terminal channel from a display channel (both are `fd_kind`#111 `5`). Without a
peer each consumer has to hand-roll `syscall(97, 6, …)` — the shape puka already hand-rolls for `CH_ENDOW`'s PTY mode.

## The ask

```
enum ChanOp {
    ...
    CH_ENDOW  = 0x05;
    CH_WINSZ_SET = 0x06;   # (fd, (xpix<<48)|(ypix<<32)|(cols<<16)|rows) → 0 / negative CH_E_*   (agnos 1.57.17)
    CH_WINSZ_GET = 0x07;   # (fd, 0) → (cols<<16)|rows · (fd, 1) → (xpix<<16)|ypix · -1 = not a terminal / never sized
}

# The emulator's end (the end it kept) sizes the terminal it endowed — or is about to endow: a size set before
# CH_ENDOW + spawn is there when the child is born. xpix/ypix 0 = unknown.
fn sys_chan_winsz_set(fd, cols, rows, xpix, ypix): i64 {
    return syscall(SYS_CHAN_OP, CH_WINSZ_SET, fd, (xpix << 48) | (ypix << 32) | (cols << 16) | rows, 0);
}
# A program in a terminal: (cols << 16) | rows of the terminal `fd` is — winsize#60's packing — or -1 when fd is not
# a terminal channel end (also: no size was ever set). The -1 is the "is this fd a terminal?" answer for FDK_CHAN.
fn sys_chan_winsz(fd): i64 { return syscall(SYS_CHAN_OP, CH_WINSZ_GET, fd, 0, 0); }
# Its pixel size: (xpix << 16) | ypix (0 = the emulator gave none), or -1 as above.
fn sys_chan_winsz_px(fd): i64 { return syscall(SYS_CHAN_OP, CH_WINSZ_GET, fd, 1, 0); }
```

⚠ **Pass every argument explicitly** (the 5-argument `syscall` form, as `sys_chan_endow` does). `CH_WINSZ_GET`'s
selector is rdx: anything but 0 or 1 is refused with `-CH_E_ARG` (-6), so a 3-argument raw call with a stale rdx can
fail. Neither op reads a3 (r10).

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2, row 97 — authoritative)

| Op | Value | Caps bit | Arguments | Returns |
|---|---|---|---|---|
| `CH_WINSZ_SET` | 0x06 | 6 (0x40) | a1 = fd: the caller's OWN, non-terminal end · a2 = `(xpix<<48)\|(ypix<<32)\|(cols<<16)\|rows`, cols and rows 1..65535 | 0 · −5 BADFD (not a channel fd; not the caller's own end; a terminal end; a peer that is neither a terminal nor the caller's) · −6 ARG (cols or rows 0) · −9 PEERGONE (the terminal end is closed) |
| `CH_WINSZ_GET` | 0x07 | 7 (0x80) | a1 = fd · a2 = selector: 0 grid, 1 pixels | sel 0: `(cols<<16)\|rows` · sel 1: `(xpix<<16)\|ypix` · **−1**: not a terminal end the caller may use (closed, out of range, not a channel, an inert inherited copy, a DISPLAY channel, the emulator's own end) or never sized · −6: any other selector |

- The size belongs to the **terminal end** (the endpoint endowed with `CH_ENDOW_STDIO`) and dies with it.
- **Resize:** a SET whose word differs from the stored one (pixels included) raises **SIGWINCH 28** to the terminal's
  holders that watch bit 28 (`sigprocmask` SIG_BLOCK `1 << 28`, then `signalfd` with mask `1 << 28` — darshana's
  `tty_open_signalfd`); an unchanged size is silent. On SIGWINCH a program in a terminal re-reads `sys_chan_winsz(fd)`.
- **Probe:** `sys_chan_caps` bits 6 and 7. `CH_OP_SUPPORTED` is **0xFF** on a 1.57.17 kernel (0x3F before).
- `winsize`#60 (the console's grid) and `fd_kind`#111 are unchanged.

## Why it exists

agnos issue `2026-10-30-a-terminal-channel-has-no-window-size` (from bannermanor 1.9.0): a program in puka can only
learn the console's grid, and no program can tell a PTY endpoint from a display channel.

## Compatibility

Nothing existing changes: two enum members and three functions. `syscall-abi-check.sh` (agnos gate) compares
syscall NUMBERS only, so it stays green either way.
