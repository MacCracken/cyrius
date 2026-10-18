#!/bin/sh
# lsp_diagnostics_file_column.sh — 6.7.12. cyrius-lsp publishes each diagnostic at the column the
# compiler gives, on the URI of the file it names, for every cyrius extension, and checks a
# project's open file itself.
#
# THE DEFECT (issues/archived/2026-10-12-lsp-diagnostics-column-file-and-extensions.md, measured on the 6.7.11
# server): `parse_and_send_diagnostics` read `error:<file>:<line>:` only, skipping the file name
# unread — cycc prints `error:<file>:<line>:<col>: <msg>`, so the column stayed in the message
# (`14: undefined variable 'nope' …`) and the range was always characters 0-100; an error in an
# INCLUDED file was published on the open document at that line number; `handle_did_open_or_save`
# returned for anything not ending `.cyr`, so `.tcyr` / `.bcyr` / `.fcyr` / `.scyr` / `.smcyr` got
# nothing; and in a project `cyrius check --with-deps`'s module redirect compiled src/main.cyr for an
# include-free file, which then showed the entry's diagnostics (plus the CLI's `… (compiler exit 1)`
# verdict at line 0) and never its own.
#
# ROWS (the server driven over stdio JSON-RPC as in the filed repro, in a throwaway HOME whose
# .cyrius/bin holds this tree's cycc and CLI):
#   R1  col.cyr (error at 2:14): line 1, characters 13 to 17 (the line's end), message stripped
#   R2  main.cyr including inc.cyr (error at inc.cyr:7:24): main.cyr's list is EMPTY and inc.cyr's
#       own URI gets line 6, character 23
#   R3  t.tcyr, and a .bcyr / .fcyr / .scyr / .smcyr, each get their own diagnostic
#   R4  in a project, the include-free src/col.cyr gets its OWN line-2 error, not src/inc.cyr's,
#       and no `(compiler exit 1)` verdict beside it (`cyrius check --with-deps --no-redirect`)
#   R5  a recompile that no longer names a file clears it: main.cyr saved after inc.cyr is fixed
#       publishes an empty list on inc.cyr
#   R6  a toolchain older than 6.7.12 (a CLI that refuses --no-redirect) is checked again without
#       the flag: no `unknown option` diagnostic
#   R7  a failed compile whose only line is the CLI's verdict still shows it (line 0)
#   R8  a diagnostic naming a file that does not exist stays on the open file's line 0, its
#       location kept in the message
#   R9  `cyrius check --help` names --no-redirect
#   R10 the CLI half direct: `cyrius check --with-deps --no-redirect src/col.cyr` checks the file
#       itself; without the flag the redirect (`check via src/main.cyr`) is unchanged
#   R11 (6.7.13) the filed repro: a loose file in a subdirectory of the server's working directory
#       whose sibling include `cyrius check` resolves publishes an EMPTY list — through the CLI
#       (`cyrius check <file relative to the cwd>`) and with cycc alone (`#@incdir` + `#@srcline`
#       fed ahead of the file)
#   R12 the same routes: a genuine error in the sibling inc.cyr is published on inc.cyr's URI
#   R13 the same routes: the file's own error keeps its line (`#@srcline`), and the CLI's verdict
#       (it names the file as it was given, relative) is not shown beside it
#   R14 outside the working directory's subtree there is no marker — the same "cannot open" as
#       `cyrius check <absolute path>` from there (the CLI writes none for an absolute entry)
#   R15 the CLI half: `cyrius check ok/main.cyr` from that directory says ok
#   R16 (6.7.14, D47 / D54 — the user, 2026-10-16) the filed repro: the server started in a project
#       that pins an uninstalled cyrius (6.5.0); a file outside any project publishes an EMPTY list —
#       not the pin's redirect error, and not cycc's drift warning about that same pin (the loose
#       check runs with CYRIUS_RESOLVED=1 and CYRIUS_NO_WARN_PIN_DRIFT=1). R11 (cli) is TL-14's
#       sibling-include row under the same environment: still empty.
#   R17 the same, with CYRIUS_RESOLVED=0 and CYRIUS_NO_WARN_PIN_DRIFT=0 inherited by the server: empty
#   R18 a file of that pinned project still reports the pin (the project route is unchanged)
# `LSP_BIN=<binary>` / `CLI_BIN=<binary>` run the gate against another build (the mutations).
#
# PROVEN RED (run when written, each mutant via LSP_BIN / CLI_BIN):
#   the 6.7.11 server and CLI                         R1 R2 R3 R4 R5 R6 R8 R9 R10 FAIL (R7: it showed the verdict too)
#   the 6.7.11 CLI under this server                  R4 R9 R10 FAIL (R6 passes: the refusal falls back)
#   the column not parsed (the message keeps it)       R1 R2 R3 R4 FAIL
#   every diagnostic on the open document's URI        R2 R5 R6 FAIL
#   `.cyr` only                                        R3 FAIL
#   the server not passing --no-redirect               R4 FAIL
#   no stale clear                                     R5 FAIL
#   no old-CLI fallback                                R6 FAIL
#   the verdict always shown / never shown             R4 / R7 FAIL
#   an unresolved name published on its own URI        R8 FAIL
# 6.7.13 (measured):
#   the 6.7.12 server                                 R11 R12 R13 FAIL (both routes; R14 R15 pass)
#   the file not made relative to the cwd (no _lsp_rel_to) R11 R12 R13 FAIL (both routes)
#   the cycc route without the #@incdir feed           R11 R12 R13 FAIL (cycc)
#   the loose verdict not recognised (_lsp_last_unit)  R2 R12 R13 FAIL (cli: the verdict on main.cyr)
#   (the feed without #@srcline turns nothing RED: cycc already discounts the `#@incdir` line,
#   6.5.7 — the marker is there because the CLI's unit carries it)
# 6.7.14 (measured):
#   the 6.7.14-open server                             R16 R17 FAIL (the pin's error at line 0)
#   CYRIUS_RESOLVED=1 alone                            R16 R17 FAIL (the drift warning at line 0)
#   inherited entries kept (ours appended after them)  R17 FAIL
#   the loose environment on the project route too     R18 FAIL
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=lsp_diagnostics_file_column
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "SKIP: $G: cyrius-lsp is driven here on Linux only"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
ok() { echo "  ok: $*"; }
fail() { echo "  FAIL: $*"; FAIL=1; }

mkdir -p "$W/h/.cyrius/bin" "$W/loose" "$W/proj/src" "$W/old/.cyrius/bin" "$W/stub/.cyrius/bin"
if [ -n "${LSP_BIN:-}" ]; then cp "$LSP_BIN" "$W/cyrius-lsp"
else "$CC" < programs/cyrius-lsp.cyr > "$W/cyrius-lsp" 2> "$W/lsp.err" && [ -s "$W/cyrius-lsp" ] \
  || { echo "FAIL: $G: programs/cyrius-lsp.cyr does not build:"; tail -3 "$W/lsp.err"; exit 1; }; fi
if [ -n "${CLI_BIN:-}" ]; then cp "$CLI_BIN" "$W/h/.cyrius/bin/cyrius"
else "$CC" < cbt/cyrius.cyr > "$W/h/.cyrius/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/h/.cyrius/bin/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err"; exit 1; }; fi
chmod +x "$W/cyrius-lsp" "$W/h/.cyrius/bin/cyrius"
cp "$CC" "$W/h/.cyrius/bin/cycc"

# The filed repro's files, plus one per other extension.
printf 'var a = 1;\nvar b = 2;\nvar c = 3;\nvar d = 4;\nvar e = 5;\nvar f = 6;\nvar g = undefined_name + 1;\n' > "$W/loose/inc.cyr"
printf 'include "inc.cyr"\nvar x = 1;\nsyscall(60, x);\n' > "$W/loose/main.cyr"
printf 'var x = 1;\nvar y = nope + 2;\nsyscall(60, x);\n' > "$W/loose/col.cyr"
printf 'var t = 1;\nvar u = nope2;\nsyscall(60, 0);\n' > "$W/loose/t.tcyr"
for x in bcyr fcyr scyr smcyr; do printf 'var t = 1;\nvar u = nope_%s;\n' "$x" > "$W/loose/e.$x"; done
printf '[package]\nname = "lp"\nversion = "0.1.0"\n' > "$W/proj/cyrius.cyml"
cp "$W/loose/col.cyr" "$W/loose/inc.cyr" "$W/proj/src/"
printf 'include "src/inc.cyr"\nsyscall(60, 0);\n' > "$W/proj/src/main.cyr"

msg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
open_msg() { msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/did$1\",\"params\":{\"textDocument\":{\"uri\":\"file://$2\",\"languageId\":\"cyrius\",\"version\":1,\"text\":\"\"}}}"; }
start() { msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'; }
stop() { msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'; msg '{"jsonrpc":"2.0","method":"exit"}'; }
# serve <cwd> <home> — the framed requests on stdin; the publishDiagnostics params, one per line.
# (Each feeder ignores SIGPIPE and ends `true`: the server may exit on `shutdown` before the
# `exit` notification is written, which is a SIGPIPE the pipeline's status must not read as a
# failure under `bash -eo pipefail`.)
# $SERVE_ENV: extra NAME=value words for the server's environment (R17).
serve() {
    # shellcheck disable=SC2086
    ( cd "$1" && env -i HOME="$2" CYRIUS_HOME="$2/.cyrius" PATH=/usr/bin:/bin ${SERVE_ENV:-} timeout 60 "$W/cyrius-lsp" 2>> "$W/lsp.log" ) \
      | tr '\r' '\n' | grep -o '"uri":"[^"]*","diagnostics":.*' | sed -e "s|file://$W/||" -e 's/Content-Length: [0-9]*$//'
}
# the publish lines for <relative path>
pub() { grep "^\"uri\":\"$2\"," "$1"; }

# ── R1 / R2 / R3: outside a project (raw cycc) ──────────────────────────────────────────────
{ trap '' PIPE; start; open_msg Open "$W/loose/col.cyr"; open_msg Open "$W/loose/main.cyr"; open_msg Open "$W/loose/t.tcyr"
  for x in bcyr fcyr scyr smcyr; do open_msg Open "$W/loose/e.$x"; done; stop; true; } | serve "$W/loose" "$W/h" > "$W/r1"
P=$(pub "$W/r1" loose/col.cyr)
if printf '%s' "$P" | grep -qF '"start":{"line":1,"character":13},"end":{"line":1,"character":17}' \
   && printf '%s' "$P" | grep -qF '"message":"undefined variable '"'"'nope'"'"' (missing include or enum?)"'; then
    ok "R1 col.cyr: line 1, characters 13-17, the column stripped from the message"
else fail "R1 col.cyr: $P"; fi
PM=$(pub "$W/r1" loose/main.cyr); PI=$(pub "$W/r1" loose/inc.cyr)
if [ "$PM" = '"uri":"loose/main.cyr","diagnostics":[]}}' ] \
   && printf '%s' "$PI" | grep -qF '"start":{"line":6,"character":23}'; then
    ok "R2 main.cyr's list is empty; inc.cyr's error is on inc.cyr's URI, line 6"
else fail "R2 main.cyr: ${PM:-none} / inc.cyr: ${PI:-none}"; fi
n3=0
pub "$W/r1" loose/t.tcyr | grep -qF '"start":{"line":1,"character":13}' && n3=1
for x in bcyr fcyr scyr smcyr; do
    pub "$W/r1" "loose/e.$x" | grep -F '"start":{"line":1,' | grep -qF "undefined variable 'nope_$x'" && n3=$((n3 + 1))
done
if [ "$n3" = 5 ]; then ok "R3 .tcyr, .bcyr, .fcyr, .scyr and .smcyr each get their line-2 error"
else fail "R3 only $n3 of 5 extensions got their diagnostic: $(grep -c . "$W/r1") publishes"; fi

# ── R4: inside a project (cyrius check --with-deps --no-redirect) ──────────────────────────────
{ trap '' PIPE; start; open_msg Open "$W/proj/src/col.cyr"; stop; true; } | serve "$W/proj" "$W/h" > "$W/r4"
P=$(pub "$W/r4" proj/src/col.cyr)
if printf '%s' "$P" | grep -qF '"start":{"line":1,"character":13}' \
   && ! printf '%s' "$P" | grep -q 'undefined_name\|compiler exit' && ! pub "$W/r4" proj/src/inc.cyr | grep -q .; then
    ok "R4 the project's include-free src/col.cyr gets its own line-2 error, nothing of src/inc.cyr's, no verdict"
else fail "R4 src/col.cyr: $P / src/inc.cyr: $(pub "$W/r4" proj/src/inc.cyr)"; fi

# ── R5: a stale file is cleared ─────────────────────────────────────────────────────────────
mkdir -p "$W/stale"; cp "$W/loose/main.cyr" "$W/loose/inc.cyr" "$W/stale/"
: > "$W/lsp.log"
{ trap '' PIPE; start; open_msg Open "$W/stale/main.cyr"
  # inc.cyr is fixed on disk once the first compile has been published (the server logs it), then
  # main.cyr is saved again
  w=0; while ! grep -q 'sent diagnostics' "$W/lsp.log" && [ "$w" -lt 300 ]; do sleep 0.1; w=$((w + 1)); done
  printf 'var a = 1;\n' > "$W/stale/inc.cyr"; open_msg Save "$W/stale/main.cyr"; stop; true; } | serve "$W/stale" "$W/h" > "$W/r5"
if pub "$W/r5" stale/inc.cyr | head -1 | grep -qF '"line":6' \
   && [ "$(pub "$W/r5" stale/inc.cyr | sed -n 2p)" = '"uri":"stale/inc.cyr","diagnostics":[]}}' ]; then
    ok "R5 main.cyr saved after inc.cyr was fixed publishes an empty list on inc.cyr"
else fail "R5 inc.cyr's publishes: $(pub "$W/r5" stale/inc.cyr | tr '\n' ' ')"; fi

# ── R6: a CLI that refuses --no-redirect ────────────────────────────────────────────────────
cp "$CC" "$W/old/.cyrius/bin/cycc"
cat > "$W/old/.cyrius/bin/cyrius" <<EOF
#!/bin/sh
for a in "\$@"; do [ "\$a" = --no-redirect ] && { echo "error: cyrius check: unknown option '--no-redirect'" >&2; exit 1; }; done
exec "$W/h/.cyrius/bin/cyrius" "\$@"
EOF
chmod +x "$W/old/.cyrius/bin/cyrius"
{ trap '' PIPE; start; open_msg Open "$W/proj/src/col.cyr"; stop; true; } | serve "$W/proj" "$W/old" > "$W/r6"
P=$(pub "$W/r6" proj/src/col.cyr)
if [ -n "$P" ] && ! printf '%s' "$P" | grep -q 'unknown option' && pub "$W/r6" proj/src/inc.cyr | grep -qF '"line":6'; then
    ok "R6 a toolchain without --no-redirect is checked again without it (the redirect's diagnostics, no refusal)"
else fail "R6 src/col.cyr: ${P:-none} / src/inc.cyr: $(pub "$W/r6" proj/src/inc.cyr)"; fi

# ── R7 / R8: stand-in compilers ─────────────────────────────────────────────────────────────
cp "$W/h/.cyrius/bin/cyrius" "$W/stub/.cyrius/bin/cyrius"
printf '#!/bin/sh\ncat > /dev/null\nexit 1\n' > "$W/stub/.cyrius/bin/cycc"; chmod +x "$W/stub/.cyrius/bin/cycc"
{ trap '' PIPE; start; open_msg Open "$W/proj/src/col.cyr"; stop; true; } | serve "$W/proj" "$W/stub" > "$W/r7"
P=$(pub "$W/r7" proj/src/col.cyr)
if printf '%s' "$P" | grep -qF '"start":{"line":0,' && printf '%s' "$P" | grep -qF 'col.cyr (compiler exit 1)'; then
    ok "R7 a failed compile with no diagnostic of its own shows the CLI's verdict on line 0"
else fail "R7 src/col.cyr: ${P:-none}"; fi
printf '#!/bin/sh\ncat > /dev/null\necho "error:nowhere_at_all.cyr:3:4: boom" >&2\nexit 1\n' > "$W/stub/.cyrius/bin/cycc"
{ trap '' PIPE; start; open_msg Open "$W/loose/col.cyr"; stop; true; } | serve "$W/loose" "$W/stub" > "$W/r8"
P=$(pub "$W/r8" loose/col.cyr)
if printf '%s' "$P" | grep -qF '"start":{"line":0,"character":0}' && printf '%s' "$P" | grep -qF '"message":"nowhere_at_all.cyr:3:4: boom"' \
   && ! grep -q nowhere_at_all.cyr\",\"diagnostics "$W/r8"; then
    ok "R8 a diagnostic naming no file stays on the open file's line 0 with its location"
else fail "R8 col.cyr: ${P:-none} / all: $(tr '\n' ' ' < "$W/r8")"; fi

# ── R9: the flag is documented ──────────────────────────────────────────────────────────────
if "$W/h/.cyrius/bin/cyrius" check --help 2>&1 | grep -q -- '--no-redirect'; then
    ok "R9 cyrius check --help names --no-redirect"
else fail "R9 cyrius check --help does not name --no-redirect"; fi

# ── R10: the CLI half, direct ───────────────────────────────────────────────────────────────
( cd "$W/proj" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin "$W/h/.cyrius/bin/cyrius" check --with-deps --no-redirect src/col.cyr > "$W/r10a" 2>&1 ) || true   # the check fails (rc 1): the file has an error
( cd "$W/proj" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin "$W/h/.cyrius/bin/cyrius" check --with-deps src/col.cyr > "$W/r10b" 2>&1 ) || true   # the check fails (rc 1): the file has an error
if grep -q "^error:<source>:2:14: undefined variable 'nope'" "$W/r10a" && ! grep -q 'check via\|undefined_name' "$W/r10a" \
   && grep -q 'check via src/main.cyr' "$W/r10b"; then
    ok "R10 cyrius check --with-deps --no-redirect checks src/col.cyr itself; without the flag the redirect stays"
else fail "R10 with the flag: $(tr '\n' ' ' < "$W/r10a") / without: $(head -1 "$W/r10b")"; fi

# ── R11-R15 (6.7.13): a loose file in a subdirectory of the server's working directory ─────────
# issues/archived/2026-10-15-lsp-loose-file-include-resolves-against-server-cwd.md. cycc tries an include
# against its working directory and then the entry's directory — the latter only through the
# `#@incdir` line the CLI writes. The server ran cycc on the file itself from its own working
# directory, so `include "inc.cyr"` beside a loose file was "cannot open" unless the editor started
# the server in that directory. Now it compiles what `cyrius check <file>` compiles from there:
# the CLI when found, else cycc with `#@incdir <dir>` + `#@srcline` ahead of the file.
mkdir -p "$W/top/ok" "$W/top/bad" "$W/top/own" "$W/other" "$W/cc/.cyrius/bin"
cp "$CC" "$W/cc/.cyrius/bin/cycc"   # a home with cycc alone: the server's own #@incdir route
printf 'fn helper(): i64 { return 0; }\n' > "$W/top/ok/inc.cyr"
printf 'include "inc.cyr"\nvar x = helper();\n' > "$W/top/ok/main.cyr"
printf 'fn helper2(): i64 { return 0; }\nvar bad = undefined_two + 1;\n' > "$W/top/bad/inc.cyr"
printf 'include "inc.cyr"\nvar x = helper2();\n' > "$W/top/bad/main.cyr"
cp "$W/top/ok/inc.cyr" "$W/top/own/inc.cyr"
printf 'include "inc.cyr"\nvar y = nope3 + helper();\n' > "$W/top/own/main.cyr"
for route in cli cycc; do
    hm="$W/h"; [ "$route" = cycc ] && hm="$W/cc"
    { trap '' PIPE; start; open_msg Open "$W/top/ok/main.cyr"; open_msg Open "$W/top/bad/main.cyr"; open_msg Open "$W/top/own/main.cyr"
      stop; true; } 2> /dev/null | serve "$W/top" "$hm" > "$W/r11$route"
    P=$(pub "$W/r11$route" top/ok/main.cyr)
    if [ "$P" = '"uri":"top/ok/main.cyr","diagnostics":[]}}' ]; then
        ok "R11 ($route) the filed repro: top/ok/main.cyr's sibling include resolves — an empty list"
    else fail "R11 ($route) top/ok/main.cyr: ${P:-none}"; fi
    PM=$(pub "$W/r11$route" top/bad/main.cyr); PI=$(pub "$W/r11$route" top/bad/inc.cyr)
    if [ "$PM" = '"uri":"top/bad/main.cyr","diagnostics":[]}}' ] && printf '%s' "$PI" | grep -qF '"start":{"line":1,' \
       && printf '%s' "$PI" | grep -qF "undefined variable 'undefined_two'"; then
        ok "R12 ($route) a genuine error in the sibling inc.cyr is published on inc.cyr's URI, line 1; main.cyr's list is empty"
    else fail "R12 ($route) main.cyr: ${PM:-none} / inc.cyr: ${PI:-none}"; fi
    P=$(pub "$W/r11$route" top/own/main.cyr)
    if printf '%s' "$P" | grep -qF '"start":{"line":1,' && printf '%s' "$P" | grep -qF "undefined variable 'nope3'" \
       && ! printf '%s' "$P" | grep -q 'compiler exit\|cannot open'; then
        ok "R13 ($route) the file's own error keeps its own line (1): #@srcline, no verdict beside it"
    else fail "R13 ($route) top/own/main.cyr: ${P:-none}"; fi
done
# R14: a file outside the working directory's subtree gets no marker — as `cyrius check` writes
# none for it (cycc refuses an absolute #@incdir): the include is "cannot open" from both
{ trap '' PIPE; start; open_msg Open "$W/top/ok/main.cyr"; stop; true; } 2> /dev/null | serve "$W/other" "$W/h" > "$W/r14"
P=$(pub "$W/r14" top/ok/main.cyr)
( cd "$W/other" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin "$W/h/.cyrius/bin/cyrius" check "$W/top/ok/main.cyr" > "$W/r14c" 2>&1 ) || true
if printf '%s' "$P" | grep -qF 'cannot open include file: inc.cyr' && grep -q 'cannot open include file: inc.cyr' "$W/r14c"; then
    ok "R14 outside the working directory's subtree: no marker, the same 'cannot open' as cyrius check from there"
else fail "R14 top/ok/main.cyr from another directory: ${P:-none} / cyrius check: $(head -1 "$W/r14c")"; fi
# R15: the CLI half the server relies on — `cyrius check ok/main.cyr` from $W/top
if ( cd "$W/top" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin "$W/h/.cyrius/bin/cyrius" check ok/main.cyr > "$W/r15" 2>&1 ) \
   && grep -q '^ok: ok/main.cyr' "$W/r15"; then
    ok "R15 cyrius check ok/main.cyr from the same directory: ok"
else fail "R15 cyrius check ok/main.cyr: $(head -2 "$W/r15" | tr '\n' ' ')"; fi

# ── R16-R18 (6.7.14): the server's working directory pins an uninstalled cyrius ──────────────
# issues/archived/2026-10-15-lsp-loose-file-reports-pin-redirect-of-server-cwd-project.md (D47 / D54, the
# user 2026-10-16: removed). The pin belongs to the project that pins it; a file with no cyrius.cyml
# at or above it is in no project, so its check reads no pin of the server's working directory.
mkdir -p "$W/pin/proj/src" "$W/pin/loose"
printf '[package]\nname = "proj"\nversion = "0.1.0"\ncyrius = "6.5.0"\n' > "$W/pin/proj/cyrius.cyml"
printf 'var x = 1;\n' > "$W/pin/loose/main.cyr"
printf 'var x = 1;\n' > "$W/pin/proj/src/x.cyr"
{ trap '' PIPE; start; open_msg Open "$W/pin/loose/main.cyr"; stop; true; } 2> /dev/null | serve "$W/pin/proj" "$W/h" > "$W/r16"
P=$(pub "$W/r16" pin/loose/main.cyr)
if [ "$P" = '"uri":"pin/loose/main.cyr","diagnostics":[]}}' ]; then
    ok "R16 the filed repro: a loose file, the server in a project pinning an uninstalled 6.5.0 — an empty list"
else fail "R16 pin/loose/main.cyr: ${P:-none}"; fi
{ trap '' PIPE; start; open_msg Open "$W/pin/loose/main.cyr"; stop; true; } 2> /dev/null \
  | SERVE_ENV="CYRIUS_RESOLVED=0 CYRIUS_NO_WARN_PIN_DRIFT=0" serve "$W/pin/proj" "$W/h" > "$W/r17"
P=$(pub "$W/r17" pin/loose/main.cyr)
if [ "$P" = '"uri":"pin/loose/main.cyr","diagnostics":[]}}' ]; then
    ok "R17 the same with CYRIUS_RESOLVED=0 and CYRIUS_NO_WARN_PIN_DRIFT=0 inherited: an empty list"
else fail "R17 pin/loose/main.cyr: ${P:-none}"; fi
{ trap '' PIPE; start; open_msg Open "$W/pin/proj/src/x.cyr"; stop; true; } 2> /dev/null | serve "$W/pin/proj" "$W/h" > "$W/r18"
P=$(pub "$W/r18" pin/proj/src/x.cyr)
if printf '%s' "$P" | grep -qF 'cyrius.cyml pins version 6.5.0 but cyrius binary is not installed'; then
    ok "R18 a file of that pinned project still reports the pin (the project route keeps its redirect)"
else fail "R18 pin/proj/src/x.cyr: ${P:-none}"; fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G"; exit 1; }
echo "PASS: $G"
exit 0
