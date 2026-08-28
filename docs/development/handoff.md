# Handoff — **v6.5.36 is cut and gate-GREEN (uncommitted).** Nothing is mid-arc.

> **Written 2026-08-28, at v6.5.36.** Read this, then [`CLAUDE.md`](../../CLAUDE.md), then
> [`state.md`](state.md), then [`roadmap.md`](roadmap.md).
>
> ⚠ **Refresh or delete this file when the next release ships. A stale handoff is worse than
> none, and this file is the repeat offender**: it sat at 6.5.10 for ten releases, then at
> 6.5.20 for thirteen more, then at 6.5.33 for two, then at 6.5.35 through the whole of `.36`.
> Every time it was found by a human, never by a gate. **There is no gate for handoff
> staleness** — a standing, deliberate gap. Treat every number below as a claim to re-derive.

---

## Where things stand

| | |
|---|---|
| Version | **6.5.36** — gate GREEN on all 5 steps. **Uncommitted**: push + tag are the maintainer's |
| cycc x86_64 | **1,178,864 B** (+16 from `.35`) — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **199 / 0** · **81** shell gate scripts |
| Cross-OS | **ecb · ach · cass · pi** — all `SELFHOST_OK` + `crossos` **55/55**, REAL hardware |
| Corpus | **284** `.tcyr` (55 in `crossos/`) · **101** `lib/*.cyr` · **97** `programs/**/*.cyr` · api-surface **5089** |
| Bench | `self_compile` **711 ms** vs `.35`'s 716 — flat. **This CSV row is trustworthy** (both quiet-box) |
| Queue | **12** open issues · **2** proposals · **351** archived |
| Mid-arc work | **None.** `.36` is complete; the next slot is open. |

---

## What `.36` was, and why it looks nothing like the roadmap's plan

`.36` was pinned as **band G (SIMD register residency)**. It became a repair release instead,
because two **Critical** defects turned out to be live in already-shipped toolchains. Band G is
untouched and still next.

### 🔴 Enum constants ≥ 2^62 were silently corrupted in `.31`–`.35`

`enum { K = 0x7FFFFFFFFFFFFFFF }` evaluated to **-1**. No warning, `--strict` clean, 282-file
corpus green. szal found it, not us.

**The cause is worth carrying: an in-band tag.** The fold table stored `(1 << 63) | val` and used
the sign bit to mean "this slot holds an enum constant" — 65 bits of information in a 64-bit
slot. v5.5.2 shipped it with a bare mask; v6.5.32 replaced that with a bit-62 heuristic and
**wrote the resulting truncation down as a specification** ("Range: -2^62 .. 2^62-1") instead of
treating it as the defect. Presence is now out of band (`_vecp_base`, lazily allocated per the
`_fnt_tparams` precedent — no new heap region, no fork edit, no `_grow_g*` change).

⭐ **The gate that should have caught it passed for five releases, and the reason generalises.**
`enum_negative_value.sh` axis 5 required every reader to route through the shared
`ENUM_CONST_VAL` decoder. That was correct about the symptom and wrong about the disease: the
decoder itself could not work, so *one shared decoder was doing the corrupting*. **A gate that
pins the mechanism rather than the property passes while the mechanism is wrong.** Axis 5 now
asserts the property (presence is out of band) and a new axis 6 asserts the full i64 range.

### 🔴 On ELF-aarch64, `sys_pause()` issued `flock` and `sys_signalfd()` issued `fsync`

kybernet's entire aarch64 target was non-functional; every gate was green. The stdlib declared
the **native** numbers (73 ppoll, 74 signalfd4) expecting pass-through, but ESYSXLAT's x86-compat
rows rewrite 73 (x86 flock) → 32 and 74 (x86 fsync) → 82 — and **a compat row cannot tell a
native number from the x86 number it is matching.**

Both moved to the ≥1000 private alias band (1073/1074). ⚠ **The rows must stay LAST in the
ELF-aarch64 chain**: they *produce* x8=73 and x8=74, exactly what the flock and fsync rows
compare against, so placing them earlier reintroduces the identical bug.

⭐ **The Mach-O allow-list had already written this collision down** — `macho_route_parity.sh`
notes that `SYS_SIGNALFD4=74` "collides with the fsync row 74->95, so it LOOKS routed; it is not
a route". Someone saw it on the Mach-O side and did not check the ELF side.

---

## ⚠ Three traps this release paid for. Read before writing a cross-host test.

1. **A `crossos/` test must be guarded by CAPABILITY, not written for Linux.** My first version
   asserted the Linux shapes unconditionally and went red on ecb, ach and cass — Darwin and
   Windows have **no signalfd at all**, and the wrapper is deliberately unrouted there, so
   calling it emits an unclassed number that SIGSYS-kills the process.
2. **Do not enumerate errnos.** The second version accepted only `{0, ENOTTY, EINVAL}` and still
   failed on both Macs while passing every time I ran it by hand — because
   `cross-os-libtest-runner.sh` runs every test with `</dev/null >/dev/null`, and the errno
   depends on what fd 1 *is*. Measured on real ecb: the identical binary returns **25 (ENOTTY) on
   a pty and 19 (ENODEV) on /dev/null**. Assert the invariant (it reached a driver, i.e. never
   ENOSYS), not the value.
3. **`check.sh` runs its shim gates under `set -e`**, so the PE failure **aborted the run before
   `folds_agnos_parity` ever executed**. Two independent root causes, only one visible at a time.
   If a shim gate fails, assume the ones after it are unmeasured.

---

## Stdlib folds — and the one that had to be fixed at source

- **sandhi 1.9.10 → 1.9.14** · **sankoch 2.7.8 → 2.7.10** — both folded clean.
- **sigil 3.12.9 → 3.12.14**, and ⛔ **3.12.14 was written during this release because 3.12.13
  could not be folded.** Two defects, one class: `agnosys_run_capture_timeout` was guarded for
  agnos only (Windows also has no fork/execve, and the cyrius PE peer defines no `SYS_FCNTL`),
  and `agnosys_run_checked_timeout` — added by 3.12.13, the release headlined *"every exec in
  sigil is bounded"* — shipped with **no target guard at all**. So the fix and the regression
  landed together.

⭐ **sigil is in every fold's preamble, so one unguarded line broke 11 of 12 folds on agnos and
the Windows builds of mabda and yukti** — repos that contain no such line. Fixed **upstream
first**, all 14 dist profiles regenerated with `distlib --all` (regenerating only the base bundle
is how sub-profiles once shipped a known-bad encoder).

---

## Next up: `.37` — band G, SIMD register residency (Slot 6)

Unchanged and un-started. **Premise-check at slot entry — these pins have a history of rot.**

- ✅ **Item 3 shipped at `.24`** (f64v4 ymm widening). ⚠ Residual: `f64v4_fmadd` was never widened.
- **Item 1** genuinely unbuilt — all 15 emitters in `backend/x86/float.cyr` are
  memory→register→op→memory loops, the ymm one included.
- ⛔ **Item 2 is a GATE-WIDENING question, not a build.** The wrapper inliner is LIVE and fires
  today, gated to generics.
- ⚠ Re-derive the simd-site count — last measured **29**, not the 25 an older pin carried.
- ⭐ **Band F handed band G its opening**: the regalloc byte matcher recognises only REX.W mov to
  and from `[rbp+disp32]`, so **no xmm/ymm local is a register candidate at all**.

---

## 📥 Reactive queue — 12 open

**Consumer-filed, unaddressed:**

- **`owl-private-fns-still-collide-across-files` (High)** — verified live. `private` is enforced
  on *reference* but not on *definition*: another file's same-named fn replaces a private helper
  **including for that file's own internal calls**; `private` in both files does not help; and
  the override **bypasses the arity check**. ⚠ Precision the filing's title overstates: cycc does
  emit `warning: duplicate fn … (last definition wins)`. The genuinely silent part is the arity
  bypass. Connects to the standing per-item `private` decision.
- **`darshana-aarch64-syscall-shadow-no-diagnostic` (Medium)** — a user `var SYS_*` shadowing the
  stdlib's arch-aware value silently emits a different syscall on aarch64; the routing warning is
  still gated to the Mach-O branch. **Same table as the Critical above, opposite direction** —
  worth doing while the context is fresh.
- **`preprocess-out-8mb-ceiling` (Medium)** — thoth is at ~96 % of a hard ceiling. Needs a heap
  **layout** change ⇒ two-step bootstrap; not foldable into an ordinary patch.
- **`audit-scope-excludes-tests-and-defines` (Medium)** — `cyrius audit` reports "lint clean" on
  a project that is not. Partly a scope-semantics decision.
- **`versioned-wrapper-does-not-pin-cycc`** — untriaged, deliberately held per the maintainer.

**Standing repair backlog (roadmap-pinned):** `ir-regalloc-rewrite-needs-reemit` (band F closed
its cross-BB half; Wall 1 re-emit + Wall 2 remain) · `macos-threading-workers-dont-run` ·
`simd-f64v-memory-operand` (now band G) · `v6415-closeout-residuals` · `dx-multi-error-reporting`
· `stiva-stackless-coroutines` (Half B) · `sock-send-result-allocates-per-call`.

---

## ⚖️ Owed to the maintainer

1. **`CYRIUS_CROSS_OS_FULL=1` as the default** — ecb/ach/pi were at 282/282 as of `.33`; cass's
   32 need triaging into skip-with-a-reason versus real. **Re-derive before deciding.**
2. **The seven residual typed-pointer warnings** on `i64`-declared sources.
3. **Slot 9 design** — both storage relocations disproven; escape analysis or a scope-tied arena.
4. **stiva Half B** — unbuilt and, on `.26`/`.27` evidence, unjustified.
5. **Per-item `private`** — still compiles with no diagnostic; the owl High leans on this area.
6. **`archived/README.md` indexes 38 of 351** — every 6.5.x-era archive is unindexed.

---

## Working rules that bit hardest here

- **Push and tag are the maintainer's.** Never commit or push. **Never `gh`** — `curl` only.
- **`~/.cyrius/versions/<VERSION>/` must exist.** The `.36` bump left no install snapshot, so
  `cyrius deps` had no toolchain to resolve and a gate failed with a misleading symptom
  ("include push is order-dependent"). `sh scripts/version-bump.sh "$(cat VERSION)"` regenerates
  it. Snapshot-refresh `cp`s guarded with `[ -d … ]` silently no-op when it is missing.
- **Fix the SOURCE repo, not the fold** — a fix in the vendored `lib/<dep>.cyr` evaporates at the
  next re-vendor. Patch upstream, bump, `distlib --all`, re-vendor.
- **Seed-derive is mandatory for ANY `src/` change**; cybs fails *silently* on things
  `build/cycc` compiles fine.
- **An unreachable host is not a passing host.** pi did not resolve on the first attempt; the
  gate was held open rather than reported green, and qemu-user is not a substitute (it could not
  surface the v6.4.42 aarch64 epoll defect, and it fails `thread_detach` on both `.35` and `.36`).
- **A number you did not just derive is stale.** Every figure here was derived 2026-08-28.
