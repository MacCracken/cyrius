# `~/.cyrius/versions/<pin>/bin/cyrius` does not pin `cycc` — a release cannot be certified against its manifest pin

**Status:** ✅ **FIXED at v6.5.42 — CLOSED.** `find_tools()` now prefers the `cycc` sitting beside the wrapper binary, so a version pin binds the compiler as well as the CLI. Ordered AFTER v6.5.37's in-repo `./build/cycc` branch (so this repo's wrapper-driven gates keep testing the newly-built compiler) and BEFORE `installed_cc` (the branch that was silently answering for every versioned wrapper). A bare-name invocation off `$PATH` has no path in `argv(0)` and falls through rather than guessing from the CWD. Gate: `tests/gates/toolchain/wrapper_resolves_sibling_cycc.sh` (3 axes).

⚖️ **LANDED AS-IS ON THE MAINTAINER'S EXPLICIT CALL, and the number that decision was made on is worth keeping.** Of 134 `cyrius.cyml` files under `~/Repos`, **128 pin something other than the current release**, and **45 pin into the 6.5.31–6.5.35 band carrying the v6.5.36 enum Critical** (constants ≥ 2^62 read as −1). Those repos were, until now, *accidentally protected by this very defect* — they were getting a newer, fixed compiler than they asked for. After this change they get the compiler they pinned, which is correct and is the entire point, but it means **45 repos may begin miscompiling large enum constants until their pins move forward.** The alternatives offered and declined were: refuse known-bad pins with an override, or bump the 45 pins first.

⚠ **This filing understated the problem.** v6.5.37's pin-redirect fix made the mismatch the DEFAULT path rather than a corner case: consumers reliably got the pinned WRAPPER and the CURRENT COMPILER.
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
