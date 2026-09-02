# stiva: stackless coroutines — the live consumer for suspend-across-await — ACCEPTED, PINNED v6.5.x

> ### ⛔ THE "BOUND TO BAND E" PREMISE IS FALSE — re-scoped 2026-08-17 (v6.5.26)
>
> This file, and the roadmap row it feeds, place the work at **`.33`–`.34` (band H)** and justify
> that placement as *"bound to band E's substrate so the poll runtime is not built twice"*.
> **Premise-checked against live code and the coupling does not exist.** Verdict INDEPENDENT,
> and an adversarial pass could not refute it across ~60 checked file:line references and five
> distinct refutation attempts.
>
> Three independent disproofs:
>
> 1. **Band E's substrate is unreachable by default and confined to one file.** It lives entirely
>    in `src/common/ir.cyr` and only runs when the `CYRIUS_IR` env var is set
>    (`src/main.cyr:1510-1529` is the sole enable path, plus `src/main_win.cyr:695`). **5 of the 7
>    compiler forks never call `IR_SENABLE` at all**, and `_IR_REC0` is a no-op at mode 0. All
>    shipped codegen — including every part of async — comes from the direct-emit `E*` path.
> 2. **The "poll runtime" is `lib/async.cyr`, which cycc does not include.**
>    `grep -rn 'include "lib/async' src/` → **zero hits**; CHANGELOG [6.4.38] states it outright
>    ("cycc byte-identical (async is not in the compiler)"). A file the compiler never compiles
>    into itself cannot share an artifact with the compiler's IR optimizer, so **"built twice" has
>    no referent.**
> 3. **The park/resume runtime ALREADY EXISTS AND WORKS.** `_async_wait_events`
>    (`lib/async.cyr:254-273`) parks the current task; `_async_step` (`:127-171`) blocks on the
>    shared epfd and re-enters it. `lib/async.cyr` already contains **five hand-written CPS state
>    machines**.
>
> ⭐ The refutation that came closest, and why it failed: a CPS transform must know which locals
> are live across a suspend point, and the IR *does* carry cross-BB liveness
> (`ir_liveness_cfg`, `IR_LIVEIN`/`IR_LIVEOUT`). If that were local-variable liveness, band H
> would genuinely sit on band E. It is not — `ir.cyr:250-256` documents them as per-BB
> **REGISTER** bitmaps (bit0=RAX, bit1=RCX, …). They would not help a locals-to-frame transform.
>
> ### ⭐ AND THE REAL BLOCKER IS A BUG, NOT A MISSING LANGUAGE FEATURE
>
> `_async_wait_events` stores **the task pointer** in the epoll data slot, so an fd has room for
> exactly ONE waiter, and the `EPOLL_CTL` return is **unchecked** — a second waiter on the same
> fd gets `-EEXIST` and is **silently lost**. That is precisely why "two independent directions
> inside one task" (the `-t` half of `exec -it`, and `select!` over N streams) has no expressible
> shape. It is a lost-wakeup defect in a waiter registry, not an absent CPS transform.
>
> ### Re-scoped plan — HALF A IS LIB-ONLY AND UNBLOCKS BOTH stiva FEATURES
>
> No compiler change, no band-E anything, so it does NOT need `.33`–`.34`:
> 1. `_async_wait_events`: hold a per-fd waiter-LIST head instead of the task pointer, and check
>    the `EPOLL_CTL` return so a second waiter `MOD`s instead of losing its `-EEXIST`; matching
>    multi-wake in `_async_step:145-170`.
> 2. Add `async_wait_rw` (read+write on one fd), which the waiter list makes possible.
> 3. Ship a reusable `async_relay(rt, rfd, wfd, buf, len)` as a sixth ctx-state-machine peer to
>    `_async_recv_task`/`_async_send_task`, so a TTY relay is a library call, not consumer-written.
> 4. Port the same contract to `lib/async_win.cyr` (IOCP) and `lib/async_agnos.cyr`.
> 5. Gate with a `tests/tcyr/crossos/` companion (two-direction relay + same-fd read/write) so it
>    is EXECUTED on real ecb/ach/cass/pi.
>
> Estimated ~150-220 lines in `lib/async.cyr`, ~60-90 in `lib/async_win.cyr`, ~30 in
> `lib/async_agnos.cyr`, ~150 of crossos gate. One release, cycc byte-identical.
>
> ### ✅ HALF A BUILT AND SHIPPED — v6.5.26
>
> `epoll_data` now carries the **fd** instead of the task pointer, and the wake path walks the
> task list waking EVERY parked task whose mask intersects what fired; `EPOLL_CTL_DEL` only
> when no waiter remains (MOD the remainder otherwise); `EPOLL_CTL_ADD`'s `-EEXIST` falls back
> to MOD; `epoll_wait` maxevents 1 → 8; `EPOLLERR`/`EPOLLHUP` wake every waiter on the fd (a
> peer closing mid-relay delivers HUP only). New task field `wait_ev` @56 (TASK_SIZE 56 → 64,
> heap-allocated so no layout change). New `async_wait_rw` + `async_relay_once`, ported to
> `lib/async_win.cyr` and `lib/async_agnos.cyr` as no-op parks per those files' convention so
> consumer code stays target-agnostic.
>
> **Both stiva shapes now work**: two waiters on ONE fd, and two waiters on one fd wanting
> OPPOSITE directions (the `exec -it` TTY-relay shape) — `tests/tcyr/concurrency/
> async_multi_waiter.tcyr`, 23 assertions.
>
> ⭐ **The async reactor had ZERO corpus coverage before this** — `grep -rln
> 'async_run\|async_spawn' tests/tcyr/` returned nothing. Four minors of reactor untested,
> which is how a one-waiter-per-fd limit with an unchecked syscall return survived.
>
> ⚠ **VERIFIED ON LINUX ONLY, and that is a real limit, not a formality.** The reactor is
> epoll-only: PE has no `sys_pipe`, Mach-O has no `sys_epoll_wait`, so the test CANNOT go in
> `crossos/` (tried; PE and Mach-O both rc=1) and the release gate does not execute it
> off-Linux. Windows/agnos got the new names and compile clean, but neither has a
> multi-waiter registry to fix and macOS async is a separate unbuilt gap.
>
> ⚠ **What mutation-testing established, against the first assumption:** the ADD→MOD fallback
> and the wake-path MOD-the-remainder are REDUNDANT INDIVIDUALLY and JOINTLY LOAD-BEARING —
> disabling either alone leaves all axes green (each covers the other), disabling BOTH hangs.
> The part carrying axes 1-4 alone is `epoll_data = fd` + the list walk. Recorded in the test
> header so nobody "simplifies" one away on the grounds the suite stays green.
>
> **Half B (a compiler-level CPS transform) remains unbuilt and, on this evidence, unneeded
> for the two filed features.**

> **Status: HALF A SHIPPED (v6.5.26). Half B not built and not currently justified.**
> ⚖️ **Maintainer decision owed:** this can now ship far earlier than `.33`–`.34`. The roadmap row
> and this file's Placement line should move only on your call.

**Status:** 🟠 **RESIDUAL FIXED at v6.5.37; the Half B DECISION remains the maintainer's.** `async_relay_once` (Linux arm) parked the task via `async_wait_fd` — which does NOT wait, it marks TASK_WAITING and returns, since cyrius has no mid-body suspend — then blocked in `sys_read`, deadlocking the runtime. It hung EVEN WITH DATA ALREADY IN THE PIPE (read and write both succeed, but the task stays parked so `async_run` waits forever to retire a task that already finished). ⭐ Not a design choice: the three sibling implementations already shipped the body WITHOUT the park, so the Linux arm was the outlier. Gate: `tests/tcyr/concurrency/async_relay_once_no_deadlock.tcyr`. ⛔ Half B is UNCHANGED.
**Placement:** ⚖️ **was v6.5.33–.34 (band H, "bound to band E") — that binding is FALSE.**
Eligible for any `.NN` from `.26`; maintainer's call.
**Discovered:** 2026-07-25 during stiva's v3.0.x → v3.1.0 roadmap review
**Severity:** Medium (hard blocker on two shipping features; workaround exists but forecloses them)
**Affects:** cycc 6.3.11 → **6.5.10** (the whole async-as-deferred-Futures era; untouched through
6.5.10, re-verified 2026-08-07)

## Summary

*(The row has since moved: it is `roadmap-future.md:137` at 6.5.10, and it is no longer
"unpinned" — it reads ▲ **PINNED v6.5.x**. The paragraph below is the state at filing.)*

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
