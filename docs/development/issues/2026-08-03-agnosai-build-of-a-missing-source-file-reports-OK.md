# `cyrius build` on a source file that does not exist reports OK and emits a do-nothing binary

**Status:** 🟡 **OPEN** — filed 2026-08-03.
**Placement:** unpinned — 6.x-line backlog. Small fix.
**Severity:** Low — ergonomic, but it costs real debugging time because the failure looks like a *runtime* bug in the program.
**Discovered:** 2026-08-03, verifying a kavach security fix from agnosai.
**Affects:** cycc 6.5.6 (behaviour looks long-standing).

## Summary

`cyrius build <path-that-does-not-exist>.cyr <out>` **succeeds**: it prints
`OK`, exits **0**, and writes a ~15 MB executable that does nothing and exits 0.
No warning names the missing file.

The stdlib is auto-prepended before the entry file is read, so the compiler ends
up with a valid translation unit containing the entire stdlib and no `main` — a
program that is legitimately compilable and legitimately does nothing. Nothing
downstream notices that the one file the user actually asked for was never
opened.

## Why this is worth fixing despite being "just" a papercut

The failure presents as a **runtime** problem, not a build problem. What it
looked like in practice: a probe program that had printed five lines a moment
earlier suddenly printed nothing, exited 0, and left correct side effects on
disk. That reads as "the library I just changed broke `println`", and the next
twenty minutes go into the library. The actual cause was a stale path — the
source had been removed and the build silently kept succeeding against nothing.

A single "no such file" would have ended it immediately.

## Reproduction

```sh
cd <any-project-root>
cyrius build /tmp/definitely-not-here-12345.cyr build/ghost ; echo "exit=$?"
ls -l build/ghost
./build/ghost ; echo "ran, exit=$?"
```

Verified on cycc 6.5.6, x86-64 Linux, 2026-08-03:

```
warning: large static data (13418736 bytes) — consider alloc() for buffers >4KB
OK
exit=0
-rwxr-xr-x 1 macro macro 15563640 … build/ghost
ran, exit=0
```

The only hint anything is wrong is the `large static data` warning — which is
present on ordinary healthy builds of this project too, so it is not a signal.

## Proposed fix

`stat`/open the entry path before doing any work and fail with the usual
`error:` shape:

```
error: no such file: /tmp/definitely-not-here-12345.cyr
```

Worth checking the same path for `cyrius test`, `cyrius check`, `cyrius fmt`,
`cyrius lint` and `cyrius doc` — the last three take a FILE and are already
known to behave surprisingly when given something unexpected (bare invocation
prints usage and exits 1).

A second, independent guard worth considering: **warn when the final translation
unit defines no `main`**. That catches this case and the adjacent one where a
typo'd path resolves to a real-but-wrong file, and it is meaningful for a
`[build] entry` program regardless of how the input went missing.

## Consumer-side workaround

None needed beyond the obvious — check the path. Recorded because the *symptom*
is so misleading: if a program that worked a minute ago goes silent and exits 0
after a dependency change, verify the source file still exists before
suspecting the dependency.
