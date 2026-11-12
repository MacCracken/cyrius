#!/usr/bin/env bash
# cyrius 6.7.18: `#inline` declines a fn whose body holds an `if` or a local `var`, however small. A finite-and-above
# check of 2 f64 parameters, under the 32-token limit, is refused when written with an `if` ("#inline ignored: body
# has control flow or a var declaration") or with a local, and taken only when written as one branch-free expression.
# ushma 2.0.0 port (M1d review): its range checks run 21 ns per three as calls and 6 ns per three inlined. Run:
#   bash docs/development/issues/repros/2026-11-11-inline-refuses-small-numeric-helpers-if-var.sh; echo $?
# Exits 1 while either of the first two forms is refused.
set -u
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cd "$d" || exit 2
mkdir -p src
cat > cyrius.cyml <<'EOF'
[package]
name = "inlinecf"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "src/main.cyr"
output = "build/inlinecf"

[deps]
stdlib = ["syscalls", "string", "alloc", "fmt", "io"]
EOF
cat > src/main.cyr <<'EOF'
const INF = 1.0 / 0.0;

# 1 when x is finite and above b: an if (refused).
#inline
fn gt_if(x: f64, b: f64): i64 {
    if (x > b) { return x < INF; }
    return 0;
}

# The same with a local (refused).
#inline
fn gt_var(x: f64, b: f64): i64 {
    var above = x > b;
    return above & (x < INF);
}

# The same as one expression (taken).
#inline
fn gt_expr(x: f64, b: f64): i64 {
    return (x > b) & (x < INF);
}

fn main() {
    alloc_init();
    var nan: f64 = 0.0 / 0.0;
    var n = gt_if(2.0, 1.0) + gt_var(2.0, 1.0) + gt_expr(2.0, 1.0);
    n = n + gt_if(nan, 1.0) + gt_var(nan, 1.0) + gt_expr(nan, 1.0);
    return 3 - n;
}
var r = main();
sys_exit_group(r);
EOF
out=$(cyrius build src/main.cyr build/inlinecf 2>&1)
rc=$?
echo "$out" | grep -E '#inline ignored' || true
if [ "$rc" -ne 0 ]; then echo "build failed (exit $rc)"; echo "$out" | tail -5; exit 2; fi
./build/inlinecf
run=$?
[ "$run" -eq 0 ] || { echo "the three checks disagree (exit $run)"; exit 2; }
if echo "$out" | grep -q '#inline ignored: body has control flow'; then
    echo "DEFECT: #inline declines a 2-parameter, under-32-token body for its if / var"
    exit 1
fi
echo "ok: all three forms inline"
exit 0
