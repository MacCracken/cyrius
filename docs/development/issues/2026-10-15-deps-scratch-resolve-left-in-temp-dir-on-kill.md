# A SIGTERM'd `cyrius deps --locked` (and 6.7.13's pin-move dry pass) leaves its scratch resolve in the CLI's temp dir — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.13 tools lane (l6713-tools @ 5c62424a, the CLI built from
`cbt/cyrius.cyr` by the tree's `build/cycc`). Met while implementing
archived/2026-10-15-d19-refusal-leaves-closure-files-revendored-at-the-new-pin.md (D41): its pin-move dry pass resolves into
a private scratch the way `--locked` does (`_cbt_tmpfile(...)` + `/lib`, `_dep_vendor_mode = 0`), and inherits the
same gap. Not repaired in that bite: the scratch is written by the resolver's ordinary copy path
(`_dep_copy_file`: mkdir -p, then an `_aw_open` sibling temp renamed into place), none of which is recorded BEFORE it
exists, which is what the kill handler's one scratch-tree slot (`_cbt_sig_tree_set`, 6.7.13) needs.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane, wave 1, unit T3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a developer's own Ctrl-C / SIGTERM of `cyrius deps --locked` (or of a `deps` / `build` at a moved
pin, during its dry pass) leaves the CLI's private `cyrius-<pid>/` temp dir holding the scratch `lib/` (16 files for
a two-leaf project; a whole snapshot's worth for a larger closure). check.sh's reaper removes a dead pid's dir; an
interactive user's `$TMPDIR` keeps it. Nothing in the project (`lib/`, `cyrius.lock`) is touched.
**Affects:** `--locked` since 6.7.6 (part L); the kill handler cleans the temp dir since 6.7.12; the dry pass since
6.7.13 (D41).

## Reproduction

```sh
# (sh; CLI = the CLI built from cbt/; a stand-in `git` first on PATH sleeps, so the kill lands mid-resolve,
#  after Phase 1 copied the stdlib leaves into the scratch)
S=$PWD/kl; rm -rf $S; mkdir -p $S/bin $S/tmp $S/p/lib
printf '#!/bin/sh\necho $$ > "$KL_PIDF"\nexec sleep 60\n' > $S/bin/git; chmod +x $S/bin/git
H=$S/home; mkdir -p $H/versions/6.6.6 && cp -r lib $H/versions/6.6.6/lib && echo 6.6.6 > $H/current
printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n\n[deps.foo]\ngit = "https://example.invalid/foo"\ntag = "1.0.0"\nmodules = ["dist/foo.cyr"]\n' > $S/p/cyrius.cyml
printf 'x\n' > $S/p/cyrius.lock; cp lib/string.cyr $S/p/lib/
( cd $S/p && PATH=$S/bin:$PATH KL_PIDF=$S/pidf TMPDIR=$S/tmp HOME=$S/nohome CYRIUS_HOME=$H CYRIUS_RESOLVED=1 \
    CYRIUS_NO_WARN_PIN_DRIFT=1 exec $CLI deps --locked > $S/out.txt 2>&1 ) & CP=$!
while [ ! -s $S/pidf ]; do sleep 0.1; done
echo "in flight: $(find $S/tmp -type f | wc -l) files"; kill -TERM $CP; wait $CP; echo "rc=$?"
echo "left: $(find $S/tmp -type f | wc -l) files: $(find $S/tmp -mindepth 1 -maxdepth 2 | tr '\n' ' ')"
kill $(cat $S/pidf) 2>/dev/null   # the git child is the separate, already-staged issue
```

```
in flight: 16 files
rc=143
left: 16 files: …/kl/tmp/cyrius-2251441 …/kl/tmp/cyrius-2251441/locked-deps
```

The same with the manifest at `cyrius = "6.6.7"` (a second snapshot whose `string.cyr` differs), the lock's trailer
`cyrius\t6.6.6` and a plain `deps`: `left: 16 files: …/cyrius-2251847 …/cyrius-2251847/pin-move-deps` (lib/ itself
untouched — the dry pass writes only the scratch). Expected: rc 143 and no `cyrius-<pid>` directory, as for a killed
check / build / distlib / capacity (cli_temp_dir_no_leak.sh axis 7).

## Root cause

The kill handler (`cbt/sigclean.cyr` `_cbt_sig_fire`) unlinks the scratch NAMES it was given, removes one registered
scratch TREE (`_cbt_sig_tree_*`, the distlib mirror: two vecs its maker fills before each file / directory exists),
then `rmdir`s the private temp dir — which fails while the scratch resolve is in it. Neither resolve into
`<tmp>/locked-deps/lib` (`cmd_deps`, --locked) nor into `<tmp>/pin-move-deps/lib` (`_deps_pin_move_dry`) is
registered: the resolver's writes go through `_dep_copy_file`, which creates directories with `sys_mkdir` per prefix
and each file through an `_aw_open` sibling temp, recording a path in `_dep_closure` only after the rename.

## Proposed fix

Record before create when the resolve writes a scratch root (`_dep_vendor_mode == 0`): `_dep_copy_file` pushes each
directory it is about to mkdir and the destination (and its `_aw` temp) onto two vecs registered through the
scratch-tree slot for the life of the scratch, cleared after `_dep_rm_tree`. (The slot is single today — distlib's
mirror and a resolve never overlap in one process, but a second slot or a stack would make that explicit.) Rows:
cli_temp_dir_no_leak.sh axis 7 — `deps --locked` and the pin-move dry pass killed mid-resolve (the stand-in git
above): rc 143, no `cyrius-<pid>` dir.
