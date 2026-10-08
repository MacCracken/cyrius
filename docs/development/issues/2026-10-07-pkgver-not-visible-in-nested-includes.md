# `CYRIUS_PKG_VERSION` resolves from a file the entry includes, but not from one it includes in turn

**Status:** 🟡 **OPEN**.
**Placement:** unpinned.
**Discovered:** 2026-10-07, by **agnostic** (0.1.15), retiring its work-around for
[`archived/2026-08-20-pkgver-not-visible-in-included-files.md`](archived/2026-08-20-pkgver-not-visible-in-included-files.md)
(fixed at 6.5.34).
**Severity:** Low. A compile error, never a miscompile: the program does not build, and the
diagnostic names the reference.
**Affects:** 6.6.14, 6.6.19, 6.7.2 and 6.7.3 (each measured with the repro below). Every version
since 6.5.34 is presumed to behave the same.

## Summary

6.5.34 made the constant resolve when an `include`d file names it and the entry file does not.
It resolves only one level deep: when the file that names it is included by another included file
— the entry includes `app.cyr`, and `app.cyr` includes `health.cyr`, which names the constant — the
build fails with `undefined variable 'CYRIUS_PKG_VERSION'`.

Naming the constant anywhere in the entry file's direct includes keeps the declaration, even in a
comment; so does naming it in the entry itself. That is how agnostic found it: its `tests/health.tcyr`
compiled because a comment in it mentions the name, and every other suite failed.

## Reproduction

[`repros/2026-10-07-pkgver-not-visible-in-nested-includes.sh`](repros/2026-10-07-pkgver-not-visible-in-nested-includes.sh)
builds three entries in a throwaway project pinned to the installed toolchain:

```
$ sh repros/2026-10-07-pkgver-not-visible-in-nested-includes.sh
a: 1.2.3
b: 1.2.3
c: FAILED — error:src/inc.cyr:1:49: undefined variable 'CYRIUS_PKG_VERSION' (missing include or enum?)
```

- **a** — the entry names the constant.
- **b** — the entry includes `inc.cyr`, which names it (the 6.5.34 case).
- **c** — the entry includes `mid.cyr`, which includes `inc.cyr`.

## Where to look (unverified)

The 6.5.34 fix keeps the declaration at the top and blanks it "at the tail of `PP_PASS` — the first
point at which every top-level `include` has been expanded" if the finished unit never names it.
The reading consistent with the repro: at that point the entry's own includes are expanded but
theirs are not yet, so the scan never sees text two levels down. `tests/gates/frontend/pkgver_visible_in_includes.sh`
covers one level only (`included.cyr` is included by the entry), which is why the gate stays
green.

## What the consumer does meanwhile

agnostic keeps its pre-6.5.34 work-around: `src/main.cyr` (the entry) reads the constant and hands
it to `src/routes/health.cyr` through a setter. Its roadmap records the retirement as blocked on
this.
