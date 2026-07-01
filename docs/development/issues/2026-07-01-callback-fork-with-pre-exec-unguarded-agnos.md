# `callback.cyr` `fork_with_pre_exec` unguarded on agnos

**Filed:** 2026-07-01
**Reporter:** agnos base-stack agnos-readiness pass (phylax consumer)
**Severity:** low — blocks `--agnos` builds of any consumer that lists the
`callback` stdlib module, even when only its `vec_*` higher-order helpers are used.
**Status:** OPEN (surfaced per hands-off policy; not patched here)

## Summary

`lib/callback.cyr` defines `fork_with_pre_exec(cmd, argv, envp, cb_fn, cb_data)`
which calls `sys_fork()` + `sys_execve()` **unconditionally** (no target guard):

```
fn fork_with_pre_exec(cmd, argv, envp, cb_fn, cb_data): i64 {
    var pid = sys_fork();          # undefined on agnos
    ...
        sys_execve(cmd, argv, envp); # undefined on agnos
        sys_exit(127);
    ...
}
```

agnos's frozen 0-33 syscall surface has no `fork`/`execve`, so on the agnos
target `sys_fork` / `sys_execve` are undefined. Because a consumer that lists
`callback` in `cyrius.cyml` `stdlib = [...]` pulls the **whole module** (the
`vec_*`/`for_each` higher-order helpers travel with `fork_with_pre_exec`),
`fork_with_pre_exec` stays reachable and the `--agnos` build fails:

```
error: refusing to emit binary with 2 reachable undefined function(s)
  (sys_fork, sys_execve)
```

This bit **phylax** (a `--agnos` base-stack consumer) even though phylax uses
*none* of `callback.cyr`'s functions — the module was an unused dependency, and
dropping it from phylax's `stdlib` list cleared the build. But any consumer that
*does* legitimately use the `vec_*` helpers on agnos would be stuck.

## Prior art in the same stdlib

`lib/process.cyr` already solves exactly this: its Linux `fork`/`exec` block is
wrapped in `#ifndef CYRIUS_TARGET_AGNOS`, and the agnos peer
(`lib/process_agnos.cyr`, dispatched via `#ifdef CYRIUS_TARGET_AGNOS include ...`)
provides fork-free equivalents through `sys_spawn`/`sys_waitpid`. `callback.cyr`
should follow the same pattern.

## Suggested fix

Guard `fork_with_pre_exec` so it is absent on agnos (the higher-order `vec_*`
helpers are pure and stay available on every target):

```
#ifndef CYRIUS_TARGET_AGNOS
fn fork_with_pre_exec(cmd, argv, envp, cb_fn, cb_data): i64 { ... }
#endif
```

Optionally, provide an agnos peer that routes through the process-agnos
`sys_spawn` path (no pre-exec callback slot — agnos spawns an in-memory ELF, so
the "run callback in the child before exec" contract doesn't map cleanly; a
guard-out is likely the honest choice).

## Repro

```
# any repo with `callback` in cyrius.cyml stdlib and nothing else pulling fork:
cyrius build --agnos src/main.cyr /tmp/out
# → error: refusing to emit binary with 2 reachable undefined function(s)
```
