# Cyrius: `lib/async.cyr` references `SYS_EPOLL_WAIT` unconditionally — undefined on aarch64

**Filed:** 2026-05-10
**Reporter:** daimon (AGNOS agent orchestrator, v1.2.0+)
**Cyrius version at time of report:** 5.10.34 (also reproduced at 5.10.47)
**Affected stdlib:** `lib/async.cyr`, `lib/syscalls_aarch64_linux.cyr`
**Severity:** **P2** — daimon's primary x86_64 path is unaffected; aarch64 cross-build (best-effort lane) fails. CI tolerant via warn-on-detect. No security impact.
**Status:** open. **Expected target:** the slot that next touches `lib/async.cyr` or aarch64-syscall surface, or any v5.10.x patch with capacity for a one-line stdlib fix.

## Summary

`lib/async.cyr` at two call sites (lines 117 + 145) references the
syscall constant `SYS_EPOLL_WAIT` unconditionally:

```cyr
117:    syscall(SYS_EPOLL_WAIT, epfd, &revents, 1, 0 - 1);
145:    var nr = syscall(SYS_EPOLL_WAIT, epfd, &revents, 1, ms);
```

`SYS_EPOLL_WAIT` is defined in `lib/syscalls_x86_64_linux.cyr` line 64
as `232` (the x86_64 Linux syscall number for `epoll_wait`) but is
**not** defined in `lib/syscalls_aarch64_linux.cyr` — because aarch64
Linux has no plain `epoll_wait` syscall. The aarch64 ABI uses
`SYS_EPOLL_PWAIT = 22` (with a NULL sigmask + 8-byte sigsetsize) which
the aarch64 syscalls module defines on line 108 and uses via wrapper
on line 590.

The result is `lib/async.cyr` compiles cleanly on x86_64 but fails on
aarch64 with:

```
error:21433: undefined variable 'SYS_EPOLL_WAIT' (missing include or enum?)
compile <consumer>/src/main.cyr -> build/<consumer>-aarch64 [aarch64] FAIL
```

Any consumer that `include`s `lib/async.cyr` and builds with
`cyrius build --aarch64` hits this.

## Repro

Minimal:

```cyr
# repro.cyr
include "lib/syscalls.cyr"
include "lib/async.cyr"

fn main() { syscall(60, 0); }
```

```
$ cyrius build --aarch64 repro.cyr /tmp/repro
error: undefined variable 'SYS_EPOLL_WAIT' (missing include or enum?)
```

## Fix options

Two clean approaches; either works for daimon's needs.

**Option 1 — arch-dispatched alias in the aarch64 syscalls module
(preferred):** add a wrapper or alias in
`lib/syscalls_aarch64_linux.cyr` so `SYS_EPOLL_WAIT` resolves to a
fn that translates to `SYS_EPOLL_PWAIT(..., 0, 8)`. Call sites in
`lib/async.cyr` stay portable. Matches the pattern sakshi 2.2.2 used
for its `_sk_open` x86=`open` / aarch64=`openat(AT_FDCWD, ...)` arity
gap.

**Option 2 — arch-gate inside `lib/async.cyr`:** wrap the two call
sites in `#ifdef CYRIUS_ARCH_AARCH64` calling `SYS_EPOLL_PWAIT` with
the 6-arg shape; `#else` calling `SYS_EPOLL_WAIT`. Bigger blast
radius (per-call-site) but no stdlib aliasing.

Option 1 keeps `lib/async.cyr` arch-portable in intent (which is what
its 1.1.x ship into daimon already assumed).

## Consumer-side workaround

Daimon's CI / release workflows (`.github/workflows/ci.yml` +
`release.yml`) downgrade this specific error to a `::warning::` and
`exit 0` for the best-effort aarch64 lane. Any other aarch64 build
failure still fails the step — daimon-side regressions stay visible.
Same posture as sakshi 2.2.2's aarch64 lane for its own stdlib gaps.

When this fix lands and daimon picks up the new cyrius pin, the build
succeeds and the warning never fires; daimon's aarch64 binary returns
to the release artifacts automatically. No daimon-side follow-up
required beyond removing the warn-on-detect grep at a future cleanup
slot.

## Severity rationale

**P2** because:

1. Daimon's primary platform is x86_64 Linux (production deployment
   target for AGNOS agent orchestration; aarch64 is opportunistic for
   edge nodes and dev hardware).
2. The aarch64 cross-build was already best-effort (gated on
   `cc5_aarch64` presence in the toolchain bundle).
3. CI keeps shipping — only the aarch64 artifact is missing per tag.
4. No correctness or security implication on the affected platform —
   the build simply doesn't produce a binary, fail-closed.

Bumps to **P1** if:

- AGNOS deploys at scale to aarch64 edge nodes and consumer fleet
  pressure surfaces (likely 1.4.x+ daimon timeline).
- Sakshi's or sandhi's aarch64 path lights up enough other consumers
  that daimon's aarch64 binary becomes an explicit demand.

## Related

- sakshi 2.2.2 — same posture for `vec_get` / `vec_len` aarch64 stdlib
  emit gaps. Daimon copies that approach for its own warn-on-detect
  workaround.
- daimon CHANGELOG 1.2.0 § Known issues — records the gap from the
  consumer side.
