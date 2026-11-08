# `path_which` — resolve a bare name against `$PATH`, in `lib/process.cyr`

**Filed:** 2026-11-06 from commandress 1.5.1 (`src/pathlookup.cyr`, which says this belongs in the stdlib).
**Status:** 🟡 **PROPOSED** — a missing stdlib primitive with measured consumer workarounds, not a capability gap.
**Placement:** not set. Its release is chosen at the next backlog re-triage.
**Severity:** Quality-of-life, with a security edge. Nobody is blocked, but the hand-rolled walks disagree on what a
`$PATH` entry means, and two of the differences decide whose binary runs.
**Affects:** `lib/process.cyr`, plus `lib/process_win.cyr` for the Windows split. No compiler, IR or backend change.

## Summary

`execve(2)` does no `PATH` lookup. That is libc's `execvp`, and Cyrius has no libc. `exec_vec`, `exec_capture` and the
rest of `lib/process.cyr` take a resolved path, and nothing in `lib/` resolves one: no fn calls `getenv("PATH")`. The
only route is `exec_cmd`, which goes through `/bin/sh -c` (`lib/process.cyr:1132`). `lib/process.cyr:1124` records what
the gap has already cost: a bare command name was "never `$PATH`-resolved → ENOENT → silent rc=127", which broke every
`cyriusly` heavy verb.

So each consumer that wants to run a tool by name, without a shell, writes the loop itself. This proposal asks for:

```cyrius
# The first regular, executable file named `name` on $PATH, as a fresh absolute
# path, or 0. See the rules below.
fn path_which(name): i64

# The same over a PATH-shaped string. For tests, and for a caller holding its own
# environment.
fn path_which_in(path_env, name): i64
```

`path_which` is free in the flat namespace. `which` is not: ai-hwaccel defines it, and so does its copy in szal.

## Motivation — the hand-rolled walks

Every site that walks `$PATH` under `~/Repos`, read on 2026-11-06. The table is why this is more than a tidy-up:

| Repo | Site | Empty entry | Relative entry | What counts as a hit | `PATH` unset |
|---|---|---|---|---|---|
| agnoshi 2.2.0 | `src/run_host.cyr:27` `path_lookup_in` | skipped | **skipped** | regular file, `X_OK` | built-in list |
| ai-hwaccel 2.5.6 | `src/detect/command.cyr:296`, `:363` `which_in` | skipped | **skipped** | regular file, `X_OK` | 0 |
| commandress 1.5.1 | `src/pathlookup.cyr:52` `find_in_path_with` | skipped | **skipped** | `X_OK` only | 0 |
| kriya 1.9.3 | `src/cmd/which.cyr` | the cwd, as POSIX says | searched | regular file, `X_OK` | 0 |
| nous 1.4.0 | `src/command.cyr` `which_path` | skipped | searched | **exists** | 0 |
| sit 1.13.2 | `src/wire_ssh.cyr` `_ssh_find_binary` | skipped | searched | `X_OK` only | built-in list |
| stiva 3.2.0 | `src/network_rootless.cyr` `stiva_which`, `src/runtime.cyr` `criu_available` | skipped | searched | **exists** | 0 |
| szal 2.3.2 | `src/mcp_tools_process.cyr` `_proc_path_lookup`, plus a vendored ai-hwaccel | skipped | searched | `X_OK` only | 0 |

kriya's `xargs` and `find -exec` carry their own `PATH` handling too, and kavach's `which_exists` skips `$PATH` and
probes a fixed list of directories instead.

What the differences mean:

- **Relative entries.** With `.` on `PATH`, sit, stiva, nous and szal will run a binary the current directory chose.
  agnoshi, ai-hwaccel and commandress each worked out independently that they must not. commandress calls this its
  audit F-8, and agnoshi's comment names it the `PATH` hijack.
- **Directories.** `access(X_OK)` passes a directory, so a directory named `node` ahead of the real tool hides it in
  commandress, sit and szal. The `execve` then fails, or never happens. commandress carries this as a known gap.
- **No execute test.** nous and stiva take any file that exists, so a non-executable file of that name ends the search.
- **Bugs already paid for.** Through 2.5.2 ai-hwaccel split on `:` on every target, so on Windows no tool was ever found,
  and an empty POSIX entry became `/<name>`. nous's `docs/development/issues/0002-sysdb-exec-bare-name-path.md` is the same
  gap from the other side. kriya's `find` had a `getenv` buffer that came back empty after a fork.

## Rules

Each is a choice a consumer made above. Having them once is the point.

1. **Only absolute entries are searched.** Empty and relative entries are skipped. This departs from POSIX on purpose: an
   empty entry means the cwd, and running what a directory holds is the hijack the three careful consumers refuse.
2. **A hit is a regular file with execute permission**, following symlinks: `stat`, `S_ISREG`, then `sys_access`. The
   stdlib's `sys_access` is what makes this work on aarch64, where commandress's raw `SYS_ACCESS` does not build.
3. **A `name` that is empty or holds a `/` returns 0.** The caller already has a path.
4. **`PATH` unset returns 0.** agnoshi and sit choose a default list, and a caller can still do that by passing one to
   `path_which_in`. A default inside the stdlib would hide a missing `PATH` from every other caller.
5. **One trailing `/` on an entry is dropped**, so `/usr/bin/` does not give `/usr/bin//sit`.
6. **Windows** splits on `;`, drops the double quotes around an entry, and tries `<dir>\<name>.exe`, as ai-hwaccel's
   `which_candidates` does. Its comment explains each of those.
7. **agnos** has no `access(2)`, so a hit there is a file that exists, as in ai-hwaccel's `_which_runnable`.
8. **One allocation per hit**, and none per miss: the candidate fits a frame buffer until it is the answer. A prompt
   renderer calls this on every redraw.

kriya's `which` is the one consumer that must keep POSIX behaviour, since being `which` is its job. It keeps its own walk.

## Repro

```sh
# Nothing in the stdlib reads PATH.
grep -n 'getenv("PATH")' lib/*.cyr      # no output on 6.7.18
grep -n '^fn exec_' lib/process.cyr     # every one takes a resolved path, or goes through sh

# The disagreement that matters. A planted `tool` in the cwd, with `.` on PATH:
#   sit, stiva, nous, szal  -> find it
#   agnoshi, ai-hwaccel, commandress -> skip it
```

## What it removes

- commandress: `find_in_path_with` and `find_in_path`, the bulk of `src/pathlookup.cyr`, which is 99 lines and exists for
  this reason. Its roadmap keeps the file's removal gated on this proposal.
- agnoshi `path_lookup_in`, ai-hwaccel `which_in` and `which_candidates`, nous `which_path`, sit `_ssh_find_binary`, stiva
  `stiva_which` and `criu_available`, szal `_proc_path_lookup`, each after a re-pin.
- sit, stiva, nous and szal lose the relative-entry behaviour in the same move, which is a fix for them.

## Tests

Pure tests through `path_which_in`, since the stdlib has no `setenv`: first hit wins; empty, relative and `.` entries
skipped; a directory, a FIFO and a non-executable file passed over for a later hit; a symlink to a binary found; a dangling
symlink passed over; a `name` with a `/` or empty; `PATH` unset; one trailing `/`; an entry longer than a frame buffer; the
Windows split on the Windows target.

## Alternatives

- **`execvp` in `lib/process.cyr`.** It runs the tool but gives no answer to "is it there?", which is what commandress,
  stiva, nous and kavach ask before deciding anything, and a prompt renderer needs the path to key its cache.
- **Keep POSIX semantics, and add a `safe` flag.** The unsafe form would stay the short one. The careful behaviour is the
  one every consumer that thought about it chose.
- **`exec_cmd` through `/bin/sh`.** Works, costs a shell per call, and puts a shell in the path of untrusted names.
