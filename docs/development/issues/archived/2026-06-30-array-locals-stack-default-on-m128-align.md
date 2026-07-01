# Array locals — make per-thread stack-allocation the DEFAULT (blocked on m128 16-alignment)

**Filed:** 2026-06-30 (v6.3.13 — follow-on to the str_builder concurrency fix)
**Severity:** **P1 — concurrency correctness.** Array locals are thread-unsafe by
default; the fix exists but is opt-in until the alignment work below lands.
**Status:** ✅ **RESOLVED — v6.3.15 (default-on).** Per-thread array locals are now
the DEFAULT (`CYRIUS_STACK_ARRAYS=0` opts back to legacy global). Both default-on
blockers landed: (1) **m128 16-alignment** — a one-slot parity pad when `&arr` disp
≡ 8 (mod 16), so `pxor`/`aesenc xmm,[arr]` stays `#GP`-free; (2) **`secret var`
zeroise** addresses the local slot (`ELOAD_LOCAL_ADDR`), not global `EVADDR`. Plus
an **auto-fallback** (an array exceeding the per-fn 16384-slot budget stays global
with a `note:` — sole case: sigil `hash_file_into`'s 256 KB buffer, already global →
no regression). The feared "ecosystem footgun" was a FALSE ALARM from a buggy scan
that mis-flagged element-typed `var x: i64[N]` as bare: a precise width+element-
typed-aware audit (11-file agent workflow) confirmed **295 bare-array locals, 0
over-runs — ZERO stdlib changes**. Six `.tcyr` suites using the daimon under-
declared-array idiom were corrected to element-typed decls. Two-step bootstrap;
cycc SHRANK 1,111,616→1,027,664 B. Release gate GREEN (check.sh 109/109; seed→cybs→
cycc; ecb+cass+pi SELFHOST_OK; bench 544 ms). See CHANGELOG [6.3.15].

## Background (root cause — fixed opt-in in v6.3.13)

`var arr[N]` LOCALS (declared inside a function) were allocated at a **fixed
global/BSS address shared by every thread** (scalar locals already stack-allocate
per-thread; array locals went through the global var table → `dbase + offset`).
So any concurrent path using an array-local aliased one global buffer → cross-thread
byte splice (~87% corruption). This was the real root cause of
[`str-builder-not-thread-safe`](2026-06-28-str-builder-not-thread-safe.md) — NOT a
str_builder logic bug. It also surfaces as the multi-worker TLS `BAD_SIGNATURE`
(two workers' response buffers overlap; one mutates while the other MACs it).

**v6.3.13 fix (opt-in `CYRIUS_STACK_ARRAYS=1`):** `PARSE_ARRAY` (parse_decl.cyr)
routes an array LOCAL to `ceil(size/8)` per-thread STACK slots (the struct-local
multi-slot mechanism: anonymous fillers + one named slot at the deepest offset, so
`&arr` = `lea [rbp-disp]` points at `arr[0]`). The existing `&arr`/`arr[i]`/store
paths already check `FINDLOCAL`→`ELOAD_LOCAL_ADDR` before the global fallback, so no
per-backend emit change was needed — one shared-frontend change covers x86 +
aarch64 + all 7 forks. Gate: `_ensure_stack_arrays` (parse.cyr). `THREAD_STACK_SIZE`
bumped 64KB→2MB (lib/thread.cyr) so large array-locals fit on a spawned thread's
stack (a per-call heap path was rejected — the bump allocator has no `free()`).

**Validated opt-in:** str_builder `sb_fail 0`; per-thread on x86 + aarch64(qemu);
cycc self-hosts with the flag (binary SHRANK 1,111,576→1,023,464 B — arrays left
BSS); fixpoint + seed→cybs→cycc byte-identical; flag-off differential byte-identical.

## The default-on blocker — SSE m128 16-byte alignment

Flipping the flag default-on (two-step bootstrap; it self-hosted + seed-derived)
turned the release gate **RED with 5 regressions**, the core being **m128
alignment**:

- **Inline-asm m128 operands** (`tests/regression-inline-asm-discard.sh`, the
  `var round_keys[240]` / AES-NI shape): `pxor xmm, [arr]` / `movdqa` / `aesenc`
  REQUIRE a **16-byte-aligned** memory operand. Global arrays got that via the
  v5.5.21 `totvar` pad (the array's VA was forced 16-aligned). **Stack slots are
  only 8-aligned**, so the m128 op faults / writes 0 bytes. Affects sigil crypto,
  AES-NI, anything using `var k[N]` as an SSE operand.
- **TLS probe compile failure** (`cycc compile of TLS probe failed`,
  `tls_native kernel-link rc=256`) — likely the same alignment / a large-array
  interaction; needs its own repro.
- **install.sh --refresh-only shim test** cascaded (version-resolution); re-check
  once the above are fixed (may be a downstream artifact).

## Fix plan (the arc)

1. **16-align array-local stack slots.** Ensure each array local's base
   `[rbp - disp]` is `≡ 0 (mod 16)`. `rbp` is 16-aligned by the SysV/AAPCS frame
   contract, so pad the frame so the array's named (deepest) slot lands on an even
   slot index (`disp ≡ 0 mod 16`). Mirror the v5.5.21 intent (16-align arrays used
   as m128 operands) but on the stack. Conservatively 16-align ALL array locals
   `> 8 bytes` (cheap; avoids needing to detect m128 use at decl time).
2. **Root-cause the TLS-probe compile failure** under stack arrays (separate repro).
3. **Re-flip default-on** + two-step bootstrap; **the m128 regression suite +
   multi-worker-TLS round-trip are the canaries.** Re-run the full release gate.
4. **Zero-init decision** (deferred): stack arrays are garbage vs BSS-zero. cycc
   self-hosts + check.sh pass without it (cyrius idiom is write-before-read), but a
   consumer relying on zero-init would break — add a `memset`-on-entry if any does.

## Acceptance

Default build (no flag): array locals per-thread; the str_builder 8-thread repro =
0 corrupt; the multi-worker-TLS round-trip succeeds; `tests/regression-inline-asm-
discard.sh` + the m128/AES-NI gates green; full release gate GREEN (seed-derive +
cross-OS); cycc self-hosts byte-identical. Then `CYRIUS_STACK_ARRAYS=0` becomes the
opt-OUT (legacy shared-global) and this issue closes.
