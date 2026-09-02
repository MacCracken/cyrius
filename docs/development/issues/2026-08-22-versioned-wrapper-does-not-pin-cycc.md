# `~/.cyrius/versions/<pin>/bin/cyrius` does not pin `cycc` — a release cannot be certified against its manifest pin

**Status:** 🟠 **STILL OPEN at v6.5.37 — an ADJACENT defect was fixed; this one was not.** Re-measured 2026-09-01: `versions/6.5.32/bin/cyrius which` still reports `~/.cyrius/bin/cycc`, the CURRENT compiler. ⚠ What v6.5.37 fixed must not be mistaken for this: `_try_redirect_to_pinned` used `file_exists("src/main.cyr")` to mean "am I the cyrius repo?", true for essentially every project since that is what `cyrius init` generates — so the pin redirect was SKIPPED for almost every consumer (same repo reported 6.3.35 without the file, 6.5.36 with it). Now `_dep_is_cyrius_source_repo()`, gated. The wrapper-resolves-the-wrong-cycc half is untouched.
**agnosai 2.0.5**. Not a codegen defect; a **toolchain-selection** one. The build *does* warn, so
nothing is silent — but there is no documented way to act on the warning short of mutating the
global install.

## What happens

`cyrius` resolves `cycc` through **`$CYRIUS_HOME/bin`** (default `~/.cyrius/bin`), which is a
symlink to `versions/<contents of ~/.cyrius/current>/bin`. It does **not** resolve `cycc`
relative to its own location, and it does **not** consult `PATH`. So invoking the *versioned*
wrapper for the pinned toolchain still compiles with whichever `cycc` is globally active:

```
$ cat ~/.cyrius/current
6.5.33

$ ~/.cyrius/versions/6.5.32/bin/cyrius --version
cyrius 6.5.32
manifest-pin: 6.5.32              # <-- no drift reported here

$ ~/.cyrius/versions/6.5.32/bin/cyrius which
/home/macro/.cyrius/bin/cycc      # <-- 6.5.33, NOT the 6.5.32 sibling

$ PATH=~/.cyrius/versions/6.5.32/bin:$PATH ~/.cyrius/versions/6.5.32/bin/cyrius which
/home/macro/.cyrius/bin/cycc      # <-- PATH does not change it either
```

and the build then reports, correctly but unactionably:

```
compile src/main.cyr -> build/agnosai [x86_64] warning: cyrius.cyml pins 6.5.32
  but cycc is 6.5.33 — toolchain drift
```

⚠ **The inconsistency is within a single command.** `cyrius lib sync --full` run from the same
versioned wrapper resolves `lib/` correctly — `synced from ~/.cyrius/versions/6.5.32/lib` — so
the wrapper *does* honour the pin for the stdlib snapshot and *does not* for the compiler. One
invocation, two different notions of "which toolchain am I".

The binaries genuinely differ (`cycc 6.5.32` sha `1456e9cb…`, `cycc 6.5.33` sha `d178aba3…`), so
this is not a cosmetic version string.

## Why it matters

Consumer repos are told to certify a release against the manifest pin, because `cycc` differs
between patch versions even when `lib/` is byte-identical. CI honours this correctly — it
installs the version named by `cyrius.cyml [package].cyrius` and gets a matching `cycc`. A
developer following the same instruction locally does **not**, and the two greens are not the
same green.

The only working local route found is to hand-build a `CYRIUS_HOME`:

```sh
SHIM=/tmp/cyrius-home-6.5.32
mkdir -p $SHIM
ln -s ~/.cyrius/versions/6.5.32/bin $SHIM/bin
ln -s ~/.cyrius/versions/6.5.32/lib $SHIM/lib
ln -s ~/.cyrius/versions      $SHIM/versions   # `lib sync` looks for versions/<pin>/lib
ln -s ~/.cyrius/deps          $SHIM/deps
cp    ~/.cyrius/dlopen-helper $SHIM/
echo 6.5.32 > $SHIM/current
CYRIUS_HOME=$SHIM cyrius build src/main.cyr build/x     # 0 drift warnings
```

That is four symlinks, a copy and a sentinel file to do what the versioned wrapper looks like it
already does — and the `versions` symlink is only discoverable by hitting
`error: cyrius.cyml pins version 6.5.32 but it is not installed at $SHIM/versions/6.5.32/lib`.

## Suggested fix — either would close it

1. **Resolve `cycc` next to the wrapper.** If `argv[0]` lives in `versions/<V>/bin`, prefer
   `versions/<V>/bin/cycc` over `$CYRIUS_HOME/bin/cycc`. Makes the versioned wrapper mean what
   it appears to mean, and needs nothing from the caller.
2. **Give the pin authority, or a switch.** Either have `cyrius build` select
   `versions/<manifest-pin>/bin/cycc` when it is installed — turning today's drift *warning*
   into a resolution — or add the `cyrius use <version>` / `--toolchain <version>` the warning
   implicitly asks for.

(1) is the smaller change and fixes the reported case directly. (2) additionally makes the
default path correct for anyone who never thinks about wrappers.

Whichever is taken, the drift warning should say what to run. It currently names the problem and
offers only `CYRIUS_NO_WARN_PIN_DRIFT=1`, which silences the diagnostic rather than fixing the
build — the one response that should not be the only one documented.

## Not affected

- CI. It installs the pinned version as the *active* toolchain, so `~/.cyrius/bin/cycc` is
  already correct there.
- `lib/` provisioning, which honours the pin from the versioned wrapper as shown above.
