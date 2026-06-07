# `cyml_parse` stack overflow — function-local `var entry_starts[256]` (256 bytes) written at 8-byte strides up to 256 entries → 1792-byte OOB from untrusted CYML

- **Filed**: 2026-06-06 (cycc 6.0.77)
- **Reporter**: the agnos **1.42.14 pre-burn security audit** — a multi-agent hardening sweep over the agnos kernel + the AGNOS-tic userland tools (bannermanor / commandress / klug) that vendor `lib/cyml.cyr`. Confirmed in the canonical `cyrius/lib/cyml.cyr`, not just the vendored copies.
- **Affects**: `lib/cyml.cyr` → **`cyml_parse`** (decl `lib/cyml.cyr:167`, store `:174`, cap `:176`). Every consumer that calls `cyml_parse` on file content it does not fully control is exposed: **commandress** (`config_load` on `~/.commandress`), **bannermanor** (`font_load_file` / `font_header_load` on `fonts/<name>.cyml`). `klug` vendors `cyml.cyr` but never calls `cyml_parse` → unaffected.
- **Severity**: **HIGH** — an out-of-bounds stack *write* driven entirely by untrusted file bytes, with no userland stack canary (the canary guard is kernel-only), so the corruption is silent: DoS at minimum, **return-address control-flow hijack** at worst, in ring-3 tools that run as the user (`cmdrs` on every shell prompt). Not a ring-3→ring-0 escalation (these are userland tools), so not critical — but a real exploitable memory-safety bug in shipping stdlib code.

## The bug

`cyml_parse` records the byte offset of each `[[entries]]` marker into a fixed array:

```cyrius
fn cyml_parse(data, len): i64 {
    ...
    var entry_starts[256];                          # :167  — FUNCTION-LOCAL
    var entry_count = 0;
    ...
        store64(&entry_starts + entry_count * 8, i); # :174  — 8-byte stride
        entry_count = entry_count + 1;
        if (entry_count >= 256) { i = len; }         # :176  — cap at 256 ENTRIES
    ...
}
```

The code treats `entry_starts` as a **256-slot `u64` array** (8-byte stride at `:174`, read back the same way at `:224`/`:235`/`:237`, cap at 256 *entries* at `:176`) — i.e. it needs **2048 bytes**. But `entry_starts` is **function-local**, and a function-local `var X[N]` allocates **N bytes** (rounded to 8-byte alignment), not N slots. So `var entry_starts[256]` is **256 bytes = 32 usable slots**.

Slot 32 stores at offset `32*8 = 256` — the first byte past the buffer. With the full 256 markers the loop writes `256*8 = 2048` bytes — a **1792-byte stack overflow** clobbering adjacent locals (`entry_count`, `i`, the doc pointer, …), the saved frame pointer, and the return address. `entry_starts` is **not** the last referenced local (it is read back after the scan), so the corruption is genuinely consumed, not dead.

## Root cause — the var-array-unit footgun, resurfaced in stdlib

This is the **same class** as the already-documented cases (`docs/development/state.md` ~2500–2508: the `cbt/build.cyr` `var argv[4]` + `store64(&argv + 8, …)` pattern, and `_exec3`'s byte-contract): **function-local `var X[N]` = N bytes; module-global `var X[N]` = N×8 bytes.** The compiler source confirms it — `src/frontend/parse_decl.cyr:53` (local) rounds `asz` bytes to 8-alignment, while `:578` (global) multiplies by 8.

The difference from the prior cases: those were caught in consumer/tooling code; **this one is in `lib/cyml.cyr` itself** (the canonical stdlib), `cyml` hasn't been touched recently, and it ships to every CYML consumer. The `[[entries]]` count comes straight from `_cyml_is_entries` matching the literal bytes `[[entries]]\n`, so the write stride is fully attacker/file-controlled.

## Reachability (confirmed in two shipping tools)

- **commandress** `config_load` (`src/config.cyr`): `alloc(65536)` → `file_read_all("~/.commandress")` → `cyml_parse(buf, n)`. ~33 `[[entries]]` lines (≈430 bytes, well within the 64 KB cap) start the overflow; 256 markers (~3.3 KB) reach the full 2048-byte write. A planted dotfile (malicious dotfile repo, a `hapi`/stow farm) triggers it on every `cmdrs` invocation.
- **bannermanor** `font_load_file` / `font_header_load` (`src/font.cyr`): reads `fonts/<name>.cyml` selected by `--font NAME` → `cyml_parse(buf, total)`. A crafted font file overflows identically.

## Fix (in `cyrius/lib/cyml.cyr` — the canonical source)

Make the write stride match the buffer's true byte capacity. Either:

1. **Size the buffer for 256 eight-byte slots** — `var entry_starts[2048];` (function-local 2048 bytes = 256 slots), which honors the existing `entry_count >= 256` cap. *Preferred* — preserves the documented "256 entries" contract; minimal change.
2. Keep `var entry_starts[256]` (256 bytes) and **cap `entry_count` at 32** (`if (entry_count >= 32) { i = len; }`), accepting at most 32 entries.

Add a comment at the declaration noting the function-local **N-byte** unit so the slot/byte distinction isn't reintroduced. After the stdlib fix, consumers pick it up on their next `cyrius lib sync` (commandress / bannermanor currently vendor the buggy copy).

## Possibly worth a broader sweep

Since this is the *N*-th instance of the same footgun in shipping code, a `grep` for `var <name>[N]` decls inside functions that are then indexed with a `* 8` / `+ 8*k` / `store64(&name + …)` stride would likely surface more. A lint (warn when a function-local `var X[N]` is addressed past byte N) would catch the class at compile time — see the `cap-drift-detector-gate` precedent in `archived/`.
