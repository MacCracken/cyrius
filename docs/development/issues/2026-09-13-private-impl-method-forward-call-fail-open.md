# A private impl method is reachable by a FORWARD call (call parsed before its `impl` block) — OPEN

**Status:** 🟡 **OPEN** — found during the v6.6.4 repair of
`2026-09-13-hisab-private-fn-reachable-via-address-of.md` (archived) and deliberately NOT
packed into it: the fix is a pass-1 change in all seven compiler forks, not a missing check.
Repro `repros/2026-09-13-private-impl-method-forward-call.cyr` **proves itself** (exit 42 while
present; the build is refused when fixed). Its control — the same call with the include ABOVE
`main` — is refused today, so the check exists and fails **open** on this ordering only.
**Placement:** unpinned — 6.x-line backlog (visibility finish-out).
**Discovered:** 2026-09-13, by the adversarial verifier of the `&fn` repair while enumerating
every path that resolves a fn.
**Severity:** Medium — the boundary is bypassable, but only for impl methods and only when the
caller precedes the impl in the concatenated stream (a shape normal include order never
produces); a direct forward call `Q_seven(&q)` is the same hole.
**Affects:** cycc 6.5.0 → 6.6.4 (every release with `private`).

## Summary

`_vis_check` (`src/frontend/parse_fn.cyr`) tests the callee's private FLAG first
(`(GFLG & 64) == 0 → return 0`) and its fileid second, and is fail-open on both by the v6.5.0
design ("fileid 0 means unrecorded … Phase 3 must revisit this"). Plain fns are stamped in
pass 1 by `_prescan_fn_sig`, so a forward call to a private plain fn resolves with flag +
owner known and is refused. Impl methods are the one definition kind **not stamped in pass
1**: the pass-1 declaration scan in `src/main.cyr:~1494` (and its six fork twins —
`main_aarch64`, `main_aarch64_macho`, `main_aarch64_native`, `main_win`, `main_x86_macho`,
`main_cx`) brace-skips `impl` bodies ("functions registered in pass 2"). A method call that
lexically precedes the impl block therefore REGISTERS `Q_seven` from the call site (`REGFN`
writes name/offset/params only — no flag, no fileid) and emits the call; the check returns
at its first test. The same call after the impl block is refused, because `PARSE_FN_DEF`
has stamped the flag by then.

```cyrius
# main.cyr                                        # lib_priv_impl.cyr
fn main() { var q: Q; …; return q.seven(); }      private
include "lib_priv_impl.cyr"                       impl Tr for Q { fn seven(self) { return 42; } }
# → builds, exit 42 (should be refused)
```

## Root cause

`src/main.cyr:~1494` (pass-1 `impl` skip, token 77) and the six fork twins. Methods never
reach `_prescan_fn_sig` in pass 1 at all — the brace-skip precedes it. (`_prescan_fn_sig`'s
own `GMOD == 0` guard is about `mod`-scoped fns, unused in-tree; the name-pool mutation it
avoids is `PARSE_FN_DEF`'s `mmod != 0` mangling, which advances `SNPOS`.) So stamping methods
in pass 1 means a pass-1 scan of each impl body that interns `Type_method` once, in a way
pass 2's mangling then reuses rather than re-mints.

## Why it was not packed into 6.6.4

The eight `&fn`/method/receive sites were **missing calls** to an existing predicate — one
line each, shared frontend, no fork edit. This is a different mechanism: **unstamped
definitions**. Closing it means registering mangled method names with their fileid + private
flag in pass 1 across all seven forks (the parity gate `directive_fork_parity.sh` shows what a
7-fork obligation costs when one fork is missed), and deciding how the pass-1 mangle
coexists with pass 2's — a design decision on the name pool, with seed-derive exposure. That
is the "cannot pack" reason CLAUDE.md names, and it is written here rather than left as prose.

## Proposed fix

Either (a) pass 1 scans each `impl` body for `fn NAME` and pre-registers `Type_NAME` with
fileid + flag 64 (all seven forks; the pass-2 mangling must then reuse that entry), or (b)
`_vis_check` fails **closed** when BOTH the flag and the fileid are unrecorded on a name that
resolves to a known struct's `Type_` prefix (registered from a call site only) — narrower,
no fork edit, but it turns an unrecorded impl method into an error even in the SAME file when
forward-called, which needs the same-file exemption to be derivable without the fileid. ⚠ A
stopgap keyed on `GFFI == 0` ALONE does nothing: the check never reaches the fileid test for
this repro. (a) is the honest fix; (b) is a stopgap.

Gate: the repro (must be refused) + its control (must stay refused) + a same-file forward
call to a private method (must build).

## Consumer-side workaround

Include the library before the code that calls into it — the normal order. hisab's
public-surface gate generates direct calls after the include, so it is unaffected.
