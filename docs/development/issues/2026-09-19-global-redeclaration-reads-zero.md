# Redeclaring a global makes an EARLIER read of it return 0 — and the "last definition wins" warning is false — OPEN

**Status:** 🟡 **OPEN** — pre-existing; found during 6.6.5 bite 9 (the implementer, while building
init-order oracles for cyrlint) and confirmed by hand at 6.6.5 HEAD `2152df67`.
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
