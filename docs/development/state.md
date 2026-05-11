# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.

## Version

**5.11.4** (shipped 2026-05-11 — **Stdlib annotation arc Phase 4:
collection libraries**). 127 public fns across 2 modules
(hashmap 41, json 86) — heavier than the roadmap's ~89 estimate.
All `: i64` (map ptrs / counts / tagged json values). cc5
byte-identical at 804,472 B. **check.sh 66/66**;
**cyrius test 146/146**. Arc total: 374 → **501** annotated
(~50 % — halfway). **v5.11.20 pinned**: kybernet
`fn_table`+`identifier buffer` cap raise (filed 2026-05-11; lands
first slot in buffer band after annotation arc).

**5.11.3** (shipped 2026-05-11 — **Stdlib annotation arc Phase 3:
string/format completion**). 85 public fns added across 5 modules
(string +7, str +16, bigint +24, chrono +19, bench +19) closing
the string-handling band. cc5 byte-identical at 804,472 B.
**check.sh 66/66**; **cyrius test 146/146**.

**Phase 3 modules + counts**: string 16/16, str 70/70, bigint 24/24,
chrono 19/19, bench 19/19. **Coverage delta**: 289 → **374**
annotated; stdlib gap → **~743** unannotated (~37 % arc progress).

**Mid-slot recovery**: snapshot-ping-pong wipe triggered when
`cyrius test` ran against a stale `~/.cyrius/lib` symlink (agnosys
agent had switched to v5.10.44 for its tests). v5.11.2 snapshot
intact; restored + re-applied Phase 3. **Pinned v5.11.19**: per-repo
version isolation via `cyrius.cyml`'s `cyrius` field (resolve from
project instead of global `~/.cyrius/current`; error if version
not installed). User direction.

**5.11.2** (shipped 2026-05-11 — **Stdlib annotation arc Phase 2:
I/O surface**). 182 public fns across 5 modules (io / fs / process
+ syscalls_x86_64_linux + syscalls_aarch64_linux). Mix of `: i64`
(raw syscall returns), `: Result` (10 fns — io `_r` family + process
run/run_capture/spawn/wait_pid), with three fs.cyr path fns kept
`: i64` (Str-shape downgrade — fs.cyr's consumers don't all
include str.cyr first; Phase 6 closeout will add the include and
re-promote). cc5 byte-identical at 804,472 B. **check.sh 66/66**;
**cyrius test 146/146** — parser_cosmetics now passes (v5.11.1
snapshot refresh fixed the include chain).

**5.11.1** (shipped 2026-05-11 — **Stdlib annotation arc Phase 1:
foundational core**). 107 public fns across 8 modules
(alloc / vec / fmt / freelist / fnptr / result / tagged / assert)
now carry `: i64` return-type annotations. Same shape as v5.10.24's
`cstring` annotation pass on `string.cyr` / `io.cyr` — parse-only,
zero codegen impact. cc5 self-host **804,472 B at v5.11.1 — byte-
identical to v5.11.0** (annotations don't change emit). check.sh
66/66; cyrius test 144/146 (1 pre-existing parser_cosmetics fail
absorbed into v5.11.2's snapshot refresh).

**v5.11.0** (shipped 2026-05-11 — **v5.11.x cycle OPEN — kavach P1
sandbox syscall wrappers + roadmap restructure**). v5.10.x closed
at .50; v5.11.0 opens the next minor with the highest-priority
pending work landed (kavach P1 — the only P1 in the consumer-
filed issue backlog) plus roadmap restructure mapping the v5.11.x
arc. cc5 self-host **804,472 B at v5.11.0 — byte-identical to
v5.10.50** (stdlib-only change; cc5 doesn't include
`lib/syscalls_*_linux.cyr`). api-surface 2,876 → **2,888**
(+12 fns).

**Six new wrappers (x86_64 + aarch64 mirrored)**: `sys_fchmod`,
`sys_setresuid`, `sys_setresgid`, `sys_prctl`, `sys_seccomp`,
`sys_execveat`. All async-signal-safe (no heap, no mutex, no
logging) for post-fork / pre-execve sandbox transition windows.
Closes `docs/development/issues/2026-05-10-kavach-sandbox-syscall-
wrappers.md`. 7 sub-asserts in new
`tests/tcyr/sandbox_syscalls.tcyr` (safe wrappers runtime-
exercised; dangerous wrappers compile-time-referenced via `&fn`).

**v5.11.x mandate**:
1. **Stdlib annotation arc** (7-phase, pinned v5.10.32):
   1,010 unannotated public fns across 75 % stdlib coverage.
2. **7 consumer-filed issues** from 2026-05-10 wave (bote /
   daimon / kavach) — 1 P1, 4 P2, 2 Low.
3. **Held-forward from v5.10.x** — Class B FFI/wgpu, cyim
   regex, float.cyr peephole.
4. **Infrastructure** — `cyrius deps` symlink → copy fix
   (v5.10.37 pin), regression.sh → cyrius port +
   Cyriusly cmdtools port (v5.10.36 pin paired), TS test
   harness program (v5.7.37 → v5.10.20).

Slot ordering at slot entry per
`feedback_priority_bottom_to_top` + `feedback_premise_check_at_slot_entry`:
P1 first → annotation foundations (v5.11.1) → cross-arch
fixes → consumer-blocking P2 → infrastructure rotation →
annotation completion → TS test harness → defensive sweep
+ closeout.

See [`docs/development/roadmap.md`](roadmap.md) `## v5.11.x —
Cleanup / annotation-completion minor` section for the full
arc map.

Premise debunk: chat-side cross-host smoke wrappers used `cmd /c
"prog.exe & echo %errorlevel%"` which expands at parse time →
false-negative `exit=0`. Correct shapes (memory pin
`feedback_windows_errorlevel_test_wrapper` saved this slot):
`cmd /v /c "... !errorlevel!"` or `.bat` indirection
(`programs/check.cyr`'s `_pe_exit_gate` always used the correct
shape; chat-side wrappers diverged). Phantom claim propagated
through CHANGELOG entries [5.10.33] / .34 / .39 / .40 / .41 /
.44 / .47; this entry is the durable correction.

**Retroactive Phase 3 status update**: v5.10.47 struct-byval
Phase 3 cass runtime is **actually green** (Point repro
`syscall(60, run())` → cass exit=42 verified with `cmd /v`).
The arc was 4/4 across x86/pi/ecb/cass, not 3/4 as the .47
entry noted under bad-wrapper assumption. Per
`feedback_doc_canonical_no_redundancy`: .47 entry stays as
shipped; this .49 entry is the corrected record.

**Arc COMPLETE** (planned at v5.10.45 entry; see CHANGELOG [5.10.45]
"Arc shape" for the empirical premise-check that drove the
re-scoping):
- Phase 1 (v5.10.45, **shipped**) — x86 SysV via rax+rdx pair.
- Phase 2 (v5.10.46, **shipped**) — aarch64 AAPCS64 via X0+X1
  pair (Linux + Mach-O share ABI). pi runtime exit=42 ✓.
- Phase 3 (v5.10.47, **shipped — arc CLOSED**) — Cross-host
  matrix: local x86 + pi + ecb runtime green; cass compile-clean
  (runtime exit-code gated on pre-existing v5.10.49 PE gap).

Acceptance bar: `struct Point {x: i64; y: i64;}` + `fn make():
Point` + `var got: Point = make();` returns got.y correctly
(not lost to scalar-rax). Pre-v5.10.45 the high half was silently
dropped across ALL backends for value-typed 16B struct returns;
v5.10.28's f64v2 fix didn't generalize (f64v2 uses SSE-class
XMM0, int-class structs use rax+rdx). Str's 16B handle-shape is
preserved unchanged via `_STR_SID(S)` special-case carve-out.
Phase 1 x86 acceptance MET; aarch64 + PE staged for Phase 2/3.

Three new public verbs (`exec_vec_str` / `exec_capture_str` /
`exec_env_str`) parallel the cstr-shape `exec_vec` / `exec_capture`
/ `exec_env`. Each `_str` sibling extracts `str_data` on the way
into execve's argv (and envp for the env variant), so callers
using the natural cyrius idiom (`vec_push(args, str_from("/bin/
foo"))`) get a working verb. Runtime byte/Str dispatch was rejected
at slot entry — both shapes are pointers in cyrius's heap layout,
and the `load64(P)`-looks-like-a-pointer heuristic fails for 8+-
char cstrs (`"/usr/bin"` loads as 7.97e18). Argonaut-blocking
issue closed; consumers migrate via one-line patch
(`exec_vec(cstr)` → `exec_vec_str(Str)`). 6 sub-asserts in new
`tests/tcyr/process_exec_str.tcyr` all pass.

api-surface bumped 2873 → **2876** (+3 fns for the `_str` family).

**Headline numbers** (CYRIUS_PROF=1, `cc5 < src/main.cyr`,
best-of-5 median, end-to-end v5.10.x perf-arc gain pre-.40 → .41):
- lex phase: **603 ms → 62 ms (−90 %, ~9.7×)** [.40]
- fixup phase: **213 ms → 76 ms (−64 %, ~2.8×)** [.41]
- total compile: **1037 ms → 387 ms (−63 %, ~2.7×)** [.40+.41 combined]

v5.10.40 approach: length-bucketed linked-list dedup at heap region
`0x4E8C000..0x4EAD000` (132 KB brk extension; PE mmap had slack).
Per-length head into a 16384-entry chain table.

v5.10.41 approach: `fn_start_hash` open-addressing table at
`0x110000` (8192 slots × 2 B = 16 KB) reusing the 232 KB free gap
between `fn_name_hash` and `struct_ftypes` — no brk extension. Knuth
golden-ratio multiplicative hash; replaces two O(N²) DCE byte-scan
linear scans with ~2-probe lookups. aarch64 fixup has no DCE pass,
so x86-specific change (cross-arch propagation verified by reading
aarch64 fixup.cyr).

Cross-host verified at v5.10.40: pi (aarch64 Linux) native
self-host fixpoint b == c byte-identical at 567,672 B; ecb (macOS
Mach-O arm64) compile+run exit=42; cass (Windows PE) compile
exit=0. v5.10.41 smoke on cass green; pi/ecb byte-identical to
v5.10.40 (no aarch64 backend change).

**Slots .33 - .50 one-liner sweep**:
- **v5.10.33** — `lib/simd.cyr` typed wrappers around f64v_*
  intrinsics; first downstream consumption of typed-simd ABI
  Phase 5 (XMM0 return).
- **v5.10.34** — `lib/tls.cyr` early-data status accessors
  (TLS_EARLY_DATA_NOT_SENT/REJECTED/ACCEPTED + 2 fns); sandhi
  1.1.0 → 1.3.3 fold (+1,194 lines); doc-health.md ledger
  introduced at this slot.
- **v5.10.35** — `PARSE_SIMD_EXT` locname-staleness codegen fix
  via new `_SIMD_STASH` helper; covers ptyp 93-130 (8 intrinsics).
  Same bug-class hit again at v5.10.39 for ptyp 89-91 (separate
  dispatch path).
- **v5.10.36** — aarch64 V0 NEON register-class return for
  f64v2 (replaced v5.10.30 X0+X1 GPR pair); LDUR Q0 / STUR Q0
  for single-register transfer.
- **v5.10.37** — `f64v4` (32-byte packed-double) value type;
  parser + var-decl + extensions; pair-quad return ABI across
  x86 SSE, aarch64 NEON imm12-scaled deep-frame fallback, cx
  4-register r0..r3.
- **v5.10.38** — f64v2 + f64v4 value-form param ABI (Phase 9
  + Phase 10); 0x1282000 fn_param_simd_mask heap region;
  cyrius-internal SysV split-counter (SIMD ordinal independent
  of int ordinal); per-backend ESTOREPARM_F64V*/ELOAD_F64V*_TO_XMM
  emission.
- **v5.10.39** — typed-simd overload dispatch (`f64v2_add(&x, &y)`
  routes to `f64v2_add_ptr`; `f64v2_add(x, y)` calls value-form
  base) + lib/simd.cyr full rewrite (50 public fns, value-form
  gated by CYRIUS_HAS_VAL_SIMD_PARAMS for non-PE targets).
- **v5.10.40** — Lex dedup hot-path optimization. Length-bucketed
  linked-list at `0x4E8C000..0x4EAD000` (132 KB brk extension);
  16384-entry table with per-length head chains; first-occurrence-
  wins canonical offset. lex 603→59 ms (10.2×), total 1037→510 ms
  (2×). Cross-host verified on pi/ecb/cass.
- **v5.10.41** — Fixup phase optimization. `fn_start_hash` at
  `0x110000` (8192 slots × 2 B; Knuth golden-ratio hash) reusing
  free 232 KB gap. Replaces two O(N²) DCE byte-scan inner linear
  scans (seed + propagate). fixup 213→76 ms (2.8×), total 510→
  387 ms (1.32×). aarch64 fixup has no DCE — x86-specific.
- **v5.10.42** — `lib/tls.cyr` hook-surface contract audit. New
  `docs/development/lib-tls-contract.md` (~230 LOC) formalises
  the verb inventory + lifecycle invariants + failure / partial-
  state contract across 24 public verbs. `lib/tls.cyr` header
  points to the doc. cc5 byte-identical (doc-only). No vidya
  entry (API surface, not gotcha). Snapshot-ping-pong guard
  applied via `~/.cyrius/lib/` mirror.
- **v5.10.43** — `lib/str.cyr` `str_split` separator-byte-comparison
  fix. Runtime dispatch on `sep < 256` (byte path) vs `>= 256` (Str
  fat-pointer path); multi-byte Str sep supported. Closes the
  long-standing
  `2026-05-03-str-split-sep-treated-as-pointer.md` issue (live the
  entire v5.x cycle). `lib/process.cyr:224` cstr-sep bug fixed in
  same slot. cc5 byte-identical (lib-only; no compiler include).
- **v5.10.44** — `lib/process.cyr` `exec_*` Str/cstr ambiguity fix.
  Parallel `_str` family (`exec_vec_str` / `exec_capture_str` /
  `exec_env_str`) — each extracts `str_data` on the way into
  execve's argv. Runtime dispatch rejected at slot entry (cstr 8+-
  char literals fail the pointer heuristic). Closes the argonaut-
  blocking
  `2026-05-10-process-exec-str-cstr-ambiguity.md`. api-surface
  2873 → 2876 (+3). cc5 byte-identical (lib-only).
- **v5.10.45** — struct-by-value ABI arc Phase 1: x86 SysV
  int-class pair-return. New `_cur_fn_ret_pair` global,
  `EFLLOAD/STORE_STRUCT_INT_PAIR` x86 emit helpers (rax+rdx),
  caller-side `asv_pair` path mirroring asv_try. `_STR_SID(S)`
  carve-out preserves Str's 16B handle-shape unchanged. cc5
  +4,176 B. 14 sub-asserts in new `tests/tcyr/struct_byval_return.tcyr`.
- **v5.10.46** — struct-by-value ABI arc Phase 2: aarch64 AAPCS64
  X0+X1 pair-return. v5.10.45 ERR_MSG stubs in
  `src/backend/aarch64/emit.cyr` replaced with LDUR/STUR X0,X1
  fast path + LDR/STR via X9 deep-frame fallback. Single change
  covers both Linux aarch64 + macOS arm64 (shared AAPCS64). pi
  runtime: minimal `struct Point` repro → exit=42 ✓ (was 7).
  cc5 byte-identical to v5.10.45 at 803,088 B (aarch64-only
  change). Phase 3 (.47 cross-host smoke + PE retptr verify)
  pinned next.

Per CLAUDE.md, slot-by-slot detail lives in `CHANGELOG.md` (source
of truth); closed cycles roll into `completed-phases.md` at each
minor close. The "Recent shipped" section below carries one-liners
for the current cycle.

## Compiler

- **cc5 (x86_64)**: **804,472 B** at v5.10.50 (unchanged
  from v5.10.48/.49; .50 is closeout — verify + docs +
  cleanup only). Full cycle delta: 753,768 B at v5.10.0 →
  804,472 B at v5.10.50 (+50,704 B / +6.7%); back-half delta
  (.39→.50): +7,008 B (.40/.41 perf miniarc +1,448 B;
  .42/.43/.44 flat; .45 +4,176 B; .46/.47 flat; .48
  +1,384 B; .49/.50 flat).
- **cc5_aarch64_native (cross-built)**: **587,048 B** at
  v5.10.47 (stable through Phase 2/3).
- **cyrius CLI**: ~170,900 B at v5.10.40 (flat across the
  cycle — `cyrius` doesn't run LEXID itself).
- **cc5_macho_arm (cross-built)**: **606,644 B** at
  v5.10.47. End-to-end run on ecb verified at Phase 3
  (exit=42).
- **cc5_win (cross)**: **701,440 B** at v5.10.47 (was
  ~696,832 B at v5.10.44; +4,608 B for the .45/.46
  emit helpers reaching the PE backend via x86 emit.cyr).
  (PE
  backend lives under x86, so the .45 emit helpers
  reach this binary — int-class pair-return ABI now
  available cross-compiled). PE retptr semantics for
  the same surface verify at Phase 3 (.47). PE mmap at
  0x5000000 has 1.5 MB slack past the v5.10.40 brk
  extension to `0x4EAD000`, no resize.
- **cc5_macho_arm (cross)**: ~590 KB at v5.10.40; mmap
  size bumped 0x4E8C000 → 0x4EAD000 to absorb the new
  LEXID region.
- **cc5_aarch64 native (Pi)**: **567,672 B** at v5.10.40
  (native self-host fixpoint b == c verified on pi
  2026-05-11). Cross-built variant from the x86 host is
  582,088 B; the cross/native byte delta is the standard
  "first-bootstrap differs from native rebuild" shape, b
  == c on the native side is the authoritative check.

> Per-slot byte-delta history is in `CHANGELOG.md` (source of truth)
> and `completed-phases.md` (closed cycles). This section tracks
> CURRENT sizes only; closeout passes consolidate per-slot detail
> into the cycle summary at `completed-phases.md`.

- **Self-host fixpoint**: 3-step (cc5_a → cc5_b → cc5_c, b == c) clean at both
  `IR_ENABLED == 0` and `IR_ENABLED == 3` (since v5.6.16).
- **IR=3 NOP-fill on cc5 self-compile** (v5.6.18 baseline carries forward;
  v5.6.19 adds infrastructure only, no codegen change): 135 folds + 678 DCE +
  15 DSE + 567 LASE = 1,395 candidates / **6,099 B**. v5.6.27 compaction
  sweeps picker NOPs at IR=0 only; IR=3 NOP harvest (DSE/LASE/const-fold)
  pinned for a future slot — needs same-shape tracking added to those passes.
- **Regalloc** (v5.6.20–v5.6.24): per-fn live-interval tables (v5.6.19) +
  Poletto-Sarkar picker (v5.6.20) + asm-skip lookahead (v5.6.23) +
  fixed SysV stack-arg shuttle (v5.6.24). **Default-on as of v5.6.24**
  (`CYRIUS_REGALLOC_AUTO_CAP=0` to disable; previously opt-in via
  `#regalloc` only). Picker pins up to 5 locals to rbx/r12-r15.
  v5.6.24 fixed the SysV ECALLPOPS r12-r14 clobber that surfaced as
  the "live-across-calls" bug (sandhi-reported / flags-test
  test_str_short→test_defaults bisection). `CYRIUS_REGALLOC_DUMP=1`
  prints intervals; `CYRIUS_REGALLOC_PICKER_CAP=N` caps assignments
  for bisection.

## Suites

Current at v5.11.0 (v5.11.x cycle OPEN). Cross-host gates wire through `~/.ssh/config`
hosts: **pi = Linux aarch64**, **ecb = Apple Silicon Mach-O arm64**,
**cass = Windows 11 PE32+**.

- **check.sh**: ~66/66 PASS (typed-simd ABI arc added the
  `simd_overload_dispatch.tcyr` gate at v5.10.39; .38 added
  `f64v2_byval_param.tcyr`; .37 added `f64v4_byval_return.tcyr`;
  .34 added `tls_early_data_status.tcyr`).
- **`tests/tcyr/*.tcyr`**: ~135 files (v5.10.x added at least
  9 gates: tls_early_data_status, simd, simd_typed_wrappers,
  f64v2_byval_return, f64v4_byval_return, f64v2_byval_param,
  simd_overload_dispatch, plus REAL TYPE SYSTEM gates).
- **`tests/scyr/*.scyr`**: 1 soak harness (alloc_pressure).
- **`tests/smcyr/*.smcyr`**: 1 smoke harness (compile_minimal).
- **`fuzz/*.fcyr`**: 5 harnesses.
- **`benches/*.bcyr`**: 14 benchmarks.
- **Release toolchain**: 10 bins.
- **Stdlib**: 79 modules (v5.9.0 niyama 1.0.1 fold; v5.10.34
  sandhi 1.1.0 → 1.3.3 refresh fold +1,194 lines).
- **api-surface**: ~2873 entries (from `docs/api-surface.snapshot`
  generated artifact; was 2792 at v5.9.42 close).

Per-slot test-gate detail in `CHANGELOG.md`. Older suite-growth
narrative in `completed-phases.md`.

## In-flight

**v5.10.x cycle CLOSED at 50 slots (2026-05-11).** THREE
completed arcs (typed-simd ABI 11 phases, REAL TYPE SYSTEM 5
phases, struct-byval ABI 3 phases) plus a compile-time-perf
miniarc (.40+.41, 2.7× total compile speedup) plus the TLS
contract pin (.42) plus the roadmap-extension open-issues sweep
(.43/.44/.48 close all 4 v5.10.42-audit issues) plus the
v5.10.49 PE premise-debunk (15-slot phantom closed) plus the
v5.10.50 closeout pass anchor the cycle. **v5.11.0 opens next.**

1. **REAL TYPE SYSTEM** 5-phase arc (v5.10.1 - v5.10.26) — type
   annotations parsed + stored, call-site arg checking, overload
   dispatch on param-type fingerprint, return-type recording,
   sum-type rewriting. Unblock for the typed-simd value-form param ABI.

2. **Typed-simd value-type ABI** 11-phase arc (v5.10.28 - v5.10.39) —
   f64v2 + f64v4 as primitive value types with end-to-end XMM/V
   register-pair param + return ABI across x86 SysV / aarch64 NEON /
   cx bytecode / macho-arm64 / Win64 PE (retptr-style fallback).
   Closed with parser-side `&IDENT → _ptr` overload dispatch and
   the full `lib/simd.cyr` value-form/pointer-form surface (50 fns).

3. **v5.10.40 + v5.10.41 compile-time-perf miniarc** —
   length-bucketed LEXID dedup at v5.10.40 cut lex 603→59 ms
   (10.2×); fn_start_hash in fixup DCE at v5.10.41 cut fixup
   213→76 ms (2.8×). End-to-end gain: total compile-time
   **1037 → 387 ms (2.7×)** on cc5 self-compile. v5.10.0
   profile-guided "compile-time wins" held entry now realised
   across both phases.

4. **v5.10.42 TLS hook-surface contract** — new
   `docs/development/lib-tls-contract.md` pins the
   invariant layer for the `lib/tls.cyr` ↔ `lib/sandhi.cyr`
   surface that stabilised across .40/.13/.21/.27/.34.

5. **v5.10.43 + v5.10.44 open-issues sweep — stdlib
   Str/cstr disambiguation** — v5.10.42-ship roadmap-
   extension audit promoted 4 open issues into v5.10.x
   slots; .43 + .44 close the two Medium-severity bugs:
   - v5.10.43: `str_split` sep-treated-as-pointer (live
     entire v5.x cycle). Runtime dispatch on `sep < 256`
     preserves all 21+ stdlib byte-int callers byte-
     identical AND fixes Str-sep semantics.
   - v5.10.44: `exec_*` family was cstr-only with no
     docstring contract; argonaut-blocking on Str pushes.
     Parallel `_str` family added (`exec_vec_str` /
     `exec_capture_str` / `exec_env_str`); runtime
     dispatch rejected because both Str/cstr are
     pointers and 8+-char cstrs fail the heuristic.

6. **v5.10.45 + v5.10.46 + v5.10.47 struct-by-value ABI
   arc (CLOSED)** — pin re-scoped at v5.10.44 ship after
   empirical premise check showed the original "macOS arm64
   struct-byval" pin was mis-framed: the underlying bug
   (16B int-class struct returns lose the high half) was
   live across ALL backends, not just Mach-O. User authorized
   expansion into a 3-phase arc.
   - **.45**: x86 SysV via rax+rdx pair, `_STR_SID(S)`
     carve-out preserving Str's legacy handle-shape.
   - **.46**: aarch64 AAPCS64 X0+X1 pair (covers Linux
     + Mach-O via shared ABI). Verified on pi (exit=42).
   - **.47**: Cross-host smoke matrix established. Verified
     on pi (exit=42), ecb (exit=42 codesigned), local x86
     (tcyr 14/14). cass compile-clean; runtime exit-code
     gated on v5.10.49 PE exit-code propagation fix. Win64
     ABI deviation from strict MS x64 spec acknowledged
     (cyrius-internal-ABI uses rax+rdx pair; closed-system
     no-consumer-impact rationale documented).

Additional in-cycle work: TLS early-data surface completion at
v5.10.34 (TLS_EARLY_DATA_NOT_SENT/REJECTED/ACCEPTED + accessors);
sandhi 1.1.0 → 1.3.3 refresh fold at v5.10.34; doc-health.md
ledger scaffolded at v5.10.34; vidya wrap-up pass paired with
v5.10.39 (retro file + 3 gotcha entries + 3 feature entries).

**Cycle stats (final, v5.10.50 close)**:
- cc5: 753,768 B at v5.10.0 → **804,472 B at v5.10.50** (+50,704 B, +6.7%)
- cc5_aarch64_native: ~470 KB at v5.10.0 → **587,048 B at v5.10.47**
- cc5_macho_arm: ~510 KB at v5.10.0 → **606,644 B at v5.10.47**
- cc5_win: ~530 KB at v5.10.0 → **701,440 B at v5.10.47**
- api-surface: 2792 → **2876 entries** (+3 v5.10.44 `_str` fns)
- New `lib/simd.cyr` (50 public fns)
- New `docs/development/lib-tls-contract.md` (v5.10.42)
- New `tests/tcyr/str_split.tcyr` (v5.10.43, 35 sub-asserts)
- New `tests/tcyr/process_exec_str.tcyr` (v5.10.44, 6 sub-asserts)
- New `tests/tcyr/struct_byval_return.tcyr` (v5.10.45, 14 sub-asserts)
- **Compile time 1037 → 387 ms (2.7×) across .40 + .41 miniarc**
- 3 locname-staleness surfacings (v5.10.35 fixed ptyp 93-130; v5.10.39
  fixed the duplicate at ptyp 89-91 missed by .35); install.sh
  `cp -L` same-file collision discovered (workaround manual; fix
  pinned for v5.10.50 closeout)

**Closeout pinning**: roadmap has v5.10.45 - v5.10.50 slotted for
the remaining v5.10.x work. Full v5.10.x retro at
`../../../vidya/content/cyrius/field_notes/compiler/retros/v510x.cyml`.

## Recent shipped (one-liner per release)

v5.10.x cycle through 2026-05-11 (CLOSED at v5.10.50):

- **v5.10.50** — cycle closeout. 11-step CLAUDE.md closeout pass
  all green: mechanical (3-step + bootstrap + check.sh 66/66 +
  heapmap 96/0/0), judgment (heap-map clean, 34 dead-fn floor
  unchanged, no x86 leaks, refactor noted), compliance (security
  + downstream all pinned to released tags), doc sync (vidya
  retro back-half + 3 features.cyml entries). One cleanup
  finding: `bootstrap/verify.sh` `stage1/` path fixed. cc5
  byte-identical. v5.11.0 opens next.
- **v5.10.49** — Win64 PE `println` + exit-code premise-debunk
  (no code change). Empirical re-test shows both pinned pieces
  work today; the "broken" claims were a 15-slot chat-side
  test-wrapper bug (`cmd /c "& echo %errorlevel%"` parse-time
  expansion). Memory pin saved. v5.10.47 struct-byval Phase 3
  cass retroactively confirmed exit=42 (arc 4/4, not 3/4).
  cc5 byte-identical to v5.10.48.
- **v5.10.48** — Defensive sweep + parser cosmetic limits (7-item
  bundle). Bare `return;` synthesizes `return 0;`; enum-ident
  array sizes accepted in BOTH PARSE_ARRAY + PARSE_GVAR_ARR;
  parse_fn.cyr AARCH64 defensive guards; `run_script` file_exists
  guard. Premise-checked 3 items as already-resolved/out-of-
  scope. cc5 +1,384 B. 4 open issues from the v5.10.42 audit
  now all closed.
- **v5.10.47** — struct-by-value ABI arc Phase 3: cross-host smoke
  + PE retptr verify (arc CLOSED). 4-target matrix: x86 (tcyr
  14/14), pi (exit=42), ecb (exit=42 codesigned), cass (compile=0;
  runtime gated on .49). Win64 ABI deviation acknowledged. cc5
  byte-identical to v5.10.45/.46.
- **v5.10.46** — struct-by-value ABI arc Phase 2: aarch64 AAPCS64
  X0+X1 pair-return. v5.10.45 ERR_MSG stubs replaced with real
  LDUR/STUR X0,X1 encodings + LDR/STR X9 deep-frame fallback.
  Linux aarch64 + macOS arm64 covered (shared ABI). pi runtime
  verify: struct Point 7+35 repro → exit=42 ✓. cc5 byte-identical
  to v5.10.45 (aarch64-only change). cc5_aarch64_native +4,960 B.
- **v5.10.45** — struct-by-value ABI arc Phase 1: x86 SysV
  int-class pair-return. `_cur_fn_ret_pair` flag set by rough-scan
  when fn returns 9-16B non-Str struct; PARSE_RETURN emits
  `mov rax,[&v+0]; mov rdx,[&v+8]`; caller `asv_pair` path mirrors
  the layout. `_STR_SID(S)` carve-out preserves Str's handle-mode.
  14 sub-asserts. Phase 2 (.46 aarch64) + Phase 3 (.47 cross-host)
  pinned.
- **v5.10.44** — `lib/process.cyr` `exec_*` Str/cstr ambiguity fix
  (parallel `_str` family). Three new public verbs (`exec_vec_str`
  / `exec_capture_str` / `exec_env_str`); each extracts `str_data`
  on the way into execve's argv. Runtime dispatch rejected (cstr
  8+-char literals fail the pointer heuristic). Closes argonaut-
  blocking `2026-05-10-process-exec-str-cstr-ambiguity.md`. 6
  sub-asserts. api-surface 2873 → 2876.
- **v5.10.43** — `lib/str.cyr` `str_split` separator-byte-comparison
  fix (runtime byte/Str dispatch). Closes the long-standing issue
  filed at `docs/development/issues/2026-05-03-str-split-sep-
  treated-as-pointer.md`. `sep < 256` → byte path; `sep >= 256` →
  Str fat-pointer path with multi-byte sep support. cc5 byte-
  identical (lib-only). 12 test groups / 35 sub-asserts.
- **v5.10.42** — `lib/tls.cyr` hook-surface contract audit. New
  `docs/development/lib-tls-contract.md` (~230 LOC) formalises 24
  public verbs (availability / connect-fused / connect-staged /
  I/O / hook-time config / session resumption / session cache cbs /
  0-RTT / soft-deprecated `tls_dlsym` escape hatch). cc5 byte-
  identical (doc-only); 3-step fixpoint clean.
- **v5.10.41** — Fixup phase optimization. `fn_start_hash` at
  `0x110000` (8192 slots × 2 B; Knuth golden-ratio multiplicative
  hash) reusing free 232 KB gap; replaces two O(N²) DCE byte-scan
  linear scans. fixup 213→76 ms (2.8×), total 510→387 ms (1.32×).
  aarch64 fixup has no DCE — x86-specific (PE backend reached too).
- **v5.10.40** — Lex dedup hot-path optimization. Length-bucketed
  linked-list at `0x4E8C000..0x4EAD000` (132 KB brk extension);
  16384-entry table; first-occurrence-wins canonical offset. lex
  603→59 ms (10.2×), total 1037→510 ms (2.0×). Cross-host verified
  on pi (native fixpoint b == c at 567,672 B) / ecb / cass.
- **v5.10.39** — typed-simd overload dispatch (`f64v2_add(&x, &y)`
  routes to `_ptr` sibling) + `lib/simd.cyr` value-form/pointer-form
  surface (50 fns). Typed-simd ABI arc CLOSED at Phase 11.
- **v5.10.38** — f64v2 + f64v4 value-form param ABI (Phase 9-10);
  0x1282000 fn_param_simd_mask; cyrius-internal SysV SIMD split-counter.
- **v5.10.37** — f64v4 (32-byte packed-double) value type; pair-quad
  return ABI across all backends.
- **v5.10.36** — aarch64 V0 NEON register-class return for f64v2
  (replaced X0+X1 GPR pair).
- **v5.10.35** — `PARSE_SIMD_EXT` locname-staleness fix + `_SIMD_STASH`
  helper; threat-model + fncall-abi doc refresh.
- **v5.10.34** — `lib/tls.cyr` early-data status accessors; sandhi
  1.1.0 → 1.3.3 fold; doc-health.md ledger introduced.
- **v5.10.33** — `lib/simd.cyr` typed wrappers (first downstream
  consumption of typed-simd ABI Phase 5 XMM0 return).
- **v5.10.32** — typed-simd ABI Phase 5: x86 SysV XMM0 single-register
  return for f64v2 (replaced int-class rax/rdx pair).
- **v5.10.31** — typed-simd ABI Phase 4: Win64 PE retptr-style fallback.
- **v5.10.30** — typed-simd ABI Phase 3: aarch64 NEON V0 return.
- **v5.10.29** — typed-simd ABI Phase 2: x86 SysV f64v2 return path.
- **v5.10.28** — typed-simd ABI Phase 1: f64v2 as primitive value type.
- **v5.10.27** — REAL TYPE SYSTEM closeout consolidation.
- **v5.10.26** — Phase 5: sum-type rewriting + derive-friendly.
- **v5.10.25** — `_str` / `_int` / `_cstr` overload pattern.
- **v5.10.22-24** — overload dispatch refinement.
- **v5.10.21** — TLS surface filling.
- **v5.10.20** — P(-1) sweep.
- **v5.10.13-19** — TLS Phase + agnosys cascade close + `_init_cyrius_lib`
  hardening.
- **v5.10.1-12** — REAL TYPE SYSTEM Phases 1-4; agnosys 1.1.12 cascade;
  vyakarana cap unblock; net/tls Phase 1; `_check_shadow_lib`.
- **v5.10.0** — per-phase compile-time profiling (`CYRIUS_PROF=1`).

(Slot-by-slot detail in `CHANGELOG.md`. Earlier cycles in
`completed-phases.md`.)

## Consumers

AGNOS kernel, agnostik (58 tests), agnosys (20 modules), argonaut (424
tests), sakshi, sigil (206 tests), libro (240 tests), shravan (audio),
cyrius-doom, bsp, mabda, kybernet (140 tests), hadara (329 tests),
ai-hwaccel (491 tests).

All AGNOS ecosystem projects depend on the compiler and stdlib.

## Verification hosts

- `ssh pi` — Pi 4 (Linux aarch64 native runtime)
- `ssh ecb` — Apple Silicon MBP (Mach-O arm64 runtime)
- `ssh cass` — Windows 11 24H2 (PE32+ runtime)

## Bootstrap chain

```
bootstrap/asm (29 KB committed binary — root of trust)
  → cyrc (12 KB compiler)
    → bridge.cyr (bridge compiler)
      → cc5 (modular compiler + IR, 9 modules)
        → cc5_aarch64 (cross-compiler)
        → cc5_win (cross-compiler)

No Rust. No LLVM. No Python. Just sh + Linux x86_64.
Build: sh bootstrap/bootstrap.sh
```
