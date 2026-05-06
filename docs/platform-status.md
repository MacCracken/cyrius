# Platform Status

Current platform coverage for the Cyrius toolchain. **Refresh
target**: every closeout pass (CLAUDE.md step 11). The roadmap's
[Platform Targets](development/roadmap.md#v5x--platform-targets)
section tracks the per-release add history; this file is the
"what works now" snapshot.

| Platform | Format | Status |
|----------|--------|--------|
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cc5 ~741 KB (v5.8.65); two-step bootstrap byte-identical. |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross-build byte-identity + native self-host on Pi 4 (repaired v5.6.32). Three libs (`lib/hashmap_fast`, `lib/u128`, `lib/mabda`) still contain ungated x86 asm — arch-gating queued. |
| cyrius-x bytecode | .cyx | **✅ Narrow** — clean CYX bytecode (path B, v5.7.12); literal-arg propagation pinned v5.7.x patch slot. |
| macOS x86_64 | Mach-O | **✅ Narrow** (v5.1.0). |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — gate fixture repaired v5.6.33 (no compiler regression existed; bytes unchanged since v5.5.13). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — gate fixture repaired v5.6.36; HIGH_ENTROPY_VA enabled v5.6.31. Win64 ABI complete (v5.5.36); .reloc + 32-bit ASLR (v5.5.35). |
| Compiler optimization (O1–O6) | — | **✅ Closed** (v5.6.5 + v5.6.7–v5.6.27). |
| RISC-V (rv64) | ELF | Queued — **v5.10.x** (moved from v5.9.x at v5.8.x close). |
| Bare-metal | ELF (no-libc) | Queued — **v5.10.0**. AGNOS kernel target. |

## Verification hosts (cross-arch SSH-wired)

Per the cross-arch propagation rule (CLAUDE.md, memory pin
`feedback_cross_arch_propagation_mandatory`), every compiler-side
fix gets cross-tested in the same slot:

| Host | Arch / OS | Role |
|------|-----------|------|
| `pi` | aarch64 Linux (Pi 4) | Native aarch64 self-host + multi-thread / mutex shakedown. |
| `cass` | macOS Apple Silicon | Mach-O native verification (broad-scope). |
| `ecb` | Windows x86_64 | PE/COFF broad-scope on real Win11. |

> "NO EXCUSE THAT SHIT [is] BEING FOUND BY PORTS" — user
> 2026-05-04. SSH-wired hosts mean cross-test is mechanical, not
> aspirational.

## Closeout audit checklist

Run during CLAUDE.md step 11 (vidya / docs sync) at every minor:

- [ ] Update compiler size for primary host (Linux x86_64) row.
- [ ] Verify each "✅ Narrow + Broad" row still holds against
      its CI lane.
- [ ] Move any "Queued" platform that landed mid-minor to a ✅
      row with the landing version.
- [ ] Cross-check pinned future targets against
      [roadmap.md](development/roadmap.md) — no version-skew.
- [ ] Re-verify SSH-wired hosts by running
      `cyrius cross-test --host {pi,cass,ecb}` (or equivalent).
