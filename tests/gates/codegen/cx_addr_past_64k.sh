#!/bin/sh
# cx_addr_past_64k.sh — cx string / global / fn-pointer addresses past 0xFFFF.
#
# v6.6.4. Every cx address emitter (ESADDR, EVADDR, EVADDR_X1, EVLOAD, EVSTORE,
# ELOAD_FN_ADDR in src/backend/cx/emit.cyr) emitted a BARE 4-byte `movi r, 0`
# placeholder, while the fixup loop in src/main_cx.cyr patched "the movhi that
# follows it" whenever the resolved address exceeded 0xFFFF. CX_MOVI(S, r, 0) never
# emits a movhi for a zero value, so that patch landed on bytes 2-3 of WHATEVER
# INSTRUCTION CAME NEXT for strings (ftype 1) and globals (ftype 0) — a wrong byte,
# a wrong global, or garbage depending on what that instruction was — while the
# fn-pointer arm (ftype 3) had no movhi write at all and simply TRUNCATED the code
# offset to 16 bits. Found while fixing the lexer's 16-bit string-length pack (same
# class: a 16-bit field silently too narrow — see
# tests/tcyr/frontend/string_literal_64k.tcyr). The emitters now always emit the
# movhi slot (`ra |= 0` when unpatched) so every fixup has a real instruction to
# write, and the ftype-3 arm patches it too.
#
# ⛔ WHY A SHELL GATE: the .tcyr surface (lib/assert.cyr + lib/fmt.cyr) does not
# compile on the cx backend, so the frontend .tcyr covers x86/aarch64/PE and cx has
# to run under cxvm — the same split cx_multi_return.sh records.
#
# Mutation-proven against the 6.6.3 compiler (this file against a HEAD tree copy):
# axis 1 = rc 1, axis 2 = rc 1, axis 3 = rc 104 (want 47), axis 4 = rc 76 (want 42);
# dropping the movhi slot from any ONE emitter reds at least one axis (EVADDR: axis 3 = 85).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cx_addr_past_64k: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$D"' EXIT

cat src/main_cx.cyr | ./build/cycc > "$D/cc" 2>/dev/null; chmod +x "$D/cc"
cat programs/cxvm.cyr | ./build/cycc > "$D/vm" 2>/dev/null; chmod +x "$D/vm"

pass=0; fail=0
run_case() {  # $1 label  $2 source-file  $3 expected exit code
    cat "$2" | "$D/cc" > "$D/c.cyx" 2>"$D/c.err" || { echo "  FAIL: $1 (compile rc=$?)"; cat "$D/c.err"; fail=$((fail+1)); return; }
    [ -s "$D/c.cyx" ] || { echo "  FAIL: $1 (empty .cyx)"; fail=$((fail+1)); return; }
    RC=0
    timeout 60 "$D/vm" < "$D/c.cyx" >/dev/null 2>&1 || RC=$?
    if [ "$RC" = "$3" ]; then
        printf '  ok: %-44s exit=%s\n' "$1" "$RC"; pass=$((pass+1))
    else
        printf '  FAIL: %-42s exit=%s (want %s)\n' "$1" "$RC" "$3"; fail=$((fail+1))
    fi
}

# rep CH N — N copies of the character CH (no external tools beyond awk)
rep() { awk -v c="$1" -v n="$2" 'BEGIN { s = ""; for (i = 0; i < n; i++) s = s c; printf "%s", s }'; }

echo "axis 1 — 17 x 4096-byte literals push the pool past 0xFFFF; the LAST one must read back:"
{
    i=0
    while [ $i -lt 17 ]; do
        # each filler starts with a distinct byte — the lexer INTERNS identical literals
        printf 'fn s%d() { return "%d%s"; }\n' "$i" "$i" "$(rep a 4094)"; i=$((i+1))
    done
    # The literal is bound INLINE so the instruction after the movi is the local
    # store (whose operand bytes the mis-aimed patch clobbers); behind a `return`
    # the next instruction is `ret`, which ignores those bytes and hid the defect.
    printf 'fn main(): i64 { var p = "Z%s"; if (load8(p) != 90) { return 1; } if (load8(p + 1) != 98) { return 2; } if (load8(p + 4096) != 0) { return 3; } return 0; }\n' "$(rep b 4095)"
    printf 'var r = main();\nsyscall(60, r);\n'
} > "$D/a1.cyr"
[ "$(wc -c < "$D/a1.cyr")" -gt 70000 ] || { echo "  FAIL: axis 1 fixture too small ($(wc -c < "$D/a1.cyr") B) — rep() produced nothing"; fail=$((fail+1)); }
run_case "17 literals, last at pool offset > 0xFFFF" "$D/a1.cyr" 0

echo "axis 2 — 20 literals (a second pool layout; 6.6.3 read a wrong byte here too):"
{
    i=0
    while [ $i -lt 20 ]; do
        printf 'fn s%d() { return "%d%s"; }\n' "$i" "$i" "$(rep a 4094)"; i=$((i+1))
    done
    printf 'fn main(): i64 { var p = "Y%s"; if (load8(p) != 89) { return 1; } return 0; }\n' "$(rep c 4095)"
    printf 'var r = main();\nsyscall(60, r);\n'
} > "$D/a2.cyr"
[ "$(wc -c < "$D/a2.cyr")" -gt 82000 ] || { echo "  FAIL: axis 2 fixture too small — rep() produced nothing"; fail=$((fail+1)); }
run_case "20 literals" "$D/a2.cyr" 0

echo "axis 3 — a global past 0xFFFF of data (bare top-level array = N x 8 bytes):"
{
    # `after` sits past 72,000 bytes of `big`; it is read (EVLOAD), written (EVSTORE) and
    # its ADDRESS taken (EVADDR — `&big` alone would not exercise that emitter's
    # >0xFFFF path, since big is the FIRST global and sits low).
    printf 'var big[9000];\nvar after = 7;\n'
    printf 'fn main(): i64 { after = after + 35; store64(&big + 71992, 5); var q = &after; return load64(q) + load64(&big + 71992); }\n'
    printf 'var r = main();\nsyscall(60, r);\n'
} > "$D/a3.cyr"
run_case "global read/write/&addr past 0xFFFF" "$D/a3.cyr" 47

echo "axis 4 — a fn pointer whose CODE offset is past 0xFFFF (cx codebuf is 512 KiB):"
{
    printf 'fn filler(): i64 { var x = 0;\n'
    i=0
    while [ $i -lt 2500 ]; do
        printf '    x = x + 1; x = x + 2; x = x + 3;\n'; i=$((i+1))
    done
    printf '    return x; }\n'
    printf 'fn target(v): i64 { return v + 40; }\n'
    printf 'fn main(): i64 { var f = &target; return callptr(f, 2); }\n'
    printf 'var r = main();\nsyscall(60, r);\n'
} > "$D/a4.cyr"
run_case "callptr(&fn) with fn past 64 KB of code" "$D/a4.cyr" 42

echo "cx_addr_past_64k: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
