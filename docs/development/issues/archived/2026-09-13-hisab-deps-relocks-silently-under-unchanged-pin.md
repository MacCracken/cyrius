# `cyrius build` / `cyrius deps` silently RE-LOCK a stdlib file whose content changed under an UNCHANGED pin — FIXED v6.6.4

**Status:** ✅ **FIXED in v6.6.4** — the lock carries a `cyrius\t<pin>` trailer, is read once at
resolve entry, and a stdlib leaf whose pinned-snapshot hash disagrees with the locked one under
an unchanged pin is refused by name with both hashes (no lock write, no binary);
`cyrius deps --relock` is the explicit accept; a pin bump re-locks silently; a pre-6.6.4 lock
fails open once and comes back stamped. Found under it: bare `deps --lock` dropped every CVE-21
commit pin; a CRLF lock turned the guard off; `--verify` read only 64 KB. Gated by
`tests/gates/toolchain/deps_relock_refused.sh` (14 axes, local `file://` git dep). The filed repro
flips BUG → OK. The companion cause (the store written from a drifted tree) is closed in the
same release.
**Placement:** unpinned — `cbt/deps.cyr`, every 6.x release checked (6.6.2, 6.6.3).
**Discovered:** 2026-09-13. A `cyrius build` in hisab — manifest pin `6.6.2`, nothing edited — printed
`1 deps resolved / cyrius.lock: 31 deps locked, 1 commit-pinned`, the same two lines a no-op prints,
and had rewritten tracked `lib/ganita.cyr` (1.2.4 → 1.2.5) and moved its `cyrius.lock` hash
`d4aaa7da…` → `fae5a807…`. `git status` was the only thing that noticed.
**Severity:** High — **the lockfile exists to detect exactly this, and instead it is updated to
agree with it.** A lock that re-hashes itself on `build` cannot distinguish "the pinned content
changed" from "nothing happened"; `deps --verify` then passes on the mutated content.

## Summary

The resolver step that `cyrius build` runs implicitly (and `cyrius deps` runs explicitly) copies the
declared stdlib subset from `~/.cyrius/versions/<pin>/lib` into the consumer's `lib/` and writes the
resulting hashes into `cyrius.lock`, **unconditionally**. When the snapshot file's content differs from
what the lock already records — and the manifest pin has NOT changed — that is the one situation a
lock is for, and the resolver treats it as routine:

- no diagnostic names the file, the old hash or the new hash;
- the consumer's tracked `lib/<file>` is overwritten;
- `cyrius.lock` is rewritten so that `deps --verify` reports the mutated content as **verified**.

The only warning the resolver does emit is the `./lib/ shadows version-pinned …` one, and it fires
for the **git** dep whose lock commit differs (sakshi 2.5.1 vs 2.5.2 in hisab's case) — not for a
stdlib file whose bytes moved under the same pin.

## Repro

`repros/2026-09-13-hisab-deps-relocks-silently-under-unchanged-pin.sh` — stages a throwaway
`CYRIUS_HOME` copied from the installed pin (nothing under `~/.cyrius` is touched), a two-file
consumer with one git dep (a lock is only written when a git dep exists, which is every real consumer),
then:

1. `cyrius deps` → lock written, `deps --verify` passes.
2. Prepend ONE comment line to the throwaway snapshot's `lib/math.cyr`. Pin unchanged.
3. `cyrius build main.cyr ./out` — no manifest edit, no `deps` requested.

Measured (6.6.3, and identically on 6.6.2):

```
lock hash for lib/math.cyr:  before=a765010977ff6829def00d050e27cc94c52e5b9c6e28defb10f1fdabe2cd74e2
                              after =e3e1861136cf57b823d9cca0ff21460c5e2c9fc37be42090e60e7443c53c243b
build output:
    1 deps resolved
    cyrius.lock: 9 deps locked, 1 commit-pinned
    compile main.cyr -> ./out [x86_64] … OK (124968 bytes)
BUG: lock re-written silently under an unchanged pin (verify PASSES on the mutated content)
```

The consumer's `lib/math.cyr` now begins with the injected comment, and `deps --verify` says
`9 verified, 0 failed`.

## Why it matters — the two directions it fails in

- **Snapshot newer than the pin** (hisab, 2026-09-13; see the companion filing
  `2026-09-13-hisab-refresh-only-overwrites-released-snapshot.md`): a developer commits a lock and a
  `lib/` that a clean install of the pin cannot reproduce. CI's fresh install then fails
  `deps --verify` on a file nobody edited, and the developer's own `deps --verify` was green.
- **Snapshot older/tampered than the pin**: a modified stdlib file — a stale copy, a local edit, a
  supply-chain substitution — is vendored, locked and verified without a word. hisab's 2.11.2 notes
  record ganita three releases stale behind a green `deps --verify`; this mechanism is how that stays
  green.

Compare cargo/npm/go: a checksum mismatch against the lock on an unchanged dependency spec is a hard
error, never a re-lock.

## Proposed fix

In the resolver, before overwriting a consumer `lib/<file>` or a lock entry: if `cyrius.lock` already
carries a hash for `<file>` AND `[package].cyrius` is unchanged since the lock was written (record the
pin in the lock header, or compare against the lock's recorded stdlib version) AND the snapshot
file's hash differs, then **stop** with a diagnostic naming the file, both hashes and the pin, and
the two legitimate ways forward: bump the pin, or `cyrius deps --relock` to accept the new content
explicitly. Re-lock silently only when the pin changed or the entry is new.

Gate: the repro script above, verbatim — its exit code is the assertion. Mutation: remove the
pin-unchanged check and it goes back to exit 1.

## Consumer stopgap (what hisab does now)

Treat any `git status` change to `lib/` or `cyrius.lock` after a bare `cyrius build` as a defect to
investigate, not as "the resolver tidied up"; and byte-compare `lib/` against the cyrius **tag**
(`git show <pin>:lib/<file>`) rather than against the install dir, because the install dir is what
this mechanism trusts.
