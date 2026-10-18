#!/bin/sh
# decl_after_statement_named.sh — a declaration after the first top-level statement is ONE error by name; an
# `async fn` there is a function (6.7.14); a declaration inside a fn body or a block is one error too, and a use
# of what a refused declaration names adds none (6.7.15).
#
# THE DEFECT (measured 6.7.10 - 6.7.13, x86_64; the frontend, every target). The guide's rule (§ Functions, § Traits)
# keeps `struct`, `enum`, `union`, `trait`, `impl`, `mod`, `use` and `pub` / `public` declarations before the first
# top-level statement; `fn`, `const` and `var` may follow it. After a statement PARSE_PROG handed each refused kind to
# PARSE_STMT: "unexpected struct" (`union`: "expected ';', got union") followed by up to three invented errors, the
# statement resync re-entering the declaration's braces (`impl Tr for P { .. }`: "expected '(', got identifier 'P'",
# "unexpected var" on the next line, "unexpected end of input"); an `include` of a file declaring one failed INSIDE
# that file ("lib/str.cyr:24:1: unexpected struct" + three). And `async fn` there — a function, which the guide says
# may follow statements — was "expected identifier, got reserved keyword 'fn'": PARSE_PROG's relaxed-ordering arm
# admitted it (`_IS_FN_KW`) but consumed only `const`'s prefix.
# (issues/archived/2026-10-12-declarations-after-first-statement-decision.md)
#
# THE DECISIONS (the user, 2026-10-16): D13 (a) — the guide's rule, one named error: "a `struct` declaration must
# come before the first top-level statement (line N)"; an include names its own line; no cascade, nothing that
# compiles changes. D14 (a) — `async fn` after the first statement compiles, as `fn` does.
#
# THE FIX. PARSE_STMT asks `_decl_late` first (module scope only: GINFN 0, `_pp_depth` 1): one error at the keyword
# naming the first statement's line (`_tl_stmt1`, where pass 1 stopped), the declaration stepped through its `}` /
# `;` (`_dl_skip`), a derive's generated line with it (`_dl_derived`). A declaration inside a file whose `include`
# follows the statement is reported at that include line (the statement's file resumes after the inclusion with the
# include's line + 1, `_dl_incl`), the rest of the inclusion stepped. The fns the refused declaration would have
# defined — a `pub fn`, an impl's methods, a `use` alias, an inclusion's or a derive's fns — are entered as reported
# (`_dl_quiet`), so calling one adds no "undefined function" / "refusing to emit binary". `async`'s prefix is consumed
# in PARSE_PROG's relaxed arm (`_tl_async_prefix`).
#
#   K   each kind after `a = 2;`, `syscall(39);` and a block statement: exactly one error, the named message
#   R   the filed repros verbatim: impl (one error), the impl-before control (7), fn after `syscall(39);` (5),
#       `include "lib/str.cyr"` after code (one error naming line 2), `async fn` (runs, 3)
#   I   includes: after each statement kind, a nested include (named at the OUTER include), two includes (the
#       declaring one named), an include of a non-declaring file after code and the declaring one before it compile
#   Q   no downstream cascade: a refused impl's methods called, a refused include's fns called, a derive's accessor
#       called, a `use` alias called — still one error; several late declarations — one error each
#   A   `async fn` after each statement kind runs through future_force (CYRIUS_ASYNC=1); `const fn` / `fn` still do
#   C   controls: every kind before the first statement compiles and runs; --syntax-only gives the same one error
#
# ONE LEVEL DOWN (6.7.15; issues/2026-10-17-declaration-inside-block-or-fn-body-cascades.md). A `struct`, `enum`,
# `union`, `trait` or `impl` inside a fn body or a block reached PARSE_STMT the same way: "unexpected struct"
# (`union`: "expected ';', got union") and up to four invented errors — "expected '=', got '{'", "undefined variable
# 'y'", "undefined variable 'Q'", and "return outside a fn body" once the resync took the fn body's own `}`. Now
# `_decl_inner` (GINFN 1, or `_pp_depth` past module scope): one error at the keyword, "a `struct` declaration
# belongs to the declaration section at top level, not inside a fn body" (or "... not inside a block"), the
# declaration stepped (`_dl_skip_in`, which leaves a `}` closing the enclosing body), the fns it would define
# entered as reported (`_dl_quiet`).
#
#   N   each kind inside a top-level `if` block, a top-level `while` block and a fn body: exactly one error
#   NS  the body parses on: a second, independent mistake after it is reported (and no "return outside a fn
#       body"); a closure, an impl method, a nested block, a `switch` case, `@unsafe`, `else`, a `for` body,
#       a generic fn at two instances, several in one body, a derived struct, an impl's method called, a
#       declaration with no body (`struct Q }`: the block's `}` is not stepped), --syntax-only: one error each
#   NC  a `const fn`'s body: the definition check's one refusal (the run-time body stands down at its token)
#
# ITS USES (6.7.15; issues/2026-10-17-late-declaration-refusal-cascades-at-its-uses.md). The refused declaration
# was stepped, so what it names was never registered, and each use was a second error: `var q = Q { 5 };`
# "undefined variable 'Q'" + "expected ';', got '{'", `E.B` / `B` "undefined variable", `fn f(q: *Q)` "unknown
# type 'Q' for parameter 'q'" + its `q.y` "no struct type in scope for 'q'". Now the struct, union and enum names
# and an enum's members are entered as reported (`_dl_names`, over the stepped tokens of each refusal: late, an
# inclusion, inner), a payload member's constructor as a reported fn; the reporters stand down for exactly those
# names (`_dl_refd_at`: `_undef_var_report`, `_tn_refuse`, the stray literal `_slit_refd` / `_slit_refd_stmt`),
# and for a variable whose annotation or literal initializer named one (`_ann_refd_mark` / `_ann_refd_said`: the
# `.field`, method and field-store `sid == 0` arms).
#
#   U   the filed repros verbatim (struct literal, `E.B`, bare `B`, `*Q` parameter + `.y`): one error each
#   UX  more uses: the literal's variable's `.y`, a parameter's field store and method, `var e: E = E.A`, an enum
#       parameter / return, sizeof, a `*Q` return, a union parameter, a generic literal, a payload constructor,
#       a `Q { 5 };` statement, in a fn body (the inner arm), a refused inclusion's struct / enum / fn; and
#       --syntax-only: one error per refused declaration
#   UE  exact names only: a name declared nowhere, an unknown type beside a refused one and an untyped `q.y` in
#       another fn are still reported (beside the refused names' uses, which are not)
#   UC  control: the same program with the declarations before the statement compiles and runs
#
# MUTATION LEDGER (each mutant built from the fixed tree with the one change):
#   base: the lane before it (5048df2e)             -> RED 49 of 54: every K / R1 / R4 / R5 / I1-I4 / Q / A row and
#                                                      C2 (the old "unexpected struct" + its cascade, "expected
#                                                      identifier, got reserved keyword 'fn'"); green: the
#                                                      controls R2 R3 I5 I6 C1
#   PARSE_STMT without its `_decl_late` line        -> RED every K row, R1 R4 I1-I4 Q1-Q5 C2 (A green)
#   `_tl_async_prefix` returns at once              -> RED R5 A1 A2 A3
#   `_dl_incl` returns 0 (reported at the decl)     -> RED R4 I1-I4 Q2 (one error, but inside lib/str.cyr, and the
#                                                      rest of the inclusion cascades)
#   `_dl_quiet` returns at once                     -> RED Q1-Q4 ("undefined function" + "refusing to emit binary")
#   `_dl_derived` returns at once                   -> RED Q3 ("unknown type 'Q' in #assert sizeof", the enum's
#                                                      `public` codec refused too)
#   `_dl_skip` steps one token                      -> RED the K rows but pub-fn / public-var (the body cascades),
#                                                      R1 Q1 Q3-Q5 C2
#   (6.7.15, measured) `_decl_inner` returns 0      -> RED all 36 N / NS / NC rows (the old "unexpected struct"
#                                                      and its cascade); the 54 rows before them green
#   `_dl_skip_in` steps a closing `}` (inner 0)     -> RED NS13 ("expected '}', got end of file": the block's `}`
#                                                      taken)
#   `_decl_inner` without `_dl_quiet`               -> RED NS12 ("undefined function 'P.g'" twice + "refusing to
#                                                      emit binary")
#   `_dl_in_report` without its `_ce_err_dup`       -> RED NS9 (the error once per generic instance), NC (the
#                                                      const fn check's token reported again by the body)
#   (6.7.15, measured) `_dl_names` returns at once  -> RED U1-U4, UX1-UX8, UE1, UE2 (every refused name used)
#   `_undef_var_report` without its stand-down      -> RED U2 U3 UX3 UX6 UX7 UE1 ("undefined variable 'E'" / 'B')
#   `_tn_refuse` without its stand-down             -> RED U4 UX1-UX4 UX7 UE2 ("unknown type 'Q' for ...")
#   `_slit_refd` returns -1                          -> RED U1 UX1 UX2 UX4 UX6 UX7 UX8 ("expected ';', got '{'")
#   `_ann_refd_said` returns 0                       -> RED U4 UX1-UX4 UX6 UX7 UE2 ("no struct type in scope")
#   `_ann_refd_said` ignoring the scope              -> RED UE2 (another fn's untyped `q.y` silenced)
#   `_dl_refd_at` matching any name                  -> RED NS4 NS5 UE1 (a name declared nowhere silenced)
#   `_dl_member_at` without `_dl_fn_quiet`           -> RED UX4 ("undefined function 'Ok2'" + "refusing to emit")
#   `_slit_refd_stmt` returns 0                      -> RED UX5 (the statement's cascade)
#   `_slit_stray` without its `_ann_refd_mark`       -> RED UX1 UX2 UX6 UX7 (the literal's variable's `.y`)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0

# one LABEL SOURCE EXPECTED-LINES [cc-args]: refused (rc != 0, no binary unless --syntax-only) and the `error` /
# `warning` lines are EXACTLY the expected ones.
one() {
    printf '%s' "$2" > "$D/o.cyr"
    rc=0
    cat "$D/o.cyr" | "$CC" ${4:-} > "$D/o.bin" 2>"$D/o.err" || rc=$?
    grep -E '^(error|warning)' "$D/o.err" > "$D/o.got" || true
    printf '%s\n' "$3" > "$D/o.want"
    if [ "$rc" = 0 ]; then
        printf '  FAIL: %-46s rc 0\n' "$1"; fail=$((fail+1))
    elif cmp -s "$D/o.got" "$D/o.want"; then
        printf '  ok: %-50s\n' "$1"; pass=$((pass+1))
    else
        printf '  FAIL: %-46s got:\n' "$1"; sed 's/^/        /' "$D/o.got"
        printf '        want:\n'; sed 's/^/        /' "$D/o.want"
        fail=$((fail+1))
    fi
}
# runs LABEL SOURCE EXIT [env-assignment]: compiles clean (no error line) and the binary exits EXIT.
runs() {
    printf '%s' "$2" > "$D/r.cyr"
    rc=0
    if [ -n "${4:-}" ]; then cat "$D/r.cyr" | env "$4" "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    else cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?; fi
    if [ "$rc" != 0 ] || [ ! -s "$D/r.bin" ] || grep -q '^error' "$D/r.err"; then
        printf '  FAIL: %-46s compile rc %s: %s\n' "$1" "$rc" "$(grep -m1 '^error' "$D/r.err" || true)"; fail=$((fail+1)); return
    fi
    chmod +x "$D/r.bin"
    x=0; ( ulimit -c 0; timeout 30 "$D/r.bin" ) > /dev/null 2>&1 || x=$?
    if [ "$x" = "$3" ]; then printf '  ok: %-50s exit %s\n' "$1" "$x"; pass=$((pass+1))
    else printf '  FAIL: %-46s exit %s, want %s\n' "$1" "$x" "$3"; fail=$((fail+1)); fi
}

R='must come before the first top-level statement'

# ── K: each kind after three first statements ───────────────────────────────────────────────────────────────
# kind label | the declaration (one line) | its article+keyword as reported
KINDS='struct|struct Q { y; }|a `struct`
enum|enum E { EA; EB; }|an `enum`
enum-stack|enum E2: stack { Ok2(v); Err2(e); }|an `enum`
union|union U { x; y: i32; }|a `union`
trait|trait Tr2 { fn m(self): i64; }|a `trait`
impl|impl P { fn get(self): i64 { return self.x; } }|an `impl`
impl-for|impl Tr for P { fn m(self): i64 { return self.x; } }|an `impl`
mod|mod mm;|a `mod`
use|use mm.f;|a `use`
pub-fn|pub fn pf(): i64 { return 1; }|a `pub`
public-var|public var pv = 3;|a `public`'
HEAD='struct P { x; }
trait Tr { fn m(self): i64; }
mod mm;
fn f(): i64 { return 1; }
mod;
var a = 1;
'
for st in 'a = 2;' 'syscall(39);' 'if (a == 1) { a = 2; }'; do
    printf '%s\n' "$KINDS" | while IFS='|' read -r k decl art; do
        [ -n "$k" ] || continue
        one "K $k after '$st'" "$HEAD$st
$decl
var b = 3;
syscall(60, a + b);
" "error:<source>:8:1: $art declaration $R (line 7)"
    done > "$D/k.out"
    cat "$D/k.out"
    pass=$((pass + $(grep -c '^  ok' "$D/k.out" || true))); fail=$((fail + $(grep -c '^  FAIL' "$D/k.out" || true)))
done

# ── R: the filed repros, verbatim ───────────────────────────────────────────────────────────────────────────
one "R1 filed: impl after a = 2;" "$(printf 'struct P { x; }\nvar a = 1;\na = 2;\nimpl P { fn get(self): i64 { return self.x; } }\nsyscall(60, a);\n')
" "error:<source>:4:1: an \`impl\` declaration $R (line 3)"
runs "R2 filed control: impl before the statement" "$(printf 'struct P { x; }\nvar a = 1;\nimpl P { fn get(self): i64 { return self.x; } }\na = 2;\nvar p: P = P { 5 };\nsyscall(60, p.get() + a);\n')
" 7
runs "R3 filed: fn after syscall(39);" "$(printf 'syscall(39);\nfn g(): i64 { return 5; }\nsyscall(60, g());\n')
" 5
one "R4 filed: include lib/str.cyr after code" "$(printf 'syscall(39);\ninclude "lib/str.cyr"\nsyscall(60, 3);\n')
" "error:<source>:2:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) $R (line 1)"
runs "R5 filed: async fn after syscall(39);" "$(printf 'include "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/async.cyr"\nsyscall(39);\nasync fn af(): i64 { return 1; }\nsyscall(60, 3);\n')
" 3 CYRIUS_ASYNC=1

# ── I: includes ─────────────────────────────────────────────────────────────────────────────────────────────
one "I1 include after a = 2;" 'var a = 1;
a = 2;
include "lib/str.cyr"
syscall(60, a);
' "error:<source>:3:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) $R (line 2)"
one "I2 include after a block statement" 'var a = 1;
if (a == 1) { a = 2; }
include "lib/str.cyr"
syscall(60, a);
' "error:<source>:3:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) $R (line 2)"
printf 'fn ia(): i64 { return 1; }\ninclude "lib/str.cyr"\nfn ib(): i64 { return 2; }\n' > "$D/inc_a.cyr"
printf 'syscall(39);\ninclude "%s"\nsyscall(60, ia());\n' "$D/inc_a.cyr" > "$D/i3.cyr"
CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1; export CYRIUS_ALLOW_ABSOLUTE_INCLUDES   # the nested file lives in the scratch dir
one "I3 a nested include: named at the outer one" "$(cat "$D/i3.cyr")
" "error:<source>:2:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) $R (line 1)"
unset CYRIUS_ALLOW_ABSOLUTE_INCLUDES
one "I4 two includes: the declaring one named" 'syscall(39);
include "lib/alloc.cyr"
include "lib/str.cyr"
syscall(60, 3);
' "error:<source>:3:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) $R (line 1)"
runs "I5 control: a non-declaring include after code" 'syscall(39);
include "lib/alloc.cyr"
alloc_init();
var p = alloc(8);
syscall(60, 4);
' 4
runs "I6 control: the declaring include before code" 'include "lib/str.cyr"
syscall(39);
syscall(60, 3);
' 3

# ── Q: no downstream cascade ────────────────────────────────────────────────────────────────────────────────
one "Q1 a refused impl's methods called" 'struct P { x; }
trait Tr { fn m(self): i64; }
var a = 1;
a = 2;
impl P { fn get(self): i64 { return self.x; } }
impl Tr for P { fn m(self): i64 { return self.x; } }
var p: P = P { 5 };
syscall(60, p.get() + p.m() + a);
' "error:<source>:5:1: an \`impl\` declaration $R (line 4)
error:<source>:6:1: an \`impl\` declaration $R (line 4)"
one "Q2 a refused include's fns called" 'include "lib/alloc.cyr"
alloc_init();
include "lib/str.cyr"
var s = str_from("x");
syscall(60, str_len(s));
' "error:<source>:3:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) $R (line 2)"
one "Q3 a derived struct, its accessor called" 'include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
alloc_init();
#derive(accessors)
struct Q { y; }
#derive(Serialize)
enum DE { DA; DB; }
var q = alloc(8);
syscall(60, Q_y(q));
' "error:<source>:7:1: a \`struct\` declaration $R (line 5)
error:<source>:9:1: an \`enum\` declaration $R (line 5)"
one "Q4 a refused use alias / pub fn called" 'mod mm;
fn g(): i64 { return 1; }
mod;
syscall(39);
use mm.g;
pub fn pg(): i64 { return 2; }
syscall(60, g() + pg());
' "error:<source>:5:1: a \`use\` declaration $R (line 4)
error:<source>:6:1: a \`pub\` declaration $R (line 4)"
one "Q5 every kind in a row: one error each" 'struct P { x; }
trait Tr { fn m(self): i64; }
var a = 1;
a = 2;
impl Tr for P { fn m(self): i64 { return self.x; } }
var b = 3;
struct Q { y; }
fn f(): i64 { return 4; }
enum E: stack { Ok2(v); Err2(e); }
union U { x; y: i32; }
pub var pv = 3;
public fn pf(): i64 { return 1; }
mod mm;
use mm.f;
syscall(60, a + b + f());
' "error:<source>:5:1: an \`impl\` declaration $R (line 4)
error:<source>:7:1: a \`struct\` declaration $R (line 4)
error:<source>:9:1: an \`enum\` declaration $R (line 4)
error:<source>:10:1: a \`union\` declaration $R (line 4)
error:<source>:11:1: a \`pub\` declaration $R (line 4)
error:<source>:12:1: a \`public\` declaration $R (line 4)
error:<source>:13:1: a \`mod\` declaration $R (line 4)
error:<source>:14:1: a \`use\` declaration $R (line 4)"

# ── A: `async fn` after the first statement is a function ───────────────────────────────────────────────────
AH='include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
var a = 1;
'
AT='async fn af(x): i64 { return x + 4; }
const fn cf(): i64 { return 2; }
fn pf(): i64 { return 1; }
alloc_init();
var fu = af(3);
syscall(60, future_force(fu) + cf() + pf() + a);
'
runs "A1 async fn after a = 2;" "${AH}a = 2;
$AT" 12 CYRIUS_ASYNC=1
runs "A2 async fn after syscall(39);" "${AH}syscall(39);
$AT" 11 CYRIUS_ASYNC=1
runs "A3 async fn after a block statement" "${AH}if (a == 1) { a = 3; }
$AT" 13 CYRIUS_ASYNC=1

# ── C: controls ─────────────────────────────────────────────────────────────────────────────────────────────
runs "C1 every kind before the first statement" 'struct P { x; }
trait Tr { fn m(self): i64; }
struct Q { y; }
enum E { EA; EB; }
enum E2: stack { Ok2(v); Err2(e); }
union U { x; y: i32; }
trait Tr2 { fn m(self): i64; }
impl P { fn get(self): i64 { return self.x; } }
impl Tr for P { fn m(self): i64 { return self.x + 1; } }
pub fn pf(): i64 { return 1; }
public var pv = 3;
mod mm;
fn f(): i64 { return 1; }
use mm.f;
var a = 1;
a = 2;
var p: P = P { 5 };
syscall(60, p.get() + p.m() + a + pf() + pv + f() + EB);
' 19
one "C2 --syntax-only: the same one error" "$(printf 'struct P { x; }\nvar a = 1;\na = 2;\nimpl P { fn get(self): i64 { return self.x; } }\nsyscall(60, a);\n')
" "error:<source>:4:1: an \`impl\` declaration $R (line 3)" --syntax-only

# ── N: one level down — a declaration in a block or a fn body (6.7.15) ──────────────────────────────────────
IR='belongs to the declaration section at top level, not inside'
NKINDS='struct|struct Q { y; }|a `struct`
enum|enum E { EA; EB; }|an `enum`
enum-stack|enum E2: stack { Ok2(v); Err2(e); }|an `enum`
union|union U { x; y: i32; }|a `union`
trait|trait Tr2 { fn m(self): i64; }|a `trait`
impl|impl P { fn get(self): i64 { return self.x; } }|an `impl`
impl-for|impl Tr for P { fn m(self): i64 { return self.x; } }|an `impl`'
NHEAD='struct P { x; }
trait Tr { fn m(self): i64; }
var a = 1;
'
printf '%s\n' "$NKINDS" | while IFS='|' read -r k decl art; do
    [ -n "$k" ] || continue
    one "N $k in a top-level if block" "${NHEAD}if (a == 1) { $decl }
syscall(60, a);
" "error:<source>:4:15: $art declaration $IR a block"
    one "N $k in a top-level while block" "${NHEAD}while (a == 1) { $decl a = 2; }
syscall(60, a);
" "error:<source>:4:18: $art declaration $IR a block"
    one "N $k in a fn body" "${NHEAD}fn f(): i64 { $decl return 1; }
syscall(60, f() + a);
" "error:<source>:4:15: $art declaration $IR a fn body"
done > "$D/n.out"
cat "$D/n.out"
pass=$((pass + $(grep -c '^  ok' "$D/n.out" || true))); fail=$((fail + $(grep -c '^  FAIL' "$D/n.out" || true)))

one "NS1 filed: struct in a top-level if block" "$(printf 'var a = 1;\nif (a == 1) { struct Q { y; } }\nsyscall(60, a);\n')
" "error:<source>:2:15: a \`struct\` declaration $IR a block"
one "NS2 filed: struct in a fn body" "$(printf 'fn f(): i64 { struct Q { y; } return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`struct\` declaration $IR a fn body"
one "NS3 filed: impl in a fn body" "$(printf 'fn f(): i64 { impl P { fn g(self): i64 { return 1; } } return 1; }\nstruct P { x; }\nsyscall(60, f());\n')
" "error:<source>:1:15: an \`impl\` declaration $IR a fn body"
one "NS4 the body parses on: its return's mistake" 'fn f(): i64 { struct Q { y; } return zz; }
syscall(60, f());
' "error:<source>:1:15: a \`struct\` declaration $IR a fn body
error:<source>:1:40: undefined variable 'zz' (missing include or enum?)"
one "NS5 the block parses on, and the program" 'var a = 1;
if (a == 1) { struct Q { y; } a = zz; }
syscall(60, yy);
' "error:<source>:2:15: a \`struct\` declaration $IR a block
error:<source>:2:37: undefined variable 'zz' (missing include or enum?)
error:<source>:3:15: undefined variable 'yy' (missing include or enum?)"
one "NS6 an impl method, a closure (the zone's, replayed last), a nested block" 'struct P { x; }
impl P { fn m(self): i64 { union U { x; } return 1; } }
var g = |x| { enum E { A, B } return x; };
fn f(): i64 { if (1 == 1) { struct Q { y; } } return 1; }
syscall(60, f());
' "error:<source>:2:28: a \`union\` declaration $IR a fn body
error:<source>:4:29: a \`struct\` declaration $IR a fn body
error:<source>:3:15: an \`enum\` declaration $IR a fn body"
one "NS7 a switch case, @unsafe in a fn" 'fn f(x): i64 { switch (x) { case 1: struct Q { y; } return 2; } return 1; }
fn g(): i64 { @unsafe { trait T { fn m(self): i64; } } return 1; }
syscall(60, f(1) + g());
' "error:<source>:1:37: a \`struct\` declaration $IR a fn body
error:<source>:2:25: a \`trait\` declaration $IR a fn body"
one "NS8 else, for, @unsafe at top level" 'var a = 1;
if (a == 2) { a = 3; } else { struct Q { y; } }
for (var i = 0; i < 1; i = i + 1) { enum E { A, B } }
@unsafe { union U { x; } }
syscall(60, a);
' "error:<source>:2:31: a \`struct\` declaration $IR a block
error:<source>:3:37: an \`enum\` declaration $IR a block
error:<source>:4:11: a \`union\` declaration $IR a block"
one "NS9 a generic fn at two instances: once" 'fn f<T>(x: T): T { enum E { A; } return x; }
syscall(60, f<i64>(1) + f<i32>(2));
' "error:<source>:1:20: an \`enum\` declaration $IR a fn body"
one "NS10 every kind in one body: one error each" 'struct P { x; }
fn f(): i64 {
    struct Q { y; }
    enum E { A, B }
    union U { x; }
    trait T { fn m(self): i64; }
    impl T for P { fn m(self): i64 { return 1; } }
    return 3;
}
syscall(60, f());
' "error:<source>:3:5: a \`struct\` declaration $IR a fn body
error:<source>:4:5: an \`enum\` declaration $IR a fn body
error:<source>:5:5: a \`union\` declaration $IR a fn body
error:<source>:6:5: a \`trait\` declaration $IR a fn body
error:<source>:7:5: an \`impl\` declaration $IR a fn body"
one "NS11 a derived struct in a fn body" 'include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
fn f(): i64 {
#derive(accessors)
struct Q { y; }
return 7;
}
syscall(60, f());
' "error:<source>:7:1: a \`struct\` declaration $IR a fn body"
one "NS12 an impl in a fn body, its method called" 'struct P { x; }
fn f(): i64 { impl P { fn g(self): i64 { return 1; } } var p = P { 1 }; return p.g(); }
syscall(60, f());
' "error:<source>:2:15: an \`impl\` declaration $IR a fn body"
one "NS13 no body: the block's own } is left" 'var a = 1;
if (a == 1) { struct Q }
syscall(60, a);
' "error:<source>:2:15: a \`struct\` declaration $IR a block"
one "NS14 --syntax-only: the same one error" "$(printf 'fn f(): i64 { struct Q { y; } return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`struct\` declaration $IR a fn body" --syntax-only
one "NC a const fn's body: the check's one refusal" 'const fn f(): i64 { struct Q { y; } return 1; }
syscall(60, f());
' "error:<source>:1:21: not in a const fn: its body takes var / const / assignment / if / elif / else / while / for / loop / do-while / return / break / continue and calls of const fns"

# ── U: a use of what a refused declaration names (6.7.15) ───────────────────────────────────────────────────
L='must come before the first top-level statement (line 2)'
one "U1 filed: struct literal of a refused struct" "$(printf 'var a = 1;\na = 2;\nstruct Q { y; }\nvar q = Q { 5 };\nsyscall(60, 0);\n')
" "error:<source>:3:1: a \`struct\` declaration $L"
one "U2 filed: E.B of a refused enum" "$(printf 'var a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, E.B);\n')
" "error:<source>:3:1: an \`enum\` declaration $L"
one "U3 filed: bare B of a refused enum" "$(printf 'var a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, B);\n')
" "error:<source>:3:1: an \`enum\` declaration $L"
one "U4 filed: a *Q parameter and its .y" "$(printf 'var a = 1;\na = 2;\nstruct Q { y; }\nfn f(q: *Q): i64 { return q.y; }\nsyscall(60, 0);\n')
" "error:<source>:3:1: a \`struct\` declaration $L"
UH='var a = 1;
a = 2;
'
one "UX1 the literal's variable, its .y" "${UH}struct Q { y; }
var q = Q { 5 };
var r: Q = Q { 6 };
syscall(60, q.y + r.y);
" "error:<source>:3:1: a \`struct\` declaration $L"
one "UX2 a parameter's field store and method" "${UH}struct Q { y; }
impl Q { fn m(self): i64 { return 1; } }
fn f(q: *Q): i64 { q.y = 1; return q.m(); }
fn g(): i64 { var q = Q { 5 }; q.y = 3; return q.y + q.m(); }
syscall(60, f(0) + g());
" "error:<source>:3:1: a \`struct\` declaration $L
error:<source>:4:1: an \`impl\` declaration $L"
one "UX3 enum annotations, sizeof, a *Q return, a union" "${UH}enum E { A, B }
struct Q { y; }
union U { x; y: i32; }
var e: E = E.A;
fn g(x: E): E { return x; }
fn h(): *Q { return 0; }
fn k(u: *U): i64 { return u.x; }
var s = sizeof(Q);
syscall(60, g(E.B) + e + s);
" "error:<source>:3:1: an \`enum\` declaration $L
error:<source>:4:1: a \`struct\` declaration $L
error:<source>:5:1: a \`union\` declaration $L"
one "UX4 a generic literal, a payload constructor" "${UH}struct G<T> { y: T; }
enum R: stack { Ok2(v); Err2(e); }
var q: G<i64> = G<i64> { 5 };
var t, v = Ok2(5);
syscall(60, q.y + v);
" "error:<source>:3:1: a \`struct\` declaration $L
error:<source>:4:1: an \`enum\` declaration $L"
one "UX5 a literal as a statement" "${UH}struct Q { y; }
fn g(): i64 { Q { 5 }; return 1; }
syscall(60, g());
" "error:<source>:3:1: a \`struct\` declaration $L"
one "UX6 in a fn body: its literal, members, variable" 'fn f(): i64 {
    struct Q { y; }
    enum E { A, B }
    var q = Q { 5 };
    return q.y + E.B + A;
}
syscall(60, f());
' "error:<source>:2:5: a \`struct\` declaration $IR a fn body
error:<source>:3:5: an \`enum\` declaration $IR a fn body"
printf 'struct Zq { y; }\nenum Ze { ZA, ZB }\nfn zf(): i64 { return 1; }\n' > "$D/inc_z.cyr"
printf 'syscall(39);\ninclude "%s"\nfn f(s: *Zq): i64 { return s.y; }\nvar z = Zq { 5 };\nsyscall(60, z.y + ZB + Ze.ZA + zf());\n' "$D/inc_z.cyr" > "$D/u7.cyr"
CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1; export CYRIUS_ALLOW_ABSOLUTE_INCLUDES
one "UX7 a refused inclusion's struct, enum and fn" "$(cat "$D/u7.cyr")
" "error:<source>:2:1: an include of a file that declares a \`struct\` ($D/inc_z.cyr:1) must come before the first top-level statement (line 1)"
unset CYRIUS_ALLOW_ABSOLUTE_INCLUDES
for u in 1 2 4; do
    case $u in
        1) us="$(printf 'var a = 1;\na = 2;\nstruct Q { y; }\nvar q = Q { 5 };\nsyscall(60, q.y);\n')"; uw='a `struct`';;
        2) us="$(printf 'var a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, E.B + B);\n')"; uw='an `enum`';;
        4) us="$(printf 'var a = 1;\na = 2;\nstruct Q { y; }\nfn f(q: *Q): i64 { return q.y; }\nsyscall(60, 0);\n')"; uw='a `struct`';;
    esac
    one "UX8 --syntax-only: U$u's shape, one error" "$us
" "error:<source>:3:1: $uw declaration $L" --syntax-only
done
one "UE1 exact: a name declared nowhere, an unknown type" "${UH}struct Q { y; }
var r: R = 0;
enum E { A, B }
syscall(60, C + B + zz);
" "error:<source>:3:1: a \`struct\` declaration $L
error:<source>:4:8: unknown type 'R' for variable 'r'
error:<source>:5:1: an \`enum\` declaration $L
error:<source>:6:15: undefined variable 'C' (missing include or enum?)
error:<source>:6:23: undefined variable 'zz' (missing include or enum?)"
one "UE2 exact: an untyped q.y in another fn" "${UH}struct Q { y; }
fn f(q: *Q): i64 { return q.y; }
fn g(q): i64 { return q.y; }
syscall(60, 0);
" "error:<source>:3:1: a \`struct\` declaration $L
error:<source>:5:26: no struct type in scope for 'q'; a '.field' access needs its struct declaration (missing include?)"
runs "UC control: the declarations before the statement" 'struct Q { y; }
enum E { A, B }
var a = 1;
a = 2;
var q = Q { 5 };
fn f(p: *Q): i64 { return p.y; }
syscall(60, q.y + f(&q) + E.B + B);
' 12

echo "decl_after_statement_named: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
