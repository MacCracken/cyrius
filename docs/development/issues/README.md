# Cyrius Issues — How to File

Active issue reports live here. Resolved items move to
[`archived/`](./archived/) — don't read archived/ looking for how
to file, read this.

## What belongs here

> ⭐ **This directory IS the backlog** (user, 2026-10-08: "issues that are backlogged should have issue/ filed, not
> sit in the roadmap"). Every backlogged bug, gap or stdlib ask — found by a consumer, a fold, a release lane or a
> closeout — is its own file here with a repro and a `**Placement:**` line. `roadmap.md` names placements and links
> to these files; it never carries an item's text.

- **Consumer-reported bugs** — misleading errors, silent
  truncation, crashes, perf regressions found while porting or
  building a real project against Cyrius.
- **Stdlib surface recommendations** — "we keep re-rolling this
  twelve-line loop, should it be in `lib/*.cyr`?". See
  [`archived/stdlib-math-recommendations-from-abaco.md`](./archived/stdlib-math-recommendations-from-abaco.md)
  for the canonical example of a well-formed recommendation doc.
- **Design-gap reports** — a language or compiler behavior that
  worked around in consumer code with a clear stopgap, where the
  fix belongs in Cyrius.

## What doesn't belong here

- **Feature wishlists without a consumer stopgap.** Speculative
  language extensions go on the watching list in
  `docs/development/roadmap-future.md`, not here. The bar for an issue is: *someone
  is working around this in production code right now.*
- **One-line questions.** If it fits in a chat message, don't
  file it.
- **Upstream tool bugs.** If the bug is in GNU `ld`, `objdump`,
  the kernel, or libc — file it upstream. Cyrius issues are for
  Cyrius-side bugs.

## How to file

Create `docs/development/issues/{short-slug}.md`. Use
kebab-case. Include the consumer name if it's a specific
project (e.g. `bote-cirlf-injection.md`,
`abaco-mulmod-perf-gap.md`). Structure:

```markdown
# {title} — {short status}

**Status:** 🟡 **OPEN** — one line on why it is still open.
**Placement:** the release / arc it is pinned to, or "unpinned — 6.x-line backlog".
**Discovered:** YYYY-MM-DD during {context}
**Severity:** Low / Medium / High / Critical
**Affects:** cycc {version range}

## Summary

One paragraph. What breaks, what the symptom looks like.

## Reproduction

Minimal source, shell commands, expected vs. actual output.
If the repro needs a specific downstream repo, pin the commit.

## Root cause (if known)

File + line number. Speculation OK — flag it as speculation.
The Cyrius agent verifies or corrects.

## Proposed fix

Can be "none — just surfacing" if you don't know the internals
well enough. Don't block on this.

## Consumer-side workaround (if any)

If you've shipped a workaround, document it here so other
consumers can pick it up while waiting for the Cyrius fix.
```

## Severity guide

- **Critical** — silent data corruption, security (CVE-class),
  broken bootstrap, self-hosting regression.
- **High** — hard failure on a shipping consumer's build; no
  workaround available.
- **Medium** — hard failure with a known workaround, or silent
  perf regression > 2×.
- **Low** — misleading error messages, doc mismatches,
  ergonomic papercuts.

## Triage + lifecycle

The Cyrius agent reads new issues on-demand. Expect one of:

1. **Accepted for release X.Y.Z** — scope locked, shows up in
   `docs/development/roadmap.md` and in the target release's
   alpha series.
2. **Accepted, modified** — e.g. the abaco `u64_mulmod` triage
   took the alternative ("fast-path in `u128_mod`") over the
   original recommendation. Reason noted in the issue file.
3. **Declined** — with reason. See the `P3-1` DSP windows entry
   in the abaco triage for the canonical "nice-to-have but not
   stdlib surface" decline shape.

When the fix lands, the issue file:
- Gets a `— RESOLVED` suffix in its top heading.
- Adds a status paragraph pointing at the fix version + the
  CHANGELOG section that closed it.
- Moves to [`archived/`](./archived/).
- Gets a row in `archived/README.md`'s index table.

  > ✅ **RESOLVED 2026-09-05 — option (a), and it was mechanical.** This block read "MAINTAINER
> DECISION OWED" and offered a choice between backfilling and dropping the promise. Neither was a
> decision anyone needed to make: the index is now **complete — all 377 archived files** are listed
> in `archived/README.md` under "Complete file listing", generated from each file's own first
> heading, alongside the curated hand-written briefs which stay as they were.
>
> ⚠ The generated columns are a POINTER, not a verdict: the Title is the file's own heading and the
> Resolved column is the first version string in it, both extracted mechanically. Several archived
> files have been found describing their own status wrongly — the file is the source, and **live
> code beats the file**.
>
> ⛔ The framing is the lesson worth keeping. "Maintainer decision owed" sat here for a minor over
> a task that took one pass to do; there is no maintainer to owe, and a rule left unfollowed is the
> same shape as a half-shipped gate that still reports green.

Filename stays stable across the move so external links keep
working.

## Status + placement lines (required, added at the v6.4.82 sweep)

**Every file in this directory carries a `**Status:**` line and a
`**Placement:**` line in its header block, ideally directly under the
`#` heading.** Before the v6.4.82 closeout sweep only two of eleven
did, which made open-vs-resolved unreadable at a glance and let a
shipped-but-still-framed-as-pending file sit in the queue.

⛔ **Re-run 2026-08-11 (v6.5.19): 3 of 11 open issues FAILED this self-check** — and the two
failing on `Placement` were **both `.20`-pinned filings**, so the next reader of that slot got
no placement line from either. The switch-case filing used a different header dialect entirely
(`**Status** open`, no colon-bold, no `Placement`), making it invisible to this file's own grep.
All fixed; **12 of 12 pass now** (the queue gained one on a restore-from-archive). ⭐ The rule was
also **extended to `../proposals/`**, where all three open files lacked a `**Placement:**` line —
which is precisely how the version-constant proposal lapsed **two** pins with nobody noticing:
its placement lived only in prose.

*(Historical)* Re-verified 2026-08-07 (v6.5.10): **17 of 17 have both.** The two that
did not — `2026-07-30-cx-backend-has-no-indirect-call.md` and
`2026-07-30-net-cyr-x86-only-socket-syscall-numbers.md`, both filed
cyrius-side in the older `**Filed:** / **Reporter:** / **Status:** open`
shape — gained theirs in that sweep. Check with:

```sh
for f in *.md; do [ "$f" = README.md ] && continue
  printf '%-72s %s %s\n' "$f" \
    "$(grep -c '^\*\*Status:\*\*' "$f")" "$(grep -c '^\*\*Placement:\*\*' "$f")"
done            # every row must read "1 1"
```

- `**Status:**` — `🟡 **OPEN** — <why, one line>`, and say **what you
  verified and when**, e.g. *"re-verified against live code at the
  v6.4.82 closeout: `X` still has zero callers."* A status that only
  restates the filing is worthless; a status that names a live check
  is what makes the next sweep cheap.
- `**Placement:**` — the release or arc it is pinned to (`v6.5.x — "IR
  substrate productionization"`), or plainly `unpinned — 6.x-line
  backlog`. Per CLAUDE.md, **every technical / codegen / runtime item
  is an issue file placed in the 6.x line — nothing
  codegen is EVER parked to 7.x** (7.x = the language book + legal).
  Say "never 7.x" so the next reader does not have to re-derive it.

**Open-by-design is a real category.** An accepted filing that is the
acceptance record for a *pinned* arc stays open and un-archived until
the work ships — archiving is how we assert something is done, so
archiving an unbuilt requirement hides it from whoever opens the slot.
Say so in the Status line
(see [`2026-07-25-stiva-stackless-coroutines-interactive-exec.md`](archived/2026-07-25-stiva-stackless-coroutines-interactive-exec.md))
so a later rot sweep does not "clean it up".

## Re-triage rule (the rot sweep)

At every minor/major closeout the whole open queue is re-triaged.
**Verify each item's status against LIVE code — never against the
file's own claim.** Counts, line numbers and "N sites remaining"
figures in a filing go stale silently: the v6.4.82 sweep found one
file claiming 25 residual sites where a live grep said 7, and another
quoting a 27-of-248 test ratio that was really 30 of 251. Re-derive
the numbers, then write the command you used into the file so the next
sweep can re-run it.

**What the 2026-08-07 sweep (v6.5.10, 12 open) found, as the working
examples of each rot shape:**

- **Four files were fully SHIPPED and still framed as open** — all
  closed in the v6.5.7/.8 burst: `fmt-int-buf-i64-min`,
  `no-thread-detach…`, `distlib-has-no-all-profiles-mode`, and the
  already-corrected `coverage-corpus…`. This is the shape the rule
  exists for; four in one minor is the fastest it has ever accumulated.
- **Two files were PARTIALLY shipped** and read as wholly open:
  `agnos-syscall-peer…` (items 2 and 3 landed, item 1 correctly still
  waits on an agnos kernel arm) and `net-cyr-x86-only-socket-syscall-
  numbers` (its predicted collision *fired for real* at v6.5.7 and was
  closed by a mechanism the filing never proposed — the ≥1000
  private-alias band — while the filing's own core stayed open).
- **One file's prose contradicted its own header two screens above:**
  `ir-regalloc-rewrite-needs-reemit` carried a v6.5.2 header saying
  Wall 3 was closed and two later sections still asserting the
  SIGSEGV/hang it closed. **Run the thing rather than reading either.**
- **Line numbers drift even when the finding does not.** Every
  still-open file needed its `file:line` pointers re-derived; the
  findings themselves all survived.

*(Superseded 2026-10-08 — the directory is the whole backlog now, so its size is the backlog's size; the lean-queue
target below is history.)* Keep this directory a lean working queue (~10–12 files). **Derived
2026-08-11 (v6.5.19): 12 open** (plus **3** in `../proposals/`, **316**
in `archived/`) — at the top of the target band. ⚠ The line here
previously read "**12** open … plus 2 … 299 archived" while also
claiming "17 of 17" two paragraphs above: **self-contradictory and wrong
in all three components.** Derive, never quote:

```sh
ls docs/development/issues/*.md | grep -vc README
ls docs/development/proposals/*.md | wc -l
find docs/development/issues/archived -name '*.md' ! -name README.md | wc -l
```

⛔ **The 6.5.19 count went UP by one, and that is correct.**
`2026-06-28-bare-metal-forbidden-module-check-unbuilt.md` was **restored
from `archived/`**, where it had been bulk-renamed on 2026-07-10 with no
resolution banner **for work that was never built**. Archiving is how we
assert something is done, so an unbuilt requirement in `archived/` is
hidden from whoever opens the slot — the exact failure this file warns
about.

## Open queue

Regenerate from the files (title = first heading, group = `**Placement:**`); never hand-count.

**6.7.7 — in this release** (1)

- [A pair-returning call stored into ONE slot keeps only the tag, silently](2026-10-08-pair-call-assigned-to-single-slot-keeps-tag.md)

**Break 2 candidates — the user picks** (15)

- [Inside a native-aarch64 region a raw syscall literal with an ESYSXLAT x86-compat row is translated with no warning](2026-10-08-aarch64-native-region-literal-translated-silently.md)
- [api-surface's line scanner resets its string state at every newline — a multi-line string hides or invents public fns](2026-10-08-api-surface-multiline-string-desync.md)
- [`asm { in al, dx; }` is refused: `in` lexes as keyword 76, so the `ASM_IN` emitter is unreachable by its documented spelling](2026-10-08-asm-in-mnemonic-unreachable.md)
- [`tests/win/async_iocp_pe.cyr` returns 1 at step 2 (`async_with_timeout`) on cass under a plain `cmd /c`](2026-10-08-async-iocp-pe-plain-cmd-c-step2.md)
- [A bare const / enum-constant name as a statement is reported as an assignment (`N;` → "cannot assign to const 'N'")](2026-10-08-bare-const-statement-reported-as-assignment.md)
- [`cyrius deps` / `build` after a pin move, before `lib sync --full`, stamp the new pin over the old pin's lock rows](2026-10-08-deps-before-lib-sync-stamps-new-pin.md)
- [`cyrius deps --verify` fails every file on a CRLF checkout of a committed `lib/` (`core.autocrlf=true`)](2026-10-08-deps-verify-crlf-checkout-mismatch.md)
- [`[embed]` / `${file:}` link race on Windows and Apple Silicon (the E-S3 residual)](2026-10-08-embed-open-link-race-pe-macos-arm64.md)
- [Generic inference does not see through a generic struct parameter (`gx(b)` for `b: Box<T>`)](2026-10-08-generic-inference-through-generic-struct-param.md)
- [In an x86 `kernel;` build a float-literal global scalar is a dead store after the program](2026-10-08-kernel-float-global-init-not-baked.md)
- [A killed `cyrius` run leaves a NON-EMPTY `cyrius-<pid>` temp dir that nothing reaps](2026-10-08-killed-cli-leaves-nonempty-tmp-dirs.md)
- [`#pure`'s `#io` / `#alloc` check is silent for a callee defined later](2026-10-08-pure-check-misses-later-defined-callee.md)
- [A redeclared global read inside its own `bool` redeclaration reads as boolean (`var G = 5; var G: bool = G;` exits 5)](2026-10-08-redeclared-global-bool-reads-own-stamp.md)
- [Native TLS conformance, as one bite: six handshake checks that are missing, loose or untested](2026-10-08-tls-native-conformance-bite.md)
- [Windows native-TLS trust store: four gaps against the Windows chain engine (CYRIUS-2026-0020's *Not covered*)](2026-10-08-windows-trust-store-parity-gaps.md)

**Asked by the folds / fold bugs** (7)

- [`#derive(Serialize)` does not support a `: cstring` field — it is taken for a nested struct (asked by sigil)](2026-10-08-derive-serialize-cstring-fields.md)
- [`lib/math.cyr` has no public length-bounded `f64_parse` — the correctly rounded core is internal (`_f64_parse_n`)](2026-10-08-f64-parse-no-public-length-bounded-form.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](2026-10-08-lib-public-constants-const-migration.md)
- [No stdlib `ppoll` wrapper, and the agnos peer lacks `sys_ioctl` / `sys_fstatat` stubs (asked by yukti)](2026-10-08-no-ppoll-wrapper-and-agnos-ioctl-fstatat-stubs.md)
- [No `sock_set_nodelay`, and Windows `sys_setsockopt` is a -38 stub although net.cyr reaches ws2_32 setsockopt — `TCP_NODELAY` is never set on PE (asked by yantra)](2026-10-08-sock-set-nodelay-windows-route.md)
- [`xflock` has no Windows route (`LockFileEx` not wired) — patra's crash recovery never runs on Windows (asked by patra)](2026-10-08-xflock-windows-lockfileex-not-wired.md)
- [yantra: nine test files include `src/web.cyr` / `src/mobile.cyr` without `src/security.cyr` (undefined-function warnings)](2026-10-08-yantra-tests-miss-security-include.md)

**Unplaced — 6.x-line backlog** (45)

- [arm64-macOS: a folded literal syscall still carries the pipe / fork post-`svc` fixups (64 B a site, XLAT-3)](2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md)
- [The lexer's `#`-attribute word list is hand-copied into six tools; five are held to `LEXATTRWORD` by no census](2026-10-08-attribute-word-list-hand-kept-in-five-tools.md)
- [Bare `cyrius bench` / `cyrius fuzz` exit 0 when they find nothing to run](2026-10-08-bench-fuzz-exit-zero-on-empty-corpus.md)
- [`scripts/ci.sh` never links `$CYRIUS_HOME/lib` on a fresh home](2026-10-08-ci-sh-fresh-home-links-no-lib.md)
- [CLI leftovers from the 6.7.6 review — path resolution (Windows, symlinked cwd, git ceiling), error counts, `lib sync --dry-run`, `update`, the lock under wine](2026-10-08-cli-path-and-reporting-leftovers.md)
- [A field access in a const fn, or on a const, is refused with a message that names the wrong thing](2026-10-08-const-field-access-diagnostics-misname-refusal.md)
- [A top-level `var X = CONST;` is baked AND stored at run time; `2 * CONST` is not folded](2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md)
- [A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10)](2026-10-08-constant-if-arms-not-folded.md)
- [cx: a fn returning a 16-byte struct is refused ("int-class 16B struct pair-return ABI not supported")](2026-10-08-cx-16b-struct-return-refused.md)
- [cybs reports a bare "syntax error" (or "undefined variable") with no file, line or construct](2026-10-08-cybs-bare-syntax-error-no-location.md)
- [cybs compiles a statement-position call to an undefined function silently; the binary segfaults](2026-10-08-cybs-undefined-fn-call-in-statement-silent.md)
- [`cyrius init` prints "Created <x>/" and exits 0 when its templates are missing](2026-10-08-cyrius-init-exits-zero-with-missing-templates.md)
- [cyrlint has neither of its two planned checks: a bare-local-array overrun and a write-length / literal mismatch](2026-10-08-cyrlint-array-overrun-and-write-length-checks.md)
- [`*p = v` through `p: *f32` / `*i32` is a raw 8-byte word store (documented design gap)](2026-10-08-deref-store-through-narrow-typed-pointer-is-word-store.md)
- [Diagnostic cascades: duplicate const-fn scope errors, three errors from one unclosed call, a for-step call's "undefined function", and `error:0:1:` at EOF](2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md)
- [`cyrius distlib`: the every-target owner rule and the partial-target rule still disagree on ties and on in-unit declarers](2026-10-08-distlib-every-target-owner-rule-differs-from-partial.md)
- [`esysxlat_fold.sh` passes a fold that never updates `cur` (mutation (c) is not caught)](2026-10-08-esysxlat-fold-gate-blind-to-cur-update.md)
- [`gp().n = 5` through a `*T`-returning call is refused as "the result is a temporary"](2026-10-08-field-store-through-pointer-returning-call-refused.md)
- [A variable or subscript classic-`for` step never checks its `)`](2026-10-08-for-step-variable-subscript-close-paren-unchecked.md)
- [`fhm_set` on a PRESENT key can rebuild (and double) the table — `lib/hashmap.cyr` stopped doing that at 6.6.20](2026-10-08-hashmap-fast-overwrite-rebuilds-table.md)
- [A call through a variable or closure that returns f64 gives an untyped word (documented design gap)](2026-10-08-indirect-call-f64-result-untyped.md)
- [One integer + f64 mix warns twice when the expression continues (`x = x + (x + 1.5)`)](2026-10-08-int-f64-mix-warns-twice-in-a-chain.md)
- [The IR heap family is six fixed `S + 0x…` bands with fixed caps — one `alloc()` arena (HEAP-12)](2026-10-08-ir-heap-bands-fixed-offsets-and-caps.md)
- [`CYRIUS_IR=3` drops unrecorded field-access bytes: signed narrow fields read garbage, a field read after a dead store reads the wrong slot](2026-10-08-ir3-drops-unrecorded-field-emits.md)
- [Literal bounds left in `lib/`: hand-kept 1024 / 64 / 40 copies, two arrays 8× their stated size, and loops bounded by writable public vars](2026-10-08-lib-literal-bounds-and-writable-public-bounds.md)
- [A fn whose body ends in `loop { … }` / `do … while` / `while (1)` is not "provably one value"](2026-10-08-loop-ending-fn-not-provably-single-return.md)
- [The x86-macOS peer `lib/syscalls_macos.cyr` declares `SYS_ACCEPT4 = 288`, which no macOS path emits](2026-10-08-macos-peer-declares-unused-sys-accept4.md)
- [`cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read](2026-10-08-manifest-build-profiles-and-target-unread.md)
- [Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1](2026-10-08-native-tls-capability-limits.md)
- [A parenthesised argument to a ≤ 8 B by-value struct parameter skips the struct type check](2026-10-08-paren-arg-small-byval-struct-skips-type-check.md)
- [Every PE build that includes `lib/syscalls.cyr` warns "syscall 12 … is not routed" (Windows `sys_brk`)](2026-10-08-pe-sys-brk-unrouted-syscall-warning.md)
- [`cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible](2026-10-08-poison-guard-pages-unbuilt.md)
- [The x86_64 release tarball ships without `cyrius-repl.sh` (release.yml looks only in `scripts/`, not `scripts/shims/`)](2026-10-08-release-tarball-misses-shim-scripts.md)
- [The seed (`bootstrap/asm`) truncates input at 131,072 B, overruns its 512-label table and its 65,536 B CODE buffer — all unchecked](2026-10-08-seed-asm-silent-caps-input-labels-code.md)
- [self_compile pays ~4 % for the preprocessor's per-byte `PP_LEXST_AT` call layer (the 6.6.20 attribute-line rule)](2026-10-08-self-compile-attribute-line-rule-cost.md)
- [An 8-byte struct local initialised from an address is a VALUE holding the address, not a handle](2026-10-08-small-struct-local-from-address-is-value-not-handle.md)
- [A struct-typed FIELD as an operator's LEFT operand never dispatches](2026-10-08-struct-field-left-operand-never-dispatches.md)
- [Struct-operator results: six typing / return-shape defects around struct operands](2026-10-08-struct-operator-results.md)
- [`--syntax-only` invents "expected '=', got '.'" for `a.f.g` when `f: *Foo` and `Foo` is in another file](2026-10-08-syntax-only-chained-field-through-unresolved-pointee.md)
- [`tls_native_set_client_cert` sizes its PEM decode at `TLS_CA_MAX_ROOTS` (300), not from the input](2026-10-08-tls-client-cert-pem-decode-sized-at-ca-max-roots.md)
- [TOKNAME has no name for 23 operator / literal tokens — "expected '=', got unknown"](2026-10-08-tokname-operator-tokens-unnamed.md)
- [u128 beyond `+` / `-` / comparisons: parameters, returns, struct fields and closure captures](2026-10-08-u128-params-returns-fields-captures.md)
- [Windows `sys_symlink` widens at 519 units with no `\\?\` prefix: a path over 260 units fails -1](2026-10-08-windows-symlink-no-long-path-prefix.md)
- [`gates_never_write_tree.sh` axis 9 cannot see a PE binary run directly through binfmt_misc](2026-10-08-wine-prefix-scan-misses-binfmt-pe-run.md)
- [x86-macOS: every `syscall()` site still inlines the whole `EMACHO_SYSXLAT` chain (~1.26 KB, 35 % of the compiler)](2026-10-08-x86-macos-emacho-sysxlat-not-folded.md)

## Recommended security floor

When filing a consumer bug, report the Cyrius version you're on
AND the recommended minimum you'd need for the fix to deploy.
The current recommended floor is **v5.0.0** (cycc IR, cyrius.cyml
manifest); v5.0.1+ adds the alloc/vec overflow-guard hardening and
v5.1.0+ adds macOS Mach-O support (per CLAUDE.md's DO-NOT block).

## Pointers

- [`archived/`](./archived/) — resolved issues, indexed.
- [`../roadmap.md`](../roadmap.md) — the active minor's plan and the unscheduled backlog.
- [`../state.md`](../state.md) — current cycle state (version, cycc size, in-flight slots).
- `../../../CHANGELOG.md` — source of truth for what each release
  actually shipped.
