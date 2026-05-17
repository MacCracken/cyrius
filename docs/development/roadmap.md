# Cyrius Development Roadmap

**Scope** — only the **current cycle** (v5.11.x) **remaining** work.
Everything else — long-term considerations, v6.x pre-pinned work,
v5.x platform / toolchain / language sections, ecosystem snapshot —
lives in [roadmap-old.md](roadmap-old.md) pending cleanout. The 6.x
items will be pulled forward into this file once v5.x closes; the
v5.x retrospective material will migrate to `completed-phases.md`
under the same archive pattern used for prior cycles.

## See also

- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check,
  cross-host smoke, cycle-close shape). Evergreen; not cycle-specific.
- [state.md](state.md) — volatile current state (version, cc5 size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [completed-phases.md](completed-phases.md) — pre-v5.11.x historical
  arc retrospective (Phase 0–11 foundation summary post-trim).
- [roadmap-old.md](roadmap-old.md) — full prior roadmap held verbatim
  for cleanout; source for v6.x items to pull in at cycle close.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v5.11.x — Final 5.x minor (close-out arc)

v5.11.x is the **last minor of the v5.x line**. All work that
closes the v5.x arc — user-binary ELF cleanup, stdlib data-domain
carve-out (bayan + ganita), parser-to-emit named-op refactor,
sovereignty/polish remainders, and the pre-v6.0 heap-map full
reorganization — lands here, sealing the cycle at the
**v5.11.68 / v5.11.69 close pair** — heap-map full reorganization
at .68 (the true closeout engineering work), with .69 reserved
for any dep foldins that earn their slot during the window
(mabda 3.0 GA conditional; if no fold lands, .68 is the final
v5.x patch).

Anything that would expand the language's *capabilities* — new
platforms, new language features, new linker modes — moves to
v6.x. The v5.x → v6.x boundary is now: **v5.x = "what the language
IS"; v6.x = "new platforms + advanced features the language gains."**

Per-patch detail for v5.11.0 → current ships lives in
[CHANGELOG.md](../../CHANGELOG.md); current-state snapshot lives
in [state.md](state.md).

### v5.11.51 / v5.11.52 — gnoboot ergonomic-improvement filings (post-arc consumer feedback)

Two enhancement filings landed 2026-05-13 from the gnoboot
consumer agent during Step 4 (`HandleProtocol(LoadedImage)`
work, the first cyrius-fn-driven gnoboot code post the pure-asm
banner). Both are ergonomic, not bugs — gnoboot v0.1.0 can ship
without them, the consumer-side workarounds work today. Pinned
as separate slots per honest scope-split (different surfaces,
clean bisect windows).

- **v5.11.51 — byte-array literal `var foo[N] = { 0x.., ... };`**
  Filing: `docs/development/issues/2026-05-13-gnoboot-byte-array-literal.md`.
  Surface: `src/frontend/parse_decl.cyr` `PARSE_GVAR_ARR`
  extension + gvar-init codegen to emit bytes into `.rdata` at
  compile time. Length-mismatch error path. Optional `u16`-typed
  variant for UTF-16LE friendliness. Estimate: ~80-150 LoC
  parser + codegen wiring. Verification: 1-2 new tcyr; all
  existing tests stay byte-identical. Acceptance: gnoboot's
  ~150 lines of `store8(&msg_pre + N, 0x..)` collapse to ~10
  lines of brace-list initializer.
- **v5.11.52 — `fn efi_main(handle, st)` entry convention +
  lib/fnptr.cyr MS-x64 branch**.
  Filing: `docs/development/issues/2026-05-13-gnoboot-efi-main-convention.md`.
  Surface: entry-point emit under `_TARGET_EFI_APPLICATION == 1`
  (parser detect of `fn efi_main` + special trampoline emit) +
  `lib/fnptr.cyr` `#ifdef CYRIUS_TARGET_EFI` branch for MS-x64
  ABI. Existing `kernel;` + top-level-asm shape stays supported
  (opt-in via fn presence). Estimate: ~100-200 LoC compiler
  + ~30 LoC stdlib. Verification: efi_probe still boots under
  OVMF (existing .49 gate); gnoboot rebuilds + OVMF smoke;
  cross-arch propagation review of lib/fnptr.cyr touchpoints.
  Acceptance: gnoboot's `main.cyr` trampoline (~50 lines of
  store8 + asm + var fp + asm) collapses to a `fn efi_main(handle,
  st)` body and cyrius handles the firmware ABI translation.

### v5.11.47 → v5.11.49 — UEFI Application PE emit mode (gnoboot MVP unblocker)

3-slot arc authorised 2026-05-13 to unblock the AGNOS sovereign
UEFI bootloader (`gnoboot`) MVP boot path. Path A (ELF64 +
multiboot2 via GRUB) is dead-on-iron due to GRUB's
`grub_relocator64_efi_boot` writing register state into its own
RO `.text` under modern UEFI's Memory Attributes Protocol; Path C
= sovereign Cyrius UEFI bootloader, ~2000 LoC, closed-beta target
early June 2026. Filing:
[`docs/development/issues/2026-05-13-gnoboot-uefi-application-emit.md`](issues/2026-05-13-gnoboot-uefi-application-emit.md).

Premise audit at slot entry surfaced that the filing's speculation
was partially stale: `.reloc` directory + DllCharacteristics
(NX_COMPAT + DYNAMIC_BASE + HIGH_ENTROPY_VA = 0x0160) already
shipped at v5.5.35 / v5.6.31. Actual compiler-side deltas are
smaller than the filing estimated.

- **v5.11.47 — Compiler enablement + `_pe_ensure_*` refactor.**
  Refactor first (consolidate 9 near-identical
  `_pe_ensure_<X>` / `_pe_<X>_get` pairs in `src/backend/pe/emit.cyr`
  — stdio_getstd, stdio_writef, readf, closeh, seekfp, vallo,
  createf, createdir, deletef, gettick — into a single generic
  helper; byte-identical proof). Then layer
  `_TARGET_EFI_APPLICATION` flag + `CYRIUS_TARGET_EFI=1` env var
  in `src/main.cyr` + `src/main_win.cyr`. Subsystem branch at
  `src/backend/pe/emit.cyr:746` (3 → 0xA). EEXIT EFI variant in
  `src/backend/x86/emit.cyr:545` (single `ret` byte 0xC3 — firmware
  reads rax as EFI_STATUS). Skip `_pe_imp_add("ExitProcess")` at
  `_pe_layout:439`; consolidated `_pe_ensure` helper errors out if
  any kernel32 reroute fires in EFI mode (compile-error, not silent
  miscompile). `.reloc` + DllCharacteristics audit-confirmed
  EFI-correct, no code change there. ~150 LoC of compiler change.
- **v5.11.48 — `programs/efi_probe.cyr` + structural gate.**
  Minimal "hello, uefi" probe: capture RCX (ImageHandle) + RDX
  (SystemTable) via inline asm as first top-level statements,
  call `SystemTable->ConOut->OutputString(L"hello, uefi\\r\\n")` via
  function-pointer indirection, return EFI_SUCCESS (0). New
  `_efi_emit_gate()` in `programs/check.cyr` compiles efi_probe
  with `CYRIUS_TARGET_EFI=1`, asserts Subsystem byte = 0x0A at the
  optional-header offset, `.reloc` directory non-zero, no
  kernel32!ExitProcess in `.idata`. check.sh **70 → 71**.
- **v5.11.49 — OVMF smoke + arc closeout.**
  `qemu-system-x86_64 -drive if=pflash,...OVMF_CODE.4m.fd
  -drive ...OVMF_VARS.4m.fd -drive ...esp.img -serial stdio
  -display none` boot of efi_probe.efi staged at
  `/EFI/BOOT/BOOTX64.EFI` on a FAT ESP image; verify "hello, uefi"
  appears on serial. Any runtime fix that surfaces (entry-point
  shape, ABI corner, `.reloc` blocks under EFI relocation, missed
  data-directory entry) lands as part of .49. Arc-closeout
  CHANGELOG cross-links the three slots; issue
  `2026-05-13-gnoboot-uefi-application-emit.md` archived. Memory
  pin `project_agnos_path_c_gnoboot` updated with final shape.

Cap is **.49**. If .47 ships clean and .48 probe boots first-try
under OVMF, .49 compresses to verification + closeout doc only.
Acceptance bar = AGNOS unblocked to start writing `gnoboot`
proper against `cyrius = "5.11.49"`.

Memory pin: `project_agnos_path_c_gnoboot`.

### Stdlib data-domain distlib carve-out (bayan + ganita)

Two sandhi-fold siblings carved out of stdlib using the v5.7.0
sandhi pattern (sakshi / patra / sigil precedent):

- **bayan** — `json`, `toml`, `cyml`, `csv`, `base64`, `bigint`, `u128`
- **ganita** — `matrix`, `linalg`, advanced math

Math primitives + regex stay in stdlib. Naming convention:
`<sibling>_<module>_*`. Hisab is **out of scope** for this carve
(parallel-universe external dep, not stdlib material).

After the carve, stdlib stays primitives-only — bare-metal
consumers in v6.x's RISC-V / firmware work won't drag the data
offshoots into kernel objects.

Memory pin: `project_bayan_ganita_carve_arc`.

### Sovereignty / polish / consumer-filed buffer

The band between named slots (current → .68, roughly 25 slots) is
the explicit absorber for items that surface during the cycle:
emergent consumer bugs, doc-health follow-ups, audit-pinned
peephole patterns, sovereignty pass remainders, agnosys
post-release polish. Same default-bias as prior cycles — ride
the cap rather than silently expanding; if the buffer truly
fills, surface the pressure rather than punting.

**Held forward** (still gated on consumer-surface triggers):

- **Class B FFI / wgpu fncall6 ABI** (mabda B1/B2) — held per
  v5.10.20 P(-1) sweep direction; pin if mabda resurfaces.
- **`cyim` regex pattern parse error** (mabda C6) — defer per
  user 2026-05-12 until cyim repo updates + re-tests against
  current cyrius.

### v5.11.x — mabda 3.0 GA fold (CONDITIONAL, watching window)

**If mabda 3.0 GA cuts during the v5.11.x window**, fold mabda
into stdlib using the v5.7.0 sandhi pattern (sakshi 2.2.3 /
patra 1.9.3 / sigil 3.1.0 / vani 0.9.2 / yukti 2.2.2 / sankoch
2.2.4 precedent in v5.8.x; niyama 1.0.1 in v5.9.x). Sister fold:
agnosys (transitive via mabda).

**Soak gate**: mabda 3.0.0-rc.2 is running its **24-hour passing
soak** (project-leader-set standard for GA promotion). 2-hour
window observed clean at 2026-05-12 session; remaining 22 hours
decide whether GA cuts inside the v5.11.x window.

**Why this fits 5.x close** (despite the language-feature
exclusion rule): the fold itself is **stdlib hygiene, not a
language capability addition** — it vendors source byte-identical
into `lib/mabda.cyr` and removes the git-dep resolution. No new
ABI, no new language syntax, no new backend. Same shape as the
six v5.8.x sandhi folds.

**Decoupled from Class B FFI / wgpu fncall6 ABI**: that's the
*language-level* ABI work (held-forward through v5.9.x →
v5.11.x); stays in v6.4.x as a capability addition regardless
of whether the fold lands earlier. The mabda 3.0 GA fold can
proceed in v5.11.x **only if mabda 3.0 GA shipped without
needing the Class B FFI fix to be functional**. If mabda 3.0 GA
gates on the ABI work, both fold + ABI move together to v6.4.x.

**Slot-entry check**: at the moment mabda 3.0 GA cuts, re-verify
the Class B FFI gate per `feedback_premise_check_at_slot_entry`.
If GA works clean: fold here. If GA still leans on Class B FFI:
both move to v6.4.x. No mid-window auto-promotion.

Memory pin: `project_mabda_rc3_at_closeout`.

### v5.11.56 / v5.11.57 — Iron-boot session papercut close (filing `2026-05-16-iron-boot-session-papercuts.md`)

Four Low-severity surface-quality items filed 2026-05-16 from
the AGNOS iron-boot Attempts 37-38 + Repair R10 session on
`archaemenid` Beelink SER. None blocked the iron work (kernel +
`read-boot-log` both rebuilt clean). Split across two patches
by surface — user directive 2026-05-17. Slot-entry premise
check 2026-05-17 surfaced an Item 3 scope question (cross-arch
DCE cost ~200 LoC NEW for aarch64); user chose to ship the
wording-only contradiction fix in .56 and earn .58 as a real
engineering slot for the reachability filter.

**v5.11.56 — Build-diagnostic polish** (Items 2 + 3, cyrius
diagnostic-emitter surface):

- **Item 2 — LSP cross-file scope noise (REAL FIX)**: every
  edit on `agnos/` / `agnosticos/` source produced a wall of
  `✘ error: undefined function 'X' (will crash at runtime)`
  for stdlib fns resolved via `[deps.*]` (`strlen`, `println`,
  `args_init`, etc.). Root cause: `cyrius-lsp.cyr`'s
  `compile_and_capture()` forks **raw `cc5`** with source on
  stdin, NULL argv tail, NULL envp, LSP's cwd — cc5 has no way
  to see `cyrius.cyml` `[deps.*]` because that resolution lives
  in the `cyrius` wrapper. Fix: switch to forking the `cyrius`
  wrapper as `cyrius check --with-deps <filepath>` with cwd set
  to the project root (walk up from filepath looking for
  `cyrius.cyml`). Wrapper resolves `[deps.*]` naturally; the
  false-positive class disappears at the source instead of being
  softened. Keep raw-cc5 fallback for files outside any project
  tree. ~60 LoC in `programs/cyrius-lsp.cyr`. Single arch (LSP
  is x86 only).
- **Item 3 — `vec_get` "will crash" + `OK` contradiction
  (LIGHT FIX: wording downgrade)**: drop the `error:` + `OK`
  contradiction by reclassifying the fixup-time emit from
  `error: undefined function 'X' (will crash at runtime)` →
  `warning: undefined function 'X' (call site may be
  unreachable)`. Cross-arch x86_64 + aarch64 in same slot per
  `feedback_cross_arch_propagation_mandatory`. ~10 LoC across
  `src/backend/x86/fixup.cyr` + `src/backend/aarch64/fixup.cyr`.
  `--strict` mode hard-fail path (`_strict_mode == 1 →
  undef_count > 0 → exit 1`) preserved unchanged for CI use.
  The DCE-aware reachability filter (which would surface
  "warning" ONLY for truly-dead callsites and stay silent for
  reachable refs) is deferred to .58 as its own slot.
- Acceptance: self-host byte-identical, `check.sh` 75/75,
  `cyrius test` 150/150, fresh LSP smoke against `agnos/`
  source surfaces no `[deps.*]`-resolution false positives, and
  `cyrius build`/`cyrius build --aarch64` of `read-boot-log`
  emits `warning:` (not `error:`) with the `(call site may be
  unreachable)` qualifier.

**v5.11.57 — cc5-side pin-drift + shadow-content detection (Items 1 + 4 cc5 surface)**:

Premise check at .57 entry (2026-05-17) revealed Item 1's
root cause is layered: the wrapper at `~/.cyrius/bin/cyrius`
has been embedding `5.11.25` since 2026-05-12 because
`scripts/install.sh::_rebuild_stale` checks `build/$target
-nt $source` against `cbt/cyrius.cyr` only, missing the
transitive dependency on `src/version_str.cyr` (which
`cbt/cyrius.cyr` includes via `_VERSION_TOOLCHAIN`). Every
bump since copied the stale May-12 binary forward into each
snapshot. Consequence: `cyrius --version` reports `.25`
regardless of what pin or actual install version a consumer
has. **User direction 2026-05-17: split.** cc5-side detection
ships in .57 (works regardless of wrapper staleness because
cc5 is rebuilt every bump for self-host); wrapper polish
earns .58.

- **Item 1 (cc5 side)** — `src/frontend/lex.cyr` near
  `_check_shadow_lib`: new `_check_cyml_pin_drift()` reads
  cwd's `cyrius.cyml`, parses `[package].cyrius = "X.Y.Z"`,
  compares to cc5's compile-time `_VERSION_STR_CC5`. When
  pin exists AND pin != cc5 self-version, emit a loud
  `warning: cyrius.cyml pins X.Y.Z but cc5 is X.Y.W —
  toolchain drift (snapshot may be stale)`. Opt-out
  `CYRIUS_NO_WARN_PIN_DRIFT=1`; strict mode
  `CYRIUS_STRICT_PIN=1` exits with code 1 instead of
  warning (CI-gating path the wrapper's --strict-pin flag in
  .58 will set automatically). Cyml parser inline (mirrors
  `cbt/deps.cyr::_dep_read_cyml_cyrius_field` shape but in
  cc5 syntax). ~80 LoC.
- **Item 4 (cc5 side)** — `_check_shadow_lib` rewrite: today
  it just probes `lib/` directory existence and warns
  unconditionally. New shape: enumerate `./lib/*.cyr`, for
  each file with a counterpart in
  `~/.cyrius/versions/<cc5-version>/lib/`, compare BYTE
  SIZES (faster than content hash, catches the common
  drift). Emit the note only when at least one pair
  differs. Files unique to `./lib/` (project-specific code)
  are ignored — they're not shadowing anything. ~70 LoC.
- **NOT in .57** (split to .58): `cyrius lib sync` command,
  `cyrius --version` manifest-pin line, `--strict-pin`
  command-line flag, `scripts/install.sh` rebuild-staleness
  fix. These are wrapper-side; they need the wrapper to be
  current to work.
- Acceptance: self-host byte-identical, `check.sh` 75/75,
  `cyrius test` 150/150. Build of `read-boot-log` from
  `agnosticos/scripts/` emits the new pin-drift warning
  (pin .55 vs cc5 .57) and SUPPRESSES the shadow-lib note
  when the local `lib/` byte-matches the snapshot.

### v5.11.58 — Wrapper polish (wrapper rebuild fix + lib sync + --strict-pin + --version pin line)

Closes the wrapper-surface remainder of the iron-boot
papercut filing (Items 1 + 4 wrapper portions; cc5 portions
landed at .57). User direction 2026-05-17 split (3-slot
papercut close was the trade-off for not punting the wrapper
work into v6.x boundary cleanup).

**Scope** (~200 LoC total):

- **`scripts/install.sh` rebuild-staleness fix**: extend
  `_rebuild_stale` to track `src/version_str.cyr` as an
  explicit dependency of `cbt/cyrius.cyr` (and any other
  binary that includes it). Without this, future bumps
  continue to copy the stale wrapper into each snapshot.
  Alternative: have `version-bump.sh` explicitly `touch
  cbt/cyrius.cyr` (and other version_str.cyr consumers)
  after regenerating version_str.cyr so the `-nt` check
  triggers a rebuild. Pick whichever is cleaner; either
  closes the underlying bug.
- **`cyrius lib sync` command** (`cbt/cyrius.cyr` dispatch
  + new `cmd_lib_sync` in `cbt/commands.cyr`): copies
  `~/.cyrius/versions/<X>/lib/*.cyr` into `./lib/*.cyr`,
  where `<X>` = current toolchain version (or cyml pin if
  set). Third remediation alongside "delete ./lib/" and
  `CYRIUS_NO_WARN_SHADOW_LIB=1` from Item 4.
- **`cyrius --version` manifest-pin enhancement**: when run
  in a project tree (cwd has `cyrius.cyml` with
  `[package].cyrius`), append a second line `manifest-pin:
  X.Y.Z (project at $PWD)` to the existing `cyrius X.Y.Z`
  output. Helps consumers spot the mismatch the same moment
  they check what wrapper they're running.
- **`--strict-pin` flag** (and/or `[build] strict_pin =
  true` in cyrius.cyml): wrapper passes through to cc5 as
  `CYRIUS_STRICT_PIN=1` env var; cc5 (already shipped in
  .57) upgrades the pin-drift warning to a hard exit. CI
  pathway for consumers that want pin-faithful builds.

**Acceptance**: self-host byte-identical, `check.sh` 75/75,
`cyrius test` 150/150, fresh `version-bump.sh` cycle
produces a wrapper that reports the current version (not the
stale .25-era one), `cyrius lib sync` from
`agnosticos/scripts/` silences the shadow note on next
build, `cyrius --strict-pin build` in a pin-mismatched
project exits non-zero.

Issue file `2026-05-16-iron-boot-session-papercuts.md` →
`archived/` after .58 ships (.56 + .57 + .58 collectively
close Items 1-4).

### v5.11.59 — DCE-aware undefined-fn reachability filter (cross-arch engineering slot)

Bumped from .58 (now wrapper polish) per user direction
2026-05-17. .56 dropped the `error:` + `OK` contradiction
via wording-only downgrade (`warning: ... (call site may be
unreachable)`) — drops the false-alarm tone but still emits
for genuinely-reachable undef refs. .59 earns the precise
fix: query the call's host fn against the DCE reachability
bitmap; suppress the warning entirely when the host is dead.

**Scope** (~300 LoC total):

- **x86_64** (`src/backend/x86/fixup.cyr`): the DCE pass at
  line 325-642 already builds `live[512]` (4096-fn bitmap) via
  byte-scan of E8/E9 control transfers. Move the undef-fn
  check (currently at line 143-180, BEFORE DCE) to AFTER DCE.
  For each undef'd fixup, walk `fn_table` to find the host fn
  whose `[start, end)` contains the fixup's `coff` (same
  pattern as the DCE seed loop at line 483-492); skip the
  warning if `live[host_idx] == 0`. Preserve `_strict_mode`
  exit semantics (host-dead undef refs don't count toward the
  strict-fail count either). ~30 LoC delta.
- **aarch64** (`src/backend/aarch64/fixup.cyr`): NO DCE pass
  exists today. Add the reachability bitmap construction
  (~200 LoC NEW) mirroring x86's seed + propagate passes but
  with aarch64 instruction encodings:
  - BL (call):   top 6 bits `100101` → `0x94..0x97` mask
                 `op & 0xFC == 0x94` (little-endian byte 3).
  - B  (jump):   top 6 bits `000101` → `0x14..0x17` mask
                 `op & 0xFC == 0x14`.
  - rel26 → byte offset: sign-extend 26-bit imm, shift left 2.
  - 4-byte instruction stride (vs x86's variable-length).
  - Same hash-table optimization for `fn_start → fi` lookup
    (existing 0x114000 slot region; x86 sized for the same
    8192 cap — verify aarch64 reuse safety).
  - Sweep (NOP-fill with aarch64 NOP `0xD503201F`) gated on
    `CYRIUS_DCE=1` (same env var, same opt-in semantics).
- After both archs have `live[]` available, the undef-fn check
  reorder + host-filter logic is parallel: ~30 LoC delta on
  aarch64 to match x86.

**Cross-arch acceptance gate**: same `cyrius build` /
`cyrius build --aarch64` of `read-boot-log` (and a deliberate
synthetic test with reachable undef refs) emits the warning
ONLY for reachable callsites; the `vec_get`-style dead-ref
case is fully silent. cc5 self-host byte-identical on both
archs. The `note: N unreachable fns (M bytes — set
CYRIUS_DCE=1 to eliminate...)` line should now fire on
aarch64 too (it didn't before — confirms the new pass works).

Memory pin: `feedback_cross_arch_propagation_mandatory`
(same-slot cross-arch, not "x86 first / aarch64 follow-up"
half-fix).

Per `feedback_deferral_requires_roadmap_pinnage`, this slot
is pinned at .59 explicitly (re-pinned 2026-05-17 from the
prior .58 pin after the wrapper-polish slot earned .58).
If priorities shift again, the deferral must be re-pinned
with new acceptance bar — not silently slipped.

### v5.11.66 / v5.11.67 — Byte-array literal peephole (5× emit compression)

The v5.11.51 byte-array literal (`var foo[N] = { 0x.., ... };`)
ships with a 21-byte-per-byte emit cost: each byte init goes
through `EVADDR + EADDRA_IMM + EPUSHR + EMOVI + EPOPC + ESTORE8
+ EXORAA` (parser-side reuse of the existing `store8(...)` expr
path, same code shape the consumer would write by hand). For
gnoboot's UTF-16LE strings (~78 bytes each) and EFI GUIDs (16
bytes each, ~8 declared), the per-byte overhead adds ~1300 bytes
of `.text` per UTF-16 string + ~250 bytes per GUID.

Peephole optimization: emit `mov byte [rcx+disp8], imm8`
(opcode `C6 41 disp imm`, 4 bytes per byte) using a cached
`&var` in RCX once at the head of the init sequence. For
offsets 0-127 (covers all practical byte-array sizes), the cost
drops from 21 → 4 bytes per byte (**5× compression**).

Pinned at v5.11.66 / v5.11.67 — late in the absorber band, just
before the .68 closeout heap-map reorg. Tag .67 is the standard
pinnage; .66 is the runway slot for cross-arch propagation work
(aarch64 + cx need parallel peephole helpers, per
`feedback_cross_arch_propagation_mandatory`). If the cross-arch
work shrinks the peephole into a single slot, .67 stays
flexible / cycles into the absorber.

**Scope** (per the v5.11.55 refactor-survey item #5):

- New x86 named op `EMOV_BYTE_RCX_DISP8_IMM8(S, disp8, imm8)`
  → `C6 41 disp imm` (4 bytes).
- Equivalent aarch64 op (STRB Wn, [Xn, imm12]).
- Equivalent cx op (bytecode store-byte with imm).
- `EMIT_GVAR_INITS` byte-array-literal replay path emits the
  base `mov rcx, &var` once + the direct-store form per byte
  instead of the full expression machinery.
- Byte-identity verify: existing cc5 self-host (no byte arrays
  in compiler source) stays byte-identical. gnoboot binary
  shrinks visibly.
- Regression test: `tests/tcyr/byte_array_literal.tcyr` 26
  sub-asserts continue passing.

Memory pin: refactor-survey item #5 in CHANGELOG [5.11.55].
Acceptance bar: gnoboot rebuild against v5.11.66/.67 shows
`.text` reduction proportional to byte-array literal count.

### v5.11.68 — Heap-map full reorganization + CVE-05 (true closeout)

The last substantive engineering work before v6.0.0 opens.
Originally pinned 2026-05-05 at v5.8.61 ship as the documented
"last-minor-before-v6.0 effort"; re-pinned to v5.11.68 at the
2026-05-12 tight-close. **CVE-05 batched in at 2026-05-13** —
per-region overflow checks at str_data / tok_names / codebuf write
boundaries (P1, from
[`docs/audit/2026-04-13-security-audit.md`](../audit/2026-04-13-security-audit.md))
land alongside the reorg since both are heap-layout concerns and
the .68 surface already touches the same region-boundary
arithmetic.

**Why .68 and not .69**: v5.11.69 is reserved as the
**fold-applied tag** for any dep foldins that earn their slot
during the window (mabda 3.0 GA being the live candidate). If
no fold lands in the window, .68 is the final v5.x patch and
.69 is unused. If a fold lands, .69 = .68 + fold-applied
(byte-identical sandhi-pattern vendor of source, drop the
`[deps.*]` entry, regen). The .68/.69 split keeps the heavy
heap-map engineering and the conditional fold cleanly
bisectable.

**Remaining gaps post v5.8.61's minimum-blast-radius reorg**
(~22 MB of unused heap reserved as documented headroom):

- `0x41A000..0x44A000` (192 KB) — pad before preprocess_out
- `0xB4A000..0x114A000` (6 MB) — output_buf → struct_ftypes gap
- `0x115A000..0x11CA000` (450 KB) — struct_ftypes → struct_fnames
- `0x11DA000..0x128A000` (700 KB) — struct_fnames → fn_names
- `0x290B000..0x368C000` (13.5 MB) — **TS frontend functional
  reservation; DO NOT CLOSE** unless TS frontend is retired

**Closeable**: 8.4 MB across 4 gaps (excluding the TS reservation).

**Scope estimate** (per the v5.8.61 audit):

- ~200 references to shift across struct_*/fn_*/ir/fixup/tok
  region offsets
- ~750 references to relocate scratch state at
  `0x18C100..0x1A6018` if the band consolidates
- Total: 800-1000 edits across 20+ source files
- Two-step bootstrap audit at byte-identity criticality

Done as its own slot (not bundled) per cycle-discipline
("Big Heavy One Thing"). Substantial enough that bundling would
obscure the bisect target if anything regresses; the v5.8.61
minimum-blast pass already proved the safer per-region approach
is viable.

**Reference**: full audit data in v5.8.61 CHANGELOG entry +
`tests/heapmap.sh` output (84 regions documented).

### v5.11.69 — Conditional fold-applied tag

Reserved exclusively for dep-fold sandhi ceremony if a candidate
GA's during the v5.11.x window. Currently watching mabda 3.0
(see conditional slot above). Engineering work does NOT land
here per [cycle-discipline.md](cycle-discipline.md) cycle-close
shape; if no fold lands, .69 stays unused and .68 is the final
v5.x patch.

---

## What comes after v5.x

v6.x scope (PIE codegen, bare-metal formalization + RISC-V rv64,
language refinements, Class B FFI fold, cross-BB regalloc, items
lifted from long-term considerations) lives in
[roadmap-old.md](roadmap-old.md) under the v6.x sections, pending
pull-forward into this file at v5.x close. The v5.x → v6.x
boundary is clean: v5.x = "what the language IS"; v6.x = "new
platforms + advanced features the language gains."
