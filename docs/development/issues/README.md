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


**6.7.14 — Break 2, repair 4: generics, the frontend, infra (added at the 6.7.12 open, 2026-10-15)** (139)

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
- [The aarch64 Linux CLI resolves `[deps.X] target = "x86_64"` and skips `target = "aarch64"` on a plain build](2026-10-15-aarch64-linux-cli-deps-target-reads-x86-arch.md)
- [The aarch64-linux release tarball ships none of the `[release] scripts`](2026-10-15-aarch64-linux-tarball-ships-no-release-scripts.md)
- [aarch64 W^X ELF layout pads every executable with up to 64 KiB of zeros — open](2026-10-15-aarch64-wx-layout-pads-every-binary-to-64k.md)
- [arm64 macOS `sys_mkdirat` / `sys_fchmodat` drop the dirfd: a relative path lands against the cwd](2026-10-15-arm64-macos-mkdirat-fchmodat-drop-the-dirfd.md)
- [Call-site diagnostics name a method by its mangled fn name (`in a call to 'S_ri'`, `'S_two' expects 2 arguments`) and a generic call by its instance (`'g$i'`) — D27 / A2's vector refusals among them](2026-10-15-call-diagnostics-name-method-by-mangled-name.md)
- [cli_temp_dir_no_leak.sh axis 7's SIGHUP rows go RED when the gate runs with SIGHUP ignored (`nohup sh scripts/check.sh`)](2026-10-15-cli-temp-dir-gate-sighup-rows-red-under-nohup.md)
- [`*(&s) OP= v` on a struct still adds to its first word, while `*p OP= v` through a `*S` is refused and `*(&s)` is now the struct value — OPEN (a decision)](2026-10-15-compound-assignment-through-address-of-struct-keeps-word-op.md)
- [cx: a conditional jump (`jz` / `jnz`) over more than 128 KiB of bytecode wraps its 16-bit offset silently — the compile exits 0 and cxvm jumps to the wrong place](2026-10-15-cx-conditional-jump-past-128k-wraps-silently.md)
- [cx: two raw `syscall(SYS_MMAP)` paths still hand back a HOST address as success — `mmap_stack` and freelist's `_fl_mmap`](2026-10-15-cx-raw-mmap-paths-return-host-address.md)
- [cx: the static heap is still 128 KB (`lib/alloc_cx.cyr` `_CX_HEAP_SLOTS`) though cxvm's guest memory is 8 MiB since 6.7.12](2026-10-15-cx-static-heap-128k-while-guest-is-8-mib.md)
- [cx: the pointer-taking wrappers outside D13's four still hand the host a guest address — and since the 8 MiB guest segment a guest address can be cxvm's own Linux image (`cyr_munmap(0x400000, …)` unmaps cxvm's code)](2026-10-15-cx-untranslated-pointer-wrappers-can-reach-cxvm-image.md)
- [`cyrius header` keeps only the first line of a multi-line parameter list, which drops parameters and misses a vector parameter on a continuation line](2026-10-15-cyrius-header-multi-line-parameter-list-keeps-first-line-only.md)
- [`cyrius header lib/net.cyr` prints `cyr_val sock_send_a(..)` / `cyr_val sock_recv_a(..)`, rc 0, for two `: i64` fns that return lib/result.cyr's pair](2026-10-15-cyrius-header-net-sock-a-wrappers-print-cyr-val-over-a-pair.md)
- [`cyrius-watch.sh` builds with raw `cat | cycc`: its output is unsigned and SIGKILLed on Apple Silicon, and an entry-relative `include` fails on every OS](2026-10-15-cyrius-watch-builds-with-raw-cycc-unsigned-on-apple-silicon.md)
- [A SIGTERM'd `cyrius deps --locked` (and 6.7.13's pin-move dry pass) leaves its scratch resolve in the CLI's temp dir](2026-10-15-deps-scratch-resolve-left-in-temp-dir-on-kill.md)
- [distlib: the bundle checks read `lib/<leaf>.cyr` from cycc's OWN version slot, not the manifest's pinned `versions/<pin>/lib` — the final "bundle compiles" check fails when only the pinned slot exists](2026-10-15-distlib-bundle-compile-ignores-pinned-stdlib.md)
- [embed_build.sh axis 6 times ONE embed build against ONE baseline build, and the 2x bound flakes under host load — the slot-open tree fails it too](2026-10-15-embed-build-axis6-single-sample-timing-flakes-under-load.md)
- [`lib/async.cyr` still hand-gates the epoll_event data offset at its three WRITE sites — the stdlib has no writer for a caller-owned (stack) buffer](2026-10-15-epoll-event-writer-for-caller-buffers.md)
- [A for step `gp().n += 1` (a field of a call's result) is refused "expected '=', got '('" plus a false "undefined variable 'gp'" — the statement form stores through a `: *T` result since 6.7.13 (D8 (a))](2026-10-15-for-step-call-led-field-assignment-refused-with-false-undefined.md)
- [`g<f64v2>(b)` with `fn g<T>(p: *T)` reports a second error from D27's refusal (naming the instance `g$i`) after the type-argument refusal — a cascade](2026-10-15-generic-vector-type-arg-refusal-cascades-d27-refusal.md)
- [A SIGTERM'd `cyrius deps` leaves `_git_run`'s captures (`git_err`, `git_rev_out`, `dep_verify_out`) and its git child, and a mid-clone kill leaves `git clone` running](2026-10-15-git-run-and-clone-children-untracked-by-the-kill-handler.md)
- [An inline `Str` where no `Str` value is taken — an untyped parameter (`h.eq(t)`), `fncall1(&f, t)` / `callptr(&f, t)`, a `*Str` local, a tuple element, an if-expression branch — still passes its `data` word](2026-10-15-inline-str-into-untyped-or-other-pointer-position-passes-data-word.md)
- [`CYRIUS_IR=3`: an f64 field store through a `*T` (`q.f = 2.5;`) SIGSEGVs](2026-10-15-ir3-f64-field-store-through-pointer-faults.md)
- [x86 ELF DCE stops compacting past 4,096 dead-code runs, and kybernet's `agnos-init` crossed it: 248,440 → 1,574,640 bytes](2026-10-15-kybernet-dce-compaction-cap-agnos-init.md)
- [cyrius-lsp: a loose file now reports the pin-redirect error of the project the server's working directory sits in](2026-10-15-lsp-loose-file-reports-pin-redirect-of-server-cwd-project.md)
- [On a macOS host, `cyrius build --win` writes a Mach-O named `.exe` at rc 0 — neither Mach-O compiler reads CYRIUS_TARGET_WIN](2026-10-15-macos-cli-win-writes-mach-o-named-exe.md)
- [`bs(n + &x)` with a narrow `n` into a by-value struct parameter of 8 B or less passes the SUM as the struct, where `bs(&x + n)` passes the struct it points at](2026-10-15-narrow-plus-address-of-into-small-byvalue-param-passes-the-sum.md)
- [The native-region renumber warning does not see a per-arch file included from inside a region, or the author's own constant](2026-10-15-native-region-warning-misses-included-files-and-author-constants.md)
- [A non-tuple word passed to a tuple parameter — `take(5)`, `take(one(3))`, `take(g2(3))` with `g2` declared `: i64` — is dereferenced as the tuple's address (a crash, no diagnostic), where the same value into a tuple variable is refused](2026-10-15-non-tuple-word-into-tuple-parameter-dereferenced.md)
- [A fn that returns a `: stack` pair only through `?` is not a pair to a caller ABOVE it: `qb(x)?` SIGSEGVs, `var v = qb(x);` binds the tag](2026-10-15-pair-fn-through-question-mark-used-above-its-definition-not-flagged.md)
- [`var a, b = (f(7));` — a destructure whose call is parenthesised — is refused "multi-value destructure needs a call on the right-hand side", where `return (g(x));` and the struct / pair checks see through the same wrap](2026-10-15-paren-wrapped-call-destructure-refused.md)
- [A store whose whole value is parenthesised and STARTS with a `: stack` pair call — `var v = (f(7) + 1);`, `h.a = (f(7) + 1);`, `x = (f(7) * 2);` — keeps the tag silently, where the unwrapped spelling is refused "bind both"](2026-10-15-paren-wrapped-pair-operand-store-keeps-tag.md)
- [PE `sys_open` answers -1 for every Win32 failure, so `file_open_r` / `file_read_all_r` can never say `IoNotFound` on Windows](2026-10-15-pe-open-failure-is-always-minus-one.md)
- [PE `sys_read` returns ReadFile's byte count even when ReadFile FAILS: a read error reads as 0, end of file](2026-10-15-pe-read-failure-reads-as-eof.md)
- [Process docs still describe the release gate's cross-OS leg as the crossos subset, with the full corpus opt-in](2026-10-15-process-docs-cross-os-leg-still-crossos-only.md)
- [A redeclared global whose LATER initializer is a folded constant (`= 2 + 1`, `= -5`, `= (7)`) is never compared — a conflicting value compiles silently](2026-10-15-redeclared-global-folded-later-value-not-compared.md)
- [A fn whose values come from `ret2(a, b)` is not counted by pass 1: `var a, b, c = g2();` binds `c` to a stale register](2026-10-15-ret2-body-not-counted-three-names-read-stale-register.md)
- [`ret2(a, b)` in a fn declared to return a vector (`: f64v2` / `f32v4` / `f64v4` / `i32v4`) compiles clean and returns no vector](2026-10-15-ret2-in-vector-returning-fn-compiles.md)
- [`return &h;` in a fn returning `S`, with `h` a handle, a `*S` local or an untyped `self`: at 8 B or less the slot's ADDRESS is the struct's word; over 8 B refused in other words](2026-10-15-return-address-of-handle-or-pointer-in-struct-fn.md)
- [`t = a;` with `t` an inline `Str` and `a` a `Str` handle stores the handle word into `t.data` (a pun), where `t = u` between two inline `Str`s copies the header — whether `var t: Str;` (no initialiser) joins D7 (1) waits on it](2026-10-15-str-handle-into-inline-str-stores-one-word.md)
- [A struct-typed field, a struct call result or a struct dereference passed to a word-pointer parameter (`ri(w.s)`, `ri(mk())`, `ri(*pp)` with `p: *i64`) pushes its first word as the address](2026-10-15-struct-field-call-or-dereference-into-word-pointer-parameter-pushes-first-word.md)
- [Native TLS hello conformance, the residue past the 6.7.12 bite: duplicate extensions, bytes after an extension block, a malformed or multi-protocol ALPN answer, and a 1.2 client ServerHello that walks nothing](2026-10-15-tls-native-hello-conformance-residue.md)
- [`TLS_SHA256_CTX_LEN` (a literal public var, no const twin) still sizes the transcript clone copy: raising it smashes the stack](2026-10-15-tls-sha256-ctx-len-literal-var-drives-transcript-clone.md)
- [A top-level `var H: Str = gt;` (gt an inline `Str` global) copies the header where the same declaration in a fn binds to it; an untyped top-level `var H = gt;` keeps the `data` word](2026-10-15-top-level-str-declaration-from-inline-str-global-copies.md)
- [A top-level `mk().n = 5;` (a struct returned by value) is reported twice: the no-frame refusal and "the result is a temporary"](2026-10-15-toplevel-by-value-call-field-store-two-errors.md)
- [`var t: (i64, i64) = callptr(fp, ..);` is refused "cannot initialize tuple 't' with a value that is not a tuple", where `fncall1(fp, ..)` captures the same call](2026-10-15-tuple-capture-of-callptr-refused.md)
- [A user struct named `Result`, `Option` or `Tagged` is a heap handle by NAME: its inline value into its by-value parameter passes the first field as the handle (SIGSEGV on every target)](2026-10-15-user-struct-named-result-option-tagged-is-a-handle-by-name.md)
- [A vector dereference as an if-expression branch is an integer — lane 0's word — where a vector name branch is refused](2026-10-15-vector-dereference-as-if-expression-branch-is-lane-zero.md)
- [`_win_widen` / `_win_widen_n` in lib/syscalls_windows.cyr have no caller left](2026-10-15-win-widen-helpers-have-no-caller.md)
- [Windows disallowed CTL: its 48-byte entries are not applied (identifier form unknown)](2026-10-15-windows-disallowed-ctl-48-byte-entries.md)
- [Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end](2026-10-15-windows-protectedroots-flag1-user-root-unverified.md)
- [Five ws tests still define a `sandhi_server_find_header` (and one a `base64_encode`) stand-in that `lib/ws_server.cyr`'s own includes made a duplicate — every compile warns, and in one the stub binds last](2026-10-15-ws-tests-carry-stale-sandhi-find-header-stubs.md)
- [The 6.7.13 changes beyond the decisions' text — confirm or restore each](2026-10-16-6713-behaviour-changes-beyond-the-decisions-text.md)
- [`callptr(&gp, 5).b = 40;` — a field store through a known callee's result in statement position — is "expected ';', got '='", where `fncall1(&gp, 5).b = 40;` stores through](2026-10-16-callptr-statement-field-store-does-not-parse.md)
- [A closure's captured vector passed to a VALUE-form vector parameter (`|k| lanes(b)`, `fn lanes(x: f64v2)`) is refused on every target — the local `lanes(b)` is passed; accept the capture as the local is?](2026-10-16-captured-vector-into-value-form-parameter-refused.md)
- [In a closure, a write to a captured name with a same-named GLOBAL compiles silently and writes the global](2026-10-16-closure-write-to-captured-name-lands-in-same-named-global.md)
- [Pointer-to-pointer pins are interned per pointee struct, so 127 distinct `**S` structs hit "max 126" where one pin served them](2026-10-16-double-pointer-pins-interned-per-struct-cap.md)
- [`(s).a` / `(mk1()).a` — a `.field` after a parenthesised expression is "expected ';', got '.'"](2026-10-16-field-of-parenthesised-expression-does-not-parse.md)
- [A generic instance's `pp: **T` PARAMETER pins its pointee unbound: `*pp + 1` steps 8 (not sizeof(T)) and `take(**pp)` into `*T`'s struct pushes the first field as the address (139), where the same `**T` as a LOCAL of the instance is right](2026-10-16-generic-double-pointer-parameter-pointee-unbound.md)
- [`callptr(&mk4, ..)` / `fncallN(&mk4, ..)` of another vector into a vector local is refused in the generic words, not as a type mismatch](2026-10-16-indirect-call-of-another-vector-into-vector-local-generic-words.md)
- [An inline `Str`'s header escapes its frame through a handle bound to it: `var h: Str = t; return h;` / `G = h` compile with no refusal and the returned handle dangles](2026-10-16-inline-str-header-escapes-through-bound-handle.md)
- [A known `&f` callee's non-struct result is an untyped word: `var w: *P2 = fncall0(&gp);` draws the typed-pointer warning, `var a = fncall0(&f);` with `f: f64` binds an integer](2026-10-16-known-callee-pointer-or-f64-result-untyped.md)
- [The vector return, the value-form vector argument and a wrapped vector-local source report a call to a missing fn as a refused source](2026-10-16-other-vector-refusals-report-undefined-call-as-refused-source.md)
- [`var a = (f()) * 2.0;` with `f: f64` binds an untyped word, where `var a = f() * 2.0;` and `var a = (f());` bind an f64](2026-10-16-paren-wrapped-f64-call-leading-operator-untyped.md)
- [`var s = (mks());` with a `: Str` call binds an untyped word — `println(s)` prints the header's bytes, `s.len()` is refused](2026-10-16-paren-wrapped-str-call-untyped-receive-is-a-word.md)
- [`HE { 7, (q0), 8 }` — a struct LOCAL in parentheses as a nested-struct literal element is "unexpected '}'"](2026-10-16-paren-wrapped-struct-name-as-nested-literal-element-refused.md)
- [A parenthesised argument to a value-form vector parameter — `lanes((v))`, `lanes((mkv(4, 2)))` — is refused on x86_64 / aarch64 / cx and passed on PE](2026-10-16-parenthesised-argument-into-value-form-vector-parameter.md)
- [patra's suite opens `/dev/null` for its failed-sync rows: on Windows the open fails and two rows fail](2026-10-16-patra-suite-dev-null-fixture-fails-on-windows.md)
- [On PE, a value-form 16-byte vector parameter (`v: f64v2` / `v: f32v4` / an integer vector) takes a vector local of any type with no check](2026-10-16-pe-16-byte-value-form-vector-argument-unchecked.md)
- [On Windows, `&w` passed to a value-form vector parameter compiles and runs, where x86_64 / aarch64 / cx refuse it](2026-10-16-pe-address-of-vector-into-value-form-parameter-accepted.md)
- [On Windows, an identifier-led expression (`lanes(q + 1)`, `lanes(z * 2)`, `lanes(w + 1)`) passed to a value-form vector parameter compiles and reads garbage](2026-10-16-pe-identifier-led-expression-into-value-form-vector-parameter.md)
- [Windows `xlseek` / `sys_lseek`: a FAILED seek returns 0 — the PE reroute ignores `SetFilePointerEx`'s BOOL and hands back its pre-zeroed output slot](2026-10-16-pe-lseek-failed-seek-returns-zero.md)
- [On PE a struct local passed to a value-form vector parameter (`lanes(p)`, `p: Pt`, `fn lanes(x: f64v2)`) is passed — the callee reads the struct's bytes as the vector — where x86_64 / aarch64 / cx refuse it](2026-10-16-pe-struct-local-into-value-form-vector-parameter.md)
- [simd_valueform_no_avx_transition.sh axis 2b reads 9 ms / 9 ms (100 %) under host load and fails a check.sh run](2026-10-16-simd-valueform-axis2b-reads-100-percent-under-host-load.md)
- [Struct- and vector-pointer argument refusals name a method-result argument by its mangled fn name (`'S2_dup'`)](2026-10-16-struct-argument-refusal-names-method-result-by-mangled-name.md)
- [`x = mkp();` / `x = b.mk();` / `x = a + c;` — a struct over 8 B ASSIGNED to a scalar local or global stores its first word, where the declaration `var x: i64 = mkp();` is refused by name (D24 / D13)](2026-10-16-struct-call-result-assigned-to-scalar-keeps-first-word.md)
- [`**pp` through a `**S` is no struct value: `take(**pp)` into a by-value `S`, `var t: S = **pp;` fault, and `**pp` of a 3-byte struct reads 8 bytes](2026-10-16-struct-double-pointer-dereference-is-no-struct-value.md)
- [A struct-typed FIELD passed to a `*V` parameter (`rd(w.s)`, `s: Pt`, `p: *f64v2`) is accepted silently, where D33 refuses the same struct from a local, a call, `*ps`, a global or a capture](2026-10-16-struct-field-into-vector-pointer-parameter-accepted.md)
- [A user struct named like a float vector type (`struct f32v4 { .. }`) is a struct as a local and a vector as a parameter type](2026-10-16-struct-named-like-a-float-vector-is-a-vector-only-as-a-parameter.md)
- [A top-level `var X: *P2 = mkp();` (or `= B.mk();`, `= A + C;`, `= callptr(&mkp);`) after the first statement compiles under the typed-pointer warning and faults at `X.b`; in the declaration zone the free / `&f` call is refused in D24's scalar words and a method compiles silently](2026-10-16-top-level-pointer-annotation-from-byvalue-struct-call.md)
- [A top-level untyped `var x = mk1();` (wrapped or not) infers no struct — `x.a` is "no struct type in scope for 'x'" — and at 9-16 B it silently binds the first word, where `var x: P2 = mk2();` is refused "needs storage in a fn's frame"](2026-10-16-top-level-untyped-struct-call-receive-infers-nothing.md)
- [A top-level `.field` / `.m()` on a method result over 16 B is refused twice](2026-10-16-toplevel-method-chain-over-16b-refused-twice.md)
- [A typed closure parameter `|m: i64|` is refused "expected unknown, got ':'" plus cascade errors, never naming the rule](2026-10-16-typed-closure-parameter-refusal-cascades.md)
- ["assigning non-pointer to typed pointer" fires on a string literal into a `*u8` (`var s: *u8 = "abc";`, `t = "xyz";`) and cascades beside the `&a[i]` refusal; D18 (a) carried both to the declaration zone and to a scalar `*T` local's assignment](2026-10-16-typed-pointer-warning-string-literal-and-address-of-subscript.md)
- [`var x: Foo = b.mk();` — an unknown annotation type cascades into D24's refusal (two errors on one line); D13 carried the free call's cascade to methods and operators](2026-10-16-unknown-annotation-type-cascades-into-d24-refusal.md)
- [A `*V` dereference passed to a value-form vector parameter (`lanes(*pb)`, `pb: *f64v2`, `fn lanes(x: f64v2)`) is refused on x86_64 / aarch64 / cx and compiles to a page fault on PE](2026-10-16-vector-dereference-into-value-form-parameter-faults-on-pe.md)
- [A `*V` dereference other than `* NAME` — `**ppb`, `*gp(pb)`, `*h.pv`, `*GPV`, `*(pb + 0)`, `*&b` — passed to a `*i64` / `*u8` / `**T` parameter still pushes lane 0 as the address (139), where the same argument into `*Pt` is refused by name (D31)](2026-10-16-vector-dereference-other-than-star-name-into-word-pointer-parameter-faults.md)
- [`*p` of a `*V` at the destinations D34 did not name: `return *p;` from a `: f64v2` fn is refused, and an untyped `var v = *p;` binds one word (lane 0)](2026-10-16-vector-dereference-return-and-untyped-destinations.md)
- [`v = missing(..)` into a vector local warns "assigning non-pointer to typed pointer" — v is no typed pointer](2026-10-16-vector-local-assignment-from-undefined-call-warns-typed-pointer.md)
- [A vector METHOD result in the destinations D29 did not name: an untyped `var v = s.mv();` binds one word (wrong lanes, silent), `var x: i64 = s.mv()` / `x = s.mv()` store a word, `return s.mv();` from a `: f64v2` fn is refused](2026-10-16-vector-method-result-untyped-scalar-and-return-destinations.md)

**6.7.15 — Break 2, repair 5 (added at the 6.7.13 integration, 2026-10-16)** (0)


**6.7.16 — the full security audit + the refactor / optimization review** (2)

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
