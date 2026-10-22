#!/bin/sh
# decl_after_statement_named.sh — a declaration after the first top-level statement is ONE error by name; an
# `async fn` there is a function (6.7.14); a declaration inside a fn body or a block is one error too, and a use
# of what a refused declaration names adds none (6.7.15); so is one in a body pass 2 never parses (6.7.17, D33).
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
# ONE LEVEL DOWN (6.7.15; issues/archived/2026-10-17-declaration-inside-block-or-fn-body-cascades.md). A `struct`, `enum`,
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
# THE OTHER KINDS ONE LEVEL DOWN (6.7.16; issues/archived/2026-10-18-mod-use-pub-inside-fn-body-or-block-named-by-token.md).
# `_decl_inner` took the five kinds 6.7.15's issue filed; a `mod`, `use`, `pub` / `public` in a fn body or a block
# reached PARSE_STMT's fallback: "unexpected mod", "unexpected pub'/'public" (the token table's two-spelling name),
# and a `pub fn` there added "fn 'g' is defined inside fn 'f'". Now every kind `_dl_kind` names, one error by the
# rule at the keyword; a `pub var` / `pub const` steps its marker alone (`_dl_pub_mark`: the declaration declares,
# its use is no "undefined variable"); a `pub const fn` steps to its body's `}` (`_dl_skip_at` stepped on to the
# NEXT `;`, module scope too); a derive's same-line step follows only a `struct` / `enum`, what `#derive` takes
# (`_dl_derived`: `use m.g; pub var x = 1;` on one line stepped the `pub` and, in a fn body, the body's `}`); a
# `pub use` alias is entered as reported like a `use` one (`_dl_quiet`).
#
#   NM  each of mod / use / pub var / pub const / pub fn / public fn / pub const fn / pub mod / pub use in a
#       top-level if block, a top-level while block and a fn body: one error; NM1-NM6 the filed repros verbatim;
#       NM7 / NM8 a pub var / const then used; NM9 the body parses on; NM10 use + pub on one line; NM11 a pub use
#       alias called; NM12 pub const fn; NM13 a generic's two instances; NM14 a switch case, a closure, an impl
#       method; NM15 a bare `pub }`; NM16 --syntax-only; NM17-NM19 the module-scope arm of the same steps;
#       NM20-NM22 two declarations on one line (`pub fn` + `pub fn`, `impl` + `fn`, in a body and a block): the
#       derive step follows a `struct` / `enum` only
#
#   (6.7.16, measured) the lane before it (b2053aff7) -> RED all 46 NM rows; the 107 rows before them green
#   `_decl_inner` back to its five kinds              -> RED NM (27 kind rows), NM1-NM16
#   `_dl_pub_mark` returns 0                          -> RED NM7 NM8 NM9 NM10 NM13 NM14 ("undefined variable 'x'")
#   `_dl_derived` without its struct / enum test      -> RED NM9 NM10 NM11 NM16 NM18 NM20 NM21 NM22 (the next
#                                                        declaration stepped as a derive's; "expected '}', got end
#                                                        of file")
#   (measured) the test as "ended at its `}`" (F4's    -> RED NM20 NM21 NM22 (a `pub fn` / `impl` ends at its `}`)
#   first cut, da0927adc)
#   `_dl_quiet` without its `pub use` step            -> RED NM11 NM19 ("undefined function 'g'")
#   `_dl_skip_at` without its `pub const fn` line     -> RED NM12 NM17 (the next statement's error lost)
#
#   PM  module scope (met in passing, 6.7.16): a late `pub var x = 5;` / `public var` stepped whole, so a use of x
#       was "undefined variable 'x'" — the marker is stepped alone there too (`_decl_late`'s `_dl_pub_mark`);
#       PM3 a `pub const` (pass 1's const prepass had registered it) the control
#   (measured) `_decl_late` without its `_dl_pub_mark` -> RED PM1 PM2
#
# ITS USES (6.7.15; issues/archived/2026-10-17-late-declaration-refusal-cascades-at-its-uses.md). The refused declaration
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
# THE USES THOSE STAND-DOWNS DID NOT REACH (6.7.16; issues/2026-10-18-refused-declaration-names-cascade-in-const-contexts-
# bounds-and-uninit.md). A refused enum's name in a const context (a case label, a const, an array size) was "unknown
# name 'E' in a const context" — and a top-level const's, swept at the end of pass 1, printed BEFORE the declaration's
# own error; a refused trait as a bound "its type argument does not implement trait 'Tr'"; `var q: Q;` (and any
# refused annotation with no initializer, `var q: Foo;`) "uninitialized variable not allowed"; a use parsed before the
# declaration (an earlier fn's `q: *Q`) "type 'Q' is declared after its use"; a refused inclusion's by-name `s: *Str`
# parameter "no struct type in scope for 's'". Now pass 1's tail walk enters each late declaration's names where
# PARSE_PROG will refuse it (`_dl_fill`, stepping the same tokens: `_dl_late_step`), a trait's name too; the const
# evaluator's unknown-name arms (`_ce_unk`) and the bound check (`_bnd_refd`) stand down for a refused name, counted
# and latched as the printed refusal is; the no-initializer refusal stands down after a refused annotation naming no
# type (`_decl_ann_refd` -> `_tup_ann_refd`), in sync; a by-name handle parameter whose struct a refused declaration
# declared is marked (`_tn_byname_refd`).
#
#   UF  UF1-UF6 the filed repros verbatim (1b: the declaration's error only — nothing printed before it); UF7 a bare
#       member in a const; UF8 case labels in a fn above the declaration; UF9 an array size after it, in sync;
#       UF10 an inner enum in its own body's labels / const; UF11 a bound in a fn above the trait; UF12 a zone
#       generic struct bounded by a late trait; UF13 `: Foo` / `: 5` / `: Foo<i64>` with no initializer, the next
#       statement's mistake reported; UF14 the zone and after a statement; UF15 a generic's two instances; UF16
#       control (`: i64`, `: *Foo` keep "uninitialized"); UF17 `s: Str`, a store and a method, a fn above the
#       include; UF18 --syntax-only of UF1-UF5's shapes (written UF18(n) below)
#   UE3 / UE4  exact: a const naming a name declared nowhere, a valid trait's unmet bound, a by-name `*Result`
#       parameter the inclusion did not declare — still reported
#
#   (6.7.16, measured) the lane before it (8bccee4d5) -> RED UF1-UF15 UF17 UF18(1-4) UE3 UE4 (22); UF16, UF18(5)
#                                                         (one error under --syntax-only already) and every row
#                                                         before them green
#   `_dl_fill` returns at once                         -> RED UF2 UF5 UF7 UF8 UF11 UF17 UF18(2)
#   `_ce_unk` without its stand-down                   -> RED UF1 UF2 UF7 UF8 UF9 UF10 UF18(1) UF18(2)
#   `_bnd_refd` returns 0                              -> RED UF3 UF11 UF12 UF18(3) UE3
#   `_dl_name_at` without the trait keyword            -> RED UF3 UF11 UF12 UF18(3) UE3
#   `_decl_ann_refd` returns 0                         -> RED UF4 UF13 UF14 UF15 UF18(4)
#   `_decl_ann_refd` never reading token 0             -> RED UF14 (the zone's first declaration)
#   `_tn_byname_refd` returns 0                        -> RED UF6 UF17 UE4
#   `_ce_unk` standing down for any name               -> RED UE3 ("unknown name 'Z'" silenced)
#   `_bnd_refd` standing down for any trait            -> RED UE3 (Tv's genuine bound silenced)
#   `_tn_byname_refd` marking any by-name handle       -> RED UE4 (`r.len` silenced)
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
error:<source>:1:38: undefined variable 'zz' (missing include or enum?)"
one "NS5 the block parses on, and the program" 'var a = 1;
if (a == 1) { struct Q { y; } a = zz; }
syscall(60, yy);
' "error:<source>:2:15: a \`struct\` declaration $IR a block
error:<source>:2:35: undefined variable 'zz' (missing include or enum?)
error:<source>:3:13: undefined variable 'yy' (missing include or enum?)"
one "NS6 an impl method, a closure (the zone's), a nested block: in source order" 'struct P { x; }
impl P { fn m(self): i64 { union U { x; } return 1; } }
var g = |x| { enum E { A, B } return x; };
fn f(): i64 { if (1 == 1) { struct Q { y; } } return 1; }
syscall(60, f());
' "error:<source>:2:28: a \`union\` declaration $IR a fn body
error:<source>:3:15: an \`enum\` declaration $IR a fn body
error:<source>:4:29: a \`struct\` declaration $IR a fn body"
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

# ── NM: one level down, the other kinds — `mod`, `use`, `pub` / `public` (6.7.16) ─────────────────────────────
NMKINDS='mod|mod m;|a `mod`
use|use m.g;|a `use`
pub-var|pub var x = 1;|a `pub`
pub-const|pub const C = 1;|a `pub`
pub-fn|pub fn g(): i64 { return 1; }|a `pub`
public-fn|public fn g(): i64 { return 1; }|a `public`
pub-const-fn|pub const fn g(): i64 { return 1; }|a `pub`
pub-mod|pub mod m;|a `pub`
pub-use|pub use m.g;|a `pub`'
printf '%s\n' "$NMKINDS" | while IFS='|' read -r k decl art; do
    [ -n "$k" ] || continue
    one "NM $k in a top-level if block" "${NHEAD}if (a == 1) { $decl }
syscall(60, a);
" "error:<source>:4:15: $art declaration $IR a block"
    one "NM $k in a top-level while block" "${NHEAD}while (a == 1) { $decl a = 2; }
syscall(60, a);
" "error:<source>:4:18: $art declaration $IR a block"
    one "NM $k in a fn body" "${NHEAD}fn f(): i64 { $decl return 1; }
syscall(60, f() + a);
" "error:<source>:4:15: $art declaration $IR a fn body"
done > "$D/nm.out"
cat "$D/nm.out"
pass=$((pass + $(grep -c '^  ok' "$D/nm.out" || true))); fail=$((fail + $(grep -c '^  FAIL' "$D/nm.out" || true)))

one "NM1 filed: mod in a fn body" "$(printf 'fn f(): i64 { mod m; return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`mod\` declaration $IR a fn body"
one "NM2 filed: use in a fn body" "$(printf 'fn f(): i64 { use m.g; return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`use\` declaration $IR a fn body"
one "NM3 filed: pub var in a fn body" "$(printf 'fn f(): i64 { pub var x = 1; return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`pub\` declaration $IR a fn body"
one "NM4 filed: mod in a top-level block" "$(printf 'var a = 1;\nif (a == 1) { mod m; }\nsyscall(60, a);\n')
" "error:<source>:2:15: a \`mod\` declaration $IR a block"
one "NM5 filed: pub fn in a fn body (it was two)" "$(printf 'fn f(): i64 { pub fn g(): i64 { return 1; } return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`pub\` declaration $IR a fn body"
one "NM6 filed: pub fn in a top-level block" "$(printf 'var a = 1;\nif (a == 1) { pub fn g(): i64 { return 1; } }\nsyscall(60, a);\n')
" "error:<source>:2:15: a \`pub\` declaration $IR a block"
one "NM7 pub var then a use of it: one error" 'fn f(): i64 { pub var x = 1; return x; }
syscall(60, f());
' "error:<source>:1:15: a \`pub\` declaration $IR a fn body"
one "NM8 public var / pub const then used, in a block" 'var a = 1;
if (a == 1) { public var x = 1; pub const C = 2; a = x + C; }
syscall(60, a);
' "error:<source>:2:15: a \`public\` declaration $IR a block
error:<source>:2:33: a \`pub\` declaration $IR a block"
one "NM9 the body parses on: each, then a mistake" 'fn f(): i64 { mod m; use m.g; pub var x = 1; public fn g2(): i64 { return 1; } return x + g2() + zz; }
syscall(60, f());
' "error:<source>:1:15: a \`mod\` declaration $IR a fn body
error:<source>:1:22: a \`use\` declaration $IR a fn body
error:<source>:1:31: a \`pub\` declaration $IR a fn body
error:<source>:1:46: a \`public\` declaration $IR a fn body
error:<source>:1:98: undefined variable 'zz' (missing include or enum?)"
one "NM10 use then pub on one line: no derive step" 'fn f(): i64 { use m.g; pub var x = 1; return x; }
syscall(60, f());
' "error:<source>:1:15: a \`use\` declaration $IR a fn body
error:<source>:1:24: a \`pub\` declaration $IR a fn body"
one "NM11 a pub use alias called: no undefined fn" 'fn f(): i64 { pub mod m; pub use m.g; return g(); }
syscall(60, f());
' "error:<source>:1:15: a \`pub\` declaration $IR a fn body
error:<source>:1:26: a \`pub\` declaration $IR a fn body"
one "NM12 pub const fn: the next statement is its own" 'fn f(): i64 { pub const fn g(): i64 { return 1; } return zz; }
syscall(60, f());
' "error:<source>:1:15: a \`pub\` declaration $IR a fn body
error:<source>:1:58: undefined variable 'zz' (missing include or enum?)"
one "NM13 a generic fn at two instances: once each" 'fn f<T>(x: T): T { pub var y = x; mod m; return y; }
syscall(60, f<i64>(1) + f<i32>(2));
' "error:<source>:1:20: a \`pub\` declaration $IR a fn body
error:<source>:1:35: a \`mod\` declaration $IR a fn body"
one "NM14 a switch case, a closure, an impl method" 'struct P { x; }
impl P { fn m(self): i64 { mod mm; return 1; } }
var g = |x| { pub var y = x; return y; };
fn f(x): i64 { switch (x) { case 1: use m.g; return 2; } return 1; }
syscall(60, f(1));
' "error:<source>:2:28: a \`mod\` declaration $IR a fn body
error:<source>:3:15: a \`pub\` declaration $IR a fn body
error:<source>:4:37: a \`use\` declaration $IR a fn body"
one "NM15 a pub with nothing after it: the block's } left" 'var a = 1;
if (a == 1) { pub }
syscall(60, a);
' "error:<source>:2:15: a \`pub\` declaration $IR a block"
one "NM16 --syntax-only: the same errors" 'fn f(): i64 { mod m; use m.g; pub var x = 1; return x; }
syscall(60, f());
' "error:<source>:1:15: a \`mod\` declaration $IR a fn body
error:<source>:1:22: a \`use\` declaration $IR a fn body
error:<source>:1:31: a \`pub\` declaration $IR a fn body" --syntax-only
one "NM17 module scope: pub const fn, the next statement's error" 'var a = 1;
a = 2;
pub const fn g(): i64 { return 1; }
syscall(60, zz);
' "error:<source>:3:1: a \`pub\` declaration $R (line 2)
error:<source>:4:13: undefined variable 'zz' (missing include or enum?)"
one "NM18 module scope: use then pub fn on one line" 'mod mm;
fn g(): i64 { return 1; }
mod;
syscall(39);
use mm.g; pub fn pg(): i64 { return 2; }
syscall(60, g() + pg());
' "error:<source>:5:1: a \`use\` declaration $R (line 4)
error:<source>:5:11: a \`pub\` declaration $R (line 4)"
one "NM19 module scope: a pub use alias called" 'mod mm;
fn g(): i64 { return 1; }
mod;
syscall(39);
pub use mm.g;
syscall(60, g());
' "error:<source>:5:1: a \`pub\` declaration $R (line 4)"
one "NM20 two pub fns on one line in a fn body" 'fn f(): i64 { pub fn g(): i64 { return 1; } pub fn h(): i64 { return 2; } return zz; }
syscall(60, f());
' "error:<source>:1:15: a \`pub\` declaration $IR a fn body
error:<source>:1:45: a \`pub\` declaration $IR a fn body
error:<source>:1:82: undefined variable 'zz' (missing include or enum?)"
one "NM21 an impl then a fn on one line in a fn body" 'struct P { x; }
fn f(): i64 { impl P { fn m(self): i64 { return 1; } } fn h(): i64 { return 2; } return zz; }
syscall(60, f());
' "error:<source>:2:15: an \`impl\` declaration $IR a fn body
error:<source>:2:56: fn 'h' is defined inside fn 'f'; define it at top level
error:<source>:2:89: undefined variable 'zz' (missing include or enum?)"
one "NM22 pub fn and public fn on one line in a block" 'var a = 1;
if (a == 1) { pub fn g(): i64 { return 1; } public fn h(): i64 { return 2; } a = zz; }
syscall(60, a);
' "error:<source>:2:15: a \`pub\` declaration $IR a block
error:<source>:2:45: a \`public\` declaration $IR a block
error:<source>:2:82: undefined variable 'zz' (missing include or enum?)"
one "PM1 module scope: pub var then used, one error" 'var a = 1;
a = 2;
pub var x = 5;
syscall(60, x);
' "error:<source>:3:1: a \`pub\` declaration $R (line 2)"
one "PM2 module scope: public var used in a fn, then a mistake" 'var a = 1;
a = 2;
public var x = 5;
fn f(): i64 { return x; }
syscall(60, f() + zz);
' "error:<source>:3:1: a \`public\` declaration $R (line 2)
error:<source>:5:19: undefined variable 'zz' (missing include or enum?)"
one "PM3 control: module scope pub const then used" 'var a = 1;
a = 2;
pub const C = 5;
const D = C + 1;
syscall(60, D + zz);
' "error:<source>:3:1: a \`pub\` declaration $R (line 2)
error:<source>:5:17: undefined variable 'zz' (missing include or enum?)"

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
error:<source>:6:13: undefined variable 'C' (missing include or enum?)
error:<source>:6:21: undefined variable 'zz' (missing include or enum?)"
one "UE2 exact: an untyped q.y in another fn" "${UH}struct Q { y; }
fn f(q: *Q): i64 { return q.y; }
fn g(q): i64 { return q.y; }
syscall(60, 0);
" "error:<source>:3:1: a \`struct\` declaration $L
error:<source>:5:26: no struct type in scope for 'q'; a '.field' access needs its struct declaration (missing include?)"

# ── UF: the uses 6.7.15's stand-downs did not reach (6.7.16) ─────────────────────────────────────────────────
FH='var a = 1;\na = 2;\n'   # the filing's H, for its repros verbatim
L5='must come before the first top-level statement (line 5)'
one "UF1 filed 1a: a case label E.A" "$(printf "${FH}enum E { A, B }\nfn g(x): i64 { switch (x) { case E.A: return 1; } return 0; }\nsyscall(60, g(1));\n")
" "error:<source>:3:1: an \`enum\` declaration $L"
one "UF2 filed 1b: a const and an array size, the declaration's error only" "$(printf "${FH}enum E { A, B }\nconst C = E.B;\nvar arr: i64[E.B];\nsyscall(60, C);\n")
" "error:<source>:3:1: an \`enum\` declaration $L"
one "UF3 filed 2: a refused trait as a bound" "$(printf "${FH}trait Tr { fn m(self): i64; }\nfn g<T: Tr>(x: T): i64 { return 1; }\nsyscall(60, g<i64>(1));\n")
" "error:<source>:3:1: a \`trait\` declaration $L"
one "UF4 filed 3: var q: Q; with no initializer" "$(printf "${FH}struct Q { y; }\nfn h(): i64 { var q: Q; return q.y; }\nsyscall(60, h());\n")
" "error:<source>:3:1: a \`struct\` declaration $L"
one "UF5 filed 4: a use before the declaration" "$(printf "${FH}fn g(q: *Q): i64 { return q.y; }\nstruct Q { y; }\nsyscall(60, 0);\n")
" "error:<source>:4:1: a \`struct\` declaration $L"
one "UF6 filed 5: a refused inclusion's by-name *Str parameter" "$(printf 'syscall(39);\ninclude "lib/str.cyr"\nfn f(s: *Str): i64 { return s.len; }\nsyscall(60, 3);\n')
" "error:<source>:2:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) must come before the first top-level statement (line 1)"
one "UF7 a bare member in a const, a const of that; then a mistake" "${UH}enum E { A, B }
const C = B;
const K = C + 1;
syscall(60, K + zz);
" "error:<source>:3:1: an \`enum\` declaration $L
error:<source>:6:17: undefined variable 'zz' (missing include or enum?)"
one "UF8 case labels in a fn above the declaration" "${UH}fn g(x): i64 { switch (x) { case E.A: return 1; case B: return 2; } return 0; }
enum E { A, B }
syscall(60, g(1));
" "error:<source>:4:1: an \`enum\` declaration $L"
one "UF9 an array size after it, in sync: the next statement's mistake" "${UH}enum E { A, B }
var arr: i64[E.B];
syscall(60, zz);
" "error:<source>:3:1: an \`enum\` declaration $L
error:<source>:5:13: undefined variable 'zz' (missing include or enum?)"
one "UF10 an inner enum in its body's case labels and const" 'fn f(x): i64 {
    enum E { A, B }
    switch (x) { case E.A: return 1; case B: return 2; }
    const C = E.B;
    return C;
}
syscall(60, f(1));
' "error:<source>:2:5: an \`enum\` declaration $IR a fn body"
one "UF11 the bound in a fn above the trait" "${UH}fn h(): i64 { return g<i64>(1); }
fn g<T: Tr>(x: T): i64 { return 1; }
trait Tr { fn m(self): i64; }
syscall(60, h());
" "error:<source>:5:1: a \`trait\` declaration $L"
one "UF12 a zone generic struct bounded by a late trait" "struct Bx<T: Tr> { v: T; }
${UH}trait Tr { fn m(self): i64; }
var b: Bx<i64> = Bx<i64> { 5 };
syscall(60, b.v);
" "error:<source>:4:1: a \`trait\` declaration must come before the first top-level statement (line 3)"
one "UF13 refused annotations with no initializer, in sync" 'fn f(): i64 { var q: Foo; var r: 5; var s: Foo<i64>; return zz; }
syscall(60, f());
' "error:<source>:1:22: unknown type 'Foo' for variable 'q'
error:<source>:1:34: expected a type for variable 'r', got number 5
error:<source>:1:44: unknown type 'Foo' for variable 's'
error:<source>:1:61: undefined variable 'zz' (missing include or enum?)"
one "UF14 the declaration zone and after a statement" "var q: Foo;
${UH}struct Q { y; }
var p: Q;
syscall(60, p.y + zz);
" "error:<source>:1:8: unknown type 'Foo' for variable 'q'
error:<source>:4:1: a \`struct\` declaration must come before the first top-level statement (line 3)
error:<source>:6:19: undefined variable 'zz' (missing include or enum?)"
one "UF15 a generic's two instances: once" 'fn f<T>(x: T): i64 { var q: Foo; return 1; }
syscall(60, f<i64>(1) + f<i32>(2));
' "error:<source>:1:29: unknown type 'Foo' for variable 'q'"
one "UF16 control: a type it still names keeps the error" 'fn f(): i64 { var q: i64; var p: *Foo; return zz; }
syscall(60, f());
' "error:<source>:1:25: uninitialized variable not allowed; use \`var X = 0;\` or initial value
error:<source>:1:35: unknown type 'Foo' as the target of pointer 'p'
error:<source>:1:38: uninitialized variable not allowed; use \`var X = 0;\` or initial value
error:<source>:1:47: undefined variable 'zz' (missing include or enum?)"
one "UF17 by-name Str: a value, a store and a method, a fn above" 'syscall(39);
fn h(t: *Str): i64 { return t.len; }
include "lib/str.cyr"
fn f(s: Str): i64 { return s.len; }
fn g(s: *Str): i64 { s.len = 3; return s.m(); }
syscall(60, 3);
' "error:<source>:3:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) must come before the first top-level statement (line 1)"
for u in 1 2 3 4 5; do
    case $u in
        1) us="$(printf "${FH}enum E { A, B }\nfn g(x): i64 { switch (x) { case E.A: return 1; } return 0; }\nsyscall(60, g(1));\n")"; uw="error:<source>:3:1: an \`enum\` declaration $L";;
        2) us="$(printf "${FH}enum E { A, B }\nconst C = E.B;\nvar arr: i64[E.B];\nsyscall(60, C);\n")"; uw="error:<source>:3:1: an \`enum\` declaration $L";;
        3) us="$(printf "${FH}trait Tr { fn m(self): i64; }\nfn g<T: Tr>(x: T): i64 { return 1; }\nsyscall(60, g<i64>(1));\n")"; uw="error:<source>:3:1: a \`trait\` declaration $L";;
        4) us="$(printf "${FH}struct Q { y; }\nfn h(): i64 { var q: Q; return q.y; }\nsyscall(60, h());\n")"; uw="error:<source>:3:1: a \`struct\` declaration $L";;
        5) us="$(printf "${FH}fn g(q: *Q): i64 { return q.y; }\nstruct Q { y; }\nsyscall(60, 0);\n")"; uw="error:<source>:4:1: a \`struct\` declaration $L";;
    esac
    one "UF18 --syntax-only: UF$u's shape, one error" "$us
" "$uw" --syntax-only
done
one "UE3 exact: a const of a name declared nowhere, a valid trait's bound" "trait Tv { fn m(self): i64; }
fn k<T: Tv>(x: T): i64 { return 1; }
fn g<T: Tr>(x: T): i64 { return 2; }
${UH}enum E { A, B }
trait Tr { fn m(self): i64; }
const C = Z.B;
var y = g<i64>(1);
var w = k<i64>(1);
syscall(60, E.A + y + w);
" "error:<source>:6:1: an \`enum\` declaration $L5
error:<source>:7:1: a \`trait\` declaration $L5
error:<source>:8:11: unknown name 'Z' in a const context
error:<source>:10:16: generic 'k': its type argument does not implement trait 'Tv'"
one "UE4 exact: a by-name Result parameter the inclusion did not declare" 'syscall(39);
include "lib/str.cyr"
fn h(s: *Str): i64 { return s.len; }
fn f(r: *Result): i64 { return r.len; }
syscall(60, 3);
' "error:<source>:2:1: an include of a file that declares a \`struct\` (lib/str.cyr:24) must come before the first top-level statement (line 1)
error:<source>:4:37: no struct type in scope for 'r'; a '.field' access needs its struct declaration (missing include?)"
runs "UC control: the declarations before the statement" 'struct Q { y; }
enum E { A, B }
var a = 1;
a = 2;
var q = Q { 5 };
fn f(p: *Q): i64 { return p.y; }
syscall(60, q.y + f(&q) + E.B + B);
' 12

# ── the five-leg rows (6.7.16, f16 FF5) ─────────────────────────────────────────────────────────────────────────
# `row5` / `ok5`: each row on the x86_64, PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1) compilers and the
# aarch64 / cx compilers built from this tree. `row5`: refused (rc != 0, no binary), the `error` / `warning` lines
# exactly <want>. `ok5`: compiles clean (no such line, a binary) on each, runs <exit> on x86_64. A compiler that does
# not build is a FAIL (a SKIP is not coverage).
LEGS="x86 pe macho"
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; LEGS="$LEGS a64"
else printf '  FAIL: %-46s\n' "src/main_aarch64.cyr did not build"; fail=$((fail+1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ]; then chmod +x "$D/cc_cx"; LEGS="$LEGS cx"
else printf '  FAIL: %-46s\n' "src/main_cx.cyr did not build"; fail=$((fail+1)); fi
N5=0
comp5() {   # <leg> <src> <out> [cc-arg]: rc in CRC
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$D/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$D/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
row5() {   # <id> <what> <source> <want-lines> [cc-arg]
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp5 "$leg" "$D/$1.cyr" "$o" "${5:-}"
        N5=$((N5 + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then printf '  FAIL: %s %s: %s: rc 0\n' "$1" "$leg" "$2"; fail=$((fail+1))
        elif ! cmp -s "$o.got" "$D/$1.want"; then
            printf '  FAIL: %s %s: %s: got %s lines: %s\n' "$1" "$leg" "$2" "$(wc -l < "$o.got")" "$(tr '\n' '|' < "$o.got")"; fail=$((fail+1))
        elif [ -s "$o" ] && [ -z "${5:-}" ]; then printf '  FAIL: %s %s: %s: refused, but a binary was written\n' "$1" "$leg" "$2"; fail=$((fail+1))
        else printf '  ok: %s %s: %s\n' "$1" "$leg" "$2"; pass=$((pass+1)); fi
    done
}
ok5() {   # <id> <what> <source> <exit>
    printf '%s' "$3" > "$D/$1.cyr"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp5 "$leg" "$D/$1.cyr" "$o"
        N5=$((N5 + 1))
        if [ "$CRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            printf '  FAIL: %s %s: %s: rc %s: %s\n' "$1" "$leg" "$2" "$CRC" "$(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"; fail=$((fail+1))
        elif [ "$leg" = x86 ]; then
            chmod +x "$o"; x=0; ( ulimit -c 0; timeout 30 "$o" ) > /dev/null 2>&1 || x=$?
            if [ "$x" = "$4" ]; then printf '  ok: %s %s: %s (exit %s)\n' "$1" "$leg" "$2" "$x"; pass=$((pass+1))
            else printf '  FAIL: %s %s: %s: exit %s, want %s\n' "$1" "$leg" "$2" "$x" "$4"; fail=$((fail+1)); fi
        else printf '  ok: %s %s: %s\n' "$1" "$leg" "$2"; pass=$((pass+1)); fi
    done
}
ZZ="undefined variable 'zz' (missing include or enum?)"
DH='include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/bayan.cyr"
'

# DV — 6.7.16 (issues/archived/2026-10-19-refused-declaration-derive-step-takes-enclosing-body-brace.md): A REFUSED DECLARATION'S
# DERIVE STEP TAKES ONLY WHAT THE DERIVE WROTE. `_dl_derived` stepped every token left on a refused struct's / enum's
# closing line when it began `fn` / `pub` — where a `#derive` writes its generated fns — so the user's own `fn h()`
# there was stepped as a derive's: below module scope through the enclosing fn body's or block's `}` ("expected '}',
# got end of file"), at module scope silently (h never defined). Now only when the preprocessor derived that type
# (`PP_DERIVE_LAST`), only the `[public] fn` units named `<Type>_..` / `_cy_..` (what PP_DERIVE_* writes, before the
# user's tail), each through its own braces. DV1 / DV2 the filed repros verbatim (two and three errors: the struct's,
# then `fn h`'s own "defined inside" / the `pub`'s, and `zz`; no EOF error); DV3 at module scope h is DEFINED (its
# body's `zz`, its call's arity); DV4 a refused `#derive(Serialize)` struct (Vec / f64 fields: the `_cy_` helpers) in
# a fn body and after a statement still steps its generated fns, a call of one quiet; DV5 an enum derive, the user's
# fn after its codecs refused as nested; DV6 a `fn Q_h` on a NON-derived refused struct's line is the user's.
# MUTATION LEDGER (2026-10-21, f16; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from that copy, so every leg's compiler carries the mutant):
#   the lane before it (b272c366a)                   -> RED DV1 DV2 DV3 DV5 DV6, 25 (DV4 green: the derive's own fns)
#   `_dl_derived` without its `PP_DERIVE_LAST` test  -> RED DV6, 5 (`fn Q_h` stepped as a derive's)
#   `_dl_dname` taking any name                      -> RED DV5, 5 (the user's `fn h` after the codecs stepped)
#   `_dl_dname` without its `_cy_` arm               -> RED DV4 DV5 Q3, 11 (the helpers parsed: "fn '_cy_vecdec_int'
#                                                       is defined inside fn 'f'", the walk stopped before the codecs)
row5 DV1 "filed: a struct then fn h on one line in a fn body" "$(printf 'fn f(): i64 { struct Q { y; } fn h(): i64 { return 1; } return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`struct\` declaration $IR a fn body
error:<source>:1:31: fn 'h' is defined inside fn 'f'; define it at top level"
row5 DV2 "filed: a struct then pub fn h on one line in a block" "$(printf 'var a = 1;\nif (a == 1) { struct Q { y; } pub fn h(): i64 { return 1; } }\nsyscall(60, a + zz);\n')
" "error:<source>:2:15: a \`struct\` declaration $IR a block
error:<source>:2:31: a \`pub\` declaration $IR a block
error:<source>:3:17: $ZZ"
row5 DV3 "module scope: struct Q {..} fn h(): h is defined" 'var a = 1;
a = 2;
struct Q { y; } fn h(): i64 { return zz; }
syscall(60, h(4));
' "error:<source>:3:1: a \`struct\` declaration $L
error:<source>:3:38: $ZZ
error:<source>:4: 'h' expects 0 arguments, got 1"
row5 DV4 "control: a refused derive's fns still stepped (a body, after a statement)" "${DH}fn f(): i64 {
#derive(Serialize)
struct Q { y; v: Vec<i64>; z: f64; }
return 7 + zz;
}
var a = 1;
a = 2;
#derive(Serialize)
pub struct R { y; v: Vec<f64>; }
var sb = 0;
R_to_json(0, sb);
syscall(60, a + f() + zz);
" "error:<source>:9:1: a \`struct\` declaration $IR a fn body
error:<source>:10:12: $ZZ
error:<source>:15:1: a \`pub\` declaration must come before the first top-level statement (line 13)
error:<source>:18:23: $ZZ"
row5 DV5 "an enum derive: its codecs stepped, the user's fn after them is not" "${DH}fn f(): i64 {
#derive(Serialize)
enum E { A; B; } fn h(): i64 { return 1; }
return E_from_json_str(0) + zz;
}
syscall(60, f());
" "error:<source>:9:1: an \`enum\` declaration $IR a fn body
error:<source>:9:18: fn 'h' is defined inside fn 'f'; define it at top level
error:<source>:10:29: $ZZ"
row5 DV6 "a fn named Q_h on a non-derived struct's line is the user's" "$(printf 'fn f(): i64 { struct Q { y; } fn Q_h(): i64 { return 1; } return zz; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`struct\` declaration $IR a fn body
error:<source>:1:31: fn 'Q_h' is defined inside fn 'f'; define it at top level
error:<source>:1:66: $ZZ"

# DV7 — 6.7.16 (the f16 review): ONLY THE NAMES THE DERIVE WROTE. `_dl_dname` took ANY `<Type>_..` / `_cy_..` on a DERIVED
# refused declaration's line as the derive's, so a user's `fn Q_h` there was stepped and its body never parsed (DV6 is
# the NON-derived struct). Now exactly the names that registration emitted (lex_pp.cyr PP_DERIVE_CODEC / PP_DERIVE_FAM):
# the codecs `<T>_to_json`, `<T>_from_json_str`, a struct's `<T>_from_json`; the accessors `<T>_<field>` /
# `<T>_set_<field>` for a field of the declaration; a `_cy_` helper only on the line that emitted it; each name once
# (a second `fn Q_set_y` is the user's duplicate). DV7 the review's dq.cyr verbatim (module scope, accessors); DV7b in a
# fn body (the user's `fn Q_h` refused as nested, not stepped); DV7c `fn Q_y` on a Serialize-only struct (no accessors);
# DV7d `fn Q_set_y` after the derive's own; DV7e a `_cy_json_skipval` on a later derive's line (the helper was the first
# one's), an enum's `E_from_json` (an enum codec writes none), `T_w` (no field w).
#   the lane before it (f33107668)                   -> RED DV7 DV7b DV7c DV7d DV7e, 25
#   `_dl_dname` without its PP_DERIVE_FAM tests      -> RED DV7c DV7e, 10 (`Q_y` and `_cy_json_skipval` stepped)
# DV5 / DV7-DV7e pin a column past a `#derive` expansion on the same line: since 6.7.17 the SOURCE line's column (the
# expansion map, issues/2026-10-21-diagnostics-print-internal-columns-carets-and-mangled-names.md, row 1), which no
# change to the generated fns moves; through 6.7.16 they were the expanded line's (`fn 'h'` at 9:651, `zz` at 10:2101).
#   `_dl_derived_fn` without `_dl_dv_once`           -> RED DV7d, 5 (the user's duplicate stepped)
row5 DV7 "review: a user's fn Q_h on a derived refused struct's line" "$(printf 'var a = 1;\na = 2;\n#derive(accessors)\nstruct Q { y; } fn Q_h(): i64 { return zz; }\nsyscall(60, Q_h(4));\n')
" "error:<source>:4:1: a \`struct\` declaration $L
error:<source>:4:40: $ZZ
error:<source>:5: 'Q_h' expects 0 arguments, got 1"
row5 DV7b "... in a fn body: the user's fn refused as nested" "$(printf 'fn f(): i64 {\n#derive(accessors)\nstruct Q { y; } fn Q_h(): i64 { return 1; } return zz; }\nsyscall(60, f());\n')
" "error:<source>:3:1: a \`struct\` declaration $IR a fn body
error:<source>:3:17: fn 'Q_h' is defined inside fn 'f'; define it at top level
error:<source>:3:52: $ZZ"
row5 DV7c "fn Q_y on a Serialize-only struct is the user's" "${DH}var a = 1;
a = 2;
#derive(Serialize)
struct Q { y; } fn Q_y(): i64 { return zz; }
syscall(60, Q_y(4));
" "error:<source>:10:1: a \`struct\` declaration must come before the first top-level statement (line 8)
error:<source>:10:40: $ZZ
error:<source>:11: 'Q_y' expects 0 arguments, got 1"
row5 DV7d "a second fn Q_set_y (the user's duplicate) is the user's" "$(printf 'var a = 1;\na = 2;\n#derive(accessors)\nstruct Q { y; } fn Q_set_y(): i64 { return zz; }\nsyscall(60, 0);\n')
" "error:<source>:4:1: a \`struct\` declaration $L
error:<source>:4:44: $ZZ"
row5 DV7e "a later line's _cy_ helper, an enum's E_from_json, T_w (no field)" "${DH}var a = 1;
a = 2;
#derive(Serialize)
struct Q { y; }
#derive(Serialize)
struct R { y; } fn _cy_json_skipval(): i64 { return zz; }
#derive(Serialize)
enum E { A; B; } fn E_from_json(): i64 { return zz2; }
#derive(accessors)
struct T { y; } fn T_w(): i64 { return zz3; }
syscall(60, 0);
" "error:<source>:10:1: a \`struct\` declaration must come before the first top-level statement (line 8)
error:<source>:12:1: a \`struct\` declaration must come before the first top-level statement (line 8)
error:<source>:12:53: $ZZ
error:<source>:14:1: an \`enum\` declaration must come before the first top-level statement (line 8)
error:<source>:14:49: undefined variable 'zz2' (missing include or enum?)
error:<source>:16:1: a \`struct\` declaration must come before the first top-level statement (line 8)
error:<source>:16:40: undefined variable 'zz3' (missing include or enum?)"

# UI — 6.7.16 (issues/archived/2026-10-19-use-before-inner-refused-declaration-still-reported.md): A USE READ BEFORE A DECLARATION
# REFUSED IN A FN BODY OR A BLOCK IS NO SECOND ERROR. `_decl_inner` entered the refused declaration's names (`_dl_names`)
# when PARSE_PROG parsed its body, in source order, so an earlier fn's `q: *Q` was "type 'Q' is declared after its use",
# `E.B` "undefined variable 'E'", and pass 1's bound `T: Tr` "unknown trait 'Tr'" — each printed before or beside the
# declaration's own error. Now `_dl_inner_fill` (before every pass-1 scan) walks the bodies and enters the names of
# each declaration `_decl_inner` will refuse; the bound's unknown-trait report (`_bnd_make`), `dyn Tr`'s "is not a
# trait" (`_dyn_chk`) and `impl Tr for P`'s "impl of undeclared trait" (`_tr_check_impl`) stand down for such a name,
# counted and latched as the printed refusal is. UI1-UI3 the filed repros verbatim (two errors each before); UI4 an
# impl method's body; UI5 the other bodies — a nested block in a fn, a `case` arm, a closure, a top-level block, a
# `pub struct`, a union, a bare member, a case label, a zone const and array size, a literal and sizeof; UI6 the
# trait's other uses: `dyn Tr`, `impl Tr for P`, a generic struct's bound; UI7 exact: a name declared nowhere is still
# reported, and a valid top-level struct of the inner one's name still resolves (its unknown field reported); UI8
# --syntax-only of UI3 (two before); UI9 exact: a zone declaration below its use is no inner one (module scope is not a
# body) — "declared after its use" still reported.
#   the lane before it (c5cf2a990)                   -> RED UI1-UI6 UI8, 35 (UI7 green)
#   `_tl_pass1` without `_dl_inner_fill`             -> RED UI1-UI6 UI8, 35
#   `_dl_inner_at` without the case arm's `:`        -> RED UI5, 5 (`case 1: struct R`'s R reported at its use)
#   `_dl_inner_fill` not marking a fn header's `{`   -> RED UI4, 5 (an impl method's body read as the impl's)
#   `_bnd_make` without its stand-down               -> RED UI3 UI6 UI8, 15 ("unknown trait 'Tr' in the bound")
#   `_dyn_chk` without its stand-down                -> RED UI6, 5 ("'Tr' is not a trait")
#   `_tr_check_impl` without its stand-down          -> RED UI6, 5 ("impl of undeclared trait 'Tr' for 'P'")
#   the fill at module scope too (no `vec_len` test) -> RED UI9, 5 (rc 1 and NO error: `Late` stood down silently)
#   (measured) a declaration's body read as a body   -> no row RED: only a declaration inside one differs, which is
#                                                       invalid there and refused before any use of its name
row5 UI1 "filed: an earlier fn's q: *Q, Q declared in a fn body" "$(printf 'fn g(q: *Q): i64 { return q.y; }\nfn f(): i64 { struct Q { y; } return 1; }\nsyscall(60, g(0) + f());\n')
" "error:<source>:2:15: a \`struct\` declaration $IR a fn body"
row5 UI2 "filed: an earlier fn's E.B, E declared in a fn body" "$(printf 'fn h(): i64 { return E.B; }\nfn f(): i64 { enum E { A, B } return 1; }\nsyscall(60, h() + f());\n')
" "error:<source>:2:15: an \`enum\` declaration $IR a fn body"
row5 UI3 "filed: a later generic's bound T: Tr, Tr declared in a fn body" "$(printf 'fn f(): i64 { trait Tr { fn m(self): i64; } return 1; }\nfn g<T: Tr>(x: T): i64 { return 1; }\nsyscall(60, g<i64>(1) + f());\n')
" "error:<source>:1:15: a \`trait\` declaration $IR a fn body"
row5 UI4 "an impl method's body" 'fn g(q: *Q): i64 { return q.y + zz; }
struct P { x; }
impl P { fn m(self): i64 { struct Q { y; } return 1; } }
syscall(60, g(0));
' "error:<source>:1:33: $ZZ
error:<source>:3:28: a \`struct\` declaration $IR a fn body"
row5 UI5 "the other bodies and uses: blocks, a case arm, a closure, pub, a union, consts" 'fn g(q: *Q, r: *R, s: *S, t: *T, u: *U, w: *W): i64 { return q.y + r.y + s.y + t.y + u.y + w.y + B + F.D; }
fn k(x): i64 { switch (x) { case E.A: return 1; } return G.H; }
const C = E.B;
var arr: i64[F.D];
fn m(): i64 { var q = Q { 5 }; return q.y + sizeof(Q); }
fn f(x): i64 {
    if (x == 1) { while (x == 0) { struct Q { y; } } }
    switch (x) { case 1: struct R { y; } }
    pub struct S { y; }
    union U { y; z: i32; }
    enum E { A, B }
    return 0;
}
var cl = |x| { struct T { y; } return x; };
var a = 1;
if (a == 1) { struct W { y; } enum F { C, D } }
fn h(): i64 { if (1 == 1) { enum G { H } } return 0; }
syscall(60, g(0, 0, 0, 0, 0, 0) + k(1) + C + m() + f(1) + h() + zz);
' "error:<source>:7:36: a \`struct\` declaration $IR a fn body
error:<source>:8:26: a \`struct\` declaration $IR a fn body
error:<source>:9:5: a \`pub\` declaration $IR a fn body
error:<source>:10:5: a \`union\` declaration $IR a fn body
error:<source>:11:5: an \`enum\` declaration $IR a fn body
error:<source>:14:16: a \`struct\` declaration $IR a fn body
error:<source>:16:15: a \`struct\` declaration $IR a block
error:<source>:16:31: an \`enum\` declaration $IR a block
error:<source>:17:29: an \`enum\` declaration $IR a fn body
error:<source>:18:65: $ZZ"
row5 UI6 "a refused inner trait's other uses: dyn, impl for, a struct bound" 'struct P { x; }
fn g(x: dyn Tr): i64 { return 1; }
impl Tr for P { fn m(self): i64 { return 1; } }
struct B<T: Tr> { v: T; }
fn f(): i64 { trait Tr { fn m(self): i64; } return 1; }
syscall(60, f() + zz);
' "error:<source>:5:15: a \`trait\` declaration $IR a fn body
error:<source>:6:19: $ZZ"
row5 UI7 "exact: a name declared nowhere, a valid top-level struct of the name" 'fn g(q: *Zq): i64 { return q.y; }
fn h(q: *Q): i64 { return q.w; }
fn f(): i64 { struct Q { y; } return 1; }
struct Q { z; }
syscall(60, g(0) + h(0) + f());
' "error:<source>:1:10: unknown type 'Zq' for parameter 'q'
error:<source>:2:30: unknown field 'w' on struct 'Q'
error:<source>:3:15: a \`struct\` declaration $IR a fn body"
row5 UI9 "exact: a zone declaration after its use is still reported" "$(printf 'var g: Late = 0;\nstruct Late { a; b; }\nfn f(): i64 { struct Q { y; } return 1; }\nsyscall(60, f());\n')
" "error:<source>:1:8: type 'Late' is declared after its use; declare it above the first use
error:<source>:3:15: a \`struct\` declaration $IR a fn body"
row5 UI8 "--syntax-only: UI3's shape" "$(printf 'fn f(): i64 { trait Tr { fn m(self): i64; } return 1; }\nfn g<T: Tr>(x: T): i64 { return 1; }\nsyscall(60, g<i64>(1) + f());\n')
" "error:<source>:1:15: a \`trait\` declaration $IR a fn body" --syntax-only

# UP — 6.7.16 (the f16 review): A PRE-WALK NAME STANDS DOWN ONLY FOR A DECLARATION THAT IS REPORTED. `_dl_inner_fill`
# enters the names of a declaration at a statement start in ANY body, and pass 2 refuses one only where it parses the
# body: a trait member's default no impl inherits, a bounded generic's base (a stub until instantiated) and a refused
# nested fn's stepped body are never parsed — so a use standing down for such a name counted an error no line said (rc 1
# and NOTHING printed: UP1 UP2 UP4 UP5), or the use's own report was lost (UP3: E's; UP6: Q's beside the nested fn's).
# Now the entry a stand-down answers through is marked (`_dl_pw_used`) and, once everything is parsed (`_dl_pw_end`),
# a marked name no reported declaration entered has its declaration reported at the keyword, in `_decl_inner`'s words,
# once (UP7: three uses of one enum, one line). UP9 control: the default inherited (the body parsed) — the one report,
# as before; UP11 `dyn Tr` / `impl Tr for P`; UP12 a kernel build's global replay (after the program; x86_64 ELF, a
# kernel target) reaches the late flush. 6.7.17 (D33, the DI block below): every such declaration is said, used or not —
# UP8 (unused: rc 0, exit 3 through 6.7.16) is refused, and UP10's unparsed Q is said beside the parsed one (in source
# order since ZR1 sorts the parse's reports; the flush printed last, so UP10 and DI8_4 compared a set until then).
#   the lane before it (6059d821c)                   -> RED UP1-UP7 UP11 UP12 (rc 1 with no line, or the decl's
#                                                       line missing), 41; UP8 UP9 UP10 green
#   `_dl_pw_flush` returns at once                   -> RED UP1-UP7 UP11 UP12, 41
#   `_dl_pw_late` returns at once                    -> RED UP12, 5 (rc 1, nothing printed)
row5 UP1 "a trait default no impl inherits: its struct used" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nfn g(q: *Q): i64 { return q.y; }\nfn main(): i64 { return g(0); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 UP2 "an uninstantiated bounded generic's base: its struct used" "$(printf 'fn gg<T: Show>(x: T): i64 { struct Q { y; } return 1; }\ntrait Show { fn s(self): i64; }\nfn g(q: *Q): i64 { return q.y; }\nfn main(): i64 { return g(0); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 UP3 "a trait default's enum: E.B beside an undefined zz" "$(printf 'trait T { fn d(self): i64 { enum E { A, B } return 1; } }\nfn h(): i64 { return E.B + zz; }\nvar r = h();\nsyscall(60, r);\n')
" "error:<source>:1:29: an \`enum\` declaration $IR a fn body
error:<source>:2:28: $ZZ"
row5 UP4 "a trait default's trait: a bound naming it" "$(printf 'trait T { fn d(self): i64 { trait Tr { fn m(self): i64; } return 1; } }\nfn g<U: Tr>(x: U): i64 { return 1; }\nfn main(): i64 { return g<i64>(1); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`trait\` declaration $IR a fn body"
row5 UP5 "a trait default's enum: a zone array size naming it" "$(printf 'var arr: i64[E.B];\ntrait T { fn d(self): i64 { enum E { A, B } return 1; } }\nfn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:2:29: an \`enum\` declaration $IR a fn body"
row5 UP6 "a refused nested fn's body: its struct used" "$(printf 'fn f(): i64 { fn g(): i64 { struct Q { y; } return 1; } return 0; }\nfn h(q: *Q): i64 { return q.y; }\nsyscall(60, h(0) + f());\n')
" "error:<source>:1:15: fn 'g' is defined inside fn 'f'; define it at top level
error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 UP7 "three uses of one unparsed enum: one line" "$(printf 'trait T { fn d(self): i64 { enum E { A, B } return 1; } }\nfn h(): i64 { return E.B + B + E.A; }\nvar r = h();\nsyscall(60, r);\n')
" "error:<source>:1:29: an \`enum\` declaration $IR a fn body"
row5 UP8 "unused: refused too (6.7.17, D33)" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 UP9 "control: the default inherited — its one report" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nstruct P { a; }\nimpl T for P { }\nfn g(q: *Q): i64 { return 1; }\nfn main(): i64 { var p = P { 1 }; return p.d() + g(0); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 UP10 "two bodies declaring Q, one parsed: both said (6.7.17)" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nfn a(): i64 { struct Q { y; } return 1; }\nfn g(q: *Q): i64 { return q.y; }\nsyscall(60, g(0) + a());\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body
error:<source>:2:15: a \`struct\` declaration $IR a fn body"
row5 UP11 "dyn Tr and impl Tr for P, Tr in a trait default" "$(printf 'struct P { x; }\nfn g(x: dyn Tr): i64 { return 1; }\nimpl Tr for P { fn m(self): i64 { return 1; } }\ntrait T { fn d(self): i64 { trait Tr { fn m(self): i64; } return 1; } }\nsyscall(60, 0);\n')
" "error:<source>:4:29: a \`trait\` declaration $IR a fn body"
one "UP12 a kernel build (x86_64 ELF): a global's E.B, replayed after the program" "$(printf 'kernel;\ntrait T { fn d(self): i64 { enum E { A, B } return 1; } }\nvar g = E.B;\nfn main(): i64 { return g; }\n')
" "error:<source>:2:29: an \`enum\` declaration $IR a fn body"

# UZ — 6.7.16 (issues/archived/2026-10-19-zone-const-context-names-late-refused-enum-before-its-refusal.md): A ZONE CONST
# CONTEXT NAMING A LATE (REFUSED) ENUM IS NO SECOND ERROR. A declaration-zone global's array size and an enum's value are
# evaluated during pass 1's zone scan, before the first statement — and so the late declarations' names (`_dl_fill`) —
# is known: "unknown name 'E' in a const context", printed BEFORE the enum's own error. Now `_ce_unk` holds the report
# of a name a later declaration declares (`_ce_zdefer`), latched as the printed one is, and `_ce_zflush` says it at the
# end of pass 1's tail walk unless a refused declaration declared the name. UZ1 / UZ2 the filed repros verbatim (two
# errors each before); UZ3 several zone uses, of two late enums (one error per enum); UZ4 control: a zone const and a
# zone #assert (one error, as before); UZ5 control: a VALID forward zone reference (no statement between) still says
# "unknown name 'E'" once — at its place, since 6.7.17's ZR1 prints the parse's reports in source order (UZ6: before the
# struct field's below it; it printed after them, at the zone's end, until then); UZ7 a name
# declared nowhere is reported in place; UZ8 a held report is said before an unmatched `}` stops the compile; UZ9
# --syntax-only of UZ1.
#   the lane before it (8c5be2e81)                   -> RED UZ1 UZ2 UZ3 UZ9 (the early "unknown name 'E'"), UZ6
#                                                       (its old order), 25
#   `_ce_unk` without `_ce_zdefer`                   -> RED UZ1 UZ2 UZ3 UZ6 UZ9, 25
#   `_ce_zflush` saying every held report            -> RED UZ1 UZ2 UZ3 UZ9, 20 (the late enum's name said)
#   `_ce_zflush` dropping every held report          -> RED UZ5 UZ6 UZ8, 15 (the valid forward reference unsaid:
#                                                       rc 1, its one error lost)
#   `_tl_stray_brace` without its `_ce_zflush`       -> RED UZ8, 5
row5 UZ1 "filed: a zone array size naming a late enum" "$(printf 'var arr: i64[E.B];\nvar a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, 0);\n')
" "error:<source>:4:1: an \`enum\` declaration must come before the first top-level statement (line 3)"
row5 UZ2 "filed: a zone enum value naming a late enum" "$(printf 'enum F { X = E.B }\nvar a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, 0);\n')
" "error:<source>:4:1: an \`enum\` declaration must come before the first top-level statement (line 3)"
row5 UZ3 "several zone uses of two late enums" 'var arr: i64[E.B];
var b: i64[E.A];
enum F { X = E.B, Y = Q.A }
var a = 1;
a = 2;
enum E { A, B }
enum Q { A }
syscall(60, zz);
' "error:<source>:6:1: an \`enum\` declaration must come before the first top-level statement (line 5)
error:<source>:7:1: an \`enum\` declaration must come before the first top-level statement (line 5)
error:<source>:8:13: $ZZ"
row5 UZ4 "control: a zone const and a zone #assert" "$(printf 'const C = E.B;\n#assert E.A == 0\nvar a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, 0);\n')
" "error:<source>:5:1: an \`enum\` declaration must come before the first top-level statement (line 4)"
row5 UZ5 "control: a valid forward zone reference is said once" "$(printf 'var arr: i64[E.B];\nenum E { A, B }\nvar a = 1;\nsyscall(60, zz);\n')
" "error:<source>:1:14: unknown name 'E' in a const context
error:<source>:4:13: $ZZ"
row5 UZ6 "control: ... at its place among the pass-1 reports" "$(printf 'var arr: i64[E.B];\nstruct P { x: Zt; }\nenum E { A, B }\nvar a = 1;\nsyscall(60, zz);\n')
" "error:<source>:1:14: unknown name 'E' in a const context
error:<source>:2:15: unknown type 'Zt' for struct field 'x'
error:<source>:5:13: $ZZ"
row5 UZ7 "control: a name declared nowhere is said in place" "$(printf 'var arr: i64[Z.B];\nstruct P { x: Zt; }\nvar a = 1;\na = 2;\nsyscall(60, zz);\n')
" "error:<source>:1:14: unknown name 'Z' in a const context
error:<source>:2:15: unknown type 'Zt' for struct field 'x'
error:<source>:5:13: $ZZ"
row5 UZ8 "a held report is said before an unmatched } stops the compile" "$(printf 'var arr: i64[E.B];\nenum E { A, B }\nvar a = 1;\n}\nsyscall(60, zz);\n')
" "error:<source>:1:14: unknown name 'E' in a const context
error:<source>:4:1: unmatched '}' at module scope"
row5 UZ9 "--syntax-only: UZ1's shape" "$(printf 'var arr: i64[E.B];\nvar a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, 0);\n')
" "error:<source>:4:1: an \`enum\` declaration must come before the first top-level statement (line 3)" --syntax-only

# DI — 6.7.17 (issues/2026-10-21-inner-declaration-in-a-body-pass-two-never-parses-never-refused.md): AN INNER
# DECLARATION IS REFUSED WHEREVER IT SITS (the user's decision D33, 2026-10-22). Pass 2 refuses one where it parses the
# body; a trait default no impl inherits, a bounded generic's base (a fn or a method, a stub until instantiated) and a
# stepped body (a refused nested fn's, a refused impl's method) are never parsed, so a declaration there compiled (6.7.16:
# said only once a use of its name stood down). Now the pre-walk records every declaration it meets in a body — every
# kind `_decl_inner` refuses — (`_dl_pw_rec`), and the end-of-parse flush (`_dl_pw_flush`, once the top-level PARSE_PROG
# and the global replay have both ended) says each at its keyword, in `_decl_inner`'s words; `_dl_in_say` says a token
# once (`_ce_err_dup`), so one pass 2 reported is not said again. DI1 / DI2 the filed repros verbatim (rc 0, exit 3
# before); DI3 the name also used (one line); DI4 / DI5 the parsed twins — the inherited default and the plain fn —
# unchanged; DI6 a bodied default and a bounded generic (fn and method) with no inner declaration still compile; DI7
# every kind; DI8 every never-parsed body (a bounded generic method, a closure and a block in one, an overridden default
# beside an inherited one, a refused nested fn's body, a refused late impl's method; a default inherited by two impls:
# once; DI8_8-DI8_10, the review's: a refused inner trait's / `pub trait`'s default, in a fn body and a block); DI9 a
# `#derive`d enum: the enum, never the derive's `public fn` codecs; DI10 --syntax-only; DI11 a kernel build
# (x86_64 ELF): the flush waits for the global replay, so a global's closure is said in the replay's words, once. DI12
# (the review's): a fn header whose `(` never closes — the `{` after it opens the fn's body, not a block.
# MUTATION LEDGER (2026-10-22, measured: a scratch copy of the tree with the one change, its 2-stage cycc, this gate):
#   the lane before it (e65604d5d)                   -> RED 111: DI1 DI2 DI7 (all ten) DI8_1-DI8_6 DI9a DI10 DI11a UP8
#                                                       UP10 (rc 0, or the unparsed declaration unsaid)
#   `_dl_pw_flush` returns at once                   -> RED 157: DI1-DI3 DI7 DI8_1-DI8_6 DI9a DI10 DI11a UP1-UP8
#                                                       UP10-UP12
#   the flush printing without `_dl_in_say`'s dedup  -> RED 286: every declaration pass 2 reported said twice (N, NS,
#                                                       NM, NC, UI, DV, UP9, DI4, DI5, DI8_7, DI9b, DI11b, ...)
#   `_dl_inner_at` recording the four named kinds    -> RED 30: DI7 impl, mod, use, pub-var, pub-fn, public-fn
#   `_dl_pw_rec` without its `_dl_pw_skip` test      -> RED 15: DV5 DI9a DI9b (the derive's `public fn` codecs said)
#   the merged tree before the window (`_dl_pw_rec`  -> RED 9 (its compiler on the x86_64 / PE / Mach-O legs): DI8_8
#     skipping from the declaration's keyword)            DI8_9 DI8_10, the inner trait's default's struct unsaid
#   `_dl_pw_end` flushing before the replay          -> RED 1: DI11b ("not inside a block": the walk's words)
#   `_dl_pw_late` returns at once                    -> RED 2: UP12 DI11a (a kernel build never flushes: rc 0)
#   the merged tree's `_dl_inner_fill` (a fn header's -> RED 3 (its compiler on the x86_64 / PE / Mach-O legs): DI12
#     `{` matched only at its `(`'s depth)                 ("... not inside a block")
row5 DI1 "filed: a trait default no impl inherits" 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
' "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 DI2 "filed: an uninstantiated bounded generic" 'trait Show { fn s(self): i64; }
fn gg<T: Show>(x: T): i64 { struct Q { y; } return 1; }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
' "error:<source>:2:29: a \`struct\` declaration $IR a fn body"
row5 DI3 "the unparsed declaration's name also used: one line" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nfn g(q: *Q): i64 { return q.y; }\nfn main(): i64 { var q = Q { 5 }; return g(&q); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 DI4 "control: the default inherited (parsed): once" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nstruct P { k; }\nimpl T for P { }\nfn main(): i64 { var p = P { 1 }; return p.d(); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 DI5 "control: a plain fn" "$(printf 'fn h(): i64 { struct Q { y; } return 1; }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:15: a \`struct\` declaration $IR a fn body"
ok5 DI6 "control: a bodied default and a bounded generic, no declaration" 'trait Show { fn s(self): i64; }
trait Tq { fn d(self): i64 { var a = 1; if (a == 1) { a = 2; } return a; } }
fn gg<T: Show>(x: T): i64 { var c = 0; while (c < 3) { c = c + 1; } return c; }
struct Pq { k; }
impl Pq { fn m<T: Show>(self, v: T): i64 { var w = |y| y + 1; return w(1); } }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
' 3
# kind label | the declaration | its article+keyword as reported
DIKINDS='enum|enum E { A, B }|an `enum`
union|union U { x; y: i32; }|a `union`
trait|trait Tr { fn m(self): i64; }|a `trait`
impl|impl P { fn g(self): i64 { return 1; } }|an `impl`
mod|mod mm;|a `mod`
use|use mm.f;|a `use`
pub-var|pub var x = 1;|a `pub`
pub-fn|pub fn pf(): i64 { return 1; }|a `pub`
public-fn|public fn pf(): i64 { return 1; }|a `public`
pub-struct|pub struct Q { y; }|a `pub`'
printf '%s\n' "$DIKINDS" > "$D/dikinds"
while IFS='|' read -r k decl art; do
    [ -n "$k" ] || continue
    row5 "DI7_$k" "every kind: $k in an unparsed default" "struct P { k; }
trait T { fn d(self): i64 { $decl return 1; } }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
" "error:<source>:2:29: $art declaration $IR a fn body"
done < "$D/dikinds"
row5 DI8_1 "a bounded generic method, never instantiated" "$(printf 'trait Show { fn s(self): i64; }\nstruct Q { k; }\nimpl Q { fn m<T: Show>(self, v: T): i64 { struct R { y; } return 1; } }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:3:43: a \`struct\` declaration $IR a fn body"
row5 DI8_2 "a closure in a bounded generic" "$(printf 'trait Show { fn s(self): i64; }\nfn gg<T: Show>(x: T): i64 { var c = |y| { struct R { y; } return y; }; return 1; }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:2:43: a \`struct\` declaration $IR a fn body"
row5 DI8_3 "a block in an unparsed default" "$(printf 'trait T { fn d(self): i64 { if (1) { enum E { A } } return 1; } }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:38: an \`enum\` declaration $IR a fn body"
row5 DI8_4 "an overridden default beside an inherited one" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } fn e(self): i64 { enum E { A } return 2; } }\nstruct P { k; }\nimpl T for P { fn d(self): i64 { return 5; } }\nfn main(): i64 { var p = P { 1 }; return p.e(); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body
error:<source>:1:75: an \`enum\` declaration $IR a fn body"
row5 DI8_5 "a refused nested fn's body, unused" "$(printf 'fn f(): i64 { fn g(): i64 { struct Q { y; } return 1; } return 0; }\nsyscall(60, f());\n')
" "error:<source>:1:15: fn 'g' is defined inside fn 'f'; define it at top level
error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 DI8_6 "a refused late impl's method" "$(printf 'struct P { k; }\nvar a = 1;\na = 2;\nimpl P { fn m(self): i64 { struct Q { y; } return 1; } }\nsyscall(60, a);\n')
" "error:<source>:4:1: an \`impl\` declaration $R (line 3)
error:<source>:4:28: a \`struct\` declaration $IR a fn body"
row5 DI8_7 "a default inherited by two impls: once" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nstruct P { k; }\nstruct P2 { k; }\nimpl T for P { }\nimpl T for P2 { }\nfn main(): i64 { var p = P { 1 }; var q = P2 { 2 }; return p.d() + q.d(); }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body"
row5 DI8_8 "review: a refused inner trait's default (fn body)" "$(printf 'fn f(): i64 { trait T2 { fn d(self): i64 { struct Q { y; } return 1; } } return 0; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`trait\` declaration $IR a fn body
error:<source>:1:44: a \`struct\` declaration $IR a fn body"
row5 DI8_9 "review: a refused inner trait's default (top-level block)" "$(printf 'var a = 1;\nif (a == 1) { trait T2 { fn d(self): i64 { struct Q { y; } return 1; } } }\nsyscall(60, a);\n')
" "error:<source>:2:15: a \`trait\` declaration $IR a block
error:<source>:2:44: a \`struct\` declaration $IR a fn body"
row5 DI8_10 "review: a refused inner pub trait's default" "$(printf 'fn f(): i64 { pub trait T2 { fn d(self): i64 { struct Q { y; } return 1; } } return 0; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`pub\` declaration $IR a fn body
error:<source>:1:48: a \`struct\` declaration $IR a fn body"
row5 DI9a "a derived enum in an unparsed default: the enum, not its codecs" "${DH}trait T { fn d(self): i64 {
#derive(Serialize)
enum E { A; B; }
return 1;
} }
syscall(60, 3);
" "error:<source>:9:1: an \`enum\` declaration $IR a fn body"
row5 DI9b "a derived enum in a top-level block: the enum, not its codecs" "${DH}var a = 1;
if (a == 1) {
#derive(Serialize)
enum E { A; B; }
}
syscall(60, a);
" "error:<source>:10:1: an \`enum\` declaration $IR a block"
row5 DI10 "--syntax-only: the filed repro" "$(printf 'trait T { fn d(self): i64 { struct Q { y; } return 1; } }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:29: a \`struct\` declaration $IR a fn body" --syntax-only
row5 DI12 "review: a fn header whose ( never closes: its body is a fn body" "$(printf 'fn f(: i64 { struct Q { y; } return 1; }\nfn main(): i64 { return 3; }\nvar r = main();\nsyscall(60, r);\n')
" "error:<source>:1:6: expected identifier, got ':'
error:<source>:1:14: a \`struct\` declaration $IR a fn body"
one "DI11a a kernel build (x86_64 ELF): an unparsed default" "$(printf 'kernel;\ntrait T { fn d(self): i64 { struct Q { y; } return 1; } }\nfn main(): i64 { return 0; }\n')
" "error:<source>:2:29: a \`struct\` declaration $IR a fn body"
one "DI11b a kernel build: a global's closure, in the replay's words" "$(printf 'kernel;\nvar g = |x| { struct Q { y; } return x; };\nfn main(): i64 { return 3; }\n')
" "error:<source>:2:15: a \`struct\` declaration $IR a fn body"

# UM — 6.7.17 (met in lane fea FA1 while making a `use` one line, the same class; issues/2026-10-21-directive-line-tails-
# unread-use-without-path-late-private.md): A REFUSED `mod` STEPS WHAT `_tl_mod` READS, `mod [NAME] [;]`. `_dl_skip_at`
# stepped it to the next `;`, so a `;`-less `mod m` after the first statement or in a fn body took the next line with
# it, that line's own error unreported; and the inner-declaration pre-walk held its header open to the next `;`, so a
# refused `struct Q` in the next block went unfilled ("type 'Q' is declared after its use"). UM1 / UM2 the refusal and
# the next line's `zz`; UM3 the pre-walk; UM4 `pub mod m;` in a fn body (the `pub` refusal, then `zz`).
#   `_dl_skip_at` without `_dl_skip_mod` (to the next `;`)          -> RED UM1 UM2, 10 (the `zz` lost)
#   `_dl_inner_fill` holding a `mod` header open again               -> RED UM3, 5 ("type 'Q' is declared after its use")
row5 UM1 "a ';'-less mod after the first statement: the next line's zz" "$(printf 'var a = 1;\na = 2;\nmod m\na = a + zz;\nsyscall(60, a);\n')
" "error:<source>:3:1: a \`mod\` declaration must come before the first top-level statement (line 2)
error:<source>:4:9: $ZZ"
row5 UM2 "a ';'-less mod in a fn body: the next line's zz" "$(printf 'fn f(): i64 { mod m\nreturn zz; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`mod\` declaration $IR a fn body
error:<source>:2:8: $ZZ"
row5 UM3 "a ';'-less mod in a body, then a block's refused struct used above it" 'fn h(q: *Q): i64 { return q.y; }
fn f(): i64 {
    mod m
    if (1 == 1) { struct Q { y; } var q = Q { 5 }; return q.y + h(&q); }
    return 0;
}
syscall(60, f());
' "error:<source>:3:5: a \`mod\` declaration $IR a fn body
error:<source>:4:19: a \`struct\` declaration $IR a fn body"
row5 UM4 "pub mod m; in a fn body: the pub refusal, then zz" "$(printf 'fn f(): i64 { pub mod m; return zz; }\nsyscall(60, f());\n')
" "error:<source>:1:15: a \`pub\` declaration $IR a fn body
error:<source>:1:33: $ZZ"

# The five-leg rows' floor: a row or a leg lost reads RED, never green. (6.7.17's merge of lanes fea and feg left two
# assignments, 330 then 220; the later one ruled, so 130 lost row-legs read green.)
F5FLOOR=370
[ "$N5" -ge "$F5FLOOR" ] || { printf '  FAIL: %-46s\n' "the five-leg rows ran $N5 row-legs (floor $F5FLOOR)"; fail=$((fail+1)); }

echo "decl_after_statement_named: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
