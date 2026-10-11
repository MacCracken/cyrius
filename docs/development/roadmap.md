# Cyrius Development Roadmap — v6.7.x (active minor)

**Scope** — the **active minor only** (v6.7.x, the LANGUAGE minor): what is left of its release sequence, the spec
of each remaining feature, the Break 2 candidates, the folded-stdlib follow-ups and the unscheduled 6.x backlog.
Shipped work does not stay here: each release's record, with the user's decisions, is its
[CHANGELOG.md](../../CHANGELOG.md) entry (traits: [ADR-007](../adr/007-traits.md)); one line per release is in
[completed-phases.md](completed-phases.md). The minors after this one are in [roadmap_6.md](roadmap_6.md), the
unpinned watching list is [roadmap-future.md](roadmap-future.md), volatile state is [state.md](state.md).

> ⛔ **Consumer work is never tracked here** (CLAUDE.md, top rule — user, 2026-10-08). This file holds the language,
> its toolchain and the folded stdlibs (what `lib/` vendors). A consumer's follow-ups live in that consumer's own
> roadmap — the last ones were moved out on 2026-10-08 — and a consumer meets a cyrius change at its own pin bump,
> through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md). agnos is a consumer.

## Where we are

**Current head: v6.7.9** (2026-10-11, slot open) — 6.7.8 shipped · cycc **2,053,536 B** · `.text` **1,840,016** · `cycc-native-aarch64` **1,881,144 B** · **553** `.tcyr`, **259** in `crossos/` · **106** `lib/*.cyr` · **458** shell gates under `tests/gates/<bucket>/` · api-surface **5,828** · **118** open issues · **1** open proposal · next ledger id **CYRIUS-2026-0036**

> Every figure above is DERIVED (2026-10-08), never carried. `version-bump.sh` rewrites only the stamp's version and
> the `(…)` after it — re-derive the rest at each release (`find tests/gates -name '*.sh' | wc -l`, …). Keep the stamp
> at the start of its line with no nested parentheses in its parenthetical, or
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red.

v6.6.x closed at 6.6.20. 6.7.0–6.7.6 shipped (2026-10-07 → 2026-10-08): [completed-phases.md](completed-phases.md)
§ *v6.7.x*.

## The v6.7.x operating rule (user, 2026-10-07)

1. **Language only between the breaks.** A feature release carries language features and nothing else. What it finds
   is FILED as an issue (`docs/development/issues/`), with a repro, the same turn; it is fixed in the release only when the feature cannot
   ship around it (a prerequisite bug) — **or when repairing it is faster than writing the issue: then it is repaired
   where it was found** (user, 2026-10-09), its own commit with its regression row; a quick fix that changes what
   compiles is still asked first. The repair releases are re-balanced at each one's open against what was filed since. A P0 security finding is reported the turn it is found — whether it interrupts
   the arc is the user's call.
2. **Catch-up breaks clear the backlog.** Break 1 was 6.7.6. **6.7.9 is a repair batch before the next feature** (user,
   2026-10-11): two lanes — the quick fixes and the critical / high issues — to take weight off the queue; B7 + P5-B
   moved to 6.7.10 and every later release shifted one. Break 2 is 6.7.11 – 6.7.13 (user, 2026-10-09): the open
   queue repaired to 0 bugs, so fuller audits can follow. 6.7.14 is the full security audit + the refactor /
   optimization review (user, 2026-10-09). The closeout's number is OPEN (user, 2026-10-09): what the 6.7.14
   reviews produce ships first, in as many releases as it takes, and the closeout follows.
3. **Every language decision is the user's** — asked at the arc's start, recorded with its date, never a lane's
   "default" (CLAUDE.md *Execution integrity*).
4. **Every new syntax ships with** a `tests/tcyr/crossos/` file (it runs on ecb / ach / cass / pi), a guide section and a
   vidya entry.

## Release sequence

| Release | Content |
|---|---|
| 6.7.0 – 6.7.8 | ✅ shipped — A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` on every lvalue · the W2 stdlib wave + Break 1 · B4 tuples + B6 default / named arguments (6.7.7) · checked `dyn` + C2 the bounds-checked mode (6.7.8) |
| 6.7.9 | **a repair batch** (user, 2026-10-11): 20 quick fixes + 19 critical / high issues (lists and the approved changes below) |
| 6.7.10 | features: **B7** packed narrow fields + **P5-B** execution coverage (on C2's flag plumbing) |
| 6.7.11 | Break 2, repair 1: the 6.7.7 follow-ons (multi-value receives, call arguments, struct operators) · cybs · install, scanner and CLI hygiene |
| 6.7.12 | Break 2, repair 2: **the platform release** — Darwin / aarch64 syscall translation, the Windows reroutes, the syscall peers, the Windows trust store, the CLI path and lock work (ecb · ach · cass · pi at slot one) |
| 6.7.13 | Break 2, repair 3: global initialisers · the IR arena (a heap-layout change) · diagnostics · u128 / asm / pointer-call stores · TLS conformance · plus whatever 6.7.8–6.7.12 file |
| 6.7.14 | **the full security audit + the refactor / optimization review** (user, 2026-10-09): the audit the 2–3-minor rule owes (last: 6.5.45), its findings fixed in the release · the largest files elevated · the libs improved with what the last months added |
| 6.7.15 → | what the 6.7.14 reviews produce — the number of releases is open, set at 6.7.14's close (user, 2026-10-09) |
| closeout | **after the review follow-ups** (number open): the closeout checklist ([cycle-discipline.md](cycle-discipline.md)) — the checklist, not an audit campaign |

**Break 2 is 6.7.11 – 6.7.13** (user, 2026-10-09): repair the open queue to 0, so fuller audits can follow. Each repair
release runs its lanes in waves, at most two `src/` lanes at a time. Each lane owns its files, and a cross-lane hunk
travels as a named hand-off patch. The binary is rebuilt once on the merged tree. There is one review round, and the
decisions are asked in one round at the open. The `2026-10-09-*` links resolve when 6.7.7 merges; they are on the
lanes until then.

**Why this order.** dyn and B7 both own `parse_types.cyr` and `parse_decl.cyr`'s field arms, so they never share a
release; C2 pairs cleanly with either. dyn goes first for two reasons. It builds directly on B4's anonymous-struct
interning and B6's argument marshaller. And its cx pair emitters must exist before B7 moves `f32 × 4` / `u8 × 16`
structs into cx's 16-byte class. P5-B is split to 6.7.10 now, at planning, because 6.7.8's two `src/` lanes are
taken; it reuses C2's flag plumbing. A third feature release is needed only if an open picks one of these:
- dyn as a generic type argument (5c);
- one of C2's heavy options: branch coverage, `*T` checked against poison headers, or raw `&a + e` checks;
- typed fn pointers too big for the dyn lane;
- u128 carriage inside 6.7.x. That needs the aarch64 register fix (6.7.7), so it would come after the repairs.

## Spec — the remaining feature

Shipped this minor (their specs and the user's decisions are in their CHANGELOG entries): traits, C3 bounds, `const`
/ `const fn`, `bool`, the if-expression, `loop` / `do`, `OP=` on every lvalue, B4 tuples and B6 default / named
arguments (6.7.7), checked `dyn` and the C2 bounds-checked mode (6.7.8).

⚠ Every new keyword is a new reserved word (`IS_KEYWORD_TOK`).

- **B7 — narrow unsigned and `f32` struct fields — layout DECIDED (user, 2026-10-08): packed.** `u8` / `u16` /
  `u32` become 1 / 2 / 4 bytes and zero-extend on read, `f32` 4 bytes, with no padding — the rule `i8` / `i16` / `i32`
  fields follow today (`struct { a: i8; b: i64; }` is 9 bytes). Only structs declaring one of them move — an ABI
  change: `lib/` declares none; cyrius's own tcyr files (23 fields) change in the release. It ships with its
  migration written up in the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md) — never silently.
## The releases after 6.7.8 (placed 2026-10-09; shifted one 2026-10-11)

Sized from every open issue and the three remaining features (the 6.7.x release-plan workflow, 2026-10-09; sizes and the full lane maps: `~/.cache/c6/plan678_712.json`). Every issue's `**Placement:**` line names its release; the open shapes of each feature are decided at its open.

### 6.7.9 — a repair batch (user, 2026-10-11)

Before the next feature, take weight off the queue: one lane of quick fixes (small, no decision; lib / fold gaps
first), one lane of the critical / high issues (silent wrong values, crashes on valid code, lib defects). Chosen
2026-10-11 from every open issue's size; the twelve fixes that change what compiles or computes were all approved as
recommended at the open (the pointer-step reset, `n + p8` typed, unary `-` / `~` in the fold, method and generic
f64 results typed, `&q` of a `*P` parameter, pointer-to-`Box<T>` inference, the stray top-level `}` / undeclared
for-step / zone method-struct-call refusals, the exec-family signal reset, `fhm_set` in place). **39 issues; the
queue 118 → 79 when it ships.**

**Quick lane (20):**
- [`var t, v = fncallN(..)` is refused on cx only — `crossos/method_pair_result.tcyr` has never built for cx](issues/2026-10-10-fncall-destructure-refused-on-cx-only.md)
- [Every PE build that includes `lib/syscalls.cyr` warns "syscall 12 … is not routed" (Windows `sys_brk`)](issues/2026-10-08-pe-sys-brk-unrouted-syscall-warning.md)
- [No stdlib `ppoll` wrapper, and the agnos peer lacks `sys_ioctl` / `sys_fstatat` stubs (asked by yukti)](issues/2026-10-08-no-ppoll-wrapper-and-agnos-ioctl-fstatat-stubs.md)
- [The x86-macOS peer `lib/syscalls_macos.cyr` declares `SYS_ACCEPT4 = 288`, which no macOS path emits](issues/2026-10-08-macos-peer-declares-unused-sys-accept4.md)
- [Literal bounds left in `lib/`: hand-kept 1024 / 64 / 40 copies, two arrays 8× their stated size, and loops bounded by writable public vars](issues/2026-10-08-lib-literal-bounds-and-writable-public-bounds.md)
- [No `sock_set_nodelay`, and Windows `sys_setsockopt` is a -38 stub although net.cyr reaches ws2_32 setsockopt — `TCP_NODELAY` is never set on PE (asked by yantra)](issues/2026-10-08-sock-set-nodelay-windows-route.md)
- [`tls_native_set_client_cert` sizes its PEM decode at `TLS_CA_MAX_ROOTS` (300), not from the input](issues/2026-10-08-tls-client-cert-pem-decode-sized-at-ca-max-roots.md)
- [`lib/math.cyr` has no public length-bounded `f64_parse` — the correctly rounded core is internal (`_f64_parse_n`)](issues/2026-10-08-f64-parse-no-public-length-bounded-form.md)
- [yantra: nine test files include `src/web.cyr` / `src/mobile.cyr` without `src/security.cyr` (undefined-function warnings)](issues/2026-10-08-yantra-tests-miss-security-include.md)
- [Eleven scripts build the compiler from `src/` without scrubbing an inherited `CYRIUS_POISON` / `CYRIUS_BOUNDS` — `install.sh` among them](issues/2026-10-10-self-build-scripts-inherit-poison-and-bounds.md)
- [`scripts/ci.sh` never links `$CYRIUS_HOME/lib` on a fresh home](issues/2026-10-08-ci-sh-fresh-home-links-no-lib.md)
- [The x86_64 release tarball ships without `cyrius-repl.sh` (release.yml looks only in `scripts/`, not `scripts/shims/`)](issues/2026-10-08-release-tarball-misses-shim-scripts.md)
- [`cyrius init` prints "Created <x>/" and exits 0 when its templates are missing](issues/2026-10-08-cyrius-init-exits-zero-with-missing-templates.md)
- [Bare `cyrius bench` / `cyrius fuzz` exit 0 when they find nothing to run](issues/2026-10-08-bench-fuzz-exit-zero-on-empty-corpus.md)
- [`gates_never_write_tree.sh` axis 9 takes any line holding ` trap ` and a trailing ` 0` as the EXIT trap — a prose label fails a clean wine gate](issues/2026-10-10-axis9-trap-detector-matches-prose.md)
- [`gates_never_write_tree.sh` axis 9 cannot see a PE binary run directly through binfmt_misc](issues/2026-10-08-wine-prefix-scan-misses-binfmt-pe-run.md)
- [Under wine, the PE compiler returns rc 3 at once with empty output; the full output lands later](issues/2026-10-09-wine-pe-compiler-exits-before-output-lands.md)
- [`esysxlat_fold.sh` passes a fold that never updates `cur` (mutation (c) is not caught)](issues/2026-10-08-esysxlat-fold-gate-blind-to-cur-update.md)
- [api-surface's line scanner resets its string state at every newline — a multi-line string hides or invents public fns](issues/2026-10-08-api-surface-multiline-string-desync.md)
- [The overload router sends a call to a later-defined `_str` sibling without judging its arity — since 6.7.7's F2 the call is refused, naming a fn the source never called](issues/2026-10-09-overload-router-forward-target-arity-unjudged.md)

**Critical / high lane (19):**
- [A whole-struct store into a ZERO-size struct global writes 8 bytes over its neighbour](issues/2026-10-09-zero-size-struct-global-store-overwrites-neighbour.md)
- [A stray top-level `}` silently ends the translation unit — everything after it is dropped, `OK`](issues/2026-10-11-stray-top-level-brace-silently-ends-the-unit.md)
- [A child the exec family starts keeps its parent's signal mask and ignored dispositions](issues/2026-10-09-exec-family-child-inherits-signal-mask-and-ignores.md)
- [`fhm_set` on a PRESENT key can rebuild (and double) the table — `lib/hashmap.cyr` stopped doing that at 6.6.20](issues/2026-10-08-hashmap-fast-overwrite-rebuilds-table.md)
- [A pointer's step outlives the operator that consumed it: with `q: *i32`, `(x == q) + 100` adds 400](issues/2026-10-10-pointer-step-leaks-through-operators.md)
- [`n + p` with a one-byte `*T` (`*u8` / `*i8`) is no typed pointer, where `p + n` is — `(1 + p8) - q32` builds, `var r: *u8 = 1 + p8;` warns](issues/2026-10-10-int-plus-byte-pointer-drops-step.md)
- [The run-time constant fold folds a literal operator OVER a unary `-` / `~` operand: `-K + 10` is 15, `~5 + 10` is 15](issues/2026-10-10-unary-minus-and-not-folded-over-by-literal-operator.md)
- [A method call's result keeps its last argument's f64 type](issues/2026-10-09-method-call-result-keeps-last-arg-f64-type.md)
- [A generic call's `T = f64` result is an untyped word when T is inferred or only the return type — `gid(h) * 2.0` multiplies bits](issues/2026-10-10-generic-call-f64-result-untyped.md)
- [`&q` of a `q: *P` PARAMETER is the pointee's address when P is a struct over 8 B — every other pointer gives the slot's](issues/2026-10-10-address-of-pointer-param-over-8b-is-pointee.md)
- [A pointer passed to a by-value `b: Box<T>` parameter runs the generic's i64 base — `b.n` read at the wrong offset](issues/2026-10-10-pointer-into-byvalue-generic-carrier-runs-base.md)
- [A closure made inside a suspending `async fn` captures a multi-word struct or tuple with its words reversed](issues/2026-10-09-coroutine-closure-captures-aggregate-words-reversed.md)
- [A top-level closure captures a global from the previous fn's dead locals when the names match — SIGSEGV](issues/2026-10-09-toplevel-closure-captures-stale-fn-local.md)
- [A field name inside a closure body is taken as a capture of the enclosing local of that name](issues/2026-10-09-closure-prescan-reads-field-names-as-captures.md)
- [A coroutine's reserved slot 0 keeps the previous fn's parameter name — a global of that name reads the frame address, and a local of that name is a "duplicate variable"](issues/2026-10-09-coroutine-slot-zero-keeps-previous-fn-local-name.md)
- [`_pm_copies` answers 0 past parameter 61: a by-value struct at parameter 62+ is neither snapshotted nor treated as copied](issues/2026-10-09-by-value-copy-mask-62-parameter-limit.md)
- [A `for` step assigning an UNDECLARED name compiles and stores nothing (`for (i = 0; i < 5; j = i + 1)` never ends)](issues/2026-10-10-for-step-undeclared-name-compiles-silently.md)
- [cx: a constant-folded global initializer is re-evaluated at run time, so `var Q = INT_MIN / -1;` kills cxvm with SIGFPE](issues/2026-10-09-cx-folded-global-reevaluated-int-min-div.md)
- [A declaration-zone global set from a METHOD returning a 9-16 byte struct compiles and crashes at startup](issues/2026-10-10-zone-global-from-method-struct-call-crashes.md)

**Lanes.** The critical lane owns `src/` (and `lib/process.cyr`, `lib/hashmap_fast.cyr`, the guide); the quick lane
owns the rest of `lib/`, `scripts/`, `cbt/`, `programs/`, the yantra fold and their gates — one router hunk in
`parse_fn.cyr` travels as a named hand-off. One review round per lane; the binary is rebuilt once on the merged tree.

### 6.7.10 — B7 + P5-B (features)

**Content.**
- **B7** packed narrow fields, bites 0–6.
  - Bite 0's prerequisite — [the odd-size global struct store](issues/archived/2026-10-09-global-odd-size-struct-store-overwrites-next-global.md) — ships in 6.7.7 (user, 2026-10-09); the
    B7 crossos file adds every size 1–16 to its global rows.
  - It rides the derive bite: [`#derive(Serialize)` and `: cstring` fields](issues/2026-10-08-derive-serialize-cstring-fields.md)
    (asked by sigil).
  - It closes here whatever the answer: [an 8 B struct local from an address is a value](issues/2026-10-08-small-struct-local-from-address-is-value-not-handle.md).
    B7 moves structs across that line.
- **P5-B**, the per-fn hit after `EFNPRO`, the fn map and `cyrius coverage` running the corpus. Closes
  [P5](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md).

**Lanes.** B7 (`src/`: parse_types.cyr, parse_decl.cyr, lex_pp.cyr's derive, util.cyr, lib/str.cyr; it commits
`build/cycc`) · P5-B (`src/` + cbt: the `EFNPRO` sites, the three backend EFNPROs, the forks, the coverage verb).

**Decisions at the open.**
- The handle line: option 1 (handle), 2 (refuse or warn) or 3 (document).
- The cstring wire shape: NULL ↔ `null`, decoded as a fresh copy.
- P5-B: granularity, sink (a Windows mapping route), hosts, spelling, whether a nonzero exit fails the run, whether
  `.tcyr` files are executed.

**Hosts.** B7's all-sizes crossos file on all four. P5-B on the hosts its decision names. `cyrius pulsar`.

### 6.7.11 — repair 1: the 6.7.7 follow-ons

**Content.**
- Return registers:
  - [a multi-value receive reads stale registers](issues/2026-10-09-multi-value-receive-reads-stale-return-registers.md);
  - [a loop-ending fn is not provably one value](issues/2026-10-08-loop-ending-fn-not-provably-single-return.md).
- Call arguments:
  - [a parenthesised struct argument of 8 B or less skips the type check](issues/2026-10-08-paren-arg-small-byval-struct-skips-type-check.md);
  - [an integer into an f64 parameter](issues/2026-10-09-int-argument-to-f64-param-silent.md);
  - [a method result keeps its last argument's f64 type](issues/2026-10-09-method-call-result-keeps-last-arg-f64-type.md).
- Struct operators, on the merge of the two lanes above:
  - [six struct-operator defects](issues/2026-10-08-struct-operator-results.md);
  - [a struct field as the left operand](issues/2026-10-08-struct-field-left-operand-never-dispatches.md);
  - [an int + f64 mix warns twice](issues/2026-10-08-int-f64-mix-warns-twice-in-a-chain.md).
- [The preprocessor's per-byte `PP_LEXST_AT` layer](issues/2026-10-08-self-compile-attribute-line-rule-cost.md),
  early, so later benches carry the win.
- cybs and the seed:
  - [the seed's unchecked caps](issues/2026-10-08-seed-asm-silent-caps-input-labels-code.md): the code-cap row only;
    the seed's own checks are [roadmap_6](roadmap_6.md)'s seed-rotation minor;
  - [cybs: a statement call to an undefined fn](issues/2026-10-08-cybs-undefined-fn-call-in-statement-silent.md)
    first;
  - [cybs: a bare "syntax error"](issues/2026-10-08-cybs-bare-syntax-error-no-location.md), within the 11-label
    headroom.
- Install:
  - [`ci.sh`'s fresh home](issues/2026-10-08-ci-sh-fresh-home-links-no-lib.md);
  - [`cyrius init` exits 0](issues/2026-10-08-cyrius-init-exits-zero-with-missing-templates.md);
  - [the tarballs miss shim scripts](issues/2026-10-08-release-tarball-misses-shim-scripts.md) (every tarball step).
- Scanners:
  - [api-surface's multi-line strings](issues/2026-10-08-api-surface-multiline-string-desync.md);
  - [the attribute word list in five tools](issues/2026-10-08-attribute-word-list-hand-kept-in-five-tools.md);
  - [cyrlint's two rules](issues/2026-10-08-cyrlint-array-overrun-and-write-length-checks.md).
- CLI:
  - [bench / fuzz exit 0 on an empty corpus](issues/2026-10-08-bench-fuzz-exit-zero-on-empty-corpus.md) (rc 1, in
    ecosystem-migration.md);
  - [distlib's two owner rules](issues/2026-10-08-distlib-every-target-owner-rule-differs-from-partial.md);
  - [a killed run's temp dir](issues/2026-10-08-killed-cli-leaves-nonempty-tmp-dirs.md);
  - [axis 9 and a binfmt PE run](issues/2026-10-08-wine-prefix-scan-misses-binfmt-pe-run.md).
- Stdlib and folds:
  - [`fhm_set` rebuilds on a present key](issues/2026-10-08-hashmap-fast-overwrite-rebuilds-table.md);
  - [`f64_parse_n`](issues/2026-10-08-f64-parse-no-public-length-bounded-form.md), the cyrius half. ⛔ bayan's
    delegation tags only after 6.7.11 ships;
  - [yantra's tests miss `security.cyr`](issues/2026-10-08-yantra-tests-miss-security-include.md). ⛔ Tag yantra
    1.0.10 before the re-vendor.

**Lanes.**
- Wave 1: multi-value receives (`src/`, owns the destructure drains; the aarch64 register fix ships in 6.7.7) · call arguments (`src/`,
  owns the B6 marshaller and the argument scanners).
- Wave 2: struct operators (`src/`, commits `build/cycc`) · the preprocessor walk (`src/`, lex_pp.cyr only).
- Alongside: cybs (`bootstrap/`) · install · scanners · CLI · stdlib + folds.

**Decisions at the open.**
- The stale-receive shapes and the loop-ending refusal, as one question (shape 3: refused, or `(p.a, p.b)`).
- `bs1((t))` refused.
- An un-annotated f64 method's value change.
- Struct operators, items 1–6.
- Fields as left operands dispatch.
- The int + f64 chain: "already reported" (default) or retype.
- distlib ties refused by name.
- Reap a dead-pid dir by its contents.
- `fhm_set` never rebuilds on a present key.
- The indirect call's (b), if it was picked at 6.7.8.

**Hosts.** qemu-aarch64, then pi and ecb for the multi-value receive rows; `cyrius pulsar`. wine, then cass, for the
Win64 value-form vectors. cxvm. Seed-derive and the asm closure for cybs.

### 6.7.12 — repair 2: the platform release

**Content.**
- Darwin / aarch64 syscall translation:
  - [x86-macOS `EMACHO_SYSXLAT` not folded](issues/2026-10-08-x86-macos-emacho-sysxlat-not-folded.md) (XLAT-2 in);
  - [an arm64-macOS literal carries pipe / fork fixups](issues/2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md);
  - [`esysxlat_fold.sh` blind to `cur`](issues/2026-10-08-esysxlat-fold-gate-blind-to-cur-update.md);
  - [a native-aarch64 region translates literals silently](issues/2026-10-08-aarch64-native-region-literal-translated-silently.md).
- Windows reroutes:
  - [the `[embed]` link race](issues/2026-10-08-embed-open-link-race-pe-macos-arm64.md) — both halves, because a
    bug ships complete; the arm64 `openat` route is the Darwin lane's bite;
  - [`sys_symlink` without `\\?\`](issues/2026-10-08-windows-symlink-no-long-path-prefix.md);
  - [`xflock` without `LockFileEx`](issues/2026-10-08-xflock-windows-lockfileex-not-wired.md).
- Syscall peers and stdlib:
  - [no `ppoll`; agnos `ioctl` / `fstatat`](issues/2026-10-08-no-ppoll-wrapper-and-agnos-ioctl-fstatat-stubs.md);
  - [Windows `sys_brk` warns](issues/2026-10-08-pe-sys-brk-unrouted-syscall-warning.md) (plus `lib/mmap.cyr:48`);
  - [no `sock_set_nodelay`](issues/2026-10-08-sock-set-nodelay-windows-route.md);
  - [the macOS peer's `SYS_ACCEPT4`](issues/2026-10-08-macos-peer-declares-unused-sys-accept4.md);
  - [literal bounds left in `lib/`](issues/2026-10-08-lib-literal-bounds-and-writable-public-bounds.md).
- Windows runtime and trust:
  - [`async_iocp_pe` step 2](issues/2026-10-08-async-iocp-pe-plain-cmd-c-step2.md) (re-verified first; the gate runs
    both launch forms);
  - [the Windows trust store's four gaps](issues/2026-10-08-windows-trust-store-parity-gaps.md).
- CLI and the lock:
  - [the CLI path / reporting leftovers](issues/2026-10-08-cli-path-and-reporting-leftovers.md) (all eight items);
  - [deps before `lib sync` stamps the new pin](issues/2026-10-08-deps-before-lib-sync-stamps-new-pin.md);
  - [`deps --verify` on CRLF](issues/2026-10-08-deps-verify-crlf-checkout-mismatch.md).
- Folds: the bayan delegation to `f64_parse_n` is refolded, which closes the f64_parse issue.

**Lanes.**
- Wave 1, both at slot one on hardware:
  - Darwin syscall (`src/`): owns `aarch64/emit.cyr` and `x86/emit.cyr`'s Mach-O syscall region;
  - Windows reroutes (`src/`): owns `pe/emit.cyr`, the PE reroute hunks of `x86/emit.cyr` (a hand-off), the route
    table, `_embed_open` and `lib/io.cyr`.
- Alongside:
  - syscall peers: owns `lib/syscalls_*.cyr` and takes `sys_symlink` and the cwd wrapper as hand-offs;
  - Windows runtime + trust;
  - CLI (`cbt/deps.cyr`, `cbt/manifest.cyr`, the in-process SHA-256);
  - the bayan refold.

**Decisions at the open.**
- Native-region literals: warn only (default) or stop translating.
- `SYS_ACCEPT4`: keep it with a comment (default) or delete it.
- Windows `sys_setsockopt` stays a stub (default).
- Trust store: item 4 fails closed (default, which closes it); item 3's wider acceptance gets a CHANGELOG line.
- The lock-pin shape: 1, 2 or 3.
- `cyrius update` copies only `[deps] stdlib` at the pin (`--full` keeps today's copy).
- XLAT-2 in (default).
- `deps --verify`: diagnose CRLF (default).

**Hosts.** All four at slot one:
- ach: the x86 Mach-O fold and its self-host.
- ecb: the literal route and the `openat` route (every file open on Apple Silicon), plus self-host.
- pi: `cyrius pulsar`.
- cass: MAX_PATH, the two-handle lock, the junction race, both launch forms, ProtectedRoots (admin), the cwd route,
  certutil's replacement.

### 6.7.13 — repair 3

**Content.**
- Global initialisers:
  - [`var X = CONST;` is baked and stored; `2 * CONST` is unfolded](issues/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md);
  - [a kernel float global is a dead store](issues/2026-10-08-kernel-float-global-init-not-baked.md) (the scalar
    half; B7 fixed the field half);
  - [a declaration-zone named struct literal is refused](issues/2026-10-09-declaration-zone-named-struct-literal-refused.md);
  - [a redeclared global reads its own bool stamp](issues/2026-10-08-redeclared-global-bool-reads-own-stamp.md).
- The IR arena:
  - [IR=3 drops unrecorded field emits](issues/2026-10-08-ir3-drops-unrecorded-field-emits.md) (the sweep is bounded
    at the open);
  - [the IR heap bands become one `alloc()` arena](issues/2026-10-08-ir-heap-bands-fixed-offsets-and-caps.md) — a
    heap LAYOUT change, so the two-step bootstrap.
- Diagnostics:
  - [a bare const statement](issues/2026-10-08-bare-const-statement-reported-as-assignment.md);
  - [cascades and `error:0:1:`](issues/2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md);
  - [const field access misnamed](issues/2026-10-08-const-field-access-diagnostics-misname-refusal.md);
  - [TOKNAME's unnamed tokens](issues/2026-10-08-tokname-operator-tokens-unnamed.md);
  - [`--syntax-only` and a chained field](issues/2026-10-08-syntax-only-chained-field-through-unresolved-pointee.md);
  - [`#pure` misses a later callee](issues/2026-10-08-pure-check-misses-later-defined-callee.md);
  - the generic-inference diagnostic, if 6.7.8 chose it.
- Frontend remainder:
  - [u128 parameters / returns / fields / captures](issues/2026-10-08-u128-params-returns-fields-captures.md): the
    capture carried, the other three refused by name; the carriage goes to roadmap_6;
  - [`gp().n = 5` refused](issues/2026-10-08-field-store-through-pointer-returning-call-refused.md);
  - [`asm { in al, dx; }`](issues/2026-10-08-asm-in-mnemonic-unreachable.md).
- TLS:
  - [native TLS conformance](issues/2026-10-08-tls-native-conformance-bite.md);
  - [the client-cert PEM sized at the CA maximum](issues/2026-10-08-tls-client-cert-pem-decode-sized-at-ca-max-roots.md).
- Slack: what 6.7.8–6.7.12 file. If it does not fit, a further repair release is said at this open, inserted before the
  audit release (which renumbers by one).

**Lanes.**
- Wave 1: globals (`src/`) · IR arena (`src/`, commits `build/cycc`, two-step).
- Wave 2: diagnostics (`src/`) · frontend remainder (`src/`).
- Alongside: TLS (`lib/tls_native_hs12.cyr` / `hs13.cyr`).

**Decisions at the open.**
- const-init: keep the store (default) or align `var X = C;` with `var X = 5;`.
- Bool redeclaration: (a) or (b).
- u128: refuse now (default) or carry it inside 6.7.x.
- `gp().n = 5` compiles (the untyped-`var` typing is declined).
- The strict asm matcher, and `out dx, eax`.
- `TLS_CA_MAX_ROOTS` is kept (default) or retired.

**Hosts.** wine (IR=1 / IR=3 on the PE fork). Seed-derive (cybs compiles `ir.cyr`). openssl locally. The standard legs.

### 6.7.14 — the full security audit + the refactor / optimization review (user, 2026-10-09)

Its own release, after the queue is at 0 bugs — **not** the closeout (the closeout stays the checklist). Scope is
set at its open, in one round; the output of both reviews is FIXES (CLAUDE.md *Execution integrity*), with only what
cannot pack filed.

- **The full security audit** (CLAUDE.md § *Security Audit Process*; last full audit
  `docs/audit/2026-09-03-security-audit.md` at 6.5.45 — the 2–3-minor rule is due): map the attack surfaces (the TLS
  stacks, `net` / `http` / `ws` / sandhi, DNS, shared temp paths and Windows plantable paths, the release / download
  channel and the seed → cybs → cycc chain, `pam`, secrets in memory) as they stand after 6.7.x's growth; scan; report
  in `docs/audit/<date>-security-audit.md`; a ledger id only for an actual vulnerability (attacker + boundary named);
  P0 / P1 fixed in the release, each with a regression test.
- **The refactor / optimization review — elevate the large files.** The frontend has outgrown its files
  (`parse_fn.cyr` ~13.9 K lines, `parse_expr.cyr` ~6.4 K, `parse_decl.cyr` ~6.2 K, `lex_pp.cyr` ~5.3 K, `parse.cyr`
  ~4.5 K; `cbt/commands.cyr` / `deps.cyr` ~6.6 K each): split them along their real seams (the trait / generic /
  const-fn modules, the call path, the statement dispatch), shrink the giant fns that sit near cybs's per-fn
  reference ceiling (PARSE_FNCALL, PARSE_RETURN, `_PARSE_FN_DEF_IMPL`, `_PARSE_FACTOR_IMPL`, `_field_load_on`), dedupe
  the walkers and scanners the 6.7.x features each grew. Logic-preserving: byte-identical self-host + the whole-corpus
  differential, seed-derive on every bite. Optimization: the self_compile growth tax (1,175 ms at 6.7.6) and cycc size,
  measured same-box before / after.
  - **The layout direction (user, 2026-10-09 — "just thoughts", settled at 6.7.14's open):** folders with direct
    names instead of prefixed files, as `backend/` already does — `src/frontend/parse/expr.cyr` for `parse_expr.cyr`,
    `parse/types/type.cyr` (beside `struct.cyr`, `tuple.cyr`, …) for `parse_types.cyr`, `parse/fn/` for the pieces of
    `parse_fn.cyr` (definitions, the call path, the return / tail path, traits, generics, the const-fn evaluator),
    `lex/` for `lex.cyr` + `lex_pp.cyr`; `cbt/` likewise (`commands.cyr` / `deps.cyr` by verb and stage). Measured
    2026-10-09: cycc embeds no `src/frontend/` path (a pure move rebuilds byte-identical); the include chain is the
    seven forks' `lex.cyr` / `parse.cyr` lines plus `parse.cyr`'s own; cybs's include handler takes a 4 KB name per
    nesting level; ~90 gate files and the docs name these paths. How:
    1. **Moves first, as their own bites — `git mv` + include lines + every path reference, no content change** (the
       grep covers `tests/gates/`, `scripts/`, `.github/workflows/`, `programs/`, `cbt/`, docs, vidya, the open issues'
       `file:line` pointers); byte-identical cycc and seed-derive prove it. Then the splits, each its own bite, so
       history follows (`git log --follow`) and every diff stays reviewable.
    2. **Keep the include graph as flat as today** — one parent includes a folder's files — since cybs's nesting
       depth is bounded; seed-derive on every bite.
    3. **Watch basename collisions** (`lex/lex.cyr` beside `ts/lex.cyr`) wherever a tool or diagnostic keys on a
       basename (`#@file` markers, `CYRIUS_SYMS`, crash localization, cyrdoc).
    4. **`src/`, `cbt/` and `programs/` are internal — free to move. `lib/` paths are the stdlib's public contract**
       (`include "lib/str.cyr"`, `[deps] stdlib`, distlib): reorganizing `lib/` keeps every old path working (a
       one-line include of the new home) and is the user's call per module.
    5. **At 6.7.14, not before** — with no lanes in flight, and after the repair releases, whose issue files cite
       today's `file:line`.
- **Improve the libs with what the last months added**: where it makes `lib/` clearer or safer, use the 6.7.x
  language (traits, `const` / `const fn`, `bool`, tuples, default / named arguments, `loop` / `do`, `OP=`), fill the
  gaps the folds and the repair releases exposed, and retire hand-rolled patterns the language now covers. ⚠ A lib
  file `src/` includes must stay compilable by cybs (no new syntax there); a public symbol's removal or semantic change
  is the user's call (`removed_symbol_census.sh`); a fold's improvement lands in its SOURCE repo and is re-vendored.

### 6.7.15 → — what the reviews produce, then the closeout (number open)

The 6.7.14 reviews' findings that did not pack into 6.7.14 ship next, in as many releases as they take — sized and
placed at 6.7.14's close, never squeezed into the closeout. Then the closeout:


The [cycle-discipline.md](cycle-discipline.md) checklist, ticked into its ledger:
- **Mechanical:** `release-gate.sh` (record check.sh's count) and the bench.
- **Judgment:** heap map (the retired IR bands), the dead-code floor, the 2–3 consolidations the minor earned, code
  review, cleanup.
- **Compliance:** the security re-scan (the full audit ran in 6.7.14); folds byte-identical to their tags (yantra,
  bayan); `verify-store.sh`.
- **Docs:** CHANGELOG / roadmap / state; vidya (tuples, defaults, `dyn`, the bounds mode, packed fields, coverage);
  the backlog re-triaged to 0 open.

### Placed arcs — open by design (moved out of the bug queue)

- [Native TLS capability limits](issues/2026-10-08-native-tls-capability-limits.md):
  - items 1–5 go to [roadmap_6](roadmap_6.md), a capability arc on top of 6.7.13's conformance work;
  - item 6 goes to [roadmap-future](roadmap-future.md), pending constant-time X448 / P-521 in sigil's source.
- [Constant `if` arms](issues/2026-10-08-constant-if-arms-not-folded.md) → roadmap_6, beside the DCE compaction arc.
- [The public-constants `const` migration](issues/2026-10-08-lib-public-constants-const-migration.md) → roadmap_6:
  a stdlib arc that changes what compiles, with sandhi's patch planned at its open.
- [Build profiles and `[build] target`](issues/2026-10-08-manifest-build-profiles-and-target-unread.md) →
  roadmap-future: a CLI feature with two forks.
- [Poison guard pages](issues/2026-10-08-poison-guard-pages-unbuilt.md) → roadmap-future: P6's unbuilt step, which
  needs a PE `VirtualProtect` reroute.
- u128 carriage → roadmap_6, after 6.7.7's register fix. The file itself closes in 6.7.13.

## Folded-stdlib follow-ups (cyrius's own work)

The twelve folds — sakshi, sigil, bayan, sandhi, ganita, niyama, mabda, vani, yantra, yukti, patra, sankoch — are the
language's own stdlib. A fix lands in the fold's SOURCE repo and is released there, then re-vendored byte-identical
(`cmp` against the tag's `dist/`) with its `docs/ecosystem.md` row updated. Each fold's own roadmap holds its longer
list (W2 left there: public `const` / `bool` sweeps in each repo's own minor, traits for hand-rolled dispatch after
checked `dyn`, sigil 3.14.0's cbank retirement, …; sandhi's libssl session-resumption test). Filed here:

- [`#derive(Serialize)` does not support a `: cstring` field — it is taken for a nested struct (asked by sigil)](issues/2026-10-08-derive-serialize-cstring-fields.md)
- [`lib/math.cyr` has no public length-bounded `f64_parse` — the correctly rounded core is internal (`_f64_parse_n`)](issues/2026-10-08-f64-parse-no-public-length-bounded-form.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](issues/2026-10-08-lib-public-constants-const-migration.md)
- [No stdlib `ppoll` wrapper, and the agnos peer lacks `sys_ioctl` / `sys_fstatat` stubs (asked by yukti)](issues/2026-10-08-no-ppoll-wrapper-and-agnos-ioctl-fstatat-stubs.md)
- [No `sock_set_nodelay`, and Windows `sys_setsockopt` is a -38 stub although net.cyr reaches ws2_32 setsockopt — `TCP_NODELAY` is never set on PE (asked by yantra)](issues/2026-10-08-sock-set-nodelay-windows-route.md)
- [`xflock` has no Windows route (`LockFileEx` not wired) — patra's crash recovery never runs on Windows (asked by patra)](issues/2026-10-08-xflock-windows-lockfileex-not-wired.md)
- [yantra: nine test files include `src/web.cyr` / `src/mobile.cyr` without `src/security.cyr` (undefined-function warnings)](issues/2026-10-08-yantra-tests-miss-security-include.md)
- **Constraints on any fold release**: never change the fold API cyrius's own `lib/` calls (sigil's 73 fns, 8 of them
  private `_x509_*` / `_ecdsa_*` used by `tls_native_hs12` / `hs13` / `tls.cyr`; sakshi's 6 in `log.cyr`; bayan
  `base64_encode` in `ws` / `ws_server`; sandhi `sandhi_server_find_header` in `ws_server`). cyrius must not make the
  stdlib internals the folds use `private` (bayan `_sb_grow_a` / `_sb_die`; niyama `_uc_decode_utf8` /
  `_uc_decompose_cp_recursive` / `_uc_emit_utf8`; ganita `_f64_rem_pio2`). A `const` beside a same-name `var` is a
  hard error (sandhi `HTTP_OK` / `HTTP_NOT_FOUND` against `lib/http.cyr` is why sandhi's public consts wait). Adopting
  6.7.x syntax raises a fold's minimum toolchain. yukti pulls sakshi and patra as git tags, so it releases after them.
  yantra's `dist/` is untracked: its refold is `cyrius distlib` at the tag.

## The backlog — `docs/development/issues/`

The backlog is [`issues/`](issues/) (user, 2026-10-08: "issues that are backlogged should have issue/ filed, not sit
in the roadmap"): one file per item, each with a repro and a `**Placement:**` line. This file carries placements and
links only. Only the user promotes an unplaced item into a release. **73** files were filed on 2026-10-08 —
the whole former backlog, premise-checked against 6.7.6, plus what the 6.7.7 lanes found — grouped in
[`issues/README.md`](issues/README.md) § *Open queue*. Placed later-minor work (the DCE compaction arc, `net.cyr` §4,
AF_UNIX, the syscall families) is in [roadmap_6.md](roadmap_6.md); unpinned features (DWARF, `tantu`,
auto-vectorization, …) are in [roadmap-future.md](roadmap-future.md).

## 7.x — public-release ONLY

The language book + legal (licensing / public-release prep). **No codegen, runtime or platform work ever lives at
7.x — if it compiles code, it is 6.x.**

## Open questions — standing defaults, not a queue

Each item carries its default and work starts under it; a genuine fork is asked in one line, that turn — never parked
here as "owed".

1. **The self_compile budget and the growth-tax audit — the later performance track owns both** (user, 2026-07-29;
   the audit is likely dropped, decided at that track's opening review). Input: **1,175 ms · 1,806,240 B at 6.7.6**
   (923 ms · 1,586,184 B at 6.6.19; the old ≤ 700 ms / ≤ 1.20 MB pair is exceeded on both halves — an input to
   re-decide, not a missed target). Record the outcome here.

## Standing notes — traps this minor must not re-learn

- **A batched release** runs strictly sequentially; parallelism is only INSIDE one, in git-worktree lanes where each
  file has one owning lane and every cross-lane hunk travels as a named hand-off patch to a named merge step. At most
  two `src/` lanes, one of which commits `build/cycc`; the binary is rebuilt once on the merged tree (fixpoint +
  seed-derive), `build/cycc-native-aarch64` once with `cyrius pulsar`. Ratchets and censuses (`CORPUS_FLOOR`,
  `CYCC_CEIL`, the alloc census, the cross-compile allowlist, the self-sufficiency floors) are integration steps.
  **A per-lane green is not a merged green.**
- **A ledger id (`CYRIUS-YYYY-NNNN`) is spent in the commit that records it, and only for an actual security
  vulnerability** (attacker and boundary named). That commit moves the ledger
  (`docs/audit/2026-10-08-security-ledger.md`) and state.md's next-id.
- **Text handed into a cyrius string literal obeys the 6.6.11 lexer**: a driver `_gate("…")` description carrying a
  bare `"` or an unknown escape (`\<LF>`, `\q`) stops `programs/checks` compiling.
- **A fold's CI runs isolated, never by hand-extracted steps**: a clean `git archive` copy with `path` deps commented
  out, a throwaway `CYRIUS_HOME` (a copy of the pinned slot, an EMPTY dep cache) and a throwaway `HOME`, with GitHub's
  shell semantics (`bash -e` unless the workflow says `shell: bash`).
- **The `PARSE_RETURN` tail path has skipped a call-site obligation five times** (v6.3.36, v6.4.53, v6.5.1, v6.5.2,
  and `defer` at 6.6.7). The diverts are one predicate now (`_tc_must_divert`, parse_fn.cyr), so a new obligation is a
  new line THERE; grep the tail path for the SHAPE of any new `PARSE_FNCALL`-resident transformation.
  `EDEFER_SAVE` / `EDEFER_RESTORE` must preserve every return register of every return convention (x86: rax, rdx, r8,
  xmm0, xmm1; aarch64: x0–x3, q0, q1; cx: r0–r5) — a new return class that adds a register adds it there.
- **A filing's target list is a report about what the reporter builds, not about the bug.** Reproduce on every host
  that shares the path before scoping the fix (the v6.6.1 DCE issue said "PE only" while x86 Mach-O crashed on ach).
- **An all-identical codegen differential is evidence of a corpus blind spot**, not that a fix is inert: when a fix
  measures 0 diffs, add the shape to the corpus in the same release.
- **A "found by ports" test beats the gate that says the code compiles**: whenever a slot adds a platform-facing verb,
  the `tests/tcyr/crossos/` file is the deliverable.
- **A gate fixture in the wrong order is a vacuous gate**, and a fixture that shares the implementation's assumption
  proves nothing: mutation-prove the gate and check the mutation is reachable.
- **The FREED compiler-state scalar holes are a policy, not a work item**: the next new compiler-state scalar goes into
  a hole (`grep -n FREED src/main.cyr`), not a new slot in the band.
- **Re-derive every count in this file at each release** — a number in a roadmap has nothing checking it.
