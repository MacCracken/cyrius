# PE: an fd above 2 that is not a multiple of 4 aliases the live handle below it (the NT kernel ignores a handle's two low bits) — `sys_close(h + 3)` closes file `h`, and a read / write / seek / ftruncate of a never-opened fd acts on another object — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 p16 review (its file_as_issue), measured again 2026-10-20 on the p16
lane (l6716-p16 at e24cc3d67) with the PE compiler built from the lane's tree (`CYRIUS_TARGET_WIN=1 ./build/cycc`),
under wine 11.20 (a private WINEPREFIX) and on real cass (Windows 11, `C:\cyrius-tests`).
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 p16 review; placed at the p16 / t16 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; pw lane, wave 4, unit PW1) — never 7.x.
**Severity:** Medium — a silent wrong value with a side effect: a value that is no descriptor reaches CloseHandle
(or ReadFile / WriteFile / SetFilePointerEx / SetEndOfFile) as a HANDLE, and the kernel resolves it to the handle
three or fewer below, so a close of a stale or computed fd closes an unrelated open file and every later use of
that file fails -9. It is 6.7.16's D78 class (a value that is no descriptor reaches CloseHandle and closes
something) in a different shape from D78's negative fds. The program's own fd values drive it — no boundary is
crossed (no ledger id).
**Why it is not fixed in the lane:** refusing an fd > 2 with `(fd & 3) != 0` as -9 in `ECLOSE_PE` and in
`_pe_fd_to_handle_rcx` (the read / write / seek reroutes) and the other fd reroutes changes what those calls answer
beyond D78 — the user's call. It is a `src/` change (seed-derive, the cass self-host).

## Reproduction

`alias.cyr`, built for each target from the repo root (`./build/cycc` / `CYRIUS_TARGET_WIN=1 ./build/cycc`), run
in an empty directory:

```cyr
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
```

| host | output |
|---|---|
| x86_64 Linux | `3 -9 3 0` |
| wine 11.20 | `52 0 -9 -9` |
| cass (real Windows 11) | `240 0 -9 -9` |

The close of fd `h + 3` answers 0 and closes `h`: the write to `h` and its own close then answer -9.

The same aliasing makes the D80 filing's "fd never opened" cell (`sys_ftruncate(99, n)`, fd 99 = handle 96)
depend on what handle 96 is in that process: on cass `ftfail.exe | findstr .` reads `-22 -9 -2 -9` (as filed) and
`ftfail.exe < nul | findstr .` reads `-22 -22 -2 -9` — fd 99 there is the char-device handle 96. (The guide's row
and path_failure_errno.tcyr pin `sys_ftruncate(-999, n)` instead since the p16 review fix.)

## The sites (src/backend/x86/emit.cyr at e24cc3d67)

- `ECLOSE_PE` (~2262): `cmp rax, 2; jg` → `.direct: mov rcx, rax; call [CloseHandle]`.
- `_pe_fd_to_handle_rcx` (~1819), shared by EWRITE_PE, EREAD_PE, ELSEEK_PE, EFLUSHFB_PE (fsync) and ESETEOF_PE
  (0xF03F, ftruncate): `cmp rax, 2; ja .direct` — the fd IS the handle.
- Any other reroute that takes an fd as the HANDLE directly (LockFileEx / UnlockFileEx,
  GetFileInformationByHandleEx, …): a fix derives the list by grepping the reroutes, never from this one.

A fix answers -9 for an fd above 2 whose low two bits are set, before any Win32 call, on every fd reroute (one
shared check, as D78's `js` in the std-close stub). Real kernel handles (files, pipes, sockets) are multiples of 4,
so no live descriptor is refused. Rows: a `crossos/` tcyr pinning the reproduction's `3 -9 3 0` shape on every
target (close / read / write / seek of `h + 1`, `h + 2`, `h + 3` answer -9 and `h` stays usable), and
pe_reroute_failure_errno.sh's axis 2 pinning the check's bytes at each site.
