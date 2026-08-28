# Handoff — **v6.5.35 is shipped and tagged.** Nothing is mid-arc, but a **Critical** regression is now open against `.31`–`.35`.

> **Written 2026-08-22, at v6.5.35; amended 2026-08-26** to add the szal enum-constant filing
> (reactive queue item 0) and re-derive the queue count. Release state is otherwise unchanged —
> `.35` is still the shipped tag. Read this, then [`CLAUDE.md`](../../CLAUDE.md), then
> [`state.md`](state.md), then [`roadmap.md`](roadmap.md) — the roadmap's
> **RE-PINNED 2026-08-22 (at v6.5.35)** block supersedes every pin below it.
>
> ⚠ **Refresh or delete this file when the next release ships. A stale handoff is worse than
> none, and this file is the repeat offender**: it sat at 6.5.10 for ten releases, then at
> 6.5.20 for thirteen more, then at 6.5.33 for two. Every time it was found by a human doing
> handoff prep, never by a gate. **There is no gate for handoff staleness** — a standing,
> deliberate gap. Treat every number below as a claim to re-derive, not as evidence.

---

## Where things stand

| | |
|---|---|
| Version | **6.5.35** — release gate GREEN, all 5 steps; committed and tagged |
| cycc x86_64 | **1,178,848 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **199 / 0** · **81** shell gate scripts |
| Cross-OS (gate set) | ecb · ach · cass · pi — all `SELFHOST_OK` + `crossos` **54/54**, real hardware |
| Cross-OS (FULL corpus) | ecb **282/0** · ach **282/0** · pi **282/0** · cass **250/32** — last measured `.33`, **re-derive before quoting** |
| Corpus | **282** `.tcyr` (54 in `crossos/`) · **101** `lib/*.cyr` · **97** `programs/**/*.cyr` · api-surface **5070** |
| Bench | `self_compile` **716 ms**, quiet box (load 0.03) — but see the warning below |
| Queue | **12** open issues · **2** proposals · **343** archived issues — ⚠ the newest is a **Critical silent miscompile shipped in `.31`–`.35`**, see the reactive queue below |
| Mid-arc work | **None.** `.35` is complete. ⚠ The next slot is no longer freely open — a Critical enum-constant miscompile is live in every release from `.31`, so `.36`'s band-G plan now competes with a regression fix. |

⚠ **The `-6.6 %` self_compile improvement in `bench-history.csv` is NOT real.** It compares
`.35`'s 716 ms against `.34`'s recorded **767 ms**, which `.34`'s own CHANGELOG documents as a
*loaded-box* reading. A like-for-like interleaved A/B gives `.34` 717–721 ms and `.35` 719–722 ms:
**flat**. The CSV baseline is poisoned for one row; don't build a growth-tax argument on it.

---

## What `.34` and `.35` did

- **`.34`** — band E: the last three `CYRIUS_IR=3` divergences, one per optimizer pass, taking
  the count to **0**. Plus both consumer filings (`CYRIUS_PKG_VERSION` from included files;
  the `cyrius port --language=python` arm) and the stdlib folds.
- **`.35`** — band F: the linear-scan register allocator finally **time-shares registers**.
  cycc −4,096 B; frame accesses −4.9 % in cycc, −8.5 % in consumer programs; self_compile flat.

---

## ⭐ The one thing worth reading before touching the register allocator

**A roadmap pin said the cross-BB defect was "localised to ONE line". It was half the story,
and the dangerous half.**

That line — `parse_fn.cyr` force-setting every live interval's end to the function end — is a
**deliberate v5.6.22 correctness guard**, not an oversight. Naive time-sharing is unsound across
a backward edge: when the picker reuses a register for a later interval, a `JMP_BACK` into a
position inside an *earlier* interval re-reads that register expecting the earlier value and
finds the later one. **Mutation-measured at `.35`: reverting it alone fails 69 of the 282 corpus
tests**, across 13 buckets, with *wrong answers* rather than crashes.

And the pin named only half the defect. `picked` counted assignments over the whole function's
lifetime, capped at 5 — so once five locals had ever received a register, every later interval
was blocked however many registers expire had just freed. ⭐ **The tell was a null result:
fixing the famous one line changed NOT ONE BYTE of any consumer program's output.** A codegen
fix that produces byte-identical output is *evidence*, not reassurance — that is what sent the
investigation looking for a second cause.

⚠ **Fork split to respect:** only `main.cyr`, `main_win.cyr` and `main_x86_macho.cyr` include
`backend/x86/decode.cyr`. The three aarch64 forks and cx take a `return -1` **stub** for
`RA_SCAN_LOOPS` in their own `emit.cyr` — the same pattern the `E*_PE` reroutes use. Any new
call from the shared frontend into an x86-backend helper needs the same treatment.

⚠ **`RA_SCAN_LOOPS` returning −1 means "no information", NOT "no loops".** The caller must fall
back to the whole-function extent. A partial edge list is worse than none: the picker would
time-share across precisely the loop the scan failed to see.

⭐ **Useful lever:** `CYRIUS_REGALLOC_PICKER_CAP=5` reproduces the pre-`.35` behaviour exactly,
and `=0` disables the picker entirely. That makes a self-contained A/B possible with no second
binary — `tests/gates/ir-opt/regalloc_cross_bb.sh` is built on it.

---

## ⚖️ Recorded but deliberately NOT shipped — read before re-attempting

Extending only values defined **before** the loop top (`first < t` in `_ra_loop_extend`) passes
the full corpus **282/282** and takes cycc a further 4,096 B smaller. It was not shipped.

The rule assumes any local whose first reference is inside the loop body is redefined every
iteration. This pass is a **byte scan**: it can see `48 89 85` (a store) and `48 8B 85` (a load),
but it has **no dominance information**, so it cannot distinguish a definition that dominates all
in-body uses from one guarded by a branch. v5.6.22's defect was exactly this class and took
releases to surface, so a passing corpus is not sufficient evidence.

**This is where an in-loop runtime win would come from** — the shipped conservative rule extends
every interval overlapping a loop body, so locals inside a hot loop cannot share a register at
all. Make it sound (real dominance, or a store-before-first-use proof) rather than re-running the
corpus and concluding it is fine.

---

## Next up: `.36` — band G, SIMD register residency (Slot 6)

Per the roadmap re-pin. **Premise-check at slot entry — the pins here have a history of rot.**

- ✅ **Item 3 shipped at `.24`** (f64v4 ymm widening) — confirmed live. ⚠ It has a residual:
  `f64v4_fmadd` was never widened.
- **Item 1** genuinely unbuilt — all 15 emitters in `backend/x86/float.cyr` are
  memory→register→op→memory loops, the ymm one included.
- ⛔ **Item 2 is a GATE-WIDENING question, not a build.** The wrapper inliner is LIVE and fires
  today, gated to generics. A pin that treats it as unbuilt work is wrong.
- ⚠ Re-derive the simd-site count — last measured **29**, not the 25 an older pin carried.
- ⭐ **Band F hands band G its opening**: the picker's byte matcher recognises only REX.W mov to
  and from `[rbp+disp32]`, so **no xmm/ymm local is a register candidate at all**. The vector
  register class is band G's now that time-sharing works for the integer file.

---

## 📥 Reactive queue — three NEW filings, all verified here on 6.5.35

Two arrived from **owl**, one from **szal**, and all three were re-run against live code during
handoff, not taken on the filing's word.

### 0. 🔴 Enum constants ≥ 2^62 are silently corrupted — **Critical**, and it is shipped in `.31`–`.35`

`2026-08-26-enum-const-bit62-sign-extension.md` (szal 2.1.1, pin 6.5.2 → 6.5.35). **Reproduced
here; bisected on released toolchains: last good `.30`, first bad `.31`.**

`enum { K = 0x7FFFFFFFFFFFFFFF }` evaluates to **-1**. The threshold is exactly 2^62 —
`0x3FFF…FFFF` is correct, `0x4000000000000000` comes back as `-4611686018427387904`. `var`
initialisers and inline literals are unaffected, which is how it survived five releases and a
282/282 corpus.

**Root cause is an in-band tag, and it is a genuine ambiguity, not a slip.**
`parse_types.cyr:436` stores each member as `(1 << 63) | val` — *"Bit 63 = 'is enum const'
marker; low 63 bits = value"* — but `val` is a full i64. `common/util.cyr:57-60` then
disambiguates with `if ((ecv & 0x4000000000000000) != 0) { return ecv; }`, i.e. it treats bit 62
as a proxy for "this was negative" and returns the word **unmasked, marker bit included**. For a
positive value with bit 62 set, that marker *is* the result's sign bit. `-1` and
`0x7FFFFFFFFFFFFFFF` pack to the **same stored word**, so no decoder heuristic can serve both.

The bisect shows what was traded: **`.30` rejects negative enum initialisers outright**
(`error: expected number, got '-'`) and gets every positive right; `.35` accepts negatives, gets
them right, and loses the top quarter of the positive range. The feature is fine; the encoding
is the defect.

⚠ **Suggested fix does not need a smarter heuristic — it needs the tag out of the value word.**
The presence bit already exists two lines away: `SVENUMID(S, vcnt, ee_eid)` at
`parse_types.cyr:444`, already used as exactly this test at `parse_types.cyr:801`
(`if (GVENUMID(S, pi) == 0) { … prior symbol is a plain var, not an enum const }`). Store `val`
raw, gate the five read sites on `GVENUMID` instead of on `ecv < 0`, and `ENUM_CONST_VAL`
disappears rather than being repaired.

⚠ **Two things worth checking while in here.** (1) `ENUM_CONST_VAL` first appears in *tagged
source* at `.32`, yet the released **`.31`** tarball already miscompiles — so that artifact looks
to have been built from a tree ahead of its tag. Worth confirming; it means the `.31` binary and
the `.31` source are not the same compiler. (2) The fold table is capped at 1024 entries
(`parse_types.cyr:435`), and `CHKDUPVAL` returns early past it (`:758`) — so the
**duplicate-value warning cannot fire at all** for symbols beyond the cap. szal's var_table is
>2000; roughly half its globals silently lose that lint. Already noted in the comment at `:748`,
never given a number.

The consumer workaround is one line (`enum` → `var`, since `var` skips the fold table) and szal
2.1.1 ships it — but it does not work where the constant is used as an array size, which needs an
enum constant. There is no workaround for that combination short of a literal.

### 1. `private` fns still collide across files — **High**, and it is in the v6.5.0 headline feature

`2026-08-22-owl-private-fns-still-collide-across-files.md`. **All three claims confirmed.**
`private` is enforced on *reference* but not on *definition*: the symbol still lives in one flat
resolution space, so another file defining the same name takes over — **including for the private
file's own internal calls** (repro exits 99 instead of 0). Declaring `private` in *both* files
does not help. And the override **bypasses the arity check**: a 2-arg call to a 1-arg fn is a
hard error normally (`error: '_h' expects 1 argument, got 2`), but routed through a duplicate it
compiles and runs.

⚠ **One precision the filing's title overstates.** It is not fully silent — cycc does emit
`warning: duplicate fn '_helper' (last definition wins; first defined in a.cyr)`. The genuinely
silent part is the **arity bypass**, which produces no diagnostic at all. Fix the real defect,
not the wording.

This connects to the standing owed decision on **per-item `private`** (roadmap open question 3),
which has now been live for eleven releases.

### 2. `getenv` reads only the first 8 KB of `/proc/self/environ` — **Medium**

`2026-08-22-owl-getenv-8kb-environ-window.md`. **Confirmed by inspection** at `lib/io.cyr:778`:
a fixed `var buf[8192]`, a single `file_read(fd, &buf, 8192)`, and a scan bounded by `n`. No
loop, no truncation signal — a caller cannot distinguish "unset" from "past the window".

⚠ **The 8 KB is deliberate, but only for agnos**, and the reader is already inside
`#ifndef CYRIUS_TARGET_AGNOS`. The comment (`CHANGELOG [6.1.12]`) explains that a function-local
`var[]` in a statically-dead region still reserves stack at the prologue, and agnos hands ring-3
only ~12 KB of init stack. So the Linux/macOS/PE path can loop or grow freely; **do not "fix" it
by enlarging the buffer in a way that reaches the agnos frame.**

### 3. Still un-absorbed, per the maintainer — later in the release line

`2026-08-22-versioned-wrapper-does-not-pin-cycc.md` (agnosai 2.0.5 certification). The versioned
wrapper resolves `cycc` through `$CYRIUS_HOME/bin` rather than relative to itself, so a release
cannot be certified against its own manifest pin. It warns, so nothing is silent. Untriaged.

---

## 🔧 Standing repair backlog (8, all roadmap-pinned)

- `ir-regalloc-rewrite-needs-reemit` — ⭐ **updated at `.35`**: band F shipped the regalloc half
  **without** the `ir_lower_all` re-emit path this file always named as its prerequisite, which
  disproves that dependency for the regalloc half. What remains is Wall 1 (re-emit) + Wall 2
  (local-access opcode model, `IR_SWITCH` CFG completion) only.
- `macos-threading-workers-dont-run` (narrowed at `.11`) · `simd-f64v-memory-operand` (items 1-2,
  now band G) · `v6415-closeout-residuals` (D1/D2) · `dx-multi-error-reporting` (residual 7) ·
  `stiva-stackless-coroutines` (Half B — unbuilt and, on `.26`/`.27` evidence, unjustified) ·
  `sock-send-result-allocates-per-call` · `cross-os-full-corpus` (premise is now the cass 32).

---

## ⚖️ Owed to the maintainer — decisions, not work

1. **`CYRIUS_CROSS_OS_FULL=1` as the default.** ecb/ach/pi are at 282/282; cass sits at 32,
   labelled PE-incompatible by the runner (`fork`/`socketpair` are POSIX-only) and needing triage
   into "skip with a named reason" versus real.
2. **The seven residual `assigning non-pointer to typed pointer` warnings** where the source is
   `i64`-declared. Type-accurate as written; whether it should fire at all under ADR-002 is a
   language-design call.
3. **Slot 9 design.** The committed "unbox the scalar case" was implemented at `.15` and
   **reverted**; both storage relocations are disproven. Survivors are escape analysis or a
   scope-tied arena with reclaim — a different size class, so the slot cannot be scoped until
   this is chosen.
4. **stiva Half B** — re-confirm it is wanted before spending a release on a compiler-level CPS
   transform that `.26`/`.27` evidence says is unjustified for the two filed features.
5. **Per-item `private`** — `private fn h()` still compiles with no diagnostic and privatises the
   whole file including `main`. Eleven releases live, and the owl filing above now leans on it.
6. **`archived/README.md` indexes 38 of 343.** Every 6.5.x-era archive is unindexed — backfill,
   or drop the all-files promise in `issues/README.md`.

---

## Working rules that bite hardest here

- **Push and tag are the maintainer's.** Never commit or push.
- **Never `gh`** — `curl` to the GitHub API only.
- **Never raw `cat | cycc` for projects** — use `cyrius build`. Raw piping gets no `#@incdir`
  marker, so `include "a.cyr"` resolves against CWD, not the entry file's directory. (This
  bit during the handoff repro above.)
- **`cyrius test <file>` takes a FILE; `cyrius tests <dir>` takes a DIRECTORY.**
- **Seed-derive is mandatory for ANY `src/` change** — the cycc fixpoint does not cover
  `seed → cybs → cycc`, and cybs fails *silently* on things `build/cycc` compiles fine.
- **Benchmark on a quiet box, and A/B the two binaries interleaved** rather than comparing to a
  stored number. `.35` learned this twice: best-of-7 on a 1.3 ms program showed a −11 % runtime
  win that collapsed to ±2 % noise at best-of-25.
- **A number you did not just derive is stale.** Every figure in this file was derived
  2026-08-22 from live artifacts. Commands: `stat -c%s build/cycc` ·
  `find tests/gates -name '*.sh' | wc -l` · `find tests/tcyr -name '*.tcyr' | wc -l` ·
  `ls lib/*.cyr | wc -l` · `ls docs/development/issues/*.md | grep -vc README`.
