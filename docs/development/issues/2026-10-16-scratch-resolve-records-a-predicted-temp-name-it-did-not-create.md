# A scratch resolve keeps a predicted temp name that `_aw_open` skipped, so a kill unlinks a file the CLI did not create — OPEN

**Status:** 🟡 **OPEN** — met 2026-10-16 by the 6.7.14 tools lane's review of 33e3b49c1 (the fix for
issues/archived/2026-10-15-deps-scratch-resolve-left-in-temp-dir-on-kill.md) and reproduced by the lane's fix step
(l6714-tools @ 69c72ca09, the CLI built from `cbt/cyrius.cyr` by the tree's `build/cycc`). The lane introduced it:
the 2600f67f CLI records nothing, so it unlinks nothing (it leaves the whole scratch, the bug 33e3b49c1 fixed). It
also contradicts the lane's CHANGELOG claim that "a file it did not write survives".
**Placement:** 6.7.15 — repair 5 (infratools lane, wave 1, unit I5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — only a same-user process can reach it, by planting `<dst>.cyrtmp.<pid>.<n>` inside the CLI's own
0700 `cyrius-<pid>/…/lib/` while the resolve runs. The file lost is that process's own, in the CLI's private
directory. This is not a security finding: it needs no boundary crossing (CLAUDE.md § Security Audit Process).
**Affects:** `cyrius deps --locked`, and the pin-move dry pass of a plain `cyrius deps`, on every POSIX CLI from
6.7.14 on: cbt/deps.cyr `_dep_copy_file` while `_dep_scr_files` is recording.

## Reproduction

```sh
# r2.sh <cyrius CLI> <cyrius tree (for lib/)> <workdir>
CLI=$1; ROOT=$2; W=$3
rm -rf "$W"; mkdir -p "$W/bin" "$W/p/lib" "$W/home/versions/6.6.6" "$W/tb"
printf '#!/bin/sh\necho $$ > "%s/git.pid"\nexec sleep 60\n' "$W" > "$W/bin/git"; chmod +x "$W/bin/git"
cp -R "$ROOT/lib" "$W/home/versions/6.6.6/lib"; echo 6.6.6 > "$W/home/current"
printf '[package]\nname = "r"\nversion = "0.0.1"\ncyrius = "6.6.6"\n\n[deps]\nstdlib = ["syscalls", "string"]\n\n[deps.foo]\ngit = "https://example.invalid/foo"\ntag = "1.0.0"\nmodules = ["dist/foo.cyr"]\n' > "$W/p/cyrius.cyml"
printf 'x\n' > "$W/p/cyrius.lock"
# syscalls.cyr is a FIFO the copy blocks in until it is released
S="$W/home/versions/6.6.6/lib/syscalls.cyr"; mv "$S" "$S.real"; mkfifo "$S"
( exec 7<> "$S"; exec sleep 600 ) 2>/dev/null &
H=$!
( cd "$W/p" && PATH="$W/bin:$PATH" HOME="$W/nohome" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
  TMPDIR="$W/tb/" sh -c 'echo $$ > "$0"; exec "$@"' "$W/cli.pid" "$CLI" deps --locked > "$W/out" 2>&1 ) &
B=$!
while [ ! -s "$W/cli.pid" ]; do sleep 0.02; done; P=$(cat "$W/cli.pid"); L="$W/tb/cyrius-$P/locked-deps/lib"
while ! ls "$L" 2>/dev/null | grep -q '^syscalls\.cyr\.cyrtmp\.'; do sleep 0.02; done
K=$(ls "$L" | sed -n 's/^syscalls\.cyr\.cyrtmp\.[0-9]*\.\([0-9]*\)$/\1/p')
echo "in flight: $(ls "$L" | tr '\n' ' ')"
# another same-user process holds the next twenty string.cyr temp names
j=1; while [ $j -le 20 ]; do echo mine > "$L/string.cyr.cyrtmp.$P.$((K + j))"; j=$((j + 1)); done
echo "planted: string.cyr.cyrtmp.$P.$((K + 1)) .. .$((K + 20))"
# release syscalls.cyr: its content, then EOF (the real file back in place for any later open)
exec 8> "$S"; rm -f "$S"; mv "$S.real" "$S"; cat "$S" >&8; exec 8>&-; kill $H
while [ ! -s "$W/git.pid" ]; do sleep 0.02; done
echo "before the kill: $(ls "$L" | grep -c '^string\.cyr\.cyrtmp\.') string.cyr temps, string.cyr $( [ -f "$L/string.cyr" ] && echo copied || echo missing)"
kill -TERM "$P"; wait $B
kill -KILL "$(cat "$W/git.pid")" 2>/dev/null
echo "after the kill: $(ls "$L" 2>/dev/null | grep -c '^string\.cyr\.cyrtmp\.') of the 20 planted files left; missing:"
j=1; while [ $j -le 20 ]; do [ -f "$L/string.cyr.cyrtmp.$P.$((K + j))" ] || echo "  string.cyr.cyrtmp.$P.$((K + j))"; j=$((j + 1)); done
```

```
HEAD (69c72ca09):
in flight: syscalls.cyr.cyrtmp.1781967.1
planted: string.cyr.cyrtmp.1781967.2 .. .21
before the kill: 20 string.cyr temps, string.cyr copied
after the kill: 19 of the 20 planted files left; missing:
  string.cyr.cyrtmp.1781967.16
2600f67f:
before the kill: 20 string.cyr temps, string.cyr copied
after the kill: 20 of the 20 planted files left; missing:
```

The resolve's own files are copied and renamed as normal: string.cyr, and the temp it actually wrote, which is the
first free name after the planted range. The one
planted file that matched the counter's next value, `.16`, is unlinked by the kill handler. The rest of the scratch's
rmdir-only contract holds: the directories that still hold the other 19 files stay.

## Root cause

`_dep_copy_file` (cbt/deps.cyr) records the destination and `stmp = _dep_scr_next_tmp(dst)` before
`_aw_open(dst)`, so the temp is tracked before it can exist. `_dep_scr_next_tmp` names `_io_tmp_name`'s next
`<dst>.cyrtmp.<pid>.<ctr+1>` without spending the counter. `_aw_open` → lib/io.cyr `_io_tmp_open` then opens each name
`O_CREAT | O_EXCL | O_NOFOLLOW`, and if the name is taken it moves to the next counter value (up to 64 tries). When
the opened temp differs from the prediction, the code appends it:

```cyr
if (stmp != 0) {
    if (_cstr_eq(load64(dh + 8), stmp) == 0) { _dep_scr_file(load64(dh + 8)); }
}
```

The predicted name, which is the existing file `_io_tmp_open` declined to touch, stays in `_dep_scr_files`. On a
signal, `_cbt_sig_tree_drop` (cbt/sigclean.cyr) unlinks every recorded file, including that one.

## Proposed fix

When the opened temp differs from `stmp`, overwrite stmp's own slot in `_dep_scr_files` with the real temp instead of
appending it. That is one 64-bit store into the vec's data, which the handler's plain loads read safely (it reads the
old name or the new one, never a torn value). A window remains between the prediction and `_aw_open`'s create, in
which a kill can still unlink a name planted in that instant. Closing it fully needs the temp tracked from inside
`_io_tmp_open` (a lib/io.cyr hook) or the handler checking the file it unlinks. Rows: `cli_temp_dir_no_leak.sh`
axis 7 with the planted range above. After the kill, all 20 planted files survive (and only they are left under
`locked-deps/lib/`). The mid-copy `.cyrtmp` row stays green.
