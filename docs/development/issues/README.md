# Cyrius Issues — How to File

Active issue reports live here. Resolved items move to
[`archived/`](./archived/) — don't read archived/ looking for how
to file, read this.

## What belongs here

> ⭐ **This directory IS the backlog** (user, 2026-10-08: "issues that are backlogged should have issue/ filed, not
> sit in the roadmap"). Every backlogged bug, gap or stdlib ask — found by a consumer, a fold, a release lane or a
> closeout — is its own file here with a repro and a `**Placement:**` line. `roadmap.md` names placements and links
> to these files; it never carries an item's text. ⚡ **A find that can be repaired faster than this file could be
> written is repaired when found instead** (user, 2026-10-09) — its own commit and regression row; file only what
> cannot be done that fast.

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

Regenerate from the files (title = first heading, group = `**Placement:**`); never hand-count. The
release plan is roadmap.md § *Release sequence* (placed 2026-10-09).

**6.7.9 — repair batch: the quick fixes + the critical / high (user, 2026-10-11)** (0)


**6.7.10 — features: B7 + P5-B** (0)


**6.7.11 — Break 2, repair 1** (0)


**6.7.12 — Break 2, repair 2: the platform release** (0)


**6.7.13 — Break 2, repair 3: struct values** (0)


**6.7.14 — Break 2, repair 4: generics, the frontend, infra (added at the 6.7.12 open, 2026-10-15)** (0)


**6.7.15 — Break 2, repair 5 (added at the 6.7.13 integration, 2026-10-16)** (0)


**6.7.16 — Break 2, repair 6 (added at the 6.7.15 wave-1 integration, 2026-10-18): what 6.7.15 files** (0)


**6.7.17 — the full security audit + the refactor / optimization review** (2)

- [A tail call that copies a by-value struct argument is an ordinary call — a per-fn "writes no memory" analysis would win its `jmp` back](2026-10-09-tail-call-by-value-copy-needs-effect-analysis.md)
- [The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line)](2026-10-13-self-compile-prints-large-static-advisory.md)

**Open by design — placed arcs, not bugs** (6)

- [A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10)](2026-10-08-constant-if-arms-not-folded.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](2026-10-08-lib-public-constants-const-migration.md)
- [`cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read](2026-10-08-manifest-build-profiles-and-target-unread.md)
- [Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1](2026-10-08-native-tls-capability-limits.md)
- [`cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible](2026-10-08-poison-guard-pages-unbuilt.md)
- [The TypeScript front end is measured against one project's files (secureyeoman's corpus), not the language — it needs true, in-tree language support](2026-10-19-typescript-support-measured-against-one-projects-files.md)

**Unplaced** (23)

- [The seed (`bootstrap/asm`) truncates input at 131,072 B, overruns its 512-label table and its 65,536 B CODE buffer — all unchecked](2026-10-08-seed-asm-silent-caps-input-labels-code.md)
- [sigil (the crypto / trust fold) has no runtime logging: none of its 68 `src/` files calls sakshi](2026-10-12-sigil-has-no-runtime-logging.md)
- [cybs names neither the construct it refused nor the file and line](2026-10-13-cybs-per-construct-refusal-and-file-line.md)
- [The developer and release helpers moved into `scripts/` (Python and shell) are converted to cyrius — sovereignty, long term](2026-10-19-dev-helper-scripts-converted-to-cyrius.md)
- [A declaration-zone initializer's error is printed after a LATER line's pass-1 refusal (`var p = g(1 2);` then `const X;` prints 3:8 before 2:13)](2026-10-20-zone-replay-error-printed-after-later-pass-one-refusal.md)
- [The 6.7.16 changes beyond the decisions' text — keep or restore each](2026-10-21-6716-behaviour-changes-beyond-the-decisions-text.md)
- [Diagnostics print the compiler's internal position or name: columns past an in-line expansion are the expanded line's, an undefined name's caret sits on the token after it, and a generic instance is named by its mangled table name (`B$i32`)](2026-10-21-diagnostics-print-internal-columns-carets-and-mangled-names.md)
- [Top-level directive lines read less than their line: `#assert`'s and `include`'s tails are skipped unread (silently dropping code), `use` takes no module path, and a `private` line after the first statement swallows the next error](2026-10-21-directive-line-tails-unread-use-without-path-late-private.md)
- [A `*fn( .. )` type outside a parameter: a local, a global or a field is refused as a reserved-keyword identifier with a cascade, and a trait member's multi-value element compiles where a fn's is refused](2026-10-21-fn-pointer-type-outside-a-parameter.md)
- [Generic parameter and type-argument lists are judged by position: a parameter list takes any token, a trait member's bound is unchecked, `union U<T>` is refused only by pass 2, a type parameter's own `<..>` is unread (a parse error as a return), and an explicit call is "undefined function" under `CYRIUS_MONOMORPH=0`](2026-10-21-generic-parameter-and-type-argument-lists-judged-by-position.md)
- [A generic call's `x: T` argument that is a struct-typed FIELD or a struct-returning METHOD call binds `T = i64`: `sizeof(T)` is 8 for a 16-byte struct, and `.b` on the value is refused](2026-10-21-generic-struct-field-or-method-argument-binds-t-i64.md)
- [A generic's T-typed parameter name rebound by a closure parameter, a `for x in` variable or a destructure is still read as T: a bounded `x.show()` on it calls the bound's impl on the word (SIGSEGV at T = Pt), and `x.b` makes the generic a stub](2026-10-21-generic-tparam-name-rebound-by-closure-param-forin-destructure-read-as-t-sigsegv.md)
- [A struct, enum or trait declared inside a body pass 2 never parses — a trait default no impl inherits, an uninstantiated bounded generic — is never refused](2026-10-21-inner-declaration-in-a-body-pass-two-never-parses-never-refused.md)
- [Windows answers beyond D79 / D94 / D95: a rename of a directory onto an existing file replaces the file (Linux -20, the file kept), a rename of a file onto a directory answers -13 (Linux -21), and `xflock` answers -1 for a closed or negative fd (Linux -9)](2026-10-21-pe-rename-onto-other-kind-and-xflock-answers-beyond-d79-d94-d95.md)
- [One mistake, more errors or the wrong one: an explicit generic call whose type-argument list is refused cascades into the receive / argument checks, a declaration whose initializer is refused leaves its name untyped, and an untypable chain's destructure says "needs a call"](2026-10-21-refused-source-cascades-or-names-the-wrong-error.md)
- [A `: stack`-pair fn called through `callptr(&f, ..)` / `fncallN(&f, ..)` with a known `&f` is no pair: `?` takes the boxed lowering (SIGSEGV) and a one-wide bind keeps the tag in silence](2026-10-21-stack-pair-fn-through-callptr-or-fncall-is-no-pair.md)
- [A statement missing its `;` before a `}` or a statement keyword loses what follows: the next fn is "defined inside" the last, and later statements' own errors are never reported](2026-10-21-statement-missing-semicolon-loses-what-follows.md)
- [`Str` shapes beyond D19 / D20 / D71 / D73: a struct result assigned into a `Str` handle (SIGSEGV), a nested literal's `*Str`-sourced leaf, a captured inline `Str`'s `*(&t) = v`, a `Str` field's named init, and a top-level untyped `str_from`](2026-10-21-str-shapes-beyond-d19-d20-d71-d73.md)
- [Struct and pointer shapes beyond D97 / D99 take a word or another struct's bytes in silence: a pointer of another struct or another depth at a call or a declaration, and a struct value stored through an untyped pointer, into a `*Q` slot, into a scalar field or element, by a compound assignment, or into a `*P` declaration](2026-10-21-struct-and-pointer-shapes-beyond-d97-d99-take-a-word.md)
- [A suspending `async fn`'s narrow parameter holds the caller's word — D72 narrows every other parameter](2026-10-21-suspending-async-fn-narrow-parameter-holds-caller-word.md)
- [The native TLS 1.3 server checks each key_share against supported_groups by a linear scan — one 16 KB ClientHello costs ~24 ms of server CPU, quadratic in peer-chosen counts (CYRIUS-2026-0037)](2026-10-21-tls13-server-key-share-scan-quadratic-in-peer-count.md)
- [A value builtin as a bare statement: `load8(p);` compiles while `load16(p);` / `load32(p);` / `load64(p);` / `f32_from(x);` / `f32_to(x);` are "unexpected load16"](2026-10-21-value-builtin-statement-load8-compiles-load16-unexpected.md)
- [A vector value in a word position beyond D100 / D101: a store through a `*V` writes one word, a vector LOCAL read as a word is its lane 0, and a multi-value fn's vector element is read as one word](2026-10-21-vector-value-in-a-word-position-beyond-d100-d101.md)

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
