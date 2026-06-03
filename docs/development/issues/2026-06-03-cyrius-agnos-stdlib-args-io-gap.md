# cyrius `CYRIUS_TARGET_AGNOS` stdlib gap — args + io (blocks agnsh-on-agnos boot)

> **Status**: OPEN — **slotted v6.0.53** (user "after .52", 2026-06-03). cyrius-side fix; the
> agnos kernel side is confirmed correct + complete (no agnos edit — that repo is READ-ONLY).
> **Origin**: filed agnos-side at `agnos/docs/development/issue/2026-06-03-cyrius-agnos-stdlib-args-io-gap.md`
> (agnos 1.41.4 shell-separation). This is the cyrius-side tracking copy + the v6.0.51 scoping survey.
> **Repro toolchain**: cyrius 6.0.51, agnoshi 1.3.4, agnos 1.41.3+, OVMF + NVMe ext2.

## Symptom

`agnsh` built with `cyrius build --agnos` `#UD`s at startup in ring 3: `v=06` (#UD), `cpl=3` (agnsh's
own code, kernel exonerated), `RAX=0x10000000` (agnos mmap-arena base → heap-init `mmap(27)` already
succeeded). The faulting byte is `0f 0b` (`ud2`) right after a `call` — cyrius's unresolved-call
sentinel — at the `args_init()` call site in agnsh's `main`. So agnsh loads, enters ring 3, inits its
heap, calls `args_init()` → `ud2` → `#UD`, no prompt.

## Root cause (v6.0.51 scoping survey — 4-agent, source-verified)

`lib/args.cyr` (`args_init`/`argc`/`argv`) has only `CYRIUS_TARGET_MACOS` + `CYRIUS_TARGET_LINUX`
branches — no `CYRIUS_TARGET_AGNOS` — so cycc emits its `ud2` sentinel (`src/backend/x86/fixup.cyr`
overwrites the undefined `call` with `0F 0B 0F 0B 90`; `main.cyr:1508` warns but does not error, so the
binary builds and faults at runtime). The Linux impl reads `/proc/self/cmdline` (no agnos equivalent);
the agnos branch must read argc/argv from the **SysV init stack**.

**THE CRUX (answered):** cyrius's agnos entry does **NOT** capture the init `rsp`/argc/argv, and the
**entry emission must change**. The only entry-prologue frame-capture (`src/main.cyr:1465`) is gated to
`_init_km == 3 || 2` (object/shared); the agnos executable path (`km==0`) runs e_entry → enum/gvar
inits → `call main` with no capture, so by the time any lib fn runs `rsp` has moved and `[rsp]` can't
recover argc. **Precedent:** the macOS arm64 driver (`src/main_aarch64.cyr:247-250`) emits
`stp x0,x1,[sp,#-16]!; mov x28,sp` at e_entry before the branch-over-fn-bodies; `lib/args_macos.cyr`
reads x28. The agnos fix mirrors this, but argc/argv live on the SysV stack (not registers).

**agnos kernel side — CONFIRMED CORRECT (read-only ground-truth, agnos/kernel/core/elf.cyr
`elf_load_from_file`, the path kybernet uses for `/bin/agnsh`):** builds a real SysV init stack —
`[rsp]=argc`, `[rsp+8+i*8]=argv[i]`, NULL, **empty envp (immediate NULL)**, **auxv = AT_NULL only**;
rsp lands exactly at argc; 16-byte aligned at entry; argc capped at 8. No agnos change needed.

## Fix — v6.0.53 = the boot-to-prompt milestone (ONE medium slot; ~3 core bites + 2 conditional)

Verify reachability empirically FIRST at slot entry: `cyrius build --agnos src/agnsh.cyr` (note: the
real built entry is `agnoshi/src/agnsh.cyr`, NOT `agnoshi/src/main.cyr` which is off-path) and grep ALL
undefined-fn warnings + trace the file_* call graph before final sizing.

1. **[medium — the dispositive core] Emit-side `_TARGET_AGNOS` entry rsp-capture.** In `src/main.cyr`
   near :960 (sibling of `main_aarch64.cyr:247`), an `if (_is_agnos_build == 1)` block emits, as the
   FIRST instruction at e_entry (before gvar inits move rsp), `mov [&_agnos_init_rsp], rsp` into a
   durable global. **Use a global, not a callee-saved reg** (robust vs x86 reg-liveness across
   enum-init/gvar-init/parse-prog). This sits in the self-host driver → the block MUST emit nothing
   when the flag is 0; verify cycc==cycc byte-identical (Linux + ecb + cass + pi) after.
2. **[small] `lib/args.cyr` agnos accessor branch.** `args_init()` = no-op (the capture is bite 1, like
   `args_macos.cyr`); `argc()` = `load64(base)`; `argv(n)` = `load64(base + 8 + n*8)` where `base` =
   `_agnos_init_rsp`. Bound-check `n` against the argv NULL terminator (don't trust a fixed count).
3. **[trivial] `sys_chmod` no-op** in `lib/syscalls_x86_64_agnos.cyr` (NOT io.cyr — chmod lives in the
   per-arch syscall peers). `fn sys_chmod(path, mode): i64 { return 0; }`. agnos has no chmod in the
   frozen 0-33 surface; no-op-returning-0 is pre-authorized. Reachable via agnsh `history.cyr:118`.
4. **[medium — conditional on reachability, likely IN] `lib/io.cyr` file_* AO_* ABI bridge.** io.cyr's
   `file_open`/`file_read_all`/`file_write_all`/`file_exists` call Linux-shaped `sys_open(path,flags,
   mode)`; the agnos peer is `sys_open(name, namelen, ao_flags)` (AO_RDONLY=0x0/AO_WRONLY=0x1/
   AO_CREAT=0x100/AO_TRUNC=0x200/AO_APPEND=0x400). On agnos the Linux flags value lands in `namelen` →
   garbage; O_* bits ≠ AO_* bits. **Silent ABI miscompile (no ud2)** that breaks every file op. Funnel
   the wrappers through one agnos-only `_io_open(path,flags,mode)` that computes `namelen=strlen(path)` +
   maps O_*→AO_*. Verify the mapping vs `agnos-userland-abi.md §3.3` at implementation (RE-FREEZE rule).
5. **[trivial-small — conditional] `getenv` agnos behavior.** If io.cyr's `getenv` (`/proc/self/environ`)
   is on the compiled path, add an agnos branch returning 0 (agnos envp is empty by design; agnsh
   tolerates null HOME via fallbacks). Confirm which `getenv` is linked at slot entry.

### Carve-outs — NOT v6.0.53, named here so they aren't surprise `#UD`s

- **agnos process `exec` (process.cyr) — a SEPARATE LARGE ARC.** `exec_vec` (process.cyr:162) uses
  `sys_fork`+`sys_execve`, neither in the agnos peer → `ud2` when agnsh runs an external program
  (`security.cyr:121`). The agnos model is `sys_spawn(elf_addr, elf_size)` (in-memory ELF) + waitpid —
  substantial, its own arc. Boot-to-prompt does not need it. **Decision (slot entry):** leave as `ud2`,
  OR stub `exec_vec` to a graceful "not supported on agnos" return so an interactive `run` can't crash.
- **chrono time source.** `lib/chrono.cyr` uses raw `syscall(228,...)` clock_gettime + `syscall(35)`
  nanosleep — outside agnos 0-33 (no ud2; bogus values). agnos has no wall-clock/sleep syscall. Stub
  to a fixed/zero epoch (v1.0 precedent) — likely defer; lower severity (just unusable timestamps).
- **`sys_stat` sudo-path (`security.cyr:88`).** agnos peer `sys_stat` is 3-arg `(path,pathlen,statbuf)`
  with AgnosStat (no st_uid); agnsh calls 2-arg + reads st_uid. Silently misbehaves. agnos `getuid` is
  always-root → the check is moot; **likely fix consumer-side (guard verify_sudo_path off under agnos)**.
- **raw `syscall(60,...)` aborts** in `lib/vec.cyr`/`hashmap.cyr`/`tagged.cyr` error paths (Linux
  exit_group; agnos exit=syscall 0). Compiles; hits an undefined agnos syscall only on error paths.
  Optional rider: normalize to `sys_exit(n)`. (agnsh.cyr:404's own exit is consumer-side.)

### Confirmed NON-issues (don't spend slot time)
`alloc.cyr` already has an agnos branch (heap mmap(27) works); `syscalls.cyr` dispatches to the agnos
peer; string/fmt/str print helpers use `syscall(1,...)` (agnos SYS_WRITE=1, safe); io.cyr file_lock
family + fs.cyr are not on the agnsh path (leave Linux-gated; latent if agnsh ever lists dirs).

## agnos-side coordination (file back to the agnos agent — NON-blocking, no cyrius dependency)

1. `agnos-userland-abi.md` documents the syscall surface but NOT the init-stack/argc/argv exec
   contract (lives only in elf.cyr + a 1.40.7 comment). Should gain an "init stack at exec" section
   (same drift-prevention rationale the doc states for syscalls). cyrius does not edit it.
2. Empty envp + AT_NULL-only auxv is by design; if agnsh ever needs real env vars that's an agnos ABI
   addition. Out of scope.
3. No time/sleep syscall in 0-33; real audit timestamps would need an agnos syscall addition.

## Validation (the real test — the issue's repro)

```
cd agnoshi && cyrius update && cyrius build --agnos src/agnsh.cyr build/agnsh_agnos
cd ../agnos && sh scripts/build.sh && bash scripts/agnsh-smoke.sh   # OVMF + ext2
```
Expect an **agnsh prompt** instead of `#UD`/emergency-shell. agnoshi must re-vendor via `cyrius update`
AFTER the cyrius lib lands (vendored `agnoshi/lib/*` is stale until then — do NOT edit it directly).
Plus the standard gates: self-host byte-identical Linux+ecb+cass+pi (the bite-1 emit change is in the
self-host driver), `check.sh` green, snapshot-ping-pong mitigation after each `lib/*.cyr` edit.

## Open decisions (recommendations; finalized at v6.0.53 slot entry)

1. **io.cyr file_* bridge (bite 4) in .53?** — recommend YES (per "a bug ships complete"); confirm
   reachability empirically at slot entry. It's the medium-vs-medium-large variable.
2. **`sys_chmod` return 0 or -1?** — recommend 0 (suppresses agnsh's stderr warning).
3. **`exec_vec` on agnos** — recommend graceful "not supported" stub in .53 (so interactive `run`
   doesn't `#UD`); the full `sys_spawn` exec capability is a separate future arc.
4. **chrono** — recommend fixed-epoch stub later (defer); no `#UD` either way.
5. **`sys_stat`/verify_sudo_path** — recommend consumer-side guard in agnsh (flag-back, not cyrius work).
6. **raw `syscall(60)` abort normalization** — optional low-priority rider; bundle or track separately.
