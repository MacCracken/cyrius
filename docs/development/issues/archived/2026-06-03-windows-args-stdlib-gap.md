# cyrius `CYRIUS_TARGET_WIN` stdlib gap — `lib/args.cyr` (last rung for ai-hwaccel's win_amd64 wheel)

> **Status**: OPEN — slotted SEPARATELY (user 2026-06-03, "keep .53 = thread+cap, slot args
> separately"). Position in the slate TBD (user's call; parallels the agnos args gap). Surfaced by
> the v6.0.53 ai-hwaccel cross-build (the threading wall cleared; args is the next + last rung).
> **Prereqs in place**: .51 process (CreateProcessW), .52 PROT_READ + `cyrius build --win`, .53
> Windows threading (thread_win.cyr) + the #derive cap raise. With those, ai-hwaccel's *entire*
> Windows closure resolves EXCEPT args.

## Symptom

`cyrius build --win src/main.cyr` of ai-hwaccel now compiles to a PE32+ (rc=0), but emits:
```
warning: undefined function 'args_init'
warning: undefined function 'argc'
warning: undefined function 'argv'
```
A full-closure survey (DCE on and off) confirms these THREE are the **only** remaining undefined
symbols — nothing else. ai-hwaccel is a CLI tool (parses `--version`, `--cost`, …), so `args_init`/
`argc`/`argv` are reached at startup → the win_amd64 binary would `#UD` parsing its flags (cycc emits
its `ud2` unresolved-call sentinel for the undefined fns).

## Root cause

`lib/args.cyr` has only `CYRIUS_TARGET_LINUX` (reads `/proc/self/cmdline`) and `CYRIUS_TARGET_MACOS`
branches — no `CYRIUS_TARGET_WIN`. Same shape as the agnos args gap
(2026-06-03-cyrius-agnos-stdlib-args-io-gap.md), but the Windows mechanism differs: Windows has no
`/proc`, and cycc's PE entry doesn't hand main an argc/argv vector.

## Fix (cyrius-side)

Add a `#ifdef CYRIUS_TARGET_WIN` branch to `lib/args.cyr` implementing `args_init`/`argc`/`argv` from
the Windows command line:
- `GetCommandLineW` (kernel32) → the full UTF-16LE command line (a new 0xF00N-style reroute in
  src/backend/x86/emit.cyr, mirroring the .51 CreateProcessW pattern — a 0-arg call returning the
  cmdline pointer in rax).
- Parse the UTF-16LE command line into an argv vector (split on spaces, honor `"`-quoting — the
  inverse of process_win.cyr's cmdline builder), down-converting each wide arg to a cstr for the
  args.cyr `argc`/`argv` interface.
- `args_init` caches the parsed vector; `argc`/`argv(n)` read it (mirroring the macOS/Linux shape).

(Alternative: `CommandLineToArgvW` does the split, but it lives in shell32 — a new import library;
GetCommandLineW + a hand-rolled splitter keeps it kernel32-only.)

## Validation

`cyrius build --win src/main.cyr` of ai-hwaccel → 0 undefined-fn warnings; run on cass: it parses its
argv and reaches detection (the .51 exec_capture spawn path) instead of `#UD`. This is the **last
rung** — ai-hwaccel's win_amd64 wheel is then fully buildable + runnable, and the owner pins
ai-hwaccel to the releasing tag (the wheel stays gated until then). Add/extend a Windows gate to
cross-build an argv-using program and assert it doesn't emit the args `ud2` (a real closure, not a
toy probe).
