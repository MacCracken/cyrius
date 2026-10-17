#!/bin/sh
# tests/gates/frontend/slice_position_refused.sh — 6.7.8 (C2-6a)
#
# SLICES: ELEMENT STORES, AND EVERY POSITION OUTSIDE A FN-LOCAL `var` REFUSED BY NAME (the user's
# decision, 2026-10-10: slices stay locals — "a slice PARAMETER and a slice declared in the
# declaration zone" refused by name; a top-level slice after the first statement keeps compiling;
# the checked mode checks "slice reads AND writes").
#
# Before 6.7.8 a slice element could be read (`s[i]`, bounds-checked since v5.8.15) but not stored —
# `s[1] = 9;` was "cannot subscript 's'". It is now stored through lib/slice.cyr's
# `_slice_idx_addr(&s, i, sizeof(T))`, which checks i against s.len as the reads do: out of range is
# "slice bounds violation", exit 134, in every mode. And `[T]` / `slice<T>` anywhere but a fn-local
# `var` (and the post-statement top-level one) met a generic parse error — a parameter `expected ')',
# got identifier 'u8'` (with an arity cascade at a forward call), a return / field / `*[T]`
# `expected identifier, got '['`, a declaration-zone global `expected '=', got identifier 'u8'`,
# `slice<T>` "unknown type 'slice'", a slice of slices `expected ']'`, a type argument "unknown type
# 'enum'". (issues/2026-10-09-slice-type-outside-fn-local-misdiagnosed.md)
#
#   SR  the issue's repro file VERBATIM: its two declaration-zone lines, each its one named refusal
#       (2 error lines, at 11 and 12); its parameter snippet verbatim: one error (no `s.len` cascade)
#   S1  a parameter `[T]` / `slice<T>` (also in a method, with a default, mid-list with a FORWARD call —
#       pass 1 steps the whole `[..]`, so no arity cascade); S1p `*[T]` / `*slice<T>` as a parameter,
#       a local, a return, a field, a declaration-zone global and a slice's pointer element
#   S2  a return `[T]` / `slice<T>`, and as a multi-value element; S3 a struct / union field;
#       S4 a declaration-zone global; S6 a slice of slices (four spellings), a type argument (`g<[u8]>`,
#       `Box<[u8]>`), a tuple element `slice<T>` (named as `[T]` was) — each exactly one error line
#   K   kept: the post-statement top-level slice compiles and runs (the helper API); a program's own
#       `struct slice` as a parameter / pointer type; K3 (6.7.14, D3 (a)) `g<slice<u8>>(0)` and `Box<slice<u8>>`
#       are refused as `[u8]` is (they ran the i64 base), a program's own `struct slice<T>` stays a type argument
#       K2b-K2f (6.7.11, the user's decision (b), 2026-10-13: a declared `struct slice` wins everywhere,
#       the built-in stays reachable as `[T]`; issues/archived/2026-10-10-user-struct-named-slice-shadowed-in-locals.md)
#       a FN-LOCAL `var x: slice` names the program's struct too — it was the built-in 16-byte slot
#       ("no struct type in scope for 'x'", "uninitialized variable not allowed"): K2b the filed repro
#       verbatim builds and runs as the same program with the struct renamed (`= 0` on a 24-byte struct is a
#       null handle, 6.7.10: both 139); K2c `var x: slice;` is the 24-byte struct (14, the issue's row); K2d
#       a generic `struct slice<T>`'s locals `slice<i64>` / `slice<Pt>` are its instances; K2e (kept: it compiled
#       before) a field and both global zones of the type, with a `[u8]` local in the same file still the built-in;
#       K2f (review) the flip side: a fn-local `slice<u8>` there is the struct, so the built-in's `.len` on it is
#       refused (it compiled through 6.7.10); K2g the `[u8]` respelling runs (14);
#       tests/tcyr/crossos/user_struct_named_slice.tcyr runs the shapes on every fork
#       K2h (6.7.14) a program's own GENERIC `struct slice<T>` as a `*slice<i64>` and a by-value `slice<i64>`
#       parameter: exit 5 — the one row that reaches `_sl_ann_at`'s FINDSTRUCT test (K2's bare `slice` has no
#       `<`, so `_sl_ann_at` answers 0 before it; issues/2026-10-14-slice-position-k2-misses-sl-ann-at-findstruct.md)
#   X   --syntax-only (cyrius lint's pre-pass) reports a slice parameter, once (a grammar refusal)
#   R12 a captured slice subscripted in a closure (read, store); R13 a struct / u128 element store;
#       R13b `OP=` on an f64 / f32 / bool element (the slice read is an untyped word); R10 a non-bool
#       into a [bool] element; R7 `s[1][2] = 5` — each exactly one error line
#   E   `OP=` agrees with `s[i] = s[i] op v` on a negative [i8] / [i16] / [i32] element (`>>=`, `/=`,
#       `%=`, `>>>=`): the compound loads the element as `s[i]` reads it (sign-extended since C2-6c —
#       the values are slice_signed_read.sh's)
#   T   the default-mode trap on every leg (x86 plain / CYRIUS_IR=3, aarch64 qemu, cx, PE wine): a store,
#       an `OP=` and a for step past the end, a negative index — exit 134, "slice bounds violation"
#   W   tests/tcyr/crossos/slice_subscript_write.tcyr compiles with no warning; --syntax-only silent;
#       then on x86 (plain, CYRIUS_IR=3, CYRIUS_IR=1, CYRIUS_DCE=1), aarch64 (qemu, `nospawn`: qemu-user
#       cannot exec the binary for the SPAWN group — the T rows cover the trap there), cx (cxvm; the
#       file leaves the SPAWN group out) and PE (wine; the SPAWN group runs); Wh on x86 under the
#       bounds-checked mode (CYRIUS_BOUNDS=1), where the SPAWN children print the mode's line: the file
#       passes in both modes (C2 review: under the mode it failed 8 checks — the SPAWN rows expected
#       only the default-mode line)
#
# MUTATION LEDGER (scratch trees, each its 2-stage mutant cycc, this gate run from that tree as
# CYCC=<mutant>; 2026-10-10):
#   M21   `_slice_idx_addr` without its two checks (lib/slice.cyr) -> RED T1a-T3e (15: every leg) and
#         Wa Wb Wf Wg We (the value file's SPAWN group; Wc / Wd run without it)
#   M28   pass 1 steps one token of a `[T]` parameter (`_param_type_step_q`) -> RED S1c (the arity error)
#   MSK   `_sl_slice` drops the element (the width only) -> RED R10 R7 R13b1-R13b3 R13b1w E T1a-T3e W0 W0s
#         Wa-Wg (every store refused as a struct element)
#   MSL   `_slice_lw` unmasked (the kind bits read as the width) -> RED S1a E W0 W0s Wa-Wg (no getter)
#   MSE   `_slice_sub_addr` keeps an integer's sign -> RED E (E1: `OP=` sign-extends, the read does not)
#         — C2-6c made the sign the rule for both; its inverse (the sign dropped) is slice_signed_read.sh's MS2
#   MIR   the store's frame base unmarked for the IR pass -> RED Wb (CYRIUS_IR=3: a variable index)
#   MR12  the captured-slice refusal dropped -> RED R12a R12b (the untyped-name text)
#   MR13b the float / bool `OP=` refusal dropped -> RED R13b1-R13b3 (they compile)
#   MSK2  `_sl_ann_skip` steps one token of a `[..]` -> RED SR1 SR2 S1a S1c S1d S1e S1p1 S1p3 S1p4 S1p6
#         S1p7 S2a S2c S3a S3c S4a S6a S6d S6e S6f X1 (the cascades)
#   MSW   (6.7.11; a one-edit copy of the tree, its compiler built by the fixed one, this gate run from it with
#         CYCC= it) `_sl_word_builtin` without its FINDSTRUCT test -> RED K2b K2c K2d (the built-in slot again: each
#         refused, as through 6.7.10) and K2f (compiled: the built-in's `.len`, review); K1-K4, K2e and K2g green
#         (K2e declares no fn-local of the type: it compiled before)
#   MSA   (6.7.14; a one-edit copy of the tree, its 2-stage mutant cycc, this gate run from it with CYCC= it)
#         `_sl_ann_at` without its FINDSTRUCT test -> RED K2h (the pointer and the by-value parameter each
#         refused as the built-in slice); every other row green (K2's bare `slice` never reaches the test)
#   MK3   (6.7.14; a one-edit copy of the tree, its 2-stage mutant cycc, this gate run from it with CYCC= it)
#         `_targ_bad_gen` without its slice arm -> RED K3 K3b (refused, but as "unknown type 'slice'")
#   (C2 review) the value file before it (its SPAWN rows expected only the default-mode line) -> RED Wh
#         (8 checks)
#   the C2-5 compiler (+ the IR=3 slice-read repair; before this bite) -> RED SR S1-S6 X R12 R13 R13b
#         R10 R7 E T1-T3 (a b e) W0 W0s Wa Wb Wf Wg We; K1-K4 green (nothing that compiled changes); Tc Td
#         Wc Wd pass (those legs' compilers are built from this tree's src)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=slice_position_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
wine_run() {   # <dir> <exe> <stderr file>: run under the private prefix; sets got
    got=0
    (cd "$1" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2" > "$1/$2.out" 2> "$3") || got=$?
}
HAVE_WINE=0
if command -v wine > /dev/null 2>&1; then HAVE_WINE=1
else echo "  SKIP Te / We: the PE legs — wine not installed"; skips=$((skips + 1)); fi
HAVE_QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then HAVE_QEMU=1
else echo "  SKIP Tc / Wc: the aarch64 legs — qemu-aarch64 not installed"; skips=$((skips + 1)); fi

# refused <name> <fragment> <what> <body> [flag]: compile fails with exactly one error line holding the fragment
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" ${5:-} < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want the refusal \"$2\""
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want exactly 1: $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|')"
    elif grep '^error' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"; fi
}
# exits <name> <want> <what> <body>: compiles and exits <want>
exits() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

SL='include "lib/slice.cyr"\n'
SP1="a slice cannot be a parameter (6.7.8: slices are fn-locals)"
SPP="a pointer to a slice is not a type (6.7.8: slices are fn-locals)"
SRT="a slice cannot be a return type (6.7.8: slices are fn-locals)"
SFD="a slice cannot be a struct or union field (6.7.8: slices are fn-locals)"
SGZ="a slice cannot be declared in the declaration zone (6.7.8: slices are fn-locals)"
SEL="a slice cannot be the element of a slice (6.7.8: slices are fn-locals)"
STA="a slice cannot be a type argument (6.7.8: slices are fn-locals)"

# ── SR: the issue's repro, verbatim ──────────────────────────────────────────────────────────────
RP="$ROOT/docs/development/issues/repros/2026-10-09-slice-type-outside-fn-local-misdiagnosed.cyr"
if [ ! -f "$RP" ]; then bad "SR1: $RP missing"
else
    rc=0; timeout 60 "$CC" < "$RP" > "$T/sr1.bin" 2> "$T/sr1.err" || rc=$?
    n=$(grep -c '^error' "$T/sr1.err" || true)
    l11=$(grep -c "^error:<source>:11:9: $SGZ" "$T/sr1.err" || true)
    l12=$(grep -c "^error:<source>:12:9: $SGZ" "$T/sr1.err" || true)
    if [ "$rc" -ne 0 ] && [ "$n" -eq 2 ] && [ "$l11" -eq 1 ] && [ "$l12" -eq 1 ]; then
        ok "SR1: the repro file: \`var GS: [u8] = 0;\` and \`var GT: slice<u8> = 0;\` each refused by name, nothing else"
    else bad "SR1: rc $rc, $n error lines: $(grep '^error' "$T/sr1.err" | head -3 | tr '\n' '|')"; fi
fi
refused sr2 "$SP1" "SR2: the issue's parameter snippet verbatim (\`s.len\` in the body: no cascade)" \
    'include "lib/slice.cyr"\nfn f(s: [u8]): i64 { return s.len; }\nfn main(): i64 { return 0; }\nsyscall(60, main());\n'

# ── S1 / S1p: parameters, and pointers to slices ────────────────────────────────────────────────
refused s1a "$SP1" "S1a: \`s: [u8]\` with s[i], s[i] = v, s.ptr in the body" \
    "${SL}fn f(s: [u8]): i64 { s[0] = 1; return s[1] + s.ptr; }\nsyscall(60, 0);\n"
refused s1b "$SP1" "S1b: \`s: slice<u8>\`" "${SL}fn f(s: slice<u8>): i64 { return s.len; }\nsyscall(60, 0);\n"
refused s1c "$SP1" "S1c: a middle parameter, called BEFORE the definition (pass 1 counts 3: no arity cascade)" \
    "${SL}fn main(): i64 { return f(1, 0, 2); }\nfn f(a, s: [u8], b): i64 { return a + b; }\nsyscall(60, main());\n"
refused s1d "$SP1" "S1d: an impl method's parameter" "${SL}impl i64 { fn m(self, s: [u8]): i64 { return 0; } }\nsyscall(60, 0);\n"
refused s1e "$SP1" "S1e: with a default (\`s: [u8] = 0\`: the default is stepped, nothing more reported)" "${SL}fn f(s: [u8] = 0): i64 { return 0; }\nsyscall(60, 0);\n"
# 6.7.8 — a trait member's signature (parsed since dyn D2) refuses a slice by name too: it met
# "expected identifier, got '['" / "unknown type 'slice'" (the issue's residual, found at integration)
refused s1t1 "$SP1" "S1t1: a trait required member's slice parameter \`s: [u8]\`" "${SL}trait T { fn m(self, s: [u8]): i64; }\nsyscall(60, 0);\n"
refused s1t2 "$SP1" "S1t2: a trait member's \`s: slice<u8>\`" "${SL}trait T { fn m(self, s: slice<u8>): i64; }\nsyscall(60, 0);\n"
refused s1t3 "$SRT" "S1t3: a trait member's slice return \`: [u8]\`" "${SL}trait T { fn m(self): [u8]; }\nsyscall(60, 0);\n"
refused s1t4 "$SRT" "S1t4: a trait member's \`: slice<u8>\` return" "${SL}trait T { fn m(self): slice<u8>; }\nsyscall(60, 0);\n"
refused s1t5 "$SP1" "S1t5: a trait DEFAULT member's slice parameter" "${SL}trait T { fn m(self, s: [u8]): i64 { return 0; } }\nsyscall(60, 0);\n"
refused s1t6 "$SPP" "S1t6: a trait member's \`p: *[u8]\`" "${SL}trait T { fn m(self, p: *[u8]): i64; }\nsyscall(60, 0);\n"
refused s1p1 "$SPP" "S1p1: \`p: *[u8]\` parameter" "${SL}fn f(p: *[u8]): i64 { return slice_len(p); }\nsyscall(60, 0);\n"
refused s1p2 "$SPP" "S1p2: \`p: *slice<u8>\` parameter" "${SL}fn f(p: *slice<u8>): i64 { return 0; }\nsyscall(60, 0);\n"
refused s1p3 "$SPP" "S1p3: a local \`var q: *[u8]\`" "${SL}fn f(): i64 { var b: i64[2]; var q: *[u8] = &b; return 0; }\nsyscall(60, f());\n"
refused s1p4 "$SPP" "S1p4: a return \`: *[u8]\`" "${SL}fn f(): *[u8] { return 0; }\nsyscall(60, 0);\n"
refused s1p5 "$SPP" "S1p5: a field \`p: *slice<u8>\`" "${SL}struct H { p: *slice<u8>; n; }\nsyscall(60, 0);\n"
refused s1p6 "$SPP" "S1p6: a declaration-zone global \`*[u8]\`" "${SL}var GP: *[u8] = 0;\nsyscall(60, 0);\n"
refused s1p7 "$SPP" "S1p7: a slice's pointer element \`[*[u8]]\`" "${SL}fn f(): i64 { var t: [*[u8]] = 0; return 0; }\nsyscall(60, f());\n"

# ── S2 / S3 / S4 / S6 ───────────────────────────────────────────────────────────────────────────
refused s2a "$SRT" "S2a: \`fn f(): [u8]\`" "${SL}fn f(): [u8] { var s: [u8] = 0; return s; }\nsyscall(60, 0);\n"
refused s2b "$SRT" "S2b: \`fn f(): slice<u8>\`" "${SL}fn f(): slice<u8> { return 0; }\nsyscall(60, 0);\n"
refused s2c "$SRT" "S2c: a multi-value element \`(i64, [u8])\`" "${SL}fn f(): (i64, [u8]) { return (0, 0); }\nsyscall(60, 0);\n"
refused s2d "$SRT" "S2d: a multi-value element \`(slice<u8>, i64)\`" "${SL}fn f(): (slice<u8>, i64) { return (0, 0); }\nsyscall(60, 0);\n"
refused s3a "$SFD" "S3a: a struct field \`s: [u8]\` (h.s used: no cascade)" \
    "${SL}struct H { s: [u8]; n; }\nfn f(h: *H): i64 { return h.s + h.n; }\nsyscall(60, 0);\n"
refused s3b "$SFD" "S3b: a struct field \`s: slice<u8>\`" "${SL}struct H { n; s: slice<u8>; }\nsyscall(60, 0);\n"
refused s3c "$SFD" "S3c: a union field" "${SL}union U { s: [u8]; n; }\nsyscall(60, 0);\n"
refused s4a "$SGZ" "S4a: a declaration-zone \`var GS: [u8] = 0;\` (slice_len(&GS) used: no cascade)" \
    "${SL}var GS: [u8] = 0;\nfn f(): i64 { return slice_len(&GS); }\nsyscall(60, f());\n"
refused s4b "$SGZ" "S4b: a declaration-zone \`slice<i64>\`" "${SL}var GT: slice<i64> = 0;\nsyscall(60, 0);\n"
refused s6a "$SEL" "S6a: \`[[u8]]\`" "${SL}fn f(): i64 { var t: [[u8]] = 0; return 0; }\nsyscall(60, f());\n"
refused s6b "$SEL" "S6b: \`slice<slice<u8>>\`" "${SL}fn f(): i64 { var t: slice<slice<u8>> = 0; return 0; }\nsyscall(60, f());\n"
refused s6c "$SEL" "S6c: \`[slice<u8>]\`" "${SL}fn f(): i64 { var t: [slice<u8>] = 0; return 0; }\nsyscall(60, f());\n"
refused s6d "$SEL" "S6d: \`slice<[u8]>\`" "${SL}fn f(): i64 { var t: slice<[u8]> = 0; return 0; }\nsyscall(60, f());\n"
refused s6e "$STA" "S6e: a type argument \`g<[u8]>(0)\`" "${SL}fn g<T>(x: T): i64 { return 0; }\nfn f(): i64 { return g<[u8]>(0); }\nsyscall(60, f());\n"
refused s6f "$STA" "S6f: a type argument \`Box<[u8]>\`" "${SL}struct Box<T> { v: T; }\nfn f(): i64 { var b: Box<[u8]>; return 0; }\nsyscall(60, f());\n"
refused s6g "a tuple element is i64, f64 or bool, not a slice" "S6g: a tuple element \`slice<u8>\` (as \`[u8]\` is)" \
    "${SL}fn f(t: (i64, slice<u8>)): i64 { return 0; }\nsyscall(60, 0);\n"

# ── K: what keeps compiling ─────────────────────────────────────────────────────────────────────
exits k1 9 "K1: a top-level slice after the first statement (the helper API)" \
    "${SL}fn noop(): i64 { return 0; }\nvar BK: u8[4];\nnoop();\nvar GS: [u8] = 0;\nvar GT: slice<u8> = 0;\nslice_set(&GS, &BK, 4);\nslice_set(&GT, &BK, 5);\nsyscall(60, slice_len(&GS) + slice_len(&GT));\n"
exits k2 7 "K2: a program's own \`struct slice\` as a parameter type and a pointer target" \
    'struct slice { a; }\nfn f(p: *slice): i64 { return p.a; }\nfn g(s: slice): i64 { return s.a; }\nvar B: i64[2];\nstore64(&B, 7);\nsyscall(60, f(&B));\n'
# K2b-K2e (6.7.11): the program's own `struct slice` in a fn-local annotation
KR="$ROOT/docs/development/issues/repros/2026-10-10-user-struct-named-slice-shadowed-in-locals.cyr"
if [ ! -f "$KR" ]; then bad "K2b: $KR missing"
else
    sed 's/slice/slyce/g' "$KR" > "$T/k2b_ren.cyr"
    rc=0; timeout 60 "$CC" < "$KR" > "$T/k2b.bin" 2> "$T/k2b.err" || rc=$?
    rr=0; timeout 60 "$CC" < "$T/k2b_ren.cyr" > "$T/k2b_ren.bin" 2> /dev/null || rr=$?
    if [ "$rc" -ne 0 ]; then bad "K2b: the filed repro verbatim: rc $rc: $(grep '^error' "$T/k2b.err" | head -1)"
    elif [ "$rr" -ne 0 ]; then bad "K2b: the renamed control did not build (rc $rr)"
    else
        chmod +x "$T/k2b.bin" "$T/k2b_ren.bin"
        g1=0; timeout 10 "$T/k2b.bin" > /dev/null 2>&1 || g1=$?
        g2=0; timeout 10 "$T/k2b_ren.bin" > /dev/null 2>&1 || g2=$?
        if [ "$g1" -eq "$g2" ]; then ok "K2b: the filed repro verbatim builds and runs as the renamed program (exit $g1 both: \`= 0\` is a null handle)"
        else bad "K2b: the repro exits $g1, the renamed program $g2"; fi
    fi
fi
exits k2c 14 "K2c: a fn-local \`var x: slice;\` is the program's 24-byte struct (the issue's 14)" \
    'include "lib/syscalls.cyr"\nstruct slice { a; b; c; }\nfn f(s: *slice): i64 { return s.c; }\nfn main(): i64 {\n    var x: slice;\n    x.a = 5;\n    var B: i64[3];\n    store64(&B + 16, 9);\n    return f(&B) + x.a;\n}\nvar rc = main();\nsyscall(60, rc);\n'
exits k2d 65 "K2d: a generic \`struct slice<T>\`'s locals \`slice<i64>\` / \`slice<Pt>\` are its instances (5 + 2 + 30 + 4 + 24)" \
    'struct Pt { x; y; }\nstruct slice<T> { a: T; n; }\nfn main(): i64 {\n    var x: slice<i64>;\n    x.a = 5;\n    x.n = 2;\n    var y: slice<Pt>;\n    y.a.x = 30;\n    y.a.y = 4;\n    return x.a + x.n + y.a.x + y.a.y + sizeof(slice<Pt>);\n}\nsyscall(60, main());\n'
exits k2e 65 "K2e: a field and both global zones of the program's slice type; a \`[u8]\` local beside them is the built-in" \
    "${SL}struct slice { a; b; c; }\nstruct H { s: slice; k; }\nvar GZ: slice = slice { 0, 0, 0 };\nfn noop(): i64 { return 0; }\nfn main(): i64 {\n    var h: H;\n    h.s.b = 7;\n    h.k = 1;\n    GZ.c = 20;\n    var bk: u8[4];\n    store8(&bk + 2, 3);\n    var u: [u8] = 0;\n    slice_set(&u, &bk, 4);\n    return h.s.b + h.k + GZ.c + u[2] + slice_len(&u) + sizeof(slice);\n}\nnoop();\nvar GP: slice = slice { 0, 0, 0 };\nGP.a = 6;\nsyscall(60, main() + GP.a);\n"
# K2f / K2g (6.7.11 review): the flip side of decision (b) — with the program's own `struct slice`
# declared, a fn-local `slice<u8>` is that struct, so the built-in's `.len` on it stops compiling
# (base 5fb211da: 14); the built-in respelled `[u8]` gives the 14.
refused k2f "unknown field 'len' on struct 'slice'" "K2f: \`struct slice\` declared: a fn-local \`slice<u8>\`'s \`.len\` is refused (the built-in is \`[u8]\` there)" \
    "${SL}struct slice { a; b; c; }\nfn f(): i64 {\n    var buf[16];\n    var s: slice<u8> = 0;\n    slice_of(&s, &buf, 7);\n    return slice_len(&s) + s.len;\n}\nsyscall(60, f());\n"
exits k2g 14 "K2g: ... respelled \`var s: [u8] = 0;\` it is the built-in slice (7 + 7)" \
    "${SL}struct slice { a; b; c; }\nfn f(): i64 {\n    var buf[16];\n    var s: [u8] = 0;\n    slice_of(&s, &buf, 7);\n    return slice_len(&s) + s.len;\n}\nsyscall(60, f());\n"
# K2h (6.7.14): a program's own GENERIC `struct slice<T>` as a pointer parameter and a by-value parameter —
# the shape that reaches `_sl_ann_at`'s FINDSTRUCT test (K2's bare `slice` is answered before it: no `<`).
# (issues/2026-10-14-slice-position-k2-misses-sl-ann-at-findstruct.md)
exits k2h 5 "K2h: a generic \`struct slice<T>\` as a \`*slice<i64>\` and a by-value \`slice<i64>\` parameter" \
    'struct slice<T> { a: T; n; }\nfn f(p: *slice<i64>): i64 { return p.a; }\nfn g(s: slice<i64>): i64 { return s.n; }\nvar B: i64[2];\nstore64(&B, 5);\nstore64(&B + 8, 2);\nsyscall(60, f(&B));\n'
# K3 (6.7.14, the user's D3 (a), 2026-10-16): the built-in slice's word form as a type argument is refused as
# `[u8]` is (S6e / S6f) — it ran the i64 base (8). A program's own generic `struct slice<T>` stays a type
# argument (K3c). (issues/2026-10-10-unknown-generic-name-accepted-as-type-argument.md)
refused k3 "$STA" "K3: \`g<slice<u8>>(0)\` refused as \`g<[u8]>(0)\` is (it ran the i64 base: 8)" \
    "${SL}fn g<T>(x: T): i64 { return sizeof(T); }\nfn f(): i64 { return g<slice<u8>>(0); }\nsyscall(60, f());\n"
refused k3b "$STA" "K3b: \`var b: Box<slice<u8>>;\` refused as \`Box<[u8]>\` is (it declared the base Box)" \
    "${SL}struct Box<T> { v: T; n; }\nfn f(): i64 { var b: Box<slice<u8>>; b.n = 4; return b.n; }\nsyscall(60, f());\n"
exits k3c 16 "K3c: a program's own generic \`struct slice<T>\` as a type argument, \`g<slice<i64>>(0)\` (16)" \
    "struct slice<T> { a: T; n; }\nfn g<T>(x): i64 { return sizeof(T); }\nfn f(): i64 { return g<slice<i64>>(0); }\nsyscall(60, f());\n"
exits k4 12 "K4: fn-local \`[T]\` / \`slice<T>\` / \`[*T]\` / \`[u128]\` / \`[T]\` at a generic T still declare" \
    "${SL}fn h<T>(): i64 { var s: [T] = 0; return 2; }\nfn f(): i64 { var a: [u8] = 0; var b: slice<i32> = 0; var c: [*u8] = 0; var d: [u128] = 0; return 10 + h<i64>(); }\nsyscall(60, f());\n"

# ── X: --syntax-only ────────────────────────────────────────────────────────────────────────────
refused x1 "$SP1" "X1: --syntax-only (cyrius lint) reports a slice parameter, once" \
    "${SL}fn f(s: [u8]): i64 { return s.len; }\nsyscall(60, 0);\n" --syntax-only

# ── R12 / R13 / R13b / R10 / R7: the store's refusals ───────────────────────────────────────────
SB="${SL}include \"lib/alloc.cyr\"\nfn f(): i64 {\n    var b: i64[8];\n    var s: [u8] = 0;\n    slice_set(&s, &b, 4);\n"
SE='    return 0;\n}\nalloc_init();\nsyscall(60, f());\n'
R12="cannot subscript 's': a slice is a fn-local - a closure cannot subscript a captured slice"
refused r12a "$R12" "R12a: a captured slice read in a closure (\`|i| s[i]\`)" "${SB}    var k = |i| s[i];\n${SE}"
refused r12b "$R12" "R12b: a captured slice stored in a closure" "${SB}    var k = |i| { s[i] = 1; return 0; };\n${SE}"
R13="cannot subscript 's': a slice element store takes an integer, f64, f32, bool or pointer element"
refused r13a "$R13" "R13a: a struct element store" \
    "${SL}struct P { a; b; }\nfn f(): i64 { var b: i64[8]; var s: [P] = 0; slice_set(&s, &b, 2); s[1] = 5; return 0; }\nsyscall(60, f());\n"
refused r13b "$R13" "R13b: a u128 element store" \
    "${SL}fn f(): i64 { var b: i64[8]; var s: [u128] = 0; slice_set(&s, &b, 2); s[1] = 5; return 0; }\nsyscall(60, f());\n"
R13B="a compound assignment on an f64, f32 or bool slice element is not supported"
refused r13b1 "$R13B" "R13b1: [f64] s[1] += 1.5 (no further warning)" \
    "${SL}fn f(): i64 { var b: i64[8]; var s: [f64] = 0; slice_set(&s, &b, 2); s[1] += 1.5; return 0; }\nsyscall(60, f());\n"
refused r13b2 "$R13B" "R13b2: [f32] s[1] -= x, in a for step" \
    "${SL}fn f(): i64 { var b: i64[8]; var s: [f32] = 0; var x: f32 = 0.5; slice_set(&s, &b, 2); for (var i = 0; i < 1; s[0] -= x) { i = i + 1; } return 0; }\nsyscall(60, f());\n"
refused r13b3 "$R13B" "R13b3: [bool] s[1] |= true" \
    "${SL}fn f(): i64 { var b: i64[8]; var s: [bool] = 0; slice_set(&s, &b, 2); s[1] |= true; return 0; }\nsyscall(60, f());\n"
if grep -q '^warning' "$T/r13b1.err"; then bad "R13b1w: a warning after the refusal: $(grep '^warning' "$T/r13b1.err" | head -1)"
else ok "R13b1w: no warning after the refusal (the operand parses as the element's kind)"; fi
refused r10 "cannot store a value that is not a bool into a bool element of 's'" "R10: [bool] s[1] = 1" \
    "${SL}fn f(): i64 { var b: i64[8]; var s: [bool] = 0; slice_set(&s, &b, 2); s[1] = 1; return 0; }\nsyscall(60, f());\n"
refused r7 "a subscript's result is an element, not an array" "R7: s[1][2] = 5" "${SB}    s[1][2] = 5;\n${SE}"

# ── E: `OP=` loads the element as `s[i]` reads it ───────────────────────────────────────────────
# Each compound is computed both ways on the same negative element; equal results exit 0, else the
# first disagreeing row's number.
cat > "$T/e.cyr" <<'EOF'
include "lib/slice.cyr"
var BA: i64[2];
var BB: i64[2];
fn pair8(): i64 {
    var a: [i8] = 0;
    var b: [i8] = 0;
    slice_set(&a, &BA, 4);
    slice_set(&b, &BB, 4);
    a[0] = 0 - 3; b[0] = 0 - 3; a[0] >>= 1; b[0] = b[0] >> 1;
    if (load8(&BA) != load8(&BB)) { return 1; }
    a[1] = 0 - 7; b[1] = 0 - 7; a[1] /= 2; b[1] = b[1] / 2;
    if (load8(&BA + 1) != load8(&BB + 1)) { return 2; }
    a[2] = 0 - 7; b[2] = 0 - 7; a[2] %= 4; b[2] = b[2] % 4;
    if (load8(&BA + 2) != load8(&BB + 2)) { return 3; }
    a[3] = 0 - 8; b[3] = 0 - 8; a[3] >>>= 1; b[3] = b[3] >>> 1;
    if (load8(&BA + 3) != load8(&BB + 3)) { return 4; }
    return 0;
}
fn pair16(): i64 {
    var a: [i16] = 0;
    var b: [i16] = 0;
    slice_set(&a, &BA, 2);
    slice_set(&b, &BB, 2);
    a[1] = 0 - 300; b[1] = 0 - 300; a[1] >>= 3; b[1] = b[1] >> 3;
    if (load16(&BA + 2) != load16(&BB + 2)) { return 5; }
    return 0;
}
fn pair32(): i64 {
    var a: [i32] = 0;
    var b: [i32] = 0;
    slice_set(&a, &BA, 2);
    slice_set(&b, &BB, 2);
    a[1] = 0 - 100000; b[1] = 0 - 100000; a[1] /= 3; b[1] = b[1] / 3;
    if (load32(&BA + 4) != load32(&BB + 4)) { return 6; }
    return 0;
}
fn main(): i64 {
    var r = pair8();
    if (r == 0) { r = pair16(); }
    if (r == 0) { r = pair32(); }
    return r;
}
var rc = main();
syscall(60, rc);
EOF
rc=0; timeout 60 "$CC" < "$T/e.cyr" > "$T/e.bin" 2> "$T/e.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "E: rc $rc: $(grep '^error' "$T/e.err" | head -1)"
else
    chmod +x "$T/e.bin"; got=0; timeout 10 "$T/e.bin" > /dev/null 2>&1 || got=$?
    case $got in
        0) ok "E1-E3: \`s[i] OP= v\` == \`s[i] = s[i] op v\` on negative [i8] / [i16] / [i32] elements (>>= /= %= >>>=)" ;;
        1|2|3|4) bad "E1: [i8] row $got: OP= and \`s[i] = s[i] op v\` disagree" ;;
        5) bad "E2: [i16] >>=: OP= and \`s[i] = s[i] >> 3\` disagree" ;;
        6) bad "E3: [i32] /=: OP= and \`s[i] = s[i] / 3\` disagree" ;;
        *) bad "E: exit $got" ;;
    esac
fi

# ── T: the default-mode trap on every leg ───────────────────────────────────────────────────────
# The cross compilers, built once from this tree by the compiler under test.
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
    && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" \
    || rm -f "$T/cc_cx" "$T/cxvm"
if [ "$HAVE_QEMU" -eq 1 ]; then
    "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
fi
trap_ok() {   # <label> <exit> <stderr file>
    if [ "$2" -eq 134 ] && tr -d '\r' < "$3" | grep -qx 'slice bounds violation'; then ok "$1: exit 134, \"slice bounds violation\""
    else bad "$1: exit $2, stderr: $(tr -d '\r' < "$3" | head -2 | tr '\n' '|')"; fi
}
trap_legs() {   # <name> <what> <statement>: s is a [u8] slice of 4 over a u8[4]
    n=$1
    printf '%b' "include \"lib/slice.cyr\"\nfn f(): i64 {\n    var b: u8[4];\n    var s: [u8] = 0;\n    slice_set(&s, &b, 4);\n$3    return 3;\n}\nsyscall(60, f());\n" > "$T/$n.cyr"
    for mode in plain IR3; do
        env_=""; lbl="${n}a: x86"
        [ "$mode" = IR3 ] && { env_="CYRIUS_IR=3"; lbl="${n}b: x86, CYRIUS_IR=3"; }
        rc=0; env $env_ "$CC" < "$T/$n.cyr" > "$T/${n}_$mode" 2> "$T/${n}_$mode.cerr" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl $2: rc $rc: $(grep '^error' "$T/${n}_$mode.cerr" | head -1)"; continue; fi
        chmod +x "$T/${n}_$mode"; got=0; timeout 10 "$T/${n}_$mode" > /dev/null 2> "$T/${n}_$mode.err" || got=$?
        trap_ok "$lbl $2" "$got" "$T/${n}_$mode.err"
    done
    if [ "$HAVE_QEMU" -eq 1 ]; then
        if [ ! -x "$T/cc_a64" ]; then bad "${n}c: src/main_aarch64.cyr did not build"
        elif "$T/cc_a64" < "$T/$n.cyr" > "$T/$n.a64" 2> "$T/$n.a64.cerr" && [ -s "$T/$n.a64" ]; then
            chmod +x "$T/$n.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$n.a64" > /dev/null 2> "$T/$n.a64.err") || got=$?
            trap_ok "${n}c: aarch64 (qemu) $2" "$got" "$T/$n.a64.err"
        else bad "${n}c: aarch64: did not compile: $(grep '^error' "$T/$n.a64.cerr" | head -1)"; fi
    fi
    if [ ! -x "$T/cc_cx" ]; then bad "${n}d: src/main_cx.cyr or programs/cxvm.cyr did not build"
    elif "$T/cc_cx" < "$T/$n.cyr" > "$T/$n.cyx" 2> "$T/$n.cyx.cerr" && [ -s "$T/$n.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/$n.cyx" > /dev/null 2> "$T/$n.cyx.err" || got=$?
        trap_ok "${n}d: cx (cxvm) $2" "$got" "$T/$n.cyx.err"
    else bad "${n}d: cx: did not compile: $(grep '^error' "$T/$n.cyx.cerr" | head -1)"; fi
    if [ "$HAVE_WINE" -eq 1 ]; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$T/$n.cyr" > "$T/$n.exe" 2> "$T/$n.exe.cerr" && [ -s "$T/$n.exe" ]; then
            wine_run "$T" "$n.exe" "$T/$n.exe.err"
            trap_ok "${n}e: PE (wine) $2" "$got" "$T/$n.exe.err"
        else bad "${n}e: PE: did not compile: $(grep '^error' "$T/$n.exe.cerr" | head -1)"; fi
    fi
}
trap_legs T1 "s[4] = 1 on a 4-element slice" '    s[4] = 1;\n'
trap_legs T2 "s[0 - 1] += 1" '    s[0 - 1] += 1;\n'
trap_legs T3 "a for step past the end" '    for (var i = 0; i < 9; s[i] = 7) { i = i + 1; }\n'

# ── W: the value file on every leg ──────────────────────────────────────────────────────────────
TC="$ROOT/tests/tcyr/crossos/slice_subscript_write.tcyr"
[ -f "$TC" ] || { echo "FAIL: $G: $TC missing"; exit 1; }
cp "$TC" "$T/w.cyr"
rc=0; "$CC" < "$T/w.cyr" > "$T/w0.bin" 2> "$T/w0.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning' "$T/w0.err"; then ok "W0: the value file compiles with no warning"
else bad "W0: rc $rc: $(grep '^error\|^warning' "$T/w0.err" | head -2 | tr '\n' '|')"; fi
rc=0; "$CC" --syntax-only < "$T/w.cyr" > /dev/null 2> "$T/w0s.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$T/w0s.err"; then ok "W0s: --syntax-only (cyrius lint) reports nothing"
else bad "W0s: rc $rc: $(grep '^error\|^warning' "$T/w0s.err" | head -2 | tr '\n' '|')"; fi
WANT=$(grep -oE '(assert_eq|assert)\(' "$TC" | wc -l)
if [ "$WANT" -lt 100 ]; then bad "W: only $WANT assertions derived from $(basename "$TC") (floor 100)"; fi
w_ok() {   # <label> <exit> <output file> <spawn: 1 = the SPAWN group ran>
    if [ "$2" -eq 0 ] && tr -d '\r' < "$3" | grep -q ' passed, 0 failed'; then
        if [ "$4" -eq 1 ] && ! tr -d '\r' < "$3" | grep -q 'the default-mode trap'; then bad "$1: the SPAWN group did not run"
        else ok "$1: $(tr -d '\r' < "$3" | grep ' passed, 0 failed' | tail -1)"; fi
    else bad "$1: exit $2 $(tr -d '\r' < "$3" | grep -m2 'FAIL\|violation' | tr '\n' '|')"; fi
}
for mode in plain IR3 IR1 DCE1; do
    case $mode in
        plain) env_=""; lbl="Wa: x86" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="Wb: x86, CYRIUS_IR=3" ;;
        IR1) env_="CYRIUS_IR=1"; lbl="Wf: x86, CYRIUS_IR=1" ;;
        DCE1) env_="CYRIUS_DCE=1"; lbl="Wg: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$T/w.cyr" > "$T/w_$mode" 2> "$T/w_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/w_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/w_$mode"; got=0; timeout 60 "$T/w_$mode" > "$T/w_$mode.out" 2>&1 || got=$?
    w_ok "$lbl" "$got" "$T/w_$mode.out" 1
done
rc=0; CYRIUS_BOUNDS=1 "$CC" < "$T/w.cyr" > "$T/w_bnd" 2> "$T/w_bnd.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "Wh: x86, CYRIUS_BOUNDS=1: rc $rc: $(grep '^error' "$T/w_bnd.err" | head -1)"
else
    chmod +x "$T/w_bnd"; got=0; timeout 60 "$T/w_bnd" > "$T/w_bnd.out" 2>&1 || got=$?
    w_ok "Wh: x86, CYRIUS_BOUNDS=1 (the SPAWN children print the mode's line)" "$got" "$T/w_bnd.out" 1
fi
if [ "$HAVE_QEMU" -eq 1 ]; then
    if [ ! -x "$T/cc_a64" ]; then bad "Wc: src/main_aarch64.cyr did not build"
    elif "$T/cc_a64" < "$T/w.cyr" > "$T/w.a64" 2> "$T/w.a64.err" && [ -s "$T/w.a64" ]; then
        chmod +x "$T/w.a64"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./w.a64 nospawn > "$T/w.a64.out" 2>&1) || got=$?
        w_ok "Wc: aarch64 (qemu; nospawn — the out-of-range store is Tc)" "$got" "$T/w.a64.out" 0
    else bad "Wc: aarch64: did not compile: $(grep '^error' "$T/w.a64.err" | head -1)"; fi
fi
if [ ! -x "$T/cc_cx" ]; then bad "Wd: src/main_cx.cyr or programs/cxvm.cyr did not build"
elif "$T/cc_cx" < "$T/w.cyr" > "$T/w.cyx" 2> "$T/w.cyx.err" && [ -s "$T/w.cyx" ]; then
    got=0; timeout 120 "$T/cxvm" < "$T/w.cyx" > "$T/w.cyx.out" 2>&1 || got=$?
    w_ok "Wd: cx (cxvm; no SPAWN group — the out-of-range store is Td)" "$got" "$T/w.cyx.out" 0
else bad "Wd: cx: did not compile: $(grep '^error' "$T/w.cyx.err" | head -1)"; fi
if [ "$HAVE_WINE" -eq 1 ]; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$T/w.cyr" > "$T/w.exe" 2> "$T/w.exe.err" && [ -s "$T/w.exe" ]; then
        wine_run "$T" w.exe "$T/w.exe.serr"
        cat "$T/w.exe.serr" >> "$T/w.exe.out"
        w_ok "We: PE (wine)" "$got" "$T/w.exe.out" 1
    else bad "We: PE: did not compile: $(grep '^error' "$T/w.exe.err" | head -1)"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — every slice position outside a fn-local var refused by name, once (SR S1-S6, X), what compiled still compiles (K); slice element stores: the refusals (R12 R13 R13b R10 R7), OP= as the read loads (E), the default-mode trap on every leg (T), the value file on x86 / IR / DCE / aarch64 / cx / PE and under the bounds-checked mode (W)"
