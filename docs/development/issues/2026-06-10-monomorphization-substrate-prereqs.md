# v6.3.x generics prerequisites — substrate is missing — AR-01/02, CO-01, AR-04

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High (these are prerequisites the v6.3.x plan *assumes exist*, not
enhancements — surfacing before the minor opens, per premise-check discipline)
**Affects:** cycc front-end + fixed-heap model 6.1.31. Bears on the v6.3.x
monomorphization slot (~7 slots) and the v6.4.x cross-BB regalloc slot.

## AR-01 — monomorphization has no working substrate (P1)

Generics currently erase via `SKIP_GENERICS` (`parse_fn.cyr:1191`; 6 call sites
in `parse_decl.cyr`). The only call-site re-parse mechanism the no-AST single-pass
design ever had — inline token replay via `fn_body_start/end` (`SFBS/SFBE`,
`parse_fn.cyr:2226-2245`) — is **dead**: `_INLINE_OK=0` on x86 (`emit.cyr:166`)
and aarch64 (`emit.cyr:2090`), disabled after ARM metadata-corruption. So the
"emit-time substitution generates per-monomorph code" plan (`roadmap_6.md:308-317`)
has no substrate to build on.

**Fix:** re-scope v6.3.x generics with an explicit **phase 0** — revive and harden
token replay (per-arch, with the ARM metadata-corruption root cause understood),
prove it on inline fns first, then build substitution on top. Pair with the
growable fn-table migration below.

## CO-01 — forward calls get zero ABI metadata (silent miscompile) (P1)

`PARSE_FNCALL` on an unseen fn auto-registers a bare name (`parse_fn.cyr:730-731`)
and reads ABI metadata at call time — Str-param mask (`:949`), SIMD mask (`:957`),
struct-ret (read at `parse_decl.cyr:1218,1437,1622`) — but these are only
**written** at fn-def parse (`:2036`). A call lexically before the definition (same
file or wrong include order) emits with mask 0: no Str auto-coercion, no SIMD
routing, silently wrong at runtime, with no diagnostic. Pass-1 prescan makes
globals/structs/enums order-independent (`main.cyr:1097-1113`) but deliberately
not fn signatures. The guide (`cyrius-guide.md:63`) *promises* forward calls work.

This is a **hard prerequisite for AR-01**: generic instantiations reference each
other in arbitrary order, so order-dependent ABI metadata miscompiles them. It is
also a public-v7 trap — C-style bottom-of-file definitions are natural and
currently miscompile silently.

**Fix:** add fn-signature capture to the pass-1 token prescan (name + param
annotations + return type are syntactically scannable without emitting), making
call ABI order-independent like structs already are. Interim: warn at fn-def time
when an annotated fn has prior call sites (warning at every auto-register would
spam, since forward calls are ubiquitous).

## AR-02 — fixed-heap tables vs monomorphization growth (P2)

cycc has linked `lib/alloc`+`lib/vec` since v6.0.6 and migrated `ret_patches` to
a growable `rp_vec` at v6.0.7 with self-host staying byte-identical
(`main.cyr:442-460`) — growable regions do **not** break determinism (output
embeds no compiler heap addresses; allocation order is input-deterministic).
Meanwhile cap-raises run ~1/minor (str_data/codebuf/output_buf) and
monomorphization is the forcing function (N instantiations × per-monomorph fn
entries + codebuf + fixups).

**Fix:** before v6.3.x opens, migrate the three pressure tables (fn tables,
`fixup_tbl`, codebuf) to vec-backed storage using the `rp_vec` recipe; keep the
fixed map for scalars/scratch (perf-positive). Wire `CYRIUS_STATS` utilization
into bench-history so headroom is visible. Resolves the AR-03 fixup-cap
split-brain (see [memory-safety-parity-gaps](2026-06-10-memory-safety-parity-gaps.md))
as a side effect.

## AR-04 — v6.4.x regalloc substrate decision (P3)

Today's "regalloc" is a post-body pass that byte-scans emitted x86 for mov
patterns, builds live intervals from machine bytes, NOP-patches, then compacts
with jump/fixup repair (`parse_fn.cyr:2352-2735`) — x86-only (`:1394`), 5
callee-saved regs no spilling (`:1406`), 4 on x86-macho (`:1407`, the v6.1.30 r15
reserve). The v6.4.x cross-BB regalloc is scoped onto this byte-archaeology
substrate.

**Fix:** make the substrate call **at v6.4.x entry, not mid-arc** — either (a)
accept the peephole ceiling and scope cross-BB work as IR-analysis feeding byte
patches (cheap, stays x86-only, widens the aarch64 perf gap — A64 has no auto
regalloc / no jump tables), or (b) activate real IR-level register allocation
(larger, but the only path to aarch64/riscv64 regalloc parity).

## Acceptance gates (currently absent)

The generics scope has **no** perf/caps acceptance bar, unlike the optional-deps
item (`roadmap_6.md:398-405`), and the v6.5.x perf-refactor lands two minors
*after* the likely compile-time blowup. Give the v6.3.x generics slot explicit
gates: a self_compile delta budget, cap-headroom checks with pre-sized raises,
and instantiation-dedup as an acceptance criterion.

## Status

Filed 2026-06-10. AR-01 + CO-01 + AR-02 are v6.3.x-open prerequisites; AR-04 is a
v6.4.x-entry decision. Premise-check these at the respective slot entries.
