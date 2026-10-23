#!/bin/sh
# macos_declines_answer_darwin_enosys.sh — 6.7.16 (D76). Every stdlib decline a macOS build can
# reach answers -78, ENOSYS in Darwin's numbering — never -38, which is Linux's ENOSYS and, on
# Darwin, ENOTSOCK.
#
# ⛔ WHY IT EXISTS. On macOS the stdlib's "no route here" answer came in two numberings: 48 declines
# answered -78 (as the Mach-O syscall path answers a real BSD failure: the negated Darwin errno),
# while sys_prctl and sys_gettid answered -38 — and sys_sched_kicks, which has no macOS arm, fell
# into its `#ifndef CYRIUS_TARGET_AGNOS` arm and answered -38 too. A macOS caller testing the
# host's ENOSYS (`== 0 - 78`, sigil's ENOSYS on macOS) misread all three; one testing `== 0 - 38`
# read Darwin's ENOTSOCK as "not implemented". cxvm's Darwin errno map (6.7.16 P2) needs every
# macOS stdlib answer Darwin-numbered. Nothing looked at the numbering, so it drifted by hand.
#
# THE CENSUS. A walk of lib/**.cyr, once per Mac (x86-macOS reaches CYRIUS_ARCH_X86 and not
# _AARCH64, arm64-macOS the reverse; both reach CYRIUS_TARGET_MACOS and neither _LINUX / _WIN /
# _AGNOS / _CX), tracking the #ifdef / #ifndef / #else frames and the fn bodies:
#   * a `return 0 - 38;` (or `return -38;`) the Mac compiles and can REACH fails. Reachable means
#     no open frame is skipped on that Mac, and no earlier `return` at the fn body's own level,
#     under frames that Mac surely compiles, ended the fn — so sys_utimensat's default arm (cx's
#     -38, after a macOS arm that returns -78) is dead on macOS and passes, while
#     sys_sched_kicks' `#ifndef CYRIUS_TARGET_AGNOS` arm with no macOS arm ahead of it fails.
#   * a file is skipped when it is FOREIGN to the Mac: a per-target peer that lib/ includes only
#     under a frame the Mac skips (syscalls_windows.cyr, *_agnos.cyr, syscalls_x86_64_linux.cyr,
#     the other Mac's syscall peer). Derived from the include sites, never a hand list; a
#     back-include (a peer pulling in its parent for self-sufficiency) does not make the parent
#     foreign.
#   * A comparison (`r != 0 - 38`, Darwin's ENOTSOCK in _fd_write_nosigpipe / _tn_nosigpipe) is
#     not a decline and is not read.
#
# Anti-vacuous: before the tree is believed, the same scanner runs over a CONTROL lib/ written
# here, whose verdict per Mac is known (a macOS arm's -38, an #ifndef-AGNOS arm, an #else of a
# Linux arm, a default arm after a conditional macOS return, an arch-only arm, a foreign peer, a
# back-included parent, a comparison, a brace inside a string — each flagged or passed as stated
# below). Then floors on the tree: >= 90 files walked, >= 10 foreign, >= 15 `return 0 - 38;` seen
# in total, and >= 48 reached -78 answers per Mac.
#
# MACOS_DECLINES_ROOT=<dir> scans <dir>/lib instead of the tree's (the lib/ mutants below run on a
# scratch copy that way, so the tree is never edited); MACOS_DECLINES_MUTANT=nodone|noforeign
# disables one scanner rule (mutants 6 and 7) — it exists to prove the controls see that rule.
#
# MUTATION LEDGER (each applied to a scratch copy, run with MACOS_DECLINES_ROOT, RED, discarded):
#   1. sys_prctl's macOS arm back to `return 0 - 38;`              -> RED: syscalls_linux_common.cyr, both Macs
#   2. sys_gettid's macOS arm back to `return 0 - 38;`             -> RED: sys.cyr, both Macs
#   3. sys_sched_kicks' macOS arm deleted                          -> RED: its #ifndef-AGNOS -38, both Macs
#   4. sys_utimensat's macOS arm deleted                           -> RED: its default arm's -38, both Macs
#   5. the aarch64 peer's sys_epoll_wait macOS decline to -38      -> RED: arm64-macOS only
#   6. the scanner's fn-ended rule disabled (MUTANT=nodone)         -> RED: controls C3 and C10 flagged
#   7. the scanner's foreign derivation disabled (MUTANT=noforeign) -> RED: control C8 flagged, 4 files walked
#   8. the pre-fix lib/ (0ba98b3bf, git archive)                    -> RED: sys.cyr:434 (sched_kicks), :527
#      (gettid), syscalls_linux_common.cyr:392 (prctl), on both Macs; 48 reachable -78 declines
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCAN_ROOT=${MACOS_DECLINES_ROOT:-$ROOT}
G=macos_declines_answer_darwin_enosys
TMP=$(mktemp -d) && [ -d "$TMP" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT INT TERM
[ -d "$SCAN_ROOT/lib" ] || { echo "FAIL: $G: $SCAN_ROOT/lib is missing"; exit 1; }
NODONE=0; NOFOREIGN=0
case "${MACOS_DECLINES_MUTANT:-}" in
    nodone) NODONE=1 ;; noforeign) NOFOREIGN=1 ;; "") ;;
    *) echo "FAIL: $G: unknown MACOS_DECLINES_MUTANT '${MACOS_DECLINES_MUTANT}'"; exit 1 ;;
esac

cat > "$TMP/scan.awk" <<'AWK'
# Usage: awk -v T=<x86|arm> -f scan.awk PASS=1 <files> PASS=2 <files>   (paths "lib/…", cwd = root)
# PASS 1 records every `include "lib/…"` site and whether target T compiles it; between the passes
# a file is FOREIGN to T when some counted site includes it under a frame T skips (a target
# dispatch) and every other counted site is skipped too or sits in a foreign file. A BACK-include
# (G including F when F includes G) is not counted. PASS 2 walks the rest and prints
#   VIOL <file>:<line>     a `return 0 - 38;` (or `return -38;`) T compiles and can reach
#   R78 <file>:<line>      a `return 0 - 78;` T compiles and can reach
#   R38ALL <n>             every `return 0 - 38;` in the walked files, reached or not
#   FILES <n> FOREIGN <n>  files walked / files judged foreign
#   UNBAL <file> <depth>   a walked file whose braces do not balance (its fn walk cannot be trusted)
# Directive spellings mirror src/frontend/lex/pp/directive.cyr (one space after #ifdef / #ifndef / #ifplat /
# #if; a non-identifier byte after #else / #elif / #endif / #endplat; any other # line is a
# comment), as darwin_syscall_literals_routed.sh's scanner does.
function reach(sym, negated,   ifs, els) {
    # 1 = that side is compiled on T, 0 = it is not, -1 = a symbol T does not fix (either way)
    if (sym == "CYRIUS_TARGET_MACOS") { ifs = 1; els = 0 }
    else if (sym == "CYRIUS_TARGET_LINUX" || sym == "CYRIUS_TARGET_WIN" || sym == "CYRIUS_TARGET_AGNOS" \
          || sym == "CYRIUS_TARGET_CX" || sym == "CYRIUS_ARCH_RISCV" || sym == "CYRIUS_TARGET_RISCV") { ifs = 0; els = 1 }
    else if (sym == "CYRIUS_ARCH_X86") { if (T == "x86") { ifs = 1; els = 0 } else { ifs = 0; els = 1 } }
    else if (sym == "CYRIUS_ARCH_AARCH64") { if (T == "arm") { ifs = 1; els = 0 } else { ifs = 0; els = 1 } }
    else { ifs = -1; els = -1 }
    if (negated) { RIF = els; REL = ifs } else { RIF = ifs; REL = els }
}
function push(sym, negated) { depth++; reach(sym, negated); cur[depth] = RIF; alt[depth] = REL }
# on_: no open frame is skipped on T.  def_(from): every frame above `from` is surely compiled on T.
function on_(   k) { for (k = 1; k <= depth; k++) if (cur[k] == 0) return 0; return 1 }
function def_(from,   k) { for (k = from + 1; k <= depth; k++) if (cur[k] != 1) return 0; return 1 }
# The code of a line, its strings' bodies and its comment removed; a string open at the end of a
# line stays open into the next (INQ), as the lexer reads a multi-line literal.
function mask(line,   code, k, c) {
    code = ""
    for (k = 1; k <= length(line); k++) {
        c = substr(line, k, 1)
        if (INQ) { if (c == "\\") { k++; continue } if (c == "\"") { INQ = 0; code = code c } continue }
        if (c == "\"") { INQ = 1; code = code c; continue }
        if (c == "#") break
        code = code c
    }
    return code
}
function compute_foreign(   changed, f, n, m, ok, back) {
    for (n = 1; n <= NINC; n++) {
        back = 0
        for (m = 1; m <= NINC; m++) if (inc_from[m] == inc_to[n] && inc_to[m] == inc_from[n]) { back = 1; break }
        if (back) { BACK[inc_from[n], inc_to[n]] = 1; continue }
        NSITES[inc_to[n]] = 1
        if (!inc_on[n]) SKIPPED[inc_to[n]] = 1
    }
    changed = 1
    while (changed) {
        changed = 0
        for (f in NSITES) {
            if ((f in FOREIGN) || !(f in SKIPPED)) continue
            ok = 1
            for (n = 1; n <= NINC; n++)
                if (inc_to[n] == f && inc_on[n] && !(inc_from[n] in FOREIGN) && !((inc_from[n], f) in BACK)) { ok = 0; break }
            if (ok) { FOREIGN[f] = 1; changed = 1 }
        }
    }
}
FNR == 1 {
    if (PASS == 2 && !COMPUTED) { if (NOFOREIGN != 1) compute_foreign(); COMPUTED = 1 }
    if (PASS == 2 && LASTF != "" && BR != 0) printf "UNBAL %s %d\n", LASTF, BR
    depth = 0; INQ = 0; BR = 0; infn = 0; done = 0; LASTF = ""
    if (PASS == 2) { if (FILENAME in FOREIGN) NFOR++; else { NFILES++; LASTF = FILENAME } }
}
PASS == 2 && (FILENAME in FOREIGN) { next }
{
    line = $0; sub(/^[ \t]+/, "", line)
    if (!INQ) {
        if (substr(line, 1, 7) == "#ifdef ")  { s = substr(line, 8); sub(/[^A-Za-z_0-9].*$/, "", s); push(s, 0); next }
        if (substr(line, 1, 8) == "#ifndef ") { s = substr(line, 9); sub(/[^A-Za-z_0-9].*$/, "", s); push(s, 1); next }
        if (substr(line, 1, 8) == "#ifplat ") { s = substr(line, 9); sub(/[^A-Za-z_0-9].*$/, "", s); push("CYRIUS_ARCH_" toupper(s), 0); next }
        if (substr(line, 1, 4) == "#if ")     { push("", 0); next }
        if (line ~ /^#else([^A-Za-z_0-9]|$)/ || line ~ /^#elif([^A-Za-z_0-9]|$)/) { if (depth > 0) cur[depth] = alt[depth]; next }
        if (line ~ /^#endif([^A-Za-z_0-9]|$)/ || line ~ /^#endplat([^A-Za-z_0-9]|$)/) { if (depth > 0) depth--; next }
        if (line ~ /^#/) next
    }
    code = mask(line)
    if (PASS == 1) {
        if (code ~ /^include[ \t]+""/ && line ~ /^include[ \t]+"lib\//) {
            p = line; sub(/^include[ \t]+"/, "", p); sub(/".*$/, "", p)
            NINC++; inc_from[NINC] = FILENAME; inc_to[NINC] = p; inc_on[NINC] = on_()
        }
        next
    }
    d0 = BR
    t = code; nopen = gsub(/\{/, "", t); t = code; nclose = gsub(/\}/, "", t); BR = BR + nopen - nclose
    if (d0 == 0 && code ~ /^fn[ \t]/) { infn = 1; fnd = depth; done = 0 }
    is38 = (code ~ /return[ \t]+0[ \t]*-[ \t]*38[ \t]*;/ || code ~ /return[ \t]*-[ \t]*38[ \t]*;/)
    if (is38) R38ALL++
    if (!on_() || done) next
    if (is38) printf "VIOL %s:%d\n", FILENAME, FNR
    if (code ~ /return[ \t]+0[ \t]*-[ \t]*78[ \t]*;/) printf "R78 %s:%d\n", FILENAME, FNR
    # A `return` at the fn body's own level, under frames all surely compiled on T, ends the fn on
    # T: the default arm after a macOS arm that returns is dead there.
    if (NODONE != 1 && infn && d0 == 1 && code ~ /^return([ \t;(]|$)/ && def_(fnd)) done = 1
}
END {
    if (LASTF != "" && BR != 0) printf "UNBAL %s %d\n", LASTF, BR
    printf "R38ALL %d\nFILES %d FOREIGN %d\n", R38ALL, NFILES + 0, NFOR + 0
}
AWK

# scan <root> <x86|arm> <out>: the census of <root>/lib for one Mac
scan() {
    ( cd "$1" && files=$(find lib -name '*.cyr' | LC_ALL=C sort) && [ -n "$files" ] \
        && awk -v T="$2" -v NODONE="$NODONE" -v NOFOREIGN="$NOFOREIGN" \
            -f "$TMP/scan.awk" PASS=1 $files PASS=2 $files ) > "$3"
}
fail=0
bad() { echo "FAIL: $G: $*"; fail=1; }

# ── controls: a lib/ whose verdict per Mac is known ──────────────────────────────────────────
C="$TMP/ctl"; mkdir -p "$C/lib"
cat > "$C/lib/ctl.cyr" <<'EOF'
#ifdef CYRIUS_TARGET_WIN
include "lib/ctl_win.cyr"
#endif
include "lib/ctl_kid.cyr"
# C1: a macOS arm answering -38 — flagged on both Macs
fn c1(): i64 {
    #ifdef CYRIUS_TARGET_MACOS
    return 0 - 38;
    #endif
    return 0;
}
# C2: a Linux arm's -38 — never compiled on a Mac
fn c2(): i64 {
    #ifdef CYRIUS_TARGET_LINUX
    return 0 - 38;
    #endif
    return 0;
}
# C3: the default arm after a macOS arm that returns — dead on a Mac
fn c3(): i64 {
    #ifdef CYRIUS_TARGET_MACOS
    return 0 - 78;
    #endif
    return 0 - 38;
}
# C4: the default arm after a macOS arm whose return is CONDITIONAL — reached, flagged
fn c4(x): i64 {
    #ifdef CYRIUS_TARGET_MACOS
    if (x == 1) { return 0 - 78; }
    #endif
    return 0 - 38;
}
# C5: an #ifndef of another target, no macOS arm ahead (sys_sched_kicks' shape) — flagged
fn c5(): i64 {
    #ifndef CYRIUS_TARGET_AGNOS
    return 0 - 38;
    #endif
}
# C6: the #else of a Linux arm — flagged
fn c6(): i64 {
    #ifdef CYRIUS_TARGET_LINUX
    return 1;
    #else
    return 0 - 38;
    #endif
}
# C7: an arch-only arm — flagged on arm64-macOS only
fn c7(): i64 {
    #ifdef CYRIUS_ARCH_AARCH64
    return 0 - 38;
    #endif
    return 0;
}
# C9: a comparison against Darwin's ENOTSOCK is not a decline; a string's brace does not open a block
fn c9(r): i64 {
    var s = "{ return 0 - 38; {";
    if (r != 0 - 38) { return r; }
    return 0;
}
# C10: after c9, the brace depth is back at the fn level: a body-level return ends this fn
fn c10(): i64 {
    #ifdef CYRIUS_TARGET_MACOS
    return 0 - 78;
    #endif
    return 0 - 38;
}
EOF
# C8: a foreign peer (included only under a skipped frame) — its -38 is never compiled on a Mac
printf 'fn c8(): i64 { return 0 - 38; }\n' > "$C/lib/ctl_win.cyr"
# C11: a module a peer back-includes stays walked (its -38 under #ifndef AGNOS is flagged)
printf '#ifdef CYRIUS_TARGET_AGNOS\ninclude "lib/ctl_kid_agnos.cyr"\n#endif\nfn c11(): i64 {\n    #ifndef CYRIUS_TARGET_AGNOS\n    return 0 - 38;\n    #endif\n}\n' > "$C/lib/ctl_kid.cyr"
printf '#ifdef CYRIUS_TARGET_AGNOS\ninclude "lib/ctl_kid.cyr"\nfn c12(): i64 { return 0; }\n#endif\n' > "$C/lib/ctl_kid_agnos.cyr"
for T in x86 arm; do
    scan "$C" "$T" "$TMP/ctl.$T" || { bad "$T control: the scanner failed"; continue; }
    got=$(sed -n 's/^VIOL lib\/\(.*\)$/\1/p' "$TMP/ctl.$T" | tr '\n' ' ')
    if [ "$T" = x86 ]; then want="ctl.cyr:8 ctl.cyr:31 ctl.cyr:36 ctl.cyr:44 ctl_kid.cyr:6 "
    else want="ctl.cyr:8 ctl.cyr:31 ctl.cyr:36 ctl.cyr:44 ctl.cyr:50 ctl_kid.cyr:6 "; fi
    if [ "$got" != "$want" ]; then
        bad "$T control: flagged '$got', want '$want'"
        echo "      (C1 macOS -38, C4 a default arm after a conditional macOS return, C5 an #ifndef-AGNOS arm, C6 an #else of a Linux arm, C7 an aarch64-only arm, C11 a back-included module; never C2 / C3 / C8 / C9 / C10)"
    fi
    grep -q '^UNBAL' "$TMP/ctl.$T" && bad "$T control: unbalanced braces: $(grep '^UNBAL' "$TMP/ctl.$T" | tr '\n' ' ')"
    grep -q '^FILES 3 FOREIGN 1$' "$TMP/ctl.$T" || bad "$T control: want 3 files walked and 1 foreign, got '$(grep '^FILES' "$TMP/ctl.$T")'"
done
[ "$fail" = 0 ] || exit 1
echo "  controls: both Macs flag exactly the reachable -38 shapes (macOS arm, #ifndef-AGNOS, #else of Linux, a default arm after a conditional return, a back-included module; arm64 its aarch64 arm) and pass the dead ones"

# ── the census of lib/ ───────────────────────────────────────────────────────────────────────
for T in x86 arm; do
    scan "$SCAN_ROOT" "$T" "$TMP/lib.$T" || { bad "$T: the scanner failed"; continue; }
    if grep -q '^VIOL' "$TMP/lib.$T"; then
        bad "$T-macOS reaches a decline answering -38 (Linux's ENOSYS, Darwin's ENOTSOCK) — answer -78, Darwin's ENOSYS:"
        sed -n 's/^VIOL /      /p' "$TMP/lib.$T"
    fi
    grep -q '^UNBAL' "$TMP/lib.$T" && bad "$T: unbalanced braces (the fn walk cannot be trusted there): $(grep '^UNBAL' "$TMP/lib.$T" | tr '\n' ' ')"
    nf=$(sed -n 's/^FILES \([0-9]*\) FOREIGN [0-9]*$/\1/p' "$TMP/lib.$T"); nfor=$(sed -n 's/^FILES [0-9]* FOREIGN \([0-9]*\)$/\1/p' "$TMP/lib.$T")
    n38=$(sed -n 's/^R38ALL \([0-9]*\)$/\1/p' "$TMP/lib.$T"); n78=$(grep -c '^R78' "$TMP/lib.$T" || true)
    [ "${nf:-0}" -ge 90 ] || bad "$T: walked only ${nf:-0} files (want >= 90)"
    [ "${nfor:-0}" -ge 10 ] || bad "$T: judged only ${nfor:-0} files foreign (want >= 10) — the include derivation found no peers"
    [ "${n38:-0}" -ge 15 ] || bad "$T: saw only ${n38:-0} \`return 0 - 38;\` in the walked files (want >= 15) — the pattern matched nothing"
    [ "${n78:-0}" -ge 48 ] || bad "$T: reached only ${n78:-0} -78 declines (want >= 48) — the reach table excludes the macOS arms"
    nv=$(grep -c '^VIOL' "$TMP/lib.$T" || true)
    echo "  $T-macOS: $nf files walked ($nfor foreign), $n78 reachable declines answer -78, $nv answer -38 (of $n38 \`return 0 - 38;\` in the walked files)"
done
[ "$fail" = 0 ] || exit 1
echo "PASS: $G"
