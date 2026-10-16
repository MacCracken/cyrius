# cyrius-lsp outside a project compiles a file from the server's working directory without its `#@incdir`, so a sibling `include` that `cyrius check` resolves is reported as `cannot open include file` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools: cyrius-lsp built from
`programs/cyrius-lsp.cyr` with 2026-10-12-lsp-diagnostics-column-file-and-extensions.md applied, this tree's `build/cycc`
and a CLI built from `cbt/cyrius.cyr` in a throwaway `$HOME/.cyrius/bin`). Met while fixing that issue: its diagnostics
now resolve a relative file name against the open file's directory (outside a project), but the compile they come from
does not resolve includes there.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Low — a wrong error in the editor for a loose file (no `cyrius.cyml` above it) whose editor started the
server somewhere other than the file's directory (an editor's workspace root): every sibling `include` is "cannot open",
and every name the include declares is then undefined. Inside a project the server runs `cyrius check`, which writes
`#@incdir`, so projects are not affected.
**Affects:** cyrius-lsp's raw-cycc path (`compile_and_capture`, programs/cyrius-lsp.cyr) since diagnostics existed; the
CLI has written `#@incdir` for an entry in a subdirectory since 6.5.7.

## Reproduction

```sh
# bash; $LSP = cyrius-lsp built from the tree, $CC = build/cycc, $CLI = build/cyrius
W=$(mktemp -d); mkdir -p "$W/h/.cyrius/bin" "$W/top/loose"
cp "$CC" "$W/h/.cyrius/bin/cycc"; cp "$CLI" "$W/h/.cyrius/bin/cyrius"
printf 'fn helper(): i64 { return 0; }\n' > "$W/top/loose/inc.cyr"
printf 'include "inc.cyr"\nvar x = helper();\n' > "$W/top/loose/main.cyr"
msg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
{ msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$W/top/loose/main.cyr\",\"text\":\"\"}}}"
  msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'; msg '{"jsonrpc":"2.0","method":"exit"}'; } \
  | (cd "$W/top" && env -i HOME="$W/h" PATH=/usr/bin:/bin timeout 30 "$LSP" 2>/dev/null) \
  | tr '\r' '\n' | grep -o '"uri":"[^"]*","diagnostics":.*' | sed "s|file://$W/||"
echo "== cyrius check from the same working directory:"
(cd "$W/top" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin "$W/h/.cyrius/bin/cyrius" check loose/main.cyr); echo "rc=$?"
```

```
"uri":"top/loose/main.cyr","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":17}},"severity":1,"source":"cyrius","message":"cannot open include file: inc.cyr"}]}}
== cyrius check from the same working directory:
ok: loose/main.cyr
rc=0
expected: no diagnostic for main.cyr — the file compiles, as `cyrius check` says
```

## Root cause

cycc resolves an `include` against its working directory first and then against the entry's directory — the latter
only when the source starts with a `#@incdir <dir>` line, which the CLI's `_materialize_source` writes for an entry in a
subdirectory. `compile_and_capture`'s raw path forks cycc with the file itself on stdin and inherits the server's
working directory, so there is no `#@incdir` and the entry's directory is never tried: a loose file's sibling include
resolves only when the editor launched the server in that file's directory.

## Proposed fix

Give the raw path the same unit `cyrius check` compiles: either run `cyrius check <file>` (standalone, no project
needed) when the CLI was found, or feed cycc `#@incdir <the file's dir>\n` followed by the file (a pipe instead of the
file as stdin; `#@srcline` after it so `<source>` lines are unchanged). Row (lsp_diagnostics_file_column.sh): the
repro above publishes an empty list for main.cyr; mutation (no `#@incdir`) RED.
