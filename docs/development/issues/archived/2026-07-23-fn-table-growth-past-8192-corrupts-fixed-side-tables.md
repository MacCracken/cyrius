# P0: `fn_table` growth past 8192 silently corrupts six fixed fn-indexed side tables — RESOLVED

> **✅ RESOLVED in v6.4.75** (`src/common/util.cyr`, `src/frontend/parse_fn.cyr`,
> `src/backend/{x86,aarch64}/fixup.cyr`; CHANGELOG [6.4.75]).
>
> All four proposed items shipped, plus the stale-doc cleanup:
> 1. **The six side tables** (`fn_deprecated_msg`, `fn_regalloc`, `fn_ret_sid`, `fn_variadic`,
>    `fn_flags`, `fn_var_bytes`) now use the lazy-alloc-at-32768 pattern (the `_fnt_tparams` /
>    `_vsgn_base` precedent) — each a `_fn*_base` gvar alloc'd max-sized on first write, never grows,
>    **no per-fork edit, no `_fnt_grow` change**. The six fixed heap bands are freed.
> 2. **`REGFN`'s forward-overload write** now goes through the relocatable `_fnt_ovstr`/`_ovint`/
>    `_ovcstr` pointers instead of the stale `S + 0x97A000` base.
> 3. **The DCE `live[]` clear loop** now covers all 4096 bytes (was 1024) on both x86 and aarch64 —
>    the uninitialised-stack tail is gone. Confirmed it was the *diagnostic-only* (conservative:
>    unreachable-fn kept, never a reachable one dropped) severity, but fixed regardless.
> 4. **The capacity warning + `CYRIUS_STATS` meter** now report against the true 32768 ceiling, not
>    the live `_fnt_cap` — 7443 fns (stiva) reports 22 % / no warning; 28000 warns "85 %".
> 5. **`_fn_grow_gate`** added to check.sh (the twin of `_var_grow_gate`) — mutation-proven.
>
> **Verified:** the exact `#must_use`-at-8250 repro is fixed; **251/251 tcyr byte-identical** to
> 6.4.74 (pure storage relocation); self-host fixpoint + seed-derive + all four cross-OS hosts green;
> stiva 3.0.6 builds + passes all 207 tests and now reports `fn_table: 7443 / 32768`. Growth tax
> +1.0 % self_compile (the lazy guard on the six hot accessors).
>
> One item from the "Related" section confirmed as recorded: the 2-byte hash slot is not the binding
> constraint (ceiling `fi+1 ≤ 65535`, above the 32768 `_fnt_grow` cap).

**Discovered:** 2026-07-23, while investigating the **stiva** agent's report of
`Compiler caps: fn_table 90%, identifiers 92%`.
**Severity:** **Critical** — silent wrong code generation with no diagnostic, on any compilation unit
above 8192 functions. CVE-class per the issues README ("silent data corruption").
**Affects:** cycc **v6.2.0 → 6.4.73** (introduced by the v6.2.0 growable-fn_table migration).
**Reported cap pressure:** stiva 3.0.6 is at **7443 / 8192 (90.8 %)** — roughly **750 functions**
from crossing this line.

## Summary

`_fnt_grow` (`src/frontend/parse_fn.cyr:98`) has grown the fn-table family since v6.2.0, doubling the
17 `_fnt_*` pointer-backed tables and both 2-byte hashes up to a loud ceiling of 32768. **But six
other tables keyed by the same fn index `fi` were never migrated.** They remain fixed 8192-slot bands
at literal heap offsets, packed back-to-back, with no bound check:

| Table | Base | Next occupant at +64 KB |
|---|---|---|
| `fn_deprecated_msg` | `0x100000` | `0x110000` fn_name_hash (initial base) |
| `fn_regalloc` | `0x14A000` | `0x15A000` fn_ret_sid |
| `fn_ret_sid` | `0x15A000` | `0x16A000` fn_variadic |
| `fn_variadic` | `0x16A000` | `0x17A000` fn_flags |
| `fn_flags` | `0x17A000` | `0x18A000` → **`0x18C100` core compiler scalars** (BL/CP/VCNT/TCNT/TI/NPOS) |
| `fn_var_bytes` | `0x1C8000` | `0x1D8000` enum_const_val (`_vecv_base`) |

Each band is exactly `8192 × 8 B = 64 KB` and they abut, so **index 8192 of each table IS index 0 of
its neighbour.** `REGFN` (`parse_fn.cyr:142`) calls `_fnt_grow` silently — there is no error at 8192,
the compiler grows straight through into the corrupt regime.

This is the **identical bug class** the v6.3.0 CHANGELOG describes for the *var* family ("not 3 tables
but a family of SEVEN … any unmigrated one silently overflows once the family grows past 8192"). The
fn-family repeat was never caught because **there is no >8192-fn test anywhere in check.sh**.

## Reproduction — verified live on this machine, one index apart

`PARSE_FN` unconditionally resets per-fn metadata for every definition (`parse_fn.cyr:2606`
`S64(S + 0x1C8000 + fi*8, 0)`, `:2610` `SFRS(S, fi, 0)`, `:2613` `SFVA(S, fi, 0)`). At `fi ≥ 8192`
those writes land in the *neighbouring* table at index `fi − 8192`.

Generate 8300 trivial fns, put `#must_use` on **fn 58**, discard `g58()`'s result, and vary only which
high fn is reachable:

```sh
# reachable fn 8250   (8250 - 8192 = 58)  -> flag WIPED, no warning at all
# reachable fn 8251                        -> warning fires correctly
```

Observed:

```
--- reachable fn = 8250 ---
(no output — the #must_use diagnostic is silently gone)
--- reachable fn = 8251 ---
warning:<source>:8304:4: #must_use result of 'g58' is discarded
```

A one-index control. The corruption is exact and deterministic.

Further symptoms found in the same investigation (independently reported, worth confirming during the
fix): `#must_use` on reachable fn 9249/9252 writes into the **core compiler scalars** at `S+0x18C100`
(`fn_flags` base `0x17A000 + 9249*8` reaches past the `0x18A000` band end into `0x18C100` = GCP/GTI)
and produces spurious `'nNNNN' is deprecated` warnings; and an enum constant's bit-63 fold marker is
wiped, which drops `_cfo`/`sc_num` and therefore **silently disables the PE/Mach-O syscall reroute**.

## The warning goes silent at exactly the wrong moment

`_capacity_warnings` (`src/common/util.cyr:376`) computes `fn_table%` against the **live** `_fnt_cap`,
not a fixed 8192:

| fns | `_fnt_cap` | reported | warning? |
|---|---|---|---|
| 8191 | 8192 | 99 % | **yes** — "split into compilation units soon" |
| 9000 | 16384 | 54 % | **no warning at all** |

Verified: a 9000-fn unit compiles with `fn_table: 9000 / 8192` in `CYRIUS_STATS=1` and **zero**
capacity warnings. So a consumer who does exactly the right thing — heeds the 85 % warning, keeps
growing, watches it disappear — reads the silence as "I fixed it", precisely when silent corruption
begins. **This is the "our gate can't see this" P0 smell, not a caveat.**

## Why this matters right now

stiva is the closest consumer at 7443/8192 and has already **split its test suite four separate times**
to dodge the *identifier* cap (`tests/mgmt.tcyr:2`, `tests/store.tcyr:4`, `tests/runpath.tcyr:2,385`).
Its fn_table is 91 % vendored stdlib — `lib/` declares 6562 fns to `src/`'s 633 — and **5469 of the
7443 are unreachable** (DCE NOPs the code but slots are allocated at parse time, so DCE does not
reclaim them: measured identical 7443 with and without `CYRIUS_DCE=1`). Any consumer adding one more
dep bundle crosses 8192.

## Proposed fix

**Do NOT extend the `_fnt_grow` chain** — `src/common/util.cyr:39-65` records that adding an 8th link
to the *var* grow chain DESYNCED cybs, and that inlining 4 grows in one fn segfaults gen1.

Follow the documented **v6.4.23 `_vsgn_base` precedent** instead: `alloc()` each of the six stragglers
**MAX-sized at driver init** so they never grow, exactly as `_vsgn_base` does ("alloc'd MAX-sized at
init, so it never grows … 8 MB lazy-mapped is ~free"). This sidesteps the cybs-fragile grow chain
entirely, is not a heap-layout change (the tables move *off* heap), and lazily-mapped untouched pages
cost nothing.

Additional items that must land in the same fix (a bug ships complete):

1. **`REGFN`'s forward overload-registration site** (`parse_fn.cyr:169-172`) still writes the
   hardcoded pre-grow bases `S + 0x97A000 / 0x98A000 / 0x99A000` — it does not follow the relocated
   `_fnt_*` pointers. Verify and migrate.
2. **The DCE `live[]` bitmap** — `var live[4096]` (4096 **bytes** = 32768 bits) is zeroed for only
   1024 bytes (`src/backend/x86/fixup.cyr:360-362`, `src/backend/aarch64/fixup.cyr:301-303`;
   introduced by the same v6.2.0 commit `9b1c724a`). With `_STACK_ARRAYS` default-on since v6.3.15 the
   untouched tail is live stack garbage. Independently reported as producing non-deterministic
   unreachable-fn counts across identical runs; an adversarial reviewer downgraded this to a
   *diagnostic* defect rather than a codegen one — **confirm which before deciding severity**, but fix
   the clear/declare mismatch regardless. `if (t3idx < 32768)` at `fixup.cyr:428` must move in lockstep.
3. **Make the capacity warning honest** — report against the *effective* ceiling, and warn loudly on
   crossing 8192 for as long as the side tables are fixed. A silent grow into a corrupt regime is
   worse than a hard error; until the six tables are migrated, **erroring at 8192 would be safer than
   today's behaviour**.
4. **Add a >8192-fn gate to check.sh.** Its absence is why a whole bug class survived two migrations.
   The `#must_use`-at-`8192+N` repro above is a ready-made mutation-provable gate.

## Stale documentation found alongside

- `src/backend/x86/fixup.cyr:394`, `src/backend/common/runtime.cyr:436-442`, and the `src/main.cyr`
  heap map at `:293`/`:305` all still describe "8192 slots × 2B … mask 8191". The code has used
  dynamic `_fnt_cap` / `_fnt_hash_mask` since v6.2.0.
- `src/common/util.cyr:190` and the v6.2.0 CHANGELOG claim cycc itself is at "6486 (79 %)". Live
  measurement: **1135 / 8192 (13.9 %)**. cycc is nowhere near the cap, which is exactly why this never
  surfaced in-repo — the same "found by ports" shape as the macOS self-host rot.

## Related

The **2-byte hash slot is NOT the binding constraint** (a common assumption worth recording as
disproven): `_fnt_hash_mask` and every probe bound are dynamic; `store16` truncates mod 65536, so the
hash slot's own arithmetic ceiling is `fi + 1 ≤ 65535`, i.e. 65535 fns — far above the 32768
`_fnt_grow` ceiling and irrelevant at 8192.
