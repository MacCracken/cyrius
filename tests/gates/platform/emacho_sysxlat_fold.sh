#!/bin/sh
# emacho_sysxlat_fold.sh — 6.7.12: x86 Mach-O folds a LITERAL syscall number's EMACHO_SYSXLAT chain
# at compile time (`_msx_fold`, XLAT-1), keeps only the fork / pipe fixup half that number can need,
# and sends a RUN-TIME number through one shared stub per arity class (`_msx_stub_site` /
# `EMACHO_SYSX_STUBS`, XLAT-2). The x86 twin of esysxlat_fold.sh (aarch64, 6.6.18).
#
# Before 6.7.12 every x86 Mach-O `syscall()` site carried `push rax`, the whole 92-row chain, the
# tail and the run-time fork / pipe fixup inline: ~1.26 KB a site, 733 copies in the x86-macOS
# compiler (2,883,584 B; ~32 %). The fold replays EMACHO_SYSXLAT in a query mode (`_msx_qon == 2`)
# with the literal, so the answer comes from the SAME rows the emitter writes — no second table.
#
#   axis 1  THE FOLD IS THE TABLE (fails on the old code): every EMACHO_SYSXLAT row's number, issued
#           as a literal at argc 3, leaves exactly `mov rax, <its classed number>` before its
#           syscall; pipe 22 at argc 1 (the row is argc >= 2 only, _msx_short) and an unrouted 4000
#           leave `mov rax, 0x200FFFF` (the tail's nosys); EEXIT's pre-classed 0x2000001 leaves no
#           mov at all. The expected list is read from the emitter source. (A literal >= 0x10000 —
#           e.g. a pre-classed 0x2000014 — is not a compile-time number to the parser, whose constant
#           fold stops at 16 bits, so it takes the run-time path; the stub leaves it as it is.)
#   axis 2  NO CHAIN AT A LITERAL SITE (fails on the old code): that all-literal probe carries ZERO
#           chain heads, ZERO tails and ZERO `pop r11` (the run-time fixup); fork 57 carries only the
#           fork half and pipe 22 (argc 3) only the pipe half, right after their `jnc; neg`, with no
#           pop / cmp r11; every other site neither.
#   axis 3  XLAT-2 (fails on the old code): the same numbers through a run-time `var` share TWO
#           chains, one per arity class — 3 argc-1 sites call one stub, the argc-3 sites the other,
#           and only the argc >= 2 stub holds the pipe row. Each stub is the push-free chain, the
#           tail and `ret`; each site keeps `push rax` before its call and the full run-time fixup
#           after its syscall. A literal site emitted BEFORE them must not leak its number into them.
#   axis 4  x86 MOVES CODE AFTER EMITTING IT, so a site is patched through the disp32 registry, not
#           at its emission offset: a variable site after a register-allocated loop (the per-fn NOP
#           compaction) and tests/tcyr/crossos/syscall_number_nonliteral.tcyr under CYRIUS_IR=3
#           (wp_compact, which must report reclaimed bytes) still call a stub head from every site.
#   axis 5  every x86 driver (main.cyr, main_x86_macho.cyr, main_win.cyr) calls EMACHO_SYSX_STUBS
#           between EEXIT and FIXUP; x86 FIXUP asserts the site list drained, and a main.cyr mutant
#           WITHOUT the call is refused at FIXUP instead of shipping `call .` (unbounded recursion).
#   axis 6  CYRIUS_IR=1 (record AND emit) builds the twin probe byte-identical to the plain build,
#           so an IR-recorded syscall emits what the direct path emits.
#   axis 7  the x86-macOS compiler itself (CYRIUS_MACHO=1 < src/main_x86_macho.cyr) carries at most
#           one chain per class (was 733) — the fold reaches the real build, not just the probes.
# The semantics are Darwin's, so the behaviour half runs on ach in the release gate's cross-OS leg:
# tests/tcyr/crossos/{syscall_number_nonliteral, sys_pipe_every_target, darwin_short_arity_sigsys,
# darwin_unrouted_syscall_faults, fork_refused_stays_negative}.tcyr pair each literal with its
# run-time twin.
#
# MUTATION LEDGER (measured 6.7.12, outside the gate):
#   (a) bypass the fold (`_msx_syscall` treats every lit as -1)        -> axis 1 FAILS (every site a stub
#                                                                          call, no mov) and axis 2 (2 heads)
#   (b) `_msx_fq` ignores `_msx_short`                                  -> axis 1 FAILS: syscall(22) at argc 1
#                                                                          folds to 0x200002A (pipe)
#   (c) the literal site keeps the full run-time fixup (no elision)     -> axis 1 FAILS (an R after every
#                                                                          literal site; axis 2 would see the
#                                                                          pop r11s)
#   (d) per-site inline chains for run-time numbers (XLAT-2 reverted)   -> axis 3 FAILS (one chain a site)
#   (e) EEXIT leaves `_msx_lit` at -1 (its exit takes the stub)         -> axis 1 FAILS (EEXIT's site
#                                                                          decodes as a stub call) and axis 2
#                                                                          (a chain in an all-literal probe)
#   (f) patch at the EMITTED offset (no registry)                        -> axis 4 FAILS: the register-
#                                                                          allocated probe is refused ("no
#                                                                          longer its call placeholder")
#   (g) drop `_msx_stubs_drained()` from x86 FIXUP                       -> axis 5 FAILS (and without its
#                                                                          source check the no-stub mutant
#                                                                          compiles, rc 0)
#   Each was measured with a mutant compiler built from a mutated copy of the tree (the gate run
#   from that copy). The slot-open 6.7.12 compiler (no fold) fails axis 1.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
fail() { echo "FAIL emacho_sysxlat_fold: $1" >&2; exit 1; }
[ -x "$CC" ] || fail "$CC missing"
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL emacho_sysxlat_fold: mktemp -d"; exit 1; }
trap 'rm -rf "$T"' EXIT
EMIT="$ROOT/src/backend/x86/emit.cyr"

# x86 Mach-O compile from $ROOT: _mo <src> <out> [env...]
_mo() { _s=$1; _o=$2; shift 2; (cd "$ROOT" && env CYRIUS_MACHO=1 "$@" "$CC" < "$_s" > "$_o" 2> "$_o.err"); }
# the bytes of a file as one line of " xx" pairs (a pattern can only match on a byte boundary)
_hex() { od -An -v -tx1 "$1" | tr -s ' \n' '  '; }
_cnt() { { _hex "$1" | grep -o " $2" || true; } | wc -l | tr -d ' '; }
HEAD='48 83 f8 00 75 07 48 c7 c0 03 00 00 02'       # the chain's first row: cmp rax,0 / jne +7 / mov rax,0x2000003
TAIL='48 3d 00 00 00 01 73 07 48 c7 c0 ff ff 00 02' # _msx_tail: cmp rax,0x1000000 / jae +7 / mov rax,0x200FFFF
PIPEROW='48 83 f8 16 75 07 48 c7 c0 2a 00 00 02'    # the pipe row 22 -> 0x200002A
POPR11='41 5b 49 83 fb 39'                         # EMACHO_PROC_FIXUP: pop r11 / cmp r11, 57

# The per-site decoder. One line per x86 Mach-O syscall site (`0f 05 73 03 48 f7 d8`, the syscall
# and its carry-negate), in file order: "<before> <after>". <before>: the decimal imm32 of a
# `mov rax, imm32` (48 c7 c0) right before the syscall, C for a stub call (50 e8 <rel32>), else -.
# <after>: F the fork half, P the pipe half, R the run-time fixup (pop r11), else -.
# Also "HEAD <off>", "TAIL <off> <ret-follows>" and "PIPEROW <off>" lines, and "CALL <site> <target>".
_dec() {
    od -An -v -tx1 "$1" | tr -s ' \n' '\n\n' | grep -v '^$' | awk -v H="$HEAD" -v TL="$TAIL" -v PR="$PIPEROW" '
    function at(i, pat,   p, k, m) { m = split(pat, p, " "); for (k = 1; k <= m; k++) if (b[i + k - 1] != p[k]) return 0; return 1 }
    { b[n++] = $0 }
    END {
        for (i = 0; i < n; i++) {
            if (b[i] == "48") {
                if (at(i, H)) print "HEAD " i
                if (at(i, TL)) print "TAIL " i " " ((b[i + 15] == "c3") ? 1 : 0)
                if (at(i, PR)) print "PIPEROW " i
            }
            if (b[i] == "0f" && at(i, "0f 05 73 03 48 f7 d8")) {
                bf = "-"
                if (i >= 7 && at(i - 7, "48 c7 c0")) bf = strtonum("0x" b[i - 1] b[i - 2] b[i - 3] b[i - 4])
                if (i >= 6 && b[i - 6] == "50" && b[i - 5] == "e8") {
                    bf = "C"
                    rel = strtonum("0x" b[i - 1] b[i - 2] b[i - 3] b[i - 4]); if (rel >= 2147483648) rel -= 4294967296
                    print "CALL " (i - 5) " " (i + rel)
                }
                af = "-"
                if (at(i + 7, "48 85 c0 78 09 48 83 fa 01 75 03 48 31 c0")) af = "F"
                if (at(i + 7, "48 85 c0 78 08 89 07 89 57 04 48 31 c0")) af = "P"
                if (at(i + 7, "41 5b 49 83 fb 39")) af = "R"
                print "SITE " bf " " af
            }
        }
    }'
}

# ── the rows, read from the emitter: "<number> <classed decimal>", first row per number ─────────
ROWS=$(awk '/^fn EMACHO_SYSXLAT\(S\): i64 \{/{s=1} s&&/^\}/{exit} s' "$EMIT" \
    | grep -oE '_msx(32)?\(S,[[:space:]]*[0-9]+,[[:space:]]*0x[0-9A-Fa-f]+\)' \
    | sed -E 's/.*S,[[:space:]]*([0-9]+),[[:space:]]*0x([0-9A-Fa-f]+)\)/\1 \2/' \
    | awk '!seen[$1]++ { printf "%s %d\n", $1, strtonum("0x" $2) }')
NROWS=$(printf '%s\n' "$ROWS" | grep -c . || true)
[ "$NROWS" -ge 80 ] || fail "decoded only $NROWS EMACHO_SYSXLAT rows — the reader or the emitter shape moved"
printf '%s\n' "$ROWS" | awk '$1 == 22 && $2 == 33554474 {f = 1} END {exit !f}' || fail "no pipe row 22 -> 0x200002A in EMACHO_SYSXLAT"
printf '%s\n' "$ROWS" | awk '$1 == 57 && $2 == 33554434 {f = 1} END {exit !f}' || fail "no fork row 57 -> 0x2000002 in EMACHO_SYSXLAT"

# ── axis 1 + 2: the all-literal probe ────────────────────────────────────────────────────────
{
    printf 'var _fb[64];\n'
    printf '%s\n' "$ROWS" | awk '{ print "syscall(" $1 ", &_fb, 0);" }'
    printf 'syscall(22);\nsyscall(4000, 0);\n'
} > "$T/lit.cyr"
_mo "$T/lit.cyr" "$T/lit.bin" || fail "the all-literal probe did not compile: $(head -3 "$T/lit.bin.err")"
{
    printf '%s\n' "$ROWS" | awk '{ h = "-"; if ($1 == 57) h = "F"; if ($1 == 22) h = "P"; print "SITE " $2 " " h }'
    printf 'SITE 33619967 -\nSITE 33619967 -\nSITE - -\n'
} > "$T/lit.want"
_dec "$T/lit.bin" > "$T/lit.dec"
grep '^SITE ' "$T/lit.dec" > "$T/lit.got" || true
NS=$(grep -c . "$T/lit.got" || true)
[ "$NS" -ge "$NROWS" ] || fail "axis 1: only $NS syscall sites decoded for $NROWS rows — the decoder is blind"
if ! cmp -s "$T/lit.want" "$T/lit.got"; then
    diff "$T/lit.want" "$T/lit.got" | head -12 >&2
    fail "axis 1: a literal site did not fold to its EMACHO_SYSXLAT row's classed number (want < > got; 'SITE <mov rax imm32 | C stub call | -> <F fork | P pipe | R run-time fixup | ->')"
fi
echo "  axis 1: $NROWS rows + 3 controls: each literal leaves exactly its row's classed number (0x200FFFF unrouted / pipe at argc 1; nothing at EEXIT's pre-classed exit)"
for p in "$HEAD" "$TAIL" "$POPR11"; do
    c=$(_cnt "$T/lit.bin" "$p")
    [ "$c" = 0 ] || fail "axis 2: $c copies of '$p' in a probe whose syscall numbers are all literals — want 0"
done
echo "  axis 2: 0 chain heads, 0 tails, 0 run-time fixups; fork 57 / pipe 22 keep only their own half"

# ── axis 3: the run-time twin ────────────────────────────────────────────────────────────────
{
    printf 'var _fb[64];\nvar _fn = 0;\nsyscall(39);\n'
    printf '_fn = 39;\nsyscall(_fn);\n_fn = 22;\nsyscall(_fn);\n_fn = 4000;\nsyscall(_fn);\n'
    printf '%s\n' "$ROWS" | awk '{ print "_fn = " $1 ";"; print "syscall(_fn, &_fb, 0);" }'
} > "$T/var.cyr"
NV=$((NROWS + 3))
_mo "$T/var.cyr" "$T/var.bin" || fail "the run-time twin probe did not compile: $(head -3 "$T/var.bin.err")"
_dec "$T/var.bin" > "$T/var.dec"
NH=$(grep -c '^HEAD ' "$T/var.dec" || true)
NT=$(grep -c '^TAIL .* 1$' "$T/var.dec" || true)
[ "$NH" = 2 ] || fail "axis 3: $NH chain heads for $NV run-time sites at arities 1 and 3 — want 2 (one stub per class)"
[ "$NT" = 2 ] || fail "axis 3: $NT chain tails followed by ret — want 2 (each stub ends tail; ret)"
FIRST=$(awk '/^SITE /{print; exit}' "$T/var.dec")
[ "$FIRST" = "SITE 33554452 -" ] || fail "axis 3: the leading literal syscall(39) decodes as '$FIRST', want 'SITE 33554452 -'"
NC=$(grep '^SITE ' "$T/var.dec" | tail -n +2 | grep -c '^SITE C R$' || true)
[ "$NC" = "$NV" ] || fail "axis 3: $NC of $NV run-time sites are 'push rax; call <stub>' + syscall + the run-time fixup (a literal's number leaked, or a chain was inlined)"
H1=$(awk '/^HEAD /{print $2; exit}' "$T/var.dec")
H2=$(awk '/^HEAD /{n++; if (n == 2) {print $2; exit}}' "$T/var.dec")
awk -v h1="$H1" -v h2="$H2" '/^CALL /{ n++; t = $3; if (n <= 3 && t != h1) bad = 1; if (n > 3 && t != h2) bad = 1 } END { exit bad }' "$T/var.dec" \
    || fail "axis 3: a run-time site does not call its class stub (argc 1 -> the stub at $H1, argc 3 -> the stub at $H2): $(grep '^CALL ' "$T/var.dec" | head -5 | tr '\n' ' ')"
# the pipe row: only in the argc >= 2 stub (the one at H2), never in the argc-1 stub
NP=$(grep -c '^PIPEROW ' "$T/var.dec" || true)
PR=$(awk '/^PIPEROW /{print $2; exit}' "$T/var.dec")
[ "$NP" = 1 ] && [ "$PR" -gt "$H2" ] || fail "axis 3: the pipe row occurs $NP times (first at ${PR:-none}) — want once, inside the argc >= 2 stub at $H2 only"
echo "  axis 3: $NV run-time sites share 2 class stubs (3 at argc 1 -> $H1, $NROWS at argc 3 -> $H2; the pipe row only in the second), each with push rax + the run-time fixup"

# ── axis 4: code that moves after emission ──────────────────────────────────────────────────
printf '%s\n' 'var _nr = 0;' 'fn work(n): i64 {' '    var a = 0; var b = 1; var c = 2; var i = 0;' \
    '    while (i < n) { a = a + b; b = b + c; c = c + 1; i = i + 1; }' '    var r = syscall(_nr);' \
    '    var s = 0;' '    while (i > 0) { s = s + a + b + c; i = i - 1; }' '    if (s < 0) { return 0 - 1; }' '    return r;' '}' \
    '_nr = 39;' 'var p = work(10);' 'syscall(60, p);' > "$T/ra.cyr"
_mo "$T/ra.cyr" "$T/ra.bin" || fail "axis 4: the register-allocated probe did not compile: $(head -3 "$T/ra.bin.err")"
[ "$(_cnt "$T/ra.bin" '48 89 c3')" -ge 1 ] || fail "axis 4: premise: the register allocator took no local into rbx (no mov rbx, rax) — the probe no longer exercises the per-fn compaction"
_dec "$T/ra.bin" > "$T/ra.dec"
RH=$(awk '/^HEAD /{print $2; exit}' "$T/ra.dec")
RC=$(awk '/^CALL /{print $3; exit}' "$T/ra.dec")
[ -n "$RH" ] && [ "$RC" = "$RH" ] || fail "axis 4: the run-time site after a register-allocated loop calls ${RC:-nothing}, not the stub head ${RH:-none}"
_mo tests/tcyr/crossos/syscall_number_nonliteral.tcyr "$T/ir3.bin" CYRIUS_IR=3 \
    || fail "axis 4: syscall_number_nonliteral.tcyr did not compile under CYRIUS_IR=3: $(head -3 "$T/ir3.bin.err")"
WPB=$(sed -n 's/^wp-compact: \([0-9][0-9]*\) bytes reclaimed.*/\1/p' "$T/ir3.bin.err")
[ -n "$WPB" ] && [ "$WPB" -gt 0 ] || fail "axis 4: premise: wp_compact reclaimed nothing under CYRIUS_IR=3 — the probe no longer moves code after the stubs are patched"
_dec "$T/ir3.bin" > "$T/ir3.dec"
NC3=$(grep -c '^CALL ' "$T/ir3.dec" || true)
[ "$NC3" -ge 4 ] || fail "axis 4: only $NC3 stub calls in the CYRIUS_IR=3 build of syscall_number_nonliteral.tcyr — want >= 4"
awk '/^HEAD /{h[$2] = 1} /^CALL /{c[++n] = $3} END { for (i = 1; i <= n; i++) if (!(c[i] in h)) bad = 1; exit bad }' "$T/ir3.dec" \
    || fail "axis 4: under CYRIUS_IR=3 a stub call misses every stub head after wp_compact ($WPB B): $(grep '^CALL ' "$T/ir3.dec" | tr '\n' ' ')"
echo "  axis 4: after a register-allocated loop and after wp_compact ($WPB B under CYRIUS_IR=3) every run-time site still calls a stub head ($NC3 calls)"

# ── axis 5: the drivers, the drain assert, and a driver without the call ────────────────────
for d in main main_x86_macho main_win; do
    awk '/^ *EEXIT\(S\);/ {e = NR} /^EMACHO_SYSX_STUBS\(S\);/ {s = NR} /^FIXUP\(S\);/ {f = NR} END {exit !(e && s && f && e < s && s < f)}' \
        "$ROOT/src/$d.cyr" || fail "axis 5: src/$d.cyr does not call EMACHO_SYSX_STUBS(S) between EEXIT(S) and FIXUP(S)"
done
awk 'index($0, "fn FIXUP(") == 1 {s = 1} s && /_msx_stubs_drained\(\)/ {f = 1} s && /^}/ {exit} END {exit !f}' \
    "$ROOT/src/backend/x86/fixup.cyr" || fail "axis 5: x86 FIXUP does not assert the stub-site list is drained (_msx_stubs_drained)"
sed '/^EMACHO_SYSX_STUBS(S);$/d' "$ROOT/src/main.cyr" > "$T/nostub.cyr"
[ "$(wc -l < "$T/nostub.cyr")" -lt "$(wc -l < "$ROOT/src/main.cyr")" ] || fail "axis 5: could not build the no-stub driver mutant"
rc=0; (cd "$ROOT" && "$CC" < "$T/nostub.cyr" > "$T/ccm" 2> "$T/ccm.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/ccm" ] || fail "axis 5: building the no-stub driver mutant failed (rc $rc): $(head -3 "$T/ccm.err")"
chmod +x "$T/ccm"
rc=0; (cd "$ROOT" && CYRIUS_MACHO=1 "$T/ccm" < "$T/var.cyr" > "$T/nostub.bin" 2> "$T/nostub.err") || rc=$?
[ "$rc" != 0 ] && grep -q 'reached FIXUP unpatched' "$T/nostub.err" \
    || fail "axis 5: a driver without EMACHO_SYSX_STUBS compiled run-time-number Mach-O sites (rc $rc) — FIXUP must refuse, or the output recurses on 'call .'"
echo "  axis 5: 3 drivers call EMACHO_SYSX_STUBS between EEXIT and FIXUP; a driver without it is refused at FIXUP"

# ── axis 6: CYRIUS_IR=1 emits what the direct path emits ─────────────────────────────────────
_mo "$T/var.cyr" "$T/var1.bin" CYRIUS_IR=1 || fail "axis 6: the twin probe did not compile under CYRIUS_IR=1"
cmp -s "$T/var.bin" "$T/var1.bin" || fail "axis 6: CYRIUS_IR=1 (record and emit) built the twin probe differently from the plain build"
_mo "$T/lit.cyr" "$T/lit1.bin" CYRIUS_IR=1 || fail "axis 6: the literal probe did not compile under CYRIUS_IR=1"
cmp -s "$T/lit.bin" "$T/lit1.bin" || fail "axis 6: CYRIUS_IR=1 built the literal probe differently from the plain build"
echo "  axis 6: CYRIUS_IR=1 builds both probes byte-identical to the plain build"

# ── axis 7: the x86-macOS compiler ─────────────────────────────────────────────────────────
_mo src/main_x86_macho.cyr "$T/mx" || fail "axis 7: the x86-macOS compiler did not build: $(head -3 "$T/mx.err")"
MH=$(_cnt "$T/mx" "$HEAD")
MS=$(_cnt "$T/mx" '0f 05 73 03 48 f7 d8')
[ "$MS" -ge 100 ] || fail "axis 7: only $MS Mach-O syscall sites in the x86-macOS compiler — the reader is blind"
[ "$MH" -le 2 ] || fail "axis 7: the x86-macOS compiler carries $MH chain heads — want <= 2 (one shared stub per class; 733 inline before 6.7.12)"
echo "  axis 7: the x86-macOS compiler ($(wc -c < "$T/mx" | tr -d ' ') B): $MS syscall sites, $MH chains"

echo "PASS emacho_sysxlat_fold (x86 Mach-O literal syscall numbers fold to their row's classed number with only the fork / pipe half they need; run-time numbers share one stub per arity class, found through the registry after code moves; every driver emits the stubs)"
