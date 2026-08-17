# cycc's 1 MB stdin `input_buf` has been reached — sigil's dist bundle is 1,079,068 B

> ### ✅ RESOLVED — SHIPPED in v6.5.22, exactly as this file's Placement line planned
>
> `input_buf` is **16 MB** (`_SRC_CAP = 16777216`, `src/common/util.cyr`; heap map
> `0x4D9D000 input_buf [16777216]`), raised into the band reclaimed from `output_buf` so
> both heap-LAYOUT changes shared ONE two-step bootstrap — the packing this file asked for.
>
> **Re-verified empirically at v6.5.25, not from the changelog:** cycc ingests sigil's
> current bundle (**1,084,265 B**, another 5 KB of growth since the last re-measure) with
> **no cap error at all**. The former `error: input exceeds 1MB buffer` is absent. (The
> bundle still reports undefined functions under a raw `cycc < file` pipe, but that is the
> documented consequence of bypassing `cyrius build` — no stdlib includes are prepended —
> not this defect. The 16× headroom is what was filed and it is delivered.)
>
> ⚠ **This file's status line said `🔴 OPEN — filed, not fixed` for three releases after it
> shipped.** It was correct to file rather than pack (a heap layout change is one of
> CLAUDE.md's named reasons), but nothing moved the status when the planned release landed —
> which is precisely the rot the closeout rule targets: *verify resolved-status against LIVE
> code, never the file's own claim.* Caught here by reading `_SRC_CAP`, not the banner.

**Status:** ✅ RESOLVED in v6.5.22 — archive at slot close.
**Discovered:** 2026-08-08, v6.5.14, while fixing `distlib`'s bundle self-check.
**Severity:** Medium — no consumer is broken TODAY (see *Why nothing is on fire*), but
the headroom is gone and the failure mode when it lands is a hard error at the entry.

## The measurement

```
$ cat ~/Repos/sigil/dist/sigil.cyr | build/cycc > /tmp/out
error: input exceeds 1MB buffer (raise input_buf in src/main.cyr)
$ wc -c ~/Repos/sigil/dist/sigil.cyr
1079068
```

`input_buf` is `[1048576]` at heap `0x00000` (`src/main.cyr:24`). sigil's main dist
bundle passed it — **by 30,492 bytes**, i.e. it crossed recently and quietly.

## Why nothing is on fire (verified, not assumed)

`include` is resolved by cycc's preprocessor **from disk**, not through `input_buf`. Only
the ENTRY file goes down stdin. So the normal consumer shape

```
include "lib/sigil.cyr"      # 1,079,068 B — read from disk, no cap
fn main(): i64 { ... }
```

compiles fine, and `cyrius deps` consumers are unaffected. Confirmed by building a
two-line entry that includes the full bundle: it got past the cap and failed only on the
expected undefined stdlib fns.

What DOES break is anything that feeds a large file to cycc as the entry:

- `cat big.cyr | cycc` — the compiler-internal self-host shape.
- `cyrius build dist/sigil.cyr out` — plausible for a consumer sanity-checking a bundle.
- `cyrius distlib`'s own bundle self-check **used to** do this. 6.5.14 changed it to
  compile through a generated `include` entry instead — partly for correctness, partly
  because piping the bundle would have failed the largest bundle in the ecosystem for a
  reason no consumer ever meets. That workaround is now load-bearing; see
  `tests/gates/toolchain/distlib_bundle_selfcheck.sh` axis 5, which asserts a >1 MB
  bundle is still genuinely checked.

## Why it is a layout change

`tok_names` is **nested inside** `input_buf`'s span — `0x00000 input_buf [1048576]` with
`0x60000 tok_names [524288]` living in the same megabyte (LEX rebuilds tok_names over the
consumed input). The region ends at `0x100000`, and v6.4.76 already grew the identifier
pool into the `0xE0000-0x100000` gap, noting the pool END must stay `<= 0x100000` because
**above it the compiler HANGS**. So raising `input_buf` means relocating `tok_names` and
re-deriving the surrounding map — a heap/brk layout change, hence the two-step bootstrap
(`cycc` compiles `cc5b`, `cycc == cc5b`) rather than a normal patch.

## Acceptance criteria

1. A >1 MB source compiles from stdin: `cat <1.5 MB file> | cycc` succeeds.
2. The new cap is stated in `src/main.cyr`'s heap map AND in the error text.
3. `tok_names` / identifier-pool ceilings re-verified — the pool end must not cross the
   physical ceiling that hangs the compiler (v6.4.76's note).
4. Two-step bootstrap verified: `cycc` builds `cc5b`, `cc5b == cycc` byte-identical.
5. Seed-derive green (`seed -> cybs -> cycc`) — cybs is more limited than `build/cycc` and
   fails SILENTLY on things it compiles fine.
6. A gate that FAILS at the old cap, mutation-proven — not merely a bigger fixture that
   happens to pass. ⚠ When writing it, note that `distlib` enforces its own **1024 KB
   per-module read cap** (fails loudly, exit 1), so a single oversized module never
   reaches the compiler; the >1 MB case has to be built from several modules.

## Do not

Do not "fix" this by having `distlib` or the CLI silently chunk the input. The cap is a
real ceiling on a real buffer; hiding it re-creates the class of defect 6.5.14 spent its
release removing (a check that reports success for work it did not do).
