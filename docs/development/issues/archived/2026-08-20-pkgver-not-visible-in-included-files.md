# `CYRIUS_PKG_VERSION` resolves only in the entry file, not in `include`d files

**Status:** ✅ **RESOLVED — FIXED at v6.5.34.** See `CHANGELOG.md` [6.5.34].

> **THE BLOCKER WAS A FALSE PREMISE IN THIS FILE, not the plumbing.** The note below says
> "Globals declared below their use ARE visible (verified separately)". **They are not.**
> Measured on the 6.5.33 binary:
>
> ```
> $ printf 'fn f(): i64 { return XYZ; }\nvar _r = f();\nsyscall(60, _r);\nvar XYZ = 7;\n' | cycc
> error:<source>:1:25: undefined variable 'XYZ' (missing include or enum?)
> ```
>
> So append-after-expansion could never work, and the "find which pass owns the final buffer"
> next step was chasing the wrong thing — the appended bytes DO reach the lexer (instrumented:
> `PP_PASS` op 121 → 156, `PP_IFDEF_PASS` preserves 156). The parser simply cannot see a global
> declared below its use. Two attempts were spent on that path.
>
> **THE FIX.** The declaration stays at the TOP, where it must be, emitted optimistically by
> `PP_EMIT_PKGVER`, which now also records its span. At the tail of `PP_PASS` — the first point
> at which every top-level `include` has been expanded — the finished unit is scanned, and if
> nothing names the constant the declaration is **blanked to spaces**. Identical byte count, so
> no line and no column moves, and whitespace emits no code: the binary of a program that never
> asked for the feature is unchanged, which is what `auto_deps_verb_gate.sh` axis 5 measures
> (verified green).
>
> ⚠ **The tail scan must skip the declaration's OWN bytes.** It contains the `CYRIUS_PKG_`
> prefix it searches for, so a whole-buffer scan matches itself, keeps the global on every
> build, and silently restores the unconditional behaviour while still appearing to be tested.
>
> Gate: `tests/gates/frontend/pkgver_visible_in_includes.sh` — four axes (include-file
> reference, entry-file regression guard, byte-neutrality, line-neutrality), mutation-proven
> against a faithful reconstruction of the v6.5.21 behaviour, which turns axis 1 red while
> leaving axis 2 green: the filed bug's exact signature.

> **Mechanism (confirmed).** `PP_EMIT_PKGVER` (`src/frontend/lex_pp.cyr`) decides whether to
> declare the constant by scanning for the literal `CYRIUS_PKG_` **in the marker's own
> buffer** — which at that moment is the ENTRY FILE's text, because includes have not been
> expanded yet. So the declaration is emitted when the entry file names the symbol and silently
> omitted when only an included file does. That is exactly the filed symptom, and the reverse
> of what the marker's position suggests.
>
> The conditional scan is not incidental: declaring unconditionally puts an unused global plus
> its string data into every binary built through `cyrius build`, which changes the bytes of
> programs that never asked for the feature — `auto_deps_verb_gate.sh` axis 5 catches that and
> is right to. So the fix must keep "declare only if referenced" while widening what "referenced"
> is scanned over.
>
> **Attempted at .33 and reverted**: record the version at the marker, then append
> `var CYRIUS_PKG_VERSION = "…";` at the end of `PP_PASS` once includes are expanded. Globals
> declared below their use ARE visible (verified separately), so the shape is sound — but the
> appended bytes **never reached the parser**, proven with an unconditional probe global that
> also failed to resolve. Something downstream of `PP_PASS` re-derives or discards the buffer
> tail; `PREPROCESS` runs `PP_PASS` → `PP_IFDEF_PASS` → `PP_MACRO_PASS` and the interaction was
> not pinned down before the attempt was backed out. Reverted rather than shipped half-working:
> `cycc` is byte-identical to the shipped 6.5.32 on the pkgver path.
>
> **Next step for whoever picks this up:** find which pass owns the final buffer and append
> there, or thread a "referenced" flag out of the expansion so the marker site can decide with
> full knowledge. Do NOT drop the conditional — axis 5 of the auto-deps gate depends on it.
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
