# Cyrius Development Roadmap — v6.6.x (active minor)

**Scope** — the **current active minor only** (v6.6.x). This is the slot-pinning working
artifact: the repair window, the proposal queue, the committed ergonomics list, and the
unscheduled 6.x backlog. Whole-cycle framing plus v6.7.x/v6.8.x live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slots) → [roadmap_6.md](roadmap_6.md)
> (v6.7.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

> ⚠ **This file was rewritten 2026-09-08 at v6.6.1.** It had been 1,043 lines still titled
> *"v6.5.x (active minor)"* — a closed minor — of which **~480 lines were a slot list where every
> entry read ✅ SHIPPED**. CLAUDE.md's rule is that closed-minor detail lives in the CHANGELOG and
> [completed-phases.md](completed-phases.md) and that this file carries **only what is still
> ahead**; that rule had been violated for a whole minor, which is the same drift the 2026-07-29
> re-scope removed from `roadmap_6.md`. The v6.5.x narrative was not deleted — it is in the
> CHANGELOG per-patch and summarised in `completed-phases.md`'s v6.5.x band. **Do not re-add
> shipped slots here.**

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: v6.7.x/v6.8.x RISC-V
  rv64, cycle budgeting, and the shape of what follows v6.x.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger**.
- [state.md](state.md) — volatile current state. Refreshed **by hand** every release —
  `version-bump.sh` never touches it (its closing summary names the rows to update).
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.6.12** (2026-09-30) — cycc **1,437,168 B** (`.text` **1,265,408**) ·
seed-derive **GREEN** · cross-OS **GREEN** on ecb/ach/cass/pi · self_compile **849 ms** ·
**403** `.tcyr` (**149** in `crossos/`) · **104** `lib/*.cyr` · **305** shell gates under
`tests/gates/<bucket>/` · **0 open issues** · **6 open proposals**.

> ⚠ **Every figure above was DERIVED on the day, not carried** (re-derived 2026-09-27 at the 6.6.7 open).
> `version-bump.sh` rewrites the version token, replaces the `(…)` after it with the bump date, and
> nothing else — **the numbers beside it are yours to re-derive.** Keep the stamp at the start of its
> line and its parenthetical free of nested `(`/`)`, or the bump refuses to rewrite it (and
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red the day it is written). Re-derive gates with `find tests/gates -name '*.sh' | wc -l`; never increment.

**v6.6.0 opened this minor** with its one breaking change: `Result` / `Option` / `Either` are the **value
form** (construction allocates zero bytes), shipped WITH the ecosystem. **v6.6.1–v6.6.6** were the repair
window: 6.6.1 closed the issue queue, 6.6.2/6.6.3 repaired what the ecosystem sweep found, 6.6.4 fixed the
59-release native-aarch64 `cyrius run/test` defect, 6.6.5 the nine issues open at 2026-09-17, and 6.6.6 its
27-bite follow-on (five lanes; see CHANGELOG). **The repair window is CLOSED.** Per-release detail is in the
CHANGELOG; do not re-add shipped slots here.

---

## The 6.6.7 → 6.6.12 batch (planned 2026-09-27; 6.6.10–6.6.12 added by the user 2026-09-28/29; CLOSED at 6.6.12)

After the 6.6.6 tag the ecosystem filed **28 new issues** in a week (agnodrm, agnostik, kybernet, daimon,
patra, sigil, kavach, tyche, hisab, samay, sakshi, vani, libro, aethersafha, agnos), on top of the two
6.6.6 left open and the ten-item tail it deliberately did not pack. **The user split that track across three
releases so each batch stays small** (6.6.6 was 27 bites and 193 commits — too big).

Every item was premise-checked against live code at `99a03056` and then adversarially re-verified by a
second, independent agent (15 themed clusters). That pass confirmed all 30 filings still open, and it
also turned up **~40 defects of the SAME classes at sites nobody had filed**: a nested-fn emitter that
drops the enclosing fn's pending returns, `-1.0` evaluating to `-4.0`, an unrouted arm64-macOS syscall that
re-runs a stale `x16`, and lint walkers that score a crashed tool as clean. Under *"an audit's output is
fixes, not a backlog"* those are placed INTO the bite that owns their class, not filed. Six items were
found already shipped or wholly a sibling's (see *Not placed*).

### Rules for these releases

- ⛔ **Releases are strictly sequential.** 6.6.8 does not start until 6.6.7 is tagged, and the same for
  6.6.9. **Parallelism happens only INSIDE a release**: independent bites run in git-worktree **lanes**, and
  each lane owns its files outright (one owner per shared file per release, listed below).
- **One implementer + one reviewer per bite, reviewing THE BITE.** ⛔ Since 2026-09-29 (user: "6.6.x is not
  just find all the bugs when fixing bugs"): a reviewer's out-of-scope find goes to the *Potential backlog*,
  never automatically into a later release — only the user promotes it. Agents do not sweep the tree for
  unrelated defects; they report a severe one met in passing (security, silent corruption) in one line.
- **At most two `src/` lanes per release, and only ONE of them commits `build/cycc`.** The other commits
  source only; the binary is rebuilt once, at the merge, with fixpoint + seed-derive.
  `build/cycc-native-aarch64` is regenerated ONCE on the merged tree (`cyrius pulsar`, release-gate
  step 1b).
- **A per-lane green is not a merged green** (the 6.6.6 lesson: five green lanes merged into four
  failures). `check.sh`, seed-derive, ARM lockstep, cross-OS on ecb/ach/cass/pi, agnos-qemu where named,
  and the bench all run on the MERGED tree, with the box quiet (`check.sh` goes RED under load until
  6.6.8 bite 8 makes deadline kills say so).
- **CVE ids**: 6.6.7 spends **CVE-46** (bite 1 — a `secret var` in a closure body was never
  zeroised), **CVE-47** (bite 2) and **CVE-48** (bite 4); 6.6.9 spent **CVE-49** (bite 10) and **CVE-50** (bite 12, the `lib/http.cyr` request overflow); 6.6.10 spends **CVE-51**, **CVE-52** and **CVE-53**. Each
  bite bumps the CLAUDE.md counter in the same commit. *(This line first planned CVE-46 for bite 2;
  bite 1's audit finding spent it first, so every later id moved up one.)*

### 6.6.7 — SHIPPED 2026-09-28 (tag `6.6.7` @ `f07395ce`)

All ten bites shipped as planned, in six worktree lanes merged into main; detail is in
`CHANGELOG.md` [6.6.7]. The twelve filed issues it fixed are archived (the daimon clock one by
its bite); each filed repro was re-run on the merged tree. It spent **three** CVE ids, not two:
**CVE-46** (a closure's `secret var` was never zeroised — bite 1), **CVE-47** (a `secret var`
skipped on a tail return — bite 2), **CVE-48** (on agnos a 127.0.0.1 server listened on the
network — bite 4); 6.6.9's planned CVE is therefore **CVE-49**.

⚠ **The merge again found what no lane could** (the 6.6.6 lesson, repeated): each lane's
`check.sh` was green, and the merged tree went red three ways — bite 7 sized an array by an enum
that the fold lane's larger bundles pushed past var index 1024 (6.6.8 bite 1's cap), bite 7's
new derived clock axis caught bite 4's unchecked #95 read, and bite 7's gate expected a
`syscall` adjacent to its number where bite 4 now zeroes `r10` in between.

**⛔ Sibling releases the fold took, by commit — tag each at that commit BEFORE the cyrius 6.6.7
tag:** sandhi **1.10.1** `f93d035` (cut during the fold: macOS EAGAIN is 35, and PE had been
borrowing yukti's `SYS_SOCKET`), vani **1.2.7** `5cdd402`, sigil **3.13.3** `92a5042`, yukti
**2.3.13** `ff97eec`, mabda **4.1.5** `2a9f67c`. sakshi 2.5.5, patra 1.15.0, niyama 1.0.12 and
bayan 1.5.7 were folded from their existing tags.

### 6.6.8 — SHIPPED 2026-09-28 (tag `6.6.8` @ `68eb2661`, a re-cut after CI's Test (AGNOS) job went red on the first tag)

All eleven bites shipped (bite 1b — the nested-emitter and derive follow-ups — included), in six
worktree lanes merged into main; detail in `CHANGELOG.md` [6.6.8]. The seven filed issues it fixed
are archived by their bites. No CVE was spent. **Sibling releases the fold took, by commit — tag
each BEFORE the cyrius 6.6.8 tag:** yukti **2.3.14** `bcc8cb0` (ppoll declines on macOS) and
ganita **1.2.7** `3c15403` (`pow` follows C99 Annex F).

⚠ **The merge found two more lane interactions, again invisible per lane:** bite 7's new
`agnos_process_peer_parity` gate required agnos peers for five host verbs bite 8 added in another
lane, and bite 8's new `check_gate_census` ratchet (gates hard-coding `CC`, measured at 74 on its
own lane) saw 80 once six other lanes' new gates arrived — converted to `${CYCC:-…}` rather than
raising a ratchet that only goes down.

⚠ **aarch64 size tax measured at the merge:** `build/cycc-native-aarch64` `.text` +82,952 B — bite 3's
nine ESYSXLAT rows copied into each of 605 syscall sites (backlog: a shared translation stub).

### 6.6.9 — SHIPPED 2026-09-28 (tag `6.6.9` @ `a5f6691e`)

All twelve bites shipped (bite 12 — `lib/http.cyr`, CVE-50 — added by the user from the 6.6.8 review
finds); detail in `CHANGELOG.md` [6.6.9]. The last ten filed issues are fixed and archived — the open
issue queue is empty. **CVE-49** (bite 10) and **CVE-50** (bite 12); the next free id is 51. No sibling
release. self_compile −17 % (bite 1's global-name index).

⚠ **Merge lessons, third release running:** bite 7 (stdlib self-sufficiency) needed two small hunks in
files lane S2 owned, which S2's bite never picked up — the lane handed over a verified patch instead of
crossing its ownership line, applied at integration; and that same self-sufficiency made a gate's
"file that cannot resolve" fixture (a copy of `lib/fs.cyr`) resolve. When a plan gives one lane's
bite a dependency on another lane's file, name the hand-off in BOTH lanes' specs.

### 6.6.10 — SHIPPED 2026-09-29 (tag `6.6.10` @ `20240fd8`)

All seventeen bites shipped; detail in `CHANGELOG.md` [6.6.10]. **CVE-51** (x86-macOS clock stray write),
**CVE-52** (stray `@`), **CVE-53** (`ws_recv_frame`); the next free id is 54. Nine sibling patch releases
(tag list in `state.md`). The merge had no conflicts — one lane owned every gate registration and every
cross-lane hunk travelled as a named hand-off patch. ⚠ Remaining merge lesson: a ratchet's "final pass"
(the cross-compile allowlist, the alloc census, the gate census) cannot run inside a lane that works in
parallel with the lanes it measures — it is an integration step, and it is now done there.

### 6.6.11 — SHIPPED 2026-09-30 (tag `6.6.11` @ `a6aa3375`)

All fourteen bites shipped; detail in `CHANGELOG.md` [6.6.11]. **CVE-54** (on Windows the resolver read a
drive-relative `C:\etc\hosts`) and **CVE-55** (a multi-line string literal defeated `private`); the next
free id is 56. Sibling releases: sandhi 1.10.3 and ganita 1.2.9 folded; stiva 3.0.21, mehman 1.0.4, libro
2.10.4, bote 3.3.14, dhvani 2.2.5 and agnosai 2.1.1 not vendored (commits and tag order in `state.md`).
J5b took the smaller option: `tls` / `tls_native` / `sigil` are refused by name on cx. The merge had one
conflict (two lanes' additions to the same cross-OS leg, both kept), and one integration fix: a driver
description carried a `\<LF>` example that B05's own escape rule refuses. The lanes' out-of-scope finds
went to the backlog below and to the sibling follow-ups — not into 6.6.12.

### 6.6.12 — CLOSED 2026-09-30 (awaiting the tags); the repair batch ENDS here

All twenty bites shipped; detail in `CHANGELOG.md` [6.6.12]. **CVE-56** (`log_info_kv` stack overflow),
**CVE-57** (the folded sandhi resolver read a plantable `C:\etc\resolv.conf` on Windows) and **CVE-58**
(cxvm guest bytecode wrote the interpreter's own memory); the next free id is 59. Seventeen sibling patch
releases — seven folded, ten consumers (commits and the tag order in `state.md`). R4 shipped (typed-array
subscripts); its remainder is Phase 3 item 3. Not placed: R6, T2, T5, SA3 and SA5 (already fixed or false);
the agnos fork item is handed to agnos. The merge had no conflicts. ⚠ Process lesson: a reviewer
hand-extracting a sibling CI step ran its "Install Cyrius toolchain" block against the live `~/.cyrius`
(the active version flipped to 6.6.10 for a minute; reverted, the slot still equals its tag) — sibling CI
now runs only through the runner, with `HOME` and `CYRIUS_HOME` pointed at throwaway dirs. The lanes'
out-of-scope finds went to the backlog below, not into a release. **From 6.6.13 the minor returns to
Phase 2 (proposals) and Phase 3 (committed ergonomics).**

### Sibling follow-ups found at the 6.6.12 releases (each is that repo's next patch release)

- ⚠ kriya `k_isatty` does TCGETS into a 16-byte `var tio[16]` (termios is 36 B): a stack overrun on
  every tty probe, a crash on aarch64 (`cp -i`, `mv -i`, `ls` on a terminal) — recorded for kriya 1.7.4,
  which also adopts 6.6.12's aarch64 wrappers after the cyrius tag.
- bayan `_toml_unescape_span_a` answers a refused allocation with `str_from("")` from the DEFAULT
  allocator, so its value arms report an empty string as success.
- mabda still names `_sk_info_cstr` in sakshi's `_sk_` namespace (no collision today).
- sakshi's "Run under qemu" step calls `qemu-aarch64-static`, which exists only after its apt step.
- bote still commits live `path = "../libro"` / `"../majra"` lines (the dhvani/libro shape 6.6.12 removed).
- aethersafha: 21 files not `cyrius fmt`-clean on 6.6.11 (its CI has no fmt step); duplicate-fn warnings
  between sigil and the agnostik / agnodrm bundles (`_hex_nibble`, `result_print_err`, …).
- sankhya's README / CLAUDE.md name varna 2.1.0 / itihas 2.4.0 / avatara 2.9.0; its 3.0.2 lock pins
  2.4.1 / 2.5.0 / 2.14.8.

### Not placed in 6.6.7–6.6.9

- **Already shipped** (their roadmap bullets are removed below): lexer attribute prefix (6.6.6 bite 5),
  preprocessor directives in strings (6.6.6 bite 4), top-level block closure (6.6.6 bite 3), `cyrius-init`
  on Windows (6.6.6 bite 6), distlib leaf OOM (6.6.3).
- **DCE compaction on PE / x86 Mach-O / aarch64** — the XL arc below (formerly repair slot `.4`–`.5`).
  **Default: the anchor `src` lane of the release after 6.6.9.**
- **The two 2026-09-20 proposals** (coverage over run programs; fuzz poison through an allocator seam) — Phase 2
  (P5, P6). Their prerequisite defects ship in 6.6.8 bite 9 and 6.6.7 bite 8.
- **ESYSXLAT emits its whole translation chain INLINE at every aarch64 syscall site** — measured at the 6.6.8
  merge: `build/cycc-native-aarch64` `.text` 1,495,592 → 1,578,544 B (+82,952 over 605 `svc` sites, ~137 B
  per site) because 6.6.8 bite 3 added nine rows and every row is copied into every site. Every aarch64
  program pays it, and each new row makes it worse. A shared translation stub (one call per site) would
  cut it to a few bytes a site. Correct today; a size tax, so it is placed here rather than in a release.
- **Fold bundles that are raw-includable** — an XL cross-repo campaign (a distlib change released first, then
  ten sibling regenerations, then a re-vendor); backlog, below.

---

## The shape of v6.6.x

| Phase | Slots | What goes here |
|---|---|---|
| **1 — Repair window** | `.2` – `.6` | ✅ **CLOSED at 6.6.6.** |
| **1b — the consumer batch** | `.7` – `.9` | The 6.6.7 → 6.6.9 batch above. |
| **2 — Proposals** | after the batch | The open proposals, sequenced by their own stated prerequisites. |
| **3 — Committed ergonomics** | after proposals | The v6.6.x "best of the best" language-import list, carried in from `roadmap_6.md`. |

---

## Open arc — DCE cannot compact on PE, x86 Mach-O or aarch64 (the rip-relative repair)

**Arrived from v6.6.1.** `CYRIUS_DCE=1` now declines the whole-program compaction on PE and x86
Mach-O, exactly as it already declines under `_pie_mode`, because both reach a live import/stub
table through a **rip-relative disp32 that the compaction pass does not repair**, and both
compute file geometry *before* elimination runs. Declining was the correct release fix — those
targets emitted a binary that faulted `0xC0000005` before `main` (PE) or SIGSEGV'd on real
Intel-Mac hardware (Mach-O) — but it leaves them on NOP-fill: **correct, and not shrinking.**
ELF still eliminates for real (measured 123,048 → 16,552 B, −86.5%).

**The repair is two things that must land together**, which is why it is scoped at two slots:

1. **Repair the rip-relative shape in `wp_compact`** — when a body is removed, every `disp32`
   whose target is *not* code that moved by the same delta needs re-patching. This is the same
   repair `_pie_mode` needs, so doing it unblocks PIE compaction too; do not build a PE-only
   version of it.
2. **Re-run `_pe_layout(S)` after compaction** (and the Mach-O equivalent) so section geometry,
   RVAs and `PointerToRawData` describe the code that was actually emitted — with the ftype=4
   IAT-reference fixups patched **after** that re-layout, since their displacement is computed
   from `_pe_idata_rva`.

⚠ **Order matters and the current code proves it**: the IAT displacement in the broken build
resolved to RVA `0x39DD` for an IAT the header put at `0x23000` — it had been patched against the
old geometry and then the instruction moved. Fixing geometry without fixing displacements, or the
reverse, produces a binary that looks fine and faults later. That is exactly the shape that cost
three attempts at the v6.5.72 compaction work.

**Acceptance**: `tests/gates/codegen/dce_pe_macho_layout_declines_compaction.sh` is **inverted** —
its axes 1-2 currently assert the payload does *not* move, and on success they must assert PE and
Mach-O shrink *and still run*. Verify by RUNNING on `cass` and `ach`, not by size alone; the
whole defect class is "smaller and broken". Keep axis 3 (ELF still eliminates) unchanged.


**Placement (default taken 2026-09-27): the anchor `src` lane of the release after 6.6.9** — it does not fit
6.6.7–6.6.9 without a third compiler lane. Premise re-checked at the 6.6.7 open: the decline is live at
`src/backend/x86/fixup.cyr:875-876`; `_pe_layout(S)` runs at `fixup.cyr:146` (the comment at `:859` and the
gate header still say "line 123"); the ftype=4 IAT disp32 is baked at `:295-300`, before compaction runs at
`:877-878`. ⚠ **Wider than the slot said**: `wp_compact` also returns 0 for EVERY aarch64 target
(`src/common/ir.cyr:1634`), so arm64 Mach-O and aarch64 ELF never compact either — the same arc, taken
together. Until it lands, the declined-path note should say it declined and why.

---

## Phase 2 — the proposal queue

Six open proposals, sequenced by their own stated prerequisites rather than by size.

### P1 — `cyrius.cyml` as the build tool's actual configuration
[`proposals/2026-09-04-build-tool-manifest-integration.md`](proposals/2026-09-04-build-tool-manifest-integration.md)

Filed 2026-09-04, 🟡 OPEN. **Sequence it first, and adjacent to `.2`** — both are about the CLI
honouring its own manifest, and `.2`'s guard needs to read the declared `src`/`entry` key, which
is precisely the surface this proposal is about.

⭐ **The lesson it already records is the reason it ranks first**: the v6.5.49 slice shipped
**inert**. Its `[build]` path fallback read `src`, the key *this* repo happens to use — but of
125 `cyrius.cyml` files across `~/Repos`, **120 declare `entry` and 5 declare `src`**, one of the
five being cyrius itself. So the feature presented as *"does not exist"* to 96% of the ecosystem,
and **its gate passed the whole time because the gate's fixture manifest was written with the
same key the implementation read.** Any work here must gate against a fixture that does *not*
share the implementation's assumptions.

### P2 — Embed data files as source strings (`[embed]` / assets manifest)
[`proposals/2026-08-10-embed-data-files-as-source-strings.md`](proposals/2026-08-10-embed-data-files-as-source-strings.md)

Ergonomics, not capability — the generated-`.cyr` idiom already works and is fleet-wide, and
agnosai ships its own generator, so nothing is blocked. **Its prerequisite has cleared**:
`2026-06-25-source-level-version-constant` shipped at v6.5.21, and `PP_EMIT_PKGVER`
(`src/frontend/lex_pp.cyr`) is the template for a `#@embed` arm.

⚠ **Hard constraint learned at `.21`**: an injected directive must emit **ZERO newlines** (merge
onto the following source line) or it shifts every `<source>` diagnostic by one — a 1-for-1 line
replacement is **not** line-neutral.

### P3 — Compile-time evaluation (`const fn` / const-eval)
[`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)

**The rung was already chosen 2026-07-07** — option 1 `const fn` primary, option 3 `#phf`
fallback, option 4 (a general const-eval VM) declined. No maintainer decision is outstanding, and
a first triage pass that labelled this "blocked on maintainer" was refuted on re-check. This is
also **item 2 of the committed ergonomics list below** — the proposal and the roadmap row are the
same work, which is why it sits at the phase 2/3 boundary rather than being listed twice.

⚠ It reuses the `ir_const_fold` fixpoint (`src/common/ir.cyr`), so it must land **after** any
work that rewrites that pass, or the churn is paid twice.

### P4 — test-only stdlib leaves, instead of hiding them from the umbrella scan
[`proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md`](proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md)

Filed 2026-09-16 by **rekha 0.4.4**, 🟡 OPEN. Nothing is blocked — rekha shipped the workaround —
so rank it by appetite, though it is **adjacent to P1**: it is the same complaint, that a
manifest does not say what the tool actually reads.

`dist/<pkg>.deps` unions the include scan of **`src/lib.cyr`** (path hardcoded at
`cbt/commands.cyr:3903`) with `[deps] stdlib`, so a harness-only leaf has nowhere to live that
is not published. rekha carried **nine** leaves for a bundle that calls `strlen` + `memcpy`;
consumers vendored eight leaves of nothing for four releases. The fix — move the harness
includes into `programs/prelude.cyr`, a file the scan does not read — cut the sidecar to
`string alloc` with **byte-identical** bundles, and is the discomfort being reported: *which
file an include sits in* decides what every downstream consumer must vendor.

⭐ **`_distlib_verify_leaves` is the part that works** and the proposal explicitly does not touch
it — it derived `alloc` unaided, because `lib/string.cyr` calls `alloc()` and declares no include
for it. Option 3 in the filing is to trust it as the *sole* authority and delete the two
over-reporting channels, which would have produced rekha's correct answer with no declaration
discipline at all.

⚠ **Two measured notes from the filing that outlive whatever shape this takes.** (a) Auto-prepend
puts every resolved leaf in scope, so a package's own tree **cannot** check its own sidecar — a
program with no includes at all compiles while calling `alloc`/`strlen`/`vec_new`, and a
"compile it the way a consumer does" suite therefore passes a sidecar that omits a needed leaf.
Only `_skip_deps = 1` catches it. (b) `_distlib_verify_leaves`' header reasons that
over-reporting is the safe direction; that holds for a *misspelled* leaf (hard resolver error)
but not for a *real* leaf that is merely unnecessary, which is silent. Over-reporting is
quieter, not safer.

### P5 — `cyrius coverage` over RUN programs, not only `.tcyr` suites
[`proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md`](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md)

Filed 2026-09-20 by **rekha 0.4.12** (25 self-checking `programs/*_test.cyr`, ~13,000 lines of assertions,
coverage reported as ~0 %). ⚠ **Its prerequisite ships first**: 6.6.8 bite 9 fixes how coverage COUNTS
(substring and comment matches, a denominator that drops public fns), and extending the corpus before that
would widen a number that is already wrong. The open scope question — a text-reference corpus versus
execution/branch coverage — is the proposal's, and gets asked when this slot opens. Size: M on top of 6.6.8.

### P6 — `cyrius fuzz --poison` through a custom allocator seam
[`proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md`](proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md)

Filed 2026-09-20 by **rekha 0.4.12**, which parses untrusted font bytes through sadish's `sd_alloc` seam and
hand-built a 2,100-line substitute because `--poison` only redzones the freelist. The overlapping piece —
freelist poison comments that no longer describe the code, and a `--poison … ACTIVE` message that claims
coverage it does not have — ships in 6.6.7 bite 8. The design fork (a redzone/fill seam versus guard-page
faulting) is the proposal's. Size: M.

---

## Phase 3 — the committed ergonomics list

**Theme set 2026-07-07 (user, horizon session).** RISC-V rv64 — previously this minor's theme —
was re-homed to v6.7.x/v6.8.x: hardware is in hand, but a 7th platform is deliberately held while
*"still heavy quality and ergonomic improvements [are] on the horizon."* v6.6.x instead takes the
modern-language feature imports that fit the assembly-up identity — **no GC, no hidden control
flow you cannot disassemble.**

1. ✅ **SHIPPED v6.6.0 — `Result` / `Option` / `Either` are the value form.** The one breaking
   change in the minor, at the front of it because everything else is additive. Detail in the
   CHANGELOG; do not re-plan it.
2. **`const fn` — the const-eval ladder, option 1.** See **P3** above; same work, listed there
   with its sequencing constraint.
3. **Opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`) — designed in the v6.3.x
   plan, never shipped. Verified live: `CYRIUS_BOUNDS`, `#bounds` and `_bounds_check` find **0**
   hits in `src/`. The sanitizer story that makes footguns findable at their source. **OFF by
   default** — assembly-up: raw stores stay raw in release builds. Premise-check the 0-hit count
   at slot entry rather than trusting this line.
   6.6.12 shipped the unchecked half: `a[i]`, `a[i] = v` and `a[i] OP= v` on an integer
   element-typed `var a: T[N]` (R4). What remains here: `*T` pointer subscripts, slice writes, and this
   checked mode.
4. **Trait-bounded generics** — the post-monomorphization ceiling. **DEMAND-GATED tail**: pulls
   in only if consumer pressure materialises by the time the slot opens. Fix the
   **multi-type-param struct-type-arg residual** first (single-tparam struct type-args shipped
   v6.3.38–.39; the residual is only the mixed multi-tparam combo).

~~`defer` / scope-exit~~ and ~~per-block scoping + shadowing~~ were struck 2026-07-29: **both
already shipped** (`defer` at v3.8.0; block scoping verified by running the compiler). They sat
here as pending work for features that had existed for majors. What remains of the scoping row —
that a **same-scope** redeclaration is a hard error — is the documented rule, not a footgun.

**Explicitly NOT imported** (decided 2026-07-07): borrow-checker-style lifetimes (wrong fit for
the trust model and the single-pass design), a general const-eval VM, exceptions of any kind.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **Found by the 6.6.12 premise check and lanes (2026-09-30; backlog, not placed — only the user promotes).**
  Met in passing, not swept for; ⚠ marks silent memory corruption.
  - ⚠ A zero-initialised narrow global clobbers the next narrow global: `var a: u8 = 0; var b: u8 = 7;`
    reads `b` = 0 on x86, aarch64 and PE (the narrow global INIT path in `parse_decl.cyr`; B01 fixed the
    `for`-step and compound paths only).
  - ⚠ Inside a fn, `var a: f64[N]` and `var a: Pt[N]` reserve only N bytes: PARSE_VAR passes
    `scalar_type = 0` for a float or struct element, so PARSE_ARRAY sizes it like a bare `var a[N]`
    (measured: a store at `&a + 16` of an `f64[4]` overwrites a neighbouring local). Top level sizes N*8.
  - ⚠ A captured struct copied into a field inside a closure stores the pointer: `var g = || { var b: Box;
    b.v = p; ... };` with a captured `Pt p` stores p's address into `b.v` (`_fsc_name_src` does not
    resolve captures; pre-existing since 6.6.10's field-store copy).
  - `var v = g<i32>(..)?;` exits 139 on a generic returning a `Result` pair: the expression-side
    `_callee_returns_pair` recognises only `name (`, not `name<T>(`. The statement form (6.6.12 R2) is right.
  - A named >8 B struct argument aliases the caller (`take(q)` passes the address; the guide documents it),
    while 6.6.12 made a FIELD argument copy — decide whether the named form copies too.
  - Windows `sys_symlink` (CreateSymbolicLinkW) widens with `_win_widen` at 519 units, no `\\?\` — a link
    at a path over 260 units fails -1 (honest).
  - cyrius-lsp `lsp_read_file` reads the open document through a fixed 1 MB buffer, silently.
  - The agnos stdlib peer has no `sys_setsockopt` (not even a declining stub), so anything reaching it
    fails to build for agnos (yantra 1.0.7 carries an agnos arm).
  - `async_await_readable_ms` is defined only in `lib/async.cyr`'s Linux branch (sandhi's cooperative
    server loop on macOS is unexercised).
  - x86-macOS `clock_now_ns` assumes the Intel 1:1 mach timebase; unverified under Rosetta (no host).
  - `cyrius lib sync --full` does not re-lock `cyrius.lock`, so rows for files a repo does not vendor keep
    stale hashes until a lock is regenerated from empty (kriya and yantra both hit it).
  - `tests/gates/codegen/cx_forward_read_constant_global.sh` builds relative to the cwd (green only from
    the repo root, where check.sh runs it).
  - The guide's zero-allocation Result example defines `fn use()`, a reserved word — the block does not
    compile (guide_examples_compile.sh skips blocks with no `include`).
  - Inside an aarch64 region (6.6.12 B05's `#@a+` markers) a raw literal that HAS an ESYSXLAT x86-compat
    row is still translated with no warning: `syscall(9, ..)` meant as native lgetxattr runs mmap (also 5 →
    fstat, 55 → getsockopt). Unchanged from 6.6.11 (the raw-literal warning only covers untranslated
    numbers); the native spelling is the 1000+N alias (6.6.12 B09). A region-aware warning for translated
    rows is open.
  - Coverage lost to a CORRECT emulator: with mirshi 1.11.3 filling `sysinfo`'s full tier and emulating
    `uptime_us` (#95), `agnos_sysinfo_tail_parity`'s runtime axis and `agnos_monotonic_clock_rdtsc`'s axis 5
    SKIP by name — the pre-1.57.9 `sched_kicks` pre-fill and the refused-calibration fallback in the stdlib
    no longer run on this box. They need an older-kernel mode (e.g. a mirshi switch) to be exercised again.
  - Inside an aarch64 region (6.6.12 B05's `#@a+` markers) a raw literal that HAS an ESYSXLAT x86-compat
    row is still translated with no warning: `syscall(9, ..)` meant as native lgetxattr runs mmap (also 5 →
    fstat, 55 → getsockopt). Unchanged from 6.6.11 (the raw-literal warning only covers untranslated
    numbers); the native spelling is the 1000+N alias (6.6.12 B09). A region-aware warning for translated
    rows is open.
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
- **DWARF debug-info emission** — backend/codegen work; slot it when a real debugger story is
  needed. Distinct from the DX diagnostics arc, which was only the error-reporting layer.
- **Incremental compilation** — unpin condition: reconsider when cycc self-host crosses ~2 s. It
  is **731–734 ms at 6.6.1** after 150+ releases, so the whole-program model is nowhere near the
  threshold. ⚠ Read the trend with care: the same binary has measured a 52 ms spread across three
  consecutive runs — **wider than most release-over-release deltas** — so a single number carries
  no signal. Every release's mandatory bench run IS the report.
- **`ir_dce` / `ir_dead_store` uncapped wrappers and `CLASSIFY_CF` / `CF_TARGET`** — decide
  wire-or-delete. Leaving a third option open is how they survived two closeouts.
- **Bare `var a[N]` byte-vs-slot convention** — a design decision, not an arc. The typed spelling
  `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is whether to
  lint the address-taken bare-local per-slot idiom.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot). Policy: the
  next new compiler-state scalar goes into a hole rather than growing the band. **Cite the live
  count** (`grep -n FREED src/main.cyr`) and the heap map; do not maintain an enumerated list that
  goes stale every minor.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term".

- **Fold bundles that are raw-includable** — found at the 6.6.7 triage: `log`, `ws` and `ws_server` cannot be
  included alone because the fold bundles they depend on strip their own includes, so the stdlib
  self-sufficiency sweep (6.6.9 bite 7) carries them as a named PENDING tier. The real fix is a distlib
  change released in cyrius first, then ten sibling regenerations + releases, then a re-vendor — an XL
  cross-repo campaign, so it is not packed into 6.6.7–6.6.9.
- **Nine syscall families consumers still hand-roll, unnamed by the stdlib** — the widened
  surface v6.6.5 measured and deliberately did NOT ship. Per-family reasons, consumers and
  collision analysis live in the table of
  [`issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md`](issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md)
  ("Not fixed, deliberately — (b)"). **Pinned here, not left in an archived file**, because a
  deferral is real only when it is pinned somewhere still open. ⛔ **They are in the exact silent
  class thoth filed**: `_SYSX_MEANT` only carries numbers named in BOTH peers, so a NAMELESS
  number produces **no warning at all** (measured: raw 160 on the aarch64 fork warns nothing).
  Two tiers:
  - ⭐ **Tier 1 SHIPPED at 6.6.8 bite 3** — kavach filed for `unshare`/`chroot`
    ([`issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md`](issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md)),
    and shakti is broken on aarch64 today, so `capget`/`capset` and `process_vm_*` ride with it.
  - **No technical blocker, held only as API surface nobody filed for** — `capget`/`capset`
    (125/126 → 90/91, consumers kybernet + shakti), `chroot` (161 → 51, kavach — the row must sit
    BELOW `51 → 204`), `unshare` (272 → 97, kavach), `process_vm_readv`/`writev` (310/311 →
    270/271, mirshi). Each needs a Darwin route-or-decline, and this release's open concern is
    that three Darwin numbers were derived from neighbouring rows rather than an SDK read — so
    take these on a slot that has an ecb/ach leg, not as a tail-end addition.
  - **Concrete blockers** — `ptrace` (101 is the PRODUCT of this release's `35 → 101`),
    `sched_getaffinity` (204 is the product of `51 → 204`), `pread64`/`pwrite64` (17 is the
    product of `79 → 17` and aarch64-native getcwd → needs the ≥1000 alias band), and the
    `rlimit` family (aarch64 has only `prlimit64`, with a different arg list → an arg-shifting
    row, real hand-assembly).
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
   it: **731–734 ms · 1,247,608 B at 6.6.1**. A previously-floated candidate pair was *≤700 ms and
   ≤1.20 MB at minor close* — ⚠ **both halves are now exceeded**, so that pair is an input to
   re-decide, not a target that was missed. Review together with item 2.
2. **The self-compile growth-tax audit — ANSWERED (user, 2026-07-29): likely dropped, but
   re-review WITH item 1's performance track**, the two being the same subject. Explicitly *not*
   silently dropped — parked against that track's opening review, which decides whether it still
   earns a bite. Record the outcome here either way.
3. **macOS concurrency ordering.** Real platform work with a genuinely broken verb on a gate
   host, so it cannot be dropped — but it has **no consumer waiting**, it mirrors an
   already-shipped split (`thread_win`), and the crossos guards mean it cannot rot silently.
   **Default: keep it last in the minor**; pull it forward if a consumer appears.

*(Former item 3 — per-item `private` — was never a question. It is a live defect and is now
slot `.3` above. Former item 2, the bare-metal forbidden-module check, SHIPPED at v6.5.24 after
this section had carried it as "never built" for thirty releases.)*

---

## Standing notes — traps this minor must not re-learn

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
