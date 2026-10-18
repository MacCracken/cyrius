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


**6.7.15 — Break 2, repair 5 (added at the 6.7.13 integration, 2026-10-16)** (113)

- [The aarch64 compiler has no TypeScript front end: `--parse-ts` / `--lex-ts` are ignored, so the aarch64 tarball's `ts_test_runner` fails every file](2026-10-16-aarch64-cycc-has-no-ts-front-end-ts-test-runner-fails-every-file.md)
- [A method no bound declares, called on a struct carrier's `T` field (`b.v.other()`, `b: Box<T>`, `T: Show`), is not checked against the bound](2026-10-16-bound-contract-unchecked-on-carrier-field-call.md)
- [A subscript or a method call in a const fn, and a method call on a const, name the wrong refusal (and two report twice)](2026-10-16-const-fn-subscript-method-and-const-method-receiver-misnamed.md)
- [A constant left operand, then `+ - & | ^` and a literal followed by `*%`, `*|`, `*?` or `>>>`, is refused "expected ';'"](2026-10-16-constant-left-literal-then-term-operator-refused.md)
- [crossos `.tcyr` rows that mkdir or symlink fail on cxvm (`xmkdir` / `xsymlink` reach the host with an untranslated guest path), and no gate runs the crossos corpus on cx — pe_open_failure_errno.tcyr's directory group joins open_flags_per_target / atomic_write_temp_exclusive there](2026-10-16-cx-crossos-mkdir-symlink-rows-fail-and-no-gate-runs-them.md)
- [cybs's include-once list is unchecked: the 257th distinct include is skipped, and a 256+ character spelling is included twice](2026-10-16-cybs-include-once-list-and-name-buffers-unchecked.md)
- [The dead-code reachability seed pass is O(call sites × fns): FIXUP dominates a large program's compile](2026-10-16-dce-seed-pass-host-scan-quadratic.md)
- [The error writers outside util.cyr's emitters still print once per generic instance: an arity error three times, a second subscript twice](2026-10-16-direct-error-writers-print-once-per-generic-instance.md)
- [A `: **Box<..>` return is read in pass 1: `: **Box<Zork>` is reported twice and `: **Box<Later>` (a struct declared below) is refused](2026-10-16-double-pointer-generic-return-read-in-pass-one.md)
- [`var a: Box<dyn Show>;` reports a second error after the dyn type-argument refusal, naming the instance `Box$dyn Show`](2026-10-16-dyn-type-argument-refusal-cascades-into-instance-local.md)
- [The explicit method spelling `x.m<..>(..)` (6.7.14, D7 (a)) is not recognised by the lookaheads that key a method call as `x.m(`: `var a, b = p.mm<i64>(3);` is "multi-value destructure needs a call on the right-hand side"](2026-10-16-explicit-method-type-args-in-method-call-lookaheads.md)
- [A generic passing its `T`-typed VALUE whole into a stub generic's struct-carrier position (`gx(x)`, `x: T`, `fn gx<U>(b: Box<U>)`) is refused at its definition](2026-10-16-generic-passing-t-value-into-stub-carrier-position-refused.md)
- [Through a generic's plain `x: T` / `p: *T` parameter, a struct argument in parentheses, a whole dereference and a closure-captured struct bind nothing (a struct carrier binds all three since 6.7.11)](2026-10-16-generic-plain-parameter-wrapped-deref-or-captured-struct-binds-nothing.md)
- [A `var t: *T` local in a generic instance is no struct receiver: `t.y` with T bound to `Pt` is "no struct type in scope for 't'", where the parameter `p: *T` and a non-generic `var t: *Pt` are](2026-10-16-generic-pointer-local-of-type-parameter-untyped-in-instance.md)
- [A scalar pointer (`*i32`, `*f64`, `&h`) through a generic's `p: *T` binds i64, not its pointee: `second(pa)` with `pa: *i32` steps 8 bytes — DECISION](2026-10-16-generic-scalar-pointee-binds-i64-through-pointer-parameter.md)
- [A generic struct's `*T` field does not hop in its instance: `b.p.y` with `b: Pb<Pt>` (`struct Pb<T> { p: *T; n; }`) is "expected ';', got '.'"](2026-10-16-generic-struct-pointer-field-does-not-hop.md)
- [The token-level generic binding (`_tok_gen_tp_sid`) does not follow D8's pointer rule: `var r = gd(&G); r.pick(t)` in a generic is refused naming the stub method](2026-10-16-generic-token-scans-miss-d8-pointer-binding.md)
- [A multi-value return element, a trait member's signature and a `*fn(..)` parameter type leave a generic struct's type arguments unread (`(Box<Zork>, i64)`, `b: Box<nosuch>`, `*fn(Box<Zork>)`)](2026-10-16-generic-type-args-unread-in-mret-trait-and-fn-pointer-signatures.md)
- [A global redeclared with a different type is refused, then a declaration-zone initializer between the two declarations is refused again for reading it](2026-10-16-global-type-change-refusal-cascades-into-earlier-reader.md)
- [The guide's `#ifplat aarch64` example `asm { dmb ish }` does not compile: aarch64 asm mnemonics take no operand](2026-10-16-guide-ifplat-example-dmb-ish-does-not-compile.md)
- [cycc includes a file twice when its include path is 128 characters or longer — include-once stores 127](2026-10-16-include-once-path-of-128-chars-included-twice.md)
- [`CYRIUS_IR=3`: a constant fold whose span holds a dead-store-eliminated node has its new immediate NOP-filled](2026-10-16-ir3-const-fold-over-dead-store-nop-fills-its-immediate.md)
- [In an x86 `kernel;` build a float global whose constant initializer is not a bare literal (`= CF`, `= (1.5)`, `= 1.5 + 1.0`) is still a dead store after the program](2026-10-16-kernel-float-global-constant-not-a-literal-left-late.md)
- [A SIGTERM'd `cyrius deps` waits without limit for a forwarded git (fwd 1) that does not die on the signal](2026-10-16-kill-handler-waits-unbounded-for-a-forwarded-git.md)
- [lsp_diagnostics_file_column.sh exits rc 1 with no verdict under `bash -eo pipefail` (a feeder's write to a server that has exited)](2026-10-16-lsp-gate-exits-without-a-verdict-under-pipefail.md)
- [The native-region renumber warning does not judge a fn-local `const` declared inside a region](2026-10-16-native-region-warning-skips-fn-local-const.md)
- [The native-region renumber warning does not judge a constant declared at the top level of a per-arch file included from inside `#ifdef CYRIUS_ARCH_AARCH64` — the D61 include shape, spelled by name](2026-10-16-native-region-warning-skips-top-level-constant-in-included-per-arch-file.md)
- [A nested type argument closed by `>>` (or `>>>`) and followed by `,` swallows the next argument: `g2<P<P<R>>, i16>` binds B to i64](2026-10-16-nested-type-arg-shift-close-then-comma-drops-next-arg.md)
- [A non-generic struct or scalar written with type arguments (`Pt<i64>`, `g<Pt<i32>>`, `i64<u8>`) compiles, the arguments ignored](2026-10-16-non-generic-type-given-type-arguments-compiles.md)
- [Two refused pass-1 const contexts evaluated in place (enum values, global array sizes, top-level `#assert`) print only the first error](2026-10-16-pass1-in-place-const-refusals-swallow-the-next.md)
- [PE `sys_close` returns CloseHandle's BOOL (1 = closed, 0 = failed), so a failed close reads as success and every `< 0` test on it is dead](2026-10-16-pe-close-returns-closehandle-bool.md)
- [PE `xlseek` / `sys_lseek` on fd 0 / 1 / 2 fails -9: ELSEEK_PE passes the std fds as raw HANDLE values (EWRITE_PE / EREAD_PE / EFLUSHFB_PE map them through GetStdHandle)](2026-10-16-pe-lseek-std-fds-pass-raw-handle.md)
- [A struct field `p: *Box<Zork>` is never checked at its declaration — unused it compiles; each use reports the bad type argument again](2026-10-16-pointer-field-generic-type-args-read-only-at-use.md)
- [A refused const fn's definition check leaves the cascade latch on for its run-time body: a false "undefined variable" for a local const, and a later statement's error reported twice](2026-10-16-refused-const-fn-check-latch-leaks-into-its-body.md)
- [A scratch resolve keeps a predicted temp name that `_aw_open` skipped, so a kill unlinks a file the CLI did not create](2026-10-16-scratch-resolve-records-a-predicted-temp-name-it-did-not-create.md)
- [A struct literal's elements need no comma: `P { 3 4 }` and `P { b: 1 a: 2 }` compile](2026-10-16-struct-literal-elements-need-no-comma.md)
- [A trait member's `: Vec<..>` return compiles, while a fn's `: Vec<..>` return is refused "type 'Vec' cannot be a fn return type"](2026-10-16-trait-member-vec-return-accepted.md)
- [syscall_xlat_generated.sh and removed_symbol_census.sh stop without a verdict under `bash -eo pipefail` (a `grep -c` at a zero count; a `git tag … | head -1` taking SIGPIPE)](2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md)
- [A `var` with `:` and no type (`var b: = 0;`, `var G: ;`) is reported as "expected '=', got number 0"](2026-10-16-var-missing-annotation-reported-as-expected-equals.md)
- [A Vec element's generic struct is not checked against its bounds: `Vec<Box<Pt>>` with `struct Box<T: Show>` and no `impl Show for Pt` compiles](2026-10-16-vec-element-generic-struct-bound-unchecked.md)
- [Windows disallowed CTL: a signature-hash entry of 20, 32 or 64 bytes is not applied](2026-10-16-windows-disallowed-ctl-other-length-signature-hashes-unapplied.md)
- [x86 inline asm ignores the register operand of lgdt / lidt / invlpg / mov crN / ltr, and masks `int N` to 8 bits — each assembles a different instruction than its source names](2026-10-16-x86-asm-operands-ignored-lgdt-lidt-invlpg-mov-cr-ltr-int.md)
- [A declaration-zone struct literal of constants is baked into the image AND stored again at startup](2026-10-16-zone-struct-literal-baked-and-stored.md)
- [The 6.7.14 changes beyond the decisions' text — confirm or restore each](2026-10-17-6714-behaviour-changes-beyond-the-decisions-text.md)
- [`&(x)` reports "expected identifier, got '('" and then a false "undefined variable 'fn'" naming the program's first word](2026-10-17-address-of-parenthesised-name-false-second-error.md)
- [A bounded-forward judgement deeper than 64 generics silently answers "not bad": a valid 65+-deep forwarding chain is refused at a definition](2026-10-17-bounded-forward-judgement-capped-at-64-deep.md)
- [`var x: f64 = mkv(41, 7);` (a by-name call declared to return a vector) compiles and stores a word, where the method spelling is refused since 6.7.14](2026-10-17-by-name-vector-call-into-f64-declaration-stores-a-word.md)
- [A vector method on a CHAINED receiver — untyped `var v = w.s.mv();` binds one word (garbage, per target); the annotated `var v: f64v2 = w.s.mv();` is refused "got `w`"](2026-10-17-chained-receiver-vector-method-binds-a-word-annotated-refused.md)
- [cxvm hands the guest's x86-Linux syscall numbers to the host's `syscall()`, whose renumbering is built for the host stdlib's own numbers — on aarch64 Linux a guest `lseek` runs `getxattr` and a guest `fork` runs `close` (the parent takes the child branch), on arm64 macOS `kill` runs `lseek`, and several of D55's scalar-only calls SIGSYS-kill cxvm on the Macs](2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md)
- [cybs: at top level, a name that is a local of the last fn compiled is taken as known (the local table is not reset after a fn)](2026-10-17-cybs-top-level-name-of-last-fns-local-taken-as-known.md)
- [cyriusly_setup_bootstrap_and_env.sh C2 is red whenever the working tree's build/cycc differs from the committed one — its reference cyrfmt is built by `$CC`, the installed one by the `git archive HEAD` copy's compiler](2026-10-17-cyriusly-setup-gate-c2-red-when-worktree-compiler-differs-from-head.md)
- [A `struct` / `enum` / `union` / `trait` / `impl` declaration inside a block or a fn body is "unexpected struct" and a cascade](2026-10-17-declaration-inside-block-or-fn-body-cascades.md)
- [default_named_args_checked.sh stops without a verdict under `bash -eo pipefail` in its SC-lsp section (a `grep -c` over two files at a zero count)](2026-10-17-default-named-args-gate-stops-under-pipefail.md)
- [`*(&p)` of a typed pointer local loses p's pointee: `**(&p)` with `p: *f64v2` is no vector at any vector destination](2026-10-17-dereference-of-address-of-typed-pointer-local-loses-its-pointee.md)
- [`**pp += 1` through a `**S` is refused as "compound assignment to the struct 'pp' points at" — pp points at a pointer, not the struct](2026-10-17-double-pointer-compound-refusal-names-the-pointer-as-the-struct.md)
- [`gx<Box<i64>>(bx)` with `bx: Box<i64>` is refused "different struct type" — the explicit type argument mints `Box$i64`, the annotation binds the base `Box`](2026-10-17-explicit-all-i64-struct-instance-type-argument-mints-a-second-struct.md)
- [A call ABOVE a fn whose by-value / `*S` parameter names a struct declared BELOW that fn takes the pass-1 signature with no struct: the 16 / 24 B argument is pushed as its first word (SIGSEGV), a `*S` one is refused](2026-10-17-forward-call-struct-parameter-of-struct-declared-below-fn.md)
- [A call ABOVE a fn whose RETURN type names a struct declared BELOW that fn takes the pass-1 signature with no struct: `var t: Pq = mk(10);` faults (139) at 8, 16 and 24 B, an untyped `var t = mk(10);` is "no struct type in scope", and a struct named like a vector is refused "vector return type does not match"](2026-10-17-forward-call-struct-return-of-struct-declared-below-fn.md)
- [A warning inside a generic fn's body is printed once per instance (the 6.7.14 latch covers errors only)](2026-10-17-generic-body-warning-printed-once-per-instance.md)
- [A parenthesised or computed `**S` argument binds nothing in a generic `pp: **T` call — `st((pps))` runs the i64 base, `tg((pps))` faults](2026-10-17-generic-double-pointer-argument-in-parentheses-binds-nothing.md)
- [A generic fn's `pp: **Box<T>` parameter (T its own type parameter) is refused "unknown type 'T' as a type argument", where `p: *Box<T>` compiles](2026-10-17-generic-double-pointer-to-generic-struct-parameter-refused.md)
- [The generics refusals name a generic METHOD by its mangled fn name (`generic 'P_pick' has no i64 ... instance`, `generic 'P_bm': its type argument does not implement trait 'Show'`)](2026-10-17-generic-refusals-name-a-generic-method-by-its-mangled-name.md)
- [A `: T` generic that reaches a scalar instance, received into a struct-annotated local, is reported at the first field use as "no struct type in scope" — or not at all — rather than at the declaration](2026-10-17-generic-t-return-scalar-instance-into-struct-local-reported-at-use.md)
- [A generic's `ppp: ***T` called with no `<..>` runs the i64 base: `**ppp + 1` steps 8 and `take(***ppp)` faults, where `t3<P3>(ppps)` is right — DECISION](2026-10-17-generic-triple-pointer-parameter-carries-nothing.md)
- [A temporary taken while an `#inline` fn's arguments are evaluated lies past the frame — `id(a) + id(a + 1)` (a u128) reads 84 for 83](2026-10-17-inline-replay-argument-temps-lie-past-the-frame.md)
- [An `#inline` vector fn's refused call is followed by a refusal Windows does not print — the replay clears the panic latch on x86_64 / aarch64 / cx](2026-10-17-inline-replay-clears-panic-latch-pe-prints-one-error-fewer.md)
- [`t = p` / `t = *p` (p a `*Str`) and `t = if (c) { a } else { b }` (Str handles) into an inline `Str` still store one word, where `t = a` copies the header since 6.7.14](2026-10-17-inline-str-assigned-from-str-pointer-or-if-expression-stores-one-word.md)
- [An inline `Str` ASSIGNED into a `*Str` (`p = t`, `GP = t`, `GP = gt`) keeps its data word, where `var p: *Str = t;` takes the header since 6.7.14](2026-10-17-inline-str-assigned-into-str-pointer-keeps-data-word.md)
- [`var b: bool = fncall0(&isb);` with `isb(): bool` is refused "not a bool" where `var c: bool = isb();` compiles — a known `&f` callee's `: bool` result is an untyped word](2026-10-17-known-callee-bool-result-not-a-bool.md)
- [`*fncall0(&bp)` with `bp: *u8` reads a WORD, and `fncall0(&bp)[1]` is "cannot subscript ... it does not return a *T" — a known `&f` callee's `: *T` result carries T's step (6.7.14, D26) but not its element kind](2026-10-17-known-callee-narrow-pointer-result-deref-reads-a-word-and-subscript-refused.md)
- [A `struct` / `enum` refused as a declaration after the first top-level statement (D13 (a)) still cascades at each use of it](2026-10-17-late-declaration-refusal-cascades-at-its-uses.md)
- [A method call on a `Str` FIELD (`w.s.len()`, `w.s.clone()`, `w.s.eq(x)`) does not parse — "expected ';', got '.'"](2026-10-17-method-call-on-str-field-does-not-parse.md)
- [The mixed-return warning ("returns a `: stack` pair on another path but a SINGLE value here") never judges an impl method or an inherited trait default](2026-10-17-mixed-pair-return-warning-skips-impl-methods.md)
- [A const- or enum-NAMED (or `= 0`) declaration-zone redeclaration is ordered unlike a literal one: `var a = D; var b = a; var a = C;` gives b == D, though the guide says every read sees the last definition](2026-10-17-named-constant-redeclaration-ordered-unlike-a-literal.md)
- [No gate runs the .tcyr corpus under CYRIUS_IR=3 and CYRIUS_DCE=1 together](2026-10-17-no-gate-runs-the-corpus-under-ir3-and-dce-together.md)
- [A statement whose destination is parenthesised — `(*p) += 1;`, `(*(&s)) -= 1;`, `(n) = 7;` — is "unexpected '('"](2026-10-17-parenthesised-assignment-destination-is-unexpected-paren.md)
- [src/frontend/parse_fn.cyr is 3.3 KB under cyrfmt / cyrlint's 1028 KB read cap: past it both tools refuse the file and tracked_sources_canonically_formatted.sh goes RED](2026-10-17-parse-fn-source-near-cyrfmt-cyrlint-read-cap.md)
- [patra's suite on macOS: `patra_hdr_write: a refused sync is an error` fails — macOS syncs `/dev/null` successfully](2026-10-17-patra-failed-sync-row-assumes-dev-null-refuses-fsync-on-macos.md)
- [patra's other harnesses still open `/tmp/...` paths: on Windows `patra_uninit.tcyr` fails 3 of 18 and `patra_raw_include.tcyr` 6 of 6](2026-10-17-patra-other-suites-open-tmp-paths-on-windows.md)
- [The pointer-to-pointer pin intern is a linear search: compile time grows quadratically in distinct `**T` pointees](2026-10-17-pointer-to-pointer-pin-intern-is-a-linear-search.md)
- [`#pure`'s `#io` / `#alloc` check is silent for a generic callee called through an instance (`h<i32>(1)`)](2026-10-17-pure-check-misses-explicit-generic-instance-callee.md)
- [A redeclared global whose initializer is a const- or enum-NAMED constant of another value is never compared — `var a = 3; var a = C;` compiles silently](2026-10-17-redeclared-global-named-constant-value-never-compared.md)
- [A variable whose annotation type was refused ("unknown type 'Foo'") cascades "no struct type in scope" at each `.field` use](2026-10-17-refused-annotation-type-cascades-at-field-uses.md)
- [`regression_pipe_to_bin` kills its CALLER with SIGPIPE (exit 141) when the child exits without reading its stdin — the check driver died mid-run](2026-10-17-regression-pipe-to-bin-dies-of-sigpipe.md)
- [A body ending in an infinite loop whose only exits are `ret2(..);` statements is not counted: `var a, b, c = g2(1);` binds a stale register](2026-10-17-ret2-only-exits-in-a-loop-ending-body-not-counted.md)
- [`return &x;` in a fn returning a struct, with `x` a scalar, a `*i64` / `*V`, a `**S` or a `Str` handle: at 8 B the slot's ADDRESS is the struct's word; over 8 B refused in other words](2026-10-17-return-address-of-scalar-or-non-struct-pointer-slot-in-struct-fn.md)
- [stdlib_modules_self_sufficient.sh stops after axis 4 with rc 42 under `bash -eo pipefail` (axis 5's probe exit trips `set -e`)](2026-10-17-stdlib-modules-self-sufficient-gate-stops-under-pipefail.md)
- [A `*Str` dereference into a `Str` parameter (`str_len(*p)`, `f(**pp)`) passes the header's first word (its data pointer), not the header](2026-10-17-str-pointer-dereference-into-str-parameter-passes-data-word.md)
- [`var s: *u8 = "abc" + 1;` and `= ("abc");` still warn "assigning non-pointer to typed pointer" — 6.7.14 exempts a string literal into a byte pointer only when it stands alone before the `;`](2026-10-17-string-literal-expression-into-byte-pointer-still-warns.md)
- [The struct assignment's and the small-struct return's refusals name a method result by its mangled fn name (`'Pt_dup'`, `` `Pt_t1` ``)](2026-10-17-struct-receive-and-return-refusals-name-method-result-by-mangled-name.md)
- [`p = mkp();` into a `*i64` / `x = mkp();` into an untyped scalar — a struct result over 8 B ASSIGNED where D27 does not reach keeps its first word (the `*i64` one SIGSEGVs)](2026-10-17-struct-result-assigned-to-pointer-or-untyped-scalar-keeps-first-word.md)
- [`--syntax-only`: `gp().n = 5;` with `gp` in a sibling module is a false "the result is a temporary" (a for step too)](2026-10-17-syntax-only-sibling-ptr-call-field-store-false-temporary.md)
- [Native TLS: bytes after the extension block still pass in the 1.2 client's ServerHello and the servers' ClientHello parses](2026-10-17-tls-native-hello-bytes-after-extension-block-1-2-sh-and-server-ch.md)
- [A top-level untyped `var G = B.mk1();` / `= A + C;` / `= fncall0(&mk1);` with a struct result binds no struct — 8 B: `G.a` is "no struct type in scope for 'G'"; 9-16 B: G silently holds the first word — where 6.7.14's D29 / D30 bind (8 B) or refuse (9-16 B) the free call `var G = mk1();`](2026-10-17-top-level-untyped-method-operator-or-known-callee-struct-result-keeps-word.md)
- [A top-level untyped `var w = mkv(..);` / `var v = s.mv();` (and `var x: i64 = mkv(..);`) binds one word of a vector result, silently, differently per target](2026-10-17-top-level-untyped-vector-call-or-method-result-binds-a-word.md)
- [A top-level untyped `var s = (mks());` with a `: Str` call is not routed as a Str — `println(s)` prints the header's bytes, where `var t = mks();` beside it prints the string](2026-10-17-top-level-wrapped-str-call-global-prints-header-bytes.md)
- [A top-level `o.mk().p[0] = 5;` (a method returning a struct by value) is reported twice, the second a false "cannot subscript field 'p': it is not a *T field"](2026-10-17-toplevel-by-value-method-result-field-subscript-two-errors.md)
- [A declaration-zone `var H: Str = gt;` with gt declared BELOW it is still refused "cannot copy-init", though since 6.7.14 the line binds a handle (no copy)](2026-10-17-toplevel-str-handle-from-inline-str-global-declared-below-refused-as-copy-init.md)
- [A trait member's `: u128` return is accepted while every body of it is refused; and an impl method's return type is never checked against its trait member's](2026-10-17-trait-member-u128-return-accepted-and-impl-return-unchecked.md)
- [Into a tuple parameter, a negated literal, a bool literal or a constant expression still compiles and is dereferenced as the tuple's address — `take(-5)`, `take((-5))`, `take(true)`, `take(5 + 0)` — where `take(5)` is refused (D44)](2026-10-17-tuple-parameter-negated-bool-or-constant-expression-literal-dereferenced.md)
- [A `u128` parameter with a default gives two errors — "it takes no default" and the D10 (a) parameter refusal](2026-10-17-u128-parameter-with-default-reported-twice.md)
- [`*pu` through a `*u128` reads and writes only the low 8 bytes, silently — a declaration, a comparison, an if-expression branch and a store — where `pu[0]` is refused by name](2026-10-17-u128-pointer-dereference-reads-and-writes-low-word.md)
- [`var t: P = (P { 5, 6 };` (the wrap's `)` missing) is reported as a struct literal outside an initializer, then "expected ')'"](2026-10-17-unclosed-wrap-around-struct-literal-initializer-names-the-literal-rule.md)
- [`undefd().n += 1;` (a field of an UNDEFINED fn's result) is "expected ';', got '.'", and as a for step "expected '=', got '('" — neither names the undefined fn](2026-10-17-undefined-callee-field-assignment-names-no-undefined-fn.md)
- [A vector call assigned to a scalar GLOBAL (by name, a method, `fncallN(&f, ..)`), or `fncallN(&f, ..)` / `callptr(&f, ..)` into a scalar LOCAL, stores one word, silently, differently per target — where `x = mkv(41, 7);` into a local is refused](2026-10-17-vector-call-or-method-assigned-to-scalar-global-stores-a-word.md)
- [A `*V` dereference refused into another pointer kind is named by its operand's LAST name, not as written — `ri(*gp(pb))` prints '*pb', `ri(*&b)` '*b', `ri(*h.pv)` '*pv', `ri(**ppb)` '*ppb'](2026-10-17-vector-dereference-refusal-names-operand-last-name.md)
- [`l = *pp` / `G = *pp` / `*q = *pp` (pp a `**S`) store the pointer word where `l = p` copies the struct, and `var t: S = *pp;` binds a handle where `var t: S = p;` copies](2026-10-17-whole-source-copy-from-double-pointer-single-deref-stores-pointer-word.md)
- [A wrapped by-name call or method call of ANOTHER vector into a vector local — `var v: f64v2 = (mk4(41));`, `(s.mv())` — is refused in the receive's generic words ("got `(...)`"), not as the type mismatch the unwrapped call gets](2026-10-17-wrapped-by-name-or-method-call-of-another-vector-into-vector-local-generic-words.md)
- [`h.p = (two(3));` — a parenthesised multi-value call stored into a tuple FIELD — is refused twice: R17's "bind it first" and then R12's "not a tuple"](2026-10-17-wrapped-multi-value-call-into-tuple-field-reports-twice.md)
- [A wrapped vector call — by name or a method — into an untyped or a scalar declaration binds a word, and a method's `s.mv() + 1` into `: i64` is not refused](2026-10-17-wrapped-vector-call-into-untyped-or-scalar-declaration-binds-a-word.md)
- [A declaration-zone untyped `var x = mkg1(33);` whose generic callee returns a generic struct instance (`: G1<T>`) binds nothing — `x.v` is "no struct type in scope for 'x'" (16 B: the D30 refusal and then that error) — where the same line after the first statement binds the instance (D29 (a))](2026-10-17-zone-untyped-generic-struct-instance-call-binds-nothing.md)
- [aarch64 Linux `sys_dup2(fd, fd)` answers -22 (EINVAL) where x86_64 answers fd: the aarch64 peer issues dup3(old, new, 0), which refuses old == new](2026-10-18-aarch64-sys-dup2-same-fd-answers-einval.md)
- [patra `fuzz/fuzz_bytes.fcyr` plants its chain corruption at a heap address used as a page number — it has tested nothing since patra 1.12.8, and on Windows hardware it writes a ~50 GB non-sparse file](2026-10-18-patra-fuzz-bytes-plants-corruption-at-a-heap-address.md)

**6.7.16 — the full security audit + the refactor / optimization review** (3)

- [A tail call that copies a by-value struct argument is an ordinary call — a per-fn "writes no memory" analysis would win its `jmp` back](2026-10-09-tail-call-by-value-copy-needs-effect-analysis.md)
- [The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line)](2026-10-13-self-compile-prints-large-static-advisory.md)
- [Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end](2026-10-15-windows-protectedroots-flag1-user-root-unverified.md)

**Open by design — placed arcs, not bugs** (5)

- [A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10)](2026-10-08-constant-if-arms-not-folded.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](2026-10-08-lib-public-constants-const-migration.md)
- [`cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read](2026-10-08-manifest-build-profiles-and-target-unread.md)
- [Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1](2026-10-08-native-tls-capability-limits.md)
- [`cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible](2026-10-08-poison-guard-pages-unbuilt.md)

**Unplaced** (54)

- [The seed (`bootstrap/asm`) truncates input at 131,072 B, overruns its 512-label table and its 65,536 B CODE buffer — all unchecked](2026-10-08-seed-asm-silent-caps-input-labels-code.md)
- [sigil (the crypto / trust fold) has no runtime logging: none of its 68 `src/` files calls sakshi](2026-10-12-sigil-has-no-runtime-logging.md)
- [cybs names neither the construct it refused nor the file and line](2026-10-13-cybs-per-construct-refusal-and-file-line.md)
- [asm_barrier_options.tcyr's header says a wrong barrier word faults (SIGILL), but a wrong option CRm runs as the full-system barrier](2026-10-18-asm-barrier-options-tcyr-header-claims-a-wrong-word-faults.md)
- [An asm `param_load(reg, idx)` reads its register by the first letters: `param_load(raxx, 0)` is rax, `param_load(r8d, 0)` a 64-bit r8 load](2026-10-18-asm-param-load-register-read-by-first-letters.md)
- [A bare `var c;` (and `var c: ;`) in a fn or after the first statement reads the NEXT statement as its initializer — "undefined variable" follows](2026-10-18-bare-declaration-refusal-reads-next-statement-as-initializer.md)
- [cli_temp_dir_no_leak.sh stops without a verdict under `bash -eo pipefail`: a `kill` of a stand-in that has already exited ends the run](2026-10-18-cli-temp-dir-gate-stops-under-pipefail.md)
- [A `--parse-ts` / `--lex-ts` / `--emit-js <file>` path is cut at the 255-byte /proc/self/cmdline read, and the cut name is opened](2026-10-18-cmdline-read-cuts-ts-path-at-255-bytes.md)
- [A commaless tuple literal is reported as "expected ',' between struct literal elements"](2026-10-18-commaless-tuple-literal-named-as-struct-literal.md)
- [A subscript of a const, and an explicit generic method call `a.m<T>(..)` in a const fn, name the wrong rule (one with a false "undefined variable")](2026-10-18-const-subscript-and-generic-method-in-const-fn-misnamed.md)
- [tests/tcyr/crossos/audit_walk_fifo.tcyr on cx ends `2 passed, 6 failed` on every host: getdents64 (217) and mknodat (259) answer -38 on cxvm (6.7.14's D55 — untranslated pointer calls), so a directory walk sees no entries and the FIFO fixture is never made; no gate runs the file on cx](2026-10-18-cx-audit-walk-fifo-getdents-mknodat-refused.md)
- [On a Windows host's cxvm the crossos file-fixture rows fail: open_flags_per_target / atomic_write_temp_exclusive put their fixtures under `/tmp/` (cx is not `CYRIUS_TARGET_WIN`, and `C:\tmp` does not exist), and file_create_exclusive over a directory answers Windows' -13 to a guest whose lib only classifies it under `CYRIUS_TARGET_WIN`](2026-10-18-cx-crossos-rows-on-a-windows-host-miss-tmp-and-eacces.md)
- [On a macOS host cxvm hands the cx guest Darwin's errno values: `open(link, O_RDONLY|O_NOFOLLOW)` answers -62 (Darwin's ELOOP) where the .cyx ABI (x86_64 Linux) and every other host say -40](2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md)
- [cxvm's F_GETFL drops O_LARGEFILE off x86_64 Linux: the x86 cxvm answers 0x8001 for fd 1, the aarch64 and macOS ones 0x1](2026-10-18-cxvm-fgetfl-drops-o-largefile-off-x86-linux.md)
- [cxvm on macOS passes a guest's x86-Linux signal number to kill unmapped: SIGUSR1 10 is Darwin's SIGBUS, SIGCHLD 17 its SIGSTOP, SIGSTOP 19 its SIGCONT](2026-10-18-cxvm-macos-kill-signal-numbers-unmapped.md)
- [docs/doc-health.md still names the renamed gate toolchain/emit_js_refused_off_x86_linux.sh as a live pin](2026-10-18-doc-health-names-renamed-emit-js-gate.md)
- [A `**G<..>` parameter's type-argument refusal swallows the next parameter's error (`fn ap(p: **Box<Zork>, q: Nope)` reports one line)](2026-10-18-double-pointer-generic-parameter-refusal-swallows-the-next.md)
- [Forming a dyn compares a method's types token by token: `Box<i64>` against `Box`, and `Box<Box<i64>>` against `Box<Box<i64> >`, are "the return type differs" / "parameter has another type"](2026-10-18-dyn-pair-check-compares-type-spellings-token-by-token.md)
- [An enum's members need no separator: `enum E { A B }` and `enum E { A = 1 B = 5 }` compile](2026-10-18-enum-members-need-no-separator.md)
- [The explicit method spelling `v.m<..>(..)` escapes a bound's contract: a method no trait of the bound declares, called with type arguments on a bounded `T` (or a carrier's `T` field), compiles](2026-10-18-explicit-method-type-args-escape-bound-contract.md)
- [A float-literal redeclaration of a declaration-zone global keeps declaration order, where an integer constant redeclaration is the value from program start](2026-10-18-float-literal-global-redeclaration-keeps-declaration-order.md)
- [A call ABOVE a fn whose `: *S` / `: **S` / `: *Box<S>` / `: **Box<S>` RETURN names a struct declared BELOW that fn reads pass 1's record, which has no pointee struct: `var t: Later = *mk();` and `take(*mk())` fault (139)](2026-10-18-forward-call-pointer-return-of-struct-declared-below-fn.md)
- [A closure's captured `f64` passed to a generic's `x: T` binds i64, where the f64 local it captures binds f64 — `|| gid(h) * 2.0` multiplies the double's bits — DECISION](2026-10-18-generic-captured-f64-binds-i64-through-plain-parameter.md)
- [Compile time grows ~4x per doubling of the number of generic fn definitions (1500 -> 3000 `fn oK<T>(x: T)`: 439 -> 1,972 ms), where non-generic fns are linear](2026-10-18-generic-definitions-compile-time-superlinear.md)
- [The bounded-forward refusal names the generic METHOD it forwards to by its mangled name (`it forwards its type parameter to 'P_bk'`, and its note)](2026-10-18-generic-forward-refusal-names-forwarded-method-by-mangled-name.md)
- [A chain of more than ~120 generics forwarding their `T`, called at a non-i64 type, is refused "nesting too deep (over 256 levels)"](2026-10-18-generic-forwarding-chain-hits-instance-nesting-cap.md)
- [A generic's multi-value return element typed by its type parameter (`fn mm2<V>(x: V): (V, i64)`) binds i64 in a destructure at the f64 instance: `var a, b = mm2<f64>(h);` makes `a` an integer word](2026-10-18-generic-multi-value-type-parameter-element-binds-i64.md)
- [The stub scan's token binding misses a `pp: **T` argument (6.7.14's D40) and a generic `: *T` call through `p: *T`: `var r = gd2(&GPP); r.pick(t)` in a generic is refused naming the stub method](2026-10-18-generic-token-scans-miss-double-pointer-and-generic-pointer-call-binding.md)
- [A generic trait member's own type parameter is "unknown type" anywhere after a `*fn(..)` in its signature (`fn g<U>(self, c: *fn(i64): i64, u: U): U;`)](2026-10-18-generic-trait-member-type-parameter-unknown-after-fn-pointer-type.md)
- [A global `*Foo` whose `Foo` is refused reads its fields as the program's FIRST struct: "unknown field 'y' on struct 'var'"](2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md)
- [The guide's Windows failure table puts the 6.7.15 close answer in its `Windows 6.7.14` column](2026-10-18-guide-windows-failure-table-close-cell-in-6-7-14-column.md)
- [`impl X for T`'s check stops at the first method whose return type differs: a second mismatch, or a required method left out, is not reported in that compile](2026-10-18-impl-check-stops-at-first-differing-return.md)
- [In an x86 `kernel;` build a float global whose constant initializer mixes an integer or enum operand into f64 arithmetic (`= 1.5 + 1`, `= 1.5 * E.A`) is still a late store](2026-10-18-kernel-float-global-mixed-int-operand-left-late.md)
- [Only the first bound-contract refusal of a compile prints: every later "method 'm' is not in the bound on type parameter 'T'" (another generic, or the same body) is swallowed by the first's panic latch](2026-10-18-later-bound-contract-refusals-swallowed-in-pass-one.md)
- [An array-list redeclaration over a const- or enum-NAMED scalar constant does not keep the bytes it does not list](2026-10-18-list-redeclaration-over-named-scalar-constant-loses-unlisted-bytes.md)
- [A `mod` / `use` / `pub` / `public` inside a fn body or a block is "unexpected <token>", not the declaration rule; a `pub fn` there is two errors](2026-10-18-mod-use-pub-inside-fn-body-or-block-named-by-token.md)
- [A generic multi-value fn's wrong-count `return` is refused once per instance, each line naming its mangled instance (`'gr$P' returns 2 values - return (a, b)`)](2026-10-18-multi-value-return-count-refusal-printed-per-instance-by-mangled-name.md)
- [`Name<..>` on a non-generic struct or a scalar is still unread (or refused with other words) in the positions 6.7.15's D6 readers do not reach](2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md)
- [PE `sys_close` and `sys_ftruncate` on fd 0 / 1 / 2 pass the raw HANDLE values 0 / 1 / 2 to kernel32 (no GetStdHandle map): close(2) answers -9 and stderr stays open, ftruncate(1) of a redirected stdout fails](2026-10-18-pe-close-and-ftruncate-pass-std-fds-raw.md)
- [PE `xlseek` / `sys_lseek` on a PIPE or console handle succeeds on Windows (answers the asked offset, the stream does not move) where Linux and macOS answer -ESPIPE (-29); wine answers -1](2026-10-18-pe-seek-on-pipe-or-console-std-handle-succeeds.md)
- [redefinition_layout_and_enum_over_var.sh stops without a verdict under `bash -eo pipefail` (a `grep -c` at a zero count)](2026-10-18-redefinition-layout-gate-stops-under-pipefail.md)
- [A refused `var` annotation, then a tuple literal initializer, cascades "a tuple literal cannot initialize 'b' - its declared type is not a tuple"](2026-10-18-refused-annotation-cascades-tuple-literal-initializer.md)
- [Uses of a refused declaration's names that 6.7.15's stand-downs do not reach: const contexts, a trait bound, an uninitialized `var q: Q;`, a use before the declaration](2026-10-18-refused-declaration-names-cascade-in-const-contexts-bounds-and-uninit.md)
- [A scratch resolve keeps each copy's temp name recorded after the rename, so a kill unlinks a file put there later](2026-10-18-scratch-resolve-keeps-a-renamed-temp-recorded.md)
- [A second refused `case` label is reported as "expected ':', got identifier 'ww'" instead of its own refusal](2026-10-18-second-refused-case-label-reported-as-expected-colon.md)
- [Decision: a redeclared struct / tuple literal keeps declaration order, while 6.7.15's D2 (a) makes every scalar constant redeclaration the value from program start](2026-10-18-struct-tuple-literal-redeclaration-order-vs-d2.md)
- [A syscall-number warning in an `#inline` fn's body prints once for the definition and again for every call](2026-10-18-syscall-warnings-repeat-once-per-inline-replay.md)
- [A third type parameter is accepted at the declaration and silently unrecorded; every explicit three-argument use is a parse error](2026-10-18-third-type-parameter-accepted-and-unrecorded.md)
- [Native TLS 1.2 server: a ClientHello with no or an overrunning compression_methods, or an extension that overruns its block, still negotiates; its short-message refusals send no alert](2026-10-18-tls-native-1-2-server-clienthello-other-leniencies.md)
- [A trait member's `cb: *fn(i64): u128` parameter is refused "`u128` is not supported as a parameter type yet", where a fn's compiles](2026-10-18-trait-member-fn-pointer-parameter-u128-return-refused.md)
- [A trait member's return type a fn's return refuses (`u8`..`u64`, `f32`, an enum, `*fn(..)`) still compiles at the trait](2026-10-18-trait-member-return-outside-fn-return-set-accepted.md)
- [A Vec element whose generic struct takes another generic struct's instance (`Vec<Box<Box<R>>>`) is not judged against the outer struct's bound](2026-10-18-vec-element-nested-instance-argument-bound-unjudged.md)
- [Windows disallowed CTL: a 16-byte entry is read only as a public-key MD5, never as an MD2 / MD5-signed certificate's signature hash](2026-10-18-windows-ctl-16-byte-entry-as-md5-signature-hash.md)
- [The declaration zone's replay reports only the FIRST latched error: every later zone declaration's error is silent](2026-10-18-zone-replay-reports-only-first-latched-error.md)

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
