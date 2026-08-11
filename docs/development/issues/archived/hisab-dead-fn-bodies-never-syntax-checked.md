# A syntax error inside an uncalled function is accepted by every gate — ✅ FIXED (compiler); lint still open

> ⚠ **RE-MEASURED 2026-08-10 on 6.5.17 by the original reporter — PARTIALLY FIXED, not fully.**
> `cyrius build` and `cyrius check --with-deps` now both reject the repro (exit 1), which is the
> load-bearing half: a file that does not parse can no longer be built or shipped. But **`cyrius lint`
> and `cyrius vet` still exit 0** on it, so the release note's "accepted by every gate" is not yet
> fully discharged. `lint` is the sharper of the two — analysing code that never runs is much of what
> a linter is for. Not reopening: if lint/vet deliberately skip a full parse, saying so closes this.
>
> | gate | 6.5.16 | 6.5.17 |
> |---|---|---|
> | `build` | exit 0 | **exit 1** ✅ |
> | `check --with-deps` | exit 0 | **exit 1** ✅ |
> | `lint` | exit 0 | exit 0 ❌ |
> | `vet` | exit 0 | exit 0 ❌ |


**Status:** ✅ **FIXED** (6.5.17) for `build` / `check`. ⚠ `cyrius lint` is NOT fixed —
see the residual below.

**Resolution.** The skip was not a privacy heuristic, it was a name-mangling bail-out.
`PARSE_FN_DEF` builds a module-scoped name as `mod` + `_` + `fn`, so a mangled
definition and its call sites intern DIFFERENT strings and the offset-keyed reference
bitmap would wrongly call the definition unreferenced; the guard treated **any** name
containing `_` as possibly-mangled. Ordinary snake_case then covered nearly all real
code, which is how it survived — and for names without an underscore the answer came
down to whether some unrelated file happened to use that word as a local (`fn n(x)`
was checked because `lib/string.cyr` has a local `n`; `fn name(x)` was not). It was
also fork-divergent: present in `main.cyr` / `main_win.cyr` / `main_x86_macho.cyr` /
`main_cx.cyr`, absent from all three aarch64 drivers.

Measured blast radius (injection oracle, not grep): 9 unchecked fns in cycc's own TU,
**28 of 56** underscore-free names in a realistic 25-module stdlib set — `atoi`,
`getenv`, `print`, `strstr`, `unwrap`, `memchr`, the `x*` family. `unwrap` and
`eprint` had never been syntax-checked by any translation unit in the project.

v6.5.17 removes the parse-time skip and its 8 KB reference-bitmap pre-scan from all
four x86-family drivers. Reachability is a codegen concern: `CYRIUS_DCE=1` acts on the
compiled result. cycc got smaller, not larger (1,146,200 → 1,142,016 B).

Gate: `tests/gates/frontend/dead_fn_body_syntax_checked.sh` — judged on the compiler's
EXIT CODE across six name shapes, with an anti-vacuous axis. Mutation-proven: restoring
the skip reproduces the filed truth table exactly.

⚠ **RESIDUAL — `cyrius lint` still reports `0 warnings` on a file that does not parse.**
The filing calls this the sharp edge and it is correct: cyrlint never runs a full parse,
so the compiler fix does not reach it. That is a cyrlint change, tracked separately.

---

**Original filing follows.**

**Status:** 🔴 OPEN — `build`, `lint`, `vet` and `check` all report green on a file that does not parse, when the offending function is uncalled and its name contains no underscore.
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
