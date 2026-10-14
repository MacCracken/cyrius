# cybs names neither the construct it refused nor the file and line — OPEN

**Status:** 🟡 **OPEN** — the remainder of [the bare `syntax error` fix](2026-10-08-cybs-bare-syntax-error-no-location.md)
that the seed's label table cannot hold today. 6.7.11 shipped the user's option A (2026-10-13): one class message that
lists what cybs lacks, followed by the offending line's text from the expanded stream; an undefined name is named. The
per-construct refusal and `file:line` were filed here by that decision.
**Placement:** roadmap_6.md § *A seed-rotation minor* (filed 2026-10-13 from the 6.7.11 infra lane; it needs more seed
labels than cybs.cyr has left) — never 7.x.
**Discovered:** 2026-10-13, sizing the bare `syntax error` fix against the seed's 512-label table.
**Severity:** Low — every case is refused, nothing miscompiles; the line text already greps to its `src/` file.
**Affects:** `bootstrap/cybs.cyr` as of 6.7.11.

## Summary

When `src/` uses syntax outside cybs's subset, seed-derive (release gate step 2) stops with one message that lists every
construct cybs lacks, `at:` the offending line of the expanded stream (`pp_expand` splices the includes in). It does not
say WHICH construct it met, and it does not say which file or line: a reader greps the printed text to find the file.

## Reproduction

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > cybs && chmod +x cybs
printf 'fn twice(a) {\n    var i = 0;\n    loop { i = i + 1; if (i == 2) { break; } }\n    return a * i;\n}\n' > helper.cyr
printf 'include "helper.cyr"\nsyscall(60, twice(21));\n' > main.cyr
./cybs < main.cyr > /dev/null; echo "exit=$?"
# 6.7.11:
# cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=), at:     loop { i = i + 1; if (i == 2) { break; } }
# exit=1
# wanted: cybs: helper.cyr:3: `loop` is not supported by the bootstrap compiler; write `while (1) { .. }`
```

## Root cause

The seed's label table. cybs.cyr defines **506 of the seed's 512 labels** after 6.7.11 (gate row S of
`tests/gates/toolchain/cybs_call_arity_named.sh`; see
[the seed's unchecked caps](2026-10-08-seed-asm-silent-caps-input-labels-code.md)), and each piece below costs labels:

- **Per construct** (the filing's (a)): `const`, `loop` and `do` lex as identifiers and the if-expression, a leading
  `-`, `>>>` and `>>=` each fail at a different `parse_err` site, so naming each one needs a recognition arm per
  construct (a lexer keyword branch or a parser arm, each a label) and a message per construct (a `db` label each, or
  one table and a writer): about 10–14 labels.
- **`file:line`** (the filing's (b)): tokens record their byte offset in the expanded stream (6.7.11,
  `r15 + 0xA000000`), but the stream carries no include boundaries. `pp_expand` would record (stream offset, file name)
  at each splice and its return, and the refusal would map an offset back through that table and count LFs from the
  file's start: about 6–8 labels.

Six labels are left, so neither fits without a new seed.

## Proposed fix

With the seed-rotation minor (roadmap_6.md), once the label table has headroom: (a) a named refusal per construct,
each saying what to write instead; (b) the include-boundary table in `pp_expand`, and `file:line` in front of the line
text on both refusals (`parse_err`, `find_var_undef`). Gate: extend `tests/gates/toolchain/cybs_diagnostics_named.sh`
(each row's expected message gains the construct's name and its `file:line`, the included-file row its file's name).
Seed-derive and the closure after. No change to what cycc compiles.
