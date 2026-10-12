#!/bin/sh
# 6.7.10 — a program that includes the sigil fold, or the TLS stack built on it, compiles with
# NO warning: `include "lib/sigil.cyr"`, `include "lib/tls.cyr"` and `include "lib/tls_native.cyr"`
# each build at rc 0, print nothing that starts with `warning`, and run (exit 0).
#
# ⛔ THE DEFECT (issue 2026-10-11-sigil-static-read-buffer-warns-on-every-build). sigil's
# `hash_file_into` declared its file-read scratch as `var buf[262144];` — 4096 B banked 64 ways —
# inside the fn. That is over the per-fn frame budget, so the compiler gave it STATIC storage and
# said so on every build that parsed the fn, called or not, plus the whole-program advisory the
# 256 KB carried sigil past:
#   warning:lib/sigil.cyr:28103:12: array local over the per-fn frame budget gets STATIC storage: …
#   warning: large static data (367664 bytes) — consider alloc() for buffers >4KB
# Two warnings on every TLS / crypto consumer's build: the noise that teaches a reader to skip
# warnings. Fixed at the SOURCE in sigil 3.13.12 (a 4 KB per-call stack buffer), refolded here.
#
# No .tcyr can see a warning (it does not change the exit code) — hence a gate.
#   axis 1  each of the three bare includes: rc 0, zero `warning` lines, the binary exits 0
#   axis 2  ANTI-VACUOUS: the same harness counts the two warnings on a probe that has the old
#           shape (an over-budget fn-local array, 262144 B) — the grep is not blind
#
# MUTATION LEDGER (6.7.10, measured in the refold worktree)
#   a. lib/sigil.cyr back to 3.13.11 (the 6.7.9 fold) -> axis 1 RED on all three includes (2
#      warnings each: the STATIC-storage warning and the large-static advisory)
# The tree -> PASS.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=tls_sigil_include_warning_free
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
fail=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fail=1; }

# axis 1
n=0
for m in sigil tls tls_native; do
    printf 'include "lib/%s.cyr"\nsyscall(60, 0);\n' "$m" > "$T/$m.cyr"
    rc=0; "$CC" < "$T/$m.cyr" > "$T/$m" 2> "$T/$m.err" || rc=$?
    w=$(grep -c '^warning' "$T/$m.err")
    if [ "$rc" -ne 0 ]; then bad "axis 1: include \"lib/$m.cyr\" does not compile (rc $rc): $(grep -m1 '^error' "$T/$m.err")"; continue; fi
    if [ "$w" -ne 0 ]; then bad "axis 1: include \"lib/$m.cyr\" prints $w warning(s): $(grep -m1 '^warning' "$T/$m.err" | cut -c1-140)"; continue; fi
    chmod +x "$T/$m"; xr=0; "$T/$m" > /dev/null 2>&1 || xr=$?
    if [ "$xr" -ne 0 ]; then bad "axis 1: include \"lib/$m.cyr\" builds clean but exits $xr"; continue; fi
    ok "axis 1: include \"lib/$m.cyr\" — rc 0, no warning, runs (exit 0)"
    n=$((n + 1))
done

# axis 2: the harness sees the old shape's two warnings
cat > "$T/old.cyr" <<'EOF'
fn f(): i64 { var buf[262144]; store8(&buf, 1); return load8(&buf); }
syscall(60, f() - 1);
EOF
"$CC" < "$T/old.cyr" > "$T/old" 2> "$T/old.err"
wo=$(grep -c '^warning' "$T/old.err")
if [ "$wo" -ge 2 ] && grep -q 'STATIC storage' "$T/old.err" && grep -q 'large static data' "$T/old.err"; then
    ok "axis 2: the old shape (a 262144 B fn-local array) prints both warnings ($wo) — the count is not blind"
else
    bad "axis 2: the old shape printed $wo warning(s), want the STATIC-storage warning and the large-static advisory"
fi

[ "$fail" -eq 0 ] && [ "$n" -eq 3 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (include \"lib/sigil.cyr\", \"lib/tls.cyr\" and \"lib/tls_native.cyr\" each compile with no warning and run; the harness sees the old shape's two warnings)"
exit 0
