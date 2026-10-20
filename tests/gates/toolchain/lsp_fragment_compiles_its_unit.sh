#!/bin/sh
# lsp_fragment_compiles_its_unit.sh — 6.7.16. cyrius-lsp checks each file of a project through its
# UNIT — the entry that includes it, on the target that includes it — not alone.
#
# THE DEFECT (issues/2026-10-19-cyrius-lsp-compiles-an-include-fragment-alone.md, measured on the
# 6.7.16-open server): in a project the open file was always the unit (`cyrius check --with-deps
# --no-redirect <the open file>`), so a file that is an `include` of another was compiled ALONE and
# every name an earlier include declares read "undefined" — 55 false errors on cyrius's own
# src/frontend/parse_ctrl.cyr, a duplicate-fn warning per fn on lib/string.cyr (the [deps] prepend
# defined them first), 67 on lib/syscalls_windows.cyr (compiled for Linux), 3 errors on
# bootstrap/cybs.cyr (assembly for bootstrap/asm, not cycc input); and only the first 8,191 bytes of
# the compiler's stderr were read.
#
# ROWS (the server driven over stdio JSON-RPC from a directory OUTSIDE the projects, in a throwaway
# HOME whose .cyrius/bin holds this tree's cycc and a `cyrius` shim that logs each run — its argv, its
# working directory, its target selectors, the include file a lib/ unit is checked through — and
# execs this tree's CLI):
#   F1  a fragment (src/b.cyr: names src/a.cyr declares) publishes an EMPTY list, compiled through
#       the manifest entry src/main.cyr (`check --with-deps --no-redirect src/main.cyr`)
#   F2  a deep fragment (src/c.cyr, two hops) the same — through the manifest entry although
#       src/alt.cyr includes it directly (the manifest entry first)
#   F3  a real error in a fragment (src/d.cyr) is published at its own line and column
#   F4  a fragment whose own list is clean while its unit has errors gets ONE Information note
#       naming the unit, and the errors go to their own files (same unit)
#   F5  the entry's own error (`<source>`) is published on the entry
#   F6  a standalone file (no includer) is checked itself, its own error at its line
#   F7  a loose file (no project) is checked as before: `check <file>` from the server's directory
#   F8  a stale list is cleared: d.cyr's error, fixed on disk, is cleared when another file of the
#       same unit is saved
#   F9  ONE compile for N fragments: a.cyr, b.cyr and c.cyr opened -> one check of src/main.cyr;
#       F9b a file of the unit changed on disk -> compiled again
#   F10 a discovered entry: tool/part.cyr (included only by tool/run.cyr, as `include "part.cyr"`,
#       resolved through the entry's directory) is clean, through tool/run.cyr
#   F11 a Windows-only lib/ peer is checked through its public module under CYRIUS_TARGET_WIN=1
#       (`check <private dir>/unit.cyr`, holding `include "lib/plat.cyr"`)
#   F12 an aarch64-only lib/ peer gets one Information note and is NOT compiled
#   F13 a file `[lsp] skip` names is never compiled (an empty list)
#   F14 a public lib/ module is checked alone, with no [deps] prepend: no duplicate-fn warnings (and
#       the private directory its include file lived in is gone after the session)
#   F14b ...and INCLUDED, not fed as the entry: a lib/fnptr.cyr defining fncall0 (cycc refuses that
#       name in the main source, 6.6.20) is clean
#   F15 a file only a test includes is its own unit, not the test's
#   F16 the fragment's own error after > 8 KB of the entry's warnings is still published
#   F17 a location-less warning (`large static data`) goes on the unit's entry, not the fragment
#   F18 one file, one unit: a fragment of another entry does not publish on a shared include whose
#       own unit is the manifest entry's
#   F19 fewest hops: a fragment two discovered entries reach is checked through the nearer one
#   F20 a PEER publishes the open file only (the unit's error in lib/plat.cyr under Windows is not
#       published) and its note names the selector
#   F21 go-to-definition from a fragment reaches what an earlier include of its entry declares
#   F22 a server started under CYRIUS_TARGET_WIN=1 / CYRIUS_MACHO=1: neither its print-config run nor
#       its host unit's check carries them
#   F23 a server KILLED after a lib/ module's compile (an editor that never sends shutdown) leaves no
#       private directory: it is removed when the compile is done, not at exit
#   S   the acceptance sweep: every src/, lib/ and bootstrap/cybs.cyr file of this tree opened in one
#       session; each one's LAST list of the session (what the editor shows at its end) is empty but
#       for named entries' and NOTEs' (see the row), so a later unit polluting a shared fragment fails
# `LSP_BIN=<binary>` / `CLI_BIN=<binary>` run the gate against another build (the mutations).
#
# PROVEN RED (measured when written; each mutant a scratch copy of the server built with this tree's
# cycc and run through LSP_BIN, under the gate's `bash -eo pipefail`):
#   the 6.7.16-open server (a06468f28)  F1 F2 F4 F5 F6 F8 F9 F10 F11 F12 F13 F14 F14b F15 F16 F17 F18
#                                       F19 F20 F21 F22 F23 S, with its verdict (F3 F7 F9b hold: a fragment's
#                                       own error, a loose file and a recompile on change were right before)
#   _lsp_drain capped at 8,192 bytes    F16
#   a location-less warning on the open file  F17 S
#   a FRAGMENT publishing every file its compile names  F18
#   no unit note                        F4 F20
#   the stale list keyed by the open file  F4 F5 F8 F16 F17 (the same-unit filter keys on it too)
#   no target selector in the child's environment  F11 F20
#   a NOTE compiled                     F12 S
#   [lsp] skip not read                 F13 S
#   a public lib/ module with --with-deps  F14 F14b S (a duplicate-fn warning per fn of lib/alloc.cyr …)
#   a lib/ unit fed as the entry (no include file)  F11 F14 F14b F23 S (lib/fnptr.cyr's fncall0 refused)
#   the include file's directory removed at exit only  F23
#   test files walked as includers      F15
#   no manifest-first ranking           F2 F9
#   ranked by path order alone (no hops)  F19
#   no unit cache                       F9
#   the signature without the closure   F8 F9b
#   the entry's directory (#@incdir) not tried in the closure  F10
#   the unit's entry not indexed        F21
#   an inherited target selector kept   F22
#   every diagnostic on the unit's entry  F3 F4 F8 F16 F17
#   the loose route with --with-deps    F7
#   `<source>` on the open file         F3 F4 F5 F16
#   the unit's entry named absolute     F1 F6 F10 F11 F14 F14b F15 F18 F19 F20 F22 S
#   a PEER publishing like an entry     F20
#   this repo's cyrius.cyml without src/main_aarch64_native.cyr in [lsp] skip (the tools lane's review,
#       6.7.16)  S: the fork's own duplicate SYS_* warnings, and its SELF unit's `syscall arity
#       mismatch` warnings republished on the shared src/common/util.cyr, src/backend/common/env.cyr,
#       runtime.cyr, src/frontend/lex.cyr, ts/driver_input.cyr and lib/syscalls_*.cyr — which their
#       FIRST publish (the grading before) showed empty
# THE SHELL: the gate re-runs itself under `bash -eo pipefail` (GitHub's `run:` semantics), as
# lsp_diagnostics_file_column.sh does; `CY_LSP_GATE_INNER=1` keeps the shell that started it. A
# pipeline that can end early is written so its status is never the verdict (6.7.15's lesson: the
# first cut of row S ended the run with rc 141 and no verdict on the 6.7.16-open server).
if [ -z "${CY_LSP_GATE_INNER:-}" ] && command -v bash > /dev/null 2>&1; then
    CY_LSP_GATE_INNER=1 exec bash -eo pipefail "$0" "$@"
fi
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=lsp_fragment_compiles_its_unit
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "SKIP: $G: cyrius-lsp is driven here on Linux only"; exit 77; }
[ "$(uname -m)" = x86_64 ] || { echo "SKIP: $G: the target-selector rows need an x86_64 cycc"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
ok() { echo "  ok: $*"; }
fail() { echo "  FAIL: $*"; FAIL=1; }

mkdir -p "$W/h/.cyrius/bin" "$W/srv" "$W/tmp"
if [ -n "${LSP_BIN:-}" ]; then cp "$LSP_BIN" "$W/cyrius-lsp"
else "$CC" < programs/cyrius-lsp.cyr > "$W/cyrius-lsp" 2> "$W/lsp.err" && [ -s "$W/cyrius-lsp" ] \
  || { echo "FAIL: $G: programs/cyrius-lsp.cyr does not build:"; tail -3 "$W/lsp.err"; exit 1; }; fi
if [ -n "${CLI_BIN:-}" ]; then cp "$CLI_BIN" "$W/cyrius-real"
else "$CC" < cbt/cyrius.cyr > "$W/cyrius-real" 2> "$W/cli.err" && [ -s "$W/cyrius-real" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err"; exit 1; }; fi
chmod +x "$W/cyrius-lsp" "$W/cyrius-real"
cp "$CC" "$W/h/.cyrius/bin/cycc"
# The shim: one line per run (argv, cwd, the target selectors it was given), then the include file a
# lib/ unit is checked through, then the real CLI.
cat > "$W/h/.cyrius/bin/cyrius" <<EOF
#!/bin/sh
{ printf 'run:'; for a in "\$@"; do printf ' %s' "\$a"; done
  printf ' | cwd=%s |' "\$(pwd)"
  for v in CYRIUS_TARGET_WIN CYRIUS_TARGET_AGNOS CYRIUS_TARGET_EFI CYRIUS_MACHO; do
      eval "x=\\\${\$v:-}"; [ -n "\$x" ] && printf ' %s=%s' "\$v" "\$x"
  done
  printf '\n'
  for a in "\$@"; do case "\$a" in */unit.cyr) printf 'unit.cyr: %s\n' "\$(cat "\$a")" ;; esac; done
} >> "$W/shim.log"
exec "$W/cyrius-real" "\$@"
EOF
chmod +x "$W/h/.cyrius/bin/cyrius"

# One framed message; a write to a server that has gone is never the verdict (6.7.15, see
# lsp_diagnostics_file_column.sh).
msg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1" || true; }
open_msg() { msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/did$1\",\"params\":{\"textDocument\":{\"uri\":\"file://$2\",\"languageId\":\"cyrius\",\"version\":1,\"text\":\"\"}}}"; }
start() { msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'; }
stop() { msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'; msg '{"jsonrpc":"2.0","method":"exit"}'; }
# serve <out> — the framed requests on stdin, the server run from $W/srv (outside every project);
# its publishDiagnostics params, one per line, paths relative to $W. $SERVE_ENV: extra NAME=value
# words for the server's environment.
serve() {
    : > "$W/shim.log"
    # shellcheck disable=SC2086
    ( cd "$W/srv" && env -i HOME="$W/h" CYRIUS_HOME="$W/h/.cyrius" PATH=/usr/bin:/bin TMPDIR="$W/tmp" ${SERVE_ENV:-} \
        timeout "${SERVE_SECS:-120}" "$W/cyrius-lsp" 2>> "$W/lsp.log" ) \
      | tr '\r' '\n' | grep -o '"uri":"[^"]*","diagnostics":.*\|"id":3,"result":.*' \
      | sed -e "s|file://$W/||g" -e 's/Content-Length: [0-9]*$//' > "$1" || true
    cp "$W/shim.log" "$1.shim"
}
pub() { grep "^\"uri\":\"$2\"," "$1" || true; }
empty() { [ "$(pub "$1" "$2" | tail -1)" = "\"uri\":\"$2\",\"diagnostics\":[]}}" ]; }
checks() { grep -c '^run: check' "$1.shim" || true; }
# wait for the server's Nth "sent diagnostics" (a feeder that edits a file between two opens)
sent_wait() { w=0; while [ "$(grep -c 'sent diagnostics' "$W/lsp.log" || true)" -lt "$1" ] && [ "$w" -lt 600 ]; do sleep 0.1; w=$((w + 1)); done; }

# ── p1: a clean project, its manifest entry src/main.cyr ────────────────────────────────────
P=$W/p1
mkdir -p "$P/src" "$P/tools" "$P/tests"
printf '[package]\nname = "p1"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\n\n[lsp]\nskip = ["tools/asm.cyr"]\n' > "$P/cyrius.cyml"
printf 'include "src/a.cyr"\ninclude "src/b.cyr"\nsyscall(60, total_b());\n' > "$P/src/main.cyr"
printf 'var shared_x = 40;\nfn helper_a(): i64 { return 2; }\n' > "$P/src/a.cyr"
printf 'include "src/c.cyr"\nfn total_b(): i64 { return shared_x + helper_a() + deep_c(); }\n' > "$P/src/b.cyr"
printf 'fn deep_c(): i64 { return shared_x - 40; }\n' > "$P/src/c.cyr"
printf 'var shared_x = 1;\ninclude "src/c.cyr"\n' > "$P/src/alt.cyr"
printf 'var s = 1;\nvar t = nope_solo + 1;\n' > "$P/src/solo.cyr"
printf 'mov rax, 60\nthis is not cyrius at all {\n' > "$P/tools/asm.cyr"
printf 'fn only_tested(): i64 { return 1; }\n' > "$P/src/only_tested.cyr"
printf 'include "src/only_tested.cyr"\nvar r = only_tested();\nvar r2 = assert_summary();\n' > "$P/tests/t.tcyr"

{ trap '' PIPE; start; open_msg Open "$P/src/b.cyr"; open_msg Open "$P/src/c.cyr"; open_msg Open "$P/src/a.cyr"
  stop; true; } 2> /dev/null | serve "$W/r1"
if empty "$W/r1" p1/src/b.cyr && grep -q '^run: check --with-deps --no-redirect src/main.cyr | cwd='"$P"' |$' "$W/r1.shim"; then
    ok "F1 the fragment src/b.cyr: an empty list, checked through src/main.cyr"
else fail "F1 src/b.cyr: $(pub "$W/r1" p1/src/b.cyr | cut -c1-200) / runs: $(tr '\n' ';' < "$W/r1.shim")"; fi
if empty "$W/r1" p1/src/c.cyr && ! grep -q 'src/alt.cyr' "$W/r1.shim"; then
    ok "F2 the deep fragment src/c.cyr: empty, through the manifest entry (not the nearer src/alt.cyr)"
else fail "F2 src/c.cyr: $(pub "$W/r1" p1/src/c.cyr | cut -c1-200) / runs: $(tr '\n' ';' < "$W/r1.shim")"; fi
n=$(checks "$W/r1")
if [ "$n" = 1 ] && empty "$W/r1" p1/src/a.cyr; then
    ok "F9 three fragments of one entry: one compile"
else fail "F9 $n checks for three fragments of src/main.cyr: $(tr '\n' ';' < "$W/r1.shim")"; fi
# F21: b.cyr alone opened (a.cyr is not), then go-to-definition of `shared_x` in it
{ trap '' PIPE; start; open_msg Open "$P/src/b.cyr"
  msg '{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$P"'/src/b.cyr"},"position":{"line":1,"character":34}}}'
  stop; true; } 2> /dev/null | serve "$W/r21"
if grep -qF '"id":3,"result":{"uri":"p1/src/a.cyr","range":{"start":{"line":0,"character":4}' "$W/r21"; then
    ok "F21 go-to-definition of shared_x from src/b.cyr reaches src/a.cyr (the unit's entry is indexed)"
else fail "F21 definition from src/b.cyr: $(grep '"id":3' "$W/r21" | cut -c1-200)"; fi

# F9b: a file of the unit changed on disk is compiled again
: > "$W/lsp.log"
cp "$P/src/c.cyr" "$W/c.keep"
{ trap '' PIPE; start; open_msg Open "$P/src/b.cyr"; sent_wait 1
  printf 'fn deep_c(): i64 { return shared_x - 39; }\n' > "$P/src/c.cyr"; open_msg Save "$P/src/b.cyr"; stop; true; } 2> /dev/null | serve "$W/r9"
cp "$W/c.keep" "$P/src/c.cyr"
n=$(checks "$W/r9")
if [ "$n" = 2 ]; then ok "F9b src/c.cyr changed on disk between two saves: compiled again (2 checks)"
else fail "F9b $n checks across a change on disk: $(tr '\n' ';' < "$W/r9.shim")"; fi

{ trap '' PIPE; start; open_msg Open "$P/src/solo.cyr"; open_msg Open "$P/tools/asm.cyr"; open_msg Open "$P/src/only_tested.cyr"
  stop; true; } 2> /dev/null | serve "$W/r6"
P6=$(pub "$W/r6" p1/src/solo.cyr)
if printf '%s' "$P6" | grep -qF '"start":{"line":1,"character":18}' && printf '%s' "$P6" | grep -qF "undefined variable 'nope_solo'" \
   && grep -q '^run: check --with-deps --no-redirect src/solo.cyr ' "$W/r6.shim"; then
    ok "F6 a file nothing includes is checked itself: its own error at line 1"
else fail "F6 src/solo.cyr: ${P6:-none} / runs: $(tr '\n' ';' < "$W/r6.shim")"; fi
if empty "$W/r6" p1/tools/asm.cyr && ! grep -q 'tools/asm.cyr' "$W/r6.shim"; then
    ok "F13 tools/asm.cyr, named by [lsp] skip: an empty list, never compiled"
else fail "F13 tools/asm.cyr: $(pub "$W/r6" p1/tools/asm.cyr | cut -c1-200) / runs: $(tr '\n' ';' < "$W/r6.shim")"; fi
if grep -q '^run: check --with-deps --no-redirect src/only_tested.cyr ' "$W/r6.shim" && empty "$W/r6" p1/src/only_tested.cyr; then
    ok "F15 src/only_tested.cyr (only tests/t.tcyr includes it) is its own unit"
else fail "F15 src/only_tested.cyr: runs: $(tr '\n' ';' < "$W/r6.shim")"; fi

# ── p2: errors in the unit ───────────────────────────────────────────────────────────────────
P=$W/p2
mkdir -p "$P/src"
printf '[package]\nname = "p2"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\n' > "$P/cyrius.cyml"
cp "$W/p1/src/a.cyr" "$W/p1/src/b.cyr" "$W/p1/src/c.cyr" "$P/src/"
printf 'include "src/a.cyr"\ninclude "src/b.cyr"\ninclude "src/d.cyr"\nvar m = nope_main + 1;\n' > "$P/src/main.cyr"
printf 'var d1 = 1;\nvar d2 = 2;\nvar bad = nope_d + 1;\n' > "$P/src/d.cyr"
{ trap '' PIPE; start; open_msg Open "$P/src/d.cyr"; open_msg Open "$P/src/b.cyr"; stop; true; } 2> /dev/null | serve "$W/r3"
PD=$(pub "$W/r3" p2/src/d.cyr | head -1)
if printf '%s' "$PD" | grep -qF '"start":{"line":2,"character":17}' && printf '%s' "$PD" | grep -qF "undefined variable 'nope_d'" \
   && ! printf '%s' "$PD" | grep -q 'nope_main'; then
    ok "F3 a real error in the fragment src/d.cyr: at its own line 2, character 17 (cycc's column)"
else fail "F3 src/d.cyr: ${PD:-none}"; fi
PB=$(pub "$W/r3" p2/src/b.cyr)
if [ "$(printf '%s' "$PB" | { grep -o '"severity":[0-9]' || true; } | tr '\n' ' ')" = '"severity":3 ' ] \
   && printf '%s' "$PB" | grep -qF '"message":"checked as part of src/main.cyr, which has 2 errors in other files"' \
   && [ "$(pub "$W/r3" p2/src/d.cyr | wc -l)" = 2 ] && pub "$W/r3" p2/src/d.cyr | tail -1 | grep -qF "nope_d"; then
    ok "F4 src/b.cyr (clean) gets one Information note naming its unit; d.cyr gets its error again"
else fail "F4 src/b.cyr: ${PB:-none} / d.cyr: $(pub "$W/r3" p2/src/d.cyr | wc -l) publishes"; fi
PM=$(pub "$W/r3" p2/src/main.cyr | tail -1)
if printf '%s' "$PM" | grep -qF '"start":{"line":3,"character":18}' && printf '%s' "$PM" | grep -qF "undefined variable 'nope_main'"; then
    ok "F5 the entry's own error (<source>) is published on src/main.cyr, line 3"
else fail "F5 src/main.cyr: ${PM:-none}"; fi

# F8: d.cyr fixed on disk, then b.cyr saved: d.cyr's list is cleared by the unit's recompile
: > "$W/lsp.log"
{ trap '' PIPE; start; open_msg Open "$P/src/d.cyr"; sent_wait 1
  printf 'var d1 = 1;\nvar d2 = 2;\nvar bad = d1 + 1;\n' > "$P/src/d.cyr"; open_msg Save "$P/src/b.cyr"; stop; true; } 2> /dev/null | serve "$W/r8"
if pub "$W/r8" p2/src/d.cyr | head -1 | grep -qF 'nope_d' && [ "$(pub "$W/r8" p2/src/d.cyr | tail -1)" = '"uri":"p2/src/d.cyr","diagnostics":[]}}' ]; then
    ok "F8 src/d.cyr fixed on disk: src/b.cyr's save (same unit) publishes an empty list on it"
else fail "F8 src/d.cyr's publishes: $(pub "$W/r8" p2/src/d.cyr | tr '\n' ' ' | cut -c1-300)"; fi

# ── F7: a loose file (no cyrius.cyml above it) ──────────────────────────────────────────────
mkdir -p "$W/srv/loose"
printf 'var x = 1;\nvar y = nope_loose + 2;\n' > "$W/srv/loose/col.cyr"
{ trap '' PIPE; start; open_msg Open "$W/srv/loose/col.cyr"; stop; true; } 2> /dev/null | serve "$W/r7"
P7=$(pub "$W/r7" srv/loose/col.cyr)
if printf '%s' "$P7" | grep -qF '"start":{"line":1,"character":19}' && grep -q '^run: check loose/col.cyr | cwd='"$W"'/srv |$' "$W/r7.shim"; then
    ok "F7 a loose file: \`check loose/col.cyr\` from the server's directory, its own error"
else fail "F7 loose/col.cyr: ${P7:-none} / runs: $(tr '\n' ';' < "$W/r7.shim")"; fi

# ── p3: discovered entries (no [build] entry) ───────────────────────────────────────────────
P=$W/p3
mkdir -p "$P/tool"
printf '[package]\nname = "p3"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
printf 'var base_value = 41;\ninclude "part.cyr"\nvar r = part_value();\n' > "$P/tool/run.cyr"
printf 'fn part_value(): i64 { return base_value + 1; }\n' > "$P/tool/part.cyr"
printf 'var far_base = 1;\ninclude "tool/mid.cyr"\n' > "$P/tool/a_far.cyr"
printf 'include "tool/deep.cyr"\n' > "$P/tool/mid.cyr"
printf 'var far_base = 2;\ninclude "tool/deep.cyr"\n' > "$P/tool/z_near.cyr"
printf 'var deep_v = far_base + 1;\n' > "$P/tool/deep.cyr"
{ trap '' PIPE; start; open_msg Open "$P/tool/part.cyr"; open_msg Open "$P/tool/deep.cyr"; stop; true; } 2> /dev/null | serve "$W/r10"
if empty "$W/r10" p3/tool/part.cyr && grep -q '^run: check --with-deps --no-redirect tool/run.cyr ' "$W/r10.shim"; then
    ok "F10 tool/part.cyr (\`include \"part.cyr\"\` in tool/run.cyr): empty, through the discovered entry"
else fail "F10 tool/part.cyr: $(pub "$W/r10" p3/tool/part.cyr | cut -c1-200) / runs: $(tr '\n' ';' < "$W/r10.shim")"; fi
if empty "$W/r10" p3/tool/deep.cyr && grep -q '^run: check --with-deps --no-redirect tool/z_near.cyr ' "$W/r10.shim" \
   && ! grep -q 'tool/a_far.cyr' "$W/r10.shim"; then
    ok "F19 tool/deep.cyr: through tool/z_near.cyr (1 hop), not tool/a_far.cyr (2 hops, first in path order)"
else fail "F19 tool/deep.cyr: runs: $(tr '\n' ';' < "$W/r10.shim")"; fi

# ── p4: lib/ — a public module, its per-target peers, the dev-mode stdlib (./lib) ─────────────
P=$W/p4
mkdir -p "$P/lib" "$P/src"
printf '[package]\nname = "p4"\nversion = "0.1.0"\n\n[deps]\nstdlib = ["plat"]\n' > "$P/cyrius.cyml"
printf '# a stand-in: ./lib holding syscalls.cyr is the stdlib the CLI resolves [deps] from\n' > "$P/lib/syscalls.cyr"
cat > "$P/lib/plat.cyr" <<'EOF'
# Usage: include "lib/plat.cyr"
fn plat_base(): i64 { return 7; }
#ifdef CYRIUS_TARGET_WIN
var plat_w = nope_win + 1;
include "lib/plat_win.cyr"
#endif
#ifdef CYRIUS_ARCH_AARCH64
include "lib/plat_a64.cyr"
#endif
#ifdef CYRIUS_TARGET_LINUX
#ifdef CYRIUS_ARCH_X86
include "lib/plat_lx.cyr"
#endif
#endif
EOF
printf 'fn plat_os(): i64 { return plat_base() + 1; }\n' > "$P/lib/plat_win.cyr"
printf 'fn plat_os(): i64 { return plat_base() + 2; }\n' > "$P/lib/plat_a64.cyr"
printf 'fn plat_os(): i64 { return plat_base() + 3; }\n' > "$P/lib/plat_lx.cyr"
printf '# Usage: include "lib/fnptr.cyr"\nfn fncall0(fp): i64 { return 0; }\n' > "$P/lib/fnptr.cyr"
printf 'var x = plat_os();\n' > "$P/src/main.cyr"
{ trap '' PIPE; start; open_msg Open "$P/lib/plat_win.cyr"; open_msg Open "$P/lib/plat_a64.cyr"; open_msg Open "$P/lib/plat.cyr"
  open_msg Open "$P/lib/fnptr.cyr"; stop; true; } 2> /dev/null | serve "$W/r11"
PW=$(pub "$W/r11" p4/lib/plat_win.cyr)
if grep -q '^run: check /.*/unit.cyr | cwd='"$P"' | CYRIUS_TARGET_WIN=1$' "$W/r11.shim" \
   && grep -q '^unit.cyr: include "lib/plat.cyr"$' "$W/r11.shim" && ! printf '%s' "$PW" | grep -q '"severity":[12]'; then
    ok "F11 lib/plat_win.cyr: through \`include \"lib/plat.cyr\"\` under CYRIUS_TARGET_WIN=1, no error of its own"
else fail "F11 lib/plat_win.cyr: ${PW:-none} / runs: $(tr '\n' ';' < "$W/r11.shim")"; fi
if printf '%s' "$PW" | grep -qF '"severity":3,"source":"cyrius","message":"checked as part of lib/plat.cyr (CYRIUS_TARGET_WIN=1), which has 1 error in another file"' \
   && ! pub "$W/r11" p4/lib/plat.cyr | head -1 | grep -q nope_win; then
    ok "F20 a PEER publishes the open file only (lib/plat.cyr's Windows error is not), with the note naming the selector"
else fail "F20 lib/plat_win.cyr: ${PW:-none} / lib/plat.cyr first: $(pub "$W/r11" p4/lib/plat.cyr | head -1 | cut -c1-200)"; fi
PA=$(pub "$W/r11" p4/lib/plat_a64.cyr)
if printf '%s' "$PA" | grep -qF '"severity":3' && printf '%s' "$PA" | grep -qF 'aarch64 Linux, aarch64 macOS (through lib/plat.cyr)' \
   && [ "$(printf '%s' "$PA" | { grep -o '"severity"' || true; } | wc -l)" = 1 ] && [ "$(grep -c '^run: check' "$W/r11.shim")" = 3 ]; then
    ok "F12 lib/plat_a64.cyr (aarch64 only): one Information note, no compile (3 checks for 4 files)"
else fail "F12 lib/plat_a64.cyr: ${PA:-none} / runs: $(tr '\n' ';' < "$W/r11.shim")"; fi
LEFT=$(cd "$W/tmp" && { ls -d cyrius-lsp-* 2> /dev/null || true; } | tr '\n' ' ')
if empty "$W/r11" p4/lib/plat.cyr && grep -q '^unit.cyr: include "lib/plat.cyr"$' "$W/r11.shim" \
   && ! grep -q 'with-deps.*lib/plat' "$W/r11.shim" && [ -z "$LEFT" ]; then
    ok "F14 lib/plat.cyr (public, in [deps] stdlib): checked alone with no prepend — no duplicate-fn warnings; no private directory left"
else fail "F14 lib/plat.cyr: $(pub "$W/r11" p4/lib/plat.cyr | cut -c1-200) / runs: $(tr '\n' ';' < "$W/r11.shim") / left in TMPDIR: ${LEFT:-none}"; fi
if empty "$W/r11" p4/lib/fnptr.cyr && grep -q '^unit.cyr: include "lib/fnptr.cyr"$' "$W/r11.shim"; then
    ok "F14b lib/fnptr.cyr defining fncall0 is checked as included: clean"
else fail "F14b lib/fnptr.cyr: $(pub "$W/r11" p4/lib/fnptr.cyr | cut -c1-200)"; fi

# F23: the server is killed (timeout's SIGTERM) after lib/plat.cyr's compile, with no shutdown
rm -rf "$W/tmp" && mkdir -p "$W/tmp"
: > "$W/lsp.log"
{ trap '' PIPE; start; open_msg Open "$W/p4/lib/plat.cyr"; sent_wait 1; sleep 10; true; } 2> /dev/null | SERVE_SECS=8 serve "$W/r23"
LEFT=$(cd "$W/tmp" && { ls -d cyrius-lsp-* 2> /dev/null || true; } | tr '\n' ' ')
if grep -q '^unit.cyr: include "lib/plat.cyr"$' "$W/r23.shim" && empty "$W/r23" p4/lib/plat.cyr && [ -z "$LEFT" ]; then
    ok "F23 a server killed after a lib/ module's compile leaves no private directory in TMPDIR"
else fail "F23 left in TMPDIR: ${LEFT:-none} / runs: $(tr '\n' ';' < "$W/r23.shim")"; fi

# ── p5: > 8 KB of the entry's warnings ahead of the fragment's error ─────────────────────────
P=$W/p5
mkdir -p "$P/src"
printf '[package]\nname = "p5"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\n' > "$P/cyrius.cyml"
{ i=0; while [ "$i" -lt 200 ]; do echo 'fn dup_noise(): i64 { return 0; }'; i=$((i + 1)); done; echo 'include "src/frag.cyr"'; } > "$P/src/main.cyr"
printf 'var f1 = 1;\nvar f2 = nope_frag + 1;\n' > "$P/src/frag.cyr"
{ trap '' PIPE; start; open_msg Open "$P/src/frag.cyr"; stop; true; } 2> /dev/null | serve "$W/r16"
P16=$(pub "$W/r16" p5/src/frag.cyr)
NW=$(pub "$W/r16" p5/src/main.cyr | { grep -o 'duplicate fn' || true; } | wc -l)
if printf '%s' "$P16" | grep -qF '"start":{"line":1,"character":19}' && printf '%s' "$P16" | grep -qF "nope_frag" && [ "$NW" -ge 150 ]; then
    ok "F16 src/frag.cyr's error after $NW duplicate-fn warnings (> 8 KB) of its entry is published"
else fail "F16 src/frag.cyr: ${P16:-none} / main.cyr warnings: $NW"; fi

# ── p6: a location-less warning; one file, one unit ─────────────────────────────────────────
P=$W/p6
mkdir -p "$P/src" "$P/tool"
printf '[package]\nname = "p6"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\n' > "$P/cyrius.cyml"
printf 'var big[70000];\ninclude "src/s.cyr"\ninclude "src/f.cyr"\n' > "$P/src/main.cyr"
printf 'fn dupg(): i64 { return 1; }\nfn dupg(): i64 { return 2; }\n' > "$P/src/s.cyr"
printf 'var f = dupg();\n' > "$P/src/f.cyr"
printf 'include "src/s.cyr"\ninclude "tool/o.cyr"\n' > "$P/tool/other.cyr"
printf 'var o = dupg();\n' > "$P/tool/o.cyr"
{ trap '' PIPE; start; open_msg Open "$P/src/f.cyr"; stop; true; } 2> /dev/null | serve "$W/r17"
if empty "$W/r17" p6/src/f.cyr && pub "$W/r17" p6/src/main.cyr | grep -qF '"start":{"line":0,"character":0}' \
   && pub "$W/r17" p6/src/main.cyr | grep -qF 'large static data' && pub "$W/r17" p6/src/s.cyr | grep -qF "duplicate fn 'dupg'"; then
    ok "F17 \`large static data\` (no location) is published on the unit's entry src/main.cyr; src/f.cyr's list is empty"
else fail "F17 f.cyr: $(pub "$W/r17" p6/src/f.cyr | cut -c1-200) / main.cyr: $(pub "$W/r17" p6/src/main.cyr | cut -c1-200)"; fi
{ trap '' PIPE; start; open_msg Open "$P/tool/o.cyr"; stop; true; } 2> /dev/null | serve "$W/r18"
if empty "$W/r18" p6/tool/o.cyr && grep -q 'check --with-deps --no-redirect tool/other.cyr ' "$W/r18.shim" \
   && [ -z "$(pub "$W/r18" p6/src/s.cyr)" ]; then
    ok "F18 tool/o.cyr (unit tool/other.cyr) publishes nothing on src/s.cyr, whose own unit is src/main.cyr"
else fail "F18 o.cyr: $(pub "$W/r18" p6/tool/o.cyr | cut -c1-120) / s.cyr: $(pub "$W/r18" p6/src/s.cyr | cut -c1-200)"; fi

# ── F22: the server's own CYRIUS_TARGET_WIN=1 reaches neither a host unit nor print-config ──
{ trap '' PIPE; start; open_msg Open "$W/p1/src/b.cyr"; stop; true; } 2> /dev/null | SERVE_ENV="CYRIUS_TARGET_WIN=1 CYRIUS_MACHO=1" serve "$W/r22"
if empty "$W/r22" p1/src/b.cyr && grep -q '^run: build --print-config | cwd='"$W"'/p1 |$' "$W/r22.shim" \
   && grep -q '^run: check --with-deps --no-redirect src/main.cyr | cwd='"$W"'/p1 |$' "$W/r22.shim"; then
    ok "F22 a server started under CYRIUS_TARGET_WIN=1 / CYRIUS_MACHO=1 runs its host unit and print-config without them"
else fail "F22 runs: $(tr '\n' ';' < "$W/r22.shim") / b.cyr: $(pub "$W/r22" p1/src/b.cyr | cut -c1-200)"; fi

# ── S: the acceptance sweep — this tree's own src/ and lib/, and bootstrap/cybs.cyr ──────────
# Every file opened in one session; each one's LAST list of the session — what the editor shows when
# the sweep ends, after every later unit has published — must be empty, but for what these entries and
# notes really say (the files their unit is themselves, or a NOTE). Its first publish alone could not
# see a later SELF unit republishing a shared fragment (the aarch64-native fork's did, below):
#   src/main.cyr, src/main_win.cyr, src/main_x86_macho.cyr — their own location-less
#       `large static data` warning (an entry's, unchanged)
#   lib/alloc_cx.cyr (cx), lib/syscalls_aarch64_linux.cyr (aarch64) — the one Information NOTE
#   src/main_aarch64_native.cyr — named by this repo's `[lsp] skip` (built only by the aarch64
#       compiler, raw: a check of it on x86_64 with the [deps] prepend read its SYS_* numbers as
#       conflicts and republished `syscall arity mismatch` on util.cyr, env.cyr, runtime.cyr, lex.cyr,
#       driver_input.cyr and lib/syscalls_*.cyr), so an empty list like every other file
#   EXEMPT (filed from the 6.7.16 tools lane): lib/yukti.cyr, a fold that does not compile alone
#       (2026-10-19-yukti-fold-does-not-compile-alone.md)
tree_files() { ( cd "$ROOT" && { find src lib -name '*.cyr'; echo bootstrap/cybs.cyr; } | sort ); }
NS=$(tree_files | wc -l | tr -d ' ')
{ trap '' PIPE; start; for f in $(tree_files); do open_msg Open "$ROOT/$f"; done; stop; true; } 2> /dev/null \
  | SERVE_SECS=900 serve "$W/rs"
sed -e "s|file://$ROOT/|TREE/|" "$W/rs" > "$W/rs.t"
bad=""; seen=0
for f in $(tree_files); do
    # its LAST publish of the session
    last=$(grep "^\"uri\":\"TREE/$f\"," "$W/rs.t" | awk '{ l = $0 } END { if (NR) print l }' || true)
    [ -n "$last" ] && seen=$((seen + 1))
    case "$f" in
        lib/yukti.cyr) continue ;;
        src/main.cyr|src/main_win.cyr|src/main_x86_macho.cyr)
            sev=$(printf '%s' "$last" | { grep -o '"severity":[0-9]' || true; } | tr '\n' ' ')
            [ "$sev" = '"severity":2 ' ] && printf '%s' "$last" | grep -qF 'large static data' && continue ;;
        lib/alloc_cx.cyr|lib/syscalls_aarch64_linux.cyr)
            sev=$(printf '%s' "$last" | { grep -o '"severity":[0-9]' || true; } | tr '\n' ' ')
            [ "$sev" = '"severity":3 ' ] && printf '%s' "$last" | grep -qF 'not compiled here' && continue ;;
        *) [ "$last" = "\"uri\":\"TREE/$f\",\"diagnostics\":[]}}" ] && continue ;;
    esac
    # its first message (awk reads its input whole: a `| head -1` would end a writer with
    # SIGPIPE, the pipeline's status under pipefail, and `set -e` would end the gate unverdicted)
    bad="$bad
    $f: $(printf '%s\n' "${last:-no publish}" | awk '{ i = index($0, "\"message\":\""); if (i) { s = substr($0, i + 11); print substr(s, 1, index(s, "\"") - 1) } else print substr($0, 1, 160) }')"
done
if [ "$NS" -ge 150 ] && [ "$seen" = "$NS" ] && [ -z "$bad" ]; then
    ok "S the acceptance sweep: $NS files of src/, lib/ and bootstrap/cybs.cyr opened, each one's last list as it should be"
else fail "S the sweep ($seen of $NS files published; floor 150):$bad"; fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G"; exit 1; }
echo "PASS: $G"
exit 0
