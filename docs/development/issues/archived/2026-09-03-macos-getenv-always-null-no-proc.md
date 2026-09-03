# `getenv` always returns 0 on macOS — `/proc/self/environ` does not exist there

> ## ✅ DONE at cyrius 6.5.45 — `getenv` now reads the init-stack envp on macOS. Verified on real ecb (arm64) and ach (Intel).
>
> ⭐ **AND THE FILING UNDERCOUNTED THE BLAST RADIUS.** It states "Windows is served (the reroute routes `0xF015 GetEnvironmentVariableA`)". That reroute serves **cycc's own `_read_env`**; nothing in the stdlib ever called it, so `getenv` fell through to `/proc/self/environ` on Windows too and returned 0 for every name there as well. Found by the release gate's cross-host leg reddening on cass once the macOS half landed. Both are fixed and verified on hardware.
>
> ⛔ **The suite could not have caught either.** The test runner execs every `.tcyr` with `EMPTY_ENVP`, so environment reading had no in-suite reachability at all. The runner now supplies one fixed entry (`CYRIUS_TEST_ENV=1`) — determinism preserved, path reachable — and `tests/tcyr/crossos/getenv_environment.tcyr` exercises it on every host.

**Filed:** 2026-09-03 · **Found by:** thoth 0.44.3 (first macOS build since thoth 0.6.4)
**Toolchain:** 6.5.35 native on Apple Silicon (macOS 26.6.2); code path unchanged in 6.5.43
**Component:** `lib/io.cyr` — `getenv` / `_env_load`
**Severity:** MEDIUM — silent wrong answer, not a crash. Every consumer that reads the
environment on macOS behaves as if the variable is unset.

## What happens

`getenv` (lib/io.cyr:818) has exactly two branches:

```
#ifdef CYRIUS_TARGET_AGNOS
    return _agnos_getenv(name);          # reads envp off the exec init stack
#endif
#ifndef CYRIUS_TARGET_AGNOS
    _env_load();                         # opens /proc/self/environ
    ...
#endif
```

`_env_load` reads **`/proc/self/environ`**. macOS has no `/proc`, so the open fails,
`_env_len` stays 0, and `getenv` returns 0 for **every** name — on a process whose
environment is fully populated.

The AGNOS branch exists precisely because that target has no `/proc`; macOS is the same
class of target and has no branch. Windows is served (the reroute routes
`0xF015 GetEnvironmentVariableA`), so macOS is the only target with no environment access
at all.

## Reproduction (native, Apple Silicon)

```cyr
fn emit(s) { return syscall(SYS_WRITE, 1, s, strlen(s)); }
fn main() {
    var t = getenv("TERM");
    if (t == 0) { emit("TERM=<null>\n"); } else { emit("TERM='"); emit(t); emit("'\n"); }
    var h = getenv("HOME");
    if (h == 0) { emit("HOME=<null>\n"); } else { emit("HOME='"); emit(h); emit("'\n"); }
    return 0;
}
```

```
$ script -q /dev/null sh -c "TERM=xterm-256color ./build/envprobe"
TERM=<null>
HOME=<null>
```

Both are set in the process environment. The same binary shape on Linux prints both.

## Why it matters downstream

Found while unblocking thoth's macOS lane. Two user-visible consequences there, and both
are the generic shape rather than anything thoth-specific:

1. **No colour, ever.** thoth's colour capability check requires `getenv("TERM")` to be
   present and not `dumb`. On macOS it is always absent, so the presentation tier degrades
   to plain on a fully capable colour terminal. (`NO_COLOR` is equally inert — it cannot
   be honoured either.)
2. **No `$HOME`-rooted config.** thoth's global config layer lives at
   `~/.thoth/config.cyml` and is found via `getenv("HOME")`, so on macOS the global layer
   can never be discovered. The consumer degrades cleanly (no crash, no global layer) but
   the feature is simply unavailable.

Any consumer reading `HOME`, `TERM`, `PATH`, `NO_COLOR`, `XDG_*` or a service URL from the
environment has the same silent hole.

## Suggested fix

A macOS branch alongside the AGNOS one. Darwin exposes the environment two ways:

* `_NSGetEnviron()` from libSystem — returns `char ***`, the documented Darwin route
  (there is no `environ` symbol to link against directly in a modern dyld image); or
* the same trick the AGNOS peer already uses — `envp` is staged on the exec init stack
  right after `argv`, and `lib/args_*.cyr` already parks the init stack pointer to read
  `argv`. If that parked pointer is available on the Mach-O lane, walking past the
  `argv` NUL terminator reaches `envp` with no dynamic-link dependency at all, which
  matches how `_agnos_getenv` is written.

The second looks cheaper and keeps `getenv` free of a libSystem dependency.

## Notes

* Not a regression — this has been true for as long as the Mach-O lane has existed. It was
  invisible because no consumer reached a macOS build: thoth's macOS lane had not compiled
  since its 0.6.4 (an unrelated thoth-side TTY-guard defect, fixed in thoth 0.44.3), which
  is what surfaced it.
* `getenv` returning 0 is indistinguishable from "the variable is genuinely unset", so no
  consumer can detect this and degrade honestly. That is what makes it worth fixing rather
  than documenting: a wrong answer, not an absent capability.
