# Handoff — v6.4.81 shipped; **v6.4.82 is the closeout**

> **Refreshed 2026-07-27.** Read this first, then `CLAUDE.md`, then [`state.md`](state.md).
> **Refresh or delete this file when the closeout ships.** A stale handoff is worse than none.

---

## Where things stand

| | |
|---|---|
| Version | **6.4.81** (81 releases in the 6.4.x minor) |
| cycc x86_64 | **1,108,328 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **150 passed / 0 failed** (was 149; `_doc_stamp_currency_gate` is new) |
| Corpus | 251 `.tcyr` · 99 `lib/*.cyr` · 97 programs |
| Open issues | **15** (was 11; four filed by the closeout audit) · 3 proposals · 271 archived |

## ⚠ v6.4.81 became a BUG-FIX release. The closeout is v6.4.82.

Same shape as .80, and for the same reason: **running the closeout audit found live bugs.** The user's
call (2026-07-27) was to ship the fixes as .81 and move the closeout *in full* to .82.

What .81 shipped — full detail in the CHANGELOG:

1. **A FOURTH `_cfo` rewind occurrence.** `EMIT_OP_DISPATCH` (struct operator overloading) re-arms the
   const-fold via `PARSE_TERM` and ends with `SESTYPE(S,0)`, so the following `+`/`-` folds and
   `SCP(S,_cfp)` rewinds the code pointer **over the operator call**: `p * 3 + 1` compiled to **4**.
   `add`/`sub` cleared `_cfo`, `mul`/`div` never did — 2-of-4 in four identical lines.
2. **CVE-32/33/34** — three unbounded copies reachable from untrusted source. `include "<31490 chars>"`
   SIGSEGV'd cycc.
3. **The heap map documented the scratch that smashed at an address no code has ever written**
   (`0x190500 [256]` vs the live, unbounded `0x190400`), so `heapmap.sh` validated a fiction.
4. **`_doc_stamp_currency_gate`** (check.sh 149 → 150), born RED on eight releases of live stamp drift.

## What v6.4.82 must do — the closeout, with its inputs already gathered

Run the full procedure: [`cycle-discipline.md`](cycle-discipline.md) "Closeout checklist + ledger"
(copy the template into a **new ledger entry and record the results** — the ledger is what makes rot
visible across cycles), with the durable rationale in `CLAUDE.md` "Closeout Pass" items 1–12.
Mechanical gates fail-fast → judgment passes → compliance → docs last.

**A 13-agent closeout audit already ran on 2026-07-27** covering items 4–12. Its confirmed,
adversarially-verified findings are the closeout's work list. Everything below was checked against
**live code**, not against the docs' own claims.

### Already filed as issues (do not re-derive)

- `2026-07-27-pe-gates-validate-a-5-11-69-binary.md` — **the Windows PE gates have been exercising a
  cycc 5.11.69 binary since 2026-05-19**, i.e. all of v6.0.x–v6.4.81. Existence-only rebuild trigger,
  artifact not in `cross_bins`. Green checkmark, wrong compiler — the macOS-rot shape.
- `2026-07-27-heapmap-blind-to-20mb-and-ts-arena-overlap.md` — `heapmap.sh`'s size regex misses
  `[16 MB]`-style entries, so it cannot see `ir_nodes` (16 MB), `ir_cp` (4 MB) and four scratch
  regions; it also mis-sizes `fn_param_struct_mask` as **5 bytes**. Plus: the TS arena at `0x298B000`
  overlaps `tok_types` entirely + 1.6 MB of `tok_values`, safe today only by an undocumented temporal
  invariant. Corrected table = **108 regions, 0 overlaps**.
- `2026-07-27-cross-compile-drops-value-form-simd.md` — `main.cyr`'s PE/Mach-O **cross** branches never
  got `CYRIUS_HAS_VAL_SIMD_PARAMS`, so value-form SIMD has been native-only all minor. 11 docs/tests
  call this "non-PE by design", including four `vr01_*` headers that wrongly claim a cass skip.
- `2026-07-27-cbt-fixed-tmp-paths-cve-35-36.md` — CVE-35/36, `cbt/`'s 20 fixed `/tmp` literals.
- `2026-07-26-no-lchown-wrapper-…` — **re-scoped upward** with an appended section: the whole chown
  family is missing from **all six** peers; two live hazards for the fix (aarch64 `54` is remapped to
  `setsockopt` by ESYSXLAT, agnos 92/93 are the GPU band); Darwin numbers must be read off ecb/ach.
  Also folds in `sys_chdir`, which `lib/regression.cyr:658` calls and **nothing defines**.

### Doc work the audit specified but did NOT apply (this is the bulk of .82)

Every item below has exact old → new text in the audit result; re-derive only if you distrust it.

- **roadmap.md "Shipped so far" stops at .72** — .73–.81 missing. Drafted bullets exist.
- **Stale stamps in 8 live docs** (cycc size, check.sh count, self_compile). `_doc_stamp_currency_gate`
  now covers three of those anchors; the rest are still manual.
- **Stackless coroutines contradicted in 4 live places** — `roadmap-future.md:116` (▲ PINNED v6.5.x) is
  authoritative; roadmap.md still files it under "Potential backlog" and calls stiva a "would-be
  consumer"; state.md's *Next up* row still says "no consumer".
- **roadmap.md's v6.5.x table omits the `pub`/`private` opener** and two of its own pinned items.
- **PLACEMENT-RULE VIOLATION** — roadmap.md parks DWARF debug-info and incremental compilation at
  "v7-PARKED", contradicting its own rule 200 lines above. Nothing codegen goes to 7.x.
- **Open-issue count says 9 in three docs**; live is now **15**.
- **state.md's Version row** was rewritten for .81, but the rest of the table still narrates .72.
- **`doc-health.md` lists SIX "open" issues that are all archived**, and two "active" proposals that
  are archived.
- **CLAUDE.md:164 says the last security audit was "v5.0.1"** — it is
  `docs/audit/2026-06-10-deep-dive-review.md` at cycc 6.1.31. A new audit doc
  (`docs/audit/2026-07-27-security-audit.md`, CVE-32…CVE-38) is warranted; CVE-32/33/34 shipped in
  .81, CVE-35/36 are filed, **CVE-37/38 were REFUTED on verification and must not be re-filed.**
- **vidya** (`~/Repos/vidya/content/cyrius/`, working tree CLEAN as of `2cf0d97`): `gotchas.cyml` stops
  at v6.4.52 — **28 releases with no entry**. `features.cyml:2680` states "f32 is type-only, no f32
  arithmetic", **actively wrong since v6.4.56**. Identifier pool documented as 256 KB in 5 places
  (512 KB since .76). ⚠ **Two premise corrections**: vidya's tree is clean (the "uncommitted sweep"
  warning in the previous handoff is stale), and **the "8192 fn table is wrong" premise is mostly
  FALSE** — `_fnt_cap = 8192` is still the live *init* cap that grows ×2 to 32768, so a blanket
  8192→32768 sweep would *introduce* errors. Exactly one 8192 is wrong (`gotchas.cyml:4334`).
- **Heap-map count**: live is **94**; it was 100 from 6.4.0 through 6.4.74 and dropped at **.75** (the
  six freed fn-indexed side tables). ADR-003 / doc-health / vidya `core.cyml` say 100; vidya
  `ecosystem.cyml` says "135 entries / 56 live", which **matches no release in history**. Note the
  count becomes 108 once the `heapmap.sh` parser is fixed — settle that issue before stamping a number.

### Refactor / dead-code candidates (verified, but proposed ranges were wrong — re-check before cutting)

- `_fnt_is_async` is a **write-only** table; `GFAS` has exactly one occurrence repo-wide (its own
  definition), so SFAS lazily allocates 256 KB nothing reads.
- `_TS_LEX_JSX_WALK` + 2 helpers are unreferenced. **The verifier confirmed the dead-code claim but
  found the proposed delete range wrong** — it would have cut live code. Re-derive the range.

## v6.5.0 — what it opens with

1. **`pub`/`private` visibility** — design **settled** (user 2026-07-22). Read
   `proposals/2026-07-02-function-visibility-pub-private.md`, **not** the roadmap's superseded
   "hybrid / derive-from-`_`" prose. Remaining work is the per-fn **file-id substrate**.
2. **Perf-quality arc** — IR/regalloc substrate; the `CYRIUS_IR=3` failures are bounded, fixable bugs.
3. **Stackless coroutines** — ▲ PINNED v6.5.x (user 2026-07-26); stiva is the live filed consumer. Its
   issue stays **open** as the acceptance record.
4. macOS-arm64 threading.

**Nothing codegen ever parks to 7.x** — 7.x is the language book + legal-for-public-release, only.

## Traps that cost real time — do not rediscover these

**Carried forward from the previous handoff (still true)**

- **cybs cannot lex `>>>`.** Self-hosts fine on `build/cycc`, then `seed-derive-cycc.sh` fails at step 3
  with a bare `syntax error`. The cleanest demonstration that the cycc fixpoint does **not** substitute
  for the seed gate.
- cybs also mis-compiles fns with too many global/call references — the reason `_var_grow` is a
  `_grow_g1..g7` chain, and why v6.4.81's `PP_FNAME_TOO_LONG` is a separate fn rather than three inline
  error blocks.
- **Cyrius precedence is NOT C's.** `&`, `|`, `^` share the `+`/`-` tier: `1 | 2 + 1` == **4**.
  `>>` is LOGICAL, `>>>` is ARITHMETIC. Verify by running the compiler.
- **`#` starts a COMMENT.** The directive is bare `include "..."`. A `#include` line is inert — this
  cost a wrong "not reproducible" conclusion on CVE-32 before the repro was corrected.
- String-literal→`Str` coercion fires **only** for a param annotated `: Str`.
- Lexer tokens **79** and **111** are double-assigned; diagnostics must name both.
- **`cyrius lib sync` is refused in this repo**; `cyrius distlib` regenerates only the main bundle.
- **Fix the SOURCE repo, not the fold.**

**New from the v6.4.81 work**

- **A test whose helper aliases the bug's output passes while broken.** The first `_cfo` repro gave
  `OpV_mul` a body of `a * b` — which is exactly what the erroneous fold produces, so it went green.
  Helpers must return values the broken path cannot produce.
- **Struct operator overloading is triggered by a `: StructName`-annotated variable**
  (`var a: Num = 20;`), not by a struct literal in expression position. `V{5} * 3` is a parse error.
- **The heap map is a machine-read format.** A correction that puts an old `0x… [N]` into prose *on the
  map line* is re-parsed as the size — the fix silently reverted itself once before this was caught.
  Prose goes on continuation lines.
- **Grep the shape across every tier that re-enters the fold.** `.74` swept `PARSE_TERM`, `.80` swept
  `PEXPR` and declared the shape gone; `.81` found it in `EMIT_OP_DISPATCH`. The durable grep is for
  *calls that can re-arm `_cfo`*, not for operator names.
- **Do not trust a subagent's repro verbatim.** Of eight P1/P2 security claims, two (CVE-37/38) were
  **refuted** on adversarial verification, and several confirmed ones had wrong mechanisms attached to
  a real defect. Re-run the repro yourself before editing a self-hosting compiler.

## Process notes

- The user handles **all** git operations — never commit, push, or tag. Never use `gh`; use `curl`.
- `release-gate.sh` GREEN before every `.NN` tag; `--quick` (steps 1–3) is **not** release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** — fixed `/tmp` paths clobber under concurrency.
- `check.sh`'s grep summary masks tcyr segfaults — run a per-file exit-code loop before claiming green.
  (.81 did: 251/251 genuinely exit 0.)
