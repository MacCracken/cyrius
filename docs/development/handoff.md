# Handoff — v6.4.80, entering the v6.4.x closeout

> **Written 2026-07-26 for an account switch.** Read this first, then `CLAUDE.md`, then
> [`state.md`](state.md). This file is the bridge: it carries what an agent would otherwise only know
> from per-session memory, which lives at `~/.claude/projects/-home-macro-Repos-cyrius/memory/`
> (62 files) and **is outside the repo, so it may not travel**. CLAUDE.md's "Working Agreements"
> section exists for exactly this reason — durable knowledge belongs in the repo.
>
> **Refresh or delete this file when the closeout ships.** A stale handoff is worse than none.

---

## Where things stand

| | |
|---|---|
| Version | **6.4.80** (80 releases in the 6.4.x minor) |
| cycc x86_64 | **1,108,272 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **149 passed / 0 failed**; release gate GREEN all 5 steps |
| Cross-OS | ecb (macOS-arm64) · ach (Intel-Mac) · cass (Windows) · pi (aarch64) — all `SELFHOST_OK` + `LIBTEST_OK` on real hardware |
| Corpus | 251 `.tcyr` · 99 `lib/*.cyr` · 97 programs |
| self_compile | ~621–632 ms (quiet box; the release-gate reading is often inflated by concurrent work) |
| Open issues | **11** (target is ~10–12 lean) · 3 proposals · 270 archived |
| Working tree | v6.4.80 uncommitted at time of writing — see "What is uncommitted" below |

Vendored stdlib (all folded, none in `[deps]`): sandhi **1.9.3** · sankoch **2.7.6** · sigil 3.12.1 ·
patra 1.12.12 · yukti 2.2.10 · mabda 4.0.7 · bayan 1.2.1 · ganita 1.0.4 · niyama 1.0.6 · vani 1.1.2 ·
sakshi 2.4.6.

## ⚠ v6.4.80 became a CRITICAL bug fix, NOT the closeout

The closeout doc sweep turned up a live **Critical** codegen bug, so .80 shipped that instead. **The
closeout moves to v6.4.81.**

`1 - 2 + 3` evaluated to **5** on 6.4.79 — the PEXPR tier (`+ - & | ^`) silently discarded its left
operand whenever a literal subtraction went negative. 10 % of a systematic 3-term expression sweep
was wrong. It is the third occurrence of one mechanism (`_cfo = 0` cleared *before* a call that
re-arms it), after cyrius-doom's `A * B * 4` in June and v6.4.74's `PARSE_TERM` sweep — each fix
scoped to the *reported operator* instead of the shape. Fixed at all 16 PEXPR sites; zero occurrences
of the shape remain in `parse_expr.cyr`.

**How it was found matters**: an adversarial verifier ran the compiler to check an unrelated *vidya*
claim about precedence. The doc sweep found a codegen bug — which is an argument for doing these
audits, not skipping them.

**251/251 tcyr were byte-identical across the fix** — the corpus contained no expression of the
failing shape at all. That is why every gate stayed green while 10 % of constant arithmetic was
wrong, and why the regression test was mandatory.

## Next: v6.4.81 is the CLOSEOUT

v6.4.81 ships as the last engineering patch of 6.4.x, before **v6.5.0**. Do not treat it as an
ordinary patch — run the full procedure:

- **Runnable checklist + ledger**: [`cycle-discipline.md`](cycle-discipline.md) "Closeout checklist +
  ledger". Copy the template into a new ledger entry and **record** the results (gate counts,
  judgment findings, follow-ups). The ledger is what makes rot visible across cycles.
- **Durable rationale for each step**: `CLAUDE.md` "Closeout Pass" items 1–12.
- Order matters: mechanical gates fail-fast → judgment passes (heap map, dead code, refactor, code
  review, cleanup) → compliance → docs last, so docs reflect whatever the judgment passes changed.

**Known closeout debt going in** (from the doc-currency audit run in this pass — findings verified
against live code, not against the docs' own claims):
- ~~`docs/doc-health.md` stale at v6.4.72~~ — **DONE**: refreshed to v6.4.79 in this pass (a .73→.79
  entry + fresh stamp block). It does not yet mention .80.
- **vidya** (`~/Repos/vidya/content/cyrius/`) is substantially stale: the bulk of its version
  references cluster at **6.4.48–6.4.52**. CLAUDE.md item 11 calls vidya out as the doc set that rots
  silently because nothing compile-checks it. Two entries are now actively WRONG, not just stale —
  anything stating an 8192-fn table or a 256 KB identifier pool (both changed at .75/.76).
- `cycle-discipline.md` has the ledger **template** but no entry yet for this closeout.

## v6.5.0 — what it opens with

1. **`pub`/`private` visibility** — the committed opener. Design is **settled** (user 2026-07-22):
   a top-level `private` declaration flips that FILE to private-by-default (fns *and* vars); a
   per-item `public` moniker re-exposes; no declaration = today's behaviour, everything public. The
   `_`-prefix convention is explicitly **LATER**. Opt-in per file and non-breaking.
   ⚠ **Read `proposals/2026-07-02-function-visibility-pub-private.md`, not the roadmap prose** — the
   roadmap's "hybrid / derive-from-`_`" framing is superseded and has contradicted itself before.
   Remaining work is implementation, not design: the per-fn **file-id substrate** is the real phase.
2. **Perf-quality arc** — IR/regalloc substrate + passes. The `CYRIUS_IR=3` failures are bounded,
   fixable bugs; this is where they get fixed. SIMD register-residency is gated on this substrate.
3. **Stackless coroutines** — ▲ newly PINNED to v6.5.x (user, 2026-07-26). stiva filed the live
   consumer that `roadmap-future.md` had been waiting for. Bound here because the poll-runtime rework
   + force-once memoization is the *same substrate* the perf arc opens — doing it earlier builds that
   substrate twice. Its issue is deliberately left **open** as the acceptance record.
4. macOS-arm64 threading also homes here.

Later: v6.6.x language ergonomics · v6.7/6.8 RISC-V. **Nothing codegen ever parks to 7.x** — 7.x is
the language book + legal-for-public-release, and only that.

## Open queue (11) — the shape

- **5 are v6.5.x-homed, leave alone**: 2026-07-02 IR/regalloc ×2, 2026-07-03 macOS threading,
  2026-07-06 SIMD register-residency, 2026-07-07 D1/D2 closeout residuals.
- **1 pinned-and-open by design**: 2026-07-25 stackless coroutines (acceptance record for v6.5.x).
- **2 ready to pick up, small and high-value**:
  - `2026-07-26-no-lchown-wrapper-...` — the **entire chown family** is absent from the Linux syscall
    layers, so consumers hardcode x86_64 `92`, which is **`exit_group` on aarch64**. A container
    runtime unpacking a tar layer silently terminates on ARM. Fix the family, not just `lchown` (a
    filing enumerates what it hit, not the class).
  - `2026-07-26-distlib-has-no-all-profiles-mode` — `cyrius distlib` regenerates one bundle per
    invocation; 36 sub-profiles across 6 repos each need a manual call. Both hand-rolled CI loops in
    the ecosystem have already drifted (sankoch omits `zip`/`zipall`, sigil omits `argon2`).
- **1 wants its own slot with design**: `2026-07-26-agora-fs-dir-list-per-call-alloc` — changes the
  allocation contract of an API `dir_walk`/`find_files`/`dir_list_full` all sit on.
- **2 residual**: 2026-07-12 DX multi-error (only the 25 inline `SYS_EXIT` errors remain; the recovery
  core shipped .62 and the EOF-cascade half shipped .78 — **the doc's own status text is stale**),
  2026-07-14 release-gate `vr01_`-glob coverage gap.

## What is uncommitted right now

The v6.4.80 fix + this doc pass are staged in the working tree, **not committed** (the user handles
all git). Roughly: `src/frontend/parse_expr.cyr` (the 16-site fix),
`tests/tcyr/const_chained_multiply_fold.tcyr` (8 → 33 assertions), `CHANGELOG.md`,
`docs/doc-health.md` (refreshed to .79), `CLAUDE.md` (ach added to 3 host lists; reserved-keyword
rule widened from 3 names to the 67-name class), this file, and
`docs/development/issues/archived/2026-07-26-cfo-rewind-pexpr-tier-negative-intermediate.md`.

**`version-bump.sh 6.4.80` has NOT been run yet** — check `VERSION` before assuming.

### Doc edits the audit identified but this pass did NOT make

Deliberately left for the closeout, because several need judgment rather than a find-and-replace:
- **roadmap.md's "Shipped so far" list stops at .72** — seven releases missing, plus stale trailing
  stamps (cycc 1,103,512 B / check.sh 147 / ~620 ms).
- **Stackless coroutines is contradicted in 3+ places.** `roadmap-future.md:116` is authoritative
  (▲ PINNED v6.5.x); roadmap.md still lists it under "Potential backlog — unscheduled" and calls
  stiva a "would-be consumer", and state.md's own *Next up* row still says "FUTURE ARC … no consumer"
  while its *In-flight* row says PINNED. Fix them to match roadmap-future.md.
- **roadmap.md's v6.5.x slot table omits the pub/private opener** that four other docs name — a
  reader working from that table alone would open v6.5.0 on the IR substrate.
- **Open-issue count says 9 in state.md / roadmap.md / cycle-discipline.md**; live is 11.
- **Heap regions disagree three ways**: `sh tests/heapmap.sh` reports **94**, doc-health + ADR-003 +
  vidya `core.cyml` say 100, vidya `ecosystem.cyml` says "135 entries / 56 live". Do NOT blind-edit —
  the 100 → 94 drop is exactly the six bands v6.4.75 freed, so this belongs to the closeout **heap-map
  audit** (CLAUDE.md item 4) where the number gets re-derived, not patched.
- **CLAUDE.md:164 says the last security audit was "v5.0.1"** — actually
  `docs/audit/2026-06-10-deep-dive-review.md` at cycc **6.1.31**. Three minors since; a re-scan is
  legitimately due at the 6.5.0 closeout.
- **vidya**: zero references to .73→.79 anywhere; `field_notes/compiler/gotchas.cyml` stops at
  v6.4.52 (27 releases with no gotcha). ⚠ **The v6.4.72 vidya sweep is sitting UNCOMMITTED in
  `~/Repos/vidya`'s working tree** — commit it before editing, or a `git checkout` there destroys it.
- **Cleanup sweep candidates** (gitignored, so invisible to `git status`): two 8.4 MB `qemu_*.core`
  dumps and an empty `_vr01_mdir/` in the repo root.

### One process fix worth more than any of the above

v6.4.77 found this same doc-rot class in `ecosystem.md`, fixed it, and added a checklist item with a
copy-pasteable verification loop — and the sankoch row **went stale again two releases later at .79**.
A checklist entry is not a gate. Either wire the check into the step that causes the drift, or add a
`check.sh` gate diffing state.md/roadmap.md stamps against `VERSION` + `build/cycc` size. The repo
already has `_doc_size_currency_gate`, so the shape is proven.

## Traps that cost real time in .73–.79 — do not rediscover these

These are the ones that would have been lost with the memory directory.

**Bootstrap / seed**
- **cybs cannot lex `>>>`.** A `>>>` in `src/` self-hosts and fixpoints fine on `build/cycc`, then
  `seed-derive-cycc.sh` fails at step 3 with a bare `syntax error`. cybs knows only `>` / `>=` / `>>`.
  Spell arithmetic shifts without the operator (see `_CF_ASR` in `parse_decl.cyr`). This is the
  cleanest demonstration of why the cycc fixpoint does **not** substitute for the seed gate.
- cybs also mis-compiles fns with too many global/call references — the reason `_var_grow` is a
  `_grow_g1..g7` tail-call chain. When adding a big table of string literals, split it into its own
  fn (see `TOKNAME_BUILTIN`).

**Language semantics**
- **Cyrius precedence is NOT C's.** `&`, `|`, `^` share the `+`/`-` tier, left-associative:
  `1 | 2 + 1` == **4** (`(1|2)+1`), `5 & 3 + 1` == **2**. `>>` is LOGICAL, `>>>` is ARITHMETIC —
  the reverse of JS/Java. Verify by running the compiler, never from docs.
- String-literal→`Str` auto-coercion fires **only** for a param annotated `: Str`. An untyped param
  receives a bare literal as a raw cstr pointer, and any consumer doing `str_len` reads
  `load64(ptr+8)` as garbage → silent empty/0, never an error. This shipped in `lib/fs.cyr` for ~a
  year across 11 fns.

**Compiler internals**
- Lexer token numbers **79** (`object` / `f64_sqrt`) and **111** (`stack` / `callptr`) are
  **double-assigned**; the grammar disambiguates by position. Diagnostics must name both.
- There are **two** keyword-lexing paths (`LEXKW_EXT` which `return`s a token, and the inline
  `ADDTOK` chain), and names >8 chars use a u64 compare **plus per-byte `load8` tails** — so a regex
  sweep over 8-byte literals under-counts. A first pass finds 51 reserved tokens; the real answer is
  **67**. Verify by compiling `var <name> = 1;` for each candidate.
- Any fn-indexed side table must handle `fi` up to **32768** (`_fnt_grow`'s ceiling). The v6.2.0
  migration left six at fixed 8192-slot bands and index 8192 aliased index 0 of the neighbour — a P0
  fixed at .75 via lazy-alloc-at-max-cap (the `_fnt_tparams` / `_vsgn_base` precedent: no fork edit,
  no grow-chain change).

**Tooling / release**
- **`cyrius lib sync` is refused in this repo** (since .77) — it would copy the snapshot over `./lib`
  and silently revert every fold. To refresh a folded dep: `cp <upstream>/dist/<name>.cyr lib/<name>.cyr`.
- **`cyrius distlib` regenerates only the main bundle.** Run `cyrius distlib <profile>` for each
  declared `[lib.<name>]`, and grep each bundle for the **fix symbol** — a version bump can ship
  without the fix.
- Re-vendoring a fold: **drift-check first** (`diff <(git -C ../<dep> show <oldtag>:dist/<dep>.cyr)
  lib/<dep>.cyr`) — byte-identical means the overwrite discards nothing. Then refresh the install
  snapshot immediately (`~/.cyrius/lib/` and `~/.cyrius/versions/<v>/lib/`) or `cyrius deps` can copy
  a stale snapshot back over your edit.
- **Fix the SOURCE repo, not the fold.** A patch applied only to `lib/<dep>.cyr` evaporates at the
  next re-vendor. Patch upstream, cut a real release there (VERSION + CHANGELOG + **all** dist
  profiles + suite), then fold.

**Verification habits that caught real bugs**
- For any change that only *moves storage*, prove it with a **251/251 byte-identical differential**
  over `tests/tcyr/` (`sha256` of `cat f | cycc`, old vs new). That is the proof a relocation is
  codegen-neutral.
- Gates must be **mutation-proven**. Several gates in this repo passed vacuously for months —
  including one that was green *because of* the bug it guarded (`platform_efi.cyr`'s kmode marker,
  fixed .74). If you add a gate, break the fix and confirm it goes red.
- A differential against a **missing** baseline binary reports "everything differs". `ls` the
  baseline first.
- `tests/dx_multi_error.sh` hardcodes `CC="$ROOT/build/cycc"` — a `CC=... sh script` override is
  ignored; swap `build/cycc` itself to mutation-test it.
- Before paying for a hot-path guard, check whether an **existing** guard already gates the only
  regime where the new check matters. That is why the `PEEKT` EOF clamp cost −0.07 % instead of
  taxing every parse step.

## Process notes worth carrying

- The user handles **all** git operations — never commit, push, or tag. Never use `gh`; use `curl`
  against the GitHub API.
- Version bumps only when a release ships; a failed/in-flight release is re-cut at the **same**
  version. The agent runs `version-bump.sh` at slot close; the user pushes and tags.
- `release-gate.sh` must be GREEN before every `.NN` tag. `--quick` (steps 1–3) is for local
  iteration and is explicitly **not** release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** — fixed `/tmp` paths clobber under concurrency.
- A consumer filing enumerates what it *hit*, not the class. Check the whole class before shipping
  (.77 was 67 tokens against 3 filed; .78's `lchown` filing names one wrapper against a missing
  family of four).
