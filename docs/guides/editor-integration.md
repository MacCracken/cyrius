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
tree with a `cyrius.cyml` — each file is checked through its **unit**: the entry
that includes it, on the target that includes it (6.7.16; see *How a file's unit
is chosen* below). A unit is compiled with `cyrius check --with-deps --no-redirect
<entry>` from the project root, the entry named relative to it, so `[deps]`
modules resolve and the CLI writes the entry's `#@incdir` (`--no-redirect` skips
the CLI's module redirect, which would compile `src/main.cyr` in place of a file
with no `include`; a project pinned to a toolchain older than 6.7.12, which
refuses the flag, is checked without it). Outside one it compiles what `cyrius check <file>` compiles from the server's
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
  number of the file you opened. `<source>` is the unit's entry (the open file
  when it is its own unit); a relative name resolves as cycc resolved it —
  against the project root (outside a project, the server's working directory),
  then the entry's directory. A name that resolves to no file stays on the open
  file's line 0, with its location kept in the message.
- **Stale files.** The server remembers which files each unit's compile
  published on (the open file too, when its list was not empty); when a
  recompile of that unit — from any of its files — no longer names one, it
  publishes an empty list there, so a fixed include's error does not stay.
- **No location.** An error with none (`error: …`) lands on the open file's
  line 0; a warning with none (`warning: large static data …`) is the unit's,
  on its entry's line 0. The CLI's closing `error: <file> (compiler exit N)`
  verdict repeats the compiler's own errors, so it is shown only when there are
  none.
- **Whole output.** The compiler's output is read to its end (up to 64 MiB,
  named in the log past that); until 6.7.16 only its first 8,191 bytes were, so
  a unit's warnings could push the open file's own error past the cut.

### How a file's unit is chosen

A project file is rarely compiled on its own: `src/frontend/parse_ctrl.cyr` is
an `include` of `src/main.cyr` and uses names the files before it declare.
Until 6.7.16 the server compiled the open file alone, so every such name read
`undefined` (55 false errors on that file). Now it keeps the project's include
graph — every `.cyr` under the root except hidden directories, the root's
`build/` and `dist/`, and a subdirectory with its own `cyrius.cyml`; each
column-0 `include "x"` resolved as cycc resolves it (the root, then the entry's
directory) and marked with the targets its `#ifdef` / `#ifndef` stack lets it
through — and checks each file in one of five modes:

| Mode | When | What is compiled | What is published |
|---|---|---|---|
| itself | the file is an entry: the manifest's `[build] entry`, or a `.cyr` no other includes (a test file is always its own) | the file | its list, and each file the compile names (as before) |
| fragment | an entry includes it, on the server's own target | that entry | its list, and each named file whose own unit is the same entry |
| peer | an entry includes it only under `CYRIUS_TARGET_WIN`, `_AGNOS`, `CYRIUS_MACHO` or `_EFI` (an x86_64 Linux server selects these) | that entry, with the selector in its environment | its list only |
| note | only a target the server cannot compile for includes it (aarch64, cx) | nothing | one Information diagnostic saying so |
| skip | `[lsp] skip` names it | nothing | an empty list |

A fragment reached by several entries is checked through the manifest's entry
when that reaches it, else the one with the fewest include hops, then the first
in path order; a test file's includes never make anything a fragment. When a
fragment's or a peer's own list is clean but its unit has errors in other files,
it gets one Information line naming the unit (`checked as part of src/main.cyr,
which has 2 errors in other files`).

`lib/` follows the stdlib's own contract (`tests/gates/toolchain/
stdlib_modules_self_sufficient.sh`): a **peer** is `lib/<R>_<x>.cyr` where
`lib/<R>.cyr` exists, included by `R`'s family, with no `# Usage: include` line
of its own and no distlib marker (`lib/syscalls_windows.cyr`, `lib/fs_win.cyr`);
everything else is a public module, checked as `include "lib/<m>.cyr"` alone —
no `[deps]` prepend, so none of the duplicate-fn warnings checking it with the
prepend gave — and a peer through its nearest public includer under the target
that includes it (`lib/syscalls_windows.cyr` through `lib/syscalls.cyr` under
`CYRIUS_TARGET_WIN=1`). The include line lives in a file in a private directory
the server makes under `$TMPDIR` (mode 0700) for that one compile and removes
after it.

The graph is kept per project root and refreshed by each file's mtime and size;
opening a file it does not hold walks the tree again. A unit's compile is kept
on its files' mtimes and sizes, `lib/`, `cyrius.cyml`, `cyrius.lock` and the
`cyrius` / `cycc` binaries, so opening N fragments of one entry costs one
compile (the first fragment of cycc's own `src/main.cyr` costs about 1.5 s). The
manifest entry and `[lsp] skip` are read through `cyrius build --print-config`,
the CLI's own manifest reader. Go-to-definition indexes the unit's entry too,
so a name an earlier include of the entry declares is found from a fragment;
includes resolve from the project root (a loose file's: the server's working
directory), not from wherever the server was started.

**`[lsp] skip`** lists files the server never compiles, as paths from the
project root — a `.cyr` that is not cycc input. This repo's `cyrius.cyml`:

```toml
[lsp]
skip = ["bootstrap/cybs.cyr"]   # assembly for the seed's bootstrap/asm
```

### Build / install

`cyrius-lsp` is one of the release binaries, so a Linux or macOS install
already put it in `~/.cyrius/bin/`. Confirm with `which cyrius-lsp`. (Until
6.7.16 the macOS tarballs built a hand list without it.) The Windows install
has none: cycc_win refuses the server (`sys_fstat` and `sys_readlink` have no
PE wrapper, and it runs its compiler through fork and pipes). To rebuild it
from a cyrius checkout:

```sh
cyrius lsp           # build programs/cyrius-lsp.cyr → $CYRIUS_HOME/bin/cyrius-lsp (default ~/.cyrius)
```

`cyriusly setup` (also run from a checkout) builds and installs it with the
rest of the toolchain.

### Which compiler it runs

The server finds `cycc` and the `cyrius` CLI without relying on `PATH`, in
this order: `$HOME/.cyrius/bin/` (the active installed version), the
directory the `cyrius-lsp` binary itself lives in, `./build/`,
`/usr/local/lib/cyrius/`, then `$CYRIUS_HOME/`. `HOME` and `CYRIUS_HOME` are
read with the stdlib's `getenv`, and the environment it hands the `cyrius`
child is the stdlib's `env_block` (6.7.16): on macOS, which has no `/proc`, the
server read neither until then, found no compiler and published no diagnostics.
Its own directory comes from `/proc/self/exe` on Linux, and on macOS from
`argv[0]` resolved with `fcntl(F_GETPATH)`, so a server launched by a path
finds the `cycc` beside it with no `HOME` at all; a bare `cyrius-lsp` found
through `PATH` gives it no directory there. It logs what it found to stderr
(`[cyrius-lsp] found cycc: …`), which most editors show in their LSP log.
Inside a project, `cyrius` then runs the toolchain version the
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
- **Which unit**: the log names the unit each compile is for (`compiling unit
  src/main.cyr (fragment, x86_64 Linux)`; `… reused` when nothing it depends on
  changed on disk). A `.cyr` in the project that is not cycc input belongs in
  `[lsp] skip`.
- **Wrong language attached**: editors that *also* have a built-in
  guesser may win over `.lsp.json` for ambiguous extensions — set the
  language id explicitly if that happens.
