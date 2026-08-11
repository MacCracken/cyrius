# `cyrius fmt` reindents INSIDE a multi-line string literal, changing what the program does

**Status:** ✅ RESOLVED in v6.5.18 — `programs/cyrfmt.cyr` now carries `in_string`
across physical lines and gates all four mutating steps (indent, leading strip,
trailing trim, blank collapse) on that state. Gated by
`tests/gates/toolchain/cyrfmt_string_continuation.sh`, registered in
`programs/checks/main.cyr`.

> **The filing under-reported the blast radius, in three ways found while fixing it.**
> 1. **It is not only the trailing backslash.** cyrius has no backslash-newline splice
>    rule at all (`src/frontend/lex.cyr:1796` is a catch-all escape store, `:1797` stores
>    a raw newline verbatim), so a literal spans lines with a bare newline and no
>    backslash too, and `\\` at EOL continues as well. The exposed construct is *any*
>    string literal containing a newline, however spelled.
> 2. **It deletes as well as inserts.** Trailing whitespace inside a literal was trimmed,
>    a whitespace-only interior line was collapsed to empty, and a continuation indented
>    deeper than `depth*4` LOST bytes. An insertion-only fix leaves those broken.
> 3. **It desynced the brace ledger.** The closing quote of a continuation line was read
>    as an *opening* quote, so the depth counter never recovered and every LATER line in
>    the file was re-indented. This repo's own `src/main.cyr` carries the raw-newline
>    shape at line 777 and `cyrfmt` rewrote **2478 lines** of it; the same in all six
>    `src/main*.cyr` driver forks. Post-fix that is 196 lines of ordinary drift, and the
>    error string is byte-identical.
>
> Differential check: old vs new `cyrfmt` over 599 repo sources disagree on exactly those
> 6 files and nothing else.
**Discovered:** 2026-08-09, v6.5.16, porting `agnosai/src/definitions/loader.cyr` and
its YAML test fixtures.
**Severity:** High — `fmt` is expected to be behaviour-preserving, and this is a silent
data change in the one construct where whitespace is not free. It is caught by a test or
not at all.

## The bug

A trailing backslash continues a string literal onto the next physical line. `cyrius fmt`
treats the continuation line as ordinary code and applies the enclosing statement's
indentation to it — and those spaces land **inside the string**.

```cyr
fn main(): i64 {
    var s = str_from("abc\
def");
    syscall(1, 1, str_data(s), str_len(s));
    return 0;
}
```

```
$ cycc … && ./probe | cat -A
abc$
def$
```

The literal is `"abc\ndef"` — 7 bytes. Now format it:

```
$ cyrius fmt probe.cyr
fn main(): i64 {
    var s = str_from("abc\
    def");
```

which is `"abc\n    def"` — 11 bytes. `fmt --check` reports the unformatted file as
dirty, so a CI cleanliness gate pushes every project toward the changed version.

`fmt` is idempotent afterwards (`fmt(fmt(x)) == fmt(x)`), so the damage is applied once
and then looks stable.

## Two facts that make it worse than it reads

1. **The backslash-newline keeps the newline.** It is not a C-style line splice. So the
   construct is already the only way to write a multi-line string, and it is exactly the
   construct being corrupted.
2. **The corruption is usually invisible.** Injected whitespace between JSON tokens
   changes nothing, so a project can format its fixtures for months before the first
   whitespace-sensitive payload arrives.

## How it was found

agnosai's `tests/definitions_loader.tcyr` carries a YAML fixture:

```cyr
var ydef = agnosai_load_from_yaml(str_from("agent_key: yaml-agent\n\
name: YAML Agent\nrole: reviewer\n..."), &err);
```

`cyrius fmt` indented `name: YAML Agent` by four spaces. In YAML that is a nesting
change, the document stopped being a mapping of four keys, and a passing suite began
failing on a file nobody had edited except by running the formatter. The same hazard
applies to any embedded payload with significant leading whitespace — YAML, Python
source, Makefiles, patch hunks, heredocs.

It also forces a workaround on generated sources: agnosai embeds eighteen JSON documents
as Cyrius source (`scripts/gen-presets.sh`), and the generator now has to run its own
output through `cyrius fmt` before committing it, purely so `fmt --check` and the
generator's `--check` stop contradicting each other. It also has to break lines only at
JSON token boundaries, because a break inside a `"description"` value would splice
`\n    ` into text a consumer displays.

## Expected

`fmt` leaves every byte between the opening and closing quote of a string literal alone,
including across backslash continuations. Reindenting the *first* line of the statement
is fine; continuation lines are string content.

## Repro

```sh
printf 'fn main(): i64 {\n    var s = str_from("abc\\\n def");\n    return str_len(s);\n}\n' > /tmp/probe.cyr
cyrius fmt /tmp/probe.cyr
```

The continuation line comes back indented to the statement body.

## Notes for the fix

The lexer already has to track literal state to find the closing quote — a
backslash-newline inside a literal is not a statement boundary, and the formatter's
line-splitting pass should be reading that state rather than re-deriving indentation per
physical line.

The two neighbouring cases were checked and are **fine** — a `#` inside a literal is not
read as a comment, and a `{` or `}` inside a literal does not move the indentation
level. So the formatter does track literal state somewhere; the continuation line is the
one place it is not consulted.

## Related

`docs/development/proposals/2026-08-10-embed-data-files-as-source-strings.md` — the
ergonomics gap that makes projects hand-write multi-line literals in the first place. A
first-class embed would remove most of the exposure to this bug, but not the bug.
