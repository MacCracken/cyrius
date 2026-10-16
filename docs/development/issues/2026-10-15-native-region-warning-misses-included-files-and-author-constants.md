# The native-region renumber warning does not see a per-arch file included from inside a region, or the author's own constant — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 darwin lane's tree (l6712-darwin @ 66384922) with the
ELF-aarch64 cross compiler built from it, run under qemu-aarch64. Filed from unit D1, which shipped the warning for
the filed shape (issues/archived/2026-10-08-aarch64-native-region-literal-translated-silently.md, D1 warn only): a raw
literal inside a region opened in the call's OWN file. Two neighbouring shapes still renumber silently.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (darwin lane; filed from the 6.7.12 darwin lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Medium — the wrong syscall runs with no diagnostic (the same defect as the filed issue, in the two
shapes its warning does not judge). Workaround: the `1000 + N` private alias (or the stdlib `SYS_*` name).
**Affects:** ELF-aarch64 output; `src/backend/aarch64/emit.cyr` `_esx_native_warn` / `_esx_raw_lit_call` /
`_esx_region_here` (6.7.12).

## Reproduction

`src/arch_aarch64.cyr`:

```cyr
# a per-arch file, included only on aarch64 — written with NATIVE numbers
fn arch_lgetxattr(path, name): i64 { return syscall(9, path, name, 0, 0); }
```

`main.cyr`:

```cyr
#ifdef CYRIUS_ARCH_AARCH64
include "src/arch_aarch64.cyr"
enum ArchNr { NR_UMOUNT2 = 39; }
fn arch_umount(path): i64 { return syscall(NR_UMOUNT2, path, 0); }
#endif
fn main(): i64 {
    var a = arch_lgetxattr("/nonexistent", "user.x");   # native lgetxattr: -2 (ENOENT)
    var b = arch_umount("/nonexistent");                # native umount2: -2 (ENOENT)
    if (a != 0 - 2) { return 1; }                      # 9 ran mmap: -22
    if (b != 0 - 2) { return 2; }                      # 39 ran getpid: a PID
    return 0;
}
syscall(60, main());
```

```sh
cat src/main_aarch64.cyr | build/cycc > cca && chmod +x cca
./cca < main.cyr > m.bin && chmod +x m.bin && qemu-aarch64 ./m.bin; echo $?
```

Actual (6.7.12 darwin lane): no warning at compile, exit 1 (`syscall(9)` in the included file ran mmap). With
`syscall(9, …)` moved into main.cyr's own region the 6.7.12 warning fires
(`raw syscall 9 inside a native-aarch64 region is renumbered → 222 (mmap); write 1009 for native lgetxattr`).

## Root cause

The 6.7.12 warning judges (a) a number written as ONE integer-literal token, (b) inside a region opened in the
call's own file. Both limits were needed to keep the stdlib silent, and both leave a real shape uncovered:

1. **A file included from inside a region.** `PP_A64_NATIVE_AT` (src/frontend/lex_pp.cyr; the 6.6.12 x86-name
   warning's region test) INHERITS a region through `include` — by design: "an included file's own blocks … nest
   inside an outer region". Under that rule the stdlib fires: `lib/syscalls.cyr` includes
   `lib/syscalls_aarch64_linux.cyr` (which includes `lib/syscalls_linux_common.cyr`) inside
   `#ifdef CYRIUS_ARCH_AARCH64`, and both deliberately write x86 numbers there — `fd_wait_ready`'s raw 7 (poll →
   ppoll 73) and `sys_epoll_wait`'s raw 232 (→ epoll_pwait 22). Measured with the inherited rule: a stdlib hello
   prints 2 warnings, each advising a wrong alias. `tests/gates/platform/raw_syscall_literals_routed.sh` uses the
   FILE-LOCAL frame (it scans syscalls_linux_common.cyr as arch-neutral and excludes the peers by name), so 6.7.12
   followed it — and a consumer's per-arch file included under the guard, written with native numbers, is missed.
   The two region rules now disagree; one of them has to be the language's (the user's call): file-local
   everywhere (the x86-name warning would then fire inside included per-arch files), inherited everywhere (the
   stdlib's shared files would need another spelling for their x86 numbers, or an explicit "x86-numbered" marker),
   or a marker a file can carry to say which numbering it uses.
2. **The author's own constant.** A `SYS_*` / enum constant is not judged because the stdlib's constants renumber
   BY DESIGN (aarch64 `SYS_FSYNC = 74` → 82); judging every folded number warned on `syscall(SYS_FSYNC, fd)` in a
   consumer's region. A constant DECLARED inside a native region by the author (`NR_UMOUNT2 = 39` above, or the
   guide's rule-3 example, a `SYS_STATFS = 43` declared under the guard) is the native number by the same argument as a
   raw literal, and still renumbers silently. Telling the two apart needs the constant's declaration site
   (whether its `enum`/`var` sits in a file-local native region), which the fold does not see today: ESCPOPS gets
   only the folded value.

## Proposed fix

A decision first (which region rule is the language's — see 1), then extend `_esx_native_warn`: for 1, the chosen
region rule; for 2, record whether a folded constant's declaration sits in a native region (at declaration time,
beside the enum value) and judge such a constant like a raw literal. Gate rows in
`tests/gates/platform/native_region_literal_warns.sh` (axis 7 pins today's silence for both shapes and would flip).
