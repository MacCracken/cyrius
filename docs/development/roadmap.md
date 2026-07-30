# Cyrius Development Roadmap — v6.5.x (active minor)

**Scope** — the **current active minor only** (v6.5.x). This is the slot-pinning working
artifact: the committed slot sequence, the reactive windows, and a code-grounded size for
each arc. The whole-cycle framing plus v6.6.x/v6.7.x/v6.8.x live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slot sequence) → [roadmap_6.md](roadmap_6.md)
> (v6.6.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: v6.6.x
  language-ergonomics (const-eval, the bounds-check mode, trait-bounded generics),
  v6.7.x/v6.8.x RISC-V rv64, and the cycle-level budgeting reference points.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger** (the doc you open, run, and log against).
- [state.md](state.md) — volatile current state (version, cycc size, in-flight slot). Refreshed
  every release by `version-bump.sh`.
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.5.2** (2026-07-29) — cycc **1,129,272 B** · check.sh **150 passed / 0
failed** · self_compile **638 ms** · **253** `.tcyr` (31 `vr01_`) · **99** `lib/*.cyr` ·
api-surface **4,761** public fns · heap map **100 regions / 0 overlaps** (unchanged across
6.5.0–.2 — the visibility file-id substrate is a lazy `alloc`, the `_fnt_tparams`/`_vsgn_base`
precedent, not a new fixed band) · **16 open issues + 2 open proposals** (276 archived issues / 27 archived proposals). The visibility proposal was found marked `✅ SHIPPED in v6.5.0` while still sitting in the open `proposals/` dir and was archived on 2026-07-29 — a shipped-but-open item is the exact rot this sweep exists to remove, so it is called out rather than quietly corrected.
`scripts/release-gate.sh` **GREEN on all four hosts** — **ecb** (macOS-arm64), **ach**
(Intel-Mac x86-Mach-O), **cass** (Windows/PE), **pi** (aarch64), real hardware, sequential.

> `_doc_stamp_currency_gate` (check.sh, since v6.4.81) keys on the `Current head:` anchor that
> opens this paragraph and checks that `VERSION` appears within 240 bytes of it. It **fails
> loudly if the anchor disappears** rather than passing on a missing one — keep the string,
> keep it unique, and keep the version next to it.

**v6.4.x CLOSED at v6.4.86.** The closeout band ran **.80 → .85**; `.85` is the
closeout-complete cut (the entry that states "v6.4.x is CLOSED"); `.86` is the post-closeout
sandhi 1.9.3 → 1.9.5 fold. Anything that says the minor closed at `.82` is wrong — `.82` was
the closeout *proper*, and `.83`/`.84` were both displaced by live bugs the closeout itself
found (an intrinsic could not flank a TERM-tier operator; `chan_try_send` plus a pre-existing
macOS channel `SIGSYS`). That displacement pattern is the reason Slot 12 below is a band and
not a single release.

### Shipped in v6.5.x — one line per release

- **v6.5.0** — **file-scoped `public`/`private` visibility**, the minor's opener: the per-fn
  origin-file-id substrate + the `#@file` preprocessor RESUME-marker repair (the map was
  silently wrong — `alloc.cyr`/`atomic.cyr` shared an id, `lex.cyr` split across two),
  `private`/`public` for **fns AND global vars**, hard-error enforcement through 13 resolution
  paths via one `_vis_check` (+ `_vis_check_var` inside `FINDVAR`), `private` excluded from
  `.dynstr` (STRSZ 24 → 14) with all three export walks unified on `_fn_exported`, api-surface
  made visibility-derived, `lib/regex.cyr` adopted (41 private / 11 public), and
  release-gate step 3 fixed to grade check.sh by `$?` rather than stdout. cycc 1,112,464 →
  1,124,968 B (+12,504, triaged growth tax).
- **v6.5.1** — **arity-aware overload-suffix dispatch, fixed compiler-side**: `_OV_ARITY_OK` +
  `_CALL_ARGC_PEEK`, the `PARSE_RETURN` tail-path divert (so `var r = f(s)` and `return f(s)`
  stop running *different functions*), wrong-arity warning → hard error; the
  `io_rdwr_agnos` gate moved CI-only → check.sh; folds bayan 1.3.0 / sakshi 2.4.7 /
  yantra 1.0.2 / sandhi 1.9.7 with 63 in-repo call-site migrations. Two stdlibs had renamed
  their own functions to escape the defect — one of those renames was a breaking public API
  change. cycc flat at 1,124,968 B.
- **v6.5.2** — **the `CYRIUS_IR=3` substrate, unblocked**: `ir_const_fold` erased the jump
  that followed a folded constant (`EJCC`/`EJMP0` were the only two x86 emitters recording
  their IR node *after* emitting bytes, so the NOP-fill span ran 5–6 bytes long and deleted
  the jump); `_read_env`'s single shared 256 B buffer made **every** IR diagnostic knob
  silently inert, which is why the filed bisection table showed five pass combinations sharing
  one hash — all five were the same no-op run. Plus the `_int` overload route gated on an
  explicit `: cstring` param, integer-literal-to-cstring now a hard error (`println(42)`
  previously compiled with no diagnostic and SIGSEGV'd), the `PARSE_RETURN` tail path **again**,
  `xrmdir` in `lib/io.cyr`, new gates `tests/ir3_fold_jump_span.sh` +
  `tests/folds_agnos_parity.sh`, and yukti 2.2.10 → 2.3.0 (six agnos ABI defects, including
  `sys_mount` fabricating `Ok()` for a filesystem that was never mounted). Corpus
  default-vs-IR=3 exit mismatches **35 → 8**. Bench 638 ms, retiring the 6.5.1 perf flag.
  cycc **1,129,272 B**.

### What "IR=3 self-hosts" actually means — state it precisely

Measured at 6.5.2, not quoted: `cat src/main.cyr | CYRIUS_IR=3 build/cycc` produces a
**1,182,520 B** compiler — **+53,248 B / +4.7 %** over the default build (1,129,272 B, which
is itself byte-identical to `build/cycc`), differing from byte 42. Pipe `src/main.cyr` through
*that* IR=3-built compiler and its output is **1,129,272 B, byte-identical to `build/cycc`**.

So the true and load-bearing claim is: **CYRIUS_IR=3 builds a compiler that reproduces
`build/cycc` byte-identically** — a semantics-preserving statement about the IR=3-built
compiler's *output*, not about its own bytes. That is what `tests/ir3_fold_jump_span.sh`
asserts and what it passes. Read it the loose way and you conclude IR=3 is byte-neutral, when
it currently makes the compiler **4.7 % larger** — which is a live data point for a minor whose
whole theme is generated-code quality, and one of the things Slot 3 has to explain.

---

> **PLACEMENT RULE (hard):** every technical / codegen / runtime / platform item lives in the
> **6.x line** or the **potential backlog** below — **NOTHING codegen-related is EVER pushed to
> 7.x**. 7.x is **language book + legal-for-public-release ONLY**. An item without a committed
> slot goes in the potential backlog (still 6.x-cycle work), never a far-future version. The
> far-future label is how real work stops being scheduled: DWARF and incremental compilation
> were both mis-parked there and corrected at the v6.4.82 closeout, and roadmap_6.md's closing
> paragraph still parks LSP/formatter/linter evolution + agnos-v2.0 alignment at 7.x — three
> more instances of the identical pattern, to be corrected in the roadmap_6.md pass.

---

## Carried over from v6.4.x — verified open at 6.5.2

Every status below was checked against live code, a live run, or `CHANGELOG.md` — never
against a roadmap or issue file's own assertion. **Items the sweep proved already shipped are
in the "explicitly not carried" list at the end of this section, so nobody re-files them.**

| Carried item | Verified status at 6.5.2 | Lands in |
|---|---|:-:|
| **DX diagnostics residual** — fail-fast inline `SYS_EXIT` parser sites + `_sync_skip` coalescing | **7 sites, not 25.** Classified all 11 `syscall(SYS_WRITE, 2, "error:", 6)` sites in `src/frontend/parse*.cyr`: 7 reach `SYS_EXIT` (`parse.cyr:809`, `:1355`; `parse_decl.cyr:324`, `:462`; `parse_expr.cyr:587`, `:695`; `parse_types.cyr:772`), 4 already `_had_error`-recover. The 18 lexer sites are pre-parse and fatal by design. Probe: 3 undefined vars in 3 statements → 1 error, exit 1. `_sync_skip` still coalesces 3 dense syntax errors into 1 report. | **Slot 1** |
| **Wrong LINE for the main source once any `include` is present** | Reproduced and **characterized further than filed**: reported line = actual line − (number of `include` directives preceding the token). Measured: 1 include + error on line 2 → `<source>:1`; 2 includes + error on line 3 → `<source>:1`; 1 include + error on line 6 → `<source>:5`; error *inside* the include → correct. Independent of include size, which kills the "FM_BUILD counts the expanded body" variant. Excerpt + caret are correct in every case — only the line path is wrong. | **Slot 1** |
| **NEW (found by this sweep)** — inverted sign test makes `assigning non-pointer to typed pointer` fire on every width/float-annotated local and **never** on a real typed-pointer local | `src/frontend/parse.cyr:1336-1337` gates on `lt > 0`, but in the local SLTYPE scheme **positive** means narrow width or a float tag (`F64_TYID`/`F32_TYID`) and **negative** (`0 - sid`) is the pointer-like case. Siblings use the other convention (`parse.cyr:1363` tests `vt < 0`; `parse_decl.cyr:2194` tests `pscale > 0`). Probes: `var x: i32 = 5; x = 6;` → bogus warning; `var x: f64 …; x += y;` → bogus warning; struct-typed local → **no** warning, i.e. the case the check exists for is unreachable. | **Slot 1** |
| **`ERR_MSG` hardcoded-length audit** — the never-done half of the v6.4.57 follow-on | v6.4.57 fixed the one filed site (`parse_fn.cyr:3732`, now 92 bytes == 92 passed, verified byte-exact). The archived issue's closing suggestion — audit every other `ERR_MSG`/`WARN` literal against its passed length — was never run. Same over-read class. | **Slot 1** (bite) |
| **Source-level version constant** (`CYRIUS_PKG_VERSION`) | `grep -rn PKG_VERSION src cbt lib scripts` → **0**. Nothing in the CHANGELOG. `src/version_str.cyr` is the *compiler's* own `--version` string, not a consumer-reachable constant. `proposals/2026-06-25-source-level-version-constant.md` is still open, pinned to "the next 6.4.x arc's closeout / an absorber band" — **that host minor closed at .86 without it**, so the pin lapsed. | **W1** (fold-in) |
| **Bare-metal deliverable #4 — forbidden-module check** | **Never built, and now invisible.** `grep -rn forbidden src/ cbt/` → one unrelated comment; `grep -rn 'host_only\|kernel_ok' src lib cbt` → 0. roadmap.md claimed the visibility arc would fold it in; v6.5.0 shipped complete with no mention of it. Its issue was bulk-renamed into `issues/archived/` on 2026-07-10 (commit `79bae42f`, an 8-file rename) **with no resolution banner** — archived unfixed. roadmap_6.md still lists it as bare-metal deliverable #4 *and* as an arc acceptance criterion. | **W2** (fold-in) — see open question 2 |
| **v6.4.15 closeout residuals D1/D2** — dead IR helpers + the speculative decoder CFG API | R2 (PE prologue) shipped v6.4.26. D1 still dead: `ir_lower_all`, `_ir_lower_node`, `ir_emit2`, `IR_BB_ID`, `IR_EDGE_FROM` are definition-only. **TRAP the file does not carry:** `ir_dce`/`ir_dead_store` are dead only as *thin uncapped wrappers* — `ir_dce_capped`/`ir_dead_store_capped` are **LIVE**, called from `src/main.cyr:2064`/`:2066`. A name-based delete sweep would take live passes with it. D2 still dead: `CLASSIFY_CF` (`decode.cyr:238`) / `CF_TARGET` (`:279`). | **Slot 3** (opening bite) |
| **`_cur_fn_ret_stash` disp↔local-index adjustment duplicated 19×** | **NOT a defect and there is no issue file** — state.md lists it as a "filed follow-on" that was never filed, and the *bug* shipped at v6.4.31. What is live is duplication: `grep -c '_cur_fn_ret_stash > 0) { disp' src/backend/x86/emit.cyr` → **19** copies of the same guard. Reframe as a one-helper (`_disp_adj`) consolidation, provable byte-identical. | **Slot 5** (bite) |
| **macOS-arm64 threading backend** | No `lib/thread_macos.cyr`; `grep -rn 'bsdthread\|__ulock' lib/` → comments only. **WIDER THAN FILED:** `lib/sync_macos.cyr:2` is a 2-state `atomic_cas` **spinlock** and its own header at `:9` records that a blocking lock is a separate follow-on — macOS concurrency is **two** gaps and the filing names one. VR-01 guards at `vr01_thread_spawn.tcyr:31/:46` and `vr01_sync_mutex.tcyr:41/:44` keep it from rotting silently. | **Slot 11** |
| **Release gate's cross-OS leg runs only the `vr01_` glob** | `scripts/release-gate.sh:110` runs `cross-os-selfhost.sh "$H" "vr01_"` inside `for H in ecb ach cass pi` at `:108`. **31** `vr01_` of **253** `.tcyr` ⇒ **222 unrun** on three of the four gated hosts, and the step prints no coverage statement, so the gate reads as authoritative when it is a subset. (Filed line/counts `:92-94`, 30/251/221 — all drifted.) | **W1** (fold-in) |
| **`cyrius distlib` has no all-profiles mode** | `cbt/commands.cyr:2131` `cmd_distlib(profile)` is single-profile; `cbt/cyrius.cyr:332-344` scans only `--modular`. Drift re-verified in the siblings **today**: `~/Repos/sankoch` declares 9 profiles, `ci.yml:91` loops **7** (zip, zipall missing); `~/Repos/sigil` declares 13, `ci.yml:173` loops **12** (argon2 missing). | **W1** (fold-in, **before** that window's re-vendors) |
| **Missing syscall wrappers — one pass** | chown family: `grep -rn 'chown\|CHOWN' lib/*.cyr` → agnos GPU-band **comments only**, zero wrappers across all six syscall peers. `fn sys_chdir` defined **nowhere**, yet called at `lib/regression.cyr:658` — a `cyrius deps`-shipped stdlib file that cannot compile for any consumer reaching `regression_exec_in_dir3`. `xmkdir` absent. `xsymlink`/`xreadlink`/`xlink` absent (agnos arities 4/4/4 vs POSIX 2/3/2). One member of the family — `xrmdir` — landed at 6.5.2 without the slot being opened. | **W1** |
| **IR substrate walls + the 8 residual IR=3 mismatches** | Wall 3 (correctness) CLOSED at 6.5.2. Walls 1+2 live: `ir_lower_all` (`src/common/ir.cyr:361`) has **zero callers** (only other mention is the how-to comment at `:37`); `IR_SENABLE(S,2)` is **never activated** — and only **2 of 7 forks** call `IR_SENABLE` at all (`main.cyr:1511`, `main_win.cyr:715`, both mode 1), so the record-only/re-emit path is unreachable on aarch64, both Mach-O forks, and cx; **23** `_IR_REC0(S, IR_RAW_EMIT)` sites on the x86 path (21 `x86/emit.cyr` + `parse.cyr:1101` + `parse_expr.cyr:1968`), 13 aarch64, 7 cx; `ir_build_edges` (`ir.cyr:1388-1455`) special-cases `IR_JMP`/`IR_JMP_BACK`/`IR_JCC` only, so **`IR_SWITCH` gets exactly one fall-through edge** despite being a listed terminator at `ir.cyr:1157`. | **Slot 3** |
| **SIMD register residency** | `EMIT_F64V_LOOP` (`src/backend/x86/float.cyr:152`) is still memory → xmm → op → memory, `rsi += 2`, **no AVX branch**; there is no value-form f64v arithmetic emitter at all (only `EMIT_F64V_{LOOP,UNARY,DOT,SCALE,AXPY,FMADD}`, all memory-loop). `lib/simd.cyr`'s **value-form** wrappers still round-trip through it — **25** sites (`grep -c "(&r, &a, &b" lib/simd.cyr`): f64v2 `:519 :526 :533 :540 :548`, f64v4 `:592 :599 :606 :613 :620`, f32v4 `:667 :674 :681 :688`, plus the int-vec one-liners from `:709`. The **33 `_ptr`-form** round-trips (`:63` `:77` `:152` `:166`, … — all inside `f64v2_add_ptr`/`_mul_ptr`/`f64v4_add_ptr`/`_mul_ptr`) **stay memory-loop by design**, per roadmap_6.md item 3: *the memory-loop kernels stay for the `_ptr`/bulk forms*. Editing those is the wrong set and measures no consumer win. f32/f32v8 **did** widen to ymm during 6.4.x; f64v4 did not. | **Slot 6** |
| **Stackless coroutines / mid-body suspend across `await`** | Untouched by 6.5.0/.1/.2. `await` lowers to a `future_force` call (`parse_expr.cyr:1701-1706`) and `future_force` (`lib/async.cyr:994`) is a straight `fncall0..N` on the stored fn pointer — deferred-then-forced, run-to-completion, **no CPS transform and no force-once memoization**. Pin live at `roadmap-future.md` ("▲ PINNED v6.5.x", user 2026-07-26). | **Slot 8** |
| **Async single-waiter-per-fd multiplex** | `_async_wait_events` (`lib/async.cyr:240-275`) stores the task pointer **into the epoll `data` slot** and then calls `EPOLL_CTL_ADD` unconditionally — the data slot *is* the waiter identity, so two tasks parking one fd hit `EEXIST` and one starves. Currently double-tracked (roadmap-future watching row **and** this file's potential backlog). | **Slot 8** (bite — resolve the double-tracking there) |

### v6.5.0 arc residuals — the visibility arc shipped, three sub-commitments did not

The feature is genuinely complete and in use; the row is retired from the slot sequence. But
the arc's own published phase list made three promises that did not land, and closing the row
without naming them would be a silent subset:

1. **Feed DCE** — phase (4) was "flip to hard-error **+ feed DCE** (file-private with no
   in-file caller is *definitively* dead) + prove the win". The hard-error flip and the
   export-table half shipped; the DCE feed did not:
   `grep -rn '_vis_check\|_fn_exported\|_fnt_vis\|fileid' src/ | grep -i 'dce\|live\['` → **0
   hits**. `_fn_exported` gates `.dynsym` count/emit and GNU hash only; nothing consults
   visibility when computing reachability. This is the only part of the arc with a measurable
   size/perf payoff, which makes it a natural fit for a performance-quality minor. → **Slot 3**
   (bite, adjacent to the D1 dead-code sweep; the `_fnt_fileid` + visibility-bit substrate is
   already shipped and gate-proven).
2. **Per-item `private` in an otherwise-public file** — design point 3 in both the proposal and
   the old roadmap promises "unless an item is individually declared private". Not implemented:
   `_TL_VIS` (`src/frontend/parse.cyr:222-234`) handles token 153 by calling
   `_PRIV_MARK(FM_FILEID(...))`, a **FILE-level flip**, with an in-source comment explaining
   that a running per-item flag was deliberately rejected because it would leak into later
   includes. Consequence, compiled through `build/cycc`: `private fn h(): i64 { return 7; }
   fn main(): i64 { return h(); }` exits 0 with **no diagnostic** and the whole file — including
   `main` — is now private. The promised syntax parses and does something much broader than the
   author asked. → **open question 3** (implement the bit, or make it a diagnostic and strike
   the clause from both documents; leaving it silently mis-parsing is the one outcome to avoid).
3. **Adoption** — phase (3) "per-file adoption where it pays" is 1 file of 99
   (`grep -rln '^private$' lib/ src/ cbt/ programs/ tests/` → `lib/regex.cyr` +
   `tests/visibility_private.sh` only). → rides the reactive windows a file at a time; not a slot.

### Explicitly NOT carried — proved shipped, do not re-file

- The three v6.4.57 scalar-float follow-ons: **param arithmetic + compound-assign** (probe:
  `inc(4.0)` on `fn inc(x: f64): f64 { return x + f64_from(1); }` exits 5; f64 and f32 `x += y`
  both exit 7), **`ERR_MSG` return-type over-read** (the one site; the *audit* is carried above),
  and the **f64/int compare-mix warning with literal-0 suppression** (probes: `x > 0` silent,
  `x > 5` warns, `x > y` warns — the filed acceptance verbatim). All three shipped two days
  after filing and all three issue files are archived with RESOLVED headers; the old tail-table
  row carried them as live `(P2)/(P3)` for 29 more releases and a full closeout.
- **SIMD + cx arc finish-out** (.53/.54/.58), **Intel-Mac revival** (.59, with `ach` now a
  first-class gate host), **`2026-07-02-ir3-fixpoint-cascade-overelimination`** (RESOLVED at
  6.5.2 and archived — *and its filed diagnosis was wrong*: there was no cascade,
  `ir_const_fold` alone miscompiled), **undefined-fn reachable-call hard error** (probe:
  `error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to
  downgrade)`, rc=1), **`[features]`/optional deps** (v6.3.1), **bare-metal #5/#6** (v6.3.3) and
  **#7** (v6.3.4), **`defer`** (v3.8.0 — residual is only that it is fn-scoped, not
  block-scoped), **per-block scoping + shadowing** (v3.7.4 era — residual is only that
  same-scope redecl is a deliberate hard error).
- **aarch64 native 256-bit `EMIT_F32V8_*`** (`src/backend/aarch64/emit.cyr:2639-2641`, three
  `return 0`) are **intentional and unreachable** — aarch64 has no 256-bit register and
  `lib/simd.cyr` routes f32v8 through 2×128 NEON. Not an item. The only open question is
  whether the closeout dead-code pass deletes them or documents them; recorded in the backlog
  so it stops being re-litigated every closeout.

---

## The slot sequence

**The ORDER is the committed part.** Release numbers are **indicative bands** — they shift as
repair tails land, and the reactive windows are anchored to *arc boundaries*, not to absolute
numbers. Sizes are `.NN` releases, each bundling several bites. **Arcs are 1–2 releases with
phases landing as commits inside them** — not one release per phase. Minors flex long; 6.4.x
ran 86 releases and 6.5.x is expected in the same class.

| # | Indicative | Slot | Contains (phases = internal commits) | Absorbs |
|:-:|:-:|---|---|---|
| **1** | **.3** | **Diagnostics finish-out** | (a) the include-line delta; (b) the 7 fail-fast `SYS_EXIT` parser sites → `_had_error` + `_panic` + return; (c) `_sync_skip` statement-start-keyword resync; (d) the inverted-sign typed-pointer warning; (e) the `ERR_MSG` hardcoded-length audit sweep | `2026-07-28-main-source-diagnostic-line-wrong-after-an-include`, `2026-07-12-dx-multi-error-reporting` |
| **2** | **.4–.8** | **▣ W1 — reactive window #1** (5) | Known drain queue (~3 releases) + ~2 reserve. See the window block below. | `2026-07-29-no-portable-xmkdir-in-io-cyr` **[UNVETTED]**, `2026-07-26-no-lchown-wrapper…`, `2026-07-29-fmt-int-buf-i64-min` **[UNVETTED]**, `2026-07-29-mutex-unlock-unconditional-futex-wake` **[UNVETTED]**, `2026-07-28-agnosai-no-nlogn-sort-in-stdlib`, `2026-07-26-agora-fs-dir-list-per-call-alloc`, `2026-07-26-distlib-has-no-all-profiles-mode`, `2026-07-14-release-gate-cross-os-runs-only-vr01-glob`, `proposals/2026-06-25-source-level-version-constant` |
| **3** | **.9–.10** | **IR substrate productionization** (2) — **the perf anchor** | Opening bite: D1/D2 dead-code removal + record the new `note: N unreachable fns` floor. Then Wall 2 (local-access opcode model; `IR_SWITCH` + unresolved-edge CFG completion). Then Wall 1 (`ir_lower_all` mode-2 activation, proven byte-identical on `differential.sh`). Then a `CYRIUS_IR=3` axis added to `differential.sh` and the 8 residual mismatches closed with it. Plus the visibility→DCE feed. | `2026-07-02-ir-regalloc-rewrite-needs-reemit` (Walls 1+2), `2026-07-07-v6415-closeout-residuals` (D1/D2) |
| **4** | **.11–.13** | **▣ W2 — reactive window #2** (3) | At the substrate/regalloc seam. Mostly reserve. Named fold-ins: bare-metal forbidden-module check; the two cyrlint gates; visibility adoption files. | — |
| **5** | **.14–.15** | **Cross-BB regalloc with a vector register class** (2) | The vector class is planned in **from the start, not retrofitted** — standing decision from roadmap_6.md. Copy-propagation and cross-BB DSE land as bites inside (both proven inert-if-sound / miscompiling-if-not on the raw substrate at v6.3.28). Plus the `_cur_fn_ret_stash` 19-site `_disp_adj` consolidation. | (downstream half of `…ir-regalloc-rewrite-needs-reemit`) |
| **6** | **.16–.17** | **SIMD register residency** (2) — the substrate's payoff | Register-resident value-form f64v arithmetic; wrapper inlining so `f64v_add(&r, a, b, 2)` stops round-tripping through memory; f64v4 widened to `vmulpd`/`vaddpd` **ymm** under `simd_has_avx2()`. Scope = fix-list items 1–3 only. | `2026-07-06-simd-f64v-memory-operand-no-register-residency` |
| **7** | **.18–.22** | **▣ W3 — reactive window #3** (5) | The burst-risk window. See the window block below. | (reserve; `sock_accept`#57 VFS-fd bridge is the named candidate) |
| **8** | **.23–.24** | **Stackless coroutines / mid-body suspend-resume across `await`** (2) | CPS transform + poll-runtime rework + force-once memoization as bites. Folds in the async **single-waiter-per-fd multiplex** (the same `_async_wait_events` rewrite) and the shipped async arc's "gap 6". Acceptance = stiva's `exec -it` TTY relay + a true multiplexed streaming server. | `2026-07-25-stiva-stackless-coroutines-interactive-exec` — **stays OPEN as the acceptance record until this slot ships; do not archive it in a rot sweep** |
| **9** | **.25–.26** | **Sum-type variant unboxing** (2) — *retitle at pin time* | Filed as "`sock_send` allocates"; it is the compiler's variant **lowering**. Fix option 1 only: unbox the scalar case (tag + i64 payload in a register pair, no allocation). Options 2/3 are traps — arena variants push the cost onto every consumer; a singleton silently breaks any caller storing a `Result` past the next call. **Full ecosystem ABI cross-walk at arc-open, one coordinated filing, not drip.** | `2026-07-28-sock-send-result-allocates-per-call` |
| **10** | **.27–.30** | **▣ W4 — reactive window #4** (4) | Feeds the closeout — a drained queue going in, so the closeout's re-triage doesn't displace releases. | (reserve) |
| **11** | **.31** | **macOS-arm64 concurrency** (1) — last in the minor | **Both** gaps in one release: `lib/thread_macos.cyr` driving `bsdthread_create` + `bsdthread_register` (mirroring the `thread_win.cyr` split) for `thread_create`/`thread_join`, **and** `__ulock_wait`/`__ulock_wake` replacing `sync_macos.cyr`'s spinlock for the mutex + channel wait/wake. Acceptance = un-guard the four VR-01 assertions and get the full worker/counter/channel checks green on **real ecb** — not a hello-world smoke. | `2026-07-03-macos-threading-workers-dont-run` |
| **12** | **.32+** | **Closeout band** | Not a single release. `release-gate.sh` mechanical gates, then the judgment passes (heap map, dead code, refactor, code review, cleanup), then security re-scan + downstream check, then doc sync + backlog re-triage. Run it per [cycle-discipline.md](cycle-discipline.md)'s runnable checklist and **record the run in the ledger**. | — |

**Totals**: ~12 releases of pinned arc work + ~17 of reactive window = **~29**, plus the
closeout band, in a minor expected to run 45–99. The remaining headroom is repair tails (the
6.4.x precedent says every codegen arc grows one) and whatever the user pivots to. **Only the
user pivots focus.**

### Why the sequence is ordered this way

- **Diagnostics first (Slot 1).** 6.5.0 shipped file-scoped `private`, so **every visibility
  error is cross-file by construction**, and both live private diagnostics
  (`parse_fn.cyr:1127`, `parse_types.cyr:772`) print through `_err_head` — which means the
  first thing a consumer adopting the new feature meets is a wrong line number. The bug is
  wrong on essentially every real program. Batching (a)–(e) means **one** negative-corpus run
  across ecb/ach/cass/pi, **one** `CYCC_FUZZ_ITERS=300 sh tests/cycc_parser_fuzz.sh`, and one
  seed-derive (the preprocessor is in cybs's path). Five of the seven `SYS_EXIT` sites are the
  same `undefined variable` diagnostic, and the recovering pattern is already established
  in-tree — the four error sites added by the 6.5.x arcs (`parse_fn.cyr:1043`, `:1127`,
  `:1604`, `parse_types.cyr:688`) were all written that way with comments explaining why.
- **W1 before the IR arc (Slot 2).** Landing it **before** the substrate arc means it cannot
  perturb the `CYRIUS_IR=3` differential baseline; landing it after adds noise to every
  default-vs-IR=3 comparison.
  **Two of its bites are NOT byte-identity-free, and the window must treat them that way.**
  cycc's *transitive* lib closure from `src/main.cyr` is **seven** files —
  `alloc`, `alloc_agnos`, `alloc_macos`, `alloc_windows`, `atomic`, `fnptr`, `vec` — because
  `lib/alloc.cyr:44` includes `lib/atomic.cyr` (and `:113/:117/:123` the platform allocators,
  `:380` `fnptr.cyr`). A one-level grep of `src/` reports only four and additionally reports
  `slice` and `syscalls_macos`, which appear in `src/` **only inside comments**
  (`parse_expr.cyr:516`, `backend/macho/emit.cyr:18`) and are not compiled into cycc at all.
  So: the `vec_sort_by` bite touches `lib/vec.cyr` **and** the three-state-mutex bite touches
  `lib/atomic.cyr` — both inside the closure. Each needs an explicit **self-host fixpoint AND
  seed-derive** confirmation, not just a corpus differential. New top-level fns in a
  cycc-included file are also precisely the shape that trips cybs's global/call-reference
  ceiling, which only seed-derive catches. This is the v6.4.1 lesson restated: *a lib fix is
  NOT automatically byte-identical when cycc includes it.*
- **IR substrate is Slot 3, not Slot 1.** Its blocking premise ("CYRIUS_IR=3 miscompiles real
  programs") died at 6.5.2 for a mundane reason, so it is now *unblocked work* rather than a
  blocked prerequisite — and everything downstream (regalloc, vector class, residency,
  copy-prop/DSE, the coroutine poll-runtime) unblocks the moment it lands. It goes as early as
  the queue allows, but not ahead of the byte-identity-free drain.
- **Regalloc + vector class as one arc (Slot 5).** roadmap_6.md's standing decision: *"the
  vector class is what lets SIMD values live in registers; planned in from the start, not
  retrofit."* Splitting the scalar and vector halves into separate rows is exactly what invites
  the retrofit. Copy-prop and cross-BB DSE are bites inside, not thin releases — and note the
  names `ir_copyprop_recon`/`ir_extdse_recon` that roadmap_6.md promises to "revive" **do not
  exist** (`grep` → 0 hits): both passes must be built, not revived.
- **Residency is the minor's acceptance anchor (Slot 6).** This is why the theme was reframed
  from self-compile growth tax to *generated-code quality*: consumer numeric code sits 10–38×
  behind its Rust baseline, and hand-SIMD gains ~5 % where LLVM gains 2–4×. The svara
  `process_block 1024` figure (186 µs vs Rust 4.84 µs at filing) is the number the minor is
  judged on.
- **Coroutines after the substrate (Slot 8).** Bound by design: the poll-runtime rework plus
  force-once memoization sit on the substrate Slot 3 builds. Running it earlier means building
  that substrate twice.
- **Sum-type unboxing late (Slot 9).** It is ABI-breaking across the ecosystem —
  `lib/result.cyr`'s own helpers and `lib/tagged.cyr` read the box directly with
  `load64(res)`/`load64(res+8)`, and downstream consumers do too — so it wants a stable
  compiler underneath it and a full cross-walk at arc-open. Ready-made acceptance exists:
  sandhi 1.9.6's `test_server_reject_arena_is_flat` currently asserts the delta over 600
  responses is exactly 600 × 16; the expected figure becomes **0**.
- **macOS concurrency last (Slot 11).** Real platform work with a real broken verb on a gate
  host, so it cannot be dropped — but it is the only pinned row with **no consumer waiting**,
  it mirrors an already-shipped split, and the VR-01 guards mean it cannot rot silently. See
  open question 4.

---

## Reactive windows — deliberately-unallocated capacity

**These are budget, not filler, and not slack to be raided when an arc runs long.** Agnos ABI
mirrors and consumer-filed repairs land as their own releases *between* arcs, following the
bare-metal open-window pattern. They are **not** counted inside the arc sizes above. The old
roadmap said reactive work was "not counted in the arc lengths", which in practice gave it no
budget at all — that is what these four windows fix.

**Measured baseline** (counted from `CHANGELOG.md`, per release touching
`lib/syscalls_x86_64_agnos.cyr`): 6.0.x **0.33** slots / 10 releases · 6.1.x **0.24** · 6.2.x
**1.32** · 6.3.x **0.65** · 6.4.x **1.40** (11 of the 12 were new syscall numbers; `.68` was an
ABI widen of existing `#13`). Broadening to all agnos-facing reactive work in 6.4.x → **~1.9 /
10 releases**. Over ~50 releases that is **~9–10 agnos-facing items, ~7 of them syscall/ABI-peer**.

**Unit cost is small; clustering is the real constraint.** 6.4.x's 11 new-number slots covered
32 numbers — modal size **2 wrappers**, median 2, mean 2.9, **every one fit in ONE release and
every one was cycc byte-identical** (the peer is `#ifdef CYRIUS_TARGET_AGNOS`-ed out of every
non-agnos build, so it sits outside cycc's include closure). Several rode along inside releases
doing unrelated work — `.70` carried `#84`/`#85` **plus** the gate-placebo fix **plus** two
folds; `.82` carried the entire closeout **plus** the TS arena fix **plus** `#94`/`#95`. But
`.63 → .73` was **6 agnos slots in 11 releases** (0.55/release) when agnos's GPU arc stood up
the ring-3 band `#82`–`#93`, while the other ~53 releases of the minor carried 2 slots. **Size
the windows for the bursts and for the gnarly-bug half** (6.4.74's `_cfo` re-arm, 6.4.80's
`1 - 2 + 3 == 5`, 6.4.81's fourth `_cfo` occurrence — each one release, each found by *running
the compiler* during unrelated work, each displacing a planned slot), and treat agnos wrapper
adds as the cheap ride-along. That is how 6.4.x actually absorbed them.

**Parity is currently FULL — there is no outstanding wrapper gap.** agnos is at 1.56.31; its
canonical dispatch (`grep -oE "num == [0-9]+" kernel/core/syscall.cyr`) is 0–43 + 45–95;
`lib/syscalls_x86_64_agnos.cyr` wraps all of those plus `#44` (`sched_yield`, which lives in
agnos's SYSCALL entry stub). Band contiguous `#82`–`#95`, asserted on both legs by
`scripts/agnos-crossbuild-gate.sh:354-391`, mutation-proven.

**And the biggest 6.4.x generator is closed by design.** agnos `planning/gpu.md:979`: *"**No
new syscall number.** D-3 already settled this … `#92 gpu_shader_op` takes an array of
**64-byte** records with the op code inside the record, and the op code IS its bit index in the
`#89 gpu_caps` support word at `+28`."* MD-4 re-minted `#93` on the same descriptor-array
shape. The ten remaining 1.56.x cuts (1.56.24–.33: bilinear, depth, persp-correct, pilot,
cold-modeset, HDMI audio, invalidate hoist) add **op codes, not numbers** — HDMI audio routes
through the existing snd band `#64`–`#69`. **Four windows, not five**, because that door is
shut; **four, not three**, because the arity-divergence class is live, the kriya symlink
un-gate is armed, and Slots 3/5/6 are a long mechanical stretch during which a consumer filing
would otherwise have nowhere to land.

### ▣ W1 — v6.5.4 → .8 (5 patches) · pre-IR-arc · drains the known queue

Known drain queue (~3 releases' worth; the rest is reserve). Six of the 16 open issues were
filed on 2026-07-28/29, and five are self-contained stdlib fixes with supplied patches — per
*an audit's output is fixes, not a backlog*, these are pack-into-a-release material, not
roadmap rows.

1. **Syscall-wrapper pass**, in this fixed internal order:
   (i) repoint `lib/yantra.cyr:453`'s bare-literal `syscall(54, fd, 6, 1, one, 4)` at
   `SYS_SETSOCKOPT` so the aarch64 `54 → 208` remap at `src/backend/aarch64/emit.cyr:840` has
   no consumer; (ii) **only then** claim aarch64-native `54` for `SYS_FCHOWNAT`;
   (iii) `fchownat` as the single wrapped primitive (x86 260 / aarch64 54; `AT_FDCWD` +
   `AT_SYMLINK_NOFOLLOW` gives `lchown` semantics) rather than the legacy trio — two of the
   agnos `92`–`95` band *terminate the caller* on ARM; (iv) explicit `-ENOSYS` agnos stubs,
   keeping the **FILE-level** `#ifdef` in `lib/syscalls.cyr` intact (do not weaken it to an
   in-fn check); (v) read the Darwin numbers off ecb/ach and add **both** the `EMACHO_SYSXLAT`
   `_msx()` entry and the aarch64 `_TARGET_MACHO == 2` cmp; (vi) `sys_chdir`;
   (vii) `xmkdir` + the `xrmdir`-shaped agnos bridge; (viii) `xmkdir_p` with Rust's
   `create_dir_all` ordering (full path first, walk parents only on `ENOENT` — the filing
   measured 43 µs → 6.0 µs); (ix) `xsymlink`/`xreadlink`/`xlink`; (x) fix `lib/yukti.cyr:1801`
   and `:5270` **upstream** in `~/Repos/yukti`, then re-vendor. One `vr01_`-named `.tcyr` so
   the cross-OS leg actually executes it on pi.
2. **`i64::MIN` formatter class — all 7 sites, not 1.** `n = 0 - n` is a no-op at `i64::MIN`,
   so both the `n == 0` and `while (n > 0)` arms are skipped and the output is a bare `-`.
   Sites: `lib/fmt.cyr:10` (`fmt_int`), `:25` (`fmt_int_fd`), `:41` (`efmt_int`), `:103`
   (`fmt_int_buf`), `lib/string.cyr:98` (`print_num`), `lib/log.cyr:137`, `lib/sakshi.cyr:415`
   (`_sk_fmt_int`). The `n > 0` → `n != 0` loop-condition change is the load-bearing part.
   **`lib/sakshi.cyr` is a FOLD** — patch `~/Repos/sakshi/src/format.cyr:40` → sakshi 2.4.8 →
   regen dist → re-vendor. Never patch the fold. Mind the snapshot-ping-pong rule for the
   `lib/` edits.
3. **Three-state mutex.** Prerequisite first: `lib/atomic.cyr` exposes only
   `atomic_load`/`atomic_store`/`atomic_cas` (returns 0/1 via `sete`, discarding the observed
   value)/`atomic_fetch_add`/`atomic_fence` — so add `atomic_swap` and a **value-returning**
   CAS (single instructions on both arches: `xchg` / `lock cmpxchg` already computes the old
   value into rax and simply does not return it; `swpal`/`casal` on aarch64). Then the
   canonical Drepper "Mutex, Take 3" — both flagged subtleties (re-acquire **as 2**, needing
   the pre-store value) are genuinely load-bearing. **Verify the new aarch64 asm on real pi,
   not qemu.** Blast radius is measured, not inferred: `lib/thread.cyr` calls `mutex_lock` at
   `:335`/`:411`/`:434`/`:459`/`:488`, so every `chan_send`/`chan_recv`/`chan_try_*` pays it.
4. **`vec_sort_by` + `vec_select_nth`.** ~55 lines, additive. Two hard constraints from the
   filing, both correct: name it **`vec_sort_by`, NOT bare `vec_sort`** — `itihas/src/util.cyr:57`
   already defines `vec_sort(v, cmp)` in the flat namespace and last-definition-wins would break
   it; and take the **hybrid** (merge/heap with an insertion cutoff ~16) so the O(n)
   nearly-sorted case consumers get today from hand-rolled insertion sorts is not lost.
   `vec_select_nth` = Hoare quickselect, median-of-3 (percentiles were the motivating case and
   never needed a full sort). Exclude `drishti/src/av1_mv.cyr:358` from any migration —
   AV1-spec-prescribed sort.
5. **`dir_list` — both halves in one release.** Cheap half: a file-scope 4 KB `getdents`
   scratch (`dir_list` is already non-re-entrant, holding one fd and one buffer — the v6.4.61
   lazy `Err(EAGAIN)` singleton precedent) + a shared `basep`, which takes agora's 1-entry case
   from ~5.3 KB to under 1 KB. Hard half: `dir_list_into` with caller-owned scratch + names +
   offsets, existing `dir_list` kept as a thin wrapper, and the same treatment threaded through
   `dir_list_full`/`dir_walk`/`find_files`/`_with_prunes` (`dir_walk` recurses, so it
   multiplies). Taking only the cheap half would be the sliced-fix antipattern.
6. **`distlib --all` + `--check` — BEFORE this window's re-vendors.** This window folds sakshi
   2.4.8 and yukti; without `--all` you re-run the exact N+1 ritual whose omission shipped
   sankoch 2.7.6's buggy gzip encoder under a 2.7.6 version string. `--all` enumerates
   `[lib.<name>]` from the manifest so the list cannot drift; `--check` regenerates to a temp
   location, diffs against the committed copy, exits non-zero on drift and **names** the
   offending bundles (the v6.4.78 lesson). `--check` must verify **content** — after any
   regeneration the version string matches whether or not the fix is in. Fix the sankoch
   zip/zipall and sigil argon2 CI lists in *those* repos in the same pass.
7. **Release-gate coverage, both halves in one bite** — print
   `cross-OS: vr01_ subset only (31 of 253) — CI runs the full corpus`, deriving both numbers
   from the globs so they cannot go stale, **and** run the FULL corpus on **pi** (cheapest
   aarch64, where per-arch numbering bites) while ecb/ach/cass keep the glob. Record the
   wall-clock delta in the CHANGELOG. Do not delete the filter. This belongs in the same
   release as the wrapper pass — per-arch syscall numbers on aarch64 and macOS are the exact
   failure class (v6.4.64 `fchmod`/`getpeername`) the blind spot let through.
8. **Fold-in:** `CYRIUS_PKG_VERSION` — option 1 of the proposal only: surface
   `[package].version` (which already resolves `${file:VERSION}`) as one injected
   source-visible cstring. No new manifest surface, explicitly **not** const-eval. Keep it
   distinct from `proposals/2026-07-05-const-eval-comptime` (v6.6.x).
9. **Fold-in:** extend `tests/folds_agnos_parity.sh`'s PREAMBLE until the SKIP list is empty —
   it currently reports 11 of 12 (`SKIP: niyama — undefined variable 'NFD'`), so one fold's
   agnos exposure is still unmeasured.

### ▣ W2 — v6.5.11 → .13 (3 patches) · at the substrate/regalloc seam

Deliberately the low end: this is **reserve, not a known queue** — W1 drains the queue, and the
one named forward agnos candidate (`lstat`, the last half of the old `readlink` pair, agnos:
*"slot when a consumer — kriya `ln -s`, or ark install layouts — demands it"*) shares its
trigger with W1's symlink work, so it may arrive here or not at all. Its purpose is to give a
consumer filing arriving during the long substrate stretch a landing slot ~3 releases out
instead of ~20. Named fold-ins if nothing arrives:

- **Bare-metal forbidden-module check** — a deny-list or `#host_only`/`#kernel_ok` annotation
  checked in the include resolver under `CYRIUS_KERNEL`, plus a **negative** fixture (a kernel
  program pulling `lib/fs.cyr` must error); `tests/fixtures/freestanding_tls/kernel_link.cyr`
  is the positive case. Directly relevant to agnos, the repo 6.4.x was held open for.
- **Two cyrlint gates, one bite** — the bare-local-array slot-write lint and the syscall-write
  byte-length gate. Both are byte-length-vs-declared-size static checks. The argument for
  acting rather than watching is the trajectory: `grep -rn "syscall(SYS_WRITE" --include='*.cyr' .`
  went **543** (filed) → 593 (.82) → **609** (6.5.2), i.e. the unguarded surface grows every
  release while the gate waits for consumer pressure that never comes for a lint. ~21
  intentional bare-local-array sites in-tree.
- **Visibility adoption**, a file or two at a time where it pays.

### ▣ W3 — v6.5.18 → .22 (5 patches) · post-residency · the burst-risk window

Sized at the top of the range because this is where the historical burst lands and where cyrius
is the **named blocker** on an agnos item. The next new-number pressure is agnos 1.57.x/1.6x —
"USB device classes and plug-and-play" (filed 2026-07-28, *"the gap is wider than hot-add"*) and
the ark M4/M5/M6 band (atomic system-update / boot-slot primitive, nested/recursive exec,
argv/env length-caps raise). Both of the most syscall-shaped items say a **design call is owed
first**, so this is sized as reserve against a possibility, not against a known plan (see open
question 6).

Named candidate: the **`sock_accept`#57 VFS-fd bridge**. agnos: *"Landed at 1.49.4, then
partially reverted at 1.53.9: `sock_accept`#57 returns the raw `conn_id` again, BECAUSE the
cyrius `net.cyr` treats the return value as a `conn_id`. Accepted sockets are therefore not
epoll-able."* That is the `sys_reboot`#13 pattern shipped at 6.4.68 — an **existing number
changing meaning**, which is the silent class: a new number fails loudly (undefined fn) or
hard-errors on arity since 6.5.1, but a widen is invisible on both sides. `net.cyr` churn is
also easier once the vector-residency work is stable, hence post-Slot-6 rather than mid.

### ▣ W4 — v6.5.27 → .30 (4 patches) · feeding the closeout

A window **in front of** the closeout so the closeout's backlog re-triage and doc sync reflect a
drained queue rather than discovering one and displacing releases — which is exactly what
happened in 6.4.x, where the closeout audit kept finding live bugs and `.80`, `.81`, `.83` and
`.84` were all displaced by it. Deliberately **not** a closeout slot: the closeout's judgment
passes are their own work, and a minor-close slot still has to carry real code deliverables.

### Two standing riders every window carries

1. **Mutation-prove the gate, in the same release as the wrapper.** v6.4.70 shipped
   *"the agnos GPU-band gate was a PLACEBO"* — `agnos-crossbuild-gate.sh`'s emit-inspect used
   `grep 'mov eax,0x52'`-style checks, and mutation proved `#84 → 99` still reported PASS. The
   band had been "gated" since `.63` with no real coverage. "Gated" without a mutation proof
   means ungated.
2. **Diff `agnos/docs/development/agnos-userland-abi.md` against
   `lib/syscalls_x86_64_agnos.cyr` once per window.** That doc is the designated frozen
   normative contract both sides code against, and it is the only cheap place to catch an ABI
   **widen** of an existing number — the failure class no compile-time check can see. Note it
   currently has **17 missing rows** (`#64`–`#69` snd and `#71`–`#81` shm/blk/readdir bands are
   dispatched by the kernel and wrapped by cyrius but have no row), and
   `agnos/docs/development/syscall-additions.md`'s header is ~35 syscalls behind
   ("through v1.45.x — surface is now 0–60"). **Both are agnos-repo docs — surface the gap to
   the agnos agent; cyrius does not edit them.**

---

## Standing notes — traps this minor must not re-learn

- **The `PARSE_RETURN` tail path has now skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each was fixed with the same narrow divert. That is the
  `_cfo` escalation shape — *"declared fixed, fourth occurrence in a path nobody enumerated"*.
  **Any new `PARSE_FNCALL`-resident transformation must be grepped against the tail path before
  it ships** — grep the SHAPE, not the operator.
- **A 0/253 codegen differential is not evidence a fix is inert — it is evidence of a corpus
  blind spot.** Three consecutive releases now: 6.5.0 was 0/253, 6.5.1's arity fix 0/253,
  6.5.2 0/253 — each a real wrong-answer-or-crash fix. Same finding as v6.4.80's 251/251. When
  a fix measures 0 diffs, add the shape to the corpus in the same release.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9
  minors behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. `ach` became a
  first-class gate host at v6.4.59 after the Intel-Mac toolchain rotted ungated for ~2.5
  minors. Run the compiler on the hardware.
- **Every one of the 16 open issue files still carries a "re-verified against live code at the
  v6.4.82 closeout" header.** That is three minors of releases stale, and it is exactly how the
  xmkdir filing came to re-assert `xrmdir` as missing **two days after 6.5.2 shipped it**. The
  header pattern is load-bearing — it is what makes a file trustworthy at a glance — so the
  re-verification stamp must move with each sweep or it becomes the rot it was designed to
  prevent.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.**
  The retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got
  cited to file against *sigil*. This is the language repo: when the compiler cannot compile
  valid cyrius, fix the compiler. Premise-check **rules**, not just pins.

### UNVETTED filings

Three open issues were authored by subagents and have **not** been reviewed by the maintainer.
They are marked **[UNVETTED]** wherever they appear above. All three were reproduced by running
code or a bench at 6.5.2 and all three describe **real** defects — but treat their evidence, not
their conclusions, as suspect:

- **`2026-07-29-no-portable-xmkdir-in-io-cyr`** — two false claims. It says the `x*` set has no
  `xrmdir` (it does — `lib/io.cyr:134`, shipped 6.5.2, with a CHANGELOG heading of its own) and
  that *"`lib/kavach.cyr` calls the unguarded form at eight sites"* — **`lib/kavach.cyr` does
  not exist in this repo**; the live raw callers are `lib/yukti.cyr:1801` and `:5270`, two
  sites, `sys_mkdir(cstr, 493)`. It also never makes its own sharpest argument: **`mkdir` is
  the one member of the family whose ARITY MATCHES** (2 args on every target — `(path, mode)`
  vs agnos's `(path, pathlen)`), which is precisely why 6.5.1's arity escalation is
  structurally blind to it and `folds_agnos_parity.sh` passes without catching it. It is the
  **last remaining member of the arity-identical-but-semantically-divergent class**.
- **`2026-07-29-fmt-int-buf-i64-min`** — no false claims; **understated**. It asks whether other
  formatters share the shape. They do: 7 sites, not 1.
- **`2026-07-29-mutex-unlock-unconditional-futex-wake`** — no false claims; one number not
  reproducible from the attached repro. Its `chan_try_send + chan_try_recv = 1.590 µs` row does
  not come out of the committed `.bcyr` (that harness emits only `nop_loop`/`alloc_16`/
  `atomic_cas_hit`/`mutex_lock_unlock`; measured 1 / 10 / 6 / 382 ns). The `.bcyr` header is
  honest about it; the issue body presents the row in the same measured table. The mechanism is
  independently verified via the `thread.cyr` call sites, so it is understated, not wrong.

**Read this as a signal about how subagent-authored filings fail: the conclusion survives, the
evidence does not.** Re-derive every line reference and count before acting on one.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks
  (`main`, `main_aarch64`, `main_aarch64_macho`, `main_aarch64_native`, `main_cx`, `main_win`,
  `main_x86_macho`); no shared pass-1 dispatch helper. This is a recurring-bug class, not
  cosmetics: `#io` v5.8.20, `#pure` v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute
  needed return-0 stubs in aarch64 + cx and only `cass`'s `cycc_cx` caught the miss.
  Logic-preserving ⇒ gate is byte-identical self-host on all four hosts + seed-derive.
  Premise-check the fork count at slot entry.
- **DWARF debug-info emission** — backend/codegen work; it emits debug sections into the object
  file. Slot it when a real debugger story is needed. Distinct from the DX diagnostics arc,
  which was only the error-reporting layer.
- **Incremental compilation** — compiler work. Unpin condition: reconsider when cycc self-host
  crosses ~2 s. It is **638 ms at 6.5.2** after 90+ releases, so the whole-program model is
  nowhere near the threshold. The reporting obligation is live: **every 6.5.x release's
  mandatory bench run IS the report.**
- **Bare `var a[N]` byte-vs-slot convention** — a user design decision, not an arc. The typed
  spelling `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is
  whether to lint the address-taken bare-local per-slot idiom or audit stdlib/consumers.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot) — live count is
  **19** FREED regions in `src/main.cyr` at 6.5.2, roughly twice what roadmap-future.md
  enumerates. Policy: the next new compiler-state scalar goes into a hole rather than growing
  the band. Cite the live count and the heap map; do not maintain an enumerated list that goes
  stale every minor.
- **aarch64 `EMIT_F32V8_*` unreachable stubs** (`src/backend/aarch64/emit.cyr:2639-2641`) — the
  verb works via 2×128 NEON and there is no correctness gap, but three never-reached functions
  are what the closeout dead-code audit exists to find. Decide once: delete them, or leave one
  comment saying why they exist. Recorded here so the next closeout does not re-litigate it.
- **`ir_dce`/`ir_dead_store` uncapped wrappers and `CLASSIFY_CF`/`CF_TARGET`** — decide
  wire-or-delete inside Slot 3's opening bite; leaving a third option open is how they survived
  two closeouts.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term". Kept out of Slot 6 deliberately: folding it in would
  inflate a bounded residency slot into an open-ended arc.

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

The one genuine 7.x technical-adjacent item is **LEGAL-01**: cyrius is GPL-3.0-only and the
stdlib — including folded sigil, whose `sigil.cyr:533` elects the GPLv2-only leg of dual
BSD/GPLv2 code, and GPLv2-only is GPL-3-incompatible — is source-included into every consumer
binary at build time. That needs legal review plus an RLE-style linking-exception decision. It
compiles nothing and emits nothing; licensing sign-off is exactly what 7.x is for. The other
7.x item is `docs/stdlib-reference.md` authoring (currently "roughly 65 of 99" modules). Note
that "an installer aimed at strangers" is **not** a 7.x deliverable — `install.sh` exists and
ships today; that is 6.x tooling.

---

## Open questions — owed to the maintainer

Six decisions this document deliberately does **not** make. Rows above reference these by
number. Nothing here blocks starting Slot 1; items 1 and 5 are owed by Slot 3 entry.

1. **The self_compile budget — half of the committed acceptance anchor is unstated.**
   roadmap_6.md's anchor has two clauses: the svara formant bench closing to single-digit-× of
   the Rust baseline, **and** *"self_compile stays inside a stated budget"*. The svara figure is
   carried above; the budget is not, and the whole point of a *stated* budget is that it is
   stated before the arcs land rather than reconstructed after. Verified baseline to set it
   against: **638 ms · 1,129,272 B** at 6.5.2. A defensible pair is *≤ 700 ms and ≤ 1.20 MB at
   minor close* — but the number is the maintainer's, not mine.
   **Note the live counter-pressure:** an IR=3-built cycc is currently **+4.7 % larger**
   (1,182,520 B), so if IR=3 ever becomes the default path the size half of any budget is
   already under strain.

2. **Bare-metal deliverable #4 — the forbidden-module check.** Never built; its issue was
   bulk-renamed into `issues/archived/` on 2026-07-10 (`79bae42f`, an 8-file rename) with **no
   resolution banner**, i.e. archived unfixed, while roadmap_6.md still lists it as a
   deliverable *and* an arc acceptance criterion. Either implement it in W2, or strike it from
   roadmap_6.md's acceptance list and say why. Leaving a never-built item as a shipped-arc
   acceptance criterion is the rot pattern.

3. **Per-item `private` — the promised syntax parses and does something much broader.**
   `_TL_VIS` (`src/frontend/parse.cyr:222-234`) handles token 153 by calling
   `_PRIV_MARK(FM_FILEID(...))` — a **FILE-level** flip — with an in-source comment recording
   that a per-item running flag was deliberately rejected because it would leak into later
   includes. So `private fn h(): i64 { … }` compiles with **no diagnostic** and privatises the
   *entire file*, `main` included. Three options: implement the per-item bit; make the per-item
   form a hard error pointing at the file-level declaration; or keep it and document the
   widening. Silently mis-parsing is the one outcome to rule out.

4. **macOS concurrency ordering (Slot 11).** Real platform work with a genuinely broken verb on
   a gate host, so it cannot be dropped — but it is the only pinned row with **no consumer
   waiting**, it mirrors an already-shipped split (`thread_win`), and the VR-01 guards mean it
   cannot rot silently. Keep it last, or pull it forward if a consumer appears?

5. **v6.5.x committed item 5 — the self-compile growth-tax audit — has no slot.**
   roadmap_6.md:1323-1369 commits v6.5.x to items **1–5** and its pull-forward note says
   v6.5.x carries *"the FULL shape, items 1–5, not just the substrate half."* Items 1–4 map to
   Slots 3/5/6. Item 5 does not appear in any slot, bite, or backlog row, and this document
   elsewhere reframes the minor's theme from self-compile growth tax to generated-code quality —
   which contradicts that note. All three prerequisites are shipped and verified
   (`scripts/bench-history.sh:174-181` runs `CYRIUS_PROF=1`; `lib/alloc.cyr:65/:85` carry the
   `_threads_active` single-threaded fast path; `2026-06-10-runtime-bench-suite-blind` is
   archived), so nothing blocks it. Either give it a named bite — a phase-resolved self_compile
   audit read off `bench-history.csv` + `CYRIUS_PROF`, in Slot 3 (shares the substrate) or W4
   (feeds the closeout) — or record here that it was retired, and why. **Do not let it vanish:
   silently dropping a user-committed item is exactly what this sweep exists to stop.**

6. **W3 sizing.** W3 is set at 5 patches on the assumption that the residency + coroutine arcs
   generate the minor's biggest consumer-facing behaviour change and therefore its biggest
   filing burst. If the agnos cadence in W1/W2 comes in lighter than the measured 6.4.x rate,
   W3 is the window to shrink first.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

**Premise-check each arc at slot entry** — empirically test that the gap still exists, against
the UPSTREAM repo source (`~/Repos/<dep>/src`), never the vendored `lib/` copy. This sweep is
the live example: three of the six rows in the previous v6.5.x table were describing work that
had already shipped or a blocker that had already died.

**`sh scripts/release-gate.sh` GREEN before EVERY `.NN` tag** — self-host fixpoint, **seed
derive** (`seed → cybs → cycc`; mandatory for ANY `src/` change, EVERY release — the cycc
fixpoint does not cover it, and cybs fails **silently** on things `build/cycc` compiles fine),
check.sh, cross-OS on ecb/ach/cass/pi (**real hardware, one host at a time** — fixed `/tmp` and
remote paths clobber under concurrency), bench. **Never tag with the gate RED.**

**Benchmark EVERY release** — `sh scripts/bench-history.sh` on a quiet box, before
`version-bump.sh`, with the headline delta (self_compile ms + cycc size) recorded in the
CHANGELOG. A perf delta is growth-tax by default; bisect only if one patch dominates. And a
byte-identical binary **cannot** regress — check the sha before triaging perf.

**One bug ships complete.** However nasty a bug turns out to be, fix it fully in one release.
Never slice one fix so the hard half defers. **An audit's output is fixes, not a backlog** —
file only when the fix genuinely cannot pack into the patch (a heap/brk **layout** change ⇒
two-step bootstrap, a design decision that is the user's, cross-repo coordination, or a full
gate cycle the release cannot absorb) and **name the reason**.

**When stuck, ASK.** Never decide to defer, slip, re-slot, or split mid-execution. Splits are
planned decisions made *before* starting. **Only the user pivots focus** — surface findings;
never unilaterally redirect. Deferral is real only when FILED with a roadmap slot and acceptance
criteria, and once documented-and-deferred, move on.

**Fix the SOURCE repo, not the fold.** sigil/sakshi/bayan/sandhi/yukti/… are the language's OWN
stdlibs — a fix applied only to the vendored `lib/<dep>.cyr` evaporates at the next re-vendor.
Patch upstream, version-bump, regen **all** distlib profiles, re-vendor. And mind the
snapshot-ping-pong loop when editing anything in `lib/`.
