# String-literal global initializer still holds garbage in LARGE programs (6.3.16 fix incomplete)

> **RESOLVED v6.3.24 — the filed diagnosis was WRONG. Root cause is a SYMBOL
> COLLISION, not a string-literal-init codegen bug.** `var DB_PATH = "yeo.patra"`
> collides by name with patra's exported `enum DbOff { DB_PATH = 16 }`. Cyrius's
> symbol resolution returns the *last* registration for a name, so once the
> consumer's var is registered, EVERY later `DB_PATH` reference — including inside
> already-parsed `patra_open`, where `store64(db + DB_PATH, wpath)` uses the
> constant as an ABI offset — rebinds to the var's slot (holding the string
> pointer). `db + <string ptr>` is a wild address → out-of-bounds store → SIGSEGV.
> The **string value is perfectly fine** (a `write(2, DB_PATH, 9)` prints
> `yeo.patra` right up to the crashing call); the crash is a mis-resolved *offset*
> inside patra. The `fn db_path()` workaround worked only because `db_path` doesn't
> collide with the enum. It reproduces only "at scale" because the collision needs
> patra (which defines the `DB_PATH` enum) linked in. **Fix:** cyrius now
> HARD-ERRORS when a non-int-literal global shadows an enum constant
> (`CHK_ENUM_SHADOW`, `src/frontend/parse_types.cyr`) — a compile-time
> `variable 'DB_PATH' shadows an enum constant (rename the variable)` instead of a
> silent miscompile. **The consumer's real fix is to rename the global** (e.g.
> `YEO_DB_FILE`); the `db_path()` fn also remains valid. Regression gate
> `tests/enum_shadow_error.sh` (check.sh). See the "## Resolution" section below.

**Filed:** 2026-07-01 (by the `yeo-cy-test` consumer; cyrius 6.3.23)
**Severity:** Medium — silent miscompile at scale. Follow-up to the **closed**
`issues/archived/2026-06-28-string-literal-global-initializer-garbage.md` (fixed +
regression-locked in v6.3.16). The 6.3.16 fix works for small programs but the bug
**recurs in a large program**, so consumers still need the `fn`-returns-the-literal
workaround.
**Component:** string-literal global initializer codegen (the data-section emit /
global-address seeding — the same path 6.3.16 fixed, but something is size- or
global-count-dependent).

## Symptom

`var S = "yeo.patra"` at module scope:
- **Small program** — works. `var S = "yeo.patra"; fn main() { fmt_int(strlen(S)); }`
  prints 9, `S` dereferences to the literal. (This is what 6.3.16's regression test
  covers, and it passes.)
- **Large program** — **garbage**. In `yeo-cy-test` (a full HTTP+HTTPS server:
  sandhi + sigil's ~14 MB banked `.bss` + patra + many module globals), the *same*
  `var DB_PATH = "yeo.patra"` holds a bad pointer, so `patra_open(DB_PATH)`
  **SIGSEGVs at startup**. Reverting to a function — `fn db_path(): i64 { return
  "yeo.patra"; }` + `patra_open(db_path())` — fixes it, deterministically. Bisected
  with stderr markers: the crash is exactly at `patra_open(DB_PATH)`, and swapping
  the global for the fn is the single change that makes it start.

So the global's initializer is correct in a small TU but wrong once the program has
a large `.bss` / many globals — a size- or layout-dependent regression the 6.3.16
small-program regression test doesn't catch.

## Likely area

The global-address seeding for a string-literal initializer probably computes an
offset/relocation that's correct for small `.bss`/`.data` but overflows or
mis-relocates past some threshold (the probe's `.bss` is ~14 MB from sigil's 64
crypto banks). Worth a regression test with a large synthetic `.bss` (e.g. a big
`var pad[16_000_000]` global) alongside a string-literal global, asserting the
string global still dereferences correctly.

## Consumer status

`yeo-cy-test` keeps the `db_path()` fn workaround (it can't use a plain string-literal
global). The `str_builder` gate (6.3.15) and multi-worker TLS otherwise work on 6.3.23.

## Resolution (v6.3.24)

Root-caused directly against the real consumer (`secureyeoman/yeo-cy-test`), not a
synthetic proxy — six synthetic "large program + string global" reproductions all
compiled a *correct* string global, because none of them named the global the same
as an included enum constant. Method: flip `db_path()` → `var DB_PATH`, reproduce
the SIGSEGV, then instrument. `write(2, DB_PATH, 9)` printed `yeo.patra` at every
point up to `patra_open` — the value is fine. DX-01's new `CYRIUS_SYMS` mapped the
crash RIP to `patra_open+0x2b5`; the faulting instruction was `store64(db + X, …)`
where `X` = a global load holding `0x1277c7f` (a data-region address) instead of a
small offset. A side-by-side disasm of the fn-form vs global-form binaries was
byte-identical **except** that store: fn-form referenced patra's `enum DbOff`
`DB_PATH=16` slot, global-form referenced the consumer's `var DB_PATH` slot. The
name collides; `FINDVAR` returns last-match, so the var (registered when `main.cyr`
parses, after the auto-prepended deps) shadowed the enum constant for `patra_open`'s
pass-2 codegen.

**Fix (cyrius side):** `CHK_ENUM_SHADOW` (`src/frontend/parse_types.cyr`), called
from the global-var registration in `parse_decl.cyr` for **non-int-literal** inits
(`chk_has == 0`). It hard-errors when the name already exists as an enum constant
(detected via the uncapped, growable `var_enum_id` marker — `GVENUMID` — not the
1024-capped fold table `CHKDUPVAL` used, which is why the collision slipped through
in large stacks). An **int-literal same-value** shadow stays allowed (chrono's
`var CLOCK_MONOTONIC = 1` harmlessly aliasing the syscall enum) and an int
*conflicting-value* shadow keeps CHKDUPVAL's warning. cycc self-hosts byte-identical
+ seed-derives; regression gate `tests/enum_shadow_error.sh`.

**Consumer follow-up (not cyrius):** `yeo-cy-test` can now use a string-literal
global for the DB path again — just not named `DB_PATH` (which patra exports as an
enum). Rename to e.g. `YEO_DB_FILE`, or keep the `db_path()` fn. Filed back to the
SecureYeoman probe.

Symmetric note: only the var-after-enum order is caught (the realistic case — deps
are auto-prepended before the entry's vars). A consumer manually `include`-ing the
enum-defining lib *after* its own `var` would not trip this check; if that ever
surfaces, add the mirror guard at enum-constant registration.
