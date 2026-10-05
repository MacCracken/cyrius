# Cyrius Development Roadmap — v6.6.x (active minor)

**Scope** — the **current active minor only** (v6.6.x). This is the slot-pinning working
artifact: the 6.6.13 repair release, the tooling proposals that round out the minor, and the
unscheduled 6.x backlog. Whole-cycle framing, the v6.7.x language arc and v6.8.x/v6.9.x RISC-V live in
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

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: the v6.7.x language arc
  (real traits, the missing common features, and the language list this minor used to carry),
  v6.8.x/v6.9.x RISC-V rv64, cycle budgeting, and the shape of what follows v6.x.
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

**Current head: v6.6.16** (2026-10-04) — cycc **1,492,144 B** (`.text` **1,315,016**) ·
seed-derive **GREEN** · cross-OS **GREEN** on ecb/ach/cass/pi · self_compile **876 ms** ·
**439** `.tcyr` (**173** in `crossos/`) · **105** `lib/*.cyr` · **326** shell gates under
`tests/gates/<bucket>/` · **2 open issues** (the hisab filings, 6.6.16) · **6 open proposals**.

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

**v6.6.7–v6.6.12 were the repair batch** (2026-09-27 → 2026-09-30, CLOSED): the 30 issues filed after
6.6.6, split by the user across three releases, then each release's own review finds, which the user
placed into 6.6.10–6.6.12 — and 6.6.12 also took the backlog's repair items and every sibling follow-up.
It spent **CVE-46 … CVE-58** (the next free id is 74) and shipped each release together with the sibling
patch releases it needed. Per-release detail is in the CHANGELOG; the process rules it settled are in
*Standing notes* below.

**Re-planned 2026-10-01 (user).** 6.6.13 is a repair release — the three silent memory-corruption finds
that led the backlog, and the open issues (I1–I11). After it the minor finishes on **tooling** (the proposals).
The language list that was Phase 3 moved to **v6.7.x**, which RISC-V vacates for v6.8.x/v6.9.x. See
*The shape of v6.6.x*.

---

## The shape of v6.6.x

| Phase | Slots | What goes here |
|---|---|---|
| **1 — Repair window** | `.2` – `.6` | ✅ **CLOSED at 6.6.6.** |
| **1b — the repair batch** | `.7` – `.12` | ✅ **CLOSED at 6.6.12** (summary in *Where we are*). |
| **1c — memory + reported-issue repair** | `.13` | ✅ **SHIPPED 2026-10-02** (tag `6.6.13`): the three silent memory-corruption finds, the open issues I1–I11, and the ganita / bayan / sigil folds. See *6.6.13* below. |
| **1d — the TLS follow-ups** | `.14` | ✅ **SHIPPED 2026-10-02** (tag `6.6.14`): every remaining noted TLS issue and the sigil 3.13.7 fold. See *6.6.14* below. |
| **2 — the 6.6.x tail** | `.15` – `.19` | The release sequence ACCEPTED 2026-10-02 (see *The 6.6.x tail*): `.15` curves + the compiler leaks, `.16` repair, `.17` manifest, `.18` distlib + poison, `.19` embed + macOS threads. |
| **3 — closeout** | `.20` | The full closeout pass, like every minor (user, 2026-10-02: done before any v6.7.x work). Then **v6.7.0**. |
| ~~**Committed ergonomics**~~ | — | **Moved to v6.7.x** with P3 `const fn` (user, 2026-10-01) — see [roadmap_6.md](roadmap_6.md). |

---

## The 6.6.x tail — release sequence (ACCEPTED by the user 2026-10-02)

**Question (user, 2026-10-02):** which proposals can be accomplished, how to coordinate the remaining
6.6.x items, and whether to do the proposals before v6.7.x or after. **Answer, accepted:** the tooling
proposals come BEFORE v6.7.x (except P3 `const fn` and P5's execution half, which belong to the
language arc); the DCE compaction arc moves AFTER v6.7.x, before the RISC-V minors (still 6.x). The
proposals and the language arc share no dependency — the only coupling is P1 into v6.7.x (C2's
bounds-checked mode wants a `[build]` key, so P1's precedence order should exist first) — and sibling
regeneration waves cost less run one after the other than overlapping. Evidence: eight premise-checked
reviews and a synthesis, archived at
[`archive/2026-10-02-6.6.x-tail-sequencing-memo.md`](archive/2026-10-02-6.6.x-tail-sequencing-memo.md).

| Release | Contents |
|---|---|
| **6.6.15** | sigil **3.13.8** fold (constant-time P-256 / P-384 ECDH; ECDSA signing made constant-time — **CVE-68**); TLS ECDHE on P-256 / P-384 everywhere (1.2 client, 1.3 client with HelloRetryRequest, native server group negotiation, ephemeral-key zeroing); the `secret var` epilogue leak (**CVE-69**); B0a string interning (a NUL-bearing literal aliased another literal, silently). See *6.6.15* below. |
| **6.6.16** repair | **Compiler:** the silent miscompiles — module-scope `var T: i64[3] = {…}` stores bytes, pointer-mode struct `q = a` / `G = a` / `a = q`, overload dispatch on a `Str` global, `g<i32>(..)?` (139) and `var v = g<i32>(..)` dropping the payload, a nested fn (SIGILL → a named error), a kmode global initialiser naming an enum; the named >8 B struct argument becomes a COPY (decided, *Open questions* 4); one shared type-name resolver (sizeof for u*/f*/bool; annotations stop prefix-matching); the `#deprecated` gaps; the cycc include fallback honouring `CYRIUS_HOME`. **Net / TLS / security:** plain-socket SIGPIPE (`sock_send*`, http, ws — CVE-66's class, a CVE), `cyrius deps` tag-field traversal (CVE-62's class), the Ed25519 `sig_len == 64` check (its ServerKeyExchange curve-binding half shipped in 6.6.15), CA EKU, Windows accept inheriting `FIONBIO`, `fd_wait_ready`'s error mask, libssl session cache (`SSL_CTX_ctrl`) and the failed-`*_complete` sticky error, Windows `THREADS_CONCURRENT=1`, the agnos `setsockopt` stub. **Plus:** cwd-independent gates, the guide's `fn use()` example, the `element_typed_array` sentinel, the PE size gate's private wine prefix, the sit-fsck lookup, the stale premises in P2/P3/C1 and the syscall-families entry; the two hisab issues (a closure's `: stack` return booked against the enclosing fn; a top-level `fncallN` on a capturing closure SIGSEGVs). **Promoted 2026-10-04 (user)** from the planning premise checks: a local `var p: *i8` / `*i16` / `*i32` stored as a 1/2/4-byte scalar (the pointer truncated — silent memory corruption), and the libssl-only `tls.cyr` verbs (session callbacks, `max_early_data`, `get` / `set_session`, the early-data verbs) writing into a NATIVE ctx once libssl is loaded in-process. |
| **6.6.17** manifest | **P1** (the single manifest reader + `--print-config`; `[build] test` WIRED after measuring the repos with named deps; `defines` / `strict` wired; a `dce` key; `features` dropped, `target` held; profiles → backlog); **P5-A** (text corpus + per-entry view; P5 stays OPEN for its execution half); DRY the pass-1 top-level scanners across the 7 forks; LSP read sized by fstat; `lib sync --full` re-locking; `_toml_key_at`'s hyphen boundary. |
| **6.6.18** distlib + poison | **P4** option 2 (the compile-verify fixpoint is the authority; one sibling regeneration wave); **P6** widened (`poison_allocator()`, leading redzone, live-block sweep, settable fill byte, `alloc()` / arena redzones; guard pages → backlog); the log / ws / ws_server fold bundles; the ESYSXLAT compile-time fold (~593 KB of `cycc-native-aarch64`); DCE's honest "compaction declined: <why>" note; the missing `sxtw`. |
| **6.6.19** | **P2** `[embed]` (generated in cbt before `#@srcline` — never an in-band marker that reads files, the CVE-45 class; `[lib.PROFILE]` scoping; the interning perf fix B0b); x86-macOS real threads + `async_await_readable_ms` on macOS / agnos / Windows (*Open questions* 3). The release to trim if 6.7.0 should come sooner. |
| **6.6.20** closeout | The full closeout pass (CLAUDE.md § Closeout, [cycle-discipline.md](cycle-discipline.md)): the release gate, heap / dead-code / refactor / code-review / cleanup passes, a security re-scan, the downstream check, vidya (`types.cyml` still stamps 6.6.1), the backlog re-triage, `verify-store`. |
| **6.7.0** | The language arc ([roadmap_6.md](roadmap_6.md)): traits first, with the ADR and the one reserved-word survey at the open; P3 `const fn` after `const` and the if-expression; P5's execution half designed with C2. |
| **after v6.7.x, before RISC-V** | The DCE compaction arc (aarch64 first, then PE / Mach-O — see its section), `lib/net.cyr` §4 per-arch socket peers, the remaining syscall families, AF_UNIX (default yes). |

Defaults taken with the plan (the memo's): P4 option 2 (reverses the v6.5.10 "union" stance); P6 widened to
`alloc()` redzones; `output` stays a default and `init --bin` writes `build/{PROJ}`; DCE stays opt-in (so the
`dce` key earns its place); shabdakosh's phf is its own generator, no `#phf` builtin. Sibling follow-ups
once these tag: rekha drops its prelude and CI pin (after P4) and adopts the poison pack (after P6); kriya's and
puka's `--poison` runs check something real (after P6); agnosai, agnostic, rekha and sankoch retire their embed
generators (after P2); sankoch retires its interning proof (after B0a, in 6.6.15).

---

## 6.6.15 — curves and the compiler's secret leaks (MERGED 2026-10-03: release gate GREEN, awaiting the tag)

**User, 2026-10-02:** the sigil work marked for after 6.6.14, then (scope answers the same day) the
`secret var` epilogue fix, B0a, and TLS 1.3 / native-server P-256 with ephemeral-key zeroing.
- **sigil 3.13.8** (tag `bbaecc4`) + **3.13.9** (tag `7d7a880`, folded): constant-time P-256 / P-384 ECDH
  (`ecdh_p256_*` / `ecdh_p384_*`, SP 800-56A peer-key validation); ECDSA signing moved onto a
  constant-time EC engine — every field operation on the secret-nonce path branched on secret data since
  3.5.9 (a Welch t-test: |t| 6.34 before, 0.69 after) — **CVE-68**; the pin moves 6.6.9 → 6.6.14 (CVE-51
  broke its Intel-Mac timing tests), the trust helpers fail closed on Windows instead of probing plantable rooted
  paths (**CVE-73**), per-run temp names.
- **cyrius:** the TLS 1.2 client's ECDHE on P-256 / P-384 (the 6.6.14 supported_groups trade-off and the
  "no shared cipher" against ECDSA servers both gone); the TLS 1.3 client lists P-256 / P-384 and handles
  HelloRetryRequest; the native server negotiates the group (1.2 by supported_groups, 1.3 by key_share or
  an HRR); every ephemeral private key and shared secret is zeroed (**CVE-70**), and an all-zero x25519 secret is
  refused (**CVE-71**). The `secret var` epilogue leak —
  the defer walker saved the return registers to dead stack after the wipe and never cleared them; in sigil
  3.13.7 that left the ECDSA nonce k behind (**CVE-69**). B0a — string interning aliased a NUL-bearing
  literal onto another literal's storage (`"a\0a"` after `"a"` read `'z'`), silently. A `defer` / `secret var` in
  a `#naked` fn is refused (it never ran — **CVE-72**). Detail: CHANGELOG [6.6.15].

---

## 6.6.13 — memory fixes + reported-issue repair (SHIPPED 2026-10-02, tag `6.6.13`)

All fourteen items landed over six lanes and are merged on `main`. **Detail is in CHANGELOG [6.6.13]; the
eleven issue files are archived.**
- Memory: M1 narrow-global init width, M2 arrays sized by element, M3 closure-captured struct copies, I9
  natural global alignment.
- Issues: I1 (CVE-59), I2 (with CVE-60), I3, I4, I5, I6, I7 (CVE-63), I8 (CVE-61), I10 (with CVE-62),
  I11.
- Folds: sigil 3.13.6, ganita 1.2.11, bayan 1.5.10, and **bayan 1.5.11** (cut for this release; tagged
  first).

Defaults taken without asking (each recorded in the CHANGELOG):
- two `src` lanes, only one committing `build/cycc`;
- I9 aligns every global naturally, rather than padding only after typed arrays;
- I3 dropped the libssl off-main guard (backlog (i));
- I8 makes no Windows transport switch (backlog (j));
- `TLS_ERR_TIMEOUT` is -22, so the released `TLS_ERR_RECORD_OVERFLOW` keeps -20.

The in-passing finds of the premise check and the lanes' reviews are in *Potential backlog* below.

---

## 6.6.14 — the TLS follow-ups (SHIPPED 2026-10-02, tag `6.6.14`)

Every remaining noted TLS issue (user, 2026-10-02) over five lanes, plus the sigil 3.13.7 fold. **Detail is in
CHANGELOG [6.6.14].**
- **CVE-64** native mTLS authenticated nobody (1.2 server, 1.3 chain, `tls_set_verify`); **CVE-65** Windows'
  plantable trust store (now the CurrentUser ROOT store); **CVE-66** SIGPIPE on a reset peer, both backends;
  **CVE-67** the `*.com` wildcard.
- Native TLS over Winsock with a real deadline; libssl fails closed off the main thread, errors stick; the
  credential loaders; no IP-literal SNI; the port-race gates; sigil 3.13.7's lenient trust-bundle decode.
- CI at the first push caught three test defects (an inherited SIGPIPE ignore; two-write peer races), fixed
  before the tag. Filed in their repos (user): the agnos #48 write deadline, kavach's `basic` seccomp vs `sendto`.

---

## Open arc — DCE cannot compact on PE, x86 Mach-O or aarch64 (the rip-relative repair)

> **Re-placed 2026-10-02 (user accepted the tail plan): AFTER v6.7.x, before the RISC-V minors — still 6.x.**
> The PE / x86 Mach-O half has no consumer today (the 18 repos that use DCE build aarch64); aarch64 needs its
> own repair model, which rv64 will reuse, and it is cheaper after the ESYSXLAT fold (6.6.18). Every target is
> correct today (the unsupported ones only skip the shrink); 6.6.18 ships the honest "compaction declined:
> <why>" note. Order: aarch64 first, then PE / Mach-O.

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

**Re-placed 2026-10-01**: 6.6.10–6.6.12 did not take it. It stays in v6.6.x and runs in the tail beside the
tooling proposals (Phase 2). It is backend work, not language work, so it did not move to v6.7.x.

---

## Phase 2 — the tooling round-out (after 6.6.14, to the minor's close)

**Set 2026-10-01 (user): v6.6.x finishes on tooling. Placed 2026-10-02 (accepted):** P1 + P5-A → 6.6.17,
P4 + P6 → 6.6.18, P2 → 6.6.19, P3 and P5's execution half → v6.7.x — see *The 6.6.x tail*. Each proposal
below carries its placement; the detail of each premise check is in the archived memo.

### P1 — `cyrius.cyml` as the build tool's actual configuration
[`proposals/2026-09-04-build-tool-manifest-integration.md`](proposals/2026-09-04-build-tool-manifest-integration.md)

**Placed: 6.6.17** (2026-10-02). Still needed: only the v6.5.49 path fallback shipped — `[build] test` and `defines` are inert (41 manifests and two sibling CIs rely on `test`; kashi's 393 assertions have never run in CI), `[build]` past 32,767 B is invisible, `--print-config` does not exist. Build the single reader and its precedence (argument > environment > manifest > default) first: P2, P4 and P5 add manifest keys. Keys by measured demand: add `dce`, wire `defines` / `strict`, wire `test` after measuring the repos with named deps, drop `features`, hold `target`; named profiles → backlog.

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

**Placed: 6.6.19** (2026-10-02). Still needed (the section is silently ignored; 4 repos run python generators; nobody is blocked). It does NOT want `const fn`: bytes in, cbt writes escaped literals (a 1.9 MB blob already round-trips on all five targets). Generate in cbt before `#@srcline` — never a compiler-side marker that reads files (the CVE-45 class); `[lib.PROFILE]` scoping (rekha and sankoch are libraries); the interning perf fix B0b. Its "zero newlines" constraint is obsolete since `#@srcline` (v6.5.24).

Ergonomics, not capability — the generated-`.cyr` idiom already works and is fleet-wide, and
agnosai ships its own generator, so nothing is blocked. **Its prerequisite has cleared**:
`2026-06-25-source-level-version-constant` shipped at v6.5.21, and `PP_EMIT_PKGVER`
(`src/frontend/lex_pp.cyr`) is the template for a `#@embed` arm.

### ~~P3 — Compile-time evaluation (`const fn`)~~ → moved to v6.7.x (2026-10-01)
[`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)

It is language, not tooling, so it moved with the rest of the language list. Its spec — the rung
chosen 2026-07-07 and its corrected base (the parse-time folder `_CF_TRY`, not the x86-ELF
peephole that runs only under opt-in `CYRIUS_IR=3`) — is now [roadmap_6.md](roadmap_6.md)
§ v6.7.x, item C1. *(Corrected 2026-10-04, 6.6.16: this stub used to point at "the
`ir_const_fold` ordering constraint", a base roadmap_6.md had already retracted on 2026-10-02.)*

### P4 — test-only stdlib leaves, instead of hiding them from the umbrella scan
[`proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md`](proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md)

**Placed: 6.6.18** (2026-10-02), **option 2**: the compile-verify fixpoint is the only authority (simulated on 7 producers × 4 targets, 0 undefined). Fleet-wide: 73 of 76 published sidecars name an unused `assert`, 53 of 53 an unused `bench` (+35 % consumer binary). Drop the `dev-stdlib` key and `[lib] umbrella` shapes. Reverses the v6.5.10 "union" stance.

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

**Placed: A (text corpus + per-entry view) 6.6.17; B (execution) v6.7.x with C2** (2026-10-02) — it shares C2's insertion point and build-flag plumbing. P5 stays OPEN after A: archiving it then would narrow the filing silently. rekha, sadish, dhancha, setu and mishran all read 0 % today.

Filed 2026-09-20 by **rekha 0.4.12** (25 self-checking `programs/*_test.cyr`, ~13,000 lines of assertions,
coverage reported as ~0 %). ⚠ **Its prerequisite ships first**: 6.6.8 bite 9 fixes how coverage COUNTS
(substring and comment matches, a denominator that drops public fns), and extending the corpus before that
would widen a number that is already wrong. The open scope question — a text-reference corpus versus
execution/branch coverage — is the proposal's, and gets asked when this slot opens. Size: M on top of 6.6.8.

### P6 — `cyrius fuzz --poison` through a custom allocator seam
[`proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md`](proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md)

**Placed: 6.6.18** (2026-10-02), widened: `alloc()` is never poisoned and 60 of 95 fuzzing repos get nothing. Pack S1–S6 + `poison_allocator()`: a leading redzone, a live-block sweep, a settable fill byte with an A/B run, `alloc()` / arena redzones (`lib/alloc.cyr` is compiler source — full gate). Drop the manifest / interposition shape; guard pages → backlog.

Filed 2026-09-20 by **rekha 0.4.12**, which parses untrusted font bytes through sadish's `sd_alloc` seam and
hand-built a 2,100-line substitute because `--poison` only redzones the freelist. The overlapping piece —
freelist poison comments that no longer describe the code, and a `--poison … ACTIVE` message that claims
coverage it does not have — ships in 6.6.7 bite 8. The design fork (a redzone/fill seam versus guard-page
faulting) is the proposal's. Size: M.

---

## ~~Phase 3 — the committed ergonomics list~~ → v6.7.x (moved 2026-10-01)

The user moved the language list out of this minor on 2026-10-01: `const fn`, the opt-in
bounds-checked mode and trait-bounded generics now open v6.7.x, together with a real-traits arc and the
missing common features. The spec lives in [roadmap_6.md](roadmap_6.md) § v6.7.x — one authority per
minor, so it is not repeated here. Of this list, item 1 (the value-form `Result` / `Option` / `Either`)
shipped at v6.6.0, and `defer` and per-block scoping had long since shipped when they were struck on
2026-07-29.

---

## Sibling follow-ups — open (each is that repo's next patch release)

Found at the 6.6.12 releases. A sibling's fix ships as that repo's own patch release, pinned to a released
cyrius; a folded stdlib is then re-vendored into `lib/` byte-identical from its tag.

**Recorded in each repo's own roadmap on 2026-10-02**: bayan, crab, sigil, mabda, sakshi, bote, aethersafha
and sankhya below, plus three 6.6.13 downstream notes — abaco (drop its TLS / tan workarounds), agnostic
(the aarch64 SIGBUS is fixed by I9; rebuild on 6.6.13) and mneme (`f64_parse` values may move ≤ 2 ulp).
kriya's was already there. Every repo that bumps to 6.6.13 must re-vendor `lib/math.cyr` in the same commit
(I5 reserves `f64_le` / `f64_ge` / `f64_trunc`); each note says so.

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
- kavach (a CONSUMER, not a stdlib — it gates nothing in cyrius; user, 2026-10-04): its `basic` seccomp
  profile allows `write` but not `sendto` (nor `poll` / `fcntl`), so a sandboxed native TLS writer on Linux is
  killed (SIGSYS) from 6.6.14 (CVE-66's `MSG_NOSIGNAL`), and from 6.6.16 a plain-socket writer too. Keeping
  its allowlist in step with the stdlib's syscalls is kavach's own patch release. Filed in kavach (user,
  2026-10-02): `kavach/docs/development/issues/2026-10-02-basic-seccomp-kills-native-tls-writes.md`.
- sankhya's README / CLAUDE.md name varna 2.1.0 / itihas 2.4.0 / avatara 2.9.0; its 3.0.2 lock pins
  2.4.1 / 2.5.0 / 2.14.8.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces.

> **Placed 2026-10-02 (the tail plan, accepted):** items named in *The 6.6.x tail* are scheduled there and
> stay listed below only until their release ships. **Removed 2026-10-02** with the evidence in the archived
> memo §3(d): the `ir_dce` / `CLASSIFY_CF` line (the wrappers were deleted at 6.5.50, `374f361d`; CLASSIFY_CF
> is wired through RA_SCAN_LOOPS), the bare `var a[N]` question (subscripting one is a hard error naming the
> typed spelling; overrun checks go to C2), the I7 / race-gate port flake (shipped in 6.6.14), the Rosetta
> timebase item (no Rosetta host — an unsupported configuration) and sakshi's qemu-static item (does not
> reproduce in CI). **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **Found by the 6.6.16 planning premise checks (2026-10-04; backlog — the user promoted only the `*iN`
  pointer truncation and the libssl-verbs-on-a-native-ctx corruption into 6.6.16).** Met in passing, not swept for.
  - ⚠ `cyrius deps` READ side: a `modules` entry with `../` or an absolute path, and a TRANSITIVE manifest's
    `path`, vendor any local file into the consumer's `lib/` (security-relevant; 6.6.16's CVE covers the `tag`
    field only). Confining a transitive `path` to its own manifest's tree is the design call (54 legitimate root
    `path = "../sibling"` uses).
  - ⚠ Silent wrong values: a top-level `var v = pair_fn(..)` keeps the tag and drops the payload (the v6.5.67
    single-bind refusal is gated on `GINFN == 1`); `var G: f32 = 1.5` (global or local) stores the f64 bit
    pattern with no warning; through a pointer-mode 8-byte struct, `o.m()` (self = `&o`) and `T_m(o)` read
    different values.
  - `asm { in al, dx; }` is refused because `in` is keyword 76, so the `ASM_IN` emitter arm is unreachable —
    a compiler bug (the guide documents the form, ~2049).
  - In an x86 `kernel;` build, float-literal global scalars (`var G: f64 = 1.5;`) are dead stores after the
    program (6.6.16's kmode warning names them); `src/common/util.cyr` ~1151 wrongly claims byte-array
    initialisers are immune.
  - cx: `lib/fnptr.cyr` has no `CYRIUS_TARGET_CX` arm, so an address-taken `&fncallN` returns 0 there.
  - `println(n)` on an `i64` local hands it to the cstring overload and exits 139 (the `_int` arm types only
    call arguments; `PARSE_FNCALL`'s header comment claims otherwise). Loud.
  - cycc's `_read_env` (`src/backend/common/env.cyr`) caps the environment at 8191 B and values at 255 B, so
    every `CYRIUS_*` knob is missed past 8 KB of environment (the class the CLI fixed at 6.6.11 J4).
  - Windows `sys_setsockopt` is a -38 stub although `net.cyr` reaches setsockopt through ws2_32 (0xF032), so
    yantra's `TCP_NODELAY` is never set on PE.
  - `lib/syscalls_macos.cyr` declares `SYS_ACCEPT4 = 288` and `sys_accept4` compiles for macOS, which has no
    accept4 (not run).
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
  - TLS — `_tn_verify_sig_scheme` (`lib/tls_native_hs13.cyr` ~533) calls `ed25519_verify` without checking
    `sig_len == 64` (placed: 6.6.16). (Its other half — binding the ECDSA curve to the scheme for the 1.2
    ServerKeyExchange — was fixed in 6.6.15 by `_tn_ecdsa_verify_12`.)
  - TLS — capability limits listed in CVE-64's *Not covered*: no RSA client certificates natively; the native
    client and the native server send their leaf only (no intermediates); an empty certificate_authorities;
    the 1.3 server reads each client message from one record (a client Certificate of at most 8 KiB).
  - TLS — the chain verifier checks only the LEAF's extendedKeyUsage, never a CA's own (Windows' chain engine
    and OpenSSL both check it).
  - TLS, Windows — the store: CurrentUser `ROOT` under the ProtectedRoots policy is unverified; the
    auto-updated disallowed CTL is not read; a root with a dated distrust is refused whole (SecureTrust's
    pre-2026-09-15 leaves fail here); roots Windows has not fetched yet are invisible (CVE-65's *Not covered*).
  - TLS, Windows — an accepted socket inherits a non-blocking listener's `FIONBIO`, so native TLS with no
    deadline on it fails `TLS_ERR_IO`.
  - TLS, libssl — `tls_ctx_set_session_cache_mode` is a silent no-op (OpenSSL 3 makes
    `SSL_CTX_set_session_cache_mode` a macro over `SSL_CTX_ctrl`; the dlsym finds nothing); a failed
    `tls_*_complete` records no sticky error, so a contract-violating `tls_read` after it re-drives the
    handshake.
  - TLS, agnos — a native write can overshoot the caller's deadline by one `sock_send#48` stall (~8 s):
    agnos's #48 hard-codes `TCP_PROGRESS_US`. It needs #48 to honour a time bound (`tcp_send_ex` already
    takes one) — an agnos ABI change, then the stdlib passes the time left (CVE-61's *Not covered*).
    **Filed in agnos** (user, 2026-10-02): `agnos/docs/development/issues/2026-10-02-sock-send-ignores-the-caller-deadline.md`.
  - `lib/net.cyr`'s plain writers (`sock_send`, `sock_send_all`, `lib/http.cyr`, `lib/ws.cyr`) are flagless
    `write`s on Linux and macOS: a reset peer still raises SIGPIPE there (CVE-66's class for plain sockets).
  - `lib/syscalls_windows.cyr` `fd_wait_ready` (~880, also ~949/955/965) returns `0 - WSAGetLastError`
    without the 32-bit mask `net.cyr` applies.
  - check.sh — `cli_pe_file_size_and_sibling_tools.sh` runs wine in the shared default prefix; with several
    check.sh runs at once its axis 1 hung to its 300 s timeout (a plausible mechanism: the gate supervisor
    reaping another run's wineserver). The `sit fsck` driver row always SKIPs in a worktree outside `~/Repos`.
  - `lib/thread_win.cyr:36` says `THREADS_CONCURRENT = 0` is a "serial fallback (bodies run inline)", while
    `thread_create` starts a real `CreateThread`.
  - `tls_native_set_client_cert` sizes its decode at `TLS_CA_MAX_ROOTS` (300) entries; sigil 3.13.7's
    `pem_count_cert_blocks` could size it exactly.
  - sigil (its repo) — the TPM helpers probe `/dev/tpmrm0` and spawn `/usr/bin/tpm2_*` by rooted path,
    drive-relative on Windows if reachable on PE (the CVE-65 class, an executable this time); its check.sh
    builds at predictable `/tmp/sigil_{t,b,f}_$$` paths. sandhi (its repo): `lib/sandhi.cyr` ~1589 still
    calls the tls ctx a 24-byte struct.
- **Found by the 6.6.13 lanes' reviews (2026-10-01; backlog, not placed — only the user promotes).** The TLS
  finds are 6.6.14's scope (*6.6.14* above).
  - `cyrius deps` joins the `tag` value into `<home>/deps/<name>/<tag>` unchecked: `tag = "../../../x"`
    exits 1 (git refuses the ref) but leaves an empty directory outside the dep cache — CVE-62's class on
    the tag field.
  - cycc's include fallback (`_init_cyrius_lib`, `src/frontend/lex.cyr`) reads
    `$HOME/.cyrius/versions/<VERSION>/lib` and ignores `CYRIUS_HOME`, although its comment says otherwise,
    so `cyrius distlib`'s verify can compile against a different stdlib than the one it attributes from
    (`distlib_sidecar_verified.sh` pins HOME to work around it).
  - Both annotation ladders PREFIX-match scalar type names: `var a: i8x` is silently `i8` (arrays and
    scalars; only vector names are matched whole, in the array path).
  - A nested `fn` inside a fn body compiles and SIGSEGVs at run time
    (`fn outer(): i64 { fn inner(): i64 { return 3; } return inner(); }` → rc 139).
  - `tests/tcyr/lang/element_typed_array.tcyr`'s sentinel sits BELOW the array, where an overrun cannot reach
    it (the new `crossos/typed_array_elem_size.tcyr` covers the shape).
- **Found by the 6.6.13 premise check (2026-10-01; backlog, not placed — only the user promotes).** Met in
  passing while planning M1–M3 and I1–I11, not swept for. ⚠ (a)–(c) are silent miscompiles. The TLS finds
  (d), (e), (f), (i), (j) are 6.6.14's scope (*6.6.14* above); the letters are kept for reference.
  - (a) A pointer-mode struct local assigned into an inline struct stores its address
    (`var a: Pt = alloc(16); var q: Pt; q = a;`): `_try_aggregate_copy_assign` (`parse.cyr` ~2457) gets 0
    from `_agc_operand` for a non-parameter pointer-mode local and falls to the 8-byte store.
  - (b) A callee writing to its by-value struct parameter mutates the caller's named-local argument
    (`bump(p)` twice gives 4 then 5): `_try_push_struct_addr_arg` pushes `&local` with no copy, while
    `_fla_push_arg` copies a field argument. The same decision as the 6.6.12 item below ("does the named
    form copy too?").
  - (c) The overload dispatcher compares a global's `GVTYPE` against the LOCAL encoding `0 - sid`
    (`parse_fn.cyr` ~2757), so a `: Str` global is never routed to its `_str` sibling: `println(gs)` prints
    the header's pointer bytes. I11 fixes the same sign in the diagnostic only (I11 is warning-only).
  - (g) `sizeof(f64)`, `sizeof(f32)`, `sizeof(u64)`, `sizeof(bool)`, `sizeof(ptr)` fail with
    `sizeof: unknown type` — loud, not silent.
  - (h) `EMACHO_PTHREAD_CREATE_ARM` takes `pthread_create`'s `int` result without sign-extending it
    (harmless: `thread_create` tests only `!= 0`).
- **`#deprecated` gaps (measured by bayan 1.5.10 on the 6.6.12 release, recorded in I11's issue as a
  *Related* separate defect; backlog, not placed).**
  - Silent: a call through `&f` (`fncall1(&old_f, 1)`), a method-dot call `o.m()` whose `T_m` is
    `#deprecated`, and a call parsed before the deprecated definition.
  - Mislocated on a tail call: PARSE_RETURN warns (`_DEPRECATED_WARN`, `parse_fn.cyr:790`) after the `)`
    and `;` are consumed, so `return old_f(x);` is reported at the NEXT token's line.
- **Found by the 6.6.12 premise check and lanes (2026-09-30; backlog, not placed — only the user promotes).**
  Met in passing, not swept for. Its three ⚠ silent-memory-corruption items were promoted to **6.6.13**
  (M1–M3) on 2026-10-01.
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
- **ESYSXLAT emits its whole translation chain INLINE at every aarch64 syscall site** — measured at the 6.6.8
  merge: `build/cycc-native-aarch64` `.text` 1,495,592 → 1,578,544 B (+82,952 over 605 `svc` sites, ~137 B
  per site) because 6.6.8 bite 3 added nine rows and every row is copied into every site. Every aarch64
  program pays it, and each new row makes it worse. A shared translation stub (one call per site) would
  cut it to a few bytes a site. Correct today; a size tax, so it is placed here rather than in a release.
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
   it: **731–734 ms · 1,247,608 B at 6.6.1**. A previously-floated candidate pair was *≤700 ms and
   ≤1.20 MB at minor close* — ⚠ **both halves are now exceeded**, so that pair is an input to
   re-decide, not a target that was missed. Review together with item 2.
2. **The self-compile growth-tax audit — ANSWERED (user, 2026-07-29): likely dropped, but
   re-review WITH item 1's performance track**, the two being the same subject. Explicitly *not*
   silently dropped — parked against that track's opening review, which decides whether it still
   earns a bite. Record the outcome here either way.
3. **macOS concurrency ordering — PLACED 6.6.19** (2026-10-02, with the tail plan): x86-macOS real
   threads and `async_await_readable_ms` on macOS / agnos / Windows. Real platform work with a
   genuinely broken verb on a gate host; no consumer waiting; it mirrors `thread_win`.
4. **A named struct argument over 8 bytes — DECIDED 2026-10-02 (user accepted): it is a COPY**,
   matching 6.6.12's field-argument copy and fixing a callee that mutates the caller's struct
   (`bump(p)` twice gave 4 then 5). Settled before v6.7.x's traits inherit the convention; lands in
   6.6.16. The blast radius is cyrius's own tests and the guide (which documents the alias today).

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
