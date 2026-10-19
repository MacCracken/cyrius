# cbt/ and programs/ child redirects run `sys_dup2(fd, N); sys_close(fd)` with no same-fd guard: `cyrius build --target=js` with stdout closed fails "could not write the output (0 of 29 bytes): errno 9" — the lib/ half was fixed in 6.7.15, these copies were not — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 libfix3 lane (branch l6715-libfix3, after 6a1184258, which
fixed the same class in lib/process.cyr, lib/regression.cyr and lib/pam.cyr —
issues/archived/2026-10-18-process-capture-redirect-closes-its-own-std-fd.md) with the worktree's `build/cyrius` (x86_64 Linux).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 libfix3 lane, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6 — a lib-adjacent defect (cbt / programs): with 6.7.16's first items) — never 7.x.
**Severity:** Low — a CLI verb (and the check driver / LSP / test-runner children) fails or loses a stream when the
calling process was started with a standard fd closed. No boundary is crossed: the caller's own fd state drives it.
**Found:** by the 6.7.15 libfix3 lane (unit L4) while sweeping `sys_dup2` callers for the lib/ fix; the brief scoped
the fix to lib/process.cyr, lib/regression.cyr and lib/pam.cyr, so these copies are filed.

## Reproduction

```sh
printf 'const x: number = 1;\nconsole.log(x);\n' > x.ts
cyrius build --target=js x.ts out.js;  echo "rc=$?"     # control
cyrius build --target=js x.ts out2.js 1>&-; echo "rc=$?"  # stdout closed
```

```text
emit-js x.ts -> out.js [js] OK            rc=0, out.js 29 bytes
error: could not write the output (0 of 29 bytes): errno 9     rc=1, no out2.js
```

## Root cause

`cbt/build.cyr` `_emit_js` (~line 111): the child opens the temp output — with the CLI's fd 1 closed it opens AT 1 —
then `sys_dup2(ofd, 1); sys_close(ofd);`: `dup2(1, 1)` is a no-op and the close closes the redirect it just made, so
cycc `--emit-js` writes its JS to a closed stdout. The same shape, one source fd per redirect, at:

- `cbt/pulsar.cyr` ~59 / ~62 (`sys_dup2(sfd, 0); sys_close(sfd);`, `sys_dup2(ofd, 1); sys_close(ofd);`)
- `programs/ts_test_runner.cyr` ~44-49
- `programs/cyrius-lsp.cyr` ~1090-1095 (`nfdi` → 0, `nfdo` → 1, `pipe_write` → 2)
- `programs/checks/` — `selfhost.cyr` (eight child setups, ~476-1007), `shared.cyr` ~310-315 / ~367-372 / ~407-412
  (`dup2(out_fd, 1); dup2(out_fd, 2); close(out_fd)` — out_fd may BE 1 or 2), `services.cyr` ~30, `crosshost.cyr`
  ~34-39 / ~108-114 / ~159-165, `ts.cyr` ~132-136 / ~177-182 / ~242-245, `platform_efi.cyr` ~1949-1952

## Fix direction

The lib/ fix's shape: close the source fd only when it is not the target (`if (fd != N) { sys_close(fd); }`; for the
both-streams form, only when it is neither 1 nor 2). Several of these sites also open their output BEFORE a lower
redirect (e.g. pulsar opens `sfd` then redirects it to 0; an `out_fd` that landed on 0 is overwritten by a later
stdin redirect) — the ordering shape filed separately for lib/regression.cyr
(archived/2026-10-18-regression-output-fd-overwritten-by-stdin-redirect.md); fix both together per site. Row: the repro above
answers rc=0 and a 29-byte out2.js; a `programs/checks` row with fd 1 / 2 closed.
