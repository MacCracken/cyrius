# A `[deps.X]` with `git` + `tag` but no `modules` is silently ignored — 🟡 OPEN

**Status:** ✅ **RESOLVED v6.6.13** (bite I10, CVE-62 for the [deps.NAME] traversal found with it) — a modules-less `[deps.X]` means `dist/X.cyr` when the tag ships it, otherwise a named warning and a `vendored nothing` count. See CHANGELOG [6.6.13].
**Placement:** **6.6.13**, bite I10 (2026-10-01, with the other open issues) — see `roadmap.md` § 6.6.13.
`cbt/deps.cyr` only: a tooling lane.
**Discovered:** 2026-10-01, agnostic 0.1.7 (moving four dep tags in `cyrius.cyml` changed nothing in
`cyrius.lock`).
**Severity:** Medium — no wrong code is built, but a declared dependency is dropped without a word,
and the build then uses whatever a TRANSITIVE declaration of the same name resolves to. A project can
believe for months that it pins a version it never pinned.
**Affects:** cyrius 6.6.12 `cbt/deps.cyr` — `_process_named_deps` (the `need_clone` guard
`if (dep_git != 0 && dep_modules != 0)` and the copy guard `if (dep_path != 0 && dep_modules != 0 &&
dep_pin_ok == 1)`). Probably every version since `modules` became the copy list.
**Repro:** [`repros/git-dep-without-modules.cyml`](repros/git-dep-without-modules.cyml).

## Summary

A named dep is cloned only when it declares `modules`, and marked visited (`_dep_visited`) only when
a module was copied. A block with `git` and `tag` and nothing else is therefore never cloned, never
vendored, never pinned in `cyrius.lock` — and never reported. `cyrius deps` exits 0 and its output
does not mention the dep.

Because it is never marked visited, the closest-wins rule does not apply to it either: if another
dep declares the same name, THAT declaration is what resolves, at that dep's tag.

## Measured (6.6.12, empty dep cache, `CYRIUS_HOME` shim)

| `[deps.tyche]` | `cyrius deps` output | clone | `lib/tyche.cyr` | lock pin |
|---|---|---|---|---|
| `git` + `tag = "1.1.0"` | `cyrius.lock: 111 deps locked` | none | absent | none |
| … + `modules = ["dist/tyche.cyr"]` | `1 deps resolved` · `112 deps locked, 1 commit-pinned` | yes | present | yes |

## How it surfaced

agnostic declared bote, majra, ai-hwaccel and tyche at the root with `git` + `tag` only, so that its
lock would not depend on agnosai's `path = "../<sibling>"` lines (`cyrius.cyml` called them "not
optional"). They never did anything: agnosai's own declarations — which do list `modules` — resolved
all four. It went unnoticed while the root tags equalled agnosai's; at agnostic 0.1.7 the root tags
moved ahead (bote 3.3.13 → 3.3.15, majra 2.9.1 → 2.9.2) and the lock still recorded 3.3.13 / 2.9.1,
from agnosai.

## Suggested fix (for the maintainer to choose)

Either is enough; the first is the minimum.

1. **Say so.** `warning: [deps.tyche] declares no modules — nothing will be vendored, and a transitive
   declaration of 'tyche' will resolve instead` (and count it in the summary line).
2. **Or default it.** Treat a missing `modules` as `["dist/<name>.cyr"]` when that file exists at the
   tag, which is what every first-party dep in agnostic's graph ships.

## Consumer stopgap

agnostic 0.1.7 removed the four inert blocks (agnosai 2.1.2 now pins the latest of each), and the
`cyrius.cyml` comment says a block added to get ahead of a dependency's pin must list `modules`.
