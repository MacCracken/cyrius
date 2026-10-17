# Editor Integration

Cyrius ships its own Language Server (`cyrius-lsp`). The Claude Code
wiring lives in the sibling repo
[`MacCracken/cyrius-plugins`](https://github.com/MacCracken/cyrius-plugins) —
install it once at user scope and every Cyrius project on the
machine picks up the LSP automatically (no per-repo `.lsp.json`).
Starter files for VS Code and Neovim ship in this repo under
[`editors/`](../../editors/).

## `cyrius-lsp` (the server)

`cyrius-lsp` is the in-tree LSP — JSON-RPC 2.0 over stdin/stdout.
Source lives at [`programs/cyrius-lsp.cyr`](../../programs/cyrius-lsp.cyr).

Capabilities (current):

- `initialize` / `initialized` — handshake / capabilities
- `textDocument/didOpen` — compile, return diagnostics
- `textDocument/didSave` — recompile, return diagnostics
- `textDocument/didChange` — recompile, return diagnostics
- `textDocument/definition` — go-to-definition (across included files)
- `textDocument/hover` — symbol kind + definition site
- `textDocument/documentSymbol` — file outline
- `textDocument/references` — find all uses
- `textDocument/semanticTokens/full` — function / variable / struct / enum /
  enum-member / keyword / parameter coloring
- `shutdown` / `exit` — exit cleanly

Diagnostics come from compiling the file **as saved on disk** (the server
does not read the editor's unsaved buffer). Inside a project — a directory
tree with a `cyrius.cyml` — it runs `cyrius check --with-deps --no-redirect <file>`
from the project root, so `[deps]` modules resolve and the open file itself is
the unit (`--no-redirect` skips the CLI's module redirect, which would compile
`src/main.cyr` in place of a file with no `include`; a project pinned to a
toolchain older than 6.7.12, which refuses the flag, is checked without it).
Outside one it compiles what `cyrius check <file>` compiles from the server's
working directory (6.7.13): `cyrius check <file>` there when the CLI is found,
else `cycc` with `#@incdir <dir>` and `#@srcline` ahead of the file — the
file named relative to that directory when it lies under it, so an `include`
of a sibling file resolves as it does for the CLI. (A file outside the
server's working directory gets no `#@incdir`, as `cyrius check` writes none
for it; until 6.7.13 every loose file was compiled that way, and a sibling
include read `cannot open include file` unless the editor had started the
server in the file's own directory.) Every extension in the table
below is compiled and indexed — `.cyr`, `.tcyr`, `.bcyr`, `.fcyr`, `.scyr`,
`.smcyr` (6.7.12; only `.cyr` was before).

Each `error:` / `warning:` line of the output becomes an LSP `Diagnostic`
(6.7.12):

- **Position.** cycc's `<file>:<line>:<col>:` gives the range: the column
  (`col - 1`, 0-based) to the end of that source line. The column is not
  repeated in the message.
- **File.** A diagnostic is published on the URI of the file it names, so an
  error inside an included file shows in that file, not at the same line
  number of the file you opened. `<source>` is the open file; a relative name
  resolves as cycc resolved it — against the project root (outside a project,
  the server's working directory), then the open file's directory. A name that
  resolves to no file stays on the open file's line 0, with its location kept
  in the message.
- **Stale files.** The server remembers which files each open document's
  compile published on; when a recompile no longer names one, it publishes an
  empty list there, so a fixed include's error does not stay.
- **No location.** A line with none (`error: …`) lands on the open file's
  line 0. The CLI's closing `error: <file> (compiler exit N)` verdict repeats
  the compiler's own errors, so it is shown only when there are none.

### Build / install

`cyrius-lsp` ships with every install (it is one of the release binaries),
so the installer already put it in `~/.cyrius/bin/`. Confirm with
`which cyrius-lsp`. To rebuild it from a cyrius checkout:

```sh
cyrius lsp           # build programs/cyrius-lsp.cyr → $CYRIUS_HOME/bin/cyrius-lsp (default ~/.cyrius)
```

`cyriusly setup` (also run from a checkout) builds and installs it with the
rest of the toolchain.

### Which compiler it runs

The server finds `cycc` and the `cyrius` CLI without relying on `PATH`, in
this order: `$HOME/.cyrius/bin/` (the active installed version), the
directory the `cyrius-lsp` binary itself lives in, `./build/`,
`/usr/local/lib/cyrius/`, then `$CYRIUS_HOME/`. It logs what it found to
stderr (`[cyrius-lsp] found cycc: …`), which most editors show in their LSP
log. Inside a project, `cyrius` then runs the toolchain version the
project's `cyrius.cyml` pins (`cyrius = "…"`, which must be installed), so
diagnostics match what `cyrius build` sees; outside a project they come from
`cyrius check` with the toolchain the CLI finds, or the `cycc` found above
when there is no CLI. A file outside any project reads no pin (6.7.14): the
server's working directory may itself be a project, but its `cyrius = "…"`
belongs to that project, so the loose file's check runs with the CLI's version
redirect off (`CYRIUS_RESOLVED=1`) and cycc's drift warning about that pin off
(`CYRIUS_NO_WARN_PIN_DRIFT=1`). In 6.7.13 a server started inside a project
that pins an uninstalled cyrius showed that project's `cyrius.cyml pins version
… but cyrius binary is not installed` error on line 1 of every loose file.

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

| Extension | Purpose                                        |
|-----------|------------------------------------------------|
| `.cyr`    | source / library modules                       |
| `.tcyr`   | test files (discovered by `cyrius test`)       |
| `.bcyr`   | benchmark files (`cyrius bench`)               |
| `.fcyr`   | fuzz harnesses (`cyrius fuzz`)                 |
| `.scyr`   | soak tests (`cyrius soak`, `tests/scyr/`)      |
| `.smcyr`  | smoke probes (`cyrius smoke`, `tests/smcyr/`)  |

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

See [`docs/development/archive/consolidate-cyrius-lsp-claude-plugin.md`](../development/archive/consolidate-cyrius-lsp-claude-plugin.md)
for the full rationale (drift, scaffold gaps, single edit point).

## Editor-specific notes

- **Claude Code** — install the plugin above; nothing else to do once
  `cyrius-lsp` is on `PATH`.
- **VS Code** — [`editors/vscode/`](../../editors/vscode/) is a minimal
  extension: a `vscode-languageclient` client that starts `cyrius-lsp`
  (from `$CYRIUS_HOME/bin/` — `~/.cyrius/bin/` when `CYRIUS_HOME` is unset —
  then `~/.local/bin/`, then `/usr/local/bin/`), plus a TextMate grammar
  and bracket / comment configuration. It registers `.cyr` only.
- **Neovim** — [`editors/neovim.lua`](../../editors/neovim.lua) maps `.cyr`
  to the `cyrius` filetype and starts `cyrius-lsp` with `vim.lsp.start`.
  ⚠ Its project-root marker is `cyrius.toml`; a cyrius project's manifest is
  `cyrius.cyml`, so change that name (or rely on its `.git` fallback).
- **Helix / Zed / generic LSP managers** — most expect their own
  config file, but the `.lsp.json` shape above is portable enough to
  lift verbatim into per-editor configs.
- **JetBrains** — no wiring ships here; a custom-LSP plugin can spawn
  `cyrius-lsp`.

## Highlighting

`cyrius-lsp` provides `textDocument/semanticTokens/full` for editors that
consume LSP semantic tokens; its legend is `function`, `variable`, `struct`,
`enum`, `enumMember`, `keyword` and `parameter`. Literals, operators,
comments and built-in type names get no semantic token, so an editor colors
those from its grammar — for VS Code the TextMate grammar in
[`editors/vscode/syntaxes/cyrius.tmLanguage.json`](../../editors/vscode/syntaxes/cyrius.tmLanguage.json),
which is also the whole of the highlighting in an editor that does not speak
semantic tokens.

## Troubleshooting

- **No diagnostics**: confirm `cyrius-lsp` resolves on PATH (the editor
  inherits PATH at launch — restart it after installing), and that the file
  has a cyrius extension (`.cyr`, `.tcyr`, `.bcyr`, `.fcyr`, `.scyr`,
  `.smcyr`) — the server compiles only those. Its stderr log names the
  `cycc` / `cyrius` it found.
- **Stale errors**: diagnostics are computed from the file on disk. Edits
  trigger a recompile (`didChange`), but of the last saved contents — save
  to see diagnostics for what you typed.
- **Wrong language attached**: editors that *also* have a built-in
  guesser may win over `.lsp.json` for ambiguous extensions — set the
  language id explicitly if that happens.
