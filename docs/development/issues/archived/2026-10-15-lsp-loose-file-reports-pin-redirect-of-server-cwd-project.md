# cyrius-lsp: a loose file now reports the pin-redirect error of the project the server's working directory sits in — RESOLVED

> ✅ **RESOLVED in v6.7.14** (TL-8, `69c72ca09`: the user's decision D47 = D54 (2026-10-16): "Remove it (check the loose file with the version redirect off)". A file with no cyrius.cyml at or above it runs `cyrius check <file>` with `CYRIUS_RESOLVED=1` (the CLI's version redirect off) and `CYRIUS_NO_WARN_PIN_DRIFT=1`, any inherited entry of either name dropped. The drift switch is needed because cycc's drift warning reads the same pin: with the redirect off alone, the loose file showed `cyrius.cyml pins 6.5.0 but cycc is 6.7.14 — toolchain drift` on line 1. The filed script now publishes `"diagnostics":[]` for the loose file; it published the pin error. `cyrius check <abs file>` from that directory still prints it, a project's own files keep their pin, and sibling includes resolve as 6.7.13 made them. Under an installed different pin, the loose file is now checked by the toolchain the server found, not the pinned one. Rows: `lsp_diagnostics_file_column.sh` R16 – R18 (R11 stays `[]`). The same decision closed item 7 of the 6.7.13 changes beyond the decisions' text. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 tools review of 67516853 (the fix for
issues/archived/2026-10-15-lsp-loose-file-include-resolves-against-server-cwd.md). Re-measured by the tools lane's fix step
with the lane's build/cyrius-lsp, build/cycc and build/cyrius (l6713-tools @ 815cd500), against a base server and CLI
built from b13d3598.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane, wave 1, unit T3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D47 (= D54 of the 6.7.13 list) — Remove it (check the loose file with the version redirect off).
**Severity:** Low — a wrong line-1 error in the editor for a file outside any project, and only when the editor
started the server inside a project that pins a cyrius version that is not installed. The diagnostic matches what
`cyrius check <abs file>` prints from that directory, which is the reference the 6.7.13 fix chose. A project's own
files already hit the same pin redirect under the LSP. So the user decides whether a loose file should follow the
working directory's pin (as `cyrius check` does) or be compiled without it.
**Affects:** cyrius-lsp's loose-file path (`_compile_via_wrapper_run` with `project_root` 0, programs/cyrius-lsp.cyr)
since 6.7.13 (67516853). It does not affect 6.7.12 or earlier, where the loose path ran cycc directly.

## Reproduction

```sh
# bash lsp_pin.sh <LSP> <CC> <CLI>
LSP=$1 CC=$2 CLI=$3
W=$(mktemp -d); mkdir -p "$W/h/.cyrius/bin" "$W/top/proj" "$W/top/loose"
cp "$CC" "$W/h/.cyrius/bin/cycc"; cp "$CLI" "$W/h/.cyrius/bin/cyrius"
printf '[package]\nname = "proj"\nversion = "0.1.0"\ncyrius = "6.5.0"\n' > "$W/top/proj/cyrius.cyml"
printf 'var x = 1;\n' > "$W/top/loose/main.cyr"
msg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
{ msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$W/top/loose/main.cyr\",\"text\":\"\"}}}"
  msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'; msg '{"jsonrpc":"2.0","method":"exit"}'; } \
  | (cd "$W/top/proj" && env -i HOME="$W/h" PATH=/usr/bin:/bin timeout 30 "$LSP" 2>/dev/null) \
  | tr '\r' '\n' | grep -o '"uri":"[^"]*","diagnostics":.*' | sed "s|file://$W/||; s|$W/|\$W/|g"
echo "== cyrius check <abs file> from the same working directory:"
(cd "$W/top/proj" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin "$W/h/.cyrius/bin/cyrius" check "$W/top/loose/main.cyr" 2>&1 | sed "s|$W/|\$W/|g")
rm -rf "$W"
```

Lane (l6713-tools, cyrius-lsp from 67516853 on):

```
"uri":"top/loose/main.cyr","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":10}},"severity":1,"source":"cyrius","message":"cyrius.cyml pins version 6.5.0 but cyrius binary is not installed at $W/h/.cyrius/versions/6.5.0/bin/cyrius"}]}}
== cyrius check <abs file> from the same working directory:
error: cyrius.cyml pins version 6.5.0 but cyrius binary is not installed at $W/h/.cyrius/versions/6.5.0/bin/cyrius
  run: cyrius install 6.5.0
```

Base (b13d3598) with the same script:

```
"uri":"top/loose/main.cyr","diagnostics":[]}}
== cyrius check <abs file> from the same working directory:
error: cyrius.cyml pins version 6.5.0 but cyrius binary is not installed at $W/h/.cyrius/versions/6.5.0/bin/cyrius
  run: cyrius install 6.5.0
```

`$W/top/loose/main.cyr` has no cyrius.cyml at or above it. Only the server's working directory (`$W/top/proj`) has one.

## Root cause

Since 67516853, a file with no project above it is compiled by `_compile_via_wrapper_run(filepath, 0, …)`: the server
runs `cyrius check <file>` with no chdir, so it runs in the server's own working directory. The CLI's version
redirect reads the cyrius.cyml in its working directory. When that file pins a version that is not installed, the CLI
stops before compiling, and the server publishes its error as a line-1 diagnostic on the loose file. `--no-redirect`
is only passed on the project route, and it only governs the src/main.cyr redirect anyway, not the version pin. The
6.7.12 loose path ran cycc directly, so no pin was read.

## Proposed fix (needs the user's call)

Either (a) keep this: it is what `cyrius check <abs file>` prints from that directory, which is the reference the
6.7.13 fix took. Or (b) run the loose-file `cyrius check` with the version redirect turned off, through whatever spelling
the CLI uses to skip its pin redirect, or by running it from the file's own directory with the file named relative
to it. (b) needs a row in lsp_diagnostics_file_column.sh: the repro above publishes `[]` for the loose file.
