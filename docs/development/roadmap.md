# Cyrius Development Roadmap — v6.3.x (active minor)

**Scope** — the **current active minor only** (v6.3.x — Language
Refinements), opened at the v6.2.x → v6.3.0 cut (2026-06-28). This is the
slot-pinning working artifact: the **proposed v6.3.x release workflow**
(the eight-release sequence below). The *fuller* per-cluster design (closures
/ generics / async / native-float), the rest of the cycle (v6.4.x → v6.6.x),
and the closed-minor summaries live in [roadmap_6.md](roadmap_6.md).

> **v6.3.0 shipped** the var-family growable migration — the last fixed
> compile-time cap (closes the v6.2.0 Phase-0 / AR-03 growable-region arc).
> **v6.3.1 shipped** dependency-model **lever 2** — required vs optional deps
> (`optional`/`[features]`/`--features`/`target=`); cbt-only, cycc byte-identical.
> **v6.3.2 shipped** the **undefined-fn reachable-call hard-error** (default-on,
> `--allow-undef` to downgrade) + the cx annotation-desync fold — the flip's full
> blast radius treated with ZERO `--allow-undef`.
> **v6.3.3 shipped** bare-metal **#5** (`[sections] base` settable kernel load base —
> de-dup'd `_kernel_load_base` accessor + `CYRIUS_KERNEL_BASE` env; resolves the
> kernel-load-base-settable issue) + **#6** (x86 inline-asm fences `mfence`/`lfence`/`sfence`
> — the last gap; the rest of #6 shipped .27/.28). check.sh 101→102; byte-identical default.
> **v6.3.4 shipped** bare-metal **#7** — kernel-freestanding `lib/tls_native` link
> (`_tls_freestanding_link_gate`) + a full TLS 1.3 handshake smoke over ONLY the transport/entropy/clock
> hooks, zero socket/getrandom syscalls (`tls_native_freestanding.tcyr`, x86+pi). **Completes the three
> OPEN bare-metal design deliverables #5/#6/#7** (#1–#3 shipped .27/.28; #4 forbidden-module-check was
> never built — filed `issues/2026-06-28-bare-metal-forbidden-module-check-unbuilt.md`). Test/gate-only →
> cycc byte-identical; check.sh 102→103.
> See [CHANGELOG.md](../../CHANGELOG.md).

> **v6.3.x EXPANSION (user direction 2026-06-30).** v6.3.x does **not** close out at
> .16. The whole **v6.4.x ABI/Perf arc** (Class B FFI / `fncall6` ABI + cross-BB
> regalloc/liveness + copy-prop + cross-BB DSE + float peephole) is **pulled into
> v6.3.x**, alongside the **2026-06-10 governance cluster** (security-audit tail,
> verification-coverage gaps, unreviewed dimensions) — **minus LEGAL-01**, which is
> deferred to near public release. The **Intel-Mac (x86_64 Mach-O) toolchain arc**
> runs at the **tail** of v6.3.x. **v6.4.x reopens as an empty staging minor.** The
> perf-arc prerequisites (un-blind the bench harness · land the differential-corpus
> gate) come FIRST, then the governance body, then the perf arc, then Intel-Mac, then
> closeout. See the expanded slot table below (v6.3.17 →).

> **v6.2.x is CLOSED** (Platform Expansion — bare-metal core + dependency-model
> lever 1; shipped .0 → .52). **v6.1.x CLOSED** (Backend Codegen multi-arc,
> .0 → .41). **v6.0.x CLOSED** (Language Cleanup + Stdlib + Native TLS, .0 → .91).
> Per-slot detail is canonical in [CHANGELOG.md](../../CHANGELOG.md); the
> closed-minor summaries live in [roadmap_6.md](roadmap_6.md).

> **Reading order**: this file (active-minor release workflow) →
> [roadmap_6.md](roadmap_6.md) (full v6.x cycle + fuller v6.3.x cluster
> design) → [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** reference
  (framing, per-minor budgeting, the fuller v6.3.x cluster design,
  v6.4.x → v6.6.x, the closed v6.0.x / v6.1.x / v6.2.x summaries).
- [roadmap-future.md](roadmap-future.md) — long-term watching list.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check at
  slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.3.x — Language Refinements

**Theme**: the language-level trio the v5.x cycle held out explicitly —
**closures with lexical capture, real generic instantiation
(monomorphization), and async/await sugar** — gated behind a **Phase 0
substrate** prerequisite. Native-float Tier A continues here. Riding the
language minor: the **dependency-model lever 2** (Required/Optional deps) and
the **bare-metal design-deliverable tail** (#5/#6/#7), both pinned in 2026-06-27.

Per-cluster design (scope, acceptance bars, touched surfaces) is in
[roadmap_6.md § v6.3.x](roadmap_6.md). This file pins what we execute now.

**Near-term committed focus** (the opening releases → **v6.3.1–.4** in the
workflow below, in order):

1. **Required vs Optional Dependencies (lever 2)** — the scoping layer on top
   of the v6.2.x modules/groupings foundation (lever 1). **[v6.3.1 — SHIPPED]**
2. **Undefined-fn reachable-call hard-error** — its own slot. **[v6.3.2 — SHIPPED]**
   (default-on flip + `--allow-undef`; full blast radius cleaned with ZERO `--allow-undef`;
   cx annotation-desync folded in.)
3. **Bare-metal deliverable completion (#5/#6/#7)** — the structured pass over the three open
   bare-metal *design* deliverables, split #5+#6 then #7. **#5+#6 SHIPPED [v6.3.3]; #7 SHIPPED
   [v6.3.4] — the three OPEN design deliverables DONE.** (#4 forbidden-module-check was never built —
   filed `issues/2026-06-28-bare-metal-forbidden-module-check-unbuilt.md`, P3.)
4. **Phase-0 substrate (D)** — CO-01 order-independent call ABI (pass-1 prescan) + AR-01
   monomorphization token-replay revival (GATED PROOF, no default codegen change; user 2026-06-28).
   **[v6.3.5 — SHIPPED]** Non-capturing closures **[v6.3.7 — SHIPPED]** + lexical capture
   **[v6.3.8 — SHIPPED]** (closures arc complete). **NEXT: real generic instantiation /
   monomorphization on this substrate [v6.3.9].**

Per cycle discipline: premise-check each arc at slot entry
([[feedback_premise_check_at_slot_entry]]); cross-arch propagation is
mandatory for any compiler-emit change
([[feedback_cross_arch_propagation_mandatory]]); 4-host cross-OS self-host
verify before every cut, even lib-only work
([[feedback_cross_os_verify_always_even_lib]],
[[reference_verification_hosts_ssh]]); seed-derive after any `src/` change
([[feedback_seed_derive_mandatory_cybs_limits]]); benchmark every release
([[feedback_benchmark_every_release]]). Window open to change
([[feedback_minor_window_at_arc_open]]) — minors flex long.

---

## v6.3.x release workflow (proposed sequence)

Nine releases, derived 2026-06-28 from a 3-lens sequencing pass
(dependency-topological / bottom-to-top-consumer-pressure / risk-first) +
your sequencing decisions (recorded below). The spine honors your stated
near-term order **A → B → C** (B un-bundled from A into its own slot once A
landed and B's 21/192 blast radius was measured), gates generics behind the
non-negotiable Phase-0 substrate, and lands the language trio last (weakest
live consumer pull). Sizes indicative; minors flex long. **v6.3.x is expected
to grow well beyond these nine** (user 2026-06-28): this is the committed spine, and
issue-repairs + items that become necessary get pulled in as they surface
through the minor — inserted between or alongside these releases, not capping
them. Only the user re-scopes ([[feedback_no_unilateral_scope_decisions]]);
reactive pull-ins follow the bare-metal open-window pattern
([[feedback_bare_metal_open_reactive_window]]). Per-cluster design lives in
[roadmap_6.md § v6.3.x](roadmap_6.md).

| Release | Content | Folds / riders | ~bites |
|---|---|---|---|
| **v6.3.0** ✅ | **var-family growable migration** — SEVEN `vcnt`-indexed tables → `_base` + chained `_var_grow` (byte-identical under cap). Closes the v6.2.0 Phase-0 / AR-03 arc — last fixed compile-time cap. | — | shipped |
| **v6.3.1** ✅ | **Deps lever 2 (A)** — `optional = true` + `[features]` table + `--features`/`--no-default-features` + platform-conditional `target=` keys (axes combine; builds on lever 1). cbt-only → cycc byte-identical; check.sh 100→101 (`_deps_features_gate`). [[project_v6_3_x_required_optional_deps]] | — | shipped |
| **v6.3.2** ✅ | **Undefined-fn reachable-call hard-error (B), default-on** + `--allow-undef` downgrade — **SHIPPED** (+ the cx annotation-desync fold **F**). Treated the flip's full blast radius with **ZERO `--allow-undef`** in the repo's own builds: 18 tcyr include-completed; 3 mabda tcyr via **source-gating** (**mabda 3.4.5** `#ifdef MABDA_LOGIND`/`MABDA_PNG`, re-folded); cx fork 47 `*_PE`/`*_ARM` stubs (`backend/cx/emit.cyr`); CLI→PE 11 POSIX stubs (`lib/syscalls_windows.cyr`); ark `nous` stubs (`programs/nous_stub.cyr`); TLS-probe includes. check.sh 101/101; ecb+cass+pi SELFHOST_OK; bench 505 ms; cycc 1,075,616 B; seed-derive OK; pi native-fixpoint OK. *(Original plan:)* Its OWN slot (un-bundled from A, user 2026-06-28). Flip the x86/aarch64 fixup gate from `_strict_mode` → `_allow_undef`; add `--al` to the 5 argv forks (`main_x86_macho` stub always-hard-errors). **Blast radius MEASURED at slot entry: 21/192 tcyr fail under the flip** — **18 are stdlib include-gaps** (real `str_*`/`vec_*`/`str_builder_*`/`payload`/`dynlib_*` refs; surgically complete each tcyr's includes — the raw-`cat\|cycc` harness has a repo-relative-include dedup subtlety that makes a blanket `cyrius build` switch non-trivial), **3 are `lib/mabda.cyr`→external `samvada_*`/`chitra_*`** (not in-repo; **fix at mabda's SOURCE**: declare optional + guard the device/PNG calls so they're not DCE-reachable when absent, then re-fold — the proper lever-2 dogfood, user 2026-06-28). [`issues/…undefined-fn-reachable-call-hard-error.md`](issues/2026-06-25-undefined-fn-reachable-call-hard-error.md). | DRY-4-scanners **dropped** (byte-identity + cybs-limit hostile per the v6.3.1 premise-check — stays on the carry-in line); the cx annotation-desync fix (the one real bug the rider targeted) folds here | ~6 |
| **v6.3.3** ✅ | **Bare-metal #5 + #6 (C-1)** — `#5` `[sections] base` settable kernel ELF load base in `cyrius.cyml` (de-dup'd `_kernel_load_base` accessor + `CYRIUS_KERNEL_BASE` env + base-aware D6 report; resolves the kernel-load-base-settable issue); `#6` x86 inline-asm fences `mfence`/`lfence`/`sfence` (the only gap — `cli`/`sti`/`hlt`/`cpuid`/port-I/O shipped .27/.28; aarch64 `dmb`/`dsb`/`isb` already complete). check.sh 101→102 (`_sections_base_override_gate`); byte-identical default; pi+ecb+cass SELFHOST_OK; bench 504 ms; cycc 1,077,136 B. **Premise-check found the roadmap stale on #6.** | opt-in bounds-checked `store*`/`load*` **carried to bug-bandwidth** (not folded — #5+#6 packed the slot) | shipped |
| **v6.3.4** ✅ | **Bare-metal #7 (C-2)** — kernel-freestanding `lib/tls_native` link + in-kernel handshake smoke (cyrius-side link + smoke; *live* in-kernel boot stays AGNOS-consumer-gated). **Premise-check found the foundation already shipped** (transport vtable v6.2.4 + entropy hook v6.2.28 = the freestanding hooks; tls_native already compiles under the kernel target) — the gap was the PROOF. `tls_native_freestanding.tcyr` runs a full 1.3 handshake over the hooks alone (fork + mmap loopback, ZERO socket/getrandom/clock syscalls on the TLS path; x86+pi); `_tls_freestanding_link_gate` proves the native stack links into a freestanding kernel ELF. check.sh 102→103; cycc byte-identical (test/gate-only). Filed: `tls13-server-get-version-zero` (P3) + `bare-metal-forbidden-module-check-unbuilt` (#4 was never built — the one remaining bare-metal gap). **Completes the OPEN design deliverables #5/#6/#7.** | **byte-length gate (DOTALL) → carried to bug-bandwidth** (separate standing audit; #7 packed the slot); load-base settability rider DONE in v6.3.3 #5 | shipped |
| **v6.3.5** ✅ | **Phase 0 substrate (D)** — **CO-01** order-independent call ABI: pass-1 fn-signature prescan (`_prescan_fn_sig`, all 7 forks) registers every top-level fn + masks/return-type before pass-2 emits calls → forward calls get the right `: Str`/SIMD/struct-return ABI (was silent mask-0). Shared `_classify_param_type`/`_classify_return_type` (differential byte-identical). **AR-01** monomorphization token-replay revival as a **GATED PROOF** (user 2026-06-28 — no default codegen change): the emit-time replay was always INTACT, only the capture was off; opt-in `_MONOMORPH_OK` (`CYRIUS_MONOMORPH=1`, all 7 drivers) re-enables it; `_monomorph_substrate_gate` (check.sh 103→**104**) + REAL pi prove byte-correct + active (the aarch64 corruption was already gone via relocation). `forward_call_abi.tcyr`; filed `inferred-struct-local-from-call-segfaults` (P2). **TYPE substitution / generics deferred to v6.3.7.** Self-host + seed→cybs→cycc byte-identical; tcyr 195/195; ecb+cass+pi SELFHOST_OK; bench 509 ms; cycc 1,079,440 B. [`issues/…monomorphization-substrate-prereqs.md`](issues/2026-06-10-monomorphization-substrate-prereqs.md). | local-array bare `var a[N]` slot-write lint (prescan territory) **carried to bug-bandwidth** | shipped |
| **v6.3.6** ✅ | **Ecosystem refold + AGNOS `sys_symlink` peer** — LIB-ONLY maintenance cut (cycc byte-identical, only the version string moved). Refolded **sigil 3.9.4→3.9.7** (SECURITY: 64-lane per-thread crypto banking kills the concurrent-TLS-handshake race; streaming Poly1305 `poly1305_init/_update/_finalize`; `ecdsa_p256/p384_warm` prewarm; per-lane RSA residue zeroize; `.bss` +~14 MB lazy), **patra 1.12.6→1.12.7** (per-handle tail-page cache, handle 64→88 B, internal `tbl_insert/5→/6`), **sandhi 1.6.13→1.7.0** (h2-promote IPv6 arity fix), **vani 0.9.5→0.9.6** (pin bumps + chrono). Added `sys_symlink`+`SYS_SYMLINK=63` to `lib/syscalls_x86_64_agnos.cyr` (mirrors `sys_link`#32 4-arg a4=r10; agnos kernel `symlink`#63 @ 1.51.0; unblocks ark M3 `.so→.so.N`/agnova/kriya). api-surface regenerated (additions-only — 5 sigil crypto + `sys_symlink/4` + internal patra arity, NO removals). check.sh 104/104; seed→cybs→cycc byte-identical; ecb+cass+pi SELFHOST_OK; bench 502 ms; cycc 1,079,440 B. on-agnos symlink round-trip = downstream ark M3 exerciser. | — | shipped |
| **v6.3.7** ✅ | **Non-capturing closures (E-base)** — premise-check found `\|x\| body` closures a scaffolded-but-NON-FUNCTIONAL, untested, unused feature (not "working closures missing capture"). Fixed FIVE codegen bugs, all from the closure being an anon fn emitted INLINE in the enclosing fn while sharing its mutable state: param-passing (`_cur_fn_regalloc` leak → params past phantom callee-saved slots + stale-reg reads), frame size never `EPATCHFRAME`'d, zero-param `\|\|` (lexed as logical-or), enclosing-local clobbering (shared local-slot tables → snapshot/restore), and the regalloc post-pass byte-scan rewriting+corrupting the inline closure (SIGILL → skip via `_cur_fn_has_closure`). + unique `__clNNNNN` naming. **First-ever `tests/tcyr/closures.tcyr`** (8 cases). Closures run on x86 + aarch64(qemu) + PE(wine); self-host byte-identical (closure-path-only); check.sh 104/104; ecb+cass+pi SELFHOST_OK; bench 501 ms; cycc 1,081,696 B. Planned base-first split (user 2026-06-29). | — | shipped |
| **v6.3.8** ✅ | **Lexical capture (E-capture)** — a closure body reading an enclosing local (a free variable) is captured **by value** into a heap env object `[fn_ptr, cap0, …]` at construction; the closure value *is* the object, dispatched via `callptr` auto-dispatch (callee tagged `CLOSURE_TYID` 0x40000003 → load fn ptr from `[obj]`, pass obj as the hidden env arg1 — call sites identical to non-capturing). `_cl_prescan_captures` intercepts `FINDLOCAL` against the v6.3.7 enclosing-name-table snapshot (free var = FINDLOCAL-fails + not param/shadow + not an `IDENT(` call + IS in snapshot); the capturing closure gains a hidden env param (slot 0; user params +1); captured read = `load64(env+(1+capi)*8)`. Needs `include lib/alloc.cyr` + `alloc_init()` (fail-loud else). Non-capturing closures stay bare fn ptrs. FIXED: stale-name scratch slot → false "duplicate variable" (shared local tables not cleared per-fn; anonymize scratch + `callptr` spill slots `name=-1`). PE: capturing fails loud (env + `ECALLPTR_PE` align unverified); non-capturing PE works. **`tests/tcyr/closures_capture.tcyr`** (7 cases). Self-host byte-identical (closure-path-only; differential vs 6.3.7); seed→cybs→cycc OK; check.sh 104/104; capture 7/7 on x86 + aarch64(qemu) + native-aarch64 regen self-hosts byte-identical & runs 7/7; PE non-cap runs / cap fails-loud (wine); closures.tcyr 8/8; ecb+cass+pi SELFHOST_OK; bench 507 ms; cycc 1,089,248 B. Closures arc complete (E-base .7 + E-capture .8). | — | shipped |
| **v6.3.9** ✅ | **Generic FUNCTIONS — i64 monomorphization (F-fns)** — `fn foo<T>(...)` over **i64**, on the proven AR-01 substrate (`_MONOMORPH_OK`, default-off → cycc byte-identical). Type-params captured at the signature (`_capture_tparams` replacing `SKIP_GENERICS`, gated) into lazy-alloc `_fnt_tparams`; a scoped `T→concrete` binding (`_tp_resolve`) substitutes at the 4 type-resolution sites (param-type / local `:T` / `slice<T>` / `sizeof`). **Architecture: the base fn IS the i64 instantiation** — its body is emitted ONCE with `T→i64` bound (`_bind_generic_call(fi,-8,-8)` before `PARSE_PROG`), so i64 calls are plain normal calls (dedup-by-construction, no instantiate-once needed). Positional inference from args; `: T` return accepted (the load-bearing fix: the return-type rough-scan was defaulting `: T` to the retptr/stash ABI, shifting params — recognize a tparam as i64-scalar). **+ btokens ceiling 16→32.** Gate `_generics_fn_i64_gate` (check.sh 104→**105**) — fixture exits 42 under the flag, REJECTED off. Byte-correct x86 + aarch64(qemu); self-host + differential + seed→cybs→cycc byte-identical; bench/cycc-size recorded in CHANGELOG. **Deferred to v6.3.10** (shares the instantiate-once machinery with structs): non-i64 type-args (`foo<i32>`/`foo<Struct>`), explicit `foo<i64>(x)` syntax. First half of the 2-release generics arc (user 2026-06-30). | — | shipped |
| **v6.3.10** ✅ | **Generic STRUCTS + non-i64 fn instantiation + explicit syntax (F-structs)** — second half of the generics arc; the full non-i64 surface on one **instantiate-once engine**. **Explicit `foo<i64>(x)`** via a non-consuming `<`-disambiguation lookahead (`LOOKAHEAD_IS_TYPE_ARG_CALL`; gated + generic-fn-callee-only, so `a<b` unaffected). **Non-i64 fn instances** (`add<i32>`): mint `foo$ty`, `FINDFN`-dedup, **re-invoke `PARSE_FN_DEF`** on the base's verbatim tokens (`_fnt_defstart`) with name + concrete-binding overrides (`_inst_name`/`_inst_conc0/1`) — full fidelity (params/masks/struct-args/body) for free, jumped-over (`EJMP0`/`EPATCH`) with enclosing-state save/restore + `_cur_fn_has_closure` regalloc-skip. **Generic structs** (`Pair<i32>`, `Holder<Point>`): the base IS the i64 instance (`val: T` → untyped field); non-i64 use re-invokes `PARSE_STRUCT_DEF` with the field `: T` consult → `Box$ty` via `REGSTRUCT`+`FINDSTRUCT`-dedup; wired at the `var x: Box<conc>` type site. **Verified x86 + aarch64(qemu)**: `add<i32>`/`Pair<i32>`/`Holder<Point>`(struct-type-arg, field-offset-correct)/dedup/fn×struct mix all exit-correct; self-host + differential + seed→cybs→cycc byte-identical (gated `_MONOMORPH_OK`); `_generics_full_gate` (check.sh 105→**106**). Filed pre-existing **1-field-struct segfault** (P2, non-generic). **Deferred** (not yet): nested `Outer<Inner<T>>`, multi-type-param distinct `T`/`U`, control-flow in generic-fn bodies. | — | shipped |
| **v6.3.11** ✅ | **Async/await (G)** — `async fn`/`await` → **first-class Futures** over the cooperative epoll runtime (NOT CPS coroutines — see below). An `async fn` call builds a deferred heap Future `[ &f$impl, argc, args… ]` (constructor; body = hidden `f$impl`); `await fut` → `future_force` via `fncallN`. Reuses E's closure-env heap construction. Gated `_ASYNC_OK` (`CYRIUS_ASYNC=1`) → cycc byte-identical (differential vs .10, x86+aarch64). `_async_await_gate` (check.sh 106→**107**). **Premise-check found the runtime is run-to-completion** (no suspend/resume), so true stackless CPS coroutines would need a poll-runtime rework — pinned as a follow-on; the deferred-then-forced Future model is the faithful, complete fit. **Native-float Tier A tail (H): already complete** (f64 type+operators+NaN x86/aarch64 .18/.19/.41; f32 conversions .18) — only f32 *scalar arithmetic* remains, consumer-less (mabda shims deleted .19), **deferred** as an optional follow-on. self_compile 533 ms; cycc 1,107,280 B. | x86-macOS usable-toolchain tail (ach-gated) | shipped |
| **v6.3.12** ✅ | **[gate] W^X — `cyrld` separate code/data PT_LOAD (P1, linker)** — every userland ELF now emits a text `R E` segment + a data `RW ` segment instead of one `RWE`, closing the last writable-executable surface on the agnos W^X loader (1.50.6 PF_X-aware → zero kernel work). **DEFAULT ON; `CYRIUS_WX=0` opts out.** Data vaddr 2 MB-aligned (`_wx_data_vaddr`; agnos huge-page granularity), file offset to `p_align` (4 KB x86 / 64 KB aarch64) so `p_vaddr ≡ p_offset` → near-zero file bytes. FIXUP ↔ EMITELF_USER lockstep on `dbase`; `.text` shifts 120→176 for the 2nd PH (entry follows). x86 + aarch64 (separate backends); Mach-O/PE/kernel/`.so` unaffected. **Two-step bootstrap to flip default-on** (cc2 stable W^X fixpoint == cc3); seed→cybs→gen2 W^X. `_wx_segments_gate` (check.sh 107→**108**, reads emitted PHs); `readelf -lW` confirms text R E / data RW on x86, aarch64, `CYRIUS_TARGET_AGNOS`. ecb+cass(unaffected)+pi(W^X, real aarch64) SELFHOST_OK; bench 538 ms; cycc 1,111,576 B. [`proposals/2026-06-29-elf-wx-separate-code-data-segments.md`](proposals/2026-06-29-elf-wx-separate-code-data-segments.md). | — | shipped |
| **v6.3.13** ✅ | **[gate] str_builder concurrency — ROOT-CAUSED + opt-in fix (P1)** — the "miscompile of str_builder fns" framing was WRONG: the real cause is FUNDAMENTAL — **`var arr[N]` LOCALS are allocated at a fixed global/BSS address shared by every thread** (scalar locals already stack-allocate per-thread; array locals went through the global var table). Any concurrent path using an array-local aliases one global buffer → ~87% cross-thread splice. Found via an ultracode 3-agent workflow (the minimal-reduction agent nailed it by varying the byte source: `&array-local` = identical `0x600C18` across all 8 threads vs scalar `lea[rbp-N]` per-thread). **Fix (opt-in `CYRIUS_STACK_ARRAYS=1`):** `PARSE_ARRAY` routes array locals to per-thread STACK slots (struct-local multi-slot mechanism; `&arr`/`arr[i]` already had `FINDLOCAL`→`lea[rbp-N]` branches — one shared-frontend change covers x86 + aarch64 + all 7 forks). `THREAD_STACK_SIZE` 64KB→2MB. Validated: str_builder `sb_fail 0`, per-thread x86+aarch64, cycc self-hosts (binary SHRANK as arrays left BSS), seed-derive byte-id, flag-off differential byte-id; `_array_local_threadsafe_gate` (check.sh 108→**109**). [`str-builder issue`](issues/2026-06-28-str-builder-not-thread-safe.md). | — | shipped |
| **v6.3.14** ✅ | **AGNOS syscall peer — 8 missing wrappers (lib-only)** — `lib/syscalls_x86_64_agnos.cyr` omitted 8 numbers the agnos kernel dispatches (the kernel implements 0–63 contiguous): `sys_klug`#36 (log ring), `sys_execwait`#37 / `sys_spawn_path`#43 / `sys_exec_redirect`#62 (process/exec + capture), `sys_fbinfo`#38 / `sys_blit`#39 (framebuffer), `sys_kbscan`#42 (input), `sys_sched_yield`#44. Proactive before the base-system consumers (kavach, bote, t-ron, thoth, phylax, aegis) port to `--agnos`. New `SysNrAgnosProc` enum + 8 `sys_*` wrappers (`#39 blit` a4=r10). cycc byte-identical (lib-only); a `--agnos` program calling all 8 emits the right `syscall #N`. [`issue`](issues/2026-06-30-agnos-syscall-peer-incomplete-8-wrappers.md). | — | ~1 |
| **v6.3.15** ✅ | **[gate] array-locals default-on (P1, completes .13)** — per-thread array locals flipped opt-in → **DEFAULT** (`CYRIUS_STACK_ARRAYS=0` opts out). Both .13 blockers fixed: **m128 16-align** (one-slot parity pad when `&arr` disp ≡ 8 mod 16 → `pxor`/`aesenc xmm,[arr]` #GP-free) + **`secret var` zeroise** through the LOCAL slot (`ELOAD_LOCAL_ADDR`). **Auto-fallback**: an array over the per-fn 16384-slot budget stays global+`note:` (sole case = sigil `hash_file_into` 256 KB buf, already global → no regression). The feared ecosystem footgun was a FALSE ALARM (buggy awk mis-flagged element-typed arrays); a precise + 11-file agent audit = **295 bare-array locals, 0 over-runs, ZERO stdlib changes**. 6 `.tcyr` suites using the daimon under-declared-array idiom → element-typed decls; `secret`/`element_typed_array` rewritten layout-independent. Two-step bootstrap; cycc SHRANK 1,111,616→1,027,664 B. Gate GREEN (check.sh 109/109; seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; bench 544 ms). [`array-locals arc`](issues/2026-06-30-array-locals-stack-default-on-m128-align.md). | — | shipped |
| **v6.3.16** ✅ | **[gate] var-decl codegen pair (P2)** — 3 struct-local codegen bugs (`parse_decl.cyr`). **(a)** inferred `var p = mk()` from a struct-returning call → infer the struct type + route through the explicit-annotation retptr/`rax:rdx`-pair codegen. **(c)** single-≤8B-field struct field access segfaulted on x86+aarch64 (1-slot has no `-1` filler → misread as pointer-to-struct → `mov[slot]` not `lea&slot`); fix = force inline when `STRUCTSZ<=8`, gated `_TARGET_CX==0` (cx boxes structs → already correct; parity test stays green). **(b)** string-literal global init already fixed earlier → regression-locked. `struct_local_codegen.tcyr`; verified x86 + aarch64 (real pi native) + cx = 42; ecb+cass+pi SELFHOST_OK; check.sh 109/109; bench 546 ms. 3 issues closed→archived. [`inferred`](issues/archived/2026-06-28-inferred-struct-local-from-call-segfaults.md) · [`1-field`](issues/archived/2026-06-30-single-field-struct-segfaults.md) · [`str-literal`](issues/archived/2026-06-28-string-literal-global-initializer-garbage.md). | — | shipped |
| — | **▼ v6.3.x EXPANSION (user 2026-06-30): pull the whole v6.4.x ABI/Perf arc + the governance cluster (ex-LEGAL) into v6.3.x; do the Intel-Mac arc at the tail; v6.4.x reopens as an empty staging minor. Closeout moves to the very end.** | | |
| **v6.3.17** ✅ | **[gov / perf-prereq] Bench harness un-blind** — **PF-02** `alloc()` single-threaded fast-path (`_alloc_lock_acquire`/`_release` no-op while `_threads_active == 0`; `thread_create`/`_thread_spawn` arm the flag before the child runs → skips the v6.0.64 CAS spinlock + 2 fences for the dominant single-thread case, incl. cycc; single-thread allocs monotonic, concurrency fixture clean, one-step self-host fixpoint) + **PF-03** `bench-history.sh` tier-3 `CYRIUS_PROF=1` per-phase rows (`compiler/phase_pp/lex/gvar/parse/fixup/emit/write` ns → v6.5.x perf-refactor trend). PF-01 already done (v6.2.15). Unblocks perf-delta measurement for the pulled-in v6.4.x arc. self_compile flat 545 ms (cycc not alloc-bound); check.sh 109/109; ecb+cass+pi SELFHOST_OK. Issue closed→archived. [`runtime-bench-suite-blind`](issues/archived/2026-06-10-runtime-bench-suite-blind.md). | — | shipped |
| **v6.3.18** ✅ | **[hardening, consumer-filed] stdlib undersized-array-locals sweep** — completes the v6.3.13 stack-locals sweep (a bare `var X[N]` written past `ceil(N/8)*8` bytes smashes the frame). Filed by the AGNOS base-stack migration. A 17-file agent audit (max-write-width vs slot) caught **2 genuine stack-smashes both in `sankoch.cyr` bzip2** — `_bz_decode_block` `var pos[6]`→`[48]` (48-byte `store64` loop) + `_bze_emit_block` `var present[16]`→`[128]` (128-byte loop), the daimon footgun (slots-meant-bytes-declared), **missed by the v6.3.13 sweep AND the v6.3.15 audit**. The 34 sites the issue named (`process`/`regression`/`pam`/`shadow`/`net`/`tls`/`yukti`/`ws`/`syscalls_*`) were latent-benign (≤8 B writes fit the 1-slot alloc) → sized correctly anyway (byte-identical codegen). New `sankoch_bzip2_roundtrip.tcyr`; cycc byte-identical (consumer-lib-only); check.sh 109/109; ecb+cass+pi SELFHOST_OK; bench 540 ms. Issue closed→archived. [`stdlib-undersized`](issues/archived/2026-06-30-stdlib-undersized-array-locals-stack-smash.md). | — | shipped |
| **v6.3.19** | **[gov / perf-prereq] Differential-corpus gate** — VR-03 `scripts/differential.sh`: build old (git-ref) cycc + new cycc, compile the pinned logic-preserving input set with both, `cmp` all outputs + a `CYRIUS_DCE=1` torture mode; manual-trigger gate. The ONLY guard between the regalloc / copy-prop refactor and a silent miscompile → **MUST precede the perf arc**. [`verification-coverage-gaps` VR-03](issues/2026-06-10-verification-coverage-gaps.md). | — | ~2 |
| **v6.3.20** | **[gov] Security-audit tail (RM-06)** — **CVE-09** jump-table overflow (`backend/x86/jump.cyr:44` cap-1023 silent truncation past 1023 targets → per-fn growable table or hard error; real codegen bug — lets LASE mis-eliminate) + CVE-10 paper-close (fixed v4.10.0, never ticked) + **CVE-11** stack-canary decision (emit, or accept-with-rationale in `threat-model.md`) + re-file CVE-09/11/12/13 as tracked rows (12/13/20 already CLOSED via the v6.2.30/.31 trust-chain arc) + **RM-02** rewrite `threat-model.md` (correct the TLS-backend / ASLR-PIE / input-buffer-cap misstatements + add native-TLS Known Limitations) + pin the next full-audit cadence. [`overdue-security-audit-cve-tail`](issues/2026-06-10-overdue-security-audit-cve-tail.md). | — | ~5 |
| **v6.3.21** | **[gov] Verification coverage (found-by-consumers class)** — **VR-01** full tcyr on all 5 targets + targeted tcyr for the 8 win/macOS platform stdlib variants (`fs_win`/`thread_win`/`sync_windows`/`alloc_macos`/`args_macos`/`process_win`/`syscalls_macos`/`syscalls_windows`) + promote LIBTEST to a standing per-host gate; **VR-02** fuzzing (TLS record/ClientHello mutation `.fcyr` into `_tn_parse` asserting clean-error-not-crash + a cycc-parser corpus-mutation fuzz); **VR-04** pure-cyrius binary structural lint (ELF/PE/Mach-O headers / section bounds / imports / entry-in-text) on every funcgate artifact. (VR-01/02 partially shipped v6.2.29.) [`verification-coverage-gaps`](issues/2026-06-10-verification-coverage-gaps.md). | — | ~7 |
| **v6.3.22** | **[gov, ex-LEGAL] Unreviewed dimensions** — **CVE-29** `PROT_NONE` guard page below each thread stack (`lib/thread.cyr:50-55`; catches stack overflow loudly — complements the v6.3.15 array-locals-on-stack move) + **DX-01** minimal line-table / `CYRIUS_SYMS` parity across all 5 backends + **SEC-AGNOS-01** agnos-target security pass (entropy / W^X / ASLR-PIE applicability / `alloc_agnos` guard) + **DX-02** `cyrius-lsp` correctness + untrusted-workspace-input pass. **LEGAL-01 EXCLUDED** — GPL linking-exception legal review deferred to near public release (v7 blocker). CVE-28 already resolved (v6.1.38). [`unreviewed-dimensions`](issues/2026-06-10-unreviewed-dimensions.md). | — | ~8 |
| **v6.3.23** | **[v6.4.x pull-in — ABI] Class B FFI / `fncall6` ABI fix** — fix Cyrius's `fncall6` vs SysV AMD64 calling-convention bug (mabda's wgpu integration needs it). Held-forward through v5.9.x–v5.11.x. | — | ~5 |
| **v6.3.24** | **[v6.4.x pull-in — perf] Cross-BB regalloc + liveness** — linear-scan register allocator with cross-BB liveness data. **AR-04 substrate decision at entry**: extend the x86 byte-peephole vs. activate real IR-level register allocation (the latter is the only path to aarch64/riscv64 regalloc parity). Gated behind the differential corpus (v6.3.18) + bench un-blind (v6.3.17). | — | ~6 |
| **v6.3.25** | **[v6.4.x pull-in — perf] Copy propagation** — `ir_copyprop_recon` revival (deferred v5.6.18/.19; the stack-machine IR had no virtual registers for the classical wins — regalloc surfaces them). | — | ~3 |
| **v6.3.26** | **[v6.4.x pull-in — perf] Extended cross-BB DSE** — `ir_extdse_recon` revival (per-BB DSE shipped v5.6.18; the cross-BB variant needs the per-BB liveness-out set regalloc builds). | — | ~3 |
| **v6.3.27** | **[v6.4.x pull-in — perf] Float peephole + bench-delta eval** — `float.cyr:41` 5-instruction → 3-byte reduction (land if the bench delta justifies) + the ABI/perf-arc bench-delta evaluation + tcyr coverage (now measurable, given v6.3.17). | — | ~4 |
| **v6.3.28** | **[Intel-Mac arc, tail] x86-macho native miscompile fix** — the core blocker (**High**): the cross-built cycc emits a broken NATIVE x86_64 Mach-O cycc (`backend/x86/emit.cyr` + `backend/macho/emit.cyr`) — Intel Macs have no working compiler. [`macos-x86-release-no-compiler`](issues/2026-06-02-macos-x86-release-no-compiler.md). | — | ~3 |
| **v6.3.29** | **[Intel-Mac arc, tail] x86-macho toolchain completion** — `_read_env`/`_macho_fill_environ` for x86-macho (HOME defaults to `/root` today); `cbt` `set_arch` Intel-vs-Apple-Silicon detection (unconditional `ARCH_AARCH64` today); wrapper cycc-discovery for x86-macho; complete `build-macos-x86-tarball.sh`; add the x86-macho branch to `install.sh` + point `release.yml` build-macos at it; add the x86 arm of the real-install gate on **ach** (Intel Mac, mirror of the ecb check); revert the superseded layer-1/3 `#ifdef CYRIUS_TARGET_MACOS` branches once `main_x86_macho.cyr` is the default. | — | ~7 |
| **v6.3.N (closeout)** | **Closeout** — cross-feature integration tcyr (generic closures, async closures capturing a generic, concurrent array-locals) + the minor-close pass (heap-map audit, dead-code, refactor, code-review, cleanup, doc/vidya sync). Sweep residual P3 issues (tls13-server-get-version-zero, bare-metal-forbidden-module-check #4, syscall-write-byte-length-gate, bare-local-array-slot-write-lint) into bug-bandwidth or the reopened v6.4.x. Ships code, not docs-only. | — | ~4 |

**Per-release gates & risks** (the places these bite):

- **v6.3.1 (SHIPPED):** byte-identical for any manifest with no `[features]`/`optional`/
  `target` (the lever-1 deps gates are the regression wall); `cyrius build --features X`
  resolves the gated dep, plain build does not; `target=` skips on a non-matching host;
  axes combine. All proven by `_deps_features_gate` + 6 manual transition tests.
- **v6.3.2 (B blast radius — MEASURED 21/192):** gate on **all 192 `.tcyr` green under
  default-on hard-error** — 18 via surgical per-tcyr include completion, 3 via the
  mabda-source optional-gating + re-fold. If any can't be made green, that's
  **STOP-and-ASK**, not a quiet `--allow-undef` sprinkle (one-bug-one-complete-fix).
  cybs-limit + seed-derive after the fixup/main-fork edits; cross-arch parity x86==aarch64.
- **v6.3.3 (#6 cross-arch emit, ABI-leak class):** disasm-verify each primitive on
  x86 **and** aarch64; guard x86-privileged ops (`cli`/`sti`/`hlt`/`in`/`out`/`cpuid`)
  on non-x86 paths; 4-host self-host mandatory — a green CI check is **not**
  verification.
- **v6.3.5 (cycle's load-bearing unknown):** AR-01 must **root-cause** the ARM
  metadata corruption that disabled `_INLINE_OK`, not paper over it — regression
  probe proving correct emit on **real pi** (aarch64-native tcyr). If un-revivable,
  surface it (it gates generics).
- **v6.3.7 (perf cliff):** the self_compile budget is a **hard** gate with in-scope
  dedup + cap-headroom — the v6.x cycle already ate a +65 % growth-tax once.
- **Every release:** seed-derive after any `src/` change (cybs limits — small fns,
  no tail calls; the v6.3.0 seed-break lesson, [[feedback_seed_derive_mandatory_cybs_limits]]),
  bench delta in CHANGELOG, 4-host cross-OS for emit changes, premise-check at entry.

**Sequencing decisions on record (user, 2026-06-28):** (1) Phase-0 substrate lands
**after** bare-metal (your literal A → B → C order), not as an early risk-spike;
(2) the **full** language trio (closures + generics + async) executes inside v6.3.x;
(3) bare-metal splits **#5+#6 then #7** (isolates the cross-arch emit change from the
stdlib-link for cleaner verification); (4) **A and B un-bundled** — A (deps lever-2)
ships as v6.3.1 on its own; B (undef-hard-error) gets its own slot v6.3.2 once A's
landing + B's measured 21/192 blast radius made the bundle's risk profile clear; (5)
B's 3 mabda-external tcyr are fixed **at mabda's source** (optional-gate + re-fold),
not by tcyr restructure or `--allow-undef`.

**Open inputs (pin at slot entry, not blocking):** the v6.3.7 self_compile ceiling
number (current ~508 ms, 500–549 ms jitter band) and the expected v6.3.x patch count
(minor-window convention, for packing density).

---

## Open carry-in / DX hardening (ride bug-bandwidth)

Not pinned to a slot — these land on a bug-bandwidth line, fold into an
adjacent compiler change, or move on consumer pressure / explicit user
direction ([[feedback_no_unilateral_scope_decisions]]), not as standalone
releases.

- **DRY the four pass-1/pass-2 top-level scanners** (`main.cyr`,
  `main_aarch64.cyr`, `main_aarch64_macho.cyr`, `main_x86_macho.cyr`). The
  v6.2.2 `unexpected enum` fix was the **3rd instance** of a new top-level
  token landing on only one fork's scanner (v5.8.20 `#io`, v6.2.2 `#pure`).
  Each fork hand-maintains a parallel pass-1 pre-scan + pass-2 parse loop; a
  7th annotation token, or any new top-level construct, will desync again.
  Extract the token-dispatch into a shared `common/`-hosted helper (mirror the
  v6.1.4/.5 `_emit_fmt`/DCE hoist pattern). Logic-preserving → byte-identical
  self-host on all 4 hosts is the gate. MEDIUM (DX / recurring-bug-class).
  See [[project_v622_annotation_fork_desync]].
- **Local-array byte-vs-slot convention decision.** Largely resolved by the
  v6.2.1 `var a: T[N]` slot spelling, but the *bare* `var a[N]` convention
  (local = N bytes, global = N slots) remains a latent footgun. Decide: lint
  the address-taken-per-slot idiom on a bare local array, or audit
  stdlib/consumers for remaining bare-array slot writes. MEDIUM (DX).
  [`issues/2026-06-25-bare-local-array-slot-write-lint.md`](issues/2026-06-25-bare-local-array-slot-write-lint.md).
- **Permanent syscall-write byte-length gate** — the `.39` audit missed a
  multi-line syscall (single-line regex); make the byte-length check a
  standing gate using DOTALL.
  [`issues/2026-06-25-syscall-write-byte-length-gate.md`](issues/2026-06-25-syscall-write-byte-length-gate.md).
- **Opt-in bounds-checked `store*` / `load*`** (added 2026-06-22 from a
  downstream report). An OFF-by-default `CYRIUS_BOUNDS=1` / `#bounds` sanitizer
  that guards each raw `store*`/`load*` against the heap-map live regions and
  aborts `_vec_die`-style instead of corrupting silently. Design + open
  questions in [roadmap_6.md § "Opt-in bounds-checked memory primitives"](roadmap_6.md).
- **x86-macOS usable-toolchain arc tail.** Phase 1 (argv prologue) shipped
  v6.1.30; remaining `ach`-gated layers: env reading (`HOME`/uname), wrapper
  macOS arch-default, cycc-finding, the layer-6 native self-compile miscompile
  (tools ship cross-built until fixed), packaging. `ach` is the supported
  macOS-x86 verify host.
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated; lands when cyim updates
  + re-tests against v6.x.

---

## Deep-dive hardening spread (rides v6.3.x+ bug-bandwidth)

From the 2026-06-10 deep-dive review
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)).
The urgent set landed across v6.1.x Phase-F (CVE-14…31, CO-02/03, AR-03) and
v6.2.x (CVE-20/21 trust-chain .30/.31 + seed→cybs→cycc derivation, CVE-29
thread-stack guard .44, CVE-32 modular-resolver closeout .51). The remainder
spreads here and to later minors per "urgent now, rest spread":

- **Monomorphization substrate** (AR-01 / CO-01) — **v6.3.x Phase 0** (the
  growable-tables half, AR-02, already landed v6.2.0 / v6.3.0).
- **Verification coverage** (VR-01…04) — VR-01/02 shipped v6.2.29; VR-03
  differential corpus gates v6.4.x; the rest as surfaced.
- **v7 readiness gates** (LEGAL-01 licensing, diagnostics) — tracked for the
  v7 cut.

Audit cadence + the CVE-09…13 re-file tail:
[overdue-security-audit-cve-tail](issues/2026-06-10-overdue-security-audit-cve-tail.md)
— this deep-dive IS the overdue full audit.
