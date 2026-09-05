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
# With both, in-tree false positives went 525 -> 0 while 43 genuinely-broken numbers still
# warn. THE ZERO IS THE ACCEPTANCE — a noisy syscall warning is worse than none here, which
# this repo already learned when the Mach-O routing warning fired 470 times and got scrolled
# past (v6.5.43).
#
# ⚠ NO `set -e`: compiles exit non-zero as DATA.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
FAIL=0

# ── axis 1: the table is REGENERATABLE and matches what is committed ──────────────
# A hand-edited or stale table is the self-drifting shape this repo keeps finding; the only
# way to keep it honest is to re-derive and diff.
./build/cyrius build programs/gen_syscall_xlat.cyr "$D/gen" > /dev/null 2>&1
if [ ! -x "$D/gen" ]; then
    echo "FAIL: axis 1: the generator does not build"
    FAIL=1
else
    cp src/common/syscall_xlat.cyr "$D/committed.cyr"
    "$D/gen" > /dev/null 2>&1
    if ! cmp -s "$D/committed.cyr" src/common/syscall_xlat.cyr; then
        echo "FAIL: axis 1: src/common/syscall_xlat.cyr is STALE — regenerating it changes it."
        echo "      The stdlib syscall tables or ESYSXLAT moved; re-run the generator and commit."
        cp "$D/committed.cyr" src/common/syscall_xlat.cyr
        FAIL=1
    else
        echo "  ok: the committed table re-derives byte-identically from the stdlib peers"
    fi
fi

# ── axis 2: ZERO false positives on the compiler's own aarch64 source ─────────────
./build/cycc < src/main_aarch64.cyr > "$D/cc_a64" 2>/dev/null
chmod +x "$D/cc_a64"
if [ ! -s "$D/cc_a64" ]; then
    echo "FAIL: axis 2: could not build the aarch64 emitter"
    FAIL=1
else
    "$D/cc_a64" < src/main_aarch64.cyr > /dev/null 2>"$D/self.err"
    fp=$(grep -c 'raw syscall' "$D/self.err")
    if [ "$fp" != 0 ]; then
        echo "FAIL: axis 2: $fp raw-syscall warnings on cycc's OWN aarch64 source — these are"
        echo "      correct x86-compat numbers that ESYSXLAT remaps; the exclusion has regressed."
        grep -m2 'raw syscall' "$D/self.err" | sed 's/^/        /'
        FAIL=1
    else
        echo "  ok: 0 false positives on cycc's own aarch64 source (was 510 before the exclusions)"
    fi

    # ── axis 3: it STILL CATCHES a genuinely wrong number ─────────────────────────
    # 5 is x86_64 fstat and is not an aarch64 syscall at all.
    printf 'fn main(): i64 { return syscall(5, 0); }\nvar r = main();\n' > "$D/bad.cyr"
    "$D/cc_a64" < "$D/bad.cyr" > /dev/null 2>"$D/bad.err"
    if [ "$(grep -c 'raw syscall 5 is x86_64 `fstat`' "$D/bad.err")" != 1 ]; then
        echo "FAIL: axis 3: a raw x86_64 fstat(5) on ELF-aarch64 produced no diagnostic"
        FAIL=1
    else
        echo "  ok: raw x86_64 fstat(5) on ELF-aarch64 is diagnosed by name"
    fi

    # ── axis 4: an ESYSXLAT-REMAPPED number must stay SILENT ──────────────────────
    # 1 is x86_64 write and the chain rewrites it to 64. Warning here is the 510-warning bug.
    printf 'fn main(): i64 { return syscall(1, 1, "x", 1); }\nvar r = main();\n' > "$D/ok.cyr"
    "$D/cc_a64" < "$D/ok.cyr" > /dev/null 2>"$D/ok.err"
    if [ "$(grep -c 'raw syscall' "$D/ok.err")" != 0 ]; then
        echo "FAIL: axis 4: raw syscall 1 (write) warned, but ESYSXLAT remaps it — supported usage"
        FAIL=1
    else
        echo "  ok: an ESYSXLAT-remapped number (write=1) stays silent"
    fi

    # ── axis 5: an AMBIGUOUS number must stay SILENT ──────────────────────────────
    # 63 is x86_64 uname AND aarch64 read; a literal cannot be judged wrong.
    printf 'fn main(): i64 { return syscall(63, 0, 0, 0); }\nvar r = main();\n' > "$D/amb.cyr"
    "$D/cc_a64" < "$D/amb.cyr" > /dev/null 2>"$D/amb.err"
    if [ "$(grep -c 'raw syscall' "$D/amb.err")" != 0 ]; then
        echo "FAIL: axis 5: raw syscall 63 warned, but it is a VALID aarch64 read — ambiguous,"
        echo "      so warning fires on correct low-level code."
        FAIL=1
    else
        echo "  ok: an ambiguous number (63 = x86 uname / aarch64 read) stays silent"
    fi
fi

# ── axis 6: the x86 fork must be UNAFFECTED (it carries return-0 stubs) ───────────
printf 'fn main(): i64 { return syscall(5, 0); }\nvar r = main();\n' > "$D/x.cyr"
./build/cycc < "$D/x.cyr" > /dev/null 2>"$D/x.err"
if [ "$(grep -c 'raw syscall' "$D/x.err")" != 0 ]; then
    echo "FAIL: axis 6: the x86_64 fork emitted an ELF-aarch64 diagnostic — the stub leaked"
    FAIL=1
else
    echo "  ok: the x86_64 fork is silent (return-0 stubs, table not linked in)"
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: syscall_xlat_generated"; exit 1; fi
echo "PASS syscall_xlat_generated (table re-derives; 0 false positives; catches real ones)"
