# `getenv` reads only the first 8 KB of `/proc/self/environ` — variables past it are silently invisible

**Status:** ✅ **RESOLVED v6.5.36** — `getenv` now reads `/proc/self/environ` to EOF into a HEAP buffer and caches it for the process. ⭐ The cache is not just an optimisation: the old code re-read and re-scanned on every call, leaking a copy each time on the no-free bump allocator. ⚠ The heap buffer also retires the agnos hazard the old comment described (a function-local `var[]` reserves stack at the prologue even in a statically-dead region). Verified: a marker after a 40 KB variable is NOT found before and IS found after, with genuinely-unset still reporting unset.
indistinguishably from "unset", so no consumer can detect or work around it.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-08-22 during the owl 1.4.6 security audit, investigating why `NO_COLOR=1`
was being ignored.
**Severity:** Medium
**Affects:** cycc — present in `lib/io.cyr` at 6.5.35; introduced whenever the `/proc/self/environ`
reader landed (the 8 KB buffer is called out in the comment referencing `CHANGELOG [6.1.12]`)

## Summary

`getenv` reads `/proc/self/environ` into a fixed 8 KB stack buffer with a single `file_read` and
scans only what fits:

```
    # lib/io.cyr:778
    var buf[8192];
    var fd = file_open("/proc/self/environ", 0, 0);
    if (fd < 0) { return 0; }
    var n = file_read(fd, &buf, 8192);
```

Any variable whose entry begins past byte 8192 is invisible. There is no loop, no truncation
signal, and no way for a caller to distinguish "unset" from "beyond the window" — both return 0.

An 8 KB environment is ordinary: one large `LS_COLORS`, a CI runner's injected secrets, a long
`PATH`, or a single big application variable is enough to push everything after it out of reach.

## Reproduction

Standalone — no downstream repo. `cyrius.cyml` with
`stdlib = ["syscalls", "alloc", "io", "str", "string", "vec", "fmt", "fs"]`, entry `main.cyr`.

```
# main.cyr
fn main() {
    var v = getenv("ZZ_MARKER");
    if (v == 0) { print("ZZ_MARKER: NOT FOUND\n", 21); return 1; }
    print("ZZ_MARKER: ", 11); print(v, strlen(v)); print("\n", 1);
    return 0;
}
```

```
$ env -i PATH=/usr/bin ZZ_MARKER=hello ./genvtest; echo "exit=$?"
ZZ_MARKER: hello
exit=0

$ env -i PATH=/usr/bin PAD="$(python3 -c 'print("x"*10000)')" ZZ_MARKER=hello ./genvtest; echo "exit=$?"
ZZ_MARKER: NOT FOUND
exit=1
```

Same variable, same value, same process — present or absent depending only on how many bytes
precede it.

## Impact seen downstream (owl)

owl reads `NO_COLOR`, `OWL_PAGER`, `PAGER`, `HOME`, `XDG_CONFIG_HOME` and `OWL_CONFIG` through
`getenv`. Measured on owl 1.4.6 under a PTY:

| environment | `NO_COLOR=1` set? | ESC bytes owl wrote |
|---|---|---|
| small | yes | **0** — honoured |
| one variable of 20,000 bytes | yes | **18** — silently ignored |

`NO_COLOR` has a published cross-tool convention (no-color.org) that consumers are expected to
honour unconditionally, so "ignored it because the environment was large" is not a defensible
behaviour for any Cyrius program that implements it. A missed `HOME` / `XDG_CONFIG_HOME` also
means user config and themes silently do not load.

For the record, and so this is not over-read: owl's escape-stripping *safety* property does not
depend on `getenv` — it keys off TTY detection — so a truncated environment can only fail to
*enable* `NO_COLOR`, never to disable stripping.

## Root cause

`lib/io.cyr:778` — fixed `var buf[8192]` plus a single `file_read` capped at the same size. The
surrounding comment explains why the buffer is deliberately kept out of the AGNOS frame (agnos
hands ring-3 only ~12 KB of init stack, so an 8 KB phantom frame overflows it); that constraint
motivates the buffer's *placement*, but not its fixed size on the non-AGNOS path.

## Proposed fix

In rough order of preference:

1. **Read to EOF into a heap buffer.** `/proc/self/environ` is not stat-sizeable, but it can be
   read in a loop into a growing `alloc`. This also sidesteps the AGNOS stack constraint the
   current comment describes, since a heap buffer reserves no frame.
2. **Parse once and cache.** Build the environment into a map on first call. Turns N lookups from
   N full file reads into one — `getenv` currently re-reads and re-scans `/proc/self/environ` on
   *every* call, which is a second, separate cost.
3. **At minimum, signal truncation.** If the read exactly fills the buffer, the environment is
   probably longer; a distinguishable return (or a `getenv_ok`-style companion) would at least let
   a caller know it cannot trust a negative answer.

## Consumer-side workaround (if any)

None good. A consumer can reimplement `getenv` locally against `/proc/self/environ` with its own
buffer — owl already reads that file directly in `src/pager.cyr` for env forwarding, so the code
exists — but doing so diverges from every other Cyrius consumer and leaves the same bug in place
for all of them. owl deliberately did **not** ship such a shim, which is why this is filed here.
