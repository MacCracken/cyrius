#!/bin/sh
# Regression: cyrius-lsp cross-file go-to-definition + documentSymbol.
#
# Pinned at v5.7.39. Drives cyrius-lsp through a JSON-RPC session on
# stdin/stdout and verifies the new method handlers behave as
# documented:
#   - initialize advertises definitionProvider + documentSymbolProvider
#   - textDocument/didOpen triggers transitive include indexing
#   - textDocument/definition returns the correct Location for an
#     IDENT under the cursor in the opened file
#   - textDocument/documentSymbol returns SymbolInformation[] for the
#     opened file
#
# Requires `build/cyrius-lsp` (or PATH `cyrius-lsp`). Skips if absent.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LSP="$ROOT/build/cyrius-lsp"
if [ ! -x "$LSP" ]; then
    LSP="$(command -v cyrius-lsp 2>/dev/null)"
fi
if [ ! -x "$LSP" ]; then
    # v5.7.39: cyrius-lsp is a release binary now (added to
    # cyrius.cyml [release].bins). Fail loud rather than skip — same
    # principle as the v5.7.36 fmt/lint loud-FAIL fix; a fresh
    # checkout against an installed toolchain still has cyrius-lsp
    # via PATH fallback.
    echo "  FAIL: cyrius-lsp not in build/ and not on PATH"
    echo "  build via: cat programs/cyrius-lsp.cyr | build/cc5 > build/cyrius-lsp && chmod +x build/cyrius-lsp"
    echo "  or: cyriusly setup (rebuilds the full release toolchain)"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── Test fixture ──
# A small .cyr file with one fn declaration. Its name is `foo_bar`,
# the `fn ` keyword starts at column 0, the IDENT `foo_bar` starts
# at column 3 of line 0.
FIXTURE="$WORK/fixture.cyr"
cat > "$FIXTURE" <<'EOF'
fn foo_bar() {
    return 42;
}
EOF

# Helper: send an LSP-framed message. Reads JSON from stdin, writes
# `Content-Length: N\r\n\r\n<json>` to stdout. Uses wc to count the
# byte length (cyrius-lsp's reader expects the literal byte count
# after the header).
send_lsp() {
    msg="$1"
    bytes=$(printf '%s' "$msg" | wc -c)
    printf 'Content-Length: %d\r\n\r\n%s' "$bytes" "$msg"
}

# Build the request stream in one go so we can pipe it through the
# LSP server in a single subshell.
URI="file://$FIXTURE"
{
    # 1. initialize
    send_lsp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
    # 2. didOpen — triggers indexer on the fixture
    send_lsp "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$URI\",\"languageId\":\"cyrius\",\"version\":1,\"text\":\"\"}}}"
    # 3. textDocument/definition pointed inside the IDENT `foo_bar`
    #    at line 0, column 5 (mid-IDENT). Should resolve to the same
    #    location since the IDENT IS the declaration.
    send_lsp "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$URI\"},\"position\":{\"line\":0,\"character\":5}}}"
    # 4. textDocument/documentSymbol
    send_lsp "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"$URI\"}}}"
    # 5. shutdown
    send_lsp '{"jsonrpc":"2.0","id":4,"method":"shutdown"}'
} | "$LSP" > "$WORK/out" 2>"$WORK/err"

# ── Assertions ──
out="$WORK/out"

# Test 1: initialize response advertises definitionProvider
if ! grep -q '"definitionProvider":true' "$out"; then
    echo "  FAIL test1: initialize did not advertise definitionProvider"
    cat "$out" | head -20
    exit 1
fi
if ! grep -q '"documentSymbolProvider":true' "$out"; then
    echo "  FAIL test1b: initialize did not advertise documentSymbolProvider"
    cat "$out" | head -20
    exit 1
fi

# Test 2: definition response contains uri pointing at fixture
if ! grep -q "\"uri\":\"$URI\"" "$out"; then
    echo "  FAIL test2: definition response missing fixture URI"
    cat "$out"
    exit 1
fi

# Test 3: definition response has line:0, character:3 (the IDENT
# `foo_bar` starts after `fn ` on line 0, columns [3..10))
if ! grep -q '"line":0,"character":3' "$out"; then
    echo "  FAIL test3: definition response missing expected position (line 0, char 3)"
    cat "$out"
    exit 1
fi

# Test 4: documentSymbol response contains the fn name + LSP kind 12 (Function)
if ! grep -q '"name":"foo_bar"' "$out"; then
    echo "  FAIL test4: documentSymbol missing 'foo_bar' name"
    cat "$out"
    exit 1
fi
if ! grep -q '"kind":12' "$out"; then
    echo "  FAIL test4b: documentSymbol kind != 12 (Function)"
    cat "$out"
    exit 1
fi

# ── Test 5: cross-file include resolution ──
# A two-file fixture: includer.cyr `include`s included.cyr which
# defines a fn. didOpen on includer.cyr should index BOTH files;
# definition request from includer.cyr against the included symbol
# should resolve to included.cyr's location.
INC="$WORK/included.cyr"
USE="$WORK/includer.cyr"
cat > "$INC" <<'EOF'
fn lib_helper() {
    return 7;
}
EOF
cat > "$USE" <<EOF
include "$INC"
fn caller() {
    return lib_helper();
}
EOF
INC_URI="file://$INC"
USE_URI="file://$USE"

# Position of `lib_helper` call in USE: line 2, column 11 (after
# "    return ").
{
    send_lsp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
    send_lsp "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$USE_URI\",\"languageId\":\"cyrius\",\"version\":1,\"text\":\"\"}}}"
    send_lsp "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$USE_URI\"},\"position\":{\"line\":2,\"character\":11}}}"
    send_lsp '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'
} | "$LSP" > "$WORK/out2" 2>"$WORK/err2"

if ! grep -q "\"uri\":\"$INC_URI\"" "$WORK/out2"; then
    echo "  FAIL test5: cross-file definition didn't resolve to included.cyr"
    echo "  expected uri: $INC_URI"
    cat "$WORK/out2"
    exit 1
fi
if ! grep -q '"line":0,"character":3' "$WORK/out2"; then
    echo "  FAIL test5b: cross-file definition position wrong (expected line 0 char 3)"
    cat "$WORK/out2"
    exit 1
fi

# ── v5.9.10 — Test 6 + 7: new providers (references + semanticTokens) ──
# Single-file fixture with a fn decl + a use site so /references
# returns 2 locations and /semanticTokens emits a recognizable
# token stream.
NEW="$WORK/newproviders.cyr"
cat > "$NEW" <<'EOF'
fn foo_bar() {
    return 42;
}

fn caller() {
    return foo_bar();
}
EOF
NEW_URI="file://$NEW"

{
    send_lsp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
    send_lsp "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$NEW_URI\",\"languageId\":\"cyrius\",\"version\":1,\"text\":\"\"}}}"
    # /references — cursor in the IDENT `foo_bar` at line 0, col 5.
    send_lsp "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"$NEW_URI\"},\"position\":{\"line\":0,\"character\":5},\"context\":{\"includeDeclaration\":true}}}"
    # /semanticTokens/full — should return a `data` array with at least
    # the 7-token sequence the file produces (fn / foo_bar / return /
    # fn / caller / return / foo_bar).
    send_lsp "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/semanticTokens/full\",\"params\":{\"textDocument\":{\"uri\":\"$NEW_URI\"}}}"
    send_lsp '{"jsonrpc":"2.0","id":4,"method":"shutdown"}'
} | "$LSP" > "$WORK/out3" 2>"$WORK/err3"

# Test 6: initialize advertises both new providers + the
# semanticTokens legend.
if ! grep -q '"referencesProvider":true' "$WORK/out3"; then
    echo "  FAIL test6: initialize did not advertise referencesProvider"
    cat "$WORK/out3" | head -20
    exit 1
fi
if ! grep -q '"semanticTokensProvider":' "$WORK/out3"; then
    echo "  FAIL test6b: initialize did not advertise semanticTokensProvider"
    cat "$WORK/out3" | head -20
    exit 1
fi
if ! grep -q '"tokenTypes":\["function","variable","struct","enum","enumMember","keyword"\]' "$WORK/out3"; then
    echo "  FAIL test6c: semanticTokensProvider legend missing or in wrong shape"
    cat "$WORK/out3" | head -20
    exit 1
fi

# Test 7: /references returns 2 Locations (decl + use).
ref_count=$(grep -oE '"uri":"file://[^"]*newproviders\.cyr"' "$WORK/out3" | wc -l)
if [ "$ref_count" -lt 2 ]; then
    echo "  FAIL test7: /references returned $ref_count Locations (expected 2)"
    cat "$WORK/out3" | head -30
    exit 1
fi

# Test 8: /semanticTokens emits the first-token tuple of the
# fixture: "fn" at line 0 col 0 length 2, type 5 (keyword),
# modifier 0 → leading data is "0,0,2,5,0".
if ! grep -q '"data":\[0,0,2,5,0' "$WORK/out3"; then
    echo "  FAIL test8: /semanticTokens data did not start with the expected 'fn' keyword token tuple"
    cat "$WORK/out3" | head -30
    exit 1
fi

echo "  PASS: cyrius-lsp definitionProvider + documentSymbolProvider + referencesProvider + semanticTokensProvider/full + cross-file indexing (v5.7.39 + v5.9.10)"
exit 0
