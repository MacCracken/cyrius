#!/bin/sh
# raw_syscall_literals_routed.sh — every raw `syscall(<literal>, …)` in arch-neutral stdlib
# / CLI code is a number ESYSXLAT routes on ELF-aarch64.
#
# v6.6.4. The v6.5.51 raw-literal DIAGNOSTIC is structurally blind to the most dangerous
# class: an x86 number that is a valid-but-DIFFERENT aarch64 syscall (its table is derived
# from the aarch64 peer's declared names, and axis 5 of syscall_xlat_generated.sh pins that
# 63 = x86 uname / aarch64 read must stay SILENT). That is exactly how lib/hashseed.cyr's
# raw 201 (x86 time → aarch64 LISTEN on fd 0), lib/sigil.cyr's raw 63 (uname → read),
# lib/fdlopen.cyr / lib/dynlib.cyr's raw 5/6/158 (fstat/lstat/arch_prctl → setxattr /
# lsetxattr / getgroups) and cbt/build.cyr's raw 110 (getppid → timer_settime, which
# killed every `cyrius run/test` child on native aarch64 since 6.5.19) all shipped.
#
# The allowlist is DERIVED, not maintained: `cmp x8,#N` on aarch64 encodes N in bits 10-21
# of `0xF100001F | N<<10`, so every `EW(S, 0xF1……1F)` word in ESYSXLAT's ELF arm is a routed
# source number (the ≥1000 private-alias band included). A site is "arch-neutral" unless it
# sits inside a `#ifdef` of CYRIUS_ARCH_X86 / CYRIUS_ARCH_AARCH64 / CYRIUS_TARGET_AGNOS /
# CYRIUS_TARGET_MACOS / CYRIUS_TARGET_WIN (or the non-Linux side of a TARGET_LINUX guard) —
# a literal under CYRIUS_ARCH_AARCH64 is a NATIVE number by construction and is not judged
# here. Numbers ≥ 0xF000 (the PE reroute band) are exempt too.
#
# Anti-vacuous: the derived set must decode ≥ 40 rows, the scan must visit ≥ 500 files and
# find ≥ 200 literal sites, or the run fails rather than reporting "all routed" over nothing.
# MUTATION LEDGER:
#   * re-introduce `syscall(201, 0)` in lib/hashseed.cyr                    → 1 unrouted, exit 1
#   * restore `syscall(53, 1, 1, 0, &sv)` in result_allocator_via.tcyr      → 1 unrouted, exit 1
#   * restore `syscall(24, 0, 0, 0, 0)` in array_local_threadsafe.cyr       → 1 unrouted, exit 1
#   * drop the string masking                                              → 2 false positives
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
EMIT=src/backend/aarch64/emit.cyr
[ -f "$EMIT" ] || { echo "FAIL: raw_syscall_literals_routed: $EMIT missing"; exit 1; }

# ── the routed set, decoded from the emitter ────────────────────────────────────────
# Bounded to ESYSXLAT's own body and to Rn == x8 (bits 5-9 == 8): `cmp x8,#N` is
# 0xF100011F | N<<10. The first cut decoded every 0xF1 word in the file with Rn unchecked,
# which admitted ETESTAZ's `cmp x0,#0` and the fork/pipe `cmp x16,#N` words — an unrelated
# comparison elsewhere in the emitter would have silently admitted a number here.
ROUTED=$(awk '/^fn ESYSXLAT\(/{on=1} on && /^fn / && !/^fn ESYSXLAT\(/{on=0} on' "$EMIT" \
  | grep -o 'EW(S, 0xF1[0-9A-Fa-f]\{6\})' | sed 's/EW(S, //; s/)//' \
  | awk '{ w = strtonum($1); if (and(w, 0xFFC003FF) == 0xF100011F) print rshift(w - 0xF100011F, 10) }' \
  | sort -n | uniq | tr '\n' ' ')
nroutes=$(echo "$ROUTED" | wc -w)
[ "$nroutes" -ge 40 ] || { echo "FAIL: raw_syscall_literals_routed: decoded only $nroutes cmp-x8 rows from ESYSXLAT in $EMIT (want ≥ 40) — the decoder or the emitter shape moved"; exit 1; }
# a cmp word OUTSIDE ESYSXLAT must not be a row: ETESTAZ's `cmp x0,#0` sits at file scope
grep -q '^fn ETESTAZ(S): i64 { EW(S, 0xF100001F)' "$EMIT" \
  || { echo "FAIL: raw_syscall_literals_routed: the out-of-body control word (ETESTAZ cmp x0,#0) moved — re-derive the decoder's negative control"; exit 1; }
echo "  derived: $nroutes routed source numbers from ESYSXLAT's ELF-aarch64 arm"

# ── the scan ────────────────────────────────────────────────────────────────────────
# The five per-target PEER files and lib/*_win.cyr are excluded BY NAME: each one IS its
# target's definition and is only ever included for that target by lib/syscalls.cyr's
# dispatch, so its numbers are native by construction. lib/syscalls_linux_common.cyr is
# NOT a peer — it is compiled on both Linux arches — so it is scanned (the first cut's
# `syscalls_*` glob exempted it).
# v6.6.5 — SCOPE WIDENED from lib/+cbt/ to the whole source tree. The first cut stopped at
# the shipped stdlib, and tests/ was carrying four live instances of the exact class it
# exists for: result_allocator_via.tcyr's raw 53 (aarch64 fchmodat) took the test's own
# "skipped rather than failed" branch so its whole sock_send group SILENTLY DID NOT RUN on
# ARM; two concurrency fixtures spun on raw 24 (aarch64 dup3) instead of yielding; async_dns
# used raw 44 (aarch64 fstatfs); and fs/defer/toml/sakshi_full cleaned up with raw 87/84
# (timerfd_gettime / sync_file_range), i.e. did nothing. A gate scoped to the code least
# likely to be wrong is the cheap half of a check.
files=$(find lib cbt tests programs benches fuzz \
      \( -name '*.cyr' -o -name '*.tcyr' -o -name '*.bcyr' -o -name '*.fcyr' -o -name '*.scyr' -o -name '*.smcyr' \) \
  | grep -v -E '^lib/syscalls_(x86_64_linux|aarch64_linux|macos|windows|x86_64_agnos)\.cyr$|_win\.cyr$|^tests/win/' | sort)
nfiles=$(echo "$files" | wc -l)
[ "$nfiles" -ge 500 ] || { echo "FAIL: raw_syscall_literals_routed: scanned only $nfiles files (want ≥ 500)"; exit 1; }
report=$(awk -v routed="$ROUTED" '
BEGIN {
    n = split(routed, r, " "); for (i = 1; i <= n; i++) ok[r[i]] = 1
    sites = 0; bad = 0
}
# Directive spellings mirror src/frontend/lex_pp.cyr EXACTLY: ISIFDEF/ISIFNDEF/ISIF/ISIFPLAT
# want ONE space after the keyword, ISELSE/ISENDIF/ISENDPLAT want a non-identifier byte
# after it, and any other `#…` line is a COMMENT to the preprocessor — so `#ifdef\tX` or
# `#ifdef  X` guards nothing and the code under it is compiled on every target. The first
# cut accepted `[ \t]+` there and exempted what the compiler compiles.
# Per frame: exif = is the if-side exempt (never reaches aarch64-Linux, or is native there),
# exel = is the else-side exempt. `#if <expr>` is neutral (inherits). `#elif` = `#else`.
function side_table(sym, negated,   ifs, els) {
    ifs = 0; els = 0
    if (sym == "CYRIUS_ARCH_X86" || sym == "CYRIUS_TARGET_AGNOS" || sym == "CYRIUS_TARGET_MACOS" \
        || sym == "CYRIUS_TARGET_WIN" || sym == "CYRIUS_ARCH_RISCV" || sym == "CYRIUS_TARGET_RISCV") { ifs = 1; els = 0 }
    else if (sym == "CYRIUS_ARCH_AARCH64") { ifs = 1; els = 1 }   # if: native; else: never aarch64
    else if (sym == "CYRIUS_TARGET_LINUX") { ifs = 0; els = 1 }
    else { ifs = -1; els = -1 }                                   # unrelated symbol: inherit
    if (negated) { EXIF = els; EXEL = ifs } else { EXIF = ifs; EXEL = els }
}
function push(sym, negated) {
    depth++; side_table(sym, negated)
    inh = (depth > 1) ? ex[depth-1] : 0     # inside an exempt frame everything is exempt
    ex[depth] = inh ? 1 : ((EXIF < 0) ? 0 : EXIF); el[depth] = inh ? 1 : ((EXEL < 0) ? 0 : EXEL)
}
FNR == 1 { depth = 0 }
{
    line = $0; sub(/^[ \t]+/, "", line)
    if (substr(line, 1, 7) == "#ifdef ")  { sym = substr(line, 8); sub(/[^A-Za-z_0-9].*$/, "", sym); push(sym, 0); next }
    if (substr(line, 1, 8) == "#ifndef ") { sym = substr(line, 9); sub(/[^A-Za-z_0-9].*$/, "", sym); push(sym, 1); next }
    if (substr(line, 1, 8) == "#ifplat ") { sym = substr(line, 9); sub(/[^A-Za-z_0-9].*$/, "", sym); push("CYRIUS_ARCH_" toupper(sym), 0); next }
    if (substr(line, 1, 4) == "#if ")     { push("", 0); next }
    if (line ~ /^#else([^A-Za-z_0-9]|$)/ || line ~ /^#elif([^A-Za-z_0-9]|$)/) { if (depth > 0) ex[depth] = el[depth]; next }
    if (line ~ /^#endif([^A-Za-z_0-9]|$)/ || line ~ /^#endplat([^A-Za-z_0-9]|$)/) { if (depth > 0) depth--; next }
    if (line ~ /^#/) next                              # a comment line
    # Strip a trailing comment — only a `#` OUTSIDE a string literal opens one — and MASK
    # the contents of every string literal.
    # ⚠ v6.6.5: the masking is what makes the widened scope usable. Two in-tree files EMBED
    # cyrius source or a syscall number in a STRING. Measured with the masking removed, the
    # widened scope reports exactly two: programs/checks/main.cyr:307 (this gate description,
    # which quotes hashseed raw 201) and :392 (which quotes the 1700 __got reroute). Those are
    # data, not calls this build makes, and platform_win_macho.cyr writes a PE probe source
    # out the same way. A gate that cries wolf is how a real warning gets scrolled past
    # (v6.5.43), so the contents of a string literal are dropped and only the quotes kept.
    # NOTE: no apostrophes in this block — the whole awk program is a single-quoted shell
    # string, and one would end it. That is how the first cut of this edit broke.
    code = ""; inq = 0
    for (k = 1; k <= length(line); k++) {
        c = substr(line, k, 1)
        if (inq) { if (c == "\\") { k++; continue } if (c == "\"") { inq = 0; code = code c } continue }
        if (c == "\"") { inq = 1; code = code c; continue }
        if (c == "#") break
        code = code c
    }
    while (match(code, /syscall\([ \t]*(0x[0-9A-Fa-f]+|[0-9]+)/)) {
        num = substr(code, RSTART + 8, RLENGTH - 8); gsub(/[ \t]/, "", num)
        code = substr(code, RSTART + RLENGTH)
        v = (num ~ /^0x/) ? strtonum(num) : num + 0
        sites++
        if (depth > 0 && ex[depth]) continue
        if (v >= 61440) continue                       # 0xF000+: the PE reroute band
        if (!(v in ok)) { bad++; printf "    UNROUTED  %s:%d  syscall(%s, …) reaches aarch64-Linux unchanged\n", FILENAME, FNR, num }
    }
}
END { printf "SITES=%d BAD=%d\n", sites, bad }
' $files)
sites=$(echo "$report" | sed -n 's/^SITES=\([0-9]*\) BAD=.*/\1/p')
bad=$(echo "$report" | sed -n 's/^SITES=[0-9]* BAD=\([0-9]*\)/\1/p')
[ "${sites:-0}" -ge 200 ] || { echo "FAIL: raw_syscall_literals_routed: found only ${sites:-0} literal sites across $nfiles files (want ≥ 200) — the scan matched nothing"; exit 1; }
echo "$report" | grep -v '^SITES=' || true
if [ "${bad:-1}" -ne 0 ]; then
    echo "FAIL: raw_syscall_literals_routed: $bad arch-neutral raw syscall literal(s) are not routed on ELF-aarch64 ($sites sites scanned)."
    echo "      Spell the SYS_* name from the peer (both Linux peers declare it, ESYSXLAT renumbers), route the x86 number in ESYSXLAT, or guard the site with #ifdef CYRIUS_ARCH_X86."
    exit 1
fi
echo "PASS raw_syscall_literals_routed: $sites raw literal sites across $nfiles source files (lib cbt tests programs benches fuzz), all routed on ELF-aarch64 ($nroutes rows derived)"
