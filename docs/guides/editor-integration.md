# Editor Integration

Cyrius ships its own Language Server (`cyrius-lsp`). The Claude Code
wiring lives in the sibling repo
[`MacCracken/cyrius-plugins`](https://github.com/MacCracken/cyrius-plugins) —
install it once at user scope and every Cyrius project on the
machine picks up the LSP automatically (no per-repo `.lsp.json`).

## `cyrius-lsp` (the server)

`cyrius-lsp` is the in-tree LSP — JSON-RPC 2.0 over stdin/stdout.
Source lives at [`programs/cyrius-lsp.cyr`](../programs/cyrius-lsp.cyr).

Capabilities (current):

- `initialize` — handshake / capabilities
- `textDocument/didOpen` — compile, return diagnostics
- `textDocument/didSave` — recompile, return diagnostics
- `textDocument/didChange` — recompile, return diagnostics
- `shutdown` — exit cleanly

Diagnostics are produced by invoking the in-tree compiler (`cc5`) and
parsing its `error:<file>:<line>: <msg>` output back into LSP
`Diagnostic` records.

### Build / install

```sh
cyrius lsp           # build programs/cyrius-lsp.cyr → ~/.cyrius/bin/cyrius-lsp
```

`cyriusly setup` also auto-installs it. Confirm with `which cyrius-lsp`.

## `.lsp.json` wiring

The `.lsp.json` shape Claude Code and similar tools expect:

```json
{
  "cyrius": {
    "command": "cyrius-lsp",
    "args": [],
    "extensionToLanguage": {
      ".cyr":   "cyrius",
      ".tcyr":  "cyrius",
      ".bcyr":  "cyrius",
      ".fcyr":  "cyrius",
      ".scyr":  "cyrius",
      ".smcyr": "cyrius"
    }
  }
}
```

Same shape `gopls` uses (`{"go": {"command": "gopls", "args":
["serve"], "extensionToLanguage": {".go": "go"}}}`) — no adapter
needed.

**Don't drop this file into each Cyrius project.** That was the
original wiring and it caused silent drift across repos. Use the
plugin instead — see below.

All `.cyr`-family extensions route to one server:

| Extension | Purpose                                |
|-----------|----------------------------------------|
| `.cyr`    | source / library modules               |
| `.tcyr`   | test files (auto-discovered by check)  |
| `.bcyr`   | benchmark files                        |
| `.fcyr`   | fuzz harnesses                         |
| `.scyr`   | soak tests                             |
| `.smcyr`  | smoke probes                           |

## Claude Code: install the plugin (recommended)

The `.lsp.json` lives in [`MacCracken/cyrius-plugins`](https://github.com/MacCracken/cyrius-plugins),
a sibling repo serving as a Claude Code marketplace for Cyrius
toolchain plugins. Install once at user scope:

```sh
/plugin marketplace add MacCracken/cyrius-plugins
/plugin install cyrius-lsp@cyrius-plugins
```

Every Cyrius project on the machine then picks up the LSP
automatically — no per-repo `.lsp.json` to copy or sync.

See [`docs/development/proposals/consolidate-cyrius-lsp-claude-plugin.md`](development/proposals/consolidate-cyrius-lsp-claude-plugin.md)
for the full rationale (drift, scaffold gaps, single edit point).

## Editor-specific notes

- **Claude Code** — install the plugin above; nothing else to do once
  `cyrius-lsp` is on `PATH`.
- **Helix / Zed / generic LSP managers** — most expect their own
  config file, but the `.lsp.json` shape above is portable enough to
  lift verbatim into per-editor configs.
- **VS Code / JetBrains** — extension-side wiring lives outside this
  repo; both can spawn `cyrius-lsp` via custom-LSP plugins.

## Highlighting

`cyrius-lsp` does not yet provide semantic-tokens. For syntax
highlighting today, fall back to the editor's TextMate / regex grammar
(or treat as plain text). A `cyrius.tmLanguage` grammar slot is on the
roadmap; track it in [`docs/development/roadmap.md`](development/roadmap.md).

## Troubleshooting

- **No diagnostics**: confirm `cyrius-lsp` resolves on PATH (the editor
  inherits PATH at launch — restart after `cyriusly setup`).
- **Stale errors**: the server recompiles on `didSave` and `didChange`;
  if your editor batches `didChange`, save to force a refresh.
- **Wrong language attached**: editors that *also* have a built-in
  guesser may win over `.lsp.json` for ambiguous extensions — set the
  language id explicitly if that happens.
