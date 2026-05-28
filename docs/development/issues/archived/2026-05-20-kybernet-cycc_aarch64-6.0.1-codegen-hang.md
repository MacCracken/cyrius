# cycc_aarch64 6.0.1 hot-spins indefinitely after parse on kybernet source

> **Filed**: 2026-05-20 (kybernet side — cyrius agent please pick up and triage)
> **Severity**: Hard regression — aarch64 cross-build unusable for kybernet
> **Last-known-good**: cc5_aarch64 v5.10.44 (kybernet 1.2.1 cut, 2026-05-11 — cross-built clean in seconds)
> **First-bad-observed**: cycc_aarch64 v6.0.1 (no intermediate cyrius pin tested between 5.10.44 and 6.0.1)
> **Reproduces with**: kybernet HEAD `f200aab` (1.2.1 + cyrius.cyml bumped to `cyrius = "6.0.1"`)
> **Adjacent**: [`2026-05-19-cycc-6.0.0-uefi-fncall-ud2-emit.md`](./2026-05-19-cycc-6.0.0-uefi-fncall-ud2-emit.md) — sibling 6.0.x-era regression; both land in the cc5→cycc rename cycle

## Symptom

`cyrius build --aarch64 src/main.cyr build/kybernet-aarch64` parses kybernet's compiled unit (kybernet source + agnosys-core + agnosys-storage + agnosys-trust + agnostik + libro + patra + argonaut selective imports + stdlib pins), emits the expected dep-bundle warning catalogue in **<1 second**, then `cycc_aarch64` enters a 99.9% CPU hot loop **with no further stdout / stderr** indefinitely. Killed at the 4-minute mark on multiple attempts; never produced an output binary.

The same source compiled and produced an `aarch64` ELF binary in seconds under cc5_aarch64 5.10.44 (the 1.2.1 cut's binary `build/kybernet-aarch64` is 1.26 MB and dated 2026-05-11).

## Repro

```sh
cd ~/Repos/kybernet
# Confirm the bump
sed -i 's|cyrius = "5.10.44"|cyrius = "6.0.1"|' cyrius.cyml
~/.cyrius/bin/cyrius deps                                              # 10 deps resolved, clean
CYRIUS_DCE=1 ~/.cyrius/bin/cyrius build src/main.cyr build/kybernet    # OK in ~5s, 1.146 MB
~/.cyrius/bin/cyrius test src/test.cyr                                 # 177 passed, 0 failed
rm -f build/kybernet-aarch64
~/.cyrius/bin/cyrius build --aarch64 src/main.cyr build/kybernet-aarch64
# emits dep warnings within 1s, then hangs
```

Reproduces both with and without `CYRIUS_DCE=1` set on the aarch64 invocation. Reproduces with `-v` (verbose) — verbose path prints compiler / source / output before the warnings, then same hang.

## Compile-time output (full, up to kill)

```
10 deps resolved
cyrius.lock: 0 deps locked
compile src/main.cyr -> build/kybernet-aarch64 [aarch64] note: cwd ./lib/ shadows version-pinned /home/macro/.cyrius/versions/6.0.1/lib/ — delete ./lib/ to use the version-matched snapshot, or set CYRIUS_NO_WARN_SHADOW_LIB=1 to silence this note
warning:9055: match arms span multiple enums (exhaustive-coverage check skipped)
warning:13522: duplicate fn 'err_permission_denied' (last definition wins)
warning:13534: duplicate fn 'err_invalid_argument' (last definition wins)
warning:13537: duplicate fn 'err_not_supported' (last definition wins)
warning:13546: duplicate fn 'err_io' (last definition wins)
warning:28342: duplicate fn 'health_check_new' (last definition wins)
warning:34450: duplicate fn '_hex_nibble' (last definition wins)
[no further output — process hot-loops in cycc_aarch64]
```

The warning catalogue is identical to the x86_64 cycc output (and identical to what cc5_aarch64 5.10.44 produced before completing successfully). All warnings are pre-existing dep-bundle duplicates that 1.1.0+ CHANGELOG documents.

## Process state at hang

```
PID     ELAPSED %CPU %MEM   RSS CMD
19341     03:56  0.0  0.0  1164 /home/macro/.cyrius/bin/cyrius build --aarch64 src/main.cyr build/kybernet-aarch64
19343     03:56 99.9  0.0 11292 /home/macro/.cyrius/bin/cycc_aarch64
```

The parent `cyrius` wrapper is idle (waiting on the child). `cycc_aarch64` is CPU-bound (99.9%), small RSS (11 MB — not allocating heavily), no I/O syscalls visible. Pattern is "tight algorithmic loop in codegen" rather than "stuck on syscall" or "OOM thrash."

`gdb -batch -p $PID -ex "thread apply all bt"` returned empty (stripped binary).

## Scope check — is it universal, or kybernet-specific?

Compiling a one-line `fn main()` source from within the kybernet project directory (so `cyrius build` picks up the kybernet `cyrius.cyml` and prepends all deps) **errors fast** on a deliberate parse error after emitting the same dep-bundle warnings:

```
$ ~/.cyrius/bin/cyrius build --aarch64 /tmp/minimal_aarch64_repro.cyr /tmp/out
[dep warnings as above]
error:43197: expected '{', got identifier 'i32'
  at fail: fn=3256/8192 ident=93798/262144 var=1805/8192 fixup=7635/32768
FAIL
```

So `cycc_aarch64` 6.0.1 parses, types, error-reports, and exits clean on a smaller compiled unit. The hang is **not a universal aarch64-target failure** — it's specific to the codegen workload of kybernet's `src/main.cyr` + full dep bundle.

The cell counts at fail-time on the minimal compile (`fn=3256 ident=93798 var=1805 fixup=7635`) are a useful upper bound on parse-stage state. The hung kybernet compile gets past parsing (warnings emit) so codegen sees ≥ this many fns. Possible suspects: codegen pathology in DCE-walk, register-allocation, or instruction-selection on a kybernet-sized unit. The cc5_aarch64 5.10.44 binary did this work in ~3-5s.

## What changed in 6.0.1 vs 5.10.44 (toolchain-side)

Diffing `~/.cyrius/versions/6.0.1/bin/` vs `~/.cyrius/versions/5.10.44/bin/`:

- `cc5_aarch64` → renamed `cycc_aarch64` (`cc5_aarch64` kept as a symlink in 6.0.1).
- Binary size: `cc5_aarch64` 491,832 B (5.10.44) → `cycc_aarch64` 564,448 B (6.0.1) — **+72,616 B (+15%)** of additional code.
- New peers introduced: `cybs` (44,496 B), `cyaudit` (44,512 B), `ts_test_runner` (82,072 B).
- `cyrius` wrapper itself: 170,896 B → 185,136 B (+14,240 B).

The +15% growth in cycc_aarch64 is the most suspicious signal — that's where the codegen path lives.

## Reproducibility

4/4 attempts hung at the same point (no recovery, no progress indication). Killed via `kill` (SIGTERM) — child orphans live; required `kill -9` on `cycc_aarch64` PID to clean up.

## Workaround at kybernet side

Kybernet 1.2.2 cut decision is open as of filing. Options under consideration:

1. Pin kybernet's `cyrius.cyml` to 5.11.4 (matches agnosys/libro siblings) — known to cross-build (sibling repos are green there).
2. Ship 1.2.2 x86_64-only at 6.0.1, document aarch64 as broken in CHANGELOG, file this issue.
3. Roll back the cyrius bump entirely.

Whichever lands, kybernet's x86_64 build under 6.0.1 is clean (DCE binary 1.146 MB; 177/177 tests pass), so the toolchain isn't dead — just the aarch64 cross path on kybernet's compile size.

## Asks of the cyrius agent

1. **Bisect the cycc_aarch64 code path** between 5.10.44 (last-known-good) and 6.0.1 — particularly any codegen change that scales worse-than-linearly with compiled-unit size. The cc5→cycc rename cycle suggests significant internal refactoring.
2. **Confirm whether a `CYRIUS_DEBUG_PHASES=1`-style env var exists** in 6.0.1 to print phase markers (parse / typecheck / DCE / regalloc / instsel / emit) — kybernet has no visibility into where the hang sits.
3. **Confirm the `cwd ./lib/ shadows version-pinned ...` note** is informational only, not a load-bearing failure mode. (Tested with `CYRIUS_NO_WARN_SHADOW_LIB=1` — hang reproduces identically, so the note is not the cause, only worth confirming.)
4. Consider whether the sibling 6.0.0 UEFI `fncall` regression (`2026-05-19`) shares a root cause — both surfaced inside the cc5→cycc rename cycle, both are codegen-stage.

— filed by kybernet maintainer, 2026-05-20
