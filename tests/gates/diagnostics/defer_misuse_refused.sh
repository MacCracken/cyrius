#!/bin/sh
# defer_misuse_refused.sh — 6.6.7 bite 1. `defer` and `break`/`continue` in a position they
# cannot honour are REFUSED with a named diagnostic and no binary; the valid neighbours of each
# refused shape still compile and compute; and `defer` inside a coroutine `async fn` runs
# exactly once, when the body completes.
#
# ⛔ WHY. Every refused row below compiled clean before 6.6.7 and did something silent:
#   top-level `defer {}`          its reached-flag is a fn frame slot, written through rbp = 0
#                                 (x86 and aarch64 SIGSEGV, exit 139); cx ran nothing (exit 3)
#   `return` inside a defer body  re-entered the epilogue walker, which re-ran the block (50x,
#                                 bounded only by the probe's own counter); a TAIL-CALL
#                                 `return g(x);` jmp'd out, replacing the value and skipping
#                                 every earlier-registered defer
#   `break` inside a defer body   jumped back into the loop the defer was registered in (20x)
#   `break` with no loop/switch   an unpatched chain link — a wild jump
#   `continue` with no loop       jumped to the stale loop top of the LAST fn that had a loop
#                                 (SIGSEGV)
#   break/continue in a closure   targeted the ENCLOSING fn's loop from inside the closure
# and a `defer` in a coroutine never ran at all: its flag was SET in the heap frame and TESTED
# on the stack frame, because the coroutine mode was cleared before the epilogue.
# 6.6.15: a `defer` or `secret var` in a `#naked` fn is refused too. A naked fn has no epilogue
# (its body ends in its own asm return), so the walker emitted after the body was unreachable:
# the defer block never ran (the probe below exited 0, want 5) and the secret was never zeroised.
#
# ⚠ A SHELL gate, not a .tcyr: refusals are compile-time (a .tcyr can only run what compiled),
# and `async`/`await` are gated behind CYRIUS_ASYNC=1, which the tcyr runner cannot set. The
# runtime nested-fn rows live in tests/tcyr/crossos/defer_every_return_path.tcyr.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: defer_misuse_refused: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL defer_misuse_refused: no build/cycc"; exit 1; }
# Build stage1 FROM SOURCE so a source revert turns this gate RED instead of being masked by a
# stale build/cycc. cd FIRST: src/main.cyr's includes resolve from the CWD, so built from
# anywhere else stage1 would be compiled from THAT directory's src/.
cd "$R"
"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL defer_misuse_refused: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"
fail=0
pass=0

# refuse <label> <needle> [env] — $T/r.cyr must fail to compile, NAME the reason, and emit no
# binary.
refuse() {
  env ${3:-CYRIUS_X=0} "$T/stage1" < "$T/r.cyr" > "$T/r.out" 2>"$T/r.err"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL: $1 COMPILED (exit 0) — it must be refused"; fail=$((fail+1)); return; fi
  if ! grep -q "$2" "$T/r.err"; then
    echo "  FAIL: $1 was refused without naming the reason (want: $2)"
    sed -n 1,2p "$T/r.err" | sed 's/^/        /'; fail=$((fail+1)); return; fi
  if [ -s "$T/r.out" ]; then
    echo "  FAIL: $1 was refused but still emitted $(wc -c < "$T/r.out") bytes"; fail=$((fail+1)); return; fi
  echo "  ok:   refused — $1"; pass=$((pass+1))
}
# runs <label> <want-exit> [env] — $T/r.cyr must compile and exit with <want-exit>.
runs() {
  env ${3:-CYRIUS_X=0} "$T/stage1" < "$T/r.cyr" > "$T/r.x" 2>"$T/r.err" || {
    echo "  FAIL: $1 did not compile"; grep -m2 '^error' "$T/r.err" | sed 's/^/        /'; fail=$((fail+1)); return; }
  chmod +x "$T/r.x"; timeout 20 "$T/r.x" > "$T/r.stdout"; g=$?
  if [ "$g" -ne "$2" ]; then
    echo "  FAIL: $1 exited $g, want $2"; fail=$((fail+1)); return; fi
  echo "  ok:   $1 (exit $g)"; pass=$((pass+1))
}

# ── top level ────────────────────────────────────────────────────────────────────────────
printf 'var s = 3;\ndefer { s = 4; }\nsyscall(60, s);\n' > "$T/r.cyr"
refuse "top-level defer" "defer only allowed inside a function"
printf 'var s = 3;\nfn f(): i64 { defer { s = 4; } return 0; }\nvar z = f();\nsyscall(60, s);\n' > "$T/r.cyr"
runs "control: the same defer inside a fn" 4

# ── escapes out of a defer body ──────────────────────────────────────────────────────────
printf 'var c = 0;\nfn f(): i64 { defer { c = c + 1; if (c < 50) { return 7; } } return 1; }\nvar z = f();\nsyscall(60, c);\n' > "$T/r.cyr"
refuse "return inside a defer body" "return inside a defer body"
cat > "$T/r.cyr" <<'EOF'
include "lib/tagged.cyr"
var c = 0;
fn g(): Result { return Err(3); }
fn f(): Result { defer { var v = g()?; c = c + 1; } return Ok(1); }
var z = f();
syscall(60, c);
EOF
refuse "\`?\` inside a defer body" "return inside a defer body"
# `return CALL(...)` is a TAIL CALL (a jmp, no rp_vec entry) — it slipped past the rp_vec-growth
# check: the callee's value replaced f's and every earlier-registered defer was skipped (exit
# 33 = z 8, c 1 — the `c + 10` defer never ran).
printf 'var c = 0;\nfn g(x): i64 { return x + 7; }\nfn f(): i64 { defer { c = c + 10; } defer { c = c + 1; return g(c); } return 1; }\nvar z = f();\nsyscall(60, z * 100 + c);\n' > "$T/r.cyr"
refuse "tail-call return inside a defer body" "return inside a defer body"
cat > "$T/r.cyr" <<'EOF2'
include "lib/tagged.cyr"
var c = 0;
fn f(): Result { defer { c = c + 1; if (c < 50) { return Err(3); } } return Ok(1); }
var z = f();
syscall(60, c);
EOF2
refuse "\`return Err(..)\` inside a defer body" "return inside a defer body"
printf 'var c = 0;\nfn g(x): i64 { return x + 7; }\nfn f(): i64 { return g(1); }\nvar z = f();\nsyscall(60, z);\n' > "$T/r.cyr"
runs "control: a tail call outside any defer body" 8
printf 'var c = 0;\nfn h(): i64 { var i = 0; while (i < 3) { defer { c = c + 1; if (c < 20) { break; } } i = i + 1; } return 1; }\nvar z = h();\nsyscall(60, c);\n' > "$T/r.cyr"
refuse "break out of a defer body into its loop" "break cannot leave a defer body"
printf 'var c = 0;\nfn h(): i64 { var i = 0; while (i < 3) { i = i + 1; defer { c = c + 1; if (c < 20) { continue; } } } return 1; }\nvar z = h();\nsyscall(60, c);\n' > "$T/r.cyr"
refuse "continue out of a defer body into its loop" "continue cannot leave a defer body"
printf 'var c = 0;\nfn k(): i64 { defer { var j = 0; while (j < 3) { j = j + 1; if (j == 2) { break; } } c = c + j; } return 1; }\nvar z = k();\nsyscall(60, c);\n' > "$T/r.cyr"
runs "control: a loop OPENED inside a defer body breaks normally" 2
printf 'var c = 0;\nfn k(x): i64 { defer { switch (x) { case 1: c = 5; break; default: c = 9; } } return 1; }\nvar z = k(1);\nsyscall(60, c);\n' > "$T/r.cyr"
runs "control: a switch opened inside a defer body breaks normally" 5

# ── #naked: no epilogue, so nothing an epilogue runs ─────────────────────────────────────
printf 'var g = 0;\n#naked\nfn f() { defer { g = 5; } asm { 0xC3; } }\nfn main(): i64 { f(); return g; }\nvar r = main();\nsyscall(60, r);\n' > "$T/r.cyr"
refuse "defer in a #naked fn" "defer is not allowed in a #naked fn"
printf '#naked\nfn f(): i64 {\n    secret var k[16];\n    asm { 0xC3; }\n}\nsyscall(60, 0);\n' > "$T/r.cyr"
refuse "secret var in a #naked fn" "secret var is not allowed in a #naked fn"
printf 'var g = 0;\n#naked\nfn nk() { asm { 0xC3; } }\nfn f(): i64 { secret var k[16]; defer { g = 5; } nk(); return 0; }\nvar z = f();\nsyscall(60, g);\n' > "$T/r.cyr"
runs "control: a #naked fn beside a fn with a secret var and a defer" 5

# ── break / continue with nothing to leave in THIS fn ────────────────────────────────────
printf 'fn f(x): i64 { if (x > 0) { break; } return 3; }\nvar r = f(1);\nsyscall(60, r);\n' > "$T/r.cyr"
refuse "break with no enclosing loop" "break outside a loop or switch"
printf 'var hits = 0;\nfn a(n): i64 { var i = 0; while (i < n) { hits = hits + 1; i = i + 1; } return 0; }\nfn b(x): i64 { if (x > 0) { continue; } return 3; }\nvar r0 = a(2);\nvar r = b(1);\nsyscall(60, 40 + hits);\n' > "$T/r.cyr"
refuse "continue with no enclosing loop (after another fn's loop)" "continue outside a loop"
printf 'var i = 0;\nbreak;\nsyscall(60, i);\n' > "$T/r.cyr"
refuse "top-level break with no loop" "break outside a loop or switch"
# The switch/match exit must give its break target BACK: without that, a `break` AFTER a
# completed switch compiled to an unpatched chain link (a wild jump).
printf 'fn f(x): i64 { var r = 0; switch (x) { case 1: r = 7; break; default: r = 9; } if (r > 0) { break; } return r; }\nsyscall(60, f(1));\n' > "$T/r.cyr"
refuse "break after a completed switch, no loop" "break outside a loop or switch"
printf 'fn f(x): i64 { var r = 0; match (x) { 1 => { r = 7; } _ => { r = 9; } } if (r > 0) { break; } return r; }\nsyscall(60, f(1));\n' > "$T/r.cyr"
refuse "break after a completed match, no loop" "break outside a loop or switch"
printf 'fn f(x): i64 { var r = 0; match (x) { 1 => { r = 7; } _ => { r = 9; } } if (r > 0) { continue; } return r; }\nsyscall(60, f(1));\n' > "$T/r.cyr"
refuse "continue after a completed match, no loop" "continue outside a loop"
cat > "$T/r.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn f(): i64 { var s = 0; var i = 0; while (i < 3) { i = i + 1; var g = |x| { if (x > 1) { continue; } return x; }; s = s + fncall1(g, i); } return s; }
var z = f();
syscall(60, z);
EOF
refuse "continue inside a closure targeting the enclosing loop" "continue outside a loop"
cat > "$T/r.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn f(): i64 { var s = 0; var i = 0; while (i < 3) { i = i + 1; var g = |x| { if (x > 1) { break; } return x; }; s = s + fncall1(g, i); } return s; }
var z = f();
syscall(60, z);
EOF
refuse "break inside a closure targeting the enclosing loop" "break outside a loop or switch"
printf 'fn f(x): i64 { var r = 0; switch (x) { case 1: r = 7; break; default: r = 9; } return r; }\nvar z = f(1);\nsyscall(60, z);\n' > "$T/r.cyr"
runs "control: break leaves a switch with no loop around it" 7
printf 'fn f(): i64 { var s = 0; for (var i = 0; i < 5; i = i + 1) { if (i == 2) { continue; } if (i == 4) { break; } s = s + i; } return s; }\nvar z = f();\nsyscall(60, z);\n' > "$T/r.cyr"
runs "control: break/continue in a for loop" 4
printf 'var s = 0;\nvar i = 0;\nwhile (i < 5) { i = i + 1; if (i == 2) { continue; } if (i == 4) { break; } s = s + i; }\nsyscall(60, s);\n' > "$T/r.cyr"
runs "control: break/continue in a top-level while" 4

# ── coroutines: defer is SUPPORTED and runs once, at completion ─────────────────────────
PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
'
# exit = c1*100 + c2*10 + c3 after three forces: 0,0,1 is right (the body completes on the
# third entry). Pre-fix this was 0,0,0 — the flag set and the flag test used different frames.
for pos in before after; do
  if [ "$pos" = before ]; then D1='    defer { cran = cran + 1; }'; D2=''; else D1=''; D2='    defer { cran = cran + 1; }'; fi
  cat > "$T/r.cyr" <<EOF
${PRE}
var cran = 0;
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
${D1}
    var x = 1;
    var s1 = await nopark();
${D2}
    x = x + 10;
    var s2 = await nopark();
    x = x + 100;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C); var c1 = cran;
    var r2 = future_force(C); var c2 = cran;
    var r3 = future_force(C); var c3 = cran;
    if (r3 != 111) { return 99; }
    return c1 * 100 + c2 * 10 + c3;
}
var e = main();
syscall(60, e);
EOF
  runs "coroutine defer registered $pos the first await runs once, at completion" 1 CYRIUS_ASYNC=1
done
cat > "$T/r.cyr" <<EOF
${PRE}
var cran = 0;
fn nopark(): i64 { return 0; }
async fn flat(): i64 { defer { cran = cran + 1; } var r = nopark(); return 5; }
fn main(): i64 { alloc_init(); var w = await flat(); return w * 10 + cran; }
var e = main();
syscall(60, e);
EOF
runs "control: defer in a flat (no mid-body await) async fn" 51 CYRIUS_ASYNC=1
# A closure literal inside a coroutine body is NOT a coroutine: with the mode leaked, its
# body was addressed through the enclosing coroutine's heap frame (106 read as 206).
cat > "$T/r.cyr" <<EOF
${PRE}
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
    var x = 1;
    var s1 = await nopark();
    var f = |y| y * 3 + 1;
    x = x + 5;
    var s2 = await nopark();
    x = x + 100;
    return x;
}
fn main(): i64 { alloc_init(); var C = steps(0); var a = future_force(C); var b = future_force(C); return future_force(C); }
var e = main();
syscall(60, e);
EOF
runs "a closure inside a coroutine body keeps the coroutine's locals" 106 CYRIUS_ASYNC=1
cat > "$T/r.cyr" <<EOF
${PRE}
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
    var x = 1;
    defer { var q = await nopark(); }
    var s1 = await nopark();
    return x;
}
fn main(): i64 { alloc_init(); var C = steps(0); return 0; }
var e = main();
syscall(60, e);
EOF
refuse "await (a suspend) inside a coroutine's defer body" "await cannot suspend inside a defer body" CYRIUS_ASYNC=1

echo "defer_misuse_refused: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
