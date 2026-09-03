# Security audit — 2026-09-03 (cycc 6.5.45)

**Scope:** the untrusted-source-input surface. Previous full audit:
`docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36) at cycc 6.4.82.
**Next free identifier after this document: CVE-42.** (CVE-37 and CVE-38 in the previous
document are **withdrawn** but still consume their ids.)

Run as part of the band K closeout, as nine parallel audit dimensions over the v6.5.x minor with
an adversarial verification pass over the highest-severity findings. Everything recorded here was
reproduced against a compiler built for the purpose; where a claim is inherited rather than
re-measured, it says so.

---

## CVE-39 — an include path's LENGTH silently changes which `#ifdef` branch compiles

| | |
|---|---|
| **Severity** | **High** — silent wrong-code generation, exit 0, no diagnostic |
| **Affected** | `src/frontend/lex_pp.cyr` (3 capture loops), through cycc 6.5.44 |
| **Fixed** | 6.5.45 |

**Vector.** The three include/`#ref` filename capture loops wrote into the scratch region at
`S+0x190400`, bounded at 4095 because the heap map declared that region `[4096]`. Two live
things sit inside that declared span:

| offset | bytes in | what |
|---|---|---|
| `S+0x190700` | 768 | `PP_EXPAND`'s output-write-cursor return slot (`lex_pp.cyr:2334` store / `:3166` load) |
| `S+0x190800` | 1024 | the `#ifdef` **feature-flag table** — name hashes, 16 slots (`:2368`, `:2379`) |

**Impact.** A path of ≥768 characters corrupts the preprocessor's own output cursor, so expanded
macro text lands at the wrong offset. At ≥1024 it overwrites the hashes of `CYRIUS_ARCH_X86`,
`CYRIUS_TARGET_MACOS` and their siblings — after which `#ifdef` selects the **wrong branches**
and the compiler emits a binary shaped for a different target.

**Measured**, against a compiler built with the pre-fix guards:

```
include path 1210 chars → probe returns 7, where 42 is correct.  compile rc=0, no diagnostic.
                          post-fix: "error: include/#ref filename exceeds 767 bytes", rc=1.
```

⚠ **A long path is not exotic.** Deep vendored dependency trees under a long `$HOME` reach four
figures, and the input is attacker-influenced wherever source is compiled on someone's behalf.

**Fix.** All three loops bounded at 767; the map corrected to `[768]` and both live neighbours
declared. ⚠ **The first cut of this fix used 1024** — reasoning from the flag table alone and
missing the cursor slot 256 bytes below it. That is why
`tests/gates/frontend/preprocessor_scratch_bounds.sh` **derives** the bound from live writes
rather than trusting the map or any comment.

---

## CVE-40 — an unbounded `#define` body copy walks out of the macro text pool

| | |
|---|---|
| **Severity** | **High** — silent memory corruption of live compiler state from ordinary source |
| **Affected** | `src/frontend/lex_pp.cyr:2704-2721`, through cycc 6.5.44 |
| **Fixed** | 6.5.45 |

**Vector.** The macro body copy ran to end-of-line with no check on the copied length **or** on
the accumulating write position `_pp_macro_text_pos`, writing into the pool at `S+0x193000`. Free
headroom there runs to `S+0x197000` — 16 KB shared across all 16 macros — so a single long body,
or enough ordinary ones in sequence, walks into live compiler state. The audit dimension that
found it measured a SIGSEGV from a 20500-character function-like macro body (that specific crash
is inherited from the audit, not re-measured here).

**Fix.** Bounded at 16384 with an honest hard error (`PP_MACRO_TEXT_FULL`). ⚠ The guard tests the
**accumulating position**, not this macro's length — bounding the length alone still overruns on
the sixteenth `#define`. Verified: a 20500-character body is refused with a diagnostic, and an
ordinary `#define` is unaffected.

---

## Not fixed here, and why

Two further findings of the same class in the same file are **filed rather than fixed**, and the
reason is named rather than implied: they need a heap/brk **layout** change (relocating the
`#derive` name scratch out from under `S+0x197020`), which makes them a two-step-bootstrap
change that this release cannot absorb alongside two other bounds fixes.

- **CVE-41 (reserved)** — three unbounded name captures in the `#derive` path
  (`lex_pp.cyr:998-1003`, `:1040`). Reserved here so the identifier is not re-used.

The remaining band K audit findings are correctness rather than security and are pinned to the
band's second phase; see `docs/development/roadmap.md`.

---

## Still holding from the previous audit

`CVE-32`/`33`/`34` fixes intact. The `cbt/` temp-file hardening (`CVE-35`/`36`) still holds —
`_cbt_tmpdir()` / `_cbt_tmpfile()` remain the only `/tmp` path producers.
