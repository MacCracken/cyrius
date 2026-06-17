# 2026-06-17 — `lib/io.cyr` O_* open-flags are Linux values, not translated for Darwin (file writes fail on arm64-macOS)

> **RESOLVED — v6.2.17.** Root-cause correction: the `sakshi_full.tcyr` failure had
> **TWO** Darwin-O_* causes, not just io.cyr (this issue's original attribution was
> incomplete):
> 1. **`lib/io.cyr`** redefined O_CREAT/O_TRUNC/O_APPEND with Linux values *after*
>    including syscalls.cyr (whose per-arch peer already has the correct per-target
>    values), so on Darwin the Linux `64` overrode the right `0x200` (last-def-wins).
>    Fix: io.cyr now defines O_* **only on agnos** (whose peer exposes `AO_*`, not
>    `O_*`, and file_open bridges O_*→AO_*); every other target uses the syscalls
>    peer's correct per-target O_*. Verified on real arm64-macOS: `file_write_all` +
>    `file_read_all` round-trip (the file is created and read back). `tests/tcyr/io.tcyr`
>    now gates it cross-OS.
> 2. **`sakshi/src/output.cyr`** (sakshi's OWN file sink — it can't pull io.cyr,
>    foundation-layer rule) hard-coded the Linux literal `1089`
>    (`O_WRONLY|O_CREAT|O_APPEND`). Fix in **sakshi 2.3.2**: per-target literal —
>    `521` (0x209) on macOS, `1089` elsewhere. `sakshi_full.tcyr` now passes 20/20 on
>    arm64-macOS. (The io.cyr fix alone did NOT make sakshi_full pass — sakshi never
>    used io.cyr's file_open.)
>
> Linux/Windows unaffected (their O_* values are unchanged). See CHANGELOG [6.2.17].

> **Class:** PRE-EXISTING (found 2026-06-17 while cross-OS-verifying the v6.2.16
> sakshi fold on ecb — NOT introduced by it; sakshi 2.3.0 fails identically). Not a
> v6.2.16 regression.

## Symptom

`tests/tcyr/sakshi_full.tcyr` fails its **"log file written"** assertion on
arm64-macOS (`19 passed, 1 failed`) — the log file is never created/written. The
span/clock paths are fine (spans time correctly: `[EXIT] test_op (8708ns)`); the
failure is isolated to **file output**. On x86_64-Linux and aarch64-Linux (pi) the
same test passes 20/20.

## Root cause

`lib/io.cyr` hard-codes the **Linux** `open(2)` flag values:

```
var O_CREAT  = 64;     # Linux 0x40
var O_TRUNC  = 512;    # Linux 0x200
var O_APPEND = 1024;   # Linux 0x400
```

It has an **agnos** bridge (`flags & 64 → AO_CREAT 0x100`, etc.) but **no Darwin
translation**. On macOS the BSD `open` flag values differ:

| flag | Linux | Darwin |
|------|------:|-------:|
| `O_CREAT`  | `0x40` (64)   | `0x200` |
| `O_TRUNC`  | `0x200` (512) | `0x400` |
| `O_APPEND` | `0x400` (1024)| `0x8`   |

So `file_open(path, O_WRONLY|O_CREAT|O_TRUNC, …)` passes Linux bits straight to
Darwin's `open`, which interprets them as different (or no) flags → the file is not
created. The compiler even warns at build time — **`duplicate symbol 'O_CREAT'
redefined with conflicting value`** (O_CREAT/O_TRUNC/O_APPEND) — the v6.2.11
CHKDUPVAL guardrail firing because a second module in the include chain disagrees
on the value; the dup masks which definition wins.

## Fix (proposed, future slot)

Make `lib/io.cyr`'s O_* per-target like the syscall/clock paths already are:
`#ifdef CYRIUS_TARGET_MACOS` → Darwin values (`O_CREAT 0x200`, `O_TRUNC 0x400`,
`O_APPEND 0x8`, `O_WRONLY 0x1`, `O_RDWR 0x2`), else the Linux values; and resolve
the duplicate O_* definition so a single source owns them. (Windows uses the PE
CreateFileW reroute, not POSIX O_*, so it is unaffected.) Then sakshi_full's file
output passes on ecb. Mirrors how `chrono`/`bench`/`net` already branch per target.

## Scope / priority

P2 — arm64-macOS file-writing consumers (sakshi file sinks, any `file_write_all`
to a new path on Darwin) are affected; stdout/stderr logging is fine. Out of scope
for v6.2.16 (the var-syscall-clock fold). Linux + Windows unaffected.
