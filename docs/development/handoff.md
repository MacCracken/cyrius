# Handoff — **v6.6.4 is tagged (`84130a7a`), gate-GREEN, store reconciled.** Nothing is mid-arc.

> **Written 2026-09-14, at the v6.6.4 bump.** Read this, then [`CLAUDE.md`](../../CLAUDE.md), then
> [`state.md`](state.md), then [`roadmap.md`](roadmap.md).
>
> ⚠ **Refresh or delete this file when the next release ships. A stale handoff is worse than
> none, and this file is the repeat offender**: it sat at 6.5.10 for ten releases, then 6.5.20
> for thirteen more, then 6.5.33, then 6.5.36 for thirty-eight releases — and then **6.6.1
> through 6.6.2, 6.6.3 and the whole of the 6.6.4 work** (the 6.6.3 "handoff" commit touched
> roadmap + state and not this file). Every time it was found by a human, never by a gate.
> **There is no gate for handoff staleness** — a standing, deliberate gap.
> **Treat every number below as a claim to re-derive.**

---

## Where things stand

| | |
|---|---|
| Version | **6.6.4** — committed and **tagged** (`84130a7a`, 2026-09-14); the post-tag `install.sh --refresh-only` has run and `verify-store.sh` reads `6.6.4 OK · stamp tag-commit`, 5 slots 0 BAD. |
| cycc x86_64 | **1,251,944 B** (`.text` 1,097,472) — +80 over 6.6.3. seed **29,024 B** → cybs → cycc byte-identical |
| Gates | `check.sh` **246 / 0** · **164** shell gate scripts (DERIVE: `find tests/gates -name '*.sh' \| wc -l`) · release-gate **GREEN** 2026-09-14 |
| Cross-OS | **ecb · ach · cass · pi** — all `SELFHOST_OK` + `crossos LIBTEST_OK` (74/74), REAL hardware. **The pi leg now builds and RUNS the CLI too.** |
| Corpus | **314** `.tcyr` (74 in `crossos/`) · **103** `lib/*.cyr` · **84** `programs/*.cyr` |
| Bench | `self_compile` **744 ms** (6.6.3: 743) · cycc +80 B — noise / growth tax, nothing to bisect |
| Queue | **2** open issues (both filed BY 6.6.4's bites) · **3** proposals |
| Mid-arc work | **None.** 6.6.4 is complete. |

---

## Do these, in this order

1. ~~Commit + tag cyrius 6.6.4~~ — done (`84130a7a`).
2. ~~Post-tag `sh scripts/install.sh --refresh-only` at the tagged commit~~ — done; store reconciled.
3. **patra 1.14.3** — committed AND tagged by the user, but its CI went red because the committed
   `cyrius.lock` had been generated against a STAGED pre-final 6.6.4 tree (five `lib/` leaves
   hashed a stdlib that never shipped; the bite-5 guard refused them). The lock is now re-locked
   against the installed 6.6.4 release (`cyrius deps --relock` → `--verify` 27/0; a clean
   worktree vendors, builds and tests green from it) — **one uncommitted file, `cyrius.lock`**.
   Commit it and re-point the `1.14.3` tag at that commit (`git tag -f 1.14.3 && git push -f
   origin 1.14.3`) — the user's call.
4. **sigil 3.12.18** — committed (`cdc90c2`), not yet tagged; same lock problem, same fix
   applied: `cyrius.lock` re-locked against the release (`--verify` 38/0, build + 65/65 tests).
   **One uncommitted file, `cyrius.lock`.** Commit, then tag.
5. **mirshi 1.11.2** — 4 files uncommitted in `~/Repos/mirshi`; pins 6.6.2, **independent**.
   `ao_to_o` now translates `AO_NOFOLLOW`/`AO_EXCL`.
6. **vidya** — 5 files uncommitted (`gotchas.cyml` +1 entry and the bite-4 retraction of the
   snapshot-refresh recipe; `methodology.cyml`, `semantics_runtime.cyml`, `features.cyml`,
   `tooling.cyml`). `bash scripts/validate-content.sh content` → 847/0.

## Start here next: slot `.3` (lands as 6.6.5) plus the two filed issues

[`roadmap.md`](roadmap.md) is the single authority. The repair window's labels have drifted
from the version numbers (6.6.3 = the sweep's repairs, 6.6.4 = the post-handoff filings); the
slots have NOT been re-numbered — that is the user's call.

- **`.3` — per-item `private` silently privatises the whole file.** `private fn h()` compiles
  with no diagnostic and flips the entire file including `main`. Default taken: make the
  per-item form a hard error pointing at the file-level declaration.
- **[`2026-09-13-private-impl-method-forward-call-fail-open.md`](issues/2026-09-13-private-impl-method-forward-call-fail-open.md)**
  — a private impl method is reachable by a FORWARD call because pass 1 brace-skips impl bodies
  in all seven forks, so the call registers `Type_method` with no fileid and `_vis_check` fails
  open. Closing it = registering mangled method names with fileid + flag in pass 1 (7 forks,
  PARSE_FN_DEF's name-pool mangling). Run seed-derive — a pass-1 change is the class the cycc
  fixpoint cannot see.
- **[`2026-09-13-fn-local-global-slots-shadow-other-files.md`](issues/2026-09-13-fn-local-global-slots-shadow-other-files.md)**
  — a fn-local struct literal / oversized array is a GLOBAL slot in the flat namespace and
  shadows other files' globals (was a silent miscompile; since bite ③'s stamps a misattributed
  diagnostic).
- **`.4`–`.5` — DCE cannot compact on PE or x86 Mach-O** (rip-relative repair + re-run
  `_pe_layout` after compaction — both, or the binary looks fine and faults later).
- ⛔ **`.6` stays unassigned.**

---

## What 6.6.4 did, one paragraph per bite (detail: `CHANGELOG.md [6.6.4]`)

**①** A string literal ≥ 64 KB read back from its SECOND byte (`(offset << 16) | len` in the
lexer — a 16-bit field silently too narrow since 2026-04) → widened to `<< 32` in the one producer
and four decoders; plus the same class in cx (every address emitter past 0xFFFF loaded a wrong
value), cx `x*2^k`, a cx crash-after-diagnostic, `#deprecated` on tail calls.
**②** `&_private_fn` from another file compiled and was callable — one of EIGHT resolution paths
`_vis_check` did not cover; plus generic-instance polarity, private arrays, method `self` on
inline stack structs (SIGSEGV).
**③** `public enum` re-exposed the NEXT declaration in a `private` file (the marker outlived its
item) — and so did struct/union/impl/`use`; plus an enum `#derive` inside a taken `#ifdef`
dropping the rest of the file.
**④** The install store was writable under a RELEASED name and stale in BOTH directions
("6.6.2"'s stdlib was 6.6.3's; "6.6.3"'s cross-compilers were the bump commit's). install.sh /
pulsar / lsp refuse; `check.sh` stages its own throwaway home; `SOURCE_COMMIT` stamps;
`scripts/verify-store.sh` (+ `--restore`); the live store restored. The old "snapshot refresh"
recipe was the corrupting writer — retracted from CLAUDE.md and vidya.
**⑤** `cyrius deps` silently re-locked a changed stdlib file under an unchanged pin; also bare
`deps --lock` dropped every commit pin, a CRLF lock turned the guard off, `--verify` read 64 KB.
Lock now carries a `cyrius\t<pin>` trailer; `deps --relock` is the explicit accept.
**⑥** Raw x86 syscall numbers in arch-neutral code ran as DIFFERENT syscalls on aarch64 — and
the worst instance was not in the filing: `cbt/build.cyr`'s raw 110 (`getppid` = aarch64
`timer_settime`) made every `cyrius run/test/tests/bench/fuzz` child exit 1 before `execve` on
native aarch64 for **59 releases**, while the compiler self-hosted on pi at every gate. ESYSXLAT
rows for fstat/lstat landed WITH fdlopen/dynlib declines; per-target `O_*`; the agnos
`AO_NOFOLLOW`/`AO_EXCL` bridge (owed since agnos 1.56.53 — found by the bite's review);
patra/sigil/mirshi at source; an emitter-DERIVED allowlist gate.

---

## Traps that cost time this session — do not re-learn them

- **qemu-user is not the hardware.** The filing said raw 158 (`arch_prctl` → aarch64 `getgroups`)
  "fails closed"; under qemu it EFAULTs, on pi it returns the group COUNT, and the `rc != 0`
  caller failed OPEN exactly on group-less processes. Run the probe on the host before writing a
  severity — and read what the caller does with the return value.
- **A compat row that turns fail-closed into fail-OPEN ships with its decline.** The fstat 5→80
  row alone would have let the x86-only ELF loader "work" on aarch64 bytes.
- **Premise-check the agnos peer against `~/Repos/agnos/kernel/core/syscall.cyr`.** `lib/io.cyr`
  said "agnos has no AO_NOFOLLOW / AO_EXCL bit" for three minors while the kernel had both.
- **Derive allowlists from the artefact, and bound the derivation.** The first cut decoded every
  `0xF1…` word in emit.cyr with Rn unchecked (ETESTAZ's `cmp x0,#0` was a "row"); the guard
  tracker accepted `#ifdef\tX`, which lex_pp treats as a COMMENT. Mirror the consumer exactly.
- **A sibling bump is done when its OWN CI checks agree** — patra's compares the README install
  snippet's `tag` to `VERSION`; I bumped one and not the other.
- ⛔ **Never generate a sibling's `cyrius.lock` against an UNRELEASED toolchain.** patra's and
  sigil's locks were re-locked from a staged copy of the mid-bite-6 tree; the review then changed
  five `lib/` files, so the committed locks hashed a stdlib that never shipped and the bite-5
  guard refused them in CI. The lock is produced only AFTER cyrius is tagged and the store slot
  reconciled (`install.sh --refresh-only` at the tag → `verify-store.sh` says `stamp tag-commit`),
  via `cyrius deps --relock` from the installed release. Both were re-locked that way on 2026-09-14.
- **`pkill -f '<script>'` matches the shell that runs it.** Launch long gates through a wrapper
  script under `setsid nohup … & disown` and poll the log for an end marker.
- **`version-bump.sh` rewrites the version token and NOTHING else** in roadmap/state — re-derive
  every number beside it (`.text` from `llvm-readelf -S build/cycc`, gates from `find`).

---

## Standing rules that bit hardest here

Full set in [`CLAUDE.md`](../../CLAUDE.md). The ones that mattered this session:

- ⛔ **A sibling repo pinned to an UNRELEASED cyrius is not releasable** — say so in the first
  line of any hand-back, not in a parenthetical.
- ⛔ **Never run `cyrius build <file>` inside this repo** — `cyrius.cyml` resolves output to
  `build/cycc`. Test compiler changes with `./build/cycc` directly (`cyrius build` re-execs the
  PINNED toolchain).
- **Release gate GREEN before every `.NN`** — self-host fixpoint · seed-derive · check.sh ·
  cross-OS on **real** ecb/ach/cass/pi · bench. A green CI checkmark is NOT the cross-OS leg —
  and a compiler that self-hosts on a host is not a CLI that runs there.
- **Seed-derive is mandatory for ANY `src/` change** — cybs fails SILENTLY on things cycc
  compiles fine.
- **Fix the SOURCE repo, not the vendored `lib/` fold**; never copy an edited `lib/*.cyr` into
  `~/.cyrius/versions/<v>/` (refused since 6.6.4; `check.sh` stages its own home).
- **The user handles all git operations.** Do not commit, push, or tag. **Never use `gh`** —
  `curl` to the GitHub API only.
