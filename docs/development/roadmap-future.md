# Cyrius Future Work — Beyond Current Minor

**Scope** — Items that aren't pinned to the current cycle but are
known long-term work: v7.0+ aspirations, unpinned language
refinements waiting on consumer pressure, speculative type-system
extensions, and the public-release manuscript pin. Items here may
get pulled forward into a v6.x minor when consumer pressure
materializes; the placement is "watching" not "deferred".

See [roadmap.md](roadmap.md) for current v6.x cycle work.

---

## TS/TSX → JS emit — frontend builder (consumer-filed, minor TBD)

SecureYeoman's `yeo-cy-test` port probe (2026-05-27) confirmed the
Cyrius TS/TSX front-end **parses** real-world TS/TSX cleanly
(interfaces, `<K extends string, V>` generics + default type params,
`?.`/`??`, async/await, enums, `readonly`/optional members,
destructuring, spread, tuples, `Record<K,V>`, a full React component
with `useState`/`useEffect`/JSX) — but has **no emit**. `--lex-ts` /
`--parse-ts` validate only; the P3–P5 lowering from the old v5.7.2 TS
plan never shipped. So Cyrius can be the build-time *validator* of a TS
frontend but not its *builder*; the consumer hand-maintains a parallel
`web/app.js` as the production stopgap.

**Ask**: a `cycc --emit-js <file.tsx>` (or `cyrius build --target=js`)
codegen stage walking the existing AST — strip type annotations /
interfaces / type aliases, lower JSX → `createElement`-style calls
(configurable pragma), pass ESM through. Single-file emit only; a
bundler is explicitly out of scope. The expensive part (a correct,
full-fidelity TS/TSX parser) already exists — this is codegen on top.

**Status**: consumer-filed with active pressure, but **minor TBD** per
user direction 2026-05-27 ("arc TBD"). Larger than the three TS
scripting papercuts the same filing surfaced (those are near-term
v6.0.x bug-bandwidth — see [roadmap.md](roadmap.md)). Notable framing:
this is a *non-machine-code output target* for an assembly-up compiler,
so its home minor is a deliberate open decision rather than an obvious
v6.3.x language-refinements fit. Issue:
[`issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`](issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md);
full write-up in `secureyeoman/yeo-cy-test/FINDINGS.md`.

---

## Unpinned language refinements

These were tracked through v5.x as known asks but explicitly held
unpinned at v5.8.65 close (2026-05-05) — consumer pressure either
didn't materialize or workarounds proved sufficient. Re-evaluate
at each cycle-open per [`feedback_premise_check_at_slot_entry`].

| Feature | Effort | Status / Notes |
|---|---|---|
| **Hardware 128-bit div-mod** | Medium | Stays unpinned. abaco / sigil work around via u128 shifts; not blocking. Pull forward if a real perf regression surfaces. |
| **Phase 3-full varargs** (`va_arg` for structs-by-value + nested) | Medium | Phase 3-min shipped v5.5.36. Stays unpinned — niche. Most consumers use array-of-args pattern instead. |
| **cycc per-block scoping** | Medium | Stays unpinned. Function-scope works for current consumer base; promote when a real refactor surfaces the pain point. |
| **Incremental compilation** | High | Stays unpinned. Whole-program self-host is fast (<400 ms at v6.0.0). Incremental adds complexity for cyrius-style projects without proportional payoff. Reconsider when cycc self-host time crosses ~2 sec. |

---

## Speculative type-system work

Long-horizon items that go beyond the v6.3.x Language Refinements
arc (closures + monomorphization + async sugar). Not pinned to any
minor; floats in the watching list until a specific consumer ask
or design driver materializes.

- **Polymorphic items beyond monomorphization** — trait-bounded
  generics, higher-kinded types, GATs (generic associated types),
  or whatever shape post-monomorphization generic work needs once
  v6.3.x ships and consumers start hitting the next ceiling.
  Concrete asks land here when they surface.
- **Effect tracking beyond `@unsafe`** — v5.8.x shipped `@unsafe`
  as the first effect annotation. Lift-to-more-effects (e.g.
  `@io`, `@alloc`, `@panic`) only if a real consumer enforcement
  scenario emerges.

---

## ~v7.0 — Public release ("Cyrius ONE")

The first book on Cyrius, written from Vidya + first-party
documentation, published alongside the public release (Amazon /
Packt or similar). Held back from v6.0.0 so the language surface
is stable before the manuscript lands. Exact version TBD; lands
with whatever version the public release cuts on (current guess:
v7).

**Why the version is uncertain**: depends on how much language
work earns its way into v6.x (closures + generics + async are
pinned to v6.3.x; further refinements may flow from v6.x consumer
filings). The manuscript fixes a "stable point" — when the
language stops accumulating substantial new surface, the book
becomes writeable.

---

## v7.0 commitments (NOT items — invariants)

Two known commitments per CLAUDE.md "Version lives in `VERSION` +
`--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
- **build/cc3 drops at v7.0.0** per the prior-major-seed
  retirement policy (cc3 stays through v6.x as the v5.0.0-era
  historical anchor; retires at v6.x → v7.x bump).

---

## How items move from here into a cycle

An item earns a v6.x slot when:
1. A consumer files a specific need (per
   `docs/development/issues/`) that the item closes.
2. Cycle bandwidth opens during a minor's absorber band.
3. User direction explicitly pulls it forward at slot entry.

When pulled forward: edit `roadmap.md` to add the item to the
target minor; remove from `roadmap-future.md`. The reverse path
(de-pinning a roadmap item back to "watching") is rare but
happens when premise-check at slot entry shows the work isn't
ready or consumer need evaporated.

---

## Retired references

- **roadmap-old.md** (1,249 lines, deleted v6.0.x) — contained the
  v5.x long-term considerations + v5.12.x retired-spec archive +
  v5.x platform-shipping table + pre-pinned v6.x narrative.
  Resolved pins moved to `roadmap.md`; unpinned items moved here;
  durable principles consolidated into `cycle-discipline.md`;
  ecosystem/platform snapshots moved to their canonical docs
  (`docs/ecosystem.md`, `docs/platform-status.md`); pre-v5.11.x
  retrospective material lives in `completed-phases.md`.
- **roadmap-last.md** (272 lines, deleted v6.0.x) — frozen v5.11.x
  in-flight roadmap. Fully duplicated CHANGELOG + new `roadmap.md`
  + memory pins by v6.0.0 cycle-open.
