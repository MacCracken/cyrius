# Top-level `var X = N` reads as zero before initializer runs

**Filed:** 2026-05-18 (during agnos xHCI Attempt 64 QEMU root-cause investigation)
**Severity:** High — silently miscompiles user code; bug surface is "constant declared at module top, used in load-bearing register write / loop bound, reads as 0." Two confirmed instances; pattern was suspected at v5.10.x but not previously root-caused.
**Affects:** Code generation for `var <UPPER_CASE_NAME> = <int_literal>;` at module top level. Reading the gvar in a function called before module-load initializers run returns 0 instead of the declared value.
**Reporter:** Claude, on behalf of agnos iron-bring-up.

## Summary

In a Cyrius module, a top-level declaration of the form

```cyrius
var XHCI_CMD_TIMEOUT_SPINS = 10000000;
```

was empirically observed to read as **0** when accessed by a function in the same module, called from outside the module's load-init path. This breaks any usage where the gvar is treated as a compile-time constant.

Two concrete instances surfaced during agnos xHCI bring-up:

1. **`XHCI_EVT_RING_SEGMENT_SIZE = 256`** in `kernel/arch/x86_64/usb/xhci_ring.cyr:51` (pre-fix). Used at line 219 as `store32(erst + 8, XHCI_EVT_RING_SEGMENT_SIZE);` to plant the Event Ring Segment Table entry's Ring Segment Size word. QEMU memory dump via monitor `xp /4wx <erst_phys>` confirmed bytes 8-11 of the ERST entry read `0x00000000`, not the expected `0x00000100`. With 0-sized segment, the xHCI controller had no event-ring slot to write Command Completion Events to — events silent-absorbed for 10+ iron-burn attempts (FF → QQ+QQ2 letter ladder).

2. **`XHCI_CMD_TIMEOUT_SPINS = 10000000`** in `kernel/arch/x86_64/usb/xhci_cmd.cyr:60` (pre-fix). Used at line 159 as `while (wait < XHCI_CMD_TIMEOUT_SPINS) { ... }`. With X=0 the loop body never executes — observable symptom: `final_idx=0`, `cycle=1`, `events_seen=0` exactly matches "loop never ran" semantics. Confirmed by enum conversion: after fix, Enable Slot completes (slot 1 assigned), AGNOS advances to Address Device phase.

Both gvars converted to `enum X { NAME = value; }` constants and the bug class disappeared. Cyrius enum members compile to literals — no module-load ordering to get wrong.

## Pre-existing suspicion

`xhci_cmd.cyr:107-115` carries a comment from an earlier consumer-side encounter (Attempt 58 era, late v5.10.x):

> Was gated on `xhci_diag_submit_count < XHCI_DIAG_SUBMIT_MAX` in Attempt 58 but the print never fired on iron despite all four string literals being present in the binary (`strings /mnt/boot/agnos` confirms). **Suspected gvar-init-order: `XHCI_DIAG_SUBMIT_MAX` reading 0 at first-call time → gate `0 < 0` = FALSE and suppressing the print.** Two-pronged fix: (a) drop the gvar dep entirely; gate on `xhci_cmd_ring_idx <= 2` …

The consumer workaround at the time was to swap the gvar gate for a runtime-state check, masking the bug. The 2026-05-18 investigation confirms the suspicion empirically — same pattern, two more gvars, definitive proof via QEMU memory inspection.

## Reproduction

In agnos at commit prior to 2026-05-18 enum conversions, with QEMU smoke harness `gnoboot/tests/ovmf_smoke.sh` extended with `-device qemu-xhci -device usb-kbd` and `-d trace:usb_xhci_*` flags:

1. Build agnos with `var XHCI_CMD_TIMEOUT_SPINS = 10000000;` at xhci_cmd.cyr:60.
2. Boot under QEMU + OVMF + qemu-xhci.
3. Observe `xhci: cmd completion timeout, final_idx=0 cycle=1 events_seen=0` immediately after Enable Slot doorbell.
4. QEMU trace shows `usb_xhci_queue_event ER_COMMAND_COMPLETE` posted by controller (HW worked).
5. QEMU monitor `xp /16wx <evt_ring_phys>` shows event TRBs in RAM with correct cycle bit.
6. AGNOS still reads `events_seen=0` because the spin loop never ran (wait < 0 = false on first check).

Convert to:
```cyrius
enum XhciCmdSpins { XHCI_CMD_TIMEOUT_SPINS = 10000000; }
```

Rebuild. Boot. Symptom gone — Enable Slot completes, slot 1 assigned, AGNOS advances to Address Device.

## Hypothesis on the root cause

Either:

- **Top-level `var = N` initializers are emitted into a module-load runtime path that hasn't been called yet** at the moment of first consumer access. The gvar's storage location is BSS-zero from program load, and the user-supplied initializer literal never gets stored before the read.
- **The compiler emits a runtime-store of N into the gvar's storage location at some "module init" boundary** which agnos's call-graph misses (agnos has no explicit module-init phase; it's bare-metal, no crt0-style init array).

Cyrius `enum NAME { MEMBER = N; }` constants compile to literals at use sites, bypassing the entire storage-location mechanism. That's why the enum conversion is a clean fix.

## Why the consumer-side workaround is not enough

The 2026-05-10-era workaround at `xhci_cmd.cyr:107-115` swaps `XHCI_DIAG_SUBMIT_MAX` for a runtime-state check. This works for diagnostic gating but doesn't generalize. Two gvars confirmed broken in 2026-05-18; the rest of the codebase has many `var X = N;` declarations that could be silently miscompiling in unobserved ways.

The language-level fix: either

1. **Diagnose the init-order bug** in Cyrius (figure out why top-level `var = N` initializers don't run before first consumer use) and fix the codegen / linker / module-init path.
2. **Promote `var X = N;` at module top with all-uppercase name + literal RHS to enum-like compile-time constant automatically** (small parser/codegen hack; gives constants without the user having to know to use enum).
3. **Emit a warning** when a top-level `var X = N;` is used in a way that suggests intent as a constant (uppercase + literal RHS), suggesting `enum` instead.

Option 1 is the cleanest. Option 2 is a smaller surface fix that catches common cases. Option 3 is a tooling-side mitigation.

## Affected agnos commits

- `kernel/arch/x86_64/usb/xhci_ring.cyr` — `XHCI_EVT_RING_SEGMENT_SIZE` converted to enum (2026-05-18, Attempt 64).
- `kernel/arch/x86_64/usb/xhci_cmd.cyr` — `XHCI_CMD_TIMEOUT_SPINS` converted to enum (2026-05-18, Attempt 64).
- **Still pending** (same pattern, not yet failing visibly): `XHCI_DIAG_EVT_MAX = 12`, `XHCI_DIAG_SUBMIT_MAX = 2` in xhci_cmd.cyr lines 46/54.

## Related

- Iron-bring-up narrative: `agnosticos/docs/development/iron-nuc-zen-log.md` § Attempt 64.
- Original consumer-side suspicion: `agnos/kernel/arch/x86_64/usb/xhci_cmd.cyr:107-115` (comment block citing this hypothesis as "Suspected gvar-init-order").
- Bug parallels `bote nested-call parse failure` (2026-05-13 ticket) in shape — both are "consumer side workaround masks underlying compiler issue." Different bug class, same disposition.

## Why this is high-severity

The two confirmed instances were load-bearing register writes and spin-loop bounds in a kernel driver. Symptoms looked like hardware quirks (silent-absorb), eating 10+ iron-burn attempts of letter-ladder hypotheses (FF → QQ+QQ2) before the compiler-side root cause surfaced. **Any Cyrius consumer using `var X = N;` as a constant is at risk of identical silent-miscompile.**

---

**Owner:** Cyrius language agent
**Disposition:** Investigate codegen for top-level `var = literal` initialization. Compare against enum codegen. Determine why initializers don't run before consumer access in bare-metal target.
