# Cyrius Future Work — Beyond Current Minor

**Scope** — A **6.x-cycle watching / potential-backlog list**: known work not yet
pinned to a slot, pulled forward into a v6.x minor the moment consumer pressure
materializes (placement is "watching," not "deferred"). **PLACEMENT RULE (hard):
everything technical here is 6.x-cycle work — no codegen / runtime / platform item is
ever a "v7 item."** The ONLY genuine 7.x content is the **public-release manuscript
(the "language book") + legal / release invariants** at the bottom of this file. If it
compiles code, it belongs in a 6.x minor (roadmap.md pinned order) or the roadmap.md
potential backlog — never parked to 7.x.

See [roadmap.md](roadmap.md) for the current active minor and
[roadmap_6.md](roadmap_6.md) for the whole v6.x cycle.

---

## cyrius-x (cx) bytecode backend — ✅ SHIPPED (v6.4.17–.22, SIMD .32, finish-outs .54/.58)

Landed in v6.4.x: `cyrius build --target=cx` CLI (.17), cx f64 arith (.18) + compare (.19),
cross-OS portable `.cyx` running on all four hosts (.20), cxvm cap/dispatch hardening (.21/.22), and
full cx SIMD codegen (.32, per-lane emitters + cxvm opcodes 0x66–0x68). Portable `.cyx` is now a
byte-exact SIMD correctness oracle. **Two later finish-out slots closed the correctness tail**: **.54**
(code-stream misalignment + the forward-call resolver — both filed cx bugs turned out to be
misdiagnosed, and fixing the real causes roughly doubled cx correctness) and **.58** (cx `%` was broken
for *every* modulo, plus 64-bit immediates via cxvm opcode 253). Detail in
[CHANGELOG.md](../../CHANGELOG.md) + completed-phases.md.

> ✅ **cx indirect call — SHIPPED v6.5.13.** `.cyx` opcode **105 (`callind`), PERMANENT**:
> `fn ECALLIND` is real at `src/backend/cx/emit.cyr:488`, the matching cxvm arm at
> `programs/cxvm.cyr:272`, gated by `tests/gates/codegen/cx_indirect_call.sh` (8 assertions).
> The issue is archived `✅ RESOLVED v6.5.13`.
>
> ⛔ **This box previously asserted the gap was open and unscheduled, and it was struck on
> 2026-08-11 — six releases late.** It had been *added* by the 2026-08-07 sweep to stop this
> section reading as a finished arc, so it became the exact rot it was written to prevent; its
> markdown link was also dead, pointing into `issues/` for a file that had moved to
> `issues/archived/`. Root cause: **`## [6.5.13]` has an EMPTY CHANGELOG body**, so there was
> no canonical line for either this file or `roadmap.md` to reconcile against. Verify
> stale-shipped rows by **running the compiler / reading live code**, never by re-reading the
> row.

---

## SIMD Phase 5 — aarch64 NEON + cx/PE — ✅ SHIPPED (v6.4.28–.32, finish-outs .53)

Phase 5 completed the whole packed-SIMD arc on the remaining three backends: **aarch64 NEON**
(v6.4.28 f32v4/f32v8, .29 f32v8-free via 2×128 fallback, .30 integer vectors + `iv_dp8` — the **last
SIMD XFAIL removed**), **Win64 PE value-form params + returns** (.31), and **cx bytecode per-lane
emitters** (.32). Packed SIMD now runs on all four backends; all `simd_*` ARM XFAILs are gone and the
`vr01_simd_*` fixtures run real emitters cross-OS on ecb/pi/cass. **Finish-outs at .53**: the duplicate-arg
`f(v, v)` bug — root cause was the *tail-call* path taking no second XMM pass, fixed on all targets — plus
i64v2 packed multiply. Only caveat, **re-verified 2026-08-07 at v6.5.10**
(`src/backend/aarch64/emit.cyr:2882-2884` — re-derived 2026-08-11; the line numbers have now moved twice, from `:2639-2641` to `:2691-2693` to here, so
re-grep rather than jumping to a cited line): the aarch64 *native* 256-bit `EMIT_F32V8_*`
emitters are `return 0` stubs that are never reached, because `lib/simd.cyr` routes f32v8
through native f32v4 NEON (the verb works; a native 256-bit path is x86-AVX2-only). Detail in
[CHANGELOG.md](../../CHANGELOG.md) + completed-phases.md.

---

## v6.1.x carry-in (from the v6.0.x → v6.1.0 closeout, 2026-06-07) — ✅ MOSTLY SHIPPED

Surfaced by the v6.0.91 closeout judgment-pass workflow (heap/dead-code/
refactor/code-review/security/downstream — all otherwise clean). **Status
2026-06-10:** the first three shipped — `aarch64 EADDRA_IMM` @ v6.1.2,
`_emit_fmt`/`_entry_base` hoist @ v6.1.4, DCE consolidation @ v6.1.5. The
freed-scalar-holes reclaim (informational) stays a fill-as-you-go item.
**Re-verified against live code at the v6.4.82 close, and again 2026-08-07 at v6.5.10** —
each bullet below now carries its shipped status inline, because the write-ups themselves
still read as pending work and this list is meant to stay honest about what is done. The
2026-08-07 re-check: `_emit_fmt` is still a single definition
(`src/backend/common/runtime.cyr:61`), `_entry_base` still deliberately two
(`x86/fixup.cyr:35` + `aarch64/fixup.cyr:29`), `_dce_hash_lookup`/`_dce_host_fn` still single
(`runtime.cyr:444`/`:466`) — all three bullets hold:

- **`aarch64` ADD/SUB-immediate 12-bit-mask class — CLOSED.** `EADDRA_IMM` was
  fixed at v6.0.91 (three-way split); the two remaining unguarded siblings
  (`EADDIMM_X1` struct-field offsets, `EPATCHFRAME` prologue frame size) were
  swept and fixed at **v6.2.21**, and the other imm12 sites (`ESTOREB_IMM`,
  `ELOAD_LOCAL_ADDR`) confirmed guarded. All latent (cycc's own offsets/frames
  are small; 256-field struct cap + array globalization keep source < 4096), so
  none bit in-tree — guarded by `tests/tcyr/aarch64_imm12_frame_field.tcyr` +
  disasm differentials. Original write-up (historical):
  [`issues/archived/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md`](issues/archived/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md).
- **Hoist `_emit_fmt` / `_entry_base` to a shared home — ✅ SHIPPED v6.1.4 (`_emit_fmt`);
  `_entry_base` deliberately stayed per-backend.** Live check at the v6.4.82 close:
  `_emit_fmt` is a single definition in `src/backend/common/runtime.cyr`, so the prereq
  below was done and the hoist landed. `_entry_base` still has two definitions
  (`x86/fixup.cyr` + `aarch64/fixup.cyr`) — and correctly so, because the bodies are no
  longer the duplicates this bullet described: they diverged on format/kmode/W^X/PIE
  constants (x86 carries `fmt == 1` Mach-O-x86 and the kmode 1/2 ladder; aarch64 does
  not). **Nothing further is owed here.** Original write-up: the v6.0.89 first-bite left
  these byte-identical-duplicated deliberately, and the hoist was BLOCKED by the
  single-pass parser + include order — `runtime.cyr` is parsed before `emit.cyr`, but
  `_emit_fmt` reads `_TARGET_MACHO/_PE/_ELF64_KERNEL` as bare-identifier globals declared
  only in `emit.cyr`, so a hoist there was a hard "undefined variable" exit. The prereq
  (move the `_TARGET_*` declarations into `runtime.cyr`/`tokens.cyr`) is what unblocked it.
- **Consolidate the DCE mark-and-sweep across `x86/fixup.cyr` +
  `aarch64/fixup.cyr` — ✅ SHIPPED v6.1.5.** Live check: `_dce_hash_lookup` and
  `_dce_host_fn` are single definitions in `src/backend/common/runtime.cyr`. Original
  write-up: the hash build/seed/propagate/sweep/undef-fn pass was duplicated across the
  two backends, and within each the open-addressing hash-probe + the linear host-fn scan
  were each written twice; the shared pair collapsed 4 probe-blocks → 1 and 4 host-scans
  → 1 (arch delta is only `E8/E9`+`DECODE_LEN` vs `BL/B` 4-byte stride).
- **Reclaim the FREED scalar holes** (informational, **still open — fill as you go**; live
  total **18** FREED regions at v6.5.10, `grep -n FREED src/main.cyr`, re-derived 2026-08-07) —
  the compiler-state scalar band has the ~2 KB v6.0.88 `ret_patches` hole + the v6.0.47
  holes (`0x18E630`/`0x18EE30`/`0x18F900`/`0x18F908`); allocate the next new
  compiler-state scalar into the `.88` hole rather than growing the band. All four v6.0.47
  holes are still marked FREED in the `src/main.cyr` heap map at the v6.4.82 close, and
  v6.4.75 added six more (`0x100000`, `0x14A000`, `0x15A000`, `0x16A000`, `0x17A000`,
  `0x1C8000`) when the fn-indexed side tables went lazy-alloc — so there is more reclaimable
  band now, not less. All four + six re-confirmed present 2026-08-07; the other eight FREED
  regions are v6.0.88 (2), v6.1.40 (3), v6.3.41, v6.3.28 and v6.4.21. **None of 6.5.0–.10
  grew the fixed band** — the visibility file-id substrate, the lazy fn-table bases and the
  v6.5.9 growable arena are all `alloc`-backed, so the heap map has held at 100 regions / 0
  overlaps across the whole minor so far.

---

## TS/TSX → JS emit — ✅ SHIPPED (v6.1.10–.15)

The `cycc --emit-js` / `cyrius build --target=js` codegen stage landed: walk the existing
AST — strip type annotations / interfaces / aliases, lower JSX → `createElement`-style
calls, pass ESM through (single-file; a bundler stays out of scope). Phase D emitter on
the corrected AST (v6.1.10/.11), surfaced via `cyrius build --target=js` (v6.1.12),
`async`-on-nested-arrow fix (v6.1.15). The TS/TSX front-end already *parsed* real-world
TS/TSX cleanly (SecureYeoman's `yeo-cy-test` probe, 2026-05-27) — this closed the
"validator but not builder" gap. check.sh-gated (`programs/checks/ts.cyr`
`_emit_js_to_file`, `tests/fixtures/ts_emit/`). Issue archived:
[`issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`](issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md).

> **Cautionary tale (kept on purpose — [[feedback_no_codegen_parking_in_v7]]):** this sat
> as "minor TBD / consumer-filed with active pressure" in this watching list for a while
> before it shipped — the SAME deferral pattern that kept the **cx backend** target-less
> "for a couple majors when it was ready to" (the wasm-shaped wall only broke when a
> consumer hit it, .17). A ready or near-ready capability belongs in a **pinned 6.x
> slot**, not left in watching/"minor TBD" limbo to "get found out." And keep this list
> HONEST: mark shipped items SHIPPED — do not leave them framed as pending (this entry was
> stale until 2026-07-11).

---

## Unpinned language refinements

These were tracked through v5.x as known asks but explicitly held
unpinned at v5.8.65 close (2026-05-05) — consumer pressure either
didn't materialize or workarounds proved sufficient. Re-evaluate
at each cycle-open per [`feedback_premise_check_at_slot_entry`].

> **Re-verified against LIVE code at the v6.4.82 close, and again on 2026-08-07 at v6.5.10**
> (not against each row's own text — that is exactly how the TS→JS row above went stale).
> ⚠ **The 2026-08-07 pass found this promise had NOT held**: *per-block scoping* was pinned
> here to v6.6.x while roadmap_6.md had struck the same item as shipped nine days earlier,
> and the *128-bit div-mod* row described code that had a hardware fast path. Two of eight
> rows wrong. **Re-run the probes; do not trust this banner.**

| Feature | Effort | Status / Notes |
|---|---|---|
| **Hardware 128-bit div-mod** | Medium | Stays unpinned, but **the description was wrong and is corrected here (2026-08-07)**. It said "shift-based". Live: `bayan_u128_divmod` (`lib/bayan.cyr:618`) has an **x86-only hardware fast path** for the `b_hi == 0` case — two back-to-back unsigned `div`s written as **raw machine-code bytes in an `asm { }` block inside a stdlib file**, `#ifdef CYRIUS_ARCH_X86`-gated precisely because those bytes would SIGILL elsewhere. Only the full 128/128 case still runs the 128-iteration shift-subtract loop, and **aarch64/cx get the slow path for everything**. What remains true — and is now the sharper argument — is that **no `div`-family emitter exists in any backend**, so the fastest u128 division in the ecosystem is hand-assembled x86 in a library. Pull forward if a real perf regression surfaces, or if aarch64 numeric work makes the arch asymmetry bite. |
| **Phase 3-full varargs** (`va_arg` for structs-by-value + nested) | Medium | Phase 3-min shipped v5.5.36. Stays unpinned — niche. Most consumers use array-of-args pattern instead. |
| ~~**cycc per-block scoping**~~ | — | ✅ **ALREADY SHIPPED — struck 2026-08-07.** This row still said "▲ PINNED v6.6.x" while [roadmap_6.md](roadmap_6.md) had already struck the same item on 2026-07-29 as shipped since the v3.7.4 era — **two docs, opposite statuses, neither checked against the compiler**, which is the exact rot the header above claims this table is free of. Re-verified by RUNNING the compiler on 2026-08-07: `if (1) { var inner = 5; } return inner;` → `error:<source>:3:15: undefined variable 'inner'`, and `var x = 1; if (1) { var x = 5; return x; }` exits **5** (the inner binding). What remains is that a **same-scope** redeclaration is a hard error — which is the documented rule in CLAUDE.md, deliberate, and not an unshipped item. Do not re-plan it. |
| **Incremental compilation** | High | Stays **watching**. Whole-program self-host is fast (~500 ms @ v6.1.x). Reconsider when cycc self-host crosses ~2 sec (**685 ms @ v6.5.19**, 2026-08-11 release gate; 648 / 652 ms @ v6.5.10, ~622 ms @ v6.4.82, 638 ms @ v6.5.2 — still ~3× under the threshold, but note the +6 % at .19, triaged as growth tax). ⚠ **Do not read a trend off single numbers here**: v6.5.7 ran the SAME binary three times for **649 / 670 / 701 ms**, a 52 ms spread that is *wider than any release-over-release delta this minor*, so this box cannot resolve deltas at that scale. Quote the pair, not a point. Per user 2026-06-11, **the next few arcs will inform the timing**: the v6.5.x perf-quality minor + RISC-V (now v6.7/v6.8) will show whether self-host is approaching the threshold (the bench harness is un-blind since v6.2.15/v6.3.17, phase-resolved). Don't pin now; let those arcs report. Same posture for the **bus-factor / institutional-memory** question (vidya + memory-pins live outside the repo) — revisit as those arcs land. |
| **Stackless coroutines** (suspend/resume across `await`) | Medium (poll-runtime rework) | ▲ **PINNED v6.5.x** (user, 2026-07-26). The unpin condition this row carried — *"No live consumer; pull forward on a real suspend-across-await need"* — **has been met**: stiva filed [`2026-07-25-stiva-stackless-coroutines-interactive-exec.md`](issues/2026-07-25-stiva-stackless-coroutines-interactive-exec.md) naming two blocked v3.1.0 features, after carrying *"stiva is that consumer and has not filed; filing is the unblock lever"* as an open action for weeks. Bound into the v6.5.x arc alongside the IR-substrate work it depends on — the poll-runtime rework (+ force-once memoization) is the same substrate the perf-quality minor opens. v6.3.11 shipped async/await as deferred-then-forced Futures over a run-to-completion epoll runtime, explicitly NOT stackless CPS. Subsumes the mid-body-suspend "gap 6" of the shipped async "W" arc. |
| **Async reactor-fd `O_CLOEXEC`** | — | ✅ **SHIPPED v6.4.43** — epfd (EPOLL_CLOEXEC), connect/resolve + UDP sockets (SOCK_CLOEXEC), accept fd (F_SETFD FD_CLOEXEC), and reactor timerfds (TFD_CLOEXEC) are all close-on-exec; a fork-in-reactor child no longer inherits reactor fds. No longer a watching item. |
| **Async single-waiter-per-fd** | — | ✅ **SHIPPED — no longer a watching item.** ⛔ This row read *"▲ BOUND INTO the v6.5.x Slot 8 coroutine arc … **Verified still live at v6.5.19**"* until 2026-09-02, and that verification had been overtaken by shipped code. Re-derived from live source: `_async_wait_events` (`lib/async.cyr:334`) computes a UNION mask via `_async_fd_mask` (`:322`) and falls back ADD→MOD; `_async_step` walks the ENTIRE task list (`:201-211`) waking every task parked on that fd whose mask matches, `EPOLL_CTL_MOD`s the remainder rather than unconditionally DEL-ing (`:217-230`), and wakes ALL waiters on EPOLLERR/EPOLLHUP (`fired & 24`, `:200`) since a peer that closes mid-relay delivers HUP only. The per-task `wait_ev` field is at +56. ⚠ The double-tracking this row described is therefore resolved: only Slot 8's Half B (mid-body suspend / CPS) remains, and that is tracked in `roadmap.md`, not here. |
| **f32 scalar arithmetic** (native-float Tier A tail) | — | ✅ **SHIPPED v6.4.56** — f32 scalar arith/compare + WARN-only typecheck, together with scalar-`f64` return type (v6.4.55). The scalar-float completion slot is closed; no longer a watching item. |

---

## DX / cyrlint tooling (watching)

Static-analysis lint gates worth a single `cyrlint` tooling slot when a
consumer ask pulls them. (The DX diagnostics arc itself SHIPPED — column +
source-excerpt v6.4.60, panic-mode multi-error recovery v6.4.62, the
reserved-word diagnostic naming all 67 builtins v6.4.77, and the `PEEKT` EOF
clamp that killed the 166,670-line truncated-input cascade v6.4.78 — so these
lint gates are the remaining unpinned tail, not part of that arc.) Consolidated
here from standalone issues at the v6.4.15 absorber-band hygiene pass — no
urgency, no consumer blocked; the underlying bugs each already have a real fix.
**Both verified un-shipped at the v6.4.82 close and again at v6.5.10** (2026-08-07;
no lint source in `cbt/` implements either check). They now have a **named W2
fold-in slot** in [roadmap.md](roadmap.md) — "the two cyrlint gates, one bite" —
so they are pinned 6.x work, not watching. ⛔ And per the placement rule,
**linter / formatter / LSP evolution is 6.x-line work**: roadmap_6.md parked it
at 7.x until 2026-08-07, when it was corrected and re-homed.

- **Bare-local-array slot-write lint** (was `issues/2026-06-25-bare-local-array-slot-write-lint.md`)
  — warn when a bare `var a[N]` (N *bytes*, rounded to 8) is written past its byte
  size as if it were N *slots*; needs byte-size-vs-max-index analysis. ~21 intentional
  sites in-tree today (the v6.4.10 top-level-array fix closed the codegen half; this is
  the lint half).
- **Syscall-write byte-length gate** (was `issues/2026-06-25-syscall-write-byte-length-gate.md`)
  — a permanent check that `syscall(SYS_WRITE, fd, "literal", LEN)`'s LEN matches the literal's
  byte length. **Re-derived 2026-08-20 at v6.5.33: 532 literal-arg sites, 0 mismatches.** The
  tree is currently CLEAN, so this is preventive, not remedial. (The earlier "609 sites" figure
  counted a looser pattern; 532 is the count of sites this lint could actually check.)
  ⭐ **Worth more than its Low priority suggests.** Two off-by-one message lengths were written
  during v6.5.30–.32 alone — `"…is not one"` passed 76 for a 77-byte string and shipped a
  diagnostic reading `"is not on"`, and a second was caught the same way. Both were found by
  *reading the output*, which is the only detector there is today.
  ⚠ **Implementation trap, learned deriving that count**: a naive checker that round-trips the
  literal through `unicode_escape` reports 23 false mismatches, all off by exactly 3 — every
  string containing an em dash, whose 3 UTF-8 bytes get double-decoded. Count raw bytes and
  collapse only two-char backslash escapes.
  Batch with the bare-local-array lint as one cyrlint line — both are
  byte-length-vs-declared-size static checks.

---

## Stdlib libs (consumer-filed proposals)

Discrete stdlib additions filed by ecosystem consumers; each is its own slot when
pulled (no urgency — every consumer has a working fallback today).

| Lib | Filed by | Effort | Status / Notes |
|---|---|---|---|
| ~~`lib/protobuf.cyr`~~ (proto3 wire encode/decode) | hoosh (OTLP/OpenTelemetry span export) | — | ✅ **Shipped v6.2.17**, finished v6.3.42 (double/float wire helpers + guide section, protobuf.tcyr 49 cases). Minimal proto3 wire codec — length-delimited messages, no `.proto` compiler; pure Cyrius, no syscalls. Proposal archived. |
| ~~`sys_fsync`/`sys_fdatasync`~~ | hapi (atomic manifest edits) | — | ✅ **Shipped v6.2.14** — bare wrappers in `syscalls_x86_64_linux.cyr` (74/75) + `syscalls_aarch64_linux.cyr` (emit x86 74/75, ESYSXLAT → 82/83). Proposal archived. |

---

## Speculative type-system work

Long-horizon items that go beyond the v6.3.x Language Refinements
arc (closures + monomorphization + async sugar). Not pinned to any
minor; floats in the watching list until a specific consumer ask
or design driver materializes.

- **Polymorphic items beyond monomorphization** — trait-bounded
  generics, higher-kinded types, GATs (generic associated types),
  or whatever shape post-monomorphization generic work needs once
  consumers start hitting the next ceiling. **Trait-bounded generics
  got a DEMAND-GATED home at the v6.6.x ergonomics tail (2026-07-07)**
  — pulls in only if consumer pressure materializes by that arc-open
  (the multi-tparam struct-type-arg residual lands first — single-tparam
  shipped v6.3.38/.39). HKTs/GATs stay here.
- **Effect tracking beyond `@unsafe`** — v5.8.x shipped `@unsafe`
  as the first effect annotation. Lift-to-more-effects (e.g.
  `@io`, `@alloc`, `@panic`) only if a real consumer enforcement
  scenario emerges.

---

## ~v7.0 — Public release ("Cyrius ONE") — FULL-PUBLIC IS AN OPEN QUESTION

**Reframed 2026-06-11** (user): "sovereign and usage — whether its full public
is still in question." Sovereign + usable is the committed direction; a *full
public* release (the book on Amazon/Packt + an installer aimed at strangers) is
**not a decided commitment**. Keep the manuscript + public launch as a *possible*
v7 shape, a watching item — not a gate.

Two things follow:
- **v6.x grows much more before any v7.0.0 bump** (user 2026-06-11) — see
  roadmap_6.md "What comes after v6.x". v7 is further out than earlier framing
  implied; the language can keep accumulating surface across additional v6.x
  minors.
- **The usability/adoption debt is worth paying regardless** of whether it ever
  goes fully public — diagnostics, debug-info, stdlib-reference coverage, the
  GPL linking-exception question all make the toolchain better for the *existing*
  ecosystem too. Tracked in roadmap_6.md "Usability / adoption readiness" + the
  2026-06-10 deep-dive audit. **Two of those have moved since this was written**:
  the diagnostics half SHIPPED in v6.4.x (column + excerpt .60, multi-error
  recovery .62, reserved-word naming .77), and **debug-info (DWARF) is 6.x-line
  work, not a v7 item** — it is codegen, and per the placement rule at the top of
  this file nothing codegen is ever parked to 7.x. Only the GPL/licensing question
  is genuinely a public-release item; the stdlib-reference authoring is docs.

**If/when a public release is decided**, the book ("written from Vidya +
first-party docs") fixes a "stable point" — when the language stops accumulating
substantial new surface. That point is now expected later in (or after) the v6.x
cycle, not at a near-term v7.

**LEGAL-01 — GPL-3.0-only stdlib statically source-included into consumers (v7-release blocker).**
Cyrius is GPL-3.0-only, and the stdlib (including folded sigil, whose own licensing has a
dual-BSD/GPLv2 leg) is *source-included* into every consumer at build time, so consumer binaries
inherit GPL-3.0 obligations. Before any full-public release this needs a deliberate licensing
decision — a linking/library exception, or an explicit statement that consumers accept GPL-3.0 —
with legal sign-off. Deliberately deferred to near public release (was tracked in the now-archived
`issues/archived/2026-06-10-unreviewed-dimensions.md`; the rest of that issue — CVE-28/29,
DX-01/02, SEC-AGNOS-01 — all shipped by v6.3.23).

---

## v7.0 commitments (NOT items — invariants)

Two known commitments per CLAUDE.md "Version lives in `VERSION` +
`--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
- **Prior-major slot rotates at v7.0.0**. **cc3 was already dropped at
  v6.1.0** (corrected 2026-06-10 — earlier text here said "build/cc3 drops
  at v7.0.0", which contradicted CLAUDE.md's "dropped at v6.1.0"; finding
  RM-05). The prior-major slot now holds **cc5** (the last v5.x top
  compiler); at v7.0.0 it rotates to the last v6.x `cycc` — same binary
  name, so the slot effectively retires (no rename bridge).

---

## How items move from here into a cycle

An item earns a v6.x slot when:
1. A consumer files a specific need (per
   `docs/development/issues/`) that the item closes.
2. Cycle bandwidth opens during a minor's absorber band.
3. User direction explicitly pulls it forward at slot entry.

When pulled forward: edit `roadmap.md` to add the item to the
target minor; remove from `roadmap-future.md`. The reverse path
(de-pinning a roadmap item back to "watching") is rare but
happens when premise-check at slot entry shows the work isn't
ready or consumer need evaporated.

---

## Retired references

- **roadmap-old.md** (1,249 lines, deleted v6.0.x) — contained the
  v5.x long-term considerations + v5.12.x retired-spec archive +
  v5.x platform-shipping table + pre-pinned v6.x narrative.
  Resolved pins moved to `roadmap.md`; unpinned items moved here;
  durable principles consolidated into `cycle-discipline.md`;
  ecosystem/platform snapshots moved to their canonical docs
  (`docs/ecosystem.md`, `docs/platform-status.md`); pre-v5.11.x
  retrospective material lives in `completed-phases.md`.
- **roadmap-last.md** (272 lines, deleted v6.0.x) — frozen v5.11.x
  in-flight roadmap. Fully duplicated CHANGELOG + new `roadmap.md`
  + memory pins by v6.0.0 cycle-open.
