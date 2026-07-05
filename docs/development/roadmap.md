# Cyrius Development Roadmap — v6.4.x (active minor)

**Scope** — the **current active minor only** (v6.4.x). This is the
slot-pinning working artifact: the committed opening sequence + a **conservative,
code-grounded length map** for each remaining arc. The fuller per-arc design, the
rest of the cycle (v6.5.x → v6.6.x), and the closed-minor summaries live in
[roadmap_6.md](roadmap_6.md); everything beyond v6.x is in
[roadmap-future.md](roadmap-future.md).

> **Reading order**: this file (active-minor pins + length map) →
> [roadmap_6.md](roadmap_6.md) (full v6.x cycle + fuller per-arc design) →
> [roadmap-future.md](roadmap-future.md) (v7+ watching list).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** (framing, per-arc
  design, the closed v6.0.x/v6.1.x/v6.2.x/v6.3.x summaries).
- [roadmap-future.md](roadmap-future.md) — long-term / v7+ watching list.
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles
  (slot acceptance, premise-check at slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size, in-flight slot).
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.4.x — ABI / Language-Features arc

**Opened** at the v6.3.45 → v6.4.0 cut (2026-07-03). The v6.3.x language-refinement
minor (closures / generics / async / native-float, plus the deps-model, bare-metal,
perf, and cross-OS-hardening arcs) **closed at v6.3.45** — its whole slot table is
canonical in [CHANGELOG.md](../../CHANGELOG.md) and summarized in
[roadmap_6.md](roadmap_6.md); it is intentionally not repeated here.

**Shipped so far in v6.4.x:**

- **v6.4.0** — `CYRIUS_MONOMORPH` **default-on flip**: generics are now a default-on
  language feature (`CYRIUS_MONOMORPH=0` opts out). Byte-identical (cycc has no
  generic fns); needed the `_INLINE_OK` decouple + the GFTP-gated frame-trim.
- **v6.4.1** — `alloc_reset()` **zero-on-reset**: closed a CVE-2026-34988-class
  memory-reuse info-leak in all four allocator backends.
- **v6.4.2** — agnos **`sys_snd_*` audio syscall band (#64–#69)**: the ring-3 half of
  the agnos 1.52.x Gate-2 audio freeze (unblocks vani + cyrius-doom).

**The committed opening sequence** (ORDER fixed by user 2026-07-03; the design
decisions *inside* each arc are chosen at arc-open — only the order is committed):
**integer SIMD → array-typed struct fields → UEFI Secure Boot signing → function
visibility**, with the **Intel-Mac (x86_64 Mach-O) toolchain arc** at the tail.

---

## Conservative length map (arc-scoped against the code, 2026-07-04)

Each arc was scoped against the actual tree (not the proposal's optimistic framing).
The estimates lean **high** — a feature touching the type system / codegen / ABI is
multi-release and grows a repair tail (the generics precedent: .9 → .39 + the .0
flip, with deep-ABI repairs still surfacing at .37/.38/.39). **Sizes are `.NN`
releases, each bundling several bites. Minors flex long.**

| # | Arc | Conservative length | Release-blocker? | Status |
|---|-----|--------------------:|:----------------:|--------|
| 1 | **Integer SIMD** (ML/AI) | **5–7 releases** | No | **PINNED — immediate** |
| 2 | **Array-typed struct fields** | **3–4 releases** | No | **PINNED — immediate** |
| 3 | **UEFI Secure Boot signing** | **3–5 releases** | No | order-committed |
| 4 | **Function visibility** (`pub`/`private`) | **4–6 releases** | No | order-committed |
| T | **Intel-Mac (x86_64 Mach-O) toolchain tail** | **2–4 releases** | No | committed tail |

**Opening sequence total: conservatively ~17–26 `.NN` releases** — v6.4.x is a **long
minor**. **None of the five arcs is a release-blocker.** On top of the arcs, **reactive
agnos + consumer-filed repairs interleave throughout** and consume **separate** slots
that are **not** counted above (3 already this minor: .1 alloc_reset, .2 agnos audio,
and .0's own de-risking) — see *Reactive headroom* below.

---

## PINNED — immediate work

### Pin 1 — Integer SIMD (arc opener, ML/AI priority) — ~5–7 releases

`iNxM` typed integer vectors + int8/16/32(/64) lane ops + the quantized-ML
primitives (widening multiply-add, sign-select, horizontal reduce). Cyrius SIMD is
**f64-only** today (`lib/simd.cyr` = `f64v2`/`f64v4`); there are no integer vector
types, capping every int/quantized/bit kernel at scalar speed — the direct blocker
for quantized-ML throughput (tentib b1.58 inference, attn11/tarka int paths, sankoch
compression, int8/16 DSP, edge/Pi tok-s). Follows the v5.10.x typed-**f64** SIMD arc
precedent — but that was a ~50-patch combined arc, and this is **8 vector types with
new integer semantics vs f64's 2 with native FP ops**, so "just mirror f64"
understates it.

- **▶ IMMEDIATE FIRST STEP (the pin): decide the type-class ENCODING — before any
  emit code.** The current `-20`/`-21` pscale sentinels + the **2-bit-per-param SIMD
  mask** physically cannot encode 8 integer vector types; that fork drives the whole
  arc (the way the array-field representation fork drives Pin 2). **Second pin:** agree
  the **minimal-op cut** (int8 load + sign-select + int16 widening-accumulate +
  hreduce) so the *first* release ships tentib-0.4.1-unblocking scope, not the full
  lane-op matrix.
- **Phases**: (0) encoding + minimal-op decision → (1) one lane width end-to-end on
  x86 (prove the encoding scales) → (2) core lane ops + the quantized-ML primitives,
  x86, bench-gated → (3) fill out the i8/i16/i32/i64 × 128/256-bit matrix → (4)
  aarch64 NEON parity (sdot/smlal) + cx stubs + PE gating → (5) `lib/simd.cyr`
  wrappers + tentib 0.4.1 integration bench → (6) repair tail (budgeted, 1–2).
- **Risks**: the 2-bit param mask + `-20/-21` sentinels are a hard scaling wall
  (silent mis-encoding class, cf. the v6.3.36 struct-mask); the builtin token-ID space
  is near-saturated (needs a new dispatch scheme); integer-only semantics (saturating,
  signed/unsigned per width, widening-madd overflow) have **no f64 template** and are
  exactly where sign-ext/truncation bugs hide; VNNI/sdot availability varies per arch;
  bench-gated acceptance means a correct-but-slow first cut doesn't satisfy the
  consumer. Cross-repo: tentib 0.4.1 is the acceptance bench (separate repo).

### Pin 2 — Array-typed struct fields — ~3–4 releases

Make `struct { field: T[]; }` / `field: T[N]` **parse, represent, access, and
derive-serialize**. Today it's a hard parse error ("expected identifier, got `[`");
variable-length data is an untyped `Vec` (i64-only). This is the "array half" of the
`#derive(Serialize)` codec (the f64 *scalar* half shipped v6.3.40) and unblocks
tables/lists in structs generally.

- **▶ IMMEDIATE FIRST STEP (the pin): decide the field REPRESENTATION —
  inline-fixed-array `T[N]` vs a typed `Vec<T>` handle — FIRST.** That fork drives
  everything downstream (layout, `struct_ftypes` widening, field-access codegen, the
  derive). **Hold dynamic `Vec<T>` element-typing OUT of the initial pin** (Vec is
  i64-only today; typing its elements is its own multi-release generics sub-arc) —
  keeping it out is what holds this arc to 3–4.
- **Phases**: (1) struct-field parser accepts `field: T[]`/`T[N]` → (2) the
  representation + layout (`struct_ftypes` needs element-type + count, likely a new
  metadata table across all `main_*` forks) → (3) field-access codegen, cross-arch →
  (4) the `#derive(Serialize)` array codegen across the 3 codec fns.
- **Consumers**: svara (~40 serde types + a 101-row phoneme table) is blocked on this;
  naad/vidya dropped round-trip tests. Tier B (`toml_v_*` typed DOM in bayan) is a
  **separate stdlib** item, not part of this arc.

---

## Order-committed (length-blocked, not yet pinned)

### 3 — UEFI Secure Boot signing — ~3–5 releases · NOT a release-blocker

Give the sovereign toolchain a **`cyrius sign-efi`** path (Authenticode-sign a
`CYRIUS_TARGET_EFI` PE) + EFI key-enrollment artifacts. Consumer-filed by **gnoboot**
(the sovereign UEFI bootloader). **Premise-check first — much already exists:** the
RSA/X.509/SHA-256 crypto floor **and** the PKCS#7/CMS + Authenticode PE-hash +
attr-cert-embed packaging are **already shipped in sigil 3.10.0** (`src/authenticode.cyr`,
KAT-tested, already folded into `lib/sigil.cyr`) — the proposal's "packaging is
missing" framing is stale.

- **Real gaps**: (A) **cyrius side** — the entire driver surface is net-new
  (`sign-efi`/`efi-keys`/`efi-sigdb` in `cbt/cyrius.cyr`, or a standalone
  `cyrsign-efi`): a thin glue over the shipped sigil core. (B) **sigil side** — P3
  (`EFI_SIGNATURE_LIST` `.esl` + `.auth` generation) is 0 files; P4 (Authenticode
  *verify*) is mostly re-assembly; X.509 *issuance* for `efi-keys` may be genuinely new.
- **▶ First step**: pin driver-subcommand-vs-standalone, then **confirm P1 round-trips
  against a real `OVMF_CODE.secboot.fd` boot** (not just the openssl KAT) — that one
  experiment says whether P1 is a thin-glue release or hides a PE-layout repair tail.
- **Notably cheap tail**: this arc touches **zero compiler codegen/ABI** → no
  cross-arch propagation cost and no deep-ABI repair tail (the 4-host self-host +
  seed-derive still run, but changes are lib/CLI-only, cycc byte-identical). Cross-repo:
  split cyrius (driver) + sigil (P3/P4/keygen, each folded back via `cyrius deps` +
  api-surface regen). Downstream gnoboot/agnova Secure Boot is post-v1.0 → not a blocker.

### 4 — Function visibility (`pub`/`private`) — ~4–6 releases · NOT a release-blocker

Execute "Phase 2 — `pub` enforcement" of
[`module-manifest-design.md`](module-manifest-design.md): close the flat-global-namespace
bug classes (the `dynlib_*` dead-code corruption, enum-shadow, slot-collision) and make
the api-surface snapshot compiler-enforced. Runs long because it's a **retrofit onto a
flat namespace + a real cross-ecosystem migration**.

- **▶ First step (the arc-open gate): the `_`-prefix cross-file-call audit.** Already
  run for cyrius-internal here — **165 distinct `_`-fns are called cross-file** (253
  pairs; 52 in `lib/` are cohesive-subsystem internals like `_tn_*`/`_uc_*`/`_alloc_*`),
  and sigil alone has 703 `_`-defs. **This DISPROVES "derive-from-`_` = zero-churn"** →
  the forced decision: a **HYBRID marker** (`_` default + explicit `pub`/`private`
  override) and **default = PUBLIC** (additive/byte-identical; reject default-private).
- **Phases**: (0) `_`-audit + decision lock → (1) the **per-fn file-id substrate** (new
  preprocessor infra + `_fnt_fileid` across all 7 `main_*` forks — the real work,
  byte-identical) → (2) `fn_flags` bit-6 + WARN-mode enforce → (3) the ecosystem
  migration (add `pub`/rename cross-file `_`-callees; cyrius first, then 14 downstream
  repos via `cyrius deps`, sigil heaviest) → (4) flip to hard-error + feed DCE + prove
  the win → (5) docs/close.
- **Risks**: HIGH-churn — subsystem-spanning `_` helpers (tls-native, unicode,
  alloc-backends) mean file=module is too fine a unit; a mis-stamped file-id → silent
  false-positive rejections; late-ABI repair tail (file-id × monomorph instances,
  use-aliases, `GMOD` mangling); two enforcement sites (`PARSE_FNCALL` + the tail-call
  path — easy to miss one). Cross-repo migration is a big part of why it runs long.

### T — Intel-Mac (x86_64 Mach-O) usable-toolchain tail — ~2–4 releases · NOT a blocker

Runs at the **v6.4.x tail** (moved 2026-07-03). Phase 1 (argv prologue) shipped
v6.1.30; remaining `ach`-gated layers: env reading (`HOME`/uname), wrapper macOS
arch-default, cycc-finding, the layer-6 native self-compile miscompile (tools ship
cross-built until fixed), packaging. `ach` is the supported macOS-x86 verify host.
[`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md).

---

## Reactive headroom — agnos + consumer repairs (interleave throughout)

Agnos ABI mirrors + consumer-filed repairs land as **separate slots between/alongside
the arcs** — they are **not** counted in the arc lengths above, and they follow the
bare-metal open-window pattern ([[feedback_bare_metal_open_reactive_window]]). This
minor has already absorbed three (`.0` de-risk, `.1` alloc_reset, `.2` agnos audio),
and **more agnos work is expected**: the audio consumers (vani's agnos backend,
cyrius-doom's `audio_write` retarget) will surface follow-ons, and the syscall-peer /
freelist-agnos / thread-backend pattern (v6.3.31, v6.4.2) continues as agnos 1.5x lands
kernel features. Budget for it; don't wedge it into an arc. **Only the user re-scopes
or re-prioritizes** ([[feedback_no_unilateral_scope_decisions]]); findings are surfaced,
never unilaterally deferred or redirected.

## Carry-in / watching (open, not in the committed sequence)

- **VR-03/04 differential + platform-lint residuals** — as surfaced (the VR-01 LIBTEST
  gate is now standing on ecb/cass/pi).
- **Consumer-gated**: cyim regex unblock (lands when cyim re-tests against v6.x);
  sandhi RPC-policy TLS-slot OOB
  ([`issues/2026-07-01-sandhi-rpc-policy-tls-slot-oob.md`](issues/2026-07-01-sandhi-rpc-policy-tls-slot-oob.md));
  the `thread_local_alloc()` allocator follow-up.
- **v7-PARKED (NOT near-term)** — LEGAL-01 licensing, DWARF/diagnostics,
  stdlib-reference docs, incremental compilation, the public-release decision. These
  stay in [roadmap-future.md](roadmap-future.md); they are **not** pulled into v6.4.x.

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

Premise-check each arc at slot entry ([[feedback_premise_check_at_slot_entry]]) — the
UEFI arc is the live example (crypto already shipped in sigil). Cross-arch propagation
is mandatory for any compiler-emit change ([[feedback_cross_arch_propagation_mandatory]]);
4-host cross-OS self-host verify before **every** cut, even lib-only
([[feedback_cross_os_verify_always_even_lib]], [[reference_verification_hosts_ssh]]);
seed-derive after any `src/` change ([[feedback_seed_derive_mandatory_cybs_limits]]);
benchmark every release ([[feedback_benchmark_every_release]]); one bug ships complete
([[feedback_one_bug_one_complete_fix]]). The minor window is open to change
([[feedback_minor_window_at_arc_open]]) — minors flex long, and this one especially.
