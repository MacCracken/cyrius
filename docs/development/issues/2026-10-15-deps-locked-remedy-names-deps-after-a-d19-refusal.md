# `deps --locked` after a D19 pin-move refusal still says "run `cyrius deps` and commit the result", and that command now refuses — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools @ 88afd900; D19 shipped in
c72b4e15, issues/2026-10-08-deps-before-lib-sync-stamps-new-pin.md). Found by the lane's review. Related, not the same
find: 2026-10-15-deps-keeps-a-lock-row-for-a-file-removed-from-lib.md (staged by this lane) is the same remedy line
going stale for a different reason (a removed file's row).
**Placement:** 6.7.13 — repair 3: struct values (tools lane; filed from the 6.7.12 tools lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — fail-closed and two steps to the remedy: CI's `--locked` sends the user to `cyrius deps`, which
exits 1 with the D19 refusal, and only that refusal names `cyrius lib sync --full`.
**Affects:** a full-vendored project (`lib sync --full`) whose `[package].cyrius` moved and whose out-of-closure files
differ at the new pin; 6.7.12 (D19) onward.

## Reproduction

The two-snapshot home of `tests/gates/toolchain/lib_sync_relocks.sh` (6.6.7 moves `chrono.cyr`, outside the closure,
and `string.cyr`, inside it):

```sh
H=$S/home; mkdir -p $H/versions/6.6.6 $H/versions/6.6.7
cp -r lib $H/versions/6.6.6/lib; cp -r lib $H/versions/6.6.7/lib
echo '# moved in 6.6.7' >> $H/versions/6.6.7/lib/chrono.cyr; echo '# moved in 6.6.7' >> $H/versions/6.6.7/lib/string.cyr
echo 6.6.7 > $H/current
cy() { (cd $S/p && HOME=$S/nohome CYRIUS_HOME=$H CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 cyrius "$@"); }
mkdir -p $S/p; printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > $S/p/cyrius.cyml
cy lib sync --full > /dev/null; cy deps > /dev/null
sed -i 's/^cyrius = ".*"/cyrius = "6.6.7"/' $S/p/cyrius.cyml
cy deps > /dev/null 2>&1; echo "deps rc=$?"
cy deps --locked; echo "rc=$?"
cy deps 2>&1 | head -2
```

Output:

```
deps rc=1
  differs: lib/string.cyr: cyrius.lock records f963c13ec3945a54d7a6c626e75b9f02d2053c60deb4fa987d7fd1fff97b1723, the tags resolve e0af9504c0dfec5d029006176dbb060d04cc44d8e0ef8dbe636a469144d8e2ff
  differs: cyrius.lock records another stdlib pin than 6.6.7
error: --locked: 2 difference(s) between what the tags resolve and the committed lib/ + cyrius.lock (named above); nothing was written — run `cyrius deps` and commit the result
rc=1
error: cyrius.lock not re-locked: [package].cyrius moved from 6.6.6 to 6.6.7, and lib/ holds 1 file this resolve did not vendor that the 6.6.7 snapshot ships with other bytes:
  lib/chrono.cyr
```

At the pin bump itself, before any `deps` runs, `--locked` gives the same remedy (3 differences: string's row, string's
stale bytes in lib/ — `lib/string.cyr: lib/ holds other bytes than the tags resolve (stale)` — and the pin), rc 1,
"… — run `cyrius deps` and commit the result"; following it hits the refusal above.

## Root cause

`_deps_finish` (`cbt/deps.cyr` ~4308) has one remedy for every `--locked` difference: "run `cyrius deps` and commit
the result". Since D19 that is wrong when the lock records another pin and `lib/` holds out-of-closure files the new
pin's snapshot ships with other bytes — exactly the set `_dep_pin_move_refused` computes.

## Proposed fix

When `--locked` finds the pin difference, run the same out-of-closure test `_dep_pin_move_refused` runs (read-only)
and, if it names any file, give D19's remedy instead: `cyrius lib sync --full` (moves them, re-locks) or
`rm <file> && cyrius deps`. Gate: `lib_sync_relocks.sh` axis 2 adds `deps --locked` after the pin move: rc 1 and the
`lib sync --full` remedy, not "run `cyrius deps`".
