# `cyriusly cmdtools` runs whatever `scripts/cyriusly` the current directory holds — OPEN

**Status:** 🟡 **OPEN** — the fix needs a packaging decision: the compiled cyriusly has no
installed shell twin to resolve.
**Placement:** unpinned — for the 6.6.20 integration to pin (lane c-pin filed it; roadmap edits
are integration's). SECURITY — needs a CVE id.
**Discovered:** 2026-10-06, 6.6.20 closeout fix batch, lane c-pin review round 1 (RS-04 sibling)
**Severity:** Medium (P2) — a toolchain verb executes repository-shipped code, the CBT-01 class;
the trigger is one rarely-run verb inside a hostile checkout, not every `cyrius` verb
**Affects:** the compiled `programs/cyriusly.cyr` (the Linux x86_64 tarball's `bin/cyriusly`),
since the verb was ported at v5.11.10. The shell twin `scripts/cyriusly` (the aarch64 and macOS
tarballs' `bin/cyriusly`) carries the verb itself and is not affected.

## Summary

`_cmd_cmdtools` delegates to the shell twin as `/bin/sh scripts/cyriusly cmdtools <action>
<tool>`, a path relative to the CURRENT directory. Run inside a cloned repository that ships
`scripts/cyriusly`, `cyriusly cmdtools` (any action, `list` included) executes that repository's
script with the user's privileges. A version manager's prompt-integration verb is not a verb that
runs repository code; a user has no reason to expect it.

6.6.20 (RS-04 review) already moved the operands to argv, so `cyriusly cmdtools 'list;cmd'` no
longer runs `cmd`. This issue is the other half: WHICH script runs.

## Reproduction

```sh
mkdir -p /tmp/hostile/scripts && cd /tmp/hostile
printf 'echo "PWNED from the checkout: $*"\n' > scripts/cyriusly
cyriusly cmdtools list
# PWNED from the checkout: cmdtools list        (rc 0)
```

Outside any directory holding `scripts/cyriusly` the verb simply fails (`sh: can't open
scripts/cyriusly`), so for an installed binary it currently works only inside a cyrius checkout.

## Root cause

`programs/cyriusly.cyr` `_cmd_cmdtools` pushes the literal `"scripts/cyriusly"`. The x86_64
store (`~/.cyrius/versions/<v>/`) ships `bin/cyriusly` as the ELF itself and no copy of the shell
twin: `[release].scripts` is `cyrius-repl.sh`, `cyrius-watch.sh`, `cyrius-prompt-info`, and
`versions/<v>/programs/` holds only `cyrius-init-templates`. So "resolve the twin from the
toolchain install" has nothing to resolve today.

## Fix options (the decision)

1. **Ship the twin into the store** (e.g. `versions/<v>/scripts/cyriusly`) from every writer —
   install.sh's refresh-only, tarball and source-bootstrap paths, the tarball builders, `cyrius
   pulsar`, and `verify-store.sh`'s slot comparison — and have `_cmd_cmdtools` run
   `<home>/versions/<current>/scripts/cyriusly` (or the twin beside its own `/proc/self/exe`),
   refusing by name when it is absent. Keeps the verb working everywhere, outside a checkout too.
2. **Port cmdtools natively** (the starship / p10k edits), dropping the delegation.
3. **Resolve relative to the running binary only** (`<exe dir>/../scripts/cyriusly`): no
   packaging change, works for a `build/cyriusly` in a checkout, refuses for the installed
   binary until option 1 lands — drops the verb for installed users run from a checkout.

Acceptance: `cyriusly cmdtools list` in a directory holding a hostile `scripts/cyriusly` does not
run it; `cyriusly cmdtools list` from an unrelated directory works (options 1 and 2) or refuses by
name (option 3). Gate: extend `tests/gates/toolchain/cyriusly_version_operand_refused.sh` axis 7
with the hostile-checkout row, and replace its "from this checkout" control.
