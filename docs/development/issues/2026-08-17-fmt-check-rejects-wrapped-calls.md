# `cyrius fmt --check` rejects any wrapped call, silently, and `cyrius fmt` cannot fix it

**Status:** 🟡 **OPEN** — filed from rupa 0.1.3; worked around by un-wrapping every call.
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
