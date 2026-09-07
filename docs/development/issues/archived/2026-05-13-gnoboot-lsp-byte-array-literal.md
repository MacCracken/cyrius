# cyrius-lsp doesn't recognize byte-array literal syntax (v5.11.51 feature) — papercut

**Discovered:** 2026-05-13 during gnoboot Step 4 development against cyrius 5.11.51+
**Severity:** Low — diagnostic noise only; `cyrius build` works correctly, the LSP just spams a misleading error on every save. No build impact. Fine candidate to roll into the next routine patch.
**Affects:** cyrius-lsp shipped with cc5 5.11.51 / 5.11.52 / 5.11.53.

## Summary

The byte-array literal syntax (`var foo[N] = { 0x.., 0x.., ... };`,
landed in cyrius 5.11.51 per
[`archived/2026-05-13-gnoboot-byte-array-literal.md`](2026-05-13-gnoboot-byte-array-literal.md))
is parsed and emitted correctly by `cc5` — gnoboot uses it
extensively for UTF-16LE strings + EFI GUIDs (~10 declarations in
`src/main.cyr`) and `cyrius build` produces a working binary.

But the `cyrius-lsp` binary emits a parse-error diagnostic on every
file edit:

```
main.cyr:
  ✘ [Line 1:1] expected ';', got '=' (cyrius)
```

Line 1 is a comment (`# gnoboot — …`), so the column-1 line-1 anchor
is a red herring. The actual offending token is the `=` after the
first `var foo[N]` declaration, which the LSP's parser still treats
as a pre-v5.11.51 `expected ';'` site.

## Reproduction

```sh
cat > /tmp/repro.cyr <<'EOF'
kernel;
var foo[2] = { 0x11, 0x22, 0x33, 0x44 };
EOF
cyrius build /tmp/repro.cyr /tmp/repro.efi
# Result: compile /tmp/repro.cyr -> /tmp/repro.efi [x86_64] OK
#         (binary produced correctly, byte-array literal honored)

# Now have the LSP look at the same file (Zed / VS Code / etc):
# Expected diagnostic: none.
# Actual diagnostic:
#   ✘ [Line 1:1] expected ';', got '=' (cyrius)
```

The error fires on a one-statement file, so it's reproducible
without the full gnoboot tree. Easier still:

```sh
cyrius-lsp --version    # whatever this surfaces — useful for the fix audit
```

vs. cc5 5.11.53.

## Root cause (speculation)

The cyrius-lsp embeds its own parser (or links against a frozen
copy of the cyrius frontend) that wasn't updated when
`PARSE_GVAR_ARR` was extended in v5.11.51 to accept the
`= { byte-list }` tail. The cc5 frontend has the new path
(`src/frontend/parse_decl.cyr:533` per the v5.11.51 CHANGELOG
implementation block); the LSP's parser is probably the same
file, but the LSP binary in `.cyrius/versions/5.11.5{1,2,3}/bin/`
was built without picking up that change — perhaps the LSP build
target wasn't on the dependency graph of the new feature.

Symmetric LSP gaps may exist for the v5.11.52 `fn efi_main`
convention recognition (the LSP should ideally surface efi_main
as the entry point in document outline); haven't checked, but
worth a glance while in the same code path.

## Proposed fix (sketch)

Whatever build / regen step produces `cyrius-lsp` from the
frontend grammar — re-run it. If the LSP statically links
`src/frontend/parse_decl.cyr`, a rebuild against the 5.11.51+
sources should fix it.

A small LSP-level regression test would lock it in: open a
`.cyr` buffer containing the byte-array literal, assert zero
diagnostics from cyrius-lsp.

## Consumer-side workaround

None needed — `cyrius build` and gates work cleanly; only the
editor-side diagnostic is wrong. Editor users can mentally ignore
the recurring `Line 1:1 expected ';'` until the LSP is refreshed.
A `// @ts-ignore`-style suppression hint inside cyrius source
isn't a cyrius feature today and would be overkill for this papercut.

## Pointers

- cyrius byte-array literal landed: v5.11.51,
  `cyrius/CHANGELOG.md` [5.11.51], archived issue
  `2026-05-13-gnoboot-byte-array-literal.md`.
- gnoboot use site: `/home/macro/Repos/gnoboot/src/main.cyr`
  (any of the ~10 `var msg_* = { ... }` or `var li_guid = { ... }`
  declarations triggers it).
- gnoboot CHANGELOG note: `gnoboot/CHANGELOG.md` mentions the
  recurring LSP diagnostic in the *Known cyrius constraints* /
  Step 5 entries.
