# `cyrius-watch.sh` builds with raw `cat | cycc`: its output is unsigned and SIGKILLed on Apple Silicon, and an entry-relative `include` fails on every OS — RESOLVED

> ✅ **RESOLVED in v6.7.14** (PL-8, `bcf1bb4fc` + `812c304e5` (the user's decision D60, 2026-10-16: "The same build as `cyrius build`"). Both build lines of `scripts/cyrius-watch.sh` are `"$CY" build "$SRC" "$OUT"`, with no `2>/dev/null` and no `>` redirect. The CLI is `CYRIUS_BIN`, else `cyrius` on PATH, else `$CYRIUS_HOME/bin/cyrius`, and `CYRIUS_CC` no longer picks a compiler. The usage line names the script; no `watch` verb was added. Repro 1 on ecb: the output launches and exits 42, `Signature=adhoc` (was killed, 137). Repro 2 on x86_64 Linux: the entry-relative include builds (4,448 B, exit 42; was COMPILE ERROR with an empty `w.out`). It also builds with [deps] on ecb and ach. A broken source shows the compiler's diagnostic and keeps the previous output. Rows: new `tests/gates/toolchain/cyrius_watch_builds_like_build.sh`, with `CYRIUS_CC=/bin/false` throughout. Axis 1: the first pass's output is byte-identical to `cyrius build`'s and exits 42. Axis 2: a failed build shows the diagnostic and keeps the output. Axis 3: the rebuild loop exits 43. Mutants a – c RED, and it passes under `bash -eo pipefail` (`812c304e5`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN**. Measured 2026-10-15 on the 6.7.12 darwin lane's tree (l6712-darwin @ f60df9df), on ecb (Darwin
27.0.0 arm64), ach (Darwin 22.6.0 x86_64) and this x86_64 Linux box. Filed from unit D3. That unit made both macOS
tarballs ship `bin/cyrius-watch.sh` (issues/archived/2026-10-11-macos-tarballs-omit-cyrius-watch-decision.md, the user's
decision D4, 2026-10-15). Running the newly shipped script on the hosts showed what it builds.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (platform lane, wave 1, unit P3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D60 — The same build as `cyrius build`.
**Severity:** Low. The shipped watcher reports `built N bytes`, but on Apple Silicon the binary dies at its first
exec. On every OS it reports `COMPILE ERROR` for a project `cyrius build` compiles. Workaround: `cyrius build`.
**Affects:** `scripts/cyrius-watch.sh` (`[release] scripts`), lines 30 and 38:
`cat "$SRC" | "$CC" > "$OUT" 2>/dev/null && chmod +x "$OUT"`. It ships in the x86_64 Linux tarball and the source
install, and since 6.7.12 in both macOS tarballs.

## Reproduction

### 1. Apple Silicon: the watcher's output is killed at exec (ecb)

Run from the 6.7.12 arm64 tarball, installed with `install.sh` (`CYRIUS_INSTALL_TARBALL`, throwaway `HOME` and
`CYRIUS_HOME`):

```sh
printf 'fn main() { return 42; }\n' > main.cyr
CYRIUS_CC="$CYRIUS_HOME/bin/cycc" "$CYRIUS_HOME/bin/cyrius-watch.sh" main.cyr out &   # killed after 4 s
./out; echo $?
```

```
cyrius watch: main.cyr → out (every 1s)
  cycc: /Users/macro/_d3_watch_1977902/ih_after/bin/cycc
  ctrl-c to stop

[10:19:02] built    49660 bytes
hostrow.sh: line 7: 70264 Killed: 9               "$D/w/out"
137
```

Confirmed with the same tarball unpacked by hand on ecb (`cat main.cyr | bin/cycc > out`):

```
unsigned-rc=137
out: code object is not signed at all
adhoc-signed-rc=42          # after codesign -s - -f out
```

On ach (Intel) the same run prints `built 8192 bytes` and `./out` exits 42: x86_64 macOS runs unsigned binaries.

### 2. Every OS: an include relative to the entry file (x86_64 Linux)

```sh
mkdir -p src
printf 'include "helper.cyr"\nfn main() { return helper(); }\n' > src/main.cyr
printf 'fn helper() { return 42; }\n' > src/helper.cyr
printf '[package]\nname = "wp"\nversion = "0.1.0"\n' > cyrius.cyml
cyrius build src/main.cyr built.out && ./built.out; echo $?
CYRIUS_CC=build/cycc sh scripts/cyrius-watch.sh src/main.cyr w.out     # killed after 3 s
```

```
compile src/main.cyr -> built.out [x86_64] OK (4448 bytes)
42
cyrius watch: src/main.cyr → w.out (every 1s)
  ...
[10:21:00] COMPILE ERROR
```

Raw `cat src/main.cyr | cycc` says `error: cannot open include file: helper.cyr`. The watcher discards that
stderr (`2>/dev/null`), so the user sees only `COMPILE ERROR`, and the `>` redirect has already left an empty `w.out`.

## Root cause

The watcher compiles with the raw compiler, not `cyrius build`. CLAUDE.md reserves raw `cat | cycc` for the
compiler's own self-host. Raw cycc gets none of the work `cyrius build` does:
- ad-hoc codesigning on macOS (`_macho_codesign`, cbt/build.cyr:1914);
- the manifest's `[deps]` and includes prepend;
- the `#@incdir` marker that resolves `include` relative to the entry file;
- the target and strict flags.

Both shapes above come from that one recipe.

## Fix direction (for whoever places it)

- Rebuild through `cyrius build "$SRC" "$OUT"`, resolved like the other CLI siblings. That also covers the codesign.
- Or keep raw cycc and add a `codesign -s - -f` on Darwin. That fixes shape 1 only.
- Either way, show the compiler's diagnostic instead of discarding it, and do not leave a truncated `$OUT` behind
  on a failed build.

Which recipe the watcher uses is the user's call, because it changes what the watcher builds on Linux too.

A related point: the script's usage line (`# Usage: cyrius watch [src] [out]`) names a verb the CLI does not have.
`cyrius watch src/main.cyr` prints `Unknown command: watch`. The script runs only by its own name.
