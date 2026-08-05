# `lib/syscalls.cyr` ships `signal_ignore` with no counterpart, so a process that ignores a signal cannot hand the default back to a child it execs

**Status:** 🟡 **OPEN** — filed 2026-08-05, worked around consumer-side with a private copy.
**Placement:** unpinned — 6.x-line backlog. Additive, ~20 lines, no blast radius.
**Discovered:** 2026-08-05 fixing an agnosai `SIGPIPE` defect found by the M7 sandbox audit.
**Severity:** Low — a gap, not a bug. Nothing in the stdlib is wrong; something is missing.
**Affects:** cycc 6.5.6 and earlier.

## Summary

`signal_ignore(signum)` (`lib/syscalls.cyr:98`) sets a signal's disposition to
`SIG_IGN`. There is no `signal_default(signum)`, and no other route back:
`grep -n 'fn signal_' lib/*.cyr` returns exactly one line.

That is fine for the case the function was written for — a server ignoring
`SIGPIPE` for its own lifetime — and insufficient for the case underneath it:
**a process that ignores a signal and then `fork`+`execve`s a child.**
`SIG_IGN` is inherited across `execve`, where a handler is reset. So every
descendant of a process that called `signal_ignore` inherits the ignore, for
good, with nothing in the stdlib able to undo it.

## Why this matters, concretely

The shape is not exotic. Any Cyrius program that both

1. writes to a pipe or socket whose peer may vanish — so it must ignore
   `SIGPIPE` or be killed by it, and
2. spawns child processes

has to choose between dying on a disconnect and silently changing its
children's signal semantics. There is no third option in the stdlib today.

The reference implementation for the correct behaviour is Rust: `std` installs
the process-wide `SIG_IGN` for `SIGPIPE` at startup for reason (1), and
`std::process::Command` restores `SIG_DFL` in the child before exec for reason
(2). A Cyrius program can do the first half and not the second.

The consumer case: agnosai's sandbox spawns tools through `fork`/`execve` and
feeds them stdin. A tool that stops reading takes the *parent* down with
`SIGPIPE` unless the parent ignores it — measured at exit 141 (128+13), three
runs out of three. Ignoring it fixes the parent and silently changes every
sandboxed tool: a tool running `cmd | head` now sees `write` return `EPIPE`
where the same tool outside the sandbox dies on the signal. Shell pipelines,
`head`, `yes`, and anything that relies on `SIGPIPE` to terminate a producer
behave differently inside the sandbox than outside it, which is exactly the kind
of silent divergence a sandbox must not introduce.

## Reproduction

The gap itself needs no program to demonstrate — `grep -n 'fn signal_'
lib/*.cyr` returns one line. What the missing call costs is visible with the
shell standing in for any process that calls `signal_ignore` and then spawns
(`trap "" PIPE` is `SIG_IGN` for `SIGPIPE`):

```sh
$ /bin/sh -c 'grep ^SigIgn /proc/self/status'
SigIgn: 0000000000000000

$ bash -c 'trap "" PIPE; /bin/sh -c "grep ^SigIgn /proc/self/status"'
SigIgn: 0000000000001000
```

Bit 12 (`0x1000`) is `SIGPIPE`. The ignore crosses `execve` into a program that
never asked for it, and the second command is what every Cyrius child of a
`signal_ignore` caller looks like.

## Proposed fix

Add `signal_default(signum)` beside `signal_ignore`, identical except that
`sa_handler` is `0` (`SIG_DFL`) instead of `1` (`SIG_IGN`):

```cyr
# Set a signal's disposition back to SIG_DFL. The counterpart to signal_ignore.
#
# Needed by any process that ignores a signal and then execs: SIG_IGN is
# INHERITED across execve (a handler is not), so without this a child inherits
# a disposition its own code never chose. Call it in the child between fork and
# execve, which is what std::process::Command does for SIGPIPE.
fn signal_default(signum): i64 {
    #ifdef CYRIUS_TARGET_LINUX
    var act[32];
    var ap = &act;
    var i = 0;
    while (i < 32) { store8(ap + i, 0); i += 1; }
    store64(ap, 0);   # sa_handler = SIG_DFL (0)
    #ifdef CYRIUS_ARCH_X86
    return syscall(13, signum, ap, 0, 8);
    #endif
    #ifdef CYRIUS_ARCH_AARCH64
    return syscall(134, signum, ap, 0, 8);
    #endif
    #endif
    #ifdef CYRIUS_TARGET_MACOS
    var mact[32];
    var mp = &mact;
    var mi = 0;
    while (mi < 32) { store8(mp + mi, 0); mi += 1; }
    store64(mp, 0);
    #ifdef CYRIUS_ARCH_X86
    return syscall(13, signum, mp, 0);
    #endif
    #ifdef CYRIUS_ARCH_AARCH64
    return syscall(134, signum, mp, 0);
    #endif
    #endif
    #ifdef CYRIUS_TARGET_WIN
    return 0;
    #endif
    #ifdef CYRIUS_TARGET_AGNOS
    return 0;
    #endif
}
```

The 32-byte `{sa_handler, 0, 0, 0}` struct and the per-target syscall routing
are already argued in `signal_ignore`'s comment; nothing new is being claimed
about the ABI. The only difference is the first word.

Worth considering alongside: `signal_ignore`'s doc comment says nothing about
`SIG_IGN` surviving `execve`. That property is the reason this counterpart is
needed, and a caller reading only that comment has no way to know it.

## Consumer-side workaround

agnosai carries a private `_agnosai_signal_default` in
`src/sandbox/spawn.cyr` — the code above, Linux arms only, since the sandbox is
Linux-only. It is called in the child between the `dup2`s and `execve`. It is
mutation-verified: deleting the call makes the child's `/proc/self/status`
report `SigIgn: 0000000000001000` and fails a suite assertion that reads bit 12
out of the mask.

The copy exists only because the stdlib has no such call; it should be deleted
the moment `signal_default` lands.
