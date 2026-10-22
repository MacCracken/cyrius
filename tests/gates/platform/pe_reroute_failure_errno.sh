#!/bin/sh
# 6.7.14 — a FAILED ReadFile / WriteFile / SetFilePointerEx / CreateFileW answers a negative errno
# on PE, through ONE GetLastError table (issues/archived/2026-10-15-pe-read-failure-reads-as-eof.md,
# 2026-10-15-pe-open-failure-is-always-minus-one.md, 2026-10-16-pe-lseek-failed-seek-returns-zero.md).
#
# ⛔ WHY: the four kernel32 file reroutes (src/backend/x86/emit.cyr) returned their success answer
# without reading the failure: EREAD_PE / EWRITE_PE the byte count ReadFile / WriteFile zero before
# they fail (a failed read read as END OF FILE, a failed write as 0 bytes written), ELSEEK_PE its
# pre-zeroed output slot (a failed seek read as a seek to 0, and the next write landed at the old
# position), EOPEN_PE CreateFileW's -1 (never -ENOENT, so never IoNotFound). Now each keeps its
# success answer and on failure calls a shared stub that calls GetLastError and maps the Win32
# code; ReadFile's own stub keeps ERROR_BROKEN_PIPE (109) and ERROR_HANDLE_EOF (38) as 0, the end,
# and ERROR_MORE_DATA (234) as the count.
#
# THE AXES
#   axis 1  POSIX ORACLE (always): the four crossos .tcyr — pe_read_write_failure_errno,
#           pe_open_failure_errno, lseek_failed_seek, close_answer (6.7.15) — run natively at 0
#           failed over their floors.
#           Their expected values are Linux's, not a table this gate and the emitter made up.
#   axis 2  EMITTER SHAPE (objdump): a probe with a literal read / write / open / seek / close
#           and a var-held syscall number (EPE_SYSCALL_DYNAMIC's argc-4 switch, which emits all four
#           again, and its argc-2 one, which emits the close) builds for PE. EVERY call through the
#           ReadFile / WriteFile / SetFilePointerEx IAT slot is followed by `test %eax,%eax; mov
#           <answer>; jne +5; call <stub>`, every CreateFileW call by `cmp $-1,%rax; jne +5; call
#           <stub>`, every CloseHandle call by `test %eax,%eax; je; xor %eax,%eax; jmp; call
#           <stub>`; ReadFile's go to the read stub, the other four to the table; at least 2 sites
#           of each (anti-vacuous).
#   axis 3  THE TABLE (objdump, the same build): the table stub aligns (`sub $0x28,%rsp`), calls
#           through GetLastError's IAT slot, and its `mov $errno,%edx` / `cmp $code,%ecx; cmove`
#           rows map EXACTLY the documented Win32 codes (TABLE below), then `neg %rax; ret`; the
#           read stub calls the table and then maps 109 and 38 to 0 and 234 to the count it parked.
#           CI has no wine: this axis is what pins the mapping there.
#   axis 4  BEHAVIOUR under wine (skipped without wine — NOT hardware; the cass cross-OS leg runs
#           the same .tcyr): the four filed repros, verbatim (exit 91; exit 2; `-22 4 -22 4`; the
#           close's exit 91, 6.7.15), and
#           the four .tcyr's PE builds at 0 failed over their floors.
#   axis 5  STATIC, lib/io.cyr: Windows' CREATE_NEW over an existing DIRECTORY answers
#           ERROR_ACCESS_DENIED (-13) on real Windows — wine says ERROR_FILE_EXISTS, so no wine run
#           can see it — and file_create_exclusive's and _io_tmp_taken's CYRIUS_TARGET_WIN arms must
#           classify a -13 by asking the name (`== 0 - 13`), or file_create_exclusive(dir) is -13
#           and an atomic write fails at a planted directory instead of moving on (measured on cass:
#           pe_open_failure_errno and atomic_write_temp_exclusive red). Since 6.7.16 (D95) sys_open
#           answers that -13 with -17 itself; the two arms stay as the backstop for a refusal of an
#           existing name that is no directory, and this axis keeps reading them.
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-10-16 (6.7.14 platform lane, P1; x86_64 Linux
# + wine 11.19; CYCC=<mutant cycc> for the compiler rows):
#   mutant                                                  result
#   the pre-fix compiler + lib (2600f67f)                   axes 2, 4, 5 FAIL (no GetLastError import,
#                                                           so axis 3 has no stub to read)
#   _pe_w32_read_rows' 109 row dropped                      axis 3 FAIL; axis 4 FAIL (the pipe-drain
#                                                           row: -32, wine answers ERROR_BROKEN_PIPE)
#   the table's 131 (ERROR_NEGATIVE_SEEK) row dropped       axis 3 FAIL; axis 4 FAIL (lseek -1 4 -1 4)
#   EOPEN_PE's `cmp rax,-1` / stub call dropped             axes 2, 4 FAIL
#   main.cyr's EPE_ERRNO_STUBS call dropped                 axes 2, 4 FAIL (every PE build stops:
#                                                           FIXUP's drained assert names the driver)
#   lib/io.cyr's Windows arms back to `== 0 - 1`            axis 5 FAIL (axis 4 PASSES: wine)
# 6.7.15 — CloseHandle joins the class (issues/archived/2026-10-16-pe-close-returns-closehandle-bool.md):
# ECLOSE_PE handed back CloseHandle's BOOL, so a good close answered 1 and a failed one 0 (the
# filed repro exited 110, Linux 91; file_close_r was never Err). It answers 0, or -errno through
# the same table stub. Axis 1 and axis 4 run tests/tcyr/crossos/close_answer.tcyr; axis 2's probe
# has a literal and a var-held close, and every CloseHandle IAT call must be followed by
# `test %eax,%eax; je; xor %eax,%eax; jmp; call <the table stub>`.
#   mutant (2026-10-18, 6.7.15 platform lane, P2)             result
#   the pre-fix compiler (b2e1f4c48: _pe_srw_call_1arg)     axis 2 FAIL (the CloseHandle sites have no
#                                                           failure check); axis 4 FAIL (the close repro
#                                                           exits 110, close_answer 4 passed 9 failed)
#   ECLOSE_PE's `xor eax,eax` dropped (TRUE answers the BOOL 1)  axis 2 FAIL; axis 4 FAIL
# 6.7.16 — fd 0 / 1 / 2 reach the std handles in a close and a truncate
# (issues/archived/2026-10-18-pe-close-and-ftruncate-pass-std-fds-raw.md; 6.7.16's D30, "close it, as Linux
# does"). ECLOSE_PE and ESETEOF_PE put the fd straight into rcx, so CloseHandle / SetEndOfFile got
# the HANDLE values 0 / 1 / 2: `sys_close(2)` answered -9 and stderr stayed open (the filed repro
# printed `-9 1` on cass and wine, Linux `0 -9`), and `sys_ftruncate(1, 3)` of a redirected stdout
# answered -1 (exit 99, Linux 100). A close of fd 0 / 1 / 2 now calls the shared std-close stub —
# GetStdHandle; 0 or INVALID_HANDLE_VALUE (not open, or closed already) is -9; SetStdHandle(n,
# INVALID_HANDLE_VALUE), so a later CreateFileW cannot be handed the closed value and receive fd 2's
# writes; CloseHandle only when no other std slot holds the same HANDLE (lib/process_win.cyr gives a
# child ONE pipe as stdout and stderr) — and SetEndOfFile maps the fd through `_pe_fd_to_handle_rcx`.
# Measured on cass (2026-10-19): a ConPTY console, sshd's pipes and cmd's redirects (`2>&1` too) give
# three distinct std handles; CloseHandle(INVALID_HANDLE_VALUE) answers TRUE (the current-process
# pseudo-handle), which is why the stub answers -9 itself. Rows: axis 1 runs the two filed repros,
# a second close and the one-handle child natively; axis 2's probe adds a literal std close and a
# SetEndOfFile, and every CloseHandle call is either a site's fd > 2 arm (`cmp $0x2,%rax; ja; call
# <std-close stub>; jmp; mov %rax,%rcx`, the `ja` a `jg` since D78, below) or the stub's own, whose
# body must read GetStdHandle, the -9 arm, SetStdHandle(.., -1), the GetStdHandle loop comparing
# each slot with the HANDLE, then CloseHandle; every SetEndOfFile call follows the std-fd map;
# axis 4 runs the same rows under wine
# plus a reuse row (after the close a file is opened and fd 2 written: -9, the file stays empty —
# Linux answers 1 there, its open reuses fd 2, so that row is PE-only). ⚠ wine's std handle for a
# Unix-side redirect refuses SetEndOfFile (ERROR_INVALID_HANDLE, measured with a zig-built probe), so
# the truncate repro runs under wine's cmd, whose redirect is a real file handle, as cmd's is on cass.
#   mutant (2026-10-19, 6.7.16 platform lane, P1; wine 11.20)  result
#   the pre-fix compiler (480de63eb)                        axis 2 FAIL (no SetStdHandle import); axis 4
#                                                           FAIL (`-9 1` with 'x'; truncate 99 abcdefgh;
#                                                           close2 `-9 -9`; child `2 oe / -9 1 1`)
#   ECLOSE_PE's std arm dropped (`ja` -> `jmp`: raw value)  axis 2 FAIL (CloseHandle not behind the
#                                                           test); axis 4 FAIL (the old answers)
#   the stub's `cmp rax, rsi` never equal (always closes)   axis 2 FAIL (7/13); axis 4 FAIL (the child's
#                                                           stdout closed with stderr: `0 / 0 -9 -9`)
#   the stub's SetStdHandle call NOPped                     axis 2 FAIL (5/13); axis 4 FAIL (the loop
#                                                           finds the HANDLE in its own slot: never
#                                                           closed, `0 1` with 'x', close2 `0 0`)
#   the stub's -9 arm dropped (`ja` -> `jmp`)               axis 2 FAIL (2/13); axis 4 FAIL (close2
#                                                           `0 0`: INVALID_HANDLE_VALUE matched its own
#                                                           cleared slot)
#   ESETEOF_PE's map back to `mov rcx, rax`                 axis 2 FAIL (SE BAD); axis 4 FAIL (99)
# 6.7.16 — a NEGATIVE fd answers -9 in a close (issues/2026-10-19-pe-close-of-negative-fd-closes-a-
# pseudo-handle.md; 6.7.16's D78, "-9, as Linux"). ECLOSE_PE's `cmp rax, 2; ja` was unsigned, so every
# negative fd reached CloseHandle as the HANDLE, and -1 / -2 are the current-process / -thread
# pseudo-handles, which CloseHandle "closes" with TRUE: the filed closeneg printed `0 0 0` on cass
# and wine (Linux `-9 -9 -9`). The compare is signed (`jg`), so a negative fd joins 0 / 1 / 2 in the
# std-close stub, which now opens `test %rax,%rax; js` to its -9 arm, before any Win32 call. Rows:
# axis 1 and axis 4 run closeneg (`-9 -9 -9`) and close_answer.tcyr's negative-fd group; axis 2 reads
# each close site's `cmp $0x2,%rax; jg` and the stub's leading `test %rax,%rax; js`.
#   mutant (2026-10-20, 6.7.16 p16 lane, PP1; wine 11.20)    result
#   ECLOSE_PE's `jg` back to `ja` (the stub keeps its js)   axis 2 FAIL (CH BAD: not behind the signed
#                                                           test); axis 4 FAIL (closeneg `0 0 0`;
#                                                           close_answer 13 passed 5 failed)
#   the stub's `js` never taken (`jo`)                      axis 2 FAIL (the stub matched 1/15); axis 4
#                                                           PASSES: GetStdHandle(-fd - 10) refuses every
#                                                           negative fd's slot, so the -9 arm answers it
#                                                           one Win32 call later — the js answers it
#                                                           before any, and axis 2 holds it
# 6.7.16 — a failed mkdir / unlink / rmdir / ftruncate / truncate answers -errno
# (issues/archived/2026-10-19-pe-mkdir-unlink-rmdir-answer-minus-one-for-every-failure.md; 6.7.16's D79,
# "Linux's negative errno, through the Windows error table", and D80, "-22, as Linux", for what
# ftruncate cannot truncate). `_pe_path_bool1` — CreateDirectoryW (83), DeleteFileW (87, 0xF035),
# RemoveDirectoryW (0xF03B) — ended `dec rax; sar rax, 63` and never read GetLastError, and
# ESETEOF_PE (0xF03F) answered the raw BOOL, which lib/syscalls_windows.cyr's sys_ftruncate turned
# into -1 at every failing step (sys_truncate too, for a failed open): the filed pathfail printed
# `0 -1 -1 -1 -1 0 0` on cass and wine (Linux `0 -17 -39 -2 -2 0 0`) and ftfail, stdout piped,
# `-1 -1 -1 -1` (Linux `-22 -9 -2 -9`). Each BOOL now goes through the table stub (`test %eax,%eax;
# je; xor %eax,%eax; jmp; call <table>`, ECLOSE_PE's shape, `_pe_bool_errno`); sys_ftruncate answers
# a failed step's errno, the seek check's -29 (a pipe or console) and SetEndOfFile's -13 (no write
# access) as -22. Rows: axis 1 and axis 4 run pathfail and ftfail (stdout a pipe) and
# path_failure_errno.tcyr; axis 2's probe adds a literal and a var-held mkdir and unlink, an 0xF035
# and an 0xF03B, and every CreateDirectoryW / DeleteFileW / RemoveDirectoryW / SetEndOfFile call
# must be followed by the table-stub shape. (A real O_APPEND descriptor's ftruncate is -22 on cass,
# where SetEndOfFile refuses FILE_APPEND_DATA; wine lets it truncate, so no row here pins it.)
#   mutant (2026-10-20, 6.7.16 p16 lane, PP1; wine 11.20)    result
#   the pre-fix tree (0ba98b3bf: compiler + lib)            axis 2 FAIL (no stub call after any of the
#                                                           four BOOLs); axis 4 FAIL (`0 -1 -1 -1 -1 0 0`,
#                                                           `-1 -1 -1 -1`, path_failure_errno 12 / 12;
#                                                           D78's rows too: `0 0 0`, close_answer 13 / 5)
#   `_pe_path_bool1`'s .fail call NOPped                    axis 2 FAIL (CreateDirectoryW / DeleteFileW /
#                                                           RemoveDirectoryW: no-stub-call); axis 4 FAIL
#                                                           (`0 0 0 0 0 0 0`; path_failure_errno 15 / 9)
#   ESETEOF_PE's map dropped (the raw BOOL, `mov eax,eax`)   axis 2 FAIL (SetEndOfFile: no-stub-call);
#                                                           axis 4 FAIL (the read-only row reads 0);
#                                                           pe_open_posix_semantics.sh RED too (its
#                                                           O_TRUNC verify reads the BOOL inverted)
#   sys_ftruncate's -29 / -13 -> -22 map dropped (lib)      axis 4 FAIL (ftfail `-29 -9 -2 -9`); on cass
#                                                           path_failure_errno's read-only row reads -13
#                                                           (wine answers that SetEndOfFile -22 itself)
# The null device (the p16 review): ftruncate of NUL opened O_WRONLY, and truncate("NUL"), are -22, as
# Linux's of /dev/null. Real Windows' SetEndOfFile fails it ERROR_INVALID_FUNCTION, which the table
# leaves -1 (sys_ftruncate maps that -1 to -22); wine's says ERROR_INVALID_HANDLE on the handle both
# seeks just accepted (sys_ftruncate maps that step's -9 to -22). path_failure_errno.tcyr pins both.
#   mutant (2026-10-20, 6.7.16 p16 review fix; wine 11.20)   result
#   SetEndOfFile's -9 -> -22 dropped (lib)                  axis 4 FAIL (path_failure_errno 25 / 2 under
#                                                           wine: the null-device rows read -9); cass 27 / 27
#   _win_ftrunc_err's -1 -> -22 dropped (lib)               wine 27 / 27 (wine never answers -1 there);
#                                                           on cass path_failure_errno 25 / 2 (-1, -1)
# 6.7.16 — an fd with a LOW BIT set is no descriptor (issues/2026-10-20-pe-fd-not-multiple-of-four-
# aliases-the-handle-below-it.md; Linux answers -9, which is what the source says). The NT kernel
# ignores a HANDLE value's two low bits, so fd `h + 1` / `h + 2` / `h + 3` reached CloseHandle /
# ReadFile / WriteFile / SetFilePointerEx / FlushFileBuffers / SetEndOfFile as the live `h`: the
# filed alias printed `52 0 -9 -9` under wine and `244 0 -9 -9` on cass (Linux `3 -9 3 0` — the
# close of h + 3 closed h). `_pe_fd_to_handle_rcx`'s fd > 2 arm opens `test $0x3,%al; jne .bad`, and
# each of its five callers lands .bad on `push $-9; pop %rax` behind a `jmp` over it; the close site
# sends a low-bit fd to the std-close stub (`cmp $0x2,%rax; jle; test $0x3,%al; je .direct`), whose
# leading compare is the unsigned `cmp $0x2,%rax; ja` to its -9 arm. Rows: axis 1 and axis 4 run the
# filed alias (its h, then `-9 3 0`) and tests/tcyr/crossos/unopened_fd_ebadf.tcyr; axis 2 requires
# the guard before EVERY ReadFile / WriteFile / SetFilePointerEx / FlushFileBuffers / SetEndOfFile
# call of the probe (literal and var-held) and reads the close site's and the stub's new compares.
#   mutant (2026-10-20, 6.7.16 pw lane, PW1; wine 11.20)     result
#   the pre-fix compiler (450ecf2c9)                        axis 2 FAIL (CH BAD: the close site's jg; no
#                                                           low-bit test before ReadFile); axis 4 FAIL
#                                                           (alias `52 0 -9 -9`; unopened_fd_ebadf 17 / 15)
#   the helper's `jnz .bad` never taken (`jo`)              axis 2 FAIL (FG BAD); axis 4 FAIL
#                                                           (unopened_fd_ebadf 12 / 20); the alias row
#                                                           PASSES: the close site has its own test
#   the close site's `je .direct` always taken (`jmp`)      axis 2 FAIL (CH BAD); axis 4 FAIL (alias
#                                                           `52 0 -9 -9`; unopened_fd_ebadf 25 / 7)
#   the stub's leading `ja` never taken (`jo`)              axis 2 FAIL (the stub matched 3/15); axis 4
#                                                           PASSES: GetStdHandle(-fd - 10) refuses the
#                                                           slot, so the -9 arm answers one Win32 call
#                                                           later — axis 2 holds the before-any-call rule
# The same value reached Winsock and kernel32's lock / final-path calls through the stdlib wrappers
# that hand an fd to a raw handle reroute (measured on cass: closesocket(s + 3) closed the socket s
# and answered 0, getsockname / listen of s + 1 acted on s; wine the same). Each answers -9 first
# (`_win_fd_aliases`, lib/syscalls_windows.cyr): the socket calls there and fd_wait_ready, lib/net.cyr's
# Winsock primitives, xflock's Windows arm, lib/tls_native_conn.cyr's and lib/async_win.cyr's
# transport leaves and reactor tasks, and win_handle_under (-1, its "cannot" answer).
#   axis 6  STATIC, the stdlib: every `syscall(<a raw handle reroute>, fd, ..)` in a non-fold lib/
#           file is preceded IN ITS fn by `_win_fd_aliases(fd)` (SetEndOfFile's 0xF03F excepted: the
#           emitter's fd map guards it), and the ctx-held sockets of async_win.cyr's three reactor
#           tasks and win_handle_under's two handles are asked too; floor 24 guarded calls.
#   axis 4 also runs a Windows-only probe of the private leaves (wrapalias: _tn_os_read /
#   _tn_os_write / _tn_nb_on / async_relay_once of s + k, win_handle_under of h + 1 and of root + 2):
#   `-9 -9 -9 -9 1 -1 -1` (the pre-fix lib: `-10057 -10054 0 -10057 1 1 1` — s itself was read,
#   written, made non-blocking, and h + 1 named h's path).
#   mutant (2026-10-20, 6.7.16 pw lane, PW1; wine 11.20)     result
#   the pre-fix lib (450ecf2c9's six files)                 axis 6 FAIL; axis 4 FAIL (wrapalias as
#                                                           above; unopened_fd_ebadf no summary, exit
#                                                           124: after its xflock and socket rows fail,
#                                                           sock_recv(s + 3) blocks on the socket that
#                                                           listen(s + 1) made listen)
#   _net_os_close's guard dropped                           axis 6 FAIL (net.cyr:_net_os_close); axis 4
#                                                           FAIL (unopened_fd_ebadf 51 / 2: sock_close
#                                                           (s + 3) answers 0 and s is gone, -10038)
#   _tn_os_read's guard dropped                             axis 6 FAIL; axis 4 FAIL (wrapalias
#                                                           `-10057 -9 -9 -9 1 -1 -1`)
# 6.7.16 — rename / symlink / fsync answer -errno too (issues/2026-10-20-pe-rename-symlink-fsync-
# answer-minus-one-for-every-failure.md; 6.7.16's D94, "Yes, extend D79"). EMOVEFILEEX_PE folded
# MoveFileExW's BOOL with `dec; sar`, ESYMLINKW_PE handed back CreateSymbolicLinkW's BOOLEAN (which
# sys_symlink folded to -1) and EFLUSHFB_PE folded FlushFileBuffers' with `cmp; sbb`: the filed rsfail
# printed `-1 -1 -1` on cass and wine (Linux `-2 -2 -9`). Each FALSE now goes through the table stub
# (`_pe_bool_errno`, inside the frame; CreateSymbolicLinkW's BOOLEAN `movzbl %al,%eax` first), and
# the raw 0xF03E answers 0 / -errno (sys_symlink tests `== 0`). Rows: axis 1 and axis 4 run rsfail
# verbatim and path_failure_errno.tcyr's rename / link / fsync group; axis 2's probe adds a literal
# rename (0xF034), link (0xF03E) and fsync (74), and every MoveFileExW / CreateSymbolicLinkW /
# FlushFileBuffers call must be followed by the table-stub shape.
#   mutant (2026-10-20, 6.7.16 pw lane, PW1; wine 11.20)     result
#   the pre-fix tree (450ecf2c9: compiler + lib)            axis 4 FAIL (path_failure_errno 30 / 7:
#                                                           every rename / link / fsync row -1)
#   EMOVEFILEEX_PE's map back to `dec; sar` (after unframe) axis 2 FAIL (a MoveFileExW call without
#                                                           the table-stub shape); axis 4 FAIL (rsfail
#                                                           `-1 -2 -9`; path_failure_errno 35 / 2)
#   ESYMLINKW_PE's map dropped (the BOOLEAN answered)       axis 2 FAIL (CreateSymbolicLinkW, the
#                                                           same); axis 4 FAIL (rsfail `-2 0 -9`: a
#                                                           failed link reads as made; 35 / 2)
#   EFLUSHFB_PE's map back to `cmp; sbb`                    axis 2 FAIL (FlushFileBuffers, the same);
#                                                           axis 4 FAIL (path_failure_errno 35 / 2:
#                                                           the closed-fd and read-only rows -1)
# The pw review: sys_symlink retried CreateSymbolicLinkW without ALLOW_UNPRIVILEGED_CREATE on EVERY
# failure, and the flagless call fails ERROR_PRIVILEGE_NOT_HELD (-1) in any non-elevated process, so
# the flagged call's -2 / -17 read -1 there: on cass under `runas /trustlevel:0x20000` (a Basic User
# token; Developer Mode off) rsfail printed `-2 -1 -9`. The retry is reached only on -22 now
# (ERROR_INVALID_PARAMETER, a Windows older than 10 1703, which does not know the flag). Wine ignores
# the privilege and the cass leg runs elevated, so axis 5 reads sys_symlink statically (two 61502
# calls, the second behind `if (r != 0 - 22) { return r; }`); path_failure_errno.tcyr's
# missing-directory and existing-name link rows run elevated or not (only the made-link rows skip).
#   mutant (2026-10-20, 6.7.16 pw review fix; wine 11.20, cass) result
#   the retry on any failure (`if (r == 0) { return 0; }`,  axis 5 FAIL (67 / 1); axis 4 PASSES (wine).
#   as b67ed7b83)                                           On cass, Basic User token: rsfail `-2 -1 -9`,
#                                                           path_failure_errno 46 / 2 (the fix: `-2 -2
#                                                           -9`, 48 / 0; elevated, both 50 / 0)
# 6.7.16 — a DIRECTORY answers EISDIR (issues/2026-10-20-pe-unlink-truncate-open-of-a-directory-
# answer-eacces-not-eisdir.md; 6.7.16's D95, "-21 as Linux"). CreateFileW and DeleteFileW refuse a
# directory ERROR_ACCESS_DENIED, which the table maps to -13: the filed dirfail printed `-13 -13 -13
# -13` on cass and wine (Linux `-21 -21 -21 -21`). lib/syscalls_windows.cyr asks the name on a -13
# (GetFileAttributesW, 6.7.14's file_create_exclusive shape): sys_open's write / create / truncate
# opens of a directory are -21 (an O_CREAT|O_EXCL one -17, Linux's EEXIST), sys_unlink's and
# xunlink's -21, sys_truncate opens through sys_open; anything that is no directory keeps -13.
#   axis 5 also reads those arms statically (CI has no wine).
#   mutant (2026-10-20, 6.7.16 pw lane, PW1; wine 11.20)     result
#   the pre-fix lib (2cd5ab993's syscalls_windows / io)      axis 5 FAIL; axis 4 FAIL (dirfail `-13 -13
#                                                           -13 -13`; path_failure_errno 42 / 7)
#   `_win_is_dir` never a directory (`return 0`)            axis 4 FAIL (dirfail `-13 -13 -13 -13`;
#                                                           path_failure_errno 42 / 7); axis 5 PASSES:
#                                                           the arms are there — behaviour is axis 4's
#   `_win_is_dir` always a directory (every -13 is -21)     axis 4 FAIL (path_failure_errno 48 / 1:
#                                                           the held-open file's -13 reads -21)
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.14] [6.7.15] [6.7.16]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: pe_reroute_failure_errno: build/cycc missing"; exit 77; }
IO="$ROOT/lib/io.cyr"
T1="$ROOT/tests/tcyr/crossos/pe_read_write_failure_errno.tcyr"
T2="$ROOT/tests/tcyr/crossos/pe_open_failure_errno.tcyr"
T3="$ROOT/tests/tcyr/crossos/lseek_failed_seek.tcyr"
T4="$ROOT/tests/tcyr/crossos/close_answer.tcyr"
T5="$ROOT/tests/tcyr/crossos/path_failure_errno.tcyr"
T6="$ROOT/tests/tcyr/crossos/unopened_fd_ebadf.tcyr"
for f in "$IO" "$T1" "$T2" "$T3" "$T4" "$T5" "$T6"; do
    [ -f "$f" ] || { echo "FAIL: pe_reroute_failure_errno: $f is missing"; exit 1; }
done
# Row floors, as measured at 6.7.14 (each .tcyr runs every row on every target it counts); T5's and
# T6's at 6.7.16.
F1=10; F2=10; F3=13; F4=13; F5=50; F6=53
# Win32 code:errno, sorted by code — the table src/backend/x86/emit.cyr's _pe_w32_errno_rows_a/_b emit.
TABLE="2:2 3:2 5:13 6:9 8:12 14:12 15:2 32:13 33:13 80:17 87:22 109:32 112:28 123:2 131:22 145:39 161:2 183:17 206:36 232:32 267:20"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_reroute_failure_errno: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache. The EXIT teardown stops THIS prefix's wineserver and removes its server
# dir, which `wineserver -k` leaves behind (the pe_last_error_reroute.sh shape). CHANGELOG [6.6.17]
WP="$D/wp"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT INT TERM

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }
# "<passed> <failed>" from a run's summary line, or empty.
summary() { tr -d '\r' < "$1" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' | tail -1; }

# axis 1: the POSIX oracle.
mkdir -p "$D/n"
for pair in "$T1:$F1" "$T2:$F2" "$T3:$F3" "$T4:$F4" "$T5:$F5" "$T6:$F6"; do
    t=${pair%:*}; fl=${pair##*:}; b=$(basename "$t" .tcyr)
    ( cd "$ROOT" && "$CC" < "$t" > "$D/n/$b" 2> "$D/n/$b.err" ) || true
    if [ ! -s "$D/n/$b" ]; then
        bad "axis 1: the native build of $b.tcyr produced no binary: $(grep -m2 '^error' "$D/n/$b.err" | tr '\n' ' ')"
        continue
    fi
    chmod +x "$D/n/$b"
    nrc=0; ( cd "$D/n" && ulimit -c 0; "./$b" > "$b.out" 2>&1 ) || nrc=$?
    sum=$(summary "$D/n/$b.out"); np=${sum% *}; nf=${sum#* }
    if [ -z "$sum" ] || [ "$nrc" != 0 ] || [ "$nf" != 0 ] || [ "$np" -lt "$fl" ]; then
        bad "axis 1: $b.tcyr natively: '${sum:-no summary}' (exit $nrc, floor $fl)"
        tr -d '\r' < "$D/n/$b.out" | grep -m4 'FAIL:' | sed 's/^/      /'
    else ok; fi
done

# 6.7.16 — the std-fd close and truncate probes. The two filed repros, verbatim (closestd, trstd);
# a second close of the same std fd (close2: Linux `0 -9`); a child whose stdout and stderr are ONE
# handle on Windows (clsh_child, started by clsh_parent through exec_capture: Linux and Windows
# alike, the child's close(2) leaves its stdout writing — `1 o` captured, the child reports `0 1 -9`);
# and, PE-only, the reuse row (clreuse: after the close a file is opened and fd 2 written).
line() { tr -d '\r' < "$1" | tr '\n' ' ' | sed 's/ *$//'; }
cat > "$D/closestd.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var c = sys_close(2);         # close stderr
var w = file_write(2, "x", 1); # a write to the closed fd
fmt_int(c); println("");
fmt_int(w); println("");
EOF
cat > "$D/trstd.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
file_write(1, "abcdefgh", 8);
var t = sys_ftruncate(1, 3);  # stdout redirected to a file
syscall(SYS_EXIT, 100 + t);   # Linux 100 (0); a failure 99 (-1)
EOF
cat > "$D/close2.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var c1 = sys_close(2);        # stderr: closed
var c2 = sys_close(2);        # not open any more: -EBADF
fmt_int(c1); println("");
fmt_int(c2); println("");
EOF
cat > "$D/clsh_child.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var c = sys_close(2);              # stderr — on Windows the SAME handle as stdout here
var w1 = file_write(1, "o", 1);    # stdout must still write
var w2 = file_write(2, "e", 1);    # the closed fd fails EBADF
var fd = file_open("clsh.txt", O_WRONLY | O_CREAT | O_TRUNC, 420);
fmt_int_fd(fd, c); file_write(fd, " ", 1);
fmt_int_fd(fd, w1); file_write(fd, " ", 1);
fmt_int_fd(fd, w2); file_write(fd, "\n", 1);
file_close(fd);
EOF
# $1 = the child as exec_capture is given it
clsh_parent() { cat <<EOF
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/process.cyr"
alloc_init();
var args = vec_new();
vec_push(args, "$1");
var buf[64];
var n = exec_capture(args, &buf, 64);
fmt_int(n); file_write(1, " ", 1);
if (n > 0) { file_write(1, &buf, n); }
println("");
EOF
}
cat > "$D/clreuse.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var c = sys_close(2);
var fd = file_open("clreuse.tmp", O_WRONLY | O_CREAT | O_TRUNC, 420);
var w = file_write(2, "x", 1);    # PE: -9, never into clreuse.tmp
file_close(fd);
var buf[8];
var rd = file_open("clreuse.tmp", O_RDONLY, 0);
var n = file_read(rd, &buf, 8);
file_close(rd);
fmt_int(c); println("");
fmt_int(w); println("");
fmt_int(n); println("");
EOF

# 6.7.16's D78: a negative fd is no descriptor (the filed repro, verbatim).
cat > "$D/closeneg.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var a = sys_close(0 - 1);     # not a descriptor: Linux -9
var b = sys_close(0 - 2);     # not a descriptor: Linux -9
var c = file_close(0 - 1);    # the same through lib/io.cyr
fmt_int(a); println("");
fmt_int(b); println("");
fmt_int(c); println("");
EOF

# 6.7.16: an fd beside an open one, never opened itself (the filed alias, verbatim). It prints h,
# then the close of h + 3, the write to h and the close of h: Linux `-9 3 0`.
cat > "$D/alias.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
var h = sys_open("alias_probe.txt", 577, 420);
p(h);
p(sys_close(h + 3));          # never opened as an fd: Linux -9
p(sys_write(h, "abc", 3));    # the file's own fd: Linux 3
p(sys_close(h));              # Linux 0
sys_unlink("alias_probe.txt");
println("");
EOF
# 6.7.16's D94: rename / symlink / fsync (the filed rsfail, verbatim; run in an empty directory).
cat > "$D/rsfail.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
var fd = sys_open("rs_t", 577, 420);
sys_close(fd);
p(file_rename("rs_missing", "rs_x"));          # rename of a missing path: Linux -2
p(xsymlink("rs_t", "rs_missing_dir/l"));       # link under a missing directory: Linux -2
p(xfsync(0 - 999));                            # fsync of a non-descriptor: Linux -9
println("");
sys_unlink("rs_t");
EOF
# 6.7.16's D95: a directory's unlink / truncate / open for writing (the filed dirfail, verbatim; run
# in an empty directory).
cat > "$D/dirfail.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
sys_rmdir("df_d");
sys_mkdir("df_d", 448);
p(sys_unlink("df_d"));                  # unlink of a directory: Linux -21
p(xunlink("df_d"));                     # the same through xunlink: Linux -21
p(sys_truncate("df_d", 1));             # truncate of a directory: Linux -21
p(file_open("df_d", O_WRONLY, 0));      # open of a directory for writing: Linux -21
println("");
sys_rmdir("df_d");
EOF
# "<h> -9 3 0" with h a descriptor above 2 (on PE a multiple of 4): the alias row's verdict.
alias_ok() {  # $1 = the output line, $2 = 4 on PE (h must be a multiple of 4), 1 natively
    set -- $1 "$2"
    [ $# = 5 ] || return 1
    [ "$2 $3 $4" = "-9 3 0" ] || return 1
    case "$1" in *[!0-9]*|'') return 1 ;; esac
    [ $(( $1 % $5 )) = 0 ] && [ "$1" -gt 2 ]
}

# 6.7.16's D79 / D80: the two filed repros, verbatim. pathfail runs in an empty directory; ftfail
# with stdout a pipe, and writes its answers to ft.out.
cat > "$D/pathfail.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
var out[256];
var on = 0;
fn pd(v): i64 {
    if (v < 0) { store8(&out + on, 45); on = on + 1; v = 0 - v; }
    var t[24];
    var n = 0;
    if (v == 0) { store8(&t, 48); n = 1; }
    while (v > 0) { store8(&t + n, 48 + v % 10); v = v / 10; n = n + 1; }
    while (n > 0) { n = n - 1; store8(&out + on, load8(&t + n)); on = on + 1; }
    store8(&out + on, 32); on = on + 1;
    return 0;
}
sys_rmdir("pf_d/f");
sys_unlink("pf_d/f");
sys_rmdir("pf_d");
pd(sys_mkdir("pf_d", 448));            # 0
pd(sys_mkdir("pf_d", 448));            # an existing directory: Linux -17
var fd = sys_open("pf_d/f", 577, 420);
sys_close(fd);
pd(sys_rmdir("pf_d"));                 # not empty: Linux -39
pd(sys_unlink("pf_missing"));          # Linux -2
pd(sys_rmdir("pf_missing"));           # Linux -2
pd(sys_unlink("pf_d/f"));              # 0
pd(sys_rmdir("pf_d"));                 # 0
store8(&out + on, 10); on = on + 1;
sys_write(1, &out, on);
sys_exit(0);
EOF
cat > "$D/ftfail.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
var out[256];
var on = 0;
fn pd(v): i64 {
    if (v < 0) { store8(&out + on, 45); on = on + 1; v = 0 - v; }
    var t[24];
    var n = 0;
    if (v == 0) { store8(&t, 48); n = 1; }
    while (v > 0) { store8(&t + n, 48 + v % 10); v = v / 10; n = n + 1; }
    while (n > 0) { n = n - 1; store8(&out + on, load8(&t + n)); on = on + 1; }
    store8(&out + on, 32); on = on + 1;
    return 0;
}
pd(sys_ftruncate(1, 3));              # stdout is a pipe: Linux -22
pd(sys_ftruncate(99, 3));             # an fd never opened: Linux -9
pd(sys_truncate("ft_missing", 3));    # no such file: Linux -2
sys_close(1);
pd(sys_ftruncate(1, 3));              # stdout closed: Linux -9
store8(&out + on, 10); on = on + 1;
var fd = sys_open("ft.out", 577, 420);
sys_write(fd, &out, on);
sys_close(fd);
sys_exit(0);
EOF

# axis 1, 6.7.16: the std-fd rows natively.
for p in closestd trstd close2 clsh_child closeneg pathfail ftfail alias rsfail dirfail; do
    ( cd "$ROOT" && "$CC" < "$D/$p.cyr" > "$D/n/$p" 2> "$D/n/$p.err" ) || true
    chmod +x "$D/n/$p" 2> /dev/null || true
done
clsh_parent "$D/n/clsh_child" > "$D/clsh_parent_n.cyr"
( cd "$ROOT" && "$CC" < "$D/clsh_parent_n.cyr" > "$D/n/clsh_parent" 2> "$D/n/clsh_parent.err" ) || true
chmod +x "$D/n/clsh_parent" 2> /dev/null || true
if [ ! -s "$D/n/closestd" ] || [ ! -s "$D/n/trstd" ] || [ ! -s "$D/n/close2" ] || [ ! -s "$D/n/clsh_child" ] || [ ! -s "$D/n/clsh_parent" ] || [ ! -s "$D/n/closeneg" ] || [ ! -s "$D/n/pathfail" ] || [ ! -s "$D/n/ftfail" ] || [ ! -s "$D/n/alias" ] || [ ! -s "$D/n/rsfail" ] || [ ! -s "$D/n/dirfail" ]; then
    bad "axis 1: a native build of the std-fd probes produced no binary: $(cat "$D/n/closestd.err" "$D/n/trstd.err" "$D/n/close2.err" "$D/n/clsh_child.err" "$D/n/clsh_parent.err" "$D/n/closeneg.err" "$D/n/pathfail.err" "$D/n/ftfail.err" "$D/n/alias.err" | grep -m2 '^error' | tr '\n' ' ')"
else
    ( cd "$D/n" && ulimit -c 0; ./closestd > cs.out 2> cs.err ) || true
    got=$(line "$D/n/cs.out")
    if [ "$got" = "0 -9" ] && [ ! -s "$D/n/cs.err" ]; then ok; else bad "axis 1: the close repro natively prints '$got' (want '0 -9', nothing on stderr)"; fi
    trc=0; ( cd "$D/n" && ulimit -c 0; ./trstd > tr.out ) || trc=$?
    if [ "$trc" = 100 ] && [ "$(cat "$D/n/tr.out")" = abc ]; then ok; else bad "axis 1: the truncate repro natively exits $trc with tr.out '$(cat "$D/n/tr.out")' (want 100, 'abc')"; fi
    ( cd "$D/n" && ulimit -c 0; ./close2 > c2.out 2> /dev/null ) || true
    got=$(line "$D/n/c2.out")
    if [ "$got" = "0 -9" ]; then ok; else bad "axis 1: a second close of fd 2 natively: '$got' (want '0 -9')"; fi
    ( cd "$D/n" && ulimit -c 0; ./clsh_parent > ps.out 2> /dev/null ) || true
    got="$(line "$D/n/ps.out") / $(line "$D/n/clsh.txt" 2> /dev/null)"
    if [ "$got" = "1 o / 0 1 -9" ]; then ok; else bad "axis 1: the child's close(2) natively: '$got' (want '1 o / 0 1 -9')"; fi
    ( cd "$D/n" && ulimit -c 0; ./closeneg > cn.out 2> /dev/null ) || true
    got=$(line "$D/n/cn.out")
    if [ "$got" = "-9 -9 -9" ]; then ok; else bad "axis 1: the negative-fd close repro natively: '$got' (want '-9 -9 -9')"; fi
    mkdir -p "$D/n/pf" "$D/n/ft"
    ( cd "$D/n/pf" && ulimit -c 0; ../pathfail > pf.out 2> /dev/null ) || true
    got=$(line "$D/n/pf/pf.out")
    if [ "$got" = "0 -17 -39 -2 -2 0 0" ]; then ok; else bad "axis 1: the path-failure repro natively: '$got' (want '0 -17 -39 -2 -2 0 0')"; fi
    ( cd "$D/n/ft" && ulimit -c 0; ../ftfail 2> /dev/null | cat > /dev/null ) || true
    got=$(line "$D/n/ft/ft.out" 2> /dev/null)
    if [ "$got" = "-22 -9 -2 -9" ]; then ok; else bad "axis 1: the truncate-failure repro (stdout a pipe) natively: '$got' (want '-22 -9 -2 -9')"; fi
    mkdir -p "$D/n/al"
    ( cd "$D/n/al" && ulimit -c 0; ../alias > al.out 2> /dev/null ) || true
    got=$(line "$D/n/al/al.out")
    if alias_ok "$got" 1; then ok; else bad "axis 1: the fd-alias repro natively: '$got' (want '<h> -9 3 0')"; fi
    mkdir -p "$D/n/rs"
    ( cd "$D/n/rs" && ulimit -c 0; ../rsfail > rs.out 2> /dev/null ) || true
    got=$(line "$D/n/rs/rs.out")
    if [ "$got" = "-2 -2 -9" ]; then ok; else bad "axis 1: the rename / symlink / fsync repro natively: '$got' (want '-2 -2 -9')"; fi
    mkdir -p "$D/n/df"
    ( cd "$D/n/df" && ulimit -c 0; ../dirfail > df.out 2> /dev/null ) || true
    got=$(line "$D/n/df/df.out")
    if [ "$got" = "-21 -21 -21 -21" ]; then ok; else bad "axis 1: the directory repro natively: '$got' (want '-21 -21 -21 -21')"; fi
fi

# axis 2, 6.7.16 (called from axis 2 below, after $D/dis, $D/imp, va and $CH are set): every
# CloseHandle call is a site's fd > 2 arm, behind the SIGNED `cmp $0x2,%rax; jle` and the low-bit
# `test $0x3,%al; je`, whose other arm (0 / 1 / 2, D78's negative fds and an fd with a low bit set)
# calls the std-close stub — or that stub's own call; the stub reads, in order, the unsigned
# `cmp $0x2,%rax; ja` (a negative or low-bit fd: -9), GetStdHandle, the -9 arm
# for 0 / INVALID_HANDLE_VALUE, SetStdHandle(.., -1), the GetStdHandle loop that compares every
# slot with the HANDLE (the one-handle child's stdout lives on that compare), then CloseHandle.
# Every SetEndOfFile call follows the std-fd map (`cmp $0x2,%rax`, then a GetStdHandle call).
_std_map_axis() {
    GS=$(va GetStdHandle); SS=$(va SetStdHandle); SE=$(va SetEndOfFile)
    if [ -z "$GS" ] || [ -z "$SS" ] || [ -z "$SE" ]; then
        bad "axis 2: the probe does not import GetStdHandle / SetStdHandle / SetEndOfFile ('$GS' '$SS' '$SE'): a close or truncate of fd 0 / 1 / 2 does not reach the std handles"
        return 0
    fi
    awk -F'\t' -v ch="$CH" -v gs="$GS" -v se="$SE" '
        NF >= 3 { n++; t[n] = $3 }
        function slot(x,   k) { k = x; if (k !~ /^call +\*0x[0-9a-f]+\(%rip\)/) return ""; sub(/.*# /, "", k); return k }
        function tgt(x,   k) { k = x; sub(/^call +/, "", k); sub(/ .*/, "", k); return k }
        END {
            for (i = 1; i <= n; i++) {
                s = slot(t[i])
                if (s == ch) {
                    if (t[i-1] ~ /^mov +%rsi,%rcx/) { print "CH stub -"; continue }
                    if (t[i-1] ~ /^mov +%rax,%rcx/ && t[i-2] ~ /^jmp / && t[i-3] ~ /^call +0x[0-9a-f]+/ && t[i-4] ~ /^je / && t[i-5] ~ /^test +\$0x3,%al/ && t[i-6] ~ /^jle / && t[i-7] ~ /^cmp +\$0x2,%rax/) { print "CH site " tgt(t[i-3]); continue }
                    print "CH BAD:not-behind-the-std-fd-test"; continue
                }
                if (s == se) {
                    g = 0
                    for (k = i - 1; k >= 1 && k >= i - 12; k--) if (slot(t[k]) != "") { g = k; break }
                    cm = 0
                    for (k = g - 1; k >= 1 && k >= g - 6; k--) if (t[k] ~ /^cmp +\$0x2,%rax/) cm = 1
                    if (g == 0 || slot(t[g]) != gs || cm == 0) print "SE BAD:no-std-fd-map-before-it"
                    else print "SE ok"
                }
            }
        }' "$D/dis" > "$D/stdmap"
    cs=$(awk '$1 == "CH" && $2 == "site"' "$D/stdmap" | wc -l | tr -d ' ')
    cst=$(awk '$1 == "CH" && $2 == "stub"' "$D/stdmap" | wc -l | tr -d ' ')
    se_n=$(awk '$1 == "SE" && $2 == "ok"' "$D/stdmap" | wc -l | tr -d ' ')
    b=$(grep -m1 'BAD' "$D/stdmap" || true)
    C=$(awk '$1 == "CH" && $2 == "site" {print $3}' "$D/stdmap" | sort -u)
    if [ -n "$b" ]; then bad "axis 2: a CloseHandle / SetEndOfFile call is not reached through the std-fd map ($b)"
    elif [ "$cs" -lt 2 ] || [ "$cst" != 1 ] || [ "$se_n" -lt 1 ]; then
        bad "axis 2: $cs CloseHandle site(s) behind the std-fd test (floor 2: the literal and the var-held route), $cst in the std-close stub (want 1), $se_n SetEndOfFile site(s) after the map (floor 1)"
    elif [ "$(printf '%s\n' "$C" | wc -l | tr -d ' ')" != 1 ]; then
        bad "axis 2: the close sites must share ONE std-close stub ($(echo $C))"
    else
        ok
        awk -F'\t' -v at="$C" '
            { a = $1; sub(/^ +/, "", a); sub(/:$/, "", a) }
            ("0x" a) == at { on = 1 }
            on && NF >= 3 { print $3 }
            on && $3 ~ /^ret/ { exit }' "$D/dis" > "$D/cstub"
        got=$(awk -v gs="$GS" -v ss="$SS" -v ch="$CH" '
            function slot(x,   k) { k = x; if (k !~ /^call +\*0x[0-9a-f]+\(%rip\)/) return ""; sub(/.*# /, "", k); return k }
            BEGIN { np = split("^cmp +\\$0x2,%rax|^ja |G|^cmp +\\$0x1,%rax|^ja |^mov +\\$0xfffffffffffffff7,%rax|^mov +\\$0xffffffffffffffff,%rdx|S|G|^cmp +%rsi,%rax|^je |^cmp +\\$0xfffffff3,%edi|^jne |^mov +%rsi,%rcx|C", pat, "|"); k = 1 }
            k <= np {
                if (pat[k] == "G") { if (slot($0) == gs) k++ }
                else if (pat[k] == "S") { if (slot($0) == ss) k++ }
                else if (pat[k] == "C") { if (slot($0) == ch) k++ }
                else if ($0 ~ pat[k]) k++
            }
            END { print k - 1 "/" np }' "$D/cstub")
        case "$got" in
            15/15) ok ;;
            *) bad "axis 2: the std-close stub at $C does not read the negative-fd test, GetStdHandle, the -9 arm, SetStdHandle(.., -1), the slot-compare loop and CloseHandle in order (matched $got): $(tr '\n' ';' < "$D/cstub" | tr -s ' ')" ;;
        esac
    fi
}

# axis 2, 6.7.16 (called from axis 2 below): an fd with a low bit set is no descriptor. Every call
# through the ReadFile / WriteFile / SetFilePointerEx / FlushFileBuffers / SetEndOfFile IAT slot is
# reached from `_pe_fd_to_handle_rcx`'s fd > 2 arm, `test $0x3,%al; jne <bad>; mov %rax,%rcx`, at
# most 16 instructions before it, and <bad> is `push $0xfffffffffffffff7; pop %rax` with a `jmp`
# over it right before (the answered path never reads -9). Floors: each API at least twice (the
# literal and the var-held route; SetEndOfFile once).
_fd_guard_axis() {
    FB=$(va FlushFileBuffers)
    if [ -z "$FB" ]; then bad "axis 2: the probe does not import FlushFileBuffers (an fsync reroute)"; return 0; fi
    awk -F'\t' -v rf="$RF" -v wf="$WF" -v sf="$SF" -v fb="$FB" -v se="$SE" '
        NF >= 3 { n++; t[n] = $3; a = $1; sub(/^ +/, "", a); sub(/:$/, "", a); ad[n] = "0x" a; at["0x" a] = n }
        function slot(x,   k) { k = x; if (k !~ /^call +\*0x[0-9a-f]+\(%rip\)/) return ""; sub(/.*# /, "", k); return k }
        function tgt(x,   k) { k = x; sub(/^j[a-z]+ +/, "", k); sub(/ .*/, "", k); return k }
        END {
            for (i = 1; i <= n; i++) {
                s = slot(t[i]); api = ""
                if (s == rf) api = "ReadFile"; else if (s == wf) api = "WriteFile"
                else if (s == sf) api = "SetFilePointerEx"; else if (s == fb) api = "FlushFileBuffers"
                else if (s == se) api = "SetEndOfFile"
                if (api == "") continue
                g = 0
                for (k = i - 1; k >= 1 && k >= i - 16; k--) if (t[k] ~ /^test +\$0x3,%al/) { g = k; break }
                if (g == 0) { print "FG", api, "BAD:no-low-bit-test-before-it"; continue }
                if (t[g+1] !~ /^jne / || t[g+2] !~ /^mov +%rax,%rcx/ || t[g-1] !~ /^jmp /) { print "FG", api, "BAD:the-test-is-not-the-fd-map-arm"; continue }
                b = at[tgt(t[g+1])]
                if (b == "" || t[b] !~ /^push +\$0xfffffffffffffff7/ || t[b+1] !~ /^pop +%rax/) { print "FG", api, "BAD:jne-does-not-reach-push-minus-9-pop-rax"; continue }
                if (t[b-1] !~ /^jmp / || tgt(t[b-1]) != ad[b+2]) { print "FG", api, "BAD:no-jmp-over-the-minus-9"; continue }
                if (b <= i) { print "FG", api, "BAD:the-minus-9-is-before-the-call"; continue }
                print "FG", api, "ok"
            }
        }' "$D/dis" > "$D/fdguard"
    b=$(awk '$3 != "ok" {print $2 " " $3; exit}' "$D/fdguard")
    if [ -n "$b" ]; then bad "axis 2: an fd-taking call is not behind the low-bit guard ($b)"; return 0; fi
    for af in ReadFile:2 WriteFile:2 SetFilePointerEx:2 FlushFileBuffers:2 SetEndOfFile:1; do
        api=${af%:*}; fl=${af#*:}
        c=$(awk -v a="$api" '$2 == a' "$D/fdguard" | wc -l | tr -d ' ')
        if [ "$c" -lt "$fl" ]; then bad "axis 2: only $c $api site(s) behind the low-bit guard (floor $fl)"; return 0; fi
    done
    ok
}

# axis 2 + 3: the emitter shape and the table.
cat > "$D/shape.cyr" <<'EOF'
var buf[16];
fn by_number(nr, a, b, c): i64 { return syscall(nr, a, b, c); }
fn by_number1(nr, a): i64 { return syscall(nr, a); }
fn by_number2(nr, a, b): i64 { return syscall(nr, a, b); }
fn main(): i64 {
    var r = syscall(0, 0 - 999, &buf, 16);
    r = r + syscall(1, 0 - 999, &buf, 16);
    r = r + syscall(2, "no_such_shape_x", 0, 0);
    r = r + syscall(8, 0 - 999, 0, 0);
    r = r + syscall(3, 0 - 999);
    r = r + syscall(74, 0 - 999);
    r = r + syscall(61492, "no_such_shape_a", "no_such_shape_b");
    r = r + syscall(61502, "no_such_shape_l", "no_such_shape_t", 0);
    r = r + by_number(0, 0 - 999, &buf, 16);
    r = r + by_number1(3, 0 - 999);
    r = r + syscall(3, 2);
    r = r + syscall(61503, 1);
    r = r + syscall(83, "no_such_shape_d", 448);
    r = r + syscall(87, "no_such_shape_u");
    r = r + syscall(61493, "no_such_shape_u");
    r = r + syscall(61499, "no_such_shape_d");
    r = r + by_number1(87, "no_such_shape_u");
    r = r + by_number2(83, "no_such_shape_d", 448);
    return r;
}
var r = main();
syscall(60, r & 255);
EOF
CYRIUS_TARGET_WIN=1 "$CC" < "$D/shape.cyr" > "$D/shape.exe" 2> "$D/shape.err" || true
if [ ! -s "$D/shape.exe" ]; then
    bad "axis 2: the PE build of the shape probe produced no binary: $(grep -m2 'error' "$D/shape.err" | tr '\n' ' ')"
elif ! objdump -p "$D/shape.exe" > "$D/imp" 2>/dev/null || ! grep -q 'DLL Name' "$D/imp"; then
    echo "  SKIP: axes 2 and 3 (no objdump that reads PE)"
else
    objdump -dw "$D/shape.exe" > "$D/dis" 2>/dev/null
    va() { s=$(awk -v n="$1" '$NF == n {print $1; exit}' "$D/imp"); [ -n "$s" ] && printf '0x%x' $((0x140000000 + 0x$s)); }
    RF=$(va ReadFile); WF=$(va WriteFile); SF=$(va SetFilePointerEx); CF=$(va CreateFileW); GL=$(va GetLastError)
    CH=$(va CloseHandle)
    CD=$(va CreateDirectoryW); DF=$(va DeleteFileW); RD=$(va RemoveDirectoryW); SE=$(va SetEndOfFile)
    MV=$(va MoveFileExW); SL=$(va CreateSymbolicLinkW); FB=$(va FlushFileBuffers)
    if [ -z "$CD" ] || [ -z "$DF" ] || [ -z "$RD" ] || [ -z "$SE" ]; then
        bad "axis 2: the probe does not import CreateDirectoryW / DeleteFileW / RemoveDirectoryW / SetEndOfFile ('$CD' '$DF' '$RD' '$SE')"
    fi
    if [ -z "$MV" ] || [ -z "$SL" ] || [ -z "$FB" ]; then
        bad "axis 2: the probe does not import MoveFileExW / CreateSymbolicLinkW / FlushFileBuffers ('$MV' '$SL' '$FB')"
    fi
    if [ -z "$RF" ] || [ -z "$WF" ] || [ -z "$SF" ] || [ -z "$CF" ] || [ -z "$CH" ]; then
        bad "axis 2: the probe does not import ReadFile / WriteFile / SetFilePointerEx / CreateFileW / CloseHandle ('$RF' '$WF' '$SF' '$CF' '$CH')"
    elif [ -z "$GL" ]; then
        bad "axis 2: the probe does not import GetLastError — no failure reads it"
    else
        # Per IAT call site: "<api> <ok|BAD:why> <stub target>". Instruction text only (after the 2nd tab).
        awk -F'\t' -v rf="$RF" -v wf="$WF" -v sf="$SF" -v cf="$CF" -v ch="$CH" -v cd="$CD" -v df="$DF" -v rd="$RD" -v se="$SE" -v mv="$MV" -v sl="$SL" -v fb="$FB" '
            NF >= 3 { n++; t[n] = $3 }
            END {
                for (i = 1; i <= n; i++) {
                    if (t[i] !~ /^call +\*0x[0-9a-f]+\(%rip\)/) continue
                    k = t[i]; sub(/.*# /, "", k)
                    api = ""
                    if (k == rf) api = "ReadFile"; else if (k == wf) api = "WriteFile"
                    else if (k == sf) api = "SetFilePointerEx"; else if (k == cf) api = "CreateFileW"
                    else if (k == ch) api = "CloseHandle"
                    else if (k == cd) api = "CreateDirectoryW"; else if (k == df) api = "DeleteFileW"
                    else if (k == rd) api = "RemoveDirectoryW"; else if (k == se) api = "SetEndOfFile"
                    else if (k == mv) api = "MoveFileExW"; else if (k == sl) api = "CreateSymbolicLinkW"
                    else if (k == fb) api = "FlushFileBuffers"
                    if (api == "") continue
                    why = "ok"; j = i + 1
                    # 6.7.16 (D94): CreateSymbolicLinkW returns a one-byte BOOLEAN, widened first.
                    if (api == "CreateSymbolicLinkW") { if (t[j] !~ /^movzbl +%al,%eax/) why = "BAD:no-movzbl"; j++ }
                    if (api == "CloseHandle" || api == "CreateDirectoryW" || api == "DeleteFileW" || api == "RemoveDirectoryW" || api == "SetEndOfFile" || api == "MoveFileExW" || api == "CreateSymbolicLinkW" || api == "FlushFileBuffers") {
                        # test; je .fail; xor eax,eax (TRUE: 0); jmp .done; .fail: call <stub>
                        if (t[j] !~ /^test +%eax,%eax/) why = "BAD:no-test-eax"
                        j++
                        if (t[j] !~ /^je /) why = "BAD:no-je"
                        j++
                        if (t[j] !~ /^xor +%eax,%eax/) why = "BAD:no-xor-eax"
                        j++
                        if (t[j] !~ /^jmp /) why = "BAD:no-jmp"
                        j++
                        s = t[j]
                        if (s !~ /^call +0x[0-9a-f]+/) { why = "BAD:no-stub-call"; s = "-" } else { sub(/^call +/, "", s); sub(/ .*/, "", s) }
                        print api, why, s
                        continue
                    }
                    if (api == "CreateFileW") {
                        if (t[j] !~ /^cmp +\$0xffffffffffffffff,%rax/) why = "BAD:no-cmp-rax-minus-1"
                        j++
                    } else {
                        if (t[j] !~ /^test +%eax,%eax/) why = "BAD:no-test-eax"
                        j++
                        if (t[j] !~ /^mov +0x28\(%rsp\),%(e|r)ax/) why = "BAD:no-answer-load"
                        j++
                    }
                    if (t[j] !~ /^jne /) why = "BAD:no-jne"
                    j++
                    s = t[j]
                    if (s !~ /^call +0x[0-9a-f]+/) { why = "BAD:no-stub-call"; s = "-" } else { sub(/^call +/, "", s); sub(/ .*/, "", s) }
                    print api, why, s
                }
            }' "$D/dis" > "$D/sites"
        for api in ReadFile WriteFile SetFilePointerEx CreateFileW CloseHandle; do
            c=$(awk -v a="$api" '$1 == a' "$D/sites" | wc -l | tr -d ' ')
            b=$(awk -v a="$api" '$1 == a && $2 != "ok" {print $2; exit}' "$D/sites")
            if [ "$c" -lt 2 ]; then bad "axis 2: only $c $api site(s) in the probe (floor 2: the literal and the var-held route)"
            elif [ -n "$b" ]; then bad "axis 2: a $api site is not followed by its failure check and stub call ($b)"
            else ok; fi
        done
        # 6.7.16 (D79): the BOOL path / truncate calls, at their own floors — mkdir and unlink each a
        # literal and a var-held route (unlink's 0xF035 a third), rmdir and SetEndOfFile literal only.
        for af in CreateDirectoryW:2 DeleteFileW:3 RemoveDirectoryW:1 SetEndOfFile:1 MoveFileExW:1 CreateSymbolicLinkW:1 FlushFileBuffers:3; do
            api=${af%:*}; fl=${af#*:}
            c=$(awk -v a="$api" '$1 == a' "$D/sites" | wc -l | tr -d ' ')
            b=$(awk -v a="$api" '$1 == a && $2 != "ok" {print $2; exit}' "$D/sites")
            if [ "$c" -lt "$fl" ]; then bad "axis 2: only $c $api site(s) in the probe (floor $fl)"
            elif [ -n "$b" ]; then bad "axis 2: a $api call is not followed by its failure check and the table-stub call ($b: a FALSE BOOL must answer -errno)"
            else ok; fi
        done
        # 6.7.16: every CloseHandle and SetEndOfFile call is reached through the std-fd map.
        _std_map_axis
        # 6.7.16: every fd-taking call is behind the low-bit guard.
        _fd_guard_axis
        TS=$(awk '$1 != "ReadFile" {print $3}' "$D/sites" | sort -u)
        RS=$(awk '$1 == "ReadFile" {print $3}' "$D/sites" | sort -u)
        if [ "$(printf '%s\n' "$TS" | wc -l | tr -d ' ')" != 1 ] || [ "$(printf '%s\n' "$RS" | wc -l | tr -d ' ')" != 1 ] || [ "$TS" = "$RS" ]; then
            bad "axis 2: the write / seek / open / close / mkdir / unlink / rmdir / truncate sites must share ONE table stub and ReadFile's ONE read stub (table: $(echo $TS), read: $(echo $RS))"
        else
            ok
            # axis 3: the table stub, from its first instruction to its ret.
            awk -F'\t' -v at="$TS" '
                { a = $1; sub(/^ +/, "", a); sub(/:$/, "", a) }
                ("0x" a) == at { on = 1 }
                on && NF >= 3 { print $3 }
                on && $3 ~ /^ret/ { exit }' "$D/dis" > "$D/table"
            awk -F'\t' -v at="$RS" '
                { a = $1; sub(/^ +/, "", a); sub(/:$/, "", a) }
                ("0x" a) == at { on = 1 }
                on && NF >= 3 { print $3 }
                on && $3 ~ /^ret/ { exit }' "$D/dis" > "$D/read"
            head1=$(sed -n 1p "$D/table"); head2=$(sed -n 2p "$D/table")
            case "$head1" in "sub "*'$0x28,%rsp'*) ok ;; *) bad "axis 3: the table stub does not open with sub \$0x28,%rsp (it reads '$head1')" ;; esac
            case "$head2" in *"# $GL") ok ;; *) bad "axis 3: the table stub's first call is not through GetLastError's IAT slot $GL (it reads '$head2')" ;; esac
            # Plain POSIX awk (CI's is mawk: no strtonum), so the hex is decoded by hand.
            got=$(awk '
                function hex(s,   i, v) { v = 0; s = tolower(s); sub(/^\$0x/, "", s); sub(/,.*/, "", s)
                    for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
                    return v }
                /^mov +\$0x[0-9a-f]+,%edx/ { e = hex($2); next }
                /^cmp +\$0x[0-9a-f]+,%ecx/ { c = hex($2); p = 1; next }
                p && /^cmove +%edx,%eax/ { print c ":" e }
                { p = 0 }' "$D/table" | sort -t: -k1,1n | tr '\n' ' ' | sed 's/ $//')
            if [ "$got" = "$TABLE" ]; then ok
            else bad "axis 3: the table maps '$got', want '$TABLE'"; fi
            tail2=$(tail -2 "$D/table" | tr '\n' ';')
            case "$tail2" in "neg "*"%rax;ret"*) ok ;; *) bad "axis 3: the table stub does not end neg %rax; ret ('$tail2')" ;; esac
            rd=$(tr '\n' ';' < "$D/read")
            case "$rd" in
                *"call   $TS"*'cmp    $0x6d,%ecx;cmove  %rdx,%rax;cmp    $0x26,%ecx;cmove  %rdx,%rax;mov    0x20(%rsp),%edx;cmp    $0xea,%ecx;cmove  %rdx,%rax;'*) ok ;;
                *) bad "axis 3: the read stub does not call the table and then map 109 / 38 to 0 and 234 to the count: $(printf '%s' "$rd" | tr -s ' ')" ;;
            esac
            case "$rd" in *'xor    %edx,%edx;cmp    $0x6d'*) ok ;; *) bad "axis 3: the read stub's end-of-file rows do not select 0 (xor %edx,%edx before them)" ;; esac
        fi
    fi
fi

# axis 5: static, lib/io.cyr's Windows classification of CREATE_NEW's -EACCES over a directory.
# One fn, comment lines dropped (a `#` line that is not a directive), and its Windows arm. No
# reader below a pipe exits before its input ends: awk reads the file itself, and warm's arm reader
# stops printing at #endif rather than exiting — behind `grep -v`, an exit at the brace killed grep
# with SIGPIPE, and under `bash -eo pipefail` (GitHub's run: shell) `ssym=$(swfn …)` stopped the
# gate with rc 141 and no verdict (3 of 100 runs). CHANGELOG [6.7.17]
fnbody() { awk -v n="fn $1(" '/^[[:space:]]*#[^a-z]/ { next } index($0, n) == 1 { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }' "$IO"; }
warm() { fnbody "$1" | awk 'w < 2 && /^[[:space:]]*#ifdef CYRIUS_TARGET_WIN/ { w = 1; next } w == 1 && /^[[:space:]]*#endif/ { w = 2 } w == 1 { print }'; }
case "$(warm file_create_exclusive)" in
    *'if (fd == 0 - 13) {'*'_io_name_exists(path) == 1'*'return 0 - 17;'*) ok ;;
    *) bad "axis 5: file_create_exclusive's CYRIUS_TARGET_WIN arm does not classify -13 (CREATE_NEW over a directory) as -17 by asking the name: $(warm file_create_exclusive | tr -s ' \n' '  ')" ;;
esac
case "$(warm _io_tmp_taken)" in
    *'if (rc == 0 - 13) { return _io_name_exists(tmp); }'*) ok ;;
    *) bad "axis 5: _io_tmp_taken's CYRIUS_TARGET_WIN arm does not classify -13 by asking the name: $(warm _io_tmp_taken | tr -s ' \n' '  ')" ;;
esac

# axis 5, 6.7.16 (D95): lib/syscalls_windows.cyr asks the name on an open's / unlink's -13.
SW="$ROOT/lib/syscalls_windows.cyr"
swfn() { awk -v n="fn $1(" '/^[[:space:]]*#[^a-z]/ { next } index($0, n) == 1 { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }' "$SW"; }
case "$(swfn sys_open)" in
    *'& 196608) == 0) { return _win_open_eacces(path, flags, syscall(SYS_OPEN'*'& 192) == 192) { return _win_open_eacces(path, flags, syscall(SYS_OPEN'*) ok ;;
    *) bad "axis 5: sys_open's plain and O_CREAT|O_EXCL arms do not hand CreateFileW's answer to _win_open_eacces: $(swfn sys_open | tr -s ' \n' '  ')" ;;
esac
case "$(swfn _win_open_eacces)" in
    *'if (h != 0 - 13) { return h; }'*'if ((flags & 579) == 0) { return h; }'*'_win_is_dir(path) == 0'*'return 0 - 17;'*'return 0 - 21;'*) ok ;;
    *) bad "axis 5: _win_open_eacces does not classify a -13 (write / create / truncate access, a directory: -21; O_EXCL -17): $(swfn _win_open_eacces | tr -s ' \n' '  ')" ;;
esac
case "$(swfn _win_is_dir)" in
    *'syscall(61465, path)'*'(at & 16) != 0'*) ok ;;
    *) bad "axis 5: _win_is_dir does not read GetFileAttributesW's directory bit: $(swfn _win_is_dir | tr -s ' \n' '  ')" ;;
esac
case "$(swfn sys_unlink)$(swfn _win_unlink_eacces)$(swfn sys_truncate)$(warm xunlink)" in
    *'_win_unlink_eacces(path, syscall(87, path))'*'_win_is_dir(path) == 1) { return 0 - 21; }'*'var h = sys_open(path, 1, 0);'*'_win_unlink_eacces(path, syscall(0xF035, path))'*) ok ;;
    *) bad "axis 5: sys_unlink / xunlink do not classify DeleteFileW's -13, or sys_truncate does not open through sys_open" ;;
esac

# axis 5, 6.7.16 (D94, the pw review): sys_symlink retries CreateSymbolicLinkW without
# ALLOW_UNPRIVILEGED_CREATE only on -22 — the flagless call fails ERROR_PRIVILEGE_NOT_HELD (-1) in
# any non-elevated process, and wine (which ignores the privilege) and the elevated cass leg never
# see it, so this static row is what holds it.
ssym=$(swfn sys_symlink)
nsym=$(printf '%s\n' "$ssym" | grep -c 'syscall(61502,' || true)
case "$ssym" in
    *'var r = syscall(61502, linkpath, target, kind | 2);'*'if (r != 0 - 22) { return r; }'*'return syscall(61502, linkpath, target, kind);'*)
        if [ "$nsym" = 2 ]; then ok
        else bad "axis 5: sys_symlink makes $nsym CreateSymbolicLinkW calls (want 2: the flagged one, then the flagless retry behind \`r != 0 - 22\`)"; fi ;;
    *) bad "axis 5: sys_symlink's flagless CreateSymbolicLinkW retry is not reachable only behind \`if (r != 0 - 22) { return r; }\`: $(printf '%s' "$ssym" | tail -5 | tr -s ' \n' '  ')" ;;
esac

# axis 6, 6.7.16: static — the stdlib wrappers that hand an fd to a raw handle reroute ask
# `_win_fd_aliases` first. The folds (docs/ecosystem.md's lib/ rows) are not cyrius-edited and call
# no raw handle reroute; the census reads every other lib/*.cyr.
FOLDS=$(grep -o '^| `lib/[a-z_0-9]*\.cyr`' "$ROOT/docs/ecosystem.md" | sed 's/^| `lib\///; s/`$//' | tr '\n' ' ')
[ -n "$FOLDS" ] || bad "axis 6: no fold rows read from docs/ecosystem.md"
for lf in "$ROOT"/lib/*.cyr; do
    case " $FOLDS " in *" $(basename "$lf") "*) continue ;; esac
    awk -v F="$(basename "$lf")" '
        /^[ \t]*#/ { next }
        /^fn [A-Za-z_0-9]+\(/ { fn = $2; sub(/\(.*/, "", fn); g = 0; gc = 0 }
        /_win_fd_aliases\(fd\)/ { g = 1 }
        /_win_fd_aliases\(load64\(ctx \+ (48|56)\)\)/ { gc = 1 }
        /syscall\((0xF0[0-9A-Fa-f][0-9A-Fa-f]|61[45][0-9][0-9]), *fd[,)]/ {
            if ($0 ~ /syscall\((0xF03F|61503), *fd/) next
            print (g ? "G ok " : "G BAD ") F ":" fn ":" NR
        }
        /syscall\(0xF0(29|2A|27), load64\(ctx \+ (48|56)\)/ { print (gc ? "C ok " : "C BAD ") F ":" fn ":" NR }
        /^fn win_handle_under\(/ { wh = 1 }
        wh && /_win_fd_aliases\(h\)/ { wa = 1 }
        wh && /_win_fd_aliases\(root_h\)/ { wb = 1 }
        wh && /syscall\(0xF04E/ { print ((wa && wb) ? "W ok " : "W BAD ") F ":" fn ":" NR; wh = 0 }
    ' "$lf"
done > "$D/census"
c6=$(awk '$2 == "ok"' "$D/census" | wc -l | tr -d ' ')
b6=$(awk '$2 == "BAD" {print $3}' "$D/census" | tr '\n' ' ')
cc6=$(awk '$1 == "C" && $2 == "ok"' "$D/census" | wc -l | tr -d ' ')
cw6=$(awk '$1 == "W" && $2 == "ok"' "$D/census" | wc -l | tr -d ' ')
if [ -n "$b6" ]; then bad "axis 6: a stdlib fd reaches a raw handle reroute without asking _win_fd_aliases first: $b6"
elif [ "$c6" -lt 24 ] || [ "$cc6" -lt 3 ] || [ "$cw6" -lt 1 ]; then bad "axis 6: $c6 guarded raw handle call(s) (floor 24), $cc6 reactor-task one(s) (floor 3), $cw6 win_handle_under (want 1)"
else ok; fi

# axis 4: behaviour under wine.
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: axis 4 (wine absent — the cass cross-OS leg runs the same .tcyr on real Windows)"
else
    mkdir -p "$D/w"
    _wine() {  # $1 = exe name inside $D/w, $2 = stdout capture
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine "$1" > "$2" 2>&1 )
    }
    # The four filed repros, verbatim.
    cat > "$D/rd.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var buf[16];
var n = file_read(0 - 999, &buf, 16);        # not a descriptor / handle
syscall(SYS_EXIT, 100 + n);                  # Linux 91 (-EBADF); Windows 100 (0, "EOF")
EOF
    cat > "$D/op.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("no_such_file_w1.txt", O_RDONLY, 0);
syscall(SYS_EXIT, 0 - fd);                   # Linux 2 (-ENOENT); Windows 1 (-1)
EOF
    cat > "$D/sk.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("lseek_neg.tmp", O_RDWR | O_CREAT | O_TRUNC, 420);
file_write(fd, "abcdefgh", 8);
var r1 = xlseek(fd, 0 - 1, 0);      # SEEK_SET to -1: must fail
var r2 = xlseek(fd, 4, 0);
var r3 = xlseek(fd, 0 - 100, 1);    # SEEK_CUR to 4 - 100: must fail
var r4 = xlseek(fd, 0, 1);
fmt_int(r1); println("");
fmt_int(r2); println("");
fmt_int(r3); println("");
fmt_int(r4); println("");
file_close(fd);
xunlink("lseek_neg.tmp");
EOF
    # 6.7.15: the close repro (issues/archived/2026-10-16-pe-close-returns-closehandle-bool.md), verbatim.
    cat > "$D/cl.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("cl_probe.tmp", O_WRONLY | O_CREAT | O_TRUNC, 420);
var ok = sys_close(fd);                      # a real descriptor: 0 on Linux
var bad = sys_close(0 - 999);                # not a descriptor / handle: -9 on Linux
xunlink("cl_probe.tmp");
syscall(SYS_EXIT, 100 + ok * 10 + bad);      # Linux 91; Windows 110 (TRUE 1, FALSE 0)
EOF
    for p in rd op sk cl; do
        ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/$p.cyr" > "$D/w/$p.exe" 2> "$D/$p.err" ) || true
    done
    if [ ! -s "$D/w/rd.exe" ]; then bad "axis 4: the PE build of the read repro produced no binary"
    else xrc=0; _wine rd.exe "$D/rd.out" || xrc=$?
        if [ "$xrc" = 91 ]; then ok; else bad "axis 4: the read repro exits $xrc under wine (want 91: file_read(-999) -> -9; 100 is the old 0, end of file)"; fi
    fi
    if [ ! -s "$D/w/op.exe" ]; then bad "axis 4: the PE build of the open repro produced no binary"
    else xrc=0; _wine op.exe "$D/op.out" || xrc=$?
        if [ "$xrc" = 2 ]; then ok; else bad "axis 4: the open repro exits $xrc under wine (want 2: -ENOENT; 1 is the old -1)"; fi
    fi
    if [ ! -s "$D/w/sk.exe" ]; then bad "axis 4: the PE build of the seek probe produced no binary"
    else xrc=0; _wine sk.exe "$D/sk.out" || xrc=$?
        sk=$(tr -d '\r' < "$D/sk.out" | tr '\n' ' ' | sed 's/ *$//')
        if [ "$sk" = "-22 4 -22 4" ]; then ok; else bad "axis 4: the seek probe prints '$sk' under wine (want '-22 4 -22 4'; '0 4 0 4' is the old answer)"; fi
    fi
    if [ ! -s "$D/w/cl.exe" ]; then bad "axis 4: the PE build of the close repro produced no binary"
    else xrc=0; _wine cl.exe "$D/cl.out" || xrc=$?
        if [ "$xrc" = 91 ]; then ok; else bad "axis 4: the close repro exits $xrc under wine (want 91: a good close 0, close(-999) -9; 110 is the old BOOL answer)"; fi
    fi
    # 6.7.16: the std-fd close and truncate rows (the probes above axis 2). The caller redirects.
    _wrun() {
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine "$@" )
    }
    for p in closestd trstd close2 clsh_child clreuse closeneg pathfail ftfail alias rsfail dirfail; do
        ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/$p.cyr" > "$D/w/$p.exe" 2> "$D/$p.werr" ) || true
    done
    clsh_parent clsh_child.exe > "$D/clsh_parent_w.cyr"
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/clsh_parent_w.cyr" > "$D/w/clsh_parent.exe" 2> "$D/clsh_parent.werr" ) || true
    if [ ! -s "$D/w/closestd.exe" ] || [ ! -s "$D/w/trstd.exe" ] || [ ! -s "$D/w/close2.exe" ] || [ ! -s "$D/w/clsh_child.exe" ] || [ ! -s "$D/w/clsh_parent.exe" ] || [ ! -s "$D/w/clreuse.exe" ] || [ ! -s "$D/w/closeneg.exe" ] || [ ! -s "$D/w/pathfail.exe" ] || [ ! -s "$D/w/ftfail.exe" ] || [ ! -s "$D/w/alias.exe" ] || [ ! -s "$D/w/rsfail.exe" ] || [ ! -s "$D/w/dirfail.exe" ]; then
        bad "axis 4: a PE build of the std-fd probes produced no binary: $(cat "$D"/*.werr | grep -m2 '^error' | tr '\n' ' ')"
    else
        _wrun closestd.exe < /dev/null > "$D/w/cs.out" 2> "$D/w/cs.err" || true
        got=$(line "$D/w/cs.out")
        if [ "$got" = "0 -9" ] && [ ! -s "$D/w/cs.err" ]; then ok
        else bad "axis 4: the close repro under wine prints '$got', stderr '$(cat "$D/w/cs.err")' (want '0 -9' and an empty stderr; '-9 1' with 'x' is the old raw-handle answer)"; fi
        # wine's std handle for a Unix-side redirect refuses SetEndOfFile (ERROR_INVALID_HANDLE), so the
        # redirect is cmd's, a real file handle, as it is on cass.
        trc=0; _wrun cmd /c "trstd.exe > tr.out" < /dev/null > /dev/null 2>&1 || trc=$?
        trg=$(tr -d '\r' < "$D/w/tr.out" 2> /dev/null)
        if [ "$trc" = 100 ] && [ "$trg" = abc ]; then ok
        else bad "axis 4: the truncate repro under wine (cmd's redirect) exits $trc with tr.out '$trg' (want 100, 'abc'; 99 and 'abcdefgh' is the old raw-handle answer)"; fi
        _wrun close2.exe < /dev/null > "$D/w/c2.out" 2> /dev/null || true
        got=$(line "$D/w/c2.out")
        if [ "$got" = "0 -9" ]; then ok; else bad "axis 4: a second close of fd 2 under wine: '$got' (want '0 -9': the slot holds INVALID_HANDLE_VALUE, which CloseHandle would accept)"; fi
        _wrun clsh_parent.exe < /dev/null > "$D/w/ps.out" 2> /dev/null || true
        got="$(line "$D/w/ps.out") / $(line "$D/w/clsh.txt" 2> /dev/null)"
        if [ "$got" = "1 o / 0 1 -9" ]; then ok; else bad "axis 4: the one-handle child's close(2) under wine: '$got' (want '1 o / 0 1 -9': its stdout still writes; '0 / 0 -9 -9' closed the shared HANDLE, '2 oe / -9 1 1' is the old raw-handle answer)"; fi
        _wrun clreuse.exe < /dev/null > "$D/w/cr.out" 2> /dev/null || true
        got=$(line "$D/w/cr.out")
        if [ "$got" = "0 -9 0" ]; then ok; else bad "axis 4: a write to fd 2 after its close and a new open, under wine: '$got' (want '0 -9 0': -9, and nothing lands in the new file)"; fi
        _wrun closeneg.exe < /dev/null > "$D/w/cn.out" 2> /dev/null || true
        got=$(line "$D/w/cn.out")
        if [ "$got" = "-9 -9 -9" ]; then ok; else bad "axis 4: the negative-fd close repro under wine: '$got' (want '-9 -9 -9'; '0 0 0' is CloseHandle of the -1 / -2 pseudo-handles)"; fi
        mkdir -p "$D/w/pf" "$D/w/ft"
        cp "$D/w/pathfail.exe" "$D/w/pf/" && cp "$D/w/ftfail.exe" "$D/w/ft/"
        ( cd "$D/w/pf" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine pathfail.exe < /dev/null > pf.out 2> /dev/null ) || true
        got=$(line "$D/w/pf/pf.out")
        if [ "$got" = "0 -17 -39 -2 -2 0 0" ]; then ok; else bad "axis 4: the path-failure repro under wine: '$got' (want '0 -17 -39 -2 -2 0 0'; '0 -1 -1 -1 -1 0 0' is the BOOL folded to -1)"; fi
        ( cd "$D/w/ft" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine ftfail.exe < /dev/null 2> /dev/null | cat > /dev/null ) || true
        got=$(line "$D/w/ft/ft.out" 2> /dev/null)
        if [ "$got" = "-22 -9 -2 -9" ]; then ok; else bad "axis 4: the truncate-failure repro (stdout a pipe) under wine: '$got' (want '-22 -9 -2 -9'; '-1 -1 -1 -1' is every step folded to -1)"; fi
        mkdir -p "$D/w/al" && cp "$D/w/alias.exe" "$D/w/al/"
        ( cd "$D/w/al" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine alias.exe < /dev/null > al.out 2> /dev/null ) || true
        got=$(line "$D/w/al/al.out")
        if alias_ok "$got" 4; then ok; else bad "axis 4: the fd-alias repro under wine: '$got' (want '<h> -9 3 0', h a multiple of 4; '<h> 0 -9 -9' is the close of h + 3 closing h)"; fi
        mkdir -p "$D/w/rs" && cp "$D/w/rsfail.exe" "$D/w/rs/"
        ( cd "$D/w/rs" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine rsfail.exe < /dev/null > rs.out 2> /dev/null ) || true
        got=$(line "$D/w/rs/rs.out")
        if [ "$got" = "-2 -2 -9" ]; then ok; else bad "axis 4: the rename / symlink / fsync repro under wine: '$got' (want '-2 -2 -9'; '-1 -1 -1' is every BOOL folded to -1)"; fi
        mkdir -p "$D/w/df" && cp "$D/w/dirfail.exe" "$D/w/df/"
        ( cd "$D/w/df" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine dirfail.exe < /dev/null > df.out 2> /dev/null ) || true
        got=$(line "$D/w/df/df.out")
        if [ "$got" = "-21 -21 -21 -21" ]; then ok; else bad "axis 4: the directory repro under wine: '$got' (want '-21 -21 -21 -21'; '-13 -13 -13 -13' is ERROR_ACCESS_DENIED unasked)"; fi
    fi
    # 6.7.16: the Windows-only wrappers' leaves (axis 6 holds their shape where wine is absent).
    cat > "$D/wrapalias.cyr" <<'EOF'
include "lib/assert.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/tagged.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/net.cyr"
include "lib/fs.cyr"
include "lib/chrono.cyr"
include "lib/fnptr.cyr"
include "lib/atomic.cyr"
include "lib/async.cyr"
include "lib/tls.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
var st, s = tcp_socket();
var bt, bv = sock_bind(s, INADDR_LOOPBACK(), 0);
var buf[16];
p(_tn_os_read(s + 1, &buf, 1));
p(_tn_os_write(s + 2, "x", 1));
p(_tn_nb_on(s + 3));
p(async_relay_once(0, s + 1, s, &buf, 1));
sys_mkdir("wa_d", 448);
var root = sys_open("wa_d", 65536, 0);
var h = sys_open("wa_d/f", 577, 420);
p(win_handle_under(h, root));
p(win_handle_under(h + 1, root));
p(win_handle_under(h, root + 2));
sys_close(h);
sys_close(root);
sys_unlink("wa_d/f");
sys_rmdir("wa_d");
sock_close(s);
println("");
EOF
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/wrapalias.cyr" > "$D/w/wrapalias.exe" 2> "$D/wrapalias.werr" ) || true
    if [ ! -s "$D/w/wrapalias.exe" ]; then bad "axis 4: the PE build of the wrapper probe produced no binary: $(grep -m2 'error' "$D/wrapalias.werr" | tr '\n' ' ')"
    else
        mkdir -p "$D/w/wa" && cp "$D/w/wrapalias.exe" "$D/w/wa/"
        ( cd "$D/w/wa" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine wrapalias.exe < /dev/null > wa.out 2> /dev/null ) || true
        got=$(line "$D/w/wa/wa.out")
        if [ "$got" = "-9 -9 -9 -9 1 -1 -1" ]; then ok; else bad "axis 4: the stdlib wrappers of an fd never opened, under wine: '$got' (want '-9 -9 -9 -9 1 -1 -1'; '-10057 -10054 0 -10057 1 1 1' is the socket s / the file h acted on)"; fi
    fi
    for pair in "$T1:$F1" "$T2:$F2" "$T3:$F3" "$T4:$F4" "$T5:$F5" "$T6:$F6"; do
        t=${pair%:*}; fl=${pair##*:}; b=$(basename "$t" .tcyr)
        ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$t" > "$D/w/$b.exe" 2> "$D/$b.werr" ) || true
        if [ ! -s "$D/w/$b.exe" ]; then
            bad "axis 4: the PE build of $b.tcyr produced no binary: $(grep -m2 '^error' "$D/$b.werr" | tr '\n' ' ')"
            continue
        fi
        wrc=0; _wine "$b.exe" "$D/$b.wout" || wrc=$?
        sum=$(summary "$D/$b.wout"); np=${sum% *}; nf=${sum#* }
        if [ -z "$sum" ] || [ "$wrc" != 0 ] || [ "$nf" != 0 ] || [ "$np" -lt "$fl" ]; then
            bad "axis 4: $b.tcyr under wine: '${sum:-no summary}' (exit $wrc, floor $fl)"
            tr -d '\r' < "$D/$b.wout" | grep -m6 'FAIL:' | sed 's/^/      /'
        else ok; fi
    done
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 10 ] || { echo "FAIL: pe_reroute_failure_errno: only $pass rows ran (floor 10: axes 1 and 5 always run)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_reroute_failure_errno"; exit 1; fi
echo "PASS: pe_reroute_failure_errno — a failed ReadFile / WriteFile / SetFilePointerEx / CreateFileW / CloseHandle / CreateDirectoryW / DeleteFileW / RemoveDirectoryW / SetEndOfFile / MoveFileExW / CreateSymbolicLinkW / FlushFileBuffers answers -errno through one GetLastError table (a good close 0); a drained pipe still reads 0; a close / truncate of fd 0 / 1 / 2 reaches the std handle; a negative fd's close is -9; an fd with a low bit set (no descriptor: it would alias the handle below it) is -9 in every fd reroute; ftruncate of a pipe, the null device or a read-only descriptor -22"
