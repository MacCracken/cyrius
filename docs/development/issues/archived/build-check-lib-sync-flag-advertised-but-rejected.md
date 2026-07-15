# `cyrius build --check-lib-sync` is advertised in usage but rejected by the arg parser

**Status:** ✅ **FIXED v6.4.64** (2026-07-14). Root cause confirmed — your speculation was right:
the usage string was updated when `_check_lib_freshness` landed in the wrapper, but the `build`
subcommand's flag loop never got the matching case, so the flag fell through to the unknown-flag
error. The pre-scan set `_check_lib_sync` and the check itself ran, but that loop still has to
CONSUME the flag. One `elif` in `cbt/cyrius.cyr`.

**Why it looked like it worked when it shipped, and why our gate missed it — worth recording.**
The only path that appeared to function was a project WITH drift: there the freshness check exits
non-zero *before* execution reaches the arg loop, so the flag is never parsed. `tests/lib_freshness.sh`
tested exactly that path, and asserted only "exit != 0" — which is ALSO what a rejected flag produces.
It passed for the wrong reason. **sandhi found this, not the gate.** The gate now asserts the flag is
ACCEPTED on a fresh lib/, asserts the drift failure by its MESSAGE rather than its exit code, and
gives its fixture a real cycc (without one every build died "cycc not found" and the exit-code
assertion proved nothing). Mutation-tested: reverting the wiring turns it RED.

Your "an advertised flag that errors is worse than an absent one, because CI authors copy the help
output" is exactly right, and it is the reason this is a fix rather than a doc revert.

**sandhi 1.9.0 can drop the workaround** — `cyrius build --check-lib-sync` now exits non-zero with
`error: ./lib/ is stale vs version-pinned <snap> — N bundled lib(s) differ: …` and exits 0 on a
fresh lib/. Requires a 6.4.64 pin.

**Original filing follows.**

---

**Discovered:** 2026-07-14 wiring the lib-freshness CI gate into sandhi 1.9.0
**Severity:** Low (a CI-only flag; no codegen/runtime impact — but it is dead on arrival)
**Affects:** cycc / cbt 6.4.63

## Summary

`cyrius build`'s own usage advertises `--check-lib-sync` and documents what it does, but
passing it fails with `error: unknown flag`. The flag appears to be documented in the usage
string without being wired into the argument parser, so the CI gate it describes cannot be
used by anyone who follows the help text.

This is the CI half of the shadow-`lib/` work that landed in 6.4.63 (see
`archived/yeo-cy-test-shadow-lib-silent-version-skew.md`, proposal 3 — "consider `cyrius
deps` / `cyrius build` verifying freshness, or offering `--check-lib-sync` for CI"). The
warning half shipped and works well; this half is advertised but unreachable.

## Reproduction

```sh
$ cyrius --version
cyrius 6.4.63

# usage advertises it, twice:
$ cyrius build 2>&1 | grep -- --check-lib-sync
Usage: cyrius build [--aarch64|--win|--agnos|--target=js] [-v] [-q] [--no-deps] [--strict]
                    [--strict-pin] [--check-lib-sync] [--features <list>] ...
  --check-lib-sync   fail the build if ./lib/ is a stale version vs the pinned snapshot (CI)

# ...but the parser rejects it (run from a project root, args passed directly):
$ cyrius build --check-lib-sync programs/smoke.cyr build/out
error: unknown flag '--check-lib-sync'
```

Reproduced in `~/Repos/sandhi` (pin 6.4.63). Not a shell-quoting artifact: the arguments are
passed directly, and every other documented flag in the same usage line is accepted. Without
the flag the same command builds fine.

Expected: the flag is accepted, and the build fails when `./lib/` is a stale version vs the
pinned snapshot (the counterpart of the `warning: ./lib/ shadows version-pinned … N bundled
lib(s) differ:` diagnostic that 6.4.63 added and which works correctly).

## Root cause (speculation — flag for verification)

Looks like the usage/help string was updated when the version-aware freshness check landed
in the CLI wrapper (`cbt/commands.cyr` `_check_lib_freshness`) but the corresponding case was
not added to `build`'s flag-parsing switch. I have not read the source — the observable
behaviour above is what is verified.

## Proposed fix

Wire the flag through to the existing `_check_lib_freshness` result: when set, a detected
skew should exit non-zero instead of warning. If the flag is intentionally deferred, remove
it from the usage text until it lands — an advertised flag that errors is worse than an
absent one, because CI authors copy the help output.

## Consumer

**sandhi 1.9.0** wanted this in CI so a stale vendored `lib/` reds the build rather than
emitting a warning that scrolls past. Working around it by relying on the (correct) 6.4.63
warning and a manual `cyrius lib sync --full` step. **yeo-cy-test** is the original filer of
the shadow-`lib/` issue this flag belongs to — it is the project that shipped for three minor
versions against a stale sigil precisely because the signal was easy to miss, so the CI gate
is the durable fix and is currently unavailable.
