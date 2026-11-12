# `mod NAME;` in an included file stays in force to the end of the compilation unit, so it mangles the includer's own functions — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-11. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-11, by ushma's Rust → Cyrius port (M0 probe 6, `ushma/docs/development/port-parity.md` §3).
**Reporter:** ushma 2.0.0 port (`ushma/docs/development/ushma-port-plan.md` §8; ushma ADR 0001 amendment)
**Severity:** **Medium.** `mod` is the language's namespacing, and it can't namespace a library. A library that tries
breaks every program that includes it. With one global namespace, the libraries fall back on written prefixes.
**Affects:** cyrius 6.7.17 (when `mod` / `use mod.NAME;` landed) through 6.7.18.

## Summary

A distlib bundle that starts with `mod us;` was meant to publish `us_f` for each of its functions, so that a consumer
writes `use us.f;` and calls `f()`. Instead:
- **The scope never ends.** `mod us;` runs to the end of the compilation unit, past the included file, so the
  consumer's own `main` becomes `us_main`. The program's top-level `var r = main();` is then an undefined function,
  and the build is refused. No form ends the scope: a second `mod` re-scopes, and there is no `mod;`.
- **Globals aren't mangled.** `var GLOBALV` stays `GLOBALV` (`us_GLOBALV` is undefined), so a module can't namespace
  its state.
- **The module can't call itself by its short name.** A bare call from one of its functions to another doesn't
  resolve without its own `use`.

The compiler's tests only use `mod` at the end of a single file, which is why this doesn't show there.

## Reproduction

`repros/2026-11-11-mod-scope-runs-past-the-included-file.sh` builds `src/main.cyr`, which includes `src/lib_us.cyr`
(`mod us;` and one fn), writes `use us.helper;` and defines `main`:

```
warning: undefined function 'main'
warning: undefined function 'main' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

It exits 1.

## Root cause (speculation)

The `mod` prefix is preprocessor or parser state set by `mod NAME;` and never restored at the end of the included
file, so it applies to every declaration after it.

## Proposed fix

Scope `mod NAME;` to the file that declares it: restore the previous prefix when that file's include ends. Mangle the
module's globals, consts and enum members with its functions, and resolve a bare name inside the module to the
module's own symbol before the global one. Then `mod` can namespace a bundle, and the collisions in
`2026-11-11-duplicate-fn-across-bundles-last-wins.md` have a language fix.

## Consumer-side workaround

A written prefix. ushma names every public symbol `us_*` / `US_*` (ADR 0001 amendment); kimiya, prakash and impetus
use their own.
