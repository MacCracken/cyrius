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

**Current head: v6.7.7** (2026-10-09, in flight) — B4 tuples + B6 default / named arguments · cycc **1,920,400 B** · `.text` **1,719,824** · `cycc-native-aarch64` **1,739,776 B** · **543** `.tcyr`, **249** in `crossos/` · **106** `lib/*.cyr` · **448** shell gates under `tests/gates/<bucket>/` · api-surface **5,828** · **96** open issues · **1** open proposal · next ledger id **CYRIUS-2026-0036**

> Every figure above is DERIVED (2026-10-08), never carried. `version-bump.sh` rewrites only the stamp's version and
> the `(…)` after it — re-derive the rest at each release (`find tests/gates -name '*.sh' | wc -l`, …). Keep the stamp
> at the start of its line with no nested parentheses in its parenthetical, or
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red.

v6.6.x closed at 6.6.20. 6.7.0–6.7.6 shipped (2026-10-07 → 2026-10-08): [completed-phases.md](completed-phases.md)
§ *v6.7.x*.

## The v6.7.x operating rule (user, 2026-10-07)

1. **Language only between the breaks.** A feature release carries language features and nothing else. What it finds
   is FILED as an issue (`docs/development/issues/`), with a repro, the same turn; it is fixed in the release only when the feature cannot
   ship around it (a prerequisite bug). A P0 security finding is reported the turn it is found — whether it interrupts
   the arc is the user's call.
2. **Catch-up breaks clear the backlog.** Break 1 was 6.7.6. Break 2 is 6.7.10 – 6.7.12 (user, 2026-10-09): the open
   queue repaired to 0 bugs, so fuller audits can follow. 6.7.13 is the full security audit + the refactor /
   optimization review (user, 2026-10-09). The closeout's number is OPEN (user, 2026-10-09): what the 6.7.13
   reviews produce ships first, in as many releases as it takes, and the closeout follows.
3. **Every language decision is the user's** — asked at the arc's start, recorded with its date, never a lane's
   "default" (CLAUDE.md *Execution integrity*).
4. **Every new syntax ships with** a `tests/tcyr/crossos/` file (it runs on ecb / ach / cass / pi), a guide section and a
   vidya entry.

## Release sequence

| Release | Content |
|---|---|
| 6.7.0 – 6.7.6 | ✅ shipped — A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` on every lvalue · the W2 stdlib wave + Break 1 |
| 6.7.7 | **B4** tuples + **B6** default and named arguments (decisions below, user 2026-10-08 / 2026-10-09) · the fixes: [`cyrius distlib`'s order-dependent owner](issues/archived/2026-10-08-distlib-owner-first-declarer-credits-fold-monolith.md) · [the ach-timing terminate-children test](issues/archived/2026-10-08-crossos-terminate-children-timing-on-ach.md) · [the silent `x += 1.5`](issues/archived/2026-10-08-compound-assign-f64-rhs-on-int-slot-silent.md) · [install.sh's init templates](issues/archived/2026-10-08-install-sh-source-bootstrap-no-init-templates.md) · [`ci.sh` and a real release tarball](issues/archived/2026-10-08-ci-sh-cannot-install-release-tarball.md) · closing with the lanes: [the pair-into-one-slot stores](issues/archived/2026-10-08-pair-call-assigned-to-single-slot-keeps-tag.md) (B4 T5 + T5b) · [every forward call arity-checked](issues/archived/2026-10-09-forward-call-arity-unchecked.md) (B6 bite 3, fork F2) · a default in a trait's required signature refused (B6, fork F1) · **the silent miscompiles, as integration bites after the lanes merge** (user, 2026-10-09): [aarch64 struct-pair vs multi-value registers](issues/archived/2026-10-09-aarch64-struct-pair-and-multi-value-registers-disagree.md) · [a struct argument sees a later argument's side effect](issues/archived/2026-10-09-struct-arg-sees-later-arg-side-effect.md) · [a closure literal's comma counted as an argument](issues/archived/2026-10-09-closure-literal-comma-counted-as-argument.md) · [an odd-size struct store into a global overwrites the next global](issues/archived/2026-10-09-global-odd-size-struct-store-overwrites-next-global.md) |
| 6.7.8 | features: **checked `dyn`** + **C2** the bounds-checked mode |
| 6.7.9 | features: **B7** packed narrow fields + **P5-B** execution coverage (on C2's flag plumbing) |
| 6.7.10 | Break 2, repair 1: the 6.7.7 follow-ons (multi-value receives, call arguments, struct operators) · cybs · install, scanner and CLI hygiene |
| 6.7.11 | Break 2, repair 2: **the platform release** — Darwin / aarch64 syscall translation, the Windows reroutes, the syscall peers, the Windows trust store, the CLI path and lock work (ecb · ach · cass · pi at slot one) |
| 6.7.12 | Break 2, repair 3: global initialisers · the IR arena (a heap-layout change) · diagnostics · u128 / asm / pointer-call stores · TLS conformance · plus whatever 6.7.8–6.7.11 file |
| 6.7.13 | **the full security audit + the refactor / optimization review** (user, 2026-10-09): the audit the 2–3-minor rule owes (last: 6.5.45), its findings fixed in the release · the largest files elevated · the libs improved with what the last months added |
| 6.7.14 → | what the 6.7.13 reviews produce — the number of releases is open, set at 6.7.13's close (user, 2026-10-09) |
| closeout | **after the review follow-ups** (number open): the closeout checklist ([cycle-discipline.md](cycle-discipline.md)) — the checklist, not an audit campaign |

**Break 2 is 6.7.10 – 6.7.12** (user, 2026-10-09): repair the open queue to 0, so fuller audits can follow. Each repair
release runs its lanes in waves, at most two `src/` lanes at a time. Each lane owns its files, and a cross-lane hunk
travels as a named hand-off patch. The binary is rebuilt once on the merged tree. There is one review round, and the
decisions are asked in one round at the open. The `2026-10-09-*` links resolve when 6.7.7 merges; they are on the
lanes until then.

**Why this order.** dyn and B7 both own `parse_types.cyr` and `parse_decl.cyr`'s field arms, so they never share a
release; C2 pairs cleanly with either. dyn goes first for two reasons. It builds directly on B4's anonymous-struct
interning and B6's argument marshaller. And its cx pair emitters must exist before B7 moves `f32 × 4` / `u8 × 16`
structs into cx's 16-byte class. P5-B is split to 6.7.9 now, at planning, because 6.7.8's two `src/` lanes are
taken; it reuses C2's flag plumbing. A third feature release is needed only if an open picks one of these:
- dyn as a generic type argument (5c);
- one of C2's heavy options: branch coverage, `*T` checked against poison headers, or raw `&a + e` checks;
- typed fn pointers too big for the dyn lane;
- u128 carriage inside 6.7.x. That needs the aarch64 register fix (6.7.7), so it would come after the repairs.

## Spec — the remaining features

⚠ Every new keyword is a new reserved word (`IS_KEYWORD_TOK`).

- **B4 — tuples as values — DECIDED (user, 2026-10-08, at the 6.7.7 open): a tuple bridges to the multi-value
  returns, captured by TYPE.** `(a, b)` builds a value laid out as an anonymous struct of 8-byte slots; `t.0` / `t.1`
  read and write it (`OP=` included); `(i64, f64)` is a type wherever a struct type goes (a `var`, a parameter, a
  field, a return). `var t: (i64, i64) = f();` captures every value of a multi-value call, and `a, b = f();`
  re-assigns existing variables (the re-poll gap — a loop re-polling a `Result` had to bind a fresh pair each pass).
  `var x = f();` keeps its documented first-value meaning (the `ret2` / `rethi()` idiom), so nothing that compiles
  today changes. A shape the decision leaves open is refused by name (extensible later), never given a default
  meaning. **The plan's forks (user, 2026-10-09):** an un-annotated literal with a float element is refused —
  "declare the tuple's type" (`var p: (i64, f64) = (1, 2.5);`; under ADR-002 `var x = 1.5;` is not f64-typed either);
  and the four lossy `: stack` pair stores (`h.n = f()`, `a[0] = f()`, `*p = f()`, `x += f()`) become the compile
  error the guide already documents.
- **B6 — default and named arguments — DECIDED (user, 2026-10-08, at the 6.7.7 open): constant defaults.**
  `fn f(a, b = 2)`: a default is a compile-time constant (a literal, a `const`, a `const fn` call — the 6.7.2
  evaluator) on a TRAILING parameter. `f(1, c: 3)`: named arguments follow the positionals, in any order, each
  parameter at most once, evaluated left to right as written. Direct calls only — a call through a fn pointer or a
  closure stays positional with its exact arity. The v6.5.1 arity check becomes min..max; overloading by arity stays
  out (a count mismatch is never intentional). **The plan's forks (user, 2026-10-09):** a default in a trait's
  required signature is an error (it compiled and was ignored — the signature's parameter list was never parsed); and
  EVERY forward call is arity-checked, not only calls to defaulted fns.
- **B7 — narrow unsigned and `f32` struct fields — layout DECIDED (user, 2026-10-08): packed.** `u8` / `u16` /
  `u32` become 1 / 2 / 4 bytes and zero-extend on read, `f32` 4 bytes, with no padding — the rule `i8` / `i16` / `i32`
  fields follow today (`struct { a: i8; b: i64; }` is 9 bytes). Only structs declaring one of them move — an ABI
  change: `lib/` declares none; cyrius's own tcyr files (23 fields) change in the release. It ships with its
  migration written up in the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md) — never silently.
- **C2 — the opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`, OFF by default). 6.6.12 shipped the
  unchecked half for integer-element `var a: T[N]`; still to do: `*T` pointer subscripts, slice writes and the
  checked mode itself. The stdlib must run clean under it (what it trips is a stdlib repair for the next break).
  **With it, proposal P5's execution half**
  ([proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md);
  P5-A shipped in 6.6.17) — the same insertion point and build-flag plumbing. The bare-local-array slot-write lint
  ([issue](issues/2026-10-08-cyrlint-array-overrun-and-write-length-checks.md)) may fold in here.
- **Checked `dyn` — DECIDED (user, 2026-10-07).** Static dispatch stays the default (ADR-004). `o: dyn Show` is an
  ordinary 16-byte `{data, vtable}` struct (ADR-002's one-word model holds); the compiler builds and VERIFIES the
  vtable from `impl Show for T`, and `o.show()` is an indirect call visible in the declared type. Why: the run-time
  vtables `lib/trait.cyr` and hand-rolled code build are unchecked — a wrong slot or a missing method is a crash.

## The releases after 6.7.7 (placed 2026-10-09)

Sized from every open issue and the three remaining features (the 6.7.x release-plan workflow, 2026-10-09; sizes and the full lane maps: `~/.cache/c6/plan678_712.json`). Every issue's `**Placement:**` line names its release; the open shapes of each feature are decided at its open.

### 6.7.8 — checked `dyn` + C2 (features)

**Content.**
- **Checked `dyn`**, bites D0–D6. Absorbs, as prerequisites:
  - [a trait's required signature is never parsed](issues/2026-10-09-trait-signature-parameter-list-unparsed.md)
    (D1; the default half ships in 6.7.7);
  - [cx refuses a 16-byte struct return](issues/2026-10-08-cx-16b-struct-return-refused.md) (D6). The pair's high
    word goes in r4, the multi-value register, so 6.7.7's aarch64 fix needs no cx bridge.
- **C2**, bites 1–7: `*T` subscripts, slice writes, exact element counts, the `CYRIUS_BOUNDS` / `#bounds` plumbing,
  the check, the crossos violation test, then the stdlib run under the mode. Absorbs:
  - [a for-step never checks its `)`](issues/2026-10-08-for-step-variable-subscript-close-paren-unchecked.md), because
    the new `p[i]` step takes the same arm;
  - [`*p` through a narrow `*T` is a word store](issues/2026-10-08-deref-store-through-narrow-typed-pointer-is-word-store.md),
    because `p[0] = v` and `*p = v` must not disagree.
- Placed by the open's answer:
  - [an indirect call's f64 result is untyped](issues/2026-10-08-indirect-call-f64-result-untyped.md): (a) a bite in
    the dyn lane · (b) goes to 6.7.10 · (c) closed at the open;
  - [generic inference through `Box<T>`](issues/2026-10-08-generic-inference-through-generic-struct-param.md): the
    inference is a bite in the dyn lane; the diagnostic only goes to 6.7.12.
- File at the open: slice parameters and top-level slices are mis-diagnosed parse errors.

**Lanes.**
- dyn (`src/`): parse_fn.cyr's trait module, parse_types.cyr, the `dyn` token and keyword tables, the method arm in
  its own fn. It commits `build/cycc`.
- C2 (`src/`): parse_expr.cyr's subscripts, the for-step, `_deref_store`, the trap emitters, the forks' env block,
  cbt's `--bounds`.
- Hand-offs: `backend/cx/emit.cyr` and the PARSE_FACTOR hook.
- Bite 7 runs after both merge.

**Decisions at the open.**
- dyn 1–8: how a dyn is formed; `self: T` of 8 B or less; generic members; how far the signature check reaches;
  dyn in collections; defaults (confirm); the two words opaque and `dyn A + B`; lib/trait.cyr's fate.
- C2:
  - what a violation does;
  - which accesses are checked (raw `&a + e` in or out; a constant out-of-range index; `@unsafe`);
  - what `*T` is checked against;
  - `p[i]`'s reach and the `*p` width;
  - slice scope;
  - flag spelling and precedence;
  - what the stdlib run's trips become.
- The indirect call: (a) / (b) / (c).
- Generic inference: the inference or the diagnostic.
- cyrlint: stays in 6.7.10 (default) or folds in here.

**Hosts.** D0 at slot one on ecb · ach · cass · pi and cxvm, probing an indirect call through the shared marshaller
(`ECALLPTR_PE`) and struct returns through it. C2's child-process violation test runs on all four. `cyrius pulsar`.

### 6.7.9 — B7 + P5-B (features)

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

### 6.7.10 — repair 1: the 6.7.7 follow-ons

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
    delegation tags only after 6.7.10 ships;
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

### 6.7.11 — repair 2: the platform release

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

### 6.7.12 — repair 3

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
- Slack: what 6.7.8–6.7.11 file. If it does not fit, a further repair release is said at this open, inserted before the
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

### 6.7.13 — the full security audit + the refactor / optimization review (user, 2026-10-09)

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
  - **The layout direction (user, 2026-10-09 — "just thoughts", settled at 6.7.13's open):** folders with direct
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
    5. **At 6.7.13, not before** — with no lanes in flight, and after the repair releases, whose issue files cite
       today's `file:line`.
- **Improve the libs with what the last months added**: where it makes `lib/` clearer or safer, use the 6.7.x
  language (traits, `const` / `const fn`, `bool`, tuples, default / named arguments, `loop` / `do`, `OP=`), fill the
  gaps the folds and the repair releases exposed, and retire hand-rolled patterns the language now covers. ⚠ A lib
  file `src/` includes must stay compilable by cybs (no new syntax there); a public symbol's removal or semantic change
  is the user's call (`removed_symbol_census.sh`); a fold's improvement lands in its SOURCE repo and is re-vendored.

### 6.7.14 → — what the reviews produce, then the closeout (number open)

The 6.7.13 reviews' findings that did not pack into 6.7.13 ship next, in as many releases as they take — sized and
placed at 6.7.13's close, never squeezed into the closeout. Then the closeout:


The [cycle-discipline.md](cycle-discipline.md) checklist, ticked into its ledger:
- **Mechanical:** `release-gate.sh` (record check.sh's count) and the bench.
- **Judgment:** heap map (the retired IR bands), the dead-code floor, the 2–3 consolidations the minor earned, code
  review, cleanup.
- **Compliance:** the security re-scan (the full audit ran in 6.7.13); folds byte-identical to their tags (yantra,
  bayan); `verify-store.sh`.
- **Docs:** CHANGELOG / roadmap / state; vidya (tuples, defaults, `dyn`, the bounds mode, packed fields, coverage);
  the backlog re-triaged to 0 open.

### Placed arcs — open by design (moved out of the bug queue)

- [Native TLS capability limits](issues/2026-10-08-native-tls-capability-limits.md):
  - items 1–5 go to [roadmap_6](roadmap_6.md), a capability arc on top of 6.7.12's conformance work;
  - item 6 goes to [roadmap-future](roadmap-future.md), pending constant-time X448 / P-521 in sigil's source.
- [Constant `if` arms](issues/2026-10-08-constant-if-arms-not-folded.md) → roadmap_6, beside the DCE compaction arc.
- [The public-constants `const` migration](issues/2026-10-08-lib-public-constants-const-migration.md) → roadmap_6:
  a stdlib arc that changes what compiles, with sandhi's patch planned at its open.
- [Build profiles and `[build] target`](issues/2026-10-08-manifest-build-profiles-and-target-unread.md) →
  roadmap-future: a CLI feature with two forks.
- [Poison guard pages](issues/2026-10-08-poison-guard-pages-unbuilt.md) → roadmap-future: P6's unbuilt step, which
  needs a PE `VirtualProtect` reroute.
- u128 carriage → roadmap_6, after 6.7.7's register fix. The file itself closes in 6.7.12.

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
