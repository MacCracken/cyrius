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


**6.7.16 — Break 2, repair 6 (added at the 6.7.15 wave-1 integration, 2026-10-18): what 6.7.15 files** (104)

- [Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end](2026-10-15-windows-protectedroots-flag1-user-root-unverified.md)
- [asm_barrier_options.tcyr's header says a wrong barrier word faults (SIGILL), but a wrong option CRm runs as the full-system barrier](2026-10-18-asm-barrier-options-tcyr-header-claims-a-wrong-word-faults.md)
- [An asm `param_load(reg, idx)` reads its register by the first letters: `param_load(raxx, 0)` is rax, `param_load(r8d, 0)` a 64-bit r8 load](2026-10-18-asm-param-load-register-read-by-first-letters.md)
- [A bare `var c;` (and `var c: ;`) in a fn or after the first statement reads the NEXT statement as its initializer — "undefined variable" follows](2026-10-18-bare-declaration-refusal-reads-next-statement-as-initializer.md)
- [cbt/ and programs/ child redirects run `sys_dup2(fd, N); sys_close(fd)` with no same-fd guard: `cyrius build --target=js` with stdout closed fails "could not write the output (0 of 29 bytes): errno 9" — the lib/ half was fixed in 6.7.15, these copies were not](2026-10-18-cbt-and-programs-child-redirects-close-their-own-std-fd.md)
- [cli_temp_dir_no_leak.sh stops without a verdict under `bash -eo pipefail`: a `kill` of a stand-in that has already exited ends the run](2026-10-18-cli-temp-dir-gate-stops-under-pipefail.md)
- [A closure's parameter keeps the type an EARLIER fn's local left in its frame slot — `|x| { return x.b; }` compiles as a `*Q` read (SIGSEGV) and `x = mkp();` copies through it](2026-10-18-closure-parameter-keeps-an-earlier-fns-slot-type.md)
- [A `--parse-ts` / `--lex-ts` / `--emit-js <file>` path is cut at the 255-byte /proc/self/cmdline read, and the cut name is opened](2026-10-18-cmdline-read-cuts-ts-path-at-255-bytes.md)
- [A commaless tuple literal is reported as "expected ',' between struct literal elements"](2026-10-18-commaless-tuple-literal-named-as-struct-literal.md)
- [A subscript of a const, and an explicit generic method call `a.m<T>(..)` in a const fn, name the wrong rule (one with a false "undefined variable")](2026-10-18-const-subscript-and-generic-method-in-const-fn-misnamed.md)
- [tests/tcyr/crossos/audit_walk_fifo.tcyr on cx ends `2 passed, 6 failed` on every host: getdents64 (217) and mknodat (259) answer -38 on cxvm (6.7.14's D55 — untranslated pointer calls), so a directory walk sees no entries and the FIFO fixture is never made; no gate runs the file on cx](2026-10-18-cx-audit-walk-fifo-getdents-mknodat-refused.md)
- [On a Windows host's cxvm the crossos file-fixture rows fail: open_flags_per_target / atomic_write_temp_exclusive put their fixtures under `/tmp/` (cx is not `CYRIUS_TARGET_WIN`, and `C:\tmp` does not exist), and file_create_exclusive over a directory answers Windows' -13 to a guest whose lib only classifies it under `CYRIUS_TARGET_WIN`](2026-10-18-cx-crossos-rows-on-a-windows-host-miss-tmp-and-eacces.md)
- [The cx compiler under `--syntax-only` refuses every call to a fn this file does not define ("undefined function(s) called (cx backend)")](2026-10-18-cx-syntax-only-refuses-sibling-module-calls.md)
- [On a macOS host cxvm hands the cx guest Darwin's errno values: `open(link, O_RDONLY|O_NOFOLLOW)` answers -62 (Darwin's ELOOP) where the .cyx ABI (x86_64 Linux) and every other host say -40](2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md)
- [cxvm's F_GETFL drops O_LARGEFILE off x86_64 Linux: the x86 cxvm answers 0x8001 for fd 1, the aarch64 and macOS ones 0x1](2026-10-18-cxvm-fgetfl-drops-o-largefile-off-x86-linux.md)
- [cxvm on macOS passes a guest's x86-Linux signal number to kill unmapped: SIGUSR1 10 is Darwin's SIGBUS, SIGCHLD 17 its SIGSTOP, SIGSTOP 19 its SIGCONT](2026-10-18-cxvm-macos-kill-signal-numbers-unmapped.md)
- [`*(&pi) += 1` of a typed pointer steps one byte, where `*(&pi) = *(&pi) + 1` (6.7.15's D21) and `pi += 1` step the element; and `*(&GQ)` of a packed `i32` global reads 8 bytes](2026-10-18-dereference-of-address-of-compound-assignment-steps-one-byte.md)
- [docs/doc-health.md still names the renamed gate toolchain/emit_js_refused_off_x86_linux.sh as a live pin](2026-10-18-doc-health-names-renamed-emit-js-gate.md)
- [A `**G<..>` parameter's type-argument refusal swallows the next parameter's error (`fn ap(p: **Box<Zork>, q: Nope)` reports one line)](2026-10-18-double-pointer-generic-parameter-refusal-swallows-the-next.md)
- [Forming a dyn compares a method's types token by token: `Box<i64>` against `Box`, and `Box<Box<i64>>` against `Box<Box<i64> >`, are "the return type differs" / "parameter has another type"](2026-10-18-dyn-pair-check-compares-type-spellings-token-by-token.md)
- [An enum's members need no separator: `enum E { A B }` and `enum E { A = 1 B = 5 }` compile](2026-10-18-enum-members-need-no-separator.md)
- [Excess type arguments to a generic struct are accepted silently — `var b: Box<i64, i64>;` with `struct Box<T>` compiles](2026-10-18-excess-type-arguments-to-generic-struct-accepted.md)
- [The explicit method spelling `v.m<..>(..)` escapes a bound's contract: a method no trait of the bound declares, called with type arguments on a bounded `T` (or a carrier's `T` field), compiles](2026-10-18-explicit-method-type-args-escape-bound-contract.md)
- [A `.field` of an undefined fn's result after an earlier plain call to it reads "it does not return a struct"](2026-10-18-field-of-call-registered-undefined-fn-says-does-not-return-a-struct.md)
- [A float-literal redeclaration of a declaration-zone global keeps declaration order, where an integer constant redeclaration is the value from program start](2026-10-18-float-literal-global-redeclaration-keeps-declaration-order.md)
- [A generic `: S` fn's `return &n;` (n a local or parameter) is not judged in the generic's BASE, which is its `T = i64` instance — `h(3)` alone still returns the slot's address as the struct](2026-10-18-generic-base-return-address-of-local-unjudged-at-i64.md)
- [A closure's captured `f64` passed to a generic's `x: T` binds i64, where the f64 local it captures binds f64 — `|| gid(h) * 2.0` multiplies the double's bits — DECISION](2026-10-18-generic-captured-f64-binds-i64-through-plain-parameter.md)
- [Compile time grows ~4x per doubling of the number of generic fn definitions (1500 -> 3000 `fn oK<T>(x: T)`: 439 -> 1,972 ms), where non-generic fns are linear](2026-10-18-generic-definitions-compile-time-superlinear.md)
- [A generic's `pp: **Box<T>` parameter infers no `T` from a `**Box<Pt>` argument: `nb(&q)` runs the `i64` base and reads `Box<Pt>.n` at `Box<i64>`'s offset](2026-10-18-generic-double-pointer-generic-struct-parameter-infers-nothing.md)
- [The bounded-forward refusal names the generic METHOD it forwards to by its mangled name (`it forwards its type parameter to 'P_bk'`, and its note)](2026-10-18-generic-forward-refusal-names-forwarded-method-by-mangled-name.md)
- [A chain of more than ~120 generics forwarding their `T`, called at a non-i64 type, is refused "nesting too deep (over 256 levels)"](2026-10-18-generic-forwarding-chain-hits-instance-nesting-cap.md)
- [`var y: T = mkp();` (or `y = mkp();`, `p = mkp();` into a `p: *T`) inside a generic fn called with `T = i64` / `u8` keeps the struct's first word — D24 / D27 / D32 never judge a scalar instance's `T`](2026-10-18-generic-instance-t-annotation-takes-struct-first-word.md)
- [A generic method on a FIELD-CHAIN receiver inside a closure, given the closure's own parameter, binds T to the captured head's struct (`|k| w.s.gs(k)` calls `S_gs` at T = W: "undefined function 'W_add'")](2026-10-18-generic-method-on-field-chain-in-closure-binds-captured-struct.md)
- [A generic's multi-value return element typed by its type parameter (`fn mm2<V>(x: V): (V, i64)`) binds i64 in a destructure at the f64 instance: `var a, b = mm2<f64>(h);` makes `a` an integer word](2026-10-18-generic-multi-value-type-parameter-element-binds-i64.md)
- [A generic whose body writes a field of a `Box<T>` field (`g.v.v = v` with `g: G1<Box<T>>`) is judged a stub: `mkn<i32>(33)` is refused "generic 'mkn' has no i64 (or other scalar) instance: it uses its type parameter as a struct", then "expected ';', got '.'" at `x.v.v`](2026-10-18-generic-nested-instance-field-of-field-judged-a-stub.md)
- [A `*Str` dereference into a generic's `x: T` with T = `Str` (`gg<Str>(*p)`, inferred `gg(*p)`) passes the header's data word](2026-10-18-generic-str-instance-dereference-argument-passes-data-word.md)
- [The stub scan's token binding misses a `pp: **T` argument (6.7.14's D40) and a generic `: *T` call through `p: *T`: `var r = gd2(&GPP); r.pick(t)` in a generic is refused naming the stub method](2026-10-18-generic-token-scans-miss-double-pointer-and-generic-pointer-call-binding.md)
- [A generic trait member's own type parameter is "unknown type" anywhere after a `*fn(..)` in its signature (`fn g<U>(self, c: *fn(i64): i64, u: U): U;`)](2026-10-18-generic-trait-member-type-parameter-unknown-after-fn-pointer-type.md)
- [A global `*Foo` whose `Foo` is refused reads its fields as the program's FIRST struct: "unknown field 'y' on struct 'var'"](2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md)
- [The guide's Windows failure table puts the 6.7.15 close answer in its `Windows 6.7.14` column](2026-10-18-guide-windows-failure-table-close-cell-in-6-7-14-column.md)
- [An `impl T { fn m(self) .. }` written ABOVE `struct T` leaves the untyped `self` with no struct: `self.b` is refused "no struct type in scope for 'self'"](2026-10-18-impl-above-its-struct-untyped-self-unresolved.md)
- [`impl X for T`'s check stops at the first method whose return type differs: a second mismatch, or a required method left out, is not reported in that compile](2026-10-18-impl-check-stops-at-first-differing-return.md)
- [A refusal latched inside an expression statement that parsed to its own `;` swallows the NEXT statement and its first error](2026-10-18-in-sync-refusal-in-assignment-swallows-next-statement.md)
- [`t = *pp` (pp a `**Str`, so `*pp` is a `*Str`) into an inline `Str` still stores one word, where `t = p` copies since 6.7.15's D14](2026-10-18-inline-str-from-double-str-pointer-single-deref-stores-one-word.md)
- [An inline `Str` assigned into a `*Str` FIELD or through a `**Str` (`w.p = gt`, `GW.p = gt`, `pw.p = gt`, `*pp = gt`) still stores the data word](2026-10-18-inline-str-into-str-pointer-field-or-double-pointer-keeps-data-word.md)
- [`mulh64(a, b);` / `sizeof(T);` as a bare statement is a call to an undefined fn — with --allow-undef it builds and traps](2026-10-18-intrinsic-as-bare-statement-is-undefined-function.md)
- [In an x86 `kernel;` build a float global whose constant initializer mixes an integer or enum operand into f64 arithmetic (`= 1.5 + 1`, `= 1.5 * E.A`) is still a late store](2026-10-18-kernel-float-global-mixed-int-operand-left-late.md)
- [Only the first bound-contract refusal of a compile prints: every later "method 'm' is not in the bound on type parameter 'T'" (another generic, or the same body) is swallowed by the first's panic latch](2026-10-18-later-bound-contract-refusals-swallowed-in-pass-one.md)
- [An array-list redeclaration over a const- or enum-NAMED scalar constant does not keep the bytes it does not list](2026-10-18-list-redeclaration-over-named-scalar-constant-loses-unlisted-bytes.md)
- [The mixed `: stack` pair / single-value return warning for a trait default inherited by several impls names the first impl (`Pt.qd`), not the trait](2026-10-18-mixed-return-warning-trait-default-names-first-impl.md)
- [A `mod` / `use` / `pub` / `public` inside a fn body or a block is "unexpected <token>", not the declaration rule; a `pub fn` there is two errors](2026-10-18-mod-use-pub-inside-fn-body-or-block-named-by-token.md)
- [A generic multi-value fn's wrong-count `return` is refused once per instance, each line naming its mangled instance (`'gr$P' returns 2 values - return (a, b)`)](2026-10-18-multi-value-return-count-refusal-printed-per-instance-by-mangled-name.md)
- [`Name<..>` on a non-generic struct or a scalar is still unread (or refused with other words) in the positions 6.7.15's D6 readers do not reach](2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md)
- [An operator after a by-name vector call into a vector local (`var w = mk2(41, 7) + 1;`, `: f64v2`, `w = ..`) is dropped silently on x86_64 / aarch64, applied to a lane on cx, and a parse error on Windows](2026-10-18-operator-after-vector-call-into-vector-local-dropped.md)
- [A 9-16 B struct fn's `return E;` with a malformed or undefined E reports the pair class's refusal AND E's own error — `return zz;` is two errors, `return &(q);` two](2026-10-18-pair-class-return-refusal-beside-the-values-own-error.md)
- [`(fncall0(&gp)).b` and `(*fncall0(&gp)).b` with `gp: *P2` are refused "the value in these parentheses is not a struct" where `fncall0(&gp).b`, `(gp()).b` and `(*gp()).b` read the field](2026-10-18-parenthesised-known-callee-pointer-to-struct-field-refused.md)
- [`var p: *i64 = (0);`, `p = (0);` and a zone `var G: *i64 = (0);` warn "assigning non-pointer to typed pointer", where `= 0;` is quiet](2026-10-18-parenthesised-null-literal-into-typed-pointer-warns.md)
- [patra: `patra_insert_row` accepts a NEGATIVE BYTES / TEXT length with `PATRA_OK` and stores it raw; since 1.16.5 that cell reads `PATRA_ERR_PAGE` while `patra_result_get_bytes_len` / `_get_text_len` answer the raw negative value (-5), not the -1 a ref longer than the file answers](2026-10-18-patra-negative-bytes-ref-length-answered-raw.md)
- [PE `sys_close` and `sys_ftruncate` on fd 0 / 1 / 2 pass the raw HANDLE values 0 / 1 / 2 to kernel32 (no GetStdHandle map): close(2) answers -9 and stderr stays open, ftruncate(1) of a redirected stdout fails](2026-10-18-pe-close-and-ftruncate-pass-std-fds-raw.md)
- [PE `xlseek` / `sys_lseek` on a PIPE or console handle succeeds on Windows (answers the asked offset, the stream does not move) where Linux and macOS answer -ESPIPE (-29); wine answers -1](2026-10-18-pe-seek-on-pipe-or-console-std-handle-succeeds.md)
- [Every self-spawning `tests/tcyr` test fails under `qemu-aarch64` on an x86 host without an aarch64 binfmt: the child's `execve` of the test's own aarch64 ELF answers 127, so a local qemu reproduction reads it as an aarch64 defect (e.g. `crossos/exec_capture_status.tcyr`: 13 passed / 14 failed, green on real pi)](2026-10-18-qemu-aarch64-self-spawning-tcyr-fail-without-binfmt.md)
- [redefinition_layout_and_enum_over_var.sh stops without a verdict under `bash -eo pipefail` (a `grep -c` at a zero count)](2026-10-18-redefinition-layout-gate-stops-under-pipefail.md)
- [A refused `var` annotation, then a tuple literal initializer, cascades "a tuple literal cannot initialize 'b' - its declared type is not a tuple"](2026-10-18-refused-annotation-cascades-tuple-literal-initializer.md)
- [The refused-annotation stand-down matches by (fn, name): a same-named untyped variable in a nested block has its genuine "no struct type in scope" error silenced](2026-10-18-refused-annotation-stand-down-silences-a-shadowing-block-variable.md)
- [Uses of a refused declaration's names that 6.7.15's stand-downs do not reach: const contexts, a trait bound, an uninitialized `var q: Q;`, a use before the declaration](2026-10-18-refused-declaration-names-cascade-in-const-contexts-bounds-and-uninit.md)
- [lib/regression.cyr's verbs that write a CALLER's `out_path` open it with the literal 577 (Linux's O_WRONLY|O_CREAT|O_TRUNC): on Darwin that is O_WRONLY|O_ASYNC|O_CREAT, so an existing file is not truncated and keeps its old tail after a shorter output](2026-10-18-regression-caller-out-path-opened-with-linux-flag-bits-on-darwin.md)
- [A `ret2(..);` right after a `case N:` / `default:` label is not counted as a two-value exit: `var a, b, c = g2(1);` binds a stale register](2026-10-18-ret2-after-case-label-not-counted.md)
- [A scratch resolve keeps each copy's temp name recorded after the rename, so a kill unlinks a file put there later](2026-10-18-scratch-resolve-keeps-a-renamed-temp-recorded.md)
- [A second refused `case` label is reported as "expected ':', got identifier 'ww'" instead of its own refusal](2026-10-18-second-refused-case-label-reported-as-expected-colon.md)
- [lib/sigil.cyr (fold, sigil 3.13.12): `agnosys_run_capture[_timeout]` and `agnosys_run_checked[_timeout]` run `sys_dup2(fd, N); sys_close(fd)` with no same-fd guard — a caller started with fds 0 + 1 closed gets Err from capturing `/bin/echo hi`, and with fd 1 or 2 closed every checked run starts its child with that fd closed](2026-10-18-sigil-agnosys-run-capture-and-run-checked-close-their-own-redirect.md)
- [`var p: *Str = str_from(..);` and `GP = str_from(..);` warn "assigning non-pointer to typed pointer"; `q = str_from(..);` into a `*Str` local does not](2026-10-18-str-call-into-str-pointer-declaration-or-global-warns-typed-pointer.md)
- [`h = *p` into a `Str` HANDLE (p a `*Str`) stores the header's data word as the handle](2026-10-18-str-handle-assigned-str-pointer-dereference-stores-data-word.md)
- [`o.s = *pp` (a struct-typed FIELD destination, pp a `**S`) stores the pointer word into the field's first word, where `o.s = p` copies the struct](2026-10-18-struct-field-destination-from-double-pointer-single-deref-stores-pointer-word.md)
- [Decision: a redeclared struct / tuple literal keeps declaration order, while 6.7.15's D2 (a) makes every scalar constant redeclaration the value from program start](2026-10-18-struct-tuple-literal-redeclaration-order-vs-d2.md)
- [A struct VALUE dereference refused by its struct is named by its operand's last name — `ri(*gps(&s))` '*s', `take8(*gu(pu))` 'pu', `return *gu(pu);` '*pu', `var s: S8 = *h.pu;` 'pu'](2026-10-18-struct-value-dereference-refusals-name-operand-last-name.md)
- [A subscript store through a parenthesised base — `(pn)[0] = 1;`, `(*(&pn))[1] = 2;` — is still "unexpected '('"](2026-10-18-subscript-store-through-parenthesised-base-is-unexpected-paren.md)
- [`--syntax-only`: `gp().n = 5;` with `fn gp(): *Foo` defined HERE and `Foo` a sibling module's struct is a false "the result is a temporary"](2026-10-18-syntax-only-pointer-return-of-sibling-struct-field-store-false-temporary.md)
- [A syscall-number warning in an `#inline` fn's body prints once for the definition and again for every call](2026-10-18-syscall-warnings-repeat-once-per-inline-replay.md)
- [A third type parameter is accepted at the declaration and silently unrecorded; every explicit three-argument use is a parse error](2026-10-18-third-type-parameter-accepted-and-unrecorded.md)
- [Native TLS 1.2 server: a ClientHello with no or an overrunning compression_methods, or an extension that overruns its block, still negotiates; its short-message refusals send no alert](2026-10-18-tls-native-1-2-server-clienthello-other-leniencies.md)
- [A top-level ASSIGNMENT of a call declared to return a vector to a scalar global (`G = mkv(41, 7);`, `G = s.mv();` after the first statement) stores one word, silently, differently per target](2026-10-18-top-level-assignment-of-vector-call-to-scalar-global-stores-a-word.md)
- [A top-level `var G: S = *GPP;` (GPP a `**S`) binds G to the struct as a handle, where the same declaration in a fn copies since 6.7.15 — OPEN (decision)](2026-10-18-top-level-declaration-from-double-pointer-single-deref-binds-handle.md)
- [A top-level untyped `var G = if (c) { B1 } else { B1 };` with a struct branch binds no struct — `G.a` is "no struct type in scope for 'G'", where in a fn `var g = if (..) { b } else { b };` binds; a 16 B struct branch at top level is refused "cannot be a vector, u128 or slice value"](2026-10-18-top-level-untyped-if-expression-struct-result-binds-nothing.md)
- [A top-level untyped `var s = BB.mks();` with a `: Str` METHOD is not routed as a Str: `println(s)` prints the header's bytes](2026-10-18-top-level-untyped-str-method-global-prints-header-bytes.md)
- [A trait member's `cb: *fn(i64): u128` parameter is refused "`u128` is not supported as a parameter type yet", where a fn's compiles](2026-10-18-trait-member-fn-pointer-parameter-u128-return-refused.md)
- [A trait member's return type a fn's return refuses (`u8`..`u64`, `f32`, an enum, `*fn(..)`) still compiles at the trait](2026-10-18-trait-member-return-outside-fn-return-set-accepted.md)
- [D36's tuple-parameter refusal calls a comparison or `!x` argument "an integer" — `take(1 == 1)`, `take(!0)` — where the guide counts them boolean values](2026-10-18-tuple-parameter-comparison-argument-called-an-integer.md)
- [Into a tuple parameter, a float literal — `take(1.5)`, `take(-1.5)`, `take((2.0))` — compiles and is dereferenced as the tuple's address](2026-10-18-tuple-parameter-float-literal-dereferenced.md)
- [A `.field` read, field store or `.m()` on an untyped closure capture is reported "undefined variable 'x'"](2026-10-18-untyped-closure-capture-field-use-says-undefined-variable.md)
- [An untyped `var k = h.clone();` (a `: Str` METHOD's result) is not typed `Str` — `k.len()` is refused "no struct type in scope for 'k'", where `var k = str_clone(h);` types k](2026-10-18-untyped-declaration-from-str-method-result-not-typed-str.md)
- [A Vec element whose generic struct takes another generic struct's instance (`Vec<Box<Box<R>>>`) is not judged against the outer struct's bound](2026-10-18-vec-element-nested-instance-argument-bound-unjudged.md)
- [A method or `callptr(&f, ..)` declared to return a vector that STARTS an assignment's right-hand side, and a vector call in parentheses that STARTS an integer initialiser or right-hand side, store the result's word plus the rest — the unwrapped by-name call is refused](2026-10-18-vector-call-starting-assignment-or-wrapped-start-stores-a-word.md)
- [A method declared to return a vector, on a receiver whose head is a parenthesised dereference or a call (`(*ps).mv()`, `(*pw).s.mv()`, `gw(&w).s.mv()`), binds one word of garbage at an untyped declaration and stores a word into `: i64`](2026-10-18-vector-method-on-dereference-or-call-head-receiver-binds-a-word.md)
- [Windows disallowed CTL: a 16-byte entry is read only as a public-key MD5, never as an MD2 / MD5-signed certificate's signature hash](2026-10-18-windows-ctl-16-byte-entry-as-md5-signature-hash.md)
- [Declaration-zone generic instance call: a refused type argument (`mkg1<*u8>(33)`) or a negated-literal carrier (`mkg1(-3)`) leaves the global untyped — a second error, or a refusal, the after-statement line lacks](2026-10-18-zone-generic-instance-refused-type-argument-or-negated-literal-unbound.md)
- [The declaration zone's replay reports only the FIRST latched error: every later zone declaration's error is silent](2026-10-18-zone-replay-reports-only-first-latched-error.md)
- [A declaration-zone untyped generic call returning a generic struct's instance binds nothing when its type argument comes from an expression, a struct carrier or a bounded struct: `var x = mkg1(30 + 3);`, `mkc(BX)` (`b: Box<T>`), `mkb(P)` (`struct G1<T: Show>`) — `x.v` is "no struct type in scope for 'x'", where after the first statement each binds](2026-10-18-zone-untyped-generic-call-instance-argument-shapes-unread.md)
- [A declaration-zone untyped `var y = b.mkg(P);` / `b.mkg<i32>(33)` — a GENERIC method returning a generic struct's instance (`fn mkg<T>(self, v: T): G1<T>`) — binds nothing (`y.v.a` is "no struct type in scope for 'y'"), where after the first statement it binds the instance](2026-10-18-zone-untyped-generic-method-generic-struct-result-binds-nothing.md)
- [The 6.7.15 changes beyond the decisions' text — confirm or restore each](2026-10-19-6715-behaviour-changes-beyond-the-decisions-text.md)
- [`cyrius-lsp` does not reach macOS: neither macOS tarball builds it, and the server reads its environment and its own path from `/proc`, which macOS has no](2026-10-19-cyrius-lsp-absent-from-macos-and-reads-proc.md)
- [`cyrius-lsp` compiles an include fragment ALONE — every name from an earlier include reads "undefined", so diagnostics in any multi-file project (cyrius's own `src/` included) are false](2026-10-19-cyrius-lsp-compiles-an-include-fragment-alone.md)
- [Gates and check rows read other projects' checkouts — agnos, mirshi, sit, agnoshi, secureyeoman, every repo under `~/Repos` — a language does not gate on other projects](2026-10-19-gates-read-other-projects-checkouts.md)
- [A capture verb killed mid-capture leaves its `<base>/audit_x[ca]_<pid>[.N]` file behind for ever: nothing reaps it, and since CYRIUS-2026-0036's O_EXCL a later process with the same pid skips the name instead of reusing it](2026-10-19-killed-capture-verb-leaves-capture-file-for-ever.md)
- [`regression_ssh_remote_exec_capture`'s output-fd lift (6.7.15) is pinned by no row and no static axis: removing it leaves every row and gate green](2026-10-19-ssh-remote-exec-capture-fd-lift-unpinned.md)

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
