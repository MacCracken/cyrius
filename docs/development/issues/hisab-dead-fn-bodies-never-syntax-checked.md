# A syntax error inside an uncalled function is accepted by every gate — OPEN

**Status:** 🔴 **OPEN** — `build`, `lint`, `vet` and `check` all report green on a file that does not parse, when the offending function is uncalled and its name contains no underscore.
**Placement:** unpinned — 6.5.x line. No consumer is blocked, but it silently removes a whole category of source from checking.
**Discovered:** 2026-08-09 while re-verifying hisab's tracked toolchain filings at the 6.5.16 bump (hisab v2.9.2)
**Severity:** **Medium** — no miscompilation; the defect is that unreachable code is never checked and nothing says so. `cyrius lint` reporting "0 warnings" on a file that does not parse is the sharp edge.
**Affects:** cycc **6.5.16** (confirmed). Not bisected against earlier pins — the skip may be long-standing.

## Summary

A function that nothing calls, and whose name contains **no underscore**, has its body skipped
entirely. Arbitrary garbage inside it compiles green and every quality gate agrees.

Both conditions are required, and the second is the surprising one: the behaviour is keyed on a
character in the identifier. That is almost certainly not the intended rule, which is the reason
this is filed rather than shrugged at as "dead code is not compiled".

## Reproduction

```
# src/g.cyr — gg is never called
fn gg() { var x = ; this is not cyrius at all ]] ((
    return 0; }
fn main() { return 0; }
var r = main();
sys_exit_group(r);
```

with `[deps] stdlib = ["syscalls"]`. Measured on 6.5.16:

```
cyrius build src/g.cyr build/g              exit=0   OK
cyrius lint src/g.cyr                       exit=0   0 warnings
cyrius vet src/g.cyr                        exit=0
cyrius check --with-deps src/g.cyr          exit=0
```

Rename `gg` → `g_g`, changing nothing else, and the same file is rejected:

```
cyrius build src/g.cyr build/g              exit=1   error:<source>:3:20:
cyrius check --with-deps src/g.cyr          exit=1   error:<source>:3:20:
cyrius lint src/g.cyr                       exit=0   0 warnings      <- lint misses it either way
```

Call `gg` from `main` and the error is reported normally (exit 1), so it is the combination
*uncalled* **and** *no underscore*. Holding everything else fixed across six names:

| name | has `_` | `cyrius build` |
|---|---|---|
| `gg` | no | **exit 0** |
| `victim` | no | **exit 0** |
| `abcdefghij` | no | **exit 0** |
| `broken_fn` | yes | exit 1 |
| `victim_x` | yes | exit 1 |
| `abcde_ghij` | yes | exit 1 |

A repro source is at `repros/2026-08-09-dead-fn-body-not-parsed.cyr`.

## Root cause

Not established — this is a consumer-side report and the skip is in territory I have not read.
`CYRIUS_DCE_VERBOSE=1` lists **both** variants as `dead:`, but the no-underscore one contributes
0 bytes to the emitted size while the underscore one contributes its body, which suggests the two
take different paths through whatever decides that a body need not be parsed. **Flagging that as
speculation** — the Cyrius side will know where to look.

## Proposed fix

Parse every function body regardless of reachability, and let dead-code elimination act on the
compiled result — reachability is a codegen concern, not a parsing one. If skipping is retained for
compile speed, it must not be keyed on the identifier's spelling, and `cyrius lint` should always do
a full parse regardless: analysing code that does not run is a large part of what a linter is for.

## Consumer-side workaround (if any)

None needed, and none available — a consumer cannot detect this from outside. hisab's exposure is
**3 of 842** distinct `fn` names in `src/` without an underscore (`main`, `einsum`, `minkowski`),
all three of which are called and asserted in `tests/abuse.tcyr`, so nothing is currently hiding.
That protection is an accident of naming convention, not a decision, and it is recorded as such at
`hisab/docs/development/issues/2026-08-09-cyrius-dead-fn-bodies-are-never-syntax-checked.md`.

## Note for whoever reproduces this

Diagnostic line numbers for the file named on the command line are offset by
(stdlib dep count + 1) — they index the concatenated translation unit, which is why an error on
line 1 reports as `<source>:3`. Errors inside `include`d files carry the true filename and line.
Unrelated to this defect, but it will confuse the repro.
