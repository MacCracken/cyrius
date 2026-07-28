# Handoff — v6.4.x is CLOSED at **v6.4.85**. **v6.5.0 opens on `public`/`private`.**

> **Written 2026-07-27**, at the v6.4.x closeout. Read this, then `CLAUDE.md`, then
> [`state.md`](state.md). **Refresh or delete this file when v6.5.0 ships** — a stale handoff is
> worse than none.

---

## Where things stand

| | |
|---|---|
| Version | **6.4.85** — the v6.4.x CLOSEOUT (85 releases in the minor) |
| cycc x86_64 | **1,112,464 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **150 / 0** + 3 shell gates · release gate GREEN all 5 steps |
| Cross-OS | ecb · ach · cass · pi — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on real hardware |
| Corpus | **251** `.tcyr` (per-file exit-code loop, not the grep summary) · 99 `lib/*.cyr` · api-surface **4749** |
| Heap | **100** regions, 0 overlaps |
| self_compile | **628 ms** (historical band 614–634) |
| Open issues | **11** · 3 proposals · 274 archived |

## What the closeout actually taught us

**The audit displaced two releases, and that is the argument FOR running it.** .80 became
`1 - 2 + 3` == **5**. .81 became a **fourth** `_cfo` occurrence (`p * 3 + 1` == 4) plus CVE-32/33/34.
.82 is the closeout proper. All three were found by *running the compiler* while checking something
else — the .80 find came from an adversarial verifier checking a **vidya** claim about precedence,
and the .82 parser gap (below) came from the vidya sweep doing the same thing.

Three recurring shapes, now written into `gotchas.cyml`:

1. **The map/gate described something other than what the code did.** `include_fname` was documented
   at an address no code has ever written, so `heapmap.sh` validated a fiction for three minors while
   an `include` path could smash the heap. The size regex could not see 20 MB of live heap. An ASCII
   collision let a mutated syscall number PASS. **Mutation-prove every gate.**
2. **Fixes scoped to the reported operator instead of the shape.** The `_cfo` class was "fully fixed"
   three times before .81 found the fourth tier.
3. **A checklist entry is not a gate** — .77 fixed a doc-rot class, added a checklist item, and a row
   went stale two releases later. Hence `_doc_stamp_currency_gate`.

## ⚠ Open, live, and worth reading first

`issues/2026-07-27-intrinsics-cannot-flank-a-term-tier-operator.md` — **`a * f64_from(2)` is a syntax
error**, both operand positions, for `* / % << >> >>>` (the `+`/`-` tier is fine). Affects every
`f64_*`/`f32_*`/`iv_*` intrinsic plus `bitget`/`store*`/`u128`/`ret2`. Pre-existing, loud (not silent
wrong code), workaround is parens. **Filed rather than fixed because the repair restructures
`PARSE_TERM`'s head — the same function that produced the `_cfo` class four times** — and needs its
own full differential + gate cycle. Read the `_cfo` CHANGELOG entries before touching it.

## v6.5.0 opens with

1. **`public`/`private` visibility** — design **settled** (user 2026-07-22). Read
   `proposals/2026-07-02-function-visibility-pub-private.md`, **not** roadmap prose: a top-level
   `private` flips that FILE to private-by-default (fns *and* vars), per-item `public` re-exposes, no
   declaration = today's behaviour. `_`-prefix is explicitly LATER. Remaining work is the per-fn
   **file-id substrate**, not design.
2. **Perf/IR substrate** — the `CYRIUS_IR=3` failures are bounded, fixable bugs (both still reproduce:
   `alloc_str_extras` and `alloc_collections` exit 139 under IR=3, 0 by default). SIMD
   register-residency is gated on this.
3. **Stackless coroutines** — ▲ PINNED v6.5.x; `roadmap-future.md` is authoritative. Its issue is
   deliberately left OPEN as the acceptance record — do not "clean it up".
4. macOS-arm64 threading also homes here.

**Nothing codegen ever parks to 7.x.** 7.x is the language book + legal-for-public-release, only that.
The closeout found and fixed a violation (DWARF + incremental compilation were at "v7-PARKED").

## Standing traps (the expensive ones)

- **cybs cannot lex `>>>`** — self-hosts fine on `build/cycc`, then seed-derive fails with a bare
  `syntax error`. The cleanest proof the cycc fixpoint does NOT cover the seed chain. cybs also
  mis-compiles fns with too many global/literal references (`_grow_g1..g7`, `TOKNAME_BUILTIN`,
  `PP_FNAME_TOO_LONG` are all split for this reason).
- **The heap map is machine-read.** Prose on a map line is parsed as the size. Keep it on
  continuation lines.
- **`var x[N]` local = N BYTES; a bare top-level `var x[N]` = N×8.** This is what made CVE-34 a
  2048-byte buffer everyone read as 256.
- **Cyrius precedence is NOT C's** — `&`/`|`/`^` share the `+`/`-` tier. `1 | 2 + 1` == 4. `>>` is
  LOGICAL, `>>>` is ARITHMETIC. Verify by running the compiler.
- **A raw agnos syscall number off-agnos is the whole hazard.** #94 is `lchown` on x86_64 (arg1 = a
  path pointer) and **`exit_group` on aarch64 — it terminates the process.** The file-level `#ifdef
  CYRIUS_TARGET_AGNOS` gate is the barrier; off-agnos these fns must not exist.
- **`cyrius lib sync` is refused in this repo** — it would revert every fold. To refresh a folded dep:
  `cp <upstream>/dist/<name>.cyr lib/<name>.cyr`, then refresh the install snapshot immediately.
- **`cyrius distlib` regenerates only the main bundle** — run it per profile and grep each for the fix.

## Process

- The user handles **all** git. Never commit, push, or tag. Never use `gh` — `curl` the API.
- `release-gate.sh` GREEN before every `.NN`. `--quick` is steps 1–3, explicitly not release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** (fixed /tmp paths clobber).
- **An audit's output is FIXES, not a backlog** (`CLAUDE.md` "Execution integrity"). File only when
  the fix genuinely cannot pack into the patch — and NAME the reason.
