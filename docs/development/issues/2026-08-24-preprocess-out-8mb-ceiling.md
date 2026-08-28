# `preprocess_out` 8 MB ceiling is a hard build failure with no flag — and thoth is already at ~96 % of it

**Status:** 🟡 **OPEN** — reproduced on **cyrius 6.5.35**, 2026-08-24. Hard error, clear message, no
override. A consumer can only respond by shrinking its own source.
**Placement:** unpinned — 6.x-line backlog. Worth a look before the next large first-party consumer lands.
**Discovered:** 2026-08-24 while wiring thoth 0.41.0's OS-sandbox seam over kavach's vendored dist bundle.
**Severity:** Medium — hard failure, but a real consumer-side workaround exists (a lean `distlib` profile).
Flagged because the *headroom*, not this one bundle, is the story.
**Affects:** cycc 6.5.35 (and every earlier release carrying the same arena slot)

## Summary

The preprocessor expands all includes into a **fixed 8 MB arena slot**. Exceeding it is a hard error:

```
error: expanded source exceeds 8MB (8510519 bytes) in PP_IFDEF_PASS iter=1
```

The diagnostic is good — it names the pass, the byte count and the limit, which is more than most fixed
caps give you. The problem is that it is the **end of the conversation**: there is no environment
variable, no flag, and no manifest key that raises it. The slot is a hard-coded address range in the
compiler's own memory map, so a consumer that hits it has exactly one move — make its source smaller.

**The reason this is worth filing now, rather than when someone actually gets stuck:** the consumer that
hit it is not doing anything exotic. **thoth is already at roughly 96 % of the ceiling before adding
anything.** Derived by subtraction rather than measured directly (the compiler only reports the size when
it overflows), so treat the exact figure as approximate:

| | bytes | % of 8,388,608 |
|---|---|---|
| thoth 0.41.0 + `dist/kavach.cyr` (the failing build) | 8,510,519 | 101.5 % |
| `dist/kavach.cyr` alone | 440,454 | |
| **thoth 0.41.0 alone (derived)** | **≈ 8,070,065** | **≈ 96.2 %** |

thoth is a normal first-party consumer: it vendors ten dist bundles (avatara, bote-core, libro, t-ron,
sit-read, sankoch, vyakarana, darshana, anuenue, kashi, agnosai-guard) plus the ~100-module stdlib
snapshot. Nothing about it is unusual for this ecosystem — vendored single-file dist bundles are the
*recommended* consumption pattern. It has **~300 KB of headroom left**, which is less than one more
average bundle. The next feature that needs a spine capability will hit this wall, and so will the next
consumer that vendors a comparable set.

## Reproduction

Downstream repo: **thoth**, at the 0.41.0 working tree (commit `c69caf9` + uncommitted 0.41.0 work).
Any tree of comparable size reproduces it; the specific bundle is not special.

```sh
cd ~/Repos/thoth
cp ~/Repos/kavach/dist/kavach.cyr src/vendor/kv-probe.cyr
# add `include "src/vendor/kv-probe.cyr"` to src/main.cyr, before the other vendored bundles
cyrius build src/main.cyr /tmp/kvprobe
```

Actual:

```
compile src/main.cyr -> /tmp/kvprobe [x86_64] error: expanded source exceeds 8MB (8510519 bytes) in PP_IFDEF_PASS iter=1
FAIL
```

Expected: either a successful build, or a documented way to raise the limit.

Without the extra include the same tree builds clean on x86_64, `--aarch64` and `--agnos`.

## Root cause (known — this part is not speculation)

The buffer is a fixed slot in the hand-laid arena map:

```
# src/main.cyr:497
#   0x459D000 preprocess_out [8388608]   8 MB expanded source buffer.
#                                        Relocated here from 0x44A000 at v5.11.33
#                                        + cap raised 2 MB → 8 MB. See CHANGELOG [5.11.33].
```

It is bounded above by `0x5D9D000 local tables` and below by the fn tables, so it cannot simply grow in
place — the neighbours move with it. The two enforcement sites are:

```
src/frontend/lex_pp.cyr:3066
src/frontend/lex_pp.cyr:3429
```

I grepped `src/main.cyr` and `src/frontend/lex_pp.cyr` for a `getenv`/env override and found none, which
is consistent with the arena being laid out statically. If an override *does* exist somewhere I missed,
this issue collapses to a documentation request — please say so and close it.

Precedent that this is a recurring shape rather than a one-off: `lexid_entries` was in exactly the same
position and was relocated to the arena top (`0x7300000`) at **v6.4.21** when its 16384-entry cap became
the binding constraint, with the aarch64/macho/cx forks extending their arena to `0x7400000` to map it.
Whatever was learned doing that relocation probably applies here.

## Proposed fix

Speculation — I do not know the arena's constraints well enough to pick between these, and I am not
touching cyrius to find out. Ordered by what looks least invasive from outside:

1. **Relocate `preprocess_out` to the arena top and grow it**, the same move `lexid_entries` got at
   v6.4.21. The precedent exists and the forks already know how to extend to map a relocated region.
2. **Make the slot dynamic** — `mmap` the expansion buffer sized from the input rather than reserving a
   fixed band. Larger change; removes the class of problem rather than moving the number.
3. **An escape hatch** — `CYRIUS_PP_MAX` or a `[build]` manifest key. Cheapest, and it at least turns a
   wall into a decision, but it leaves the ceiling in place for anyone who does not know to look.

Not proposing a specific number: raising 8 MB to 16 MB buys thoth roughly one more year of bundles at the
current rate, which is a delay rather than a fix. Option 2 is the only one that stops this recurring.

## Consumer-side workaround (shipped, and it does not scale)

The pattern that works today is a **lean `distlib` profile**: the library publishes a `[lib.X]` subset and
the consumer vendors that instead of the full fold.

- **kavach 3.12.3** added `[lib.confine]` — 4,796 lines / 192,567 bytes against the full fold's 11,524
  lines / 440,454 bytes. Builds clean inside thoth.
- **agnosai 2.0.7** added `[lib.guard]` for the same reason (915 lines against a 37,595-line fold).
- Precedent: sit's `[lib.read]`, sankoch's `[lib.zlib]`.

This is genuinely good practice and I would recommend it regardless of the ceiling — a consumer should
take the surface it uses. But as a *response to a hard cap* it has two problems worth recording:

1. **It pushes the cost upstream, per consumer.** Every large first-party library ends up publishing a
   bespoke profile for each consumer's particular slice. That is N×M profiles across the AGNOS family, all
   needing their own closure verification. Both profiles above needed an upstream source move to close
   (`_agnosai_to_ascii_lower` out of `llm/retry.cyr`; `cstr_contains` + `str_to_lower_into` out of
   `scanning_code.cyr`) — small changes, but each one is a library restructuring itself around a compiler
   limit rather than around its own design.
2. **It runs out.** thoth's ~300 KB of headroom is the real number here. Trimming individual bundles buys
   a few features; it does not change the trajectory.

## What this cost, concretely

thoth 0.41.0 scheduled an OS-sandbox seam over kavach. The ceiling was the first blocker, and the lean
profile cleared it — that part worked. (The feature ultimately shipped-not-shipped for an unrelated
design reason on kavach's side, so this issue is not blocking thoth today.) The point is that the ceiling
was hit on the *first* attempt to add a spine capability to a normal consumer, and the next one starts
from 300 KB of room.
