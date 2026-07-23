# Cyrius Issues — How to File

Active issue reports live here. Resolved items move to
[`archived/`](./archived/) — don't read archived/ looking for how
to file, read this.

## What belongs here

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
  language extensions go in `docs/development/roadmap.md` under
  "candidate themes", not here. The bar for an issue is: *someone
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

Filename stays stable across the move so external links keep
working.

## Recommended security floor

When filing a consumer bug, report the Cyrius version you're on
AND the recommended minimum you'd need for the fix to deploy.
The current recommended floor is **v5.0.0** (cycc IR, cyrius.cyml
manifest); v5.0.1+ adds the alloc/vec overflow-guard hardening and
v5.1.0+ adds macOS Mach-O support (per CLAUDE.md's DO-NOT block).

## Pointers

- [`archived/`](./archived/) — resolved issues, indexed.
- [`../roadmap.md`](../roadmap.md) — shipped / planned releases.
- [`../state.md`](../state.md) — current cycle state (version, cycc size, in-flight slots).
- `../../../CHANGELOG.md` — source of truth for what each release
  actually shipped.
