# Bare `var X[N]` global silently under-sized 8x when declared AFTER the first bare top-level statement

- **Filed**: 2026-07-05 (during agnos kernel FP/SIMD B5 work; surfaced as a ring-3 #PF, root-caused to array sizing)
- **Severity**: P1 (silent 8x under-size of a top-level array → BSS buffer overflow → memory corruption; compiles clean, only surfaces downstream. Opt-in to hit: you must declare a top-level array and overrun it — but when hit it is a hard-to-trace corruption, not a fail-safe miss). **Review after the current SIMD work lands.**
- **File**: `src/frontend/parse_decl.cyr` — the bare-array element-width default in `PARSE_ARRAY` (line 59) vs `PARSE_GVAR_ARR` (lines 699–701); split driven by `src/main.cyr` pass-1 terminator (line 1314)

## Symptom

Identical `var X[N]` syntax, same translation unit, same target — sized **N bytes** when the declaration lexically FOLLOWS the first bare top-level statement, but **N×8 bytes** when it PRECEDES it (or lives in an included pure-declaration module, which is always ahead of the top-level file's bare statements in the concatenated stream).

Empirical matrix (measured this session; cyrius 6.4.8). Method: declare `var A[N]; var Amarker = 0;` pairs at the same scope; the byte gap `&Amarker - &A` is A's allocated size (two consecutive i64 scalar globals are 8 bytes apart, so the subtraction is a raw byte count).

AGNOS-KERNEL build (`cyrius build --agnos`, freestanding, `FP_CTXSW_SELFTEST=1`):
- **Included module** `kernel/core/proc.cyr` (pure decls, no bare statements): `X[8]`→64, `X[24]`→192, `X[128]`→1024, `fpu_state[1026]`→8208. **N×8 (N×u64).**
- **Top-level program file** `kernel/core/main.cyr` (contains bare entry statements): `X[8]`→8, `X[24]`→24, `X[64]`→64, `X[128]`→128, `X[1026]`→~1032. **N bytes (N×1).**

HOST build (`cyrius build arrsize.cyr out`, x86_64, all arrays at TOP of file above the first bare statement): `X[1]`→8 … `X[1026]`→8208 — **all N×8.** The all-before-bare layout hides the anomaly. Note: the host top-level does NOT surface the N-byte anomaly on its own — because in that repro every array is declared before the trailing `_entry();`, so all sit in the pass-1 zone. The N-byte behavior requires an array *after* the first bare statement (see the isolation repro, which reproduces it on plain host).

HOST isolation repro (single top-level file, non-agnos, non-kmode): `var BEF[24]` above the first bare statement measured **192** (24×8); `var AFT[24]` below it measured **24**. Same syntax, same file, same target — only position differs. (Confirmed live this session — see Repro below; the reader function must be defined *after* the arrays for the measurement to reflect the pass-2 size, see the note in that section.)

The bug it caused: agnos `kernel/core/main.cyr` had `var fpctxsw_payload[24]` (top-level) intended as a ≥113-byte ring-3 code buffer. Because the top-level post-bare-statement path sizes `var X[24]` at only 24 bytes, a ~103-byte hand-assembled payload written via `store8(p+i, …)` overflowed 79 bytes past the buffer into the following globals (`fpctxsw_wit_a/b/shared`), corrupting a witness page-table pointer → the proc's witness PDE was built from a garbage phys → ring-3 `#PF (v=0e e=000c, User+RSVD)`. Fixed by declaring `var fpctxsw_payload[256]`; reverting to `[24]` reproducibly re-broke it.

The existing agnos memory rule "module-global `var X[N]` = N×u64" is TRUE for included modules but FALSE for the top-level program file after its first bare statement.

## Why it's been invisible

The 8x under-size is **silent** — no diagnostic. It compiled clean and only surfaced ~3500 lines downstream as a ring-3 page fault. It is masked in the common case because:

- Included modules are pure declarations with no bare statements, so all their globals sit in the correctly-sized (N×8) pass-1 zone.
- The standard "declare everything at the top of the file" style (as in the `arrsize.cyr` host repro) puts every array ahead of the trailing `_entry();`, so they too land in the pass-1 zone → all N×8, no anomaly visible.
- Element-typed forms already agree in both paths (`var g: u8[N]` = N, `var g: i64[N]` = 8N via explicit element width). Only the **bare** `var X[N]` default (element width 1 vs 8) disagrees, so the blast radius is bare top-level arrays declared after the first bare statement.

To hit it you must specifically declare a bare top-level array after top-level executable code AND overrun its intended (larger) size — exactly the `fpctxsw_payload` case.

## Root cause

*Confirmed from source (cyrius 6.4.8) — line numbers verified against `/home/macro/Repos/cyrius`.*

cyrius parses each translation unit (all `include`d modules expanded in-place ahead of the top-level file, lexed as one stream) in TWO passes, and the two passes size bare arrays through **different code paths with different element-width defaults**:

- **Pass-1 path (N×8)** — `PARSE_GVAR_ARR`, `src/frontend/parse_decl.cyr:699-701`: `var ar_ew = ew; if (ar_ew < 1) { ar_ew = 8; } var sz = sz_raw * ar_ew;`. Bare `var g[N]` has `ew==0` → element width defaults to **8** → N×8 bytes. Registered at `parse_decl.cyr:706-707`.
- **Pass-2 path (N)** — `PARSE_ARRAY`, `src/frontend/parse_decl.cyr:59-60`: `var aligned = (asz + 7) & (0-8); if (ew > 0) { aligned = (asz*ew + 7) & (0-8); }`. Bare `var g[N]` has `ew==0` → element width **1** → N bytes rounded to 8. Registered at `parse_decl.cyr:128-131`. This is the SAME path used for function-local arrays.

Both write the per-gvar byte size into the single `var_sizes` table (`_vars_base = S+0x12A000`), which every backend's `.bss` emitter byte-copies (e.g. `src/backend/x86/fixup.cyr:108`, `totvar = totvar + L64(_vars_base + vi*8)`). Whichever value was written wins.

Which pass sees a decl is decided by **token position relative to the first bare top-level statement**:

- **Pass 1** (`src/main.cyr:1175-1315`) is a top-of-file declaration pre-scan (`while(scan==1)`) dispatching only `mod`/`pub`/`use`/`struct`/`union`/`var`/directives (plus `fn`/`enum`/`impl`/kernel-mode markers). A global `var` (token typ 3) routes `PARSE_GVAR_REG` (`main.cyr:1228`) → `PARSE_GVAR_ARR` (N×8). **Crucially, the loop's catch-all `else { scan = 0; }` at `src/main.cyr:1314` terminates the pre-scan at the FIRST token that is not one of those declaration keywords — i.e. the first bare top-level executable statement (a call/assignment).** Any `var X[N]` after that point is never seen by pass 1.
- A second declaration loop then re-walks the stream and halts identically at its own catch-all `else { topgo = 0; }` (`src/main.cyr:1661`); in that loop a `var` token is merely SKIPPED (`main.cyr:1654-1657`) because pass 1 already registered it.
- The saved cursor (`gvar_save_ti`, `src/main.cyr:1736`) is where `PARSE_PROG` resumes (`src/main.cyr:1757` kernel-mode `_init_km==1` / `1805` otherwise). It parses everything from the first bare statement to EOF as STATEMENTS; a `var X[N]` there goes `PARSE_PROG` → catch-all `else { PARSE_STMT(S); }` (`parse.cyr:1328`) → `PARSE_STMT` (`parse.cyr:762`, typ 3 → `PARSE_VAR`) → `PARSE_ARRAY` (`parse_decl.cyr:1976-1977`) → N.

For the agnos kernel TU (`kernel/agnos.cyr`): `include`s pure-decl modules first (`core/proc.cyr` at line 49) and `core/main.cyr` last (line 119). `proc.cyr`'s `var fpu_state[1026]` (proc.cyr:150) sits before any bare statement → pass 1 → 8208 bytes (measured). `main.cyr`'s first bare statement (`vmm_remap_wc_range(...)` at line 25, then `fb_console_init();` at line 30) STOPS pass 1; `var fpctxsw_payload[…]` at `main.cyr:3563` (~3500 tokens later) → `PARSE_PROG` → `PARSE_ARRAY` → N bytes. Hence identical `var X[24]` = 192 in `proc.cyr` but 24 in `main.cyr`, in the same compile.

Confirmed independent of target/freestanding/kmode: the host isolation repro (below) reproduces the BEF=192 / AFT=24 split on plain x86_64, non-agnos, non-kmode. **The trigger is lexical position relative to the first bare top-level statement — not `--agnos`, not freestanding, not kernel-mode.**

A related secondary symptom of the same pass split: a global `var` declared AFTER the first bare statement is not registered in pass 1, so a function defined *earlier* in the file that references it does not bind to the pass-2 declaration — it either fails with "undefined variable" or (as observed in the repro work) resolves to the pass-1 view. This is why the isolation repro must define its measuring function *after* the arrays (see Repro). Worth noting to the author as corroboration.

## Fix sketch

*NOTE: cyrius is hands-off — this is surfaced for the cyrius author to confirm and implement, not to be implemented here. Represent the fix as a proposal.*

Make the two paths agree on the bare `var X[N]` element-width default for **true top-level globals**. Cleanest source-level fix: in `PARSE_ARRAY` (`parse_decl.cyr:59-60`), when the array is NOT a real function-local (the same top-level condition already used nearby — `GINFN(S) != 1` / `_cur_fn_ix < 0`, cf. `parse_decl.cyr:137`), size bare `var X[N]` at N×8 to match `PARSE_GVAR_ARR`, so a top-level array gets the documented N-u64 size regardless of which pass parsed it. True in-function locals keep the N-byte rounding (unchanged).

Alternatives:
- Teach pass 1 (`src/main.cyr:1178-1314`) to keep scanning declarations past bare top-level statements — a larger structural change to the pre-scan loop; the `PARSE_ARRAY` element-width unification is the minimal, targeted fix.
- Cheapest non-compiler workaround (documentation-only): require element-typed spelling for post-bare-statement top-level arrays — `var X: u64[N]` / `var X: i64[N]` flows `ew=8` through `PARSE_ARRAY` and yields N×8 explicitly. This is the interim consumer-side guard.
- Independent interim guardrail: warn when a bare `var X[N]` global is registered in the `PARSE_PROG` (post-bare-statement) zone, since that is exactly the surprising case.

Items for the author to confirm before unifying:
1. Unifying on N×8 could grow the `.bss` of existing top-level programs that (knowingly or not) relied on the N-byte size for post-bare-statement globals — a subtle footprint shift. Growing is the safe direction (under-sizing is the latent bug), but grep consumers for top-level `var X[N]` whose intended size is genuinely N bytes.
2. At true top level `PARSE_ARRAY`'s v6.3.13 stack-array path is inert (`GINFN(S) != 1` → `sa_on` stays 0, `parse_decl.cyr:76`), so it takes the global-BSS branch (`:128-131`) — confirmed, but re-check no future change lets a top-level array wander into the per-thread stack-slot path.
3. Kernel-mode vs normal mode (`PARSE_PROG` at `main.cyr:1757` vs `1805`) affects emit ORDERING only, not sizing — both go through `PARSE_ARRAY`. Confirmed by the non-kernel host repro reproducing the split.

## Repro

Minimal, host x86_64, cyrius 6.4.8. **Verified live this session** — builds clean and prints `192` then `24`. Also placed at `docs/development/issues/repros/2026-07-05-toplevel-bare-array-8x-undersize.cyr`.

Two structural requirements, both load-bearing (an earlier draft that violated them did NOT reproduce the split — it printed the pass-1 size for both arrays):
1. The measuring/printing function must be defined **after** the arrays and invoked via a bare statement, because a global declared after the first bare statement is not visible to functions defined earlier (see the secondary symptom above).
2. Stay dependency-free: use raw `syscall(60, …)` to exit and hand-roll the decimal print — do NOT use `SYS_EXIT` / `println_i64`, which require includes not present in a bare host build. (Do not use an `as` cast on `&BEF`; plain pointer subtraction yields the byte gap directly.)

```cyrius
# Does the SAME `var X[N]` size differently depending on whether it appears
# BEFORE (pass-1 declaration zone) or AFTER (PARSE_PROG statement zone) the
# first bare top-level statement?

var BEF[24];   var BEFm = 0;    # BEFORE the bare stmt -> pass-1 PARSE_GVAR_ARR (expect 192 = N*8)

fn pr(label: i64, len: i64, n: i64): i64 {
    syscall(1, 1, label, len);
    var tmp[32];
    var tp = &tmp;
    var ti = 0;
    var v = n;
    if (v == 0) { store8(tp, 48); ti = 1; }
    while (v > 0) { store8(tp + ti, 48 + (v % 10)); v = v / 10; ti = ti + 1; }
    var buf[34];
    var bp = &buf;
    var bi = 0;
    while (ti > 0) { ti = ti - 1; store8(bp + bi, load8(tp + ti)); bi = bi + 1; }
    store8(bp + bi, 10); bi = bi + 1;
    syscall(1, 1, bp, bi);
    return 0;
}

nop_first();   # FIRST bare top-level statement -> HALTS the pass-1 pre-scan
fn nop_first(): i64 { return 0; }

var AFT[24];   var AFTm = 0;    # AFTER the bare stmt -> PARSE_PROG PARSE_ARRAY (expect 24 = N)

# reader defined AFTER the arrays so it can see the pass-2 `AFT` declaration
report();
fn report(): i64 {
    pr("BEFORE size[24] = ", 18, &BEFm - &BEF);   # 192  (24 * 8, pass-1 path)
    pr("AFTER  size[24] = ", 18, &AFTm - &AFT);   #  24  (pass-2 PARSE_ARRAY path)
    return 0;
}

syscall(60, 0);
```

Build/run: `cyrius build 2026-07-05-toplevel-bare-array-8x-undersize.cyr out && ./out`. Actual (buggy) output, verified:

```
BEFORE size[24] = 192
AFTER  size[24] = 24
```

Same syntax, same file, same host target — only position across the first bare statement differs. (An earlier attempt that defined the reader *before* the bare statement instead printed `192` for the AFTER line too, because the early-defined reader binds to the pass-1 view of `AFT` — a direct manifestation of the secondary symptom above, and the reason the reader must come last.)

## Why deferred

- The discriminator is fully root-caused and the fix is a one-site element-width unification, but any change to top-level array sizing shifts `.bss` layout/footprint for existing programs and wants a deliberate re-baseline, not a silent bundle into a SIMD release.
- Impact is opt-in (declare a top-level array after top-level code and overrun it) and has a known consumer-side workaround today (`var X[256]`, or element-typed `var X: u64[N]`), so agnos is unblocked.
- **Review after the current SIMD work lands**, in a dedicated frontend-correctness slot.
