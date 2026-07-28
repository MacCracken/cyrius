# No `lchown`/`fchownat` wrapper, so consumers hardcode an x86_64 syscall number that is `exit_group` on aarch64

**Discovered:** 2026-07-26, during an adversarial review of stiva 3.0.15
**Severity:** Medium for the stdlib (a missing wrapper); **High for any consumer that works around it**
**Affects:** cyrius 6.4.78's vendored syscall layer; earlier versions unverified

## Summary

`lib/syscalls_*_linux.cyr` exposes no `sys_lchown` wrapper and no `SYS_LCHOWN` / `SYS_FCHOWNAT`
constant. A consumer that needs to change ownership without following a symlink — which is every
container runtime unpacking a tar layer — has no portable option and ends up writing the raw x86_64
number:

```
fn _stor_lchown(path, uid, gid) { return syscall(94, path, uid, gid); }
```

**94 is `lchown` on x86_64 and `__NR_exit_group` on aarch64.** The consumer does not fail, does not
warn, and does not return an error: the process **terminates silently**, with the path pointer's
low byte as the exit status.

## Reproduction

In stiva (verified by execution, `cyrius build --aarch64` + `qemu-aarch64`):

```
x86_64 :  stiva load img.tar   -> "Loaded 1 image(s)", rc=0
aarch64:  stiva load img.tar   -> (no output), rc=16
```

`qemu-aarch64 -strace` shows the run ending immediately after the first tar entry with
`exit_group(2125840)` — that is the `path` argument reinterpreted as an exit code
(`2125840 & 0xff == 16`).

The same shape reproduces standalone:

```
# built twice, once per target
var r = syscall(94, "/tmp/some-file", 0, 0);
print("after");          # printed on x86_64; never reached on aarch64
```

## Why the consumer cannot fix this itself

Three options, all bad:

1. **Hardcode a second literal behind an arch conditional.** stiva has no `#ifdef` anywhere in its
   domain modules, and introducing one to work around a missing stdlib wrapper puts the per-arch
   syscall table in the wrong repository — it will drift the moment a third arch appears.
2. **Use `SYS_*` constants.** There are none for this call. `SYS_CHDIR` *is* defined per-arch
   (x86_64 49/80, aarch64 49), which is exactly why the sibling `chdir` bug in the same file was
   fixable and this one was not.
3. **Skip ownership restoration.** Changes behaviour: uid/gid in the layer would be silently
   dropped rather than best-effort applied.

stiva has therefore left the call as-is with its consequence documented, and treats aarch64 as a
non-working target.

## Proposed fix

Add a wrapper alongside the existing ones in `lib/syscalls_linux_common.cyr`:

```
fn sys_lchown(path, uid, gid): i64 { … }     # or
fn sys_fchownat(dirfd, path, uid, gid, flags): i64 { … }
```

`fchownat` is the better primitive — it is the modern call, it is present on every Linux arch
(x86_64 260, aarch64 54), and `AT_SYMLINK_NOFOLLOW` gives `lchown` semantics — and `AT_FDCWD` is
already defined and used by `sys_lstat`'s aarch64 implementation.

Failing that, per-arch `SYS_FCHOWNAT` constants would be enough; the consumer can then write the
`syscall(SYS_FCHOWNAT, …)` form the way it already writes `syscall(SYS_CHDIR, …)`.

## Wider point, offered as a suggestion rather than a request

This is the second instance of the same class found in one review. The other two were consumer
bugs fixable in the consumer, because the stdlib *did* expose the right thing and the consumer had
not used it:

- `syscall(157, 38, 1, …)` for `prctl` — 157 is `prctl` on x86_64, **`setsid` on aarch64**.
  `sys_prctl` already existed; the consumer just was not using it.
- `syscall(80, workdir)` for `chdir` — 80 is `chdir` on x86_64, **`fstat` on aarch64**.
  `SYS_CHDIR` already existed.

Both were silent: no crash, no error, just the wrong syscall. `lib/syscalls.cyr`'s own header
documents this drift class as a previously-fixed regression, which suggests it recurs.

A lint that flags a bare integer literal as the first argument of `syscall()` — "use the `SYS_*`
constant or a wrapper" — would have caught all three at authoring time, and would catch the next
one. Offered as a suggestion; the call on whether it is worth the false-positive rate is yours.

---

## RE-SCOPED UPWARD — v6.4.x closeout audit, 2026-07-27

**Verdict: KEEP-OPEN, and the scope is wider than the filing.** Per CLAUDE.md, *a consumer filing
enumerates what it HIT, not the class* — so the class was checked. Two corrections and two hazards.

### 1. The whole chown family is absent from **all six** syscall peers, not just `lchown`

```
$ grep -rn 'chown\|CHOWN' lib/*.cyr
(only three agnos GPU-band comments: syscalls_x86_64_agnos.cyr:106, :107, :731)
```

**Zero wrappers and zero `SYS_` constants** across `syscalls_x86_64_linux.cyr`,
`syscalls_aarch64_linux.cyr`, `syscalls_linux_common.cyr`, `syscalls_macos.cyr`,
`syscalls_windows.cyr`, `syscalls_x86_64_agnos.cyr`.

Authoritative numbers from this box's kernel headers — x86_64 (`asm/unistd_64.h:96-98,264`):
`chown=92`, `fchown=93`, **`lchown=94`**, `fchownat=260`. aarch64 (`asm-generic/unistd.h:154-156`):
**`fchownat=54`, `fchown=55`, and no `chown`/`lchown` at all**; `:260` → **`exit_group=94`**.

So the filing's "94 is `lchown` on x86_64 and `exit_group` on aarch64" is **exactly right**.
*Correction to how this was summarised elsewhere:* the hardcoded number is **94, not 92** — aarch64
92 is `personality`.

The template to copy is `sys_fchmodat` at `lib/syscalls_linux_common.cyr:80-83`. `lchown` semantics =
`AT_FDCWD` + `AT_SYMLINK_NOFOLLOW`, both already defined at `syscalls_linux_common.cyr:38/:48`.

### 2. ⚠ HAZARD — `SYS_FCHOWNAT = 54` on aarch64 is silently remapped to `setsockopt`

The aarch64-Linux leg of `ESYSXLAT` matches `x8==54` unconditionally:
`src/backend/aarch64/emit.cyr:840` `# setsockopt 54→208` (and the macho leg at `:719`, 54→105). The
correct aarch64-native `fchownat` number **is** 54, so a peer-native `SYS_FCHOWNAT = 54` gets
rewritten to 208/105.

The shim cannot simply be dropped: there is a live raw caller, `lib/yantra.cyr:453`
`return syscall(54, fd, 6, 1, one, 4);` — a bare-literal x86 `setsockopt`/TCP_NODELAY, and itself an
instance of the bare-syscall-literal class this filing's "wider point" asks to lint.

The other obvious numbering collides too: the aarch64-macho leg already claims **260** as a source
(`# wait4 260→7`).

**This is the verbatim v6.4.64 collision class.** `lib/syscalls_aarch64_linux.cyr:174-178` documents
it in its own words for the 51/52 pair: *"x86-52 collides with this peer's own `SYS_FCHMOD = 52`, and
an ESYSXLAT entry for it would remap fchmod to getpeername (CI caught exactly that: sandbox_syscalls
RED on pi)"*. Picking either number without resolving this reproduces that bug, **silently**, and the
release gate's `vr01_` subset would very likely not catch it.

*Resolution path:* fix `lib/yantra.cyr:453` to use `SYS_SETSOCKOPT` (x86 54 / aarch64 208) first; the
`54→208` shim then has no consumer and aarch64-native 54 becomes safe for `fchownat`.

### 3. ⚠ HAZARD — agnos 92/93 are **already** the GPU band

`lib/syscalls_x86_64_agnos.cyr:106` `SYS_GPU_SHADER_OP = 92;` and `:107` `SYS_GPU_MODESET_OP = 93;`.
The file's own notes at `:731`/`:741-745` already reason about this overlap in the other direction.
agnos is the one target where a chown number is not merely wrong but points at a **live,
side-effecting GPU primitive that reads arg1 as a userland VA**. Give the agnos peer an explicit
`-ENOSYS` stub; never let it inherit the Linux common wrapper.

### 4. Darwin numbers are NOT verifiable from this box — read them off the hardware

`lib/syscalls_macos.cyr` uses **x86_64 Linux numbers** by convention and relies on emit-time
translation (`:115` `SYS_FSYNC = 74;  # EMACHO_SYSXLAT maps 74→BSD 95`). `EMACHO_SYSXLAT`
(`src/backend/x86/emit.cyr:836-885`) has no entry for 260 or 92/93/94 today, so adding a constant
without the translation entry means the call reaches Darwin **untranslated** — the exact failure mode
documented at `emit.cyr:877-882`. Read the numbers off ecb/ach directly
(`grep -i chown /usr/include/sys/syscall.h`), then add both the `_msx()` entry and the matching
`cmp x8,#N` in the `_TARGET_MACHO == 2` branch of the aarch64 `ESYSXLAT`. Both legs, or macOS-arm64
and Intel-Mac diverge.

### 5. Same class, found in passing: `sys_chdir` is called but **defined nowhere**

`lib/regression.cyr:658` calls `sys_chdir(work_dir)` inside `regression_exec_in_dir3`. There is no
`fn sys_chdir` anywhere in `lib/` or `src/` — only the `SYS_CHDIR` **constants** (x86 80, aarch64 49,
macOS 80). A full sweep of `sys_*` called-vs-defined across `lib/`, `src/`, `programs/`, `cbt/` returns
exactly one genuinely undefined name: this one.

cycc classifies the call site as unreachable in the checks program (which uses its own
`_exec_in_dir` with `syscall(SYS_CHDIR, …)` and *checks the return*), so it only warns. But any
consumer that actually calls `regression_exec_in_dir3` gets
`error: refusing to emit binary with 1 reachable undefined function(s)` — **a shipped stdlib helper
that cannot be compiled by the consumers it ships to.** `lib/regression.cyr` goes out via
`cyrius deps`.

Fold `sys_chdir` into whatever wrapper pass fixes the chown family — same missing-wrapper class, same
per-arch constant-exists-but-no-wrapper shape.

### Placement

v6.5.x, as one "missing syscall wrappers" pass covering `fchownat`/`fchown`/`lchown`-semantics +
`sys_chdir`. Gate it with a `vr01_`-named tcyr so the cross-OS leg actually executes it on pi.
**Not 7.x.**
