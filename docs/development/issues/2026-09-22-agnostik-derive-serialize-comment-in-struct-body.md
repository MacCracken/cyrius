# `#derive(Serialize)`: a `#` comment inside the struct body makes `_to_json` emit a field named `#` and read past the struct — OPEN

**Status:** 🟡 **OPEN** — silent wrong output on every version tested (5.10.14 → 6.6.6). agnostik
has worked around it since 5.10.14 but recorded it only in its own repo, so it was never filed
here until now.
**Placement:** unpinned — 6.6.x-line backlog (derive codegen; per the placement rule, not 7.x).
**Discovered:** 2026-05-10 during agnostik v1.1.1 (sub-byte field widths). Re-verified 2026-09-22
on cycc 6.6.0, 6.6.2 and 6.6.6 during agnostik's 1.6.4 issue review.
**Severity:** Critical, per this directory's guide ("silent data corruption"). There is no warning.
The generated serializer emits the wrong field names, and values loaded from past the end of the
struct, into the JSON. In the repro one of those values reads as a heap address
(`140040034321072` = `0x7F5E…`). The trigger is an ordinary comment, so the first person to
document a derive struct ships it.
**Affects:** cycc 5.10.14 through 6.6.6 (every version measured). The `#derive(Serialize)`
struct-body walk in `src/frontend/lex_pp.cyr` is the suspected site (see Root cause).

## Summary

Put a `#` comment anywhere inside the body of a struct marked `#derive(Serialize)`, and the
generated `<S>_to_json` goes wrong. It names the first field `#`, and it loads values at the wrong
widths and offsets, reading bytes beyond a 5-byte struct. `<S>_from_json_str` of that output does
not round-trip. The same struct with the comment moved above the `#derive` line is correct. The
build is clean: no warning, and the syntax is valid.

## Reproduction

Self-proving:
[`repros/2026-09-22-agnostik-derive-serialize-comment-in-struct-body.cyr`](repros/2026-09-22-agnostik-derive-serialize-comment-in-struct-body.cyr).
It exits 0 when the derived output is correct, and 1 otherwise.

```
cyrius build docs/development/issues/repros/2026-09-22-agnostik-derive-serialize-comment-in-struct-body.cyr /tmp/dsc && /tmp/dsc
```

cycc 6.6.6, from the repo root, with a warning-free build:

```
control (comment above) ok   {"sql":85,"xss":10,"command":5,"path_traversal":0,"prompt_injection":0}
(a) comment inside body  FAIL {"#":330325,"xss":88,"command":1,"path_traversal":128,"prompt_injection":156}
(b)-(e) comment shapes   FAIL {"#":8090864126215,"#":0,"#":140040034321072}
FAIL: #derive(Serialize) output corrupted by a comment in the struct body
exit=1
```

The core of case (a), five `i8` fields holding 85 / 10 / 5 / 0 / 0:

```cyr
#derive(Serialize)
struct Bad {
    # any comment here breaks codegen
    sql: i8; xss: i8; command: i8; path_traversal: i8; prompt_injection: i8;
}
```

The expected output is `{"sql":85,"xss":10,"command":5,"path_traversal":0,"prompt_injection":0}`.

- **The first value is deterministic.** `330325` is `0x050A55`: the three bytes 85, 10, 5 loaded as
  one wider integer. 6.6.0, 6.6.2 and 6.6.6 all print it, and so did 5.10.14.
- **The rest vary run to run,** because they come from beyond the struct.
- **Every comment shape corrupts,** in case (b)–(e): after the `{`, two consecutive lines, before a
  field, and trailing after a field. In that struct *every* field is named `#`.

## Root cause (speculation — please verify)

The `#derive(Serialize)` machinery in `src/frontend/lex_pp.cyr` builds the field table by walking
the struct body. That walk appears to take `#` as a token, the first "field name", instead of
skipping to end of line as the main lexer does for a comment. The rest of the comment then shifts
the name, width and offset table, which is why a single comment corrupts every later field, and why
the loads come out at the wrong widths.

This is **not** the path
[`archived/2026-09-19-lexer-attribute-prefix-swallows-comments.md`](archived/2026-09-19-lexer-attribute-prefix-swallows-comments.md)
fixed at 6.6.6. That one was a comment that *starts with an attribute name* (`#ioctl …`), in the
main lexer. This bug fires on any comment text, and 6.6.6 still shows it. Nor is it the 6.6.6
`#derive(Serialize)` word-boundary change.

## Proposed fix

In the derive body walk, treat `#` as start-of-comment and skip to end of line, mirroring the main
lexer. That covers a line of its own, after the `{`, and trailing after a field. The repro's
(a)–(e) cases are the acceptance test. The control struct must stay correct.

## Consumer-side workaround

Keep every comment **above** the `#derive(Serialize)` line, never inside the body. agnostik has done
this in all 7 of its derive structs since 1.1.1. It also pins every derived `_to_json` output byte
for byte (`tests/tcyr/test_v110_serde_golden.tcyr`), so a comment that slips into a body fails its
CI instead of shipping. Mutation-checked: one comment in `InjectionScores`' body gives
`FAIL: InjectionScores compact bytes`. Consumers without golden tests have no such guard, which is
the case for fixing this in the compiler rather than documenting it.

agnostik's original record, with the 5.10.14 output, is
`agnostik/docs/development/issues/cyrius-derive-comments-in-struct-body-2026-05-10.md`.
