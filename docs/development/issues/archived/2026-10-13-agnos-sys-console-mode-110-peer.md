# `lib/syscalls_x86_64_agnos.cyr` has no `sys_console_mode`#110 peer — RESOLVED

> ✅ **RESOLVED in v6.7.11** (LIB-4, `e7cac25f`; comments by the review fix `338fabc0`: `SYS_CONSOLE_MODE = 110` after `SYS_WINSIZE`, `enum AgnosConsoleMode { CM_NOECHO = 1; CM_FLUSH = 2; }` right after `SysNrAgnos` (an enum cannot nest), `fn sys_console_mode(set, clear)` after `sys_winsize` with the row-110 contract in its doc comment, and `SIGWINCH = 28` in `AgnosSignal`. The ask builds and hands the kernel's answer back unchanged. No decision needed (additive, to the contract). Rows: `agnos_peer_fake_kernel.sh` axis 10 (6 rows: `(CM_NOECHO | CM_FLUSH, 0)` / `(CM_FLUSH, 0)` / `(0, CM_NOECHO)` / `(0, 0)` reach #110 as given, the answer is returned as is, the constants are 1 / 2 / 28; two mutants RED); `agnos_abi_doc_parity` reads #110 shared. Fake kernel only — cyrius has no agnos host. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — filed by agnos (2026-10-13). agnos has assigned and built the number in its 1.57.13 cut, where it is reviewed and gated. Do not mint it here before agnos's `1.57.13` tag.
**Placement:** 6.7.11 — repair 1, the stdlib lane — an agnos filing (pulled in at the open: user, 2026-10-13) — never 7.x. Was: `lib/syscalls_x86_64_agnos.cyr`. Put the constant and the two mode bits next to `SYS_WINSIZE = 60` (:118), and the wrapper `sys_console_mode()` next to `sys_winsize()` (:2301).
**Filed:** 2026-10-13, by agnos. agnos minted and built the number; cyrius owns the peer.
**Affects:** cyrius **6.7.10**. `#110` exists from agnos **1.57.13**.
**Severity:** **Low as a defect, blocking for the consumer.** darshana 1.3.0's `tty_echo_off` and `tty_flush_input` return -1 on agnos today, deliberately, because no call reaches the console mode.

## The ask

```
SYS_CONSOLE_MODE = 110;   # console_mode(set, clear) → the console's flags BEFORE the call / -1 (agnos 1.57.13)
CM_NOECHO = 1;            # a MODE: cooked-line reads of the console store and edit but echo nothing
CM_FLUSH  = 2;            # an ACTION (set only): discard typeahead + the NB reader's partial line
fn sys_console_mode(set, clear): i64 { return syscall(SYS_CONSOLE_MODE, set, clear); }
```

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2, row 110 — authoritative)

The new flags are `new = (old & ~clear) | set`. The call returns the flags as they were before it; `FLUSH` never appears in a return.

- **`CM_NOECHO`** — every cooked-line read of the console keeps storing and editing input, and backspace still erases, but nothing is echoed:
  - no printable byte;
  - no `BS SP BS`;
  - **no newline** (Linux `n_tty` with both ECHO and ECHONL clear).

  It applies to fd 0, 1, 2 or any console fd, blocking or non-blocking. After a hidden read, the program writes its own `\n`, as on Linux.
- **`CM_FLUSH`** — discards the typeahead in the kernel's key ring and the non-blocking reader's partial line (`tcflush(TCIFLUSH)`).
  - `NOECHO|FLUSH` in one call is `TCSETSF`.
  - It waits only while another live reader is in the middle of a line.
- **Any other bit, in `set` or `clear` (including `FLUSH` in `clear`), returns -1 with nothing changed.** So a program asking an older kernel for a mode it lacks gets -1, never a silent 0.
- **The mode belongs to the console, and is held by whoever set it.** The setter is the holder, and the mode dies with the holder on every death path: exit, fault, kill. A program that dies with echo off never leaves the console dark. Any process may clear it.
- **Shapes:**
  - `(0, 0)` is a query.
  - `(0, CM_NOECHO)` turns echo back on.

**darshana's mapping on agnos:**

| darshana call | console_mode call |
|---|---|
| `tty_echo_off` | `console_mode(CM_NOECHO \| CM_FLUSH, 0)` |
| `tty_flush_input` | `console_mode(CM_FLUSH, 0)` |
| restore | `console_mode(0, CM_NOECHO)` |

**Probe:** `#110(0, 0)` returns ≥ 0 on a supporting kernel and -1 before 1.57.13.

## Why it exists

These are agnos issue `2026-10-12-console-line-discipline-has-no-ring3-control` (from darshana 1.3.0) and agnos's roadmap row "`tcsetattr`/`ioctl` no-op stub — waiting on a consumer". The consumers are:
- **kybernet:** the emergency shell's password prompt (`_prompt_password`) logged "password will be VISIBLE" on agnos.
- **chakshu:** flushing typeahead before the kill confirmation.
- **shakti:** passphrase entry.

The call has a new number because, on this ABI, widening a live call's arity is not backward compatible.

## Compatibility

Nothing existing changes: this adds new constants and one function.

## Related

- **SIGWINCH (28), also new in agnos 1.57.13, needs no new syscall.** When the console grid actually changes, agnos posts bit 28 only to processes holding a signalfd whose mask includes it (darshana's `TTY_SIGMASK_WINCH`, `1 << 28`).
  - Nobody else gets it, because under agnos's "a signal is a bit, no default action" rule a stray pending bit would never be consumed.
  - If cyrius's agnos lib carries a signal-number table, `SIGWINCH = 28` belongs in it. Otherwise nothing is owed.
- agnos `docs/development/agnos-userland-abi.md` § 3.2 row 110, and the signal section for SIGWINCH.
- `2026-10-13-agnos-sys-sock-send-dl-109-peer.md` and `2026-10-13-agnos-sys-fd-kind-111-peer.md` — the other two numbers agnos 1.57.13 adds.
