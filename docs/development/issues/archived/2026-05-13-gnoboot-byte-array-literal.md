# Byte-array literal `var foo[N] = { 0x..., 0x... };` — open (enhancement)

**Discovered:** 2026-05-13 during gnoboot Step 4 (building UTF-16LE strings and an EFI_GUID)
**Severity:** Low — workaround works (`store8` calls at top level OR bytes embedded inline in an `asm` block). Enhancement, not a bug.
**Affects:** cc5 5.11.49 (all targets, but the friction is most visible under `CYRIUS_TARGET_EFI=1`)

## Summary

Cyrius supports string-literal initializers for ASCII strings —
`var s = "hello";` — but rejects byte-array initializers like
`var foo[N] = { 0x.., 0x.., ... };`. The parser fails with
`error:<source>:N: expected ';', got '='`.

This is fine for ASCII-heavy code but expensive in two real
consumer-side situations that came up in gnoboot Step 4:

1. **UTF-16LE strings (UEFI's `CHAR16*`).** UEFI's `OutputString`
   and most string protocols take 16-bit-per-codepoint UTF-16LE.
   `"step 4: HandleProtocol(LoadedImage) = "` is 38 ASCII chars =
   76 bytes wire. Today, building this means 76 `store8` calls
   (one per byte), or 38 paired pairs (one per CHAR16).
2. **EFI GUIDs.** Each protocol's GUID is a fixed 16-byte blob with
   a specific wire format (first u32 LE, two u16 LE, eight raw
   bytes — Microsoft GUID convention). gnoboot needs at least
   the `EFI_LOADED_IMAGE_PROTOCOL_GUID` and the
   `EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID` at Step 4–5; the full
   bootloader will reach ~8 GUIDs. Each is 16 `store8` calls today.

Concretely, gnoboot's current `main.cyr` has ~150 lines that look
like:

```cyrius
store8(&msg_pre +  0, 0x73); store8(&msg_pre +  1, 0x00);  # s
store8(&msg_pre +  2, 0x74); store8(&msg_pre +  3, 0x00);  # t
store8(&msg_pre +  4, 0x65); store8(&msg_pre +  5, 0x00);  # e
store8(&msg_pre +  6, 0x70); store8(&msg_pre +  7, 0x00);  # p
... (about 80 more lines)
```

A byte-array literal would collapse those 80 lines into ~10:

```cyrius
var msg_pre[78] = {
    0x73, 0x00,  0x74, 0x00,  0x65, 0x00,  0x70, 0x00,    # s t e p
    0x20, 0x00,  0x34, 0x00,  0x3A, 0x00,  0x20, 0x00,    # ' ' 4 ':' ' '
    # ...
    0x00, 0x00                                              # NUL CHAR16
};
```

A `u16`-array literal (UTF-16LE-friendly) would be even nicer but
strictly optional:

```cyrius
var msg_pre[39]: u16 = { 0x73, 0x74, 0x65, 0x70, 0x20, ... };
```

…though the byte-array form covers both UTF-16LE strings and the
EFI GUID case in one feature.

## Reproduction

```cyrius
# minimal repro, save as /tmp/bal.cyr and run `cyrius build`:
var buf[4] = { 0x12, 0x34, 0x56, 0x78 };
```

Result:

```
error:<source>:1: expected ';', got '='
```

The same shape works for scalars (`var x = 5;`) and ASCII strings
(`var s = "hi";`), just not the brace-list form for arrays.

## Root cause (speculation)

Not a bug — a missing parser path. Cyrius's grammar for `var X[N]`
expects a `;` after the size (`PARSE_GVAR_ARR` in
`src/frontend/parse_decl.cyr`, per the grep hit during gnoboot
investigation), while the brace-list initializer support exists for
other constructs (struct field init via `PARSE_STRUCT_INIT`,
function arg lists). Hooking `{ ... }` into the gvar-array path
should be small.

## Proposed fix (sketch)

1. Extend `PARSE_GVAR_ARR` to accept an optional `= { byte-list }`
   tail.
2. The bytes are emitted into `.rdata` (or wherever cyrius lays out
   the array's storage) at compile time — no runtime init code
   needed (the bytes are statically known).
3. Mismatch between `N` and the brace list's length: warn or error,
   cyrius-agent's call. Probably error to keep parity with
   "explicit-size declaration must match data".
4. Optional: support `u16`-typed array literals so UTF-16LE strings
   can be written as `var msg[N]: u16 = { 0x73, ... };` — even
   nicer ergonomic, but byte form alone covers the use case.

## Consumer-side workaround (currently in gnoboot)

Two patterns work and are both used in `gnoboot/src/main.cyr`:

1. **Runtime `store8` initialization** at top level (or inside a
   fn): the pattern shown above. Verbose but readable; each byte is
   its own line.
2. **Bytes embedded inline inside an `asm { ... }` block,
   `lea rdx, [rip + disp32]`-addressed**. Used in gnoboot's pure-asm
   Step 4 (earlier attempt before fn-based architecture worked).
   Costs the consumer hand-computing rip-relative displacements; not
   pleasant but the bytes themselves are compact.

Neither is wrong; both are wordier than a byte-literal would be.

## Pointers

- gnoboot CHANGELOG entry (with constraint documentation):
  `gnoboot/CHANGELOG.md` § *Known cyrius constraints*
- Sister enhancement issue (logical companion):
  `cyrius/docs/development/issues/2026-05-13-gnoboot-efi-main-convention.md`
- Use site (concrete example of the friction):
  `gnoboot/src/main.cyr` — the `store8(&msg_pre + N, ...)` runs
  that this issue would shrink.
