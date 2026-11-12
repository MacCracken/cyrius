# `#deprecated` on a `var` / `const` — warn where a renamed constant is read

**Filed:** 2026-11-09 from taar 0.9.1. Its 1.0 surface review (taar ADR 0002) renamed three public constants, and
cannot warn their readers.
**Status:** 🟡 **PROPOSED** — an extension of an existing attribute, with a defect it would also close
(`issues/2026-11-09-an-attribute-before-a-var-attaches-to-the-next-fn.md`).
**Placement:** the 6.x-line backlog, after that issue's refusal lands. The refusal is the safe interim; this
proposal turns the refused case into a supported one.
**Severity:** Quality-of-life. Nobody is blocked. Renames simply break readers with no warning, at the release
that removes the old name.
**Affects:** the front end: `src/frontend/parse/fn/def.cyr` (`_tl_deprecated`), the top-level `var` / `const`
parse, and the use sites that read a global. The warning text is already in `src/frontend/parse/fn/call.cyr:88`
("' is deprecated"). No backend or IR change: a deprecated constant compiles exactly as an undecorated one.

## Summary

`#deprecated("…")` works on a `fn` and on a `const fn`: every call site warns,
on every backend (CHANGELOG 6.6.9 / 6.6.10). A library that renames a function
can therefore keep the old name as a warned alias for a release, and consumers
learn about the rename from their own build. A library that renames a
**constant** cannot do the same. The library's options today:

- **Keep the old name silently.** taar 0.9.1 does this for `_TAAR_ERR_TIMEOUT`,
  `_TAAR_ERR_INTR` and `IPV4_PARSE_FAIL`. Its consumers learn nothing until the
  release that removes the name stops their build.
- **Remove it at once,** breaking every reader at the release that renames it.
- **Try `#deprecated` anyway.** Today this marks the next function instead (the
  issue above).

This proposal asks for:

```cyrius
#deprecated("use TAAR_ERR_TIMEOUT; _TAAR_ERR_TIMEOUT is removed at taar 1.0.0")
var _TAAR_ERR_TIMEOUT = 0 - 11;

#deprecated("use NEW_LIMIT")
const OLD_LIMIT = 64;
```

**The semantics:** each *read* of the name outside its own declaration warns
`'_TAAR_ERR_TIMEOUT' is deprecated: <message>`, once per site. That is the fn
rule, with "call" replaced by "read".
- **Writes warn too:** `OLD = 3` warns, because a deprecated mutable global is
  being kept alive by its writer.
- **Lint stays silent,** as it is for fns. The warning is the compiler's, so a
  consumer's lint gate stays green while its build names each site.

## Motivation

taar is a network library with three consumers: yo, dig and whirl. Its 1.0
review renamed every unprefixed or wrongly-prefixed public name, keeping the old
names as aliases until 1.0.0:

| Was | Is | Warns today? |
|---|---|---|
| `ipv4_parse`, `ipv4_format_to_buf` | `taar_ipv4_*` | yes: `#deprecated` fn alias |
| `taar_sock_close` | `taar_tcp_close` | yes |
| `IPV4_PARSE_FAIL` | `TAAR_IPV4_PARSE_FAIL` | **no** |
| `_TAAR_ERR_TIMEOUT`, `_TAAR_ERR_INTR` | `TAAR_ERR_*` | **no** |

The constants are the names consumers *branch on*:
- dig compares against `IPV4_PARSE_FAIL` at 6 sites;
- the error constants are the only error values taar's contract lets a caller
  test.

Those are the renames a consumer most needs to hear about, and the only ones
the toolchain cannot announce.

This is not taar-specific. cyrius's own constants migration
(`issues/2026-10-08-lib-public-constants-const-migration.md`) moves stdlib
publics to `const`. Any rename in that migration, or after it, has the same
gap.

## Design notes

- **One flag, one message, as fns have.** The fn side already stores a message
  token per fn (`_fndep_base`, `src/common/util.cyr:488`) and a flags word
  (`_fnflg_base`, :494). A global needs the same pair, keyed by the global's
  index.
- **`const` folding.** A `const` whose value is folded into its use sites still
  has a use site to warn at. The warning belongs to name resolution, not to code
  generation.
- **`enum` members** could reuse it later. This proposal leaves them out.
- **Other attributes before a `var`** (`#must_use`, `#pure`, …) stay refused, as
  the issue proposes. Only `#deprecated` has a meaning for a value.

## Consumer workaround meanwhile

Document the deprecation in the constant's doc comment, keep the value
identical, and list the rename in the release notes and in the consumers'
migration notes. That is what taar 0.9.1 does.
