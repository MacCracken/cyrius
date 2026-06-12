# `main_aarch64.cyr` pass-1 scanner never got the v5.8.21 annotation-token fix → `#pure`/`#io`/`#alloc` cause `error: unexpected enum` on aarch64/macOS

**Filed:** 2026-06-12
**Severity:** **HIGH** — blocks **all** aarch64 + macOS builds for any consumer
that includes a stdlib module carrying a `#pure` / `#io` / `#alloc` annotation
(notably **`bayan`**, the data-domain module). x86_64-linux is unaffected. No
correctness/security impact — the build simply produces no binary (fail-closed).
**Component:** frontend — `src/main_aarch64.cyr` pass-1 pre-scan (the aarch64
compile entry point's global-decl scanner)
**Reported by:** thoth (multi-target build bring-up, 0.6.x → macOS/aarch64)
**Toolchains reproduced:** cycc **6.1.38** and **6.2.0**, both the x86_64-hosted
cross backend (`cycc_aarch64`) and the **native arm64 cycc on real hardware**
(macOS arm64, host `ecb`).

## Summary

`src/main.cyr`'s pass-1 pre-scan consumes the fn-attribute annotation tokens
`#regalloc` (109), `#must_use` (122), `#deprecated` (124), `#pure` (125), `#io`
(126), `#alloc` (127) — the **v5.8.21** fix (`src/main.cyr:1150-1166`). Its own
comment records why:

> v5.8.21: … Pre-fix, an annotated fn at the start of any stdlib file (e.g.
> `#io fn sys_write`) caused the pass-1 scanner to fall into the catchall else
> and terminate, leaving subsequent enum / fn defs unregistered for pass 2.
> Surfaced when the v5.8.20 annotation-ramp … marked sys_open/close/read/write
> `#io` and check.sh dropped to 48/64 — every test file including syscalls hit
> "unexpected enum" at lib/syscalls_x86_64_linux.cyr:555.

**`src/main_aarch64.cyr` never received that fix.** Its pass-1 `scan` loop
(`src/main_aarch64.cyr:306-402`) handles enum/struct/union/gvar/fn/kernel tokens
but has **no case for 109/122/124/125/126/127**. When the scanner meets a
`#pure` (etc.) token it matches nothing and falls into the catchall
`else { scan = 0; }` at **`src/main_aarch64.cyr:402`**, terminating pass-1 early.
Every enum/fn after the annotated fn goes unregistered, and the build dies with:

```
error: unexpected enum
```

This is the **same bug class** as the original `#io` regression — the x86 entry
got patched, the aarch64 entry did not.

## Minimal repro (7 lines, no stdlib data modules, no consumer code)

```cyr
# /tmp/pure.cyr
include "lib/syscalls.cyr"
#pure
fn f(): i64 { return 1; }
enum E { A; B; }
fn _m(){ return 0; }
var r = _m();
syscall(SYS_EXIT, r);
```

```
$ cyrius build --aarch64 --no-deps /tmp/pure.cyr /tmp/p
error:1087: unexpected enum
FAIL

$ cyrius build --no-deps /tmp/pure.cyr /tmp/p     # x86_64
OK
```

Drop the `#pure` line → aarch64 compiles clean. Any of `#io` / `#alloc` in the
same position reproduces identically.

## Real-world impact

Discovered bringing **thoth** to macOS/aarch64. thoth includes the `bayan`
stdlib module (json/toml/cyml/base64/bigint), which annotates several functions
`#pure` (e.g. `lib/bayan.cyr:327` `bayan_u128_eq`, `:335` `bayan_u128_is_zero`).
Result: a *trivial* `fn main(){return 0;}` that pulls thoth's stdlib set fails on
the **native arm64 cycc** at `error: unexpected enum`, ~line 1187 of bayan (the
first `enum`, `TomlError`, after the first `#pure` fn). bayan therefore cannot
compile on aarch64/macOS at all, so no bayan-consuming binary can be produced for
those targets. (ai-hwaccel avoids this only because it still uses the pre-carve
`json` module, not `bayan`.)

## Root cause (one spot)

- **x86_64 path (correct):** `src/main.cyr:1150-1166` — pass-1 silently consumes
  109/122/124/125/126/127; pass-2 (`src/main.cyr:1377-1391`) arms the pending
  flags via parse.cyr's directive dispatcher.
- **aarch64 path (missing):** `src/main_aarch64.cyr:306-402` — no such cases; the
  annotation token hits the `else { scan = 0; }` catchall at line **402**.

## Fix

Port the pass-1 annotation-consume from `main.cyr` into `main_aarch64.cyr`'s
`scan` loop, immediately before the `else { scan = 0; }` catchall at line 402:
add cases for tokens **109, 122, 124, 125, 126, 127** that advance the cursor
(`STI(S, GTI(S) + 1)`), with token 124 (`#deprecated`) also consuming its
optional `( STR )` arg — exactly as `main.cyr:1150-1166` does. Pass-2 already
handles the pending-flag arming generically, so no aarch64 pass-2 change should
be needed (mirrors the x86 fix shape).

A follow-up audit could DRY the two pass-1 scanners (`main.cyr` /
`main_aarch64.cyr`) so an annotation-token addition can't again land on only one
entry point — this is the second documented instance (`#io`, now `#pure`).

## Consumer-side workaround (if any)

There is **no clean consumer-side fix** that keeps `bayan` — the desync is in the
compiler entry point, not the consumer. Options for a consumer needing
aarch64/macOS before this lands:

1. **Best-effort lane** (recommended; mirrors daimon's aarch64 posture in the
   `2026-05-10` issue): the macOS/aarch64 build lane warns-and-continues on this
   specific `unexpected enum`, ships the other targets, and lights up
   automatically once the fix lands. No source change, nothing removed.
2. **Drop `bayan` for the pre-carve `json` / `toml` / `cyml` modules** (what
   ai-hwaccel does). Avoids the `#pure`-annotated `bayan`, but is a data-layer
   regression and an API churn — not recommended just to dodge a one-spot
   compiler fix.

## Verification plan (post-fix)

1. `/tmp/pure.cyr` repro: `cyrius build --aarch64` → OK.
2. Native arm64 self-host on `ecb` byte-identical (unchanged — scanner-only add).
3. `cyrius build` of a `bayan`-including trivial program on `ecb` → Mach-O arm64.
4. thoth native macOS build on `ecb` → Mach-O; aarch64-linux cross → ELF.

## Related

- The original `#io` instance — same root cause, x86-only fix (`#io` removed from
  the syscalls common file as the consumer-side stopgap):
  `docs/development/issues/archived/2026-05-10-daimon-async-aarch64-sys-epoll-wait.md`
  references the same pass-1-scanner-token theme.
- `src/main.cyr:1138-1148` — the v5.8.21 fix comment (authoritative description).
