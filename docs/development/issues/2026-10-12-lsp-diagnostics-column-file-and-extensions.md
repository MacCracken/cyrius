# cyrius-lsp diagnostics: the column lands in the message, an included file's error lands on the open file, and `.tcyr` / `.bcyr` / `.fcyr` / `.scyr` / `.smcyr` get nothing — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B): `cyrius-lsp` built from `programs/cyrius-lsp.cyr` by that `build/cycc` (byte-identical to
the tree's `build/cyrius-lsp`), with `build/cycc` and a CLI built from `cbt/cyrius.cyr` in a throwaway
`$HOME/.cyrius/bin`, driven over stdio with `initialize` / `didOpen` / `shutdown` / `exit`. Outside a project:
`col.cyr` (error at 2:14) publishes `line 1, character 0–100, message "14: undefined variable 'nope' …"`;
`main.cyr` (3 lines, including `inc.cyr`, whose line 7 has the error) publishes a diagnostic at line 6 of
`main.cyr` with message `"24: undefined variable 'undefined_name' …"`; `t.tcyr` (an error at line 2) gets no
`publishDiagnostics` at all. Inside a project (`cyrius check --with-deps`): `src/col.cyr` has no `include`, so the
check is redirected to `src/main.cyr`; `col.cyr` shows `src/inc.cyr`'s line-7 error at its own line 6 plus a line-0
`"…/src/col.cyr (compiler exit 1)"`, and its own line-2 error is never compiled.
**Placement:** 6.7.13 — repair 3 (roadmap.md § *6.7.13*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (reported in its tools findings; the sweep's re-verified
`docs/guides/editor-integration.md` documents the line-only spans and the `.cyr`-only coverage as gaps); re-verified
and filed by the 6.7.10 planning lane.
**Severity:** Medium — wrong diagnostics in the editor: an error in another file is pinned to an unrelated (or
nonexistent) line of the open file, every message starts with a stray number, and five of the six documented
extensions get no diagnostics or symbol index at all.
**Affects:** `cyrius-lsp` (shipped in every install as a release binary); the column since cycc's
`error:file:line:col:` format, the file and extension handling since the server's first diagnostics.

## Summary

`parse_and_send_diagnostics` was written for `error:<file>:<line>: <message>`. cycc now prints
`error:<file>:<line>:<col>: <message>` (`<source>` as the file for stdin). The parser skips everything up to the
first `:`, reads the line, and takes the rest — `14: undefined variable …` — as the message; the range is always
`character 0` to `100`. The file name it skips is the only thing that says WHICH file the error is in, so an error in
an included file is published on the open document at that line number. In a project the server runs
`cyrius check --with-deps <file>`, whose legacy module redirect compiles `src/main.cyr` instead whenever the file has
no `include ` directive (`cbt/commands.cyr:1176-1210`) — so the open file shows the entry's diagnostics and its own
are never produced. And `handle_did_open_or_save` returns early for any path not ending in `.cyr`, so the
`.tcyr` / `.bcyr` / `.fcyr` / `.scyr` / `.smcyr` files the documented `.lsp.json` routes to the server are neither
compiled nor indexed (the guide states this as a gap; the routing table still lists them).

## Reproduction

```sh
# bash; writes only under $W
cd /home/macro/Repos/cyrius
W=$(mktemp -d); mkdir -p "$W/h/.cyrius/bin" "$W/loose" "$W/proj/src"
build/cycc < programs/cyrius-lsp.cyr > "$W/cyrius-lsp" 2>/dev/null && chmod +x "$W/cyrius-lsp"
cp build/cycc "$W/h/.cyrius/bin/cycc"                    # the server looks in $HOME/.cyrius/bin
build/cycc < cbt/cyrius.cyr > "$W/h/.cyrius/bin/cyrius" 2>/dev/null && chmod +x "$W/h/.cyrius/bin/cyrius"
printf 'var a = 1;\nvar b = 2;\nvar c = 3;\nvar d = 4;\nvar e = 5;\nvar f = 6;\nvar g = undefined_name + 1;\n' > "$W/loose/inc.cyr"
printf 'include "inc.cyr"\nvar x = 1;\nsyscall(60, x);\n' > "$W/loose/main.cyr"     # 3 lines; the error is inc.cyr:7
printf 'var x = 1;\nvar y = nope + 2;\nsyscall(60, x);\n' > "$W/loose/col.cyr"        # error at line 2, column 14
printf 'var t = 1;\nvar u = nope2;\nsyscall(60, 0);\n' > "$W/loose/t.tcyr"
printf '[package]\nname = "lp"\nversion = "0.1.0"\n' > "$W/proj/cyrius.cyml"
cp "$W/loose/col.cyr" "$W/loose/inc.cyr" "$W/proj/src/"
printf 'include "src/inc.cyr"\nsyscall(60, 0);\n' > "$W/proj/src/main.cyr"
msg() { printf 'Content-Length: %d\r\n\r\n%s' "${#1}" "$1"; }
drive() {
  msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  for f in "$@"; do
    msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$f\",\"languageId\":\"cyrius\",\"version\":1,\"text\":\"\"}}}"
  done
  msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'; msg '{"jsonrpc":"2.0","method":"exit"}'
}
echo "== outside a project (raw cycc) =="
( cd "$W/loose" && drive "$W/loose/col.cyr" "$W/loose/main.cyr" "$W/loose/t.tcyr" | HOME="$W/h" timeout 30 "$W/cyrius-lsp" 2>/dev/null ) \
  | tr '\r' '\n' | grep -o '"uri":"[^"]*","diagnostics":.*' | sed -e "s|file://$W/||" -e 's/Content-Length: [0-9]*$//'
echo "== inside a project (cyrius check --with-deps) =="
( cd "$W/proj" && drive "$W/proj/src/col.cyr" | HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" timeout 30 "$W/cyrius-lsp" 2>/dev/null ) \
  | tr '\r' '\n' | grep -o '"uri":"[^"]*","diagnostics":.*' | sed -e "s|file://$W/||" -e 's/Content-Length: [0-9]*$//'
cd /; rm -rf "$W"
```

```
actual:
== outside a project (raw cycc) ==
"uri":"loose/col.cyr","diagnostics":[{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":100}},"severity":1,"source":"cyrius","message":"14: undefined variable 'nope' (missing include or enum?)"}]}}
"uri":"loose/main.cyr","diagnostics":[{"range":{"start":{"line":6,"character":0},"end":{"line":6,"character":100}},"severity":1,"source":"cyrius","message":"24: undefined variable 'undefined_name' (missing include or enum?)"}]}}
          (nothing for loose/t.tcyr)
== inside a project (cyrius check --with-deps) ==
"uri":"proj/src/col.cyr","diagnostics":[{"range":{"start":{"line":6,…},"end":{"line":6,"character":100}},…,"message":"24: undefined variable 'undefined_name' (missing include or enum?)"},{"range":{"start":{"line":0,…}},…,"message":"/tmp/tmp.…/proj/src/col.cyr (compiler exit 1)"}]}}
expected: col.cyr → line 1, character 13 (0-based), message "undefined variable 'nope' …"; main.cyr → no
          diagnostic on main.cyr's lines for inc.cyr's error (published on inc.cyr's URI, or attached to the
          `include` line); t.tcyr → its line-2 error; the project's col.cyr → its OWN line-2 error
```

## Root cause

- `programs/cyrius-lsp.cyr:1147` documents the old `error:filename:line: message` format;
  `parse_and_send_diagnostics` (`:1150`) skips the file name without reading it (`:1218-1219`), parses one number
  after it, and starts the message after the next `:` — so `<col>: ` stays in the message. The range is a constant
  `character 0` / `100` (`:1256-1260`).
- No per-diagnostic file comparison exists: every `error:` / `warning:` line of the child's stderr is published on the
  open document's URI (`:1253-1287`).
- `compile_and_capture` (`:1076`) → `_compile_via_wrapper` (`:1013`) runs `cyrius check --with-deps <file>` in a
  project; `cmd_check`'s module redirect (`cbt/commands.cyr:1176-1210`) swaps an include-free file for
  `src/main.cyr`.
- `handle_did_open_or_save` (`:1355`): `if (memeq(path + plen - 4, ".cyr", 4) != 1) { return 0; }` (`:1362-1365`) —
  no compile, no index (`lsp_index_file`, `:479`), not even a clearing `publishDiagnostics`.

## Proposed fix

In `programs/cyrius-lsp.cyr`:
1. Parse `error:` / `warning:` as `<file>:<line>[:<col>]: <message>`: keep the file, read the column when present,
   publish `character: col - 1` (to the end of the token or line), and strip it from the message.
2. Publish each diagnostic on the URI of the file it names (resolved against the project root, or the open file for
   `<source>`); a diagnostic in an included file is either published on that file's URI or reported on the
   `include` line that reached it — one choice, documented in `editor-integration.md`.
3. In a project, check the open file itself: run `cyrius check` with the file as the unit (the redirect exists for a
   CLI convenience the server does not want), or — if the redirect is kept — publish only the diagnostics whose file
   is the open file. Either way the open file's own errors must appear.
4. Accept every documented extension (`.cyr`, `.tcyr`, `.bcyr`, `.fcyr`, `.scyr`, `.smcyr`) in
   `handle_did_open_or_save` and the indexer.
Rows (a `tests/gates/toolchain/` LSP script driving the server over stdio, as above): the column parsed and stripped;
an included-file error not published on the includer's lines; a `.tcyr` gets its diagnostic; the project's
include-free module gets its own error. Mutation: revert each part → its row goes RED. `editor-integration.md`'s
"gaps" sentence goes when the gaps do.

## Consumer-side workaround

Run `cyrius check <file>` (or the build) in a terminal for exact file / line / column; treat the editor's
diagnostic line as a hint.
