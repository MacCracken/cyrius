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
- [state.md](state.md) — volatile current state (version, cycc size,
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

### Shipped this cycle (v5.11.47 → v5.11.68)

Per-slot detail in [CHANGELOG.md](../../CHANGELOG.md). One-liner
ledger below; expanded narrative for shipped work lives in CHANGELOG
+ state.md per `feedback_doc_canonical_no_redundancy`.

**gnoboot AGNOS unblock arc (.47-.49, .51-.53)**
- **.47** — UEFI Application PE emit mode P1: `_TARGET_EFI_APPLICATION` flag, Subsystem 3→0xA, EEXIT EFI variant, ExitProcess import skip, `_pe_ensure_*` refactor (9 helpers → 1).
- **.48** — `programs/efi_probe.cyr` + structural gate (`_efi_emit_gate()`); check.sh 70 → 71.
- **.49** — OVMF runtime smoke + RELOCS_STRIPPED clear; arc CLOSED. AGNOS unblocked to start writing gnoboot proper against `cyrius = "5.11.49"`. Memory pin: `project_agnos_path_c_gnoboot`.
- **.51** — Byte-array literal `var foo[N] = { 0x.., 0x.., ... }`; new `EADDRA_IMM` named op + PARSE_GVAR_ARR extension. 26-assert tcyr.
- **.52** — `fn efi_main(handle, st)` entry convention + `CYRIUS_TARGET_EFI` predefine. Both gnoboot ergonomic filings closed same-day.
- **.53** — Hotfix: efi_main trampoline entry-save REX prefix 0x4C → 0x49 (MR-form REX.R vs REX.B for r14/r15-as-dst).

**Cycle infrastructure / polish (.50, .54-.55)**
- **.50** — Cap-drift detector + doc-size currency gates + fresh-tier doc refresh.
- **.54** — LSP papercut close + REX named ops + `_find_fn_by_name` helper; cycc first shrink in v5.11.x.
- **.55** — Refactor sweep — cap-drift gate extends to all 6 parse_*.cyr files; ESWITCH_DISPATCH_* named ops.

**Iron-boot session papercut close (.56-.59)**
- **.56** — Build-diagnostic polish: LSP `[deps.*]` resolution fix (raw cycc → wrapper); fixup-time wording downgrade error → warning + "(call site may be unreachable)".
- **.57** — cycc-side pin-drift + shadow-content detection (`_check_cyml_pin_drift()` + `_check_shadow_lib` byte-size compare).
- **.58** — Wrapper polish: version-bump rebuild fix (transitive `version_str.cyr` dep) + `cyrius lib sync` + wrapper `--strict-pin` + `--version` manifest-pin line.
- **.59** — DCE-aware undefined-fn reachability filter (cross-arch x86 + aarch64). aarch64 gained full DCE infrastructure for the first time. Pre-existing strict-mode parity gap acknowledged → pinned at .63.

**commandress papercut absorber band (.60-.63, all 4 slots shipped 2026-05-18)**
- **.60** — `lib/process.cyr` bug-fix pair (Items 6 + 7): `_exec3 var argv[4]` → `var argv[40]` byte-contract fix + stderr→/dev/null dup2 across vec-based `exec_capture`/`exec_env`/`exec_capture_str`/`exec_env_str`. New `tests/tcyr/process_run_capture_args.tcyr` (6 sub-asserts).
- **.61** — `lib/toml.cyr::toml_parse_file` heap-alloc rewrite (Item 2): 256 KB on-fn-scope buffer → `alloc()`; mirrors `toml_parse_file_r` v5.8.30. −256 KB bss in any consumer that includes `lib/toml.cyr`.
- **.62** — Compiler/tooling pair (Items 5 + 1): Item 5 reframed at slot entry after premise check (CYRIUS_DCE=1 NOPs `.text` only, doesn't shrink bss — empirically verified). Ships dead-fn `.bss` attribution hint via new `fn_var_bytes [8192]` heap region at 0x1C8000 + per-fn parser tracking; warning now shows "M bytes inside N unreachable fn(s)". commandress: 92 % of bss attributable. Drive-by 2-byte fix to pre-existing warning byte-count bug. Item 1: `cyrius init` bench scaffold uses real `bench_new` + `bench_batch_*` API + `bench` added to default `[deps.stdlib]`.
- **.63** — aarch64 `_strict_mode` parity (.59 retro follow-up): `_strict_mode` global + `/proc/self/cmdline` parsing added to all three `main_aarch64*.cyr` variants; `src/backend/aarch64/fixup.cyr` strict-exit mirrors x86 lines 729-738. Drive-by: wrapper `--strict` plumbing extended to BOTH archs (was absent for both pre-.63). Band CLOSED.

**v6.0 runway (.64-.67)**
- **.64** — agnos gvar-init-order fix: top-level `var X = INT_LITERAL ;` declarations now bake the literal into the file image at FIXUP-time via new `gvar_initval` / `gvar_byte_off` tables (cross-arch x86 + aarch64 + Mach-O + PE; cx opts out). Closes 10-iron-burn root-cause search; cycc SHRANK 2,384 B from eliminating runtime stores for cycc's own TS_TOK_* gvars.
- **.65** — CVE-05 split forward from .68: tok_names mangle-path write-boundary guard. 11 mangle sites (BUILD_METHOD_NAME / BUILD_OP_NAME / PARSE_FN_DEF module-mangle / variant-ctor × 2 / use-alias × 6 main_*.cyr variants) replaced magic-256 NPOS_GUARD with computed-source-length shape; 4 of the 6 main_*.cyr variants had no prior tok_names guard at all on the use-alias path. `_cve05_guard_gate` locks the magic-256 pattern out. check.sh 75 → 76. .68 stays a pure heap-map reorg.
- **.66** — Bridge-compiler retirement: `src/bridge.cyr` deleted (2,005 LoC). Audit confirmed bridge was never in active bootstrap chain (`seed → cybs → asm` is the real chain; cycc is built standalone). 150 `bridge::*` entries cleanly removed from `docs/api-surface.snapshot` via regeneration. CLAUDE.md Key Principle + project structure listing + util.cyr comment + ADR-001 historical note all updated. One v6.0.0 accompanying-refactor item absorbed into v5.x close.
- **.67** — Triple-pull bundle of v6.0.0 accompanying-refactor items (effectively a double-pull after premise-check at slot entry caught `cyrius build --strict` plumbing already shipped at v5.11.63): (1) `scripts/build-cycc-verify.sh` (~100 LoC bash) — formalizes the cycc byte-identical fixpoint verifier, ad-hoc one-liners now permanent; renames to `build-cyc.sh` at v6.0.0; (2) cc3-era residue cleanup — `docs/adr/005-two-step-bootstrap.md` rewritten with stage_a/stage_b convention (was using cc3/cc4 ambiguously throughout an active ADR), `docs/doc-health.md` vidya example syntax updated, `roadmap-old.md` self-references marked done. README also updated for the post-bridge bootstrap chain. Byte-array literal peephole moved out to v6.0.x per user direction "put the pinned byte-array into 6.0.x line of work now."
- **.68** — Heap-map full reorganization (true closeout engineering work): closes all four documented closeable gaps from the v5.8.61 minimum-blast-radius pass — 2.24 MB + 6 MB + 448 KB + 448 KB = 9.06 MB reclaimed. brk shrinks 0x56AD000 → **0x4D9D000** (-9.06 MB / ~77.6 MB total heap, was ~86.6 MB). 13.3 MB TS frontend reservation preserved. Cascade across four groups: codebuf + output_buf (-2.24 MB) → struct_ftypes (-8.19 MB) → struct_fnames (-8.62 MB) → 25+ regions through preprocess_out (-9.06 MB). ~32 distinct hex constants replace_all'd across 20 src/ files. Windows MMAP shrunk 0x5800000 → 0x4F00000. cycc byte-identical at 874,232 B; cross-arch unchanged. heapmap.sh: 99 regions, monotonic 0x00000 → brk except single TS reservation.

Issue file `2026-05-17-commandress-stdlib-papercuts.md` archived after .63 ship; .64 absorbed the agnos gvar-init-order fix, .65 shipped CVE-05 split forward from .68 (tok_names mangle-path guard; per-region overflow checks). v6.0-runway scope confirmed at .65 entry per user direction 2026-05-19 "start the march to 6.0".

---

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

### mabda 3.0 GA fold — dropped from v5.11.x (2026-05-19)

User direction at .67 ship: "no mabda fold". The conditional
fold that was originally pinned for v5.11.69 (gated on mabda
3.0 GA cutting + 24-hour soak passing) is no longer in scope
for v5.11.x. mabda stays as a git `[deps.*]` resolution
through v6.x or until the fold is re-pinned in a future cycle.

Class B FFI / wgpu fncall6 ABI work continues to track in
v6.4.x as previously pinned — that decision is independent of
the fold dropping.

### Byte-array literal peephole — moved to v6.0.x (2026-05-19)

The v5.11.51 byte-array literal peephole (5× emit compression
for `var foo[N] = { ... }` init via `mov byte [rcx+disp8], imm8`)
was originally pinned at v5.11.66 / v5.11.67. Per user direction
2026-05-19 ("put the pinned byte-array into 6.0.x line of work
now"), the work moved out of v5.11.x and into v6.0.x — it's
optimization-shape, not v5.x close-out shape. Scope + cross-arch
plan preserved in `docs/development/roadmap-old.md` under v6.x.

The .66 + .67 slots that held it shipped other v6.0-runway
items instead: .66 retired `src/bridge.cyr`, .67 shipped the
build-cycc-verify.sh + cc3-era residue triple-pull
(double-pull post-premise-check).

### v5.11.68 — Heap-map full reorganization (true closeout)

The last substantive engineering work before v6.0.0 opens.
Originally pinned 2026-05-05 at v5.8.61 ship as the documented
"last-minor-before-v6.0 effort"; re-pinned to v5.11.68 at the
2026-05-12 tight-close. **CVE-05 was unpinned from this slot at
v5.11.65** — the audit at slot entry confirmed earlier work
(CVE-06 + `EB` + `NPOS_GUARD`) already covered the bulk of the
write-boundary surface, and the remaining tok_names mangle-path
gap was orthogonal to the heap-map layout reshuffle. .68 now
stays a pure layout reorg per "Big Heavy One Thing" — the .65
ship handles the write-side checks; the long-term
`mmap`-with-guard-pages split tracks separately for v6.x.

**Why .68 and not .69**: .68 is the Big Heavy heap-map
engineering; .69 is reserved as **another v6.0-runway item**
(user direction 2026-05-19 after .67 ship: "no mabda fold and
we will make .69 another pre 6.0 item"). The split keeps the
heap-map reorg cleanly bisectable from whatever .69 absorbs.

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

### v5.11.69 — Another v6.0-runway item (TBD at slot entry)

Continues the .64-.67 v6.0-runway thread. User direction
2026-05-19 retired the original conditional mabda-fold framing:
"no mabda fold and we will make .69 another pre 6.0 item."
Candidate selection happens at slot entry per
[`feedback-no-unilateral-scope-decisions`] — pool drawn from
[roadmap-old.md](roadmap-old.md) § v6.0.0 accompanying-refactor
+ closeout list (dead-code careful sweep, vidya bulk refresh,
security re-scan, downstream check, or another candidate
surfaced during the .68 ship).

Mabda 3.0 fold is **dropped from v5.11.x entirely** — stays as
a git `[deps.*]` resolution through v6.x or until re-pinned in
a future cycle. Class B FFI / wgpu fncall6 ABI work continues
to track in v6.4.x as previously pinned.

---

## What comes after v5.x

v6.x scope (PIE codegen, bare-metal formalization + RISC-V rv64,
language refinements, Class B FFI fold, cross-BB regalloc, items
lifted from long-term considerations) lives in
[roadmap-old.md](roadmap-old.md) under the v6.x sections, pending
pull-forward into this file at v5.x close. The v5.x → v6.x
boundary is clean: v5.x = "what the language IS"; v6.x = "new
platforms + advanced features the language gains."

### v6.x review queue (noted-not-pressing for v5.11.x)

Items surfaced during the v5.11.x cycle that don't warrant
in-cycle action but should be reviewed at v6.0.0 cycle-open
when the broader v6.x roadmap is pulled forward.

- **Self-compile time growth audit** (surfaced 2026-05-18
  doc-health sweep, framing adjusted per user direction same
  day): `bench-history.sh` tier-3 shows self_compile **244 ms
  → 404 ms (+160 ms / +65 %)** between commits `a17a8de`
  (2026-04-18, post-v5.10.50) and `f60ec9b2` (2026-05-18,
  post-v5.11.63). The 1-month / ~30-patch baseline spread is
  itself the tell that this is **growth, not regression**.
  Window covers: stdlib annotation arc (.0-.7), TS test
  harness (.11), parser-to-emit named-op refactor (.35-.39),
  ELF section header arc (.29-.34), byte-array literal (.51),
  UEFI Application emit mode (.47-.49 + .52-.53), DCE-aware
  reachability filter cross-arch (.59 — full aarch64 DCE
  pass, ~200 LoC NEW), per-fn array-bytes attribution parser
  tracking (.62), aarch64 `_strict_mode` parity (.63). Averages
  to roughly +5 ms/patch of in-cycle feature work — expected
  for the kind of work shipped (more parser tracking, more
  dispatch checks, more cross-arch propagation). **Growth tax
  to evaluate, not regression to bisect**: cycc binary grew
  only +1,072 B over the same window, so the cost is
  parse/codegen overhead, not output bloat.
  **Likely shape at v6.x review**: v6.x adds its own growth-
  creating surfaces (PIE codegen, bare-metal + RISC-V rv64,
  Class B FFI, language refinements) so the audit moves
  late in the v6.x cycle once those have landed and the new
  baseline is established. Form factor likely a **dedicated
  perf-refactor minor** (vs the v5.10.40/.41 2-slot miniarc
  inside a regular minor) — too much accumulated surface
  across 5.x + early-v6.x to clean up in 2 slots, and a
  whole minor lets the refactor breathe without bumping
  capability work. First step at audit: capture intermediate
  datapoints via on-quiet-box `bench-history.sh` runs so the
  trend has more than 2 endpoints; gradual-accretion vs
  one-patch-dominates determines whether bisection is even
  productive (gradual is the likelier shape given the work
  mix).
