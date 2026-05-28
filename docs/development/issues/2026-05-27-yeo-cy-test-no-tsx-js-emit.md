# TS/TSX front-end has no JS/JSX emit — frontend can be validated but not built by Cyrius

**Discovered:** 2026-05-27 during the SecureYeoman → Cyrius port viability probe (`secureyeoman/yeo-cy-test`)
**Severity:** Medium — blocks "build the TS/TSX frontend just by Cyrius"; consumer stopgap is a hand-lowered JS bundle
**Affects:** `cycc` 6.0.3 TS/TSX front-end (`--parse-ts` / `--lex-ts`); `cyrius` build tool

## Status

- **Main ask (TS→JS / JSX emit):** OPEN. Larger arc, minor TBD. See `roadmap-future.md`.
- **Adjacent papercut #1 (`ts_test_runner` `cyc` truncation):** FIXED in v6.0.5 (four v6.0.0 rename-drift length args in `programs/ts_test_runner.cyr`). The "still exits 0" sub-claim didn't reproduce — `syscall(60, rc)` was already wired at line 254; the truncation was the user-visible bug. See CHANGELOG [6.0.5].
- **Adjacent papercut #2 (`cyrius build` exits 0 on failure):** NOT REPRODUCED on v6.0.4 / .5. Empirical repro across `cmd_build`, `--strict`, `-q`, stdout-suppressed: every variant exits 1. `cmd_build` returns `compile()`'s result directly (unchanged since 2026-04-16). Likely a consumer shell wrapper masking the exit code. Locked in as an invariant via `_build_exit_nonzero_gate` (check.sh 81) so it can't silently regress.
- **Adjacent papercut #3 (`--parse-ts <file>` blocks on stdin):** FIXED in v6.0.5. `src/main.cyr`'s cmdline parser now captures the next non-flag arg after `--parse-ts` / `--lex-ts` and opens it instead of reading stdin. Backward-compatible with `dup2(fd, 0)` callers. Locked in via `_ts_path_arg_gate` (check.sh 82). See CHANGELOG [6.0.5].

## Summary

The Cyrius TS/TSX front-end parses but does not **emit**. `cycc --parse-ts`
cleanly accepts real-world TS/TSX — interfaces, `<K extends string, V>`
generics, default type params (`Result<T, E = Error>`), `?.`/`??`, async/await,
enums, `readonly`/optional members, destructuring, spread, tuples, `Record<K,V>`,
`// line comments`, and a full React component (`useState<Note[]>`, `useEffect`,
JSX with `.map`/`key`/`data-*`). The parser is genuinely complete and was a
pleasure to validate against. **But there is no TS→JS / JSX-lowering codegen
anywhere in the toolchain**, so the only thing Cyrius can do with a `.tsx` today
is say "yes, that parses."

`cyrius build web/app.tsx build/out` does **not** route through the TS
front-end at all — it treats the `.tsx` as *Cyrius source* and dies on the first
`//` (`error: <source>:1: unexpected '/'`, since Cyrius comments are `#`).

Net effect for a consumer building a web frontend: Cyrius can be the build-time
*validator* of the frontend, but not its *builder*. We author the typed source
in `web/app.tsx` (Cyrius-validated as a build gate) and hand-maintain the
browser-runnable `web/app.js` in parallel. That hand-lowering is the production
workaround in `yeo-cy-test` right now.

The expensive part — a correct, full-fidelity TS/TSX parser — already exists.
The ask is a codegen stage on top of the existing AST.

## Reproduction

```sh
# parses clean (exit 0) — note the </dev/null, see "Adjacent papercuts" below
cycc --parse-ts web/app.tsx </dev/null ; echo $?      # -> 0

# but cyrius build has no TS pipeline; it compiles .tsx as Cyrius source:
cyrius build web/app.tsx build/app.out
#   error: <source>:1: unexpected '/'
#   FAIL                       (and exits 0 — see papercut #2)
```

`web/app.tsx` is ~40 lines of ordinary typed React-flavored TS; every construct
in it parses individually and together.

## What would close it

A `cycc --emit-js <file.tsx>` (or `cyrius build --target=js`) that walks the
already-built AST and emits browser JS: strip type annotations / interfaces /
type aliases, lower JSX to `createElement`-style calls (or a configurable
pragma), and pass ESM through. A bundler is out of scope; single-file emit
would already let a consumer serve a real frontend built entirely by Cyrius.

## Adjacent papercuts (found in the same investigation)

These each independently break *scripting* the TS front-end (CI, build tools):

1. **`cycc --parse-ts <file>` blocks on stdin even when given a file argument.**
   In a no-tty / backgrounded / scripted context it hangs forever — one
   orphaned invocation sat ~17 min holding a lock and wedging subsequent runs.
   Workaround: always invoke with `</dev/null`. Fix: don't read stdin when a
   path argument is present.
2. **`cyrius build` exits 0 on compile failure.** The `cyrius build web/app.tsx`
   above printed `error: …` + `FAIL` but returned exit code 0, so a build script
   can't detect failure by status — it must scrape stderr. Compile errors should
   be non-zero.
3. **`ts_test_runner` looks for the compiler at `~/.cyrius/bin/cyc`** (truncated;
   should be `cycc`) and prints `error: cycc not found at …/cyc`, then **still
   exits 0**. The official TS harness is unusable out of the box and silently
   "passes." Two bugs: wrong binary name + zero exit on its own error path.

## Context

Part of `secureyeoman/yeo-cy-test`, a thin full-stack slice (Cyrius HTTP server
+ patra storage + TS/TSX frontend) standing up the SecureYeoman stack on Cyrius
to de-risk the eventual port. The backend side is viable today; the frontend is
gated on this emit stage. Full write-up: `secureyeoman/yeo-cy-test/FINDINGS.md`.
