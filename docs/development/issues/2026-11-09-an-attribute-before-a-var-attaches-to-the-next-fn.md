# An attribute before a `var` or `const` silently attaches to the next fn — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-09 against cyrius 6.7.18 (`31c24ca9b`), x86_64.
**Placement:** `src/frontend/parse/fn/def.cyr`. `_tl_directive` (:37-58) arms a pending flag "PARSE_FN_DEF
transfers onto the next fn", and `_tl_deprecated` (:102) does the same for its message. Nothing clears the
pending state when a top-level declaration that is not a fn (`var`, `const`, `struct`, `enum`) comes first.
**Filed:** 2026-11-09 from taar 0.9.1, while deprecating its renamed constants (taar ADR 0002).
**Severity:** Medium.
- **Silent:** the build is `OK`, `cyrius lint` reports 0 warnings, and the
  attribute lands on a function its author never marked.
- **Consumers are misled:** a library that tries to deprecate a constant tells
  every caller of some unrelated function that it is deprecated, with the
  constant's message.
- **`#must_use` does it too:** an unrelated function's dropped result starts
  warning.

**Affects:** every one-token fn attribute and `#deprecated(...)`. The table in
`src/frontend/lex/attr.cyr:88-97` lists `#must_use`, `#deprecated`, `#pure`,
`#io`, `#alloc`, `#naked`, `#inline` and `#regalloc`. Only `#deprecated` and
`#must_use` were reproduced; the rest share the same pending-flag path.

## Repro

[`repros/2026-11-09-an-attribute-before-a-var-attaches-to-the-next-fn.cyr`](repros/2026-11-09-an-attribute-before-a-var-attaches-to-the-next-fn.cyr)
covers `#deprecated` and `#must_use` together. The shortest form:

```cyrius
#deprecated("use NEW_V")
var OLD_V = 7;
# an unrelated helper
fn helper(): i64 { return 7; }
fn main() { return OLD_V - helper(); }
var r = main();
syscall(60, r);
```

```
$ cyrius build t_next.cyr t_next.out
warning:<source>:5:35: 'helper' is deprecated: use NEW_V
OK (4464 bytes)
$ cyrius lint t_next.cyr
0 warnings
```

- **`OLD_V`** is read on line 5 with no warning.
- **`helper`**, which nothing marked, warns with `OLD_V`'s message.
- **`const` behaves the same:** `#deprecated("…") const OLD_C = 7;` puts the
  warning on the next fn.
- **`#must_use` behaves the same:**
  `#must_use var X = 1; fn f(): i64 { return 1; } fn main() { f(); … }` warns
  "#must_use result of 'f' is discarded".

## Expected

An attribute applies to the declaration directly after it, or is refused there:

- **Now:** a pending fn attribute that meets a non-fn top-level declaration is
  an error at the attribute: "#deprecated applies to a fn; it is followed by a
  `var` (line N)". The rule matches 6.6.10's "report at the directive, not at
  the `fn` after it" for a bare `#deprecated`.
- **Later:** `#deprecated` on a `var` / `const` becomes real; that is the
  proposal `proposals/2026-11-09-deprecated-constants.md`. Until then the error
  is the honest answer.

## Workaround

Do not put an attribute before a `var` or `const`. taar 0.9.1 deprecates its
renamed constants in their doc comment only, and says why
(`taar/src/socket.cyr`, `taar/src/ipv4.cyr`).
