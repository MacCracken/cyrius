#!/bin/sh
# toplevel_indirect_call.sh — 6.6.16 (H1). `fncall0..8` and `callptr` at TRUE TOP LEVEL dispatch
# a capturing closure, on every target, and a top-level `callptr` compiles.
#
# ⛔ THE DEFECT (hisab, filed 2026-10-03 against pins 6.6.0 - 6.6.14). Since 6.5.17 an indirect
# call is lowered by PINDIRECT_CALL (src/frontend/parse_expr.cyr), which spills the callee to
# FRAME slots and decides "closure or bare fn pointer" at run time from bit 63. Top-level code
# has no frame, so both lowering gates — the expression one in _PARSE_FACTOR_IMPL and the
# statement one in _PARSE_STMT_IMPL — read `_cur_fn_ix >= 0`, and PINDIRECT_CALL itself refused
# top level ("must be inside a function"). `callptr` was therefore a compile error at top level,
# and `fncallN` silently stayed an ordinary call into lib/fnptr.cyr, whose asm calls the RAW
# value. A capturing closure that escaped a fn (returned, stashed in a global, round-tripped
# through memory) is its env object with bit 63 set: x86_64 / aarch64 / Mach-O SIGSEGV (139),
# Windows 0xC0000005, and on cx — lib/fnptr.cyr has no cx arm — EVERY top-level fncallN
# returned 0, plain fn pointers included (no gate ran cx there, so three crossos files had been
# failing on cxvm unseen). The gate comment said the library call was "the only thing that ever
# worked there anyway". That premise was false for an escaped closure.
#
# ⭐ THE FIX: a top-level indirect call opens a per-call-site MICRO-FRAME (ETLFRAME_OPEN /
# ETLFRAME_CLOSE in src/backend/{x86,aarch64,cx}/emit.cyr), sized at the close from the slots the
# call used, so the same lowering runs at every depth; both gates and the refusal are gone. In-fn
# codegen is unchanged (PINDIRECT_CALL calls its body directly there). On x86 the frame keeps
# rsp's parity (8 + size == 0 mod 16); on PE it carries the page-walk stack probe, with the size
# in r10 so rax survives.
#
# ROWS (compilers are BUILT FROM THIS TREE into a private dir; build/cycc_* is never read)
#   1. x86_64: the filed repro VERBATIM builds to more than 1 KB (an empty output is executable
#      and exits 0) and exits 0; tests/tcyr/crossos/closure_escape_dispatch.tcyr (its TOP-LEVEL
#      section) exits 0.
#   2. aarch64 under qemu-aarch64 (src/main_aarch64.cyr): the repro and the .tcyr exit 0.
#   3. PE under wine, in a PRIVATE prefix (CYRIUS_TARGET_WIN=1): the repro and the .tcyr exit 0.
#   4. cx under cxvm (src/main_cx.cyr, programs/cxvm.cyr): the repro, the .tcyr, a top-level
#      fncall1 on a PLAIN fn pointer (42, was 0), and the three crossos/stdlib files that failed
#      on cxvm before (toplevel_block_closure 10, toplevel_for_in 1, fncall_ceiling 14) exit 0.
#      The release gate's cross-OS leg never runs cx; this row is cx's only coverage.
#   5. A top-level `callptr(...)` compiles and returns 42, and the refusal text is gone from src/.
#   6. PE bytes: a fixture with 3 top-level indirect calls carries the r10 page-walk micro-frame
#      exactly 3 times, and the same calls made inside a fn carry it 0 times.
#   Rows 2 and 3 SKIP (the gate then exits 77, never PASS) when qemu-aarch64 / wine is absent.
#
# MUTATION LEDGER (measured 6.6.16: each mutant a scratch copy of the tree with ONE edit, this
# gate run inside it, so every compiler is rebuilt from the mutated source; 15 rows):
#   a. the expression gate restored (`if (_cur_fn_ix >= 0) {` around the fncallN lowering in
#      _PARSE_FACTOR_IMPL)                                          -> 13 red: the repro 139 on
#        x86 and aarch64, 5 (0xC0000005) under wine, 3 on cx; the .tcyr 139 / 139 / 5 / 13;
#        cx plain 214 (0 - 42); the three cx files 10 / 1 / 14; row 6 counts 2 walks for 3
#   b. the statement gate restored (`_cur_fn_ix >= 0` on `_stmt_fcn` in _PARSE_STMT_IMPL)
#                                                                   -> 5 red: the .tcyr's
#        `fncall1(f, 7);` row 139 on x86 and aarch64, 5 under wine, 1 on cx; row 6 2 walks
#        (its first cut used a NON-capturing setter, a plain code pointer that worked even
#        through lib/fnptr.cyr — the row was green under this mutant until it captured)
#   c. the top-level refusal restored at the head of PINDIRECT_CALL -> 15 red: nothing with a
#        top-level indirect call compiles, and the refusal text is back in src/
#   d. x86 ETLFRAME_CLOSE without the parity term (frame rounded to 16, not 16 - 8)
#                                                                   -> 1 red: the .tcyr's
#        alignment rows on x86 (callee lands at 8 where a direct call lands at 0). PE stays
#        green — ECALLPTR_PE re-aligns every indirect call itself
#   e. the PE page walk dropped from ETLFRAME_OPEN (plain `sub rsp, imm32`)  -> 1 red: row 6
#   pre-fix tree (src/ of the 6.6.16 slot open, 0bf9b773)          -> 15 red, 0 green
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=toplevel_indirect_call
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$T/wp"
_cleanup() {
    if [ -d "$WP" ] && command -v wineserver > /dev/null 2>&1; then WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1; fi
    rm -rf "$T"
}
trap _cleanup EXIT
ulimit -c 0 2>/dev/null
REPRO=docs/development/issues/repros/2026-10-03-hisab-toplevel-fncall-capturing-closure-segv.cyr
TCYR=tests/tcyr/crossos/closure_escape_dispatch.tcyr
[ -f "$REPRO" ] || { echo "FAIL $G: the filed repro is missing: $REPRO"; exit 1; }
[ -f "$TCYR" ] || { echo "FAIL $G: missing $TCYR"; exit 1; }

"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" && [ -s "$T/x86" ] \
  || { echo "FAIL $G: could not build src/main.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
fail=0
pass=0
skips=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# _leg <label> <compile-cmd> <run-cmd> <source> : compile with "$2" < source, run with "$3"
# (empty = native). Sets BRC to the compile's exit code (and BSZ to the output's size) and LRC
# to the run's exit code; LRC is -1 when nothing was run.
_leg() {
    LRC=-1
    $2 < "$4" > "$T/$1.bin" 2> "$T/$1.err"; BRC=$?
    BSZ=$(wc -c < "$T/$1.bin" | tr -d ' ')
    if [ "$BRC" -ne 0 ] || [ "${BSZ:-0}" -le 1024 ]; then return 0; fi
    chmod +x "$T/$1.bin"
    # The group's own stderr is dropped too: a crash is reported by LRC, not by the shell's
    # "Segmentation fault" job message.
    if [ -n "$3" ]; then { $3 "$T/$1.bin" > "$T/$1.out" 2>&1 < /dev/null; } 2> /dev/null; LRC=$?
    else { "$T/$1.bin" > "$T/$1.out" 2>&1 < /dev/null; } 2> /dev/null; LRC=$?; fi
    return 0
}
# _want <label> <compile-cmd> <run-cmd> <source> <what>: the leg must exit 0
_want() {
    _leg "$1" "$2" "$3" "$4"
    if [ "$LRC" -eq -1 ]; then
        _bad "$1: $5 did not compile (rc $BRC, ${BSZ:-0} bytes; an empty output is executable and exits 0)"
        grep -E '^error' "$T/$1.err" | head -2 | cut -c1-160 | sed 's/^/      /'
    elif [ "$LRC" -ne 0 ]; then
        _bad "$1: $5 exited $LRC, want 0"
        grep -E 'FAIL|failed' "$T/$1.out" | head -3 | cut -c1-160 | sed 's/^/      /'
    else
        pass=$((pass + 1))
    fi
}

# ── row 1: x86_64 ───────────────────────────────────────────────────────────────────────────
_want x86_repro "$T/x86" "" "$REPRO" "the filed repro"
_want x86_tcyr "$T/x86" "" "$TCYR" "closure_escape_dispatch.tcyr"

# ── row 2: aarch64 under qemu ───────────────────────────────────────────────────────────────
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$T/x86" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/eb" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        _want a64_repro "$T/cc_a64" qemu-aarch64 "$REPRO" "the filed repro (aarch64)"
        _want a64_tcyr "$T/cc_a64" qemu-aarch64 "$TCYR" "closure_escape_dispatch.tcyr (aarch64)"
    else
        _bad "aarch64: src/main_aarch64.cyr did not build"
    fi
else
    echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; skips=$((skips + 1))
fi

# ── row 3: PE under wine, private prefix ────────────────────────────────────────────────────
if command -v wine > /dev/null 2>&1; then
    printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$T/x86" > "$T/wcc"; chmod +x "$T/wcc"
    printf '#!/bin/sh\nWINEPREFIX="%s" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1"\n' "$WP" > "$T/wrun"
    chmod +x "$T/wrun"
    _want pe_repro "$T/wcc" "$T/wrun" "$REPRO" "the filed repro (PE)"
    _want pe_tcyr "$T/wcc" "$T/wrun" "$TCYR" "closure_escape_dispatch.tcyr (PE)"
else
    echo "  SKIP: PE leg (wine not installed)"; skips=$((skips + 1))
fi

# ── row 4: cx under cxvm ────────────────────────────────────────────────────────────────────
if "$T/x86" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/eb" && [ -s "$T/cc_cx" ] \
   && "$T/x86" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/eb2" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    printf '#!/bin/sh\nexec "%s" < "$1"\n' "$T/cxvm" > "$T/cxrun"; chmod +x "$T/cxrun"
    printf 'include "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\nfn add41(x) { return x + 41; }\nvar r = fncall1(&add41, 1);\nsyscall(60, r - 42);\n' > "$T/plain.cyr"
    _want cx_repro "$T/cc_cx" "$T/cxrun" "$REPRO" "the filed repro (cx)"
    _want cx_tcyr "$T/cc_cx" "$T/cxrun" "$TCYR" "closure_escape_dispatch.tcyr (cx)"
    _want cx_plain "$T/cc_cx" "$T/cxrun" "$T/plain.cyr" "a top-level fncall1(&add41, 1) (cx; returned 0 before 6.6.16)"
    for f in tests/tcyr/crossos/toplevel_block_closure.tcyr tests/tcyr/crossos/toplevel_for_in.tcyr \
             tests/tcyr/stdlib/fncall_ceiling.tcyr; do
        _want "cx_$(basename "$f" .tcyr)" "$T/cc_cx" "$T/cxrun" "$f" "$f (cx)"
    done
else
    _bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"
fi

# ── row 5: a top-level callptr compiles; the refusal is gone ───────────────────────────────
printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\nfn mk(b) { return |x| b + x; }\nvar r = callptr(mk(41), 1);\nsyscall(60, r - 42);\n' > "$T/cp.cyr"
_want x86_callptr "$T/x86" "" "$T/cp.cyr" "a top-level callptr(mk(41), 1)"
if grep -rqF 'must be inside a function, not at top level' src/; then
    _bad "the top-level indirect-call refusal text is still in src/"
else
    pass=$((pass + 1))
fi

# ── row 6: PE bytes — the probed micro-frame is emitted for top-level calls only ────────────
# 49 89 E3 / 4D 29 D3 / 4C 39 DC / 76 0D / 48 81 EC 00 10 00 00 / 48 89 24 24 / EB EE / 4C 89 DC:
# the page walk with the size in r10. A PE fn prologue walks with the size in eax (49 29 C3), so
# `4d29d3` never matches one.
WALK=4989e34d29d34c39dc760d4881ec0010000048892424ebee4c89dc
_walks() { od -An -v -tx1 "$1" | tr -d ' \n' | { grep -o "$WALK" || true; } | wc -l | tr -d ' '; }
HD='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn mk(b) { return |x| b + x; }'
printf '%s\nvar g = mk(41);\nvar a = fncall1(g, 1);\nvar b = callptr(g, 1);\nfncall1(g, 1);\nsyscall(60, a + b - 84);\n' "$HD" > "$T/w_top.cyr"
printf '%s\nfn run() { var g = mk(41); var a = fncall1(g, 1); var b = callptr(g, 1); fncall1(g, 1); return a + b - 84; }\nsyscall(60, run());\n' "$HD" > "$T/w_fn.cyr"
if CYRIUS_TARGET_WIN=1 "$T/x86" < "$T/w_top.cyr" > "$T/w_top.exe" 2> /dev/null \
   && CYRIUS_TARGET_WIN=1 "$T/x86" < "$T/w_fn.cyr" > "$T/w_fn.exe" 2> /dev/null; then
    nt=$(_walks "$T/w_top.exe"); nf=$(_walks "$T/w_fn.exe")
    if [ "$nt" != 3 ] || [ "$nf" != 0 ]; then
        _bad "PE micro-frame: $nt page walks for 3 top-level calls (want 3), $nf for the same calls in a fn (want 0)"
    else
        pass=$((pass + 1))
    fi
else
    _bad "PE micro-frame: the CYRIUS_TARGET_WIN=1 fixtures did not compile"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL $G: $fail row(s) red, $pass green"; exit 1; fi
if [ "$skips" -gt 0 ]; then
    echo "SKIP $G: $skips leg(s) above could not run; all $pass that ran passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS $G: $pass rows — fncallN and callptr at top level dispatch an escaped capturing closure (the filed repro exits 0 and closure_escape_dispatch.tcyr's top-level section passes on x86_64, aarch64/qemu, PE/wine and cx/cxvm; cx's plain top-level fncall1 is 42 and its three formerly-failing files pass; top-level callptr compiles; the PE micro-frame carries the page walk at top level only)"
exit 0
