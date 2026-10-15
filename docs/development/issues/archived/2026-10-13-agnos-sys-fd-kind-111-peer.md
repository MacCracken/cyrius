# `lib/syscalls_x86_64_agnos.cyr` has no `sys_fd_kind`#111 peer — RESOLVED

> ✅ **RESOLVED in v6.7.11** (LIB-5, `624ed9d9`; comments by the review fix `338fabc0`: `SYS_FD_KIND = 111` after `SYS_LSTAT`, `enum FdKind` (`FDK_CONSOLE = 1` … `FDK_DEVICE = 10`, as asked) and `fn sys_fd_kind(fd)` after `sys_lstat`. Per the contract the filing quotes, which wins over the ask's raw one-liner, the wrapper answers cyrius's own tagged sockets itself: `FDK_SOCKET` while the slot is open (reserved, connected or listening), -1 once it is free, with no kernel call. Every other fd, a negative one included, goes to #111. The doc comment names `sys_fd_kind(0) != -1` as the support probe. No decision needed (additive, to the contract). Rows: `agnos_peer_fake_kernel.sh` axis 11 (10 rows; the raw one-liner → 5 FAIL, a bit-test `_agnos_is_sock_fd` → 2 FAIL); `agnos_abi_doc_parity` 111 shared, 0 awaiting. Fake kernel only — cyrius has no agnos host. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — filed by agnos (2026-10-13). agnos has assigned and built the number in its 1.57.13 cut, where it is reviewed and gated. Do not mint it here before agnos's `1.57.13` tag.
**Placement:** 6.7.11 — repair 1, the stdlib lane — an agnos filing (pulled in at the open: user, 2026-10-13) — never 7.x. Was: `lib/syscalls_x86_64_agnos.cyr`. Put the `SysNrAgnos` constant and an `FdKind` enum next to `SYS_LSTAT = 102` (:97). Put `sys_fd_kind()` next to `sys_lstat()` (:1301).
**Filed:** 2026-10-13, by agnos. agnos minted and built the number; cyrius owns the peer.
**Affects:** cyrius **6.7.10**. `#111` exists from agnos **1.57.13**.
**Severity:** **Low as a defect, blocking for the consumer.** darshana's agnos `tty_isatty(fd)` can only answer for the console, not for the fd. So `prog > file` and `prog | other` get terminal escapes.

## The ask

```
SYS_FD_KIND = 111;   # fd_kind(fd) → kind (≥ 1) / -1 (agnos 1.57.13)
enum FdKind {
    FDK_CONSOLE = 1;  FDK_FILE = 2;  FDK_DIR = 3;  FDK_PIPE = 4;  FDK_CHAN = 5;
    FDK_SOCKET = 6;   FDK_SIGNALFD = 7;  FDK_EPOLL = 8;  FDK_TIMERFD = 9;  FDK_DEVICE = 10;
}
fn sys_fd_kind(fd): i64 { return syscall(SYS_FD_KIND, fd); }
```

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2, row 111 — authoritative)

`#111` answers `fstat`'s `st_mode & S_IFMT` and `isatty(3)`'s question in one register, for the caller's fd table.

| Kind | Value | What it is |
|---|---|---|
| CONSOLE | 1 | The console device. A `read` on any console fd is the cooked keyboard line, `#110`-aware. |
| FILE | 2 | A regular file on any backend: initrd and `/fonts`, ext2, FAT/exFAT, ZFS. |
| DIR | 3 | An `AO_DIRECTORY` fd. |
| PIPE | 4 | Either end of a pipe. |
| CHAN | 5 | A `#97` channel endpoint: the PTY band a terminal emulator hands its child. Whether that counts as a terminal is the caller's call. |
| SOCKET | 6 | A kernel `VFS_SOCK` fd. |
| SIGNALFD | 7 | |
| EPOLL | 8 | |
| TIMERFD | 9 | |
| DEVICE | 10 | Another character device. None is registered today. |

**It returns -1** for:
- a closed fd;
- `fd < 0` or `fd >= 32`;
- **cyrius's own tagged socket handle** (`AGNOS_SOCK_TAG` `0x40000000 | slot`). That handle is a userland adapter over conn ids, not a kernel fd. A cyrius-side `isatty` or `fd_kind` wrapper should answer for its own sockets first (`_agnos_is_sock_fd`) and call `#111` only for real fds.

agnos uses its own enum rather than `S_IFMT` values because POSIX folds a channel endpoint and the three event fds into kinds that cannot be told apart.

**Probe:** call `#111` on an fd you KNOW is open. It answers ≥ 1 on a supporting kernel and -1 before 1.57.13. `#111(0) != -1` is the support test, not `== 1`, because fd 0 is 4 when stdin is a pipe and 2 when it is a file.

**darshana's mapping on agnos:** `tty_isatty(fd)` is `fd_kind(fd) == FDK_CONSOLE`.

## Why it exists

This is agnos issue `2026-10-12-no-way-to-ask-what-an-fd-is` (from darshana 1.3.0). darshana's agnos `tty_isatty` has answered "is the console up" via `winsize`#60 since v0.9.0.

## Compatibility

Nothing existing changes: this adds new constants and one function.

## Related

- agnos `docs/development/agnos-userland-abi.md` § 3.2 row 111 — the authoritative contract.
- `2026-10-13-agnos-sys-sock-send-dl-109-peer.md` and `2026-10-13-agnos-sys-console-mode-110-peer.md` — the other two numbers agnos 1.57.13 adds.
