# `lib/syscalls_x86_64_agnos.cyr` has no `sys_power_source`#114 peer

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-08). agnos has assigned and built the number in its 1.57.18 cut, where
it is reviewed and gated (`scripts/smoke/power-source-smoke.sh`). Do not mint it here before agnos's `1.57.18` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr`. The `SysNrAgnos` constant in number order after the 1.57.18 cwd pair
(`#112` / `#113`, filed separately), or beside `SYS_REBOOT = 13` (:74), the other power number — cyrius's call. A
`PowerSrc` enum beside the `FdKind` one (:194). `sys_power_source()` beside `sys_reboot()` (:1302).
**Filed:** 2026-11-08, by agnos. agnos minted and built the number; cyrius owns the peer.
**Affects:** cyrius **6.7.18** (agnos's pin). `#114` exists from agnos **1.57.18**.
**Severity:** **Low as a defect, blocking for the consumer.** daimon's file index (crab's "pauses on battery") has no
agnos arm in `_fx_power_find` until a wrapper exists; it answers `"power":"unknown"` and keeps walking.

## The ask

```
SYS_POWER_SOURCE = 114;   # power_source() → answer word (≥ 0); -1 = a kernel before agnos 1.57.18
enum PowerSrc {
    PSRC_UNKNOWN = 0;  PSRC_MAINS = 1;  PSRC_BATTERY = 2;          # w & 0xFF (2 reserved: never returned yet)
    PSRC_F_TABLES = 0x100;  PSRC_F_BATTERY = 0x200;  PSRC_F_PRESENT = 0x400;
    PSRC_F_AC = 0x800;  PSRC_F_INFERRED = 0x1000;  PSRC_F_MALFORMED = 0x2000;
}
fn sys_power_source(): i64 { return syscall(SYS_POWER_SOURCE); }
```

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2 row 114 and § 4.10 — authoritative)

`#114` takes no argument (a1..a4 are never read) and returns ONE word the kernel computed at boot from an ACPI
namespace scan and cached: one load, no pointer, no lock, no blocking — a 10 s poll costs nothing.

| `w & 0xFF` | State |
|---|---|
| 0 | cannot say — a battery may be present, no usable ACPI tables, or a table failed a bound check |
| 1 | mains — inferred: no battery declared, or every declared battery declared absent by a constant `_STA` |
| 2 | battery — RESERVED for a later AML `_PSR`/`_BST` evaluator; agnos 1.57.18 never returns it |

| Bit | Name | Set when |
|---|---|---|
| 0x100 | `PSRC_F_TABLES` | the DSDT was found and passed its checks |
| 0x200 | `PSRC_F_BATTERY` | a battery (`PNP0C0A` / `ACPI0002`) is declared |
| 0x400 | `PSRC_F_PRESENT` | a declared battery is not ruled absent (why the state is 0) |
| 0x800 | `PSRC_F_AC` | an AC adapter (`ACPI0003`) is declared (informational) |
| 0x1000 | `PSRC_F_INFERRED` | the state is inferred from declarations, not evaluated (every state 1 in 1.57.18) |
| 0x2000 | `PSRC_F_MALFORMED` | a table failed a bound check (the state is then 0) |
| bits 14–63 | — | reserved, 0 |

**Probe:** the word is never negative. `sys_power_source() < 0` means a kernel before 1.57.18 (an unknown number
answers -1). **Callers read the state as `w & 0xFF`**, never `w == PSRC_MAINS`: the flag bits ride on every answer.
Typical words: QEMU and a desktop with no battery `0x1101`; a laptop `0x700` (`0xF00` with its AC adapter); a
desktop declaring a disabled battery `0x1301`; no ACPI `0x0`.

## A self-proving repro (once the wrapper exists)

On agnos 1.57.18 under QEMU (`-machine q35`, no battery device): `sys_power_source()` returns `0x1101`
(`& 0xFF` == `PSRC_MAINS`). On agnos 1.57.17: -1. A program that prints both `sys_power_source()` and
`syscall(114)` must print the same value. agnos's own ring-3 exerciser is `tests/telemetry/psrc.cyr` (raw `#114`);
`scripts/smoke/power-source-smoke.sh` boots it against 15 QEMU scenarios (crafted SSDTs via `-acpitable`).

## Compatibility

Nothing existing changes: one constant, one enum, one function. `agnos_abi_doc_parity` gains row 114.

## Related

- agnos issue `docs/development/issues/2026-11-06-no-way-to-read-the-power-source.md` (filed from daimon 2.5.4).
- daimon `docs/development/issues/2026-11-08-agnos-power-source-arm-for-fx-power-find.md` — the consumer.
- `archived/2026-10-13-agnos-sys-fd-kind-111-peer.md` — the shape this follows.
