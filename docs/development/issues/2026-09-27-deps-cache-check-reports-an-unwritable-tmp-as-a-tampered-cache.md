# `cyrius deps` reports an unwritable `/tmp` as a TAMPERED dep cache, and advises deleting it — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-09-27 on 6.6.6 (the reproduction below, run verbatim), and read in
source at HEAD `d5697d73`.
**Placement:** unpinned — 6.x-line backlog (cli).
**Discovered:** 2026-09-27, aethersafha 0.16.27 development: every `cyrius build` / `test` / `deps` refused all
ten deps as tampered for a few minutes, then passed again with nothing changed. The machine's `/tmp` is a
tmpfs mounted `usrquota`, and the user was at quota; the cyrius LSP failed at the same moment with
`could not write the output … errno 122` (EDQUOT).
**Severity:** Medium. It fails closed — nothing untrusted is accepted — but it is a **false tamper
accusation** that names the wrong cause, fires for **every** cached dep at once, comes and goes with a quota
(so it reads as cache corruption that heals itself), and tells the user to `rm -rf` a healthy cache.
**Affects:** 6.6.6 CLI, `cbt/deps.cyr` (`_git_run`, `_git_rev`, `_git_cache_verify`) and `cbt/build.cyr`
(`_cbt_tmpbase`).

## Summary

`_git_cache_verify` resolves `refs/tags/<tag>^{commit}` through `_git_rev`, which runs git via `_git_run` with
stdout redirected into a capture file under the CLI's private temp dir in `/tmp`. When that file cannot be
created (EDQUOT, ENOSPC, no inodes), the child **does not stop**: `ofd < 0` just skips the `dup2`, git runs
with the parent's stdout, and its correct answer goes to the terminal. `_git_rev` then reads no capture, returns
0 — the same value as "the tag does not resolve" — and `_git_cache_verify` returns reason 2:

```
error: cached checkout for dep 'bhumi' tag '1.4.5' does not match its source — refusing tampered cache: HEAD is not the tag's commit (a local commit, a checkout, or a moved tag).
  cache: /home/macro/.cyrius/deps/bhumi/1.4.5
  offline restore: rm -f …/.git/index && git … reset -q --hard refs/tags/1.4.5 && git … clean -qffdx
  or: rm -rf /home/macro/.cyrius/deps/bhumi/1.4.5   (re-clones from the remote on the next resolve).
```

The cache was intact: HEAD, `refs/tags/1.4.5` and the working tree all agreed (`git rev-parse` by hand, with the
same flags and `GIT_CEILING_DIRECTORIES`, printed `21ca348c…` and exited 0).

⚠ **`TMPDIR` does not help.** `_cbt_tmpbase` (`cbt/build.cyr:734`) returns the literal `"/tmp"` on every POSIX
target, so a user whose `/tmp` is full or quota-limited has no way to point the CLI elsewhere.

## Reproduction

Needs only a project with a tagged `[deps.<name>]` resolved once, and unprivileged user namespaces. Each run gets
a PRIVATE `/tmp`, so nothing shared is touched:

```sh
cd <project>
# control — a roomy private /tmp: resolves
unshare -r -m sh -c 'mount -t tmpfs -o nr_inodes=64 tmpfs /tmp && cyrius deps'
# an inode-starved private /tmp: the private dir is created, its capture files are not
unshare -r -m sh -c 'mount -t tmpfs -o nr_inodes=3 tmpfs /tmp && cyrius deps'
```

Measured on 6.6.6: the control prints `10 deps resolved`; the starved run prints the bare commit sha (git's
uncaptured stdout) and then the tamper refusal above for the first dep.

## Where it happens (HEAD `d5697d73`)

- `_git_run` (`cbt/deps.cyr:3152`): in the child, `ofd = sys_open(outf, O_WRONLY | O_CREAT | O_TRUNC, 0x180)`;
  on failure it neither exits nor reports, so git runs uncaptured.
- `_git_rev` (`cbt/deps.cyr`, after `_git_run`): `if (nn < 40) { return 0; }` — "no capture" and "no such rev"
  are one value.
- `_git_cache_verify` (`cbt/deps.cyr:3624-3631`): `tc == 0` → reason 2 → the message above.
- ⭐ The right shape already exists 40 lines further on: `if (osz < 0) { … return 3; }   # no capture = git
  failed, not "clean"` (`cbt/deps.cyr:3673`). The rev path is the one that lacks it.

## Fix sketch

1. `_git_run`: when `outf != 0` and its open fails, `sys_exit` with a distinct code before `execve` — never run
   git with an uncaptured stdout.
2. `_git_rev`: return a distinct value for "could not run / could not capture" versus "does not resolve", and
   have `_git_cache_verify` map it to its own reason — still fail closed, but say what failed (for example
   *"could not verify the cache: cannot write under /tmp (errno 122)"*) and **do not** suggest deleting the cache.
3. `_cbt_tmpbase`: honour `$TMPDIR` on POSIX when it is set and is an absolute path, keeping the private 0700
   directory discipline.

Gate idea: the two `unshare` runs above as a `tests/gates/toolchain/` script, skipped with a named reason where
user namespaces are unavailable.
