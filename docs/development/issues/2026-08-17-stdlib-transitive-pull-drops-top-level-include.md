# A `[deps].stdlib` entry reached transitively never gets its top-level `include` prepended

**Status:** ✅ **RESOLVED in v6.5.28 — archive at slot close.**

> ### ✅ FIXED — the seen-guard conflated two jobs
>
> `_dep_copy_stdlib_recursive` both COPIES the module and PUSHES its top-level include, and the
> seen-guard `return 0` ran before the push. Once a module was pulled transitively it was
> marked seen, so its own `[deps].stdlib` entry short-circuited and never pushed the include.
> The seen path now services a top-level request via `_dep_push_include_once`.
>
> **The filed repro passes both ways.** Before: CASE A (async before chrono) 2 undefined
> symbols / no binary, CASE B fine. After: both cases 0 undefined, both emit a binary — the
> ordering artifact is gone.
>
> ⚠ **Top-level-only push preserved deliberately.** Pushing transitive includes too would have
> made the repro green while re-opening a PRIOR bug: an explicit include overrides the
> `#ifdef CYRIUS_TARGET_*` arch dispatchers, so both syscall peers parse at once (duplicate
> fns, wrong-arch syscall numbers). Gate axis 3 pins that BOTH push sites keep their `is_top`
> gate, so the easy over-fix cannot pass.
>
> Gate: `tests/gates/toolchain/stdlib_transitive_include_pushed.sh` (drives the filed repro;
> axis 0 is anti-vacuous because a repro that printed nothing would otherwise score clean).
**Placement:** unpinned — 6.5.x-line backlog. Resolver/toolchain item, so 6.x line — never 7.x.
**Discovered:** 2026-08-17 during kavach's `6.5.21 → 6.5.27` pin move (the whole tree stopped building).
**Severity:** Medium — hard build failure on a shipping consumer, with a known workaround. It would be High without the workaround: the failure is order-dependent, the diagnostic names a *symbol* rather than the module that went missing, and it propagates to every downstream consumer of an affected `dist/*.deps` sidecar.
**Affects:** cycc **6.5.26 – 6.5.27** (bisected below). The resolver guard is much older; 6.5.26's new include chain is what exposed it.

## Summary

`cyrius deps` copies every declared `[deps].stdlib` module into `lib/`, and separately pushes one
`include "lib/<mod>.cyr"` per module onto `_dep_includes` so `compile()` can prepend them. Those two
jobs share one function, and its de-dup guard runs **before** the push.

So when module **X** is pulled in transitively (as an `include` of some earlier module, `is_top=0`), X
is marked seen. When the resolver later reaches X's own **top-level** `[deps].stdlib` entry, it
short-circuits on the seen-set and returns — **without ever pushing X's `include`**.

The result is the confusing part: `lib/X.cyr` is present on disk, `cyrius deps` reports success, the
lockfile lists it — and every symbol in X is an undefined function. Nothing in the output names X.

⚠ **It is purely an ORDERING artifact of the manifest.** The same declared module set builds or fails
depending only on which entry comes first. That is what makes it expensive to diagnose: the manifest
looks correct, and it *is* correct.

⛔ **It is not confined to `[deps].stdlib`.** `_dep_pull_leaves` (`cbt/deps.cyr:780`) — which serves the
`requires` key and the `dist/<pkg>.deps` sidecar — calls the same function with `is_top=1`, so a library
whose sidecar lists the leaves in an unlucky order hands the identical failure to **every consumer of
its bundle**, on a machine where nobody edited anything.

## Reproduction

`docs/development/issues/repros/2026-08-17-stdlib-transitive-pull-drops-top-level-include.sh`
(self-contained; builds its own fixture in a temp dir, takes the cycc version as `$1`).

Two builds, **identical declared module set**, only the order differs:

```
$ ./2026-08-17-stdlib-transitive-pull-drops-top-level-include.sh 6.5.27
=== cycc 6.5.27 ===
CASE A (async before chrono)  stdlib = ["syscalls", "alloc", "async", "chrono"]
    lib/chrono.cyr vendored : YES
    'undefined clock_now_ns': 2
    binary emitted          : NO

CASE B (chrono before async)  stdlib = ["syscalls", "alloc", "chrono", "async"]
    lib/chrono.cyr vendored : YES
    'undefined clock_now_ns': 0
    binary emitted          : YES
```

The program under test is three lines:

```cyrius
fn main(): i64 {
    return clock_now_ns();
}
var r = main();
syscall(60, 0);
```

and the failure is:

```
warning: undefined function 'clock_now_ns'
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

⚠ **`chrono` is declared in both cases and vendored in both cases.** The error never mentions `chrono`.

### Bisect

Same CASE A fixture, every installed 6.5.x:

| cycc | `lib/async_macos.cyr` present | `undefined clock_now_ns` | binary |
|---|---|---|---|
| 6.5.21 | no | 0 | YES |
| 6.5.22 | no | 0 | YES |
| 6.5.23 | no | 0 | YES |
| 6.5.24 | no | 0 | YES |
| 6.5.25 | no | 0 | YES |
| **6.5.26** | **yes** | **2** | **NO** |
| **6.5.27** | **yes** | **2** | **NO** |

The break lands exactly on 6.5.26 — the release that added `lib/async_macos.cyr`
(*"Added — `lib/async_macos.cyr`, so macOS async EXISTS"*). That file carries
`include "lib/chrono.cyr"` (`async_macos.cyr:57`, the portable-`sleep_ms` change), and
`lib/async.cyr:47` includes it. So from 6.5.26 onward `chrono` is reachable transitively through
`async`, and any manifest listing `async` before `chrono` silently loses chrono's prepend.

⭐ **6.5.26 did nothing wrong.** The new include is correct and the resolver bug is years older; the
chain change merely walked into it. Any future stdlib module that grows an `include` of a commonly
declared leaf re-arms this for a different pair.

## Root cause

`cbt/deps.cyr:520-522` — the seen-check is the **first** statement, ahead of everything:

```cyrius
fn _dep_copy_stdlib_recursive(stdlib_dir, mod_name, is_top): i64 {
    if (_dep_stdlib_seen_has(mod_name) == 1) { return 0; }   # <-- returns before the push
    _dep_stdlib_seen_add(mod_name);
```

while the push it skipped lives 60 lines later, at `cbt/deps.cyr:582`:

```cyrius
    if (is_top == 1) { vec_push(_dep_includes, dst_full); }
```

The seen-set records **that** a module was resolved, not **at what level**. A module first seen at
`is_top=0` can never be upgraded to `is_top=1`, so its own top-level entry is a silent no-op.

⚠ The guard is load-bearing and must not simply be deleted — the comment above the function records
why. Pre-fix, every transitively copied file was pushed onto `_dep_includes`, which overrode the
`#ifdef CYRIUS_TARGET_*` arch dispatchers: both `syscalls_x86_64_linux.cyr` and
`syscalls_aarch64_linux.cyr` parsed at once, cascading `duplicate fn` warnings and binaries carrying
the wrong arch's syscall numbers. **The top-level-only push is correct; the ordering of the guard
against it is the defect.**

Both call sites that pass `is_top=1` are affected:
- the `[deps].stdlib` loop (`cbt/deps.cyr:~1880`), and
- `_dep_pull_leaves` (`cbt/deps.cyr:780`) — the `requires` key and the `dist/<pkg>.deps` sidecar.

## Proposed fix

Track the two facts separately: keep `_dep_stdlib_seen` as the copy/recursion de-dup it is, and add a
second set for "already pushed as a top-level include". Then a seen module arriving at `is_top=1` still
gets its include, and still skips the copy and the recursive scan:

```cyrius
fn _dep_copy_stdlib_recursive(stdlib_dir, mod_name, is_top): i64 {
    if (_dep_stdlib_seen_has(mod_name) == 1) {
        # Already copied + scanned. But if THIS is the top-level declaration and
        # the earlier visit was transitive, the include still owes a push.
        if (is_top == 1) { _dep_stdlib_push_top_once(mod_name); }
        return 0;
    }
    _dep_stdlib_seen_add(mod_name);
    ...
```

where `_dep_stdlib_push_top_once` pushes `lib/<mod>.cyr` onto `_dep_includes` guarded by its own
`_dep_stdlib_top_pushed` set, and the `is_top == 1` push at line 582 routes through the same helper so
the two paths cannot disagree.

⭐ This preserves the arch-dispatcher property exactly — nothing transitive is ever pushed, because the
new push is still gated on `is_top == 1`. It only repairs the case where a top-level declaration was
*silently downgraded* by an earlier transitive visit.

**Speculation, flagged as such:** the dedicated `_dep_stdlib_top_pushed` set may be unnecessary —
cyrius include resolution is include-once, so a duplicate `include` line is harmless. The set is
proposed only to keep `_dep_includes` free of duplicates for the temp-file writer at
`cbt/build.cyr:416`. If that writer already tolerates repeats, an unconditional push is simpler.

**Worth considering alongside the fix:** the diagnostic. A `[deps].stdlib` entry that resolves to a
no-op is currently invisible — the build fails several steps later naming a *symbol*. A one-line
verbose note ("`chrono`: already resolved transitively, no include emitted") would have turned this
from a bisect into a glance. `.24`'s work on `_dep_pull_leaves`' error text was in this same spirit.

## Consumer-side workaround (if any)

Shipped in **kavach 3.11.14**: an explicit `include "lib/chrono.cyr"` in `src/util.cyr` — kavach's
first `[lib].modules` entry — plus one each in `tests/kavach.fcyr` and `tests/samay_integration.tcyr`,
which include no `src/` module and so cannot inherit it.

```cyrius
# src/util.cyr — first module in [lib].modules
include "lib/chrono.cyr"
```

⚠ **Prefer the explicit include over reordering `[deps].stdlib`.** Reordering (moving `chrono` above
`async`) also works and is a one-line diff — kavach's CASE B above is exactly that — but it encodes an
assumption about *upstream's* include chains into a downstream manifest, and silently un-fixes itself
the next time a stdlib module grows an `include`. The explicit include is order-independent.

⭐ **For library authors, the explicit include also fixes your consumers.** `cyrius distlib` preserves
`include "lib/..."` lines into the bundle, and it emits the `.deps` sidecar in bundle order — so
kavach's include moved `chrono` to the **top** of `dist/kavach.deps`, ahead of `async`, which means
`_dep_pull_leaves` now reaches it at `is_top=1` first and consumers cannot hit the bug either. Two
independent protections from one line.

⚠ **Filed the same day, and causally linked:** documenting this bug in kavach's manifest is
what surfaced [`2026-08-17-auto-deps-4095-byte-manifest-window.md`](./2026-08-17-auto-deps-4095-byte-manifest-window.md) — the explanatory comment pushed `[deps]` past the 4095-byte prefix `_auto_deps` scans, so *no* deps were prepended at all. If you write up this issue in your own `cyrius.cyml`, put the text **below** the array.

⚠ Note for other consumers on the 6.5.26+ line: the exposure is **any** manifest or sidecar declaring
`chrono` *after* `async`, which is the alphabetical order most `[deps].stdlib` lists happen to use.
Anything using `clock_epoch_secs` / `clock_now_ns` / `sleep_ms` / `dt_now` is a candidate. Symptom to
grep for is `undefined function 'clock_` in a build that previously passed.
