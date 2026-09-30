#!/bin/sh
# v6.5.25 — a PE binary must contain ZERO raw Linux `syscall` instructions, and
# the folded stdlib must BUILD for Windows.
#
# THE BUG. An unrouted LITERAL syscall number under `CYRIUS_TARGET_WIN=1` warned and then
# fell through to `ESCPOPS`, emitting a raw `syscall` instruction. On Windows that is
# STATUS_ILLEGAL_INSTRUCTION (0xC000001D) — a hard crash at the first call, from a warning
# buried in a 1233-byte wall of text. The NON-literal arm has emitted an honest -38/-ENOSYS
# since v6.1.17 for precisely this reason, so the two halves of one decision disagreed for
# four minors. Fixed by routing the literal arm through the same `_pe_dyn_nomatch` tail.
#
# ⭐ WHY THIS UNBLOCKED THE STDLIB ON WINDOWS. `lib/syscalls_windows.cyr` is a STANDALONE
# peer (it includes nothing), and it had no `SYS_IOCTL` constant — so `lib/yukti.cyr`'s
# CD-ROM eject path made `undefined variable 'SYS_IOCTL'` a HARD COMPILE ERROR for a PE
# build of yukti, and of anything including it. Measured before: rc=1, 4 error lines.
# The constant could not be added on its own: doing that alone converts the compile error
# into 39 raw `syscall` instructions, i.e. a runtime crash instead of a build failure — strictly
# worse. Constant + honest-degrade had to land together, and this gate pins BOTH halves.
#
# ⚠ SCOPE, HONESTLY. `SYS_IOCTL` was NOT "the sole symbol blocking every fold", as the
# premise-check claimed. With it fixed, yukti / vani / patra build for PE; `mabda` and
# `sigil` still fail on SEPARATE, unrelated gaps (`PROT_READ`/`PROT_WRITE`/`MAP_SHARED`
# absent from the Windows peer, plus undefined fns). Those are tracked separately — this
# gate deliberately asserts only what is actually true today, so it cannot pass while
# claiming more than was fixed.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
cd "$ROOT"
command -v objdump >/dev/null 2>&1 || { echo "SKIP: objdump not available (a raw byte scan is NOT an acceptable substitute — see raw_syscalls)"; exit 77; }
T=$(mktemp --suffix=.cyr) && [ -f "$T" ] || { echo "FAIL: pe_no_raw_syscall_bytes: mktemp --suffix=.cyr failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
B=$(mktemp) && [ -f "$B" ] || { echo "FAIL: pe_no_raw_syscall_bytes: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: pe_no_raw_syscall_bytes: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -f "$T" "$B" "$E"' EXIT
fail=0

# Count real `syscall` INSTRUCTIONS by disassembling.
#
# ⛔ DO NOT byte-scan for `0F 05`. The first version of this gate did, and it reported a
# FALSE POSITIVE on `lib/patra.cyr`: the pair it found sat inside `e9 0f 05 00 00`, i.e. a
# `jmp rel32` whose displacement happens to be 0x050f. objdump reads PE fine here
# (`file format pei-x86-64`) and reported 0 syscall mnemonics for the same binary, so the
# disassembler is the oracle and a raw scan cannot distinguish code from a displacement,
# an immediate, or string data. This is also why the premise-check's "baseline floor of 2
# byte-sequences" figure should not be treated as real syscalls.
raw_syscalls() {
    objdump -d "$1" 2>/dev/null | grep -cE '[[:space:]]syscall([[:space:]]|$)' || true
}

# --- axis 1: an explicitly unrouted literal syscall must NOT emit 0F 05 on PE ---
# 16 is ioctl: real, named by the roadmap, and deliberately never routed on Windows.
printf 'include "lib/syscalls.cyr"\nfn main(): i64 { return syscall(16, 1, 2, 0); }\nvar ec = main();\nsyscall(60, ec);\n' > "$T"
CYRIUS_TARGET_WIN=1 "$CC" < "$T" > "$B" 2>"$E" || true
if [ ! -s "$B" ]; then
    echo "  FAIL axis 1: PE build of an unrouted literal syscall produced no binary"
    grep -m2 "^error" "$E" | sed 's/^/      /'
    fail=1
else
    n=$(raw_syscalls "$B")
    if [ "$n" != "0" ]; then
        echo "  FAIL axis 1: PE binary contains $n raw syscall instruction(s) - each is STATUS_ILLEGAL_INSTRUCTION on Windows"
        fail=1
    else
        echo "  ok axis 1: unrouted literal emits no raw syscall instruction on PE (honest -38/-ENOSYS instead)"
    fi
fi

# --- axis 2 (ANTI-VACUOUS): the same source on LINUX must still emit a real syscall ---
# Without this, deleting syscall emission entirely would pass axis 1.
"$CC" < "$T" > "$B" 2>"$E" || true
if [ ! -s "$B" ]; then
    echo "  FAIL axis 2 (anti-vacuous): the Linux build of the same probe produced no binary"
    fail=1
else
    n=$(raw_syscalls "$B")
    if [ "$n" -lt 1 ]; then
        echo "  FAIL axis 2 (anti-vacuous): Linux binary disassembles to NO syscall instruction — emission is broken, so axis 1 proves nothing"
        fail=1
    else
        echo "  ok axis 2: the Linux build of the same source still emits real syscall instructions ($n sites)"
    fi
fi

# --- axis 3: the SYS_IOCTL constant must exist on the Windows peer ---
# Its absence was a hard compile error for the folded stdlib.
if grep -qE '^[[:space:]]*SYS_IOCTL[[:space:]]*=' lib/syscalls_windows.cyr; then
    echo "  ok axis 3: lib/syscalls_windows.cyr defines SYS_IOCTL"
else
    echo "  FAIL axis 3: lib/syscalls_windows.cyr has no SYS_IOCTL — a PE build of any consumer that names it (vani's and mabda's agnos ioctl arms spell sys_ioctl; out-of-tree code may still spell SYS_IOCTL) is a hard compile error again"
    fail=1
fi

# --- axis 4: the folds that CAN build for PE must keep building, with no raw 0F 05 ---
# yukti is the fold SYS_IOCTL once blocked (it spells private `_YK_*` names since 2.3.13,
# CHANGELOG [6.6.7]); vani follows yukti because vani's audio API calls yukti's, the order
# `cyrius distlib` emits (vani reaches ioctl through its OWN `_audio_ioctl`, not yukti);
# patra is an unrelated control.
#
# ⚠ v6.5.30 — `patra` now leads the yukti specs. yukti 2.3.8 references `PATRA_OK`, and it has
# declared `[deps.patra]` in its manifest all along, so a consumer resolving through
# `cyrius deps` was never affected — but these hand-listed include sets were, and a build
# failure here reads as "yukti broke on Windows" when the truth is "this list is stale".
# Second instance in two releases (bayan 1.4.2 needing `lib/str.cyr` at .29): when a fold
# names a new type or constant, EVERY hand-written include list in the tree is a caller.
for spec in "patra yukti" "patra yukti vani" "patra"; do
    {
        printf 'include "lib/syscalls.cyr"\n'
        for m in $spec; do printf 'include "lib/%s.cyr"\n' "$m"; done
        printf 'fn main(): i64 { return 0; }\nvar ec = main();\nsyscall(60, ec);\n'
    } > "$T"
    CYRIUS_TARGET_WIN=1 "$CC" < "$T" > "$B" 2>"$E" || true
    label=$(echo "$spec" | tr ' ' '+')
    if [ ! -s "$B" ]; then
        echo "  FAIL axis 4 [$label]: does not build for PE"
        grep -m2 "^error" "$E" | sed 's/^/      /'
        fail=1
    else
        n=$(raw_syscalls "$B")
        if [ "$n" != "0" ]; then
            echo "  FAIL axis 4 [$label]: PE binary carries $n raw syscall instruction(s)"
            fail=1
        else
            echo "  ok axis 4 [$label]: builds for PE with 0 raw syscall instructions"
        fi
    fi
done

# --- axis 6: sandhi (and yantra over it) must build for PE WITHOUT yukti in scope ---
# 6.6.7: sandhi's IPv6 open paths spelled `syscall(SYS_SOCKET, ...)` / `SYS_CONNECT`, names
# the Windows peer has never defined. PE builds of sandhi only compiled because yukti
# <= 2.3.12 declared both as top-level globals, and every hand-written preamble here and in
# folds_agnos_parity puts yukti ahead of sandhi. yukti 2.3.13 stopped declaring them and
# sandhi broke on PE (4 `undefined variable` errors) with every gate green. So this axis
# builds sandhi against the stdlib leaves plus its OWN fold deps (sakshi, sigil, bayan)
# and nothing else: a fold that borrows another fold's constant fails here.
# CHANGELOG [6.6.7].
SANDHI_PRE="syscalls string alloc result str fmt vec hashmap io fs fnptr tagged mmap net ws math chrono random thread thread_local process dynlib fdlopen tls sakshi sigil bayan"
for spec in "sandhi" "sandhi async yantra"; do
    {
        for m in $SANDHI_PRE $spec; do printf 'include "lib/%s.cyr"\n' "$m"; done
        printf 'fn main(): i64 { return 0; }\nvar ec = main();\nsyscall(60, ec);\n'
    } > "$T"
    if grep -q 'lib/yukti.cyr' "$T"; then
        echo "  FAIL axis 6: the preamble includes yukti — the axis would be vacuous"; fail=1; continue
    fi
    CYRIUS_TARGET_WIN=1 "$CC" < "$T" > "$B" 2>"$E" || true
    label=$(echo "$spec" | tr ' ' '+')
    if [ ! -s "$B" ]; then
        echo "  FAIL axis 6 [$label]: does not build for PE without yukti in scope"
        grep -m4 "^error" "$E" | sed 's/^/      /'
        fail=1
    else
        n=$(raw_syscalls "$B")
        if [ "$n" != "0" ]; then
            echo "  FAIL axis 6 [$label]: PE binary carries $n raw syscall instruction(s)"
            fail=1
        else
            echo "  ok axis 6 [$label]: builds for PE with no other fold in scope, 0 raw syscall instructions"
        fi
    fi
done

# --- axis 5: the three new Windows raw-floor wrappers must exist ---
# Each was a band-D (.25) item whose 0xF0xx reroute was already live; only the wrapper
# was missing, which made the name a hard compile error for PE.
for fn in sys_getpid sys_access sys_socketpair; do
    if grep -qE "^fn $fn\(" lib/syscalls_windows.cyr; then
        echo "  ok axis 5: lib/syscalls_windows.cyr defines $fn"
    else
        echo "  FAIL axis 5: lib/syscalls_windows.cyr has no $fn — the name is a hard compile error on PE"
        fail=1
    fi
done

[ "$fail" -eq 0 ] || { echo "FAIL: pe-no-raw-syscall-bytes"; exit 1; }
echo "PASS: pe-no-raw-syscall-bytes — unrouted literals degrade to -ENOSYS, no 0F 05 reaches a PE binary, the folds SYS_IOCTL blocked build, and sandhi/yantra build with no borrowed fold constants"
