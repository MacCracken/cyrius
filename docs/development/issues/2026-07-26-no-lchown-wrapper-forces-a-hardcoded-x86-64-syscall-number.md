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
