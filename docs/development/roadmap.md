# Cyrius Development Roadmap — v6.5.x (active minor)

**Scope** — the **current active minor only** (v6.5.x). This is the slot-pinning working
artifact: the committed slot sequence, the reactive windows, and a code-grounded size for
each arc. The whole-cycle framing plus v6.6.x/v6.7.x/v6.8.x live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slot sequence) → [roadmap_6.md](roadmap_6.md)
> (v6.6.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: v6.6.x
  language-ergonomics (const-eval, the bounds-check mode, trait-bounded generics),
  v6.7.x/v6.8.x RISC-V rv64, and the cycle-level budgeting reference points.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger** (the doc you open, run, and log against).
- [state.md](state.md) — volatile current state (version, cycc size, in-flight slot). Refreshed
  every release by `version-bump.sh`.
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.5.57** (2026-09-05) — cycc **1,200,792 B** (.text 1,050,000) · `check.sh` **GREEN** · seed-derive **GREEN** · **297** `.tcyr` (**64** in `crossos/`) · **102** `lib/*.cyr` · **125** shell gates under `tests/gates/<bucket>/` · self_compile **668 ms** · **4 open issues + 3 open proposals**.

⛔ The previous head line ended "every remaining issue is an arc or a maintainer decision, not a patch". **There is no maintainer to hand work to — the user is the maintainer**, so "maintainer decision" is a deferral to nobody and must not appear in this repo's docs. It was also wrong on the facts: `.54` shipped from the top of that supposedly-undoable list, and its premise (a recorded IR=3 cost of +3.6 % compile time) turned out to be **off by 20×**. ⚠ The same line also carried **119** shell gates when `find tests/gates -name '*.sh' | wc -l` said **124** — re-derive these counts, never increment them.

⛔ **THE v6.5.x MINOR IS NOT CLOSED, AND THIS LINE SAYING IT WAS IS THE DEFECT.** It read *"The
v6.5.x minor is CLOSED. Band K finished it at `.45`–`.47`"* while **`.48` through `.56` — nine
releases — shipped into the minor** and four issues stayed open. The consequence was not
cosmetic: with the minor marked closed there was no slot list, so nine releases of work were
selected ad hoc and the open issues were pinned to nothing. Band K closed a BAND, not the minor.

⭐ **What closes v6.5.x is stated below and nowhere else: the four open issues, decomposed into
numbered slots with acceptance criteria.** When those land the minor closes and the next release
is v6.6.0.

⚠ **This section was stale for eleven releases and that is the reason it now carries live
figures only.** Until 2026-09-04 it read "Current head: v6.5.48" while quoting `.37`-era numbers
throughout — cycc 1,179,104 B, check.sh 211/0, 14 open issues — and still announced that "`.38`
is the next open number". Every figure above was re-derived on the day, not carried forward.

**What is ahead** is [`roadmap_6.md`](roadmap_6.md) (v6.6.x onward) and the re-triaged backlog
below. Nothing in this file is a live slot pointer any more.


## Open work — re-triaged 2026-09-05 against LIVE code (`.55` sweep)

Every row below was verified by reading or running the live tree, never against an issue file's
or a roadmap row's own claim. That distinction is not ceremonial: this sweep found the previous
"8 open" list naming an item **closed at `.44`**, omitting three that exist, and describing `R2`
as deferred when it **shipped at v6.4.26**.

**Verdict key** — `LIVE` reproduced · `PARTLY` some sub-items shipped · `ARC` multi-release,
pinned below with an opening version.

⛔ **There is no `DECISION`/`maintainer` verdict any more, and its removal is the point.** Three
rows carried it and it was a deferral to nobody: the maintainer is the person reading this, who
had already asked twice for these to be fixed. Where a row genuinely turned on a choice, the
choice gets made with a stated default and the work starts. `darshana-aarch64-syscall-shadow` was
the proof — it sat as "needs a maintainer call on where a ~350-row table lives" until the call was
taken (**generate it from the stdlib peers**), whereupon it became 43 derived rows and shipped at
`.51`. Assume the same is true of anything below that looks like it needs permission.

| Item | Verdict | What is actually left | Size |
|---|---|---|---|
| `ir-regalloc-rewrite-needs-reemit` | **PARTLY SHIPPED `.54`** | ⛔ Its stated cost was WRONG BY 20×: the file said `CYRIUS_IR=3` was "+3.6 % compile time"; live it was **13,967 ms against 672 ms**. `.54` fixed both halves — `ir_build_edges` now resolves jump targets function-locally (**→ 1,012 ms**) and the NOP-harvest compactor runs under IR mode (**19,067 NOPs → 8,249**, `.text` at parity). What is left is a **whole-program compaction pass after the IR fixpoint** to collect the remaining 8,249, which are the IR passes' own eliminations. ⭐ The prize CHANGED SIGN: IR=3 is no longer 6.2 % larger than the default build, so this is now worth ~8–12 KB **smaller** — the first real size payoff from the IR optimizers. | 1 release |
| `simd-f64v-memory-operand` | **PARTLY SHIPPED `.52`/`.53`** | ⛔ Its stated blocker was WRONG: "the picker only recognises REX.W mov" is true of the code and the wrong lever — **SysV has no callee-saved XMM**, so a vector cannot survive a call and every chain link WAS one. `.52` inlined the wrappers (24→16 ms) and `.53` widened LASE to 128-bit pairs (18→15 `movupd`). Left: the 15 remaining reloads are **not adjacent** to their store, so closing them needs real vector liveness — now possible because the calls are gone. **Re-measure the prize before pinning.** | unpinned |
| ~~`v6415-closeout-residuals`~~ | **✅ CLOSED at `.50`** | All three parts resolved. D1 deleted nine definition-only IR fns (−174 lines, unreachable floor 84 → 75). The "do NOT name-sweep" warning was load-bearing and honoured — `ir_dce_capped`/`ir_dead_store_capped` are LIVE and contain the dead names as prefixes. D2 had already been resolved by execution at `.35`. | done |
| `stiva-stackless-coroutines` | **ARC → unpinned** | Half A (multi-waiter registry) shipped `.26`. Half B is a CPS transform: liveness-across-suspend, locals-to-frame lifting, a per-`async fn` state machine. Ordered last because the consumer that justified pulling it forward no longer blocks on it — that is a PRIORITY input, not a reason to leave it unpinned. | arc |
| `sock-send-result-allocates-per-call` | **PARTLY SHIPPED `.55`** | Symptom shipped `.41` (`ok_via`/`err_via`); the COMPILER capability shipped `.55` as **`enum Name: stack`** — payload variants return `(tag, payload)` in the multi-return register pair, **measured zero allocator growth**. ⛔ The "24 declarations, 516 construction sites" figure was a raw grep line-count including prose; live it is **9 declarations / ~306 real occurrences** in this repo, and only **3 distinct stdlib types** ecosystem-wide (Option/Either/Result) plus 6 in one test file. ⛔ "cycc's source cannot validate this" is HALF TRUE — only the byte-identity gates are vacuous; `check.sh` runs the corpus behaviorally and does detect representation defects. Left: the **ecosystem half** — migrating Result/Option/Either themselves, which needs `?` to accept a pair, `is_ok`/`result_unwrap` rewritten, and the hand-rolled `load64(+8)` reads updated across sibling repos. | 1 release, cross-repo |
| ~~`darshana-aarch64-syscall-shadow`~~ | **✅ CLOSED at `.51`** | Both halves diagnose. The raw-literal half shipped via a **generated** 43-row correspondence (`programs/gen_syscall_xlat.cyr`), not the ~350 hand-maintained rows the filing assumed. ⛔ The table-free heuristic misses the 10 worst cases (`uname` 63 = **read**), and the naive table warned **510×** on cycc's own correct source; two derived exclusions took in-tree false positives **525 → 0**. | done |
| ~~`compile-time-superlinear-in-fn-count`~~ | **✅ CLOSED at `.51`** | Compile time is now LINEAR (flat ~5.3 µs/fn, 34k→120k). Cause was the fn-name hash running to **100 % load** before every doubling — max probe 65,263, 31.5 M probes/compile; two slots per entry → max probe 38. ⛔ Every previously-proposed cause was wrong: `_fnt_grow` costs **4–9 ms total** (not 1145), the DCE walk is off by default and never ran, and load factor alone was misleading. | done |
| ~~`test-runner-bounded-gate-intermittent`~~ | **✅ CLOSED at `.50`** | The proxy-vs-property read was right, but ⛔ **the filing's leading hypothesis was REFUTED**: a zombie's argv collapses to `[test_bin] <defunct>` and cannot match the sampler's PATH pattern, so the recommended state-filter fix would have been a no-op. Axis 1b now requires two CONSECUTIVE samples; the abandon-mutation still trips it at 19. | done |

### Closed by the `.55` sweep

- **The cross-OS leg never RAN a payload-enum constructor on any host** — 1 of 63 `crossos/`
  files even mentioned one, as an unused include, and `CYRIUS_DCE_VERBOSE=1` reported
  `dead: Ok` / `dead: Err` / `dead: Some` on every target. Closed at `.55`;
  crossos is now **64** files and all four hosts run them.
- **No test held two payload-enum values from one call site alive at once** — the exact shape
  v6.5.15 broke. Closed at `.55` by `tests/tcyr/lang/payload_enum_retention.tcyr`,
  mutation-proven against a silent aliasing defect.

### Closed by the `.51`/`.54` sweeps

- **`ERR_MSG` hardcoded-length audit** — carried since v6.4.57 as "the never-done half". Done at
  `.49`: two `WARN` sites declared **45** bytes for a **41**-byte literal, each leaking 4 bytes
  past the string. ⚠ `.47`'s `write_literal_lengths` gate had missed them because it covered only
  `sys_write` / `syscall`; it now covers `ERR_MSG` and `WARN` too — **1298** sites checked.
- **`macos-threading-workers-dont-run`** — closed at `.44`, archived, but still listed here as
  open until today.


## Remaining repair arcs — version-pinned, named for what they do

⛔ **THE BAND LETTERS ARE RETIRED FOR FORWARD WORK.** Bands A–F and K are shipped history and
stay named that way in `completed-phases.md` and the CHANGELOG, because that is what the commits
say. But "band G" as a *pointer to unstarted work* told a reader nothing: it survived four
releases in `state.md`'s **Next up** row without anyone being able to tell from the name what
would change, and a name that carries no content is how an item sits unstarted while still
looking tracked. Forward arcs are pinned to an opening version and named for the thing they fix.

⚠ **An arc is 1–2 releases** (CLAUDE.md: *"Arcs are 1–2 releases, not per-phase releases"*), so a
pin is an ORDER with an opening version, not a promise that each takes exactly one `.NN`.

⛔ **Two of the pins in this section turned out to name the WRONG BLOCKER, and both were only
caught by measuring at slot entry.** `.52`'s said the SIMD problem was the allocator's byte
matcher when it was an ABI fact (no callee-saved XMM). `.54`'s carried an IR=3 cost that was off
by **20×** because the number had been copied forward for releases without being re-taken. Neither
error was visible from inside the document — cross-checking the roadmap against the issue files
only ever confirmed them, because both said the same thing. **Re-measure at slot entry, against
the running compiler, before coding to any pin below.**

### UNPINNED — vector register class: keep f64v values in registers across a chain
*(was "`.52`", was "band G item 1"; issue `2026-07-06-simd-f64v-memory-operand-no-register-residency`)*

⛔ **THIS SECTION'S STATED BLOCKER WAS WRONG AND WAS CORRECTED AT `.53`. Do not code to the old
text.** It said the blocker is that "the allocator's picker only recognises REX.W `mov` to/from
`[rbp+disp32]` (`parse_fn.cyr:4567`), so no xmm/ymm local is ever a candidate". That is a true
statement about the code and the WRONG LEVER, for an ABI reason rather than a missing feature:
**SysV has NO callee-saved XMM registers** — xmm0-15 are all volatile — so a vector value cannot
be held in a register across a call at all, and before `.52` every link of a value-form SIMD
chain WAS a call. Widening the picker would have allocated registers that every call immediately
invalidated.

**What actually shipped instead, and it was the right order:** `.52` inlined the value-form SIMD
wrappers (removing the calls — the precondition), and `.53` extended LASE to 128-bit store/load
pairs, taking a 3-link f32v4 chain from 18 `movupd` to 15 and 15 ms to 14 ms.

📎 The `.52`/`.53` implementation detail that used to live here (the four-defect inline-replay
bisect, the "why the obvious first move fails" table) is shipped history: it is in the CHANGELOG
and in vidya as `an_inline_replay_that_binds_params_BY_NAME_hides_four_defects_at_once` and
`no_callee_saved_XMM_on_SysV_means_a_vector_cannot_survive_a_call`. The defect it warned about was
fixed at `.52`, so it is no longer a trap to avoid — it is a lesson already banked.

📌 **What is genuinely left**, measured at `.53`: 15 `movupd` persist because most reloads are
**not adjacent** to their store — an intervening store to a different slot separates them, and a
windowed matcher does not help (windows 0/1/2/3 all catch the same 3 pairs). Closing the rest
needs real liveness for a vector register class, which is now *possible* because the calls are
gone. Unpinned rather than re-numbered: re-measure the remaining prize before spending a release
on it.


### `.54` — ✅ SHIPPED: make `CYRIUS_IR=3` a viable path (was "`.53` regalloc re-emit")
*(issue `2026-07-02-ir-regalloc-rewrite-needs-reemit`)*

⛔ **The slot's own premise was wrong and the correction is the finding.** This slot was scoped
from a recorded IR=3 cost of "+3.6 % compile time, +6.2 % size". The size half was right; the time
half had been carried forward across releases without being re-measured and was **off by a factor
of twenty** — live, IR=3 took **13,967 ms** against the default path's **672 ms**. Re-take a number
before you plan around it.

Both defects are fixed and IR=3 is now **1,012 ms and at exact `.text` parity** with the default
build (NOPs 19,067 → 8,249): `ir_build_edges` no longer resolves each jump by scanning the whole
program, and the NOP-harvest compactor is no longer disabled under IR mode — which needed a repair
pass for the IR's node→CP table, without which the IR-built compiler dies with
`alloc_init: mmap failed`. See CHANGELOG [6.5.54].

📌 **Residual, and it has changed sign.** The remaining 8,249 NOPs are the IR passes' own
eliminations, written after every per-function compaction has run, so only a whole-program pass
after the IR fixpoint collects them. That pass is no longer a repair for a regression — IR=3 is at
parity now — it is worth roughly **8–12 KB smaller than the default path**, which would be the
first real size payoff from the IR optimizers.

### `.55` — ✅ SHIPPED: `enum Name: stack` — payload variants that do not allocate

⛔ **The slot's framing named the wrong blocker, and the correction is the finding.** The plan
said acceptance could not come from cycc because "cycc's own source cannot validate this
change". That is only half true: `src/` really has no payload enum, so the byte-identity gates
are vacuous — but `check.sh` runs the 294-file corpus BEHAVIORALLY and does detect
representation defects (verified by differential against a deliberately-broken compiler). The
real blind spot was elsewhere and nobody had named it: **the cross-OS leg never RAN a
payload-enum constructor on any host.** One of 63 `crossos/` files even mentioned one, as an
unused include, and `CYRIUS_DCE_VERBOSE=1` listed `dead: Ok` / `dead: Err` / `dead: Some` on
every target. A representation defect would have shipped green through ecb/ach/cass/pi.

⭐ **And the standing design note was a CLOSED SET that had dropped the answer.** It read:
caller-frame storage is too short-lived, a global too shared, "therefore no relocation-based
design can work; the survivors are escape analysis or a scope-tied arena with reclaim" — so
every revisit re-derived escape analysis and judged it too large. The omitted option needed no
new machinery: the multi-return ABI has shipped since v5.10.45, and **copy semantics removes
both v6.5.15 failure modes at once** — each binding is its own copy of two registers, so two
values built at one call site cannot alias and there is no storage to dangle into.

`enum Name: stack { V(x); }` returns `(tag, payload)` in that pair. **Measured zero allocator
growth**, including 16 constructions in a loop. Opt-in: the boxed layout is the DOCUMENTED
representation (`?` desugars to `load64(rax + 8)`; ~300 sites read +0/+8 by hand), and a pair
read as a pointer is a plausible-looking address, so flipping the default would break them
silently. Verified inert — byte-identical on all six payload-enum corpus files. See
CHANGELOG [6.5.55].

📌 **Residual: the ECOSYSTEM half.** Migrating `Result`/`Option`/`Either` themselves to the
value form needs `?` to accept a pair, `is_ok`/`result_unwrap` rewritten, and the hand-rolled
`load64(+8)` reads updated across the sibling repos. The compiler capability it was waiting on
now exists.

### `.56` — ✅ SHIPPED: the LEXID prefix-compare P0 (found by slot entry, not by a filing)

Neither of the two defects `.56` fixed was on the open queue. Both were found by the slot-entry
premise-check, which is the argument for running one: **identifier dedup was a PREFIX compare**,
so `var ah = 7; var ahxaa = 99;` read `ah` as 99 — two names became one symbol, in five shipped
releases, across 127 repos. And `private fn h()` compiled with no diagnostic while privatising the
whole file. See CHANGELOG [6.5.56].

### THE SLOT LIST — what remains of v6.5.x

Every open issue is pinned to a numbered release with acceptance criteria. Sizes come from the
`.56` slot-entry premise-check, which measured each one by running the compiler.

⚠ **"It is an arc" is a size, not a plan, and it is what this list previously said instead of
decomposing the work.** Each row below states what SHIPS in that release and what must be true
for it to be done.

#### `.57` — aggregate assignment copies every word *(in flight)*
*(closes `2026-09-05-aggregate-assignment-truncates-to-8-bytes`)*

Three fixes, one defect surface: the assignment path gets the multi-word copy the declaration path
has had since the struct-byval work; `_try_struct_copy_init` learns vector descriptors (it fell
through to a scalar init for `var B: f32v4 = src`); and the register-allocator picker stops
promoting an aggregate's non-base words — latent since the picker existed, because a field is
reached as `lea rcx,[rbp+base]` so only the base slot ever appears as an rbp disp.

**Done when:** `aggregate_copy_all_words.sh` green across struct 2/3/4-slot, f32v4, f64v2, both
assignment and declaration forms, self-assignment, three-live-aggregates (the regalloc axis), and
a scalar control · mutation-proven per fix · release gate green.

#### `.58` — SIMD wrapper inlining reaches every wrapper shape
*(`simd-f64v-memory-operand`, part 1 — **user-selected next**)*

`_fn_has_simd_param` (`util.cyr:989-996`) loops `i < pc` over `GLTYPE(S,i)`, but a wide param's
SLTYPE lives on its NAMED slot, which sits after `slots-1` anonymous fillers. The named slot falls
inside `[0,pc)` only when `slots-1 < pc` — true only for **two 128-bit params**. This is the same
off-by-slot bug `.52` fixed in `SFINL`, left unfixed in the gate that decides whether to look. So
`f64v4_add(a,b)` — the family the issue was filed about, from svara — still emits a `callq` per
link. `pc > 2` (`parse_fn.cyr:4530`) separately excludes the 3-param `_fmadd` wrappers.

**Measured today:** 3-link f64v4 chain, 2M iterations = **72–78 ms with 3 `callq` and 20
`movupd`**, against 4 ms for `gcc -O2 -mavx2`. The equivalent f32v4 fix at `.52` was 24 → 16 ms.

**Done when:** a 1-param 128-bit wrapper, a 1-param 256-bit wrapper and `f64v4_add(a,b)` all
inline (no `callq` per link, verified by disassembly) · the f64v4 chain time drops measurably ·
corpus byte-identical outside the SIMD tests · gated on real hardware, because the value-form SIMD
ABI differs per target.

#### `.59` — kill the round-trips inlining exposes
*(`simd-f64v-memory-operand`, part 2)*

Two cheap wins measured at `.53`/`.56`, neither needing the register class. **(a)** A 128-bit arm
for `DSE_PASS` (`parse_fn.cyr:2525-2563`, currently `48 89 85` only): 3 of the 11 remaining stores
in a 3-link f32v4 chain are provably never read once LASE removed their reloads — 15 `movupd` →
12. Same shape as `.53`'s LASE arm. **(b)** Constant-`n` loop elision in `EMIT_F32V_LOOP` /
`EMIT_F64V_LOOP`: every value-form wrapper passes a literal `n` equal to one register width, so
the loop always runs exactly once — removes ~14 of ~33 instructions per link plus the pointer
spills.

⚠ **Do not scope a release around (b) alone.** Instruction count is not the cost here: a C/SSE
proxy with 16 instructions per iteration but 5 serialized store→reload round-trips measured
**slower** than cyrius's 66-instruction path. Removing scaffolding without removing round-trips is
worth ~20–25 %, not a multiple.

**Done when:** `movupd` count drops on the gate's own fixture, timing improves, and the corpus is
byte-identical outside SIMD.

#### `.60`–`.61` — the vector register class
*(`simd-f64v-memory-operand`, part 3 — closes the issue)*

Only now, because until `.58` lands every chain link crosses a call and **SysV has no callee-saved
XMM**, so any measurement before that is of the wrong thing. Needs: (a) xmm0-15 modelled as a
**caller-saved** class with intervals split at every call — the existing picker's "hold in a
callee-saved register for the interval" model does not transfer; (b) value-form ops emitting
reg-reg-reg instead of the memory kernel; (c) real 16/32-byte liveness, since the current
per-local safety scan is byte-pattern and 8-byte-only.

**Done when:** the **svara formant bench closes to single-digit-× of the Rust baseline** — this is
the minor's stated acceptance anchor and the reason the arc exists.

#### `.62` — payload enums stop allocating for real
*(closes `sock-send-result-allocates-per-call`)*

`.55` shipped the compiler capability (`enum Name: stack`). This is the ecosystem half: teach `?`
to accept a `(tag, payload)` pair (it currently desugars to `load64(rax + 8)`, i.e. it
dereferences), rewrite `is_ok` / `is_err_result` / `result_unwrap` / `err_code_of` for the value
form, migrate `lib/result.cyr` + `lib/tagged.cyr`, and update the hand-rolled `load64(+8)` reads
(6 in `lib/bayan.cyr`). Then re-vendor.

⚠ Scope check from `.55`: the "24 declarations / 516 sites" figure was a raw grep count including
prose. Live it is **9 declarations / ~306 occurrences** here, and **3 distinct stdlib types**
ecosystem-wide.

**Done when:** `Result`/`Option`/`Either` construction allocates **0 bytes**, every existing
consumer still compiles, and crossos is green on all four hosts.

#### `.63` — whole-program NOP compaction
*(closes `ir-regalloc-rewrite-needs-reemit`)*

The `.54` residual: 8,249 NOPs are the IR passes' own eliminations, written after every per-function
compaction has run, so only a pass after the IR fixpoint collects them. Needs the IR passes to
register their NOP runs program-wide, then repair jump disp32s (decoder-based, via `CLASSIFY_CF` /
`CF_TARGET` in `backend/x86/decode.cyr`), fixup-table CPs, switch-table entries, function offsets
and `IR_NODE_CP`.

⚠ Rated **live-but-low-value** at `.56`: prize smaller and price larger than the issue file
claimed, and IR=3 is already at `.text` parity. It is last of the code work for that reason.

**Done when:** IR=3 `.text` is measurably smaller than the default build and an IR=3-built cycc
still reproduces the default cycc byte-identically.

#### Stackless coroutines — **RECOMMEND MOVING OUT OF v6.5.x**
*(`stiva-stackless-coroutines-interactive-exec`)*

Genuinely unbuilt and verified broken (a task calling `async_wait_fd` re-enters its body from the
top; an unconditional park never terminates). But measured at `.56`: **no consumer** — the filing
repo records no block — and **zero non-comment `async fn` uses anywhere in the ecosystem**. Two
releases of compiler-level CPS transform for a feature nothing uses.

**This is the one call in this list that is genuinely the user's**, because it is a priority
question and not a technical one: move it to v6.6.x, or keep it as `.64`–`.65` and close the minor
after it.

#### Then v6.5.x closes → v6.6.0


## The slot sequence — CLOSED

The v6.5.x minor is closed (band K, `.45`–`.47`). This section carried **seven stacked per-slot
blocks** — each once the "▶ NEXT" pointer, each superseded by the next and kept "for lineage" —
plus the four spent reactive windows W1–W4. That is closed-minor narrative, and it is now in
[`completed-phases.md`](completed-phases.md#v65x--bands-and-what-each-actually-delivered) and the
CHANGELOG.

⚠ **Removed 2026-09-04 because it had started to mislead, not merely to bulk.** A band-K audit
found roadmap rows here describing already-shipped fixes as live defects, and the "8 open"
repair backlog named an item closed at `.44` while omitting three that existed. A stale pointer
is worse than no pointer: someone codes to it.

**What is still ahead lives in [`roadmap_6.md`](roadmap_6.md)** (v6.6.x onward) and in the
re-triaged backlog below.

## Standing notes — traps this minor must not re-learn

- **The `PARSE_RETURN` tail path has now skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each was fixed with the same narrow divert. That is the
  `_cfo` escalation shape — *"declared fixed, fourth occurrence in a path nobody enumerated"*.
  **Any new `PARSE_FNCALL`-resident transformation must be grepped against the tail path before
  it ships** — grep the SHAPE, not the operator.
- **An all-identical codegen differential is not evidence a fix is inert — it is evidence of a
  corpus blind spot.** Three consecutive releases: 6.5.0 was 0/253, 6.5.1's arity fix 0/253,
  6.5.2 0/253 — each a real wrong-answer-or-crash fix. Same finding as v6.4.80's 251/251. When
  a fix measures 0 diffs, add the shape to the corpus in the same release. (The corpus is
  **260** at 6.5.10; quote the live count, not these historical denominators.) The 6.5.8
  `i64::MIN` sweep is the same lesson from the other side: a **5,500-assertion suite** missed
  arena exhaustion because allocation tests are small-fixture by nature and nothing in them
  probed the ceiling.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9
  minors behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. `ach` became a
  first-class gate host at v6.4.59 after the Intel-Mac toolchain rotted ungated for ~2.5
  minors. Run the compiler on the hardware.
- **7 of the 16 open issue files still carry a "re-verified against live code at the v6.4.82
  closeout" header** (re-counted 2026-08-07; the other 9 were filed after that closeout and
  carry no re-verification stamp at all, which is the same problem wearing different clothes).
  v6.4.82 is three minors of releases stale, and it is exactly how the xmkdir filing came to
  re-assert `xrmdir` as missing **two days after 6.5.2 shipped it**. The header pattern is
  load-bearing — it is what makes a file trustworthy at a glance — so the re-verification stamp
  must move with each sweep or it becomes the rot it was designed to prevent. **Four of the 16
  are outright shipped-but-unarchived** — see the ⚠ note under *Where we are*.
- **A "found by ports" test is worth more than the gate that says the code compiles.**
  v6.5.7 shipped `tests/gates/platform/syscall_wrapper_pass.sh`, which proves the new wrappers *compile* on
  five targets — most of the risk, and none of the bugs. The one `.tcyr` that actually RAN
  them on hardware found **seven** defects, two of them pre-existing rot (`xrmdir` broken on
  macOS-arm64 since the day it shipped; a macOS-x86 `Stat` enum mixing two structs). Five of
  the seven were **half-fixes that stopped at the first symptom**. Whenever a slot adds a
  platform-facing verb, the `tests/tcyr/crossos/` file is the deliverable, not the nice-to-have (this said `vr01_`; see the standing correction).
- **A gate fixture in the wrong order is a vacuous gate.** Twice in v6.5.10 a mutation axis
  passed against deliberately-broken code because the fixture's decoy sat *after* the real key
  and the scan stops at its first match; v6.5.8 hit the same shape assuming `dir_walk` ordering.
  Mutation-prove the gate *and* check that the mutation is reachable.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.**
  The retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got
  cited to file against *sigil*. This is the language repo: when the compiler cannot compile
  valid cyrius, fix the compiler. Premise-check **rules**, not just pins.

### UNVETTED filings — ✅ all three now CLOSED (kept for the lesson)

Three issues were authored by subagents and never reviewed by the maintainer. **All three
have since shipped** — xmkdir at **v6.5.7**, the `i64::MIN` formatter class at **v6.5.8**, the
mutex wake at **v6.5.9** — so the `[UNVETTED]` marks are retired from the slot table above.
The section stays because **what the outcomes proved is the durable part**: every one of the
three was *understated or mis-evidenced in the same direction*, and each shipped fix was
bigger than its filing. All three were reproduced by running code or a bench at 6.5.2 and all
three described **real** defects — but their evidence, not their conclusions, was the suspect
half:

- **`2026-07-29-no-portable-xmkdir-in-io-cyr`** — two false claims. It says the `x*` set has no
  `xrmdir` (it does — `lib/io.cyr:134`, shipped 6.5.2, with a CHANGELOG heading of its own) and
  that *"`lib/kavach.cyr` calls the unguarded form at eight sites"* — **`lib/kavach.cyr` does
  not exist in this repo**; the live raw callers are `lib/yukti.cyr:1801` and `:5270`, two
  sites, `sys_mkdir(cstr, 493)`. It also never makes its own sharpest argument: **`mkdir` is
  the one member of the family whose ARITY MATCHES** (2 args on every target — `(path, mode)`
  vs agnos's `(path, pathlen)`), which is precisely why 6.5.1's arity escalation is
  structurally blind to it and `folds_agnos_parity.sh` passes without catching it. It is the
  **last remaining member of the arity-identical-but-semantically-divergent class**.
- **`2026-07-29-fmt-int-buf-i64-min`** — no false claims; **understated**. It asks whether other
  formatters share the shape. They do: 7 sites, not 1.
- **`2026-07-29-mutex-unlock-unconditional-futex-wake`** — no false claims; one number not
  reproducible from the attached repro. Its `chan_try_send + chan_try_recv = 1.590 µs` row does
  not come out of the committed `.bcyr` (that harness emits only `nop_loop`/`alloc_16`/
  `atomic_cas_hit`/`mutex_lock_unlock`; measured 1 / 10 / 6 / 382 ns). The `.bcyr` header is
  honest about it; the issue body presents the row in the same measured table. The mechanism is
  independently verified via the `thread.cyr` call sites, so it is understated, not wrong.

**Read this as a signal about how subagent-authored filings fail: the conclusion survives, the
evidence does not.** Re-derive every line reference and count before acting on one.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- ~~**`#derive(Serialize)` / `#derive(Deserialize)` on an ENUM — generate the codec**~~ —
  ✅ **SHIPPED v6.5.31**, archived to `issues/archived/2026-08-19-derive-serialize-enum-support`.
  The blocker was never effort, it was the wire-shape contract; the maintainer settled it
  (**name string** + **`Result`**) and the implementation followed the same day. Both
  directions shipped — the parse side is the half ranga could not emulate. A pre-existing
  sibling defect went with it: a bare `#derive(Deserialize)` emitted nothing on **structs**
  too, because the codec body was only reached when `Serialize` happened to be stacked.

- **Embed data files as source strings — an `[embed]` / assets manifest section**
  (`proposals/2026-08-10-embed-data-files-as-source-strings`) — ⛔ **added 2026-08-11 by the
  placement-rule audit, which found it referenced in NONE of `roadmap.md`, `roadmap_6.md`,
  `roadmap-future.md` or `state.md`. It was completely homeless** — the third instance of that
  shape after the cx indirect call and the `net.cyr` arch guards, both caught by the 2026-08-07
  sweep. Ergonomics, not capability: the generated-`.cyr` idiom already works and is fleet-wide
  (`kashi_font_data.cyr` vendored in 6 repos, `shabdakosh/programs/gen_cmudict.cyr`,
  `kavach/src/scanning_data.cyr`, `ghurni/src/presets.cyr`), so nothing is blocked — agnosai
  shipped its generator and pins 6.5.19. **Sequence it after `CYRIUS_PKG_VERSION`** (Slot 1b):
  the proposal names that as its sibling, both are "a build-time value that source cannot
  read", and the smaller one should define the shape. Candidate for the v6.6.x ergonomics list.

- ~~**Tuples — lightweight multi-value returns**~~ — ✅ **SHIPPED v6.5.21**, archived to
  `proposals/archived/2026-08-13-tuple-multi-value-returns`. ⛔ **This entry, as originally
  written here, repeated the proposal's FALSE premise** ("ergonomics, not capability... nothing
  is blocked") and is kept only as the correction. Two-value multi-value return with
  destructuring had shipped at **v3.7.2** — `return (a, b);` + `var q, r = f();` — four majors
  before the filing; the proposal's table tested `return a, b;` and `var (x, y) = f();`, which
  differ only in where the parens go. Our own vidya entry (`language/features.cyml →
  ret2_rethi`) documented the paren-less form under a heading reading "NATIVE MULTI-RETURN",
  so a consumer following CLAUDE.md's search-vidya-first rule got the wrong syntax from the
  authoritative source. What was genuinely missing and shipped at `.21`: **arity 3** (the one
  real capability gap — `_dd_pow10`), a **declared return type** `fn f(): (f64, f64)` making
  arity checkable at a forward call, a **destructure contract** (there was none — `var q, r = 42;`
  compiled, and `dm(17,5) + (k/9) - 11` put the idiv REMAINDER in `r`), and **three silent
  miscompiles** the proposal never knew about: cx returned the first value twice (return-0
  emitter stubs), a `: f64` tuple lost its first value to a stale xmm0 on x86/PE — the exact
  Dekker shape — and f64 type was lost at the binding, which is why the `: f64` RETURN
  annotation had two uses ecosystem-wide, both in our own tests. **The lesson worth keeping:
  a consumer-filed capability table is a report about OUR docs as much as about the language —
  premise-check it against a RUN BINARY, not against the filing.**

- **`lib/net.cyr` AF_UNIX surface** (was §9 of `2026-07-30-net-cyr-x86-only-socket-syscall-numbers`,
  archived v6.5.12) — a yes/no DESIGN call for the maintainer, not a defect: whether `net.cyr`
  grows a Unix-domain socket surface alongside INET. Landed here rather than left in the issue
  queue when the rest of that filing resolved — §3 disarmed at v6.5.7, §4 premise-disproved on
  real pi, and the silent net.cyr ⇄ ESYSXLAT coupling gated at v6.5.11. Nothing blocks on it.

- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks
  (`main`, `main_aarch64`, `main_aarch64_macho`, `main_aarch64_native`, `main_cx`, `main_win`,
  `main_x86_macho`); no shared pass-1 dispatch helper. This is a recurring-bug class, not
  cosmetics: `#io` v5.8.20, `#pure` v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute
  needed return-0 stubs in aarch64 + cx and only `cass`'s `cycc_cx` caught the miss.
  Logic-preserving ⇒ gate is byte-identical self-host on all four hosts + seed-derive.
  Premise-check the fork count at slot entry.
- **DWARF debug-info emission** — backend/codegen work; it emits debug sections into the object
  file. Slot it when a real debugger story is needed. Distinct from the DX diagnostics arc,
  which was only the error-reporting layer.
- ~~**cx has no indirect call**~~ — **✅ SHIPPED v6.5.13, struck 2026-08-11.** `.cyx` opcode
  **105 (`callind`), PERMANENT**: `fn ECALLIND` is real at `src/backend/cx/emit.cyr:501`, the
  matching cxvm arm is at `programs/cxvm.cyr:272`, and the issue is archived `✅ RESOLVED
  v6.5.13` with `tests/gates/codegen/cx_indirect_call.sh` (8 assertions) green. Verified
  against **live code**, not the file's own claim. ⚠ This bullet was added by the 2026-08-07
  sweep *because the item "had no roadmap home at all"* — and it had in fact shipped six
  releases earlier. **The reason both this list and `roadmap-future.md` went on carrying it as
  open is that `## [6.5.13]` has an EMPTY CHANGELOG body**, so there was no canonical line to
  reconcile against. Backfill that entry.
- **`lib/net.cyr` hardcodes seven x86-only socket syscall numbers with zero arch guards**
  (`2026-07-30-net-cyr-x86-only-socket-syscall-numbers` — **ARCHIVED** `✅ RESOLVED v6.5.7 + v6.5.11`, closed deliberately WITHOUT its §4; filed by sandhi 1.9.7 via bote 3.2.1). ⛔ **Status corrected 2026-08-11: this file said "archived v6.5.12" 24 lines above and "open" here — a literal self-contradiction about one issue.** The unshipped §4 work below is real and correctly preserved in this backlog; what was wrong is calling the issue open, which sends a reader to the open queue to find nothing. Re-verified on the issue itself at 6.5.10:
  `lib/net.cyr:18-24` still carries the bare x86 numbers, `grep -c CYRIUS_ARCH lib/net.cyr` →
  **0**, and the nine `ESYSXLAT` x86-compat socket rows are live at
  `src/backend/aarch64/emit.cyr:865-873`. The §3 collision it worried about was **disarmed at
  v6.5.7 by a different mechanism** (the ≥1000 private-alias band, not the per-arch peer
  wrappers §4 proposed), so the sharp edge is gone but the §4 work is unshipped. Note the
  direct tension with the W1 "steps (i)/(ii) disproven" banner above: that remap is
  **load-bearing for 51 ecosystem repos**, so this is a migration, not a deletion.
- **Incremental compilation** — compiler work. Unpin condition: reconsider when cycc self-host
  crosses ~2 s. It is **648 / 652 ms at 6.5.10** (638 ms at 6.5.2) after 100+ releases, so the
  whole-program model is nowhere near the threshold. ⚠ Read that trend with care: 6.5.7 ran
  the SAME binary three times for **649 / 670 / 701 ms**, a 52 ms spread — **wider than any
  release-over-release delta this minor**, so a single number from this series carries no
  signal. The reporting obligation is live: **every 6.5.x release's mandatory bench run IS the
  report.**
- **Bare `var a[N]` byte-vs-slot convention** — a user design decision, not an arc. The typed
  spelling `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is
  whether to lint the address-taken bare-local per-slot idiom or audit stdlib/consumers.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot) — live count is
  **18** FREED regions in `src/main.cyr` at 6.5.10 (`grep -n FREED src/main.cyr`), roughly twice
  what roadmap-future.md enumerates. Policy: the next new compiler-state scalar goes into a hole
  rather than growing the band. Cite the live count and the heap map; do not maintain an
  enumerated list that goes stale every minor. (This line read "19 at 6.5.2" until 2026-08-07 —
  re-derive it, don't carry it.)
- ~~**aarch64 `EMIT_F32V8_*` unreachable stubs**~~ — **✅ FIXED at v6.5.49.** They were
  `return 0;` while the cx backend and the F64V4 siblings twelve lines above both delegated, and
  the comment beside those siblings argues the case for delegating without doing it here.
  Reaching a stub emits NOTHING: compiles clean, runs clean, wrong answer, no diagnostic.
  ⚠ **The old bullet said "no correctness gap"** because `lib/simd.cyr` gates on
  `simd_has_avx2()` — true, and exactly why it survived: no caller and no crossos test touched
  the emitters. **Measured on real aarch64 (pi): pre-fix 0 of 4 assertions ("got 0, expected
  16"), post-fix 4 of 4.** Now covered by `tests/tcyr/crossos/simd_f32v8_emitters.tcyr`.


- **`ir_dce`/`ir_dead_store` uncapped wrappers and `CLASSIFY_CF`/`CF_TARGET`** — decide
  wire-or-delete inside Slot 3's opening bite; leaving a third option open is how they survived
  two closeouts.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term". Kept out of Slot 6 deliberately: folding it in would
  inflate a bounded residency slot into an open-ended arc.

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

The one genuine 7.x technical-adjacent item is **LEGAL-01**: cyrius is GPL-3.0-only and the
stdlib — including folded sigil, whose `sigil.cyr:533` elects the GPLv2-only leg of dual
BSD/GPLv2 code, and GPLv2-only is GPL-3-incompatible — is source-included into every consumer
binary at build time. That needs legal review plus an RLE-style linking-exception decision. It
compiles nothing and emits nothing; licensing sign-off is exactly what 7.x is for. The other
7.x item is `docs/stdlib-reference.md` authoring (currently "roughly 65 of 99" modules). Note
that "an installer aimed at strangers" is **not** a 7.x deliverable — `install.sh` exists and
ships today; that is 6.x tooling.

---

## Open questions — standing defaults, not a queue

⛔ **This section used to be titled "owed to the maintainer" and that framing is banned here.
There is nobody to owe: the maintainer is the person reading this, who has already asked for
these to be fixed.** A question parked as "owed" is a deferral to nobody, and it is how three of
these sat for months. The rule now: **each item carries a stated default and the work starts
under it**; where a genuine fork remains it gets ASKED, in one line, in the reply that turn — not
recorded here and left.

The proof is on the record: `darshana-aarch64-syscall-shadow` sat as "needs a call on where a
~350-row table lives" until the call was simply taken (**generate it from the stdlib peers**),
whereupon it became 43 derived rows and shipped at `.51`. Assume the same of anything below.

⚠ Two of the six are already ANSWERED and stay only as inputs. Of the rest, **item 3 is not a
question at all — it is a live defect** (`private fn h()` compiles with no diagnostic and
privatises the whole file including `main`, twelve releases live) and has been moved to the
backlog as work. Items 2, 4 and 6 carry defaults below.

1. **The self_compile budget — ✅ ANSWERED (user, 2026-07-29): the later performance track
   owns it.** Not a decision owed at Slot 3 entry after all — the budget gets set as part of
   that track rather than pinned up front, and **open question 5 below is to be reviewed
   together with it**, the two being the same subject. The material below stays as the input
   that track should start from.

   *Original framing:* half of the committed acceptance anchor is unstated.
   roadmap_6.md's anchor has two clauses: the svara formant bench closing to single-digit-× of
   the Rust baseline, **and** *"self_compile stays inside a stated budget"*. The svara figure is
   carried above; the budget is not, and the whole point of a *stated* budget is that it is
   stated before the arcs land rather than reconstructed after. Baseline **re-measured
   2026-08-07: 648 / 652 ms · 1,141,792 B at 6.5.10** (it was 638 ms · 1,129,288 B at 6.5.2 —
   **+12,504 B across eight releases**, all triaged growth tax). A defensible pair is
   *≤ 700 ms and ≤ 1.20 MB at minor close* — but the number is the maintainer's, not mine, and
   note that 6.5.10 is already **1.09 MB**, i.e. ~10 % of headroom under that candidate cap
   with the three biggest codegen arcs (Slots 3/5/6) still to land.
   **Note the live counter-pressure:** an IR=3-built cycc is currently **+5.02 % larger**
   (1,199,136 B, re-measured 2026-08-07), so if IR=3 ever becomes the default path the size
   half of any budget is already under strain — and the overhead has grown in both absolute
   and relative terms since 6.5.2 (+53,248 B / +4.7 % then).

2. **Bare-metal deliverable #4 — the forbidden-module check. ✅ SHIPPED v6.5.24** (gate passes 6/6 axes; verified 2026-09-05). This entry said "never built" for thirty releases. Original text: its issue was
   bulk-renamed into `issues/archived/` on 2026-07-10 (`79bae42f`, an 8-file rename) with **no
   resolution banner**, i.e. archived unfixed, while roadmap_6.md still lists it as a
   deliverable *and* an arc acceptance criterion. Either implement it in W2, or strike it from
   roadmap_6.md's acceptance list and say why. Leaving a never-built item as a shipped-arc
   acceptance criterion is the rot pattern.

3. **Per-item `private` — the promised syntax parses and does something much broader.**
   `_TL_VIS` (`src/frontend/parse.cyr:222-234`) handles token 153 by calling
   `_PRIV_MARK(FM_FILEID(...))` — a **FILE-level** flip — with an in-source comment recording
   that a per-item running flag was deliberately rejected because it would leak into later
   includes. So `private fn h(): i64 { … }` compiles with **no diagnostic** and privatises the
   *entire file*, `main` included. Three options: implement the per-item bit; make the per-item
   form a hard error pointing at the file-level declaration; or keep it and document the
   widening. Silently mis-parsing is the one outcome to rule out.

4. **macOS concurrency ordering (Slot 11).** Real platform work with a genuinely broken verb on
   a gate host, so it cannot be dropped — but it is the only pinned row with **no consumer
   waiting**, it mirrors an already-shipped split (`thread_win`), and the VR-01 guards mean it
   cannot rot silently. Keep it last, or pull it forward if a consumer appears?

5. **v6.5.x committed item 5 — the self-compile growth-tax audit — ✅ ANSWERED (user,
   2026-07-29): likely dropped, but re-review it WITH open question 1's performance track,
   since the two are related.** So it is explicitly *not* silently dropped — it is parked
   against that track's opening review, which decides whether it still earns a bite. Whoever
   opens the perf track: read this row and question 1 together, and record the outcome here
   either way.

   *Original framing:* it has no slot.
   roadmap_6.md's *"v6.5.x — ACTIVE MINOR"* section (`roadmap_6.md:115-118` at 2026-08-07 —
   the old `:1323-1369` reference here was dangling, that file is **321** lines since the
   2026-07-29 re-scope) commits v6.5.x to items **1–5** and its pull-forward note says
   v6.5.x carries *"the FULL shape, items 1–5, not just the substrate half."* Items 1–4 map to
   Slots 3/5/6. Item 5 does not appear in any slot, bite, or backlog row, and this document
   elsewhere reframes the minor's theme from self-compile growth tax to generated-code quality —
   which contradicts that note. All three prerequisites are shipped and verified
   (`scripts/bench-history.sh:174-181` runs `CYRIUS_PROF=1`; `lib/alloc.cyr:65/:85` carry the
   `_threads_active` single-threaded fast path; `2026-06-10-runtime-bench-suite-blind` is
   archived), so nothing blocks it. Either give it a named bite — a phase-resolved self_compile
   audit read off `bench-history.csv` + `CYRIUS_PROF`, in Slot 3 (shares the substrate) or W4
   (feeds the closeout) — or record here that it was retired, and why. **Do not let it vanish:
   silently dropping a user-committed item is exactly what this sweep exists to stop.**

6. **W3 sizing.** W3 is set at 5 patches on the assumption that the residency + coroutine arcs
   generate the minor's biggest consumer-facing behaviour change and therefore its biggest
   filing burst. If the agnos cadence in W1/W2 comes in lighter than the measured 6.4.x rate,
   W3 is the window to shrink first.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

**Premise-check each arc at slot entry** — empirically test that the gap still exists, against
the UPSTREAM repo source (`~/Repos/<dep>/src`), never the vendored `lib/` copy. This sweep is
the live example: three of the six rows in the previous v6.5.x table were describing work that
had already shipped or a blocker that had already died.

**`sh scripts/release-gate.sh` GREEN before EVERY `.NN` tag** — self-host fixpoint, **seed
derive** (`seed → cybs → cycc`; mandatory for ANY `src/` change, EVERY release — the cycc
fixpoint does not cover it, and cybs fails **silently** on things `build/cycc` compiles fine),
check.sh, cross-OS on ecb/ach/cass/pi (**real hardware, one host at a time** — fixed `/tmp` and
remote paths clobber under concurrency), bench. **Never tag with the gate RED.**

**Benchmark EVERY release** — `sh scripts/bench-history.sh` on a quiet box, before
`version-bump.sh`, with the headline delta (self_compile ms + cycc size) recorded in the
CHANGELOG. A perf delta is growth-tax by default; bisect only if one patch dominates. And a
byte-identical binary **cannot** regress — check the sha before triaging perf.

**One bug ships complete.** However nasty a bug turns out to be, fix it fully in one release.
Never slice one fix so the hard half defers. **An audit's output is fixes, not a backlog** —
file only when the fix genuinely cannot pack into the patch (a heap/brk **layout** change ⇒
two-step bootstrap, a design decision that is the user's, cross-repo coordination, or a full
gate cycle the release cannot absorb) and **name the reason**.

**When stuck, ASK.** Never decide to defer, slip, re-slot, or split mid-execution. Splits are
planned decisions made *before* starting. **Only the user pivots focus** — surface findings;
never unilaterally redirect. Deferral is real only when FILED with a roadmap slot and acceptance
criteria, and once documented-and-deferred, move on.

**Fix the SOURCE repo, not the fold.** sigil/sakshi/bayan/sandhi/yukti/… are the language's OWN
stdlibs — a fix applied only to the vendored `lib/<dep>.cyr` evaporates at the next re-vendor.
Patch upstream, version-bump, regen **all** distlib profiles, re-vendor. And mind the
snapshot-ping-pong loop when editing anything in `lib/`.
