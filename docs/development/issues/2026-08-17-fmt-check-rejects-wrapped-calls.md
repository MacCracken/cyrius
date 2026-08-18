# `cyrius fmt --check` fails silently on continuation indent, and `cyrius fmt` cannot fix it in place

**Status:** 🟡 **OPEN — RE-TITLED and SCOPED 2026-08-18; maintainer decisions taken, implementation is the next bite.**

> ### ⚠ THE ORIGINAL HEADLINE IS WRONG, AND SO WAS THE FIRST REFUTATION OF IT
>
> Wrapped calls are **not** rejected as such — cyrfmt PRESERVES the line break. What it
> normalises is the continuation **indent**. But a premise-check that concluded "headline
> refuted, nothing to see" was also wrong, and measurement settles it:
>
> ```
> $ cyrius fmt w.cyr            # prints canonical form to stdout, file UNCHANGED
> $ cyrius fmt w.cyr --check    # exit 1, ZERO bytes of output
> ```
>
> So there IS a state the tool flags and offers no in-place way to fix, which is exactly what
> the consumer reported ("worked around by un-wrapping every call"). Both the filing and its
> refutation were half right.
>
> ### Root cause
>
> `programs/cyrfmt.cyr` re-indents every line to `depth * 4` where `depth` is **BRACE** depth.
> It does not track paren depth at all, so a continuation line inside an unclosed `(` is
> emitted at the enclosing statement's indent — the flattening. `--check` then compares the
> file against that output and exits 1 on any difference, silently.
>
> ### ⚖️ MAINTAINER DECISIONS (2026-08-18) — implement to these
>
> **1. Canonical continuation indent is TWO spaces; FOUR is accepted; deeper is REJECTED.**
> Maintainer: *"I'd rather have 2-space indents and accept 4 but nothing more; else it
> wouldn't be a format check."* So `--check` carries a deliberate, bounded tolerance rather
> than a byte-for-byte equality — accepting *anything* would make it not a check, and
> accepting only one form would churn every already-formatted file in the ecosystem.
> ⇒ cyrfmt must track PAREN depth and emit statement-indent + 2 for continuations.
>
> **2. `cyrius fmt <file>` REWRITES IN PLACE by default**, plus:
>    * `--verbose` — rewrite in place AND echo the result to stdout.
>    * `--dry` — leave the file alone and report what would change.
> ⇒ This is a deliberate behaviour change from stdout-only; scripts relying on the old
> default must move to `--dry`/`--verbose`. Note it in the CHANGELOG as a breaking CLI change.
>
> **3. `--check` must SAY WHAT DIFFERS** — file and first differing line, not exit 1 in
> silence. The silence is the uncontested half of the original filing.
>
> ⛔ **AND THE CLAUDE.md LINE IS PART OF THE FIX.** It currently reads "cyrfmt flattens
> multi-line call continuations to 4-space indent — write them that way up front", i.e. the
> workaround written down as a rule for authors to pre-comply with. That is the same shape as
> the retired "≤6 args" rule. Once the formatter emits 2 and accepts 4, that line must be
> rewritten as a formatter contract, not an authoring instruction.
**Placement:** unpinned — 6.5.x-line backlog.
**Discovered:** 2026-08-17 while adding `tests/tcyr/motion.tcyr` to rupa (CI's format gate failed).
**Severity:** Medium — hard CI failure with a known workaround, and the workaround fights the lint gate.
**Affects:** cycc 6.5.25 (found here). Not bisected against earlier 6.5.x.

## Summary

`cyrius fmt <file> --check` exits **1** for any file containing a function call whose arguments are
split across more than one line. It prints **nothing** — no diff, no message, no line number — so the
failure is indistinguishable from a crash or a bad path.

The confusing part, and the reason this took a bisect rather than a glance: **`cyrius fmt <file>`
(rewriting) produces a byte-identical file.** The formatter has no complaint it can express as an edit,
yet `--check` insists the file is unformatted. Following the tool's own advice — "run `cyrius fmt` and
commit the result" — changes nothing and CI stays red.

⚠ It also collides with the 120-character lint limit. A long assertion has to wrap to satisfy
`cyrius lint`, and must not wrap to satisfy `cyrius fmt --check`. A line that is too long to fit on one
line currently satisfies neither gate.

## Reproduction

`docs/development/issues/repros/2026-08-17-fmt-check-wrapped-call.cyr`:

```cyrius
fn t_ge(a, b): i64 { if (a >= b) { return 1; } return 0; }

fn main() {
    alloc_init();
    assert_eq(t_ge(2, 1), 1,
              "a call whose arguments continue on the next line");
    return assert_summary();
}

var exit_code = main();
syscall(60, exit_code);
```

```
$ cyrius fmt repro.cyr --check ; echo "rc=$?"
rc=1                       # no output at all

$ cyrius fmt repro.cyr      # rewrites the file
$ diff repro.cyr repro.cyr.orig
                           # ...byte-identical, nothing changed

$ cyrius fmt repro.cyr --check ; echo "rc=$?"
rc=1                       # still fails
```

Join the two lines into `assert_eq(t_ge(2, 1), 1, "the same call on one line");` and:

```
$ cyrius fmt repro.cyr --check ; echo "rc=$?"
rc=0
```

That single edit is the whole difference. Measured both directions on cycc 6.5.25.

## Root cause (if known)

Unknown — **speculation**, flagged as such: `--check` looks like it compares against a canonical form
that always joins a call onto one line, while the rewrite path leaves existing line breaks alone. That
would produce exactly this pair of symptoms (check disagrees, rewrite is a no-op). Not verified; I have
not read the formatter.

## Proposed fix

None offered — I do not know the internals. What would make it non-blocking even unfixed: **have
`--check` say which line it objects to.** A silent exit 1 from a formatter is the part that cost the
time here; the wrapping rule itself is easy to live with once it is visible.

## Consumer-side workaround (if any)

Shipped in rupa 0.1.3 (`tests/tcyr/motion.tcyr`): keep every call on ONE line, and where that exceeds
120 characters, hoist the long sub-expressions into locals first rather than wrapping the call.

```cyrius
# was — wrapped, fails --check
assert_eq(rupa_motion_ease(RupaMotion.RU_MO_CALM, RupaEase.RU_EASE_LINEAR),
          RupaEase.RU_EASE_LINEAR, "an ease override is honoured");

# now — one line, fits 120, passes both gates
var lin = RupaEase.RU_EASE_LINEAR;
assert_eq(rupa_motion_ease(RupaMotion.RU_MO_CALM, lin), lin, "an ease override is honoured");
```

⚠ Shortening the assertion MESSAGE is the tempting fix and it is the worse one — the message is what a
failing gate tells the next reader. Hoist the expression, keep the sentence.

⚠ Note for other consumers: repos whose CI lints `tests/` as well as `src/` will hit this first, because
test files carry the long assertion messages. rupa's `theme.tcyr` passed for years purely because every
call in it happens to be short enough to fit on one line.
