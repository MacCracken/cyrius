# On Linux a program's arguments come only from `/proc/self/cmdline`: no `/proc` or no free fd means `argc() == 0` — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-01 against live code at a1cf8c026: `lib/args.cyr` `args_init` still opens only `/proc/self/cmdline` (line 168).
**Placement:** unpinned — 6.x-line backlog, never 7.x.
**Discovered:** 2026-10-31 during owl's P(−1) audit (1.5.3, INFO-010; owl's half is FINDING-038).
**Severity:** Low. A hard failure, but one a program can now detect (`args_init` has returned a negative
errno since 6.7.12), so a careful consumer can refuse to run instead of misbehaving.
**Affects:** cyrius 6.7.18 (verified) Linux targets, x86_64 and aarch64; `lib/args.cyr` `args_init`.

## Summary

`args_init()` reads argv from `/proc/self/cmdline`. When that open fails, every program loses its whole
command line, though the kernel always places argv on the process's initial stack. That happens in a
chroot or minimal container without `/proc`, or when the process has no free descriptor (inherited
`ulimit -n`, fd exhaustion). macOS and agnos already read the initial stack: cycc parks the entry `rsp` in a
callee-saved register (`r15` on x86 macOS and agnos, `x28` on arm64 macOS) and `args` reads through it. The
Linux path in `lib/args.cyr` uses no such anchor and reads only `/proc`. Whether cycc's Linux entry can park
`rsp` the same way is cyrius's call; the stdlib side would then mirror the agnos reader.

Before owl 1.5.3, owl ignored `args_init`'s result and, with an unreadable command line, silently behaved as
if run with no arguments: it read stdin instead, and blocked forever when stdin was a socket.

## Reproduction

```sh
# a scratch project with the usual stdlib list
cyrius build repros/2026-10-31-cyrius-argv-without-proc.cyr build/argv
./build/argv one two three                          # args_init=118 argc=4
sh -c 'ulimit -n 3; ./build/argv one two three'     # args_init=-24 argc=0   (EMFILE)
```

## Proposed fix

Park the entry `rsp` on Linux the way macOS and agnos do, read `argc` / `argv` from the initial stack, and
keep `/proc/self/cmdline` only as a fallback. That removes the `/proc` dependency (and one open) for every
cyrius program. `getenv`'s `_env_load` could then read `envp` from the same anchor, as its macOS branch
already does.

## Consumer-side workaround

Check `args_init()`'s result. owl 1.5.3 prints `owl: cannot read the command line` and exits 2.
