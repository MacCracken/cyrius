# `distlib`'s bundle self-check rejects any bundle that reads a stdlib global — OPEN

**Status:** 🔴 **OPEN** — `cyrius distlib` exits 1 on a correct bundle from 6.5.14 onward; 44 of 69 `[lib]` repos on this machine are affected, 2 of them today.
**Placement:** unpinned — 6.5.x line. Blocks CI/release for any consumer whose bundle uses a stdlib constant, so it wants a patch release rather than the backlog.
**Discovered:** 2026-08-09 during hisab's 6.5.9 → 6.5.16 toolchain bump (hisab v2.9.2)
**Severity:** **High** — hard failure of a shipping consumer's CI and release gates, with no in-tool workaround. Not a correctness risk: the bundle written is correct.
**Affects:** cycc / cbt **6.5.14 → 6.5.16** (introduced by 6.5.14's "distlib's bundle self-check had never once run"; 6.5.9 and 6.5.13 are clean)

## Summary

6.5.14 repaired the `distlib` bundle self-check, which had never executed — it compiled to
`/dev/null`, whose `<out>.tmp.<pid>` sibling cannot be created, so it failed on the write and the
handler printed a reassuring note. Good fix. But the repaired check compiles the bundle **alone**,
with no stdlib in scope, under `_cc_allow_undef = 1`, and its comment states the premise:

> Undefined fns are the ONE expected failure (a bundle ships no stdlib), so
> downgrade exactly that and let everything else stay fatal.

A bundle ships no stdlib **globals** either. Any bundle that reads a stdlib `var` or enum constant
is therefore reported as a defective bundle and `distlib` exits 1.

For hisab this is `F64_ONE` — the ordinary way to write the literal `1.0` in a language with no
float literals:

```
error:hisab.cyr:111:42: undefined variable 'F64_ONE' (missing include or enum?)
error: distlib: the generated bundle does not compile: dist/hisab.cyr
      (undefined fns are already downgraded — this is a REAL defect
       in the bundle, not the consumer's missing stdlib).
```

`dist/hisab.cyr:111` is `fn hvec2_one() { return hvec2_new(F64_ONE, F64_ONE); }`. `F64_ONE` is
`lib/math.cyr:15` and reaches a consumer via `[deps] stdlib`. The parenthetical is exactly backwards
for this case: it **is** the missing stdlib, and the bundle has no defect — `cyrius check --with-deps
dist/hisab.cyr` reports `ok`.

## Reproduction

Three projects identical but for the single expression in the `[lib]` module.

```
# cyrius.cyml (all three)
[package]
name = "r2"
version = "0.0.1"
language = "cyrius"
cyrius = "6.5.16"
[build]
src = "src/a.cyr"
output = "build/r2"
[lib]
modules = ["src/a.cyr"]
[deps]
stdlib = ["syscalls", "string", "math"]
```

```
# src/a.cyr — one of:
fn c_fn(s)   { return strlen(s); }    # stdlib FUNCTION
fn c_var()   { return F64_ONE; }      # stdlib GLOBAL VAR
fn c_enum()  { return STDOUT_FD; }    # stdlib ENUM CONSTANT
```

Measured on 6.5.16 (`cyrius distlib`, exit code read without shell redirection):

| `[lib]` module body | result |
|---|---|
| `strlen(s)` — stdlib **function** | **exit 0** — `warning: undefined function 'strlen'` |
| `F64_ONE` — stdlib **global var** | **exit 1** — `undefined variable 'F64_ONE'` |
| `STDOUT_FD` — stdlib **enum constant** | **exit 1** — `undefined variable 'STDOUT_FD'` |

Bisected across installed toolchains on a byte-identical scratch copy of hisab (the generated
bundle `diff -q`s identical to the shipped `dist/hisab.cyr`): **6.5.9 rc=0, 6.5.13 rc=0,
6.5.14 rc=1, 6.5.16 rc=1**.

## Root cause

`_cc_allow_undef` becomes a single `--allow-undef` argv token (`cbt/build.cyr:659-661`). Inside
cycc, `_allow_undef` is read in exactly two places — `src/backend/x86/fixup.cyr:725` and
`src/backend/aarch64/fixup.cyr:559` — each gating a `undef_count` whose message reads
`reachable undefined function(s) (pass --allow-undef to downgrade)`. That is the **fixup stage**, at
the end of the backend.

An unresolved *name* dies in the **frontend**, long before any backend runs
(`src/frontend/parse_expr.cyr:585-593`):

```
var idx = FINDVAR(S, noff);
if (idx < 0) {
    ... ": undefined variable '" ... "' (missing include or enum?)\n"
    syscall(SYS_EXIT, 1);
}
```

An immediate process exit. **There is no path by which `--allow-undef` could affect it.** So this is
not "globals were forgotten" — the self-check's premise (*one flag suppresses the one expected
failure*) is unreachable for every name-resolved symbol kind. Function *calls* are the only thing
that survives, because only they are deferred to fixup. Sibling exits at
`parse_decl.cyr:324`, `parse_decl.cyr:462` and `parse_expr.cyr:699` are the same shape.

The self-check itself is `cbt/commands.cyr:3080-3145`; the flag is set at `:3131`.

## Blast radius

Sandbox-tested across every repo on this machine carrying a `[lib]` block (manifest + `[lib]`
modules copied to scratch, pin rewritten to 6.5.16, `cyrius distlib` run; nothing written back):

- **69** repos declare a `[lib]` bundle; **44** exit 1 once pinned to 6.5.16, **42** of those naming
  an `undefined variable`.
- **3** are pinned ≥ 6.5.14 today, so only they are broken now: **hisab** (6.5.16, `F64_ONE`),
  **majra** (6.5.14, `CLOCK_MONOTONIC`), and **sigil** (6.5.14, passes — its bundle happens to
  reference no consumer-supplied global, which is very likely why 6.5.14 shipped without this
  surfacing).
- The remaining ~41 are latent and fire on their next toolchain bump.

## Proposed fix

**Preferred: compile the self-check bundle with the project's own `[deps]` stdlib in scope** — give
the generated entry the same treatment `cyrius check --with-deps` gets. That verifies the bundle in
the scope a consumer actually builds it in, needs no suppression flag at all, and is immune to the
whole class rather than to one symbol kind. The manifest is already parsed at that point and
`distlib` has just written the `.deps` sidecar naming exactly those leaves.

The alternative — extending suppression to names — is a poor second: it means gating the frontend's
`FINDVAR` failure path *and* every other name-resolution exit, and it would still be verifying the
bundle in a scope no consumer ever uses.

Minor: the two `_info` lines asserting *"this is a REAL defect in the bundle, not the consumer's
missing stdlib"* should not print unconditionally, since the one case they exclude is the case that
fires here.

## Consumer-side workaround (hisab v2.9.2)

`distlib` is **write-then-verify** — the bundle is written at `cbt/commands.cyr:2801`, ~330 lines
before the check, and the failure path at `:3141-3145` does not unlink it. So regeneration works and
only the exit code is wrong. Proven: bumping `VERSION` 2.9.1 → 2.9.2 and running `cyrius distlib`
exits 1 *and* leaves the bundle correctly regenerated, `git diff` showing exactly the one-line
header change. `cyrius distlib --check` (the non-writing drift path) returns at `:3078`, before the
check, and is unaffected.

hisab's `ci.yml` and `release.yml` now capture `distlib`'s output and tolerate a non-zero rc **only**
when it carries this exact signature (`does not compile` *and* `undefined variable`), failing on any
other distlib failure — plus a separate `cyrius check --with-deps dist/hisab.cyr` step, which is
strictly stronger than the self-check it replaces. Filed consumer-side at
`hisab/docs/development/issues/2026-08-09-cyrius-distlib-selfcheck-rejects-stdlib-globals.md`.
