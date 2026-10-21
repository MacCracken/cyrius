#!/bin/sh
# false_warnings_valid_shapes.sh — 6.6.17. Four warnings that fired on valid code (each built and
# ran correctly), each paired with a row proving the warning still fires on a genuinely wrong
# shape — a gate that only checks silence passes a deleted warning.
#
#   B  `warning: undefined function 'f'` for a fn defined inside a TOP-LEVEL block and called
#      from a fn earlier in the file: the relaxed-ordering prescan did not descend into blocks.
#      (The same blind spot miscompiled a forward call passing a struct: rc 139 — pinned at run
#      time by tests/tcyr/lang/toplevel_block_fn_forward_call.tcyr.) Control: a call to a fn
#      defined nowhere still warns.
#   P  `assigning non-pointer to typed pointer` for a RHS of exactly the local's struct type:
#      `a = GP` (a pointer-mode struct global), `b = q.name()` (a method declared `: Str`),
#      `b = q.name` / `b = w.q.name` (a `: Str` field, nested). Controls: an integer, a global of
#      ANOTHER struct type, an i64 field and an i64 method still warn — one each.
# RED on the slot-open compiler (4a37046b): B1, B1a and P1.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: false_warnings_valid_shapes: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: false_warnings_valid_shapes: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: false_warnings_valid_shapes: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# The five-leg rows' PE runs use a PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on
# exit (`-k` leaves /tmp/.wine-<uid>/server-<dev>-<ino> behind) — tuple_checked.sh's helper.
WP="$D/wine"
WHM="$D/whome"
_d_down() {
  [ -d "$WP" ] || return 0
  _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
  WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
  WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
  rm -rf "$_ws" || true
}
trap '_d_down; rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: false_warnings_valid_shapes $1"; fail=$((fail + 1)); }
# chk <row> <file> <needle> <want-count> [<want-exit>]
chk() {
  rc=0; "$CC" < "$D/$2" > "$D/$2.bin" 2> "$D/$2.err" || rc=$?
  [ "$rc" = 0 ] || { bad "$1: did not compile (rc $rc): $(grep -m1 error "$D/$2.err")"; return; }
  n=$(grep -c -- "$3" "$D/$2.err" || true)
  [ "$n" = "$4" ] || { bad "$1: '$3' printed $n time(s), want $4"; grep -- "$3" "$D/$2.err" | head -4; return; }
  if [ -n "${5:-}" ]; then
    chmod +x "$D/$2.bin"; x=0; "$D/$2.bin" > /dev/null 2>&1 || x=$?
    [ "$x" = "$5" ] || bad "$1: ran to $x, want $5"
  fi
}

cat > "$D/b1.cyr" <<'EOF'
fn early(): i64 { return inner(1) + deep(0); }
var z = 0;
if (z == 0) {
    fn inner(x): i64 { return x + 40; }
    while (z == 0) {
        fn deep(x): i64 { return x + 1; }
        z = 1;
    }
}
syscall(60, early());
EOF
chk "B1 (fns in top-level blocks, called earlier)" b1.cyr "undefined function" 0 42
# B1a (review find): an attribute line before the block fn kept it unprescanned
cat > "$D/b1a.cyr" <<'EOF'
fn early(): i64 { return inner(1) + deep(0); }
var z = 0;
if (z == 0) {
    #pure
    fn inner(x): i64 { return x + 40; }
    #deprecated("use something else")
    fn deep(x): i64 { return x + 1; }
}
syscall(60, early());
EOF
chk "B1a (attributed fns in a top-level block)" b1a.cyr "undefined function" 0 42
cat > "$D/b2.cyr" <<'EOF'
fn early(): i64 { return nowhere(1); }
var z = 0;
if (z == 0) {
    fn inner(x): i64 { return x + 40; }
}
var q = inner(1);
EOF
"$CC" < "$D/b2.cyr" > /dev/null 2> "$D/b2.err" || true
n=$(grep -c "warning: undefined function 'nowhere'" "$D/b2.err" || true)
[ "$n" = 1 ] || bad "B2 (control): a fn defined nowhere warned $n time(s), want 1"
grep -q "undefined function 'inner'" "$D/b2.err" && bad "B2 (control): the block fn beside it warned"

cat > "$D/p1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
struct Pt { x; y; z; }
struct Q { name: Str; n; }
struct W { q: Q; k; }
fn Q_name(self: Q): Str { return self.name; }
var GP: Pt = alloc(24);
var GS: Str = str_from("gs");
fn main(): i64 {
    alloc_init();
    var a: Pt = alloc(24);
    a = GP;
    var q: Q;
    q.name = str_from("qq");
    q.n = 3;
    var w: W;
    w.q = q;
    w.k = 0;
    var b: Str = str_from("b");
    b = q.name();
    b = q.name;
    b = w.q.name;
    b = GS;
    return str_len(b);
}
syscall(60, main());
EOF
chk "P1 (a RHS of the local's own struct type)" p1.cyr "assigning non-pointer to typed pointer" 0 2
cat > "$D/p2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
struct Pt { x; y; z; }
struct Q { name: Str; n; }
fn Q_count(self: Q): i64 { return self.n; }
var GQ: Q = alloc(16);
fn main(): i64 {
    alloc_init();
    var a: Pt = alloc(24);
    var n = 5;
    a = n;
    a = GQ;
    var q: Q;
    q.name = str_from("qq");
    q.n = 3;
    var b: Str = str_from("b");
    b = q.n;
    b = q.count();
    return 0;
}
syscall(60, main());
EOF
chk "P2 (control: int, another struct's global, i64 field, i64 method)" p2.cyr "assigning non-pointer to typed pointer" 4

# D (6.7.13, D9 (a), the user 2026-10-15; issues/archived/2026-10-13-double-pointer-dereference-is-an-untyped-word.md):
# `*pp` of a `pp: **T` is a `*T`, so `var q: *T = *pp;` and `q = *pp;` are silent — a `**i64` local, parameter,
# global (in a fn and at top level), field and `: **i64` call, and a `***i64`'s `**ppp`. It warned "assigning
# non-pointer to typed pointer" at each (the filed repro: line 9). D2 (controls): `**pp` (the i64 element) and an
# integer still warn — one each. D3: `*pp - b` with `b: *u8` is a pointer difference of two element sizes now,
# refused by name (it was a byte count of an untyped word). Mutation: `_pp_inner` answering 0 -> D0, D1 RED (the
# warnings return; D0's repro exits 1) and D3 RED (it compiles).
DR="$ROOT/docs/development/issues/archived/2026-10-13-double-pointer-dereference-is-an-untyped-word.md"
if [ -f "$DR" ]; then
  awk '/^```cyrius$/ { f = 1; next } /^```$/ { if (f) exit } f' "$DR" > "$D/d0.cyr"
  chk "D0 (the filed repro verbatim: silent, exit 0)" d0.cyr "assigning non-pointer to typed pointer" 0 0
fi
cat > "$D/d1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct H { k; pp: **i64; }
var GA: i64[3];
var GP: *i64 = &GA;
fn sec(pp: **i64): i64 { var q: *i64 = *pp; q = *pp; return *(q + 1); }
fn trip(ppp: ***i64): i64 { var q: *i64 = **ppp; return *(q + 2); }
GA[1] = 4;
GA[2] = 5;
var GPP: **i64 = &GP;
var TQ: *i64 = *GPP;
fn gpp(): **i64 { return GPP; }
fn main(): i64 {
    var p: *i64 = &GA;
    var pp: **i64 = &p;
    var q: *i64 = *pp;
    q = *pp;
    var g: *i64 = *GPP;
    var h: H;
    h.pp = &p;
    var f: *i64 = *h.pp;
    var c: *i64 = *gpp();
    return *(q + 1) + sec(pp) + *(g + 1) + *(f + 1) + *(c + 2) + trip(&pp) + *(TQ + 1) - 25;
}
syscall(60, main());
EOF
chk "D1 (var q: *i64 = *pp: a local, a parameter, a global in a fn and at top level, a field, a call, ***)" d1.cyr "assigning non-pointer to typed pointer" 0 5
cat > "$D/d2.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: i64[2];
    var p: *i64 = &a;
    var pp: **i64 = &p;
    var q: *i64 = **pp;
    var r: *i64 = 7;
    return 0;
}
syscall(60, main());
EOF
chk "D2 (control: **pp, the element, and an integer still warn)" d2.cyr "assigning non-pointer to typed pointer" 2
cat > "$D/d3.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: i64[4];
    var p: *i64 = &a;
    var b: *u8 = &a;
    var pp: **i64 = &p;
    return *pp - b;
}
syscall(60, main());
EOF
rc=0; "$CC" < "$D/d3.cyr" > /dev/null 2> "$D/d3.err" || rc=$?
n=$(grep -c "pointer difference of pointers with different element sizes" "$D/d3.err" || true)
[ "$rc" != 0 ] && [ "$n" = 1 ] || bad "D3 (*pp - b, a *i64 less a *u8): rc $rc, refused $n time(s), want refused once"

# N (6.7.16; issues/2026-10-18-parenthesised-null-literal-into-typed-pointer-warns.md): the literal 0 is a null pointer
# under parentheses that wrap it whole (6.7.13's D18 (a) by the guide's whole-wrap transparency, as 6.7.15's D59 took
# the string literal): `var p: *i64 = (0);`, `p = (0);` and a zone `var G: *i64 = (0);` warned "non-pointer" where
# `= 0;` is quiet. N0 the filed repro verbatim; N1 `((0))`, after the first statement, a global assignment, a `*P`
# local, a parameter; N2 (controls) `(0) + 1`, `(1)`, `(0) + 0` still warn, one each. Mutation: `_tp_null_exempt`
# peeling no `(` (the 6.7.15 shape) -> N0 N1 RED (3 and 9 warnings).
cat > "$D/n0.cyr" <<'EOF'
fn main(): i64 {
    var p: *i64 = (0);
    p = (0);
    return 0;
}
var G: *i64 = (0);
syscall(60, main());
EOF
chk "N0 (the filed repro verbatim: (0) into a *i64 decl, assignment, zone global)" n0.cyr "assigning non-pointer to typed pointer" 0 0
cat > "$D/n1.cyr" <<'EOF'
struct P { a; }
fn main(): i64 {
    var p: *i64 = ((0));
    p = ((0));
    var s: *P = (0);
    s = (0);
    return 0;
}
fn f(q: *P): i64 { q = (0); return 0; }
var G: *i64 = ((0));
var z = 1;
z = 2;
var H: *i64 = ((0));
H = (0);
G = (0);
syscall(60, main() + f(0));
EOF
chk "N1 (((0)), a *P local, a parameter, after the first statement, a global assignment)" n1.cyr "assigning non-pointer to typed pointer" 0 0
cat > "$D/n2.cyr" <<'EOF'
fn main(): i64 {
    var p: *i64 = (0) + 1;
    p = (1);
    var q: *i64 = (1);
    q = (0) + 0;
    return 0;
}
var G: *i64 = (1);
var K: *i64 = (0) + 1;
syscall(60, main());
EOF
chk "N2 (control: (0) + 1, (1), (0) + 0 still warn)" n2.cyr "assigning non-pointer to typed pointer" 6

# SP (6.7.16; issues/2026-10-18-str-call-into-str-pointer-declaration-or-global-warns-typed-pointer.md): a call declared
# `: Str` returns the header's address, which is what a `*Str` holds, so a `: Str` call into a `*Str` declaration (in a
# fn, the zone, after the first statement) or a `*Str` global's assignment is quiet, as the `*Str` local's assignment
# already was (v6.5.28): SP0 the filed repro verbatim (2 warnings before, exit 20); SP1 the method forms (a local, a
# global and a nested-field receiver, into a declaration and a global), the zone and after-the-first-statement
# declarations and assignment (8 before, exit 112). The `: Q` / `: P1` / `**Str` controls are
# tests/gates/diagnostics/typed_pointer_warn_sign.sh axis 16. Mutation: `_tp_call_pointee` answering 0 -> SP0 SP1 RED
# (2 and 8 warnings).
cat > "$D/sp0.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
var GP: *Str = 0;
fn main(): i64 {
    alloc_init();
    var p: *Str = str_from("abcde");
    GP = str_from("xyz");
    var q: *Str = 0;
    q = str_from("ab");
    return str_len(p) * 100 + str_len(GP) * 10 + str_len(q);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
chk "SP0 (the filed repro verbatim: a : Str call into a *Str declaration and global)" sp0.cyr "assigning non-pointer to typed pointer" 0 20
cat > "$D/sp1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct H { name: Str; n; }
struct W { h: H; k; }
fn H_clone(self: H): Str { return str_from("hc"); }
var _ai = alloc_init();
var GZ: *Str = 0;
var GP2: *Str = str_from("zone");
var GH: H = alloc(16);
fn main(): i64 {
    var h: H = alloc(16);
    h.name = str_from("nm");
    h.n = 1;
    GH.name = str_from("gh");
    var w: W;
    w.h.name = str_from("w");
    w.k = 0;
    var p: *Str = h.clone();
    GZ = h.clone();
    var g: *Str = GH.clone();
    GZ = GH.clone();
    var n: *Str = w.h.clone();
    return str_len(p) + str_len(GZ) * 10 + str_len(GP2) * 20 + str_len(g) + str_len(n);
}
var z = 1;
z = 2;
var GP3: *Str = str_from("late");
GP3 = str_from("later!");
var r = main() + str_len(GP3);
syscall(SYS_EXIT, r);
EOF
chk "SP1 (methods, a nested receiver, the zone, after the first statement)" sp1.cyr "assigning non-pointer to typed pointer" 0 112

# ── the five-leg rows (6.7.16) ────────────────────────────────────────────────────────────────────
# `fw5` compiles a row on x86_64, PE and Mach-O (the env legs of $CC) and on the aarch64 / cx compilers built from this
# tree, and wants rc 0, a binary, and EXACTLY its typed-pointer warning lines (`L:C` each; no other error or warning
# line) on each; with an exit it runs on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine). A missing tool is named and
# fails the gate (a SKIP is not coverage).
F5=0
F5N=0
_f5_init() {
  [ "$F5" -eq 1 ] && return 0
  F5=1
  F5L="x86_64 pe macho"
  if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; F5L="$F5L aarch64"
  else bad "five-leg rows: src/main_aarch64.cyr did not build"; fi
  if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; F5L="$F5L cx"
  else bad "five-leg rows: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
  command -v qemu-aarch64 > /dev/null 2>&1 || bad "five-leg rows: qemu-aarch64 is not installed (the aarch64 runs)"
  command -v wine > /dev/null 2>&1 || bad "five-leg rows: wine is not installed (the PE runs)"
}
_f5_cc() {   # <leg> <name>: $D/<name>.<leg> (+ .err); rc in $rc
  rc=0
  case $1 in
    x86_64)  timeout 60 "$CC" < "$D/$2.cyr" > "$D/$2.$1" 2> "$D/$2.$1.err" || rc=$? ;;
    pe)      CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$D/$2.cyr" > "$D/$2.$1" 2> "$D/$2.$1.err" || rc=$? ;;
    macho)   CYRIUS_MACHO=1 timeout 60 "$CC" < "$D/$2.cyr" > "$D/$2.$1" 2> "$D/$2.$1.err" || rc=$? ;;
    aarch64) timeout 60 "$D/cc_a64" < "$D/$2.cyr" > "$D/$2.$1" 2> "$D/$2.$1.err" || rc=$? ;;
    cx)      timeout 60 "$D/cc_cx" < "$D/$2.cyr" > "$D/$2.$1" 2> "$D/$2.$1.err" || rc=$? ;;
  esac
}
_f5_run() {   # <leg> <name>: the exit in $got ('-' for a leg that does not run here)
  got=0
  case $1 in
    x86_64)  timeout 30 "$D/$2.$1" > /dev/null 2>&1 || got=$? ;;
    aarch64) timeout 60 qemu-aarch64 "$D/$2.$1" > /dev/null 2>&1 || got=$? ;;
    cx)      timeout 60 "$D/cxvm" < "$D/$2.$1" > /dev/null 2>&1 || got=$? ;;
    pe)      mkdir -p "$WHM"; cp "$D/$2.$1" "$D/$2.exe"
             (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
               WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2.exe" > /dev/null 2>&1) || got=$? ;;
    *)       got=- ;;
  esac
}
fw5() {   # <row> <file in $D> <want warnings: `L:C` per line, or empty> <want exit or ->
  _f5_init
  n5="${2%.cyr}"
  : > "$D/$n5.want"
  for lc in $3; do echo "warning:<source>:$lc: assigning non-pointer to typed pointer" >> "$D/$n5.want"; done
  for leg in $F5L; do
    _f5_cc "$leg" "$n5"
    F5N=$((F5N + 1))
    grep -E '^(error|warning)' "$D/$n5.$leg.err" > "$D/$n5.$leg.got" || true
    if [ "$rc" -ne 0 ] || [ ! -s "$D/$n5.$leg" ]; then bad "$1 ($leg): rc $rc: $(grep '^error' "$D/$n5.$leg.err" | head -1)"; continue; fi
    if ! cmp -s "$D/$n5.$leg.got" "$D/$n5.want"; then bad "$1 ($leg): got $(wc -l < "$D/$n5.$leg.got") line(s): $(tr '\n' '|' < "$D/$n5.$leg.got") want: $(tr '\n' '|' < "$D/$n5.want")"; continue; fi
    if [ "$4" != - ]; then
      chmod +x "$D/$n5.$leg"; _f5_run "$leg" "$n5"
      if [ "$got" != - ] && [ "$got" != "$4" ]; then bad "$1 ($leg): exit $got, want $4"; fi
    fi
  done
}

# SF (6.7.16; issues/2026-10-19-str-field-into-str-pointer-declaration-or-global-warns-typed-pointer.md): a `: Str` FIELD
# is a pointer slot (its value is the header's address), so a `: Str` field into a `*Str` declaration (in a fn, the zone,
# after the first statement) or a `*Str` global's assignment is quiet, as `l = h.name;` into the local already was
# (6.6.17). `_tp_call_pointee` took calls only (the value had to end `)`); it now reads what the local's arm reads
# (`_tpv_sid`, parse.cyr), so with the field came the rest of that class: a `Str`-typed name (`GS`), a field or a method
# of a call's result (`mkh().name`, `mkh().nm()`), and each of them and the call under parentheses that wrap the value
# whole (`(h.name)`, `((str_from(..)))` — into the local and a handle too, where a wrapped value warned while the bare
# one did not). SF0 the filed repro verbatim (2 warnings before, exit 6); SF1 nested `w.h.name` (5 before); SF2 the
# siblings (13 before); SF3 controls: an i64 field (`h.n`, wrapped too) and a value the parentheses do not wrap whole
# still warn, at their lines (the zone's at its replay, last). Warning text only: every row's binary is the one before (exits unchanged).
#   the lane's compiler before the bite (7bab85ee)                -> RED SF0 SF1 SF2 (2, 5 and 13 warnings)
#   `_tp_call_pointee` with 6.7.16's earlier calls-only test      -> RED SF0 SF1 SF2 (the fields, the names, the wraps)
#   `_tpv_peel` refusing any wrap                                 -> RED SF2 (the wrapped siblings, the handle)
#   `_tpv_peel` without its `;` test (`(h.name) + 0` taken whole)  -> RED SF3 (18:31, 19:28 missing)
#   `_asg_hdl_call` not peeling                                    -> RED SF2 (`k = (str_from(..))` into a P3 handle)
cat > "$D/sf0.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct H { name: Str; n; }
var GZ: *Str = 0;
fn main(): i64 {
    alloc_init();
    var h: H = alloc(16);
    h.name = str_from("nm");
    var f: *Str = h.name;
    GZ = h.name;
    var l: *Str = 0;
    l = h.name;
    return str_len(f) + str_len(GZ) + str_len(l);
}
syscall(60, main());
EOF
fw5 "SF0 (the filed repro verbatim: a : Str field into a *Str declaration and global; 2 warnings before)" sf0.cyr "" 6
cat > "$D/sf1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct H { name: Str; n; }
struct W { h: H; k; }
var _ai = alloc_init();
fn mkw(): i64 { var w: W = alloc(32); w.h.name = str_from("zone"); return w; }
var GW: W = mkw();
var GZ: *Str = GW.h.name;
var GG: *Str = 0;
fn main(): i64 {
    var w: W = alloc(32);
    w.h.name = str_from("xyz");
    var f: *Str = w.h.name;
    GG = w.h.name;
    return str_len(f) + str_len(GG) * 10 + str_len(GZ) * 20;
}
var z = 1;
z = 2;
var GL: *Str = GW.h.name;
GG = GW.h.name;
var r = main();
syscall(60, r + str_len(GL) + str_len(GG));
EOF
fw5 "SF1 (nested w.h.name into a declaration, a global, the zone, after the first statement; 5 before)" sf1.cyr "" 120
cat > "$D/sf2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct H { name: Str; n; }
struct P3 { a; b; c; }
fn H_nm(self: H): Str { return self.name; }
fn mkh(): H { var h: H = alloc(16); h.name = str_from("cd"); h.n = 4; return h; }
var _ai = alloc_init();
var GS: Str = str_from("gs");
var GA: *Str = GS;
var GB: *Str = (GS);
var GZ: *Str = 0;
fn main(): i64 {
    var h: H = alloc(16);
    h.name = str_from("nm");
    var a: *Str = GS;
    var b: *Str = mkh().name;
    var c: *Str = mkh().nm();
    var d: *Str = (h.name);
    var e: *Str = ((str_from("abc")));
    var f: *Str = (mkh().nm());
    GZ = mkh().name;
    var g = str_len(GZ);
    GZ = (h.name);
    var l: *Str = 0;
    l = (h.name);
    var m: *Str = 0;
    m = ((str_from("wxyz")));
    var k: P3 = alloc(24);
    k = (str_from("ab"));
    var u = k;
    return str_len(a) + str_len(b) + str_len(c) + str_len(d) + str_len(e) + str_len(f) + g + str_len(GZ) + str_len(l) + str_len(m) + str_len(GA) + str_len(GB) + str_len(u);
}
syscall(60, main());
EOF
fw5 "SF2 (a Str name, a call's field and method, each wrapped whole, into a *Str and a handle; 13 before)" sf2.cyr "" 29
cat > "$D/sf3.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct H { name: Str; n; }
var _ai = alloc_init();
fn mkh(): i64 { var h: H = alloc(16); h.name = str_from("cd"); h.n = 4; return h; }
var GH: H = mkh();
var GK: *Str = GH.n;
var GZ: *Str = 0;
fn main(): i64 {
    var h: H = alloc(16);
    h.name = str_from("nm");
    h.n = 1;
    var a: *Str = h.n;
    var b: *Str = (h.n);
    GZ = h.n;
    var l: *Str = 0;
    l = h.n;
    var c: *Str = (h.name) + 0;
    l = (str_from("x")) + 0;
    return 0;
}
syscall(60, main());
EOF
fw5 "SF3 (controls: an i64 field, wrapped too, and a value its parentheses do not wrap whole still warn)" sf3.cyr "13:22 14:24 15:13 17:12 18:31 19:28 7:20" 0
[ "$F5N" -ge 20 ] || bad "SF: the five-leg rows ran $F5N row-legs (floor 20)"

if [ "$fail" -ne 0 ]; then echo "FAIL false_warnings_valid_shapes: $fail row(s) red"; exit 1; fi
echo "PASS false_warnings_valid_shapes: fns in top-level blocks are not 'undefined' (a fn defined nowhere still is); a same-typed global / Str method / Str field (nested too) assigned into a typed local is not 'non-pointer' (int, foreign struct, i64 field and i64 method still are); \`*pp\` of a \`**T\` is a \`*T\` (D9 (a)); \`(0)\` wrapped whole is the null literal; a \`: Str\` call into a \`*Str\` is its pointer, and so are a \`: Str\` field, a \`Str\` name, a call's \`Str\` field or method, each wrapped whole (five legs)"
exit 0
