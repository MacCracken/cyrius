# TOML single-bracket section syntax (`[name]`) in `lib/toml.cyr`

**Filed:** 2026-05-17 during commandress v0.2.0 config-loader work
**Severity:** Quality-of-life — current consumers can spell single sections as `[[name]]` (array-of-tables); the gap is conformance to the TOML spec, not a build blocker.
**Affects:** `lib/toml.cyr::toml_parse` (single concentrated change). No `lib/cyml.cyr` impact — CYML uses `[[entries]]` as its only special marker; everything else lives in the body zone.
**Target slot:** v6.x (per `project_v5_11_x_closeout_at_40`) — additive, no ABI impact.

## Summary

Cyrius's `lib/toml.cyr` parser recognises `[[name]]` (TOML's array-of-tables marker) but silently drops `[name]` (TOML's regular-table marker — by far the more common form in real-world TOML). Every Cyrius consumer writing a TOML-shaped config either has to use `[[name]]` for what's semantically a single section, or roll their own parser.

This proposal asks the parser to grow `[name]` support alongside the existing `[[name]]`, matching standard TOML semantics: `[name]` opens a single table; `[[name]]` opens (or appends to) an array of tables under that key. The fix is ~10 lines in `toml_parse`'s dispatch.

## Motivation — the concrete tax

### commandress's config schema, as written today

```cyml
[[prompt]]
segments  = ["cwd", "exit"]
separator = " "
trailer   = " $ "

[[segments.cwd]]
home_shorten = true

[[segments.exit]]
hide_zero = true
```

What we'd write if `[name]` worked:

```cyml
[prompt]
segments  = ["cwd", "exit"]
separator = " "
trailer   = " $ "

[segments.cwd]
home_shorten = true

[segments.exit]
hide_zero = true
```

The double-bracket form is semantically wrong: `[[prompt]]` claims the schema can have *multiple* `prompt` sections, which it can't. A reader familiar with TOML reads `[[prompt]]` and asks "where are the other ones?". The two forms have different parse semantics in standard TOML — Cyrius treats them identically, which is also wrong.

### Other Cyrius consumers that would benefit

Any project parsing TOML-shaped configs:

- **vidya** — content metadata. Currently uses `[[entries]]` because that IS the array-of-tables case (multiple entries per file); the proposal doesn't touch this. But any future top-level `[meta]` section is forced into `[[meta]]`.
- **kriya** — coreutils. If kriya ever grows a user config (`.kriyarc`, etc.), single-section configs would want `[name]`.
- **agnoshi** — shell. Same — user shell config naturally wants `[shell]`, `[history]`, `[completion]` as single sections.
- **commandress** — the immediate driver.
- **any package manifest** — `cyrius.cyml`'s `[package]` / `[build]` / `[deps]` are themselves single sections. Today they parse correctly because Cyrius reads `cyrius.cyml` with bespoke code, not `lib/toml.cyr`. If we ever consolidate, the proposal becomes load-bearing.

## Why not just keep using `[[name]]` for single sections

- **Spec divergence.** Cyrius's TOML parser claims to parse TOML; failing to handle `[name]` is the single biggest divergence from the spec. Consumers reading other people's TOML configs (e.g., a `Cargo.toml`-shaped file for interop) hit it on day one.
- **Semantic correctness.** `[[name]]` means "this is one of potentially many"; `[name]` means "this exists at most once". Tools and humans both rely on the distinction.
- **Cross-project consistency.** Every new Cyrius consumer has to learn the workaround. The cost is small per project (one comment in the schema docs) but cumulative across consumers.
- **Onboarding friction.** Users coming from starship/Cargo/Hugo/etc. expect `[section]` to work. The first time they edit `~/.commandress.cyml` and find their `[prompt]` section silently ignored, they file a bug.

## Proposed syntax

Standard TOML. `[name]` opens a single table; `[[name]]` opens an array of tables. The two are distinct:

```cyml
# Single table — at most one [database] section per file
[database]
host = "localhost"
port = 5432

# Array of tables — one [[server]] per server
[[server]]
name = "alpha"

[[server]]
name = "beta"
```

`toml_get_sections(sections, "database")` returns a vec of length 1 (or 0 if absent).
`toml_get_sections(sections, "server")` returns a vec of length N.

The existing API surface stays identical — `toml_get_sections` already returns a vec, so callers don't care whether the underlying type was single or array.

## Proposed implementation

In `lib/toml.cyr::toml_parse` line 173, the current dispatch:

```cyrius
# Array of tables: [[name]]
elif (c == 91 && pos + 1 < slen && load8(data + pos + 1) == 91) {
    ...
}
```

Add a sibling branch for `[name]`:

```cyrius
# Single table: [name]  (NEW)
elif (c == 91 && pos + 1 < slen && load8(data + pos + 1) != 91) {
    # Save current section if it has pairs
    if (vec_len(cur_pairs) > 0) {
        vec_push(sections, toml_section_new(cur_name, cur_pairs));
    }
    pos = pos + 1;
    var nstart = pos;
    while (pos < slen && load8(data + pos) != 93) { pos = pos + 1; }
    cur_name = str_new(data + nstart, pos - nstart);
    if (pos < slen && load8(data + pos) == 93) { pos = pos + 1; }
    cur_pairs = vec_new();
    while (pos < slen && load8(data + pos) != 10) { pos = pos + 1; }
}

# Array of tables: [[name]]
elif (c == 91 && pos + 1 < slen && load8(data + pos + 1) == 91) {
    ...  (unchanged)
}
```

That's the entire surface. Existing callers (vidya, anything using `[[entries]]`) keep working byte-for-byte. New callers (commandress, future agnoshi config, etc.) can use the natural `[name]` form.

Optional follow-up: distinguish single-vs-array semantically. Today `toml_section_new` stores `(name, pairs)` and `toml_get_sections` returns vec of matches. The proposal can keep this as-is — `[name]` produces one entry, `[[name]]` produces N — without exposing the distinction to callers. If a caller does want to enforce "single section only", they assert `vec_len(matches) <= 1` after lookup. Future API: `toml_get_section(sections, name)` returns the first match or 0.

## Test cases

```cyrius
# Single table parses correctly
var s = toml_parse(str_from("[a]\nk = 1\n"));
var as = toml_get_sections(s, "a");
assert(vec_len(as) == 1);

# Array of tables still works
var s2 = toml_parse(str_from("[[b]]\nk = 1\n[[b]]\nk = 2\n"));
var bs = toml_get_sections(s2, "b");
assert(vec_len(bs) == 2);

# Mixed file
var s3 = toml_parse(str_from("[meta]\nname = \"x\"\n[[items]]\nv = 1\n[[items]]\nv = 2\n"));
assert(vec_len(toml_get_sections(s3, "meta")) == 1);
assert(vec_len(toml_get_sections(s3, "items")) == 2);
```

Negative tests:

```cyrius
# Unclosed bracket — should not corrupt subsequent parse
var s = toml_parse(str_from("[unclosed\nk = 1\n[good]\nk2 = 2\n"));
# (define expected behavior — error reporting model TBD)
```

## Consumer-side preview

Once this lands, commandress's [`src/config.cyr`](https://github.com/MacCracken/commandress/blob/main/src/config.cyr) updates from `[[prompt]]` to `[prompt]` (and analogous for the two `[[segments.X]]` blocks); the example config at [`docs/examples/commandress.cyml.example`](https://github.com/MacCracken/commandress/blob/main/docs/examples/commandress.cyml.example) follows. The migration note for users:

> v0.X.Y: `~/.commandress.cyml` now accepts standard TOML `[section]` syntax. The old `[[section]]` form keeps working — both produce identical config — but new examples use the single-bracket form.

That's the whole consumer story.

## Related items

- [`../issues/2026-05-17-commandress-stdlib-papercuts.md`](../issues/2026-05-17-commandress-stdlib-papercuts.md) Item 3 — the consumer-side report.
- [TOML v1.0.0 spec — Tables](https://toml.io/en/v1.0.0#table) — the syntax this proposal aligns with.
- [TOML v1.0.0 spec — Array of Tables](https://toml.io/en/v1.0.0#array-of-tables) — what `[[name]]` actually means.
