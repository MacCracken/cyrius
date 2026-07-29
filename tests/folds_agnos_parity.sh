#!/bin/sh
# Gate: every folded stdlib that compiles for Linux must also compile for agnos.
#
# WHY THIS EXISTS. `lib/yukti.cyr` shipped for months with SIX agnos ABI errors —
# `sys_mount` called with 5 arguments against agnos's 0-parameter no-op stub (so yukti
# returned `Ok(mount_result_new(...))` for a mount that never happened), plus three
# length-carrying wrappers called with the bare-pointer POSIX shape. Nothing caught it
# because **no gate ever compiled a folded stdlib for a non-Linux target.** They were
# only ever built for the host. Found at v6.5.1 only because escalating an arity
# mismatch from warning to error made the six fatal instead of silent.
#
# WHY PARITY, not "must compile". The distlib bundles deliberately do NOT carry their
# stdlib dependencies — `cyrius.cyml` documents that the consumer supplies them via
# `[deps] stdlib`. So a bundle failing to build in isolation proves nothing about
# agnos; it usually just means this harness under-included. Comparing the SAME source
# against BOTH targets isolates the real class — target-specific ABI breakage — and is
# immune to include gaps: a dep that fails on both is a harness limitation, and a dep
# that builds on Linux but not agnos is the bug.
#
# COVERAGE IS PARTIAL AND SAID SO OUT LOUD. Deps that cannot be brought up on Linux
# with the preamble below are reported as SKIP with the symbol that stopped them, never
# silently dropped — a gate that hides what it did not check reads as "all clear" when
# it is not. Raising coverage means extending PREAMBLE until the SKIP list is empty.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

# Dependency-ordered. sigil before yantra, yukti before vani, tls before sandhi,
# sakshi before mabda — the bundles reference each other's constants.
PREAMBLE='include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/result.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/fnptr.cyr"
include "lib/tagged.cyr"
include "lib/mmap.cyr"
include "lib/net.cyr"
include "lib/ws.cyr"
include "lib/math.cyr"
include "lib/chrono.cyr"
include "lib/thread.cyr"
include "lib/thread_local.cyr"
include "lib/process.cyr"
include "lib/dynlib.cyr"
include "lib/fdlopen.cyr"
include "lib/tls.cyr"
include "lib/sakshi.cyr"
include "lib/sigil.cyr"
include "lib/yukti.cyr"'

DEPS="sigil patra sankoch sakshi bayan ganita mabda niyama yantra vani sandhi yukti"

checked=0
skipped=0
fails=0
skiplist=""

for d in $DEPS; do
    # Drop the dep's own line from the preamble so it is included exactly once, last.
    printf '%s\n' "$PREAMBLE" | grep -v "lib/$d\.cyr" > "$D/p.cyr"
    printf 'include "lib/%s.cyr"\nfn main(): i64 { return 0; }\n' "$d" >> "$D/p.cyr"

    cat "$D/p.cyr" | "$CC" > /dev/null 2>"$D/lin.err"; lrc=$?
    if [ "$lrc" != "0" ]; then
        sym=$(grep -m1 -oE "undefined (variable|function) '[A-Za-z_0-9]+'" "$D/lin.err" || true)
        skipped=$((skipped + 1))
        skiplist="$skiplist
    SKIP: $d — not buildable in this harness on Linux either (${sym:-see stderr}); extend PREAMBLE to cover it"
        continue
    fi

    cat "$D/p.cyr" | CYRIUS_TARGET_AGNOS=1 "$CC" > /dev/null 2>"$D/ag.err"; arc=$?
    checked=$((checked + 1))
    if [ "$arc" != "0" ]; then
        fails=$((fails + 1))
        # Attribute to the file the compiler names, NOT to the dep under test. Several
        # folds appear in the PREAMBLE, so a break in (say) lib/yukti.cyr otherwise gets
        # reported under sigil, patra, sankoch… — every dep that includes it. The header
        # says which probe tripped; the culprit is whatever file the error points at.
        culprit=$(grep -m1 -oE "^error:lib/[a-z_0-9]+\.cyr" "$D/ag.err" | sed 's/^error://' || true)
        if [ -n "$culprit" ] && [ "$culprit" != "lib/$d.cyr" ]; then
            echo "  FAIL: probe '$d' builds for Linux but NOT for agnos — break is in $culprit (a PREAMBLE dep, not $d itself):"
        else
            echo "  FAIL: $d builds for Linux but NOT for agnos — target-specific ABI break:"
        fi
        grep -E "^error" "$D/ag.err" | head -6 | sed 's/^/      /'
    fi
done

# Never silent about what was not covered.
if [ "$skipped" != "0" ]; then
    printf '%s\n' "  $skipped of 12 folds NOT checked (reported, not hidden):$skiplist"
fi

if [ "$fails" = "0" ]; then
    echo "PASS: folds-agnos-parity — $checked/12 folded stdlibs build for BOTH Linux and agnos ($skipped skipped)"
    exit 0
fi
echo "FAIL: folds-agnos-parity — $fails of $checked checked folds break on agnos"
exit 1
