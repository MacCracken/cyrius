# Bare-metal deliverable #4 (forbidden-module check) was never built

> ### ⛔ RESTORED to the open queue 2026-08-11 — it had been archived UNFIXED
>
> This file was bulk-renamed into `issues/archived/` on 2026-07-10 (commit `79bae42f`, an
> 8-file rename) **with no resolution banner, for work that was never built.** It sat in the
> resolved graveyard while `roadmap.md` simultaneously named it a live W2 fold-in with a spec
> and a negative fixture, and `roadmap_6.md` listed it as an acceptance criterion for a
> *closed* arc.
>
> `issues/README.md` states the principle exactly: **archiving is how we assert something is
> done, so archiving an unbuilt requirement hides it from whoever opens the slot.** This is
> that case — and it was caught by the roadmap, not by the archive sweep.
>
> Premise re-checked against live code at v6.5.19 before restoring:
> `grep -rn 'host_only\|kernel_ok' src cbt lib` → **no implementation**, and the only
> `forbidden` hit in `src/` is an unrelated comment at `parse_fn.cyr:3901`. Still unbuilt.

**Status:** 🔴 OPEN — never built; restored from `archived/` 2026-08-11.
**Placement:** **v6.5.24 — band C**, the small-fix cluster.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** Premise re-verified UNBUILT (`grep -rn 'host_only\|kernel_ok' src cbt lib` → 0 hits). ⚠ Its former W2 arm is DEAD (W2 consumed at .19), so band C is the only remaining home for what is otherwise a never-built acceptance criterion of a shipped arc.
**Filed:** 2026-06-28 (surfaced during the v6.3.4 #7 premise-check).
**Severity:** P3 (DX / safety-rail; no consumer is blocked — agnos builds its
kernel today without it).

## What

The v6.x bare-metal-target arc (roadmap_6.md § "Bare-metal target formalization")
lists **seven** deliverables. Deliverable **#4** is:

> *Kernel-mode stdlib subset (forbidden-module check errors when bare-metal code
> pulls host-OS modules).*

and the arc **acceptance** says "forbidden-module check errors clearly when
bare-metal code pulls host-OS modules" + (for #7) "a kernel object links
tls_native freestanding **and passes the forbidden-module check**."

The v6.3.4 #7 premise-check found **no such check exists** in the compiler. A
`--target=<arch>-bare-metal-elf` build sets `CYRIUS_KERNEL` + `CYRIUS_ELF64_KERNEL`
(+ now `CYRIUS_KERNEL_BASE`) and does NOT restrict which `lib/*.cyr` modules an
`include` can pull. So a kernel build that pulls a host-OS-only module (e.g.
`lib/fs.cyr`, a `sys_open`-on-`/proc` path) compiles silently and faults only at
runtime in the kernel. The roadmap claimed deliverables #1–#3 shipped (.27/.28)
and pinned the OPEN design deliverables as #5/#6/#7 — #4 was never explicitly
marked shipped *or* pinned, so it fell through.

## Why it didn't bite

`tls_native` (the #7 target) happens to be self-contained crypto/state-machine
code; its host-OS coupling (sockets/entropy/clock) is already abstracted behind
the v6.2.x hooks, so it links freestanding cleanly without the check. The check is
a *guard rail* for future bare-metal consumers, not a blocker for the current
agnos kernel or for #7.

## Fix (when picked up)

A compile-time forbidden-module check under `CYRIUS_KERNEL`: maintain a small
deny-list of host-OS-only stdlib modules (or, better, mark each `lib/*.cyr` with
a `#kernel_ok` / `#host_only` annotation) and have the preprocessor/`include`
resolver error with a clear message when a kernel build pulls a `#host_only`
module. Then the #7 fixture (`tests/fixtures/freestanding_tls/kernel_link.cyr`)
becomes a positive case (it passes the check) and a negative fixture (a kernel
program that pulls `lib/fs.cyr`) becomes the gate. This completes the bare-metal
arc's stated acceptance.
