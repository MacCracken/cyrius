# cycc's 1 MB stdin `input_buf` has been reached — sigil's dist bundle is 1,079,068 B

**Status:** 🔴 OPEN — filed, not fixed, because the fix is a **heap LAYOUT change** and
therefore needs a two-step bootstrap. That is one of the named reasons in CLAUDE.md's
*an audit's output is fixes* rule for filing rather than packing; it is not a
"different subsystem" dodge. Everything else found in this pass shipped in 6.5.14.
**Re-measured 2026-08-11 (v6.5.19):** the bundle is now **1,079,160 B** — it has grown another
**92 B** since filing, so it is **30,584 B over the cap** and still `rc=1`,
`error: input exceeds 1MB buffer (raise input_buf in src/main.cyr)`. The headroom is not
merely gone, it is receding.
**Placement:** **v6.5.21 — the heap-layout release**, packed with the retired `output_buf`
band reclamation (roadmap Slot 12's carried-in item). ⭐ **Both are heap-LAYOUT changes and
each carries its own two-step bootstrap; doing them in ONE two-step bootstrap is materially
cheaper than two.** Pinning them to the same release is the whole reason this now has a slot
instead of drifting to closeout. See roadmap.md's slot sequence.
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
