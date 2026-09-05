#!/bin/sh
# emitelf_obj_scratch_derived.sh — v6.5.50. `object;` output stays correct at ANY function
# count and ANY total name length, because EMITELF_OBJ SIZES ITS SCRATCH FROM THE UNIT.
#
# WHAT THIS PINS. EMITELF_OBJ (src/backend/x86/fixup.cyr) built four sub-regions — strtab,
# fn_strtab_off, symtab, rela — at HARDCODED offsets inside a FIXED 1 MB brk block, sized by
# a comment that says "for the v4.7.1 4096 fn cap". None was bounds-checked. Past the cap each
# region walked into its neighbour, and past the whole block it walked off the end:
#   * fnc >= 31,398  -> SIGSEGV, zero bytes out, EMPTY STDERR (symtab runs past the 1 MB block)
#   * fnc >=  5,528  -> rc=0 and a CORRUPT SYMBOL TABLE (fn_strtab_off runs into symtab)
#   * ~1,100 fns with long names -> rc=0 and a corrupt table (strtab runs into fn_strtab_off)
# The crash is loud and self-announcing. THE SILENT BAND IS THE DANGEROUS HALF, and it is what
# this gate is built around: a bad `.o` with a zero exit status is what ships.
#
# ⚠ THE FILED THRESHOLDS WERE BOTH WRONG AND MEASURING THEM IS WHY THIS GATE EXISTS.
# The issue recorded "~12,000 fns with LONG names" for the silent band and asserted "6,000 fns
# is clean". Bisected against a pre-fix compiler on 2026-09-04: ORDINARY SHORT NAMES corrupt at
# 5,528 (deterministic, 3/3), and 6,000 short-named fns produce 116 corrupt symbols. The band
# was ~2x more reachable than filed and needed no unusual naming at all. Do not trust a
# remembered threshold here; if you touch the sizing, re-bisect.
#
# ⚠ ACCEPTANCE IS A PROPERTY, NOT AN OFFSET. This deliberately does NOT grep for derived
# arithmetic or for the absence of 0x40000/0x48000/0x60000. A gate that pins the MECHANISM
# passes while the mechanism is wrong — the v6.5.36 enum gate stayed green through five bad
# releases doing exactly that. What is asserted is what a consumer can observe: every function
# appears in .symtab with an intact name. Any sizing scheme that achieves it is fine.
#
# ⚠ THE TWO AXES TRIP DIFFERENT REGIONS AND BOTH ARE REQUIRED. Axis 1 (many short names)
# overruns fn_strtab_off/symtab via COUNT; axis 2 (few long names) overruns strtab via TOTAL
# NAME BYTES. A fix to one region alone passes the other axis. Sizes are chosen just past each
# pre-fix threshold so the whole gate runs in about a second — the 31,398-fn crash repro is
# real but costs minutes, and the silent band it sits above is the stronger test anyway.
#
# ⚠ NO `set -e`: readelf/grep exit non-zero as DATA here (grep -c prints 0 and exits 1).
#
# MUTATION PROOF (2026-09-04): `git show <pre-fix>:src/backend/x86/fixup.cyr` rebuilt as the
# host compiler puts BOTH overrun axes RED while axis 3 stays green; restoring the derived
# sizing returns 0/0/green.
#
# ⚠ THE NUMBER OF CORRUPT SYMBOLS IS NOT STABLE — ONLY ITS PRESENCE IS. The overrun reads
# whatever the neighbouring region last held, and that is residual brk content, so repeated
# mutant runs on the SAME input gave 927 and then 1106 on axis 2. (The corruption THRESHOLD is
# stable — 5,528 reproduced 3/3 — it is the magnitude past it that wanders.) That is why every
# assertion here is `corrupt = 0` and never a count: a gate that pinned an expected number of
# corrupt symbols would itself be flaky, and would fail for reasons unrelated to the defect.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
CC="$ROOT/build/cycc"
FAIL=0

# Axis 1 — COUNT. 5,600 short-named fns: 72 past the measured pre-fix corruption threshold.
python3 -c "
n=5600
open('$D/count.cyr','w').write('object;\n'+'\n'.join('fn f%d(): i64 { return %d; }'%(i,i%97) for i in range(n))+'\nfn main(): i64 { return 42; }\n')
"
"$CC" < "$D/count.cyr" > "$D/count.o" 2>/dev/null
rc=$?
corrupt=$(readelf -sW "$D/count.o" 2>/dev/null | grep -c '<corrupt>')
funcs=$(readelf -sW "$D/count.o" 2>/dev/null | grep -c 'FUNC')
if [ "$rc" != 0 ] || [ "$corrupt" != 0 ] || [ "$funcs" != 5602 ]; then
    echo "FAIL: 5,600-fn object unit — rc=$rc corrupt=$corrupt FUNC=$funcs (want rc=0 corrupt=0 FUNC=5602)"
    FAIL=1
else
    echo "  ok: 5,600 short-named fns -> 5602 symbols, none corrupt"
fi

# Axis 2 — NAME BYTES. 1,400 fns x ~245-char names = ~343 KB of strtab, past the old 256 KB.
python3 -c "
n=1400; pad='z'*240
open('$D/names.cyr','w').write('object;\n'+'\n'.join('fn f%s%d(): i64 { return %d; }'%(pad,i,i%97) for i in range(n))+'\nfn main(): i64 { return 42; }\n')
"
"$CC" < "$D/names.cyr" > "$D/names.o" 2>/dev/null
rc=$?
corrupt=$(readelf -sW "$D/names.o" 2>/dev/null | grep -c '<corrupt>')
funcs=$(readelf -sW "$D/names.o" 2>/dev/null | grep -c 'FUNC')
# the LAST function's full name must survive intact, not merely be non-"<corrupt>"
lastname=$(readelf -sW "$D/names.o" 2>/dev/null | grep -c "fz\{240\}1399")
if [ "$rc" != 0 ] || [ "$corrupt" != 0 ] || [ "$funcs" != 1402 ] || [ "$lastname" != 1 ]; then
    echo "FAIL: 1,400 long-named fns — rc=$rc corrupt=$corrupt FUNC=$funcs lastname=$lastname (want 0/0/1402/1)"
    FAIL=1
else
    echo "  ok: 1,400 fns x 245-char names -> 1402 symbols, none corrupt, last name intact"
fi

# Axis 3 — REGRESSION. A small unit must still be a well-formed relocatable object.
python3 -c "
open('$D/small.cyr','w').write('object;\n'+'\n'.join('fn f%d(): i64 { return %d; }'%(i,i) for i in range(200))+'\nfn main(): i64 { return 42; }\n')
"
"$CC" < "$D/small.cyr" > "$D/small.o" 2>/dev/null
rc=$?
kind=$(readelf -hW "$D/small.o" 2>/dev/null | grep -c 'REL (Relocatable file)')
corrupt=$(readelf -sW "$D/small.o" 2>/dev/null | grep -c '<corrupt>')
if [ "$rc" != 0 ] || [ "$kind" != 1 ] || [ "$corrupt" != 0 ]; then
    echo "FAIL: 200-fn object unit regressed — rc=$rc REL=$kind corrupt=$corrupt (want 0/1/0)"
    FAIL=1
else
    echo "  ok: 200-fn unit is a well-formed REL object"
fi

if [ "$FAIL" != 0 ]; then
    echo "FAIL: EMITELF_OBJ scratch is not sized from the unit"
    exit 1
fi
echo "PASS emitelf_obj_scratch_derived (object output correct past every pre-fix overrun threshold)"
