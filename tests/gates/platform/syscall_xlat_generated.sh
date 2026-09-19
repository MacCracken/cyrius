#!/bin/sh
# syscall_xlat_generated.sh — v6.5.51. The x86_64<->aarch64 syscall correspondence is
# DERIVED from the stdlib peers, and the ELF-aarch64 raw-literal diagnostic uses it without
# firing on correct code.
#
# WHAT THIS PINS. On ELF-aarch64 a raw hardcoded syscall NUMBER is indistinguishable from an
# intended native one, so a consumer writing the x86_64 number gets a DIFFERENT, VALID
# syscall with a successful build and no diagnostic (filed from darshana).
#
# ⛔ THE OBVIOUS TABLE-FREE CHECK IS UNSOUND AND THE DATA SAYS SO. "warn if the number is not
# a valid SYS_* value here" catches 61 of the 71 differing syscalls and misses the 10 that
# matter most, because those x86 numbers ARE real aarch64 syscalls: uname 63 = read,
# kill 62 = lseek, execve 59 = pipe2, wait4 61 = getdents64, clone 56 = openat.
#
# ⛔ AND THE OBVIOUS TABLE IS ALSO WRONG — the FIRST cut of this diagnostic warned 510 times
# on cycc's own aarch64 source and 15 times on a stdlib hello-world, all of it CORRECT CODE.
# Two exclusions were needed, and both are derived rather than assumed:
#   1. ESYSXLAT's ELF-aarch64 arm already REMAPS 42 x86 numbers, and writing those is the
#      SUPPORTED convention — cycc's own `enum Sys` uses them (main_aarch64.cyr:
#      SYS_WRITE = 1) precisely because the chain rewrites them. ⚠ That arm is written as
#      literal `EW(S, 0x...)` instruction words, NOT `_esx_arm(...)` call rows, so a grep for
#      call rows finds ZERO and silently under-excludes; the generator DECODES
#      `cmp x8,#imm` (0xF1000000 | imm<<10 | 8<<5 | 0x1F) instead.
#   2. The 10 ambiguous numbers above, where a literal is plausibly correct.
# With both, in-tree false positives went 525 -> 0 while the genuinely-broken numbers still
# warn. ⚠ v6.6.5: this line used to quote that second count ("43 genuinely-broken numbers").
# It is DERIVED — the table shrinks every time a call gains a name in both peers and grows
# when one arrives on only one — so it went stale the moment the release it was written for
# shipped. Derive it instead: `grep -c '_SYSX_MEANT' src/common/syscall_xlat.cyr`, or read
# the count the generator prints. CHANGELOG [6.6.5]
# THE ZERO IS THE ACCEPTANCE — a noisy syscall warning is worse than none here, which
# this repo already learned when the Mach-O routing warning fired 470 times and got scrolled
# past (v6.5.43).
#
# ⚠ NO `set -e`: compiles exit non-zero as DATA.
#
# ⛔ v6.6.6 — THIS GATE NEVER WRITES THE TREE. Axis 1 used to copy the committed table to
# mktemp, regenerate it IN PLACE, and copy the backup back on a diff. When /tmp was full
# (measured at the 6.6.5 close) the backup landed EMPTY, the regenerated table "differed"
# from it, and the gate restored the empty file over src/common/syscall_xlat.cyr mid-check.sh
# — and reported the table STALE, a false diagnosis on top of the damage. The generator now
# takes an OUT path and writes crash-safe; axis 1 regenerates under $D and diffs, so a broken
# temp dir can fail this gate but can no longer touch the tracked file.
# tests/gates/toolchain/gates_never_write_tree.sh pins it — the write shapes statically across
# every gate, and this gate by running it under four TMPDIR faults and with a generator that
# cannot write (which must read "could not write", never STALE). CHANGELOG [6.6.6]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: syscall_xlat_generated: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
# _ran <axis> <what> <rc> <bin> <probe-src>
# ⛔ v6.6.6: an axis that proves a property by the ABSENCE of a diagnostic needs a positive
# proof the compiler RAN. Five axes (2, 3b, 4, 5, 6) grepped stderr for `raw syscall` and said
# `ok` on zero matches without looking at the exit status or the probe: under RLIMIT_FSIZE the
# aarch64 emitter segfaulted on every probe and all five printed `ok`, and on a full TMPDIR axis
# 6 printed `ok` over an EMPTY probe. Returns 0 only when the probe is non-empty, the compile
# exited 0 and wrote a non-empty binary; otherwise FAILs naming which. CHANGELOG [6.6.6]
# Mutation (6.6.6): `ulimit -f 600` (the aarch64 emitter segfaults) -> axes 2/3b/4/5 FAIL "did not
# run to completion (rc=139)" where 6.6.5 printed four `ok`s; TMPDIR on a 1 MiB tmpfs
# (`unshare -rm` + mount) -> 3b/4/5/6 FAIL "is empty", axis 2 rc=139. Normal run: same `ok` lines.
_ran() {
    if [ ! -s "$5" ]; then echo "FAIL: $1: could not write $2 ($5 is empty) — its silence proves nothing"; FAIL=1; return 1; fi
    if [ "$3" -ne 0 ]; then echo "FAIL: $1: the compiler did not run to completion on $2 (rc=$3) — its silence proves nothing"; FAIL=1; return 1; fi
    if [ ! -s "$4" ]; then echo "FAIL: $1: $2 compiled to an EMPTY binary — its silence proves nothing"; FAIL=1; return 1; fi
    return 0
}

# ── axis 1: the table is REGENERATABLE and matches what is committed ──────────────
# A hand-edited or stale table is the self-drifting shape this repo keeps finding; the only
# way to keep it honest is to re-derive and diff. The regenerated copy goes to $D/regen.cyr;
# a generator that cannot write it exits non-zero, which is a gate FAILURE, not "stale".
./build/cyrius build programs/gen_syscall_xlat.cyr "$D/gen" > /dev/null 2>&1
if [ ! -x "$D/gen" ]; then
    echo "FAIL: axis 1: the generator does not build"
    FAIL=1
elif ! "$D/gen" "$D/regen.cyr" > "$D/gen.out" 2>&1 || [ ! -s "$D/regen.cyr" ]; then
    echo "FAIL: axis 1: the generator could not write its output under $D:"
    sed 's/^/      /' "$D/gen.out" 2>/dev/null | head -3
    FAIL=1
elif ! cmp -s "$D/regen.cyr" src/common/syscall_xlat.cyr; then
    echo "FAIL: axis 1: src/common/syscall_xlat.cyr is STALE — regenerating it changes it."
    echo "      The stdlib syscall tables or ESYSXLAT moved; regenerate and commit:"
    echo "      cyrius build programs/gen_syscall_xlat.cyr build/gen_syscall_xlat && ./build/gen_syscall_xlat"
    FAIL=1
else
    echo "  ok: the committed table re-derives byte-identically from the stdlib peers (regenerated under \$D, tree untouched)"
fi

# ── axis 2: ZERO false positives on the compiler's own aarch64 source ─────────────
./build/cycc < src/main_aarch64.cyr > "$D/cc_a64" 2>/dev/null
chmod +x "$D/cc_a64"
if [ ! -s "$D/cc_a64" ]; then
    echo "FAIL: axis 2: could not build the aarch64 emitter"
    FAIL=1
else
    rc2=0; "$D/cc_a64" < src/main_aarch64.cyr > "$D/self.bin" 2>"$D/self.err" || rc2=$?
    fp=$(grep -c 'raw syscall' "$D/self.err")
    if ! _ran "axis 2" "cycc's own aarch64 source" "$rc2" "$D/self.bin" src/main_aarch64.cyr; then
        :
    elif [ "$fp" != 0 ]; then
        echo "FAIL: axis 2: $fp raw-syscall warnings on cycc's OWN aarch64 source — these are"
        echo "      correct x86-compat numbers that ESYSXLAT remaps; the exclusion has regressed."
        grep -m2 'raw syscall' "$D/self.err" | sed 's/^/        /'
        FAIL=1
    else
        echo "  ok: 0 false positives on cycc's own aarch64 source (was 510 before the exclusions)"
    fi

    # ── axis 3: it STILL CATCHES a genuinely wrong number ─────────────────────────
    # v6.6.4: 5 (fstat) is ROUTED now (5→80), so it must NOT warn; 91 (x86 fchmod) is the
    # probe — it is aarch64 capset (kavach's filed fchmod→capset), unrouted, and not a name
    # the aarch64 peer declares. ⚠ This axis used to say 5 "is not an aarch64 syscall at
    # all"; it is setxattr. The diagnostic's own text carried the same error.
    printf 'fn main(): i64 { return syscall(91, 0, 0); }\nvar r = main();\n' > "$D/bad.cyr"
    "$D/cc_a64" < "$D/bad.cyr" > /dev/null 2>"$D/bad.err"
    if [ "$(grep -c 'raw syscall 91 is x86_64 `fchmod`' "$D/bad.err")" != 1 ]; then
        echo "FAIL: axis 3: a raw x86_64 fchmod(91) on ELF-aarch64 produced no diagnostic"
        FAIL=1
    elif grep -q 'not a syscall at all' "$D/bad.err"; then
        echo "FAIL: axis 3: the diagnostic still claims the number is 'not a syscall at all' (91 IS capset there)"
        FAIL=1
    else
        echo "  ok: raw x86_64 fchmod(91) on ELF-aarch64 is diagnosed by name, without the false 'not a syscall' claim"
    fi
    printf 'fn main(): i64 { return syscall(5, 0, 0); }\nvar r = main();\n' > "$D/fst.cyr"
    rc3=0; "$D/cc_a64" < "$D/fst.cyr" > "$D/fst.bin" 2>"$D/fst.err" || rc3=$?
    if ! _ran "axis 3b" "the fstat(5) probe" "$rc3" "$D/fst.bin" "$D/fst.cyr"; then
        :
    elif [ "$(grep -c 'raw syscall' "$D/fst.err")" != 0 ]; then
        echo "FAIL: axis 3b: raw fstat(5) warned, but ESYSXLAT routes it (5→80) since v6.6.4"
        FAIL=1
    else
        echo "  ok: raw fstat(5) is routed now and stays silent"
    fi

    # ── axis 4: an ESYSXLAT-REMAPPED number must stay SILENT ──────────────────────
    # 1 is x86_64 write and the chain rewrites it to 64. Warning here is the 510-warning bug.
    printf 'fn main(): i64 { return syscall(1, 1, "x", 1); }\nvar r = main();\n' > "$D/ok.cyr"
    rc4=0; "$D/cc_a64" < "$D/ok.cyr" > "$D/ok.bin" 2>"$D/ok.err" || rc4=$?
    if ! _ran "axis 4" "the write(1) probe" "$rc4" "$D/ok.bin" "$D/ok.cyr"; then
        :
    elif [ "$(grep -c 'raw syscall' "$D/ok.err")" != 0 ]; then
        echo "FAIL: axis 4: raw syscall 1 (write) warned, but ESYSXLAT remaps it — supported usage"
        FAIL=1
    else
        echo "  ok: an ESYSXLAT-remapped number (write=1) stays silent"
    fi

    # ── axis 5: an AMBIGUOUS number must stay SILENT ──────────────────────────────
    # 63 is x86_64 uname AND aarch64 read; a literal cannot be judged wrong.
    printf 'fn main(): i64 { return syscall(63, 0, 0, 0); }\nvar r = main();\n' > "$D/amb.cyr"
    rc5=0; "$D/cc_a64" < "$D/amb.cyr" > "$D/amb.bin" 2>"$D/amb.err" || rc5=$?
    if ! _ran "axis 5" "the ambiguous-63 probe" "$rc5" "$D/amb.bin" "$D/amb.cyr"; then
        :
    elif [ "$(grep -c 'raw syscall' "$D/amb.err")" != 0 ]; then
        echo "FAIL: axis 5: raw syscall 63 warned, but it is a VALID aarch64 read — ambiguous,"
        echo "      so warning fires on correct low-level code."
        FAIL=1
    else
        echo "  ok: an ambiguous number (63 = x86 uname / aarch64 read) stays silent"
    fi
fi

# ── axis 7/8: ZERO raw-syscall warnings on an aarch64 build of a stdlib hello and of the
#    CLI — the wolf-cry the gate says must be zero. v6.6.4: lib/io.cyr's native flock(32)
#    under `#ifdef CYRIUS_ARCH_AARCH64` was flagged "raw syscall 32 is x86_64 dup" on EVERY
#    aarch64 build that includes io.cyr, and cbt/build.cyr's raw 110 (getppid → aarch64
#    timer_settime, which killed every `cyrius run/test` child on native aarch64 since 6.5.19)
#    had printed its warning since the diagnostic landed at 6.5.51 (27 releases), scrolled
#    past. ⚠ Anti-vacuous: a compile that
#    FAILS emits 0 warnings too, so each axis also requires rc 0 and a non-empty output.
if [ -x "$D/cc_a64" ]; then
    printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/io.cyr"\nfn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$D/hello.cyr"
    rc7=0; "$D/cc_a64" < "$D/hello.cyr" > "$D/hello.bin" 2>"$D/hello.err" || rc7=$?
    if [ "$rc7" -ne 0 ] || [ ! -s "$D/hello.bin" ]; then
        echo "FAIL: axis 7: the stdlib hello did not build for aarch64 (rc=$rc7)"; FAIL=1
    elif [ "$(grep -c 'raw syscall' "$D/hello.err")" != 0 ]; then
        echo "FAIL: axis 7: a stdlib hello (syscalls+alloc+io) warns on aarch64 — a false positive on correct lib code:"
        grep 'raw syscall' "$D/hello.err" | head -3 | sed 's/^/      /'; FAIL=1
    else
        echo "  ok: a stdlib hello builds for aarch64 with 0 raw-syscall warnings (io.cyr's flock is SYS_FLOCK now)"
    fi
    rc8=0; "$D/cc_a64" < cbt/cyrius.cyr > "$D/cli.bin" 2>"$D/cli.err" || rc8=$?
    if [ "$rc8" -ne 0 ] || [ ! -s "$D/cli.bin" ]; then
        echo "FAIL: axis 8: cbt/cyrius.cyr did not build for aarch64 (rc=$rc8)"; FAIL=1
    elif [ "$(grep -c 'raw syscall' "$D/cli.err")" != 0 ]; then
        echo "FAIL: axis 8: the CLI warns on aarch64 — a raw x86 number reached cbt/ again:"
        grep 'raw syscall' "$D/cli.err" | head -3 | sed 's/^/      /'; FAIL=1
    else
        echo "  ok: the CLI builds for aarch64 with 0 raw-syscall warnings (cbt/build.cyr's 110 is SYS_GETPPID now)"
    fi
fi

# ── axis 9: EVERY routed source number compiles SILENT on the aarch64 fork ────────
# v6.6.5. Axis 4 pins ONE remapped number (write=1). The set is 58 now and fourteen of them
# landed in a single release, so pin the PROPERTY: if ESYSXLAT routes it, writing it raw is
# the supported convention and must not warn. The set is DERIVED from the emitter, and the
# expectation that each one is a real x86_64 syscall comes from the committed KERNEL table
# (tests/data/syscalls/x86_64.tbl) — a different source from the generated table under test,
# which is derived from the peers.
#
# ⛔ v6.6.5 — THE GUARD BELOW MUST NOT BE THE ONLY THING STANDING BETWEEN THESE AXES AND
# SILENCE. As first written it was `if [ -x cc_a64 ] && [ -f ...x86_64.tbl ]` with no else:
# moving tests/data/syscalls/ aside made the gate print the IDENTICAL PASS line with both
# axes simply gone — a check that disappears when its input does, which is the vacuous-green
# shape this whole release is about. The missing-table case is now a hard FAIL (the sibling
# syscall_peer_kernel_agreement.sh already does this); the missing-compiler case is covered
# by axis 2, which fails first and loudly. CHANGELOG [6.6.5]
if [ ! -f tests/data/syscalls/x86_64.tbl ]; then
    echo "FAIL: axes 9+10: tests/data/syscalls/x86_64.tbl is missing — it is the COMMITTED"
    echo "      kernel-fact source both axes cross-check against (see its header for the"
    echo "      derivation command). Without it these axes are not skipped, they are absent."
    FAIL=1
fi
if [ -x "$D/cc_a64" ] && [ -f tests/data/syscalls/x86_64.tbl ]; then
    ROUTED=$(awk '
    /^fn ESYSXLAT\(/ { on = 1 }
    on && /^fn / && !/^fn ESYSXLAT\(/ { on = 0 }
    on && /_TARGET_MACHO == 2/ { m = 1 }
    on && m && /^        return 0;/ { m = 0; next }
    on && !m {
        line = $0
        while (match(line, /EW\(S, 0xF1[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]\)/)) {
            w = strtonum("0x" substr(line, RSTART + 8, 8)); line = substr(line, RSTART + RLENGTH)
            if (and(w, 0xFFC003FF) == 0xF100011F) { v = rshift(w - 0xF100011F, 10); if (v < 1000) print v }
        }
    }' src/backend/aarch64/emit.cyr | sort -n -u)
    nr=$(echo "$ROUTED" | wc -w)
    # every routed source must be a real x86_64 syscall number — otherwise the row is
    # routing something that cannot be written deliberately, and this axis is vacuous.
    unknown=0
    for n in $ROUTED; do
        awk -v n="$n" '$1 == n { f = 1 } END { exit !f }' tests/data/syscalls/x86_64.tbl || unknown=$((unknown + 1))
    done
    : > "$D/allrouted.cyr"
    echo 'fn main(): i64 {' >> "$D/allrouted.cyr"
    for n in $ROUTED; do echo "    syscall($n, 0, 0, 0);" >> "$D/allrouted.cyr"; done
    echo '    return 0;' >> "$D/allrouted.cyr"
    echo '}' >> "$D/allrouted.cyr"
    echo 'var r = main();' >> "$D/allrouted.cyr"
    rc9=0; "$D/cc_a64" < "$D/allrouted.cyr" > "$D/allrouted.bin" 2>"$D/allrouted.err" || rc9=$?
    if [ "$nr" -lt 50 ]; then
        echo "FAIL: axis 9: only $nr routed source numbers decoded (floor 50) — the decoder moved"; FAIL=1
    elif [ "$rc9" -ne 0 ] || [ ! -s "$D/allrouted.bin" ]; then
        echo "FAIL: axis 9: the routed-number probe did not build for aarch64 (rc=$rc9)"; FAIL=1
    elif [ "$unknown" -ne 0 ]; then
        echo "FAIL: axis 9: $unknown routed source number(s) are not x86_64 syscalls per tests/data/syscalls/x86_64.tbl"; FAIL=1
    elif [ "$(grep -c 'raw syscall' "$D/allrouted.err")" != 0 ]; then
        echo "FAIL: axis 9: a number ESYSXLAT ROUTES still warns — writing it raw is the supported convention:"
        grep 'raw syscall' "$D/allrouted.err" | head -5 | sed 's/^/      /'; FAIL=1
    else
        echo "  ok: all $nr routed source numbers compile silent on the aarch64 fork (derived from the emitter)"
    fi

    # ── axis 10: a newly-NAMED number that is NOT routed gains a diagnostic ───────────
    # v6.6.5 named SYS_INOTIFY_INIT1 = 294 on the x86 peer (it was a raw literal; the aarch64
    # peer had always declared 26). aarch64 294 is kexec_file_load, the number is unrouted and
    # not an aarch64 declaration, so it is exactly the case the table exists for. The expected
    # NAME comes from the kernel table, not from src/common/syscall_xlat.cyr.
    #
    # MUTATION LEDGER (measured 6.6.5, corrected). ⚠ The first ledger for this axis said
    # "remove SYS_INOTIFY_INIT1 from the x86 peer -> axis 10 FAIL". IT DOES NOT: the peer's
    # own three inotify wrappers now spell that name, so deleting the declaration stops the
    # GENERATOR compiling and only axis 1 reddens ("the generator does not build") while
    # axis 10 still prints ok. Re-measured — the mutation that actually reaches axis 10 is
    # deleting the `if (n == 294) { return "inotify_init1"; }` row from the generated
    # src/common/syscall_xlat.cyr: axis 10 FAILs with "raw 294 is not diagnosed", and axis 1
    # FAILs too because the table is generated and any hand-edit of it IS staleness. Same
    # result from renaming the row's string. There is no mutation that reaches axis 10 and
    # leaves axis 1 green, and a ledger entry that claims otherwise is the check-shares-a-
    # defect shape one level up. CHANGELOG [6.6.5]
    want294=$(awk '$1 == 294 { print $2 }' tests/data/syscalls/x86_64.tbl)
    printf 'fn main(): i64 { return syscall(294, 0); }\nvar r = main();\n' > "$D/ino.cyr"
    "$D/cc_a64" < "$D/ino.cyr" > /dev/null 2>"$D/ino.err"
    if [ -z "$want294" ]; then
        echo "FAIL: axis 10: tests/data/syscalls/x86_64.tbl has no entry for 294"; FAIL=1
    elif [ "$(grep -c "raw syscall 294 is x86_64 \`$want294\`" "$D/ino.err")" != 1 ]; then
        echo "FAIL: axis 10: raw 294 is not diagnosed as x86_64 \`$want294\` (aarch64 294 is kexec_file_load)"
        grep -m2 'raw syscall' "$D/ino.err" | sed 's/^/      /'; FAIL=1
    else
        echo "  ok: raw 294 is diagnosed as x86_64 \`$want294\` (the v6.6.5 peer-asymmetry fix)"
    fi
fi

# ── axis 6: the x86 fork must be UNAFFECTED (it carries return-0 stubs) ───────────
printf 'fn main(): i64 { return syscall(5, 0); }\nvar r = main();\n' > "$D/x.cyr"
rc6=0; ./build/cycc < "$D/x.cyr" > "$D/x.bin" 2>"$D/x.err" || rc6=$?
if ! _ran "axis 6" "the x86_64 fork's probe" "$rc6" "$D/x.bin" "$D/x.cyr"; then
    :
elif [ "$(grep -c 'raw syscall' "$D/x.err")" != 0 ]; then
    echo "FAIL: axis 6: the x86_64 fork emitted an ELF-aarch64 diagnostic — the stub leaked"
    FAIL=1
else
    echo "  ok: the x86_64 fork is silent (return-0 stubs, table not linked in)"
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: syscall_xlat_generated"; exit 1; fi
echo "PASS syscall_xlat_generated (table re-derives; 0 false positives; catches real ones)"
