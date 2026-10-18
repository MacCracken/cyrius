#!/bin/sh
# inline_async_warned.sh — 6.7.14: `#inline` on an `async fn` says it is ignored. The body is compiled as `f$impl`
# and reached only through its Future (`future_force`'s fn pointer); no call names `f$impl`, so its inline replay
# can never run — but the classification at the fn's end admitted it and said nothing, while the same directive
# on a plain fn it cannot inline is warned `#inline ignored: <reason>` (v6.5.63's contract). Reason 8, checked
# first: "#inline ignored: async fn 'f' runs through its Future". A warning only: the binary and the exit code are
# what they were (issues/archived/2026-10-11-inline-on-async-fn-silently-ignored.md).
#
#   A1  the filed repro verbatim (CYRIUS_ASYNC=1): `pl` and `co` warned by name, `sy` not; the run exits 15
#   A2  the repro's binary equals the one built with the two async fns' `#inline` lines removed (no effect)
#   A3  an async fn another reason also disqualifies (3 parameters; a `var` in the body) gets the async reason, once
#   A4  an async fn with no `#inline` is quiet; a coroutine whose body has control flow gets the async reason
#   A5  a plain `#inline` fn keeps its own reason
#
# MUTATION (measured, 6.7.14): the reason-8 line removed from _PARSE_FN_DEF_IMPL -> A1 and A3 RED (no async
# warning; A3's other reasons printed instead) and A4 RED (reason 4 printed instead).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: inline_async_warned: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: inline_async_warned: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: inline_async_warned: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: inline_async_warned $1"; fail=$((fail + 1)); }

# row ID WANT_EXIT WANT — the source on stdin compiles under CYRIUS_ASYNC=1 (rc 0, no error), its warning lines
# (`<source>:` stripped, joined by '|') are exactly WANT, and the program exits WANT_EXIT.
row() {
  rows=$((rows + 1))
  cat > "$D/$1.cyr"
  rc=0; CYRIUS_ASYNC=1 "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || rc=$?
  [ "$rc" -eq 0 ] || { bad "$1: compile rc $rc: $(grep -E '^error' "$D/$1.err" | head -1)"; return; }
  [ -s "$D/$1" ] || { bad "$1: empty output"; return; }
  got=$(grep -E '^(error|warning)' "$D/$1.err" | sed 's/^warning:<source>://' | tr '\n' '|')
  [ "$got" = "$3" ] || { bad "$1: warnings {$got}, want {$3}"; return; }
  chmod +x "$D/$1"
  x=0; "$D/$1" > /dev/null 2>&1 || x=$?
  [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
}

row A1 15 "10:37: #inline ignored: async fn 'pl' runs through its Future|12:46: #inline ignored: async fn 'co' runs through its Future|" <<'EOF'
# Build with CYRIUS_ASYNC=1. `#inline` on an `async fn` (a plain Future or a coroutine) has no
# effect and no diagnostic; the same directive on a plain fn it cannot inline is warned
# "#inline ignored: <reason>" (v6.5.63's contract).
# Expected: a warning per async fn naming why (its body runs through future_force's fn pointer).
# Actual (6.7.9 crit tip): no warning; exits 15.
include "lib/alloc.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 7; }
#inline
async fn pl(x): i64 { return x + 1; }
#inline
async fn co(C): i64 { return await nopark(); }
#inline
fn sy(x): i64 { return x + 2; }
fn main(): i64 { alloc_init(); var F = pl(4); var r = future_force(F); var G = co(0); var q = future_force(G); q = future_force(G); return r + q + sy(1); }
syscall(60, main());
EOF
rows=$((rows + 1))
if [ -s "$D/A1" ]; then
  sed -e '9s/^#inline$//' -e '11s/^#inline$//' "$D/A1.cyr" > "$D/A2.cyr"
  rc=0; CYRIUS_ASYNC=1 "$CC" < "$D/A2.cyr" > "$D/A2" 2> "$D/A2.err" || rc=$?
  if [ "$rc" -ne 0 ]; then bad "A2: compile rc $rc"
  elif grep -q '^warning' "$D/A2.err"; then bad "A2: a warning without the async #inline lines: $(grep '^warning' "$D/A2.err" | head -1)"
  else cmp -s "$D/A1" "$D/A2" || bad "A2: the async fns' #inline changed the binary"
  fi
else bad "A2: no A1 binary to compare"; fi
row A3 9 "4:50: #inline ignored: async fn 'three' runs through its Future|6:53: #inline ignored: async fn 'withvar' runs through its Future|" <<'EOF'
include "lib/alloc.cyr"
include "lib/async.cyr"
#inline
async fn three(a, b, c): i64 { return a + b + c; }
#inline
async fn withvar(x): i64 { var y = x + 1; return y; }
async fn plain(x): i64 { return x; }
fn main(): i64 { alloc_init(); return future_force(three(1, 2, 3)) + future_force(withvar(1)) + future_force(plain(1)); }
syscall(60, main());
EOF
row A4 4 "6:71: #inline ignored: async fn 'cf' runs through its Future|" <<'EOF'
include "lib/alloc.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 2; }
async fn quiet(x): i64 { return x + 1; }
#inline
async fn cf(x): i64 { if (x > 0) { return await nopark(); } return 0; }
fn main(): i64 { alloc_init(); var G = cf(1); var q = future_force(G); q = future_force(G); return future_force(quiet(1)) + q; }
syscall(60, main());
EOF
row A5 3 "4:1: #inline ignored: body has control flow or a var declaration|" <<'EOF'
#inline
fn sy(x): i64 {
    var y = x; return y + 2;
}
syscall(60, sy(1));
EOF

[ "$rows" -ge 5 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL inline_async_warned: $fail of $rows row(s) red"; exit 1; fi
echo "PASS inline_async_warned: $rows rows — #inline on an async fn (a Future, a coroutine) is warned by name, once; the binary is unchanged"
exit 0
