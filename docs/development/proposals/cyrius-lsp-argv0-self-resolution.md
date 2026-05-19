# `cyrius-lsp`: probe `argv[0]` to self-resolve `cycc`

**Filed:** 2026-05-02 alongside `consolidate-cyrius-lsp-claude-plugin`
**Severity:** Low — diagnostics work when `~/.cyrius/bin` is on the
inherited `PATH`; silently disabled when it isn't
**Affects:** `programs/cyrius-lsp.cyr` only — purely a `cyrius-lsp`
side fix; plugin / marketplace stay portable

## Summary

`cyrius-lsp` shells out to `cycc` for diagnostics. It currently
resolves `cycc` via the inherited environment's `PATH`. Run from an
interactive shell with `cyriusly setup` applied, that PATH includes
`~/.cyrius/bin` and everything works. Run under Claude Code's LSP
launcher (or another editor whose process inherits a minimal env),
the search fails and `cyrius-lsp` falls back to:

```
[cyrius-lsp] warning: cycc not found — diagnostics disabled
```

Diagnostics go silently off. The user gets the LSP attached, hover
events fire, but no `error:` markers ever surface — same broken
state as not having the LSP at all, but with no obvious failure
indicator.

The right fix is the trick `gopls`, `clangd`, `rust-analyzer`, etc.
use: **probe the LSP binary's own `argv[0]`, derive the bin
directory, and prepend it to the search path used for child
processes.** A toolchain installed coherently (compiler + LSP next
to each other under one `bin/` — the `cyriusly setup` and
`cyrius lsp` install pattern) then resolves regardless of how the
editor launched it.

## Today's workaround

Per-machine: add an `env.PATH` block to the Claude Code plugin's
`.lsp.json`, hard-coding the install directory. Documented in the
plugin README's "Open: cycc not found under Claude Code" section.
Doesn't generalize — every user who hits the silent-diagnostics
state has to know about the workaround and edit a JSON file to fix
it.

## Proposed fix

Inside `programs/cyrius-lsp.cyr`, on startup (before the first
`cycc` invocation):

1. Read `argv[0]`. The auxiliary vector parsing already in
   `lib/syscalls.cyr` / `lib/fdlopen.cyr` provides the path —
   `dynlib_bootstrap_environ` / `dynlib_auxv_get` etc. surface it.
2. If `argv[0]` contains a `/`, treat it as the absolute or
   relative path to the LSP binary; otherwise fall back to
   resolving via the inherited `PATH` (current behavior — but
   warn loudly with the resolved path).
3. Strip the basename to derive the install directory
   (`/home/<user>/.cyrius/bin/cyrius-lsp` → `/home/<user>/.cyrius/bin`).
4. When looking up `cycc`, check the derived directory FIRST, then
   fall back to the inherited `PATH`. Don't mutate `PATH` globally
   — pass the resolved absolute path to the `execve` of `cycc` and
   skip the search entirely.
5. Log the resolved `cycc` path on startup (stderr) so the user
   sees which `cycc` is being invoked — same shape as the existing
   `[cyrius-lsp] warning: cycc not found` line.

Behavior matrix after the fix:

| Launch context | argv[0] | cycc resolution |
|---|---|---|
| `cyrius-lsp` from interactive shell | bare name | inherited `PATH` (unchanged) |
| `~/.cyrius/bin/cyrius-lsp` from a wrapper | absolute | derive `~/.cyrius/bin/cycc` from argv[0] |
| Claude Code LSP launcher | absolute (Claude Code expands the binary path on launch) | derive `~/.cyrius/bin/cycc` |
| Symlinked into `/usr/local/bin/cyrius-lsp` | absolute (resolves to /usr/local/bin) | derive `/usr/local/bin/cycc` IF cycc lives there too; else fall back to `PATH` |

The symlink case wants one extra step: `realpath`-style resolution
of `argv[0]` so the directory derived is the *real* install dir,
not the symlink's directory. Most installs won't symlink (the
`cyrius lsp` install drops the binary directly into
`~/.cyrius/bin/`), so this can land in a follow-up if a consumer
trips on it.

## Why this and not env.PATH everywhere

The marketplace plugin currently keeps `.lsp.json` portable by
NOT setting `env.PATH` (which would have to hard-code a per-user
home directory — JSON values aren't shell-expanded). A plugin
that needs per-machine config to work isn't really a plugin; it's
half-shipped wiring. Self-resolution via `argv[0]` removes the
need for the workaround entirely — same property `gopls` enjoys.

## Testing

- New tcyr or smcyr that:
  1. Installs `cyrius-lsp` to a non-`PATH` location (e.g.,
     `/tmp/cyrlsp-test/cyrius-lsp` + `/tmp/cyrlsp-test/cycc`).
  2. Spawns it from a minimal env (`env -i /tmp/cyrlsp-test/cyrius-lsp`).
  3. Sends an `initialize` + `textDocument/didOpen` for a `.cyr`
     file with a known parse error.
  4. Asserts the diagnostic comes back (i.e., `cycc` was found
     and invoked).
- Pre-fix: assertion fails (cycc not found).
- Post-fix: assertion passes.

## Severity

LOW — same severity as the consolidate-plugin proposal. Diagnostics
silently disabled is annoying but not corrupting. The workaround
exists. Self-resolution makes the workaround unnecessary, removes
a per-user friction point, and brings `cyrius-lsp` in line with
the toolchain-resolution pattern every other major LSP uses.

## Slot estimate

One slot in a future v5.8.x or v5.9.x patch — not on the critical
path of slices true-completion (v5.8.14-v5.8.19), so naturally
slots after Phase 3 closeout (v5.8.37-v5.8.41) or whenever the
silent-diagnostics state surfaces in a consumer report.
