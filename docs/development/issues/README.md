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


**6.7.13 — Break 2, repair 3: struct values** (75)

- [`gp().n = 5` through a `*T`-returning call is refused as "the result is a temporary"](2026-10-08-field-store-through-pointer-returning-call-refused.md)
- [An inline `Str` (from a `Str { .. }` literal) used as a `Str` value passes its `data` word, not a handle: `f(t)` with `fn f(s: Str)` reads the wrong length, silently](2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md)
- ["assigning non-pointer to typed pointer" is missing for a declaration-zone `*T` global and for an assignment to a local or parameter `*T` of a scalar `T`](2026-10-12-typed-pointer-non-pointer-warning-gaps.md)
- [A fn declared `: (T1, T2[, T3])` that can fall off its end hands the caller stale registers](2026-10-13-declared-multi-value-fn-falls-off-its-end.md)
- [`var a, b = callptr(fp, 5);` is refused "multi-value destructure needs a call on the right-hand side", where `fncall1(fp, 5)` destructures](2026-10-13-destructure-of-callptr-refused.md)
- [`*pp` of a `pp: **T` is an untyped word, not a `*T`: `*pp + 1` steps one BYTE, and `var q: *T = *pp;` warns "assigning non-pointer to typed pointer"](2026-10-13-double-pointer-dereference-is-an-untyped-word.md)
- [`fncall1(&mk3, 5).b` — a field of a struct result through fncallN / callptr is a parse error, where `mk3(5).b` works](2026-10-13-field-of-indirect-call-struct-result.md)
- [`ret2(a, b)` in a fn declared `: (i64, i64, i64)` leaves the third value stale](2026-10-13-ret2-in-three-value-fn-leaves-third-register-stale.md)
- [A call DECLARED to return a vector that the vector receive / return still do not take: a method call, an untyped `var v = callptr(&f, ..)`, `return callptr(&f, ..)`](2026-10-13-vector-call-results-the-receives-do-not-take.md)
- [`var v: f64v2 = *p;` / `v = *p;` with `p: *f64v2` — refused since 6.7.11 (it stored one word); copy the vector through the pointer, as a struct's `*p` is?](2026-10-13-vector-dereference-into-vector-local-decision.md)
- [A fn ending in `while (true) { .. }` / `do { .. } while (true);` is not proved to return one value](2026-10-13-while-true-ending-fn-not-provably-single-return.md)
- [`&x.f` — the address of a struct field — does not parse (`expected ')', got '.'`), while the guide cites `load64(&s.f)` and `&h.f` as expressions — OPEN (a decision)](2026-10-14-address-of-field-does-not-parse-guide-cites-it.md)
- [An undeclared `async fn` that says `return h();` of a multi-value call still drops the second value](2026-10-14-async-fn-forwarding-multi-value-call-loses-second-value.md)
- [A bare `Vec` struct field's size depends on whether a `struct Vec` is declared above or below the struct that uses it — the same text gives two layouts (the 6.6.10 order-dependent-layout class)](2026-10-14-bare-vec-field-layout-depends-on-declaration-order.md)
- [The captured-name refusal's fix-it reads `var y = y;` when the captured name is `y`](2026-10-14-captured-name-refusal-fixit-reads-var-y-equals-y.md)
- [A closure's capture of a narrow scalar local (`i8` .. `i32`, `u8` .. `u32`) reads the slot's whole 8-byte word: a negative value is zero-extended, and stale upper bytes come along](2026-10-14-closure-capture-of-narrow-local-reads-unextended-word.md)
- [In a closure, `var a = a + n;` (and a destructure's FIRST name, `var a, b = f(a);`) reads a global `a`, or is refused "undefined variable", where the enclosing local `a` is meant](2026-10-14-closure-var-initializer-reading-its-own-name-drops-the-capture.md)
- [A struct dereference as an IF-EXPRESSION BRANCH is typed an integer: `var v: S = if (c) { *p } else { *q };` binds `v` as a handle holding the word `*p` read (SIGSEGV at every size), and `if (c) { *p } else { s }` is refused as "branches differ in type"](2026-10-14-dereference-as-if-expression-branch.md)
- [A dereference of a `*S` as a tuple literal's element stores the struct's first word, where a struct value element is refused by name](2026-10-14-dereference-as-tuple-element-stores-first-word.md)
- [`*(&p)` of a struct over 8 B — as an argument for a by-value struct parameter or a declaration's initialiser — reads its first word as the struct's address: SIGSEGV](2026-10-14-dereference-of-address-of-struct-faults.md)
- [The `#derive` scanner `T_from_json_str` does not walk a SCALAR field's object or array value: its inner keys are read as the outer struct's](2026-10-14-derive-scanner-scalar-field-holding-object-derails-scan.md)
- [A `dyn Tr` result through a known callee (`var a: dyn Shape = fncall1(&mkd, &q);`) is refused, where `mkd(&q)` forms the dyn](2026-10-14-dyn-result-through-known-callee-refused.md)
- [An explicit-instance generic call returning a vector (`mkg<i64>(41, 7)`) is not received by a value-form vector local](2026-10-14-explicit-instance-vector-result-not-received.md)
- [An untyped `var c = f() < 1.0;` with a `: f64` leading call is typed f64 — `-c` flips the sign bit](2026-10-14-f64-leading-call-types-comparison-binding-f64.md)
- [A fn that calls an inline-replayed `: stack` pair generic is flagged pair-returning ITSELF: a false "bind both" at its callers and a false mixed-return warning](2026-10-14-inline-replayed-pair-return-flags-the-caller.md)
- [An integer comparison or bitwise operator with an f64 right operand leaves its result typed f64](2026-10-14-integer-comparison-result-keeps-f64-right-operand-type.md)
- [`*p = f()` with `f` a multi-value fn and `p: *S` stores the FIRST value as the struct's word, where `G = f()` into a struct is refused by name — OPEN (a decision)](2026-10-14-multi-value-call-stored-through-struct-pointer-decision.md)
- [A nested closure's parameter named like an enclosing local is taken as a capture by the closure around it — refused without lib/alloc.cyr, or a needless heap env](2026-10-14-nested-closure-parameter-taken-as-outer-capture.md)
- [A `: stack` pair-returning trait DEFAULT method used above its trait / impl is not a pair: `p.m(d)?` SIGSEGVs, `var v = p.m(d);` binds the tag](2026-10-14-pair-trait-default-method-used-above-its-trait-not-flagged.md)
- [`var x = (mk1());` (an 8 B struct) and `var x = (b.mk());` (a 9–16 B method) still infer nothing — the method's first word crashes through a by-value parameter](2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md)
- [A parenthesised dyn-returning call as a struct literal's `dyn` element is refused with two reports, where the unwrapped call and every other dyn destination take it](2026-10-14-paren-wrapped-dyn-call-as-dyn-literal-element-refused.md)
- [A parenthesised 9-16 B method or operator result as a nested-struct literal element is refused ("unexpected '}'")](2026-10-14-paren-wrapped-pair-method-or-operator-as-nested-literal-element-refused.md)
- [A parenthesised `: stack` pair call escapes every pair check: `var v = (f(7));`, `x = (f(7));`, `h.a = (f(7));`, `P { (f(7)), 3 }` keep the tag silently, and `var v = (f(7))?;` takes the boxed `?` and SIGSEGVs](2026-10-14-paren-wrapped-stack-pair-call-escapes-every-pair-check.md)
- [A parenthesised `&f` callee (`callptr((&mk3), 5)`, `fncall1((&mk2), 5)`) is an unknown callee: its struct / vector result convention is lost — SIGSEGV](2026-10-14-parenthesised-fn-pointer-callee-loses-struct-result.md)
- [A pointer-annotated local from a by-value struct call: `var x: *P2 = mkp();` (16 B) compiles with only a warning and SIGSEGVs at `x.b`; `var x: *i64 = mkp();` holds the first word](2026-10-14-pointer-annotated-local-from-byvalue-struct-call.md)
- [A local `const k: i64 = 3;` is refused, and every later read of `k` adds "undefined variable 'k'"](2026-10-14-refused-local-const-annotation-cascades-undefined-variable.md)
- [A refused parameter default drops every default of its fn — each call that relies on one is refused again](2026-10-14-refused-parameter-default-refuses-every-short-call.md)
- [`ret2(a, b)` in a fn returning a struct over 16 B or of 8 B or less takes the multi-value path](2026-10-14-ret2-in-struct-returning-fn-takes-multi-value-path.md)
- [`return &s;` in a fn returning the struct `S`: at 8 B or less the ADDRESS is the struct's word; over 8 B it is refused in other words — OPEN (a decision)](2026-10-14-return-address-of-struct-local-decision.md)
- [`var x: i64 = b.mk();` / `var y: u8 = a + b;` take a struct METHOD's or OPERATOR's first word, narrowed, where the free-call form is refused since 6.7.11 — OPEN (a decision)](2026-10-14-scalar-annotation-from-struct-method-or-operator-keeps-first-word.md)
- [A sync fn declared one value (`fn g2(): i64 { return (1, 2); }`) compiles clean and the caller silently gets the first value](2026-10-14-scalar-declared-fn-returning-multi-value-literal.md)
- [A by-value `self` from a `*S` receiver, and a `*S` into a by-value `S` parameter, of a 3 / 5 / 6 / 7-byte struct carry FRAME GARBAGE in the word's padding (`_hl_pval_ra`'s temp is not zeroed)](2026-10-14-small-struct-byvalue-word-padding-from-frame.md)
- [A whole struct-typed FIELD of 3, 5, 6 or 7 bytes used as a value — `take(w.s)`, `return w.s`, `w.s + a`, a top-level `var G: S3 = GW.s;` — is loaded as an 8-byte word: it reads past the object (SIGSEGV when it ends a mapping)](2026-10-14-small-struct-field-value-reads-past-the-object.md)
- [A fn declared `: P1` (a struct of 8 B or less) that says `return mk(..);` of a multi-value call returns its first value as the struct](2026-10-14-small-struct-fn-returns-multi-value-call.md)
- [struct_value_codegen.sh's A rows (struct_value_codegen.tcyr) carry no row-count floor — a gutted values file passes](2026-10-14-struct-value-codegen-a-rows-no-floor.md)
- [A top-level `ret2(a, b)` compiles with no diagnostic and does not return: x86_64 / PE run on past it, aarch64 / cx hang at it](2026-10-14-top-level-ret2-never-returns.md)
- [An undeclared multi-value call (`return (a, b)`, counted by pass 1) passed to a TUPLE parameter is taken as its address](2026-10-14-undeclared-multi-value-call-into-tuple-parameter-crashes.md)
- [`*p = v` with an untyped value into a struct over 8 bytes writes only the first 8 bytes — confirm the reading of decision D4 (a)'s "at sizeof(S) bytes" — OPEN (a decision to confirm)](2026-10-14-untyped-store-through-struct-pointer-over-8-bytes-reading.md)
- [The value-form vector local refusal prints its fn-pointer hint for every source, and now reports an undefined function as a refused source](2026-10-14-vector-local-refusal-hint-every-source.md)
- [A zero-size struct value into a struct-typed FIELD (`o.s = GP`, `o.s = gp()`, `o.s = (GP)`, `o.s = mk()`) or a zero-size `*p` used as a value still moves an 8-byte word: the field's neighbour is clobbered, and `take(*p)` reads 8 bytes past the object](2026-10-14-zero-size-struct-into-field-or-dereference-value-moves-a-word.md)
- [6.7.12 changes that stop existing programs compiling (or change what they do) beyond the decisions' text — confirm each, or restore it](2026-10-15-6712-behaviour-changes-beyond-the-decisions-text.md)
- [On an aarch64 Linux host, `cyrius build --win` writes an aarch64 ELF named `.exe` at rc 0, and `--aarch64` / `--target=aarch64-bare-metal-elf` fail looking for the x86_64-hosted `cycc_aarch64`](2026-10-15-aarch64-linux-cli-win-writes-aarch64-elf-and-aarch64-selectors-need-cross-compiler.md)
- [`cyrius distlib` records a named dep's need as the bundle's own when `cyrius deps` kept the fold over that dep's thin profile: bote-core's sidecar gets `sigil` + `ct`](2026-10-15-bote-distlib-kept-fold-over-thin-profile-records-named-deps-need.md)
- [A SIGTERM'd `cyrius capacity` leaves `cap_err` in its temp dir and its compiler running](2026-10-15-capacity-killed-leaves-cap-err-and-its-compiler-running.md)
- [Inside a closure, a captured vector passed to `p: *Pt` / `p: *i64` passes the capture's address (exit 42), where the same local outside the closure is refused by name under D27](2026-10-15-captured-vector-into-other-pointer-kind-passes-capture-address.md)
- [The CLI's kill handler has a fork-to-track window: a signal between `fork` and `_cbt_child_track` lets one child recreate `<out>.tmp.<pid>`](2026-10-15-cli-kill-handler-fork-to-track-window.md)
- [`cyrius header` prints `cyr_val f(..)` for a fn that is pair-returning only through a `?` on a pair call](2026-10-15-cyrius-header-misses-a-pair-propagated-by-question-mark.md)
- [`cyrius header` prints `cyr_val v` for a SIMD vector PARAMETER, which cycc receives in a vector register](2026-10-15-cyrius-header-vector-parameter-prints-cyr-val.md)
- [After D19's pin-move refusal, the closure files are already re-vendored at the new pin, so `deps --verify` fails on them while the refusal says only that the lock is unchanged](2026-10-15-d19-refusal-leaves-closure-files-revendored-at-the-new-pin.md)
- [D24 does not reach a top-level declaration: `var G: i64 = mk2(5);` (a 9-16 B struct) compiles and reads the first field](2026-10-15-d24-scalar-annotation-refusal-misses-top-level.md)
- [`cyrius deps` keeps a `cyrius.lock` row for a file removed from `lib/`, and `--locked` tells you to run the `deps` that does not drop it](2026-10-15-deps-keeps-a-lock-row-for-a-file-removed-from-lib.md)
- [`cyrius deps --lock` and a scoped `cyrius lib sync` at a moved pin still stamp the new pin over the old pin's rows](2026-10-15-deps-lock-and-scoped-lib-sync-restamp-a-moved-pin.md)
- [`deps --locked` after a D19 pin-move refusal still says "run `cyrius deps` and commit the result", and that command now refuses](2026-10-15-deps-locked-remedy-names-deps-after-a-d19-refusal.md)
- [A `cyrius distlib` killed mid-verify leaves its stdlib mirror `dist/.dlverify-<pid>/` (114 files) in the project](2026-10-15-distlib-verify-killed-leaves-its-stdlib-mirror-in-dist.md)
- [cyrius-lsp outside a project compiles a file from the server's working directory without its `#@incdir`, so a sibling `include` that `cyrius check` resolves is reported as `cannot open include file`](2026-10-15-lsp-loose-file-include-resolves-against-server-cwd.md)
- [`cyrius build --pie` on a macOS host writes the same Mach-O as a plain build at rc 0 — neither Mach-O compiler reads CYRIUS_PIE](2026-10-15-macos-cli-pie-inert-mach-o-compilers-read-no-cyrius-pie.md)
- [patra on Windows still treats a contended `xflock` as "no lock can be had": `_pt_flock_contended` accepts EAGAIN only on Linux / macOS](2026-10-15-patra-flock-contended-ignores-windows-xflock.md)
- [A struct passed to a `*V` parameter (`rd(s)` with `p: *f64v2`, `s: Pt`) is accepted silently: its address is read as the vector](2026-10-15-struct-into-vector-pointer-parameter-accepted.md)
- [A struct local passed to a word-pointer parameter (`ri(s)` with `p: *i64`) pushes its first field as the address](2026-10-15-struct-local-into-word-pointer-parameter-pushes-first-word.md)
- [An untyped `var q = G;` (a struct global) or `var q = h;` (a handle) in a fn still binds a word — does D29's typed copy reach them?](2026-10-15-untyped-name-copy-of-struct-global-or-handle-keeps-word.md)
- [A value-form `v: f32v8` parameter receives only its first word: `load32(&v + 8)` reads 0](2026-10-15-value-form-f32v8-parameter-receives-one-word.md)
- [A vector call result passed to a value-form vector parameter (`lanes(mkv(4, 2))`) is refused on x86_64 / aarch64 / cx with a cascade ("IDENT not found as a local" then "expected ';'"), and compiles to a page fault on PE](2026-10-15-vector-call-result-into-value-form-vector-parameter.md)
- [A vector dereference through an address-of or a double pointer, `rd(*&b)` / `rd(**ppb)`, into a `*V` parameter still passes lane 0 as the address (D27's `*pv` rule misses an operand with no step word)](2026-10-15-vector-deref-through-address-of-or-double-pointer-into-vector-pointer-param.md)
- [A vector call result or `*pv` into a pointer of another kind (`*Pt`, `*i64`), a vector local into a by-value struct parameter, and a vector METHOD or explicit-instance call result into `*V`, pass lane 0's bits as the address](2026-10-15-vector-value-into-other-pointer-or-byvalue-struct-and-unreceived-call-sources.md)
- [Windows: a drive-rooted `[deps.X] path` is joined onto the manifest's directory](2026-10-15-windows-drive-rooted-dep-path-joined-onto-manifest-dir.md)

**6.7.14 — Break 2, repair 4: generics, the frontend, infra (added at the 6.7.12 open, 2026-10-15)** (74)

- [`asm { in al, dx; }` is refused: `in` lexes as keyword 76, so the `ASM_IN` emitter is unreachable by its documented spelling](2026-10-08-asm-in-mnemonic-unreachable.md)
- [A bare const / enum-constant name as a statement is reported as an assignment (`N;` → "cannot assign to const 'N'")](2026-10-08-bare-const-statement-reported-as-assignment.md)
- [A field access in a const fn, or on a const, is refused with a message that names the wrong thing](2026-10-08-const-field-access-diagnostics-misname-refusal.md)
- [A top-level `var X = CONST;` is baked AND stored at run time; `2 * CONST` is not folded](2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md)
- [Diagnostic cascades: duplicate const-fn scope errors, three errors from one unclosed call, a for-step call's "undefined function", and `error:0:1:` at EOF](2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md)
- [The IR heap family is six fixed `S + 0x…` bands with fixed caps — one `alloc()` arena (HEAP-12)](2026-10-08-ir-heap-bands-fixed-offsets-and-caps.md)
- [`CYRIUS_IR=3` drops unrecorded field-access bytes: signed narrow fields read garbage, a field read after a dead store reads the wrong slot](2026-10-08-ir3-drops-unrecorded-field-emits.md)
- [In an x86 `kernel;` build a float-literal global scalar is a dead store after the program](2026-10-08-kernel-float-global-init-not-baked.md)
- [`#pure`'s `#io` / `#alloc` check is silent for a callee defined later](2026-10-08-pure-check-misses-later-defined-callee.md)
- [A redeclared global read inside its own `bool` redeclaration reads as boolean (`var G = 5; var G: bool = G;` exits 5)](2026-10-08-redeclared-global-bool-reads-own-stamp.md)
- [`--syntax-only` invents "expected '=', got '.'" for `a.f.g` when `f: *Foo` and `Foo` is in another file](2026-10-08-syntax-only-chained-field-through-unresolved-pointee.md)
- [TOKNAME has no name for 23 operator / literal tokens — "expected '=', got unknown"](2026-10-08-tokname-operator-tokens-unnamed.md)
- [u128 beyond `+` / `-` / comparisons: parameters, returns, struct fields and closure captures](2026-10-08-u128-params-returns-fields-captures.md)
- [A refused top-level const leaves the `_panic` latch set: the next const's error is never printed, and pass 2 drops a statement](2026-10-09-const-sweep-swallows-later-const-errors.md)
- [A named-field struct literal in the declaration zone is refused ("undefined variable 'a'") — the guide's own Structs example fails as written](2026-10-09-declaration-zone-named-struct-literal-refused.md)
- [A non-generic fn's parameter type `Mp<K, V>` with `K` / `V` never declared compiles silently](2026-10-09-undeclared-generic-type-arguments-accepted.md)
- [An error inside a generic fn's body is printed once per instance](2026-10-10-generic-body-errors-reported-per-instance.md)
- [An unknown name followed by `<..>` is accepted as a type argument (`g<Nonexist<u8>>`, `Box<slice<u8>>`) and runs as the i64 base](2026-10-10-unknown-generic-name-accepted-as-type-argument.md)
- [A top-level global whose constant initializer folds to ZERO, or folds through an enum constant, re-runs the expression at startup: `var R = INT_MIN % -1;` kills x86 and cx (136) and is 0 on aarch64 — OPEN (a decision)](2026-10-11-folded-zero-or-enum-global-reruns-at-startup-decision.md)
- [`#inline` on an `async fn` is silently a no-op: no "#inline ignored" warning](2026-10-11-inline-on-async-fn-silently-ignored.md)
- [An explicit type argument on a METHOD call (`p.id<f64>(h)`) is refused as "unknown field 'id'" and "undefined variable 'f64'"](2026-10-11-method-call-explicit-type-arguments-misdiagnosed.md)
- [A struct literal anywhere but a `var` initializer (`G = P { 5 };`, `f(P { 5, 6 })`, `(P { .. })`) is refused as "undefined variable 'P'"](2026-10-11-struct-literal-outside-var-initializer-misdiagnosed.md)
- [`CYRIUS_DCE=1` keeps the callees of a redefined function's losing body alive](2026-10-12-dce-keeps-the-callees-of-a-redefined-fns-losing-body.md)
- [A declaration after the first top-level statement: `fn` / `const` are taken, `struct` / `enum` / `trait` / `impl` / `union` / `mod` / `use` / `public` / `async fn` are refused, `impl` with a cascade, `async fn` and `union` by a misleading message — OPEN (a decision)](2026-10-12-declarations-after-first-statement-decision.md)
- [cybs's preprocessor buffers are unchecked: an include over 2 MB that includes another file has its tail overwritten](2026-10-13-cybs-include-scratch-and-buffers-unchecked.md)
- [CYRIUS_SYMS writes pre-compaction addresses under CYRIUS_DCE=1](2026-10-13-cyrius-syms-pre-compaction-addresses-under-dce.md)
- [CYRIUS_DCE=1 removes a LIVE generic instance emitted inside a dead instance's code range](2026-10-13-dce-removes-live-generic-instance-nested-in-dead-one.md)
- [W^X dead-code compaction leaves stale code bytes in .text's alignment pad](2026-10-13-wx-compaction-leaves-stale-bytes-in-text-pad.md)
- [Appending code to the end of a large function makes an EARLIER call in it segfault](2026-10-14-anuenue-growing-a-large-fn-segfaults-an-earlier-call.md)
- [A bounded method call on a struct carrier's `T` field (`b.v.show()`, `b: Box<T>`, `T: Show`) is a struct use: `gs(bi)` with `bi: Box<i64>` is refused although `impl Show for i64` exists](2026-10-14-bounded-method-call-on-carrier-field-is-a-struct-use.md)
- [A const context's skipped arm (`1 || pk()`, an untaken if-expression arm) names another file's `private` const fn with no visibility check and no `#deprecated` warning](2026-10-14-const-context-skipped-arm-calls-private-const-fn-unchecked.md)
- [cybs reports an indexed store to an undefined name (`zz[1] = 5;`) as the syntax-error class, never naming `zz`](2026-10-14-cybs-indexed-store-undefined-name-not-named.md)
- [cybs segfaults with no message when the input ends right after `fn` or `var`](2026-10-14-cybs-segfaults-on-eof-after-fn-or-var.md)
- [dead_code_floor.sh axis 1 goes RED on the DCE byte scan's false-live: two unrelated globals flip `ir_emit1 cx`](2026-10-14-dead-code-floor-trips-on-dce-byte-scan-false-live.md)
- [A declaration-zone global annotated `**T` is refused "expected '='" — the replay reads one `*`](2026-10-14-declaration-zone-pointer-annotation-replay-reads-one-star.md)
- [The stub scan's struct-carrier table (`_gcr`) holds 64 entries per generic and drops the rest without a word](2026-10-14-generic-carrier-table-caps-at-64-silently.md)
- [A generic forwarding its `T` inside a struct carrier into a stub generic (`gx(mk1(x))`, `gx(b)` with `b: Box<T>`) is refused at its definition](2026-10-14-generic-forwarding-carrier-into-stub-generic-refused.md)
- [A generic that forwards its `T` to a bounded generic is refused at `f64` when the bound has no `impl … for i64`: `o(h)` says "uses its type parameter as a struct"](2026-10-14-generic-forwarding-to-bounded-generic-refused-at-f64.md)
- [A generic fn's inline-replayed `return` inside a fn that returns a struct by value runs under THAT fn's struct-return class: `fn gpg<T>(): *T { return GPA; }` is refused ("… the 9-16 byte struct `P2` … got `GPA`")](2026-10-14-generic-instance-return-takes-enclosing-fns-struct-return-class.md)
- [A fn-local `var h: S = gpg<S>();` — a handle from a GENERIC call declared `: *T` — drops its `S` annotation: `h` is an untyped word and `h.v` is refused "no struct type in scope for 'h'"](2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md)
- [A `*S` LOCAL binds a generic's T to S — through an `x: *T` parameter and, against the guide, an `x: T` one — while `&G`, a `*S` global, field or parameter infer i64 and run the base — DECISION](2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md)
- [A generic fn declared `: *Box<T>` is refused at its definition ("unknown type 'T' as a type argument")](2026-10-14-generic-pointer-to-generic-struct-return-refused.md)
- [A local `const` in an `#inline` fn or a generic fn makes its second call in one scope a refusal — "'L' is already declared in this scope"](2026-10-14-local-const-in-inline-or-generic-body-refused-at-second-call.md)
- [One call of another file's `private` fn inside an `#inline` or generic body is reported once per replay of the body — three identical errors](2026-10-14-private-call-reported-once-per-body-replay.md)
- [slice_position_refused.sh K2 does not depend on `_sl_ann_at`'s FINDSTRUCT test: deleting it leaves the gate green](2026-10-14-slice-position-k2-misses-sl-ann-at-findstruct.md)
- [A two-parameter generic's instance name is ambiguous when a type argument is itself an instance: `g2<P<R>, i32>` and `g2<P, R<i32>>` share `g2$P$R$i32` — the second call runs the first's body](2026-10-14-two-param-generic-nested-instance-names-collide.md)
- [A type argument that is not a name (`Box<1 + 2>`, `Box<u128>`, `id<1 + 2>(3)`) is refused as "unknown type 'truct'" / "'struct'" — a name read from a number — and the generic call cascades](2026-10-14-type-argument-non-name-reported-with-garbage-name.md)
- [A `var` annotation that is not a type at all (`var b: 1 = 0;`, `var c: + = 2;`, `var G: 7 = 4;`) compiles silently](2026-10-14-var-annotation-non-type-token-compiles.md)
- [A `Vec<..>` still skips its argument unread as a type argument, a multi-value element, a trait member's parameter, a field's nested `Vec<Vec<..>>`, and in a Vec element's own `<..>`](2026-10-14-vec-type-argument-unread-outside-annotations.md)
- [The aarch64-linux release tarball ships none of the `[release] scripts`](2026-10-15-aarch64-linux-tarball-ships-no-release-scripts.md)
- [aarch64 W^X ELF layout pads every executable with up to 64 KiB of zeros — open](2026-10-15-aarch64-wx-layout-pads-every-binary-to-64k.md)
- [arm64 macOS `sys_mkdirat` / `sys_fchmodat` drop the dirfd: a relative path lands against the cwd](2026-10-15-arm64-macos-mkdirat-fchmodat-drop-the-dirfd.md)
- [Call-site diagnostics name a method by its mangled fn name (`in a call to 'S_ri'`, `'S_two' expects 2 arguments`) and a generic call by its instance (`'g$i'`) — D27 / A2's vector refusals among them](2026-10-15-call-diagnostics-name-method-by-mangled-name.md)
- [cx: a conditional jump (`jz` / `jnz`) over more than 128 KiB of bytecode wraps its 16-bit offset silently — the compile exits 0 and cxvm jumps to the wrong place](2026-10-15-cx-conditional-jump-past-128k-wraps-silently.md)
- [cx: two raw `syscall(SYS_MMAP)` paths still hand back a HOST address as success — `mmap_stack` and freelist's `_fl_mmap`](2026-10-15-cx-raw-mmap-paths-return-host-address.md)
- [cx: the static heap is still 128 KB (`lib/alloc_cx.cyr` `_CX_HEAP_SLOTS`) though cxvm's guest memory is 8 MiB since 6.7.12](2026-10-15-cx-static-heap-128k-while-guest-is-8-mib.md)
- [cx: the pointer-taking wrappers outside D13's four still hand the host a guest address — and since the 8 MiB guest segment a guest address can be cxvm's own Linux image (`cyr_munmap(0x400000, …)` unmaps cxvm's code)](2026-10-15-cx-untranslated-pointer-wrappers-can-reach-cxvm-image.md)
- [`cyrius-watch.sh` builds with raw `cat | cycc`: its output is unsigned and SIGKILLed on Apple Silicon, and an entry-relative `include` fails on every OS](2026-10-15-cyrius-watch-builds-with-raw-cycc-unsigned-on-apple-silicon.md)
- [distlib: the bundle checks read `lib/<leaf>.cyr` from cycc's OWN version slot, not the manifest's pinned `versions/<pin>/lib` — the final "bundle compiles" check fails when only the pinned slot exists](2026-10-15-distlib-bundle-compile-ignores-pinned-stdlib.md)
- [embed_build.sh axis 6 times ONE embed build against ONE baseline build, and the 2x bound flakes under host load — the slot-open tree fails it too](2026-10-15-embed-build-axis6-single-sample-timing-flakes-under-load.md)
- [`lib/async.cyr` still hand-gates the epoll_event data offset at its three WRITE sites — the stdlib has no writer for a caller-owned (stack) buffer](2026-10-15-epoll-event-writer-for-caller-buffers.md)
- [`g<f64v2>(b)` with `fn g<T>(p: *T)` reports a second error from D27's refusal (naming the instance `g$i`) after the type-argument refusal — a cascade](2026-10-15-generic-vector-type-arg-refusal-cascades-d27-refusal.md)
- [x86 ELF DCE stops compacting past 4,096 dead-code runs, and kybernet's `agnos-init` crossed it: 248,440 → 1,574,640 bytes](2026-10-15-kybernet-dce-compaction-cap-agnos-init.md)
- [The native-region renumber warning does not see a per-arch file included from inside a region, or the author's own constant](2026-10-15-native-region-warning-misses-included-files-and-author-constants.md)
- [PE `sys_open` answers -1 for every Win32 failure, so `file_open_r` / `file_read_all_r` can never say `IoNotFound` on Windows](2026-10-15-pe-open-failure-is-always-minus-one.md)
- [PE `sys_read` returns ReadFile's byte count even when ReadFile FAILS: a read error reads as 0, end of file](2026-10-15-pe-read-failure-reads-as-eof.md)
- [Process docs still describe the release gate's cross-OS leg as the crossos subset, with the full corpus opt-in](2026-10-15-process-docs-cross-os-leg-still-crossos-only.md)
- [A redeclared global whose LATER initializer is a folded constant (`= 2 + 1`, `= -5`, `= (7)`) is never compared — a conflicting value compiles silently](2026-10-15-redeclared-global-folded-later-value-not-compared.md)
- [Native TLS hello conformance, the residue past the 6.7.12 bite: duplicate extensions, bytes after an extension block, a malformed or multi-protocol ALPN answer, and a 1.2 client ServerHello that walks nothing](2026-10-15-tls-native-hello-conformance-residue.md)
- [`TLS_SHA256_CTX_LEN` (a literal public var, no const twin) still sizes the transcript clone copy: raising it smashes the stack](2026-10-15-tls-sha256-ctx-len-literal-var-drives-transcript-clone.md)
- [`_win_widen` / `_win_widen_n` in lib/syscalls_windows.cyr have no caller left](2026-10-15-win-widen-helpers-have-no-caller.md)
- [Windows disallowed CTL: its 48-byte entries are not applied (identifier form unknown)](2026-10-15-windows-disallowed-ctl-48-byte-entries.md)
- [Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end](2026-10-15-windows-protectedroots-flag1-user-root-unverified.md)
- [Five ws tests still define a `sandhi_server_find_header` (and one a `base64_encode`) stand-in that `lib/ws_server.cyr`'s own includes made a duplicate — every compile warns, and in one the stub binds last](2026-10-15-ws-tests-carry-stale-sandhi-find-header-stubs.md)

**6.7.15 — the full security audit + the refactor / optimization review** (2)

- [A tail call that copies a by-value struct argument is an ordinary call — a per-fn "writes no memory" analysis would win its `jmp` back](2026-10-09-tail-call-by-value-copy-needs-effect-analysis.md)
- [The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line)](2026-10-13-self-compile-prints-large-static-advisory.md)

**Open by design — placed arcs, not bugs** (5)

- [A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10)](2026-10-08-constant-if-arms-not-folded.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](2026-10-08-lib-public-constants-const-migration.md)
- [`cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read](2026-10-08-manifest-build-profiles-and-target-unread.md)
- [Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1](2026-10-08-native-tls-capability-limits.md)
- [`cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible](2026-10-08-poison-guard-pages-unbuilt.md)

**Unplaced** (3)

- [The seed (`bootstrap/asm`) truncates input at 131,072 B, overruns its 512-label table and its 65,536 B CODE buffer — all unchecked](2026-10-08-seed-asm-silent-caps-input-labels-code.md)
- [sigil (the crypto / trust fold) has no runtime logging: none of its 68 `src/` files calls sakshi](2026-10-12-sigil-has-no-runtime-logging.md)
- [cybs names neither the construct it refused nor the file and line](2026-10-13-cybs-per-construct-refusal-and-file-line.md)

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
