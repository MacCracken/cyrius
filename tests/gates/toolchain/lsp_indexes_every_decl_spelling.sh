#!/bin/sh
# Gate: cyrius-lsp indexes every top-level declaration spelling the compiler accepts, and
# nothing that is only in a comment, a string or a fn body (6.6.10, bite 15).
#
# THE DEFECT. programs/cyrius-lsp.cyr kept its own declaration reader — the sixth in the tree
# — and it matched `fn `, `var `, `enum ` and `struct ` at COLUMN 0 only. No `pub`/`public`,
# no attribute (`#inline fn`), no indentation, no `fn<TAB>`, and `fn NAME` only when `(`
# followed the name at once, so no generic `fn f<T>(`. Go-to-definition, documentSymbol and
# hover missed every `pub fn` — lib/yukti.cyr alone has 322. And it read comments and
# strings as code. It also read each file through a fixed 1 MB buffer, so everything past
# the first MiB of lib/mabda.cyr (1.37 MB) and lib/sigil.cyr (1.26 MB) was never indexed.
#
# THE FIX. The LSP includes cbt/srcscan.cyr and indexes through `_src_decls`, the reader
# `cyrius coverage` and `cyrius distlib` use, over a blanked copy of the file, read whole.
#
# AXES
#   1  documentSymbol lists every spelling: pub fn, public fn, #inline fn, an indented fn,
#      fn<TAB>, pub #inline fn, a generic fn, pub var, secret var, both names of a top-level
#      destructure, an enum and its members, a struct — and a plain fn/var (control)
#   2  …and NOT a fn in a comment, a fn in a multi-line string, or a fn-local var
#   3  go-to-definition from another file resolves a `pub fn` across the include, to its line
#   4  a declaration past the first MiB of an included file is indexed (whole-file read)
#   5  (6.6.12) the symbol index has no silent cap: the LAST of 6000 long-named fns in one
#      include (past the old 4096-row, 256 KB-names and 32 KB-paths caps), a fn in the 300th
#      included file (past the old 256-file cap), and — a real row — sigil's last fn,
#      sv_verify_boot_chain, through `include "lib/sigil.cyr"`, all resolve
#
# PROVEN RED (run by hand when written, LSP_BIN=<binary> runs the gate against another build):
#   the 6.6.9 cyrius-lsp (programs/cyrius-lsp.cyr at 6d12c1e6)   15 of 25 checks FAIL —
#       every non-column-0 spelling (axis 1), sp_in_string (axis 2), axes 3 and 4
#   this tree with `_src_blank_noncode(cb, total)` removed      axis 2 FAIL (sp_in_string)
#   the 6.6.11 cyrius-lsp (programs/cyrius-lsp.cyr at 2bc29059)  axis 5: all three rows FAIL
#   6.6.12 with `_lsp_grow` returning -1 whenever it must grow    axis 5: all three rows FAIL
#   6.6.12 with `_lsp_grow_rows` never growing (4096-row cap)     axis 5: the 6000-fn row FAILS
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=lsp_indexes_every_decl_spelling
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $NAME — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# Built from THIS tree (from the repo root: the LSP includes cbt/srcscan.cyr). A compile that
# fails or yields a tiny file stops the gate — cycc on empty stdin exits 0.
LSP=${LSP_BIN:-"$T/cyrius-lsp"}
if [ -z "${LSP_BIN:-}" ]; then
    ( cd "$ROOT" && "$CC" < programs/cyrius-lsp.cyr > "$LSP" 2> "$T/build.err" ) || {
        echo "FAIL: $NAME — could not build programs/cyrius-lsp.cyr"; sed -n '1,5p' "$T/build.err"; exit 1; }
    [ "$(wc -c < "$LSP")" -gt 20000 ] || { echo "FAIL: $NAME — cyrius-lsp built to $(wc -c < "$LSP") bytes"; exit 1; }
    chmod +x "$LSP"
fi

frame() {   # $1 JSON body → one LSP message on stdout
    printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c | tr -d ' ')" "$1"
}
session() {   # $@ JSON bodies → the LSP's whole stdout in $T/out
    : > "$T/in"
    for b in "$@"; do frame "$b" >> "$T/in"; done
    # No `cyrius` on the child's PATH: didOpen's diagnostics compile is not what this gate
    # tests, and a missing wrapper only means an empty diagnostics list.
    ( cd "$T" && PATH=/usr/bin:/bin HOME="$T/nohome" timeout 30 "$LSP" < "$T/in" > "$T/out" 2> "$T/err" ) || :
}
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
DOWN='{"jsonrpc":"2.0","id":99,"method":"shutdown"}'
open_doc() { echo '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$1"'","languageId":"cyrius","version":1,"text":""}}}'; }
has() { if grep -qF -- "$1" "$T/out"; then echo yes; else echo no; fi; }

# ── the fixture: every spelling, plus the three things that are NOT declarations ─────────
F="$T/spell.cyr"
printf '%s\n' \
  'pub fn sp_pub(): i64 { return 1; }' \
  'public fn sp_public(): i64 { return 1; }' \
  '#inline fn sp_attr(): i64 { return 1; }' \
  '    fn sp_indent(): i64 { return 1; }' \
  'pub #inline fn sp_pubattr(): i64 { return 1; }' \
  'fn sp_generic<T>(x: T): i64 { return 1; }' \
  'fn sp_two(): i64 { return 2; }' \
  'fn sp_plain(): i64 { return 3; }' \
  'var sp_plainvar = 0;' \
  'pub var sp_pubvar = 1;' \
  'secret var sp_secret = 2;' \
  'var sp_q, sp_r = divmod_like(7);' \
  'enum SpColor { SP_RED; SP_GREEN = 5; }' \
  'struct SpPt { x; y; }' \
  '# fn sp_comment(): i64 { return 0; }' \
  'var sp_str = "' \
  'fn sp_in_string(): i64 {' \
  '";' \
  'fn sp_outer(): i64 {' \
  '    var sp_local = 1;' \
  '    return sp_local;' \
  '}' > "$F"
printf 'fn\tsp_tab(): i64 { return 1; }\n' >> "$F"
session "$INIT" "$(open_doc "$F")" \
  '{"jsonrpc":"2.0","id":2,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://'"$F"'"}}}' "$DOWN"
check "premise: the LSP answered documentSymbol" yes "$(has '"id":2')"
for n in sp_pub sp_public sp_attr sp_indent sp_tab sp_pubattr sp_generic sp_pubvar sp_secret sp_q sp_r SpColor SP_RED SP_GREEN SpPt; do
    check "1 documentSymbol lists $n" yes "$(has "\"name\":\"$n\"")"
done
check "1 control: a plain fn and var are listed" "yes yes" "$(has '"name":"sp_plain"') $(has '"name":"sp_plainvar"')"
for n in sp_comment sp_in_string sp_local; do
    check "2 documentSymbol does NOT list $n" no "$(has "\"name\":\"$n\"")"
done

# ── 3: go-to-definition of a `pub fn` from another file, across the include ─────────────
U="$T/user.cyr"
printf 'include "%s"\nfn user(): i64 {\n    return sp_pub();\n}\n' "$F" > "$U"
session "$INIT" "$(open_doc "$U")" \
  '{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$U"'"},"position":{"line":2,"character":12}}}' "$DOWN"
check "3 definition of sp_pub() resolves to the fixture" yes "$(has "\"uri\":\"file://$F\"")"
check "   …at its line and column (0, 7)" yes "$(has '"line":0,"character":7')"
session "$INIT" "$(open_doc "$U")" \
  '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://'"$U"'"},"position":{"line":2,"character":12}}}' "$DOWN"
check "   …and hover names it as a fn" yes "$(has '**fn** `sp_pub`')"

# ── 4: a declaration past the first MiB of an included file ──────────────────────────────
B="$T/big.cyr"
{ echo 'fn big_head(): i64 { return 1; }'
  awk 'BEGIN { for (i = 0; i < 16000; i++) print "# filler to push the next declaration past one mebibyte ........." }'
  echo 'pub fn big_tail(): i64 { return 2; }'; } > "$B"
check "4 premise: the file is larger than 1 MiB" yes "$([ "$(wc -c < "$B")" -gt 1048576 ] && echo yes || echo no)"
V="$T/vuser.cyr"
printf 'include "%s"\nfn v(): i64 {\n    return big_tail();\n}\n' "$B" > "$V"
session "$INIT" "$(open_doc "$V")" \
  '{"jsonrpc":"2.0","id":5,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$V"'"},"position":{"line":2,"character":12}}}' "$DOWN"
check "4 definition of big_tail() (past 1 MiB) resolves" yes "$(has "\"uri\":\"file://$B\"")"

# ── 5: no silent cap on the symbol index ─────────────────────────────────────────────────
M="$T/many_decls_with_a_deliberately_long_directory_name/many.cyr"
mkdir -p "$(dirname "$M")"
awk 'BEGIN { for (i = 0; i < 6000; i++)
    printf "fn many_decls_a_fairly_long_function_name_to_fill_the_table_%05d(): i64 { return %d; }\n", i, i }' > "$M"
W="$T/muser.cyr"
printf 'include "%s"\nfn w(): i64 {\n    return many_decls_a_fairly_long_function_name_to_fill_the_table_05999();\n}\n' "$M" > "$W"
session "$INIT" "$(open_doc "$W")" \
  '{"jsonrpc":"2.0","id":6,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$W"'"},"position":{"line":2,"character":12}}}' "$DOWN"
check "5 definition of the 6000th fn of one include resolves" yes "$(has "\"uri\":\"file://$M\"")"
check "   …at its line (5999)" yes "$(has '"line":5999,"character":3')"

D="$T/incs"
mkdir -p "$D"
i=0
while [ "$i" -lt 300 ]; do
    printf 'fn inc_file_fn_%03d(): i64 { return %d; }\n' "$i" "$i" > "$D/f$i.cyr"
    i=$((i + 1))
done
X="$T/xuser.cyr"
{ i=0; while [ "$i" -lt 300 ]; do printf 'include "%s/f%d.cyr"\n' "$D" "$i"; i=$((i + 1)); done
  printf 'fn x(): i64 {\n    return inc_file_fn_299();\n}\n'; } > "$X"
session "$INIT" "$(open_doc "$X")" \
  '{"jsonrpc":"2.0","id":7,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$X"'"},"position":{"line":301,"character":12}}}' "$DOWN"
check "5 definition of a fn in the 300th included file resolves" yes "$(has "\"uri\":\"file://$D/f299.cyr\"")"

SG="$ROOT/lib/sigil.cyr"
if [ -f "$SG" ]; then
    SGL=$(grep -n '^fn sv_verify_boot_chain(' "$SG" | head -1 | cut -d: -f1)
    check "5 premise: lib/sigil.cyr declares sv_verify_boot_chain" yes "$([ -n "$SGL" ] && echo yes || echo no)"
    Y="$T/suser.cyr"
    printf 'include "%s"\nfn y(): i64 {\n    return sv_verify_boot_chain(0, 0);\n}\n' "$SG" > "$Y"
    session "$INIT" "$(open_doc "$Y")" \
      '{"jsonrpc":"2.0","id":8,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$Y"'"},"position":{"line":2,"character":12}}}' "$DOWN"
    check "5 definition of sigil's sv_verify_boot_chain resolves" yes "$(has "\"uri\":\"file://$SG\"")"
    check "   …at its line ($((SGL - 1)))" yes "$(has "\"line\":$((SGL - 1)),\"character\":3")"
else
    check "5 premise: lib/sigil.cyr is vendored" yes no
fi

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: $NAME — $checks checks"
exit 0
