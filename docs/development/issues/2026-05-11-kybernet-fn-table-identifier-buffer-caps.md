# Cyrius: raise `fn_table` and `identifier buffer` caps for AGNOS-scale consumers

**Filed:** 2026-05-11
**Reporter:** kybernet (AGNOS PID 1 init system, v1.1.1)
**Cyrius version at time of report:** 5.10.44 (release tarball)
**Affected:** `cc5` (and `cc5_aarch64`) internal compilation-unit tables — `fn_table` (4096-entry cap) and `identifier buffer` (131072-byte cap)
**Severity:** **P2** — see "Severity rationale" below; current consumers can stay under-cap with surface-trimming work (kybernet 1.1.1 demonstrates this) but the headroom is narrow and shrinking.
**Status:** open.

## Summary

kybernet's 1.1.0 build, which assembled the AGNOS PID-1 surface (stdlib + agnosys-full + agnostik + libro + patra + argonaut + sigil + sakshi) into a single compilation unit, hit:

- **`fn_table at 92% (3779 / 4096)`**
- **`identifier buffer at 85% (112094 / 131072 bytes)`**

Both triggered cc5's "split into compilation units soon" / "reduce includes or split soon" warnings. The next dep-surface bump (any one of: agnostik adding a module, libro `-D LIBRO_TPM=1`, kybernet pulling a second agnosys profile alongside `core` for 1.2.0 edge boot) would have tipped past the **hard** cap; cc5 errors at fn_table 4096 and identifier buffer 131072 are non-recoverable.

kybernet 1.1.1 worked around the cliff by switching `[deps.agnosys]` from `dist/agnosys.cyr` (350 fns) → `dist/agnosys-core.cyr` (56 fns), reclaiming ~290 fn_table slots. That trim was lossless for kybernet specifically (it calls zero agnosys-prefixed functions) — but it's a one-shot. As soon as edge-boot work in 1.2.0 brings `agnosys-storage` + `agnosys-trust` alongside `agnosys-core`, we're back in the warning band, and the next minor after that tips over.

This isn't a kybernet-specific bug — it's an upstream sizing decision that was right for cc3-era consumers and is becoming tight for first-party AGNOS-scale ones. The ask is: **raise the two caps** so the v1.x AGNOS surface fits cleanly under them with room for the next two minors of growth, and re-evaluate again at the next bundle-expansion event.

## Caps and current usage

From `cc5` strings (5.10.44):

| Table | Current cap | Warn threshold | kybernet 1.1.0 (agnosys-full) | kybernet 1.1.1 (agnosys-core) |
|---|---:|---:|---:|---:|
| `fn_table` | 4096 | 90% (3686) | **3779 (92%)** ⚠ | < 3686 (no warn) |
| `identifier buffer` | 131072 B | 85% (~111430) | **112094 B (85%)** ⚠ | < 111430 B (no warn) |
| `variable table` (globals + enums + arrays) | 8192 | n/a | not yet hit | not yet hit |
| `enum table` (enum decls) | 1024 | n/a | not yet hit | not yet hit |
| `fixup_table` | 262144 or 1048576 (path-dep) | (emits %, no number known) | not surfaced | not surfaced |
| `identifier dedup table` | 16384 entries | n/a | not yet hit | not yet hit |

The two hitting caps (`fn_table` + `identifier buffer`) are also the two with explicit "split into compilation units" messaging, which suggests they're the ones the maintainer team has been watching too.

## Why splitting isn't the right answer (yet)

The warning text says "split into compilation units soon" and that *is* the structural fix long-term — but for kybernet specifically:

- **kybernet IS the compilation unit.** It's a PID 1 binary. The whole point is one ELF, one symbol table, one address space — no dynamic linking, no shared libraries, no exec-time module loading. cyrius supports `#ifdef`-gated includes, which can shard cleanly for *features*, but kybernet's surface is overwhelmingly *dep-imported*, not feature-gated.
- **The deps themselves can't shard further** without breaking their own consumers. agnosys already split into 5 profile bundles (`core` / `security` / `storage` / `trust` / `system`); libro gated its TPM path behind `-D LIBRO_TPM=1`; argonaut split out resolver/notify/audit_ext. The leaf is doing the sharding it can do.
- **The cap is hit during single-pass compile**, not at link. Splitting kybernet into two cyrius units that produce one ELF would help iff cyrius supports linking separately-compiled units — which the documentation suggests is planned but not shipped (`cyrius self` does cc5==cc5 self-host, not multi-unit). If multi-unit linking is on a future roadmap, we'd consume it.

The right interim fix is "more headroom in the existing table sizes." The right long-term fix is "multi-unit compilation+link." This issue is asking for the former because the latter is on cyrius's own timeline.

## Concrete ask

**Bump `fn_table` to 8192** (2×) and **`identifier buffer` to 262144 bytes** (2×). Rationale per bump:

### `fn_table` 4096 → 8192

- kybernet 1.1.1 measured ~2430 dead-fns out of registered, meaning the *registered* count was ~3700+. Most are from dist-bundle surface kybernet never calls — but cc5 has to register them all to do the forward-reference scan and emit the dead-fn report.
- Doubling gives kybernet ~50% headroom across 1.2.0 (`agnosys-storage` + `agnosys-trust` profiles add ~120 fns total) and probably 1.3.x agent-runtime work.
- argonaut, kavach, and stiva would all benefit from the same doubling — they're not yet hit, but they're at ~60-70% on 1.5.x/3.x/2.x respectively and trending the same direction.

### `identifier buffer` 131072 → 262144

- This one's tighter than fn_table — every imported function name + every type name + every constant + every variable contributes. The 85% kybernet hit at 1.1.0 is on a surface that doesn't include the agnosys storage or trust domains; 1.2.0's edge-boot work adds ~30-40 long-named identifiers (`luks_format_with_passphrase`, `verity_hash_tree_create`, `tpm_seal_to_pcr_with_policy`, `secure_boot_verify_chain`, etc.) that I can pre-name-budget at roughly 1.5–2 KB.
- Doubling buys two minors of comfortable headroom.

Both bumps are pure cap raises — no algorithmic change, no on-disk format change, no consumer-visible API surface. The change set should be a single source-line edit in cc5 (the fn_table cap) and lex.cyr (the LEXID cap referenced in the existing error message: `error: identifier dedup table full (16384 entries) - raise LEXID cap in lex.cyr`).

## Severity rationale (P2, not P1)

- **Not P1**: kybernet 1.1.1 ships clean under the existing caps. Workarounds (profile-bundle adoption, surface trim) exist and were applied. No active build break.
- **Not P3**: the headroom is narrow enough that the next two minor cuts plausibly tip past the warn threshold (1.2.0 edge boot, 1.3.x agent runtime if it lands at the kybernet layer). Workaround availability is also one-shot — kybernet has already used its main lever (the agnosys profile-bundle switch).
- **P2 is the right rate**: visible cliff in one or two minors, no current blocker. Fix is low-risk (cap raise, single edit, no API change).

## Repro / measurement

```sh
# In kybernet at 1.1.0 tag (before the trim):
cd kybernet/
git checkout 1.1.0
CYRIUS_NO_WARN_SHADOW_LIB=1 CYRIUS_DCE=1 cyrius build src/main.cyr build/kybernet 2>&1 | grep -E "fn_table at|identifier buffer at"
# → warning: fn_table at 92% (3779/4096) — split into compilation units soon
# → warning: identifier buffer at 85% (112094/131072 bytes) — reduce includes or split soon
```

## What kybernet will do regardless of this issue

- Continue tracking against caps in CI via `cyrius build` warning capture — surface a CI failure if fn_table or identifier buffer cross 95% (currently no gate; warnings are silent in CI logs).
- For 1.2.0 edge boot, pre-budget the agnosys-storage + agnosys-trust surface against current measurements before pulling them; reject the inclusion if the projected total tips past the existing caps and this upstream issue hasn't shipped.
- If multi-unit compilation+link lands upstream, evaluate splitting kybernet into a core unit + per-feature linker-input units (mount/cgroup, security/seccomp/sandbox, audit/notify) on its own timeline.

## Related

- The "split into compilation units soon" warning text already implies this is on the maintainer team's radar. This filing is the consumer-side data point.
- agnosys 1.2.0's introduction of profile bundles (`agnosys-core` + 4 domain profiles) was the first first-party response to the same pressure. The pattern works — it just doesn't scale past the leaf level.
- See also `kavach/CHANGELOG.md` 3.1.x and `stiva/` consumer-base for adjacent surface sizing.
