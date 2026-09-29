#!/bin/sh
# missing_helper_error_exits_1.sh — 6.6.9 bite 3. A compile that reports "you need
# lib/<x>.cyr" (or "async is gated") EXITS 1 on every backend. It never crashes after the
# diagnostic.
#
# ⛔ WHY. ERR_MSG reports and CONTINUES (the v6.4.62 multi-error contract). Eleven callers
# looked up a helper by name, reported when it was missing, and then handed the -1 on to
# ECALLFIX anyway: the seven aarch64 f64 polyfills, the slice subscript, `await` (twice) and
# the `async fn` constructor. ECALLFIX stored `(2 << 56) | -1`, which is -1, and that reads
# back as fixup type 0xFF with an index near 2^56. The aarch64 FIXUP and the cx fixup walk
# both ran BEFORE the `_had_error` early-out and decoded it as a variable fixup. Their
# `vi < idx` loop ran off `_vars_base`: rc 139, right after the correct message. Measured
# before 6.6.9: every trigger below was 139 on cycc_aarch64 (the native aarch64 compiler
# too, under qemu), and slice / await / async were 139 on cycc_cx. x86 and PE exited 1.
# Scripts that key on rc == 1 read those crashes as something else.
#
# THREE layers, each enough on its own (mutation-checked when this gate was written):
#   - aarch64 FIXUP's relocation walk skips an undecodable entry (ftype > 5) once an error has
#     been reported, and the cx fixup walk exits before it runs;
#   - ECALLFIX (x86, aarch64 and cx) refuses a negative index;
#   - each of the eleven sites returns (or skips the call) after its message.
# The rc rows prove the combination. The per-site returns are also observable: without them
# a refused `await` / `async fn` reported a SECOND, misleading error ("needs lib/async.cyr",
# "needs lib/alloc.cyr"), so each row also requires EXACTLY one error line. The first two
# layers are generic backstops that no user trigger reaches once the sites return, so they
# are pinned structurally below.
#
# The aarch64 skip is deliberately NARROW. Its first cut returned at FIXUP entry, which also
# skipped the liveness pass and the reachable-undefined refusal, so an aarch64 compile with an
# error plus an undefined call reported ONE error where x86, PE and cx report two (the v6.4.62
# multi-error contract). The multi_err rows pin that parity on every backend.
#
# Anti-vacuous rows: with lib/math.cyr included, f64_exp builds rc 0 on aarch64. With
# CYRIUS_ASYNC=1, lib/alloc.cyr and lib/async.cyr, await/async build rc 0 on x86. A gate that
# refused everything fails those rows.
#
# The compilers are built FROM SOURCE, so reverting a fix turns this RED instead of being
# masked by a stale build/ binary.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: missing_helper_error_exits_1: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL missing_helper_error_exits_1: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
"$CC" < src/main.cyr > "$T/x86" 2>"$T/eb" || { echo "FAIL missing_helper_error_exits_1: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
for f in aarch64 win cx; do
  "$T/x86" < "src/main_$f.cyr" > "$T/$f" 2>"$T/eb" || { echo "FAIL missing_helper_error_exits_1: could not build src/main_$f.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
  chmod +x "$T/$f"
done
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# ── fixtures (no lib/ includes: nothing may pre-register the helper name) ──────────────────
for op in sin cos exp2 atan exp ln log2; do
  printf 'var x = f64_%s(0);\nsyscall(60, 0);\n' "$op" > "$T/pf_$op.cyr"
done
cat > "$T/slice.cyr" <<'EOF'
fn main() { var s: [u8] = 0; var v = s[1]; return v; }
var r = main();
syscall(60, r);
EOF
cat > "$T/await.cyr" <<'EOF'
fn f() { return 1; }
fn main() { var x = await f(); return x; }
var r = main();
syscall(60, r);
EOF
cat > "$T/asyncfn.cyr" <<'EOF'
async fn f() { return 1; }
fn main() { var x = f(); return 0; }
var r = main();
syscall(60, r);
EOF
# an error AND a reachable undefined call: every backend reports both
cat > "$T/multi_err.cyr" <<'EOF'
fn main() { var a = undefined_var_q; var b = nope_fn(3); return a + b; }
var r = main();
syscall(60, r);
EOF
# anti-vacuous: the same ops with their helpers present
cat > "$T/pf_ok.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/math.cyr"
var x = f64_exp(0);
syscall(60, 0);
EOF
cat > "$T/async_ok.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/async.cyr"
async fn f() { return 1; }
fn main() { var x = await f(); return x; }
var r = main();
syscall(60, r);
EOF

# exits1 <compiler> <fixture> <async 0|1> <needle> — rc exactly 1, exactly one error line, the needle
exits1() {
  if [ "$3" = 1 ]; then CYRIUS_ASYNC=1 "$T/$1" < "$T/$2.cyr" > "$T/o" 2>"$T/e"; rc=$?
  else env -u CYRIUS_ASYNC "$T/$1" < "$T/$2.cyr" > "$T/o" 2>"$T/e"; rc=$?; fi
  if [ "$rc" -ne 1 ]; then _bad "$1 $2 (CYRIUS_ASYNC=$3): rc $rc, expected 1 (139 = the crash after the diagnostic)"; grep '^error' "$T/e" | head -2 | sed 's/^/      /'; return; fi
  n=$(grep -c '^error' "$T/e")
  if [ "$n" -ne 1 ]; then _bad "$1 $2 (CYRIUS_ASYNC=$3): $n error lines, expected exactly 1 (a refused site fell through to a second error)"; grep '^error' "$T/e" | head -3 | sed 's/^/      /'; return; fi
  if ! grep -q "$4" "$T/e"; then _bad "$1 $2 (CYRIUS_ASYNC=$3): '$4' not reported"; grep '^error' "$T/e" | head -2 | sed 's/^/      /'; return; fi
  pass=$((pass + 1))
}

# aarch64: the seven polyfills (x86/PE have native transcendentals; cx refuses float ops by name)
for op in sin cos exp2 atan exp ln log2; do
  exits1 aarch64 "pf_$op" 0 "f64_$op on aarch64 requires include \"lib/math.cyr\""
done
# every backend: slice, the async gate, and (with the gate open) the missing runtime helpers.
# cx is an ordinary row since 6.6.10: it compiled against a `return 0` _read_env stub, so
# CYRIUS_ASYNC=1 never opened the gate there and its rows were special-cased to the gate
# message — the refusal told the user to set a variable cycc_cx could not read.
for c in x86 aarch64 win cx; do
  exits1 "$c" slice 0 'slice subscript requires include "lib/slice.cyr"'
  exits1 "$c" await 0 'await requires CYRIUS_ASYNC=1'
  exits1 "$c" asyncfn 0 'async fn requires CYRIUS_ASYNC=1'
  exits1 "$c" await 1 'await needs include "lib/async.cyr"'
  exits1 "$c" asyncfn 1 'an async fn needs include "lib/alloc.cyr"'
done

# multi-error parity: rc 1, the undefined variable AND the undefined-call refusal
for c in x86 aarch64 win cx; do
  env -u CYRIUS_ASYNC "$T/$c" < "$T/multi_err.cyr" > "$T/o" 2>"$T/e"; rc=$?
  n=$(grep -c '^error' "$T/e")
  if [ "$rc" -ne 1 ] || [ "$n" -ne 2 ] || ! grep -q "undefined variable 'undefined_var_q'" "$T/e" || ! grep -q '^error.*undefined function' "$T/e"; then
    _bad "$c multi_err: rc $rc, $n error line(s) — expected rc 1 with the undefined variable AND the undefined-call refusal"; grep '^error' "$T/e" | head -3 | sed 's/^/      /'
  else pass=$((pass + 1)); fi
done

# ── anti-vacuous ────────────────────────────────────────────────────────────────────────────
"$T/aarch64" < "$T/pf_ok.cyr" > "$T/o" 2>"$T/e"; rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then _bad "aarch64 pf_ok: rc $rc — f64_exp WITH lib/math.cyr must build"; else pass=$((pass + 1)); fi
CYRIUS_ASYNC=1 "$T/x86" < "$T/async_ok.cyr" > "$T/o" 2>"$T/e"; rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then _bad "x86 async_ok: rc $rc — await/async WITH their libs must build"; grep '^error' "$T/e" | head -2; else pass=$((pass + 1)); fi

# ── structural: the two generic backstops stay in place ─────────────────────────────────────
for f in src/backend/x86/emit.cyr src/backend/aarch64/emit.cyr src/backend/cx/emit.cyr; do
  if awk '/^fn ECALLFIX\(S, fnidx\)/{f=1;n=0} f{n++; if (/if \(fnidx < 0\)/) {ok=1} if (n>12) f=0} END{exit ok?0:1}' "$f"; then pass=$((pass + 1))
  else _bad "$f: ECALLFIX no longer refuses a negative fn index in its first lines"; fi
done
if awk '/^fn FIXUP\(S\)/{f=1} f && /if \(ftype > 5 && _had_error == 1\) \{ fi = fi \+ 1; continue; \}/{ok=1; exit} END{exit ok?0:1}' src/backend/aarch64/fixup.cyr; then pass=$((pass + 1))
else _bad "src/backend/aarch64/fixup.cyr: FIXUP's relocation walk no longer skips an undecodable entry on a failed compile"; fi
if grep -B2 '^var fcnt = GFCNT(S);' src/main_cx.cyr | grep -q '^if (_had_error == 1)'; then pass=$((pass + 1))
else _bad "src/main_cx.cyr: the fixup walk is no longer guarded by _had_error"; fi

if [ "$fail" -ne 0 ]; then echo "FAIL missing_helper_error_exits_1: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS missing_helper_error_exits_1: $pass rows — 7 aarch64 polyfills + slice/await/async on x86/aarch64/PE/cx exit 1 with one error, multi-error parity on all four, helpers-present rows build, backstops in place"
exit 0
