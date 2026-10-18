# A scratch resolve keeps each copy's temp name recorded after the rename, so a kill unlinks a file put there later — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 infratools lane (l6715-infratools @ 73249ddb5, unit I5, the CLI
built from `cbt/cyrius.cyr` by the lane's build/cycc, x86_64 Linux); the same on the CLI before that unit (5c0a2b34b's,
which still recorded the predicted temp), so it predates 6.7.15.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 infratools lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — the same reach as issues/2026-10-16-scratch-resolve-records-a-predicted-temp-name-it-did-not-create.md:
only a same-user process can put a file inside the CLI's own 0700 `cyrius-<pid>/…/lib/` while the resolve runs, and the
file lost is that process's own, in the CLI's private directory. Not a security finding (no boundary is crossed).
**Kind:** tooling (cbt/deps.cyr `_dep_copy_file`, the kill handler's scratch-tree records).
**Discovered:** unit I5, fixing the predicted-temp issue above. That fix (73249ddb5) records the temp `_aw_open`
actually CREATED, with HUP / INT / TERM held across the create, so the name recorded is always one the CLI made — but
the record outlives the file: once `_aw_commit` renames the temp into place (or `_aw_abort` unlinks it), its name is
free, and it stays in `_dep_scr_files` until the scratch ends. The predicted-temp filing's surface was the name
recorded BEFORE the create; this window is AFTER the rename, so it was filed, not folded in.

## Reproduction

```sh
# r5.sh <cyrius CLI> <cyrius tree (for lib/)> <workdir>
# A scratch resolve's copies are renamed into place; a file another same-user process then puts
# at a temp name one of them used is unlinked by the kill.
CLI=$1; ROOT=$2; W=$3
rm -rf "$W"; mkdir -p "$W/bin" "$W/p/lib" "$W/home/versions/6.6.6" "$W/tb"
printf '#!/bin/sh\necho $$ > "%s/git.pid"\nexec sleep 60\n' "$W" > "$W/bin/git"; chmod +x "$W/bin/git"
cp -R "$ROOT/lib" "$W/home/versions/6.6.6/lib"; echo 6.6.6 > "$W/home/current"
printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n\n[deps.foo]\ngit = "https://example.invalid/foo"\ntag = "1.0.0"\nmodules = ["dist/foo.cyr"]\n' > "$W/p/cyrius.cyml"
printf 'x\n' > "$W/p/cyrius.lock"
( cd "$W/p" && PATH="$W/bin:$PATH" HOME="$W/nohome" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
  TMPDIR="$W/tb/" sh -c 'echo $$ > "$0"; exec "$@"' "$W/cli.pid" "$CLI" deps --locked > "$W/out" 2>&1 ) &
B=$!
# the stdlib leaves are copied and renamed into place before the clone the stand-in git sleeps in
while [ ! -s "$W/git.pid" ]; do sleep 0.02; done
P=$(cat "$W/cli.pid"); L="$W/tb/cyrius-$P/locked-deps/lib"
echo "copied: $(ls "$L" | grep -vc cyrtmp) files, $(ls "$L" | grep -c cyrtmp) temps left"
# another same-user process puts a file at <file>.cyrtmp.<pid>.<n>, n = 1..40, beside each copy
: > "$W/planted"
for f in $(ls "$L"); do n=1; while [ $n -le 40 ]; do echo mine > "$L/$f.cyrtmp.$P.$n"; echo "$f.cyrtmp.$P.$n" >> "$W/planted"; n=$((n + 1)); done; done
echo "planted: $(wc -l < "$W/planted" | tr -d ' ')"
kill -TERM "$P"; wait $B
kill -KILL "$(cat "$W/git.pid")" 2>/dev/null
echo "after the kill: $(ls "$L" 2>/dev/null | grep -c cyrtmp) planted files left; unlinked:"
while read -r f; do [ -f "$L/$f" ] || echo "  $f"; done < "$W/planted"
```

```
l6715-infratools @ 73249ddb5 (the held record):
copied: 16 files, 0 temps left
planted: 640
after the kill: 624 planted files left; unlinked:
  alloc.cyr.cyrtmp.700347.7
  alloc_agnos.cyr.cyrtmp.700347.12
  alloc_cx.cyr.cyrtmp.700347.13
  alloc_macos.cyr.cyrtmp.700347.11
  alloc_windows.cyr.cyrtmp.700347.10
  atomic.cyr.cyrtmp.700347.8
  fnptr.cyr.cyrtmp.700347.14
  poison.cyr.cyrtmp.700347.9
  string.cyr.cyrtmp.700347.16
  syscalls.cyr.cyrtmp.700347.1
  syscalls_aarch64_linux.cyr.cyrtmp.700347.5
  syscalls_linux_common.cyr.cyrtmp.700347.4
  syscalls_macos.cyr.cyrtmp.700347.6
  syscalls_windows.cyr.cyrtmp.700347.2
  syscalls_x86_64_agnos.cyr.cyrtmp.700347.15
  syscalls_x86_64_linux.cyr.cyrtmp.700347.3
5c0a2b34b (the predicted record): the same 16 names (pid 700479) unlinked, 624 of 640 left.
```

Exactly one planted file per copy goes: the one at the temp name that copy created and renamed into place. The other
624 (names no copy used) stay.

## Root cause

`_dep_copy_file` (cbt/deps.cyr) pushes the temp's name onto `_dep_scr_files` once `_aw_open` has created it, and
nothing ever takes it off: after `_aw_commit` renames the temp over the destination (or `_aw_abort` / a failed commit
unlinks it) the name no longer refers to anything of the CLI's, but `_cbt_sig_tree_drop` (cbt/sigclean.cyr) still
unlinks every recorded file on a signal, whatever sits at that name by then.

Related shape, left as 6.7.15 decided it (the I5 brief: "`_dep_scr_file(dst)` stays as it is"): the destination is
recorded before it exists, so a file put at `<dst>` between that record and the copy's rename would also be unlinked by
a kill in that window (after the rename `<dst>` is the CLI's own copy).

## Proposed fix

Forget the temp once it is gone: remember its index when it is recorded (`vec_len(_dep_scr_files) - 1`, under the
hold), and store 0 there (the handler already skips a 0 slot) once `_aw_commit` / `_aw_abort` returns — with HUP / INT /
TERM held across the commit and the clear, so no kill lands between the rename and the clear (the hold then spans an
fsync, a close and a rename). Rows: `cli_temp_dir_no_leak.sh` axis 7 with the shape above (all planted files survive,
nothing of the resolve's own left beside them); `tests/tcyr/crossos/cli_scratch_resolve_kill.tcyr`: a CHILD that copies,
then plants at the name its copy used, then SIGTERMs itself, keeps the planted file.
