# Undefined-function reachable call should hard-error by default — DEFERRED to the dependency-model arc

> **DEFERRED (2026-06-25), not abandoned.** Designed, implemented end-to-end,
> and verified working in a v6.2.44 spike — then pulled back out of the cut
> because making it the *default* is architecturally entangled with the
> dependency-model arc (see "Why deferred"). The spike's two byproducts —
> the 3 genuine cross-arch stub fixes it surfaced — **did ship in v6.2.44**.
> Pick this up as part of the dependency-model arc (the lever-1 work), where
> cross-module refs become resolvable/declarable.

**Filed:** 2026-06-25 · **Status:** DEFERRED → **v6.3.x (bundled with lever-2 optional deps)**
**Pinned in:** [roadmap_6.md](../roadmap_6.md) v6.3.x "Required vs Optional Dependencies" (lever 2).
**Re-pinned 2026-06-27 (user):** lever 1 (v6.2.46–.49: `requires`/sidecar/umbrella/`[groups]`)
made *declared/transitive* refs resolve, but the issue's acceptance — "loosely-coupled
*consumer* configs build clean WITHOUT `--allow-undef`" — needs refs declarable-*optional*
(e.g. `mabda-but-not-samvada`), which is **lever 2 (v6.3.x)**. So the hard-error default
ships *with* lever 2 in v6.3.x, where it's fully safe; flipping it default-on under lever-1
alone would force `--allow-undef` on legit optional-feature consumer configs. The harness
switch (`cat | cycc` → `cyrius build`) lands with it.
**Supersedes the "Next items" bullet** in roadmap.md for undefined-fn hard-error.

## The bug class

A call to an undefined fn currently compiles with `exit 0` + a warning, then
the emitted `ud2` (x86) / `UDF` (aarch64) **SIGILLs at runtime**. So a consumer
who didn't migrate to a carved sibling (e.g. a removed bayan/sigil fn) ships a
"successful" build of a crashing binary — repeatedly misdiagnosed as a toolchain
bug. The desired fix: a *reachable* undefined-fn call is a hard compile error;
genuinely-dead/unreferenced stubs stay warnings.

## What was designed + verified (the spike)

User-chosen design: **hard-error by default + `--allow-undef` downgrade flag.**

- Flip the existing reachability-filtered check in `src/backend/x86/fixup.cyr`
  and `src/backend/aarch64/fixup.cyr` from `if (_strict_mode == 1 && undef_count
  > 0)` to gate on a new `_allow_undef` global (default 0 → hard-error;
  `--allow-undef` sets 1 → warn). `undef_count` already excludes dead-host refs
  (host-liveness filter), so it fires only on reachable refs.
- These two files cover **5 of 6 forks**: `main.cyr` (x86), `main_win.cyr` (PE)
  and `main_x86_macho.cyr` all `include "src/backend/x86/fixup.cyr"`; the three
  aarch64 forks share `aarch64/fixup.cyr`. Each fork main needs `var _allow_undef
  = 0;` + a `--al` cmdline match (mirroring `--strict`). `main_x86_macho.cyr` has
  no argv parse → always hard-errors (acceptable; Intel-EOL, self-compile HELD).
- The **cx** fork (bytecode) is excluded: it has no fixup-table undef check, no
  cmdline parse, raw-address fn tables incompatible with `_dce_host_fn`, and
  bytecode doesn't SIGILL — porting is ~200-300 lines for ~zero value.
- Verified working on 4 probes: reachable→exit 1; reachable+`--allow-undef`→warn
  +build; dead-host→filtered+builds; clean→builds. All 6 native forks compiled
  clean; x86 self-host byte-identical fixpoint held.

The implementation is recoverable from the git history around 2026-06-25 (the
reverted hard-error edits) if not re-derived.

## Why deferred (the blast-radius finding)

Making it the **default** breaks **21/192 tcyr** + the cx-compiler gate + the
CLI→PE cross gate. The cause is not bugs — it's that the cyrius stdlib is
**loosely-coupled**: module A calls sibling-module B's fns on feature/dead paths
(e.g. `lib/mabda.cyr` → `samvada_session_release_device`, defined only in the
external `samvada` lib; `trait.tcyr` → `str_from`/`str_print` from a string
module it doesn't explicitly include). Warn-only tolerated these everywhere.
`cyrius build` (full dep resolution) satisfies most; anything compiled without
the full set has reachable-host/dead-branch undefs that would now hard-error.

Crucially this is **not just our corpus**: a real consumer using `cyrius build`
who pulls **mabda-but-not-samvada** (a legit optional-feature config) would also
hard-error. A default hard-error therefore needs the dependency model in place
first — so cross-module refs are either always resolved (transitive auto-resolve)
or explicitly declared optional. That is exactly the lever-1 work.

Secondary finding worth fixing independently: the check.sh tcyr harness compiles
via raw `cat | cycc` (the "never raw `cat|cycc` for projects" antipattern
CLAUDE.md forbids) instead of `cyrius build`, which is why it sees undefs
`cyrius build` doesn't. Consider switching the harness to `cyrius build` as part
of this work.

## What already shipped (v6.2.44 byproducts)

The spike's hard-error surfaced 3 genuine cross-arch-propagation gaps (dead PE/
Mach-O dispatch branches that lacked their stubs — masked by warn-only since
v6.2.12/.13). Fixed + shipped in v6.2.44, independent of the hard-error:

- `src/backend/aarch64/emit.cyr`: `EPROCPRNG_PE` + `EGETSYSTIME_PE` stubs
  (completes the 38-fn `_PE` stub cohort; was 36).
- `src/main_aarch64_native.cyr`: `EMITMACHO_ARM64` native-only stub.

## Acceptance (when picked up with the deps arc)

- Reachable undefined-fn call → hard error by default; `--allow-undef` downgrades.
- Cross-module refs resolved/declared-optional so the corpus + loosely-coupled
  consumer configs build clean WITHOUT `--allow-undef`.
- Harness compiles tcyr via `cyrius build`, not raw `cat | cycc`.
- 4-host self-host byte-identical; check.sh green.
