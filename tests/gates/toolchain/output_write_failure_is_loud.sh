#!/bin/sh
# output_write_failure_is_loud.sh — v6.6.6 bite 15a.
#
# CYCC USED TO EXIT 0 AFTER A FAILED WRITE OF ITS OWN OUTPUT. Six of the seven
# driver forks ended with the same hand-rolled loop:
#
#     while (wgo == 1) {
#         var w = syscall(SYS_WRITE, 1, _output_base + written, olen - written);
#         if (w <= 0) { wgo = 0; }          # stops — but records no error
#         else { written = written + w; if (written >= olen) { wgo = 0; } }
#     }
#
# `written < olen` was never tested, so a full disk — or a quota, or RLIMIT_FSIZE
# — produced a TRUNCATED executable reported as a successful build. Measured at
# 6.6.5 on a 64 KB tmpfs: `cyrius build` printed `OK (65536 bytes)` for a
# 71272-byte image, exit 0, and renamed the stub over the previous artifact.
# Every CI step that trusts `$?` shipped it. The cx fork ignored the return value
# of all six of its writes; `_ej_flush` (--emit-js) said "partial-write safe" in
# its own comment and returned success on a failed write.
#
# Fixed by _write_out_all / _write_out_failed in src/common/util.cyr: every write
# of the compiler's own output goes through one loop that compares what landed
# against what was asked for, prints
# `error: could not write the output (N of M bytes): errno E` on stderr and exits 1.
#
# ⭐ THE ORACLE IS NEVER THE COMPILER'S OWN CLAIM. M is taken from an
# UNCONSTRAINED compile of the same source and `wc -c` of its output; N is taken
# from `wc -c` of the truncated file. Both come from the filesystem, not from the
# message the gate is checking — the message has to agree with two numbers it did
# not produce.
#
# ⚠ THE FAILURE IS INJECTED WITH RLIMIT_FSIZE, not a mount: `ulimit -f` needs no
# privilege and no namespace, and with SIGXFSZ ignored the writer sees exactly the
# full-disk sequence (a short count, then EFBIG). The filing's `unshare -rm` +
# 64 KB tmpfs repro was run by hand at the fix and is recorded in the CHANGELOG;
# it is not in the gate because `unshare -r` is unavailable on hosts with user
# namespaces disabled and would make this gate skip silently on them.
#
# Axes:
#   1  the filed shape: cycc's exit status is NON-ZERO after a short write
#   2  the diagnostic names the short write, and its two numbers equal the sizes
#      the filesystem reports (N = truncated bytes, M = full image bytes)
#   3  anti-vacuous: the truncated output really is shorter than the full image
#      (if the limit never bit, axis 1 would be meaningless)
#   4  control: the same compile with no limit exits 0 and writes all M bytes
#   5  `cyrius build` reports FAIL, exits non-zero, prints no `OK (` line and
#      leaves NO artifact at the output path
#   6  `cycc --emit-js` — the second output path, whose flush had the same defect
#   7  census, derived from the source: no raw fd-1 write remains in src/ outside
#      the helper, and every one of the 7 driver forks reaches _write_out_all
#
# MUTATION LEDGER (2026-09-19, cycc 1,315,040 B, measured). Each mutation is
# applied to a scratch tree built with `git archive HEAD src bootstrap lib` plus
# the edited file, a compiler built from it with the good cycc, and the gate run
# against that compiler (CYRIUS_CC / CYRIUS_CBT); the scratch tree is deleted after:
#   M1 `if (written < len) { _write_out_failed(...); }` deleted from _write_out_all
#      (i.e. the pre-6.6.6 behaviour restored for every fork at once)
#      → 4 FAIL / 3 ok: axes 1, 2, 5, 6. Axes 3, 4 and 7 stay green — 3 and 4 are
#      the anti-vacuous pair and 7 reads the source, which the mutation leaves
#      spelled the same way.
#   M2 the comparison inverted to `if (written > len)` (a plausible typo)
#      → same 4 FAIL / 3 ok.
#   M3 `_write_out_failed` keeps the diagnostic but exits 0 instead of 1
#      → 3 FAIL / 4 ok: axes 1, 5, 6. ⚠ AXIS 2 STAYS GREEN, which is why the exit
#      status and the message are SEPARATE axes: a gate that only grepped stderr
#      would score a compiler that still exits 0 as fixed, and exit 0 is the
#      entire filed defect.
#   M4 `_ej_flush` returned to its own loop (`if (n <= 0) { return 0; }`)
#      → 1 FAIL / 6 ok: axis 6 only. The ELF path is unaffected, which is why the
#      JS path is not folded into axis 1.
#   real tree → 7/7 green
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYRIUS_CC:-"$ROOT/build/cycc"}
CBT=${CYRIUS_CBT:-"$ROOT/build/cyrius"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ulimit -c 0 2>/dev/null || true

# A program whose image is comfortably larger than the limit the gate sets, so
# the write is PARTIAL rather than refused outright — the full-disk shape.
printf 'var A = 7;\nvar B = A + 1;\nsyscall(60, B);\n' > "$D/p.cyr"

# ── the two oracles, both read off the filesystem.
"$CC" < "$D/p.cyr" > "$D/full.bin" 2> "$D/full.err" || {
    printf 'FAIL: harness — the unconstrained compile failed: %s\n' \
        "$(head -1 "$D/full.err" | cut -c1-90)"
    exit 1
}
M=$(wc -c < "$D/full.bin" | tr -d ' ')
[ "$M" -gt 2048 ] || { printf 'FAIL: harness — probe image is %s B, too small to truncate at 2048\n' "$M"; exit 1; }

# ── axes 1-3 — the short write itself. stderr is captured through a PIPE
#    (command substitution), which RLIMIT_FSIZE does not apply to, so the
#    diagnostic survives the very condition it reports on.
rc=0
msg=$( ( trap '' XFSZ; ulimit -f 4; "$CC" < "$D/p.cyr" > "$D/short.bin" ) 2>&1 ) || rc=$?
N=$(wc -c < "$D/short.bin" | tr -d ' ')

if [ "$rc" -ne 0 ]; then
    printf '  ok: axis 1 — cycc exits %s after a short write (was 0)\n' "$rc"
    pass=$((pass+1))
else
    printf '  FAIL: axis 1 — cycc exited 0 after writing %s of %s bytes\n' "$N" "$M"
    fail=$((fail+1))
fi

want="error: could not write the output ($N of $M bytes)"
if printf '%s' "$msg" | grep -qF "$want"; then
    printf '  ok: axis 2 — the diagnostic names the short write: %s\n' "$want"
    pass=$((pass+1))
else
    printf '  FAIL: axis 2 — stderr does not carry "%s"; got: %s\n' \
        "$want" "$(printf '%s' "$msg" | grep -i 'could not write' | head -1 | cut -c1-90)"
    fail=$((fail+1))
fi

if [ "$N" -lt "$M" ] && [ "$N" -gt 0 ]; then
    printf '  ok: axis 3 — the limit really truncated the image (%s of %s bytes landed)\n' "$N" "$M"
    pass=$((pass+1))
else
    printf '  FAIL: axis 3 — RLIMIT_FSIZE did not produce a PARTIAL write (%s of %s)\n' "$N" "$M"
    fail=$((fail+1))
fi

# ── axis 4 — control. Same compiler, same source, no limit.
rc=0
( "$CC" < "$D/p.cyr" > "$D/ok.bin" ) 2>/dev/null || rc=$?
OKN=$(wc -c < "$D/ok.bin" | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$OKN" = "$M" ]; then
    printf '  ok: axis 4 — unconstrained, cycc exits 0 and writes all %s bytes\n' "$M"
    pass=$((pass+1))
else
    printf '  FAIL: axis 4 — unconstrained compile: rc=%s, %s of %s bytes\n' "$rc" "$OKN" "$M"
    fail=$((fail+1))
fi

# ── axis 5 — `cyrius build`, the consumer that printed `OK (65536 bytes)`.
#    Run from a scratch dir with the compiler under test beside the wrapper, so
#    cbt resolves THIS cycc (inside the source repo it would always pick
#    ./build/cycc and a mutation would not reach it).
if [ -x "$CBT" ]; then
    mkdir -p "$D/bin" "$D/w"
    cp "$CC" "$D/bin/cycc"
    cp "$CBT" "$D/bin/cyrius"
    cp "$D/p.cyr" "$D/w/p.cyr"
    rc=0
    out=$( ( cd "$D/w" && trap '' XFSZ && ulimit -f 4 && "$D/bin/cyrius" build p.cyr art ) 2>&1 ) || rc=$?
    if [ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -q 'OK (' && [ ! -e "$D/w/art" ]; then
        printf '  ok: axis 5 — `cyrius build` exits %s, prints no OK line, leaves no artifact\n' "$rc"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 5 — rc=%s artifact=%s line=%s\n' "$rc" \
            "$( [ -e "$D/w/art" ] && wc -c < "$D/w/art" | tr -d ' ' || echo none )" \
            "$(printf '%s' "$out" | grep -o 'OK ([0-9]* bytes)' | head -1)"
        fail=$((fail+1))
    fi
else
    printf '  FAIL: axis 5 — %s is not executable (build the CLI: `cat cbt/cyrius.cyr | ./build/cycc`)\n' "$CBT"
    fail=$((fail+1))
fi

# ── axis 6 — the SECOND output path. `_ej_flush` had the same defect with its
#    own loop, so it needs its own axis: M4 in the ledger moves only this one.
printf 'const x: number = 1;\nconsole.log(x);\nconsole.log("%s");\n' \
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$D/p.ts"
"$CC" --emit-js < "$D/p.ts" > "$D/full.js" 2>/dev/null || true
JM=$(wc -c < "$D/full.js" | tr -d ' ')
rc=0
jmsg=$( ( trap '' XFSZ; ulimit -f 0; "$CC" --emit-js < "$D/p.ts" > "$D/short.js" ) 2>&1 ) || rc=$?
JN=$(wc -c < "$D/short.js" | tr -d ' ')
if [ "$JM" -gt 0 ] && [ "$rc" -ne 0 ] && [ "$JN" -lt "$JM" ] && printf '%s' "$jmsg" | grep -q 'could not write the output'; then
    printf '  ok: axis 6 — --emit-js exits %s after writing %s of %s bytes\n' "$rc" "$JN" "$JM"
    pass=$((pass+1))
else
    printf '  FAIL: axis 6 — --emit-js: rc=%s, %s of %s bytes, msg=%s\n' "$rc" "$JN" "$JM" \
        "$(printf '%s' "$jmsg" | head -1 | cut -c1-70)"
    fail=$((fail+1))
fi

# ── axis 7 — census, derived from the source two different ways. A NEW fork, or
#    a new output path added with its own loop, turns this RED instead of being
#    silently uncovered. The helper's own definition is the one permitted fd-1
#    write; nothing else in src/ may call write(1) directly.
raw=$(grep -rn 'syscall(SYS_WRITE, 1,' src/ | grep -cv '^src/common/util.cyr:' || true)
forks=$(ls src/main.cyr src/main_aarch64.cyr src/main_aarch64_macho.cyr \
           src/main_aarch64_native.cyr src/main_win.cyr src/main_x86_macho.cyr \
           src/main_cx.cyr 2>/dev/null | wc -l | tr -d ' ')
wired=$(grep -l '_write_out_all(' src/main.cyr src/main_aarch64.cyr src/main_aarch64_macho.cyr \
           src/main_aarch64_native.cyr src/main_win.cyr src/main_x86_macho.cyr \
           src/main_cx.cyr 2>/dev/null | wc -l | tr -d ' ')
if [ "$raw" -eq 0 ] && [ "$forks" -eq 7 ] && [ "$wired" -eq "$forks" ]; then
    printf '  ok: axis 7 — census: 0 raw fd-1 writes outside the helper, %s/%s forks wired\n' "$wired" "$forks"
    pass=$((pass+1))
else
    printf '  FAIL: axis 7 — census: %s raw fd-1 write(s) outside the helper, %s of %s forks wired\n' \
        "$raw" "$wired" "$forks"
    fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: output-write-failure-is-loud — %s of %s axes failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: output-write-failure-is-loud — %s/%s axes green\n' "$pass" "$pass"
