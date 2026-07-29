# yukti has never worked on agnos — 6 syscall arity mismatches, 3 of them a design question

**Status:** ✅ **RESOLVED v6.5.2** — yukti **2.3.0** fixed upstream then re-vendored.
Option 2 was taken (fail closed on agnos, `_yk_mount` → `-ENOSYS`) rather than option 1
(a real agnos 5-arg `sys_mount`), because option 1 is an agnos-side kernel ABI commitment
that is not yukti's to make; if agnos gains real mount support, delete the one `#ifdef`
branch. `sys_stat`/`sys_unlink`/`sys_rmdir` moved to `xstat`/`xunlink`/`xrmdir` — the last
of which did not exist and was added to `lib/io.cyr` for this release. `lib/yukti.cyr`
builds clean for agnos (was 6 errors); yukti 653 tests pass. Acceptance criterion 4's wider
point is also addressed: `tests/folds_agnos_parity.sh` now builds 11 of 12 folded stdlibs
for agnos, so this class cannot recur silently.
**Severity:** **Medium–High.** Nothing regresses *because* of this — it has been broken the
whole time — but `sys_mount` silently no-op'd on agnos, which is the worst failure shape:
a container/mount layer that reports success and mounts nothing.
**Shipped:** v6.5.2 (cyrius) / yukti 2.3.0.

## What

Compiling `lib/yukti.cyr` for agnos fails with six arity errors. All six pre-date v6.5.1;
that release only escalated an arity mismatch from a *warning* to an error, so they became
visible instead of silent.

```
$ printf 'include "lib/syscalls.cyr"\ninclude "lib/yukti.cyr"\nfn main(): i64 { return 0; }\n' \
    | CYRIUS_TARGET_AGNOS=1 build/cycc > /tmp/yk.bin
error:lib/yukti.cyr:875   'sys_stat'   expects 3 arguments, got 2
error:lib/yukti.cyr:1792  'sys_mount'  expects 0 arguments, got 5
error:lib/yukti.cyr:1808  'sys_mount'  expects 0 arguments, got 5
error:lib/yukti.cyr:1852  'sys_rmdir'  expects 2 arguments, got 1
error:lib/yukti.cyr:3733  'sys_unlink' expects 2 arguments, got 1
error:lib/yukti.cyr:4703  'sys_mount'  expects 0 arguments, got 5
$ echo $?  # 1, and 0 bytes emitted
```

None of these call sites is inside a `CYRIUS_TARGET_AGNOS` guard — the nearest preceding
agnos directive is the `#endif` at `lib/yukti.cyr:73`.

## Root cause — two different problems wearing the same error message

**(a) The length-carrying mismatch — mechanical.** agnos's raw syscall wrappers take explicit
`(ptr, len)` pairs because the agnos kernel does not walk NUL-terminated strings at the
syscall boundary. Every other target takes a bare pointer:

| wrapper | Linux x86-64 / aarch64 / macOS / Windows | agnos |
|---|---|---|
| `sys_unlink` | `(path)` | **`(path, pathlen)`** |
| `sys_rmdir` | `(path)` | **`(path, pathlen)`** |
| `sys_stat` | `(path, statbuf)` | **`(path, pathlen, statbuf)`** |

The fix is to route through the portable bridges in `lib/io.cyr` (`xunlink` already carries
exactly the right agnos branch), or to measure the path at the call site under an `#ifdef`.

**(b) `sys_mount` — NOT mechanical, and this is what blocks the issue.** agnos's is a
0-parameter no-op stub:

```cyrius
# lib/syscalls_x86_64_agnos.cyr:479
# Mount (stub / no-op today). Returns 0.
fn sys_mount(): i64 { return syscall(SYS_MOUNT); }
```

yukti calls it with five arguments at three sites. Those arguments were silently discarded
and the stub returns **0**, which yukti reads as success — verified at `lib/yukti.cyr:1823`:

```cyrius
var r = sys_mount(dev_path_cstr, mount_cstr, fs_try, flags, 0);
if (r == 0) {
    sakshi_span_exit();
    var dev_id = device_id_new_cstr(dev_path_cstr);
    return Ok(mount_result_new(dev_id, str_from(dev_path_cstr), str_from(mount_cstr), ...
```

So on agnos this does not merely fail quietly — it **fabricates an `Ok(mount_result_new(...))`
for a mount that never happened**, and every caller downstream believes it has a mounted
filesystem. The sibling site at `:1807` has the same shape via `if (r < 0)`.

There is no correct mechanical repair, because the two sides disagree about whether agnos has
a mount ABI at all.

## The decision that was needed — RESOLVED: option 2 was taken

Pick one:

1. **Give agnos's `sys_mount` a real 5-argument signature** matching the Linux shape, and
   implement or stub it honestly kernel-side (returning `-ENOSYS` rather than 0). Correct
   long-term; needs an agnos-side change and a syscall-number/ABI commitment.
2. **Gate yukti's mount path off on agnos** with `#ifdef CYRIUS_TARGET_AGNOS` + an explicit
   `Err(_NOT_SUPPORTED)`. Honest immediately, no agnos change, but concedes that yukti's
   mount features do not exist on agnos.

Either way the fix lands **upstream in `~/Repos/yukti` first**, then version-bump → regen
dist → re-vendor into `lib/yukti.cyr`. A fix applied only to the vendored copy evaporates at
the next re-vendor.

**Resolution: option 2.** Option 1 would have committed agnos to a mount ABI that its
kernel does not implement, which is not yukti's call to make. `_yk_mount` fails closed with
`-ENOSYS` on agnos and passes through on POSIX; if agnos later gains real mount support,
deleting one `#ifdef` branch is the whole change.

## Acceptance criteria

1. `include "lib/yukti.cyr"` compiles clean under `CYRIUS_TARGET_AGNOS=1` — 0 errors.
2. Whichever option is chosen, `sys_mount` on agnos must **not** return 0 for a mount that
   did not happen. Silent success is the actual defect; a clean error is a fix.
3. Fixed upstream in `~/Repos/yukti`, version-bumped, dist regenerated, re-vendored — and
   `cmp lib/yukti.cyr ~/Repos/yukti/dist/yukti.cyr` is identical afterwards.
4. A gate that compiles `lib/yukti.cyr` for agnos, mutation-proven by reverting one call site.
   Note the wider gap this exposed: **no gate compiles the folded stdlibs for agnos at all**,
   which is why six errors sat in a shipped module. Consider a sweep that builds every
   `lib/*.cyr` for every target rather than a yukti-specific gate.
5. Sweep the other 11 folds for the same class while in there — `lib/sigil.cyr:415` was
   checked at filing time and is correctly `#ifndef CYRIUS_TARGET_AGNOS`, the rest were not
   audited.
