# `cyrius doctest` auto-prepends nothing, where `tests` and `bench` prepend `[deps]`

**Status:** 🔴 OPEN — filed from a consumer (agnosai), measured against v6.5.18.
**Severity:** Medium. Not a wrong answer — a usability cliff that makes the feature
impractical on any project with dependencies, and it has already broken cyrius's own
`lib/hashmap.cyr` doctest.

## The inconsistency

`cyrius tests` and `cyrius bench` auto-prepend the project's `[deps].stdlib` and its
`[deps.NAME]` bundles. That is load-bearing enough that consumers document it as a rule —
agnosai's CLAUDE.md carries *"Do not `include "lib/syscalls.cyr"` (or any stdlib module) in
a `.tcyr`/`.bcyr` — the stdlib is auto-prepended, so an explicit include lands after it and
single-passes into an undefined-symbol error."*

**`cyrius doctest` prepends none of it.** Measured, in a project whose `cyrius.cyml`
declares `str` in `[deps].stdlib`:

```cyr
# >>> fn main() { var s = str_from("x"); if (str_len(s) != 1) { return 1; } return 0; }
# >>> var r = main(); syscall(60, r);
# === 0
```

```
warning: undefined function 'str_from'
warning: undefined function 'str_len'
0 passed, 1 failed (1 total doc tests)
```

Same for `[deps].stdlib` entries beyond the core (`SK_FATAL` from sakshi,
`bayan_json_v_null` from bayan) and for `[deps.NAME]` git bundles (`ACCEL_CPU` from
ai-hwaccel).

## What it costs

To doctest one three-line example in agnosai's `src/core/mod.cyr`, the block needs **24
hand-written `include` lines** before it — the whole transitive lib chain in single-pass
order — for **two** lines of actual example:

```cyr
# >>> include "lib/syscalls.cyr"
# >>> include "lib/alloc.cyr"
# >>> include "lib/result.cyr"
# >>> include "lib/fmt.cyr"
# >>> include "lib/io.cyr"
# >>> include "lib/str.cyr"
# ... 15 more ...
# >>> include "src/core/mod.cyr"
# >>> fn main() { ... }
# >>> var r = main(); syscall(60, r);
# === 0
```

It works — that block passes today — but the list is a copy of `src/main.cyr`'s include
order with no mechanism keeping the two in step, so it rots the first time a dependency
becomes reachable from `core/`. And the failure mode is a bare compile error that names a
missing symbol, never the missing `include`.

## It has already broken cyrius's own doctest

`cyrius doctest lib/hashmap.cyr` **fails on main**:

```
warning: undefined function 'str_data'
warning: undefined function 'str_len'
warning: undefined function 'str_eq'
error: refusing to emit binary with 3 reachable undefined function(s)
  FAIL: lib/hashmap.cyr:20 (compile error)
0 passed, 1 failed (1 total doc tests)
```

The block at `lib/hashmap.cyr:14-20` includes `lib/string.cyr`, but `str_data`, `str_len`
and `str_eq` live in `lib/str.cyr`. Two files, one letter apart, and nothing prepends the
right one. `lib/vec.cyr`'s doctest passes only because its example happens not to reach any
`str_*`.

That is the argument in miniature: if hand-listing is required, the list will be wrong, and
it will be wrong silently until someone runs the command.

## Expected

**Auto-prepend `[deps]` for doctests exactly as `tests` and `bench` do.** Then the block
above collapses to its last three lines, matches what a reader of `.tcyr` files already
expects, and `lib/hashmap.cyr`'s doctest starts passing without being touched.

If explicit includes must remain possible, prepending is still compatible: an explicit
`include` of an already-prepended module is the existing `.tcyr` hazard and is a separate
question — but nobody would need to write one.

Two smaller things noticed alongside, either of which would have saved time here:

- **`cyrius doctest` takes exactly one file.** `cyrius tests` takes a directory and recurses;
  `cyrius doctest` has no sweep, so there is no way to ask "are all my doctests passing?"
  short of a shell loop. A project-wide form would let it join a cleanliness gate the way
  `fmt`/`lint`/`doc` have.
- **`cyrius audit` does not appear to run doctests**, though its help says
  "project sweep: fmt/lint/docs/tests/bench" — worth confirming, since "docs" there reads
  like it might.

## Repro

```sh
cd any-project-with-deps
printf '# >>> fn main() { return str_len(str_from("x")) - 1; }\n# >>> var r = main(); syscall(60, r);\n# === 0\nfn _x(): i64 { return 0; }\n' > /tmp/dt.cyr
cyrius doctest /tmp/dt.cyr
```

and, in the cyrius tree itself:

```sh
cyrius doctest lib/hashmap.cyr
```
