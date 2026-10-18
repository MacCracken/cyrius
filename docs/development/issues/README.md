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


**6.7.14 — Break 2, repair 4: generics, the frontend, infra (added at the 6.7.12 open, 2026-10-15)** (137)

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
- [Five ws tests still define a `sandhi_server_find_header` (and one a `base64_encode`) stand-in that `lib/ws_server.cyr`'s own includes made a duplicate — every compile warns, and in one the stub binds last](2026-10-15-ws-tests-carry-stale-sandhi-find-header-stubs.md)
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

**6.7.15 — Break 2, repair 5 (added at the 6.7.13 integration, 2026-10-16)** (110)

- [Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end](2026-10-15-windows-protectedroots-flag1-user-root-unverified.md)
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
