# 2026-07-10 — USB-HID arrow / navigation keys reach ring-3 clients (agnos ↔ ecosystem)

**Status:** ✅ FIXED in agnos **1.53.12** (2026-07-10). Cross-repo copy — the primary fix is
in the agnos kernel (`kernel/arch/x86_64/usb/hid_translate.cyr` + `hid.cyr`); its full
detail lives in `agnos/docs/development/issues/2026-07-10-usb-hid-arrow-nav-keys.md`. This
copy tracks the **ecosystem input-path** side for the language/desktop team.

## Why this is a cyrius-ecosystem concern

The AGNOS input path is a kernel ↔ ecosystem seam:

```
USB-HID kbd → agnos kernel (HID→set-1) → kb_buf → sys_kbscan (#42)
   → bhumi (_bhumi_set1_ext_to_hid) → HID usage → aethersafha → SETU_INPUT_KEY → client
```

`bhumi` (the sovereign platform backend consumed by the aethersafha compositor) already
decoded the E0-extended set-1 stream — `_bhumi_set1_ext_to_hid` maps `E0 0x48 → Up`,
`E0 0x50 → Down`, etc. But the **kernel never emitted those bytes**: the arrow / nav-cluster
HID usages (`0x49`–`0x52`) were deferred in the HID→PS/2 table, so `sys_kbscan` drained
nothing for an arrow press. Regular keys worked; arrows produced zero events at every layer
above the kernel — including any Cyrius program reading `sys_kbscan` directly (games, TUIs).

## Resolution (kernel-side; no cyrius toolchain change)

- No new syscall and no new Cyrius stdlib wrapper — the existing `sys_kbscan`#42 contract is
  unchanged. The fix is purely the kernel populating the extended scancodes it was dropping.
- The kernel now maps HID `0x49`–`0x52` to their set-1 base codes and prefixes `0xE0` on the
  make/break of an extended key, so the `sys_kbscan` byte stream is the canonical
  `E0 <base>` / `E0 <base|0x80>` that `bhumi` (and `cyrius-doom`-style raw scancode readers)
  already expect.

## Note for Cyrius consumers of `sys_kbscan`

Programs that read raw scancodes (e.g. `cyrius-doom`'s `input_poll`) can now receive arrow /
nav keys on agnos ≥ 1.53.12. They must handle the `0xE0` extended prefix (a lead byte, then
the base make/break) — the same shape a PS/2 set-1 keyboard produces on hardware.
