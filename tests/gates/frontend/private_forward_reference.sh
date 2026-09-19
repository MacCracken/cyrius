#!/bin/sh
# tests/gates/frontend/private_forward_reference.sh — 6.6.5
#
# ⛔ THE DEFECT. `private` was enforced only against definitions PASS 1 HAD REGISTERED, and
# pass 1 did not register everything: impl methods were brace-skipped, `mod`-scoped fns were
# excluded by a `GMOD == 0` guard, the scan stopped at the first top-level statement while
# PARSE_PROG kept defining fns after it, and the file was not marked private until the walk
# reached the `private` line. An unregistered definition has no owner and no private bit, so
# `_vis_check` returned at its FIRST test — which means a call that merely came EARLIER in
# the concatenated stream reached a private method, operator impl or helper from any file.
# Measured on 6.6.4: exit 42 where the build must be refused.
#
# ⭐ THE SAME ROOT PRODUCED THE MIRROR IMAGE, and that is why axis 3 exists. Pass 1 kept one
# entry per NAME, so a second file's same-named helper overwrote the first file's owner,
# arity and private bit: two private `_h` helpers gave a FALSE "is private to its file" AND
# a FALSE "expects 2 arguments, got 1", and the guide's own two-file `_helper` example was
# REFUSED when the PUBLIC file was included first — no forward call involved, purely include
# order. A fix that only tightened refusals would ship those false refusals forever.
#
# ⛔ AND IT MISCOMPILED. With no pass-1 parameter masks, a forward call passing a >8-byte
# struct used the mask-0 ABI — the value was pushed into a callee that derefs it as a
# pointer. SIGSEGV, silent, on x86, aarch64 and PE. That half is pinned on real hardware by
# tests/tcyr/crossos/forward_ref_abi_binding.tcyr; this gate pins the refusal half, which no
# .tcyr can express (a refused compile has no binary to run).
#
# HOW AXIS 2 COMPUTES ITS EXPECTED VALUE A DIFFERENT WAY FROM THE ACTUAL: it compiles each
# row TWICE — once with the library included BEFORE the caller (the backward order, which
# takes pass 2's stamping path and has always been enforced) and once AFTER (the forward
# order, the defect) — and requires the two refusal SETS to be equal. The expected value is
# therefore produced by a different code path in the compiler, not by a list in this file.
# Each row also carries a hard-coded expected symbol as an ANTI-VACUOUS FLOOR: an empty
# backward set would otherwise make an empty forward set "equal".
# ⚠ AND THE FLOOR IS THE LOAD-BEARING HALF, not the differential. Once the fix lands, both
# include orders resolve through the SAME pass-1 stamp, so forward-vs-backward stops being
# two distinct compiler paths — measured: with M2 (no pre-mark) both sets are empty and the
# differential alone PASSES. Every mutant that reddens this axis reddens it on the floor
# line. The differential is what proves the two orders AGREE; the floor is what proves
# either of them enforces anything at all. Do not drop it as redundant.
#
# MUTATION LEDGER — every mutant below was BUILT (a full cycc from the mutated source) and
# RUN at land time; what is written is what was measured, not what was predicted.
#   M1  restore main.cyr's inline pass-1 impl brace-skip  -> axis 1 red on main.cyr (both checks),
#         axis 2 addrof red; AND tests/tcyr/crossos/forward_ref_abi_binding.tcyr SIGSEGVs (139)
#   M2  delete the _PRIV_PRESCAN pre-mark call in LEX     -> 10/10 axis-2 rows red on the
#         ANTI-VACUOUS floor (nothing is marked private any more, so even the backward order stops
#         refusing) + axis 2b and axis 3 dup_split / guide_pub_first / guide_priv_first /
#         last_private red — 36 FAIL lines in all. The floor is what makes this a failure instead
#         of a silent forward==backward "pass" — both sets would be empty.
#         ⚠ TEN, not nine: this line and the CHANGELOG bullet both read 9/9 after the review
#         round that ADDED the `use_alias` row, which is the same hand-quoted-count defect that
#         round had just corrected next door. DERIVE it:
#           grep -cE '^row [a-z_]+ ' tests/gates/frontend/private_forward_reference.sh
#   M3  drop the bit-64 CLEAR in PARSE_FN_DEF             -> axis 3 last_public red (a `public`
#         last definition stayed private). ⚠ MEASURED, NOT ASSUMED: the guide_pub_first row does
#         NOT redden, because the pass-1 per-definition split already keeps the two files' entries
#         apart. The clear is observable only where two definitions legitimately SHARE an entry.
#   M4  _prescan_tail returns immediately                 -> the crossos tcyr SIGSEGVs (139), but
#         axis 2 STAYS GREEN: the _vis_check deferral catches the refusal half on its own.
#         That is the deferral earning its place, and it is why M5 is proven jointly:
#   M4+M5 also disable the deferral                       -> axis 2 after_stmt row red
#   M5  disable the deferral ALONE                        -> axis 2b red (0 reports, binary emitted)
#   M5b re-walk the deferral list without CONSUMING       -> axis 2b red with **13** reports instead
#         of 1 — PARSE_PROG is the block parser, so the list is re-judged at every block end
#   M6  drop the _fn_by_defti pass-1 authority            -> public_marker_scoped_to_its_item
#         var_then_fn + arr_then_fn red (pass 2's `var` skip re-arms `public` and consumes nothing)
#   M7  remove the SNPOS commit in parse_decl.cyr         -> axis 3 wrong_name red (names Q7_seven,
#         a method that EXISTS, for a call to q.nosuch())
#   M8  remove SFDS in pass 1                             -> axis 3 fwd_generic red, the crossos
#         tcyr fails to COMPILE, and var_then_fn/arr_then_fn red (the authority keys on SFDS)
#   M9  remove the _spec < 0 guard in parse_expr.cyr      -> axis 3 struct_targ red ("undefined
#         function 'enum'" — an out-of-bounds read of _fnt_names at index -3)
#   M11 method args pushed without the callee mask        -> the crossos tcyr SIGSEGVs (139)
#   M12 `_try_push_struct_addr_arg` back to an unconditional `&slot` -> the crossos tcyr's three
#         pointer-mode rows fail with the ADDRESS in place of field 0 (a SILENT wrong value)
#   M13 method loop without _try_push_str_literal_arg     -> the crossos tcyr's Str rows read the
#         raw cstr back (a SILENT wrong value, not a crash)
#   M14 method loop without the SIMD record + second pass -> the crossos tcyr's vmix rows return
#         927 for 923 — a vector pushed as an int arg shifts every LATER argument by a register
#   M15 drop the tail path's `_fnt_strmask` divert        -> the crossos tcyr's tail-position Str
#         rows read the raw cstr back while the `var r = f(...)` rows beside them stay correct
#   M16 drop the EOF carve-out in _PRIV_PRESCAN_TOK       -> private_per_item_rejected axis 3b red
#
# ⚠ TWO CHANGES IN THIS BITE THAT THIS LEDGER DOES **NOT** COVER, written out rather than
#   implied by silence:
#   * the three FORWARD rows added to public_marker_scoped_to_its_item.sh are order-coverage,
#     not proof of the pass-1 authority. Measured: they stay GREEN on the pre-fix compiler and
#     under M6. What M6 reddens is that gate's pre-existing BACKWARD var_then_fn/arr_then_fn.
#   * `_prescan_tail_loop` asking `_IS_FN_KW` instead of a bare `t == 32`. An `async fn` after
#     the first top-level statement is `unexpected async` from PARSE_PROG on 6.6.4 and on this
#     build, so no program can observe the difference today. It is there so the two pass-1
#     scanners agree about what a definition IS; a gate row would assert nothing.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { printf "  SKIP: private_forward_reference — %s not built\n" "$CC"; exit 0; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: private_forward_reference: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
fail=0

# ─────────────────────────────────────────────────────────────────────────────────────
# AXIS 1 — static fork parity. Read from source; no behaviour involved.
#
# The pass-1 impl handling and the relaxed-ordering prescan are TWO one-line calls that
# every one of the seven per-target forks must carry. Miss one and the fail-open (or the
# forward-call ABI miscompile) comes back on that target ONLY — the exact shape of the
# macOS rot, and invisible to an x86 self-host. The forks are DERIVED with a glob, so a
# new fork is covered the day it is added rather than the day someone remembers this list.
# ─────────────────────────────────────────────────────────────────────────────────────
forks=$(ls "$ROOT"/src/main*.cyr 2>/dev/null | grep -v version_str)
nf=$(printf '%s\n' "$forks" | grep -c .)
[ "$nf" -ge 7 ] || { echo "  FAIL: private_forward_reference axis1 — expected >= 7 src/main*.cyr forks, found $nf"; fail=1; }
for f in $forks; do
  b=$(basename "$f")
  ci=$(grep -c '_prescan_impl(S)' "$f" || true)
  ct=$(grep -c '_prescan_tail(S)' "$f" || true)
  cs=$(grep -c 'var idep = 0' "$f" || true)
  [ -n "$ci" ] || ci=0; [ -n "$ct" ] || ct=0; [ -n "$cs" ] || cs=0
  [ "$ci" = "1" ] || { echo "  FAIL: private_forward_reference axis1 — $b has $ci x _prescan_impl(S), want exactly 1"; fail=1; }
  [ "$ct" = "1" ] || { echo "  FAIL: private_forward_reference axis1 — $b has $ct x _prescan_tail(S), want exactly 1"; fail=1; }
  [ "$cs" = "0" ] || { echo "  FAIL: private_forward_reference axis1 — $b still carries the inline pass-1 impl brace-skip ('var idep = 0')"; fail=1; }
done

# ─────────────────────────────────────────────────────────────────────────────────────
# Shared fixture. `lib/` is symlinked from the real tree so the probes can include
# syscalls/simd; the row-specific library goes in lib/pf.cyr.
# ─────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$T/w/lib"
ln -s "$ROOT/lib"/* "$T/w/lib/" 2>/dev/null || true
PRE='include "lib/syscalls.cyr"
'
INC='include "lib/pf.cyr"
'

# row <name> <expected-symbol> <lib-body> <caller-body>
#
# Compiles the caller with the include AFTER it (forward) and BEFORE it (backward), then
# compares the SET of symbols each run reported as private. `expected-symbol` is the
# anti-vacuous floor: the backward run must contain it, or an empty-vs-empty comparison
# would pass while nothing was enforced at all.
row() {
  _n=$1; _sym=$2; _lib=$3; _body=$4
  printf '%s\n' "$_lib" > "$T/w/lib/pf.cyr"
  printf '%s%s\n%s' "$PRE" "$_body" "$INC" > "$T/w/$_n.fwd.cyr"
  printf '%s%s%s\n' "$PRE" "$INC" "$_body" > "$T/w/$_n.bwd.cyr"
  ( cd "$T/w" && "$CC" < "$_n.fwd.cyr" > "$_n.fwd.bin" 2> "$_n.fwd.err" ) || true
  ( cd "$T/w" && "$CC" < "$_n.bwd.cyr" > "$_n.bwd.bin" 2> "$_n.bwd.err" ) || true
  _f=$(grep -o "'[^']*' is private to its file" "$T/w/$_n.fwd.err" 2>/dev/null | sort -u | tr '\n' ' ' || true)
  _b=$(grep -o "'[^']*' is private to its file" "$T/w/$_n.bwd.err" 2>/dev/null | sort -u | tr '\n' ' ' || true)
  case "$_b" in
    *"'$_sym'"*) : ;;
    *) echo "  FAIL: private_forward_reference axis2 [$_n] — anti-vacuous floor: the BACKWARD order did not refuse '$_sym' (got: $_b)"; fail=1 ;;
  esac
  [ "$_f" = "$_b" ] || { echo "  FAIL: private_forward_reference axis2 [$_n] — forward refusals differ from backward: forward={$_f} backward={$_b}"; fail=1; }
  if [ -s "$T/w/$_n.fwd.bin" ]; then echo "  FAIL: private_forward_reference axis2 [$_n] — the forward-order build still emitted a binary"; fail=1; fi
  if [ -s "$T/w/$_n.bwd.bin" ]; then echo "  FAIL: private_forward_reference axis2 [$_n] — the backward-order build still emitted a binary"; fail=1; fi
  return 0
}

row method   Q_seven \
'private
struct Q { a: i64; b: i64; }
impl Tr for Q { fn seven(self) { return 42; } }' \
'fn main(): i64 { var q: Q; q.a = 1; q.b = 2; return q.seven(); }'

row mangled  Q_seven \
'private
struct Q { a: i64; b: i64; }
impl Tr for Q { fn seven(self) { return 42; } }' \
'fn main(): i64 { var q: Q; q.a = 1; q.b = 2; return Q_seven(&q); }'

row addrof   Q_seven \
'private
struct Q { a: i64; b: i64; }
impl Tr for Q { fn seven(self) { return 42; } }' \
'include "lib/fnptr.cyr"
fn main(): i64 { var q: Q; var f = &Q_seven; return fncall1(f, &q); }'

row tailcall Q_seven \
'private
struct Q { a: i64; b: i64; }
impl Tr for Q { fn seven(self) { return 42; } }' \
'fn tc(q): i64 { return Q_seven(q); }
fn main(): i64 { var q: Q; q.a = 1; q.b = 2; return tc(&q); }'

# ⚠ The struct stays in the CALLER, only the operator fn is in the private file: a typed
# global needs its struct declared above it, so moving the whole library below the use
# would break the TYPE and the row would test nothing (measured — the forward run reported
# no violation because no operator dispatch happened at all).
# ⚠ The operator fn must live in an `impl` BLOCK, not as a bare `fn OpV_add`: a bare
# top-level fn IS prescanned even on the broken compiler, so that spelling passes against
# a defect it was written to catch (measured). The struct also stays in the CALLER — a
# typed global needs its struct above it, so moving the whole library below the use would
# break the TYPE and no operator dispatch would happen at all.
row operator OpV_add \
'private
impl Add for OpV { fn add(a, b) { return 39 + b; } }' \
'struct OpV { v; }
var opv: OpV = 5;
fn main(): i64 { var r = opv + 3; return r; }'

row modscope mm_secret_m \
'private
mod mm;
fn secret_m(): i64 { return 42; }' \
'fn main(): i64 { return mm_secret_m(); }'

# ⚠ The `use mod.fn;` ALIAS is a separate pass-1 arm per fork (the token-74 handler in
# src/main*.cyr), reached by a DIFFERENT name than the pre-mangled spelling above: the
# alias registers `mz_usec` and the call site writes the bare `usec()`. On 6.6.4 the
# forward order said `undefined function` — it never got as far as a visibility judgement —
# so the mangled row would have passed a compiler where this one fails.
row use_alias usec \
'private
mod mz;
fn usec(): i64 { return 42; }' \
'use mz.usec;
fn main(): i64 { return usec(); }'

row above_marker late_helper \
'fn late_helper(): i64 { return 42; }
private' \
'fn main(): i64 { return late_helper(); }'

row gvar_above gsecret2 \
'var gsecret2 = 42;
private' \
'fn main(): i64 { return gsecret2; }'

# ⚠ `var zz = 0; zz = 1;` — pass 1 HAS an arm for a top-level `var` and skips it; what
# stops the scan is a real STATEMENT. A fixture with only a `var` never reaches the
# relaxed-ordering path and the row passes against a broken compiler (measured).
row after_stmt after_stmt_secret \
'private
public fn stmt_api(): i64 { return 0; }
var zz = 0;
zz = 1;
fn after_stmt_secret(): i64 { return 42; }' \
'fn main(): i64 { return after_stmt_secret() + stmt_api(); }'

# ⚠ Every command whose non-zero status is DATA (a refused compile, a probe's exit code, a
# grep that finds nothing) is guarded, so this file behaves the same under plain `sh` and
# under `bash -eo pipefail` — CI may run a gate either way, and `var=$(failing_cmd)` trips
# `set -e` BEFORE the bookkeeping that would have reported the failure.
ok() {
  _n=$1; _want=$2; shift 2
  ( cd "$T/w" && "$CC" < "$_n.cyr" > "$_n.bin" 2> "$_n.err" ) || true
  if [ ! -s "$T/w/$_n.bin" ]; then
    echo "  FAIL: private_forward_reference axis3 [$_n] — a LEGAL program was refused"; head -3 "$T/w/$_n.err" | sed 's/^/      /' || true; fail=1; return 0
  fi
  chmod +x "$T/w/$_n.bin"
  _got=0
  ( cd "$T/w" && "./$_n.bin" ) || _got=$?
  [ "$_got" = "$_want" ] || { echo "  FAIL: private_forward_reference axis3 [$_n] — exit $_got, expected $_want"; fail=1; }
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────
# AXIS 2b — the fail-CLOSED DEFERRAL, on a shape pass 1 genuinely cannot stamp.
#
# A fn NESTED inside another fn's body is defined by PARSE_FN_DEF at pass-2 emit time;
# pass 1 never walks a fn body, so nothing prescans it. A forward cross-file call to one in
# a `private` file therefore still resolves with no owner — and this is where `_vis_check`'s
# deferral earns its place: the reference is recorded and re-judged once the definition has
# been stamped. Measured on 6.6.4: the build was ACCEPTED and SIGSEGV'd (rc 139).
#
# ⚠ AND IT MUST REPORT EXACTLY ONCE. `_vis_check_deferred` hangs off the end of PARSE_PROG,
# which is the BLOCK parser — it runs at the end of every `if` / `while` body, not once per
# program. The fixture therefore carries several further blocks AFTER the definition, so an
# implementation that re-walks its pending list without consuming entries reports the one
# violation **13** times (measured, mutant M5b) and fails here.
cat > "$T/w/lib/nest.cyr" <<'EOF'
private
public fn outer(): i64 {
    fn inner_secret(): i64 { return 42; }
    return inner_secret();
}
public fn more1(): i64 { if (1 == 1) { return 1; } return 0; }
public fn more2(): i64 { if (1 == 1) { return 1; } return 0; }
public fn more3(): i64 { var i = 0; while (i < 2) { i = i + 1; } return i; }
public fn more4(): i64 { var j = 0; while (j < 2) { if (j == 0) { j = j + 1; } else { j = j + 1; } } return j; }
EOF
cat > "$T/w/nested.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { if (1 == 1) { return inner_secret(); } return 0; }
include "lib/nest.cyr"
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/w" && "$CC" < nested.cyr > nested.bin 2> nested.err ) || true
nd=$(grep -c "'inner_secret' is private to its file" "$T/w/nested.err" 2>/dev/null || true)
[ -n "$nd" ] || nd=0
[ "$nd" = "1" ] || { echo "  FAIL: private_forward_reference axis2b [deferral] — expected EXACTLY 1 report, got $nd"; fail=1; }
if [ -s "$T/w/nested.bin" ]; then echo "  FAIL: private_forward_reference axis2b [deferral] — a binary was still emitted"; fail=1; fi
# ANTI-VACUOUS, and judged on the DIAGNOSTIC rather than an exit code: the identical program
# with the `private` line removed must compile with NO visibility error, which is what says
# the refusal above is caused by `private` and not by the shape.
#
# ⚠ Deliberately NOT `ok nested_ok 42`. A cross-file call to a fn nested inside another fn's
# body SIGSEGVs on 6.6.4 and on this build alike — a separate, pre-existing defect that has
# nothing to do with visibility (measured: rc 139 from both compilers, on a fixture with no
# `private` anywhere). Asserting an exit code here would couple this axis to that bug; the
# compile-clean assertion is the part this bite owns. `public` is a TOP-LEVEL marker and is
# rejected on a nested fn, so dropping `private` is the only available control.
sed '1d' "$T/w/lib/nest.cyr" > "$T/w/lib/nest_pub.cyr"
sed 's|lib/nest.cyr|lib/nest_pub.cyr|' "$T/w/nested.cyr" > "$T/w/nested_ok.cyr"
( cd "$T/w" && "$CC" < nested_ok.cyr > nested_ok.bin 2> nested_ok.err ) || true
if grep -q "is private to its file" "$T/w/nested_ok.err" 2>/dev/null; then
  echo "  FAIL: private_forward_reference axis2b [control] — the SAME program with no \`private\` was still refused on visibility"; fail=1
fi
[ -s "$T/w/nested_ok.bin" ] || { echo "  FAIL: private_forward_reference axis2b [control] — the non-private control did not build at all"; head -3 "$T/w/nested_ok.err" | sed 's/^/      /' || true; fail=1; }

# ─────────────────────────────────────────────────────────────────────────────────────
# AXIS 3 — NO FALSE REFUSALS, and the expected exit codes are computed by shell
# arithmetic from the fixture literals, never copied from a compiler run.
# ─────────────────────────────────────────────────────────────────────────────────────

# same-file forward call to a private method: legal, and must still WORK.
A=10; B=32
cat > "$T/w/same_file.cyr" <<EOF
include "lib/syscalls.cyr"
private
struct SF { a: i64; b: i64; }
fn main(): i64 { var s: SF; s.a = $A; s.b = $B; return s.sum(); }
impl Tr for SF { fn sum(self) { return load64(self) + load64(self + 8); } }
var rc = main();
sys_exit_group(rc);
EOF
ok same_file $((A + B))

# a `public fn` method in a private file, called forward from another file.
cat > "$T/w/lib/pubm.cyr" <<'EOF'
private
struct PM { a: i64; }
impl Tr for PM { public fn twice(self) { return load64(self) * 2; } }
EOF
C=21
cat > "$T/w/pub_method.cyr" <<EOF
include "lib/syscalls.cyr"
fn main(): i64 { var p: PM; p.a = $C; return p.twice(); }
include "lib/pubm.cyr"
var rc = main();
sys_exit_group(rc);
EOF
ok pub_method $((C * 2))

# TWO private files with a SAME-NAMED helper, each forward-calling its own. Pass 1 kept
# one entry per name, so this produced false "private" AND false arity errors.
cat > "$T/w/lib/dupA.cyr" <<'EOF'
private
public fn dupfwd_entry_a(): i64 { return dup_h(10, 5); }
fn dup_h(x, y): i64 { return x + y + 1; }
EOF
cat > "$T/w/lib/dupB.cyr" <<'EOF'
private
public fn dupfwd_entry_b(): i64 { return dup_h(13); }
fn dup_h(x): i64 { return x * 2; }
EOF
cat > "$T/w/dup_split.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/dupA.cyr"
include "lib/dupB.cyr"
fn main(): i64 { return dupfwd_entry_a() + dupfwd_entry_b(); }
var rc = main();
sys_exit_group(rc);
EOF
ok dup_split $(( (10 + 5 + 1) + (13 * 2) ))

# THE GUIDE'S OWN EXAMPLE, in BOTH include orders — which also compares two runs of the
# compiler against each other rather than against a literal. Public-first used to be
# REFUSED because the stale pass-1 private bit was never cleared.
cat > "$T/w/lib/ga.cyr" <<'EOF'
private
fn _ge_helper(x): i64 { return 1; }
public fn ga_entry(): i64 { return _ge_helper(0); }
EOF
cat > "$T/w/lib/gb.cyr" <<'EOF'
fn _ge_helper(x): i64 { return 70; }
fn gb_entry(): i64 { return _ge_helper(0); }
EOF
# ⚠ main calls `_ge_helper` DIRECTLY as well as through the two entries: the false refusal
# landed on the direct cross-file call to the PUBLIC definition, which the wrappers alone
# do not exercise. `_findfn_scoped` must hand main the public one (70), ga_entry its own
# private one (1), gb_entry the public one (70).
cat > "$T/w/guide_pub_first.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/gb.cyr"
include "lib/ga.cyr"
fn main(): i64 { return _ge_helper(0) + ga_entry() + gb_entry(); }
var rc = main();
sys_exit_group(rc);
EOF
cat > "$T/w/guide_priv_first.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/ga.cyr"
include "lib/gb.cyr"
fn main(): i64 { return _ge_helper(0) + ga_entry() + gb_entry(); }
var rc = main();
sys_exit_group(rc);
EOF
ok guide_pub_first  $((70 + 1 + 70))
ok guide_priv_first $((70 + 1 + 70))

# "last definition wins" — and when the last one carries `public`, the symbol IS public.
# The private bit was only ever SET, never cleared, so the earlier definition's stamp
# survived onto the public one and the cross-file call was refused (measured on 6.6.4).
# ⚠ The opposite order is asserted too: `public fn` then a plain `fn` in a private file must
# stay PRIVATE, or "clear the bit" would have been implemented as "clear it unconditionally".
L1=5; L2=6
cat > "$T/w/lib/lastvis.cyr" <<EOF
private
fn lv_h(): i64 { return $L1; }
public fn lv_h(): i64 { return $L2; }
public fn lv_sealed(): i64 { return $L1; }
fn lv_sealed(): i64 { return $L2; }
EOF
cat > "$T/w/last_public.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/lastvis.cyr"
fn main(): i64 { return lv_h(); }
var rc = main();
sys_exit_group(rc);
EOF
ok last_public $L2
cat > "$T/w/last_private.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/lastvis.cyr"
fn main(): i64 { return lv_sealed(); }
EOF
( cd "$T/w" && "$CC" < last_private.cyr > last_private.bin 2> last_private.err ) || true
grep -q "'lv_sealed' is private to its file" "$T/w/last_private.err" || { echo "  FAIL: private_forward_reference axis3 [last_private] — a PRIVATE last definition was left public"; head -3 "$T/w/last_private.err" | sed 's/^/      /' || true; fail=1; }

# a forward `use` of a PUBLIC mod fn resolves and runs — through the ALIAS spelling, which
# is the arm the axis-2 use_alias row refuses on. The pre-mangled `mz_okm()` spelling takes a
# different resolution arm and would leave the alias half untested in both polarities.
cat > "$T/w/lib/usem.cyr" <<'EOF'
mod mz;
public fn okm(): i64 { return 42; }
EOF
cat > "$T/w/fwd_use.cyr" <<'EOF'
include "lib/syscalls.cyr"
use mz.okm;
fn main(): i64 { return okm(); }
include "lib/usem.cyr"
var rc = main();
sys_exit_group(rc);
EOF
ok fwd_use 42

# a forward explicit generic instantiation — GFDS was recorded in pass 2 only, so the
# instantiator returned -2 and the caller printed a stale "follow-on bite" error.
cat > "$T/w/fwd_generic.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 { var v: i32 = pgp<i32>(42); return v; }
fn pgp<T>(x: T): T { return x; }
var rc = main();
sys_exit_group(rc);
EOF
ok fwd_generic 42
if grep -q "follow-on" "$T/w/fwd_generic.err" 2>/dev/null; then echo "  FAIL: private_forward_reference axis3 [fwd_generic] — still reports the 'follow-on bite' error"; fail=1; fi

# the diagnostic for an unknown method must name the method that was CALLED. The method
# path REGFN'd an uncommitted scratch name, so a later mint overwrote it and the message
# named a DIFFERENT, EXISTING method.
cat > "$T/w/wrong_name.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Q7 { a: i64; }
fn main(): i64 { var q: Q7; return q.nosuch(); }
impl Tr for Q7 { fn seven(self) { return 42; } }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/w" && "$CC" < wrong_name.cyr > wrong_name.bin 2> wrong_name.err ) || true
grep -q "Q7_nosuch" "$T/w/wrong_name.err" || { echo "  FAIL: private_forward_reference axis3 [wrong_name] — the diagnostic does not name Q7_nosuch"; head -3 "$T/w/wrong_name.err" | sed 's/^/      /' || true; fail=1; }
if grep -q "Q7_seven" "$T/w/wrong_name.err"; then echo "  FAIL: private_forward_reference axis3 [wrong_name] — the diagnostic names Q7_seven, a method that EXISTS"; fail=1; fi

# a generic with STRUCT type-args is still refused — but it must not read out of bounds
# and invent a name. `_fnt_names[_spec]` with _spec == -3 printed "undefined function 'enum'".
cat > "$T/w/struct_targ.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x: i64; y: i64; }
fn two<A, B>(a: A, b: B): i64 { return 1; }
fn main(): i64 { var p: Pt; return two<Pt, i64>(p, 2); }
var rc = main();
sys_exit_group(rc);
EOF
( cd "$T/w" && "$CC" < struct_targ.cyr > struct_targ.bin 2> struct_targ.err ) || true
if grep -q "undefined function 'enum'" "$T/w/struct_targ.err"; then echo "  FAIL: private_forward_reference axis3 [struct_targ] — out-of-bounds _fnt_names read: \"undefined function 'enum'\""; fail=1; fi
grep -q "STRUCT type-arguments" "$T/w/struct_targ.err" || { echo "  FAIL: private_forward_reference axis3 [struct_targ] — the real diagnostic is gone"; head -3 "$T/w/struct_targ.err" | sed 's/^/      /' || true; fail=1; }

# compiling cycc's OWN source must not warn about its relaxed-ordering fns. The pre-pass
# "undefined function" loop runs BEFORE PARSE_PROG, which is where those are defined.
( cd "$ROOT" && "$CC" < src/main.cyr > "$T/selfw.bin" 2> "$T/selfw.err" ) || true
[ -s "$T/selfw.bin" ] || { echo "  FAIL: private_forward_reference axis3 [self] — cycc failed to compile its own source"; fail=1; }
sw=$(grep -c "warning: undefined function" "$T/selfw.err" 2>/dev/null || true)
[ "$sw" = "0" ] || { echo "  FAIL: private_forward_reference axis3 [self] — $sw 'undefined function' warnings compiling cycc's own source"; grep "undefined function" "$T/selfw.err" | head -3 | sed 's/^/      /' || true; fail=1; }

[ "$fail" = 0 ] || exit 1
echo "PASS private_forward_reference: 7/7 forks carry both pass-1 calls; 10 refusal rows match forward==backward over a hard-coded symbol floor; the deferral backstop reports a nested-fn violation exactly once; 8 legal programs run (6 with exit codes computed in the shell from the fixture literals, 2 against a literal) plus 2 build-only controls; last-definition visibility holds both ways; diagnostics name the right symbol"
exit 0
