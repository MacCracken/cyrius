# Redeclaring a global makes an EARLIER read of it return 0 — and the "last definition wins" warning is false — FIXED

**Status:** ✅ FIXED in 6.6.6 (bite 2). A declaration-zone redeclaration now names ONE global and the
last definition wins for every read — the rule the warning always stated. See CHANGELOG [Unreleased]
(6.6.6) and the guide's *Global Initializers → Declaring a global twice*. Gates:
`tests/gates/frontend/global_redeclaration_one_definition.sh`, `tests/tcyr/crossos/global_redeclaration.tcyr`.
(Originally: 🟡 OPEN — pre-existing; found during 6.6.5 bite 9 while building init-order oracles for
cyrlint, confirmed by hand at 6.6.5 HEAD `2152df67`.)
**Placement:** 6.6.6 (the repair batch deferred from 6.6.5 — see `roadmap.md`). Not parked to 7.x.
**Discovered:** 2026-09-19.
**Severity:** Medium — SILENT. A clean compile (no diagnostic at all when the values match), and a
read that should see 5 sees 0.
**Affects:** cycc 6.6.5 HEAD (x86_64 Linux measured); the top-level `var` path in
`src/frontend/parse_decl.cyr` (`PARSE_VAR`'s global branch / global registration and static init).
Other forks unmeasured.

## Reproduction

```cyrius
var a = 5;
var b = a;
var a = 5;
syscall(60, b);
```

`cat r1.cyr | ./build/cycc > r1 && ./r1; echo $?` → **0** (want 5). No warning is printed.

Control — the same program without the redeclaration exits **5**.

With a DIFFERENT value on the redeclaration (`var a = 7;` on line 3) the compiler prints

```
warning:<source>:3:7: duplicate symbol 'a' redefined with conflicting value (last definition wins)
```

and the program still exits **0** — neither the first value (5) nor the "last definition" (7). The
warning describes a semantics the compiler does not implement.

## Root cause (not yet isolated)

Likely the redeclaration registers a SECOND global slot (or re-points the name) after `b`'s
initializer has already been bound, so `b = a` reads the new, not-yet-initialised slot; or the
static-fold of `b` is resolved against the later declaration. The 6.6.5 bite-4 work (aggregate
storage class) moved fn-local slots but did not touch top-level redeclaration.

## Proposed fix

Decide the rule and make the compiler and the diagnostic agree: either a same-scope redeclaration of a
global is a hard error (consistent with the language's "no `var` redecl in same scope" rule for locals),
or it genuinely means "last definition wins" and every earlier read sees the value it names. Silent 0 is
not an option under either rule.

Gate: the three shapes above with absolute expected exit codes, plus a same-value redeclaration after a
`#ifdef` arm (the realistic way two files end up declaring one global).

## Resolution (6.6.6, bite 2)

Reproduced on the 6.6.5-tree compiler (`7a6a8925`): the repro exits 0, the conflicting form exits 0
under the warning, the control exits 5. After the fix: 5, 7 (warning now true), 5.

The rule chosen — the guide was silent, and this is the reading that makes the existing warning true
and matches how a duplicate `fn` resolves: **before the first top-level statement, a redeclared
name is one global and the last definition wins for every read.** A constant redeclaration is the
global's value from program start (an earlier computed initializer still runs, for its side effects,
into a discarded sink); a computed redeclaration runs in declaration order; a redeclaration that
changes the type or size is an error. The hard-error option was not taken: same-name globals across
co-linked modules are an established, documented pattern (`lib/chrono.cyr`'s `CLOCK_MONOTONIC`, the
`SYS_*` override note in the guide), and a same-value `#ifdef` redeclaration must keep compiling.

## Corrections to this filing

- **"registers a SECOND global slot … after `b`'s initializer has already been bound, so `b = a`
  reads the new, not-yet-initialised slot"** — half right. It is a second slot, but nothing is
  bound early: every deferred initializer is replayed after the whole declaration zone is
  registered, so `b = a` reads the LAST slot. The defect is on the other side — the FIRST
  declaration's static-init value was baked into a slot no reference ever reads, and the second
  declaration (sent to the runtime-store path because it shadowed) stored after `b`'s initializer.
- **"or the static-fold of `b` is resolved against the later declaration"** — no: the static-init
  folder refuses identifiers, so `var b = a;` is never folded.
- **"Affects: … `PARSE_VAR`'s global branch"** — not that path. The declaration-zone path is
  `PARSE_GVAR_REG` (pass 1) + `EMIT_GVAR_INITS` (the replay). `PARSE_VAR`'s global branch handles a
  `var` after the first top-level statement, where a redeclaration is (and stays) a new variable for
  the code after it.
- **Wider than filed:** the same second slot also (a) left a chain's third link unwarned — it
  compared against 0 — and (b) in a kernel build, whose deferred initializers replay after the
  top-level program, let the replay re-resolve the name onto a later `var` of the same name and
  store into THAT slot — and READ from it: `var b = id(a);` read the program's later `var a`
  (the first cut of the fix covered only the store; the review found the read); and (c) a var
  over an ENUM constant with a CONFLICTING value (`enum E { K = 5; } var b = K; var K = 7;`) gave
  `b` the enum's 5 while a fn read 7, because the enum's startup store resolves the name
  last-match and runs before every deferred initializer.
  All three are fixed and gated (gate rows F, K/K2, L/M/N).
- ⚠ **Correction to the first cut of this fix (review, before release):** it claimed
  `enum E { K = 5; } var b = K; var K = 5;` "read 0 as well". It never did — it gives 5 at 6.6.5
  on x86, aarch64 and cx, for exactly the reason in (c): the enum store fills the var's slot first.
  That first cut made the var static without stopping the enum store, which then OVERWROTE the
  var (`var K = 7` read 5 everywhere, fn included). The enum store now targets only an enum
  constant's own slot (`PARSE_ENUM_DEF`).

