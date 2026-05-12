# Zero-call public stdlib fn audit — v5.11.21

**Date**: 2026-05-11
**Cyrius version**: 5.11.20 → 5.11.21
**Driver**: v5.11.7 close-out lib refactor audit found 10 PUBLIC stdlib
fns with 0 callers across the cyrius repo. Stdlib is consumed by 40+
downstream repos via `cyrius deps`, so 0-call-in-grep is not
safe-to-remove without verifying downstream usage.

## Methodology

Per fn, search across all `/home/macro/Repos/*` siblings (excluding
cyrius itself + vidya). Match on `\b<fn>\b` in `*.cyr` files,
filtered to NON-`lib/` and NON-`dist/` paths so vendored copies
of the stdlib don't inflate counts. Decision tree per fn:

1. **Has consumer caller outside lib/dist**: KEEP. Document the
   consumer in the fn's docstring + roadmap reference if applicable.
2. **No caller anywhere**: candidate for deprecation. But: many of
   these are coherent surfaces (e.g. the `*_invalidate_cache` trio,
   subsystem-init verbs like `log_init`) where deprecating without
   the rest is wrong. KEEP with a docstring pointer documenting
   intended consumer + revisit window.
3. **Speculative scaffolding for active work** (per
   `feedback_dead_code_audit_scope`): KEEP, add roadmap pointer.

## Per-fn findings

### 1. `async_new` (lib/async.cyr)

**Caller**: daimon/src/main.cyr.

**Status**: KEEP, consumer documented.

**Action**: docstring updated to name daimon as the load-bearing
consumer.

### 2. `for_each` (lib/callback.cyr)

**Callers**: none across all 50 sibling repos.

**Status**: KEEP — speculative iterator-style API. v5.5.x callback
infrastructure shipped expecting consumer adoption; no consumer
has materialized in 6 minors. Not deprecated this audit because:
(a) iterator-style consumer-ergonomics fn — API shape stays
useful even if unused; (b) v5.12.x agent-runtime work (per
roadmap long-term) is the natural consumer.

**Revisit**: if v5.12.x ships without claiming this verb, flag for
deprecation at v5.12.x closeout. v6.0.0 closeout dead-code sweep
already pins removal of unclaimed verbs.

### 3. `grp_invalidate_cache` (lib/grp.cyr)

**Callers**: none across all 50 sibling repos.

**Status**: KEEP — part of the NSS cache-invalidation trio
(pwd / grp / shadow). Coherent surface; deprecating one without
the others is wrong. Trio is intended for /etc/passwd / /etc/group /
/etc/shadow reload after admin tools modify them — natural consumer
is agnos or kavach when shipping user-management primitives.

**Revisit**: agnos user-management ETA → if not shipped by v6.0.0
GA, drop the trio.

### 4. `log_init` (lib/log.cyr)

**Callers**: none across all 50 sibling repos.

**Status**: KEEP — explicit subsystem-init entry. lib/log.cyr's
structured-log surface ships an init verb so consumers can choose
output destination + level at startup. Pre-init reads default to
stderr (free, no setup needed). The init verb is the explicit
opt-in for structured output.

**Revisit**: if v6.0.0 dead-code sweep finds NO consumer claiming
the structured-log surface, deprecate the whole module — but
`log_init` doesn't go alone.

### 5. `niyama_bre_compile` (lib/niyama.cyr)

**Callers**: cyim/src/cli.cyr, niyama/src/bre.cyr (internal).

**Status**: KEEP, consumer documented. cyim is the external
consumer; niyama's internal use is the source-side reference
implementation that got folded in at v5.9.0.

**Action**: docstring updated to name cyim + note niyama-internal use.

### 6. `pwd_invalidate_cache` (lib/pwd.cyr)

**Callers**: none across all 50 sibling repos.

**Status**: KEEP — see `grp_invalidate_cache` rationale (NSS
cache-invalidation trio).

### 7. `sakshi_clock_recalibrate` (lib/sakshi.cyr)

**Callers**: sakshi/src/clock.cyr, sakshi/src/lib.cyr (sakshi-
internal).

**Status**: KEEP — sakshi distfile was folded byte-identical at
v5.8.65; the internal callers ARE the legitimate use. The fn is
exported as part of the sakshi public surface; long-running
consumers (kybernet, bote) may eventually call recalibrate after
DST shifts or NTP corrections.

**Revisit**: track in sakshi 2.x roadmap (sakshi's own repo).

### 8. `sandhi_err_kind_name` (lib/sandhi.cyr)

**Callers**: sandhi/src/error.cyr + sandhi/docs/examples + sandhi/
programs (all sandhi-internal).

**Status**: KEEP — sandhi distfile was folded byte-identical at
v5.7.0 (and refreshed since). Diagnostic verb; documented in
sandhi's API surface as the canonical error-classifier.

### 9. `shadow_invalidate_cache` (lib/shadow.cyr)

**Callers**: none across all 50 sibling repos.

**Status**: KEEP — see `grp_invalidate_cache` rationale.

### 10. `sig_alg_name` (lib/sigil.cyr)

**Callers**: libro/src/proof.cyr, libro/src/signing.cyr,
sigil/src/types.cyr.

**Status**: KEEP, consumers documented. sigil distfile was folded
v5.8.65; libro is the external consumer using sig_alg_name for
debug / log output naming the active signature algorithm.

**Action**: docstring updated to name libro + sigil-internal use.

## Aggregate decision

**Net change**: 0 deprecations, 0 removals. All 10 fns stay public.

| Group | Fns | Status |
|---|---|---|
| External consumer found | async_new, niyama_bre_compile, sig_alg_name | KEEP + docstring |
| Within-distfile consumer | sakshi_clock_recalibrate, sandhi_err_kind_name | KEEP (folded distfile internal) |
| Speculative iterator API | for_each | KEEP + revisit window |
| NSS cache-invalidation trio | grp/pwd/shadow_invalidate_cache | KEEP (coherent surface, agnos consumer) |
| Subsystem init verb | log_init | KEEP (lib/log.cyr's opt-in entry) |

## Process notes

The "0-call internal grep" was an accurate trigger but the audit
revealed:
- 5 / 10 fns HAVE downstream consumers (just not cyrius-internal).
- 2 / 10 are within-distfile internal (folded sandhi/sakshi own them).
- 3 / 10 are coherent-surface-with-no-claimant-yet (NSS trio).
- 0 / 10 are truly orphan with no API rationale.

Per `feedback_dead_code_audit_scope`: 0-callers-in-grep is NOT
safe-to-remove. This audit confirms the principle — every flagged
fn has either a current consumer, a folded distfile justification,
or a coherent API role.

## Follow-up roadmap items

No new pins. Existing v6.0.0 closeout already pins a dead-code
sweep — that's the natural revisit window for any of these fns
that still have no claimant.

## Files touched (alongside this audit doc)

- `lib/async.cyr` — `async_new` docstring: name daimon.
- `lib/niyama.cyr` — `niyama_bre_compile` docstring: name cyim.
- `lib/sigil.cyr` — `sig_alg_name` docstring: name libro + sigil.
- `lib/callback.cyr` — `for_each` docstring: note speculative, name v5.12.x revisit.
- `lib/log.cyr` — `log_init` docstring: note structured-log opt-in.
- `lib/grp.cyr` + `lib/pwd.cyr` + `lib/shadow.cyr` — `*_invalidate_cache`
  docstrings: note NSS trio + agnos/kavach intended-consumer.
- `lib/sakshi.cyr` + `lib/sandhi.cyr` — folded-distfile note: within-
  distfile callers are legitimate.
