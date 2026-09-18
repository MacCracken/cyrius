# A private impl method is reachable by a FORWARD call (call parsed before its `impl` block)

**Status:** ✅ **FIXED in 6.6.5 (bite 3).** The filed repro
`repros/2026-09-13-private-impl-method-forward-call.cyr` is now REFUSED
(`error:<source>:<line of the `q.seven()` call>:57: 'Q_seven' is private to its file`), and so
is its control. ⚠ The LINE is deliberately not quoted here: an earlier draft of this block said
`:7:57`, which was the line before the repro grew its “FIXED in 6.6.5” header, and it will move
again the next time that header is edited. The SYMBOL and the column are the stable parts. Pass 1 stamps
every definition kind — impl methods (`_prescan_impl`), `mod` fns (the `GMOD == 0` guard is
gone), fns after the first top-level statement (`_prescan_tail`) and fns above the `private`
line (`_PRIV_PRESCAN` marks the file before either pass) — and is now the AUTHORITY on
visibility (`_fn_by_defti`), with a fail-closed deferral in `_vis_check` as the backstop under
it. See CHANGELOG [6.6.5] and `tests/gates/frontend/private_forward_reference.sh` +
`tests/tcyr/crossos/forward_ref_abi_binding.tcyr`.
⚠ **Read the "Corrections to this filing" section at the bottom before citing anything above
it** — the severity, the scope and the "cannot pack" reasoning were all wrong, and the way they
were wrong is the reusable lesson.
**Placement:** was unpinned (6.x-line backlog, visibility finish-out); landed in the 6.6.5
repair window.
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

---

## Corrections to this filing (written at the 6.6.5 fix)

Every one of these was found by investigating rather than by reading the filing, and each one
changed the size of the fix. They are recorded because the FILING'S SHAPE was the misleading
part, not its facts.

1. **"Impl methods are the one definition kind not stamped in pass 1" — WRONG.** Three more
   kinds were unstamped: `mod`-scoped fns (excluded by `_prescan_fn_sig`'s `GMOD == 0` guard),
   every fn after the first top-level statement (pass 1 stops there; `PARSE_PROG` keeps
   defining fns), and anything declared ABOVE the `private` line (the marker was recorded as
   pass 1 walked past it, so an earlier definition was prescanned while the file still read
   public). A global above the line was never private in EITHER order. Fixing only the impl
   skip would have left four reachable holes behind a closed one.

2. **"Severity: Medium … a shape normal include order never produces" — WRONG in three
   directions, and this is the important correction.** The same root produced, in ORDINARY
   include order: FALSE refusals (two private files with a same-named helper got
   `is private to its file` AND `expects 2 arguments, got 1`; the GUIDE'S OWN two-file
   `_helper` example was refused when the public file came first, with no forward call
   involved); GARBAGE diagnostics (`q.nosuch()` reported as `undefined function 'Q7_seven'`, a
   method that exists, because the method path registered an uncommitted scratch name); and
   SILENT SIGSEGVs (a forward call passing a >8-byte struct took the mask-0 ABI, on x86,
   aarch64 and PE). A forward `f<i32>(x)` also failed inside a SINGLE file. The filing scoped
   the bug to what its reporter had reproduced — which is what a filing is — so the severity
   line was an artifact of the report, not a property of the defect.

3. **"Not packable: a design decision on the name pool, with seed-derive exposure, across a
   7-fork obligation" — WRONG, and it was the load-bearing claim.** The pool question has a
   mechanical answer (`_mod_name_intern`: mint at `GNPOS` without committing, reuse the
   existing string when `FINDFN` + `STREQ` already has it, otherwise commit — pool growth
   unchanged, one mangler for both passes). The fork obligation is two one-line calls into
   shared code per fork. There is no heap/brk layout change (both new tables are lazily
   allocated), the fixpoint closes in ONE step, and seed-derive is GREEN. "It needs a design
   decision" deserves the same scrutiny as any other cannot-pack reason: the decision here
   took one function.

4. **"Option (b), a stopgap keyed on `GFFI == 0`, is narrower and needs no fork edit" —
   half-right, and shipped as a BACKSTOP rather than as the fix.** The filing correctly noted
   that a check on the fileid ALONE does nothing, because `_vis_check` returns at the flag
   test first. What it ships as is a DEFERRAL: an unstamped, unemitted callee is recorded with
   the caller's file and re-judged at the end of `PARSE_PROG`. That is fail-closed-later rather
   than fail-open, it produces no noise on legitimately-unknown callees (enum constructors, DCE
   stubs), and it is the layer that would catch a future definition kind pass 1 does not walk.
   It is NOT a substitute for stamping: with `_prescan_tail` disabled the deferral still
   refuses the forward call, but the program MISCOMPILES (the ABI comes from the masks, not
   from the visibility check).

5. **The proposed gate was "the repro + its control + a same-file forward call".** That would
   have passed on a compiler that refuses everything. The gate that shipped compares the
   FORWARD refusal set against the BACKWARD one per row — the expected value comes from a
   different path in the compiler — with a hard-coded symbol per row as an anti-vacuous floor,
   plus 8 legal programs (6 with exit codes computed in the shell from the fixture literals,
   5 of those by arithmetic) and 2 build-only controls. Two of the mutation predictions written
   during the premise check did not hold when measured; the gate header records what was
   measured instead — including, after review, an explicit note of the two changes it does
   NOT discriminate. ⚠ An earlier draft of this paragraph said "ten legal programs whose exit
   codes are computed by shell arithmetic"; both halves were looser than the axis.

6. **Found during this bite's triage, not in the filing, and fixed here:** `s.method(big)`
   SIGSEGV'd even in BACKWARD order (the method-call argument loop had no callee mask), and the
   v6.5.56 per-item `private` diagnostic printed TWICE and privatised the file anyway, so a
   legitimate sibling fn was reported private at its caller.

7. **And the first fix for that method-arg loop was itself incomplete — caught in review, not
   filed.** It added only `_fnt_structmask`. Two of PARSE_FNCALL's three callee masks were still
   missing, each a SILENT wrong value measured against the identical free fn: a string literal
   into a `: Str` param returned 0 for 5 (`_fnt_strmask`, no `str_from` wrap), and a vector
   argument followed by a scalar shifted every later argument by a register (`_fnt_simdmask`,
   927 for 923 — a vector as the ONLY argument worked by luck, which is how the shape stayed
   unnoticed). Both arms are now shared code lifted out of PARSE_FNCALL. Writing the test for
   the first of them exposed a FIFTH defect: `return f("lit")` is a different lowering that
   never ran the wrap either, so the free-fn CONTROL the method was compared against was itself
   wrong. See CHANGELOG [6.6.5].

8. **And the fix for THAT was itself incomplete, twice more — caught in review round 2.** Three
   further defects in the same family, none of them in the filing:
   * the `: Str` tail-call divert added in correction 7 was armed by a literal at ANY paren
     depth, so `return deep(n - 1, str_from("abc"))` — whose literal is already wrapped — lost
     its TAIL CALL and a program that ran on 6.6.4 SIGSEGV'd at depth 200,000. The comment
     justifying it asserted that "over-diverting costs a tail call" and that a depth-1 rule
     "can only under-cover"; both were measurably false. Depth 1 is PARSE_FNCALL's own
     criterion (`_try_push_str_literal_arg` wraps only an argument's FIRST token), so it cannot
     under-cover.
   * the marshalling loop count was wrong in the same way correction 1's definition-kind count
     was. It is not three paths but SEVEN argument loops: PARSE_FNCALL, the method path, the
     tail path, and FOUR Win64 hidden-retptr vector receives. Those four still ran one gate,
     so the `: Str` defect was still live **on PE only** — measured under wine, the same source
     gave 5 on ELF and 0 on PE.
   * the method path had no `_CHECK_ARITY` and no `_fnt_cstrmask` check either: `q.one(5, 99)`
     built and returned 6, and `w.pr(42)` into a `: cstring` param built and SIGSEGV'd, where
     both identical free calls are hard errors.
   ⭐ The durable answer is not another row: it is
   `tests/gates/frontend/method_call_runs_every_callee_gate.sh`, a DIFFERENTIAL against the
   identical free fn plus a derived check on the loop's own source, so the next forgotten gate
   fails without anyone editing the gate. Three rounds of "one more mask" is what a list gets
   you.

9. **One defect found while verifying correction 7 was NOT packed, and the reason is named:**
   a value-form SIMD argument alongside SIX or more int-class arguments miscompiles on every
   call path — identical on 6.6.4 and 6.6.5, so pre-existing and unmoved. Filed as
   `docs/development/issues/2026-09-17-simd-arg-with-six-or-more-int-args-miscompiles.md` with
   a verbatim repro and acceptance criteria. The reason it is not here: the fix is a change to
   the value-form SIMD calling convention past the integer register ceiling, which is a
   different convention on each of the four gate targets, and its failure mode is another
   silent wrong value — it needs its own bisect and a real-hardware run, inside a release whose
   compiler changes are otherwise proven byte-clean across 317 `.tcyr` and 117 programs.
