# `lib/syscalls_linux_common.cyr`'s `sys_ioctl` comment says ELF aarch64 has no 16 → 29 row; the backend has had one since v6.5.38 — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-12 against the published 6.7.9: the comment is unchanged (`lib/syscalls_linux_common.cyr:179`), the row exists at the 6.7.9 tag (`src/backend/aarch64/emit.cyr:1532` comment, `:1550` the emit), and a raw `syscall(16, …)` run under qemu-aarch64 behaves as ioctl.
**Placement:** Unplaced — filed from darshana 1.3.0 (2026-10-12). Only the user places it.
**Discovered:** 2026-10-12, darshana's 1.1.4 audit (darshana had made the same claim in its own docs and corrected it there).
**Severity:** Low — doc mismatch. The advice it gives (use the per-arch number, not 16) is still right; the reason it gives is wrong.
**Affects:** the comment since `sys_ioctl` was added; the row since v6.5.38.

## Summary

The `sys_ioctl` docstring says:

> Do NOT "normalise" these to the x86 value — on ELF-aarch64 a literal 16 is not translated at all (there is no
> 16→29 row), so a consumer that hardcodes the x86 number silently issues a different, valid syscall. That is the
> exact defect `2026-08-23-darshana-aarch64-syscall-shadow-no-diagnostic` reports.

v6.5.38 added that row ("ioctl 16 → 29 (x86-compat), closing the darshana filing's first ask", `emit.cyr:1532`), so
on ELF aarch64 a literal 16 now reaches `ioctl`. The darshana filing the comment cites is archived as resolved. What
the comment should say is narrower: a literal 16 is rewritten only because of an x86-compat row, so hardcoding it
relies on the translation. A hardcoded x86 number with no row is the case that still silently misfires.

## Reproduction

```
# cyrius.cyml: cyrius = "6.7.9", [deps] stdlib = ["syscalls", "string", "fmt", "io"]
var tio[64];
fn main() {
    var raw = syscall(16, 1, 0x5401, &tio);       # TCGETS on stdout
    var wrapped = sys_ioctl(1, 0x5401, &tio);
    sys_write(2, "raw 16: ", 8); fmt_int_fd(2, raw); sys_write(2, "\n", 1);
    sys_write(2, "sys_ioctl: ", 11); fmt_int_fd(2, wrapped); sys_write(2, "\n", 1);
    return 0;
}
main();
syscall(SYS_EXIT, 0);
```

```sh
cyrius build --aarch64 raw16.cyr build/raw16 && qemu-aarch64 build/raw16 | cat
```

Actual (6.7.9), stdout a pipe:

```
raw 16: -25
sys_ioctl: -25
```

Both are `-ENOTTY`, ioctl's answer for TCGETS on a pipe. Untranslated, 16 is `fremovexattr` on aarch64, which would
answer `-EFAULT` or `-EBADF` for these arguments.

## Proposed fix

Reword the comment: the per-arch number is right because it does not depend on an x86-compat ESYSXLAT row; 16 is
rewritten today (v6.5.38), but a hardcoded x86 number with no row is still silently a different syscall. Or drop the
parenthetical.

## Consumer-side workaround

None needed.
