# Handoff — **v6.5.33 is cut (uncommitted).** Nothing is mid-arc.

> **Written 2026-08-20**, at v6.5.33, as part of a documentation sweep. Read this, then
> [`CLAUDE.md`](../../CLAUDE.md), then [`state.md`](state.md), then [`roadmap.md`](roadmap.md)
> — the roadmap's **RE-PINNED 2026-08-20** block supersedes every pin below it.
>
> ⚠ **Refresh or delete this file when the next release ships. A stale handoff is worse than
> none, and this file is the repeat offender**: it sat at 6.5.10 for ten releases, then at
> 6.5.20 for thirteen more. Both times it was found by a human doing handoff prep, never by a
> gate. **There is no gate for handoff staleness** — that is a standing, deliberate gap.

---

## Where things stand

| | |
|---|---|
| Version | **6.5.33** — release gate GREEN, all 5 steps |
| cycc x86_64 | **1,182,928 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **198 / 0** · **77** shell gate scripts |
| Cross-OS (gate set) | ecb · ach · cass · pi — all `SELFHOST_OK` + `crossos` **54/54** on real hardware |
| Cross-OS (FULL corpus) | ecb **282/0** · ach **282/0** · pi **282/0** · cass **250/32** |
| Corpus | **282** `.tcyr` (54 in `crossos/`) · **101** `lib/*.cyr` · api-surface **4918** |
| Bench | `self_compile` **711 ms** — settled box, load 0.34 |
| Queue | **10** open issues · **2** proposals · **341** archived issues |
| Mid-arc work | **None.** `.33` is complete; the next slot is open. |

⚠ **Push and tag are the maintainer's.** The tree is uncommitted at handoff time. `.33` has
been cut locally (VERSION, CHANGELOG, docs) but not committed, tagged or pushed.

---

## What `.28`–`.33` actually did, in one line each

- **`.28`** — typed-pointer warning consulted the callee's declared return type; `fmt` writes
  in place (**breaking CLI change**); deps manifest window 4095 → 65535; distlib anchored scan.
- **`.29`** — distlib profile sidecars (two filings, one root cause); `cyrius fuzz --poison`
  (redzones + quarantine, a compile-time predefine on all seven forks); `&x` stopped warning.
- **`.30`** — seven stdlib folds; the `stdlib` key-scan matching inside a quoted value (the
  **same bug and same phrase** as the bayan defect fixed at v6.5.17, in two un-swept copies);
  `fmt_float` carry; `#derive` on a non-struct rejected loudly.
- **`.31`** — enum derive codecs generated (**name string + `Result`**, maintainer's call); a
  bare `#derive(Deserialize)` emitted nothing, on structs too; package-directory leaf declared
  in both places.
- **`.32`** — negative enum values, and the `enum_const_val` sign-extension they exposed.
- **`.33`** — **the cybs bootstrap P1**, root-caused and fixed (see below); vani 1.2.2 fold.

---

## ⭐ The one thing worth reading before touching the compiler

**`.33` fixed a stray write in the bootstrap compiler that had been corrupting every build.**

`parse_if_else` (`bootstrap/cybs.cyr`) records the skip-over-else patch offset in **`rbx`**,
recursively parses the else body, then patches — and the recursive parse clobbers `rbx`, so a
4-byte rel32 landed at an arbitrary place in the emitted compiler. Instrumented tracing found
exactly **one orphan patch** (a PATCH with no matching SET) in the *ordinary* build too; it
merely landed inside a `movabs` immediate where a wrong constant was survivable. Shift the
layout ~80 bytes and it lands on an instruction boundary — `gen1` links fine and dies with
SIGILL compiling `src/main.cyr`.

For one release this was written down as "`src/common/util.cyr` cannot take a branching
function". **It was never a rule** — it was a position-dependent symptom of a
register-discipline bug three layers down, and writing it up as a language/layout constraint
is the antipattern `feedback_dont_encode_codegen_bugs_as_language_rules` names. Guarded now by
`tests/gates/toolchain/cybs_if_else_rbx.sh`.

⚠ That gate's behavioural axis **must have `gen1` compile `src/main.cyr`**, not a toy program.
A first draft used a three-line probe and **survived its own mutation**.

---

## Traps this stretch re-taught (all cost real time)

- **`syscall` clobbers `rcx` and `r11` — and `r11` is cybs's token index.** The first
  instrumented cybs died instantly because of it.
- **`patch_rel32` takes CODEBUF offsets, not file offsets** (file − 0x78, the ELF header). A
  breakpoint on file offsets never fires and reads as "not this code path".
- **Verify the artifact between diagnostic rounds.** A `re.sub` with `DOTALL` ate ~80 lines of
  `util.cyr`; four "BROKEN" results afterwards were measuring a file that no longer compiled.
- **gdb software watchpoints cannot survive a 1.2 MB compile.** Conditional breakpoints can;
  instrumenting the compiler itself is faster than both.
- **Message-length arguments to `syscall(SYS_WRITE, …)` must be counted, not eyeballed.** Two
  off-by-ones shipped into diagnostics this stretch and were caught only by reading the output.
- **A fold can break hand-written include lists.** bayan 1.4.2 needed `lib/str.cyr` and broke
  five `.tcyr` plus a bench; yukti 2.3.8 needed `patra`. `.bcyr`/`.fcyr` are in no corpus —
  `tests/gates/toolchain/bench_fuzz_sources_compile.sh` exists because of that.

---

## Next slot

**`.34` = band E, the IR substrate.** Premise re-derived at `.33`: **7 of 254** default-vs-IR=3
exit mismatches. Re-derive at slot entry anyway — one slot is all that freshness lasts.

Three decisions are owed to the maintainer and are listed in the roadmap's re-pin block; the
sharpest is whether to flip `CYRIUS_CROSS_OS_FULL=1` to the default now that ecb/ach/pi are at
282/282, and what to do about cass's 32 PE-incompatible failures.

---

## Doing a release

`sh scripts/release-gate.sh` must be GREEN before every `.NN`. Then `sh scripts/version-bump.sh
<new>` — **never pre-write `VERSION`**; the script rewrites `CLAUDE.md`, `install.sh`, the
CHANGELOG header and the roadmap stamp only when it sees a version CHANGE.

Cross-OS runs **one host at a time** (fixed `/tmp` paths clobber under concurrency). Bench on a
settled box — wait for load < 0.35, or the numbers are noise. Two gates are load-sensitive and
will go red on a busy machine (`alloc_via` 14 ns, `test_runner_bounded` axis 1b); re-measure at
idle rather than writing them off, which is what the comments in those gates are about.
