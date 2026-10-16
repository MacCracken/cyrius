# A `cyrius distlib` killed mid-verify leaves its stdlib mirror `dist/.dlverify-<pid>/` (114 files) in the project — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-7: the kill handler gains one scratch-tree slot (`_cbt_sig_tree_set`, owner-checked). `_distlib_mirror_make` arms it once the mirror's root exists, and `_distlib_mirror_drop` clears it. After stopping the children and unlinking the names, the handler unlinks the mirror's files and removes its directories deepest first, using plain loads. The round's `entry.cyr` is tracked as a name, and each mirror file is recorded before its write creates it. The filed repro now leaves `p/dist` holding only d7.cyr (`cli rc=143`, `tb:` empty). Before, `dist/.dlverify-<pid>/` kept 114 files. No decision needed. Rows: `cli_temp_dir_no_leak.sh` axis 7's distlib kill row (no mirror left; it goes RED with the slot never set, or with entry.cyr untracked); `crossos/cli_kill_handler.tcyr` scenario F (a forked child spares the tree, and this process's SIGTERM removes it; no tree drop → 3 RED, no owner check → 1 RED) on x86_64, qemu-aarch64, pi, ecb and ach; the slot's rows also run on cass and wine. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools, the CLI built from
`cbt/cyrius.cyr` by the tree's `build/cycc`, with the 6.7.12 kill handler of
2026-10-13-cli-killed-mid-compile-leaves-scratch.md applied). Met while fixing that issue: the handler now cleans the
private temp dir of a SIGTERM'd distlib verify (its own `dlverifyerr<t>` and, through the forwarded signal, every
per-target child's `cpp_<pid>` / `dlverifyout<t>.tmp.<pid>`), but the verify's OTHER scratch — the copy of the pinned
stdlib snapshot it makes under the PROJECT, `dist/.dlverify-<pid>/lib/` — is not a temp-dir name and is not tracked,
so a kill leaves it. That issue's filed surface is the temp dir (its acceptance: "an empty `cyrius-<pid>` dir (or
none)"); this is a second location.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Low — litter in the project's `dist/` (one stdlib copy per killed run, ~114 files at 6.7.12); a dot
directory, so `ls` hides it, but `git status` shows it untracked unless `dist/` is ignored, and nothing ever removes
it (check.sh's reaper only looks under `$TMPDIR`). The next run uses its own pid, so it never collides.
**Affects:** every CLI since the per-round mirror (`_distlib_mirror_make`, 6.6.x); a refused or failed verify with
the CLI alive already drops it (`_distlib_mirror_drop`; cli_temp_dir_no_leak.sh axis 7's distlib row asserts "no
dist/.dlverify-<pid> mirror").

## Reproduction

```sh
# (sh; ROOT = a cyrius checkout with build/cyrius built from its cbt/) stand-in compilers that sleep, so the
# verify's six per-target compiles are running when the CLI is SIGTERM'd
W=$(mktemp -d); cd "$W"; V=$(tr -d '[:space:]' < "$ROOT/VERSION")
mkdir -p bin home/versions/$V p/src tb
cp "$ROOT/build/cyrius" bin/cyrius
printf '#!/bin/sh\necho $$ >> "%s/cc.pids"\ncat > /dev/null\necho partial\nexec sleep 60\n' "$W" > bin/cycc
cp bin/cycc bin/cycc_aarch64; chmod +x bin/*
cp -R "$ROOT/lib" home/versions/$V/lib
printf '[package]\nname = "d7"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$V" > p/cyrius.cyml
printf 'fn d7_a(): i64 { return 1; }\n' > p/src/lib.cyr
( cd p && CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 TMPDIR="$W/tb" exec ../bin/cyrius distlib ) > out 2>&1 & pid=$!
while [ "$(wc -l 2>/dev/null < cc.pids || echo 0)" -lt 5 ]; do sleep 0.05; done
echo "in flight:"; ls -A tb/cyrius-*/ | tr '\n' ' '; echo
kill -TERM $pid; wait $pid; echo "cli rc=$?"
echo "tb: $(ls tb)"; ls -A p/dist; for d in p/dist/.dlverify-*; do echo "$d: $(find "$d" -type f | wc -l) files"; done
```

```
in flight:
cpp_182742 cpp_182743 cpp_182744 cpp_182746 cpp_182748 cpp_182750 dlverifyerr0 dlverifyerr1 dlverifyerr2 dlverifyerr3 dlverifyerr4 dlverifyerr5 dlverifyout0.tmp.182742 dlverifyout1.tmp.182743 dlverifyout2.tmp.182744 dlverifyout3.tmp.182746 dlverifyout4.tmp.182748 dlverifyout5.tmp.182750
cli rc=143
tb:
.dlverify-182738
d7.cyr
p/dist/.dlverify-182738: 114 files
expected: no dist/.dlverify-<pid> after the SIGTERM (the temp dir is already clean)
```

(Before the 6.7.12 handler the same run also left `tb/cyrius-<pid>/dlverifyerr0..5` and six stand-in compilers
running.)

## Root cause

`_distlib_mirror_make` (cbt/commands.cyr) records every file and directory it creates in `_dl_mirror_files` /
`_dl_mirror_dirs` (vecs) and `_distlib_mirror_drop` removes them on every return path of the verify. The kill handler
(`_cbt_sig_fire`, cbt/sigclean.cyr) unlinks only the names in its fixed table (`_cbt_scratch_track`), and the mirror's
paths are never registered: the table has 32 slots, and the mirror is ~114 files plus its directories.

## Proposed fix

Give the handler the mirror as one more thing it removes, without allocating: register the mirror's ROOT with the
handler (a single slot, set after `_distlib_mirror_mkdir(m)` succeeds and cleared by `_distlib_mirror_drop`), and in
the handler walk the two vecs `_distlib_mirror_make` already filled (reading a vec is plain loads; the handler never
grows or frees it), unlinking the files and rmdir-ing the directories deepest first — the drop's own order. Row:
cli_temp_dir_no_leak.sh axis 7's distlib kill row asserts no `dist/.dlverify-*` after the SIGTERM; mutation (the slot
never set) RED.
