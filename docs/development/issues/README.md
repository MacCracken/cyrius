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


**6.7.11 — Break 2, repair 1** (73)

- [The lexer's `#`-attribute word list is hand-copied into six tools; five are held to `LEXATTRWORD` by no census](2026-10-08-attribute-word-list-hand-kept-in-five-tools.md)
- [cybs reports a bare "syntax error" (or "undefined variable") with no file, line or construct](2026-10-08-cybs-bare-syntax-error-no-location.md)
- [cybs compiles a statement-position call to an undefined function silently; the binary segfaults](2026-10-08-cybs-undefined-fn-call-in-statement-silent.md)
- [cyrlint has neither of its two planned checks: a bare-local-array overrun and a write-length / literal mismatch](2026-10-08-cyrlint-array-overrun-and-write-length-checks.md)
- [`cyrius distlib`: the every-target owner rule and the partial-target rule still disagree on ties and on in-unit declarers](2026-10-08-distlib-every-target-owner-rule-differs-from-partial.md)
- [One integer + f64 mix warns twice when the expression continues (`x = x + (x + 1.5)`)](2026-10-08-int-f64-mix-warns-twice-in-a-chain.md)
- [A killed `cyrius` run leaves a NON-EMPTY `cyrius-<pid>` temp dir that nothing reaps](2026-10-08-killed-cli-leaves-nonempty-tmp-dirs.md)
- [A fn whose body ends in `loop { … }` / `do … while` / `while (1)` is not "provably one value"](2026-10-08-loop-ending-fn-not-provably-single-return.md)
- [A parenthesised argument to a ≤ 8 B by-value struct parameter skips the struct type check](2026-10-08-paren-arg-small-byval-struct-skips-type-check.md)
- [The seed (`bootstrap/asm`) truncates input at 131,072 B, overruns its 512-label table and its 65,536 B CODE buffer — all unchecked](2026-10-08-seed-asm-silent-caps-input-labels-code.md)
- [self_compile pays ~4 % for the preprocessor's per-byte `PP_LEXST_AT` call layer (the 6.6.20 attribute-line rule)](2026-10-08-self-compile-attribute-line-rule-cost.md)
- [Struct-operator results: six typing / return-shape defects around struct operands](2026-10-08-struct-operator-results.md)
- [An `async fn` declared `: (i64, i64)` compiles, and its Future carries only the first value](2026-10-09-async-fn-multi-value-return-loses-second-value.md)
- [A const context calls another file's `private` const fn with no visibility check (and no `#deprecated` warning)](2026-10-09-const-context-calls-private-const-fn.md)
- [A const context counts a `Pair<i64, i64>` parameter as two — `pick(0, 7)` is refused, `pick(0, 1, 7)` builds](2026-10-09-const-fn-generic-param-comma-miscounted.md)
- [`var a, b = f();` from a struct callee wider than 16 B reads a wrong second value, silently, on every target](2026-10-09-destructure-of-wide-struct-callee-reads-wrong-second-value.md)
- [An integer constant passed to an `f64` / `f32` parameter keeps its bits with no warning](2026-10-09-int-argument-to-f64-param-silent.md)
- [A multi-value call where a named struct over 8 B is expected is taken as its address — four shapes compile clean](2026-10-09-multi-value-call-into-named-struct-slot.md)
- [A multi-value receive reads a return register the callee never wrote — three shapes compile silently](2026-10-09-multi-value-receive-reads-stale-return-registers.md)
- [Diagnostic cascades after a 6.7.7 refusal: tuples, `: stack` pair stores, u128 compound ops and D19](2026-10-09-refusal-cascades-tuples-pairs-u128-d19.md)
- [Source scanners: `const fn` is invisible, `Pair<i64, i64>` is two parameters, `cyrius header` prints `cyr_val ...`, cyrdoc writes past its buffers](2026-10-09-source-scanners-miss-const-fn-and-generic-commas.md)
- [A `: stack` pair in a struct-literal element or passed as a plain argument keeps the tag and drops the payload, silently](2026-10-09-stack-pair-struct-literal-element-and-argument-keep-tag.md)
- [`var p: P = f();` with a multi-value `f` compiles and crashes (the first value is taken as a pointer)](2026-10-09-struct-var-from-multi-value-call-crashes.md)
- [A `Vec<T>` var or parameter annotation never reads its `<T>`, so `Vec<(i64, i64)>` compiles where every other type argument refuses a tuple](2026-10-09-vec-annotation-type-argument-unchecked.md)
- [agnos — `CYRIUS_DCE=1` cannot shrink a `kernel;` image: compaction miscompiles through 6.6.19 and is declined from 6.6.20 on](2026-10-10-agnos-kernel-dce-compaction-moves-data.md)
- [`cyrius header` prints `cyr_val f(..)` for a fn returning a struct (9-16 B: rax:rdx; > 16 B: a hidden pointer)](2026-10-10-cyrius-header-ignores-struct-returns.md)
- [`.field` on a METHOD's `*T` result (`h.get().b`) is refused, where a free fn's `get2(h).b` reads it](2026-10-10-field-of-method-pointer-result-refused.md)
- [A generic that reads its struct parameter's `T` field as a struct (`b.v.y`, `b: Box<T>`) does not compile, called or not](2026-10-10-generic-base-reads-carrier-field-as-struct.md)
- [A generic call's own result as a struct-carrier argument (`gx(mk1(p))`) is not inferred — refused as a "different struct type"](2026-10-10-generic-call-result-as-carrier-argument-refused.md)
- [A generic METHOD called as `p.m(x)` with a struct for its type parameter runs the i64 base (the dead stub)](2026-10-10-generic-method-call-runs-i64-base.md)
- [A `: stack` pair-returning METHOD used above its `impl` is not a pair: `p.div(d)?` SIGSEGVs, `var v = p.div(d);` binds the tag](2026-10-10-pair-method-defined-after-use-not-flagged.md)
- [A fn parameter's type annotation is read as ONE token: `fn f(a: 5)` / `fn f(a: +)` compile, `fn f(p: **i64)` does not](2026-10-10-param-type-annotation-reads-one-token.md)
- [A parenthesised struct-returning call as a nested-struct literal element is refused ("unexpected '}'")](2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.md)
- [A pointer-to-vector PARAMETER (`p: *f64v2`) is taken as a by-value vector: `rd(&b)` is refused, `rd(b)` builds and SIGSEGVs](2026-10-10-pointer-to-vector-parameter-is-value-form.md)
- [`CYRIUS_POISON=0` (or empty, or any value) turns the poison mode ON — every compiler fork tests only "is it set"](2026-10-10-poison-env-zero-or-empty-turns-mode-on.md)
- [A local's struct receive from a call: `var x = (mk());` infers nothing, `var x: u8 = mk();` infers the struct over its annotation](2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md)
- [A program's own `struct slice` is used by a parameter / pointer but not by a fn-local `var x: slice`](2026-10-10-user-struct-named-slice-shadowed-in-locals.md)
- [On Windows, `cyrius build --agnos` and `--target=x86_64-bare-metal-elf` write a plain PE and exit 0](2026-10-10-windows-cli-drops-target-selectors.md)
- [`await f` keeps its operand's pointer step: with `f: *i32`, `(await f) + 1` adds 4](2026-10-11-await-result-keeps-typed-pointer-step.md)
- [A bounded generic called at `f64` is refused unless the trait ALSO has `impl … for i64`: `gb(h)` with only `impl Show for f64` says "needs `impl Show for i64`"](2026-10-11-bounded-generic-f64-impl-needs-i64-impl.md)
- [`cyrius pulsar` and the CLI's on-demand cx builds hand an inherited `CYRIUS_POISON` / `CYRIUS_BOUNDS` to the compiler they build](2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md)
- [Inside a closure, `s.len` of a captured slice and `q.y` of a captured untyped struct copy (`var q = p;`) are refused as "undefined variable"](2026-10-11-closure-field-read-of-captured-slice-or-untyped-struct-copy-refused.md)
- [A name a closure body declares without a `var` right before it is taken as a capture of the enclosing local](2026-10-11-closure-prescan-reads-declared-names-as-captures.md)
- [cx never auto-calls `fn main`: a program that leaves `main` to the entry epilogue does nothing on cx](2026-10-11-cx-does-not-auto-call-main.md)
- [`*p = l` through a `p: *S` (a struct pointer) stores neither the struct nor one word consistently — a zero-size `S` is overrun by 8 bytes, a small `S` gets its first field only, a 16-byte `S` its first 8 bytes — OPEN (a decision)](2026-10-11-deref-store-through-struct-pointer-decision.md)
- [A narrow scalar LOCAL (`u8` / `i16` / `i32`) is a one-byte pointer to the step checks, and `n + &x` is no pointer where `&x + n` is](2026-10-11-narrow-scalar-local-and-address-of-carry-byte-pointer-step.md)
- [Under `--allow-undef`, an undefined `_str` / `_int` sibling still takes its base's call: `pr(s)` reaches the undefined `pr_str` and traps (rc 132) instead of calling the defined `pr` — OPEN (a decision)](2026-10-11-overload-router-undefined-sibling-under-allow-undef-decision.md)
- [`+| +? -| -?` on a typed pointer add an unscaled count, then hand the result the pointer's step: with `q: *i32`, `(q +| 1) + 1` is `q + 5` — OPEN (a decision)](2026-10-11-saturating-op-keeps-left-pointer-step-decision.md)
- [agnos: a negative fd is taken for a tagged socket — `sys_write(-1, …)` sends on socket slot 7's connection, and `sys_close(-1)` returns 0 after freeing slot 7](2026-10-12-agnos-negative-fd-taken-for-socket-slot-7.md)
- [BENCHMARKS.md prints the cycc size rows (byte counts) as milliseconds — `cc5_bytes | 1ms | 2ms | 2ms` — and the file-size row is still named `size/cc5_bytes`](2026-10-12-benchmarks-md-size-rows-formatted-as-time.md)
- [The `#derive` scanner `T_from_json_str` skips a nested `#derive`d struct field's object to its first inner `,`: the nested field stays 0, every field after it is lost, and the nested object's own keys land in the outer struct](2026-10-12-derive-scanner-loses-fields-after-nested-struct.md)
- [A generic instantiated at `f64` and at a struct named `i` share one instance (`gen$i`) — the second call runs the first's body — OPEN (a decision)](2026-10-12-generic-f64-instance-name-collides-with-struct-i.md)
- [Under `CYRIUS_IR=3`, LASE drops the reload of a just-stored local across an unrecorded `EFLADDR` (`lea rax, [rbp+d]`): a method's argument, a by-value struct argument or a struct-returning call's argument receives the struct's ADDRESS](2026-10-12-ir3-lase-reloads-across-unrecorded-efladdr.md)
- [A pointer into a by-value struct parameter of 8 B or less is still passed as the pointer word when the pointer typing calls it no pointer: an if-expression of two different steps, an integer on the LEFT of the pointer](2026-10-12-pointer-into-small-byvalue-param-untyped-edges.md)
- [The "cannot be a fn return type" note lists an incomplete return-type set: `bool`, a multi-value `(T1, T2)`, `dyn Tr` and a generic's `T` are accepted but not named](2026-10-12-return-type-refusal-note-incomplete.md)
- [Every build that includes `lib/sandhi.cyr` (so every `lib/yantra.cyr` build) prints the large-static-data advisory](2026-10-12-sandhi-include-prints-large-static-advisory.md)
- [A dereference `*p` of a struct under 8 bytes is read as a whole word: a global initialised or assigned from it, a local assigned from it, a by-value argument and a `return *p` read past the object (SIGSEGV when it ends a mapping); only a local declaration copies byte-exact](2026-10-12-small-struct-dereference-reads-past-the-object.md)
- [A fn returning a struct of 8 B or less returns a local of ANOTHER struct type (its word) with no refusal, and a `*T` local or a `*U` parameter as its ADDRESS](2026-10-12-small-struct-return-takes-another-structs-value.md)
- [A struct global over 8 B initialised from a field reached through a `*T` (`var G: S16 = P.s;`, `= gp().s;`, `= VV.p.s;`) holds the field's first word and SIGSEGVs at the first use](2026-10-12-struct-global-init-from-field-through-pointer-faults.md)
- [A struct result over 8 bytes through `fncallN` / `callptr` compiles with no diagnostic and faults: no hidden result pointer is passed, no register pair is received](2026-10-12-struct-result-through-fn-pointer-faults.md)
- [A top-level `return` compiles with no diagnostic and does not return: execution continues past it on x86_64 / PE and it hangs on aarch64 / cx — OPEN (a decision)](2026-10-12-top-level-return-decision.md)
- [A value-form vector receive from `callptr` / `fncallN` (or any source but a by-name vector call) compiles with no diagnostic and reads wrong lanes, and faults on PE](2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md)
- [`lib/syscalls_x86_64_agnos.cyr` has no `sys_console_mode`#110 peer](2026-10-13-agnos-sys-console-mode-110-peer.md)
- [`lib/syscalls_x86_64_agnos.cyr` has no `sys_fd_kind`#111 peer](2026-10-13-agnos-sys-fd-kind-111-peer.md)
- [`lib/syscalls_x86_64_agnos.cyr` has no `sys_sock_send_dl`#109 peer](2026-10-13-agnos-sys-sock-send-dl-109-peer.md)
- [An ASSIGNMENT from a struct dereference (`l = *p`, `G = *p`, `o.s = *p`, `q = *p` into a `*S`) stores one word at every size, with a false "assigning non-pointer to typed pointer" warning](2026-10-13-assignment-from-struct-dereference-copies-one-word.md)
- [`take8(*pu)` with `pu: *U8` (a pointer to ANOTHER struct) into a by-value `S8` parameter compiles and passes U8's bytes; `take8(u)` with `u: U8` and the 16 B `take(*pu)` are refused by name — OPEN (a decision)](2026-10-13-dereference-of-other-struct-into-small-byvalue-param-decision.md)
- [`dir_list` / `dir_list_into` open the directory with a plain `O_RDONLY` — a FIFO there blocks forever](2026-10-13-dir-list-opens-directory-without-o-directory.md)
- [A generic call declared `: *T` (`fn gpg<T>(): *T`) is no struct source: `l = gpg<S>()` stores the pointer's word, `*gpg<S>()` as a value SIGSEGVs (a declaration, an argument, either operand), `gpg<S>().v` is refused](2026-10-13-generic-pointer-returning-call-as-struct-source.md)
- [`return GP;` (a `*S` global) and `return gp();` (a `: *S` call) from a fn returning a struct of 8 B or less return the POINTER's word; over 8 B both are refused by name — OPEN (a decision)](2026-10-13-small-struct-return-of-pointer-global-or-call-decision.md)
- [A struct-typed FIELD destination from a `*S` global, a `: *S` call or a `*S` field (`o.s = GP`, `o.s = gp()`, `o.s = w.p`) stores the pointer's word at every size](2026-10-13-struct-field-destination-from-pointer-global-call-or-field.md)
- [`GP = l` with `GP` a `*S` GLOBAL stores `l`'s first word into `GP` (a garbage pointer), where a `*S` local or parameter destination copies `l` into its pointee — OPEN (a decision)](2026-10-13-struct-value-into-pointer-global-destination-decision.md)
- [An untyped binding takes a struct-returning OPERATOR's type at every size (decision 12), but not a method chain or an if-expression of 8 B or less, nor a parenthesised 9–16 B operator / method result — OPEN (a decision)](2026-10-13-untyped-struct-binding-beyond-operators-decision.md)

**6.7.12 — Break 2, repair 2 (the platform release)** (111)

- [Inside a native-aarch64 region a raw syscall literal with an ESYSXLAT x86-compat row is translated with no warning](2026-10-08-aarch64-native-region-literal-translated-silently.md)
- [arm64-macOS: a folded literal syscall still carries the pipe / fork post-`svc` fixups (64 B a site, XLAT-3)](2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md)
- [`tests/win/async_iocp_pe.cyr` returns 1 at step 2 (`async_with_timeout`) on cass under a plain `cmd /c`](2026-10-08-async-iocp-pe-plain-cmd-c-step2.md)
- [CLI leftovers from the 6.7.6 review — path resolution (Windows, symlinked cwd, git ceiling), error counts, `lib sync --dry-run`, `update`, the lock under wine](2026-10-08-cli-path-and-reporting-leftovers.md)
- [`cyrius deps` / `build` after a pin move, before `lib sync --full`, stamp the new pin over the old pin's lock rows](2026-10-08-deps-before-lib-sync-stamps-new-pin.md)
- [`cyrius deps --verify` fails every file on a CRLF checkout of a committed `lib/` (`core.autocrlf=true`)](2026-10-08-deps-verify-crlf-checkout-mismatch.md)
- [`[embed]` / `${file:}` link race on Windows and Apple Silicon (the E-S3 residual)](2026-10-08-embed-open-link-race-pe-macos-arm64.md)
- [Windows `sys_symlink` widens at 519 units with no `\\?\` prefix: a path over 260 units fails -1](2026-10-08-windows-symlink-no-long-path-prefix.md)
- [Windows native-TLS trust store: four gaps against the Windows chain engine (CYRIUS-2026-0020's *Not covered*)](2026-10-08-windows-trust-store-parity-gaps.md)
- [x86-macOS: every `syscall()` site still inlines the whole `EMACHO_SYSXLAT` chain (~1.26 KB, 35 % of the compiler)](2026-10-08-x86-macos-emacho-sysxlat-not-folded.md)
- [`xflock` has no Windows route (`LockFileEx` not wired) — patra's crash recovery never runs on Windows (asked by patra)](2026-10-08-xflock-windows-lockfileex-not-wired.md)
- [`--strict-pin` / CYRIUS_STRICT_PIN does nothing off Linux, and cycc.exe ignores CYRIUS_PIE](2026-10-10-strict-pin-and-pie-inert-off-linux.md)
- [On macOS an exec-family child still inherits a signal mask its parent inherited from a launcher](2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md)
- [The macOS release tarballs ship two of the three `[release] scripts` — `cyrius-watch.sh` is left out — OPEN (a decision)](2026-10-11-macos-tarballs-omit-cyrius-watch-decision.md)
- [cass (Windows) full-corpus failures were never triaged into named skips vs real failures — the last count is v6.5.33's 32 of 282, the corpus is now 562, and no open issue tracks it](2026-10-12-cass-full-corpus-failures-untriaged.md)
- [`cyrius build` takes contradictory target flags (`--win --aarch64`, `--win --agnos`, `--aarch64 --target=js`, …), silently keeps one and exits 0](2026-10-12-combined-target-flags-silently-resolved.md)
- [cx's fixed 512 KiB code buffer: `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr` stops with a bare "codebuf overflow" on cx](2026-10-12-cx-codebuf-512k-overflows-yukti-crossos-test.md)
- [`cyriusly setup` (compiled): its "bootstrap cycc" step builds no cycc, its cross-bin loop can never match, and it builds the installed tools under an inherited `CYRIUS_BOUNDS`](2026-10-12-cyriusly-setup-bootstrap-cross-loop-and-env.md)
- [`cyrius init --help`, `cyrius port --help` and `cyrius sign-efi --help` (and `-h`) fail as unknown flags, while `cyrius --help` promises every command takes `--help`](2026-10-12-init-port-sign-efi-reject-help.md)
- [`cyrius package` with a missing `[build] entry` prints "package ready: build/<out>" and exits 0 with no artifact; its help row promises an `.ark` it never writes](2026-10-12-package-missing-entry-reports-ready.md)
- [`cyrius tests` still says it "goes in the next release" three releases after the one it named — when the deprecated alias is removed — OPEN (a decision)](2026-10-12-tests-verb-deprecated-alias-removal-decision.md)
- [agnos: `sock_bind` / `sock_listen` / `sock_accept` / `sock_connect` take ANY fd for socket slot `fd & 7` — a failed open's -1 binds, listens, accepts and connects on slot 7](2026-10-13-agnos-net-arms-take-any-fd-for-a-socket-slot.md)
- [`agnos_sock_send_deadline`: rearm=1's ceiling refresh after a re-arm is pinned by no row — deleting it leaves both deadline gates GREEN](2026-10-13-agnos-sock-send-deadline-rearm-ceiling-refresh-unpinned.md)
- [`cyrius api-surface` counts a variadic tail `...` as a parameter (`va/2`, `zv/1`)](2026-10-13-api-surface-variadic-arity.md)
- [`lib/audit_walk.cyr`'s Linux lister opens a directory with plain `O_RDONLY` — a FIFO there blocks the walk forever](2026-10-13-audit-walk-linux-lister-opens-without-o-directory.md)
- [A `cyrius` run killed mid-compile still leaves `cpp_<pid>`, `cc_err` and `<out>.tmp.<pid>` in its temp dir — only check.sh's reaper removes them](2026-10-13-cli-killed-mid-compile-leaves-scratch.md)
- [cybs's preprocessor buffers are unchecked: an include over 2 MB that includes another file has its tail overwritten](2026-10-13-cybs-include-scratch-and-buffers-unchecked.md)
- [CYRIUS_SYMS writes pre-compaction addresses under CYRIUS_DCE=1](2026-10-13-cyrius-syms-pre-compaction-addresses-under-dce.md)
- [cyrlint's overrun rule sizes only a fn-local `var a[N]` with a LITERAL N — a const / enum / expression size and a top-level bare array are never checked](2026-10-13-cyrlint-overrun-rule-literal-size-and-locals-only.md)
- [CYRIUS_DCE=1 removes a LIVE generic instance emitted inside a dead instance's code range](2026-10-13-dce-removes-live-generic-instance-nested-in-dead-one.md)
- [A fn declared `: (T1, T2[, T3])` that can fall off its end hands the caller stale registers](2026-10-13-declared-multi-value-fn-falls-off-its-end.md)
- [`var a, b = callptr(fp, 5);` is refused "multi-value destructure needs a call on the right-hand side", where `fncall1(fp, 5)` destructures](2026-10-13-destructure-of-callptr-refused.md)
- [`*pp` of a `pp: **T` is an untyped word, not a `*T`: `*pp + 1` steps one BYTE, and `var q: *T = *pp;` warns "assigning non-pointer to typed pointer"](2026-10-13-double-pointer-dereference-is-an-untyped-word.md)
- [`fncall1(&mk3, 5).b` — a field of a struct result through fncallN / callptr is a parse error, where `mk3(5).b` works](2026-10-13-field-of-indirect-call-struct-result.md)
- [On PE a vector-returning call whose result goes nowhere passes no hidden result pointer: `mkv(41, 7);` as a statement page-faults](2026-10-13-pe-discarded-vector-call-result-no-hidden-pointer.md)
- [README.md's list of fold versions is stale for six folds, and no gate ties it to `lib/`'s `# Version:` headers](2026-10-13-readme-fold-version-list-stale.md)
- [`ret2(a, b)` in a fn declared `: (i64, i64, i64)` leaves the third value stale](2026-10-13-ret2-in-three-value-fn-leaves-third-register-stale.md)
- [`cyrius type-audit` does not count a generic fn (`fn f<T>(..)`) as a public fn](2026-10-13-type-audit-skips-generic-fns.md)
- [A call DECLARED to return a vector that the vector receive / return still do not take: a method call, an untyped `var v = callptr(&f, ..)`, `return callptr(&f, ..)`](2026-10-13-vector-call-results-the-receives-do-not-take.md)
- [`var v: f64v2 = *p;` / `v = *p;` with `p: *f64v2` — refused since 6.7.11 (it stored one word); copy the vector through the pointer, as a struct's `*p` is?](2026-10-13-vector-dereference-into-vector-local-decision.md)
- [A vector VALUE that is not a named local, passed to a `*V` parameter (`rd(mkv(..))`, `rd(*pv)`), and a vector local passed to a non-vector pointer (`*Pt`, `*i64`) or to a `*f32v8`, pass lane 0's bits as the address](2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md)
- [A fn ending in `while (true) { .. }` / `do { .. } while (true);` is not proved to return one value](2026-10-13-while-true-ending-fn-not-provably-single-return.md)
- [`lib/ws.cyr` and `lib/ws_server.cyr` both declare the nine `WS_*` constants, so `cyrius distlib` refuses a bundle that uses one with neither leaf in its unit](2026-10-13-ws-and-ws-server-declare-the-same-constants.md)
- [W^X dead-code compaction leaves stale code bytes in .text's alignment pad](2026-10-13-wx-compaction-leaves-stale-bytes-in-text-pad.md)
- [On an aarch64 Linux host, `cyrius build --agnos` writes an aarch64 Linux ELF, and `--target=x86_64-bare-metal-elf` writes an aarch64 image while printing an x86_64 multiboot2 entry line, both at rc 0](2026-10-14-aarch64-linux-cli-drops-target-selectors.md)
- [`&x.f` — the address of a struct field — does not parse (`expected ')', got '.'`), while the guide cites `load64(&s.f)` and `&h.f` as expressions — OPEN (a decision)](2026-10-14-address-of-field-does-not-parse-guide-cites-it.md)
- [An undeclared `async fn` that says `return h();` of a multi-value call still drops the second value](2026-10-14-async-fn-forwarding-multi-value-call-loses-second-value.md)
- [A bare `Vec` struct field's size depends on whether a `struct Vec` is declared above or below the struct that uses it — the same text gives two layouts (the 6.6.10 order-dependent-layout class)](2026-10-14-bare-vec-field-layout-depends-on-declaration-order.md)
- [A bounded method call on a struct carrier's `T` field (`b.v.show()`, `b: Box<T>`, `T: Show`) is a struct use: `gs(bi)` with `bi: Box<i64>` is refused although `impl Show for i64` exists](2026-10-14-bounded-method-call-on-carrier-field-is-a-struct-use.md)
- [The captured-name refusal's fix-it reads `var y = y;` when the captured name is `y`](2026-10-14-captured-name-refusal-fixit-reads-var-y-equals-y.md)
- [A closure's capture of a narrow scalar local (`i8` .. `i32`, `u8` .. `u32`) reads the slot's whole 8-byte word: a negative value is zero-extended, and stale upper bytes come along](2026-10-14-closure-capture-of-narrow-local-reads-unextended-word.md)
- [In a closure, `var a = a + n;` (and a destructure's FIRST name, `var a, b = f(a);`) reads a global `a`, or is refused "undefined variable", where the enclosing local `a` is meant](2026-10-14-closure-var-initializer-reading-its-own-name-drops-the-capture.md)
- [A const context's skipped arm (`1 || pk()`, an untaken if-expression arm) names another file's `private` const fn with no visibility check and no `#deprecated` warning](2026-10-14-const-context-skipped-arm-calls-private-const-fn-unchecked.md)
- [cx: seven corpus .tcyr fail under cxvm once their `fn main` runs — stdlib wrappers that compile for cx but pass guest offsets to the host (pipe, fstat, unlink), a host-address `mmap_anon`, and tests with no cx arm](2026-10-14-cx-main-running-tcyr-fail-at-guest-contract-limits.md)
- [cybs reports an indexed store to an undefined name (`zz[1] = 5;`) as the syntax-error class, never naming `zz`](2026-10-14-cybs-indexed-store-undefined-name-not-named.md)
- [cybs segfaults with no message when the input ends right after `fn` or `var`](2026-10-14-cybs-segfaults-on-eof-after-fn-or-var.md)
- [`cyrius header` prints `cyr_val f(..)` for a fn returning a `: stack` enum (`: Result` / `: Option`, the stdlib's value form), which cycc returns as a (tag, payload) pair in rax:rdx](2026-10-14-cyrius-header-stack-enum-return-prints-cyr-val.md)
- [`cyrius header` prints `cyr_val f(..)` for a fn returning a SIMD vector (`f64v2`, `f64v4`, `i32v4`, ...)](2026-10-14-cyrius-header-vector-return-prints-cyr-val.md)
- [`cyrius self` and `cyrius soak` self-host the compiler under an inherited CYRIUS_POISON / CYRIUS_BOUNDS / CYRIUS_COVERAGE — their verdict is about a mode build, not the default compiler](2026-10-14-cyrius-self-and-soak-inherit-compile-mode-switches.md)
- [dead_code_floor.sh axis 1 goes RED on the DCE byte scan's false-live: two unrelated globals flip `ir_emit1 cx`](2026-10-14-dead-code-floor-trips-on-dce-byte-scan-false-live.md)
- [A declaration-zone global annotated `**T` is refused "expected '='" — the replay reads one `*`](2026-10-14-declaration-zone-pointer-annotation-replay-reads-one-star.md)
- [A struct dereference as an IF-EXPRESSION BRANCH is typed an integer: `var v: S = if (c) { *p } else { *q };` binds `v` as a handle holding the word `*p` read (SIGSEGV at every size), and `if (c) { *p } else { s }` is refused as "branches differ in type"](2026-10-14-dereference-as-if-expression-branch.md)
- [A dereference of a `*S` as a tuple literal's element stores the struct's first word, where a struct value element is refused by name](2026-10-14-dereference-as-tuple-element-stores-first-word.md)
- [`*(&p)` of a struct over 8 B — as an argument for a by-value struct parameter or a declaration's initialiser — reads its first word as the struct's address: SIGSEGV](2026-10-14-dereference-of-address-of-struct-faults.md)
- [The `#derive` scanner `T_from_json_str` does not walk a SCALAR field's object or array value: its inner keys are read as the outer struct's](2026-10-14-derive-scanner-scalar-field-holding-object-derails-scan.md)
- [A `dyn Tr` result through a known callee (`var a: dyn Shape = fncall1(&mkd, &q);`) is refused, where `mkd(&q)` forms the dyn](2026-10-14-dyn-result-through-known-callee-refused.md)
- [An explicit-instance generic call returning a vector (`mkg<i64>(41, 7)`) is not received by a value-form vector local](2026-10-14-explicit-instance-vector-result-not-received.md)
- [An untyped `var c = f() < 1.0;` with a `: f64` leading call is typed f64 — `-c` flips the sign bit](2026-10-14-f64-leading-call-types-comparison-binding-f64.md)
- [The stub scan's struct-carrier table (`_gcr`) holds 64 entries per generic and drops the rest without a word](2026-10-14-generic-carrier-table-caps-at-64-silently.md)
- [A generic forwarding its `T` inside a struct carrier into a stub generic (`gx(mk1(x))`, `gx(b)` with `b: Box<T>`) is refused at its definition](2026-10-14-generic-forwarding-carrier-into-stub-generic-refused.md)
- [A generic that forwards its `T` to a bounded generic is refused at `f64` when the bound has no `impl … for i64`: `o(h)` says "uses its type parameter as a struct"](2026-10-14-generic-forwarding-to-bounded-generic-refused-at-f64.md)
- [A generic fn's inline-replayed `return` inside a fn that returns a struct by value runs under THAT fn's struct-return class: `fn gpg<T>(): *T { return GPA; }` is refused ("… the 9-16 byte struct `P2` … got `GPA`")](2026-10-14-generic-instance-return-takes-enclosing-fns-struct-return-class.md)
- [A fn-local `var h: S = gpg<S>();` — a handle from a GENERIC call declared `: *T` — drops its `S` annotation: `h` is an untyped word and `h.v` is refused "no struct type in scope for 'h'"](2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md)
- [A `*S` LOCAL binds a generic's T to S — through an `x: *T` parameter and, against the guide, an `x: T` one — while `&G`, a `*S` global, field or parameter infer i64 and run the base — DECISION](2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md)
- [A generic fn declared `: *Box<T>` is refused at its definition ("unknown type 'T' as a type argument")](2026-10-14-generic-pointer-to-generic-struct-return-refused.md)
- [header_spellings_and_size.sh: H8's preprocessor-guard rows and H11 / H11b are skipped silently on a host with cc that is not x86_64 (no SKIP named, the gate PASSes)](2026-10-14-header-gate-skips-guard-and-c-caller-rows-silently.md)
- [A fn that calls an inline-replayed `: stack` pair generic is flagged pair-returning ITSELF: a false "bind both" at its callers and a false mixed-return warning](2026-10-14-inline-replayed-pair-return-flags-the-caller.md)
- [An integer comparison or bitwise operator with an f64 right operand leaves its result typed f64](2026-10-14-integer-comparison-result-keeps-f64-right-operand-type.md)
- [A local `const` in an `#inline` fn or a generic fn makes its second call in one scope a refusal — "'L' is already declared in this scope"](2026-10-14-local-const-in-inline-or-generic-body-refused-at-second-call.md)
- [`*p = f()` with `f` a multi-value fn and `p: *S` stores the FIRST value as the struct's word, where `G = f()` into a struct is refused by name — OPEN (a decision)](2026-10-14-multi-value-call-stored-through-struct-pointer-decision.md)
- [A nested closure's parameter named like an enclosing local is taken as a capture by the closure around it — refused without lib/alloc.cyr, or a needless heap env](2026-10-14-nested-closure-parameter-taken-as-outer-capture.md)
- [A `: stack` pair-returning trait DEFAULT method used above its trait / impl is not a pair: `p.m(d)?` SIGSEGVs, `var v = p.m(d);` binds the tag](2026-10-14-pair-trait-default-method-used-above-its-trait-not-flagged.md)
- [`var x = (mk1());` (an 8 B struct) and `var x = (b.mk());` (a 9–16 B method) still infer nothing — the method's first word crashes through a by-value parameter](2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md)
- [A parenthesised dyn-returning call as a struct literal's `dyn` element is refused with two reports, where the unwrapped call and every other dyn destination take it](2026-10-14-paren-wrapped-dyn-call-as-dyn-literal-element-refused.md)
- [A parenthesised 9-16 B method or operator result as a nested-struct literal element is refused ("unexpected '}'")](2026-10-14-paren-wrapped-pair-method-or-operator-as-nested-literal-element-refused.md)
- [A parenthesised `: stack` pair call escapes every pair check: `var v = (f(7));`, `x = (f(7));`, `h.a = (f(7));`, `P { (f(7)), 3 }` keep the tag silently, and `var v = (f(7))?;` takes the boxed `?` and SIGSEGVs](2026-10-14-paren-wrapped-stack-pair-call-escapes-every-pair-check.md)
- [A parenthesised `&f` callee (`callptr((&mk3), 5)`, `fncall1((&mk2), 5)`) is an unknown callee: its struct / vector result convention is lost — SIGSEGV](2026-10-14-parenthesised-fn-pointer-callee-loses-struct-result.md)
- [A pointer-annotated local from a by-value struct call: `var x: *P2 = mkp();` (16 B) compiles with only a warning and SIGSEGVs at `x.b`; `var x: *i64 = mkp();` holds the first word](2026-10-14-pointer-annotated-local-from-byvalue-struct-call.md)
- [One call of another file's `private` fn inside an `#inline` or generic body is reported once per replay of the body — three identical errors](2026-10-14-private-call-reported-once-per-body-replay.md)
- [A global first declared `= 0` and redeclared with another value is silent (no "conflicting value" warning), so two files' same-name globals merge unseen](2026-10-14-redeclared-global-from-zero-is-silent-and-cross-fold-collisions-invisible.md)
- [A local `const k: i64 = 3;` is refused, and every later read of `k` adds "undefined variable 'k'"](2026-10-14-refused-local-const-annotation-cascades-undefined-variable.md)
- [A refused parameter default drops every default of its fn — each call that relies on one is refused again](2026-10-14-refused-parameter-default-refuses-every-short-call.md)
- [`ret2(a, b)` in a fn returning a struct over 16 B or of 8 B or less takes the multi-value path](2026-10-14-ret2-in-struct-returning-fn-takes-multi-value-path.md)
- [`return &s;` in a fn returning the struct `S`: at 8 B or less the ADDRESS is the struct's word; over 8 B it is refused in other words — OPEN (a decision)](2026-10-14-return-address-of-struct-local-decision.md)
- [`var x: i64 = b.mk();` / `var y: u8 = a + b;` take a struct METHOD's or OPERATOR's first word, narrowed, where the free-call form is refused since 6.7.11 — OPEN (a decision)](2026-10-14-scalar-annotation-from-struct-method-or-operator-keeps-first-word.md)
- [A sync fn declared one value (`fn g2(): i64 { return (1, 2); }`) compiles clean and the caller silently gets the first value](2026-10-14-scalar-declared-fn-returning-multi-value-literal.md)
- [slice_position_refused.sh K2 does not depend on `_sl_ann_at`'s FINDSTRUCT test: deleting it leaves the gate green](2026-10-14-slice-position-k2-misses-sl-ann-at-findstruct.md)
- [A by-value `self` from a `*S` receiver, and a `*S` into a by-value `S` parameter, of a 3 / 5 / 6 / 7-byte struct carry FRAME GARBAGE in the word's padding (`_hl_pval_ra`'s temp is not zeroed)](2026-10-14-small-struct-byvalue-word-padding-from-frame.md)
- [A whole struct-typed FIELD of 3, 5, 6 or 7 bytes used as a value — `take(w.s)`, `return w.s`, `w.s + a`, a top-level `var G: S3 = GW.s;` — is loaded as an 8-byte word: it reads past the object (SIGSEGV when it ends a mapping)](2026-10-14-small-struct-field-value-reads-past-the-object.md)
- [A fn declared `: P1` (a struct of 8 B or less) that says `return mk(..);` of a multi-value call returns its first value as the struct](2026-10-14-small-struct-fn-returns-multi-value-call.md)
- [struct_value_codegen.sh's A rows (struct_value_codegen.tcyr) carry no row-count floor — a gutted values file passes](2026-10-14-struct-value-codegen-a-rows-no-floor.md)
- [A top-level `ret2(a, b)` compiles with no diagnostic and does not return: x86_64 / PE run on past it, aarch64 / cx hang at it](2026-10-14-top-level-ret2-never-returns.md)
- [A two-parameter generic's instance name is ambiguous when a type argument is itself an instance: `g2<P<R>, i32>` and `g2<P, R<i32>>` share `g2$P$R$i32` — the second call runs the first's body](2026-10-14-two-param-generic-nested-instance-names-collide.md)
- [A type argument that is not a name (`Box<1 + 2>`, `Box<u128>`, `id<1 + 2>(3)`) is refused as "unknown type 'truct'" / "'struct'" — a name read from a number — and the generic call cascades](2026-10-14-type-argument-non-name-reported-with-garbage-name.md)
- [An undeclared multi-value call (`return (a, b)`, counted by pass 1) passed to a TUPLE parameter is taken as its address](2026-10-14-undeclared-multi-value-call-into-tuple-parameter-crashes.md)
- [`*p = v` with an untyped value into a struct over 8 bytes writes only the first 8 bytes — confirm the reading of decision D4 (a)'s "at sizeof(S) bytes" — OPEN (a decision to confirm)](2026-10-14-untyped-store-through-struct-pointer-over-8-bytes-reading.md)
- [A `var` annotation that is not a type at all (`var b: 1 = 0;`, `var c: + = 2;`, `var G: 7 = 4;`) compiles silently](2026-10-14-var-annotation-non-type-token-compiles.md)
- [A `Vec<..>` still skips its argument unread as a type argument, a multi-value element, a trait member's parameter, a field's nested `Vec<Vec<..>>`, and in a Vec element's own `<..>`](2026-10-14-vec-type-argument-unread-outside-annotations.md)
- [The value-form vector local refusal prints its fn-pointer hint for every source, and now reports an undefined function as a refused source](2026-10-14-vector-local-refusal-hint-every-source.md)
- [A zero-size struct value into a struct-typed FIELD (`o.s = GP`, `o.s = gp()`, `o.s = (GP)`, `o.s = mk()`) or a zero-size `*p` used as a value still moves an 8-byte word: the field's neighbour is clobbered, and `take(*p)` reads 8 bytes past the object](2026-10-14-zero-size-struct-into-field-or-dereference-value-moves-a-word.md)
- [`var A: (i64, i64) = (B);` in the declaration zone, with B declared below: `_gci_below` names the wrong source, 'var' instead of 'B'](2026-10-14-zone-tuple-copy-init-below-names-var-for-parenthesised-source.md)

**6.7.13 — Break 2, repair 3** (31)

- [`asm { in al, dx; }` is refused: `in` lexes as keyword 76, so the `ASM_IN` emitter is unreachable by its documented spelling](2026-10-08-asm-in-mnemonic-unreachable.md)
- [A bare const / enum-constant name as a statement is reported as an assignment (`N;` → "cannot assign to const 'N'")](2026-10-08-bare-const-statement-reported-as-assignment.md)
- [A field access in a const fn, or on a const, is refused with a message that names the wrong thing](2026-10-08-const-field-access-diagnostics-misname-refusal.md)
- [A top-level `var X = CONST;` is baked AND stored at run time; `2 * CONST` is not folded](2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md)
- [Diagnostic cascades: duplicate const-fn scope errors, three errors from one unclosed call, a for-step call's "undefined function", and `error:0:1:` at EOF](2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md)
- [`gp().n = 5` through a `*T`-returning call is refused as "the result is a temporary"](2026-10-08-field-store-through-pointer-returning-call-refused.md)
- [The IR heap family is six fixed `S + 0x…` bands with fixed caps — one `alloc()` arena (HEAP-12)](2026-10-08-ir-heap-bands-fixed-offsets-and-caps.md)
- [`CYRIUS_IR=3` drops unrecorded field-access bytes: signed narrow fields read garbage, a field read after a dead store reads the wrong slot](2026-10-08-ir3-drops-unrecorded-field-emits.md)
- [In an x86 `kernel;` build a float-literal global scalar is a dead store after the program](2026-10-08-kernel-float-global-init-not-baked.md)
- [`#pure`'s `#io` / `#alloc` check is silent for a callee defined later](2026-10-08-pure-check-misses-later-defined-callee.md)
- [A redeclared global read inside its own `bool` redeclaration reads as boolean (`var G = 5; var G: bool = G;` exits 5)](2026-10-08-redeclared-global-bool-reads-own-stamp.md)
- [`--syntax-only` invents "expected '=', got '.'" for `a.f.g` when `f: *Foo` and `Foo` is in another file](2026-10-08-syntax-only-chained-field-through-unresolved-pointee.md)
- [Native TLS conformance, as one bite: six handshake checks that are missing, loose or untested](2026-10-08-tls-native-conformance-bite.md)
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
- [`TLS_CA_MAX_ROOTS` bounds nothing since 6.7.9 — keep the public name or retire it — OPEN (a decision)](2026-10-11-tls-ca-max-roots-unread-decision.md)
- [The public bound vars (`var X = _X;`): stay writable, or become read-only — the TLS stack's first — OPEN (a decision)](2026-10-11-tls-public-bound-vars-api-decision.md)
- [The native TLS stack's public bound vars still drive storage their consts size: a raised `TLS12_RANDOM_LEN` smashes the stack](2026-10-11-tls-public-bound-vars-drive-const-storage.md)
- [A declaration after the first top-level statement: `fn` / `const` are taken, `struct` / `enum` / `trait` / `impl` / `union` / `mod` / `use` / `public` / `async fn` are refused, `impl` with a cascade, `async fn` and `union` by a misleading message — OPEN (a decision)](2026-10-12-declarations-after-first-statement-decision.md)
- [cyrius-lsp diagnostics: the column lands in the message, an included file's error lands on the open file, and `.tcyr` / `.bcyr` / `.fcyr` / `.scyr` / `.smcyr` get nothing](2026-10-12-lsp-diagnostics-column-file-and-extensions.md)
- ["assigning non-pointer to typed pointer" is missing for a declaration-zone `*T` global and for an assignment to a local or parameter `*T` of a scalar `T`](2026-10-12-typed-pointer-non-pointer-warning-gaps.md)
- [`programs/wc.cyr` (a demo): counts of 8 or more digits run together with no separator, and VT / FF do not separate words](2026-10-12-wc-demo-columns-run-together-and-whitespace-set.md)

**6.7.14 — the full security audit + the refactor / optimization review** (2)

- [A tail call that copies a by-value struct argument is an ordinary call — a per-fn "writes no memory" analysis would win its `jmp` back](2026-10-09-tail-call-by-value-copy-needs-effect-analysis.md)
- [The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line)](2026-10-13-self-compile-prints-large-static-advisory.md)

**Open by design — placed arcs, not bugs** (5)

- [A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10)](2026-10-08-constant-if-arms-not-folded.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](2026-10-08-lib-public-constants-const-migration.md)
- [`cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read](2026-10-08-manifest-build-profiles-and-target-unread.md)
- [Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1](2026-10-08-native-tls-capability-limits.md)
- [`cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible](2026-10-08-poison-guard-pages-unbuilt.md)

**Unplaced** (10)

- [`cyrfmt --check` exits 0 on a file that `cyrfmt` itself reformats (a call's continuation-line indent)](2026-10-12-cyrfmt-check-passes-a-file-cyrfmt-would-reformat.md)
- [`CYRIUS_DCE=1` keeps the callees of a redefined function's losing body alive](2026-10-12-dce-keeps-the-callees-of-a-redefined-fns-losing-body.md)
- [`cyrius deps` keeps a stdlib leaf removed from `[deps].stdlib` vendored and locked, and nothing reports it](2026-10-12-deps-keeps-a-removed-stdlib-leaf-vendored-and-locked.md)
- [After a `[deps.NAME]` tag changes, `cyrius.lock` keeps the old tag's `commit` row beside the new one, and `deps --locked` accepts it](2026-10-12-deps-keeps-a-stale-commit-row-after-a-tag-change.md)
- [`cyrius distlib` records a named dep's transitive stdlib leaf as the bundle's own: a pure module's sidecar gets `boxed`](2026-10-12-distlib-records-a-named-deps-transitive-leaf-as-the-bundles-own.md)
- [An inline `Str` (from a `Str { .. }` literal) used as a `Str` value passes its `data` word, not a handle: `f(t)` with `fn f(s: Str)` reads the wrong length, silently](2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md)
- [sigil (the crypto / trust fold) has no runtime logging: none of its 68 `src/` files calls sakshi](2026-10-12-sigil-has-no-runtime-logging.md)
- [The stdlib builds an `epoll_event` per arch (`epoll_event_new`) but offers nothing to read one back, so consumers hand-gate the data offset](2026-10-12-stdlib-epoll-event-has-a-writer-but-no-reader.md)
- [`lib/syscalls_linux_common.cyr`'s `sys_ioctl` comment says ELF aarch64 has no 16 → 29 row; the backend has had one since v6.5.38](2026-10-12-sys-ioctl-comment-says-aarch64-has-no-16-to-29-row.md)
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
