# `cyrius deps` writes `cyrius.lock` in an order that differs between machines

**Status:** 🟡 **OPEN** — reproduced on a real GitHub runner against a local machine,
with the two lock files proven to hold IDENTICAL content.
**Placement:** unpinned. Breaks any consumer CI gate that compares the lock byte-for-byte.
**Discovered:** 2026-08-26 by commandress (first CI run); re-hit and diagnosed in
**agnostic** on 2026-09-12 during the 6.6.2 ecosystem sweep.
**Severity:** Medium — no wrong code is produced, but it makes a committed lock
unverifiable off the machine that generated it, and the failure is maximally confusing:
the diffstat looks exactly like real dependency drift.

## Symptom

A consumer commits `cyrius.lock`. CI runs the documented remedy
(`cyrius lib sync --full && cyrius deps`) and then `git diff --quiet -- cyrius.lock`,
which fails:

```
Error: the committed cyrius.lock does not match a clean resolution at this pin
   cyrius.lock | 196 +++++++++++++++++++++++++---------------------------
   1 file changed, 98 insertions(+), 98 deletions(-)
```

## The content is identical — only the ORDER differs

Printing an order-insensitive comparison alongside the diff settles it. On agnostic's
runner, with 117 locked entries:

```
--- diff (first 40 lines) ---
+dc500d51…  lib/security.cyr
+99f96283…  lib/args_macos.cyr
 3e51b4f1…  lib/tagged.cyr          <- unchanged, same hash both sides
-fe799dda…  lib/net.cyr
-e84c090f…  lib/cffi.cyr
…
--- order-insensitive compare (EMPTY means a pure REORDER) ---
                                    <- EMPTY
```

`sort committed | diff - <(sort resolved)` is **empty**: every one of the 117 hashes and
all 9 `commit` pin lines are byte-identical. Only the sequence moved. Note the shape —
98 insertions + 98 deletions with **zero net line change**, and unchanged lines
interleaved — which is what a permutation looks like in a unified diff.

## What was ruled out

Measured, not assumed, before concluding order:

- The 6.6.2 release **tarball**'s `lib/` is byte-identical to the local
  `~/.cyrius/versions/6.6.2/lib` — 103 files, none missing on either side.
- All 9 `commit` pins match the real tag SHAs in each dep repo.
- Every cached dep bundle under `~/.cyrius/deps/<n>/<tag>/dist/` is byte-identical to
  `git show <tag>:<path>` in that dep.
- Both sides emit the SAME two `refusing to overwrite stdlib leaf` warnings
  (sigil, patra) and the same `9 deps resolved` / `117 deps locked, 9 commit-pinned`.
- Re-running `cyrius deps` three times on one machine gives a byte-identical lock, and
  rebuilding `lib/` with files created in REVERSE name order does not change the order
  either — so it is stable *per machine* and not naively creation-ordered.

## Why it matters

The order carries no meaning, so a byte-exact gate asserts something the tool does not
promise. Any repo whose CI does `git diff --exit-code -- cyrius.lock` fails for **every**
lock committed from a different machine — which is every lock. Two repos had the gate in
this shape; commandress hit it immediately, agnostic much later, and in between the
message ("does not match a clean resolution at this pin") reads as a genuine dependency
problem and sends the reader hunting stale pins that are not stale.

## Consumer-side remedy already in use

`commandress/scripts/lock-check.sh` compares order-insensitively, split into the
`commit` pin lines and the `<sha256>  lib/<file>` set so the message says which half
moved. It still catches a changed hash, an added entry or a dropped one — including the
case it was written for, a `path = "../dep"` override dropping a dep's `commit` line
entirely. Adopted verbatim into agnostic on 2026-09-12.

⚠ That script also documents a trap worth repeating here: it must baseline from
`git show HEAD:cyrius.lock`, **not** the working tree. Consumer CI usually runs
`cyrius deps` in an earlier step, so a working-tree baseline compares a regeneration
against another regeneration and passes unconditionally — a tampered lock was verified
to pass that way (commandress audit 2026-08-26, A-03).

## Fix

Emit the lock in a deterministic order — sort the `<sha256>  lib/<file>` lines by path
and the `commit` lines by dep name. Then a byte-exact `git diff` becomes a legitimate
gate and every consumer can drop the workaround.

## Acceptance

- Two machines resolving the same manifest at the same pin produce byte-identical locks.
- agnostic and commandress pass with a plain `git diff --exit-code -- cyrius.lock`.
- A real change (hash, added entry, dropped `commit` pin) still fails the gate.
