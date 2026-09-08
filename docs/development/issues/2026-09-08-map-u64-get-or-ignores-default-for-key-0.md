# 2026-09-08 — `map_u64_get_or(m, 0, default)` silently returns 0, not `default`

**Filed by:** chakshu (the AGNOS system monitor), during v0.10.2.
**Affects:** `lib/hashmap.cyr`. Behaviour is *documented*; the sharp edge is that the failure is
silent and returns a plausible number.
**Checked against:** cyrius **6.6.1**.

## What happens

`MAP_U64_EMPTY = 0` (`lib/hashmap.cyr:425`), and the header at `:392` says so plainly:
`key == MAP_U64_EMPTY (0) → empty slot`. So key 0 is not storable. That part is fair and documented.

The sharp edge is the *read* path:

```
fn map_u64_get_or(m, key, default_val): i64 {
    var ep = _map_u64_find(m, key);
    if (ep == 0) { return default_val; }
    if (load64(ep) != key) { return default_val; }
    return load64(ep + 8);
}
```

For `key == 0`, `_map_u64_find` returns an **empty** slot, whose stored key is `0`. The guard
`load64(ep) != key` is then `0 != 0` — **false** — so the function falls through and returns
`load64(ep + 8)`: the empty slot's value, which is `0`.

**A caller that passes a sentinel default does not get it.** The whole point of `get_or`'s third
argument is to distinguish absent from present, and for exactly one key it silently does not.

## Why this is worth a note rather than a shrug

It cost chakshu a wrong number in a shipped-shaped build, and the number was plausible.

chakshu keys a per-process CPU-tick baseline by pid and uses `-1` as "no baseline yet, render n/a".
Linux has no pid 0, so this was invisible for several releases. **AGNOS has a pid 0** (`kmain`). The
lookup returned `0` instead of `-1`, so the baseline read as zero, the delta became the process's
entire cumulative-since-boot tick count, and the monitor rendered **59% CPU for an idle kernel
thread on an idle machine**.

Nothing failed. No error, no negative, no obviously-bogus magnitude — a number in range, in a
column where numbers belong.

It surfaced only because a second statistic derived from the same counter disagreed: the aggregate
summed ticks across all slots and showed a delta of exactly 0 for the window in which pid 0 claimed
59%. Without that cross-check it would have shipped.

## Suggestions, in order of preference

1. **Make the read path honest** — one line:

   ```
   if (key == MAP_U64_EMPTY) { return default_val; }
   ```

   at the top of `map_u64_get_or` (and the same in `map_u64_has`, which today returns `0` for key 0
   by the same path and is therefore accidentally correct). Key 0 is unstorable, so "absent" is the
   only truthful answer, and `default_val` is what the caller asked for in that case.

2. **Or refuse the write** — have `map_u64_set(m, 0, v)` return an error rather than silently doing
   nothing, so the mistake surfaces at insert time instead of three functions later.

3. **At minimum, warn in the doc comment.** `:392` documents the sentinel, but a reader looking at
   `get_or`'s signature has no reason to go read the collision-strategy header. A line on the
   function itself — *"⚠ key 0 is the empty sentinel: `get_or` returns 0, NOT `default_val`"* —
   would have been enough to stop this.

⚠ Option 1 is a behaviour change for anyone currently relying on getting `0` back for key 0, but it
is hard to imagine that being deliberate — the caller would have had to pass a default and want it
ignored.

## Workaround, for anyone who finds this before it changes

Bias the key: store `k + 1`, look up `k + 1`. chakshu now does this
(`src/proc_agnos.cyr`, `AGNOS_PID_KEY_BIAS`) and it costs nothing.
