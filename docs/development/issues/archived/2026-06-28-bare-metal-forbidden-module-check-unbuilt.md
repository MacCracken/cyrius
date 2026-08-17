# Bare-metal deliverable #4 (forbidden-module check) was never built

> ### ✅ RESOLVED — BUILT and SHIPPED in v6.5.24
>
> A host-OS-only stdlib module now marks itself with a first-column `#host_only` line; a
> kernel build that pulls one fails with a message naming the module. Annotated:
> `lib/fs.cyr`, `lib/process.cyr`, `lib/net.cyr`.
>
> **Chose the annotation, which this file preferred** ("or, better, mark each `lib/*.cyr`")
> — and it is also the anti-drift choice: the fact lives in the module it describes and
> moves with the file, whereas a central deny-list is a hand-maintained value that goes
> stale on every module add or rename. Unannotated modules stay allowed, so the default
> behaviour is unchanged rather than breaking every kernel build on day one.
>
> ⚠ **The check is at end-of-`PARSE_PROG`, NOT the include site**, and the first cut got
> this wrong: `PREPROCESS(S)` runs at `main.cyr:1189` but `CYRIUS_KERNEL` is not read until
> `:1217`, so `kernel_mode` is still 0 while includes expand — the check compiled, ran, and
> **silently never fired**. End-of-parse also catches the source `kernel;` directive, which
> is not known until every top-level statement is parsed, so both declaration paths are
> covered from one shared site with no per-fork duplication.
>
> This file's own prediction held: the #7 fixture became the positive case. Gate
> `tests/gates/platform/bare_metal_forbidden_module.sh` — 5 axes, including
> `tests/fixtures/freestanding_tls/kernel_link.cyr` passing the check (the arc's stated
> acceptance) and two negatives (host builds, and clean kernel builds) so it cannot
> degenerate into a blanket rejection.

**Status:** ✅ RESOLVED in v6.5.24 — archive at slot close.
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
