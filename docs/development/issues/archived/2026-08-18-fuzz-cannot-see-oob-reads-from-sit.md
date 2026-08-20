# `cyrius fuzz` cannot see an out-of-bounds READ — every overread in every consumer is invisible to it

**Status:** ✅ **RESOLVED** — shipped in **v6.5.29** as `cyrius fuzz --poison`. See `CHANGELOG.md` [6.5.29].

> Delivered exactly what the filing asked for and no more: redzones around `fl_alloc`
> allocations poisoned with a known pattern (0xA5), a check that COUNTS violations at free
> (`fl_poison_violations()`), and quarantine-on-free so use-after-free reads the pattern
> instead of the block's old contents. No shadow memory, per the filing's own "full ASAN-grade
> shadow memory is not required".
>
> ⛔ `.28` had shipped the alloc-side fill and deferred the rest, stating a free-side poison
> "needs the block's original size, and the size-class path stores only its class". That was
> wrong about the more valuable half: the class yields the block's CAPACITY, and filling the
> whole capacity on free is strictly SAFER than filling the requested size. The redzone does
> need the size, and the class table has zero slack, so poison mode bumps the class and stores
> the size in the last 8 bytes of capacity — no header change, no heap-layout change.
>
> Wired as a COMPILE-TIME predefine on all SEVEN forks (`lib/freelist.cyr` depends on mmap +
> atomic only and must not read the environment), and `tests/tcyr/crossos/poison_redzone.tcyr`
> RAN on ecb, ach, cass and pi — verified off-host, not merely compiled there.
disclosure that its fuzz suite had been running past for three minor versions.

**Severity:** **Medium–High as a tooling gap.** No cyrius defect; the runtime does exactly
what it says. But it means the *class* of bug fuzzing is best at — memory-safety on
attacker-controlled input — is only half covered for every consumer in the ecosystem.

## The incident

sit's `.git/` packfile reader had an out-of-bounds read in its delta interpreter: the literal
opcode bounds-checked its **destination** but never its **source**, so a crafted delta copied
**127 bytes of adjacent heap** into the reconstructed object. Because the attacker also picks
the declared result size, the function returned **success** and the bytes were printed to the
user by an ordinary read-only command. The output contained a **live heap pointer** — an
ASLR-defeating disclosure.

The relevant part for this repo:

- The module had **10 million rounds/run** of fuzzing over adjacent decoders and **passed**.
- The overread was found by **reading the code**, not by any harness.
- It is now pinned only by a hand-built deterministic corpus that asserts on the leak
  directly.

The reason fuzzing could not see it is simply that **the read landed in mapped memory**. There
was no fault to catch. `alloc` is a bump allocator with no redzones, so a 127-byte overread
off a small allocation is, to the process, a perfectly ordinary load.

## Why this generalizes

This is not specific to sit or to that parser. Under the current allocator, for **any**
consumer:

- an out-of-bounds **write** is caught only if it reaches an unmapped page;
- an out-of-bounds **read** is essentially **never** caught, because a read has no side effect
  the harness can observe.

So `cyrius fuzz` reports "no crashes" and that is true and says nothing about overreads. Every
`fuzz: no crashes` line in every consumer's CI carries that asterisk today.

## Wanted

A build/run mode — `CYRIUS_ASAN=1`, `cyrius fuzz --poison`, whatever shape fits — that makes
overreads *observable*:

- **Redzones** around `alloc` / `fl_alloc` allocations, poisoned with a known pattern;
- a check that faults (or reports) when a load or store touches a redzone;
- ideally quarantine-on-free for `fl_free` so use-after-free is caught in the same mode.

Full ASAN-grade shadow memory is not required. Even **redzone poisoning plus a fill pattern**
would have caught the sit defect: the leaked bytes would have been the pattern rather than
heap contents, and a harness asserting "output contains no poison bytes" turns an invisible
overread into a loud one.

Slow is fine — this is a fuzz/test mode, not a release mode.

## What the consumer did instead

Wrote a deterministic corpus (`tests/integration/hostile_pack.py`, 11 crafted `.idx`/`.pack`
fixtures) that asserts on the leak's *symptom*: a delta case that exits 0 is a failure. That
works and is checked in — but it only covers the overreads someone already thought to look
for, which is precisely the gap fuzzing is supposed to fill.

## Reference

sit's audit write-up, if the incident detail is useful:
`sit/docs/audit/2026-08-17-audit.md` (findings 2 and 9 — the second is the meta-finding that
the one module with no fuzz target held every serious defect).
