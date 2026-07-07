# stdlib `mutex_new/lock/unlock` defined twice (thread.cyr ⇄ sync.cyr) — 3 `duplicate fn` warnings on every consumer build

**Filed:** 2026-07-03 (by the `yeo-cy-test` consumer — SecureYeoman → Cyrius
full-stack viability probe; cyrius 6.3.41)
**Severity:** **LOW (benign today, latent footgun + build noise).** The two
definitions are behaviorally identical, so "last definition wins" picks a correct
one and the probe builds + runs green. But every consumer that links both modules
sees three `duplicate fn` warnings, and if the two impls ever diverge the winner
is decided silently by link/registration order.
**Component:** stdlib `lib/thread.cyr` and `lib/sync.cyr` (both vendored into a
consumer's `lib/` snapshot).

## Symptom

Building the probe (which pulls `thread` explicitly and `sync` transitively — via
`alloc`/`atomic`/`patra`) emits, on every build:

```
warning:lib/sync.cyr:44: duplicate fn 'mutex_new' (last definition wins)
warning:lib/sync.cyr:52: duplicate fn 'mutex_lock' (last definition wins)
warning:lib/sync.cyr:65: duplicate fn 'mutex_unlock' (last definition wins)
```

## Cause

Both stdlib modules define the same three symbols for the **same platform**
(LINUX / futex):

- `lib/thread.cyr:306` `mutex_new`, `:314` `mutex_lock`, `:332` `mutex_unlock`
- `lib/sync.cyr:51` `mutex_new`, `:59` `mutex_lock`, `:72` `mutex_unlock`

(Each file also carries the AGNOS/Windows/macOS variants under platform guards —
`sync.cyr:90+`, `thread_agnos.cyr:72+`, `thread_win.cyr:63+`, `sync_windows.cyr`,
`sync_macos.cyr` — but the LINUX pair above is the one that collides in a normal
Linux consumer link.) The two LINUX impls are byte-identical futex wrappers, so
the collision is harmless — but it's a real symbol overlap between two stdlib
modules that a consumer can't avoid once anything pulls `sync`.

## Precedent (same class, already filed)

This is a fresh instance of the duplicate-fn-across-stdlib-modules class already
seen for the allocator: `docs/development/issues/archived/2026-06-02-macos-alloc-arena-duplicate-fns.md`
(`arena_new`/`arena_alloc`/… "last definition wins"). That issue proposed the
general fix below.

## Recommendation

Pick one:

1. **Single owner.** Make `mutex_*` live in exactly one module (e.g. `sync`) and
   have `thread` re-export / include it, so there's one definition per platform.
2. **Dedup identical defs silently.** As the arena issue proposed: have the
   `duplicate fn` path treat a byte-identical redefinition as benign (dedup, no
   warning) and reserve the warning for *divergent* redefinitions — which is the
   only case that's actually a footgun.

Either removes the per-build noise and closes the silent-winner risk if the two
mutex impls ever drift.
