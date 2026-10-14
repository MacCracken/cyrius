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

**Current head: v6.7.11** (2026-10-13) — B7 packed narrow fields + the handle line + size-independent struct copies, P5-B execution coverage, the 6.7.9 fold wave refolded · cycc **2,114,376 B** · `.text` **1,900,296** · `cycc-native-aarch64` **1,950,240 B** · **573** `.tcyr`, **276** in `crossos/` · **106** `lib/*.cyr` · **474** shell gates under `tests/gates/<bucket>/` · api-surface **5,838** · **137** open issues · **0** open proposals · next ledger id **CYRIUS-2026-0036**

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
| 6.7.0 – 6.7.10 | ✅ shipped — A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` on every lvalue · the W2 stdlib wave + Break 1 · B4 tuples + B6 default / named arguments (6.7.7) · checked `dyn` + C2 the bounds-checked mode (6.7.8) · the repair batch (6.7.9) · B7 packed narrow fields + the handle line + P5-B execution coverage (6.7.10) |
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

## Spec — the remaining features

Every feature of the v6.7.x plan has shipped (its spec and the user's decisions are in its CHANGELOG entry): traits,
C3 bounds, `const` / `const fn`, `bool`, the if-expression, `loop` / `do`, `OP=` on every lvalue, B4 tuples and B6
default / named arguments (6.7.7), checked `dyn` and the C2 bounds-checked mode (6.7.8), B7 packed narrow fields with
the handle line and size-independent struct copies, and P5-B execution coverage (6.7.10). What remains is repair
(6.7.11 – 6.7.13), the audit and review (6.7.14) and the closeout.

⚠ Every new keyword is a new reserved word (`IS_KEYWORD_TOK`).

## The releases after 6.7.8 (placed 2026-10-09; shifted one 2026-10-11)

Sized from every open issue and the three remaining features (the 6.7.x release-plan workflow, 2026-10-09; sizes and the full lane maps: `~/.cache/c6/plan678_712.json`). Every issue's `**Placement:**` line names its release; the open shapes of each feature are decided at its open.

### 6.7.11 — repair 1: the 6.7.7 follow-ons

**Content.**
- Return registers:
  - [a multi-value receive reads stale registers](issues/2026-10-09-multi-value-receive-reads-stale-return-registers.md);
  - [a loop-ending fn is not provably one value](issues/2026-10-08-loop-ending-fn-not-provably-single-return.md).
- Call arguments:
  - [a parenthesised struct argument of 8 B or less skips the type check](issues/2026-10-08-paren-arg-small-byval-struct-skips-type-check.md);
  - [an integer into an f64 parameter](issues/2026-10-09-int-argument-to-f64-param-silent.md);
- Struct operators, on the merge of the two lanes above:
  - [six struct-operator defects](issues/2026-10-08-struct-operator-results.md);
  - [a struct field as the left operand](issues/archived/2026-10-08-struct-field-left-operand-never-dispatches.md);
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
- Scanners:
  - [the attribute word list in five tools](issues/2026-10-08-attribute-word-list-hand-kept-in-five-tools.md);
  - [cyrlint's two rules](issues/2026-10-08-cyrlint-array-overrun-and-write-length-checks.md).
- CLI:
  - [distlib's two owner rules](issues/2026-10-08-distlib-every-target-owner-rule-differs-from-partial.md);
  - [a killed run's temp dir](issues/2026-10-08-killed-cli-leaves-nonempty-tmp-dirs.md);
- Stdlib and folds:

- Filed 2026-10-12 (the doc sweep's verifiers, the 6.7.10 refolds):
  - [BENCHMARKS.md prints the cycc size rows (byte counts) as milliseconds — `cc5_bytes | 1ms | 2ms | 2ms` — and the file-size row is still named `size/cc5_bytes`](issues/2026-10-12-benchmarks-md-size-rows-formatted-as-time.md);
  - [The "cannot be a fn return type" note lists an incomplete return-type set: `bool`, a multi-value `(T1, T2)`, `dyn Tr` and a generic's `T` are accepted but not named](issues/2026-10-12-return-type-refusal-note-incomplete.md);
  - [Every build that includes `lib/sandhi.cyr` (so every `lib/yantra.cyr` build) prints the large-static-data advisory](issues/2026-10-12-sandhi-include-prints-large-static-advisory.md);
  - [A struct result over 8 bytes through `fncallN` / `callptr` compiles with no diagnostic and faults: no hidden result pointer is passed, no register pair is received](issues/2026-10-12-struct-result-through-fn-pointer-faults.md);
  - [A value-form vector receive from `callptr` / `fncallN` (or any source but a by-name vector call) compiles with no diagnostic and reads wrong lanes, and faults on PE](issues/2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md);

- Filed 2026-10-12 / 13 (the 6.7.10 lanes and their reviews):
  - [The `#derive` scanner `T_from_json_str` skips a nested `#derive`d struct field's object to its first inner `,`: the nested field stays 0, every field after it is lost, and the nested object's own keys land in the outer struct](issues/2026-10-12-derive-scanner-loses-fields-after-nested-struct.md);
  - [Under `CYRIUS_IR=3`, LASE drops the reload of a just-stored local across an unrecorded `EFLADDR` (`lea rax, [rbp+d]`): a method's argument, a by-value struct argument or a struct-returning call's argument receives the struct's ADDRESS](issues/2026-10-12-ir3-lase-reloads-across-unrecorded-efladdr.md);
  - [A pointer into a by-value struct parameter of 8 B or less is still passed as the pointer word when the pointer typing calls it no pointer: an if-expression of two different steps, an integer on the LEFT of the pointer](issues/2026-10-12-pointer-into-small-byvalue-param-untyped-edges.md);
  - [A dereference `*p` of a struct under 8 bytes is read as a whole word: a global initialised or assigned from it, a local assigned from it, a by-value argument and a `return *p` read past the object (SIGSEGV when it ends a mapping); only a local declaration copies byte-exact](issues/2026-10-12-small-struct-dereference-reads-past-the-object.md);
  - [A fn returning a struct of 8 B or less returns a local of ANOTHER struct type (its word) with no refusal, and a `*T` local or a `*U` parameter as its ADDRESS](issues/2026-10-12-small-struct-return-takes-another-structs-value.md);
  - [A struct global over 8 B initialised from a field reached through a `*T` (`var G: S16 = P.s;`, `= gp().s;`, `= VV.p.s;`) holds the field's first word and SIGSEGVs at the first use](issues/2026-10-12-struct-global-init-from-field-through-pointer-faults.md);
  - [An ASSIGNMENT from a struct dereference (`l = *p`, `G = *p`, `o.s = *p`, `q = *p` into a `*S`) stores one word at every size, with a false "assigning non-pointer to typed pointer" warning](issues/2026-10-13-assignment-from-struct-dereference-copies-one-word.md);
  - [`take8(*pu)` with `pu: *U8` (a pointer to ANOTHER struct) into a by-value `S8` parameter compiles and passes U8's bytes; `take8(u)` with `u: U8` and the 16 B `take(*pu)` are refused by name](issues/2026-10-13-dereference-of-other-struct-into-small-byvalue-param-decision.md);
  - [A generic call declared `: *T` (`fn gpg<T>(): *T`) is no struct source: `l = gpg<S>()` stores the pointer's word, `*gpg<S>()` as a value SIGSEGVs (a declaration, an argument, either operand), `gpg<S>().v` is refused](issues/2026-10-13-generic-pointer-returning-call-as-struct-source.md);
  - [`return GP;` (a `*S` global) and `return gp();` (a `: *S` call) from a fn returning a struct of 8 B or less return the POINTER's word; over 8 B both are refused by name](issues/2026-10-13-small-struct-return-of-pointer-global-or-call-decision.md);
  - [A struct-typed FIELD destination from a `*S` global, a `: *S` call or a `*S` field (`o.s = GP`, `o.s = gp()`, `o.s = w.p`) stores the pointer's word at every size](issues/2026-10-13-struct-field-destination-from-pointer-global-call-or-field.md);
  - [`GP = l` with `GP` a `*S` GLOBAL stores `l`'s first word into `GP` (a garbage pointer), where a `*S` local or parameter destination copies `l` into its pointee](issues/2026-10-13-struct-value-into-pointer-global-destination-decision.md);
  - [An untyped binding takes a struct-returning OPERATOR's type at every size (decision 12), but not a method chain or an if-expression of 8 B or less, nor a parenthesised 9–16 B operator / method result](issues/2026-10-13-untyped-struct-binding-beyond-operators-decision.md);

**Pulled in at the open (user, 2026-10-13).**
- The agnos filings: the `#109` `sys_sock_send_dl` / `#110` `sys_console_mode` / `#111` `sys_fd_kind` peers (agnos
  1.57.13 is tagged), [the negative fd taken for socket slot 7](issues/2026-10-12-agnos-negative-fd-taken-for-socket-slot-7.md),
  and [the kernel DCE compaction](issues/2026-10-10-agnos-kernel-dce-compaction-moves-data.md) (roadmap_6.md's arc,
  its kernel bite only).
- The newly filed Highs: [the f64 / `struct i` instance collision](issues/2026-10-12-generic-f64-instance-name-collides-with-struct-i.md),
  [the top-level `return`](issues/2026-10-12-top-level-return-decision.md) and
  [the async multi-value return](issues/2026-10-09-async-fn-multi-value-return-loses-second-value.md) (from 6.7.13),
  [the poison env](issues/2026-10-10-poison-env-zero-or-empty-turns-mode-on.md),
  [`cyrius header`'s struct returns](issues/2026-10-10-cyrius-header-ignores-struct-returns.md),
  [the Windows target selectors](issues/2026-10-10-windows-cli-drops-target-selectors.md) and
  [cbt's self-builds](issues/2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md) (from 6.7.12).
- [`dir_list` without `O_DIRECTORY`](issues/2026-10-13-dir-list-opens-directory-without-o-directory.md) (a `lib/` defect).
- The folds: sankoch **2.8.6** refolded; sakshi **2.5.10** (the two 4 KiB rings declared as 4096 slots — the cause of
  the sandhi large-static advisory). ⛔ 6.7.11 cannot tag before the user tags sakshi 2.5.10 and it is refolded.

**Lanes** (triage 2026-10-13: all 79 items reproduce on the slot-open compiler; at most two parser lanes at a time).
- Wave 1: multi-value receives · call arguments (parser) — alongside: infra (the preprocessor fast path, cybs + the
  seed's code-cap row, the kernel DCE compaction) · tools (scanners, cyrlint, distlib, the temp-dir reaper, the bench
  report, the CLI Highs) · stdlib + folds.
- Wave 2, on wave 1's merge: struct copies + struct operators (one lane) · generics, then the frontend remainder (one
  lane).

**Decisions at the open** (user, 2026-10-13 — asked once, all answered as recommended; recorded in each bite's
CHANGELOG line). Every one applies an existing rule to a shape it missed, except two forks:
- **D22:** a `: stack` pair as a struct-literal element is refused by name; a pair as a plain argument keeps the
  documented single-argument tag rule (`is_ok(f())`) — the 2026-10-09 argument half is withdrawn.
- **D11:** a top-level `return` is refused by name ("return outside a fn body").
- The rest, by lane: multi-value — the stale-register shapes, loop-ending one-value callees, a >16 B struct callee
  in a destructure, a multi-value call into a named struct, a scalar annotation from a struct call and an
  `async fn (T1, T2)` refused by name; a pair method above its impl refused for a single bind. Call arguments — an
  unknown fn-pointer callee's struct result stays a handle (a known `&f` callee is fixed); a vector receive from an
  unknown callee or a word refused; `rd(b)` into `p: *V` passes the address; parameter types take the trait-signature
  grammar plus bare `*fn`; `bs1((t))` and `take8(*pu)` refused; `n + pb` is that pointer. Struct copies — a `*S`
  return source returns the pointee; `GP = l` copies into `*GP`; a ≤8 B return of another struct refused; `*p = v`
  copies the whole struct. Struct operators — unary minus is word negation; `return (a, b)` in a struct fn and a
  non-dispatching operator after a pair call refused; the int + f64 chain warns once; decision 12 extends to a
  ≤8 B method chain / if-expression and a parenthesised 9–16 B result; `h.get().b` and a wrapped call as a nested
  literal element accepted. Generics — `gen$f64` with marked struct fragments; a scalar into a struct-typed generic
  method refused; a generic call's result infers T; an undefined overload sibling never takes a call; `Vec<T>`
  annotations checked; a declared `struct slice` wins in locals. Frontend — const arity = run-time arity; a
  closure reads a captured slice's `.len` / `.ptr`; saturating ops on a pointer give an integer; `n + &x` is a byte
  pointer; cx auto-calls `fn main`. Tools — distlib ties refused; the reaper removes scratch-only dead-pid dirs;
  `CYRIUS_POISON` takes the `CYRIUS_BOUNDS` rule; `cyrius header` models the struct-return ABI; the Windows CLI
  refuses `--agnos` / bare-metal targets. cybs — the line text plus the unsupported-construct list (per-construct
  refusals and file:line filed to the seed-rotation minor).

**Hosts.** qemu-aarch64, then pi and ecb for the multi-value receive rows; `cyrius pulsar`. wine, then cass, for the
Win64 value-form vectors. cxvm. Seed-derive and the asm closure for cybs.

### 6.7.12 — repair 2: the platform release

**Content.**
- Darwin / aarch64 syscall translation:
  - [x86-macOS `EMACHO_SYSXLAT` not folded](issues/2026-10-08-x86-macos-emacho-sysxlat-not-folded.md) (XLAT-2 in);
  - [an arm64-macOS literal carries pipe / fork fixups](issues/2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md);
  - [a native-aarch64 region translates literals silently](issues/2026-10-08-aarch64-native-region-literal-translated-silently.md).
- Windows reroutes:
  - [the `[embed]` link race](issues/2026-10-08-embed-open-link-race-pe-macos-arm64.md) — both halves, because a
    bug ships complete; the arm64 `openat` route is the Darwin lane's bite;
  - [`sys_symlink` without `\\?\`](issues/2026-10-08-windows-symlink-no-long-path-prefix.md);
  - [`xflock` without `LockFileEx`](issues/2026-10-08-xflock-windows-lockfileex-not-wired.md).
- Syscall peers and stdlib:
- Windows runtime and trust:
  - [`async_iocp_pe` step 2](issues/2026-10-08-async-iocp-pe-plain-cmd-c-step2.md) (re-verified first; the gate runs
    both launch forms);
  - [the Windows trust store's four gaps](issues/2026-10-08-windows-trust-store-parity-gaps.md).
- CLI and the lock:
  - [the CLI path / reporting leftovers](issues/2026-10-08-cli-path-and-reporting-leftovers.md) (all eight items);
  - [deps before `lib sync` stamps the new pin](issues/2026-10-08-deps-before-lib-sync-stamps-new-pin.md);
  - [`deps --verify` on CRLF](issues/2026-10-08-deps-verify-crlf-checkout-mismatch.md).

- Filed 2026-10-12 (the doc sweep's verifiers, the 6.7.10 refolds):
  - [cass (Windows) full-corpus failures were never triaged into named skips vs real failures — the last count is v6.5.33's 32 of 282, the corpus is now 562, and no open issue tracks it](issues/2026-10-12-cass-full-corpus-failures-untriaged.md);
  - [`cyrius build` takes contradictory target flags (`--win --aarch64`, `--win --agnos`, `--aarch64 --target=js`, …), silently keeps one and exits 0](issues/2026-10-12-combined-target-flags-silently-resolved.md);
  - [cx's fixed 512 KiB code buffer: `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr` stops with a bare "codebuf overflow" on cx](issues/2026-10-12-cx-codebuf-512k-overflows-yukti-crossos-test.md);
  - [`cyriusly setup` (compiled): its "bootstrap cycc" step builds no cycc, its cross-bin loop can never match, and it builds the installed tools under an inherited `CYRIUS_BOUNDS`](issues/2026-10-12-cyriusly-setup-bootstrap-cross-loop-and-env.md);
  - [`cyrius init --help`, `cyrius port --help` and `cyrius sign-efi --help` (and `-h`) fail as unknown flags, while `cyrius --help` promises every command takes `--help`](issues/2026-10-12-init-port-sign-efi-reject-help.md);
  - [`cyrius package` with a missing `[build] entry` prints "package ready: build/<out>" and exits 0 with no artifact; its help row promises an `.ark` it never writes](issues/2026-10-12-package-missing-entry-reports-ready.md);
  - [`cyrius tests` still says it "goes in the next release" three releases after the one it named — when the deprecated alias is removed](issues/2026-10-12-tests-verb-deprecated-alias-removal-decision.md);

**Lanes.**
- Wave 1, both at slot one on hardware:
  - Darwin syscall (`src/`): owns `aarch64/emit.cyr` and `x86/emit.cyr`'s Mach-O syscall region;
  - Windows reroutes (`src/`): owns `pe/emit.cyr`, the PE reroute hunks of `x86/emit.cyr` (a hand-off), the route
    table, `_embed_open` and `lib/io.cyr`.
- Alongside:
  - syscall peers: owns `lib/syscalls_*.cyr` and takes `sys_symlink` and the cwd wrapper as hand-offs;
  - Windows runtime + trust;
  - CLI (`cbt/deps.cyr`, `cbt/manifest.cyr`, the in-process SHA-256).

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
- Slack: what 6.7.8–6.7.12 file. If it does not fit, a further repair release is said at this open, inserted before the
  audit release (which renumbers by one).

- Filed 2026-10-12 (the doc sweep's verifiers, the 6.7.10 refolds):
  - [A declaration after the first top-level statement: `fn` / `const` are taken, `struct` / `enum` / `trait` / `impl` / `union` / `mod` / `use` / `public` / `async fn` are refused, `impl` with a cascade, `async fn` and `union` by a misleading message](issues/2026-10-12-declarations-after-first-statement-decision.md);
  - [cyrius-lsp diagnostics: the column lands in the message, an included file's error lands on the open file, and `.tcyr` / `.bcyr` / `.fcyr` / `.scyr` / `.smcyr` get nothing](issues/2026-10-12-lsp-diagnostics-column-file-and-extensions.md);
  - ["assigning non-pointer to typed pointer" is missing for a declaration-zone `*T` global and for an assignment to a local or parameter `*T` of a scalar `T`](issues/2026-10-12-typed-pointer-non-pointer-warning-gaps.md);
  - [`programs/wc.cyr` (a demo): counts of 8 or more digits run together with no separator, and VT / FF do not separate words](issues/2026-10-12-wc-demo-columns-run-together-and-whitespace-set.md);

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

- Filed 2026-10-12 / 13 (the 6.7.10 lanes and their reviews):
  - [The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line)](issues/2026-10-13-self-compile-prints-large-static-advisory.md);


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

- [`#derive(Serialize)` does not support a `: cstring` field — it is taken for a nested struct (asked by sigil)](issues/archived/2026-10-08-derive-serialize-cstring-fields.md)
- [`lib/math.cyr` has no public length-bounded `f64_parse` — the correctly rounded core is internal (`_f64_parse_n`)](issues/archived/2026-10-08-f64-parse-no-public-length-bounded-form.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](issues/2026-10-08-lib-public-constants-const-migration.md)
- [No stdlib `ppoll` wrapper, and the agnos peer lacks `sys_ioctl` / `sys_fstatat` stubs (asked by yukti)](issues/archived/2026-10-08-no-ppoll-wrapper-and-agnos-ioctl-fstatat-stubs.md)
- [No `sock_set_nodelay`, and Windows `sys_setsockopt` is a -38 stub although net.cyr reaches ws2_32 setsockopt — `TCP_NODELAY` is never set on PE (asked by yantra)](issues/archived/2026-10-08-sock-set-nodelay-windows-route.md)
- [`xflock` has no Windows route (`LockFileEx` not wired) — patra's crash recovery never runs on Windows (asked by patra)](issues/2026-10-08-xflock-windows-lockfileex-not-wired.md)
- [yantra: nine test files include `src/web.cyr` / `src/mobile.cyr` without `src/security.cyr` (undefined-function warnings)](issues/archived/2026-10-08-yantra-tests-miss-security-include.md)
- [sigil has no runtime logging: none of its `src/` files calls sakshi](issues/2026-10-12-sigil-has-no-runtime-logging.md) — unplaced (the user, 2026-10-12: "leave it for later")
- **Adoptions 6.7.9 opened** — prepared 2026-10-11 as fold patches pinned to cyrius 6.7.9, refolded in 6.7.10
  (CHANGELOG [6.7.10], with the sakshi and sigil fixes): yukti → `sys_ppoll`; bayan → `f64_parse_n`; yantra → `sock_set_nodelay`.
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
