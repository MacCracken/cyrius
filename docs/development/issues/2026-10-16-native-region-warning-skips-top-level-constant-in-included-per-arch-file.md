# The native-region renumber warning does not judge a constant declared at the top level of a per-arch file included from inside `#ifdef CYRIUS_ARCH_AARCH64` — the D61 include shape, spelled by name — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 platform lane's tree (l6714-platform, after ce65feca8,
the fix for issues/archived/2026-10-15-native-region-warning-misses-included-files-and-author-constants.md), with the
ELF-aarch64 cross compiler built from it (`build/cycc_aarch64`), run under qemu-aarch64. Filed from the platform
lane's review.
**Placement:** 6.7.15 — repair 5 (platform lane; filed from the 6.7.14 platform review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — the wrong syscall runs with no diagnostic (the class the 6.7.12 / 6.7.14 warning exists for).
Warn-only territory (6.7.12's D1): no program's behaviour is at stake, only the missing warning. Workaround: the
`1000 + N` private alias, or declare the constant inside a `#ifdef CYRIUS_ARCH_AARCH64` region of its own file
(judged since 6.7.14).
**Affects:** ELF-aarch64 output; `src/backend/aarch64/emit.cyr` `_esx_native_warn` / `_esx_decl_in_region`.
**Not the same shape as** the staged `2026-10-16-native-region-warning-skips-fn-local-const.md` (a fn-local `const`
inside a region: not a var slot at all). Here the constant IS a judged var slot; its declaration is outside every
region opened in its own file.

## Reproduction

`src/arch_aarch64.cyr`:

```cyr
enum ArchNr { NR_UMOUNT2 = 39; }
fn arch_umount(path) { return syscall(NR_UMOUNT2, path, 0); }
```

`main.cyr`:

```cyr
#ifdef CYRIUS_ARCH_AARCH64
include "src/arch_aarch64.cyr"
#endif
var r = arch_umount("/nonexistent");
if (r == 0 - 2) { syscall(60, 0); }   # native umount2: -ENOENT
syscall(60, 2);                       # 39 ran getpid: a PID
```

```sh
cat main.cyr | build/cycc_aarch64 > main.bin; echo "rc=$?"; chmod +x main.bin; qemu-aarch64 ./main.bin; echo "exit=$?"
```

```text
rc=0                       (no warning on stderr — only the unreachable-fns note)
exit=2                     (39 was renumbered → 172, getpid)
```

The same file with the literal (`fn arch_umount(path) { return syscall(39, path, 0); }`, included the same way)
warns — the raw-literal half of D61 carries through `include`:

```text
warning:src/arch_lit.cyr:1:31: raw syscall 39 inside a native-aarch64 region is renumbered → 172 (getpid); write 1039 for native umount2
exit=2
```

## Root cause

6.7.14 judges a folded constant by where it was DECLARED (`SVDECL` records the name token's expanded-source offset per
var slot), and `_esx_decl_in_region` asks `_esx_rg_local` — a region opened in the declaration's OWN file — on
purpose: the aarch64 stdlib peer `lib/syscalls_aarch64_linux.cyr` declares its deliberately x86-numbered `SYS_*` at
its file's top level (`SYS_FSYNC = 74;`, line 57, renumbered → 82 by design) and is itself included from inside
`lib/syscalls.cyr`'s `#ifdef CYRIUS_ARCH_AARCH64` region, so a carried region would warn on every such number. An author's
per-arch file included under the guard is the same shape as a stdlib peer, so its top-level native constant is silent
too, while the raw literal in the same file warns (`_esx_region_at`, which carries the region through include).

## What a fix needs (the user's call)

A rule that tells an author's per-arch file from a stdlib syscall peer — e.g. carry the includer's region for a
constant declared outside `lib/`, or for a file not reached through `lib/syscalls.cyr`, or a marker the peers carry —
since spelling-by-name is guide rule 1-2's sanctioned way to write an x86 number inside the region. The row:
tests/gates/platform/native_region_literal_warns.sh gains this repro (warns, exit unchanged) and keeps its
stdlib-silence sweep (every lib/*.cyr for ELF aarch64 and arm64 Mach-O: 0 native-region warnings).
