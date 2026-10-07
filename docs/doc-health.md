---
name: Cyrius Documentation Health
description: Living state of doc currency in the cyrius repo — fresh / stale / archived / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — cyrius

> **Last refresh**: 2026-10-06 (**v6.6.20**, the v6.6.x closeout doc sync — CLN-04/06/07/08/09/12,
> HEAP-11, BACKLOG-00…14). Every figure below was **re-derived from the tree or from the tagged
> 6.6.19 install slot** (`~/.cyrius/versions/6.6.19`, stamped `tree-matches-tag: yes`), not carried.
> What it found, and it is the same shape as every sweep before it:
>
> **The public figures had frozen at v6.6.1 — nineteen releases.** `README.md`, `faq.md`,
> `platform-status.md`, `size-comparisons.md` and `stdlib-modules.md` all still cited cycc 1,247,608 B
> (live 1,586,184), 102 stdlib modules (106 — the index had never heard of `boxed`, `alloc_cx`,
> `tls_hostid` or `poison`), 5,152 API fns (5,827), 301 `.tcyr` (482) and a 144-gate count (372).
> `size-comparisons.md` still carried the 35 MB installed-tree figure "because the `cyrsign` helpers
> are ~14 MB each" that the README itself had corrected at v6.6.1 — a correction made in one file and
> never propagated to its sibling. The README's *Caps + heap* paragraph still described a 512 KB
> identifier pool, a 32,768-fn ceiling and a doubling 3 MB codebuf, all retired by v6.5.40; ADR-003's
> layout table was worse (input_buf at 0x0, output_buf in-heap, the heap top at 0x5E1D000).
>
> **This ledger marked stale rows ✅ Fresh.** README (`v6.3.0 / cycc 1,075,136 B`) and CLAUDE.md
> (`Version field at 6.2.0`) were both ✅ in the Tier 1 table — three minors old. A "Fresh" verdict
> with nothing re-checking it is a claim, not a status; every row below now carries the date the
> file was last touched (`git log -1`) and what this sweep did or did not re-verify.
>
> **`handoff.md` went stale again — sixteen releases (6.6.4 → 6.6.19)** — and is now ARCHIVED
> (`development/archive/handoff-v6.6.4.md`) rather than refreshed a sixth time: there is no gate for
> it, and the volatile state it duplicated lives in `state.md` (refreshed every release) and
> `roadmap.md`. **CLAUDE.md** still told contributors to add a `vr01_` test for every new syscall
> wrapper (retired at v6.5.11 — a file so named opts OUT of the cross-OS leg), as did the guide and
> four other docs; its reserved-word class missed the two builtins `IS_KEYWORD_TOK` lists by hand.
> **58 source / test / workflow comments** pointed at issue files that had moved to `archived/`.
> **roadmap.md** still called 6.6.18 OPEN and 6.6.19 MERGED, carried five backlog claims that were
> materially wrong, and a cyrlint item pointed at a roadmap slot that had not existed for a month.
>
> *Previous*: 2026-09-08 (**v6.6.1**). A numbers sweep — every figure below was
> **re-derived from the tree**, not carried. What it found, and the shape is consistent:
> **README.md had not been touched since 2026-08-16 and contradicted itself** (270 vs 260
> `.tcyr`; 100 vs 99 stdlib modules in the same file). Its compiler size, fold versions, gate
> counts, API-surface count, heap-region count and toolchain totals were all stale — the
> toolchain total by 508 KB, and the installed-tree figure by **10×** (35,138,369 B claimed
> "because the two `cyrsign*` helpers are ~14 MB each"; they are ~1.4 MB each). ⚠ **A number
> carrying a stated reason is not more trustworthy than a bare one** — the reason was wrong too.
>
> **`size-comparisons.md` cited `cycc 6.5.74` — a version that was never released** (cut in
> error, re-cut as 6.6.0), so an "authoritative" table referenced a toolchain no user can
> obtain. The three Cyrius rows were **re-measured** (504 / 4,448 / 1,536 — unchanged again) and
> both ELF variants RUN, exiting 42.
>
> **The reserved-token count had THREE live values at once**: 51 (a `util.cyr` comment), 67
> (README + CLAUDE.md), 76 (the actual arm count). The README also claimed `IS_KEYWORD_TOK`
> "derives from `TOKNAME_BUILTIN` so the two sets cannot drift" while that function's own comment
> says the guarantee covers only the builtin half. The count is now derived, the source comment's
> number **deleted rather than corrected** (it had no reader that could check it), and the
> missing `f64v256_*` row (9 intrinsics, shipped v6.5.38) added to the table.
>
> **99 dead internal links → 31.** 68 repaired, every one verified to resolve before rewriting;
> the 31 left are targets that exist nowhere (repros never committed, `archive/` vs `archived/`
> typos), all inside already-archived files — left rather than invented, same call as last sweep.
> `platform-status.md` cited four issues by a path they no longer live at and called one "open"
> two clauses after stating its failures were gone. `hashseed.cyr` — a HashDoS mitigation with a
> measured 934× — was in no index at all.
>
> *Previous*: 2026-09-06 (**v6.6.0**). The value-form flip forced a real doc change, not
> just a stamp: `docs/guides/cyrius-guide.md` **published the boxed layout as a user-facing
> contract** — `Ok(42)` as a 16-byte heap box with tag at `+0` and payload at `+8`, `?` "needs
> the boxed form", `match load64(opt)`, and a helper table listing `payload()` / `tagged_new()`.
> ⛔ **v6.6.2:** `tagged_new()` is back (`lib/boxed.cyr`) and `tag()` is gone; the boxed layout
> (tag +0 / payload +8) is a live published contract again, not a historical note.
> All of that is now false. The sum-type section was rewritten around the register pair, the
> helper table replaced with an ARITY table marking the two deleted functions, and the boxed
> shape kept where it is still correct (a variant with two or more fields cannot be a pair, so
> `match load64(x)` is documented as the boxed form with a warning that applying it to a value
> form dereferences the tag). `docs/ecosystem.md`'s fold table moved eight rows to their new
> releases and its refold stamps to v6.6.0.
>
> ⚠ **A doc that publishes a representation is a contract, and this one had six places to fix.**
> Grepping for the type name would have missed most of them — they were found by grepping for
> the *offsets* (`+ 8`, `load64(`), which is the shape a layout leaks in.
>
> *Previous*: 2026-09-06 (v6.5.74, an unreleased number). Local doc sweep run as part of the
> v6.5.x close-out sequence. **93 dead internal links repointed** across 41 files — almost all of them
> referrers that were never updated when an issue was archived, which is the dominant rot shape
> in this tree and is now cheap to re-check (walk every `](*.md)` and resolve it). 8 remain, all
> inside already-archived files pointing at paths that never existed; left rather than invented.
> `size-comparisons.md`'s three Cyrius rows were RE-MEASURED (504 / 4,448 / 1,536 — unchanged)
> rather than re-stamped. `CLAUDE.md`'s security-audit pointer and vidya's structural-facts entry
> were corrected in the v6.5.73 closeout; see the ledger in `cycle-discipline.md`.
>
> *Previous refresh*: 2026-08-20 (**v6.5.33**). Doc sweep + handoff prep, run directly rather
> than fanned out to agents. **Every figure below was derived from live artifacts** — binaries
> `stat`'d, hosts run over SSH, counts `find`-ed — not read out of another doc. That rule is
> the standing lesson of the v6.5.10 sweep recorded further down, where an agent stamped a
> vidya entry "re-verified live" against a stale *source comment* and reproduced the error with
> a fresh timestamp on it.
>
> ⭐ **THE FIND: three of four cross-OS hosts are at ZERO full-corpus failures, and nobody
> knew.** `2026-08-05-cross-os-full-corpus-23-failures-on-ecb` had carried "23 failures on ecb"
> since **v6.5.10**. Re-measured on real hardware this sweep:
>
> | host | v6.5.10 | **v6.5.33** |
> |---|---|---|
> | ecb (macOS arm64) | 237 / 23 of 260 | **282 / 0 of 282** |
> | ach (macOS Intel) | 233 / 27 of 260 | **282 / 0 of 282** |
> | pi (Linux aarch64) | 255 / 5 of 260 | **282 / 0 of 282** |
> | cass (Windows PE) | 263 / 7 | 250 / **32** (runner labels them PE-incompatible) |
>
> The failures were fixed incrementally across twenty-three releases and the issue was never
> re-derived — it was only ever carried forward. `platform-status.md` repeated the same stale
> rows verbatim. **A number that is copied between docs decays silently; only re-running it
> resets the clock.** Both documents now carry the measured figures, and the maintainer
> decision the issue was holding (flip `CYRIUS_CROSS_OS_FULL=1`) is finally well-posed.
>
> ⭐ **`handoff.md` was stale AGAIN — thirteen releases this time** (6.5.20 → 6.5.33), under
> its own instruction that "a stale handoff is worse than none". That is the *second*
> consecutive sweep to find it as the worst offender (the last found it four releases stale at
> 6.5.6, and before that ten at 6.5.10). It is stale because **there is no gate for handoff
> staleness** — every other currency claim in this repo has one. Rewritten in full; the gap is
> now stated inside the file rather than rediscovered each time.
>
> **Also corrected this sweep:**
> - `roadmap.md`'s head block had rotted a second time (claimed a 2026-08-14 derivation while
>   citing 1,154,816 B / 178 gates / 270 `.tcyr` / 12 open issues — every figure wrong). The
>   block now carries a dated derivation and a superseding re-pin for post-`.33` work.
> - `size-comparisons.md` and `platform-status.md` cited **1,141,792 B** (v6.5.10). Live is
>   **1,182,928 B**. Historical narrative and past-sweep changelog entries were deliberately
>   left alone — those are records, not claims.
> - The `CLAUDE.md` bullet asserting that `src/common/util.cyr` "cannot take a new branching
>   function" is **deleted**: `.33` root-caused it to a cybs register-clobber and fixed it. It
>   was a symptom written up as a layout rule, which is the antipattern
>   `feedback_dont_encode_codegen_bugs_as_language_rules` exists to catch.
> - `roadmap-future.md`'s syscall-write-byte-length entry re-derived: **532 sites, 0
>   mismatches** — the tree is clean, so that lint is preventive. Deriving it exposed a trap
>   worth writing down: a checker that round-trips literals through `unicode_escape` reports 23
>   false positives, all off by 3, one per em dash.
>
> **Touched at 6.6.9 (bite 5, not a sweep):** `docs/guides/cyrius-guide.md`'s PE `open` section
> said `O_DIRECTORY` and `O_NOFOLLOW` "are still ignored on Windows, deliberately" and blamed the
> dangling-link follow on `O_EXCL|O_NOFOLLOW` — when plain `O_CREAT|O_EXCL` followed it too. Both
> flags now have their POSIX meaning there, and the section is a table of what each target answers,
> every row asserted by `open_flags_per_target.tcyr` on real cass/ecb/ach/pi. Its Durability note
> said a var-held 74/75 "gets the honest -38" (true, and the defect: the runtime switch did not carry
> them); its arity table now lists them. `docs/stdlib-reference.md`: `xsymlink` is no longer -1 on
> Windows, `file_create_exclusive` is no longer non-atomic on agnos, and `is_symlink` has a row.
> ⚠ Same pattern as 6.6.6 bite 9h: the degrade was load-bearing in a source comment
> (`lib/syscalls_windows.cyr` OFlags), a test's PE arm (`syscall_shm_fd_passing.tcyr` asserted that
> `sys_ftruncate` DECLINES) and a sibling comment (`cbt/deps.cyr`, handed to the cbt lane).
>
> **Touched at 6.6.5 (bite 8, not a sweep):** the CLI-argument rewrite corrected FOUR doc
> claims that had never been true. `docs/guides/cyrius-guide.md` (6.6.4 line 1136) said a bare `cyrius lint`
> lints all of the stdlib — measured on 6.6.4 it printed usage and exited 1 — and line 2724
> documented `cyrius build --pie src dst` while the build loop had no `--pie` arm, so the
> documented command errored (the flag is real as of 6.6.5; the doc was fixed by making the
> code match it, not by deleting the line). In `vidya/content/cyrius/language/tooling.cyml`,
> `cyrius doc --serve [port]` was advertised with a default port and an implementation file —
> **that mode has never existed** in `programs/cyrdoc.cyr` — and `cyrius lint --check` was
> listed among lint's flags, which made cyrlint open a file called "--check". Both corrected
> in place with the measurement, not removed. `docs/stdlib-reference.md`'s `flags.cyr` section
> gained the six new entry points and a note on the three silent drops it used to carry;
> `docs/api-surface.snapshot` regenerated (+6, now 5,194). ⚠ The pattern this ledger keeps
> catching held again: **every one of the four was a claim about behaviour nobody had run.**
>
> **Touched at 6.6.6 (bite 9h, not a sweep):** `docs/stdlib-reference.md`'s `xrmdir` row said
> "**-1 on Windows** (no `RemoveDirectoryW` reroute wired)" and
> `docs/guides/cyrius-guide.md`'s wrapper paragraph listed only `DeleteFileW`/`MoveFileExW` as
> the kernel32 reroutes behind those names. Both were TRUE when written and stopped being true
> the moment that reroute was wired (`syscall(0xF03B)`); both now say so with the release that
> changed them. ⚠ The same statement was load-bearing in four non-doc places — a source
> comment, a conditional assertion in a crossos test, a per-target fixed name in the same test
> and a whole allowlist RULE in a gate — which is the reason this correction is recorded here
> rather than edited away: a degrade repeated often enough stops reading as a gap and starts
> reading as a design.
>
> **Touched at 6.6.5 (bite 5, not a sweep):** `docs/guides/cyrius-guide.md` gained a
> "raw syscall numbers are the most portable-LOOKING thing that is not portable" rule in the
> cross-platform section — three ordered rules plus the six x86 numbers cyrius deliberately
> leaves unrouted on ELF-aarch64, and the fact that a VARIABLE syscall number is rewritten by
> the chain too. It carries no derived count (the first draft quoted "58 rows", which is the
> very shape this ledger keeps catching). In the sibling `vidya/` repo, the language field
> note `fn_main_is_not_the_entry_point` was **corrected**: it had said cyrius has no auto-call
> for `main()`, which stopped being true at **v5.9.37** — eighteen minors of a field note
> stating the opposite of what the compiler does. ⚠ Review round 1 found the correction was
> **half-applied**: `field_notes/index.cyml`'s one-line summary of that same entry still read
> "fn main() isn't auto-called", so the corpus said both things at once. Fixed — and the
> general lesson is that an entry with an index summary is TWO statements of the same fact.
> Round 1 also added rule 4 to the guide's list (the `dup2` → `dup3` self-dup divergence) and
> the `#ifdef`-guarded-declaration half of rule 3, after `lib/yukti.cyr` was found declaring
> `SYS_STATFS = 43` under exactly that guard.
> Round 2 extended rule 3 again — to say which gate enforces it, over which trees, and that
> the compiler's OWN source (`src/backend/common/runtime.cyr`) was breaking the rule while
> the rule was being written. Round 2 also pinned the nine unshipped syscall families into
> `docs/development/roadmap.md`'s potential backlog: they had been documented only in an
> ARCHIVED issue, which is documentation, not a deferral. Three `vidya/` compiler gotchas
> were added (an x86-hosted cross compiler takes the HOST's arch `#ifdef` arm; a gate can
> have a positive control and still read green over an empty corpus; `assert_lte(f(), 0)`
> on a syscall wrapper accepts every failure).
>
> ⚖️ **Not re-verified at 6.6.5, and stated rather than implied**: the `vidya/` edits named
> above (plus round 2's three compiler gotchas) are the ONLY ones — that repo's per-minor
> structural refresh is a closeout item and
> was not run here (a first cut of this paragraph left the blanket "vidya/ was not touched"
> standing directly beneath a paragraph recording a vidya edit). The Tier 2–7 inventories
> below still carry their 2026-06 anchors, and the tier tables are approximate by
> construction — the rollup counts lag.

> **Touched at 6.6.6 (bite 5, review round — not a sweep):** `docs/guides/cyrius-guide.md`'s
> attribute-boundary paragraph was **corrected twice in one release**, which is the entry worth
> keeping. It first documented the boundary *exactly as shipped* — `(` accepted after all ten
> attribute names — and that shipped rule was itself wrong: `#io(fd) reads a byte`, a comment,
> still failed to compile. A doc that faithfully records a defective implementation reads as
> confirmation, which is why "the guide matches the code" is not a currency check. The
> paragraph now names the three names that end at `(` and says why `#assert` is one of them
> although its paren form is not syntax. A second paragraph was added for the PREPROCESSOR
> directive names (`#endif`, `#endplat`, `#host_only`, `#derive(…)`, `#@srcline`), where the
> same missing boundary was SILENT: `#endifoo note` closed a conditional and the skipped code
> was compiled in. `docs/audit/2026-09-03-security-audit.md`'s CVE-45 entry gained the residual
> it had not recorded (a string literal could still mint a file-map span) plus the consumer-side
> fix and, explicitly, what remains as an argument from the grammar rather than a check.
> `docs/development/issues/archived/2026-09-19-lexer-attribute-prefix-swallows-comments.md`'s
> "Corrections" section gained two: the shipped boundary was too wide, and its own claim that
> the gate "covers all three mirror readers" was FALSE WHEN WRITTEN — and that false claim was
> the stated reason for declining the coverage the filing's acceptance asked for. One
> `vidya/` compiler gotcha added (`grep the SHAPE, not the name; a rule applied inline once is
> the tell`); no other `vidya/` file touched, and the per-minor structural refresh remains a
> closeout item.

> **Touched at 6.6.6 (bite 15, not a sweep):** `docs/guides/cyrius-guide.md`'s
> "the preprocessor reads it the same way" paragraph said *"the four line-oriented passes now
> share one state machine"* — true as written, and still an incomplete picture of the rule a
> reader takes from it, because MACRO EXPANSION is a FIFTH pass that is byte-oriented and had
> neither the string state nor a left word boundary: `"ID(5) literal"` lost two bytes of its
> own data and `myID(5)` called `my`. A paragraph for it was added beneath, including the one
> place a macro IS still expanded (inside a `#` comment) and why that cannot change what is
> compiled. The lesson is the same as the attribute-boundary entry above: a doc sentence scoped
> to the passes that were FIXED reads as a statement about the whole preprocessor.
> `docs/development/issues/archived/2026-09-19-cycc-exits-zero-after-a-short-output-write.md`
> gained four corrections, of which the load-bearing one is that the filing's own "grep
> `while (wgo == 1)`" recipe finds six of the ELEVEN sites. One `vidya/` compiler gotcha added
> (a test whose oracle lives in the same file the defect damages cannot fail).
>
> ⛔ **Corrected at 6.6.6 (bite 15d), one bite after it was written here:** the sentence above —
> "the one place a macro IS still expanded (inside a `#` comment) and why that cannot change what
> is compiled" — **was false**, and this file was one of six places asserting it. An expansion
> opened in a comment read forward to the matching `)` with no line bound, so `# TODO: fix M(`
> deleted every statement up to the next `)` and the program exited 0 with an empty stderr. The
> guide paragraph now says so, and the rule it states is the fixed one: an invocation that starts
> in a comment must close on that line. ⚠ The lesson to take is narrower than "the doc was
> stale": the doc faithfully recorded a justification that had been reasoned about and was wrong
> about the READ side of the operation, so re-reading the doc would never have caught it. Only
> running the shape did.
> **Touched at 6.6.6 (bite 18, not a sweep):** `docs/guides/cyrius-guide.md` gained a Windows
> **open-flag table** (the POSIX flag word → CreateFileW's `dwDesiredAccess` /
> `dwCreationDisposition` pair) and an **Environment / `getenv`** subsection, because both
> halves of that page had been describing a compiler that ignored `O_TRUNC`/`O_APPEND` and
> could not read its own environment variables. Both are documented with what they cost:
> the table names the two residual divergences that come out of ONE Win32 rule
> (`TRUNCATE_EXISTING` is refused without `GENERIC_WRITE`), and the env section carries the
> `cmd.exe` trap (`set VAR=1 & prog` puts a trailing space IN THE VALUE, so a correctly fixed
> `cycc.exe` reads exactly like the broken one). The review round added the
> `O_EXCL|O_NOFOLLOW` residual — `CREATE_NEW` resolves a final reparse point instead of
> refusing it, measured on real cass against the identical Linux source — to the guide and to
> `lib/syscalls_windows.cyr`, since the flag table is what a consumer will read before
> trusting sigil's keyfile pattern on Windows. ⚠ This entry exists because the bite's first
> cut edited the guide and did NOT stamp this ledger; nothing in `scripts/`, `tests/` or
> `programs/` enforces the stamp, so the only thing standing between a guide edit and silent
> ledger drift is remembering — which is exactly the failure this file is for.
>
> ⚖️ **Not re-verified at 6.6.6:** the tier tables and the "At a glance" anchors below still
> carry their 2026-09-08 v6.6.1 figures. cycc is **1,315,040 B** as of this bite
> (`docs/development/state.md` carries the live stamp); the 1,247,608 B anchor below is the
> v6.6.1 one and has not been re-tallied here.
> **Touched at 6.6.6 (bite 23, not a sweep):** `docs/guides/cyrius-guide.md` gained two
> corrections, both of things it already said that were not behaviour. (1) The CLI verb list
> had no `cyrius self` line at all, and nothing anywhere said which SOURCE `self` / `soak`
> compile — they named `src/main.cyr`, the x86-64 **Linux** fork, on every host, which on
> aarch64 and macOS COMPILES and yields a verdict about a compiler nobody ships. The verb is
> listed now, with the host → fork mapping and the fact that a missing fork is refused by
> name. (2) "`--emit-js` is **x86-Linux-only**" was documentation, not behaviour: elsewhere
> the CLI forked a compiler that does not know the flag, and that compiler ignored it, read
> its empty stdin and emitted a runnable binary which the CLI renamed over the `.js` and
> called OK (measured on real pi: exit 0, a 65,888-byte aarch64 ELF). The note now records
> what it does instead. ⚠ Neither is a new fact — both paragraphs describe the *intended*
> behaviour the code did not have, which is the class this ledger exists for: a doc that is
> right about intent and silent about what actually happens reads as verified. Both are now
> pinned by gates (`toolchain/self_host_src_per_target.sh`,
> `toolchain/emit_js_refused_off_x86_linux.sh`), so the doc and the behaviour move together.
> No other tier was re-verified at 6.6.6 by this bite.

> **Touched at 6.6.6 (bite 24, not a sweep):** `docs/guides/cyrius-guide.md`, the same CLI
> verb list. (1) `cyrius capacity [--check] <src>` showed the source as REQUIRED; it is
> optional, and the no-argument default was the bare literal `src/main.cyr` — the x86-64
> Linux fork — so in a checkout on ARM or macOS it metered a compiler that host does not
> build and reported its table occupancy as the local one's. Corrected to `[src]` with a
> note on the host-fork default and its two fallbacks. (2) `cyrius pulsar` was **not in the
> verb list at all**, and nothing said it is an x86-64-Linux-HOST orchestrator — off that
> host it died on an exec with `error: cycc compile failed`, a message about the compiler
> for a problem about the verb. Listed now, with the constraint and the named refusal. ⚠
> Same class as bite 23's two entries: the list described a tool that was intended, not the
> one that ran, and a verb missing from a list is the quietest form of that. Both are pinned
> by gates (`toolchain/capacity_meters_host_fork.sh`,
> `toolchain/pulsar_is_x86_linux_host_verb.sh`) so the doc and the behaviour move together.
> One vidya entry was added (`field_notes/compiler/gotchas.cyml`, on a shape-detecting gate
> judging the fn you inline into); no other tier was re-verified at 6.6.6 by this bite.
> **Touched at 6.6.6 (bite 11, not a sweep):** `docs/guides/cyrius-guide.md`'s ESYSXLAT rule
> list gained a **rule 5** and a correction to rule 3. Rule 3 had ended at the yukti
> `SYS_STATFS = 43` finding; it now records that 6.6.6 gave the call the NAME it was missing
> (both Linux peers declare 137/138 with rows 137→43 / 138→44, Darwin 345/346, `sys_statfs` /
> `sys_fstatfs` wrappers) and that a consumer keeping its own aarch64 declaration still runs
> `accept()` — and now gets a `duplicate symbol … redefined with conflicting value` warning.
> Rule 5 is new ground for this section, which had only ever been about the syscall NUMBER:
> the STRUCT the call fills differs in **width** as well as offset — Darwin's `f_bsize` is
> uint32 with `f_iosize` packed above it, so `load64(buf + STATFS_BSIZE)` there returns
> `f_bsize | (f_iosize << 32)`, measured on ecb. `lib/syscalls_x86_64_agnos.cyr`'s
> "AGNOS-ONLY … `sys_statfs` exists NOWHERE else in this repo" note was rewritten as HISTORY
> rather than deleted: its reasoning was right and its own stated upgrade path was taken, so
> the note is now a record of a trigger that fired. `docs/api-surface.snapshot` regenerated
> (+8, now 5,234 — the review fix added the agnos peer's missing `sys_fstatfs`, which had
> shipped on four of the five peers and made a `CYRIUS_TARGET_AGNOS=1` build of portable
> source a hard compile error). In the sibling `vidya/` repo, one language field note was added
> (`routing_a_syscall_number_is_only_half_of_portability_the_struct_width_is_the_other_half`).
> ⚖️ Same caveat as 6.6.5: that is the ONLY `vidya/` edit — the per-minor structural refresh
> is a closeout item and was not run here.

## At a glance — inventory (anchors re-derived 2026-10-06 at the v6.6.20 closeout; the bucket table is approximate by construction)

**~105 markdown files** across the repo (+1 from 2026-05-18: `scripts/shims/README.md` added at v5.11.69 alongside the 3 CLI-shim moves). The 4 guide-shape docs (`tutorial`, `editor-integration`, `faq`, `cyrius-guide`) moved from `docs/` flat → `docs/guides/` subdirectory; no count delta. **Current-cycle anchors (2026-10-06, the v6.6.20 slot open = the v6.6.19 tag — ALL DERIVED)**: **376** registered check.sh shell gates (**372** under `tests/gates/` in 8 buckets + 4 `scripts/*-gate.sh`; ~193 registered in `scripts/check.sh`, ~183 in the driver — `sh scripts/check.sh --registry`) · the v6.6.19 release gate GREEN (0 failed, 2 named agnos-parity SKIPs) · cycc x86_64 fixpoint **1,586,184 B** · `cycc-native-aarch64` **1,323,400 B** · **482 .tcyr** (197 in `crossos/`) · **106 lib/*.cyr** · **85** programs · heap **102 regions** (`heapmap.sh`) · api-surface **5,827** · reserved tokens **107** (26 statement + 79 `TOKNAME_BUILTIN` + 2 hand-listed builtins) · core toolchain **8,718,168 B**; installed bin **12,440,524 B** (the tagged 6.6.19 slot) · cross-OS ecb/ach/cass/pi `SELFHOST_OK` + `LIBTEST_OK` on real hardware (6.6.19 gate) · self_compile **923 ms** (6.6.19 gate) · **0** open issues / **473** archived · **2** open proposals / **34** archived · **59** non-archived markdown files (579 including the archives) · **0** dead internal links in live docs (38 inside archived / audit / CHANGELOG files, left as records). (**Prior anchors, 2026-09-08, v6.6.1**: check.sh **240 gates** · **144** shell gate scripts in `tests/gates/` (8 buckets) · cycc x86_64 fixpoint **1,247,608 B** · **301 .tcyr** (68 in `crossos/`) · **102 lib/*.cyr** · **84** programs · heap **102 regions** (gate-derived; a raw `grep` says 145 by also matching FREED markers — that miscount was made and caught inside this same sweep) · api-surface **5152** · reserved tokens **102** (26 statement + 76 builtin, disjoint) · core toolchain **6,893,216 B**; installed `~/.cyrius/bin` **10,249,873 B** · cross-OS ecb/ach/cass/pi `SELFHOST_OK` + `LIBTEST_OK` on real hardware · self_compile **731–734 ms** · **0** open issues / **387** archived · **3** open proposals · **57** non-archived markdown files (486 including the archive) · **31** dead internal links, all unresolvable-by-design. (**Prior anchors, 2026-08-07, v6.5.10**: check.sh **162 gates** · **41** shell gate scripts in `tests/` · cycc x86_64 fixpoint **1,141,792 B** · **260 .tcyr** (36 `vr01_`) · **99 lib/*.cyr** · **97** programs · heap **100 regions** · api-surface **4817** · cross-OS ecb/ach/cass/pi `SELFHOST_OK` + VR-01 `LIBTEST_OK` on real hardware · self_compile ~648-652 ms (⚠ 648-701 observed within one release — treat a single figure as noise) · **12** open issues / **299** archived. (**Prior anchors, 2026-08-03, v6.5.6**: check.sh 153 · cycc 1,133,440 B · 254 .tcyr · api-surface 4783 · 281 archived.) (**Prior anchors, 2026-07-23, v6.4.72**: check.sh 147 gates + QEMU boot · cycc x86_64 fixpoint 1,103,512 B · 251 .tcyr · 99 lib/*.cyr · 97 programs · heap 100 regions · highest SIMD builtin token 151 (`f32v8_dot`) · SIMD Phase 5 complete on all four backends (x86/aarch64/PE/cx) · cross-OS ecb/cass/pi `SELFHOST_OK` · self_compile ~620 ms.) (.63→.72 band: agnos GPU-syscall band **#82–#91** contiguous, bayan 1.2.1 f64 JSON round-trip, sandhi 1.9.1 getpeername fold, `cyrius coverage` project-`src/`-scope fix.) (**Prior anchors, 2026-07-12, v6.4.62**: check.sh 146 · cycc 1,103,568 B · 246 .tcyr · self_compile ~627 ms.) (**Prior anchors, 2026-07-10, v6.4.48**: check.sh 141 · cycc 1,091,000 B · 241 .tcyr · self_compile ~649 ms.) (**Prior anchors, 2026-07-09, v6.4.32**: check.sh 132 · cycc 1,077,592 B · 240 .tcyr · 98 lib/*.cyr · self_compile ~616 ms.) (**Prior anchors, 2026-07-06, v6.4.10**: check.sh 130 · cycc 1,057,568 B · 227 .tcyr · self_compile ~561 ms.) (**Prior anchors, 2026-06-28, v6.3.0**: check.sh **100/100** gates + QEMU boot gate · **192 .tcyr** · **98 lib/*.cyr** modules · cycc x86_64 **1,075,136 B** · cross `cycc_aarch64` 627,376 B / `cycc_win` 851,968 B / `cycc-native-aarch64` 947,280 B · api-surface **4352**.) Bucket counts:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / touched in current cycle** | ~39 | Touched within the v6.x cycle-open + v5.x close; state.md / roadmap.md (rewritten at v6.0.0 cycle-open) / roadmap-future.md (new) / cycle-discipline.md / CHANGELOG / completed-phases (trimmed at .41) / cyrius-guide / tutorial / faq (**cycc-size refreshed 2026-05-17**) / stdlib-reference / benchmarks (**re-pointed at root BENCHMARKS.md 2026-05-18**) / ecosystem / editor-integration / platform-status (**cycc-size refreshed 2026-05-17**) / size-comparisons (**cycc-size refreshed 2026-05-17**) / 6 ADRs / 5 audits / 4 open proposals / dev/process-notes (**historical-frontmatter 2026-05-18**) / dev/module-manifest-design (**cyrius.toml→cyrius.cyml 2026-05-18**) / dev/crash-localization (**cc3→cycc + rename note 2026-05-18**) / dev/benchmarks (**historical-frontmatter 2026-05-18**) / arch/cyrius.md (**doc-currency frontmatter 2026-05-18**) / arch/package-format (**schema refresh + cycc examples 2026-05-18**) / ffi/struct-packing (**verified accurate 2026-05-18**) / threat-model (v5.10.35 refresh) / fncall-abi (v5.10.35 verified) / lib-tls-contract.md / **NEW: `/BENCHMARKS.md` at repo root** (auto-gen by `scripts/bench-history.sh`) |
| 🟡 **Stale — refresh in place** | ~6 | **P2 prose-currency flagged by the 2026-06-04 sweep** (see notes): tutorial.md "Everything is a 64-bit integer / no floats" now false (float + f64v2/f64v4 SIMD shipped); faq.md perf answer pinned to v6.0.3 (needs a bench re-run, not just a size swap); cyrius-guide.md + stdlib-reference.md "v6.0.0 removes legacy io fns" never happened (Result + legacy coexist); octal literals undocumented in the guide; size-comparisons/BENCHMARKS perf tables on a stale baseline. Prose-judgment, deferred to the vidya/follow-up pass. |
| 🟠 **Read-through outstanding** | ~5 | **Structural gaps (P1) flagged 2026-06-04** — human-led re-write needed: `stdlib-reference.md` (native TLS 1.3 + ~40 shipped modules have zero API surface); `cyrius-guide.md` AGNOS include block (~L828-850) references nonexistent files across 3 sibling repos; `architecture/cyrius.md` frozen at a v5.6.43 snapshot + 4 dead `regression-*.sh` refs; `platform-status.md` missing UEFI target row (AGNOS userspace row added v6.0.87); **`migration-strategy.md`** still frozen at v5.7.39 (trigger long passed). (`lib-tls-contract.md` + `threat-model.md` were updated for the two-backend native-TLS model in the v6.0.83 sweep — no longer outstanding.) |
| 🔵 **Probably evergreen** | ~4 | ADR-002/-003/-004 (everything-is-i64, fixed-heap-layout, convention-based-dispatch) + cycle-discipline.md — load-bearing principles; re-read pass quarterly, not weekly. |
| 📦 **Archive — frozen by design** | ~50 | `docs/development/archive/` (6) + `docs/development/issues/archived/` (41 — +1 since 2026-05-17 for commandress papercut filing) + `docs/development/proposals/archived/` (3 — unchanged). Verified — frozen by design. |
| ❓ **Open strategic question** | 0 | None. |

Numbers approximate; rolls up from the per-tier tables below.

**Why now**: doc-health convention adopted at v5.10.34 alongside the sandhi 1.3.2 TLS unblocker. The cyrius doc tree has been actively maintained (CHANGELOG is canonical per CLAUDE.md, state.md refreshes every release, vidya sync at every minor closeout) but the *aggregate* currency has no surface — this file is that surface.

**2026-06-04 sweep notes** (v6.0.62, multi-agent): 8 parallel auditors swept the user-facing + reference tiers (point-in-time docs — issues / proposals / audit / archive / CHANGELOG / state.md — excluded by design). **~70 objective currency fixes landed** across ~20 docs (versions/sizes → v6.0.62 / 906 KB; binary-name purge; counts: programs 59/68 → 80, gates 79 → 85, .tcyr → 157, module counts; mabda git-dep → folded; 6 broken `docs/guides/` relative links). Two empirically-disproven "Known Limitations" removed from the guide (negative literals + mixed `&&`/`||` — both verified to compile/evaluate). **Cross-cutting pattern**: the phantom `cycc → cyc` rename (never happened — `cycc` is permanent) + the wrong `cc3 → cycc @ v5.0.0` chain (correct: `cc3 → cc5 @ v5.0.0`, `cc5 → cycc @ v6.0.0`) appeared in 7+ files — all corrected; forbidden literal `cc5_*` binary names purged. The P1 structural gaps + P2 prose items (see the 🟠/🟡 buckets) are **FLAGGED, not edited** — they need human-led rewrites or a benchmark re-run, routed to the vidya/follow-up pass. **Source-level finding (out of doc scope, surfaced for fixing) — RESOLVED .72**: `lib/tls_native.cyr`'s header previously said "v6.0.10 SCAFFOLD / every fn returns NOT_IMPLEMENTED" despite being a real client+server implementation. The header was corrected 2026-06-04 and rewritten again in .72 to describe the IMPLEMENTED 1.3 stack, the three KNOWN-HOLE public fns, and the IN-PROGRESS 1.2 backport (record layer .72, PRF/key schedule .73). No longer a misleading comment.

**2026-05-18 sweep notes**: dedicated doc-health pass (not a normal release-bump touch) explicitly read-through of the 8 🟠 carryovers from the 2026-05-17 sweep + verification of bench infrastructure shape. Sweep retired 7 of 8 carryovers (the 8th, migration-strategy.md, deferred to v6.0.0 doc-pass per user direction). Three classes of finding:

1. **Mostly accurate, needed naming refresh** (4 docs): `process-notes.md` / `crash-localization.md` / `architecture/cyrius.md` / `architecture/package-format.md` had `cc3` / `cyrius.toml` references that pre-date the v5.0.0 binary rename and the v5.5.x manifest rename. Light frontmatter notes added documenting the renames + pointer at canonical-current docs. `module-manifest-design.md` got mechanical `cyrius.toml` → `cyrius.cyml` sed across 11 occurrences; rest of the doc remains canonical schema reference.

2. **Bench infrastructure orphan** (2 docs): `docs/benchmarks.md` and `docs/development/benchmarks.md` were pointing at each other as authoritative — but the actual auto-gen 3-tier bench system (`scripts/bench-history.sh` + `BENCHMARKS.md` at repo root + `bench-history.csv` history) had been live since v5.7.x with the doc pointers never updated. Fix: `docs/benchmarks.md` now points at `/BENCHMARKS.md` as canonical-current; `docs/development/benchmarks.md` got a historical-frontmatter clarifying it's bounded to the v5.6.x perf arc only. Re-ran `bench-history.sh` to refresh the auto-gen file against v5.11.63 — and the new run caught a **+65.2 % self_compile regression vs 2026-04-18 baseline** (244 ms → 404 ms). To investigate as its own slot.

3. **Accurate-as-is** (1 doc): `ffi/struct-packing.md` — agent-assessed STILL-ACCURATE and grep-verified (fncallN ABI unchanged since v5.4.13 landing).

4. **Defer-to-v6.0.0** (1 doc): `docs/development/migration-strategy.md` — frozen at v5.7.39 Wave snapshot; most Wave work has shipped piecemeal (niyama fold v5.9.0, sandhi 1.3.3 v5.10.34, bayan/ganita carve in flight). User direction: refresh at v6.0.0 cycle-open when v5.x → v6.x migration story itself needs codification, not in this sweep.

Also closed: 1 issue filing (commandress papercut → archived) from the .60-.63 ship arc.

**Prior sweep (2026-05-17, v5.11.59)**: ledger lagged 9 patches behind reality; brought rows current to v5.11.59. Iron-boot papercut 4-slot arc fully closed (.56-.59) + DCE-aware reachability filter cross-arch (aarch64 gained full DCE for the first time). cycc-size claims refreshed 823 KB → 875 KB.

**Prior sweep (2026-05-13, v5.11.42 → v5.11.50)**: ledger lagged 13 patches behind reality; brought rows current to v5.11.42 + caught proposals/archived/ miscategorization. v5.11.50 added cap-drift + doc-size programmatic gates.

---

## Tier 1 — Structural docs (root + `/docs` root)

> Re-derived 2026-10-06 (v6.6.20). **Last touched** is `git log -1` at the 6.6.20 slot open or this
> sweep's commit; **Status** says what was re-verified, not what was assumed.

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-10-06 | ✅ Fresh (re-derived 6.6.20) | Every figure re-derived (CLN-09): cycc 1,586,184 B, the cross / LSP / linker / toolchain sizes from the tagged 6.6.19 slot, 106 modules with current fold versions, 5,827 API fns, 482 `.tcyr`, 376 registered gates, 107 reserved tokens, the *Caps + heap* paragraph from the heap map. It had been frozen at v6.6.1 while this table called a v6.3.0 snapshot Fresh. |
| `CHANGELOG.md` | 2026-10-06 | ✅ Fresh | **Source of truth per CLAUDE.md.** Through **v6.6.19**; the `[6.6.20]` section is written at the closeout's integration. |
| `CLAUDE.md` | 2026-10-06 | ✅ Fresh (re-derived 6.6.20) | Version 6.6.20 (version-bump). Derived counts re-derived (CLN-06: lib 106, programs 85, the reserved class 107 with `f64_sqrt` / `callptr`, the src listing), the `vr01_` instruction replaced (CLN-04), stale `file:line` cites cited by name. |
| `VERSION` | 2026-10-06 | ✅ Fresh | `6.6.20`. Single source of truth; bumped only by `scripts/version-bump.sh`. |
| `BENCHMARKS.md` (root) | 2026-10-06 | ✅ Fresh | Auto-generated by `scripts/bench-history.sh` at every release gate (6.6.19: self_compile 923 ms). |
| `docs/guides/cyrius-guide.md` | 2026-10-06 | ✅ Fresh | Covers the minor's features (`[embed]`, `--print-config`, `help manifest`, `--poison`, `#deprecated`, `f64_le`/`ge`/`trunc`, the value-form `Result`, pointer fields — checked by the 6.6.20 cleanup audit). 6.6.20 replaced its `vr01_` wrapper instruction and the aarch64 `f32v8` "return-0 stubs" caveat. |
| `docs/guides/tutorial.md` | 2026-09-06 | 🔵 Not re-verified at 6.6.20 | No version or size claims to drift; onboarding prose. |
| `docs/guides/faq.md` | 2026-10-06 | ✅ Fresh (re-derived 6.6.20) | Self-compile and size re-derived (923 ms / 1,586,184 B at v6.6.19). |
| `docs/stdlib-modules.md` | 2026-10-06 | ✅ Fresh (re-derived 6.6.20) | 106 modules; `boxed`, `alloc_cx`, `tls_hostid`, `poison` indexed (none was). Refresh when a `lib/*.cyr` module is added or removed. |
| `docs/stdlib-reference.md` | 2026-10-06 | 🟠 Read-through (coverage) | Per-function API; touched every release a surface changes. Coverage of the 106 modules was last counted at v6.5.10 (65 of 99); re-count at the next doc sweep. Mirrors `docs/api-surface.snapshot`. |
| `docs/benchmarks.md` | 2026-08-07 | 🔵 Evergreen | Pointer hub for the three bench surfaces (`/BENCHMARKS.md`, size comparisons, the historical perf arc). |
| `docs/ecosystem.md` | 2026-10-06 | ✅ Fresh (verified 6.6.20) | The 12 fold rows equal each fold's latest tag (the 6.6.20 downstream check; `fold_table_matches_vendored` gates it). |
| `docs/guides/editor-integration.md` | 2026-07-12 | 🔵 Not re-verified at 6.6.20 | LSP + editor configs. |
| `docs/size-comparisons.md` | 2026-10-06 | ✅ Fresh (re-measured 6.6.20) | The three Cyrius exit42 rows re-measured and RUN (504 / 4,448 / 1,536, unchanged); the self-host block re-read from the tagged 6.6.19 slot — it still carried the 35 MB installed-tree error the README had fixed at v6.6.1. The C / Rust / Go / Zig sweep is still the v6.5.33 one, as its header says. |
| `docs/platform-status.md` | 2026-10-06 | 🟡 Partly re-derived | The x86 cycc size and the cross-host line (crossos 197 at the 6.6.19 gate) re-derived at 6.6.20; the rows are as verified 2026-09-08 and its header now says so. Full row-by-row re-check due at the next sweep. |
| `docs/api-surface.snapshot` | 2026-10-06 | ✅ Generated | 5,827 lines. Regenerated by `cyrius_api_surface`; gated in `check.sh`. |

---

## Tier 2 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `cyrius.md` | 2026-07-12 | 🟡 Stale in part | Principles and the self-hosting framing are durable; its per-platform table is "as of v6.4.62". Re-verify the table at the next sweep. |
| `package-format.md` | 2026-10-05 | ✅ Fresh | Touched for 6.6.17's manifest work. |

---

## Tier 3 — Operational / Development (`docs/development/`)

> **Important framing**: state.md + roadmap.md + completed-phases.md form the **canonical operational surface**. CLAUDE.md delegates volatile state to state.md, and roadmap.md is the slot-pinning artifact. These three rotate every release; everything else in this tier rotates per-need. **`handoff.md` is archived (2026-10-06)** — there is no separate handoff file any more; state.md is the handoff.

| File | Last touched | Status | Action |
|---|---|---|---|
| `state.md` | 2026-10-06 | ✅ Fresh (reconciled 6.6.20) | 6.6.19 SHIPPED (tag `f5a5175a`), 6.6.20 = the closeout in progress; the ecosystem row is the 6.6.20 downstream check. It had said 6.6.19 was "awaiting the tag" against an integration commit (CLN-07). The `cycc` row is gated by the doc-stamp row and is re-stamped at integration. |
| `roadmap.md` | 2026-10-06 | ✅ Fresh (re-triaged 6.6.20) | The active minor: 6.6.18 / 6.6.19 SHIPPED, 6.6.20 in progress, the backlog re-triaged (61 bullets; struck / corrected / re-pinned in place — BACKLOG-00…14), the DCE arc spec moved to roadmap_6.md ahead of the v6.7.x rotation. Its `Current head:` stamp is gated by the doc-stamp row and `version_bump_doc_anchors.sh`. |
| `roadmap_6.md` | 2026-10-06 | ✅ Fresh | v6.7.x spec gained the backlog's v6.7.x candidates (A4 `Struct = *Struct` corrected, A4 `o.m()` vs `T_m(o)`, A5 8-byte method-return inference, B8 compound assignment on a field, C3 generic-struct fields) and the DCE compaction arc's spec. |
| `roadmap-future.md` | 2026-10-06 | ✅ Fresh | NFKC/NFKD struck as shipped (v5.8.60), the cyrlint gates re-pinned, the aarch64 `f32v8` caveat and the self_compile figures corrected, the imm12 "class CLOSED" line re-opened (6.6.20). |
| `completed-phases.md` | 2026-10-06 | ✅ Fresh | v6.6.x band gained 6.6.18, 6.6.19 and an in-progress 6.6.20 row (integration completes it). |
| `cycle-discipline.md` | 2026-10-06 | ✅ Fresh | The Closeout checklist + ledger; the v6.6.x → v6.7.0 ledger entry is drafted at 6.6.20 (gate placeholders filled at integration). |
| `ecosystem-migration-6.6.2.md` | 2026-10-06 | 🗄 Historical, kept in place | The v6.6.0 value-form sweep worklist, CLOSED 2026-09-12; five dead issue links re-pointed at 6.6.20. Not moved to `archive/`: `docs/retired-symbols.allow` and the `lib/boxed.cyr` / `lib/tagged.cyr` comments cite this path. |
| `ecosystem-migration-6.6.13.md` | 2026-10-01 | 🗄 Historical census | The `f64_le` / `f64_ge` / `f64_trunc` builtin census (6.6.13). Re-derive before acting on any figure, as it says. |
| `ecosystem-migration-6.6.18.md` | 2026-10-06 | ✅ Current consumer note | The 6.6.18 sidecar-delta note for consumers at their pin bump. |
| `dev-tools-linux.md` | 2026-10-06 | ✅ Fresh | Per-environment toolchain; 6.6.20 fixed its cross-OS paragraph (the `vr01_` pointer, "one host at a time" — safe concurrently since v6.6.6). |
| `benchmark-regimes.md` | 2026-10-01 | 🔵 Evergreen ledger | Which bench rows are comparable; extend it when a measurement regime changes. |
| `lib-tls-contract.md` | 2026-10-05 | ✅ Fresh | Stdlib TLS contract, re-pinned to the 6.6.13 surface 2026-10-01 and touched for 6.6.16. Verify at the next minor closeout. |
| `threat-model.md` | 2026-07-12 | 🟡 Not re-verified since 2026-07-12 | It names no CVE past CVE-29; the classes found since (CVE-30 … CVE-78) are not reflected. Re-read at the next full security audit. |
| `migration-strategy.md` | 2026-09-06 | 📦 Historical | Banner-marked frozen v5.7.39 snapshot. |
| `crash-localization.md` | 2026-07-12 | 🔵 Not re-verified at 6.6.20 | The `CYRIUS_SYMS` mechanism. |
| `module-manifest-design.md` | 2026-05-18 | 🟡 Stale in part | The `[deps]` design is canonical; the 6.6.17 manifest work (`[build]` keys, `--print-config`, `[coverage]`, `[embed]`) is documented in the guide, not here. |
| `benchmarks.md` | 2026-05-19 | 📦 Historical | Bounded to the v5.6.x perf arc by its frontmatter. |
| `process-notes.md` | 2026-06-04 | 📦 Historical | Bounded to pre-v5.0.0 phases by its frontmatter. |

---

## Tier 4 — ADRs (`docs/adr/`)

6 ADRs. Re-read pass quarterly; ADRs document decisions, not status.

| File | Last touched | Status | Notes |
|---|---|---|---|
| `001-assembly-cornerstone.md` | 2026-09-08 | 🔵 Evergreen | Foundational principle. |
| `002-everything-is-i64.md` | 2026-07-06 | 🔵 Evergreen | Carries the SIMD-vector and float exceptions (its §2 and the closing note) — the distinction this ledger used to ask for is written. |
| `003-fixed-heap-layout.md` | 2026-10-06 | ✅ Re-derived 6.6.20 | Its layout summary was five relocations stale (input_buf at 0x0, tok_names at 0x60000, output_buf in-heap, heap top 0x5E1D000, fn ceiling 32,768); re-derived from `src/main.cyr`'s HEAP MAP (HEAP-11). The map wins. |
| `004-convention-based-dispatch.md` | 2026-04-05 | 🔵 Evergreen | Foundational; v6.7.x's traits ADR will amend it or sit beside it (roadmap_6.md § v6.7.x). |
| `005-two-step-bootstrap.md` | 2026-06-28 | 🔵 Evergreen | Bootstrap chain principle. |
| `006-registry-sovereignty.md` | 2026-05-05 | 🔵 Evergreen | Sovereignty pattern. |

---

## Tier 5 — Audits (`docs/audit/`)

Periodic audit reports; per-audit timestamped (don't refresh in place — supersede with a new audit doc, or append a finding with its CVE id).

**3 active** + **5 archived** (`docs/audit/archived/`). *(This section read "0 active" from 2026-06-09 until 6.6.20, while three active audits accumulated.)*

| File | Status |
|---|---|
| `2026-09-03-security-audit.md` | The last full audit (cycc 6.5.45, CVE-38 … CVE-42); every CVE spent since is appended to it — through **CVE-78** (6.6.18). The next free id is **79**. |
| `2026-07-27-security-audit.md` | Full audit at cycc 6.4.82 (CVE-32 … CVE-36; CVE-37 / CVE-38 withdrawn). |
| `2026-06-10-deep-dive-review.md` | Deep-dive review at cycc 6.1.31 (… CVE-31). |
| `archived/` (5) | 2026-04-13 security audit, 2026-05-01 pre-5.8.0, 2026-04-26 stdlib fn collisions, 2026-04-27 cx direct-emit inventory, 2026-05-11 zero-call stdlib — all with completion banners. |

---

## Tier 6 — Issues + Proposals (`docs/development/issues/`, `docs/development/proposals/`)

Open issues are tracked artifacts (filed by consumers or internal observation). Archived when resolved.

**Re-derived 2026-10-06 (v6.6.20).** *(This section had listed the June 2026 open set — seven files, every one long since archived — until then.)*

- **Open issues: 0** — `issues/` holds only `README.md`, `archived/` (**473** files) and `repros/` (binary + source repro storage, not tracked filings).
- **Open proposals: 2** — `2026-07-05-const-eval-comptime.md` (P3 `const fn` → roadmap_6.md § v6.7.x C1; its header re-stamped at 6.6.20) and `2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md` (P5: A shipped 6.6.17, B execution coverage → v6.7.x with C2). **34** archived.
- Out-of-scope finds live in roadmap.md's *Potential backlog* (re-triaged at 6.6.20), not as issue files.

Per the `feedback_close_to_archive_issues` memory pin: re-opens are a `git mv` back, not a re-file.

---

## Tier 7 — FFI / Reference (`docs/ffi/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `fncall-abi.md` | 2026-09-17 | 🔵 Not re-verified at 6.6.20 | `fncallN` (int-class scalar calls). |
| `struct-packing.md` | 2026-04-19 | 🔵 Not re-verified at 6.6.20 | `fncallN` struct-by-value shims. |

---

## Tier 8 — Archive (`docs/development/archive/`, `docs/development/issues/archived/`, `docs/development/proposals/archived/`)

| Path | Count | Status |
|---|---|---|
| `docs/development/archive/` | 8 | 📦 Frozen — historical (cyml-format, two handoffs — v5.3.13 and **v6.6.4, archived 2026-10-06** — the v5.3.0 emitter, 2026-04 benchmarks / aarch64 stdlib, lsp-claude consolidation, the 2026-10-02 6.6.x-tail sequencing memo) |
| `docs/development/issues/archived/` | 473 | 📦 Frozen — resolved issues |
| `docs/development/proposals/archived/` | 34 | 📦 Frozen — shipped or closed proposals |

Leave alone unless they need re-classification (e.g., something archived prematurely surfaces again).

---

## Refresh procedure

When docs are touched:

1. Find the affected row in the relevant tier table.
2. Update **Last touched** to the new date.
3. Update **Status** if the bucket changed.
4. Update **Action** if the next step changed.
5. If a doc moved or was archived, update its row.
6. Re-anchor "Last refresh" date in the header.

When the bucket counts at the top drift by more than ~3 in any cell, refresh the at-a-glance table.

This file's refresh cadence is **opportunistic** (touched when other docs are touched), not periodic.

---

## What this file is NOT

- Not a substitute for [`development/state.md`](development/state.md) (which holds cross-repo cycle / pin / sweep state).
- Not a CHANGELOG (which records what shipped, not what's stale).
- Not a TODO list (open work for the project lives in [`development/roadmap.md`](development/roadmap.md)).
- Not a per-doc review log (this is the ledger of where each doc stands, not the per-doc reasoning).

---

## Forward doc-policy commitments

Items that are *scheduled* doc decisions, not stale state. Surfaced here so they aren't forgotten when the trigger date arrives.

| # | Commitment | Trigger | Source | Notes |
|---|---|---|---|---|
| 1 | **Vidya sync per minor closeout** — `vidya/content/cyrius/*.cyml` (language, field_notes/{compiler,language}, implementation, types, dependencies, ecosystem) refreshed at every minor closeout per CLAUDE.md "Closeout Pass" step 11. Vidya entries reference cc-binary-name + version + non-obvious gotchas surfaced in the minor. | Every minor closeout | [`CLAUDE.md`](../CLAUDE.md) "Closeout Pass" §11 | Manual — `version-bump.sh` doesn't touch vidya. Cross-check version refs every closeout: vidya files saying `cycc 5.4.x` / `cycc 5.8.x` should match current VERSION (the historical `cc3 4.8.5`-style refs hold pre-v5.0.0 anchor context). |
| 2 | **Periodic security audit** — full source scan for vulnerable patterns (sys_system / READFILE / bounds-check gaps / etc.) before major releases or after significant surface change. | Before each major release; cycle audit every 2-3 minors | [`CLAUDE.md`](../CLAUDE.md) "Security Audit Process" | **Current (re-derived 2026-10-06):** the last full audit is `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45), with every CVE spent since appended to it through CVE-78; the next free id is 79; 6.6.20's closeout ran the §9 re-scan as one of its audit passes. *History, as this cell read before:* Last full audit: 2026-04-13 + 2026-05-01 (pre-5.8.0). v5.11.41 shipped CVE-08 hardening + v5.11.65 CVE-05 mangle-path guard piecemeal. **TRIGGER PASSED**: the pinned "before the v6.0.0 cut" full audit did NOT run as a standalone artifact — v6.0.0→.3 shipped (rename + two codegen P1s + deps-lock fix) without it. **RESOLVED (leader, ~late May 2026):** the full audit WAS run ~2 weeks before the 2026-06-07 closeout — the prior "overdue / never ran" note here was stale (the artifact is not under cyrius's own `docs/audit/`, so it was filed at the ecosystem level, not this repo). The v6.0.91 closeout ran only the §9 *quick* re-scan (clean: no new vulnerability class in .88–.90; byte-array peephole bounds-checked — pass-1 cap + per-arch disp caps), which is all the closeout calls for. NOT overdue. **Separate, still open:** vidya `dependencies.cyml` dep catalog is stale beyond this cycle (sigil listed 2.9.3 vs current 3.7.7) — a fuller vidya refresh than the per-closeout gotchas add is its own task. |
| 3 | **API surface snapshot regeneration** — `docs/api-surface.snapshot` regenerated as part of `check.sh`; gate fails if drift. | Every release | `cyrius_api_surface` binary; gate in [`scripts/check.sh`](../scripts/check.sh) | Already automated; included here for visibility. |

---

*Initial scaffold: 2026-05-10 (v5.10.34). First full stale sweep: 2026-05-13 (v5.11.42 — caught 13 patches of drift, 3 archived issues miscategorized as open, 2 untracked proposals, 1 untracked doc, 1 new audit, +19 archived issues, retired v5.12.x ADR-008 reference, v6.0.0 audit re-pin) + proposals-archive pass (caught 3 already-shipped proposals miscategorized as open). Second sweep: 2026-05-13 (v5.11.50 — doc-currency programmatic gates landed). Third sweep: 2026-05-17 (v5.11.59 — iron-boot 4-slot arc fully closed; +8 archived issues; +2 open proposals (kriya M2 v6.x targets); cycc-size refresh 823 KB → 875 KB across Tier 1 docs after the +52 KB drift past the ±50 KB currency gate). Fourth sweep: 2026-05-18 (v5.11.63 — .60-.63 commandress papercut absorber band CLOSED + dedicated doc-health read-through retiring 7 of 8 🟠 carryovers; bench-infrastructure orphan finding: `BENCHMARKS.md` auto-gen system was live since v5.7.x but doc pointers sent readers at frozen v5.6.x narrative instead; pointers fixed + fresh bench run caught +65 % self_compile regression vs 2026-04-18 to investigate; only `migration-strategy.md` remains 🟠 (deferred to v6.0.0 doc-pass per user direction)). Refresh in place when docs are touched.*
