# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.

## Version

**5.11.51** (shipped 2026-05-13 — **Byte-array literal
`var foo[N] = { 0x.., 0x.., ... };` — gnoboot ergonomic fix #1
of 2**). Closes `2026-05-13-gnoboot-byte-array-literal.md`.
Companion `fn efi_main` convention lands at .52.

**Syntax/semantics**:
- `[N]` allocates `N*8` bytes (existing cyrius semantic; arrays
  are 8-byte slots).
- Brace-list bytes initialise the first `k+1` bytes (zero rest);
  each must be NUM in `[0, 255]`. Hex/decimal/trailing-comma all OK.
- Capacity check `k+1 > N*8` is a hard parse error.
- Bytes are initialised by emitted `store8(&var + i, B)` sequences
  at top-level entry — same shape the consumer would write by
  hand; ~21 bytes of `.text` per byte. Future v6.x peephole/`.rdata`
  compaction possible.

**Implementation** (3-part):
1. **`EADDRA_IMM(S, n)`** named op per backend (`src/backend/{x86,
   aarch64,cx}/emit.cyr`) — `rax += imm`. x86: `48 05 imm32` (6 B);
   aarch64: `ADD x0,x0,#imm12` (`0x91000000 | (imm<<10)`, 4 B);
   cx: composed via `CX_MOVI` to scratch + add-reg.
2. **`PARSE_GVAR_ARR`** (`src/frontend/parse_decl.cyr:533`) — extended
   to accept `sti` param + optional `= { byte-list };` tail.
   Validates inline (parse-time errors on bad bytes / capacity)
   but **defers codegen** — saves `sti` to `gvar_toks` so pass-2
   replay can emit. Pass-1 emits land in dead code (skipped by
   entry-jmp patch).
3. **`EMIT_GVAR_INITS`** (`src/frontend/parse_decl.cyr:735`) — at
   replay, detects array-decl shape (`[` after IDENT) and emits
   per-byte: `EVADDR + EADDRA_IMM + EPUSHR + EMOVI + EPOPC +
   ESTORE8 + EXORAA`.

**Token-ID gotcha** (caught at slot bringup): `{` is token **13**,
`{` is **NOT** token 19 (which is `<`). Initial mis-map produced
`error: expected '<', got '{'` — the kind of confused-diagnostic
that consumers would file. Comment now names token IDs explicitly.

**Test coverage**: `tests/tcyr/byte_array_literal.tcyr` — 26
sub-asserts across 5 categories (ordering / zero-fill /
UTF-16LE interleave / boundary u8 / mixed-hex-decimal +
trailing-comma).

**Issue archive**:
`docs/development/issues/2026-05-13-gnoboot-byte-array-literal.md`
→ `archived/`.

**Cross-arch**: all 3 backends ship `EADDRA_IMM` in this slot.
Deferred-emit is parser-side (backend-agnostic via named ops).
Not a half-fix.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**825,760 B** / +2,648 from v5.11.50); `check.sh` **74/74**;
`cyrius test` **150/150** (+1 new tcyr).

**Next**: v5.11.52 — `fn efi_main(handle, st)` convention +
`lib/fnptr.cyr` MS-x64 branch. The other gnoboot ergonomic
filing.

**5.11.50** (shipped 2026-05-13 — **Cap-drift detector + doc-size
currency gates + fresh-tier doc refresh**). Two new programmatic
gates in `programs/check.cyr` close recurring drift surfaces.
Plus immediate fix-forward of the stale cc5-size claims in
size-comparisons.md / platform-status.md / faq.md. Resolves the
v5.11.49-filed `2026-05-13-cap-drift-detector-gate.md` issue
same-day.

**Cap-drift gate** — `_cap_drift_gate()` cross-checks heap-map
comments at `src/main.cyr:24+` against inline literal caps in
`src/frontend/lex.cyr`. Three known surfaces verified:
`input_buf` (1 MB / 1048576), `tok_names` (256 KB / 262144 with
261872 inline guard accounting for 272 B LEXID slack), `str_data`
(2 MB / 2097152). Anchored on `0xADDR region_name` combos to
skip cross-reference NOTEs.

**Doc-size gate** — `_doc_size_currency_gate()` scans
size-comparisons.md / platform-status.md / faq.md / README.md
for `cc5 ~NNN KB` claims, verifies within ±50 KB of actual
build/cc5 (decimal KB). Lines with `(v5.X.Y)` historical tag
are exempt.

**Fresh-tier doc refresh** — size-comparisons.md cc5 739,672 B
(v5.8.31) → 823,112 B (v5.11.50); platform-status.md cc5 ~741 KB
(v5.8.65) → ~823 KB (v5.11.50); faq.md self-compile time 280 ms
→ 387 ms (post v5.10.40-.41 perf miniarc), cc5 size bumped to
~823 KB. Cross-compiler sizes refreshed (cc5_aarch64 506,216 B;
cc5_win 630,272 B). doc-health.md ledger header bumped.

**Helper fn** `_find_str_from(buf, n, from, needle, nlen)` —
bounded substring search returning absolute offset on hit or −1
on miss. Used by both new gates.

**Issue archive** —
`docs/development/issues/2026-05-13-cap-drift-detector-gate.md`
→ `archived/`. Filed during the v5.11.49 vidya cleanup; resolved
at .50 ship.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**823,112 B** — unchanged from v5.11.49; gates are tooling, no
compiler change); `check.sh` **72 → 74**; `cyrius test`
**149/149**.

**Next**: two new gnoboot ergonomic-improvement issues filed
2026-05-13 by gnoboot agent (byte-array literal + efi_main
calling convention). User-pinned for .51/.52 (or .51 bundle
if scope fits).

**5.11.49** (shipped 2026-05-13 — **OVMF runtime smoke + arc
closeout; gnoboot MVP unblocker GA, arc KO**). Third and final
slot of the 3-slot UEFI Application emit arc. cyrius-compiled
`programs/efi_probe.cyr` boots end-to-end under qemu+OVMF and
prints `"hello, uefi"` to firmware's ConOut serial.

**Runtime bringup discovery**. Manual OVMF boot of v5.11.48
output produced `BdsDxe: failed to load ... Not Found`. Walk-
through: DOS+PE+Subsystem+DllChar+DataDirs all correct; **COFF
Characteristics = 0x0023 includes RELOCS_STRIPPED (0x0001)**.
UEFI firmware treats RELOCS_STRIPPED as "load me at exactly
ImageBase=0x140000000 or fail" — and OVMF's runtime services
occupy nearby pages so allocation fails silently → "Not Found".
Standard UEFI Application binaries (rEFInd, systemd-boot,
GRUB-EFI) NEVER set RELOCS_STRIPPED for exactly this reason.

**Fix**. `src/backend/pe/emit.cyr:714` COFF Characteristics
branch:
```cyrius
var _chars = 0x0023;
if (_pe_reloc_vsize != 0) { _chars = 0x0022; }
if (_TARGET_EFI_APPLICATION == 1) { _chars = 0x0022; }
```
EFI mode now clears RELOCS_STRIPPED unconditionally — firmware
can place at any free address; probe doesn't care (all addressing
is runtime register-indirect, no imm64 references); gnoboot will
care correctly once it has globals (covered by `.reloc`).

**Post-fix boot trace**:
```
BdsDxe: starting Boot0002 "UEFI QEMU HARDDISK QM00001 " ...
hello, uefi
BdsDxe: loading Boot0000 "BootManagerMenuApp" ...
```
Firmware loaded BOOTX64.EFI, jumped to AddressOfEntryPoint, our
inline-asm executed `SystemTable→ConOut→OutputString(L"hello,
uefi\r\n")`, returned EFI_SUCCESS, firmware unwound back to boot
manager menu. **End-to-end working.**

**_efi_ovmf_smoke_gate()** (new). `programs/check.cyr` registers
the runtime-floor gate right after `_efi_emit_gate`. Compiles
`efi_probe.cyr` via `_self_host_pipe_efi`; orchestrates a GPT-
disk-with-ESP build (parted + mtools + mcopy); runs the disk
under qemu+OVMF with `-serial stdio` capture; greps for
`"hello, uefi"`. Orchestration is a `/bin/sh -c '<one-liner>'
-- $efi_path` shell-out (test glue, not a separate
scripts/ovmf-smoke.sh deliverable). Graceful SKIP path if
qemu/parted/mtools/OVMF firmware missing — gate is opt-in via
test-environment presence. Negative-test verified: v5.11.48 cc5
(RELOCS_STRIPPED set) → gate FAILs `(sh rc=1)`; post-fix → PASS.

**Issue archive**:
`docs/development/issues/2026-05-13-gnoboot-uefi-application-emit.md`
→ `docs/development/issues/archived/`.

**gnoboot consumer status**: AGNOS Path C / gnoboot can pin
`cyrius = "5.11.49"` and start writing the sovereign UEFI
bootloader. Path A (ELF64 multiboot2 via GRUB) dead-on-iron;
Path C is the live MVP boot path.

**Arc summary (v5.11.47 → v5.11.49)**:
- cc5: 821,984 → **823,112 B** (+1,128 B total across 3 slots)
- check.sh: 70 → **72** (+2 gates: structural + runtime)
- 1 new cyrius source program: `programs/efi_probe.cyr` (64 LoC,
  inline-asm-only — no fixups, no globals)
- 1 filing closed (gnoboot UEFI emit issue, archived)
- Compile→runtime turnaround: same-day (filing in the morning →
  arc shipped + runtime-verified in the afternoon)

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**823,112 B**); `check.sh` **72/72**; `cyrius test` **149/149**.
Default-off path byte-identical to v5.11.48.

**Next**: gnoboot consumer agent picks up the unblocked toolchain.
Cyrius cycle returns to v5.11.x absorber buffer (.50 → .67 open;
.68 = heap-map full reorg, .69 = conditional mabda fold).

### Prior v5.11.x ships (one-liner per release; detail in CHANGELOG.md)

- **v5.11.50** — Cap-drift detector + doc-size currency gates + fresh-tier doc refresh: `_cap_drift_gate()` cross-checks heap-map comments vs inline literal caps; `_doc_size_currency_gate()` scans fresh-tier docs for cc5 size refs (decimal KB ±50 KB tolerance); 4 docs refreshed v5.8.x → v5.11.50. check.sh 72→74.
- **v5.11.49** — OVMF runtime smoke + gnoboot arc closeout: RELOCS_STRIPPED cleared in EFI mode (UEFI firmware needs latitude to place anywhere); new `_efi_ovmf_smoke_gate()` boots efi_probe.efi under qemu+OVMF and asserts "hello, uefi" on serial. Arc filing → ship same-day. check.sh 71→72.
- **v5.11.48** — EFI Application probe + structural gate (gnoboot arc P2): `programs/efi_probe.cyr` (64 LoC, inline-asm-only); `_efi_emit_gate()` structural check (Subsystem=0xA, NX_COMPAT, Data Dirs zeroed, .text has ret); DllCharacteristics NX_COMPAT forced in EFI mode even without `.reloc`. check.sh 70→71.
- **v5.11.47** — UEFI Application PE emit mode + `_pe_ensure_*` refactor (gnoboot arc P1): `_TARGET_EFI_APPLICATION` flag, Subsystem byte 3→10 branch, EEXIT EFI variant (single `ret`), ExitProcess import skip + kernel32 fail-fast guard, Data Dirs [1]/[12] zeroed. 9 `_pe_ensure_<X>(S)` fns consolidated to single `_pe_register_kernel32` helper.
- **v5.11.46** — ELF64 kernel entry-arithmetic agreement (FIXUP ↔ EMITELF64_KERNEL) — agnos UEFI x86_64 boot regression fix; `_elf64_kernel_entry_gate()` added (check.sh 69→70).
- **v5.11.45** — P(-1) hardening sweep (4-item bundle): state.md compression 1451→583, `build/cc5` contamination gate, `cyrius vet` restored, dead-fn report behind `CYRIUS_DCE_VERBOSE=1`. check.sh 68→69.
- **v5.11.44** — `build/cc5` mabda-contamination restoration + cyrius-lsp `argv[0]` self-resolution + doc-cleanup bundle.
- **v5.11.43** — ELF64 kernel emit + multiboot2 + EFI64-entry tag — Path A for AGNOS UEFI x86_64 boot.
- **v5.11.42** — LSP `textDocument/semanticTokens/full` legend extension — locals + parameters colored. Roadmap doc-cleanup: -1258 lines (-51%).
- **v5.11.41** — CVE-08 security hardening (`cld` before `rep movsb`) + doc-cleanup: `completed-phases.md` phase-out trim + roadmap held-items reconciliation.
- **v5.11.40** — `f64_abs(x)` peephole — long-pinned optimization landed.
- **v5.11.39** — `ESWITCH_DISPATCH_*` named ops; drift gate extends to all 6 parse_*.cyr files.
- **v5.11.38** — Parser-to-emit named-op refactor — Class B missed-site + drift-prevention gate; ARC CLOSED.
- **v5.11.37** — Parser-to-emit named-op refactor — Class C (f64 unary ops).
- **v5.11.36** — Parser-to-emit named-op refactor — Class B (PIC-vs-direct address loads).
- **v5.11.35** — Parser-to-emit named-op refactor — Class D (v5.7.12 audit doc).
- **v5.11.34** — aarch64 user-binary ELF emitter section-header fix.
- **v5.11.33** — `PP_IFDEF_PASS` 2 MB cap raised to 8 MB; `preprocess_out` buffer relocated.
- **v5.11.32** — x86_64 user-binary ELF emitter section-header fix.
- **v5.11.31** — `cyrld` ELF64 user-binary linker section-header fix.
- **v5.11.30** — aarch64 kernel ELF emitter section-header fix.
- **v5.11.29** — Kernel ELF emitter: minimal section header table for GRUB multiboot compatibility.
- **v5.11.28** — bote parser quirk slot — closed as no-repro + diagnostic improvement + regression test.
- **v5.11.27** — aarch64-native build repair.
- **v5.11.26** — Per-repo isolation Part 3: `cyriusly use --global` flag + per-repo default.
- **v5.11.25** — Per-repo isolation Part 2: `cyrius` CLI version-resolved dispatcher.
- **v5.11.24** — `#derive(accessors)` >16-field silent miscompile fix.
- **v5.11.23** — PE32+ kernel32 path-API alignment fix.
- **v5.11.22** — ai-hwaccel `cc5_win` debunk + mkdir/unlink PE plumbing.
- **v5.11.21** — 0-call public stdlib fn downstream survey.
- **v5.11.20** — Syscall-wrapper DRY consolidation.
- **v5.11.19** — kybernet Part A.ii: `fn_table` 4096 → 8192 (heap-map refactor).
- **v5.11.18** — kybernet Part A.i + Part B: identifier buffer 2× + socket-syscall wrappers.
- **v5.11.17** — Per-repo isolation Part 1: `cyrius deps` stdlib_dir fix.
- **v5.11.16** — bote WS handshake key validation (RFC 6455 §4.1).
- **v5.11.15** — bote P2: streaming dispatch primitives.
- **v5.11.14** — bote P2: arena lifecycle terminator + per-frame reuse pattern.
- **v5.11.13** — bote P2 part A: `sock_set_recv_timeout` (Slowloris fix).
- **v5.11.12** — daimon P2: `lib/async.cyr` aarch64 portability fix.
- **v5.11.11** — TS test harness program.
- **v5.11.10** — Cyriusly cmdtools port closeout — full surface, cyriusly added to release bins, `scripts/cyriusly` retired from release.scripts.
- **v5.11.9** — Cyriusly cmdtools port — scaffold + light verbs.
- **v5.11.8** — `cyrius deps` symlink → file-copy.
- **v5.11.7** — Stdlib annotation arc — Phase 7: compiler-side internals + ARC CLOSE.
- **v5.11.6** — Cross-binary ship: `cc5_win` (PLATFORM BLOCKER unblock).
- **v5.11.5** — Stdlib annotation arc — Phase 6: partial-coverage closeouts + 9-sibling release fold-in.
- **v5.11.4** — Stdlib annotation arc — Phase 4: collection libraries.
- **v5.11.3** — Stdlib annotation arc — Phase 3: string/format completion.
- **v5.11.2** — Stdlib annotation arc — Phase 2: I/O surface.
- **v5.11.1** — Stdlib annotation arc — Phase 1: foundational core.
- **v5.11.0** — v5.11.x cycle OPEN — kavach P1 sandbox syscall wrappers + roadmap restructure.


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
