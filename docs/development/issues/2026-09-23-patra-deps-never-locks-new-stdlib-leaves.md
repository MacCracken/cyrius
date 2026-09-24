# `cyrius deps` never locks a newly declared stdlib leaf, and `--verify` passes over it tampered — OPEN

**Status:** 🟡 **OPEN**: reproduced 2026-09-23 with the installed 6.6.6, in a scratch project (below)
and in patra's tree.
**Placement:** unpinned — `cbt/deps.cyr`.
**Discovered:** 2026-09-23 during patra's 1.15.0 cut, which added `chrono` and `random` to
`[deps] stdlib`. `cyrius deps` vendored both into `lib/`, left `cyrius.lock` at 29 of 31 entries, and
`cyrius deps --verify` reported `29 verified, 0 failed`. `cyrius deps --relock` wrote all 31.
**Severity:** Medium: the lock's integrity check does not cover every vendored file, so a tampered
one verifies clean. No wrong binary follows by itself, since `cyrius build` re-syncs declared leaves
from the pinned snapshot, but the lock no longer means what it says.
**Affects:** cyrius 6.6.6 (reproduced). The fresh-project case (3 below) is identical under 6.6.3 and
6.6.4, so it predates 6.6.4's lock work.

## Summary

1. **A newly declared leaf is vendored but never locked.** With a lock stamped at the current pin,
   adding a leaf to `[deps] stdlib` and running `cyrius deps` copies `lib/<leaf>.cyr` into place,
   prints nothing, and leaves the lock unchanged. A later `cyrius build` does not lock it either.
2. **`--verify` passes over the unlocked file, even tampered.** It checks only what the lock lists.
3. **A stdlib-only project never gets a lock** from `cyrius deps` or `cyrius build`. Only
   `cyrius deps --relock` writes one. `cyrius deps --help` documents `--relock` only as *"accept a stdlib
   leaf whose pinned snapshot changed …"* (`cbt/cli_args.cyr:262`), not as the way to lock a new leaf
   or write a first lock. The top-level `cyrius help` line for `deps` shows only
   `[--no-lock|--verify]`.

Case 1 is not the case the 6.6.4 fix refuses
(`archived/2026-09-13-hisab-deps-relocks-silently-under-unchanged-pin.md`, a locked file whose
snapshot content *changed* under an unchanged pin). A new leaf has no locked hash to disagree with.

## Reproduction

```sh
mkdir r && cd r
printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > cyrius.cyml
cyrius deps;  ls cyrius.lock                    # no such file (case 3)
cyrius deps --relock                            # cyrius.lock: 15 deps locked
sed -i 's/"string"\]/"string", "chrono"]/' cyrius.cyml
cyrius deps                                     # prints nothing
grep -c lib/chrono.cyr cyrius.lock              # 0: lib/chrono.cyr exists, unlocked (case 1)
echo '# tampered' >> lib/chrono.cyr
cyrius deps --verify                            # 15 verified, 0 failed (case 2)
```

## Options (the maintainer's call), with what each changes for consumers

- **Lock new leaves when the declared set grows under an unchanged pin.** Nothing the 6.6.4 refusal
  protects is at stake. Visible effect: `cyrius.lock` gains lines in consumer repos on their next
  `deps`.
- **Make `--verify` fail on a declared leaf that is in `lib/` but missing from the lock**, naming it.
  ⚠ Consumers whose lock is incomplete today (patra's was, until it ran `--relock`) would start
  failing `--verify` until they relock. That is the point, but it is a visible change for anyone who
  runs it in CI.
- **Write a lock on the first `cyrius deps`** in a project that has none, or print that none was
  written. ⚠ This creates a new tracked file in every stdlib-only consumer repo.
- **Say in `cyrius deps --help` that `--relock` also locks newly declared leaves and writes a
  first lock**, and list it on the top-level `cyrius help` line. No behaviour change.

## What patra does meanwhile

patra 1.15.0 ran `cyrius deps --relock` once. It checked the two new hashes against the 6.6.6
toolchain's copies and confirmed the other 29 entries unchanged. Its lock and `lib/` agree
(31 = 31).
