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
