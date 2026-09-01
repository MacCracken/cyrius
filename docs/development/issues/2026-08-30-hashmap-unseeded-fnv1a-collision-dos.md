# `lib/hashmap.cyr`'s FNV-1a is unseeded, so one precomputed collision set degrades every consumer's `map_set` to O(n²)

**Status:** 🟠 **OPEN** — no consumer can fix this; `lib/` is vendored, and at least one
first-party project (samay) has a hard rule against modifying it. Requested as a stdlib change.
**Placement:** `lib/hashmap.cyr` — `hash_str` (`:69`) and `hash_str_v` (`:84`). Self-contained,
but see [Compatibility](#compatibility--this-is-the-part-that-needs-a-decision): seeding changes
per-process iteration order, which is the actual decision to make.
**Discovered:** 2026-07-21, during samay's M5 security audit
([`samay/docs/audit/2026-07-21-audit.md`](https://github.com/MacCracken/samay) finding **F4**).
**Filed:** 2026-08-30. The audit's own Recommendation 5 was "file an upstream Cyrius stdlib issue
to seed `hash_str_v`/`hash_str`" — that was never done, and samay's roadmap carried it as
"upstream, not ours" for six weeks while nobody upstream knew. Filing it now closes that gap.
**Severity:** **Medium** for any consumer that inserts attacker- or user-influenced strings as map
keys. Not a crash, not memory corruption — algorithmic-complexity denial of service.
**Affects:** cycc **6.5.36** and every earlier release. Both hash functions have carried fixed
constants since they were written.

## Summary

`hash_str` and `hash_str_v` are textbook FNV-1a with the standard offset basis
(`0xCBF29CE484222325`) and prime (`0x100000001B3`), and **no per-process seed**:

```
fn hash_str_v(s): i64 {
    if (s == 0) { return 0; }
    var data = str_data(s);
    var len = str_len(s);
    var h = 0xCBF29CE484222325;      # <-- fixed, identical in every process
    var hi = 0;
    while (hi < len) {
        h = h ^ load8(data + hi);
        h = h * 0x100000001B3;
        hi = hi + 1;
    }
    return h;
}
```

Because the function is deterministic across every process on every machine, a set of keys that all
land in the same bucket can be **computed once, offline, and reused against every consumer forever**.
The map is open-addressed with linear probing, so bulk-inserting such a set turns `map_set` from
amortised O(1) into O(n²).

This is the standard hash-flooding shape (CVE-2011-4815 and its long tail; it is why Python, Ruby,
Rust and Go all seed or use SipHash). It is not a novel finding — it is the absence of a mitigation
those runtimes adopted more than a decade ago.

## Measured

From samay's audit, using running probes with the timer validated against a 50M busy-loop (≈450 ms):

| workload | colliding keys | distinct keys | ratio |
|---|---|---|---|
| raw `map_set`, N=8,000 | 493 ms | 2.5 ms | **~197×** |
| `task_scheduler_from_json_str`, N=8,000 (182 KB doc) | 1.00 s | 43 ms | **~23×** |
| same, N=16,000 (370 KB doc) | 2.44 s | 79 ms | **~31×** |
| same, dense collisions at final capacity | 1.42 s | 37 ms | **~38×** |

Parse cost is identical between the two columns — only the *contents* of the key strings differ. A
~185 KB document costs ≈1.4 s of single-core CPU; a multi-MB crafted document scales to tens of
seconds.

## Why consumers cannot fix it

`hash_str` / `hash_str_v` are selected internally by `map_new_str` based on key type; a consumer
cannot inject its own hash without reimplementing the map. The only consumer-side mitigation is to
**bound N** — samay caps restored collections at 100,000 items (`SAMAY_JSON_MAX_ITEMS`), which turns
an unbounded blowup into a bounded one but leaves the within-cap quadratic cost intact. Every other
consumer with untrusted map keys has to invent the same cap independently, and most will not know to.

## Fix shape

Two options, in preference order:

**(a) Seed the offset basis per process.** One `getrandom`-derived value read once at first use and
XOR-ed into (or substituted for) the initial `h`. Smallest possible change, kills the
precomputed-set property outright, and leaves the hash's distribution characteristics alone. An
attacker can no longer compute collisions offline because they no longer know the basis.

**(b) Move to a keyed hash (SipHash-1-3 or similar).** Stronger — it resists an attacker who can
*observe* collisions at runtime and adaptively probe, which (a) does not fully prevent. Costs more
per byte, which matters because this is on the hot path of every string-keyed map in the ecosystem.

(a) is almost certainly the right trade for a systems stdlib. It is worth stating the residual
explicitly in the module header either way: seeding defeats offline precomputation, not adaptive
online probing.

## Compatibility — this is the part that needs a decision

**Seeding makes `map_values` iteration order differ between runs of the same program.** It is
already documented as bucket order and already unstable across insertion orders — but today it is at
least *reproducible* for a fixed insertion sequence, and after seeding it would not be.

That is a real migration consideration, and it cuts both ways:

- Any consumer that has (incorrectly) come to depend on reproducible `map_values` order will
  change behaviour. **Surfacing those is a benefit** — they are latent bugs today, and they will
  otherwise surface at the worst possible moment.
- Consumers that sort explicitly are unaffected. samay is one: its determinism guarantee
  (ADR-0004) breaks every tie on a unique key precisely because `map_values` order is not
  trustworthy, so seeding costs it nothing. That ADR is a worked example of the pattern other
  consumers should follow.

Worth considering: land the seeding behind a build define for one release
(`-D CYRIUS_HASH_SEED=0` to opt out) so consumers have a window to find their order dependencies,
then flip the default. A `cyrius lint` rule that flags `map_values` results reaching output without
an intervening sort would find most of them mechanically.

## Reproduction

Insert N keys chosen so `hash_str_v(k) & (cap-1)` is constant, into a `map_new_str`, and time it
against N random keys of the same length at the same capacity. The colliding set is straightforward
to generate by brute-forcing short suffixes against the published constants — which is exactly the
point of the finding.
