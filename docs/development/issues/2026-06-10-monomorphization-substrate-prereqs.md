# v6.3.x generics prerequisites — substrate is missing — AR-01/02, CO-01, AR-04

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High (these are prerequisites the v6.3.x plan *assumes exist*, not
enhancements — surfacing before the minor opens, per premise-check discipline)
**Affects:** cycc front-end + fixed-heap model 6.1.31. Bears on the v6.3.x
monomorphization slot (~7 slots) and the v6.4.x cross-BB regalloc slot.

## Premise-check resolution (v6.3.5 entry, 2026-06-28) — PLAN BANKED, no code yet

Premise-checked at v6.3.5 slot entry. **The roadmap's fear that AR-01 may be
"un-revivable" is wrong — it is FEASIBLE.** User decisions: AR-01 = **gated proof**
(revive + prove the substrate byte-correct cross-arch via a gated mechanism/test,
**NO default codegen change**); execution = **full push** (CO-01 then AR-01 as
v6.3.5). Full carry-forward plan in memory `project_v635_substrate_plan`.

**AR-01 — the token-replay EMIT path is INTACT** (`parse_fn.cyr:986-1044`); only
the CAPTURE side is off (`_INLINE_OK=0` in x86/emit.cyr:161, aarch64/emit.cyr:2242,
cx/emit.cyr:49+782; capture site parse_fn.cyr:2371-2396). **Both disables are
benign for monomorphization:** x86 disabled in commit 6f82f29f (v1.11.3) purely
because inlining made code *bigger* (irrelevant — monomorph wants per-instance
code); aarch64 was the old 0x2C8000 heap overlap, tables since RELOCATED to
S+0x9EA000 (now in the safe fn-table family 0x93A000–0xA2A000 aarch64 uses every
compile → corruption is STALE). v6.3.5 = re-enable capture under a monomorph
flag + prove byte-correct on x86 + REAL pi. Type-substitution (NOVEL — no current
hook) + forward-ref + N-param generalization → **deferred to v6.3.7**.

**CO-01 — exact plan** (lands first; the hard AR-01 prerequisite): (1)
`_classify_param_type(S,tnoff)` extracts the param type-name byte-compares
(parse_fn.cyr:1947-2049) → class 0-7; (2) refactor PARSE_FN_DEF's param loop to
use it (logic-preserving → verify byte-identical); (3) `_prescan_fn_sig(S)` =
REGFN + scan params via the helper → write the 6 masks (parse_fn.cyr:2181-2192) +
return-type, skip body; (4) wire into all 7 forks' pass-1 prescan (replace the
inline fn-skip at main.cyr:1212-1228 etc. with a one-line call); (5) test a
forward call to an annotated fn; (6) cross-arch + seed-derive. **Byte-identity
risk:** pass-1 REGFNing all fns may change fn-index order vs pass-2-only — verify
self-host stays byte-identical.

## AR-01 — monomorphization has no working substrate (P1) — SUBSTRATE REVIVED v6.3.5 (gated proof)

**RESOLVED v6.3.5 (Phase 0, gated proof — no default codegen change).** The fear
that the token-replay substrate was un-revivable was wrong. The emit-time replay
path (`PARSE_FNCALL`, the `GFINL != 0` branch — eval args → store to param slots →
re-seat the cursor to `GFBS` → `PARSE_PROG` the body → patch returns) was always
INTACT; only the body-token CAPTURE was off (`_INLINE_OK = 0` per backend, x86
disabled for code SIZE at v1.11.3, aarch64 for a metadata overlap since relocated).

v6.3.5 adds an opt-in `_MONOMORPH_OK` flag (util.cyr, default 0; set by
`CYRIUS_MONOMORPH=1` in all 7 drivers) that ORs into the two capture gates in
PARSE_FN_DEF. With it off, codegen is **byte-identical** (verified: the AR-01
compiler emits the same self-host binary as the pre-AR-01 compiler; x86 self-host +
seed-derive + cross-OS pi/ecb/cass SELFHOST_OK). With it on, the capture fires and
the intact replay produces per-call-site code. Proven byte-correct + active by
`programs/checks/_monomorph_substrate_gate` (`tests/fixtures/monomorph/inline_proof.cyr`
compiled with/without the flag — both exit 42, binaries differ; check.sh 103→104)
AND on REAL aarch64 (pi): the re-enabled aarch64 capture inlines byte-correct (the
old metadata corruption is gone — tables relocated to the S+0x9EA000 fn-table family).

This proves the **value-replay** substrate. The NOVEL parts — TYPE substitution
(generics emit per-instance code with the type parameter bound), forward-ref
instantiation, and generalizing past the inliner's ≤2-param / ≤16-token ceiling —
are **deferred to v6.3.7**, building on this proven base.

## AR-01 — monomorphization has no working substrate (P1) — original analysis

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

## CO-01 — forward calls get zero ABI metadata (silent miscompile) (P1) — RESOLVED v6.3.5

**RESOLVED v6.3.5.** A pass-1 fn-signature prescan (`_prescan_fn_sig` in
`parse_fn.cyr`, wired into all 7 forks' pass-1 in place of the old inline fn-skip)
now REGFNs every top-level fn AND records its ABI metadata before pass-2 emits any
call. Shared classifiers `_classify_param_type` / `_classify_return_type` (extracted
from PARSE_FN_DEF, byte-identical refactor) keep the prescan and the pass-2
definition in lockstep. The prescan extracts on a throwaway cursor then resets and
replays the verbatim pre-CO-01 skip, so pass-1's net token-cursor advancement is
unchanged — the only new effect is the early registration + masks.

**Covered (verified by `tests/tcyr/forward_call_abi.tcyr`, old cycc fails / new
passes):** forward calls to `: Str` / cstring / Result / Option / Tagged / SIMD-param
fns (auto-coercion + arg routing) and to `: Struct`-returning fns with an explicit
local annotation (`var p: T = mk()` — the retptr ABI). Self-hosts byte-identical on
x86 + aarch64 (pi) + macOS (ecb) + Windows (cass); seed-derive + check.sh 103/103 +
tcyr 195/195 green; compiler self-compilation byte-identical to v6.3.4 (the fix is
inert for non-forward code).

**Boundaries (by design / out of scope):**
- Like structs and globals, the prescan covers declarations BEFORE the first
  top-level statement (pass-1 stops there — catch-all `scan = 0`). The standard
  cyrius decls-before-statements order, which is why C-style "fns first, `main()` /
  top-level statements last" programs are fully covered.
- Module-scoped fns (`GMOD != 0`) keep the pass-2-only registration — PARSE_FN_DEF's
  name mangling mutates the name pool and `mod` is unused in-tree; revisit if a
  consumer adopts modules.
- `var p = mk()` (INFERRED local type from a struct-returning call) still segfaults —
  but it does so regardless of definition order, so it is a separate pre-existing
  var-decl/retptr bug, filed
  [`2026-06-28-inferred-struct-local-from-call-segfaults.md`](2026-06-28-inferred-struct-local-from-call-segfaults.md),
  NOT a forward-call defect. Use `var p: T = mk()`.

GOTCHA found during the fix: `_prescan_params` must consume the closing `)` so the
return-type scan sees `:` next — otherwise `: Struct` returns are never classified and
the struct-return mask stays 0 (the explicit-type struct case kept segfaulting until
this was added).

---

## CO-01 — forward calls get zero ABI metadata (silent miscompile) (P1) — original analysis

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
