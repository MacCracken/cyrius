# An `include "lib/X.cyr"` of a stdlib module the manifest does not list compiles the toolchain's copy, unvendored and unlocked, with no word — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-16. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-16, by rasayan's Rust → Cyrius port: part 3a's probe 8 included `lib/sakshi.cyr`, which
rasayan's `[deps] stdlib` did not list, and it built (`rasayan/docs/development/port-parity.md` §3, probes 8 and 10);
part 3b's probes 7 and 10 compile sandhi and its TLS stack the same way.
**Reporter:** rasayan 2.0.0 port.
**Severity:** **Medium.** Nothing fails, which is the problem: `cyrius.lock` is "a contract, not a cache" (the guide,
6.6.4), and `deps --locked` / `--verify` report lib/ and the lock exact while the build compiles a module neither
covers. A change of toolchain changes that module unseen.
**Affects:** cycc / cyrius 6.7.18 (include resolution; `cyrius deps --locked`, `--verify`, `build -v`).

## Summary

A project that lists `["string", "fmt", "alloc", "syscalls", "io"]` and writes `include "lib/sakshi.cyr"`:
- `cyrius deps` vendors the five leaves and locks them; `lib/sakshi.cyr` is not created;
- `cyrius build` succeeds: the include falls through to the pinned toolchain's `lib/` (resolution is CWD-first);
- `cyrius build -v` lists the five declared leaves and says nothing of sakshi;
- `cyrius deps --locked` passes: "lib/ and cyrius.lock are exactly what the tags resolve".

The build mixes provenances silently. rasayan's probes that include `lib/sandhi.cyr` (not in its `[deps] stdlib`)
get sakshi from the project's vendored `lib/` and sandhi, tls, net and the rest from the toolchain, in one compile.

## Reproduction

[`repros/2026-11-16-unlisted-stdlib-include-resolves-from-the-toolchain.sh`](repros/2026-11-16-unlisted-stdlib-include-resolves-from-the-toolchain.sh)
(it makes its own project under
`build/`):

```sh
bash docs/development/issues/repros/2026-11-16-unlisted-stdlib-include-resolves-from-the-toolchain.sh; echo $?
# sakshi level 3
# lib/sakshi.cyr vendored: 0; lock rows: 0; deps --locked rc: 0; build lines naming sakshi: 0
# repro: DEFECT PRESENT (an unlisted stdlib include compiled from the toolchain, unvendored and unlocked, silently)
# 1
```

## Proposed fix

Any one of, in order of preference:
1. **Say it.** When an `include "lib/X.cyr"` resolves outside the project's `lib/` (the toolchain snapshot), print a
   `hint:` naming the leaf to add to `[deps] stdlib`, as the CLI already does for a bundle's missing sidecar leaf.
2. **Make `deps --locked` / `--verify` see it**: they fail when the last build compiled a `lib/` file that is neither
   vendored nor locked (the build knows its include set).
3. **Refuse it** under `--locked` / `CYRIUS_LOCKED=1`, where the user asked for exactly the locked inputs.

## Consumer-side workaround

rasayan lists every stdlib module its library code calls (sakshi and log since M0 part 3b), and its probes that need
sandhi say in their headers that it comes from the toolchain until M8 decides how `[lib.ai]`'s tests get it.
