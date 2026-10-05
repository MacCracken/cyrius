#!/bin/sh
# lsp_reads_whole_document.sh — 6.6.17. cyrius-lsp reads an open document sized by fstat, and
# refuses an absurd size by name.
#
# THE DEFECT: `lsp_read_file` (programs/cyrius-lsp.cyr) read through a fixed 1 MB buffer, silently,
# so definition / hover / references / semantic tokens found nothing past the cut — and two stdlib
# files (lib/mabda.cyr, lib/sigil.cyr) are over 1 MB. Measured on the 6.6.17 slot-open LSP: a
# definition request on a use at byte ~1.2 MB answered `"result":null`.
#
# ROWS (the LSP is driven over stdio JSON-RPC, in a throwaway HOME, with no cycc to find):
#   far_use     definition at a use past 1 MB answers the declaration on line 0.
#   over_limit  a 64 MiB + 1 B (sparse) document is not read: the log names the path and size,
#               the request answers null, and the server still answers the next request.
#   at_limit    a document of exactly 64 MiB is read: no refusal is logged.
# Old LSP: far_use and over_limit FAIL.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=lsp_reads_whole_document
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "SKIP: $G: cyrius-lsp is driven here on Linux only"; exit 77; }
command -v truncate > /dev/null 2>&1 || { echo "SKIP: $G: truncate (coreutils) is not installed"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $G: $*"; FAIL=1; }
ulimit -c 0 2>/dev/null

mkdir -p "$W/bin" "$W/home" "$W/cwd"
"$CC" < programs/cyrius-lsp.cyr > "$W/bin/cyrius-lsp" 2> "$W/lsp.err" && [ -s "$W/bin/cyrius-lsp" ] \
  || { echo "FAIL: $G: programs/cyrius-lsp.cyr does not build:"; tail -3 "$W/lsp.err" | sed 's/^/      /'; exit 1; }
chmod +x "$W/bin/cyrius-lsp"

msg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
lsp() {   # stdin = the framed requests; $1 = stderr file; stdout = responses, one per line
    ( cd "$W/cwd" && env -i HOME="$W/home" PATH=/usr/bin:/bin timeout 120 "$W/bin/cyrius-lsp" 2> "$1" ) | tr '\r' '\n'
}

# ── far_use ──────────────────────────────────────────────────────────────────────────────
D="$W/doc.cyr"
{ printf 'fn zz_far(): i64 { return 7; }\n'
  i=0; while [ $i -lt 12000 ]; do
      printf '# padding %05d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' $i
      i=$((i + 1)); done
  printf 'var q = zz_far();\n'; } > "$D"
SZ=$(wc -c < "$D" | tr -d ' '); LAST=$(( $(wc -l < "$D") - 1 ))
[ "$SZ" -gt 1048576 ] || { echo "FAIL: $G: the far_use document is only $SZ B"; exit 1; }
{ msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  msg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$D"'","languageId":"cyrius","version":1,"text":""}}}'
  msg '{"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$D"'"},"position":{"line":'"$LAST"',"character":9}}}'
  msg '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'; } | lsp "$W/far.err" > "$W/far.out"
if grep -q '"id":2,"result":{"uri":"file://'"$D"'","range":{"start":{"line":0,' "$W/far.out"; then
    echo "  ok: far_use — a definition request at byte ~$SZ answers line 0"
else
    fail "far_use — the definition at line $LAST of a $SZ-B document did not answer line 0: $(grep -o '"id":2[^}]*' "$W/far.out" | head -1)"
fi

# ── over_limit / at_limit ────────────────────────────────────────────────────────────────
hover() {   # $1 = document, $2 = stderr file, $3 = stdout file
    { msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
      msg '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://'"$1"'"},"position":{"line":0,"character":0}}}'
      msg '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'; } | lsp "$2" > "$3"
}
BIG="$W/big.cyr"; truncate -s 67108865 "$BIG"
hover "$BIG" "$W/big.err" "$W/big.out"
if grep -qF "not reading $BIG: 67108865 bytes" "$W/big.err" && grep -q '"id":2,"result":null' "$W/big.out" \
   && grep -q '"id":3,' "$W/big.out"; then
    echo "  ok: over_limit — a 64 MiB + 1 B document is refused by name, and the server goes on"
else
    fail "over_limit — log: $(tail -2 "$W/big.err" | tr '\n' ' ') / responses: $(grep -o '"id":[23][^}]*' "$W/big.out" | tr '\n' ' ')"
fi
EDGE="$W/edge.cyr"; truncate -s 67108864 "$EDGE"
hover "$EDGE" "$W/edge.err" "$W/edge.out"
if ! grep -q 'not reading' "$W/edge.err" && grep -q '"id":3,' "$W/edge.out"; then
    echo "  ok: at_limit — a document of exactly 64 MiB is read"
else
    fail "at_limit — a 64 MiB document: $(tail -2 "$W/edge.err" | tr '\n' ' ')"
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: $G"
exit 0
