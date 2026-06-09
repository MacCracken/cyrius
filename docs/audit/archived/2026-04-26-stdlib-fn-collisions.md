# Stdlib fn-name collision audit (v5.7.9)

> **ARCHIVED — RESOLVED.** The one genuine collision (`patra json_build` →
> `patra_json_build`) was renamed in CHANGELOG [5.7.9]; the other 65 were
> `#ifdef` arch-conditional false positives, and a warn-on-duplicate-fn-name
> check was added. Archived 2026-06-09 (v6.1.18 doc sweep).

Date: 2026-04-26
Cyrius version at audit: 5.7.8 (in-flight v5.7.9 work)
Source of truth: `lib/*.cyr` after `cyrius deps` resolves the
6 manifest deps (sakshi, patra, sigil, yukti, mabda, sankoch)
into `lib/`.

## Method

```sh
grep -h '^fn ' lib/*.cyr | \
  sed -E 's/^fn ([a-zA-Z_][a-zA-Z0-9_]*)\(.*$/\1/' | \
  sort | uniq -c | sort -rn | awk '$1 > 1'
```

Returns 66 fn-name occurrences with count > 1. Each entry was
then traced to its defining files via
`grep -ln "^fn <name>(" lib/*.cyr` and classified.

## Result

**1 genuine collision** (cross-module, both files always included):

| Fn name | File A | File B | Notes |
|---------|--------|--------|-------|
| `json_build` | `lib/json.cyr:125` (arity 1) | `lib/patra.cyr:2931` (arity 6) | Different arities, different semantics. patra's takes a buffer + max + keys/vals/types arrays; json.cyr's takes a vec of pairs. **Last-include wins.** |

**65 false positives** — all arch-conditional, only one variant
active per build via `#ifdef CYRIUS_TARGET_*`:

- **Syscalls** (lib/syscalls_x86_64_linux.cyr vs
  lib/syscalls_aarch64_linux.cyr vs lib/syscalls_macos.cyr vs
  lib/syscalls_windows.cyr): `sys_*` family (~40 names),
  `WIFEXITED`/`WEXITSTATUS`/`WIFSIGNALED`/`WTERMSIG`,
  `is_err`/`err_code`, `sigset_*`, `epoll_*`, `timerfd_*`,
  `timerspec_*`.
- **Allocator** (lib/alloc.cyr vs lib/alloc_macos.cyr vs
  lib/alloc_windows.cyr): `alloc`, `alloc_init`, `alloc_used`,
  `alloc_reset`, `arena_*` family.
- **Args** (lib/args.cyr vs lib/args_macos.cyr): `args_init`,
  `argc`, `argv`.

The arch-guards are pre-existing and load-bearing; pulling N
variants together would break independently of any fn-name
collision rule (different syscall numbers, different stack-
frame conventions on the args path, etc.). They're not part of
the v5.7.9 scope.

## Decision: option (b) — warn + last-wins

Three resolution rules were considered (per roadmap):

- **(a) Hard error** on duplicate fn-name across translation
  units. Most strict, breaks any code that happens to collide.
- **(b) Warn + last-wins** (today's silent behavior, made
  visible). Lower friction, surfaces the issue.
- **(c) Arity-aware overload resolution.** Highest ergonomic,
  but a real semantic addition.

**Picked (b)** for v5.7.9. Rationale: the only genuine collision
in the ecosystem today is `json_build`, and v5.7.9 also renames
patra's variant to `patra_json_build` (resolving the collision
at the source). The warning is the diagnostic that future
collisions surface loudly instead of silently miscompiling. (c)
is a separate language addition and gets its own slot if/when
the ecosystem actually grows enough overloaded utilities to
justify it.

## Action items shipped in v5.7.9

1. Rename `lib/patra.cyr:2931 fn json_build(buf, max, keys,
   vals, types, n)` → `fn patra_json_build(...)`. Matches the
   `patra_*` namespace convention used elsewhere in patra.
2. cc5 emits `warning:<file>:<line>: duplicate fn '<name>'
   (was at <prev-file>:<prev-line>; last definition wins)` when
   a fn-name registration finds an existing entry with a
   non-`-1` body offset.
3. New `tests/tcyr/fn_name_collision.tcyr` covers:
   - same-arity duplicate (warn fires)
   - different-arity duplicate (warn fires; semantic check via
     call-with-different-arg-count)
   - transitive collision via `include`
   - intentional-override via `#allow_redef` (if/when added)

## Forward note (v5.7.x)

The 65-false-positive count means the warn-on-duplicate
implementation MUST be aware of the arch-conditional include
pattern, OR the arch-conditional stdlib must be rewritten so
only one variant is ever read by the compiler. Cleanest fix:
the warn fires AT REGISTRATION time, after preprocessing —
so #ifdef'd-out variants never reach the registration path
and thus never warn. This is the natural choice given how
cyrius's preprocessor already works. No refactor of the stdlib
arch-guards is needed.
