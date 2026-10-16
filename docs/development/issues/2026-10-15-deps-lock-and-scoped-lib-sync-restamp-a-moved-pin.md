# `cyrius deps --lock` and a scoped `cyrius lib sync` at a moved pin still stamp the new pin over the old pin's rows — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools @ c72b4e15, which ships D19 for
the resolve: `deps` / `build` now refuse this shape, 2026-10-08-deps-before-lib-sync-stamps-new-pin.md). The two
other lock writers reach the same lie by another verb. D19 was decided for "deps refuses to re-lock"; extending it
to these two verbs (or another shape for them) is a decision, so it is filed, not folded in.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D42 — (1) Extend D19 to both writers.
**Severity:** Medium — the same as the issue D19 closed: the lock's one `cyrius <pin>` trailer names a pin its rows do
not have, `deps --verify` (113 verified) and `--locked` agree with it, and the next `lib sync --full` refuses under
"the pin the lock records" (`_libsync_guard` now names these two verbs as the cause, so the advice is right; the
lock is still wrong until then).
**Affects:** `deps --lock` since 6.6.4 (the trailer); the scoped `lib sync` re-lock since 6.6.17.

## Reproduction

A throwaway `CYRIUS_HOME` holding two snapshots of this tree's `lib/`, 6.6.7's `chrono.cyr` changed (the shape of
`tests/gates/toolchain/lib_sync_relocks.sh`):

```sh
H=$S/home; mkdir -p $H/versions/6.6.6 $H/versions/6.6.7
cp -r lib $H/versions/6.6.6/lib; cp -r lib $H/versions/6.6.7/lib
echo '# moved in 6.6.7' >> $H/versions/6.6.7/lib/chrono.cyr; echo 6.6.7 > $H/current
cy() { (cd $S/p && HOME=$S/nohome CYRIUS_HOME=$H CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 $S/cyrius "$@"); }
mkp() { rm -rf $S/p; mkdir -p $S/p; printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n' > $S/p/cyrius.cyml
        cy lib sync --full >/dev/null; cy deps > /dev/null; sed -i 's/^cyrius = ".*"/cyrius = "6.6.7"/' $S/p/cyrius.cyml; }
echo "=== bare deps --lock after a pin move"; mkp
cy deps --lock; echo rc=$?; tail -1 $S/p/cyrius.lock; grep chrono $S/p/cyrius.lock; cy deps --verify | tail -1; cy lib sync --full 2>&1 | head -2
echo "=== scoped lib sync after a pin move"; mkp
cy lib sync; echo rc=$?; tail -1 $S/p/cyrius.lock; grep chrono $S/p/cyrius.lock; cy deps --verify | tail -1; cy lib sync --full 2>&1 | head -2
```

Output:

```
=== bare deps --lock after a pin move
cyrius.lock: 113 deps locked
rc=0
cyrius	6.6.7
7dfcca2a419856daa9a79ba00e5f02ad8ccd1e8f219c3ddb5150c9c070de84d8  lib/chrono.cyr
113 verified, 0 failed
error: lib/chrono.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE under the pin the lock records, 6.6.7
  cyrius.lock records  7dfcca2a419856daa9a79ba00e5f02ad8ccd1e8f219c3ddb5150c9c070de84d8
=== scoped lib sync after a pin move
synced from …/home/versions/6.6.7/lib — copied 8 .cyr files (declared [deps].stdlib subset; --full for whole snapshot)
cyrius.lock: 113 deps locked
rc=0
cyrius	6.6.7
7dfcca2a419856daa9a79ba00e5f02ad8ccd1e8f219c3ddb5150c9c070de84d8  lib/chrono.cyr
113 verified, 0 failed
error: lib/chrono.cyr: cyrius.lock and the pinned stdlib snapshot DISAGREE under the pin the lock records, 6.6.7
  cyrius.lock records  7dfcca2a419856daa9a79ba00e5f02ad8ccd1e8f219c3ddb5150c9c070de84d8
```

`7dfcca2a…` is 6.6.6's chrono; 6.6.7's is `1816fd27…`. (The bare `--lock` also stamps 6.6.7 over the closure's own
6.6.6 rows — `lib/string.cyr` etc. — since nothing was re-vendored at all.)

## Root cause

`cmd_deps_lock` (`cbt/deps.cyr`) writes `cyrius\t<this run's pin>` as the one trailer whatever produced the rows.
6.7.12's `_dep_pin_move_refused` (D19) runs only after a resolve (`_dep_closure != 0`) and not for `lib sync`'s
re-lock (`_dep_lock_only != 0`): the bare `--lock` re-hashes `lib/` as it stands, and the scoped `lib sync` re-hashes
the declared subset it wrote and keeps every other row byte for byte (6.6.17) — both under the new pin's name.

## Proposed fix (the user's call)

Hold both writers to D19's rule: at a pin change, refuse to stamp the new pin while `lib/` holds snapshot files the
run did not (re-)write whose bytes are not the new pin's — for the bare `--lock` that is every such file (it wrote
none; its remedy is `cyrius deps` first), for the scoped `lib sync` the out-of-subset ones (`--full`). Gate:
`lib_sync_relocks.sh` axis 2 gains the two verbs.
