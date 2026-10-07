# Cyrius Development Roadmap — v6.6.x (active minor)

**Scope** — the **current active minor only** (v6.6.x). This is the slot-pinning working
artifact: the rest of the 6.6.x tail (the tooling proposals that round out the minor, then the
closeout), and the unscheduled 6.x backlog. Whole-cycle framing, the v6.7.x language arc and v6.8.x/v6.9.x RISC-V live in
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

**Current head: v6.6.20** (2026-10-06) — **the v6.6.x closeout, in progress** (6.6.19 shipped: tag `6.6.19` @ `f5a5175a`)
· cycc **1,586,184 B** (`.text` **1,405,464**) at the slot open, unchanged from 6.6.19 · `cycc-native-aarch64` **1,323,400 B** ·
seed-derive **GREEN** (6.6.19 gate) · cross-OS **GREEN** on ecb/ach/cass/pi (6.6.19 gate) · self_compile **923 ms** (6.6.19
gate) · **482** `.tcyr` (**197** in `crossos/`) · **106** `lib/*.cyr` · **372** shell gates under `tests/gates/<bucket>/` ·
api-surface **5,827** · **0 open issues** · **2 open proposals** · the next free CVE id is **79**.

> ⚠ **Every figure above was DERIVED on the day, not carried** (re-derived 2026-09-27 at the 6.6.7 open).
> `version-bump.sh` rewrites the version token, replaces the `(…)` after it with the bump date, and
> nothing else — **the numbers beside it are yours to re-derive.** Keep the stamp at the start of its
> line and its parenthetical free of nested `(`/`)`, or the bump refuses to rewrite it (and
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red the day it is written). Re-derive gates with `find tests/gates -name '*.sh' | wc -l`; never increment.

**v6.6.0–v6.6.19 are shipped** — the value-form `Result` flip, the repair window (.1–.6), the repair batch (.7–.12),
the memory / TLS / curves / repair releases (.13–.16), the manifest release (.17), distlib + poison (.18, then the
post-tag wave of 12 fold regenerations) and the fold re-vendor + `[embed]` + macOS threads (.19, tag `f5a5175a`). One
line per release is in [completed-phases.md](completed-phases.md) § *v6.6.x*; the detail is the CHANGELOG. **Do not
re-add shipped releases here.** What is left of the minor: **6.6.20**, the closeout (in progress 2026-10-06), then
**v6.7.0** (*The 6.6.x tail* below). ⚠ **At the v6.7.0 rotation** this file becomes the v6.7.x roadmap: the
*Potential backlog* below moves with it (it is 6.x work, never 7.x), and the DCE arc's spec already lives in
[roadmap_6.md](roadmap_6.md) § *Between v6.7.x and RISC-V* (moved 2026-10-06).

---

## The shape of v6.6.x

| Phase | Slots | What goes here |
|---|---|---|
| **1 — repair** | `.1` – `.16` | ✅ **SHIPPED** — the repair window (.1–.6), the repair batch (.7–.12), memory + reported issues (.13), the TLS follow-ups (.14), curves + the compiler leaks (.15), repair (.16). See [completed-phases.md](completed-phases.md) § *v6.6.x*. |
| **2 — the 6.6.x tail** | `.17` – `.19` | ✅ **SHIPPED** — the release sequence ACCEPTED 2026-10-02 (see *The 6.6.x tail*): `.17` manifest (tag `c2e7eef9`), `.18` distlib + poison (tag `010538b5`), `.19` the fold re-vendor + embed + macOS threads (tag `f5a5175a`), all 2026-10-06. |
| **3 — closeout** | `.20` | **IN PROGRESS 2026-10-06** — the full closeout pass, like every minor (user, 2026-10-02: done before any v6.7.x work). Then **v6.7.0**. |
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
| **6.6.18** distlib + poison — ✅ **SHIPPED 2026-10-06** (tag `6.6.18` @ `010538b5`; the 12-fold wave tagged after it) | ✅ **P4** option 2 (the compile-verify fixpoint is the only sidecar authority, with its prerequisites D1–D3; every bundle raw-includable through a requires block; a failed build names the leaf to declare); ✅ **P6** widened (`poison_allocator()`, leading redzone, live-block sweep, settable fill byte, `alloc()` / arena redzones, exit 86, `--poison=ab`; guard pages → backlog); ✅ the ESYSXLAT compile-time fold (`cycc-native-aarch64` −718,792 B, −35.2 %; the pre-commit ARM band back to 700K–2M); ✅ DCE's honest "compaction declined: <why>" note; ✅ the missing `sxtw`; **CVE-78**. The log / ws / ws_server fold bundles moved to 6.6.19 (user decision 2026-10-06: siblings can pin only a RELEASED cyrius, so all 12 folds regenerate in ONE wave after the tag). |
| **6.6.19** — ✅ **SHIPPED 2026-10-06** (tag `6.6.19` @ `f5a5175a`; the gate ran on `19ceb8c6`; CHANGELOG [6.6.19]) | ✅ R1 the 12 folds re-vendored byte-identical from their tags, ✅ R2 `lib/log.cyr` / `lib/ws.cyr` / `lib/ws_server.cyr` include their folds (the PENDING tier retired), ✅ R3 the native TLS stack drops its mirror of sigil's leaves; ✅ B0b (interning by index: byte-identical, self_compile −6.7 %, the 1.9 MB-embed case 11.4 s → ~0.9 s), ✅ P2 `[embed]` + distlib `embed` + the review's E-S1…E-S4 (no CVE: unreleased), ✅ T1 x86-macOS real threads, ✅ A1 / A2 `async_await_readable_ms` on macOS, Windows and agnos. |
| **6.6.20** closeout — **IN PROGRESS 2026-10-06** | The full closeout pass (CLAUDE.md § Closeout, [cycle-discipline.md](cycle-discipline.md)): the release gate, heap / dead-code / refactor / code-review / cleanup passes, a security re-scan, the downstream check, vidya (`types.cyml` still stamped 6.6.1), the backlog re-triage, `verify-store`. Run as one audit (141 findings) fixed in parallel worktree lanes, plus three backlog items the user promoted on 2026-10-06 (the redefined-fn binding, aarch64 calls with 262+ arguments, the `sizeof` / `mulh64` / `fncallN` names). The ledger is in [cycle-discipline.md](cycle-discipline.md) § *Closeout checklist + ledger*. |
| **6.7.0** | The language arc ([roadmap_6.md](roadmap_6.md)): traits first, with the ADR and the one reserved-word survey at the open; P3 `const fn` after `const` and the if-expression; P5's execution half designed with C2. |
| **after v6.7.x, before RISC-V** | The DCE compaction arc (aarch64 first, then PE / Mach-O — spec in [roadmap_6.md](roadmap_6.md) § *Between v6.7.x and RISC-V*), `lib/net.cyr` §4 per-arch socket peers, the remaining syscall families, AF_UNIX (default yes). |

Defaults taken with the plan (the memo's): P4 option 2 (reverses the v6.5.10 "union" stance); P6 widened to
`alloc()` redzones; `output` stays a default and `init --bin` writes `build/{PROJ}`; DCE stays opt-in (so the
`dce` key earns its place); shabdakosh's phf is its own generator, no `#phf` builtin. Sibling follow-ups
once these tag: rekha drops its prelude and CI pin (after P4) and adopts the poison pack (after P6); kriya's and
puka's `--poison` runs check something real (after P6); agnosai, agnostic, rekha and sankoch retire their embed
generators (after P2); sankoch retires its interning proof (after B0a, in 6.6.15).

---

## ~~Open arc — DCE cannot compact on PE, x86 Mach-O or aarch64~~ → after v6.7.x (spec moved 2026-10-06)

Placed **after v6.7.x, before the RISC-V minors — still 6.x** (the tail plan, accepted 2026-10-02). Its spec — the
rip-relative repair in `wp_compact`, the post-compaction re-layout, the aarch64 `bl <ESYSXLAT stub>` sites 6.6.18 added,
and the inverted-gate acceptance — **moved to [roadmap_6.md](roadmap_6.md) § *Between v6.7.x and RISC-V*** at the
6.6.20 closeout, so it survives this file's rotation to v6.7.x (BACKLOG-14). Every target is correct today; the
declining ones only skip the shrink, and say so (6.6.18).

---

## Phase 2 — the tooling round-out (to the minor's close)

**Set 2026-10-01 (user): v6.6.x finishes on tooling. Placed 2026-10-02 (accepted):** P1 + P5-A → 6.6.17,
P4 + P6 → 6.6.18, P2 → 6.6.19, P3 and P5's execution half → v6.7.x — see *The 6.6.x tail*. Each proposal
below carries its placement; the detail of each premise check is in the archived memo.

### ~~P1 — `cyrius.cyml` as the build tool's actual configuration~~ → ✅ SHIPPED 6.6.17 (archived)
[`proposals/archived/2026-09-04-build-tool-manifest-integration.md`](proposals/archived/2026-09-04-build-tool-manifest-integration.md) —
detail in CHANGELOG [6.6.17]. Named profiles are in *Potential backlog*. Its lesson stands for every manifest key
P2 / P4 / P6 add: gate against fixtures written the way CONSUMERS write the key, never in the implementation's own
spelling (the v6.5.49 slice read `src` while 120 of 125 manifests declare `entry`, and its gate passed throughout).

### ~~P2 — Embed data files as source strings (`[embed]`)~~ → ✅ SHIPPED 6.6.19 (archived)
[`proposals/archived/2026-08-10-embed-data-files-as-source-strings.md`](proposals/archived/2026-08-10-embed-data-files-as-source-strings.md)
— its resolution header and CHANGELOG [6.6.19] *Embed — P2* carry the detail; the guide's *Embedding data files:
[embed]* is the reference. The E-S3 residual (Windows, Apple Silicon) is in *Potential backlog*.

### ~~P3 — Compile-time evaluation (`const fn`)~~ → moved to v6.7.x (2026-10-01)
[`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)

It is language, not tooling, so it moved with the rest of the language list. Its spec — the rung
chosen 2026-07-07 and its corrected base (the parse-time folder `_CF_TRY`, not the x86-ELF
peephole that runs only under opt-in `CYRIUS_IR=3`) — is now [roadmap_6.md](roadmap_6.md)
§ v6.7.x, item C1. *(Corrected 2026-10-04, 6.6.16: this stub used to point at "the
`ir_const_fold` ordering constraint", a base roadmap_6.md had already retracted on 2026-10-02.)*

### ~~P4 — test-only stdlib leaves, instead of hiding them from the umbrella scan~~ → ✅ SHIPPED 6.6.18 (archived)
[`proposals/archived/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md`](proposals/archived/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md) —
option 2 plus the D1–D3 prerequisites the planning simulation missed; detail in CHANGELOG [6.6.18], consumer notes in
[ecosystem-migration-6.6.18.md](ecosystem-migration-6.6.18.md). Its measured note stands: over-reporting a REAL but
unnecessary leaf is silent, so it is quieter, not safer.

### P5 — `cyrius coverage` over RUN programs, not only `.tcyr` suites
[`proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md`](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md)

**🟡 OPEN — A SHIPPED in 6.6.17** (text corpus + per-entry view: `[coverage] programs`, `--programs <glob>`, `--per-entry`); **B (execution coverage) is v6.7.x with C2** — it shares C2's insertion point and build-flag plumbing. P5 stays OPEN until B: archiving it after A would narrow the filing silently. The scope question (text references vs execution) was answered by the placement: A is text, B is execution.


### ~~P6 — `cyrius fuzz --poison` through a custom allocator seam~~ → ✅ SHIPPED 6.6.18 (archived)
[`proposals/archived/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md`](proposals/archived/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md) —
widened as planned (S1–S6 + `poison_allocator()`; `alloc()` and arena redzones, exit 86, `--poison=ab`); detail in
CHANGELOG [6.6.18] and the guide's *Fuzzing with `--poison`*. S7 guard pages are in *Potential backlog*; S8 (the
manifest / interposition shape) was dropped.

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

- **Found by the 6.6.19 lanes and their review (2026-10-06; backlog — only the user promotes).**
  - **The `[embed]` link race on Windows and Apple Silicon (E-S3 residual).** Linux and x86 macOS walk the path
    with `openat(dirfd, component, O_DIRECTORY | O_NOFOLLOW)`; PE keeps the per-component reparse-point check plus a
    whole-path `O_NOFOLLOW` open, so a directory swapped for a junction between them is followed — fix with
    `GetFinalPathNameByHandleW` on the opened handle + containment under the project root (a NEW PE reroute).
    macOS arm64's `SYS_OPENAT` 56 is rerouted to BSD `open` DROPPING the dirfd (Linux `AT_FDCWD` −100 ≠ Darwin −2,
    so a straight row to `openat` 463 would break every open) — needs a dirfd-preserving Mach-O route, with a
    companion in `tests/tcyr/crossos/`. Both need concurrent write access to the checkout during the build.
  - **`sizeof` is in neither of `util.cyr`'s reserved tables** (`TOKNAME_BUILTIN` / `IS_KEYWORD_TOK`): `fn
    sizeof()` declares, and calling it is a parse error. `mulh64` and `fncall0..8` are the same shape
    (`_is_ident_intrinsic` / `_IS_FNCALL_NAME`). Any tool that derives the reserved set from util.cyr alone misses
    them — `[embed]`'s list reads all four sources.
  - **The macOS-arm64 `cyrius` CLI looks for `cycc_aarch64` in `CYRIUS_HOME/bin`** (the ecb `[embed]` smoke had to
    supply one) — check whether that is intended for a native Mach-O host.
  - **Some gates leave temp dirs in `TMPDIR`** — the 9.9.9 installer staging and `cyrius-<pid>` test dirs.
- **Found by the 6.6.19 R2/R3 work (2026-10-06; backlog — only the user promotes).**
  - ⚠ **A redefined fn did not bind to its LAST definition in one build** (possible silent mis-binding): in
    `stdlib_alloc_refusal_sentinels.sh`'s ws_server probe, a stub `sandhi_server_find_header` defined after
    `include "lib/ws_server.cyr"` was called from `main`, yet `ws_server_handshake` still called sandhi's
    version — while the compiler warns "last definition wins". Two-file repros DO bind to the last
    definition, so the trigger is specific to that build (call sites compiled before the redefinition inside a
    large fold?). Needs a repro hunt, then a fix or a named refusal.

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces.

> **Placed 2026-10-02 (the tail plan, accepted):** items named in *The 6.6.x tail* are scheduled there and
> stay listed below only until their release ships. **Removed 2026-10-02** with the evidence in the archived
> memo §3(d): the `ir_dce` / `CLASSIFY_CF` line (the wrappers were deleted at 6.5.50, `374f361d`; CLASSIFY_CF
> is wired through RA_SCAN_LOOPS), the bare `var a[N]` question (subscripting one is a hard error naming the
> typed spelling; overrun checks go to C2), the I7 / race-gate port flake (shipped in 6.6.14), the Rosetta
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
  - `dce_eliminates.sh` exits 7 silently under `bash -eo pipefail` (it passes under `sh`, which is how check.sh runs it).
  - `cbt/commands.cyr`'s comment "dir_list is non-recursive, so fuzz and tests are disjoint" is stale since v6.5.7.
  - Two `check.sh` selectors in parallel in ONE worktree collide on `build/cyrius_check` — run them in parallel only
    across worktrees (or give the check driver a per-run output name).
  - ~893 stale `/tmp/cyrius-*` directories on the dev box — the 6.6.20 closeout cleanup.
- **Found by the 6.6.17 lanes (2026-10-05; backlog, not placed — only the user promotes).** Met in passing by the
  6.6.17 implementers, reviewers and integrator, each pre-existing unless it says otherwise; not swept for.
  - ⚠ Silent wrong value: `var q: B1 = p;` with `p: *B1` and `sizeof(B1) <= 8` stores the POINTER into q (`q.v` reads
    an address), while `var p: Node = h;` with `h: *Node` COPIES the struct, so a walk `p = p.next` overwrites nodes
    or loops. Decide bind vs copy (or refuse) for `Struct = *Struct` once, with the value / handle model — **v6.7.x
    language arc** candidate.
  - ⚠ aarch64: a call with ~300 or more arguments (direct or `callptr`) dies with SIGILL under qemu (250 / 260 right;
    509+ `callptr` arguments segfault).
  - ⚠ cx: a call with more than 248 arguments has nowhere to put them (250 return a wrong value, 260 trap "guest stack
    overflow"); value-form vector arguments ride r16..r31, which are integer argument registers once a call has 14
    or more integer arguments.
  - A method call on a field (`h.name.len()`, `h.name.clone()`) is `expected ';'`; compound assignment on any field
    (`h.n += 1`) is `expected '='` — a missing common feature, **v6.7.x** candidate.
  - `p[i]` on a `*T` is refused (no element descriptor) — with `p + n` now `sizeof(T)` everywhere, a typed-pointer
    subscript is the natural next step (**v6.7.x** candidate).
  - An UNTYPED `var u = s.clone();` does not take a method's struct return type (`u.len()`: "no struct type in
    scope"); a free call's result is inferred.
  - A generic-struct FIELD `b: Box<i32>;` is `expected identifier, got '<'`; `#derive` on a struct with a
    `Vec<Box<i64>>` field stops its field walk at the nested `<` (later accessors undefined — loud).
  - `#pure`'s `#io` / `#alloc` check reads the callee's flags at the call, so a call to an `#io` fn defined LATER is
    silent (only `#deprecated` has a pass-1 record).
  - cybs refuses a fn with more than 6 parameters with a bare `syntax error` and no location (keep `src/` helpers at
    6 parameters or fewer until it names it).
  - The aarch64, both Mach-O and cx forks ignore `--syntax-only` (only main.cyr and main_win.cyr read it), so
    `cyrius lint` / `check` do a full compile there — slower, harmless.
  - `_strict_mode` is set by six `src/main*.cyr` forks and read by none (`cycc --strict` has had no effect since
    6.3.2) — a dead-code closeout item.
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
  - ⚠ `cyrius deps` READ side: a `modules` entry with `../` or an absolute path, and a TRANSITIVE manifest's
    `path`, vendor any local file into the consumer's `lib/` (security-relevant; 6.6.16's CVE-76 covers the `tag`
    field only). Confining a transitive `path` to its own manifest's tree is the design call (54 legitimate root
    `path = "../sibling"` uses).
  - ⚠ Silent wrong values: a top-level `var v = pair_fn(..)` keeps the tag and drops the payload (the v6.5.67
    single-bind refusal is gated on `GINFN == 1`); `var G: f32 = 1.5` (global or local) stores the f64 bit
    pattern with no warning; through a pointer-mode 8-byte struct, `o.m()` (self = `&o`) and `T_m(o)` read
    different values.
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
  - sigil (its repo) — the TPM helpers probe `/dev/tpmrm0` and spawn `/usr/bin/tpm2_*` by rooted path,
    drive-relative on Windows if reachable on PE (the CVE-65 class, an executable this time); its check.sh
    builds at predictable `/tmp/sigil_{t,b,f}_$$` paths. sandhi (its repo): `lib/sandhi.cyr` ~1589 still
    calls the tls ctx a 24-byte struct.
- **Found by the 6.6.12 premise check and lanes (2026-09-30; backlog, not placed — only the user promotes).**
  Met in passing, not swept for. Its three ⚠ silent-memory-corruption items were promoted to **6.6.13**
  (M1–M3) on 2026-10-01.
  - Windows `sys_symlink` (CreateSymbolicLinkW) widens with `_win_widen` at 519 units, no `\\?\` — a link
    at a path over 260 units fails -1 (honest).
  - cyrius-lsp `lsp_read_file` reads the open document through a fixed 1 MB buffer, silently.
  - `cyrius lib sync --full` does not re-lock `cyrius.lock`, so rows for files a repo does not vendor keep
    stale hashes until a lock is regenerated from empty (kriya and yantra both hit it).
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
