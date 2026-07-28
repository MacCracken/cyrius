# stiva: stackless coroutines — the live consumer for suspend-across-await — ACCEPTED, PINNED v6.5.x

**Status:** 🟡 **OPEN — DELIBERATELY, and it is not rot.** This file is the **acceptance record for a
pinned arc**, not an untriaged report. It is open because no cyrius change has shipped for it (and
none will before v6.5.x); it stays un-archived because archiving is how we assert something is
*done*, and doing that here would hide the consumer requirement from whoever opens the slot.
**Do not "clean this up" in a future rot sweep** — verify instead that the roadmap pin still exists,
and archive only when the v6.5.x coroutine work actually lands.
**Placement:** **▲ PINNED v6.5.x** — confirmed live at the v6.4.82 closeout at
`roadmap-future.md:116`, where the row's original unpin condition (*"No live consumer; pull forward
on a real suspend-across-await need"*) is recorded as **met** by this filing. Bound into the v6.5.x
arc because the poll-runtime rework it needs is the same IR/runtime substrate that minor opens, and
it subsumes the mid-body-suspend "gap 6" of the shipped async "W" arc. 6.x line, never 7.x.

> **✅ ACCEPTED for the v6.5.x arc** (user, 2026-07-26). This filing did exactly what it set out to do:
> `roadmap-future.md:116` parked stackless coroutines with the unpin condition *"No live consumer;
> pull forward on a real suspend-across-await need"*, and this is that consumer and that need. The row
> is now **▲ PINNED v6.5.x**.
>
> Bound into v6.5.x rather than taken as a patch because the poll-runtime rework (+ force-once
> memoization) it requires is the **same IR/runtime substrate the v6.5.x perf-quality minor opens** —
> doing it earlier would mean building that substrate twice. It also subsumes the mid-body-suspend
> "gap 6" of the shipped async "W" arc, so the two land together.
>
> No cyrius change ships for this before v6.5.x; stiva's documented workaround stands until then.
> Left OPEN deliberately (not archived) — it is the acceptance record for a pinned arc, and archiving
> it would hide the consumer requirement from whoever opens that slot.

**Discovered:** 2026-07-25 during stiva's v3.0.x → v3.1.0 roadmap review
**Severity:** Medium (hard blocker on two shipping features; workaround exists but forecloses them)
**Affects:** cycc 6.3.11 → 6.4.78 (the whole async-as-deferred-Futures era)

## Summary

`roadmap-future.md:116` parks **Stackless coroutines** as an *Unpinned follow-on* with the note
*"No live consumer; pull forward on a real suspend-across-await need."*

**stiva is that consumer, and this is that need.** Two features on stiva's v3.1.0 line are blocked
on it, and stiva's own roadmap has carried *"stiva is that consumer and has not filed. Filing is
the unblock lever, not waiting"* as an open action item for weeks. This file closes that gap: the
consumer is now on record.

Nothing is broken. This is not a bug report — the run-to-completion model does exactly what
v6.3.11 documented. It is the "real suspend-across-await need" the entry asked to be shown before
pulling the item forward.

## The blocked features

**1. Interactive `exec -it` (TTY).** `docker exec -it` semantics: attach a terminal to a process
inside a running container, relay keystrokes in and output out, until the user detaches. The
relay must suspend mid-body — read from the pty, `await` the container's stdout, resume where it
left off — while the surrounding task stays alive. Under deferred-then-forced Futures the await
runs to completion at the force point, so there is no "resume where it left off": the loop has to
be restructured as a poll loop that owns the whole body, which is precisely what a TTY relay
cannot be (it is two independent directions, each blocking).

Nuance worth recording so the scope is not overstated: **non-TTY single-stream `exec -i` is
buildable today** over a blocking poll loop, and stiva may ship that first. It is the `-t` half —
two concurrent directions inside one task — that has no expressible shape.

**2. A true multiplexed streaming server** — `select!`-style waiting over many client streams
inside one task. stiva's MCP layer and `logs -f` currently poll a file and terminate on
quiescence (v3.0.12/3.0.13). That is honest for one stream against one file; it does not
generalise to N attached clients, each wanting its own suspend point.

## Reproduction

There is no crashing repro to attach — the shape simply cannot be written. The nearest thing to a
repro is the workaround's cost, which is measurable:

```
stiva 3.0.13, src/main.cyr — `_cli_logs_follow`
  terminates on log QUIESCENCE (2 s idle), not on the stream ending,
  because there is no way to park on "more bytes OR container exited"
  and resume. A 200 ms poll loop is the substitute.
```

```
stiva docs/development/roadmap.md, §v3.1.0
  - [ ] Interactive `exec -it` (TTY) + a true multiplexed streaming server
        Blocked on cyrius stackless coroutines (mid-body suspend/resume —
        the run-to-completion model can't express them).
```

If a compile-fails-to-express repro would help triage more than prose, say so and I will write the
`exec -it` relay in the shape it *wants* to have and attach the diagnostic.

## Root cause

Not a defect — a documented design boundary. From `roadmap-future.md:116`: v6.3.11 shipped
async/await as first-class **deferred-then-forced** Futures over the run-to-completion epoll
runtime, *explicitly not* stackless CPS. True suspend/resume needs the poll-runtime rework (plus
force-once memoization) the same entry names.

## Proposed fix

None from this consumer — the internals call is yours, and the entry already scopes it
("poll-runtime rework + force-once memoization"). The ask is only the one the entry itself
invites: **pull the item forward now that a live consumer exists**, or decline it with a reason so
stiva can close its v3.1.0 item as "won't have" and design around it permanently rather than
holding the slot open.

A decline is a genuinely acceptable outcome here. What is costly is the current state — stiva
carrying a blocked line item indefinitely against an unpinned entry that was waiting for a
consumer to appear.

## Consumer-side workaround (shipped)

stiva ships all three of these today; they are why this is Medium and not High:

1. **`logs -f` polls the file and terminates on quiescence** (200 ms interval, 2 s idle window)
   rather than parking on the stream. It also cannot use container state as the termination
   signal, for an unrelated reason (`container_fixup_after_restart` rewrites RUNNING→STOPPED on
   every load, so a fresh one-shot CLI process never observes a running container).
2. **MCP dispatch is one-shot per tool call** — no long-lived attached session.
3. **`exec -it` is simply not offered.** `stiva exec` reports "not yet wired"; the non-interactive
   half is scheduled over a blocking poll loop, and the `-t` half is deferred to whatever this
   issue resolves to.

Other consumers wanting a TTY relay can reuse (1)'s shape — poll with an idle window — with the
same caveat: it converts "stream until the peer ends it" into "stream until it goes quiet", which
is a different contract and will truncate a slow producer.

## Related

- stiva `docs/development/roadmap.md` §v3.1.0 — the two blocked items, tracked by symbol.
- The sibling gate on that line, kavach `sandbox_spawn` (detached `run -d`), **shipped in kavach
  3.9.0 on 2026-07-25**. Coroutines are now the only remaining external gate on stiva v3.1.0.
