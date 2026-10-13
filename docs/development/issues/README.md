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


**6.7.10 — features: B7 + P5-B** (5)

- [`#derive(Serialize)` does not support a `: cstring` field — it is taken for a nested struct (asked by sigil)](2026-10-08-derive-serialize-cstring-fields.md)
- [An 8-byte struct local initialised from an address is a VALUE holding the address, not a handle](2026-10-08-small-struct-local-from-address-is-value-not-handle.md)
- [`lib/sakshi.cyr` (the sakshi fold) has no cx arm: any program that includes it does not compile for cx](2026-10-11-sakshi-fold-has-no-cx-arm.md)
- [Every build that includes `lib/sigil.cyr` (so every `lib/tls.cyr` program) prints two warnings for sigil's deliberately static 256 KB `hash_file_into` buffer](2026-10-11-sigil-static-read-buffer-warns-on-every-build.md)
- [A pointer passed to a by-value struct parameter of 8 B or less is the struct's VALUE — the callee reads the address as its fields](2026-10-11-typed-pointer-into-small-byvalue-struct-param.md)

**6.7.11 — Break 2, repair 1** (48)

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
- [A struct-typed FIELD as an operator's LEFT operand never dispatches](2026-10-08-struct-field-left-operand-never-dispatches.md)
- [Struct-operator results: six typing / return-shape defects around struct operands](2026-10-08-struct-operator-results.md)
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
- [`.field` on a METHOD's `*T` result (`h.get().b`) is refused, where a free fn's `get2(h).b` reads it](2026-10-10-field-of-method-pointer-result-refused.md)
- [A generic that reads its struct parameter's `T` field as a struct (`b.v.y`, `b: Box<T>`) does not compile, called or not](2026-10-10-generic-base-reads-carrier-field-as-struct.md)
- [A generic call's own result as a struct-carrier argument (`gx(mk1(p))`) is not inferred — refused as a "different struct type"](2026-10-10-generic-call-result-as-carrier-argument-refused.md)
- [A generic METHOD called as `p.m(x)` with a struct for its type parameter runs the i64 base (the dead stub)](2026-10-10-generic-method-call-runs-i64-base.md)
- [A `: stack` pair-returning METHOD used above its `impl` is not a pair: `p.div(d)?` SIGSEGVs, `var v = p.div(d);` binds the tag](2026-10-10-pair-method-defined-after-use-not-flagged.md)
- [A fn parameter's type annotation is read as ONE token: `fn f(a: 5)` / `fn f(a: +)` compile, `fn f(p: **i64)` does not](2026-10-10-param-type-annotation-reads-one-token.md)
- [A parenthesised struct-returning call as a nested-struct literal element is refused ("unexpected '}'")](2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.md)
- [A pointer-to-vector PARAMETER (`p: *f64v2`) is taken as a by-value vector: `rd(&b)` is refused, `rd(b)` builds and SIGSEGVs](2026-10-10-pointer-to-vector-parameter-is-value-form.md)
- [A local's struct receive from a call: `var x = (mk());` infers nothing, `var x: u8 = mk();` infers the struct over its annotation](2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md)
- [A program's own `struct slice` is used by a parameter / pointer but not by a fn-local `var x: slice`](2026-10-10-user-struct-named-slice-shadowed-in-locals.md)
- [`await f` keeps its operand's pointer step: with `f: *i32`, `(await f) + 1` adds 4](2026-10-11-await-result-keeps-typed-pointer-step.md)
- [A bounded generic called at `f64` is refused unless the trait ALSO has `impl … for i64`: `gb(h)` with only `impl Show for f64` says "needs `impl Show for i64`"](2026-10-11-bounded-generic-f64-impl-needs-i64-impl.md)
- [Inside a closure, `s.len` of a captured slice and `q.y` of a captured untyped struct copy (`var q = p;`) are refused as "undefined variable"](2026-10-11-closure-field-read-of-captured-slice-or-untyped-struct-copy-refused.md)
- [A name a closure body declares without a `var` right before it is taken as a capture of the enclosing local](2026-10-11-closure-prescan-reads-declared-names-as-captures.md)
- [cx never auto-calls `fn main`: a program that leaves `main` to the entry epilogue does nothing on cx](2026-10-11-cx-does-not-auto-call-main.md)
- [`*p = l` through a `p: *S` (a struct pointer) stores neither the struct nor one word consistently — a zero-size `S` is overrun by 8 bytes, a small `S` gets its first field only, a 16-byte `S` its first 8 bytes — OPEN (a decision)](2026-10-11-deref-store-through-struct-pointer-decision.md)
- [A narrow scalar LOCAL (`u8` / `i16` / `i32`) is a one-byte pointer to the step checks, and `n + &x` is no pointer where `&x + n` is](2026-10-11-narrow-scalar-local-and-address-of-carry-byte-pointer-step.md)
- [Under `--allow-undef`, an undefined `_str` / `_int` sibling still takes its base's call: `pr(s)` reaches the undefined `pr_str` and traps (rc 132) instead of calling the defined `pr` — OPEN (a decision)](2026-10-11-overload-router-undefined-sibling-under-allow-undef-decision.md)
- [`+| +? -| -?` on a typed pointer add an unscaled count, then hand the result the pointer's step: with `q: *i32`, `(q +| 1) + 1` is `q + 5` — OPEN (a decision)](2026-10-11-saturating-op-keeps-left-pointer-step-decision.md)
- [BENCHMARKS.md prints the cycc size rows (byte counts) as milliseconds — `cc5_bytes | 1ms | 2ms | 2ms` — and the file-size row is still named `size/cc5_bytes`](2026-10-12-benchmarks-md-size-rows-formatted-as-time.md)
- [The "cannot be a fn return type" note lists an incomplete return-type set: `bool`, a multi-value `(T1, T2)`, `dyn Tr` and a generic's `T` are accepted but not named](2026-10-12-return-type-refusal-note-incomplete.md)
- [Every build that includes `lib/sandhi.cyr` (so every `lib/yantra.cyr` build) prints the large-static-data advisory](2026-10-12-sandhi-include-prints-large-static-advisory.md)
- [A struct result over 8 bytes through `fncallN` / `callptr` compiles with no diagnostic and faults: no hidden result pointer is passed, no register pair is received](2026-10-12-struct-result-through-fn-pointer-faults.md)
- [A value-form vector receive from `callptr` / `fncallN` (or any source but a by-name vector call) compiles with no diagnostic and reads wrong lanes, and faults on PE](2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md)

**6.7.12 — Break 2, repair 2 (the platform release)** (25)

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
- [`cyrius header` prints `cyr_val f(..)` for a fn returning a struct (9-16 B: rax:rdx; > 16 B: a hidden pointer)](2026-10-10-cyrius-header-ignores-struct-returns.md)
- [`CYRIUS_POISON=0` (or empty, or any value) turns the poison mode ON — every compiler fork tests only "is it set"](2026-10-10-poison-env-zero-or-empty-turns-mode-on.md)
- [`--strict-pin` / CYRIUS_STRICT_PIN does nothing off Linux, and cycc.exe ignores CYRIUS_PIE](2026-10-10-strict-pin-and-pie-inert-off-linux.md)
- [On Windows, `cyrius build --agnos` and `--target=x86_64-bare-metal-elf` write a plain PE and exit 0](2026-10-10-windows-cli-drops-target-selectors.md)
- [`cyrius pulsar` and the CLI's on-demand cx builds hand an inherited `CYRIUS_POISON` / `CYRIUS_BOUNDS` to the compiler they build](2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md)
- [On macOS an exec-family child still inherits a signal mask its parent inherited from a launcher](2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md)
- [The macOS release tarballs ship two of the three `[release] scripts` — `cyrius-watch.sh` is left out — OPEN (a decision)](2026-10-11-macos-tarballs-omit-cyrius-watch-decision.md)
- [cass (Windows) full-corpus failures were never triaged into named skips vs real failures — the last count is v6.5.33's 32 of 282, the corpus is now 562, and no open issue tracks it](2026-10-12-cass-full-corpus-failures-untriaged.md)
- [`cyrius build` takes contradictory target flags (`--win --aarch64`, `--win --agnos`, `--aarch64 --target=js`, …), silently keeps one and exits 0](2026-10-12-combined-target-flags-silently-resolved.md)
- [cx's fixed 512 KiB code buffer: `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr` stops with a bare "codebuf overflow" on cx](2026-10-12-cx-codebuf-512k-overflows-yukti-crossos-test.md)
- [`cyriusly setup` (compiled): its "bootstrap cycc" step builds no cycc, its cross-bin loop can never match, and it builds the installed tools under an inherited `CYRIUS_BOUNDS`](2026-10-12-cyriusly-setup-bootstrap-cross-loop-and-env.md)
- [`cyrius init --help`, `cyrius port --help` and `cyrius sign-efi --help` (and `-h`) fail as unknown flags, while `cyrius --help` promises every command takes `--help`](2026-10-12-init-port-sign-efi-reject-help.md)
- [`cyrius package` with a missing `[build] entry` prints "package ready: build/<out>" and exits 0 with no artifact; its help row promises an `.ark` it never writes](2026-10-12-package-missing-entry-reports-ready.md)
- [`cyrius tests` still says it "goes in the next release" three releases after the one it named — when the deprecated alias is removed — OPEN (a decision)](2026-10-12-tests-verb-deprecated-alias-removal-decision.md)

**6.7.13 — Break 2, repair 3** (33)

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
- [An `async fn` declared `: (i64, i64)` compiles, and its Future carries only the first value](2026-10-09-async-fn-multi-value-return-loses-second-value.md)
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
- [A top-level `return` compiles with no diagnostic and does not return: execution continues past it on x86_64 / PE and it hangs on aarch64 / cx — OPEN (a decision)](2026-10-12-top-level-return-decision.md)
- ["assigning non-pointer to typed pointer" is missing for a declaration-zone `*T` global and for an assignment to a local or parameter `*T` of a scalar `T`](2026-10-12-typed-pointer-non-pointer-warning-gaps.md)
- [`programs/wc.cyr` (a demo): counts of 8 or more digits run together with no separator, and VT / FF do not separate words](2026-10-12-wc-demo-columns-run-together-and-whitespace-set.md)

**6.7.14 — the full security audit + the refactor / optimization review** (1)

- [A tail call that copies a by-value struct argument is an ordinary call — a per-fn "writes no memory" analysis would win its `jmp` back](2026-10-09-tail-call-by-value-copy-needs-effect-analysis.md)

**Open by design — placed arcs, not bugs** (6)

- [A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10)](2026-10-08-constant-if-arms-not-folded.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](2026-10-08-lib-public-constants-const-migration.md)
- [`cyrius.cyml` has no named build profiles (`[build.PROFILE]`), and `[build] target` is held — warned, never read](2026-10-08-manifest-build-profiles-and-target-unread.md)
- [Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1](2026-10-08-native-tls-capability-limits.md)
- [`cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible](2026-10-08-poison-guard-pages-unbuilt.md)
- [agnos — `CYRIUS_DCE=1` cannot shrink a `kernel;` image: compaction miscompiles through 6.6.19 and is declined from 6.6.20 on](2026-10-10-agnos-kernel-dce-compaction-moves-data.md)

**Unplaced** (11)

- [agnos: a negative fd is taken for a tagged socket — `sys_write(-1, …)` sends on socket slot 7's connection, and `sys_close(-1)` returns 0 after freeing slot 7](2026-10-12-agnos-negative-fd-taken-for-socket-slot-7.md)
- [`cyrfmt --check` exits 0 on a file that `cyrfmt` itself reformats (a call's continuation-line indent)](2026-10-12-cyrfmt-check-passes-a-file-cyrfmt-would-reformat.md)
- [`CYRIUS_DCE=1` keeps the callees of a redefined function's losing body alive](2026-10-12-dce-keeps-the-callees-of-a-redefined-fns-losing-body.md)
- [`cyrius deps` keeps a stdlib leaf removed from `[deps].stdlib` vendored and locked, and nothing reports it](2026-10-12-deps-keeps-a-removed-stdlib-leaf-vendored-and-locked.md)
- [After a `[deps.NAME]` tag changes, `cyrius.lock` keeps the old tag's `commit` row beside the new one, and `deps --locked` accepts it](2026-10-12-deps-keeps-a-stale-commit-row-after-a-tag-change.md)
- [`cyrius distlib` records a named dep's transitive stdlib leaf as the bundle's own: a pure module's sidecar gets `boxed`](2026-10-12-distlib-records-a-named-deps-transitive-leaf-as-the-bundles-own.md)
- [A generic instantiated at `f64` and at a struct named `i` share one instance (`gen$i`) — the second call runs the first's body — OPEN (a decision)](2026-10-12-generic-f64-instance-name-collides-with-struct-i.md)
- [An inline `Str` (from a `Str { .. }` literal) used as a `Str` value passes its `data` word, not a handle: `f(t)` with `fn f(s: Str)` reads the wrong length, silently](2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md)
- [sigil (the crypto / trust fold) has no runtime logging: none of its 68 `src/` files calls sakshi](2026-10-12-sigil-has-no-runtime-logging.md)
- [The stdlib builds an `epoll_event` per arch (`epoll_event_new`) but offers nothing to read one back, so consumers hand-gate the data offset](2026-10-12-stdlib-epoll-event-has-a-writer-but-no-reader.md)
- [`lib/syscalls_linux_common.cyr`'s `sys_ioctl` comment says ELF aarch64 has no 16 → 29 row; the backend has had one since v6.5.38](2026-10-12-sys-ioctl-comment-says-aarch64-has-no-16-to-29-row.md)

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
