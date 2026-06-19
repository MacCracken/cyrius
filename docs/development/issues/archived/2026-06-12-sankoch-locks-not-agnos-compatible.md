# sankoch lock primitives are not agnos-compatible (pull the Linux clone-thread path → `CLONE_VM`)

**Filed:** 2026-06-12
**Severity:** MEDIUM — blocks the agnos build of *any* sankoch consumer; no host/runtime impact (host build is clean)
**Component:** stdlib — `lib/sankoch.cyr` thread-safety locks (`_sankoch_lock`/`_sankoch_unlock`) + the `thread`/`mmap` clone family they transitively pull
**Reported by:** kii 1.0.0 (image→ANSI converter; first agnos consumer of sankoch — PNG IDAT inflate)
**Related:** agnos roadmap 1.44.x row already tracks this class ("mihi/iam/chakshu sysinfo blocked because ai-hwaccel's GPU probe pulls thread/atomic/Linux `CLONE_VM`"); ai-hwaccel consumer-side issue filed `ai-hwaccel/docs/development/issues/2026-06-12-gpu-probe-thread-blocks-agnos-build.md`; archived sibling `archived/2026-06-04-cyrius-global-allocator-not-thread-safe.md`.

## Symptom

```
$ cyrius build --agnos src/main.cyr build/kii_agnos
...
error: lib/mmap.cyr:184: undefined variable 'CLONE_VM' (missing include or enum?)
FAIL
```

Host build is clean (`cyrius build src/main.cyr build/kii` → OK, 258 KB). The failure is **agnos-target-only**.

## Root cause

kii decodes PNG via sankoch's `zlib_decompress`. sankoch wraps its decode entry points in `_sankoch_lock()` / `_sankoch_unlock()` for thread-safety (`lib/sankoch.cyr:4733`):

```cyrius
fn _sankoch_lock(): i64 {
    ...
    mutex_lock(_sankoch_mtx);   # unconditional — NO CYRIUS_TARGET_AGNOS branch
}
```

`mutex_lock` lives in `lib/thread.cyr`, which `include`s `lib/mmap.cyr` (`thread.cyr:30`) and builds threads via the Linux clone model:

```cyrius
# thread.cyr:199
var flags = CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND;
```

`CLONE_VM` is a Linux-only constant (`CloneFlag` enum, `syscalls_*_linux`), undefined under `CYRIUS_TARGET_AGNOS`. agnos has `mmap`(27) for the **allocator** (`alloc_agnos.cyr`) but **no clone-based userland threading** — agnos userland is single-threaded today. So any agnos consumer that touches a sankoch lock drags the whole Linux-clone `thread`→`mmap`→`CLONE_VM` chain into the build and fails to compile.

## Why kii is the first to hit it

The existing agnos tools (owl, kriya, anuenue, bnrmr, iam) don't depend on sankoch. kii is the **first agnos consumer of sankoch** (PNG IDAT inflate), so it's the first to pull `sankoch → thread → mmap → CLONE_VM` into an agnos build.

## Recommended repair (minimal, consumer-transparent)

Make sankoch's lock primitives no-ops under `CYRIUS_TARGET_AGNOS`. agnos userland is single-threaded, so the mutex is unnecessary and gating it out removes the thread/mmap/clone dependency entirely:

```cyrius
fn _sankoch_lock(): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return 0;     # agnos userland is single-threaded — no lock needed
    #endif
    ... mutex_lock(_sankoch_mtx) ...   # host/Linux/Windows unchanged
}
```

(same for `_sankoch_unlock`, and skip the `_sankoch_mtx` init on agnos). sankoch's API and host behavior stay byte-identical; the agnos build simply skips the lock and never pulls `thread`/`mmap`/`CLONE_VM`.

## Broader pattern (the actual class of "cyrius repair")

This is one instance: the Linux-clone `thread` / `mmap` / `atomic` stdlib family has no agnos branch, so **any** agnos consumer that pulls it breaks. Two strategic options (the agnos roadmap's framing):

- **(a) per-consumer `CYRIUS_TARGET_AGNOS` no-op / sync fallback** — cheap, available now. Recommended for sankoch (this issue) and ai-hwaccel (sibling issue). Unblocks kii / mihi / iam / chakshu immediately.
- **(b) a real agnos userland threading model** — when agnos exposes a clone/thread primitive (a future agnos arc). The long-term fix; not needed to unblock the single-threaded consumers above.

Option (a) for sankoch is the ask here.

## Repro

- repo: kii 1.0.0, `cyrius.cyml` pin 6.1.14 (lib/ vendored from 6.2.0 — `_sankoch_lock` byte-identical across both)
- FAIL: `cyrius build --agnos src/main.cyr build/kii_agnos` → the `CLONE_VM` error above
- OK:   `cyrius build src/main.cyr build/kii` → clean host build

## Resolution — v6.2.22 (2026-06-18, sankoch 2.4.4)

**RESOLVED via Option (a), with a corrected root-cause.** `_sankoch_lock` /
`_sankoch_unlock` no-op under `CYRIUS_TARGET_AGNOS` (sankoch 2.4.4, re-folded into
cyrius `lib/sankoch.cyr` byte-identical). sankoch now references no `mutex_*` on
agnos, so it builds `--agnos` self-sufficiently — even for a consumer that does not
pull `thread.cyr`.

**Premise correction (cyrius v6.2.22 adversarial review).** This filing's
"`thread.cyr → mmap.cyr → CLONE_VM` would warn-and-ud2" describes the **pre-v6.2.3**
`thread.cyr`. The current `thread.cyr` already self-guards agnos: `#ifdef
CYRIUS_TARGET_AGNOS → include "lib/thread_agnos.cyr"` (no-op mutexes), with the
`mmap.cyr`/CLONE_VM body behind `#ifndef CYRIUS_TARGET_AGNOS`. So the sankoch fix is
the sankoch-layer counterpart (self-sufficiency / defense-in-depth), **not** a crash
preventer. Empirically: a consumer on current cyrius stdlib + sankoch 2.4.4 builds
`--agnos` clean (exit 0, no `CLONE_VM`).

**kii follow-up (consumer-side).** kii's own `--agnos` repro still fails because kii
vendors **stale** stdlib — its `thread.cyr` predates the v6.2.3 agnos selector. kii
must `cyrius deps`-refresh against released cyrius 6.2.22 + sankoch 2.4.4 to pick up
the current `thread.cyr` + the no-op locks. (cyrius-side is complete; this is the
consumer's refresh.)
