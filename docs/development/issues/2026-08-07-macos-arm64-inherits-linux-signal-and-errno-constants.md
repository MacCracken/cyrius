# macOS-arm64 inherits Linux signal / errno / mmap constant VALUES, and no translation layer can catch it

**Filed:** 2026-08-07
**Reporter:** cyrius (found while fixing `MAP_ANONYMOUS` for v6.5.11)
**Cyrius version:** 6.5.11
**Affected:** `lib/syscalls.cyr:64-71` (the macOS-arm64 peer selection), `lib/syscalls_aarch64_linux.cyr` (the `Signal` / errno enums it exports to Darwin)
**Status:** ✅ **FIXED in v6.5.15** — all ten split per-OS in `lib/syscalls_aarch64_linux.cyr`
(mirroring the `Stat` precedent already in that file), **re-probed on real ecb after the fix: all
ten now resolve to the Darwin column.** Gated by `tests/tcyr/crossos/signal_errno_peer_values.tcyr`,
which runs on ecb/ach/cass/pi via the release gate and is **mutation-proven** (putting Linux's
SIGCHLD=17 back into the Darwin arm turns ecb red at 12/1, naming the assertion).
⭐ Two extras the filing's table did not list, both found by re-deriving the divergence set
preprocessor-aware rather than by grepping: **`SIGPWR` was 30 on the Darwin side, which IS Darwin's
`SIGUSR1`** — so `kill(pid, SIGPWR)` silently delivered SIGUSR1; it is now inert `0`, matching the
`MAP_STACK = 0` precedent for a flag the OS does not have. And `MAP_ANONYMOUS` is now correct in
the PEER too, not only in `lib/mmap.cyr`'s shadowing declaration, so both include orders are right.
aarch64-**Linux** is byte-for-byte unchanged (verified by cross-compiling the same probe and running
it under qemu: every Linux value preserved), so pi cannot regress.
*(Historical status below.)* 🟡 OPEN — measured on real ecb (macOS 26.5.2, arm64) at v6.5.11. **7 constants confirmed wrong.**
**Severity:** Medium. No *currently gated* consumer reads them, which is precisely why it has survived — see "Why nothing is red today".
**Related:** `2026-07-03-macos-threading-workers-dont-run` (the signal constants are a prerequisite for any real macOS thread/signal work, but that issue is scoped to the missing `thread_macos.cyr` backend and does **not** cover these values). Archived precedent — `2026-06-17-io-cyr-o-flags-not-darwin-translated` is the SAME class, third occurrence.

## The mechanism

`lib/syscalls.cyr:64-71` selects the constant peer for macOS by **arch**:

```
#ifdef CYRIUS_TARGET_MACOS
#ifdef CYRIUS_ARCH_X86
include "lib/syscalls_macos.cyr"          # Darwin values
#endif
#ifdef CYRIUS_ARCH_AARCH64
include "lib/syscalls_aarch64_linux.cyr"  # ← LINUX values, on Darwin
#endif
#endif
```

On **macOS-arm64** the stdlib therefore imports the *Linux aarch64* peer wholesale. That is a
deliberate, documented compromise (`syscalls.cyr:46-63`): the backend's `ESYSXLAT` renumbers Linux
syscall NUMBERS to BSD, so feeding it Linux numbers is correct by design.

⛔ **But `ESYSXLAT` renumbers SYSCALL NUMBERS ONLY. It never touches VALUES.** Any constant that is
an argument, an errno, a signal number, or a struct offset passes through to the Darwin kernel
verbatim. Where Linux and Darwin disagree on such a value, macOS-arm64 is simply wrong, and there is
no layer that could ever notice.

## Measured — real hardware, not a source diff

⚠ **Do not derive this list by grepping the peer files.** `syscalls_aarch64_linux.cyr` carries its
own `#ifdef CYRIUS_TARGET_MACOS` arm (`:426-436`), so a naive parse reads the wrong branch and
produces a table that is substantially wrong — a first pass at this issue claimed 18 divergences
including the whole `STAT_*` family, and **the `STAT_*` family is correct**. These values come from
compiling a constant-reporting probe with the native codesigned `r1r` on ecb and running it:

| constant | macOS-arm64 resolves to | Darwin truth | status |
|---|--:|--:|:-:|
| `EAGAIN` | **11** | **35** | ❌ wrong |
| `SIGCHLD` | **17** | **20** | ❌ wrong |
| `SIGCONT` | **18** | **19** | ❌ wrong |
| `SIGSTOP` | **19** | **17** | ❌ wrong |
| `SIGUSR1` | **10** | **30** | ❌ wrong |
| `SIGUSR2` | **12** | **31** | ❌ wrong |
| `SIG_BLOCK` | **0** | **1** | ❌ wrong |
| `SIG_SETMASK` | **2** | **3** | ❌ wrong |
| `SIG_UNBLOCK` | **1** | **2** | ❌ wrong |
| `MAP_STACK` | **131072** | **0** | ❌ wrong (Darwin has no `MAP_STACK`) |
| `MAP_ANONYMOUS` | 4096 | 4096 | ✅ **fixed v6.5.11** |
| `STAT_SIZE` | 96 | 96 | ✅ correct |
| `STAT_MODE` | 4 | 4 | ✅ correct |
| `STAT_UID` | 16 | 16 | ✅ correct |
| `STAT_MTIME` | 48 | 48 | ✅ correct |

`SIGSTOP` / `SIGCHLD` are the sharpest pair: they are not merely different numbers, they are
**swapped-ish** across the two systems (Linux 17/19 vs Darwin 20/17), so a wrong value does not
fail — it signals the *wrong thing*. Sending `SIGSTOP` on macOS-arm64 today sends **17 = SIGSTOP on
Darwin by luck**, but `SIGCHLD` 17 means a process waiting on child-exit is watching Darwin's
`SIGSTOP` instead.

## Why nothing is red today

- No macOS thread backend exists (`2026-07-03-macos-threading-workers-dont-run`), so the signal
  constants have no live consumer on that target.
- `signal_ignore` (`syscalls.cyr:94+`) hardcodes `SIGPIPE = 13`, which happens to be 13 on both.
- `EAGAIN` is compared against negated syscall returns in non-blocking paths that the gated corpus
  does not exercise on macOS.

That is the whole risk: **this becomes wrong the moment macOS concurrency work starts** — i.e. at
Slot 11, which is exactly when someone will be debugging a thread backend and will not suspect the
constants. Fixing it before that arc opens removes a false trail from it.

## Precedent — this is the third occurrence of one shape

1. **v6.2.17** — `lib/io.cyr` redefined `O_CREAT`/`O_TRUNC`/`O_APPEND` with Linux values *after*
   including `syscalls.cyr`; last-def-wins overrode Darwin's `0x200`. File writes failed on
   arm64-macOS. (`2026-06-17-io-cyr-o-flags-not-darwin-translated`, archived.)
2. **v6.2.17** — `sakshi/src/output.cyr` hardcoded the Linux literal `1089`.
3. **v6.5.11** — `lib/mmap.cyr` declared `MAP_ANONYMOUS = 32` unguarded; on macOS every
   `MAP_PRIVATE | MAP_ANONYMOUS` became a FILE mapping with `fd = -1` ⇒ `EBADF`, so `mmap_anon()`
   returned 0 for every caller.

Each was fixed as a one-off at the call site. The **generator** — macOS-arm64 importing a Linux
constant peer — was never addressed, so the class keeps producing instances.

## Options (maintainer's call — this is why it is filed, not fixed)

1. **Darwin constant peer for arm64.** Split the Darwin *values* out of `syscalls_macos.cyr` (today
   x86-shaped) into an arch-neutral file and include it on macOS-arm64 *after* the Linux peer, so
   the Darwin values win by last-def-wins. Smallest change; keeps the "Linux syscall numbers +
   ESYSXLAT" contract intact, which CLAUDE.md mandates.
2. **Per-target `#ifdef` arms inside `syscalls_aarch64_linux.cyr`**, matching what it already does
   for `Stat` at `:426`. Consistent with existing practice in that file, but grows a file whose
   name says "linux".
3. **Do nothing until Slot 11**, accepting that macOS concurrency opens with known-bad constants.

⚠ Whichever is chosen, it needs a **gate that asserts VALUES on real hardware** —
`tests/tcyr/crossos/mmap_anon_flag.tcyr` (v6.5.11) is the pattern: it asserts the resolved constant,
not just that a call succeeded, precisely because on Linux the wrong value is the right value and a
host-side test can never see the defect.

## Incidental find

`lib/syscalls.cyr:61` reads *"Tracked as the macОS tool-surface follow-up"* — the `О` is **U+041E
CYRILLIC CAPITAL LETTER O**, not ASCII. `grep "macOS tool-surface"` finds nothing, so the pointer
reads as a live reference while being unfindable. No such follow-up issue exists in
`docs/development/issues/` (open or archived); this file is now the closest thing to it. Fix the
character when this area is next touched.
