# `cyrius deps` writes `cyrius.lock` in an order that differs between machines

**Status:** ✅ **FIXED in v6.6.3** — `_deps_lock_dir` (`cbt/deps.cyr`) now sorts the
`lib/` traversal with the `_dep_name_cmp` comparator that already existed in the same
file. Gated by `tests/gates/toolchain/deps_lock_sorted.sh`, mutation-proven (removing the
one line reddens it with readdir order: `bench, math, boxed …`).
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

---

## Resolution (v6.6.3)

One line, and the remedy was already in the file. `cbt/deps.cyr:830` had carried
`vec_sort_by(entries, &_dep_name_cmp)` since **v6.5.37 (A8)** with the comment *"readdir
order is not deterministic"* — that release fixed the module-family walker and missed the
lock writer. The same call now guards `_deps_lock_dir`.

The commit-pin lines needed no sort: they are appended in manifest declaration order,
which is already machine-independent. Confirmed rather than assumed — they appeared as
unchanged CONTEXT lines in the agnostic diff while only the hash lines moved.

**Verified:** a 25-entry lock comes back fully path-sorted, including the nested
`lib/unicode/` package landing correctly between `lib/tyche.cyr` and `lib/vani.cyr`, and
is byte-identical across two resolves.

### Consumer workarounds that can now be retired

- `agnostic/scripts/lock-check.sh` + its `ci.yml` step
- `commandress/scripts/lock-check.sh` + its `ci.yml` step

Both compare the lock as sorted sets. They are harmless to keep — they still catch a
changed hash, an added entry or a dropped `commit` pin — but a plain
`git diff --exit-code -- cyrius.lock` is now a legitimate gate again. ⚠ Whoever retires
them should keep the HEAD-baseline lesson recorded in `lock-check.sh`: consumer CI usually
runs `cyrius deps` in an earlier step, so a gate that baselines from the working tree
compares a regeneration against another regeneration and passes unconditionally
(commandress audit 2026-08-26, A-03 — a tampered lock was verified to pass that way).
