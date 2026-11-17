# `cyrius lint` compiles without the manifest's stdlib, so it refuses a capturing closure that `cyrius build` accepts — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-15.
**Discovered:** 2026-11-15, by pramana's Rust → Cyrius port (M0 step 9, probe P3;
`pramana/docs/development/port-parity.md` §6.2).
**Reporter:** pramana 2.0.0 port (filed with no stand-in: a coding rule covers it, `pramana-port-plan.md` §8.3, §10).
**Severity:** **Low.** Nothing computes wrong, but the lint gate disagrees with the build on the same file, so a
library either adds an include it doesn't need for the build or fails its cleanliness check.

## Summary

`cyrius build` resolves the stdlib from `cyrius.cyml` ("source files only need project includes"). `cyrius lint` first
compiles the file to check that it parses, and that compile does not read the manifest. A missing stdlib function is
only a warning there. A capturing closure, though, is a hard error, *a capturing closure needs include
"lib/alloc.cyr" for its heap env*, and lint then runs none of its checks and exits 1.

So a library file with a capturing closure must `include "lib/alloc.cyr"` itself to pass lint, though the build has
it already (include-once makes the extra include a no-op there).

## Reproduction

[`repros/2026-11-15-lint-refuses-a-capturing-closure-the-build-accepts.cyr`](repros/2026-11-15-lint-refuses-a-capturing-closure-the-build-accepts.cyr),
from the repo root:

```sh
cyrius build docs/development/issues/repros/2026-11-15-lint-refuses-a-capturing-closure-the-build-accepts.cyr /tmp/lintcap
/tmp/lintcap; echo "exit=$?"
# exit=0
cyrius lint docs/development/issues/repros/2026-11-15-lint-refuses-a-capturing-closure-the-build-accepts.cyr; echo "exit=$?"
# error: does not parse or compile, so lint checks were NOT run: …
# error:<source>:20:34: a capturing closure needs include "lib/alloc.cyr" for its heap env
# exit=1
```

## Ask

**Let lint's compile see what the build sees:** resolve the manifest's stdlib (and `[deps]`) when a `cyrius.cyml` is
present, as `build`, `test` and `vet` do. Or treat the closure's missing include as the warning a missing function
already is.

## Meanwhile

pramana's rule (CLAUDE.md): a file that builds a capturing closure includes `lib/alloc.cyr` itself, because
`cyrius lint` compiles without the manifest.
