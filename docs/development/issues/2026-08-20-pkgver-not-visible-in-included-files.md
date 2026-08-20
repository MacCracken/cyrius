# `CYRIUS_PKG_VERSION` resolves only in the entry file, not in `include`d files

**Status:** 🟡 **OPEN**
**Placement:** unpinned — 6.5.x backlog. `cbt/build.cyr:402-413` (marker emission) + the cycc side that replaces it.
**Discovered:** 2026-08-20 in **agnostic**, wiring a `/ready` endpoint that reports its own version.
**Severity:** Low — a one-line workaround exists. The cost is that the feature does not work where it is most useful.
**Affects:** cyrius 6.5.32 (feature added 6.5.21).

## Summary

`cbt` writes `#@pkgver <version>` at byte 0 and cycc replaces it with a `CYRIUS_PKG_VERSION`
declaration, surfacing `[package].version` to source. It works — but **only in the entry file's own
text**. Any `include`d file referencing the symbol fails to compile:

```
error:src/routes/health.cyr:120:73: undefined variable 'CYRIUS_PKG_VERSION' (missing include or enum?)
```

That is the opposite of what the placement suggests. The marker is emitted *before* the dep includes
(`cbt/build.cyr:402-413`), so a reader would reasonably expect the declaration to precede — and
therefore be visible to — everything in the translation unit.

## Reproduction

Verified at cyrius 6.5.32 in a project whose `cyrius.cyml` has `version = "${file:VERSION}"` and a
`VERSION` of `0.1.0`.

**Works** — reference from the entry file:

```cyrius
# src/main.cyr
fn main(): i64 { alloc_init(); println(CYRIUS_PKG_VERSION); return 0; }
var _v = main();
sys_exit_group(_v);
```
```
$ cyrius build src/main.cyr build/x
OK
$ build/x
0.1.0
```

**Fails** — same symbol, one `include` away:

```cyrius
# src/probe.cyr
fn _probe_ver(): i64 { return CYRIUS_PKG_VERSION; }

# src/main.cyr
include "src/probe.cyr"
fn main(): i64 { alloc_init(); return 0; }
var _v = main();
sys_exit_group(_v);
```
```
$ cyrius build src/main.cyr build/x
error:src/probe.cyr:1:31: undefined variable 'CYRIUS_PKG_VERSION' (missing include or enum?)
```

Confirmed from two different included files at two different include depths
(`src/http/status.cyr`, included directly; `src/routes/health.cyr`, included later), so it is not
depth- or order-specific — it is entry-file-only.

## Why this matters more than the severity suggests

The natural consumer of a package version is a `/version` or `/ready` endpoint, an `--version` flag,
or a User-Agent header. In any project big enough to have those, they live in a **module**, not in
`main.cyr` — the entry file is conventionally thin. So the symbol is unavailable in precisely the
files that want it, and available in the one file that usually does not.

The failure is at least loud: a compile error naming the symbol, not a silent 0. Credit where due —
a silently-0 version string would be considerably worse.

## Consumer-side workaround

Read it in the entry file and hand it to the module at startup:

```cyrius
# src/main.cyr — the only file where the symbol resolves
agnostic_version_set(str_from(CYRIUS_PKG_VERSION));
```

```cyrius
# src/routes/health.cyr
var _agnostic_version = 0;
fn agnostic_version_set(v: Str): i64 { _agnostic_version = v; return 0; }
fn agnostic_version(): i64 {
    if (_agnostic_version == 0) { return str_from("unknown"); }
    return _agnostic_version;
}
```

This keeps the version *derived* from `${file:VERSION}` rather than hand-maintained, which is the
point of the feature — it just costs a setter and a mount-time call per consumer.

## Suggested fix

Either make the replacement visible across the whole translation unit — which is what the byte-0
placement already implies — or, if that is structurally hard, document the entry-file-only scope
where the feature is described so consumers reach for the setter pattern immediately instead of
discovering it through a compile error.

Filing only; per this consumer's operating rule the cyrius tree is not modified from a consumer repo.

## Related

The same session filed `2026-08-20-cyrius-port-language-python.md` (no `--language=python` port mode;
`cyrius init` emitting fewer files than the standard promises; the scaffold's own unprefixed
top-level global).
