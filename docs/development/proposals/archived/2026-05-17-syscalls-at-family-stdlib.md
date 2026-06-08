# Stdlib syscall wrappers: POSIX `*at()` family + symlink-aware peers

**Filed:** 2026-05-17 during kriya M2 (`touch`/`ln` implementation)
**Severity:** Stdlib gap — kriya M2 utilities are calling raw `syscall(N, …)` with magic numbers for filesystem ops that POSIX considers core. Not a blocker (the raw syscalls work), but every consumer touching the filesystem reinvents the wrapper.
**Affects:** `lib/syscalls_x86_64_linux.cyr`, `lib/syscalls_aarch64_linux.cyr` (the aarch64 peer already uses the `at`-family for `openat`/`newfstatat`/`mkdirat`/`unlinkat` internally — those wrappers just aren't exposed by name).
**Target slot:** v6.x — bundles with a larger syscall-stdlib expansion arc the next major absorbs (kriya as the low-level surfacer, with agnos as a likely future consumer of the same set). v5.11.x is the final 5.x minor (closeout at .68); single proposals don't earn quality-of-life patches in the absorber band when a v6.x arc will land them coherently. User direction 2026-05-17.

## Summary

The current stdlib exposes `sys_open`, `sys_stat`, `sys_mkdir`, `sys_rmdir`, `sys_unlink`, `sys_symlink`, `sys_readlink`, `sys_chmod`, `sys_access` — the "bare-name" POSIX wrappers. Missing from that list:

| Name | Linux syscall | Why a wrapper |
|---|---|---|
| `sys_link` | `link(2)` (SYS_LINK=86 x86_64, via `linkat` on aarch64) | Hard-link counterpart to `sys_symlink`. Required for `ln` without `-s`. |
| `sys_lstat` | `lstat(2)` (SYS_LSTAT=6 x86_64, via `newfstatat(AT_SYMLINK_NOFOLLOW)` on aarch64) | Stat that does NOT follow symlinks. Required everywhere a utility must distinguish "this is a symlink" from "this is what the link points at" — `ln -n`, `cp -P`/`mv`/`rm` traversal under ADR 0003, `find -type l`, every shell file-test. |
| `sys_rename` | `rename(2)` (SYS_RENAME=82 x86_64, via `renameat` on aarch64) | Required by `mv` (single-FS path). |

And the entire `*at()` family — none of these are exposed today:

| Name | Linux syscall | Why a wrapper |
|---|---|---|
| `sys_openat` | `openat(2)` SYS=257 | Foundation of TOCTOU-safe directory traversal. Per kriya ADR 0003: every recursive walk is `openat(parent_fd, name, O_NOFOLLOW \| O_DIRECTORY)`. Without this, cp/mv/rm cannot meet the safety property. |
| `sys_mkdirat` | `mkdirat(2)` SYS=258 | Symlink-safe directory creation during recursive copy. |
| `sys_fstatat` | `fstatat(2)` / `newfstatat(2)` SYS=262 | Combined with `AT_SYMLINK_NOFOLLOW`, the canonical lstat-during-walk. |
| `sys_unlinkat` | `unlinkat(2)` SYS=263 | `AT_REMOVEDIR` makes one syscall serve both `unlink` and `rmdir` during traversal. |
| `sys_linkat` | `linkat(2)` SYS=265 | Hard-link with explicit `AT_SYMLINK_FOLLOW` policy. kriya ADR 0003 requires this for `ln -P` semantics. |
| `sys_renameat` | `renameat(2)` SYS=264 (or `renameat2` SYS=316) | `mv` across the boundaries of an FD-rooted operation. |
| `sys_fchmodat` | `fchmodat(2)` SYS=268 | Symlink-aware chmod for the M3 utility. |
| `sys_utimensat` | `utimensat(2)` SYS=280 | Used by `touch` *today* via raw `syscall(280, …)` in [`kriya/src/cmd/touch.cyr`](https://github.com/MacCracken/kriya/blob/main/src/cmd/touch.cyr). Should be a stdlib wrapper. |

And the constants the `*at()` family needs:

| Constant | Value | Use |
|---|---|---|
| `AT_FDCWD` | `0 - 100` (`-100`) | "use cwd as the base dirfd" — every `*at()` call needs this for the rooted-at-cwd shape that matches the bare-name syscalls. |
| `AT_SYMLINK_FOLLOW` | `0x400` (1024) | `linkat`-only: follow source symlink (POSIX `link`'s usual semantics). |
| `AT_SYMLINK_NOFOLLOW` | `0x100` (256) | `fstatat` and `fchmodat`: don't follow. The kriya/POSIX policy default for safe walks. |
| `AT_REMOVEDIR` | `0x200` (512) | `unlinkat`: treat as `rmdir`. |
| `AT_NO_AUTOMOUNT` | `0x800` (2048) | Optional; rarely needed at userland. |
| `UTIME_NOW` | `(1 << 30) - 1` (1073741823) | `utimensat` "now". Used today as a literal in kriya/touch. |
| `UTIME_OMIT` | `(1 << 30) - 2` (1073741822) | `utimensat` "don't touch this side". Same. |

## Concrete consumer pain — what the gap looks like today

From `kriya/src/cmd/touch.cyr` (M2, 2026-05-17):

```cyrius
# What we wrote today, because stdlib has no sys_utimensat:
# UTIME_NOW  = (1 << 30) - 1 = 1073741823
# UTIME_OMIT = (1 << 30) - 2 = 1073741822
# AT_FDCWD = (0 - 100) per CLAUDE.md.
# SYS_UTIMENSAT = 280 on x86_64.
fn _touch_update_times(path, update_atime, update_mtime): i64 {
    ...
    var ts[32];
    store64(&ts + 0,  0);
    store64(&ts + 8,  1073741823);    # times[0].tv_nsec = UTIME_NOW
    store64(&ts + 16, 0);
    store64(&ts + 24, 1073741822);    # times[1].tv_nsec = UTIME_OMIT
    return syscall(280, 0 - 100, path, &ts, 0);
}
```

That code has three magic numbers (`280`, `1073741823`, `1073741822`) plus the `0 - 100` AT_FDCWD pattern. Each is documented in a comment, but every kriya utility that uses these touches the same magic numbers, and the same will be true of every Cyrius consumer (agnos, owl, cyim, sit, agnoshi) that walks the filesystem.

`kriya/src/cmd/ln.cyr` (in flight as of this filing) needs `linkat` for ADR 0003's `-P` policy, and the gap is wider — without `sys_linkat` we hand-roll the syscall plus the `AT_FDCWD` and `AT_SYMLINK_FOLLOW` constants.

The full M2 destructive surface (`cp`, `mv`, `rm`) makes this worse: every traversal step is an `openat(O_NOFOLLOW | O_DIRECTORY)` per ADR 0003. The kriya implementation will work either way, but every site emits magic numbers in the meantime.

## Proposed wrapper surface

```cyrius
# --- bare-name peers (missing today, would close the parity gap) ---
fn sys_link(oldpath, newpath): i64;
fn sys_lstat(path, buf): i64;
fn sys_rename(oldpath, newpath): i64;

# --- *at()-family ---
fn sys_openat(dirfd, path, flags, mode): i64;
fn sys_mkdirat(dirfd, path, mode): i64;
fn sys_fstatat(dirfd, path, buf, flags): i64;
fn sys_unlinkat(dirfd, path, flags): i64;
fn sys_linkat(olddirfd, oldpath, newdirfd, newpath, flags): i64;
fn sys_renameat(olddirfd, oldpath, newdirfd, newpath): i64;
fn sys_fchmodat(dirfd, path, mode, flags): i64;
fn sys_utimensat(dirfd, path, times, flags): i64;

# --- constants (new enums) ---
enum AtFlag {
    AT_FDCWD = 0 - 100;
    AT_SYMLINK_NOFOLLOW = 256;     # 0x100
    AT_REMOVEDIR        = 512;     # 0x200
    AT_SYMLINK_FOLLOW   = 1024;    # 0x400
    AT_NO_AUTOMOUNT     = 2048;    # 0x800
}

enum Utime {
    UTIME_NOW  = 1073741823;       # (1 << 30) - 1
    UTIME_OMIT = 1073741822;       # (1 << 30) - 2
}
```

All wrappers return Linux syscall convention (`<0` is `-errno`).

### Per-arch implementation note

The bare-name peers (`sys_link`, `sys_lstat`, `sys_rename`) need the arch-split treatment already established for `sys_stat`:

- **x86_64**: bare `SYS_LINK=86`, `SYS_LSTAT=6`, `SYS_RENAME=82` syscalls.
- **aarch64**: route through `linkat(AT_FDCWD, …, AT_FDCWD, …, 0)`, `newfstatat(AT_FDCWD, path, buf, AT_SYMLINK_NOFOLLOW)`, `renameat(AT_FDCWD, …, AT_FDCWD, …)`. aarch64 dropped the bare-name variants from the generic syscall table; we already do this for `sys_stat`/`sys_open` per the file's existing comments.

The `*at()` wrappers are uniform across arches — both syscall tables expose them by the same number. The bare-name peers go in the per-arch peer files; the `*at()` wrappers can live in either.

## Why not just keep using raw `syscall(N, …)` in consumers

- **Numeric drift risk.** `sys_stat` v5.8.6 history is documented in the stdlib file: "Pre-v5.8.6, x86_64's stdlib defined the SYS_STAT (4) / SYS_FSTAT" — that drift broke aarch64 builds silently. Every raw syscall in a consumer is a place that can regress on a number change without compile-time signal.
- **Per-arch portability lives in stdlib.** The aarch64 peer's whole purpose is to route bare-name calls through the at-family for arches that dropped the bare-name syscalls. Consumers that write raw `syscall(SYS_LINK, …)` are silently x86_64-only.
- **Constants-as-magic.** `AT_FDCWD = -100` is mythology that every consumer learns once and forgets. A stdlib enum keeps it in one place.
- **Documentation surface.** A wrapper is grep-able (`fn sys_linkat`); a raw `syscall(265, …)` is not. Discoverability matters when six kindred Cyrius repos start writing fs code.

## Why not auto-generate from syscall.h

C's `<linux/fcntl.h>` and `<sys/syscall.h>` could in principle be parsed to produce these. Cyrius's stdlib pattern is hand-curation — wrappers expose only the constants and shapes the language actually wants — and that's worth preserving. The proposed surface is the minimum kriya M2 needs; future additions land per-consumer-request, same as today.

## Test plan

Cyrius's existing stdlib syscall tests cover `sys_open`/`sys_stat`/`sys_unlink` end-to-end. The new wrappers get the same shape:

1. **Round-trip per wrapper.** `sys_link` → file exists at new name → `sys_lstat` returns the same inode. Negative path: source missing → `-ENOENT`.
2. **Cross-arch fixpoint.** Build on x86_64 and aarch64; the bare-name peers route through different syscalls per arch but produce identical observable behaviour.
3. **AT_SYMLINK_NOFOLLOW correctness.** `sys_fstatat(AT_FDCWD, link, buf, AT_SYMLINK_NOFOLLOW)` returns the link's metadata; without the flag, returns the target's.
4. **UTIME_OMIT correctness.** `sys_utimensat` with one side `UTIME_OMIT` leaves that timestamp unchanged.
5. **AT_REMOVEDIR.** `sys_unlinkat(AT_FDCWD, emptydir, AT_REMOVEDIR)` removes an empty dir; `0` for the flags fails with `-EISDIR`.

## Alternatives considered

### Stub a single `sys_syscall(num, ...)` and require consumers to wrap themselves

Cyrius already has `syscall(N, …)` as a primitive. The proposal here is named wrappers, not new capability. Forcing consumers to wrap is the status quo, and the cost is the magic numbers documented above.

**Rejected** — the value of stdlib is consistency. If kriya/agnos/owl/cyim each grow their own `_my_link(a, b)` wrapper, they will not be identical, will not benefit from per-arch portability fixes in stdlib, and will not get a free `sys_link` rename if the kernel ever moves to `linkat`-only.

### Add only what kriya M2 immediately needs (`sys_link`, `sys_utimensat`, `sys_lstat`)

Smaller surface, faster to land. The risk is the next M2 utility (`cp`) immediately needs `sys_openat` + `sys_mkdirat` + `sys_unlinkat`, and the M2-after (`mv`, `rm`) extends the gap further. Six wrappers landing one per PR is more churn than the whole at-family landing once.

**Rejected unless the stdlib grooming budget demands the staged path** — bundling has measurable lower aggregate cost.

### `linkat`-only API (drop `sys_link`, force the at-family everywhere)

Cleanest target, but kriya's `mkdir`/`rmdir`/`touch`/`ln` non-recursive call sites don't *need* the at-family. The bare-name wrappers are the everyday shape; the at-family wrappers are the traversal-safe shape. Both shapes have callers.

**Rejected** — keep both, document when to use which.

## Work breakdown

1. **Decide per-arch peer placement.** `*at()`-family wrappers go in `lib/syscalls_common_linux.cyr` if such a file exists, else duplicate (small) in each peer. Match the existing pattern for `sys_open`/`sys_stat`.
2. **Add the bare-name peers** (`sys_link`, `sys_lstat`, `sys_rename`) in each arch peer file. x86_64 calls bare syscalls; aarch64 routes through the at-family. Mirror the existing `sys_stat` / `sys_open` precedent.
3. **Add the `*at()`-family wrappers.** Same shape, same arch dispatch (the at-family uses identical syscall numbers across x86_64 and aarch64 generic-table, so this is uniform).
4. **Add the `AtFlag` and `Utime` enums.** Place in `syscalls_x86_64_linux.cyr` / aarch64 peer; the enum values are arch-independent ABI-stable Linux constants.
5. **Update stdlib tests.** Round-trip + cross-arch fixpoint per the test plan.
6. **CHANGELOG.** Entry under the version that lands.
7. **vidya documentation.** Update `vidya/content/cyrius/stdlib/syscalls.toml` (or wherever stdlib surface is catalogued) so downstreams (kriya, agnos, owl, cyim, sit, agnoshi) can grep for the wrappers when they need them.
8. **kriya follow-up (separate PR in `kriya`).** Once the wrappers land, sweep `kriya/src/cmd/touch.cyr` to use `sys_utimensat` and the `AtFlag`/`Utime` enum constants; same for `ln.cyr` and the rest of M2 as it ships.

## Open questions

- **`renameat2(SYS=316)` instead of `renameat`?** `renameat2` adds the `RENAME_NOREPLACE` / `RENAME_EXCHANGE` flags, both genuinely useful for atomic deploy patterns. Recommendation: ship `sys_renameat` (the unconditional rename) first, and add `sys_renameat2` when a consumer asks. Keep `sys_rename` aligned with `rename(2)` POSIX semantics for predictability.
- **`statx(2)`?** Strictly more powerful than `fstatat`. Same answer: ship the POSIX-shaped wrapper first; `sys_statx` lands when something needs the extended fields.
- **Should `AT_FDCWD` be in `AtFlag` or its own constant?** `AtFlag` is fine; `AT_FDCWD` isn't a flag *to* a syscall but a dirfd value, and consumers reach for it in the same `AT_*` mental space anyway. Group it.

## Decision required

- [ ] Approve the bundled `*at()`-family + bare-name-peer + constants addition.
- [ ] Approve per-arch routing (x86_64 bare-name + at-family; aarch64 routes bare-name through at-family).
- [ ] Approve targeted slot — v5.11.x patch or v6.x bundle, whichever has stdlib-grooming budget first.

Promote to an ADR if approved before implementation; the "bare-name vs at-family parity" framing is durable language-design content.

## Cross-references

- First concrete consumer (the magic-number tax): kriya `touch` 2026-05-17 (`syscall(280, 0 - 100, path, &ts, 0)`).
- Adjacent open proposal: [`2026-05-17-octal-literal-syntax.md`](2026-05-17-octal-literal-syntax.md) — same kriya-M2 origin; both proposals share the "stop hand-rolling things stdlib should expose" theme.
- kriya ADR 0003 (symlink-follow policy) requires `openat(O_NOFOLLOW | O_DIRECTORY)` for the cp/mv/rm traversal. Implementing that ADR without `sys_openat` means raw syscalls in every traversal site.
- Stdlib precedent for arch-split bare-name routing: `sys_open` / `sys_stat` in `syscalls_x86_64_linux.cyr` header comments (the SYS_STAT v5.8.6 incident).
