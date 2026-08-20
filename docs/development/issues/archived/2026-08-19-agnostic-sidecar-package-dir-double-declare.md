# A package-DIRECTORY stdlib leaf declared in BOTH `[deps].stdlib` and a dep's `.deps` sidecar emits an unexpanded `lib/<name>.cyr` include — build fails

**Status:** ✅ **RESOLVED** — shipped in **v6.5.31**. See `CHANGELOG.md` [6.5.31].

> Reproduced verbatim (Variant C: `cannot open include file: lib/unicode.cyr` with
> `lib/unicode/` fully populated) and fixed at the seen-guard: a top-level request for an
> ALREADY-SEEN module now pushes a flat `include "lib/<mod>.cyr"` only when that file actually
> exists, guarded by the same `file_exists` test the directory-family expansion itself keys on
> so the two cannot disagree about what a family is. The family members were already pushed by
> whichever route arrived first, so the correct action on the second route is to push nothing.
>
> ⚠ **Bisected: introduced at v6.5.28, not v6.2.47** as the filing reasonably assumed. That
> push did not exist before — it was added by the v6.5.28 "transitive stdlib pull drops the
> consumer's own top-level include" fix, which was written for flat leaves and never
> considered the one package-directory module. Either declaration alone worked precisely
> because only the combination reaches the seen path.
>
> Both halves are now pinned in ONE gate, deliberately: axes 1-2 require the seen path to
> push (the .28 fix), axis 4 requires it not to push a family name (this fix). They share a
> code path and must be read together. Axis 3 was also rewritten — it grepped for a literal
> one-liner and went RED against correct code when the guard grew multi-line, so it now checks
> the is_top invariant scoped to the enclosing function rather than the formatting.
**Placement:** unpinned — 6.5.x backlog. `cbt/deps.cyr` (sidecar consumption vs. directory-family expansion).
**Discovered:** 2026-08-19 while wiring **agnostic 2.0.1** (Python → Cyrius port) to consume **agnosai 2.0.2**'s new `dist/agnosai.cyr` bundle.
**Severity:** Medium — hard build failure, known workaround, and the error names a file that legitimately does not exist so the reader is sent looking for a missing stdlib module rather than a double-declaration.
**Affects:** cycc / cbt 6.5.29 (not bisected further back; the sidecar consumer path is v6.2.47, the directory-family expansion is v6.1.x, so the interaction is likely present since v6.2.47).

## Summary

`unicode` is the only stdlib module that is a **package directory** (`lib/unicode/*.cyr`) rather than
a single `lib/unicode.cyr`. `cbt/deps.cyr:571-577` handles this: when `<stdlib_dir>/<name>.cyr` is
absent but `<stdlib_dir>/<name>/` is a directory, it resolves every `.cyr` inside instead.

That expansion is reached when `unicode` comes in via `[deps].stdlib`, and it is reached when
`unicode` comes in via a dependency's `dist/<pkg>.deps` sidecar. It is **not** reached when it comes
in via **both** — the build then emits a flat `include "lib/unicode.cyr"` for a file that does not
exist, and fails:

```
compile src/main.cyr -> build/uni3 [x86_64] error: cannot open include file: lib/unicode.cyr
FAIL
```

`./lib/unicode/` is present and correctly populated at this point — the *copy* half succeeded. Only
the emitted include is wrong.

This is not a synthetic combination. A consumer naturally declares the stdlib it uses directly, and
its dependency independently declares the same leaf in its own manifest, which `cyrius distlib`
faithfully records in the sidecar. Any consumer of a bundle whose sidecar lists `unicode` hits this
the moment it also uses `unicode` itself.

## Reproduction

Three variants, identical except for where `unicode` is declared. Run each with a clean tree.

### Shared: a 2-line synthetic dep with a sidecar that lists `unicode`

```sh
mkdir -p /tmp/fakedep/dist
printf 'fn fakedep_ping(): i64 { return 7; }\n'  > /tmp/fakedep/dist/fakedep.cyr
printf '# sidecar\nstr\nunicode\n'               > /tmp/fakedep/dist/fakedep.deps
```

### Shared: the consumer entry

```sh
mkdir -p /tmp/uni/src
printf 'fn main(): i64 { return fakedep_ping() * 6; }\nvar f = main();\nsyscall(60, f);\n' \
  > /tmp/uni/src/main.cyr
```

### Variant A — `unicode` in `[deps].stdlib` only, no dep → **OK**

```toml
[deps]
stdlib = ["syscalls", "alloc", "str", "string", "vec", "unicode"]
```
```
compile src/main.cyr -> build/uni [x86_64] ... OK
```

### Variant B — `unicode` in the dep's sidecar only, absent from `[deps].stdlib` → **OK**

```toml
[deps]
stdlib = ["syscalls", "alloc", "str", "string", "vec"]

[deps.fakedep]
git = "https://example.com/fakedep.git"
path = "/tmp/fakedep"
tag = "0.0.1"
modules = ["dist/fakedep.cyr"]
```
```
compile src/main.cyr -> build/uni4 [x86_64] ... OK
```

### Variant C — `unicode` in **both** → **FAIL**

```toml
[deps]
stdlib = ["syscalls", "alloc", "str", "string", "vec", "unicode"]

[deps.fakedep]
git = "https://example.com/fakedep.git"
path = "/tmp/fakedep"
tag = "0.0.1"
modules = ["dist/fakedep.cyr"]
```
```
1 deps resolved
cyrius.lock: 109 deps locked
compile src/main.cyr -> build/uni3 [x86_64] error: cannot open include file: lib/unicode.cyr
FAIL
```

Run `cyrius lib sync --full` before each build. `ls lib/unicode/` shows all seven family files
present in the failing case, so this is purely the emitted include, not a provisioning failure.

### Real-world instance

`agnosai` 2.0.2 declares `unicode` in `[deps].stdlib` (it calls `unicode_category`), so
`cyrius distlib` writes `unicode` into `dist/agnosai.deps`. A consumer that declares
`[deps.agnosai]` *and* `unicode` — the natural manifest, since it is copied from agnosai's own —
fails identically. Dropping the one line from the consumer's `[deps].stdlib` builds and runs.

## Root cause — speculation, flagged as such

The copy half is fine: `_dep_pull_leaves` (`cbt/deps.cyr:820`) calls
`_dep_copy_stdlib_recursive(stdlib_dir, leaf, 1)`, and the directory-family expansion at
`cbt/deps.cyr:571-577` lives inside that function, which is why `./lib/unicode/` ends up populated in
all three variants.

The suspect is the `_dep_stdlib_seen` dedup that the sidecar path and the `[deps].stdlib` path share.
The comment at `cbt/deps.cyr:1742-1743` states the intent:

> Shared resolver + `_dep_stdlib_seen` dedup (a leaf also in `[deps].stdlib`/`requires` won't repeat).

With stdlib-before-deps ordering (the v5.5.26 flip noted in `cbt/build.cyr`), the plausible sequence
is that one path marks `unicode` seen and the other then takes an early-return that pushes the
canonical `lib/<leaf>.cyr` include without re-testing the directory case — so the flat include is
emitted exactly once, by the path that skipped the expansion. **This is inference from the
A/B/C evidence table above, not from reading the emitted include list** — `cbt` has no keep-temp or
dump-includes flag, so the preprocessed unit could not be inspected directly. The three-variant
result is solid; the mechanism is not.

## Proposed fix

Whichever path emits the include for an already-seen leaf should apply the same
`file_exists(<stdlib_dir>/<name>.cyr) == 0 && is_dir(<stdlib_dir>/<name>/)` test that
`cbt/deps.cyr:571-577` applies, and expand to the family rather than emitting the bare stem. Equally
valid: make the dedup record *what was emitted* (family vs. single file) rather than just the leaf
name, so the second path can tell a satisfied family from an unsatisfied one.

A gate for this is cheap and would have caught it: a project declaring a package-directory leaf in
both places at once. `unicode` is currently the only such module, so the axis is one fixture wide.

## Consumer-side workaround

**Do not declare a package-directory leaf in `[deps].stdlib` when a declared dependency's sidecar
already lists it.** For agnostic 2.0.1 consuming agnosai 2.0.2 that is one line removed from
`[deps].stdlib`; `dist/agnosai.deps` supplies `unicode`, `cyrius deps` provisions `lib/unicode/`, and
the build then completes and runs (verified: consumer binary links `agnosai_percentile_i64`,
`agnosai_uuid_v4`/`_version` and `agnosai_orchestrator_new`/`_crew_count`, exits 42).

The workaround is fragile in one direction worth noting: it makes the consumer's manifest depend on a
transitive detail. If agnosai ever stopped needing `unicode`, the consumer's own usage would break
with a different error, and the fix would be to add back the line this issue says to remove.
