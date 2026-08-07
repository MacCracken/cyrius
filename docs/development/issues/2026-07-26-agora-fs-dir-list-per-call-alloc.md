# `fs.cyr` `dir_list` allocates its whole working set per call — the last unbounded path in a long-running consumer

**Status:** 🟡 **OPEN** — nothing has shipped for it. **Re-verified against live code on cycc
6.5.10, 2026-08-07: every line number below is still exact.** `lib/fs.cyr` still allocates per call
in both branches (`:110` / `:150` `vec_new()`, `:114` / `:153` `alloc(4096)`, `:158` `alloc(8)`),
the per-entry `str_from_buf` push is unchanged (`:138`), and `grep -rn dir_list_into lib/ src/`
returns **nothing** — no caller-owned-buffer variant exists. `dir_list_full` (`:199`), `dir_walk`
(`:248`), `find_files` (`:280`) and the `_with_prunes` variants (`:307` / `:342`) still share the
shape; `dir_list_full` and `dir_walk` carry their own `alloc(4096)` / `alloc(8)` at `:221` and
`:236`–`:237`.
⚠ Neither v6.5.9's growable arena / exhaustion policy nor v6.5.10's `alloc_via` call-plumbing work
touches this: both are about the *allocator*, and `dir_list` does not thread one — it calls bare
`alloc()` / `vec_new()`. Do not read the 6.5.9/.10 allocator entries as narrowing this.
**Placement:** **v6.5.x — W1 reactive window, `.11`–`.16`.** `roadmap.md`'s W1 row (verified live
2026-08-07) lists this file under "⏳ still owed", alongside
`proposals/2026-06-25-source-level-version-constant`; 7 of the window's 13 slots are spent and 6
remain. It is the direct follow-on to the `sock_accept` per-poll leak that shipped in v6.4.61. The
cheap half (a file-scope `getdents` scratch, mirroring .61's lazy `Err(EAGAIN)` singleton) can fold
into an adjacent release on its own. Never 7.x.

**Discovered:** 2026-07-26 while closing out agora's 1.6.x memory work (the 2026-07-26 P(-1) audit)
**Severity:** Medium — no hard failure, but it is unbounded growth in a shipping server with **no
consumer-side workaround**, and it is now the *only* remaining one there
**Affects:** cyrius 6.4.78 (`lib/fs.cyr:109` agnos / `:149` Linux+macOS); every earlier version with
the same shape. `dir_list_full`, `dir_walk`, `find_files` and the `_with_prunes` variants share it.

## Summary

`dir_list` allocates its entire working set from the no-free bump allocator on **every call**: a
4096-byte `getdents` buffer, an 8-byte `basep` out-param, a `vec`, and one `Str` per surviving
directory entry. Nothing is reclaimed, because nothing can be — `alloc()` has no free and the
function owns no lifetime the caller can express.

For a one-shot CLI that is correct and cheap. For a **long-running server that lists a directory per
request**, it is a leak proportional to (requests × directory size), and the consumer cannot fix it
from the outside: the allocation is inside the stdlib, the returned `vec` of `Str` is the documented
return value, and there is no variant that writes into caller memory.

This is the same shape as the `sock_accept` per-poll leak filed by mishran and fixed in **6.4.61** —
a stdlib function that allocates per call in a loop the consumer runs forever. That one named agora
among the affected daemons. This is the follow-on: with agora's own allocations now reclaimed,
`dir_list` is what is left.

## Consumer context — why this is the last one standing

agora (the telnet BBS) spent five cuts making its memory bounded under `AGORA_SERVE=poll`, where one
process serves all 64 sessions for the life of the server:

- **1.6.2** — a per-command scratch arena (agora ADR 0021), reset once per dispatched line.
- **1.6.3** — a `DD_FREE` hook putting door-game state on the freelist (agora ADR 0022).
- **1.6.4/1.6.5** — the audit's remaining findings.

Measured on the finished 1.6.5 build, poll mode, 300 commands per run:

| Workload | Directory entries | Growth |
|---|---:|---:|
| `help` / `whoami` (touches no directory) | — | **68 B/command** |
| `list` | 1 | **5,338 B/command** |
| `list` | 151 | **15,647 B/command** |

The first row is agora's own residue — effectively zero, which is the point. The other two are
`dir_list`: a fixed **~5.3 KB per call** plus **~69 B per directory entry**
((15,647 − 5,338) / 150). A board with a few thousand posts costs hundreds of KB per `list`, and a
BBS lists on nearly every interaction.

## Reproduction

Any program that calls `dir_list` in a loop shows it; the pattern is what matters:

```cyrius
# Bump-allocator growth is linear in iterations × entries.
var i = 0;
while (i < 10000) {
    var entries = dir_list(str_from("/some/dir"));   # ~4.1 KB + ~69 B/entry, never reclaimed
    var n = vec_len(entries);
    i = i + 1;
}
```

End-to-end against the consumer (agora 1.6.5, needs the agora repo):

```bash
# build, register an identity, create a 150-post board
bash docs/examples/02-register-and-post.sh
for i in $(seq 1 150); do echo "b $i" | ./build/agora post --store ./bbs --subject "s$i" \
    --as qix --key ./keys/qix >/dev/null; done
AGORA_SERVE=poll ./build/agora serve 2323 --store ./bbs &
# then drive `list` N times on one connection and watch VmRSS of the server pid:
#   1 entry   -> ~5.3 KB/command
#   151       -> ~15.6 KB/command
#   `help`    -> ~68 B/command   (control: no directory touched)
```

## Root cause

`lib/fs.cyr`, both target branches of `dir_list`:

- `:110` / `:150` — `var entries = vec_new();`
- `:114` / `:153` — `var buf = alloc(4096);` (the `getdents` buffer)
- `:158` — `var basep = alloc(8);` (Linux/macOS `getdirentries64` out-param)
- `:138` and the equivalent in the non-agnos loop — `vec_push(entries, str_from_buf(name, namelen))`,
  one `Str` allocation per surviving entry, plus the vec's own doubling growth.

None of it is wrong in isolation — it is the natural way to write the function. The gap is that
there is **no variant that lets the caller own the memory**, so a caller with a per-request lifetime
has nowhere to put it.

`dir_list_full` (`:199`), `dir_walk` (`:248`), `find_files` (`:280`),
`dir_walk_with_prunes` (`:307`) and `find_files_with_prunes` (`:342`) all build on the same pattern
and have the same property. `dir_walk` recurses, so it multiplies it.

## Proposed fix

Filing the observation, not the design — but the shape that would let a server-side consumer take
this is a **caller-owned-buffer variant**, mirroring how the `_buf` composers in darshana let a
caller keep the bytes:

```cyrius
# Scratch (the 4 KB getdents buffer) and results both caller-owned.
# Returns the entry count, or negative on error. Names are written as
# NUL-terminated cstrings into `names`, with offsets in `offs`.
fn dir_list_into(path: Str, scratch, scratch_len, names, names_cap, offs, max_entries): i64
```

The existing `dir_list` would keep its signature and become a thin wrapper, so nothing downstream
changes. Two smaller things would also help on their own, if the full variant is not wanted:

1. **A shared/lazily-boxed `getdents` buffer**, the way 6.4.61 handled the `Err(EAGAIN)` singleton —
   `dir_list` is not re-entrant today anyway (it holds one fd and one buffer), so a file-scope 4 KB
   scratch would remove the fixed ~4.1 KB per call without touching the API. That alone takes the
   1-entry case from ~5.3 KB to well under 1 KB.
2. **Documenting the per-call cost** in the function header, so a consumer reaching for `dir_list`
   inside a request loop learns it before measuring it.

The per-entry `Str` cost is the harder half and the one that genuinely needs the caller-owned form.

## Consumer-side workaround (none that works)

Recorded because these were tried or considered and rejected, so the next consumer does not repeat
them:

- **`alloc_reset()`** (`lib/alloc.cyr:243`) rewinds the *entire* bump heap to the first chunk. In a
  server that is unusable mid-session: it would also free the session pool, the door-descriptor
  registry and every live per-session buffer. It is a between-requests tool for a one-shot process,
  not a scoped free.
- **Routing through the consumer's own arena** — agora's `cmd_alloc` (ADR 0021) reclaims per
  dispatched line, and every agora-side allocation on the `list` path was converted to it. It cannot
  reach inside `dir_list`, which is the entire remaining residue.
- **Caching directory listings** — a correctness change (staleness) to work around an allocator
  property. Rejected.
- **`fl_alloc`/`fl_free`** — the freelist is available to consumers, but `dir_list` does not use it
  and a consumer cannot make it.

agora is shipping with the growth documented rather than worked around: agora's `state.md` and its
[2026-07-26 audit](https://github.com/MacCracken/agora/blob/main/docs/audit/2026-07-26-audit.md)
both record this as an upstream ask, in the same terms as the 1.4.5 `sock_set_send_timeout` ask —
which shipped upstream and came back in a later pin.
