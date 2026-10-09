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

**Current head: v6.7.6** (2026-10-08) — Break 1 shipped · cycc **1,806,240 B** · `.text` **1,612,016** · `cycc-native-aarch64` **1,601,032 B** · **537** `.tcyr`, **243** in `crossos/` · **106** `lib/*.cyr` · **441** shell gates under `tests/gates/<bucket>/` · api-surface **5,828** · **73** open issues · **1** open proposal · next ledger id **CYRIUS-2026-0036**

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
2. **Catch-up breaks clear the backlog.** Break 1 was 6.7.6. Break 2 comes after the remaining features, before the
   closeout; the user picks its items.
3. **Every language decision is the user's** — asked at the arc's start, recorded with its date, never a lane's
   "default" (CLAUDE.md *Execution integrity*).
4. **Every new syntax ships with** a `tests/tcyr/crossos/` file (it runs on ecb / ach / cass / pi), a guide section and a
   vidya entry.

## Release sequence

| Release | Content |
|---|---|
| 6.7.0 – 6.7.6 | ✅ shipped — A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` on every lvalue · the W2 stdlib wave + Break 1 |
| 6.7.7 | **B4** tuples + **B6** default and named arguments (decisions below, user 2026-10-08) · the fixes: [`cyrius distlib`'s order-dependent owner](issues/2026-10-08-distlib-owner-first-declarer-credits-fold-monolith.md) · [the ach-timing terminate-children test](issues/2026-10-08-crossos-terminate-children-timing-on-ach.md) · [the silent `x += 1.5`](issues/2026-10-08-compound-assign-f64-rhs-on-int-slot-silent.md) · [install.sh's init templates](issues/2026-10-08-install-sh-source-bootstrap-no-init-templates.md) · [`ci.sh` and a real release tarball](issues/2026-10-08-ci-sh-cannot-install-release-tarball.md) · [the pair-into-one-slot stores (with B4)](issues/2026-10-08-pair-call-assigned-to-single-slot-keeps-tag.md) |
| 6.7.8 → | the remaining features, decisions asked at each start: **B7** narrow struct fields (layout decided below) · **C2** the bounds-checked mode (+ P5 execution coverage) · **checked `dyn`** |
| Break 2 | catch-up — the user picks from the candidates below |
| closeout | the closeout checklist ([cycle-discipline.md](cycle-discipline.md)) — the checklist, not an audit campaign |

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

## Break 2 — candidates (the user picks)

Premise-checked at the 6.7.6 open and again when each was filed as an issue (2026-10-08). Each file carries the
repro, the root cause and the proposed fix; a fix that changes what compiles says so. Also for the user: the ptrace
native-declaration decision ([roadmap_6.md](roadmap_6.md) § *syscall families*) and the live-store restore
([state.md](state.md) *Open decisions*).

- [Inside a native-aarch64 region a raw syscall literal with an ESYSXLAT x86-compat row is translated with no warning](issues/2026-10-08-aarch64-native-region-literal-translated-silently.md)
- [api-surface's line scanner resets its string state at every newline — a multi-line string hides or invents public fns](issues/2026-10-08-api-surface-multiline-string-desync.md)
- [`asm { in al, dx; }` is refused: `in` lexes as keyword 76, so the `ASM_IN` emitter is unreachable by its documented spelling](issues/2026-10-08-asm-in-mnemonic-unreachable.md)
- [`tests/win/async_iocp_pe.cyr` returns 1 at step 2 (`async_with_timeout`) on cass under a plain `cmd /c`](issues/2026-10-08-async-iocp-pe-plain-cmd-c-step2.md)
- [A bare const / enum-constant name as a statement is reported as an assignment (`N;` → "cannot assign to const 'N'")](issues/2026-10-08-bare-const-statement-reported-as-assignment.md)
- [`cyrius deps` / `build` after a pin move, before `lib sync --full`, stamp the new pin over the old pin's lock rows](issues/2026-10-08-deps-before-lib-sync-stamps-new-pin.md)
- [`cyrius deps --verify` fails every file on a CRLF checkout of a committed `lib/` (`core.autocrlf=true`)](issues/2026-10-08-deps-verify-crlf-checkout-mismatch.md)
- [`[embed]` / `${file:}` link race on Windows and Apple Silicon (the E-S3 residual)](issues/2026-10-08-embed-open-link-race-pe-macos-arm64.md)
- [Generic inference does not see through a generic struct parameter (`gx(b)` for `b: Box<T>`)](issues/2026-10-08-generic-inference-through-generic-struct-param.md)
- [In an x86 `kernel;` build a float-literal global scalar is a dead store after the program](issues/2026-10-08-kernel-float-global-init-not-baked.md)
- [A killed `cyrius` run leaves a NON-EMPTY `cyrius-<pid>` temp dir that nothing reaps](issues/2026-10-08-killed-cli-leaves-nonempty-tmp-dirs.md)
- [`#pure`'s `#io` / `#alloc` check is silent for a callee defined later](issues/2026-10-08-pure-check-misses-later-defined-callee.md)
- [A redeclared global read inside its own `bool` redeclaration reads as boolean (`var G = 5; var G: bool = G;` exits 5)](issues/2026-10-08-redeclared-global-bool-reads-own-stamp.md)
- [Native TLS conformance, as one bite: six handshake checks that are missing, loose or untested](issues/2026-10-08-tls-native-conformance-bite.md)
- [Windows native-TLS trust store: four gaps against the Windows chain engine (CYRIUS-2026-0020's *Not covered*)](issues/2026-10-08-windows-trust-store-parity-gaps.md)

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
