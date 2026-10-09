# `cyrius deps` / `build` after a pin move, before `lib sync --full`, stamp the new pin over the old pin's lock rows — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the CLI built from `cbt/cyrius.cyr` by
the tree's `build/cycc`, in a throwaway `CYRIUS_HOME` holding two snapshots of this tree's `lib/` (6.6.7's
`chrono.cyr` changed): after `deps` at the new pin the lock's trailer reads `cyrius 6.6.7` while `lib/chrono.cyr` and
its row are still 6.6.6's bytes; `deps --verify` (113 verified, 0 failed) and `deps --locked` ("exactly what the tags
resolve") both pass on that state; `lib sync --full` then refuses (rc 1) as if the 6.6.7 snapshot had changed under
an unchanged pin.
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** 6.6.17 (2026-10-05; the loud refusal shipped then, `lib_sync_relocks.sh` axis 2 pins it); filed
2026-10-08 from roadmap.md.
**Severity:** Medium — the lock misstates which snapshot its rows came from and the integrity checks agree with it;
the recovery (`lib sync --full --relock`) is named in the refusal but is the same command the refusal tells a user
whose snapshot really moved NOT to run.
**Affects:** 6.6.4 (the pin trailer) through 6.7.6.

## Summary

A project that vendors the whole snapshot (`lib sync --full`) holds `lib/` files outside its declared
`[deps].stdlib` closure. When `[package].cyrius` moves and `cyrius deps` (or any auto-deps verb such as `build`) runs
before `lib sync --full`, `deps` re-vendors only the declared closure, then rewrites the lock by hashing ALL of
`lib/` and stamps the NEW pin as the trailer. Every row for a file `deps` did not vendor now carries the previous
pin's hash under the new pin's name. Nothing flags it: `--verify` compares disk to lock (they agree) and `--locked`
keeps undeclared files as-is. The next `lib sync --full` sees an unchanged pin whose snapshot disagrees with the lock
and refuses with both explanations ("if you just moved the pin … `--relock`"; "if the pin did NOT move … do not
`--relock`"), leaving the user to guess which.

## Reproduction

(The shape of `tests/gates/toolchain/lib_sync_relocks.sh` axis 2, by hand.)

```sh
cat cbt/cyrius.cyr | build/cycc > $S/cyrius && chmod +x $S/cyrius
H=$S/home; mkdir -p $H/versions/6.6.6 $H/versions/6.6.7
cp -r lib $H/versions/6.6.6/lib; cp -r lib $H/versions/6.6.7/lib
echo '# moved in 6.6.7' >> $H/versions/6.6.7/lib/chrono.cyr; echo 6.6.7 > $H/current
mkdir -p $S/p; printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > $S/p/cyrius.cyml
cy() { (cd $S/p && HOME=$S/nohome CYRIUS_HOME=$H CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 $S/cyrius "$@"); }
cy lib sync --full; cy deps                                   # locked at 6.6.6
sed -i 's/^cyrius = ".*"/cyrius = "6.6.7"/' $S/p/cyrius.cyml
cy deps                                                       # rc 0
tail -1 $S/p/cyrius.lock; grep lib/chrono.cyr $S/p/cyrius.lock   # cyrius 6.6.7 / 7dfcca2a… (6.6.6's hash)
cy deps --verify; cy deps --locked                            # both pass
cy lib sync --full                                            # refused
```

Expected: after `deps` at 6.6.7, either the lock still says which rows are 6.6.6's, or `--verify` / `--locked` flag
`lib/chrono.cyr` as the previous pin's. Actual: trailer `cyrius 6.6.7`, chrono row `7dfcca2a…` = 6.6.6's
(6.6.7's is `1816fd27…`); `113 verified, 0 failed`; `--locked: lib/ and cyrius.lock are exactly what the tags
resolve`; then

```
error: lib/chrono.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE under the pin the lock records, 6.6.7
…
error: lib sync: 1 file(s) refused above — NOTHING was written and cyrius.lock is unchanged.
  If you just moved [package].cyrius and ran `deps`/`build` first, these rows are the
  previous pin's: `cyrius lib sync --relock` (with --full for the whole snapshot).
  If the pin did NOT move, the installed snapshot changed under it — reinstall that
  version; do not `--relock`.
```

## Root cause

`cmd_deps_lock` (`cbt/deps.cyr:6439`) re-hashes every `.cyr` under `lib/` (`_deps_lock_dir("lib", lock_h)`, `:6515`)
and writes `cyrius\t<this run's pin>` as the trailer (`:6535-6538`) — one pin for the whole lock, whether or not this
run wrote the row. The guard that later refuses is `_dep_lock_guard_stdlib_leaf` (`:6087`, message `:6118`), reached
from `lib sync` through `_libsync_guard` (`cbt/commands.cyr:1839`).

## Proposed fix

Make the lock say the truth about a mixed `lib/` (which shape is the user's call — it changes what `deps` writes):
1. On a pin change, `deps` keeps the OLD trailer (and the old rows) for files it did not re-vendor and says so, so
   `lib sync` sees a pin change and re-locks without `--relock`; or
2. `deps` at a pin change refuses to re-lock until the out-of-closure files are re-synced (naming `lib sync --full`);
   or
3. `deps --verify` / `--locked` compare an out-of-closure row to the CURRENT pin's snapshot and name it as the
   previous pin's.
Gate: extend `lib_sync_relocks.sh` axis 2 to assert the post-`deps` state no longer passes as 6.6.7's.
