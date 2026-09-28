#!/bin/sh
# Gate: `cyrius header <file.cyr>` emits a C prototype for EVERY public fn of the file —
# every declaration spelling, the file-scope `private` rule — and reads the WHOLE file
# (6.6.8). Until 6.6.8 this verb had NO gate anywhere. H5 pins the same 64 KiB read in
# `cyrius doctest`, fixed in the same bite.
#
# THREE DEFECTS, ALL rc=0 (plus a fourth that the first cut of the fix introduced):
#
#  1. SPELLINGS. It matched a column-0 `pub fn ` and nothing else (its comment said "pub fn
#     or fn"). A bare `fn` — public in an ordinary file — never got a prototype, nor did
#     `public fn` (the SAME lexer token as `pub`), `fn<TAB>`, `pub  fn`, an indented fn or
#     an attributed `#inline fn`. Meanwhile the coverage gate's header claimed "the
#     native-header generator already handled both spellings": a check sharing a defect
#     with the thing it checks.
#  2. THE FILE-SCOPE `private` RULE. In a `private` file only `pub`/`public` fns are
#     exported; the bare fns are file-private and must NOT get a prototype.
#  3. A FIXED 64 KiB READ. An 81,752-byte file with `pub fn late` past the cut emitted
#     only `early`, rc=0.
#
#  4. METHODS AND `main` — introduced by the FIRST CUT of this fix (accepting indented and
#     bare fns) and caught in its review, never released. A fn inside `impl T for S { … }`
#     is a method emitted as `S_m`; read by its bare name it printed conflicting prototypes
#     (`new`, twice, for method_dispatch.tcyr). Only brace depth 0 is FFI surface. And a
#     program's `fn main` is its entry point: its prototype would collide with the C host's
#     `int main`.
#
# The declaration rule is cbt/core.cyr `_src_public_fn_at` — the one cmd_coverage uses, so
# the two verbs cannot disagree about what is public again.
#
# MUTATION LEDGER (6.6.8; build/cyrius rebuilt from each mutant, gate re-run):
#   _src_decl_at back to column-0 `fn `/`pub fn ` only   → H1, H2 FAIL (8 assertions)
#   _src_file_private forced to 0                        → H2 FAIL
#   _src_blank_noncode made a no-op                      → H1 FAIL (comment/string decls)
#   cmd_header truncated at 64 KiB again                 → H3 FAIL
#   cmd_doctest truncated at 64 KiB again                → H5 FAIL
#   _src_brace_delta counts nothing (impl methods top)   → H6 FAIL
#   `main` no longer excluded                            → H1 FAIL
#   no whitespace skipped between attribute and `(`     → H1 FAIL
#   the optional `async` before `fn` not accepted        → H1 FAIL
#   `pub` / `public` must follow every attribute         → H1 FAIL
#   `private;` + an item on the same line rejected       → H2 FAIL
#   real tree → every assertion green
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: header_spellings_and_size: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
# has <out-file> <exact prototype line>
has() { grep -cxF "$2" "$1" || true; }

[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }
cd "$D" || exit 2

# ── H1: every spelling the compiler accepts; not `_` names, not a comment, not a string.
echo "H1 — every public declaration spelling gets a prototype:"
printf 'pub fn h_pub(a, b: i64): i64 { return a; }\npublic fn h_public(): i64 { return 1; }\nfn h_bare(x): i64 { return x; }\nfn\th_tab(): i64 { return 1; }\npub  fn h_twosp(): i64 { return 1; }\n    fn h_indent(): i64 { return 1; }\n#inline fn h_attr(): i64 { return 1; }\n#deprecated("use (x)") pub fn h_dep(q): i64 { return q; }\n#deprecated ("old") fn h_depsp(x): i64 { return x; }\nasync fn h_async(x) { return x; }\npub #inline fn h_pubattr(): i64 { return 1; }\npublic #inline fn h_publicattr(): i64 { return 1; }\nfn main(): i64 { return 0; }\nfn _h_private(): i64 { return 1; }\n# fn h_comment(): i64 { return 1; }\nvar s = "\nfn h_string(): i64 {\n";\n' > s.cyr
"$CY" header s.cyr > o1 2>&1; rc1=$?
check "exit 0" 0 "$rc1"
check "pub fn, with params" 1 "$(has o1 'cyr_val h_pub(cyr_val a, cyr_val b);')"
check "public fn" 1 "$(has o1 'cyr_val h_public(void);')"
check "bare fn (public in an ordinary file)" 1 "$(has o1 'cyr_val h_bare(cyr_val x);')"
check "fn<TAB>" 1 "$(has o1 'cyr_val h_tab(void);')"
check "pub  fn (two spaces)" 1 "$(has o1 'cyr_val h_twosp(void);')"
check "indented fn" 1 "$(has o1 'cyr_val h_indent(void);')"
check "#inline fn" 1 "$(has o1 'cyr_val h_attr(void);')"
check "#deprecated(...) pub fn" 1 "$(has o1 'cyr_val h_dep(cyr_val q);')"
check "#deprecated (...) fn — a space before the argument list" 1 "$(has o1 'cyr_val h_depsp(cyr_val x);')"
check "async fn" 1 "$(has o1 'cyr_val h_async(cyr_val x);')"
check "pub #inline fn — pub before the attribute" 1 "$(has o1 'cyr_val h_pubattr(void);')"
check "public #inline fn — public before the attribute" 1 "$(has o1 'cyr_val h_publicattr(void);')"
check "no prototype for the program's fn main (it would collide with the C host's)" 0 "$(grep -c ' main(' o1 || true)"
check "exactly those 12 prototypes" 12 "$(grep -c '^cyr_val ' o1 || true)"
check "no _name / comment / string declaration" 0 "$(grep -cE 'h_private|h_comment|h_string' o1 || true)"

# ── H2: a `private` file exports only its pub/public fns — the marker covers the whole
# file, so a bare fn written ABOVE it is private too.
echo "H2 — in a private file only pub/public fns get a prototype:"
printf 'fn above(): i64 { return 1; }\nprivate\nfn helper(): i64 { return 7; }\npublic fn api(): i64 { return helper(); }\npub fn api2(): i64 { return 1; }\n' > p.cyr
"$CY" header p.cyr > o2 2>&1
check "public fn api" 1 "$(has o2 'cyr_val api(void);')"
check "pub fn api2" 1 "$(has o2 'cyr_val api2(void);')"
check "no prototype for a file-private fn" 0 "$(grep -cE 'helper|above' o2 || true)"
# `private;` closes the marker with an item on the SAME line: that line makes the file
# private and declares its item.
printf 'private; pub fn pvs_x(): i64 { return 1; }\nprivate; fn pvs_y(): i64 { return 2; }\n' > ps.cyr
"$CY" header ps.cyr > o2b 2>&1
check "\`private; pub fn\` gets a prototype" 1 "$(has o2b 'cyr_val pvs_x(void);')"
check "\`private; fn\` does not" 0 "$(grep -c 'pvs_y' o2b || true)"

# ── H3: past the old fixed 64 KiB read.
echo "H3 — a >64 KiB file is read whole:"
{ echo 'pub fn early(): i64 { return 1; }'
  awk 'BEGIN{for(j=0;j<1300;j++) print "# filler line to push the next fn past the old 64 KiB header read ......"}'
  echo 'pub fn late(z): i64 { return z; }'; } > big.cyr
check "file exceeds the old 64 KiB cap" 1 "$([ "$(wc -c < big.cyr)" -gt 65536 ] && echo 1 || echo 0)"
"$CY" header big.cyr > o3 2>&1; rc3=$?
check "exit 0" 0 "$rc3"
check "the fn before the cut" 1 "$(has o3 'cyr_val early(void);')"
check "the fn AFTER the cut" 1 "$(has o3 'cyr_val late(cyr_val z);')"

# ── H4: an unreadable file is an error, not an empty header.
echo "H4 — a missing file fails:"
"$CY" header no_such_file.cyr > o4 2>&1; rc4=$?
check "exit non-zero" 1 "$([ "$rc4" -ne 0 ] && echo 1 || echo 0)"
check "and says so" 1 "$(grep -c 'cannot read' o4 || true)"

# ── H5: the sibling fixed 64 KiB read in `cyrius doctest` (same file, same fix). An
# example past the cut silently did not exist — neither run nor counted — so a FAILING
# example there read "1 passed, 0 failed", rc=0. The compiler is pinned to this tree's
# build/cycc through a throwaway CYRIUS_HOME, so the axis never reads the live store.
echo "H5 — cyrius doctest reads a >64 KiB file whole:"
mkdir -p "$D/home/bin" && ln -s "$ROOT/build/cycc" "$D/home/bin/cycc"
{ printf '# >>> syscall(60, 3);\n# === 3\nfn dt_a(): i64 { return 1; }\n'
  awk 'BEGIN{for(j=0;j<1300;j++) print "# filler line to push the next example past the old 64 KiB doctest read"}'
  printf 'fn dt_z(): i64 { return 1; }\n# >>> syscall(60, 4);\n# === 5\nfn dt_b(): i64 { return 1; }\n'; } > dt.cyr
check "file exceeds the old 64 KiB cap" 1 "$([ "$(wc -c < dt.cyr)" -gt 65536 ] && echo 1 || echo 0)"
CYRIUS_HOME="$D/home" "$CY" doctest dt.cyr > o5 2>&1; rc5=$?
check "both examples are run (2 total)" 1 "$(grep -c '^1 passed, 1 failed (2 total doc tests)' o5 || true)"
check "the failing example past the cut fails the run" 1 "$([ "$rc5" -ne 0 ] && echo 1 || echo 0)"
check "and is named by its line" 1 "$(grep -c 'FAIL: dt.cyr:1306 (expected 5, got 4)' o5 || true)"

# ── H6: only TOP-LEVEL fns. A fn inside `impl T for S { … }` is a method, emitted as
# `S_m`; reading it by its bare name printed `cyr_val new(cyr_val start, cyr_val step);`
# and `cyr_val new(cyr_val a, cyr_val b);` for tests/tcyr/frontend/method_dispatch.tcyr —
# conflicting prototypes for symbols that do not exist. Depth must come back to 0 after.
echo "H6 — impl methods get no prototype; depth recovers after the block:"
printf 'fn top(): i64 { return 1; }\nimpl Make for Counter {\n    fn new(start, step) { return start; }\n}\nimpl Make for Pair {\n    fn new(a, b) { return a; }\n}\nfn after(z): i64 { return z; }\n' > im.cyr
"$CY" header im.cyr > o6 2>&1
check "the top-level fn before the impls" 1 "$(has o6 'cyr_val top(void);')"
check "the top-level fn after the impls" 1 "$(has o6 'cyr_val after(cyr_val z);')"
check "no method prototype" 0 "$(grep -c ' new(' o6 || true)"
"$CY" header "$ROOT/tests/tcyr/frontend/method_dispatch.tcyr" > o6b 2>&1
check "method_dispatch.tcyr: no bare 'new' prototype" 0 "$(grep -c ' new(' o6b || true)"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: header-spellings-and-size — every public spelling, the private rule, whole-file read"
    exit 0
fi
echo "FAIL: header-spellings-and-size — $fails assertion(s) failed"
exit 1
