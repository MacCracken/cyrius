# Cyrius Development Roadmap — v6.7.x (active minor)

**Scope** — the **current active minor only** (v6.7.x, the LANGUAGE minor). This is the slot-pinning
working artifact: the release sequence, the spec of each arc, the stdlib impact of each feature, and the
unscheduled 6.x backlog (frozen until the first catch-up break — see the operating rule). The DCE compaction
arc, the net migration, v6.8.x/v6.9.x RISC-V and whole-cycle framing live in [roadmap_6.md](roadmap_6.md);
the unpinned watching list is [roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slots) → [roadmap_6.md](roadmap_6.md)
> (after v6.7.x, and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

> ⚠ **Rotated 2026-10-07 at the v6.7.0 open.** The v6.6.x slots are shipped and gone from this file
> (CHANGELOG per release; [completed-phases.md](completed-phases.md) § *v6.6.x*). The v6.7.x spec MOVED here
> from roadmap_6.md, which keeps a pointer — one authority per active minor. **Do not re-add shipped slots
> here.**

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: the DCE compaction arc and the net
  migration (between v6.7.x and RISC-V), v6.8.x/v6.9.x RISC-V rv64, cycle budgeting, and what follows v6.x.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit unpin conditions.
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable closeout
  checklist + per-closeout ledger**.
- [state.md](state.md) — volatile current state, refreshed by hand every release.
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the CHANGELOG
  disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.7.1** (2026-10-07) — **C3 landed: trait-bounded generics** (6.7.0 shipped: tag `6.7.0` @ `64b7a523`)
· cycc **1,631,440 B** (`.text` **1,449,624**) · `cycc-native-aarch64` **1,393,448 B** · **514** `.tcyr` (**223** in
`crossos/`) · **106** `lib/*.cyr` · **417** shell gates under `tests/gates/<bucket>/` · api-surface **5,827** · **4 open
issues** · **2 open proposals** · the next free CVE id is **103**.

> ⚠ **Every figure above was DERIVED on the day, not carried** (2026-10-07 at the 6.7.0 open).
> `version-bump.sh` rewrites the version token, replaces the `(…)` after it with the bump date, and
> nothing else — **the numbers beside it are yours to re-derive.** Keep the stamp at the start of its
> line and its parenthetical free of nested `(`/`)`, or the bump refuses to rewrite it (and
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red the day it is written). Re-derive gates with `find tests/gates -name '*.sh' | wc -l`; never increment.

**v6.6.x is closed** (6.6.0–6.6.20; the closeout shipped 2026-10-07, CVE-79 … CVE-102). One line per release is
in [completed-phases.md](completed-phases.md) § *v6.6.x*; the detail is the CHANGELOG.

---

## The v6.7.x operating rule (user, 2026-10-07)

1. **Language only until the majority of the minor's features have landed.** The releases between the open
   and the first catch-up break carry language features (arcs A, B, C below) and nothing else — no backlog
   work, no found-issue repair, no tooling arcs. *The `cyrius --help` cleanup and the CI refresh in 6.7.0
   were asked for with the open; they are the only non-language items before the first break.*
2. **What a feature release finds is FILED, not fixed** — to *Potential backlog* below, with a repro, in the
   same turn. The only in-release fix is a genuine prerequisite of the feature in hand (a bug the feature
   cannot ship around — CLAUDE.md's prereq-bug case). A P0 security finding is reported to the user the turn
   it is found; whether it interrupts the arc is the user's call.
3. **Catch-up breaks** clear the backlog and found issues. **Proposed placement (the user adjusts):**
   - **Break 1 — after arcs A and C3 and the majority of B** (roughly: traits, trait-bounded generics, and
     `const` / `bool` / if-expression / `loop` + `do` / field compound assignment). One or two releases. The
     user picks which backlog items it takes; the `cyrius test` / `tests` consolidation (below) lands here.
   - **Break 2 — before the closeout**, after the remaining features. One or two releases, then the closeout.
4. **Every language decision is the user's** (CLAUDE.md *Execution integrity*). Each arc below lists its
   decisions: the taken ones with the date, the open ones as questions asked at that arc's start — never a
   lane's "default".
5. **Every new syntax ships with** a `tests/tcyr/crossos/` file (it runs on ecb / ach / cass / pi), a guide
   section and a vidya entry.

---

## Release sequence (planned at the open, 2026-10-07)

| Release | Content |
|---|---|
| **6.7.0** | **A — real traits** (A1–A6, decisions below; A1–A5 landed 2026-10-07 — [ADR-007](../adr/007-traits.md)) · the CI refresh: every Linux job on **`ubuntu-26.04`** (the `-arm` job on `ubuntu-26.04-arm`) and every action at its latest stable release, SHA-pinned (checkout v7, upload-artifact v7, download-artifact v8, action-gh-release v3) · **`cyrius --help` reorganised** (commands grouped by what they do; nothing renamed or removed) |
| **6.7.1** | **C3 — trait-bounded generics** (needs A), with its prerequisite the multi-type-param struct-type-arg residual and the generic-struct field — decisions taken at the open (spec below); ✅ landed 2026-10-07 |
| **6.7.2 →** | the next of "then, by size" below — the user picks |
| then, by size | **B1 `const` + C1 `const fn`** together · B2 `bool` / `true` / `false` · B3 the if-expression · B5 `loop` / `do … while` · B8 compound assignment on a field |
| **Break 1** | catch-up: backlog + found issues (user picks) · `cyrius test` / `tests` consolidation · **cybs stack arguments** (below) |
| then | B4 tuples · B6 default + named arguments · B7 narrow struct fields (ABI survey + migration) · C2 bounds-checked mode (+ P5 execution coverage) · **checked `dyn`** (decided 2026-10-07, open question 5) |
| **Break 2** | catch-up |
| **closeout** | the closeout checklist ([cycle-discipline.md](cycle-discipline.md)) — the checklist, not an audit campaign (CLAUDE.md) |

Each arc is one or two releases with its phases as bites (CLAUDE.md *Release & Slot Discipline* rule 2). Expect a
large minor.

---

## Spec — A: real traits (6.7.0)

The identity rule carries over: **no GC, no hidden control flow you cannot disassemble.** Still not imported
(decided 2026-07-07): borrow-checker lifetimes, a general const-eval VM, exceptions of any kind.

**Premise re-measured 2026-10-07 at the open** (`build/cycc` 6.7.0):

| Shape | cycc 6.7.0 |
|---|---|
| `trait Show { … }` | No such keyword: a parse error. |
| `impl Show for Point { fn sum(self) … }`, then `p.sum()` | Works; the method is `Point_sum` (ADR-004 naming). |
| `impl NoSuchTrait for Point { … }` | Compiles — `PARSE_IMPL` skips the trait name unread. |
| Two traits each give `Point` a `size` method | Both become `Point_size`; duplicate-fn warning; since 6.6.20 the LAST definition binds. |
| `impl Point { … }` (no trait) | `expected for` |
| `b.m()` on an 8-byte struct `B1 { v }` with `fn m(self) { return load64(self); }` | 7 — `self = &b`. |
| `B1_m(b)` — the same method called directly | **SIGSEGV**: the value 7 is passed as `self` (`o.m()` and `T_m(o)` disagree). |
| `var q: B1 = p;` with `p: *B1` (8 B) | `q.v` reads garbage — the pointer VALUE is stored. |
| `var n: N2 = h;` with `h: *N2` (16 B) | COPIES (`n.v = 5` leaves `h.v`). ⚠ The 6.6.20 backlog note said it binds — re-measured, it copies. |

1. **`trait` declarations, checked.** `trait Show { fn show(self): i64; }` declares a method set, and
   `impl Show for T` is checked against it: a missing method, an extra one, a wrong arity or an undeclared
   trait is a compile error naming the trait. A method with a body in the trait is a **default**,
   instantiated into every impl that does not supply its own.
2. **Trait-qualified names — DECIDED 2026-10-07 (user): the mangled `T_Trait_m`.** Every trait method is
   also defined as `Point_Show_size` (ADR-004's planned naming); calling it directly is how a collision is
   chosen. No new call syntax. `Point_size` keeps resolving whenever only one trait (or an inherent impl)
   provides `size`; only a real collision changes — `p.size()` becomes an ambiguity error naming both traits
   and both qualified names.
3. **Inherent `impl T { … }`**: methods with no trait.
4. **`self` typed by its impl.** An untyped `self` inside `impl … for T` becomes `self: *T` — still the
   receiver's ADDRESS, so every `load64(self)` body keeps working, and `self.x` reads through it like a
   `pp: *Pt` parameter. ⚠ NOT `self: T` (an 8-byte-or-less struct is passed BY VALUE since 6.6.11 and every
   small-struct `load64(self)` would break — `tests/tcyr/crossos/method_self_inline_struct.tcyr`'s `P1`).
   With `self: *T`, 6.6.20's rule that a bare struct passed to a `*T` parameter passes its address makes
   `T_m(o)` agree with `o.m()` (the SIGSEGV row above, BACKLOG-13).
   - **`Struct = *Struct` — DECIDED 2026-10-07 (user): COPY, at both sizes.** `var q: T = p;` with `p: *T`
     gives `q` its own copy of `*p` whatever `sizeof(T)`; this fixes the ≤ 8 B garbage read and keeps the
     > 8 B behaviour measured above. Aliasing stays explicit: `var q: *T = p;` (BACKLOG-06).
5. **Methods on nested fields and chains**: `b.v.sum()`, `mk(3).v.sum()` — and the result type of a method
   call on an 8-byte struct (`var u = s.clone(); u.len()` fails for a one-field struct while 16/24-byte
   ones infer; BACKLOG-07).
6. **Dispatch stays static (ADR-004)** in 6.7.0. Whether 6.7.x adds compiler-checked trait objects is open
   question 5 below — A is built the same either way (it is the prerequisite of both).

**At the open, before code:** an ADR for traits (ADR-007, amending ADR-004's naming section) and the vidya
entries; the keyword survey is done (below).

## Spec — C3: trait-bounded generics (6.7.1) — ✅ LANDED 2026-10-07 (CHANGELOG [6.7.1]; ADR-007 decision 8)

`<T: Show>` parses as a bound (before 6.7.1 it minted a second type parameter named `Show`, so `f(p)` with a struct
was refused as "a struct beside a second type argument"), and an instantiation whose `T` has no `impl Show` is an
error. ⚠ First fix the **multi-type-param struct-type-arg residual**: a struct type argument works only on a
one-parameter generic, and `g<Pt, i64>` is refused. **And a generic-struct FIELD** (BACKLOG-13): `struct H { a: i64;
b: Box<i32>; }` is `expected identifier, got '<'`, and `#derive` on a struct with a `Vec<Box<i64>>` field stops its
field walk at the nested `<` (re-measured 6.7.1: `#derive(accessors)` never defines the fields after it).

**Decisions (user, 2026-10-07, at the 6.7.1 open):**
- **A bound is a CONTRACT.** On a bounded `T`, `v.m()` must be a method of the bound's trait(s) — an error at the
  generic's DEFINITION otherwise — and the bound picks that trait's `m` when `T` has a colliding one (as `self.m()`
  does inside an impl, ADR-007). Fields are not part of a trait and still resolve per instance. An UNBOUNDED `T`
  keeps per-instance resolution (`fn f<T>(v: T) { return v.show(); }` compiles today and keeps compiling).
- **Several bounds: `<T: Show + Eq>`** requires every impl; the same syntax bounds a generic struct's parameter
  (`struct Box<T: Show>`).
- A bound is satisfied by `impl Trait for X` whatever X is — a struct or a scalar (`impl Show for i64` defines
  `i64_show` today).

## Spec — B: the missing common features

⚠ Every new keyword is a new reserved word (`IS_KEYWORD_TOK`). The ONE survey is done (2026-10-07, below).

1. **`const` declarations.** `const LIMIT = 7;` is a compile-time value with no storage, folded like an enum
   constant; lands with C1 so a `const` can be initialised by a `const fn`.
2. **`true`, `false`** (and `bool` as a real type for intent, typechecks and `#derive` — ⚠ `bool` ALREADY
   parses as an 8-byte type name: `sizeof(bool) == 8`, `var a: bool[3]` in three tcyr files). 0 and 1
   underneath (ADR-002 keeps i64 the core).
3. **A conditional expression.** ⚠ C's `c ? a : b` collides with the postfix `?` that propagates a `Result`
   (v5.8.29). Proposed: an if-expression (`var v = if (c) { a } else { b };`) — **asked at B3's start.**
4. **Tuples as values.** `var t = (1, 2); t.0` — proposed as sugar over an anonymous struct (layout and ABI
   unchanged; multi-return keeps its register pair) — asked at B4's start.
5. **`loop { … }` and `do { … } while (c);`.** A `continue` in a `do … while` goes to the condition. ⚠ `loop`
   is the ONE keyword with real collisions (survey below) — whether it is a full reserved word (rename 224
   sites in 10 repos) or contextual (a keyword only when `{` follows) is **asked at B5's start.**
6. **Default and named arguments.** `fn f(a, b = 2)` and `f(a: 1, b: 2)`; the v6.5.1 arity check becomes
   min..max. Overloading by arity stays out (v6.5.1's rule that a count mismatch is never intentional).
7. **Narrow unsigned and `f32` struct fields.** Today `u8` / `u16` / `u32` / `f32` fields take a full word;
   narrowing changes the LAYOUT of every struct that declares one — an ABI change. Ships with the migration,
   never silently.
8. **Compound assignment on a field** (BACKLOG-13). `h.n += 4` is `expected '=', got '+'` for a struct local
   and a field alike; every compound operator on every lvalue form (field, chain, `p.f` through a pointer, a
   subscript), with `*=` / `/=` on f64 fields following the 6.6.11 float rules.

## Spec — C1 / C2

1. **`const fn`** ([`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)).
   Option 1 `const fn` primary, option 3 `#phf` fallback, option 4 (a general const-eval VM) declined
   (2026-07-07). Its base is the parse-time folder `_CF_TRY`, NOT `ir_const_fold` (an x86-ELF peephole under
   opt-in `CYRIUS_IR=3`); "a computed initializer is folded" is false today (a deferred runtime store). Size
   ~800–1,500 src lines, 1–2 releases, after B1 and B3.
2. **Opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`), OFF by default. 6.6.12 shipped the
   unchecked half for integer-element `var a: T[N]`; still to do: `*T` pointer subscripts, slice writes, and
   the checked mode itself. **With it, proposal P5's execution half** ([`proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md`](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md);
   A shipped 6.6.17) — it shares C2's insertion point and build-flag plumbing.

## Bootstrap item placed in Break 1 — cybs stack arguments (user, 2026-10-07)

cybs (the hand-assembly bootstrap compiler the seed assembles; `bootstrap/cybs.cyr`) passes only the six
register arguments: `emit_fn_call_pops` handles 0..6 and `emit_store_param` stores parameters 0..5. Found at
6.7.0, when seed-derive rejected a 7-argument helper call in `src/` with a bare "syntax error". **6.7.0 shipped
the interim** (user's option 2): a 7+ argument call is refused BY NAME, and `cybs_call_arity_named.sh` runs
cybs over `src/main.cyr` in check.sh. A 7+ parameter DEFINITION keeps its first six — `lib/fnptr.cyr`'s
`fncall6..8`, which the compiler includes, are such; unreachable with all their arguments (see the comment at
`emit_store_param`). **The repair:** the caller pushes arguments 7+ and the callee reads them from its frame
(`[rbp + 16 + (i - 6) * 8]`, the SysV layout), so `src/` may use 7+ argument helpers and cybs compiles
fncall6..8 faithfully. Acceptance: closure (cybs reproduces `bootstrap/asm`), seed-derive, a cybs fixture with
a 7- and a 9-argument call returning the right values, and the gate's refusal row turned into a success row.
Keep it small and auditable — cybs is the trusted root's first rung (CLAUDE.md *Sovereignty*).

## Tooling item placed in Break 1 — `cyrius test` absorbs `cyrius tests` (user, 2026-10-07)

Today `cyrius test` takes a FILE (bare: the whole corpus, recursive since 6.5.11) and `cyrius tests` takes a
DIRECTORY — two verbs for one job, and CLAUDE.md has to warn about the difference. Consolidate into
`cyrius test` with a recursive directory option: `cyrius test <file>`, `cyrius test <dir>` (recursive),
bare `cyrius test` unchanged. `cyrius tests` stays as a deprecated alias for a release with a one-line notice
naming the new spelling, then goes. CI (`ci.yml`), `scripts/`, CLAUDE.md, the guide and vidya are updated in
the same release.

---

## Stdlib and ecosystem impact of the 6.7.x features (survey 2026-10-07)

Measured by a source scan of every repo under `~/Repos` — strings and comments masked, vendored `lib/`
copies in consumers skipped, `cyrius/lib/` counted as the stdlib. **A fix lands in the SOURCE repo of a folded
stdlib, then re-vendors** (CLAUDE.md *Ecosystem & stdlib*); a non-stdlib repo gets a filed note, never a lane.

| Feature | Stdlib (`lib/` + folded) | Ecosystem | What it needs |
|---|---|---|---|
| A traits / typed `self` | **0** `impl` blocks; `lib/trait.cyr` is the runtime-dispatch library | 0 `impl` blocks outside cyrius's own 22 test impls; 1,182 `fn x(self, …)` FREE fns in 16 repos (dhvani 339, naad 252, …) — untouched (A4 types `self` only inside `impl … for T`) | nothing to repair; stdlib types MAY gain `impl` blocks later (opportunity, not a fix) |
| A `Struct = *Struct` copy | — | sites that relied on the 8-byte pointer store were already reading garbage | none expected; the arc's tcyr pins both sizes |
| B1 `const` | 0 identifier uses | 0 | — |
| B2 `true` / `false` | 0 | 0; `bool` already a type name (3 cyrius tcyr files) | — |
| B5 `loop` / `do` | **`loop`: 3 sites in `lib/sankoch.cyr`** (folded — fix in sankoch's source repo) · `do`: 0 | `loop`: **224 sites in 10 repos** — kriya 143, rekha 25, vidya 22, chakshu 12, bhumi 6, argonaut 5, … (mostly `var loop = 1; while (loop == 1)`) | if `loop` is a full reserved word: sankoch fixed + re-vendored BEFORE B5 ships, and a note filed in each of the 10 repos; if contextual: nothing |
| B7 narrow fields | **0** narrow fields in `lib/` | 76 in 4 repos — kavach 21, secureyeoman 21, agnostik 11, cyrius tests 23 | layout change: notes to kavach / secureyeoman / agnostik with the migration; cyrius's tcyr updated in the release |
| C2 bounds mode | every `lib/` raw store becomes checkable when a consumer opts in | — | stdlib must run clean under `#bounds`; anything it trips is a stdlib repair queued to the next break |
| C3 trait generics | **0** generic fns / structs in `lib/` | 1 repo (vidya, an example) | — |
| B3 / B4 / B6 / B8 / C1 | additive syntax | additive | none (stdlib MAY adopt `const` / defaults later) |

---

## Sibling follow-ups — open (each is that repo's next patch release)

Found at the 6.6.12 releases. A sibling's fix ships as that repo's own patch release, pinned to a released
cyrius; a folded stdlib is then re-vendored into `lib/` byte-identical from its tag.

**Recorded in each repo's own roadmap on 2026-10-02**: bayan, crab, sigil, mabda, sakshi, bote, aethersafha
and sankhya below, plus three 6.6.13 downstream notes — abaco (drop its TLS / tan workarounds), agnostic
(the aarch64 SIGBUS is fixed by I9; rebuild on 6.6.13) and mneme (`f64_parse` values may move ≤ 2 ulp).
kriya's was already there. Every repo that bumps to 6.6.13 must re-vendor `lib/math.cyr` in the same commit
(I5 reserves `f64_le` / `f64_ge` / `f64_trunc`); each note says so.

**Recorded in each repo on 2026-10-05 (the 6.6.16 filings; filings only from here)**: hisab `1faa48f` + `8895f32`,
kavach `237098d`, sandhi `857a469`, sigil `e36a140`, bayan `a63bd45`, yantra `38627f1`, abaco `e1f4abb`, szal
`6770fde`, agnosai `6cb1fc4`, agnos `e8553c47` — one bullet each below. Not filed: gnoboot (srcb-3 recorded nothing
for it, and its roadmap.md has uncommitted changes), argonaut (net-5's stale comment at `src/syscall_compat.cyr:59`,
information only), the retired agnosys copies.

- ⚠ kriya `k_isatty` does TCGETS into a 16-byte `var tio[16]` (termios is 36 B): a stack overrun on
  every tty probe, a crash on aarch64 (`cp -i`, `mv -i`, `ls` on a terminal) — recorded for kriya 1.7.4,
  which also adopts 6.6.12's aarch64 wrappers after the cyrius tag.
- bayan: `bayan_toml_escape_a` still answers a refused output buffer with `str_from("")` from the default
  allocator (1.5.11 fixed the unescape side), and `bayan_toml_parse` / `_inline_parse_a` leave their other
  refusals unchecked (`vec_new`, `section_new`, `pair_new`, `vec_push`, and the `str_builder` paths).
- crab: `[deps.daimon]` has no `modules`, so from 6.6.13 (I10) it warns on every build and CI clones daimon —
  add `modules = []` before pinning ≥ 6.6.13.
- sigil can drop its in-process cold-trial workaround for arm64 macOS once it pins ≥ 6.6.13 (I6).
- mabda still names `_sk_info_cstr` in sakshi's `_sk_` namespace (no collision today).
- bote still commits live `path = "../libro"` / `"../majra"` lines (the dhvani/libro shape 6.6.12 removed).
- aethersafha: 21 files not `cyrius fmt`-clean on 6.6.11 (its CI has no fmt step); duplicate-fn warnings
  between sigil and the agnostik / agnodrm bundles (`_hex_nibble`, `result_print_err`, …).
- sankhya's README / CLAUDE.md name varna 2.1.0 / itihas 2.4.0 / avatara 2.9.0; its 3.0.2 lock pins
  2.4.1 / 2.5.0 / 2.14.8.
- **hisab** — 6.6.16 fixes both of its 2026-10-03 filings: a top-level `fncallN` on a capturing closure (srca-2,
  H1) and a closure's `: stack` return being booked against the enclosing fn (srca-1, H2, its D082). Nothing
  changes in its tree. Once it pins ≥ 6.6.16 it may relax `src/autodiff.cyr`'s "invoke from inside a fn" recipe
  note and return `ad_grad_into(..)` from the closure again, returning a pair on every path; then it archives
  both records. The ganita 1.2.13 fold also addresses its two ganita SVD filings, but SVD non-convergence is now
  −3 (was −1), so `svd_compute`'s fallback needs a re-check. Roadmap + records: hisab `1faa48f`, `8895f32`.
- **kavach** (a CONSUMER, not a stdlib — it gates nothing in cyrius; user, 2026-10-04) — from 6.6.16 (CVE-74)
  plain-socket writers issue `sendto(..., MSG_NOSIGNAL)`, so `security_create_basic_seccomp_filter` kills a
  process that loads it on itself on its first `sock_send_all`. This was measured, not only for native TLS
  (whose writers have done the same since 6.6.14, CVE-66). Its sandboxed spawn paths load the exec filter and are
  not affected. A measured argument-pinned `sendto`/`fcntl` + `poll`/`ppoll` allowlist (40/37 instructions) was
  added to its open issue as a suggestion, with the probe under `repros/`; kavach decides. Filed in kavach (user,
  2026-10-02): `kavach/docs/development/issues/2026-10-02-basic-seccomp-kills-native-tls-writes.md`; updated
  2026-10-05 in kavach `237098d`.
- **sandhi** (stdlib, fixed upstream at its next release) — both 2026-10-04 filings are fixed in 6.6.16 (thr-1
  blocking channel + `CHAN_BLOCKING`; thr-2 PEM key decoded once per key text) and marked so. Its new
  `2026-10-05-adopt-cyrius-6616.md` lists five adoptions: the stale "sock_send has no MSG_NOSIGNAL" premise
  (`src/server/mod.cyr:1260`/`:1469`), the redundant `_sandhi_server_conn_blocking` (N4),
  `sandhi_session_cache_supported()` reading 1 on OpenSSL 3 under libssl plus an end-to-end resumption test
  (N6), `_sandhi_server_pool_inline` keyed on `CHAN_BLOCKING`, and the server-guide DER-key bullet plus probe [8]
  tightened to `per == 0`. sandhi `857a469`.
- **sigil** (stdlib, fixed upstream) — two issues filed. `pem_decode_privkey` (`src/privkey.cyr:435`, the fold's
  ~20456) never wipes its decoded-key DER scratch, which leaves a plaintext private key in never-freed heap on
  every return path, including the RSA retry case. It also never checks `alloc(pem_len)` for 0, and
  `pem_decode_certs` (`src/pem.cyr:359`) has the same unchecked alloc. Separately, `tests/threads.cyr`'s Windows
  comment is stale since `THREADS_CONCURRENT` reads 1 on Windows (N7). sigil `e36a140`.
- **bayan** (stdlib) — at its 6.6.16 pin bump, `#deprecated` warns through `&fn` (C9), so
  `tests/bayan.tcyr:3111-3112,3575-3576` give 4 warnings and `no-warnings.sh cyrius test` goes red. Rearranging
  those references is bayan's call (no pattern allowance). The `consumer-check.sh` ~266 comment is also stale.
  bayan `a63bd45`.
- **yantra** (stdlib) — with a ≥ 6.6.16 floor, `_cdp_set_nodelay`'s agnos arm can go: N8 defines a -38
  `sys_setsockopt` stub on agnos. Its `json_v_obj_get` calls (`src/protocol/cdp.cyr` 158/187/313/316) now warn in
  either include order; switch them to `bayan_json_v_obj_get_by_cstr`. yantra `38627f1`.
- **abaco** — `_ccy_nodelay`'s `#ifdef CYRIUS_TARGET_LINUX` guard (`src/ai.cyr:1813`) can relax at the 6.6.16 pin,
  because agnos now has a `sys_setsockopt` stub (N8). The guard also skips macOS, where TCP_NODELAY works. abaco
  `e1f4abb`.
- **szal** — from 6.6.16 a full subscriber channel blocks `_hub_publish` on arm64 macOS and Windows as it does on
  Linux (it used to drop the event), and the `run_parallel` permit semaphore now really caps there. Its
  stream/parallel tests should run on macOS and Windows at the bump, and its "no `chan_try_send`" comment is stale
  (that API has existed since 6.4.84). szal `6770fde`.
- **agnosai** — no code change. The sandhi 1.10.7 fold reaches it at 6.6.16 (the chunked verbs now report write
  results, so B8 can notice a departed client). Its kavach `basic`-profile row was corrected (spawn paths load the
  exec filter). `arena_pool`'s ring is now locked on arm64 macOS, and the `inference_queue` reply channel really
  waits on Windows. agnosai `6cb1fc4`.
- **agnos** (roadmap only, pinned 6.6.6) — at the 6.6.16 pin an x86 kernel build warns twice (srcb-3 kmode:
  `_AGNOS_VERSION` version.cyr:55, `kernel_hostname` core/syscall.cyr:1582) with a byte-identical image.
  Separately, the aarch64 kernel build fails on agnos's own 6.6.6 compiler too: `DIRECTMAP_BASE` is undefined at
  `core/pmm.cyr:330` because `core/vmm.cyr` is included only under `ARCH_X86_64`. The agnos stdlib peer also gains
  a `sys_setsockopt` decline stub (N8). agnos `e8553c47`.

**Recorded in each repo on 2026-10-05 (the 6.6.17 filings; docs commits, not pushed — each opens with "nothing to
do until cyrius 6.6.17 is tagged and out")**: one line each below. Not filed: **ark** and **bote** (their
`docs/development/roadmap.md` has uncommitted changes — ark's `[build] defines` note, bote's `lib sync` note stay
here until it is clean), **mishran** (no roadmap or issues dir; its P5-A note is the sadish / dhancha one), and the
two generic notes with no per-repo list — the ~57 repos with `CYRIUS_DCE=1 cyrius build` CI lines (`[build] dce =
true`) and scaffolds from `cyrius init --bin` / `cyrius port` before 6.6.17 (`output = "{PROJ}"`) — which live in
CHANGELOG [6.6.17] *Downstream* (no ecosystem sweep).
- **agnos** — the BSD socket names are portable wrappers on the agnos peer (no new syscall number); the CLI builds
  for agnos but answers version / help only. agnos `267b200d`.
- **kashi** — bare `cyrius test` runs `[build] test` (`src/test.cyr`, 393 assertions) for the first time in CI;
  check it is green before the pin bump. kashi `fdadf99`.
- **crab** — its CI comment "`cyrius test` DOES NOT RUN THE `[build].test` ENTRY" becomes false; `test = "tests"`
  runs each file once. crab `b932a53`.
- **sakshi** — `[build] defines` is read; the CI `-D SAKSHI_SMOKE` is redundant. sakshi `e2f3a0a`.
- **sigil** — `[build] defines` is read for every `cyrius build` (the fuzz loop included); the CI `-D SIGIL_SMOKE`
  is redundant. sigil `6acc021`.
- **rekha** (P5's filer) — `[coverage] programs` / `--programs` / `--per-entry` (text coverage; P5-B is v6.7.x);
  its "blind to programs/" CI comment can be revised. rekha `a4005be`.
- **sadish** — the same P5-A note. sadish `f6f6ad4`.
- **dhancha** — the same P5-A note. dhancha `13c8aa5`.
- **setu** — the same P5-A note, as an information issue (setu keeps no roadmap.md). setu `f3c7b6b`.
- **kriya** — the `lib sync --full` lock complaint is fixed; run `lib sync` before `deps` / `build` after a pin
  move (`--relock` otherwise). kriya `8275490`.
- **yantra** — the `rm -rf lib cyrius.lock` regeneration recipe is no longer needed. yantra `20d8260`.
- **agnostik** — CI runs `lib sync` → `deps` → `deps --verify`: no change; a moved snapshot now fails at
  `lib sync` by name. agnostik `07720f0`.
- **nein** — the same `lib sync` note. nein `cc55e18`.
- **agnostic** — the same `lib sync` note, ⚠ plus one workflow without `deps --verify` that CAN go red; and its
  `[deps] stdlib` "patra" / "sigil" leaves, lost to a `]` in a comment, are read again (m6). agnostic `9d5e9a9`.
- **agnosai** — ⚠ CAN go red at the pin bump: CI runs `lib sync` → `deps` with no `deps --verify`, and `lib sync`
  now refuses a lock's previous-pin rows (`--relock`). agnosai `2ab334d`.
- **ai-hwaccel** — the same ⚠ `lib sync` note as agnosai. ai-hwaccel `85d7985`.


**6.6.18 — the post-tag fold wave (OUR work, not a filing) and the filings (2026-10-06).**
- ~~**W — the 12 folded stdlibs regenerate in ONE wave**~~ → ✅ **SHIPPED** — all twelve tagged after 6.6.18
  (sakshi 2.5.7, bayan 1.5.12, sandhi 1.10.8, sigil 3.13.10, ganita 1.2.14, niyama 1.0.13, mabda 4.1.7, vani 1.2.9,
  yantra 1.0.8, yukti 2.3.15, patra 1.15.2, sankoch 2.8.1) and re-vendored byte-identical in **6.6.19 R1–R3**
  (CHANGELOG [6.6.19] *Folds*); the 6.6.20 downstream check found all twelve pinned to 6.6.18 with their latest tags
  equal to `docs/ecosystem.md`'s rows. The filings below stay until each is done.
- **takumi** — declare `sakshi` in `[deps] stdlib` before the 6.6.18 pin bump (sandhi's fold calls it; it reached
  `lib/` only through sigil's old sidecar). takumi `b4b8e9a`.
- **samvada** — has no Windows `sys_recvmsg` wrapper (`lib/syscalls_linux_common` + agnos only); mabda's 6.6.18
  distlib names it on `x86_64-windows`. ⚠ **Not filed yet**: samvada's `docs/development/roadmap.md` has uncommitted
  changes (with nine other files); it stays here until that tree is clean.
- **To file after the tag** (docs commits in each repo, not pushed): **rekha** — drop `programs/prelude.cyr` and
  the CI sidecar pin (P4), and adopt `--poison[=ab]` through `poison_alloc` for `sd_alloc` (P6); **kriya**, **puka** —
  `--poison` now covers `alloc()` and an overwrite exits 86, so their poison runs check something real; **agora** —
  re-evaluate N4 against P6.
- The ~62 non-fold producers with sidecars: no filing per repo — they meet the stale `--check` (its hint names the
  cause) and the agnos verify target at their own pin bump; consumers that used a leaf only because a sidecar
  over-reported it follow ecosystem-migration-6.6.18.md. No sweep.
- **6.6.19 — filed 2026-10-06 in each repo's `docs/development/roadmap.md`** (docs commits, not pushed; each opens
  "⛔ Needs cyrius >= 6.6.19 — do not bump the pin until 6.6.19 is tagged"; notes, never orders):
  - **`[embed]` retires the embed generators** — **agnosai** (`scripts/gen-presets.sh` + the checked-in
    `presets_data.cyr`; one entry per preset, `var X` becomes `X()`; JSON compaction stays theirs), **agnostic**
    (`gen-presets.sh` outright and the escaping half of `gen-webgui.sh`; CSP hashing stays theirs), **rekha**
    (`scripts/face2cyr.py` + the 1.65 MB `fonts/face_data.cyr` → `[embed] REKHA_FACE` + an embed-only `[lib.face]`
    profile; agnos then points its `modules` at the face bundle), **sankoch** (folded stdlib —
    `scripts/brotli_dict2cyr.py` + `nul-literal-gate.py` retire upstream, `[lib] embed` / `[lib.woff] embed` carry
    `_brotli_dict_data`, then cyrius re-vendors `lib/sankoch.cyr` byte-identical).
  - **Threads / async** — **sigil**: the `_crypto_needs_block` comment ("macOS keep it process-global") is stale,
    both macOS arches have per-thread TLS. **sandhi**: `_sandhi_server_pool_inline` can test `CHAN_BLOCKING` instead
    of `CYRIUS_TARGET_LINUX`, and the stop-flag idle path can use `async_await_readable_ms(sfd,
    SANDHI_SERVER_STOP_POLL_MS)` instead of `sleep_ms` on every target. **agnos**: a non-destructive readiness probe
    (a blocking epoll over VFS_SOCK, or #57 returning a VFS_SOCK fd) would let the cyrius peer drop A2's readiness
    stash; and please boot-test sandhi's cooperative server (`run_async`) — A2 is verified only under the
    PTRACE_SYSEMU fake kernel.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

> ⛔ **Frozen until Break 1** (the v6.7.x operating rule): items are ADDED here during the feature releases —
> found issues with a repro — and none is worked until a catch-up break, where the user picks.

> **Re-triaged 2026-10-06 at the 6.6.20 closeout (Closeout item 12, BACKLOG-00).** All **61** bullets were
> checked against the live tree at `e696746d` — with `build/cycc`, `cycc_aarch64` + qemu, a tree-built cx
> compiler / VM, throwaway-HOME CLI runs or a code citation; the probes are the audit's. **55 still live** —
> five of them carried a materially WRONG claim, corrected in place below (the redefined-fn binding, aarch64
> many-argument calls, the reserved intrinsic names, `Struct = *Struct`, the `cyrius deps` read side); two are
> host-only and were not re-verified (XLAT-3 on ecb, `async_iocp_pe` on cass). **2 shipped**, **2 partly
> shipped**, **2 obsolete or answered** — struck in place with the evidence. **1 removed item recurred** (the
> race-gate port flake), and the audit scored the `/tmp/cyrius-<pid>` bullet done ("cleaned, 2 left") when its
> class was still live — 49 by the same evening; it stays open, below. The v6.7.x candidates moved into [roadmap_6.md](roadmap_6.md) § v6.7.x (two were
> duplicates there). Placement is clean: nothing codegen or runtime is parked at 7.x here, in roadmap_6.md or in
> roadmap-future.md. 0 open issues; both open proposals correctly open.
>
> **Promoted into 6.6.20 by the user (2026-10-06):** the redefined-fn binding, aarch64 calls with 262+
> arguments, and the `sizeof` / `mulh64` / `fncallN` names. **Placed in the 6.6.20 closeout passes** (the audit's
> group A — small, no design call): the `cyrius deps` `modules` `..` refusal, the race-gate log fix, the gate
> temp-dir leaks, and four cleanup items (`dce_eliminates.sh` under pipefail, the stale `dir_list` comment, the
> check driver's shared output name, the dead `_strict_mode`). Each is marked below; the CHANGELOG [6.6.20] entry
> is the record of what shipped. ⚠ *Integration: strike each marked bullet that merged; un-mark any that did not.*
>
> **Proposed order for the rest (only the user promotes):** **(B)** the first repair window after the closeout,
> the silent wrong-binding / wrong-value class first — a top-level `var v = pair_fn(..)`, `var G: f32 = 1.5`
> storing f64 bits, `println(n)` on a typed local, `asm { in .. }`, `#pure` and a forward `#io`, cycc's 8 KB
> environment cap, `--syntax-only` in five forks, the Windows `sys_setsockopt` stub; **(C)** the 6.6.x arc
> finish-outs — the `[embed]` E-S3 residual, P6 S7 guard pages, named profiles + `[build] target` (⚠ today
> `[build.release]` and unknown sections are silently ignored) + the `deps` / `lib sync` order, the ESYSXLAT fold
> tail (x86-macOS, XLAT-3, the `esysxlat_fold` blind spot), the TLS conformance batch, the cx limits (> 248
> arguments, the fnptr arm); **(D)** the v6.7.x language arc — moved to roadmap_6.md; **(E)** after v6.7.x and
> before RISC-V (already placed) — DCE compaction + the WPNR merge + `dce_data_vaddr_frozen`, net §4, the syscall
> families, AF_UNIX; **(F)** the long tail — the DRY pass-1 scanners (the structural fix for `--syntax-only`'s
> class), DWARF, incremental compilation (923 ms vs the 2 s condition), the FREED holes (19), tantu,
> auto-vectorization, the cybs > 6-parameter diagnostic, the agnos CLI port, Windows long-path symlinks, the
> aarch64-region translated-row warning, mirshi's old-kernel mode, `async_iocp_pe` (cass), `gates_never_write_tree`
> axis 9, agnos #48's deadline (agnos), the sandhi comment (a filing).

- **Found by the 6.7.x feature releases (backlog — only the user promotes; v6.7.x operating rule 2).**
  - ⚠ **A struct ARGUMENT is never type-checked against its parameter** (found at the 6.7.1 open, C3): a `Pt`
    passed to `fn bq(b: Q)` compiles and reads past it (`bq(p)` returned garbage for `b.c`), and a generic
    INSTANCE passed where its base is declared reads the base's layout — `fn bs(b: Box)` with `bs(mk1(p))`
    (`mk1<T>(x: T): Box<T>`, `Box<Pt>` is 24 B) returned `b.v.y`'s 4 where `n` was 8. A silent wrong value. The
    RECEIVE path already refuses the same mismatch (`var r: Box; r = mk1(p);` → "cannot copy 'mk1' into a
    variable of a different struct/vector type"), so the argument path is the gap; refusing it changes what
    compiles (a language decision — the user's). Repro: the two programs above, `build/cycc` 6.7.1.

- **Found by the 6.6.20 closeout and not fixed in it (2026-10-07; backlog — only the user promotes).**
  - **A parenthesised struct argument to an address-passed parameter pushes the struct's VALUE**: `rd3((a))`
    (`p: *P3`), `rd1((s))` (`p: *S1`), `rd1((mk1(4)))` — SIGSEGV on x86 / aarch64, an access violation on PE, a guest
    error on cx. `_try_push_struct_addr_arg` keys every arm on the argument's first token being the name. (The
    operator path takes the parenthesised forms since 6.6.20.) Pre-existing at 6.6.19.
  - **A struct-returning call over 8 B as an operator's address-passed operand** — `s - mk3(4)`, `s - (mk3(4))` with
    `fn P3_sub(a: *P3, b: *P3)`, and the by-value `a - bump(b)`: SIGSEGV on x86 and aarch64, a wrong value on cx.
    `_op_rhs` gives only the <= 8 B class a temp. Pre-existing at 6.6.19.
  - **`cyrius deps --verify` on a CRLF checkout of a committed `lib/`** (`core.autocrlf=true`, the Git for Windows
    default) reports a hash mismatch for every file: the lock hashes the LF bytes. 6.6.20 made `cyrius.lock` itself
    CRLF-tolerant, not the files it hashes. Remedy today: `.gitattributes` `lib/** -text`. Decision: normalise or
    document.
  - **The TRANSITIVE `[deps]` `path` confinement** (CVE-88 closed the `modules` `..` / committed-symlink vectors only):
    a tagged dep's own `cyrius.cyml` declaring `[deps.evil] path = "<abs dir>"` still vendors from that directory.
  - **Held back by decision (DECISIONS.md)**: folding constant `if (SYS_OPEN == 2)` arms at parse time (DEAD-10; the PE
    warnings are gone via `#ifndef`), consolidating the IR heap bands into one `alloc()` arena (HEAP-12), `var f: f32 =
    1.5` storing the f64 bits (LEX-EXPR-04, already listed).
  - **16 store slots carry a stale `bin/cybs`** (g-install's RS-02 found `--refresh-only` installed an untracked
    `build/cybs`; fixed for every future refresh). Restoring 6.6.3–6.6.9 and 6.6.11–6.6.19 is
    `sh scripts/verify-store.sh --restore <v>` per slot — it writes the live store, so it is the user's to run.
  - **self_compile +6.8 % on the same input, all from CVE-86's attribute-line rule** (s-pplex `0d85cdcd`, +50 ms of
    924 → 987 ms; a per-commit scan of the 6.6.20 merge history, every other lane within ±6 ms). The lexer half only
    runs on `#`; the cost is likely the preprocessor half (`lex_pp.cyr`). Find it and take it back without reopening
    the forged-`#@file` vector.
- **Found by the 6.6.19 lanes and their review (2026-10-06; backlog — only the user promotes).**
  - **The `[embed]` link race on Windows and Apple Silicon (E-S3 residual).** Linux and x86 macOS walk the path
    with `openat(dirfd, component, O_DIRECTORY | O_NOFOLLOW)`; PE keeps the per-component reparse-point check plus a
    whole-path `O_NOFOLLOW` open, so a directory swapped for a junction between them is followed — fix with
    `GetFinalPathNameByHandleW` on the opened handle + containment under the project root (a NEW PE reroute).
    macOS arm64's `SYS_OPENAT` 56 is rerouted to BSD `open` DROPPING the dirfd (Linux `AT_FDCWD` −100 ≠ Darwin −2,
    so a straight row to `openat` 463 would break every open) — needs a dirfd-preserving Mach-O route, with a
    companion in `tests/tcyr/crossos/`. Both need concurrent write access to the checkout during the build.
  - ⚠ **`sizeof`, `mulh64` and `fncall0..8` are in neither of `util.cyr`'s reserved tables** — **✅ FIXED IN
    6.6.20 (promoted by the user 2026-10-06; BACKLOG-03)**: a fn / var / param declaration with one of those names
    is refused by name. CORRECTED at the re-triage — the three are NOT the same shape: `fn sizeof()` declares and a
    call is a parse error (as this bullet said), but a user `fn mulh64(a, b)` compiles and every call SILENTLY binds
    the intrinsic (the user fn is reported unreachable), and a user `fn fncall1(a, b)` compiles and its call is
    lowered to an indirect call through argument 1 — a crash. Any tool that derives the reserved set from util.cyr
    alone misses them — `[embed]`'s list reads all four sources.
  - ~~**The macOS-arm64 `cyrius` CLI looks for `cycc_aarch64` in `CYRIUS_HOME/bin`**~~ → answered at the 6.6.20
    re-triage: **by design** — the arm64-macOS tarball ships `cycc_aarch64` as a copy of the native `cycc`
    (`scripts/build-macos-arm64-tarball.sh`, "the same native arm64 binary") and the wrapper defaults to it
    (`cbt/core.cyr`, `cbt/cyrius.cyr`); the ecb smoke lacked it only because it was not staged from the tarball.
  - **Some gates leave temp dirs in `TMPDIR`** — the 9.9.9 installer staging and `cyrius-<pid>` test dirs. **Placed
    in the 6.6.20 closeout** (CLN-01 the installer's staging dir on every refusal, CLN-02 the SIGKILLed runner's
    dir, CLN-03 check.sh reaping EMPTY dead-pid `cyrius-<pid>` dirs — a non-empty one is kept; see the `/tmp` bullet
    below).
- **Found by the 6.6.19 R2/R3 work (2026-10-06; backlog — only the user promotes).**
  - ⚠ **A redefined fn binds a non-tail call to its FIRST definition** (a silent mis-binding) — **✅ FIXED IN
    6.6.20 (promoted by the user 2026-10-06; BACKLOG-01)**. Found as: in `stdlib_alloc_refusal_sentinels.sh`'s
    ws_server probe, a stub `sandhi_server_find_header` defined after `include "lib/ws_server.cyr"` was called from
    `main`, yet `ws_server_handshake` still called sandhi's version — while the compiler warns "last definition
    wins". CORRECTED at the re-triage: this bullet said two-file repros bind to the last definition and the trigger
    was specific to that build; it is not. A 4-line single file (`g` returns 2, `h` calls `g`, `g` redefined to
    return 1, `main` returns `h()`) exits **2** on x86, aarch64 and cx. Mechanism: a direct call to an
    already-defined fn bakes its CURRENT offset (`ECALLTO`, `src/frontend/parse_expr.cyr` and 14 more sites), and a
    redefinition overwrites the offset without re-patching the earlier sites; tail calls and forward calls go
    through fixups and bind to the last definition.

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces.

> **Placed 2026-10-02 (the tail plan, accepted):** items named in *The 6.6.x tail* are scheduled there and
> stay listed below only until their release ships. **Removed 2026-10-02** with the evidence in the archived
> memo §3(d): the `ir_dce` / `CLASSIFY_CF` line (the wrappers were deleted at 6.5.50, `374f361d`; CLASSIFY_CF
> is wired through RA_SCAN_LOOPS), the bare `var a[N]` question (subscripting one is a hard error naming the
> typed spelling; overrun checks go to C2), the I7 / race-gate port flake (shipped in 6.6.14 — ⚠ it RECURRED at
> 6.6.19, recorded only in CHANGELOG [6.6.19]; the 6.6.20 audit root-caused it — the readiness grep read a stale
> `ACCEPT` line from a log file the second serve reuses, in `tls_first_use_thread_race.sh` and on every row of
> `tls_libssl_hostname_binding.sh` — and it is placed in the 6.6.20 closeout, BACKLOG-05), the Rosetta
> timebase item (no Rosetta host — an unsupported configuration) and sakshi's qemu-static item (does not
> reproduce in CI). **Removed 2026-10-05**: every item 6.6.16 shipped (the 6.6.13 lanes' five, premise-check
> (a)–(c) and (g), the `#deprecated` gaps, five 6.6.12 items, eight 6.6.14-lane items), each checked against the
> merged tree; their history is CHANGELOG [6.6.16]. **Removed 2026-10-06** (shipped in 6.6.18): the ESYSXLAT
> inline-chain item (the compile-time fold and the per-class stubs) and 6.6.13 premise-check item (h), the arm64
> macOS `pthread_create` sign-extension — which had been called "harmless: `thread_create` tests only `!= 0`", and
> was not: `!= 0` compares all 64 bits, exactly the comparison the unspecified upper half of an `int` return reads.
> **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **Found by the 6.6.18 lanes (2026-10-06; backlog, not placed — only the user promotes).** Planned out of the
  6.6.18 rows or met in passing by the lanes, reviewers and integrator; pre-existing unless it says otherwise.
  - The x86-macOS `EMACHO_SYSXLAT` fold — XLAT-1's method on the x86 Mach-O chain (its rows are copied into every
    site, ~1.3 KB each, ~0.8 MB of the x86-macOS compiler).
  - XLAT-3: arm64-macOS pipe / fork post-`svc` fixups for literal numbers (~68 B a site; verifiable on ecb only).
  - The WPNR 4,096-run merge — merge a dead run into the previous one when `cp == prev_cp + prev_len` — lifts static
    x86 ELF's compaction cliff at 4,097 dead fns (6.6.18 names it; it does not lift it).
  - `dce_data_vaddr_frozen.sh` as a behavioural gate, once the merge lands (≤ 4,096 dead fns of ≳ 520 B cross a 2 MB
    bucket).
  - `esysxlat_fold.sh` cannot see a fold that skips its `cur` update: no live re-capture row exists to exercise it
    (`esysxlat_row_order.sh` keeps the chain free of them). A synthetic row in the gate's own probe would.
  - P6 S7, poison guard pages — the one way to catch a read that jumps a whole redzone. Constraints: `mprotect`;
    16 KiB pages on Apple arm64; `VirtualProtect` reaches no stdlib path today; agnos `cyr_mprotect` is a no-op, so
    an agnos run must REPORT "unguarded", never claim the coverage.
  - `dce_eliminates.sh` exits 7 silently under `bash -eo pipefail` (it passes under `sh`, which is how check.sh runs
    it). **✅ Fixed in the 6.6.20 closeout.**
  - `cbt/commands.cyr`'s comment "dir_list is non-recursive, so fuzz and tests are disjoint" is stale since v6.5.7.
    **✅ Fixed in the 6.6.20 closeout.**
  - Two `check.sh` selectors in parallel in ONE worktree collide on `build/cyrius_check` — run them in parallel only
    across worktrees (or give the check driver a per-run output name). **✅ Fixed in the 6.6.20 closeout.**
  - ⚠ **A killed `cyrius` CLI run leaves a NON-EMPTY `cyrius-<pid>` dir in `/tmp`, and nothing reaps it.** The ~893
    dirs this bullet first counted were cleaned (2 left at the 6.6.20 audit), but the class is live: **49**
    `/tmp/cyrius-*` dirs by 19:34 on 2026-10-06, all created during the closeout's own lane runs, every pid dead,
    **33** holding a killed `cyrius check`'s `check_<pid>.tmp.<pid>` + `cpp_<pid>` + `cc_err` (~650 KB each).
    **CLN-03 (6.6.20) mitigates the EMPTY case only**: check.sh rmdirs an empty dead-pid `$TMPDIR/cyrius-<pid>`
    older than `CYRIUS_CHECK_REAP_MINS`, keeps a non-empty one by design (the CLI's post-mortem contract), and
    reaches `/tmp` only when `TMPDIR=/tmp`. Not yet traced: which runs land in `/tmp` although every lane exports
    `TMPDIR`. Open decision: whether a non-empty dead-pid dir past an age bound is reaped too.
- **Found by the 6.6.17 lanes (2026-10-05; backlog, not placed — only the user promotes).** Met in passing by the
  6.6.17 implementers, reviewers and integrator, each pre-existing unless it says otherwise; not swept for.
  - ~~⚠ `Struct = *Struct` bind vs copy~~ → **DECIDED 2026-10-07: copy at both sizes — roadmap.md § Spec A4** (moved at the 6.6.20
    re-triage, CORRECTED: `≤ 8 B` stores the pointer value (still a silent wrong value), but `> 8 B` BINDS (aliases) —
    it does not copy, so the walk this bullet described works (BACKLOG-06). ⚠ Re-measured at the 6.7.0 open: `> 8 B` now COPIES.
  - ⚠ **aarch64: a call with 262 or more arguments silently corrupts `sp`** — **✅ FIXED IN 6.6.20 (promoted by
    the user 2026-10-06; BACKLOG-02)**. CORRECTED at the re-triage: this bullet said "~300 or more … dies with
    SIGILL"; the real threshold is **262** and the failure there is SILENT. `ECALLCLEAN`
    (`src/backend/aarch64/emit.cyr`) emits `add sp, sp, #((n - 6) * 16)` with no imm12 guard: n = 261 is
    `add sp, #0xff0`; n = 262 encodes `#0x0, lsl #12` (sp is never restored — 4 KiB leaked per call, and a
    4,000-iteration loop SIGSEGVs); n = 263 adds 64 KiB; only from n = 519 does the shift field go reserved and
    SIGILL (direct and `callptr` alike). It is the imm12 class roadmap-future.md had marked CLOSED; this site was
    missed.
  - ⚠ cx: a call with more than 248 arguments has nowhere to put them (250 return a wrong value, 260 trap "guest stack
    overflow"); value-form vector arguments ride r16..r31, which are integer argument registers once a call has 14
    or more integer arguments.
  - ~~A method call on a field; compound assignment on a field~~ → **moved to [roadmap_6.md](roadmap_6.md)
    § v6.7.x** at the 6.6.20 re-triage (BACKLOG-13): the method-on-field half was a duplicate of A5 (`b.v.sum()`);
    compound assignment on a field (`h.n += 4` → `expected '='`; a scalar `x += 4` works) is B8.
  - ~~`p[i]` on a `*T` is refused~~ → a duplicate of [roadmap_6.md](roadmap_6.md) § v6.7.x C2 ("Still to do: `*T`
    pointer subscripts"); struck from here at the 6.6.20 re-triage (BACKLOG-13).
  - ~~An UNTYPED `var u = s.clone();` does not take a method's struct return type~~ → **narrowed and moved to
    [roadmap_6.md](roadmap_6.md) § v6.7.x A5** at the 6.6.20 re-triage: it is fixed for structs over 8 bytes and
    fails only for an 8-byte (one-field) struct (BACKLOG-07).
  - ~~A generic-struct FIELD `b: Box<i32>;`~~ → **moved to [roadmap_6.md](roadmap_6.md) § v6.7.x C3** (generics)
    at the 6.6.20 re-triage (BACKLOG-13).
  - `#pure`'s `#io` / `#alloc` check reads the callee's flags at the call, so a call to an `#io` fn defined LATER is
    silent (only `#deprecated` has a pass-1 record).
  - cybs refuses a fn with more than 6 parameters with a bare `syntax error` and no location (keep `src/` helpers at
    6 parameters or fewer until it names it).
  - The aarch64, both Mach-O and cx forks ignore `--syntax-only` (only main.cyr and main_win.cyr read it), so
    `cyrius lint` / `check` do a full compile there — slower, harmless.
  - `_strict_mode` is set by six `src/main*.cyr` forks and read by none (`cycc --strict` has had no effect since
    6.3.2) — a dead-code closeout item. **✅ Fixed in the 6.6.20 closeout** (DEAD-07).
  - `cyrius deps` / `build` run after a pin move but BEFORE `lib sync --full` stamp the new pin over lock rows for
    files `deps` does not vendor, and `lib sync` then refuses (it names `--relock`). Removing the order dependence
    means `deps` re-vendoring or re-locking those rows on a pin change, which touches every consumer with a
    `lib sync --full` tree; the loud refusal ships in 6.6.17.
  - Named manifest profiles (`[build.PROFILE]`, P1's deferred half) — and `[build] target`, held in 6.6.17
    (recognised, warned, not read), wired when a consumer needs it.
  - The agnos `cyrius` CLI answers only `version` / `help`: a working one is a port of cbt's process layer (~95
    `sys_unlink(path)` and ~17 `sys_waitpid(pid, &st, opt)` sites, raw `sys_execve` / `sys_dup2`) onto
    `lib/process_agnos.cyr` and the portable `xunlink`.
  - `tests/win/async_iocp_pe.cyr` on cass returns 1 at step 2 (`async_with_timeout`) under a plain
    `cmd /c "cd /d … && aip.exe"`, 3 of 3, identically at the 6.6.17 slot open; the release gate's
    `cmd /v /c "…& …"` form exits 42.
  - `gates_never_write_tree.sh` axis 9's static wine scan cannot see a PE binary run directly through binfmt_misc
    (which uses the shared `~/.wine` and the real HOME); no gate does it since 6.6.17's g7.
- **Found by the 6.6.16 planning premise checks (2026-10-04; backlog — the user promoted only the `*iN`
  pointer truncation and the libssl-verbs-on-a-native-ctx corruption into 6.6.16).** Met in passing, not swept for.
  - ⚠ `cyrius deps` READ side: a `modules` entry with a `..` component, and a TRANSITIVE manifest's `path`, vendor
    any readable local file into the consumer's `lib/` — and `deps` exits **0** ("1 deps resolved"; measured at the
    re-triage: `modules = ["src/x.cyr", "../secret"]` → `lib/sib_secret` holds the secret). CORRECTED: an absolute
    `modules` path is NOT a vector (it is joined as `<dep>//etc/hostname` and reported "not found"). **The `modules`
    `..` half is placed in the 6.6.20 closeout** (BACKLOG-04 — refused by name, as `[embed]` and CVE-76's tag check
    already do; it needs no design call). Still open: confining a TRANSITIVE manifest's `path` to its own tree is
    the design call (54 legitimate root `path = "../sibling"` uses). Security-relevant; 6.6.16's CVE-76 covers the
    `tag` field only.
  - ⚠ Silent wrong values: a top-level `var v = pair_fn(..)` keeps the tag and drops the payload (the v6.5.67
    single-bind refusal is gated on `GINFN == 1`); `var G: f32 = 1.5` (global or local) stores the f64 bit
    pattern with no warning. *(Its third case — through a pointer-mode 8-byte struct, `o.m()` (self = `&o`) and
    `T_m(o)` read different values — moved to [roadmap_6.md](roadmap_6.md) § v6.7.x A4 at the 6.6.20 re-triage,
    BACKLOG-13: it is the `self` model's question.)*
  - `asm { in al, dx; }` is refused because `in` is keyword 76, so the `ASM_IN` emitter arm is unreachable —
    a compiler bug (the guide documents the form, ~2049).
  - In an x86 `kernel;` build, float-literal global scalars (`var G: f64 = 1.5;`) are dead stores after the
    program (6.6.16's kmode warning names them).
  - cx: `lib/fnptr.cyr` has no `CYRIUS_TARGET_CX` arm, so an ADDRESS-TAKEN `&fncallN` (called through another
    indirect call) returns 0 there; on x86 / aarch64 the same `&fncallN` runs the library asm, which calls a
    capturing closure's tagged value (no closure dispatch). Direct `fncallN(..)` calls are lowered by the compiler
    at every depth since 6.6.16 and are not affected.
  - `println(n)` on an `i64` local hands it to the cstring overload and exits 139 (the `_int` arm types only
    call arguments). Loud.
  - cycc's `_read_env` (`src/backend/common/env.cyr`) caps the environment at 8191 B and values at 255 B, so
    every `CYRIUS_*` knob is missed past 8 KB of environment (the class the CLI fixed at 6.6.11 J4).
  - Windows `sys_setsockopt` is a -38 stub although `net.cyr` reaches setsockopt through ws2_32 (0xF032), so
    yantra's `TCP_NODELAY` is never set on PE.
  - ~~`lib/syscalls_macos.cyr` declares `SYS_ACCEPT4 = 288` and `sys_accept4` compiles for macOS, which has no
    accept4 (not run).~~ → obsolete (6.6.20 re-triage): `sys_accept4` on macOS is composed from `accept` (43) +
    the fcntl wrappers since 6.5.16 (`lib/syscalls_linux_common.cyr`) and RUNS on ecb / ach in
    `tests/tcyr/crossos/fd_nonblocking.tcyr`. Residual, cosmetic: the unused `SYS_ACCEPT4 = 288` constant (a raw
    `syscall(SYS_ACCEPT4, ..)` there gets -ENOSYS).
  - TLS conformance: the 1.3 ECDSA arms of `_tn_verify_sig_scheme` do not bind the leaf's curve to the scheme
    (RFC 8446 §4.2.3); the 1.3 CertificateVerify and 1.2 ServerKeyExchange length checks use `>`, so trailing
    bytes inside the message are accepted.
- **Found by the 6.6.14 lanes (2026-10-02; backlog, not placed — only the user promotes).** Met in passing or
  left by a lane with its reason; not swept for.
  - TLS (found by the 6.6.15 TLS lane, pre-existing): the native TLS 1.3 client accepts a ServerHello carrying
    an extension it never offered (RFC 8446 §4.2 — unsupported_extension; the walk must still admit
    pre_shared_key on resumption; EncryptedExtensions likely the same); the native 1.2 client does not check
    the server certificate's curve against its own supported_groups; the 1.2 server takes a legacy_session_id
    longer than 32 bytes (never stored or echoed — conformance only); four 1.2-client ServerKeyExchange length
    / key-type checks (`lib/tls_native_hs12.cyr` ~679 / 688 / 691 / 711) have no test that fails without them.
    Not in scope of 6.6.15: a libssl-backend `tls_set_groups`; X448 / secp521r1 (sigil has neither ECDH).
  - TLS — capability limits listed in CVE-64's *Not covered*: no RSA client certificates natively; the native
    client and the native server send their leaf only (no intermediates); an empty certificate_authorities;
    the 1.3 server reads each client message from one record (a client Certificate of at most 8 KiB).
  - TLS, Windows — the store: CurrentUser `ROOT` under the ProtectedRoots policy is unverified; the
    auto-updated disallowed CTL is not read; a root with a dated distrust is refused whole (SecureTrust's
    pre-2026-09-15 leaves fail here); roots Windows has not fetched yet are invisible (CVE-65's *Not covered*).
  - TLS, agnos — a native write can overshoot the caller's deadline by one `sock_send#48` stall (~8 s):
    agnos's #48 hard-codes `TCP_PROGRESS_US`. It needs #48 to honour a time bound (`tcp_send_ex` already
    takes one) — an agnos ABI change, then the stdlib passes the time left (CVE-61's *Not covered*).
    **Filed in agnos** (user, 2026-10-02): `agnos/docs/development/issues/2026-10-02-sock-send-ignores-the-caller-deadline.md`.
  - `tls_native_set_client_cert` sizes its decode at `TLS_CA_MAX_ROOTS` (300) entries; sigil 3.13.7's
    `pem_count_cert_blocks` could size it exactly.
  - ~~sigil (its repo) — the TPM helpers probe `/dev/tpmrm0` and spawn `/usr/bin/tpm2_*` by rooted path; its
    check.sh builds at predictable `/tmp/sigil_{t,b,f}_$$` paths~~ → ✅ **SHIPPED upstream and folded**: sigil
    3.13.8's `scripts/check.sh` works in a private `mktemp -d` under `$TMPDIR`, and sigil 3.13.9's
    `agnosys_rooted_paths_untrusted` makes every rooted TPM / tool / sysfs probe fail closed on Windows (cyrius
    CVE-73, folded at 6.6.15). Struck at the 6.6.20 re-triage (BACKLOG-11).
  - sandhi (its repo, a FILING only): its `src/http/conn.cyr` comment (`lib/sandhi.cyr` ~1604 in the fold) still
    calls the stdlib `tls_connect` ctx "a 24-byte struct"; `lib/tls.cyr` allocates `_TLS_LIBSSL_SHIM_LEN` (40) for
    the libssl shim since 6.6.13. Not yet recorded in sandhi's roadmap / issues — file it there at its next release.
- **Found by the 6.6.12 premise check and lanes (2026-09-30; backlog, not placed — only the user promotes).**
  Met in passing, not swept for. Its three ⚠ silent-memory-corruption items were promoted to **6.6.13**
  (M1–M3) on 2026-10-01.
  - Windows `sys_symlink` (CreateSymbolicLinkW) widens with `_win_widen` at 519 units, no `\\?\` — a link
    at a path over 260 units fails -1 (honest).
  - ~~cyrius-lsp `lsp_read_file` reads the open document through a fixed 1 MB buffer, silently.~~ → ✅ **SHIPPED
    6.6.17 (t4)**: it reads the document whole, sized by `fstat`, and refuses past `_LSP_DOC_MAX` (64 MiB) by name
    (CHANGELOG [6.6.17]; `tests/gates/toolchain/lsp_reads_whole_document.sh`). Struck at the 6.6.20 re-triage.
  - ~~`cyrius lib sync --full` does not re-lock `cyrius.lock`~~ → ✅ **SHIPPED 6.6.17 (t1)**: `lib sync` re-hashes the
    lock rows for the files it writes, and `lib sync --relock` accepts a moved snapshot (CHANGELOG [6.6.17];
    `tests/gates/toolchain/lib_sync_relocks.sh`, 8 axes). Only the pin-move ORDER dependence remains — the
    `deps` / `build` before `lib sync --full` bullet in *Found by the 6.6.17 lanes* (D12). Struck at the 6.6.20
    re-triage.
  - Inside an aarch64 region (6.6.12 B05's `#@a+` markers) a raw literal that HAS an ESYSXLAT x86-compat
    row is still translated with no warning: `syscall(9, ..)` meant as native lgetxattr runs mmap (also 5 →
    fstat, 55 → getsockopt). Unchanged from 6.6.11 (the raw-literal warning only covers untranslated
    numbers); the native spelling is the 1000+N alias (6.6.12 B09). A region-aware warning for translated
    rows is open.
  - Coverage lost to a CORRECT emulator: with mirshi 1.11.3 filling `sysinfo`'s full tier and emulating
    `uptime_us` (#95), `agnos_sysinfo_tail_parity`'s runtime axis and `agnos_monotonic_clock_rdtsc`'s axis 5
    SKIP by name — the pre-1.57.9 `sched_kicks` pre-fill and the refused-calibration fallback in the stdlib
    no longer run on this box. They need an older-kernel mode (e.g. a mirshi switch) to be exercised again.
- **`lib/net.cyr` §4 — per-arch socket syscall peers.** The issue is ARCHIVED (`✅ RESOLVED
  v6.5.7 + v6.5.11`) and was closed deliberately without its §4, so the sharp edge is gone but
  the work is unshipped: `lib/net.cyr` still carries bare x86 numbers with `grep -c CYRIUS_ARCH`
  → **0**, working because nine `ESYSXLAT` x86-compat rows remap them. That remap is
  **load-bearing for 51 ecosystem repos** — this is a migration, not a deletion.
- **`lib/net.cyr` AF_UNIX surface** — a yes/no design call, not a defect: whether `net.cyr` grows
  a Unix-domain socket surface alongside INET. Nothing blocks on it.
- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks with
  no shared pass-1 dispatch helper. A recurring-bug class, not cosmetics: `#io` v5.8.20, `#pure`
  v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute needed return-0 stubs in aarch64 + cx
  and only `cass`'s `cycc_cx` caught the miss. Logic-preserving ⇒ gate is byte-identical
  self-host on all four hosts + seed-derive. Premise-check the fork count at slot entry.
- **The two cyrlint gates — one bite** (re-pinned 2026-10-06 at the 6.6.20 re-triage; their detail is
  [roadmap-future.md](roadmap-future.md) § *DX / cyrlint tooling*): a **bare-local-array slot-write** lint (a
  `var a[N]` — N BYTES — written past its byte size as if it held N slots) and a **SYS_WRITE byte-length** gate
  (`syscall(SYS_WRITE, fd, "literal", LEN)` with LEN ≠ the literal's byte length; 532 sites, 0 mismatches at
  v6.5.33, so preventive). `programs/cyrlint.cyr` implements neither. They had pointed at a "named W2 fold-in slot"
  that no longer existed — an unpinned deferral for a month. The slot-write half may fold into v6.7.x C2.
- **DWARF debug-info emission** — backend/codegen work; slot it when a real debugger story is
  needed. Distinct from the DX diagnostics arc, which was only the error-reporting layer.
- **Incremental compilation** — unpin condition: reconsider when cycc self-host crosses ~2 s. It
  is **923 ms at 6.6.19** (the 2026-10-06 release gate; 731–734 ms at 6.6.1), so the whole-program
  model is still well under the threshold. ⚠ Read the trend with care: the same binary has measured a 52 ms spread across three
  consecutive runs — **wider than most release-over-release deltas** — so a single number carries
  no signal. Every release's mandatory bench run IS the report.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot). Policy: the
  next new compiler-state scalar goes into a hole rather than growing the band. **Cite the live
  count** (`grep -n FREED src/main.cyr`) and the heap map; do not maintain an enumerated list that
  goes stale every minor.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term".

- **The syscall families consumers still hand-roll, unnamed by the stdlib — `setrlimit`, `ptrace`,
  `sched_getaffinity`, `pread64` / `pwrite64`** — what remains of the widened surface v6.6.5
  measured and deliberately did NOT ship. Per-family reasons, consumers and collision analysis
  live in the table of
  [`issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md`](issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md)
  ("Not fixed, deliberately — (b)"). **Pinned here, not left in an archived file**, because a
  deferral is real only when it is pinned somewhere still open. ⛔ **They are in the exact silent
  class thoth filed**: `_SYSX_MEANT` only carries numbers named in BOTH peers, so a NAMELESS
  number produces **no warning at all** (measured: raw 160 on the aarch64 fork warns nothing).
  *(Corrected 2026-10-04, 6.6.16: this entry was titled "Nine syscall families", still listed the
  shipped Tier 1 as unshipped, and called the rlimit family blocked on a `prlimit64` arg-shift.)*
  - ⭐ **Already shipped, so no longer listed here**: Tier 1 at **6.6.8 bite 3** — `unshare`,
    `chroot`, `capget` / `capset`, `process_vm_readv` / `writev`, plus `pivot_root`
    (`lib/syscalls_linux_common.cyr:495-562`, with `-38` decline stubs in the agnos and Windows
    peers; CHANGELOG [6.6.8]; kavach's
    [`issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md`](issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md))
    — and `getrlimit` at **6.6.12** (`sys_getrlimit`, `lib/syscalls_linux_common.cyr:755`; the
    aarch64 peer declares the NATIVE `SYS_GETRLIMIT = 163`, Darwin row `163 → 194`).
  - **`setrlimit` has no arg-shift blocker.** aarch64 has `setrlimit` **164** natively, as it has
    `getrlimit` 163 — no `prlimit64` row is needed (measured under `qemu-aarch64` at 6.6.16: raw
    164 set `RLIMIT_NOFILE`'s soft limit to 64 and raw 163 read 64 back). It wants the getrlimit
    shape: a native declaration in the aarch64 peer, no ESYSXLAT row.
  - **What is left is the warning interplay, not number collisions.** The x86 spellings of
    `ptrace` (101), `sched_getaffinity` (204) and `pread64` (17) ARE products of the ELF-arm rows
    `35 → 101`, `51 → 204` and `79 → 17`, which is why this entry used to call them blocked —
    but the aarch64 peer would declare the NATIVE numbers, as `SYS_GETRLIMIT = 163` does, and the
    natives **117** (ptrace), **123** (sched_getaffinity), **67** / **68** (pread64 / pwrite64)
    and **164** (setrlimit) are neither sources nor products of the ELF-arm chain. That is
    derived from the row COMMENTS in `src/backend/aarch64/emit.cyr`'s ESYSXLAT block, not decoded
    from the generator's tables; it is cross-checked by `qemu-aarch64` runs at 6.6.16 (raw 67
    read `pread` at offset 6, raw 123 returned 8, raw 164 as above) and, for 117, by the
    compiler's own diagnostic — "raw syscall 117 is x86_64 `setresuid`; on ELF-aarch64 that
    number is `ptrace`" — i.e. no row translates it. The remaining design point:
    `programs/gen_syscall_xlat.cyr`'s `is_native_a64` drops the raw-x86-literal warning row for
    any number the aarch64 peer declares below the 1000 alias band — but it can only drop a row
    that EXISTS, and `_SYSX_MEANT` (`src/common/syscall_xlat.cyr`) carries a row only for an x86
    number named in BOTH peers. Of the five natives, only **117** has one today (x86
    `setresuid`): declaring `ptrace` natively would silence that live warning. **123**, **67**,
    **68** and **164** are x86 `setfsgid` / `shmdt` / `msgget` / `settimeofday`, which the x86
    peer does not name, so they have no row and already warn nothing (measured at 6.6.16 with
    the tree's aarch64 cross compiler: raw 117 warns, raw 123 / 67 / 68 / 164 are silent) —
    their native declarations silence nothing now, and would matter only if those x86 names
    later get declared in both peers. So the per-family decision is `ptrace`'s alone: accept
    losing the setresuid-117 warning, or give `ptrace` a ≥1000 alias instead (as the 6.6.12
    xattr band did for the same reason); re-check with `programs/gen_syscall_xlat.cyr` when the
    slot opens.
  - **Acceptance**: every family named in `lib/syscalls_linux_common.cyr` (or the peer that owns
    it) with a Darwin arm, a row whose placement `esysxlat_row_order.sh` passes, and a runtime
    assertion in `tests/tcyr/crossos/` that fails when the number is wrong — the three tests
    v6.6.5 itself had to add.

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

---

## Open questions — standing defaults, not a queue

⛔ **This section was once titled "owed to the maintainer" and that framing is banned here. There
is nobody to owe: the maintainer is the person reading this.** A question parked as "owed" is a
deferral to nobody, and it is how several of these sat for months. The rule: **each item carries
a stated default and the work starts under it**; where a genuine fork remains it gets ASKED, in
one line, that turn — not recorded here and left.

The proof is on the record: `darshana-aarch64-syscall-shadow` sat as *"needs a call on where a
~350-row table lives"* until the call was simply taken (**generate it from the stdlib peers**),
whereupon it became 43 derived rows and shipped at `.51`. Assume the same of anything below.

1. **The self_compile budget — ANSWERED (user, 2026-07-29): the later performance track owns it.**
   The budget gets set as part of that track rather than pinned up front. Input for whoever opens
   it: **923 ms · 1,586,184 B at 6.6.19** (731–734 ms · 1,247,608 B at 6.6.1). A previously-floated candidate pair was *≤700 ms and
   ≤1.20 MB at minor close* — ⚠ **both halves are now exceeded**, so that pair is an input to
   re-decide, not a target that was missed. Review together with item 2.
2. **The self-compile growth-tax audit — ANSWERED (user, 2026-07-29): likely dropped, but
   re-review WITH item 1's performance track**, the two being the same subject. Explicitly *not*
   silently dropped — parked against that track's opening review, which decides whether it still
   earns a bite. Record the outcome here either way.
3. **macOS concurrency ordering — RESOLVED in 6.6.19** (placed 2026-10-02 with the tail plan): **T1** x86
   macOS starts real threads (raw `bsdthread_*`, per-thread TLS in the gs base, the `__ulock` channel shared
   with arm64, `THREADS_CONCURRENT` = `CHAN_BLOCKING` = 1 on both Mach-O arches); **A1** `async_await_readable_ms`
   on macOS and Windows over `fd_wait_ready`; **A2** the agnos peer over a readiness stash in the socket adapter.
   The legacy `async_await_readable` really waits on all three. CHANGELOG [6.6.19] *Threads / async*.
4. **A named struct argument over 8 bytes — SHIPPED 6.6.16 (C7)** (decided 2026-10-02, user accepted:
   it is a COPY, matching 6.6.12's field-argument copy and fixing a callee that mutated the caller's
   struct — `bump(p)` twice gave 4 then 5). The callee copies on entry, so it holds for every argument
   form, at top level and through fn pointers; a typed `self: T` follows it; an `async fn` refuses such
   a parameter by name; `p: *T` + `f(&x)` is the mutating spelling.

5. **Compiler-native trait objects (`dyn`) — ANSWERED (user, 2026-10-07, at the 6.7.1 open): CHECKED `dyn`, later in
   6.7.x** (the release-sequence row after Break 1). Static dispatch stays the default (ADR-004). `o: dyn Show` is an
   ordinary 16-byte `{data, vtable}` struct — no new value type (ADR-002's one-word model holds: it is a struct like any
   other) — the compiler builds and VERIFIES the vtable from `impl Show for T`, and `o.show()` is an indirect call
   visible in the declared type. Why, on the record: 7 repos use `lib/trait.cyr`'s fat pointer and ~15 more hand-roll
   vtables (szal, majra, agnosai, ganita, agnostik, …), all unchecked — a wrong slot or a missing method is a runtime
   crash, and static-only would leave them so for good. "Static first" was sequencing (arc A is the prerequisite of
   both), not ease. Migrating those repos is each repo's own job once it ships (filings).

*(Former item 3 — per-item `private` — was never a question. It is a live defect and is now
slot `.3` above. Former item 2, the bare-metal forbidden-module check, SHIPPED at v6.5.24 after
this section had carried it as "never built" for thirty releases.)*

---

## Standing notes — traps this minor must not re-learn

- **How a batched release runs (settled across 6.6.5–6.6.12).** Releases are strictly sequential;
  parallelism happens only INSIDE one, in git-worktree lanes where each file has exactly one owning lane
  and every cross-lane hunk travels as a named hand-off patch that lands at a named merge step. At most
  two `src/` lanes, and only one commits `build/cycc`; the binary is rebuilt once on the merged tree
  (fixpoint + seed-derive), `build/cycc-native-aarch64` once with `cyrius pulsar`. Ratchet and census
  final passes (`CORPUS_FLOOR`, `CYCC_CEIL`, the alloc census, the cross-compile allowlist, the
  self-sufficiency floors) are integration steps — a lane working in parallel cannot see the lanes it
  measures. **A per-lane green is not a merged green**: the full gate runs on the merged tree.
- **Fixing bugs is not hunting bugs** (user, 2026-09-29). One implementer + one reviewer per bite,
  reviewing THE BITE; an out-of-scope find goes to the *Potential backlog*, never automatically into a
  later release — only the user promotes. A severe find met in passing (security, silent corruption) is
  reported in one line, not swept for.
- **A CVE id is spent in the commit that records it**, and that commit moves BOTH counters (the
  September audit file's header and `CLAUDE.md`). 6.6.5's did not, and three reviewers had to report it.
- **Text handed into a cyrius string literal obeys the 6.6.11 lexer.** A driver `_gate("…")`
  description carrying a bare `"` or an unknown escape (`\<LF>`, `\q`) stops `programs/checks` compiling —
  it happened at the 6.6.11 merge. Hand-off text for descriptions must avoid both.
- **A sibling's CI runs isolated, never by hand-extracted steps.** Use a clean `git archive` copy with
  `path` deps commented out, a throwaway `CYRIUS_HOME` (a copy of the pinned slot, an EMPTY dep cache) and
  a throwaway `HOME`. At 6.6.12 a reviewer cut the wrong block out of bote's workflow and ran its
  "Install Cyrius toolchain" step against the live `~/.cyrius` (the active version flipped to 6.6.10 for a
  minute). Run the steps with GitHub's shell semantics: `bash -e` unless the workflow says `shell: bash`.
- **The `PARSE_RETURN` tail path has skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each fixed with the same narrow divert — the `_cfo`
  escalation shape, *"declared fixed, fourth occurrence in a path nobody enumerated"*. **Any new
  `PARSE_FNCALL`-resident transformation must be grepped against the tail path before it ships**
  — grep the SHAPE, not the operator.
  **FIFTH occurrence (6.6.7 bite 2): `defer`.** The tail path skipped the EPILOGUE's obligation,
  not PARSE_FNCALL's — every `return f(..);` in a fn with a `defer`/`secret var` jumped past the
  defer walker (CVE-47). By then the arm carried fifteen bolted-on diverts, not four; they are one
  predicate now (`_tc_must_divert`, parse_fn.cyr), so a new obligation is a new line THERE. And
  the walker the divert lands on must keep the whole return convention:
  **`EDEFER_SAVE`/`EDEFER_RESTORE` must preserve every return register of every return
  convention on x86, aarch64 AND cx** (x86: rax, rdx, r8, xmm0, xmm1; aarch64: x0-x3, q0, q1;
  cx: r0-r5) — a new return class that adds a register adds it there.
- **A filing's target list is a report about what the reporter builds, not about the bug.** The
  v6.6.1 DCE issue said *"PE / `--win` target only"*; x86 Mach-O shared the code path and was
  crashing on real Intel-Mac hardware, unreported, because the reporter does not build that
  platform. **Reproduce on every host that shares the path before scoping the fix.**
- **An all-identical codegen differential is not evidence a fix is inert — it is evidence of a
  corpus blind spot.** Three consecutive releases measured 0 diffs on real wrong-answer fixes.
  When a fix measures 0 diffs, add the shape to the corpus in the same release.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9 minors
  behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. Run the compiler on the
  hardware.
- **A "found by ports" test is worth more than the gate that says the code compiles.** v6.5.7's
  compile-only wrapper gate proved the wrappers *compile* on five targets — most of the risk, none
  of the bugs. The one `.tcyr` that RAN them found **seven** defects, five of which were half-fixes
  that stopped at the first symptom. Whenever a slot adds a platform-facing verb, the
  `tests/tcyr/crossos/` file is the deliverable, not the nice-to-have.
- **A gate fixture in the wrong order is a vacuous gate**, and a gate whose fixture shares the
  implementation's assumption proves nothing at all (the v6.5.49 `entry`/`src` case). Mutation-prove
  the gate *and* check that the mutation is reachable.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.** The
  retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got cited to
  file against *sigil*. This is the language repo: when the compiler cannot compile valid cyrius,
  fix the compiler. Premise-check **rules**, not just pins.
- **Re-derive every count in this file at slot entry.** The head line above was version-stamped
  correctly and wrong in five metrics simultaneously; the previous edition carried a gate count
  seven higher than the tree. A number in a roadmap has nothing checking it.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

- **Atomic commits, packed releases.** One logical change per commit; a release bundles many.
- **A bug ships complete** — no granularity by gnarliness, no slicing the hard half into the next
  patch.
- **Only the user pivots focus.** Surface findings; never unilaterally redirect or defer.
- **Release gate GREEN before every `.NN`** — self-host fixpoint · seed-derive · check.sh ·
  cross-OS on ecb/ach/cass/pi (REAL hardware) · bench. Never tag with the gate RED.
- **Benchmark every release**, recording self_compile + cycc size in the CHANGELOG entry.
- **An audit's output is fixes, not a backlog.** File only when the fix genuinely cannot pack —
  and name the reason.
