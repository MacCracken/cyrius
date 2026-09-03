# `cyrius audit` passes a project with lint-dirty tests and a failing `-D` build — two coverage gaps in the aggregate gate

**Status:** ✅ **FIXED at v6.5.42 — CLOSED.** `cyrius audit` now walks `tests/`, `benches/`, `fuzz/` (and `cbt/` in this repo), recursively, and recognises `.tcyr` / `.bcyr` / `.fcyr`. Gate: `tests/gates/toolchain/audit_scope_covers_suite.sh`.

⭐ **THREE INDEPENDENT HALVES, AND ANY ONE MISSING STILL REPORTS A CLEAN VERDICT OVER NOTHING** — which is why a partial fix here would have been worse than none:
1. **Scope** — `tests/` was not in the directory list at all.
2. **Descent** — the walkers listed each directory and nothing beneath it. The suite lives at `tests/tcyr/<bucket>/*.tcyr`, **two levels down**, so adding `tests/` to a flat lister finds a directory containing only directories and audits zero files while the `scope:` banner cheerfully prints "tests".
3. **Extension** — `_aw_is_cyr` matched only `.cyr`. Its tail scan is anchored at `len-4`, so `"foo.tcyr"` ends in `"tcyr"`, not `".cyr"`, and did **not** fall out of the same check.

⚠ **The widened audit immediately surfaced ~86 unformatted files** across the newly-covered trees. They are NOT fixed here: bulk-reformatting 86 files (including test fixtures whose exact formatting some tests may depend on) is a large mechanical diff that would mask real changes, and `cyrius audit` already fails in this repo by design on cycc's deliberately-unformatted `main*.cyr` forks. The fix is that the audit can now SEE them; whether to format them is a separate call with its own diff.
**Placement:** unpinned — 6.5.x-line backlog.
**Discovered:** 2026-08-26 during the svara Rust→Cyrius port (svara 3.4.0 and 3.5.1).
**Severity:** Medium — no hard failure, but the gate returns a **false negative**: it reports `lint clean` on a project that is not lint-clean, and `N passed` on a suite that fails. CI trusts it.
**Affects:** cycc 6.5.35 (both behaviours are long-standing; not regressions).

## Summary

`cyrius audit` is documented and used as *the* pre-merge gate — svara's
`CONTRIBUTING.md` names it, and its CI ran it as the sole quality step. It exits 0
on a project with:

1. **Lint violations in `tests/`** — an over-length line and an untracked
   deferral. The audit banner says `scope: src`, so the fmt / lint / docs legs
   never look at `tests/*.tcyr` or `benches/*.bcyr`. Those files *are* compiled by
   the tests leg, so they are clearly project source; they are simply not linted.

2. **A test that fails under `-D`** — `cyrius test` does not accept or forward
   `-D NAME`, so the tests leg only ever compiles the *no-defines* half of any
   `#ifdef`-gated feature. A project with a conditionally-compiled subsystem has
   that subsystem built by nobody.

Neither is a wrong result on its own terms — the scope line is printed honestly,
and `cyrius test` never claimed to take `-D`. The problem is the **aggregate**:
`cyrius audit` reads as "everything is checked", and downstream projects wire it
into CI on that basis.

## Reproduction

Complete, ~30 lines. Also reproducible in svara at tag `3.5.1`.

```sh
mkdir -p repro/src repro/tests && cd repro
```

`cyrius.cyml`:

```toml
[package]
name = "auditscope"
version = "0.1.0"
license = "GPL-3.0-only"
language = "cyrius"
cyrius = "6.5.35"

[build]
entry = "src/main.cyr"
output = "build/auditscope"

[deps]
stdlib = ["syscalls", "string", "io", "assert", "alloc", "vec", "math", "fmt"]
```

`src/main.cyr` — deliberately clean:

```
# main.cyr -- clean by construction.
# entry point
fn main() { return 0; }
var exit_code = main();
syscall(60, exit_code);
```

`tests/a.tcyr` — one over-length line and one untracked deferral:

```
# a.tcyr
fn main() {
    alloc_init();
    test_group("scope");
    # TODO wire this up properly
    assert_eq(1, 1, "this next line is deliberately over one hundred and twenty characters long to trip the line-length rule xxxxxxxxxx");
    return assert_summary();
}
var exit_code = main();
syscall(60, exit_code);
```

`tests/b.tcyr` — passes without a define, fails with one:

```
# b.tcyr
fn main() {
    alloc_init();
    test_group("define");
#ifdef FEATURE
    assert_eq(0, 1, "this assertion exists only under -D FEATURE, and it FAILS");
#endif
#ifndef FEATURE
    assert_eq(1, 1, "no define: trivially passes");
#endif
    return assert_summary();
}
var exit_code = main();
syscall(60, exit_code);
```

### Expected vs actual

```
$ cyrlint tests/a.tcyr
  deferral line 5: untracked 'TODO' (cross-reference a CHANGELOG/issue/roadmap entry, or #skip-lint)
  warn line 6: line exceeds 120 characters
1 untracked deferrals
1 warnings

$ cyrius audit ; echo "exit: $?"
  scope: src  (lib/ excluded — vendored deps, not project source)
── lint ──
  ok: lint clean            <-- gap 1: the two findings above are invisible
── tests ──
2 passed, 0 failed          <-- gap 2: b.tcyr's -D FEATURE half was never built
exit: 0

$ cyrius build -D FEATURE tests/b.tcyr /tmp/b_on && /tmp/b_on ; echo "exit: $?"
  FAIL: this assertion exists only under -D FEATURE, and it FAILS
exit: 1
```

So `cyrius audit` exits 0 on a project that has lint violations **and** a failing
test.

## Root cause (speculation — not verified against cycc internals)

**Gap 1** looks deliberate: the banner `scope: src (lib/ excluded — vendored
deps, not project source)` suggests the intent was to exclude **`lib/`**, and
restricting to `src/` was the mechanism. That correctly excludes vendored bundles
but takes `tests/` and `benches/` with it. If so the fix is a scope of
`src/ + tests/ + benches/` rather than `src/`, keeping `lib/` excluded.

**Gap 2** is an argument-forwarding gap: `cyrius build` accepts `-D NAME` (before
the source/output operands) but `cyrius test` rejects it —
`cyrius test -D LOGGING tests/x.tcyr` fails with `error: no such file: -D`. The
tests leg of `audit` has no way to be told about defines even if a caller wanted to.

## Proposed fix

Two independent changes; either is useful alone.

1. **Widen the fmt / lint / docs scope to the project's own source**, i.e. add
   `tests/` and `benches/` while still excluding `lib/`. If a narrower default is
   wanted for compatibility, a `--scope all` flag would do — but the honest
   default is that a `.tcyr` the tests leg compiles is project source.

2. **Let `cyrius test` (and therefore `cyrius audit`) take `-D NAME`.** Forwarding
   it to the per-file compile is probably enough. A richer option would be a
   manifest key — e.g. `[audit] defines = [[], ["LOGGING"]]` — so `cyrius audit`
   runs the suite once per configuration; that is what a project with an
   `#ifdef`-gated subsystem actually needs, and it would make the aggregate gate
   genuinely aggregate.

An intermediate that costs almost nothing: **have `audit` print what it did not
check** — "lint scope: src (tests/, benches/ not linted)" and "tests: no defines".
The gaps become visible without changing behaviour.

## Consumer-side workaround (shipped in svara 3.4.0 / 3.5.1)

Both are extra CI steps, since `cyrius audit` alone is not sufficient.

**Gap 1** — lint the rest of the project explicitly:

```sh
for f in tests/*.tcyr tests/*.bcyr tests/*.fcyr benches/*.bcyr; do
    [ -f "$f" ] || continue
    cyrfmt --check "$f" || fail=1
    out="$(cyrlint "$f" 2>&1)"
    echo "$out" | grep -qE '^0 warnings'            || { echo "$out"; fail=1; }
    echo "$out" | grep -qE '^0 untracked deferrals' || { echo "$out"; fail=1; }
done
```

**Gap 2** — drive the `-D` build from a script that uses `cyrius build` on the
`.tcyr` directly and runs the resulting binary (a `.tcyr` is an ordinary program
with `main()` + `assert_summary()` + `syscall(60, rc)`, so this works):

```sh
cyrius build -D LOGGING tests/logging.tcyr "$OUT/logging-on" && "$OUT/logging-on"
```

svara's full version is `scripts/check-logging.sh` at tag 3.5.1 — it builds and
runs both ways and additionally requires each build to emit no `warning:` at all.

## Why this is worth fixing rather than just documenting

svara found each gap only by accident, a release apart:

- The `-D` gap surfaced when adding an `#ifdef LOGGING` subsystem and realising
  `cyrius audit` had compiled none of it.
- The lint gap surfaced when a new 300-line test suite with **five** >120-char
  lines passed `cyrius audit` clean; it was caught by running `cyrlint` on the
  file by hand, for unrelated reasons.

A project that trusts the aggregate gate — which is what it is for — would have
shipped both.
