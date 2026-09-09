# Handoff — **v6.6.1 is cut, tagged and gate-GREEN.** Nothing is mid-arc.

> **Written 2026-09-08, at v6.6.1.** Read this, then [`CLAUDE.md`](../../CLAUDE.md), then
> [`state.md`](state.md), then [`roadmap.md`](roadmap.md).
>
> ⚠ **Refresh or delete this file when the next release ships. A stale handoff is worse than
> none, and this file is the repeat offender**: it sat at 6.5.10 for ten releases, then 6.5.20
> for thirteen more, then 6.5.33, then **6.5.36 from 2026-08-28 through the whole of v6.5.x
> AND v6.6.0 AND v6.6.1** — thirty-eight releases. Every time it was found by a human, never
> by a gate. **There is no gate for handoff staleness** — a standing, deliberate gap.
> **Treat every number below as a claim to re-derive.**

---

## Where things stand

| | |
|---|---|
| Version | **6.6.1** — committed and **tagged**. Gate GREEN on all 5 steps. |
| cycc x86_64 | **1,247,608 B** (`.text` 1,090,832) — unchanged from 6.6.0. seed **29,024 B** → cybs → cycc byte-identical |
| Gates | `check.sh` **240 / 0** · **144** shell gate scripts (DERIVE: `find tests/gates -name '*.sh' \| wc -l`) |
| Cross-OS | **ecb · ach · cass · pi** — all `SELFHOST_OK` + `crossos LIBTEST_OK`, REAL hardware |
| Corpus | **301** `.tcyr` (68 in `crossos/`) · **102** `lib/*.cyr` · **84** `programs/*.cyr` · api-surface **5,152** · heap **102** regions |
| Bench | `self_compile` **731–734 ms** across two runs · cycc size flat |
| Queue | **1** open issue · **3** proposals · **387** archived |
| Mid-arc work | **None.** 6.6.1 is complete. The next slot is `.2`, already specified. |

---

## Start here: slot `.2` is specified and waiting

[`roadmap.md`](roadmap.md) was rewritten for the v6.6.x arc and is the single authority.
Shape: **`.2`–`.6` are a reserved repair window**, then the proposal queue, then the
committed ergonomics list. Three occupants are pinned with acceptance criteria:

- **`.2` — `cyrius build <src>` can overwrite the running compiler, and did.** In this repo
  `cyrius.cyml` declares `output = build/cycc`, and the documented argument ladder says one
  positional arg means "that src + manifest output". So `cyrius build <a test file>` wrote an
  842 KB test binary over the compiler at the v6.6.0 cut. Fix is narrow: refuse when the
  resolved output is the compiler `cbt` is currently running, UNLESS the source is the
  manifest's declared `src`/`entry`. ⚠ The gate must not run against this repo's own
  `build/cycc`, or the gate becomes the destructive act.
- **`.3` — per-item `private` silently privatises the whole file.** `private fn h()` compiles
  with no diagnostic and flips the entire file including `main`. Twelve-plus releases live.
  Default taken: make the per-item form a hard error pointing at the file-level declaration.
- **`.4`–`.5` — DCE cannot compact on PE or x86 Mach-O.** 6.6.1 made both DECLINE compaction
  (they emitted binaries that faulted `0xC0000005` / SIGSEGV'd). Repairing it means fixing the
  rip-relative displacement shape AND re-running `_pe_layout` after compaction — both, or the
  binary looks fine and faults later.

⛔ **`.6` is deliberately unassigned.** Do not fill it with backlog items; if nothing claims
it, phase 2 starts early.

---

## What the last three sessions did, in one paragraph each

**v6.6.0** — flipped `Result` / `Option` / `Either` to the **value form**: a payload variant
returns `(tag, payload)` in a register pair, so construction allocates **zero bytes** (the
filed `100x sock_send` → 1600 B measurement now reads 0). It shipped WITH the ecosystem — 8
sibling stdlibs migrated at source, pin-bumped, released and re-folded. It re-aritied every
payload-taking helper and **deleted `payload()` and `tagged_new()`**. ⛔ **CORRECTED at v6.6.2:
`tagged_new()` is RESTORED** (`lib/boxed.cyr`) — the deletion rested on a survey of the 12
fold-table stdlibs written down as "nothing in the ecosystem", and agnostik calls it 19 times,
agnova 9. `tag()` was deleted instead: v6.6.0 had kept the NAME and redefined the body, so on a
box it silently returned the pointer. `payload()` stays deleted, deliberately. A P0 was found at the
cut: `X = Y;` between two struct-POINTER locals copied `STRUCTSZ/8` slots over neighbours,
silent since v6.5.57 — **seventeen releases** — and invisible to the fixpoint because cycc's
own source never uses the shape.

**v6.6.1** — closed the entire open issue queue (three filings) and folded five stdlibs
(patra 1.14.1, sakshi 2.5.1, sankoch 2.7.14, ganita 1.2.4, niyama 1.0.10). ⭐ **The DCE
filing said "PE / `--win` target only" and that was wrong** — `main_x86_macho.cyr` includes
the same `x86/fixup.cyr`, so Intel-Mac Mach-O was crashing on real hardware, unreported,
because the reporter does not build that platform. Found by running the repro on `ach` rather
than trusting the report's target matrix. **A filing's target list is a report about what the
reporter builds, not about the bug.**

**Docs + roadmap + vidya sweep (2026-09-08, no version bump)** — README had not been touched
in three weeks and contradicted itself (270 vs 260 `.tcyr`; 100 vs 99 stdlib modules, same
file); the installed-toolchain figure was wrong by **10×**; `size-comparisons.md` cited
**cycc 6.5.74**, a version that was never released. `roadmap.md` was 1,043 lines still titled
*v6.5.x* with ~480 of them a slot list reading ✅ SHIPPED throughout — rewritten to 380.
Vidya's gotchas file was audited **158 → 62 entries** (461 KB → 164 KB): **59 of the 158 were
instances of 14 recurring classes**, now merged with the recurrence QUANTIFIED, 51 archived
to `retros/resolved_traps.cyml`, and one live defect filed as the open issue below.

---

## The one open issue

[`2026-09-08-lexer-token-types-79-and-111-double-assigned.md`](issues/2026-09-08-lexer-token-types-79-and-111-double-assigned.md)
— token 79 is BOTH `object` and `f64_sqrt`; token 111 is BOTH `stack` and `callptr`, verified
live in `src/common/util.cyr:1421,1487`. No miscompile (the grammar disambiguates by
position), but the compiler knows which keyword you typed and discards it, then hands the
reader `object'/'f64_sqrt`. Renumbering was deferred with a legitimate reason: it touches
codegen across the **seven** `main_*.cyr` forks and the seed chain. ⚠ **Run seed-derive** —
a front-end token change is exactly the class the cycc fixpoint cannot see (the `>>>` case at
v6.4.74, where cybs could not lex the new spelling and only seed-derive noticed).

---

## Traps that cost time this session — do not re-learn them

- **`version-bump.sh` rewrites the version token and NOTHING else.** Both `roadmap.md`'s and
  `state.md`'s head lines were stamped `v6.6.1` while every metric beside them was pre-6.6.1.
  Re-derive the numbers; the stamp is not evidence.
- **Derive counts THE WAY THE GATE DOES.** I put **145** heap regions into two docs from
  `grep -cE '^#   0x' src/main.cyr`; the real number is **102** — that regex also matches 18
  `FREED` markers and multi-scalar band lines. Run `sh tests/gates/memory/heapmap.sh`.
- **A number with a stated reason is not more trustworthy than a bare one.** README claimed a
  35 MB installed tree "because the two `cyrsign*` helpers are ~14 MB each". They are ~1.4 MB
  each and the tree is 10.2 MB. The reason was wrong too.
- **A rejected tool call may have already partially executed.** A `sed -i` earlier in a
  compound command had run before the rejection landed. Verify with `git diff`, then revert.
- **pgrep-based waiters self-match** — `until ! pgrep -f "release-gate.sh"` never terminates,
  because the waiting shell's own command line contains the pattern.

---

## Standing rules that bit hardest here

Full set in [`CLAUDE.md`](../../CLAUDE.md). The ones that mattered this session:

- ⛔ **Never run `cyrius build <file>` inside this repo** — `cyrius.cyml` resolves output to
  `build/cycc` and it WILL overwrite the compiler. (This is slot `.2`.)
- ⛔ **Never pass `$HOME/.cyrius` as a staging target to `funcgate-stage.sh`** — it rewrites
  that tree.
- **Release gate GREEN before every `.NN`** — self-host fixpoint · seed-derive · check.sh ·
  cross-OS on **real** ecb/ach/cass/pi · bench. A green CI checkmark is NOT the cross-OS leg.
- **Seed-derive is mandatory for ANY `src/` change**, including comment-only ones — cybs is
  far more limited than `build/cycc` and fails SILENTLY on things cycc compiles fine.
- **Fix the SOURCE repo, not the vendored `lib/` fold**, and refresh the `~/.cyrius` install
  snapshot immediately after editing any `lib/*.cyr` (snapshot ping-pong).
- **The user handles all git operations.** Do not commit, push, or tag. **Never use `gh`** —
  `curl` to the GitHub API only.
