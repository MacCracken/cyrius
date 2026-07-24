# `identifiers` pool capped at 256 KB — growable in place — RESOLVED

> **✅ RESOLVED in v6.4.76** (`src/frontend/lex.cyr`, `src/common/util.cyr`, `src/main.cyr`,
> `src/main_win.cyr` + heap-map comments; CHANGELOG [6.4.76]).
>
> Shipped the recommended **512 KB** in-place raise — a constants-only change. Verified against live
> code (line numbers had shifted from the 6.4.73 filing): the real LEX thresholds are `261872` in
> `NPOS_GUARD` + `LEXID` (not the "three size sites" the filing guessed), plus the util.cyr capacity
> divisor and the two `CYRIUS_STATS` meter denominators. All moved 261872→524016 / 262144→524288.
>
> The `0xA0000–0x100000` band was re-confirmed free in all 7 forks. Chose 512 KB over the 640 KB hard
> ceiling for a 128 KB margin below the `0x100000` physical end (`fn_name_hash`'s initial base) — a
> prominent comment now documents that ceiling (max safe threshold 655088; above it the pool overruns
> the hash/var tables and HANGS, which is what the filing's "hung indefinitely" observation was).
>
> **Verified:** a ~360 KB-identifier program errors on 6.4.75 and compiles+runs on 6.4.76; a >512 KB
> program still errors CLEANLY (no hang) at the new ceiling; 251/251 byte-identical; self-host +
> seed-derive + all four cross-OS hosts green; stiva now `identifiers: 243737 / 524288` (46 %, was
> 93 %). Added `_idpool_gate` (mutation-proven) + updated `_cap_drift_gate`. Neither the DCE bitmap
> nor the 1 MB jump was bundled, per the filing's guidance.
>
> Note the filing's cross-reference: the fn_table P0 it called "more urgent" shipped first (v6.4.75),
> so raising this cap does not now walk consumers into a silent corruption — both caps are fixed.

**Discovered:** 2026-07-23, from the **stiva** agent's `Compiler caps: … identifiers 92%` report.
**Severity:** **Medium–High** — a hard ceiling a shipping consumer is 8 % from, already forcing
codebase contortions; loud when hit, but with no grow path it is a dead end.
**Affects:** cycc **≤ 6.4.73**.
**Measured:** stiva 3.0.6 at **243737 / 262144 (93 %)**. cycc's own self-compile: 43090 (16 %).

## What it is

`tok_names` — a packed NUL-terminated **interned** identifier pool at `S+0x60000`, exactly 262144
bytes, ending at `0xA0000`. One 64-bit cursor `NPOS` at `S+0x18C128` (`GNPOS`/`SNPOS`,
`src/common/util.cyr:132-133`). `LEXID` (`src/frontend/lex.cyr:817`) is the primary writer: it appends
the candidate at `npos`, NUL-terminates, dedups via the length-bucketed lexid chain, and **rewinds the
cursor on a hit** — so the pool holds one copy of each *distinct* identifier, not one per occurrence.

Unlike `fixup_tbl` (`_fixup_base`/`_fixup_cap`), `codebuf` (`_codebuf_base`), the fn family
(`_fnt_*`) and the var family (`_var_cap`), **the pool has no base gvar and no cap gvar**. The base
`0x60000` appears as a bare immediate at ~362 sites across 22 files (94 in `parse_fn.cyr` alone), so
*relocating* it is a large mechanical change — but **growing it in place is not**.

## The consumer cost is already being paid

stiva has split its test suite **four separate times** explicitly to stay under this cap:

- `tests/mgmt.tcyr:2` — "Split from stiva.tcyr for the cycc identifier cap."
- `tests/store.tcyr:4` — "…pushed the monolithic stiva.tcyr past cycc's identifier cap"
- `tests/runpath.tcyr:2` and `:385` — "the monolith hit the cycc identifier cap"

That is a consumer restructuring its code around a compiler limit — the pattern
`feedback_dont_encode_codegen_bugs_as_language_rules` says to treat as a bug report against the
compiler.

## It IS growable in place — proven, not inferred

The band `0xA0000 – 0x100000` (393216 B) is **free of any occupant** in all 7 forks — verified by an
exhaustive scan of every `S + 0x…` / `= S + 0x…` / `S + <decimal>` form across the forks and the lib
files cycc includes. The only textual hits in that range are stale comments. The next real occupant is
`fn_deprecated_msg` at exactly `S+0x100000`.

**Empirically proven:** in a scratch copy of `src/`, changing *only* the size thresholds produced a
compiler that (a) **self-hosts byte-identical**, and (b) compiled a 965 KB single-file program at
`identifiers: 620015` — **2.37× the current cap**.

### The `input_buf` overlap does not forbid it

`input_buf` is `S+0 .. S+0x100000` and the preprocessor's include-fixpoint copy-back
(`src/frontend/lex_pp.cyr:2229-2232`) rewrites `S+0 .. S+0xFFFFF` on every iteration, so the pool
region *is* clobbered during preprocessing. **The invariant is temporal, not spatial**: all
`input_buf` writes complete inside `PREPROCESS` before `LEX` starts filling the pool. Growth is
therefore safe, bounded by the pool's *end*.

### The exact ceiling

**Pool END must stay ≤ `0x100000`.** Base is `S+0x60000`, so the maximum pool SIZE is
`0x100000 − 0x60000` = **`0xA0000` = 655360 bytes (640 KB)** — a **2.5×** raise. Note this is a bound
on size, not a bound of `0x100000` on size: a 0x100000-byte pool would end at `0x160000` and overwrite
`fn_deprecated_msg` / `fn_name_hash` / the var tables.

**Crossing the ceiling is NOT a clean error today** — with the threshold set past `0x100000` the
compiler **hung indefinitely with zero diagnostic**. Any raise must move the threshold *and* keep it
strictly under the end bound.

## Proposed fix — 256 KB → 512 KB, constants only

No region moves, no base changes, no `brk`/`mmap` change (the pool already lives inside the mapped
`input_buf`), no new physical memory (lazily mapped; untouched pages cost nothing). **Not** a layout
change, so the v6.4.10-class two-step-for-sizing rule does not bite — but cycc's own binary changes
(different immediates), so the normal fixpoint + seed-derive gates apply.

Sites (a reviewer corrected the initial count from two to **three** — verify each):

- `src/frontend/lex.cyr:802` and `:818` — the `261872` thresholds (keep the 272-byte slack)
- `src/common/util.cyr` — the third size site the audit found; confirm before editing
- `src/frontend/lex.cyr:805` / `:821` — error strings `/262144 bytes)`
- `src/common/util.cyr:381/383/385` — `_capacity_warnings` divisor + message
- `src/main.cyr:2064` and `src/main_win.cyr:992` — the `CYRIUS_STATS=1` denominator
- the heap-map comment at `src/main.cyr:29`

## Do NOT bundle

- **The DCE referenced-name bitmap.** It is the only structure *indexed by* a tok_names offset
  (8192 B at `S+0x1DA000`, `src/main.cyr:1337`) but it is **already decoupled** from the pool size —
  producer (`:1348`) and consumer (`:1566`) both guard `noff < 65536`, covering only the first 64 KB,
  and the out-of-range path is **fail-safe** (the fn is kept, not stubbed). Growing it to cover
  512 KB would fit in the `0xE0000–0x100000` remainder, but DCE stubbing is unconditional
  (`main.cyr:1598-1665`, not env-gated), so newly-covered names would *start* being stubbed — a real
  behaviour change for exactly the large consumers this is meant to unblock.
- **Getting to 1 MB.** That requires relocating the `0x100000–0x160000` occupants and is a separate
  project.

## Note the interaction with the fn_table P0

A consumer hitting the identifier cap is, by construction, a consumer with a very large include
closure — i.e. one also approaching **8192 functions**. See
[`2026-07-23-fn-table-growth-past-8192-corrupts-fixed-side-tables.md`](./2026-07-23-fn-table-growth-past-8192-corrupts-fixed-side-tables.md),
which is the **more urgent** of the two: the identifier cap fails loudly, the fn_table one corrupts
silently. Raising the identifier cap *without* fixing fn_table would let consumers build bigger units
and walk into the silent one.
