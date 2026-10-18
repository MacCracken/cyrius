# x86 ELF DCE stops compacting past 4,096 dead-code runs, and kybernet's `agnos-init` crossed it: 248,440 → 1,574,640 bytes — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-4, `c6540a1af`, and IN-4r, `600577c53` (no decision needed): the dead-code run registry (WPNR) and the switch-table registry (WPSW) grow — the first 4,096 records at their old regions, then `alloc()`'d and doubling, the run table with its merge scratch — and a run that starts where the last ended extends it (the proposed merge). Compaction no longer has a run count past which it declines: 4,100 one-line dead fns compact to 4,456 B (were 201,064 B, declined); 4,100 dead fns interleaved with 4,100 live ones compact (336,232 B, exit 4 — the merge alone would not have lifted this); 10,000 non-abutting dead fns and 30,000 + 30,000 compact; under `CYRIUS_IR=3` no corpus file declines (were 59 of 624). A decline now means an alloc failed and says so. kybernet's `agnos-init` was not rebuilt here (a consumer's tree); its shape — more than 4,096 dead-code runs, x86_64 ELF, `CYRIUS_DCE=1` — is the rows'. Rows: `dce_eliminates.sh` axis 6 (6a – 6d, each removing every byte it NOP-filled); `wp_compact_registry_caps.sh` axes 3 / 5 and `dce_pe_macho_layout_declines_compaction.sh` axes 5 / 9 inverted to pin the compaction; `dce_data_vaddr_frozen.sh` row 10 (a compaction across a 2 MB bucket keeps the frozen data base, exit 42); mutations: no grow, no abutting merge, the fixed base in `_wp_shift`, a fixed scratch, a short copy, no WPSW grow — each RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — the cap is the "WPNR 4,096-run merge" item in `roadmap_6.md`; this file records a shipped consumer binary that hit it.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-15, moving kybernet 1.7.10 from cyrius 6.6.6 to 6.6.20 (and its deps to the tags that pin 6.6.20).
**Severity:** Low — the binary is correct (the dead code is NOP-filled and never runs), but a release artifact grew 6.3x.
**Affects:** static x86_64 ELF under `CYRIUS_DCE=1`, any program with more than 4,096 unreachable fns. Measured on 6.6.20. (aarch64 ELF does not compact at all yet, so it NOP-fills either way.)

## Summary

kybernet's package ships two programs built from one manifest: `kybernet` (PID 1) and `agnos-init`, a small
oneshot that makes the AGNOS directory layout. Both link the manifest's whole dependency set (argonaut, libro,
agnostik, sigil and the stdlib), and `agnos-init` uses very little of it. At 6.6.20 its unreachable-fn count
went past the repair registry's 4,096 dead-code runs, so DCE NOP-fills the dead code and keeps it. 6.6.18's
honest note says so; the size is what a consumer sees.

## Reproduction

In a kybernet 1.7.10 checkout (`cyrius = "6.6.20"`):

```sh
cyrius deps
CYRIUS_DCE=1 cyrius build src/agnos_init.cyr build/agnos-init
CYRIUS_DCE=1 cyrius build src/main.cyr build/kybernet
```

Measured:

| Binary | Unreachable fns | DCE note | Bytes |
|---|---:|---|---:|
| `agnos-init`, kybernet 1.7.9 source and deps, on 6.6.6 | 4,012 | `1247476 bytes of dead code eliminated` | 248,440 |
| `agnos-init`, kybernet 1.7.9 source and deps, on 6.6.20 | 4,170 | `1301637 bytes NOPed; compaction declined on x86_64 ELF: more than 4096 dead-code runs, the repair registry cap` | 1,565,664 |
| `agnos-init`, kybernet 1.7.10 (deps moved) on 6.6.20 | 4,180 | same note, `1305788 bytes NOPed` | 1,574,640 |
| `kybernet`, 1.7.10 on 6.6.20 | 3,351 | `940939 bytes of dead code eliminated` | 751,544 |

The second row isolates the toolchain: the same source and the same dependency tags, and the stdlib's growth
between 6.6.6 and 6.6.20 adds 158 unreachable fns, which takes `agnos-init` from 84 under the cap to 74 over it.
kybernet 1.7.10's dependency moves (argonaut 1.15.4 → 1.15.6, libro 2.10.3 → 2.10.8, agnostik 1.6.3 → 1.7.1,
sigil 3.12.18 → 3.13.10) add 10 more.

## Root cause

The fixed 4,096-run registry described in the 6.6.18 CHANGELOG ("DCE — the honest 'compaction declined'
note", measured there as 4,096 one-line dead fns compacting to 4,456 B while 4,097 leave 201,064 B).

## Proposed fix

The WPNR 4,096-run merge already planned in `roadmap_6.md`: merge a dead run into the previous one when
`cp == prev_cp + prev_len`. Contiguous dead fns, which is most of an unused dependency, would then cost one run.

## Consumer-side workaround

None taken. The binary is correct, and kybernet's own PID 1 (3,351 dead fns) still compacts. kybernet records
the size in its CHANGELOG and roadmap and will re-measure when the cap moves. Splitting `agnos-init` onto its own
manifest with a smaller dependency set would avoid the cap, at the cost of a second lock to keep in step.
