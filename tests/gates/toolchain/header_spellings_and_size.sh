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
#     bare fns) and caught in its review, never released. A fn inside `impl S { … }`
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
#
# 6.7.11 — THE RETURN TYPE (H7-H11; issues/archived/2026-10-10-cyrius-header-ignores-struct-returns.md,
# decision A, user 2026-10-13). The verb never read past the parameter list's `)`: a 9-16 B struct,
# a dyn and a two-value return (rax:rdx / x0:x1) and a >16 B struct (a hidden result pointer) all
# printed `cyr_val f(..)`. H7 the filed repro verbatim (and the `_WIN64` guard as cc -E reads it);
# H8 31 field shapes sized against `sizeof` compiled by build/cycc, then the class boundaries
# (3 / 8 B a word, 9 / 16 B the pair, 17 B three words) and a two-value return — cycc lands it in
# rax:rdx on x86_64 but x0:x2 on aarch64, so its cyr_val2 prototype is x86_64 SysV only (the
# guard read by cc -E and clang's aarch64 / Windows targets); H9 every refusal by name, rc 1; H10
# cc (and -D_WIN64) and clang's aarch64 / Windows / macOS targets read the headers; H11 a C caller
# links against the repro (`object;`) through the header, and the callee leaves the result
# pointer in rax; H11b a two-value return and a 17 B struct (the callee writes 3 whole words)
# read by a linked C caller. No cc: H7's guard rows, H10 and H11 SKIP by name (exit 77).
# 6.7.12 — EVERY LEG THAT DOES NOT RUN IS NAMED AND COUNTED (issues/2026-10-14-header-gate-skips-guard-
# and-c-caller-rows-silently.md). H8's guard rows and H11 / H11b need cc on x86_64; on a host with cc
# that is not x86_64 (aarch64 Linux, arm64 macOS) both were skipped with no line and the gate read
# PASS, and the no-clang line was named but never counted. Each now SKIPs by name and counts, so
# the gate exits 77 whenever a leg did not run. Rows (a fake `uname -m` printing aarch64 first on
# PATH, cc present; and a PATH without clang), under sh and bash -eo pipefail: the gate exits 77
# naming H8's guard rows and H11 (no clang: naming H8's clang guard rows and H10's cross-target
# rows). Mutation: the 6.7.11 gate under the same fake uname exits 0 with PASS, 6 rows unrun.
# 6.7.12 — H12, A `: stack` ENUM RETURN (issues/archived/2026-10-14-cyrius-header-stack-enum-return-prints-cyr-val.md,
# D23, the user 2026-10-15): `: Result` / `: Option` / `: Tagged` / an own `enum E: stack` return is
# cyr_val2 (tag w0, payload w1) under the x86_64 SysV guard — cycc lands the pair in x0:x2 on aarch64
# (pi and ecb: x1 0, x2 the payload) and rax:rdx on Win64 — and a word signature over a body that
# returns the pair (a constructor, or a pair fn of this file: a fixpoint) is refused by name, rc 1;
# cycc's own "bind both" refusal is the oracle for all 22 shapes; a C caller reads tag and payload.
#   the 6.7.11 header (no stack-enum class, no refusal)       → H12 FAIL (26 rows: every row but the words)
#   the stack-enum class dropped (Result/Option/Tagged a word)  → H12 FAIL (repro, process, shapes, own, guard, C)
#   the class under the pair's #ifndef _WIN64 (aarch64 kept)   → H12 FAIL (the guard, both aarch64 rows)
#   no propagation refusal                                     → H12 FAIL (the 10 refusals, count, prototypes)
#   one propagation round, in file order (no fixpoint)         → H12 FAIL (early, gw: callees defined below)
#   a closure's body not skipped                               → H12 FAIL (count, the word row, the oracle)
#   a nullary variant (None(), Vb()) counted as a pair         → H12 FAIL (count, the word row, the oracle)
# 6.7.13 — H12's `?` route (issues/archived/2026-10-15-cyrius-header-misses-a-pair-propagated-by-question-mark.md):
#   no `?` route (6.7.12's _hdr_body_pair)                     → H12 FAIL (9: the filed repro's 2, count, 5 refusal rows, the oracle)
#   an expression closure's body not skipped                   → H12 FAIL (count, the word row, the oracle)
#   the call's `)` found by _hdr_close (`<` a bracket)          → H12 FAIL (count, the qx row, the oracle)
#   the `?` route named as a `return` ('parse(..)')            → H12 FAIL (the filed repro and the 5 refusal rows)
# 6.7.13 — D37 (issues/archived/2026-10-15-6712-behaviour-changes-beyond-the-decisions-text.md item 2):
#   lib/result.cyr's ok_via / err_via back to `: i64`          → H12 FAIL (the result.cyr rows: rc 1, both prototypes)
# 6.7.14 — the same for lib/net.cyr (issues/2026-10-15-cyrius-header-net-sock-a-wrappers-print-cyr-val-over-a-pair.md):
#   lib/net.cyr's sock_send_a / sock_recv_a back to `: i64`     → H12 FAIL (both cyr_val2 rows, the copy row)
# MUTATION LEDGER (6.7.11; build/cyrius rebuilt from each mutant in a scratch tree, gate re-run):
#   _hdr_ret_of answers "a word" (the annotation ignored, as before)   → H7, H8, H9, H11 FAIL
#   a Str FIELD sized 16                                              → H8 FAIL (the shapes row)
#   u8 / u16 / u32 / f32 fields 8 bytes (the pre-6.7.10 layout)        → H8 FAIL
#   the pair prototype without its #ifndef _WIN64 arm                 → H7, H8, H10 FAIL
#   two values under the pair's #ifndef _WIN64 (aarch64 kept)          → H8 FAIL (the guard rows)
#   a type not declared in this file read as a word (fail-open)       → H9 FAIL
#   three values printed as the pair                                  → H9 FAIL
#   a struct body's #ifdef arms summed (the conditional not refused)   → H9 FAIL
#   newlines not skipped before the return's `:`                      → H8 FAIL (the ml row)
#   cyr_valN of floor(size / 8) words (17 B -> 2)                     → H8, H10, H11b FAIL
#   a union's fields summed                                           → H8 FAIL (the shapes row)
#   `Str` a word before the file's own struct Str is sized             → H8 FAIL (the str3 row)
#   a bare `Vec` field always the 8-byte handle (the review's find)   → H8 FAIL (the struct-Vec-above row)
#   a bare `Vec` the file's struct Vec in either order                → H8 FAIL (the struct-Vec-below row)
# 6.7.13 (D10 (b)): a struct Vec declared below the field sized 8 again → H8 FAIL (the refusal rows)
# 6.7.12 (D24): `_hdr_vec_name` → a word again (the 6.7.11 return)    → H8 FAIL (the 6 vector refusal rows)
# 6.7.13: `_hdr_vparam` answering 0 (a vector parameter `cyr_val`)     → H8 FAIL (7: the vector-parameter rows)
#         a `*` pointer type read as its vector name                 → H8 FAIL (the stays-cyr_val row, the count)
# 6.7.14 — H13, A WRAPPED PARAMETER LIST (issues/2026-10-15-cyrius-header-multi-line-parameter-list-keeps-first-line-only.md):
#   the list's `)` looked for on the declaration's line (6.7.13)     → H13 FAIL (8: ml.cyr's b3 / a3, the nine, the shapes, cc)
#   the parameter walk skips spaces alone (a newline is a name)     → H13 FAIL (7)
#   the trailing trim drops spaces alone (a newline before `,`)     → H13 FAIL (the comments row)
#   _hdr_only_ellipsis blind to newlines (a wrapped `...` alone)    → H13 FAIL (the variadic row, cc)
#   an empty list only when `(` meets `)` (`fn e0(` / `)` → `e0()`) → H13 FAIL (the (void) row)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: header_spellings_and_size: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0
skips=0
# H8's guard rows and H11 / H11b need cc on x86_64 (the one host whose cc runs SysV x86_64 and
# whose cycc emits a linkable `object;`); off it, each SKIPs by name, with the reason. CHANGELOG [6.7.12]
CCX86=0
if ! command -v cc > /dev/null 2>&1; then CCX86_WHY="no C compiler (cc) on this host"
elif [ "$(uname -m)" != x86_64 ]; then CCX86_WHY="needs cc on x86_64; this host is $(uname -m)"
else CCX86=1; CCX86_WHY=""; fi

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
rc1=0; "$CY" header s.cyr > o1 2>&1 || rc1=$?
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
rc3=0; "$CY" header big.cyr > o3 2>&1 || rc3=$?
check "exit 0" 0 "$rc3"
check "the fn before the cut" 1 "$(has o3 'cyr_val early(void);')"
check "the fn AFTER the cut" 1 "$(has o3 'cyr_val late(cyr_val z);')"

# ── H4: an unreadable file is an error, not an empty header.
echo "H4 — a missing file fails:"
rc4=0; "$CY" header no_such_file.cyr > o4 2>&1 || rc4=$?
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
rc5=0; CYRIUS_HOME="$D/home" "$CY" doctest dt.cyr > o5 2>&1 || rc5=$?
check "both examples are run (2 total)" 1 "$(grep -c '^1 passed, 1 failed (2 total doc tests)' o5 || true)"
check "the failing example past the cut fails the run" 1 "$([ "$rc5" -ne 0 ] && echo 1 || echo 0)"
check "and is named by its line" 1 "$(grep -c 'FAIL: dt.cyr:1306 (expected 5, got 4)' o5 || true)"

# ── H6: only TOP-LEVEL fns. A fn inside `impl S { … }` is a method, emitted as
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

# ── H7-H11 (6.7.11): THE RETURN TYPE. cmd_header never read past the parameter list's `)`, so a
# fn returning a struct printed `cyr_val f(..)` like a word: a 9-16 B struct, a dyn and a
# two-value return come back in rax:rdx (C read rax alone: a dyn lost its vtable), and over 16 B
# through a hidden result pointer (the prototype's first `cyr_val` landed in the callee's
# result slot). The user's decision (2026-10-13): model the ABI — the pair is `cyr_val2` under
# `#ifndef _WIN64` (Win64 C returns 16 B through a hidden pointer: a named comment there, no
# prototype), over 16 B a `cyr_valN` of N words returned by value; refuse by name (stderr, rc 1)
# what the scanner cannot size. docs/development/issues/archived/2026-10-10-cyrius-header-ignores-struct-returns.md
REPRO="$ROOT/docs/development/issues/repros/2026-10-10-cyrius-header-ignores-struct-returns.cyr"
echo "H7 — the filed repro, verbatim:"
rc7=0; "$CY" header "$REPRO" > o7 2> e7 || rc7=$?
check "exit 0" 0 "$rc7"
check "mkq (16 B) is cyr_val2" 1 "$(has o7 'cyr_val2 mkq(cyr_val a, cyr_val b);   /* returns Q, 16 B */')"
check "mkr (24 B) is cyr_val3, returned by value" 1 "$(has o7 'cyr_val3 mkr(cyr_val a);   /* returns R, 24 B */')"
check "mkd (a dyn) is cyr_val2" 1 "$(has o7 'cyr_val2 mkd(cyr_val p);   /* returns dyn Show, 16 B */')"
check "plain unchanged" 1 "$(has o7 'cyr_val plain(cyr_val a);')"
check "the cyr_val2 typedef, once" 1 "$(has o7 'typedef struct { int64_t w0, w1; } cyr_val2;')"
check "the cyr_val3 typedef, once" 1 "$(has o7 'typedef struct { int64_t w[3]; } cyr_val3;')"
check "a named Win64 comment for mkq and for mkd" 2 "$(grep -cE '^/\* (mkq|mkd): no prototype on Win64 -- cycc returns its (Q|dyn Show) in rax:rdx' o7 || true)"
check "nothing on stderr" 0 "$(wc -c < e7 | tr -d ' ')"
# The guard, as a C preprocessor reads it (cc when present; the SKIP is named in H10).
if command -v cc > /dev/null 2>&1; then
    protos() { cc -E -P -x c "$@" o7 2> /dev/null | grep -oE '(mkq|mkr|mkd|plain)\(' | tr -d '(' | sort | paste -sd' ' -; }
    check "SysV / AAPCS64 (no _WIN64): all four prototypes" "mkd mkq mkr plain" "$(protos)"
    check "Win64 (-D_WIN64): no mkq / mkd, the by-value mkr and plain kept" "mkr plain" "$(protos -D_WIN64)"
fi

# ── H8: the scanner's struct sizes ARE the compiler's. Every field shape is padded with two
# untyped fields (so each struct is over 16 B and its header line names its size) and the size
# the header prints is compared with `sizeof` compiled by build/cycc. Then the class boundaries.
echo "H8 — every field shape sized as the compiler sizes it; the class boundaries:"
SHAPES='f;|f: i8;|f: u8;|f: i16;|f: u16;|f: i32;|f: u32;|f: f32;|f: i64;|f: u64;|f: f64;|f: bool;|f: cstring;|f: Str;|f: Option;|f: Result;|f: Tagged;|f: *Q3;|f: **u8;|f: *Box<i64>;|f: Vec<i64>;|f: Vec;|f: E;|f: Q3;|f: R24;|f: UU;|f: (i64, i64);|f: (i64, f64, bool);|f: dyn Show;|a: u8 b: u16 c: u32 d: f32|x: Q3; y: C2;'
{ echo 'include "lib/str.cyr"'
  echo 'include "lib/vec.cyr"'
  echo 'struct Q3 { a: u8; b: u8; c: u8; }'
  echo 'struct R24 { a; b; c; }'
  echo 'struct C2 { a: i8; b: u8; }'
  echo 'union UU { a: u8; b: u32; c: f32; }'
  echo 'struct Box<T> { v: T; }'
  echo 'trait Show { fn show(self): i64; }'
  k=0; IFS='|'; for sh in $SHAPES; do k=$((k + 1)); echo "struct Z$k { $sh p1; p2; }"; done; unset IFS
  echo 'enum E { EA; EB; }'; } > sz.cyr
nshapes=$(echo "$SHAPES" | tr '|' '\n' | wc -l | tr -d ' ')
cp sz.cyr szh.cyr
k=0; while [ "$k" -lt "$nshapes" ]; do k=$((k + 1)); echo "fn rz$k(): Z$k { var z: Z$k; return z; }" >> szh.cyr; done
# The compiler's sizes: one probe printing sizeof(Zk) per line.
{ cat sz.cyr
  echo 'fn pz(n): i64 { var d[24]; var i = 22; store8(&d + 23, 10); if (n == 0) { store8(&d + i, 48); i = i - 1; } while (n > 0) { store8(&d + i, 48 + n % 10); n = n / 10; i = i - 1; } syscall(1, 1, &d + i + 1, 23 - i); return 0; }'
  k=0; while [ "$k" -lt "$nshapes" ]; do k=$((k + 1)); echo "pz(sizeof(Z$k));"; done
  echo 'syscall(60, 0);'; } > szp.cyr
{ (cd "$ROOT" && "$ROOT/build/cycc" < "$D/szp.cyr" > "$D/szp" 2> "$D/szp.err") && chmod +x szp && ./szp > sz.cc 2> /dev/null; } || :
check "the compiler sized every shape (the probe compiled and ran)" "$nshapes" "$(grep -c . sz.cc 2> /dev/null || echo 0)"
rc8=0; "$CY" header szh.cyr > o8 2> e8 || rc8=$?
check "exit 0 (every shape sizable)" 0 "$rc8"
k=0; bad=""; while [ "$k" -lt "$nshapes" ]; do
    k=$((k + 1))
    want=$(sed -n "${k}p" sz.cc)
    got=$({ grep -oE "rz$k\\(void\\);   /\\* returns Z$k, [0-9]+ B" o8 || :; } | { grep -oE '[0-9]+ B$' || :; } | tr -d ' B')
    [ "$got" = "$want" ] || bad="$bad Z$k[$(echo "$SHAPES" | cut -d'|' -f$k)]:header=${got:-none},cycc=$want"
done
check "each of the $nshapes shapes: the header's size == cycc's sizeof" "" "$bad"
printf '%s\n' 'struct C3 { r: u8; g: u8; b: u8; }' 'struct B8 { a: u8; b: u8; c: u8; d: u8; e: u32; }' \
  'struct B9 { a: u8; b: i64; }' 'struct B16 { a; b; }' 'struct B17 { a: u8; b; c; }' 'union UU { a: u8; b: u32; }' \
  'fn rc3(): C3 { var z = C3 { 1, 2, 3 }; return z; }' 'fn rb8(): B8 { var z: B8; return z; }' \
  'fn rb9(): B9 { var z: B9; return z; }' 'fn rb16(): B16 { var z: B16; return z; }' \
  'fn rb17(): B17 { var z: B17; return z; }' 'fn ruu(): UU { var z: UU; return z; }' \
  'fn rs(): Str { return 0; }' 'fn rp(): *B17 { return 0; }' 'fn ri(): i32 { return 1; }' 'fn rf(): f64 { return 0; }' \
  'fn rt(): (i64, f64) { return (1, 2); }' 'fn rfw(): FW { var z: FW; return z; }' \
  'fn ml(a)' '    : B16 { var z: B16; return z; }' \
  'struct FW { a; b; c; d; }' > cls.cyr
rc8b=0; "$CY" header cls.cyr > o8b 2> e8b || rc8b=$?
check "boundaries: exit 0" 0 "$rc8b"
check "a packed 3 B u8 struct stays cyr_val" 1 "$(has o8b 'cyr_val rc3(void);')"
check "8 B stays cyr_val" 1 "$(has o8b 'cyr_val rb8(void);')"
check "9 B (packed u8 + i64) is cyr_val2" 1 "$(has o8b 'cyr_val2 rb9(void);   /* returns B9, 9 B */')"
check "16 B is cyr_val2" 1 "$(has o8b 'cyr_val2 rb16(void);   /* returns B16, 16 B */')"
check "17 B is cyr_val3 — the callee writes three whole words" 1 "$(has o8b 'cyr_val3 rb17(void);   /* returns B17, 17 B, the callee writes 3 words */')"
check "a 4 B union stays cyr_val" 1 "$(has o8b 'cyr_val ruu(void);')"
check "Str (a 16-byte handle) stays cyr_val" 1 "$(has o8b 'cyr_val rs(void);')"
check "a pointer, an i32 and an f64 stay cyr_val" 3 "$(grep -cxE 'cyr_val (rp|ri|rf)\(void\);' o8b || true)"
check "a two-value return is cyr_val2" 1 "$(has o8b 'cyr_val2 rt(void);   /* returns (i64, f64), 16 B */')"
check "... under the x86_64 SysV guard (aarch64 lands it in x0:x2)" 1 "$(grep -B1 -xF 'cyr_val2 rt(void);   /* returns (i64, f64), 16 B */' o8b | grep -cxF '#if defined(__x86_64__) && !defined(_WIN64)' || true)"
check "... and a named comment in its other arm" 1 "$(grep -cF '/* rt: no prototype here -- cycc returns its (i64, f64) in x0:x2 on aarch64 (AAPCS64 C reads x0:x1), in rax:rdx on Win64' o8b || true)"
# The guards as each target's preprocessor reads them: the pair (rb16) everywhere but Win64, the
# two values (rt) on x86_64 SysV alone. cc is the host (x86_64 here); clang names the others.
if [ "$CCX86" = 1 ]; then
    p8() { "$@" -E -P -x c o8b 2> /dev/null | grep -oE ' (rb16|rt)\(' | tr -d ' (' | sort | paste -sd' ' -; }
    check "x86_64 SysV (cc): rb16 and rt" "rb16 rt" "$(p8 cc)"
    if command -v clang > /dev/null 2>&1; then
        check "aarch64 (clang): rb16 alone" "rb16" "$(p8 clang --target=aarch64-linux-gnu -ffreestanding)"
        check "aarch64 macOS (clang): rb16 alone" "rb16" "$(p8 clang --target=aarch64-apple-darwin -ffreestanding)"
        check "Win64 (clang): neither" "" "$(p8 clang --target=x86_64-w64-windows-gnu -ffreestanding)"
    fi
else
    echo "  SKIP (named): H8's guard rows — $CCX86_WHY"; skips=$((skips + 1))
fi
check "a struct declared after the fn is sized (the whole file is read)" 1 "$(has o8b 'cyr_val4 rfw(void);   /* returns FW, 32 B */')"
check "a return annotation on the line after the list's ')'" 1 "$(has o8b 'cyr_val2 ml(cyr_val a);   /* returns B16, 16 B */')"
# 6.7.12 (D24, the user 2026-10-15): a SIMD vector return is REFUSED by name — it printed `cyr_val`
# (C reads rax / x0; cycc returns a vector elsewhere, by width and target), and no C11 return type
# carries one. The filed repro verbatim (issues/archived/2026-10-14-cyrius-header-vector-return-prints-cyr-val.md),
# then every one of the twelve vector names. Mutation: the 6.7.11 word restored → these rows RED.
printf '%s\n' 'fn rv2(a): f64v2 { var v: f64v2; return v; }' 'fn rv4(): f64v4 { var v: f64v4; return v; }' \
  'fn ri4(): i32v4 { var v: i32v4; return v; }' > vec.cyr
(cd "$ROOT" && "$ROOT/build/cycc" < "$D/vec.cyr" > "$D/vec.bin" 2> /dev/null) && vrc=0 || vrc=$?
check "the filed vec.cyr builds with cycc" 0 "$vrc"
rcv=0; "$CY" header vec.cyr > o8v 2> e8v || rcv=$?
check "vector returns: exit 1" 1 "$rcv"
for vt in rv2:f64v2 rv4:f64v4 ri4:i32v4; do
    check "'${vt%%:*}' (${vt#*:}) refused by name" 1 "$(grep -cxF "error: cyrius header: '${vt%%:*}' returns '${vt#*:}': a SIMD vector return, which no C11 return type carries; no prototype written" e8v || true)"
done
check "no prototype for a vector return, the header still closes" "0 1" "$(grep -cE '(rv2|rv4|ri4)\(' o8v || true) $(has o8v '#endif /* CYRIUS_FFI_H */')"
: > v12.cyr; for vt in f64v2 f64v4 f32v4 f32v8 i32v4 u32v4 i16v8 u16v8 i64v2 u64v2 i8v16 u8v16; do echo "fn r_$vt(): $vt { var v: $vt; return v; }" >> v12.cyr; done
echo 'fn keep(a): i64 { return a; }' >> v12.cyr
rcv12=0; "$CY" header v12.cyr > o8w 2> e8w || rcv12=$?
check "all twelve vector types refused, a scalar fn beside them kept, exit 1" "12 1 1" "$(grep -c "returns '[a-z0-9]*': a SIMD vector return, which no C11 return type carries; no prototype written" e8w || true) $(has o8w 'cyr_val keep(cyr_val a);') $rcv12"
# 6.7.13: a SIMD vector PARAMETER is refused the same way — cycc receives it in xmm / v, the
# prototype said `cyr_val v` (C passes it in rdi / x0). The filed repro verbatim
# (issues/archived/2026-10-15-cyrius-header-vector-parameter-prints-cyr-val.md), then f64v4 / i32v4 and a
# vector second; a `: Result` / `: Option` parameter (one word, its tag) and a `*f64v2` (a
# pointer) stay `cyr_val`. Mutation: `_hdr_vparam` answering 0 (6.7.12) → these rows RED.
printf 'fn pv(v: f64v2): i64 { return 0; }\nfn pr(r: Result): i64 { return r; }\n' > pv.cyr
rcp=0; "$CY" header pv.cyr > o8p 2> e8p || rcp=$?
check "the filed pv.cyr: pv refused by name, exit 1" "1 1" \
    "$(grep -cxF "error: cyrius header: 'pv' takes 'v: f64v2': a SIMD vector parameter, which no C11 type carries; no prototype written" e8p || true) $rcp"
check "... no pv prototype; pr (: Result) stays cyr_val; the header closes" "0 1 1" \
    "$(grep -c 'pv(' o8p || true) $(has o8p 'cyr_val pr(cyr_val r);') $(has o8p '#endif /* CYRIUS_FFI_H */')"
printf '%s\n' 'include "lib/tagged.cyr"' 'fn p4(v: f64v4): i64 { return 0; }' 'fn pi4(v: i32v4, x): i64 { return x; }' \
  'fn pm(a, w :f64v2, b = 2): i64 { return a + b; }' 'fn po(o: Option, t: Tagged): i64 { return o; }' \
  'fn pp(v: *f64v2): i64 { return v; }' 'fn pd(a: f64, n: i64): i64 { return n; }' > vp.cyr
(cd "$ROOT" && "$ROOT/build/cycc" < "$D/vp.cyr" > "$D/vp.bin" 2> /dev/null) && vprc=0 || vprc=$?
check "vp.cyr builds with cycc" 0 "$vprc"
rcvp=0; "$CY" header vp.cyr > o8q 2> e8q || rcvp=$?
check "vector parameters: exit 1, three refusals" "1 3" "$rcvp $(grep -c '^error: ' e8q || true)"
for vt in 'p4:v: f64v4' 'pi4:v: i32v4' 'pm:w :f64v2'; do
    check "'${vt%%:*}' ('${vt#*:}') refused by name" 1 "$(grep -cxF "error: cyrius header: '${vt%%:*}' takes '${vt#*:}': a SIMD vector parameter, which no C11 type carries; no prototype written" e8q || true)"
done
check "no prototype for a refused fn" 0 "$(grep -cE '(p4|pi4|pm)\(' o8q || true)"
check "Option / Tagged parameters, a *f64v2 and scalars stay cyr_val" "1 1 1" \
    "$(has o8q 'cyr_val po(cyr_val o, cyr_val t);') $(has o8q 'cyr_val pp(cyr_val v);') $(has o8q 'cyr_val pd(cyr_val a, cyr_val n);')"
printf '%s\n' 'struct Str { a; b; c; }' 'fn rs3(): Str { var z: Str; return z; }' > str3.cyr
"$CY" header str3.cyr > o8c 2>&1 || :
check "a file's own 24 B struct Str: the result pointer (Str's word is the 9-16 B band alone)" 1 "$(has o8c 'cyr_val3 rs3(void);   /* returns Str, 24 B */')"
# A bare `Vec` field is the file's own `struct Vec` when one is declared ABOVE the field (the
# compiler's FINDSTRUCT), the 8-byte handle when the file has none, and refused by name when the
# file's struct Vec is declared BELOW it — cycc refuses that order since 6.7.13 (D10 (b), the user
# 2026-10-15; it was silently the handle, 24 B here), so the header names it and guesses no size.
# Mutation: `_hdr_type_size`'s below arm back to `return 8` -> the refusal rows RED.
printf '%s\n' 'struct VB { v: Vec; p1; p2; }' 'struct Vec { a; b; c; }' 'struct VA { v: Vec; p1; p2; }' > vo.cyr
{ cat vo.cyr
  echo 'fn pz(n): i64 { var d[24]; var i = 22; store8(&d + 23, 10); if (n == 0) { store8(&d + i, 48); i = i - 1; } while (n > 0) { store8(&d + i, 48 + n % 10); n = n / 10; i = i - 1; } syscall(1, 1, &d + i + 1, 23 - i); return 0; }'
  echo 'pz(sizeof(VA)); syscall(60, 0);'; } > vop.cyr
rcvo=0; (cd "$ROOT" && "$ROOT/build/cycc" < "$D/vop.cyr" > "$D/vop" 2> "$D/vop.err") || rcvo=$?
check "cycc refuses the field whose struct Vec is declared below it, by name, once" "1 1 1" \
    "$rcvo $(grep -c "^error:<source>:1:19: struct field type 'Vec' is declared after its use; declare it before 'VB'" vop.err || true) $(grep -c '^error' vop.err || true)"
grep -v 'struct VB' vop.cyr > vopa.cyr
{ (cd "$ROOT" && "$ROOT/build/cycc" < "$D/vopa.cyr" > "$D/vopa" 2> /dev/null) && chmod +x vopa && ./vopa > vo.cc 2> /dev/null; } || :
check "cycc's sizeof: struct Vec above the field 40 B" "40" "$(paste -sd' ' vo.cc 2> /dev/null)"
printf '%s\n' 'fn rva(): VA { var z: VA; return z; }' 'fn rvb(): VB { var z: VB; return z; }' >> vo.cyr
rc8d=0; "$CY" header vo.cyr > o8d 2> e8d || rc8d=$?
check "a bare Vec field with the file's own struct Vec declared above: that struct (40 B, cyr_val5)" 1 "$(has o8d 'cyr_val5 rva(void);   /* returns VA, 40 B */')"
check "... declared below the field: refused by name, no prototype, exit 1" "1 0 1" \
    "$(grep -cxF "error: cyrius header: 'rvb' returns 'VB': its field type 'Vec' is the file's own struct Vec declared below its use, which cycc refuses; no prototype written" e8d || true) $(grep -c 'rvb(' o8d || true) $rc8d"
printf '%s\n' 'struct VN { v: Vec; p1; p2; }' 'fn rvn(): VN { var z: VN; return z; }' 'enum Vec { VX; }' > von.cyr
"$CY" header von.cyr > o8n 2>&1 || :
check "no struct Vec of the file's own (an enum Vec below): the 8-byte handle (24 B, cyr_val3)" 1 "$(has o8n 'cyr_val3 rvn(void);   /* returns VN, 24 B */')"
check "each typedef once (cyr_val2, cyr_val3, cyr_val4)" "1 1 1" \
    "$(grep -c 'cyr_val2;$' o8b) $(grep -c '} cyr_val3;$' o8b) $(grep -c '} cyr_val4;$' o8b)"

# ── H9: what the scanner cannot size is REFUSED by name — never guessed.
echo "H9 — refused by name, rc 1, no prototype; the rest still written:"
printf '%s\n' 'struct Box<T> { v: T; }' 'struct WB { b: Box<i64>; x; }' 'struct WX { e: Ext; f; }' \
  '#ifdef SOMEWHERE' 'struct D { a; b; c; }' '#else' 'struct D { a; }' '#endif' \
  'fn gb(): Box<i64> { var z: Box<i64>; return z; }' 'fn gbb(): Box { return 0; }' 'fn ext(a): Ext { return a; }' \
  'fn wb(): WB { var z: WB; return z; }' 'fn wx(): WX { var z: WX; return z; }' \
  'fn t3(): (i64, i64, i64) { return (1, 2, 3); }' 'fn rd(): D { var z: D; return z; }' 'fn fine(a): i64 { return a; }' \
  'struct CB {' '    a;' '#ifdef CYRIUS_TARGET_WIN' '    b; c;' '#else' '    b;' '#endif' '}' 'fn rcb(): CB { var z: CB; return z; }' > rf.cyr
rc9=0; "$CY" header rf.cyr > o9 2> e9 || rc9=$?
check "exit 1" 1 "$rc9"
check "a generic struct instance" 1 "$(grep -cxF "error: cyrius header: 'gb' returns 'Box<i64>': a generic struct instance, which this scanner cannot size; no prototype written" e9 || true)"
check "a generic struct" 1 "$(grep -cxF "error: cyrius header: 'gbb' returns 'Box': a generic struct, which this scanner cannot size; no prototype written" e9 || true)"
check "a struct not declared in this file" 1 "$(grep -cxF "error: cyrius header: 'ext' returns 'Ext': a type not declared in this file, which this scanner cannot size; no prototype written" e9 || true)"
check "a struct holding a generic instance names the field type" 1 "$(grep -cxF "error: cyrius header: 'wb' returns 'WB': its field type 'Box<i64>' is a generic struct instance, which this scanner cannot size; no prototype written" e9 || true)"
check "a struct holding another file's type names it" 1 "$(grep -cxF "error: cyrius header: 'wx' returns 'WX': its field type 'Ext' is a type not declared in this file, which this scanner cannot size; no prototype written" e9 || true)"
check "three values (rax:rdx:r8)" 1 "$(grep -cxF "error: cyrius header: 't3' returns '(i64, i64, i64)': three values, returned in rax:rdx:r8 (aarch64 x0:x2:x3), which no C return type carries; no prototype written" e9 || true)"
check "a struct declared twice (two #ifdef arms)" 1 "$(grep -cxF "error: cyrius header: 'rd' returns 'D': declared more than once in this file, which this scanner cannot size; no prototype written" e9 || true)"
check "a struct whose fields sit under #ifdef" 1 "$(grep -cxF "error: cyrius header: 'rcb' returns 'CB': a struct whose fields sit under a preprocessor conditional, which this scanner cannot size; no prototype written" e9 || true)"
check "exactly those 8 refusals" 8 "$(grep -c '^error: ' e9 || true)"
check "no prototype for a refused fn" 0 "$(grep -cE '(gb|gbb|ext|wb|wx|t3|rd|rcb)\(' o9 || true)"
check "the rest is written and the header closes" "1 1" "$(has o9 'cyr_val fine(cyr_val a);') $(has o9 '#endif /* CYRIUS_FFI_H */')"

# ── H10: the headers are C. cc (the host), the Win64 arm (-D_WIN64), and — when clang is here —
# the aarch64 Linux / Windows / macOS targets (freestanding: <stdint.h> only).
echo "H10 — the generated headers compile as C:"
if command -v cc > /dev/null 2>&1; then
    for f in o7 o8 o8b o8p o8q o9; do
        check "$f: cc -std=c11 -pedantic-errors" 0 "$(cc -std=c11 -pedantic-errors -fsyntax-only -x c "$f" > /dev/null 2>&1; echo $?)"
        check "$f: the same with -D_WIN64" 0 "$(cc -std=c11 -pedantic-errors -fsyntax-only -D_WIN64 -x c "$f" > /dev/null 2>&1; echo $?)"
    done
else
    echo "  SKIP (named): H7's guard rows, H10 and H11 — no C compiler (cc) on this host"; skips=$((skips + 1))
fi
if command -v clang > /dev/null 2>&1; then
    for tg in aarch64-linux-gnu x86_64-w64-windows-gnu aarch64-apple-darwin; do
        check "o7 + o8b: clang --target=$tg" 0 "$(clang --target=$tg -ffreestanding -std=c11 -pedantic-errors -fsyntax-only -x c o7 > /dev/null 2>&1 && clang --target=$tg -ffreestanding -std=c11 -pedantic-errors -fsyntax-only -x c o8b > /dev/null 2>&1; echo $?)"
    done
else
    echo "  SKIP (named): H8's clang guard rows and H10's cross-target rows — no clang on this host"; skips=$((skips + 1))
fi

# ── H11: a real C caller, through the header, on x86_64 Linux (the one target whose cycc emits a
# linkable object: `object;`). The repro is compiled verbatim behind `object;`, a C main calls it
# through the generated header, and an asm probe checks the SysV rule the by-value large return
# rests on: the callee leaves the result pointer in rax.
echo "H11 — a C caller links against the repro and reads every value:"
if [ "$CCX86" = 1 ]; then
    cp o7 ffi.h
    { echo 'object;'; cat "$REPRO"; } > lib.cyr
    (cd "$ROOT" && "$ROOT/build/cycc" < "$D/lib.cyr" > "$D/lib.o" 2> /dev/null) || :
    cat > caller.c <<'CEOF'
#include <stdio.h>
#include "ffi.h"
extern void _cyrius_init(void);
__attribute__((noinline)) static long mkr_rax(void *buf, long a) {
    long rax;
    __asm__ volatile("call mkr" : "=a"(rax), "+D"(buf), "+S"(a)
                     : : "rcx", "rdx", "r8", "r9", "r10", "r11", "memory", "cc");
    return rax;
}
int main(void) {
    _cyrius_init();
    int64_t q[2] = {5, 6};
    cyr_val2 a = mkq(11, 22);
    cyr_val3 r = mkr(33);
    cyr_val2 d = mkd((cyr_val)q);
    cyr_val (*show)(cyr_val) = (cyr_val (*)(cyr_val))(*(int64_t *)d.w1);
    cyr_val3 r2;
    long rax = mkr_rax(&r2, 9);
    printf("%ld %ld|%ld %ld %ld|%d %ld|%ld|%d %ld\n", (long)a.w0, (long)a.w1, (long)r.w[0], (long)r.w[1],
           (long)r.w[2], d.w0 == (cyr_val)q, (long)show(d.w0), (long)plain(44), rax == (long)&r2, (long)r2.w[2]);
    return 0;
}
CEOF
    if cc -std=c11 -O1 -mno-red-zone caller.c lib.o -I. -o caller > cc11.err 2>&1; then
        check "mkq 11 22 | mkr 33 x3 | mkd's data word and its vtable's show() | plain | rax = the result pointer" \
            "11 22|33 33 33|1 5|44|1 9" "$(./caller 2>&1)"
    else
        check "the C caller compiles and links against the repro object" 0 1; sed 's/^/    /' cc11.err | head -5
    fi
    # H11b — the two-value return (x86_64 SysV's pair) and a 17 B struct: the callee writes three
    # whole words through the result pointer (bytes 17-23 overwritten), so C's cyr_val3 (24 B) is
    # the buffer it needs — a 17-byte one would be overrun; the word past 24 B is untouched.
    printf '%s\n' 'object;' 'struct B17 { a: u8; b; c; }' \
      'fn rt(a): (i64, i64) { return (a + 1, a + 2); }' 'fn rtf(a): (f64, i64) { return (f64_from(a), a); }' \
      'fn rb17(x): B17 { var z: B17; z.a = 7; z.b = x; z.c = x + 1; return z; }' > lib2.cyr
    (cd "$ROOT" && "$ROOT/build/cycc" < "$D/lib2.cyr" > "$D/lib2.o" 2> /dev/null) || :
    "$CY" header lib2.cyr > ffi2.h 2> /dev/null || :
    cat > caller2.c <<'CEOF'
#include <stdio.h>
#include <string.h>
#include "ffi2.h"
extern void _cyrius_init(void);
/* The result pointer handed over explicitly (C may pass a temporary): what the callee writes. */
__attribute__((noinline)) static void rb17_into(void *buf, long x) {
    __asm__ volatile("call rb17" : "+D"(buf), "+S"(x)
                     : : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "memory", "cc");
}
int main(void) {
    _cyrius_init();
    cyr_val2 t = rt(40);
    cyr_val2 tf = rtf(3);
    double d; memcpy(&d, &tf.w0, 8);
    cyr_val3 r = rb17(100);
    unsigned char *b = (unsigned char *)&r;
    int64_t w1, w2; memcpy(&w1, b + 1, 8); memcpy(&w2, b + 9, 8);
    struct { cyr_val3 r; int64_t guard; } g;
    memset(&g, 0x5a, sizeof g);
    rb17_into(&g.r, 9);
    unsigned char *gb = (unsigned char *)&g.r;
    /* bytes 17-23 hold the callee's last word's tail (frame bytes, not the 0x5a fill) */
    int tail = 0; for (int i = 17; i < 24; i++) { if (gb[i] != 0x5a) tail = 1; }
    printf("%ld %ld|%g %ld|%d %ld %ld|%d %d\n", (long)t.w0, (long)t.w1, d, (long)tf.w1,
           b[0], (long)w1, (long)w2, tail, g.guard == 0x5a5a5a5a5a5a5a5aLL);
    return 0;
}
CEOF
    if cc -std=c11 -O1 -mno-red-zone caller2.c lib2.o -I. -o caller2 > cc11b.err 2>&1; then
        check "H11b: rt 41 42 | rtf 3.0 (rax's f64 bits) 3 | rb17's fields | bytes 17-23 written, the word past 24 untouched" \
            "41 42|3 3|7 100 101|1 1" "$(./caller2 2>&1)"
    else
        check "H11b: the C caller compiles and links against lib2's object" 0 1; sed 's/^/    /' cc11b.err | head -5
    fi
elif command -v cc > /dev/null 2>&1; then   # no cc at all: H11 is named in H10's SKIP line above
    echo "  SKIP (named): H11 / H11b — $CCX86_WHY"; skips=$((skips + 1))
fi
# ── H12 (6.7.12, D23 — the user, 2026-10-15): A `: stack` ENUM RETURN. A payload constructor of a
# `: stack` enum (Ok / Err / Some / Left / Right, a file's own `enum E: stack { V(x); }`) returns a
# (tag, payload) pair — rax:rdx on x86_64 (SysV and Win64), x0:x2 on aarch64 (measured on pi and
# ecb: x1 is 0, x2 the payload) — and the header printed `cyr_val parse(..)`, so a C caller read
# the tag alone. An annotated `: Result` / `: Option` / `: Tagged` (or own stack enum) return is
# now cyr_val2 (tag w0, payload w1) under the x86_64 SysV guard, a named comment elsewhere; a fn
# whose signature says a word (none, or `: i64`) but whose body returns the pair — a constructor,
# or a call of a pair fn of this file (a fixpoint) — is REFUSED by name, rc 1.
# issues/archived/2026-10-14-cyrius-header-stack-enum-return-prints-cyr-val.md
echo "H12 — a \`: stack\` enum's pair: modelled when annotated, refused by name when propagated:"
printf '%s\n' 'include "lib/result.cyr"' 'fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }' > se.cyr
rc12=0; "$CY" header se.cyr > o12 2> e12 || rc12=$?
check "the filed repro: exit 0, nothing on stderr" "0 0" "$rc12 $(wc -c < e12 | tr -d ' ')"
check "parse is cyr_val2, the tag in w0 and the payload in w1" 1 "$(has o12 'cyr_val2 parse(cyr_val x);   /* returns Result: the tag in w0, the payload in w1 */')"
check "... under the x86_64 SysV guard" 1 "$(grep -B1 -xF 'cyr_val2 parse(cyr_val x);   /* returns Result: the tag in w0, the payload in w1 */' o12 | grep -cxF '#if defined(__x86_64__) && !defined(_WIN64)' || true)"
check "... and a named comment in its other arm" 1 "$(has o12 '/* parse: no prototype here -- cycc returns its Result (tag, payload) in x0:x2 on aarch64 (AAPCS64 C reads x0:x1), in rax:rdx on Win64 (C passes a hidden result pointer) */')"
"$CY" header "$ROOT/lib/process.cyr" > o12p 2> e12p || :
for fnp in 'run(cyr_val cmd, cyr_val arg1, cyr_val arg2)' 'run_capture(cyr_val cmd, cyr_val arg1, cyr_val arg2, cyr_val buf, cyr_val buflen)' \
           'spawn(cyr_val cmd, cyr_val arg1, cyr_val arg2)' 'wait_pid(cyr_val pid)'; do
    check "lib/process.cyr: ${fnp%%(*} (: Result) is cyr_val2" 1 "$(has o12p "cyr_val2 $fnp;   /* returns Result: the tag in w0, the payload in w1 */")"
done
check "lib/process.cyr: no refusal" 0 "$(wc -c < e12p | tr -d ' ')"
# 6.7.13 (D37 — the user, 2026-10-15: keep D23's reach, and re-annotate lib/result.cyr's wrappers):
# ok_via / err_via are declared `: Result`, what their bodies return, so cyrius's own lib clears its
# own verb — rc 0, both cyr_val2 — and a caller compiles byte-identical to the 6.7.12 `: i64`
# spelling (a copy of lib/ with the two signatures put back), the differential that proved it.
rcv=0; "$CY" header "$ROOT/lib/result.cyr" > o12v 2> e12v || rcv=$?
check "lib/result.cyr: exit 0, nothing on stderr (D37)" "0 0" "$rcv $(wc -c < e12v | tr -d ' ')"
for fnp in 'ok_via(cyr_val a, cyr_val v)' 'err_via(cyr_val a, cyr_val e)'; do
    check "lib/result.cyr: ${fnp%%(*} (: Result) is cyr_val2" 1 "$(has o12v "cyr_val2 $fnp;   /* returns Result: the tag in w0, the payload in w1 */")"
done
mkdir old && cp -R "$ROOT/lib" old/lib
sed -e 's/^fn ok_via(a, v): Result {$/fn ok_via(a, v): i64 {/' -e 's/^fn err_via(a, e): Result {$/fn err_via(a, e): i64 {/' \
    "$ROOT/lib/result.cyr" > old/lib/result.cyr
check "the 6.7.12 copy differs from lib/result.cyr in the two signatures alone" 2 "$(diff "$ROOT/lib/result.cyr" old/lib/result.cyr | grep -c '^> fn [a-z_]*(a, [ve]): i64 {$' || true)"
cp "$ROOT/tests/tcyr/stdlib/result_allocator_via.tcyr" via.tcyr
vrc=0; (cd "$ROOT" && "$ROOT/build/cycc" < "$D/via.tcyr" > "$D/via_new" 2> /dev/null) || vrc=$?
vro=0; (cd "$D/old" && "$ROOT/build/cycc" < "$D/via.tcyr" > "$D/via_old" 2> /dev/null) || vro=$?
check "a caller (result_allocator_via.tcyr: ok_via, err_via, net.cyr's sock_*_a) compiles byte-identical to the : i64 spelling" \
    "0 0 same" "$vrc $vro $(cmp -s via_new via_old && echo same || echo differ)"
# 6.7.14 — the same for lib/net.cyr's sock_send_a / sock_recv_a, which return ok_via / err_via's pair
# (issues/2026-10-15-cyrius-header-net-sock-a-wrappers-print-cyr-val-over-a-pair.md; 6.7.13's D37
# applied to cyrius's own lib): declared `: Result`, they are cyr_val2 and `cyrius header lib/net.cyr`
# stays rc 0. Callers compile byte-identical to the 6.7.13 `: i64` spelling (x86_64 and PE), and a
# copy whose sock_*_a returns `ok_via(a, n + 7)` differs — the copy's lib is the one compiled.
# Mutation: the two signatures back to `: i64` → the cyr_val2 rows RED.
rcn=0; "$CY" header "$ROOT/lib/net.cyr" > o12n 2> e12n || rcn=$?
check "lib/net.cyr: exit 0, nothing on stderr" "0 0" "$rcn $(wc -c < e12n | tr -d ' ')"
for fnp in 'sock_send_a(cyr_val a, cyr_val fd, cyr_val buf, cyr_val len)' 'sock_recv_a(cyr_val a, cyr_val fd, cyr_val buf, cyr_val len)'; do
    check "lib/net.cyr: ${fnp%%(*} (: Result) is cyr_val2" 1 "$(has o12n "cyr_val2 $fnp;   /* returns Result: the tag in w0, the payload in w1 */")"
done
mkdir old14 old14p && cp -R "$ROOT/lib" old14/lib && cp -R "$ROOT/lib" old14p/lib
sed -e 's/^fn sock_send_a(a, fd, buf, len): Result {$/fn sock_send_a(a, fd, buf, len): i64 {/' \
    -e 's/^fn sock_recv_a(a, fd, buf, len): Result {$/fn sock_recv_a(a, fd, buf, len): i64 {/' "$ROOT/lib/net.cyr" > old14/lib/net.cyr
sed -e 's/^    return ok_via(a, n);$/    return ok_via(a, n + 7);/' "$ROOT/lib/net.cyr" > old14p/lib/net.cyr
check "the 6.7.13 copy differs from lib/net.cyr in the two signatures alone" "2 2" \
    "$(diff "$ROOT/lib/net.cyr" old14/lib/net.cyr | grep -c '^> fn sock_[a-z]*_a(a, fd, buf, len): i64 {$' || true) $(diff "$ROOT/lib/net.cyr" old14/lib/net.cyr | grep -c '^>' || true)"
cp "$ROOT/tests/tcyr/crossos/net_plain_write_peer_reset.tcyr" npr.tcyr
nbad=""
for src in via npr; do
    for tw in x86:0 pe:1; do
        t=${tw%%:*}; w=${tw#*:}
        for side in new old14 old14p; do
            dir="$ROOT"; [ "$side" = new ] || dir="$D/$side"
            if [ "$w" = 1 ]; then (cd "$dir" && CYRIUS_TARGET_WIN=1 "$ROOT/build/cycc" < "$D/$src.tcyr" > "$D/$src.$t.$side" 2> /dev/null) || nbad="$nbad $src/$t/$side:rc"
            else (cd "$dir" && "$ROOT/build/cycc" < "$D/$src.tcyr" > "$D/$src.$t.$side" 2> /dev/null) || nbad="$nbad $src/$t/$side:rc"; fi
        done
        cmp -s "$src.$t.new" "$src.$t.old14" || nbad="$nbad $src/$t:differs-from-i64"
        cmp -s "$src.$t.new" "$src.$t.old14p" && nbad="$nbad $src/$t:probe-identical"
    done
done
check "callers (result_allocator_via, net_plain_write_peer_reset; x86_64 and PE) compile byte-identical to the : i64 spelling; the n + 7 copy differs" "" "$nbad"
cat > pr.cyr <<'EOF'
include "lib/tagged.cyr"
enum Sx: stack { Va(v); Vb(); }
enum Mine { Mx(v); My; }
fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }
fn opt(x): Option { if (x == 0) { return None(); } return Some(x); }
fn tg(x): Tagged { return Left(x); }
fn mk(x) { return Ok(x); }
fn w(x) { return mk(x); }
fn w2(x) { return parse(x); }
fn ai(x): i64 { return Ok(x); }
fn nn() { return None(); }
fn cl(x) { var f = |a| { return Ok(a); }; return 0; }
fn sv(x) { return Va(x); }
fn sn() { return Vb(); }
fn bx(x) { return Mx(x); }
fn early(x) { return late(x); }
fn late(x) { if (x > 0) { return Err(x); } return 0; }
fn gw(x) { return gen<i64>(x); }
fn gen<T>(x: T) { return Right(x); }
fn _h(x) { return Ok(x); }
fn pubw(x) { return _h(x); }
fn tagonly(x) { return Ok; }
fn plain(x) { return x + 1; }
fn callplain(x) { return plain(x); }
fn ml(x)
{
    if (x == 1) { return 0; }
    return
        Some(x);
}
EOF
rc12b=0; "$CY" header pr.cyr > o12b 2> e12b || rc12b=$?
check "shapes: exit 1 (refusals)" 1 "$rc12b"
check "annotated : Result / : Option / : Tagged are cyr_val2" 3 "$(grep -cE '^cyr_val2 (parse|opt|tg)\(cyr_val x\);   /\* returns (Result|Option|Tagged): the tag in w0, the payload in w1 \*/$' o12b || true)"
refused() { grep -cxF "error: cyrius header: '$1' returns a \`: stack\` enum's (tag, payload) pair through '$2(..)', which its signature does not declare (cycc returns it in rax:rdx, aarch64 x0:x2); declare it \`: Result\`, \`: Option\` or \`: Tagged\`; no prototype written" e12b || true; }
check "refused by name: no annotation, returns Ok(..)" 1 "$(refused mk Ok)"
check "  ... returns a pair fn of this file (mk)" 1 "$(refused w mk)"
check "  ... returns an annotated pair fn (parse)" 1 "$(refused w2 parse)"
check "  ... a \`: i64\` signature over Ok(..)" 1 "$(refused ai Ok)"
check "  ... the file's own stack enum's payload variant" 1 "$(refused sv Va)"
check "  ... a fn defined BELOW it (the fixpoint)" "1 1" "$(refused early late) $(refused late Err)"
check "  ... a generic fn of this file (gen<i64>(..))" 1 "$(refused gw gen)"
check "  ... a private fn of this file (_h)" 1 "$(refused pubw _h)"
check "  ... a return whose call is on the next line" 1 "$(refused ml Some)"
check "exactly those 10 refusals" 10 "$(grep -c '^error: ' e12b || true)"
check "no prototype for a refused fn" 0 "$(grep -cE '^cyr_val2? (mk|w|w2|ai|sv|early|late|gw|pubw|ml)\(' o12b || true)"
check "a word: nullary None() / Vb(), a closure's own return, a boxing enum, a bare tag, a plain call" 7 \
    "$(grep -cxE 'cyr_val (nn\(void\)|sn\(void\)|cl\(cyr_val x\)|bx\(cyr_val x\)|tagonly\(cyr_val x\)|plain\(cyr_val x\)|callplain\(cyr_val x\));' o12b || true)"
# The compiler is the oracle: a single bind of every pair fn is refused ("bind both"), and of
# every word fn is not — and the header's own verdict (refused or cyr_val2 = the pair, cyr_val = a
# word; the expected one for gen and _h, which get no prototype) is cycc's.
hverdict() {
    if grep -qF "error: cyrius header: '$1' " e12b; then echo 1
    elif grep -qE "^cyr_val2 $1\(" o12b; then echo 1
    elif grep -qE "^cyr_val $1\(" o12b; then echo 0
    else echo "$2"; fi
}
bad=""
for fa in parse:1:5 opt:1:5 tg:1:5 mk:1:5 w:1:5 w2:1:5 ai:1:5 sv:1:5 early:1:5 late:1:5 gw:1:5 gen:1:5 _h:1:5 pubw:1:5 ml:1:5 \
          nn:0: sn:0: cl:0:5 bx:0:5 tagonly:0:5 plain:0:5 callplain:0:5; do
    fnm=${fa%%:*}; rest=${fa#*:}; want=${rest%%:*}; arg=${rest#*:}
    { cat pr.cyr; echo "var z = $fnm($arg);"; echo 'syscall(60, 0);'; } > pr1.cyr
    prc=0; (cd "$ROOT" && "$ROOT/build/cycc" < "$D/pr1.cyr" > /dev/null 2> "$D/pr1.err") || prc=$?
    got=0; [ "$prc" = 0 ] || got=compile-error   # a word fn's bind must COMPILE, not merely not say it
    grep -q 'returns two values — bind both' pr1.err && got=1
    hv=$(hverdict "$fnm" "$want")
    [ "$got" = "$want" ] && [ "$hv" = "$want" ] || bad="$bad $fnm:want=$want,cycc=$got,header=$hv"
done
check "cycc and the header agree on all 22: the pair fns, and only they, refuse a single bind" "" "$bad"
printf '%s\n' 'enum Sx: stack { Va(v); Vb(); }' 'enum Pl { Pa; Pb; }' 'fn sa(x): Sx { return Va(x); }' 'fn pl(): Pl { return Pa; }' > own.cyr
"$CY" header own.cyr > o12c 2> /dev/null || :
check "a file's own \`enum E: stack\` annotation is cyr_val2, a plain enum's a word" "1 1" \
    "$(has o12c 'cyr_val2 sa(cyr_val x);   /* returns Sx: the tag in w0, the payload in w1 */') $(has o12c 'cyr_val pl(void);')"
printf '%s\n' 'fn Some(x) { return x; }' 'fn u(x) { return Some(x); }' > shadow.cyr
"$CY" header shadow.cyr > o12d 2> e12d || :
check "a file's own fn named like a stdlib constructor decides (no refusal)" "1 0" "$(has o12d 'cyr_val u(cyr_val x);') $(wc -c < e12d | tr -d ' ')"
# 6.7.13 — THE `?` ROUTE (issues/archived/2026-10-15-cyrius-header-misses-a-pair-propagated-by-question-mark.md): a `?` on
# a pair call returns the callee's pair on its Err path and marks the enclosing fn pair-returning
# (the compiler's third route to GFLG 256), and the header printed `cyr_val q2(..)`. The filed
# repro verbatim, then the shapes; cycc's "bind both" refusal is the oracle again.
printf '%s\n' 'include "lib/result.cyr"' 'fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }' \
  'fn q2(x) { var v = parse(x)?; return v + 1; }' > qm.cyr
rcq=0; "$CY" header qm.cyr > o12q 2> e12q || rcq=$?
qref() { grep -cxF "error: cyrius header: '$1' returns a \`: stack\` enum's (tag, payload) pair through '$2(..)?', which its signature does not declare (its \`?\` returns the Err pair, in rax:rdx, aarch64 x0:x2); declare it \`: Result\`, \`: Option\` or \`: Tagged\`; no prototype written" "$3" || true; }
check "the filed qm.cyr: q2 refused by name through 'parse(..)?', exit 1" "1 1" "$(qref q2 parse e12q) $rcq"
check "... no q2 prototype; parse still cyr_val2; the header closes" "0 1 1" \
    "$(grep -c 'q2(' o12q || true) $(has o12q 'cyr_val2 parse(cyr_val x);   /* returns Result: the tag in w0, the payload in w1 */') $(has o12q '#endif /* CYRIUS_FFI_H */')"
{ cat qm.cyr; echo 'var z = q2(5);'; echo 'syscall(60, z);'; } > qm1.cyr
(cd "$ROOT" && "$ROOT/build/cycc" < "$D/qm1.cyr" > /dev/null 2> "$D/qm1.err") || :
{ cat qm.cyr; echo 'var t, v = q2(0 - 3);'; echo 'syscall(60, t * 10 + v);'; } > qm3.cyr
qrc=0; { (cd "$ROOT" && "$ROOT/build/cycc" < "$D/qm3.cyr" > "$D/qm3" 2> /dev/null) && chmod +x qm3 && ./qm3; } || qrc=$?
check "cycc agrees: a single bind of q2 is refused (bind both), and q2(-3) forwards Err(3) (13)" "1 13" "$(grep -c 'returns two values — bind both' qm1.err || true) $qrc"
cat > qs.cyr <<'QEOF'
include "lib/result.cyr"
fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }
fn plain(x) { return x + 1; }
fn gen<T>(x: T) { return Ok(x); }
fn q2(x) { var v = parse(x)?; return v + 1; }
fn q3(x) { var v = q2(x)?; return v; }
fn qg(x) { var v = gen<i64>(x)?; return v; }
fn qs(x) { parse(x)?; return 0; }
fn qi(x): i64 { var v = parse(x)?; return v; }
fn qx(x) { var v = parse((x + 1) < 3)?; return v; }
fn qsp(x) { var v = parse(x) ?; return v; }
fn qok(x): Result { var v = parse(x)?; return Ok(v); }
fn qw(x) { var r = alloc(16); var v = plain(r)?; return v; }
fn qcb(x) { var f = |a| { var v = parse(a)?; return v; }; return 0; }
fn qce(x) { var f = |a| parse(a)?; return 0; }
fn qcz(x) { var f = || parse(1)?; return x; }
fn qor(x) { var y = x | 1; var z = y || 0; return z; }
QEOF
rcqs=0; "$CY" header qs.cyr > o12r 2> e12r || rcqs=$?
check "the ? shapes: exit 1, seven refusals" "1 7" "$rcqs $(grep -c '^error: ' e12r || true)"
check "  refused: a chained q2(..)? (the fixpoint)" 1 "$(qref q3 q2 e12r)"
check "  ... a generic call's gen<i64>(..)?" 1 "$(qref qg gen e12r)"
check "  ... a bare-statement parse(..)?;" 1 "$(qref qs parse e12r)"
check "  ... a \`: i64\` signature (D37's reach)" 1 "$(qref qi parse e12r)"
check "  ... nested parentheses and a < in the arguments; a blank before the ?" "1 1" "$(qref qx parse e12r) $(qref qsp parse e12r)"
check "a word: ? on a word call, a closure's own ? (a block, an expression, ||), | and ||" 5 \
    "$(grep -cxE 'cyr_val (qw|qcb|qce|qcz|qor)\(cyr_val x\);' o12r || true)"
check "an annotated : Result with a ? stays cyr_val2" 1 "$(has o12r 'cyr_val2 qok(cyr_val x);   /* returns Result: the tag in w0, the payload in w1 */')"
qbad=""
for fa in q2:1 q3:1 qg:1 qs:1 qi:1 qx:1 qsp:1 qok:1 qw:0 qcb:0 qce:0 qcz:0 qor:0; do
    fnm=${fa%%:*}; want=${fa#*:}
    { cat qs.cyr; echo "var z = $fnm(5);"; echo 'syscall(60, 0);'; } > qs1.cyr
    prc=0; (cd "$ROOT" && "$ROOT/build/cycc" < "$D/qs1.cyr" > /dev/null 2> "$D/qs1.err") || prc=$?
    got=0; [ "$prc" = 0 ] || got=compile-error
    grep -q 'returns two values — bind both' qs1.err && got=1
    hv=0; { grep -qF "error: cyrius header: '$fnm' " e12r || grep -qE "^cyr_val2 $fnm\(" o12r; } && hv=1
    [ "$got" = "$want" ] && [ "$hv" = "$want" ] || qbad="$qbad $fnm:want=$want,cycc=$got,header=$hv"
done
check "cycc and the header agree on all 13 ? shapes" "" "$qbad"
if [ "$CCX86" = 1 ]; then
    p12() { "$@" -E -P -x c o12 2> /dev/null | grep -oE ' parse\(' | tr -d ' (' | paste -sd' ' -; }
    check "x86_64 SysV (cc): parse declared" "parse" "$(p12 cc)"
    check "-D_WIN64 (cc): no parse" "" "$(p12 cc -D_WIN64)"
    if command -v clang > /dev/null 2>&1; then
        check "aarch64 Linux (clang): no parse (x0:x2)" "" "$(p12 clang --target=aarch64-linux-gnu -ffreestanding)"
        check "aarch64 macOS (clang): no parse (x0:x2)" "" "$(p12 clang --target=aarch64-apple-darwin -ffreestanding)"
        check "Win64 (clang): no parse (a hidden result pointer)" "" "$(p12 clang --target=x86_64-w64-windows-gnu -ffreestanding)"
        for tg in aarch64-linux-gnu x86_64-w64-windows-gnu aarch64-apple-darwin; do
            check "o12 + o12b: clang --target=$tg" 0 "$(clang --target=$tg -ffreestanding -std=c11 -pedantic-errors -fsyntax-only -x c o12 > /dev/null 2>&1 && clang --target=$tg -ffreestanding -std=c11 -pedantic-errors -fsyntax-only -x c o12b > /dev/null 2>&1; echo $?)"
        done
    else
        echo "  SKIP (named): H12's clang guard rows — no clang on this host"; skips=$((skips + 1))
    fi
    for f in o12 o12b o12p o12q o12r o12n; do
        check "$f: cc -std=c11 -pedantic-errors (and -D_WIN64)" "0 0" "$(cc -std=c11 -pedantic-errors -fsyntax-only -x c "$f" > /dev/null 2>&1; echo $?) $(cc -std=c11 -pedantic-errors -fsyntax-only -D_WIN64 -x c "$f" > /dev/null 2>&1; echo $?)"
    done
    # A C caller linked against the filed repro (`object;`): both words through the header.
    cp o12 ffi12.h
    { echo 'object;'; cat se.cyr; } > lib12.cyr
    (cd "$ROOT" && "$ROOT/build/cycc" < "$D/lib12.cyr" > "$D/lib12.o" 2> /dev/null) || :
    cat > caller12.c <<'CEOF'
#include <stdio.h>
#include "ffi12.h"
extern void _cyrius_init(void);
int main(void) {
    _cyrius_init();
    cyr_val2 a = parse(21);
    cyr_val2 b = parse(-5);
    printf("%ld %ld|%ld %ld\n", (long)a.w0, (long)a.w1, (long)b.w0, (long)b.w1);
    return 0;
}
CEOF
    if cc -std=c11 -O1 caller12.c lib12.o -I. -o caller12 > cc12.err 2>&1; then
        check "a C caller reads Ok(42) and Err(5) through the header: tag | payload" "0 42|1 5" "$(./caller12 2>&1)"
    else
        check "the C caller compiles and links against the repro object" 0 1; sed 's/^/    /' cc12.err | head -5
    fi
else
    echo "  SKIP (named): H12's guard rows and C caller — $CCX86_WHY"; skips=$((skips + 1))
fi

# ── H13: a parameter list that WRAPS (6.7.14; issues/2026-10-15-cyrius-header-multi-line-parameter-list-keeps-first-line-only.md).
# The list's `)` was looked for on the declaration's line alone, so a list continued on the next
# line lost every later parameter (the C caller passed garbage in the dropped registers) and a
# vector parameter there escaped the 6.7.13 refusal — rc 0, nothing on stderr. The filed repro
# verbatim, cyrius's own lib (tls_native_hkdf_expand_label: nine parameters over two lines), then
# a default and a tuple type that wrap, tabs, CRLF, comments, an empty / variadic wrapped list.
echo "H13 — a parameter list that wraps lines: every parameter, every refusal:"
printf 'fn b3(x,\n      y): i64 { return 0; }\nfn a3(x,\n      v: u8v16): i64 { return 0; }\n' > ml.cyr
rc13=0; "$CY" header ml.cyr > o13 2> e13 || rc13=$?
check "the filed ml.cyr: b3 prints both parameters" 1 "$(has o13 'cyr_val b3(cyr_val x, cyr_val y);')"
check "... a3 (v: u8v16 on the continuation line) refused by name, no prototype, exit 1" "1 0 1" \
    "$(grep -cxF "error: cyrius header: 'a3' takes 'v: u8v16': a SIMD vector parameter, which no C11 type carries; no prototype written" e13 || true) $(grep -c 'a3(' o13 || true) $rc13"
printf 'fn a1(x, v: u8v16): i64 { return 0; }\n' > one.cyr
rc13o=0; "$CY" header one.cyr > /dev/null 2> e13o || rc13o=$?
check "... as the one-line a1 is" "1 1" "$(grep -c "^error: cyrius header: 'a1' takes 'v: u8v16'" e13o || true) $rc13o"
{ cat ml.cyr; printf 'var r = b3(1, 2);\nsyscall(60, r);\n'; } > ml1.cyr
mrc=0; (cd "$ROOT" && "$ROOT/build/cycc" < "$D/ml1.cyr" > "$D/ml1" 2> /dev/null) || mrc=$?
mx=$( { chmod +x ml1 && ./ml1; } > /dev/null 2>&1; echo $?)
check "... and ml.cyr compiles with cycc, b3(1, 2) exits 0" "0 0" "$mrc $mx"
"$CY" header "$ROOT/lib/tls_native_keysched.cyr" > o13t 2> /dev/null || :
check "lib/tls_native_keysched.cyr: tls_native_hkdf_expand_label has its nine parameters" 1 \
    "$(has o13t 'cyr_val tls_native_hkdf_expand_label(cyr_val sec, cyr_val secret_len, cyr_val label, cyr_val label_len, cyr_val ctx, cyr_val ctx_len, cyr_val hash_algo, cyr_val out, cyr_val out_len);')"
printf 'include "lib/result.cyr"\nfn r2(x,\n      y): Result { return Ok(x); }\nfn wd(a,\n      t: (i64,\n          i64),\n      b = (1 +\n              2),\n      c = 3): i64 { return a; }\nfn tb(a,\n\tb): i64 { return a; }\nfn cr(a,\r\n      b): i64 { return a; }\nfn cm(a, # the first\n      b # the second\n      , c): i64 { return a; }\nfn e0(\n): i64 { return 0; }\nfn va(\n    ...\n): i64 { return 0; }\nfn tw(a,\n      ...): i64 { return a; }\n' > mw.cyr
wrc=0; (cd "$ROOT" && "$ROOT/build/cycc" < "$D/mw.cyr" > /dev/null 2> /dev/null) || wrc=$?
check "the wrapped shapes compile with cycc" 0 "$wrc"
rc13w=0; "$CY" header mw.cyr > o13w 2> e13w || rc13w=$?
check "the wrapped shapes: exit 0, nothing on stderr" "0 0" "$rc13w $(wc -c < e13w | tr -d ' ')"
check "  a wrapped : Result keeps both parameters (cyr_val2)" 1 "$(has o13w 'cyr_val2 r2(cyr_val x, cyr_val y);   /* returns Result: the tag in w0, the payload in w1 */')"
check "  a tuple type and a default that wrap" 1 "$(has o13w 'cyr_val wd(cyr_val a, cyr_val t, cyr_val b, cyr_val c);')"
check "  a tab, a CRLF, comments before a wrapped comma" "1 1 1" \
    "$(has o13w 'cyr_val tb(cyr_val a, cyr_val b);') $(has o13w 'cyr_val cr(cyr_val a, cyr_val b);') $(has o13w 'cyr_val cm(cyr_val a, cyr_val b, cyr_val c);')"
check "  an empty wrapped list is (void); a wrapped ... alone is variadic (void); a wrapped tail is ..." "1 1 1" \
    "$(has o13w 'cyr_val e0(void);') $(has o13w 'cyr_val va(void); /* variadic in cyrius: it reads no argument */') $(has o13w 'cyr_val tw(cyr_val a, ...);')"
if command -v cc > /dev/null 2>&1; then
    { cat o13w; echo 'void f13(void) { (void)tb(1, 2); (void)cr(1, 2); (void)cm(1, 2, 3); (void)wd(1, 2, 3, 4); (void)e0(); (void)va(); (void)tw(1, 2, 3); }'; } > o13c.c
    { cat o13t; echo 'void f13t(void) { (void)tls_native_hkdf_expand_label(1, 2, 3, 4, 5, 6, 7, 8, 9); }'; } > o13tc.c
    check "a C caller passes each wrapped fn its arity (cc -std=c11 -pedantic-errors)" "0 0 0" \
        "$(cc -std=c11 -pedantic-errors -fsyntax-only -x c o13c.c > /dev/null 2>&1; echo $?) $(cc -std=c11 -pedantic-errors -fsyntax-only -x c o13tc.c > /dev/null 2>&1; echo $?) $(cc -std=c11 -pedantic-errors -fsyntax-only -x c o13 > /dev/null 2>&1; echo $?)"
else
    echo "  SKIP (named): H13's C arity row — no C compiler (cc) on this host"; skips=$((skips + 1))
fi
cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ] && [ "$skips" -gt 0 ]; then
    echo "SKIP: header-spellings-and-size — every check that ran passed; $skips leg(s) could not run here (named above; exit 77: a SKIP, not a PASS)"
    exit 77
fi
if [ "$fails" = "0" ]; then
    echo "PASS: header-spellings-and-size — every public spelling, the private rule, whole-file read, the return type"
    exit 0
fi
echo "FAIL: header-spellings-and-size — $fails assertion(s) failed"
exit 1
